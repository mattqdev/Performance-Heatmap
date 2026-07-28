![PerformanceHeatmap Banner](https://github.com/mattqdev/Performance-Heatmap/blob/main/assets/PerformanceHeatmapbanner.png)

<div align="center">

**[🔨 Download](https://create.roblox.com/store/asset/89564204038561) | [👑 Creator Profile](https://www.roblox.com/users/2992118050) | [🪲 Support ](https://discord.gg/ETgCMSps4c)**

</div>

# Performance Heatmap

A Roblox Studio plugin that scans your `Workspace` and highlights the objects most likely to be hurting performance, alongside a live panel of `Stats` service metrics.

**[Get it on the Creator Store](https://create.roblox.com/store/asset/89564204038561)** · **[DevForum thread](https://devforum.roblox.com/t/3416936)**

## Heatmap modes

Pick a mode from the panel header and the plugin outlines the offenders directly in the viewport — red for the worst, yellow for borderline — and lists them sorted worst-first within each section. The **HIGH COST** / **MODERATE** headers show how many items fell into each bucket. Clicking a row selects the instance.

| Mode          | What it looks at                                                                                                        |
| ------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **Count**     | Part count per `Model`, attributed to the nearest `Model` so a map container doesn't report the whole place.             |
| **Density**   | Parts per 1,000 studs³ of the model's bounding box — how tightly a build is packed, not how big it is.                  |
| **Triangles** | Per-`MeshPart` triangle count, measured where permissions allow and estimated otherwise.                                 |
| **Textures**  | Distinct image assets per object, weighted towards images the place uses only once.                                     |
| **Overlap**   | Parts that sit inside other parts — buried geometry and z-fighting candidates.                                          |
| **Lights**    | `PointLight` / `SpotLight` / `SurfaceLight`, scored as `Brightness × Range`, tripled when the light casts shadows.       |
| **Particles** | `ParticleEmitter`, scored by overdraw: particles alive at once × area × opacity.                                        |

Scans run on a time budget and yield between slices, so Studio stays responsive on large places; progress appears in the widget title, and picking another mode cancels the scan in flight.

### About the Triangles mode

Where possible the real triangle count is read from the mesh via `AssetService:CreateEditableMeshAsync`. That API only works on assets you own, so most Toolbox and Marketplace meshes can't be measured — those fall back to a rough cost estimate from `RenderFidelity`, `CollisionFidelity` and bounding-box size, and are always labelled `(est. …)`. An estimate is never presented as a measured triangle count. Measured meshes are listed above estimated ones, since a triangle count and an estimate score aren't the same unit and can't be ranked against each other.

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

This is a heuristic tool. It points you at likely suspects — it does not prove that a highlighted object is what's costing you frames. Profile with the Studio microprofiler before making big decisions.

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
    Analyzers/init.luau           mode registry; `id` must match the GUI Frame name
    Analyzers/*.luau              one module per mode
    UIService/init.luau           panel, results list, stats rendering
    UIService/Properties.luau     tracked Stats metrics + their good/warn budgets
    Anim.luau                     TweenService hover/click animations
    Version.luau                  current version + semver helpers
    UpdateChecker.luau            checks version.json on GitHub for updates
version.json                      published version, served over raw.githubusercontent
```

Adding a mode is one file in `Analyzers/` plus a `Frame` of the same name under `Body.Head` in the plugin's GUI — `run` dispatches off the registry, so there is no if-chain to extend.

## Development

There is no build step. The `.luau` files are synced into the plugin's script tree with Roblox Studio's native **Script Sync**; the `init.luau` / `init.local.luau` naming mirrors the Rojo convention. Test by toggling the toolbar button in Studio and exercising each mode against a scene.

To cut a release: bump `Version.current` in `Main/Modules/Version.luau`, bump `version` in `version.json`, push to `main`, then publish the plugin.

## Roadmap

What's planned, in what order, and what's deliberately out of scope: **[ROADMAP.md](ROADMAP.md)**. Next up is per-object draw call and triangle *measurement* — reading the engine's own counters rather than estimating — followed by one-click fixes for the findings.

## Feedback

Feature requests and bug reports are welcome on the [DevForum thread](https://devforum.roblox.com/t/3416936) — the roadmap is driven by it.
