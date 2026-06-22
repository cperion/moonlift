# MLUI as a Real LLPVM VM Stack — Full Spec Blueprint

Status: blueprint v0.1  
Target artifact: Moonlift-native MLUI kernel + LLPVM stack + C embedding profile  
Primary rule: **MLUI is immediate-mode at the authoring layer and retained by construction at the LLPVM phase layer.**

This document redesigns MLUI as a real LLPVM virtual-machine stack. It preserves the original `lua/ui` semantic richness: authored UI is not flattened into a widget-callback API, render ops are not confused with authored ops, text remains an explicit product boundary, backends stay op appliers/input producers, and the public C surface is a sealed ABI over stable rows and opaque handles.

The separate `mlui_bytecode.md` and `mlui_c_api.h` files referenced by the uploaded design were not part of the uploaded file set available to this drafting pass. This blueprint therefore defines a coherent v1 row/ABI contract from the uploaded MLUI, LLPVM, Moonlift, and Design Bible documents. Numeric constants are specified here as v1 defaults, but the implementation rule is stronger: numeric constants must be generated from `mlui_stack.mlua` or tested against it, never hand-maintained in divergent files.

---

## 1. One-sentence machine statement

```text
MLUI consumes one semantic UI world at a time and produces the next semantic UI
world: authored UI becomes expanded UI, validated UI, imported UI, styled UI,
measured UI, laid-out UI, renderable UI, reported frame, and handled frame.
```

The surface remains immediate:

```text
app state + model + input facts -> authored UI stream
```

The runtime is retained because authored streams are fed through LLPVM phases
whose consumed worlds already contain the facts that affect meaning:

```text
fresh authored stream each frame
  + stable semantic ids
  + resource generations / epochs embedded in the relevant world
  + viewport/input/model facts embedded before the phase that needs them
  + LLPVM phase cache
  = retained behavior without retained authoring objects
```

---

## 2. Scope and source of truth

### 2.1 Canonical source file

The canonical stack declaration is:

```text
experiments/mlui-llpvm/mlui_stack.mlua
```

It declares:

```text
LLPVM VM config
languages
language-local type tables
constructors
worlds
machines
phases
phase cache policies
C ABI projection names
row-kind names
validation tables
Moonlift products/protocols/ABI seals
```

Everything else is generated from or mechanically checked against it:

```text
experiments/mlui-llpvm/mlui_header.mlua         compatibility shim over mlui_stack.mlua
experiments/mlui-llpvm/mlui_types.mlua          removed or compatibility alias only if retained
experiments/mlui-llpvm/mlui_bytecode.md         generated readable bytecode contract
experiments/mlui-llpvm/mlui_c_api.h             generated public C declarations/constants
experiments/mlui-llpvm/mlui_build_c.lua         generated artifact builder
experiments/mlui-llpvm/mlui_opcode_tests.lua    generated constant equivalence tests
```

### 2.2 Projection rule

```text
LLPVM typed stream language is canonical.
MLUI fast-row bytecode is a C-friendly projection.
C helper builders are authoring convenience.
Lua no-parens builders are authoring convenience.
Native stores and buffers are runtime materialization.
```

No API other than the stack declaration is allowed to invent semantics.

---

## 3. Design laws

### 3.1 Richness preservation

```text
Tree richness may be encoded.
Tree richness may not disappear.
```

If a semantic union becomes a `kind` byte in an ABI row, that byte belongs to exactly one visitor or consumer protocol. Example owners:

```text
UiAuthNode.kind      -> ui_visit_auth_node
UiComposeNode.kind   -> ui_visit_compose_node
UiStyleAtom.kind     -> ui_visit_style_atom
UiLayoutNode.kind    -> ui_visit_layout_node
UiDecorNode.kind     -> ui_visit_decor_node
UiSolveNode.kind     -> ui_visit_solve_node
UiViewOp.kind        -> ui_visit_view_op
UiPaintOp.kind       -> ui_visit_paint_program
UiRawInput.kind      -> ui_visit_raw_input
UiEvent.kind         -> ui_visit_event
UiKey.kind           -> ui_visit_key
UiValueRecord.kind   -> ui_visit_value
```

Raw `switch kind` is allowed only in the owning visitor/consumer implementation or in code generated directly from the same visitor table. Other phases consume visitor protocols or already-lowered products.

### 3.2 Retention law

Semantic retention is owned by LLPVM phases, not hidden widget state and not ad hoc Lua tables.

```text
LLPVM phase cache owns:
  compose expansion
  auth import/lowering products
  style resolution
  text measurement products where represented as phase outputs
  intrinsic measurement
  solve products
  render op generation
  report derivation / recordings

UiKernel owns:
  native resource stores
  copied content bytes
  host resource handles
  text layout records selected/materialized for C use
  persistent interaction model
  materialized frame buffers
  C borrowed output lifetimes
```

`UiKernel` may contain backing stores used by phase machines. It is not a parallel handwritten semantic cache architecture.

### 3.3 Ownership law

```text
Lua owns authoring convenience and metaprogramming.
LLPVM owns typed UI languages, streams, machines, phase caches, and bytecode images.
Moonlift MLUI runtime owns native stores, durable handles, materialized buffers, and interaction state.
Backends own windows, renderers, fonts, textures, clipboard, IME, and platform event acquisition.
Applications own domain state and consume UiEvent streams.
```

### 3.4 Backend law

Backends consume `UiViewOp` buffers and produce `UiRawInput` buffers. They do not own focus, activation, pointer capture, drag/drop semantics, widget behavior, app state, or layout policy.

### 3.5 Text law

Borrowed text from a backend event is valid only for the dispatch that carries it. Durable text must be copied into `UiContentStore` or app-owned storage. Rendering draws the `UiTextLayoutRef` selected by solve; it must not re-measure or re-wrap.

### 3.6 ABI law

Status codes exist only at sealed C ABI boundaries. Internally, failures are typed continuations.

---

## 4. Stack architecture

### 4.1 Layers

```text
Lua authoring DSL / C builder / serialized tools
  -> typed MLUI LLPVM streams
  -> LLPV bytecode image or MLUI fast-row projection
  -> native load/import boundary
  -> cached LLPVM phases over MLUI worlds
  -> UiKernel stores + interaction model + frame buffers
  -> UiViewOp / UiReport / UiEvent outputs
  -> backend draw + app event handling
```

### 4.2 Canonical pipeline

```text
authored_ui
  -> expand_ui             cache = full
  -> expanded_ui

expanded_ui
  -> validate_ui           cache = record
  -> valid_ui

valid_ui
  -> import_ui             cache = full
  -> imported_ui

imported_ui
  -> style_ui              cache = full
  -> styled_ui

styled_ui
  -> measure_ui            cache = full
  -> measured_ui

measured_ui
  -> layout_ui             cache = full
  -> laid_out_ui

laid_out_ui
  -> render_ui             cache = record
  -> renderable_ui

renderable_ui
  -> report_frame          cache = record
  -> reported_frame

reported_frame
  -> handle_input          cache = none, optionally record for replay
  -> handled_frame
```

### 4.3 Domain Worlds Carry Dependencies

A phase consumes one world and produces one world. If a phase seems to need
several streams or side facts, the input world is wrong. The needed values must
be part of a domain world with a name that makes sense without mentioning the
phase.

```text
Wrong:
  imported_ui + style + env + model -> lower_scene -> scene

Right:
  imported_ui -> styled_ui -> measured_ui -> laid_out_ui
```

World names answer "what domain thing exists now?" Phase names answer "what
transformation happened?"

Core domain-world facts:

```text
authored_ui
  authored compose/auth nodes, stable ids, local state facts

expanded_ui
  canonical auth tree after compose expansion

valid_ui
  validated authored semantics, arity, ids, resource references

imported_ui
  imported node handles plus resource/model/theme/environment epochs required
  to interpret the tree

styled_ui
  imported UI plus resolved style/decor/interaction facts

measured_ui
  styled UI plus intrinsic sizes and selected text layout refs

laid_out_ui
  measured UI plus viewport/scroll facts and final rects

renderable_ui
  laid-out UI plus ordered view ops and render/report stack facts

reported_frame
  renderable UI plus runtime report, hit/focus/scroll facts, current model,
  raw input batch, and frame clock facts

handled_frame
  reported frame after input semantics: semantic events, next interaction
  model, invalidation facts
```

Cache keys are derived from the consumed world identity/content plus the phase
identity and runtime profile. Epochs and resource generations are values inside
the consumed world; they are not side `phase_args`.

Representative embedded products:

```text
UiEnvArgs
  env_class: UiEnvClass
  viewport: UiViewport
  time_ms: u64
  flags: u32

UiThemeArgs
  theme_ref: UiThemeRef
  theme_epoch: u64

UiResourceArgs
  content_epoch: u64
  paint_epoch: u64
  image_epoch: u64
  font_epoch: u64
  value_epoch: u64
  text_layout_epoch: u64

UiInteractionArgs
  model_epoch: u64
  hover_id: UiId
  focus_id: UiId
  capture_id: UiId
  drag_id: UiId
  scroll_epoch: u64

UiSolveArgs
  viewport_w: f32
  viewport_h: f32
  scroll_epoch: u64
  text_layout_epoch: u64

UiRenderArgs
  solve_epoch: u64
  decor_epoch: u64
  paint_epoch: u64
  text_epoch: u64

UiReportArgs
  view_epoch: u64
  model_epoch: u64
```

---

## 5. LLPVM declaration blueprint

`mlui_stack.mlua` must be readable as the type forest and control graph.

