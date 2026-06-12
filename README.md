# Moonlift

**A typed, jump-first compiled language that generates native code through Cranelift.**
**Metaprogrammed through LuaJIT — quoted with `moon.XXX` — compiled to machine code.**

Moonlift compiles to native machine code. You write Moonlift source enclosed in
`moon.func[[]]`, `moon.region[[]]`, `moon.stmts[[]]` quotes — or embed it in `.mlua`
files where `@{...}` carrier closures resolve bindings automatically. The
compiler turns them into JIT-ed function pointers, relocatable `.o` files, or
`.so`/`.dylib` shared libraries.

The `moonlift` binary embeds the full compiler (Lua staging + Cranelift backend).
Zero runtime dependencies — copy it anywhere.

```
.mlua / .lua source
  → moon.func[[]] / moon.region[[]] quotes
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
- [Metaprogramming Model](#metaprogramming-model)
- [The `@{}` Bridge — Lua values in Moonlift](#the--bridge--lua-values-in-moonlift)
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
| **Quoting API** | `moon.func[[]]`, `moon.region[[]]`, `moon.stmts[[]]` — write Moonlift in strings, get typed ASDL back. No separate builder API to learn. |
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

### From Lua: `moon.func[[]]` quotes

```lua
local moon = require("moonlift")

-- Define a function by quoting Moonlift source
local add = moon.func [[add(a: i32, b: i32): i32 return a + b end]]

-- Compile and run
local bundle = moon.bundle("demo")
module:add_func(add)
local compiled = module:compile()
local fn = compiled:get("add")
print(fn(3, 4))  -- 7, running as native machine code
compiled:free()
```

### From `.mlua`: Lua host + typed islands with `@{...}`

```lua
-- .mlua files mix Lua and Moonlift with automatic binding resolution.
-- @{lua_expr} splices Lua values into Moonlift source.

local function expect_byte(tag, byte, err_code)
    local name = "expect_" .. tag
    return region @{name}(p: ptr(u8), n: i32, pos: i32;
        ok(next: i32),
        err(pos: i32, code: i32))
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

-- Function with jump-first control
local parse_packet = func(p: ptr(u8), n: i32): i32
    return region: i32
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

### Values binder: generate code from Lua data

```lua
-- Build switch arms from Lua data, spread into Moonlift source
local function literal_arm(text, push_src)
    local bytes = { text:byte(1, #text) }
    local lines = {}
    lines[#lines + 1] = ("if i + %d > n then jump fail() end"):format(#bytes)
    for off = 2, #bytes do
        lines[#lines + 1] = ("if as(i32, p[i + %d]) ~= %d then jump fail() end"):format(off - 1, bytes[off])
    end
    lines[#lines + 1] = push_src
    lines[#lines + 1] = ("jump done(next_i = i + %d)"):format(#bytes)
    return { raw_key = tostring(bytes[1]), body = moon.stmts(table.concat(lines, "\n")) }
end

local literal_arms = {
    literal_arm("true",  "lua_pushboolean(L, 1)"),
    literal_arm("false", "lua_pushboolean(L, 0)"),
    literal_arm("null",  "lua_pushnil(L)"),
}

-- Bind values, then quote: moon.func { values } [[ source ]]
local parse_value = moon.func { literal_arms = literal_arms } [[
parse_value(L: ptr(u8), p: ptr(u8), n: i32, pos: i32, buf: ptr(u8)): i32
    return region: i32
    entry start()
        switch as(i32, p[i]) do
        @{literal_arms...}
        case 34 then emit parse_string(...)
        default then emit parse_number(...)
        end
    end
    ...
end
]]
```

See `examples/json/json_lua_stack_decoder.lua` for a complete decoder that
beats lua-cjson by 2.5×.

### Control: typed blocks, jumps, yields

