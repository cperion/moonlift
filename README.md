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
| **Resource discipline** | Handles are durable identity, leases are temporary access, and `owned T` is explicit CFG discharge authority. No hidden destructors. |
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
local function literal_arm(text, tag)
    local bytes = { text:byte(1, #text) }
    local lines = {}
    lines[#lines + 1] = ("if i + %d > n then jump fail() end"):format(#bytes)
    for off = 2, #bytes do
        lines[#lines + 1] = ("if as(i32, p[i + %d]) ~= %d then jump fail() end"):format(off - 1, bytes[off])
    end
    lines[#lines + 1] = "tags[meta[0]] = " .. tostring(tag)
    lines[#lines + 1] = "a[meta[0]] = 0"
    lines[#lines + 1] = "b[meta[0]] = 0"
    lines[#lines + 1] = "nums[meta[0]] = 0.0"
    lines[#lines + 1] = "meta[0] = meta[0] + 1"
    lines[#lines + 1] = ("jump done(next_i = i + %d)"):format(#bytes)
    return { raw_key = tostring(bytes[1]), body = moon.stmts(table.concat(lines, "\n")) }
end

local literal_arms = {
    literal_arm("true",  8),
    literal_arm("false", 9),
    literal_arm("null",  10),
}

-- Bind values, then quote: moon.func { values } [[ source ]]
local parse_value = moon.func { literal_arms = literal_arms } [[
parse_value(p: ptr(u8), n: i32, pos: i32, tags: ptr(i32), a: ptr(i32),
            b: ptr(i32), nums: ptr(f64), meta: ptr(i32)): i32
    return region: i32
    entry start()
        switch as(i32, p[i]) do
        @{literal_arms...}
        case 34 then emit parse_string_event(...)
        default then emit parse_number_event(...)
        end
    end
    ...
end
]]
```

See `examples/json/json_lua_stack_decoder.mlua` for the JSON showcase: a
library-shaped decoder/encoder that emits a full C backend blob. Its canonical
decode path builds a typed Moonlift value-event tape first, then projects that
explicit value stream to Lua while preserving JSON null and array/object shape.

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
- LuaJIT with FFI support

### Build

```bash
git clone https://github.com/your-org/moonlift.git
cd moonlift
git submodule update --init --recursive
make libtcc
make
```

Produces a fully static binary at `target/release/moonlift`:
- Embeds the Moonlift Lua staging layer via `include_str!`
- Links vendored LuaJIT statically (from `.vendor/LuaJIT/`)
- Links the Rust/Cranelift backend in-process
- No runtime dependencies beyond libc

`make libtcc` builds the vendored TinyCC submodule under `deps/tinycc/.local`.
The C emission tests use this repo-local `libtcc.so` for in-memory callable C
backend coverage.

### Run a `.mlua` file

```bash
target/release/moonlift examples/json/json_lua_stack_decoder.mlua
```

The JSON example returns a Lua library table with `decode`, `decode_or_nil`,
`encode`, `valid`, `new_decoder`, `c_blob`, `c_header`, `c_api`, and
`emcc_args`. Its native parser emits a Lua-free C API, prefers a GCC `-O3`
shared artifact for local execution, and can be compiled for the browser with
Emscripten. In WASM, the output buffers map directly to JS typed arrays:
`Int32Array` for event tags/slices/meta, `Float64Array` for numbers, and
`Uint8Array` for source and decoded string bytes.

### Compile to a native object file

```lua
-- From Lua: moon.emit_object(source, "build/out.o")
local moon = require("moonlift")
local obj_bytes = moon.emit_object(source, "build/out.o")
```

### Quick validation

```bash
luajit tests/run.lua                              # Stable default suite
luajit tests/backend/test_back_add_i32.lua          # Bare Cranelift JIT path
luajit tests/frontend/test_mlua_asdl_host_model.lua  # .mlua hosted island bridge
luajit tests/frontend/test_parse_typecheck.lua       # Parse + typecheck pipeline
luajit tests/lsp/test_lsp_integrated.lua             # Full LSP integration
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

```moonlift
handle SessionRef : u64 invalid 0 end
handle VoiceRef : u32 invalid 0 domain VoiceStore target VoiceState end
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

```moonlift
region my_region(params...; exit_a(sig...) | exit_b(sig...))
entry start()
    emit other_fragment(args...; out = exit_a)
end
end
```

Compose regions with `emit`. The caller decides what each exit means.

`emit` is also the ownership-carrying composition form. If an emitted region
returns ownership on a continuation, the filled target must declare a matching
`owned` parameter:

```moonlift
region close_session(app: ptr(App), s: owned SessionRef;
    closed()
  | missing(s: owned SessionRef))
end

block retry(s: owned SessionRef)
    emit close_session(app, s; closed = done, missing = retry)
end
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
In `.mlua` files, function and region headers can also be implemented without
explicit long-bracket calls:

```lua
local add_h = func add(a: i32, b: i32): i32 end
local add = func add_h
    return a + b
end

local scan_h = region scan(; done) end
local scan = region scan_h
entry start()
    jump done()
end
end
```

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

### JSON value-event benchmark

Moonlift's hosted JSON showcase parses JSON in typed native kernels and
materializes those kernels as a C backend blob. The canonical `.mlua` library
constructs a Moonlift-owned value-event tape for `null`, booleans, numbers,
strings, arrays, objects, and object keys. The raw benchmark measures that
typed-array-shaped event API. A separate benchmark line measures full Lua object
projection, which is the fair comparison against decoders that return Lua
tables. The C blob itself has no Lua dependency.

Benchmarked against **lua-cjson**, **dkjson**, and pure Lua on a realistic
2.9 KB payload with 50 user records:

```bash
luajit benchmarks/bench_json_stack_decode.lua          # quick
luajit benchmarks/bench_json_stack_decode.lua full     # full
```

The JSON showcase lives in `examples/json/json_lua_stack_decoder.mlua` and
exports the generated C source, a small C header, tag constants, and Emscripten
export flags.

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
│   ├── tree_to_code.lua        Tree → normalized MoonCode
│   ├── code_to_back.lua        MoonCode → flat backend commands
│   ├── lower_to_back.lua       Kernel/Code lowering → backend commands
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
│   ├── json/                   C-backed JSON library showcase + stack benchmark
│   ├── protocols/              RESP parser example
│   └── terra_vs_mlua/          Terra comparison
├── benchmarks/                 Performance benchmarks
├── tests/                      Lua test suite (~130+ tests)
├── LANGUAGE_REFERENCE.md       Complete language reference
├── OWNED_CFG_DESIGN.md         Linear owned/handle/lease design
├── CONVENTIONS.md              Naming and file organization conventions
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
| [`OWNED_CFG_DESIGN.md`](OWNED_CFG_DESIGN.md) | **Owned CFG resource discipline.** Final rules for `owned T`, handles, leases, emit transfer, disallowed aggregates, and diagnostics. |
| [`CONVENTIONS.md`](CONVENTIONS.md) | **Project conventions.** Naming, headers vs implementations, handles, generations, stores, and protocol naming. |
| [`BACK_WIRE_FORMAT.md`](BACK_WIRE_FORMAT.md) | **Flatline v4 binary wire format.** The stable ABI between the Lua frontend and the Rust Cranelift backend. |
| [`PVM_GUIDE.md`](PVM_GUIDE.md) | **Complete PVM guide.** ASDL contexts, structural update, recording-triplet phases, pull-driven evaluation, the triplet algebra. |
| [`COMPILER_PATTERN.md`](COMPILER_PATTERN.md) | **Interactive software as compilers.** The philosophy behind Moonlift's architecture: ASDL as the input language, live compilation, memoized phase boundaries. |
| [`explicit_programming.md`](explicit_programming.md) | **Explicit programming philosophy.** A guide to designing systems with typed data types and typed control protocols. |

---

## Testing

Moonlift has 240+ tests grouped by compiler boundary under `tests/`.

```bash
luajit tests/run.lua              # Stable default suite
luajit tests/run.lua frontend
luajit tests/run.lua backend
luajit tests/run.lua all          # Includes optional/retired suites
```

### Parser + typechecker

```bash
luajit tests/frontend/test_parse_typecheck.lua
luajit tests/frontend/test_parse_kernels.lua
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

### Kernel lowering

```bash
luajit tests/code_ir/test_code_flow_facts.lua
luajit tests/code_ir/test_code_mem_facts.lua
luajit tests/code_ir/test_code_kernel_plan.lua
luajit tests/code_ir/test_code_lower_plan.lua
```

### Metaprogramming and splice tests

```bash
luajit tests/frontend/test_spread_splice_lists.lua
luajit tests/frontend/test_spread_splice_regions.lua
luajit tests/host/test_host_metaprogramming_patterns.lua
luajit tests/host/test_host_struct_values.lua
luajit tests/host/test_host_stmt_list_builder.lua
luajit tests/frontend/test_parse_spread_splice.lua
luajit tests/frontend/test_region_frag_runtime_param_call.lua
luajit tests/frontend/test_direct_mutual_recursion.lua
luajit tests/host/test_host_extern_symbol.lua
```

### `.mlua` integration tests

```bash
luajit tests/frontend/test_mlua_splice_shapes.lua
luajit tests/frontend/test_mlua_asdl_host_model.lua
luajit tests/frontend/test_mlua_diagnostics.lua
target/release/moonlift examples/json/json_lua_stack_decoder.mlua
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

### 6. Monomorphic compilation

Every Moonlift function, region, block, continuation, and value has concrete
types when it reaches typecheck/lowering. No runtime type dispatch in compiled
code.

### 7. Flat backend commands

The compilation target is a flat, verifiable array of `BackCmd` variants.
No nested IR trees, no mutable builder state, no hidden side effects.

---

*Moonlift: typed data, jump-first control, native code.*
