# Step 3: Expression lowering rewrite

Replace `lua/moonlift/mom/back/expr_lower.mlua` with a clean implementation that uses `MomBackLowerCtx` and `mb_emit_*` helpers.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every case complete.**



## Pattern

```moonlift
return function(M)
  local i32p = moon.ptr(moon.i32)
  -- import helpers from other modules
  -- define dispatch region + per-case regions
  -- exports on M
  return M
end
```

## Imports

All op/type helpers come from `back/ops.mlua`:
- `mb_core_scalar_to_back`, `mb_type_to_back_scalar`
- `mb_semantic_cast_op`, `mb_lower_surface_cast_op`
- `mb_lower_unary_op`, `mb_binary_class`, `mb_binary_op_code`
- `mb_lower_compare_op`

All command emission through `mb_emit_*` from `back/cmd.mlua`.

## Entrypoints (from port_map section 9 lines 625-628)

```moonlift
mb_lower_expr(ctx: ptr(MomBackLowerCtx), expr_idx: i32)
  -> value: i32, scalar: i32, ok: bool  (via ExprResult protocol)

mb_lower_expr_as_view(ctx: ptr(MomBackLowerCtx), expr_idx: i32)
  -> data: i32, len: i32, stride: i32, elem_scalar: i32, ok: bool  (via ViewResult protocol)

mb_lower_call_args(ctx: ptr(MomBackLowerCtx), list_start: index, list_count: index)
  -> aux: i32, count: i32, ok: bool
```

Dispatch on `tree.expr_tag[expr_idx]` (the expression variant tag from the materialized tree).

## Cases (from port_map section 9 lines 631-679, hosted oracle tree_to_back.lua expr_to_back)

### EX_LIT (ExprLit)
Check `tree.expr_subtag[idx]`:
- `LitString`: Declare data, init bytes + trailing null, emit data address. Return value=address, scalar=BackPtr.
- `LitBool`: `mb_ctx_fresh_value(ctx)`, `mb_emit_const(ctx, dst, BackBool, BackLitBool(bool_val), 0, 0)`. Return (value, BackBool, ok=true).
- `LitInt`: `mb_ctx_fresh_value(ctx)`, `mb_emit_const(ctx, dst, scalar, BackLitInt(raw), lit_lo, lit_hi)`. Return (value, scalar, ok=true).
- `LitFloat`: `mb_ctx_fresh_value(ctx)`, `mb_emit_const(ctx, dst, scalar, BackLitFloat(raw), lit_lo, lit_hi)`. Return (value, scalar, ok=true).
- `LitNil`: `mb_ctx_fresh_value(ctx)`, `mb_emit_const(ctx, dst, BackVoid, BackLitNull, 0, 0)`. Return (value, BackVoid, ok=true).
- Non-scalar (struct/array literal): unsupported.
- Edge: `back_scalar(expr_ty)` returns nil → unsupported.

### EX_REF (ExprRef)
Check `tree.expr_a[idx]` (ValueRef variant):
- `ValueRefBinding`: `mb_env_lookup_into(ctx.env, binding_key, kind_out, value_out, scalar_out)`. If `TreeBackScalarLocal` → return directly. If `TreeBackStackLocal` → `mb_ctx_fresh_value(ctx)`, `mb_emit_stack_addr(ctx, dst, slot)`, `mb_emit_load_info(ctx, dst, shape, scalar, base, 0, ...)`, return value.
- `BindingClassGlobalConst`: const_value_for + `mb_emit_const`. Unsupported if not compile-time.
- `BindingClassGlobalStatic`: load_global_data + `mb_emit_data_addr`.
- `BindingClassGlobalFunc`: `mb_ctx_fresh_value(ctx)`, `mb_emit_func_addr(ctx, dst, func_id)`.
- `BindingClassExtern`: `mb_ctx_fresh_value(ctx)`, `mb_emit_extern_addr(ctx, dst, extern_id)`.
- `ValueRefConstSlot`/`ValueRefStaticSlot`: slot_consts/slot_statics lookup → data address.
- `ValueRefFuncSlot`: `mb_emit_func_addr`.
- else: unsupported.

