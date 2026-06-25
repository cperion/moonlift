# Lalin UI library completion review
Audit lua/ui after importing the standalone UI library, with focus on SDL3 synth UI readiness and next completion tasks.
**Workflow ID**: wf-a6d2de07
**Started**: 2026-06-13 21:32:16
---

## Scout Output — 2026-06-13 21:36:25

## Files Retrieved

1. `lua/ui/README.md` (lines 1-210) — high-level architecture/status notes; also contains stale demo references and open gaps.
2. `lua/ui/asdl.lua` (lines 1-970) — full typed schema: style/auth/layout/view/interact/text/paint/session data.
3. `lua/ui/init.lua` (lines 1-29) — facade exports.
4. `lua/ui/build.lua` (lines 1-382) — immediate-mode authored node builders.
5. `lua/ui/lower.lua` (lines 1-375) — authored tree → layout tree lowering, including structural scroll compatibility.
6. `lua/ui/measure.lua` (lines 1-423), `lua/ui/plan.lua` (lines 1-805), `lua/ui/render.lua` (lines 1-353) — layout measurement/planning/render-op stream.
7. `lua/ui/runtime.lua` (lines 1-375), `lua/ui/interact.lua` (lines 1-545) — generic op consumer, hit/focus/scroll/drag reports, semantic interaction reducer.
8. `lua/ui/session.lua` (lines 1-476), `lua/ui/session_sdl3.lua` (lines 1-10) — multi-window event/redraw loop and SDL3 wrapper.
9. `lua/ui/_sdl3.lua` (lines 1-368), `lua/ui/host_sdl3.lua` (lines 1-427), `lua/ui/runtime_sdl3.lua` (lines 1-394), `lua/ui/text_sdl3.lua` (lines 1-583) — SDL3 FFI/host/render/text backend.
10. `lua/ui/text.lua`, `text_nav.lua`, `text_edit.lua`, `text_field.lua`, `text_field_view.lua` — text layout bridge and editable text controller/view.
11. `lua/ui/paint.lua` (lines 1-147), `lua/ui/runtime_love.lua` (lines 1-485) — typed paint builders and Love backend comparison.
12. `lua/ui/widgets/*`, `lua/ui/recipes/*` — text input/area widgets; activatable/selectable/reorderable/scroll/edit recipes.
13. `examples/ui/text_sdl3_probe.lua` (lines 1-119), `examples/ui/text_field_sdl3_demo.lua` (lines 1-182) — only current UI examples.
14. `tests/test_ui_smoke.lua` (lines 1-36) — only UI-specific test.

## Key Code

### ASDL architecture is strong and typed

`lua/ui/asdl.lua` defines the whole UI vocabulary:

```lua
module Auth {
  Node = Box(...) | Text(...) | TextRef(...) | Paint(...) | Scroll(...)
       | WithState(...) | WithInput(...) | WithDragSource(...)
       | WithDropTarget(...) | WithDropSlot(...) | Fragment(...) | Empty
}

module View {
  Kind = KBox | KText | KPaint | KPushClipRect | KPopClip | KPushTx | KPopTx
       | KPushScroll | KPopScroll | KHit | KFocus | KCursor
       | KDragSource | KDropTarget | KDropSlot
}

module Interact {
  Raw = PointerMoved(...) | PointerPressed(...) | PointerReleased(...)
      | WheelMoved(...) | FocusNext | FocusPrev | ActivateFocus | CancelPointer
}
```

This is well-aligned with Lalin’s “explicit ASDL meaning” style.

### Render/runtime flow

`lua/ui/render.lua` emits a relative op stream:

```lua
Auth/Compose -> lower -> Layout.Node
Layout.Node + env -> measure/render -> View.Op*
runtime.run(driver, opts, ops...) -> draw + Interact.Report
interact.step(model, report, raw) -> semantic events + next model
```

`lua/ui/runtime.lua` consumes the same op stream for drawing and hit/focus/scroll/drag facts, which is a good foundation for synth UI interaction.

### SDL3 backend exists

SDL3 pieces are present under both old and new paths:

- `ui._sdl3`
- `ui.host_sdl3`
- `ui.runtime_sdl3`
- `ui.text_sdl3`
- `ui.session_sdl3`
- `ui.backends.sdl3.*` wrappers

`lua/ui/host_sdl3.lua` normalizes SDL events, clipboard, text input, window lifecycle, frame begin/present.

`lua/ui/text_sdl3.lua` uses SDL3_ttf substring APIs for layout, hit testing, range queries, IME support.

### Paint support is good in schema/builders, incomplete in SDL runtime

`lua/ui/paint.lua` supports:

```lua
line, polyline, polygon, circle, arc, bezier, mesh, image
```

Love backend implements all of these in `lua/ui/runtime_love.lua`.

SDL backend currently handles only simple line-ish paths:

```lua
-- runtime_sdl3.lua lines 239-295
Paint.Line      -> SDL_RenderLine
Paint.Polyline  -> SDL_RenderLines
Paint.Polygon   -> stroke only, no fill
Paint.Circle    -> line approximation; filled circle still drawn as outline
Paint.Arc       -> lines
Paint.Bezier    -> lines
-- no Mesh/Image branches
```

## Relationships

- `ui.build` creates `Auth.Node`.
- `ui.compose` lowers named shell/workbench patterns into `Auth.Node`.
- `ui.lower` resolves styles and emits `Layout.Node`.
- `ui.measure` and `ui.render` share planning helpers from `ui.plan`.
- `ui.render` emits `View.Op`.
- `ui.runtime` executes ops through a backend driver and returns `Interact.Report`.
- `ui.interact` classifies raw pointer/wheel/focus events against the report and updates `Interact.Model`.
- SDL host provides normalized host events, but text editing and keyboard handling are partly outside generic `Interact.Raw`.

## Runnable Checks

Passed:

```sh
luajit tests/test_ui_smoke.lua
# ok test_ui_smoke
```

Module load check passed for non-SDL UI modules and recipes/widgets.

SDL require check passed:

```sh
require("ui._sdl3")
require("ui.runtime_sdl3")
require("ui.text_sdl3")
require("ui.host_sdl3")
require("ui.session_sdl3")
require("ui.backends.sdl3")
```

SDL text probe passed:

```sh
luajit examples/ui/text_sdl3_probe.lua
```

SDL text field demo can run headless briefly:

```sh
AUTO_QUIT_MS=50 SDL_VIDEODRIVER=dummy luajit examples/ui/text_field_sdl3_demo.lua
```

Found reproducible issue:

```sh
luajit - <<'LUA'
package.path='./lua/?.lua;./lua/?/init.lua;'..package.path
local sdl3=require('ui._sdl3')
print('SDLK_PAGEUP', tostring(sdl3.SDLK_PAGEUP))
print('SDLK_PAGEDOWN', tostring(sdl3.SDLK_PAGEDOWN))
LUA
# SDLK_PAGEUP nil
# SDLK_PAGEDOWN nil
```

`host_sdl3.lua` tries to normalize PageUp/PageDown, but `_sdl3.lua` never defines those constants.

## Observations

### Strengths

- Typed ASDL-first UI architecture is coherent and compiler-shaped.
- Structural scroll, hit/focus reports, drag/drop surfaces, and content-store text references are already designed.
- SDL3 backend is real enough to open windows, process input, draw text, handle clipboard/IME, and run demos.
- Text field stack is unusually complete: selection, caret movement, clipboard, IME composition, hit testing, scrolling helpers.
- Session loop supports dirty/timed redraw scheduling, useful for synth animation/meters.

### Concrete gaps/bugs for SDL3 synth UI readiness

1. **No synth controls yet**: no knob, slider/fader, toggle, menu, meter widget, value drag, tooltip/popup, or canvas abstraction beyond raw `Paint`.
2. **SDL paint incomplete**: no filled polygon, real filled circle, mesh, image, stroke width, or rounded rect rendering in `runtime_sdl3`.
3. **SDL rounded boxes ignored**: `BoxVisual.shape/radius` exists, Love honors it, SDL draws only rectangular fill/stroke.
4. **PageUp/PageDown broken in SDL key normalization** due missing constants.
5. **No Tab/Space key constants or generic keyboard event model** in `ui.input`/`Interact.Raw`; focus traversal exists only as abstract raw events.
6. **Text backend registration footgun**: `session` creates an SDL text system but only registers it if `opts.text_key` is provided; otherwise `ui.text.layout(..., host.text_system)` falls back to approximate layout.
7. **Test coverage is very thin**: only `tests/test_ui_smoke.lua`, which checks facade/builders/paint construction, not lower/measure/render/runtime/interact/SDL authored flow.
8. **README demo list is stale**: references Love UI demos not present in repo; actual `examples/ui/` only has SDL text probe and text field demo.
9. **No default theme/env factory found**; authored-tree lowering requires caller-provided `Theme.T` and `Env.Class`.
10. **SDL renderer performance likely needs work** for synth UI: text creates/destroys `TTF_Text` per draw run; custom paint is immediate-mode SDL primitives only.

## Knowledge-builder Output — 2026-06-13 23:00:01

### What Matters Most for This Problem

For turning `lua/ui` into a general-purpose UI kit, the important dimensions are:

- **Public contract stability** across `Auth → Layout → View → Runtime → Interact`
- **Completeness definition**: not “can draw a demo,” but “has reusable controls, lifecycle, input, text, backend, and test guarantees”
- **Backend parity** and avoidance of SDL/Love divergence
- **Interaction semantics**: keyboard, focus, pointer capture, nesting, drag/drop, disabled/selected state
- **ASDL discipline**: meaning should stay typed and explicit, not leak into host callbacks/string events
- **Documentation/test truthfulness**: README, examples, and tests must match actual capabilities
- **Sequencing**: some gaps block whole classes of widgets, while others are polish/backend coverage

### Non-Obvious Observations

