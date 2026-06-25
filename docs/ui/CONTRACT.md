# Lalin UI Kernel Contract

This document is the product contract for `lua/ui` as a general-purpose UI kit.
It is intentionally contract-first: widgets, examples, and backend behavior are
valid only when they preserve the typed kernel described here.

The kernel is a compiler-shaped UI pipeline:

```text
Auth.Node
  -> resolve/lower(Auth.Node, Theme.T, Env.Class, interaction state)
  -> Scene.Node(Layout.Node layout, Decor.Node decor)
  -> measure(Layout.Node, constraints, text/content systems)
  -> solve(Layout.Node, Solve.Env, text/content systems) -> Solve.Node
  -> render(Solve.Node, Decor.Node) -> View.Op* typed variants
  -> runtime.run(driver, opts, View.Op*)
  -> Interact.Report
  -> interact.step(Interact.Model, Interact.Report, Interact.Raw)
  -> Interact.Event* + next Interact.Model
  -> next Auth.Node authored by the application/widgets
```

The authoritative vocabulary for meaningful UI state is `lua/ui/asdl.lua`.  Host
backends, widget helpers, recipes, and session code may adapt data, but they must
not invent untyped application semantics in callbacks, string events, or hidden
side tables.

## 1. Phase responsibilities

### Authored tree: `Auth.Node`

`Auth.Node` is the user-facing structure authored by apps, compose phases, and
widgets. It describes what exists, not where it is laid out or how a backend draws
it.

The authored tree owns these meanings:

- visual/content nodes: boxes, literal text, content-store text references, and
  typed paint programs;
- structural wrappers: scroll viewports, explicit input surfaces, drag sources,
  drop targets, drop slots, layers, overlays, focus scopes, and modal regions;
- explicit state wrappers when app/widget state must influence styling;
- stable IDs for every semantic surface that can be focused, hit, scrolled,
  dragged, dropped on, referenced by content, or addressed by a widget.

Authored nodes must be immutable ASDL values. Apps produce a new authored tree
when application state changes.

### Lowered scene: `Scene.Node(Layout.Node, Decor.Node)`

`Scene.Node` is the lowered form of the authored tree. Style normalization first
splits authored tokens into `Style.LayoutSpec` and `Style.DecorSpec`; resolution
then produces independent `Resolved.LayoutFacts` and `Resolved.DecorFacts`. Its
`Layout.Node` contains only layout and measurement facts. Its parallel
`Decor.Node` contains visual, cursor, text-paint, and paint-program facts.
Lowering resolves style tokens against the theme, environment, and
interaction/app state, then places each fact at the first phase that semantically
needs it.

Lowering owns:

- theme/env/style resolution;
- merge of inherited state, interaction-derived state, and explicit
  `Auth.WithState` state;
- compatibility lowering of legacy overflow-scroll styling into structural
  scroll, while new authored code uses explicit `Auth.Scroll`;
- full-tree ID validation when requested by the public root helper;
- no host/backend calls.

### Measurement and planning

Measurement computes sizes from `Layout.Node`, constraints, layout text metrics,
text layout systems, and explicit content stores. It does not see visual color,
box paint, cursor, or paint programs. Planning helpers shared by measure and
render are the single source of truth for flow, flex, and grid placement.

Measurement must not depend on pointer position, scroll offset, backend event
state, or hidden session globals. Text measurement depends on an explicit text
system key/system or an explicit approximate fallback.

### Solve tree: `Solve.Node`

Solving turns `Layout.Node` plus viewport/text/content facts into placed layout.
`Solve.Node` owns box rectangles, content rectangles, scroll content extents, and
text layouts. Render must not re-run layout placement; it consumes solved facts.

### Render stream: `View.Op*`

Rendering consumes `Solve.Node` plus the parallel `Decor.Node`: solve supplies
placement, while decor supplies visual/text-paint/paint-program facts. `View.Op`
is a typed sum of operation variants, not a nullable kitchen-sink tuple. The
stream is both drawing input and semantic-runtime input. If a thing can affect
hit testing, focus order, scrolling, dragging, cursors, overlays, or modal
behavior, it must be represented in `View.Op`, not only in a backend callback.

The render stream owns:

