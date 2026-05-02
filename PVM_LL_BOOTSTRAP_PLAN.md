# Moonlift PVM-LL Bootstrap Plan

This is a lightweight plan for bootstrapping faster Moonlift compiler pieces with
Moonlift itself.

The core idea is simple:

```text
current Moonlift/PVM implementation = reference implementation
PVM-LL implementation               = faster lowering/native implementation
shared ASDL schemas                 = common truth
A/B tests                           = guarantee they stay equivalent
```

This is not a rewrite and does not require a complicated accelerator platform up
front.  Two implementations are acceptable because they share the hard part: the
ASDL model.  When the compiler data model changes, both paths naturally follow
the same schema changes.  The important discipline is to test the lowerings
against each other continuously.

## Goal

Use the current LuaJIT/PVM Moonlift compiler to compile selected PVM-LL compiler
phases, then use those phases as faster implementations where useful.

```text
Moonlift0: current Lua/PVM compiler
    builds
Moonlift-LL pieces: .mlua/PVM-LL compiler phases
    checked against
Moonlift0 reference phases
```

The PVM implementation remains the readable/reference path.  The PVM-LL
implementation is allowed to be more direct and machine-shaped.

## Non-goals

- No whole-compiler rewrite.
- No need to eliminate Lua/PVM.
- No need for a huge artifact registry before the first useful result.
- No need to prove every phase is worth native lowering.
- No need to avoid duplicate implementations at all costs.

Duplication is fine when:

1. both implementations consume/produce the same ASDL values or equivalent ASDL
   facts/reports;
2. tests compare them directly;
3. the reference path stays available.

## Why this is manageable

The hard part of a compiler is usually the model: names, types, commands, facts,
issues, invariants.  In Moonlift that model is ASDL.

Both implementations share:

- `MoonCore`
- `MoonBack`
- `MoonType`
- host/schema definitions
- diagnostic/report types
- backend command model

Therefore most refactors hit the shared schema first.  After that, failures in
one lowering are usually obvious type/constructor/test failures rather than
silent divergence.

## Rule of development

For every PVM-LL phase, keep a reference PVM/Lua phase and an equality test:

```lua
local ref = Reference.phase(input)
local got = Fast.phase(input)
assert_same_report_or_facts(ref, got)
```

During development, it is acceptable to run both always.  Later, the fast path
can be selected by default for phases that have proven stable and faster.

## First target: `back_validate`

`back_validate` is still the best first target because it is already close to
this model.

Existing files:

- `lua/moonlift/back_validate.lua`
- `benchmarks/bench_compile_back_validate_ll.lua`
- `benchmarks/compare_compile_ll.sh`

Current shape:

```text
validate_pvm_cold(program)  -- reference/cold triplet-ish path
validate_ll(program)        -- flatter/direct path
```

Immediate target:

```text
validate_pvm_cold(program).issues == validate_ll(program).issues
```

Then evolve `validate_ll` toward real PVM-LL/native code when useful.

## Practical workflow

For each candidate phase:

1. Pick one phase boundary.
2. Keep the current PVM/Lua implementation as reference.
3. Write or extract a PVM-LL/direct implementation.
4. Add an A/B test over real compiler inputs.
5. Add a benchmark.
6. Use the fast implementation only when tests pass.

That is enough.

## Candidate phase template

Each migrated phase should document only:

```text
name
input ASDL type(s)
output ASDL type/report/facts
reference function
PVM-LL/direct function
comparator
benchmark
```

Example:

```text
name: back_validate
input: MoonBack.BackProgram
output: MoonBack.BackValidationReport
reference: validate_pvm_cold(program)
fast: validate_ll(program)
comparator: same ordered issues
benchmark: benchmarks/bench_compile_back_validate_ll.lua
```

## Test modes

A small mode switch is enough:

```text
off      use only reference implementation
auto     use fast implementation where enabled
verify   run both, compare, then return fast/reference result
```

This can be an environment variable later, for example:

```text
MOONLIFT_PVM_LL=off|auto|verify
```

No complex loader is required initially.  Start in-process.  Add artifact caching
only after a phase is worth compiling and reusing.

