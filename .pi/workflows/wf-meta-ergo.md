# Lalin metaprogramming ergonomics — builder vs source quoting vs splicing
Explore the full landscape of how Lalin code is constructed: source syntax (quoted in .mlua), lalin.stmts[[]] snippets, the builder API (host_*_values.lua), @{} antiquote splicing, and the PVM/ASDL layer. Find the friction points, the duplication, and the gaps. Goal: understand whether there's a real gap worth filling to make metaprogramming feel more natural, or whether the current layers are sufficient.
**Started**: 2026-05-19 07:41:40
---

## Scout Output — 2026-05-19 07:45:45

Now I have a comprehensive picture. Let me compile the full map.

---

# Lalin Metaprogramming — Comprehensive Terrain Map

## Files Retrieved

1. `lua/lalin/parse.lua` (2384 lines) — Unified lexer + Pratt parser. Single parsing path for all island kinds. Tokenizer emits `TK.hole` for `@{...}` antiquote splices; parser creates typed `LalinOpen` slots.
2. `lua/lalin/host_func_values.lua` (450 lines) — `api.stmts()`, `api.param()`, `api.control_block()`, `api.switch_arm()`, `FuncBuilder` with all builder methods (`:let`, `:var`, `:if_`, `:switch_`, `:jump`, `:emit`, `:return_`, `:yield_`, `:set`, `:expr`)
3. `lua/lalin/host_region_values.lua` (430 lines) — `RegionFragValue`, `RegionBuilder`, `BlockBuilder`. Methods: `:entry()`, `:block()`, `:block_decl()`, `:jump()`, `:yield_()`, `:emit()`, `:if_()`, `:switch_()`. `BlockValue:body_fn()` for deferred body assignment.
4. `lua/lalin/host_fragment_values.lua` (140 lines) — `ExprFragValue`, `ExprFragBuilder`, `api.expr_frag()`, `api.emit_expr()`, `api.expr_frag_template()`
5. `lua/lalin/host_values.lua` (200 lines) — Canonical value handles: `RegionFragValue`/`ExprFragValue` wrappers for ASDL nodes, `lalin.memoize()`, `host_value_ref()`, `deps_asdl_from_table()`
6. `lua/lalin/host_expr_values.lua` (280 lines) — `ExprValue` metatable with operator overloads (`__add`, `__sub`, `__mul`, etc.) and methods (`:field`, `:index`, `:select`, `:as`, `:eq`/`:ne`/`:lt`/etc). Constructor functions: `lalin.int()`, `lalin.float()`, `lalin.bool_lit()`, `lalin.string_lit()`, `lalin.select()`, `lalin.load()`, `lalin.addr_of()`, `lalin.call()`, `lalin.agg()`, `lalin.array_expr()`, `lalin.intrinsic()`, atomics.
7. `lua/lalin/host_type_values.lua` (130 lines) — `TypeValue` metatable, scalar types as prebuilt singletons, constructors: `lalin.ptr(T)`, `lalin.array()`, `lalin.view()`, `lalin.func_type()`, `lalin.closure_type()`, `lalin.named()`, `lalin.path_named()`, `lalin.local_named()`
8. `lua/lalin/host_struct_values.lua` (250 lines) — `StructValue`, `DraftStructValue`, `TypeDeclValue`, `FieldValue`. Builder: `lalin.field()`, `lalin.variant()`, `lalin.struct()`, `lalin.union()`, `lalin.tagged_union()`, `lalin.enum()`, `lalin.newstruct()`
9. `lua/lalin/host_template_values.lua` (90 lines) — `StructTemplateValue`, `api.type_param()`, `api.struct_template()`. Template instantiation via `open_expand.ExpandEnv`.
10. `lua/lalin/host_module_values.lua` (250 lines) — `ModuleValue` with `:struct()`, `:union()`, `:func()`, `:export_func()`, `:extern_func()`, `:compile()`, `:emit_object()`, `:to_asdl()`. `CompiledModule`/`CompiledFunction` wrappers.
11. `lua/lalin/host_decl_values.lua` (240 lines) — Host declaration builders: `lalin.host_struct()`, `lalin.host_expose()`, `lalin.host_field()`, `lalin.host_lua_accessor()`, `lalin.host_field_accessor()`, `lalin.host_lalin_accessor()`, `lalin.host_bool8/bool32`, etc.
12. `lua/lalin/host_splice.lua` (420 lines) — Single coercion point for splice-hole filling. `M.fill()` dispatches by `Slot` subclass. Fillers for all roles: `type`, `expr`, `expr_list`, `type_list`, `param_list`, `field_list`, `variant_list`, `switch_stmt_arm_list`, `switch_expr_arm_list`, `open_param_list`, `block_param_list`, `entry_param_list`, `cont_slot_list`, `control_block_list`, `region_body`, `region_frag`, `expr_frag`, `name`.
13. `lua/lalin/host_session.lua` (140 lines) — Session management. `Session:api()` installs all host_*_values modules. `Session:symbol_key()` generates unique symbols.
14. `lua/lalin/host.lua` (40 lines) — Thin public facade. Default session exposed as `lalin.*`.
15. `lua/lalin/mlua_run.lua` (920 lines) — `.mlua` runner. `scan_document` → parse per island → fill splice slots via `host_splice` → expand via `open_expand` → wrap results as host values. Carrier code generation via `quote.lua`.
16. `lua/lalin/open_expand.lua` (1030 lines) — Expands open slots/fills into concrete ASDL. `lookup_slot_value`, `expand_type`, `expand_expr`, `expand_stmt`, `expand_func`, `expand_region_frag`, `expand_expr_frag`, `expand_module`. Resolves all `TSlot`/`SlotValue*` placeholders.
17. `lua/lalin/pvm.lua` (1336 lines) — Recording phase boundary. Memoized triplets for all phase dispatch.
18. `lua/lalin/quote.lua` (140 lines) — Hygienic Lua code generation: `val()` capture, `sym()` fresh symbol, `__call` for lines, `emit()` compose, `compile()` to function.
19. `lua/lalin/ast.lua` (1060 lines) — Low-level ASDL node constructor API. All `Lalin*` ASDL nodes constructible directly with field-by-field params. No wrapper objects, no side caches.
20. `lua/lalin/asdl_builder.lua` (180 lines) — Meta-ASDL builder for defining ASDL schemas themselves (`schema`, `module`, `sum`, `product`, `alias`, `field`).
21. `lua/lalin/host_place_values.lua` — Place value wrappers (`lalin.place_ref()`, `lalin.place_name()`, etc.)
22. `LANGUAGE_REFERENCE.md` (3200 lines) — Sections 14 (splicing), 15 (builder API), 16 (metaprogramming guide) are the canonical documentation.
23. `tests/test_host_stmt_list_builder.lua` — Shows all three construction paths: source snippet `lalin.stmts[[]]`, builder form `lalin.stmts({x=...}, function(b)...)`, and region body fragment combined in one function.
24. `tests/test_spread_splice_lists.lua` — Four splice positions: parameter lists, field lists, variant lists, expression lists.
25. `tests/test_spread_splice_regions.lua` — Region param/cont/entry-param/block-param/block-list spread splices.
26. `tests/test_host_metaprogramming_patterns.lua` — Factory functions generating named region fragments via Lua closures, `@{...}` for constants, expression fragments specialized by constants.
27. `tests/test_region_frag_runtime_param_call.lua` — Type-spliced runtime params for `emit`.
28. `tests/test_host_template_values.lua` — `lalin.struct_template` with type params.
29. `tests/bench_frontend_speed.lua` — Module builder pattern for multiple functions, uses `lalin.stmts(function(b2)...)` for loop body in control blocks.
30. `tests/bench_both.lua` — Module builder benchmark pattern.

---

## Key Code

### Path A: Source syntax (.mlua files)

Entry point: `mlua_run.lua` `M.loadstring()` → `Parse.scan_document()` → per-island `ParseApi.parse_island()`.

The parser is a single unified Pratt parser (`parse.lua`). It shares the same token stream (`M.lex()`) and parser struct (`Parser`) for ALL island kinds. The island scanner (`M.scan_document()` in parse.lua, lines ~1700-1980) walks Lua source and finds Lalin keywords at "statement start" positions (after `=`, `return`, `end`, `open paren`, comma, etc.).

Each island gets a token *window* — `tokenize_island()` lexes from the start keyword through a depth-matched `end`, recording all tokens in a shared token array. The parser operates on `(first, limit)` boundaries, never on string slices.

**All Lalin constructs in source syntax** — these are the parse functions in parse.lua:

| Construct | Parser method | ASDL output class |
|---|---|---|
| `func f(...) -> T body end` | `parse_func()` (line ~1537) | `Tr.FuncLocal`/`Tr.FuncLocalContract` |
| `extern f(...) -> T end` | `parse_extern()` (line ~1510) | `Tr.ExternFunc` |
| `region name(...; ...) entry... end` | `parse_region_frag()` (line ~1630) | `O.RegionFrag` |
| `expr name(...) -> T body end` | `parse_expr_frag()` (line ~1700) | `O.ExprFrag` |
| `struct Name f: T end` | `parse_struct_island()` (line ~1724) | `Tr.TypeDeclStruct` |
| `union Name a(T) | b(T) end` | `parse_union_island()` (line ~1770) | `Tr.TypeDeclTaggedUnionSugar` |
| `if cond then ... else ... end` | `parse_if_stmt()` (line ~1007) | `Tr.StmtIf` |
| `switch val do case... end` | `parse_switch_stmt()` (line ~1040) | `Tr.StmtSwitch` |
| `let x: T = expr` / `var x: T = expr` | `parse_stmt()` (line ~1414) | `Tr.StmtLet`/`Tr.StmtVar` |
| `jump label(args)` / `jump cont(args)` | `parse_stmt()` (line ~1440) | `Tr.StmtJump`/`Tr.StmtJumpCont` |
| `yield [expr]` / `return [expr]` | `parse_stmt()` (line ~1430) | `Tr.StmtYieldVoid/Value` / `Tr.StmtReturnVoid/Value` |
| `emit frag(args; fills)` | `parse_emit_stmt()` (line ~1326) | `Tr.StmtUseRegionFrag` |
| `emit expr frag(args)` | `parse_emit_expr()` (line ~1365) | `Tr.ExprUseExprFrag` |
| `block label(args) -> T body end` | `parse_control_expr_after_block()` (line ~1139) | `Tr.ControlExprRegion` |
| `region -> T entry... block... end end` | `parse_multi_control_expr()` (line ~1155) | `Tr.ControlExprRegion` |
| `as(T, expr)` | `nud()` (line ~710) | `Tr.ExprCast` |
| Assignment `place = expr` | `parse_stmt()` (line ~1455) | `Tr.StmtSet` |

