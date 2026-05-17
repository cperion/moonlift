# Step 9: Memory, atomic, globals, view return, export wrappers

Complete the remaining command families across all lowerer files. This is an **integration pass** that wires up atomic ops, global data commands, view return ABI (sret), and host export wrappers.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every case complete.**

**Note:** Before this step, the lowerer returns `ok=false` for atomic ops, global data accesses, and view returns. This step replaces those stubs with real implementations.

## Tree encoding — what exists and what does not

### Atomic expression tags

| Tag | Constant | `expr_op` | `expr_lhs` | `expr_rhs` | `expr_aux0` | Source ref |
|-----|----------|-----------|------------|------------|-------------|------------|
| EX_UNARY | 3 | unary_op | sub expr idx | 0 | 0 | `native_core.mlua:478` |
| EX_BINARY | 4 | bin_op | lhs expr | rhs expr | 0 | `native_core.mlua:478` |
| EX_ATOMIC_LOAD | N/A | — | — | — | — | **not encoded in parser yet** — these are in `mom_tags.lua` for future use |
| EX_ATOMIC_RMW | N/A | — | — | — | — | **not encoded in parser yet** |
| EX_ATOMIC_CAS | N/A | — | — | — | — | **not encoded in parser yet** |

**Atomic expressions are NOT yet emitted by the parser.** Currently, atomic constructs (`@atomic.load`, `@atomic.rmw`, `@atomic.cas`) are handled at the AST level in the hosted compiler and lowered to `BackCmd` directly. The MOM parser has no `EX_ATOMIC_LOAD/RMW/CAS` constants — these exist only in `mom_tags.lua` under the `ME_*` prefix for future use.

### What does NOT exist

- **No `EX_ATOMIC_LOAD`, `EX_ATOMIC_RMW`, `EX_ATOMIC_CAS` in the parser** — these expression tags are defined in `mom_tags.lua` (as `ME_ATOMIC_LOAD` etc.) but **never emitted** by `native_core.mlua`. The step 9 implementation must still handle the expr_tags in the dispatch (looking up `T.EX_ATOMIC_LOAD` etc.), but silently return `ok=false` because the parser never produces them. When the parser later supports atomics, `ok=false` becomes the real implementation.
- **No `ST_ATOMIC_STORE`, `ST_ATOMIC_FENCE` in the parser** — same deal. Tags defined in mom_tags but never emitted. Handle dispatch with `ok=false`.
- **No `expr_subtag` array** — atomic rmw ops within EX_ATOMIC_RMW are encoded as expr_op (the subtag is the RMW operation variant). For now, this is not relevant since no atomics are emitted.
- **No `is_view_type()` helper in the tree** — view types are detected by checking `ctx.tree.type_tag[ty] == MT_VIEW` (value 4).
- **No separate `const_eval` in the tree** — constant evaluation for global const items must be done via `sem_const_eval.lua` oracle (read from Lua side, not MOM tree).
- **No `deref_bytes` computation** — always use 0 for default.

### Wire format for atomic commands

From `BACK_WIRE_FORMAT.md` and `back_command_binary.lua`:

- **CmdAtomicLoad**: dst, scalar, addr_base_tag, addr_base_id, byte_offset_lo, byte_offset_hi, memory_info, atomic_ordering
- **CmdAtomicStore**: scalar, addr_base_tag, addr_base_id, byte_offset_lo, byte_offset_hi, value, memory_info, atomic_ordering
- **CmdAtomicRmw**: dst, rmw_op, scalar, addr_base_tag, addr_base_id, byte_offset_lo, byte_offset_hi, value, memory_info, atomic_ordering
- **CmdAtomicCas**: dst, scalar, addr_base_tag, addr_base_id, byte_offset_lo, byte_offset_hi, expected, replacement, memory_info, atomic_ordering
- **CmdAtomicFence**: ordering (always `1` = AtomicSeqCst)

### Wire format for data commands

- **CmdDeclareData**: data_id, size_lo, size_hi, align_pow2
- **CmdDataInit**: data_id, offset_lo, offset_hi, scalar, lit_tag, lit_lo, lit_hi
- **CmdDataInitZero**: data_id, offset_lo, offset_hi, size_lo, size_hi
- **CmdDataAddr**: dst, data_id

## 1. Atomic expressions (expr_lower.mlua)

Each atomic case follows the same pattern: lower the address expression, lower the value expression(s), emit the atomic command.

