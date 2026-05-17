# Step 8: Control region lowering

Create `lua/moonlift/mom/back/control_lower.mlua` — lowers control regions (block/jump/yield) to backend blocks and jumps.

Modify `lua/moonlift/mom/back/control.mlua` to export control facts needed by the lowerer.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every function complete.**

## Tree encoding — control regions

### Control region expressions (EX_CONTROL)

EX_CONTROL (tag 19) is produced at `native_core.mlua:912`:
```
np_add_expr(out, EX_CONTROL, tok, result_ty, ctrl_start, 1, 0)
```

In `MomTreeOut`:
```
expr_tag[idx]   = 19 (ME_CONTROL)
expr_tok[idx]   = token index
expr_op[idx]    = result type index (0 = void)
expr_lhs[idx]   = ctrl_start (index into ctrl_block_* arrays)
expr_rhs[idx]   = 1 (block count — always 1 for single-entry region; all sub-blocks follow)
expr_aux0[idx]  = 0
```

### Control region statements (ST_CONTROL)

ST_CONTROL (tag 11) is produced at `native_core.mlua:888`:
```
np_add_stmt(out, ST_CONTROL, tok, label_tok, entry_param_start, param_count, ctrl_start, 1)
```

```
stmt_name[i]         = label_tok (entry block name token)
stmt_type[i]         = entry_param_start (index into entry_param_* arrays)
stmt_value[i]        = param_count (number of entry block params)
stmt_body_start[i]   = ctrl_start (index into ctrl_block_* arrays)
stmt_body_count[i]   = 1 (block count for entry)
```

### Control block arrays

There are 5 parallel arrays in `MomTreeOut`:
```
ctrl_block_label[ctrl_start + b]          = label token for block b
ctrl_block_param_start[ctrl_start + b]    = index into entry_param_* or param_* arrays
ctrl_block_param_count[ctrl_start + b]    = number of params
ctrl_block_body_start[ctrl_start + b]     = index into stmt_list for block body
ctrl_block_body_count[ctrl_start + b]     = number of stmts in block body
```

### Entry param arrays

```
entry_param_name[ep_start + i]    = name token for entry param i
entry_param_type[ep_start + i]    = type index for entry param i
entry_param_init[ep_start + i]    = initializer expression index for entry param i
```

The first block (b=0) in a region is always the entry block. Its params are in `entry_param_*` arrays. All other blocks' params use the flat `param_name/param_type` arrays (from `native_core.mlua:984`).

**There is NO `param_init` array for non-entry blocks** — non-entry block params don't have initializers (they receive values from jumps).

**There is NO `ctrl_block_entry_flag`** — the entry block is always `ctrl_block_*[ctrl_start + 0]` (the first block in the ctrl block array for a region).

### Jump statements in control bodies

ST_JUMP (10) in a control body targets a block label:
```
stmt_name[idx]  = target name token (block label to jump to)
stmt_type[idx]  = arg_start (index into jump_arg_name/expr arrays)
stmt_value[idx] = arg_count
```

The target block is found by matching `stmt_name` against `ctrl_block_label` for all blocks in the region.

### What does NOT exist

- **No `ctrl_region_*` arrays** — control regions are just EX_CONTROL/ST_CONTROL with `ctrl_start` pointing into the flat `ctrl_block_*` arrays.
- **No `control_target_resolution`** — target block is resolved by matching label tokens (name-based, not indexed).
- **No `block_cont_spec`** — continuations are not used for block/jump inside control regions.
- **No separate `ctrl_block_entry_flag`** — entry is block 0.
- **No `param_init` for non-entry blocks** — only entry params have initializers.

### Existing helpers available in cmd.mlua

