# SpongeJIT Lua 5.5 Feature Roadmap 
Identify features needed after SpongeJIT clean-base reset to grow toward full Lua 5.5 semantics.
**Workflow ID**: wf-lua55-roadmap
**Started**: 2026-06-06 16:17:46
---

## Scout Output — 2026-06-06 16:27:42

## Files Retrieved

1. `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` (lines 1-260, 261-520, 521-880, 881-1270, 1271-1610, 1760-1814) — full current clean-base vocabulary: `LuaSrc`, `LuaFFI`, `LuaRT`, `LuaGC`, `LuaExec`, `MoonCFG`, `LuaCompile`.
2. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_from_puc_decode.lua` (lines 1-135) — PUC event/table decoder into `LuaSrc.Op`, explicit decoders for all real opcodes.
3. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_window_collect.lua` (lines 1-46) — window collector and `EXTRAARG` preservation.
4. `experiments/lua_interpreter_vm/spongejit/lua_compile/validate.lua` (lines 1-160) — cross-layer validation, LuaSrc companion checks.
5. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua` (lines 1-923) — current source-to-`LuaExec` semantic lowering and fail-closed cases.
6. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua` (lines 1-880) — `LuaExec` to `MoonCFG` lowering; supported runtime expressions, outcome mode, unsupported ops.
7. `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua` (lines 1-1329) — MoonCFG-to-Moonlift emitter and executable runtime substrates.
8. `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua` (lines 1-393) — validator support set and forbidden protocol/legacy concepts.
9. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_value_model.lua` (lines 1-145) — executable `LuaRTValue` tags/type tests.
10. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_stack_model.lua` (lines 1-88) — stack/window/sequence/vararg runtime model.
11. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_object_model.lua` (lines 1-132) — table/string/raw-get/hash/barrier runtime model.
12. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_cdata_model.lua` (lines 1-64) — cdata scalar-bank model.
13. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_outcome_model.lua` (lines 1-82) — return/error/yield outcome model.
14. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua` (lines 1-220) — structural LuaExec validator; recognizes more expressions than MoonCFG lower executes.
15. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_to_moon_kernel.lua` (lines 1-77) — public compile route: `LuaSrc.Window -> LuaExec.Kernel -> MoonCFG.Kernel`, no fallback.
16. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_unit.lua` (lines 1-21) — unit construction from events/evidence.
17. `experiments/lua_interpreter_vm/spongejit/lua_compile/init.lua` (lines 1-43) — public facade exports.
18. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_runtime_observe.lua` (lines 1-212) — runtime observation import into `LuaFact.Evidence`.
19. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_foundry_bundle.lua` (lines 1-57) — foundry facts to evidence.
20. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_foundry.lua` (lines 160-536) — fact axes, compile artifact generation, coverage manifest.
21. `experiments/lua_interpreter_vm/spongejit/src/loop_regions.lua` (lines 1-220) — loop topology recognition data for numeric/generic for loops.
22. `experiments/lua_interpreter_vm/spongejit/Makefile` (lines 1-64) — green gate vs opt-in completion/corpus; retired targets.
23. `experiments/lua_interpreter_vm/spongejit/bench/README.md` (lines 1-31) — measurement status.
24. `experiments/lua_interpreter_vm/spongejit/ssa_asdl/README.md` (lines 1-38) — layer responsibilities/guardrails.
25. `experiments/lua_interpreter_vm/spongejit/puc/README.md` (lines 1-15) — PUC bytecode ingestion contract.
26. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-31) — current direction and retired assumptions.
27. `experiments/lua_interpreter_vm/SPONJIT_FFI_DESIGN.md` (lines 1-180) — FFI design target and explicit data/control split.
28. `experiments/lua_interpreter_vm/SPONJIT_GC_DESIGN.md` (lines 1-180) — GC design target.
29. `experiments/lua_interpreter_vm/SPONJIT_MOONLIFT_COPY_PATCH_DESIGN.md` (lines 1-180) — copy/patch executor design.
30. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_src.lua` (lines 1-120) — LuaSrc decode coverage and field preservation tests.
31. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua` (lines 1-119) — schema presence/shape assertions.
32. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua` (lines 1-380) — core LuaExec/MoonCFG executable tests.
33. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arithmetic.lua` (lines 1-179) — current arithmetic executable slice.
34. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_objects.lua` (lines 1-168) — object/table/string executable slice.
35. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_stack.lua` (lines 1-207) — stack/sequence/vararg executable slice.
36. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua` (lines 1-363) — MoonCFG route, positive/negative support tests.
37. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_ffi.lua` (lines 1-159) — FFI ASDL/validator/stencil metadata foundation.
38. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_gc.lua` (lines 1-230) — GC ASDL/validator/stencil metadata foundation.
39. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_completion.lua` (lines 1-63) — opt-in completion gate.
40. `experiments/lua_interpreter_vm/spongejit/build/lua_compile_corpus100/lua_compile_grammar_coverage.json` (line 1) — generated corpus coverage after run.
41. `experiments/lua_interpreter_vm/spongejit/build/lua_compile_corpus100/lua_compile_representatives.md` (lines 1-34) — generated corpus representative summary.
42. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-120) — Moonlift-native VM data tree, separate from SpongeJIT clean-base compiler but relevant substrate evidence.
43. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-287) — Lua 5.5 VM opcode/tag/TM/resume/error constants.
44. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-880) — native VM dispatch arms/handlers for opcodes.
45. `experiments/lua_interpreter_vm/src/op_handlers.lua` (lines 1-19) — native VM handler aggregation.
46. `experiments/lua_interpreter_vm/src/op/_init.lua` (lines 1-164) — native VM opcode handler continuations/protocols.

## Key Code

### ASDL doctrine and layers

```asdl
-- spongejit_lua_ssa.asdl lines 9-17
--   LuaSrc          answers: what did PUC encode?
--   LuaEvidence     answers: what did runtime/foundry prove and lease?
--   LuaFFI          answers: what Lua-visible C FFI declarations/types/values/facts exist.
--   LuaGC           answers: what explicit Lua GC objects/state/control facts exist.
--   LuaRT           answers: what Lua runtime semantic objects/state exist.
--   LuaExec         answers: what explicit semantic Lua CFG is executed over LuaRT.
--   CompileContract answers: what executable-route obligations/facts/invalidation assumptions are attached.
--   MoonCFG         answers: what explicit Moonlift CFG is emitted.
```

### LuaSrc opcode surface

`LuaSrc.Op` enumerates all 85 Lua 5.5 real opcodes plus `UnsupportedOpcode`, including:

- loads/moves: `MOVE`, `LOADI`, `LOADF`, `LOADK`, `LOADKX`, `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`, `LOADNIL`
- upvalues/tables: `GETUPVAL`, `SETUPVAL`, `GETTABUP`, `GETTABLE`, `GETI`, `GETFIELD`, `SETTABUP`, `SETTABLE`, `SETI`, `SETFIELD`, `NEWTABLE`, `SELF`
- arithmetic: all `ADDI`, `ADDK`…`SHRI`, register-register ops, `MMBIN*`, unary ops
- control/compare/call/return/loops/vararg: `JMP`, comparisons, `CALL`, `TAILCALL`, `RETURN*`, `FOR*`, `TFOR*`, `SETLIST`, `CLOSURE`, `VARARG`, `GETVARG`, `ERRNNIL`, `VARARGPREP`, `EXTRAARG`

Decoder evidence:

```lua
-- lua_src_from_puc_decode.lua lines 76-133
DECODER.MOVE = function(e) return Src.MOVE(pc(e), slot(e.a), slot(e.b)) end
...
DECODER.SETLIST = function(e) return Src.SETLIST(pc(e), slot(e.a), count(e.vb or e.b), count(e.vc or e.c), kflag(e), B.ax(explicit_extraarg(e) or 0)) end
DECODER.CLOSURE = function(e) return Src.CLOSURE(pc(e), slot(e.a), kref(e.bx or e.b)) end
DECODER.VARARG = function(e) return Src.VARARG(pc(e), slot(e.a), slot(e.b), count(has_field(e, "c") and e.c or e.nresults), kflag(e)) end
DECODER.GETVARG = function(e) return Src.GETVARG(pc(e), slot(e.a), slot(e.b), slot(e.c)) end
DECODER.ERRNNIL = function(e) return Src.ERRNNIL(pc(e), slot(e.a), B.ax(bx_value(e))) end
DECODER.VARARGPREP = function(e) return Src.VARARGPREP(pc(e), count(e.a or e.b or 0)) end
DECODER.EXTRAARG = function(e) return Src.EXTRAARG(pc(e), B.ax(e.ax or e.bx or 0)) end
```

Test signal:

```lua
-- test_spongejit_lua_compile_lua_src.lua lines 23-38
assert(#names == 85, "ASDL real LuaSrc.Op coverage count must be 85")
for _, name in ipairs(names) do
  assert(Decode.DECODER[name], "missing explicit decoder for " .. name)
  local op = Decode.decode(sample_event(name))
  assert(op.kind == name)
end
```

### Current LuaExec support gate

```lua
-- lua_src_to_lua_exec_lower.lua lines 20-33
local TERMINAL_RETURN = { RETURN = true, RETURN0 = true, RETURN1 = true }
local TERMINAL_EFFECT = { SETTABLE = true }
local ARITHMETIC_OP = {
  ADD = { op = RT.ArithAdd, lhs = "slot", rhs = "slot", companion = "MMBIN" },
  ADDI = { op = RT.ArithAdd, lhs = "slot", rhs = "imm", companion = "MMBINI" },
  ADDK = { op = RT.ArithAdd, lhs = "slot", rhs = "const", companion = "MMBINK" },
}
local SUPPORTED_INSTR = {
  LOADNIL = true, LOADFALSE = true, LOADTRUE = true, LOADI = true,
  LOADK = true, MOVE = true, NOT = true, VARARG = true, GETVARG = true,
  GETTABLE = true, LEN = true, CONCAT = true,
  MMBIN = true, MMBINI = true, MMBINK = true
}
```

`coverage_summary()` reports these current LuaExec-covered op names:

```json
["ADD","ADDI","ADDK","CONCAT","EQ","EQI","EQK","ERRNNIL","GEI","GETTABLE","GETVARG","GTI","JMP","LE","LEI","LEN","LOADFALSE","LOADI","LOADK","LOADNIL","LOADTRUE","LT","LTI","MMBIN","MMBINI","MMBINK","MOVE","NOT","RETURN","RETURN0","RETURN1","SETTABLE","TEST","TESTSET","VARARG"]
```

Important nuance: `MMBIN*` are supported only as companions to `ADD/ADDI/ADDK`; standalone markers reject.

```lua
-- test_spongejit_lua_compile_lua_rt_arithmetic.lua lines 151-158
local bad_unit = C.unit_from_events({ {op="MMBIN", pc=1, a=1, b=2, c="ADD"}, {op="RETURN0", pc=2} }, {})
local bad_exec, bad_errors = ExecLower.lower(bad_unit.source, bad_unit.evidence)
assert(not bad_exec, "standalone MMBIN must not compile as success")
assert(table.concat(bad_errors or {}, "; "):match("unsupported_instruction:MMBIN"))
```

### Fail-closed examples

```lua
-- lua_src_to_lua_exec_lower.lua lines 205-219
elseif op.kind == "SETLIST" then
  return nil, { "lua_exec:setlist_table_write_semantics_future:" .. tostring(op.pc.id) }
elseif TERMINAL_RETURN[op.kind] or TERMINAL_EFFECT[op.kind] then
  ...
elseif not SUPPORTED_INSTR[op.kind] then
  return nil, { "lua_exec:unsupported_instruction:" .. tostring(op.kind) }
end
```

```lua
-- test_spongejit_lua_compile_moon_cfg.lua lines 270-282
local external_jump = C.compile_to_moon_kernel(...)
assert(external_jump.kind == "Reject", "external jump target must not compile as closed success")

local legacy_mul = C.compile_to_moon_kernel(...)
assert(legacy_mul.kind == "Reject", "NF-owned MUL must not compile through MoonKernel fallback")
```

```lua
-- test_spongejit_lua_compile_moon_cfg.lua lines 344-345
for _, op in ipairs({ "CALL", "TAILCALL", "CLOSE", "TBC", "TFORPREP", "TFORCALL", "TFORLOOP", "SETLIST", "GETVARG" }) do
  local r = C.compile_to_moon_kernel(C.unit_from_events({ sample_event(op) }, {}))
  assert(r.kind == "Reject", op .. " must not compile as protocol success")
end
```

### Public compile route has no semantic fallback

```lua
-- lua_compile_to_moon_kernel.lua lines 52-65
-- Accepted MoonKernel compilation has one executable route:
-- LuaSrc.Window -> LuaExec.Kernel -> MoonCFG.Kernel. Unsupported source
-- windows return diagnostics; there are no silent success fallbacks.
local exec_kernel, exec_errors = LuaExecLower.lower(unit.source, unit.evidence)
if not exec_kernel then
  return Errors.compile_reject_from_errors("lua_exec_lower", unit.source, exec_errors, "unsupported_semantic_case")
end
...
if not cfg_kernel then
  return Errors.compile_reject_from_errors("lua_exec_to_moon_cfg_lower", unit.source, cfg_errors, "internal_invariant_failure")
end
```

### Executable runtime substrates present in MoonCFG emitter

- `LuaRTValue`: tag + payload fields, all tags modeled.
- `LuaRTOutcome`: normal/error/yield with first two values.
- `LuaRTStack`, `LuaRTValueSeq`, `LuaRTVarargSource`.
- `LuaRTString`, `LuaRTTable`, `LuaRTRawGetResult`, hash entries.
- Raw table get/set with array and bounded hash path.
- String len, table len no-metatable, concat of two strings.
- Arithmetic no-metamethod ADD, including string numeric metadata coercion.
- Table write barrier metadata.
- CData scalar access/load renderer exists, but not accepted by current lower/validator path.

Example object model:

```lua
-- lua_rt_object_model.lua lines 15-24
-- Tables:
--   * payload_i64 indexes LuaRTTable[];
--   * this executable substrate supports raw array-part get/set by integer key
--     and raw hash-part get/set over explicit LuaRTTableHashEntry storage for
--     integer keys outside the array range and string keys;
--   * metatable_kind is explicit data. 0 means no metatable. Non-zero
--     metatable/callable paths must be represented by LuaExec regions before
--     accepted full semantic kernels may use them.
```

Example raw table support:

```lua
-- moon_cfg_emit.lua lines 462-528
-- raw get checks TableTag, payload handle, NoMetatable, integer array key,
-- then bounded hash probe over hash_capacity <= HASH_PROBE_LIMIT.
```

Example cdata emitter fragment:

```lua
-- moon_cfg_emit.lua lines 327-355
local function render_cdata_access_ok(cdata_bank, cdata_value, scalar, type_id, offset_bytes, width_bytes)
  ...
  "if " .. cdata_value .. ".tag == " .. tag_lit("CDataTag") .. " then",
  ...
  "if " .. cd .. ".type_id == " .. cdata_type_id_lit(type_id) .. " then",
  ...
end
```

But `moon_cfg_validate.lua` accepted runtime expr list does **not** include `RuntimeCDataAccessOk` / `RuntimeCDataLoadScalar`, and `lua_exec_to_moon_cfg_lower.lua` has no cdata expression lowering.

## Relationships

### Main SpongeJIT clean-base data flow

```text
PUC/event rows
  -> lua_src_from_puc_decode.lua
  -> LuaSrc.Window
  -> lua_fact_from_runtime_observe.lua / lua_fact_from_foundry_bundle.lua
  -> LuaCompile.Unit(source, evidence)
  -> lua_src_to_lua_exec_lower.lua
  -> LuaExec.Kernel
  -> lua_exec_to_moon_cfg_lower.lua
  -> MoonCFG.Kernel
  -> moon_cfg_validate.lua
  -> moon_cfg_emit.lua
  -> Moonlift source/native compile in tests
```

### Current supported executable families

- **Loads/constants/move**
  - `LOADNIL`, `LOADFALSE`, `LOADTRUE`, `LOADI`, `LOADK`, `MOVE`.
  - `LOADK` requires `ConstI64` evidence for constants.
  - `LOADF`, `LOADKX`, `EXTRAARG` decode but do not execute through LuaExec.
- **Truthiness/control**
  - `NOT`, `TEST`, `TESTSET`.
  - Closed `JMP`.
  - Comparisons with following-JMP companions: `EQ`, `LT`, `LE`, `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI`.
  - External jumps and missing companion/fallthrough reject.
- **Returns/outcomes**
  - `RETURN0`, `RETURN1`, `RETURN`.
  - Outcome mode is used when needed for dynamic Lua values/errors/table effects.
  - `RETURN` close-upvalue/k/C cases reject.
- **Arithmetic**
  - `ADD`, `ADDI`, `ADDK` only.
  - Uses no-metamethod numeric slice; integer/float/string numeric metadata.
  - Produces typed `ArithmeticError`.
  - Other arithmetic/bitwise/unary opcodes are decoded but fail closed in LuaExec.
- **Tables/strings**
  - `GETTABLE`: raw table get only, array + bounded hash, no metatable success.
  - `SETTABLE`: raw set only, nil key error, bounded hash, barrier metadata.
  - `LEN`: no-metamethod string/table length.
  - `CONCAT`: exactly two operands; strings only; synthetic negative payload string handle.
  - `NEWTABLE`, `GETI`, `GETFIELD`, `SETI`, `SETFIELD`, `GETTABUP`, `SETTABUP`, `SELF`, `SETLIST` not executable in SpongeJIT LuaExec.
- **Varargs/stack**
  - `VARARG`: hidden-frame varargs, fixed and open forms.
  - `GETVARG`: integer-key hidden-frame vararg indexing in appropriate window.
  - Vararg table mode and `VarargNField` reject.
- **Errors/yield**
  - `ERRNNIL` executable as runtime tag check, produces `ErrNnilError`.
  - Manual `LuaExec.Error` / `LuaExec.Yield` lower to `LuaRTOutcome` in outcome mode.
- **Calls/closures/upvalues/metatables**
  - Rich ASDL/native VM model exists.
  - SpongeJIT accepted LuaExec path does not lower `CALL`, `TAILCALL`, `CLOSURE`, upvalue access, or function-valued metamethod calls.
  - Nonzero table metatable in current raw object path becomes typed error outcome, not success.
- **FFI/cdata**
  - ASDL and validators model C types, layouts, symbols, callbacks, cdata, finalizers, patch holes.
  - CData runtime model/emitter fragments exist for scalar bank load/access.
  - No current source opcode/API path lowers FFI/cdata operations to accepted MoonCFG.
- **GC**
  - ASDL and validators model headers, state, roots, barriers, finalizers, weak/ephemeron controls.
  - Executable SpongeJIT path has table write barrier metadata only.
  - No allocation/tracing/finalizer execution lowering in SpongeJIT LuaExec.

### Current native VM is broader but separate

`experiments/lua_interpreter_vm/src/opcodes.lua` builds dispatch arms for opcode numbers 0-84 and routes all non-inlined opcodes to handler regions. `src/products.lua` defines VM-level `Value`, `String`, `Table`, `Proto`, `UpVal`, `LClosure`, `CClosure`, `UserData`, `Frame`, `LuaThread`, `GlobalState`. This is evidence of runtime substrate in the Moonlift-native VM, but SpongeJIT clean-base compiler intentionally accepts only the LuaExec/MoonCFG route above.

## Test / Coverage Signals

Commands run:

```sh
cd experiments/lua_interpreter_vm/spongejit && make test
```

Result: green.

Printed tests:

- `ok - SpongeJIT LuaCompile FFI semantic ASDL foundation`
- `ok - SpongeJIT LuaCompile foundry replacement`
- `ok - SpongeJIT LuaCompile GC semantic ASDL foundation`
- `ok - SpongeJIT LuaExec core-value pipeline`
- `ok - SpongeJIT LuaCompile LuaFact (subjects/predicates/dependencies/payloads 8/25/8/5)`
- `ok - SpongeJIT LuaCompile LuaRegion`
- `ok - SpongeJIT LuaRT arithmetic semantics`
- `ok - SpongeJIT LuaRT/LuaExec structural ASDL`
- `ok - SpongeJIT LuaRT object/table/string substrate`
- `ok - SpongeJIT LuaRT stack/window/top/sequence/vararg substrate`
- `ok - SpongeJIT LuaCompile LuaSrc (decode coverage 85/85)`
- `ok - SpongeJIT LuaCompile MoonCFG LuaExec route`
- `ok - SpongeJIT LuaCompile pipeline`
- `ok - SpongeJIT LuaCompile schema`
- `ok - SpongeJIT LuaCompile stencil artifacts`

Opt-in completion:

```sh
cd experiments/lua_interpreter_vm/spongejit && make test-completion
```

Result:

```text
ok - SpongeJIT LuaCompile completion (LuaExec/MoonCFG semantic fixtures)
```

Opt-in corpus:

```sh
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Result:

```text
[foundry] 18859 workload regions -> 120 opcode windows
[foundry] compiling 120 windows through LuaCompile
[foundry] done: reps=26 compiles=141 ok=37 rejected=104 out=build/lua_compile_corpus100
ok - SpongeJIT LuaCompile corpus100 (31 successful windows, 26 reps checked)
```

Generated coverage:

```json
{
  "distinct_successful_windows": 31,
  "fact_coverage": {"dependencies":8,"payloads":5,"predicates":24,"subjects":8},
  "lua_exec_coverage": {"supported_ops":[...35 ops...]},
  "lua_src_decode": {"decoded":85,"real_ops":85},
  "rejection_reasons":{"UnsupportedSemanticCase":104},
  "stats":{"compiles":141,"ok":37,"rejected":104,"unique_representatives":26,"windows":120}
}
```

Top corpus accepted/rejected patterns after run:

- OK top patterns: `RETURN`, `RETURN0`, `SETTABLE`, `RETURN RETURN0`, `RETURN1`.
- Rejected top patterns: `MOVE`, `CALL`, `GETUPVAL`, `JMP`, `ADDI`, `GETTABUP`, `TAILCALL`, `GETFIELD`, `SELF`, `LEN`.
- All corpus rejections are `UnsupportedSemanticCase`.

## Observations

- LuaSrc is complete for Lua 5.5 opcode decoding: 85/85 real op families.
- LuaExec/MoonCFG is intentionally much narrower than LuaSrc. Coverage summary lists 35 supported op names, but some are contextual (`MMBIN*` companions, `GETVARG` with full vararg window, closed comparisons with following `JMP`).
- The clean-base no-fallback invariant is strongly tested: no `LuaSem`, `LuaNF`, protocol exits, `out_tag`, opcode helper fallbacks, or old stencil-bank path in accepted products.
- Main suite excludes `completion` and `corpus100`; both opt-in gates are currently green after running.
- ASDL already models many full Lua semantics substrates: FFI, GC, closures, upvalues, calls, metatables, yield/error state, close chains, numeric/generic loops, cdata.
- Executable SpongeJIT currently implements only portions of those substrates:
  - tables/strings/varargs/errors are executable in bounded slices;
  - GC/FFI/cdata are mostly typed ASDL/validator/stencil metadata foundations, with small runtime-emitter fragments;
  - calls/metatables/upvalues/closures are represented but not accepted executable LuaExec/MoonCFG paths.
- MoonCFG has CData ASDL/emitter cases, but current validator/lower path does not include them as accepted expressions; no tests execute cdata scalar load/store.
- Native VM code under `experiments/lua_interpreter_vm/src/` has broader Lua 5.5 runtime structures and opcode handlers, but SpongeJIT clean-base roadmap evidence should keep it distinct from the current `lua_compile` accepted fast-path compiler.

## Knowledge-builder Output — 2026-06-06 16:31:45

### What Matters Most for This Problem

- **Semantic dependency ordering**: many Lua 5.5 opcodes are not independent; calls, arity, close chains, GC allocation, and metatable lookup are shared prerequisites.
- **No fake success**: accepted kernels must not silently encode “raw/no-meta/no-call” behavior when Lua would call metamethods, close variables, yield, allocate, or adjust arity.
- **Contract/invalidation honesty**: foundry facts, compile contracts, and stencil keys must describe every assumption: call target, metatable epoch, table shape, upvalue epoch, GC barrier state, ABI/layout.
- **Window/context completeness**: companion opcodes and control pairs matter: `MMBIN*`, `EXTRAARG`, comparison+`JMP`, loop triads, call/result windows.
- **Artifact stability**: JIT/stencil success must require typed patch holes and ABI facts, not semantic strings or helper fallbacks.

### Non-Obvious Observations

- **Calls are the central semantic bottleneck.**  
  `CALL`/`TAILCALL` are not just another opcode family. They are required by:
  - `__index`, `__newindex`, `__call`, arithmetic/comparison/concat/len metamethods
  - generic `for` iterator calls
  - `__close`
  - FFI C calls and callbacks
  - finalizers
  - open-result arity adjustment  
  So accepting “full” table, arithmetic, close, generic-loop, or FFI semantics before call/yield/result handling exists would create fake success.

- **Arity/sequence support must precede real calls, returns, varargs, and constructors.**  
  Current MoonCFG/outcome support is effectively small-arity: outcome projection and value sequences preserve only the first two values in several places. That is fine for the current slice, but Lua 5.5 call/return/vararg semantics depend on open counts (`B=0`, `C=0`), top adjustment, result padding/truncation, and value buffers. Without general `ValueSeq`/top/value-buffer correctness, `CALL`, `TAILCALL`, `RETURN`, `VARARG`, `SETLIST`, and generic `for` can only be partial.

- **Metatable-present cases cannot be modeled as “typed error” once claiming full semantics.**  
  Current raw table/len/arithmetic paths can error or reject when metatables are present. For the clean-base slice that is honest, but for Lua 5.5 coverage it becomes wrong unless the contract proves no relevant metamethod exists. A table `GETTABLE` with `__index`, arithmetic with `__add`, `LEN` with `__len`, or callable table with `__call` is not an error path; it is a call path.

- **`MMBIN*` companions make arithmetic sequencing non-local.**  
  Arithmetic support is not “add more opcodes.” LuaSrc preserves `MMBIN`, `MMBINI`, `MMBINK`, operand flip flags, and metamethod selector data. A full arithmetic opcode cannot be accepted safely unless its companion relationship, operand order, and continuation are known. Standalone companion markers must remain reject-only.

- **The current `ADDI` limitation implies a hidden source fidelity constraint.**  
  `MMBINI` preserves `operands_flipped`, but current ADDI lowering only accepts unflipped companions because the arithmetic op itself lacks enough source-origin information. Any roadmap for full arithmetic must account for operand-order fidelity before claiming immediate arithmetic/metamethod coverage.

- **Closures/upvalues depend on both GC and close-chain semantics.**  
  `CLOSURE`, `GETUPVAL`, and `SETUPVAL` are tied to:
  - closure allocation
  - open vs closed upvalue identity
  - frame lifetime
  - upvalue write barriers
  - upvalue epoch invalidation
  - `CLOSE`, `TBC`, return-close, tailcall-close  
  Treating upvalues as just extra slots would break lifetime and invalidation semantics.

- **`CLOSE`/`TBC` is a cross-cutting control protocol, not a side effect.**  
  Close handling appears on explicit `CLOSE`, `TBC`, `RETURN` with close flag, `TAILCALL` with close flag, errors, yields, and possibly finalizer/`__close` interactions. Since ASDL already models `CloseYieldState`, `CloseErrorState`, and resume points, full support must preserve error/yield ordering through close chains. Accepting return/error paths before close obligations are represented would be unsound.

- **Numeric `for` is simpler than generic `for`, but still not scalar.**  
  `loop_regions.lua` correctly treats loop bytecodes as whole-region topology. `FORPREP`/`FORLOOP` depend on slot conventions, integer-vs-float loop state, comparisons, increments, and backedges. Generic `for` additionally depends on call/arity/yield/close behavior. Loop support cannot be measured by individual opcode acceptance.

- **`NEWTABLE`, `SETLIST`, `CONCAT`, `CLOSURE`, and cdata creation all force real allocation semantics.**  
  Current `CONCAT` uses a synthetic negative string handle; current table support assumes preexisting table banks. Full Lua semantics require GC allocation results, root safety during initialization, object headers, write barriers, and allocation-failure/error behavior. GC cannot remain only “barrier metadata” once constructors or allocating string operations are accepted.

- **`SETLIST` is blocked by three dependencies at once.**  
  It needs table allocation/shape semantics, bulk writes with barriers, and open value counts from varargs/call results. Its `EXTRAARG` extension is already preserved, so dropping or simplifying that field would be an observable fake success.

- **FFI/cdata has a visible schema/emitter mismatch.**  
  ASDL and emitter fragments include cdata scalar access/load/store, but MoonCFG validation/lowering do not accept them. That means cdata is currently architectural substrate, not executable feature coverage. Any accepted FFI/cdata path must first close the lower/validator/emitter/ABI gap.

- **FFI depends on both call ABI and GC/finalization.**  
  FFI is not just scalar loads/stores. `ffi.C` calls need symbol resolution, ABI/calling convention, relocation/patch holes, and result conversion. CData ownership/finalizers require GC roots and finalizer queues. Callbacks re-enter Lua call/yield/error semantics. So FFI should not be considered independently coverable from calls and GC.

- **Foundry facts currently outpace executable semantics.**  
  Foundry can generate facts for `GETFIELD`, `SETFIELD`, `GETTABUP`, arithmetic families, barriers, and call targets, but the lowerer rejects many of those opcodes. This is good as a guardrail. The risk is future “coverage” metrics counting fact availability or decode coverage as semantic support.

- **Corpus success is presently biased toward terminal/simple windows.**  
  The corpus accepted top patterns are mostly `RETURN*` and raw `SETTABLE`; rejected patterns include common program features like `CALL`, `GETUPVAL`, `GETTABUP`, `TAILCALL`, `GETFIELD`, `SELF`. This implies full Lua coverage requires changing the semantic frontier, not merely improving fact supply.

- **Stencil artifact identity must grow with semantics.**  
  Current representative identity uses MoonCFG + CompileContract + Stencil.VariantKey, but real calls/GC/FFI require typed patch holes for call targets, frame layout, constants/upvalues, FFI symbols/field offsets/layouts, GC state pointers, barrier entries, finalizer queues, and epochs. Otherwise materialized code can become stale while still matching the same variant key.

- **The validator’s forbidden-string policy is currently a roadmap constraint.**  
  `moon_cfg_validate.lua` forbids semantic strings like `call`, `close`, `generic_for`, `setlist`, `getvarg` to prevent legacy/protocol fallback. That protects the clean base, but future real typed support must not accidentally trip the same anti-fallback checks or weaken them so much that legacy protocol exits re-enter.

- **“Supported ops” count overstates readiness.**  
  The reported 35 supported op names include contextual cases: comparisons require following `JMP`, `MMBIN*` only as companions, `GETVARG` needs proper vararg source/window, arithmetic needs following continuation, returns reject close/C cases. Roadmap coverage should track semantic families plus preconditions, not opcode names alone.

### Knowledge Gaps

- Exact Lua 5.5 runtime rules for `TBC`, `__close`, yieldability during close/finalization, and tailcall close ordering should be pinned against PUC behavior.
- The intended arbitrary-value buffer ABI for full call/return/vararg support is not yet clear from the current accepted MoonCFG path.
- Native VM opcode handlers may contain useful semantic detail, but they are intentionally separate from SpongeJIT; any reuse boundary needs explicit confirmation.
- Current stencil object-byte extraction/materialization status is unclear beyond metadata foundations.

## Approach-proposer Output — 2026-06-06 16:33:14

### Approach A: Dependency-Ordered Semantic Core

- **Core idea**: Build the missing shared Lua runtime semantics first—arity/calls/GC/close/metatables—then enable opcode families only when their full dependencies are executable through `LuaExec -> MoonCFG`.

- **Key changes**:
  - Extend `ssa_asdl/spongejit_lua_ssa.asdl` with complete `LuaRT`/`LuaExec` nodes for:
    - arbitrary `ValueSeq`, call frames, call results, tailcalls
    - closures/upvalues/open-upvalue close chains
    - GC allocation/root/barrier/finalizer state
    - metatable lookup and metamethod invocation
    - close/TBC/error/yield resume state
    - FFI ABI/cdata scalar access/call/finalizer facts
  - Add runtime semantic modules:
    - `lua_rt_call_model.lua`
    - `lua_rt_value_seq_model.lua`
    - `lua_rt_gc_alloc_model.lua`
    - `lua_rt_closure_upvalue_model.lua`
    - `lua_rt_metatable_model.lua`
    - `lua_rt_ffi_abi_model.lua`
  - Expand:
    - `lua_src_to_lua_exec_lower.lua`
    - `lua_exec_to_moon_cfg_lower.lua`
    - `moon_cfg_validate.lua`
    - `moon_cfg_emit.lua`
  - Strengthen foundry/stencil contracts so every accepted kernel records call-target, metatable, upvalue, GC, ABI, and layout assumptions.

- **Tradeoff**: Optimizes semantic correctness and long-term coherence; sacrifices short-term corpus wins because many opcodes remain rejected until the shared core exists.

- **Risk**: The foundational layer may become large before it visibly improves accepted coverage, and arbitrary arity/call/yield/close handling may force substantial MoonCFG/emitter changes.

- **Rough sketch**:
  - First implement general `LuaRTValueSeq`/top/arity semantics for `CALL`, `RETURN`, `VARARG`, `SETLIST`, and open counts.
  - Add complete call/tailcall/outcome machinery, including Lua closure calls, C/FFI calls, yields, and errors.
  - Add GC allocation/root/barrier semantics before enabling `NEWTABLE`, allocating `CONCAT`, `CLOSURE`, cdata creation, or finalizers.
  - Add metatable-aware table/arithmetic/len/concat/call operations, where metamethod paths become explicit `LuaExec.Call` paths.
  - Then enable opcode families in dependency order: arithmetic/bitwise, tables, closures/upvalues, numeric loops, generic loops, close/TBC, FFI/cdata.

---

### Approach B: Fact-Leased Specialized Feature Shards

- **Core idea**: Grow full Lua 5.5 coverage through many narrowly proven, contract-heavy specializations, accepting each dynamic feature only when foundry/evidence proves the required semantic facts.

- **Key changes**:
  - Make `LuaEvidence`, `CompileContract`, foundry facts, and stencil variant keys first-class owners of assumptions:
    - call target identity/epoch
    - arity shape
    - metatable epoch and specific metamethod absence/presence
    - closure proto/upvalue identity
    - table shape/hash/array facts
    - GC allocation/barrier state
    - FFI symbol/layout/ABI/cdata ownership
  - Extend `lua_src_to_lua_exec_lower.lua` with feature-specific accepted variants:
    - raw/no-metatable table variants
    - proven-metamethod table/arithmetic variants
    - known Lua closure call variants
    - known C/FFI call variants
    - known iterator generic-for variants
    - known close/TBC handler variants
  - Extend stencil artifacts with typed patch holes for constants, closures, upvalues, symbols, ABI layouts, metatable epochs, GC state, and invalidation leases.
  - Expand corpus/foundry tooling to report “semantic family coverage under contract,” not just opcode-name coverage.

- **Tradeoff**: Optimizes incremental progress and performance on hot/corpus-proven cases; sacrifices genericity because unproven dynamic cases still reject.

- **Risk**: Contract bugs are dangerous: if a fact omits an epoch, layout, call target, or metamethod dependency, the compiler can produce fake success. Variant explosion is also likely.

- **Rough sketch**:
  - First harden contract/stencil identity so every semantic assumption is typed and invalidatable.
  - Add specialized arity/call variants for known Lua closures and fixed/open result shapes.
  - Add table/metatable/arithmetic variants driven by explicit no-metamethod or known-metamethod facts.
  - Add closure/upvalue, loop, close/TBC, GC allocation, and FFI/cdata variants in corpus-priority order.
  - Testing strategy: every accepted feature shard gets PUC differential tests, negative stale-contract tests, corpus representative tests, and stencil-key mutation tests.

---

### Approach C: Opcode-Complete Static Semantic Region Library

- **Core idea**: Build a complete typed semantic region library for all Lua 5.5 opcodes and lower each `LuaSrc` instruction/window into static `LuaExec` regions, using native VM code only as semantic reference—not as fallback or interpreter handoff.

- **Key changes**:
  - Create one explicit `LuaExec` semantic region family per opcode or opcode group:
    - `CallRegion`
    - `ReturnRegion`
    - `TableAccessRegion`
    - `MetatableLookupRegion`
    - `ClosureRegion`
    - `UpvalueRegion`
    - `NumericForRegion`
    - `GenericForRegion`
    - `CloseTBCRegion`
    - `GCAllocRegion`
    - `FFIRegion`
  - Refactor `lua_src_to_lua_exec_lower.lua` from ad-hoc opcode cases into static region emission.
  - Use `src/opcodes.lua`, `src/products.lua`, and related native VM structures as reference material, but re-express everything as `LuaRT`/`LuaExec`/`MoonCFG`.
  - Extend `moon_cfg_validate.lua` so future support is typed region support, not forbidden semantic strings.
  - Add exhaustive opcode conformance tests: every LuaSrc opcode must have either a complete static region lowering or a precise reject reason.

- **Tradeoff**: Optimizes completeness and traceability: engineers can grep one semantic region per feature/opcode. Sacrifices early optimization and may produce large MoonCFG/stencils.

- **Risk**: If the region library mirrors VM handlers too literally, it may become bulky and hard to optimize. It must avoid becoming a runtime bytecode interpreter; each source window must lower to static CFG, not dynamic dispatch.

- **Rough sketch**:
  - Define full runtime state objects: frame, stack, top, value buffer, heap, GC state, call state, close state, thread/yield state.
  - Port opcode semantics into typed static regions, starting with arity/calls/returns, then tables/metatables, closures/upvalues, loops, close/TBC, GC/allocation, arithmetic, and FFI/cdata.
  - Lower compound bytecode patterns as whole regions: `EXTRAARG`, `MMBIN*`, comparison+`JMP`, loop groups, call/result windows.
  - Emit static MoonCFG per window/proto; no fallback, no VM protocol exit, no hidden helper semantics.
  - Testing strategy: opcode matrix tests, PUC differential fixtures, region-level validators, corpus completion, and stencil artifact identity checks.

---

### Comparison

- Pick **Approach A** if the priority is the cleanest long-term architecture and strongest semantic correctness story.
- Pick **Approach B** if the priority is getting useful JIT coverage quickly while preserving strict no-fake-success guarantees through contracts and invalidation.
- Pick **Approach C** if the priority is complete Lua 5.5 opcode coverage with a clear static semantic library, accepting larger generated CFGs and later optimization work.

## Documenter Output — 2026-06-06 17:03:50

# SpongeJIT Lua 5.5 Roadmap Decision: ASDL-First Opcode-Complete Static Semantic Regions

## Goal

Enable SpongeJIT to grow from its current clean-base LuaExec/MoonCFG slice into full Lua 5.5 semantic coverage by lowering every `LuaSrc` opcode or opcode family into explicit, typed `LuaExec` semantic regions and then into `MoonCFG`, with ASDL-defined runtime state, contracts, and control semantics as the governing architecture.

## Incentives

SpongeJIT already decodes all Lua 5.5 bytecodes, but its executable compiler accepts only a narrow subset. The current pipeline is intentionally fail-closed: unsupported Lua semantics return `Reject`, and accepted kernels must go through `LuaSrc.Window -> LuaExec.Kernel -> MoonCFG.Kernel` with no fallback. That discipline has protected the clean base from fake success, but it also means common Lua features remain outside the accepted fast path: `CALL`, `TAILCALL`, `GETUPVAL`, `GETTABUP`, `GETFIELD`, `SELF`, closures, upvalues, metatables, loops, `SETLIST`, allocation, close/TBC, FFI/cdata, and most arithmetic families.

The roadmap decision addresses this gap without weakening the clean-base invariants. Full Lua 5.5 support cannot be reached by treating opcodes as isolated cases or by embedding helper strings/protocol exits. Lua semantics are cross-cutting: calls are needed by metamethods, generic `for`, FFI, `__close`, and finalizers; arity and value sequences are needed by calls, returns, varargs, constructors, and `SETLIST`; GC allocation is needed by tables, closures, strings, cdata, and finalizers; close/TBC semantics affect returns, errors, yields, and tailcalls. The chosen direction makes those dependencies explicit in typed ASDL products before any lowering or emission claims support.

## Current State

### Pipeline and architectural boundaries

The current SpongeJIT clean-base compiler is centered on `experiments/lua_interpreter_vm/spongejit/lua_compile/` and the ASDL vocabulary in:

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`

The ASDL layers define the intended separation of meaning:

| Layer | Responsibility |
|---|---|
| `LuaSrc` | What PUC encoded |
| `LuaEvidence` / `LuaFact` | What runtime/foundry proved and leased |
| `LuaFFI` | Lua-visible C FFI declarations, types, values, and facts |
| `LuaGC` | GC objects, state, control facts |
| `LuaRT` | Lua runtime semantic objects/state |
| `LuaExec` | Explicit semantic Lua CFG over `LuaRT` |
| `CompileContract` | Executable-route obligations, facts, invalidation assumptions |
| `MoonCFG` | Explicit Moonlift CFG to emit |

The accepted compile route is:

```text
PUC/event rows
  -> lua_src_from_puc_decode.lua
  -> LuaSrc.Window
  -> lua_fact_from_runtime_observe.lua / lua_fact_from_foundry_bundle.lua
  -> LuaCompile.Unit
  -> lua_src_to_lua_exec_lower.lua
  -> LuaExec.Kernel
  -> lua_exec_to_moon_cfg_lower.lua
  -> MoonCFG.Kernel
  -> moon_cfg_validate.lua
  -> moon_cfg_emit.lua
```

The public route in:

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_to_moon_kernel.lua`

has one accepted executable path only:

```text
LuaSrc.Window -> LuaExec.Kernel -> MoonCFG.Kernel
```

Unsupported source windows return diagnostics. There is no semantic fallback, no interpreter handoff, and no silent success route.

### LuaSrc coverage

`LuaSrc.Op` already represents all 85 real Lua 5.5 opcodes. The decoder in:

- `lua_src_from_puc_decode.lua`

has explicit decoder cases for every opcode, including companion/context opcodes such as:

- `EXTRAARG`
- `MMBIN`, `MMBINI`, `MMBINK`
- comparison + `JMP` forms
- loop opcodes
- vararg opcodes
- closure/upvalue/call/table forms

The test:

- `tests/test_spongejit_lua_compile_lua_src.lua`

asserts decode coverage of `85/85` real opcodes and requires an explicit decoder for each one.

This means source fidelity is not the blocker. The gap is semantic execution coverage.

### Current LuaExec/MoonCFG support

The current `LuaExec` lowering in:

- `lua_src_to_lua_exec_lower.lua`

supports only a limited semantic slice. Current accepted families include:

- Basic loads/moves:
  - `LOADNIL`, `LOADFALSE`, `LOADTRUE`, `LOADI`, `LOADK`, `MOVE`
- Truthiness/control:
  - `NOT`, `TEST`, `TESTSET`
  - closed `JMP`
  - comparisons only with required following-`JMP` structure
- Returns:
  - `RETURN0`, `RETURN1`, selected `RETURN`
- Arithmetic:
  - `ADD`, `ADDI`, `ADDK`
  - only with proper `MMBIN*` companion context
- Raw object operations:
  - `GETTABLE`, `SETTABLE`
  - no-metatable raw table behavior only
- String/table operations:
  - selected `LEN`
  - two-string `CONCAT`
- Varargs:
  - selected `VARARG`, `GETVARG`
- Error/yield substrate:
  - `ERRNNIL`
  - manual `LuaExec.Error` / `LuaExec.Yield` paths

Unsupported cases deliberately reject. Examples include `CALL`, `TAILCALL`, `CLOSURE`, `GETUPVAL`, `SETUPVAL`, `NEWTABLE`, `SETLIST`, `GETFIELD`, `SETFIELD`, `GETI`, `SETI`, `SELF`, `GETTABUP`, `SETTABUP`, `FOR*`, `TFOR*`, `CLOSE`, `TBC`, most arithmetic/bitwise operations, FFI/cdata operations, and allocating semantics.

The validation and tests also enforce absence of legacy concepts. `moon_cfg_validate.lua` rejects forbidden protocol/helper concepts, and tests assert that unsupported instructions do not compile as successful kernels.

### Runtime substrates already present but incomplete

Several runtime-model files already provide executable pieces:

- `lua_rt_value_model.lua`
- `lua_rt_stack_model.lua`
- `lua_rt_object_model.lua`
- `lua_rt_cdata_model.lua`
- `lua_rt_outcome_model.lua`

`moon_cfg_emit.lua` already contains executable substrate for:

- tagged `LuaRTValue`
- stack/window/vararg structures
- raw table array/hash lookup and set
- table write barrier metadata
- string/table length slices
- two-string concat slice
- numeric `ADD` slice
- outcome values for return/error/yield
- cdata scalar emitter fragments

However, several modeled substrates are not accepted through the full lowering/validation path. For example, cdata access/load rendering exists in the emitter, but `moon_cfg_validate.lua` and `lua_exec_to_moon_cfg_lower.lua` do not currently accept cdata expressions as executable feature coverage.

### Native VM relationship

The broader native VM under:

- `experiments/lua_interpreter_vm/src/products.lua`
- `experiments/lua_interpreter_vm/src/constants.lua`
- `experiments/lua_interpreter_vm/src/opcodes.lua`
- `experiments/lua_interpreter_vm/src/op/_init.lua`

contains much wider Lua 5.5 runtime structures and opcode handlers. It models VM-level values, strings, tables, protos, closures, upvalues, frames, threads, and global state.

For SpongeJIT, this VM code is reference material only. The clean-base compiler must not become a VM fallback path. Semantics used by SpongeJIT must be re-expressed as typed `LuaRT`, `LuaExec`, `CompileContract`, and `MoonCFG` products.

### Current testing and corpus signal

The main SpongeJIT test suite is green. Important tests include:

- LuaSrc decode coverage
- LuaExec pipeline tests
- LuaRT arithmetic/object/stack tests
- MoonCFG route tests
- FFI ASDL foundation tests
- GC ASDL foundation tests
- fail-closed rejection tests

The opt-in corpus run reports:

- `120` opcode windows
- `37` successful compiles
- `104` rejected compiles
- all rejections as `UnsupportedSemanticCase`

Accepted corpus patterns are biased toward simple terminal windows such as `RETURN*` and raw `SETTABLE`. Rejected patterns include common Lua program features like `CALL`, `GETUPVAL`, `GETTABUP`, `TAILCALL`, `GETFIELD`, `SELF`, and broader `LEN` cases.

This confirms that full Lua 5.5 progress requires expanding the semantic frontier, not merely improving decode coverage or fact supply.

## Chosen Target

### Approach

The chosen roadmap is **Approach C: Opcode-Complete Static Semantic Region Library**, governed by an explicit **ASDL-first discipline**.

The decision is:

> Every Lua 5.5 opcode or opcode family represented by `LuaSrc` should lower into explicit, typed `LuaExec` semantic regions and then into typed `MoonCFG`. No accepted feature may rely on interpreter fallback, VM protocol handoff, hidden helper strings, side-table semantics, or partial “raw-only” behavior that would be observably wrong under full Lua semantics.

The governing discipline is ASDL-first:

1. Define the typed ASDL product shape.
2. Define the semantic region shape.
3. Define the runtime state shape.
4. Define the compile contract and invalidation shape.
5. Only then lower from `LuaSrc` to `LuaExec`.
6. Only then lower from `LuaExec` to `MoonCFG`.
7. Only then validate, emit, and test the feature.

This preserves the current clean-base rule that ASDL is the architecture. Semantics must live in typed products, not in strings, callbacks, helper names, legacy protocol exits, or implicit interpreter behavior.

### Architecture

The target architecture is a static semantic region library expressed in the existing ASDL-layered compiler:

```text
LuaSrc.Op / LuaSrc.Window
  -> typed LuaExec semantic region
  -> typed LuaRT state/effects/outcomes
  -> typed CompileContract obligations
  -> typed MoonCFG region/kernel
  -> MoonCFG validation
  -> Moonlift emission
```

Each opcode family becomes a named, typed semantic region family in `LuaExec`, backed by explicit `LuaRT` state and lowered into `MoonCFG`. The semantic regions are static CFG expansions for the source window/proto being compiled. They are not dynamic bytecode dispatch and not a hidden interpreter.

The region library covers the major Lua 5.5 semantic families:

| Semantic family | Target representation |
|---|---|
| Calls and tailcalls | typed call regions, call frames, call results, yield/error outcomes, arity adjustment |
| Value sequences / arity | arbitrary `LuaRTValueSeq`/top/value-buffer semantics for open counts, padding, truncation, varargs, returns |
| Tables and metatables | typed table access/update regions, raw paths, metatable lookup, `__index`, `__newindex`, `__call` |
| Arithmetic/comparison/concat/len metamethods | typed operation regions with `MMBIN*` companion structure and explicit metamethod call paths |
| Closures and upvalues | closure construction, open/closed upvalue identity, upvalue reads/writes, lifetime, write barriers, epochs |
| Numeric loops | whole-region lowering for `FORPREP`/`FORLOOP` topology, integer/float state, backedges |
| Generic loops | iterator call/result/yield/close-aware regions for `TFOR*` groups |
| Close/TBC/error/yield | typed close-chain regions preserving ordering through return, tailcall, error, yield, and resume states |
| GC/allocation | allocation/root/barrier/finalizer state for tables, strings, closures, cdata, and other heap objects |
| FFI/cdata | typed ABI/cdata regions, scalar access/load/store, C calls, callbacks, ownership/finalizer facts |
| Constructors and bulk writes | `NEWTABLE`, `SETLIST`, `EXTRAARG`, barriers, allocation, open-result handling |
| Source companions/windows | explicit region handling for `EXTRAARG`, `MMBIN*`, comparison+`JMP`, loop groups, call/result windows |

The native VM may be consulted as a semantic reference, especially for opcode behavior and runtime object shape. It is not part of the accepted execution route.

### ASDL-first discipline

For each feature, the first artifact is the ASDL meaning. The roadmap does not treat lowering or emission as the source of truth.

A feature is not considered supported merely because:

- `LuaSrc` can decode it,
- foundry can produce facts for it,
- `moon_cfg_emit.lua` contains a fragment resembling it,
- the native VM has an opcode handler,
- a corpus window compiles through a helper path,
- or a stringly escape hatch can be emitted.

A feature is considered on the roadmap’s accepted path only when its semantics are represented as typed ASDL products across the relevant layers:

- `LuaRT` for runtime values/state/effects,
- `LuaExec` for semantic control regions,
- `CompileContract` / evidence for assumptions and invalidation,
- `MoonCFG` for emitted CFG structure.

This is especially important for dynamic Lua features. For example, a metatable-present table access is not an error under full Lua semantics; it may be a metamethod call. Therefore full table support requires ASDL-visible metatable and call semantics, not a raw-only success path pretending to be complete.

### Dependency sequencing constraints

The decision chooses opcode-complete static semantic regions, but it also incorporates the dependency ordering discipline identified in the analysis.

Some opcode families cannot be honestly completed before their shared prerequisites exist:

- `CALL`/`TAILCALL` and arity semantics are prerequisites for metamethods, generic `for`, FFI calls, callbacks, open results, and `__close`.
- General value sequences/top adjustment are prerequisites for calls, returns, varargs, `SETLIST`, and constructors.
- GC allocation/rooting/barriers are prerequisites for `NEWTABLE`, allocating `CONCAT`, `CLOSURE`, cdata creation, finalizers, and object initialization.
- Close/TBC state is prerequisite for close-aware returns, tailcalls, errors, yields, and finalization ordering.
- Metatable lookup and metamethod invocation are prerequisites for full table, arithmetic, comparison, concat, len, and callable-table behavior.
- Closure/upvalue semantics require allocation, frame lifetime, open/closed upvalue identity, barriers, and invalidation epochs.
- FFI/cdata support requires ABI/layout facts, symbol resolution, call semantics, GC ownership, and finalizer behavior.

The roadmap therefore does not measure progress by opcode-name count alone. It measures semantic family coverage under typed ASDL representation and executable lowering.

### Foundry, contracts, corpus, and stencil validation

Foundry facts and corpus coverage remain important, but they do not define semantic support by themselves.

The chosen target requires contracts and stencil identities to grow with semantics. Accepted kernels must record typed assumptions such as:

- call target identity and epoch,
- arity/result shape,
- metatable epoch and metamethod absence/presence,
- table shape/hash/array facts,
- closure proto and upvalue identity,
- upvalue epoch,
- GC allocation/barrier/root state,
- FFI symbol/layout/ABI facts,
- cdata ownership/finalizer facts.

Stencil artifacts must use typed patch holes and typed variant keys for these assumptions. Semantic strings or untyped helper names are not acceptable carriers of meaning.

Corpus reporting should remain fail-closed and should distinguish:

- decoded opcode coverage,
- available facts,
- accepted semantic family coverage,
- rejected unsupported semantic cases,
- stale/invalid contract cases.

### Tests and validation implications

The current validation posture remains part of the decision:

- unsupported semantics reject,
- standalone companion opcodes such as `MMBIN*` reject unless in valid context,
- external jumps reject,
- legacy fallback concepts remain forbidden,
- accepted products must pass `LuaExec` and `MoonCFG` validation,
- emitted kernels must come from typed regions, not helper strings or protocol exits.

Future tests are expected to validate the ASDL-first route for each semantic family:

- ASDL schema presence and shape,
- `LuaSrc` window/context preservation,
- `LuaExec` semantic region construction,
- `LuaExec -> MoonCFG` lowering,
- MoonCFG validation,
- Moonlift emission,
- PUC behavior conformance where applicable,
- negative tests for fake success and stale contracts,
- corpus representative coverage under typed contracts.

### Tradeoffs acknowledged

This decision prioritizes completeness, traceability, and semantic honesty over short-term corpus wins.

The accepted tradeoffs are:

- Generated `LuaExec`/`MoonCFG` may be larger than hand-specialized shards.
- Early progress may appear slower because shared runtime state and semantic regions must be defined before opcode families are accepted.
- The region library may require substantial ASDL expansion before many new corpus windows succeed.
- Optimization is secondary to correctness and explicitness at this stage.
- The native VM cannot be reused as an execution fallback, even where it already implements broader behavior.

These tradeoffs are acceptable because the goal is full Lua 5.5 semantic coverage without compromising the clean-base no-fallback invariant.

### Risks acknowledged

Known risks of the chosen target are:

- The static region library could become bulky if it mirrors VM handlers too literally.
- Large generated CFGs may need later optimization work.
- Calls, arity, yield, close, and GC interactions are complex and may force substantial changes to `LuaRT`, `LuaExec`, `MoonCFG`, validation, and emission.
- Weakening the validator’s forbidden-string policy could accidentally reintroduce legacy protocol fallback; the policy must evolve toward typed support, not become permissive.
- Contract omissions are dangerous: missing epochs, layouts, barriers, ABI facts, or metamethod dependencies can cause fake success.
- Opcode-complete coverage must not become dynamic bytecode dispatch. Each accepted source window must lower to explicit static semantic CFG.

The decision accepts these risks in order to keep SpongeJIT’s full Lua 5.5 roadmap aligned with its core architecture: typed ASDL products, explicit control, fail-closed compilation, and no hidden semantic escape hatches.

## Edit-planner Output — 2026-06-06 18:00:54

### Precondition Checks

Before edits begin, verify:

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
  - `LuaRT` starts at line 496; `CountSpec`/`ValueSeq` live around lines 546-587.
  - `LuaRT.CallShape`/`CallResult` live around lines 756-769.
  - `LuaGC` starts at line 875 and already owns allocation/root/barrier objects.
  - `LuaExec` starts at line 1119; `RegionKind` is currently lines 1135-1151.
  - `CompileContract` starts at line 1323.
  - `MoonCFG` starts at line 1357.
  - `Stencil` starts at line 1548.
- Existing schema tests still assert field order for:
  - `LuaRT.ValueSeq == "kind,values,count,origin"`
  - `LuaExec.Region == "id,kind,params,continuations,entry,blocks"`
  - `LuaExec.Kernel == "id,frame,body,contract"`
  - Do **not** change these field orders.
- `lua_src_to_lua_exec_lower.lua` still has:
  - `SUPPORTED_INSTR` at line 29.
  - `scan_shape` around line 139.
  - `lower_block` around line 682.
  - final region construction around lines 915-918.
- `lua_exec_to_moon_cfg_lower.lua` still rejects `Exec.EmitRegion` at lines 582-583.
- `moon_cfg_validate.lua` still forbids lowercase semantic fallback strings at lines 13-21.

---

### Files to Modify

#### `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`

**Goal**: Add ASDL-first static semantic region scaffolding while preserving the current executable slice and field-order tests.

**Edit blocks**

1. **Lines 546-587**: Modify/add LuaRT arity scaffolding after `ResultAdjustment`.
   - Keep existing `CountSpec`, `ValueSeq`, `SequenceOrigin`, and `ResultAdjustment`.
   - Add:
     ```asdl
     ArityKind = FixedArity | OpenArity | VarargArity | UnknownArity

     ArityShape = (LuaRT.CountSpec provided,
                   LuaRT.CountSpec wanted,
                   LuaRT.ResultAdjustment adjustment,
                   LuaRT.ArityKind kind) unique

     ResultChannelKind = DirectReturnChannel
                       | OutcomeReturnChannel
                       | ContinuationReturnChannel
                       | TailCallReturnChannel
                       | UnsupportedReturnChannel

     ResultChannel = (LuaRT.ResultChannelKind kind,
                      LuaRT.ValueSeq values,
                      LuaRT.CountSpec count) unique
     ```
   - Do **not** replace `ValueSeq`; this phase only makes arity explicit.

2. **Lines 756-769**: Extend call/tailcall state scaffolding after `CallResult`.
   - Add:
     ```asdl
     CallTargetKind = UnknownCallTarget
                    | LuaClosureCallTarget
                    | CClosureCallTarget
                    | LightCFunctionCallTarget
                    | MetamethodCallTarget
                    | FFICallTarget

     CallTarget = (LuaRT.CallTargetKind kind,
                   LuaRT.ValueRef callee,
                   LuaRT.Metamethod metamethod) unique

     CallStateKind = CallStart
                   | CallTargetResolved
                   | CallFramePrepared
                   | CallRunning
                   | CallResultsReady
                   | CallErrored
                   | CallYielded
                   | CallUnsupported

     CallState = (LuaRT.CallRef call,
                  LuaRT.CallShape shape,
                  LuaRT.CallTarget target,
                  LuaRT.CallStateKind state,
                  LuaRT.ResultChannel result_channel) unique
     ```
   - This is scaffolding only; no source `CALL` or `TAILCALL` should become accepted yet.

3. **Around lines 697-704**: Extend metatable/metamethod scaffolding after `MetamethodLookup`.
   - Add:
     ```asdl
     MetamethodCallHook = (LuaRT.MetamethodLookup lookup,
                           LuaRT.CallShape call,
                           LuaRT.ResultChannel result_channel) unique
     ```
   - This models hooks for future table/arithmetic/len/concat/call semantics without making them executable.

4. **Around lines 770-795**: Add close placeholder hooks after `CloseState`.
   - Add:
     ```asdl
     CloseHookKind = ExplicitCloseHook
                   | ReturnCloseHook
                   | TailCallCloseHook
                   | ErrorCloseHook
                   | YieldCloseHook
                   | FinalizerCloseHook

     CloseHook = (LuaRT.CloseHookKind kind,
                  LuaRT.CloseChain chain,
                  LuaRT.ResultChannel result_channel) unique
     ```

5. **Before `LuaGC` closing brace, around line 1116**: Add GC hook taxonomy inside `LuaGC`.
   - Add:
     ```asdl
     GCHookKind = AllocationHook
                | RootHook
                | BarrierHook
                | FinalizerHook
                | EpochHook

     GCHook = (LuaGC.GCHookKind kind,
               LuaGC.Control* controls,
               LuaGC.GCFact* facts) unique
     ```
   - Keep GC hooks in `LuaGC`, not `LuaRT`, because `LuaRT` appears before `LuaGC`.

6. **Lines 1119-1151**: Add region ids and opcode-family taxonomy in `LuaExec`.
   - After `Name`, add:
     ```asdl
     RegionId = (LuaExec.Name name) unique
     RegionRef = (LuaExec.RegionId id) unique
     ```
   - Extend `RegionKind` with:
     ```asdl
     CoreWindowRegion
     LoadMoveRegion
     BranchRegion
     TableAccessRegion
     MetatableRegion
     ClosureRegion
     UpvalueRegion
     GCAllocRegion
     FFIRegion
     OpcodeFamilyRegion
     ```
   - Add after `RegionKind`:
     ```asdl
     OpcodeFamily = LoadMoveFamily
                  | ArithmeticFamily
                  | CompareBranchFamily
                  | ReturnFamily
                  | CallFamily
                  | TailCallFamily
                  | TableAccessFamily
                  | TableSetFamily
                  | ConstructorFamily
                  | VarargFamily
                  | ClosureFamily
                  | UpvalueFamily
                  | NumericForFamily
                  | GenericForFamily
                  | CloseTBCFamily
                  | MetatableFamily
                  | GCFamily
                  | FFIFamily
                  | ErrorYieldFamily
                  | UnsupportedFamily

     RegionDescriptor = (LuaExec.RegionId id,
                         LuaExec.RegionKind kind,
                         LuaExec.OpcodeFamily family,
                         LuaRT.Pc start_pc,
                         LuaRT.Pc end_pc,
                         boolean executable) unique
     ```
   - Do **not** change `Region = (id, kind, params, continuations, entry, blocks)`.

7. **Around lines 1170-1220**: Add scaffold expressions only.
   - Add to `Expr`:
     ```asdl
     CallStateExpr(LuaRT.CallState call) unique
     MetamethodCallHookExpr(LuaRT.MetamethodCallHook hook) unique
     CloseHookExpr(LuaRT.CloseHook hook) unique
     GCHookExpr(LuaGC.GCHook hook) unique
     RegionDescriptorExpr(LuaExec.RegionDescriptor descriptor) unique
     ```
   - These should validate structurally but be rejected by executable lowering unless explicitly supported later.

8. **Around lines 1238-1254**: Extend obligations/guarantees.
   - Add `RequiresRegionDescriptor(LuaExec.RegionDescriptor descriptor)` to `LuaExec.Obligation`.
   - Add `DescribesRegion(LuaExec.RegionDescriptor descriptor)` to `LuaExec.Guarantee`.

9. **Lines 1323-1355**: Extend `CompileContract`.
   - Add typed assumptions:
     ```asdl
     SemanticAssumption = AssumesCallTarget(LuaRT.CallTarget target) unique
                        | AssumesArityShape(LuaRT.ArityShape shape) unique
                        | AssumesMetatable(LuaRT.ValueRef value, LuaRT.MetatableRef metatable) unique
                        | AssumesNoMetamethod(LuaRT.ValueRef value, LuaRT.Metamethod method) unique
                        | AssumesGCHook(LuaGC.GCHook hook) unique
                        | AssumesRegionDescriptor(LuaExec.RegionDescriptor descriptor) unique
                        | AssumesFFILayout(LuaFFI.CTypeId type_id, string layout_hash) unique
     ```
   - Add to `Obligation`:
     ```asdl
     | RequiresSemanticAssumption(CompileContract.SemanticAssumption assumption) unique
     ```
   - Add to `Guarantee`:
     ```asdl
     | GuaranteesSemanticAssumption(CompileContract.SemanticAssumption assumption) unique
     ```

10. **Lines 1548-1650**: Extend `Stencil.PatchSource`.
   - Add typed patch sources:
     ```asdl
     | FromCallTarget(LuaRT.CallTarget target) unique
     | FromRegionDescriptor(LuaExec.RegionDescriptor descriptor) unique
     | FromMetatableEpoch(LuaRT.MetatableRef metatable) unique
     | FromUpvalueEpoch(LuaRT.UpvalueRef upvalue) unique
     ```
   - Do not add stringly variant names.

**Danger zones**
- Do not rename `call`, `close`, etc. into lowercase string fields; existing validators forbid those strings intentionally.
- Do not change existing field order for tested constructors.
- Do not make `CALL` or `TAILCALL` accepted from `LuaSrc` in phase 1.

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua` **(new)**

**Goal**: Centralize static semantic region taxonomy and executable/scaffold classification.

**Contents sketch**
```lua
-- representation metadata only; no interpreter dispatch

local Schema = require("lua_compile.schema")
local T = Schema.get()
local Exec, RT = T.LuaExec, T.LuaRT

local M = {}

M.EXECUTABLE_REGION_KIND = {
  CoreWindowRegion = true,
  ReturnRegion = true,
  VarargRegion = true,
  ArithmeticRegion = true,
  TableGetRegion = true,
  TableSetRegion = true,
  LenRegion = true,
  ConcatRegion = true,
  ErrorRegion = true,
  GuardRegion = true,
}

M.SCAFFOLD_ONLY_REGION_KIND = {
  CallRegion = true,
  TailCallRegion = true,
  MetatableRegion = true,
  ClosureRegion = true,
  UpvalueRegion = true,
  GCAllocRegion = true,
  FFIRegion = true,
  NumericForRegion = true,
  GenericForRegion = true,
  CloseRegion = true,
}

function M.is_executable_region_kind(kind) ... end
function M.opcode_family_for_src_kind(kind) ... end
function M.region_kind_for_existing_block_term(term_kind) ... end
function M.descriptor(id, kind, family, start_pc, end_pc, executable) ... end
function M.validate_against_schema() ... end

return M
```

**Patterns**
- Follow existing model-file style from `lua_rt_stack_model.lua`.
- Metadata only. No helper calls, no dynamic dispatch.

---

#### New runtime model files under `experiments/lua_interpreter_vm/spongejit/lua_compile/`

Add these as schema/model metadata files:

1. `lua_rt_arity_model.lua`
   - Validates `ArityKind`, `ArityShape`, `ResultChannelKind`, `ResultChannel`.
   - Provides `is_fixed_shape(shape)` and `adjustment_supported_now(adjustment)`.
   - Phase-1 executable: fixed/count adjustment only, using current `ValueSeq` substrate.

2. `lua_rt_call_model.lua`
   - Validates `CallTargetKind`, `CallTarget`, `CallStateKind`, `CallState`.
   - Marks all real call targets as scaffold-only in phase 1.

3. `lua_rt_metatable_model.lua`
   - Validates `Metamethod`, `MetamethodLookup`, `MetamethodCallHook`.
   - Does not perform lookup.

4. `lua_rt_close_model.lua`
   - Validates `CloseHookKind`, `CloseHook`, existing `CloseState`.
   - No close execution.

5. `lua_rt_gc_alloc_model.lua`
   - Validates `LuaGC.GCHookKind` and `LuaGC.GCHook`.
   - Metadata only; no allocator lowering.

6. `lua_rt_closure_upvalue_model.lua`
   - Validates existing `ClosureRef`, `UpvalueRef`, plus scaffold assumptions.
   - Metadata only.

7. `lua_rt_loop_model.lua`
   - Validates existing `NumericForState`/`GenericForState`.
   - Metadata only.

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/init.lua`

**Goal**: Export new model modules.

**Edit block**

- **After lines 17-21**, add:
  ```lua
  M.lua_rt_arity_model = require("lua_compile.lua_rt_arity_model")
  M.lua_rt_call_model = require("lua_compile.lua_rt_call_model")
  M.lua_rt_metatable_model = require("lua_compile.lua_rt_metatable_model")
  M.lua_rt_close_model = require("lua_compile.lua_rt_close_model")
  M.lua_rt_gc_alloc_model = require("lua_compile.lua_rt_gc_alloc_model")
  M.lua_rt_closure_upvalue_model = require("lua_compile.lua_rt_closure_upvalue_model")
  M.lua_rt_loop_model = require("lua_compile.lua_rt_loop_model")
  M.lua_exec_region_model = require("lua_compile.lua_exec_region_model")
  ```

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua`

**Goal**: Add structural validation for new LuaRT scaffolding.

**Edit blocks**

1. **Lines 10-13**: require new model files.
2. **After `M.value_seq` around line 43**:
   - Add:
     ```lua
     function M.arity_shape(shape) ... end
     function M.result_channel(channel) ... end
     function M.call_state(state) ... end
     function M.metamethod_call_hook(hook) ... end
     function M.close_hook(hook) ... end
     ```
3. Validation should only check ASDL class membership and obvious invariants:
   - `ArityShape.provided/wanted` are `RT.CountSpec`.
   - `ResultChannel.values` is valid `ValueSeq`.
   - `CallState.shape` is `RT.CallShape`.
   - `MetamethodCallHook.call` is `RT.CallShape`.

**Danger zone**
- Do not add executable call/metatable behavior here. This is structural only.

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua`

**Goal**: Recognize new region scaffold classes structurally while preserving fail-closed lowering.

**Edit blocks**

1. **Top imports, lines 8-11**:
   - Add:
     ```lua
     local RegionModel = require("lua_compile.lua_exec_region_model")
     ```

2. **`validate_expr`, around lines 45-67**:
   - Add structural recognition for:
     - `Exec.CallStateExpr`
     - `Exec.MetamethodCallHookExpr`
     - `Exec.CloseHookExpr`
     - `Exec.GCHookExpr`
     - `Exec.RegionDescriptorExpr`
   - These should be “recognized but not executable”.

3. **`M.region`, after region kind check around line 129**:
   - If region kind is scaffold-only, allow structural validation.
   - Do **not** reject here; rejection happens in `lua_exec_to_moon_cfg_lower.lua`.

4. **Obligation/Guarantee validation**
   - If currently absent, add helpers to validate:
     - `RequiresRegionDescriptor`
     - `DescribesRegion`

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua`

**Goal**: Transition toward static region emission without changing current accepted behavior.

**Edit blocks**

1. **Header comment, lines 1-6**:
   - Replace “bounded core Lua value slice” wording with:
     ```lua
     -- This stage lowers LuaSrc windows into typed LuaExec static semantic
     -- regions. Phase 1 keeps the existing executable slice but attaches
     -- ASDL-visible region taxonomy. Unsupported dynamic regions remain reject-only.
     ```

2. **Imports, lines 8-12**:
   - Add:
     ```lua
     local RegionModel = require("lua_compile.lua_exec_region_model")
     ```

3. **`SUPPORTED_INSTR`, line 29**:
   - Do **not** add `CALL`, `TAILCALL`, `CLOSURE`, metatable, loop, or GC allocation opcodes.
   - Add a comment:
     ```lua
     -- Phase-1 static-region scaffolding does not expand accepted LuaSrc opcodes.
     ```

4. **`scan_shape`, around lines 139-219**:
   - Add explicit typed reject branches before generic unsupported:
     ```lua
     elseif op.kind == "CALL" then
       return nil, { "lua_exec:scaffold_only_region:CallRegion:" .. tostring(op.pc.id) }
     elseif op.kind == "TAILCALL" then
       return nil, { "lua_exec:scaffold_only_region:TailCallRegion:" .. tostring(op.pc.id) }
     elseif op.kind == "CLOSE" or op.kind == "TBC" then
       return nil, { "lua_exec:scaffold_only_region:CloseRegion:" .. tostring(op.pc.id) }
     elseif op.kind == "NEWTABLE" or op.kind == "CLOSURE" then
       return nil, { "lua_exec:scaffold_only_region:GCAllocRegion:" .. tostring(op.pc.id) }
     ```
   - Keep final `unsupported_instruction` fallback.

5. **`new_builder`, around line 384**:
   - Add a field:
     ```lua
     region_descriptors = {}
     ```

6. **Before `lower_value`, around line 905**:
   - Add:
     ```lua
     local function region_kind_for_shape(shape)
       return RegionModel.region_kind_for_existing_shape(shape)
     end

     local function region_descriptor_for_shape(shape)
       ...
     end
     ```
   - Descriptor should use first and last pc from `shape.blocks`.

7. **Final region construction, lines 915-918**:
   - Before:
     ```lua
     local region = Exec.Region(ename("lua_exec_core_body"), Exec.ReturnRegion, builder.kernel_params, {}, entry, blocks)
     ```
   - After:
     ```lua
     local rkind = region_kind_for_shape(shape) or Exec.CoreWindowRegion
     local descriptor = region_descriptor_for_shape(shape)
     builder.region_descriptors[#builder.region_descriptors + 1] = descriptor
     local region = Exec.Region(ename("lua_exec_core_body"), rkind, builder.kernel_params, {}, entry, blocks)
     local contract = Exec.Contract(
       { Exec.RequiresRegionDescriptor(descriptor) },
       { Exec.DescribesRegion(descriptor) }
     )
     return Exec.Kernel(ename("lua_exec_core_kernel"), make_frame(shape.blocks[1].pc), region, contract), nil
     ```
   - If changing contract causes too much churn, keep `empty_contract()` for current kernels and add descriptor only to tests/manual regions. But preferred phase-1 foundation is typed descriptor in contract.

**Danger zones**
- `coverage_summary()` must not report CALL/TAILCALL as supported.
- `MMBIN*` standalone rejection must remain.
- Existing green tests must keep passing.

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua`

**Goal**: Lower only executable static regions and reject scaffold-only regions explicitly.

**Edit blocks**

1. **Imports, lines 8-15**:
   - Add:
     ```lua
     local RegionModel = require("lua_compile.lua_exec_region_model")
     ```

2. **`lower_expr`, around lines 361-527**:
   - Add explicit rejects:
     ```lua
     if cls == Exec.CallStateExpr then
       return add_error(state, "scaffold_only_lua_exec_expr:CallStateExpr")
     end
     ...
     ```
   - Do this for all scaffold-only expressions.

3. **`lower_op`, around lines 582-583**:
   - Keep `Exec.EmitRegion` rejected unless a phase-1 arity-normalize region is deliberately implemented.
   - Error should mention:
     ```lua
     unsupported_lua_exec_op:EmitRegion:static_region_scaffold_only
     ```

4. **`lower_value`, around lines 813-840**:
   - Immediately after `local region = kernel.body`, add:
     ```lua
     if not RegionModel.is_executable_region_kind(region.kind) then
       return nil, { "lua_exec_to_moon_cfg:scaffold_only_region:" .. tostring(region.kind and region.kind.kind) }
     end
     ```
   - Preserve existing lowering for executable region kinds.

5. **Contract propagation, lines 24-38**
   - Existing `compile_contract` wraps exec obligations/guarantees into `CompileContract`.
   - Extend it to pass through `RequiresRegionDescriptor` / `DescribesRegion` as typed compile-contract obligations/guarantees.

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua`

**Goal**: Keep MoonCFG guardrails strict while recognizing any new typed ASDL nodes as non-fallback metadata.

**Edit blocks**

1. **Forbidden strings, lines 13-21**:
   - Do not remove anything.
   - Add comment:
     ```lua
     -- Future typed CallRegion/CloseRegion ASDL constructors are allowed as
     -- constructors, but lowercase semantic strings remain forbidden.
     ```

2. **`validate_runtime_expr`, lines 143-258**:
   - If new MoonCFG expressions are added for arity only, validate them here.
   - Do not add validation for dynamic call/metatable/GC execution yet.

3. **`validate_region`, lines 300-382**:
   - Keep `CFG.EmitRegion`, `CFG.Continue`, and `CFG.Exit` unsupported unless phase-1 explicitly emits a fixed arity normalization region.
   - If supporting `CFG.EmitRegion`, require:
     - target region exists,
     - continuations resolve,
     - region kind is executable,
     - no forbidden strings.

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua`

**Goal**: Emit only phase-1 executable value-seq/arity substrate; no call helper or protocol handoff.

**Edit blocks**

1. **Runtime value-seq rendering, around lines 683-707**:
   - Reuse existing `RuntimeValueSeqFixed`, `RuntimeValueSeqFromStack`, `RuntimeValueSeqAdjust`.
   - If ASDL adds a new MoonCFG arity expression, render it as explicit `LuaRTValueSeq` manipulation, not a helper call.

2. **Type inference, around lines 837-845**:
   - Add any new arity-only runtime expr to `LuaRTValueSeq`.
   - Do not infer callable/call/metatable/GC expressions as executable.

3. **Region rendering, around lines 1244-1248**:
   - No dynamic region emit support in phase 1 unless tests require the fixed arity normalization region.
   - Do not emit `call`, `close`, `generic_for`, `setlist`, `getvarg`, `out_tag`, or helper strings.

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua`

**Goal**: Validate typed semantic assumptions.

**Edit blocks**

1. **After `validate_payload_use`, around line 33**:
   - Add:
     ```lua
     local function validate_semantic_assumption(errors, a, path) ... end
     ```

2. **`validate_obligation`, around lines 35-60**:
   - Add case:
     ```lua
     elseif cls == T.CompileContract.RequiresSemanticAssumption then
       validate_semantic_assumption(errors, o.assumption, path .. ".assumption")
     ```

3. **`validate_guarantee`, around lines 62-80**:
   - Add case for `GuaranteesSemanticAssumption`.

4. Validation must reject raw strings as semantic carriers where typed nodes exist.

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_key.lua`

**Goal**: Ensure new contract assumptions are included structurally.

**Edit**
- Existing structural `key_value` should already include new ASDL constructors automatically.
- Add a comment near line 34:
  ```lua
  -- New semantic assumptions are intentionally keyed structurally through ASDL fields.
  ```

---

#### `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_key.lua`

**Goal**: Preserve no stringly variant hacks.

**Edit blocks**

1. **Forbidden exact strings, lines 15-27**:
   - Keep unchanged.

2. **`check_strings`, lines 42-58**:
   - No behavior change expected.
   - Add tests ensuring typed `FromCallTarget` / `FromRegionDescriptor` are accepted, but lowercase `"call"` remains rejected.

---

#### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua`

**Goal**: Assert ASDL/model presence for the new foundation.

**Edit blocks**

1. **After line 75**:
   - Add assertions for:
     - `LuaRT.ArityShape`
     - `LuaRT.ResultChannel`
     - `LuaRT.CallState`
     - `LuaRT.MetamethodCallHook`
     - `LuaRT.CloseHook`
     - `LuaGC.GCHook`

2. **After line 78**:
   - Add assertions for:
     - `LuaExec.RegionId`
     - `LuaExec.RegionDescriptor`
     - `LuaExec.OpcodeFamily`
     - new region kinds.

3. **After model validations around lines 58-68**:
   - Require new model modules and call `validate_against_schema()`.

4. **After CompileContract assertions around lines 20-22**:
   - Assert:
     - `T.CompileContract.SemanticAssumption`
     - `RequiresSemanticAssumption`
     - `GuaranteesSemanticAssumption`

---

#### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua` **(new)**

**Goal**: Test phase-1 static region foundation and no fake success.

**Contents sketch**
- Set package path like other SpongeJIT tests.
- Import:
  ```lua
  local C = require("lua_compile")
  local Schema = require("lua_compile.schema")
  local ExecLower = require("lua_compile.lua_src_to_lua_exec_lower")
  local ExecToMoon = require("lua_compile.lua_exec_to_moon_cfg_lower")
  local ExecValidate = require("lua_compile.lua_exec_validate")
  local RegionModel = require("lua_compile.lua_exec_region_model")
  ```
- Tests:
  1. `LOADI RETURN1` still compiles.
  2. Resulting `exec_kernel.body.kind` is executable per `RegionModel`.
  3. Exec contract contains typed region descriptor obligation/guarantee if implemented.
  4. Manual `Exec.Region(..., Exec.CallRegion, ...)` validates structurally.
  5. Manual `CallRegion` rejects in `ExecToMoon.lower` with `scaffold_only_region`.
  6. LuaSrc `CALL` still rejects through `compile_to_moon_kernel`.
  7. LuaSrc `TAILCALL` still rejects.
  8. `MMBIN` standalone still rejects.

---

#### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua`

**Goal**: Extend guardrail tests.

**Edit blocks**
- Around existing negative unsupported list near lines 344-345:
  - Keep `CALL`, `TAILCALL`, `CLOSE`, `TBC`, `TFOR*`, `SETLIST`, `GETVARG`.
  - Assert diagnostics mention `Reject`, not success.
- Add test that `StencilKey.check_no_forbidden_strings({ "call" })` fails, but a typed `CompileContract.SemanticAssumption.AssumesCallTarget(...)` key succeeds.

---

### Order of Operations

1. Update ASDL first.
2. Add new model files and export them from `init.lua`.
3. Extend validators.
4. Add `lua_exec_region_model.lua`.
5. Refactor `lua_src_to_lua_exec_lower.lua` to attach/use static region metadata without expanding accepted opcodes.
6. Add fail-closed checks in `lua_exec_to_moon_cfg_lower.lua`.
7. Update MoonCFG validator/emitter only for explicitly executable arity/value-seq scaffolding.
8. Update compile contract/stencil validation.
9. Add schema/model tests.
10. Add static region/no-fake-success tests.
11. Run verification.

---

### Testing Strategy

Run incrementally:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
```

Optional corpus check:

```sh
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Expected phase-1 behavior:
- Existing successful kernels remain successful.
- `CALL`/`TAILCALL`/metatable/GC/close dynamic semantics still reject.
- New region scaffolding appears in schema/model tests.
- No protocol/helper fallback strings appear in emitted Moonlift.

---

### Structured Edit Plan Sidecar

Updated workflow sidecar `wf-lua55-roadmap` to revision `r1` with tasks `T001`–`T012`.

Ready first task:
- `T001`: Extend ASDL semantic region foundation.

---

### Pattern Memo

- ASDL first: add typed products before lowering/emission.
- Scaffold-only means structurally valid but executable lowering rejects.
- Do not expand `SUPPORTED_INSTR` for `CALL`, `TAILCALL`, metatables, close/TBC, GC allocation, or FFI in phase 1.
- No lowercase semantic strings as variant keys or fallback tags.
- Existing executable tests must remain green.

## Worker Output — 2026-06-06 18:21:25

## Completed
Implemented Phase 1 ASDL-first static semantic region scaffolding for `wf-lua55-roadmap`.

- Added typed ASDL scaffolding for arity/result channels, call state, metamethod hooks, close hooks, GC hooks, LuaExec region descriptors/opcode families, semantic assumptions, and typed stencil patch sources.
- Added representation-only LuaRT/LuaExec model modules.
- Extended LuaRT, LuaExec, and CompileContract validators structurally.
- Added static region metadata to current LuaExec kernels without expanding accepted opcodes.
- Kept CALL/TAILCALL/metatable/GC/close/FFI execution scaffold-only/fail-closed.
- Added explicit scaffold-only rejection in LuaExec→MoonCFG lowering.
- Added schema/static-region/no-fake-success tests.
- Marked edit-plan tasks `T001`–`T012` complete.

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` - new typed scaffold constructors.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua` - new static region taxonomy/model.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_arity_model.lua` - new arity model.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_call_model.lua` - new call scaffold model.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_metatable_model.lua` - new metatable scaffold model.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_close_model.lua` - new close scaffold model.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_gc_alloc_model.lua` - new GC hook model.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_closure_upvalue_model.lua` - new closure/upvalue model.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_loop_model.lua` - new loop scaffold model.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/init.lua` - exports new models.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua` - validates new LuaRT scaffold nodes.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua` - validates region descriptors/scaffold expressions/contracts.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua` - attaches region descriptor contracts; scaffold-only source rejects.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua` - rejects scaffold-only regions/expressions; propagates semantic assumptions.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua` - preserved forbidden-string guardrail comment.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua` - validates semantic assumptions.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_key.lua` - structural-keying note.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua` - schema/model coverage.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua` - new static region tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua` - no-fake-success/contract/stencil tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_pipeline.lua` - planned file list updated.

## Verification
Passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Corpus result remained fail-closed: `37 ok / 104 rejected`, with test reporting `31 successful windows, 26 reps checked`.

## Notes
No remaining blockers. CALL/TAILCALL/close/GC allocation scaffolds are structurally valid typed products but still reject before MoonCFG execution, as required.

## Edit-planner Output — 2026-06-06 18:28:38

### Precondition Checks

Before edits begin, verify the repo still matches Phase 1:

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
  - `LuaRT.ValueSeq` field order is still `kind,values,count,origin` around lines 627-638.
  - `LuaRT.ArityShape` and `LuaRT.ResultChannel` exist around lines 650-668.
  - `LuaExec.Expr` includes `AdjustResultsExpr`, scaffold-only exprs around lines 1323-1358.
  - `LuaExec.Op.AssignSeq` exists around line 1395.
  - `MoonCFG.RuntimeValueSeq*` and `RuntimeOutcome*` exprs exist around lines 1548-1559.
  - Do **not** change tested field orders for `ValueSeq`, `ArityShape`, `ResultChannel`, `Region`, `Kernel`, `Block`.
- `lua_src_to_lua_exec_lower.lua`
  - `SUPPORTED_INSTR` is still line ~30 and must not gain `CALL`, `TAILCALL`, `SETLIST`, `TFOR*`.
  - `VARARG` lowering is around lines 510-523.
  - `return_seq_for` is around lines 660-688.
- `lua_exec_to_moon_cfg_lower.lua`
  - `lower_value_seq_runtime` is around lines 328-366.
  - `AssignSeq` currently stores only value0/value1 around lines 567-575.
  - `lower_return_outcome` currently uses `RuntimeOutcomeReturn(count, values, i64_const(0))` around lines 742-745.
- `moon_cfg_emit.lua`
  - `seq_value_at` currently returns value0/value1 or buffer directly around lines 597-600; Phase 2 must make this count-safe.
- Existing Phase 1 tests are green before starting.

---

## Files to Modify

### `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`

**Goal**: Add typed executable arity/value-sequence/result-channel vocabulary without changing current opcode acceptance.

**Edit blocks**

1. **Lines 633-668**: Modify `SequenceOrigin` and add executable arity normalization.
   - Add to `SequenceOrigin`:
     ```asdl
     | FromArityNormalization(LuaRT.ArityNormalization normalization) unique
     ```
   - After `ResultChannel`, add:
     ```asdl
     ArityNormalization = (LuaRT.ValueSeq source,
                           LuaRT.ArityShape shape,
                           LuaRT.ResultChannel channel) unique
     ```
   - Keep `ValueSeq = (kind, values, count, origin)` unchanged.

2. **Lines 1323-1358**: Extend `LuaExec.Expr`.
   - Add:
     ```asdl
     | NormalizeResultsExpr(LuaRT.ValueSeq seq, LuaRT.ArityShape shape) unique
     | ResultChannelExpr(LuaRT.ResultChannel channel) unique
     ```
   - These are executable only for fixed/open value-sequence normalization, not calls.

3. **Lines 1393-1415**: Keep `AssignSeq` but clarify it is lowered via normalized sequence store.
   - No field-order change.
   - `AssignSeq(dst, src, adjustment)` remains the LuaExec op used by current `VARARG`.

4. **Lines 1438-1477**: Extend LuaExec/CompileContract obligations.
   - Add to `LuaExec.Obligation`:
     ```asdl
     | RequiresArityShape(LuaRT.ArityShape shape) unique
     | RequiresResultChannel(LuaRT.ResultChannel channel) unique
     ```
   - Add to `LuaExec.Guarantee`:
     ```asdl
     | NormalizesArity(LuaRT.ArityNormalization normalization) unique
     | ProducesResultChannel(LuaRT.ResultChannel channel) unique
     ```
   - Add to `CompileContract.SemanticAssumption`:
     ```asdl
     | AssumesResultChannel(LuaRT.ResultChannel channel) unique
     ```

5. **Lines 1548-1559**: Extend `MoonCFG.Expr`.
   - Add:
     ```asdl
     | RuntimeValueSeqNormalize(MoonCFG.Value seq, LuaRT.ArityShape shape) unique
     | RuntimeValueSeqBuffer(MoonCFG.Value seq) unique
     | RuntimeValueSeqBase(MoonCFG.Value seq) unique
     | RuntimeOutcomeReturnSeq(MoonCFG.Value seq) unique
     | RuntimeOutcomeYieldSeq(LuaRT.ResumePoint resume_point,
                              MoonCFG.Value seq,
                              MoonCFG.Value saved_pc,
                              MoonCFG.Value saved_top) unique
     ```

6. **Lines 1618-1641**: Extend `MoonCFG.Op`.
   - Add:
     ```asdl
     | RuntimeValueSeqStore(MoonCFG.Value stack,
                            MoonCFG.Value base,
                            MoonCFG.Value seq) unique
     ```

**Danger zones**
- Do not alter `LuaRT.ResultChannel` field order.
- Do not add interpreter/protocol/fallback strings.
- Do not add CALL/TAILCALL execution constructors beyond scaffold metadata.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_arity_model.lua`

**Goal**: Make arity/result-channel semantics executable for fixed/open value sequences.

**Edit blocks**

1. **Header lines 1-3**: Update comment from “metadata only” to “typed arity semantics for current executable value-sequence slice”.

2. **After current kind tables, lines ~17-25**: Add supported adjustment helpers:
   ```lua
   M.EXECUTABLE_ADJUSTMENT = {
     ExactCount = true,
     FillNilTo = true,
     TruncateTo = true,
     OpenResult = true,
     PropagateOpenTail = true,
   }
   ```

3. **After `is_fixed_shape`, lines ~24-31**: Add helpers:
   - `fixed_count_value(count_spec)`
   - `adjustment_target_count(adjustment)`
   - `shape_for_adjustment(provided, wanted, adjustment)`
   - `result_channel(kind, seq, count)`
   - `normalization(source, shape, channel)`

4. **After `validate_result_channel`, lines ~45-52**: Add:
   ```lua
   function M.validate_arity_normalization(n) ... end
   function M.is_executable_normalization(n) ... end
   ```
   Rules:
   - `source` must be `LuaRT.ValueSeq`.
   - `shape` must validate.
   - `channel` must validate.
   - Reject `UnknownCount` / `DynamicCount` as executable in Phase 2 unless already represented by `OpenFromTop`/`OpenFromVarargs`.

5. **`validate_against_schema`, lines ~54-62**: Include `ArityNormalization`.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_stack_model.lua`

**Goal**: Document and expose safe value-sequence buffer semantics.

**Edit blocks**

1. **Lines 15-20**: Keep `LuaRTValueSeq` struct shape:
   ```moonlift
   kind, count, value0, value1, buffer: ptr(LuaRTValue), base
   ```
   Do not remove inline value0/value1.

2. **After `SEQ_KIND` table, lines ~30-38**: Add:
   ```lua
   M.INLINE_VALUE_COUNT = 2
   function M.requires_buffer_index(index) return index >= M.INLINE_VALUE_COUNT end
   ```

3. **`validate_against_schema`**: No behavioral change except ensure `AdjustedSeq` remains present.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_outcome_model.lua`

**Goal**: Let outcome values carry sequence buffer/base for fixed-shape result projection beyond value1.

**Edit block**

- **Lines 16-19**: Change emitted Moonlift struct from:
  ```moonlift
  value_buffer: i64;
  ```
  to:
  ```moonlift
  value_buffer: ptr(LuaRTValue); value_base: i64;
  ```
- Update all emitted outcome constructors later in `moon_cfg_emit.lua` to initialize both fields.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua`

**Goal**: Validate new LuaRT arity normalization.

**Edit blocks**

1. **After `result_channel`, lines ~65-76**:
   ```lua
   function M.arity_normalization(n)
     return ArityModel.validate_arity_normalization(n)
   end
   ```

2. Ensure `result_channel` still recursively validates `channel.values` with `M.value_seq`.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua`

**Goal**: Recognize Phase 2 arity/result-channel expressions and contract nodes structurally.

**Edit blocks**

1. In `validate_expr`, add recognition for:
   - `Exec.NormalizeResultsExpr`
   - `Exec.ResultChannelExpr`

2. In obligation/guarantee validation, add:
   - `RequiresArityShape`
   - `RequiresResultChannel`
   - `NormalizesArity`
   - `ProducesResultChannel`

**Danger zone**
- Validation is structural only; unsupported call/metatable/GC scaffold expressions must still validate structurally but reject in MoonCFG lowering.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua`

**Goal**: Validate result-channel assumptions.

**Edit block**

- **Inside `validate_semantic_assumption`, around lines 60-78**:
  - Add:
    ```lua
    elseif cls == T.CompileContract.AssumesResultChannel then
      if not is(a.channel, T.LuaRT.ResultChannel) then
        add(errors, path .. ".channel must be LuaRT.ResultChannel")
      end
    ```

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_key.lua`

**Goal**: Preserve structural identity for arity/result-channel contracts.

**Edit block**

- Add a comment near existing structural-key logic:
  ```lua
  -- ArityShape and ResultChannel assumptions are keyed structurally through ASDL;
  -- do not encode arity semantics as variant strings.
  ```
- No algorithm change expected.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_key.lua`

**Goal**: Keep no-stringly-stencil guardrails.

**Edit**
- No functional change expected.
- Add/extend tests only: variant keys containing typed arity/result-channel assumptions succeed; lowercase `"call"`, `"setlist"`, `"generic_for"` still fail.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua`

**Goal**: Route existing `RETURN`/`VARARG`/`GETVARG` through typed arity/value-sequence core without enabling new dynamic opcodes.

**Edit blocks**

1. **Imports, lines 7-11**:
   ```lua
   local ArityModel = require("lua_compile.lua_rt_arity_model")
   ```

2. **`SUPPORTED_INSTR`, line ~30**:
   - Do not add `CALL`, `TAILCALL`, `SETLIST`, `TFOR*`.

3. **Add helpers before `lower_instruction`, around line ~470**:
   - `fixed_count(n)`
   - `return_result_channel(seq)`
   - `arity_shape_for_seq(seq, adjustment)`
   - `normalized_seq(seq, adjustment, channel_kind)`
   - `add_arity_contract(builder, normalization)`

4. **`VARARG` lowering, lines 510-523**:
   - Current:
     ```lua
     local seq = RT.ValueSeq(RT.VarargSeq, {}, count_spec, RT.FromVarargs(vararg_source()))
     ops[#ops + 1] = Exec.AssignSeq(dst_window, seq, adjustment)
     ```
   - Change to construct:
     - source `VarargSeq`
     - `ArityShape`
     - `ResultChannel` with direct/continuation-style channel
     - `ArityNormalization`
     - adjusted `ValueSeq(RT.AdjustedSeq, {}, wanted_count, RT.FromArityNormalization(normalization))`
     - `Exec.AssignSeq(dst_window, adjusted_seq, adjustment)`
   - Preserve `SetTop` for open vararg.

5. **`return_seq_for`, lines 660-688**:
   - For `RETURN0`, `RETURN1`, fixed `RETURN`, open `RETURN`:
     - Build source seq as now.
     - Wrap in `ArityNormalization`.
     - Return adjusted seq with `FromArityNormalization`.
   - Keep rejects:
     - `close_upvalues`
     - `C != 0`
     - unsupported return close semantics.

6. **Final contract construction, lines 880-906**:
   - Extend `contract_for_descriptor` to include accumulated arity/result-channel obligations/guarantees from builder:
     ```lua
     Exec.RequiresArityShape(shape)
     Exec.RequiresResultChannel(channel)
     Exec.NormalizesArity(normalization)
     Exec.ProducesResultChannel(channel)
     ```
   - Preserve existing region descriptor contract entries.

**Danger zones**
- `coverage_summary()` must not report new opcodes.
- `SETLIST` remains `lua_exec:setlist_table_write_semantics_future`.
- `CALL`/`TAILCALL` remain scaffold-only rejects.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua`

**Goal**: Lower normalized value sequences and result channels into explicit MoonCFG runtime ops.

**Edit blocks**

1. **Imports, lines 8-16**:
   ```lua
   local ArityModel = require("lua_compile.lua_rt_arity_model")
   ```

2. **`lower_value_seq_runtime`, lines 328-366**:
   - Add case:
     ```lua
     elseif origin_cls == RT.FromArityNormalization then
       local n = seq.origin.normalization
       local src = lower_value_seq_runtime(state, env, n.source, label .. "_norm_src")
       return emit_expr(state, label .. "_normalized_seq",
         CFG.RuntimeValueSeqNormalize(src.value, n.shape), "lua_seq")
     ```
   - Keep old `FromAdjusted` fallback but do not use it for new lowering.

3. **`lower_expr`, lines 397-404**:
   - Add:
     - `Exec.NormalizeResultsExpr` → `CFG.RuntimeValueSeqNormalize`
     - `Exec.ResultChannelExpr` → lower `channel.values`.

4. **`AssignSeq`, lines 567-575**:
   - Replace two fixed stores with:
     ```lua
     local seq = lower_value_seq_runtime(...)
     local adjusted = emit_expr(... CFG.RuntimeValueSeqNormalize or RuntimeValueSeqAdjust ...)
     state.current_ops[#state.current_ops + 1] =
       CFG.RuntimeValueSeqStore(stack.value, i64_const(base), adjusted.value)
     ```
   - This is what makes `VARARG` fixed/open copies safe beyond two values.

5. **`lower_seq_runtime_values`, lines 705-712**:
   - Return normalized sequence value, not only `{v0,v1}`.
   - Use `RuntimeOutcomeReturnSeq(seq)` in outcome mode.

6. **`lower_return_outcome`, lines 742-745**:
   - Replace:
     ```lua
     CFG.RuntimeOutcomeReturn(count, values, i64_const(0))
     ```
   - With:
     ```lua
     CFG.RuntimeOutcomeReturnSeq(seq_entry.value)
     ```

7. **`lower_yield_outcome`, lines 759-761**:
   - Use `RuntimeOutcomeYieldSeq` to preserve count/buffer/base.

8. **Outcome projections, lines 715-738**:
   - Keep existing projections.
   - Add parser for dynamic names:
     - `value2_tag`
     - `value2_payload_i64`
     - `value3_tag`
     - etc.
   - Use existing `RuntimeOutcomeValueTag(out, index)` constructors.

9. **Contract propagation, lines 24-43**:
   - Convert new `LuaExec.RequiresArityShape` / `RequiresResultChannel` to `CompileContract.RequiresSemanticAssumption`.
   - Convert new guarantees similarly.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua`

**Goal**: Validate new MoonCFG arity/runtime ops while preserving forbidden fallback policy.

**Edit blocks**

1. **Forbidden strings, lines 13-21**:
   - Keep unchanged.

2. **`validate_runtime_expr`, lines 170-240**:
   - Add validation for:
     - `RuntimeValueSeqNormalize`
     - `RuntimeValueSeqBuffer`
     - `RuntimeValueSeqBase`
     - `RuntimeOutcomeReturnSeq`
     - `RuntimeOutcomeYieldSeq`
   - Remove “first two only” rejection for `RuntimeOutcomeReturnSeq`.

3. **Op validation, around `RuntimeStackStore` support**:
   - Add `RuntimeValueSeqStore`.
   - Validate stack is stack-like, base is i64-like, seq is seq-like.

4. **`infer_let_type`, lines 246-258**:
   - `RuntimeValueSeqNormalize` → `LuaRTValueSeq`
   - `RuntimeValueSeqBuffer` → `ptr(LuaRTValue)`
   - `RuntimeValueSeqBase` → `i64`
   - `RuntimeOutcomeReturnSeq` / `RuntimeOutcomeYieldSeq` → `LuaRTOutcome`

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua`

**Goal**: Emit safe executable sequence normalization, stack copies, and outcome projection beyond two values.

**Edit blocks**

1. **`seq_value_at`, lines 597-600**:
   - Replace direct field/buffer access with count-safe expression/block:
     - If `index >= seq.count`, yield nil.
     - `0` → `value0`
     - `1` → `value1`
     - `>=2` → buffer/base access only when buffer is non-null; otherwise nil.

2. **`render_outcome_index`, lines 613-616**:
   - Make index count-safe:
     - If index >= outcome.count → nil field result.
     - 0/1 use inline values.
     - >=2 use `outcome.value_buffer[outcome.value_base + index]` if non-null, else nil.

3. **`RuntimeOutcomeReturn` rendering, lines 647-655**:
   - Initialize new `value_buffer` as `ptr_null(LuaRTValue)` and `value_base = 0`.

4. **Add rendering for `RuntimeOutcomeReturnSeq`**:
   - Count from `seq.count`.
   - value0/value1 from safe sequence access.
   - value_buffer from `seq.buffer`.
   - value_base from `seq.base`.

5. **Add rendering for `RuntimeValueSeqNormalize`**:
   - `ExactCount`, `FillNilTo`, `TruncateTo`: set count to target count.
   - `OpenResult`, `PropagateOpenTail`: preserve source count.
   - value0/value1 must be nil-padded through safe access.
   - Preserve buffer/base.

6. **Add rendering for `RuntimeValueSeqStore` in `render_op`, around lines 1044-1047**:
   - Emit explicit Moonlift block loop copying `i = 0..seq.count-1`:
     ```moonlift
     stack[base + i] = seq_value_at(seq, i)
     ```
   - No helper calls.

7. **`infer_expr_type`, lines ~837-850**:
   - Add new expr types.

**Danger zones**
- Do not emit `out_tag`, `out_event_kind`, `call`, `close`, `generic_for`, or helper names.
- All nil padding must use `render_nil_value()`.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_to_moon_kernel.lua`

**Goal**: Keep public compile route honest with new result-channel core.

**Edit block**

- **`needs_outcome_mode`, lines 24-33**:
  - Add checks for:
    - `LuaExec.NormalizeResultsExpr`
    - `LuaExec.ResultChannelExpr`
  - Only if direct lowering would otherwise reject dynamic LuaRTValue returns.
  - Do not treat this as fallback; it is still `LuaExec -> MoonCFG`.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_foundry.lua`

**Goal**: Ensure foundry representative identity remains structural.

**Edit block**

- No semantic behavior change expected.
- If representative summaries include contract text, ensure arity/result-channel assumptions appear naturally through `CompileContract.Key`.
- Corpus success count should not be expected to increase from unsupported dynamic opcodes.

---

## Tests

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua`

Add assertions for:

- `LuaRT.ArityNormalization`
- `LuaRT.FromArityNormalization`
- `LuaExec.NormalizeResultsExpr`
- `LuaExec.ResultChannelExpr`
- `LuaExec.RequiresArityShape`
- `LuaExec.RequiresResultChannel`
- `LuaExec.NormalizesArity`
- `LuaExec.ProducesResultChannel`
- `CompileContract.AssumesResultChannel`
- `MoonCFG.RuntimeValueSeqNormalize`
- `MoonCFG.RuntimeValueSeqBuffer`
- `MoonCFG.RuntimeValueSeqBase`
- `MoonCFG.RuntimeValueSeqStore`
- `MoonCFG.RuntimeOutcomeReturnSeq`
- `MoonCFG.RuntimeOutcomeYieldSeq`

Keep existing field-order asserts.

---

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua` **(new)**

**Purpose**: Executable Phase 2 arity/value-sequence core tests.

Cover:

1. `RuntimeValueSeqNormalize(TruncateTo(1))`
   - count is 1
   - value0 preserved
   - value1 tag is nil

2. `RuntimeValueSeqNormalize(FillNilTo(3))`
   - count is 3
   - missing value2 projects as nil

3. Stack-backed seq with count 4
   - value2/value3 project from buffer safely.

4. `RuntimeValueSeqStore`
   - copies 3+ values from vararg/stack seq into stack.

5. `VARARG` fixed count >2
   - e.g. `VARARG c=4`, `RETURN b=4`
   - outcome count is 3
   - `value2_payload_i64` matches third vararg.

6. Open `VARARG`
   - top update still works.
   - value2 projection works.

7. `RETURN` fixed count >2
   - `LOADI` into slots, `RETURN b=4`
   - outcome count/value2 correct.

8. Out-of-range value projection returns nil, not memory garbage.

---

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua`

Add regression tests:

- Existing `RETURN0`, `RETURN1`, fixed `RETURN`, open `RETURN` still pass.
- Existing `VARARG`/`GETVARG` tests still pass.
- Exec kernel contract contains:
  - `RequiresArityShape`
  - `RequiresResultChannel`
  - `NormalizesArity`
  - `ProducesResultChannel`
  - compile contract contains structural semantic assumptions after MoonCFG lowering.

---

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua`

Add fail-closed checks:

- `CALL` rejects.
- `TAILCALL` rejects.
- `SETLIST` rejects.
- `TFORPREP`, `TFORCALL`, `TFORLOOP` reject.
- New arity/result-channel scaffolding does not make scaffold-only regions executable.

---

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua`

Add guardrail tests:

- Emitted source contains no forbidden protocol strings.
- `StencilKey` accepts typed arity/result-channel contracts.
- Lowercase semantic strings still rejected.

---

## Order of Operations

1. Update ASDL first.
2. Update `lua_rt_arity_model.lua`, `lua_rt_stack_model.lua`, `lua_rt_outcome_model.lua`.
3. Update LuaRT/LuaExec/CompileContract validators.
4. Update LuaSrc lowering to build typed arity normalization for existing supported ops only.
5. Update LuaExec→MoonCFG lowering.
6. Update MoonCFG validator/emitter.
7. Update public compile route/foundry contract expectations.
8. Add schema/model tests.
9. Add new arity executable tests.
10. Add regressions/fail-closed tests.
11. Run verification.

---

## Testing Strategy

Run incrementally:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
```

Optional corpus:

```sh
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Expected Phase 2 behavior:

- Current successful kernels remain successful.
- Existing `VARARG`/`RETURN` support becomes safer for fixed/open value sequences.
- No new dynamic opcode family becomes accepted.
- `CALL`, `TAILCALL`, `SETLIST`, generic-for remain fail-closed.
- No forbidden protocol/helper strings appear.

---

## Structured Edit Plan Sidecar

Updated workflow sidecar `wf-lua55-roadmap` to revision `r26`.

Added tasks:

- `T013` Extend ASDL arity execution vocabulary
- `T014` Implement arity model semantics helpers
- `T015` Extend structural validators for arity nodes
- `T016` Add contract identity support for result channels
- `T017` Refactor LuaSrc lowering to emit arity normalization
- `T018` Lower arity normalization to MoonCFG
- `T019` Emit and validate safe value-sequence runtime ops
- `T020` Update compile route and foundry expectations
- `T021` Update schema and model tests
- `T022` Add executable arity/value-sequence tests
- `T023` Add regression and fail-closed tests
- `T024` Run Phase 2 verification gates

Ready task: `T013`.

---

## Pattern Memo

- ASDL first; no stringly semantics.
- Phase 2 expands value-sequence/arity execution only, not dynamic calls.
- Count-safe projection: out-of-range sequence/outcome values yield nil.
- `AssignSeq` must copy by explicit typed loop, not first-two-only stores.
- Result/arity assumptions must appear structurally in contracts/stencil keys.
- Unsupported dynamic semantics remain `Reject`, not fake success.

## Worker Output — 2026-06-06 19:03:20

## Completed
Implemented Phase 2 executable value-sequence/arity core for `wf-lua55-roadmap`.

- Added ASDL vocabulary for `ArityNormalization`, `FromArityNormalization`, arity/result-channel Exec contracts, `AssumesResultChannel`, and MoonCFG sequence/outcome runtime nodes.
- Added/extended arity model, validators, contract keying, LuaSrc→LuaExec lowering, LuaExec→MoonCFG lowering, MoonCFG validation/emission.
- Refactored existing `RETURN`/`VARARG` sequence paths through typed arity normalization without enabling new dynamic opcode families.
- Kept `CALL`, `TAILCALL`, `SETLIST`, generic-for, close/GC dynamic semantics fail-closed.
- Added Phase 2 arity tests and updated regression/guardrail tests.
- Completed edit-plan tasks `T013`–`T024`.

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` - Phase 2 ASDL nodes.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_arity_model.lua` - executable arity helpers/validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_stack_model.lua` - sequence buffer metadata.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_outcome_model.lua` - outcome buffer/base representation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua` - arity normalization validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua` - new Exec expr/contract validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua` - `AssumesResultChannel`.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_key.lua` - structural keying note.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua` - typed arity normalization/contracts.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua` - normalized seq lowering and projections.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua` - new runtime expr/op validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua` - safe seq store/projection emission.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_to_moon_kernel.lua` - outcome-mode detection.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua` - schema/validator coverage.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua` - new executable arity tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua` - arity contracts/fail-closed checks.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua` - arity contract/outcome regressions.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua` - result-channel contract key coverage.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_stack.lua` - legacy vararg projection coverage moved to new arity test.

## Verification
Passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Corpus remained fail-closed: `37 ok / 104 rejected`; report now checks `27` reps.

## Notes
No remaining blockers. Phase 2 expands arity/value-sequence execution only; dynamic call/metatable/close/GC/generic-for semantics remain rejected.

## Edit-planner Output — 2026-06-06 19:09:59

### Precondition Checks

Before edits begin, verify:

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
  - `LuaRT.ResultChannel` field order is still `kind,values,count` at lines ~661-669.
  - `LuaRT.CallShape` field order is still `callee,args,wanted_results,is_tailcall,may_yield` at lines ~787-791.
  - `LuaRT.CallTarget` field order is still `kind,callee,metamethod` at lines ~810-812.
  - `LuaRT.CallState` field order is still `call,shape,target,state,result_channel` at lines ~823-827.
  - `LuaExec.Region` field order is still `id,kind,params,continuations,entry,blocks`.
  - `LuaExec.Expr` starts around line ~1320; `LuaExec.Op` starts around line ~1400.
  - `MoonCFG.Expr` starts around line ~1545; `MoonCFG.Op` starts around line ~1647.
- `lua_src_to_lua_exec_lower.lua`
  - `SUPPORTED_INSTR` still does **not** include `CALL` or `TAILCALL`.
  - `CALL` still rejects with `lua_exec:scaffold_only_region:CallRegion`.
  - `TAILCALL` still rejects with `lua_exec:scaffold_only_region:TailCallRegion`.
- `lua_exec_region_model.lua`
  - `CallRegion`/`TailCallRegion` are currently scaffold-only.
- Phase 1 + Phase 2 tests are green before starting.

---

## Phase 3 Scope Decision

Phase 3 should **not accept LuaSrc `CALL` or `TAILCALL` yet**.

Current repo facts do not yet support safe source-level call execution:

- no executable closure body/proto dispatch path,
- no static callee-region invocation lowering,
- no close/yield/tailcall replacement semantics,
- no complete call-target evidence contract path from source op to executable region.

Instead, Phase 3 establishes an **ASDL-first fixed-shape call-frame substrate**:

- typed call target identity/resolution,
- typed call argument/result channels,
- typed call frame layout/state,
- fixed-shape call-frame argument/result transfer,
- contract/stencil identity for call assumptions,
- manually constructed `CallRegion` can lower only when fully typed and contracted,
- source `CALL`/`TAILCALL` remain fail-closed.

This is call foundation, not a generic interpreter-like call fallback.

---

## Files to Modify

### `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`

**Goal**: Add typed Phase 3 call-frame/call-target/result-channel vocabulary without changing existing field orders.

**Edit blocks**

1. **Lines ~779-827, after existing `CallState`**: Add LuaRT call target identity and call frame substrate.

   Add:

   ```asdl
   CallFrameRef = (LuaRT.Name name) unique

   CallTargetIdentity = UnknownTargetIdentity unique
                      | LuaClosureTargetIdentity(LuaRT.ClosureRef closure,
                                                  LuaSrc.KRef proto,
                                                  number closure_handle,
                                                  LuaFact.Dependency* deps) unique
                      | CClosureTargetIdentity(LuaRT.ClosureRef closure,
                                                number function_handle,
                                                LuaFact.Dependency* deps) unique
                      | LightCFunctionTargetIdentity(LuaRT.FunctionRef function,
                                                       number function_handle,
                                                       LuaFact.Dependency* deps) unique
                      | MetamethodTargetIdentity(LuaRT.Metamethod method,
                                                 LuaRT.ValueRef receiver,
                                                 LuaFact.Dependency* deps) unique
                      | FFISymbolTargetIdentity(LuaFFI.CSymbolId symbol,
                                                LuaFact.Dependency* deps) unique

   ResolvedCallTarget = (LuaRT.CallTarget target,
                         LuaRT.CallTargetIdentity identity,
                         LuaRT.CallableKind callable) unique

   CallArgChannel = (LuaRT.CallRef call,
                     LuaRT.ValueSeq args,
                     LuaRT.ArityShape shape) unique

   CallFrameLayout = (LuaRT.CallFrameRef id,
                      LuaRT.FrameRef caller,
                      LuaRT.FrameRef callee,
                      LuaRT.Slot callee_slot,
                      LuaRT.Slot arg_base,
                      LuaRT.CountSpec arg_count,
                      LuaRT.Slot result_base,
                      LuaRT.CountSpec result_count,
                      LuaRT.Count frame_slots) unique

   CallFrameStateKind = CallFrameUnprepared
                      | CallFrameArgsStored
                      | CallFrameActive
                      | CallFrameResultsReady
                      | CallFrameReleased
                      | CallFrameUnsupported

   CallResultChannel = (LuaRT.CallRef call,
                        LuaRT.ResultChannel channel,
                        LuaRT.ArityNormalization normalization) unique

   CallFrameState = (LuaRT.CallFrameLayout layout,
                     LuaRT.CallArgChannel args,
                     LuaRT.CallResultChannel results,
                     LuaRT.ResolvedCallTarget target,
                     LuaRT.CallFrameStateKind state) unique
   ```

   **Notes**
   - Do not alter `CallShape`, `CallTarget`, or `CallState`.
   - `UnknownTargetIdentity` is structural only and must never be executable.

2. **Line ~661, `ResultChannelKind`**: Add a call-specific result channel kind.

   ```asdl
   | CallFrameResultChannel
   ```

   **Note**: Append only; do not reorder existing result channel variants.

3. **Line ~1320, `LuaExec.Expr`**: Add call substrate expressions.

   ```asdl
   | ResolvedCallTargetExpr(LuaRT.ResolvedCallTarget target) unique
   | CallArgChannelExpr(LuaRT.CallArgChannel channel) unique
   | CallFrameStateExpr(LuaRT.CallFrameState frame) unique
   | CallResultChannelExpr(LuaRT.CallResultChannel channel) unique
   ```

4. **Line ~1400, `LuaExec.Op`**: Add explicit call-frame transfer ops.

   ```asdl
   | PrepareCallFrame(LuaRT.CallFrameState frame) unique
   | ReceiveCallResults(LuaRT.CallFrameState frame) unique
   ```

   **Meaning**
   - `PrepareCallFrame`: stores normalized args into the callee frame.
   - `ReceiveCallResults`: normalizes callee result sequence into caller result channel.
   - Neither op invokes a callee body.

5. **Line ~1240, after `RegionDescriptor` or near LuaExec region metadata**: Add static call continuation metadata.

   ```asdl
   CallContinuationRegion = (LuaRT.CallRef call,
                             LuaExec.RegionRef callee_region,
                             LuaExec.ContRef return_cont,
                             LuaExec.ContRef error_cont,
                             LuaExec.ContRef yield_cont) unique
   ```

   **Phase 3 status**: validate structurally only; do not emit `EmitRegion`.

6. **Lines ~1435-1449, LuaExec obligations/guarantees**: Add typed call contracts.

   ```asdl
   -- Obligation
   | RequiresResolvedCallTarget(LuaRT.ResolvedCallTarget target) unique
   | RequiresCallFrameLayout(LuaRT.CallFrameLayout layout) unique
   | RequiresCallArgChannel(LuaRT.CallArgChannel channel) unique
   | RequiresCallResultChannel(LuaRT.CallResultChannel channel) unique

   -- Guarantee
   | ResolvesCallTarget(LuaRT.ResolvedCallTarget target) unique
   | PreparesCallFrame(LuaRT.CallFrameState frame) unique
   | ProducesCallResults(LuaRT.CallResultChannel channel) unique
   ```

7. **Lines ~1463-1470, `CompileContract.SemanticAssumption`**: Add call assumptions.

   ```asdl
   | AssumesResolvedCallTarget(LuaRT.ResolvedCallTarget target) unique
   | AssumesCallFrameLayout(LuaRT.CallFrameLayout layout) unique
   | AssumesCallArgChannel(LuaRT.CallArgChannel channel) unique
   | AssumesCallResultChannel(LuaRT.CallResultChannel channel) unique
   | AssumesCallTargetIdentity(LuaRT.CallTargetIdentity identity) unique
   ```

8. **Lines ~1545-1620, `MoonCFG.Expr`**: Add typed call runtime expressions.

   ```asdl
   | RuntimeClassifyCallee(MoonCFG.Value callee) unique
   | RuntimeCallTargetCheck(MoonCFG.Value callee,
                            LuaRT.ResolvedCallTarget target) unique
   | RuntimeCallFramePrepare(MoonCFG.Value caller_stack,
                             MoonCFG.Value callee_stack,
                             LuaRT.CallFrameLayout layout,
                             MoonCFG.Value args) unique
   | RuntimeCallFrameResultSeq(MoonCFG.Value callee_stack,
                               LuaRT.CallFrameLayout layout,
                               LuaRT.CallResultChannel channel) unique
   ```

9. **Lines ~1647-1666, `MoonCFG.Op`**: Add explicit arg transfer op.

   ```asdl
   | RuntimeCallFrameStoreArgs(MoonCFG.Value callee_stack,
                               LuaRT.CallFrameLayout layout,
                               MoonCFG.Value args) unique
   ```

   Result transfer can reuse `RuntimeValueSeqStore`.

10. **Lines ~1806+, `Stencil.PatchSource`**: Add typed call patch sources.

   ```asdl
   | FromCallTargetIdentity(LuaRT.CallTargetIdentity identity) unique
   | FromCallFrameLayout(LuaRT.CallFrameLayout layout) unique
   ```

**Danger zones**

- Do not introduce lowercase `"call"` string semantics.
- Do not add VM dispatch, protocol exits, or helper-name fallback.
- Do not make `UnknownTargetIdentity` executable.
- Do not accept `TAILCALL`.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_call_model.lua`

**Goal**: Evolve from scaffold metadata into Phase 3 fixed-shape call-frame validation/executability helpers.

**Edit blocks**

1. **Lines 1-3**: Update comment.

   Say Phase 3 supports fixed-shape call-frame substrate only; source `CALL` remains rejected.

2. **After current kind tables, lines ~13-30**: Add tables for:

   - executable target kind: only `LuaClosureCallTarget`
   - non-executable target kinds: unknown, C closure, light C function, metamethod, FFI
   - executable frame states: `CallFrameUnprepared`, `CallFrameArgsStored`, `CallFrameResultsReady`

3. **Add `TYPE_DECL`** for emission:

   ```lua
   M.FRAME_TYPE_NAME = "LuaRTCallFrame"
   M.TYPE_DECL = [[
   struct LuaRTCallFrame
       caller_stack: ptr(LuaRTValue);
       callee_stack: ptr(LuaRTValue);
       arg_base: i64;
       arg_count: i64;
       result_base: i64;
       result_count: i64;
       target_ok: bool;
   end
   ]]
   ```

4. **Add validators**:

   - `validate_call_target_identity(identity)`
   - `validate_resolved_call_target(target)`
   - `validate_call_arg_channel(channel)`
   - `validate_call_result_channel(channel)`
   - `validate_call_frame_layout(layout)`
   - `validate_call_frame_state(frame)`

5. **Add executable checks**:

   - `is_executable_resolved_target(target)`
     - true only for:
       - `target.target.kind == LuaClosureCallTarget`
       - `target.identity.kind == LuaClosureTargetIdentity`
       - `target.callable == CallableLuaClosure`
       - `closure_handle >= 0`
     - false for unknown, C, FFI, metamethod, light C function.
   - `is_executable_frame_layout(layout)`
     - fixed `arg_count` and fixed `result_count` only.
   - `is_executable_call_frame_state(frame)`
     - direct Lua closure target,
     - non-tail call,
     - fixed arity,
     - executable result normalization.

6. **`validate_against_schema()`**: Include all new constructors.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua`

**Goal**: Add structural entry points for new LuaRT call products.

**Edit blocks**

1. **After `M.call_state`, around lines ~100-104**: Add:

   ```lua
   function M.call_target_identity(identity) ... end
   function M.resolved_call_target(target) ... end
   function M.call_arg_channel(channel) ... end
   function M.call_result_channel(channel) ... end
   function M.call_frame_layout(layout) ... end
   function M.call_frame_state(frame) ... end
   ```

2. Delegate to `CallModel`.

**Danger zone**: structural validation only; do not bless executable source calls here.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua`

**Goal**: Recognize new LuaExec call substrate nodes structurally.

**Edit blocks**

1. **`validate_region_descriptor`, lines ~48-65**:
   - Current validation rejects `executable=true` on scaffold-only region kind.
   - Replace with `RegionModel.is_potentially_executable_region_kind(kind)`.
   - Allow `CallRegion` as potentially executable; actual contract gating happens in `lua_exec_to_moon_cfg_lower.lua`.

2. **`validate_expr`, lines ~70-120**:
   - Add cases for:
     - `ResolvedCallTargetExpr`
     - `CallArgChannelExpr`
     - `CallFrameStateExpr`
     - `CallResultChannelExpr`

3. **Region op validation, lines ~180-230**:
   - Add cases for:
     - `PrepareCallFrame`
     - `ReceiveCallResults`

4. **Contract validation, lines ~235-270**:
   - Add new call obligations/guarantees.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua`

**Goal**: Permit executable `CallRegion` only with typed Phase 3 contract.

**Edit blocks**

1. **Keep `CallRegion` in `SCAFFOLD_ONLY_REGION_KIND`** for kind-only checks.

2. **Add**:

   ```lua
   function M.is_potentially_executable_region_kind(kind) ... end
   function M.is_executable_region(region, contract) ... end
   ```

3. Rules:
   - Existing executable kinds pass.
   - `CallRegion` passes only if `CallModel.contract_allows_executable_call_region(contract)` is true.
   - `TailCallRegion` remains false.
   - `OpcodeFamilyRegion` remains false.

4. Update `validate_against_schema()` to include call continuation region constructors.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua`

**Goal**: Lower fixed-shape call-frame substrate into typed MoonCFG.

**Edit blocks**

1. **Imports, lines ~8-16**:
   - Add:

     ```lua
     local CallModel = require("lua_compile.lua_rt_call_model")
     ```

2. **`compile_contract`, lines ~31-55**:
   - Convert new LuaExec call obligations/guarantees to `CompileContract.RequiresSemanticAssumption` / `GuaranteesSemanticAssumption`.

3. **Add helpers near stack helpers, after lines ~180-230**:

   - `lower_call_target_check(state, env, target, callee_value)`
   - `lower_call_args_seq(state, env, arg_channel)`
   - `lower_call_frame_layout(state, env, layout)`
   - `lower_call_result_seq(state, env, result_channel)`

4. **`lower_expr`, lines ~384-560**:
   - Replace unconditional `CallStateExpr` scaffold rejection.
   - New behavior:
     - If `CallModel.is_executable_call_frame_state(expr.call)` then lower to `CFG.RuntimeCallFramePrepare`.
     - Otherwise reject with:
       `unsupported_lua_exec_call_state:<reason>`
   - Add expression lowering for new call exprs.

5. **`lower_op`, lines ~574-630**:
   - Add `PrepareCallFrame`:
     - validate executable frame state,
     - lower args seq,
     - find callee stack via `stack_value_for_ref`,
     - emit `CFG.RuntimeCallFrameStoreArgs`.
   - Add `ReceiveCallResults`:
     - lower result seq from callee stack via `CFG.RuntimeCallFrameResultSeq`,
     - normalize through existing arity path,
     - store to caller result base with `CFG.RuntimeValueSeqStore`.

6. **`lower_value`, lines ~915-924**:
   - Replace:

     ```lua
     RegionModel.is_executable_region_kind(region.kind)
     ```

     with:

     ```lua
     RegionModel.is_executable_region(region, kernel.contract)
     ```

   - Empty/under-contracted `CallRegion` must still reject.

7. **Do not lower `Exec.EmitRegion`**.
   - Static call continuation regions remain metadata only in Phase 3.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua`

**Goal**: Validate typed call runtime nodes without weakening forbidden-string policy.

**Edit blocks**

1. **Forbidden strings, lines ~15-21**:
   - Keep unchanged.

2. **Supported ops table, lines ~25-35**:
   - Add `CFG.RuntimeCallFrameStoreArgs`.

3. **`validate_runtime_expr`, lines ~162-248**:
   - Add validation for:
     - `RuntimeClassifyCallee`
     - `RuntimeCallTargetCheck`
     - `RuntimeCallFramePrepare`
     - `RuntimeCallFrameResultSeq`

4. **`infer_let_type`, lines ~252-270**:
   - `RuntimeClassifyCallee` → `i64`
   - `RuntimeCallTargetCheck` → `bool`
   - `RuntimeCallFramePrepare` → `LuaRTCallFrame`
   - `RuntimeCallFrameResultSeq` → `LuaRTValueSeq`

5. **`validate_expr`, lines ~272-294**:
   - Include new call runtime exprs.

6. **Op validation, lines ~322-334**:
   - Validate `RuntimeCallFrameStoreArgs` requires a seq-like `args` value.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua`

**Goal**: Emit explicit Moonlift call-frame substrate.

**Edit blocks**

1. **Imports/top section**:
   - Require `lua_rt_call_model`.

2. **`render_kernel`, lines ~1460-1480**:
   - Add `CallModel.TYPE_DECL` after `StackModel.TYPE_DECL`.

3. **`render_expr`, lines ~650-820**:
   - Add:
     - `RuntimeClassifyCallee`: returns callable kind integer from value tag.
     - `RuntimeCallTargetCheck`: checks Lua closure tag + expected handle for `LuaClosureTargetIdentity`; false for all unsupported target identities.
     - `RuntimeCallFramePrepare`: returns `LuaRTCallFrame` struct.
     - `RuntimeCallFrameResultSeq`: returns `LuaRTValueSeqFromStack`-style sequence from callee stack/result base/count.

4. **`infer_expr_type`, lines ~920-935**:
   - Add call runtime types.

5. **`render_op`, lines ~1240-1260**:
   - Add `RuntimeCallFrameStoreArgs`:
     - emit explicit stores using existing sequence projection logic,
     - copy all values through a typed loop,
     - no helper function call.

**Danger zones**

- Do not emit strings: `"call"`, `"close"`, `"generic_for"`, `"out_tag"`, `"out_event_kind"`.
- Do not emit VM dispatch or function pointer invocation.
- Do not implement dynamic callee dispatch.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua`

**Goal**: Validate typed call assumptions structurally.

**Edit blocks**

1. **`validate_semantic_assumption`, around lines ~58-78**:
   - Add cases for:
     - `AssumesResolvedCallTarget`
     - `AssumesCallFrameLayout`
     - `AssumesCallArgChannel`
     - `AssumesCallResultChannel`
     - `AssumesCallTargetIdentity`

2. Reject malformed `UnknownTargetIdentity` only in executable-call helper checks, not structural validation.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_key.lua`

**Goal**: Keep call identity structural.

**Edit**

- Add comment near existing structural-key comments:

  ```lua
  -- Phase 3 call target identity, frame layout, and result channels are keyed
  -- structurally through ASDL; never encode call semantics as variant strings.
  ```

No algorithm change expected.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_key.lua`

**Goal**: Preserve no-stringly call semantics.

**Edit**

- No functional change expected.
- Add tests: typed `FromCallTargetIdentity` and `FromCallFrameLayout` are accepted; lowercase `"call"` remains rejected.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua`

**Goal**: Keep source `CALL`/`TAILCALL` fail-closed.

**Edit blocks**

1. **`SUPPORTED_INSTR`, line ~29**:
   - Do not add `CALL` or `TAILCALL`.

2. **`scan_shape`, lines ~191-195**:
   - Preserve explicit rejects.
   - Add comment:

     ```lua
     -- Phase 3 call-frame substrate is executable only in manually constructed
     -- typed CallRegion products. Source CALL/TAILCALL remain rejected until
     -- static callee region invocation, close/yield, and target contracts exist.
     ```

---

## Tests

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua`

Add assertions for all new ASDL nodes:

- `LuaRT.CallTargetIdentity`
- `LuaRT.ResolvedCallTarget`
- `LuaRT.CallArgChannel`
- `LuaRT.CallFrameLayout`
- `LuaRT.CallFrameState`
- `LuaRT.CallResultChannel`
- `LuaExec.PrepareCallFrame`
- `LuaExec.ReceiveCallResults`
- `LuaExec.RequiresResolvedCallTarget`
- `LuaExec.RequiresCallFrameLayout`
- `LuaExec.ResolvesCallTarget`
- `CompileContract.AssumesResolvedCallTarget`
- `CompileContract.AssumesCallFrameLayout`
- `MoonCFG.RuntimeClassifyCallee`
- `MoonCFG.RuntimeCallTargetCheck`
- `MoonCFG.RuntimeCallFramePrepare`
- `MoonCFG.RuntimeCallFrameResultSeq`
- `MoonCFG.RuntimeCallFrameStoreArgs`
- `Stencil.FromCallTargetIdentity`
- `Stencil.FromCallFrameLayout`

Keep old field-order assertions unchanged.

---

### New file: `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_call.lua`

**Purpose**: Phase 3 executable fixed-shape call-frame substrate tests.

Cover:

1. `RuntimeClassifyCallee`:
   - Lua closure tag → callable Lua closure kind.
   - integer/nil/table → not callable.

2. `RuntimeCallTargetCheck`:
   - Lua closure tag + matching payload handle succeeds.
   - mismatched handle fails.
   - unknown target fails.

3. `RuntimeCallFrameStoreArgs`:
   - copies 3+ args from caller sequence to callee stack.

4. `RuntimeCallFrameResultSeq`:
   - projects 3+ callee results with count-safe value2/value3.

5. Manual executable `LuaExec.CallRegion`:
   - has fixed direct Lua closure target identity,
   - has call frame layout,
   - has arg/result channels,
   - validates structurally,
   - lowers to MoonCFG,
   - validates,
   - emits,
   - compiled Moonlift test returns expected result projection.

6. Negative manual cases:
   - missing call contract rejects.
   - `UnknownTargetIdentity` rejects.
   - C/FFI/metamethod target rejects.
   - tailcall call shape rejects.
   - dynamic/unknown arity rejects.

---

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua`

Update existing static-region tests:

- Empty `CallRegion` still rejects.
- Under-contracted `CallRegion` still rejects.
- Properly contracted manual `CallRegion` lowers.
- Source `CALL` still rejects through `compile_to_moon_kernel`.
- Source `TAILCALL` still rejects.
- `SETLIST`, `TFOR*`, standalone `MMBIN*` remain fail-closed.

---

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua`

Add guardrail checks:

- Emitted call substrate source does not contain forbidden semantic strings.
- `StencilKey.check_no_forbidden_strings({ "call" })` still fails.
- Typed call target/frame patch sources pass.

---

## Order of Operations

1. Update ASDL.
2. Update `lua_rt_call_model.lua`.
3. Update LuaRT/LuaExec/CompileContract validators.
4. Update region executability gating.
5. Lower call substrate in `lua_exec_to_moon_cfg_lower.lua`.
6. Validate/emit MoonCFG call runtime nodes.
7. Preserve source `CALL`/`TAILCALL` rejects.
8. Add schema/model tests.
9. Add executable call substrate tests.
10. Add fail-closed/guardrail regressions.
11. Run verification.

---

## Testing Strategy

Run:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_call.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
```

Optional:

```sh
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Expected Phase 3 behavior:

- Manual fixed-shape typed `CallRegion` substrate can validate/lower/emit.
- Source `CALL`/`TAILCALL` remain rejected.
- Corpus success count should not be expected to increase.
- No forbidden protocol/helper strings appear.

---

## Structured Edit Plan Sidecar

Updated `wf-lua55-roadmap` sidecar to revision `r51`.

Added tasks:

- `T025` Extend ASDL call foundation
- `T026` Implement call model semantics helpers
- `T027` Extend structural validators for call nodes
- `T028` Gate executable CallRegion by typed contract
- `T029` Lower call substrate to MoonCFG
- `T030` Validate and emit MoonCFG call runtime
- `T031` Propagate call contract identity
- `T032` Keep source CALL and TAILCALL fail-closed
- `T033` Update schema and model tests
- `T034` Add executable call substrate tests
- `T035` Add fail-closed source call regressions
- `T036` Run Phase 3 verification gates

Ready first task: `T025`.

---

## Pattern Memo

- ASDL first; no stringly call semantics.
- Phase 3 executes call-frame substrate only, not source `CALL`.
- `CallRegion` executable only with typed resolved target + frame/arity/result contract.
- Unknown/C/FFI/metamethod/tailcall targets reject.
- No `EmitRegion`, VM dispatch, interpreter handoff, or helper fallback in Phase 3.

## Worker Output — 2026-06-06 19:27:31

## Completed
Implemented Phase 3 for `wf-lua55-roadmap` and completed edit-plan tasks `T025`–`T036`.

Phase 3 adds the ASDL-first fixed-shape call-frame substrate:
- typed call target identity/resolution
- call arg/result channels
- call frame layout/state
- LuaExec call-frame exprs/ops/contracts
- CompileContract call assumptions
- MoonCFG runtime call-frame nodes/op
- typed Stencil call patch sources
- executable gating for manually constructed, fully contracted `CallRegion`

Source `CALL` / `TAILCALL` remain rejected and were not added to `SUPPORTED_INSTR`.

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` - Phase 3 call ASDL vocabulary.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_call_model.lua` - call-frame validation/executability helpers and `LuaRTCallFrame` type.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua` - call structural validators.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua` - call expr/op/contract validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua` - contract-aware `CallRegion` gating.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua` - call substrate lowering and call contract propagation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua` - MoonCFG call runtime validation/inference.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua` - call-frame runtime emission.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua` - call assumption validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_key.lua` - structural call keying note.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua` - explicit source `CALL`/`TAILCALL` fail-closed comments.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua` - schema/model/call validation assertions.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_call.lua` - new executable call-frame substrate tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua` - contracted/under-contracted `CallRegion` tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua` - typed call stencil guardrails.

## Verification
Passed:
```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_call.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Corpus remained fail-closed: `37 ok / 104 rejected`, `31 successful windows`, `29 reps checked`.

## Notes
No remaining blockers. Phase 3 executes call-frame transfer/extraction substrate only; it does not invoke callees and does not accept LuaSrc `CALL` or `TAILCALL`.

## Edit-planner Output — 2026-06-06 19:32:24

### Precondition Checks

Before Phase 4 edits begin, verify current Phase 3 state:

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
  - `LuaRT.CallShape` field order remains `callee,args,wanted_results,is_tailcall,may_yield` around lines 787-792.
  - `LuaRT.CallFrameState` field order remains `layout,args,results,target,state` around lines 878-882.
  - `LuaExec.Module = (regions,kernels)` exists around lines 1252-1253.
  - `LuaExec.Region` field order remains `id,kind,params,continuations,entry,blocks` around lines 1263-1268.
  - `LuaExec.CallContinuationRegion` exists around lines 1325-1329.
  - `LuaExec.Op.EmitRegion(region,args,continuations)` still exists around line 1481.
  - `MoonCFG.Op.EmitRegion` exists around line 1754 but is still rejected by validation/emission.
- `lua_exec_to_moon_cfg_lower.lua`
  - Direct `Exec.EmitRegion` still rejects at lines ~695-696.
  - `lower_value(kernel, opts)` currently lowers only one `Exec.Kernel`, not a module/library.
- `moon_cfg_validate.lua`
  - `CFG.EmitRegion`, `CFG.Continue`, and `CFG.Exit` are still unsupported terminators/ops around lines 400-401.
- `lua_src_to_lua_exec_lower.lua`
  - `SUPPORTED_INSTR` still does **not** include `CALL` or `TAILCALL`.
  - Source `CALL`/`TAILCALL` still reject scaffold-only.
- Existing Phase 1–3 tests are green.

---

## Phase 4 Scope Decision

Choose **static callee region invocation for manually constructed typed `LuaExec.Module` products**.

Phase 4 does **not** accept source `CALL` or `TAILCALL`.

What becomes executable:

- `LuaExec.EmitRegion` becomes executable only in a new module-lowering path when:
  - the kernel is inside a `LuaExec.Module`,
  - the target region is present in the module region library,
  - the invocation is covered by typed `StaticRegionInvocation` / `CallContinuationRegion` contract nodes,
  - the target region is a static, non-scaffold executable region,
  - the invocation is inlined before MoonCFG lowering.

What stays rejected:

- Direct `ExecToMoon.lower(kernel)` with `EmitRegion`.
- `MoonCFG.EmitRegion`.
- source `CALL` / `TAILCALL`.
- unknown call targets, dynamic arity, C/FFI/metamethod targets, tailcalls, nested/uncontracted emits.

---

## Files to Modify

### `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`

**Goal**: Add typed static-region invocation contracts without changing existing tested field orders.

**Edit blocks**

1. **After `CallContinuationRegion`, lines ~1325-1329**: add static invocation metadata.

```asdl
StaticRegionRole = StaticCalleeBodyRegion
                 | StaticContinuationRegion
                 | StaticInlineOnlyRegion

StaticRegionBinding = (LuaExec.RegionRef region,
                       LuaExec.RegionDescriptor descriptor,
                       LuaExec.StaticRegionRole role) unique

StaticRegionInvocation = (LuaExec.Name id,
                          LuaExec.Name op_region,
                          LuaExec.StaticRegionBinding target,
                          LuaExec.Arg* args,
                          LuaExec.ContBinding* continuations,
                          LuaExec.CallContinuationRegion call_continuation) unique
```

2. **`LuaExec.Expr`, around lines ~1421-1428**: add structural expression nodes.

```asdl
| StaticRegionBindingExpr(LuaExec.StaticRegionBinding binding) unique
| StaticRegionInvocationExpr(LuaExec.StaticRegionInvocation invocation) unique
```

3. **`LuaExec.Obligation`, around lines ~1502-1513**: add obligations.

```asdl
| RequiresStaticRegion(LuaExec.StaticRegionBinding binding) unique
| RequiresStaticRegionInvocation(LuaExec.StaticRegionInvocation invocation) unique
| RequiresCallContinuationRegion(LuaExec.CallContinuationRegion region) unique
```

4. **`LuaExec.Guarantee`, around lines ~1515-1523**: add guarantees.

```asdl
| ProvidesStaticRegion(LuaExec.StaticRegionBinding binding) unique
| InvokesStaticRegion(LuaExec.StaticRegionInvocation invocation) unique
| BindsCallContinuationRegion(LuaExec.CallContinuationRegion region) unique
```

5. **`CompileContract.SemanticAssumption`, around lines ~1536-1549**: add assumptions.

```asdl
| AssumesStaticRegion(LuaExec.StaticRegionBinding binding) unique
| AssumesStaticRegionInvocation(LuaExec.StaticRegionInvocation invocation) unique
| AssumesCallContinuationRegion(LuaExec.CallContinuationRegion region) unique
```

6. **`Stencil.PatchSource`, around lines ~1850-1865**: add typed patch sources.

```asdl
| FromStaticRegion(LuaExec.StaticRegionBinding binding) unique
| FromStaticRegionInvocation(LuaExec.StaticRegionInvocation invocation) unique
```

**Danger zones**
- Do not change `LuaExec.Module`, `Kernel`, `Region`, `Op.EmitRegion`, or `MoonCFG.Kernel` field order.
- Do not add lowercase semantic strings.
- Do not add dynamic call dispatch constructors.

---

### New file: `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_static_region_model.lua`

**Goal**: Centralize Phase 4 static invocation validation and executable gating.

**Contents sketch**

```lua
local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local Exec = T.LuaExec
local RegionModel = require("lua_compile.lua_exec_region_model")
local CallModel = require("lua_compile.lua_rt_call_model")

local M = {}

function M.validate_static_region_binding(binding) ... end
function M.validate_static_region_invocation(invocation) ... end
function M.validate_call_continuation_region(region) ... end

function M.index_module_regions(module) ... end
function M.contract_invocations(contract) ... end
function M.contract_allows_static_invocation(contract, invocation) ... end

function M.is_executable_target_region(region, contract) ... end
function M.validate_emit_op_shape(op, block, op_index) ... end

function M.validate_against_schema() ... end

return M
```

**Rules to enforce**
- Target region must exist in `LuaExec.Module.regions`.
- Target region kind must be executable via `RegionModel.is_executable_region`; scaffold-only regions reject.
- `TailCallRegion`, `GenericForRegion`, `FFIRegion`, `MetatableRegion`, `CloseRegion`, and `OpcodeFamilyRegion` reject.
- `CallContinuationRegion.callee_region` must match the target binding.
- Phase 4 permits only fixed, typed Lua-closure call-frame contracts from Phase 3.
- Unknown/C/FFI/metamethod targets reject.
- Nested `EmitRegion` inside the target region rejects in Phase 4.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/init.lua`

**Goal**: Export the new static-region model.

**Edit block**

- **After `M.lua_exec_region_model`, around line 28**, add:

```lua
M.lua_exec_static_region_model = require("lua_compile.lua_exec_static_region_model")
```

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_call_model.lua`

**Goal**: Add call-continuation executability helpers that build on Phase 3 call-frame checks.

**Edit blocks**

1. **Header, lines 1-6**: update comment to mention Phase 4 static callee-region invocation.

2. **After `contract_allows_executable_call_region`, around line ~300**: add:

```lua
function M.validate_call_continuation_region(region) ... end
function M.is_executable_call_continuation_region(region, frame_state) ... end
function M.contract_allows_static_call_invocation(contract, invocation) ... end
```

**Executable rules**
- `CallContinuationRegion.call` must match `CallArgChannel.call` and `CallResultChannel.call`.
- `return_cont`, `error_cont`, `yield_cont` must be typed `LuaExec.ContRef`.
- Phase 4 only executes non-tail `LuaClosureTargetIdentity`.
- Error/yield continuations may be structurally present, but target callee region must not produce error/yield paths yet.

3. **`validate_against_schema`, lines ~314-330**: add new static invocation constructors.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua`

**Goal**: Validate modules, static invocation metadata, and stricter continuation wiring structurally.

**Edit blocks**

1. **Imports, lines 8-13**: add:

```lua
local StaticRegionModel = require("lua_compile.lua_exec_static_region_model")
```

2. **`validate_expr`, around lines ~70-140**: recognize:
- `Exec.StaticRegionBindingExpr`
- `Exec.StaticRegionInvocationExpr`

3. **Region validation, around lines ~150-240**:
- Build `continuations_by_id`.
- For `Exec.Continue`, require the continuation exists in `region.continuations`.
- For `Exec.EmitRegion`:
  - allow structurally,
  - validate args/continuation bindings,
  - if Phase 4 executable path is intended, require:
    - op is last op in the block,
    - block terminator is `Exec.Unreachable`.
  - Do not mark it executable here; module lowering decides.

4. **Add `M.module(module)`**:
- Validate every `module.regions`.
- Validate every `module.kernels`.
- Reject duplicate region ids.
- Ensure kernels do not duplicate library region ids.

5. **Contract validation, around lines ~260-330**:
- Add new static-region obligations/guarantees.

---

### New file: `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_static_region_inline.lua`

**Goal**: Expand typed `LuaExec.EmitRegion` into a single inlined executable `LuaExec.Kernel` before MoonCFG lowering.

**Contents sketch**

```lua
local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local Exec = T.LuaExec
local ExecValidate = require("lua_compile.lua_exec_validate")
local StaticRegionModel = require("lua_compile.lua_exec_static_region_model")

local M = {}

function M.inline_module_kernel(module, kernel_name_or_nil)
  -- returns inlined Exec.Kernel or nil, errors
end

return M
```

**Inlining algorithm**
1. Validate `LuaExec.Module`.
2. Pick the requested kernel, or the sole kernel if only one exists.
3. Index `module.regions` by `region.id.text`.
4. Walk kernel body blocks.
5. For an executable `EmitRegion` op:
   - require it is final op in the block;
   - require terminator is `Exec.Unreachable`;
   - find matching `StaticRegionInvocation` in kernel contract;
   - require target binding resolves to a module region;
   - reject nested `EmitRegion` in target region;
   - clone target blocks with hygienic prefix:
     - `__static_<target>_<ordinal>__<block>`
   - replace caller block terminator with `Jump(cloned_entry, lowered_args)`.
   - translate callee `Continue(cont,args)` to `Jump(bound_target_block,args)`.
6. Preserve all non-emitting blocks unchanged.
7. Merge/retain contracts; add/keep guarantees for static invocation.

**Phase 4 restrictions**
- Only one level of static invocation.
- No dynamic dispatch.
- No VM fallback.
- No source `CALL`.
- No target `Return/Error/Yield` terminators inside invoked callee region; use `Continue` only.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua`

**Goal**: Gate executable regions with module/static invocation context.

**Edit blocks**

1. **Imports, lines 8-10**: avoid circular import; do not require the static model here if it requires `RegionModel`.

2. **After `is_executable_region`, around line ~90**: add:

```lua
function M.is_executable_static_target_region(region, contract)
  ...
end
```

**Rules**
- Existing executable region kinds pass.
- `CallRegion` only passes through existing call contract gate.
- Scaffold-only kinds reject.
- `TailCallRegion` always rejects.

3. **`validate_against_schema`, around lines ~245-260**: assert:
- `StaticRegionRole`
- `StaticRegionBinding`
- `StaticRegionInvocation`
- new obligations/guarantees.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua`

**Goal**: Add module lowering through static inlining while keeping direct `EmitRegion` rejected.

**Edit blocks**

1. **Imports, lines ~8-16**: add:

```lua
local StaticInline = require("lua_compile.lua_exec_static_region_inline")
```

2. **`compile_contract`, lines ~32-70**:
- Convert:
  - `RequiresStaticRegion`
  - `RequiresStaticRegionInvocation`
  - `RequiresCallContinuationRegion`
- Into `CompileContract.RequiresSemanticAssumption`.
- Convert corresponding guarantees.

3. **`lower_op`, lines ~695-696**:
- Keep direct `Exec.EmitRegion` rejection:
```lua
unsupported_lua_exec_op:EmitRegion:requires_static_module_inline
```

4. **After `lower_value(kernel, opts)`, around line ~1008**: add:

```lua
local function lower_module_value(module, kernel_name, opts)
  local inlined, inline_errors = StaticInline.inline_module_kernel(module, kernel_name)
  if not inlined then return nil, inline_errors end
  return lower_value(inlined, opts)
end
```

5. **Public exports, bottom lines ~1035-1040**:
- Add:
```lua
function M.lower_module(module, kernel_name) ... end
function M.lower_module_outcome(module, kernel_name, projection) ... end
M.lower_module_uncached = lower_module_value
```

**Danger zone**
- Do not change `M.lower(kernel)` or public source compile route behavior.
- Existing kernel-only tests must keep passing.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua`

**Goal**: Preserve MoonCFG guardrails.

**Edit blocks**

1. **Forbidden strings, lines 16-26**:
- Keep unchanged.
- Add comment:
```lua
-- Phase 4 LuaExec static invocation is inlined before MoonCFG. MoonCFG.EmitRegion
-- remains rejected until typed MoonCFG region emission is implemented separately.
```

2. **Supported ops table, lines 28-37**:
- Do **not** add `CFG.EmitRegion`.

3. **Terminator validation, lines ~400-401**:
- Keep `CFG.Continue` and `CFG.Exit` unsupported.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua`

**Goal**: No new MoonCFG emit support in Phase 4.

**Edit blocks**

1. **`render_op`, around lines ~1244-1441**:
- Keep no `CFG.EmitRegion` render case.
- If adding a guard comment:
```lua
-- LuaExec static invocation must be inlined before MoonCFG; do not render
-- MoonCFG.EmitRegion in Phase 4.
```

2. Ensure emitted source still contains no:
- `call`
- `close`
- `generic_for`
- `out_tag`
- helper/dispatch strings.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua`

**Goal**: Validate static invocation assumptions structurally.

**Edit blocks**

- In `validate_semantic_assumption`, add cases for:
  - `AssumesStaticRegion`
  - `AssumesStaticRegionInvocation`
  - `AssumesCallContinuationRegion`

Use `lua_exec_static_region_model` helpers.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_key.lua`

**Goal**: Preserve structural identity.

**Edit**
- Add comment near existing structural-key notes:
```lua
-- Phase 4 static region invocation and call-continuation assumptions are keyed
-- structurally through ASDL. Never encode invocation meaning as strings.
```

No algorithm change expected.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_key.lua`

**Goal**: Preserve no-stringly guardrails.

**Edit**
- No functional change expected.
- Tests should prove typed `FromStaticRegion` / `FromStaticRegionInvocation` pass, while lowercase `"call"` / `"emit"`-style semantic strings fail if forbidden.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua`

**Goal**: Keep source `CALL` and `TAILCALL` fail-closed.

**Edit blocks**

- Around existing `CALL` / `TAILCALL` rejects in `scan_shape`, add comment:
```lua
-- Phase 4 static region invocation is available only for manually constructed
-- typed LuaExec.Module products. Source CALL/TAILCALL still require closure/proto
-- evidence, static callee region construction, close/yield semantics, and strict
-- contracts before they can be accepted.
```

Do not alter `SUPPORTED_INSTR`.

---

## New Files

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_static_region_model.lua`

Purpose: Phase 4 validation/executability model for static region invocation.

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_static_region_inline.lua`

Purpose: Fail-closed inliner from `LuaExec.Module` + typed `EmitRegion` contracts to one executable `LuaExec.Kernel`.

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_invoke.lua`

Purpose: executable Phase 4 tests for manually constructed typed static callee invocation.

---

## Tests

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua`

Add assertions for:
- `LuaExec.StaticRegionRole`
- `LuaExec.StaticRegionBinding`
- `LuaExec.StaticRegionInvocation`
- `LuaExec.RequiresStaticRegion`
- `LuaExec.RequiresStaticRegionInvocation`
- `LuaExec.RequiresCallContinuationRegion`
- `LuaExec.InvokesStaticRegion`
- `CompileContract.AssumesStaticRegion`
- `CompileContract.AssumesStaticRegionInvocation`
- `CompileContract.AssumesCallContinuationRegion`
- `Stencil.FromStaticRegion`
- `Stencil.FromStaticRegionInvocation`

Call `lua_exec_static_region_model.validate_against_schema()`.

---

### New `test_spongejit_lua_compile_static_invoke.lua`

Cover:

1. Manual `LuaExec.Module`:
   - library region writes fixed results into callee stack,
   - region terminates via `Continue(return_cont)`,
   - kernel body:
     - `PrepareCallFrame`
     - `EmitRegion`
     - continuation block
     - `ReceiveCallResults`
     - `Return`
   - `lower_module_outcome(module, "kernel", "value2_payload_i64")` succeeds.
   - emitted Moonlift runs and returns expected third result.

2. Contract identity:
   - compile contract contains static invocation assumptions.
   - structural key changes when target region descriptor changes.

3. Negative cases:
   - bare `lower_outcome(kernel_with_emit)` rejects.
   - missing `StaticRegionInvocation` contract rejects.
   - target region not in module rejects.
   - nested target `EmitRegion` rejects.
   - target scaffold-only region rejects.
   - unknown call target rejects.
   - dynamic arg/result count rejects.
   - tailcall target rejects.

4. Emission guardrails:
   - emitted source does not contain helper/protocol/lowercase semantic fallback strings.

---

### Existing regression tests

Update:

- `test_spongejit_lua_compile_static_regions.lua`
  - Empty/under-contracted `CallRegion` still rejects.
  - Direct kernel `EmitRegion` still rejects.
  - Proper module static invocation succeeds only through new module API.
  - Source `CALL` / `TAILCALL` still reject.

- `test_spongejit_lua_compile_lua_rt_call.lua`
  - Existing Phase 3 call-frame substrate still passes.

- `test_spongejit_lua_compile_moon_cfg.lua`
  - `MoonCFG.EmitRegion` still rejected.
  - typed static invocation stencil sources accepted.
  - lowercase semantic strings rejected.

---

## Order of Operations

1. Update ASDL.
2. Add `lua_exec_static_region_model.lua`.
3. Export it from `init.lua`.
4. Extend `lua_rt_call_model.lua`.
5. Extend `lua_exec_validate.lua`.
6. Add `lua_exec_static_region_inline.lua`.
7. Wire module lowering in `lua_exec_to_moon_cfg_lower.lua`.
8. Update contract/stencil validation comments/tests.
9. Preserve MoonCFG `EmitRegion` rejection.
10. Preserve source `CALL`/`TAILCALL` rejection.
11. Add schema/static-invocation tests.
12. Run verification.

---

## Testing Strategy

Run:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_invoke.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_call.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
```

Optional:

```sh
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Expected:
- No source `CALL`/`TAILCALL` acceptance.
- Corpus success count should not be expected to increase.
- New manual module static invocation tests pass.
- No forbidden helper/protocol strings emitted.

---

## Structured Edit Plan Sidecar

Updated workflow sidecar `wf-lua55-roadmap` to revision `r76`.

Added tasks:
- `T037` Extend ASDL static invocation vocabulary
- `T038` Add static region invocation model
- `T039` Extend LuaRT and LuaExec validators
- `T040` Implement static region inline expansion
- `T041` Wire module lowering through inliner
- `T042` Preserve MoonCFG EmitRegion guardrails
- `T043` Update contract and stencil validation
- `T044` Keep source CALL fail-closed
- `T045` Update schema and model tests
- `T046` Add executable static invocation tests
- `T047` Add fail-closed regression tests
- `T048` Run Phase 4 verification gates

Ready first task: `T037`.

---

## Pattern Memo

- ASDL first; no stringly semantics.
- Phase 4 executes **manual typed static invocation only**, not source `CALL`.
- `LuaExec.EmitRegion` is executable only through `LuaExec.Module` + typed contract + inline expansion.
- `MoonCFG.EmitRegion` remains rejected.
- Unknown/dynamic/tailcall/C/FFI/metamethod targets reject.
- No VM dispatch, interpreter handoff, helper calls, or protocol exits.

## Documenter Output — 2026-06-06 19:34:31

# SpongeJIT Lua 5.5 Roadmap Correction: Complete ASDL Architecture First, Phased Implementation Only

## Goal

Define SpongeJIT’s full Lua 5.5 semantic architecture coherently up front in ASDL/product form, so every future executable feature—calls, arity, closures, upvalues, metatables, GC, FFI, loops, close/TBC, error/yield, contracts, static regions, and stencil/foundry identity—implements against one complete target architecture rather than extending the architecture piecemeal.

## Incentives

The previous roadmap correctly preserved the clean-base invariant that accepted kernels must go through `LuaSrc.Window -> LuaExec.Kernel -> MoonCFG.Kernel` with no fallback. However, its implementation plans framed the architecture itself as phased: Phase 1 scaffold-only regions, Phase 2 arity, Phase 3 call frames, Phase 4 static invocation, and so on. That is the corrected mistake. A partial “scaffold now, semantic architecture later” approach is too avoidant for Lua 5.5 because the hard features are interdependent. Calls depend on arity, metatables, closures, close/yield, and FFI; GC allocation affects tables, closures, strings, cdata, finalizers, and barriers; close/TBC affects returns, errors, yields, and tailcalls. If the product vocabulary is allowed to evolve feature-by-feature, the architecture can encode local compromises that later conflict with full semantics.

The corrected rule is: **implementation may be phased; architecture must not be phased**.

## Current State

SpongeJIT currently has a clean, typed compiler stack under:

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/`

The main route remains:

```text
PUC/event rows
  -> lua_src_from_puc_decode.lua
  -> LuaSrc.Window
  -> LuaCompile.Unit(source, evidence)
  -> lua_src_to_lua_exec_lower.lua
  -> LuaExec.Kernel
  -> lua_exec_to_moon_cfg_lower.lua
  -> MoonCFG.Kernel
  -> moon_cfg_validate.lua
  -> moon_cfg_emit.lua
```

`LuaSrc` already decodes all 85 real Lua 5.5 opcodes. The source layer is complete enough to preserve bytecode facts such as `EXTRAARG`, `MMBIN*`, comparison + `JMP`, loop groups, call/return counts, varargs, closures, and table forms.

The executable `LuaExec`/`MoonCFG` slice is much narrower. It currently supports selected loads, moves, returns, comparisons, `ADD`/`ADDI`/`ADDK`, raw `GETTABLE`/`SETTABLE`, limited `LEN`/`CONCAT`, selected varargs, and typed outcomes. Common Lua features such as `CALL`, `TAILCALL`, closures/upvalues, metatable paths, `NEWTABLE`, `SETLIST`, loops, close/TBC, GC allocation, and FFI/cdata remain rejected.

Recent work introduced typed scaffold/product pieces for static regions, arity/result channels, call frames, call target identity, and call-frame transfer. It also kept source `CALL`/`TAILCALL` rejected. Those edits are useful as implementation material, but the *architectural framing* as sequential scaffold phases is now superseded. The correct architecture is not “Phase 1 ASDL, then Phase 2 ASDL, then Phase 3 ASDL.” The correct architecture is one complete Lua 5.5 semantic product model, with implementation gates filling in lowering/emission over time.

## Chosen Target

### Approach

The chosen target remains ASDL-first and static-region based, but with the corrected architectural rule:

> SpongeJIT must define the complete Lua 5.5 semantic product architecture up front. Implementation may proceed incrementally, but every phase must implement against that complete architecture, not extend the architecture as a partial scaffold.

This means `spongejit_lua_ssa.asdl` is the target architecture, not a staging area for temporary abstractions. Product names, contracts, region kinds, runtime state, and stencil/foundry identities should be designed as if full Lua 5.5 support is required, even when many lowerings still reject.

### Architecture

The complete target architecture is organized by the existing ASDL layers.

#### `LuaSrc`

`LuaSrc` remains the source-fidelity layer:

- all 85 Lua 5.5 opcodes;
- companion/context forms:
  - `EXTRAARG`;
  - `MMBIN`, `MMBINI`, `MMBINK`;
  - comparison + `JMP`;
  - call/return arity windows;
  - loop groups;
  - close/TBC markers;
  - vararg forms.

No executable semantics belong in `LuaSrc`.

#### `LuaRT`

`LuaRT` is the complete runtime semantic model. It must include, coherently and up front:

- values, tags, stack slots, frames, value sequences;
- arbitrary arity:
  - `CountSpec`;
  - `ValueSeq`;
  - `ArityShape`;
  - `ResultChannel`;
  - `ArityNormalization`;
- calls:
  - `CallRef`;
  - `CallShape`;
  - `CallTarget`;
  - `CallTargetIdentity`;
  - `ResolvedCallTarget`;
  - `CallArgChannel`;
  - `CallResultChannel`;
  - `CallFrameLayout`;
  - `CallFrameState`;
- closures/upvalues:
  - closure refs;
  - proto identity;
  - open/closed upvalue state;
  - upvalue epochs;
  - close interaction;
  - write barriers;
- tables/metatables:
  - raw table access/update;
  - table shape/hash/array facts;
  - metatable refs and epochs;
  - metamethod lookup;
  - `__index`, `__newindex`, `__call`, arithmetic, comparison, concat, len hooks;
- arithmetic/metamethods:
  - numeric fast paths;
  - coercion facts;
  - companion opcode ordering;
  - metamethod call fallback as explicit call semantics;
- loops:
  - numeric `for` state;
  - generic `for` iterator state;
  - loop-region topology;
  - iterator call/result/yield/close handling;
- close/TBC/error/yield:
  - close chains;
  - close hooks for return, tailcall, error, yield, finalizer;
  - resume points;
  - outcome state;
  - error/yield ordering;
- GC/allocation:
  - object headers;
  - allocation state;
  - roots;
  - barriers;
  - finalizer queues;
  - weak/ephemeron controls;
  - epochs;
- FFI/cdata:
  - C type/layout identity;
  - symbols;
  - ABI facts;
  - cdata ownership;
  - scalar load/store;
  - finalizers;
  - callbacks.

#### `LuaExec`

`LuaExec` is the explicit semantic CFG over `LuaRT`. Its region library must be complete, not scaffolded feature-by-feature.

The target region families include:

- `LoadMoveRegion`
- `ReturnRegion`
- `CallRegion`
- `TailCallRegion`
- `TableAccessRegion`
- `MetatableRegion`
- `ArithmeticRegion`
- `CompareBranchRegion`
- `ClosureRegion`
- `UpvalueRegion`
- `NumericForRegion`
- `GenericForRegion`
- `CloseTBCRegion`
- `GCAllocRegion`
- `FFIRegion`
- `ErrorYieldRegion`
- `StaticContinuationRegion`

Static invocation must be represented explicitly through typed region products such as:

- `RegionDescriptor`
- `RegionRef`
- `CallContinuationRegion`
- `StaticRegionBinding`
- `StaticRegionInvocation`

`LuaExec.EmitRegion` is a typed static CFG composition mechanism, not a fallback or interpreter call. When executable, it must splice typed regions or lower through a validated static invocation path. It must never mean “go run the VM.”

#### `CompileContract`

`CompileContract` records every semantic assumption needed for executable correctness. It must cover:

- call target identity and epoch;
- callable kind;
- arity/result shape;
- static region identity;
- continuation binding;
- closure proto identity;
- upvalue identity and epoch;
- metatable epoch;
- metamethod absence/presence;
- table shape/hash/array facts;
- GC allocation/root/barrier state;
- finalizer obligations;
- FFI symbol/layout/ABI identity;
- cdata ownership/finalizer identity.

No assumption may be hidden in strings, helper names, side tables, or untyped variant keys.

#### `MoonCFG`

`MoonCFG` is the typed Moonlift CFG target. It must contain only explicit runtime operations corresponding to typed `LuaRT`/`LuaExec` semantics.

Valid future support includes typed operations for:

- value-sequence normalization and storage;
- outcome construction/projection;
- stack/frame transfer;
- call target checks;
- static region invocation after validation/inlining;
- raw and metatable-aware table paths;
- GC allocation/root/barrier operations;
- close-chain execution;
- FFI/cdata scalar and ABI operations.

`MoonCFG.EmitRegion`, if supported later, must be typed and validated. Until then, static `LuaExec` invocation may be inlined before MoonCFG. It must not become a protocol exit.

#### Foundry, stencil, and identity

Foundry evidence and stencil keys must align with the complete architecture.

Typed identity must include:

- `FromCallTarget`
- `FromCallTargetIdentity`
- `FromCallFrameLayout`
- `FromStaticRegion`
- `FromStaticRegionInvocation`
- metatable epochs;
- upvalue epochs;
- FFI layouts;
- GC state/epoch assumptions;
- table shape facts;
- region descriptors.

Stencil/foundry identity must be structural ASDL identity. Lowercase semantic strings such as `"call"`, `"close"`, `"generic_for"`, `"setlist"`, `"out_tag"`, or helper/protocol markers remain forbidden.

### Implementation Rule

Implementation can still be phased, but phases are now execution milestones only.

Correct:

```text
Complete ASDL/product architecture exists.
Phase N implements lowering/emission/tests for one subset.
Unsupported complete-architecture cases reject.
```

Incorrect:

```text
Phase N invents partial scaffold architecture.
Phase N+1 changes the architecture to add missing semantic dimensions.
```

Each implementation phase must ask: “Which part of the already-complete Lua 5.5 product model are we making executable?” It must not ask: “Which architectural concepts should we introduce for this phase?”

### Tradeoffs acknowledged

This decision front-loads architectural design. It may require larger ASDL/product work before new corpus wins appear. It also makes implementation planning stricter: incomplete executable support must still conform to full product shapes.

That cost is accepted because Lua 5.5 semantics are too interconnected for piecemeal product design. A phased architecture risks encoding avoidant partial abstractions that later become wrong.

### Risks acknowledged

The main risks are:

- the complete ASDL model may be large;
- product design mistakes will be more visible and costly;
- implementation phases may feel slower because they must target full semantics;
- validators must distinguish “well-formed but not executable yet” from fake success;
- contract omissions can still cause unsound compiled kernels;
- static regions must not degrade into VM dispatch or interpreter fallback.

The correction accepts these risks to preserve the core SpongeJIT rule: **ASDL is the architecture, and accepted code must be explicit, typed, validated, and fail-closed.**

## Scout Output — 2026-06-06 19:40:48

## Files Retrieved

1. `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` (lines 1-180, 170-499, 496-1255, 1250-2020, 2020-2048) — current ASDL authority: doctrine, all `LuaSrc` opcodes, `LuaFact`, `LuaFFI`, `LuaRT`, `LuaGC`, `LuaExec`, `CompileContract`, `MoonCFG`, `Stencil`, `LuaCompile`.
2. `experiments/lua_interpreter_vm/spongejit/ssa_asdl/README.md` (lines 1-38) — layer responsibilities and guardrails.
3. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_from_puc_decode.lua` (lines 1-135) — explicit decoder for 85 Lua 5.5 real opcodes.
4. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_window_collect.lua` (lines 1-46) — `EXTRAARG` preservation for `LOADKX`, `NEWTABLE`, `SETLIST`.
5. `experiments/lua_interpreter_vm/spongejit/lua_compile/validate.lua` (lines 1-160) — source companion validation, cross-layer entry points.
6. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua` (lines 1-1000) — accepted source slice, explicit rejects for call/close/GC/setlist/etc., arity normalization in current lowering.
7. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua` (lines 1-260) — current region taxonomy, executable vs scaffold-only classification.
8. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_arity_model.lua` (lines 1-148) — current arity/result-channel model.
9. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_call_model.lua` (lines 1-333) — fixed-shape call-frame substrate and executable gate.
10. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_metatable_model.lua` (lines 1-40) — metatable hook validation only.
11. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_close_model.lua` (lines 1-39) — close/TBC hook validation only.
12. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_closure_upvalue_model.lua` (lines 1-18) — closure/upvalue schema presence only.
13. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_gc_alloc_model.lua` (lines 1-42) — GC hook metadata only.
14. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_loop_model.lua` (lines 1-18) — loop metadata only.
15. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_cdata_model.lua` (lines 1-64) — cdata scalar bank substrate.
16. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua` (lines 1-135) — structural validation for LuaRT products.
17. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua` (lines 1-350) — structural LuaExec validation; module validation is shallow.
18. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua` (lines 1-1090) — LuaExec→MoonCFG lowering; `EmitRegion` still rejected.
19. `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua` (lines 1-450) — MoonCFG support set and forbidden fallback strings.
20. `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_emit.lua` (lines 1-220, 560-1530) — MoonCFG runtime emission for current executable substrate.
21. `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua` (lines 1-160) — current semantic assumption validation.
22. `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_key.lua` (lines 1-120) — structural keying and forbidden string guardrails.
23. `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_validate.lua` (lines 1-220) — stencil structural validation.
24. `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_materialize.lua` (lines 240-330) — materializer supports only a small subset of `PatchSource`.
25. `experiments/lua_interpreter_vm/spongejit/lua_compile/stencil_foundry.lua` (lines 1-34) — stencil variant identity from MoonCFG + contract.
26. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_runtime_observe.lua` (lines 1-212) — runtime observations to facts/evidence.
27. `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_foundry.lua` (lines 160-320) — current fact axes for arithmetic/table/upvalue/call-target-ish evidence.
28. `experiments/lua_interpreter_vm/spongejit/src/loop_regions.lua` (lines 1-220) — numeric/generic loop topology recognition.
29. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-287) — Lua 5.5 opcode, tag, metamethod, resume, error, GC constants.
30. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-120) — native VM runtime products: `Proto`, `UpVal`, closures, frames, thread/global state, finalizers.
31. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-260 plus grep lines 600-681) — opcode dispatch and handler continuation groupings.
32. `experiments/lua_interpreter_vm/src/op/_init.lua` (lines 1-164) — native VM protocol snippets for table metamethod calls.
33. `experiments/lua_interpreter_vm/src/op/call.lua` (lines 1-300) — native VM call/return/tailcall semantics reference.
34. `experiments/lua_interpreter_vm/src/op/table.lua` (lines 1-340) — table access/set/newtable/self/setlist semantics reference.
35. `experiments/lua_interpreter_vm/src/op/arithmetic.lua` (lines 1-320) — arithmetic/bitwise/unary semantics reference.
36. `experiments/lua_interpreter_vm/src/op/closure.lua` (lines 1-98) — closure/vararg opcode semantics reference.
37. `experiments/lua_interpreter_vm/src/op/loop.lua` (lines 1-142) — numeric/generic loop semantics reference.
38. `experiments/lua_interpreter_vm/src/op/misc.lua` (lines 1-200) — len/concat/close/tbc/jmp/errnnil reference.
39. `experiments/lua_interpreter_vm/src/op/compare.lua` (lines 1-220) — compare/test/testset reference.
40. `experiments/lua_interpreter_vm/src/op/protocols.lua` (lines 1-47) — native VM continuation protocols, semantic reference only.
41. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua` (lines 1-220) — current schema and field-order assertions.
42. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_src.lua` (lines 1-140) — decode coverage and source field preservation.
43. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua` (lines 1-158) — scaffold/contracted manual `CallRegion` tests.
44. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_call.lua` (lines 1-220) — executable fixed-shape call-frame substrate tests.
45. `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua` (lines 300-450) — unsupported source guardrails, stencil key guardrails.
46. `experiments/lua_interpreter_vm/spongejit/Makefile` (lines 1-64) — main test scope and no-old-imports gate.
47. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-31) — current no-fallback direction.
48. `experiments/lua_interpreter_vm/SPONJIT_FFI_DESIGN.md` (lines 1-220) — FFI target facts.
49. `experiments/lua_interpreter_vm/SPONJIT_GC_DESIGN.md` (lines 1-220) — GC target facts.
50. `experiments/lua_interpreter_vm/SPONJIT_MOONLIFT_COPY_PATCH_DESIGN.md` (lines 1-220) — copy/patch/stencil target facts.

## Key Code

### ASDL doctrine

```asdl
-- spongejit_lua_ssa.asdl lines 5-18
--   LuaSrc          answers: what did PUC encode?
--   LuaEvidence     answers: what did runtime/foundry prove and lease?
--   LuaFFI          answers: what Lua-visible C FFI declarations/types/values/facts exist.
--   LuaGC           answers: what explicit Lua GC objects/state/control facts exist.
--   LuaRT           answers: what Lua runtime semantic objects/state exist.
--   LuaExec         answers: what explicit semantic Lua CFG is executed over LuaRT.
--   CompileContract answers: what executable-route obligations/facts/invalidation assumptions are attached.
--   MoonCFG         answers: what explicit Moonlift CFG is emitted.
--   Stencil         answers: what typed copy-and-patch backend artifact is materialized from MoonCFG.
--
-- Source opcode mechanics are code-shaping in LuaSrc and must be dead after LuaExec.
-- Physical residency is not semantic identity.
-- Runtime/Moonlift output never rediscovers Lua opcode meaning.
```

### LuaSrc opcode coverage

Current `LuaSrc.Op` has 85 real opcodes plus `UnsupportedOpcode`.

Families represented:

- Load/move: `MOVE`, `LOADI`, `LOADF`, `LOADK`, `LOADKX`, `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`, `LOADNIL`
- Upvalue/table: `GETUPVAL`, `SETUPVAL`, `GETTABUP`, `GETTABLE`, `GETI`, `GETFIELD`, `SETTABUP`, `SETTABLE`, `SETI`, `SETFIELD`, `NEWTABLE`, `SELF`
- Arithmetic/bitwise/unary/metamethod companions: `ADDI`, `ADDK`, `SUBK`, `MULK`, `MODK`, `POWK`, `DIVK`, `IDIVK`, `BANDK`, `BORK`, `BXORK`, `SHLI`, `SHRI`, `ADD`, `SUB`, `MUL`, `MOD`, `POW`, `DIV`, `IDIV`, `BAND`, `BOR`, `BXOR`, `SHL`, `SHR`, `MMBIN`, `MMBINI`, `MMBINK`, `UNM`, `BNOT`, `NOT`, `LEN`, `CONCAT`
- Close/control/compare: `CLOSE`, `TBC`, `JMP`, `EQ`, `LT`, `LE`, `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI`, `TEST`, `TESTSET`
- Calls/returns/loops: `CALL`, `TAILCALL`, `RETURN`, `RETURN0`, `RETURN1`, `FORLOOP`, `FORPREP`, `TFORPREP`, `TFORCALL`, `TFORLOOP`
- Constructors/closures/varargs/errors: `SETLIST`, `CLOSURE`, `VARARG`, `GETVARG`, `ERRNNIL`, `VARARGPREP`, `EXTRAARG`

Decoder and tests assert 85/85 explicit decoders.

```lua
-- test_spongejit_lua_compile_lua_src.lua lines 23-31
assert(#names == 85, "ASDL real LuaSrc.Op coverage count must be 85")
for _, name in ipairs(names) do
  assert(Decode.DECODER[name], "missing explicit decoder for " .. name)
  local op = Decode.decode(sample_event(name))
  assert(op.kind == name)
end
```

### Current LuaRT semantic product surface

Already typed:

- `ValueTag`, `TValue`, `ValueRef`, `Frame`, `StackWindow`, `ValueSeq`
- `CountSpec`, `ArityShape`, `ResultChannel`, `ArityNormalization`
- table/ref/metatable lookup states
- metamethod enum matching PUC ltm order
- call shape/state/target identity/call-frame products
- error/yield/resume/close hook products
- numeric/generic loop state
- `SetListState`
- guards and arithmetic companion metadata

Call products now present:

```asdl
CallShape = (LuaRT.ValueRef callee,
             LuaRT.StackWindow args,
             LuaRT.CountSpec wanted_results,
             boolean is_tailcall,
             boolean may_yield) unique

CallTargetIdentity = UnknownTargetIdentity unique
                   | LuaClosureTargetIdentity(LuaRT.ClosureRef closure,
                                               LuaSrc.KRef proto,
                                               number closure_handle,
                                               LuaFact.Dependency* deps) unique
                   | CClosureTargetIdentity(...)
                   | LightCFunctionTargetIdentity(...)
                   | MetamethodTargetIdentity(...)
                   | FFISymbolTargetIdentity(...)

CallFrameLayout = (LuaRT.CallFrameRef id,
                   LuaRT.FrameRef caller,
                   LuaRT.FrameRef callee,
                   LuaRT.Slot callee_slot,
                   LuaRT.Slot arg_base,
                   LuaRT.CountSpec arg_count,
                   LuaRT.Slot result_base,
                   LuaRT.CountSpec result_count,
                   LuaRT.Count frame_slots) unique
```

### Current LuaGC and LuaFFI are broad metadata layers

`LuaGC` includes:

- object headers, colors, phases, state, lists, allocator
- GC object kinds: string/table/closure/proto/thread/userdata/cdata/upvalue
- roots, barriers, facts, allocation/step/mark/traverse/finalizer/weak/ephemeron controls
- object products for `TString`, `TableObject`, `LClosure`, `UserdataObject`, `CDataObject`

Notable gap: `GCObjectKind` includes `ProtoKind`, `ThreadKind`, `UpvalueKind`, but `CollectableObject` currently has no `GCProtoObject`, `GCThreadObject`, or `GCUpvalueObject`.

`LuaFFI` includes:

- C scalar/type/param/layout/symbol/library/cdata/callback/finalizer products
- FFI operation outcomes and facts

Validators explicitly state they do not implement execution:

```lua
-- lua_ffi_validate.lua lines 1-5
-- They do not parse C, call LuaJIT FFI, dlopen/dlsym,
-- lower C ABIs, or implement C calls.
```

### Current LuaExec regions and partial executable gate

```lua
-- lua_exec_region_model.lua lines 14-41
M.EXECUTABLE_REGION_KIND = {
  CoreWindowRegion = true,
  LoadMoveRegion = true,
  BranchRegion

## Knowledge-builder Output — 2026-06-06 19:42:19

### What Matters Most for This Problem

- **Whole-architecture coherence before execution milestones**: ASDL must model complete Lua 5.5 semantics now; “supported today” belongs in validators/lowerers, not in product shape.
- **Cross-feature semantic closure**: calls, arity, metatables, close/TBC, yield/error, GC, FFI, closures/upvalues, and loops are mutually dependent.
- **Typed identity and invalidation**: every assumption needs structural ASDL identity: epochs, layouts, targets, continuations, region bindings, barriers, ABI, upvalues, metatables.
- **No implementation-status leakage into architecture**: scaffold/executable/phase concepts should not distort final semantic products.
- **Fail-closed without fake semantics**: rejected cases are fine; typed products must not encode “raw-only,” “no-meta,” or “fixed-shape only” as if they were full Lua semantics.

---

### Non-Obvious Observations

- **The current ASDL still reflects phased implementation, not a completed target architecture.**  
  Names/comments/models such as “scaffold-only,” “Phase 2,” “Phase 3,” `executable` flags on `RegionDescriptor`, and `EXECUTABLE_REGION_KIND` make implementation status visible in architectural products. For the corrected roadmap, ASDL should describe semantic possibility; executability should be a contract/lowering property, not a field baked into region identity.

- **`RegionDescriptor.executable` is especially suspect.**  
  A region’s semantic identity should not change because today’s lowerer can or cannot emit it. If variant keys or contracts include this boolean, code identity can accidentally encode compiler maturity instead of Lua meaning. The architecture likely needs separate typed support/validation facts, not semantic identity fields.

- **Calls are currently split across overlapping products that do not yet form one invariant.**  
  `CallShape`, `CallTarget`, `CallState`, `ResolvedCallTarget`, `CallArgChannel`, `CallResultChannel`, `CallFrameLayout`, and `CallFrameState` all describe parts of a call, but the ASDL itself does not enforce that:
  - they share the same `CallRef`,
  - the callee in `CallShape` matches `CallTarget.callee`,
  - arg/result counts match frame layout,
  - tailcall state matches continuation kind,
  - yielded/error outcomes correspond to call continuation wiring.  
  Full Lua 5.5 needs call identity as a single consistency spine across these products.

- **`CallTarget` has a shape smell: every target carries a `metamethod`.**  
  Non-metamethod calls still require a `LuaRT.Metamethod` field. That makes irrelevant data mandatory and risks bogus values becoming part of structural identity. Full architecture should distinguish direct callable identity from metamethod-call identity without forcing unused fields into every target.

- **Fixed-shape call-frame substrate is not the same as Lua call semantics.**  
  The current call-frame model copies args/results but explicitly does not invoke callee bodies. That is valid implementation substrate, but architecturally a full call product also needs:
  - frame activation/replacement,
  - proto dispatch/static region binding,
  - C/FFI call boundaries,
  - error/yield continuation,
  - close-on-tailcall/return,
  - open-result propagation,
  - vararg preparation,
  - debug/resume PC state.

- **Arity products are close, but still too “normalization-result” centered.**  
  `ArityNormalization(source, shape, channel)` describes source adjustment, but Lua call/return semantics also require ownership of top movement, caller/callee frame slots, result overwrite ranges, padding/truncation, and open tail propagation through nested call/vararg/constructor contexts. These are not just sequence transforms; they are frame effects.

- **`ResultChannel` mixes destination policy and value carrier.**  
  A result channel currently contains `kind`, `values`, and `count`. For full semantics, “where results go” and “what values exist” may diverge: return outcome, continuation args, caller stack slots, tailcall frame replacement, yielded values, and close-chain pending result all need different routing while sharing the same value sequence.

- **Closures/upvalues are under-modeled relative to their semantic weight.**  
  `UpvalueRef = (number index)` is too weak for full identity. Upvalues need proto/frame scope, open-vs-closed state, captured slot identity, close epoch, write barrier dependency, and alias identity across closures. Otherwise `GETUPVAL`/`SETUPVAL` can appear slot-like even though lifetime and invalidation are the main semantics.

- **GC and closure products are not yet aligned.**  
  `LuaGC.GCObjectKind` includes `ProtoKind`, `ThreadKind`, and `UpvalueKind`, but `CollectableObject` lacks corresponding object variants. That mismatch matters because closures, protos, threads, and upvalues are precisely the objects call/close/yield semantics depend on.

- **Metatable products describe lookup states but not complete invalidation identity.**  
  `MetatableRef`, `MetamethodLookup`, and `MetamethodCallHook` exist, but full semantics require epoch/fact identity for:
  - receiver’s metatable,
  - metamethod slot content,
  - type metatable cache,
  - `__index` / `__newindex` chains,
  - loop-limit assumptions,
  - metamethod absence vs presence.  
  `AssumesNoMetamethod(value, method)` is not enough unless tied to the exact metatable epoch and lookup path.

- **Raw table paths must not become the architectural table model.**  
  Current executable `GETTABLE`/`SETTABLE` are raw/no-metatable slices. Full ASDL must make raw access one branch of table semantics, not the table semantics. Otherwise metatable-present cases risk staying modeled as errors even though Lua requires call/table-chain behavior.

- **Arithmetic is split inconsistently.**  
  `LuaRT.ArithmeticOp` only covers arithmetic through `IDiv`, while `LuaExec.NumberOp` includes bitwise and unary ops. Lua 5.5 arithmetic/bitwise/unary semantics share companion/metamethod/coercion rules. Splitting them across layers risks losing the invariant that opcode, `MMBIN*`, operand order, operation kind, and metamethod selector are one semantic unit.

- **Companion opcodes are architectural, not lowering trivia.**  
  `MMBIN*`, `EXTRAARG`, comparison+`JMP`, loop groups, and call/result windows must remain represented as typed source-window constraints until semantic lowering has consumed them. Full ASDL should not let single-op regions claim completeness where Lua semantics require multi-op context.

- **Generic `for` is a call/arity/close/yield feature, not a loop feature.**  
  `GenericForState` currently stores iterator/state/control/closing/wanted results. Full generic-for semantics must tie this to iterator call identity, result channel, yielded call continuation, close variable, and loop backedge topology. Otherwise it will be impossible to distinguish “iterator returned nil” from call error/yield/close effects.

- **Numeric `for` still needs whole-region identity.**  
  Numeric for is simpler than generic for, but `FORPREP`/`FORLOOP` depend on typed loop variables, integer/float mode, control-slot conventions, backedge target, and overflow/comparison rules. Modeling only `NumericForState` is insufficient unless region topology is also first-class.

- **Close/TBC is under-integrated with error/yield/return.**  
  `CloseHook(kind, chain, result_channel)` captures a hook but not the ordering protocol: original result/error/yield, close method lookup, close call, replacement error, yielded close continuation, resume behavior, and tailcall frame replacement. Full semantics need close chains to be part of every exit path, not a side metadata hook.

- **Error and yield outcomes need richer causality.**  
  `ErrorState(kind, error_object, saved_pc, saved_top)` and `YieldState` exist, but full Lua 5.5 needs to know whether an error/yield occurred during normal call, metamethod, iterator, close, finalizer, FFI callback, or allocation path, because resumption/propagation rules differ.

- **GC is broad but not yet connected to allocation-producing opcodes.**  
  `NEWTABLE`, `CLOSURE`, allocating `CONCAT`, cdata creation, userdata, closures, and finalizers all require allocation/root/barrier/failure products. Current `GCHook` is too generic if it becomes the only bridge; full architecture needs typed allocation result/effect products tied to the runtime object being created.

- **FFI is architecturally broad but execution identity is thin.**  
  FFI products model layouts, symbols, callbacks, cdata, and finalizers, but full integration also needs call ABI channels, conversion rules between `LuaRT.TValue` and C values, ownership transitions, callback re-entry into Lua call/yield/error, and GC rooting/finalizer identity. `AssumesFFILayout(type_id, layout_hash)` is only one slice.

- **Stencil identity already knows about future domains, but materialization lags.**  
  `PatchSource` has GC/FFI/call/upvalue/metatable sources, while materialization supports only a subset. That is acceptable only if unsupported patch sources reject loudly. Architecturally, every executable contract assumption that can affect generated code needs a corresponding typed patch/variant identity path.

- **Foundry fact axes are too coarse for full semantics.**  
  Existing dependencies like `MetatableEpoch`, `UpvalueEpoch`, `CallTargetEpoch`, `VmAbiEpoch` are useful but likely too global. Full ASDL needs facts that bind an epoch to a specific object/path/layout/slot, or stale assumptions may survive structural keying.

- **Static regions must be semantic CFG composition, not call semantics by another name.**  
  `EmitRegion` / static invocation should mean typed CFG splice with explicit continuation binding. It must not hide callee dispatch, VM protocol, or fallback. The key invariant is: static region invocation composes already-typed regions; it does not discover Lua meaning at runtime.

- **`LuaExec.Module` is currently too shallow for full static region architecture.**  
  A module with `regions,kernels` needs region-library identity, duplicate-region constraints, continuation resolution, binding contracts, and inlining/composition invariants. Without these, static invocation can become a side table convention instead of ASDL-controlled architecture.

- **Contracts need relationship invariants, not just node presence.**  
  Current validators mostly check structural class membership. Full correctness requires cross-node constraints: same call ref, matching frame refs, matching region descriptors, dependency coverage for every assumption, no unknown target in executable contracts, no dynamic count where fixed required, etc.

- **The final ASDL should separate three notions now conflated:**
  - **semantic product exists**: well-formed Lua meaning;
  - **contract proves assumptions**: safe specialization;
  - **lowerer supports execution**: current implementation capability.  
  Phase-scaffold products blur these boundaries.

---

### Complete Typed Product Families That Must Exist Up Front

- **Call family**: call shape, resolved target, callable kind, callsite identity, arg/result channels, frame activation, continuation routing, tailcall replacement, yield/error paths, static callee region binding.
- **Arity/value sequence family**: count specs, open tails, top movement, padding/truncation, vararg/call-result propagation, sequence storage/projection, result routing.
- **Closure/upvalue family**: proto identity, closure object, open/closed upvalues, captured stack slots, close state, barriers, epochs.
- **Metatable/metamethod family**: metatable identity/epoch, lookup paths, absence/presence facts, chain limits, metamethod call hooks, receiver/key/value conventions.
- **Loop family**: numeric loop topology/state and generic iterator call/result/close/yield topology.
- **Close/TBC family**: close chains, hook origin, close method lookup/call, error replacement, yield/resume ordering, return/tailcall integration.
- **Error/yield/outcome family**: causality, saved PC/top, result preservation, resume points, continuation mapping.
- **GC/allocation family**: object headers, collectable variants, roots, allocation requests/results, barriers, finalizer queues, weak/ephemeron state, epochs.
- **FFI/cdata family**: C type/layout/symbol/ABI identity, scalar access, calls, conversions, callbacks, ownership, finalizers, GC interaction.
- **Static region family**: region descriptors, bindings, invocations, continuation contracts, module identity, splice/inlining invariants.
- **Contract/stencil family**: typed semantic assumptions, dependencies, patch sources, materialization support/rejection, structural variant keys.

---

### Final ASDL Invariants to Preserve

- No lowercase semantic strings or helper/protocol names carry meaning.
- LuaSrc opcode mechanics are fully consumed before MoonCFG; MoonCFG never rediscovers bytecode semantics.
- Every executable dynamic assumption has typed contract identity and invalidation dependencies.
- Every call-related product in one call path shares a coherent `CallRef`.
- Every upvalue identity is scoped enough to distinguish proto/frame/lifetime/epoch.
- Every metatable or metamethod absence assumption is epoch-bound.
- Every allocation-producing semantic path has GC allocation/root/barrier/failure representation.
- Every close-aware exit path explicitly models close ordering and replacement error/yield behavior.
- Every static region invocation has typed target binding and continuation wiring.
- Unsupported execution rejects, but well-formed full-semantics products remain representable.
- Stencil variant identity changes when any semantic assumption that can affect code changes.

---

### Knowledge Gaps

- Exact Lua 5.5 `__close` yield/error replacement ordering should be pinned against PUC behavior.
- The intended full static-region/module identity model is not yet present in ASDL.
- Upvalue/proto/thread GC object products need reconciliation with `GCObjectKind`.
- FFI callback/yield/error restrictions need precise target semantics before final ASDL locking.

## Documenter Output — 2026-06-06 19:44:15

# SpongeJIT Lua 5.5 Target Architecture: ASDL-First Complete Semantic Model

## Goal

Define SpongeJIT’s complete Lua 5.5 semantic architecture up front as typed ASDL products, so all future executable support—calls, arity, closures/upvalues, metatables, GC, FFI, loops, close/TBC, errors/yields, static regions, contracts, stencil identity, and foundry evidence—implements against one coherent target model while unsupported execution remains fail-closed until later implementation phases.

## Incentives

SpongeJIT already has a strong clean-base invariant: accepted kernels must compile through the typed route

```text
LuaSrc.Window -> LuaExec.Kernel -> MoonCFG.Kernel
```

with no interpreter fallback, protocol exit, helper-name semantics, or legacy opcode helper path. This protects correctness, but current executable coverage is intentionally narrow. `LuaSrc` decodes all 85 Lua 5.5 real opcodes, while `LuaExec`/`MoonCFG` currently accepts only a subset: basic loads/moves, returns, selected comparisons, `ADD`/`ADDI`/`ADDK`, raw `GETTABLE`/`SETTABLE`, limited `LEN`/`CONCAT`, selected varargs, and typed outcomes.

The main roadmap correction is that **implementation may be phased, but architecture must not be phased**. Lua 5.5 semantics are too interdependent for product vocabulary to grow opportunistically. Calls depend on arity, closures, metatables, generic `for`, FFI, close/TBC, yield/error, and static region invocation. GC allocation affects `NEWTABLE`, `CLOSURE`, strings, cdata, finalizers, barriers, roots, and object lifetime. Close/TBC affects returns, tailcalls, errors, yields, and finalizer ordering. If ASDL products are introduced only as local scaffolds for each implementation phase, they risk encoding partial truths that later conflict with full Lua semantics.

Therefore, ASDL must describe the complete Lua 5.5 semantic target now. Lowerers, validators, emitters, and tests may implement that target incrementally, but product identity must not encode current compiler maturity.

## Current State

### Architectural layers

The governing ASDL file is:

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`

Its layer doctrine is already correct and remains the target organizing principle:

| Layer | Responsibility |
|---|---|
| `LuaSrc` | What PUC encoded |
| `LuaEvidence` / `LuaFact` | What runtime/foundry proved and leased |
| `LuaFFI` | Lua-visible C FFI declarations, types, values, and facts |
| `LuaGC` | Explicit Lua GC objects, state, control facts |
| `LuaRT` | Lua runtime semantic objects/state |
| `LuaExec` | Explicit semantic Lua CFG over `LuaRT` |
| `CompileContract` | Executable-route obligations, facts, invalidation assumptions |
| `MoonCFG` | Explicit Moonlift CFG emitted from semantic products |
| `Stencil` | Typed copy/patch backend artifact identity and patch sources |

The clean-base compiler path is:

```text
PUC/event rows
  -> lua_src_from_puc_decode.lua
  -> LuaSrc.Window
  -> LuaCompile.Unit(source, evidence)
  -> lua_src_to_lua_exec_lower.lua
  -> LuaExec.Kernel
  -> lua_exec_to_moon_cfg_lower.lua
  -> MoonCFG.Kernel
  -> moon_cfg_validate.lua
  -> moon_cfg_emit.lua
```

The public compiler route has no semantic fallback. Unsupported windows reject.

### LuaSrc coverage

`LuaSrc.Op` already covers all 85 Lua 5.5 real opcodes plus `UnsupportedOpcode`.

It preserves source-level bytecode mechanics including:

- `EXTRAARG` for `LOADKX`, `NEWTABLE`, `SETLIST`
- `MMBIN`, `MMBINI`, `MMBINK`
- comparison + `JMP` patterns
- call/return count fields
- `FOR*` and `TFOR*` loop groups
- close/TBC opcodes
- closure/upvalue/table/call forms
- vararg and `GETVARG` forms

Tests assert explicit 85/85 decoder coverage. Source fidelity is not the main gap.

### Current executable slice

Current `lua_src_to_lua_exec_lower.lua` accepts a limited subset:

- loads/moves: `LOADNIL`, `LOADFALSE`, `LOADTRUE`, `LOADI`, `LOADK`, `MOVE`
- control/truthiness: `NOT`, `TEST`, `TESTSET`, closed `JMP`
- comparisons only with valid following `JMP`
- returns: `RETURN0`, `RETURN1`, selected `RETURN`
- arithmetic: `ADD`, `ADDI`, `ADDK` with valid `MMBIN*` companion context
- raw table access/update: selected `GETTABLE`, `SETTABLE`
- limited `LEN`, `CONCAT`
- selected `VARARG`, `GETVARG`
- typed errors/outcomes such as `ERRNNIL`

Common Lua features still reject:

- `CALL`, `TAILCALL`
- `CLOSURE`, `GETUPVAL`, `SETUPVAL`
- `GETTABUP`, `SETTABUP`, `GETFIELD`, `SETFIELD`, `GETI`, `SETI`, `SELF`
- `NEWTABLE`, `SETLIST`
- `FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, `TFORLOOP`
- `CLOSE`, `TBC`
- most arithmetic/bitwise/unary operations
- full metatable/metamethod behavior
- FFI/cdata execution
- GC allocation/finalization execution

This fail-closed behavior is correct. The issue is not that these reject today; the issue is that the architecture must already be rich enough to represent their full semantics.

### Current product surface

Recent work introduced typed products for:

- region taxonomy and descriptors
- arity/result channels
- arity normalization
- call target identity
- call frames
- call arg/result channels
- call-frame transfer substrate
- typed contract assumptions
- typed stencil patch sources

These are useful foundations, but the corrected roadmap treats them as partial current material, not the final architectural boundary. Product shape must now be reviewed as complete Lua 5.5 architecture rather than phase-local scaffolding.

### Current design tensions

The scout and knowledge-builder findings identify several important tensions:

1. **Implementation status leaks into architecture.**  
   Terms and flags such as scaffold-only, executable region kind tables, and `RegionDescriptor.executable` encode current compiler capability rather than Lua semantic identity.

2. **Calls are split across overlapping products.**  
   `CallShape`, `CallTarget`, `CallState`, `ResolvedCallTarget`, `CallArgChannel`, `CallResultChannel`, `CallFrameLayout`, and `CallFrameState` exist, but the architecture must make their shared `CallRef` and cross-field invariants explicit.

3. **`CallTarget` carries a mandatory metamethod field.**  
   Non-metamethod calls still carry a `LuaRT.Metamethod`, forcing irrelevant data into structural identity.

4. **Arity is modeled as sequence normalization, but full Lua arity also moves frame state.**  
   Calls, returns, varargs, `SETLIST`, constructors, tailcalls, and generic `for` require top movement, slot overwrite ranges, open-tail propagation, and result routing.

5. **Closures/upvalues are under-modeled.**  
   `UpvalueRef` is too weak if it only identifies an index. Full semantics require proto/frame scope, captured slot identity, open/closed state, lifetime, close epoch, aliasing, and barriers.

6. **Metatable facts are insufficient without lookup-path identity.**  
   Assumptions such as no metamethod must be tied to exact metatable epoch and lookup path.

7. **GC object taxonomy is broader than collectable object representation.**  
   `GCObjectKind` includes proto/thread/upvalue kinds, while collectable object variants are not fully aligned.

8. **`LuaExec.Module` and static regions are shallow.**  
   Full static region architecture needs region library identity, duplicate detection, continuation resolution, binding contracts, and splice/inlining invariants.

9. **Contract validation is mostly structural.**  
   Full correctness needs relationship invariants: same call refs, matching frame layouts, matching descriptors, epoch coverage, fixed/dynamic arity legality, and no unknown executable targets.

## Chosen Target

### Approach

The chosen target is:

> A complete ASDL-first Lua 5.5 semantic architecture, with static semantic regions as the executable organization, where unsupported implementation cases reject but all full Lua semantics are representable as typed products from the beginning.

This is not an implementation plan. It defines the architecture that implementation phases must target.

Implementation phases may later make individual subsets executable, but they must not invent temporary product concepts that encode partial semantics. A phase asks:

```text
Which part of the complete ASDL product model becomes executable now?
```

not:

```text
Which reduced product model is enough for this phase?
```

### Core invariant

The central invariant is:

```text
Semantic meaning lives in ASDL products.
Execution support lives in validators/lowerers/emitters.
Current compiler maturity must not become semantic identity.
```

A well-formed Lua semantic product may exist even if it is not executable yet. Unsupported execution rejects loudly.

---

## Complete Target Product Families

## LuaSrc

`LuaSrc` is source fidelity only.

It must preserve:

- all Lua 5.5 opcode fields;
- opcode companion structure:
  - `EXTRAARG`
  - `MMBIN*`
  - comparison + `JMP`
  - call/result windows
  - loop groups
- bytecode-local operands, counts, flags, slots, constants, and PCs.

`LuaSrc` must not contain runtime semantics. Opcode mechanics must be consumed before `MoonCFG`; `MoonCFG` must never rediscover Lua opcode meaning.

## LuaRT

`LuaRT` is the full Lua runtime semantic state model.

It must model:

### Values, frames, stacks, and sequences

- tagged Lua values
- slots and stack windows
- frame identity
- top movement
- arbitrary value sequences
- open tails
- fixed and dynamic counts
- padding/truncation
- sequence storage/projection
- result routing

Important product concepts:

- `ValueRef`
- `FrameRef`
- `StackWindow`
- `CountSpec`
- `ValueSeq`
- `ArityShape`
- `ArityNormalization`
- result-routing products distinct from value carriers

### Calls

Calls are the central semantic spine.

The target call family must include:

- callsite identity
- callee value
- callable kind
- resolved target identity
- Lua closure targets
- C closure targets
- light C function targets
- metamethod targets
- FFI symbol targets
- call argument channel
- call result channel
- frame activation
- frame replacement for tailcalls
- static callee region binding
- error continuation
- yield continuation
- return continuation
- close-aware exits
- result arity adjustment
- saved PC/top for resume

All call-related products in one call path must share a coherent `CallRef`.

### Arity and result routing

Arity is not just sequence normalization. Full architecture must represent:

- provided count
- wanted count
- open result propagation
- vararg propagation
- call-result propagation
- padding with nil
- truncation
- caller/callee frame slot ownership
- result overwrite ranges
- return outcome routing
- continuation routing
- tailcall frame replacement
- yielded value routing
- close-chain pending result routing

A value sequence and a destination channel are separate concepts, even when current code combines them.

### Closures and upvalues

The closure/upvalue family must include:

- proto identity
- closure object identity
- closure allocation
- open upvalue identity
- closed upvalue identity
- captured stack slot identity
- owner frame/proto scope
- alias identity across closures
- upvalue close state
- close epoch
- upvalue write barriers
- upvalue invalidation dependencies
- `GETUPVAL` / `SETUPVAL` semantics

Upvalues must not be modeled as simple slots.

### Tables and metatables

The table family must include both raw and metamethod-aware semantics:

- table object identity
- array/hash shape
- raw get/set
- nil-key errors
- table barriers
- metatable ref
- metatable epoch
- type metatable cache identity
- `__index`
- `__newindex`
- `__call`
- lookup-chain path identity
- lookup-chain limits
- metamethod absence/presence facts

Raw table access is one branch of table semantics, not the full table model.

### Arithmetic, bitwise, unary, comparison, concat, len

The operation family must unify:

- opcode operation kind
- operand order
- immediate/constant/register source
- `MMBIN*` companion relationship
- operand-flip flags
- numeric coercion
- integer/float behavior
- bitwise behavior
- unary operations
- comparison branch behavior
- concat allocation
- len string/table/metamethod behavior
- metamethod lookup and call fallback

Companion opcodes are architectural context, not lowering trivia.

### Loops

Loop semantics must be whole-region, not single-op.

Numeric loops require:

- `FORPREP`/`FORLOOP` topology
- control variable slots
- limit/step state
- integer vs float mode
- overflow/comparison rules
- backedge identity

Generic loops require:

- iterator function/state/control values
- iterator call shape
- result channel
- yielded iterator call continuation
- close variable handling
- nil-stop behavior
- loop backedge topology

Generic `for` is a call/arity/yield/close feature as much as a loop feature.

### Close/TBC, error, yield, outcome

Close/TBC must be integrated into every exit path.

The target family must include:

- close chains
- close hook origin:
  - explicit `CLOSE`
  - `TBC`
  - return
  - tailcall
  - error
  - yield
  - finalizer
- close method lookup
- close method call
- close-call error replacement
- close-call yield/resume
- original result/error preservation
- final propagated result/error/yield
- saved PC/top
- resume points
- causality of error/yield:
  - normal call
  - metamethod
  - iterator
  - close
  - finalizer
  - allocation
  - FFI callback

A metatable-present path or close-required path must not be represented as a typed error if Lua semantics require a call.

### GC and allocation

The GC/allocation family must include:

- object headers
- object colors
- GC phases
- roots
- barriers
- allocation requests
- allocation results
- allocation failure
- root safety during initialization
- finalizer queues
- weak/ephemeron behavior
- GC epochs
- table/string/closure/proto/thread/upvalue/userdata/cdata objects
- object lifetime and ownership

Allocation-producing semantics include:

- `NEWTABLE`
- `CLOSURE`
- allocating `CONCAT`
- cdata/userdata creation
- finalizer-bearing objects
- closure/upvalue objects

`LuaGC.GCObjectKind` and collectable object variants must be reconciled so every collectable kind has a coherent product representation.

### FFI and cdata

The FFI/cdata family must include:

- C type identity
- layout identity
- ABI identity
- symbols/libraries
- scalar loads/stores
- cdata ownership
- cdata finalizers
- C calls
- callbacks
- Lua/C value conversion
- callback re-entry into Lua call/yield/error semantics
- FFI allocation and GC rooting
- FFI finalizer ordering

FFI is not only scalar access; it depends on calls, ABI, GC, ownership, conversion, error/yield, and finalization.

---

## LuaExec

`LuaExec` is the explicit semantic CFG over `LuaRT`.

It must provide a complete static semantic region library for Lua 5.5:

| Region family | Meaning |
|---|---|
| Load/move | register/value transfer |
| Return | result routing, close-aware exits |
| Call | callsite, target, frame, continuations |
| Tailcall | frame replacement, close-aware tail exit |
| Table access | raw and metamethod-aware get/set |
| Metatable | lookup paths and metamethod invocation |
| Arithmetic/bitwise/unary | numeric/coercion/metamethod semantics |
| Compare/branch | comparison semantics plus control topology |
| Closure | closure allocation and proto/upvalue binding |
| Upvalue | open/closed access, write barrier, close lifetime |
| Numeric for | whole-loop numeric topology |
| Generic for | iterator call/result/yield/close topology |
| Close/TBC | close-chain execution |
| GC allocation | allocation/root/barrier/failure effects |
| FFI | cdata/ABI/call/callback/finalizer semantics |
| Error/yield | outcome causality and continuation |
| Static continuation | typed region composition and continuation binding |

Static region invocation is semantic CFG composition. It must never mean VM dispatch, interpreter fallback, or dynamic rediscovery of Lua opcode behavior.

Required static-region concepts include:

- region identity
- region descriptors
- region references
- module region libraries
- static region bindings
- static invocations
- continuation bindings
- call continuation regions
- splice/inlining invariants
- duplicate-region constraints
- continuation resolution

`LuaExec.Module` must be a first-class architecture product, not a shallow container.

---

## CompileContract

`CompileContract` records typed assumptions and invalidation obligations.

It must cover:

- call target identity
- callable kind
- call target epoch
- arity/result shape
- frame layout
- static region binding
- continuation binding
- closure proto identity
- closure object identity
- upvalue identity and epoch
- metatable identity and epoch
- metamethod absence/presence
- exact metamethod lookup path
- table shape/hash/array facts
- GC allocation/root/barrier facts
- GC epoch
- finalizer obligations
- FFI type/layout/ABI identity
- FFI symbol identity
- cdata ownership/finalizer identity
- VM ABI/layout dependencies

Contracts must not merely contain nodes; they must encode relationship invariants. For example:

- all products for one call path share the same `CallRef`;
- result counts match frame layout;
- call target identity matches callable kind;
- static invocation target binding matches region descriptor;
- metatable absence is tied to a specific metatable epoch and lookup path;
- upvalue assumptions are tied to specific closure/proto/frame identity.

No semantic assumption may be hidden in strings, helper names, side tables, or untyped variant keys.

---

## MoonCFG

`MoonCFG` is the typed Moonlift CFG emitted from semantic products.

It must contain explicit runtime operations for:

- value sequence construction/normalization
- sequence storage/projection
- outcome construction/projection
- stack/frame transfer
- call target checks
- frame activation/replacement
- static region invocation after validation/inlining
- table raw and metamethod-aware paths
- arithmetic/coercion/metamethod paths
- closure/upvalue access and close behavior
- GC allocation/root/barrier/finalizer behavior
- close-chain execution
- FFI/cdata scalar/ABI/call behavior

`MoonCFG` must not contain Lua opcode mechanics. It must not contain lowercase semantic strings such as `"call"`, `"close"`, `"generic_for"`, `"setlist"`, `"out_tag"`, or helper/protocol tags as carriers of meaning.

If `MoonCFG.EmitRegion` is supported later, it must be typed and validated. Until then, static `LuaExec` invocation may be inlined before MoonCFG.

---

## Stencil and Foundry

Stencil and foundry identity must be structural ASDL identity.

Foundry evidence must provide typed facts with precise dependencies, not broad global hints. Stencil keys must change when any assumption that can affect emitted code changes.

Required identity domains include:

- call target identity
- call frame layout
- static region binding
- static region invocation
- continuation binding
- metatable epoch and lookup path
- upvalue epoch and identity
- table shape
- FFI type/layout/ABI/symbol
- GC state/epoch/barrier/root
- closure/proto identity
- cdata ownership/finalizer identity

Stencil patch sources must be typed. Unsupported patch sources must reject loudly during validation/materialization rather than silently degrading.

---

## Architecture Cleanup Requirements

The following current ASDL/model smells must be cleaned up as part of converging on the complete target architecture. These are architectural requirements, not implementation steps.

### Remove implementation-status identity from semantic products

Products must not encode current lowerer support.

Problematic concepts include:

- `RegionDescriptor.executable`
- scaffold-only naming in product identity
- executable/scaffold region-kind classifications treated as semantic facts
- phase-oriented comments or names that imply temporary architecture

Executability is a property of validator/lowerer support plus contract satisfaction, not region semantic identity.

### Separate semantic existence, contract proof, and executable support

The architecture must distinguish:

1. a product is well-formed Lua semantics;
2. a contract proves assumptions for specialization;
3. a lowerer/emitter currently supports execution.

These must not be conflated.

### Normalize call identity around a single spine

All call products must consistently relate through one call identity. The architecture must make it impossible to accidentally combine mismatched:

- call shape
- call target
- resolved target
- arg channel
- result channel
- frame layout
- frame state
- continuation region
- static callee binding

### Fix `CallTarget` shape

A direct non-metamethod call should not carry irrelevant metamethod data. Metamethod calls should have explicit metamethod target identity; direct calls should not require placeholder metamethod fields.

### Strengthen arity/frame semantics

Arity must model frame effects and routing, not only sequence normalization. Destination/result policy must be distinct from the value sequence itself.

### Strengthen upvalue identity

Upvalue identity must include enough scope to distinguish proto, closure, frame, captured slot, open/closed state, lifetime, close epoch, aliasing, and barrier dependencies.

### Bind metatable assumptions to lookup identity

Metamethod absence/presence facts must be tied to exact metatable epoch and lookup path, not only `(value, method)`.

### Reconcile GC object taxonomy

Every `GCObjectKind` used by Lua semantics must have a corresponding collectable object representation and lifecycle model.

### Promote `LuaExec.Module` to a full semantic product

Modules must define region library identity, uniqueness, continuation resolution, static invocation contracts, and splice/inlining invariants.

### Strengthen contract validation beyond shape checks

Contracts must validate relationships, not just constructor classes.

---

## Validation Invariants

Validators must enforce:

- no lowercase semantic strings carry meaning;
- source opcode mechanics do not survive into MoonCFG;
- every executable dynamic assumption has typed contract identity;
- every call path has coherent `CallRef`;
- every static invocation has target binding and continuation wiring;
- every upvalue assumption is scoped by lifetime/epoch;
- every metatable assumption is epoch/path-bound;
- every allocation path has GC allocation/root/barrier/failure representation;
- every close-aware exit models close ordering;
- unsupported execution rejects loudly;
- well-formed full-semantics products remain representable even if not executable;
- stencil identity changes when semantic assumptions change.

---

## Testing Architecture

Tests must distinguish:

| Test category | Purpose |
|---|---|
| ASDL schema tests | Ensure complete product families exist and field-order invariants hold |
| Structural validation tests | Ensure well-formed semantic products validate even if not executable |
| Executability gate tests | Ensure unsupported products reject at lowering/emission boundaries |
| No-fallback tests | Ensure no helper/protocol/string fallback enters accepted products |
| Contract invariant tests | Ensure assumptions are typed and relationship-consistent |
| Stencil key tests | Ensure semantic assumptions affect structural identity |
| PUC conformance tests | Ensure executable semantics match Lua 5.5 behavior |
| Negative stale-contract tests | Ensure invalidated facts reject or recompile |
| Corpus tests | Measure accepted semantic family coverage, not opcode-name coverage alone |

Coverage must not be reported as merely:

- decoded opcode count;
- fact availability;
- ASDL product presence;
- emitter fragment presence.

Coverage means accepted execution of a semantic family under typed contracts and validation.

---

## Final Target Summary

The SpongeJIT Lua 5.5 target architecture is:

```text
Complete LuaSrc fidelity
  -> complete LuaRT semantic state
  -> complete LuaExec static semantic regions
  -> typed CompileContract assumptions/invalidation
  -> explicit MoonCFG runtime operations
  -> structural Stencil/foundry identity
```

The compiler remains fail-closed. Unsupported execution rejects. But the architecture itself must already be complete, coherent, and Lua 5.5-shaped.

The decisive rule is:

> ASDL is the architecture. Implementation phases fill in executable lowering later; they do not define partial architectures.

## Edit-planner Output — 2026-06-06 20:00:55

### Precondition Checks

Before edits begin, verify current repo matches Phase 3 state:

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
  - `LuaRT.UpvalueRef = (number index)` at line ~535.
  - `LuaRT.ResultChannel = (kind,values,count)` at line ~668.
  - `LuaRT.CallTarget = (kind,callee,metamethod)` at line ~811.
  - `LuaExec.RegionDescriptor = (..., boolean executable)` at lines ~1318-1324.
  - `CompileContract.SemanticAssumption` starts at line ~1537.
  - `Stencil.PatchSource` starts at line ~1898.
- Current source lowering still rejects `CALL`/`TAILCALL`; do **not** add them to `SUPPORTED_INSTR`.
- Existing Phase 1–3 tests are green before starting.
- Treat old edit-plan tasks `T037`–`T048` as obsolete; they are skipped in the sidecar.

---

## Files to Modify

### `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`

**Goal**: Replace phased/scaffold product shape with complete Lua 5.5 semantic architecture while keeping executable support separate.

#### Edit blocks

1. **Lines ~535-560: strengthen refs**
   - Replace weak/index-only upvalue identity:
     ```asdl
     UpvalueRef = (number index) unique
     ```
   - With name-based refs plus scoped identity:
     ```asdl
     ProtoRef = (LuaSrc.KRef proto) unique
     UpvalueRef = (LuaRT.Name name) unique

     UpvalueStorageKind = OpenStackUpvalue | ClosedHeapUpvalue | DeadUpvalue
     UpvalueIdentity = (LuaRT.UpvalueRef upvalue,
                        LuaRT.ProtoRef proto,
                        LuaRT.ClosureRef owner,
                        LuaRT.FrameRef frame,
                        LuaRT.Slot captured_slot,
                        LuaRT.UpvalueStorageKind storage,
                        number close_epoch,
                        number alias_epoch) unique

     ClosureIdentity = (LuaRT.ClosureRef closure,
                        LuaRT.ProtoRef proto,
                        LuaRT.UpvalueIdentity* upvalues,
                        number closure_epoch) unique
     ```
   - Update all `RT.UpvalueRef(0)`-style test constructors.

2. **Lines ~650-676: separate value carrier from result routing**
   - Replace `ResultChannel = (kind, values, count)` with:
     ```asdl
     ResultRouteKind = DirectReturnRoute
                     | OutcomeReturnRoute
                     | StackWindowRoute
                     | ContinuationRoute
                     | TailCallFrameRoute
                     | YieldRoute
                     | ClosePendingRoute

     ResultDestination = ReturnDestination unique
                       | OutcomeDestination unique
                       | StackWindowDestination(LuaRT.StackWindow window) unique
                       | ContinuationDestination(LuaRT.Name continuation) unique
                       | TailCallDestination(LuaRT.FrameRef frame) unique
                       | YieldDestination(LuaRT.ResumePoint resume_point) unique
                       | ClosePendingDestination(LuaRT.CloseChain chain) unique

     ResultChannel = (LuaRT.Name id,
                      LuaRT.ResultRouteKind kind,
                      LuaRT.ResultDestination destination,
                      LuaRT.CountSpec count) unique

     ResultBundle = (LuaRT.ValueSeq values,
                     LuaRT.ResultChannel channel) unique

     FrameEffectKind = SetTopEffect | StoreSeqEffect | ReplaceFrameEffect | PreserveFrameEffect
     FrameEffect = (LuaRT.FrameEffectKind kind,
                    LuaRT.FrameRef frame,
                    LuaRT.StackWindow window,
                    LuaRT.CountSpec count) unique

     ArityNormalization = (LuaRT.ValueSeq source,
                           LuaRT.ArityShape shape,
                           LuaRT.ResultBundle result,
                           LuaRT.FrameEffect* effects) unique
     ```
   - Remove `UnsupportedReturnChannel` / `CallFrameResultChannel`; unsupported support status must not be ASDL identity.

3. **Lines ~770-878: rebuild call spine around `CallRef`**
   - Replace `CallTargetKind` + `CallTarget(kind, callee, metamethod)` with sum variants:
     ```asdl
     CallTarget = UnknownCallTarget(LuaRT.ValueRef callee) unique
                | DirectLuaClosureTarget(LuaRT.ValueRef callee, LuaRT.ClosureRef closure) unique
                | DirectCClosureTarget(LuaRT.ValueRef callee, LuaRT.ClosureRef closure) unique
                | DirectLightCFunctionTarget(LuaRT.ValueRef callee, LuaRT.FunctionRef function) unique
                | MetamethodFunctionTarget(LuaRT.ValueRef callee, LuaRT.MetamethodLookupPath path) unique
                | FFISymbolTarget(LuaRT.ValueRef callee, LuaFFI.CSymbolId symbol) unique
     ```
   - Change call products to carry one coherent call id:
     ```asdl
     TailCallMode = NotTailCall | TailCallReplace | TailCallWithClose
     YieldPolicy = NonYieldingCall | YieldingCall | YieldForbidden

     CallShape = (LuaRT.CallRef call,
                  LuaRT.ValueRef callee,
                  LuaRT.StackWindow args,
                  LuaRT.CountSpec wanted_results,
                  LuaRT.TailCallMode tail_mode,
                  LuaRT.YieldPolicy yield_policy) unique

     ResolvedCallTarget = (LuaRT.CallRef call,
                           LuaRT.CallTarget target,
                           LuaRT.CallTargetIdentity identity,
                           LuaRT.CallableKind callable) unique

     CallArgChannel = (LuaRT.CallRef call,
                       LuaRT.ValueSeq args,
                       LuaRT.ArityShape shape) unique

     CallResultChannel = (LuaRT.CallRef call,
                          LuaRT.ResultChannel channel,
                          LuaRT.ArityNormalization normalization) unique

     CallFrameState = (LuaRT.CallRef call,
                       LuaRT.CallFrameLayout layout,
                       LuaRT.CallArgChannel args,
                       LuaRT.CallResultChannel results,
                       LuaRT.ResolvedCallTarget target,
                       LuaRT.CallFrameStateKind state) unique
     ```
   - Validators must reject mismatched `CallRef` relationships.

4. **Lines ~760-780: complete metatable lookup identity**
   - Replace simple `MetamethodLookup`/`MetamethodCallHook` with:
     ```asdl
     MetatableEpoch = (LuaRT.MetatableRef metatable, number epoch) unique
     MetamethodSlot = (LuaRT.MetatableRef metatable,
                       LuaRT.Metamethod method,
                       LuaRT.ValueRef slot_value,
                       number slot_epoch) unique

     MetamethodLookupStep = CheckReceiverMetatable(LuaRT.ValueRef receiver, LuaRT.MetatableEpoch epoch) unique
                          | CheckTypeMetatable(LuaRT.ValueTag tag, LuaRT.MetatableEpoch epoch) unique
                          | CheckMetamethodSlot(LuaRT.MetamethodSlot slot) unique
                          | FollowIndexTable(LuaRT.TableRef table, number depth) unique
                          | InvokeMetamethodCandidate(LuaRT.ValueRef function) unique

     MetamethodLookupResult = MetamethodFoundResult(LuaRT.ValueRef function) unique
                            | MetamethodMissingResult unique
                            | MetamethodLookupTypeError(LuaRT.ValueRef receiver) unique
                            | MetamethodLookupLoopLimitExceeded unique

     MetamethodLookupPath = (LuaRT.ValueRef receiver,
                             LuaRT.Metamethod method,
                             LuaRT.MetamethodLookupStep* steps,
                             LuaRT.MetamethodLookupResult result,
                             LuaFact.Dependency* deps) unique

     MetamethodDispatch = (LuaRT.MetamethodLookupPath path,
                           LuaRT.CallShape call,
                           LuaRT.ResultChannel result_channel) unique
     ```

5. **Lines ~940-1000: complete loop and operation products**
   - Extend loops with topology:
     ```asdl
     LoopTopology = NumericForTopology(LuaRT.Pc prep_pc, LuaRT.Pc loop_pc, LuaRT.Pc body_start, LuaRT.Pc exit_pc) unique
                  | GenericForTopology(LuaRT.Pc prep_pc, LuaRT.Pc call_pc, LuaRT.Pc loop_pc, LuaRT.Pc body_start, LuaRT.Pc exit_pc) unique
     ```
   - Replace narrow `ArithmeticOp` with complete operation shape:
     ```asdl
     OperationKind = OpAdd | OpSub | OpMul | OpMod | OpPow | OpDiv | OpIDiv
                   | OpBand | OpBor | OpBXor | OpShl | OpShr
                   | OpUnm | OpBNot | OpNot | OpLen | OpConcat
                   | OpEq | OpLt | OpLe | OpTest | OpTestSet

     OperandSourceKind = RegisterOperand | ImmediateOperand | ConstantOperand
     OperationOperand = (LuaRT.OperandSourceKind source,
                         LuaRT.ValueRef value,
                         boolean flipped) unique

     CompanionContext = NoCompanion unique
                      | MMBINCompanion(LuaRT.Pc pc, LuaRT.Metamethod method) unique
                      | MMBINICompanion(LuaRT.Pc pc, LuaRT.Metamethod method, boolean operands_flipped) unique
                      | MMBINKCompanion(LuaRT.Pc pc, LuaRT.Metamethod method, boolean operands_flipped) unique
                      | ExtraArgCompanion(LuaRT.Pc pc, LuaRT.Ax ax) unique

     LuaOperation = (LuaRT.Pc pc,
                     LuaRT.OperationKind kind,
                     LuaRT.OperationOperand* operands,
                     LuaRT.ValueRef* results,
                     LuaRT.CompanionContext companion,
                     LuaRT.MetamethodLookupPath metamethod_path) unique
     ```

6. **Lines ~894-940: complete error/yield/close causality**
   - Keep current `ErrorState`/`YieldState` if needed for emitter compatibility, but add causality products:
     ```asdl
     OutcomeCause = DirectReturnCause
                  | CallCause(LuaRT.CallRef call) unique
                  | MetamethodCause(LuaRT.MetamethodLookupPath path) unique
                  | IteratorCause(LuaRT.LoopTopology topology) unique
                  | CloseCause(LuaRT.CloseChain chain) unique
                  | FinalizerCause(LuaRT.Name finalizer) unique
                  | AllocationCause(LuaRT.Name allocation) unique
                  | FFICallbackCause(LuaFFI.CCallbackId callback) unique

     CloseAction = CloseSkipFalsey(LuaRT.CloseItem item) unique
                 | CloseLookupMethod(LuaRT.CloseItem item, LuaRT.MetamethodLookupPath path) unique
                 | CloseInvokeMethod(LuaRT.CloseItem item, LuaRT.CallShape call) unique
                 | ClosePropagateOriginal(LuaRT.ResultBundle result) unique
                 | CloseReplaceWithError(LuaRT.ErrorState error) unique
                 | CloseYieldAndResume(LuaRT.YieldState yield) unique

     ClosePlan = (LuaRT.CloseChain chain,
                  LuaRT.OutcomeCause cause,
                  LuaRT.CloseAction* actions,
                  LuaRT.ResultBundle pending_result) unique
     ```

7. **Lines ~1040-1248: complete GC collectables/effects**
   - Add missing collectables:
     ```asdl
     ProtoObject = (LuaGC.GCHeader header, LuaRT.ProtoRef proto, string proto_hash) unique
     ThreadObject = (LuaGC.GCHeader header, LuaRT.ThreadRef thread, LuaRT.FrameRef* frames) unique
     UpvalueObject = (LuaGC.GCHeader header, LuaRT.UpvalueIdentity identity, LuaRT.ValueRef value) unique
     ```
   - Extend `CollectableObject` with `GCProtoObject`, `GCThreadObject`, `GCUpvalueObject`.
   - Replace generic `GCHook` identity with explicit effects:
     ```asdl
     GCEffect = GCAllocationEffect(LuaGC.AllocRequest request, LuaGC.AllocResult result) unique
              | GCRootEffect(LuaGC.RootSet roots) unique
              | GCBarrierEffect(LuaGC.BarrierKind barrier, LuaGC.BarrierAction action, LuaGC.BarrierResult result) unique
              | GCFinalizerEffect(LuaGC.FinalizerRequest request, LuaGC.FinalizerProcessingResult result) unique
              | GCEpochEffect(LuaGC.GCFact fact) unique
     ```

8. **Lines ~260-430: complete FFI call/callback/ownership**
   - Add FFI ABI products:
     ```asdl
     CValueConversion = LuaToCValue(LuaRT.ValueRef lua_value, LuaFFI.CType type) unique
                      | CToLuaValue(LuaFFI.CType type, LuaRT.ValueRef lua_value) unique

     FFICallShape = (LuaFFI.CSymbolId symbol,
                     LuaFFI.CAbi abi,
                     LuaFFI.CParamList params,
                     LuaFFI.CType return_type,
                     LuaFFI.CValueConversion* conversions,
                     LuaRT.CallRef call) unique

     CDataOwnershipTransition = (LuaFFI.CData cdata,
                                 LuaFFI.OwnershipState from_state,
                                 LuaFFI.OwnershipState to_state,
                                 LuaFact.Dependency* deps) unique

     FFICallbackEntry = (LuaFFI.CCallbackId callback,
                         LuaFFI.CAbi abi,
                         LuaRT.CallShape call,
                         LuaRT.OutcomeCause cause) unique
     ```

9. **Lines ~1255-1325: remove implementation status from region identity**
   - Replace:
     ```asdl
     RegionDescriptor = (..., boolean executable)
     ```
   - With:
     ```asdl
     RegionDescriptor = (LuaExec.RegionId id,
                         LuaExec.RegionKind kind,
                         LuaExec.OpcodeFamily family,
                         LuaRT.Pc start_pc,
                         LuaRT.Pc end_pc) unique
     ```
   - Add complete module/static region products:
     ```asdl
     ModuleId = (LuaExec.Name name) unique
     ModuleDescriptor = (LuaExec.ModuleId id,
                         LuaExec.RegionDescriptor* regions,
                         LuaExec.RegionDescriptor* kernels) unique

     StaticRegionRole = StaticCalleeBodyRegion
                      | StaticContinuationRegion
                      | StaticInlineOnlyRegion
                      | StaticKernelBodyRegion

     StaticRegionBinding = (LuaExec.RegionRef region,
                            LuaExec.RegionDescriptor descriptor,
                            LuaExec.StaticRegionRole role) unique

     StaticRegionInvocation = (LuaExec.Name id,
                               LuaExec.StaticRegionBinding target,
                               LuaExec.Arg* args,
                               LuaExec.ContBinding* continuations,
                               LuaExec.CallContinuationRegion call_continuation) unique
     ```
   - Remove/rename phase/scaffold identity terms; diagnostic strings may say unsupported, ASDL must not.

10. **Lines ~1400-1525: update LuaExec expr/op/contracts**
   - Replace hook exprs:
     - `MetamethodCallHookExpr` → `MetamethodDispatchExpr`
     - `CloseHookExpr` → `ClosePlanExpr`
     - `GCHookExpr` → `GCEffectExpr`
   - Add:
     ```asdl
     StaticRegionBindingExpr(...)
     StaticRegionInvocationExpr(...)
     LuaOperationExpr(LuaRT.LuaOperation operation)
     ```
   - Add obligations/guarantees for complete products:
     `RequiresResultRoute`, `RequiresFrameEffect`, `RequiresStaticRegion`, `RequiresStaticRegionInvocation`, `RequiresMetamethodLookupPath`, `RequiresUpvalueIdentity`, `RequiresGCEffect`, `RequiresFFICallShape`, etc.

11. **Lines ~1537-1570: complete `CompileContract.SemanticAssumption`**
   - Add typed assumptions for:
     - callsite/target identity
     - result routes/frame effects
     - static region/module identity
     - closure/upvalue identity and epoch
     - metatable epoch + lookup path
     - operation/companion context
     - loop topology
     - close plan / outcome cause
     - GC effects/object epochs/finalizers
     - FFI ABI/call/callback/cdata ownership

12. **Lines ~1898-1920: complete `Stencil.PatchSource`**
   - Add typed sources:
     - `FromStaticRegion`, `FromStaticRegionInvocation`
     - `FromClosureIdentity`, `FromUpvalueIdentity`
     - `FromMetamethodLookupPath`, `FromMetatableEpoch`
     - `FromLuaOperation`
     - `FromLoopTopology`
     - `FromGCEffect`
     - `FromFFICallShape`, `FromFFICallback`, `FromCDataOwnership`

**Danger zones**
- `RegionDescriptor` field order changes intentionally; update every constructor and schema test.
- `ResultChannel`, `CallShape`, `CallTarget`, `CallFrameState`, `UpvalueRef` shape changes are breaking.
- Do not encode support status in ASDL fields.
- Do not add source `CALL` acceptance.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua`

**Goal**: Move executability to support gates, not semantic identity.

**Edits**
- Remove `SCAFFOLD_ONLY_REGION_KIND` terminology.
- Rename tables:
  - `EXECUTABLE_REGION_KIND` → `SUPPORTED_REGION_KIND_NOW`
  - scaffold helpers → unsupported semantic descriptor helpers.
- Update `descriptor(...)` and `descriptor_for_shape(...)` to construct 5-field `RegionDescriptor`.
- `is_executable_region(region, contract)` remains, but document it as lowerer support gate only.
- Remove `.executable` checks and all `scaffold_*` names.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_arity_model.lua`

**Goal**: Validate complete result routing and frame effects.

**Edits**
- Update constructors/validators for:
  - `ResultRouteKind`
  - `ResultDestination`
  - new `ResultChannel`
  - `ResultBundle`
  - `FrameEffect`
  - new `ArityNormalization`
- Preserve current executable helper behavior for current slice only.
- Rename “Phase 2” comments to “current support gate”.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_call_model.lua`

**Goal**: Enforce coherent call spine.

**Edits**
- Update validators for new `CallShape`, `CallTarget`, `ResolvedCallTarget`, `CallFrameState`.
- Add relationship validator:
  ```lua
  validate_call_spine(shape, target, args, results, frame)
  ```
  It must require all `call` fields share same `CallRef`.
- Remove mandatory metamethod validation for direct calls.
- Keep executable gate for current manual call-frame substrate, but rename comments away from “Phase 3”.

---

### Model files to update

#### `lua_rt_metatable_model.lua`
- Validate `MetatableEpoch`, `MetamethodSlot`, `MetamethodLookupStep`, `MetamethodLookupPath`, `MetamethodDispatch`.
- Ensure no-metamethod assumptions require epoch/path.

#### `lua_rt_close_model.lua`
- Replace hook validation with `ClosePlan`, `CloseAction`, `OutcomeCause`.

#### `lua_rt_gc_alloc_model.lua`
- Replace generic hook validation with `GCEffect`.
- Validate new proto/thread/upvalue collectables.

#### `lua_rt_closure_upvalue_model.lua`
- Validate `ProtoRef`, `ClosureIdentity`, `UpvalueIdentity`, storage kind, epochs.

#### `lua_rt_loop_model.lua`
- Validate `LoopTopology`, numeric/generic loop state + topology coherence.

#### `lua_rt_cdata_model.lua` / `lua_ffi_validate.lua`
- Validate `FFICallShape`, `FFICallbackEntry`, `CDataOwnershipTransition`.

#### `lua_rt_object_model.lua`
- Treat raw table access as one branch; validate table/metatable epoch/path products.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua`

**Goal**: Structural validation for complete LuaRT products.

**Edits**
- Add entry points for all new product families.
- Structural validation should accept well-formed but unsupported products.
- Relationship validation should catch:
  - mismatched `CallRef`
  - malformed metatable epoch/path
  - upvalue identity missing proto/frame/scope
  - result route missing destination

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_validate.lua`

**Goal**: Validate full semantic CFG/module shape.

**Edits**
- Remove `.executable` validation from `RegionDescriptor`.
- Add validation for:
  - static region bindings/invocations
  - `ModuleDescriptor`
  - duplicate region ids
  - continuation resolution
  - complete expression/obligation/guarantee nodes
- `M.module` should become meaningful, not shallow.

---

### `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua`

**Goal**: Validate typed assumptions and relationship invariants.

**Edits**
- Update `validate_region_descriptor` to 5-field descriptor.
- Add cases for every new `SemanticAssumption`.
- Add relationship checks:
  - call assumptions share `CallRef`
  - static invocation descriptor matches target
  - metatable absence includes epoch/path
  - upvalue assumption includes epoch/scope
- No semantic strings.

---

### `compile_contract_key.lua`, `stencil_key.lua`, `stencil_validate.lua`, `stencil_materialize.lua`

**Goal**: Preserve structural identity and loud rejection.

**Edits**
- Structural keying should naturally include new ASDL fields.
- Add comments/tests: no variant strings for semantic meaning.
- `stencil_materialize.lua` must reject unsupported new `PatchSource` constructors explicitly, not silently ignore them.

---

### `lua_src_to_lua_exec_lower.lua`

**Goal**: Migrate current lowering to new constructors without broadening support.

**Edits**
- Update region descriptor construction.
- Update arity/result-channel construction.
- Update call/close/GC/metatable reject diagnostics:
  - from `scaffold_only_region:*`
  - to `unsupported_semantic_region:*` or `unsupported_source_semantics:*`
- Keep `SUPPORTED_INSTR` unchanged.

---

### `lua_exec_to_moon_cfg_lower.lua`

**Goal**: Lower current executable slice; reject complete unsupported products cleanly.

**Edits**
- Update contract propagation for new assumption constructors.
- Update result channel/arity lowering for new `ResultBundle`.
- Replace scaffold-only expression rejections with unsupported semantic product diagnostics.
- Keep unsupported complete products rejected before MoonCFG emission.

---

### `moon_cfg_validate.lua` / `moon_cfg_emit.lua`

**Goal**: Preserve current MoonCFG support and guardrails.

**Edits**
- Update renamed runtime products only if current slice needs them.
- Keep forbidden strings unchanged.
- Keep `MoonCFG.EmitRegion`, `Continue`, `Exit` unsupported unless separately implemented.
- No VM dispatch, no helper calls.

---

## New Files

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_static_region_model.lua`
- Validates module/static region binding/invocation/continuation products.
- No inlining or execution implementation in this architecture cleanup.

### `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_operation_model.lua`
- Validates full operation/companion/metamethod context.

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_full_semantics_products.lua`
- Constructs well-formed non-executable full Lua semantic products and validates them structurally.

### `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_semantic_gates.lua`
- Proves unsupported complete products reject at lowering/emission boundaries.

---

## Order of Operations

1. Update ASDL completely first.
2. Update constructors/builders and direct test constructors.
3. Update arity/call models.
4. Update metatable/table/arithmetic/operation models.
5. Update closure/upvalue/GC/FFI/loop/close models.
6. Update LuaRT/LuaExec/CompileContract validators.
7. Update contract/stencil key/validation/materialization.
8. Update source lowering to new constructors while preserving unsupported rejects.
9. Update LuaExec→MoonCFG and MoonCFG validators/emitters.
10. Update schema and structural tests.
11. Update current regression tests.
12. Run verification.

---

## Testing Strategy

Run incrementally:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_full_semantics_products.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_semantic_gates.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_call.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
```

Optional:

```sh
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Expected:
- Architecture/product coverage expands.
- Current executable slice remains green.
- Source `CALL`/`TAILCALL` still reject.
- No corpus success increase is required.

---

## Structured Edit Plan Sidecar

Updated `wf-lua55-roadmap` sidecar to revision `r77`.

- Skipped obsolete old Phase 4 tasks `T037`–`T048`.
- Added new tasks `T049`–`T066`.
- Ready first task: `T049 Complete ASDL semantic architecture`.

---

## Pattern Memo

- ASDL describes full Lua semantics, not current implementation maturity.
- Executability belongs in model/lowerer gates, never semantic product identity.
- No `scaffold`, `phase`, or `executable` fields in ASDL meaning.
- No lowercase semantic strings/helper/protocol tags.
- Unsupported execution rejects loudly; structural semantic products may still validate.
- Do not broaden source opcode acceptance during architecture cleanup.

## Worker Output — 2026-06-06 20:33:03

## Completed
Implemented the corrected `wf-lua55-roadmap` complete ASDL architecture cleanup and finished all remaining edit-plan tasks `T049`–`T066`.

Key outcomes:
- ASDL now models complete Lua 5.5 semantic architecture up front.
- Removed `RegionDescriptor.executable` and scaffold/phase identity from semantic products.
- Added complete products for call spine, result routing, frame effects, metatable lookup paths, operations/companions, close plans, loop topology, GC effects/collectables, FFI calls/callbacks/ownership, static region identity, contracts, and stencil identities.
- Updated model/validator/lowering code for new product shapes.
- Preserved current executable slice and fail-closed source behavior.
- `CALL`/`TAILCALL` and other dynamic semantics still reject; no source opcode acceptance was broadened.
- Added structural full-semantics tests and semantic gate tests.

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl` - complete ASDL architecture cleanup.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_arity_model.lua` - result routes/bundles/frame effects.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_call_model.lua` - coherent `CallRef` call spine.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_metatable_model.lua` - metatable epoch/lookup path validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_operation_model.lua` - new operation/companion validator.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_close_model.lua` - close plan/outcome cause validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_gc_alloc_model.lua` - GC effects and collectables.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_closure_upvalue_model.lua` - closure/upvalue identity.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_loop_model.lua` - loop topology validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_cdata_model.lua` / `lua_ffi_validate.lua` - FFI/cdata products.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_rt_validate.lua` - new structural validators.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_region_model.lua` / `lua_exec_validate.lua` - region/module/static identity validation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/compile_contract_validate.lua` / `compile_contract_key.lua` / `stencil_key.lua` - typed contract/stencil identity.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_exec_lower.lua` - updated constructors and fail-closed diagnostics.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_exec_to_moon_cfg_lower.lua` - updated gates/contract propagation.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/moon_cfg_validate.lua` - guardrail comments retained/clarified.
- Tests updated/added under `experiments/lua_interpreter_vm/tests/`, including:
  - `test_spongejit_lua_compile_schema.lua`
  - `test_spongejit_lua_compile_full_semantics_products.lua`
  - `test_spongejit_lua_compile_semantic_gates.lua`
  - current slice regression tests.

## Verification
Passed:
```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_full_semantics_products.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_semantic_gates.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_arity.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_rt_call.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_static_regions.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_exec_pipeline.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_cfg.lua
cd experiments/lua_interpreter_vm/spongejit && make test
cd experiments/lua_interpreter_vm/spongejit && make test-completion
cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-corpus100
```

Corpus remained fail-closed: `37 ok / 104 rejected`, `31 successful windows`, `28 reps checked`.

## Notes
No blockers remaining. Structured edit plan now has no ready/todo/claimed tasks; obsolete T037–T048 remain skipped.
