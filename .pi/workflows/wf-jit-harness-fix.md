# Lua VM JIT harness completion 
Fix and complete experiments/lua_interpreter_vm JIT stencil harness based on design docs.
**Started**: 2026-05-25 11:00:29
---

## Scout Output — 2026-05-25 11:07:02

## Files Retrieved

1. `experiments/lua_interpreter_vm/LUA_STENCIL_HARNESS_DESIGN.md` (lines 1-1835) — canonical design. Important mismatches: expected modules include `awfy.lua`, `compile.lua`, `profile_dynamic.lua`; CLI expects `moonlift-jit-harness ... --flags`; pipeline requires real bytecode compilation, static/dynamic profiles, L0-L4, object mining, verification, benchmarking, export.
2. `experiments/lua_interpreter_vm/tools/jit_harness/README.md` (lines 1-217) — current claimed status. Says all 16 modules implemented, but design lists 17 modules and 3 are missing. Admits compilation/object mining/benchmarking/binary generation are mock placeholders.
3. `experiments/lua_interpreter_vm/tools/jit_harness/harness.lua` (lines 1-244) — top-level dispatcher. No direct script entrypoint; command set is incomplete vs design; pipeline continues despite compile/mining failures.
4. `experiments/lua_interpreter_vm/tools/jit_harness/corpus.lua` (lines 1-201) — AWFY discovery/normalization. Uses LuaJIT `load()` syntax checking instead of VM compiler; static AWFY fallback omits `main.lua`; no general corpus config/enumeration/read DB.
5. `experiments/lua_interpreter_vm/tools/jit_harness/profile_static.lua` (lines 1-269) — static profiler over Lua tables, not actual packed VM `Instr.word` arrays.
6. `experiments/lua_interpreter_vm/tools/jit_harness/fact_trace.lua` (lines 1-180) — Lua-value fact mock, not VM `TValue`/trace fact canonicalization.
7. `experiments/lua_interpreter_vm/tools/jit_harness/seed_l0.lua` (lines 1-254) — 27 hardcoded manual seed names. Does not load YAML/manual file path and does not emit full `L0SeedSpec` contract/fact/product shape.
8. `experiments/lua_interpreter_vm/tools/jit_harness/layer_closure.lua` (lines 1-319) — generates pair/triple/quad name combinations with simple budget gates. No contract composition, state/effect/fact validation, aliases, selected winners, or L2-L4 iteration.
9. `experiments/lua_interpreter_vm/tools/jit_harness/candidate_emit.lua` (lines 1-119) — emits trivial Moonlift `return 0i64` functions; not semantic opcode kernels.
10. `experiments/lua_interpreter_vm/tools/jit_harness/candidate_compile.lua` (lines 1-156) — invokes invalid `target/release/moonlift --emit-object` command; wrong cwd assumptions; ignores close status.
11. `experiments/lua_interpreter_vm/tools/jit_harness/object_mine.lua` (lines 1-184) — all mining data is randomized mock holes/relocs/clobbers.
12. `experiments/lua_interpreter_vm/tools/jit_harness/verify.lua` (lines 1-241) — shallow shape checks only; candidates without contracts pass valid.
13. `experiments/lua_interpreter_vm/tools/jit_harness/bench.lua` (lines 1-160) — randomized benchmark data; `#map` bug can produce `inf` average cycles.
14. `experiments/lua_interpreter_vm/tools/jit_harness/select.lua` (lines 1-222) — selection over candidates, not benchmarked verified products; selector is counts, not runtime table.
15. `experiments/lua_interpreter_vm/tools/jit_harness/export_runtime.lua` (lines 1-193) — exports all layer candidates, not selected verified stencils; C header has metadata but no bytes/fixups.
16. `experiments/lua_interpreter_vm/tools/jit_harness/report.lua` (lines 1-247) — simple reports; coverage/speed are placeholder.
17. `experiments/lua_interpreter_vm/tests/test_jit_harness.lua` (lines 1-185) — weak tests; errors are printed but do not fail process; only module loading/basic helpers tested.
18. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-120) — actual VM `Proto`/`Instr` shape: `Instr` is packed `word: u32`, `Proto.code` is `ptr(Instr)`.
19. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-180) — actual opcode numeric table, 0-84.
20. `experiments/lua_interpreter_vm/src/regions_compiler.lua` (lines 1-85) — actual Moonlift VM compiler entry region: `compile_lua_source_into`.
21. `experiments/lua_interpreter_vm/tests/test_parser_compile.lua` (lines 70-243) — concrete integration example for compiling source to `Proto`/`Instr` and running it through `vm_resume`.
22. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-154) — actual VM loop; no dynamic profiling/JIT instrumentation hooks.
23. `emit_object.lua` (lines 1-56) — working hosted object-emission CLI: `luajit emit_object.lua input.mlua -o output.o`.
24. `tests/test_stencil_codegen.lua` (lines 1-99) and `tests/test_elf_parser.lua` (lines 1-124) — stale tests referencing missing `experiments.lua_interpreter_vm.src.jit.stencil_codegen` and `...src.jit.elf_parser`.

