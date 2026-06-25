# Shadow Stencil Tool Notes

This directory contains exploratory stencil tooling for shadow/profile analysis.
It is not a source of current SpongeJIT contracts.

Current contracts live in:

- `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md`
- `experiments/lua_interpreter_vm/SPONJIT_LALIN_COPY_PATCH_DESIGN.md`
- `experiments/lua_interpreter_vm/SPONJIT_FFI_DESIGN.md`
- `experiments/lua_interpreter_vm/SPONJIT_GC_DESIGN.md`
- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`

Stencil artifacts in the current design derive from explicit ASDL semantic CFGs,
contracts, and target layout. Shadow tool names or C sketches here must not be
used as implementation contracts.
