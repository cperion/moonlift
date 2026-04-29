# Moonlift

Moonlift is a LuaJIT-hosted compiler/runtime built on the PVM discipline:

```text
ASDL source values
  -> PVM phases
  -> explicit facts / decisions / proofs / rejects
  -> flat backend commands
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
examples/          runnable hosted Moonlift examples
tests/             Lua test suite
tests/fixtures/    non-runnable editor/LSP/demo fixtures
emit_object.lua    .mlua -> host-native .o
emit_shared.lua    .mlua -> .so/.dylib/.dll through the ASDL linker layer
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

## Schema-as-data authoring

Moonlift is moving away from parser-text-first ASDL authoring. New schema and
compiler wiring work should use Lua-hosted builders that produce canonical ASDL
values:

```lua
local A = require("moonlift.asdl_builder").Define(T)

local schema = A.schema {
  A.module "MoonCore" {
    A.product "Id" {
      A.field "text" "string",
      A.unique,
    },
    A.sum "Scalar" {
      A.variant "ScalarI32",
      A.variant "ScalarI64",
    },
  },
}
```

The table-builder surface is syntax only; the consumed values are
`MoonAsdl.Schema` / `MoonPhase.Package` ASDL values. The current bridge emits
legacy ASDL text for `T:Define`, and later direct context construction can
consume the same data without changing authoring syntax.

The clean schema source now lives under `lua/moonlift/schema/` as full
`MoonCore` / `MoonBack` / `MoonType` / ... builder modules. These are the
schema-as-data source of truth; historical compatibility names are not used in
this clean schema. `tests/test_schema_core.lua` validates the full clean schema
can define a context and construct representative core/type/backend values.

## PVM-on-Moonlift lowering direction

The native PVM path lowers phase semantics to ordinary Moonlift values, not to
an extra low-level VM and not through string-first code generation.
`MoonAsdl.Schema` products/sums become hosted Moonlift module values containing
structs and tagged unions with typed IDs/arenas. Lowerable PVM phase bodies are
authored with Lua builders that produce `MoonPvmSurface` ASDL values; the region
lowerer turns `once`, `empty`, `concat`, phase calls, and handler dispatch into
hosted Moonlift `RegionFragValue` / `MoonTree` values using typed jumps and
`emit(value; resume)` continuations. `.mlua` files remain a valid authoring
surface, but generated compiler structure should be Moonlift values first.

Initial executable-design modules:

```text
lua/moonlift/schema/pvm_surface.lua
lua/moonlift/pvm_surface_model.lua
lua/moonlift/pvm_surface_builder.lua
lua/moonlift/pvm_surface_region_values.lua
lua/moonlift/pvm_surface_schema_values.lua
lua/moonlift/pvm_surface_union_values.lua
lua/moonlift/pvm_surface_cache_values.lua
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
  -> linker plan
  -> linker command plan
  -> system linker
```

## Benchmarks

```bash
benchmarks/run_vs_terra.sh
benchmarks/run_vs_terra.sh quick
```

Back-validation now defaults to the flat fact loop used for build-time LL-PVM
work. Compare the old triplet command-fact path against the default flat path
with:

```bash
luajit benchmarks/bench_compile_back_validate_ll.lua
benchmarks/compare_compile_ll.sh
```

These compare Moonlift's jump-first kernels against equivalent Terra kernels.

## Core rule

If a distinction is meaningful, represent it as ASDL and lower it through a PVM
phase.  Do not hide compiler meaning in strings, context bags, side caches, or
backend-only IR.
