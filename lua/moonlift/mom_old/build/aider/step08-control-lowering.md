# Step 8: Control region lowering

Create `lua/moonlift/mom/back/control_lower.mlua` and wire control-region
lowering into statement/function lowering. This step lowers parsed
`block`/`region` control blocks (`MS_CONTROL`, `ME_CONTROL`, `MS_JUMP`,
`MS_YIELD_*`) to backend blocks, block params, jumps, and region-exit blocks.

**Policy: hard rewrite for the touched lowerers. No compatibility shims, no
Lua tables in native lowering, no raw command packing, no `CmdTrap` fallback,
no fake continuation args.**

## Required source-of-truth checks

Before coding, verify these files agree:

1. `lua/moonlift/mom/parser/native_core.mlua` control parsing:
   - `np_parse_control_stmt`
   - `np_parse_control_expr`
   - `np_parse_region_blocks`
   - `np_add_stmt` / `np_add_expr` payload order
2. `lua/moonlift/mom/parser/native_tree.mlua` materialization:
   - parser `ST_*` tags are converted to typed `MS_*` tags
   - expression tags are converted to typed `ME_*` tags
   - `MomTreeOut.counts` layout
3. Hosted oracle:
   - `lua/moonlift/tree_control_to_back.lua`
   - control-related cases in `lua/moonlift/tree_to_back.lua`
4. Language semantics:
   - `LANGUAGE_REFERENCE.md` control-region section
   - `PROTOCOL_SYNTAX.md` for named exits/continuations

## Typed tree facts that must be used

After materialization, lowerers consume `MomTreeOut`, not parser-private tags.
Use these generated constants:

- Expressions: `T.ME_CONTROL`, `T.ME_*`
- Statements: `T.MS_CONTROL`, `T.MS_JUMP`, `T.MS_YIELD_VOID`,
  `T.MS_YIELD_VALUE`, `T.MS_RETURN_VOID`, `T.MS_RETURN_VALUE`, etc.
- Types: `T.MT_SCALAR`, `T.MT_PTR`, `T.MT_VIEW`, etc.

Do **not** use parser `ST_*` or `EX_*` constants in this lowerer.

### `MomTreeOut.counts` indices

From `native_tree.mlua`:

```
counts[0]  = type count
counts[1]  = expr count
counts[2]  = stmt count
counts[3]  = item count
counts[4]  = param count
counts[5]  = field count
counts[6]  = jump arg count
counts[7]  = expr list count
counts[8]  = stmt list count
counts[9]  = type list count
counts[10] = switch arm count
counts[11] = control block count
counts[12] = entry param count
```

## Control tree encoding

### Control region expression: `ME_CONTROL`

Produced by `np_parse_control_expr`:

```
expr_tag[idx]  = T.ME_CONTROL
expr_tok[idx]  = token index
expr_op[idx]   = result type index (0 or negative means void/no scalar result)
expr_lhs[idx]  = ctrl_start, index into ctrl_block_* arrays
expr_rhs[idx]  = parser-local count; currently 1 for inline block/region expr
expr_aux0[idx] = 0
```

For item-level `region` declarations, control blocks are stored in item fields:

```
item_tag[i]        = IT_REGION
item_body_start[i] = ctrl_start
item_body_count[i] = ctrl_count
```

### Control region statement: `MS_CONTROL`

Produced by `np_parse_control_stmt` and materialized to `MS_CONTROL`:

```
stmt_name[i]       = entry label token
stmt_type[i]       = entry_param_start
stmt_value[i]      = entry_param_count
stmt_body_start[i] = ctrl_start
stmt_body_count[i] = parser-local count; currently 1 for inline block stmt
```

### Control block arrays

```
ctrl_block_label[ctrl_start + b]       = label token
ctrl_block_param_start[ctrl_start + b] = entry_param_* start for b=0, param_* start otherwise
ctrl_block_param_count[ctrl_start + b] = number of block params
ctrl_block_body_start[ctrl_start + b]  = stmt_list start
ctrl_block_body_count[ctrl_start + b]  = stmt_list count
```

Entry block is always block index `0` within a region. There is no
`ctrl_block_entry_flag`.

Entry block params use:

```
entry_param_name/type/init
```

Non-entry block params use:

```
param_name/type
```

There is no initializer for non-entry params.

### Jump statements

`MS_JUMP` payload:

```
stmt_name[idx]  = target block label token
stmt_type[idx]  = jump_arg_start
stmt_value[idx] = jump_arg_count
```

Jump args are:

```
jump_arg_name[jump_arg_start + i]
jump_arg_expr[jump_arg_start + i]
```

Resolve jump targets by integer token equality against `ctrl_block_label`.

## New helpers in `back/control.mlua`

Add exported pure/native helpers:

```moonlift
mb_control_find_block_by_label(tree: ptr(MomTreeOut), ctrl_start: i32, n_blocks: i32, label_tok: i32) -> i32
mb_control_block_param_start(tree: ptr(MomTreeOut), ctrl_start: i32, block_idx: i32) -> i32
mb_control_block_param_count(tree: ptr(MomTreeOut), ctrl_start: i32, block_idx: i32) -> i32
mb_control_block_param_name(tree: ptr(MomTreeOut), ctrl_start: i32, block_idx: i32, param_i: i32) -> i32
mb_control_block_param_type(tree: ptr(MomTreeOut), ctrl_start: i32, block_idx: i32, param_i: i32) -> i32
mb_control_type_to_scalar(ctx: ptr(MomBackLowerCtx), type_idx: i32) -> i32
```

Rules:

- `block_idx == 0` reads `entry_param_*` arrays.
- `block_idx > 0` reads `param_*` arrays.
- Scalar conversion must use existing backend type helpers (`mb_type_to_back_scalar`
  or equivalent), not raw `type_scalar` alone.

Do **not** build maps/tables. Linear scans are fine.

## New module: `back/control_lower.mlua`

### Exported entrypoints

```moonlift
mb_lower_control_expr(ctx: ptr(MomBackLowerCtx), expr_idx: i32)
  -> value: i32, scalar: i32, ok: bool

mb_lower_control_stmt(ctx: ptr(MomBackLowerCtx), stmt_idx: i32)
  -> flow: i32, ok: bool

mb_lower_control_region(ctx: ptr(MomBackLowerCtx), ctrl_start: i32, n_blocks: i32,
                        is_expr: bool, result_scalar: i32)
  -> value: i32, flow: i32, ok: bool

mb_lower_control_stmt_in_region(ctx: ptr(MomBackLowerCtx), stmt_idx: i32,
                                ctrl_start: i32, n_blocks: i32,
                                block_ids_aux: i32, exit_blk: i32,
                                is_expr: bool, result_scalar: i32)
  -> flow: i32, ok: bool

mb_lower_control_stmt_list(ctx: ptr(MomBackLowerCtx), body_start: i32, body_count: i32,
                           ctrl_start: i32, n_blocks: i32,
                           block_ids_aux: i32, exit_blk: i32,
                           is_expr: bool, result_scalar: i32)
  -> flow: i32, ok: bool
```

Use local constants in the file:

```
BackFallsThrough = 0
BackTerminates   = 1
```

Do not rely on nonexistent generated `T.BackTerminates` tags.

## Correct lowering algorithm

### Region setup

`mb_lower_control_expr`:

1. Assert/dispatch `ctx.tree.expr_tag[expr_idx] == T.ME_CONTROL`.
2. `ctrl_start = ctx.tree.expr_lhs[expr_idx]`.
3. Determine `n_blocks`:
   - For inline `ME_CONTROL`, `expr_rhs` is currently parser-local and may be `1`.
   - Use `expr_rhs` if it is greater than `1`.
   - Otherwise conservatively use `ctx.tree.counts[11] - ctrl_start`, but stop at first zero label if encountered.
4. `result_scalar = ctx.expr_scalar[expr_idx]`; if zero, use `T.BackVoid`.
5. Call `mb_lower_control_region(..., is_expr=true, result_scalar)`.

`mb_lower_control_stmt`:

1. Assert/dispatch `ctx.tree.stmt_tag[stmt_idx] == T.MS_CONTROL`.
2. `ctrl_start = ctx.tree.stmt_body_start[stmt_idx]`.
3. Determine `n_blocks` using `stmt_body_count` if greater than `1`, otherwise the same conservative count rule.
4. Call `mb_lower_control_region(..., is_expr=false, result_scalar=T.BackVoid)`.

### Block creation and exit block

Inside `mb_lower_control_region`:

1. Reserve an aux segment for backend block ids:
   - `block_ids_aux = ctx.aux_i32.len`
   - for each control block: fresh block id, push to aux, emit `mb_emit_create_block`.
2. Always create a region exit block:
   - `exit_blk = fresh block`, emit `mb_emit_create_block`.
   - If `is_expr`, create `result_val = fresh value` and emit
     `mb_emit_append_block_param(exit_blk, result_val, scalar shape, result_scalar, 0)`.
   - If statement region, exit block has no params.
3. Append block params for every control block before lowering any body:
   - for each block param: fresh value id, emit `mb_emit_append_block_param(block_id, param_val, scalar shape, scalar, 0)`.
   - Store param value ids in a second aux segment in block-major order, or recompute through a deterministic aux layout.

### Entry initializer trampoline

The current insertion block is the block that contains the control expression or
statement. Do not switch to the entry block before lowering initializers.

