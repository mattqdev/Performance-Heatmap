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
   - `triangles()` iterates `MeshPart`s. Where possible it uses the **real triangle count** from `meshTriangleCount()`, which loads each mesh via `AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))` and returns `#editableMesh:GetFaces()` — `pcall`-guarded, cached per `MeshId` (across runs, in `self._triCache`), each EditableMesh `:Destroy()`d immediately (they are memory-heavy). **Reality check:** `CreateEditableMeshAsync` fails with "no permission to load asset" on any mesh the user doesn't own, i.e. most Toolbox/Marketplace assets — in a public plugin the real count is unavailable for the majority of scenes. So meshes that can't be measured fall back to `meshCostEstimate()`, a crude proxy from always-readable properties (`RenderFidelity`, `CollisionFidelity`, bounding-box size); those rows are labelled `(est. …)`, never presented as a triangle count. Highlights the MeshPart itself via `createHighlightPart`.
   - Each analyzer buckets items into Ok / Medium / Big by threshold, records `{ Model = <instance>, Amount = <string>, Sort = <number>, Group = <number?> }` entries into `MediumModels`/`BigModels`, and draws semi-transparent oversized highlight `Part`s into a non-`Archivable` workspace folder (`ensureFolder`).
   - **Folder lifecycle:** `clear()` destroys the folder itself (not just its children) and resets the result tables. `detach()` / `attach()` are the panel-close/open pair: `detach()` reparents the folder to `nil` — it disappears from `Workspace`/Explorer but stays alive in `self._folder` along with the result tables, so `attach()` can restore the previous scan verbatim with no re-analysis. This is **session-only, in-memory** state by design — do not persist it via `plugin:SetSetting`. `ensureFolder()` re-attaches a detached folder rather than making a second one, and rebuilds from scratch if the user deleted it from the Explorer (a destroyed instance's `Parent` is locked, hence the `pcall`s).
   - `sortModels()` sorts descending by the entry's explicit numeric `Sort`, then by `Group` (higher first — used by `triangles()` to rank measured meshes above estimated ones, since the two aren't the same unit), then by name so the order never depends on `Workspace` traversal order. Parsing `Amount` is only a fallback for entries that don't set `Sort`; if you add an analyzer, set `Sort`.

2. **`Modules/UIService.luau`** (`UIService/init.luau`) — all panel UI logic. `new(mouse, anim, main, template, statsTemplate)` binds the header menu buttons to `fire(option)` → `onOptionSelected` callback, and caches the `HeaderBig` / `HeaderMedium` base titles. `refreshList(bigList, medList, instanceClass, colors)` re-renders the results list by cloning `template` rows (title, amount, class icon, click-to-`Selection:Set`); it assigns a **unique incrementing `LayoutOrder`** to the two section headers and every row (equal `LayoutOrder`s would leave the final order up to sibling order in the `ScrollingFrame`), and appends ` (N)` to each header's `Title`. The base title is re-derived by stripping a trailing ` (N)`, because the GUI lives in the place file and could be saved with a count already in it. `createStats(mainUI, statsTemplate, colors)` renders the live metrics panel from `Properties.luau`, binding each row to `Stats:GetPropertyChangedSignal` (tracked in a module-level `connections` table, disconnected/reconnected on each rebuild), and colours each value green/yellow/red against that row's `Good`/`Warn` budget.

3. **`Modules/Anim.luau`** — reusable TweenService hover/click/button animations applied to UI frames.

