# UI Performance Architecture

This note records measured performance facts and the architectural performance
contract for `lua/ui`. It exists because the SDL gallery exposed a real design
problem: dynamic UI examples can accidentally force broad remeasurement and text
layout work even when only paint/value state changed.

The goal is not to make one demo faster by ad-hoc patches. The goal is a general
UI kit whose phase boundaries make it clear which changes invalidate structure,
layout, text layout, paint, and interaction reports.

## Measured facts

The gallery was profiled with SDL's dummy video driver so rendering work could be
separated from window/display behavior.

Representative commands used during investigation:

```sh
AUTO_QUIT_MS=1000 SDL_VIDEODRIVER=dummy luajit examples/ui/gallery_sdl3.lua
AUTO_QUIT_MS=1000 SDL_VIDEODRIVER=dummy luajit /tmp/profile_gallery.lua
AUTO_QUIT_MS=1 SDL_VIDEODRIVER=dummy luajit /tmp/profile_gallery_pvm.lua
```

Before the validated cache-policy edit, the 1s dummy run showed approximately:

```text
ui.render.root           n=7     avg=0.1137s/frame
ui.text.layout           n=5899  total calls in run
ui.lower.root            n=7     avg=0.0052s/frame
ui.runtime.run           n=7     avg=0.0072s/frame
```

A single-frame PVM stats probe showed:

```text
ui.measure      calls=5350  reuse≈12%
ui.text_layout  calls=1524  reuse≈21%
ui.render       calls=199   reuse=0% on first frame
ui.lower        calls=208   reuse≈0% on first frame
```

This showed that the visible slowness was not primarily SDL drawing. It was
layout measurement and text layout churn.

A narrow cache-policy experiment isolated one concrete bug: `ui.measure.phase`
was using `args_cache = "last"`. During flex/grid/render planning the same node
can legitimately be measured under several constraints in one frame. Keeping
only the latest argument tuple evicted useful results and forced redundant
measurement.

Changing only `ui.measure.phase` to `args_cache = "full"` changed the 1s dummy
profile to approximately:

```text
ui.render.root           n=23    avg=0.0125s/frame
ui.text.layout           n=625   total calls in run
ui.lower.root            n=23    avg=0.0028s/frame
ui.runtime.run           n=23    avg=0.0032s/frame
```

Single-frame stats after that edit:

```text
ui.measure      calls=2688  reuse≈34%
ui.text_layout  calls=637   reuse≈28%
```

This edit is evidence-backed and local, but it is not the full performance
architecture. Thousands of measurements in one frame are still too many for a
large general-purpose UI.

## What the measurements imply

### Rebuilding Auth trees is not automatically fatal

Most authored and layout nodes are ASDL `unique` values. Rebuilding the same
structural tree can still hit PVM caches if the rebuilt values are structurally
identical. Therefore the issue is not simply "immediate mode is slow".

The problem appears when dynamic values are embedded as structure:

- sliders encode the current value as a fill box width;
- meters/progress/knobs/canvas programs can rebuild paint values;
- value labels rebuild text literals;
- hover/focus/active state can change styled subtrees;
- text fields can change both text content and text layout.

Those changes create new ASDL values and invalidate ancestors. Some of this is
necessary; much of it is not.

### Measurement and placement are currently duplicated

The current pipeline is roughly:

```text
Auth.Node -> lower -> Layout.Node -> render -> View.Op
                         ^             |
                         |             calls measure/layout planning
                         measure ------+
```

`ui.measure` and `ui.render` both call the shared layout planning helpers in
`ui.plan`. Measurement uses planning to compute intrinsic/final sizes. Rendering
uses planning again to place children and emit transform/render ops. PVM caches
child `Layout.Size` results, but the plan artifact itself is not a first-class
cached value shared by measure and render.

This means the system has a hidden phase that is not represented as a stable
artifact: solved layout.

### Text layout is a special cache dimension

`ui.text_layout` currently keeps only the last argument tuple. That was chosen to
avoid retaining unbounded histories of width-sensitive text layouts. This is
reasonable as a memory-safety instinct, but the gallery shows that layout can
request the same text under multiple constraints repeatedly.

Blindly switching text layout to full caching may improve some cases but risks
unbounded history for resizable/text-heavy UIs. Text layout needs an explicit
cache policy, not an incidental PVM setting.

## Performance contract

### 1. Separate structure, solved layout, and dynamic display data

The UI kit should treat these as separate invalidation classes:

```text
Auth structure/style/theme/env
  -> Layout tree
  -> Solved layout tree / placement artifact
  -> View ops / runtime report

Dynamic stores:
  text content
  widget values
  paint programs / canvas data
  interaction state
  scroll state
```

