![PerformanceHeatmap Banner](https://github.com/mattqdev/Performance-Heatmap/blob/main/assets/PerformanceHeatmapbanner.png)

<div align="center">

**[🔨 Download](https://create.roblox.com/store/asset/89564204038561) | [👑 Creator Profile](https://www.roblox.com/users/2992118050) | [🪲 Support ](https://discord.gg/ETgCMSps4c)**

</div>

# Performance Heatmap

A Roblox Studio plugin that scans your `Workspace` and highlights the objects most likely to be hurting performance, alongside a live panel of `Stats` service metrics.

**[Get it on the Creator Store](https://create.roblox.com/store/asset/89564204038561)** · **[DevForum thread](https://devforum.roblox.com/t/3416936)**

## Heatmap modes

Pick a mode from the panel header and the plugin colours the offenders directly in the viewport — red for the worst, yellow for borderline, green for fine — and lists them sorted worst-first within each section. The **BIG ELEMENTS** / **MEDIUM ELEMENTS** headers show how many items fell into each bucket. Clicking a row selects the instance.

| Mode          | What it looks at                                                                                    |
| ------------- | --------------------------------------------------------------------------------------------------- |
| **Density**   | Parts per unit of volume in a `Model`, so tightly packed builds score worse than large sparse ones. |
| **Count**     | Raw part count per `Model`.                                                                         |
| **Lights**    | `PointLight` / `SpotLight` / `SurfaceLight`, scored as `Brightness × Range`.                        |
| **Particles** | `ParticleEmitter`, scored as `Rate × average Lifetime × Brightness`.                                |
| **Triangles** | Per-`MeshPart` triangle count.                                                                      |

### About the Triangles mode

Where possible the real triangle count is read from the mesh via `AssetService:CreateEditableMeshAsync`. That API only works on assets you own, so most Toolbox and Marketplace meshes can't be measured — those fall back to a rough cost estimate from `RenderFidelity`, `CollisionFidelity` and bounding-box size, and are always labelled `(est. …)`. An estimate is never presented as a measured triangle count. Measured meshes are listed above estimated ones, since a triangle count and an estimate score aren't the same unit and can't be ranked against each other.

## Highlights in your scene

The highlight parts live in a non-`Archivable` `PerformanceHeatmapContainer` folder in `Workspace`. Closing the panel removes that folder from `Workspace`; re-opening it in the same Studio session puts the previous scan back exactly as it was, so accidentally closing the panel costs you nothing. Nothing is persisted — reopening the place starts clean.

## Stats panel

A live readout of `Stats` service metrics (including `SceneDrawcallCount` and `SceneTriangleCount`), refreshed continuously while the widget is open. Each value is coloured green / yellow / red against a rough budget for a mid-range device, so you can see at a glance whether a metric looks healthy. Those budgets are rules of thumb, not engine limits: red means "worth investigating". The tracked list and its thresholds live in `Main/Modules/UIService/Properties.luau`.

## A note on accuracy

This is a heuristic tool. It points you at likely suspects — it does not prove that a highlighted object is what's costing you frames. Profile with the Studio microprofiler before making big decisions.

## Repository layout

Only the Luau source is version-controlled; the plugin's GUI instances live inside the Roblox plugin file and are resolved at runtime.

```
Main/
  init.local.luau                 entry point (plugin LocalScript, Studio API + wiring)
  Modules/
    HeatmapService.luau           analysis + viewport highlighting
    UIService/init.luau           panel, results list, stats rendering
    UIService/Properties.luau     tracked Stats metrics + their good/warn budgets
    Anim.luau                     TweenService hover/click animations
    Version.luau                  current version + semver helpers
    UpdateChecker.luau            checks version.json on GitHub for updates
version.json                      published version, served over raw.githubusercontent
```

## Development

There is no build step. The `.luau` files are synced into the plugin's script tree with Roblox Studio's native **Script Sync**; the `init.luau` / `init.local.luau` naming mirrors the Rojo convention. Test by toggling the toolbar button in Studio and exercising each mode against a scene.

To cut a release: bump `Version.current` in `Main/Modules/Version.luau`, bump `version` in `version.json`, push to `main`, then publish the plugin.

## Feedback

Feature requests and bug reports are welcome on the [DevForum thread](https://devforum.roblox.com/t/3416936) — the roadmap is driven by it.