## Equality/comparison rules

Comparators should be explicit per phase.

For validation/report phases:

- same number of issues;
- same issue ASDL variant;
- same payload values;
- same order, unless the phase contract says order does not matter.

For fact streams:

- same facts;
- same order if downstream phases rely on order;
- otherwise compare as a multiset with clear duplicate handling.

For scalar phases:

- same value or same absence/failure result.

## When to lower a phase

Good candidates:

- hot in benchmarks;
- stable ASDL contract;
- flat command/fact loops;
- low boundary conversion cost;
- easy oracle comparison.

Bad candidates for now:

- rapidly changing semantics;
- phases dominated by parsing/string handling;
- phases where packing/unpacking would cost more than execution;
- phases without a clear comparator.

## Minimal milestones

### M1 — Keep `back_validate` A/B clean

- Ensure tests compare `validate_pvm_cold` and `validate_ll`.
- Benchmark them regularly.

### M2 — Add verify mode

- Make it easy to run both implementations from the same public entry point.
- Fail loudly on mismatch in developer/CI mode.

### M3 — Move one direct phase into real PVM-LL

- Use `.mlua` regions and `moonlift.pvm_ll` helpers where they remove boilerplate.
- Keep the same ASDL input/output contract.

### M4 — Compile/reuse if worth it

- If native/JIT compilation gives meaningful speedup, add a tiny artifact cache.
- If not, keep the direct Lua/flat path and move on.

## Risks and simple mitigations

### Divergence

Mitigation: A/B tests are permanent.

### Maintenance cost

Mitigation: only duplicate hot/stable phases.  Delete the fast path if it stops
paying for itself.

### Refactor friction

Mitigation: ASDL is shared, so schema refactors break both paths visibly.

### Premature infrastructure

Mitigation: do not build registries/caches/loaders until a compiled phase proves
useful.

## Current next actions

1. Strengthen `back_validate` comparison tests.
2. Add a small `verify` wrapper/mode for `validate`.
3. Keep measuring with:

```bash
luajit benchmarks/compare_compile_ll.sh
```

4. Pick the next phase only after `back_validate` gives clear lessons.

## Summary

The plan is intentionally small:

```text
share ASDL
keep reference PVM implementation
write faster PVM-LL/direct implementation
test them against each other
benchmark
use fast path only where it wins
```

That is enough to bootstrap Moonlift toward faster self-hosted compiler pieces
without turning the bootstrap itself into a large project.

## Task checklist

Below is the concrete task list, ordered by risk and effort.
Each task names the files involved.

### Phase 0 — Foundation (no native code, just clean comparison)

These tasks are pure-Lua cleanup to make A/B testing reliable before writing any native phase.

- [x] **0.1** — Add `validate_verify()` entry point in `lua/moonlift/back_validate.lua`.
  Runs both `validate_pvm_cold` and `validate_ll`, compares reports (same issue count,
  same issue ASDL variants, same payload), returns result.  Fails hard on mismatch.

  *Files*: `lua/moonlift/back_validate.lua`

- [x] **0.2** — Add `tests/test_back_validate_verify.lua`.
  Uses all existing `test_schema_back_validate` programs plus a few random programs
  through the full `parse → typecheck → tree_to_back` pipeline.  Calls `validate_verify`
  on each and asserts pass.

  *Files*: new `tests/test_back_validate_verify.lua`

- [x] **0.3** — Extend `benchmarks/bench_compile_back_validate_ll.lua` to report
  `verify` mode timings and print per-program report when `arg[1] == "verbose"`.

  *Files*: `benchmarks/bench_compile_back_validate_ll.lua`

- [x] **0.4** — Add to `benchmarks/compare_compile_ll.sh` a third column: `verify` mode.

  *Files*: `benchmarks/compare_compile_ll.sh`

### Phase 1 — `back_command_tape` as first compiled PVM-LL phase

The tape encoder is the lowest-risk native target:

- Input: `BackProgram` command stream (flat array).
- Output: byte buffer (flat bytes, no ASDL output values).
- Boundary cost is low: pack commands into an i32 array once, call native, unpack result.
- The reference implementation is `append_cmd_facts_flat` + the encode loop in `lua/moonlift/back_command_tape.lua`.