### EX_UNARY (ExprUnary)
- `mb_lower_expr(ctx, child)` → (child_val, child_scalar, ok).
- `mb_ctx_fresh_value(ctx)` → dst.
- `mb_lower_unary_op(op_tag, child_scalar)` → back_unary_op.
- `mb_emit_unary(ctx, dst, back_unary_op, 0 (shape_scalar), child_scalar, 0 (lanes), child_val)`.
- Edge: `UnNeg` → BackUnaryIneg if int, BackUnaryFneg if float. `UnNot` → BackUnaryBoolNot. `UnBNot` → BackUnaryBnot.
- Return (dst, child_scalar, ok=true).

### EX_BINARY (ExprBinary)
- `mb_lower_expr(ctx, lhs)` → (lhs_val, lhs_scalar, ok1). If fail → unsupported.
- `mb_lower_expr(ctx, rhs)` → (rhs_val, rhs_scalar, ok2).
- Check `BinAdd`/`BinSub` with `BackPtr` pointer arithmetic: index cast, optional Ineg, `mb_emit_ptr_offset`.
- Non-ptr: `mb_binary_class(op, scalar)` → determines command family (IntBinary/FloatBinary/BitBinary/Shift). `mb_ctx_fresh_value(ctx)` → dst.
  - Int: `mb_emit_int_binary(ctx, dst, op, scalar, BackIntWrap, 0, lhs_val, rhs_val)`.
  - Float: `mb_emit_float_binary(ctx, dst, op, scalar, BackFloatStrict, lhs_val, rhs_val)`.
  - Bit: `mb_emit_bit_binary(ctx, dst, op, scalar, lhs_val, rhs_val)`.
  - Shift: `mb_emit_shift(ctx, dst, op, scalar, lhs_val, rhs_val)`.
- Note: if `mb_emit_binary` is the catch-all helper, it delegates to the family-specific one.
- Return (dst, scalar, ok=true).
- Edge: `BinConcat` → unsupported (hosted embeds str concat).

### EX_COMPARE (ExprCompare)
- `mb_lower_expr(ctx, lhs)` → (lhs_val, lhs_scalar, ok1).
- `mb_lower_expr(ctx, rhs)` → (rhs_val, rhs_scalar, ok2).
- `mb_lower_compare_op(op_tag, lhs_scalar)` → back_compare_op.
- `mb_ctx_fresh_value(ctx)` → dst.
- `mb_emit_compare(ctx, dst, back_compare_op, 0 (shape_scalar), lhs_scalar, 0 (lanes), lhs_val, rhs_val)`.
- Result scalar always `BackBool`.
- Return (dst, BackBool, ok=true).

### EX_CAST (ExprCast, ExprMachineCast)
- `mb_lower_expr(ctx, child)` → (child_val, child_scalar, ok).
- `back_scalar(expr_ty)` → dst_scalar.
- If `machine_cast_op` is identity → return (child_val, dst_scalar, ok=true).
- `mb_ctx_fresh_value(ctx)` → dst.
- `mb_emit_cast(ctx, dst, cast_op, dst_scalar, child_val)`.
- Surface cast: `mb_lower_surface_cast_op(op, src_scalar, dst_scalar)` → machine cast op, then same as machine cast.
- Return (dst, dst_scalar, ok=true).

### EX_LOGIC (ExprLogic)
- `mb_lower_expr(ctx, lhs)` → (lhs_val, lhs_scalar, ok1).
- `mb_lower_expr(ctx, rhs)` → (rhs_val, rhs_scalar, ok2).
- Both sides always lowered eagerly (hosted behavior).
- `LogicAnd`: `mb_emit_const(ctx, false_val, BackBool, BackLitBool(false), 0, 0)`. `mb_emit_select(ctx, dst, 0, BackBool, 0, lhs_val, rhs_val, false_val)`.
- `LogicOr`: `mb_emit_const(ctx, true_val, BackBool, BackLitBool(true), 0, 0)`. `mb_emit_select(ctx, dst, 0, BackBool, 0, lhs_val, true_val, rhs_val)`.
- Return (dst, BackBool, ok=true).

