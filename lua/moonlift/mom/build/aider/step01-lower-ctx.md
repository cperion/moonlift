# Step 1: MomBackLowerCtx struct

Create `lua/moonlift/mom/back/lower_ctx.mlua` — the typed lowering context.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every function complete.**



## Pattern
```moonlift
return function(M)
  -- local type aliases
  -- struct definition
  -- helper functions
  -- exports on M
  return M
end
```

All exports use `mb_` prefix.

## Struct fields

From `port_map.lua` lines 128-139 and `compile_source.mlua` lines 622-627:

| Field | Type | Source |
|-------|------|--------|
| `tree` | `ptr(MomTreeOut)` | materialized AST from parser |
| `expr_type` | `ptr(i32)` | typecheck result per expr index |
| `expr_scalar` | `ptr(i32)` | typecheck result per expr index |
| `type_size` | `ptr(i32)` | layout phase: byte size per type index |
| `type_align` | `ptr(i32)` | layout phase: byte alignment per type index |
| `field_offset` | `ptr(i32)` | layout phase: byte offset per struct field index |
| `field_size` | `ptr(i32)` | layout phase: byte size per struct field index |
| `item_size` | `ptr(i32)` | layout phase: byte size per named item index |
| `item_align` | `ptr(i32)` | layout phase: byte alignment per named item index |
| `env` | `ptr(MomBackLocalEnv)` | local binding environment from `env.mlua` |
| `ids` | `ptr(MomBackIdAllocator)` | value/block/access/slot ID allocator from `ids.mlua` |
| `cmd_buffer` | `ptr(MomCmdBuffer)` | command output buffer from `builders.mlua` |
| `aux_i32` | `ptr(MomI32Builder)` | auxiliary i32 value list builder |
| `string_pool_count` | `i32` | string pool entries (driver-managed) |
| `symbol_pool_count` | `i32` | symbol pool entries (driver-managed) |
| `current_module_id` | `i32` | module name string pool id |
| `current_func_id` | `i32` | function name string pool id |
| `current_return_mode` | `i32` | 0=scalar, 1=void, 2=view |
| `issues` | `ptr(MomIssueBuilder)` | diagnostic issue writer from `builders.mlua` |

The struct must be flat (no nested allocation), all `i32` or `ptr(i32)` for FFI compat.

## Init function

```moonlift
mb_ctx_init(ctx: ptr(MomBackLowerCtx),
  tree: ptr(MomTreeOut),
  expr_type: ptr(i32), expr_scalar: ptr(i32),
  type_size: ptr(i32), type_align: ptr(i32),
  field_offset: ptr(i32), field_size: ptr(i32),
  item_size: ptr(i32), item_align: ptr(i32),
  env: ptr(MomBackLocalEnv),
  ids: ptr(MomBackIdAllocator),
  cmd_buffer: ptr(MomCmdBuffer),
  aux_i32: ptr(MomI32Builder),
  issues: ptr(MomIssueBuilder)) -> void
```

Sets all pointer fields, zeros all i32 fields.

## Reset function (per-function reuse)

```moonlift
mb_ctx_reset_func(ctx: ptr(MomBackLowerCtx), func_id: i32, return_mode: i32) -> void
```

- Calls `mb_env_reset(ctx.env)` and `mb_ids_reset_func(ctx.ids)`
- Sets `ctx.current_func_id = func_id`
- Sets `ctx.current_return_mode = return_mode`
- Preserves tree, type arrays, buffers (they don't change per function)

## Module setter

```moonlift
mb_ctx_set_module(ctx: ptr(MomBackLowerCtx), module_id: i32) -> void
```

## Fresh ID allocators

```moonlift
mb_ctx_fresh_value(ctx) -> i32    # delegates to mb_fresh_value(ctx.ids)
mb_ctx_fresh_block(ctx) -> i32    # delegates to mb_fresh_block(ctx.ids)
mb_ctx_fresh_access(ctx) -> i32   # delegates to mb_fresh_access(ctx.ids)
mb_ctx_fresh_slot(ctx) -> i32     # delegates to mb_fresh_slot(ctx.ids)
```

## Aux helper

```moonlift
mb_ctx_push_aux_i32(ctx: ptr(MomBackLowerCtx), value: i32) -> i32
```

Calls `mr_i32_builder_push(ctx.aux_i32, value)` and returns the index.

## Overflow check

```moonlift
mb_ctx_overflowed(ctx: ptr(MomBackLowerCtx)) -> bool
```

Returns true if any of `cmd_buffer`, `aux_i32`, `issues`, or `env` have overflowed.

## Hard bans

- No `TODO`/`FIXME`/`placeholder`/`simplified`/`not-yet`/`for-now` comments
- No `@malloc` or hidden allocation
- No fake continuation args
- All fields `i32` or `ptr(i32)` only
- Struct is flat, no nested allocation (no `struct` inside `struct`)
- No extra fields beyond what's listed in the table above
- Every function must be exported on `M`
- Return `M` at end of file
