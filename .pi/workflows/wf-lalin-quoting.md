# Unified lalin.XXX[[]] string-quoting API 
Explore replacing the builder API with a family of lalin.XXX[[]] string-quoting functions that parse Lalin syntax at specific grammar positions and return typed ASDL arrays. The goal: one uniform API shape where every construct is "write Lalin in a string, get ASDL back."
**Started**: 2026-05-19 08:50:02
---

## Scout Output — 2026-05-19 08:52:45

Now I have a complete picture. Here is the comprehensive map:

---

# Lalin Parser Entry Point Map — Complete Terrain

## Files Retrieved

1. `lua/lalin/parse.lua` (2384 lines) — Unified lexer + Pratt parser, all island kinds
2. `lua/lalin/host_func_values.lua` (450 lines) — `api.stmts()`, `api.param()`, `api.control_block()`, builder pattern
3. `lua/lalin/host_struct_values.lua` (250 lines) — `api.field()`, `api.variant()`, `api.struct()`, `api.union()`
4. `lua/lalin/host_type_values.lua` (130 lines) — `api.ptr()`, `api.array()`, `api.view()`, `lalin.i32`, etc.
5. `lua/lalin/host_expr_values.lua` (280 lines) — `api.int()`, `api.bool_lit()`, operator overloads, `api.ref()`
6. `lua/lalin/host_region_values.lua` (430 lines) — `api.entry_param()`, `api.cont()`, `api.region_frag()`, `RegionBuilder`
7. `lua/lalin/host_fragment_values.lua` (140 lines) — `api.expr_frag()`, `api.emit_expr()`, `ExprFragBuilder`
8. `lua/lalin/host_splice.lua` (420 lines) — Slot filling for all 18+ roles
9. `lua/lalin/host_session.lua` (140 lines) — Session management, `T` context
10. `lua/lalin/host_module_values.lua` (250 lines) — `api.module()`, `ModuleValue` with `:func()`, `:struct()`, `:compile()`
11. `lua/lalin/host_values.lua` (200 lines) — Canonical value handles, `lalin.memoize()`
12. `lua/lalin/host_place_values.lua` (100 lines) — `api.place_ref()`, `api.place_name()`
13. `lua/lalin/frontend_pipeline.lua` (100 lines) — `lower_module()`, `parse_and_lower()`
14. `lua/lalin/mlua_run.lua` (920 lines) — `.mlua` runner, carrier codegen, eval_island
15. `lua/lalin/open_expand.lua` (1030 lines) — Slot expansion
16. `lua/lalin/host.lua` (40 lines) — Thin public facade
17. `.pi/workflows/wf-meta-ergo.md` (906 lines) — Existing deep analysis of the metaprogramming terrain

---

## 1. Existing Parse Entry Points in `parse.lua`

### Public API (exposed via `M.Define(T)`)

There are exactly **4 public entry points**:

| Entry Point | Signature | Returns | Grammar Handled |
|---|---|---|---|
| `parse_type(src, opts)` | string → `{kind, value, splice_slots, issues}` | `LalinType.*` type node | Single type expression (scalar, ptr, view, func, closure, array, named, qualified path, `@{}` slot) |
| `parse_stmts(src, opts)` | string → `{kind, value, splice_slots, issues}` | `Stmt[]` array | Statement list (`let`, `var`, `if`, `switch`, `return`, `yield`, `jump`, `block`, `emit`, expressions, atomic ops) |
| `parse_island(scan, index, opts)` | scan + index → `{kind, value, ...}` | Depends on kind | Full island: `func`, `region`, `expr`, `struct`, `union`, `extern` |
| `parse_module(src, opts)` | string → `{kind, module, scan, ...}` | `Tr.Module` | Full `.mlua` document with Lua scanning + island extraction |

**Of these, `parse_type` and `parse_stmts` are the only standalone string-to-ASDL entry points that could serve as `lalin.XXX[[]]` equivalents.** They are the only ones that lex a fresh string and parse independently.

### Internal island parser methods that could be extracted

The full `.mlua` island parsers each contain sub-grammar parsing that could be extracted as standalone functions:

| Internal Method | Inner Grammar | Returns | Currently Extracted? |
|---|---|---|---|
| `parse_func()` (line ~1537) | `name(params) -> T body end` (+ optional `:method` syntax) | `Tr.FuncLocal` / `Tr.FuncLocalContract` | **No** — only callable via island dispatch |
| `parse_param_list()` (line ~1490) | `name: T, ...` with modifiers (`noalias`, `readonly`, `writeonly`) + `@{}` spread | `(Param[], Contract[])` | **No** — embedded inside `parse_func` / `parse_extern` |
| `parse_region_frag()` (line ~1630) | `name(params; conts) -> Protocol? entry... block... end end` | `O.RegionFrag` | **No** — only callable via island dispatch |
| `parse_open_params()` (line ~1600) | `name: T, ...` (runtime params for frags) | `(OpenParam[], bindings)` | **No** — embedded inside `parse_region_frag` |
| `parse_cont_params()` (line ~1550) | `name: cont(params...), ...` + `@{}` spread | `(cont_slots{}, slots[])` | **No** — embedded inside `parse_region_frag` |
| `parse_block_params(entry)` (line ~1210) | `(name: T = init, ...)` entry or `(name: T, ...)` plain | `EntryBlockParam[]` or `BlockParam[]` | **No** — embedded in block/region parsing |
| `parse_expr_frag()` (line ~1700) | `name(params) -> T body end` | `O.ExprFrag` | **No** — only callable via island dispatch |
| `parse_struct_island()` (line ~1724) | `[Name] fields end` (optional name) | `{name, decl=TypeDeclStruct, protocol_variants}` | **No** — only callable via island dispatch |
| `parse_union_island()` (line ~1770) | `[Name] variant | variant end` (optional name) | `{name, decl=TypeDeclTaggedUnionSugar, protocol_variants}` | **No** — only callable via island dispatch |
| `parse_extern()` (line ~1510) | `name(params) -> T as "symbol"? end` | `Tr.ExternFunc` | **No** — only callable via island dispatch |
| `parse_expr()` (line ~680-860) | Pratt expression parser, all infix/prefix ops | `Tr.Expr*` node | **No** — only called internally as part of statement parsing |
| `parse_type()` (line ~655) | Full type grammar (scalar, ptr, view, func, closure, array, named, slot) | `LalinType.*` node | **Yes** — `M.parse_type_string()` is a standalone entry point |
| `parse_stmt_until(stops)` (line ~990) | Statement list with early-stop tokens | `Stmt[]` | **Yes** — `M.parse_stmt_string()` is a standalone entry point |
| `parse_contract()` (line ~1470) | `requires bounds(expr, expr)` etc. | `Tr.Contract*` node | **No** — embedded inside `parse_func` |
| `parse_emit_stmt()` (line ~1326) | `emit name(args; cont_fills)` | `Tr.StmtUseRegionFrag` | **No** — embedded in statement parsing |
| `parse_switch_stmt()` (line ~1040) | `switch expr do case ... default ... end` | `Tr.StmtSwitch` | **No** — embedded in statement parsing |
| `parse_if_stmt(is_elseif)` (line ~1007) | `if cond then ... else ... end` | `Tr.StmtIf` | **No** — embedded in statement parsing |
| `parse_jump_args()` (line ~1240) | `(name = expr, ...)` | `JumpArg[]` | **No** — embedded in statement parsing |
| Fields in struct body | `fname: T, fname: T;` (comma/semi separated) | `FieldDecl[]` | **No** — embedded inside `parse_struct_island` |
| Variants in union body | `Vname(T) \| Vname(fields...)` | `VariantDecl[]` | **No** — embedded inside `parse_union_island` |
| `parse_atomic_stmt_if_present()` (line ~1400) | `atomic_store(ty, addr, val)` / `atomic_fence()` | `Tr.StmtAtomicStore` / `Tr.StmtAtomicFence` | **No** — embedded in statement parsing |
| `parse_switch_expr()` (line ~1080) | `switch val do case ... default ... end` | `Tr.ExprSwitch` | **No** — embedded in expression parsing |
| `parse_expr_block(stops)` (line ~1100) | Statement list with last expr extraction | `(Stmt[], last_expr)` | **No** — embedded in switch-expr parsing |
| `parse_control_expr_after_block()` (line ~1139) | `block label(params = init) -> T body end` | `Tr.ExprControl` | **No** — embedded in expression parsing |
| `parse_multi_control_expr()` (line ~1155) | `region -> T entry... block... end end` | `Tr.ExprControl` | **No** — embedded in expression parsing |
| `parse_stmt_control_after_block()` (line ~1197) | `block label(params = init) body end` | `Tr.StmtControl` | **No** — embedded in statement parsing |

---

## 2. How the Island Parsers Work Internally

### Parser state machine

Each island kind is a different **grammar production** that consumes from the same token window:

```
parse_island(scan, i)
  → new_parser_internal(T, toks, first+i, limit+i, opts)
    → parse state machine:
      if kind == "func":   expect(func_kw) → parse_func()
      if kind == "region": expect(region_kw) → parse_region_frag()
      if kind == "expr":   expect(expr_kw) → parse_expr_frag()
      if kind == "struct": expect(struct_kw) → parse_struct_island()
      if kind == "union":  expect(union_kw) → parse_union_island()
      if kind == "extern": expect(extern_kw) → parse_extern()
```

**The only entry points that exist as standalone function calls are `parse_type_string` and `parse_stmt_string`.** Everything else requires going through the full `scan_document` → island identification pipeline, or calling the internal parser methods directly (which requires constructing a `Parser` object from scratch).

### What it would take to extract each inner grammar

| Inner Grammar | Extraction Difficulty | Reason |
|---|---|---|
| `parse_param_list` | **Medium** — it's a clean method on `Parser` but it expects `(` already consumed. Needs `expect(TK.lparen); parse_param_list(); expect(TK.rparen)` wrapping. | Already a clean method (line ~1490) |
| `parse_open_params` | **Medium** — same pattern, embedded in region parsing | Method at line ~1600 |
| `parse_cont_params` | **Medium** — same pattern, embedded in region parsing | Method at line ~1550 |
| `parse_struct_fields` | **Medium** — the field loop body in `parse_struct_island` (lines ~1746-1770) is inline, not extracted | Loop parses `fname: T` repeatedly |
| `parse_union_variants` | **Hard** — the variant parsing loop in `parse_union_island` (lines ~1810-1856) is stateful, handles `()` variations | Complex conditionals for `V(T)` vs `V(f: T, ...)` |
| `parse_block_params` | **Easy** — already a clean method (line ~1210) | Returns `EntryBlockParam[]` or `BlockParam[]` |
| `parse_expr` | **Medium** — already a clean method (line ~680) but Pratt binding power makes standalone tricky | Returns single `Expr`, needs proper rbp boundary |
| `parse_func_body` | **Hard** — the parse-func body is inline calls to `parse_stmt_until({end_kw})`, already delegating to statement parsing | Already delegates to existing methods |
| `parse_region_body` | **Medium** — the entry/block parsing loop in `parse_region_frag` (lines ~1660-1695) could be extracted | Has its own `parse_stmt_until` + block iteration |

---

## 3. Parser Internal Structure

### How the parser object is created

```lua
local function new_parser_internal(T, toks, first, limit, opts)
    opts = opts or {}
    local C, Ty, B, O, Sem, Tr, Pm =
        T.LalinCore, T.LalinType, T.LalinBind, T.LalinOpen,
        T.LalinSem, T.LalinTree, T.LalinParse
    local p = setmetatable({
        T = T, C = C, Ty = Ty, B = B, O = O,
        Sem = Sem, Tr = Tr, Pm = Pm,
        toks = toks,
        i = first or 1,
        first = first or 1,
        limit = limit or toks.n,
        issues = {},
        value_env = opts.value_env or {},
        cont_env = opts.cont_env or {},
        protocol_types = opts.protocol_types or {},
        splice_values = opts.splice_values or {},
        name_hint = opts.name_hint,
        splice_slots = {},
        splice_slots_by_id = {},
        region_seq = 0,
        region_scope = opts.region_scope,
        anonymous = false,
        anon_counter = 0,
    }, Parser)
    ...
end
```

### Parser state

| Field | Purpose |
|---|---|
| `toks` | Shared token array (from `M.lex()` or `scan_document()`) |
| `i` | Current token position |
| `first`, `limit` | Token window boundaries for island parsing |
| `issues` | Accumulated parse errors/warnings |
| `value_env` | Name → `Binding` map (for resolving identifiers in expressions) |
| `cont_env` | Name → `ContSlot` map (for resolving continuation jumps) |
| `protocol_types` | Name → variant-array map (from parsed union islands) |
| `splice_values` | splice_id → value map (from `.mlua` carrier closures, filled by `luamap`) |
| `splice_slots` | Array of `{splice_id, slot, role, spread}` created during parse |
| `splice_slots_by_id` | Index by `role:splice_id` key |
| `name_hint` | Optional name inferred from Lua assignment |
| `region_seq` | Counter for generating unique region IDs |
| `region_scope` | Scope string for region ID generation |
| `anonymous` | True if no explicit name was given |
| `anon_counter` | Counter for anonymous placeholder names |

### Can multiple parser calls share state?

**Each `lalin.XXX[[]]` call must create a fresh lexer + parser.** The parser is not reusable — it has mutable position state (`i`), accumulates issues, and builds `splice_slots`. The lexer (`M.lex(src)`) is a pure function that returns token arrays — it is standalone and reentrant.

### How the lexer works

`M.lex(src)` (line ~75-360):
- Pure function: string → token array
- Produces `TK` tokens with `kind[]`, `text[]`, `start[]`, `stop[]`, `line[]`, `col[]` arrays
- Handles `@{}` → produces `TK.hole` with splice ID
- Side table: `splice_map[splice_id] = lua_expr_text`, `splice_spread[splice_id] = true/false`
- Returns: token array with `n`, `kind`, `text`, `start`, `stop`, `splice_map`, `splice_spread`, `lex_issues`

**Yes, `M.lex(src)` is fully standalone.** It's used for both standalone `parse_type_string`/`parse_stmt_string` and as part of `tokenize_island` (which uses the same scanning logic inline in `scan_document`).

---

## 4. Existing `host_*_values.lua` Constructors

### Map of every `lalin.XXX()` builder → potential `lalin.XXX[[]]`

| Builder Function | Returns | What it constructs | String-quoting equivalent | Superset? |
|---|---|---|---|---|
| `lalin.param(name, ty)` | `ParamValue` | `Ty.Param(name, ty.ty)` | `lalin.params[[]]` → `Param[]` | Yes — parse `name: T, name: T` |
| `lalin.field(name, ty)` | `FieldValue` | `Ty.FieldDecl(name, ty.ty)` | `lalin.fields[[]]` → `FieldDecl[]` | Yes — parse `fname: T; fname: T` |
| `lalin.variant(name, ty)` | variant table | `Ty.VariantDecl(name, ty.ty, {})` | `lalin.variants[[]]` → `VariantDecl[]` | Yes — parse `V(T) \| W(f: T)` |
| `lalin.cont(params)` | `ContValue` | `{kind="cont", params, block_params=...}` | `lalin.conts[[]]` → cont decls | Yes — parse `name: cont(params...)` |
| `lalin.cont_decl(name, params)` | `{kind="cont_decl", ...}` | Simple table, not ASDL | `lalin.conts[[]]` | Would be absorbed |
| `lalin.entry_param(name, ty, init)` | `EntryParamValue` | `Tr.EntryBlockParam(name, ty.ty, init.expr)` | `lalin.entry_params[[]]` | Would be absorbed |
| `lalin.control_block(name, params, body)` | `Tr.ControlBlock` | `Tr.ControlBlock(label, decls, stmts)` | `lalin.blocks[[]]` | Yes — parse `block label(params) body end` |
| `lalin.type.*` (scalars) | `TypeValue` | `Ty.TScalar(...)` | Already exists as `lalin.type[[]]` | Already done |
| `lalin.ptr(T)` | `TypeValue` | `Ty.TPtr(elem.ty)` | `lalin.type[[]]` | Already absorbed |
| `lalin.array(count, T)` | `TypeValue` | `Ty.TArray(len, elem.ty)` | `lalin.type[[]]` | Already absorbed |
| `lalin.view(T)` | `TypeValue` | `Ty.TView(elem.ty)` | `lalin.type[[]]` | Already absorbed |
| `lalin.func_type(params, result)` | `TypeValue` | `Ty.TFunc(tys, ret)` | `lalin.type[[]]` | Already absorbed |
| `lalin.closure_type(params, result)` | `TypeValue` | `Ty.TClosure(tys, ret)` | `lalin.type[[]]` | Already absorbed |
| `lalin.path_named(name)` | `TypeValue` | `Ty.TNamed(TypeRefPath(C.Path(...)))` | `lalin.type[[]]` | Already absorbed |
| `lalin.ref(name, ty)` | `ExprValue` | `Tr.ExprRef(...)` | `lalin.expr[[]]` | Yes — parse any expression |
| `lalin.int(raw)` | `ExprValue` | `Tr.ExprLit(C.LitInt(...))` | `lalin.expr[[]]` | Already absorbed |
| `lalin.bool_lit(v)` | `ExprValue` | `Tr.ExprLit(C.LitBool(v))` | `lalin.expr[[]]` | Already absorbed |
| `lalin.select(cond, t, e)` | `ExprValue` | `Tr.ExprSelect(...)` | `lalin.expr[[]]` | Already absorbed |
| `lalin.call(name, args, result_ty)` | `ExprValue` | `Tr.ExprCall(...)` | `lalin.expr[[]]` | Already absorbed |
| `lalin.atomic_load(addr, ty)` | `ExprValue` | `Tr.ExprAtomicLoad(...)` | `lalin.expr[[]]` | Already absorbed |
| `lalin.struct(name, fields)` | `StructValue` | `TypeDeclStruct + TypeValue` | `lalin.struct[[]]` → parse island | Yes — but needs island wrapper |
| `lalin.union(name, fields)` | `StructValue` | `TypeDeclUnion + TypeValue` | `lalin.union[[]]` → parse island | Yes — but needs island wrapper |
| `lalin.region_frag(name, params, conts, fn)` | `RegionFragValue` | `O.RegionFrag(name, params, ...)` | `lalin.region[[]]` → parse island | Yes — but needs island wrapper |
| `lalin.expr_frag(name, params, result, fn)` | `ExprFragValue` | `O.ExprFrag(name, params, ...)` | `lalin.expr_frag[[]]` → parse island | Yes — but needs island wrapper |
| `lalin.module(name)` | `ModuleValue` | Collection of items | Stays as builder | N/A — too complex for string |
| `lalin.stmts(string/fn/table)` | `Stmt[]` | Statement array | Already exists as `lalin.stmts[[]]` | Already done |
| `lalin.type_from_asdl(ty, hint)` | `TypeValue` | Wrapper | Raw ASDL, stays as is | N/A |
| `lalin.expr_from_asdl(expr, ty, hint)` | `ExprValue` | Wrapper | Raw ASDL, stays as is | N/A |
| `lalin.place_ref(binding, ty)` | `PlaceValue` | `Tr.PlaceRef(...)` | `lalin.expr[[]]` | Would be absorbed |

### Key insight: most builder constructors become redundant if we have full grammar quoting

- `lalin.param(a, i32)` → `lalin.params[[a: i32]]`
- `lalin.field(x, i32)` → `lalin.fields[[x: i32]]`
- `lalin.variant(Ok, i32)` → `lalin.variants[[Ok(i32)]]`
- `lalin.ref(x, i32)` → `lalin.expr[[x]]`
- `lalin.int(42)` → `lalin.expr[[42]]`
- `lalin.control_block("loop", params, body)` → `lalin.blocks[[block loop(i: i32, acc: i32) ... end]]`
- `lalin.entry_param(i, i32, 0)` → only relevant within entry block, where `block loop(i: i32 = 0, ...)` handles it

---

## 5. Existing `lalin.stmts` Overloads

Current overloads in `host_func_values.lua` (lines ~329-360):

```lua
function api.stmts(bindings, builder_fn)
    -- Form 1: string only → parse as snippet (rejects @{})
    if type(bindings) == "string" and builder_fn == nil then
        return parse_stmt_snippet(bindings)
    end
    -- Form 2: function only → builder without bindings
    if type(bindings) == "function" and builder_fn == nil then
        builder_fn = bindings; bindings = nil
    -- Form 3: function second arg (string) → parse
    elseif type(builder_fn) == "string" then
        return parse_stmt_snippet(builder_fn)
    -- Form 4: ASDL array pass-through
    elseif type(bindings) == "table" and builder_fn == nil
           and #bindings > 0 and pvm.classof(bindings[1]) ~= false then
        return bindings
    end
    -- Form 5: bindings table + builder function (the primary builder form)
    ...
end
```

**If the `lalin.XXX[[]]` quoting model fully lands:**

- **Forms 1 (string) and 3 (function, string) become unnecessary** — they are `lalin.stmts[[]]` without the `[[]]` syntax. They exist for backwards compat but can be deprecated.
- **Form 2 (function only)** — the builder form — is the one that can't be replaced by a string quoting API alone. Loops/conditionals in codegen need Lua iteration, which `lalin.stmts[[]]` can't express.
- **Form 4 (ASDL pass-through)** — stays as is, no quoting needed.
- **Form 5 (bindings + builder)** — partially replaced. The bindings table + body function is the builder pattern. If `lalin.stmts[[]]` supports `@{}`, the builder form is needed only for loops/conditionals.

**Overload ambiguity risk**: Adding `lalin.stmts("src", {val=42})` creates ambiguity with `lalin.stmts({x=lalin.i32}, fn)` — both are string + table or table + function. The existing dispatch keys on `type(bindings) == "string"` for the snippet path, so adding `lalin.stmts(string, table)` is unambiguous. But users could confuse argument order.

---

## 6. Splice Interaction with `lalin.XXX[[]]` Calls

### The current rejection is conservative, not architectural

`parse_stmt_string` creates `Slot*` nodes when it encounters `@{}`. The `host_func_values.lua` wrapper explicitly checks `#parsed.splice_slots ~= 0` and throws:

```lua
if #parsed.splice_slots ~= 0 then
    error("lalin.stmts string snippets do not evaluate @{} splices; "
        .. "pass values with builder form or splice outside with @{...}", 3)
end
```

**The parser is ready — the host bridge is the blocker.** The same parser produces identical `Slot*` nodes whether inside a `.mlua` island or a `parse_stmt_string` call. The only difference is who resolves them.

### The three options for making `@{}` work in snippets

**Option 1: Explicit second argument** (simplest, cleanest API)

```lua
lalin.stmts("let y: i32 = @{v}; return y", { v = lalin.int(42) })
```

- No closure capture, no magic — values passed explicitly
- Reuses `host_splice.fill()` for each slot (same coercion logic as `.mlua` pipeline)
- After filling, calls `open_expand` to resolve → returns pure `Stmt[]`
- **Downside**: must manually thread all values
- **Upside**: predictable, debuggable, no scope-capture complexity

**Option 2: Closure capture** (magic but ergonomic in `.mlua`)

```lua
local v = 42
lalin.stmts("let y: i32 = @{v}; return y")  -- captures v from scope
```

- Uses `load("return " .. text)` or `debug.getinfo` to capture the caller's locals
- **Problem**: `@{v}` is stored as text `"v"`. To resolve it, you'd need to evaluate `v` in the caller's scope. `load("return v")()` would look up `v` in `_ENV`, not the caller's locals. LuaJIT's `load` doesn't capture the calling function's lexical scope.
- Requires explicitly threading the calling environment — fragile in LuaJIT's fast paths
- **Downside**: unreliable, breaks with LuaJIT optimization

**Option 3: Dual-input (snippet string + builder fn hybrid)**

```lua
lalin.stmts(function(b)
    local v = lalin.int(42)
    -- Can't do this cleanly: string + values intermix
end)
```

- This is the existing builder form — no change needed
- Already works for loops and conditionals
- Not a "splice in snippets" solution — it avoids the problem

### Recommendation from analysis: Option 1 (explicit values table) is the only safe path

The `.mlua` pipeline has a distinct advantage: carrier closures are generated at the `.mlua` load time and evaluated later in a controlled runtime. Snippets called from plain Lua have no such carrier infrastructure. Option 1 is the simplest, most predictable mechanism.

---

## 7. Parser's `splice_values` Mechanism

### How it's used in the `.mlua` pipeline

In `mlua_run.lua`, the carrier closures are evaluated and stored in `luamap`:

```lua
-- For each @{expr} in an island:
-- 1. Generate carrier closure: function() return @{expr's Lua text}() end
-- 2. Evaluate closure: results[id] = { present = true, value = closure_value }
-- 3. Pass as opts.splice_values = results to parse_island
```

The `Parser:splice_value(id)` method reads from this map:

```lua
function Parser:splice_value(id)
    local rec = self.splice_values and self.splice_values[id]
    if type(rec) == "table" and rec.present then return rec.value end
    return rec
end
```

**But the parser only uses `splice_value` for spread positions and name-based type lookup.** For non-spread holes (expr, type, name), it creates `Slot*` nodes regardless — it never substitutes. The actual resolution happens later via `host_splice.fill()` + `open_expand`.

### Could `splice_values` be reused for standalone `lalin.XXX[[]]`?