```
mb_emit_create_block(ctx, blk_id)
mb_emit_switch_to_block(ctx, blk_id) 
mb_emit_append_block_param(ctx, blk_id, val, shape_tag, scalar, lanes)
mb_emit_seal_block(ctx, blk_id)
mb_emit_jump(ctx, target_blk, args_aux, count)
mb_emit_br_if(ctx, cond, then_blk, then_args, then_count, else_blk, else_args, else_count)
mb_emit_return_void(ctx)
mb_emit_return_value(ctx, val)
mb_emit_switch_int(ctx, val, scalar, cases_aux, n_cases, default_blk)
mb_ctx_fresh_value(ctx)
mb_ctx_fresh_block(ctx)
mb_ctx_push_aux_i32(ctx, val)
```

## control.mlua changes

Add to `lua/moonlift/mom/back/control.mlua`:

```moonlift
mb_control_get_region_info(ctx, region_idx)
  → ctrl_start: i32, n_blocks: i32, entry_label: i32, result_scalar: i32
  -- Extract control region info from EX_CONTROL or ST_CONTROL tree node.
  -- For EX_CONTROL: reads expr_op (result type) and expr_lhs (ctrl_start)
  --   + expr_rhs (block count, always 1 for the entry; total blocks = scan till labels change)
  -- For ST_CONTROL: reads stmt_type (entry_param_start), stmt_value (param_count),
  --   stmt_body_start (ctrl_start), stmt_body_count (block count)
  -- Returns the ctrl_start index, total n_blocks (count non-zero labels), etc.

mb_control_find_block_by_label(tree, ctrl_start, n_blocks, label_tok) → block_idx: i32
  -- Linear scan: ctrl_block_label[ctrl_start + b] == label_tok → return b
  -- Returns -1 if not found

mb_control_get_block_params(tree, ctrl_start, block_idx) 
  → param_start, param_count: i32
  -- Delegate: if block_idx == 0 (entry), return from entry_param_start/count
  -- else return from ctrl_block_param_start/count

mb_control_get_param_type(tree, ctrl_start, block_idx, param_offset) → type_idx: i32
  -- Get type for a specific block param
  -- Entry params from entry_param_type[], non-entry from param_type[]
```

## control_lower.mlua

```moonlift
return function(M)
  -- imports from cmd.mlua, env.mlua, expr_lower.mlua, stmt_lower.mlua, control.mlua
  return M
end
```

### Entrypoints

```moonlift
mb_lower_control_region(ctx: ptr(MomBackLowerCtx), region_idx: i32)
  -> value: i32, flow: i32, ok: bool

mb_lower_control_stmt(ctx: ptr(MomBackLowerCtx), stmt_idx: i32)
  -> flow: i32, ok: bool
```

### Control lowering algorithm

