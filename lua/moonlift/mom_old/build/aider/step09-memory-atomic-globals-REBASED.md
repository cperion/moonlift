# Step 9: Command tape width, memory/data commands, globals, and atomics
## [REBASED for Struct-Based Continuation Architecture]

This step is an integration/repair pass after Step 8. Its primary job is to extend
the native command buffer to represent **all MLBT v3 command slots**, and to wire
memory/data commands using the new **struct-based continuation architecture**.

**Architecture note**: All regions now use struct result types (MomExprResult,
MomStmtResult, MomAddressResult, etc.) instead of tuple continuations. This step
must maintain consistency with that pattern.

**Policy**: Hard rewrite for touched files. No raw command packing in lowerers,
no `LowerState`, no `CmdTrap` fallback, no fake global/atomic/view support. All
result continuations use struct types. If parser/typecheck do not represent a
feature, return explicit `ok=false` via struct result instead of inventing semantics.

## Required source-of-truth checks

Read and cross-check before editing:

- `BACK_WIRE_FORMAT.md` section 7 command slot table
- `lua/moonlift/back_command_binary.lua` hosted MLBT encoder
- `lua/moonlift/tree_to_back.lua` memory/global/data lowering oracle
- `lua/moonlift/type_size_align.lua`
- `lua/moonlift/type_to_back_scalar.lua`
- `lua/moonlift/mom/schema/MoonBack.mlua` — **all result struct types**
- `lua/moonlift/mom/runtime/builders.mlua`
- `lua/moonlift/mom/back/cmd.mlua`
- `lua/moonlift/mom/driver/lower_wire.mlua`
- `lua/moonlift/mom/back/validate.mlua`

## Result struct types (from schema)

All region continuations now use one of these struct result types:

```
MomExprResult = {value: i32, scalar: i32, ok: bool}
MomStmtResult = {flow: i32, ok: bool}
MomAddressResult = {addr: i32, pointee_scalar: i32, ok: bool}
MomIndexAddrResult = {addr: i32, elem_scalar: i32, ok: bool}
MomViewResult = {data: i32, len: i32, stride: i32, elem_scalar: i32, ok: bool}
```

Use only these types. Do not create new tuple-based continuations.

## Non-negotiable correction: command tape width

Current `MomCmdBuffer` must support full MLBT v3 command widths (up to 17 words).

### Required `MomCmdBuffer` shape (from schema)

In `runtime/builders.mlua`:

```moonlift
M.MomCmdBuffer = struct MomCmdBuffer
    tag: ptr(i32)
    w0: ptr(i32);  w1: ptr(i32);  w2: ptr(i32);  w3: ptr(i32)
    w4: ptr(i32);  w5: ptr(i32);  w6: ptr(i32);  w7: ptr(i32)
    w8: ptr(i32);  w9: ptr(i32);  w10: ptr(i32); w11: ptr(i32)
    w12: ptr(i32); w13: ptr(i32); w14: ptr(i32); w15: ptr(i32)
    w16: ptr(i32)
    len: index
    cap: index
end
```

Provide append helper:

```
mr_cmd_buffer_push_entry(b, tag, w0..w16) -> index
```

### Required `cmd.mlua` shape

`back/cmd.mlua` owns slot layout and emission helpers. Every `mb_emit_*` helper must:

1. Construct/fill a `CmdEntry` via `mb_cmd_*` constructor.
2. Push all `tag + w0..w16` into `MomCmdBuffer`.
3. Use struct continuations exclusively when calling sub-regions.

Do not truncate to six words. Do not hide extra words in `aux_i32` unless the
wire format explicitly expects an aux index.

### Required `lower_wire.mlua` shape

Wire encoder must serialize from `MomCmdBuffer` fields `tag,w0..w16` using
`mom_wire_slot_count(tag)`. It must not read old `a..f` fields after this step.

### Required `validate.mlua` shape

Validator must read command fields from `w0..w16`. It must validate:

- declaration order and duplicates for sig/func/extern/data/block/slot/value
- value definitions for `Const`, binary/unary/cast/compare/select/load/call/etc.
- block existence for jump/branch/switch
- data existence for `DataAddr`, `DataInit`, `DataInitZero`

## Correct MLBT v3 slot layouts

Use `BACK_WIRE_FORMAT.md`. Relevant layouts:

```
CmdDeclareData    [data, size, align]
CmdDataInitZero   [data, offset, size]
CmdDataInit       [data, offset, scalar, lit_tag, lit_lo, lit_hi]
CmdDataAddr       [dst, data]

CmdLoadInfo       [dst, shape_tag, scalar, lanes, base_tag, base_id, byte_offset,
                   access, align_k, align_b, deref_k, deref_b, trap_k, motion_k,
                   mode_k]
CmdStoreInfo      [shape_tag, scalar, lanes, base_tag, base_id, byte_offset, value,
                   access, align_k, align_b, deref_k, deref_b, trap_k, motion_k,
                   mode_k]

CmdAtomicLoad     [dst, scalar, base_tag, base_id, byte_offset, access, align_k,
                   align_b, deref_k, deref_b, trap_k, motion_k, mode_k, ordering,
                   pad]
CmdAtomicStore    [scalar, base_tag, base_id, byte_offset, value, access, align_k,
                   align_b, deref_k, deref_b, trap_k, motion_k, mode_k, ordering]
CmdAtomicRmw      [dst, op, scalar, base_tag, base_id, byte_offset, value, access,
                   align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k,
                   ordering]
CmdAtomicCas      [dst, scalar, base_tag, base_id, byte_offset, expected,
                   replacement, access, align_k, align_b, deref_k, deref_b, trap_k,
                   motion_k, mode_k, ordering, pad]
CmdAtomicFence    [ordering]
```

