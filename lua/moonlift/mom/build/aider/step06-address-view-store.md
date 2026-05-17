# Step 6: Address/view/store module

Create `lua/moonlift/mom/back/address.mlua` — address, view, and store lowering.
Update `lua/moonlift/mom/back/expr_lower.mlua` to wire EX_DOT, EX_INDEX, EX_ADDR dispatch.
Update `lua/moonlift/mom/back/stmt_lower.mlua` to wire ST_SET dispatch.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every function complete.**
**No `mb_emit_view`, `CmdViewFromData`, `CmdViewFromPtr`, or `CmdWindow` exist — view lowering uses ptr_offset + const + load_info.**

## Tree encoding — what exists and what does not

**Do NOT add new arrays to `MomTreeOut`.** The generic `expr_op/lhs/rhs/aux0/1/2` slots already encode everything the parser emits. There are NO `view_tag`, `view_start`, `view_len`, `view_stride`, `place_tag`, `place_*`, or `index_base_*` arrays.

Each expression is stored via `np_add_expr(out, tag, tok, a, b, c, d)` in `native_core.mlua`. The `expr_*` arrays in `MomTreeOut` (`native_tree.mlua:252-259`) map as:

```
expr_tag[i] = tag (EX_* constant)
expr_tok[i] = tok (token index)
expr_op[i]  = a   (semantic payload varies by tag)
expr_lhs[i] = b   (semantic payload varies by tag)
expr_rhs[i] = c   (semantic payload varies by tag)
expr_aux0[i]= d   (semantic payload varies by tag)
expr_aux1[i]= 0   (always 0 — reserved)
expr_aux2[i]= 0   (always 0 — reserved)
```

### Expression tag encoding table

| Tag | Constant | `expr_op` | `expr_lhs` | `expr_rhs` | `expr_aux0` | Source ref |
|-----|----------|-----------|------------|------------|-------------|------------|
| EX_REF | 2 | token index | 0 | 0 | 0 | `native_core.mlua:491` |
| EX_DOT | 10 | base expr idx | name token idx | 0 | 0 | `native_core.mlua:561` |
| EX_INDEX | 11 | base expr idx | index expr idx | 0 | 0 | `native_core.mlua:555` |
| EX_DEREF | 12 | TK_STAR | sub expr idx | 0 | 0 | `native_core.mlua:498` |
| EX_ADDR | 13 | TK_AMP | sub expr idx | 0 | 0 | `native_core.mlua:498` |
| EX_LEN | 14 | **never emitted by parser** | — | — | — | defined at `native_core.mlua:120` only |
| EX_VIEW | 15 | **never emitted by parser** | — | — | — | defined at `native_core.mlua:121` only |

### Statement tag encoding for ST_SET

ST_SET (3) uses `np_add_stmt(out, ST_SET, tok, e, v, 0, 0, 0)` at `native_core.mlua:672`.
The `stmt_*` arrays map as:
```
stmt_tag[i]           = ST_SET (3)
stmt_name[i] (= a)    = target place expression index (the expression chain to assign to)
stmt_type[i] (= b)    = 0
stmt_value[i] (= c)   = source value expression index
stmt_body_start[i] (= d) = 0
stmt_body_count[i] (= e) = 0
stmt_aux[i]           = 0
```

### Place encoding

There are NO `place_tag`/`place_*` arrays. A "place" is a chain of expression nodes:
- `PlaceRef` → `EX_REF` (expr_tok = name token, lookup in env)
- `PlaceDeref` → `EX_DEREF` (expr_lhs = sub expr, lower to pointer)
- `PlaceIndex` → `EX_INDEX` (expr_op = base, expr_lhs = index expr)
- `PlaceField` → `EX_DOT` (expr_op = base expr, expr_lhs = field name token)

So `mb_place_addr_to_back` receives a `place_idx` which is an expression index. It dispatches on `expr_tag[place_idx]` and follows the encoding above.

### Typecheck outputs consumed by step 6

