# Moonlift

**A typed, jump-first compiled language embedded in LuaJIT that generates native code through Cranelift.**

Moonlift compiles to machine code. You write `.mlua` files — Lua with hosted
typed islands — and Moonlift turns them into JIT-ed function pointers, relocatable
`.o` files, or `.so`/`.dylib` shared libraries. Lua is the metaprogramming
language; Moonlift is the monomorphic native output. No strings, no templating
hacks, no extra VM.

---

## Table of Contents

- [Why](#why)
- [At a Glance](#at-a-glance)
- [Quick Start](#quick-start)
- [The Language](#the-language)
- [Metaprogramming Model](#metaprogramming-model)
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
| **Native performance** | Cranelift JIT + object emission. Same backend tier as wasmtime. |
| **Control flow** | Typed blocks with explicit jump/yield/return. No hidden `next`, no implicit fallthrough. |
| **Semantics** | Everything meaningful is represented as ASDL (Algebraic Semi-structured Data Language) values. No hidden state in strings, callbacks, or mutable tables. |
| **Composability** | Region fragments with named continuation exits. Compose with `emit`. Dispatch with `switch`. |
| **Vectorization** | Explicit facts-based vectorization. No secret pattern matching on loop shapes. |
| **Tooling** | Full LSP: diagnostics, completion, hover, go-to-definition, references, rename, semantic tokens, folding. |

Moonlift is for people who want native performance with LuaJIT-level
metaprogramming, and who believe semantics should be data, not strings.

---

## At a Glance

### JIT: Compile and call native functions from Lua

```lua
local moon = require("moonlift.host")

local M = moon.module("Demo")
M:export_func("add", {
    moon.param("a", moon.i32),
    moon.param("b", moon.i32),
}, moon.i32, function(fn)
    fn:return_(fn.a + fn.b)
end)

local demo = M:compile()
local add = demo:get("add")
print(add(3, 4))  -- 7, running as native machine code
demo:free()
```

### `.mlua` source: Lua host + typed islands

```moonlift
-- Lua metaprogramming layer
local function expect_byte(tag, byte, err_code)
    return region expect_@{tag}(p: ptr(u8), n: i32, pos: i32;
        ok: cont(next: i32),
        err: cont(pos: i32, code: i32))
    entry start()
        if pos >= n then jump err(pos = pos, code = @{err_code}) end
        if as(i32, p[pos]) == @{byte} then
            jump ok(next = pos + 1)
        end
        jump err(pos = pos, code = @{err_code})
    end
    end
end

local expect_A = expect_byte("A", 65, 10)
local expect_semicolon = expect_byte("semicolon", 59, 30)

-- Typed module with jump-first control
module PacketParser

export func parse_packet(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        if n <= 0 then yield -1 end
        switch as(i32, p[0]) do
        case 65 then
            emit two_digits(p, n, 1; ok = got_A, err = bad)
        case 66 then
            emit @{expect_A}(p, n, 1; ok = got_byte, err = bad)
        case 67 then
            emit digit_sum_until_semicolon(p, n, 1; ok = got_C, err = bad)
        default then
            yield -9
        end
    end
    block got_A(value: i32, pos2: i32)
        yield 1000 + value
    end
    block got_byte(next: i32)
        yield 2000
    end
    block got_C(sum: i32, pos2: i32)
        yield 3000 + sum
    end
    block bad(pos: i32, code: i32)
        yield 0 - code
    end
    end
end

end
```

### Control: typed blocks, jumps, yields

```moonlift
-- No while, for, break, or continue.
-- Everything is blocks with explicit state transitions.

export func sum(xs: view(i32), n: index) -> i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
```

### Regions: typed control fragments with continuation protocols

```moonlift
region scan_until(p: ptr(u8), n: i32, target: i32;
                  hit: cont(pos: i32),
                  miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
```

### Host types: compile-time structs and tagged unions

```moonlift
struct User
    id: i32
    age: i32
    active: bool32
end

expose Users: view(User)

func User:is_active(self: ptr(User)) -> bool
    return self.active
end
```

---

## Quick Start

### Prerequisites

- [LuaJIT](https://luajit.org/) (with FFI support)
- [Rust](https://rustup.rs/) (for the Cranelift backend)
- A C compiler (`cc`) for shared library linking

### Build

```bash
git clone https://github.com/your-org/moonlift.git
cd moonlift
cargo build --release
```

### Run your first `.mlua` file

```bash
# JIT and run a .mlua file
luajit run_mlua.lua examples/pvm_ll_hosted_types.mlua
```

### Compile to a native object file

```bash
luajit emit_object.lua examples/protocols/resp_parser.mlua -o build/resp_parser.o
```

### Compile to a shared library

```bash
luajit emit_shared.lua examples/pvm_ll_hosted_types.mlua -o build/libtape.so
```

### Quick validation

```bash
luajit tests/test_back_add_i32.lua          # Bare Cranelift JIT path
luajit tests/test_back_object_emit.lua       # Object file emission
luajit tests/test_host_quote.lua             # .mlua hosted island bridge
luajit tests/test_parse_typecheck.lua        # Parse + typecheck pipeline
luajit tests/test_parse_kernels.lua          # Jump-first kernel suite
luajit tests/test_lsp_integrated.lua         # Full LSP integration
```

---

## The Language

Moonlift is small on purpose. The entire language fits in one statement:

> Monomorphic typed data + typed regions + explicit continuation exits
> + switch/emit/jump composition + semantic `as(T, value)` conversion.

### Types

```
void  bool
i8 i16 i32 i64    u8 u16 u32 u64
f32 f64           index
ptr(T)            view(T)
```

No source-level generics. Lua generates monomorphic concrete types.

### Control flow

There is no `for`, `while`, `break`, `continue`, or `next`. The base
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

```moonlift
region my_region(params...; exit_a: cont(sig...), exit_b: cont(sig...))
entry start()
    emit other_fragment(args...; out = exit_a)
end
end
```

Compose regions with `emit`. The caller decides what each exit means.

### Switch dispatch

```moonlift
switch tag do
case 0 then jump value(delta = 1)
case 1 then jump value(delta = -1)
default then jump value(delta = 0)
end
```

No fallthrough. Explicit, verifiable control branches.

### Splicing: Lua → Moonlift values

Inside hosted islands, `@{lua_expr}` splices typed ASDL values:

```lua
local T = moon.i32
-- Splice in type position
let x: @{T} = 0

-- Splice a fragment
emit @{my_fragment}(p, n; hit = done, miss = bad)

-- Splice constants
let limit: i32 = @{SOME_CONSTANT}
```

Splices insert typed ASDL values, never raw source text.

### Host declarations

```moonlift
struct User
    id: i32
    age: i32
    active: bool32
end

expose UserRef: ptr(User)
expose Users: view(User)
```

---

## Metaprogramming Model

Lua is where genericity lives. Moonlift receives the monomorphic result.

### Lua generates Moonlift code

```lua
-- Generic fragment factory
local function expect_byte(tag, byte, err_code)
    return region expect_@{tag}(p: ptr(u8), n: i32, pos: i32;
        ok: cont(next: i32), err: cont(pos: i32, code: i32))
    entry start()
        if pos >= n then jump err(pos = pos, code = @{err_code}) end
        if as(i32, p[pos]) == @{byte} then
            jump ok(next = pos + 1)
        end
        jump err(pos = pos, code = @{err_code})
    end
    end
end

local expect_A = expect_byte("A", 65, 10)
local expect_B = expect_byte("B", 66, 20)
-- expect_A and expect_B are distinct, monomorphic, differently-named regions
```

### Lua assembles modules

```lua
local function make_parser(tag_rules)
    local M = moon.module("Parser_for_" .. tag_rules.label)
    for _, rule in ipairs(tag_rules.rules) do
        M:add_region(rule.fragment)
    end
    -- Build the combined dispatch function ...
    return M:compile()
end
```

### Two builder APIs

| API | Path | Use |
|---|---|---|
| **Lua-hosted builder** | `moonlift.host` | High-level: direct construction of types, functions, regions |
| **ASDL AST builder** | `moonlift.ast` | Low-level: field-by-field ASDL node construction, LuaLS documented |

Both APIs produce the same ASDL values consumed by the same PVM phases.

---

## Compilation Pipeline

Moonlift's compilation pipeline is explicit at every step:

```
.mlua source
  │
  ├─► mlua_parse       ──► MoonTree module (ASDL)
  ├─► tree_typecheck   ──► typed+resolved module
  ├─► tree_to_back     ──► MoonBack program (flat command array)
  ├─► back_validate    ──► validation facts + rejects
  │
  ├─► back_jit         ──► Cranelift JIT → function pointers (Rust)
  ├─► back_object       ──► Cranelift → .o relocatable object (Rust)
  └─► back_object
        + link_target   ──► link plan → system linker → .so/.dylib
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

### JIT: Lua-hosted function pointers

```lua
local M = moon.module("Demo")
M:export_func("add", params, result_type, body_fn)
local compiled = M:compile()
local add_fn = compiled:get("add")
print(add_fn(1, 2))  -- 3
compiled:free()
```

### Object files (.o)

```bash
luajit emit_object.lua examples/protocols/resp_parser.mlua -o build/resp_parser.o
```

Publishable, linkable object files for use with C, Rust, or any language
that consumes ELF/Mach-O/COFF.

### Shared libraries (.so/.dylib)

```bash
luajit emit_shared.lua examples/pvm_ll_hosted_types.mlua -o build/libtape.so
```

The linker path: `.mlua` → parse → typecheck → lower → object → link plan → system linker → `.so`.

### From Lua with the builder API

```bash
luajit run_mlua.lua examples/terra_vs_mlua/typed_dispatch_mlua.mlua
```

The `run_mlua.lua` runner loads `.mlua` files with the host quote bridge and
automatically calls exported `main`, `run`, or `test` functions if present.

---

## LSP & Editor Support

Moonlift ships with a full Language Server Protocol implementation:

| Feature | Status |
|---|---|
| Diagnostics | Parse issues, type errors, control rejects, open slot issues |
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

```lua
-- lsp.lua contains the LSP entry point
luajit lsp.lua
```

LSP capabilities and integration live under `lua/moonlift/editor_*` and
`lua/moonlift/lsp_*`.

---

## Standard Library

Moonlift's standard library lives under `lib/`:

| Module | Description |
|---|---|
| `json.lua` | Canonical hosted JSON decoder; compiled Moonlift builds Lua tables directly through the Lua C API |
| `json_meta_decode.mlua` | Internal hosted JSON implementation module |
| `lua_api.mlua` | Hosted Lua C API declarations/fragments for native Lua value construction |

JSON benchmarks compare the hosted Moonlift decoder against Lua CJSON.

---

## Benchmarks

### Moonlift vs Terra

The benchmark suite compares Moonlift's jump-first typed block/jump kernels
against equivalent Terra kernels:

```bash
benchmarks/run_vs_terra.sh          # Full suite
benchmarks/run_vs_terra.sh quick    # Quick mode
```

Results include compile time and kernel execution time comparisons across
counted loops, view construction, switch dispatch, and region composition.

### Compilation profiling

```bash
luajit benchmarks/bench_compile_back_validate_ll.lua
benchmarks/compare_compile_ll.sh
```

Compares the old triplet-based validation path against the flat fact loop
used for build-time compilation work.

### JSON benchmarks

```bash
cargo run --release --bin moonlift -- benchmarks/bench_json_hosted_decode.mlua
```

### Host type benchmarks

```bash
luajit benchmarks/bench_host_arena_abi.lua      # Arena ABI performance
luajit benchmarks/bench_host_arena_native.lua   # Native host type access
```

---

## Repository Layout

```
moonlift/
├── lua/moonlift/           Lua compiler, PVM framework, ASDL, LSP, linker
│   ├── schema/             Schema-as-data source of truth (MoonCore, MoonType, MoonBack, ...)
│   ├── parse.lua           Moonlift source parser
│   ├── mlua_parse.lua      .mlua hosted island parser
│   ├── host_quote.lua      LuaJIT hosted island bridge
│   ├── tree_typecheck.lua  Typecheck/name resolution
│   ├── tree_to_back.lua    Tree → flat backend commands
│   ├── back_validate.lua   Backend validation facts
│   ├── back_jit.lua        JIT compilation backend (Rust FFI)
│   ├── back_object.lua     Object file emission
│   ├── back_program.lua    Backend program construction
│   ├── tree_control_facts.lua     Control validation (labels, params, edges)
│   ├── vec_loop_facts.lua         Vector loop shape facts
│   ├── vec_kernel_plan.lua        Vector kernel planning
│   ├── pvm.lua             PVM: ASDL context, phases, triplets
│   ├── triplet.lua         Triplet iterator algebra
│   ├── host.lua            High-level Lua builder API
│   ├── ast.lua             Low-level ASDL node constructor API
│   │   ...
│   └── editor_*.lua        LSP features (completion, hover, references, ...)
├── src/                    Rust Cranelift backend
│   ├── lib.rs              Full Cranelift backend (JIT + object emission)
│   ├── ffi.rs              Lua FFI surface
│   └── host_arena.rs       Host arena native implementation
├── lib/                    Moonlift standard library
│   ├── json.lua            Hosted JSON decoder public API
│   ├── json_meta_decode.mlua  Hosted JSON implementation internals
│   ├── lua_api.mlua        Hosted Lua C API fragments
│   └── ...
├── examples/               Runnable examples
│   ├── protocols/          RESP parser example
│   ├── pvm_ll_hosted_types.mlua     PVM-LL convergence demo
│   ├── pvm_ll_expr_compiler.mlua    Expression compiler demo
│   └── terra_vs_mlua/              Terra comparison
├── benchmarks/             Performance benchmarks
├── tests/                  Lua test suite (~130+ tests)
│   └── fixtures/           Non-runnable editor/LSP fixtures
├── Cargo.toml              Rust project configuration
├── emit_object.lua         .mlua → native .o
├── emit_shared.lua         .mlua → .so/.dylib
├── run_mlua.lua            Run hosted .mlua with LuaJIT staging
├── lsp.lua                 LSP entry point
├── init.lua                Package init
├── LANGUAGE_REFERENCE.md   Complete language reference
├── SOURCE_GRAMMAR.md       Jump-first grammar contract
├── PVM_GUIDE.md            PVM ASDL/phase framework guide
├── COMPILER_PATTERN.md     Interactive software as compilers
├── PVM_LL.md               PVM-LL lowering direction
└── README.md               This file
```

---

## Documentation

| Document | Description |
|---|---|
| [`LANGUAGE_REFERENCE.md`](LANGUAGE_REFERENCE.md) | **Complete Moonlift language reference.** Types, modules, functions, control regions, fragments, host declarations, view ABI, vectorization. |
| [`SOURCE_GRAMMAR.md`](SOURCE_GRAMMAR.md) | **Jump-first source grammar contract.** Lexical rules, modules, types, statements, expressions, control validation rules. |
| [`PVM_GUIDE.md`](PVM_GUIDE.md) | **Complete PVM guide.** ASDL contexts, structural update, recording-triplet phases, pull-driven evaluation, the triplet algebra. |
| [`COMPILER_PATTERN.md`](COMPILER_PATTERN.md) | **Interactive software as compilers.** The philosophy behind Moonlift's architecture: ASDL as the input language, live compilation, memoized phase boundaries. |
| [`PVM_LL.md`](PVM_LL.md) | **PVM-LL lowering direction.** Lowering PVM phase semantics to ordinary Moonlift values with typed IDs and arenas. |

---

## Testing

Moonlift has ~130+ tests covering every phase of the pipeline:

### Core compiler tests

```bash
# Parser + typechecker
luajit tests/test_parse_typecheck.lua
luajit tests/test_parse_kernels.lua
luajit tests/test_tree_typecheck.lua

# Control validation
luajit tests/test_tree_control_facts.lua
luajit tests/test_parse_contract_kernels.lua

# Backend (JIT)
luajit tests/test_back_add_i32.lua
luajit tests/test_back_call.lua
luajit tests/test_back_memory_data.lua

# Object emission
luajit tests/test_back_object_emit.lua
luajit tests/test_back_object_full.lua

# Shared library emission
luajit tests/test_back_shared_emit.lua
luajit tests/test_link_plan.lua

# Vectorization
luajit tests/test_vec_loop_facts_decide.lua
luajit tests/test_vec_kernel_plan.lua
luajit tests/test_vec_to_back.lua
```

### Host and builder tests

```bash
luajit tests/test_host_quote.lua
luajit tests/test_host_value_jit.lua
luajit tests/test_host_metaprogramming_patterns.lua
luajit tests/test_host_struct_values.lua
```

### `.mlua` integration tests

```bash
luajit tests/test_mlua_parse.lua
luajit tests/test_mlua_host_pipeline.lua
luajit tests/test_mlua_document_analysis.lua
luajit tests/test_mlua_splice_shapes.lua
```

### LSP tests

```bash
luajit tests/test_lsp_integrated.lua
luajit tests/test_editor_completion_items.lua
luajit tests/test_editor_hover.lua
luajit tests/test_editor_semantic_tokens.lua
```

### Schema and PVM tests

```bash
luajit tests/test_schema_core.lua
luajit tests/test_asdl_builder.lua
luajit tests/test_pvm_surface_region_values.lua
```

---

## Philosophy

Moonlift follows a few hard rules:

### 1. ASDL is the architecture

If a distinction matters to compilation, it is represented as an ASDL value —
interned, immutable, with structural identity. Meaning must not hide in strings,
callbacks, mutable side tables, or backend-only IR. Everything downstream
consumes explicit facts.

### 2. Lua is the metaprogramming language

Moonlift source has no type parameters, no generics, no angle-bracket syntax.
LuaJIT Lua is where templates, specialization, and code generation live.
Moonlift receives the monomorphic result. This keeps the language small and the
metaprogramming powerful.

### 3. Jump-first control flow

There is no `for`, `while`, `break`, or `continue`. All loops are typed blocks
with explicit jump arguments and yield/return exits. Vectorization consumes
explicit facts, not parser guesses about loop shapes.

### 4. Every phase is explicit

Parse → typecheck → lower → validate → emit. Each phase produces explicit
facts, decisions, proofs, and rejects. Diagnostics are ASDL values consumed by
tools and LSP features — not format strings rediscovered from raw text.

### 5. Monomorphic compilation

Every Moonlift function, region, block, continuation, and value has concrete
types when it reaches typecheck/lowering. No runtime type dispatch in compiled
code.

### 6. Flat backend commands

The compilation target is a flat, verifiable array of `BackCmd` variants.
No nested IR trees, no mutable builder state, no hidden side effects.

---

## License

[Specify your license here]

---

## Contributing

[Specify contribution guidelines here]

---

*Moonlift: typed data, jump-first control, native code.*
