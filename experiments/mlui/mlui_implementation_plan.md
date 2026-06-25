# MLUI Implementation Plan

Status: superseded by
[`experiments/mlui-llpvm/mlui_llpvm_stack_blueprint.md`](../mlui-llpvm/mlui_llpvm_stack_blueprint.md).
This plan is retained only as historical implementation input. Do not execute
its old `lower_scene` / `solve_scene` / `interact_step` checklist as the current
architecture. Current MLUI implementation planning must follow the semantic
domain-world pipeline:
`authored_ui -> expanded_ui -> valid_ui -> imported_ui -> styled_ui ->
measured_ui -> laid_out_ui -> renderable_ui -> reported_frame ->
handled_frame`.

Audience: a code agent that may be tempted to stop at declarations, mocks,
test-only paths, or Lua-side substitutes.  Do not do that.

Historical goal: implement the MLUI VM as a real Lalin kernel with a portable
`UiProgram` bytecode frontend, explicit stores, region bodies, C ABI seals, and
no hidden Lua-only runtime path.

This plan is mechanical on purpose.  Implement every region and ABI seal in the
order below.  Do not claim completion because a declaration test passes.

## Required Reading

Read these files before editing:

```text
CONVENTIONS.md
LANGUAGE_REFERENCE.md
PROTOCOL_SYNTAX.md
OWNED_CFG_DESIGN.md
experiments/mlui/mlui_design.md
experiments/mlui/mlui_lua_api.md
experiments/mlui/mlui_bytecode.md
experiments/mlui/mlui_c_api.h
experiments/mlui/mlui_types.mlua
lua/ui/asdl.lua
lua/ui/render.lua
lua/ui/interact.lua
lua/ui/measure.lua
lua/ui/solve.lua
lua/ui/resolve.lua
lua/ui/lower.lua
```

Respect `CONVENTIONS.md`:

- flat `experiments/mlui/` folder;
- lowercase file names with semantic machine names;
- no `utils.mlua`, `helpers.mlua`, `impl.mlua`, or `runtime.mlua`;
- products are nouns;
- regions are verbs or `verb_noun`;
- `Ref` handles resolve through stores;
- resolver regions grant leases;
- invalidating regions use `invalidate`;
- ABI functions are the only status-code boundary.

## Current Header Name

`experiments/mlui/mlui_types.mlua` is header-shaped but not convention-named.
Before broad implementation, either:

1. rename it to `mlui_header.mlua` and update all docs/tests/imports; or
2. keep `mlui_types.mlua` only as a temporary compatibility header and document
   the exception at the top.

Do not scatter public declarations across implementation files.  Header first,
then bodies.

## Implementation Files

Use one flat folder:

```text
experiments/mlui/
  mlui_header.mlua              -- or current mlui_types.mlua until renamed
  mlui_memory.mlua              -- allocator, buffer growth, byte copy, resets
  mlui_kernel_store.mlua        -- kernel create/borrow/close
  mlui_resource_store.mlua      -- content/text/paint/image/font/value lifecycles
  mlui_program_validate.mlua    -- UiProgram bytecode validation
  mlui_program_import.mlua      -- UiProgram/AuthBuffer -> node store
  mlui_compose_expand.mlua      -- Compose opcodes -> Auth program projection
  mlui_style_resolve.mlua       -- style tokens -> layout/decor facts
  mlui_scene_lower.mlua         -- imported auth -> scene buffers
  mlui_measure.mlua             -- intrinsic measurement
  mlui_solve.mlua               -- layout placement
  mlui_render_ops.mlua          -- solve/decor -> UiViewOp stream
  mlui_runtime_report.mlua      -- UiViewOp stream -> UiReport
  mlui_interact.mlua            -- UiRawInput + report + model -> events
  mlui_abi.mlua                 -- public F.* seals only
  mlui_build_c.lua              -- emits generated C blob/header later
```

Each file must return the implemented fragments:

```lua
return {
    ui_validate_program = ui_validate_program,
    mlui_validate_program = mlui_validate_program,
}
```

## Lalin Syntax Hints

Implementation files import the header:

```lua
local H = lalin.require("mlui_types") -- or "mlui_header" after rename
local T = H.T
local R = H.R
local F = H.F
```

Implement a declared region:

```lua
local ui_validate_program = region @{R.ui_validate_program}
entry start()
    if program == as(ptr(T.UiProgram), 0) then
        jump invalid_header(code = 1)
    end
    jump valid(root_kind = program.header.root_kind, root_index = program.header.root_index)
end
end
```

Implement a declared function:

