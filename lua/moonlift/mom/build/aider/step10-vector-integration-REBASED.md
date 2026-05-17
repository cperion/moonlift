# Step 10: Vector integration with struct-based continuation discipline
## [REBASED for Struct Continuations Architecture]

This step integrates the vector pipeline as a conservative try/fallback pass,
following the **struct-based continuation architecture** established in Steps 1-9.
It must never fabricate vector facts or emit vectorized loops unless legality and
plan data are explicitly proven.

**Architecture requirement**: Vector modules (vec_facts, vec_decide, vec_plan,
vec_lower) must return struct results instead of tuple continuations, maintaining
consistency with the rest of the backend.

**Prerequisites:**
- Step 8 control lowering complete and struct-based.
- Step 9 command tape width correct and struct-based.
- If either is missing, this step must stop after making vec modules compile-safe.

**Policy:** Hard rewrite for touched vec files. No raw command packing, no
`LowerState`, no `CmdTrap` fallback, no hidden allocation, no fake vector facts,
no fake plans. All vector regions use struct result types. Vector failure always
falls back to scalar lowering.

## Required source-of-truth checks

Read before editing:

- `lua/moonlift/vec_kernel_plan.lua`
- `lua/moonlift/vec_kernel_to_back.lua`
- Vector sections in `lua/moonlift/tree_to_back.lua`
- `BACK_WIRE_FORMAT.md` vector command slots
- `lua/moonlift/mom/vec/*.mlua` current skeletons
- `lua/moonlift/mom/back/control_lower.mlua` — for block/param patterns
- `lua/moonlift/mom/back/cmd.mlua` — for `mb_emit_vec_*` helpers
- `lua/moonlift/mom/back/func.mlua`

## Vector result struct types (New)

Add to `lua/moonlift/mom/schema/MoonBack.mlua`:

```moonlift
M.MomVecFactsResult = struct MomVecFactsResult
    facts_aux: i32
    fact_count: i32
    ok: bool
end

M.MomVecDecideResult = struct MomVecDecideResult
    decision_aux: i32
    decision_tag: i32
    elem_scalar: i32
    lanes: i32
    ok: bool
end

M.MomVecPlanResult = struct MomVecPlanResult
    plan_aux: i32
    plan_count: i32
    ok: bool
end

M.MomVecLowerStatus = struct MomVecLowerStatus
    status: i32
end
```

All vector entrypoints return these struct types, not tuples.

## What exists and what does not

There are no vector-specific parsed AST arrays in `MomTreeOut`:

- no `vec_op`
- no `vec_lanes`
- no vector expression tags from source syntax
- no vector statement tags from source syntax

Vectorization is a compiler optimization over already-typechecked control
regions. It must inspect `ctrl_block_*`, `stmt_list`, expression trees, and
backend scalar/type facts.

## Required command helpers

Before touching vec lowering, verify these helpers exist in `cmd.mlua` and push
full-width command entries:

```
mb_emit_vec_splat(ctx, dst, elem_scalar, lanes, scalar_val)
mb_emit_vec_binary(ctx, dst, op, elem_scalar, lanes, lhs, rhs)
mb_emit_vec_compare(ctx, dst, op, elem_scalar, lanes, lhs, rhs)
mb_emit_vec_select(ctx, dst, elem_scalar, lanes, cond, then_val, else_val)
mb_emit_vec_mask(ctx, dst, op, mask, ...)
mb_emit_vec_load_info(ctx, dst, elem_scalar, lanes, base_tag, base_id, ...)
mb_emit_vec_store_info(ctx, elem_scalar, lanes, base_tag, base_id, ...)
```

If missing, implement in `cmd.mlua` first. Do not call `mv_push_cmd` or write
command slots by hand in vec modules.

## Aux layout discipline

Use `ctx.aux_i32` for facts/plans. Every aux segment starts with a header:

```
aux[start + 0] = segment_tag
aux[start + 1] = entry_count
aux[start + 2] = entry_stride
aux[start + 3] = first_entry_word...
```

Local segment tags:

```
MV_SEG_FACTS = 1
MV_SEG_DECISION = 2
MV_SEG_PLAN = 3
```