From `MomBackLowerCtx` (see `lower_ctx.mlua`):
```
ctx.expr_type[idx]   — type index for expression idx (set by typecheck)
ctx.expr_scalar[idx] — back scalar tag for expression idx (set by typecheck)
ctx.tree.type_tag[ty_idx]   — type tag (MT_SCALAR=1, MT_PTR=3, MT_VIEW=4, etc.)
ctx.tree.type_scalar[ty_idx] — scalar sub-tag for MT_SCALAR types
ctx.tree.type_elem[ty_idx]   — element type index for ptr(T) or view(T)
```

## Wire format for memory commands (for the Rust decoder side)

From `BACK_WIRE_FORMAT.md` and `back_command_binary.lua`:

- **Address base**: 0=BackAddrValue(value_id), 1=BackAddrStack(slot_id), 2=BackAddrData(data_id)
- **MemoryInfo**: 8-tuple encoded as (access_id, align_kind, align_bytes, deref_kind, deref_bytes, trap_kind, motion_kind, mode_kind)
  - access_id: 0=Read, 1=Write, 2=ReadWrite
  - align_kind: 0=Known, 1=Unknown
  - align_bytes: alignment in bytes
  - deref_kind: 0=Default, 1=NoDeref
  - deref_bytes: 0 for default
  - trap_kind: 0=NoTrap, 1=TrapOnZero, 2=TrapOnNull
  - motion_kind: 0=NonVolatile, 1=Volatile
  - mode_kind: 0=Normal, 1=Ordered

**Default memory info for scalar loads/stores**: (0=Read, 0=Known, 4, 0=Default, 4, 0=NoTrap, 0=NonVolatile, 0=Normal) for reads. For writes: access=1=Write.

- **CmdLoadInfo** slot layout: dst, shape_tag, scalar, lanes, addr_base_tag, addr_base_id, byte_offset_lo, byte_offset_hi, align_kind, align_bytes, deref_kind, deref_bytes, trap_kind, motion_kind, mode_kind, misc_flags
- **CmdStoreInfo** slot layout: shape_tag, scalar, lanes, addr_base_tag, addr_base_id, byte_offset_lo, byte_offset_hi, store_value, align_kind, align_bytes, deref_kind, deref_bytes, trap_kind, motion_kind, mode_kind, misc_flags
- **CmdPtrOffset** slot layout: dst, base_tag, base_id, index, elem_size, offset_lo, offset_hi
  - Computes: `base + index * elem_size + offset`. When stride != elem_size (for view indexing), pre-multiply index by stride before calling mb_emit_ptr_offset with elem_size=1.

## Entrypoints

```moonlift
mb_view_to_back(ctx: ptr(MomBackLowerCtx), view_idx: i32)
  -> data: i32, len: i32, stride: i32, elem_scalar: i32, ok: bool

mb_index_addr_to_back(ctx: ptr(MomBackLowerCtx), base_idx: i32, index_expr: i32, elem_type: i32)
  -> addr: i32, elem_scalar: i32, ok: bool

mb_place_addr_to_back(ctx: ptr(MomBackLowerCtx), place_idx: i32)
  -> addr: i32, pointee_scalar: i32, ok: bool

mb_place_store_to_back(ctx: ptr(MomBackLowerCtx), place_idx: i32, value_expr: i32)
  -> flow: i32, ok: bool

mb_memory_info(access, align_kind, align_bytes, deref_kind, deref_bytes, trap_kind, motion_kind, mode_kind)
  -> packed memory info (used by load/store emit helpers)

mb_address_from_ptr(ptr_value)
  -> (base_tag=0, base_id=ptr_value) for use in load/store
```

## View lowering

`mb_view_to_back` dispatches on `expr_tag[view_idx]`. Since EX_VIEW (15) is **never emitted by the parser**, this function always returns `ok=false`. Implement the dispatch structure but all cases return unsupported.

- **EX_VIEW**: unreachable (parser never emits it). Return `ok=false`.
  When the parser later emits EX_VIEW, the encoding will be:
  `expr_op = view_variant_tag`, `expr_lhs = base_expr_idx`, `expr_rhs = len_expr_idx`, `expr_aux0 = stride_expr_idx`
  For now do NOT implement actual view lowering — return ok=false.