```moonlift
-- No while, for, break, or continue.
-- Everything is blocks with explicit state transitions.

local sum = func(xs: view(i32), n: index): i32
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
                  hit(pos: i32),
                  miss(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
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

Produces a fully static binary at `target/release/moonlift`:
- Embeds the Moonlift Lua staging layer via `include_str!`
- Links vendored LuaJIT statically (from `.vendor/LuaJIT/`)
- Links the Rust/Cranelift backend in-process
- No runtime dependencies beyond libc

### Run a `.mlua` file

```bash
target/release/moonlift examples/json/json_lua_stack_decoder.mlua
```

### Run the same decoder from pure Lua

```bash
luajit examples/json/json_lua_stack_decoder.lua
```

Both produce identical output. The `.lua` version uses `moon.func[[]]` quotes
and doesn't require the `.mlua` carrier pipeline.

### Compile to a native object file

```lua
-- From Lua: moon.emit_object(source, "build/out.o")
local moon = require("moonlift")
local obj_bytes = moon.emit_object(source, "build/out.o")
```

### Quick validation

```bash
luajit tests/test_back_add_i32.lua          # Bare Cranelift JIT path
luajit tests/test_mlua_host_pipeline.lua    # .mlua hosted island bridge
luajit tests/test_parse_typecheck.lua       # Parse + typecheck pipeline
luajit tests/test_lsp_integrated.lua        # Full LSP integration
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

```moonlift
region my_region(params...; exit_a(sig...) | exit_b(sig...))
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

### Extern imports

Source-level extern declarations describe C-ABI imports:

```moonlift
extern write(fd: i32, buf: ptr(u8), count: index): index end
extern host_add7(x: i32): i32 as "host_add7_impl" end
```

Moonlift code calls these names like ordinary functions. The Cranelift JIT
resolves normal process symbols through dynamic lookup. Object/shared-library
emission leaves externs as normal linker imports.

---

## Metaprogramming Model

Every `moon.XXX` is either a **quote** (write Moonlift syntax in a string,
get typed ASDL back) or a **table builder** (build data with Lua loops,
get typed ASDL back).

### Quotes `moon.XXX[[]]` — code-shaped things

```lua
-- Full islands: keyword is optional (moon.func already says "func")
local f = moon.func     [[add(a: i32, b: i32): i32 return a + b end]]
local r = moon.region   [[scan(p: ptr(u8); hit(v: i32)) entry ... end end]]
local s = moon.struct   [[Point x: i32, y: i32 end]]
local u = moon.union    [[Option Some(i32) | None end]]
local e = moon.extern   [[write(fd: i32, buf: ptr(u8)): i32 end]]

-- Fine-grained
local stmts = moon.stmts [[let y = x + 1; return y * 2]]
local ty    = moon.type  [[ptr(i32)]]
local expr  = moon.expr  [[x + 1]]
```

### Table builders `moon.XXX{ }` — data-shaped things

```lua
-- Build arrays with Lua loops, get typed ASDL
local params = moon.params {
    { name = "x", type = moon.i32 },
    { name = "y", type = moon.i32 },
}

local fields = moon.fields {
    { name = "x", type = moon.f64 },
    { name = "y", type = moon.f64 },
}

local variants = moon.variants {
    { name = "Some", payload = moon.i32 },
    { name = "None" },
}

local conts = moon.conts {
    hit  = { params = { { name = "pos", type = moon.i32 } } },
    miss = { params = {} },
}

-- Codegen: build tables with a Lua for loop
local params = {}
for i = 1, N do
    params[i] = { name = "x" .. i, type = moon.i32 }
end
```

### Values binder `moon.XXX{values}[[src]]` — Lua data meets Moonlift syntax

```lua
-- Bind Lua values in a table, then quote Moonlift with @{} holes
moon.func { T = moon.i32, params = param_list } [[
add(@{params...}): @{T}
    return a + b
end
]]