Fact entry stride: 6 words `[fact_tag, a, b, c, d, e]`
Plan entry stride: 8 words `[plan_tag, elem_scalar, lanes, trip_count_val, iv_init_val, iv_step_val, body_block_idx, flags]`

## Vector module entrypoints

All return struct results. Use continuation blocks for any internal regions.

### `vec_facts.mlua`

Export as region:

```moonlift
local mv_extract_vec_facts = region(ctx: ptr(MomBackLowerCtx), item_idx: i32;
                                   done: cont(result: MomVecFactsResult))
entry start()
    -- algorithm
    jump done(result = MomVecFactsResult{facts_aux = aux, fact_count = n, ok = true})
end
end
```

Algorithm:

1. Find function body's control region.
   - If no body control region: return `(facts_aux, 0, true)`.
2. Determine `ctrl_start` and `n_blocks` from item/body metadata.
3. Find backedges by scanning block jumps and resolving labels.
4. If no backedge: return zero facts, `ok=true`.
5. Extract only provable facts:
   - one primary induction variable (block param updated by `iv + constant_step`)
   - counted domain from compare/yield guard
   - contiguous memory load/store with invariant base and induction index
   - reduction as `acc + value`
6. If pattern not recognized, return fewer facts or `VF_REJECT` fact.

### `vec_decide.mlua`

Export as region:

```moonlift
local mv_decide = region(ctx: ptr(MomBackLowerCtx),
                        facts_aux: i32, fact_count: i32;
                        done: cont(result: MomVecDecideResult))
entry start()
    -- decision algorithm
    jump done(result = MomVecDecideResult{decision_aux = aux, decision_tag = tag,
                                        elem_scalar = scalar, lanes = n, ok = true})
end
end
```

Algorithm:

1. If `fact_count == 0`, return `VD_ILLEGAL`, `ok=true`.
2. Reject if any `VF_REJECT` fact exists.
3. Require exactly one primary induction fact.
4. Require a counted domain/trip count fact.
5. Determine element scalar from memory/reduction facts.
6. Compute lanes from 128-bit vector width: `lanes = 128 / scalar_bits(elem_scalar)`.
   Reject if `scalar_bits == 0` or `lanes < 2`.
7. Reject calls, unknown statements, non-contiguous memory, unsupported ops.
8. Write decision segment, return `VD_LEGAL` only if all checks pass.

### `vec_plan.mlua`

Export as region:

```moonlift
local mv_plan_kernel = region(ctx: ptr(MomBackLowerCtx),
                             facts_aux: i32, fact_count: i32,
                             decision_aux: i32, decision_tag: i32,
                             elem_scalar: i32, lanes: i32;
                             done: cont(result: MomVecPlanResult))
entry start()
    -- planning algorithm
    jump done(result = MomVecPlanResult{plan_aux = aux, plan_count = n, ok = true})
end
end
```

Algorithm:

1. If decision is not `VD_LEGAL`, return `(plan_aux, 0, true)`.
2. Classify plan:
   - reduction facts → `VP_REDUCE`
   - memory map with elementwise ops → `VP_MAP`
   - otherwise `VP_NO_PLAN`
3. Do not invent algebraic plans unless hosted oracle has exact rule.
4. Write one plan entry only when lowering has enough operands/block ids.
   Otherwise return no plan and scalar fallback.

### `vec_lower.mlua`

Export as region:

```moonlift
local mv_lower_kernel = region(ctx: ptr(MomBackLowerCtx),
                              plan_aux: i32, plan_count: i32;
                              done: cont(result: MomVecLowerStatus))
entry start()
    -- lowering algorithm
    jump done(result = MomVecLowerStatus{status = 0})  -- 0 = success
end
end
```

Rules:

- If `plan_count == 0`, return nonzero (scalar fallback).
- Use only `mb_emit_*` helpers.
- Do not call `mv_push_cmd`.
- Do not write command arrays directly.
- Every vector op must specify `elem_scalar` and `lanes`.
- Remainder handling mandatory. If not implemented, return fallback status before
  emitting partial CFG.

Lowering outline for legal complete plan:

1. Create vector loop blocks with `mb_ctx_fresh_block` and `mb_emit_create_block`.
2. Append/bind loop block params for induction/reduction values.
3. Compute vector trip count = `trip_count - (trip_count % lanes)`.
4. Emit loop compare and `mb_emit_br_if`.
5. Emit vector loads/ops/stores/reduction using vector helpers.
6. Jump back with updated IV/reduction params.
7. Emit scalar remainder block or delegate to scalar body lowering at vector trip
   count start.
8. Seal all blocks.

If any operand, trip count, memory base, or remainder is unavailable, return
fallback status before emitting vector commands.

## `func.mlua` integration

Add region wrapper:

```moonlift
local mb_try_vector_func = region(ctx: ptr(MomBackLowerCtx), item_idx: i32;
                                 done: cont(result: i32))
entry start()
    emit mv_extract_vec_facts(ctx, item_idx; done = after_facts)
end
block after_facts(facts_result: MomVecFactsResult)
    if facts_result.ok == false or facts_result.fact_count == 0 then
        jump done(result = 0)  -- scalar path
    end
    emit mv_decide(ctx, facts_result.facts_aux, facts_result.fact_count;
                   done = after_decide)
end
block after_decide(decide_result: MomVecDecideResult)
    if decide_result.ok == false or decide_result.decision_tag != VD_LEGAL then
        jump done(result = 0)  -- scalar path
    end
    emit mv_plan_kernel(ctx, ..., decide_result.elem_scalar, decide_result.lanes;
                        done = after_plan)
end
block after_plan(plan_result: MomVecPlanResult)
    if plan_result.ok == false or plan_result.plan_count == 0 then
        jump done(result = 0)  -- scalar path
    end
    emit mv_lower_kernel(ctx, plan_result.plan_aux, plan_result.plan_count;
                        done = after_lower)
end
block after_lower(lower_result: MomVecLowerStatus)
    jump done(result = select(lower_result.status == 0, 1, 0))
end
end
```

Call from `mb_lower_func` after signature/entry setup, before scalar body lowering.
If vector try returns 0, scalar lowering runs unchanged.

**Important:** If vector lowering emits commands before discovering failure, it
cannot safely fall back without rollback. Either:

- Add command-buffer mark/truncate API and use it around vector try, or
- Require `mv_lower_kernel` to validate all required facts/plans before its first
  command.

Prefer the second approach.

## Struct continuation patterns in vec modules

All regions must use struct continuations, never tuples:

```moonlift
block after_region(result: MomVecFactsResult)
    if result.ok == false then jump error end
    let facts_aux: i32 = result.facts_aux
    let fact_count: i32 = result.fact_count
    -- continue with fields
end
```

Never write `block after_region(facts_aux: i32, fact_count: i32, ok: bool)`.

## Manifest and hygiene

- Ensure `vec_facts`, `vec_decide`, `vec_plan`, `vec_lower` load after
  `back/control_lower` and before `func.mlua`.
- Remove or replace raw-packing code in `vec_lower.mlua`.
- All vector regions must use struct result types.
- Repository hygiene must not flag raw vector packing after this step.

## Tests to add/run

Add tests:

1. `test_mom_vec_no_loop_fallback.lua`: function with no loop → scalar path works.
2. `test_mom_vec_reject_call.lua`: loop with call → vector illegal, scalar fallback.
3. `test_mom_vec_raw_packing_hygiene.lua`: hygiene no longer reports raw packing.
4. Only if complete legal vector loop implemented:
   - `test_mom_vec_counted_map.lua`: validates vectorized result and scalar remainder.

Run:

```
luajit scripts/emit_mom_precompiled.lua
luajit tests/test_mom_run_2plus2.lua
luajit tests/test_mom_vec.lua
luajit tests/test_mom_vec_no_loop_fallback.lua
luajit scripts/check_mom_hygiene.lua
```

## Completion criteria

- ✓ Vector result structs defined in schema.
- ✓ All `vec_*.mlua` entrypoints return struct results.
- ✓ All internal regions use struct continuations.
- ✓ `mb_try_vector_func` wires decision→plan→lower with struct results.
- ✓ No raw vector command packing in `vec_lower.mlua`.
- ✓ Vector try cannot corrupt scalar fallback.
- ✓ Tests pass.
- ✓ No new hygiene violations.
