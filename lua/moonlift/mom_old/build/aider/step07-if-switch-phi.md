# Step 7: If/switch phi statements

Enhance `lua/moonlift/mom/back/stmt_lower.mlua` with proper phi-node (SSA join block params) for mutated local cells across branches.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every case complete.**

## Tree encoding — what exists and what does not

**Do NOT add new arrays to `MomTreeOut`.** All statement fields use the existing `stmt_name/type/value/body_start/body_count/aux` slots. Switch arms use the `switch_arm_*` arrays. Jump args use `jump_arg_name/expr` arrays.

### Statement tag encoding table

Each statement is stored via `np_add_stmt(out, tag, tok, a, b, c, d, e)` in `native_core.mlua`. The `stmt_*` arrays in `MomTreeOut` map as:

```
stmt_tag[i]           = tag (ST_* constant)
stmt_tok[i]           = tok (token index)
stmt_name[i] (= a)    = varies by tag
stmt_type[i] (= b)    = varies by tag
stmt_value[i] (= c)   = varies by tag
stmt_body_start[i](=d)= varies by tag
stmt_body_count[i](=e)= varies by tag
stmt_aux[i]           = 0 (always 0 — reserved)
```

| Tag | Constant | `stmt_name` | `stmt_type` | `stmt_value` | `stmt_body_start` | `stmt_body_count` | Source ref |
|-----|----------|-------------|-------------|--------------|-------------------|-------------------|------------|
| ST_LET | 1 | name token | type index | init expr idx | 0 | 0 | `native_core.mlua:593` |
| ST_VAR | 2 | name token | type index | init expr idx | 0 | 0 | `native_core.mlua:593` |
| ST_SET | 3 | place expr idx | 0 | value expr idx | 0 | 0 | `native_core.mlua:672` |
| ST_EXPR | 4 | expr idx | 0 | 0 | 0 | 0 | `native_core.mlua:676` |
| ST_IF | 5 | cond expr idx | then_body_start | then_body_count | else_body_start | else_body_count | `native_core.mlua:731` |
| ST_RETURN_VOID | 6 | 0 | 0 | 0 | 0 | 0 | `native_core.mlua:609` |
| ST_RETURN_VALUE | 7 | value expr idx | 0 | 0 | 0 | 0 | `native_core.mlua:614` |
| ST_YIELD_VOID | 8 | 0 | 0 | 0 | 0 | 0 | `native_core.mlua:609` |
| ST_YIELD_VALUE | 9 | value expr idx | 0 | 0 | 0 | 0 | `native_core.mlua:614` |
| ST_JUMP | 10 | target name tok | jump_arg_start | jump_arg_count | 0 | 0 | `native_core.mlua:664` |
| ST_SWITCH | 13 | value expr idx | arm_start | arm_count | default_start | default_count | `native_core.mlua:791` |

### IF statement encoding detail

ST_IF (5) is produced at `native_core.mlua:731`:
```
np_add_stmt(out, ST_IF, kw_tok, cond, then_start, then_count, else_start, else_count)
```

```
stmt_name[i]         = cond expression index
stmt_type[i]         = then_body_start (index into stmt_list)
stmt_value[i]        = then_body_count
stmt_body_start[i]   = else_body_start (-1 if no else)
stmt_body_count[i]   = else_body_count
```

Both `then_body` and `else_body` reference ranges in `ctx.tree.stmt_list` (the flat stmt list array). The `stmt_list` is a flat array indexed by `ctx.tree.stmt_list[idx]`, with `count` entries starting at `stmt_body_start`.

### SWITCH statement encoding detail

ST_SWITCH (13) is produced at `native_core.mlua:791`:
```
np_add_stmt(out, ST_SWITCH, tok, value, arm_start, arm_count, default_start, default_count)
```

```
stmt_name[i]         = value expression index
stmt_type[i]         = arm_start (index into switch_arm_* arrays)
stmt_value[i]        = arm_count
stmt_body_start[i]   = default_body_start (index into stmt_list, -1 if no default)
stmt_body_count[i]   = default_body_count
```

Switch arms stored in separate arrays:
```
switch_arm_key[arm_start + a]         = key expression index for arm a
switch_arm_body_start[arm_start + a]  = body stmt list start (index into stmt_list)
switch_arm_body_count[arm_start + a]  = body stmt list count
```

**There is NO separate `switch_arm_key_raw` array.** The arm key is an expression index. To get the literal value, lower the key expression.

**There is NO `arm_*_cont` or continuation tracking.** Switch lowering collects phi changes across all arms + default, not per-continuation.

### ST_SET for local cell mutation

ST_SET (3) sets a local cell. It uses `np_add_stmt(out, ST_SET, tok, e, v, 0, 0, 0)` where:
- `stmt_name = e` = place expression index (the target)
- `stmt_value = v` = value expression index (the source)
- All other fields = 0

