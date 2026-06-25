# Lalin - Agent Guidance

Lalin is a typed, jump-first compiled language embedded in LuaJIT. Lua is the
metaprogramming layer; Lalin is the monomorphic program produced after Lua and
LLB families have expanded syntax, fragments, schemas, and rules.

The active runtime backend is LuaTrace materialized as LuaJIT bytecode
copy-patch. The old native FFI bridge and object-emission backend have been
removed.

## Build

```sh
make
```

`make` builds the repo-local LuaJIT archive if needed.

Optional C backend and native stencil-bank work may need:

```sh
git submodule update --init --recursive
make libtcc
```

GCC/TinyCC are bank-generation tools for C/native stencil work. They are not
runtime dependencies of the LuaTrace bytecode backend.

## Run DSL Files

```lua
local lalin = require("lalin")
lalin.use()

local add = fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}

local module = lalin.compile("demo", { add })
print(module.add(3, 4)) -- 7
```

Inline evaluation:

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

Cross-file Lua modules should call `require("lalin").use()` at the top if
they use global DSL names.

## Test

Tests are standalone LuaJIT scripts:

```sh
luajit tests/run.lua
luajit tests/run.lua frontend
luajit tests/run.lua code_ir
luajit tests/run.lua schema
luajit tests/run.lua pvm
```

Useful focused checks:

```sh
luajit tests/code_ir/test_luajit_bc_bank.lua
luajit tests/code_ir/test_luajit_backend_luatrace.lua
luajit tests/code_ir/test_stencil_luajit_provider.lua
luajit tests/pvm/test_compiler_driver.lua
luajit tests/pvm/test_compiler_package.lua
```

## Architecture

- `lua/llb.lua` - LLB substrate: staged heads, fragments, formatting, origins,
  diagnostics, streams, managed `use`, and family algebra.
- `lua/llisle/` - LLB-native relation/rule language used by lowering passes.
- `lua/lalin/dsl/` - Lalin authoring surface: `fn`, `region`, `entry`,
  `jump`, `emit`, types, contracts, and fragments.
- `lua/lalin/schema/` - schema family definitions for syntax, tree, code,
  stencil, LuaJIT, compiler, host, and phase objects.
- `lua/lalin/frontend_pipeline.lua` - DSL/tree/typecheck/code pipeline.
- `lua/lalin/luajit_backend.lua` - LuaTrace backend facade.
- `lua/lalin/stencil_luajit.lua` - LuaTrace stencil lowering and bytecode
  bank materialization.
- `lua/lalin/luajit_bc_bank.lua` - LuaJIT bytecode copy-patch bank builder
  and loader.
- `lua/lalin/stencil_bank.lua` - native binary copy-patch stencil bank.
- `lua/lalin/c_backend.lua` - optional C emission path.
- `lua/llpvm/` - LLPVM family member and bytecode/task substrate.

Compilation pipeline:

```text
DSL tables
  -> LalinSyntax ASDL
  -> LalinTree ASDL
  -> tree_typecheck
  -> tree_to_code
  -> code facts / kernels / schedules
  -> LuaTrace stencil artifacts
  -> LuaJIT bytecode bank
  -> loaded LuaJIT module
```

## Key Documentation

| Doc | Description |
|-----|-------------|
| `README.md` | Project overview, build, tests, backend model |
| `docs/LANGUAGE_REFERENCE.md` | Lalin DSL reference |
| `docs/LLB_GUIDE.md` | LLB substrate and family guide |
| `docs/LLB_GENERIC_REGION_ALGEBRA.md` | Shared region/control-machine model |
| `docs/LUAJIT_BYTECODE_COPY_PATCH_BACKEND.md` | LuaTrace bytecode bank backend |
| `docs/LUAJIT_LUATRACE_STENCIL_BACKEND.md` | LuaTrace stencil backend |
| `docs/LUAJIT_COPY_PATCH_STENCIL_BACKEND.md` | Native copy-patch stencil bank |
| `docs/LLPVM_GUIDE.md` | LLPVM guide |
| `docs/CONVENTIONS.md` | Naming and file organization |

## Language Cheatsheet

Types:

```lua
void  bool
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64 index
ptr(T)
view(T)
lease ptr(T)
owned(Handle)
handle(Name, u64, 0)
struct(Name, { a = T1, b = T2 })
union(Name, { ok = T, err = T })
func_type({ i32, i32 }, i32)
closure_type({ i32 }, i32)
```

Function:

```lua
local add = fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}
```

Region:

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

## Design Philosophy

- Co-author data products and control protocols.
- Regions are the shared control-machine algebra; streams, parsers, processes,
  phases, and functions are protocols or lowerings of that algebra.
- Compose with regions, seal with functions.
- Lua owns genericity; Lalin receives concrete monomorphic programs.
- Schema values carry meaning. Do not hide semantics in strings, callbacks, or
  side tables.
- LuaTrace bytecode is the default executable materialization.
- Native C copy-patch banks are generated ahead of time and shipped as bank data.
- Fail fast and loudly at unsupported backend boundaries.

## Non-Negotiable Rules

1. No Lalin source generics.
2. No angle-bracket type arguments.
3. Explicit schema meaning.
4. Monomorphic executable artifacts.
5. Jump-first control.
6. Every block path must terminate.
7. No fallthrough in switch.
8. Switch requires a default arm.
9. `owned T` must be discharged or transferred exactly once by typed CFG.
10. No owned aggregates, owned fields, `var owned T`, or `owned ptr(T)`.
11. Region calls cannot carry lease or owned continuation payloads; use `emit`.
12. Commas are for product-shaped lists; `|` is for semantic alternatives.
