![PerformanceHeatmap Banner](https://github.com/mattqdev/Performance-Heatmap/blob/main/assets/PerformanceHeatmapbanner.png)

<div align="center">

**[🔨 Download](https://create.roblox.com/store/asset/89564204038561) | [👑 Creator Profile](https://www.roblox.com/users/2992118050) | [🪲 Support ](https://discord.gg/ETgCMSps4c)**

</div>

# Performance Heatmap

A Roblox Studio plugin that scans your `Workspace` and highlights the objects most likely to be hurting performance, alongside a live panel of `Stats` service metrics.

**[Get it on the Creator Store](https://create.roblox.com/store/asset/89564204038561)** · **[DevForum thread](https://devforum.roblox.com/t/3416936)**

## Heatmap modes

Pick a mode from the panel header and the plugin outlines the offenders directly in the viewport — red for the worst, yellow for borderline — and lists them sorted worst-first within each section. The **HIGH COST** / **MODERATE** headers show how many items fell into each bucket. Clicking a row selects the instance.

| Mode           | What it looks at                                                                                                        |
| -------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **Measure**    | The **real** draw calls and triangles of the objects you select, read from the engine's own counters. Not an estimate.   |
| **Draw calls** | How the whole place batches, and which assets pay a full draw call for a single object.                                  |
| **Count**      | Part count per `Model`, attributed to the nearest `Model` so a map container doesn't report the whole place.             |
| **Density**    | Parts per 1,000 studs³ of the model's bounding box — how tightly a build is packed, not how big it is.                  |
| **Triangles**  | Per-`MeshPart` triangle count, measured where permissions allow and estimated otherwise.                                 |
| **Textures**   | Distinct image assets per object, weighted towards images the place uses only once.                                     |
| **Overlap**    | Parts that sit inside other parts — buried geometry and z-fighting candidates.                                          |
| **Lights**     | `PointLight` / `SpotLight` / `SurfaceLight`, scored as `Brightness × Range`, tripled when the light casts shadows.       |
| **Particles**  | `ParticleEmitter`, scored by overdraw: particles alive at once × area × opacity.                                        |

Scans run on a time budget and yield between slices, so Studio stays responsive on large places; progress appears in the widget title, and picking another mode cancels the scan in flight.

### About the Measure mode

Every other mode ranks a proxy. This one measures. The engine publishes `SceneDrawcallCount` and `SceneTriangleCount` every frame, so Measure reads them, makes the objects you selected stop rendering, reads them again, and the difference is what those objects actually cost.

Two things that gets you which nothing else does: a **real triangle count on meshes you don't own** — the ones `AssetService:CreateEditableMeshAsync` refuses to open, which on most places is nearly every Toolbox and Marketplace asset — and a **per-object draw call figure**, the most-requested number on the DevForum thread.

Select objects in the Explorer or the viewport and pick **Measure**. With nothing selected it falls back to the worst offenders of your last scan, which is the intended workflow: heuristic heatmap to narrow the field, measurement to confirm you narrowed it to the right things. It costs a few frames per object, so it's capped at 50.

**Nothing is written to your place.** Only `LocalTransparencyModifier` is touched — it isn't serialised, it doesn't dirty the file, and it's restored on every path out, including a cancelled scan. `CastShadow` is deliberately left alone: it *is* serialised, and the shadow counters take too long to settle to give an honest number, so shadow cost is reported as not measured rather than guessed at.

Read the numbers for what they are: the cost **from where your camera is standing**, **at the margin**. An object outside the view, or one that shares a batch with fifty others, measures zero — that's a fact about the shot and the batching, not a free object, and the panel says so instead of printing "0 draw calls". For the same reason these figures don't add up: objects measured one at a time total less than the same objects measured together.

### About the Draw calls mode

The whole-place counterpart to Measure. The renderer draws together objects that share geometry and surface, so Draw calls groups every renderable by what can actually be batched — mesh, texture, `SurfaceAppearance`, material variant, plus the transparency and shadow passes — and the number of groups is roughly the number of draw calls your place costs.

The total isn't the interesting part; the tail is. An asset used once pays a full draw call for one object, while a mesh reused 8,000 times pays one draw call for all of them, and the list shows you the one-offs. The summary prints the estimate next to the engine's live `SceneDrawcallCount` **so you can see the error instead of trusting it** — bearing in mind the two count different things, since the estimate covers the whole place and the engine's counter covers only what the camera can see.

It's an estimate and labelled `est.` on every row: batching depends on renderer decisions no property exposes, and copies of the same union can't be distinguished from different unions, so each union is counted separately. Use Measure when you need the exact figure for specific objects.

### About the Triangles mode

Where possible the real triangle count is read from the mesh via `AssetService:CreateEditableMeshAsync`. That API only works on assets you own, so most Toolbox and Marketplace meshes can't be measured — those fall back to a rough cost estimate from `RenderFidelity`, `CollisionFidelity` and bounding-box size, and are always labelled `(est. …)`. An estimate is never presented as a measured triangle count. Measured meshes are listed above estimated ones, since a triangle count and an estimate score aren't the same unit and can't be ranked against each other.

Select any estimated row and use **Measure** for the engine's real count — it works regardless of who owns the asset.

### About the Textures mode

Texture memory is a common reason a place is fine on desktop and crashes on a phone, and no instance property reports it. What can be counted exactly is how many distinct images the place references and how often each is reused: an atlas on 500 objects is paid for once, 500 one-off images are paid for 500 times. This mode ranks objects by that, so it surfaces *memory pressure* — it counts assets, not megabytes, because the engine doesn't expose resolution.

### About the Overlap mode

Parts buried inside other parts are never seen but are still stored, replicated and — unless something occludes them — drawn; coincident surfaces also flicker and cost overdraw. Overlap buckets world-space bounding boxes into a grid and reports how much of each part sits inside another. Boxes are axis-aligned, so for rotated parts the percentage is an upper bound.

## Highlights in your scene

Highlights are `BoxHandleAdornment`s in a folder under `CoreGui` — **nothing is added to your `Workspace`**. They don't show up in the Explorer, aren't saved into the place, don't count towards the `Stats` the panel reports, follow objects that move, and never block clicking the object underneath. Only the HIGH COST and MODERATE items are drawn, capped at the worst 150; anything past the cap is still listed in full, and the panel says so.

Closing the panel hides the adornments; re-opening it in the same Studio session puts the previous scan back exactly as it was, so accidentally closing the panel costs you nothing. Nothing is persisted — reopening the place starts clean.

## Stats panel

A live readout of `Stats` service metrics (including `SceneDrawcallCount` and `SceneTriangleCount`), refreshed while the widget is open. Each value is coloured green / yellow / red against a rough budget for a mid-range device. Those budgets are rules of thumb, not engine limits: red means "worth investigating".

In edit mode the timing and bandwidth rows describe **Studio**, not your game — frame times include the editor viewport, selection gizmos and every open dock widget. Those rows are greyed out and labelled until you hit Play, rather than being coloured against a budget they have no relationship to. The tracked list and its thresholds live in `Main/Modules/UIService/Properties.luau`.

## A note on accuracy

Most of these modes are heuristics. They point you at likely suspects — they do not prove that a highlighted object is what's costing you frames. Profile with the Studio microprofiler before making big decisions.

**Measure** is the exception, and it's exact about a narrow thing: what the selected objects cost the renderer *from the current camera, at the margin*. That's a measurement, not a guess, but it's a measurement of one shot. **Draw calls** is explicitly an estimate and prints its own error against the engine's counter. Everything else is a proxy and says which one.

## Repository layout

Only the Luau source is version-controlled; the plugin's GUI instances live inside the Roblox plugin file and are resolved at runtime.

```
Main/
  init.local.luau                 entry point (plugin LocalScript, Studio API + wiring)
  Modules/
    HeatmapService.luau           run lifecycle: index -> analyzer -> buckets -> highlights
    WorkspaceIndex.luau           one traversal of Workspace, shared by every mode
    Budget.luau                   time-slicing, progress reporting, cancellation
    Highlighter.luau              CoreGui adornments (never touches Workspace)
    RenderProbe.luau              measures real render cost by hiding objects and diffing Stats
    Analyzers/init.luau           mode registry; `id` must match the GUI Frame name
    Analyzers/*.luau              one module per mode
    UIService/init.luau           panel, results list, stats rendering
    UIService/Properties.luau     tracked Stats metrics + their good/warn budgets
    Anim.luau                     TweenService hover/click animations
    Format.luau                   shared number formatting for the results list
    Version.luau                  current version + semver helpers
    UpdateChecker.luau            checks version.json on GitHub for updates
version.json                      published version, served over raw.githubusercontent
```

Adding a mode is one file in `Analyzers/` plus a `Frame` of the same name under `Body.Head` in the plugin's GUI — `run` dispatches off the registry, so there is no if-chain to extend.

## Development

There is no build step. The `.luau` files are synced into the plugin's script tree with Roblox Studio's native **Script Sync**; the `init.luau` / `init.local.luau` naming mirrors the Rojo convention. Test by toggling the toolbar button in Studio and exercising each mode against a scene.

To cut a release: bump `Version.current` in `Main/Modules/Version.luau`, bump `version` in `version.json`, push to `main`, then publish the plugin.

## Roadmap

What's planned, in what order, and what's deliberately out of scope: **[ROADMAP.md](ROADMAP.md)**. Per-object measurement landed in v1.7; next up is turning findings into one-click, undoable fixes.

## Feedback

Feature requests and bug reports are welcome on the [DevForum thread](https://devforum.roblox.com/t/3416936) — the roadmap is driven by it.