- [ ] **1.1** — Write `lua/moonlift/pvm_ll_tape.mlua`.
  A `.mlua` module with PVM-LL regions for tape encoding:
  - region that takes packed command array + index and appends to output buffer.
  - region that loops over command range and encodes each.
  Uses `pvmll.append_sink` for the output append pattern.

  *Files*: new `lua/moonlift/pvm_ll_tape.mlua`

- [ ] **1.2** — Add Lua-hosted packing/unpacking layer in `lua/moonlift/back_command_tape.lua`.
  New function `encode_native(program)` that:
  1. Packs `program.cmds` into a flat i32 array (command tag + payload).
  2. Calls the compiled PVM-LL tape module.
  3. Returns the same byte result as `encode(program)`.

  *Files*: `lua/moonlift/back_command_tape.lua`

- [ ] **1.3** — Add `tests/test_back_command_tape_native.lua`.
  Compiles the PVM-LL tape module, A/B tests `encode(program) == encode_native(program)`
  on all programs from `test_schema_back_validate` and a few random ones.

  *Files*: new `tests/test_back_command_tape_native.lua`

- [ ] **1.4** — Add benchmark: `benchmarks/bench_tape_encode.lua`.
  Measures `encode` vs `encode_native` on programs of varying sizes.

  *Files*: new `benchmarks/bench_tape_encode.lua`

### Phase 2 — `back_validate` as compiled PVM-LL phase

This is the main target.  The current flat path (`validate_ll`) is already a
linear scan over facts followed by a linear validation pass.  The goal is to
compile that whole scan into a native region.

The data boundary is harder here because the output is ASDL `BackIssue` values.
The strategy is:

1. Pack `BackProgram.cmds` into a compact i32 array (reuse the tape packing).
2. Run native validation on the packed array.
3. Validation issues are reported as compact error codes + payload.
4. Unpack to ASDL `BackIssue` values for the report.

- [ ] **2.1** — Write `lua/moonlift/pvm_ll_validate.mlua`.
  Native PVM-LL validation regions that work on packed command arrays.
  Structure mirrors `validate_program_impl`:
  - First pass: collect facts (defined/used sets) into bit-sets or counter arrays.
  - Second pass: check each command against the collected facts.
  - Issues encoded as compact (index, issue_kind, payload...) into a sink.

  *Files*: new `lua/moonlift/pvm_ll_validate.mlua`

- [ ] **2.2** — Add `validate_native(program)` entry point in `lua/moonlift/back_validate.lua`.
  Packs program, calls compiled PVM-LL region, unpacks issues to ASDL report.

  *Files*: `lua/moonlift/back_validate.lua`

- [ ] **2.3** — Add `tests/test_back_validate_native.lua`.
  A/B tests `validate_native(program) == validate(program)` on:
  - All programs from `test_schema_back_validate`
  - All programs from `test_back_validate`
  - Random programs through full pipeline

  *Files*: new `tests/test_back_validate_native.lua`

- [ ] **2.4** — Extend `benchmarks/compare_compile_ll.sh` to include native column.

  *Files*: `benchmarks/compare_compile_ll.sh`

### Phase 3 — `tree_to_back` phases (scalar shape first)

`tree_to_back` produces most of the compile time after parsing (see
`profile_compile.lua`).  The core phases are:

- `expr_to_back` — lowers typed Tree expressions to Back commands
- `stmt_to_back` — lowers typed Tree statements
- `func_to_back` — lowers typed Tree functions
- `module_to_back` — lowers typed Tree modules

Before these can be native, the Tree ASDL values need a compact representation.
This is the biggest data-ABI task.

- [ ] **3.1** — Define a compact Tree packing format.
  Each Tree node (Expr, Stmt, Place, Type, etc.) gets a small integer tag + field
  pack.  Fields reference other nodes by index.  The packer walks the ASDL tree
  once and produces a flat array + index lookup.  The unpacker is not needed
  (output goes directly to BackProgram commands).

  *Files*: new `lua/moonlift/tree_pack.lua`