-- Switch arms generated from Lua data
moon.func { literal_arms = arm_array } [[
parse_value(...): i32
    switch as(i32, p[i]) do
    @{literal_arms...}
    default then ...
    end
end
]]
```

### The single dispatch rule

Every `moon.XXX` is a **chain object** (see `lua/moonlift/chain.lua`). Its
`__call` dispatches on the type of the first argument:

| Input | Means | Returns |
|---|---|---|
| `moon.XXX [[src]]` | Pure quote — `@{}` in `src` is an error (no bindings) | Typed ASDL directly |
| `moon.XXX { string keys }` | Values binder — `@{key}` in the next string resolves from table | Quote closure `fn(src)` |
| `moon.XXX { string keys } [[src]]` | Binder + quote — `@{key}` in `src` bound from table | Typed ASDL directly |
| `moon.XXX { int keys }` | Table builder — records from data | Typed ASDL array |
| `moon.XXX [[header only]]` | Bodyless decl (`func`/`region`) — `@{}` is an error (no bindings yet) | **Header closure** (callable) |
| `moon.XXX {b} [[header with @{}]]` | Binder → header — `@{}` in header resolved from `b` | **Header closure** carrying `b` |
| `header [[body with @{}]]` | Body string — `@{}` resolved from header's accumulated bindings | Typed ASDL directly |
| `header { more } [[body with @{}]]` | Merge more bindings, then body — `@{}` resolved from merged set | Typed ASDL directly |

### The `chain.lua` monoid — composable call steps

Because every step returns something callable, calls compose left-to-right
without extra variables. This is the monoid property of `chain.lua`: each
returned value is either typed ASDL (terminal) or something that continues
accepting calls.

**`@{}` resolves from the accumulated bindings at each string.**  Any string
passed to a chain step — whether a header string or a body string — is parsed
and `@{key}` holes are filled from the bindings table accumulated so far in
the chain.  Two separate strings in the same chain share the same binding
scope.

```lua
-- ① Pure quote — one call, one result
local add = moon.func [[add(a: i32, b: i32): i32
    return a + b
end]]

-- ② Binder + quote — {values} then [[src]]
--    The {values} call returns a closure; [[src]] calls it immediately.
local add = moon.func { T = moon.i32 } [[
add(a: @{T}, b: @{T}): @{T}
    return a + b
end]]

-- ③ Header closure — split declaration from body
--    moon.func sees a bodyless `func` (no body, no `end`), returns a
--    header closure instead of ASDL. The closure is then called with
--    the body string. @{} is NOT available here (no bindings table).
local header = moon.func [[add(a: i32, b: i32): i32]]
local add    = header [[return a + b]]

-- The two steps collapse into one expression:
local add = moon.func [[add(a: i32, b: i32): i32]]
                      [[return a + b]]

-- ④ Binder → header closure → body  (all three in one expression)
--    {bindings} seeds the binding scope. Both the header string and the
--    body string can use @{key} — they share the same accumulated bindings.
local add = moon.func { T = moon.i32 }
                      [[add(a: @{T}, b: @{T}): @{T}]]   -- @{T} resolved here
                      [[return a + b]]                     -- @{T} also available here

-- ⑤ Header closure + extra bindings injected mid-chain
--    The header itself has no bindings yet (plain [[...]] call), so @{}
--    would error there. Bindings are supplied on the header closure, and
--    then @{} in the body string resolves from those bindings.
local generic_header = moon.func [[add(a: @{T}, b: @{T}): @{T}]]
--                              ^^^ no @{} resolved yet — parsed but slots left open

local add_i32 = generic_header { T = moon.i32 } [[return a + b]]
--                             ^^^^^^^^^^^^^^ bindings provided here, @{T} resolved
local add_f64 = generic_header { T = moon.f64 } [[return a + b]]

-- ⑥ Table builder — integer-keyed, no quotes involved
--    moon.params / moon.fields / moon.variants etc. use this path.
local params = moon.params {
    { name = "x", type = moon.i32 },
    { name = "y", type = moon.i32 },
}

-- ⑦ region follows the same pattern (header → body)
--    @{} works in both the header and the body; both share the bindings.
local scan = moon.region { target = moon.i32 }
                         [[scan(p: ptr(u8), n: i32; hit(pos: i32), miss)]]
                         [[
entry loop(i: i32 = 0)
    if i >= n then jump miss() end
    if as(i32, p[i]) == @{target} then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end]]
