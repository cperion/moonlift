# SponJIT Shadow Simulator

Non-executing economic simulator for SponJIT. It validates absorber economics before
building native codegen.

It models:

```text
all-residual interpreter plan
  -> mixed native/residual plans
  -> local absorption by residual pressure
  -> seam tax / projection cost
  -> oracle regret
  -> residual miss reports
  -> absorber proposals
```

## Test

```bash
luajit experiments/lua_interpreter_vm/tests/test_sponjit_shadow.lua
```

## Initial training corpus: AWFY + Moonlift

This is the default first training corpus:

```text
AWFY      numeric loops, algorithmic kernels, loop/table motifs
Moonlift  real compiler Lua: AST/ASDL traversal, modules, tables, strings, calls
```

Run:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua suite-initial \
  --awfy-root experiments/lua_interpreter_vm \
  --moonlift-root lua/moonlift \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_initial \
  --max-files 200 \
  --max-regions 50 \
  --fact-mode balanced
```

Outputs:

```text
experiments/lua_interpreter_vm/build/sponjit_shadow_initial/awfy/suite_report.md
experiments/lua_interpreter_vm/build/sponjit_shadow_initial/moonlift/suite_report.md
experiments/lua_interpreter_vm/build/sponjit_shadow_initial/combined/suite_report.md
experiments/lua_interpreter_vm/build/sponjit_shadow_initial/combined/miss_report.json
```

Then generate absorber proposals:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua propose \
  --miss-report experiments/lua_interpreter_vm/build/sponjit_shadow_initial/combined/miss_report.json \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_initial/proposals
```

Outputs:

```text
absorber_proposals.md
absorber_proposals.json
```

The proposal report includes an `SSA/NF` column. It is produced by the initial
Foundry SSA engine in `tools/sponjit_shadow/foundry_ssa.lua`: tuple candidates are
expanded into a VM-shaped SSA graph, facts specialize that graph, local SSA passes
simplify it, and the result gets a semantic normal form such as
`SELF MOVE CALL -> SELF_CALL` or `GETFIELD ADDI SETFIELD -> FIELD_ADDI_UPDATE`.
Runtime still sees only selected absorbers; SSA is the offline fact consumer, not
runtime compilation.

## Other commands

Synthetic suite:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua suite \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_smoke
```

AWFY only:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua suite-awfy \
  --awfy-root experiments/lua_interpreter_vm \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_awfy \
  --max-regions 50 \
  --fact-mode balanced
```

Profile arbitrary Lua source root with the PUC bytecode dumper:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua profile-root \
  --root lua/moonlift \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_moonlift_profile.json \
  --max-files 200
```

Run suite from an existing profile:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua suite-profile \
  --profile experiments/lua_interpreter_vm/build/sponjit_shadow_moonlift_profile.json \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_moonlift \
  --max-regions 50 \
  --fact-mode balanced
```

Sensitivity over fact mode and seam cost:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua sensitivity-awfy \
  --awfy-root experiments/lua_interpreter_vm \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_sensitivity \
  --max-regions 50
```

SSA form enumeration over tuple × fact combinations:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua enumerate-ssa \
  --awfy-root experiments/lua_interpreter_vm \
  --moonlift-root lua/moonlift \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_ssa_enum \
  --max-files 50 \
  --max-regions 20 \
  --max-windows 80 \
  --max-fact-combos 4096 \
  --fact-mode balanced
```

This implements the simplest foundry idea: take observed opcode windows, enumerate
all applicable fact combinations, run Foundry SSA, dedupe semantic normal forms, and
rank the resulting forms. Selected forms are the things that can become atoms in the
next recursive layer.

Recursive foundry training simulation:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua foundry-initial \
  --awfy-root experiments/lua_interpreter_vm \
  --moonlift-root lua/moonlift \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_foundry \
  --max-files 100 \
  --max-regions 30 \
  --max-windows 80 \
  --max-fact-combos 4096 \
  --layers 3 \
  --layer-cap 12 \
  --fact-mode balanced
```

This is a hypothetical AOT foundry economics run: selected absorber proposals become
abstract atoms for the next layer. It tests the fixed-arity/growing-basis idea before
real absorber code exists.

Time-series / phase-change modelling:

```bash
luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua timeseries \
  --workload phase_changing_method \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_timeseries_method \
  --observe-fraction 0.10

luajit experiments/lua_interpreter_vm/tools/sponjit_shadow/harness.lua timeseries \
  --workload phase_changing_numeric \
  --out experiments/lua_interpreter_vm/build/sponjit_shadow_timeseries_numeric \
  --observe-fraction 0.10
```

This models warmup and mode-cache effects that aggregate bytecode windows cannot show.

## Interpreting reports

Important fields:

```text
avg density              fraction of hot bytecode covered by native absorbers
avg speedup vs residual  estimated improvement over all-residual interpreter plan
avg regret               online/local plan cost divided by seam-aware oracle cost
mixed/full residual/full native
                         whether SponJIT is finding stable mixed plans
Top residual misses      next absorber opportunities by remaining pressure
Top neighborhoods        arity<=4 candidate starting points for the foundry
```

The numbers are not real speedups. They are architecture/economics signals under an
abstract cost model. Use sensitivity runs to reject results that only work under
fantasy costs.