- The scout findings are partly stale relative to the current tree. Several reported SDL gaps appear fixed now:
  - `lua/ui/_sdl3.lua` now defines `SDLK_PAGEUP`, `SDLK_PAGEDOWN`, `SDLK_TAB`, `SDLK_SPACE`.
  - `lua/ui/runtime_sdl3.lua` now has rounded/capsule box drawing and branches for filled polygons, circles, mesh, and image paint.
  - `lua/ui/theme.lua` now provides `ui.theme.default()` and env helpers.
  This matters because completion work should not be planned from the scout gap list alone.

- The remaining risk is less “missing SDL primitives” and more “missing UI-kit contracts.” The code can author, lower, measure, render, and hit-test trees, but there is not yet a canonical app-level contract for composing widgets, routing events, applying interaction state, redrawing, and synchronizing host text input.

- `Interact.Raw` is still pointer/wheel/focus-only. Keyboard events exist as backend-normalized Lua tables and `ui.input` string constants, not ASDL events. Text fields and scroll views handle keys through side APIs. This is a schema boundary mismatch with the project’s explicit-ASDL philosophy.

- Styling has rich state conditions (`hover`, `focus`, `active`, `selected`, `disabled`), but state application is manual via `Auth.WithState`. `ui.interact` computes hover/focus/pressed/drag facts, yet there is no automatic bridge from `Interact.Model` into `Style.State` during lowering. General-purpose controls will otherwise each reinvent hover/focus/active styling.

- IDs are a hidden global invariant. `Core.IdValue(string)` is used for scroll state, focus, hit routing, drag/drop, and recipe surface maps. Builders prevent duplicate IDs only within one builder call, not across the full tree. Duplicate IDs can silently collide across focus, scroll offsets, and event routing.

- Current hit testing is rectangular even when visuals are rounded/capsule/custom paint. That is acceptable for many widgets, but it means custom-painted controls are not semantically interactive unless wrapped in rectangular `WithInput`/drag/drop surfaces. “Canvas” or complex controls would need a clearer semantic hit model.

- Runtime hit selection only exposes a single `hover_id` by default. There is optional `collect_hits`, but classification uses only the topmost hover ID. This limits nested interactions, ancestor hover styling, bubbling-like behavior, tooltips on parent regions, and composite widgets with overlapping subparts.

- There is no explicit pointer capture concept. Drag state stores source ID, but reports are rebuilt from the current frame. If a pressed/dragged node disappears, reorders, or moves during interaction, semantics depend on current report geometry and ID stability rather than an explicit capture invariant.

- Focus order is stream order. That is simple and typed, but general UI kits usually need disabled skipping, focus scopes, modal scopes, tab groups, and sometimes custom order. The current model has no focus scope/layer concept.

- Popups, menus, tooltips, context menus, and modals are not just “more widgets.” The current render stream is structurally clipped by ancestry. Anything that must escape parent clipping or sit in a separate top layer likely stresses the current tree model, hit ordering, and focus model.

- Text editing is comparatively advanced, but it is partly out-of-band. `text_field_view` and text widgets draw overlays directly through the host rather than entirely through `Auth/Layout/View` ops. That is practical, but it creates a second rendering path outside the main typed op stream.

- Text backend registration remains a footgun. `ui.text.layout(style, constraint, key)` looks up a global registry. `ui.session` only registers the shared text system if `opts.text_key` is provided. Without that, layout falls back to approximate measurement even if an SDL text system exists.

- `Env.Density` exists in ASDL and theme env, but appears unused by layout/render resolution. HiDPI/device scaling is therefore not a completed contract, despite the schema suggesting it exists.

- Motion conditions exist in style schema, and session supports timed redraws, but animation itself is not first-class. A general-purpose kit needs clarity on whether animation is external app state or typed UI state.

- Layout is a deliberate subset, not CSS. README notes remaining flex/grid gaps. For a general UI kit, “complete” should probably mean “documented stable subset with tests,” not “full browser-equivalent flex/grid.”

- Recipes currently return small bundles with `node`, `surfaces`, and route functions. That is a useful seed, but there is no larger composition/router abstraction for many widgets. As the widget set grows, event routing and state ownership may become the real integration bottleneck.

- Documentation is still not trustworthy as a completion signal. `lua/ui/README.md` references Love examples such as `examples/ui_love_demo`/`ui_studio_demo`, but the current `examples/ui/` tree only shows SDL demos. This mismatch is important for making the library usable by others.

- Test coverage is still thin for a UI kit. Current UI tests cover facade/basic lowering/runtime smoke and SDL paint smoke, but not layout golden cases, interaction reducer edge cases, text editing behavior, scroll invariants, focus traversal, content-store invalidation, or backend parity.

### What “Complete” Should Mean Here

For this codebase, “complete” should mean:

- Stable typed contracts for authoring, layout, rendering, interaction, input, text, and session lifecycle.
- A documented supported layout subset with tests.
- Canonical reusable widgets with clear model/event/state contracts.
- Backend parity for declared primitives.
- A reliable text/input story across SDL/session/direct-host usage.
- Deterministic ID, focus, scroll, and event-routing invariants.
- Examples that exercise real app composition, not only probes.
- Tests covering both pure phases and backend smoke paths.

### Sequencing Implications

- Input/focus/state contracts should be clarified before growing many widgets, or each widget will encode incompatible conventions.
- Layering/popups/modal semantics should be understood before menus/tooltips/select boxes.
- Text backend/session registration should be made reliable before treating text input as a standard widget.
- Layout semantics need golden tests before broader component work depends on subtle flex/grid behavior.
- Documentation/examples should be corrected alongside capability claims, because the README currently overstates available demos.

### Knowledge Gaps

- Whether Love remains a supported backend target or SDL3 is the primary backend.
- Whether accessibility/semantic roles are in scope for “general-purpose.”
- Expected performance budget for large trees/text-heavy UIs.
- Desired boundary between typed ASDL rendering and host-direct overlay drawing.

## Approach-proposer Output — 2026-06-13 23:00:40

### Approach A: Contract-First Typed Kernel

- **Core idea**: Stabilize the typed UI pipeline and interaction semantics before expanding the widget catalog.
- **Make stable first**: `Auth → Layout → View → Runtime → Interact` contracts, IDs, keyboard input, focus, pointer capture, state propagation, text/session lifecycle.
- **Key changes**:
  - Extend `lua/ui/asdl.lua` with first-class keyboard/input events, possibly focus scopes and pointer capture.
  - Update `lua/ui/interact.lua`, `lua/ui/runtime.lua`, `lua/ui/session.lua`, and SDL host glue to route those typed events.
  - Add automatic bridge from `Interact.Model` to style state used by lowering/rendering.
  - Harden ID uniqueness, scroll/focus invariants, text backend registration, and env/theme defaults.
- **Artifacts produced**:
  - `lua/ui/CONTRACT.md` or updated README section defining stable phase contracts.
  - Golden tests for layout/render/interaction reducers.
  - Backend-independent interaction test fixtures.
  - Default theme/env factory documentation.
- **Tradeoff**: Optimizes for long-term coherence and ASDL discipline; sacrifices speed of visible widget delivery.
- **Risk**: The contract could be over-designed before enough real controls stress it.
- **Rough sketch**:
  - Define stable public lifecycle: author tree, lower, measure, render, runtime report, interaction step.
  - Add typed keyboard/focus/pointer-capture semantics.
  - Add interaction-state-to-style-state propagation.
  - Add invariant checks for duplicate IDs and focus/scroll routing.
  - Build a small reference widget set only after contracts are stable.

---

### Approach B: Widget-Catalog-First Productization

- **Core idea**: Treat the UI kit as incomplete until it ships reusable controls and examples, using real widgets to force API stabilization.
- **Make stable first**: Canonical widget API: model shape, event return values, IDs, styling hooks, composition pattern, recipe/widget boundary.
- **Key changes**:
  - Expand `lua/ui/widgets/` with sliders, knobs, toggles, buttons, menus, meters, value drags, scroll panels, text fields, and simple forms.
  - Standardize widget return contracts around `{ node, events, surfaces/state/apply }` or a similar convention.
  - Promote useful recipes into stable widgets where appropriate.
  - Add a synth-oriented demo app exercising controls, meters, text input, layout, and session redraw.
- **Artifacts produced**:
  - `lua/ui/widgets/README.md` with per-widget model/event contracts.
  - A widget gallery/demo under `examples/ui/`.
  - Snapshot/smoke tests for every canonical widget.
  - A “building custom widgets” guide.
- **Tradeoff**: Optimizes for practical usability and immediate app-building; sacrifices early purity of the lower-level contracts.
- **Risk**: Widgets may bake in inconsistent routing/state conventions if the underlying interaction model remains under-specified.
- **Rough sketch**:
  - Define one canonical widget authoring shape.
  - Build primitive controls: button, toggle, slider, knob, text input, meter.
  - Add composite controls: menu, select, panel, toolbar, property row.
  - Use examples to expose missing interaction/layout needs.
  - Backfill contracts/tests from patterns that survive real usage.

---

### Approach C: Platform/Backend-First UI Runtime

- **Core idea**: Complete the UI kit by making SDL3/runtime/text/rendering/layer behavior a dependable platform before focusing on higher-level widgets.
- **Make stable first**: Backend driver contract, render-op semantics, text backend registration, HiDPI/env behavior, layers/popups/clipping, paint/image/canvas capabilities.
- **Key changes**:
  - Formalize the backend driver interface used by `lua/ui/runtime.lua`, `runtime_sdl3.lua`, and possibly `runtime_love.lua`.
  - Add conformance tests for paint primitives, clipping, transforms, scrolling, text measurement, cursors, and input normalization.
  - Introduce a typed layer/top-level overlay model for popups, menus, tooltips, modals, and drag previews.
  - Clarify whether Love remains supported or SDL3 becomes the primary backend.
- **Artifacts produced**:
  - Backend conformance suite.
  - `lua/ui/BACKEND_CONTRACT.md`.
  - SDL3 runtime examples for paint, text, popups, drag/drop, and HiDPI.
  - Performance probes/benchmarks for render ops and text-heavy UI.
