# SponJIT full fact-consuming lowering rework 
Plan complete SSA lowering rework under experiments/lua_interpreter_vm/spongejit/src preserving grammar_enum -> worker_compile -> ssa.compile -> ssa_to_c.generate -> GCC -> build_bank.
**Started**: 2026-05-28 16:23:30
---

## Scout Output — 2026-05-28 16:27:17

## Files Retrieved

1. `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` (lines 1-128) - Public facade: `SSA.compile()` pipeline is `Lift.lift -> Opt.optimize -> summarize`; returns graph, normal forms, `active_ops`, `active_node_specs`, facts/deps/projection.
2. `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` (lines 1-225) - Current fact-consuming lowering. Main source of `GenericExit` fallback reasons.
3. `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` (lines 1-425) - IR node vocabulary, codegen op names, graph helpers for table/call/residual/generic exits.
4. `experiments/lua_interpreter_vm/spongejit/src/ssa_to_c.lua` (lines 1-380) - Current SSA-to-C lowering. Handles i64/slots/constants/returns/boundaries; table/call-rich nodes fall through to `UNLOWERED`.
5. `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` (lines 1-254) - Optimizer only runs frame forwarding + guard dominance.
6. `experiments/lua_interpreter_vm/spongejit/src/ssa_normalize.lua` (lines 1-226) - Normal-form names and composite pattern expectations for table/call forms that lifter does not currently emit.
7. `experiments/lua_interpreter_vm/spongejit/src/ssa_validate.lua` (lines 1-51) - Validation allows `GenericExit`; no lowerability check is used by worker.
8. `experiments/lua_interpreter_vm/spongejit/src/facts.lua` (lines 1-300) - Typed fact lattice plus legacy string compatibility; legacy facts target `value:lhs`, not real slots.
9. `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` (lines 1-543) - Grammar generation, fact-axis enumeration, `generate_l0_all`.
10. `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 1-147) - Actual build worker: reimplements fact axes, compiles facts, calls `SSAtoC.generate`, writes `/tmp/grammar_*`.
11. `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` (lines 1-543) - Joins worker output with object symbols/relocs; encodes fact signatures and selector tables.
12. `experiments/lua_interpreter_vm/spongejit/src/enumerate.lua` (lines 1-630) - Corpus enumerator and atom expansion path; has a separate, more correct fact-axis implementation for some ops.
13. `experiments/lua_interpreter_vm/spongejit/src/fact_schema.lua` (lines 1-236) - Stale/parallel schema vocabulary; only required by `puc_bytecode.lua`, not by `ssa_lift`.
14. `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua` (lines 1-160) - Reopens active node/codegen op lists; can create table/call IR nodes, but C backend does not lower them.
15. `experiments/lua_interpreter_vm/spongejit/src/stencil_model.lua` (lines 1-269) - Legacy abstract stencil model used by old foundry path, not the current `worker_compile -> ssa_to_c -> GCC` path.
16. `experiments/lua_interpreter_vm/spongejit/src/puc_bytecode.lua` (lines 100-346) - Profiling/fact-key path; imports `fact_schema` but emits string rewrite fact keys.
17. `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` (lines 1-115) - Current intended build pipeline: `grammar_enum -> worker_compile -> GCC -> ld -> stencil_library.json`.
18. `experiments/lua_interpreter_vm/spongejit/build_bank.sh` (lines 1-34) - Bank `.so` build wrapper around `src/build_bank.lua`.
19. `experiments/lua_interpreter_vm/spongejit/Makefile` (lines 1-62) - Stale older targets reference missing `stencils/` directory.
20. `experiments/lua_interpreter_vm/spongejit/test_ssa_to_c.lua` (lines 1-186) - Immediate test is stale and currently crashes against current `ssa_to_c.generate` return shape.

## Key Code

### Main lowering gap: `ssa_lift.lua`

```lua
local function lower_table_or_generic(g, op, pc, ev)
    -- Table fast paths need the concrete Lua Table/TValue ABI before C emission
    -- can be honest. Until then, this is a structured semantic exit, not a fake
    -- lowered path or a bare return.
    return generic_exit(g, op, pc, ev, "table_abi_not_lowered")
end
```

Used for:

```lua
elseif op == "GETTABLE" or op == "GETI" or op == "GETFIELD" or op == "GETTABUP" or op == "SELF" or
       op == "SETTABLE" or op == "SETI" or op == "SETFIELD" or op == "SETTABUP" or op == "NEWTABLE" then
    terminal = lower_table_or_generic(g, op, pc, ev)