```lua
local ll = require "llpvm"

local M = {}

M.vm = ll.vm {
    cache_bytes = 64 * 1024,
}

-- Languages. These name domain states, not implementation files.
M.Authored   = M.vm.language "MluiAuthored"
M.Expanded   = M.vm.language "MluiExpanded"
M.Valid      = M.vm.language "MluiValid"
M.Imported   = M.vm.language "MluiImported"
M.Styled     = M.vm.language "MluiStyled"
M.Measured   = M.vm.language "MluiMeasured"
M.LaidOut    = M.vm.language "MluiLaidOut"
M.Renderable = M.vm.language "MluiRenderable"
M.Reported   = M.vm.language "MluiReported"
M.Handled    = M.vm.language "MluiHandled"

-- Worlds.
M.authored_ui   = M.Authored:world "authored_ui"
M.expanded_ui   = M.Expanded:world "expanded_ui"
M.valid_ui      = M.Valid:world "valid_ui"
M.imported_ui   = M.Imported:world "imported_ui"
M.styled_ui     = M.Styled:world "styled_ui"
M.measured_ui   = M.Measured:world "measured_ui"
M.laid_out_ui   = M.LaidOut:world "laid_out_ui"
M.renderable_ui = M.Renderable:world "renderable_ui"
M.reported_frame = M.Reported:world "reported_frame"
M.handled_frame = M.Handled:world "handled_frame"

-- Machines.
M.m_expand_ui = M.vm.machine "mlui_expand_ui" {
    from = M.authored_ui,
    to = M.expanded_ui,
    entry = "ui_expand",
}

M.m_validate_ui = M.vm.machine "mlui_validate_ui" {
    from = M.expanded_ui,
    to = M.valid_ui,
    entry = "ui_validate",
}

M.m_import_ui = M.vm.machine "mlui_import_ui" {
    from = M.valid_ui,
    to = M.imported_ui,
    entry = "ui_import",
}

M.m_style_ui = M.vm.machine "mlui_style_ui" {
    from = M.imported_ui,
    to = M.styled_ui,
    entry = "ui_style",
}

M.m_measure_ui = M.vm.machine "mlui_measure_ui" {
    from = M.styled_ui,
    to = M.measured_ui,
    entry = "ui_measure",
}

M.m_layout_ui = M.vm.machine "mlui_layout_ui" {
    from = M.measured_ui,
    to = M.laid_out_ui,
    entry = "ui_layout",
}

M.m_render_ui = M.vm.machine "mlui_render_ui" {
    from = M.laid_out_ui,
    to = M.renderable_ui,
    entry = "ui_render",
}

M.m_report_frame = M.vm.machine "mlui_report_frame" {
    from = M.renderable_ui,
    to = M.reported_frame,
    entry = "ui_report_frame",
}

M.m_handle_input = M.vm.machine "mlui_handle_input" {
    from = M.reported_frame,
    to = M.handled_frame,
    entry = "ui_handle_input",
}

-- Phases.
M.expand_ui = M.vm.phase "mlui_expand_ui" {
    from = M.authored_ui,
    to = M.expanded_ui,
    machine = M.m_expand_ui,
    cache = "full",
}

M.validate_ui = M.vm.phase "mlui_validate_ui" {
    from = M.expanded_ui,
    to = M.valid_ui,
    machine = M.m_validate_ui,
    cache = "record",
}

M.import_ui = M.vm.phase "mlui_import_ui" {
    from = M.valid_ui,
    to = M.imported_ui,
    machine = M.m_import_ui,
    cache = "full",
}

M.style_ui = M.vm.phase "mlui_style_ui" {
    from = M.imported_ui,
    to = M.styled_ui,
    machine = M.m_style_ui,
    cache = "full",
}

M.measure_ui = M.vm.phase "mlui_measure_ui" {
    from = M.styled_ui,
    to = M.measured_ui,
    machine = M.m_measure_ui,
    cache = "full",
}

M.layout_ui = M.vm.phase "mlui_layout_ui" {
    from = M.measured_ui,
    to = M.laid_out_ui,
    machine = M.m_layout_ui,
    cache = "full",
}

M.render_ui = M.vm.phase "mlui_render_ui" {
    from = M.laid_out_ui,
    to = M.renderable_ui,
    machine = M.m_render_ui,
    cache = "record",
}

M.report_frame = M.vm.phase "mlui_report_frame" {
    from = M.renderable_ui,
    to = M.reported_frame,
    machine = M.m_report_frame,
    cache = "record",
}

M.handle_input = M.vm.phase "mlui_handle_input" {
    from = M.reported_frame,
    to = M.handled_frame,
    machine = M.m_handle_input,
    cache = nil,
}

return M
```

---

## 6. Scalar, handle, and common product spec

### 6.1 Scalar policy

Public C ABI scalar mapping:

| MLUI type | C type | Meaning |
| --- | --- | --- |
| `UiId` | `uint64_t` | semantic authoring id; 0 means anonymous/invalid where noted |
| `UiRef` | `uint32_t` | slot+generation runtime handle; 0 invalid |
| `UiEpoch` | `uint64_t` | monotonic generation/epoch/version |
| `UiKind` | `uint16_t` | row kind / semantic variant |
| `UiFlags` | `uint32_t` | bitset |
| `UiIndex` | `uint32_t` or `size_t` | ABI-local indices; row fields use `uint32_t`, pointer-count APIs use `size_t` |
| `UiScalar` | `float` | logical-pixel geometric scalar |

Moonlift internal `index` remains pointer-sized. ABI rows use fixed-width scalars for portability.

### 6.2 Handles

Handles are nominal in Moonlift and encoded in C as `uint32_t` by the default v1 profile:

```text
bits  0..23  slot index + 1
bits 24..31  generation
0            invalid
```

The store slot carries:

```text
live: bool
generation: u8
product: T
```

Resolver algorithm:

```text
unpack ref -> index, generation
ref == 0 -> missing(ref)
index out of range -> missing(ref)
slot.live == false -> missing(ref)
slot.generation != generation -> stale(ref)
otherwise -> borrowed(lease(kernel) ptr(slot.product))
```

If a target requires more than 16,777,215 live slots or wider generations, the profile must switch to `uint64_t` handles and bump `MLUI_ABI_VERSION`.

### 6.3 Common C structs

```c
typedef uint64_t mlui_id;
typedef uint32_t mlui_ref;
typedef uint64_t mlui_epoch;

typedef struct mlui_vec2 {
    float x;
    float y;
} mlui_vec2;

typedef struct mlui_rect {
    float x;
    float y;
    float w;
    float h;
} mlui_rect;

typedef struct mlui_insets {
    float left;
    float top;
    float right;
    float bottom;
} mlui_insets;

typedef struct mlui_color {
    float r;
    float g;
    float b;
    float a;
} mlui_color;

typedef struct mlui_range {
    uint32_t first;
    uint32_t count;
} mlui_range;

typedef struct mlui_size {
    float w;
    float h;
} mlui_size;
```

### 6.4 Common handles

Moonlift header names:

```moonlift
handle UiKernelRef     : u32 invalid 0 domain UiKernelStore     target UiKernel end
handle UiNodeRef       : u32 invalid 0 domain UiNodeStore       target UiNodeRecord end
handle UiContentRef    : u32 invalid 0 domain UiContentStore    target UiContent end
handle UiTextLayoutRef : u32 invalid 0 domain UiTextLayoutStore target UiTextLayout end
handle UiPaintRef      : u32 invalid 0 domain UiPaintStore      target UiPaintProgramSet end
handle UiImageRef      : u32 invalid 0 domain UiImageStore      target UiImageRecord end
handle UiFontRef       : u32 invalid 0 domain UiFontStore       target UiFontRecord end
handle UiValueRef      : u32 invalid 0 domain UiValueStore      target UiValueRecord end
handle UiThemeRef      : u32 invalid 0 domain UiThemeStore      target UiTheme end
```

C aliases:

```c
typedef mlui_ref mlui_kernel_ref;
typedef mlui_ref mlui_node_ref;
typedef mlui_ref mlui_content_ref;
typedef mlui_ref mlui_text_layout_ref;
typedef mlui_ref mlui_paint_ref;
typedef mlui_ref mlui_image_ref;
typedef mlui_ref mlui_font_ref;
typedef mlui_ref mlui_value_ref;
typedef mlui_ref mlui_theme_ref;
```

---

## 7. Enumerations and bitsets

Numeric values in this section are the v1 fast-row projection. They must be generated from `mlui_stack.mlua`.

### 7.1 ABI version and magic

```c
#define MLUI_ABI_VERSION 1u
#define MLUI_MAGIC_U32 0x49554c4du /* 'M''L''U''I' little-endian */
#define MLUI_LLPV_MAGIC_U32 0x56504c4cu /* 'L''L''P''V' little-endian */
```

### 7.2 Status codes

```c
typedef enum mlui_status_code {
    MLUI_OK                   = 0,
    MLUI_OOM                  = 1,
    MLUI_DUPLICATE_ID         = 2,
    MLUI_INVALID_ID           = 3,
    MLUI_INVALID_CHILD        = 4,
    MLUI_UNSUPPORTED_NODE     = 5,
    MLUI_MISSING_NODE         = 6,
    MLUI_MISSING_TEXT         = 7,
    MLUI_TEXT_BACKEND_ERROR   = 8,
    MLUI_DECOR_MISMATCH       = 9,
    MLUI_MALFORMED_OP         = 10,
    MLUI_STACK_UNBALANCED     = 11,
    MLUI_STALE_FOCUS          = 12,
    MLUI_STALE_CAPTURE        = 13,
    MLUI_MISSING_SCROLL       = 14,
    MLUI_INVALID_HEADER       = 15,
    MLUI_INVALID_SECTION      = 16,
    MLUI_INVALID_OPCODE       = 17,
    MLUI_INVALID_RANGE        = 18,
    MLUI_INVALID_ARITY        = 19,
    MLUI_MISSING_RESOURCE     = 20,
    MLUI_UNSUPPORTED_FEATURE  = 21,
    MLUI_STALE_REF            = 22,
    MLUI_BUSY                 = 23,
    MLUI_BAD_ARGUMENT         = 24,
    MLUI_BACKEND_ERROR        = 25
} mlui_status_code;

typedef struct mlui_status {
    int32_t code;
    int32_t detail;
    size_t at;
    size_t needed;
} mlui_status;
```

Status fields:

```text
code      one mlui_status_code
detail    small code/kind/section/id fragment depending on status
at        byte offset, row index, or product index where applicable
needed    bytes/elements needed for OOM; otherwise 0
```

### 7.3 Root kind

```c
typedef enum mlui_root_kind {
    MLUI_ROOT_NONE      = 0,
    MLUI_ROOT_AUTH      = 1,
    MLUI_ROOT_COMPOSE   = 2,
    MLUI_ROOT_LLPV      = 3
} mlui_root_kind;
```

### 7.4 Axes, directions, roles

