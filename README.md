# Moonlift

**A typed, jump-first compiled language that generates native code through Cranelift.
Two compiler frontends, one ABI, one runtime.**

Moonlift compiles to machine code. You write Moonlift source — plain `.moon` files
or `.mlua` (Lua with Moonlift value islands) — and Moonlift turns them into
JIT-ed function pointers, relocatable `.o` files, or `.so`/`.dylib` shared
libraries.

The `moonlift` and `mom` binaries use the production semantic pipeline:
parse → typecheck → tree_to_back → back_validate → MLBT v3 → Cranelift. MOM
parser/runtime modules remain under `lua/moonlift/mom/` for the native compiler
port.

| Frontend | Entry point | Status |
|---|---|---|
| **Lua** | `moon.loadstring(source)` / builder API | Metaprogramming host, `.mlua` staging, object/JIT/shared emission. |
| **MOM** | `moon.native_loadstring(source)` | Standalone binary/API using the production semantic pipeline. |

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

### MOM binary/API

```lua
local moon = require("moonlift")
local ffi = require("ffi")
local compiled = moon.native_loadstring([[func f() -> i32 return 7 end]])
local f = ffi.cast("int32_t (*)()", compiled:get("f"))
print(f())
compiled:free()
```

### `.mlua` source: Lua host + typed islands (Lua frontend)

```lua
-- Lua metaprogramming layer: build region fragments from Lua functions
local function expect_byte(tag, byte, err_code)
    local name = "expect_" .. tag
    return region @{name}(p: ptr(u8), n: i32, pos: i32;
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

-- Function with jump-first control (no module, no export)
local parse_packet = func(p: ptr(u8), n: i32) -> i32
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

return { parse_packet = parse_packet }
```

### Spread splices: generate switch arms from Lua

```lua
-- Build switch arms in Lua, spread them into a switch
local literal_arms = {
    moon.switch_arm(116, moon.stmts [=[
        if i + 4 > n then jump fail() end
        if as(i32, p[i + 1]) ~= 114 then jump fail() end
        if as(i32, p[i + 2]) ~= 117 then jump fail() end
        if as(i32, p[i + 3]) ~= 101 then jump fail() end
        pushboolean(L, 1)
        jump done(next_i = i + 4)
    ]=]),
    moon.switch_arm(110, moon.stmts [=[
        if i + 4 > n then jump fail() end
        if as(i32, p[i + 1]) ~= 117 then jump fail() end
        if as(i32, p[i + 2]) ~= 108 then jump fail() end
        if as(i32, p[i + 3]) ~= 108 then jump fail() end
        pushnil(L)
        jump done(next_i = i + 4)
    ]=]),
}

-- Inside a region:
    switch as(i32, p[i]) do
    @{literal_arms...}
    case 34 then emit @{parse_string}(...)
    default then emit @{parse_number}(...)
    end
```

See `examples/json/json_lua_stack_decoder.mlua` for a complete decoder that
beats lua-cjson by 2.5× using this pattern.

### Control: typed blocks, jumps, yields

```moonlift
-- No while, for, break, or continue.
-- Everything is blocks with explicit state transitions.

local sum = func(xs: view(i32), n: index) -> i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

return sum
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

- [Rust](https://rustup.rs/) (nightly, for the Cranelift backend)
- A C compiler (`cc`) for shared library linking

### Build

```bash
git clone https://github.com/your-org/moonlift.git
cd moonlift
make
```

Produces fully static binaries at `target/release/moonlift` and `target/release/mom`:
- Embed the Moonlift Lua staging layer and MOM compiler sources via `include_str!`
- Link vendored LuaJIT statically (from `.vendor/LuaJIT/`)
- Link the Rust/Cranelift backend in-process
- No runtime dependencies beyond libc

### Run your first `.mlua` file

```bash
# Hosted-Lua pipeline (default)
target/release/moonlift examples/protocols/resp_parser.mlua

