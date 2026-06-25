# Lalin UI Kernel Design

Status: superseded by
[`experiments/mlui-llpvm/mlui_llpvm_stack_blueprint.md`](../mlui-llpvm/mlui_llpvm_stack_blueprint.md).
This file is retained only as historical design input from the pre-LLPVM
iteration. Do not use its phase names, dependency model, or ABI names as the
current MLUI architecture. The current center is semantic domain worlds:
`authored_ui -> expanded_ui -> valid_ui -> imported_ui -> styled_ui ->
measured_ui -> laid_out_ui -> renderable_ui -> reported_frame ->
handled_frame`.

Historical scope: experiment design for translating `lua/ui` into a
Lalin-native UI kernel while preserving the existing Lua authoring taste.

This is not a replacement for `lua/ui`.  The current Lua UI library is the seed:
it is already compiler-shaped, ASDL-first, backend-independent, and tested.  The
Lalin version should make the same phase boundaries explicit as typed
products and protocols so the hot kernel can become a native artifact.

The native translation must not flatten the authored model into a poor widget
API.  The richness of `lua/ui/asdl.lua` is part of the architecture.

The author-facing Lua API is specified separately in
[`mlui_lua_api.md`](mlui_lua_api.md).  It follows the same callable-table,
no-parentheses law as `chain.lua` and the MWUI blueprint.

The portable frontend bytecode is specified in
[`mlui_bytecode.md`](mlui_bytecode.md).  That document is the contract for Lua,
C, serialized tools, and browser builders that emit MLUI programs directly.
The draft public C constants and row declarations live in
[`mlui_c_api.h`](mlui_c_api.h).
The mechanical implementation order is specified in
[`mlui_implementation_plan.md`](mlui_implementation_plan.md).

## Thesis

```text
Lua authors UI.
Lalin owns the UI kernel protocols.
Backends draw typed op streams.
Applications own domain state.
```

The current `lua/ui` pipeline is the architecture:

```text
Auth.Node
  -> lower(Auth, Theme, Env, Interact.Model/Report)
  -> Scene(Layout.Node, Decor.Node)
  -> solve(Layout.Node, Solve.Env, TextSystem, ContentStore)
  -> Solve.Node
  -> render(Solve.Node, Decor.Node)
  -> View.Op[]
  -> runtime report
  -> interact_step(Model, Report, Raw)
  -> Event[] + next Model
```

The translation target is not a browser DOM framework and not a callback widget
kit.  It is a typed retained kernel underneath an ergonomic Lua authoring layer.

## Immediate Mode With Retained Phases

MLUI should stay immediate-mode at the Lua surface:

```text
app state + interaction model + frame input -> authored tree
```

That does not mean the native kernel is throwaway.  The right model is the PVM
trick applied to UI:

```text
immediate Lua authoring
  + stable ids
  + explicit epochs
  + typed dependency keys
  + memoized phase products
  = retained performance without retained authoring state
```

The app may rebuild the semantic tree every frame.  The kernel records enough
typed facts to reuse expensive products:

| Product | Memoization key |
| --- | --- |
| imported authored nodes | stable `UiId` + node shape hash |
| style resolution | style token id + theme epoch + env class + state mask |
| text layout | content ref + font ref + width constraint + text epoch |
| paint program | paint ref + paint epoch |
| intrinsic measurement | layout style + content/layout epochs |
| solved placement | parent constraints + child measure epochs |
| view ops | solve epoch + decor/paint/text epochs |
| interaction report | view/runtime op epoch + raw input epoch |

This keeps the authoring API immediate and pleasant while letting the kernel
behave like a retained compiler cache.  The cache boundary is explicit: ASDL
products, handles, epochs, and region outputs.  No hidden Lua callback state is
needed.

This is not `memo func` for UI functions.  Function compile caches may keep a
native pointer alive; they do not define semantic reuse.  MLUI reuse belongs to
`UiKernel` stores:

```text
cache owner     UiKernel / phase-specific store
cache key       stable id + shape/dependency/epoch product
cache value     typed phase product
cache protocol  hit | miss | stale | oom
invalidation    explicit epoch/generation boundary
```

So the reusable units are imported node products, resolved styles, text layouts,
measurements, solved placements, view op buffers, reports, and event reductions.
They are not arbitrary Lua or Lalin function calls with invisible side state.

