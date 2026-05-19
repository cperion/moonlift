# Step 9: Command tape width, memory/data commands, globals, and explicit unsupported atomics/views

This step is an integration/repair pass after Step 8 and proper
`MomBackLowerCtx` function/module wiring. Its first job is to make the native
command buffer capable of representing **all MLBT v3 command slots**, not only
six payload words. Only after that should memory/data commands be wired.

**Policy: hard rewrite for touched files. No raw command packing in lowerers,
no `LowerState`, no `CmdTrap` fallback, no fake global/atomic/view support. If
parser/typecheck do not represent a feature, return explicit `ok=false`/status
instead of inventing semantics.**

## Required source-of-truth checks

Read and cross-check before editing:

- `BACK_WIRE_FORMAT.md` section 7 command slot table
- `lua/moonlift/back_command_binary.lua` hosted MLBT encoder
- `lua/moonlift/tree_to_back.lua` memory/global/data lowering oracle
- `lua/moonlift/type_size_align.lua`
- `lua/moonlift/type_to_back_scalar.lua`
- `lua/moonlift/sem_const_eval.lua` only as an oracle for future const eval
- `lua/moonlift/mom/runtime/builders.mlua`
- `lua/moonlift/mom/back/cmd.mlua`
- `lua/moonlift/mom/driver/lower_wire.mlua`
- `lua/moonlift/mom/back/validate.mlua`

## Non-negotiable correction: command tape width

Current/old `MomCmdBuffer` with only `tag,a,b,c,d,e,f` cannot encode MLBT v3
commands with more than six slots (`LoadInfo`, `StoreInfo`, `Call`, `BrIf`,
`Atomic*`, vector commands, etc.). Step 9 must fix this before adding memory or
atomic commands.

### Required `MomCmdBuffer` shape

Change `runtime/builders.mlua` to store canonical command entries:

```
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

Provide append helpers:

```
mr_cmd_buffer_push_entry(b, tag, w0..w16) -> index
mr_cmd_buffer_push6(...) may remain only as a compatibility wrapper if existing
callers need it, but lowerers must not use it directly.
```

### Required `cmd.mlua` shape

`back/cmd.mlua` owns slot layout. Every `mb_emit_*` helper must:

1. Construct/fill a `CmdEntry` via `mb_cmd_*` constructor.
2. Push all `tag + w0..w16` into `MomCmdBuffer`.
3. Export a named helper for every command family used by lowerers.

Do not truncate to six words. Do not hide extra words in `aux_i32` unless the
wire format explicitly expects an aux index (e.g. `params_aux`, `args_aux`,
`cases_aux`).

### Required `lower_wire.mlua` shape

Wire encoder must serialize from `MomCmdBuffer` fields `tag,w0..w16` using
`mom_wire_slot_count(tag)`. It must not read old `a..f` fields after this step.

### Required `validate.mlua` shape

Validator must read command fields from `w0..w16` or from a compatibility view
that is mechanically equivalent. It must validate at least:

- declaration order and duplicates for sig/func/extern/data/block/slot/value
- value definitions for `Const`, binary/unary/cast/compare/select/load/call/etc.
- block existence for jump/branch/switch
- data existence for `DataAddr`, `DataInit`, `DataInitZero`

## Correct MLBT v3 slot layouts to use

Use `BACK_WIRE_FORMAT.md`, not old notes. Relevant layouts:

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

No `size_hi`, `offset_hi`, or packed memory-info word exists in current MLBT v3.

## Memory/address command completion

### `back/address.mlua`

Complete and audit:

```
mb_memory_info_read(ctx...)       -- either returns explicit tuple values or helper constants
mb_memory_info_write(ctx...)
mb_address_from_ptr(ptr_value)    -- base_tag=0, base_id=ptr_value convention
mb_descriptor_field_load(...)     -- only if view descriptors are actually supported; otherwise ok=false
```

`mb_place_addr_to_back` must handle only tree-represented places:

- `ME_REF` stack local -> `CmdStackAddr`
- `ME_REF` scalar local -> not addressable, `ok=false`
- `ME_DEREF` -> lower child expression to pointer value
- `ME_INDEX` -> compute base address + index * element size
- `ME_DOT` -> only if layout/field resolution is available; otherwise `ok=false`

Do not add new tree arrays.

### `back/expr_lower.mlua`

Audit expression memory cases against `MomTreeOut` fields:

- use `expr_op/lhs/rhs/aux0`, not parser-private `expr_a/b/c/d`
- `ME_DEREF` emits `CmdLoadInfo`
- `ME_INDEX` delegates to address lowering then emits `CmdLoadInfo`
- `ME_ADDR_OF` delegates to place address lowering
- `ME_REF` may resolve to local scalar, stack local, function/extern/global binding only if the env/context actually stores those bindings

## Global data support: only for represented metadata

Do **not** claim full const/static lowering unless MOM parser/driver supplies
const/static metadata. Current `MomTreeOut.item_tag` only includes:

```
IT_FUNC, IT_EXTERN, IT_STRUCT, IT_UNION, IT_REGION, IT_EXPR_FRAG
```

There is no `item_const_value`, `item_static`, or const initializer tape.

Step 9 may implement one of these two paths:

### Path A: explicit unsupported (acceptable if no metadata exists)

- `ME_REF` unresolved in local env returns `ok=false`.
- module lowering does not invent data commands.
- Add clear tests proving unsupported references fail loudly.

### Path B: real metadata plumbing (only if implemented in this step)

If adding const/static support, add explicit driver-owned metadata fields to the
native workspace/context first. Then implement:

1. collect global data names -> data ids before function bodies
2. emit `CmdDeclareData` before any function body
3. emit `CmdDataInit`/`CmdDataInitZero` from real native const/static metadata
4. bind global name -> data id in a backend global map/env
5. `ME_REF` unresolved local checks global map and emits `CmdDataAddr`

Do not use hosted Lua tables at native runtime. Do not infer const values from
names or strings.

## Atomics: explicit unsupported until parser emits nodes

`native_core.mlua` currently does not emit atomic expression/statement tags.
If generated `mom_tags.lua` contains future `ME_ATOMIC_*` constants, they are
not design evidence.

For this step:

- Add dispatch only if constants exist and compile.
- Each atomic expression/statement returns `ok=false` / status unsupported.
- Do not emit atomic commands from non-existent syntax.

When parser support is later added, use the slot layouts above and ordering
`AtomicSeqCst`.

## View returns and host wrappers: explicit unsupported until view expression/ABI exists

Parser currently does not emit `ME_VIEW`. View ABI requires function-entry sret
binding and descriptor component values (`data`, `len`, `stride`). If those are
not represented in `MomBackLowerCtx`/env, do not implement fake stores.

For this step:

- scalar `MS_RETURN_VALUE` remains normal `CmdReturnValue`
- if return expression/type is `MT_VIEW`, return `ok=false` unless full view ABI
  plumbing is implemented in the same change
- `mb_lower_host_export_wrapper` may exist only as an explicit unsupported
  function returning false/status; it must not emit partial wrappers

## Module/function command order

After command-tape width repair, proper module lowering should emit:

1. `CmdTargetModel`
2. all `CmdCreateSig`
3. all `CmdDeclareFunc` / `CmdDeclareExtern`
4. all represented `CmdDeclareData` / data init commands
5. function bodies in item order
6. `CmdFinalizeModule`

No duplicate function declarations: if module hoisting declares a function,
`mb_lower_func` must begin/finish the same func id, not allocate and declare a
second one.

## Tests to add/run

Add focused tests:

1. command buffer width test: emit a `CmdLoadInfo` and verify wire output has all
   15 slots.
2. scalar stack var load/store still works.
3. unresolved global ref fails loudly.
4. if metadata path B is implemented: global data address and data init tests.

Run:

```
luajit scripts/emit_mom_precompiled.lua
luajit tests/test_mom_run_2plus2.lua
luajit tests/test_mom_command_width.lua
luajit tests/test_mom_memory_lowering.lua
luajit scripts/check_mom_hygiene.lua
```

Existing repository-wide hygiene may still report known schema/vector issues;
new touched files must not add new hygiene failures.
