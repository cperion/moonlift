# SpongeJIT LuaCompile — Agent Guidance

This file governs `experiments/lua_interpreter_vm/spongejit/`, especially
`lua_compile/` and `ssa_asdl/`.

## Current architecture

LuaCompile is a **PVM phase graph over ASDL products**. The maintained route is:

```text
PUC bytecode / full operand events
  -> LuaSrc.Window
runtime/foundry observations
  -> LuaFact.Evidence
LuaSrc.Window + LuaFact.Evidence
  -> LuaCompile.Unit
  -> LuaExec.Kernel or LuaExec.Module
  -> LalinCFG.Kernel + CompileContract.Contract
  -> Stencil typed backend artifacts
```

Accepted compilation goes through LuaExec then LalinCFG. There is no maintained
NormalForm/LalinOut/LuaSem/LuaNF pipeline.

## Source of truth

- `ssa_asdl/spongejit_lua_ssa.asdl` is the product vocabulary.
- `lua_compile/schema.lua` is the only module that loads textual ASDL.
- `lua_compile/init.lua` is the public LuaCompile facade.
- `lua_compile/lua_compile_to_lalin_kernel.lua` owns the public compile route.
- `experiments/lua_interpreter_vm/README.md` and
  `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` describe current
  direction.
- Workflow files under `.pi/workflows/` are historical working notes. Do not use
  them as architecture authority when they disagree with code/tests/docs.

## PVM discipline

A transformation between named ASDL product layers must be one of:

1. a named `pvm.phase` exported by its module, or
2. a local helper used only inside an existing phase.

Do not add free-floating compiler transformations that silently bypass the phase
boundary. If a new stage becomes architectural, make the implementation shape
honest in code; do not add tests whose only purpose is proving that an agent
remembered the design rule.

Useful audit command:

```sh
rg -n 'pvm\.phase' experiments/lua_interpreter_vm/spongejit/lua_compile
```

## Validators

Validators are **boundary contracts**, not the architecture.

Use validators only for invariants ASDL cannot encode, such as companion bytecode
ops, CFG jump-argument consistency, forbidden fallback strings, unresolved
relocations, and backend patch constraints.

Do not create validators that merely restate `pvm.classof(x) == T.Foo` unless a
boundary/test needs that exact assertion. A validator should either guard a phase
boundary, protect artifact ingestion/emission, or document a real non-ASDL
invariant in tests.

## Builders and helpers

`lua_compile/builders.lua` contains convenience constructors for ASDL values.
That is an API role, not an architectural boundary.

Builders and helper/model modules must not perform hidden lowering, fallback,
optimization, backend selection, or semantic recovery. Those decisions belong in
named phase implementations and must return typed ASDL products.

## Retired names and paths

Do not reintroduce these as maintained architecture:

- `LuaSem`, `LuaNF`, `LuaContract`, `LuaPlace`, `NormalForm`, `LalinOut`
- `lua_sem`, `lua_nf`, `lua_contract`, `lua_place`, `normal_form`,
  `lalin_cfg_closed`, `ssa2`
- protocol exits as successful lowering completion
- semantic `out_tag` / `out_event_kind` ABI as accepted execution
- external semantic fallback or handoff
- descriptor-bank compatibility names
- opcode-shaped stencil keys
- tests that treat compiler rejection as success for valid Lua behavior

Old shadow/harness material under `tools/` may be useful for corpus/profile data,
but it is not the current compiler architecture.

## Maintained tests

From `experiments/lua_interpreter_vm/spongejit/`:

```sh
make test                         # implemented-slice gate + no-old-imports
make test-lua-compile             # LuaCompile test suite
make test-lua-compile-foundry     # current foundry artifact path
make test-completion              # stricter opt-in completeness gate
```

Retired targets such as `stencils`, `bank`, `test-bank`, and old C/interpreter
probe targets intentionally fail. Do not make them pass by reviving the retired
runtime path.

## Change discipline

When changing LuaCompile architecture:

1. Update ASDL first if the product vocabulary changes.
2. Put transformations at named PVM phase boundaries.
3. Keep validators attached to concrete boundary/artifact invariants.
4. Update this `AGENTS.md` when the discipline or maintained route changes.
5. Add or update tests only for observable compiler behavior, product validity,
   diagnostics, or executable semantics — not for design-rule compliance by itself.
