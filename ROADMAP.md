# Roadmap

What's left to build, roughly in the order it should happen. The goal it's all
pointed at: **stop being a tool that tells you what is big, and become one that
tells you what costs frames and then fixes it.**

Feedback that drives this lives on the [DevForum thread](https://devforum.roblox.com/t/3416936).
Shipped work is in the [README](README.md); implementation notes and conventions
are in [CLAUDE.md](CLAUDE.md).

---

## Where things stand

v1.6 closed out the credibility problems: highlights no longer touch `Workspace`
(so the plugin stopped inflating the stats it reports), scans no longer freeze
Studio, the two dead menu buttons became the `Texture` and `Overlap` modes, and
the `Density` / `Lights` / `Particles` formulas were measuring the wrong things
and now don't.

What that did **not** fix is the strategic gap. Every mode still answers "what
looks expensive?" using proxies. A developer's actual question is "what should I
change, and how much will it save?" — and nothing here answers the second half.
Everything below exists to close that gap.

---

## v1.7 — Real numbers

The theme: replace heuristics with measurements wherever the engine will give us
one.

### Measure Selection

**The flagship feature. Nothing else on this list matters as much.**

The engine already knows the true cost of every object — `SceneDrawcallCount`,
`SceneTriangleCount` and `ShadowsDrawcallCount` are right there in `Stats`. We
can attribute those numbers to a single object by difference:

1. read the counters
2. make the object stop rendering (`LocalTransparencyModifier = 1` plus
   `CastShadow = false` — neither is serialised, so the place is never dirtied)
3. wait a frame
4. read again; the delta is that object's real draw calls, triangles and shadow
   cost from the current camera

What this unlocks in one move:

- **real triangle counts on Toolbox and Marketplace meshes**, sidestepping the
  `CreateEditableMeshAsync` permission wall that makes `Triangles` fall back to
  an estimate on most scenes
- **draw calls per object** — the thread's most-repeated request (NotRapidV,
  xor25th), which no plugin currently answers
- **shadow cost per object**, separately from its base cost

It takes ~2 frames per object, so this is a *"measure the selection"* /
*"measure the top 50 from the last scan"* action, not a whole-place sweep. The
workflow becomes: heuristic heatmap to narrow the field, real measurement to
confirm.

> ⚠️ **Verify before promising anything.** Confirm in Studio that
> `LocalTransparencyModifier = 1` actually drops the object from the render batch
> in edit mode. If it doesn't, fall back to `Transparency = 1` (restore after,
> and don't record a ChangeHistory waypoint) or `Parent = nil`. Do this test
> first — the whole feature depends on it.

### Static draw-call report

Draw calls are also derivable without measuring, because objects batch by
`(MeshId, TextureID, SurfaceAppearance, MaterialVariant, Transparency > 0,
CastShadow)`. Group every renderable by that key: the number of groups is
approximately the number of draw calls.

The actionable output isn't the total, it's the tail — *"60 assets appear
exactly once, costing a full draw call each; your 12 most-reused meshes cover
8,000 instances in 12 draw calls."*

Validate the estimate against the real `SceneDrawcallCount` and **display the
error rather than hiding it**. An estimate that shows its own accuracy is worth
more than one that doesn't.

### Texture memory, with actual numbers

`Texture` currently ranks asset counts because the engine exposes no resolution.
Investigate whether `Stats` memory categories (`GraphicsTexture`) can be diffed
the same way Measure Selection diffs draw calls. If they can, the mode graduates
from a ranking to a measurement.

---

## v1.8 — From diagnostic to tool

The theme: a finding you can act on beats a finding you can only read.

### One-click fixes

Each finding gets a safe, reversible action, applied in bulk, wrapped in
`ChangeHistoryService:TryBeginRecording` / `FinishRecording` so Ctrl+Z works.
Always **preview → select → apply**; never silent, never automatic.

| Finding | Fix | Typical impact |
| --- | --- | --- |
| `CollisionFidelity = PreciseConvexDecomposition` on decorative meshes | → `Box` | **Largest safe win on most places** (memory + physics) |
| `CastShadow` on small or interior props | → `false` | High, near-invisible visually |
| `RenderFidelity = Precise` on small or distant meshes | → `Automatic` | High |
| Unanchored parts that never move | → `Anchored = true` | High (physics) |
| Lights with `Shadows` on decorative fixtures | → `false` | High |
| Fully buried parts (from `Overlap`) | → flag for deletion | Medium |
| `ParticleEmitter` with an absurd `Rate` | → suggested clamp | Medium |

### Performance score

One number for the place, plus the top five issues and an estimated saving:
*"62/100 — applying the suggested fixes drops an estimated 3,400 draw calls to
1,200."* Developers screenshot scores. That is free distribution, and it's the
kind of thing that gets a plugin recommended rather than merely installed.

