# Step 10: Vector integration

Connect the existing `vec/*.mlua` modules to the lowering pipeline. Refactor them to use `MomBackLowerCtx` and `mb_emit_*` helpers, and integrate into function lowering.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every function complete.**

## Tree encoding — what exists and what does not

### Vector-related tree arrays

**There are NO vector-specific arrays in `MomTreeOut`.** The parser does not emit vector expressions or statements. Vectorization operates at the control-flow level: it looks at loop patterns in control regions (step 8 lowering output) and replaces scalar loop bodies with vectorized equivalents.

### Existing vec modules and their current state

The vec modules in `lua/moonlift/mom/vec/` exist but use raw array packing (`mv_push_cmd`) and `LowerState`-style structs. They must be refactored:

| Module | Current interface | Target interface |
|--------|-------------------|------------------|
| `vec_facts.mlua` | `mv_extract_vec_facts(back, tree, state)` | `mv_extract_vec_facts(ctx: MomBackLowerCtx) → fact_count, ok` |
| `vec_decide.mlua` | `mv_decide(tree, state, facts)` | `mv_decide(ctx: MomBackLowerCtx, fact_count) → decision, scalar, lanes` |
| `vec_plan.mlua` | `mv_plan_kernel(tree, state, decision)` | `mv_plan_kernel(ctx: MomBackLowerCtx) → plan_count, ok` |
| `vec_lower.mlua` | `mv_lower_kernel(back, tree, state, plan)` | `mv_lower_kernel(ctx: MomBackLowerCtx, back_ctx: MomBackLowerCtx) → status` |

### Vector-related tag constants (from mom_tags.lua)

```
VF_PRIMARY_INDUCTION = 2   — induction variable fact
VF_REDUCTION_ADD     = 10  — reduction fact (add)
VF_MEMORY_LOAD       = 20  — memory load fact
VF_MEMORY_STORE      = 21  — memory store fact
VF_REJECT            = 99  — reject fact
VF_DOMAIN_COUNTED   = 1    — domain fact

VD_LEGAL   = 1
VD_ILLEGAL = 2

VP_NO_PLAN   = 1
VP_REDUCE    = 2
VP_MAP       = 3
VP_ALGEBRAIC = 4

BackShapeScalar = 1
BackShapeVec    = 2

DEFAULT_VECTOR_BITS = 128  — max vector width in bits
```

### Fact encoding in aux_i32

Vector facts are encoded as tagged tuples in `ctx.aux_i32`:

```
Induction fact (VF_PRIMARY_INDUCTION = 2):
  aux[0] = VF_PRIMARY_INDUCTION
  aux[1] = iv_value_id    — the induction variable's SSA value
  aux[2] = init_expr_idx  — initial value expression index
  aux[3] = step_expr_idx  — step value expression index
  aux[4] = trip_count_id  — trip count value ID

Memory load fact (VF_MEMORY_LOAD = 20):
  aux[0] = VF_MEMORY_LOAD
  aux[1] = base_ptr_id    — base pointer value ID
  aux[2] = stride_expr    — element stride expression index
  aux[3] = elem_scalar    — element scalar tag
  aux[4] = result_val_id  — loaded value ID

Memory store fact (VF_MEMORY_STORE = 21):
  aux[0] = VF_MEMORY_STORE
  aux[1] = base_ptr_id    — base pointer value ID
  aux[2] = stride_expr    — element stride expression index
  aux[3] = elem_scalar    — element scalar tag
  aux[4] = stored_val_id  — stored value ID

Reduction fact (VF_REDUCTION_ADD = 10):
  aux[0] = VF_REDUCTION_ADD
  aux[1] = accumulator_id  — reduction accumulator value ID
  aux[2] = update_val_id   — value being reduced
  aux[3] = init_val_id     — initial accumulator value

Domain fact (VF_DOMAIN_COUNTED = 1):
  aux[0] = VF_DOMAIN_COUNTED
  aux[1] = lower_bound_expr  — loop lower bound expression index
  aux[2] = upper_bound_expr  — loop upper bound expression index
  aux[3] = trip_count_val_id — trip count value ID
```

### What does NOT exist