Since the parser never emits these tags, the handlers return `ok=false`. Implement the dispatch structure:

```moonlift
-- In the main expr dispatcher switch block:
case T.EX_ATOMIC_LOAD then
    -- Parser never emits EX_ATOMIC_LOAD yet.
    jump done(value = 0, scalar = 0, ok = false)

case T.EX_ATOMIC_RMW then
    -- Parser never emits EX_ATOMIC_RMW yet.
    jump done(value = 0, scalar = 0, ok = false)

case T.EX_ATOMIC_CAS then
    -- Parser never emits EX_ATOMIC_CAS yet.
    jump done(value = 0, scalar = 0, ok = false)
```

When these are later enabled, the implementation will be:

### ExprAtomicLoad
```
expr_tag == EX_ATOMIC_LOAD:
  1. mb_lower_expr_region(ctx, addr_expr) → (addr_val, scalar, ok1)
  2. mb_emit_const(ctx, zero, BackIndex, BackLitInt(0), 0, 0)  -- zero offset
  3. mb_ctx_fresh_value(ctx) → dst
  4. mb_emit_atomic_load(ctx, dst, scalar, 0, addr_val, 0, 0, memory_info_read, 1)
     -- addr_base_tag=0 (BackAddrValue), byte_offset=0, memory_info_read=0, atomic_seq_cst=1
  5. Return (dst, scalar, ok=true)
```

### ExprAtomicRmw
```
expr_tag == EX_ATOMIC_RMW:
  1. mb_lower_expr_region(ctx, addr_expr) → (addr_val, scalar, ok1)
  2. mb_lower_expr_region(ctx, value_expr) → (val, val_scalar, ok2)
  3. mb_emit_const(ctx, zero, BackIndex, BackLitInt(0), 0, 0)
  4. mb_ctx_fresh_value(ctx) → dst
  5. rmw_op = atomic_rmw_op_from_subtag(subtag)  -- Add=1, Sub=2, And=3, Or=4, Xor=5, Xchg=6
  6. mb_emit_atomic_rmw(ctx, dst, rmw_op, scalar, 0, addr_val, 0, 0, val, memory_info_readwrite, 1)
  7. Return (dst, scalar, ok=true)
```

### ExprAtomicCas
```
expr_tag == EX_ATOMIC_CAS:
  1. Lower addr, expected, replacement expressions
  2. mb_emit_atomic_cas(ctx, dst, scalar, 0, addr_val, 0, 0, expected_val, replacement_val, ...)
  3. Return (dst, scalar, ok=true)
```

## 2. Atomic statements (stmt_lower.mlua)

Similarly, the parser never emits these. Stub implementations:

```moonlift
case T.ST_ATOMIC_STORE then
    jump done(flow = @{BackFallsThrough}, ok = false)

case T.ST_ATOMIC_FENCE then
    jump done(flow = @{BackFallsThrough}, ok = false)
```

### When enabled, actual implementation:
```
ST_ATOMIC_STORE:
  1. Lower addr_expr and value_expr
  2. mb_emit_atomic_store(ctx, scalar, 0, addr_val, 0, 0, val, memory_info_write, 1)
  3. Return (BackFallsThrough, ok=true)

ST_ATOMIC_FENCE:
  1. mb_emit_atomic_fence(ctx, 1)  -- AtomicSeqCst
  2. Return (BackFallsThrough, ok=true)
```

## 3. View return ABI (stmt_lower.mlua + address.mlua)

### StmtReturnValue for views

When the return type is a view (ctx.tree.type_tag[ret_type] == MT_VIEW = 4), the function returns via sret (hidden pointer). In the hosted compiler, this is handled by the ABI classification layer. In the MOM backend, view returns use the sret convention:

```
IF ctx.tree.type_tag[return_type] == @{T.MT_VIEW} (4):
  1. The return value expression produces data/len/stride (view components).
     Lower the value expression:
     mb_lower_expr_region(ctx, value_expr) → (val, scalar, ok)
     -- For EX_REF of a view local: env_lookup returns MB_LOCAL_VIEW
     --   with data_val, len_val, stride_val from env
  
  2. Get the hidden sret pointer from ctx.env (stored by func entry lowering).
     sret_ptr = lookup ctx.env for "sret" or similar hidden binding.
  
  3. Store view components at correct offsets:
     mb_emit_store_info(ctx, 0, BackPtr, 0, 0, sret_ptr, 0, 0, data_val, 0, 0, 0, 0, 0, 0, 0)
     -- data at offset 0, scalar=BackPtr
  
     Compute len_addr: mb_emit_ptr_offset(ctx, len_addr, 0, sret_ptr, 0, 1, 8, 0)
     mb_emit_store_info(ctx, 0, BackIndex, 0, 0, len_addr, 0, 0, len_val, 0, 0, 0, 0, 0, 0, 0)
     -- len at offset 8, scalar=BackIndex
  
     Compute stride_addr: mb_emit_ptr_offset(ctx, stride_addr, 0, sret_ptr, 0, 1, 16, 0)
     mb_emit_store_info(ctx, 0, BackIndex, 0, 0, stride_addr, 0, 0, stride_val, 0, 0, 0, 0, 0, 0, 0)
     -- stride at offset 16
  
  4. mb_emit_return_void(ctx)  -- real return is through hidden pointer, not value
```

For now, since the parser does NOT emit EX_VIEW expressions (step 6 established this), view return lowering should return `ok=false`. The implementation skeleton should be ready but gated:

```moonlift
case @{T.ST_RETURN_VALUE} then
    let value_expr = ctx.tree.stmt_name[idx]
    let ret_type = ctx.expr_type[value_expr]  -- or function result type
    if ctx.tree.type_tag[ret_type] == @{T.MT_VIEW} then
        -- View return not supported yet (parser doesn't emit EX_VIEW)
        jump done(flow = @{BackFallsThrough}, ok = false)
    end
    -- normal scalar return:
    ...
```

### mb_descriptor_field_load (address.mlua)

Helper for host export wrapper — loads a field from a view descriptor pointer:
```moonlift
mb_descriptor_field_load(ctx, desc_ptr, field_offset, field_scalar) -> value: i32
  1. mb_ctx_fresh_value(ctx) → dst
  2. mb_emit_load_info(ctx, dst, 0, field_scalar, 0, 0, desc_ptr, field_offset, 0, 0, 0, 0, 0, 0, 0, 0)
     -- addr_base_tag=0 (BackAddrValue), base=desc_ptr, offset=field_offset
     -- Default memory info for reads
  3. Return dst
```

This helper is for eventual view ABI support. In the current state (no view types in parser output), return `ok=false`.

## 4. Host export wrapper (func.mlua)

For hosted functions with view params/results, `mb_lower_host_export_wrapper` creates an ABI-compatible shim. Since view types aren't parsed yet, implement as stub with `ok=false`:

```moonlift
mb_lower_host_export_wrapper(ctx, item_idx, inner_func_id):
    return false  -- not supported yet (no view types in parser output)
```

The algorithm (for when view types are supported):
```
1. Get function sig from item: has TView params or result?
2. Create public sig using host ABI (BackPtr for each view param, BackPtr for view result)
3. For each TView param, unwrap: load data/len/stride from descriptor ptr
4. If TView result, store sret output ptr for return
5. Call inner function
6. Return void (for view return) or value (for scalar return)
```

## 5. Global data init, const/static commands (module.mlua)

### Current state

`mb_lower_module` in `back/module.mlua` already handles function lowering. This step adds data commands for global const/static items.

### Tree encoding for items

```
item_tag[idx]           = IT_FUNC=1, IT_EXTERN=2, IT_STRUCT=3, IT_UNION=4, IT_REGION=5, IT_EXPR_FRAG=6
item_tok[idx]           = token index
item_name[idx]          = name token
item_member_start[idx]  = param_start (for funcs), member/field start for structs
item_member_count[idx]  = param_count / member count
item_result[idx]        = result type index
item_body_start[idx]    = body stmt list start
item_body_count[idx]    = body stmt list count
```

**There is NO `item_const_value` or `item_static` flag in the tree.** Const and static items are distinguished by the Lua-level item kind at parse time. For MOM, the `compile_module.mlua` driver passes the item list from the Lua side. The driver provides const/static item metadata (NOT in the tree arrays — passed separately).

### Data emit algorithm