A change should declare which class it invalidates:

| Change | Required invalidation |
|---|---|
| add/remove/reorder node | structure + layout + render/report |
| change style tokens affecting box/layout/text metrics | layout + render/report |
| change theme/env/density/viewport | layout + render/report |
| change text content in a layout text node | text layout + layout + render/report |
| change text content in fixed-size/clipped display | text layout + render/report, layout only if configured |
| change slider value represented as paint | render/report only |
| change meter/scope/canvas paint data | render only, report only if hit geometry changes |
| hover/focus/active state that only changes colors | render only |
| hover/focus/active state that changes border/size/layout | layout + render/report |
| scroll offset | render/report only, not structure/layout |

Widgets must not hide this. A widget should know whether its value changes are
layout-affecting or paint-only.

### 2. Introduce a solved layout artifact

The missing phase should be made explicit:

```text
Layout.Node + constraint + text system + layout-affecting content
  -> Solve.Node / Solve.Tree
```

A solved tree should contain at least:

- node id;
- absolute or parent-relative position;
- final border/content sizes;
- clipping/scroll content sizes;
- focus/hit/drag/drop rectangles;
- text layouts for text nodes;
- references to paint/text/value bindings where render-time resolution is safe.

`ui.render` should consume the solved artifact rather than recomputing flex,
flow, and grid plans from scratch. `ui.measure` can either become a query over
`Solve.Node` or remain as a lower-level helper used by the solve phase.

This is the compiler-shaped boundary the current design is missing.

### 3. Keep dynamic values out of structural widgets when possible

Widget catalog rules:

- A slider/fader/knob's geometry is structural; its current value should normally
  be dynamic display data.
- Track fill, knob arcs, meters, scopes, and progress bars should be paint-backed
  or solved-geometry-backed dynamic rendering, not child box widths that force
  flex/layout re-solving on every value change.
- Value labels are text. If the label's changing width can affect layout, it is a
  layout-affecting content update. If the label is in a fixed slot, it can be a
  render/text update only.
- Canvas content should be a paint binding/store, not a freshly rebuilt authored
  tree for every frame.
- Text fields are allowed to be layout-affecting, but the fixed-size field shell
  should not be rebuilt for every caret/selection/composition paint update.

Compatibility wrappers may continue to build immediate authored nodes, but the
productized path should expose stable structure plus dynamic stores.

### 4. Cache policies must be explicit

Observed/validated policy:

- `ui.measure.phase` needs full argument history per live node, because one frame
  legitimately measures a node under multiple constraints. Weak node keys mean
  this does not retain dead nodes, but live resizable trees can still accumulate
  many constraint entries.

Required future policies:

- solved layout cache should be keyed by `(layout node, constraint, text-system,
  layout-affecting content epoch)`;
- text layout cache should be bounded or epoch-scoped, not accidentally unbounded;
- render-op cache should distinguish layout-stable paint changes from layout
  changes;
- examples should expose counters so regressions in lower/measure/render/text
  calls are visible.

`args_cache = "full"` is acceptable for phases where argument cardinality is
bounded by the solve contract. It is not a general answer for arbitrary dynamic
inputs.

### 5. The gallery is an acceptance test, not the architecture

The gallery should eventually demonstrate the contract by:

- building stable structure once or by coarse structural epoch;
- updating widget values through dynamic stores;
- updating meters/canvas through paint bindings;
- preserving focus/hover/scroll state through `Interact.Model`;
- showing that paint-only animation does not re-lower/re-measure the whole tree;
- exposing debug counters for lower/solve/text/render/runtime work.

A fast gallery that merely hides expensive work is not sufficient.

## Concrete current edit

The only code edit made from this investigation so far is:

```lua
-- lua/ui/measure.lua
measure_phase = pvm.phase("ui.measure", ..., {
    args_cache = "full",
})
```

This is a concrete bug fix supported by measurement. It should remain documented
as an interim correction, not the final performance architecture.

## Required design work before larger edits

Before adding implementation tasks for retained/dynamic UI, the following design
questions must be answered precisely:

1. What is the exact ASDL shape of a solved layout artifact?
2. Which solved fields are stable across paint-only updates?
3. What dynamic store types are needed: text, numeric values, booleans,
   selections, paint programs, images?
4. How do widgets declare whether a binding is layout-affecting?
5. How are content/text epochs represented in cache keys?
6. Is text layout cache per-session, per-frame, bounded LRU, or PVM phase cache?
7. How does overlay/modal/scroll/focus reporting use solved geometry without
   recomputing layout?
8. What profiling counters become part of tests/examples?

Only after these are answered should the edit plan receive concrete tasks for a
retained/solved/dynamic pipeline.