1. Lower every entry param initializer expression in the current block.
2. Push initializer values to `ctx.aux_i32`.
3. Emit `mb_emit_jump(ctx, entry_block_id, init_args_aux, entry_param_count)`.
4. Then switch to each region block and lower its body.

This is the key distinction:

- `mb_emit_append_block_param` defines a block parameter.
- `mb_emit_jump` supplies runtime arguments to those parameters.

Do not append entry params twice.

### Per-block body lowering

For each control block `b`:

1. `mb_emit_switch_to_block(ctx, block_id)`.
2. Mark env: `mark = mb_env_mark(ctx.env)`.
3. Bind block params into env using the already-created param value ids:
   - entry params from `entry_param_name/type`
   - non-entry params from `param_name/type`
4. Lower `ctrl_block_body_start/count` with `mb_lower_control_stmt_list`.
5. If body flow is not terminating, this is invalid for a control block; return `ok=false`.
6. Truncate env to mark.

After all blocks are lowered, seal all region blocks and the exit block.
Finally switch to the exit block. Return:

- expression region: `(result_val, BackFallsThrough, true)`
- statement region: `(0, BackFallsThrough, true)`

### Statement dispatch inside a region

`mb_lower_control_stmt_in_region` dispatches on `MS_*` tags.

#### `T.MS_JUMP`

1. Resolve target label by linear scan.
2. For each jump arg:
   - `arg_expr = jump_arg_expr[arg_start + i]`
   - lower `arg_expr` via `mb_lower_expr_region`
   - push value to aux
3. Emit `mb_emit_jump(ctx, target_block_id, args_aux, arg_count)`.
4. Return `BackTerminates`.

Do not use jump arg names as values. Names are for checking/protocol matching;
the expression payload supplies the runtime value.

#### `T.MS_YIELD_VALUE`

Only valid for expression regions.

1. Lower `stmt_name[stmt_idx]` via `mb_lower_expr_region`.
2. Push value as the single exit-block arg.
3. Emit `mb_emit_jump(ctx, exit_blk, args_aux, 1)`.
4. Return `BackTerminates`.

Do **not** emit `CmdReturnValue` for yield.

#### `T.MS_YIELD_VOID`

Only valid for statement/void regions.

1. Emit `mb_emit_jump(ctx, exit_blk, 0, 0)`.
2. Return `BackTerminates`.

Do **not** emit `CmdReturnVoid` for yield.

#### `T.MS_RETURN_VOID` / `T.MS_RETURN_VALUE`

These are function returns inside a region; emit `CmdReturn*` and return
`BackTerminates`.

#### Normal statements

Delegate to existing scalar statement lowerer for:

- `MS_LET`
- `MS_VAR`
- `MS_SET`
- `MS_EXPR`

The existing lowerer must not dispatch `MS_JUMP`/`MS_YIELD_*` outside this
region context.

#### `MS_IF` / `MS_SWITCH`

If Step 7 phi lowering exists and is correct, delegate to it. Otherwise return
`ok=false`. Do not produce fake branch lowering.

#### Nested `MS_CONTROL`

Lower recursively through `mb_lower_control_stmt` or return `ok=false` if the
current implementation cannot preserve nested-region exit semantics.

## Integration requirements

1. `expr_lower.mlua`:
   - Add `case T.ME_CONTROL` -> `mb_lower_control_expr`.
2. `stmt_lower.mlua`:
   - Add `case T.MS_CONTROL` -> `mb_lower_control_stmt`.
   - Do not handle `MS_JUMP`/`MS_YIELD_*` outside a control region; return `ok=false`.
3. `func.mlua`:
   - Function body lowering must use `mb_lower_stmt_list` normally.
   - If the first body statement is `MS_CONTROL`, the statement dispatcher handles it; do not special-case with fake returns.
4. `build/manifest.lua`:
   - Add `lua/moonlift/mom/back/control_lower.mlua` after `stmt_lower.mlua` or after dependencies are loaded.

## Tests to add/run

Add focused tests under `tests/`:

1. Control expression with value yield:

```moonlift
func main() -> i32
    return block loop(i: i32 = 0, acc: i32 = 0)
        if i >= 4 then yield acc end
        jump loop(i = i + 1, acc = acc + 1)
    end
end
```

2. Control statement with void yield in a void function.
3. Jump target resolution failure should return native error/status, not emit invalid commands.
4. Entry block params are initialized via a jump arg, not by duplicate block params.

Run:

```
luajit scripts/emit_mom_precompiled.lua
luajit tests/test_mom_run_2plus2.lua
luajit tests/test_mom_control_lower.lua
luajit scripts/check_mom_hygiene.lua
```

Existing repository-wide hygiene may still report known schema/vector issues;
new touched files must not add new hygiene failures.