Only ship this once the numbers behind it are measurements (v1.7), not
heuristics stacked on heuristics.

### Snapshot & diff

Save a scan, optimise, scan again, see the delta: *"−2,100 draw calls, −840k
triangles, −12k instances."* Closes the feedback loop, which is what makes a tool
worth reopening.

### Per-finding explanations

Every row gets a one-line "why this costs" ("Precise collision on an 8k-triangle
mesh: the collision mesh is generated at runtime and sits in memory"). Tools that
teach are the ones that become defaults.

---

## v2.0 — Platform

The theme: make the project maintainable by someone other than its author.

### Build the GUI in code

Right now `MainUI`, `BG`, `Template`, `Stat` and `Divider` live inside the
plugin file and are resolved with `script:WaitForChild(...)`. The cost of that is
visible in CLAUDE.md, which carries a running list of "manual steps in Studio".
Constructing the panel in Luau means: everything in git, reviewable diffs, no
manual steps, contributors who don't need the author's place file — and Studio
theme support (`settings().Studio.Theme` + `ThemeChanged`), which is impossible
while the colours are baked into instances.

This is the single highest-leverage refactor left, and it blocks the three items
below.

### Rojo, CI, tests

- a `*.project.json` so the plugin builds from a clean checkout
- `selene` + `stylua` in GitHub Actions
- a released `.rbxm` artifact per tag
- analyzers are already pure `(index, budget) -> findings` functions, so they can
  be tested against a fake index under Lune. There are currently **zero** tests
  over the analysis logic.

### Play-mode profiler

`RunService:IsRunning()` already gates the `PlayOnly` Stats rows. Go further:
sample frame time across a playtest and report **p1% / p5% / average** plus spike
timestamps. Percentiles are what actually correspond to a game feeling bad; a
live instantaneous readout does not.

### Settings and presets

- persist thresholds, palette, highlight cap and last mode via
  `plugin:SetSetting`
- **budget presets** — Mobile / Console / PC retune every threshold at once. The
  values hard-coded in each analyzer cannot be right for a simulator and a horror
  game simultaneously.

---

## Backlog

Small, independent, each worth doing whenever there's an opening.

- **Virtualise the results list.** `refreshList` builds one frame per row; a few
  thousand findings will stall the panel.
- **Search / filter / group by asset** in the list, and "select every HIGH COST
  item" (`Selection:Set` takes a list).
- **Camera cost view** — cull to the current camera frustum and report *"78% of
  the triangles in this shot come from 3 objects."* Makes the next move obvious.
- **Keyboard shortcut** via `plugin:CreatePluginAction`.
- **Resizable panel** — the widget minimum is 153×300, which is cramped for the
  Stats view.
- **In-panel changelog.** `UpdateChecker` already downloads `version.json`; put
  release notes in it and show them after an update.
- **Export a report** (Markdown / CSV). Plugins have no clipboard or filesystem
  access, so this means a selectable `TextBox`, or writing a `Script` into
  `ServerStorage` with the report as its source.
- **Terrain and script analysis.** Terrain cost is invisible to every mode here.
  A static linter for common script antipatterns (`while true do` with no wait,
  unbounded `Heartbeat` connections) would be genuinely useful and nobody ships
  one.

---

## Known limitations to keep honest

Carry these caveats forward; do not let them quietly disappear from the UI.

- **`Triangles`** cannot measure meshes the user doesn't own. Estimated rows are
  labelled `(est. …)` and ranked separately, because a triangle count and a
  heuristic score are different units. Measure Selection is the real fix.
- **`Texture`** counts assets, not megabytes. The engine exposes no resolution.
- **`Overlap`** uses axis-aligned bounding boxes, so the reported percentage is
  an upper bound for rotated parts.
- **Thresholds** are rules of thumb for a mid-range device, not engine limits.
  Red means "worth a look", not "broken". They also haven't been calibrated
  against a large sample of real places — budget presets are the proper fix.
- **The highlight cap** (150) means the viewport shows the worst offenders while
  the list stays complete. The panel says so; keep it saying so.
- **Edit-mode `Stats`** describe the Studio process. Timing and bandwidth rows
  are greyed out and labelled until Play. Never colour a number against a budget
  it has no relationship to.

---

## Explicitly not doing

- **Claiming a highlighted object definitively causes lag.** It doesn't, and the
  thread has already called the plugin out for overstating. Profile with the
  microprofiler before big decisions — the README says this and should keep
  saying it.
- **Persisting scan results across sessions.** Highlights and result tables are
  session-only, in-memory state by design. Reopening the place starts clean.
- **Auto-applying fixes.** Every mutation is previewed, undoable, and chosen by
  the user.