# MOM binary/API
target/release/mom run --call main my_program.mlua
```

### Compile to a native object file

```bash
luajit emit_object.lua examples/protocols/resp_parser.mlua -o build/resp_parser.o
# Or from Lua: moon.emit_object(source, "build/resp_parser.o")
```

### Compile to a shared library

```bash
luajit emit_shared.lua examples/protocols/resp_parser.mlua -o build/libresp_parser.so
# Or from Lua: moon.emit_shared(source, "build/libresp_parser.so")
```

### Quick validation

```bash
luajit tests/test_back_add_i32.lua          # Bare Cranelift JIT path
luajit tests/test_back_object_emit.lua       # Object file emission
luajit tests/test_mlua_host_pipeline.lua     # .mlua hosted island bridge
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

For higher-level composition, use the **region composition algebra** (`moonlift.region_compose`):

```lua
local C = moon.region_compose.new("grammar")
local digit = C:choice({digit_0, digit_1, digit_2, ...})
local number = C:plus(digit)       -- one or more digits
local optional_sign = C:opt(sign)  -- zero or one sign
local int = C:seq({optional_sign, number})
-- All fragments emitted as native jump-first regions at generation time
```

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

Inside hosted islands, `@{lua_expr}` splices one typed value and
`@{lua_expr...}` spreads a Lua list of typed values into the current syntactic
list:

```lua
local T = moon.i32
local params = { moon.param("a", moon.i32), moon.param("b", moon.i32) }
local fields = { moon.field("x", moon.i32), moon.field("y", moon.i32) }
local args = { 20, 22 }

-- Splice one value in type/expression/name/fragment position
let x: @{T} = 0
let limit: i32 = @{SOME_CONSTANT}
emit @{my_fragment}(p, n; hit = done, miss = bad)

-- Spread lists in list positions
func add(@{params...}) -> i32
    return a + b
end

struct Pair
    @{fields...}
end

return add(@{args...})
```

### Extern imports

Source-level extern declarations describe C-ABI imports directly in `.mlua`:

```moonlift
extern write(fd: i32, buf: ptr(u8), count: index) -> index end
extern host_add7(x: i32) -> i32 as "host_add7_impl" end
```

Moonlift code calls these names like ordinary functions. The Cranelift JIT
resolves normal process symbols through dynamic lookup, and custom JIT symbols
can still be supplied with `module:symbol(name, ptr)` / compile options when
needed. Object/shared-library emission leaves externs as normal linker imports.

