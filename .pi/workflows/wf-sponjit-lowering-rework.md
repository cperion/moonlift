# SponJIT full fact-consuming lowering rework 
Plan and implement a complete rework of spongejit SSA lowering so opcode semantics + facts produce specialized C/stencil code instead of shallow GenericExit ladders.
**Started**: 2026-05-28 16:22:33
---

## Planner Output — 2026-05-28 16:29:56

## Goal
Rework SponJIT SSA lowering so typed facts drive rich semantic SSA and lowerable C stencils while preserving the current `grammar_enum -> worker_compile -> ssa.compile -> ssa_to_c.generate -> GCC -> build_bank` pipeline.

## Plan

1. Baseline and freeze current failures:
   - Run from `experiments/lua_interpreter_vm/spongejit`:
     - `luajit test_ssa_to_c.lua`
     - `N=2 ./build_stencils.sh` if feasible
   - Record current `GenericExit` counts and stale test failures for comparison.

2. Add one shared fact-axis source:
   - Create `src/ssa_fact_axes.lua`.
   - Move opcode-to-fact-axis logic out of both `src/grammar_enum.lua` and `src/worker_compile.lua`.
   - Use exact opcode lookup tables, not Lua `string.match("|")`.
   - Include axes for:
     - i64 arithmetic/comparison: `is_i64`
     - table field/array access: `is_table`, `shape_known`, `metatable_absent`, `key_i64`, `array_hit`, `bounds_ok`
     - calls: `known_call_target`
     - stores: `barrier_clean`
     - constants: `key_const`, `const_i64` where applicable.

3. Wire shared axes into enumeration/build:
   - In `src/grammar_enum.lua`, replace local `fact_axes_for_ops` and `fact_subsets` with `ssa_fact_axes`.
   - In `src/worker_compile.lua`, delete duplicated `axes_lookup`, `patterns`, `fact_axes`, `fact_subsets`; call `FactAxes.axes_for_ops()` and `FactAxes.subsets()`.
   - In `src/enumerate.lua`, either delegate `fact_axes_for_ops` to `ssa_fact_axes` or keep corpus extras but merge shared axes first.

4. Fix fact subject compatibility:
   - In `src/facts.lua`, keep legacy strings but add helpers/aliases so `lhs_i64`, `rhs_i64`, `table`, `key_i64`, `known_call_target`, etc. can satisfy slot-based lowering when used with opcode roles.
   - In `src/ssa_lift.lua`, replace `has_slot_fact` with a helper that checks:
     - exact slot subject: `slot:Rn`
     - role subject: `value:lhs`, `value:rhs`, `value:table`, `value:key`, `value:callee`
     - global facts for `barrier_clean`
   - This makes existing tests using legacy facts lower richly again.

5. Expand SSA IR where needed:
   - In `src/ssa_ir.lua`, add/adjust helpers:
     - `guard_table(value, fact, pc)`
     - `guard_shape(table_value, fact, pc)`
     - `guard_metatable_absent(table_value, fact, pc)`
     - `guard_array_hit(table_value, index_value, fact, pc)`
     - `guard_bounds(table_value, index_value, fact, pc)`
     - `guard_call_target(callee_value, fact, pc)`
     - `field_load(table_value, key, pc)` with `args.key`
     - `field_store(table_value, key, value, pc)`
     - `array_load(table_value, index_value, pc)`
     - `array_store(table_value, index_value, value, pc)`
     - optional guards: `GuardNonZeroI64`, `GuardShiftRange`
   - Update `CODEGEN_OP`, `PURE_OP`, and validation names for any new nodes.