```lua
local mlui_validate_program = func @{F.mlui_validate_program}
    return region: T.UiStatus
    entry start()
        emit ui_validate_program(kernel, program;
            valid = ok,
            invalid_header = bad_header,
            invalid_section = bad_section,
            invalid_opcode = bad_opcode,
            invalid_range = bad_range,
            invalid_arity = bad_arity,
            duplicate_id = dup_id,
            missing_resource = missing_res,
            unsupported_feature = unsupported,
            oom = oom_exit)
    end
    block ok(root_kind: u8, root_index: u32)
        yield T.UiStatus(0, as(i32, root_kind), as(index, root_index), 0)
    end
    block bad_header(code: i32)
        yield T.UiStatus(15, code, 0, 0)
    end
    block bad_section(section: u8)
        yield T.UiStatus(16, as(i32, section), 0, 0)
    end
    block bad_opcode(at: index, kind: u8)
        yield T.UiStatus(17, as(i32, kind), at, 0)
    end
    block bad_range(section: u8, first: u32, count: u32)
        yield T.UiStatus(18, as(i32, section), as(index, first), as(index, count))
    end
    block bad_arity(at: index, expected: u32, got: u32)
        yield T.UiStatus(19, as(i32, expected), at, as(index, got))
    end
    block dup_id(id: T.UiId)
        yield T.UiStatus(2, as(i32, id), 0, 0)
    end
    block missing_res(section: u8, index_: u32)
        yield T.UiStatus(20, as(i32, section), as(index, index_), 0)
    end
    block unsupported(flags: u32)
        yield T.UiStatus(21, as(i32, flags), 0, 0)
    end
    block oom_exit(needed: index)
        yield T.UiStatus(1, 0, 0, needed)
    end
    end
end
```

Rules that prevent common lazy-agent mistakes:

- No `while`, `for`, `break`, or `continue`; use `block` and `jump`.
- Every `emit` names every continuation.
- Do not call regions as ordinary functions when continuation payloads matter.
- Do not use `error()` for protocol outcomes.
- Do not return integer status internally; use continuations internally and
  convert to `UiStatus` only in `F.*` ABI seals.
- Do not pass `owned T` as plain `T`.
- If a failed continuation preserves ownership, return the `owned` handle in
  the payload exactly as declared.
- No hidden global caches; caches are products in `UiKernel` or named stores.
- Top-level `.mlua` is Lua. Write `local MASK = 0x00FFFFFF`, not
  `local MASK: u32 = ...`. Type annotations belong inside Lalin islands.
- Lalin inequality is `~=`, not `!=`.
- View construction is `view(ptr, len)` or `view(ptr, len, stride)`. Do not
  write `view(u8, ptr, len, stride)`.
- Nested places are legal and should be used directly:
  `slot_ptr[0].content.bytes = bytes_view`,
  `(*slot_ptr).content.layout_affecting = false`, and
  `&(kernel.content.slots)` are valid place/address forms.
- `ptr[index].field` is an addressable place. If a nested write ever becomes
  hard to read, take a named subpointer with `let content: ptr(T.UiContent) =
  &((*slot_ptr).content)` and then write `content.bytes = ...`; this is a
  clarity choice, not a parser workaround.
- Statement-position expressions may continue across newlines for infix
  operators and assignment `=`, but may not introduce postfix call/index/dot
  continuation across a statement newline. If a parser diagnostic seems to join
  two statements, run `luajit tests/frontend/test_parse_stmt_newline_boundaries.lua`
  before changing MLUI code.

## Build And Verification Commands

Build compiler/runtime:

```sh
make
cargo build --release
make libtcc
```

Run focused MLUI checks:

```sh
luajit tests/experiments/test_mlui_types.lua
luajit tests/experiments/test_mlui_c_api_header.lua
```

Run the optional experiment suite:

```sh
luajit tests/run.lua experiments
```

Run C backend syntax/emission checks:

```sh
luajit tests/run.lua c_backend
```

C backend usage patterns:

```lua
local lalin = require("lalin")
local c_src = lalin.emit_c_file("experiments/mlui/mlui_abi.mlua", "out.c", "mlui")
local compiled = lalin.compile_c_file("experiments/mlui/mlui_abi.mlua", {
    name = "mlui",
    runner = "shared",
    cc = "gcc",
    cflags = "-O3 -fPIC -shared",
})
```

Do not use passing tests as a substitute for region bodies.  Tests are a smoke
signal.  Completion means every declared `R.*` and `F.*` in the header has a
real body wired into an emitted artifact.

## Implementation Order

Follow this order.  Do not jump to rendering before stores and validation exist.

## Dumb Progress Checklist

Use this section as the mechanical tracker.  Check a box only when the file
exists, the relevant region/function bodies are implemented, and the work is
wired into the emitted MLUI artifact.  Do not check boxes for declarations alone.

### Setup And Header

- [x] Read `CONVENTIONS.md`.
- [x] Read `LANGUAGE_REFERENCE.md`.
- [x] Read `PROTOCOL_SYNTAX.md`.
- [x] Read `OWNED_CFG_DESIGN.md`.
- [x] Read `experiments/mlui/mlui_design.md`.
- [x] Read `experiments/mlui/mlui_lua_api.md`.
- [x] Read `experiments/mlui/mlui_bytecode.md`.
- [x] Read `experiments/mlui/mlui_c_api.h`.
- [x] Read `lua/ui/asdl.lua`.
- [x] Decide whether to rename `mlui_types.mlua` to `mlui_header.mlua`. (Keep `mlui_types.mlua`, document exception at top)
- [x] Update all imports/tests/docs if the header is renamed. (No rename needed)
- [x] Confirm no public declarations were added outside the header.
- [x] Confirm `rg '^R\.' experiments/mlui/mlui_types.mlua` lists every protocol. (53 regions)
- [x] Confirm `rg '^F\.' experiments/mlui/mlui_types.mlua` lists every ABI seal. (15 functions)

