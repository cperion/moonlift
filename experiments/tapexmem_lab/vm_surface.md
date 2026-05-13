# VM Surface: Moonlift-first mental model

Core claim:

1. **Memory layout schema** is first-class (`struct`, `view`, `ptr`, ABI facts).
2. **Machine protocol schema** is first-class (`union` continuations for all transitions).
3. Everything else (opcode bodies, fold rules, emit templates, patching details) is implementation.

## Two planes

- **Data plane**: iterator state, trace state, register file, arenas.
- **Control plane**: mode protocol + subprotocols.

A runtime step is valid iff it preserves data-plane invariants while following
one legal control-plane transition.

## In this lab

`five_mode_machine_regular.mlua` encodes this directly:

- top-level state schema (`IteratorState`, `TraceState`)
- mode protocolized regions
- split recording pipeline (`decode -> observe -> fold -> exec`)
- split compiling pipeline (`ra -> emit -> patch -> install`)
- split native pipeline (`enter -> run -> exit decode -> resume`)

This is the project compass for the LuaJIT-class build:
**one iterator machine, many protocolized submachines, shared typed state.**