- z-order by op order;
- clip, transform, and scroll stack boundaries;
- visual ops for boxes, text, and paint;
- semantic ops for hit regions, focus slots, cursors, drag/drop regions, layers,
  overlays, focus scopes, and modal barriers.

### Runtime report: `Interact.Report`

`ui.runtime` consumes the same op stream that drivers draw. It is the fact source
for interaction reducers. The report contains frame-local geometry and ordering:

- current topmost hover/cursor/scroll IDs;
- full hit stack, focusables, scrollables, drag sources, drop targets, drop slots;
- layer, overlay, modal, and focus-scope facts;
- viewport/content limits for scroll clamping.

Runtime may draw through a backend driver, but report construction is part of the
kernel contract and remains backend-independent.

### Interaction reducer: `Interact.Model`, `Interact.Raw`, `Interact.Event`

`Interact.Raw` values are backend-independent input facts. `interact.step` is a
pure reducer from previous model, current report, and one raw input value to an
ordered semantic event list plus next model.

The reducer owns:

- pointer position, hover, pressed target, pointer capture, focus, drag state,
  and scroll offsets;
- keyboard-to-focus/activation/cancel/value intent mapping;
- text input routing to the focused edit target;
- scope/modal-aware focus traversal;
- deterministic event order.

The reducer must not call host APIs, mutate widgets, draw, allocate backend
resources, or invoke application callbacks.

### Next authored tree

Applications and widgets observe semantic events and their own model state, then
author the next tree. This closes the loop. The kernel never hides app state
inside a driver or session object.

## 2. ID contract

IDs are global semantic identity within one rendered UI tree. A `Core.IdValue` may
be reused across frames for the same semantic surface, but duplicate semantic IDs
inside one tree are invalid unless a specific wrapper explicitly documents an
aliasing rule.

IDs are required for:

- input surfaces and focus targets;
- scroll viewports and persistent scroll positions;
- drag sources, drop targets, and drop slots;
- layers, overlays, focus scopes, modal regions, and widget roots;
- text edit targets, content-store references, and generated widget subparts.

The public root lowering/validation path must fail loud on duplicate or invalid
IDs. Diagnostics must include enough structural path information to find both the
first occurrence and the duplicate, for example:

```text
root.children[3].WithInput(id="gain") duplicates root.children[1].Scroll(id="gain")
```

Widget authors must derive sub-IDs deterministically from the widget root ID using
a documented convention. Generated IDs must remain stable across frames and may
not depend on table iteration order or transient layout position.

## 3. State and styling contract

`Style.State` contains the common interaction flags:

- `hovered`
- `focused`
- `active`
- `selected`
- `disabled`

The kernel owns the canonical bridge from `Interact.Model` and `Interact.Report`
to derived per-ID style state. Widgets may supply explicit selected/disabled/app
state, but hover/focus/pressed/captured/drag-active state must be interpreted
consistently across controls.

State merge order is:

1. inherited parent state;
2. interaction-derived state for the current semantic ID;
3. explicit app/widget `Auth.WithState` state.

Explicit state may intentionally override or augment derived state, but the merge
rule must be documented and deterministic. Disabled state affects both style and
interaction: disabled targets are not focusable, activatable, draggable, or valid
keyboard recipients unless a specialized control explicitly documents otherwise.

## 4. Input contract

Host events are normalized into backend-independent `Interact.Raw` values before
entering the reducer. SDL, Love, tests, and future hosts may expose their native
event tables for compatibility, but the canonical UI route is typed raw input.

The input vocabulary includes:

- pointer move/press/release/cancel;
- wheel motion;
- key press/release with modifiers and repeat information;
- text input and IME/text editing composition;
- focus-lost/window-lost events;
- abstract focus/activation/cancel intents for compatibility and tests.

Default key mapping:

- `Tab` -> focus next;
- `Shift+Tab` -> focus previous;
- `Return` and `Space` -> activate focused target;
- `Escape` -> cancel pointer capture/drag/modal or focused edit operation;
- arrow/Page/Home/End keys may become scroll, text-navigation, or value intents
  depending on the focused target role.

Text-editing targets receive key/text/IME input before generic activation when
they own focus. Backend constants must not leak into `ui.input` or pure tests.

## 5. Pointer capture and drag contract