### Memory And Kernel Store

- [x] Create `experiments/mlui/mlui_memory.mlua`.
- [x] Implement `mlui_alloc_bytes`.
- [x] Implement `mlui_realloc_bytes`.
- [x] Implement `mlui_free_bytes`.
- [x] Implement `mlui_zero_bytes`.
- [x] Implement `mlui_copy_bytes`.
- [x] Implement grow helper for `UiAuthBuffer`. (mlui_grow_auth_nodes)
- [x] Implement grow helper for `UiSceneBuffer`. (mlui_grow_scene_layout_nodes, decor_nodes, children, tracks)
- [x] Implement grow helper for `UiSolveBuffer`. (mlui_grow_solve_nodes, children)
- [x] Implement grow helper for `UiViewBuffer`. (mlui_grow_view_ops)
- [x] Implement grow helper for `UiEventBuffer`. (mlui_grow_events)
- [x] Create `experiments/mlui/mlui_kernel_store.mlua`.
- [x] Implement `ui_kernel_create`.
- [x] Implement `ui_kernel_borrow`.
- [x] Implement `ui_kernel_close`.
- [x] Implement `ui_reset_auth`.
- [x] Implement `ui_reset_scene`.
- [x] Implement `ui_reset_solve`.
- [x] Implement `ui_reset_view`.
- [x] Implement `ui_reset_frame_events`.
- [x] Implement `mlui_kernel_init`.
- [x] Implement `mlui_kernel_init_ex`.
- [x] Implement `mlui_kernel_close`.
- [x] Implement `mlui_kernel_reset_frame`.

### Borrow Resolvers

- [x] Implement `ui_borrow_node`.
- [x] Implement `ui_borrow_content`.
- [x] Implement `ui_borrow_text_layout`.
- [x] Implement `ui_borrow_paint`.
- [x] Implement `ui_borrow_image`.
- [x] Implement `ui_borrow_font`.
- [x] Implement `ui_borrow_value`.
- [x] Confirm every resolver checks out-of-range -> `missing`.
- [x] Confirm every resolver checks dead slot -> `missing`.
- [x] Confirm every resolver checks generation mismatch -> `stale`.
- [x] Confirm no resolver exposes a lease on failure.

### Resource Lifecycles

- [x] Create `experiments/mlui/mlui_resource_store.mlua`.
- [x] Implement `ui_content_retain`.
- [x] Implement `ui_content_publish`.
- [x] Implement `ui_content_release`.
- [x] Implement `ui_text_layout_retain`.
- [x] Implement `ui_text_layout_publish`.
- [x] Implement `ui_text_layout_release`.
- [x] Implement `ui_paint_retain`.
- [x] Implement `ui_paint_publish`.
- [x] Implement `ui_paint_release`.
- [x] Implement `ui_image_register`.
- [x] Implement `ui_image_release`.
- [x] Implement `ui_font_register`.
- [x] Implement `ui_font_release`.
- [x] Implement `ui_value_retain`.
- [x] Implement `ui_value_publish`.
- [x] Implement `ui_value_release`.
- [x] Implement `ui_visit_value`.
- [x] Confirm retain/register regions return `owned Ref`.
- [x] Confirm publish consumes `owned Ref`.
- [x] Confirm release consumes or returns `owned Ref` exactly as declared.
- [x] Confirm durable content bytes are copied.

### Bytecode Validation And Import

- [x] Create `experiments/mlui/mlui_program_validate.mlua`.
- [x] Implement `ui_validate_program`.
- [x] Implement `mlui_validate_program`.
- [x] Validate null program pointer.
- [x] Validate `MLUI_MAGIC`.
- [x] Validate `MLUI_ABI_VERSION`.
- [x] Validate endian.
- [x] Validate pointer size.
- [x] Validate root kind.
- [x] Validate root index.
- [x] Validate auth opcode ranges.
- [x] Validate compose opcode ranges.
- [x] Validate child ranges.
- [x] Validate wrapper arity.
- [x] Validate leaf arity.
- [x] Validate style token ranges.
- [x] Validate style track ranges.
- [x] Validate paint ranges.
- [x] Validate resource refs.
- [x] Validate duplicate nonzero ids.
- [x] Validate unsupported flags.
- [x] Create `experiments/mlui/mlui_program_import.mlua`.
- [x] Implement `ui_import_auth`.
- [x] Implement `mlui_import_auth_buffer`.
- [x] Implement `mlui_load_program`.
- [x] Confirm `mlui_load_program` emits `ui_validate_program`.
- [x] Confirm `mlui_load_program` handles auth root.
- [x] Confirm `mlui_load_program` handles compose root.
- [x] Confirm imported nodes preserve `auth_index`.

### Compose And Style

