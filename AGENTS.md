# Moonlift — Agent Guidance

Moonlift is a **typed, jump-first compiled language embedded in LuaJIT** that
generates native code through Cranelift. Lua is the metaprogramming layer;
Moonlift is the monomorphic native output.

## Build

```sh
make                                    # produces fully static target/release/moonlift
cargo build --release                   # produces target/release/libmoonlift.so plus binaries
```

`libmoonlift.so` is loaded by `lua/moonlift/back_jit.lua` via FFI. Build
`--release` before running tests. The standalone `moonlift` binary embeds the
compiler (195 Lua sources via `include_str!`) + vendored LuaJIT — zero runtime
deps.

## Setup

```sh
git submodule update --init --recursive  # LuaJIT + TinyCC
make libtcc                              # repo-local libtcc for C backend tests
luajit -v                                # must have FFI support
```

All scripts set `package.path` to include `./lua/?.lua`.

## Run .mlua files

```sh
# Hosted pipeline (LuaJIT-mediated, default)
target/release/moonlift file.mlua
target/release/moonlift run --call main file.mlua

# From Lua
local moon = require("moonlift")
moon.loadstring(src)            -- hosted JIT
moon.loadfile(path)            -- hosted JIT
moon.emit_object(src, path)    -- emit .o bytes
moon.emit_shared(src, path)    -- emit .so/.dylib bytes

# LSP
luajit lsp.lua
```

## Test

240+ tests under `tests/`, grouped by compiler boundary. No test framework —
each is a standalone script, with `tests/run.lua` for suites:

```sh
luajit tests/run.lua                              # stable default suite
luajit tests/run.lua frontend
luajit tests/run.lua backend
luajit tests/backend/test_back_add_i32.lua             # Cranelift JIT path
luajit tests/backend/test_back_object_emit.lua          # Object file emission
luajit tests/frontend/test_mlua_asdl_host_model.lua      # .mlua hosted island bridge
luajit tests/frontend/test_parse_typecheck.lua           # Parse + typecheck pipeline
luajit tests/frontend/test_parse_kernels.lua             # Jump-first kernel suite
luajit tests/lsp/test_lsp_integrated.lua                 # Full LSP integration
```

## Benchmarks

```sh
luajit benchmarks/bench_json_stack_decode.lua [full]   # JSON decoder benchmark
luajit benchmarks/bench_compile_back_validate_ll.lua     # Compilation profiling
benchmarks/run_vs_terra.sh [quick]                      # Compare with Terra
luajit benchmarks/bench_host_arena_abi.lua               # Arena ABI performance
luajit benchmarks/bench_host_arena_native.lua            # Native host type access
```

## Architecture

- **`lua/moonlift/`** — compiler frontend: PVM/ASDL framework (~80+ modules),
  parser, typechecker, tree-to-back lowering, validation, LSP, linker
- **`src/`** — Rust Cranelift backend: JIT (`lib.rs`), standalone binary
  (`main.rs`), object emission (`lib.rs`), host arena, FFI surface (`ffi.rs`)
- **`lua/moonlift/pvm.lua`** — recording phase boundary: ASDL context, phases,
  triplets driving all compilation
- **`lua/moonlift/back_jit.lua`** — Lua-side JIT bridge (loads libmoonlift.so)
- **`lua/moonlift/host.lua`** — high-level Lua builder API
- **`lua/moonlift/ast.lua`** — low-level ASDL node constructor API
- **`lib/`** — standard library (`region_compose.lua` PEG combinators)
- **`build.rs`** — generates `src/embedded_lua.rs` (all Lua sources via
  `include_str!`)

Compilation pipeline:
`.mlua` → parse/scan_document → tree_typecheck → tree_to_back →
back_validate → back_jit / back_object / back_object + link_target

## Key documentation

When working under `experiments/lua_interpreter_vm/spongejit/`, also read
`experiments/lua_interpreter_vm/spongejit/AGENTS.md`. It contains the current
LuaCompile/SpongeJIT architecture discipline and retired-name guardrails.

