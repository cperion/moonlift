# Step 2: mb_emit_* append helpers

Add `mb_emit_*` append helpers to `lua/moonlift/mom/back/cmd.mlua`.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every helper complete.**



## Pattern

Each helper combines CmdEntry construction with MomCmdBuffer push:

```
mb_emit_<name>(ctx: ptr(MomBackLowerCtx), <args...>) -> void
```

Body:
1. Declare local `entry: CmdEntry` (stack-allocated)
2. Call the existing `mb_cmd_<name>` constructor with `&entry` + args
3. Call `mr_cmd_buffer_push(ctx.cmd_buffer, entry.tag, entry.w0, entry.w1, entry.w2, entry.w3, entry.w4, entry.w5)`
4. No return value (or return push index if caller needs it)

First 6 data slots (w0-w5) go directly into `mr_cmd_buffer_push`. Commands with more than 6 data slots push extras to `ctx.aux_i32` before the main push.

## Helpers required (from port_map section 7 lines 512-518)

### Structural
```
mb_emit_create_sig(ctx, sig, params_aux, n_params, results_aux, n_results)
mb_emit_declare_func(ctx, visibility, func_id, sig)
mb_emit_declare_extern(ctx, extern_id, symbol, sig)
mb_emit_begin_func(ctx, func_id)
mb_emit_create_block(ctx, blk)
mb_emit_switch_to_block(ctx, blk)
mb_emit_seal_block(ctx, blk)
mb_emit_bind_entry_params(ctx, blk, vals_aux, n_vals)
mb_emit_append_block_param(ctx, blk, value, shape_tag, scalar, lanes)
mb_emit_finish_func(ctx, func_id)
mb_emit_finalize_module(ctx)
```

### Value
```
mb_emit_const(ctx, dst, scalar, lit_tag, lit_lo, lit_hi)
mb_emit_alias(ctx, dst, src)
mb_emit_stack_addr(ctx, dst, slot)
mb_emit_data_addr(ctx, dst, data)
mb_emit_func_addr(ctx, dst, func_id)
mb_emit_extern_addr(ctx, dst, extern_id)
mb_emit_ptr_offset(ctx, dst, base_tag, base_id, index, elem_size, offset_lo, offset_hi)
```

### Unary / binary / compare / cast / select / call
```
mb_emit_unary(ctx, dst, op, shape_tag, scalar, lanes, value)
mb_emit_binary(ctx, dst, op, scalar, overflow, exact, lhs, rhs)
mb_emit_compare(ctx, dst, op, shape_tag, scalar, lanes, lhs, rhs)
mb_emit_cast(ctx, dst, op, scalar, value)
mb_emit_select(ctx, dst, shape_tag, scalar, lanes, cond, then_val, else_val)
mb_emit_call(ctx, result_tag, result_dst, result_scalar, target_tag, target_id, sig, args_aux, count)
```

Note: `mb_emit_binary` maps to CmdIntBinary (wraps mb_cmd_int_binary). `mb_emit_const` maps to CmdConst.

### Memory / atomic
```
mb_emit_load_info(ctx, dst, shape_tag, scalar, lanes, base_tag, base_id, byte_offset, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k)
mb_emit_store_info(ctx, shape_tag, scalar, lanes, base_tag, base_id, byte_offset, value, access, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k)
mb_emit_atomic_load(ctx, ...)    -- stub
mb_emit_atomic_store(ctx, ...)   -- stub
mb_emit_atomic_rmw(ctx, ...)     -- stub  
mb_emit_atomic_cas(ctx, ...)     -- stub
mb_emit_atomic_fence(ctx, ...)   -- stub
```

For LoadInfo/StoreInfo (15/14 slots), push w6+ to `ctx.aux_i32` via `mr_i32_builder_push` before the main `mr_cmd_buffer_push`. For atomic stubs, create the helper with a comment noting atomic not yet in hosted lowering.

### Control flow
```
mb_emit_jump(ctx, dest, args_aux, count)
mb_emit_br_if(ctx, cond, then_block, then_aux, then_count, else_block, else_aux, else_count)
mb_emit_switch_int(ctx, value, scalar, cases_aux, n_cases, default_blk)
mb_emit_return_void(ctx)
mb_emit_return_value(ctx, value)
```

### Vector (stubs — vec pipeline not connected yet)
```
mb_emit_vec_splat(ctx, ...)
mb_emit_vec_binary(ctx, ...)
mb_emit_vec_compare(ctx, ...)
mb_emit_vec_select(ctx, ...)
mb_emit_vec_mask(ctx, ...)
mb_emit_vec_load_info(ctx, ...)
mb_emit_vec_store_info(ctx, ...)
```

## Exports

All helpers must be exported on `M`:
```
M.mb_emit_create_sig = mb_emit_create_sig
M.mb_emit_declare_func = mb_emit_declare_func
...
```

## Naming

Must exactly match the names listed above (from port_map). No deviations.

## Hard bans

- No `TODO`/`FIXME`/`placeholder`/`not-yet`
- No `CmdTrap` usage
- Each helper must call the existing `mb_cmd_*` constructor — no hand-packing slots
- No `@malloc` or hidden allocation
- Commands go to `ctx.cmd_buffer`, never to a raw array
