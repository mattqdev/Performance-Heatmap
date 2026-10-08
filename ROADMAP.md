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

v1.7 closed the strategic gap those fixes left open. Until then every mode
answered "what *looks* expensive?" with a proxy; `Measure` answers "what does
this actually cost?" with the engine's own counters, and `Draws` answers "how
many draw calls is this place?" for the whole scene. The half still missing is
"…and how much will changing it save?" — that's v1.8.

---

## v1.7 — Real numbers ✅ shipped

The theme: replace heuristics with measurements wherever the engine will give us
one.

### Measure Selection ✅

Reads `SceneDrawcallCount` / `SceneTriangleCount`, makes the selected objects
stop rendering, reads again, reports the difference. Works on the selection, or
on the worst offenders of the last scan when nothing is selected. Capped at 50
targets. Mechanics and the full record of what was verified live in
`Modules/RenderProbe.luau`.

**What the verification in Studio actually found** (edit mode, 1082-part scene):

- `LocalTransparencyModifier = 1` **does** drop a part from the render batch:
  58 → 13 draw calls, 33,080 → 26 triangles with everything hidden, and the
  counters return to exactly their previous values on restore. No fallback to
  `Transparency` or `Parent = nil` is needed, so the place is never dirtied.
- With nothing moving the counters are **stable to the unit**, frame after
  frame. A delta of one draw call is signal, not noise.
- **This roadmap was wrong about `CastShadow`.** It claimed neither property is
  serialised; `CastShadow` is, so toggling it would mark the place as modified.
  The shadow counters were also still drifting (0 → 15 → 2 → 39) several frames
  after a change. Per-object **shadow cost is therefore not measured** — left
  out rather than reported as a noisy number that dirties the file to obtain.
  Anyone revisiting this needs a way to settle the shadow map deterministically
  first.
- Per-object deltas are frequently **zero**, for two different reasons: the
  object is outside the camera frustum, or it shares a batch with others so
  removing it alone saves nothing. Both are real answers about *this shot*, and
  the UI says "not drawn from this camera" rather than "0 draw calls".

### Static draw-call report ✅

`Draws` groups every renderable by `(geometry, surface, pass)` — mesh URI /
primitive shape / per-union identity, then `SurfaceAppearance` maps, texture,
`MaterialVariant` or material, then transparency and shadow pass. The number of
groups is approximately the draw call count, and the list is the tail: batches
used once, which pay a full draw call for a single object.

The summary prints the estimate next to the live `SceneDrawcallCount` so the
error is visible — with the caveat that they count different things (whole place
vs. what the camera sees). On the test scene the estimate came out at 58 batches
against 58 reported draw calls, which is a better agreement than this method
deserves in general and should not be quoted as its accuracy.

Known imprecision, stated in the mode and worth keeping stated:
`UnionOperation.AssetId` is not a readable member, so copies of one union cannot
be told apart from distinct unions and each is counted as its own batch.

### Texture memory, with actual numbers — still open

`Texture` currently ranks asset counts because the engine exposes no resolution.
Investigate whether `Stats` memory categories (`GraphicsTexture`) can be diffed
the way `RenderProbe` now diffs draw calls. The obstacle to expect: texture
memory is a cache, so it won't drop the frame an object stops rendering the way
a draw call does, and the diff may need an eviction that plugins can't force. If
it works, the mode graduates from a ranking to a measurement; if it doesn't,
record why here and leave the mode honest about counting assets.

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
heuristics stacked on heuristics. `Draws` now gives a whole-place draw call
figure to build a score on; `Measure` gives per-object confirmation. What's still
missing is the *saving* half — the estimate of what a fix is worth, which is the
one-click fixes above.

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
  thousand findings will stall the panel. **More pressing since v1.7:** `Draws`
  reports one row per one-off batch, and a place assembled from Toolbox models
  can easily have thousands. Capping the list is not the answer — the highlight
  cap exists precisely so the list can stay complete — so this is the fix.
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

- **`Measure`** reports the cost **from the current camera, at the margin**. Zero
  means the object is outside the frustum or shares a batch with others — never
  "free", and the UI must keep saying "not drawn from this camera" instead of
  "0 draw calls". Marginal costs also don't sum: objects measured one at a time
  total less than the same objects measured together. Shadow cost is not
  measured at all (see v1.7 above for why).
- **`Draws`** is an estimate. Batching depends on renderer decisions no property
  exposes, and each `UnionOperation` is counted as its own batch because there is
  no readable shared asset id. Its summary prints the engine's own count beside
  the estimate; keep it printing it, and keep saying the two cover different
  scopes.
- **`Triangles`** cannot measure meshes the user doesn't own. Estimated rows are
  labelled `(est. …)` and ranked separately, because a triangle count and a
  heuristic score are different units. `Measure` is the way round it, per object.
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