State machines are therefore optional protocol nouns, not the base rendering
model.  Use them when the UI object has real named phases: text editing, IME,
drag/drop, modal/menu flows, async workflows, or component-level interaction
protocols.  Do not require every widget or visual node to become an actor.

## Ownership Law

```text
Lua owns authoring convenience and metaprogramming.
Lalin owns durable UI stores, ids, solved layout, view op buffers, reports, and interaction state.
Backends own platform resources: windows, renderers, fonts, textures, clipboard, IME.
Applications own app/domain state.
```

Meaningful state must not hide in callbacks or side tables:

- IDs are explicit `UiId`.
- Text content crossing into durable storage is copied into a `UiContentStore`.
- Text layout is a retained product with a lifecycle.
- View ops are typed records, not ad hoc tuples.
- Runtime interaction facts become `UiReport`.
- Interaction changes become `UiEvent` records.

The memory law follows the Design Bible literally:

```text
UiKernel owns stores and frame buffers.
Ui*Ref handles name durable identity inside UiKernel.
Borrow regions grant leases.
Retain/register regions create owned obligations.
Publish regions transfer owned obligations into kernel-visible durable refs.
Release/close regions consume owned obligations or return them on failure.
Reset regions are named invalidation boundaries.
```

## Layer Map

```text
lua/ui authoring DSL
  build, tw, widgets, recipes
  produces authored semantic trees and stores

mlui kernel
  typed flat buffers, handles, regions
  lower / measure / solve / render / interact protocols

backend bridge
  SDL3, Love, embedded framebuffer, or host binding
  consumes ViewOp buffers and supplies text/input/window resources

application
  observes UiEvent stream
  updates app state
  authors next tree or updates dynamic stores
```

The bridge is intentionally small.  The complete Lua API should not be compiled
into Lalin.  The compiled kernel should receive validated typed buffers and
produce typed output buffers.

## UI VM Model

MLUI can be designed as a small retained UI VM:

```text
program      = UiProgram / UiAuthBuffer rows + resource stores
heap         = UiKernel stores, caches, epochs, model, frame buffers
input        = UiRawInput rows
execution    = import -> lower -> measure -> solve -> render -> report -> interact
output       = UiViewOp rows + UiEvent rows
syscalls     = text measure, image/font/resource registration, host draw outside VM
```

This matters because Lua should not be the only frontend.  Lua is the first and
best authoring compiler, but C, Zig, Rust, generated tools, or a browser builder
can emit the same program rows directly:

```text
Lua no-parens DSL     -> UiProgram
C immediate builder   -> UiProgram
serialized asset file -> UiProgram
inspector/editor      -> UiProgram
```

The VM opcode law:

```text
UiProgramOp / UiAuthNode = authored semantic opcode row
UiViewOp                 = render/report output opcode row
UiRawInput               = input opcode row
UiEvent                  = semantic event output opcode row
```

`UiProgramOp` is not a low-level drawing command.  It preserves authored
semantics: boxes, text, paint, scrolls, input surfaces, drag/drop nouns, focus
scopes, layers, overlays, modals, style token ranges, content refs, paint ranges,
and explicit state.  The VM lowers those semantic opcodes into layout, solve,
view, report, and event products.

Therefore the C API should expose two authoring paths:

```text
1. load/import a complete UiProgram buffer;
2. optionally use a small C builder that appends UiProgramOp rows.
```

Both paths are frontends.  Neither gets to mutate `UiKernel` internals directly.
The complete row/opcode contract is in [`mlui_bytecode.md`](mlui_bytecode.md).

## Products

The first native product layer is rich and compiler-oriented.  Flat buffers are
only the ABI encoding of that richness:

- `UiEnvClass`: breakpoint/scheme/motion/density selection facts.
- `UiTheme`: palette, spacing, font, radius, border, opacity scales.
- `UiStyleToken`: conditional authored style atoms.
- `UiAuthNode`: encoded `Auth.Node`, including wrappers and interaction nouns.
- `UiComposeNode`: encoded `Compose.Node` for panels, splits, workbenches.
- `UiLayoutNode`: layout-only node facts after style/theme resolution.
- `UiDecorNode`: visual/text/paint facts parallel to layout.
- `UiPaintProgram`: line/polyline/polygon/circle/arc/bezier/mesh/image programs.
- `UiTextLayout`: lines, runs, glyphs, clusters, and caret boundaries.
- `UiSolveNode`: placed layout artifact.
- `UiViewOp`: typed render/runtime operation.
- `UiReport`: frame-local runtime interaction facts.
- `UiModel`: persistent interaction state, capture, drag, scrolls.
- `UiEvent`: semantic interaction event.

