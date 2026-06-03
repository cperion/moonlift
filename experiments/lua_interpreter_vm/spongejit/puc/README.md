# SpongeJIT PUC Integration Notes

PUC bytecode is a source input for SpongeJIT's explicit semantic compiler path.

```text
PUC bytecode windows
→ LuaSrc
→ LuaFact / LuaRT / LuaExec
→ MoonCFG
→ Stencil artifacts
→ Moonlift-native copy/patch materialization
```

PUC opcode fields must be preserved faithfully in `LuaSrc`. Opcode meaning is
then consumed by semantic lowering into explicit ASDL/MoonCFG structure.

PUC bytecode is also used for corpus validation and profiling through full
operand-bearing windows.
