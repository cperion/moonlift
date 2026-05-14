# Moonlift Core Stabilization Plan

Moonlift must be able to express the LuaJIT-grade VM directly: typed regions for control flow, funcs for pure data access, typed protocol exits, reusable module-level definitions, and explicit low-level memory operations. This document records the stabilization architecture so VM work does not accumulate parser/module workarounds.

## Principles

- `.mlua` is host metaprogramming; Moonlift syntax is parsed by Moonlift, not by keyword-depth guesses.
- Module dependencies follow the Lua model: host-time module tables, no Moonlift `import` keyword.
- Qualified module-table fields are compile-time constants/types/functions/regions, never runtime Lua lookups.
- `region` is the unit of control flow. `func` is for pure computation and layout accessors.
- Constants are folded before backend lowering, including switch cases.
- Pointer arithmetic and pointer/integer casts are explicit VM-grade primitives.

## Stabilization milestones

### S0: Parser and island robustness

- Parenthesize every generated island expression so host Lua never depends on newline continuation.
- Replace fragile switch-case depth accounting with structural opener tracking: cases are not `end`-delimited; nested forms inside cases are tracked by their own openers.
- Treat semicolons as statement/module item separators.
- Support compact function bodies such as `func f() -> i32 return 1 end`.
- Keep keyword-like field names/variant fields from being treated as island openers.

Current status: first implementation landed with regression coverage in `tests/test_mlua_stabilization.lua`.

### S1: Lua-style module tables

Target source shape:

```lua
local runtime = moon.require("tapexmem.runtime")

local vm_loop = region(ts: ptr(runtime.ThreadState); done: cont(code: i32))
entry start()
    ...
end
end

return vm_loop
```

Required semantics:

- `moon.require(name)` loads and caches a Moonlift module at host time.
- Exported `const`, `type`, `func`, `region`, and protocol/tagged-union types appear as sealed fields on the returned module table.
- `bc.BC_KSHORT`, `proto.DispatchResult`, and `ir.ir_op1` resolve statically in Moonlift islands.
- No generated runtime Lua table access is allowed.

### S2: Module-level regions

- Keep regions as `.mlua` hosted islands and compose them through Lua-held fragment values.
- Typecheck and lower exported regions.
- Allow region-to-region composition across module boundaries through RNF.
- Enforce: funcs cannot call regions; regions may call funcs and compose regions.

### S3: Const resolution and lowering

- Consts may depend on other consts and imported module-table consts.
- Named consts are valid in switch cases.
- By backend lowering, all switch keys are literals or typed variant keys.

### S4: Pointer and memory model

Add and document:

- `p + i` / `p - i` as element pointer arithmetic for `ptr(T)`.
- `ptr_add_bytes(p, n)` for byte offsets.
- `as(u64, p)` and `as(ptr(T), x)` for explicit pointer/integer casts.
- `&place` for field/index/local addresses.

### S5: Extern and indirect calls

- `extern func` calls lower to external symbols.
- Function pointer types and indirect calls are supported.
- Fallible VM calls are wrapped by regions with explicit `abort`/`error` exits.

### S6: Diagnostics

- Every parse/type/backend issue reports original file, line, column, and phase.
- `.mlua` evaluation errors include island kind and source span.
- `run_mlua.lua` supports compile-only/module-only files without requiring `main`.

### S7: ~~Fix `var` mutation in conditional branches~~ **FIXED**

`var x: i32 = 0` followed by `if cond then x = 5 end` previously left `x` always at 0
because:

1. `place_store_to_back[PlaceRef]` silently dropped assignments to `BindingClassLocalCell`
   bindings (used the wrong `pvm.classof` comparison — `LocalCell` is a unit variant
   so direct equality `binding.class == Bn.BindingClassLocalCell` must be used, not
   `pvm.classof(binding.class) == Bn.BindingClassLocalCell`).

2. `lower_if_stmt` restored `env.locals` to the pre-branch snapshot after both
   branches, discarding any mutations. Fixed by:
   - Tracking which `LocalCell` bindings changed in each branch.
   - Emitting `CmdAppendBlockParam` on the join block for each mutated binding.
   - Patching the branch `CmdJump` calls to pass the correct SSA values.
   - Binding the join block's param value in the post-if env.

Nested ifs are handled correctly because each `lower_if_stmt` call propagates
mutations outward, and the outer if sees the phi results from inner ifs.


Every stabilization bug gets a test before or with the fix. Current parser/island tests cover:

- semicolon item separators
- compact exported funcs
- large modules with 64 exports
- Lua-style string module names
- nested `if` inside `switch case` inside a region island