When the place is `EX_REF` (a local variable reference), the set mutates that local's binding. The env stores it as either `MB_LOCAL_SCALAR` (value-backed, rebind via `mb_env_bind_scalar`) or `MB_LOCAL_STACK` (stack cell, emit store).

### Jump arg encoding

Jump arguments for `ST_JUMP`:
```
jump_arg_name[jump_arg_start + i]   = name token for arg i
jump_arg_expr[jump_arg_start + i]   = expression index for arg i
```

### Typecheck outputs consumed by step 7

```
ctx.expr_type[idx]     — type index for expression idx
ctx.expr_scalar[idx]   — back scalar tag for expression idx  
```

### Related env functions

From `lua/moonlift/mom/back/env.mlua`:
```
mb_env_lookup_into(env, name_tok, kind_out, value_out, scalar_out)
  → kind (MB_LOCAL_SCALAR=0, MB_LOCAL_STACK=1, MB_LOCAL_VIEW=2, MB_NOT_FOUND=-1)
  → value_out, scalar_out (filled on success)

mb_env_bind_scalar(env, name_tok, val_id, scalar)
  → rebinds a name to a new SSA value (used for phi rebinding)

mb_env_bind_stack(env, name_tok, slot_id, scalar)  
  → binds a name to a stack slot
```

### LowerCtx helpers available

```
mb_ctx_fresh_value(ctx)                     → new value id
mb_ctx_fresh_block(ctx)                     → new block id (if needed)
mb_ctx_push_aux_i32(ctx, val)               → push to ctx.aux_i32
mb_emit_create_block(ctx, blk_id)           → declares a backend block
mb_emit_switch_to_block(ctx, blk_id)        → switches insertion point
mb_emit_append_block_param(ctx, blk, val, shape, scalar, lanes) → adds block param
mb_emit_seal_block(ctx, blk_id)             → seals a block (no more branches)
mb_emit_br_if(ctx, cond, then_blk, then_args_aux, then_count, else_blk, else_args_aux, else_count)
mb_emit_jump(ctx, target_blk, args_aux, count)
mb_emit_switch_int(ctx, val, scalar, cases_aux, n_cases, default_blk)
mb_emit_return_void(ctx)
mb_emit_return_value(ctx, val)
```

## Algorithm

### Binding change detection

`collect_changed_bindings(tree, stmt_list_start, stmt_list_count)`:
- Scan stmts in the list for `ST_SET` where the place is an `EX_REF` (local cell set).
- `expr_tag[place_idx] == 2` (EX_REF) means PlaceRef targeting a local variable.
- Collect the `expr_tok[place_idx]` (name token) for each such set.
- Also recurse into nested IF/switch bodies to find changes there.
- Return a deduplicated array of binding keys (name tokens).
- This is a plain Lua function (not region), returning a Lua table of name_tok keys.

### If statement phi

```
mb_lower_if_stmt(ctx, stmt_idx):
  1. Read ST_IF fields:
     cond = ctx.tree.stmt_name[stmt_idx]
     then_start = ctx.tree.stmt_type[stmt_idx]
     then_count = ctx.tree.stmt_value[stmt_idx]
     else_start = ctx.tree.stmt_body_start[stmt_idx]
     else_count = ctx.tree.stmt_body_count[stmt_idx]
   
  2. mb_lower_expr(ctx, cond) → (cond_val, cond_scalar, ok)
     if !ok: return (BackFallsThrough, ok=false)

  3. Scan then_body (at ctx.tree.stmt_list[then_start] for then_count entries)
     and else_body (at ctx.tree.stmt_list[else_start] for else_count entries, if else_start >= 0)
     for locally-mutated bindings (ST_SET on EX_REF).
     → changed_names: Lua table of name_tok → true

  4. Create backend blocks:
     mb_emit_create_block(ctx, then_blk)     — fresh block id
     mb_emit_create_block(ctx, else_blk)     — fresh block id
     mb_emit_create_block(ctx, join_blk)     — fresh block id

  5. For each changed binding name_tok in changed_names:
     mb_ctx_fresh_value(ctx) → phi_val
     mb_emit_append_block_param(ctx, join_blk, phi_val, 0, scalar, 0)
     — shape_tag=0 (BackShapeScalar), scalar from env_lookup
     Save (name_tok, phi_val, scalar) for later env rebind.

  6. mb_emit_br_if(ctx, cond_val, then_blk, 0, 0, else_blk, 0, 0)
     — conditional branch: cond true → then_blk, false → else_blk
     — args_aux=0, count=0 (block params on entry blocks, not on br_if branches)

  7. Lower then body:
     mb_emit_switch_to_block(ctx, then_blk)
     mb_lower_stmt_list_body(ctx, then_start, then_count) → (flow, ok)
     — mb_lower_stmt_list_body lowers the stmts in ctx.tree.stmt_list from then_start for then_count
     
     If flow != BackTerminates:
       For each changed name_tok:
         mb_env_lookup_into(ctx.env, name_tok, kind, value, scalar)
         If kind == MB_LOCAL_SCALAR: push value to then_args_aux
         If kind == MB_LOCAL_STACK: mb_ctx_fresh_value → load_val, mb_emit_load_info(load_val, scalar, slot_addr, 0, ...), push load_val
       mb_emit_jump(ctx, join_blk, then_args_aux_start, n_changed)

  8. Lower else body (if else_start >= 0):
     mb_emit_switch_to_block(ctx, else_blk)
     mb_lower_stmt_list_body(ctx, else_start, else_count) → (flow, ok)
     
     If flow != BackTerminates:
       For each changed name_tok (same pattern as then):
         env_lookup → push value
       mb_emit_jump(ctx, join_blk, else_args_aux_start, n_changed)

  9. If else_start < 0 (no else clause):
     mb_emit_switch_to_block(ctx, else_blk)
     — else_blk is the fallthrough (empty else)
     For each changed name_tok:
       env_lookup → push value
     mb_emit_jump(ctx, join_blk, args_aux_start, n_changed)

  10. mb_emit_seal_block(ctx, join_blk)
      mb_emit_switch_to_block(ctx, join_blk)

  11. For each saved (name_tok, phi_val, scalar):
      mb_env_bind_scalar(ctx.env, name_tok, phi_val, scalar)

  12. Determine flow:
      - If both branches terminate: return (BackTerminates, ok=true)
      - Else: return (BackFallsThrough, ok=true)
```