### Path B: `lalin.stmts[[]]` snippet quoting

Defined in `host_func_values.lua` lines ~345-360:

```lua
local function parse_stmt_snippet(src)
    local parsed = require("lalin.parse").Define(T).parse_stmts(src)
    if #parsed.issues ~= 0 then error(parsed.issues[1].message or ... , 3) end
    if #parsed.splice_slots ~= 0 then
        error("lalin.stmts string snippets do not evaluate @{} splices; ..., 3)
    end
    return parsed.value
end

function api.stmts(bindings, builder_fn)
    if type(bindings) == "string" and builder_fn == nil then
        return parse_stmt_snippet(bindings)
    end
    -- ... builder form
end
```

The snippet path calls `M.parse_stmt_string()` (`parse.lua` line ~2325), which:
1. Lexes the string with `M.lex(src)` (standalone lexer, no scan_document)
2. Parser is `new_parser_internal(T, toks, 1, toks.n, ...)` — no island wrapping
3. Calls `p:parse_stmt_until({})` — parses until eof, same `parse_stmt` method used in full parser
4. **Rejects `@{}` splices explicitly** — checks `#parsed.splice_slots ~= 0` and throws error

**What it CAN express**: Any statement-level Lalin construct (the same `parse_stmt()` function), including:
- `let`/`var` bindings
- `if`/`then`/`else`
- `switch`/`case`/`default`
- `return`/`yield`
- `jump`/`block`
- `emit` (region fragments by name only)
- Expression statements
- `atomic_store`/`atomic_fence`

**What it CANNOT express**:
- `@{...}` antiquote splices (explicitly rejected)
- Reference to Lua values (no closure or binding mechanism)
- Function/region/expr/struct/union/extern *declarations* (only statements)
- Type annotations in the snippet must be literal type names that are visible at parse time (no host type values)
- The snippet form is a pure string parse — there's no mechanism to pass bindings, so names like `x` must exist in the surrounding Lalin scope at the splice site

**The relationship to the full parser**: Same `parse_stmt`, same `Parser` machinery, same lexer. The difference is:
1. No `scan_document` island wrapping → no `splice_values` map passed as parser opts
2. Explicit rejection of holes
3. No name_hint inference from Lua assignment
4. Different outer calling context (no protocol_types tracking, no region_scope)

### Path C: Builder API

The builder API is spread across `host_func_values.lua`, `host_region_values.lua`, `host_fragment_values.lua`, `host_expr_values.lua`, `host_type_values.lua`, `host_struct_values.lua`, `host_module_values.lua`, `host_decl_values.lua`.

The primary entry `api.stmts()` has overloaded signatures:

```lua
-- Form 1: Source string
lalin.stmts "let x: i32 = 0; return x"

-- Form 2: Bindings table + builder function
lalin.stmts({ x = lalin.i32 }, function(b)
    local x = b:param("x")
    local y = b:let("y", lalin.i32, x + 1)
    b:return_(y * 2)
end)

-- Form 3: Builder function only (no bindings)
lalin.stmts(function(b)
    b:return_(lalin.int(42))
end)

-- Form 4: Pass-through existing statement list (detected by ASDL classof)
lalin.stmts(existing_stmt_array)
```

**Full `FuncBuilder` surface** (`host_func_values.lua` lines ~140-280):
- `b:param(name)` — expression value for an existing binding
- `b:let(name, ty, init)` — `let` binding, returns expression value
- `b:var(name, ty, init)` — `var` binding, returns expression value
- `b:set(place, value)` — assignment
- `b:if_(cond, then_fn, else_fn?)` — if statement
- `b:switch_(value, arms, default_fn?)` — switch statement
- `b:emit(fragment, runtime_args, fills)` — region emit
- `b:use_region(fragment, args, fills)` — alias for emit
- `b:jump(target, args)` — jump statement
- `b:yield_(expr?)` — yield
- `b:return_(expr?)` — return
- `b:expr(expr)` — expression statement
- `b:atomic_store(addr, value, ty)` — atomic store
- `b:atomic_fence()` — atomic fence
- `b:place(name)` — place value from binding

**Full `BlockBuilder` surface** (`host_region_values.lua` lines ~130-230):
Same as FuncBuilder minus `let`/`var`/`set`/`place`, plus:
- `block:jump(target, args)` — accepts BlockValue or ContValue targets
- `block:emit(fragment, args, fills)` — region emit with fill validation against fragment's declared continuations
- `block:return_(expr?)` / `block:yield_(expr?)`
- `block:if_(cond, then_fn, else_fn?)` / `block:switch_(value, arms, default_fn?)`

**Full `RegionBuilder` surface** (`host_region_values.lua` lines ~232-300):
- `region:entry(name, params, body_fn)` — defines entry block
- `region:block(name, params, body_fn)` — defines additional block
- `region:block_decl(name, params)` — declares a block without body (body set later via `block:body_fn(fn)`)
- `region:param(name)` — access to open param as expression value
- RegionBuilder `__index` fallback: accesses `self.bindings[name]` (open params), then `self.conts[name]` (continuation values)

**What the builder enables that the other paths can't**:
1. **Loops in code generation** — Lua `for`/`while` to emit statements (`for i = 1, N do b:emit(...) end`)
2. **Conditional generation** — Lua `if` to decide which statements to emit
3. **Lua values embedded in expressions** — via operator overloads on ExprValue: `x + 1` where `x` is ExprValue, `1` is coerced to ExprValue
4. **Lua values embedded in types** — `lalin.ptr(lalin.i32)` constructs ASDL type nodes
5. **Type-polymorphic code generation** — `lalin.struct_template` with type params
6. **Combined source + builder** — mix `lalin.stmts [[...]]` with builder-generated parts via `@{...}` spread
7. **Fragment reuse with dependency tracking** — `region_frag_value`/`expr_frag_value` track deps for correct compilation order
8. **Explicit extern symbol binding** — `M:symbol(name, ffi.cast(...))`
9. **Cross-function reference** — module builder supports mutual recursion
10. **Atomic operations** — `lalin.atomic_load()`, `lalin.atomic_store()`, etc. produce ASDL nodes directly

### The `@{}` antiquote / splice system

**Lexer handling** (`parse.lua` lines ~180-270):
- `@{` in source triggers `scan_antiquote()` which finds matching `}`, handling nesting and strings
- `@{...}` → creates a `TK.hole` token with `splice_id` like `"splice.1"`
- `@{...}` spread form detected when Lua expr ends with `...` → `t.splice_spread[id] = true`
- Splice text stored in `t.splice_map[id]` = `lua_expr`

**Parser splice positions** — every position creates a different `LalinOpen.Slot*` variant:

| Position in source | Parser action | Slot type | Role string |
|---|---|---|---|
| Type position (`@{T}`) | `self.O.TypeSlot(...)` → `O.SlotType(slot)` | `O.SlotType` | `"type"` |
| Expression position (`@{val}`) | `self.O.ExprSlot(...)` → `O.SlotExpr(slot)` | `O.SlotExpr` | `"expr"` |
| Statement/body (`@{stmts}`) | `self.O.RegionSlot(...)` → `O.SlotRegion(slot)` | `O.SlotRegion` | `"region_body"` |
| Emit target (`emit @{frag}(...)`) | `self.O.RegionFragSlot(...)` → `O.SlotRegionFrag(slot)` | `O.SlotRegionFrag` | `"region_frag"` |
| Emit-expr target (`emit expr @{frag}(...)`) | `self.O.ExprFragSlot(...)` → `O.SlotExprFrag(slot)` | `O.SlotExprFrag` | `"expr_frag"` |
| Name (`func @{name}(...)`) | `self.O.NameSlot(...)` → `O.SlotName(slot)` | `O.SlotName` | `"name"` |
| Spread in expr list `f(@{args...})` | `self:spread_expr_slot("expr_list", id)` → `O.SlotExpr` | `O.SlotExpr` | `"expr_list"` |
| Spread in type list `func(@{types...})` | `self:spread_type_slot("type_list", id)` → `O.SlotType` | `O.SlotType` | `"type_list"` |
| Spread in param list `func(@{params...})` | `self:spread_region_slot("param_list", id)` → `O.SlotRegion` | `O.SlotRegion` | `"param_list"` |
| Spread in field list `struct @{fields...}` | `self:spread_region_slot("field_list", id)` → `O.SlotRegion` | `O.SlotRegion` | `"field_list"` |
| Spread in variant list `union @{variants...}` | `self:spread_region_slot("variant_list", id)` → `O.SlotRegion` | `O.SlotRegion` | `"variant_list"` |
| Spread switch stmt arms | `self:spread_region_slot(...)` | `O.SlotRegion` | `"switch_stmt_arm_list"` |
| Spread switch expr arms | same pattern | `O.SlotRegion` | `"switch_expr_arm_list"` |
| Spread open params `region(@{params...})` | `self:spread_region_slot("open_param_list", id)` | `O.SlotRegion` | `"open_param_list"` |
| Spread block params `block(@{params...})` | `self:spread_region_slot("block_param_list", id)` | `O.SlotRegion` | `"block_param_list"` |
| Spread entry params `entry(@{entry_params...})` | `self:spread_region_slot("entry_param_list", id)` | `O.SlotRegion` | `"entry_param_list"` |
| Spread conts `region(...; @{conts...})` | `self:spread_region_slot("cont_slot_list", id)` | `O.SlotRegion` | `"cont_slot_list"` |
| Spread blocks after entry | `self:spread_region_slot("control_block_list", id)` | `O.SlotRegion` | `"control_block_list"` |