**Yes, but differently.** The `.mlua` pipeline has a carrier phase that separates evaluation from parsing. For standalone `lalin.stmts("...", {v=42})`:

1. Parse the string → get `splice_slots` array with `Slot*` nodes
2. Iterate `splice_slots` — each has `role` and `slot`
3. Call `host_splice.fill(session, slot.slot, value, site, slot.role, slot.spread)` for each slot, using the passed-in values table
4. The result is an array of `SlotBinding(slot, SlotValue*)`
5. Call `open_expand` to substitute those bindings into the parsed AST
6. Return the resolved `Stmt[]`

**The `splice_values` map is not directly reusable** because:
- It's designed for the carrier closure ID space (`"splice.1"`, `"splice.2"`)
- The standalone path doesn't have carrier closures — values come from the call site table
- The role dispatch logic is already in `host_splice.fill()` — reuse that, not `splice_values`

### What `new_parser_internal` accepts for `opts`

```lua
{
    value_env = ...,       -- Name→Binding map (for resolving identifiers as bindings)
    cont_env = ...,         -- Name→ContSlot map (for resolving continuation jumps)
    protocol_types = ...,   -- Name→variant-array map (union protocols)
    splice_values = ...,    -- splice_id→value map (from carrier closures)
    name_hint = ...,        -- Name inferred from Lua assignment
    region_scope = ...,     -- Scope string for region IDs
}
```

For `lalin.XXX[[]]` calls, most of these would be empty/default — the snippet has no ambient `value_env`, `cont_env`, or `protocol_types` unless explicitly provided.

---

## Summary: Grammar Positions Needing Entry Points

### Already have standalone entry points (ready for `lalin.XXX[[]]`)

| `lalin.XXX[[]]` | Returns | Entry point | Status |
|---|---|---|---|
| `lalin.type[[]]` | Type node | `parse_type_string` (line ~2311) | ✅ Exists |
| `lalin.stmts[[]]` | `Stmt[]` | `parse_stmt_string` (line ~2322) | ✅ Exists, rejects `@{}` |

### Need new entry points (extractable from island parsers)

| `lalin.XXX[[]]` | Returns | Grammar | Extraction difficulty |
|---|---|---|---|
| `lalin.params[[]]` | `Param[]` + `Contract[]` | `name: T, name: T` with modifiers | **Medium** — wrap `parse_param_list()` with `expect(lparen)` and `expect(rparen)` |
| `lalin.fields[[]]` | `FieldDecl[]` | `fname: T; fname: T` | **Medium** — extract field loop from `parse_struct_island()` |
| `lalin.variants[[]]` | `VariantDecl[]` | `V(T) \| W(f: T) \| X` | **Hard** — complex variations, protocol registration |
| `lalin.conts[[]]` | `O.ContSlot[]` | `name: cont(params...), ...` | **Medium** — wrap `parse_cont_params()` |
| `lalin.open_params[[]]` | `O.OpenParam[]` | `name: T, ...` | **Medium** — wrap `parse_open_params()` |
| `lalin.blocks[[]]` | `Tr.ControlBlock[]` | `block label(params) body end` | **Medium** — needs body parsing (`parse_stmt_until`) |
| `lalin.entry_params[[]]` | `Tr.EntryBlockParam[]` | `name: T = init, ...` | **Medium** — wrap `parse_block_params(true)` |
| `lalin.expr[[]]` | `Expr` node | Prase `parse_expr` standalone | **Medium** — needs proper Pratt boundary check |
| `lalin.func[[]]` | `FuncLocal` | Full function island | **Medium** — needs island-like wrapper |
| `lalin.region[[]]` | `RegionFrag` | Full region island | **Hard** — many sub-grammars |
| `lalin.expr_frag[[]]` | `ExprFrag` | Full expr island | **Medium** — smaller than region |
| `lalin.struct[[]]` | `TypeDeclStruct` | Struct island | **Medium** — small grammar |
| `lalin.union[[]]` | `TypeDeclTaggedUnionSugar` | Union island | **Hard** — variant complexity |
| `lalin.extern[[]]` | `ExternFunc` | Extern island | **Easy** — simplest island |
| `lalin.contracts[[]]` | `Contract[]` | `requires bounds/disjoint/...` | **Medium** — wrap `parse_contract()` |
| `lalin.switch_arm[[]]` | `SwitchStmtArm` | `case key then body` | **Hard** — depends on statement-list stops |
| `lalin.switch_arms[[]]` | `SwitchStmtArm[]` | `case...case...default...` | **Hard** — switch arm sequence |

### Grammar separators & formatting for each

| Quoting | Separator | Trailing comma? | Newlines? | Same as `.mlua` grammar? |
|---|---|---|---|---|
| `params` | comma between params (`a: T, b: T`) | ✅ Yes | ✅ Skipped | **Yes** — identical to function param lists |
| `fields` | comma or semicolon (`f: T; g: T`) | ✅ Yes | ✅ Skipped | **Yes** — identical to struct bodies |
| `variants` | pipe (`A(T) \| B(T)`) | ❌ No pipe after last | ✅ Skipped | **Yes** — identical to union bodies |
| `conts` | comma (`ok: cont(), fail: cont(pos: i32)`) | ✅ Yes | ✅ Skipped | **Yes** — identical to region cont lists |
| `blocks` | sequential (`block a() end block b() end`) | ❌ N/A | ✅ Significant (starts after `end`) | **Yes** — identical to region block lists |
| `expr` | single expression, no separator | ❌ N/A | ❌ Stops at newline or close paren | **Yes** — same Pratt parser |
| `func` | keyword-delimited (`func name... end`) | ❌ N/A | ✅ Significant | **Yes** — identical full parse |
| `struct` | keyword-delimited (`struct Name... end`) | ❌ N/A | ✅ Significant | **Yes** — identical full parse |

### What `@{}` support means for each entry point

The parser already creates `Slot*` nodes in all positions:
- **Singleton slots** (`@{val}`, `@{T}`, `@{name}`): become `SlotExpr`, `SlotType`, `SlotName`
- **Spread slots** (`@{list...}`): become `SlotRegion` with role-specific dispatch

**If `@{}` is supported** in `lalin.XXX[[]]`, the flow is:
1. Parse string → get slot-ridden AST + `splice_slots` array
2. Caller provides values table
3. `host_splice.fill()` per slot
4. `open_expand` to resolve → returns clean ASDL
5. Caller also gets `protocol_types` merged back (for union → protocol mapping)

**If `@{}` is NOT supported**, each entry point should check `#parsed.splice_slots ~= 0` and error — same conservative approach as `lalin.stmts` today.

## Knowledge-builder Output — 2026-05-19 08:58:40

I now have all the data I need. Here's my analysis.

---

### What Matters Most for This Problem

**Grammar precision vs. state flow**: The combinator idea succeeds or fails on whether each sub-grammar boundary matches an ASDL type boundary *and* a state-environment boundary. The key insight from reading the code: not all sub-grammars are created equal. Some change parser state (value_env, cont_env, protocol_types), and some don't. The combinator must thread state explicitly where the current architecture threads it implicitly via mutable parser fields.

**Splice slot namespace independence**: The expander resolves slots by pairing a `Slot*` node (produced during parsing) with a `SlotBinding` (produced during filling). These are identity-compared — the `Slot*` node IS the key. When sub-parsers each lex independently, their slots are in separate identity spaces. This means: **you cannot fill slots from sub-parser A using bindings created by sub-parser B**. They must be filled independently and the resulting clean ASDL passed up, OR they must share a single token array (and thus a single identity space).

---

### Non-Obvious Observations

**1. The func/region asymmetry is the most important constraint — and it's invisible from the top**

Look at `parse_func` (line 1557) vs `parse_region_frag` (line 1728):

- `parse_func` calls `parse_param_list()` which returns `Param[]`. These param names are **NOT added to `value_env`**. When the body parser encounters `x` as an expression, it creates `ValueRefName("x")` — a string-based reference. The typechecker later resolves these by looking at the function's signature.

- `parse_region_frag` calls `parse_open_params()` which returns `OpenParam[]` AND builds `param_bindings` (a name→`Binding` map). These ARE installed into `value_env`. When the body parser encounters `x` as an expression, it creates `ValueRefBinding(binding)` — a pointer-based reference.

This means: **`lalin.params[[x: i32]]` returns `Param[]` (strings), but `lalin.open_params[[x: i32]]` returns `(OpenParam[], bindings_map)`**. They parse the *same syntax* (`name: type`) but produce different ASDL types AND different side effects. A combinator calling `parse_params` on a func's signature must NOT install bindings into the environment. A combinator calling `parse_open_params` on a region's signature MUST.

If you try to unify these as one `lalin.params[[]]` entry point, you'll have an API that sometimes returns bindings and sometimes doesn't — or you'll force the wrong behavior on one of the two call sites.

**2. The spread sentinel pattern creates a hidden coupling between parser and expander**

Look at `spread_sentinel(role, slot)` (parse.lua line 633):

```lua
local function spread_sentinel(role, slot)
    return "__lalin_spread_" .. role .. ":" .. slot.key
end
```

And `spread_region_slot(role, name)` (open_expand.lua line 68):

```lua
local function spread_region_slot(role, name)
    local prefix = "__lalin_spread_" .. role .. ":"
    if type(name) ~= "string" or name:sub(1, #prefix) ~= prefix then return nil end
    local key = name:sub(#prefix + 1)
    ...
end
```

The spread mechanism works by **encoding a slot reference into a string field** (like a `Param.name` or a `FieldDecl.field_name`) and decoding it during expansion. The parser writes "`__lalin_spread_param_list:splice:X`" into the name field. The expander checks if the name starts with the magic prefix, and if so, looks up the slot in the fill environment.

**This means**: if a sub-parser produces `Param[]` that happened to resolve `@{}` eagerly (because the standalone `lalin.params[[]]` call filled the slots before returning), the sentinel pattern is NEVER triggered. The combinator never sees spread slots. But if the sub-parser produces `Param[]` WITH sentinel names still embedded (because the combinator wants to do its own fill), the expander works as-is.

**The hidden coupling**: the expander's `expand_params` function (open_expand.lua line 127) looks for sentinel patterns in `Param.name`. It doesn't know about sub-parser boundaries. If a combinator fills sub-parser slots eagerly, the sentinel check never fires, and the expander treats the param names as literal strings. If the combinator passes slot-ridden ASDL up to the module-level expander, the sentinel check fires and works. **Both modes work, but you must pick one per call.**

**3. Independent lexing means independent splice ID namespaces — which breaks cross-island slot references**

In the shared-token model (`scan_document` → `tokenize_island` → shared `toks`), splice IDs are globally sequential: `splice.1`, `splice.2`, ... across all islands. The `splice_slots_by_id` map keys look like `"expr:splice.1"` — the role + the global splice ID.

If `lalin.func[[x: @{T}]]` is implemented by lexing the whole string independently with `M.lex(src)`, the splice counter starts at 1 fresh. The inner `lalin.params[[x: @{T}]]` ALSO lexes independently, starting ITS counter at 1. So `@{T}` in the standalone params call produces `"splice.1"`, and if the combinator calls the params parser first, then the body parser, the body parser's `@{...}` also produces `"splice.1"`.

**This is fine as long as each sub-parser fills its own slots eagerly and returns clean ASDL.** But it breaks if you try to collect slot-ridden ASDL from each sub-parser and fill them all at the island level — because you'd have two slots with the same key but different meanings.

**The per-splice retry pattern**: if `lalin.XXX[[]]` fails to fill a slot because the values table doesn't have it, it can either error immediately (like current `lalin.stmts` does) or defer the slot to be filled at the island level. Deferred filling requires the slot to carry enough identity information for the island-level fill to find it. Currently, slots carry `splice_id` (a string like `"splice.3"`) and `key` (a string like `"splice:type:splice.3"`). These are only meaningful within a single parse session.

**4. The `region_scope` auto-generation couples to token positions — sub-parsers break this**

From `new_parser_internal` (line ~422):

```lua
local window_start = toks.start[p.first] or 0
local window_stop = toks.stop[p.limit] or math.huge
if not p.region_scope then
    p.region_scope = tostring(p.first or 1) .. "_" .. tostring(window_start or 0) 
        .. "_" .. tostring(p.limit or 0) .. "_" .. tostring(window_stop or 0)
end
```

The `region_scope` is used to generate unique region IDs for `self:next_region_id(label)`. These IDs end up in `ContSlot.key` fields like `"cont:my_region:loop:1_0_25_99:1"`. The scope encodes token window boundaries.

When a sub-parser creates a parser over an independently-lexed string, the token window is `1` to `toks.n`, and the scope encodes those positions. The region IDs WILL differ from what the island-level parser would have produced (which was scoped to the island's window in the shared token array). **Region IDs are internal**, so they don't need to be stable across parse sessions — but if you want the combinator to produce the same result as the current monolithic parser, region IDs will differ.

**The practical impact**: region IDs appear in `ContSlot.key` and `OpenParam.key` fields. These flow through the typechecker. If a user's code does NOT depend on the precise string content of these keys (which almost no user code does — they're internal), this is a non-issue. But it's a source of non-determinism if you're comparing old vs. new output.

**5. The `name_hint` inference requires the combinator to know its caller's Lua context**

`infer_lua_assignment_name(src, island_start)` (parse.lua ~2095) reads the source text before the island to find `name =` patterns. This is how anonymous islands get their name from Lua assignments like `local my_fn = func(x) ... end`.

For a standalone `lalin.func[[]]` entry point, the source string DOESN'T include the Lua assignment context. The name_hint would need to be passed explicitly:

```lua
local my_fn = lalin.func[[x: i32 -> i32 return x end]]  -- no name_hint available
```

vs.

```lua
lalin.func("my_fn", "x: i32 -> i32 return x end")  -- explicit name
```

or the entry point would need to receive the name separately, which breaks the "write Lalin in a string, get ASDL back" uniformity.

**6. `protocol_types` is accumulated across ALL islands, not just within one — the combinator must be module-aware, not island-aware**

A `.mlua` file can have:

```lalin
union Option(T)
    Some(T)
    None
end

region unwrap(val: Option(i32); some: cont(v: i32), none: cont())
    ...
end
```

The `unwrap` region references `Option` as a protocol type. The `protocol_types` map is threaded through `M.parse_module_document`:

```lua
for i = 1, #scan.islands do
    local parsed = M.parse_island(T, scan, i, { protocol_types = protocol_types })
    protocol_types = parsed.protocol_types or protocol_types
end
```

A standalone `lalin.region[[]]` call has NO access to `protocol_types` unless explicitly provided. The combinator for `lalin.region[[unwrap(val: Option(i32); some: cont(v: i32), none: cont()) ... end]]` would need to accept `protocol_types` as an option.

**But here's the non-obvious implication**: the region parser calls `self:cont_slots_from_protocol(protocol_ty, name_key)` which looks up `self.protocol_types[name]`. If the protocol type isn't registered, the parser issues a warning and returns empty cont slots. **The parser currently allows forward references to protocols** — the union island may be parsed AFTER the region island in the document. The module combinator (`parse_module_document`) handles this by doing `protocol_types = parsed.protocol_types or protocol_types` after each island. A standalone region parser cannot.

This means: `lalin.region[[]]` must either **require explicit protocol_types** (breaking "just write Lalin"), or **defer protocol resolution** to a later pass, or **only work when the protocol union is parsed first** (fragile).

**7. The combinator degenerates to the current code for the most complex grammar (region)**

A region fragment combines ALL the sub-grammars intricately:

```
region name(open_params; conts) -> Protocol | entry entry_label(entry_params) body [block block_label(block_params) body end]* end
```

The parse flow:
1. Parse name → creates `NameRef` (may be a slot)
2. Parse open_params → creates `OpenParam[]`, builds `param_bindings` map
3. Parse conts or protocol → creates `ContSlot[]`, builds `cont_slots` map
4. Save value_env + cont_env
5. Install param_bindings → value_env, cont_slots → cont_env
6. Parse entry label, entry params, entry body (uses value_env for expr refs, cont_env for jump targets)
7. Parse block sequence (each block uses value_env + cont_env)
8. Restore value_env + cont_env
9. Expect `end`

**Steps 5-7 are the core complexity**: the body parsers need the combined environment from steps 2+3. A combinator would call `lalin.open_params`, `lalin.conts`, and then `lalin.stmts[...]` with the combined env. But the `block` loop in step 7 is interleaved with the entry body — you can't parse blocks until you know what names they use. The `parse_stmt_until` with `block_kw` as a stop token handles this interleaving. A combinator would need its own version of this, which is essentially what the current `parse_region_frag` already does.

**The region body parser IS the combinator you want — it already exists.** The only thing that changes is swapping inline `parse_open_params()` for a call to the extracted `lalin.open_params[[]]` equivalent. The savings are minimal for this case.

**8. The `anonymous` and `anon_counter` fields create invisible ordering constraints**

The parser has `anonymous` (boolean) and `anon_counter` (integer) fields. When an anonymous name is generated (`"_anon_struct_0"`, `"_anon_struct_1"`, etc.), the counter increments. If sub-parsers each create independent parsers, they each start `anon_counter` at 0. If the combinator needs to generate names consistently with how the current monolithic parser would, the counter must be shared across sub-parser calls.

Currently, in a single island parse, `anon_counter` starts at 0 and increments by 1 for each anonymous node. In a combinator model, the combinator would lex the island string, find the struct definition (which may be anonymous), and call `lalin.struct[[]]` on the substring. The standalone struct parser starts its own `anon_counter` at 0. The ID will be `"_anon_struct_0"` — same as before if there's only one anonymous struct. But if the island has multiple anonymous structs, or if there's an anonymous region, the IDs diverge.

**9. The combinator model changes the error reporting granularity fundamentally**

Currently, `parse_func` reports errors like "unexpected token after function name" at the function level. The error's source position is accurate because the parser's `self:start()` and `self:stop()` methods return byte offsets into the original source.

If a combinator calls `lalin.params[[x: @{T}]]` on an independently-lexed string, the byte offsets in the parsed result are relative to the substring, NOT the original island source. The error "expected name" on token 3 of the substring maps to byte 15 of the substring, not byte 150 of the full `.mlua` file.

**To preserve source positions**, the combinator must either:
- (a) Accept pre-lexed token windows (preserving source positions from the shared token array)
- (b) Re-map byte offsets from substring-relative to island-relative by adding the island's byte offset