4. **`Modules/UIService/Properties.luau`** — declarative list of the `Stats` metrics to display, as `{ Name, Description, Good, Warn }` rows interleaved with `{ Divider = true, Title }` section headers. This is the single place to add/remove tracked metrics and to tune the colour thresholds (`Good`/`Warn`, lower-is-better unless the row sets `HigherIsBetter`; omit both to leave a row uncoloured). Timing metrics are in **seconds** (the engine's `*Ms` variants are the deprecated ones). The budgets are rules of thumb for a mid-range device, not engine limits — keep the framing honest, both in code comments and in the docs. `SceneDrawcallCount` / `SceneTriangleCount` live here — this is where the forum's "draw calls" request is surfaced (globally, via the Stats panel).

5. **`Modules/Version.luau`** — single source of truth for the plugin's own version (`Version.current`), plus semver `parse` / `compare` / `isNewer` helpers. **Bump `Version.current` here and `version.json` at the repo root on every release.** The version is now baked into code — the old `Version` `StringValue` instance is no longer read (delete it from the plugin in Studio).

6. **`Modules/UpdateChecker.luau`** — `check()` fetches `version.json` from `raw.githubusercontent.com/mattqdev/Performance-Heatmap/main/version.json` via `HttpService:GetAsync` (plugins may make HTTP requests regardless of the game's HttpEnabled setting), `JSONDecode`s it, and compares against `Version.current`. Fully `pcall`-guarded and returns a non-fatal `Result` table; `init.local.luau` runs it in a `task.spawn`, `warn`s on an available update, and appends "Update available" to the widget title.

### Control flow

`init.local.luau` connects `ui:onOptionSelected` so that selecting a menu option: toggles the Stats vs. List view, calls `heatmap:run(option)`, then calls `ui:refreshList(...)` passing the chosen instance class (`PointLight` / `ParticleEmitter` / `MeshPart` / `Model`, from the local `rowClass` helper) for the row icons and `heatmap.colors`. A background `task.spawn` loop rebuilds the stats panel every `0.1s`, skipped while the widget is hidden.

The toolbar button only flips `widget.Enabled`; the show/hide side effects hang off `widget:GetPropertyChangedSignal("Enabled")` — **the widget's own X button never fires the toolbar `Click`**, and closing by accident is exactly the case the restore is for. Hiding calls `heatmap:detach()`, showing calls `heatmap:attach()` and re-renders the list from the retained tables. `plugin.Unloading` stops the stats loop and calls `heatmap:clear()` so a detached folder isn't left dangling across a plugin reload.

## User-requested roadmap (from the DevForum thread)

The plugin is public and its direction is driven by feedback at https://devforum.roblox.com/t/3416936. Recurring themes to keep in mind when adding features:

- **Better performance metrics than part/mesh count.** The strongest, repeated critique (bura1414, bitsplicer, xor25th, ramdoys) is that raw part/mesh count does not predict lag — placement and density in a small space matter more. Partially addressed by `density()` and now by the per-MeshPart `triangles()` mode. ✅ triangle count shipped.
- **Draw calls metric** (NotRapidV, xor25th): the engine surfaces this via Shift+F2. `SceneDrawcallCount` / `SceneTriangleCount` are read into the Stats panel via `Properties.luau`, answering it at scene level. A per-object draw-call heatmap is not straightforward (draw calls depend on batching/materials/textures, not a single object property) — still open.
- **Honest framing.** The creator (MattQ) has acknowledged the tool is "not exactly the most precise." Keep classification claims accurate and avoid overstating that highlighted objects definitively cause lag. `triangles()` shows real counts where permissions allow and clearly labels the rest as `(est. …)` — never dress an estimate up as a measured triangle count.

### Manual steps in Studio (not in this repo)

Some changes here require a matching edit to the plugin's GUI/instances in Studio:

- **Mode buttons:** the header menu auto-wires every `Frame` under `mainUI.Body.Head` (its `Name` is passed straight to `heatmap:run`), so adding a mode is GUI-only once `run` handles the name. ✅ the `Triangles` frame exists. ⚠️ `Body.Head` also contains `Texture` and `Overlap` frames that `run` does **not** handle: clicking them clears the highlights and shows an empty list. Either implement those analyzers or remove the frames.
- **Header title width:** `List.HeaderBig.Title` / `HeaderMedium.Title` are `TextScaled` and only ~0.44 of the header wide, so the ` (N)` suffix added by `refreshList` shrinks the text. Widen `Title.Size.X` to ~0.62 and narrow the sibling `Line` to ~0.27 to compensate (the header uses a horizontal `UIListLayout`).
- **Delete the old `Version` StringValue** from the plugin tree — the code no longer reads it.
- **Release flow:** bump `Version.current` in `Version.luau`, bump `version` in `version.json`, commit/push to `main` (so GitHub raw serves the new number), then publish the plugin.

## Conventions

- **All code — comments, identifiers, and user-facing strings — is written in English.** (Older code was partly in Italian; it has been translated. Don't reintroduce Italian.)
- The `Amount` field is a human-readable string (e.g. `"(42 Parts)"`, `"(Score: 88.50)"`); sorting relies on parsing the first number out of it, so keep a parseable leading number if you change the format.
- Classification thresholds are hard-coded inside each analyzer in `HeatmapService.luau`.