**Slot filling** is handled by `host_splice.lua`:
- `M.fill(session, slot, value, site, role, spread)` dispatches by role string or by `Slot` subclass
- Each role has a dedicated filler: `fill_type`, `fill_expr`, `fill_expr_list`, `fill_type_list`, `fill_param_list`, `fill_field_list`, `fill_variant_list`, `fill_switch_stmt_arm_list`, `fill_switch_expr_arm_list`, `fill_open_param_list`, `fill_block_param_list`, `fill_entry_param_list`, `fill_cont_slot_list`, `fill_control_block_list`, `fill_region_body`, `fill_region_frag`, `fill_expr_frag`, `fill_name`
- Fillers accept typed host values (TypeValue, ExprValue, ParamValue, FieldSpec, Raw ASDL nodes, primitives for expr slots, etc.)
- All fillers produce `O.SlotBinding(slot, O.SlotValue*)` wrappers

**Host bridge** (`mlua_run.lua` lines ~425-530):
- `.mlua` load → `scan_document` → generate carrier Lua code
- For each island, closures are built for each `@{lua_expr}` plus ambient names
- Closures evaluated via pcall → values stored in `luamap[id] = {present = true, value = val}`
- Parsed island's `splice_slots` are iterated → `Splice.fill(session, slot.slot, rec.value, ...)`
- Resulting bindings fed into `Expand.env_with_fills(env, bindings)` for expansion

### ASDL bridge / PVM layer

The PVM layer (`pvm.lua`) provides:
- `pvm.context()` — creates a GC-backed ASDL type system (the `T` object)
- `pvm.classof(node)` — returns the ASDL class metatable
- `pvm.with(node, overrides)` — structural update preserving sharing

The builder API (`host_session.lua`) creates or accepts a `T` context. All builder methods construct ASDL values within this context using the `T.Lalin*` class constructors. The host values are then wrapped in Lua metatables (`TypeValue`, `ExprValue`, `FuncValue`, `RegionFragValue`, etc.) but the *semantic payload* is always the ASDL node.

**There is no impedance mismatch.** Builder-constructed ASDL values and parser-constructed ASDL values are the same classes from the same `T` context. The only difference is metadata attached by the Lua wrapper objects (e.g., `TypeValue.source_hint`, `ExprValue.type`). Both produce identical `LalinTree.Stmt[]`, `LalinTree.Func`, `LalinOpen.RegionFrag`, etc.

### The `parse_stmts` vs full parser relationship

`parse_stmts` uses `parse_stmt_string()` (parse.lua line ~2325):
```lua
function M.parse_stmt_string(T, src, opts)
    local toks = M.lex(src)                    -- standalone lex, no island
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    local stmts = p:parse_stmt_until({})        -- same parse_stmt_until
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("...") end
    return { kind = "stmt_list", value = stmts, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end
```

Key difference from full `.mlua` parsing:
1. **No scan_document** — standalone lex, not island-aware
2. **No name_hint inference** — no Lua assignment scanning
3. **No fragment registration** — no `region_frags[name]`/`expr_frags[name]` side tables
4. **No protocol_types** — no union→protocol mapping
5. **No splice_values** — no `splice_values` map in opts, so holes CANNOT be resolved during parse
6. **BUT** — `parse_stmt_until` and `parse_stmt` are the *same functions*, so the snippet CAN produce `Slot*` nodes if `@{...}` appears in the source. The `host_func_values.lua` wrapper catches this and rejects it (`if #parsed.splice_slots ~= 0 then error(...)`).

**Why it rejects `@{}` explicitly**: Because the parse produces slots but there's no host bridge available to fill them — `parse_stmt_string` returns `splice_slots` but the snippet call site has no mechanism to bind Lua values to those slots. The builder form is the recommended alternative.

### Real usage patterns from tests

**Pattern 1: Module builder (most common in benchmarks, tests)**
```lua
local M = lalin.module("Demo")
M:export_func("add", {lalin.param("a", lalin.i32), lalin.param("b", lalin.i32)},
    lalin.i32, function(fn)
    fn:return_(fn.a:add(fn.b))
end)
```
Used in: `bench_both.lua`, `bench_frontend_speed.lua`, `test_direct_mutual_recursion.lua`, `test_host_extern_symbol.lua`, `test_host_template_values.lua`

**Pattern 2: `.mlua` source islands with `@{}` (most expressive)**
```lua
local args = { 20, 22 }
local add = func add(a: i32, b: i32) -> i32
    return a + b
end
local main = func main() -> i32
    return add(@{args...})
end
```
Used in: `test_spread_splice_lists.lua`, `test_spread_splice_regions.lua`, `test_host_metaprogramming_patterns.lua`, `test_region_frag_runtime_param_call.lua`

**Pattern 3: `lalin.stmts` snippet (simple constant bodies)**
```lua
local source_body = lalin.stmts [[
    let z: i32 = x + 2
    return z * 2
]]
local h = func h(x: i32) -> i32
    @{source_body...}
end
```
Used in: `test_host_stmt_list_builder.lua`

**Pattern 4: `lalin.stmts` builder form (loops/generated code)**
```lua
local body = lalin.stmts({ x = lalin.i32 }, function(b)
    local x = b:param("x")
    local y = b:let("y", lalin.i32, x + 1)
    b:return_(y * 2)
end)
```
Used in: `test_host_stmt_list_builder.lua`, `bench_frontend_speed.lua`

**Pattern 5: Factory functions generating named fragments (most metaprogramming-heavy)**
```lua
local function expect_byte(full_name, byte, err_code)
    return region @{full_name}(p: ptr(u8), pos: i32;
        ok: cont(next: i32), fail: cont(pos: i32, code: i32))
    entry start()
        if as(i32, p[pos]) == @{byte} then jump ok(next = pos + 1) end
        jump fail(pos = pos, code = @{err_code})
    end
    end
end
```
Used in: `test_host_metaprogramming_patterns.lua`

**Pattern 6: Pure builder regions (no source at all)**
```lua
local region_body = lalin.stmts({ n = lalin.i32 }, function(b)
    b:yield_(b:param("n") + 5)
end)
```
Used in: `test_host_stmt_list_builder.lua`

**Pattern 7: Control blocks with builder** (bench_frontend_speed.lua)
```lua
b:block(lalin.control_block("loop",
    {lalin.param("i", lalin.i32, i), lalin.param("acc", lalin.i32, acc)},
    lalin.stmts(function(b2)
        ...
    end)))
```

---

## Relationships

### Data flow for `.mlua` source

```
Source text
  → scan_document(src)          [parse.lua:1700-1980]
    → tokenize_island()          [parse.lua:1560-1700]
      → M.lex() for each island  [parse.lua:75-360]
  → carrier Lua code generation [mlua_run.lua:500-820]
    → quote.lua hygienic generation
    → per-island eval_island() closures
  → Runtime:eval_island()        [mlua_run.lua:370-530]
    → Evaluate closures → luamap
    → ParseApi.parse_island()    [parse.lua:1990-2100]
      → new_parser_internal() → parse_func/parse_region_frag/etc
      → Returns parsed with splice_slots[]
    → host_splice.fill() per slot  [host_splice.lua:50-420]
      → dispatch by role → create SlotBinding
    → Expand.env_with_fills()     [open_expand.lua]
    → Expand.expand_*()           [open_expand.lua]
    → Wrap result as host value
      → RegionFragValue / FuncValue / ExprFragValue / TypeValue
```

### Data flow for builder API

```
Lua code (require("lalin"))
  → lalin.stmts / lalin.module / lalin.region_frag / etc.
  → host_*_values.lua constructors
  → Direct ASDL node construction in T context
  → Wrap in host value metatables (TypeValue, ExprValue, FuncValue, etc.)
  → ModuleValue:compile() / FuncValue:compile()
    → ModuleValue:to_asdl() → Tr.Module
    → frontend_pipeline.lower_module()
    → back_jit / back_object
```

### How `lalin.stmts[[...]]` snippet data flows

```
String source
  → parse_stmt_string()         [parse.lua:2325]
    → M.lex(src)                (standalone lex)
    → parse_stmt_until({})      (same parser, same functions)
    → Returns stmts[] + splice_slots[]
  → host_func_values.lua wrapper
    → Checks splice_slots == 0  (rejects @{})
    → Returns stmt array
  → Spread via @{stmts...} into surrounding source
```

### Call chain for splice expansion

```
Parser creates Slot* nodes during parse_island
  → Stored in p.splice_slots[] array
  → Each entry: { splice_id, slot=SlotType/Expr/Region/RegionFrag/etc., role="type"/"expr"/..., spread }

Runtime evaluation:
  → eval Lua closure for each splice_id
  → host_splice.fill(session, slot, value, site, role, spread)
    → M.fill() dispatches by slot's ASDL class or explicit role string
    → Role-specific filler creates SlotBinding(Slot, SlotValue*)
  → Expand.env_with_fills(env, bindings) registers bindings
  → Expand.expand_*(node, env) traverses ASDL tree
    → When it hits a TSlot/ExprSlotValue/etc. with matching fill → substitutes configured value
    → When it hits a spread slot → expands array elements in-place
  → Cleaned AST (no more Slot/SlotValue nodes) → proceeds to typechecking
```