The `mb_lower_expr_as_view` region in `expr_lower.mlua` already dispatches `mb_expr_view` for EX_VIEW and returns ok=false for all other tags. This is correct — no changes needed for view protocol.

## Address lowering

`mb_place_addr_to_back` gets an expression index (`place_idx`). It dispatches on `ctx.tree.expr_tag[place_idx]`:

### PlaceRef (expr_tag == EX_REF, i.e. value 2)

```
let name_tok = ctx.tree.expr_tok[place_idx]
let kind, scalar, val, aux0 = mb_env_lookup_into(ctx.env, name_tok, ...)
```

- `kind == MB_LOCAL_STACK` — a stack-allocated var. Emit `mb_emit_stack_addr(ctx, dst, aux0)` where aux0 = slot id. Return (dst, scalar, ok=true).
- `kind == MB_LOCAL_SCALAR` — a value-backed local (not addressable). Return ok=false.
- Not found in env — could be global. Return ok=false (global data addresses in step 9).

### PlaceDeref (expr_tag == EX_DEREF, i.e. value 12)

```
let child_idx = ctx.tree.expr_lhs[place_idx]
```

Lower child via `mb_lower_expr_region(ctx, child_idx, ...)`. The child should produce a pointer value. Return (child_val, pointee_scalar, ok=true). The pointee scalar comes from `ctx.expr_scalar[place_idx]`.

### PlaceIndex (expr_tag == EX_INDEX, i.e. value 11)

```
let base_idx = ctx.tree.expr_op[place_idx]
let idx_expr = ctx.tree.expr_lhs[place_idx]
```

Two sub-cases based on what `base_idx` points to:

- **Base is EX_REF**: the indexed thing is a simple local. Look up in env. If it's a view local (MB_LOCAL_VIEW), this is IndexBaseView. Lower the index expression, multiply by stride (from env lookup aux0 for len, stride stored... actually view locals store len in aux0). For now: return ok=false for view indexing (parser doesn't emit EX_VIEW yet).

- **Base is EX_DEREF**: the indexed thing is a pointer deref (IndexBaseExpr). Lower the base as a place to get a pointer address, then lower index, multiply by elem_size, emit `mb_emit_ptr_offset`. Implementation:
  ```
  let base_addr, base_scalar, addr_ok = mb_place_addr_to_back(ctx, base_idx)
  if !addr_ok: return ok=false
  let idx_val, idx_scalar, idx_ok = mb_lower_expr_region(ctx, idx_expr, ...)
  if !idx_ok: return ok=false
  let elem_size = scalar_size(scalar_from_type(elem_type))  -- 4 for i32, etc.
  let off = ctx_fresh_value()
  emit mb_emit_int_binary(ctx, off, BackIntMul, BackIndex, wrap, idx_val, const_index)
  let dst = ctx_fresh_value()
  emit mb_emit_ptr_offset(ctx, dst, 0, base_addr, off, 1, 0, 0)
  ```

- **Base is EX_INDEX or EX_DOT**: recuse: lower base first to get address, then compute scaled offset. (Recursive walk.)

**For initial implementation**: handle PlaceDeref and PlaceIndex (base=EX_DEREF). Return ok=false for all other place shapes.

### PlaceField (expr_tag == EX_DOT, i.e. value 10)

```
let base_idx = ctx.tree.expr_op[place_idx]
let field_name_tok = ctx.tree.expr_lhs[place_idx]
```

Lower base as place. After typecheck, fields with resolved offsets are stored as EX_DOT with the field name token. To get the offset, you'd need layout phase. For now: return ok=false (field offset resolution deferred).

## Expr lowering dispatch updates

### Add to `expr_lower.mlua`'s main dispatch (around line 389):

```moonlift
case @{T.EX_DOT} then emit mb_expr_dot(ctx, idx; done = out)
case @{T.EX_INDEX} then emit mb_expr_index(ctx, idx; done = out)
case @{T.EX_ADDR} then emit mb_expr_addr_of(ctx, idx; done = out)
```

### New regions in `expr_lower.mlua` (delegate to address.mlua):