- **Tradeoff**: Optimizes for reliable rendering/session behavior and backend parity; sacrifices immediate expansion of app-level abstractions.
- **Risk**: Could spend too much effort on backend polish before the public widget API is known.
- **Rough sketch**:
  - Define required backend capabilities and optional extensions.
  - Add tests comparing generic runtime expectations to SDL3 behavior.
  - Make text registration/session behavior automatic and unsurprising.
  - Add layer/overlay semantics for UI elements that escape parent clipping.
  - Build widgets later on top of the stabilized runtime platform.

---

### Comparison

- **A** starts from typed architecture and makes the semantic core stable first.
- **B** starts from end-user controls and lets real widgets shape the public API.
- **C** starts from the runtime/backend platform and makes drawing, text, layers, and session behavior dependable first.

Each produces a different completion artifact: **A** yields contracts and invariants, **B** yields a usable widget catalog and demos, **C** yields backend conformance and runtime guarantees.

## Critique Output — 2026-06-13 23:02:08

### Approach A: Contract-First Typed Kernel

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 2/5 | It touches many modules, but mainly to clarify boundaries between `Auth`, `Layout`, `View`, `Runtime`, `Interact`, session, and SDL glue. The goal reduces implicit coupling. |
| **Cohesion** | 5/5 | Strong separation of responsibilities: schema, lowering, rendering, interaction, session, text lifecycle, and state propagation each become explicit contracts. |
| **Migration cost** | 4/5 | First-class keyboard input, pointer capture, state propagation, ID invariants, and text/session fixes likely require cross-cutting changes. |
| **Philosophy fit** | 5/5 | Best aligned with Lalin’s ASDL-first design: explicit typed meaning, stable phase boundaries, fail-loud invariants, and testable reducers. |
| **Risk** | 3/5 | Main risk is overdesigning before enough real controls exist. But the known gaps — keyboard, focus, IDs, state bridge, text registration — are already concrete. |
| **Testability** | 5/5 | Highly testable through pure layout/render/interact fixtures, reducer tests, ID invariant checks, and backend-independent event reports. |

**Verdict**: **Strong yes**
**Key concern**: Keep the contract grounded in actual widget needs, especially sliders/knobs/text fields/menus, so the kernel does not become abstract architecture detached from product use.

---

### Approach B: Widget-Catalog-First Productization

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Without stable interaction/state/input contracts, widgets will likely bind directly to current quirks in recipes, `Interact.Model`, host events, and styling conventions. |
| **Cohesion** | 3/5 | It improves product cohesion at the widget layer, but risks mixing event routing, state ownership, styling, redraw policy, and backend assumptions inside each widget. |
| **Migration cost** | 3/5 | Initial cost is moderate, but later correction could be expensive if many widgets bake in inconsistent contracts. |
| **Philosophy fit** | 3/5 | Practical, but weaker fit with Lalin’s “ASDL is the architecture” principle unless widget semantics quickly become typed and explicit. |
| **Risk** | 4/5 | Highest risk of accumulating conventions that work in demos but become hard to reconcile across focus, keyboard, drag, popups, text, and state styling. |
| **Testability** | 3/5 | Widget smoke/snapshot tests are useful, but without lower-level interaction contracts they may validate behavior rather than architecture. |

**Verdict**: **Yes with caveats**
**Key concern**: A canonical widget contract must be established immediately; otherwise this approach will create a fragmented UI kit rather than a stable one.

---

### Approach C: Platform/Backend-First UI Runtime

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Formalizing backend contracts can reduce runtime/backend coupling, but layer/popups/text/HiDPI semantics may force changes upward into `View`, session, and interaction. |
| **Cohesion** | 4/5 | Good cohesion around rendering, backend conformance, text, clipping, overlays, and platform guarantees. Less complete at the app/widget contract layer. |
| **Migration cost** | 3/5 | Moderate-to-high depending on whether layers/popups alter render stream semantics. SDL fixes alone are manageable; typed overlay semantics are broader. |
| **Philosophy fit** | 4/5 | Fits well if backend capabilities are expressed as typed contracts and conformance tests. Slightly less central than A because it starts from platform behavior rather than semantic UI meaning. |
| **Risk** | 3/5 | Risk is spending effort polishing SDL/runtime details before the public widget and interaction model is settled. |
| **Testability** | 4/5 | Backend conformance, paint/text/input smoke tests, and render-op fixtures are practical, though visual parity remains harder than pure reducer tests. |

**Verdict**: **Yes with caveats**
**Key concern**: Backend work should not define app semantics accidentally; layers, text, input, and popups need to remain part of the typed UI contract, not SDL-only behavior.

---

### Summary

- **Recommended**: **Approach A**. It best matches Lalin’s ASDL-first architecture and addresses the real remaining blockers: input, focus, state propagation, IDs, pointer capture, text/session lifecycle, and testable phase contracts. It gives the strongest foundation for a complete general-purpose UI kit.

- **Dark horse**: **Approach B**. It has the most immediate product upside because users need actual controls and examples. But it should only win if the project prioritizes fast synth UI delivery over long-term architectural stability.

- **Avoid**: **Approach B as the primary architecture path**. Building many widgets before stabilizing interaction and state contracts risks producing inconsistent controls that later require painful migration.

If a hybrid decision is allowed, the safest one is **A as the controlling architecture**, with **B used as validation pressure** through a small reference widget set, and **C reserved for backend conformance where it blocks those contracts.**

## Documenter Output — 2026-06-13 23:03:39

# Architecture Decision: Complete `lua/ui` with a Contract-First Typed Kernel

**Workflow:** `wf-a6d2de07`
**Status:** Decided
**Decision:** Approach A controls: contract-first typed kernel. Validate the contract with a small reference widget set from Approach B, and perform backend conformance work from Approach C where it blocks the typed contracts.

## Goal

Enable `lua/ui` to become a general-purpose UI kit by stabilizing its typed authoring, layout, rendering, runtime, interaction, input, text, and session contracts before expanding the widget catalog. The objective is not merely to draw SDL3 demos, but to make the UI pipeline reliable enough that reusable controls, synth-oriented interfaces, text input, focus, drag/drop, scrolling, styling, and backend rendering all operate through explicit ASDL-shaped semantics.

## Incentives

This matters because `lua/ui` already has a coherent compiler-like pipeline, but the remaining incompleteness is concentrated at contract boundaries rather than at isolated drawing primitives. Scout findings showed a strong `Auth → Layout → View → Runtime → Interact` flow and working SDL3 support, but also highlighted missing synth controls, thin tests, stale documentation, weak keyboard integration, and text/session footguns. Knowledge-builder analysis refined that picture: several earlier SDL3 primitive gaps have since been fixed, but the deeper risks remain around implicit UI-kit conventions — keyboard events are not first-class `Interact.Raw` ASDL values, interaction state is not automatically bridged into style state, IDs are a hidden global invariant, focus order is underspecified, text rendering/editing partly bypasses the main op stream, and examples/tests do not yet prove general-purpose readiness.

The chosen path prevents a widget library from growing around unstable conventions. Sliders, knobs, menus, meters, text fields, and synth controls all depend on consistent answers for IDs, focus, keyboard routing, pointer capture, scroll state, hover/active/selected/disabled styling, redraw scheduling, and backend text/paint behavior. Stabilizing those contracts first fits Lalin’s broader philosophy: explicit ASDL meaning, fail-loud invariants, typed phase boundaries, and testable reducers.

## Current State

`lua/ui` is organized around an ASDL-first immediate-mode UI pipeline.

The core schema lives in `lua/ui/asdl.lua`. It defines typed modules for authored trees, styling, layout, view operations, interaction, text, paint, and session data. Important existing types include:

```lua
Auth.Node =
    Box(...)
  | Text(...)
  | TextRef(...)
  | Paint(...)
  | Scroll(...)
  | WithState(...)
  | WithInput(...)
  | WithDragSource(...)
  | WithDropTarget(...)
  | WithDropSlot(...)
  | Fragment(...)
  | Empty

View.Kind =
    KBox
  | KText
  | KPaint
  | KPushClipRect
  | KPopClip
  | KPushTx
  | KPopTx
  | KPushScroll
  | KPopScroll
  | KHit
  | KFocus
  | KCursor
  | KDragSource
  | KDropTarget
  | KDropSlot

Interact.Raw =
    PointerMoved(...)
  | PointerPressed(...)
  | PointerReleased(...)
  | WheelMoved(...)
  | FocusNext
  | FocusPrev
  | ActivateFocus
  | CancelPointer
```

The public facade in `lua/ui/init.lua` exports the main modules. Authored trees are created through `lua/ui/build.lua`, which provides immediate-mode builders producing `Auth.Node` values. `lua/ui/lower.lua` lowers authored trees into layout nodes, resolving style and structural features such as scroll compatibility. Layout measurement and planning are handled by `lua/ui/measure.lua`, `lua/ui/plan.lua`, and `lua/ui/render.lua`. Rendering emits a relative `View.Op` stream.

The current data flow is:

```text
Auth/Compose
  → lower
  → Layout.Node
  → measure / plan / render
  → View.Op*
  → runtime.run(driver, opts, ops...)
  → Interact.Report
  → interact.step(model, report, raw)
  → semantic events + next Interact.Model
```

`lua/ui/runtime.lua` consumes the `View.Op` stream through a backend driver. It performs drawing and records hit, focus, scroll, drag source, drop target, and drop slot facts into an `Interact.Report`. `lua/ui/interact.lua` reduces backend-independent raw interaction values against the report and the previous `Interact.Model`, producing semantic interaction events and an updated model.

SDL3 support exists and is substantial. Relevant files include:

- `lua/ui/_sdl3.lua` — SDL3/SDL_ttf FFI bindings and constants.
- `lua/ui/host_sdl3.lua` — SDL event normalization, clipboard, IME/text input, window lifecycle, frame begin/present.
- `lua/ui/runtime_sdl3.lua` — SDL3 render backend for `View.Op` streams.
- `lua/ui/text_sdl3.lua` — SDL3_ttf text layout, hit testing, range queries, and IME support.
- `lua/ui/session.lua` — multi-window event/redraw loop.
- `lua/ui/session_sdl3.lua` — SDL3 session wrapper.