```c
typedef enum mlui_axis {
    MLUI_AXIS_NONE = 0,
    MLUI_AXIS_X    = 1,
    MLUI_AXIS_Y    = 2,
    MLUI_AXIS_BOTH = 3
} mlui_axis;

typedef enum mlui_direction {
    MLUI_DIR_NONE     = 0,
    MLUI_DIR_LEFT     = 1,
    MLUI_DIR_RIGHT    = 2,
    MLUI_DIR_UP       = 3,
    MLUI_DIR_DOWN     = 4,
    MLUI_DIR_NEXT     = 5,
    MLUI_DIR_PREV     = 6,
    MLUI_DIR_INWARD   = 7,
    MLUI_DIR_OUTWARD  = 8
} mlui_direction;

typedef enum mlui_input_role {
    MLUI_ROLE_NONE       = 0,
    MLUI_ROLE_BUTTON     = 1,
    MLUI_ROLE_CHECKBOX   = 2,
    MLUI_ROLE_SLIDER     = 3,
    MLUI_ROLE_TEXT_FIELD = 4,
    MLUI_ROLE_MENU_ITEM  = 5,
    MLUI_ROLE_TAB        = 6,
    MLUI_ROLE_CANVAS     = 7,
    MLUI_ROLE_CUSTOM     = 255
} mlui_input_role;
```

### 7.5 State mask

```c
typedef enum mlui_state_mask_bits {
    MLUI_STATE_HOVERED        = 1u << 0,
    MLUI_STATE_PRESSED        = 1u << 1,
    MLUI_STATE_ACTIVE         = 1u << 2,
    MLUI_STATE_FOCUSED        = 1u << 3,
    MLUI_STATE_DISABLED       = 1u << 4,
    MLUI_STATE_SELECTED       = 1u << 5,
    MLUI_STATE_DRAGGING       = 1u << 6,
    MLUI_STATE_DROP_HOVERED   = 1u << 7,
    MLUI_STATE_EDITING        = 1u << 8,
    MLUI_STATE_INVALID        = 1u << 9,
    MLUI_STATE_MODAL_ACTIVE   = 1u << 10
} mlui_state_mask_bits;
```

---

## 8. Language type forest

This section names the semantic constructors. The row ABI may encode these with `kind`, but the semantic constructors remain the design.

### 8.1 Core language

```moonlift
local Id        = moon.u64
local Ref       = moon.u32
local Epoch     = moon.u64
local Flags     = moon.u32
local Kind      = moon.u16
local Index32   = moon.u32

local Vec2 = struct MluiCore_Vec2
    x: f32,
    y: f32
end

local Rect = struct MluiCore_Rect
    x: f32,
    y: f32,
    w: f32,
    h: f32
end

local Range = struct MluiCore_Range
    first: u32,
    count: u32
end
```

### 8.2 Env language

`UiEnvClass` is a compact product of environment facts used by style and layout:

```text
UiEnvClass
  breakpoint: u8       none/sm/md/lg/xl/custom
  color_scheme: u8     light/dark/high_contrast
  motion: u8           normal/reduced
  density: u8          compact/normal/spacious
  pointer: u8          coarse/fine/none
  platform: u8         generic/desktop/mobile/browser/embedded
  flags: u32
```

Constructors:

```text
MluiEnv.Class.Default
MluiEnv.Class.Custom(breakpoint, color_scheme, motion, density, pointer, platform, flags)
MluiEnv.Viewport(width, height, device_scale)
```

### 8.3 Theme language

`UiTheme` contains scale products, not backend resources:

```text
UiTheme
  id: UiThemeRef
  epoch: UiEpoch
  palette_range: Range
  spacing_range: Range
  font_range: Range
  radius_range: Range
  border_range: Range
  opacity_range: Range
```

Scale records:

```text
UiPaletteEntry(name_id, color)
UiSpacingEntry(name_id, value)
UiFontEntry(name_id, family_content_ref, font_ref, size, weight, style_flags)
UiRadiusEntry(name_id, radius)
UiBorderEntry(name_id, width, color)
UiOpacityEntry(name_id, opacity)
```

Theme constructors:

```text
Theme.Palette(name, color)
Theme.Spacing(name, value)
Theme.Font(name, content_ref, font_ref, size, weight, flags)
Theme.Radius(name, value)
Theme.Border(name, width, color)
Theme.Opacity(name, value)
Theme.Theme(ranges...)
```

### 8.4 Style language

Style is split into tokens, conditions, and atoms.

```text
UiStyleToken
  id: UiId
  first_cond: u32
  cond_count: u32
  first_atom: u32
  atom_count: u32
  order: u32
  flags: u32

UiStyleCond
  kind: UiStyleCondKind
  lhs: u32
  op: u8
  rhs_i: i32
  rhs_f: f32
  rhs_id: UiId
  flags: u32

UiStyleAtom
  kind: UiStyleAtomKind
  target: u8              layout/decor/text/paint/interaction
  a: u32
  b: u32
  c: u32
  x: f32
  y: f32
  z: f32
  color: mlui_color
```

Semantic style atom constructors:

```text
Style.Display(kind)
Style.Position(kind)
Style.Width(length)
Style.Height(length)
Style.MinWidth(length)
Style.MinHeight(length)
Style.MaxWidth(length)
Style.MaxHeight(length)
Style.Margin(insets)
Style.Padding(insets)
Style.Gap(x, y)
Style.FlexDirection(row|column)
Style.FlexGrow(value)
Style.FlexShrink(value)
Style.FlexBasis(length)
Style.AlignItems(value)
Style.JustifyContent(value)
Style.GridTracks(axis, first_track, count)
Style.Overflow(axis, policy)
Style.BackgroundColor(color_or_theme_ref)
Style.ForegroundColor(color_or_theme_ref)
Style.BorderColor(color_or_theme_ref)
Style.BorderWidth(width)
Style.Radius(radius)
Style.Opacity(value)
Style.Font(font_ref_or_theme_name)
Style.FontSize(size)
Style.FontWeight(weight)
Style.TextAlign(align)
Style.LineHeight(value)
Style.Cursor(cursor)
Style.LayerOrder(order)
Style.UserFlag(flag)
```

Length representation:

```text
UiLength
  kind: auto | px | fraction | percent | fit | min_content | max_content | clamp
  value: f32
  min: f32
  max: f32
```

Grid track representation:

```text
UiTrack
  min: UiLength
  max: UiLength
  repeat: u32
  flags: u32
```

Style resolution phase:

```text
Input:  UiStyleToken stream + UiTheme + UiEnvClass + UiState facts
Output: UiLayoutStyle + UiDecorStyle + UiInteractionStyle
Cache:  full
Failure exits: invalid_atom(kind), missing_theme, missing_resource, oom
```

### 8.5 Resource language

```text
Resource.Content(bytes_ref, byte_len, encoding, layout_affecting, epoch)
Resource.TextLayout(lines, runs, glyphs, clusters, carets, epoch)
Resource.PaintProgram(first_op, op_count, epoch)
Resource.Image(host_key, width, height, format, epoch)
Resource.Font(host_key, family_content_ref, size, weight, style, epoch)
Resource.Value(kind, payload, epoch)
```

Value record semantic variants:

```text
Value.None
Value.Bool(value)
Value.I32(value)
Value.U32(value)
Value.F32(value)
Value.F64(value)
Value.Id(value)
Value.Ref(value)
Value.Range(min, max, value)
Value.Color(color)
Value.Text(content_ref)
Value.Custom(kind, data_ref)
```

### 8.6 Auth language

Auth nodes are authored semantic nodes. They are not draw ops.

Constructors:

```text
Auth.Empty(id?, state, styles)
Auth.Fragment(id?, children)
Auth.Box(id, styles, children, source_state)
Auth.Text(id, content_ref, styles, source_state)
Auth.TextInline(id, content_ref, styles, source_state)
Auth.TextRef(id, text_layout_ref, styles, source_state)
Auth.Paint(id, paint_ref_or_range, styles, source_state)
Auth.Canvas(id, value_ref, paint_ref_or_range, styles, source_state)
Auth.Image(id, image_ref, styles, source_state)
Auth.Scroll(id, axis, policy, child, styles, source_state)
Auth.InputSurface(id, role, policy, child, styles, source_state)
Auth.DragSource(id, drag_policy, child, styles, source_state)
Auth.DropTarget(id, drop_policy, child, styles, source_state)
Auth.FocusScope(id, focus_policy, children, styles, source_state)
Auth.Layer(id, layer_kind, order, child, styles, source_state)
Auth.Overlay(id, anchor_id, placement, child, styles, source_state)
Auth.Modal(id, barrier_policy, child, styles, source_state)
Auth.TextField(id, content_ref, text_field_state_ref, styles, source_state)
Auth.Slot(id, slot_kind, value_ref, child?, styles, source_state)
```

Minimum row payload:

```text
UiAuthNode
  kind: u16
  id: UiId
  parent: u32                  optional import/debug parent; 0 means none
  first_child: u32
  child_count: u32
  first_style: u32
  style_count: u32
  first_paint: u32
  paint_count: u32
  content_ref: UiContentRef
  text_layout_ref: UiTextLayoutRef
  image_ref: UiImageRef
  font_ref: UiFontRef
  value_ref: UiValueRef
  other_id: UiId               anchor, paired target, label, group, etc.
  axis: u8
  role: u8
  policy: u16
  state_mask: u32
  flags: u32
```

Auth row kind values:

```c
typedef enum mlui_auth_kind {
    MLUI_AUTH_EMPTY         = 0,
    MLUI_AUTH_FRAGMENT      = 1,
    MLUI_AUTH_BOX           = 2,
    MLUI_AUTH_TEXT          = 3,
    MLUI_AUTH_TEXT_INLINE   = 4,
    MLUI_AUTH_TEXT_REF      = 5,
    MLUI_AUTH_PAINT         = 6,
    MLUI_AUTH_CANVAS        = 7,
    MLUI_AUTH_IMAGE         = 8,
    MLUI_AUTH_SCROLL        = 9,
    MLUI_AUTH_INPUT_SURFACE = 10,
    MLUI_AUTH_DRAG_SOURCE   = 11,
    MLUI_AUTH_DROP_TARGET   = 12,
    MLUI_AUTH_FOCUS_SCOPE   = 13,
    MLUI_AUTH_LAYER         = 14,
    MLUI_AUTH_OVERLAY       = 15,
    MLUI_AUTH_MODAL         = 16,
    MLUI_AUTH_TEXT_FIELD    = 17,
    MLUI_AUTH_SLOT          = 18
} mlui_auth_kind;
```

Arity rules:

```text
Empty/Text/TextInline/TextRef/Paint/Canvas/Image/TextField without adornment: 0 children
Box/Fragment/FocusScope: any child_count
Scroll/InputSurface/DragSource/DropTarget/Layer/Overlay/Modal: exactly 1 child
Slot: 0 or 1 child depending flags
```