```

**Why it works.**  `moon.XXX` is a table with `__call`. Calling it with
`{string keys}` returns a plain Lua `function` that carries the bindings.
Calling that function with a string resolves `@{key}` holes from those
bindings.  Calling `moon.XXX` directly with a string (`[[...]]`) or with
`{int keys}` returns typed ASDL — `@{}` in a bare string with no prior
bindings table is a parse error.  For `moon.func` and `moon.region`, when
the parsed result is a *bodyless declaration*, `wrap_fn` returns a
**header closure** — a table with its own `__call` — instead of typed ASDL.
That closure carries the accumulated bindings from all `{...}` steps so far.
Calling the header closure with a body string resolves any `@{key}` in
that string from the same accumulated bindings, then produces final ASDL.
Header calls take body-only strings: no repeated outer declaration and no
outer closing `end`.
Calling it with a `{table}` merges more bindings and returns a new header
closure.  The chain terminates exactly once, when a fully-resolved ASDL
value is produced.

The implementation lives entirely in two files:
- `lua/moonlift/chain.lua` — the generic chain/dispatch machinery
- `lua/moonlift/host.lua` — all `moon.XXX` instances wired up via `make_quote`

Extending with your own chain:

```lua
local moon = require("moonlift")
-- moon.chain is make_chain bound to the default session
local my_api = moon.chain {
    name    = "my_api",
    parse   = function(T, src) ... end,
    wrap    = function(value, parsed, T, src, bindings) ... end,
    expand  = function(e, value, env) ... end,  -- for @{} splice support
    table_fn = function(arr) ... end,            -- for {int-key} builder form
}
-- my_api then has the same moon.XXX calling conventions
```

### No buildr API, no `function(b) ... end`

The old builder API (`b:let`, `b:if_`, `b:switch_`, `b:return_`, `b:jump`,
`b:yield_`, `b:emit`) is retired. All codegen goes through quotes or
table builders.

What stays:
- `moon.bundle("Name")` — output packaging (compile together, emit .o/.so)
- `moon.ast.*` — low-level ASDL constructors (escape hatch)
- Lua `for` loops for building tables — the only "builder" you need

---

## The `@{}` Bridge — Lua values in Moonlift

Inside `.mlua` files, `@{lua_expr}` splices Lua values into Moonlift source:

```moonlift
let x: @{T} = @{initial}
emit @{fragment}(p, n; ok = done, err = bad)

func f(@{params...}): i32
    @{body...}
end
```

Inside standalone `moon.XXX{values}[[src]]` calls, `@{key}` fills from the
values table. Both paths go through the same `host_splice` + `open_expand`
pipeline — the same ASDL slots, the same expansion, the same result.

### Splice positions

| Position | Example | Value type |
|---|---|---|
| Type | `let x: @{T}` | `TypeValue` |
| Expression | `if x > @{limit}` | `ExprValue`, number, bool |
| Name | `func @{name}(...)` | String |
| List (spread) | `@{params...}` | Lua array of matching type |
| Fragment | `emit @{frag}(...)` | `RegionFragValue` |
| Switch arms | `@{arms...}` | `{ raw_key, body }[]` |
| Params | `@{params...}` | `{ name, type }[]` |
| Fields | `@{fields...}` | `{ name, type }[]` |
| Variants | `@{variants...}` | `{ name, payload? }[]` |
| Blocks | `@{blocks...}` | `{ label, params?, body? }[]` |
| Conts | `@{conts...}` | `{ [name] = { params? } }` map |

See `LANGUAGE_REFERENCE.md` §14 for the complete reference.

---

## Compilation Pipeline

### Single pipeline

```
.mlua / moon.XXX source
  │
  ├─► parse ──► ASDL (Slot-typed AST)
  ├─► fill/expand ──► slot-resolved AST
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

### JIT: Lua-hosted function pointers

**Callable functions** — `moon.func[[]]` returns a callable table that
auto-compiles on first invocation. No module scaffolding needed:

```lua
local moon = require("moonlift")
local add = moon.func [[add(a: i32, b: i32): i32 return a + b end]]
print(add(3, 4))  -- 7 — first call compiles, caches, runs native
add:free()
```