```

Call facts are ignored:

```lua
elseif op == "CALL" or op == "TAILCALL" then
    terminal = generic_exit(g, op, pc, ev, "call_boundary")
else
    terminal = generic_exit(g, op, pc, ev, "opcode_not_specialized")
end
```

Constant-table numeric ops explicitly exit:

```lua
elseif BIN_K[op] then
    return generic_exit(g, op, pc, ev, "constant_numeric_operand")
```

Unary `NOT`/`LEN` are in dispatch but rejected inside unary lowering:

```lua
local function lower_i64_unary(g, op, pc, ev)
    if op ~= "UNM" and op ~= "BNOT" then return generic_exit(g, op, pc, ev, "generic_unary") end
```

### Fact-axis bug: Lua patterns using `|`

`grammar_enum.lua` and `worker_compile.lua` use Lua `string.match` as if it supported regex alternation:

```lua
if n:match("^ADD$|^SUB$|^MUL$|^DIV$|^MOD$|^POW$|^IDIV$") or
   n:match("^BAND$|^BOR$|^BXOR$|^SHL$|^SHR$") or
   n:match("^MMBIN$") then
```

Lua patterns do **not** treat `|` as alternation. Result: many expected axes are never emitted. Observed directly: single-op `ADD` got zero fact axes and compiled to `GENERIC_EXIT`.

`worker_compile.lua` repeats the same issue:

```lua
local patterns = {
  {"^ADD$|^SUB$|^MUL$|^DIV$|^MOD$|^POW$|^IDIV$|^BAND$|^BOR$|^BXOR$|^SHL$|^SHR$|^MMBIN$", "binop_rr"},
  ...
}
...
if n:match(pat[1]) then
```

### Fact subject mismatch

Legacy strings in `facts.lua` map to symbolic values, not opcode slots:

```lua
lhs_i64 = function() return M.fact("type", M.value("lhs"), "is_i64", nil, "observed") end,
rhs_i64 = function() return M.fact("type", M.value("rhs"), "is_i64", nil, "observed") end,
table = function() return M.fact("type", M.value("table"), "is_table", nil, "observed") end,
```

But `ssa_lift.lua` requires slot subjects:

```lua
local function i64_value_if_fact(g, slot, role, pc)
    local ok, subj = has_slot_fact(g, slot, "is_i64")
```

Observed: `SSA.compile({ADD...}, {"lhs_i64","rhs_i64"})` returns `GENERIC_EXIT`; explicit `{subject=Facts.slot("R0")}`/`R1` facts lower to rich i64 SSA.

### C backend gaps

`ssa_to_c.lua` handles:

- `FrameLoad`, `FrameStore`
- `GuardTypeI64`
- `UnboxI64`, `BoxI64`
- `AddI64`, `SubI64`, `MulI64`, `I64BinOp`, `I64UnaryOp`, `CmpI64`
- `ConstI64`, `ConstNil`, `ConstBool`, `Move`, `LoadConst`
- `GenericExit`/`Residual`
- `Jump`, `Return*`, `Call`/`KnownCall`/`TailCall` as boundary exits

Everything else falls to:

```lua
else
    local role = "unlowered_" .. tostring(op)
    local h = holes:alloc(role, (n.source or 1) - 1)
    emit(string.format("    ((void(*)(void*))__H_%d)(stack); return; /* UNLOWERED: %s */", h, op))