## Key Code

### Design-required modules vs actual files

Design requires:

```text
tools/jit_harness/
  harness.lua
  corpus.lua
  awfy.lua
  compile.lua
  profile_static.lua
  profile_dynamic.lua
  ...
```

Actual `tools/jit_harness/` has no:

- `awfy.lua`
- `compile.lua`
- `profile_dynamic.lua`

Also no runtime `src/jit/` modules despite root tests expecting:

```lua
require("experiments.lua_interpreter_vm.src.jit.stencil_codegen")
require("experiments.lua_interpreter_vm.src.jit.elf_parser")
```

### CLI is not executable as advertised

`harness.lua` ends with:

```lua
return M
```

There is no:

```lua
os.exit(M.main(arg))
```

Observed:

```sh
cd experiments/lua_interpreter_vm
luajit tools/jit_harness/harness.lua help
# prints nothing, exits 0
```

The dispatcher itself only implements:

```lua
profile-awfy
seed-l0
build-l1
test
```

but design expects:

```text
profile-awfy
profile-corpus
seed-l0
build-layer
iterate-layers
verify-layer
bench-layer
export-runtime
report
clean
```

### AWFY profiling is host-LuaJIT syntax checking, not VM bytecode compilation

`corpus.lua`:

```lua
local chunk, err = load(content, file_path)
if not chunk then
    return nil, "syntax error: " .. tostring(err)
end
```

This rejects Lua 5.5 features before they ever reach the VM compiler. Observed:

```text
Found 33 AWFY test files
Normalized: 3
Errors: 30
```

The actual AWFY directory contains `main.lua`, but the no-lfs static fallback list omits it.

### Actual VM bytecode shape is packed `Instr.word`

`src/products.lua`:

```lua
local Instr = host.struct [[struct Instr word: u32 end]]
local Proto = host.struct [[struct Proto ... code: ptr(Instr); code_len: index; ... end]]
```

`tests/test_parser_compile.lua` decodes opcodes as:

```lua
local function op_of(i) return bit.band(i.word, 127) end
```

But `profile_static.lua` expects Lua-table instructions:

```lua
for i, instruction in ipairs(proto.code) do
    local op_name = instruction.op or instruction[1]
```

So current static profiling does not consume real VM `Proto.code`.

### Real compiler integration already exists in tests

`tests/test_parser_compile.lua` wraps `compile_lua_source_into`:

```lua
local compile_region = vm.regions_compiler.compile_lua_source_into
local wrapper = moon.func { compile_lua_source_into = compile_region } [[
compile_text(cu: ptr(CompileUnit), b: ptr(FuncBuilder), p: ptr(Proto),
             bytes: ptr(u8), n: index, code: ptr(Instr),
             locals: ptr(CompileLocal)) -> i32
    ...
end
]]
local compiled = assert(wrapper:compile())
```

This is the most concrete path for `tools/jit_harness/compile.lua`.

### Candidate compilation command is wrong

`candidate_compile.lua`:

```lua
local moonlift_cmd = string.format(
    "target/release/moonlift --emit-object -o '%s' '%s' 2>&1",
    obj_path, kernel_src
)
```

Observed from repo root:

```text
unknown option: --emit-object
unknown option: -o
```

Observed from `experiments/lua_interpreter_vm` cwd:

```text
target/release/moonlift: No such file or directory
```

Working object CLI is root `emit_object.lua`:

```sh
luajit emit_object.lua input.mlua -o output.o --module-name name
```

### Candidate emission source is invalid/trivial

`candidate_emit.lua` emits:

```lua
func stencil_probe(arg1: i64) -> i64
    return 0i64
end
```

Using the working object emitter, this fails because `0i64` is not accepted. Changing to `return 0` compiles. Also this emits no VM state, no `LuaThread`, no `Frame`, no holes, no side exits, no opcode semantics.

### Object mining and benchmarking are randomized placeholders

`object_mine.lua`:

```lua
for i = 1, math.random(1, 3) do ... holes ... end
for i = 1, math.random(0, 2) do ... relocs ... end
```

`bench.lua`:

```lua
cycles = math.random(100, 1000)
...
result.avg_cycles = math.floor(result.total_cycles / #result.corpus_runs)
```

`#result.corpus_runs` is `0` for string-keyed corpus maps. Observed:

```text
total_cycles=815 avg_cycles=inf
```

### Verification accepts almost everything

`verify.lua` only checks fields if present. Harness verifies `l1.candidates` directly, not mined objects:

```lua
local verification = M.verify.verify_candidate(cand, {})
if verification.valid then table.insert(verified_candidates, cand) end
```

Candidates with no contract/holes/relocs pass.