- [x] Create `experiments/mlui/mlui_compose_expand.mlua`.
- [x] Implement `ui_visit_compose_node`.
- [x] Implement `ui_expand_compose`.
- [x] Implement panel expansion.
- [x] Implement scroll panel expansion.
- [x] Implement hsplit expansion.
- [x] Implement vsplit expansion.
- [x] Implement workbench expansion.
- [x] Create `experiments/mlui/mlui_style_resolve.mlua`.
- [x] Implement `ui_visit_style_atom`.
- [x] Implement `ui_resolve_style`.
- [x] Implement condition matching for env.
- [x] Implement condition matching for state.
- [x] Implement layout style atoms.
- [x] Implement decor style atoms.
- [x] Implement token override order.
- [x] Implement `invalid_atom`.
- [x] Implement `missing_theme`.

### Lower, Measure, Solve

- [x] Create `experiments/mlui/mlui_scene_lower.mlua`.
- [x] Implement `ui_visit_auth_node`.
- [ ] Implement `ui_visit_layout_node`.
- [ ] Implement `ui_visit_decor_node`.
- [ ] Implement `ui_lower_scene`.
- [ ] Lower visual/content nodes.
- [ ] Lower scroll wrappers.
- [ ] Lower input wrappers.
- [ ] Lower drag/drop wrappers.
- [ ] Lower focus scopes.
- [ ] Lower layers.
- [ ] Lower overlays.
- [ ] Lower modals.
- [ ] Create `experiments/mlui/mlui_measure.mlua`.
- [ ] Implement `ui_measure_node`.
- [ ] Measure empty/fragment.
- [ ] Measure flow.
- [ ] Measure flex row.
- [ ] Measure flex column.
- [ ] Measure grid subset.
- [ ] Measure text leaf.
- [ ] Measure text ref.
- [ ] Measure paint/canvas.
- [ ] Measure wrappers by child.
- [ ] Create `experiments/mlui/mlui_solve.mlua`.
- [ ] Implement `ui_visit_solve_node`.
- [ ] Implement `ui_solve_scene`.
- [ ] Place border rects.
- [ ] Place content rects.
- [ ] Compute scroll content extents.
- [ ] Preserve solved wrappers.
- [ ] Store text layout refs in solve nodes.

### Render And Runtime Report

- [ ] Create `experiments/mlui/mlui_render_ops.mlua`.
- [ ] Implement `ui_visit_view_op`.
- [ ] Implement `ui_visit_paint_program`.
- [ ] Implement `ui_render_ops`.
- [ ] Emit `Box`.
- [ ] Emit `Text`.
- [ ] Emit `Paint`.
- [ ] Emit `PushClipRect` / `PopClip`.
- [ ] Emit `PushTx` / `PopTx`.
- [ ] Emit `PushScroll` / `PopScroll`.
- [ ] Emit `Hit`.
- [ ] Emit `Focus`.
- [ ] Emit `Cursor`.
- [ ] Emit drag/drop ops.
- [ ] Emit focus scope ops.
- [ ] Emit layer ops.
- [ ] Emit overlay and modal barrier ops.
- [ ] Implement `mlui_view_ops`.
- [ ] Create `experiments/mlui/mlui_runtime_report.mlua`.
- [ ] Implement `ui_runtime_report`.
- [ ] Implement `mlui_runtime_report`.
- [ ] Implement `mlui_report_get`.
- [ ] Maintain transform stack.
- [ ] Maintain clip stack.
- [ ] Maintain scroll stack.
- [ ] Maintain focus scope stack.
- [ ] Maintain layer/modal stack.
- [ ] Collect hits.
- [ ] Collect focusables.
- [ ] Collect scrollables.
- [ ] Collect drag/drop boxes.
- [ ] Collect layers/overlays/modal barriers.
- [ ] Return `malformed_op` for invalid rows.
- [ ] Return `stack_unbalanced` for unbalanced push/pop.

### Interaction

- [ ] Create `experiments/mlui/mlui_interact.mlua`.
- [ ] Implement `ui_visit_raw_input`.
- [ ] Implement `ui_visit_event`.
- [ ] Implement `ui_visit_key`.
- [ ] Implement `ui_interact_step`.
- [ ] Implement pointer move.
- [ ] Implement pointer press.
- [ ] Implement pointer release.
- [ ] Implement pointer cancel.
- [ ] Implement wheel routing.
- [ ] Implement key press.
- [ ] Implement key release.
- [ ] Implement focus move.
- [ ] Implement focus lost.
- [ ] Implement activate focused.
- [ ] Implement cancel interaction.
- [ ] Implement text input routing.
- [ ] Implement text editing routing.
- [ ] Implement drag pending.
- [ ] Implement drag movement.
- [ ] Implement drop/cancel.
- [ ] Implement scroll clamping.
- [ ] Implement `mlui_interact_step`.
- [ ] Implement `mlui_events`.
- [ ] Implement `mlui_clear_events`.

### ABI And C Artifact

