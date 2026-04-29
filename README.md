# Moonlift

Moonlift is a LuaJIT-hosted compiler/runtime built on the PVM discipline:

```text
ASDL source values
  -> PVM phases
  -> explicit facts / decisions / proofs / rejects
  -> flat Moon2Back commands
  -> JIT, .o, and shared-library artifacts
```

The language core is jump-first: loops are recognized patterns over typed
blocks, named jump arguments, and explicit `yield` / `return` exits.  Lua is the
build/staging language; emitted Moonlift object code is native and does not
bundle LuaJIT unless the user deliberately links Lua-facing runtime code.

## What to read

- `LANGUAGE_REFERENCE.md` — main user-facing Moonlift language reference.
- `SOURCE_GRAMMAR.md` — jump-first source grammar contract.
- `PVM_GUIDE.md` — how the PVM ASDL/phase/triplet framework works.
- `COMPILER_PATTERN.md` — philosophy behind interactive software as compilers.

## Repository layout

```text
lua/moonlift/      Lua compiler, PVM, ASDL, hosted API, LSP, linker phases
src/               Rust Cranelift backend and FFI surface
lib/               Moonlift standard-library sources
benchmarks/        performance benchmarks
tests/             Lua test suite
emit_object.lua    .mlua -> host-native .o
emit_shared.lua    .mlua -> .so/.dylib/.dll through Moon2Link
run_mlua.lua       run hosted .mlua files with LuaJIT staging
```

## Build

```bash
cargo build
```

The Lua side loads `./target/release/libmoonlift.*` first when present, then
`./target/debug/libmoonlift.*`.

## Quick validation

```bash
luajit tests/test_asdl_define.lua
cargo build
luajit tests/test_back_add_i32.lua
luajit tests/test_back_object_emit.lua
luajit tests/test_back_object_full.lua
luajit tests/test_link_plan.lua
luajit tests/test_back_shared_emit.lua
```

A broader smoke set:

```bash
luajit tests/test_parse_typecheck.lua
luajit tests/test_parse_kernels.lua
luajit tests/test_vec_kernel_plan.lua
luajit tests/test_host_quote.lua
luajit tests/test_json_library.lua
luajit tests/test_lsp_integrated.lua
```

## Artifact emission

Compile `.mlua` object code to a relocatable object:

```bash
luajit emit_object.lua examples/add.mlua -o build/add.o
```

Compile `.mlua` object code to a shared library through the ASDL linker layer:

```bash
luajit emit_shared.lua examples/add.mlua -o build/libadd.so
```

The shared path is:

```text
.mlua
  -> mlua_parse
  -> tree_typecheck
  -> tree_to_back
  -> back_validate
  -> back_object (.o)
  -> Moon2Link.LinkPlan
  -> LinkCommandPlan
  -> system linker
```

## Benchmarks

```bash
benchmarks/run_vs_terra.sh
benchmarks/run_vs_terra.sh quick
```

These compare Moonlift's jump-first kernels against equivalent Terra kernels.

## Core rule

If a distinction is meaningful, represent it as ASDL and lower it through a PVM
phase.  Do not hide compiler meaning in strings, context bags, side caches, or
backend-only IR.