### 8.7 Compose language

Compose nouns are not Lua-only sugar. They validate and then expand through `ui_expand`.

Constructors:

```text
Compose.Panel(id, header?, body, footer?, styles, source_state)
Compose.ScrollPanel(id, header?, body, footer?, axis, styles, source_state)
Compose.HSplit(id, panes, ratios?, styles, source_state)
Compose.VSplit(id, panes, ratios?, styles, source_state)
Compose.Workbench(id, toolbar?, sidebar?, main, bottom?, styles, source_state)
```

Row payload:

```text
UiComposeNode
  kind: u16
  id: UiId
  first_child: u32
  child_count: u32
  first_style: u32
  style_count: u32
  first_weight: u32
  weight_count: u32
  axis: u8
  flags: u32
```

Kind values:

```c
typedef enum mlui_compose_kind {
    MLUI_COMPOSE_PANEL        = 1,
    MLUI_COMPOSE_SCROLL_PANEL = 2,
    MLUI_COMPOSE_HSPLIT       = 3,
    MLUI_COMPOSE_VSPLIT       = 4,
    MLUI_COMPOSE_WORKBENCH    = 5
} mlui_compose_kind;
```

Expansion rules:

```text
Panel        -> box/header/body/footer composition
ScrollPanel  -> panel body wrapped in Scroll
HSplit       -> flex/grid row with pane children
VSplit       -> flex/grid column with pane children
Workbench    -> named toolbar/sidebar/main/bottom regions
```

### 8.8 Scene language

Scene is the lower product split into layout and decor.

```text
UiSceneBuffer
  layout_nodes: ptr(UiLayoutNode)
  layout_count: index
  decor_nodes: ptr(UiDecorNode)
  decor_count: index
  children: ptr(u32)
  child_count: index
  tracks: ptr(UiTrack)
  track_count: index
  epoch: UiEpoch
```

`UiLayoutNode` semantic variants:

```text
Layout.Empty
Layout.Fragment
Layout.Flow
Layout.FlexRow
Layout.FlexColumn
Layout.Grid
Layout.Text
Layout.TextRef
Layout.Paint
Layout.Canvas
Layout.Image
Layout.Scroll
Layout.InputSurface
Layout.DragSource
Layout.DropTarget
Layout.FocusScope
Layout.Layer
Layout.Overlay
Layout.Modal
Layout.TextField
```

`UiDecorNode` semantic variants:

```text
Decor.None
Decor.Box(visuals)
Decor.Text(text_style, content_ref/layout_ref)
Decor.Paint(paint_ref/range)
Decor.Image(image_ref)
Decor.Cursor(cursor)
Decor.Hit(policy)
Decor.Focus(policy)
Decor.Drag(policy)
Decor.Drop(policy)
Decor.Layer(kind, order)
Decor.Overlay(anchor, placement)
Decor.ModalBarrier(policy)
```

Layout row payload:

```text
UiLayoutNode
  kind: u16
  id: UiId
  first_child: u32
  child_count: u32
  first_track: u32
  track_count: u32
  style_index: u32
  content_ref: UiContentRef
  text_layout_ref: UiTextLayoutRef
  image_ref: UiImageRef
  value_ref: UiValueRef
  axis: u8
  flags: u32
```

Decor row payload:

```text
UiDecorNode
  kind: u16
  id: UiId
  visual_index: u32
  text_style_index: u32
  paint_first: u32
  paint_count: u32
  content_ref: UiContentRef
  text_layout_ref: UiTextLayoutRef
  image_ref: UiImageRef
  cursor: u16
  role: u8
  policy: u16
  layer_kind: u8
  placement: u8
  order: i32
  flags: u32
```

### 8.9 Measure language

Measurement products:

```text
UiIntrinsicSize
  min_w: f32
  min_h: f32
  pref_w: f32
  pref_h: f32
  max_w: f32
  max_h: f32
  baseline: f32
  flags: u32

UiMeasureNode
  id: UiId
  layout_index: u32
  intrinsic: UiIntrinsicSize
  text_layout_ref: UiTextLayoutRef
  epoch: UiEpoch
```

Required measurement cases:

```text
empty/fragment
flow
flex row/column
grid subset declared in ASDL
text leaf with UiContentRef
text ref
paint/canvas
scroll wrapper
input/drag/drop/focus/layer/overlay/modal wrappers
```

Text measurement rule:

```text
Use an existing UiTextLayoutRef when valid for (content_ref, font_ref, width_constraint, content_epoch, font_epoch, text_backend_epoch).
Otherwise ask the configured text measurement service.
Approximate fallback is allowed only when MLUI_CONFIG_APPROX_TEXT is set.
Render never measures.
```

### 8.10 Solve language

```text
UiSolveNode
  kind: u16
  id: UiId
  layout_index: u32
  decor_index: u32
  parent: u32
  first_child: u32
  child_count: u32
  border_rect: mlui_rect
  content_rect: mlui_rect
  clip_rect: mlui_rect
  scroll_x: f32
  scroll_y: f32
  content_w: f32
  content_h: f32
  text_layout_ref: UiTextLayoutRef
  flags: u32
```

Solve responsibilities:

```text
consume UiMeasureWorld / UiSceneBuffer
place every layout node
compute border/content/clip rects
compute scroll content extents
select text layout refs
preserve interaction wrappers
fail on missing_scene/missing_text/text_backend_error/unsupported_layout/oom
```

### 8.11 View language

`UiViewOp` is render/runtime output. It is not an authored op.

Semantic constructors:

```text
View.Box(id, rect, visual)
View.Text(id, rect, text_layout_ref, text_style)
View.Paint(id, rect, paint_ref/range)
View.PushClipRect(rect)
View.PopClip
View.PushTx(dx, dy)
View.PopTx
View.PushScroll(id, viewport_rect, content_w, content_h, scroll_x, scroll_y)
View.PopScroll
View.Hit(id, rect, role, policy)
View.Focus(id, rect, policy)
View.Cursor(id, rect, cursor)
View.DragSource(id, rect, policy)
View.DropTarget(id, rect, policy)
View.DropSlot(id, rect, other_id, policy)
View.BeginFocusScope(id, rect, policy)
View.EndFocusScope(id)
View.BeginLayer(id, layer_kind, order)
View.EndLayer(id)
View.Overlay(id, anchor_id, rect, placement)
View.ModalBarrier(id, rect, policy)
```

Kind values:

```c
typedef enum mlui_view_kind {
    MLUI_VIEW_BOX               = 1,
    MLUI_VIEW_TEXT              = 2,
    MLUI_VIEW_PAINT             = 3,
    MLUI_VIEW_PUSH_CLIP_RECT    = 4,
    MLUI_VIEW_POP_CLIP          = 5,
    MLUI_VIEW_PUSH_TX           = 6,
    MLUI_VIEW_POP_TX            = 7,
    MLUI_VIEW_PUSH_SCROLL       = 8,
    MLUI_VIEW_POP_SCROLL        = 9,
    MLUI_VIEW_HIT               = 10,
    MLUI_VIEW_FOCUS             = 11,
    MLUI_VIEW_CURSOR            = 12,
    MLUI_VIEW_DRAG_SOURCE       = 13,
    MLUI_VIEW_DROP_TARGET       = 14,
    MLUI_VIEW_DROP_SLOT         = 15,
    MLUI_VIEW_BEGIN_FOCUS_SCOPE = 16,
    MLUI_VIEW_END_FOCUS_SCOPE   = 17,
    MLUI_VIEW_BEGIN_LAYER       = 18,
    MLUI_VIEW_END_LAYER         = 19,
    MLUI_VIEW_OVERLAY           = 20,
    MLUI_VIEW_MODAL_BARRIER     = 21
} mlui_view_kind;
```

C row:

```c
typedef struct mlui_view_op {
    uint16_t kind;
    uint16_t axis_role_policy_hi;
    uint32_t flags;
    mlui_id id;
    mlui_id other_id;
    mlui_rect rect;
    uint32_t first;
    uint32_t count;
    mlui_ref content_ref;
    mlui_ref text_layout_ref;
    mlui_ref paint_ref;
    mlui_ref image_ref;
    int32_t order;
    float dx;
    float dy;
    float content_w;
    float content_h;
} mlui_view_op;
```

Payload law:

```text
kind        selects variant
id          semantic surface id
other_id    paired id, overlay anchor, drop slot peer, etc.
rect        local op rect or viewport
first/count range into paint/style/text/resource rows
axis/role/policy/cursor/layer_kind/placement encoded in small enum fields or flags
order       layer order
dx/dy       transform deltas
content_w/h scroll extents
```

Stack discipline:

```text
PushTx / PopTx
PushClipRect / PopClip
PushScroll / PopScroll
BeginFocusScope / EndFocusScope
BeginLayer / EndLayer
```

Unbalanced stack is `MLUI_STACK_UNBALANCED`. Malformed row is `MLUI_MALFORMED_OP`.

### 8.12 Report language

`UiReport` is frame-local interaction fact output derived from the same `UiViewOp` stream used for drawing.

```text
UiReport
  epoch: UiEpoch
  viewport: mlui_rect
  pointer_x: f32
  pointer_y: f32
  hover_id: UiId
  cursor_id: UiId
  cursor: u16
  scroll_target_id: UiId
  modal_depth: u32
  hit_first/hit_count
  focus_first/focus_count
  scroll_first/scroll_count
  drag_first/drag_count
  drop_first/drop_count
  layer_first/layer_count
  overlay_first/overlay_count
  modal_first/modal_count
  scope_first/scope_count
```

Fact records:

```text
UiHitBox(id, rect, role, policy, order, layer)
UiFocusBox(id, rect, policy, scope_id, order)
UiScrollBox(id, viewport_rect, content_w, content_h, scroll_x, scroll_y, axis, policy)
UiDragBox(id, rect, policy)
UiDropBox(id, rect, policy, slot_id)
UiLayerBox(id, order, kind, range)
UiOverlayBox(id, anchor_id, rect, placement)
UiModalBarrier(id, rect, policy)
UiFocusScope(id, rect, policy, parent_scope_id)
```

Report builder responsibilities:

```text
maintain transform stack
maintain clip stack
maintain scroll stack
maintain focus-scope stack
maintain layer/modal stack
compute absolute rects
collect facts
select topmost hover/cursor/scroll ids by stream order and current pointer
return malformed_op or stack_unbalanced on bad stream
never build a second hidden tree
```

### 8.13 Input language

Raw input is backend-independent.

