![PerformanceHeatmap Banner](https://github.com/mattqdev/Performance-Heatmap/blob/main/assets/PerformanceHeatmapbanner.png)

<div align="center">

**[🔨 Download](https://create.roblox.com/store/asset/89564204038561) | [👑 Creator Profile](https://www.roblox.com/users/2992118050) | [🪲 Support ](https://discord.gg/ETgCMSps4c)**

</div>

# Performance Heatmap

A Roblox Studio plugin that scans your `Workspace` and highlights the objects most likely to be hurting performance, alongside a live panel of `Stats` service metrics.

**[Get it on the Creator Store](https://create.roblox.com/store/asset/89564204038561)** · **[DevForum thread](https://devforum.roblox.com/t/3416936)**

## Heatmap modes

Pick a mode from the panel header and the plugin colours the offenders directly in the viewport — red for the worst, yellow for borderline, green for fine — and lists them sorted worst-first. Clicking a row selects the instance.

| Mode          | What it looks at                                                                                    |
| ------------- | --------------------------------------------------------------------------------------------------- |
| **Density**   | Parts per unit of volume in a `Model`, so tightly packed builds score worse than large sparse ones. |
| **Count**     | Raw part count per `Model`.                                                                         |
| **Lights**    | `PointLight` / `SpotLight` / `SurfaceLight`, scored as `Brightness × Range`.                        |
| **Particles** | `ParticleEmitter`, scored as `Rate × average Lifetime × Brightness`.                                |
| **Triangles** | Per-`MeshPart` triangle count.                                                                      |

### About the Triangles mode

Where possible the real triangle count is read from the mesh via `AssetService:CreateEditableMeshAsync`. That API only works on assets you own, so most Toolbox and Marketplace meshes can't be measured — those fall back to a rough cost estimate from `RenderFidelity`, `CollisionFidelity` and bounding-box size, and are always labelled `(stima …)`. An estimate is never presented as a measured triangle count.

## Stats panel

A live readout of `Stats` service metrics (including `SceneDrawcallCount` and `SceneTriangleCount`), refreshed continuously while the widget is open. The tracked list lives in `Main/Modules/UIService/Properties.luau`.

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
    UIService/Properties.luau     declarative list of tracked Stats metrics
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