| Doc | Description |
|-----|-------------|
| `README.md` | Full project README with examples, benchmarks, philosophy |
| `LANGUAGE_REFERENCE.md` | **Complete language reference** — types, modules, functions, control regions, fragments, host decls, memory/resource model, view ABI, vectorization, builder API, metaprogramming guide |
| `OWNED_CFG_DESIGN.md` | Final `owned T` CFG resource discipline — handles, leases, emit transfer, disallowed aggregates, diagnostics |
| `CONVENTIONS.md` | Naming, file organization, headers vs implementations, handles, generations, stores, protocol naming |
| `SOURCE_GRAMMAR.md` | Jump-first source grammar contract |
| `PROTOCOL_SYNTAX.md` | Named protocol exits (tagged-union region exit protocols) |
| `PVM_GUIDE.md` | Complete PVM guide — ASDL contexts, structural update, triplets |
| `COMPILER_PATTERN.md` | Interactive software as compilers philosophy |

## Language cheatsheet

Syntax mirrors Moonlift's two categories: commas separate product-shaped lists
(fields, params, payload fields, fill maps), while `|` separates semantic
alternatives (union variants and region continuation exits).

### Types

```
Scalars:  void  bool  i8 i16 i32 i64  u8 u16 u32 u64  f32 f64  index
Pointers: ptr(T)
Views:    view(T)         -- (data, len, stride) descriptor
Leases:   lease ptr(T)    -- temporary access fact; may not escape
Owned:    owned HandleRef -- CFG discharge authority; no Drop, no inference
Handles:  handle Name : u32 invalid 0 [domain Store] [target Item] end
Structs:  struct Name f: T, ... end
Unions:   union Name a(T) | b(T) end
Func:     func(i32, i32): i32        -- function pointer type
Closure:  closure(i32): i32          -- closure type (function + context)
```

### Functions

```moonlift
func add(a: i32, b: i32): i32
    return a + b
end
```

Parameters may carry modifiers: `noalias readonly writeonly`.

### Control — no for/while/break/continue

Only `block`/`jump`/`yield`/`return`/`emit`/`switch`:

```moonlift
-- Loop via typed block with jump
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end

-- Multi-block region
return region: i32
entry start()
    jump loop(i = 0, acc = 0)
end
block loop(i: index, acc: i32)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end
end
```

### Regions — typed control fragments

```moonlift
region scan(p: ptr(u8), n: i32, target: i32;
            hit(pos: i32)
          | miss(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end

-- Use via emit (zero-cost CFG splice, not a call)
emit scan(p, n, 65; hit = found, miss = not_found)
```

### Handles, leases, owned

```moonlift
handle SessionRef : u64 invalid 0 end

region close_session(app: ptr(App), s: owned SessionRef;
            closed()
          | missing(s: owned SessionRef))
end

region borrow_session(app: ptr(App), s: SessionRef;
            borrowed(session: lease ptr(Session))
          | stale()
          | missing())
end
```

Handles are copyable durable identity. Leases are temporary access granted by
typed protocols. `owned T` is mandatory discharge authority carried through CFG:
consume it, return/yield it, or transfer it to another `owned` parameter exactly
once. `owned` does not grant access; use resolver regions for leases. `emit` is
the region composition form that can carry owned continuation payloads.

Rejected by design: `var owned T`, owned fields, owned aggregates,
`owned ptr(T)`, `owned lease T`, passing `owned T` as plain `T`, and
expression-style region calls whose continuation payload contains `owned`.

### Expression fragments

```moonlift
expr clamp(x: i32): i32
    select(x < 0, 0, x)
end

-- Use: let v = emit clamp(val)
```

### Bindings

```moonlift
let x: i32 = 42    -- immutable (SSA-like)
var i: index = 0   -- mutable (stack-backed)
```

### Conversion

```moonlift
as(i32, u8_val)    -- only conversion form: extend/truncate/bitcast/fp convert
```

### Splices — `@{lua_expr}` embeds Lua values into Moonlift source

Evaluated at `.mlua` load time:

- Type position: `let x: @{T} = 0`
- Fragment position: `emit @{frag}(args; ok = done)`
- Name position: `region @{name}(...)` (must be whole token)
- Expression: `if x > @{limit} then ...`
- Spread: `@{list...}` expands a Lua array into a syntactic list

### Extern imports

```moonlift
extern write(fd: i32, buf: ptr(u8), count: index): index end
extern host_add7(x: i32): i32 as "host_add7_impl" end
```

### Hosted JIT: compile and call from Lua

```lua
local moon = require("moonlift")
local add_val = moon.loadstring([[
local add = func(a: i32, b: i32): i32
    return a + b
end
return add
]], "demo.mlua")()
local compiled = add_val:compile()
print(compiled(3, 4))  -- 7, running as native machine code
compiled:free()
```

