# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **Roblox Studio plugin** ("Performance Heatmap") written in Luau. It scans `Workspace` and highlights Models / lights / particle emitters that are likely performance offenders, and shows a live panel of `Stats` service metrics. Only the script source (`.luau`) is version-controlled — the plugin's GUI instances (`MainUI`, `BG`, `Template`, `Stat`, `Divider`, and the `Version` value) live inside the Roblox place/plugin file and are referenced at runtime via `script:WaitForChild(...)`.

- **Published plugin:** https://create.roblox.com/store/asset/89564204038561
- **DevForum thread (user feedback / feature requests):** https://devforum.roblox.com/t/3416936 — the roadmap is driven by requests here (see "User-requested roadmap" below).
- **`ROADMAP.md`** — the source of truth for unbuilt work: what's next, why, in what order, and what has been ruled out. Read it before proposing a feature; update it when direction changes.

## Build / test / run

There is **no build, test, or lint tooling in the repo** — no `*.project.json`, no `selene`/`stylua` config, no CI. `rojo` and `wally` are installed globally via rokit, but nothing here consumes them. Development happens inside Roblox Studio:

- The `.luau` files are synced into the plugin's GUI/script tree using **Roblox Studio's native Script Sync** (not Rojo). Editing a file here updates the corresponding script in Studio.
- The naming still mirrors the Rojo convention: `init.luau` = a folder's module (`UIService/init.luau` → the `UIService` module), `init.local.luau` = the entry-point `LocalScript`.
- Test manually by toggling the toolbar button in Studio and exercising each menu option against a scene.

Do not invent build/test commands; if you add tooling, wire it up explicitly.

## Inspecting the plugin's GUI tree

The GUI instances (`MainUI`, `Template`, `Stat`, `Divider`, `BG`, `Version`) are **not** in this repo. To see the actual instance tree / properties, use the Chrome MCP against the place in Studio **only for reading the plugin tree** — the user has pre-authorized that specific use. For any other MCP use, ask the user first, and use it sparingly.

## Architecture

Entry point is `Main/init.local.luau` (the plugin `LocalScript`). It owns all Studio-plugin API calls and wires the modules together. The analysis pipeline is: **one traversal → shared index → one analyzer → buckets → adornments.**

1. **`Modules/WorkspaceIndex.luau`** — `build(budget)` walks `Workspace:GetDescendants()` **once** and returns an index every analyzer reads: `parts`, `meshParts`, `lights`, `emitters`, `models`, `textured` / `textureUsage` / `uniqueTextures`. Returns `nil` if the budget was cancelled mid-walk. Two things it fixes by construction: analyzers no longer re-traverse per mode (the Model modes used to call `GetDescendants()` again per Model — quadratic on nested rigs), and each part is attributed to its **nearest** `Model` ancestor (`record.direct`) with the inclusive figure kept only for display (`record.total`) — previously a part counted for every `Model` ancestor, so the map container always won and drowned out everything else.

2. **`Modules/Budget.luau`** — cooperative time-slicing and cancellation. Every analyzer loop calls `budget:step()` per item; when the ~8ms slice is spent it reports progress and yields a frame. `step()` returns `false` once cancelled, which is the caller's cue to `return nil` immediately. `setPhase(label, total)` names the current phase. **Any loop you add over place-sized data must step.**

3. **`Modules/Highlighter.luau`** — draws `BoxHandleAdornment`s into a folder under **`CoreGui`**, never into `Workspace`. This is deliberate and load-bearing: the old approach cloned an oversized transparent `Part` per highlighted `BasePart`, which doubled the instance count on large places, **inflated the very `Stats` the plugin displays**, sat on top of the real objects so they couldn't be clicked, and went stale when anything moved. Adornments have none of those problems and follow their `Adornee`. A `Model` gets one box around its bounding box (`Adornee` is the `Model` itself — `Model` is a `PVInstance` — so the adornment `CFrame` is relative to the model's pivot); a light or emitter gets a box on its nearest `BasePart` ancestor. Capped at 150 (`Highlighter.max`): a viewport painted entirely red tells you nothing, and the list stays complete. `setVisible(bool)` is the panel-close/open pair — it just unparents the folder, keeping the adornments and result tables alive so re-opening restores the previous scan with no re-analysis. Session-only, in-memory state by design — **do not persist it via `plugin:SetSetting`.**

