# Moonlift — Agent Guidance

Moonlift is a **typed, jump-first compiled language embedded in LuaJIT** that
generates native code through Cranelift. Lua is the metaprogramming layer;
Moonlift is the monomorphic native output.

The authoring surface is the **DSL** (`require("moonlift.dsl")`). You write
Moonlift declarations as ordinary Lua table expressions — no parser, no
antiquotes, no string quoting. The DSL normalizes Lua tables into typed ASDL
and feeds the same compilation pipeline.

## Build

```sh
make                                    # produces target/release/libmoonlift.so
cargo build --release                   # produces target/release/libmoonlift.so
```

`libmoonlift.so` is loaded by `lua/moonlift/back_jit.lua` via FFI. Build
`--release` before running tests.

## Setup

```sh
git submodule update --init --recursive  # LuaJIT + TinyCC
make libtcc                              # repo-local libtcc for C backend tests
luajit -v                                # must have FFI support
```

All scripts set `package.path` to include `./lua/?.lua`.

## Run DSL files (.mld.lua)

```sh
# From Lua
local moon = require("moonlift")
local add_val = moon.loadstring([[
    local add = fn("add", { a = i32, b = i32 }, i32)
        return a + b
    end
    return add
]], "demo.mld.lua")()
local compiled = add_val:compile()
print(compiled(3, 4))  -- 7

# Cross-file require
local dsl = require("moonlift.dsl")
dsl.install_searcher()           -- so plain require() finds .mld.lua
local header = require("math_header")  -- finds math_header.mld.lua

# LSP
luajit lsp.lua
```

## Test

Tests under `tests/`, grouped by compiler boundary. No test framework —
each is a standalone script, with `tests/run.lua` for suites:

```sh
luajit tests/run.lua                              # stable default suite
luajit tests/run.lua frontend
luajit tests/run.lua backend
luajit tests/backend/test_back_add_i32.lua             # Cranelift JIT path
luajit tests/backend/test_back_object_emit.lua          # Object file emission
luajit tests/frontend/test_dsl_lua_owned.lua            # DSL integration test
luajit tests/lsp/test_lsp_integrated.lua                 # Full LSP integration
```

## Benchmarks

```sh
luajit benchmarks/bench_llpvm_image_load.lua          # LLPVM image loading
```

## Architecture

- **`lua/moonlift/dsl/`** — DSL authoring surface: `fn`, `struct`, `region`, `emit`, `jump`,
  etc. as Lua heads. Normalizes Lua tables → MoonSyntax ASDL → MoonTree ASDL.
- **`lua/moonlift/`** — compiler pipeline: PVM/ASDL framework (~80+ modules),
  typechecker, lowering, validation, LSP, linker
- **`lua/llpvm/`** — official Low-Level PVM API surface: no-parens Lua
  authoring, direct borrowed bytecode images, runtime FFI wrapper, and native
  Moonlift/C blob implementation under `lua/llpvm/native/`
- **`src/`** — Rust Cranelift backend: JIT (`lib.rs`), object emission (`lib.rs`),
  FFI surface (`ffi.rs`)
- **`lua/moonlift/pvm.lua`** — recording phase boundary: ASDL context, phases,
  triplets driving all compilation
- **`lua/moonlift/back_jit.lua`** — Lua-side JIT bridge (loads libmoonlift.so)
- **`lua/moonlift/ast.lua`** — low-level ASDL node constructor API
- **`lib/`** — standard library (`region_compose.lua` PEG combinators)
- **`build.rs`** — generates `src/embedded_hosted_lua.rs` (Lua modules
  embedded as LuaJIT bytecode)

Compilation pipeline:
DSL tables → MoonSyntax ASDL (via `syntax_lower.lua`) → MoonTree ASDL →
tree_typecheck → tree_to_code → code_* facts/kernel/schedule → lower_to_back →
back_validate → back_jit / back_object / back_object + link_target

## Key documentation