---

## Observations

### Friction points

1. **No `@{}` in `lalin.stmts` snippets**: The most visible constraint. The error message is explicit: `"lalin.stmts string snippets do not evaluate @{} splices; pass values with builder form or splice outside with @{...}"`. This means you can't nest splices inside snippets — you must either use the builder form, or define the snippet as a separate `.mlua` region and reference it. This creates a choice point where the user must switch mental models mid-task.

2. **Name binding gap with builder**: When using `lalin.stmts(bindings, fn)`, bindings are strings → ExprValue references. But `b:let()` generates fresh ASDL `Binding` objects with generated IDs. If you need to refer to an outer binding by name, you use `b:param(name)` or `lalin.ref()`. The discipline is clean but has a subtlety: `b:let()` returns an ExprValue that can be used in the builder, but if you spread the result into a source island with `@{body...}`, the generated names (like `y`) are NOT `lalin.ref("y", ...)` — they have ASDL Binding IDs (`"local:stmt_list:y"`). This works correctly because the typechecker resolves both `ValueRefBinding` and `ValueRefName`, but it means the user can't intuitively know which names will be visible at the splice site.

3. **Three forms of `lalin.stmts` with different semantics**: (a) string → parsed source (no splice support), (b) table+builder → procedural construction, (c) table of ASDL nodes → pass-through. The string form is the most ergonomic for simple cases but has the most constraints. The builder form is the most flexible but requires the most boilerplate.

4. **Fragment naming conventions**: Factory functions that generate region fragments must generate unique names (`expect_A`, `expect_B`). The standard pattern is Lua concatenation: `local name = "expect_" .. string.char(byte)`. There's no automatic hygienic naming for generated fragments.

5. **String as source-name escape**: For pragmatic cases, raw strings are accepted in type/name/fragment positions as "explicit complete Lalin source/name fragments." This is an escape hatch that bypasses the ASDL typing. `LANGUAGE_REFERENCE.md` section 14.3 explicitly documents this: "strings are treated as explicit complete Lalin source/name fragments, not as quoted string literals."

6. **The `lalin.ast` low-level API vs `lalin.host` high-level API**: Both produce identical ASDL values. `ast.lua` is the bare constructor (no session, no name generation, no wrappers). `host.lua` adds session management, automatic name generation, host value registration, and compilation. The documentation says "Choose based on preference and task."

7. **Impedance between string and builder approaches**: When a user starts with `lalin.stmts [[...]]` and then needs to parameterize it, they must switch to the builder form or the `@{...}` spread pattern. The two forms can be mixed (builder-produced values spread into source islands), which is powerful but requires understanding the spread mechanism.

### Which pattern dominates

Based on the test corpus:
- **Source islands with `@{...}`** is the most expressive and most common for complex metaprogramming (factory functions, type-specialized fragments, parameterized regions).
- **Module builder** (`M:export_func(...)`) dominates for simple standalone functions and benchmarks.
- **`lalin.stmts` snippet** is used sparingly, mainly for small constant bodies.
- **`lalin.stmts` builder form** appears in benchmarks and when loops/conditionals are needed in code generation.
- **Pure builder regions** (no source) appear only in the stmt_list_builder test.

### What the doc says about the three paths

From `LANGUAGE_REFERENCE.md` section 16 (Metaprogramming and composition guide):

> "This is the preferred alternative to string concatenation. Strings remain useful for small source snippets (`lalin.stmts [[...]]`) and generated names, but program meaning should live in typed values: types, expressions, params, fields, statements, fragments, regions, blocks, and modules."

> "Snippet strings are parsed as Lalin statements. They are a containment tool for source-shaped code, not an invitation to concatenate whole functions. Prefer builder form for loops, conditional generation, and insertion of Lua values."

### The `lalin.ast` module

The low-level `ast.lua` (1060 lines) provides direct constructors for all ASDL nodes:
- `ast.type.{void, bool, i32, ...}` → scalar types
- `ast.type.ptr(T)` → pointer type
- `ast.expr.{lit_int, lit_bool, lit_float, lit_string, lit_nil, ref, call, binary, unary, ...}`
- `ast.stmt.{let, var, if_, switch_, return_value, return_void, jump, yield, emit, ...}`
- `ast.func.{local, export, extern}`
- `ast.module.{new, add_item}`
- `ast.region_frag.new(...)`, `ast.expr_frag.new(...)`
- `ast.struct.new(...)`, `ast.union.new(...)`

All constructors take explicit field-by-field params and return plain ASDL nodes — no metatables, no session, no registration. This is the "raw metal" path that the higher-level `host_*` API wraps.

## Knowledge-builder Output — 2026-05-19 07:58:28

Now I have the complete picture. Here is the deep analysis:

---

## What Matters Most for This Problem

1. **Evaluation order synchronization** — `.mlua` carrier closures evaluate at a specific point in the runtime lifecycle. Snippets are called at Lua evaluation time. These are *different times* and the gap has structural consequences.

2. **Slot binding model** — `Slot*` nodes created by the parser must be paired with `SlotValue*` nodes. The pairing happens either via `host_splice.fill()` (full pipeline) or implicitly if values are resolved eagerly. The resolution strategy determines the entire implementation shape.

3. **Spread compatibility** — The existing `@{body...}` spread receives statements as raw `LalinTree.Stmt[]` and feeds them into a `SlotValueRegion` at the **receiving** island's expansion. Snippet-originating slots must survive the spread or be resolved before it.

4. **Scope capture hygiene** — `@{...}` in snippets would need access to Lua values. Different from the `.mlua` path where carriers capture their enclosing Lua environment.

5. **API stability** — `lalin.stmts` already has four overloads. Adding splice support adds a fifth and creates a namespace collision with the binding-table form.

---

## Non-Obvious Observations

### 1. There Are Three Evaluation Moments, Not Two

The `.mlua` path has: T1 (carrier closure construction) → T2 (closure evaluation, producing values in `luamap`) → T3 (expansion, resolving slots from fills). The snippet path would need to decide where T2 happens relative to the call to `lalin.stmts[[]]`.

But there's a third moment the scout missed: **T0 — the snapshot of the Lua environment at snippet construction time.** In `.mlua`, `@{x}` captures the variable `x` from the enclosing Lua scope via a closure. In a snippet `lalin.stmts[[]]`, there's no closure — `x` is just the text `"x"` stored in `t.splice_map["splice.1"]`. To evaluate `x`, you'd need to either:

1. **Pass it explicitly**: `lalin.stmts("let z = @{x}", { x = 42 })` — values provided at the call site
2. **Capture it implicitly**: Use `debug.getlocal` or equivalent to snapshot the caller's Lua stack at T0 — fragile, slow, and wrong in LuaJIT
3. **Generate a closure**: Use `load("return " .. text)` at T1 — but this evaluates arbitrary Lua text in the *snippet*'s scope, not the *caller's* scope

**Hidden constraint**: Option 1 is the only safe approach, but it means the user must manually thread values. This is exactly what they do with the builder form anyway. The splice advantage over the builder form is dramatically reduced if you must still pass values in a table.

### 2. The Rejection Is Deeply Conservative, Not Incidental

The current error says: *"lalin.stmts string snippets do not evaluate @{} splices; pass values with builder form or splice outside with @{...}"*

The second option — "splice outside with @{...}" — is the **architecturally pure** recommendation. It means: use the snippet for boilerplate that doesn't vary, and use the `@{...}` spread at the *outer* island level for parameterization. This creates a clean separation:

- Snippets are self-contained, resolved statement arrays
- `@{...}` is the responsibility of the enclosing `.mlua` island, which has the full carrier mechanism

If you enable `@{...}` inside snippets, you're blurring this boundary. The snippet is now *both* a resolved statement template *and* a carrier of unresolved slots. Its return type is no longer pure `Stmt[]` — it's `Stmt[] | (Stmt[] + deferred fills)`.

### 3. The Slot Key Namespace Gap Makes Lazy-Nested Resolution Impossible

This is the most important non-obvious insight. Consider:

```lua
local body = lalin.stmts [[          -- snippet.1 parse: creates slot with key "region_body:splice.1"
    let z = @{val}                  -- creates slot with key "expr:splice.2"
    return z
]]

-- In an .mlua island:
func f(x: i32) -> i32
    @{body...}                       -- outer island spread: creates slot with key "region_body:splice.3"
end
```

The spread `@{body...}` creates a `SlotRegion` in the *outer* island's parse, with key `"region_body:splice.3"` (or similar). The *inner* stash from the pre-resolved statement at `let z = @{val}` has key `"expr:splice.2"`. These are **different key spaces** — they come from different invocations of `parse_stmt_string`.

When the outer island expands, `open_expand` resolves `"region_body:splice.3"` by looking up the slot in `env.fills`. If it finds a `SlotValueRegion` containing the previously-parsed body, it recursively expands those stmts. But when it hits `ExprSlotValue("expr:splice.2")` inside the body, it looks up *that* key in `env.fills` — and fails, because the fill for `"expr:splice.2"` was never added to the outer environment.

**The only way to fix this**: Either:
- (a) Resolve all inner slots eagerly at snippet call time, so the returned stmts contain zero slots — making the snippet a fully baked `Stmt[]`
- (b) Attach the snippet's fills to the returned value (e.g., as a metatable or extra field) and have the expander merge them into the outer env when it encounters a spread — requiring changes to `open_expand`
- (c) Re-key the inner slots to use unique IDs that survive into the outer parse space — but this is fragile because slot IDs are generated during parse, not during spread

**Option (a) is the simplest but most constraining** — it means `@{val}` in a snippet cannot reference anything from the *expansion* site. It can only reference values available at the snippet construction site. This kills the use case where `@{val}` should be an expression that makes sense in the enclosing island's scope (like a function parameter or a block label).

### 4. The Parser Already Has Eager Resolution via `splice_values` — But It's Incomplete