The text subsystem is comparatively advanced. `lua/ui/text.lua`, `text_nav.lua`, `text_edit.lua`, `text_field.lua`, and `text_field_view.lua` support text layout, caret movement, selection, clipboard operations, IME composition, hit testing, and editable field behavior. Existing examples under `examples/ui/` include SDL text probes and text-field demos.

Paint support is defined in `lua/ui/paint.lua` with builders for lines, polylines, polygons, circles, arcs, beziers, meshes, and images. The Love backend in `lua/ui/runtime_love.lua` historically implemented a broader set of paint features, while earlier scout findings found SDL incomplete. Knowledge-builder analysis observed that current SDL3 code has since improved: missing key constants such as PageUp/PageDown/Tab/Space, rounded/capsule boxes, filled polygons/circles, mesh, image, and theme/env helpers now appear present. Therefore the current blocking issue is no longer simply “SDL cannot draw enough primitives”; it is that the contracts around input, state, lifecycle, backend parity, and widgets are not yet stable enough to call the library complete.

The major limitations in the current state are:

1. **Keyboard/input is not fully ASDL-shaped.**
   Backend-normalized Lua key tables and `ui.input` constants exist, but `Interact.Raw` remains mostly pointer, wheel, and abstract focus actions. Text fields and scroll behavior handle keys through side APIs. This violates the desired explicit-ASDL boundary.

2. **Interaction state does not automatically drive style state.**
   Style conditions include `hover`, `focus`, `active`, `selected`, and `disabled`, and authored trees can use `Auth.WithState`. `ui.interact` computes hover, focus, press, drag, and related facts. There is not yet a canonical bridge that applies `Interact.Model` to `Style.State` during lowering or rendering.

3. **IDs are a hidden global invariant.**
   `Core.IdValue(string)` is used for focus, hit routing, scroll state, drag/drop surfaces, and recipe maps. Builders prevent duplicate IDs only within a single builder call, not across the full authored tree. Duplicate IDs can silently collide across independent subsystems.

4. **Pointer capture and nested interaction semantics are incomplete.**
   Runtime hit selection exposes a topmost `hover_id` by default, with optional hit collection. Classification primarily uses the current frame’s report. If a pressed or dragged node disappears, moves, or reorders, semantics depend on current geometry and stable IDs rather than an explicit capture invariant.

5. **Focus is stream-order only.**
   The current model can traverse focus, but it lacks stronger contracts for disabled skipping, focus scopes, modal scopes, tab groups, or custom order. This matters for menus, text fields, dialogs, and synth panels.

6. **Popups and overlays stress the tree model.**
   The current render stream is structurally clipped by ancestry. Menus, tooltips, context menus, modals, drag previews, and overlays may need typed layer behavior so they can escape parent clipping without becoming SDL-only special cases.

7. **Text lifecycle has a registration footgun.**
   `ui.session` creates an SDL text system, but layout can fall back to approximate measurement unless the text system is registered under the expected key. This makes text behavior depend on session options rather than an unsurprising default lifecycle contract.

8. **Widgets are not yet a canonical catalog.**
   The tree has recipes and text widgets, but no complete general-purpose set of controls such as button, toggle, slider, knob, fader, meter, menu, tooltip, popup, property row, or synth-specific value drag. More importantly, there is no stable widget contract for model shape, event return values, IDs, styling hooks, state ownership, or routing.

9. **Tests and documentation are not yet truth-bearing enough.**
   Existing UI tests are thin compared to the number of contracts involved. The README contains stale references to Love demos that do not match the current `examples/ui/` contents. A general-purpose UI kit needs tests for pure phases, reducers, layout golden cases, interaction invariants, text editing, scroll behavior, focus traversal, content-store invalidation, and backend smoke/conformance.

## Chosen Target

### Approach

The chosen architecture is **Approach A: Contract-First Typed Kernel**.

Approach A controls all subsequent completion work. The stable target is the typed kernel and lifecycle:

```text
Auth.Node
  → Layout.Node
  → View.Op
  → Runtime driver execution
  → Interact.Report
  → Interact.Model / semantic events
  → next authored tree
```

The decision explicitly incorporates two validating pressures:

- From **Approach B**, build only a **small reference widget set** early enough to validate the contracts against real controls. This prevents the kernel from becoming abstract and untested by actual widget needs.
- From **Approach C**, perform **backend conformance work where it blocks the typed contracts**, especially around text registration, input normalization, render-op semantics, layers/overlays, clipping, paint, HiDPI/env behavior, and SDL3 runtime behavior.

Approach A was chosen because it best matches Lalin’s ASDL-first architecture and directly addresses the remaining blockers identified by the workflow: keyboard/input typing, focus semantics, pointer capture, interaction-state styling, ID invariants, text/session lifecycle, and testable reducer/layout/runtime boundaries.

### Architecture

The target architecture keeps the existing phase structure but makes each phase’s public contract explicit and testable.

#### 1. ASDL schema remains the source of UI meaning

`lua/ui/asdl.lua` remains the authoritative definition of meaningful UI state. Completion work should extend existing typed modules rather than encoding semantics in stringly host events, ad hoc callbacks, or backend-specific side tables.

Key existing schema areas:

- `Auth.Node` — authored UI structure.
- `Layout.Node` — lowered layout tree.
- `View.Op` / `View.Kind` — render/runtime operation stream.
- `Interact.Raw` — backend-independent raw input.
- `Interact.Report` — facts collected from runtime execution.
- `Interact.Model` — persistent interaction state.
- `Style.State` / style conditions — hover/focus/active/selected/disabled styling.
- `Text` and `Paint` modules — typed text and paint vocabulary.

The contract-first target requires first-class typed representation for currently implicit or side-channel concepts:

- Keyboard input and text-relevant key actions.
- Focus traversal and activation semantics.
- Pointer capture / pressed-pointer ownership.
- Interaction-state-to-style-state propagation.
- ID uniqueness and routing invariants.
- Text backend/session registration lifecycle.
- Overlay/layer semantics where popups, menus, tooltips, modals, or drag previews require escape from parent clipping.

#### 2. Input and interaction become backend-independent typed contracts

`lua/ui/interact.lua`, `lua/ui/runtime.lua`, `lua/ui/session.lua`, `lua/ui/host_sdl3.lua`, and SDL glue should route input through ASDL-shaped values instead of letting each widget interpret backend tables independently.

The target contract is:

```text
host_sdl3 normalized events
  → typed Interact.Raw values
  → interact.step(model, report, raw)
  → semantic interaction events
  → next Interact.Model
```

Keyboard input must become part of the same reducer story as pointer and wheel input. Existing abstract actions such as `FocusNext`, `FocusPrev`, `ActivateFocus`, and `CancelPointer` remain part of the model, but the keyboard path that produces them must be explicit and testable.

This contract is especially important for:

- Text fields.
- Sliders/faders/knobs.
- Menus/select boxes.
- Buttons/toggles.
- Scroll panels.
- Modal or popup focus behavior.
- Synth keyboard shortcuts.

#### 3. Style state is derived consistently from interaction state

The current system has rich style conditions and explicit `Auth.WithState`, but application is manual. The target architecture adds a canonical bridge from `Interact.Model` and `Interact.Report` facts into style state used during lowering/rendering.

The important invariant is that common visual states — hover, focus, active/pressed, selected, disabled — are not reimplemented differently by each widget. Widgets may still author explicit state where appropriate, but the kernel owns the consistent mapping from interaction facts to `Style.State`.

This protects controls from diverging in behavior: a button, slider thumb, text field, and menu item should all use the same hover/focus/active semantics unless they explicitly opt into a documented variation.

#### 4. IDs become explicit validated invariants

`Core.IdValue(string)` remains the shared identity mechanism, but duplicate and unstable IDs must become fail-loud contract violations rather than silent collisions.

The target contract covers all subsystems that consume IDs:

- Hit routing via `WithInput` / `KHit`.
- Focus routing via `KFocus`.
- Scroll state via `Scroll`.
- Drag/drop via `WithDragSource`, `WithDropTarget`, `WithDropSlot`.
- Widget surface maps and recipe route tables.
- Text field identity and content-store references.

The architecture requires full-tree ID validation at the appropriate boundary, not just duplicate checks inside one builder call. This supports deterministic behavior for focus, scroll offsets, pressed state, drag ownership, and widget routing.

#### 5. Pointer capture is part of interaction semantics

The reducer must distinguish “currently hovered” from “currently captured/pressed/dragged.” Pointer ownership should not be inferred solely from the current frame’s geometry after a node moves, disappears, or reorders.

The target model keeps pointer capture in `Interact.Model` or an equivalent typed interaction state, and `interact.step` uses that state to decide release, cancel, drag, and activation behavior. Runtime hit reports remain frame-local facts; capture is persistent semantic state.

This is required for robust sliders, knobs, drag handles, reorderables, scrubbers, and synth value drags.

#### 6. Text/session lifecycle becomes unsurprising

`lua/ui/session.lua`, `lua/ui/session_sdl3.lua`, `lua/ui/text.lua`, and `lua/ui/text_sdl3.lua` must define a reliable lifecycle for text systems.

The target contract is:

- If an SDL text system exists for a session, text layout should use it without requiring callers to know a hidden `text_key` registration convention.
- Approximate text layout fallback should be explicit and testable, not an accidental result of missing registration.
- Text input, IME, selection, clipboard, caret movement, and layout should integrate with the same typed input/session model where possible.

This preserves the strong existing text-editing implementation while removing the registration footgun.

#### 7. Reference widgets validate the kernel, not replace it

A small widget set from Approach B is part of the chosen target only as validation pressure. The purpose is to prove the kernel contracts against real controls before broad catalog expansion.

The reference set should cover distinct interaction patterns:

- A button or toggle for activation/focus/hover/active state.
- A slider/fader or knob for pointer capture and continuous value changes.
- A text input using the existing text-field stack.
- A scroll panel or list for scroll/focus interaction.
- A simple meter or paint-backed control for render/backend validation.

These widgets should establish a canonical widget shape around authored `Auth.Node` output, stable IDs, semantic events, and model/state ownership. They should not become a large catalog before the underlying contracts are stable.

#### 8. Backend conformance is performed where it blocks contracts

Approach C is included only where backend behavior is necessary to uphold typed contracts.

Backend work is required for:

- SDL3 event normalization into typed input.
- Render-op semantics for clipping, transforms, scrolling, cursors, hit regions, and focus regions.
- Text measurement and text rendering lifecycle.
- Paint primitive parity for declared primitives.
- Layer/overlay behavior if popups, menus, tooltips, modals, or drag previews become part of the typed contract.
- HiDPI/env behavior where `Env.Density` or related fields are declared as meaningful.
- Backend smoke/conformance tests for SDL3 and any still-supported Love path.

The backend must not define app semantics accidentally. If a behavior matters to widgets or interaction, it belongs in the typed UI contract and is then implemented by the backend.

### Tradeoffs Acknowledged

This decision sacrifices immediate breadth of visible widgets. A large catalog of knobs, sliders, menus, meters, forms, popups, and synth controls will come later than it would under a widget-catalog-first plan.

That tradeoff is accepted because building many widgets before stabilizing input, focus, pointer capture, state styling, IDs, text lifecycle, and event routing would likely bake inconsistent conventions into each control. The later migration cost would be higher than the cost of stabilizing the kernel first.

The decision also accepts some backend work without making backend polish the primary goal. SDL3 conformance, paint behavior, text lifecycle, and layer semantics are addressed when they block typed contracts, not as an open-ended rendering-platform project.

Finally, the decision accepts that a small reference widget set is necessary to keep the typed kernel grounded. The kernel must be validated by real controls, but those controls serve the contract; they do not define independent ad hoc conventions.

### Risks Acknowledged

The main risk is over-designing the kernel before enough real widgets stress it. This is mitigated by the explicit inclusion of a small reference widget set covering activation, text input, continuous pointer capture, scrolling, and paint-backed display.

A second risk is cross-cutting migration cost. Extending `Interact.Raw`, updating `ui.interact`, routing through `ui.session` and `host_sdl3`, adding state propagation, validating IDs, and hardening text registration will touch many modules. The critique accepted this cost because it clarifies boundaries rather than increasing hidden coupling.

A third risk is that backend work could accidentally define semantics outside ASDL. The decision constrains backend conformance to typed contracts: layers, input, text, paint, clipping, and session behavior must be specified in the UI architecture before becoming SDL-only behavior.

A fourth risk is under-delivering visible product value while contracts are being stabilized. The reference widget set and examples are included specifically to produce practical validation artifacts while preserving the contract-first direction.

## Edit-planner Output — 2026-06-13 23:08:54

### Precondition Checks

- Confirm current `lua/ui/asdl.lua` still has:
  - `Auth.Node` at lines 450-479.
  - `Layout.Node` at lines 723-768.
  - `View.Kind` / `View.Op` at lines 771-789.
  - `Interact.Raw/Event/Model/State` at lines 792-934.
- Confirm current `lua/ui/interact.lua` still has reducer structure:
  - `classify_events` at lines 125-275.
  - `apply_event` at lines 356-393.
  - public constructors at lines 395-541.
- Confirm current text registration footgun still exists:
  - `session.lua` registers text only when `text_key ~= nil` at lines 64-85.
  - `text.lua` falls back to approximate layout when `system_key == nil` or unregistered at lines 778-785.
- Run baseline checks before editing:
  - `luajit tests/test_ui_smoke.lua`
  - `SDL_VIDEODRIVER=dummy luajit tests/test_ui_sdl3_paint.lua`
  - `AUTO_QUIT_MS=50 SDL_VIDEODRIVER=dummy luajit examples/ui/text_field_sdl3_demo.lua`

---

## Files to Modify

### `lua/ui/asdl.lua`

**Goal**: Make input, focus, pointer capture, layers/overlays/modals, and widget/runtime facts explicit ASDL vocabulary.

**Edit blocks**

1. **Lines 7-29**: Modify `Core` / `Env`
   - Add typed identity helpers if needed:
     - `Core.IdPath` or equivalent diagnostic-friendly ID path records.
   - Extend density semantics if backend scaling will be meaningful.
   - Do not remove `Core.NoId` or `Core.IdValue`.

2. **Lines 450-479**: Modify `Auth.Node`
   - Before:
     ```lua
     | WithState(...)
     | WithInput(...)
     | WithDragSource(...)
     | WithDropTarget(...)
     | WithDropSlot(...)
     | Fragment(...)
     | Empty
     ```
   - After: add typed authored wrappers for:
     - `Layer(id, kind, child)`
     - `Overlay(id, anchor_id?, placement?, modal?, child)`
     - `FocusScope(id, policy, child)`
     - optional `Disabled(id, child)` / state-specific wrapper only if needed by kernel.
   - Preserve existing constructors for compatibility.

3. **Lines 555-768**: Modify `Layout.Node`
   - Add lowered equivalents of new authored layer/focus/modal nodes.
   - Add focus policy/scope fields where runtime needs them.
   - Keep `Layout.Scroll` structural behavior unchanged.

4. **Lines 771-789**: Modify `View.Kind` / `View.Op`
   - Before:
     ```lua
     Kind = KBox | KText | KPaint | KPushClipRect | KPopClip | ...
          | KHit | KFocus | KCursor
          | KDragSource | KDropTarget | KDropSlot
     ```
   - After: add:
     - `KPushLayer`, `KPopLayer`
     - `KModalBarrier`
     - `KFocusScope`, `KEndFocusScope` if scopes are stream-scoped
     - fields needed for layer index, modal flag, focus policy, and semantic hit category.
   - Quirk: `View.Op` is a single tuple; add nullable fields rather than side tables.

5. **Lines 792-934**: Replace/extend `Interact`
   - Add typed input:
     - `Key`, `Modifiers`, `KeyEvent`, `TextInput`, `TextEditing`.
     - `Raw = KeyPressed(...) | KeyReleased(...) | TextInput(...) | TextEditing(...) | FocusLost | PointerCancelled`, while keeping old raw constructors.
   - Add pointer capture:
     - model field `capture_id`.
     - events `SetCapture`, `ReleaseCapture`, `CancelCapture`.
   - Add hit stack/layer facts:
     - report fields for `hit_stack`, `active_layer`, modal barrier, focus scopes.
   - Add widget-grade semantic events:
     - activation, value intent, cancel, text input routing, focus enter/leave as needed.

**Patterns to enforce**
- All meaningful UI state belongs in ASDL, not strings or backend tables.
- Preserve old constructors unless consciously deprecated in `MIGRATION.md`.

**Danger zones**
- Any ASDL constructor rename breaks PVM identity/cache behavior.
- Avoid wildcard matching in downstream phase tables; every new constructor needs explicit handling.

---

### `lua/ui/input.lua`

**Goal**: Become the backend-independent typed input conversion layer.

**Edit blocks**

1. **Lines 1-19**: Modify constants
   - Keep existing string constants as compatibility aliases.
   - Add typed constructors:
     ```lua
     M.key_return()
     M.key_escape()
     M.modifiers(opts)
     M.raw_key_down(key, mods, repeat_)
     M.raw_text_input(text)
     ```
   - Add host event conversion:
     ```lua
     M.raw_from_host_event(ev)
     M.raw_many_from_host_event(ev)
     ```

2. **After line 19**: Add focus keymap
   - Map:
     - `Tab` → `FocusNext`
     - `Shift+Tab` → `FocusPrev`
     - `Return`/`Space` → `ActivateFocus`
     - `Escape` → `CancelPointer` / cancel modal.
   - Quirk: text-editing widgets must be able to consume keys before generic activation if focused edit target owns input.

**Danger zones**
- Do not make SDL constants leak into this file.
- Preserve existing `ui.input.KeyLeft` string aliases for current text code.

---

### `lua/ui/id.lua` *(new)*

**Purpose**: Full-tree ID validation and collection.

**Contents sketch**
- `collect_auth(node, opts)`
- `collect_layout(node, opts)`
- `collect_compose(node, opts)`
- `validate_auth(node, opts) -> ok, errors`
- `assert_auth(node, opts)`
- Duplicate detection across:
  - authored node IDs
  - `WithInput`
  - scroll IDs
  - drag/drop IDs
  - layer/overlay/focus-scope IDs
  - generated widget sub-IDs
  - content-store references when supplied.
- Error format must include path like:
  - `root.children[3].WithInput(id="gain") duplicates root.children[1].Scroll`.

---

### `lua/ui/state.lua` *(new)*

**Purpose**: Canonical bridge from `Interact.Model`/`Interact.Report` to `Style.State`.

**Contents sketch**
- `state.for_id(id, model, report, opts)`
- `state.provider(model, report, opts)`
- `state.apply_to_auth(node, provider, opts)`
- Merge rules:
  - `hovered`: report/model hover ID.
  - `focused`: model focus ID.
  - `active`: pressed/captured/dragging source ID.
  - `selected`: explicit widget/app state.
  - `disabled`: explicit widget/app state.
- `Auth.WithState` must merge with derived state, not replace it.

---

### `lua/ui/lower.lua`

**Goal**: Lower authored trees with canonical interaction-derived style state.

**Edit blocks**

1. **Lines 18-31**: Modify state merge/resolve
   - Before:
     ```lua
     local function merge_state(parent, child)
     local function resolve_style(tokens, theme, env, state)
     ```
   - After:
     - Support state provider callback keyed by current node ID.
     - Merge order:
       1. parent inherited state
       2. derived per-ID interaction state
       3. explicit `Auth.WithState`
     - Keep `normalize.no_state` fallback.