```moonlift
local mb_expr_addr_of = region(ctx, idx; done)
entry start()
    let child_idx = ctx.tree.expr_lhs[idx]
    let addr, scalar, ok
    emit mb_place_addr_to_back(ctx, child_idx, addr, scalar, ok)
    jump done(value = addr, scalar = scalar, ok = ok)
end
end

local mb_expr_dot = region(ctx, idx; done)
entry start()
    -- Dot expressions need field offset resolution (layout phase).
    -- For initial scalar-only subset, return ok=false.
    jump done(value = 0, scalar = 0, ok = false)
end
end

local mb_expr_index = region(ctx, idx; done)
entry start()
    let base_idx = ctx.tree.expr_op[idx]
    let idx_expr = ctx.tree.expr_lhs[idx]
    let elem_type = ctx.expr_type[idx]  -- the result type (element type)
    let addr, elem_scalar, ok
    emit mb_index_addr_to_back(ctx, base_idx, idx_expr, elem_type, addr, elem_scalar, ok)
    if ok == false then jump done(value = 0, scalar = 0, ok = false) end
    -- Load from the computed address
    let dst = mb_ctx_fresh_value(ctx)
    mb_emit_load_info(ctx, dst, 0, elem_scalar, 0, 0, addr, 0, 0, 0, 0, 0, 0, 0, 0, 1)
    jump done(value = dst, scalar = elem_scalar, ok = true)
end
end
```

## Stmt lowering dispatch update

### Update `stmt_lower.mlua`'s ST_SET case (around line 119):

Replace the current `ok=false` with delegation to `mb_place_store_to_back`:

```moonlift
case @{T.ST_SET} then
    let place_idx = stmt_a       -- ctx.tree.stmt_name[idx]
    let value_idx = stmt_c       -- ctx.tree.stmt_value[idx]
    local flow: i32; local store_ok: bool
    emit mb_place_store_to_back(ctx, place_idx, value_idx, flow, store_ok)
    if store_ok == false then jump done(flow = @{BackFallsThrough}, ok = false) end
    jump done(flow = flow, ok = true)
```

Note reading ST_SET fields correctly: `stmt_a` is the value of `ctx.tree.stmt_name[idx]` (= place expression index). `stmt_c` is `ctx.tree.stmt_value[idx]` (= value expression index). The existing `stmt_lower.mlua` dispatch pattern assigns `stmt_a = ctx.tree.stmt_name[idx]`, `stmt_c = ctx.tree.stmt_value[idx]`. The current code at line 120 uses `stmt_a` for the place reference, which is correct.

## Store lowering

`mb_place_store_to_back(ctx, place_idx, value_expr_idx)`:

1. `mb_place_addr_to_back(ctx, place_idx)` → (addr, pointee_scalar, addr_ok). If not ok, return ok=false.
2. `mb_lower_expr_region(ctx, value_expr_idx)` → (val, val_scalar, val_ok). If not ok, return ok=false.
3. `mb_emit_store_info(ctx, 0, pointee_scalar, 0, 0, addr, 0, val, 0, 0, 0, 0, 0, 0, 0, 2)` — default memory info with write access.
   - shape_tag=0 (scalar), scalar=pointee_scalar, lanes=0
   - addr_base_tag=0 (BackAddrValue), addr_base_id=addr, byte_offset=0
   - store_value=val
   - Default memory info fields (align_kind=0/known, align_bytes=0/default, etc.)
   - misc_flags=2 (write access)
4. Return (BackFallsThrough, ok=true).

**Local cell SSA rebind**: if the place is an EX_REF and env lookup returns MB_LOCAL_SCALAR (value-backed), do NOT emit a store. Instead `mb_env_bind_scalar(ctx.env, name_tok, new_val, scalar)` to create a new SSA value. Return (BackFallsThrough, ok=true).

## Memory info helpers

```moonlift
-- Build default read memory info flags.
mb_memory_info_read() -> i32
    return 0  -- Read, Known align, 4 bytes, Default deref, 4 bytes, NoTrap, NonVolatile, Normal

-- Build default write memory info flags.
mb_memory_info_write() -> i32
    return 2  -- Write access
```

These are simple helper funcs (not regions) that return the memory info value used by `mb_emit_load_info`/`mb_emit_store_info` in their respective slots.