Look at lines 402-416 of parse.lua:

```lua
local function new_parser_internal(T, toks, first, limit, opts)
    ...
    splice_values = opts.splice_values or {},
    ...
```

And line 637-639:

```lua
function Parser:splice_value(id)
    local rec = self.splice_values and self.splice_values[id]
    if type(rec) == "table" and rec.present then return rec.value end
    return rec
end
```

The parser already **reads** splice values during parsing. This is used in the `.mlua` pipeline (`parse_opts.splice_values = luamap` at mlua_run.lua line 478). But the parser only uses this for **spread** positions (line 1587: `local value = self:splice_value(id)` in `parse_region_frag`).

For **non-spread** holes (expression, type, name, statement positions), the parser creates `Slot*` nodes regardless of whether a value is available. It never substitutes the value inline. The substitution happens later in `host_splice.fill()` + `open_expand`.

**This is an architectural invariant**: The parser produces *open* AST nodes with explicit slots. The host bridge fills those slots with typed values. The expander substitutes them. Eager resolution at parse time would require the parser to also *evaluate* — which would be a deep change to the parser's role.

### 5. The `parse_stmt_string` Function Already Handles Holes — It Creates the Right Slots

The critical finding: `parse_stmt_string` calls `parse_stmt_until({})` which calls `parse_stmt()` which at line 1401-1406 encounters `TK.hole` and creates `StmtUseRegionSlot`. The slot nodes are structurally identical to what the full `.mlua` parser produces. The only differences are:

1. The `splice_values` map is empty, so the parser can't eagerly resolve (not that it would)
2. No `splice_values` → no `luamap` → no type resolution via `type_name()` check at line 658 (it checks `self:splice_value(name)` for *any* name, not just `@{...}`)
3. The calling context has no session, no carrier, no expansion env

**So the minimal implementation surface really is**: thread a values table through `parse_stmt_string` → `new_parser_internal` → and then do what `eval_island` does: fill slots → build expansion env → expand. The difference is that `eval_island` has access to the runtime (for deps, fragment registration, etc.), which the snippet path doesn't need.

### 6. The "Write a Switch Arm" Use Case Exposes the Scope Problem

The user's example:

```lua
local arms = {}
for i, key in ipairs(keys) do
    arms[i] = lalin.switch_arm(key, lalin.stmts [[
        jump handler_@{key}()
    ]])
end
```

For this to work with eager resolution, `@{key}` would need to capture `key` at each loop iteration. With the explicit-values approach, this would be:

```lua
arms[i] = lalin.switch_arm(key, lalin.stmts("jump handler_@{name}()", { name = key }))
```

This is actually **less concise** than the builder form:

```lua
arms[i] = lalin.switch_arm(key, lalin.stmts(function(b)
    b:jump("handler_" .. key, {})
end))
```

Wait — but the builder form also has a problem here. `b:jump` expects either a BlockLabel string or a block-like table, with `jump_args` as the second arg. The `b:jump("handler_" .. key)` is actually string concatenation doing the work, not the jump mechanism being parametric.

The splice form `lalin.stmts("jump handler_@{name}()", { name = key })` is barely shorter than `lalin.stmts(function(b) b:jump("handler_" .. key, {}) end)`. The advantage of the splice form is **readability** — the control flow is visible in the source-shaped text. The disadvantage is the **dual-input** pattern (string + values table) which is another thing to learn.

### 7. Expression Splices Inside Snippets Have No Coercion

The `host_splice.fill()` for expressions (host_splice.lua lines 106-150) does extensive type coercion:

```lua
-- Primitive Lua values → literal ASDL nodes
if tv == "number" then
    if value == math.floor(value) and value >= -2^31 and value < 2^31 then
        expr = Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(math.floor(value))))
    else
        expr = Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(value)))
    end
elseif tv == "boolean" then
    expr = Tr.ExprLit(Tr.ExprSurface, C.LitBool(value))
...
```

If a naive implementation resolves `@{42}` by simply `load("return 42")()` and plops the raw number into the AST, it **won't work** because the number `42` is not an ASDL node. You need `host_splice`'s coercion logic whether you go eager or lazy.

**This means any implementation must call `host_splice.fill()` (or equivalent logic) for each `@{...}` in the snippet.** There's no shortcut via `loadstring` evaluation.

### 8. The `lalin.stmts` Multi-Form Overload Creates a Table Ambiguity

Currently:
- `lalin.stmts("source")` → parse
- `lalin.stmts({x=ty}, fn)` → builder with bindings
- `lalin.stmts(fn)` → builder only
- `lalin.stmts(existing)` → pass-through ASDL array

The natural addition: `lalin.stmts("source", {val=42, name="hello"})` → parse with values.

**The ambiguity**: What if someone writes `lalin.stmts({ x = 42 }, fn)` today? Currently this means "binding `x` of type... wait, `42` is a number, not a TypeValue — error." But if we add the two-arg string+table form, the table could be *either* bindings (for builder) or splice values (for snippet). The parser would need to disambiguate based on the first arg's type (string vs table), which it already does. However, the error messages would become confusing: "expected TypeValue for binding x, got number" might look like a bug in the splice handler.

**More subtly**: The third form `lalin.stmts({x=lalin.i32}, fn)` and the potential splice form `lalin.stmts("source", {x=lalin.i32})` could both be called with the same second argument type. A user who confuses the argument order would get a confusing error.

### 9. The Existing Workaround Is Actually Architected Correctly

The error message suggests: "splice outside with @{...}". This pattern exists in `test_host_stmt_list_builder.lua`:

```lua
local body = lalin.stmts({ x = lalin.i32 }, function(b)
    local x = b:param("x")
    b:return_(x * 2)
end)

local h = func h(x: i32) -> i32
    @{body...}
end
```

The builder produces the parametric stmts. The source island consumes them via spread. This is **two layers of metaprogramming**: Lua at the outer level (builder), Lalin at the inner level (source). The separation means each layer is self-contained and independently testable.

Enabling `@{...}` in snippets would create a **hybrid** path: the snippet is a Lalin source string *with* Lua evaluation holes, parsed by the Lalin parser but evaluated by the Lua runtime. This is neither pure source (because some meaning is in Lua) nor pure Lua (because the structure is Lalin). It's the same hybrid as `.mlua` islands — which is fine — but it adds a third path to a system that already has two well-understood paths with different tradeoffs.

### 10. The `lalin.ast` Low-Level Path Is Unaffected — And That's Important

The `ast.lua` constructor API (`ast.stmt.{let, var, if_, ...}`) constructs bare ASDL with no slot support. It's completely orthogonal to `@{...}`. The splice facility only exists in the parser, in `host_splice`, and in `open_expand`. This means:
- If you use `ast.lua` directly, you can't use `@{...}` anyway — you construct nodes by hand
- The `ast.lua` path doesn't need changes
- The host_values path (`lalin.*` API) does need changes because `api.stmts()` is the entry point

### 11. Statement-Level `@{...}` vs Expression-Level `@{...}` Have Different Expansion Consequences

Look at what the parser produces for different `@{...}` positions:

**Statement position** (line 1401-1406): `Tr.StmtUseRegionSlot(Tr.StmtSurface, slot)` — this is a *statement wrapper* around a slot. When expanded, the `StmtUseRegionSlot` handler (open_expand.lua line 860-866) looks up the slot and expands its body as statements. The body is a `Stmt[]` array.

**Expression position** (line 808-811): `Tr.ExprSlotValue(Tr.ExprSurface, slot)` — this is an *expression wrapper* around a slot. When expanded, the `ExprSlotValue` handler replaces the slot with the expression from the fill.

**Critical difference**: `StmtUseRegionSlot` is a *container* that holds other statements. `ExprSlotValue` is a *leaf* that is replaced by a single expression. This means:

- If a snippet uses `@{...}` in statement position (e.g., `@{body...}` or a single `@{stmt}`), the result of resolving that slot is a **statement array** that gets spliced into the surrounding statement list
- If a snippet uses `@{...}` in expression position (e.g., `let x = @{val}`), the result is a **single expression** that replaces the slot

Both are handled by the expander, but the expander's spread mechanism only handles statement-level spreads via the `StmtUseRegionSlot` → `SlotValueRegion` path. For expression-level slots, there's no spread — it's a single-value substitution. This means **`
`lalin.stmts([[let x = @{vals...}]]` would not work** as a spread of multiple expressions — spread in expression position is already handled at the call-site level by the `parse_expr` call path in the outer island, not by the expander.

### 12. The `new_parser_internal` Debug Info Gap

When `parse_stmt_string` creates a parser, it doesn't set a meaningful `name_hint` or file information. The `name_hint` (line 418) defaults to nil. The `region_scope` (line 428) is auto-generated from token positions. This means:

- Error messages from snippet parsing will say "=(parse_stmt)" or similar
- Source maps won't point back to the Lua file where the snippet was written
- Diagnostic spans will be byte offsets in the snippet string, not in the `.mlua` file

In the `.mlua` pipeline, `line_starts` and `SourceMap` provide rich diagnostics. Snippets would lose this unless you explicitly pass the Lua source location — which LuaJIT's `debug.getinfo` can provide, but only if you're careful about stack depth.

---

## Knowledge Gaps

1. **How does `lalin.switch_arm(key, body)` currently handle string bodies?** The code at line 394-396 of host_func_values.lua calls `parse_stmt_snippet(body)` when body is a string. If that string contains `@{...}`, it errors. But what about `lalin.stmts` called with a string directly (not inside `lalin.switch_arm`)? Same rejection. I'd need to verify all call sites of `parse_stmt_snippet` and `parse_stmt_string` to find every interception point.