2. **Lines 37-40 / 117-135**: Modify child lowering helpers
   - Pass `opts` or state provider through all recursive calls.

3. **Lines 169-231**: Modify wrappers
   - `Auth.WithState`: merge explicit state.
   - `Auth.WithInput` / drag/drop wrappers: ensure derived state is applied to their ID.

4. **Lines 274-365**: Modify node handlers
   - For `Auth.Box/Text/TextRef/Paint/Scroll`, resolve styles with derived state for `self.id`.
   - Add new handlers for `Auth.Layer`, `Auth.Overlay`, `Auth.FocusScope`.

5. **After current exports**: Add productized root helper
   ```lua
   M.root(auth, theme, env, opts)
   ```
   - Runs ID validation if `opts.validate_ids ~= false`.
   - Applies state provider from `opts.model/report`.
   - Returns lowered nodes.

**Danger zones**
- Existing `lower.phase(node, theme, env, state)` should remain usable for pure tests.
- Do not make lowering depend on backend/session state directly.

---

### `lua/ui/render.lua`

**Goal**: Emit complete view op stream for input, layers, modals, focus scopes, and overlays.

**Edit blocks**

1. **Lines 28-29**: Modify `make_op`
   - Add nullable fields needed by new `View.Op`.
   - Keep call sites readable; consider local helper builders for layer/focus ops.

2. **Lines 100-113**: Modify `append_input_ops`
   - Centralize role-to-hit/focus/cursor logic.
   - Add disabled/focus policy behavior.
   - Add edit-target metadata if needed.

3. **Lines 148-188**: Modify wrapper handlers
   - Add render handlers for new `Layout.Layer`, `Layout.Overlay`, `Layout.FocusScope`.
   - Emit push/pop layer ops around child render stream.

4. **Lines 248-278**: Preserve scroll op semantics
   - Ensure overlays can escape parent clipping only through explicit layer semantics, not by weakening scroll clipping globally.

**Danger zones**
- Op order defines z-order and hit order.
- Do not bypass `View.Op` by backend-specific overlay callbacks.

---

### `lua/ui/runtime.lua`

**Goal**: Runtime report becomes complete interaction fact source.

**Edit blocks**

1. **Lines 112-148**: Extend runtime state
   - Add layer stack, modal stack/barrier, focus scope stack, full hit stack.
   - Keep current transform/clip/scroll stacks intact.

2. **Lines 184-362**: Modify op handling
   - Existing `KHit`, `KFocus`, `KCursor`, drag/drop handlers must record layer/scope metadata.
   - New `KPushLayer/KPopLayer` changes z-order and optionally clip behavior.
   - New modal barrier suppresses lower-layer hit/focus/scroll candidates.
   - `collect_hits` should become default-safe for tests or replaced by explicit `hit_stack`.

3. **Lines 344-361**: Modify report constructor
   - Return extended `Interact.Report`.
   - Preserve old fields (`hover_id`, `scroll_id`, `focusables`) for compatibility helpers.

**Danger zones**
- Hit testing must still respect current clip stack unless a typed layer explicitly escapes.
- Modal barriers must block lower interaction facts but not erase rendering.

---

### `lua/ui/interact.lua`

**Goal**: Pure reducer supports typed keyboard, pointer capture, focus scopes, modals, drag/drop, and widget semantics.

**Edit blocks**

1. **Lines 19-43**: Modify focus helpers
   - Add scope-aware focus traversal.
   - Skip disabled/unfocusable entries.
   - Honor modal top layer.

2. **Lines 89-108**: Modify hit helpers
   - Use report hit stack/layer info instead of only topmost `hover_id`.
   - Preserve helpers `drag_source_at`, `drop_target_at`, `drop_slot_at`.

3. **Lines 125-275**: Rewrite `classify_events`
   - Pointer press:
     - set pointer
     - set hover
     - set focus if eligible
     - set pressed
     - set capture for pressed/captured target.
   - Pointer move:
     - if captured, route movement to capture ID even if pointer leaves geometry.
     - drag threshold uses capture/source ID.
   - Pointer release:
     - activation compares release against capture/pressed contract, not current hover only.
   - Keyboard:
     - typed key raw maps to focus next/prev/activate/cancel/scroll/value intents.
   - Text:
     - route `TextInput/TextEditing` to focused edit target.
   - Modal/focus-scope:
     - cancel closes/cancels active modal/popup semantics via events.

4. **Lines 356-393**: Modify `apply_event`
   - Add `capture_id`, focus-scope/model fields, modal active state if kernel owns it.
   - Keep scroll clamping via report.

5. **Lines 395-406**: Modify `M.model`
   - Add defaults for capture/focus scope/modal-related fields.

6. **Lines 496-525**: Add public raw constructors
   - `key_pressed`, `key_released`, `text_input`, `text_editing`, `pointer_cancelled`.

7. **Lines 534-540**: Modify `M.state`
   - Include active/capture-derived state or delegate to `ui.state`.

**Danger zones**
- Reducer must remain pure: no host calls, no widget callbacks.
- Event order must be deterministic and tested.

---

### `lua/ui/host_sdl3.lua`

**Goal**: SDL host events normalize into typed input while preserving host-table compatibility.

**Edit blocks**

1. **Lines 38-66**: Modify button/key normalization
   - Return typed/compatible keys from `ui.input`.
   - Add modifiers conversion helper.

2. **Lines 98-182**: Modify `normalize_event`
   - For each mouse/key/text event, attach:
     ```lua
     raw = input.raw_from_host_event(...)
     raws = input.raw_many_from_host_event(...)
     ```
   - Keep existing `type`, `key`, `x`, `y`, `window_id` fields.

3. **Lines 341-360**: Text input lifecycle
   - Ensure session/text widgets can call `set_text_input` and `set_text_input_rect` consistently.
   - Do not start/stop text input in widget draw code without session policy.

**Danger zones**
- SDL key constants stay in `_sdl3.lua` / host only.
- Do not require SDL for pure `ui.input` tests.

---

### `lua/ui/session.lua`

**Goal**: Session owns reliable text backend lifecycle and raw UI input routing.

**Edit blocks**

1. **Lines 64-85**: Fix text registration
   - Before:
     ```lua
     local text_key = opts.text_key
     if text_key ~= nil and shared_text_system ~= nil then
         text.register(text_key, shared_text_system)
     end
     ```
   - After:
     - Choose default key, e.g. `opts.text_key or ("session:" .. tostring(self/session id))`.
     - Register if text system exists unless explicitly disabled.
     - Store `session.text_key`.

2. **Lines 209-248**: Window creation
   - Store:
     - `window.text_system`
     - `window.text_key`
     - `window.interact_model` optional default
     - raw routing hooks.

3. **Lines 305-335**: Dispatch events
   - Convert host events to typed raw input via `ui.input`.
   - Offer default routing helper:
     ```lua
     window:on_raw_ui(raw)
     ```
   - Preserve `on_event`.

4. **Lines 450-469**: Close
   - Unregister default text key.
   - Close owned text system.
   - Ensure no stale registry entries.

**Danger zones**
- Avoid global text-key collision across multiple sessions.
- Approx fallback must be explicit, not accidental.

---

### `lua/ui/text.lua`

**Goal**: Make text system selection explicit and safe.

**Edit blocks**

1. **Lines 11-18**: Add default registry state
   - `local default_key = nil`
   - fallback policy flag if needed.

2. **Lines 778-799**: Modify `M.layout`
   - Before:
     ```lua
     if system_key == nil then return M.approx_layout(...) end
     if systems[system_key] == nil then return M.approx_layout(...) end
     ```
   - After:
     - If `system_key == nil`, use default key if set.
     - If missing system and fallback not allowed, error or return diagnostic depending option.
     - Keep `approx_layout` available explicitly.

3. **Lines 801-818**: Add APIs
   - `set_default(key)`
   - `default_key()`
   - `layout_approx(...)`
   - maybe `register_default(key, system)`.

**Danger zones**
- Existing tests using approximate layout should call explicit approx or run without default.
- Do not hide text backend in PVM cache keys.

---

### `lua/ui/runtime_sdl3.lua`

**Goal**: SDL backend conforms to documented runtime driver contract.

**Edit blocks**

1. **Lines 370-395**: Add capabilities
   - Expose:
     ```lua
     self.capabilities = { paint = ..., text = ..., layers = ..., images = ... }
     ```

2. **Lines 510-554**: `draw_rect`
   - Ensure contract names match generic runtime expectations.
   - Honor density/scaling if kernel defines it.

3. **Lines 556-632**: `draw_paint`
   - Keep existing primitives.
   - Add contract assertions/guards for image/mesh.
   - Ensure no primitive silently fails except documented optional missing resource.

4. **Add layer hooks if required**
   - `push_layer`, `pop_layer`, or no-op documented support if generic runtime handles layer ordering before driver calls.

---

### `lua/ui/runtime_love.lua`

**Goal**: Keep Love backend either conformant or explicitly optional.

**Edit blocks**
- Add same capability metadata as SDL.
- Align function names with `BACKEND_CONTRACT.md`.
- Add layer/clip/image/text behavior notes.
- If Love is not product-supported, mark unsupported paths loudly in docs/tests.

---

### `lua/ui/recipes/_core.lua`

**Goal**: Share canonical widget bundle/event contract.

**Edit blocks**

1. **Lines 1-5**: Require `ui.widget`.
2. **Lines 11-22**: Surface helpers
   - Detect duplicate surface IDs.
   - Use canonical ID string helpers from `ui.id`.

3. **Lines 35-55**: `bundle`
   - Preserve current shape:
     ```lua
     { node, surfaces, route_one, route_ui_event, route_ui_events }
     ```
   - Add canonical fields:
     - `kind`
     - `id`
     - `model`
     - `events`
     - `validate`.

---

### `lua/ui/widgets/_text_common.lua`

**Goal**: Bring text widgets under canonical widget/input/session contract.

**Edit blocks**

1. **Lines 20-31**: `require_id`
   - Validate ID via `ui.id`.
