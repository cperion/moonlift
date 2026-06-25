# Fix Lalin Memory Kit — 3 remaining issues
Investigate and fix three critical issues: StmtTrap flow termination, std:memory module naming, and null(T) non-pointer type acceptance
**Started**: 2026-05-21 18:53:20
---

## Scout Output — 2026-05-21 18:55:47

Now I have all the information I need. Here's my comprehensive report.

---

## Files Retrieved

### Issue 1: StmtTrap Flow Termination

1. **`lua/lalin/tree_to_back.lua`** (lines 2137-2142) — **The fix is already applied.** The `[Tr.StmtTrap]` handler returns `Back.BackTerminates` (line 2139). Earlier context says it was `BackFallsThrough` but the current code is correct.

2. **`lua/lalin/tree_to_back.lua`** (lines 2145-2153) — `lower_body` function: the flow-propagation loop checks `if flow == Back.BackTerminates then break end` (line 2150). With `BackTerminates`, subsequent dead statements are skipped.

3. **`lua/lalin/frontend_pipeline.lua`** (lines 61-63) — The `assert_no_cmd_trap` call is gated behind `if not _G.LALIN_ALLOW_TRAP then` (line 61). The trap gate is conditional.

4. **`lua/lalin/schema/back.lua`** (line 906) — `CmdTrap` variant is defined as a zero-arg variant in the schema.

5. **`lua/lalin/back_command_binary.lua`** (lines 399-400) — `CmdTrap` encodes with wire tag `T.Trap`.

6. **`lua/lalin/back_validate.lua`** (lines 206, 487-489) — Validation treats `CmdTrap` as a function body terminator (same as `CmdReturnVoid`).

7. **`back/dasm/rules_x64.lisle`** (lines 170-172) — DynASM lowers `CmdTrap` to `int3`.

8. **`back/dasm/phases/build_cfg.lua`** (lines 105-106) — DynASM builds `DTermTrap` terminator from `CmdTrap`.

9. **`back/dasm/phases/select_mir.lua`** (lines 36-37) — DynASM selects `CmdTrap` from `DTermTrap`.

### Issue 2: `std:memory` Module Naming

1. **`build.rs`** (lines 1-87) — Module name generation: `collect(stdlib_dir, stdlib_dir.parent().unwrap(), "mlua", ...)` where base is `"."`. The `module_name` function strips base prefix, replaces `/` with `.`, producing `"stdlib.memory"`, `"stdlib.arena"`, `"stdlib.view"`.

2. **`src/embedded_hosted_lua.rs`** (lines 1-3, end of file) — Generated output confirms:
   - `("stdlib.arena", include_str!("../stdlib/arena.mlua"))`
   - `("stdlib.memory", include_str!("../stdlib/memory.mlua"))`
   - `("stdlib.view", include_str!("../stdlib/view.mlua"))`

3. **`src/main.rs`** (lines 123-132) — Registers each embedded module as `package.preload[name] = loader`. So `package.preload["stdlib.memory"]` is set.

4. **`stdlib/arena.mlua`** (line 2) — `require "stdlib.memory"` — uses `"stdlib.memory"` which matches the preload entry.

5. **`stdlib/memory.mlua`** (full file) — Defines extern `__ml_*` functions and convenience wrappers (`memcpy`, `memset`, `memcmp`, `alloc`, `free`).

6. **`stdlib/view.mlua`** (full file) — View helpers. Uses `trap` keyword but has NO `require` calls. Would need `_G.LALIN_ALLOW_TRAP` set.

7. **`lua/lalin/mlua_run.lua`** (lines 184-201) — `transform_mlua` function: treats non-island content as Lua. `require "stdlib.memory"` in `arena.mlua` stays as plain Lua, wrapped with `local lalin = require('lalin')` prefix. When no islands detected, entire source is Lua.

### Issue 3: `null(T)` Accepting Non-Pointer Types

1. **`lua/lalin/tree_typecheck.lua`** (lines 613-618) — **The fix is already applied.** The `[Tr.ExprNull]` handler checks `pvm.classof(self.elem) ~= Ty.TPtr` and emits `Tr.TypeIssueExpected("null", Ty.TPtr(Ty.TVoid), self.elem)` as an error.

2. **`lua/lalin/schema/tree.lua`** (line 1097-1102) — `TypeIssueExpected` is defined with `site`, `expected`, `actual` fields.

3. **`lua/lalin/error/catalog.lua`** (line 109) — Maps `TypeIssueExpected` → `"E0301"` (type mismatch error, severity: error).

4. **`lua/lalin/tree_typecheck.lua`** (lines 977-979) — Error formatter for `TypeIssueExpected`: produces `error[E0301]: type mismatch`.