### Switch statement phi

```
mb_lower_switch_stmt(ctx, stmt_idx):
  1. Read ST_SWITCH fields:
     value = ctx.tree.stmt_name[stmt_idx]
     arm_start = ctx.tree.stmt_type[stmt_idx]
     arm_count = ctx.tree.stmt_value[stmt_idx]
     default_start = ctx.tree.stmt_body_start[stmt_idx]
     default_count = ctx.tree.stmt_body_count[stmt_idx]
   
  2. mb_lower_expr(ctx, value) → (val, scalar, ok)
     if !ok: return (BackFallsThrough, ok=false)

  3. Collect changed bindings across all arms + default body.
     For each arm a (0..arm_count-1):
       body_start = ctx.tree.switch_arm_body_start[arm_start + a]
       body_count = ctx.tree.switch_arm_body_count[arm_start + a]
       scan stmt_list[body_start .. body_start+body_count-1] for ST_SET on EX_REF
     Default: scan same way

  4. Create arm blocks + default block + join block.
     arm_blk_ids: array of fresh block ids (one per arm)
     default_blk = fresh block id
     join_blk = fresh block id

  5. For each changed binding:
     mb_ctx_fresh_value(ctx) → phi_val
     mb_emit_append_block_param(ctx, join_blk, phi_val, 0, scalar, 0)
     Save (name_tok, phi_val, scalar)

  6. Build cases_aux for mb_emit_switch_int:
     For each arm a:
       key_expr = ctx.tree.switch_arm_key[arm_start + a]
       mb_lower_expr(ctx, key_expr) → (key_val, key_scalar, ok)
       if !ok: return (BackFallsThrough, ok=false)
       mb_ctx_push_aux_i32(ctx, key_val)
       mb_ctx_push_aux_i32(ctx, arm_blk_ids[a])
     → cases_aux = starting index, n_cases = arm_count

  7. mb_emit_switch_int(ctx, val, scalar, cases_aux, n_cases, default_blk)

  8. For each arm a:
     mb_emit_switch_to_block(ctx, arm_blk_ids[a])
     body_start = ctx.tree.switch_arm_body_start[arm_start + a]
     body_count = ctx.tree.switch_arm_body_count[arm_start + a]
     mb_lower_stmt_list_body(ctx, body_start, body_count) → (flow, ok)
     If flow != BackTerminates:
       collect current values for changed bindings
       mb_emit_jump(ctx, join_blk, args_aux, n_changed)

  9. Default arm:
     mb_emit_switch_to_block(ctx, default_blk)
     mb_lower_stmt_list_body(ctx, default_start, default_count) → (flow, ok)
     If flow != BackTerminates:
       collect current values → mb_emit_jump(ctx, join_blk, args_aux, n_changed)

  10. mb_emit_seal_block(ctx, join_blk)
      mb_emit_switch_to_block(ctx, join_blk)

  11. For each saved (name_tok, phi_val, scalar):
      mb_env_bind_scalar(ctx.env, name_tok, phi_val, scalar)

  12. Determine flow as with if statement.
```