6. Rework `src/ssa_lift.lua` into fact-consuming opcode lowerers:
   - Keep the public `M.lift(ops, facts, config)` API unchanged.
   - Add helpers:
     - `slot(slot_no)`
     - `load_tvalue(g, slot_no, pc)`
     - `i64_from_slot(g, slot_no, role, pc)`
     - `table_from_slot(g, slot_no, role, pc)`
     - `const_i64_operand(g, ev, operand_name, pc)`
     - `store_i64(g, value, dst_slot, pc)`
     - `store_tvalue(g, value, dst_slot, pc)`
   - Arithmetic:
     - Fully lower `ADD/SUB/MUL/DIV/MOD/IDIV/BAND/BOR/BXOR/SHL/SHR`.
     - Fully lower `ADDI/SHLI/SHRI`.
     - Lower `ADDK/SUBK/...` when constant facts exist; otherwise use structured `GenericExit`.
     - Add guards for division-by-zero and unsafe shift counts.
   - Unary:
     - Lower `UNM`, `BNOT`.
     - Lower `NOT` as bool-ish TValue result if truthiness fact exists; otherwise `GenericExit`.
     - Keep `LEN` generic until table/string length facts exist.
   - Comparisons:
     - Lower `EQ/LT/LE/EQI/LTI/LEI/GTI/GEI` with i64 facts.
     - Lower `EQK` with constant facts.
     - Emit `CmpI64` and store boolean/TValue result or branch node if followed by `JMP`.
   - Loads/moves:
     - Lower `LOADI`, `LOADF`, `LOADTRUE`, `LOADFALSE`, `LFALSESKIP`, `LOADNIL`, `LOADK`, `LOADKX`, `MOVE`.
   - Tables:
     - Lower `GETFIELD/GETTABUP/SELF` when table + shape/metatable facts exist.
     - Lower `GETTABLE/GETI` when table + array/key/bounds facts exist.
     - Lower `SETFIELD/SETTABUP/SETTABLE/SETI` with barrier fact or explicit `BarrierCheck`.
     - Lower `SELF` as field load into `A` and receiver copy into `A+1`.
   - Calls:
     - Lower `CALL/TAILCALL` with `known_call_target` to `GuardCallTarget + KnownCall/TailCall`.
     - Keep unknown calls as structured boundaries, not shallow unannotated exits.
   - Loops/control:
     - Keep `RETURN*` and `JMP`.
     - Add rich i64 variants for `FORPREP/FORLOOP` when `loop_i64`/slot i64 facts exist; otherwise boundary exit.
   - Important: `GenericExit` should mean “missing required fact/unsupported semantic case,” not “backend forgot this node.”

7. Keep optimizer minimal:
   - In `src/ssa_opt.lua`, retain frame forwarding and guard dominance.
   - Add only safe semantic passes:
     - field-load forwarding after same `FieldStore`
     - barrier elimination for `barrier_clean`
   - Do not add scalar arithmetic folding/DCE beyond safe semantic rewrites; let GCC optimize generated C.

8. Harden `src/ssa_to_c.lua`:
   - Replace fixed `__H_0..__H_23` preamble with generated declarations for at least 256 holes.
   - Add `node_count`, `exit_count`, `unlowered_count`, and `holes` compatibility fields to the return table.
   - Add `compile_to_file(ssa_result, path, source_ops, config)` or update tests to stop calling it.
   - Make unhandled SSA nodes an error by default; allow only with `config.allow_unlowered`.
   - Keep `GenericExit` and explicit VM boundary nodes lowerable.

9. Add rich C emitters in `src/ssa_to_c.lua`:
   - Guards:
     - `GuardTable`
     - `GuardShape`
     - `GuardMetatableAbsent`
     - `GuardArrayHit`
     - `GuardBounds`
     - `GuardCallTarget`
     - `GuardNonZeroI64`
     - `GuardShiftRange`
   - Table ops:
     - `FieldLoad`
     - `FieldStore`
     - `ArrayLoad`
     - `ArrayStore`
     - `BarrierCheck`
   - Calls/control:
     - `KnownCall`
     - `TailCall`
     - `Branch`
   - Constants:
     - Fix `ConstBool` to use `args.value`, not a `bool_val` hole.
     - Make `LoadConst` use explicit constant-table/index holes.
   - Emit simple C locals/loads/stores only; rely on GCC `-O2`.

10. Extend hole role metadata:
   - In `src/build_bank.lua`, extend `ROLE_KIND` and `classify_role()` for:
     - `shape_id`
     - `shape_offset`
     - `metatable_offset`
     - `field_offset`
     - `array_base_offset`
     - `array_len_offset`
     - `array_index`
     - `const_base`
     - `const_index`
     - `call_target`
     - `barrier`
   - Keep existing `slot`, `imm`, `const`, `bool`, `exit`, `fail` roles compatible.

11. Expand fact signatures in `src/build_bank.lua`:
   - Current 64-bit signature is too small for richer facts.
   - Change tile descriptors to store two 64-bit words, e.g. `fact_lo`, `fact_hi`.
   - Update selector check from:
     - `(t->fact_sig & ~sig) == 0`
     - to `(t->fact_lo & ~sig_lo) == 0 && (t->fact_hi & ~sig_hi) == 0`
   - Keep old `spon_select_greedy(..., uint64_t sig, ...)` wrapper if needed, but add a new two-word selector entry point.

12. Preserve build pipeline while adding smoke controls:
   - In `build_stencils.sh`, keep the same stages.
   - Add optional env vars:
     - `MAX_ARITY=${MAX_ARITY:-4}`
     - `MAX_FACT_COMBOS=${MAX_FACT_COMBOS:-}` if used by `ssa_fact_axes.subsets`.
   - Use these only for faster tests; default behavior remains full arity 4.