Constructors:

```text
Input.PointerMoved(x, y)
Input.PointerPressed(button, x, y)
Input.PointerReleased(button, x, y)
Input.PointerCancelled
Input.WheelMoved(dx, dy, x, y)
Input.KeyPressed(key, mods, repeat)
Input.KeyReleased(key, mods)
Input.TextInput(text)
Input.TextEditing(text, start, length)
Input.FocusMove(direction)
Input.FocusLost
Input.ActivateFocused
Input.CancelInteraction
```

Kind values:

```c
typedef enum mlui_raw_input_kind {
    MLUI_RAW_POINTER_MOVED      = 1,
    MLUI_RAW_POINTER_PRESSED    = 2,
    MLUI_RAW_POINTER_RELEASED   = 3,
    MLUI_RAW_POINTER_CANCELLED  = 4,
    MLUI_RAW_WHEEL_MOVED        = 5,
    MLUI_RAW_KEY_PRESSED        = 6,
    MLUI_RAW_KEY_RELEASED       = 7,
    MLUI_RAW_TEXT_INPUT         = 8,
    MLUI_RAW_TEXT_EDITING       = 9,
    MLUI_RAW_FOCUS_MOVE         = 10,
    MLUI_RAW_FOCUS_LOST         = 11,
    MLUI_RAW_ACTIVATE_FOCUSED   = 12,
    MLUI_RAW_CANCEL_INTERACTION = 13
} mlui_raw_input_kind;
```

C row:

```c
typedef struct mlui_raw_input {
    uint16_t kind;
    uint16_t button;
    uint32_t key;
    uint32_t mods;
    uint32_t direction;
    uint32_t repeat_;
    float x;
    float y;
    float dx;
    float dy;
    const uint8_t *text;
    size_t text_len;
    uint32_t text_start;
    uint32_t text_length;
} mlui_raw_input;

typedef struct mlui_raw_input_buffer {
    const mlui_raw_input *items;
    size_t count;
} mlui_raw_input_buffer;
```

Raw input contains no semantic target id. Targeting is derived from `UiReport` and `UiModel`.

### 8.14 Model language

`UiModel` is persistent interaction state.

```text
UiModel
  epoch: UiEpoch
  pointer_x: f32
  pointer_y: f32
  hover_id: UiId
  pressed_id: UiId
  capture_id: UiId
  focus_id: UiId
  active_id: UiId
  drag_id: UiId
  drag_state: u8
  drag_start_x: f32
  drag_start_y: f32
  modal_scope_id: UiId
  focus_scope_id: UiId
  scroll_epoch: UiEpoch
  scroll_store_ref: UiScrollStoreRef/internal
```

Scroll records:

```text
UiScrollState
  id: UiId
  x: f32
  y: f32
  content_w: f32
  content_h: f32
  viewport_w: f32
  viewport_h: f32
  epoch: UiEpoch
```

Text edit records:

```text
UiTextEditState
  id: UiId
  cursor: u32
  selection_start: u32
  selection_end: u32
  composing_start: u32
  composing_len: u32
  flags: u32
  epoch: UiEpoch

UiTextFieldState
  id: UiId
  content_ref: UiContentRef
  edit_state_ref: UiValueRef or internal text-edit handle
  placeholder_ref: UiContentRef
  flags: u32
  epoch: UiEpoch
```

### 8.15 Event language

Semantic event constructors:

```text
Event.HoverChanged(id, hovered)
Event.Pressed(id, button)
Event.Released(id, button)
Event.Activated(id)
Event.FocusChanged(old_id, new_id)
Event.ScrollChanged(id, x, y)
Event.DragStarted(id, x, y)
Event.DragMoved(id, x, y, dx, dy)
Event.DragEnded(id, x, y)
Event.DragCancelled(id)
Event.Dropped(source_id, target_id, slot_id)
Event.TextInput(id, text)
Event.TextEditing(id, text, start, length)
Event.TextInputWithoutFocus(text)
Event.Cancelled(id)
Event.CaptureChanged(old_id, new_id)
```

Kind values:

```c
typedef enum mlui_event_kind {
    MLUI_EVENT_HOVER_CHANGED        = 1,
    MLUI_EVENT_PRESSED              = 2,
    MLUI_EVENT_RELEASED             = 3,
    MLUI_EVENT_ACTIVATED            = 4,
    MLUI_EVENT_FOCUS_CHANGED        = 5,
    MLUI_EVENT_SCROLL_CHANGED       = 6,
    MLUI_EVENT_DRAG_STARTED         = 7,
    MLUI_EVENT_DRAG_MOVED           = 8,
    MLUI_EVENT_DRAG_ENDED           = 9,
    MLUI_EVENT_DRAG_CANCELLED       = 10,
    MLUI_EVENT_DROPPED              = 11,
    MLUI_EVENT_TEXT_INPUT           = 12,
    MLUI_EVENT_TEXT_EDITING         = 13,
    MLUI_EVENT_TEXT_INPUT_NO_FOCUS  = 14,
    MLUI_EVENT_CANCELLED            = 15,
    MLUI_EVENT_CAPTURE_CHANGED      = 16
} mlui_event_kind;
```

C row:

```c
typedef struct mlui_event {
    uint16_t kind;
    uint16_t button;
    uint32_t key;
    uint32_t mods;
    uint32_t flags;
    mlui_id id;
    mlui_id other_id;
    mlui_id third_id;
    float x;
    float y;
    float dx;
    float dy;
    const uint8_t *text;
    size_t text_len;
    uint32_t text_start;
    uint32_t text_length;
} mlui_event;

typedef struct mlui_event_buffer {
    const mlui_event *items;
    size_t count;
} mlui_event_buffer;
```

Event text pointer is borrowed from the frame event buffer and valid until next `mlui_clear_events`, `mlui_frame`, reset, or close. Applications that retain it must copy.

---

## 9. Paint and text products

### 9.1 Paint program

Paint is retained resource data plus view op references.

Semantic paint constructors:

```text
Paint.Line(p0, p1, stroke)
Paint.Polyline(points, stroke)
Paint.Polygon(points, fill, stroke?)
Paint.Rect(rect, fill, stroke?, radius?)
Paint.Circle(center, radius, fill, stroke?)
Paint.Arc(center, radius, start, sweep, stroke)
Paint.Bezier(p0, p1, p2, p3, stroke)
Paint.Mesh(vertices, indices, material)
Paint.Image(image_ref, src_rect, dst_rect, tint)
```

C records:

```c
typedef struct mlui_paint_point {
    float x;
    float y;
} mlui_paint_point;

typedef struct mlui_paint_vertex {
    float x;
    float y;
    float u;
    float v;
    mlui_color color;
} mlui_paint_vertex;

typedef struct mlui_paint_op {
    uint16_t kind;
    uint16_t stroke_join_cap;
    uint32_t flags;
    uint32_t first;
    uint32_t count;
    mlui_rect rect;
    mlui_color fill;
    mlui_color stroke;
    float stroke_width;
    float radius;
    mlui_ref image_ref;
} mlui_paint_op;
```

`ui_visit_paint_program` owns `mlui_paint_op.kind` decoding.

### 9.2 Text content

```text
UiContent
  bytes: owned/copied byte buffer
  byte_len: index
  encoding: utf8 | utf16 | backend_native
  layout_affecting: bool
  content_epoch: UiEpoch
```

Retain rule:

```text
ui_content_retain copies bytes.
Borrowed backend text must never become durable by pointer retention.
```

### 9.3 Text layout

```text
UiTextLayout
  content_ref: UiContentRef
  font_ref: UiFontRef
  width_constraint: f32
  epoch: UiEpoch
  first_line/count
  first_run/count
  first_glyph/count
  first_cluster/count
  first_caret/count
```

```c
typedef struct mlui_text_line {
    uint32_t first_run;
    uint32_t run_count;
    float x;
    float y;
    float w;
    float h;
    float baseline;
} mlui_text_line;

typedef struct mlui_text_run {
    uint32_t first_glyph;
    uint32_t glyph_count;
    mlui_ref font_ref;
    mlui_color color;
    float x;
    float y;
    float advance;
    uint32_t flags;
} mlui_text_run;

typedef struct mlui_glyph {
    uint32_t glyph_id;
    uint32_t cluster;
    float x;
    float y;
    float advance;
    float offset_x;
    float offset_y;
} mlui_glyph;

typedef struct mlui_text_cluster {
    uint32_t byte_start;
    uint32_t byte_len;
    uint32_t first_glyph;
    uint32_t glyph_count;
} mlui_text_cluster;

typedef struct mlui_caret_boundary {
    uint32_t byte_index;
    float x;
    float y;
    float h;
    uint32_t flags;
} mlui_caret_boundary;
```

Text layout is produced by the text measurement service or imported resource records. Rendering only consumes it.

---

## 10. Program bytecode and row ABI

MLUI supports two frontends:

```text
1. Canonical LLPV image: portable LLPVM program bytes.
2. MLUI fast-row profile: stable C row arrays generated from the same stack.
```

Both must validate through the same semantic validation table and import into the same phase graph.

### 10.1 LLPV canonical image

The canonical image uses the LLPVM bytecode format:

```text
magic = "LLPV"
version = LLPVM bytecode version
root stream ids
record* tagged little-endian records
```

MLUI stack declarations appear as language/type/world/machine/phase records. MLUI-authored UI is represented as streams in `MluiAuth` or `MluiCompose` worlds.

Required runtime entry:

```c
mlui_status mlui_load_llpv_program(
    mlui_kernel *ui,
    const void *bytes,
    size_t len,
    mlui_node_ref *out_root);
```

Ownership:

```text
The caller owns bytecode bytes.
The runtime borrows by default.
Native stream handles are not Lua authoring proxies.
If the host wants copied ownership, it copies bytes before or through an explicit copy-load API.
```

### 10.2 MLUI fast-row program

The C in-memory profile:

```c
typedef struct mlui_program_header {
    uint32_t magic;
    uint32_t abi_version;
    uint32_t flags;
    uint8_t endian;        /* 1 little, 2 big */
    uint8_t pointer_size;  /* sizeof(void*) expected by this in-memory profile */
    uint8_t root_kind;
    uint8_t reserved0;
    uint32_t root_index;
} mlui_program_header;

typedef struct mlui_program {
    mlui_program_header header;

    const mlui_auth_node *auth_nodes;
    size_t auth_count;

    const mlui_compose_node *compose_nodes;
    size_t compose_count;

    const uint32_t *children;
    size_t child_count;

    const mlui_style_token *style_tokens;
    size_t style_token_count;

    const mlui_style_cond *style_conds;
    size_t style_cond_count;

    const mlui_style_atom *style_atoms;
    size_t style_atom_count;

    const mlui_track *tracks;
    size_t track_count;

    const mlui_paint_op *paint_ops;
    size_t paint_op_count;

    const mlui_paint_point *paint_points;
    size_t paint_point_count;

    const mlui_paint_vertex *paint_vertices;
    size_t paint_vertex_count;

    const uint32_t *paint_indices;
    size_t paint_index_count;

    uint64_t feature_flags;
} mlui_program;
```

Serialized file profile must replace pointers with little-endian offsets and byte lengths:

```text
mlui_image_header
section table: kind, offset, stride, count, byte_len
payload sections
```

No serialized profile may contain raw native pointers.

### 10.3 Validation order

`ui_validate_program` must check:

```text
1. null pointer checks
2. magic == MLUI for fast-row or LLPV for canonical image path
3. ABI version / LLPVM version
4. endian and pointer size match runtime profile for in-memory C rows
5. root kind and root index valid
6. section pointers/counts consistent
7. auth opcode kind in range
8. compose opcode kind in range
9. child ranges are in bounds
10. wrapper arity exactly one child
11. leaf arity zero children
12. token ranges in bounds
13. style track ranges in bounds
14. paint ranges in bounds
15. resource refs not invalid where required
16. duplicate nonzero ids fail
17. unsupported feature flags fail
```

Validation must not import or mutate kernel state, except for temporary scratch owned by validation.

### 10.4 Import rules

`ui_import` turns valid authored rows into imported node records:

```text
allocate/import UiNodeRecord entries
copy row facts required after call
build id -> node lookup for nonzero UiId
preserve child ranges or canonicalized child vectors
preserve wrappers and interaction nouns
return root UiNodeRef
```

The import phase must not lower directly to view ops.

---

## 11. Native stores and kernel product

### 11.1 UiKernel

`UiKernel` is the runtime owner of stores, the persistent model, configured services, and borrowed frame outputs.

```text
UiKernel
  allocator: UiAllocator
  config: UiConfig
  llpvm: LlVm or embedded LLPVM runtime handle
  node_store: UiNodeStore
  content_store: UiContentStore
  text_layout_store: UiTextLayoutStore
  paint_store: UiPaintStore
  image_store: UiImageStore
  font_store: UiFontStore
  value_store: UiValueStore
  theme_store: UiThemeStore
  scroll_store: UiScrollStore
  model: UiModel
  scene_buffer: UiSceneBuffer
  measure_buffer: UiMeasureBuffer
  solve_buffer: UiSolveBuffer
  view_buffer: UiViewBuffer
  report: UiReport
  event_buffer: UiEventBuffer
  epochs: UiEpochs
```

`UiKernel` owns materialization, not semantic cache policy. The phase cache lives in LLPVM runtime state and may hold handles to products whose lifetimes are governed by the kernel/profile.

### 11.2 Store products

```text
UiNodeStore
  slots: ptr(UiNodeSlot)
  len/cap/free_head/epoch
  id_index: implementation-owned map or sorted table

UiContentStore
  slots: ptr(UiContentSlot)
  byte_arena: ByteArena
  len/cap/free_head/epoch

UiTextLayoutStore
  slots: ptr(UiTextLayoutSlot)
  lines/runs/glyphs/clusters/carets buffers
  len/cap/free_head/epoch

UiPaintStore
  slots: ptr(UiPaintSlot)
  paint_ops/points/vertices/indices buffers
  len/cap/free_head/epoch

UiImageStore
  slots: ptr(UiImageSlot)
  len/cap/free_head/epoch

UiFontStore
  slots: ptr(UiFontSlot)
  len/cap/free_head/epoch

UiValueStore
  slots: ptr(UiValueSlot)
  len/cap/free_head/epoch

UiScrollStore
  rows: ptr(UiScrollState)
  len/cap/epoch
```

### 11.3 Resource lifecycle protocols

Retain/register returns owned obligations:

```text
ui_kernel_create      -> owned UiKernelRef
ui_content_retain     -> owned UiContentRef
ui_text_layout_retain -> owned UiTextLayoutRef
ui_paint_retain       -> owned UiPaintRef
ui_image_register     -> owned UiImageRef
ui_font_register      -> owned UiFontRef
ui_value_retain       -> owned UiValueRef
```

Publish transfers owned obligation into durable kernel-visible identity (the owned handle is consumed, returned non-owned on success):

```text
owned UiContentRef -> ui_content_publish -> UiContentRef (non-owned)
owned UiPaintRef   -> ui_paint_publish   -> UiPaintRef (non-owned)
owned UiValueRef   -> ui_value_publish   -> UiValueRef (non-owned)
```

Failure continuations (missing/stale) return the owned handle so the caller may retry or release.

Release/close consumes the owned handle or returns it on failure.

### 11.4 Dynamic store invalidation

Dynamic updates use resource stores instead of mutating authored structure when possible:

```text
slider value change          -> UiValueStore / paint-only epoch
meter/scope/canvas update    -> UiPaintStore / value epoch
caret/selection/composition  -> text edit/value epoch
layout-affecting text change -> UiContentStore content epoch + text layout epoch
```

Invalidation is expressed by the consumed domain world. Resource epochs,
viewport facts, input batches, and model revisions are values inside the world
that first needs them, so cache keys can be derived from one consumed product
instead of side metadata.

---

## 12. Moonlift declaration blueprint

The public Moonlift declaration surface lives in the canonical stack module. It contains products `T.*`, protocols `R.*`, ABI seals `F.*`, and the LLPVM machine definition. A separate `mlui_header.mlua` may exist only as a compatibility shim that imports the stack with `moon.require`.

### 12.1 Canonical module layout

```lua
local moon = require "moonlift"
local ll = require "llpvm"

local M = {
    T = {},
    R = {},
    F = {},
}

M.vm = ll.vm { ... }

local T = M.T
local R = M.R
local F = M.F

-- LLPVM languages, worlds, machines, phases
-- scalar aliases, structs, handles
-- region protocols
-- ABI function seals

return M
```

Implementation files import the stack directly:

```lua
local H = moon.require("mlui_stack")
local T = H.T
local R = H.R
local F = H.F
```

Compatibility-only imports may use:

```lua
local H = moon.require("mlui_header")
```

`mlui_header.mlua` must be a Moonlift-aware shim. It must not use plain Lua
`dofile`, because `mlui_stack.mlua` contains Moonlift declarations.

### 12.2 Required region declarations

Representative region signatures:

```moonlift
region ui_kernel_create(config: ptr(UiConfig);
    created(kernel: owned UiKernelRef)
  | oom(needed: index)) end

region ui_kernel_borrow(kernel: UiKernelRef;
    borrowed(ui: lease ptr(UiKernel))
  | missing(kernel: UiKernelRef)
  | stale(kernel: UiKernelRef)) end

region ui_kernel_init_ptr(config: ptr(UiConfig);
    created(ui: ptr(UiKernel))
  | bad_argument(code: i32)
  | oom(needed: index)) end

region ui_kernel_close(kernel: owned UiKernelRef;
    closed
  | busy(kernel: owned UiKernelRef)
  | missing(kernel: owned UiKernelRef)
  | stale(kernel: owned UiKernelRef)) end

region ui_validate(ui: ptr(UiKernel), readonly program: ptr(UiProgram);
    valid(root_kind: u8, root_index: u32)
  | invalid_header(code: i32)
  | invalid_section(section: u8)
  | invalid_opcode(at: index, kind: u16)
  | invalid_range(section: u8, first: u32, count: u32)
  | invalid_arity(at: index, expected: u32, got: u32)
  | duplicate_id(id: UiId)
  | missing_resource(section: u8, index_: u32)
  | unsupported_feature(flags: u64)
  | oom(needed: index)) end

region ui_import(ui: ptr(UiKernel), readonly program: ptr(UiProgram), root_kind: u8, root_index: u32;
    imported(root: UiNodeRef)
  | invalid_child(parent: UiId, child_index: u32)
  | duplicate_id(id: UiId)
  | missing_resource(section: u8, index_: u32)
  | unsupported_node(kind: u16)
  | oom(needed: index)) end

region ui_expand(ui: ptr(UiKernel), readonly compose: view(UiComposeNode);
    expanded(auth: UiAuthBuffer)
  | invalid_child(parent: UiId, child_index: u32)
  | unsupported_compose(kind: u16)
  | oom(needed: index)) end

region ui_style(ui: ptr(UiKernel), root: UiNodeRef, env: UiEnvClass;
    styled(styled_epoch: UiEpoch)
  | missing_node(id: UiId)
  | unsupported_node(kind: u16)
  | invalid_atom(kind: u16)
  | missing_theme(id: UiId)
  | missing_resource(section: u8, index_: u32)
  | oom(needed: index)) end

region ui_measure_node(ui: ptr(UiKernel), layout_index: u32, constraint: UiMeasureConstraint;
    measured(size: UiIntrinsicSize, text_layout: UiTextLayoutRef)
  | missing_text(content: UiContentRef)
  | text_backend_error(code: i32)
  | unsupported_layout(kind: u16)
  | oom(needed: index)) end

region ui_measure(ui: ptr(UiKernel), viewport: UiViewport;
    measured(measured_epoch: UiEpoch)
  | missing_scene
  | missing_text(content: UiContentRef)
  | text_backend_error(code: i32)
  | unsupported_layout(kind: u16)
  | oom(needed: index)) end

region ui_layout(ui: ptr(UiKernel), viewport: UiViewport;
    laid_out(layout_epoch: UiEpoch)
  | missing_scene
  | missing_text(content: UiContentRef)
  | text_backend_error(code: i32)
  | unsupported_layout(kind: u16)
  | oom(needed: index)) end

region ui_render(ui: ptr(UiKernel);
    rendered(view_epoch: UiEpoch)
  | missing_node(id: UiId)
  | missing_text(content: UiContentRef)
  | decor_mismatch(layout_index: u32, decor_index: u32)
  | malformed_op(at: index, kind: u16)
  | oom(needed: index)) end

region ui_report_frame(ui: ptr(UiKernel);
    reported(report_epoch: UiEpoch)
  | malformed_op(at: index, kind: u16)
  | stack_unbalanced(stack: u8)
  | oom(needed: index)) end

region ui_handle_input(ui: ptr(UiKernel), raw: readonly view(UiRawInput);
    handled(event_count: index, model_epoch: UiEpoch)
  | malformed_raw(at: index, kind: u16)
  | stale_focus(id: UiId)
  | stale_capture(id: UiId)
  | missing_scroll(id: UiId)
  | text_input_without_focus(at: index)
  | oom(needed: index)) end
```