### Env lookup for current values

After lowering a branch body, for each changed binding:
```
kind, value, scalar = mb_env_lookup_into(ctx.env, name_tok)
```
- If `kind == MB_LOCAL_SCALAR` → the current value ID is in `value`.
- If `kind == MB_LOCAL_STACK` → emit load from stack slot:
  ```
  mb_emit_stack_addr(ctx, slot_addr, slot_id)
  mb_emit_load_info(ctx, loaded_val, 0, scalar, 0, 0, slot_addr, 0, 0, 0, 0, 0, 0, 0, 0)
  push loaded_val to args_aux
  ```
- If not found → skip (binding unchanged in this branch, use original phi's env binding)

### Stmt list body lowering

`mb_lower_stmt_list_body(ctx, body_start, body_count)`:
- The body is a range of the flat `stmt_list` array at indices body_start..body_start+body_count-1.
- For each stmt_idx = ctx.tree.stmt_list[body_start + offset]:
  - Dispatch on `ctx.tree.stmt_tag[stmt_idx]` to lower each stmt
- Track whether the previous stmt terminated (BackTerminates).
- If any stmt terminates, remaining stmts in the range are dead code (skip).
- Return (flow, ok) where flow is the flow of the last non-dead stmt.

### Dispatch integration

In `stmt_lower.mlua`, the main `mb_lower_stmt_region` dispatcher currently handles these case tags. Wire the new functions:

| New function | Replaces case tag | Signature |
|---|---|---|
| `mb_lower_if_stmt` | `case ST_IF` | `(ctx, stmt_idx) → (flow, ok)` |
| `mb_lower_switch_stmt` | `case ST_SWITCH` | `(ctx, stmt_idx) → (flow, ok)` |

The existing ST_SET handler should remain but be checked: it must handle the SSA rebind case where the place is an EX_REF with MB_LOCAL_SCALAR binding.

## Wire format for branch commands

From `BACK_WIRE_FORMAT.md` and `back_command_binary.lua`:

- **CmdBrIf** slot layout: cond, then_blk, then_args_aux, then_count, else_blk, else_args_aux, else_count
- **CmdJump** slot layout: target_blk, args_aux, count
- **CmdSwitchInt** slot layout: val, scalar, cases_aux, n_cases, default_blk
  - cases_aux points to pairs: (key_val, target_blk) for each case
- **CmdAppendBlockParam** slot layout: block_id, value, shape_tag, scalar, lanes
  - shape_tag=0 for scalar, scalar=BackI32/BackIndex/etc., lanes=0

## Stmt dispatch update pattern

```
-- In stmt_lower.mlua imports:
local mb_lower_if_stmt = M.mb_lower_if_stmt
local mb_lower_switch_stmt = M.mb_lower_switch_stmt

-- In the main switch block:
case @{T.ST_IF} then
    local flow: i32; local ok: bool
    emit mb_lower_if_stmt(ctx, idx, flow, ok)
    if ok then mb_last_flow = flow end
    jump done(flow = flow, ok = ok)

case @{T.ST_SWITCH} then
    local flow: i32; local ok: bool
    emit mb_lower_switch_stmt(ctx, idx, flow, ok)
    if ok then mb_last_flow = flow end
    jump done(flow = flow, ok = ok)
```

## What to wire where

| New function | Lives in | Called from |
|---|---|---|
| `mb_lower_if_stmt` | `stmt_lower.mlua` | main stmt dispatcher for ST_IF |
| `mb_lower_switch_stmt` | `stmt_lower.mlua` | main stmt dispatcher for ST_SWITCH |
| `collect_changed_bindings` | `stmt_lower.mlua` | `mb_lower_if_stmt`, `mb_lower_switch_stmt` |
| `mb_lower_stmt_list_body` | `stmt_lower.mlua` | branch lowering in if/switch |

## Hard bans

- No raw command packing — use `mb_emit_create_block`, `mb_emit_switch_to_block`, `mb_emit_br_if`, `mb_emit_jump`, `mb_emit_switch_int`, `mb_emit_append_block_param`, `mb_emit_seal_block`
- No `LowerState` — only `MomBackLowerCtx`
- No `CmdTrap` fallbacks
- No `TODO`/`FIXME`/`placeholder`/`simplified`
- No assuming branches always fall through — check `BackTerminates` before emitting jump to join
- Must read stmt fields from `ctx.tree.stmt_*` arrays — not hardcoded values
- Switch arms must be read from `switch_arm_key/body_start/body_count` — not stmt body fields
- No hardcoded 0 aux counts where actual values are needed
- No `@malloc` or hidden allocation — use `ctx.aux_i32` for aux arrays, Lua tables for changed_names
