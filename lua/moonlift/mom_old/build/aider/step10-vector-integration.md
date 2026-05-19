# Step 10: Vector integration without fake vectorization

This step removes raw vector command packing and integrates the vector pipeline
as a conservative try/fallback pass. It must never fabricate vector facts or
emit vectorized loops unless legality and plan data are explicitly proven from
control-region structure.

**Prerequisites:** Step 8 control lowering is complete and Step 9 command tape
width/`mb_emit_vec_*` helpers are correct. If either prerequisite is missing,
this step must stop after making vec modules compile-safe and scalar-fallback
only.

**Policy: hard rewrite for touched vec files. No raw command packing, no
`LowerState`, no `CmdTrap` fallback, no hidden allocation, no fake vector facts,
no fake vector plans. Vector failure must always fall back to scalar lowering.**

## Required source-of-truth checks

Read before editing:

- `lua/moonlift/vec_kernel_plan.lua`
- `lua/moonlift/vec_kernel_to_back.lua`
- vector-related sections in `lua/moonlift/tree_to_back.lua`
- `BACK_WIRE_FORMAT.md` vector command slots
- `lua/moonlift/mom/vec/*.mlua` current skeletons
- `lua/moonlift/mom/back/control_lower.mlua`
- `lua/moonlift/mom/back/cmd.mlua`
- `lua/moonlift/mom/back/func.mlua`

## What exists and what does not

There are no vector-specific parsed AST arrays in `MomTreeOut`:

- no `vec_op`
- no `vec_lanes`
- no vector expression tags from source syntax
- no vector statement tags from source syntax

Vectorization is a compiler optimization over already typechecked control
regions. It must inspect `ctrl_block_*`, `stmt_list`, expression trees, and
backend scalar/type facts.

## Required command helpers

Before touching vec lowering, verify these helpers exist and push full-width
command entries:

```
mb_emit_vec_splat(ctx, dst, elem_scalar, lanes, scalar_val)
mb_emit_vec_binary(ctx, dst, op, elem_scalar, lanes, lhs, rhs)
mb_emit_vec_compare(ctx, dst, op, elem_scalar, lanes, lhs, rhs)
mb_emit_vec_select(ctx, dst, elem_scalar, lanes, cond, then_val, else_val)
mb_emit_vec_mask(ctx, dst, op, mask, ...)
mb_emit_vec_load_info(ctx, dst, elem_scalar, lanes, base_tag, base_id, byte_offset, ...)
mb_emit_vec_store_info(ctx, elem_scalar, lanes, base_tag, base_id, byte_offset, value, ...)
```

If these helpers are missing or are empty stubs, implement/fix them in
`back/cmd.mlua` first. Do not call `mv_push_cmd` or write command slots by hand.

## Aux layout discipline

Use `ctx.aux_i32` for facts/plans. Every aux segment must start with a header:

```
aux[start + 0] = segment_tag
aux[start + 1] = entry_count
aux[start + 2] = entry_stride
aux[start + 3] = first_entry_word...
```

Do not rely on global implicit offsets. Return the segment start from each
phase.

Suggested segment tags local to vec modules:

```
MV_SEG_FACTS = 1
MV_SEG_DECISION = 2
MV_SEG_PLAN = 3
```

Fact entry stride is 6 words:

```
[fact_tag, a, b, c, d, e]
```

Plan entry stride is 8 words:

```
[plan_tag, elem_scalar, lanes, trip_count_val, iv_init_val, iv_step_val, body_block_idx, flags]
```

## New/rewritten vec entrypoints

### `vec_facts.mlua`

Export:

```moonlift
mv_extract_vec_facts(ctx: ptr(MomBackLowerCtx), item_idx: i32)
  -> facts_aux: i32, fact_count: i32, ok: bool
```

Algorithm:

1. Find the function body's control region.
   - If no body control region: create an empty facts segment and return
     `(facts_aux, 0, true)`.
2. Determine `ctrl_start` and `n_blocks` from item/body metadata. Do not guess
   across unrelated control regions.
3. Find backedges:
   - scan each control block body for `MS_JUMP`
   - resolve target label by linear scan
   - a target block index `<= current block index` is a potential backedge
4. If no backedge: return zero facts, `ok=true`.
5. Extract only facts that can be proven exactly:
   - one primary induction variable from a block param that is updated by a
     backedge arg of form `iv + constant_step`
   - counted domain from compare/yield guard if recognizable
   - contiguous memory load/store only when address expression is an indexed
     pointer/view with invariant base and induction index
   - reduction only when accumulator block param is updated as `acc + value`
6. If a pattern is not recognized, do not reject the program; return fewer facts
   or a `VF_REJECT` fact. Vector try will fall back to scalar.

Do not use Lua tables. Use linear scans and `ctx.aux_i32`.

### `vec_decide.mlua`

Export:

```moonlift
mv_decide(ctx: ptr(MomBackLowerCtx), facts_aux: i32, fact_count: i32)
  -> decision_aux: i32, decision_tag: i32, elem_scalar: i32, lanes: i32, ok: bool
```

Algorithm:

1. If `fact_count == 0`, return `VD_ILLEGAL`, `ok=true`.
2. Reject if any `VF_REJECT` fact exists.
3. Require exactly one primary induction fact.
4. Require a counted domain/trip count fact.
5. Determine element scalar from memory/reduction facts.
6. Compute lanes from 128-bit vector width:
   - lanes = `128 / scalar_bits(elem_scalar)`
   - reject if scalar bits are 0 or lanes < 2
7. Reject calls, unknown statements, non-contiguous memory, unsupported scalar ops.
8. Write a decision segment and return `VD_LEGAL` only if every required check
   succeeds.

### `vec_plan.mlua`

Export:

```moonlift
mv_plan_kernel(ctx: ptr(MomBackLowerCtx), facts_aux: i32, fact_count: i32,
               decision_aux: i32, decision_tag: i32, elem_scalar: i32, lanes: i32)
  -> plan_aux: i32, plan_count: i32, ok: bool
```

Algorithm:

1. If decision is not `VD_LEGAL`, return `(plan_aux, 0, true)`.
2. Classify plan:
   - reduction facts -> `VP_REDUCE`
   - memory map with elementwise operations -> `VP_MAP`
   - otherwise `VP_NO_PLAN`
3. Do not invent algebraic plans unless hosted oracle has an exact matching rule.
4. Write one plan entry only when lowering has enough operands/block ids to emit
   a correct vector loop. Otherwise return no plan and scalar fallback.

### `vec_lower.mlua`

Export:

```moonlift
mv_lower_kernel(ctx: ptr(MomBackLowerCtx), plan_aux: i32, plan_count: i32)
  -> status: i32
```

Rules:

- If `plan_count == 0`, return nonzero scalar-fallback status.
- Use only `mb_emit_*` helpers.
- Do not call `mv_push_cmd`.
- Do not write command arrays directly.
- Every vector op must specify `elem_scalar` and `lanes`.
- Remainder handling is mandatory for any emitted vector loop. If remainder
  lowering is not implemented for the plan, return scalar-fallback status
  before emitting partial vector CFG.

Lowering outline for a legal complete plan:

1. Create vector loop blocks with `mb_ctx_fresh_block` and `mb_emit_create_block`.
2. Append/bind loop block params for induction/reduction values.
3. Compute vector trip count = `trip_count - (trip_count % lanes)`.
4. Emit loop compare and `mb_emit_br_if`.
5. Emit vector loads/ops/stores/reduction using vector helpers.
6. Jump back with updated IV/reduction params.
7. Emit scalar remainder block or delegate to scalar body lowering with IV start
   at vector trip count.
8. Seal all blocks.

If any operand id, trip count, memory base, or remainder detail is unavailable,
return scalar-fallback status before emitting vector commands.

## `func.mlua` integration

Add:

```moonlift
mb_try_vector_func(ctx: ptr(MomBackLowerCtx), item_idx: i32) -> i32
```

Algorithm:

1. `mv_extract_vec_facts`.
2. If no facts or not ok -> return `0` (scalar).
3. `mv_decide`.
4. If not legal -> return `0`.
5. `mv_plan_kernel`.
6. If no plan -> return `0`.
7. `mv_lower_kernel`.
8. If status is success -> return `1`, else return `0`.

Call from `mb_lower_func` only after function signature/entry setup is ready and
before scalar body lowering. If vector try returns `0`, scalar lowering must run
unchanged.

Important: if vector lowering emits any command before discovering failure, it
cannot safely fall back unless command-buffer rollback exists. Therefore either:

- add a command-buffer mark/truncate API and use it around vector try, or
- require `mv_lower_kernel` to validate all required facts/plans before emitting
  its first command.

Prefer the second approach unless rollback already exists.

## Manifest and hygiene

- Ensure `vec_facts`, `vec_decide`, `vec_plan`, `vec_lower` load after backend
  context/cmd/control modules and before `func.mlua` if `func.mlua` imports them.
- Remove or replace raw-packing code in `vec_lower.mlua`.
- Repository hygiene currently flags raw vector packing; this step must eliminate
  those vector raw-packing failures.

## Tests to add/run

Add tests:

1. `tests/test_mom_vec_no_loop_fallback.lua`
   - function with no loop -> scalar path still works.
2. `tests/test_mom_vec_reject_call.lua`
   - loop with call -> vector decision illegal, scalar fallback.
3. `tests/test_mom_vec_raw_packing_hygiene.lua`
   - hygiene no longer reports `vec_lower.mlua` raw packing.
4. Only if a complete legal vector loop is implemented:
   - `tests/test_mom_vec_counted_map.lua`
   - validates vectorized result and scalar remainder.

Run:

```
luajit scripts/emit_mom_precompiled.lua
luajit tests/test_mom_run_2plus2.lua
luajit tests/test_mom_vec.lua
luajit tests/test_mom_vec_no_loop_fallback.lua
luajit scripts/check_mom_hygiene.lua
```

Do not mark Step 10 complete unless raw vector packing is gone and vector try
cannot corrupt scalar fallback.