- **No vector tree arrays** — no `vec_op`, `vec_lanes`, `vec_elem_ty` in `MomTreeOut`.
- **No EX_VEC_* expression tags** — vector operations are not parsed expressions; they are compiler-generated during vectorization.
- **No ST_VEC_* statement tags** — no vector statements in source AST.
- **No `vec_intrinsic` or `vec_builtin` mappings** in the tree — vector lowering maps scalar ops to vector ops.

## Entrypoints

```moonlift
mv_extract_vec_facts(ctx: ptr(MomBackLowerCtx))
  -> fact_count: i32, ok: bool

mv_decide(ctx: ptr(MomBackLowerCtx), fact_count: i32)
  -> decision_tag: i32, elem_scalar: i32, lanes: i32  -- or VD_ILLEGAL

mv_plan_kernel(ctx: ptr(MomBackLowerCtx))
  -> plan_count: i32, ok: bool

mv_lower_kernel(ctx: ptr(MomBackLowerCtx), back_ctx: ptr(MomBackLowerCtx))
  -> status: i32

mb_try_vector_func(ctx: ptr(MomBackLowerCtx), item_idx: i32)
  -> choice: i32 (0=scalar, 1=vectorized)
```

## 1. vec_facts.mlua — Fact extraction

Current implementation uses raw `vtag/va/vb/vc/vd/ve/vf` arrays. Replace with:

```moonlift
mv_extract_vec_facts(ctx):
  -- 1. Read control region info from ctx.tree
  --    Find the function body's control region (if any)
  --    Get ctrl_start from expr_op/expr_lhs of the body expression
  --    OR from stmt_body_start if the func body is a ST_CONTROL
  -- 
  -- 2. Scan ctrl blocks for loop patterns:
  --    A "loop" is a block that jumps to an earlier block (backedge).
  --    For each block b in the region:
  --      body_start = ctx.tree.ctrl_block_body_start[ctrl_start + b]
  --      body_count = ctx.tree.ctrl_block_body_count[ctrl_start + b]
  --      Scan stmts in body for ST_JUMP where target label is an
  --      earlier block in the same region.
  --      → CF_BACKEDGE pattern
  --
  -- 3. If no backedge found: return (0, true) — not a loop, skip vectorization
  --
  -- 4. Extract induction variable:
  --    Look at block params of the loop header block
  --    params that increment by a constant each iteration → induction var
  --    Push VF_PRIMARY_INDUCTION fact to aux_i32
  --
  -- 5. Extract memory access patterns:
  --    Scan stmts for ST_SET on deref (EX_DEREF with indexed base)
  --    → VF_MEMORY_STORE fact
  --    Scan exprs for EX_DEREF in load context
  --    → VF_MEMORY_LOAD fact
  --
  -- 6. Extract reduction patterns:
  --    Look for binop patterns where result feeds back into next iter
  --    → VF_REDUCTION_ADD/MUL/XOR fact
  --
  -- 7. Return (fact_count, ok=true)
```

Edge: no backedge found → return (0, true). Loop pattern not recognized → return (0, true) — don't emit error, just skip vectorization.

## 2. vec_decide.mlua — Legality decision

```moonlift
mv_decide(ctx, fact_count):
  -- Read facts from ctx.aux_i32 (written by mv_extract_vec_facts)
  -- fact_count entries, each entry is 5 aux_i32 slots
  -- Use mb_ctx_read_aux_i32(ctx, idx) or direct ctx.aux_i32 access
  
  -- 1. Check target vector width: DEFAULT_VECTOR_BITS = 128
  -- 2. Compute elem_scalar * lanes fits in 128 bits
  --    e.g., i32 (32 bits) × 4 lanes = 128 bits → legal
  --    e.g., i64 (64 bits) × 2 lanes = 128 bits → legal
  --    e.g., i32 × 8 lanes = 256 bits → illegal for 128-bit target
  -- 3. Check all memory accesses are contiguous and aligned
  -- 4. Check loop has single induction variable
  -- 5. Check no function calls inside loop body
  -- 6. Check all operations in loop body are vectorizable
  
  -- Return: (VD_LEGAL=1, elem_scalar, lanes) or (VD_ILLEGAL=2, reject_reason, 0)
```