### Unified API — `require("moonlift")` module

Hosted-Lua pipeline:

- `moon.loadstring(src [, name [, opts]])` — compile and return chunk
- `moon.loadfile(path [, opts])` — compile and return chunk from file
- `moon.dofile(path [, opts, ...])` — compile, load, and call
- `moon.eval(src, ...)` — shorthand: compile string, call immediately

Object emission (hosted pipeline):

- `moon.emit_object(src [, path [, name]])` — emit .o bytes
- `moon.emit_shared(src [, path [, name]])` — emit .so/.dylib bytes

Inside `.mlua` files, the `moon` table provides:
`moon.require`, `moon.emit_object`, and hosted pipeline helpers.

## Design philosophy

- **Co-author two typed structures**: data types (type forest) + control types
  (continuation signatures). Both are checked.
- **Regions bridge the two**: runtime params are data types; continuations are
  control types.
- **Compose with regions, seal with functions**: `emit` is zero-cost CFG splicing
  (inline, no call overhead).
- **Lua is metaprogramming**: generics, templates, codegen live in Lua. Moonlift
  receives monomorphic result. No source-level generics (no angle brackets).
- **ASDL is the architecture**: all meaningful compilation state is interned,
  immutable ASDL values. No hidden state in strings, callbacks, or side tables.
- **PVM phases are auto-cached memoization boundaries**: edit one subtree, only
  that subtree recompiles.
- **Flat backend commands**: compilation target is `BackCmd[]` — flat, verifiable,
  no nested IR trees.
- **Fail fast, fail loud**: assertions at boundaries, no silent fallbacks.

## Why Moonlift is grep-shaped

Because control structure is syntactic, dumb text tools become smart:

```bash
rg '^region '           # API surface: every operation that exists
rg '^\s*block '         # States: every state machine state
rg '\bjump '            # Transitions: every CFG edge in the system
rg '\bemit '            # Composition: who uses which region
```

Each answer is complete, not a heuristic. No hidden exception edges,
no implicit async state machines, no callback conventions, no vtable
dispatch. The control graph is in the source text, not behind compiler
passes or runtime dispatch tables.

This means you can:

- Map error paths from source alone: `rg '\b(err|bad|fail|closed)\b'`
- Trace composition: `rg 'emit read_loop'` finds every user of that region
- Extract state machines: `rg '^\s*block '` lists all states with their params
- Verify protocol completeness: every continuation at an `emit` site is named

Explicit programming makes plain-text tooling powerful again.

## Non-negotiable rules

1. No Moonlift source generics — Lua is where genericity lives
2. No angle-bracket type arguments — only `as(T, value)` for conversions
3. Explicit ASDL meaning — no hiding semantics in strings or callbacks
4. Monomorphic object code — all types resolved before backend
5. No for/while/break/continue — jump-first control only
6. Every block path must terminate (jump/yield/return)
7. No fallthrough in switch — every case is an independent branch
8. Switch requires a default arm
9. `owned T` must be discharged or transferred exactly once by typed CFG
10. No owned aggregates, owned fields, `var owned T`, or `owned ptr(T)`
11. Region calls cannot carry lease or owned continuation payloads; use `emit`
12. Commas are for product-shaped lists; `|` is for semantic alternatives

## Key files

| File | Purpose |
|------|---------|
| `init.lua` | Package init — sets `package.path` and loads facade |
| `run_mlua.lua` | `.mlua` runner (superseded by `moonlift` binary) |
| `lsp.lua` | LSP server entry point |
| `lua/moonlift/pvm.lua` | Phase Virtual Machine — recording triplet framework |
| `lua/moonlift/back_jit.lua` | Lua→Rust JIT FFI bridge |
| `lua/moonlift/host.lua` | High-level Lua builder API |
| `lua/moonlift/ast.lua` | Low-level ASDL node constructor API |
| `src/lib.rs` | Full Cranelift backend (JIT + object emission) |
| `src/main.rs` | Standalone `moonlift` binary (embeds Lua compiler) |
| `src/ffi.rs` | C FFI exports for LuaJIT interop (binary wire format) |
| `lua/moonlift/back_command_binary.lua` | Flatline v4 binary wire format encoder |
| `BACK_WIRE_FORMAT.md` | Binary wire format specification (Flatline v4) |
