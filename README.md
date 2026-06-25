# Lalin

Lalin is a LuaJIT-hosted language family built around LLB.

LLB is the center of the system: it turns evaluated Lua values into language
objects with heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, and generic regions. Region is the shared control algebra
that composes the family. Lalin is the compiled member: it consumes LLB regions
and typed values, checks them, and lowers them through LuaTrace into LuaJIT
bytecode copy-patch artifacts.

```text
Lua source
  -> Lua values
  -> LLB family capture
  -> Lalin ASDL
  -> typecheck
  -> LalinCode facts
  -> LuaTrace stencil plans
  -> LuaJIT bytecode bank
  -> loaded module
```

There is no Cranelift/Rust runtime path in the active architecture.

## Quick Start

```lua
local lalin = require("lalin")
lalin.family.use()

local add = ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
  ll.ret (a + b),
}

local module = lalin.compile("demo", { add })
print(module.add(3, 4)) -- 7
```

For isolated loading:

```lua
local lalin = require("lalin")

local unit = lalin.loadstring([[
  return {
    ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
      ll.ret (a + b),
    },
  }
]], "demo.lua")()
```

## Build

```sh
make
```

`make` builds the repository-local LuaJIT archive if needed.

Optional C/native stencil work may need:

```sh
git submodule update --init --recursive
make libtcc
```

The default LuaTrace bytecode backend does not require Cargo, Rust, Cranelift,
or a system C compiler.

## Test

```sh
luajit tests/run.lua
```

Focused suites:

```sh
luajit tests/run.lua frontend
luajit tests/run.lua code_ir
luajit tests/run.lua schema
luajit tests/run.lua llpvm
luajit tests/run.lua ui
```

Useful backend checks:

```sh
luajit tests/code_ir/test_luajit_bc_bank.lua
luajit tests/code_ir/test_luajit_backend_luatrace.lua
luajit tests/code_ir/test_stencil_luajit_provider.lua
```

## Repository Map

```text
lua/llb.lua                  LLB language-workbench substrate
lua/lalin/                   Lalin compiler, schemas, DSL, and backend
lua/lalin/dsl/               authoring heads and namespace surface
lua/lalin/schema/            ASDL/schema definitions
lua/llpvm/                   low-level VM/task language member
lua/llisle/                  lowering/rewrite rule language
lua/ui/                      UI kernel and widgets
tests/                       standalone LuaJIT tests
benchmarks/                  measurement scripts
docs/                        consolidated documentation
```

## Language Shape

Lalin uses products for data that exists together and protocols for named
control outcomes.

```lua
region. scan
  { p [ll.ptr [ll.u8]], n [ll.index], target [ll.u8] }
  {
    hit { pos [ll.index] },
    miss { pos [ll.index] },
  }
  {
    ll.entry. loop { i [ll.index] } {
      ll.when (i :ge (n)) {
        ll.jump. miss { pos = i },
      },

      ll.when (p[i] :eq (target)) {
        ll.jump. hit { pos = i },
      },

      ll.jump. loop { i = i + 1 },
    },
  }
```

`region.` is the generic LLB control-machine head. Lalin consumes generic
regions as native typed CFG when the body uses Lalin block/jump vocabulary.

Internal composition normally uses `emit`, which splices a callee region into
the caller CFG. Use region `call` when you need a real frame for recursion,
debugging, profiling, or instrumentation; it lowers as a sealed function plus
an encoded exit union and dispatch back to named exits.

## Documentation

The docs are intentionally small:

- `docs/LLB_GUIDE.md` - central LLB workbench and region guide
- `docs/LANGUAGE_REFERENCE.md` - public Lalin family language reference
- `docs/ARCHITECTURE.md` - family, compiler, backend, and lowering architecture
- `docs/LLPVM_GUIDE.md` - low-level VM/task language member
- `docs/UI_GUIDE.md` - UI package guide
- `docs/CONVENTIONS.md` - naming, style, and repository conventions
- `docs/DESIGN_BIBLE.md` - long-form design philosophy

## Design Rules

- Lua owns genericity; Lalin receives monomorphic values.
- LLB is the workbench; Lalin is the compiled family member.
- Types are evaluated Lua values in `[]`.
- Heads are syntax; roles own normalization.
- Fragments are role-tagged reusable values.
- Regions model control; `emit` splices; region `call` gives frames/recursion.
- Functions are the sealed product-return ABI substrate.
- Pull-shaped work is a region protocol lowered through GPS.
- Schedules are policy, not semantics.
- Backend facts must be explicit ASDL.
- No compatibility shims for removed surfaces.