- [ ] Create `experiments/mlui/mlui_abi.mlua`.
- [ ] Implement `mlui_lower_solve_render`.
- [ ] Implement `mlui_frame`.
- [ ] Confirm every `F.*` function is implemented exactly once.
- [ ] Confirm ABI functions only translate protocol exits to `UiStatus`/`i32`.
- [ ] Confirm `mlui_frame` composes reset/lower/solve/render/report/interact.
- [ ] Keep `experiments/mlui/mlui_c_api.h` synchronized with the header.
- [ ] Create `experiments/mlui/mlui_build_c.lua`.
- [ ] Emit single C blob.
- [ ] Compile generated C with `gcc -O3`.
- [ ] Compile generated C with `cc` fallback.
- [ ] Confirm no generated C depends on LuaJIT.
- [ ] Confirm C frontend can construct a `mlui_program`.

### Tests

- [ ] Keep `tests/experiments/test_mlui_types.lua` passing.
- [ ] Keep `tests/experiments/test_mlui_c_api_header.lua` passing.
- [ ] Add bytecode bad header test.
- [ ] Add bytecode bad opcode test.
- [ ] Add bytecode bad range test.
- [ ] Add duplicate id validation test.
- [ ] Add C-built box/text program import test.
- [ ] Add Lua no-parens to `UiProgram` equivalence test.
- [ ] Add render op golden test.
- [ ] Add runtime report golden test.
- [ ] Add interaction pointer test.
- [ ] Add interaction key/focus test.
- [ ] Add interaction text input test.
- [ ] Add interaction drag/drop test.
- [ ] Add generated C blob compile test.

### 1. Header Hygiene

Tasks:

- Rename or explicitly document the `mlui_types.mlua` header exception.
- Keep all public `T.*`, `R.*`, and `F.*` declarations in the header.
- Add missing products before writing bodies if a body needs a fact that is not
  named yet.
- Add enum constants as products or generated C constants; do not rely on magic
  comments.

Done when:

- `rg '^T\\.' experiments/mlui/mlui_types.mlua` answers public products.
- `rg '^R\\.' experiments/mlui/mlui_types.mlua` answers all protocols.
- `rg '^F\\.' experiments/mlui/mlui_types.mlua` answers ABI seals.

### 2. Memory Primitives: `mlui_memory.mlua`

Implement private helpers first.  These are not public protocols unless the
header declares them.

Required helpers:

```text
mlui_alloc_bytes
mlui_realloc_bytes
mlui_free_bytes
mlui_zero_bytes
mlui_copy_bytes
mlui_grow_u32_buffer
mlui_grow_auth_buffer
mlui_grow_scene_buffer
mlui_grow_solve_buffer
mlui_grow_view_buffer
mlui_grow_event_buffer
```

Implementation law:

- Use `UiAllocator` callbacks when present.
- Use default extern malloc/realloc/free only behind this file.
- Return `oom(needed)` through regions.
- Never make allocation failure a Lua exception.
- Use counted loops:

```lalin
block loop(i: index = 0)
    if i >= n then jump copied end
    dst[i] = src[i]
    jump loop(i = i + 1)
end
```

### 3. Kernel Store: `mlui_kernel_store.mlua`

Implement:

```text
R.ui_kernel_create
R.ui_kernel_borrow
R.ui_kernel_close
R.ui_reset_auth
R.ui_reset_scene
R.ui_reset_solve
R.ui_reset_view
R.ui_reset_frame_events
F.mlui_kernel_init
F.mlui_kernel_init_ex
F.mlui_kernel_close
F.mlui_kernel_reset_frame
```

Mechanical behavior:

- `ui_kernel_create`: allocate and zero `UiKernel`, initialize all store caps,
  return `owned UiKernelRef`.
- `ui_kernel_borrow`: resolve `UiKernelRef` to `lease ptr(UiKernel)` or
  `stale/missing`.
- `ui_kernel_close`: free all buffers/stores, consume owned handle, return
  `busy(kernel)` only if outstanding owned child resources prevent close.
- reset regions set counts to zero and bump relevant epochs/generations.

If `UiKernelRef` is not yet backed by a global/session store, add that store to
the header.  Do not fake `UiKernelRef` as `ptr(UiKernel)` in public APIs.

### 4. Handle Stores And Borrow Regions

Implement reusable slot+generation logic for every `Ref` store:

```text
R.ui_borrow_node
R.ui_borrow_content
R.ui_borrow_text_layout
R.ui_borrow_paint
R.ui_borrow_image
R.ui_borrow_font
R.ui_borrow_value
```

Resolver algorithm for every store:

```text
unpack ref -> index, generation
index out of range -> missing(ref)
slot.live == false -> missing(ref)
slot.gen != generation -> stale(ref)
otherwise -> borrowed(lease(kernel) ptr(slot.product))
```

Add private helpers in the same machine file, not global Lua helpers.

Do not expose handle packing/unpacking outside store implementation files.

### 5. Resource Lifecycles: `mlui_resource_store.mlua`

Implement:

```text
R.ui_content_retain
R.ui_content_publish
R.ui_content_release
R.ui_text_layout_retain
R.ui_text_layout_publish
R.ui_text_layout_release
R.ui_paint_retain
R.ui_paint_publish
R.ui_paint_release
R.ui_image_register
R.ui_image_release
R.ui_font_register
R.ui_font_release
R.ui_value_retain
R.ui_value_publish
R.ui_value_release
```