Edge: multiple memory streams → legal if all same stride pattern.
Edge: non-contiguous access → illegal.
Edge: call inside loop → illegal (unless known vectorizable intrinsic).
Edge: no reducible operations → legal (MAP plan still possible).

## 3. vec_plan.mlua — Kernel plan

```moonlift
mv_plan_kernel(ctx):
  -- Read decision from aux_i32 (written by mv_decide)
  -- Read facts from aux_i32 (written by mv_extract_vec_facts)
  
  -- Classify the kernel:
  -- If all operations are element-wise with no cross-iteration dependency:
  --   → VP_MAP plan (3)
  -- If kernel has reduction pattern:
  --   → VP_REDUCE plan (2)
  -- If kernel has algebraic simplification opportunity:
  --   → VP_ALGEBRAIC plan (4)
  -- Otherwise:
  --   → VP_NO_PLAN (1)
  
  -- Push plan to aux_i32 as:
  --   aux[0] = plan_tag
  --   aux[1] = elem_scalar
  --   aux[2] = stop_value (trip count)
  --   aux[3] = counter_init
  --   aux[4] = extra_info
  
  -- Return (plan_count (=1 plan), ok=true) or (0, ok=false)
```

## 4. vec_lower.mlua — Kernel lowering

This is the critical refactoring: replace all raw `mv_push_cmd` calls with `mb_emit_*` helpers:

```moonlift
mv_lower_kernel(ctx, back_ctx):
  -- Read kernel plan from aux_i32
  -- Create vectorized loop blocks:
  blk_entry = mb_ctx_fresh_block(back_ctx)
  blk_loop  = mb_ctx_fresh_block(back_ctx)
  blk_body  = mb_ctx_fresh_block(back_ctx)
  blk_exit  = mb_ctx_fresh_block(back_ctx)
  
  mb_emit_create_block(back_ctx, blk_entry)
  mb_emit_create_block(back_ctx, blk_loop)
  mb_emit_create_block(back_ctx, blk_body)
  mb_emit_create_block(back_ctx, blk_exit)
  
  -- Entry block: initialize induction variable, compute trip count (rounded down)
  mb_emit_switch_to_block(back_ctx, blk_entry)
  -- ... compute trip_count_vec = trip_count - (trip_count % lanes) ...
  -- mb_emit_jump(back_ctx, blk_loop, args_aux, count)
  
  -- Loop block: compare IV against vectorized trip count
  mb_emit_switch_to_block(back_ctx, blk_loop)
  -- mb_emit_append_block_param(back_ctx, blk_loop, iv_val, 0, scalar, 0)
  -- mb_emit_compare(back_ctx, cond, cmp_op, BackShapeScalar, scalar, 0, iv_val, trip_count_vec)
  -- mb_emit_br_if(back_ctx, cond, blk_body, 0, 0, blk_exit, 0, 0)
  
  -- Body block: load vectors, apply vector ops, store/reduce
  mb_emit_switch_to_block(back_ctx, blk_body)
  -- For each memory load fact:
  --   mb_emit_vec_load_info(back_ctx, vec_dst, elem_scalar, lanes, 0, base_ptr, iv_scaled, ...)
  -- For each operation fact:
  --   mb_emit_vec_binary(back_ctx, vec_dst, vec_op, elem_scalar, lanes, lhs, rhs)
  --   mb_emit_vec_compare(back_ctx, vec_dst, cmp_op, elem_scalar, lanes, lhs, rhs)
  --   mb_emit_vec_select(back_ctx, vec_dst, elem_scalar, lanes, cond, then_val, else_val)
  -- For each memory store fact:
  --   mb_emit_vec_store_info(back_ctx, elem_scalar, lanes, 0, base_ptr, iv_scaled, vec_val, ...)
  -- For reduction:
  --   mb_emit_vec_splat(back_ctx, splat, elem_scalar, lanes, scalar_val)
  --   mb_emit_vec_binary(...) -- horizontal op across lanes
  -- Update induction variable by lanes
  -- mb_emit_jump(back_ctx, blk_loop, args_aux, count)
  
  -- Exit block: scalar remainder (if any)
  mb_emit_switch_to_block(back_ctx, blk_exit)
  -- ... handle remainder loop ...
  
  -- Seal all blocks
  mb_emit_seal_block(back_ctx, blk_entry)
  mb_emit_seal_block(back_ctx, blk_loop)
  mb_emit_seal_block(back_ctx, blk_body)
  mb_emit_seal_block(back_ctx, blk_exit)
  
  -- Return status (0=ok)
```