13. Update tests:
   - Fix `test_ssa_to_c.lua` for current/new `ssa_to_c.generate` return shape.
   - Add assertions that these no longer compile to `GENERIC_EXIT` when facts are present:
     - `ADD + RETURN1`
     - `ADDI + RETURN1`
     - `ADDK` with const-i64 fact
     - `GETFIELD + ADDI + SETFIELD`
     - `GETTABLE + ADD + RETURN1`
     - `SELF + CALL` with `known_call_target`
   - Assert generated C contains no `UNLOWERED`.
   - Assert representative generated C compiles with GCC.

14. Add focused smoke tests:
   - New `tests/test_sponjit_fact_axes.lua`
     - checks `ADD`, `GETFIELD`, `SETTABLE`, `CALL`, `FORLOOP` produce expected axes.
   - New `tests/test_sponjit_lowering.lua`
     - checks normal forms and `active_ops`.
   - New `tests/test_sponjit_codegen_compile.lua`
     - writes representative C and runs `gcc -c -O2`.
   - New `tests/test_sponjit_bank_smoke.lua`
     - runs small build with `N=2 MAX_ARITY=2 ./build_stencils.sh && N=2 ./build_bank.sh`.

15. Benchmarks/metrics:
   - Add a small metrics script or extend worker logging to report:
     - total forms
     - forms containing `GenericExit`
     - forms containing `UNLOWERED`
     - rich table forms
     - rich call forms
     - average holes/form
   - Run:
     - `luajit bench_stencil_vs_interp.lua`
     - `luajit bench_real.lua`
     - full `./build_stencils.sh && ./build_bank.sh` once smoke passes.

16. Immediate MVP milestones:
   - MVP 1: fact-axis fix + legacy fact compatibility; `ADD` with facts lowers richly.
   - MVP 2: generated arithmetic C compiles; no stale test API failures.
   - MVP 3: `GETFIELD/SETFIELD` and `GETTABLE/SETTABLE` produce rich SSA and lower to C.
   - MVP 4: `SELF + known CALL` produces rich SSA and lowerable boundary C.
   - MVP 5: full arity-4 build produces bank with zero `UNLOWERED` nodes and sharply reduced `GenericExit` forms.

## Files to Modify

- `experiments/lua_interpreter_vm/spongejit/src/facts.lua` - add role/slot compatibility helpers and richer predicate normalization.
- `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` - use shared fact-axis module; remove broken Lua-pattern alternation.
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` - use shared fact-axis/subset module; keep output JSON/C contract unchanged.
- `experiments/lua_interpreter_vm/spongejit/src/enumerate.lua` - merge/use shared fact axes for corpus enumeration.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` - add guard/table/array/call helper nodes and codegen names.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` - main rework: fact-consuming opcode semantic lowering.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` - keep minimal optimizer; add only safe semantic forwarding/barrier cleanup.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_validate.lua` - validate new node invariants and optionally enforce lowerability.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_normalize.lua` - add names/composite patterns for new rich variants.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_c.lua` - add dynamic hole declarations, rich C emitters, metadata return fields, no-unlowered gate.
- `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` - extend fact signatures and hole role classification.
- `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` - preserve pipeline; add optional smoke env knobs.
- `experiments/lua_interpreter_vm/spongejit/test_ssa_to_c.lua` - update stale expectations and add rich-lowering checks.

## New Files

- `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` - single source for opcode fact axes and fact subset enumeration.
- `experiments/lua_interpreter_vm/spongejit/tests/test_sponjit_fact_axes.lua` - fact-axis regression tests.
- `experiments/lua_interpreter_vm/spongejit/tests/test_sponjit_lowering.lua` - SSA normal-form regression tests.
- `experiments/lua_interpreter_vm/spongejit/tests/test_sponjit_codegen_compile.lua` - generated C compile smoke tests.
- `experiments/lua_interpreter_vm/spongejit/tests/test_sponjit_bank_smoke.lua` - small end-to-end bank build smoke test.

## Risks

- Fact signature expansion can break selector ABI; keep a compatibility wrapper.
- Table/TValue layout is currently simplified; use explicit hole offsets so runtime patching can supply real ABI details later.
- Signed integer C overflow is risky; use `uint64_t`-based arithmetic where possible.
- `GenericExit` must remain valid for missing facts, but `UNLOWERED` should become a hard failure in codegen/tests.
- Full arity-4 builds may get much larger once variants are real; use smoke env knobs during development.
