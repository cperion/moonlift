# Step 5: Function and module lowering

Create `lua/moonlift/mom/back/func.mlua` and `lua/moonlift/mom/back/module.mlua` for semantic function/module lowering.

Take lowering orchestration out of `compile_module.mlua` (reduce to phase calling) and put semantics in `back/`.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every function complete.**



## func.mlua — Function lowering (port_map section 13 lines 879-900, 907-913)

```moonlift
return function(M)
  -- imports: mb_emit_*, mb_core_scalar_to_back, mb_env_bind_*, mb_fresh_*
  -- function: mb_lower_func
  -- function: mb_lower_extern
  -- function: mb_lower_data_init
  return M
end
```

### mb_lower_func(ctx: ptr(MomBackLowerCtx), item_idx: i32) -> i32 (status)

Algorithm (from port_map lines 891-900):
1. `abi_api.plan(func_name, params, result_ty)` → AbiPlan with param_plan + result_plan.
2. `mb_emit_create_sig(ctx, sig_id, params_aux, n_params, results_aux, n_results)`.
3. `collect_address_taken_stmts(func.body)` → set of binding keys needing stack slots.
4. `mb_emit_declare_func(ctx, visibility, func_id, sig_id)`.
5. `mb_emit_begin_func(ctx, func_id)`.
6. For each param: if `AbiParamScalar` → `mb_env_bind_scalar(ctx.env, binding, value, scalar)`. If `AbiParamView` → `mb_env_bind_strided_view(ctx.env, binding, data, len, stride)`.
7. `mb_lower_stmt_list(ctx, body_start, body_count)` → (flow, ok).
8. If last flow is not `BackTerminates`:
   - Void func → `mb_emit_return_void(ctx)`.
   - Non-void → unsupported (falling off non-void func).
9. `mb_emit_finish_func(ctx, func_id)`.
10. Return status (0=ok, negative=error).

### mb_lower_extern(ctx: ptr(MomBackLowerCtx), item_idx: i32) -> i32 (status)

Algorithm (from port_map lines 901-906):
1. `abi_api.plan(extern_name, params, result_ty)` → AbiPlan.
2. `mb_emit_create_sig(ctx, sig_id, params_aux, n_params, results_aux, n_results)`.
3. `mb_emit_declare_extern(ctx, extern_id, symbol, sig_id)`.
4. If extern has body: same as func lowering (BeginFunc → body → FinishFunc).
5. Return status.

### mb_lower_data_init(ctx: ptr(MomBackLowerCtx), item_idx: i32) -> i32 (status)

Algorithm (from port_map lines 907-913):
1. `back_scalar(ty)` → must be non-nil.
2. `const_eval` → Sem.Const*.
3. `sem_const_literal(value)` → BackLit*.
4. `scalar_size_align(scalar)` → size, align.
5. `mb_emit_declare_data(ctx, data_id, size, align)`.
6. `mb_emit_data_init(ctx, data_id, 0, scalar, lit_tag, lit_lo, lit_hi)`.
7. Return status.

## module.mlua — Module lowering (port_map section 13 lines 879-889, 915-930)

```moonlift
return function(M)
  -- imports: mb_lower_func, mb_lower_extern, mb_lower_data_init from func.mlua
  -- function: mb_collect_module_context
  -- function: mb_lower_module
  return M
end
```

### mb_collect_module_context(ctx: ptr(MomBackLowerCtx)) -> i32 (status)

Algorithm (from port_map lines 924-930):
1. Walk all items in module, classify: func/extern/const/static/type.
2. Collect const items into `ctx` const env.
3. Collect static data ids into global map.
4. Collect slot maps (const/static slot bindings).
5. Collect func bindings by `module_name+item_name → BackFuncId`.
6. Return status.

### mb_lower_module(ctx: ptr(MomBackLowerCtx)) -> i32 (status)

Algorithm (from port_map lines 915-923):
1. `mb_collect_module_context(ctx)`.
2. Module command hoisting order:
   - `mb_emit_target_model(ctx, target_triple, data_layout)` — if needed.
   - `mb_emit_create_sig` for all function/extern signatures (deduplicated).
   - `mb_emit_declare_func` / `mb_emit_declare_extern` for all items.
   - `mb_emit_declare_data` for all const/static items.
   - Function bodies in item order: `mb_lower_func(ctx, item_i)` for each func.
   - `mb_emit_alias_fact(ctx, ...)` for global aliasing info.
   - `mb_emit_finalize_module(ctx)`.
3. Return status.

## Changes to compile_module.mlua

Reduce to orchestration only:
1. Call `mb_collect_module_context(ctx)`.
2. Call `mb_lower_module(ctx)`.
3. Remove all bridge expr/stmt pre-pass functions (mc_bridge_expr_arrays, mc_bridge_stmt_arrays, mc_lower_module_region).
4. Remove LowerState usage — use MomBackLowerCtx exclusively.
5. Wire result: get cmd_buffer contents from ctx.cmd_buffer into wire builder.

## Hard bans

- No LowerState in new files — only MomBackLowerCtx
- No raw command packing
- No duplicate sig creation — sigs are deduplicated by function/extern identity
- No CmdTrap fallbacks
- No TODO/FIXME/placeholder
- compile_module.mlua changes must not break existing wire/validate pipeline