Rules:

- `retain/register` allocate a slot and return `owned Ref`.
- `publish` transfers owned obligation into kernel-visible durable identity.
- `release` consumes owned obligation or returns it on `missing/stale`.
- `content_retain` copies bytes; borrowed text must not become durable without
  copying.
- `paint_retain` deep-copies paint programs/ranges if source memory is not
  kernel-owned.
- image/font records store host backend keys, not raw backend pointers unless
  the backend key type is explicitly an opaque integer.

### 6. Bytecode Validation: `mlui_program_validate.mlua`

Implement:

```text
R.ui_validate_program
F.mlui_validate_program
```

Validation order:

1. null pointer checks;
2. `magic == MLUI`;
3. `abi_version == MLUI_ABI_VERSION`;
4. endian and pointer size match runtime profile;
5. root kind and root index valid;
6. section pointers/counts consistent;
7. auth opcode kind in range;
8. compose opcode kind in range;
9. child ranges are in-bounds;
10. wrapper arity exactly one child;
11. leaf arity zero children;
12. token ranges in-bounds;
13. style track ranges in-bounds;
14. paint ranges in-bounds;
15. resource refs not invalid when required;
16. duplicate nonzero ids fail;
17. unsupported feature flags fail.

Use separate local blocks:

```text
check_header -> check_auth_loop -> check_compose_loop -> check_ids_loop -> valid
```

Do not import or mutate kernel state during validation except temporary scratch
owned by the validation region.

### 7. Program Import: `mlui_program_import.mlua`

Implement:

```text
R.ui_import_auth
F.mlui_import_auth_buffer
F.mlui_load_program
```

Algorithm:

1. `mlui_load_program` emits `ui_validate_program`.
2. If root is compose, emit `ui_expand_compose` first.
3. Emit `ui_import_auth`.
4. Return root `UiNodeRef`.

`ui_import_auth`:

- reset auth/node store for the imported program or update by stable id/shape
  when memoization support exists;
- create `UiNodeRecord` for each auth opcode;
- preserve `auth_index`;
- validate duplicate ids if not already validated;
- store stable `UiId -> UiNodeRef` association if an id lookup store is added;
- return root node ref.

Do not skip validation because the C frontend "should be trusted".

### 8. Compose Expansion: `mlui_compose_expand.mlua`

Implement:

```text
R.ui_expand_compose
R.ui_visit_compose_node
```

Visitor exits map opcodes:

```text
panel
scroll_panel
hsplit
vsplit
workbench
```

Expansion emits canonical auth ops:

- panel -> box/header/body/footer composition;
- scroll_panel -> scroll wrapper plus panel body;
- hsplit/vsplit -> flex/grid with two or more child panes;
- workbench -> named regions for toolbar/sidebar/main/bottom.

Do not erase compose nouns before validation.  `ui_expand_compose` is the only
consumer that turns compose into auth.

### 9. Style Resolution: `mlui_style_resolve.mlua`

Implement:

```text
R.ui_visit_style_atom
R.ui_resolve_style
```

Required behavior:

- Check `UiStyleCond` against `UiEnvClass` and `UiState`.
- For matching tokens, apply `UiStyleAtom` to `UiLayoutStyle` and
  `UiDecorStyle`.
- Later tokens override earlier tokens where `lua/ui` does.
- Unsupported atom kind returns `invalid_atom(kind)`.
- Missing theme resources return `missing_theme`.

Do not hard-code one widget's style path.  The region is the single owner of
style atom interpretation.

### 10. Scene Lowering: `mlui_scene_lower.mlua`

Implement:

```text
R.ui_visit_auth_node
R.ui_lower_scene
R.ui_visit_layout_node
R.ui_visit_decor_node
```

`ui_lower_scene`:

- borrow/import root node;
- walk imported auth nodes in child order;
- resolve style for each node;
- append parallel `UiLayoutNode` and `UiDecorNode`;
- preserve child ranges;
- preserve wrappers: scroll, input, drag/drop, focus scope, layer, overlay,
  modal;
- fail on `missing_node`, `duplicate_id`, `unsupported_node`, or `oom`.

Do not directly emit view ops from auth.  Lowering produces scene only.

### 11. Measurement: `mlui_measure.mlua`

Implement:

```text
R.ui_measure_node
```

Required cases:

- empty/fragment;
- flow;
- flex row/column;
- grid subset declared in current ASDL;
- text leaf with `UiContentRef`;
- text ref;
- paint/canvas;
- scroll wrapper;
- input/drag/drop/focus/layer/overlay/modal wrappers.

Text:

- use retained `UiTextLayoutRef` if valid for key `(content,font,width,epoch)`;
- otherwise call backend text measurement callback/product once available;
- approximate fallback only if the program/profile explicitly allows it.

Do not make render re-measure text.

### 12. Solve: `mlui_solve.mlua`

Implement:

```text
R.ui_solve_scene
R.ui_visit_solve_node
```

Required behavior:

- consume current `UiSceneBuffer`;
- produce `UiSolveBuffer`;
- place every layout node into border/content rects;
- compute scroll content extents;
- store selected text layout refs;
- preserve wrappers as solved nodes;
- fail on `missing_scene`, `missing_text`, `text_backend_error`,
  `unsupported_layout`, or `oom`.