```
mb_lower_control_region(ctx, region_idx):
  1. Determine if region is an expression or statement region:
     - If ctx.tree.expr_tag[region_idx] == ME_CONTROL (19):
       → expression region. result_ty = ctx.tree.expr_op[region_idx]
       → result_scalar = ctx.expr_scalar[region_idx] or BackVoid
       → ctrl_start = ctx.tree.expr_lhs[region_idx]
     - If ctx.tree.stmt_tag[region_idx] == MS_CONTROL (11):
       → statement region. result_ty = 0 (void)
       → result_scalar = BackVoid
       → ctrl_start = ctx.tree.stmt_body_start[region_idx]
     
     n_blocks = count blocks: scan ctrl_block_label from ctrl_start until 0 or end of array
               (practical approach: look at counts[COUNT_CTRL_BLOCKS] - ctrl_start)
     
  2. Build label→block_idx map:
     For b = 0..n_blocks-1:
       label_tok = ctx.tree.ctrl_block_label[ctrl_start + b]
       store in Lua table: label_map[label_tok] = b

  3. Create backend block IDs:
     For entry block (=ctrl_start + 0) and each named block:
       mb_ctx_fresh_block(ctx) → blk_id
       store in array: blk_ids[b] = blk_id
       mb_emit_create_block(ctx, blk_id)

  4. Lower entry block params and entry jump:
     entry_param_start = ctx.tree.ctrl_block_param_start[ctrl_start + 0]
     entry_param_count = ctx.tree.ctrl_block_param_count[ctrl_start + 0]
     
     For ep = 0..entry_param_count-1:
       name_tok = ctx.tree.entry_param_name[entry_param_start + ep]
       init_expr = ctx.tree.entry_param_init[entry_param_start + ep]
       mb_lower_expr_region(ctx, init_expr, ...) → (init_val, scalar, ok)
       mb_emit_append_block_param(ctx, blk_ids[0], init_val, 0, scalar, 0)
       (Don't bind in env yet — params are bound when entering the block)

  5. For each block b in order (0..n_blocks-1):
     mb_emit_switch_to_block(ctx, blk_ids[b])
     
     -- Bind block params
     if b == 0:
       param_start = ctx.tree.ctrl_block_param_start[ctrl_start + 0]
       param_count = ctx.tree.ctrl_block_param_count[ctrl_start + 0]
       -- Entry param init already done in step 4. Now bind them in env:
       for ep = 0..param_count-1:
         name_tok = ctx.tree.entry_param_name[param_start + ep]
         param_type = ctx.tree.entry_param_type[param_start + ep]
         scalar = ctx.tree.type_scalar[param_type]  -- for MT_SCALAR types
         mb_ctx_fresh_value(ctx) → param_val
         mb_emit_append_block_param(ctx, blk_ids[b], param_val, 0, scalar, 0)
         mb_env_bind_scalar(ctx.env, name_tok, param_val, scalar)
     else:
       param_start = ctx.tree.ctrl_block_param_start[ctrl_start + b]
       param_count = ctx.tree.ctrl_block_param_count[ctrl_start + b]
       for p = 0..param_count-1:
         name_tok = ctx.tree.param_name[param_start + p]
         param_type = ctx.tree.param_type[param_start + p]
         scalar = ctx.tree.type_scalar[param_type]
         mb_ctx_fresh_value(ctx) → param_val
         mb_emit_append_block_param(ctx, blk_ids[b], param_val, 0, scalar, 0)
         mb_env_bind_scalar(ctx.env, name_tok, param_val, scalar)
     
     -- Lower block body
     body_start = ctx.tree.ctrl_block_body_start[ctrl_start + b]
     body_count = ctx.tree.ctrl_block_body_count[ctrl_start + b]
     body_flow, body_ok = mb_lower_stmt_list_body(ctx, body_start, body_count)
     
     (body_flow should be BackTerminates — every block must end in jump/yield/return)

  6. After all blocks lowered, seal them:
     for b = 0..n_blocks-1:
       mb_emit_seal_block(ctx, blk_ids[b])

  7. For expression regions:
     The region produces a value through its yields. Create an exit block:
     mb_emit_create_block(ctx, exit_blk)
     mb_ctx_fresh_value(ctx) → result_val
     mb_emit_append_block_param(ctx, exit_blk, result_val, 0, result_scalar, 0)
     mb_emit_switch_to_block(ctx, exit_blk)
     mb_emit_seal_block(ctx, exit_blk)
     Return (result_val, BackTerminates, ok=true)

  8. For statement regions (void):
     Return (0, BackTerminates, ok=true)
```

### Control statement lowering dispatcher