## Relationships

### Intended design flow

```text
AWFY/corpus source
  -> compile.lua -> LuaProtoBundle using VM bytecode
  -> profile_static.lua + profile_dynamic.lua
  -> seed_l0.lua
  -> layer_closure.lua
  -> candidate_emit.lua
  -> candidate_compile.lua
  -> object_mine.lua
  -> verify.lua
  -> bench.lua
  -> select.lua
  -> export_runtime.lua
```

### Current implemented flow

```text
corpus.lua
  -> host LuaJIT load() syntax check only
  -> no bytecode bundle
  -> seed_l0 uses manual seeds only
  -> layer_closure combines seed names
  -> candidate_emit emits trivial invalid/no-op functions
  -> candidate_compile invokes wrong command
  -> object_mine can mine failed compile result because it does not read object
  -> verify checks original candidate names, not mined code
  -> bench returns random data
  -> export writes all candidates as stencils
```

### Real integration anchors

- Source → VM bytecode: `src/regions_compiler.lua` + `tests/test_parser_compile.lua`.
- Opcode IDs: `src/constants.lua`.
- Packed instruction decode: `bit.band(instr.word, 127)` in `tests/test_parser_compile.lua`.
- Execution path for dynamic profiling: `src/vm_loop.lua` / `vm_resume`, but currently no profile counters or trace hooks.
- Object emission: root `emit_object.lua` or `moon.emit_object`, not `target/release/moonlift --emit-object`.
- Object parser/mining: missing under `experiments/lua_interpreter_vm/src/jit/`; stale tests expect it.

## Observations

### Concrete breakages vs design

1. Missing modules: `awfy.lua`, `compile.lua`, `profile_dynamic.lua`.
2. No direct CLI entrypoint; advertised `luajit tools/jit_harness/harness.lua test` does nothing.
3. CLI flags/design mismatch: no `--awfy-root`, `--out`, `--profile`, `--manual`, `--layer`, `iterate-layers`, `verify-layer`, `bench-layer`, `clean`.
4. AWFY discovery fallback is stale and non-validating; reports 33 known files and omits `main.lua`.
5. Corpus normalization rejects Lua 5.5 via LuaJIT parser instead of compiling through the Moonlift Lua VM compiler.
6. Static profile does not accept real packed VM `Proto`/`Instr`.
7. Dynamic profile is absent and VM has no trace/profile instrumentation.
8. Candidate emission is semantically empty and currently object-emission-invalid due `0i64`.
9. Candidate compilation uses a nonexistent/unsupported CLI mode and cwd-dependent binary path.
10. Object mining is random mock data and does not parse object bytes.
11. Verification does not verify semantics/equivalence/contracts unless optional fields happen to exist.
12. Benchmarking is random and has an `inf` average-cycle bug.
13. Selection/export consume all candidates, not selected verified benchmark winners.
14. Runtime integration products (`StencilPlan`, `ExecutableUnit`, `EntryCell`, selector table view) have no implementation under `src/`.
15. Tests do not fail the process on failed subtests and do not test direct CLI, object emission, object mining, profile-static-on-real-bytecode, dynamic profiling, export validity, or runtime consumption.

### High-priority fixes recommended

1. **Make the CLI real first**: add script entrypoint, package path setup, design-compatible commands/flags, and fail-fast status codes.
2. **Add `compile.lua` around `compile_lua_source_into`** using the pattern in `tests/test_parser_compile.lua`; produce a real `LuaProtoBundle` from VM `Proto.code`.
3. **Replace `corpus.lua` LuaJIT `load()` validation** with VM compiler compilation/rejects; fix AWFY discovery and include `main.lua`.
4. **Rewrite `profile_static.lua` to decode packed `Instr.word`** using opcode constants/reverse names and real operand fields.
5. **Add minimal `profile_dynamic.lua` plus VM instrumentation point** in/around `vm_loop` or `dispatch_instruction` for instruction counts, opcode windows, branch outcomes, and value facts.
6. **Fix candidate object path**: use `luajit emit_object.lua` or `moon.emit_object`, configurable repo root/tool path, and check process exit status/object freshness.
7. **Fix candidate emission to generate compilable source** before semantics work; remove `0i64`, then evolve from no-op to real VM-state stencil kernels.
8. **Implement deterministic object mining or wire to an ELF/Mach-O parser**; stop random holes/relocs/clobbers.
9. **Make verification consume mined candidates** and require contracts/expansions for candidates to pass.
10. **Replace benchmark randoms with real micro/AWFY runners**; fix map length bug immediately.
11. **Tighten tests**: fail nonzero on any subtest error; add tests for direct CLI, real source→Proto profile, candidate compile, object mine, no random output, and export artifact invariants.
12. **Fix portability basics**: shell-quote paths or avoid shell, avoid hardcoded `target/release`, JSON-escape all strings, and make outputs reproducible.