- [ ] **3.2** — Add `tests/test_tree_pack.lua`.
  Round-trip validation: pack → check invariants, not unpack (output is Back).
  Compare packed structure against original ASDL via a field-verifying checker.

  *Files*: new `tests/test_tree_pack.lua`

- [ ] **3.3** — Write native `expr_to_back` in `.mlua`.
  Uses packed Tree nodes, emits Back commands into a sink.

  *Files*: new `lua/moonlift/pvm_ll_expr_to_back.mlua`

- [ ] **3.4** — A/B test native `expr_to_back` against reference.
  Same input module → same BackProgram command stream (structural equality).

  *Files*: new `tests/test_tree_to_back_native.lua`

- [ ] **3.5** — Continue with `stmt_to_back`, `func_to_back`, `module_to_back`.
  Same pattern: pack Tree, call native region, compare BackProgram output.

  *Files*: new `lua/moonlift/pvm_ll_stmt_to_back.mlua`, etc.

- [ ] **3.6** — Benchmark full pipeline with native `tree_to_back`.

  *Files*: extend `benchmarks/profile_compile.lua`

### Phase 4 — `tree_typecheck` phases (deferred)

Type checking also shows in `profile_compile.lua`.  Same data-ABI challenge as
`tree_to_back` — needs packed Tree representation.  Defer until Phase 3 proves
the packing and native patterns work.

- [ ] **4.1** — Write native `expr_type` in `.mlua` (scalar type inference).
- [ ] **4.2** — A/B test against reference `expr_type`.
- [ ] **4.3** — Continue with `stmt_type`, `func_type`, `module_type`.
- [ ] **4.4** — Benchmark full pipeline with native typecheck.

### Phase Ops — Infrastructure & polish

These can happen at any point once a native phase exists.

- [ ] **Ops.1** — Define `MOONLIFT_PVM_LL` env var with modes: `off`, `auto`, `verify`.
  `off`: use reference only.
  `auto`: use native when compiled artifact is present and hash matches.
  `verify`: run both, compare, return reference result with diagnostics on mismatch.

  *Files*: new `lua/moonlift/pvm_ll_mode.lua`

- [ ] **Ops.2** — Add per-phase A/B report at the end of compilation.
  When in `verify` mode, print a summary line for each phase: `phase-name: match/diverged, ref=0.42ms native=0.11ms speedup=3.8x`.

  *Files*: new `lua/moonlift/pvm_ll_report.lua`

- [ ] **Ops.3** — Add `make check-pvm-ll` target or script that runs all native A/B tests.

  *Files*: new `scripts/check_pvm_ll.sh`

- [ ] **Ops.4** — Artifact cache for compiled `.mlua` modules.
  Only after Phase 1 or 2 proves a native phase is worth reusing.
  Cache compiled `.so` by source hash in `.moonlift-cache/pvm-ll/`.

  *Files*: new `lua/moonlift/pvm_ll_cache.lua`

### Task ordering summary

```text
Phase 0 (foundation)
  ├── 0.1   verify entry (back_validate.lua)
  ├── 0.2   verify test
  ├── 0.3   verbose benchmark
  └── 0.4   verify column in compare script

Phase 1 (tape encoder — lowest risk)
  ├── 1.1   pvm_ll_tape.mlua
  ├── 1.2   encode_native entry
  ├── 1.3   A/B test
  └── 1.4   benchmark

Phase 2 (back_validate native)
  ├── 2.1   pvm_ll_validate.mlua
  ├── 2.2   validate_native entry
  ├── 2.3   A/B test
  └── 2.4   benchmark column

Phase 3 (tree_to_back native)
  ├── 3.1   tree_pack.lua
  ├── 3.2   pack test
  ├── 3.3   expr_to_back native
  ├── 3.4   A/B test
  ├── 3.5   stmt/func/module
  └── 3.6   full pipeline benchmark

Phase 4 (tree_typecheck native, deferred)
  └── 4.x   same pattern as Phase 3

Ops (any time)
  ├── Ops.1  mode switch
  ├── Ops.2  per-phase report
  ├── Ops.3  check-pvm-ll script
  └── Ops.4  artifact cache
```