4. **`Modules/Analyzers/`** — one module per mode, registered in `Analyzers/init.luau` (`list` + `byId`). Each exports `{ id, label, scan(index, budget) -> findings, summary? }` where `id` **must equal** the `Frame`'s `Name` under `mainUI.Body.Head` (the menu wires frames by name, and `run` dispatches off `byId`). A finding is `{ Instance, Amount, Sort, Bucket, Group? }`, `Bucket` ∈ `"Ok" | "Medium" | "Big"`. `Sort` is the numeric severity and is **required**; `Group` (higher first) separates metrics that can't be ranked against each other — only `Triangles` uses it, to keep measured counts above estimates. The optional second return is a one-off `summary` string that `init.local.luau` `warn`s after the scan.

   - `Count` — parts per `Model` (direct). The bluntest mode, kept because it's still the fastest way to find a model built out of 400 wedges; the forum is right that it doesn't predict frame time.
   - `Density` — parts per 1,000 studs³ of `Model:GetBoundingBox()`. The old formula was `count / Σ(part volumes)`, i.e. the inverse of the average part size, which ranked scattered small parts as "dense" and stacked large ones as "sparse" — backwards for the thing the mode exists to find.
   - `Triangles` — real triangle count via `AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))`, `pcall`-guarded, cached per `MeshId` in a **module-level** table (survives across runs; each `EditableMesh` is `:Destroy()`d immediately, they're memory-heavy). **Reality check:** that API fails with "no permission to load asset" on any mesh the user doesn't own, i.e. most Toolbox/Marketplace assets — in a public plugin the real count is unavailable for the majority of scenes. Unmeasurable meshes fall back to a proxy from always-readable properties (`RenderFidelity`, `CollisionFidelity`, size), labelled `(est. …)` and **never** presented as a triangle count.
   - `Texture` — distinct image assets per object (`Decal`/`Texture`, `SurfaceAppearance` maps, `MeshPart.TextureID`/`TextureContent`, `ParticleEmitter.Texture`), weighted towards images used exactly once in the place. Ranks *memory pressure*: the engine exposes no resolution, so these are asset counts, not megabytes — say so.
   - `Overlap` — world-space AABBs bucketed into a 16-stud grid, pairwise inside each cell, scoring how much of a part sits inside another. Finds buried geometry (stored, replicated, often drawn, never seen) and z-fighting candidates. Boxes are axis-aligned so the percentage is an upper bound for rotated parts. Guarded by `MAX_SPAN` (skips baseplate-sized slabs) and `MAX_PAIRS`.
   - `Lights` — `Brightness × Range`, **×3 when `Shadows`** (a shadow-casting light re-draws everything in range into a shadow map; it dwarfs a few studs of extra range). Disabled lights are skipped, not reported green.
   - `Particles` — `simultaneous × size² × opacity`, where `simultaneous = Rate × avg Lifetime`. The old score multiplied by `Brightness`, which isn't what hurts: particles are transparent quads, so cost is screen coverage and overdraw. Disabled and fully transparent emitters are skipped.

5. **`Modules/HeatmapService.luau`** — the run lifecycle only; no analysis lives here. `run(option, onProgress)` **yields**: it cancels any scan in flight, bumps a `_token`, builds the index, calls the analyzer, buckets findings into `BigModels` / `MediumModels`, sorts, and paints. It returns `false` when cancelled or superseded — a stale scan must never write results, hence the token check after every await point. `sortModels()` orders by `Group` (higher first), then `Sort`, then name, so the order never depends on `Workspace` traversal order. `_paint()` draws **only** Big and Medium: the old code created a highlight for every object that was fine, which on a large place meant tens of thousands of instances spent saying "nothing to see here".

6. **`Modules/UIService.luau`** (`UIService/init.luau`) — all panel UI logic. `refreshList(bigList, medList, colors)` clones `template` rows and assigns a **unique incrementing `LayoutOrder`** to the headers and every row (equal `LayoutOrder`s would leave the final order up to sibling order in the `ScrollingFrame`). Row icons come from each row's own `ClassName`, so modes reporting mixed classes (`Overlap`, `Texture`) show the right icon per row. Section titles are set from `HEADER_TITLES` **in code** ("HIGH COST" / "MODERATE"), not read from the place file — the old "BIG/MEDIUM ELEMENTS" described object size, which is not what the buckets mean. `ensureStats()` builds the metrics rows **once** and `updateStats()` then only writes two properties per row; the old `createStats` destroyed and rebuilt all ~22 rows and rebound all ~22 property signals every 0.1s.

7. **`Modules/UIService/Properties.luau`** — declarative list of the `Stats` metrics, as `{ Name, Description, Good, Warn }` rows interleaved with `{ Divider = true, Title }` headers. Single place to add/remove metrics and tune thresholds (lower-is-better unless the row sets `HigherIsBetter`; omit both to leave a row uncoloured). Timing metrics are in **seconds** (the engine's `*Ms` variants are the deprecated ones). `PlayOnly = true` marks rows that describe the **Studio process**, not the place — in edit mode `FrameTime`, `RenderGPUFrameTime` and the bandwidth rows are measuring the editor viewport, selection gizmos and dock widgets, so the panel greys them out and labels them instead of colouring them against a budget they have no relationship to. Budgets are rules of thumb for a mid-range device, not engine limits — keep the framing honest, in code and docs.

8. **`Modules/Anim.luau`** — reusable TweenService hover/click/button animations applied to UI frames.

9. **`Modules/Version.luau`** — single source of truth for the plugin's own version (`Version.current`), plus semver `parse` / `compare` / `isNewer` helpers. **Bump `Version.current` here and `version.json` at the repo root on every release.** The version is baked into code — the old `Version` `StringValue` instance is no longer read (delete it from the plugin in Studio).

10. **`Modules/UpdateChecker.luau`** — `check()` fetches `version.json` from `raw.githubusercontent.com/mattqdev/Performance-Heatmap/main/version.json` via `HttpService:GetAsync` (plugins may make HTTP requests regardless of the game's HttpEnabled setting), `JSONDecode`s it, and compares against `Version.current`. Fully `pcall`-guarded and returns a non-fatal `Result` table; `init.local.luau` runs it in a `task.spawn` and folds the notice into `idleTitle`.

### Control flow

`init.local.luau` connects `ui:onOptionSelected` so that selecting a menu option toggles the Stats vs. List view, then (for any mode but `Stats`) calls `heatmap:run(option, onProgress)` and, **only if it returns true**, calls `ui:refreshList(...)` and `warn`s the analyzer's summary. A superseded scan returns `false` and must render nothing — a newer scan is already repainting behind it.

Progress goes to `widget.Title` via `setStatus`, because the title is the only piece of panel chrome that lives in code rather than in the place file. `idleTitle` holds the base title plus any update notice; `setStatus(nil)` restores it.

A background `task.spawn` loop calls `ui:ensureStats()` + `ui:updateStats()` every `0.1s`, skipped while the widget is hidden or the list view is showing.

The toolbar button only flips `widget.Enabled`; the show/hide side effects hang off `widget:GetPropertyChangedSignal("Enabled")` — **the widget's own X button never fires the toolbar `Click`**, and closing by accident is exactly the case the restore is for. Hiding calls `heatmap:setVisible(false)`, showing calls `setVisible(true)` and re-renders the list from the retained tables. `plugin.Unloading` stops the stats loop and calls `heatmap:clear()`, which also cancels any scan still in flight.

## User-requested roadmap (from the DevForum thread)

The plugin is public and its direction is driven by feedback at https://devforum.roblox.com/t/3416936. Recurring themes to keep in mind when adding features:

- **Better performance metrics than part/mesh count.** The strongest, repeated critique (bura1414, bitsplicer, xor25th, ramdoys) is that raw part/mesh count does not predict lag — placement and density in a small space matter more. ✅ `Triangles`, `Texture` and `Overlap` shipped; `Density` now measures actual packing. `Count` stays as the blunt instrument it is.
- **Draw calls metric** (NotRapidV, xor25th): the engine surfaces this via Shift+F2. `SceneDrawcallCount` / `SceneTriangleCount` are read into the Stats panel via `Properties.luau`, answering it at scene level. A per-object draw-call heatmap is **still open** and is the next big item — see the plan below.
- **Honest framing.** The creator (MattQ) has acknowledged the tool is "not exactly the most precise." Keep classification claims accurate and avoid overstating that highlighted objects definitively cause lag. Established practice: `Triangles` labels unmeasurable meshes `(est. …)`; `Texture` says it ranks asset counts, not megabytes; `Overlap` says its percentages are an upper bound for rotated parts; `PlayOnly` Stats rows say they're measuring Studio. **Never dress a heuristic up as a measurement.**

### Planned next

**`ROADMAP.md` at the repo root is the single source of truth for unbuilt work** — what's next, why, in what order, and what has been ruled out. Read it before proposing a feature, and update it when direction changes rather than restating plans here.

The short version: `Measure Selection` (attribute real draw calls and triangles to one object by diffing `Stats` while it stops rendering — sidesteps the `CreateEditableMeshAsync` permission wall), then a static draw-call report, then one-click fixes via `ChangeHistoryService`.

### Manual steps in Studio (not in this repo)

Some changes here require a matching edit to the plugin's GUI/instances in Studio:

- **Mode buttons:** the header menu auto-wires every `Frame` under `mainUI.Body.Head` (its `Name` is passed straight to `heatmap:run`), so adding a mode is a module in `Analyzers/` plus a `Frame` of the same name. ✅ every frame now has an analyzer — `Texture` and `Overlap` are implemented, so `Body.Head` no longer ships dead buttons.
- **New script tree:** `Modules/` gained `Budget`, `Highlighter`, `WorkspaceIndex` and an `Analyzers/` folder (`init.luau` + seven modules). Studio's Script Sync creates these from disk; confirm they landed under `Modules` and that `Analyzers` is a folder with `init.luau` inside, or the `require`s in `Analyzers/init.luau` will fail.
- **Header title width:** `List.HeaderBig.Title` / `HeaderMedium.Title` are `TextScaled` and only ~0.44 of the header wide, so the ` (N)` suffix added by `refreshList` shrinks the text. Widen `Title.Size.X` to ~0.62 and narrow the sibling `Line` to ~0.27 to compensate (the header uses a horizontal `UIListLayout`). Their `Text` no longer matters — titles are set from `HEADER_TITLES` in `UIService`.
- **Delete the old `Version` StringValue** from the plugin tree — the code no longer reads it.
- **The old `PerformanceHeatmapContainer` folder** is gone: highlights are `CoreGui` adornments now. If a place was saved with one in `Workspace` from an older version, delete it by hand — nothing in the code will find it.
- **Release flow:** bump `Version.current` in `Version.luau`, bump `version` in `version.json`, commit/push to `main` (so GitHub raw serves the new number), then publish the plugin.

## Conventions

- **All code — comments, identifiers, and user-facing strings — is written in English.** (Older code was partly in Italian; it has been translated. Don't reintroduce Italian.)
- The `Amount` field is purely a display string (e.g. `"(42 parts)"`, `"(38% overlapped · 3 parts)"`) — it is **never** parsed. Ordering comes from the numeric `Sort` on each finding, which every analyzer must set.
- Classification thresholds are named constants at the top of each analyzer module, not magic numbers inline. They're rules of thumb; when you change one, change the comment that justifies it.
- Any loop over place-sized data calls `budget:step()` and bails on `false`. A scan that can freeze Studio is a bug, not a slow scan.
- Nothing the plugin creates goes into `Workspace`, and nothing it measures may include itself.

## Verifying a change

There's no test runner, but the source does compile-check. `luau-compile` isn't in the repo's toolchain; fetch it into a scratch dir when you need it:

```sh
curl -sSL -o luau.zip https://github.com/luau-lang/luau/releases/latest/download/luau-macos.zip && unzip -o -q luau.zip
for f in $(find Main -name '*.luau'); do ./luau-compile --null "$f" || echo "FAILED $f"; done
```

That catches syntax errors only. Behaviour still has to be exercised by hand in Studio: run every mode against a real scene, check the widget title shows progress, click a second mode mid-scan to confirm the first is cancelled and doesn't render, and confirm `Workspace` is untouched afterwards.