Spread splices work for expression/type/parameter/field/statement lists and for
region lists such as runtime params, continuations, block params, and blocks.
Splices occupy whole syntactic positions. They do not splice into the middle of identifiers; build the full name in Lua and use `@{name}` in a name position.

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
    local name = "expect_" .. tag
    return region @{name}(p: ptr(u8), n: i32, pos: i32;
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

### Lua builds statement lists

Lua can build statement lists as values and Moonlift source can spread them into
function or region bodies. This is the preferred escape hatch when a body is
mostly generated: Lua builds `Stmt[]`; Moonlift syntax decides where it goes.

```lua
local body = moon.stmts({ x = moon.i32 }, function(b)
    local x = b:param("x")
    local y = b:let("y", moon.i32, x + 1)
    b:return_(y * 2)
end)

return func twice_plus_two(x: i32) -> i32
    @{body...}
end
```

Region blocks are values too; use `moon.control_block(...)` when generating a
list for `@{blocks...}` in a region.

For small source-shaped snippets, `moon.stmts [[...]]` parses a Moonlift
statement list directly:

```lua
local body = moon.stmts [[
    let y: i32 = x + 1
    return y * 2
]]
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

### Two compiler frontends

| Frontend | Entry point | Compiler core runtime | Status |
|---|---|---|---|
| **Lua** | `moon.loadstring(source)` / builder API | Lua + PVM phases | Production compiler path |
| **MOM** | `moon.native_loadstring(source)` | Production semantic pipeline | Standalone binary/API |

Both entry points emit MLBT v3 binary format consumed by the Rust Cranelift
backend.

---

## Compilation Pipeline

Moonlift's production compilation pipeline:

### Lua frontend pipeline (production / oracle)

```
.mlua source
  │
  ├─► parse/scan_document ──► hosted island values / MoonTree module (ASDL)
  ├─► tree_typecheck      ──► typed+resolved module
  ├─► tree_to_back        ──► MoonBack program (flat command array)
  ├─► back_validate       ──► validation facts + rejects
  │
  ├─► back_command_binary ──► MLBT v3 binary (Lua encoder)
  ├─► moonlift_jit_compile_binary   ──► Cranelift JIT → function pointers (Rust)
  └─► moonlift_object_compile_binary ──► Cranelift → .o relocatable object (Rust)
```

This pipeline produces MLBT v3 binary wire format consumed by the same Rust
Cranelift backend used by MOM runtime experiments.

### MOM pipeline target

```
source bytes
  ├─► mom_lex_into              ──► token tape
  ├─► mom_parse_native_core     ──► native AST tape
  ├─► typed AST / open / bind / typecheck
  ├─► tree_to_back-equivalent lowering
  ├─► validation
  └─► MLBT v3 binary            ──► Cranelift backend
```

The parser/runtime groundwork exists. The semantic phases and tree_to_back parity
boundary are not complete, so `moon.native_loadstring` and `target/release/mom`
reject source compilation explicitly.

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
local moon = require("moonlift")
local compiled = moon.loadstring([[
  local add = func(a: i32, b: i32) -> i32
    return a + b
  end
  return add
]], "demo.mlua")()
local add_fn = compiled:get("add")
print(add_fn(3, 4))  -- 7, running as native machine code
compiled:free()
```

### Object files (.o)

From Lua:

```lua
local moon = require("moonlift")
local obj_bytes = moon.emit_object(source, "build/resp_parser.o")
-- Or from CLI: mom --emit-object -o build/resp_parser.o file.mlua
```

Publishable, linkable object files for use with C, Rust, or any language
that consumes ELF/Mach-O/COFF.

### Shared libraries (.so/.dylib)

```lua
local moon = require("moonlift")
local so_bytes = moon.emit_shared(source, "build/libresp_parser.so")
```

The linker path: `.mlua` → parse → typecheck → lower → object → link plan → system linker → `.so`.

### Standalone binaries

```bash
make
# Hosted-Lua pipeline (default)
target/release/moonlift file.mlua

# MOM binary/API
target/release/mom run --call main file.mlua
target/release/mom --emit-object -o out.o file.mlua
```

The `mom` and `moonlift` binaries are fully static with zero runtime dependencies.
Copy them anywhere. No `libluajit.so`, no `lua/` directory, no `libmoonlift.so`.

### From Lua with the builder API

```lua
local moon = require("moonlift")

-- Hosted JIT pipeline
local compiled = moon.loadstring([[
  local add = func(a: i32, b: i32) -> i32
    return a + b
  end
  return add
]], "demo.mlua")()
local fn = compiled:get("add")
print(fn(3, 4))  -- 7
compiled:free()

-- Or use the builder API
local M = moon.module("Demo")
M:export_func("add", params, result_type, body_fn)
local built = M:compile()
local add_fn = built:get("add")
print(add_fn(1, 2))  -- 3
built:free()
```

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
| `region_compose.lua` | **Region composition algebra.** PEG-style combinators (`seq`, `choice`, `star`, `plus`, `opt`, `pred`, `not_pred`) that generate native jump-first regions at Lua generation time. Exposed as `moonlift.region_compose` |

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

### JSON stack decoder benchmark

Moonlift's hosted JSON stack decoder is a jump-first native state machine that
parses JSON and builds Lua values directly through the Lua C API — no
interpreter overhead in the parsing loop, no `strtod`, pre-counted table
allocations, region fragments for zero-cost control-flow composition.

It uses source-level `extern ... end` declarations for Lua C API calls,
`moon.switch_arm` + `@{literal_arms...}` spread splices to generate the
`true`/`false`/`null` dispatch arms from Lua, and direct mutual recursion for
`parse_value`/`parse_array`/`parse_object`.

Benchmarked against **lua-cjson 2.1.0** (the standard fast C JSON library
for Lua), **dkjson** (pure Lua), and a hand-written pure-Lua recursive descent
decoder on a realistic 2.9 KB payload with 50 user records:

```bash
luajit benchmarks/bench_json_stack_decode.lua          # quick
luajit benchmarks/bench_json_stack_decode.lua full     # full
```

**Results: Moonlift beats cjson by 2.5×, pure Lua by 4.6×.**

| Decoder | Time | ns/byte | Throughput |
|---|---|---|---|
| **moonlift_json_stack** | 0.109s | 3.7 | **268 MB/s** |
| cjson_decode | 0.268s | 9.2 | 109 MB/s |
| pure_lua_json | 0.505s | 17.3 | 58 MB/s |
| dkjson_decode | 1.363s | 46.7 | 21 MB/s |

| Comparison | Speedup |
|---|---|
| Moonlift / cjson | **2.46×** |
| Moonlift / pure Lua | **4.63×** |
| Moonlift / dkjson | **12.50×** |

The decoder source lives in `examples/json/json_lua_stack_decoder.mlua`.
For cjson/dkjson comparison, install locally:

```bash
luarocks --lua-version=5.1 --local install lua-cjson
luarocks --lua-version=5.1 --local install dkjson
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
├── lua/moonlift/
│   ├── mom/                MOM native compiler modules
│   │   ├── parser/         Native tokeniser, AST tape parser core
│   │   ├── back/           Backend op/type/command lowering (native)
│   │   ├── vec/            Vectorization loop facts, decision, planning
│   │   ├── driver/         MLBT v3 wire generation, Rust backend FFI
│   │   ├── runtime/        Runtime builders, integer maps
│   │   └── schema/         Schema seed (MoonBack, MoonCore, ...)
│   ├── host_mom.lua        MOM frontend — moon.native_loadstring / moon.native_loadfile
│   ├── host.lua            High-level Lua builder API (Lua frontend)
│   ├── ast.lua             Low-level ASDL node constructor API
│   ├── back_jit.lua        Lua→Rust JIT FFI bridge (now uses binary wire format)
│   ├── back_command_binary.lua  MLBT v3 binary wire format encoder (Lua)
│   ├── back_object.lua     Object file emission (uses binary wire format)
│   ├── parser/             Lua-based source parser
│   ├── schema/             ASDL source of truth (MoonCore, ...)
│   ├── pvm.lua             PVM: ASDL context, phases, triplets
│   ├── tree_typecheck.lua  Typecheck/name resolution
│   ├── tree_to_back.lua    Tree → flat backend commands
│   └── ...                 Remaining Lua compiler phases
├── src/                    Rust Cranelift backend + standalone binary
│   ├── lib.rs              Full Cranelift backend (JIT + object emission)
│   ├── main.rs             Standalone `moonlift` binary (embeds Lua compiler)
│   ├── ffi.rs              Lua FFI surface
│   ├── host_arena.rs       Host arena native implementation
│   └── embedded_lua.rs     Auto-generated by build.rs: all Lua sources via include_str!
├── build.rs                Generates src/embedded_lua.rs at compile time
├── Makefile                Top-level build (static binary via `make`)
├── lib/                    Moonlift standard library
│   └── ...
├── examples/               Runnable examples
│   ├── json/              JSON stack decoder (spread splices, region composition)
│   ├── protocols/          RESP parser example
│   └── terra_vs_mlua/              Terra comparison
├── benchmarks/             Performance benchmarks
├── tests/                  Lua test suite (~130+ tests)
│   └── fixtures/           Non-runnable editor/LSP fixtures
├── Cargo.toml              Rust project configuration
├── emit_object.lua         Legacy: .mlua → native .o (use moon.emit_object or mom --emit-object)
├── emit_shared.lua         Legacy: .mlua → .so/.dylib (use moon.emit_shared)
├── run_mlua.lua            Legacy: run hosted .mlua (use moonlift binary or moon.loadfile)
├── lsp.lua                 LSP entry point
├── init.lua                Package init
├── LANGUAGE_REFERENCE.md   Complete language reference
├── SOURCE_GRAMMAR.md       Jump-first grammar contract
├── PVM_GUIDE.md            PVM ASDL/phase framework guide
├── COMPILER_PATTERN.md     Interactive software as compilers
└── README.md               This file
```

---

## Documentation

| Document | Description |
|---|---|---|
| [`LANGUAGE_REFERENCE.md`](LANGUAGE_REFERENCE.md) | **Complete Moonlift language reference.** Types, modules, functions, control regions, fragments, host declarations, view ABI, vectorization. |
| [`SOURCE_GRAMMAR.md`](SOURCE_GRAMMAR.md) | **Jump-first source grammar contract.** Lexical rules, modules, types, statements, expressions, control validation rules. |
| [`lua/moonlift/mom/PORTING_GUIDE.md`](lua/moonlift/mom/PORTING_GUIDE.md) | **MOM porting guide.** Phase plan, module organization, lowering discipline for the native compiler. |
| [`lua/moonlift/mom/PARSER_DESIGN.md`](lua/moonlift/mom/PARSER_DESIGN.md) | **MOM native parser design.** Source-to-AST pipeline, token tape, Pratt parsing, memory model. |
| [`BACK_WIRE_FORMAT.md`](BACK_WIRE_FORMAT.md) | **MLBT v3 binary wire format.** The stable ABI shared by both frontends. |
| [`PROTOCOL_SYNTAX.md`](PROTOCOL_SYNTAX.md) | **Named protocol exits.** Tagged-union types used as reusable region exit protocols. |
| [`PVM_GUIDE.md`](PVM_GUIDE.md) | **Complete PVM guide.** ASDL contexts, structural update, recording-triplet phases, pull-driven evaluation, the triplet algebra. |
| [`COMPILER_PATTERN.md`](COMPILER_PATTERN.md) | **Interactive software as compilers.** The philosophy behind Moonlift's architecture: ASDL as the input language, live compilation, memoized phase boundaries. |

---

## Testing

Moonlift has ~150+ tests covering every phase of both frontends:

### MOM tests (native compiler)

```bash
# Compiler core
luajit tests/test_mom_groundwork.lua        # Runtime builders, maps, id allocators
luajit tests/test_mom_native_lexer.mlua     # Native lexer
luajit tests/test_mom_native_core.lua       # Native parser core (AST tapes)
luajit tests/test_mom_native_ast.lua        # Native AST vs Lua AST cross-check
luajit tests/test_mom_source_to_binary.lua  # MOM API source → MLBT → execute
luajit tests/test_mom_cli.lua               # Standalone mom run/object CLI

# Schema validation
luajit tests/test_mom_check_correctness.mlua  # Schema type comparison

# Vectorization
luajit tests/test_mom_vec.lua               # Vec facts → decide → plan → lower

# Wire format
luajit tests/test_mom_wire.lua              # MLBT v3 wire builder

# Frontend API
target/release/mom status
```

### Lua frontend tests (bootstrap / oracle)

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
luajit tests/test_host_value_jit.lua
luajit tests/test_host_metaprogramming_patterns.lua
luajit tests/test_host_struct_values.lua
luajit tests/test_host_stmt_list_builder.lua
luajit tests/test_host_func_values.lua
```

### Metaprogramming and splice tests

```bash
luajit tests/test_parse_spread_splice.lua
luajit tests/test_spread_splice_lists.lua
luajit tests/test_spread_splice_regions.lua
luajit tests/test_switch_stmt_lowering.lua
luajit tests/test_region_frag_runtime_param_call.lua
luajit tests/test_direct_mutual_recursion.lua
luajit tests/test_host_extern_symbol.lua
luajit tests/test_addr_of_var_stack.lua
```

### `.mlua` integration tests

```bash
luajit tests/test_mlua_host_pipeline.lua
luajit tests/test_mlua_document_analysis.lua
luajit tests/test_mlua_splice_shapes.lua
target/release/moonlift examples/json/json_lua_stack_decoder.mlua
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

### 1. Two frontends, one ABI

MOM (Moonlift-on-Moonlift) is the default compiler — native code from source to
backend. The Lua frontend is the bootstrap seed and conformance oracle. Both
produce the same MLBT v3 binary wire format consumed by the Rust Cranelift
backend. Two implementations sharing one stable ABI means every bug in one is a
test case for the other.

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

### 6. Monomorphic compilation

Every Moonlift function, region, block, continuation, and value has concrete
types when it reaches typecheck/lowering. No runtime type dispatch in compiled
code.

### 7. Flat backend commands

The compilation target is a flat, verifiable array of `BackCmd` variants.
No nested IR trees, no mutable builder state, no hidden side effects.

---

*Moonlift: typed data, jump-first control, native code.*