Lua can continue to use recursive ASDL trees.  The native kernel boundary should
prefer buffers because C and embedded targets want compact ABI surfaces:

```text
UiProgram/AuthBuffer -> SceneBuffer -> SolveBuffer -> ViewOpBuffer -> Report/EventBuffer
```

Recursive authoring trees remain a Lua-side source representation, not the
lowest-level native ABI.  The native authoring ABI is `UiProgram`: a tight,
validated opcode/data buffer.

## ASDL Coverage

`lua/ui/asdl.lua` remains the checklist.  Every module has a destination in the
Lalin translation:

| Lua ASDL module | Lalin destination |
| --- | --- |
| `Core` | `UiId`, handle identity, validation protocols |
| `Content` | `UiContent`, `UiContentStore`, retain/release protocols |
| `Env` | `UiEnvClass`, consumed by style/theme resolution |
| `Style` | `UiStyleToken`, `UiStyleAtom`, lengths, basis, tracks, conditions |
| `Theme` | `UiTheme` and scale products |
| `Paint` | `UiPaintProgram`, `UiPaintStore`, paint visitor/backend protocol |
| `Auth` | `UiAuthNode`/`UiAuthBuffer`, including wrappers and source state |
| `Compose` | `UiComposeNode`/`ui_expand_compose`, not erased as Lua-only sugar |
| `Resolved` | `UiLayoutStyle`, `UiDecorStyle`, resolved style facts |
| `Layout` | `UiLayoutNode`, text specs/layouts, grid tracks, solve protocols |
| `Decor` | `UiDecorNode`, box/text/paint facts parallel to layout |
| `Scene` | `UiSceneBuffer`, explicit layout/decor product split |
| `Solve` | `UiSolveNode`, placed boxes, scroll geometry, solved text refs |
| `View` | `UiViewOp`, runtime/backend op protocol |
| `Interact` | `UiReport`, hit/focus/scroll/drag/drop/layer/overlay/modal/scope boxes, `UiModel`, `UiRawInput`, `UiEvent` |
| `TextEdit` | `UiTextEditState` |
| `TextField` | `UiTextFieldState` |

The rule is strict:

```text
Tree richness may be encoded.
Tree richness may not disappear.
```

When a Lua ASDL union becomes a native `kind` field, that `kind` is an encoding
owned by one named consumer region such as `ui_visit_auth_node`,
`ui_resolve_style`, `ui_visit_paint_program`, `ui_render_ops`, or
`ui_interact_step`.  Other phases use the consumer protocol instead of
scattered switches.

## Resource Model

The kernel product owns the storage:

| Store/product | Owns |
| --- | --- |
| `UiNodeStore` | imported authored node identities and id lookup |
| `UiContentStore` | copied text/content bytes and layout-affecting epochs |
| `UiTextLayoutStore` | measured text layouts, runs, glyphs, clusters, boundaries |
| `UiPaintStore` | rich paint programs, point arrays, mesh vertices |
| `UiImageStore` | backend image/texture records |
| `UiFontStore` | backend font records |
| `UiValueStore` | dynamic widget/display values |
| `UiSceneBuffer` | current lowered layout/decor projection |
| `UiSolveBuffer` | current solved placement projection |
| `UiViewBuffer` | current render/runtime op projection |
| `UiEventBuffer` | current frame semantic events |

Durable identity is via handles:

```text
UiKernelRef
UiNodeRef
UiContentRef
UiTextLayoutRef
UiPaintRef
UiImageRef
UiFontRef
UiValueRef
```

Access is only through borrow protocols such as `ui_borrow_content`,
`ui_borrow_text_layout`, `ui_borrow_image`, and `ui_borrow_font`.  Successful
exits grant `lease(kernel) ptr(...)`.  Missing/stale exits grant no access.

Creation/registration uses owned obligations:

```text
ui_kernel_create      -> owned UiKernelRef
ui_content_retain     -> owned UiContentRef
ui_text_layout_retain -> owned UiTextLayoutRef
ui_paint_retain       -> owned UiPaintRef
ui_image_register     -> owned UiImageRef
ui_font_register      -> owned UiFontRef
ui_value_retain       -> owned UiValueRef
```

Publishing transfers ownership into a durable kernel-visible reference:

```text
owned UiContentRef -> ui_content_publish -> UiContentRef
owned UiPaintRef   -> ui_paint_publish   -> UiPaintRef
owned UiValueRef   -> ui_value_publish   -> UiValueRef
```

Release/close regions consume owned handles and return the owned handle on
failure when discharge did not happen.  This is non-negotiable: a UI resource
cannot disappear behind a status code.

## Dynamic Stores

The current performance notes are correct: the product path needs explicit
dynamic stores.

```text
UiContentStore    text bytes and content ids
UiPaintStore      paint programs, images, mesh payloads
UiValueStore      widget scalar/display values
UiTextLayoutStore retained measured text layouts
UiScrollStore     persistent scroll positions
```

This avoids structural invalidation for paint-only or value-only changes:

- slider value changes normally update paint/value store, not child geometry;
- meter/scope/canvas updates normally update paint data, not authored nodes;
- caret/selection/composition updates normally update text field view data, not
  layout shell structure;
- text that affects intrinsic size declares a layout-affecting epoch.

## Protocols

The kernel protocols are named after the existing Lua phases:

```lalin
ui_import_auth
ui_lower_scene
ui_measure_node
ui_solve_scene
ui_render_ops
ui_runtime_report
ui_interact_step
```

The encoded ASDL worlds have explicit consumer protocols:

```text
Style.Atom      -> ui_visit_style_atom
Compose.Node    -> ui_visit_compose_node
Auth.Node       -> ui_visit_auth_node
Layout.Node     -> ui_visit_layout_node
Decor.Node      -> ui_visit_decor_node
Solve.Node      -> ui_visit_solve_node
View.Op         -> ui_visit_view_op
Paint.Program   -> ui_visit_paint_program
Interact.Raw    -> ui_visit_raw_input
Interact.Event  -> ui_visit_event
Interact.Key    -> ui_visit_key
UiValueRecord   -> ui_visit_value
```

This is the Chapter 4 rule applied to UI: a stored `kind` byte is an encoding,
not the design.  The visitor/consumer region is the design.  Every other phase
either calls the consumer protocol or works on products already produced by that
consumer.

Each region owns one boundary and has typed exits:

- invalid input is not a host exception;
- missing ids or duplicate ids are protocol exits;
- allocation failures return `oom(needed)`;
- backend resource failure is reported at backend bridge protocols;
- public ABI functions translate typed exits to status codes only at the edge.

## Rendering Op Contract

Rendering is specified by the existing `lua/ui` `View.Op` vocabulary and the
native `UiViewOp` row encoding.  It is well enough to implement only if both
halves are kept:

```text
View.Op semantic variants are the design.
UiViewOp rows are the ABI projection.
```

The semantic variants are:

```text
Box
Text
Paint
PushClipRect / PopClip
PushTx / PopTx
PushScroll / PopScroll
Hit
Focus
Cursor
DragSource
DropTarget
DropSlot
BeginFocusScope / EndFocusScope
BeginLayer / EndLayer
Overlay
ModalBarrier
```

`ui_render_ops` emits a single ordered stream.  The order is authoritative:
backends draw in stream order, while `ui_runtime_report` derives hit/focus/layer
facts from the same stream.  There is no separate hidden hit-test tree.

Stack discipline is part of the contract:

| Stack | Push | Pop | Failure |
| --- | --- | --- | --- |
| transform | `PushTx` | `PopTx` | `stack_unbalanced` |
| clip | `PushClipRect` | `PopClip` | `stack_unbalanced` |
| scroll | `PushScroll` | `PopScroll` | `stack_unbalanced` |
| focus scope | `BeginFocusScope` | `EndFocusScope` | `stack_unbalanced` |
| layer | `BeginLayer` | `EndLayer` | `stack_unbalanced` |

Malformed rows do not become backend surprises.  `ui_visit_view_op` owns kind
decoding and `ui_runtime_report` returns `malformed_op` or `stack_unbalanced`.

The row payload law:

```text
kind        selects the semantic variant
id          is the semantic surface id
rect        is the local op rectangle or viewport
other_id    is the paired id, such as overlay anchor
first/count address paint/style/text/resource ranges
axis/role/policy/cursor/layer_kind/placement/flags carry encoded enums
order       carries layer order
dx/dy       carry transform deltas
content_w/h carry scroll content extents
```

Drawing ops may refer to retained stores:

- `Box` reads resolved `UiBoxVisual`/decor facts;
- `Text` reads a retained `UiTextLayoutRef` and resolved text style;
- `Paint` reads a range of `UiPaintProgram` rows plus point/mesh/image stores.

Backends consume `UiViewBuffer` plus resource stores.  They never inspect
`Auth`, `Layout`, `Decor`, or `Solve` buffers directly.

## Input Op Contract

Input is specified by backend-independent `UiRawInput`, not platform event
tables.  Host bridges translate SDL/Love/browser/embedded events into raw input
rows before `ui_interact_step`.

The semantic raw variants are:

```text
PointerMoved(x, y)
PointerPressed(button, x, y)
PointerReleased(button, x, y)
PointerCancelled
WheelMoved(dx, dy, x, y)
KeyPressed(key, mods, repeat)
KeyReleased(key, mods)
TextInput(text)
TextEditing(text, start, length)
FocusMove(direction)
FocusLost
ActivateFocused
CancelInteraction
```

`UiRawInput` payload law:

```text
kind          selects the raw variant
button        is valid for pointer press/release
key/mods      are valid for key press/release
direction     is valid for focus move / abstract navigation
repeat_       is valid for key press
x/y           are pointer coordinates in logical pixels
dx/dy         are wheel deltas in logical pixels or backend-normalized units
text          is borrowed backend/event text for this dispatch only
text_start    is valid for text editing
text_length   is valid for text editing
```

Raw input has no required semantic target id.  Targeting is derived by
`ui_interact_step` from the current `UiReport` and persistent `UiModel`: hover,
focus, capture, drag, scroll positions, modal scope, and focus scopes.

Text input follows the text boundary law: borrowed event text may be routed
through the reducer, but anything stored into UI/app state must be copied into a
`UiContentStore`.

## Text Boundary

Text is the hardest UI boundary and should stay explicit.

Borrowed input text from a backend event is valid only during event dispatch.  If
stored into UI state or app state, it must be copied into owned content storage.

Text layout is a product:

```text
UiTextLayoutRef = retained measured lines/runs/clusters/boundaries
```

Backends may measure through platform text APIs, but the kernel consumes the
result as typed layout data.  Rendering must draw the text layout that solve
selected; it must not re-measure or re-wrap in the driver.

## Backend Contract

Backends are not application runtimes.  They provide:

- window/frame lifecycle;
- typed raw input construction;
- text measurement/layout service;
- drawing of `UiViewOp` buffers;
- platform resource handles for images/fonts/textures.

They do not own:

- focus;
- activation;
- pointer capture;
- drag/drop;
- widget semantics;
- app state;
- layout policy.

Those stay in the Lalin UI kernel.

## Lua Authoring Contract

Keep the good part of `lua/ui`:

```lua
local ui = require "mlui"
local b = ui.build
local tw = ui.tw
local W = ui.widgets
```

The authored tree remains pleasant and immediate-mode-looking.  The important
change is underneath:

```text
Lua tree -> validated/imported native buffers -> typed kernel phases
```

The MLUI surface is specified as callable builders rather than paren-heavy
helper functions:

```lua
local gain = W.slider "gain" {
    label = "Gain",
    value = app.gain,
    min = 0,
    max = 1,
    step = 0.01,
    model = model,
    report = report,
}

local root = ui.box "main" {
    tw.flex, tw.col, tw.gap.y[4], tw.p[6],
    tw.bg.slate[950], tw.fg.white,
    ui.text "Oscillator" { tw.text.lg, tw.font.semibold },
    gain.node,
}
```

Lua no-parentheses calls only accept string literals and table constructors, so
dynamic values are passed in table calls.  This is a feature, not a limitation:
it keeps non-string facts named and product-shaped.

Widgets should declare whether their changing values are:

- structure-affecting;
- layout-affecting;
- text-layout-affecting;
- paint-only;
- interaction-only.

That declaration drives invalidation and native buffer updates.

## Historical C Boundary Sketch

The deployment target should be one tiny artifact:

```c
int32_t mlui_lower_scene(...);
int32_t mlui_solve_scene(...);
int32_t mlui_render_ops(...);
int32_t mlui_runtime_report(...);
int32_t mlui_interact_step(...);
```

This old sketch mentioned browser typed arrays. That is not a current MLUI ABI
claim. In the current design, emitted C may be compiled by external C-to-WASM
toolchains, and JavaScript bindings are host-owned.

