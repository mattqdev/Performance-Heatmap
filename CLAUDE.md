# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **Roblox Studio plugin** ("Performance Heatmap") written in Luau. It scans `Workspace` and highlights Models / lights / particle emitters that are likely performance offenders, and shows a live panel of `Stats` service metrics. Only the script source (`.luau`) is version-controlled — the plugin's GUI instances (`MainUI`, `BG`, `Template`, `Stat`, `Divider`, and the `Version` value) live inside the Roblox place/plugin file and are referenced at runtime via `script:WaitForChild(...)`.

- **Published plugin:** https://create.roblox.com/store/asset/89564204038561
- **DevForum thread (user feedback / feature requests):** https://devforum.roblox.com/t/3416936 — the roadmap is driven by requests here (see "User-requested roadmap" below).

## Build / test / run

There is **no build, test, or lint tooling in the repo** — no `*.project.json`, no `selene`/`stylua` config, no CI. `rojo` and `wally` are installed globally via rokit, but nothing here consumes them. Development happens inside Roblox Studio:

- The `.luau` files are synced into the plugin's GUI/script tree using **Roblox Studio's native Script Sync** (not Rojo). Editing a file here updates the corresponding script in Studio.
- The naming still mirrors the Rojo convention: `init.luau` = a folder's module (`UIService/init.luau` → the `UIService` module), `init.local.luau` = the entry-point `LocalScript`.
- Test manually by toggling the toolbar button in Studio and exercising each menu option against a scene.

Do not invent build/test commands; if you add tooling, wire it up explicitly.

## Inspecting the plugin's GUI tree

The GUI instances (`MainUI`, `Template`, `Stat`, `Divider`, `BG`, `Version`) are **not** in this repo. To see the actual instance tree / properties, use the Chrome MCP against the place in Studio **only for reading the plugin tree** — the user has pre-authorized that specific use. For any other MCP use, ask the user first, and use it sparingly.

## Architecture

Entry point is `Main/init.local.luau` (the plugin `LocalScript`). It owns all Studio-plugin API calls and wires the modules together:

1. **`Modules/HeatmapService.luau`** — pure analysis + highlighting. `new(containerName)` creates an instance holding `BigModels` / `MediumModels` result tables and a `colors` map (Big=red, Medium=yellow, Ok=green). `run(option)` clears prior state then dispatches to one analyzer:
   - `density()` / `count()` iterate `Model`s and classify by part density or part count.
   - `lights()` / `particles()` iterate light and `ParticleEmitter` instances and classify by a computed score.
   - `triangles()` iterates `MeshPart`s. Where possible it uses the **real triangle count** from `meshTriangleCount()`, which loads each mesh via `AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))` and returns `#editableMesh:GetFaces()` — `pcall`-guarded, cached per `MeshId` (across runs, in `self._triCache`), each EditableMesh `:Destroy()`d immediately (they are memory-heavy). **Reality check:** `CreateEditableMeshAsync` fails with "no permission to load asset" on any mesh the user doesn't own, i.e. most Toolbox/Marketplace assets — in a public plugin the real count is unavailable for the majority of scenes. So meshes that can't be measured fall back to `meshCostEstimate()`, a crude proxy from always-readable properties (`RenderFidelity`, `CollisionFidelity`, bounding-box size); those rows are labelled `(stima …)`, never presented as a triangle count. Highlights the MeshPart itself via `createHighlightPart`.
   - Each analyzer buckets items into Ok / Medium / Big by threshold, records `{ Model = <instance>, Amount = <string> }` entries into `MediumModels`/`BigModels`, and draws semi-transparent oversized highlight `Part`s into a non-`Archivable` workspace folder (`ensureFolder`). `clear()` destroys that folder's children.
   - `sortModels()` sorts result tables descending by the number parsed out of the `Amount` string.

2. **`Modules/UIService.luau`** (`UIService/init.luau`) — all panel UI logic. `new(mouse, anim, main, template, statsTemplate)` binds the header menu buttons to `fire(option)` → `onOptionSelected` callback. `refreshList(bigList, medList, instanceClass, colors)` re-renders the results list by cloning `template` rows (title, amount, class icon, click-to-`Selection:Set`). `createStats(mainUI, statsTemplate)` renders the live metrics panel from `Properties.luau`, binding each row to `Stats:GetPropertyChangedSignal` (tracked in a module-level `connections` table, disconnected/reconnected on each rebuild).

