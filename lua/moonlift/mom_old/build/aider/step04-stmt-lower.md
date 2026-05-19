# Step 4: Statement lowering rewrite

Replace `lua/moonlift/mom/back/stmt_lower.mlua` to use `MomBackLowerCtx` and `mb_emit_*` helpers.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every case complete.**



## Entrypoints (port_map section 11 lines 758-762)

```moonlift
mb_lower_stmt(ctx: ptr(MomBackLowerCtx), stmt_idx: i32)
  -> flow: i32, ok: bool  (via StmtResult protocol)

mb_lower_stmt_list(ctx: ptr(MomBackLowerCtx), list_start: index, list_count: index)
  -> flow: i32, ok: bool

mb_lower_if_stmt(ctx: ptr(MomBackLowerCtx), stmt_idx: i32)
  -> flow: i32, ok: bool

mb_lower_switch_stmt(ctx: ptr(MomBackLowerCtx), stmt_idx: i32)
  -> flow: i32, ok: bool
```

Flow values: 0 = BackFallsThrough, 1 = BackTerminates. Hosted also has BackJumps but outside control regions that's treated as terminating.

## Cases (port_map section 11 lines 764-792)

### ST_LET
`tree.stmt_tag[idx]` dispatch:
- `mb_lower_expr(ctx, init_expr)` → (value, scalar, ok).
- If `is_view_type(init_ty)` → `mb_env_bind_view(ctx.env, binding_key, data_id, len_id)` or `mb_env_bind_strided_view(...)`.
- Else → `mb_env_bind_scalar(ctx.env, binding_key, value, scalar)`.
- Return (BackFallsThrough, ok=true).

### ST_EXPR
- If expr is `ExprCall` and `back_scalar(expr_ty)` returns void/nil → `mb_lower_expr(ctx, expr)` → void call, discard result.
- Else → `mb_lower_expr(ctx, expr)` → discard value.
- Return (BackFallsThrough, ok=true).

### ST_RETURN_VALUE
- If `is_view_type(expr_ty)` → view_to_back (stub for now: unsupported). Store data/len/stride to hidden sret pointer (3× `mb_emit_store_info`). `mb_emit_return_void(ctx)`.
- Else → `mb_lower_expr(ctx, value)` → `mb_emit_return_value(ctx, value)`.
- Return (BackTerminates, ok=true).

### ST_RETURN_VOID
- `mb_emit_return_void(ctx)`.
- Return (BackTerminates, ok=true).

### ST_VAR
- If `binding_is_stack_local(binding)` (address-taken):
  - `mb_ctx_fresh_slot(ctx)` → slot.
  - `mb_emit_create_stack_slot(ctx, slot, size, align)`.
  - `mb_lower_expr(ctx, init)` → (value, scalar, ok).
  - `mb_emit_stack_addr(ctx, addr, slot)`.
  - `mb_emit_store_info(ctx, 0, scalar, 0, addr, 0, value, access_write, ...)`.
  - `mb_env_bind_stack(ctx.env, binding_key, slot, scalar)`.
- Else → same as ST_LET.
- Return (BackFallsThrough, ok=true).

### ST_SET
- Delegate to address/store module: `mb_place_store_to_back(ctx, place_idx, value_expr)`.
- Stub: unsupported, return (BackFallsThrough, ok=false).

### ST_ATOMIC_STORE
- `mb_lower_expr(ctx, addr)` → (addr_val, scalar, ok1).
- `mb_lower_expr(ctx, value)` → (val, val_scalar, ok2).
- `mb_emit_const(ctx, zero, BackIndex, BackLitInt(0), 0, 0)`.
- `mb_emit_atomic_store(ctx, scalar, addr_val, zero, val, memory_info, ordering)`.
- Return (BackFallsThrough, ok=true).

### ST_ATOMIC_FENCE
- `mb_emit_atomic_fence(ctx, back_atomic_ordering(ordering))`.
- Return (BackFallsThrough, ok=true).

### ST_ASSERT
- No backend commands.
- Return (BackFallsThrough, ok=true).

### ST_IF
- `mb_lower_expr(ctx, cond)` → (cond_val, cond_scalar, ok).
- `mb_emit_create_block(ctx, then_blk)`, `mb_emit_create_block(ctx, else_blk)`, `mb_emit_create_block(ctx, join_blk)`.
- `mb_emit_br_if(ctx, cond_val, then_blk, then_aux, then_count, else_blk, else_aux, else_count)`.
- `mb_emit_switch_to_block(ctx, then_blk)` → `mb_lower_stmt_list(ctx, then_body)` → if not terminates → `mb_emit_jump(ctx, join_blk, args_aux, count)`.
- `mb_emit_switch_to_block(ctx, else_blk)` → `mb_lower_stmt_list(ctx, else_body)` → if not terminates → `mb_emit_jump(ctx, join_blk, args_aux, count)`.
- For each changed local cell binding: `mb_emit_append_block_param(ctx, join_blk, value, 0, scalar, 0)` before lowering bodies, and pass args on jump.
- `mb_emit_seal_block(ctx, join_blk)`, `mb_emit_switch_to_block(ctx, join_blk)`.
- Return (BackFallsThrough, ok=true).

### ST_SWITCH
- `mb_lower_expr(ctx, value)` → (val, scalar, ok).
- `switch_key_raw` per arm → raw int/bool keys.
- Create arm blocks + default block + join block.
- `mb_emit_append_block_param(ctx, join, value, 0, scalar, 0)` for each changed cell.
- `mb_emit_switch_int(ctx, val, scalar, cases_aux, n_cases, default_blk)`.
- For each arm: `mb_emit_switch_to_block(ctx, arm_blk)` → lower body → `mb_emit_jump(ctx, join, args)` if not terminates.
- Default: same.
- `mb_emit_seal_block(ctx, join)`.
- Edge: Variant (TaggedUnion) arms → unsupported.
- Return (BackFallsThrough or BackTerminates, ok=true).

### ST_JUMP, ST_JUMPCONT, ST_YIELD*, ST_CONTROL
- All unsupported outside control regions (handled by control lowering).
- `mb_stmt_control_outside_region`: return (BackTerminates, ok=false).

### ST_USEREGIONSLOT, ST_USEREGIONFRAG
- No-op after open expansion. Return (BackFallsThrough, ok=true).

## Flow handling

`lower_stmt_list` iterates stmts in order. After a terminating stmt (BackTerminates), stops. Returns the last flow value.

## Hard bans

- No raw command packing (`mb_stmt_push_cmd`, CMD_STRIDE_STMT)
- No `LowerState` — use `MomBackLowerCtx`
- No `CmdTrap` fallbacks
- No `TODO`/`FIXME`/`placeholder`
- Expression lowering delegated to `mb_lower_expr` (import from expr_lower.mlua), not duplicated
- If/switch phi uses env snapshots and canonical binding keys
