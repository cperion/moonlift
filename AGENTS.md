# Lalin - Agent Guidance

Lalin is a LuaJIT-hosted dialect of the LLBL language. Lua is the
metaprogramming layer. LLBL is the central extensible language workbench and
bootstrap language: heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, dialect extension, and generic regions. Lalin is the compiled
language dialect that lowers typed programs into LuaJIT copy+residual artifacts.

LLBL bootstraps itself in plain Lua. `lua/llbl.lua` is the stage-0 kernel;
`lua/llbl/bootstrap.lua` defines the stage-1 `llbl` dialect and installs the
public `llbl.grammar` facade. The preserved stage-0 grammar is
`llbl.kernel.grammar`.

The bare `llbl` member is the identity of language composition. It provides shared
mechanics: source/generated symbols, origins, diagnostics, fragments, regions,
formatting docs, and language-level symbol bindings. Dialects own semantic
meaning.

The active fast backend is `copy_patch_mc` bank stencils plus TCC residual glue.
`copy_patch_bc` is the LuaTrace/LuaJIT bytecode artifact path. `lalin.compile`
currently defaults to bytecode copy-patch; emitted LuaJIT artifacts default to
machine-code copy+residual. The old Cranelift/Rust runtime path is not part of
the current architecture.

## Build

```sh
make
```

Optional C/native stencil work may need:

```sh
git submodule update --init --recursive
make libtcc
```

## Run DSL Files

```lua
local lalin = require("lalin")
lalin.language.use()

local add = lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}

local module = lalin.compile("demo", { add })
print(module.add(3, 4)) -- 7
```

Inline evaluation:

```lua
local lalin = require("lalin")

local unit = lalin.loadstring([[
  return {
    lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
      lln.ret (a + b),
    },
  }
]], "demo.lua")()
```

## Test

Tests are standalone LuaJIT scripts:

```sh
luajit tests/run.lua
luajit tests/run.lua frontend
luajit tests/run.lua code_ir
luajit tests/run.lua schema
luajit tests/run.lua llpvm
```

Useful focused checks:

```sh
luajit tests/code_ir/test_copy_patch_bc.lua
luajit tests/code_ir/test_luajit_backend_bc.lua
luajit tests/code_ir/test_copy_patch_luatrace.lua
luajit tests/pvm/test_compiler_driver.lua
```

## Architecture

```text
Lua source
  -> Lua values
  -> LLBL language capture
  -> Lalin ASDL
  -> typecheck
  -> LalinCode facts
  -> kernel and schedule facts
  -> LuaTrace stencil plans or C stencil plans
  -> LuaJIT copy+residual artifact
  -> loaded LuaJIT module
```

Key files:

```text
lua/llbl.lua                  LLBL extensible language workbench substrate
lua/lalin/dsl/               Lalin authoring heads
lua/lalin/schema/            ASDL/schema definitions
lua/lalin/frontend_pipeline.lua
                             DSL/tree/typecheck/code pipeline
lua/lalin/luajit_backend.lua LuaTrace/LuaJIT backend facade
lua/lalin/copy_patch_bc.lua LuaJIT BC bank
lua/llpvm/                   LLPVM member
```

## Key Docs

```text
docs/LLBL_GUIDE.md            central LLBL workbench and region guide
docs/LANGUAGE_REFERENCE.md   public Lalin language reference
docs/ARCHITECTURE.md         language, compiler, backend, and lowering architecture
docs/LLPVM_GUIDE.md          low-level VM/task language member
docs/UI_GUIDE.md             UI package guide
docs/CONVENTIONS.md          naming, style, and repository conventions
docs/DESIGN_BIBLE.md         long-form design philosophy
```

## Non-Negotiable Rules

1. LLBL is the workbench; Lalin is the compiled language member.
2. Lua owns genericity; Lalin receives monomorphic values.
3. Types are evaluated Lua values in `[]`.
4. No angle-bracket type arguments.
5. No source-level `for`, `while`, `break`, or `continue`.
6. Every block path terminates.
7. Switches require a default arm and have no fallthrough.
8. `region.` is generic LLBL control syntax; Lalin consumes it.
9. Pull-shaped work is a region protocol lowered through GPS.
10. Backend facts must be explicit ASDL.
11. No compatibility shims for removed surfaces.

## Working Notes

Use `rg` for searches. Do not revert user changes. Ignore `museum/gps.lua`
unless the user explicitly asks to work on it.
