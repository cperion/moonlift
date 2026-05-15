# Moonlift — Agent Guidance

Moonlift is a **typed, jump-first compiled language embedded in LuaJIT** that
generates native code through Cranelift. Lua is the metaprogramming layer;
Moonlift is the monomorphic native output.

## Build

```sh
make                                    # produces fully static target/release/moonlift and target/release/mom
cargo build --release                   # produces target/release/libmoonlift.so plus binaries
```

`libmoonlift.so` is loaded by `lua/moonlift/back_jit.lua` via FFI. Build
`--release` before running tests. The standalone `moonlift` binary embeds the
compiler (195 Lua sources via `include_str!`) + vendored LuaJIT — zero runtime
deps.

## Setup

```sh
git submodule update --init    # for .vendor/LuaJIT
luajit -v                      # must have FFI support
```

All scripts set `package.path` to include `./lua/?.lua`.

## Run .mlua files

```sh
target/release/mom run --call main file.mlua   # standalone MOM binary
target/release/moonlift file.mlua              # standalone Lua frontend binary
luajit run_mlua.lua file.mlua                  # via LuaJIT runner
luajit emit_object.lua input.mlua -o out.o     # compile to .o
luajit emit_shared.lua input.mlua -o out.so    # compile to .so
luajit lsp.lua                                 # LSP server (stdio)
```

## Test

~130+ tests under `tests/`. No test framework — each is a standalone script:

```sh
luajit tests/test_back_add_i32.lua             # Cranelift JIT path
luajit tests/test_back_object_emit.lua          # Object file emission
luajit tests/test_mlua_host_pipeline.lua        # .mlua hosted island bridge
luajit tests/test_parse_typecheck.lua           # Parse + typecheck pipeline
luajit tests/test_parse_kernels.lua             # Jump-first kernel suite
luajit tests/test_lsp_integrated.lua            # Full LSP integration

## MOM tests

luajit tests/test_mom_groundwork.lua            # MOM compiler foundation
luajit tests/test_mom_native_lexer.mlua         # Native lexer
luajit tests/test_mom_native_core.lua           # Native parser core
luajit tests/test_mom_native_ast.lua            # Native AST verification
luajit tests/test_mom_check_correctness.mlua    # Schema correctness
luajit tests/test_mom_vec.lua                   # Vectorization pipeline
luajit tests/test_mom_wire.lua                  # MLBT v3 wire format
luajit tests/test_mom_source_to_binary.lua      # End-to-end: source to executable
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

When working under `lua/moonlift/mom/`, also read `lua/moonlift/mom/AGENTS.md`.
It contains stricter MOM-specific discipline for the native compiler port,
including the no-escape-hatch/no-"for now" framing rule, module organization,
and required verification boundaries.

| Doc | Description |
|-----|-------------|
| `README.md` | Full project README with examples, benchmarks, philosophy |
| `LANGUAGE_REFERENCE.md` | **Complete language reference** (3057 lines) — types, modules, functions, control regions, fragments, host decls, view ABI, vectorization, builder API, metaprogramming guide |
| `SOURCE_GRAMMAR.md` | Jump-first source grammar contract |
| `PROTOCOL_SYNTAX.md` | Named protocol exits (tagged-union region exit protocols) |
| `PVM_GUIDE.md` | Complete PVM guide — ASDL contexts, structural update, triplets |
| `COMPILER_PATTERN.md` | Interactive software as compilers philosophy |

## Language cheatsheet

### Types
```
Scalars:  void  bool  i8 i16 i32 i64  u8 u16 u32 u64  f32 f64  index
Pointers: ptr(T)
Views:    view(T)         -- (data, len, stride) descriptor
Structs:  struct Name f: T; ... end
Unions:   union Name a(T) | b(T) end
Func:     func(i32, i32) -> i32        -- function pointer type
Closure:  closure(i32) -> i32          -- closure type (function + context)
```

### Functions
```moonlift
func add(a: i32, b: i32) -> i32
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
return region -> i32
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
            hit: cont(pos: i32),
            miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end

-- Use via emit (zero-cost CFG splice, not a call)
emit scan(p, n, 65; hit = found, miss = not_found)
```

### Expression fragments
```moonlift
expr clamp(x: i32) -> i32
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
extern write(fd: i32, buf: ptr(u8), count: index) -> index end
extern host_add7(x: i32) -> i32 as "host_add7_impl" end
```

### JIT: Compile and call native functions from Lua
```lua
local Host = require("moonlift.mlua_run")
local chunk = Host.loadstring([[
local add = func(a: i32, b: i32) -> i32
    return a + b
end
return add
]], "demo.mlua")
local add_val = chunk()
local compiled = add_val:compile()
print(compiled(3, 4))  -- 7, running as native machine code
compiled:free()
```

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

## Key files

| File | Purpose |
|------|---------|
| `init.lua` | Package init — sets `package.path` and loads facade |
| `run_mlua.lua` | `.mlua` runner entry point |
| `lsp.lua` | LSP server entry point |
| `lua/moonlift/pvm.lua` | Phase Virtual Machine — recording triplet framework |
| `lua/moonlift/back_jit.lua` | Lua→Rust JIT FFI bridge |
| `lua/moonlift/host.lua` | High-level Lua builder API |
| `lua/moonlift/ast.lua` | Low-level ASDL node constructor API |
| `src/lib.rs` | Full Cranelift backend (JIT + object emission) |
| `src/main.rs` | Standalone `moonlift` binary (embeds Lua compiler) |
| `src/ffi.rs` | C FFI exports for LuaJIT interop (text tape + binary wire format) |
| `lua/moonlift/back_command_binary.lua` | MLBT v3 binary wire format encoder (replaces text tape) |
| `BACK_WIRE_FORMAT.md` | Binary wire format specification (MLBT v3) |
| `lua/moonlift/back_command_tape.lua` | Legacy text tape encoder (kept for CI cross-check) |
| `lua/moonlift/host_mom.lua` | MOM frontend `moon.mom()` API — source → native compiler → executable |
| `lua/moonlift/mom/` | MOM compiler modules (runtime, parser, back, vec, driver, schema) |
