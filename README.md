# Moonlift

**A typed, jump-first compiled language that generates native code through Cranelift.**
**Authored through the Lua-owned DSL — metaprogrammed through LuaJIT — compiled to machine code.**

Moonlift compiles to native machine code. You author Moonlift in ordinary Lua
via `require("moonlift.dsl")` — Lua parses products, protocols, bodies, and fill
maps as table values; the DSL normalizes them into typed ASDL. The compiler
turns them into JIT-ed function pointers, relocatable `.o` files, or
`.so`/`.dylib` shared libraries.

The DSL works because Moonlift's semantics are exactly two structures:
products (data shapes) and sums (control alternatives). Lua arrays are
products. Lua record tables are fill maps. `[]` is the type slot. `.name`
is the declaration target. The design discipline became the syntax.

The `moonlift` binary is no longer built — Moonlift is a pure LuaJIT library.

```
.lua source
  → moon.use() injects DSL globals into _G
  → Lua tables with typed constructors
  → ASDL (interned, immutable, typed)
  → typecheck → lower → validate
  → Flatline binary wire format (v4)
  → Cranelift JIT / object emission
```

---

## Table of Contents

- [Why](#why)
- [At a Glance](#at-a-glance)
- [Quick Start](#quick-start)
- [The Language](#the-language)
- [Authoring — the Lua-owned DSL](#authoring--the-lua-owned-dsl)
- [Compilation Pipeline](#compilation-pipeline)
- [Artifact Emission](#artifact-emission)
- [LSP & Editor Support](#lsp--editor-support)
- [Standard Library](#standard-library)
- [Benchmarks](#benchmarks)
- [Repository Layout](#repository-layout)
- [Documentation](#documentation)
- [Testing](#testing)
- [Philosophy](#philosophy)

---

## Why

Most compiled languages force you to choose:

- **C/Rust/Zig**: full control, zero runtime, but limited metaprogramming and
  slow compile-edit cycles.
- **LuaJIT/Terra**: great metaprogramming through Lua, but Terra is unmaintained
  and its source language carries legacy design decisions.

Moonlift takes a different approach:

| Concern | Moonlift's answer |
|---|---|
| **Metaprogramming** | LuaJIT Lua. Real genericity lives in Lua, not in template syntax. |
| **Authoring** | Lua-owned DSL (`require("moonlift.dsl")`). Lua parses the shape, LLB hosts declaration/control heads, and Moonlift normalizes to ASDL. Header/impl split via callable stages. |
| **Native performance** | Cranelift JIT + object emission. Same backend tier as wasmtime. |
| **Control flow** | Typed blocks with explicit jump/yield/return. No hidden `next`, no implicit fallthrough. |
| **Semantics** | Everything meaningful is represented as ASDL (Algebraic Semi-structured Data Language) values. No hidden state in strings, callbacks, or mutable tables. |
| **Composability** | Region fragments with named continuation exits. Compose with `emit`. Dispatch with `switch`. |
| **Resource discipline** | Handles are durable identity, leases are temporary access, and `owned T` is explicit CFG discharge authority. No hidden destructors. |
| **Vectorization** | Explicit facts-based vectorization. No secret pattern matching on loop shapes. |
| **Tooling** | Full LSP: diagnostics, completion, hover, go-to-definition, references, rename, semantic tokens, folding. |

Moonlift is for people who want native performance with LuaJIT-level
metaprogramming, and who believe semantics should be data, not strings.

---

## At a Glance

### Authoring — the Lua-owned DSL

```lua
local moon = require("moonlift")
moon.use()                         -- inject DSL globals into _G

local m = module "Demo" {
  struct .Point { x [f32], y [f32] },

  fn .add { a [i32], b [i32] } [i32] {
    ret (a + b),
  },
}

-- Full pipeline
m:lower()               -- lowered program
m:compile()             -- JIT-compiled native code
m:emit_c_artifact()     -- C/header/support artifact
```

### Header / implementation split

```lua
-- math_header.lua — signatures, no bodies
require("moonlift").use()
return {
  fn .add { a [i32], b [i32] } [i32],
  fn .sub { a [i32], b [i32] } [i32],
}

-- math_impl.lua — fill the bodies
require("moonlift").use()
local header = require("math_header")
return module "Math" {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
```

### Factory — Lua is the generator

```lua
local function expect_byte(tag, byte, err_code)
    local name = "expect_" .. tag
    return function()
        return {
            region[name]
              { p [ptr [u8]], n [index], pos [index] }
              { ok { next [index] }, err { pos [index], code [i32] } }
              {
                entry .start {} {
                  when (pos:ge(n)) { jump .err { pos = pos, code = err_code } },
                  when (as [i32] (p[pos]):eq(byte)) { jump .ok { next = pos + 1 } },
                  jump .err { pos = pos, code = err_code },
                },
              },
        }
    end
end
```

---

## Quick Start

Moonlift is a **LuaJIT library**. Any LuaJIT process is the runtime host.

### Prerequisites

- LuaJIT with FFI support (`luajit -v` must show FFI)
- Rust toolchain (`rustup`, for building the Cranelift backend)

### Build the library

```bash
cargo build --release --lib     # produces libmoonlift.so
```

`libmoonlift.so` is the Cranelift JIT backend. LuaJIT loads it via FFI when
you `require("moonlift")`. No vendored LuaJIT, no submodules, no make —
just a Rust cdylib.

### Use it

```lua
-- Any LuaJIT process with lua/ on package.path and libmoonlift.so in system path
local moon = require("moonlift")
moon.use()
local m = module "Demo" {
  fn .add { a [i32], b [i32] } [i32] { ret (a + b) },
}
print(m:compile().add(3, 4))  -- 7, running as native machine code
```

### C emission (optional)

C backend tests need `libtcc`:

```bash
git submodule update --init deps/tinycc
make libtcc
```

Not needed for JIT compilation — only if you want the C artifact emitter.

### Quick validation

```bash
luajit tests/run.lua                              # Stable default suite
luajit tests/backend/test_back_add_i32.lua          # Bare Cranelift JIT path
luajit tests/frontend/test_dsl_lua_owned.lua        # DSL integration test
```

---

## The Language

Moonlift is small on purpose. The entire language fits in one statement:

> Monomorphic typed data + typed regions + explicit continuation exits
> + switch/emit/jump composition + semantic `as(T, value)` conversion.

The syntax keeps Moonlift's two categories visible: commas separate
product-shaped lists (fields, params, payload fields, fill maps), while `|`
separates semantic alternatives (union variants and region continuation exits).

### Types

```
void  bool
i8 i16 i32 i64    u8 u16 u32 u64
f32 f64           index
ptr(T)            view(T)
lease ptr(T)      lease view(T)
owned T
```

No source-level generics. Lua generates monomorphic concrete types.

Handles are nominal durable identities:

```lua
handle .SessionRef { invalid = 0 }
handle .VoiceRef { invalid = 0, domain = "VoiceStore", target = "VoiceState" }
```

`lease ptr(T)` and `lease view(T)` are temporary access facts granted by
typed protocols. `owned T` is mandatory discharge authority carried by CFG:
it must be consumed, returned, yielded, or transferred to another `owned`
parameter exactly once. It is not a destructor, not implicit access, and not
durable storage; `var owned T`, owned fields, owned aggregates, and
`owned ptr(T)` are rejected.

### Control flow

There is no `for`, `while`, `break`, or `continue`. The base
language is jump-first:

```
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

Every control-block path must terminate explicitly with `jump`, `yield`,
or `return`. No implicit fallthrough.

### Regions and fragments

Regions are typed control components with named continuation exits:

```lua
region .my_region { params ... } { exit_a { sig ... }, exit_b { sig ... } } {
    entry .start {} {
      emit .other_fragment { args ... } { out = exit_a }
    },
  }
```

Compose regions with `emit`. The caller decides what each exit means.

`emit` is also the ownership-carrying composition form. If an emitted region
returns ownership on a continuation, the filled target must declare a matching
`owned` parameter:

```lua
region .close_session
  { app [ptr [App]], s [owned [SessionRef]] }
  { closed, missing { s [owned [SessionRef]] } }

block .retry { s [owned [SessionRef]] } {
    emit .close_session { app, s } { closed = done, missing = retry }
}
```

Expression-style region calls reject continuation payloads containing leases or
`owned` values; use `emit` so the access or obligation stays in typed control
flow.

For higher-level composition, use the **region composition algebra** (`moonlift.region_compose`):

```lua
local C = moon.region_compose.new("grammar")
local digit = C:choice({digit_0, digit_1, digit_2, ...})
local number = C:plus(digit)       -- one or more digits
local int = C:seq({optional_sign, number})
-- All fragments emitted as native jump-first regions at generation time
```

### Switch dispatch

```lua
switch (tag) {
    case (0) { jump .value { delta = 1 } },
    case (1) { jump .value { delta = -1 } },
    default { jump .value { delta = 0 } },
}
```

No fallthrough. Explicit, verifiable control branches.

### Extern imports

Source-level extern declarations describe C-ABI imports:

```lua
extern .write { fd [i32], buf [ptr [u8]], count [index] } [index] { symbol = "write" }
extern .host_add7 { x [i32] } [i32] { symbol = "host_add7_impl" }
```

Moonlift code calls these names like ordinary functions. The Cranelift JIT
resolves normal process symbols through dynamic lookup. Object/shared-library
emission leaves externs as normal linker imports.

---

## Authoring — the Lua-owned DSL

All Moonlift is authored through the Lua-owned DSL (`require("moonlift")`).
Once `moon.use()` is called, DSL names (fn, i32, struct, etc.) become
available as Lua globals. No separate parser, no textual antiquote, no string
quotes. Values are values.

```lua
local moon = require("moonlift")
moon.use()

local m = module "Demo" {
  struct .Point { x [f32], y [f32] },

  fn .add { a [i32], b [i32] } [i32] {
    ret (a + b),
  },

  region .scan
    { p [ptr [u8]], n [i32], target [i32] }
    { hit { pos [i32] }, miss { pos [i32] } }
    {
      entry .loop { i [i32] (0) } {
        when (i:ge(n)) { jump .miss { pos = i } },
        when (as [i32] (p[i]):eq(target)) { jump .hit { pos = i } },
        jump .loop { i = i + 1 },
      },
    },
}

-- Pipeline: syntax → ast → typecheck → lower → jit / object / c
local lowered = m:lower()
local compiled = m:compile()
```

### Table shapes

The DSL assigns meaning to Lua table shapes:

| Lua syntax | DSL meaning |
|---|---|
| `.name` | fixed DSL token or declared name |
| `[expr]` | type slot, computed name, value insertion |
| `{ a, b, c }` | ordered product (params, fields, body, conts) |
| `{ k = v }` | unordered record (jump args, emit fills, options) |
| `name[T]` | typed name token |
| `name[T](init)` | typed name with initializer |

### Header / implementation split

`fn` and `region` declaration chains are **curried**. Supplying params and
result does not create the final declaration; it returns a **callable LLB
stage** waiting for the body. Export it from a header file, call it with a body
in an implementation file:

```lua
-- math_header.lua — declare signatures
return {
  fn .add { a [i32], b [i32] } [i32],
  fn .sub { a [i32], b [i32] } [i32],
}

-- math_impl.lua — fill bodies
local header = require("math_header")
return module "Math" {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
```

### Composition — spread and fragments

Program slicing is ordinary Lua table construction:

```lua
local xy = product { x [f32], y [f32] }

return module "M" {
  struct .Point { spread(xy), z [f32] },
  fn .tag_of { p [Point] } [u8] { ret (p.tag) },
}
```

### Contracts — `requires {...}`

Functions carry typed contract annotations via the `requires` keyword:

```lua
fn .read
  { buf [ptr [u8]], count [index] }
  [index]
  {
    requires { bounds (buf, count), noalias (buf) },
    ret (count),
  }
```

### Atomics

```lua
let .a [i32] (aload (i32, p))
astore (i32, p, v)
let .b [i32] (armw ("xchg", i32, p, v))
afence ()
```

### Low-level ASDL — the escape hatch

For tooling and AST construction that bypasses the DSL, `require("moonlift.ast")`
exposes direct ASDL constructors. Prefer the DSL for normal authoring.

### Bundle — output packaging

```lua
local bundle = dsl.bundle("MyModule")
bundle:pack(func_value)
local artifact = bundle:jit()  -- Cranelift JIT
-- or: bundle:emit_object() / bundle:emit_shared() / bundle:emit_c_artifact()
```

---

## Compilation Pipeline

### Single pipeline

```
moon.use() DSL source (.lua)
  │
  ├─► Lua table normalization ──► ASDL
  ├─► fill/expand for quoted carriers, direct values for DSL
  ├─► typecheck ──► typed + resolved module
  ├─► lower ──► flat BackCmd array
  ├─► validate ──► validation facts + rejects
  │
  └─► Flatline binary wire format (v4)
       │
       ├─► Cranelift JIT ──► function pointers
       └─► Cranelift object ──► .o relocatable object
```

### PVM: the phase framework

Every transformation is a PVM (Phase Virtual Machine) phase:

- **Input**: ASDL values (interned, immutable, structural identity)
- **Output**: ASDL values + facts/decisions/proofs/rejects
- **Caching**: memoized phase boundaries, recompile only changed subtrees
- **Execution**: triplets — iterators that map/filter/concat/flatmap over phase results

### Cranelift backend (Rust)

`src/lib.rs` provides the native backend:

- **JIT mode**: `moonlift.Jit` → `compile(program)` → `Artifact` with callable function pointers
- **Object mode**: `moonlift.compile_object(program, name)` → `ObjectArtifact` → `.o` bytes
- **Full ISA integration**: Cranelift 0.131.0 with native target detection

### Backend command set

The compilation target is a flat array of `BackCmd` variants:

```
CreateSig, DeclareData, DataInitZero, DataInitInt, ...
BeginFunc, CreateBlock, SwitchToBlock, SealBlock, ...
ConstInt, ConstFloat, Iadd, Isub, Imul, Fadd, ...
LoadInfo, StoreInfo, Memcpy, Memset, ...
Jump, BrIf, SwitchInt, CallValueDirect, ...
ReturnVoid, ReturnValue, Trap, FinishFunc
```

This is deliberately flat and verifiable. No nested IR, no hidden context.

---

## Artifact Emission

### Loading and compiling

```lua
local moon = require("moonlift")
moon.use()

-- Inline
local m = module "Demo" {
  fn .add { a [i32], b [i32] } [i32] { ret (a + b) },
}

-- From file
local chunk = moon.loadfile("demo.lua")
local m = chunk()

-- One-shot convenience
local m = require("moonlift.dsl").load(src, "demo.lua")

-- Cross-file: call moon.use() at the top of each .lua file
-- require("moonlift").use(); local header = require("math_header")

-- Compile: JIT, object, or shared library
local jit = m:compile()                     -- Cranelift JIT
local obj = m:lower()                       -- lowered program for object emission
local art = m:emit_c_artifact { c_path = "out.c" }  -- C blob + header
```

The linker path: `.lua` → moon.use() → DSL normalize → typecheck → lower → object → link plan → system linker → `.so`.

---

## LSP & Editor Support

Moonlift ships with a full Language Server Protocol implementation:

| Feature | Status |
|---|---|
| Diagnostics | Type errors, control rejects, semantic issues |
| Completion | Context-aware, typed identifiers, fragments |
| Hover | Type information, documentation |
| Go to definition | Jump-first region/fragment navigation |
| Find references | Cross-module reference resolution |
| Rename | Semantic rename across files |
| Semantic tokens | Syntax highlighting for editors |
| Signature help | Function/region continuation signatures |
| Folding ranges | Block/region folding |
| Code actions | Quick fixes for common issues |
| Inlay hints | Type and parameter hints |
| Document symbols | Module structure outline |
| Workspace apply | Multi-file editing support |

### Running the LSP

```bash
luajit lsp.lua
```

---

## Standard Library

Moonlift has two standard-library surfaces:

```text
lib/          small source-level libraries and region combinators
lua/llpvm/    official Low-Level PVM API for typed instruction languages
```

| Module | Description |
|---|---|
| `region_compose.lua` | **Region composition algebra.** PEG-style combinators (`seq`, `choice`, `star`, `plus`, `opt`, `pred`, `not_pred`) that generate native jump-first regions at Lua generation time. Exposed as `moonlift.region_compose` |
| `llpvm` | **Low-Level PVM.** PVM-style type authoring for operation worlds plus direct borrowed bytecode images, native handles, streams, phases, recordings, cache, C blob/header emission, and LuaJIT FFI runtime loading. |

Free-form Moonlift source is still the language: write `struct`, `handle`,
`region`, and `func` directly for bespoke kernels and system internals. LLPVM is
the standard-library solution when the task is to author a typed instruction
language and feed it to an incremental bytecode VM.

---

## Benchmarks

```sh
luajit benchmarks/bench_llpvm_image_load.lua          # LLPVM image loading benchmark
```

---

## Repository Layout

```
moonlift/
├── lua/moonlift/
│   ├── dsl/                    DSL authoring surface
│   ├── ast.lua                 Low-level ASDL node constructor API
│   ├── pvm.lua                 PVM: ASDL context, phases, triplets
│   ├── tree_typecheck.lua      Typecheck/name resolution
│   ├── tree_to_code.lua        Tree → normalized MoonCode
│   ├── code_to_back.lua        MoonCode → flat backend commands
│   ├── lower_to_back.lua       Kernel/Code lowering → backend commands
│   ├── frontend_pipeline.lua   Compilation pipeline orchestration
│   ├── back_jit.lua            Lua→Rust JIT FFI bridge (Flatline wire format)
│   ├── back_command_binary.lua Flatline v4 binary wire format encoder
│   ├── back_object.lua         Object file emission
│   ├── schema/                 ASDL source of truth (MoonCore, MoonType, ...)
│   ├── editor_*                LSP features
│   ├── lsp_*                   LSP protocol
│   └── region_compose.lua      Region composition algebra
├── lua/llpvm/                  Official Low-Level PVM API, bytecode builder, native C blob
├── src/                        Rust Cranelift backend
│   ├── lib.rs                  Full Cranelift backend (JIT + object emission)
│   ├── ffi.rs                  Lua FFI surface
│   └── embedded_hosted_lua.rs  Auto-generated by build.rs
├── build.rs                    Generates src/embedded_hosted_lua.rs at compile time
├── examples/
│   ├── json/                   C-backed JSON library showcase + stack benchmark
│   ├── protocols/              RESP parser example
│   └── terra_vs_mlua/          Terra comparison
├── benchmarks/                 Performance benchmarks
├── tests/                      Lua test suite (~100+ tests)
├── LANGUAGE_REFERENCE.md       Complete language reference
├── OWNED_CFG_DESIGN.md         Linear owned/handle/lease design
├── CONVENTIONS.md              Naming and file organization conventions
├── PVM_GUIDE.md                PVM ASDL/phase framework guide
├── LLPVM_GUIDE.md              Low-level PVM bytecode/native VM guide
├── COMPILER_PATTERN.md         Interactive software as compilers
├── BACK_WIRE_FORMAT.md         Flatline v4 binary wire format
├── explicit_programming.md     Explicit programming philosophy
└── README.md                   This file
```

---

## Documentation

| Document | Description |
|---|---|
| [`LANGUAGE_REFERENCE.md`](LANGUAGE_REFERENCE.md) | **Complete DSL language reference.** Types, modules, functions, control regions, fragments, contracts, atomics, host declarations, view ABI, vectorization. |
| [`lua/moonlift/dsl/LANGUAGE_REFERENCE.md`](lua/moonlift/dsl/LANGUAGE_REFERENCE.md) | **Lua-owned DSL reference.** Direct Lua-value authoring, structural `{}` products/protocols/bodies, no-antiquote metaprogramming, and natural program slicing without a second parser. |
| [`OWNED_CFG_DESIGN.md`](OWNED_CFG_DESIGN.md) | **Owned CFG resource discipline.** Final rules for `owned T`, handles, leases, emit transfer, disallowed aggregates, and diagnostics. |
| [`CONVENTIONS.md`](CONVENTIONS.md) | **Project conventions.** Naming, headers vs implementations, handles, generations, stores, and protocol naming. |
| [`BACK_WIRE_FORMAT.md`](BACK_WIRE_FORMAT.md) | **Flatline v4 binary wire format.** The stable ABI between the Lua frontend and the Rust Cranelift backend. |
| [`PVM_GUIDE.md`](PVM_GUIDE.md) | **Complete PVM guide.** ASDL contexts, structural update, recording-triplet phases, pull-driven evaluation, the triplet algebra. |
| [`LLPVM_GUIDE.md`](LLPVM_GUIDE.md) | **Complete LLPVM guide.** Low-level PVM doctrine, direct borrowed bytecode images, native VM handles, C blob ABI, phases, streams, recordings, and cache discipline. |
| [`COMPILER_PATTERN.md`](COMPILER_PATTERN.md) | **Interactive software as compilers.** The philosophy behind Moonlift's architecture: ASDL as the input language, live compilation, memoized phase boundaries. |
| [`explicit_programming.md`](explicit_programming.md) | **Explicit programming philosophy.** A guide to designing systems with typed data types and typed control protocols. |

---

## Testing

Moonlift has 100+ tests grouped by compiler boundary under `tests/`.

```bash
luajit tests/run.lua              # Stable default suite
luajit tests/run.lua frontend
luajit tests/run.lua backend
luajit tests/run.lua all          # Includes optional/retired suites
```

### Typechecker

```bash
luajit tests/code_ir/test_tree_typecheck.lua
```

### Backend (JIT)

```bash
luajit tests/backend/test_back_add_i32.lua
luajit tests/backend/test_back_call.lua
luajit tests/backend/test_back_memory_data.lua
```

### Object emission

```bash
luajit tests/backend/test_back_object_emit.lua
luajit tests/backend/test_back_object_full.lua
```

### Shared library emission

```bash
luajit tests/backend/test_back_shared_emit.lua
luajit tests/tooling/test_link_plan.lua
```

### DSL + integration tests

```bash
luajit tests/frontend/test_dsl_lua_owned.lua
```

### LSP tests

```bash
luajit tests/lsp/test_lsp_integrated.lua
luajit tests/editor/test_editor_completion_items.lua
luajit tests/editor/test_editor_hover.lua
luajit tests/editor/test_editor_semantic_tokens.lua
```

---

## Philosophy

Moonlift follows a few hard rules:

### 1. One pipeline, one ABI

One production compiler. One Flatline v4 binary wire format between the Lua
frontend and the Rust Cranelift backend. No parallel implementations — a single
battle-tested path from source to machine code.

### 2. ASDL is the architecture

If a distinction matters to compilation, it is represented as an ASDL value —
interned, immutable, with structural identity. Meaning must not hide in strings,
callbacks, mutable side tables, or backend-only IR. Everything downstream
consumes explicit facts.

### 3. Lua is the metaprogramming language

Moonlift source has no type parameters, no generics, no angle-bracket syntax.
LuaJIT Lua is where templates, specialization, and code generation live.
Moonlift receives the monomorphic result. This keeps the language small and the
metaprogramming powerful.

### 4. Jump-first control flow

There is no `for`, `while`, `break`, or `continue`. All loops are typed blocks
with explicit jump arguments and yield/return exits. Vectorization consumes
explicit facts, not parser guesses about loop shapes.

### 5. Every phase is explicit

Parse → typecheck → lower → validate → emit. Each phase produces explicit
facts, decisions, proofs, and rejects. Diagnostics are ASDL values consumed by
tools and LSP features — not format strings rediscovered from raw text.

### 5.5. Typed instruction languages use LLPVM

Free-form Moonlift remains the base layer for native kernels. When the design
task is "define a small typed operation language, stream it, phase it, cache it,
and run it through a portable runtime", the standard answer is LLPVM:

```text
PVM-style authoring
    -> operation worlds and streams
    -> borrowed bytecode image
    -> native VM / C blob
```

That keeps type authoring as rich as PVM while moving execution and ownership to
a portable native substrate.

### 6. Monomorphic compilation

Every Moonlift function, region, block, continuation, and value has concrete
types when it reaches typecheck/lowering. No runtime type dispatch in compiled
code.

### 7. Flat backend commands

The compilation target is a flat, verifiable array of `BackCmd` variants.
No nested IR trees, no mutable builder state, no hidden side effects.

---

*Moonlift: typed data, jump-first control, native code.*
