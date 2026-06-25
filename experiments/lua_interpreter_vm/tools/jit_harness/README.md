# Lua Bytecode / Corpus Harness Notes

This directory contains bytecode and corpus utilities that may feed SpongeJIT
source-window discovery and profiling.

Current SpongeJIT path:

```text
PUC bytecode windows
→ LuaSrc + LuaFact
→ LuaRT / LuaExec
→ LalinCFG
→ Stencil artifacts
→ Lalin-native selection and copy/patch materialization
```

Use the harness only as a source of bytecode windows, profiles, or comparison
measurements. It is not the architecture source for semantic lowering,
stencil-bank layout, or runtime materialization.

Current checks:

```sh
cd experiments/lua_interpreter_vm/spongejit
make test
make lua-compile-foundry
make test-lua-compile-corpus100
```