```
For each const item passed from driver (Lua provides list of const item infos):
  1. tree_idx = item_idx in tree
  2. item_type = ctx.tree.item_result[tree_idx]
  3. scalar = scalar_from_type(item_type) -- through back_scalar oracle
  4. size, align = type_size_align(item_type) -- from type_size_align.lua oracle
  5. mb_ctx_fresh_value(ctx) → data_id  (use value namespace, distinct from func IDs)
  6. mb_emit_declare_data(ctx, data_id, size, 0, align_pow2)  -- size_hi=0 for small sizes
  7. const_eval_value = sem_const_eval(tree_idx) -- from hosted oracle
  8. lit_tag, lit_lo, lit_hi = sem_const_to_literal(const_eval_value)
  9. mb_emit_data_init(ctx, data_id, 0, 0, scalar, lit_tag, lit_lo, lit_hi)  -- offset=0

For each static item:
  1. Same size/align computation
  2. mb_emit_declare_data(ctx, data_id, size, 0, align_pow2)
  3. mb_emit_data_init_zero(ctx, data_id, 0, 0, size, 0)  -- zero-init
  4. Store data_id in ctx static map
```

### Global data address in expressions

For `EX_REF` that resolves to a global const/static:
```
kind, value, scalar = mb_env_lookup_into(ctx.env, name_tok)
If kind == MB_NOT_FOUND:
  -- Could be global. Look up in ctx.global_data_map[name_tok]
  If found:
    mb_ctx_fresh_value(ctx) → dst
    mb_emit_data_addr(ctx, dst, data_id)
    Return (dst, BackPtr, ok=true)
  Else:
    Return ok=false
```

### Command order in module lowering

```
1. mb_emit_target_model(ctx, triple, data_layout)  -- if applicable
2. mb_emit_create_sig for all function/extern sigs (deduplicated)
3. mb_emit_declare_func / mb_emit_declare_extern for all items
4. mb_emit_declare_data for all const/static items
5. Function bodies in item order
6. mb_emit_finalize_module(ctx)
```

### Scalar size/type helpers

From `type_size_align.lua` oracle:
```lua
MT_SCALAR=1: 
  BackI8=3  → size=1, align=1
  BackI16=4 → size=2, align=2
  BackI32=5 → size=4, align=4
  BackI64=6 → size=8, align=8
  BackU8=7  → size=1, align=1
  BackU16=8 → size=2, align=2
  BackU32=9 → size=4, align=4
  BackU64=10→ size=8, align=8
  BackF32=11→ size=4, align=4
  BackF64=12→ size=8, align=8
  BackPtr=13→ size=8, align=8 (64-bit)
  BackIndex=14→ size=8, align=8 (64-bit)
  BackBool=2 → size=1, align=1
```

## 6. Wiring table

| Case/Function | Lives in | Status | Notes |
|---|---|---|---|
| EX_ATOMIC_LOAD | expr_lower.mlua | stub → ok=false | Parser never emits |
| EX_ATOMIC_RMW | expr_lower.mlua | stub → ok=false | Parser never emits |
| EX_ATOMIC_CAS | expr_lower.mlua | stub → ok=false | Parser never emits |
| ST_ATOMIC_STORE | stmt_lower.mlua | stub → ok=false | Parser never emits |
| ST_ATOMIC_FENCE | stmt_lower.mlua | stub → ok=false | Parser never emits |
| View return sret | stmt_lower.mlua | stub → ok=false | No EX_VIEW in parser |
| `mb_descriptor_field_load` | address.mlua | stub → ok=false | Not needed until views work |
| `mb_lower_host_export_wrapper` | func.mlua | stub → ok=false | Not needed until views work |
| Const/static data | module.mlua | full | Wired via `declare_data` + `data_init` |
| Global data addr | expr_lower.mlua (EX_REF) | full | Wired via `data_addr` |

## Hard bans

- No raw command packing — all via `mb_emit_*` helpers (including `mb_emit_atomic_*`, `mb_emit_data_addr`, `mb_emit_declare_data`, `mb_emit_data_init`, `mb_emit_data_init_zero`)
- No `LowerState` — only `MomBackLowerCtx`
- No `CmdTrap` fallbacks
- No `TODO`/`FIXME`/`placeholder`/`simplified`
- View sret must write data/len/stride at correct offsets (0, 8, 16). Parser does not emit view types, so return `ok=false`
- Atomic ordering is always SeqCst (value 1) — hosted simplification
- Every atomic RMW must have the correct op mapping if enabled (Add=1, Sub=2, And=3, Or=4, Xor=5, Xchg=6)
- Const data must be declared before any function that references it (command order)
- Do NOT add new tree arrays — const/static metadata comes from Lua-level driver, not tree