| Doc | Description |
|-----|-------------|
| `README.md` | Full project README with examples, benchmarks, philosophy |
| `lua/moonlift/dsl/LANGUAGE_REFERENCE.md` | **Complete DSL reference** — types, modules, functions, control regions, fragments, host decls, memory/resource model, view ABI, vectorization, builder API, metaprogramming guide |
| `OWNED_CFG_DESIGN.md` | Final `owned T` CFG resource discipline — handles, leases, emit transfer, disallowed aggregates, diagnostics |
| `CONVENTIONS.md` | Naming, file organization, headers vs implementations, handles, generations, stores, protocol naming |
| `SOURCE_GRAMMAR.md` | Jump-first source grammar contract |
| `PROTOCOL_SYNTAX.md` | Named protocol exits (tagged-union region exit protocols) |
| `PVM_GUIDE.md` | Complete PVM guide — ASDL contexts, structural update, triplets |
| `LLPVM_GUIDE.md` | Complete LLPVM guide — bytecode-fed native VM substrate, direct borrowed images, streams, phases, recordings, C blob ABI |
| `COMPILER_PATTERN.md` | Interactive software as compilers philosophy |
| `THE_MOONLIFT_DESIGN_BIBLE.md` | Full design philosophy — dual trees, products/sums, DSL integration |

## Language cheatsheet

### Types (via DSL)

```
Scalars:  void  bool  i8 i16 i32 i64  u8 u16 u32 u64  f32 f64  index
Pointers: ptr(T)
Views:    view(T)
Leases:   lease ptr(T)
Owned:    owned(Handle)
Handles:  handle(Name, u64, 0)
Structs:  struct(Name, { a = T1, b = T2 })
Unions:   union(Name, { ok = T, err = T })
Func:     func_type({ i32, i32 }, i32)
Closure:  closure_type({ i32 }, i32)
```

### Functions

```lua
local add = fn("add", { a = i32, b = i32 }, i32)
    return a + b
end
```

### Regions

```lua
local scan = region("scan",
    { p = ptr(u8), n = i32, target = i32 },
    { hit = { pos = i32 }, miss = { pos = i32 } }
)
entry("loop", { i = i32(0) })
    if i >= n then jump .miss { pos = i } end
    if as(i32, p[i]) == target then jump .hit { pos = i } end
    jump .loop { i = i + 1 }
end
end
```

### Emit (zero-cost CFG splice)

```lua
emit scan(p, n, 65; hit = found, miss = not_found)
```

### Contracts

```lua
local add_checked = fn("add_checked", { a = i32, b = i32 }, i32)
    requires {
        noalias(a),
        noalias(b),
    }
    return a + b
end
```

## Design philosophy

- **Co-author two typed structures**: data types (type forest) + control types
  (continuation signatures). Both are checked.
- **Regions bridge the two**: runtime params are data types; continuations are
  control types.
- **Compose with regions, seal with functions**: `emit` is zero-cost CFG splicing
  (inline, no call overhead).
- **Lua is metaprogramming**: generics, templates, codegen live in Lua. Moonlift
  receives monomorphic result.
- **ASDL is the architecture**: all meaningful compilation state is interned,
  immutable ASDL values. No hidden state in strings, callbacks, or side tables.
- **PVM phases are auto-cached memoization boundaries**: edit one subtree, only
  that subtree recompiles.
- **Flat backend commands**: compilation target is `BackCmd[]` — flat, verifiable,
  no nested IR trees.
- **Fail fast, fail loud**: assertions at boundaries, no silent fallbacks.

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
| `lsp.lua` | LSP server entry point |
| `lua/moonlift/dsl/init.lua` | DSL authoring surface — Lua heads → MoonSyntax ASDL |
| `lua/moonlift/pvm.lua` | Phase Virtual Machine — recording triplet framework |
| `lua/llpvm/init.lua` | Official LLPVM Lua API facade |
| `lua/llpvm/native/llpvm_abi.mlua` | LLPVM native C ABI seals over typed regions |
| `lua/llpvm/native/build_c.lua` | LLPVM C blob/header artifact builder |
| `lua/moonlift/back_jit.lua` | Lua→Rust JIT FFI bridge |
| `lua/moonlift/ast.lua` | Low-level ASDL node constructor API |
| `lua/moonlift/syntax_lower.lua` | MoonSyntax → MoonTree lowering |
| `lua/moonlift/frontend_pipeline.lua` | Full lowering pipeline (typecheck→codegen) |
| `src/lib.rs` | Full Cranelift backend (JIT + object emission) |
| `src/ffi.rs` | C FFI exports for LuaJIT interop (binary wire format) |
| `lua/moonlift/back_command_binary.lua` | Flatline v4 binary wire format encoder |
| `BACK_WIRE_FORMAT.md` | Binary wire format specification (Flatline v4) |