end
```

Notably no direct C cases for:

- `GuardTable`
- `GuardShape`
- `GuardMetatableAbsent`
- `GuardCallTarget`
- `GuardArrayHit`
- `GuardBounds`
- `FieldLoad`, `FieldStore`
- `ArrayLoad`, `ArrayStore`
- `BarrierCheck`
- rich `KnownCall`

### Stale test interface

`test_ssa_to_c.lua` expects fields/methods no longer returned by `ssa_to_c.generate`:

```lua
result.node_count, result.exit_count,
table.concat(result.holes, ", ")
...
local ok, err = SSAtoC.compile_to_file(r, path)
```

Current `ssa_to_c.generate` returns only:

```lua
{
    c_code = ...,
    func_name = func_name,
    hole_catalog = holes:catalog(),
    hole_count = holes:count(),
    n_absorbed = #source_ops,
}
```

Observed run:

```text
exit=1
NF: GENERIC_EXIT ops: generic_exit
...
luajit: test_ssa_to_c.lua:28: bad argument #1 to 'concat' (table expected, got nil)
```

## Relationships

Current intended pipeline:

```text
build_stencils.sh
  -> Grammar.generate_all(4)
  -> Grammar.generate_l0_all()
  -> write /tmp/grammar_chunk_N.json
  -> src/worker_compile.lua
       -> fact_axes()
       -> fact_subsets()
       -> SSA.compile(ops, facts, {})
            -> ssa_lift.lift()
            -> ssa_opt.optimize()
            -> ssa_normalize/summarize()
       -> SSAtoC.generate(r, ops, {facts=facts})
       -> /tmp/grammar_c_code_N.c
       -> /tmp/grammar_holes_N.json
       -> /tmp/grammar_result_N.json
  -> gcc each chunk
  -> ld -r build/cp_lib/stencils.o
  -> stencil_library.json
build_bank.sh
  -> objcopy/nm
  -> src/build_bank.lua
       -> load grammar_result/hole JSON
       -> encode fact signatures
       -> classify hole roles
       -> emit libsponbank.c
  -> gcc shared libsponbank.so
```

Important data-flow facts:

- Fact signatures in `build_bank.lua` encode only predicates in `PRED` and slots `< 8`.
- `worker_compile.lua` dedupes by `normal_form_hash | op_signature(ops)`, not facts alone.
- `SSA.compile` treats `GenericExit` as valid/ok; worker emits C for it.
- `ssa_to_c.lua` turns `GenericExit` into an exit-hole call, so generic forms become real selectable tiles.
- Selector chooses by pattern and required fact subset: `if (t && ((t->fact_sig & ~sig) == 0))`.

## Observations

- Concrete observed single-op L0 status with “max facts” from current worker-like axes:
  - `72 / 85` concrete PUC opcodes compile to `GENERIC_EXIT`.
  - Non-generic: `ADDI`, `SHLI`, `SHRI`, `LOADI`, `LOADK`, `LOADTRUE`, `LOADFALSE`, `LOADNIL`, `MOVE`, `RETURN`, `RETURN0`, `RETURN1`, `JMP`.
- `Grammar.enumerate_grammar({max_arity=2})` observed:
  - `750` sequences
  - `8754` compiles
  - `209` unique forms
  - `154` forms include `GENERIC_EXIT`
  - top form is plain `GENERIC_EXIT` with count `4608`.
- `ADD` can lower richly today **only** with explicit slot facts:
  - explicit `R0/R1 is_i64` facts -> `FRAME_LOAD|I64|UNBOX_I64|...|ADD_I64|BOX_I64|FRAME_STORE|RETURN1`
  - legacy `{"lhs_i64","rhs_i64"}` -> `GENERIC_EXIT`
- `GETFIELD` with explicit table/shape/metatable facts still exits with `table_abi_not_lowered`.
- `CALL` with explicit known target facts still exits with `call_boundary`.
- `ADDK` with lhs i64 fact starts lowering but exits at `constant_numeric_operand`.
- `ssa_ir.lua` already has graph methods and codegen names for table/call/barrier nodes; `ssa_lift.lua` just does not emit them from opcode facts, and `ssa_to_c.lua` would not lower them if emitted.
- `ssa_normalize.lua` already expects composite table/call normal forms such as `FIELD_ADDI_UPDATE`, `ARRAY_ADD_UPDATE`, `SELF_CALL`, but the current lifter cannot produce them.
- `Makefile` appears stale for this path: it references `stencils/stencils.c`, `stencils/extract.lua`, and `build/stencil_library.json`; current directory listing has no `stencils/` directory, while active scripts use `build/cp_lib`.
- `ssa_to_c.lua` predeclares only `__H_0` through `__H_23`; richer variants with more slots/guards/exits may need attention at this exact preamble.
- `ConstBool` C lowering currently uses a runtime hole `bool_val` instead of directly using `args.value`, despite `ConstBool` carrying the value.
- `LoadConst` currently fakes constants via `(TValue*)(stack + 4096) + k_idx`; no actual constant table ABI is modeled.
- `build_bank.lua classify_role()` already recognizes `exit_` and `unlowered_` roles as exit holes, so any unimplemented C node silently becomes an exit-class patch site rather than failing the bank build.