The browser or embedded host is a small op applier, not a second UI framework.

## Single-File C Embedding Profile

MLUI should be buildable as:

```text
mlui.c       one generated implementation blob
mlui.h       optional extracted declarations
mlui_amalgam.c may contain both when the host wants one includable file
```

The public C surface is the sealed ABI.  It does not expose the Lua authoring
DSL, PVM triplets, ASDL objects, or internal stores.  A C program includes the
public declarations, creates a kernel, loads already-encoded `UiProgram` buffers
or builds them with helper appenders, runs frames, draws returned view ops, and
consumes returned events.

Canonical C shape:

```c
#define MLUI_IMPLEMENTATION
#include "mlui_amalgam.c"

mlui_kernel *ui = 0;
mlui_status st = mlui_kernel_init_ex(&config, &ui);
if (st.code != MLUI_OK) { /* handle */ }

st = mlui_load_program(ui, &program, &root);
st = mlui_frame(ui, root, width, height, &raw);

const mlui_view_op *ops = 0;
size_t n_ops = 0;
mlui_view_ops(ui, &ops, &n_ops);

const mlui_event *events = 0;
size_t n_events = 0;
mlui_events(ui, &events, &n_events);

mlui_kernel_close(ui);
```

Ownership law at the C boundary:

| Thing | Owner |
| --- | --- |
| `mlui_kernel*` | MLUI until `mlui_kernel_close` |
| returned op/event/report pointers | borrowed from kernel until next frame/reset/close |
| imported `UiProgram` buffers | borrowed for the call unless retained through explicit resource APIs |
| raw input text | borrowed for `mlui_interact_step` / `mlui_frame` only |
| image/font/backend resources | host-owned handles registered into MLUI records |

The C API should support both allocation profiles:

```text
default allocator       MLUI uses malloc/realloc/free internally
configured allocator    caller supplies alloc/realloc/free callbacks
arena/no-heap profile   caller supplies fixed buffers; oom is a status
```

Status is product-shaped, even when old compatibility functions still return
`int32_t`:

```c
typedef struct mlui_status {
    int32_t code;
    int32_t detail;
    size_t at;
    size_t needed;
} mlui_status;
```

Codes are ABI encodings of region exits at the seal:

```text
MLUI_OK
MLUI_OOM
MLUI_DUPLICATE_ID
MLUI_INVALID_ID
MLUI_INVALID_CHILD
MLUI_UNSUPPORTED_NODE
MLUI_MISSING_NODE
MLUI_MISSING_TEXT
MLUI_TEXT_BACKEND_ERROR
MLUI_DECOR_MISMATCH
MLUI_MALFORMED_OP
MLUI_STACK_UNBALANCED
MLUI_STALE_FOCUS
MLUI_STALE_CAPTURE
MLUI_MISSING_SCROLL
```

The ABI must be versioned:

```c
#define MLUI_ABI_VERSION 1
uint32_t mlui_abi_version(void);
```

Stable row structs are allowed in public C.  Internal stores are opaque.  Public
rows include:

```text
mlui_rect
mlui_color
mlui_program_op / mlui_program
mlui_auth_node / mlui_auth_buffer compatibility aliases
mlui_view_op / mlui_view_buffer
mlui_raw_input
mlui_event / mlui_event_buffer
mlui_report
```

No C caller should depend on the layout of `mlui_kernel`.  If a host needs
resources, it registers typed handles or passes host callbacks.  If a backend
needs to measure text, the C profile should expose a text-measure callback table
rather than hardwire SDL, browser, or platform text into the core.

External C-to-WASM toolchains may wrap the same C artifact, but JavaScript
linear-memory and typed-array bindings are host-owned and not a current MLUI ABI.

## Non-Negotiable Rules

```text
The current lua/ui richness is source material; the current phase shape is the
LLPVM semantic domain-world pipeline.
The native kernel is product/protocol typed, not callback typed.
Auth/Layout/Decor/Solve/View/Report/Event are distinct products.
Render consumes Solve, never recomputes layout.
Text layout is an explicit retained product.
Dynamic paint/value data must not masquerade as structure.
Backends consume ops and produce raw input; they do not own UI semantics.
Public ABI status codes exist only at sealed C boundaries.
The single-file C artifact exposes stable row buffers and an opaque kernel, not
Lalin internals or Lua authoring objects.
UiProgram is the portable frontend contract; Lua, C, and generated tools may all
emit it.
```