Hover is frame-local. Capture is persistent semantic state.

On primary pointer press over an eligible target, the reducer records the pressed
ID and capture ID. Subsequent moves and release route to the captured/pressed
surface even if the pointer leaves its current geometry, as long as the surface is
still valid or until cancellation rules apply.

Drag behavior is defined over explicit drag source/drop target/drop slot facts:

- press over a drag source starts a pending drag;
- movement beyond the configured threshold starts dragging;
- drag movement reports the current target/slot using the frame report;
- release produces drop or cancel events according to capture and target state;
- pointer cancel/focus lost clears pressed/capture/drag state deterministically.

A node moving, reordering, or temporarily losing hover during a drag must not
silently transfer ownership to another ID.

## 6. Focus contract

Focus order is defined by the rendered focus stream, scoped by focus scopes and
modal layers. Focus traversal is deterministic, wraps within its active scope, and
skips disabled or non-focusable entries.

Focus scopes define traversal boundaries. Modal scopes restrict traversal and
activation to the topmost active modal layer. When a focused ID disappears from
the current report, the next reducer step must either clear focus or move focus
according to a documented scope policy; it must not leave an unobservable focused
ID indefinitely active.

Activation is a semantic event. Pointer activation requires press/release under
the capture contract. Keyboard activation requires a focused activatable target.

## 7. Layers, overlays, popups, and modals

Tree ancestry normally controls clipping and stacking. Any UI that escapes parent
clipping or participates in a top layer must do so through typed layer/overlay
nodes and matching view ops.

Layer contract:

- layers have stable IDs and explicit kind/order semantics;
- layer push/pop ops preserve deterministic z-order;
- layer facts are visible in runtime reports;
- layers do not weaken ordinary scroll/clip behavior outside their typed scope.

Overlay contract:

- overlays have stable IDs, optional anchor IDs, placement policy, and modal flag;
- anchored placement is resolved by the layout/render contract, not by backend-only
  code;
- overlays can host menus, tooltips, popups, drag previews, and context surfaces;
- modal overlays emit modal barriers that block lower-layer hit/focus candidates
  without erasing lower-layer drawing.

Modal contract:

- only the active top modal scope receives pointer/focus/keyboard interaction;
- cancel intent is routed to the active modal before lower layers;
- focus traversal remains inside the modal scope;
- closing a modal is an app/widget state transition caused by semantic events.

## 8. Text and session contract

Text is a first-class subsystem, not an accidental backend side effect.

`ui.text` owns registry and fallback policy. A real text backend must be selected
explicitly by key or session default. Approximate layout remains available, but it
must be an explicit fallback choice or test fixture, not the silent result of a
missing registration.

A session that creates a text system must register it under a collision-free key,
store that key on the session/window, make it the default for that session's UI
work, and unregister it during close. Multiple sessions must not collide in the
global text registry.

Text field/editing contract:

- text editing state is widget/app model data;
- text layout, hit testing, caret placement, selection, clipboard, and IME
  composition use the active text system;
- focused edit targets control text input activation and composition rectangle;
- text overlay drawing must use the same layout facts as measurement/rendering;
- generic input still enters through typed raw input before text widgets interpret
  editing-specific commands.

## 9. Runtime/backend contract boundary

Backends implement drawing and host integration for typed kernel concepts. They do
not define application semantics.

A runtime driver may provide:

- box, text, paint, image, mesh, clip, transform, scroll, cursor, and layer draw
  operations;
- host clipboard/text input/IME/window lifecycle support;
- capability metadata for optional features.

Missing optional capabilities must fail loud or return documented diagnostics.
Declared primitives must not silently no-op. Backend-specific resources such as
fonts, images, textures, and renderer handles are passed through explicit systems,
registries, or resolver callbacks.

HiDPI/density is part of the environment contract. If `Env.Density` affects
layout, text, or rendering, that effect must be specified and tested; if a backend
cannot support it, capability metadata and docs must say so.

## 10. Widget contract

Widgets are typed authored-tree producers plus pure event/model helpers. A widget
is not a callback sink hidden inside runtime.

Canonical widget bundles expose:

- `id`: stable root ID;
- `kind`: widget kind string or typed tag;
- `node`: authored `Auth.Node` subtree;
- `surfaces`: deterministic map of root/subpart IDs used for routing;
- `model`: widget state where the widget owns state;
- `events`: semantic widget events produced from UI events when applicable;
- route helpers for one event and event lists;
- validation helpers for IDs and required options.

Reusable widgets must use the kernel contracts for hover/focus/active styling,
focusability, pointer capture, keyboard routing, text input, and disabled state.
The widget catalog must cover general-purpose and synth-oriented controls:
buttons, toggles, checkboxes/radios, sliders/faders, knobs/value drags, meters,
progress, lists/tabs, menus/selects, tooltips/popups/modals, panels/toolbars,
property rows, split panes, scroll panels, canvas/paint surfaces, text input, and
text area.

## 11. Supported layout subset

The UI layout system is a documented subset, not a browser clone. Supported
layout modes are:

### Flow

Flow lays children vertically in stream order, honors padding/margins/gaps, and
uses display-specific auto-width semantics. Constrained flow containers and flow
children with auto width fill available width; unconstrained cases may hug
content according to sizing rules.

### Flex

Flex supports row/column axis, wrapping, main/cross alignment, gaps, grow,
shrink, and basis. Shared flex planning drives both measurement and rendering.
The supported contract does not include every CSS flexbox behavior: special
main-axis auto margins, full `align-content`, and precise baseline behavior are
outside the guaranteed subset until explicitly added and tested.

### Grid

Grid supports authored row/column tracks, auto/fixed/fr/minmax tracks, item
placement by row/column start/span, gaps, implicit auto tracks for referenced
out-of-range placements, and shared planning for measurement/rendering. Dense
auto-placement, full content-based multi-span solving, and item-specific authored
alignment are outside the guaranteed subset until explicitly added and tested.

### Scroll and clipping

Clipping is style. Scrolling is structure. `Auth.Scroll` / `Layout.Scroll` define
scrollable viewports and runtime scroll facts. Scroll clipping applies to visual
ops and interaction facts. Wheel and keyboard scrolling clamp to runtime-reported
viewport/content bounds.

### Paint

Paint nodes have no intrinsic content measurement beyond their styled box. Authors
must provide dimensions when paint content must reserve space. Paint programs are
typed ASDL values and render through the same clip/transform/scroll stack as all
other view ops.

## 12. Testing obligations

A UI change is complete only when the relevant contract boundary is tested.
Required coverage areas are:

- ASDL constructor compatibility and explicit handling in lowering/render/runtime;
- ID validation diagnostics;
- state bridge merge behavior;
- input conversion and pure reducer event order;
- pointer capture, drag/drop, cancel, and disappearing-target behavior;
- focus traversal, focus scopes, disabled skipping, and modals;
- scroll clamping and nested scroll behavior;
- layout golden cases for flow/flex/grid/text/paint/scroll;
- text registry/session lifecycle and explicit approximate fallback;
- backend conformance/smoke tests for declared primitives and capabilities;
- widget bundle contracts and catalog behavior;
- example smoke tests under dummy/headless backends where possible.

Tests should prefer pure phase fixtures where possible and use backend smoke tests
only for backend-specific guarantees.

## 13. Compatibility and migration

Existing public constructors remain compatible unless a migration document names a
replacement and deprecation path. Compatibility helpers may translate old forms
into typed kernel forms, but they must not preserve silent ambiguity.

When strengthening a contract, prefer:

1. add typed ASDL vocabulary;
2. add explicit conversion/compatibility helper;
3. add validation with clear diagnostics;
4. update examples/docs/tests;
5. only then remove or deprecate old ambiguous behavior.

## 14. Definition of complete

`lua/ui` is a complete general-purpose UI kit when:

- every meaningful UI/input/focus/layer/text/widget state has typed vocabulary;
- the authored-to-runtime-to-interaction lifecycle is documented and tested;
- IDs, focus, scroll, capture, state styling, and text/session lifecycle fail loud
  on invalid use;
- backends conform to documented runtime capabilities;
- the canonical widget catalog uses one bundle/event/model contract;
- examples exercise real app composition, including SDL3 synth-style UI;
- documentation describes actual supported behavior and does not rely on stale
  demo references or hidden conventions.