2. **Lines 41-76**: `build_shell`
   - Use `ui.widget.bundle`.
   - Use state bridge for focus/disabled styling.
3. **Lines 130-158**: `draw_overlay`
   - Use default session text key/system.
   - Avoid accidental approximate layout.
   - Ensure IME rect lifecycle is controlled by focused edit target.

---

### `lua/ui/widgets/init.lua`

**Goal**: Export complete general-purpose widget catalog.

**Edit block**

- Replace current two-entry table:
  ```lua
  return {
      text_input = ...,
      text_area = ...,
  }
  ```
- With exports for:
  - `button`
  - `toggle`
  - `checkbox`
  - `radio`
  - `slider`
  - `fader`
  - `value_drag`
  - `knob`
  - `meter`
  - `progress`
  - `list`
  - `tabs`
  - `menu`
  - `select`
  - `tooltip`
  - `popup`
  - `modal`
  - `panel`
  - `toolbar`
  - `property_row`
  - `split_pane`
  - `scroll_panel`
  - `canvas`
  - existing `text_input`, `text_area`.

---

### `lua/ui/init.lua`

**Goal**: Expose completed public API.

**Edit blocks**

1. **Lines 1-29**: Add exports:
   ```lua
   M.id = require("ui.id")
   M.state = require("ui.state")
   M.input = require("ui.input")
   M.widget = require("ui.widget")
   M.backend_contract = require("ui.backend_contract")
   ```
2. Preserve all existing exports.

---

### `lua/ui/README.md`

**Goal**: Replace stale restart notes with truth-bearing product docs.

**Edit blocks**

1. **Lines 1-80**: Replace status intro with completed architecture overview.
2. **Lines 80-160**: Update module inventory for new contract modules/widgets.
3. **Lines 160-213**: Replace stale demo references with actual examples:
   - `examples/ui/gallery_sdl3.lua`
   - `examples/ui/synth_sdl3_demo.lua`
   - `examples/ui/backend_conformance_sdl3.lua`
   - existing text/paint probes.
4. Add links to:
   - `CONTRACT.md`
   - `BACKEND_CONTRACT.md`
   - `widgets/README.md`
   - `MIGRATION.md`.

---

## New Files

### Docs
- `lua/ui/CONTRACT.md`
  - Complete kernel contract: phases, IDs, input, focus, capture, state, text, overlays, layout subset.
- `lua/ui/BACKEND_CONTRACT.md`
  - Backend driver, host, text, paint, image, layer, density, input conformance.
- `lua/ui/widgets/README.md`
  - Canonical widget API and catalog docs.
- `lua/ui/MIGRATION.md`
  - Compatibility/deprecation notes.

### Kernel modules
- `lua/ui/id.lua`
- `lua/ui/state.lua`
- `lua/ui/widget.lua`
- `lua/ui/backend_contract.lua`

### Widget catalog
- `lua/ui/widgets/button.lua`
- `lua/ui/widgets/toggle.lua`
- `lua/ui/widgets/checkbox.lua`
- `lua/ui/widgets/radio.lua`
- `lua/ui/widgets/slider.lua`
- `lua/ui/widgets/fader.lua`
- `lua/ui/widgets/value_drag.lua`
- `lua/ui/widgets/knob.lua`
- `lua/ui/widgets/meter.lua`
- `lua/ui/widgets/progress.lua`
- `lua/ui/widgets/list.lua`
- `lua/ui/widgets/tabs.lua`
- `lua/ui/widgets/menu.lua`
- `lua/ui/widgets/select.lua`
- `lua/ui/widgets/tooltip.lua`
- `lua/ui/widgets/popup.lua`
- `lua/ui/widgets/modal.lua`
- `lua/ui/widgets/panel.lua`
- `lua/ui/widgets/toolbar.lua`
- `lua/ui/widgets/property_row.lua`
- `lua/ui/widgets/split_pane.lua`
- `lua/ui/widgets/scroll_panel.lua`
- `lua/ui/widgets/canvas.lua`

### Tests
- `tests/test_ui_interact_contract.lua`
- `tests/test_ui_id_validation.lua`
- `tests/test_ui_state_bridge.lua`
- `tests/test_ui_overlay_layers.lua`
- `tests/test_ui_layout_golden.lua`
- `tests/test_ui_backend_contract.lua`
- `tests/test_ui_text_session.lua`
- `tests/test_ui_widgets_contract.lua`
- `tests/test_ui_widget_catalog.lua`
- `tests/test_ui_examples.lua`

### Examples
- `examples/ui/gallery_sdl3.lua`
- `examples/ui/synth_sdl3_demo.lua`
- `examples/ui/backend_conformance_sdl3.lua`

---

## Order of Operations

1. Write `CONTRACT.md` and `BACKEND_CONTRACT.md`.
2. Extend `asdl.lua` for input/focus/capture/layers.
3. Implement `input.lua`, `id.lua`, `state.lua`.
4. Wire state/ID/input through `lower.lua`, `render.lua`, `runtime.lua`, `interact.lua`.
5. Fix session/text lifecycle in `session.lua`, `session_sdl3.lua`, `text.lua`.
6. Add backend contract helpers and align SDL/Love runtimes.
7. Add `widget.lua`, refit recipes/text widgets.
8. Implement full widget catalog.
9. Add gallery/synth/conformance examples.
10. Replace README/docs.
11. Add full tests and update existing smoke tests.
12. Run full UI verification suite.

---

## Testing Strategy

Incremental verification:

- After ASDL/input/interact changes:
  - `luajit tests/test_ui_interact_contract.lua`
- After ID/state/lower changes:
  - `luajit tests/test_ui_id_validation.lua`
  - `luajit tests/test_ui_state_bridge.lua`
- After overlay/runtime changes:
  - `luajit tests/test_ui_overlay_layers.lua`
- After text/session changes:
  - `luajit tests/test_ui_text_session.lua`
- After backend changes:
  - `SDL_VIDEODRIVER=dummy luajit tests/test_ui_backend_contract.lua`
  - `SDL_VIDEODRIVER=dummy luajit tests/test_ui_sdl3_paint.lua`
- After widgets:
  - `luajit tests/test_ui_widgets_contract.lua`
  - `luajit tests/test_ui_widget_catalog.lua`
- Final:
  - all `tests/test_ui*.lua`
  - dummy SDL example smoke runs with `AUTO_QUIT_MS`.

---

## Structured Edit Plan Sidecar

Created sidecar: `wf-a6d2de07/ui-completion`

Summary:
- 55 tasks created.
- Covers docs, ASDL/kernel contracts, ID/state/input, runtime/interact/session/text, backend conformance, widget contract/catalog, examples, docs, and tests.
- First ready task: `T001 Write UI kernel contract documentation`.
- Final verification task: `T055 Run full UI verification suite`.

---

## Pattern Memo

- **ASDL first**: any meaningful UI/input/focus/layer/widget state must be represented in `lua/ui/asdl.lua`.
- **Pure reducers**: `ui.interact` must not call host/backend/widget callbacks.
- **No silent fallbacks**: text approximate layout and backend missing capabilities must be explicit.
- **IDs fail loud**: duplicate IDs are validation errors, not undefined behavior.
- **Widgets return canonical bundles**: `{ node, surfaces, route_one, route_ui_event, route_ui_events, ... }`.
- **Backend semantics follow contract docs**: SDL/Love implement typed contracts; they do not invent app semantics.

## Worker Output — 2026-06-13 23:33:14

## Completed
Implemented and marked done tasks T001–T016 in workflow `wf-a6d2de07`, plan `ui-completion`.

Highlights:
- Added UI kernel/backend contract docs.
- Extended ASDL for typed input, focus scopes, capture, layers, overlays, modals, reports.
- Added `ui.input`, `ui.id`, and `ui.state` kernel helpers.
- Wired ID/state into lowering and facade.
- Added render/runtime support for layer/focus/modal ops and reports.
- Added typed keyboard/text/pointer-capture interaction handling.
- Integrated typed raw input in SDL3 host/session.
- Stabilized session/text default backend lifecycle.

## Files Changed
- `lua/ui/CONTRACT.md` - new UI kernel contract doc.
- `lua/ui/BACKEND_CONTRACT.md` - new backend contract doc.
- `lua/ui/asdl.lua` - new input/focus/capture/layer/report ASDL vocabulary.
- `lua/ui/input.lua` - typed input constructors and host-event conversion.
- `lua/ui/id.lua` - new full-tree ID collection/validation module.
- `lua/ui/state.lua` - new interaction-to-style state bridge.
- `lua/ui/init.lua` - exports `ui.id`.
- `lua/ui/lower.lua` - `lower.root`, ID validation, state bridge, new wrapper lowering.
- `lua/ui/plan.lua` - layout wrapper delegation for new nodes.
- `lua/ui/measure.lua` - measurement delegation for new wrappers.
- `lua/ui/render.lua` - emits focus scope/layer/overlay/modal view ops.
- `lua/ui/runtime.lua` - consumes new ops and reports hit/layer/modal/focus-scope facts.
- `lua/ui/interact.lua` - pointer capture, typed key/text input reducer support.
- `lua/ui/host_sdl3.lua` - attaches typed raw input to normalized SDL events.
- `lua/ui/session.lua` - default text key registration, raw UI routing, text input helpers.
- `lua/ui/session_sdl3.lua` - default SDL3 session text lifecycle wrapper.
- `lua/ui/text.lua` - default text registry APIs and explicit fallback policy.

## Checks Run
- `luajit tests/test_ui_smoke.lua`
- Multiple targeted `luajit` snippets for:
  - ASDL constructors
  - input conversion
  - ID validation
  - state bridge
  - lower/root validation
  - render layer ops
  - runtime layer/modal reports
  - interact pointer capture/typed input
  - SDL host typed input helpers
  - session text/raw lifecycle
  - text registry fallback/default behavior

## Notes
Edit plan status is now **16/55 done**. Next ready tasks include backend conformance helpers, widget core, and contract tests.

## Worker Output — 2026-06-13 23:47:28