```
mb_lower_control_stmt(ctx, stmt_idx):
  dispatch on ctx.tree.stmt_tag[stmt_idx]:
    ST_JUMP (10):
      → target_label = ctx.tree.stmt_name[stmt_idx]
      → arg_start = ctx.tree.stmt_type[stmt_idx]
      → arg_count = ctx.tree.stmt_value[stmt_idx]
      → Find target block in label_map
      → For each arg i:
          name_tok = ctx.tree.jump_arg_name[arg_start + i]
          arg_expr = ctx.tree.jump_arg_expr[arg_start + i]
          If arg_expr is name-token-based (jump by name):
            kind, val, scalar = mb_env_lookup_into(ctx.env, name_tok)
            mb_ctx_push_aux_i32(ctx, val)
          Else:
            mb_lower_expr_region(ctx, arg_expr) → (val, scalar, ok)
            mb_ctx_push_aux_i32(ctx, val)
      → mb_emit_jump(ctx, target_blk, args_aux_start, arg_count)
      → Return (BackTerminates, ok=true)

    ST_YIELD_VOID (8):
      → mb_emit_return_void(ctx)
      → Return (BackTerminates, ok=true)

    ST_YIELD_VALUE (9):
      → value_expr = ctx.tree.stmt_name[stmt_idx]
      → mb_lower_expr_region(ctx, value_expr) → (val, scalar, ok)
      → mb_emit_return_value(ctx, val)
      → Return (BackTerminates, ok=true)

    ST_IF (5): → delegate to mb_lower_if_stmt(ctx, stmt_idx)
    ST_SWITCH (13): → delegate to mb_lower_switch_stmt(ctx, stmt_idx)
    ST_LET (1): → delegate to mb_stmt_let(ctx, stmt_idx)
    ST_VAR (2): → delegate to mb_stmt_var(ctx, stmt_idx)
    ST_SET (3): → delegate to mb_stmt_set(ctx, stmt_idx)
    ST_EXPR (4): → delegate to mb_stmt_expr(ctx, stmt_idx)
    ST_RETURN_VOID (6): → mb_emit_return_void(ctx); Return (BackTerminates, ok=true)
    ST_RETURN_VALUE (7): → mb_lower_expr + mb_emit_return_value; Return (BackTerminates, ok=true)
    ST_CONTROL (11): → recursive: mb_lower_control_region(ctx, stmt_idx) for nested regions
    else → Return (BackFallsThrough, ok=false)
```

### Statement list body lowering

Reuses the same `mb_lower_stmt_list_body` from step 7. For each stmt in the range:
- Dispatch to the appropriate handler based on `stmt_tag`.
- Track `mb_last_flow` for termination detection.
- If previous stmt terminated, remaining stmts are dead code (skip without error).

### Integration with func.mlua

`mb_lower_func_body` should handle the body containing control regions:
- If the func body's first stmt is ST_CONTROL, it might be a region-based func body.
- The body list may also contain just normal stmts (simple func body).

For now, a simple func body with `let/return` etc. uses the normal stmt lowering.
A func body that starts with a control region delegates to `mb_lower_control_region`.

### What to export from control_lower.mlua

```lua
return {
  mb_lower_control_region = mb_lower_control_region,
  mb_lower_control_stmt = mb_lower_control_stmt,
  mb_lower_stmt_list_body = mb_lower_stmt_list_body,
}
```

### Wiring

| Function | Lives in | Called from |
|---|---|---|
| `mb_control_get_region_info` | `control.mlua` | `control_lower.mlua` |
| `mb_control_find_block_by_label` | `control.mlua` | `control_lower.mlua` |
| `mb_control_get_block_params` | `control.mlua` | `control_lower.mlua` |
| `mb_lower_control_region` | `control_lower.mlua` | `func.mlua` (if func body is a region) |
| `mb_lower_control_stmt` | `control_lower.mlua` | body lowering inside regions |
| `mb_lower_stmt_list_body` | `control_lower.mlua` | body lowering (shared) |

## Hard bans

- No raw command packing — use `mb_emit_create_block`, `mb_emit_switch_to_block`, `mb_emit_append_block_param`, `mb_emit_jump`, `mb_emit_return_*`, `mb_emit_seal_block`
- No `LowerState` — only `MomBackLowerCtx`
- No `CmdTrap` fallbacks
- No `TODO`/`FIXME`/`placeholder`/`simplified`
- Block params are real typed values — no fake continuation args
- Every block must be sealed after its body lowers
- Entry block params have initializers (entry_param_init) — lower those before binding param values
- Non-entry block params have NO initializers — they receive values from jumps at runtime
- Block labels are name tokens, not string names — compare with integer equality
- Target resolution for jumps is label-based: find matching `ctrl_block_label` in the region