## Region continuation patterns

All regions that return address/memory results must follow this pattern:

```moonlift
local mb_example_region = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;
                                done: cont(result: MomAddressResult))
entry start()
    -- computation
    if error_condition then
        jump done(result = MomAddressResult{addr = 0, pointee_scalar = 0, ok = false})
    end
    jump done(result = MomAddressResult{addr = addr_val, pointee_scalar = scalar, ok = true})
end
end
```

Never emit results as tuples. Always use the struct literal syntax with field names.

## Memory/address command completion

### `back/address.mlua` — Already Converted ✓

This file has been converted to use struct-based continuations:

- `mb_view_to_back` returns `MomViewResult`
- `mb_index_addr_to_back` returns `MomIndexAddrResult`
- `mb_place_addr_to_back` returns `MomAddressResult`
- `mb_place_store_to_back` returns `MomStmtResult`
- All internal jumps use struct syntax

**Action**: Audit only for semantic correctness. Do not rewrite for struct
conversion.

### `back/expr_lower.mlua` — Audit for Memory Cases

Verify expression memory cases use struct results correctly:

- `ME_DEREF` → lower via `mb_lower_expr_region`, check `result.ok`
- `ME_INDEX` → delegate to address lowering, check address result type
- `ME_ADDR_OF` → delegate to place address lowering
- `ME_REF` → resolve to local scalar/stack/binding only if env stores it

All emit calls must use continuation blocks with struct parameters:

```moonlift
emit mb_lower_expr_region(ctx, expr_idx; done = after_expr)
block after_expr(result: MomExprResult)
    if result.ok == false then jump error end
    -- use result.value, result.scalar
end
```

### `back/stmt_lower.mlua` — Audit for Store Commands

Verify statement store commands:

- `ST_SET` with `EX_DEREF` place → emit `CmdStoreInfo` after address lowering
- All address/expression continuations receive struct results
- Store result wrapped in `MomStmtResult`

## Global data support: Path A (Explicit Unsupported)

The parser currently supplies no `item_const_value`, `item_static`, or const
initializer metadata. Step 9 implements Path A:

- `ME_REF` unresolved in local env returns `ok=false` via `MomExprResult`.
- module lowering does not invent data commands.
- Add clear tests proving unresolved references fail loudly.

### When metadata is added (Future)

If parser adds const/static metadata:

1. Add explicit driver-owned metadata fields to `MomBackLowerCtx`.
2. Implement collect-globals phase before function bodies.
3. Emit `CmdDeclareData` before functions.
4. Emit `CmdDataInit`/`CmdDataInitZero` from native metadata.
5. Bind global name → data id in backend env.
6. `ME_REF` unresolved local checks global map, emits `CmdDataAddr`.

Do not use hosted Lua tables at native runtime.

## Atomics: Explicit unsupported

`native_core.mlua` currently does not emit atomic expression/statement tags.
Step 9 does not implement atomic lowering.

For each atomic expression/statement:

- Dispatch only if tag constants exist and compile.
- Return `ok=false` / status unsupported via struct result.
- Do not emit atomic commands.

When parser support is added, use slot layouts above with `AtomicSeqCst` ordering.

## View returns: Explicit unsupported

Parser currently does not emit `ME_VIEW`. View ABI requires function-entry sret
binding and descriptor component values.

For this step:

- Scalar `MS_RETURN_VALUE` remains normal `CmdReturnValue`.
- If return expression/type is `MT_VIEW`, return `ok=false` unless full view ABI
  is implemented in same change.
- `mb_lower_host_export_wrapper` returns false/status; no partial wrappers.

## Module/function command order

After command-tape width repair, module lowering emits:

1. `CmdTargetModel`
2. all `CmdCreateSig`
3. all `CmdDeclareFunc` / `CmdDeclareExtern`
4. all represented `CmdDeclareData` / data init commands
5. function bodies in item order
6. `CmdFinalizeModule`

No duplicate function declarations. If module declares a function, `mb_lower_func`
begins/finishes same func id.

## Struct continuations in validate.mlua

Validator region continuations must use struct results:

```moonlift
local validate_section = region(ctx: ptr(@{MomBackLowerCtx});
                               done: cont(result: MomValidateResult))
-- ...
jump done(result = MomValidateResult{issue_count = count})
```

## Tests to add/run

Add focused tests:

1. `test_mom_command_width.lua`: emit a `CmdLoadInfo`, verify wire output has
   all 15 slots.
2. `test_mom_memory_lowering.lua`: scalar stack var load/store still works.
3. unresolved global ref fails loudly (if metadata path is later added).

Run:

```
luajit scripts/emit_mom_precompiled.lua
luajit tests/test_mom_run_2plus2.lua
luajit tests/test_mom_command_width.lua
luajit tests/test_mom_memory_lowering.lua
luajit scripts/check_mom_hygiene.lua
```

## Completion criteria

- ✓ Command buffer width extended to 17 words.
- ✓ All `mb_emit_*` helpers push full-width entries.
- ✓ `address.mlua` uses struct continuations (already done).
- ✓ `expr_lower.mlua` memory cases verified for struct usage.
- ✓ `stmt_lower.mlua` store commands verified.
- ✓ `validate.mlua` uses struct results.
- ✓ Tests pass.
- ✓ No new hygiene violations.