**Cross-function dependencies** — declare deps in the values table:

```lua
local dep = moon.func [[dep(x: i32): i32 return x + 1 end]]
local main = moon.func { dep = dep } [[
main(x: i32): i32
    return @{dep}(x)
end
]]
print(main(5))  -- 6 — dep registered in ephemeral module
main:free()
dep:free()
```

**Explicit module path** — still available for complex multi-function artifacts:

```lua
local bundle = moon.bundle("demo")
module:add_func(add)
local compiled = module:compile()
local fn = compiled:get("add")
print(fn(3, 4))  -- 7
compiled:free()
```

### From `.mlua` files

```lua
local moon = require("moonlift")
local chunk = moon.loadfile("file.mlua")
local result = chunk()
```

### Object files (.o)

```lua
local moon = require("moonlift")
local obj_bytes = moon.emit_object(source, "build/out.o")
```

### Shared libraries (.so/.dylib)

```lua
local moon = require("moonlift")
local so_bytes = moon.emit_shared(source, "build/libout.so")
```

The linker path: `.mlua` → parse → typecheck → lower → object → link plan → system linker → `.so`.

### Standalone binary

```bash
make
target/release/moonlift file.mlua
```

The `moonlift` binary is fully static with zero runtime dependencies.
Copy it anywhere. No `libluajit.so`, no `lua/` directory.

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

```bash
luajit lsp.lua
```

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

### JSON stack decoder benchmark

Moonlift's hosted JSON stack decoder parses JSON and builds Lua values directly
through the Lua C API — no interpreter overhead in the parsing loop, no `strtod`,
region fragments for zero-cost control-flow composition.

Benchmarked against **lua-cjson 2.1.0**, **dkjson**, and pure Lua on a realistic
2.9 KB payload with 50 user records:

```bash
luajit benchmarks/bench_json_stack_decode.lua          # quick
luajit benchmarks/bench_json_stack_decode.lua full     # full
```

| Decoder | Time | Throughput |
|---|---|---|
| **moonlift_json_stack** | 0.109s | **268 MB/s** |
| cjson_decode | 0.268s | 109 MB/s |
| pure_lua_json | 0.505s | 58 MB/s |
| dkjson_decode | 1.363s | 21 MB/s |

The decoder is available in two forms:
- `examples/json/json_lua_stack_decoder.mlua` — `.mlua` with `@{}` carrier closures
- `examples/json/json_lua_stack_decoder.lua` — pure Lua using `moon.func[[]]` quotes

Both produce identical native code and benchmark results.

---

## Repository Layout

```
moonlift/
├── lua/moonlift/
│   ├── host.lua                Unified moon.XXX quoting + table builder API
│   ├── host_func_values.lua    Statement/params/values binders (internal)
│   ├── host_region_values.lua  Region/cont/block builders (internal)
│   ├── host_struct_values.lua  Struct/field/variant builders (internal)
│   ├── host_type_values.lua    Type value constructors
│   ├── host_expr_values.lua    Expression value constructors
│   ├── host_splice.lua         Slot filling for all grammar positions
│   ├── host_session.lua        Session management, T context
│   ├── host_module_values.lua  Module builder + compilation
│   ├── host_values.lua         Canonical value wrappers
│   ├── ast.lua                 Low-level ASDL node constructor API
│   ├── parse.lua               Lexer + Pratt parser, all island kinds
│   ├── open_expand.lua         Slot expansion (fill + resolve)
│   ├── pvm.lua                 PVM: ASDL context, phases, triplets
│   ├── tree_typecheck.lua      Typecheck/name resolution
│   ├── tree_to_back.lua        Tree → flat backend commands
│   ├── back_jit.lua            Lua→Rust JIT FFI bridge (Flatline wire format)
│   ├── back_command_binary.lua Flatline v4 binary wire format encoder
│   ├── back_object.lua         Object file emission
│   ├── frontend_pipeline.lua   Compilation pipeline orchestration
│   ├── schema/                 ASDL source of truth (MoonCore, MoonType, ...)
│   ├── editor_*                LSP features
│   ├── lsp_*                   LSP protocol
│   └── region_compose.lua      Region composition algebra
├── src/                        Rust Cranelift backend + standalone binary
│   ├── lib.rs                  Full Cranelift backend (JIT + object emission)
│   ├── main.rs                 Standalone `moonlift` binary
│   ├── ffi.rs                  Lua FFI surface
│   └── embedded_lua.rs         Auto-generated by build.rs
├── build.rs                    Generates src/embedded_lua.rs at compile time
├── lib/                        Moonlift standard library
│   └── region_compose.lua
├── examples/
│   ├── json/                   JSON stack decoder (.mlua + .lua versions)
│   ├── protocols/              RESP parser example
│   └── terra_vs_mlua/          Terra comparison
├── benchmarks/                 Performance benchmarks
├── tests/                      Lua test suite (~130+ tests)
├── LANGUAGE_REFERENCE.md       Complete language reference
├── PVM_GUIDE.md                PVM ASDL/phase framework guide
├── COMPILER_PATTERN.md         Interactive software as compilers
├── BACK_WIRE_FORMAT.md         Flatline v4 binary wire format
├── explicit_programming.md     Explicit programming philosophy
└── README.md                   This file
```

