## SponJIT Foundry SSA — Optimization Headroom

The SSA is the foundry's brain. Better SSA → more optimizations discovered
→ more high-quality copy-and-patch artifacts. This document tracks what each
pass buys and what's next.

### Current passes

| Pass | What it eliminates | Impact |
|---|---|---|
| `copy_forward` | MOVE chains | redundant value copies |
| `box_unbox` | box_i64(unbox_i64(x)) | redundant tag conversions |
| `store_load_forward` | store_slot(x); load_slot | redundant frame round-trips |
| `guard_dedupe` | duplicate guards | redundant checks across atom boundaries |
| `DCE` | unused pure values | dead computation |

### Fact vocabulary

| Domain | Current facts | Missing |
|---|---|---|
| Numeric | `lhs_i64`, `rhs_i64` | `result_in_rcx` (residency), `constant_value` |
| Table | `shape_known`, `metatable_absent`, `key_const` | `field_offset_known`, `no_metamethods` |
| Array | `array_hit`, `key_i64` | `array_bounds_known`, `index_constant` |
| Call | `known_call_target` | `call_is_leaf`, `nargs_known` |
| Barrier | `barrier_clean` | `gc_phase_known` |
| Control | `returns_prev`, `loop_backedge` | `branch_direction_known` |
| Liveness | — | `result_dead`, `slot_reuse` |
| Residency | — | `value_in_rax`, `value_in_rcx` |

### Next SSA passes (ordered by impact)

1. **Residency propagation** — track which register holds each value.
   Eliminates load_slot when value is already in rax. Eliminates unbox_i64
   when value is already in rcx. Eliminates box_i64 when downstream consumer
   expects native i64.

2. **Liveness-driven store elimination** — when a stored value is never read
   before being overwritten, delete the store. When the result_dead fact holds,
   delete the final store.

3. **Table access fusion** — when `guard_shape + table_field_load` or
   `table_field_load + guard_i64 + add_i64 + box_i64 + table_field_store`
   appear as recognized patterns with the right facts, fuse them into single
   stencils with fewer holes and less guard overhead.

4. **Bounds check elimination** — when `array_bounds_known` fact holds,
   delete `guard_bounds`. When loop index is monotonically increasing and
   upper bound is known, hoist the bounds check out of the loop.

5. **Call specialization** — when `known_call_target` and `call_is_leaf`
   facts hold, inline the callee's first few operations into the caller's
   artifact, eliminating the call boundary overhead.

### What this buys

Each pass that removes a node removes it from the eventual stencil template.
Fewer nodes → smaller artifact, fewer holes, lower runtime cost. The SSA is
the only place where these optimizations happen — the runtime never does them.

### Measurement

After each SSA pass addition, measure:

```sh
luajit experiments/lua_interpreter_vm/spongejit/foundry.lua --max-files 200
```

Compare:
- Unique forms per layer
- Template bytes per layer  
- Nodes per template (avg)
- New forms discovered in L1 vs L0