2. **Does the expander's `expand_stmts` function handle `StmtUseRegionSlot` at any nesting depth?** I saw it does for the top level (open_expand line 860-866), but what about stmts nested inside `if` bodies, `switch` arms, or `control_block` bodies? The expander processes those via `expand_stmt` → `StmtUseRegionSlot`, which should work recursively. But I should verify there's no depth limit or recursion guard.

3. **What happens when a lazy snippet's slots are spread into an island that also has its own `@{...}` slots?** Could the slot IDs collide? The splice key includes the splice counter from the lexer, which is independent per parse invocation. So a snippet parse and an island parse have separate counters, meaning no collision — but the slot *key strings* would be distinct, so the expander's `slot_value()` lookup would never match them. This confirms the key-namespace gap I identified above.

## Approach-proposer Output — 2026-05-19 08:07:40

Now I have all the details I need. Let me formulate three distinct approaches.

---

### Approach A: Lazy Snippet Islands

- **Core idea**: `lalin.stmts[[ @{x} ]]` returns a *lazy fragment* (slot-ridden AST + capture closures), not a resolved `Stmt[]`. The return value's `@{x}` slots are resolved only when the snippet is *spread into an outer island* via `@{...}`, at which point the outer expansion environment merges with the snippet's captured closures.

- **Key changes**:
  1. **`host_func_values.lua` — `parse_stmt_snippet`**: Instead of rejecting `@{}`, accept it. The return type changes from `Stmt[]` to a new host value type `SnippetValue` (or reuse `ExprFragValue`-like wrapper) that carries: slot-ridden `Stmt[]`, captured closures per slot ID, and a `splice_slots` array identical to what `eval_island` produces.
  2. **`host_splice.lua` — new filler**: `M.fill_snippet(slot, snippet_value, ...)` creates a `SlotValueRegion` whose body is the snippet's stmts *plus* a merged fill env that resolves the snippet's inner slots. This is the key novelty: when the outer expander hits `StmtUseRegionSlot`, it expands the snippet's stmts with an env that has both outer fills and inner fills.
  3. **`open_expand.lua` — `StmtUseRegionSlot` handler**: Modified so that when a slot's `SlotValueRegion` carries attached inner fills, those are merged into the expansion env. The expander already does recursive expansion of slot bodies; it just needs the fills to be present.
  4. **`parse.lua` — `parse_stmt_string`**: No change needed — it already creates `Slot*` nodes. The rejection in `host_func_values` is the only barrier.
  5. **Carrier code generation**: `mlua_run.lua`'s `eval_island` machinery is replicated at the snippet call site. The snippet's `@{...}` expressions become closures capturing the local Lua scope.

- **How it works**:
  ```lua
  -- Inside an .mlua file:
  local body = lalin.stmts [[
      let y: i32 = @{val}
      return y * 2
  ]]

  -- When spread into an island:
  func f(x: i32) -> i32
      @{body...}
  end
  ```
  1. `lalin.stmts [[...]]` is parsed at Lua evaluation time (same as today) — the parser creates `ExprSlotValue` for `@{val}`, records `splice_slots = {{splice_id="splice.1", slot=SlotExpr(...), role="expr"}}`. The string source for `@{val}` is stored in the splice map.
  2. Instead of erroring, the function generates carrier-style closures capturing `val` from the local scope: `closures["splice.1"] = function() return val end`.
  3. The snippet returns a `SnippetValue` wrapping: the slot-ridden `Stmt[]`, the closures, and the full `splice_slots` array.
  4. When `@{body...}` in the outer island is expanded, the outer `Slotsplice.fill` for `region_body` calls a new filler that produces `SlotValueRegion(body = snippet_stmts)`. If the snippet has unresolved inner fills, these are attached as a `sub_env` on the `SlotValueRegion`.
  5. The expander's `StmtUseRegionSlot` handler checks for `sub_env`, merges it with the current `env`, and expands the body with the merged env. Inner `ExprSlotValue` nodes resolve against the merged env.

- **Tradeoff**: Optimizes for **uniform mental model** — the same lazy `@{}` semantics work in `.mlua` islands and `lalin.stmts` snippets. Sacrifices **simplicity of `lalin.stmts` return value** — it's no longer a plain `Stmt[]` you can inspect or pass around. You must spread it to evaluate it.

- **Risk**: **The key-namespace gap is real and critical.** The snippet's slots have keys like `"expr:splice.1"` (from its own parse), and the outer island's slots have keys like `"region_body:splice.3"` (from the outer parse). When the expander looks up `SlotExpr(slot)` in the merged env, it uses the snippet's `slot` object (which carries `splice.1`). This only works if the snippet's `slot` objects are copied into the outer fill env by identity, not by key string. **Solution**: the sub_env attached to `SlotValueRegion` must use the actual slot *objects* (the ones created during snippet parsing) as keys. The `slot_value()` lookup in `open_expand.lua` iterates bindings and matches by slot identity, so this works if the snippet's slot objects survive into the merged env. The risk is that `slot_value` uses reference equality on ASDL objects — if snippet parsing used a different `T` context, the slot objects won't match. **Mitigation**: enforce that snippet parsing uses the same session's `T` as the outer expansion.

