# Lalin

Lalin is a typed, jump-first compiled language embedded in LuaJIT.

Lua is the metaprogramming and authoring layer. Lalin receives the
monomorphic program after Lua has expanded templates, families, schemas, and
fragments. The runtime backend is LuaJIT bytecode copy-patch through the
LuaTrace stencil path.

```text
Lua DSL values
  -> LLB family capture
  -> LalinSyntax / LalinTree
  -> typecheck
  -> LalinCode facts, kernels, schedules
  -> LuaTrace stencil plans
  -> LuaJIT bytecode bank
  -> loaded LuaJIT module
  -> LuaJIT traces hot loops
```

There is no external native compiler toolchain in the main path.

## Build

```sh
make
```

`make` builds the repository-local LuaJIT archive if it is missing. Optional C
backend and stencil-bank experiments can still use the repo-local TinyCC build:

```sh
git submodule update --init --recursive
make libtcc
```

GCC or another C compiler is only a bank-generation dependency for native
copy-patch stencil banks. Runtime execution of the LuaTrace bytecode backend
does not require an external build system or a system C compiler.

## Use

```lua
local lalin = require("lalin")
lalin.use()

local add = fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}

local module = lalin.compile("demo", { add })
print(module.add(3, 4)) -- 7
```

For isolated evaluation without installing globals:

```lua
local lalin = require("lalin")

local module = lalin.loadstring([[
  local add = fn. add { a [i32], b [i32] } [i32] {
    ret (a + b),
  }
  return lalin.compile("demo", { add })
]], "demo.lua")()

print(module.add(3, 4))
```

## Tests

Tests are standalone LuaJIT scripts. The grouped runner is:

```sh
luajit tests/run.lua
luajit tests/run.lua frontend
luajit tests/run.lua code_ir
luajit tests/run.lua schema
luajit tests/run.lua pvm
```

Useful focused tests:

```sh
luajit tests/code_ir/test_luajit_bc_bank.lua
luajit tests/code_ir/test_luajit_backend_luatrace.lua
luajit tests/code_ir/test_stencil_luajit_provider.lua
luajit tests/pvm/test_compiler_driver.lua
```

## Architecture

- `lua/llb.lua` - the Lua Language Builder substrate: staged heads, fragments,
  managed `use`, origins, diagnostics, streams, and family algebra.
- `lua/llisle/` - LLB-native rewrite/rule language used by lowering passes.
- `lua/lalin/dsl/` - Lalin authoring surface: `fn`, `region`, `entry`,
  `jump`, `emit`, type heads, contracts, and fragments.
- `lua/lalin/schema/` - LalinSchema/ASDL family definitions for syntax,
  tree, code, stencil, LuaJIT, compiler, host, phase, and runtime objects.
- `lua/lalin/frontend_pipeline.lua` - frontend pipeline from DSL values to
  checked tree/code forms.
- `lua/lalin/luajit_backend.lua` - LuaTrace/LuaJIT backend facade.
- `lua/lalin/stencil_luajit.lua` - LuaTrace stencil lowering and bytecode
  bank materialization.
- `lua/lalin/luajit_bc_bank.lua` - LuaJIT bytecode copy-patch bank builder
  and loader.
- `lua/lalin/stencil_bank.lua` - native binary copy-patch stencil bank
  support for C-compiled stencils.
- `lua/lalin/c_backend.lua` and related modules - optional C emission path.
- `lua/llpvm/` - LLPVM family member and bytecode/task substrate.

## Backend Model

The canonical runtime backend is LuaTrace bytecode copy-patch:

```text
LalinCode
  -> kernel and schedule facts
  -> StencilArtifact[]
  -> LuaTrace plan
  -> LJBCStencilBank
  -> patched dumped LuaJIT bytecode
  -> loaded module table
```

Direct Lua source materialization was removed. Generated Lua source remains as
trusted stencil template input and bank provenance only; it is not a runtime
backend. The previous native FFI bridge and object-emission path were removed
from the active codebase.

The native C copy-patch path remains a separate stencil-bank realization. Its
job is to build a bank ahead of time and ship the bank, not to make users build
the compiler stack at runtime.

## Language Shape

Lalin is jump-first:

```lua
local scan = region. scan
  { p [ptr(u8)], n [i32], target [i32] }
  { hit { pos [i32] }, miss { pos [i32] } }
{
  entry. loop { i [i32] = i32(0) } {
    if_ (i >= n) { jump. miss { pos = i } },
    if_ (as(i32, p[i]) == target) { jump. hit { pos = i } },
    jump. loop { i = i + 1 },
  },
}
```

Regions are the shared control-machine algebra: products in, named continuation
protocols out. Streams, processes, parsers, phases, and functions are region
protocols or lowerings, not separate semantic universes.

## Documentation

- `docs/LANGUAGE_REFERENCE.md` - Lalin authoring reference.
- `docs/LLB_GUIDE.md` - LLB substrate and family guide.
- `docs/LLB_GENERIC_REGION_ALGEBRA.md` - shared region/control model.
- `docs/LUAJIT_BYTECODE_COPY_PATCH_BACKEND.md` - LuaTrace bytecode materializer.
- `docs/LUAJIT_LUATRACE_STENCIL_BACKEND.md` - LuaTrace stencil backend.
- `docs/LUAJIT_COPY_PATCH_STENCIL_BACKEND.md` - native binary stencil bank.
- `docs/LALIN_FAMILY_REFERENCE.md` - family composition rules.
- `docs/CONVENTIONS.md` - naming and file organization.

## Design Rules

1. Lua owns genericity and staging; Lalin receives monomorphic programs.
2. Products and protocols are explicit typed structures.
3. Regions compose control; functions seal a single-return ABI.
4. LLB families share symbols, types, fragments, origins, diagnostics, and
   region-shaped control semantics.
5. Meaning lives in schema values, not strings, side tables, or hidden callbacks.
6. Backend lowering consumes facts and schedules explicitly.
7. No silent fallback: unsupported shapes fail at the boundary that rejected them.