3. **`Modules/Anim.luau`** — reusable TweenService hover/click/button animations applied to UI frames.

4. **`Modules/UIService/Properties.luau`** — declarative list of the `Stats` metrics to display, as `{ Name, Description }` rows interleaved with `{ Divider = true, Title }` section headers. This is the single place to add/remove tracked metrics. `SceneDrawcallCount` / `SceneTriangleCount` live here — this is where the forum's "draw calls" request is surfaced (globally, via the Stats panel).

5. **`Modules/Version.luau`** — single source of truth for the plugin's own version (`Version.current`), plus semver `parse` / `compare` / `isNewer` helpers. **Bump `Version.current` here and `version.json` at the repo root on every release.** The version is now baked into code — the old `Version` `StringValue` instance is no longer read (delete it from the plugin in Studio).

6. **`Modules/UpdateChecker.luau`** — `check()` fetches `version.json` from `raw.githubusercontent.com/mattqdev/Performance-Heatmap/main/version.json` via `HttpService:GetAsync` (plugins may make HTTP requests regardless of the game's HttpEnabled setting), `JSONDecode`s it, and compares against `Version.current`. Fully `pcall`-guarded and returns a non-fatal `Result` table; `init.local.luau` runs it in a `task.spawn`, `warn`s on an available update, and appends "Update available" to the widget title.

### Control flow

`init.local.luau` connects `ui:onOptionSelected` so that selecting a menu option: toggles the Stats vs. List view, calls `heatmap:run(option)`, then calls `ui:refreshList(...)` passing the chosen instance class (`PointLight` / `ParticleEmitter` / `Model`) for the row icons and `heatmap.colors`. A background `task.spawn` loop rebuilds the stats panel every `0.1s`. The toolbar button toggles the dock widget and calls `heatmap:clear()` when hidden.

## User-requested roadmap (from the DevForum thread)

The plugin is public and its direction is driven by feedback at https://devforum.roblox.com/t/3416936. Recurring themes to keep in mind when adding features:

- **Better performance metrics than part/mesh count.** The strongest, repeated critique (bura1414, bitsplicer, xor25th, ramdoys) is that raw part/mesh count does not predict lag — placement and density in a small space matter more. Partially addressed by `density()` and now by the per-MeshPart `triangles()` mode. ✅ triangle count shipped.
- **Draw calls metric** (NotRapidV, xor25th): the engine surfaces this via Shift+F2. `SceneDrawcallCount` / `SceneTriangleCount` are read into the Stats panel via `Properties.luau`, answering it at scene level. A per-object draw-call heatmap is not straightforward (draw calls depend on batching/materials/textures, not a single object property) — still open.
- **Honest framing.** The creator (MattQ) has acknowledged the tool is "not exactly the most precise." Keep classification claims accurate and avoid overstating that highlighted objects definitively cause lag. `triangles()` shows real counts where permissions allow and clearly labels the rest as `(stima …)` — never dress an estimate up as a measured triangle count.

### Manual steps in Studio (not in this repo)

Some changes here require a matching edit to the plugin's GUI/instances in Studio:

- **Triangles mode button:** the header menu auto-wires every `Frame` under `mainUI.Body.Head` (its `Name` is passed straight to `heatmap:run`). To expose the new mode, add a `Frame` named exactly `Triangles` (with the `Click`/`TextLabel`/etc. children the other buttons have) to `Body.Head`. No code change needed — `init.local.luau` and `HeatmapService:run` already handle `"Triangles"` and map its row icon to `MeshPart`.
- **Delete the old `Version` StringValue** from the plugin tree — the code no longer reads it.
- **Release flow:** bump `Version.current` in `Version.luau`, bump `version` in `version.json`, commit/push to `main` (so GitHub raw serves the new number), then publish the plugin.

## Conventions

- **All code — comments, identifiers, and user-facing strings — is written in English.** (Older code was partly in Italian; it has been translated. Don't reintroduce Italian.)
- The `Amount` field is a human-readable string (e.g. `"(42 Parts)"`, `"(Score: 88.50)"`); sorting relies on parsing the first number out of it, so keep a parseable leading number if you change the format.
- Classification thresholds are hard-coded inside each analyzer in `HeatmapService.luau`.