---

## Documentation

| Document | Description |
|---|---|
| [`LANGUAGE_REFERENCE.md`](LANGUAGE_REFERENCE.md) | **Complete Moonlift language reference.** Types, modules, functions, control regions, fragments, quoting API, splicing, host declarations, view ABI, vectorization. |
| [`BACK_WIRE_FORMAT.md`](BACK_WIRE_FORMAT.md) | **Flatline v4 binary wire format.** The stable ABI between the Lua frontend and the Rust Cranelift backend. |
| [`PVM_GUIDE.md`](PVM_GUIDE.md) | **Complete PVM guide.** ASDL contexts, structural update, recording-triplet phases, pull-driven evaluation, the triplet algebra. |
| [`COMPILER_PATTERN.md`](COMPILER_PATTERN.md) | **Interactive software as compilers.** The philosophy behind Moonlift's architecture: ASDL as the input language, live compilation, memoized phase boundaries. |
| [`explicit_programming.md`](explicit_programming.md) | **Explicit programming philosophy.** A guide to designing systems with typed data types and typed control protocols. |

---

## Testing

Moonlift has ~130+ tests covering every phase:

### Parser + typechecker

```bash
luajit tests/test_parse_typecheck.lua
luajit tests/test_parse_kernels.lua
luajit tests/test_tree_typecheck.lua
```

### Backend (JIT)

```bash
luajit tests/test_back_add_i32.lua
luajit tests/test_back_call.lua
luajit tests/test_back_memory_data.lua
```

### Object emission

```bash
luajit tests/test_back_object_emit.lua
luajit tests/test_back_object_full.lua
```

### Shared library emission

```bash
luajit tests/test_back_shared_emit.lua
luajit tests/test_link_plan.lua
```

### Vectorization

```bash
luajit tests/test_vec_loop_facts_decide.lua
luajit tests/test_vec_kernel_plan.lua
luajit tests/test_vec_to_back.lua
```

### Metaprogramming and splice tests

```bash
luajit tests/test_spread_splice_lists.lua
luajit tests/test_spread_splice_regions.lua
luajit tests/test_host_metaprogramming_patterns.lua
luajit tests/test_host_struct_values.lua
luajit tests/test_host_stmt_list_builder.lua
luajit tests/test_parse_spread_splice.lua
luajit tests/test_region_frag_runtime_param_call.lua
luajit tests/test_direct_mutual_recursion.lua
luajit tests/test_host_extern_symbol.lua
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

### 6. Monomorphic compilation

Every Moonlift function, region, block, continuation, and value has concrete
types when it reaches typecheck/lowering. No runtime type dispatch in compiled
code.

### 7. Flat backend commands

The compilation target is a flat, verifiable array of `BackCmd` variants.
No nested IR trees, no mutable builder state, no hidden side effects.

---

*Moonlift: typed data, jump-first control, native code.*
