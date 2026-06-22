# MLUI Bytecode

Status: superseded by
[`experiments/mlui-llpvm/mlui_llpvm_stack_blueprint.md`](../mlui-llpvm/mlui_llpvm_stack_blueprint.md).
This file is retained only as historical bytecode input from the pre-LLPVM
iteration.

Historical scope: design specification for the portable MLUI VM program format.

MLUI bytecode is the frontend contract for Lua, C, generated tools, serialized
assets, and browser builders. It is not a render stream and not a DOM. It is a
compact authored semantic program consumed by the MLUI kernel.

## Machine Model

```text
program bytecode = UiProgram
input bytecode   = UiRawInput
output bytecode  = UiViewOp + UiEvent
heap             = UiKernel stores, caches, epochs, model, frame buffers
execution        = load -> lower -> measure -> solve -> render -> report -> interact
```

The frontend writes `UiProgram`. The VM produces `UiViewOp[]` for backend
drawing/report construction and `UiEvent[]` for app/widget semantic updates.

## Format Level

This document specified the **row ABI**: the in-memory C contract used by
frontends and by generated C. A serialized file format may wrap the same rows
later, but must still decode to this shape before `mlui_load_program`.

All rows use fixed-width fields from `mlui_types.mlua`:

```text
u8/u16/u32/u64/i32/i64/f64/index/handle/view
```

The public C header must define these with exact sizes and ABI version checks.
The current draft header is [`mlui_c_api.h`](mlui_c_api.h); C frontends should
use its constants instead of hand-typing opcode numbers.

## Program Container

```text
UiProgramHeader
UiProgramOp[]          authored semantic op rows
children[]             child op indices
UiStyleToken[]         authored style token rows
UiStyleTrack[]         grid/minmax track payload rows
UiComposeNode[]        optional compose opcode rows
compose_children[]     child indices for compose rows
UiPaintProgram[]       paint command rows
paint_points[]         f64 point lanes
UiPaintVertex[]        mesh vertices
resource ref tables    content/image/font/value refs registered with UiKernel
```

`UiProgramHeader.root_index` selects the root `UiProgramOp` unless
`root_kind == compose`, in which case it selects a root `UiComposeNode`.

## Header

```text
magic        must be MLUI
abi_version  row ABI version
flags        validation/runtime feature bits
root_index   root op index
root_kind    0 auth, 1 compose
endian       1 little, 2 big
pointer_size host pointer size for native row ABI
epoch        frontend-authored program epoch
```

The VM rejects unknown ABI versions, invalid endian/pointer-size profiles, and
roots outside their section.

## Authored Opcode Rows

`UiProgramOp` is an alias of `UiAuthNode`. Its `kind` selects the opcode. The
consumer region is `ui_visit_auth_node`; no other phase owns opcode decoding.

Canonical opcode numbers:

| Code | Name | Payload |
| --- | --- | --- |
| 0 | `Invalid` | rejected |
| 1 | `Empty` | no payload |
| 2 | `Fragment` | `first_child`, `n_child` |
| 3 | `Box` | child range + style token range + optional state |
| 4 | `Text` | `content` + style token range |
| 5 | `TextRef` | `content` + style token range |
| 6 | `Paint` | `paint_first`, `paint_count` + style token range |
| 7 | `Scroll` | `scroll_axis` + one child + style token range |
| 8 | `WithInput` | `id`, `role`, one child |
| 9 | `WithDragSource` | `id`, one child |
| 10 | `WithDropTarget` | `id`, one child |
| 11 | `WithDropSlot` | `id`, one child |
| 12 | `WithState` | `state`, one child |
| 13 | `FocusScope` | `id`, `focus_policy`, one child |
| 14 | `Layer` | `id`, `layer_kind`, `order`, one child |
| 15 | `Overlay` | `id`, `anchor_id`, `overlay_placement`, `modal`, one child |
| 16 | `Modal` | `id`, one child |

Common payload law:

```text
id                  semantic id; invalid when intentionally anonymous
kind                opcode number
role                input role for WithInput
scroll_axis         Scroll axis
focus_policy        FocusScope policy
layer_kind          Layer kind
overlay_placement   Overlay placement
anchor_id           Overlay anchor id
order               Layer order
modal               Overlay modal flag
first_child/n_child index range into program.children
token_first/count   range into program.auth.styles.tokens
content             UiContentRef registered with UiKernel
paint_first/count   range into program.paint.programs
state               explicit style state facts
```

Child entries are indices into `UiProgramOp[]`. Children are ordered. `n_child`
must match the opcode rule: wrappers require exactly one child; `Empty`, `Text`,
`TextRef`, and `Paint` require zero children; `Box`/`Fragment` allow any count.

## Compose Opcode Rows

`UiComposeNode` remains a separate section because compose nouns are semantic
authoring nodes, not layout nodes.

Canonical compose opcode numbers:

| Code | Name | Payload |
| --- | --- | --- |
| 0 | `Invalid` | rejected |
| 1 | `Panel` | `id`, child ranges, panel style ranges |
| 2 | `ScrollPanel` | `id`, `scroll_id`, `scroll_axis`, child/style ranges |
| 3 | `HSplit` | `id`, child ranges |
| 4 | `VSplit` | `id`, child ranges |
| 5 | `Workbench` | `id`, child ranges |
| 6 | `RawAuth` | `raw_auth` handle/reference |

`ui_expand_compose` owns compose opcode decoding and emits an auth program
projection. Compose may be absent; pure C frontends can emit auth ops directly.

## Style Bytecode

Style rows are authored semantic tokens:

```text
UiStyleToken = UiStyleCond + UiStyleAtom
```

`UiStyleAtom.kind` mirrors the `lua/ui` `Style.Atom`/declaration vocabulary.
The bytecode does not interpret it directly. `ui_visit_style_atom` and
`ui_resolve_style` own interpretation.

Token ranges are local to the op that names them. Conditions gate the atom by
environment and interaction/app state:

```text
breakpoint, scheme, motion, hovered, focused, active, selected, disabled
```

Grid/minmax track payloads live in `UiStyleTokenBuffer.tracks`, referenced by
`track_first`/`track_count`.

## Paint Bytecode

Paint rows preserve authored paint semantics:

| Code | Name |
| --- | --- |
| 0 | invalid |
| 1 | line |
| 2 | polyline |
| 3 | polygon |
| 4 | circle |
| 5 | arc |
| 6 | bezier |
| 7 | mesh |
| 8 | image |

`UiPaintProgram` references point lanes, mesh vertices, image refs, stroke/fill,
opacity, tint, mode, and segment counts. `ui_visit_paint_program` owns decoding.

## Resource Binding

Program rows may reference kernel resources:

```text
UiContentRef
UiPaintRef or paint program ranges
UiImageRef
UiFontRef
UiValueRef
```

For C frontends, these refs come from registration/retain APIs before
`mlui_load_program`, or from resource tables carried by `UiProgram`. Serialized
formats should store stable external resource keys and bind them to refs before
loading the program.

No raw host pointer is a bytecode identity.

## Validation

`mlui_load_program` must validate before import:

```text
header magic/version/endian/pointer profile
root index and root kind
opcode kind ranges
child ranges and wrapper arity
style token ranges
track ranges
paint ranges
resource refs
duplicate ids
cycles if non-tree child references are ever allowed
unsupported opcode/profile flags
```

Failures become `UiStatus` values at the C seal and typed exits inside Moonlift.
Backends must never see malformed op rows.

## Frontend Rules

```text
Lua frontend        no-parens DSL -> recursive ASDL -> canonical UiProgram rows
C frontend          builder append calls or direct row filling -> UiProgram
generated frontend  asset decode + resource binding -> UiProgram
```

All frontends must produce the same semantics for the same row program.

## Non-Negotiables

```text
UiProgram is semantic authored bytecode, not drawing bytecode.
Opcode decoding is owned by visitor/consumer regions.
Rows are stable ABI products; UiKernel internals are opaque.
Handles are durable identities, not raw pointers.
Text views in input are borrowed; durable text is content storage.
Validation happens before lowering/solve/render.
View ops and events are VM outputs, not frontend inputs.
```