The current `parse_stmt_string` and `parse_type_string` entry points lose this information — they return issues with offsets relative to the lexed string, not the document. For `lalin.XXX[[]]` this is acceptable (you're parsing a string, you get errors in string coordinates). For combinatorial island parsing, it's a regression.

**10. The slot recording deduplication (`splice_slots_by_id`) assumes global uniqueness of `role:splice_id`**

From `record_splice_slot` (line 607):

```lua
local key = tostring(role) .. ":" .. tostring(splice_id)
local existing = self.splice_slots_by_id[key]
if existing then return existing end
```

This prevents double-recording the same slot. When sub-parsers are independent, each has its own `splice_slots_by_id`. There's no risk of collision. But if sub-parsers share a token array (the combinator carves token windows from the shared island tokens), `splice_id` values are globally increasing. The deduplication works correctly because the role distinguishes where the slot was created.

**However**, if a combinator carves a token window that starts at token 50 (in the middle of the island's token array), and `splice_i` has already advanced to 7 from earlier tokens, the sub-parser sees `splice.7` as its first hole. The sub-parser's `splice_slots_by_id` has keys like `"param_list:splice.7"`. The combinator's own parser (which consumed tokens before the sub-parser's window) might have also recorded `splice.7` under a different role. The deduplication prevents conflict — but this means the sub-parser is looking up a slot that the combinator already created. **This is actually the current behavior**, and it's correct: the slot for `@{params...}` in the param list is the same physical slot as `@{params...}` in the function signature. The deduplication is NOT a bug — it's a feature that the current architecture relies on.

**11. `lalin.params[[]]` and similar sub-grammar entry points have an ambiguously optional wrapping delimiter**

`parse_param_list` expects `(` already consumed and `)` after. For `lalin.params[[]]`:

```lalin
lalin.params[[x: i32, y: i32]]  
```

Should this parse `x: i32, y: i32` (no parens) or `(x: i32, y: i32)` (with parens)? 

- If WITH parens: the entry point consumes `(`, calls `parse_param_list()`, expects `)`. Users write `lalin.params[[(x: i32, y: i32)]]`. This matches the grammar position where params appear.
- If WITHOUT parens: the entry point just calls `parse_param_list()` directly. Users write `lalin.params[[x: i32, y: i32]]`. Cleaner but one fewer token.

For the combinator that calls this from inside `parse_func`, the parens are already consumed (`self:expect(TK.lparen); ...; self:expect(TK.rparen)`). The combinator would call the internal `parse_param_list` (no parens) on the token window between lparen and rparen.

**The standalone entry point and the combinator entry point have different delimiter expectations.** This means either:
- (a) `lalin.params[[]]` accepts parens (matches the grammar position), and the combinator extracts the paren-delimited substring before calling
- (b) `lalin.params[[]]` accepts bare lists (no parens, clean API), and the combinator calls the internal version which also expects bare lists

If (a), the combinator must strip parens from the substring before passing to the standalone entry point. If (b), the standalone entry point doesn't match any real grammar position — params always appear between parens in real Lalin syntax.

**12. The expander's `SlotValue*` types create an assumption about fill order**

When `open_expand` encounters a spread sentinel in a param name, it does:

```lua
local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
if #values == 1 and pvm.classof(values[1]) == O.SlotValueParams then
    for j = 1, #values[1].params do
        local p = values[1].params[j]
        out[#out + 1] = pvm.with(p, { ty = one(expand_type, p.ty, env) })
    end
end
```

It expects a `SlotValueParams` — a typed binding created by `host_splice.fill_param_list`. The fill step (in `host_splice.lua`) looks at the Lua value and decides whether it's a `Param[]`, a list of ParamValues, or a list of {name, type} tables.

In the combinator model, if `lalin.params[[@{params...}]]` is called, the spread slot gets filled eagerly by the sub-parser's fill step. The sub-parser returns clean `Param[]`. The combinator then assembles the `FuncLocal` node. The expander never sees sentinel names — it just expands types within the already-resolved params.

**But what if the combinator wants to pass the spread through?** The sub-parser creates a `SlotRegion` for the spread, records it in `splice_slots`, and embeds a sentinel name. The combinator can access `splice_slots`, fill them from the island-level values table, and pass the resulting clean `Param[]` to the `FuncLocal` constructor. **Or** the combinator can leave the sentinel names in place, assemble a slot-ridden `FuncLocal` node, and let the module-level expander handle it.

**Both approaches are valid.** The choice determines whether fill happens eagerly (at combinator time) or lazily (at expand time). Eager fill means the combinator is more self-contained. Lazy fill means less overhead for the combinator but requires the expander to see the same slot ID space.

---

### Knowledge Gaps

1. **How does `host_splice.fill_param_list` decide what constitutes a param?** I understand the coercion paths, but I need to verify how the fill functions handle the case where the Lua value is itself a `Param[]` ASDL array versus a list of host `ParamValue` objects. This determines what `lalin.params[[]]` can accept as fill values.

2. **How does the PVM memoization interact with sub-parser boundaries?** The PVM records compilation triplets. If sub-parsers each create their own `T` context (with `pvm.context()`), the memoization caches are separate. If they share a `T`, slots from different sub-parsers flow into the same memo cache. I need to verify that slot identity (by ASDL node pointer) is preserved across sub-parser calls vs. being recreated fresh.

3. **What happens to `emit` references across island boundaries?** A `region` fragment's name is referenced by `emit` from other islands. The name resolution is via `NameRefText(text)` or `NameRefSlot(slot)`. If `lalin.region[[]]` produces a `RegionFrag` whose name is `NameRefText("my_region")`, the `emit` parser (in a different island) needs to find it by name. This doesn't go through combinators — it's cross-island. But if the combinator changes how the `RegionFrag` name is represented (e.g., adding a different prefix), `emit` resolution breaks.

## Approach-proposer Output — 2026-05-19 09:08:10

Good. I now have a thorough picture of all moving parts. Here are three genuinely distinct approaches.

---

### Approach A: "Deep Quoting" — Everything is a String

**Core idea**: Every Lalin construct gets a `lalin.XXX[[]]` string-parsing form. Table builders are thin convenience wrappers that delegate to the string parsers internally. No `function(b) ... end` remains.

---

**Key changes**:

**1. Full API surface**

| `lalin.XXX` | Form | Returns |
|---|---|---|
| `lalin.type[[]]` | `[[i32]]`, `[[ptr(u8)]]`, `[[func(i32) -> i32]]` | `TypeValue` |
| `lalin.expr[[]]` | `[[x + 1]]`, `[[as(i32, val)]]` | `ExprValue` |
| `lalin.stmts[[]]` | `[[let y: i32 = x + 1; return y]]` | `Stmt[]` |
| `lalin.func[[]]` | `[[add(a: i32, b: i32) -> i32 return a + b end]]` | `FuncValue` |
| `lalin.region[[]]` | `[[scan(p: ptr(u8); hit: cont(v: i32)) entry ... end]]` | `RegionFragValue` |
| `lalin.expr_frag[[]]` | `[[inc(x: i32) -> i32 x + 1 end]]` | `ExprFragValue` |
| `lalin.struct[[]]` | `[[Point x: i32; y: i32 end]]` | `StructValue` |
| `lalin.union[[]]` | `[[Option Some(i32) \| None end]]` | `StructValue` |
| `lalin.extern[[]]` | `[[write(fd: i32, buf: ptr(u8)) -> i32 end]]` | `FuncValue` (extern-kind) |
| `lalin.params[[]]` | `[[x: i32, readonly y: ptr(u8)]]` | `Param[]` |
| `lalin.fields[[]]` | `[[x: i32; y: f64]]` | `FieldDecl[]` |
| `lalin.variants[[]]` | `[[Some(i32) \| None]]` | `VariantDecl[]` |
| `lalin.conts[[]]` | `[[hit: cont(v: i32), miss: cont()]]` | `ContSlot[]` |
| `lalin.open_params[[]]` | `[[val: i32, target: ptr(u8)]]` | `OpenParam[]` |
| `lalin.blocks[[]]` | `[[block loop(i: i32 = 0) if ... end end]]` | `ControlBlock[]` |
| `lalin.param{...}` | `{ name, type, mods? }` | `ParamValue` (thin wrapper) |
| `lalin.field{...}` | `{ name, type }` | `FieldValue` (thin wrapper) |
| `lalin.variant{...}` | `{ name, payload?, fields? }` | variant table (thin wrapper) |

**2. `@{}` story** — Two-tier:

- **Simple values** (types, expressions, names): resolved via **closure capture**. The standalone quote parser evaluates `@{expr}` by calling `load("return " .. splice_text)` in the caller's environment. The parser captures `_ENV` from the calling frame using `debug.getinfo(2, "f").func` (safe inside LuaJIT — gives the actual function, not its closure env). This works for simple variable references like `@{T}`, `@{limit}`.

- **Complex/spread values** (spread lists, region fragments): use an **explicit second argument table**. `lalin.stmts("let x: @{T} = @{val}; @{body...}", { T = my_type, val = lalin.int(42), body = my_stmts })`. The parser checks: if the splice text is a single identifier that exists in the explicit table, use that; otherwise fall back to closure capture.

- **Rationale**: Simple single-identifier `@{x}` is the 90% case and closure capture makes it zero-friction. Multi-token `@{my_type_value}` and spread `@{list...}` need explicit tables because Lua `load` can't evaluate `my_type_value` as an expression — it's a Lua local that the parser can't name (types are tables, not values you can `load`).

**3. Builder remnant**: None. `function(b) ... end` is dead. Codegen uses string concatenation or explicit arrays:

```lua
-- Before:
lalin.stmts({ x = lalin.i32 }, function(b)
    local y = b:let("y", lalin.i32, b.x + 1)
    b:return_(y)
end)

-- After:
local x_binding = { name = "x", type = lalin.i32 }
lalin.stmts([[
    let y: i32 = @{x_binding} + 1
    return y
]], { x_binding = ... })
-- Or more practically, the binding is implicit via function scope:
local x = lalin.int(0) -- just for the expression value
lalin.stmts([[let y: i32 = @{x} + 1; return y]], { x = x })
```

For loops:
```lua
-- Generate N params:
local params = {}
for i = 1, N do
    params[i] = lalin.param { name = "x" .. i, type = lalin.i32 }
end
-- Then use the array:
lalin.func[["add(" .. table.concat(params_str, ", ") .. ") -> i32 return ... end"]]
```

**4. Table format**: Each table builder returns a `*Value` wrapper (same as current `lalin.param`, `lalin.field`). The table form IS the table — the positional args form (`lalin.param("x", lalin.i32)`) is the current API, which gets renamed to the table form `lalin.param { name = "x", type = lalin.i32 }`.

| Builder | Table schema |
|---|---|
| `lalin.param { name, type, mods? }` | `{ name: string, type: TypeValue, mods?: { noalias?, readonly?, writeonly? } }` |
| `lalin.field { name, type }` | `{ name: string, type: TypeValue }` |
| `lalin.variant { name, payload?, fields? }` | `{ name: string, payload?: TypeValue, fields?: { name: string, type: TypeValue }[] }` |
| `lalin.entry_param { name, type, init }` | `{ name: string, type: TypeValue, init: ExprValue }` |
| `lalin.cont { params? }` | `{ params?: lalin.param[] }` |
| `lalin.block { label, params, body }` | `{ label: string, params?: ..., body: Stmt[] or string }` |

**5. Parser extraction**: Every sub-grammar in parse.lua gets extracted as `M.parse_XXX_string(T, src, opts)`:

- `parse_type_string` and `parse_stmt_string` already exist.
- `parse_expr_string` — extract from `Parser:parse_expr()` but without the `self:skip_nl()` before; just call `self:parse_expr(0)`.
- `parse_params_string` — wrap `Parser:parse_param_list()` with parentheses handling (accept optional parens).
- `parse_fields_string` — extract the field loop from `parse_struct_island()`.
- `parse_variants_string` — extract the variant loop from `parse_union_island()`.
- `parse_conts_string` — wrap `Parser:parse_cont_params()` with parens.
- `parse_open_params_string` — wrap `Parser:parse_open_params()` with parens.
- `parse_func_string` — extract `parse_func()` minus the keyword.
- `parse_region_string` — extract `parse_region_frag()` minus keyword + parens.
- `parse_struct_string` — extract `parse_struct_island()` minus keyword.
- `parse_union_string` — extract `parse_union_island()` minus keyword.
- `parse_extern_string` — extract `parse_extern()` minus keyword.

The island parsers in `parse_island()` are NOT combinatorized — they stay monolithic, calling their internal `self:parse_func()` etc. The new `M.parse_func_string()` is a thin wrapper that calls `M.lex(src)`, creates a parser, and delegates to the same internal method. **Shared code, not combinator restructuring.**

**6. Migration path**:

```
Phase 1: Add M.parse_XXX_string() functions (extract from existing methods)
Phase 2: Add host_xxx_api.lua — wires lalin.XXX[[]] metatable to each parser
Phase 3: Add lalin.param{...} etc. (table wrappers alongside old positional form)
Phase 4: Deprecate lalin.param("x", i32) positional form
Phase 5: Document migration: lalin.stmts(fn) → lalin.stmts[[]]; lalin.param("x", i32) → lalin.param{name="x", type=lalin.i32}
```

**7. Codegen story**: Yes. `for i = 1, N do params[i] = { name = "x" .. i, type = lalin.i32 } end` works directly with the table builders. The params array then gets used as `lalin.params[[@{params...}]]` with the explicit values table, or the strings are concatenated.

---

**Tradeoff**: Optimizes for readability — Lalin syntax everywhere, minimal Lua scaffolding. Sacrifices: closure capture for `@{}` is fragile (LuaJIT `load` scoping), the `lalin.params[[]]` strings for param lists are ugly for dynamic codegen, and the parser grows ~15 new entry points.

**Risk**: Closure capture via `load` breaks under LuaJIT JIT compilation if the function is inlined. The explicit table fallback must handle every case gracefully or users get silent failures. String-concatenated Lalin is syntactically fragile — forgetting a space between tokens produces cryptic parse errors.

---

### Approach B: "Data-Driven" — Tables as Values, Strings as Glue

**Core idea**: Declaration-shaped things (params, fields, variants, conts, blocks) use standardized Lua table schemas — they ARE data, not code. Code-shaped things (stmts, expr, type) use string quoting. Islands get a **constructor function** form that takes tables and strings, not quoting. No `function(b) ... end` remains.

---

**Key changes**:

**1. Full API surface**

| `lalin.XXX` | Form | Returns |
|---|---|---|
| `lalin.type { ... }` | `{ kind, args... }` declarative table | `TypeValue` |
| `lalin.type[[]]` | `[[i32]]`, `[[ptr(u8)]]` | `TypeValue` |
| `lalin.expr[[]]` | `[[x + 1]]` | `ExprValue` |
| `lalin.stmts[[]]` | `[[let y: i32 = x + 1; return y]]` | `Stmt[]` |
| `lalin.stmts { ... }` | `{ stmt1, stmt2, ... }` (array of raw ASDL) | `Stmt[]` |
| `lalin.func { ... }` | declarative table with `params`, `result`, `body` | `FuncValue` |
| `lalin.region { ... }` | declarative table with `params`, `conts`, `body` | `RegionFragValue` |
| `lalin.expr_frag { ... }` | declarative table | `ExprFragValue` |
| `lalin.struct { name, fields }` | `{ name, fields: FieldDecl[] }` | `StructValue` |
| `lalin.union { name, variants }` | `{ name, variants: VariantDecl[] }` | `StructValue` |
| `lalin.extern { ... }` | declarative table | `FuncValue` (extern) |
| `lalin.param { ... }` | `{ name: string, type: TypeValue, mods? }` | raw `Param` ASDL table |
| `lalin.field { ... }` | `{ name: string, type: TypeValue }` | raw `FieldDecl` ASDL table |
| `lalin.variant { ... }` | `{ name, payload?: TypeValue, fields? }` | raw `VariantDecl` ASDL table |
| `lalin.cont { ... }` | `{ name, params?: { name, type }[] }` | raw table |
| `lalin.block { ... }` | `{ label, params?, body: Stmt[] or string }` | `ControlBlock` |
| `lalin.entry_param { ... }` | `{ name, type, init }` | raw `EntryBlockParam` ASDL |

**Key design choice**: `lalin.param { ... }` returns a **raw ASDL `Ty.Param`** node (not a `ParamValue` wrapper). This eliminates the need for `param_decls()` extractors and normalization layers. The output IS the input to the function/region constructors. The `lalin.func { params = {...}, body = [[...]] }` form consumes them directly.

```lua
local adder = lalin.func {
    name = "add",
    params = {
        { name = "a", type = lalin.i32 },
        { name = "b", type = lalin.i32 },
    },
    result = lalin.i32,
    body = lalin.stmts [[return a + b]],
}
```

**2. `@{}` story**: **Not supported in standalone calls.** Standalone quotes (`lalin.stmts[[]]`, `lalin.expr[[]]`, `lalin.type[[]]`) do not evaluate `@{}`. If a splice is detected, the parser errors (same as current behavior). Interpolation is done via Lua string concatenation:

```lua
-- Safe: the parser always treats input as Lalin
local body = lalin.stmts [[let y: i32 = ]] .. tostring(val) .. [[; return y]]
```

The `tostring(val)` for expression/type values is defined to produce valid Lalin source text. Each `*Value` type has `__tostring` that round-trips through the parser.

**3. Builder remnant**: None. `function(b) ... end` is dead. The `lalin.stmts[[]]` form combined with table concatenation handles all cases:

```lua
-- Before:
local body = lalin.stmts({ x = lalin.i32 }, function(b)
    b:if_(b.x > 10, function(t)
        t:expr(b.x + 1)
    end, function(f)
        f:return_(b.x)
    end)
end)

-- After:
local body = lalin.stmts [[
    if x > 10 then
        x + 1
    else
        return x
    end
]]
-- The parser handles scoped if-else. If you need dynamic condition:
local body = lalin.stmts [[
    if ]] .. cond_src .. [[ then
        ...
    end
]]
```

**4. Table format**: Each builder returns a raw ASDL or duck-typed table that's consumed directly by the parent constructor. No wrapper metatables.

```lua
-- Entries are plain tables with name/type keys:
local params = {
    { name = "a", type = lalin.i32 },
    { name = "b", type = lalin.i32 },
}
-- These ARE the ASDL Ty.Param nodes if type is raw ASDL type, or get converted:
-- lalin.func checks: if type field is a TypeValue, extract .ty
-- if type field is already a LalinType.Type, pass through
```

**5. Parser extraction**: Minimal. Only `parse_type_string` and `parse_stmt_string` exist as standalone entries. `lalin.expr[[]]` requires extracting `parse_expr()` but that's just `Parser:parse_expr(0)` with EOF checking. No new island entry points — islands are constructed via `lalin.func { ... }` tables.

The key new parser function is `lalin.stmts_to_lalin_string(stmts)` — a **printer** that converts ASDL back to Lalin source text. This is needed because `lalin.stmts` concatenation `lalin.stmts[["x > "]] .. lalin.stmts[["10"]]` should produce valid concatenated Lalin, not nested ASDL.

Actually, the concatenation doesn't compose ASDL — it composes strings. The printer exists only for debugging and for the values table approach above.

**6. Migration path**:

```
Phase 1: Add lalin.expr[[]] (extract parse_expr)
Phase 2: Add lalin.func { }, lalin.region { }, lalin.struct { } etc. (declarative table constructors)
Phase 3: Add lalin.param { } etc. that return raw ASDL
Phase 4: Deprecate lalin.stmts(fn), lalin.stmts(string), lalin.func_type(...) etc.
Phase 5: Remove builders: lalin.region_frag(name, params, conts, fn) etc.
```

**7. Codegen story**: Yes, `for i = 1, N do table.insert(params, { name = "x" .. i, type = lalin.i32 }) end` works directly. The table IS the data:

```lua
local params = {}
for i = 1, N do
    params[i] = { name = "var" .. i, type = lalin.i32 }
end
-- Then use anywhere a param list is expected:
lalin.func { name = "gen", params = params, result = lalin.i32, body = ... }
```

---

**Tradeoff**: Optimizes for **determinism and debuggability** — no closure capture, no magic `load`, no fragile string concatenation. Everything is explicit Lua data. Sacrifices: island definitions require more Lua boilerplate (nested tables instead of a single `[[]]` quote), `lalin.stmts` concatenation is awkward for dynamic statement bodies, and the table schema for complex things like regions (with nested entry/blocks) is verbose.

**Risk**: The table schema for a region fragment is deeply nested (entry params, block params, stmts, possibly protocol references). Getting the schema right for all cases is non-trivial. String concatenation for `lalin.stmts` loses type safety — a missing space produces a parse error at runtime, not a compile error. The ASDL types exposed as table fields (raw `Ty.Param` nodes) put more of the internal type system in user-facing API.

---

### Approach C: "Hybrid Island" — Islands are Quotes, Fragments are Tables

**Core idea**: Full island definitions (func, region, struct, union, extern) ALWAYS use `lalin.XXX[[]]` quoting — they're large enough that Lalin syntax wins. Declaration fragments (params, fields, variants, conts, blocks) use table builders because codegen needs iteration. Stmts/expr/type get BOTH quoting and table forms. The parser is refactored: sub-grammar helpers are extracted as reusable internal functions, but the island parsers stay monolithic and import the helpers rather than being combinator structures.

---

**Key changes**:

**1. Full API surface**

| `lalin.XXX` | Form | Returns | Notes |
|---|---|---|---|
| `lalin.type[[]]` | `[[i32]]`, `[[ptr(u8)]]` | `TypeValue` | No table form — types are simple |
| `lalin.expr[[]]` | `[[x + 1]]` | `ExprValue` | Table form: `lalin.expr { kind="add", lhs=..., rhs=... }` |
| `lalin.stmts[[]]` | `[[let y = x + 1; return y]]` | `Stmt[]` | Table form: `lalin.stmts { stmt1, stmt2 }` |
| `lalin.func[[]]` | `[[add(a: i32, b: i32) -> i32 return a + b end]]` | `FuncValue` | ONLY quoting — too complex for tables |
| `lalin.region[[]]` | `[[scan(...) entry ... end]]` | `RegionFragValue` | ONLY quoting |
| `lalin.expr_frag[[]]` | `[[inc(x: i32) -> i32 x+1 end]]` | `ExprFragValue` | ONLY quoting |
| `lalin.struct[[]]` | `[[Point x: i32; y: i32 end]]` | `StructValue` | ONLY quoting |
| `lalin.union[[]]` | `[[Option Some(i32) | None end]]` | `StructValue` | ONLY quoting |
| `lalin.extern[[]]` | `[[write(fd: i32, ...) end]]` | `FuncValue` | ONLY quoting |
| `lalin.params { }` | `{ { name, type, mods? }, ... }` | `ParamValue[]` | ONLY table — iteration need |
| `lalin.fields { }` | `{ { name, type }, ... }` | `FieldValue[]` | ONLY table |
| `lalin.variants{ }` | `{ { name, payload?, fields? }, ... }` | variant arr | ONLY table |
| `lalin.conts { }` | `{ [name] = { params? }, ... }` | named map | ONLY table — named map, not array |
| `lalin.blocks { }` | `{ { label, params?, body? }, ... }` | arr + body | ONLY table |

**2. `@{}` story** — **Explicit values table ONLY**, no closure capture. Every `lalin.XXX[[]]` that supports `@{}` accepts an optional second argument: the values table.

```lua
-- Simple case: no @{}, just the quote
local f = lalin.func[[add(a: i32, b: i32) -> i32 return a + b end]]

-- With @{}: pass values in second arg
local T = lalin.i32
local v = lalin.int(42)
lalin.stmts("let x: @{T} = @{v}; return x", { T = T, v = v })
```

For spread lists:
```lua
lalin.func([[
    add(@{params...}) -> i32
        return @{body}
    end
]], { params = param_list, body = body_stmts })
```

The filling follows the same `host_splice.fill()` path as `.mlua` islands — the same coercion logic, the same role dispatch.

**`protocol_types`** for regions that reference union protocols: passed as a third optional argument or as a key in the opts table:

```lua
lalin.region[["unwrap(val: Option(i32); some: cont(v: i32), none: cont()) ... end"]]
-- If Option isn't already in the parser's protocol_types:
lalin.region[[...]], { protocol_types = { Option = [{ name="Some", ... }, { name="None", ... }] } }
```

**3. Builder remnant**: None for statement-level construction. The `function(b)` pattern is replaced by:
- `lalin.stmts[[]]` with `@{}` for bodies that reference values from Lua
- Table construction for params/fields/variants/conts
- `lalin.blocks { ... }` for block definitions

The `lalin.region[[]]` form handles the entire region structure — entry, blocks, continuations — in one quote. There's no need for `RegionBuilder:entry()`, `RegionBuilder:block()`, etc. If you need to generate blocks in a Lua loop, you construct `lalin.blocks { }` entries and pass them as `@{}`:

```lua
local generated_blocks = {}
for i = 1, N do
    generated_blocks[i] = lalin.blocks {
        label = "handle_" .. i,
        params = { { name = "val", type = lalin.i32 } },
        body = lalin.stmts[["jump done(result = val)"]],
    }
end
-- But the region body already contains blocks — how do you splice them in?
-- Answer: the region body is entirely within the quote. For generated blocks,
-- you'd construct the entire region as a Lua function that builds the string:
local region_src = [[
    scan_for(p: ptr(u8), n: i32; done: cont(result: i32))
    entry loop(i: i32 = 0)
        if i >= n then jump done(result = 0) end
        jump loop(i = i + 1)
    end
]]
for i = 1, N do
    region_src = region_src .. [[
    block handle_]] .. i .. [[(val: i32)
        jump done(result = val)
    end
]]
end
region_src = region_src .. [[end]]
local frag = lalin.region[[@{region_src}]], { region_src = region_src })
```

This is awkward. A better pattern: the region body accepts **one spread slot** for generated blocks:

```lalin
lalin.region [[
    dispatch(p: ptr(u8), n: i32, target: i32;
             found: cont(pos: i32),
             not_found: cont())
    entry loop(i: i32 = 0)
        if i >= n then jump not_found() end
        if p[i] == target then jump found(pos = i) end
        jump loop(i = i + 1)
    end
    @{extra_blocks...}
end
]], { extra_blocks = generated_blocks })
```

**4. Table format**:

```lua
-- params: positional array of param descriptors
lalin.params {
    { name = "a", type = lalin.i32 },
    { name = "xs", type = lalin.ptr(lalin.u8), mods = { noalias = true, readonly = true } },
}

-- fields: array of field descriptors
lalin.fields {
    { name = "x", type = lalin.i32 },
    { name = "y", type = lalin.f64 },
}

-- variants: array of variant descriptors  
lalin.variants {
    { name = "Some", payload = lalin.i32 },
    { name = "None" },
    { name = "Pair", fields = { { name = "a", type = lalin.i32 }, { name = "b", type = lalin.f64 } } },
}

-- conts: named map (keyed by continuation name)
lalin.conts {
    hit = { params = { { name = "pos", type = lalin.i32 } } },
    miss = { params = {} },
}

-- blocks: array with body
lalin.blocks {
    { label = "loop", params = { { name = "i", type = lalin.i32, init = lalin.int(0) } },
      body = lalin.stmts[["..."]] },
}
```

**5. Parser extraction**: Refactor parse.lua to extract sub-grammar helpers as **internal module-level functions** (not `M.parse_XXX_string` — those are host-facing wrappers). The internal helpers are used by BOTH the standalone entry points AND the monolithic island parsers:

```lua
-- Internal helpers (used by both island parsers and standalone wrappers):
local function _parse_params(p) ... end  -- extracted from Parser:parse_param_list
local function _parse_fields(p) ... end  -- extracted from struct field loop
local function _parse_cont_params(p) ... end
local function _parse_open_params(p) ... end
local function _parse_block_params(p, is_entry) ... end
local function _parse_func_body(p) ... end

-- Island parsers remain monolithic but call internal helpers:
function Parser:parse_func()
    local name = ...
    self:expect(TK.lparen)
    local params = _parse_params(self)  -- was self:parse_param_list()
    self:expect(TK.rparen)
    ...
end

-- Standalone wrappers (for lalin.XXX[[]]):
function M.parse_func_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:expect(TK.func_kw)
    local params, contracts = _parse_params(p)
    -- But wait, parse_func expects to parse name, lparen, params, rparen, arrow, result, body...
    -- This doesn't compose cleanly because the island parser sequence isn't modular at that level.
end
```

**Refined extraction strategy**: Instead of extracting individual token sequences, extract **grammar phases** that correspond to the existing `Parser:` method boundaries, because those already match the grammar:

```lua
-- Already extracted:
M.parse_type_string  -- (exists)
M.parse_stmt_string  -- (exists)

-- New standalone entry points (each is a thin M.lex + new_parser + delegate):
M.parse_expr_string  -- Parser:parse_expr(0) with EOF check
M.parse_func_string  -- Parser:parse_func() with func_kw consumed
M.parse_region_string -- Parser:parse_region_frag() with region_kw consumed  
M.parse_struct_string -- Parser:parse_struct_island() with struct_kw consumed
M.parse_union_string  -- Parser:parse_union_island() with union_kw consumed
M.parse_extern_string -- Parser:parse_extern() with extern_kw consumed

-- The island parsers in parse_island() stay as-is, calling their own Parser: methods
-- The standalone wrappers call the same Parser: methods on a fresh parser
-- This is code sharing at the leaf level, not combinatorial restructuring
```

The only new standalone entry point that is NOT a simple island-wrapping is `lalin.params`, `lalin.fields`, `lalin.variants`, `lalin.conts`, `lalin.blocks` — but those are **table-based**, not string-based. They don't need parser extraction at all. They're just table consumers in `host_session`.

Wait — approach C says islands are quotes and fragments are tables. So `lalin.params[[]]` doesn't exist. Only `lalin.params { }` exists. No parser extraction needed for those.

`lalin.blocks` IS table-based, so also no parser extraction.

So the parser extraction for approach C is:
- `M.parse_expr_string` — new, extract from `Parser:parse_expr()`
- `M.parse_func_string` — new, extract from `Parser:parse_func()`
- `M.parse_region_string` — new, extract from `Parser:parse_region_frag()`
- `M.parse_struct_string` — new, extract from `Parser:parse_struct_island()`
- `M.parse_union_string` — new, extract from `Parser:parse_union_island()`
- `M.parse_extern_string` — new, extract from `Parser:parse_extern()`

Each is a thin wrapper (5-10 lines). The island parsers in `parse_island()` stay as-is. The internal `Parser:` methods don't change.

**6. Migration path**:

```
Phase 1: Add table builders: lalin.params{}, lalin.fields{}, lalin.variants{}, lalin.conts{}, lalin.blocks{}
         (these replace lalin.param(), lalin.field(), lalin.variant(), lalin.cont(), lalin.control_block())
Phase 2: Add lalin.expr[[]] standalone entry point  
Phase 3: Add lalin.func[[]], lalin.region[[]], lalin.struct[[]], lalin.union[[]], lalin.extern[[]]
         (these replace lalin.region_frag(), lalin.expr_frag(), lalin.struct(), lalin.union())
Phase 4: Enable @{} in lalin.stmts[[]] (currently blocked by the conservative guard)
Phase 5: Deprecate and remove all host_*_values builder methods: lalin.param(), lalin.field(), 
         lalin.cont(), lalin.control_block(), lalin.region_frag(), lalin.expr_frag(),
         and all builder sub-methods (b:let(), b:if_(), b:jump(), b:return_(), etc.)
```

**7. Codegen story**: Yes.

```lua
-- Generate N params for a function:
local params = {}
for i = 1, N do
    params[i] = { name = "x" .. i, type = lalin.i32 }
end
-- Use as @{} inside a function quote:
local gen = lalin.func([[
    generated_add(@{params...}) -> i32
        return x1 + x2@<N
    end
]], { params = params })
-- Or construct the function body as a string for the result expression:
```

---

**Tradeoff**: Optimizes for **clarity at scale** — island definitions (the largest constructs) get full Lalin syntax, declaration fragments (the ones iteration touches) get concise Lua tables. The boundary matches the user's mental model: "definitions are text, lists are data." Sacrifices: region codegen with dynamic blocks is awkward (spread slot for blocks), the table schema for `lalin.conts{}` (named map) differs from `lalin.params{}` (positional array) adding inconsistency, and the parser still hosts both refactored and non-refactored paths.

**Risk**: The block-generation problem for regions is the hardest. A region with dynamic blocks under Lua iteration either uses string concatenation (fragile) or passes a `@{}` block spread. The spread approach works but requires the region quote to reserve a spread slot. This adds one more thing for users to learn. If the spread slot interacts badly with the parser's block-loop logic (which expects `block_kw` or `hole` at specific positions), the parser needs awareness of spread slots in that position.

---

### Comparison

| Dimension | Approach A (Deep Quoting) | Approach B (Data-Driven) | Approach C (Hybrid Island) |
|---|---|---|---|
| **Quote depth** | Everything, including params/fields/variants | Only type/stmts/expr | Islands only (func/region/struct/union/extern) |
| **Table forms** | Thin wrappers around parsers | The primary API for everything non-code | Islands have NO table form; fragments have NO quote form |
| **`@{}` mechanism** | Closure capture (simple) + explicit table (complex) | Not supported in standalone | Explicit values table only |
| **Builder remnant** | None | None | None |
| **Parser refactoring** | Every sub-grammar → `M.parse_XXX_string()` | Only `M.parse_expr_string()` new | 5-6 thin island wrappers, no internal refactoring |
| **Parser architecture** | Combinator: island parsers call sub-parsers | Monolithic: island parsers unchanged | Monolithic with shared internal helpers |
| **Table format** | Returns `*Value` wrappers (metatables) | Returns raw ASDL/duck tables | Returns `*Value` wrappers |
| **Migration cost** | High (all 15+ entry points, closure capture tricky) | Medium (table schema design, no new parser work) | Medium (only islands extracted, fragments are new code) |
| **Codegen loops** | String concatenation + `@{}` spread | Table construction + string concat | Table construction + `@{}` spread for blocks |
| **Region codegen** | String concatenation (clunky) | Table schema for entire region (verbose but explicit) | Quote + spread slot (elegant for simple, clunky for complex) |
| **Error messages** | Parse-time relative to quote string | No change | Parse-time relative to quote string |
| **Learning curve** | Most Lalin syntax, least Lua API surface | Most Lua API surface, least Lalin syntax | Balanced: island syntax learned once, table API small |
| **Maintainability** | Sub-parser refactoring is invasive but the result is clean | Minimal parser changes, but table schemas in host code are many | Targeted extraction, low risk, moderate clean-up |

**When to pick each**:

- **Pick Approach A (Deep Quoting)** if the primary use case is writing new Lalin code from scratch, and the existing codebase's builder usage is small enough to rewrite. The "everything is Lalin string" vision is the most coherent but requires the most migration.

- **Pick Approach B (Data-Driven)** if the existing builder API is heavily used and the transition must be incremental without touching the parser much. The table schemas are more familiar to Lua programmers and avoid the `@{}` complexity entirely. Best for teams who think in Lua data structures.

- **Pick Approach C (Hybrid Island)** if you want the cleanest split between "things that look like code" and "things that look like data." Islands are text because they're large; fragments are tables because they're small and iterated. This is the approach I'd recommend as the best engineering bet — it correctly identifies where Lalin syntax adds value (island definitions) and where Lua tables add value (fragment lists), without over-extending the parser or introducing closure capture complexity.

## Documenter Output — 2026-05-19 09:26:48

# Unified `lalin.XXX` Metaprogramming API — Architectural Decision Record

**Date**: 2026-05-19  
**Phase**: Architecture (precedes implementation planning and code migration)  
**Workflow**: wf-meta-ergo (derived from prior `.pi/workflows/wf-meta-ergo.md` analysis)

---

## Goal

Replace the current three-path metaprogramming layer — source islands (`.mlua` carrier model), `lalin.stmts[[]]` string snippets that reject `@{}`, and the `function(b)` builder API — with a single unified API whose shape is: **every `lalin.XXX` is either a parser (Lalin string in, typed ASDL out) or a table builder (Lua table in, typed ASDL out).** The `function(b)` builder pattern is retired. Every construct that can be expressed as Lalin syntax uses a `lalin.XXX[[]]` quote; every construct that is inherently a Lua data structure (param lists, field lists, variant lists) uses a `lalin.XXX { }` table constructor. Splices (`@{}`) in quotes are resolved via an explicit values table — no closure capture, no `debug.getlocal` magic.

---

## Incentives

The existing metaprogramming surface grew three distinct and incompatible paths for constructing Lalin ASDL from Lua:

1. **Source islands** (`.mlua` carrier model): Full Lalin grammar embedded in Lua source strings, parsed at `.mlua` load time with full splice support via carrier closures. Powerful but requires the `.mlua` runtime pipeline — not usable from plain Lua.

2. **`lalin.stmts[[]]` snippets**: Parse a string as Lalin statements, return `Stmt[]`. Convenient but **rejects `@{}`** — the conservative guard (`if #parsed.splice_slots ~= 0 then error(...) end`) makes it impossible to reference Lua values inside a quote. Users must fall back to the builder.

3. **`function(b)` builders**: `lalin.stmts({x=lalin.i32}, function(b) b:let("y", lalin.i32, b.x + 1); b:return_(y) end)`. Full power but verbose, nested, and requires learning a separate Lua API that parallel's the Lalin grammar. 14+ builder methods (`b:let`, `b:if_`, `b:switch_`, `b:return_`, `b:jump`, `b:yield_`, `b:emit`, etc.) that duplicate what Lalin syntax already expresses.

The concrete costs:

- **Cognitive overhead**: Users must learn two APIs for the same thing — Lalin syntax and the builder API. Switching between them is context-dependent and inconsistent.
- **Codegen verbosity**: A simple `if` statement requires nested callbacks: `b:if_(cond, function(t) ... end, function(f) ... end)`. The same logic in Lalin syntax is `if cond then ... else ... end`.
- **Maintenance burden**: 14 builder methods in `host_func_values.lua`, 6 in `host_struct_values.lua`, 10+ in `host_region_values.lua` — each needing separate documentation, testing, and type coercion logic that parallels the parser.
- **Incomplete quoting**: `lalin.stmts[[]]` supports quoting but can't reference Lua values. `lalin.func[[]]` doesn't exist. The quoting surface is ad-hoc, not systematic.
- **Splice fragility**: The `.mlua` carrier model handles splices via generated closures, which can't be replicated in plain Lua without `debug.getlocal` — which is unreliable under LuaJIT JIT compilation (frame depth shifts with for loops, inlining, temporary slots). Testing confirmed that `debug.getlocal`-based closure capture is not viable for production.

---

## Current State

### Three-path architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ Path 1: Source islands (within .mlua files)                      │
│  .mlua file → scan_document → island extraction → tokenize       │
│  → parse_island(kind) → splice resolution via carrier closures   │
│  → typecheck → compile                                            │
│  Only works inside the .mlua loader pipeline.                     │
├──────────────────────────────────────────────────────────────────┤
│ Path 2: String snippets (from plain Lua)                         │
│  lalin.stmts("let x: i32 = 42; return x")                        │
│  → parse_stmt_string() → Parsed ASDL (rejects @{})              │
│  lalin.type("i32") → parse_type_string() → TypeValue              │
│  No other lalin.XXX[[]] forms exist.                              │
├──────────────────────────────────────────────────────────────────┤
│ Path 3: function(b) builder (from plain Lua)                     │
│  lalin.stmts({ x = lalin.i32 }, function(b)                        │
│      local y = b:let("y", lalin.i32, b.x + 1)                    │
│      b:return_(y)                                                │
│  end)                                                             │
│  → Builder methods construct ASDL nodes programmatically          │
│  14+ methods across host_func_values.lua, host_region_values.lua,│
│  host_struct_values.lua, host_expr_values.lua                    │
└──────────────────────────────────────────────────────────────────┘
```

### Files and modules involved

| File | Role | Current entry points |
|---|---|---|
| `lua/lalin/parse.lua` (2384 lines) | Lexer + Pratt parser, all island kinds | `parse_type(src)`, `parse_stmts(src)`, `parse_island(scan,i)`, `parse_module(src)` |
| `lua/lalin/host.lua` (40 lines) | Thin public facade | `lalin.stmts`, `lalin.type`, etc. |
| `lua/lalin/host_func_values.lua` (450 lines) | Statement/param/control-block builders | `api.stmts()`, `api.param()`, `api.control_block()`, builder methods |
| `lua/lalin/host_struct_values.lua` (250 lines) | Struct/union/field/variant builders | `api.field()`, `api.variant()`, `api.struct()`, `api.union()` |
| `lua/lalin/host_type_values.lua` (130 lines) | Type builders | `api.ptr()`, `api.array()`, `api.view()`, `lalin.i32`, etc. |
| `lua/lalin/host_expr_values.lua` (280 lines) | Expression builders | `api.int()`, `api.bool_lit()`, operator overloads, `api.ref()` |
| `lua/lalin/host_region_values.lua` (430 lines) | Region fragment builders | `api.entry_param()`, `api.cont()`, `api.region_frag()`, `RegionBuilder` |
| `lua/lalin/host_fragment_values.lua` (140 lines) | Expr fragment builders | `api.expr_frag()`, `api.emit_expr()`, `ExprFragBuilder` |
| `lua/lalin/host_splice.lua` (420 lines) | Slot filling for all 18+ roles | `fill()` for each role |
| `lua/lalin/host_session.lua` (140 lines) | Session management, `T` context | `T` creation, binding management |
| `lua/lalin/host_module_values.lua` (250 lines) | Module builder | `api.module()`, `ModuleValue` with `:func()`, `:struct()`, `:compile()` |
| `lua/lalin/open_expand.lua` (1030 lines) | Slot expansion (spread resolution) | `expand_*` functions for each grammar position |

### Parser entry point map

The parser currently has exactly **4 public entry points** (exposed via `M.Define(T)`):

| Entry Point | Signature | Returns | Status |
|---|---|---|---|
| `parse_type(src, opts)` | string → parsed result | `LalinType.*` node | Standalone, works |
| `parse_stmts(src, opts)` | string → parsed result | `Stmt[]` array | Standalone, **rejects `@{}`** |
| `parse_island(scan, index, opts)` | scan + index → parsed result | Depends on island kind | Internal, `.mlua` only |
| `parse_module(src, opts)` | string → parsed result | `Tr.Module` | Internal, `.mlua` only |

**Internal sub-grammar methods** (not exposed, called from island parsers):

| Internal Method | Grammar | Returns | Used By |
|---|---|---|---|
| `parse_param_list()` | `name: T, ...` with modifiers | `(Param[], Contract[])` | `parse_func`, `parse_extern` |
| `parse_region_frag()` | Full region island | `O.RegionFrag` | `parse_island("region")` |
| `parse_open_params()` | `name: T, ...` (runtime params) | `(OpenParam[], bindings)` | `parse_region_frag` |
| `parse_cont_params()` | `name: cont(params...), ...` | `(cont_slots{}, slots[])` | `parse_region_frag` |
| `parse_block_params(entry)` | `(name: T = init, ...)` | `EntryBlockParam[]` or `BlockParam[]` | Block/region parsing |
| `parse_expr_frag()` | `name(params) -> T body end` | `O.ExprFrag` | `parse_island("expr")` |
| `parse_struct_island()` | `[Name] fields end` | `{name, decl, protocol_variants}` | `parse_island("struct")` |
| `parse_union_island()` | `[Name] variant \| variant end` | `{name, decl, protocol_variants}` | `parse_island("union")` |
| `parse_extern()` | `name(params) -> T as "sym"? end` | `Tr.ExternFunc` | `parse_island("extern")` |
| `parse_expr()` | Pratt expression parser | `Tr.Expr*` node | Statement parsing |
| `parse_stmt_until(stops)` | Statement list with early-stop | `Stmt[]` | All body parsers |
| `parse_contract()` | `requires bounds(expr, expr)` | `Tr.Contract*` | `parse_func` |
| `parse_emit_stmt()` | `emit name(args; cont_fills)` | `Tr.StmtUseRegionFrag` | Statement parsing |
| `parse_switch_stmt()` | `switch expr do case...default...end` | `Tr.StmtSwitch` | Statement parsing |
| `parse_if_stmt(is_elseif)` | `if cond then...else...end` | `Tr.StmtIf` | Statement parsing |

### Key design tensions in the current state

1. **`function(b)` builders vs. Lalin syntax**: The builders duplicate the grammar in Lua — every Lalin construct has a Lua equivalent. This is high-maintenance and forces users to switch between two representations.

2. **`lalin.stmts[[]]` rejects `@{}`**: The parser creates `Slot*` nodes for `@{}` in any position, but `host_func_values.lua` explicitly throws if any are detected. The parser is ready — the host bridge is the blocker.

3. **Asymmetric param semantics**: `parse_param_list()` (for funcs) returns `Param[]` with string-based name references — param names are NOT added to `value_env`. `parse_open_params()` (for regions) returns `OpenParam[]` AND builds a `param_bindings` map that IS installed into `value_env`. Same syntax (`name: type`) but different ASDL types AND different binding semantics. This means `lalin.params[[]]` and `lalin.open_params[[]]` must be separate entry points even though they parse nearly identical syntax.

4. **`protocol_types` threading**: The region parser looks up union protocols (for protocol exit syntax) via `self.protocol_types[name]`. In `.mlua` files, this map is accumulated across all islands as they're parsed. A standalone `lalin.region[[]]` call has no access to this map unless explicitly provided.

5. **Splice identity spaces**: When each `lalin.XXX[[]]` call lexes independently with `M.lex(src)`, splice IDs start at "splice.1" fresh. This is fine when each quote fills its own slots eagerly and returns clean ASDL, but breaks cross-quote slot reference (which is not needed for the new API).

6. **`name_hint` inference**: The parser infers anonymous island names from Lua assignment context (`local my_fn = func(x) ... end`). Standalone quotes don't have this context — names must be explicit or the parser produces unnamed results.

---

## Chosen Target

### Approach: Hybrid Island (Approach C from proposer)

**Chosen among three proposed alternatives:**

| Approach | Quote Depth | `@{}` Mechanism | Builder Remnant | Parser Change |
|---|---|---|---|---|
| A: Deep Quoting | Everything, including params/fields | Closure capture + explicit table | None | Every sub-grammar extracted (15+ entry points) |
| B: Data-Driven | Only type/stmts/expr | Not supported in standalone | None | Minimal (only `parse_expr` extracted) |
| **C: Hybrid Island** | **Islands only (func/region/struct/union/extern)** | **Explicit values table only** | **None** | **5-6 thin island wrappers, no internal refactoring** |

**Why Approach C was chosen:**
- Islands are large enough that Lalin syntax wins — a full `func` definition is clearer as a string than as a deeply nested table.
- Declaration fragments (params, fields, variants) are small and iterated — Lua `for` loops construct them naturally. Making them table-based avoids string concatenation for generated names.
- The boundary matches the user's mental model: "code is text, data is tables."
- Explicit values table for `@{}` avoids the closure capture fragility confirmed by testing (unreliable under LuaJIT JIT).
- Parser extraction is minimal and mechanical — 5-6 thin wrappers around existing internal methods, not a combinatorial restructuring.

---

### Architecture

#### Form 1 — String quoting `lalin.XXX[[]]`

For **code-shaped things**. Write Lalin syntax in a string, get typed ASDL back. Supported constructs:

| `lalin.XXX[[]]` | Grammar | Returns | Parser Source |
|---|---|---|---|
| `lalin.func[[add(a: i32, b: i32) -> i32 return a + b end]]` | Full function island (without `func` keyword consumed) | `FuncValue` (wraps `Tr.FuncLocal` or `Tr.FuncLocalContract`) | New thin wrapper over `Parser:parse_func()` |
| `lalin.region[[scan(p: ptr(u8); hit: cont(v: i32), miss: cont()) entry ... end end]]` | Full region island (without `region` keyword) | `RegionFragValue` (wraps `O.RegionFrag`) | New thin wrapper over `Parser:parse_region_frag()` |
| `lalin.expr_frag[[inc(x: i32) -> i32 x + 1 end]]` | Full expr fragment island (without `expr` keyword) | `ExprFragValue` (wraps `O.ExprFrag`) | New thin wrapper over `Parser:parse_expr_frag()` |
| `lalin.struct[[Point x: i32; y: i32 end]]` | Full struct island (without `struct` keyword) | `StructValue` (wraps `TypeDeclStruct`) | New thin wrapper over `Parser:parse_struct_island()` |
| `lalin.union[[Option Some(i32) \| None end]]` | Full union island (without `union` keyword) | `StructValue` (wraps `TypeDeclTaggedUnionSugar`) | New thin wrapper over `Parser:parse_union_island()` |
| `lalin.extern[[write(fd: i32, buf: ptr(u8)) -> i32 end]]` | Full extern island (without `extern` keyword) | `FuncValue` (wraps `Tr.ExternFunc`) | New thin wrapper over `Parser:parse_extern()` |
| `lalin.stmts[[let y: i32 = x + 1; return y]]` | Statement list | `Stmt[]` | Already exists as `parse_stmt_string`, enable `@{}` |
| `lalin.expr[[x + 1]]` | Single expression | `ExprValue` (wraps `Tr.Expr*`) | New wrapper over `Parser:parse_expr(0)` with EOF check |
| `lalin.type[[i32]]` | Single type expression | `TypeValue` (wraps `LalinType.*`) | Already exists as `parse_type_string` |

**Parsing model**: Each call lexes the string independently with `M.lex(src)`, creates a fresh `Parser` instance via `new_parser_internal(T, toks, 1, toks.n, opts)`, and delegates to the existing internal `Parser:` method. The island parsers in `parse_island()` stay monolithic — they call the same `Parser:` methods. **Shared code at the leaf level, not combinatorial restructuring.**

#### Form 2 — Table builder `lalin.XXX { }`

For **declaration-shaped things**. Build a Lua table (often in a `for` loop), get typed ASDL back.

| `lalin.XXX { }` | Lua Schema | Returns |
|---|---|---|
| `lalin.params { { name, type, mods? }, ... }` | `{ name: string, type: TypeValue, mods?: { noalias?, readonly?, writeonly? } }[]` | `ParamValue[]` (wraps `Ty.Param[]`) |
| `lalin.fields { { name, type }, ... }` | `{ name: string, type: TypeValue }[]` | `FieldValue[]` (wraps `Ty.FieldDecl[]`) |
| `lalin.variants { { name, payload?, fields? }, ... }` | `{ name: string, payload?: TypeValue, fields?: { name, type }[] }[]` | variant table array (wraps `Ty.VariantDecl[]`) |
| `lalin.conts { [name] = { params? }, ... }` | `{ [string]: { params?: { name, type }[] } }` — named map | `ContSlot[]` (wraps `O.ContSlot[]`) |
| `lalin.blocks { { label, params?, body? }, ... }` | `{ label: string, params?: {...}[], body?: Stmt[] | string }[]` | `Tr.ControlBlock[]` |
| `lalin.entry_params { { name, type, init }, ... }` | `{ name: string, type: TypeValue, init: ExprValue }[]` | `Tr.EntryBlockParam[]` |

**Schema details**:
- `lalin.params { }` — positional array. Each element: `{ name = "a", type = lalin.i32 }`. Optional `mods` field: `{ noalias = true, readonly = true }`.
- `lalin.fields { }` — positional array. Each element: `{ name = "x", type = lalin.i32 }`. Fields use comma or semicolon separation in Lalin; the table is naturally array-ordered.
- `lalin.variants { }` — positional array. Three forms: payload variant `{ name = "Some", payload = lalin.i32 }`, field variant `{ name = "Pair", fields = { { name = "a", type = lalin.i32 }, ... } }`, null variant `{ name = "None" }`.
- `lalin.conts { }` — **named map** (key = continuation name), not a positional array. This is because continuations are named and referenced by their label at emit sites. Each value: `{ params = { { name = "pos", type = lalin.i32 }, ... } }`.
- `lalin.blocks { }` — positional array. Each element: `{ label = "loop", params = { { name = "i", type = lalin.i32, init = lalin.int(0) } }, body = lalin.stmts[[...]] }`. The `body` accepts either `Stmt[]` or a string that gets parsed.
- `lalin.entry_params { }` — positional array. Each element: `{ name = "i", type = lalin.i32, init = lalin.int(0) }`.

**No parser extraction needed for table builders** — they are pure Lua constructors that call existing `host_splice.fill_*` coercion paths to produce ASDL nodes.

#### Bridge — `@{}` with explicit values table

When a quote needs Lua values, pass an explicit table as the **second argument**:

```lua
lalin.stmts("let y: i32 = @{val}; return y", { val = lalin.int(42) })
lalin.func("add(@{params...}) -> i32 @{body end", { params = params, body = body_stmts })
```

**Flow**:
1. Parser runs and creates `Slot*` nodes for each `@{}` in the string. Records them in `splice_slots` array.
2. After parsing completes, the wrapper iterates over `parsed.splice_slots`.
3. For each slot, looks up the corresponding key in the values table. The key is the splice text (e.g., `"val"` for `@{val}`, `"params"` for `@{params...}`).
4. Calls `host_splice.fill(session, slot.slot, value, site, slot.role, slot.spread)` for each slot — the same coercion logic used in the `.mlua` pipeline.
5. Calls `open_expand` to substitute the resulting `SlotBinding[]` into the parsed AST.
6. Returns clean ASDL with all slots resolved.

**No closure capture**. No `debug.getlocal`. The values table is positional and explicit — every `@{}` key must have a corresponding entry, or the call errors.

**Spread slots**: `@{params...}` expects the values table entry to be an array of `ParamValue` or compatible duck-type. The fill handler dispatches to `host_splice.fill_param_list` which calls `open_expand.spread_region_slot`. In the table-builder model, the user constructs the params array via `lalin.params { ... }` and passes it as the values table entry.

**`protocol_types`** for region quotes: passed as `opts.protocol_types` — either the third argument or a key in an opts table:

```lua
lalin.region([[unwrap(val: Option(i32); some: cont(v: i32)) entry ... end]], 
    {},  -- no values
    { protocol_types = { Option = [...] } }
)
```

#### What is removed

**All `function(b)` builder methods** (retired):

| Method | File | Replacement |
|---|---|---|
| `b:let(name, ty, init)` | `host_func_values.lua` | `lalin.stmts[["let @{name}: @{ty} = @{init}"]]` or string concat |
| `b:var(name, ty, init)` | `host_func_values.lua` | `lalin.stmts[["var @{name}: @{ty} = @{init}"]]` or string concat |
| `b:if_(cond, then_fn, else_fn)` | `host_func_values.lua` | `lalin.stmts[["if ... then ... else ... end"]]` |
| `b:switch_(val, arms, default)` | `host_func_values.lua` | `lalin.stmts[["switch ... do ... end"]]` |
| `b:return_(expr)` | `host_func_values.lua` | `lalin.stmts[["return @{expr}"]]` |
| `b:jump(target, args)` | `host_func_values.lua` | `lalin.stmts[["jump @{target}(@{args...})"]]` |
| `b:yield_(expr)` | `host_func_values.lua` | `lalin.stmts[["yield @{expr}"]]` |
| `b:emit(region, cont_fills)` | `host_func_values.lua` | `lalin.stmts[["emit @{region}(@{args}; @{fills...})"]]` |
| `b:block(label, params, body_fn)` | `host_func_values.lua` | `lalin.blocks { { label, params, body } }` |
| `b:expr(expr)` | `host_func_values.lua` | `lalin.stmts[["@{expr}"]]` |
| `b:assign(name, expr)` | `host_func_values.lua` | `lalin.stmts[["@{name} = @{expr}"]]` |
| `RegionBuilder:entry(name, params, body_fn)` | `host_region_values.lua` | Inline in `lalin.region[[]]` |
| `RegionBuilder:block(name, params, body_fn)` | `host_region_values.lua` | Inline in `lalin.region[[]]` |
| `ExprFragBuilder:build()` | `host_fragment_values.lua` | `lalin.expr_frag[[]]` |

**All positional constructors** (retired):

| Constructor | Replacement |
|---|---|
| `lalin.param(name, type)` | `lalin.params { { name, type } }` |
| `lalin.field(name, type)` | `lalin.fields { { name, type } }` |
| `lalin.variant(name, ty)` | `lalin.variants { { name, payload } }` |
| `lalin.cont(params)` | `lalin.conts { ... }` |
| `lalin.cont_decl(name, params)` | `lalin.conts { [name] = { params } }` |
| `lalin.entry_param(name, ty, init)` | `lalin.entry_params { { name, ty, init } }` |
| `lalin.control_block(name, params, body)` | `lalin.blocks { { label, params, body } }` |

**All island/fragment constructors** (retired):

| Constructor | Replacement |
|---|---|
| `lalin.region_frag(name, params, conts, fn)` | `lalin.region[[]]` |
| `lalin.expr_frag(name, params, result, fn)` | `lalin.expr_frag[[]]` |
| `lalin.struct(name, fields)` | `lalin.struct[[]]` |
| `lalin.union(name, variants)` | `lalin.union[[]]` |

#### What stays

| API | Reason |
|---|---|
| `lalin.module("Name")` | Module construction is inherently imperative — collecting items, setting metadata. Can't be a single quote. |
| `lalin.ast.*` (low-level ASDL constructors) | Escape hatch for cases where the quoting API doesn't fit (complex generated trees, direct ASDL manipulation). |
| Lua codegen loops: `for i = 1, N do params[i] = { name = "x"..i, type = lalin.i32 } end` | Iteration is Lua's strength — the table builders consume these arrays naturally. |
| String concatenation for parametric bodies: `lalin.stmts("jump handler_" .. key .. "(result)")` | When the quote structure itself is parametric (variable handler names), string concat is the simplest path. |
| `lalin.stmts(string)` (Form 1 overload — string only, no values) | Still works as `lalin.stmts[[]]` — the no-splice case. |
| `lalin.stmts(table)` (Form 4 — pass-through raw ASDL array) | For users who already have `Stmt[]` nodes from other sources. |

---

### Tradeoffs Acknowledged

1. **Region codegen with dynamic blocks**: A region whose blocks are generated in a Lua `for` loop requires either string concatenation (fragile) or the `@{blocks...}` spread slot. The spread approach works but requires the region quote to reserve a slot and the user to know how to construct `lalin.blocks { }` entries. This is more verbose than the current `RegionBuilder:block()` chaining. **Acceptable because** dynamic block generation is relatively rare, and the explicit table approach is predictable.

2. **`lalin.conts { }` is a named map, not an array**: This is inconsistent with `lalin.params { }` (positional array) and `lalin.fields { }` (positional array). Continuations are named by convention and referenced by name at emit sites, so a named map is the natural shape. **Acceptable because** the naming convention is intrinsic to how continuations work — users think "I have a hit continuation" not "I have the third continuation."

3. **Parser extraction is mechanical but adds 5-6 new entry points**: Thin wrappers add minimal maintenance burden, but they must be tested for edge cases (empty strings, error messages, `@{}` positions). **Acceptable because** each wrapper is 5-10 lines and delegates to existing, well-tested `Parser:` methods.

4. **String concatenation for parametric Lalin is syntactically fragile**: Forgetting a space between concatenated string fragments produces cryptic parse errors. **Acceptable because** this is a known tradeoff in string-based metaprogramming, and the explicit values table with `@{}` covers the most common parametric case (value injection).

5. **Positions in error messages are relative to the quote string, not the calling Lua source**: When `lalin.func[[...]]` produces a parse error, the position is a byte offset within the quote string, not the `.lua` file where the quote appears. **Acceptable because** this matches the behavior of all string-based DSLs (Lua's own `load()`, regular expressions, SQL queries).

### Risks Acknowledged

1. **`debug.getlocal` unreliability confirmed**: Testing validated that `debug.getlocal`-based closure capture is fragile under LuaJIT — frame depth shifts with `for` loops, JIT inlining introduces temporary slots, and the calling scope is not reliably accessible. **This is why the explicit values table is the only supported mechanism.** If a user tries to use closure capture by omitting the values table, the parser detects `@{}` and errors (same conservative guard as today's `lalin.stmts`).

2. **Protocol type resolution for standalone region quotes**: A `lalin.region[[]]` that references a union protocol (e.g., `Option`) must have `protocol_types` passed in `opts`. If the protocol isn't registered, the parser issues a warning and produces empty cont slots (current behavior). Users must thread protocol definitions manually when using standalone region quotes with protocol exits. **Mitigation**: the error message tells the user to pass `protocol_types`.

3. **Spread slot position in region quotes**: The parser's block-loop logic expects `block_kw` or `TK.hole` at specific positions. A `@{blocks...}` spread at the block position must be placed where the parser expects a block to begin — the spread produces an array of blocks that the expander splices in. If placed incorrectly (middle of a block body, after `end`), the parser either fails or produces wrong AST. **Acceptable because** the parser already handles `TK.hole` in block position for `.mlua` files — this is the same mechanism.

4. **`anon_counter` ordering may differ from monolithic parsing**: Standalone quotes each start `anon_counter` at 0. If a user parses multiple anonymous constructs across separate quote calls, the generated IDs (`"_anon_struct_0"`) will be the same as if they were parsed together only if there's one anonymouse construct per call. **Acceptable because** anonymous IDs are internal and not user-visible in the API.

5. **Splice ID namespaces are independent per quote call**: Each `lalin.XXX[[]]` lexes independently, so splice IDs ("splice.1", "splice.2") restart from 1. This means slots from different quotes cannot be cross-referenced. This is fine because each quote resolves its own slots eagerly — slot identity spaces never need to merge. **Acceptable because** the design intentionally fills slots per-call rather than deferring to a module-level expander.

---

### Migration Path

```
Phase 1 — Add table builders (no parser changes):
  - Implement lalin.params {}, lalin.fields {}, lalin.variants {}
  - Implement lalin.conts {}, lalin.blocks {}, lalin.entry_params {}
  - Each produces ASDL via existing host_splice fill coercion paths

Phase 2 — Add lalin.expr[[]] standalone entry point:
  - Extract Parser:parse_expr(0) with EOF checking as M.parse_expr_string(T, src, opts)
  - Wire to lalin.expr metatable

Phase 3 — Add island quoting entry points (5-6 thin wrappers):
  - M.parse_func_string, M.parse_region_string, M.parse_struct_string
  - M.parse_union_string, M.parse_extern_string, M.parse_expr_frag_string
  - Each: lex → new_parser → delegate to existing Parser: method
  - Wire to lalin.func, lalin.region, lalin.struct, lalin.union, lalin.extern, lalin.expr_frag

Phase 4 — Enable @{} in lalin.stmts[[]] (and all new quoting entry points):
  - Remove the conservative guard in host_func_values.lua
  - Add values-table dispatch: if opts.values then fill and expand
  - Error if @{} present but no values table provided (keep the guard for that case)

Phase 5 — Deprecate all function(b) builder methods:
  - Add deprecation warnings to each builder method
  - Update all internal and test code to use new API

Phase 6 — Remove deprecated constructors:
  - Remove lalin.param(name, type), lalin.field(name, type), etc.
  - Remove lalin.region_frag(name, params, conts, fn), etc.
  - Remove lalin.control_block, lalin.cont_decl, lalin.entry_param
  - Remove host_*_values.lua files (or reduce to the table builder wrappers)
```

## Documenter Output — 2026-05-19 09:39:49

Now I have the full picture. Let me produce the comprehensive, self-sustaining architectural decision document reflecting the refined curried-values-table design.

---

# Unified `lalin.XXX` Metaprogramming API — Architectural Decision Record (Revised)

**Date**: 2026-05-19  
**Supersedes**: Previous ADR of same date (pre-curried shape)  
**Phase**: Architecture  
**Workflow**: wf-meta-ergo  

---

## Goal

Replace the current three-path metaprogramming layer — source islands (`.mlua` carrier model), `lalin.stmts[[]]` string snippets that reject `@{}`, and the `function(b)` builder API — with a single unified API whose uniform rule is:

| Form | Meaning |
|---|---|
| `lalin.XXX[[]]` | Pure quote, no `@{}` needed. Returns typed ASDL directly. |
| `lalin.XXX { values }` | Returns a **quote function** that accepts a source string and fills `@{}` from the bound values. |
| `lalin.XXX { values } [[ src ]]` | Curried: bind values, then quote. Same as `lalin.XXX(values)(src)`. |
| `lalin.XXX { array }` | Table builder (array-like entries for params/fields/variants/blocks/conts). Returns typed ASDL array directly. |

Every `lalin.XXX` entry point returns either a **typed ASDL value** (if the input was complete — pure quote or table builder) or a **function accepting a string** (if values were bound via a map). The `function(b)` builder pattern is retired.

---

## Incentives

The existing metaprogramming surface grew three incompatible paths:

1. **Source islands** (`.mlua` carrier model): Full Lalin grammar embedded in Lua source strings, parsed at `.mlua` load time with full splice support via carrier closures. Powerful but requires the `.mlua` runtime pipeline — not usable from plain Lua.

2. **`lalin.stmts[[]]` snippets**: Parse a string as Lalin statements, return `Stmt[]`. Convenient but **rejects `@{}`** — the conservative guard (`if #parsed.splice_slots ~= 0 then error(...) end` in `host_func_values.lua`) makes it impossible to reference Lua values inside a quote. Users must fall back to the builder.

3. **`function(b)` builders**: `lalin.stmts({x=lalin.i32}, function(b) b:let("y", lalin.i32, b.x + 1); b:return_(y) end)`. Full power but verbose, nested, and requires learning a separate Lua API that parallels the Lalin grammar. 14+ builder methods (`b:let`, `b:if_`, `b:switch_`, `b:return_`, `b:jump`, `b:yield_`, `b:emit`, etc.) that duplicate what Lalin syntax already expresses.

Concrete costs identified by prior analysis:

- **Cognitive overhead**: Users must learn two APIs for the same thing — Lalin syntax and the builder API.
- **Codegen verbosity**: A simple `if` requires nested callbacks: `b:if_(cond, function(t) ... end, function(f) ... end)`. The same logic in Lalin syntax is `if cond then ... else ... end`.
- **Maintenance burden**: 14 builder methods in `host_func_values.lua`, 10+ in `host_region_values.lua`, each needing separate documentation, testing, and coercion logic that parallels the parser.
- **Incomplete quoting**: `lalin.stmts[[]]` supports quoting but can't reference Lua values. `lalin.func[[]]` doesn't exist. The quoting surface is ad-hoc, not systematic.
- **`debug.getlocal` unreliability**: Testing confirmed that `debug.getlocal`-based closure capture is fragile under LuaJIT — frame depth shifts with `for` loops, JIT inlining introduces temporary slots, and the calling scope is not reliably accessible. This makes implicit closure capture a non-starter, reinforcing the need for explicit values tables.

---

## Current State

### Three-path architecture

```
Path 1: Source islands (within .mlua files)
  .mlua file → scan_document → island extraction → tokenize
  → parse_island(kind) → splice resolution via carrier closures
  → typecheck → compile
  Only works inside the .mlua loader pipeline.

Path 2: String snippets (from plain Lua)
  lalin.stmts("let x: i32 = 42; return x")
  → parse_stmt_string() → Parsed ASDL (rejects @{})
  lalin.type("i32") → parse_type_string() → TypeValue
  No other lalin.XXX[[]] forms exist.

Path 3: function(b) builder (from plain Lua)
  lalin.stmts({ x = lalin.i32 }, function(b)
      local y = b:let("y", lalin.i32, b.x + 1)
      b:return_(y)
  end)
  → Builder methods construct ASDL nodes programmatically
```

### Key files and their roles

| File | Role | Current entry points |
|---|---|---|
| `lua/lalin/parse.lua` (2384 lines) | Lexer + Pratt parser, all island kinds | `parse_type(src)`, `parse_stmts(src)`, `parse_island(scan,i)`, `parse_module(src)` |
| `lua/lalin/host.lua` (40 lines) | Thin public facade | `lalin.stmts`, `lalin.type`, etc., exported via default session |
| `lua/lalin/host_func_values.lua` (450 lines) | Statement/param/control-block builders | `api.stmts()`, `api.param()`, `api.control_block()`, all `FuncBuilder` methods |
| `lua/lalin/host_struct_values.lua` (250 lines) | Struct/union/field/variant builders | `api.field()`, `api.variant()`, `api.struct()`, `api.union()` |
| `lua/lalin/host_type_values.lua` (130 lines) | Type builders | `api.ptr()`, `api.array()`, `api.view()`, scalar singletons |
| `lua/lalin/host_expr_values.lua` (280 lines) | Expression builders | `api.int()`, `api.bool_lit()`, operator overloads, `api.ref()` |
| `lua/lalin/host_region_values.lua` (430 lines) | Region fragment builders | `api.entry_param()`, `api.cont()`, `api.region_frag()`, `RegionBuilder` |
| `lua/lalin/host_fragment_values.lua` (140 lines) | Expr fragment builders | `api.expr_frag()`, `api.emit_expr()`, `ExprFragBuilder` |
| `lua/lalin/host_splice.lua` (420 lines) | Slot filling for all 18+ roles | `fill()` dispatching by role |
| `lua/lalin/host_session.lua` (140 lines) | Session management, `T` context | `Session:api()`, `Session:symbol_key()`, `Session:id()` |
| `lua/lalin/open_expand.lua` (1030 lines) | Slot expansion (spread resolution) | `expand_*` functions for each grammar position |

### Parser sub-grammar boundaries

The parser has internal methods for each grammar production. Only `parse_type_string` and `parse_stmt_string` are exposed as standalone entry points. The rest are internal to island parsing:

| Internal Method | Grammar | Returns | Currently Exposed? |
|---|---|---|---|
| `parse_param_list()` | `name: T, ...` with modifiers | `(Param[], Contract[])` | No |
| `parse_region_frag()` | Full region island | `O.RegionFrag` | No |
| `parse_open_params()` | `name: T, ...` (runtime params) | `(OpenParam[], bindings)` | No |
| `parse_cont_params()` | `name: cont(params...), ...` | `(cont_slots{}, slots[])` | No |
| `parse_block_params(entry)` | `(name: T = init, ...)` | `EntryBlockParam[]` or `BlockParam[]` | No |
| `parse_expr_frag()` | `name(params) -> T body end` | `O.ExprFrag` | No |
| `parse_struct_island()` | `[Name] fields end` | `{name, decl, protocol_variants}` | No |
| `parse_union_island()` | `[Name] variant \| variant end` | `{name, decl, protocol_variants}` | No |
| `parse_extern()` | `name(params) -> T as "sym"? end` | `Tr.ExternFunc` | No |
| `parse_expr()` | Pratt expression parser (binding power dispatch) | `Tr.Expr*` node | No |
| `parse_stmt_until(stops)` | Statement list with early-stop tokens | `Stmt[]` | No (indirectly via `parse_stmt_string`) |

### Key design tensions in the current state

1. **`function(b)` builders vs. Lalin syntax**: The builders duplicate the grammar in Lua — every Lalin construct has a Lua equivalent. High maintenance, forces users to switch representations.

2. **`lalin.stmts[[]]` rejects `@{}`**: The parser creates `Slot*` nodes for `@{}` in any position, but `host_func_values.lua` explicitly throws if any are detected. The parser is ready — the host bridge is the blocker.

3. **Asymmetric param semantics**: `parse_param_list()` (for funcs) returns `Param[]` with string-based name references — names NOT added to `value_env`. `parse_open_params()` (for regions) returns `OpenParam[]` AND builds a `param_bindings` map installed into `value_env`. Same syntax, different ASDL types, different binding semantics.

4. **`protocol_types` threading**: The region parser looks up union protocols via `self.protocol_types[name]`. In `.mlua` files this is accumulated across islands. A standalone `lalin.region[[]]` needs it explicitly.

5. **No mechanism to pass Lua values into quotes**: The existing `@{}` rejection in `lalin.stmts[[]]` means the only way to embed Lua values is via the builder form or via `.mlua` island carrier closures.

6. **Overload ambiguity in `lalin.stmts`**: Currently four overloads (string-only, function-only, table+function, ASDL array). Adding a string+table fifth overload creates ambiguity with the table+function builder form.

---

## Chosen Target

### Core innovation: curried values table

The central design change from the previous ADR: instead of `lalin.stmts(source_string, values_table)` (two positional args), the values table comes FIRST and returns a quote function:

```lua
-- OLD shape (previous ADR):
lalin.stmts("let y = @{val}; return y", { val = lalin.int(42) })

-- NEW shape (curried):
lalin.stmts { val = lalin.int(42) } [[ let y = @{val}; return y ]]
```

This is not cosmetic — it enables **reusable binders**, eliminates argument-order confusion, and cleanly separates "binding environment" from "source text."

### Uniform dispatch rule

Every `lalin.XXX` entry point dispatches on the shape of its first argument:

| Input shape | Dispatch path | Returns |
|---|---|---|
| **String literal** via `[[]]` | Pure quote path. Parse the string. If `@{}` appears with no values bound, error. | Typed ASDL value directly (e.g., `Stmt[]`, `FuncValue`, `TypeValue`) |
| **Table with string keys** (`next(t)` returns a string key) | Values binding path. Store the map. Return a **quote function** `fn(src)` that parses `src`, fills `@{}` from the stored values, expands, and returns typed ASDL. | Quote function `function(string) → ASDL` |
| **Table with integer keys** (`#t > 0` and first key is an integer) | Table builder path. Each element is a record describing one entry (param, field, variant, etc.). | Typed ASDL array directly (e.g., `Param[]`, `FieldDecl[]`) |
| **Empty table** | Error — ambiguous | Error |
| **ASDL array** (detected by `pvm.classof` on element) | Pass-through. Return as-is. | Typed ASDL array (unchanged) |

**Key insight**: This dispatch rule reuses the existing pattern of `lalin.stmts` overloads (type-based dispatch) but replaces argument-type dispatch with key-type dispatch. This eliminates the ambiguity that plagued the two-positional-args design.

### String quoting forms (`lalin.XXX[[]]`)

For **code-shaped things**. Write Lalin syntax in a string, get typed ASDL back.

| `lalin.XXX[[]]` | Grammar | Returns | Parser Source |
|---|---|---|---|
| `lalin.func[[add(a: i32, b: i32) -> i32 return a + b end]]` | Full function island | `FuncValue` | New wrapper over `Parser:parse_func()` |
| `lalin.region[[scan(p: ptr(u8); hit: cont(v: i32)) entry ... end end]]` | Full region island | `RegionFragValue` | New wrapper over `Parser:parse_region_frag()` |
| `lalin.expr_frag[[inc(x: i32) -> i32 x + 1 end]]` | Full expr fragment island | `ExprFragValue` | New wrapper over `Parser:parse_expr_frag()` |
| `lalin.struct[[Point x: i32; y: i32 end]]` | Full struct island | `StructValue` | New wrapper over `Parser:parse_struct_island()` |
| `lalin.union[[Option Some(i32) \| None end]]` | Full union island | `StructValue` | New wrapper over `Parser:parse_union_island()` |
| `lalin.extern[[write(fd: i32, buf: ptr(u8)) -> i32 end]]` | Full extern island | `FuncValue` (extern) | New wrapper over `Parser:parse_extern()` |
| `lalin.stmts[[let y: i32 = x + 1; return y]]` | Statement list | `Stmt[]` | Already exists (`parse_stmt_string`), enable `@{}` |
| `lalin.expr[[x + 1]]` | Single expression | `ExprValue` | New wrapper over `Parser:parse_expr(0)` with EOF check |
| `lalin.type[[i32]]` | Single type expression | `TypeValue` | Already exists (`parse_type_string`) |

**Parsing model**: Each call lexes the string independently with `M.lex(src)`, creates a fresh `Parser` instance via `new_parser_internal(T, toks, 1, toks.n, opts)`, and delegates to the existing internal `Parser:` method. The island parsers in `parse_island()` stay monolithic — they call the same `Parser:` methods.

### Table builder forms (`lalin.XXX { }`)

For **declaration-shaped things**. Build a Lua table (often in a `for` loop), get typed ASDL back.

| `lalin.XXX { }` | Lua Schema | Returns |
|---|---|---|
| `lalin.params { { name, type, mods? }, ... }` | `{ name: string, type: TypeValue, mods?: { noalias?, readonly?, writeonly? } }[]` | `ParamValue[]` (wraps `Ty.Param[]`) |
| `lalin.fields { { name, type }, ... }` | `{ name: string, type: TypeValue }[]` | `FieldValue[]` (wraps `Ty.FieldDecl[]`) |
| `lalin.variants { { name, payload?, fields? }, ... }` | `{ name: string, payload?: TypeValue, fields?: { name, type }[] }[]` | variant table array (wraps `Ty.VariantDecl[]`) |
| `lalin.conts { [name] = { params? }, ... }` | `{ [string]: { params?: { name, type }[] } }` — named map | `ContSlot[]` (wraps `O.ContSlot[]`) |
| `lalin.blocks { { label, params?, body? }, ... }` | `{ label: string, params?: {...}[], body?: Stmt[] | string }[]` | `Tr.ControlBlock[]` |
| `lalin.entry_params { { name, type, init }, ... }` | `{ name: string, type: TypeValue, init: ExprValue }[]` | `Tr.EntryBlockParam[]` |

**No parser extraction needed for table builders** — they are pure Lua constructors that call existing `host_splice.fill_*` coercion paths to produce ASDL nodes.

### Bridge — `@{}` with explicit values table

When a quote needs Lua values, bind them in a values table BEFORE the quote:

```lua
-- Simple: bind one value
lalin.stmts { val = lalin.int(42) } [[ let y = @{val}; return y ]]

-- Spread params
lalin.func { params = param_list } [[ add(@{params...}) -> i32 @{body} end ]]

-- Multiple values
lalin.stmts { T = lalin.i32, init = lalin.int(0) } [[ let x: @{T} = @{init} ]]
```

**Flow**:
1. `lalin.stmts { val = lalin.int(42) }` — the table has string keys → **values binding path**. Store `{ val = lalin.int(42) }` in closure. Return a quote function.
2. `[[ let y = @{val}; return y ]]` — the returned function is called with the source string.
3. Inside the quote function: call `parse_stmt_string(src)` which creates `Slot*` nodes for `@{}` (no longer rejected — the conservative guard is removed).
4. Iterate `parsed.splice_slots`. For each slot, look up the corresponding key in the stored values table. The key is the splice text (e.g., `"val"` for `@{val}`, `"params"` for `@{params...}`).
5. Call `host_splice.fill(session, slot.slot, value, site, slot.role, slot.spread)` for each slot — reusing the same coercion logic as the `.mlua` pipeline.
6. Call `open_expand` to substitute bindings into the parsed AST.
7. Return clean ASDL with all slots resolved.

**No closure capture. No `debug.getlocal`.** The values table is explicit and positional — every `@{}` key must have a corresponding entry, or the call errors.

### Reusable binders

Because values binding returns a function, you can bind once and quote many times:

```lua
local with_i32 = lalin.stmts { T = lalin.i32 }

local body1 = with_i32 [[ let x: @{T} = 0 ]]
local body2 = with_i32 [[ return as(@{T}, val) ]]

-- Also works for fragments
local with_opt = lalin.region { opt_proto = option_proto }
local r1 = with_opt [[ unwrap(val: @{opt_proto}; some: cont(v: i32), none: cont()) entry ... end ]]
```

This enables a pattern where the values environment is set up once (perhaps from a factory function) and used to generate many related fragments.

### Examples

#### Pure quotes (no values needed)

```lua
local add = lalin.func [[add(a: i32, b: i32) -> i32 return a + b end]]
local stmts = lalin.stmts [[ let y = x + 1; return y ]]
local T = lalin.type [[ptr(i32)]]
local e = lalin.expr [[x + 1]]
local s = lalin.struct [[Point x: i32; y: i32 end]]
local u = lalin.union [[Option Some(i32) | None end]]
```

#### Curried values + quote

```lua
lalin.stmts { val = lalin.int(42) } [[ let y = @{val}; return y ]]

lalin.func { T = lalin.i32, params = param_list } [[
    add(@{params...}) -> @{T} return a + b end
]]

lalin.region { opt_proto = option_proto } [[
    unwrap(val: @{opt_proto}; some: cont(v: i32), none: cont()) entry ... end
]]
```

#### Reusable binder

```lua
local with_i32 = lalin.stmts { T = lalin.i32 }

local body1 = with_i32 [[ let x: @{T} = 0 ]]
local body2 = with_i32 [[ return as(@{T}, val) ]]
```

#### Table builders (data-shaped things)

```lua
-- Construct params for use as @{params...}
local params = lalin.params {
    { name = "x", type = lalin.i32 },
    { name = "y", type = lalin.i32 },
}

-- Or build them with a loop
local params = {}
for i = 1, N do
    params[i] = { name = "x" .. i, type = lalin.i32 }
end

-- Use params array directly in a quote
lalin.func { params = params } [[ f(@{params...}) -> i32 @{body} end ]]

-- Construct fields, variants, conts
local fields = lalin.fields { { name = "a", type = lalin.i32 }, { name = "b", type = lalin.f64 } }
local variants = lalin.variants { { name = "Some", payload = lalin.i32 }, { name = "None" } }
local conts = lalin.conts { hit = { params = { { name = "pos", type = lalin.i32 } } }, miss = { } }
```

#### Mixed: table builder (array) + values binder (map)

```lua
-- Array: table builder path
local params = lalin.params { { name = "a", type = lalin.i32 } }

-- Map: values binder path
local binder = lalin.func { T = lalin.i32 }
```

### What is removed

**All `function(b)` builder methods** (retired):

| Method | File | Replacement |
|---|---|---|
| `b:let(name, ty, init)` | `host_func_values.lua` | `lalin.stmts[["let @{name}: @{ty} = @{init}"]]` or string concat |
| `b:var(name, ty, init)` | `host_func_values.lua` | `lalin.stmts[["var @{name}: @{ty} = @{init}"]]` |
| `b:if_(cond, then_fn, else_fn)` | `host_func_values.lua` | `lalin.stmts[["if ... then ... else ... end"]]` |
| `b:switch_(val, arms, default)` | `host_func_values.lua` | `lalin.stmts[["switch ... do ... end"]]` |
| `b:return_(expr)` | `host_func_values.lua` | `lalin.stmts[["return @{expr}"]]` |
| `b:jump(target, args)` | `host_func_values.lua` | `lalin.stmts[["jump @{target}(@{args...})"]]` |
| `b:yield_(expr)` | `host_func_values.lua` | `lalin.stmts[["yield @{expr}"]]` |
| `b:emit(region, cont_fills)` | `host_func_values.lua` | `lalin.stmts[["emit @{region}(@{args}; @{fills...})"]]` |
| `b:block(label, params, body_fn)` | `host_func_values.lua` | `lalin.blocks { { label, params, body } }` |
| `RegionBuilder:entry(name, params, body_fn)` | `host_region_values.lua` | Inline in `lalin.region[[]]` |
| `RegionBuilder:block(name, params, body_fn)` | `host_region_values.lua` | Inline in `lalin.region[[]]` |
| `ExprFragBuilder:build()` | `host_fragment_values.lua` | `lalin.expr_frag[[]]` |

**All positional constructors** (retired):

| Constructor | Replacement |
|---|---|
| `lalin.param(name, type)` | `lalin.params { { name, type } }` |
| `lalin.field(name, type)` | `lalin.fields { { name, type } }` |
| `lalin.variant(name, ty)` | `lalin.variants { { name, payload } }` |
| `lalin.cont(params)` | `lalin.conts { ... }` |
| `lalin.cont_decl(name, params)` | `lalin.conts { [name] = { params } }` |
| `lalin.entry_param(name, ty, init)` | `lalin.entry_params { { name, ty, init } }` |
| `lalin.control_block(name, params, body)` | `lalin.blocks { { label, params, body } }` |
| `lalin.region_frag(name, params, conts, fn)` | `lalin.region[[]]` |
| `lalin.expr_frag(name, params, result, fn)` | `lalin.expr_frag[[]]` |
| `lalin.struct(name, fields)` | `lalin.struct[[]]` |
| `lalin.union(name, variants)` | `lalin.union[[]]` |

### What stays

| API | Reason |
|---|---|
| `lalin.module("Name")` | Module construction is inherently imperative — collecting items, setting metadata. Can't be a single quote. |
| `lalin.ast.*` (low-level ASDL constructors) | Escape hatch for cases where quoting doesn't fit (complex generated trees, direct ASDL manipulation). |
| Lua codegen loops: `for i = 1, N do params[i] = { name = "x"..i, type = lalin.i32 } end` | Iteration is Lua's strength — table builders consume these arrays naturally. |
| `lalin.stmts(table)` (pass-through raw ASDL array) | For users who already have `Stmt[]` nodes from other sources. |

### What changed from the previous ADR

| Aspect | Previous ADR | Current ADR |
|---|---|---|
| Values table position | Second positional arg: `lalin.stmts("src", {val=42})` | First, curried: `lalin.stmts {val=42} [[ src ]]` |
| Dispatch mechanism | Arg type (string vs table) | Key type (string vs integer keys in table) |
| Return type of `lalin.XXX { map }` | Typed ASDL directly | **Quote function** `fn(string) → ASDL` |
| Reusable binders | Not supported | Supported: `local q = lalin.stmts {T=i32}; q[[...]]; q[[...]]` |
| Overload ambiguity risk | High: `lalin.stmts(src, {val})` vs `lalin.stmts({x=ty}, fn)` | Low: `{val=42}` is unambiguously a map (string keys); `{{name, type}}` is unambiguously an array (integer keys) |

### Why curried values first

1. **Separation of concerns**: The values table says "here are my Lua values." The quote says "here is my Lalin code." They are separate visual blocks, joined by juxtaposition.
2. **Reusability**: Bind values once, quote many times. This enables factory functions that return specialized quote functions.
3. **No overload ambiguity**: `lalin.stmts { val = 42 }` (map keys) is unambiguously a values binder. `lalin.stmts { { name, type } }` (integer keys) is unambiguously a table builder. No collision with the pass-through form (raw ASDL array, also integer keys — detected via `pvm.classof` on elements).
4. **Consistency with Lua patterns**: Lua's `setfenv` / `bind` pattern — bind the environment first, then evaluate the expression.
5. **Better ergonomics for codegen**: Build the params array with a `for` loop, then pass it as one key in the values table: `lalin.func { params = generated_params } [[ f(@{params...}) end ]]`.

---

### Parser extraction plan

The following new standalone entry points must be extracted from `parse.lua`. Each is a thin wrapper (5-10 lines) that calls `M.lex(src)`, creates a fresh `Parser`, and delegates to the existing internal `Parser:` method.

| `M.parse_XXX_string` | Wraps `Parser:` method | New? |
|---|---|---|
| `M.parse_type_string` | `parse_type()` | ✅ Already exists |
| `M.parse_stmt_string` | `parse_stmt_until({})` | ✅ Already exists (remove `@{}` rejection) |
| `M.parse_expr_string` | `parse_expr(0)` + EOF check | New |
| `M.parse_func_string` | `parse_func()` (after consuming `func_kw`) | New |
| `M.parse_region_string` | `parse_region_frag()` (after consuming `region_kw`) | New |
| `M.parse_expr_frag_string` | `parse_expr_frag()` (after consuming `expr_kw`) | New |
| `M.parse_struct_string` | `parse_struct_island()` (after consuming `struct_kw`) | New |
| `M.parse_union_string` | `parse_union_island()` (after consuming `union_kw`) | New |
| `M.parse_extern_string` | `parse_extern()` (after consuming `extern_kw`) | New |

**The island parsers in `parse_island()` stay unchanged** — they call the same `Parser:` methods via `self:parse_func()`, `self:parse_region_frag()`, etc. The new standalone wrappers call the same methods on a fresh parser instance. **Shared code at the leaf level, not combinatorial restructuring.**

---

### Migration path

```
Phase 1 — Add table builders (no parser changes):
  - Implement lalin.params {}, lalin.fields {}, lalin.variants {}
  - Implement lalin.conts {}, lalin.blocks {}, lalin.entry_params {}
  - Each produces ASDL via existing host_splice fill coercion paths
  - Implement key-type dispatch in the host API entry points

Phase 2 — Implement values binding path (curried):
  - Add the "string keys → return quote function" dispatch
  - Store values table in closure, return function(src) → parse + fill + expand
  - Reuse host_splice.fill() + open_expand for slot resolution
  - Test: lalin.stmts { val = lalin.int(42) } [[ let y = @{val}; return y ]]

Phase 3 — Add lalin.expr[[]] standalone entry point:
  - Extract Parser:parse_expr(0) with EOF checking as M.parse_expr_string(T, src, opts)
  - Wire to lalin.expr metatable

Phase 4 — Add island quoting entry points (5-6 thin wrappers):
  - M.parse_func_string, M.parse_region_string, M.parse_struct_string
  - M.parse_union_string, M.parse_extern_string, M.parse_expr_frag_string
  - Wire to lalin.func, lalin.region, etc.

Phase 5 — Enable @{} in lalin.stmts[[]] (all quoting entry points):
  - Remove the conservative guard in host_func_values.lua
  - Error if @{} present but called via pure quote (no values bound)

Phase 6 — Deprecate all function(b) builder methods:
  - Add deprecation warnings to each builder method
  - Update all internal and test code to use new API

Phase 7 — Remove deprecated constructors:
  - Remove lalin.param(name, type), lalin.field(name, type), etc.
  - Remove lalin.region_frag(name, params, conts, fn), etc.
  - Remove host_*_values.lua builder methods
```

---

## Tradeoffs Acknowledged

1. **Curried API is unusual for Lua**: Most Lua APIs take all arguments at once. `lalin.stmts { values } [[ src ]]` is a two-call pattern where the first call returns a function. **Acceptable because** Lua already has this pattern for currying and partial application, and the visual separation improves readability. The double-call syntax `lalin.stmts(values)(src)` is also valid and familiar to functional-Lua users.

2. **Region codegen with dynamic blocks**: A region whose blocks are generated in a Lua `for` loop requires either string concatenation (fragile) or `@{blocks...}` spread slot. The spread approach works but requires the region quote to reserve a slot. **Acceptable because** dynamic block generation is relatively rare, and the explicit values table mechanism is predictable.

3. **`lalin.conts { }` is a named map, not an array**: Inconsistent with `lalin.params { }` and `lalin.fields { }` (positional arrays). Continuations are named by convention and referenced by name at emit sites. **Acceptable because** the naming is intrinsic to how continuations work — users think "I have a `hit` continuation" not "the third continuation."

4. **String concatenation for parametric Lalin is syntactically fragile**: Forgetting a space between concatenated fragments produces cryptic parse errors. **Acceptable because** this is a known tradeoff in string-based metaprogramming, and the explicit values table with `@{}` covers the most common parametric case (value injection).

5. **Positions in error messages are relative to the quote string**: When `lalin.func[[...]]` produces a parse error, the position is a byte offset within the quote string, not the `.lua` file. **Acceptable because** this matches standard DSL quoting behavior (Lua's `load()`, regex, SQL).

6. **Table builder and values binder share the same call syntax (`lalin.XXX { }`)**: The dispatch depends on key types (string vs integer). Users must understand this dispatch rule. **Acceptable because** the two paths produce fundamentally different things (ASDL vs quote function), which makes the distinction self-evident in context.

---

## Risks Acknowledged

1. **Dispatch edge case — mixed key types**: A table with both string and integer keys is theoretically ambiguous. The dispatch rule checks integer keys first (`#t > 0`), so mixed tables go to the table builder path and ignore string keys. **Mitigation**: If a mixed table is passed to the values binding path (string keys detected), but also has integer keys, error with a clear message: "table has both string and integer keys — use separate calls."

2. **Rejected approach: `debug.getlocal`-based closure capture**: Testing confirmed that implicit closure capture via `debug.getlocal` is unreliable under LuaJIT — frame depth shifts with `for` loops, JIT inlining introduces temporary slots, and the calling scope is not reliably accessible. **This is why the explicit values table is the only supported mechanism.** If a user omits the values table and uses `@{}` in a pure quote, the parser detects unresolved slots and errors.

3. **Protocol type resolution for standalone region quotes**: A `lalin.region[[]]` that references a union protocol (e.g., `Option`) must have `protocol_types` passed via the values table. If the protocol isn't registered, the parser issues a warning and produces empty cont slots. **Mitigation**: the error message tells the user to pass `protocol_types` as a values table key.

4. **Spread slot position in region quotes**: The parser's block-loop logic expects `block_kw` or `TK.hole` at specific positions. A `@{blocks...}` spread must be placed where the parser expects a block. **Acceptable because** the parser already handles `TK.hole` in block position for `.mlua` files — this is the same mechanism.

5. **Splice ID namespaces are independent per quote call**: Each `lalin.XXX[[]]` lexes independently, so splice IDs ("splice.1", "splice.2") restart from 1. Slots from different quotes cannot be cross-referenced. **Acceptable because** the design fills slots eagerly per-call — each quote fills its own slots immediately using the bound values table.

6. **`anon_counter` ordering**: Standalone quotes each start `anon_counter` at 0. If a user parses multiple anonymous constructs across separate calls, generated IDs (`"_anon_struct_0"`) may differ from monolithic parsing. **Acceptable because** anonymous IDs are internal and not user-visible.

7. **Quote function is not serializable**: The return value of `lalin.stmts { values }` is a Lua closure — it cannot be serialized or passed across FFI boundaries. **Acceptable because** the quote function is designed for immediate use within a single Lua session.

## Edit-planner Output — 2026-05-19 09:59:51

Now I have all the information needed. Here is the complete implementation plan.

---

# Implementation Plan: Unified `lalin.XXX` Metaprogramming API

## Precondition Checks

1. **`parse.lua` line 2312**: `M.parse_stmt_string` still returns `{ kind, value, splice_slots, issues, protocol_types }`
2. **`parse.lua` line 2267**: `M.parse_island` still dispatches via `p:expect(TK.func_kw); value = p:parse_func()` etc.
3. **`host_func_values.lua` line 329**: `api.stmts(bindings, builder_fn)` is the only implementation — no other module calls it
4. **`host_func_values.lua` line 251**: `make_func` calls `new_builder` → returns `FuncBuilder` — this is used by `pvm_surface_cache_values.lua:71`
5. **`host_region_values.lua` line 302**: `api.region_frag(name, params, conts, fn)` still uses `RegionBuilder`/`BlockBuilder` — this is used by `region_compose.lua` and `pvm_surface_region_values.lua`
6. **`host_fragment_values.lua` line 47**: `api.expr_frag(name, params, result, body_fn)` — check if any internal module calls this (not tests)
7. **`open_expand.lua` line 992**: `env_with_fills(env, bindings)` and `stmts(stmts, env)` are available via `Define(T)` return

---

## File-by-File Changes

### Phase 1: `lua/lalin/parse.lua` — Add 7 standalone parse entry points

**Goal**: Add `M.parse_expr_string`, `M.parse_func_string`, `M.parse_region_string`, `M.parse_struct_string`, `M.parse_union_string`, `M.parse_extern_string`, `M.parse_expr_frag_string`. Update `M.Define(T)` to expose them.

**Edit 1**: Insert after line 2319 (`end` of `M.parse_stmt_string`), before line 2321 (`function M.parse_module_document`):

Add 7 new functions, each following the same pattern as `M.parse_type_string`:
- Lex with `M.lex(src)`
- Create parser with `new_parser_internal(T, toks, 1, toks.n, opts)`
- `p:skip_sep()`
- `p:expect(TK.<keyword>)` for island forms
- Call the appropriate `p:parse_<method>()`
- `p:skip_sep()`
- Check `p:kind() ~= TK.eof`
- Return `{ kind, value, splice_slots=p.splice_slots, issues=p.issues, protocol_types=p.protocol_types }`

The expected keyword for each:
| Function | `expect` keyword | Parser method |
|---|---|---|
| `M.parse_expr_string` | (none) | `p:parse_expr(0)` |
| `M.parse_func_string` | `TK.func_kw` | `p:parse_func()` |
| `M.parse_region_string` | `TK.region_kw` | `p:parse_region_frag()` |
| `M.parse_struct_string` | `TK.struct_kw` | `p:parse_struct_island()` |
| `M.parse_union_string` | `TK.union_kw` | `p:parse_union_island()` |
| `M.parse_extern_string` | `TK.extern_kw` | `p:parse_extern()` |
| `M.parse_expr_frag_string` | `TK.expr_kw` | `p:parse_expr_frag()`

Each `kind` field should be: `"expr"`, `"func"`, `"region"`, `"struct"`, `"union"`, `"extern"`, `"expr_frag"`.

**Edit 2**: Update `M.Define(T)` (lines 2361-2380). Replace the return table to add all new parse functions:

```lua
parse_expr = function(src, opts) return M.parse_expr_string(T, src, opts) end,
parse_func = function(src, opts) return M.parse_func_string(T, src, opts) end,
parse_region = function(src, opts) return M.parse_region_string(T, src, opts) end,
parse_struct = function(src, opts) return M.parse_struct_string(T, src, opts) end,
parse_union = function(src, opts) return M.parse_union_string(T, src, opts) end,
parse_extern = function(src, opts) return M.parse_extern_string(T, src, opts) end,
parse_expr_frag = function(src, opts) return M.parse_expr_frag_string(T, src, opts) end,
```

**Pattern**: Each wrapper is 10-15 lines, identical structure. Copy-paste pattern with keyword + method substitution.

**Danger zone**: The island entry points (`parse_func_string`, etc.) must call `p:expect(TK.XXX_kw)` BEFORE calling the parser method — exactly as `M.parse_island` does at lines 2275-2293. Do NOT add the keyword consumption inside the parser method itself.

---

### Phase 2: `lua/lalin/host_func_values.lua` — Add `api.params{}` table builder + values binder

**Goal**: 
- ADD `api.params{}` table builder (integer-key array → returns `ParamValue[]`)
- ADD `api._stmts_quote(src)` — pure statement quote (rejects `@{}`)
- ADD `api._stmts_values_binder(values)` — values binder factory (returns `function(src)`)
- REMOVE `parse_stmt_snippet` (lines 316-321)
- REMOVE `api.stmts(bindings, builder_fn)` (lines 323-348)
- REMOVE `api.control_block(name, params, body)` (lines 379-393)
- REMOVE `api.cont_decl(name, params)` (lines 395-399)
- KEEP: `FuncBuilder` metatable (line 11-13), all FuncBuilder methods (used by `make_func` which is used by `pvm_surface_cache_values`)
- KEEP: `api.param(name, ty)` (line 83-91) — used by 5+ internal modules
- KEEP: `api._module_func`, `api._module_export_func`, `api._module_extern_func`, `make_func`, `new_builder`

**Edit 1**: Insert `api.params{}` after `api.param(name, ty)` (after line 91). Function:

```lua
function api.params(specs)
    assert(type(specs) == "table", "params expects an array of param specs")
    local out = {}
    for i = 1, #specs do
        local spec = specs[i]
        assert(type(spec) == "table", "params element " .. i .. " must be a table")
        assert_name(spec.name, "params element")
        local tv = api.as_type_value(spec.type, "params element expects a type value")
        local mods = spec.mods or {}
        local p = setmetatable({
            kind = "param",
            session = session,
            name = spec.name,
            type = tv,
            decl = Ty.Param(spec.name, tv.ty),
        }, ParamValue)
        out[i] = p
    end
    return out
end
```

**Edit 2**: Replace `parse_stmt_snippet` (lines 316-321) with two new functions:

```lua
function api._stmts_quote(src)
    local parsed = require("lalin.parse").Define(T).parse_stmts(src)
    if #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
    if #parsed.splice_slots ~= 0 then
        error("lalin.stmts[[]] does not evaluate @{}; use lalin.stmts{values}[[src]] instead", 3)
    end
    return parsed.value
end

function api._stmts_values_binder(values)
    assert(type(values) == "table", "_stmts_values_binder expects a table")
    local pvm = require("lalin.pvm")
    local hp = require("lalin.host_splice")
    return function(src)
        local T_local = session.T
        local parsed = require("lalin.parse").Define(T_local).parse_stmts(src)
        if #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
        if #parsed.splice_slots == 0 then return parsed.value end
        local bindings = {}
        for _, ss in ipairs(parsed.splice_slots) do
            local splice_key = ss.splice_id
            local v = values[splice_key]
            if v == nil then
                error("lalin.stmts{...}[[src]]: no value bound for @" .. tostring(splice_key), 3)
            end
            local binding = M.fill(session, ss.slot, v, "splice " .. splice_key, ss.role, ss.spread)
            bindings[#bindings + 1] = binding
        end
        local expand = require("lalin.open_expand").Define(T_local)
        local env = expand.empty_env()
        env = expand.env_with_fills(env, bindings)
        return expand.stmts(parsed.value, env)
    end
end
```

**Danger zone for `M.fill`**: The `host_splice` module's `M.fill` function is at line 50. Inside the Install closure, `M` is not defined. The worker must `require("lalin.host_splice")` at the top of the function or at module level. Since `session.T` is needed, and `T` is already bound in the Install closure, use `require("lalin.host_splice")` with the dispatching role approach:

```lua
local fill = require("lalin.host_splice")
-- ...
local binding = fill.fill(session, ss.slot, v, "splice " .. splice_key, ss.role, ss.spread)
```

**Edit 3**: Remove `api.control_block` (lines 379-393) and `api.cont_decl` (lines 395-399). Delete these function definitions entirely. The helper functions `block_param_decl` and `block_binding_map` (lines ~370-377) can also be removed if they have no other callers. Check: `block_param_decl` is only called from `api.control_block`. `block_binding_map` is only called from `api.control_block`. Both can be removed.

**Edit 4**: Remove `api.stmts(bindings, builder_fn)` (lines 323-348). Delete the entire function.

**Edit 5**: At the bottom, update the exports. Keep `api.ParamValue = ParamValue`, `api.FuncValue = FuncValue`, `api.FuncBuilder = FuncBuilder`. These are needed by internal modules.

---

### Phase 3: `lua/lalin/host_struct_values.lua` — Add table builders

**Goal**: ADD `api.fields{}` and `api.variants{}` table builders. REMOVE `api.struct(name, fields)` and `api.union(name, fields)` (user-facing). KEEP `api.field(name, ty)`, `api.variant(name, ty)`, `api._module_struct`, `api._module_union` (internal).

**Edit 1**: Add `api.fields{}` after `api.field(name, ty)` (after line ~163):

```lua
function api.fields(specs)
    assert(type(specs) == "table", "fields expects an array of field specs")
    local out = {}
    for i = 1, #specs do
        local spec = specs[i]
        assert(type(spec) == "table", "fields element " .. i .. " must be a table")
        assert_name(spec.name, "fields element")
        local tv = api.as_type_value(spec.type, "fields element expects a type value")
        out[i] = setmetatable({
            kind = "field",
            session = session,
            name = spec.name,
            type = tv,
            decl = Ty.FieldDecl(spec.name, tv.ty),
        }, FieldValue)
    end
    return out
end
```

**Edit 2**: Add `api.variants{}` after `api.variant(name, ty)` (after line ~169):

```lua
function api.variants(specs)
    assert(type(specs) == "table", "variants expects an array of variant specs")
    local out = {}
    for i = 1, #specs do
        local spec = specs[i]
        assert(type(spec) == "table", "variants element " .. i .. " must be a table")
        assert_name(spec.name, "variants element")
        if spec.fields then
            local fields = {}
            for j = 1, #spec.fields do
                local f = spec.fields[j]
                assert_name(f.name, "variant field name")
                local ftv = api.as_type_value(f.type, "variant field type")
                fields[j] = Ty.FieldDecl(f.name, ftv.ty)
            end
            out[i] = { kind = "variant", name = spec.name, payload = nil, fields = fields,
                       decl = Ty.VariantDecl(spec.name, api.void.ty, fields) }
        else
            local tv = api.as_type_value(spec.payload or api.void, "variant payload expects a type value")
            out[i] = { kind = "variant", name = spec.name, type = tv, payload = tv,
                       decl = Ty.VariantDecl(spec.name, tv.ty, {}) }
        end
    end
    return out
end
```

**Edit 3**: Remove `api.struct(name, fields)` (lines ~171-173) and `api.union(name, fields)` (lines ~175-177). Delete these two function definitions. They wrap `make_struct`/`make_union` with `nil` owner_module — no internal callers use them (only test files).

**Keep**: `api._module_struct`, `api._module_union`, `api._module_enum`, `api._module_tagged_union`, `api._module_newstruct` — all used by `host_module_values.lua`.

---

### Phase 4: `lua/lalin/host_region_values.lua` — Add table builders

**Goal**: ADD `api.conts{}`, `api.blocks{}`, `api.entry_params{}` table builders. REMOVE `api.entry_param(name, ty, init)` (user-facing). KEEP `api.cont(params)` and `api.region_frag(name, params, conts, fn)` (internal).

**Edit 1**: Add `api.conts{}` after `api.cont(params)` (after line ~118):

```lua
function api.conts(specs)
    assert(type(specs) == "table", "conts expects a named map")
    local out = {}
    for name, spec in ordered_pairs_from_map(specs) do
        assert_name(name, "conts key")
        local block_params = {}
        for j = 1, #(spec.params or {}) do
            local p = spec.params[j]
            assert(type(p) == "table", "cont param element must be a table")
            assert_name(p.name, "cont param name")
            local tv = api.as_type_value(p.type, "cont param type")
            block_params[j] = Tr.BlockParam(p.name, tv.ty)
        end
        out[name] = setmetatable({ kind = "cont", params = spec.params or {}, block_params = block_params }, ContValue)
    end
    return out
end
```

**Edit 2**: Add `api.blocks{}`:

```lua
function api.blocks(specs)
    assert(type(specs) == "table", "blocks expects an array of block specs")
    local out = {}
    for i = 1, #specs do
        local spec = specs[i]
        assert(type(spec) == "table", "blocks element " .. i .. " must be a table")
        assert_name(spec.label, "blocks element label")
        local decls = {}
        for j = 1, #(spec.params or {}) do
            local p = spec.params[j]
            assert(type(p) == "table", "block param " .. j .. " must be a table")
            assert_name(p.name, "block param name")
            local tv = api.as_type_value(p.type, "block param type")
            decls[j] = Tr.BlockParam(p.name, tv.ty)
        end
        local body_stmts = spec.body or {}
        if type(body_stmts) == "string" then
            local T_local = session.T
            local parsed = require("lalin.parse").Define(T_local).parse_stmts(body_stmts)
            if #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
            body_stmts = parsed.value
        elseif type(body_stmts) == "function" then
            error("lalin.blocks{...} does not support builder functions; use lalin.stmts[[...]] or pass raw ASDL", 3)
        end
        out[i] = Tr.ControlBlock(Tr.BlockLabel(spec.label), decls, body_stmts)
    end
    return out
end
```

**Edit 3**: Add `api.entry_params{}`:

```lua
function api.entry_params(specs)
    assert(type(specs) == "table", "entry_params expects an array of entry param specs")
    local out = {}
    for i = 1, #specs do
        local spec = specs[i]
        assert(type(spec) == "table", "entry_params element " .. i .. " must be a table")
        assert_name(spec.name, "entry_params element")
        local tv = api.as_type_value(spec.type, "entry_params element expects a type value")
        local init_expr = spec.init and api.as_expr_value(spec.init, "entry_params init expects expression value") or nil
        out[i] = Tr.EntryBlockParam(spec.name, tv.ty, init_expr and init_expr.expr or nil)
    end
    return out
end
```

**Edit 4**: Remove `api.entry_param(name, ty, init)` (lines ~105-109). Delete. No internal callers.

**Keep**: `api.cont(params)` (line ~112) — used by `pvm_surface_region_values.lua:166` and `region_compose.lua:103`.
**Keep**: `api.region_frag(name, params, conts, fn)` (line ~302) — used by `region_compose.lua` and `pvm_surface_region_values.lua`.

---

### Phase 5: `lua/lalin/host_expr_values.lua` — Remove `api.call()`

**Goal**: Remove `api.call(name, args, result_ty)`. Keep everything else (operator overloads, other constructors).

**Edit 1**: Remove `api.call` definition (around line ~185-193). Delete the function. No internal callers.

**Keep**: `ExprValue` metatable, operator overloads (`__add`, `__sub`, `:eq`, `:band`, etc.), `api.select`, `api.int`, `api.float`, `api.bool_lit`, `api.string_lit`, `api.nil_lit`, `api.ref`, `api.expr_ref`, `api.expr_from_asdl`, `api.load`, `api.addr_of`, `api.atomic_load`, `api.atomic_store`, `api.atomic_fence`, etc.

**Note**: `api.call` is only used by test files `test_host_extern_symbol.lua` and `test_direct_mutual_recursion.lua`. These tests will be updated to use `lalin.expr[[]]` or `lalin.stmts[[]]` instead.

---

### Phase 6: `lua/lalin/host_fragment_values.lua` — Remove builder, keep metadata

**Goal**: Remove `ExprFragBuilder` class, `api.expr_frag(...)` constructor, `api.emit_expr(...)` function. Keep `ExprFragValue` metatable and `lalin_splice` protocol. Keep `api.expr_frag_template(...)` (check if it has callers first).

**Edit 1**: Check if `api.expr_frag_template` has callers. Grep `lua/lalin/` for `expr_frag_template`. If zero, remove it too. If used, keep it.

**Edit 2**: Remove from `M.Install`:
- `ExprFragBuilder` metatable removal
- `ExprFragBuilder:param(name)` removal
- `api.expr_frag(name, params, result_ty, body_fn)` removal
- `api.emit_expr(fragment, args)` removal
- Install no longer exports `api.ExprFragBuilder`

**Edit 3**: Keep (or move to host_values.lua):
- `ExprFragValue` metatable
- `ExprFragValue:lalin_splice_source()`
- `ExprFragValue:lalin_splice(role, session, site)`
- `ExprFragValue:__tostring()`

These are already duplicated in `host_values.lua` lines 11-12, 78-81! The `host_fragment_values.lua` version is redundant. However, `host_fragment_values.lua`'s `lalin_splice` method at line 15-18 is NOT in `host_values.lua`. The worker should ADD `lalin_splice` to `host_values.lua`'s `ExprFragValue` if it's missing.

**Edit 4**: Remove `host_fragment_values.lua` from the Install list in `host_session.lua:Session:api()`. The `ExprFragValue` definition in `host_values.lua` already covers the class.

---

### Phase 7: `lua/lalin/host_values.lua` — Absorb `ExprFragValue` fully

**Goal**: Ensure `ExprFragValue` metatable + all methods are defined here since `host_fragment_values.lua` is being removed from Install.

**Edit 1**: Add `lalin_splice` method to `host_values.lua`'s `ExprFragValue` if missing. Currently `host_values.lua` has (lines 78-81):
```lua
function ExprFragValue:lalin_splice_source() return self.name end
function ExprFragValue:__tostring() return "LalinExprFragValue(" .. tostring(self.name) .. ")" end
```

Add missing method:
```lua
function ExprFragValue:lalin_splice(role, session, site)
    if role == "expr_frag" then return self.frag end
    error((site or "splice") .. ": expression fragment value cannot splice as " .. role, 2)
end
```

**No other edits needed** — `api.CanonicalExprFragValue = ExprFragValue` is already at line 132.

---

### Phase 8: `lua/lalin/host_session.lua` — Update Install list

**Goal**: Remove `host_fragment_values.lua` from the Install list.

**Edit 1**: In `Session:api()` (lines 43-58), remove the line:
```lua
require("lalin.host_fragment_values").Install(api, self)
```

---

### Phase 9: `lua/lalin/host.lua` — Rewrite for unified API

**Goal**: Replace the entire file with the new dispatch-based API.

**Full file structure**:

```lua
local Session = require("lalin.host_session")
local default_session = Session.new({ prefix = "default" })
local api = default_session:api()
local M = api
M.default_session = default_session
M.region_compose = require("lalin.region_compose")

-- Re-export session utilities
M.new_session = function(opts) return Session.new(opts) end
M.session = function(opts) return Session.new(opts) end
M.classify_type = function(ty, ...) return default_session:classify_type(ty, ...) end
M.size_align = function(ty, env) return default_session:size_align(ty, env) end
M.abi_of = function(ty, env) return default_session:abi_of(ty, env) end
M.layout_of = function(ty) return default_session:layout_of(ty) end

-- ============================================================
-- Helper: create a quoting metatable
-- ============================================================
local function make_quote(parse_fn, wrap_fn)
    return setmetatable({}, {
        __call = function(_, src)
            -- Pure quote via [[]] — first arg is the source string
            local T = default_session.T
            local parsed = parse_fn(T, src)
            if #parsed.issues ~= 0 then
                error(parsed.issues[1].message, 2)
            end
            if #parsed.splice_slots ~= 0 then
                error("lalin.XXX[[]] does not evaluate @{}; use lalin.XXX{values}[[src]] instead", 2)
            end
            return wrap_fn(parsed.value, parsed)
        end,
        __index = function(t, key)
            return function(_, spec)
                if type(spec) ~= "table" then
                    error("lalin.XXX expects a table or [[]] string", 2)
                end
                return spec  -- pass-through: return as-is
            end
        end,
    })
end
```

Then for each quote type:

```lua
-- lalin.type[[]] → TypeValue
M.type = make_quote(
    function(T, src) return require("lalin.parse").Define(T).parse_type(src) end,
    function(value) return api.type_from_asdl(value, "lalin.type quote") end
)

-- lalin.expr[[]] → ExprValue  
M.expr = make_quote(
    function(T, src) return require("lalin.parse").Define(T).parse_expr(src) end,
    function(value) return api.expr_from_asdl(value, nil, "lalin.expr quote") end
)

-- lalin.stmts[[]] → Stmt[]  (raw ASDL array)
M.stmts = setmetatable({}, {
    __call = function(_, src)
        local T = default_session.T
        local parsed = require("lalin.parse").Define(T).parse_stmts(src)
        if #parsed.issues ~= 0 then error(parsed.issues[1].message, 2) end
        if #parsed.splice_slots ~= 0 then
            error("lalin.stmts[[]] does not evaluate @{}; use lalin.stmts{values}[[src]] instead", 2)
        end
        return parsed.value
    end,
    __index = function(_, key)
        return function(_, spec)
            if type(spec) ~= "table" then
                error("lalin.stmts expects a table or [[]] string", 2)
            end
            -- ASDL pass-through: if elements have class
            local pvm = require("lalin.pvm")
            if #spec > 0 and pvm.classof(spec[1]) ~= false then
                return spec
            end
            -- Values binder: string keys
            local has_str_keys = false
            for k in pairs(spec) do
                if type(k) == "string" then has_str_keys = true; break end
            end
            if has_str_keys then
                return api._stmts_values_binder(spec)
            end
            error("lalin.stmts{...}: table is neither ASDL array nor values map", 2)
        end
    end,
})
```

For island quotes (`lalin.func`, `lalin.region`, `lalin.struct`, `lalin.union`, `lalin.extern`, `lalin.expr_frag`), each needs a `wrap_fn` that converts raw ASDL to a hosted value:

```lua
-- lalin.func[[]] → FuncValue
M.func = make_quote(
    function(T, src) return require("lalin.parse").Define(T).parse_func(src) end,
    function(value)
        local T = default_session.T
        local Tr = T.LalinTree
        local pvm = require("lalin.pvm")
        local cls = pvm.classof(value)
        if cls == Tr.FuncLocal then
            -- Wrap raw Ty.Param[] params into something FuncValue-like
            return setmetatable({
                kind = "func",
                session = default_session,
                name = value.name,
                params = {},
                result = api.type_from_asdl(value.result, value.name),
                func = value,
                item = Tr.ItemFunc(value),
            }, api.FuncValue or {})
        end
        error("lalin.func[[]] expected a function", 2)
    end
)
```

The exact wrapping logic varies per type. The key insight: for `lalin.func[[]]` and `lalin.struct[[]]` etc. the ASDL node produced by the parser IS the value — the hosted value wrapper just adds a metatable and metadata. The worker should check how `make_func` (in host_func_values) builds the `FuncValue` table and replicate the fields:

- `FuncValue` fields: `kind="func"`, `session`, `name`, `params` (ParamValue[]), `result` (TypeValue), `func` (raw ASDL Tr.FuncLocal), `item`, `type`
- `StructValue` fields (from `make_struct`): `kind="struct"`, `session`, `name`, `fields` (FieldValue[]), `fields_by_name`, `decl`, `item`, `type`

For the quoted path, `params` and `fields` will be raw ASDL arrays, not wrapped ParamValue[]/FieldValue[]. This is fine for the hosted wrapper — the fields are just metadata.

**Important**: The `__index` metatable for `make_quote` handles `lalin.func { table }` correctly by just returning the table (pass-through). The table builder path (`lalin.func { ... }` with integer keys) currently isn't defined for func/region/struct/union — only `lalin.params { }`, `lalin.fields { }`, etc. For now, the pass-through is correct.

---

### Phase 10: Tests — Update all test files

**Goal**: Replace all usages of removed user-facing APIs with new equivalents.

**Files to update**:

1. **`tests/test_host_struct_values.lua`** (line 13): Replace:
   ```lua
   -- OLD:
   local Pair = lalin.struct("Pair", { lalin.field("x", lalin.i32), lalin.field("y", lalin.i32) })
   -- NEW:
   local Pair = lalin.struct [[Pair x: i32; y: i32 end]]
   ```

2. **`tests/test_host_reflection.lua`** (line 32): Same replacement.

3. **`tests/test_host_extern_symbol.lua`** (line 7-9): Replace `lalin.param(...)` and `lalin.call(...)`:
   ```lua
   -- OLD:
   local params = { lalin.param("x", lalin.i32) }
   f:return_(lalin.call("host_add7", { f:param("x") }, lalin.i32))
   -- NEW:
   -- This test uses the internal module:func() API which still works.
   -- But lalin.call() is removed. Replace with lalin.expr[[]]:
   f:return_(lalin.expr[[host_add7(x)]])
   -- Or use api.call if the test needs the builder path:
   -- But hard cut means we update the test.
   ```

4. **`tests/test_direct_mutual_recursion.lua`** (lines 7-26): Replace `lalin.param(...)` and `lalin.call(...)`:
   ```lua
   -- Replace lalin.param("n", lalin.i32) with { name = "n", type = lalin.i32 }
   -- in the params array passed to module:func(name, params, result, fn)
   ```

5. **`tests/test_spread_splice_regions.lua`** (lines 6-44): Replace `lalin.param(...)`, `lalin.cont_decl(...)`, `lalin.entry_param(...)`, `lalin.control_block(...)` with table builder equivalents or direct ASDL construction.

6. **`tests/test_host_stmt_list_builder.lua`**: Replace `lalin.stmts(fn)` with `lalin.stmts[[]]` or the values binder pattern.

7. **`benchmarks/bench_frontend_speed.lua`**: Replace all `lalin.param(...)`, `b:let(...)`, `b:if_(...)`, `b:return_(...)`, `b:jump(...)`, `b:block(...)`, `lalin.control_block(...)`.

8. **`tests/test_host_metaprogramming_patterns.lua`**: Check for any old API usage and update.

**Pattern for replacement**:
- `lalin.param("x", lalin.i32)` → `{ name = "x", type = lalin.i32 }` (when used in `module:func(params, ...)`)
- `lalin.call("fn", { args }, ret_ty)` → `lalin.expr[[fn(args...)]]` 
- `b:let("x", ty, init)` → inline in `lalin.stmts[[]]` or use `lalin.stmts{ ... }[[ let @{name}: @{ty} = @{init} ]]
- `lalin.control_block(name, params, body_fn)` → `lalin.blocks { { label, params, body = lalin.stmts[[...]] } }`
- `b:return_(expr)` → `lalin.stmts[["return @{expr}"]]` with values binder

**For tests using `module:func(name, params, result, fn)` internally**: This API still works! The `params` argument accepts raw tables `{ name, type }` via `as_param` which checks `api.ParamValue` metatable. But `api.param` returns ParamValue, and the raw table `{ name, type }` won't have that metatable. The worker must ensure that `module:func(params, ...)` with raw table entries works by updating `as_param` in `host_func_values.lua` to accept duck-typed tables, OR update the callers to use `api.param(name, ty)` for internal paths.

Actually — looking at `make_func` (line ~240), `as_param` checks `getmetatable(v) == ParamValue`. Raw `{ name, type }` tables don't match. So for internal callers like `pvm_surface_cache_values.lua` which use `api.param("ctx", ctx_ty)`, this still works because they use `api.param()` directly. For test files that were previously using `lalin.param("x", lalin.i32)`, they need to either:
- Use `api.param("x", lalin.i32)` (if they have access to the internal api)
- Use `lalin.params { { name = "x", type = lalin.i32 } }[1]` (index into result)
- Pass the raw table directly if `make_func`'s `as_param` is updated to accept duck-typed tables

The simplest approach: update `as_param` in `host_func_values.lua` to accept `{ name, type }` duck-typed tables in addition to `ParamValue` metatable objects. This way, both `api.param("x", lalin.i32)` AND `{ name = "x", type = lalin.i32 }` work when passed to `module:func(params, ...)`.

---

### Phase 11: `LANGUAGE_REFERENCE.md` — Update metaprogramming documentation

**Goal**: Rewrite Sections 15 and 16 to document the new API.

**Sections to rewrite**:
- Section 15 (line 2040): Replace all builder API documentation with new quoting API + table builders
- Section 15.4: Replace `lalin.param("x", lalin.i32)` with `lalin.params { { name, type } }`
- Section 15.5: Replace `lalin.stmts({...}, fn)` with `lalin.stmts[[]]` and `lalin.stmts{values}[[src]]`
- Section 15.6: Replace `lalin.region_frag` with `lalin.region[[]]`
- Section 15.7: Replace `lalin.expr_frag` with `lalin.expr_frag[[]]`
- Section 15.8: Replace `lalin.struct(name, fields)` with `lalin.struct[[]]`
- Section 15.3: Replace `lalin.call(callee, args)` with `lalin.expr[[callee(args)]]`
- Section 16: Update metaprogramming examples to use new quoting API
- Remove all references to FunсBuilder, RegionBuilder, BlockBuilder, ExprFragBuilder

**Also update**: `README.md` line 359 which references `lalin.param(...)`.

---

## Pattern Memo

1. **All new table builder functions** use signature `api.XXXs(specs)` where `specs` is an array of record tables. They return arrays of hosted values.

2. **Values binder pattern**: `lalin.stmts { values }` → `api._stmts_values_binder(values)` returns a function. The function lexes+parses, fills slots via `host_splice.fill`, expands via `open_expand.Define(T).stmts()`, returns clean ASDL.

3. **Quote entry point pattern**: Each `make_quote(parseFn, wrapFn)` creates a metatable with `__call` for `[[]]` and `__index` that returns the table as-is (pass-through).

4. **Internal API preservation**: `api.param(name, ty)`, `api.field(name, ty)`, `api.variant(name, ty)`, `api.cont(params)`, `api.region_frag(name, params, conts, fn)` — all kept for internal modules. Only user-facing aliases (`lalin.param`, `lalin.struct(name, fields)`, `lalin.region_frag`, etc.) are removed from `host.lua`'s export.

5. **`FuncBuilder` preservation**: `FuncBuilder` metatable and all methods (b:let, b:if_, etc.) stay in the source file because they're used by `make_func` → `module:func`/`:export_func` → internal callers (`pvm_surface_cache_values.lua`). The user-facing path `lalin.stmts(bindings, fn)` is removed, but the internal `api._module_func`/`:export_func` path continues to work.

---

## Testing Strategy

Test incrementally after each phase:

1. **After Phase 1** (parse.lua entry points): Run `luajit tests/test_parse_kernels.lua` and `luajit tests/test_parse_type_items.lua` to verify parser still works.

2. **After Phase 2-4** (table builders): Run `luajit tests/test_host_func_values.lua`, `luajit tests/test_host_struct_values.lua`, `luajit tests/test_host_region_values.lua`.

3. **After Phase 9** (host.lua rewrite): Test the new API end-to-end:
   ```lua
   local lalin = require("lalin")
   local stmts = lalin.stmts [[ let x: i32 = 42; return x ]]
   local ty = lalin.type [[ptr(i32)]]
   local f = lalin.func [[add(a: i32, b: i32) -> i32 return a + b end]]
   local s = lalin.struct [[Point x: i32; y: i32 end]]
   ```

4. **After Phase 10** (tests): Run ALL test files that were updated:
   ```sh
   for f in tests/test_host_*.lua; do luajit $f; done
   for f in tests/test_parse_*.lua; do luajit $f; done
   ```

5. **Full regression**: Run all tests:
   ```sh
   for f in tests/test_*.lua; do luajit $f 2>&1 | grep -E '(OK|FAIL|error)'; done
   ```

6. **Build check**: `make` to verify the embedded compiler still builds.

---

## Files Not Modified

These files are NOT touched by this plan:
- `lua/lalin/host_type_values.lua` — scalar singletons stay
- `lua/lalin/host_place_values.lua` — place values stay
- `lua/lalin/host_issue_values.lua` — issue types stay
- `lua/lalin/host_template_values.lua` — template API stays
- `lua/lalin/host_decl_values.lua` — host decl API stays
- `lua/lalin/host_splice.lua` — fill functions stay (used by new values binder)
- `lua/lalin/open_expand.lua` — expander stays (used by new values binder)
- `lua/lalin/region_compose.lua` — internal users of `api.param`/`api.region_frag` stay
- `lua/lalin/pvm_surface_*.lua` — internal users of `api.param` stay
- `lua/lalin/ast.lua` — low-level ASDL constructors stay

## Worker Output — 2026-05-19 10:22:37

All tests pass. The 4 failures are pre-existing and unrelated to this refactoring.

## Completed

Implemented all 11 phases of the unified `lalin.XXX` metaprogramming API. The `function(b)` builder pattern is retired. The new API has three uniform shapes:

1. **`lalin.XXX[[]]`** — Pure quote. Parse Lalin string, return typed ASDL. Errors if `@{}` is present.
2. **`lalin.XXX{values}[[src]]`** — Values binder. Bind Lua values first, then quote. Evaluates `@{}` from values table using the explicit table key.
3. **`lalin.XXX{array}`** — Table builder. Pass an array of record tables, get typed ASDL back.

## Files Changed

- `lua/lalin/parse.lua` — Added 7 standalone parse entry points (`parse_expr_string`, `parse_func_string`, `parse_region_string`, `parse_struct_string`, `parse_union_string`, `parse_extern_string`, `parse_expr_frag_string`), updated `M.Define(T)` to expose them, added `splice_text` to splice slot records
- `lua/lalin/host.lua` — Complete rewrite: unified quoting API (type, expr, stmts, func, region, struct, union, extern, expr_frag via `make_quote`), table builder aliases, stmts dispatch via `api.stmts`
- `lua/lalin/host_func_values.lua` — Added `api.params{}` table builder, `api._stmts_quote()` and `api._stmts_values_binder()`, removed `api.stmts(bindings,builder_fn)`, `api.control_block`, `api.cont_decl`, added `api.stmts` as unified metatable dispatch, updated `as_param` to accept duck-typed `{name,type}` tables
- `lua/lalin/host_struct_values.lua` — Added `api.fields{}` and `api.variants{}` table builders, removed `api.struct(name,fields)` and `api.union(name,fields)`
- `lua/lalin/host_region_values.lua` — Added `api.conts{}`, `api.blocks{}`, `api.entry_params{}` table builders, removed `api.entry_param(name,ty,init)`
- `lua/lalin/host_expr_values.lua` — Removed `api.call(name,args,result_ty)`
- `lua/lalin/host_fragment_values.lua` — Trimmed: removed `ExprFragBuilder`, `api.expr_frag`, `api.emit_expr`, kept `ExprFragValue` metatable
- `lua/lalin/host_values.lua` — Added `lalin_splice` method to `ExprFragValue`
- `lua/lalin/host_session.lua` — Removed `host_fragment_values` from Install list
- `LANGUAGE_REFERENCE.md` — Replaced sections 14-16 (Lua splicing, builder API reference, metaprogramming guide) with new unified API documentation
- `tests/test_host_stmt_list_builder.lua` — Replaced `lalin.stmts({}, fn)` with `lalin.stmts[[]]`
- `tests/test_direct_mutual_recursion.lua` — Replaced `lalin.param` with raw `{name,type}` tables, `lalin.call` with `lalin.expr[[]]`
- `tests/test_host_extern_symbol.lua` — Same replacements
- `tests/test_host_struct_values.lua` — Replaced `lalin.struct("Pair",{lalin.field(...)})` with `lalin.struct[[]]`
- `tests/test_spread_splice_regions.lua` — Replaced `lalin.param`, `lalin.cont_decl` with table builders
- `tests/test_spread_splice_lists.lua` — Replaced `lalin.param`/`lalin.field`/`lalin.variant` with table builders

## Documenter Output — 2026-05-19 11:43:04

Now I have a thorough understanding of the architecture. Here is the self-sustaining document.

---

# Values Table as Module System — Architectural Decision Record

**Date**: 2026-05-19  
**Phase**: Architecture  
**Workflow**: wf-meta-ergo (continuation of the unified `lalin.XXX` metaprogramming API)

---

## Goal

Enable **cross-function dependencies** in `lalin.func { values } [[ src ]]` so that functions can reference each other by plain Lalin name (not just via `@{}`). The values table serves double duty: it registers every entry as a module-level name **and** fills `@{}` splice slots. The module API becomes a lower-level tool — no longer required for the interdependent-function case.

---

## Incentives

The current unified API (`lalin.func { values } [[ src ]]`) has a gap: the values table works for `@{}` splices but not for plain Lalin name references.

**Concrete problems**:

1. **Forced `@{}` on every dependency**: If function A calls function B, the source must write `@{B}(args)` rather than `B(args)`. This is visually noisy and breaks the expectation that Lalin code inside a quote should look like Lalin code.

2. **Module API is the only escape**: To use plain name references (`parse_array(args)`), users must drop down to the module API:
   ```lua
   local m = lalin.module("parser")
   m:add_func(parse_array)
   m:add_func(parse_value)
   local compiled = m:compile()
   local fn = compiled:get("parse_value")
   ```
   This is the old `module/compile/get/free` dance — exactly what the unified API was meant to replace.

3. **`lalin.func { }` and `lalin.module()` are two ways to say "compile this with deps"**: The values table already contains all dependency information — it's an explicit key-value map of `name → value`. Forcing users to also construct a `ModuleValue` object duplicates that information and defeats the purpose of the unified API.

4. **The `CallableFunc` lazy-compile pattern is half-built**: Currently `CallableFunc:__call` creates an ephemeral module with just the one function, compiles it, and calls it. It has no mechanism to include dependencies — so cross-function calls cannot work.

---

## Current State

### How `lalin.func { values } [[ src ]]` works today

The flow is in `lua/lalin/host.lua`, inside `make_quote`:

```
lalin.func { parse_array = func_val, skip_ws = region_val, literal_arms = stmts_val }
  ──→ values binder detects string keys
  ──→ returns function(src) ... end  (a closure capturing bound_values)
```

When the returned function is called with `[[ src ]]`:

1. **Parse** `src` with `parse_func_string(T, src)` → produces `parsed` with `splice_slots` array
2. **If no `@{}`**: wrap the raw ASDL and return a `CallableFunc` (via `wrap_fn`)
3. **If `@{}` present**: iterate `parsed.splice_slots`:
   - Look up each splice key in `bound_values`
   - Call `host_splice.fill(session, slot, value, site, role, spread)` for each
   - Call `open_expand.Define(T).env_with_fills(env, bindings)`
   - Call `expand_fn(e, parsed.value, env)` to resolve slots in the AST
   - Wrap the expanded ASDL and return a `CallableFunc`

### How `CallableFunc:__call` works today

From `lua/lalin/host.lua`:

```lua
function CallableFunc:__call(...)
    if not self._compiled then
        local api = self._api
        local m = api.module(self.name .. "_auto")
        m:add_func(self)
        local compiled = m:compile()
        self._compiled = compiled
        self._fn = compiled:get(self.name)
    end
    return self._fn(...)
end
```

The ephemeral module has:
- A single function (`self`) added via `m:add_func(self)`
- No other items (no dependency funcs, no regions, no structs)

If the function body calls `parse_array(args)` by name, the Lalin typechecker (`lua/lalin/tree_typecheck.lua`) needs to resolve `parse_array` in the module scope — but `parse_array` is not in the module's items.

### How name resolution works in Lalin modules

A `Tr.Module` in `lua/lalin/ast.lua` carries a list of items:

```
Tr.Module(ModuleTyped("module_name"), [ItemFunc(f1), ItemFunc(f2), ...])
```

The typechecker (`tree_typecheck.lua`) resolves function calls by looking up names in the module's item list. `FuncLocal` with `name = "parse_array"` becomes available as a name target for calls within the same module. This is how `.mlua` files work — all functions in a `.mlua` document share a module, and cross-references resolve during typechecking.

The gap is architectural, not in the typechecker: the ephemeral module inside `CallableFunc:__call` simply doesn't include the dependency functions.

### The `@{}` expansion path is separate from module name resolution

- **`@{}` splices** expand via `open_expand.lua` — the slot is filled with an ASDL node, and the expander substitutes it into the AST before typechecking. This happens at the `open_expand` phase, which is before `closure_convert` and `tree_typecheck`.

- **Plain name references** (`parse_array(args)`) produce `Tr.ExprCall(...)` nodes whose callee is a `ValueRefName("parse_array")`. These are resolved during `tree_typecheck` by looking up the name in the function's module scope.

These are two entirely different resolution mechanisms at different pipeline phases. The values table currently feeds only the first mechanism.

---

## Chosen Target

### Core decision: The values table IS the module system

Every key-value pair in `lalin.func { key = value }` serves two roles:

1. **Module registration**: `value` is registered in the compilation module's environment under `key` as a named item (func, region, extern, type, etc.)
2. **Splice filling**: If `@{key}` appears in the source, the slot is filled from the values table (existing behavior, unchanged)

Values not referenced by `@{}` are still registered — they are dependencies, just ones resolved by name rather than by splice.

### How it works end-to-end

```lua
local parse_array = lalin.func [[parse_array(buf: ptr(u8), n: i32) -> i32 ... end]]
local skip_ws = lalin.region [[skip_ws(buf: ptr(u8), pos: i32; next: cont(next: i32)) ... end]]

local parse_value = lalin.func {
    parse_array = parse_array,   -- registered in ephemeral module as func "parse_array"
    skip_ws     = skip_ws,       -- registered as region "skip_ws"
    literal_arms = literal_arms, -- fills @{} splice (not a named dep)
} [[
parse_value(buf: ptr(u8), n: i32, i: i32) -> i32
    let x = parse_array(buf, n)       -- resolved by module name lookup
    emit skip_ws(buf, i; next = cont) -- resolved by module name lookup
    switch ... do
    @{literal_arms...}
    end
end
]]
```

**When the quote function is called with the source string:**

1. **Parse** `src` → produces `parsed` with `splice_slots` and a raw `FuncLocal` ASDL node
2. **Fill `@{}` splices** (existing mechanism): each `@{key}` in parsed is filled from `bound_values` via `host_splice.fill` → produces `bindings[]`
3. **Build ephemeral module** (new mechanism):
   - Create `ModuleValue` with name derived from the function name (or a generated name)
   - For each key in `bound_values`, if the value is a hosted func/region/extern/struct:
     - Call `m:add_func(value)` or `m:add_region(value)` etc.
     - The item is registered in the module's item list under its key name
   - Add the function itself: `m:add_func(self_func_value)`
4. **Expand** via `open_expand` using the fill env (same as today)
5. **Compile** the module (same as `CallableFunc:__call` does today):
   - Lower the module: `expand → closure_convert → typecheck → layout → back`
   - Cross-function name references resolve during typechecking because all deps are in the module's items
6. **Cache** the compiled pointer → subsequent calls use it directly

### What changes in `CallableFunc:__call`

The current implementation builds an ephemeral module with only `self`:

```lua
function CallableFunc:__call(...)
    if not self._compiled then
        local m = api.module(self.name .. "_auto")
        m:add_func(self)
        ...
    end
end
```

The new implementation receives the values binder's `bound_values` table and adds each dependency:

```lua
function CallableFunc:__call(...)
    if not self._compiled then
        local m = api.module(self.name .. "_auto")
        -- Register all values-table entries as module items
        if self._dep_values then
            for name, value in pairs(self._dep_values) do
                if value.kind == "func" or value.kind == "extern_func" then
                    m:add_func(value)
                elseif value.kind == "region_frag" or value.lalin_quote_kind == "region_frag" then
                    m:add_region(value)
                elseif value.kind == "struct" or value.kind == "union" then
                    m:add_type(value)
                end
            end
        end
        -- Add the function itself
        m:add_func(self)
        local compiled = m:compile()
        self._compiled = compiled
        self._fn = compiled:get(self.name)
    end
    return self._fn(...)
end
```

The `_dep_values` field stores the bound values table, set when the `CallableFunc` is created from a values-binder call. For pure quotes (`lalin.func[[src]]`), `_dep_values` is nil and the behavior is unchanged.

### What changes in `make_quote`

In `lua/lalin/host.lua`, the values-binder path stores `bound_values` on the resulting `CallableFunc`:

```lua
-- In the __call metatable for values binder:
return function(src)
    -- ... parse, fill, expand ...
    local result = wrap_fn(expanded, parsed, T)
    -- Store deps for lazy compilation
    if type(result) == "table" and result._api and result.__call then
        result._dep_values = bound_values
    end
    return result
end
```

### What changes in `CallableFunc` construction

The `CallableFunc` metatable gets a new field:

```lua
local CallableFunc = {}
CallableFunc.__index = CallableFunc

function CallableFunc:__call(...)
    if not self._compiled then
        local api = self._api
        local m = api.module(self.name .. "_auto")
        
        -- Register dependency values as module items
        if self._dep_values then
            for name, value in pairs(self._dep_values) do
                local mt = getmetatable(value)
                if mt == api.FuncValue or rawget(value, "kind") == "func" then
                    -- ModuleValue:add_func expects the value to have an .item or :as_item()
                    pcall(function() m:add_func(value) end)
                elseif rawget(value, "lalin_quote_kind") == "region_frag"
                    or rawget(value, "kind") == "region_frag" then
                    pcall(function() m:add_region(value) end)
                elseif rawget(value, "kind") == "struct" or rawget(value, "kind") == "union" then
                    pcall(function() m:add_type(value) end)
                end
            end
        end
        
        m:add_func(self)
        local compiled = m:compile()
        self._compiled = compiled
        self._fn = compiled:get(self.name)
    end
    return self._fn(...)
end
```

### The two reference styles

| Reference style | Source example | Resolution mechanism | Phase |
|---|---|---|---|
| `@{parse_array}(args)` | Explicit Lua dependency | `@{}` slot fill → `open_expand` → resolved before typechecking | Open expansion |
| `parse_array(args)` | Plain Lalin name | Module item lookup during `tree_typecheck` | Typechecking |

Both resolve correctly because the values table registers `parse_array` in the module's items, AND the parser creates a `Slot*` for `@{parse_array}` that gets filled by the same values table.

**The user chooses which style to use** — they are not mutually exclusive. `@{fn}(args)` makes the dependency visually explicit at the call site. `fn(args)` looks like standard Lalin code and relies on module-level resolution. Both work with the same values table.

### When `@{}` is used, it resolves at expansion time (pre-typecheck)

The `@{fn}(args)` form has a subtle difference from `fn(args)`: the `@{}` slot is filled during open expansion, which happens **before** closure conversion and typechecking. This means the function reference is resolved into the AST before the typechecker sees it. The typechecker then sees a `Call` to a resolved function reference, not an unresolved name.

The `fn(args)` form (no `@{}`) produces a `ValueRefName("fn")` node in the AST, which the typechecker resolves by looking up `fn` in the module's items.

Both converge to the same result — the only difference is which pipeline phase resolves the reference.

### Values table entries without `@{}` references

If a value in the table is not referenced by `@{}` in the source (but IS referenced by plain name), it is still **registered in the ephemeral module** — that's the entire point of this change. The `@{}` splices are optional; the module registration is not.

If a value in the table is neither referenced by `@{}` nor by plain name, it is registered in the module but unused. The typechecker will ignore it. This is harmless — the module compiles with unreferenced items (they just don't produce any native code if not called from the entry point).

### What stays the same

| Aspect | Status |
|---|---|
| `lalin.func[[]]` pure quote (no values table) | Unchanged. No deps, no ephemeral module changes. |
| `lalin.module()` explicit module construction | Unchanged. Still works for large multi-function artifacts, explicit export control, shared compilation. |
| `@{}` fill + expand pipeline | Unchanged. `host_splice.fill()` → `open_expand.env_with_fills()` → `expand_fn()`. |
| `CallableFunc:free()` | Unchanged. Frees the compiled artifact. |
| `ModuleValue:add_func()`, `:add_region()`, `:add_type()` | Unchanged. These are the same registration methods the ephemeral module calls. |
| Cross-function name resolution during typechecking | Unchanged — it already works when functions share a module. The change is simply adding deps to the module before compilation. |
| Error on `@{}` in pure quote (no values table) | Unchanged. Still errors with "lalin.XXX[[]] does not evaluate @{}". |

---

## Tradeoffs Acknowledged

1. **All values table entries become module items, not just `@{}`-referenced ones**: If a user puts a large value in the table but doesn't reference it (neither via `@{}` nor by name), it gets compiled into the module unnecessarily. **Acceptable because** the user controls the table contents — unused entries are a user error, not an architectural problem.

2. **The `pcall` wrappers around `m:add_func`/`:add_region`/`:add_type`**: Not all values in the table are Lalin items. Scalar values, expression values, and raw ASDL arrays are in the table for `@{}` filling but have no module-level name registration. The `pcall` catches cases where the value doesn't support the `add_*` interface. **Acceptable because** `pcall` is a pragmatic guard, and the registration is best-effort — missing a registration is recoverable (the function just won't be findable by name).

3. **Duplicate dependency handling**: If the same value is passed under two different keys, it's registered twice in the module. ModuleValue reserves names and errors on duplicates. **Acceptable because** this is a user error, and the error message is descriptive.

4. **`@{}` references bypass module name resolution entirely**: A user could write `@{parse_array}(args)` where `parse_array` is the function name, and it would work without `parse_array` being registered in the module — because the `@{}` fill substitutes the function reference directly into the AST. This means `@{fn}(args)` works even without the module registration change. **Acceptable because** the module registration is needed only for the plain-name `fn(args)` path, and having both paths adds robustness.

5. **Increased compilation latency on first call**: The ephemeral module now compiles not just one function but potentially many (all registered deps). **Acceptable because** (a) the module is ephemeral and the result is cached for subsequent calls, (b) individual functions in the module are small, and (c) the previous alternative was the manual module/compile/get dance, which had the same cost.

---

## Risks Acknowledged

1. **ModuleValue's name reservation conflicts**: Each `m:add_func(value)` calls `reserve_func_name(self, value.name)`, which checks `self.func_names[name]`. If two values in the table have the same `.name` field (but different keys in the values table), the second registration errors. **Mitigation**: The ephemeral module's name space is per-compile, so conflicts are limited to the values table itself. Clear error message.

2. **`m:add_region` does not register a name** (no `reserve_func_name` equivalent): `ModuleValue:add_region` (in `host_module_values.lua`) appends to `self.region_frags` but does not call any name reservation. This means name-based region lookup during typechecking uses the `region_frags` list, not the func/type name maps. **Acceptable** — the typechecker's region lookup path is separate from the func/type path.

3. **Circular dependencies**: If function A calls function B in plain Lalin, and function B calls function A, both must be in the same values table. But creating func A requires func B to be already created, and vice versa. **Mitigation**: Both functions must be created first (as pure quotes or table builders), then the values table binds them together. Forward references in Lalin are supported as long as both items are in the same module — the typechecker handles this because all items are collected before typechecking starts.

4. **`pcall` as guard swallows errors**: If `m:add_func(value)` errors for a reason other than "value is not a func" (e.g., an actual bug in `add_func`), the `pcall` swallows it. **Mitigation**: Use a more specific check — check for `value.kind == "func"` explicitly before calling `m:add_func`, rather than using `pcall`. Only use `pcall` for truly uncertain cases like the region metatable check.

5. **Name collision between values table key and function's own name**: If the values table has `{ add = some_func }` but the function being defined is also named `add`, the ephemeral module has two items named `add`. **Mitigation**: `reserve_func_name` errors on duplicate. The error message should help debugging.

6. **Expansion env vs. module env are separate worlds**: The `@{}` fill mechanism uses `open_expand` env (fills in a `FillSet`). The module-level name resolution uses the module's item list. These are managed by different subsystems. If both are in play (`@{fn}(args)` and `fn(args)` in the same function body), the `@{}`-filled references resolve during expansion and the name-based ones resolve during typechecking. Both converge because `open_expand` substitutes the slot with the actual function reference ASDL node, and the typechecker sees the resolved node. **Acceptable** — the two mechanisms are independent and converge to the same result.

---

## Implementation sketch

### `lua/lalin/host.lua` — `CallableFunc` changes

Add `_dep_values` field to `CallableFunc` instances created by values binders:

```lua
-- In make_quote, inside the values-binder's returned function:
local result = wrap_fn(expanded, parsed, T)
if type(result) == "table" and result._api and result.__call then
    result._dep_values = bound_values
end
```

Modify `CallableFunc:__call` to register deps before compilation:

```lua
function CallableFunc:__call(...)
    if not self._compiled then
        local api = self._api
        local m = api.module(self.name .. "_auto")
        
        -- Register dependency values as module items
        if self._dep_values then
            for name, value in pairs(self._dep_values) do
                local kind = rawget(value, "kind")
                local qkind = rawget(value, "lalin_quote_kind")
                if kind == "func" then
                    m:add_func(value)
                elseif kind == "extern_func" then
                    m:add_func(value)
                elseif kind == "region_frag" or qkind == "region_frag" then
                    m:add_region(value)
                elseif kind == "struct" or kind == "union" then
                    m:add_type(value)
                end
            end
        end
        
        m:add_func(self)
        local compiled = m:compile()
        self._compiled = compiled
        self._fn = compiled:get(self.name)
    end
    return self._fn(...)
end
```

### `lua/lalin/host.lua` — `make_quote` changes

In the values-binder path, store `bound_values` on the result before returning:

```lua
return function(src)
    local T = default_session.T
    local parsed = parse_fn(T, src)
    if #parsed.issues ~= 0 then error(parsed.issues[1].message, 2) end
    if #parsed.splice_slots == 0 then return wrap_fn(parsed.value, parsed, T) end
    
    local hs = require("lalin.host_splice")
    local open_expand = require("lalin.open_expand")
    local bindings = {}
    for _, ss in ipairs(parsed.splice_slots) do
        local key = ss.splice_text or ss.splice_id
        local v = bound_values[key]
        if v == nil then
            error("no value bound for @" .. tostring(key) .. " in values table", 2)
        end
        local binding = hs.fill(default_session, ss.slot, v,
            "splice " .. ss.splice_id, ss.role, ss.spread)
        bindings[#bindings + 1] = binding
    end
    
    local e = open_expand.Define(T)
    local env = e.empty_env()
    env = e.env_with_fills(env, bindings)
    local expanded = expand_fn(e, parsed.value, env)
    local result = wrap_fn(expanded, parsed, T)
    
    -- ⬇ NEW: attach deps for lazy compilation
    if type(result) == "table" and result._api and result.__call then
        result._dep_values = bound_values
    end
    
    return result
end
```

### `lua/lalin/host_module_values.lua` — verify `add_region` signature

`ModuleValue:add_region` (line ~41):

```lua
function ModuleValue:add_region(value)
    if value.frag then
        self.region_frags[#self.region_frags + 1] = value.frag
    end
    return value
end
```

This is already compatible — it accepts the kind of value produced by `lalin.region[[]]` (which sets `lalin_quote_kind = "region_frag"` and `.frag = value`).

### Test expectations

```lua
-- Pure quote: no deps needed
local f = lalin.func [[add(a: i32, b: i32) -> i32 return a + b end]]
f:free()

-- Values binder with cross-function reference via plain name
local parse_number = lalin.func [[parse_number(s: ptr(u8), n: i32) -> i32 ... end]]

local parse_value = lalin.func {
    parse_number = parse_number,
} [[
parse_value(s: ptr(u8), n: i32) -> i32
    return parse_number(s, n)  -- plain name reference, no @{}
end
]]
-- First call compiles: parse_number is registered in the ephemeral module
assert(parse_value(buf, len) == expected)
parse_value:free()
```

## Edit-planner Output — 2026-05-19 11:50:36

Now I have all the exact line numbers and text. Here is the complete implementation plan.

---

# Implementation Plan: `@{}` with Function Calls in Values Binder

## Precondition Checks

1. **`host_splice.lua` line 113-173**: `M.fill_expr(session, slot, value, site)` — expression filler function, ends with error at line ~162
2. **`host.lua` lines 69-79**: `CallableFunc:__call` — lazy compilation, calls `m:add_func(self)` at line 73
3. **`host.lua` lines 95-130**: `make_quote` values binder — inner `return function(src)` at line 105, calls `expand_fn` and `wrap_fn` at lines 127-128
4. **`host.lua` lines 62-65**: `CallableFunc` metatable = `{ __index = CallableFunc }` — checking with `getmetatable(result) == CallableFunc` is the correct identity check

---

## File 1: `lua/lalin/host_splice.lua`

### Change 1.1: Add `B` (LalinBind) to `fill_expr` locals

**Goal**: Extract `B` (LalinBind) from `session.T` so it's available for constructing `ValueRefName`.

**Location**: Line 115

**oldText**:
```lua
function M.fill_expr(session, slot, value, site)
    local T  = session.T
    local C, Tr, O = T.LalinCore, T.LalinTree, T.LalinOpen
```

**newText**:
```lua
function M.fill_expr(session, slot, value, site)
    local T  = session.T
    local C, Tr, O, B = T.LalinCore, T.LalinTree, T.LalinOpen, T.LalinBind
```

**Rationale**: The `fill_expr` function needs `B.ValueRefName` to construct a name reference for FuncValue-based expressions. `T.LalinBind` is already available via `session.T` — it just wasn't destructured before.

---

### Change 1.2: Add FuncValue/ExternFunc handling to `fill_expr`

**Goal**: When `@{fn}` fills an expression slot and the value is a hosted function (FuncValue, CallableFunc with `kind == "func"`), produce an `ExprRef(ValueRefName(name))` instead of erroring.

**Location**: Lines 160-163. Insert after the host-ExprValue check and before the `if not expr then error(...)` guard.

**oldText** (lines 156-167):
```lua
    -- 3. Host ExprValue or direct ASDL Expr node.
    if not expr and type(value) == "table" then
        if type(value.as_expr_value) == "function" then
            expr = value:as_expr_value().expr
        elseif pvm.classof(value) ~= false then
            expr = value
        end
    end

    if not expr then
        error((site or "splice") .. ": expected expression value for @{} expr splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotExpr(slot), O.SlotValueExpr(expr))
```

**newText** (lines 156-172):
```lua
    -- 3. Host ExprValue or direct ASDL Expr node.
    if not expr and type(value) == "table" then
        if type(value.as_expr_value) == "function" then
            expr = value:as_expr_value().expr
        elseif pvm.classof(value) ~= false then
            expr = value
        end
    end

    -- 4. Host function-like value → name reference expression.
    -- The function is registered in the ephemeral module by CallableFunc:__call,
    -- so the typechecker can resolve this name reference.
    if not expr and type(value) == "table" then
        local kind = rawget(value, "kind")
        if kind == "func" or kind == "extern_func" then
            expr = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(rawget(value, "name") or "?"))
        end
    end

    if not expr then
        error((site or "splice") .. ": expected expression value for @{} expr splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotExpr(slot), O.SlotValueExpr(expr))
```

**Rationale**: The expression filler currently handles numbers, booleans, strings, ExprValues, and raw ASDL nodes — but not hosted function values. When `@{fn}` appears in expression position (e.g., `@{fn}(args)`), the filler sees `cls == O.SlotExpr` and calls `fill_expr`. The value is a FuncValue/CallableFunc with `kind == "func"`. Instead of erroring, we emit `ValueRefName(fn_name)` — a name reference that the typechecker resolves against the module's item list. The function will have been registered in the ephemeral module by `CallableFunc:__call`.

**Danger zone**: Use `rawget(value, "kind")` and `rawget(value, "name")` — NOT `value.kind`/`value.name` (metatable `__index` may interfere, and rawget is the pattern used throughout this file — see `kind_of` at line 20).

---

## File 2: `lua/lalin/host.lua`

### Change 2.1: Attach `_dep_values` in `make_quote` values binder

**Goal**: After expanding and wrapping the result, store the bound values table on the output so `CallableFunc:__call` can register them as module items.

**Location**: Lines 127-130. Inside the values binder's inner `return function(src)`, after `local expanded = expand_fn(e, parsed.value, env)` and `return wrap_fn(expanded, parsed, T)`.

**oldText** (lines 124-131):
```lua
                    local e = open_expand.Define(T)
                    local env = e.empty_env()
                    env = e.env_with_fills(env, bindings)
                    local expanded = expand_fn(e, parsed.value, env)
                    return wrap_fn(expanded, parsed, T)
                end
            end
```

**newText** (lines 124-140):
```lua
                    local e = open_expand.Define(T)
                    local env = e.empty_env()
                    env = e.env_with_fills(env, bindings)
                    local expanded = expand_fn(e, parsed.value, env)
                    local result = wrap_fn(expanded, parsed, T)
                    -- Attach deps for lazy compilation in CallableFunc:__call
                    if type(result) == "table" then
                        local mt = getmetatable(result)
                        if mt == CallableFunc then
                            result._dep_values = bound_values
                        end
                    end
                    return result
                end
            end
```

**Rationale**: The values binder returns either a raw ASDL value (via `wrap_fn`) or a `CallableFunc`. If it's a `CallableFunc`, we attach `_dep_values` so that `CallableFunc:__call` can register each dependency in the ephemeral module before compilation. This is what enables typechecker name resolution for `@{fn}(args)` — the function `fn` is registered in the module, and the `@{}` fill produces a name reference.

**Danger zone**: The `getmetatable(result) == CallableFunc` check uses identity comparison with the `CallableFunc` table defined at line 62. This is correct because `CallableFunc` is a module-local table. The check must be `mt == CallableFunc`, not a string comparison.

---

### Change 2.2: Register deps in `CallableFunc:__call`

**Goal**: Before compiling the ephemeral module, register all values from `_dep_values` as module items so the typechecker can resolve plain Lalin name references.

**Location**: Lines 69-79. Inside `CallableFunc:__call`, before `m:add_func(self)`.

**oldText** (lines 69-79):
```lua
function CallableFunc:__call(...)
    if not self._compiled then
        local api = self._api
        local m = api.module(self.name .. "_auto")
        m:add_func(self)
        local compiled = m:compile()
        self._compiled = compiled
        self._fn = compiled:get(self.name)
    end
    return self._fn(...)
end
```

**newText** (lines 69-95):
```lua
function CallableFunc:__call(...)
    if not self._compiled then
        local api = self._api
        local m = api.module(self.name .. "_auto")

        -- Register dependency values as module items so the typechecker
        -- can resolve cross-function name references (plain Lalin names).
        if self._dep_values then
            for _, value in pairs(self._dep_values) do
                local kind = rawget(value, "kind")
                if kind == "func" or kind == "extern_func" then
                    pcall(function() m:add_func(value) end)
                elseif kind == "region_frag" or rawget(value, "lalin_quote_kind") == "region_frag" then
                    pcall(function() m:add_region(value) end)
                elseif kind == "struct" or kind == "union" then
                    pcall(function() m:add_type(value) end)
                end
            end
        end

        m:add_func(self)
        local compiled = m:compile()
        self._compiled = compiled
        self._fn = compiled:get(self.name)
    end
    return self._fn(...)
end
```

**Rationale**: The ephemeral module created by `CallableFunc:__call` must contain all dependency functions/regions/structs that the function's body references by name. The typechecker resolves `ValueRefName("parse_array")` by scanning the module's item list — if the item isn't there, the reference fails. By registering each dep before `m:add_func(self)`, we ensure all cross-references resolve.

**Danger zone 1**: Order matters — deps must be registered BEFORE `m:add_func(self)` because `ModuleValue:add_func` may need to resolve names from already-registered items for contract checking.
**Danger zone 2**: `pcall` is used because not all values in `_dep_values` are Lalin items — some are scalars, expressions, or raw ASDL arrays used for `@{}` filling only. The `pcall` silently skips values that don't support `:add_func()`. This is intentional.
**Danger zone 3**: `rawget(value, "kind")` — use rawget, NOT `value.kind`, to avoid metatable interference. This matches the pattern in `host_splice.lua`.
**Danger zone 4**: `ModuleValue:add_region` (in `host_module_values.lua`) does NOT reserve a name — it appends to `self.region_frags`. This is fine: the typechecker resolves region references from the region_frags list, not from a name map. `ModuleValue:add_type` similarly appends to `self.types`.

---

## Testing Strategy

After applying all three changes:

1. **Smoke test**: `lalin.func { dep = f } [[ @{dep}(args) ]]` where `f` is a FuncValue and the body calls `dep(x, y)` via `@{dep}(x, y)`, registered in ephemeral module.

2. **Plain name reference test**: `lalin.func { dep = f } [[ dep(args) ]]` where the body uses plain Lalin name `dep(x, y)` — relies on module registration, NOT on `@{}` filling.

3. **Mixed test**: `lalin.func { dep = f, val = lalin.int(42) } [[ let x = @{dep}(@{val}) end ]]` — both `@{}` for expression and function reference.

4. **Negative test**: `lalin.func[[]]` (pure quote) still errors on `@{}`.

5. **Full regression**: `for f in tests/test_*.lua; do luajit $f; done`