Visitor regions:

```text
ui_visit_style_atom
ui_visit_compose_node
ui_visit_auth_node
ui_visit_layout_node
ui_visit_decor_node
ui_visit_solve_node
ui_visit_view_op
ui_visit_paint_program
ui_visit_raw_input
ui_visit_event
ui_visit_key
ui_visit_value
```

Borrow resolver regions:

```text
ui_borrow_node
ui_borrow_content
ui_borrow_text_layout
ui_borrow_paint
ui_borrow_image
ui_borrow_font
ui_borrow_value
```

Reset regions:

```text
ui_reset_auth
ui_reset_scene
ui_reset_solve
ui_reset_view
ui_reset_frame_events
```

### 12.3 Required ABI seals

```text
F.mlui_kernel_init
F.mlui_kernel_init_ex
F.mlui_kernel_close
F.mlui_kernel_reset_frame
F.mlui_import_buffer
F.mlui_load_program
F.mlui_load_llpv_program
F.mlui_validate_program
F.mlui_frame
F.mlui_style_measure_layout_render
F.mlui_report_frame
F.mlui_handle_input
F.mlui_view_ops
F.mlui_events
F.mlui_report_get
F.mlui_clear_events
F.mlui_content_retain_copy
F.mlui_content_release
F.mlui_paint_retain
F.mlui_paint_release
F.mlui_image_register
F.mlui_image_release
F.mlui_font_register
F.mlui_font_release
F.mlui_value_set
F.mlui_value_retain
F.mlui_value_release
```

ABI seals convert typed region exits to `mlui_status` exactly once and do not duplicate region logic.

---

## 13. Public C ABI

### 13.1 Opaque kernel and config

```c
typedef struct mlui_kernel mlui_kernel;

typedef void *(*mlui_alloc_fn)(void *user, size_t size, size_t align);
typedef void *(*mlui_realloc_fn)(void *user, void *ptr, size_t old_size, size_t new_size, size_t align);
typedef void (*mlui_free_fn)(void *user, void *ptr, size_t size, size_t align);

typedef struct mlui_allocator {
    void *user;
    mlui_alloc_fn alloc;
    mlui_realloc_fn realloc;
    mlui_free_fn free;
} mlui_allocator;

typedef struct mlui_text_measure_request {
    mlui_content_ref content_ref;
    mlui_font_ref font_ref;
    float width_constraint;
    uint32_t flags;
} mlui_text_measure_request;

typedef mlui_status (*mlui_text_measure_fn)(
    void *user,
    const mlui_text_measure_request *request,
    mlui_text_layout_ref *out_layout);

typedef struct mlui_backend_callbacks {
    void *user;
    mlui_text_measure_fn measure_text;
} mlui_backend_callbacks;

typedef struct mlui_config {
    uint32_t abi_version;
    uint32_t flags;
    size_t initial_node_cap;
    size_t initial_scene_cap;
    size_t initial_solve_cap;
    size_t initial_view_cap;
    size_t initial_event_cap;
    size_t llpvm_cache_bytes;
    mlui_allocator allocator;
    mlui_backend_callbacks backend;
} mlui_config;
```

### 13.2 Core functions

```c
uint32_t mlui_abi_version(void);

mlui_status mlui_kernel_init(mlui_kernel **out);
mlui_status mlui_kernel_init_ex(const mlui_config *config, mlui_kernel **out);
mlui_status mlui_kernel_close(mlui_kernel *ui);
mlui_status mlui_kernel_reset_frame(mlui_kernel *ui);

mlui_status mlui_validate_program(mlui_kernel *ui, const mlui_program *program);
mlui_status mlui_load_program(mlui_kernel *ui,
                              const mlui_program *program,
                              mlui_node_ref *out_root);

mlui_status mlui_load_llpv_program(mlui_kernel *ui,
                                   const void *bytes,
                                   size_t len,
                                   mlui_node_ref *out_root);

mlui_status mlui_import_buffer(mlui_kernel *ui,
                               const mlui_auth_node *nodes,
                               size_t node_count,
                               const uint32_t *children,
                               size_t child_count,
                               mlui_node_ref *out_root);

mlui_status mlui_style_measure_layout_render(mlui_kernel *ui,
                                             mlui_node_ref root,
                                             float width,
                                             float height);

mlui_status mlui_frame(mlui_kernel *ui,
                       mlui_node_ref root,
                       float width,
                       float height,
                       const mlui_raw_input_buffer *raw);

mlui_status mlui_report_frame(mlui_kernel *ui);
mlui_status mlui_handle_input(mlui_kernel *ui,
                              const mlui_raw_input_buffer *raw);

mlui_status mlui_view_ops(mlui_kernel *ui,
                          const mlui_view_op **ops,
                          size_t *n_ops);

mlui_status mlui_events(mlui_kernel *ui,
                        const mlui_event **events,
                        size_t *n_events);

mlui_status mlui_report_get(mlui_kernel *ui,
                            const mlui_report **report);

mlui_status mlui_clear_events(mlui_kernel *ui);
```

### 13.3 Resource functions

These functions are optional for pure `UiProgram` callers but required for dynamic/native hosts.

```c
mlui_status mlui_content_retain_copy(mlui_kernel *ui,
                                     const void *bytes,
                                     size_t len,
                                     uint32_t encoding,
                                     uint32_t flags,
                                     mlui_content_ref *out);

mlui_status mlui_content_release(mlui_kernel *ui, mlui_content_ref ref);

mlui_status mlui_paint_retain(mlui_kernel *ui,
                              const mlui_paint_op *ops,
                              size_t op_count,
                              const mlui_paint_point *points,
                              size_t point_count,
                              mlui_paint_ref *out);

mlui_status mlui_paint_release(mlui_kernel *ui, mlui_paint_ref ref);

mlui_status mlui_image_register(mlui_kernel *ui,
                                uint64_t host_key,
                                float width,
                                float height,
                                uint32_t format,
                                mlui_image_ref *out);

mlui_status mlui_image_release(mlui_kernel *ui, mlui_image_ref ref);

mlui_status mlui_font_register(mlui_kernel *ui,
                               uint64_t host_key,
                               mlui_content_ref family,
                               float size,
                               uint32_t weight,
                               uint32_t flags,
                               mlui_font_ref *out);

mlui_status mlui_font_release(mlui_kernel *ui, mlui_font_ref ref);

mlui_status mlui_value_set(mlui_kernel *ui,
                           mlui_value_ref ref,
                           const mlui_value_record *value);

mlui_status mlui_value_retain(mlui_kernel *ui,
                              const mlui_value_record *value,
                              mlui_value_ref *out);

mlui_status mlui_value_release(mlui_kernel *ui, mlui_value_ref ref);
```

### 13.4 C boundary ownership

```text
mlui_kernel*                  owned by MLUI until mlui_kernel_close
returned view/event pointers   borrowed until next frame/reset/clear/close
returned report pointer        borrowed until next frame/reset/close
UiProgram pointer sections     borrowed for call unless loaded through explicit copy API
LLPV bytecode bytes            borrowed while native streams derived from them live, unless copy-load profile is used
raw input text                 borrowed for mlui_frame/mlui_handle_input only
image/font host resources      host-owned opaque keys stored in MLUI records
```

### 13.5 Canonical C usage

```c
#define MLUI_IMPLEMENTATION
#include "mlui_amalgam.c"

mlui_kernel *ui = 0;
mlui_status st = mlui_kernel_init_ex(&config, &ui);
if (st.code != MLUI_OK) { /* handle */ }

mlui_node_ref root = 0;
st = mlui_load_program(ui, &program, &root);
if (st.code != MLUI_OK) { /* handle */ }

st = mlui_frame(ui, root, width, height, &raw);
if (st.code != MLUI_OK) { /* handle */ }

const mlui_view_op *ops = 0;
size_t n_ops = 0;
mlui_view_ops(ui, &ops, &n_ops);

/* backend draws ops */

const mlui_event *events = 0;
size_t n_events = 0;
mlui_events(ui, &events, &n_events);

/* app consumes events and updates app state */

mlui_kernel_close(ui);
```

---

## 14. C To WebAssembly

MLUI does not define a separate WASM ABI. The generated artifact is ordinary C.
If a user wants WebAssembly, they compile the emitted C with `emcc` or another
C-to-WASM toolchain and design their own JavaScript binding layer around the C
ABI. MLUI should not declare `mlui_wasm_*` functions, linear-memory offset
protocols, or typed-array layouts as part of its own contract.

---

## 15. Lua authoring contract

Lua authoring keeps the no-parentheses taste:

```lua
local ui = require "mlui"
local b = ui.build
local tw = ui.tw
local W = ui.widgets

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

Dynamic values are passed through table calls because non-string facts should remain named and product-shaped.

Lua builders must output LLPVM values/streams or MLUI fast-row buffers; they must not require the native runtime to understand Lua tables.

Widget factories must declare invalidation class:

```text
structure-affecting
layout-affecting
text-layout-affecting
paint-only
interaction-only
```

That declaration determines which next domain world changes. A paint-only
widget update should change the renderable/reported path without invalidating
authored structure; a layout-affecting update must produce a new measured or
laid-out world.

---

## 16. Frame algorithm

`mlui_frame` composes the sealed runtime pipeline as a domain-world transform:

```text
1. validate root ref
2. reset frame events
3. style imported UI through LLPVM phase cache
4. measure styled UI through LLPVM phase cache
5. layout measured UI through LLPVM phase cache
6. render laid-out UI into renderable UI through LLPVM phase cache / recording
7. report the renderable frame from the same view op stream
8. if raw input exists, handle input by transforming reported frame into handled frame
9. return mlui_status
```

Pseudo-control:

```moonlift
func mlui_frame(ui: ptr(UiKernel), root: UiNodeRef, width: f32, height: f32, raw: ptr(UiRawInputBuffer)): UiStatus
    return region: UiStatus
    entry start()
        emit ui_reset_frame_events(ui; reset = style, oom = oom_exit)
    end
    block style()
        emit ui_style(ui, root, env; styled = measure, missing_node = missing_node, unsupported_node = unsupported_node, oom = oom_exit)
    end
    block measure(styled_epoch: UiEpoch)
        emit ui_measure(ui, viewport; measured = layout, missing_text = missing_text, text_backend_error = text_error, oom = oom_exit)
    end
    block layout(measured_epoch: UiEpoch)
        emit ui_layout(ui, viewport; laid_out = render, missing_text = missing_text, text_backend_error = text_error, oom = oom_exit)
    end
    block render(layout_epoch: UiEpoch)
        emit ui_render(ui; rendered = report, decor_mismatch = decor_mismatch, malformed_op = malformed_op, oom = oom_exit)
    end
    block report(view_epoch: UiEpoch)
        emit ui_report_frame(ui; reported = handle_or_done, malformed_op = malformed_op, stack_unbalanced = stack_bad, oom = oom_exit)
    end
    block handle_or_done(report_epoch: UiEpoch)
        if raw == as(ptr(UiRawInputBuffer), 0) then jump ok() end
        emit ui_handle_input(ui, raw.view; handled = ok, stale_focus = stale_focus, stale_capture = stale_capture, missing_scroll = missing_scroll, oom = oom_exit)
    end
    block ok()
        yield UiStatus(MLUI_OK, 0, 0, 0)
    end
    -- failure blocks map typed exits to UiStatus exactly once
    end
