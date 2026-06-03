# SpongeJIT Measurement Notes

SpongeJIT measurements should target the current ASDL/MoonCFG/stencil pipeline.

Useful commands:

```sh
cd experiments/lua_interpreter_vm/spongejit
make test
make lua-compile-foundry
make test-lua-compile-corpus100
```

Current useful metrics:

```text
source windows examined
fact/evidence combinations attempted
LuaExec/MoonCFG products generated
Stencil templates generated
variant-key and bank-index sizes
patch-hole / reloc counts
materialization latency
native fast-path execution latency
corpus full-operand window coverage
```

Benchmarks should be named around explicit semantic CFGs, stencil bank
selection, Moonlift copy/patch materialization, and native fast-path execution.
