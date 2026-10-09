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

4. **`Modules/RenderProbe.luau`** — the only thing here that **measures** rather than estimates. Reads `Stats.SceneDrawcallCount` / `SceneTriangleCount`, sets `LocalTransparencyModifier = 1` on the target's `BasePart`s, waits `SETTLE_FRAMES`, reads again; the delta is the object's real cost. `cost(parts)` yields ~9 frames and **restores on every path out**, including a failed property write — leaving a user's geometry invisible because a scan was cancelled is the one outcome it may not produce. Verified in Studio before shipping (edit mode, 1082 parts): the hide really does drop parts from the batch (58→13 draw calls, 33,080→26 triangles), the counters return exactly, `LocalTransparencyModifier` is **not serialised** so the place is never dirtied, and with nothing moving the counters are stable to the unit — a delta of 1 draw call is signal. **`CastShadow` is deliberately not touched**: it *is* serialised (toggling it dirties the place) and the shadow counters were still drifting several frames after a change, so shadow cost is left unmeasured rather than guessed. A delta of zero means "outside the frustum, or batched with others" — it is a fact about the current camera, and must never be rendered as "0 draw calls".

5. **`Modules/Analyzers/`** — one module per mode, registered in `Analyzers/init.luau` (`list` + `byId`). Each exports `{ id, label, usesIndex?, scan(index, budget, context) -> findings, summary? }` where `id` **must equal** the `Frame`'s `Name` under `mainUI.Body.Head` (the menu wires frames by name, and `run` dispatches off `byId`). A finding is `{ Instance, Amount, Sort, Bucket, Group? }`, `Bucket` ∈ `"Ok" | "Medium" | "Big"`. `Sort` is the numeric severity and is **required**; `Group` (higher first) separates metrics that can't be ranked against each other — only `Triangles` uses it, to keep measured counts above estimates. The optional second return is a one-off `summary` string that `init.local.luau` `warn`s after the scan. `usesIndex = false` skips the `WorkspaceIndex` build entirely (only `Measure`, which works on a selection). `context.previous` carries the last completed scan's `Big` / `Medium` tables.

   - `Measure` — **the real numbers.** Measures the current `Selection` via `RenderProbe`, falling back to the previous scan's worst offenders when nothing is selected; capped at `MAX_TARGETS` (50) because each costs a few frames. This is a true triangle count on meshes `CreateEditableMeshAsync` refuses to open — i.e. most of the Toolbox — and the first per-object draw call figure the plugin has had. Draw calls and triangles are different units, so `DRAWCALL_IN_TRIANGLES` trades them off *for row ordering only*; it is never displayed and is not a cost model. Zero-cost targets are labelled `(not drawn from this camera)` and bucketed `Ok`, with the count called out in the summary.
   - `Draws` — static draw-call estimate for the whole place. Groups renderables by `geometryKey|surfaceKey|passKey`; the number of groups ≈ the draw call count, and the list is the tail (batches used once). Skips `Terrain` (drawn by its own system) and fully transparent parts; `Decal`/`Texture` are separate surface quads and get their own batches. `UnionOperation.AssetId` **is not a readable member**, so each union is counted as its own batch — stated in the mode. The summary prints the estimate next to the live `SceneDrawcallCount` **with the error visible**, and says the two cover different scopes (whole place vs. what the camera sees).
   - `Count` — parts per `Model` (direct). The bluntest mode, kept because it's still the fastest way to find a model built out of 400 wedges; the forum is right that it doesn't predict frame time.
   - `Density` — parts per 1,000 studs³ of `Model:GetBoundingBox()`. The old formula was `count / Σ(part volumes)`, i.e. the inverse of the average part size, which ranked scattered small parts as "dense" and stacked large ones as "sparse" — backwards for the thing the mode exists to find.
   - `Triangles` — real triangle count via `AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))`, `pcall`-guarded, cached per `MeshId` in a **module-level** table (survives across runs; each `EditableMesh` is `:Destroy()`d immediately, they're memory-heavy). **Reality check:** that API fails with "no permission to load asset" on any mesh the user doesn't own, i.e. most Toolbox/Marketplace assets — in a public plugin the real count is unavailable for the majority of scenes. Unmeasurable meshes fall back to a proxy from always-readable properties (`RenderFidelity`, `CollisionFidelity`, size), labelled `(est. …)` and **never** presented as a triangle count.
   - `Texture` — distinct image assets per object (`Decal`/`Texture`, `SurfaceAppearance` maps, `MeshPart.TextureID`/`TextureContent`, `ParticleEmitter.Texture`), weighted towards images used exactly once in the place. Ranks *memory pressure*: the engine exposes no resolution, so these are asset counts, not megabytes — say so.
   - `Overlap` — world-space AABBs bucketed into a 16-stud grid, pairwise inside each cell, scoring how much of a part sits inside another. Finds buried geometry (stored, replicated, often drawn, never seen) and z-fighting candidates. Boxes are axis-aligned so the percentage is an upper bound for rotated parts. Guarded by `MAX_SPAN` (skips baseplate-sized slabs) and `MAX_PAIRS`.
   - `Lights` — `Brightness × Range`, **×3 when `Shadows`** (a shadow-casting light re-draws everything in range into a shadow map; it dwarfs a few studs of extra range). Disabled lights are skipped, not reported green.
   - `Particles` — `simultaneous × size² × opacity`, where `simultaneous = Rate × avg Lifetime`. The old score multiplied by `Brightness`, which isn't what hurts: particles are transparent quads, so cost is screen coverage and overdraw. Disabled and fully transparent emitters are skipped.

6. **`Modules/HeatmapService.luau`** — the run lifecycle only; no analysis lives here. `run(option, onProgress)` **yields**: it cancels any scan in flight, bumps a `_token`, builds the index, calls the analyzer, buckets findings into `BigModels` / `MediumModels`, sorts, and paints. It returns `false` when cancelled or superseded — a stale scan must never write results, hence the token check after every await point. `sortModels()` orders by `Group` (higher first), then `Sort`, then name, so the order never depends on `Workspace` traversal order. `_paint()` draws **only** Big and Medium: the old code created a highlight for every object that was fine, which on a large place meant tens of thousands of instances spent saying "nothing to see here".

7. **`Modules/UIService.luau`** (`UIService/init.luau`) — all panel UI logic. `refreshList(bigList, medList, colors)` clones `template` rows and assigns a **unique incrementing `LayoutOrder`** to the headers and every row (equal `LayoutOrder`s would leave the final order up to sibling order in the `ScrollingFrame`). Row icons come from each row's own `ClassName`, so modes reporting mixed classes (`Overlap`, `Texture`) show the right icon per row. Section titles are set from `HEADER_TITLES` **in code** ("HIGH COST" / "MODERATE"), not read from the place file — the old "BIG/MEDIUM ELEMENTS" described object size, which is not what the buckets mean. `ensureStats()` builds the metrics rows **once** and `updateStats()` then only writes two properties per row; the old `createStats` destroyed and rebuilt all ~22 rows and rebound all ~22 property signals every 0.1s. `_layoutModeBar()` lays out the mode buttons in code: `Body.Head` in the place file is a fixed 60px non-wrapping row, which with ten modes overflowed (and couldn't be clicked) on any panel under ~650px. Buttons now shrink to fit (60 → 30px), then wrap into balanced `Row` frames, and `List` / `Stats` take the remaining height. Button `Size` is never touched — `Anim.hover` tweens relative to the size it captured — so a button's size is set via its row's height.