Use block-based loops for child traversal and layout.  No Lua recursion in the
native kernel.

### 13. Render Ops: `mlui_render_ops.mlua`

Implement:

```text
R.ui_render_ops
R.ui_visit_view_op
R.ui_visit_paint_program
F.mlui_view_ops
```

Render semantics must match `lua/ui/render.lua`:

- ordered stream is authoritative;
- push/pop transform around non-root placed children;
- push/pop clip for clipped boxes;
- push/pop scroll with content extents;
- emit `Box` when visual is non-empty;
- emit `Text` with retained text layout ref/style;
- emit `Paint` with paint range;
- emit semantic ops for hit/focus/cursor/drag/drop/focus scope/layer/overlay/
  modal barrier.

Do not output backend draw calls.  Output `UiViewOp` rows only.

`ui_visit_view_op` owns `kind` decoding.  Backends and report construction call
the visitor or mirror its exact table; they do not scatter raw `kind` switches.

### 14. Runtime Report: `mlui_runtime_report.mlua`

Implement:

```text
R.ui_runtime_report
F.mlui_runtime_report
F.mlui_report_get
```

The report builder consumes the same `UiViewOp` stream as drawing:

- maintain transform stack;
- maintain clip stack;
- maintain scroll stack;
- maintain focus scope stack;
- maintain layer/modal stack;
- compute absolute rects;
- collect hit boxes, focus boxes, scroll boxes, drag/drop boxes, layers,
  overlays, modal barriers, focus scopes;
- select topmost hover/cursor/scroll ids by stream order and current model
  pointer position.

Malformed ops return `malformed_op`; unbalanced stacks return
`stack_unbalanced`.

Do not build a second hidden tree for hit testing.

### 15. Raw Input And Interaction: `mlui_interact.mlua`

Implement:

```text
R.ui_visit_raw_input
R.ui_visit_event
R.ui_visit_key
R.ui_interact_step
F.mlui_interact_step
F.mlui_events
F.mlui_clear_events
```

Reducer behavior:

- pointer moved: update pointer, hover from report, drag move if dragging;
- pointer pressed: choose top hit target, set pressed/capture, maybe drag
  pending;
- pointer released: activate if press/release under capture rules, drop/cancel
  drag, release capture;
- pointer cancelled/focus lost: clear pressed/capture/drag as events;
- wheel: route to hovered/current scroll target and clamp through scroll boxes;
- key pressed: focus traversal, activation, cancel, text navigation hooks;
- key released: emit only state changes that current ASDL demands;
- text input/text editing: route to focused edit target or
  `text_input_without_focus`;
- abstract focus/activate/cancel inputs map to same semantic paths as keys.

Events are rows in `UiEventBuffer`.  Widgets/app route events outside the
kernel.  The reducer never calls app callbacks.

### 16. ABI Seals: `mlui_abi.mlua`

Implement all `F.*` functions as seals:

```text
F.mlui_kernel_init
F.mlui_kernel_init_ex
F.mlui_kernel_close
F.mlui_kernel_reset_frame
F.mlui_import_auth_buffer
F.mlui_load_program
F.mlui_validate_program
F.mlui_lower_solve_render
F.mlui_frame
F.mlui_runtime_report
F.mlui_interact_step
F.mlui_view_ops
F.mlui_events
F.mlui_report_get
F.mlui_clear_events
```

Rules:

- ABI functions may return `i32` or `UiStatus`.
- ABI functions convert typed region exits to status codes exactly once.
- ABI functions do not duplicate region logic.
- Borrowed output pointers are valid until next frame/reset/close.
- `mlui_frame` composes the pipeline:

```text
reset frame events
lower scene
solve scene
render ops
runtime report
interact step if raw != null
return status
```

### 17. C Header And Amalgamation

Keep `mlui_c_api.h` synchronized with `mlui_types.mlua` and
`mlui_bytecode.md`.

Implement `mlui_build_c.lua` later:

- load MLUI module bundle;
- emit C backend source with executed-module `:emit_c` or `lalin.emit_c_file`;
- prepend/emit `mlui_c_api.h` declarations;
- produce `mlui_amalgam.c`;
- compile smoke:

```sh
gcc -O3 -std=c99 -fPIC -shared -I. -o /tmp/mlui.so mlui_amalgam.c
```

Do not hand-maintain diverging opcode numbers.  Generate them or test them.

## Region Completion Matrix

Every item below must have a body.  Declaration-only is not completion.