## What to wire where

| New function | Lives in | Called from |
|---|---|---|
| `mb_place_addr_to_back` | `address.mlua` | `mb_place_store_to_back`, `mb_expr_addr_of` |
| `mb_place_store_to_back` | `address.mlua` | ST_SET in `stmt_lower.mlua` |
| `mb_index_addr_to_back` | `address.mlua` | `mb_expr_index` in `expr_lower.mlua` |
| `mb_view_to_back` | `address.mlua` | (future, always returns ok=false now) |
| `mb_memory_info_read` | `address.mlua` | callers of load/store |
| `mb_memory_info_write` | `address.mlua` | callers of store |
| `mb_expr_dot` | `expr_lower.mlua` | dispatcher in `mb_lower_expr_region` |
| `mb_expr_index` | `expr_lower.mlua` | dispatcher in `mb_lower_expr_region` |
| `mb_expr_addr_of` | `expr_lower.mlua` | dispatcher in `mb_lower_expr_region` |

## Existing helpers available in `cmd.mlua`

All needed helpers exist (verified):
- `mb_emit_const(ctx, dst, scalar, lit_tag, lit_lo, lit_hi)` — line 543
- `mb_emit_stack_addr(ctx, dst, slot)` — line 555
- `mb_emit_ptr_offset(ctx, dst, base_tag, base_id, index, elem_size, offset_lo, offset_hi)` — line 641
- `mb_emit_load_info(ctx, dst, shape_tag, scalar, lanes, addr_base_tag, addr_base_id, ...)` — line 649
- `mb_emit_store_info(ctx, shape_tag, scalar, lanes, addr_base_tag, addr_base_id, ...)` — line 657
- `mb_emit_int_binary(ctx, dst, op, scalar, overflow, exact, lhs, rhs)` — line 587
- `mb_emit_compare(ctx, dst, op, shape_tag, scalar, lanes, lhs, rhs)` — line 617
- `mb_emit_select(ctx, dst, shape_tag, scalar, lanes, cond, then_val, else_val)` — line 629

## Expr dispatch update pattern

In `expr_lower.mlua`, the main dispatcher `mb_lower_expr_region` handles these cases. Add three new case entries in the `switch` block (around line 389). Import the new regions from the M table.

```moonlift
-- In imports section (around line 30-40):
local mb_place_addr_to_back = M.mb_place_addr_to_back
local mb_index_addr_to_back = M.mb_index_addr_to_back

-- New regions before the main dispatcher:
local mb_expr_addr_of = ...
local mb_expr_dot = ...
local mb_expr_index = ...

-- In the switch block, add:
case @{T.EX_DOT} then emit mb_expr_dot(ctx, idx; done = out)
case @{T.EX_INDEX} then emit mb_expr_index(ctx, idx; done = out)
case @{T.EX_ADDR} then emit mb_expr_addr_of(ctx, idx; done = out)
```

## Stmt dispatch update pattern

In `stmt_lower.mlua`, the ST_SET case currently returns ok=false. Replace with delegation:

```moonlift
-- In imports section:
local mb_place_store_to_back = M.mb_place_store_to_back

-- In the ST_SET case:
case @{T.ST_SET} then
    let place_idx: i32 = stmt_a
    let value_idx: i32 = stmt_c
    local flow: i32; local store_ok: bool
    emit mb_place_store_to_back(ctx, place_idx, value_idx, flow, store_ok)
    if store_ok == false then jump done(flow = @{BackFallsThrough}, ok = false) end
    jump done(flow = flow, ok = true)
```

## Hard bans

- No raw command packing — use `mb_emit_ptr_offset`, `mb_emit_stack_addr`, `mb_emit_load_info`, `mb_emit_store_info`, `mb_emit_compare`, `mb_emit_select`, `mb_emit_const`, `mb_emit_int_binary`
- No `LowerState` — only `MomBackLowerCtx`
- No `CmdTrap` fallbacks
- No `TODO`/`FIXME`/`placeholder`/`simplified`
- No invented tree arrays — use only existing `expr_*` fields
- No `mb_emit_view` — does not exist, do not add it