8. **`Modules/UIService/Properties.luau`** — declarative list of the `Stats` metrics, as `{ Name, Description, Good, Warn }` rows interleaved with `{ Divider = true, Title }` headers. Single place to add/remove metrics and tune thresholds (lower-is-better unless the row sets `HigherIsBetter`; omit both to leave a row uncoloured). Timing metrics are in **seconds** (the engine's `*Ms` variants are the deprecated ones). `PlayOnly = true` marks rows that describe the **Studio process**, not the place — in edit mode `FrameTime`, `RenderGPUFrameTime` and the bandwidth rows are measuring the editor viewport, selection gizmos and dock widgets, so the panel greys them out and labels them instead of colouring them against a budget they have no relationship to. Budgets are rules of thumb for a mid-range device, not engine limits — keep the framing honest, in code and docs.

   - `InstanceCount` is deliberately **uncoloured**: it counts the whole process (Studio UI, CoreGui, every plugin), so an empty baseplate reads ~49k. `PlaceInstances` (`Source = "Place"`) is the place's own share, from **`Modules/PlaceCounter.luau`** — one `GetDescendants` per content service, then kept current via `DescendantAdded`/`Removing`; CoreGui (where our adornments live) is not counted.

9. **`Modules/Anim.luau`** — reusable TweenService hover/click/button animations applied to UI frames.

10. **`Modules/Version.luau`** — single source of truth for the plugin's own version (`Version.current`), plus semver `parse` / `compare` / `isNewer` helpers. **Bump `Version.current` here and `version.json` at the repo root on every release.** The version is baked into code — the old `Version` `StringValue` instance is no longer read (delete it from the plugin in Studio).

11. **`Modules/UpdateChecker.luau`** — `check()` fetches `version.json` from `raw.githubusercontent.com/mattqdev/Performance-Heatmap/main/version.json` via `HttpService:GetAsync` (plugins may make HTTP requests regardless of the game's HttpEnabled setting), `JSONDecode`s it, and compares against `Version.current`. Fully `pcall`-guarded and returns a non-fatal `Result` table; `init.local.luau` runs it in a `task.spawn` and folds the notice into `idleTitle` — **edit mode only** (`RunService:IsEdit()`): plugins are reloaded in every playtest DataModel, and on the client `HttpService` throws, which used to print a warning on every Play.

### Control flow

`init.local.luau` connects `ui:onOptionSelected` so that selecting a menu option toggles the Stats vs. List view, then (for any mode but `Stats`) calls `heatmap:run(option, onProgress)` and, **only if it returns true**, calls `ui:refreshList(...)` and `warn`s the analyzer's summary. A superseded scan returns `false` and must render nothing — a newer scan is already repainting behind it.

Progress goes to `widget.Title` via `setStatus`, because the title is the only piece of panel chrome that lives in code rather than in the place file. `idleTitle` holds the base title plus any update notice; `setStatus(nil)` restores it.

A background `task.spawn` loop calls `ui:ensureStats()` + `ui:updateStats()` every `0.1s`, skipped while the widget is hidden or the list view is showing.

The toolbar button only flips `widget.Enabled`; the show/hide side effects hang off `widget:GetPropertyChangedSignal("Enabled")` — **the widget's own X button never fires the toolbar `Click`**, and closing by accident is exactly the case the restore is for. Hiding calls `heatmap:setVisible(false)`, showing calls `setVisible(true)` and re-renders the list from the retained tables. `plugin.Unloading` stops the stats loop and calls `heatmap:clear()`, which also cancels any scan still in flight.

## User-requested roadmap (from the DevForum thread)

The plugin is public and its direction is driven by feedback at https://devforum.roblox.com/t/3416936. Recurring themes to keep in mind when adding features:

- **Better performance metrics than part/mesh count.** The strongest, repeated critique (bura1414, bitsplicer, xor25th, ramdoys) is that raw part/mesh count does not predict lag — placement and density in a small space matter more. ✅ `Triangles`, `Texture` and `Overlap` shipped; `Density` now measures actual packing. `Count` stays as the blunt instrument it is.
- **Draw calls metric** (NotRapidV, xor25th): the engine surfaces this via Shift+F2. ✅ answered three ways now — `SceneDrawcallCount` / `SceneTriangleCount` in the Stats panel at scene level, `Draws` as a static whole-place estimate with its error shown, and `Measure` as a real per-object figure from the engine's counters.
- **Honest framing.** The creator (MattQ) has acknowledged the tool is "not exactly the most precise." Keep classification claims accurate and avoid overstating that highlighted objects definitively cause lag. Established practice: `Triangles` labels unmeasurable meshes `(est. …)`; `Texture` says it ranks asset counts, not megabytes; `Overlap` says its percentages are an upper bound for rotated parts; `Draws` prints its estimate next to the engine's own count; `Measure` says "not drawn from this camera" rather than "0 draw calls"; `PlayOnly` Stats rows say they're measuring Studio. **Never dress a heuristic up as a measurement — and now that one mode really does measure, never let the others borrow its credibility.**

### Planned next

**`ROADMAP.md` at the repo root is the single source of truth for unbuilt work** — what's next, why, in what order, and what has been ruled out. Read it before proposing a feature, and update it when direction changes rather than restating plans here.

The short version: v1.7 shipped `Measure` and `Draws`, so the "real numbers" block is done apart from the texture-memory investigation. Next is v1.8 — one-click, undoable fixes via `ChangeHistoryService`, then a performance score built on the measurements rather than on stacked heuristics.

### Manual steps in Studio (not in this repo)

Some changes here require a matching edit to the plugin's GUI/instances in Studio:

- **Mode buttons:** the header menu auto-wires every `Frame` under `mainUI.Body.Head` (its `Name` is passed straight to `heatmap:run`), so adding a mode is a module in `Analyzers/` plus a `Frame` of the same name. ⚠️ **v1.7 needs two new frames: `Measure` and `Draws`.** Duplicate an existing mode frame twice, rename each to exactly those names (the `Name` is the dispatch key — the label the user reads comes from whatever `TextLabel` the frame already has), and keep the `Click` `GuiButton` child, which is what `UIService.new` connects. Without the frames the analyzers are registered but unreachable.
- **New script tree:** `Modules/` gained `Budget`, `Highlighter`, `WorkspaceIndex`, `RenderProbe`, `Format` and an `Analyzers/` folder (`init.luau` + nine modules, `Measure` and `Draws` new in v1.7). Studio's Script Sync creates these from disk; confirm they landed under `Modules` and that `Analyzers` is a folder with `init.luau` inside, or the `require`s in `Analyzers/init.luau` will fail.
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
- **The place is never dirtied.** `Measure` is the only code that writes to a user's instances, and it may only write **non-serialised** properties (`LocalTransparencyModifier`), must restore them on every path out including cancellation and failed writes, and must never touch a serialised one — `CastShadow` was dropped from the design for exactly this reason. If a future feature needs a serialised write, it goes through `ChangeHistoryService` and an explicit user action, per the v1.8 plan.

## Verifying a change

There's no test runner, but the source does compile-check. `luau-compile` isn't in the repo's toolchain; fetch it into a scratch dir when you need it:

```sh
curl -sSL -o luau.zip https://github.com/luau-lang/luau/releases/latest/download/luau-macos.zip && unzip -o -q luau.zip
for f in $(find Main -name '*.luau'); do ./luau-compile --null "$f" || echo "FAILED $f"; done
```

That catches syntax errors only. Behaviour still has to be exercised by hand in Studio: run every mode against a real scene, check the widget title shows progress, click a second mode mid-scan to confirm the first is cancelled and doesn't render, and confirm `Workspace` is untouched afterwards.

For anything touching `RenderProbe` or `Measure`, add these:

- **cancel mid-measurement** (click another mode while "Measuring" is in the title) and confirm nothing in the scene is left invisible — this is the failure mode that matters most;
- **the place must not go dirty**: measure a selection, then check the title bar has no unsaved-changes marker and Ctrl+Z has nothing new to undo;
- **point the camera away from the selection and measure again** — every row should read "not drawn from this camera", never "0 draw calls";
- for `Draws`, compare the summary's estimate against the `SceneDrawcallCount` it prints beside it, with the camera framing the whole place so the two are actually comparable.

The Roblox Studio MCP's `execute_luau` is a good way to check a measurement hypothesis against a real scene before writing it into the plugin, which is how the v1.7 design was settled (see `ROADMAP.md`). Ask before using it — CLAUDE.md pre-authorises only the Chrome MCP, and only for reading the plugin's GUI tree.