Vector emit helpers (already exist in cmd.mlua from step 2):
```
mb_emit_vec_splat(ctx, dst, elem_scalar, lanes, scalar_val)
mb_emit_vec_binary(ctx, dst, op, elem_scalar, lanes, lhs, rhs)
mb_emit_vec_compare(ctx, dst, op, elem_scalar, lanes, lhs, rhs)
mb_emit_vec_select(ctx, dst, elem_scalar, lanes, cond, then_val, else_val)
mb_emit_vec_load_info(ctx, dst, elem_scalar, lanes, addr_base_tag, addr_base_id, byte_offset, ...)
mb_emit_vec_store_info(ctx, elem_scalar, lanes, addr_base_tag, addr_base_id, byte_offset, value, ...)
mb_emit_vec_mask(ctx, dst, op, mask, ...)
```

## 5. func.mlua — Integration

```moonlift
mb_try_vector_func(ctx, item_idx):
  -- 1. mv_extract_vec_facts(ctx) → (fact_count, ok)
  -- 2. If fact_count == 0 → return 0 (scalar path)
  -- 3. mv_decide(ctx, fact_count) → (decision, elem, lanes)
  -- 4. If decision != VD_LEGAL → return 0 (scalar path)
  -- 5. mv_plan_kernel(ctx) → (plan_count, ok)
  -- 6. If plan_count == 0 → return 0 (scalar path)
  -- 7. mv_lower_kernel(ctx, ctx) → status
  -- 8. If status == 0 → return 1 (vectorized path)
  -- 9. Else → return 0 (scalar fallback)
```

Called from `mb_lower_func`:
```
mb_lower_func(ctx, item_idx):
  1. If item has loop body (control region with backedge):
     let vec_choice = mb_try_vector_func(ctx, item_idx)
     if vec_choice == 1 → return (vectorized, ok=true)
  2. Else: proceed with scalar lowering (existing algorithm)
```

## 6. Wiring table

| Function | Module | Purpose |
|---|---|---|
| `mv_extract_vec_facts` | vec_facts.mlua | Extract loop facts → aux_i32 |
| `mv_decide` | vec_decide.mlua | Decide if vectorization is legal |
| `mv_plan_kernel` | vec_plan.mlua | Create vectorization plan → aux_i32 |
| `mv_lower_kernel` | vec_lower.mlua | Emit vectorized loop using mb_emit_vec_* |
| `mb_try_vector_func` | func.mlua | Try+fallback: attempt vectorization → scalar |
| Remaining helpers | cmd.mlua | All vector emit helpers exist |
| `ctx.aux_i32` | lower_ctx.mlua | Shared data conduit between vec modules |

## Hard bans

- No raw command packing — vec_lower must use `mb_emit_vec_*` helpers exclusively
- No `LowerState` — only `MomBackLowerCtx`
- No `CmdTrap` fallbacks
- No `TODO`/`FIXME`/`placeholder`/`simplified`
- Vector emit helpers must already exist in cmd.mlua — do NOT add new ones in this step
- Vectorization failure must NOT prevent scalar lowering — it's a try/fallback
- All vector operations must specify `elem_scalar` + `lanes` (shape_tag=1=BackShapeVec when using vec emits — but the `mb_emit_vec_*` helpers handle this internally)
- `ctx.aux_i32` is the communication channel between vec modules — read/write use `ctx.aux_i32.data[start]` or `mb_ctx_push_aux_i32`/helper to read
- Do NOT create new tree arrays — vectorization is a lowering-time optimization, not a parsed language feature
- Remainder loop (trip_count % lanes != 0): lower as a scalar remainder block following the vectorized loop