| Region/func | File | Implementation note |
| --- | --- | --- |
| `ui_kernel_create` | `mlui_kernel_store.mlua` | allocate/zero kernel, initialize stores |
| `ui_kernel_borrow` | `mlui_kernel_store.mlua` | resolve kernel handle to lease |
| `ui_kernel_close` | `mlui_kernel_store.mlua` | free stores, consume owned handle |
| `ui_reset_auth` | `mlui_kernel_store.mlua` | reset imported node/auth state |
| `ui_reset_scene` | `mlui_kernel_store.mlua` | reset scene buffer |
| `ui_reset_solve` | `mlui_kernel_store.mlua` | reset solve buffer |
| `ui_reset_view` | `mlui_kernel_store.mlua` | reset view buffer/report temps |
| `ui_reset_frame_events` | `mlui_kernel_store.mlua` | clear events only |
| `ui_borrow_node` | `mlui_resource_store.mlua` | slot+generation resolver |
| `ui_borrow_content` | `mlui_resource_store.mlua` | slot+generation resolver |
| `ui_borrow_text_layout` | `mlui_resource_store.mlua` | slot+generation resolver |
| `ui_borrow_paint` | `mlui_resource_store.mlua` | slot+generation resolver |
| `ui_borrow_image` | `mlui_resource_store.mlua` | slot+generation resolver |
| `ui_borrow_font` | `mlui_resource_store.mlua` | slot+generation resolver |
| `ui_borrow_value` | `mlui_resource_store.mlua` | slot+generation resolver |
| `ui_expand_compose` | `mlui_compose_expand.mlua` | compose buffer to auth buffer |
| `ui_resolve_style` | `mlui_style_resolve.mlua` | tokens to layout/decor style |
| `ui_visit_style_atom` | `mlui_style_resolve.mlua` | owns style atom decoding |
| `ui_visit_compose_node` | `mlui_compose_expand.mlua` | owns compose kind decoding |
| `ui_visit_auth_node` | `mlui_program_import.mlua` | owns auth opcode decoding |
| `ui_visit_layout_node` | `mlui_scene_lower.mlua` | owns layout kind decoding |
| `ui_visit_decor_node` | `mlui_scene_lower.mlua` | owns decor kind decoding |
| `ui_visit_solve_node` | `mlui_solve.mlua` | owns solved kind decoding |
| `ui_visit_view_op` | `mlui_render_ops.mlua` | owns view op kind decoding |
| `ui_visit_paint_program` | `mlui_render_ops.mlua` | owns paint kind decoding |
| `ui_import_auth` | `mlui_program_import.mlua` | auth rows to node store |
| `ui_validate_program` | `mlui_program_validate.mlua` | full bytecode validation |
| `ui_lower_scene` | `mlui_scene_lower.mlua` | auth/node store to scene |
| `ui_measure_node` | `mlui_measure.mlua` | intrinsic sizing |
| `ui_solve_scene` | `mlui_solve.mlua` | scene to placed solve buffer |
| `ui_render_ops` | `mlui_render_ops.mlua` | solve/decor to view ops |
| `ui_runtime_report` | `mlui_runtime_report.mlua` | view ops to report |
| `ui_visit_raw_input` | `mlui_interact.mlua` | raw input decoding |
| `ui_visit_event` | `mlui_interact.mlua` | event decoding |
| `ui_visit_key` | `mlui_interact.mlua` | key decoding |
| `ui_visit_value` | `mlui_resource_store.mlua` | value record decoding |
| `ui_interact_step` | `mlui_interact.mlua` | pure reducer |
| all retain/publish/release/register regions | `mlui_resource_store.mlua` | owned obligations |
| all `F.*` ABI functions | `mlui_abi.mlua` | seal protocols to C status |

## Test Plan After Bodies Exist

Only after all region bodies exist:

```text
tests/experiments/test_mlui_types.lua
tests/experiments/test_mlui_c_api_header.lua
new test: bytecode validation rejects bad headers/opcodes/ranges
new test: C-built UiProgram box/text imports
new test: Lua no-parens DSL emits same UiProgram as C builder
new test: render op golden for box/text/scroll/input/focus/layer/modal
new test: runtime report golden for hit/focus/scroll/overlay/modal
new test: interact reducer golden for pointer/key/text/drag/scroll
new test: C header + emitted C blob compiles with gcc -O3
```

Do not make tests assert only that symbols exist.  Symbol tests are smoke tests,
not implementation tests.

## Forbidden Shortcuts

These are not acceptable:

- implementing MLUI only in Lua and calling it done;
- returning success from unimplemented regions;
- emitting empty buffers to satisfy ABI shape;
- converting all internal failures to `i32` status early;
- using Lua tables as hidden native stores;
- treating `UiProgramOp.kind` as a random switch outside visitor regions;
- skipping ownership by storing raw pointers in refs;
- making text input durable without copying;
- making the C API depend on LuaJIT, FFI, or Lalin host objects;
- adding a generic `memo func`;
- hiding cache invalidation in side tables;
- adding deep folders to look organized.

## Final Completion Definition

The implementation is done only when:

```text
1. every R.* region has a Lalin body;
2. every F.* ABI function has a Lalin body;
3. the C header and Lalin ABI declarations agree;
4. a C frontend can construct a UiProgram without Lua;
5. the VM validates, loads, frames, emits view ops, reports, and events;
6. gcc -O3 can compile the generated single-file C artifact;
7. Lua no-parens authoring and C bytecode authoring produce equivalent VM input;
8. tests cover malformed bytecode, ownership failures, render/report stacks,
   and interaction reducer events.
```

Until then, the work is not complete.  Passing declaration tests is not complete.