end
```

---

## 17. Interaction reducer spec

`ui_handle_input` transforms a reported frame into a handled frame. Its consumed
world contains the raw input batch, hit report, scroll/focus/capture model, and
application-facing model revision required for the step.

Rules:

```text
PointerMoved
  update pointer coordinates
  recompute hover from report
  emit HoverChanged when changed
  if dragging, emit DragMoved

PointerPressed
  choose top hit target under modal/layer/focus rules
  set pressed/capture as policy allows
  maybe enter drag-pending
  emit Pressed/CaptureChanged as applicable

PointerReleased
  if capture/press rules match, emit Activated
  if dragging, resolve drop or cancel drag
  release capture and pressed state

PointerCancelled / FocusLost
  clear pressed/capture/drag
  emit Cancelled / DragCancelled / CaptureChanged / FocusChanged as needed

WheelMoved
  route to hovered/current scroll target from report/model
  clamp scroll through UiScrollBox extents
  update scroll store/model epoch
  emit ScrollChanged

KeyPressed
  focus traversal
  activation
  cancel
  text navigation hooks
  emit only semantic changes

KeyReleased
  emit only state changes demanded by ASDL

TextInput / TextEditing
  route to focused edit target
  if no focus target, emit TextInputWithoutFocus or typed continuation
  borrowed text is valid only for this dispatch unless copied

FocusMove / ActivateFocused / CancelInteraction
  map to same semantic paths as keys
```

The reducer never calls app callbacks.

---

## 18. Backend contract

Backend responsibilities:

```text
create window/frame lifecycle
translate platform events into UiRawInput rows
provide text measurement/layout service
apply UiViewOp stream to renderer
manage platform resources for image/font/texture handles
copy app-retained text when needed
```

Backend forbidden responsibilities:

```text
focus ownership
activation semantics
pointer capture semantics
drag/drop semantics
widget semantics
application state
layout policy
interpreting Auth/Layout/Decor/Solve directly
```

View op application:

```text
for op in UiViewBuffer:
  ui_visit_view_op or generated exact table
  maintain backend draw transform/clip stack consistently with report builder
  draw Box/Text/Paint/Image ops
  ignore/report-only ops as appropriate, but preserve stack effects
```

---

## 19. File layout

Flat folder, semantic machine names:

```text
experiments/mlui-llpvm/
  mlui_stack.mlua              -- canonical LLPVM stack + Moonlift declarations
  mlui_header.mlua             -- compatibility shim over mlui_stack.mlua
  mlui_types.mlua              -- removed or compatibility alias only if needed
  mlui_memory.mlua             -- allocator, buffer growth, byte copy, resets
  mlui_kernel_store.mlua       -- kernel create/borrow/close
  mlui_resource_store.mlua     -- content/text/paint/image/font/value lifecycles
  mlui_program_validate.mlua   -- fast-row + LLPV validation adapters
  mlui_program_import.mlua     -- valid UI -> imported UI
  mlui_expand.mlua             -- authored UI -> expanded UI
  mlui_style.mlua              -- imported UI -> styled UI
  mlui_measure.mlua            -- intrinsic measurement + text layout selection
  mlui_layout.mlua             -- measured UI -> laid-out UI
  mlui_render.mlua             -- laid-out UI -> renderable UI
  mlui_report_frame.mlua       -- renderable UI -> reported frame
  mlui_handle_input.mlua       -- reported frame -> handled frame
  mlui_abi.mlua                -- public F.* seals only
  mlui_build_c.lua             -- emits generated C blob/header
  mlui_bytecode.md             -- generated documentation
```

No `utils.mlua`, `helpers.mlua`, `impl.mlua`, or fake deep folders.

---

## 20. Required implementation order

```text
1. mlui_stack.mlua declaration and generated projection checking
2. memory primitives and buffer growth
3. kernel store and reset protocols
4. handle store resolvers
5. resource lifecycles
6. bytecode validation
7. program import
8. compose expansion
9. style resolution
10. scene lowering
11. measurement
12. solve
13. render ops
14. runtime report
15. raw input and interaction
16. ABI seals
17. C header and amalgamation
18. tests and golden equivalence
```

Every `R.*` region and every `F.*` function must have a body. Declaration-only is not completion.

---

## 21. Test and verification plan

Required tests:

```text
test_mlui_stack_generates_header.lua
test_mlui_types.lua
test_mlui_c_api_header.lua
test_mlui_opcode_constants_match_stack.lua
test_mlui_bytecode_bad_header.lua
test_mlui_bytecode_bad_opcode.lua
test_mlui_bytecode_bad_range.lua
test_mlui_duplicate_id_validation.lua
test_mlui_c_built_box_text_program_import.lua
test_mlui_lua_no_parens_to_uiprogram_equivalence.lua
test_mlui_llpv_and_fastrow_equivalence.lua
test_mlui_compose_expansion_golden.lua
test_mlui_style_resolution_golden.lua
test_mlui_measure_text_boundary.lua
test_mlui_solve_scroll_text_golden.lua
test_mlui_render_op_golden_box_text_scroll_input_focus_layer_modal.lua
test_mlui_runtime_report_golden_hit_focus_scroll_overlay_modal.lua
test_mlui_interaction_pointer.lua
test_mlui_interaction_key_focus.lua
test_mlui_interaction_text_input.lua
test_mlui_interaction_drag_drop.lua
test_mlui_resource_ownership_failures.lua
test_mlui_generated_c_blob_gcc_o3.lua
```

Build checks:

```sh
make
cargo build --release
make libtcc
luajit tests/experiments/test_mlui_types.lua
luajit tests/experiments/test_mlui_c_api_header.lua
luajit tests/run.lua experiments
luajit tests/run.lua c_backend
gcc -O3 -std=c99 -fPIC -shared -I. -o /tmp/mlui.so mlui_amalgam.c
```

Tests must assert behavior, not merely symbol existence.

---

## 22. Non-negotiable rules

```text
The current lua/ui richness is the source material; the phase shape is the
semantic domain-world pipeline.
MLUI is an LLPVM VM stack, not a widget callback framework.
The native kernel is product/protocol typed, not callback typed.
Auth/Layout/Decor/Solve/View/Report/Event are distinct products.
UiProgramOp / UiAuthNode is authored semantic opcode, not draw command.
UiViewOp is render/report output opcode, not authored input.
Render consumes Solve and never recomputes layout.
Text layout is explicit and retained/materialized.
Borrowed text never becomes durable without copying.
Dynamic paint/value data must not masquerade as structure.
Backends consume ops and produce raw input; they do not own UI semantics.
Public ABI status codes exist only at sealed C boundaries.
LLPVM phases own semantic retention; no hidden Lua side tables.
UiKernel owns stores/resources/model/materialized buffers; not a parallel cache universe.
All kind decoding has one owning visitor/consumer region.
The single-file C artifact exposes stable row buffers and opaque kernel handles.
No C API depends on LuaJIT, FFI, Moonlift host objects, or Lua authoring tables.
Lua no-parens authoring and C/LLPV bytecode authoring must produce equivalent VM input.
Generated numeric constants must match `mlui_stack.mlua`.
```

Forbidden shortcuts:

```text
Lua-only runtime path
success-returning stubs
empty buffers as fake implementation
internal i32 status propagation
raw pointer refs
hidden global caches
scattered raw kind switches
backend text remeasurement during render
second hidden hit-test tree
manual divergent opcode constants
C ABI exposure of internal store layout
```

---

## 23. Completion definition

MLUI is complete when:

```text
1. `mlui_stack.mlua` is the source of truth for languages/worlds/machines/phases and public `T/R/F` declarations.
2. Every generated C/bytecode projection is generated from or checked against the stack.
3. Every `R.*` region has a real Moonlift body.
4. Every `F.*` ABI function has a real Moonlift body.
5. C header and Moonlift ABI declarations agree.
6. A C frontend can construct a UiProgram without Lua.
7. A Lua no-parens frontend and C/fast-row frontend produce equivalent VM input.
8. LLPV canonical bytecode and MLUI fast-row projection validate/import through the same semantics.
9. The VM validates, imports, frames, emits view ops, builds reports, and emits events.
10. Text measurement/layout obeys the text boundary.
11. Render/report stack discipline is tested.
12. Interaction reducer behavior is tested for pointer/key/text/drag/scroll/focus.
13. Resource ownership failures are tested.
14. Generated single-file C artifact compiles with `gcc -O3`.
```

---

## 24. Summary architecture card

```text
MLUI = LLPVM UI compiler stack

Authoring:
  Lua no-parens DSL, C builder, serialized tools

Canonical representation:
  typed LLPVM languages/worlds/streams/phases in mlui_stack.mlua

Projection:
  MLUI fast-row ABI for C/embedded hosts

Retention:
  LLPVM phase cache over semantic domain worlds

Runtime ownership:
  UiKernel stores resources, interaction model, and borrowed output buffers

Pipeline:
  authored_ui -> expanded_ui -> valid_ui -> imported_ui -> styled_ui
      -> measured_ui -> laid_out_ui -> renderable_ui -> reported_frame
      -> handled_frame

Backends:
  draw View ops, measure text, register resources, produce RawInput

Apps:
  consume UiEvent, update app state, author next frame
```
