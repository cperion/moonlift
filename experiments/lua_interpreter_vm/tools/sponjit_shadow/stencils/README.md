## SponJIT Stencil Library

Precompiled native-code stencils for the copy-and-patch JIT materialization path.

### Files

- `stencil_abi.h` — C-side stencil ABI: function signatures, hole descriptor format,
  artifact template structure, residency convention, and the runtime materialization
  API (`sponjit_materialize`, `sponjit_patch`, `sponjit_free_artifact`).

### Model

Each SSA node (from `foundry_ssa.lua`) maps to exactly one stencil. The stencil
is a small C function compiled by GCC/Clang into position-independent machine code.
The build system extracts `.text` bytes and relocation records. The foundry
concatenates stencils into artifact templates with patch-hole metadata.

### Residency convention

```
rax  = current tagged TValue
rcx  = current unboxed i64 accumulator
rdx  = scratch
rbx  = Lua stack base
rsi  = constants table
rdi  = scratch (table/upvalue ptr)
```

### Implementation status

- [x] Stencil vocabulary designed (25 base stencils + 3 fused)
- [x] C ABI header with full signatures
- [x] Lua-side stencil model + lowering pass (`stencil_model.lua`)
- [x] Tests pass: SSA → stencil cover → template
- [ ] GCC-compiled stencil `.o` files
- [ ] Build system extraction of `.text` + relocs
- [ ] Runtime `sponjit_materialize` / `sponjit_patch` implementation
- [ ] Benchmark harness