- **Rough sketch**:
  1. In `host_func_values.lua`, add a new host value type `SnippetValue` that wraps: `{ stmts = Stmt[], splice_slots = {...}, closures = {...}, splice_map = {...} }`
  2. `parse_stmt_snippet` becomes `parse_stmt_snippet_lazy` — parses, records slots, returns the raw parsed result (don't check `#parsed.splice_slots ~= 0`)
  3. A new function `api.stmts_lazy(src)` generates carrier closures for each splice expression using `load("return " .. text)` (or better, uses a captured environment table passed at call time)
  4. In `host_splice.lua`, add `fill_snippet_body` — takes a `SnippetValue`, evaluates its closures with the current session, calls `fill` for each inner slot, produces a `SlotValueRegion` with a merged fill env
  5. In `open_expand.lua`, modify the `StmtUseRegionSlot` handler: after looking up the `SlotValueRegion`, check for a `sub_env` field. If present, create a merged env that layers the sub_env fills on top of the current env before expanding the body.
  6. Wiring: `host_func_values.lua` intercepts `lalin.stmts(bindings, fn)` with `type(bindings) == "string"` — if the string contains `@{`, use the lazy path instead of the string snippet path.

---

### Approach B: Lua-in-Source Blocks

- **Core idea**: Lalin source syntax gains `for/lua ... end` and `if/lua ... end` blocks that run Lua code at parse/expand time, producing Lalin AST sections. The builder API becomes unnecessary because iteration and conditionals live *in* the source.

- **Key changes**:
  1. **`parse.lua` — new token / syntax**: Add a `TK.lua_kw` token (or use `${...}` delimiters) that marks a Lua metaprogramming block. Inside a Lalin island:
     ```
     for/lua i = 1, N do
         let buf_${i}: i32 = 0
     end
     ```
     The parser recognizes `for/lua` as a special construct: it slurps the rest as a Lua expression, evaluates it (via `load` or host-provided function), and expects each iteration to produce `Stmt[]` or `Expr[]` via a host callback.
  2. **`mlua_run.lua` — new carrier phase**: Lua-in-source blocks generate carrier closures, same as `@{}` splices, but the closure returns a *fragment builder* callback rather than a value. The carrier calls this callback with a `FragmentBuilder` object that the user's Lua code uses to emit Lalin AST.
  3. **`host_fragment_values.lua` — `FragmentBuilder`**: A builder that operates *inside* a Lalin source construct. It's like the existing `FuncBuilder` but specialized for inline code generation: `fb:stmt(...)`, `fb:expr(...)`, `fb:let(...)`, etc. But the key difference from the builder API: the user writes this *inside* Lalin source, not as a separate Lua closure.
  4. **Alternative: `${}` expression escape**: A lighter-weight syntax for compute-time Lua values that produce AST:
     ```
     let x: i32 = ${ compute_threshold() }
     ```
     Here `${...}` is a Lua expression that runs at expand time and must return a Lalin expression (or a value coercible to one via `host_splice`).
  5. **`open_expand.lua` — new expander handlers**: For `ForLuaBlock` and `IfLuaBlock` AST nodes, the expander evaluates the Lua code and splats the result into the surrounding AST.

- **How it works**:
  ```lalin
  -- Region fragment with generated switch arms:
  region dispatch(val: i32, handlers: ptr(Handler), n: i32;
                  done: cont(result: i32))
  entry start()
      switch val do
          for/lua i = 0, n - 1 do
              case ${i}:
                  jump done(result = handlers[${i}].result)
          end
          default:
                  jump done(result = 0)
      end
  end
  end
  ```
  1. The parser encounters `for/lua i = 0, n - 1 do`. It recognizes this as a compile-time Lua loop.
  2. It parses the loop header: `i = 0, n - 1` is Lua. `n` is captured from the enclosing Lua scope (like `@{n}` captures).
  3. The loop body `case ${i}: jump done(...)` is parsed as Lalin source with `${i}` acting as a compile-time expression splice.
  4. The parser produces a new ASDL node `ForLuaBlock` that records: the Lua loop triplet `(var = start, end)`, the template body (slot-ridden statements), and captured closures for `n`, `i`, etc.
  5. During expansion, the `ForLuaBlock` handler evaluates the Lua loop: for each `i`, it fills `${i}` with the current integer, fills the body's slots with the captured values, expands, and collects all resulting `Stmt[]` into the parent statement list.

- **Tradeoff**: Optimizes for **eliminating the builder API entirely** — you never leave Lalin source, even for iteration. Sacrifices **language simplicity** — Lalin now has two execution modes (compile-time Lua and run-time Lalin) that look syntactically similar but behave fundamentally differently.

- **Risk**: **Semantic confusion is high.** `for/lua ... end` inside a Lalin island looks like it might be a runtime loop. Users will accidentally try to write runtime logic in Lua blocks. The compile-time vs runtime distinction is subtle and error-prone. **Mitigation**: Use distinct delimiters like `${for ...} ... ${end}` or `gfor ... do ... end` (with a `g` prefix for "generate"). But any visual distinction adds noise.

- **Rough sketch**:
  1. Add new `TK` values: `TK.for_lua`, `TK.if_lua`, `TK.lua_expr` (for `${...}`)
  2. In `parse.lua`, recognize `for/lua` at statement-start positions. Parse the Lua iteration expression (delegate to a Lua parser or text slurp with brace matching). Parse the body as Lalin stmts with `${...}` holes.
  3. Create ASDL node `Tr.ForLuaBlock(for_expr: string, body: Stmt[], captures: CapturedVars[])`
  4. In `open_expand.lua`, add `expand_for_lua_block`. It evaluates the `for_expr` Lua snippet (using captured values from the fill env), iterates, and for each iteration creates a fill env where `${...}` holes are resolved with the loop variable's value.
  5. Carrier code generation (`mlua_run.lua`): For each `for/lua`, generate carrier closures that capture the loop variable `n` (etc.) from the enclosing Lua scope.
  6. `${...}` in expressions: handled as a new expression node `Tr.ExprLuaSlot` that the expander evaluates via `host_splice.fill_expr` (reusing the coercion logic).

---

### Approach C: SlotValue Universal API

- **Core idea**: All three construction paths — `.mlua` islands, `lalin.stmts` snippets, and the builder API — produce the same thing: `SlotValue` trees that the standard expander resolves. The builder API is not retired but *transparently aligned*: `b:let(...)` constructs a `SlotValueExpr` wrapping a `Tr.StmtLet`, which is the exact same kind of node the parser produces for `let x = @{val}` after filling the slot. The user thinks in SlotValues regardless of path.

- **Key changes**:
  1. **`host_func_values.lua` — builder methods return SlotValues**: Currently, `b:let()` returns an `ExprValue` representing the binding (eagerly constructed). Change it to return a `SlotValueExpr` that wraps a deferred `Tr.StmtLet` with a `SlotExpr` for the initializer. The `ExprValue` wrapping the binding reference is only materialized when the slot is filled. This means the builder is *always lazy* — consistent with the parser's slot model.
  2. **`host_splice.lua` — unified dispatch for all paths**: The `fill()` function already handles all roles. Add a `fill_stmts` that takes a list of SlotValue-annotated stmts (from builder or parser) and resolves them in one pass. The same coerce-expand cycle.
  3. **`open_expand.lua` — new unified entry point**: `expand_stmts_with_values(stmts, slot_values, env)` — takes a mixed list of resolved stmts and slot-ridden stmts (produced by any path), fills slots from a slot_values table, and expands. This is the single point where all three paths converge.
  4. **Remove `parse_stmt_snippet`'s error on `@{}`**: Instead, if a snippet string contains `@{}`, it returns slot-ridden stmts that can be filled later via the unified entry point. The `lalin.stmts(string)` form returns slot-ridden stmts if `@{` is present, or resolved stmts if not. The caller can choose to fill them immediately (by passing a values table as second arg) or defer.
  5. **New `lalin.stmts` overload**: `lalin.stmts("source with @{x}", { x = 42 })` — parses the string, fills the slots immediately using the provided values table (calling `host_splice.fill` for each), returns resolved `Stmt[]`. This is the missing overload that replaces the builder for many simple cases.

- **How it works**:
  ```lua
  -- All three paths produce the same thing under the hood:

  -- Path 1: .mlua island (already works)
  local body = func f(x: i32) -> i32
      return x * 2
  end

  -- Path 2: Snippet with values (new)
  local val = lalin.int(42)
  local body = lalin.stmts("let y: i32 = @{v}; return y", { v = val })
  -- Calls parse_stmt_string("let y: i32 = @{v}; return y")
  --   → parser creates ExprSlotValue for @{v}
  --   → host_splice.fill for each slot with the table values
  --   → expands, returns resolved Stmt[]

  -- Path 3: Builder producing SlotValues (aligned, not retired)
  local body = lalin.stmts({ x = lalin.i32 }, function(b)
      local x = b:param("x")
      -- b:return_ returns SlotValueStmt, not raw Tr.StmtReturn
      b:return_(x * 2)
  end)
  -- expand_stmts_with_values resolves all SlotValue wrappers
  ```

  The key insight: the builder's `b:let()`, `b:return_()`, etc. return **the exact same kind of SlotValue-annotated AST node** that the parser produces when it sees `@{...}`. The builder is not a separate paradigm — it's just a direct way to construct SlotValues without parsing.

  Under the hood, `b:let("y", lalin.i32, expr)` constructs:
  ```
  SlotBinding(
      SlotExpr(key="builder:y"),
      SlotValueExpr(body=Tr.StmtLet(...))
  )
  ```
  which is structurally identical to what the parser produces for `let y: i32 = @{expr}` after filling.

- **Tradeoff**: Optimizes for **conceptual unity** — one mental model (SlotValue → expand) across all paths. Sacrifices **simplification** — the builder API still exists and still requires learning. The goal of "retiring the builder API" isn't achieved; instead, it's *assimilated* into a larger SlotValue framework.

- **Risk**: **Too abstract, too much ceremony.** If the builder API is "just SlotValues", the user now needs to understand Slot/SlotValue/Binding/Expansion to use any path. The current builder API's value is that it *hides* this complexity. Exposing SlotValue as the universal currency makes the system more consistent but harder to learn. **Mitigation**: Keep the high-level bindings-layer convenience (e.g., `lalin.stmts(src, {x=42})`) as syntactic sugar over explicit SlotValue construction. The SlotValue model is the *architecture*; the convenience API is the *UI*.

- **Rough sketch**:
  1. Add `SlotValueStmt`, `SlotValueExpr`, `SlotValueType` host wrapper types in `host_values.lua` — these are thin wrappers over `O.SlotBinding` with a `resolve()` method.
  2. Modify `FuncBuilder`: each method (`:let`, `:return_`, `:if_`, etc.) constructs a `SlotValueStmt` instead of directly adding to `b.body`. The slot is filled lazily with the actual ASDL node.
  3. Add `expand_and_collect(stmts, slot_values, env)` to `open_expand.lua` — this is the single entry point for all three paths. Given stmts that may contain `SlotValueStmt` wrappers, it fills the slots from `slot_values`, expands, and returns resolved `Stmt[]`.
  4. `lalin.stmts(string, values_table)` — parse string, get slot-ridden stmts, call `fill` for each slot using values table (this reuses `host_splice.fill`), call `expand_and_collect` with empty env, return resolved stmts.
  5. `mlua_run.lua`'s `eval_island` already calls `fill` + `expand` — this is the same path. Document that `eval_island` is just `expand_and_collect` specialized for `.mlua` source islands.
  6. The `lalin.stmts(function(b)...)` builder form is refactored: `b` is now a `SlotValueCollector` that produces `SlotValueStmt[]`. These are fed into `expand_and_collect` with the provided bindings as slot values. The bindings table `{x=lalin.i32}` creates slots for the builder's parameter references.

---

### Comparison

| Dimension | A: Lazy Snippet Islands | B: Lua-in-Source Blocks | C: SlotValue Universal |
|-----------|------------------------|------------------------|-----------------------|
| **Retires builder API?** | Partially — snippets with lazy `@{}` cover many cases, but Lua loops still need builder | Yes — loops/conditionals in source eliminate the builder's main use case | No — builder is absorbed into SlotValue framework, not removed |
| **New concepts to learn** | `SnippetValue`, sub-env merging | `for/lua`, `${}`, compile-time vs runtime distinction | SlotValue, SlotBinding, fill-then-expand cycle |
| **User mental model** | "Snippets are like .mlua islands with lazy holes" | "Lalin with integrated Lua code generation" | "Everything is a SlotValue that gets expanded" |
| **Implementation risk** | Slot identity across parse contexts | New syntax, compile-time eval confusion | Over-abstraction, ceremony |
| **Composition with outer scope** | Natural — inner slots resolve against merged outer+inner fills | Natural — body template captures outer variables | Explicit — values must be threaded as slot fillers |
| **Loops in codegen** | Still need builder (wrap snippet call in Lua for loop) | Built-in: `for/lua ... do ... end` | Still need Lua loop around builder calls |
| **Migration from builder** | Minimal — snippets are a superset of builder for many cases | Large — new syntax, no builder API anymore | Minimal — existing builder code still works |

**When to pick each:**
- **Pick A** if the goal is incremental improvement: make snippets more powerful while keeping the builder API for Lua loops and complex generation. Best risk/reward ratio — the existing Slot/expander machinery directly supports it modulo slot identity issues.
- **Pick B** if the goal is a radical simplification: eliminate the builder API entirely by making Lalin source self-sufficient for code generation. Best for the user who wants to stay in source syntax. Highest risk — language gets a metaprogramming subsystem that looks like the runtime language.
- **Pick C** if the goal is conceptual elegance: unify everything under one model, even if the builder API remains. Best for the compiler developer who values minimal orthogonal primitives over API surface reduction.

## Scout Output — 2026-05-19 11:22:49

I now have a complete picture. Here is the full inventory.

---

## Complete Stale Reference Inventory

### 1. `README.md` — Most heavily affected

**RETIRED BUILDER API — 10 references:**

| Line(s) | Pattern | Details |
|---------|---------|---------|
| 19 | `lalin.loadstring(source)` / builder API | Production pipeline table says "builder API" |
| 144, 152 | `lalin.switch_arm(...)` | Example code with retired `lalin.switch_arm` (2x) |
| 359 | `lalin.param("a", lalin.i32)` | Example code — retired |
| 360 | `lalin.field("x", lalin.i32), lalin.field("y", lalin.i32)` | Example code — retired (2x) |
| 447-451 | `lalin.stmts({ x = lalin.i32 }, function(b) ... b:let(...) ... b:return_(...) ... end)` | Full builder pattern example — entire block is stale |
| 458 | `lalin.control_block(...)` | Comment reference to retired `lalin.control_block` |
| 488 | `lalin.loadstring(source)` / builder API | Frontend table — stale |
| 622-638 | "From Lua with the builder API" section + example | Entire subsection heading and code example stale |
| 638 | "Or use the builder API" | Comment in code |
| 782 | "High-level Lua builder API" | Repo layout description of `host.lua` |

**MLBT v3 → should be v4 Flatline — 11 references:**

| Line(s) | Phrase |
|---------|--------|
| 12 | `→ MLBT v3 → Cranelift` |
| 20 | "MLBT v3 binary ABI" |
| 491 | "Both entry points emit MLBT v3 binary format" |
| 510 | `MLBT v3 binary (Lua encoder)` |
| 515 | "produces MLBT v3 binary wire format" |
| 527 | `MLBT v3 binary` |
| 778 | "MLBT v3 wire generation" |
| 785 | "MLBT v3 binary wire format encoder" |
| 833 | "**MLBT v3 binary wire format.**" |
| 862 | "MLBT v3 wire builder" |
| 958 | "the same MLBT v3 binary wire format" |

**MOM / `lua/lalin/mom/` — ~30 references:**

Entire "Two frontends" model throughout the document. Major sections affected:
- Lines 11-21: "Two frontends, one ABI" intro table with MOM rows
- Line 72-81: "MOM binary/API" section
- Line 238-239: mom binary embedding MOM sources
- Lines 250-251: MOM binary/API sub-section
- Line 489: MOM in frontend table
- Lines 518-531: "MOM pipeline target" section (pipeline diagram)
- Lines 592, 614-619: mom CLI examples
- Lines 774-785: `mom/` directory, `host_mom.lua` in repo layout
- Lines 831-832: MOM doc links (`PORTING_GUIDE.md`, `PARSER_DESIGN.md`)
- Lines 844-865: "MOM tests" listing (8 test references + `mom status`)
- Line 956: "MOM (Lalin-on-Lalin) is the default compiler"
- Line 958: "both produce the same MLBT v3 binary wire format"

---

### 2. `LANGUAGE_REFERENCE.md` — Partially updated, 8 stale builder references remain

**RETIRED BUILDER API — 8 references:**

| Line(s) | Pattern | Context |
|---------|---------|---------|
| 40 | "15. Lua builder API reference" | TOC entry (section title is now "Quoting and builder API reference" but the `function(b)` pattern is documented as retired) |
| 259 | "alongside the builder API" | Section 3 intro |
| 302 | "### 3.4 Low-level builder APIs" | Section header |
| 304 | "Two additional builder APIs" | Still describes it as current |
| 1416 | "through the builder API (`BackCmd.Sdiv`)" | Section 9.16 — should say "through ASDL construction" or similar |
| 2052 | "## 15. Quoting and builder API reference" | Title says "builder API" |
| 2939 | "-- In builder API:" | Section 21.2 comment in example code |
| 3168 | "high-level builder API entry point" | Implementation map for host.lua |

Also: Line 993 `lalin.stmts("jump handler_" .. key .. "(result)")` — this is the two-arg string form. If that was also retired, this is stale.

**Note**: LANGUAGE_REFERENCE.md sections 3.4 (lines 302-320) describe `lalin.ast` as a "low-level builder API" but this is the ASDL node constructor API which is NOT retired. The text says "Two additional builder APIs produce the same ASDL values" — the `lalin.ast` API is still valid; only the wording "builder API" is misleading.

**MLBT v3**: No references found in LANGUAGE_REFERENCE.md — clean.

**MOM**: 4 references (lines 271, 275-277, 336-339) — all in section 3.2 describing `lalin.native_loadstring` through the MOM pipeline.

---

### 3. `AGENTS.md` — 3 MLBT v3, 9 MOM references

**MLBT v3 → should be v4:**

| Line | Phrase |
|------|--------|
| 78 | "MLBT v3 wire format" (test docstring) |
| 334 | "MLBT v3 binary wire format encoder" |
| 335 | "Binary wire format specification (MLBT v3)" |

**MOM:**

| Line | Reference |
|------|-----------|
| 31 | "MOM status" section — "mom binary links ... MOM sources" |
| 33 | "Do not route compilation through parser-tape shortcuts" |
| 63-65 | MOM test references (3x: `test_mom_groundwork`, `test_mom_native_lexer`, etc.) |
| 78 | MOM wire test |
| 79 | "MOM API source → MLBT → execute" |
| 337 | `host_mom.lua` in key files table |
| 338 | `lua/lalin/mom/` directory in key files table |
| 339 | "When working under `lua/lalin/mom/`" guidance |

---

### 4. `BACK_WIRE_FORMAT.md` — Correct as-is

This file documents itself as "v4 — Flatline" (correct). Lines 5 and 388 reference "MLBT v3" as historical context ("Replaces MLBT v3" and "What Changed from MLBT v3"), which is correct changelog documentation. **No stale references.**

---

### 5. `explicit_programming.md` — 1 stale builder reference

| Line | Pattern |
|------|---------|
| 2947 | `lalin.switch_arm(i, lalin.stmts(function(b)` |

---

### 6. `IMPLEMENTATION_STATUS.md` — Entirely about MOM, 3 MLBT v3 references

**MLBT v3:** Lines 13, 33, 159 (all `driver/wire.mlua` — "MLBT v3 serialization/wire format").

**MOM:** The entire 260-line document is a MOM reorganization status tracker. If MOM is retired, the entire file is stale.

---

### 7. `CURRENT_TASK.md` — 10 MOM references

Lines 128-140 reference `lua/lalin/mom/back/` and `lua/lalin/mom/vec/` files. If MOM is retired, this file's task description is stale.

---

### 8. `struct-conversion.md` — Entirely about MOM (~300 lines)

Whole document is "MOM Struct Conversion Implementation Plan" with references to `lua/lalin/mom/schema/`, `lua/lalin/mom/back/`, etc. Stale if MOM retired.

---

### 9. `README_BACK_LOWER.md` — MOM references

Lines 8-11 reference `lua/lalin/mom/back/back_lower.mlua` and `lua/lalin/mom/back/BACK_LOWER_GUIDE.md`.

---

### 10. `BLOCKER_RESOLUTION_REPORT.md` — MOM references

Lines 3-16 reference `lua/lalin/mom/back/back_lower.mlua` and related files.

---

### 11. Lua source file comments/docstrings

| File | Line | Stale text | Fix needed |
|------|------|-----------|-----------|
| `lua/lalin/back_object.lua` | 3 | "as the **MLBT v3** binary wire format" | Change to "as the Flatline binary wire format (v4)" |
| `lua/lalin/host_func_values.lua` | ~1-428 | Entire `FuncBuilder` class, `b:let`, `b:if_`, `b:return_`, etc. | **But**: These are internal helpers used by `api._module_func`/`:export_func` and `pvm_surface_cache_values.lua` — not directly user-facing. Task says internal APIs are preserved. Comment/docstrings are fine if they're internal use only. |
| `lua/lalin/host_region_values.lua` | ~1-410 | Entire `RegionBuilder`/`BlockBuilder` classes, `api.region_frag(...)` | Same — internal API preserved. |
| `lua/lalin/region_compose.lua` | 167-372 | Uses `b:emit(...)`, `api.region_frag(...)`, `b:jump(...)` | Internal API usage — fine if preserved internally. |

---

### 12. Files that are CLEAN (no stale references found)

- `DESIGN_PHILOSOPHY.md` — no builder, MOM, or MLBT v3 references
- `HOWTO.md` — clean
- `STRUCTURED_PAPER_DRAFT.md` — clean
- `designing_software_with_lalin.md` — clean
- `COMPILER_PATTERN.md` — clean (about ASDL compiler pattern, not Lalin-specific)
- `PVM_GUIDE.md` — clean (the "named-field builders" references are about ASDL builders, not the Lalin builder API)
- `SOURCE_GRAMMAR.md` — does not exist on disk
- `PROTOCOL_SYNTAX.md` — does not exist on disk

---

### Summary Count

| Category | Files affected | Total instances |
|----------|---------------|-----------------|
| Retired builder API (`lalin.param`, `lalin.field`, `lalin.switch_arm`, `b:let`, etc.) | 3 primary + 1 internal | ~19 in docs (README.md: 10, LANGUAGE_REFERENCE.md: 8, explicit_programming.md: 1) |
| MLBT v3 → should be v4 | 4 files | ~15 instances (README.md: 11, AGENTS.md: 3, IMPLEMENTATION_STATUS.md: 3, back_object.lua: 1) |
| MOM / `lua/lalin/mom/` retired | 7 files | ~60+ instances (README.md: ~30, AGENTS.md: 9, LANGUAGE_REFERENCE.md: 4, IMPLEMENTATION_STATUS.md: 260 lines, CURRENT_TASK.md: 10, struct-conversion.md: 300 lines, README_BACK_LOWER.md: 4, BLOCKER_RESOLUTION_REPORT.md: 3) |

### Priority for cleanup

1. **README.md** — Most visible document. Update builder API examples to `lalin.stmts[[]]` / values binder, update MLBT v3 to Flatline v4, remove or minimize MOM sections.
2. **LANGUAGE_REFERENCE.md** — Rename section 15 title, remove "builder API" language from sections 3.4 and 21, update line 1416 and 2939.
3. **AGENTS.md** — Update MLBT v3 references, remove MOM directory pointer.
4. **back_object.lua** — One-line docstring fix.
5. **Explicit_programming.md** — One-line example fix.
6. **Root-level orphan files** (IMPLEMENTATION_STATUS.md, CURRENT_TASK.md, struct-conversion.md, README_BACK_LOWER.md, BLOCKER_RESOLUTION_REPORT.md) — Either remove or archive if MOM is truly retired.