### EX_CALL (ExprCall)
- For each arg: `mb_lower_expr(ctx, arg_i)` → collect values + scalars into aux list via `mb_ctx_push_aux_i32(ctx, value)`.
- `back_scalar(expr_ty)` → result_scalar.
- `call_target` from typecheck (tree.expr_a/b/c/d): `CallDirect(funcId)`, `CallExtern(externId)`, `CallIndirect(value)`, `CallClosure` → unsupported.
- `mb_ctx_fresh_value(ctx)` → dst (if non-void result).
- `mb_emit_call(ctx, result_tag, result_dst, result_scalar, target_tag, target_id, sig, args_aux, count)`.
- Void call: `mb_emit_call(ctx, BackCallVoid, 0, 0, target_tag, target_id, sig, args_aux, count)`, return (0, 0, ok=true).
- Non-void: return (dst, result_scalar, ok=true).
- Edge: non-scalar result → unsupported.

### EX_SELECT (ExprSelect)
- `mb_lower_expr(ctx, cond)` → (cond_val, cond_scalar, ok1).
- `mb_lower_expr(ctx, then_expr)` → (then_val, then_scalar, ok2).
- `mb_lower_expr(ctx, else_expr)` → (else_val, else_scalar, ok3).
- Or use the expr_as protocol with env threading: `then` gets `cond.env`, `else` gets `then.env`.
- `back_scalar(expr_ty)` → result_scalar.
- `mb_emit_select(ctx, dst, 0 (shape_scalar), result_scalar, 0 (lanes), cond_val, then_val, else_val)`.
- Return (dst, result_scalar, ok=true).

### EX_LEN (ExprLen)
- `mb_lower_expr(ctx, value)` → or check for view-local via env.
- If `ExprRef(ValueRefBinding)` → `mb_env_lookup_into` → `TreeBackViewLocal` or `TreeBackStridedViewLocal` → return `(len, BackIndex, ok=true)`.
- If lowered expr is view → return `(len, BackIndex, ok=true)`.
- Else → unsupported.

### EX_DEREF (ExprDeref)
- `mb_lower_expr(ctx, value)` → (ptr_val, ptr_scalar, ok).
- `back_scalar(expr_ty)` → scalar.
- `mb_ctx_fresh_value(ctx)` → dst.
- `mb_emit_load_info(ctx, dst, 0, scalar, 0, ptr_val, 0, access_read, ...)`.
- Return (dst, scalar, ok=true).

### EX_ADDR (ExprAddrOf)
- Delegate to address lowering (stub: `mb_expr_addr_of` → unsupported, return ok=false).

### EX_VIEW (ExprView)
- Delegate to view lowering (stub: `mb_expr_view` → unsupported, return ok=false).

### EX_SWITCH (ExprSwitch)
- `mb_lower_expr(ctx, value)` → (val, scalar, ok).
- `result_scalar = back_scalar(expr_ty)`.
- Create arm blocks + default block + join block.
- `mb_emit_create_block(ctx, join_blk)`, `mb_emit_append_block_param(ctx, join, result_value, 0, result_scalar, 0)`.
- `mb_emit_switch_int(ctx, val, scalar, cases_aux, n_cases, default_blk)`.
- For each arm: `mb_emit_switch_to_block(ctx, arm_blk)` → lower body → `mb_lower_expr(ctx, result)` → `mb_emit_jump(ctx, join_blk, args_aux, count)`.
- Default: same.
- `mb_emit_seal_block(ctx, join_blk)`.
- Return with join block's env counters.

### EX_IF, EX_DOT, EX_HOLE, EX_CONTROL
- All unsupported at this stage (hosted reports unsupported or delegates to control/address lowering).
- Return ok=false.

## Protocol

All returning cases use the ExprResult protocol (value, scalar, ok). The `ok` flag signals whether lowering succeeded. When `ok=false`, the returned value/scalar are undefined.

## Main dispatch

```moonlift
mb_lower_expr(ctx, expr_idx)
  let tag = tree.expr_tag[idx]
  switch tag ...
  end
  return (0, 0, false)  -- unsupported fallback
```

Each case is a separate region or func. The dispatch region uses switch on the tag.

## Hard bans

- No raw command packing (`mb_push_cmd`, `mb_push_cmd_w10`, `mb_push_cmd_w15`, direct cmds array writes)
- No `LowerState` — use `MomBackLowerCtx` exclusively
- No `CMD_STRIDE` constant — slot layout is `cmd.mlua`'s responsibility
- No `CmdTrap` as fallback marker
- No `TODO`/`FIXME`/`placeholder`
- No op helper duplication — import from `back/ops.mlua`
- Every case must return through the protocol (value, scalar, ok) — not fake values
- Unsupported cases return `ok=false`, not pretend-emitted commands