5. **`lua/lalin/tree_to_back.lua`** (expr lowering section, lines around 607) — `ExprNull` lowering path. With the typecheck already catching the error, the lowering path only sees correctly-typed `ExprNull(ptr(T))` nodes.

6. **`lua/lalin/tree_typecheck.lua`** (lines 627-632) — `ExprIsNull` has a parallel check using `TypeIssueNotPointer` (also error).

7. **`lua/lalin/parse.lua`** (lines 82, 162-163) — Token definitions for `null_kw` (162) and `is_null_kw` (163), keywords map for `null` and `is_null`.

8. **`lua/lalin/sem_layout_resolve.lua`** (line 324-330) — Identity pass for `ExprNull` and `StmtTrap` (no resolution needed).

---

## Key Code

### Issue 1 — StmtTrap lowering (already correct):

```lua
-- lua/lalin/tree_to_back.lua:2137-2142
[Tr.StmtTrap] = function(_, env)
    return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdTrap }, Back.BackTerminates))
end,
[Tr.StmtUseRegionSlot] = function(_, env) return pvm.once(Tr.TreeBackStmtResult(env, {}, Back.BackFallsThrough)) end,
```

```lua
-- lua/lalin/tree_to_back.lua:2145-2153
lower_body = function(stmts, env)
    local current = env
    local cmds = {}
    local flow = Back.BackFallsThrough
    for i = 1, #stmts do
        if flow == Back.BackTerminates then break end
        local result = stmt_to_back:one_uncached(stmts[i], current)
        append_all(cmds, result.cmds)
        current = result.env
        flow = result.flow
    end
    return current, cmds, flow
end
```

```lua
-- lua/lalin/frontend_pipeline.lua:61-63
if not _G.LALIN_ALLOW_TRAP then
    assert_no_cmd_trap(T, program, site)
end
```

### Issue 2 — Module naming (already consistent):

```rust
// build.rs (collect for stdlib)
let stdlib_dir = Path::new("stdlib");
if stdlib_dir.exists() {
    collect(stdlib_dir, stdlib_dir.parent().unwrap(), "mlua", &mut modules);
}
```

```rust
// build.rs module_name function
fn module_name(path: &Path, base: &Path) -> String {
    let rel = path.strip_prefix(base).unwrap().with_extension("");
    let mut s = rel.to_string_lossy().replace('/', ".");
    // ... strip .init suffix, handle empty ...
    s
}
```

```rust
// Generated src/embedded_hosted_lua.rs (excerpt)
("stdlib.arena", include_str!("../stdlib/arena.mlua")),
("stdlib.memory", include_str!("../stdlib/memory.mlua")),
("stdlib.view", include_str!("../stdlib/view.mlua")),
```

```rust
// src/main.rs:123-132 — Registration in package.preload
let package = lua.globals().get::<mlua::Table>("package")?;
let preload = package.get::<mlua::Table>("preload")?;
for (name, source) in embedded_hosted_lua::embedded_modules() {
    let loader = lua.create_function(move |lua, ()| {
        let chunk = lua.load(source).set_name(name).into_function()?;
        let result: mlua::Value = chunk.call(())?;
        Ok(result)
    })?;
    preload.set(name, loader)?;
}
```

```lalin
-- stdlib/arena.mlua:2
require "stdlib.memory"   -- Lua-level require, resolves via package.preload["stdlib.memory"]
```

### Issue 3 — null(T) typecheck (already correct):

```lua
-- lua/lalin/tree_typecheck.lua:613-618
[Tr.ExprNull] = function(self, ctx)
    local issues = {}
    if pvm.classof(self.elem) ~= Ty.TPtr then
        issues[#issues + 1] = Tr.TypeIssueExpected("null", Ty.TPtr(Ty.TVoid), self.elem)
    end
    return pvm.once(result_expr(Tr.ExprNull(Tr.ExprTyped(self.elem), self.elem), self.elem, issues))
end,
```

```lua
-- lua/lalin/tree_typecheck.lua:627-632 (parallel check for is_null)
[Tr.ExprIsNull] = function(self, ctx)
    local value = pvm.one(type_expr(self.value, ctx))
    local issues = {}; append_all(issues, value.issues)
    if pvm.classof(value.ty) ~= Ty.TPtr then
        issues[#issues + 1] = Tr.TypeIssueNotPointer(value.ty)
    end
    return pvm.once(result_expr(Tr.ExprIsNull(Tr.ExprTyped(bool_ty()), value.expr), bool_ty(), issues))
end,
```

```lua
-- lua/lalin/error/catalog.lua:109
TypeIssueExpected = "E0301",   -- E0301 = type mismatch, severity: error
```

---

## Relationships

### Data flow for StmtTrap:

```
Source: trap
  → Parse (parse.lua:1482-1484): Tr.StmtTrap(Tr.StmtSurface)
  → Typecheck (tree_typecheck.lua:741-743): Tr.StmtTrap(Tr.StmtTyped(void_ty()))
  → Layout resolve (sem_layout_resolve.lua:330): identity pass
  → Lowering (tree_to_back.lua:2138-2140): Tr.TreeBackStmtResult(env, {Back.CmdTrap}, Back.BackTerminates)
    → lower_body (tree_to_back.lua:2145-2153): flow=BackTerminates → subsequent stmts skipped
  → Pipeline gate (frontend_pipeline.lua:61-63): skipped if _G.LALIN_ALLOW_TRAP is set
  → Backend validation (back_validate.lua:487-489): treats as body terminator
  → Encoder (back_command_binary.lua:399-400): WireTag::Trap
  → Cranelift decoder (decode.rs): ctx.builder.ins().trap(TrapCode::unwrap_user(1))
  → DynASM (rules_x64.lisle:170-172): int3
```

### Data flow for stdlib require:

```
stdlib/arena.mlua: `require "stdlib.memory"`
  → mlua_run.lua transform_mlua: treats as Lua code (no island detected for `require`)
  → Lua's require() → checks package.preload["stdlib.memory"]
  → Registered by main.rs:132: preload.set(name, loader) where name="stdlib.memory"
  → Source comes from embedded_hosted_lua.rs: include_str!("../stdlib/memory.mlua")
  → Name comes from build.rs: module_name("stdlib/memory.mlua", ".") = "stdlib.memory"
```

### Data flow for null(ptr(T)):

```
Source: null(ptr(i32))
  → Parse (parse.lua): Tr.ExprNull(Tr.ExprSurface, Ty.TPtr(Ty.TScalar(ScalarI32)))
  → Typecheck (tree_typecheck.lua:613-618):
    - pvm.classof(elem) == Ty.TPtr → no issue
    - typed as ptr(i32) (the type passed to null())
  → Layout resolve (sem_layout_resolve.lua:324): identity pass
  → Lowering (tree_to_back.lua): → CmdConst(dst, BackPtr, BackLitNull)
  → Encoder → WireTag::ConstNull → Cranelift iconst(ptr_ty, 0)
```

### Data flow for null(i32) (with the error check):

```
Source: null(i32)
  → Parse: Tr.ExprNull(Tr.ExprSurface, Ty.TScalar(ScalarI32))
  → Typecheck (tree_typecheck.lua:613-618):
    - pvm.classof(elem) = Ty.TScalar ≠ Ty.TPtr
    - emits TypeIssueExpected("null", ptr(void), i32) → E0301 (error)
    - With ThrowingCollector: compilation aborts with error
    - With CollectingCollector: issue collected, expression typed as i32
  → If not caught: lowering would produce CmdConst(dst, BackI32, BackLitNull)
    → type inconsistency (i32 typed constant with null value)
```

---

## Observations

### All three issues appear to be already fixed.

1. **StmtTrap flow**: `tree_to_back.lua:2139` uses `Back.BackTerminates` (correct). The `assert_no_cmd_trap` guard is gated behind `_G.LALIN_ALLOW_TRAP` at `frontend_pipeline.lua:61`.

2. **Stdlib module naming**: `build.rs` produces `stdlib.memory` (not just `memory`), `embedded_hosted_lua.rs` shows `("stdlib.memory", ...)`, and `arena.mlua` uses `require "stdlib.memory"` — all consistent. The module is registered as `package.preload["stdlib.memory"]` in `main.rs`.

3. **null(T) non-pointer check**: `tree_typecheck.lua:614-617` already checks `pvm.classof(self.elem) ~= Ty.TPtr` and emits `TypeIssueExpected` (E0301, severity: error).

### Remaining concerns:

1. **`_G.LALIN_ALLOW_TRAP` is never set** in any code path. `stdlib/view.mlua` uses `trap` (line 4: `trap -- bounds check`). For this to work, something must set `_G.LALIN_ALLOW_TRAP = true` before compilation. Currently, this doesn't happen anywhere visible — meaning `view.mlua` would fail to compile with the default pipeline.

2. **With LSP/CollectingCollector**, `null(i32)` would produce an issue but compilation could continue with a mis-typed expression (typed as `i32` instead of `ptr(T)`). The backend would then try to lower an `ExprNull` with an `i32` element type, producing `CmdConst(dst, BackI32, BackLitNull)` — a type-inconsistent constant. This is a secondary concern since the production pipeline (ThrowingCollector) catches it as a hard error.

3. **The MOM pipeline** (`lua/lalin/mom/` directory) doesn't exist at the path searched, suggesting it may be in a different location or was not implemented yet. The hosted pipeline (through `frontend_pipeline.lua`) is the main path.