## Completed
Implemented and marked done tasks **T017–T022** in workflow `wf-a6d2de07`, plan `ui-completion`.

Added backend conformance helpers, aligned SDL3/Love runtime capability contracts, introduced the canonical widget core, and refit existing recipes to return canonical widget metadata/surfaces/events while preserving compatibility.

## Files Changed
- `lua/ui/backend_contract.lua` - new backend conformance helper module.
- `lua/ui/runtime_sdl3.lua` - capabilities, contract aliases, missing image policy.
- `lua/ui/host_sdl3.lua` - host capabilities, `pixel_size`, `new_runtime_driver`.
- `lua/ui/text_sdl3.lua` - text capability metadata.
- `lua/ui/backends/sdl3/init.lua` - package-level SDL3 capabilities.
- `lua/ui/runtime_love.lua` - Love capability metadata and optional-gap contract alignment.
- `lua/ui/widget.lua` - new canonical widget contract core.
- `lua/ui/recipes/_core.lua` - delegates bundle/event helpers through `ui.widget`.
- `lua/ui/recipes/activatable.lua` - canonical metadata/events.
- `lua/ui/recipes/selectable_list.lua` - canonical surfaces/events.
- `lua/ui/recipes/reorderable_list.lua` - canonical surfaces/events.
- `lua/ui/recipes/edit_surface.lua` - canonical text input routing.
- `lua/ui/recipes/scroll_view.lua` - canonical scroll event routing.

## Checks Run
- `luajit tests/test_ui_smoke.lua`
- `SDL_VIDEODRIVER=dummy luajit tests/test_ui_sdl3_paint.lua`
- Targeted `luajit` snippets for backend contract helpers, SDL3 dummy host/driver validation, Love runtime metadata, widget bundle routing, and recipe canonical routing.

## Notes
Plan status is now **22/55 done**. Next ready tasks include `T023` text widget refit, widget modules, and contract tests. `ui.widget` and `ui.backend_contract` are currently available by direct `require`; top-level facade export remains planned under `T035`.

## Worker Output — 2026-06-14 00:05:13

## Completed
Implemented and marked done tasks **T023–T028** for workflow `wf-a6d2de07`, plan `ui-completion`.

Added/refit:
- Canonical text widget bundles
- Button widget
- Toggle / checkbox / radio widgets
- Slider / fader / value_drag widgets
- Knob widget
- Meter / progress widgets
- Hardened `ui.state` boolean state flag handling

Current plan status: **28/55 done**, no claimed/blocked tasks.

## Files Changed
- `lua/ui/widgets/_text_common.lua` - canonical text widget contract, surfaces, state/text lifecycle handling
- `lua/ui/widgets/text_input.lua` - bundle/surface/route exports
- `lua/ui/widgets/text_area.lua` - bundle/surface/route exports
- `lua/ui/widgets/button.lua` - new button widget
- `lua/ui/widgets/toggle.lua` - new toggle core
- `lua/ui/widgets/checkbox.lua` - new checkbox wrapper
- `lua/ui/widgets/radio.lua` - new radio wrapper
- `lua/ui/widgets/slider.lua` - new slider/value contract
- `lua/ui/widgets/fader.lua` - new fader wrapper
- `lua/ui/widgets/value_drag.lua` - new value drag wrapper
- `lua/ui/widgets/knob.lua` - new paint-backed knob
- `lua/ui/widgets/meter.lua` - new meter widget
- `lua/ui/widgets/progress.lua` - new progress wrapper
- `lua/ui/widgets/init.lua` - exports new widgets
- `lua/ui/state.lua` - boolean selected/disabled/active specs now accepted

## Checks Run
- `luajit tests/test_ui_smoke.lua`
- `SDL_VIDEODRIVER=dummy luajit tests/test_ui_sdl3_paint.lua`
- Targeted LuaJIT snippets for text widgets, button, toggle/checkbox/radio, slider/fader/value_drag, knob, meter/progress, and state boolean flags.

## Notes
Next ready task is `T029` for list/listbox/tabs widgets, followed by composition/canvas widgets and contract tests.

## Worker Output — 2026-06-14 00:31:17

## Completed
Implemented and marked done tasks **T029–T035** in workflow `wf-a6d2de07`, plan `ui-completion`.

Added:
- List/listbox/tabs widgets
- Menu/select/dropdown/popup widgets
- Overlay/tooltip/popover/modal helpers
- Composition widgets: panel, toolbar, property row, form field, split pane, scroll panel
- Canvas widget
- Completed widget facade exports and top-level UI facade exports

Checks passed:
- `luajit tests/test_ui_smoke.lua`
- `SDL_VIDEODRIVER=dummy luajit tests/test_ui_sdl3_paint.lua`
- Targeted LuaJIT snippets for each new widget group

## Files Changed
- `lua/ui/widgets/list.lua`
- `lua/ui/widgets/listbox.lua`
- `lua/ui/widgets/tabs.lua`
- `lua/ui/widgets/popup.lua`
- `lua/ui/widgets/menu.lua`
- `lua/ui/widgets/select.lua`
- `lua/ui/widgets/overlay.lua`
- `lua/ui/widgets/tooltip.lua`
- `lua/ui/widgets/popover.lua`
- `lua/ui/widgets/modal.lua`
- `lua/ui/widgets/panel.lua`
- `lua/ui/widgets/toolbar.lua`
- `lua/ui/widgets/property_row.lua`
- `lua/ui/widgets/form_field.lua`
- `lua/ui/widgets/split_pane.lua`
- `lua/ui/widgets/scroll_panel.lua`
- `lua/ui/widgets/canvas.lua`
- `lua/ui/widgets/init.lua`
- `lua/ui/init.lua`

## Notes
Plan status is now **35/55 done**. No tasks are currently claimed or blocked. Next ready work includes widget README, contract tests, backend/text/session tests, widget catalog tests, and SDL examples.

## Worker Output — 2026-06-14 04:34:35

## Completed
Implemented and marked done **T036–T041** in workflow `wf-a6d2de07`, plan `ui-completion`.

Added product docs and contract tests for widgets, README, interaction reducer, ID validation, state bridge, and overlay/layer behavior.

## Files Changed
- `lua/ui/widgets/README.md` - new canonical widget API/catalog docs.
- `lua/ui/README.md` - rewritten current productized UI overview.
- `tests/test_ui_interact_contract.lua` - new reducer contract tests.
- `tests/test_ui_id_validation.lua` - new ID validation tests.
- `tests/test_ui_state_bridge.lua` - new state bridge/lowering tests.
- `tests/test_ui_overlay_layers.lua` - new overlay/layer/modal tests.
- `lua/ui/asdl.lua` - extended `View.Op` metadata for layer/focus/overlay info.
- `lua/ui/render.lua` - emits layer kind, focus policy, placement/modal metadata.
- `lua/ui/runtime.lua` - reports layer kind, focus policy, overlay placement/modal.
- `lua/ui/id.lua` - handles `Auth.Empty` singleton during ID collection.
- `lua/ui/state.lua` - handles `Auth.Empty` singleton during state application.

## Checks Run
- `luajit tests/test_ui_smoke.lua`
- `SDL_VIDEODRIVER=dummy luajit tests/test_ui_sdl3_paint.lua`
- `luajit tests/test_ui_interact_contract.lua`
- `luajit tests/test_ui_id_validation.lua`
- `luajit tests/test_ui_state_bridge.lua`
- `luajit tests/test_ui_overlay_layers.lua`

## Notes
Plan status is now **41/55 done**. No tasks are currently claimed or blocked.

## Worker Output — 2026-06-14 04:48:52

## Completed
Implemented and marked done tasks **T042–T044** in workflow `wf-a6d2de07`, plan `ui-completion`.

Added:
- Layout golden tests
- Backend contract tests
- Text/session lifecycle tests
- Missing `ui.backend_contract.assert_text_module` helper

Plan status is now **44/55 done**.

## Files Changed
- `tests/test_ui_layout_golden.lua` - new golden tests for flow/flex/grid/scroll/sizing/text layout.
- `tests/test_ui_backend_contract.lua` - new backend capability/runtime/SDL3/Love contract tests.
- `tests/test_ui_text_session.lua` - new text registry/session lifecycle/cache/SDL session tests.
- `lua/ui/backend_contract.lua` - added `assert_text_module`.

## Notes
Checks passed:
- `luajit tests/test_ui_smoke.lua`
- `luajit tests/test_ui_interact_contract.lua`
- `luajit tests/test_ui_id_validation.lua`
- `luajit tests/test_ui_state_bridge.lua`
- `luajit tests/test_ui_overlay_layers.lua`
- `luajit tests/test_ui_layout_golden.lua`
- `SDL_VIDEODRIVER=dummy luajit tests/test_ui_backend_contract.lua`
- `SDL_VIDEODRIVER=dummy luajit tests/test_ui_text_session.lua`
- `SDL_VIDEODRIVER=dummy luajit tests/test_ui_sdl3_paint.lua`

## Worker Output — 2026-06-14 05:00:57

## Completed
Implemented and marked done **T047** in workflow `wf-a6d2de07`, plan `ui-completion`.

Added a complete SDL3 widget gallery that exercises:
- `ui.session_sdl3` default text lifecycle / `window.text_key`
- Theme/env defaults
- Typed raw input routing through `ui.interact.step`
- Focus traversal, activation, scrolling, text input
- Overlay, popup, tooltip, popover, modal layers
- Full widget catalog coverage

## Files Changed
- `examples/ui/gallery_sdl3.lua` - new SDL3 widget gallery example.

## Checks Run
- All current `tests/test_ui*.lua`
- `AUTO_QUIT_MS=50 SDL_VIDEODRIVER=dummy luajit examples/ui/gallery_sdl3.lua`
- Existing SDL examples:
  - `text_field_sdl3_demo.lua`
  - `paint_sdl3_demo.lua`
  - `text_sdl3_probe.lua`

## Notes
No blockers. Plan status is now **45/55 done**.
