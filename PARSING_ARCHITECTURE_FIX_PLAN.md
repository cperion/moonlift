# Moonlift Parsing Architecture Rewrite Plan

This is a concrete code-level rewrite plan. It says what code goes away, what new code is added, and where responsibilities land.

Goal: one parser, one `.mlua` model, no source modules, no `export`, no compatibility shims.

---

## 0. Final language/runtime decisions

These are fixed decisions, not later choices.

### `.mlua` model

`.mlua` is Lua with embedded Moonlift **value islands**.

Valid style:

```lua
local add = func add(a: i32, b: i32) -> i32
    return a + b
end

return add
```

Invalid/removed style:

```moonlift
export func add(a: i32, b: i32) -> i32
    return a + b
end
```

There is no user-facing Moonlift module source. There is no implicit top-level item collection.

### User-facing island kinds

Keep exactly:

```text
func
region
expr
type
```

Remove as user-facing islands:

```text
export
module
struct
const
static
extern
import
expose
```

`struct` remains only inside a `type` island:

```lua
local Pair = type Pair = struct
    x: i32
    y: i32
end
```

### Type island syntax

All `type` islands are end-delimited.

```lua
local Result = type Result = ok(value: i32) | err(code: i32) | none
end
```

No line-only type islands.
No enum or untagged union syntax in the clean core.
No braced struct syntax.

### Splice rule

`@{...}` is a whole syntax node.

Allowed:

```moonlift
func @{name}(x: @{T}) -> @{T}
    return @{expr}
end
```

Removed:

```moonlift
func f_@{suffix}(...)
region r_@{name}(...)
```

---

## 1. Files to delete or stop using

Delete these if present. If already deleted, keep them deleted.

```text
lua/moonlift/mlua_document.lua
lua/moonlift/mlua_host_model.lua
lua/moonlift/mlua_lex.lua
lua/moonlift/mlua_loop_expand.lua
lua/moonlift/host_eval.lua
lua/moonlift/host_decl_parse.lua
lua/moonlift/parser_compose.lua
```

Remove all active `require(...)` references to them.

Known references to remove/update:

```text
lua/moonlift/rpc_out_commands.lua            requires moonlift.mlua_document_analysis
editor/LSP test files                        old document parse/analysis stack
old tests                                    host_decl_parse, mlua_document, mlua_host_model, parser_compose
```

For now, editor/LSP code may be disabled. Do not keep a second parse model alive just to keep LSP compiling.

---

## 2. `parse.lua` rewrite

`lua/moonlift/parse.lua` becomes the only parser and document scanner.

### 2.1 Remove from `parse.lua`

Remove token kinds and keywords for removed source concepts:

```lua
export_kw
extern_kw
const_kw
static_kw
```

Remove parser functions:

```lua
Parser:parse_extern_func
Parser:parse_const
Parser:parse_static
Parser:parse_struct as standalone island parser
```

Keep struct parsing only as an internal helper for `type Name = struct ... end`.

Remove any public or private module/item parser path:

```lua
parse_module
parse_items
parse_stmt_list
parse_type_string
parse_func public wrapper
parse_region_frag public wrapper
parse_expr_frag public wrapper
parse_struct public wrapper
parse_const public wrapper
parse_static public wrapper
parse_extern_func public wrapper
parse_item
ItemUseItemsSlot creation from parser
module_items splice role from parser
```

Remove public token parser exports:

```lua
parser_from_toks
```

### 2.2 Add concrete data structures

Add documented internal tables. They can be plain Lua tables for now.

```lua
-- Returned by Parse.scan_document(src)
DocumentScan = {
    src = string,
    toks = TokenStream,
    lua_spans = { LuaSpan... },
    islands = { IslandSpan... },
    splice_map = { [splice_id] = lua_expr_source },
}

LuaSpan = {
    start = byte_start,
    stop = byte_stop,
}

IslandSpan = {
    kind = "func" | "region" | "expr" | "type",
    first_tok = token_index,
    last_tok = token_index,
    start = byte_start,
    stop = byte_stop,
    holes = { splice_id... },
}
```

Token stream remains array-based:

```lua
TokenStream = {
    src = src,
    n = token_count,
    kind = {}, text = {}, start = {}, stop = {}, line = {}, col = {},
    splice_map = {},
    splice_i = number,
}
```

But tokens in document scans are only Moonlift island tokens, not tokens for arbitrary Lua text.

### 2.3 Add Lua-aware scanner

Add these functions to `parse.lua`:

```lua
local function skip_lua_short_string(src, i, quote) -> new_i
local function scan_lua_long_bracket(src, i) -> close_i_or_nil
local function skip_lua_comment(src, i) -> new_i
local function scan_lua_identifier(src, i) -> text, new_i
local function lua_value_position(prev_sig_token) -> boolean
local function scan_lua_until_island(src, i, state) -> lua_span_or_island_start
function M.scan_document(src) -> DocumentScan
```

`scan_document` works in Lua mode:

- skip Lua `'...'`
- skip Lua `"..."`
- skip Lua long strings `[=[...]=]`
- skip Lua `--...`
- skip Lua `--[=[...]=]`
- scan Lua identifiers without treating them as islands unless they appear in value position

Recognized island starts only in Lua value position:

```lua
local f = func ... end
return func ... end
foo(func ... end)
{ func ... end }
name = region ... end
```

Do **not** recognize bare top-level Moonlift item syntax. This is intentionally invalid:

```moonlift
func f() end
```

unless it is in Lua value position, e.g. `local f = func f() end`.

### 2.4 Add island tokenization from original source

Add a lexer entry that tokenizes an island directly from the original document source and appends tokens into the shared document token stream.

```lua
local function lex_moon_from(src, start_byte, toks, scan_state) -> first_tok, last_tok, stop_byte
```

Rules:

- It uses original byte offsets.
- It updates the shared `splice_i` and `splice_map`.
- It records `TK.hole` token text as the global splice id.
- It stops at the grammar boundary for the island kind.
- It does not allocate a source substring and then call `M.lex(substring)`.

The existing lexer can be refactored into:

```lua
local function lex_range(src, i, stop_predicate, toks, scan_state)
```

but token spans must remain original document spans.

### 2.5 Add token-window parser construction

Replace private parser constructor with:

```lua
local function new_parser(T, toks, first_tok, last_tok, opts)
```

Parser fields:

```lua
first = first_tok
limit = last_tok
i = first_tok
```

Token accessors become limit-aware:

```lua
function Parser:kind(offset)
    local j = self.i + (offset or 0)
    if j > self.limit then return TK.eof end
    return self.toks.kind[j]
end
```

`text/start/stop` should similarly handle `j > limit`.

### 2.6 Replace public parse API

Public API exported by `M.Define(T)` should be only:

```lua
{
    TK = TK,
    scan_document = M.scan_document,
    parse_island = function(scan, island_index, opts)
        return M.parse_island(T, scan, island_index, opts)
    end,
    parse_type = function(src_or_window, opts)
        return M.parse_type(T, src_or_window, opts)
    end,
}
```

Module-level API:

```lua
M.scan_document(src)
M.parse_island(T, scan, island_index, opts)
M.parse_type(T, src_or_window, opts)
```

No source-string `parse(kind, src)` for islands in final runtime path.

### 2.7 Implement `parse_island`

```lua
function M.parse_island(T, scan, island_index, opts)
    local island = scan.islands[island_index]
    local p = new_parser(T, scan.toks, island.first_tok, island.last_tok, opts)
    ... dispatch on island.kind ...
end
```

Dispatch:

```lua
func   -> parse_func()       returns MoonTree.FuncLocal / FuncLocalContract
region -> parse_region_frag() returns MoonOpen.RegionFrag
expr   -> parse_expr_frag()   returns MoonOpen.ExprFrag
type   -> parse_type_decl_island() returns TypeDeclParseResult
```

`func` never parses `export`.

### 2.8 Type parsing return shape

Replace current `parse_type_item` returning `Tr.ItemType(...)` with a non-item result.

Add:

```lua
function Parser:parse_type_decl_island()
    -- consumes: type Name = ... end
    -- returns:
    return {
        name = name,
        decl = TypeDeclStruct(...) or TypeDeclTaggedUnionSugar(...),
        protocol_variants = variants_or_nil,
    }
end
```

No `MoonTree.ItemType` in the parser result for user-facing type islands.

---

## 3. `mlua_run.lua` rewrite

`lua/moonlift/mlua_run.lua` becomes runtime/carrier/value code only. It does not parse.

### 3.1 Remove from `mlua_run.lua`

Remove parser-like code:

```lua
manual island_kws table
manual openers table
manual token walk for island boundaries
source slicing as island_src
regex qualified probe scan
kind_word = isl.kind:gsub(...)
```

Remove user-facing module code:

```lua
ModuleValue public wrapper
CompiledModule public wrapper
exported_module_fields
module_funcs as exported-module discovery
module_name_of as user-facing metadata
module_with_required_deps using required modules
module item field exposure
```

A small internal helper may still assemble a temporary `MoonTree.Module` for compilation, but it must not be exposed as a Lua host value.

Remove source-module style `moon.require` dependency injection. `moon.require` should load a `.mlua` file and return its Lua return value. Dependencies are carried by explicit host values, not implicit module imports.

### 3.2 Runtime holds the scan

In `M.loadstring`:

```lua
local scan = Parse.scan_document(src)
local runtime = setmetatable({
    T = T,
    session = session,
    scan = scan,
    region_frags = {},
    expr_frags = {},
    protocol_types = {},
    require_cache = ...,
}, Runtime)
```

### 3.3 Carrier generation uses scan output

Carrier generation:

```lua
local cursor = 1
for island_index, island in ipairs(scan.islands) do
    emit Lua span from cursor to island.start - 1
    emit eval call for island_index
    cursor = island.stop + 1
end
emit trailing Lua
```

Generated island call:

```lua
__moonlift_runtime:eval_island(<island_index>, {
    ["splice.1"] = function() return (<lua expr>) end,
})
```

Do not pass island source text.

### 3.4 Fix `Runtime:eval_island` signature

Replace:

```lua
Runtime:eval_island(kind_word, island_src, closures)
```

with:

```lua
Runtime:eval_island(island_index, closures)
```

Implementation:

```lua
local island = self.scan.islands[island_index]
local parsed = Parse.Define(T).parse_island(self.scan, island_index, parse_opts)
```

### 3.5 Remove regex qualified probes

Delete this entire behavior:

```lua
for base, field in isl_text:gmatch("...") do
    qualified.base.field closure
end
```

No replacement in `mlua_run.lua`.

Dependencies must be explicit via splices:

```moonlift
@{T}
emit @{frag}(...)
region @{name}(...)
```

### 3.6 Add explicit value dependency model

Create a simple dependency table carried by host values:

```lua
Deps = {
    type_decls = { TypeDeclValue... },
    region_frags = { RegionFragValue... },
    expr_frags = { ExprFragValue... },
}
```

Add helpers in `mlua_run.lua` or `host_values.lua`:

```lua
local function empty_deps()
local function merge_deps(a, b)
local function deps_of_value(value)
local function collect_closure_deps(luamap)
```

When an island is evaluated:

1. evaluate closures;
2. collect deps from closure values;
3. fill slots;
4. expand;
5. attach merged deps to returned host value.

This replaces implicit module imports.

### 3.7 Uniform expansion for every island kind

Add runtime helper:

```lua
local function expand_parsed_value(runtime, parsed, bindings, deps)
```

Implementation by kind:

#### `region`

```lua
expanded = Expand.expand_region_frag(parsed.value, env)
return HostValues.region_frag_value(session, expanded, { deps = deps })
```

#### `expr`

```lua
expanded = Expand.expand_expr_frag(parsed.value, env)
return HostValues.expr_frag_value(session, expanded, { deps = deps })
```

#### `func`

Wrap in internal module, expand module, extract function:

```lua
local raw_mod = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(parsed.value) })
local expanded_mod = Expand.expand_module(raw_mod, env)
local func = extract only ItemFunc
return FuncValue { func = func, deps = deps }
```

The returned `FuncValue.func` must contain no open slots.

#### `type`

Parsed type returns `{ name, decl, protocol_variants }`.

Construct a `TypeDeclValue`:

```lua
TypeDeclValue {
    name = parsed.value.name,
    decl = expanded_decl,
    ty = Ty.TNamed(Ty.TypeRefGlobal("", parsed.value.name)), -- internal empty module name for now
    protocol_variants = parsed.value.protocol_variants,
    deps = deps,
}
```

Register protocol variants in `runtime.protocol_types` by name.

### 3.8 Replace `FuncValue:compile`

`FuncValue:compile()` assembles an internal module:

```lua
items = {}
append deps.type_decls as Tr.ItemType(decl)
append function as Tr.ItemFunc(func)
mod = Tr.Module(Tr.ModuleSurface, items)
run typecheck/layout/lower/JIT
return CompiledFunction
```

No exported-module discovery.
No `CompiledModule:get`.

`CompiledFunction` stores one function name and C signature.

---

## 4. Host value changes

### 4.1 `host_values.lua`

Remove source-string values completely:

```lua
SourceValue
NilSpliceValue as source
api.HostSourceValue
api.source_value
HostValueSource kind use
```

Add or move dependency helpers here if not in `mlua_run.lua`:

```lua
api.empty_deps()
api.merge_deps(...)
api.deps_of(value)
```

Region/expr fragment values should carry deps:

```lua
value.deps = opts.deps or empty_deps()
```

### 4.2 `host_type_values.lua`

Add `TypeDeclValue` or extend `TypeValue` to carry declaration deps.

Required fields:

```lua
{
    kind = "type",
    name = "Pair",
    ty = MoonType.TNamed(...),
    decl = MoonTree.TypeDeclStruct(...), -- optional for scalar types
    protocol_variants = optional,
    deps = Deps,
    session = session,
}
```

Scalar types have empty deps and no decl.

Named type islands have a decl and deps including themselves:

```lua
deps.type_decls = { self }
```

### 4.3 `host_splice.lua`

Keep only parser-produced slot wrappers:

```lua
O.SlotType
O.SlotExpr
O.SlotRegion
O.SlotRegionFrag
O.SlotExprFrag
O.SlotName
```

Remove support for:

```lua
O.SlotItems
O.SlotModule
O.SlotTypeDecl
O.SlotFunc
O.SlotConst
O.SlotStatic
O.SlotCont
Direct TypeSlot/ExprSlot/etc convenience paths
source string parsing
cross-context reparsing
```

Add session checks:

```lua
if value.session and value.session ~= session then
    error("splice value belongs to a different Moonlift session")
end
```

`fill_type` should accept only:

- active-session `TypeValue` / `TypeDeclValue`
- raw ASDL type node from the same context if explicitly allowed internally

`fill_expr` should accept only:

- primitives -> literal expressions
- active-session ExprValue
- raw ASDL expr node if explicitly allowed internally

No `moon.source` or raw source string coercion.

---

## 5. Schema cleanup

### 5.1 `lua/moonlift/schema/init.lua`

Remove:

```lua
require("moonlift.schema.mlua")(A)
```

until a new schema is written for the new scan model.

### 5.2 Delete or quarantine `lua/moonlift/schema/mlua.lua`

The old `MoonMlua` schema describes the deleted document pipeline. It should not be part of active `A.Define(T)`.

If editor/LSP later needs schema, create a new one, e.g. `schema/parse_document.lua`, based on `Parse.scan_document` concepts, not old HostProgram/DocumentParts.

### 5.3 `lua/moonlift/schema/host.lua`

Remove old parse pipeline products/sums:

```text
HostDeclSource
MluaSource
HostStep
HostProgram
MluaParseResult
MluaHostPipelineResult
HostIssueTemplateParseError
HostValueSource
```

Keep host facts/layout/JIT support only if still used by non-parser code.

### 5.4 `lua/moonlift/schema/open.lua`

Do not necessarily delete internal slot variants yet, because other ASDL phases may still mention them.

But parser/runtime must stop producing/filling these user-facing roles:

```text
SlotItems
SlotModule
SlotTypeDecl
SlotFunc
SlotConst
SlotStatic
SlotCont
```

Later compiler cleanup can remove them if no longer used.

---

## 6. `host_session.lua` cleanup

Stop installing APIs tied to deleted module/source concepts.

Remove from `Session:api()` if no longer used:

```lua
require("moonlift.host_module_values").Install(api, self)
require("moonlift.host_decl_values").Install(api, self) -- if only for expose/decl pipeline
require("moonlift.host_template_values").Install(api, self) -- if it represents old template API, not generic type factories
```

Keep:

```lua
host_type_values
host_expr_values
host_place_values
host_fragment_values
host_struct_values if used for type values
host_func_values if compatible with FuncValue model
host_region_values if used for fragment builders
```

If a kept module exposes source/module parse APIs, remove only those functions.

---

## 7. Compiler container helpers

Create a small internal helper module or local helpers in `mlua_run.lua`:

```lua
local function internal_module_for_func(T, func, deps)
    local Tr = T.MoonTree
    local items = {}
    append_type_deps(items, deps)
    items[#items + 1] = Tr.ItemFunc(func)
    return Tr.Module(Tr.ModuleSurface, items)
end
```

This is the only module assembly path left.

No source parser emits modules.
No host runtime exposes modules as user values.

---

## 8. Tests to delete or rewrite

### Delete old parser pipeline tests

Delete or fully rewrite tests that require:

```text
moonlift.mlua_document
moonlift.mlua_host_model
moonlift.mlua_loop_expand
moonlift.host_decl_parse
moonlift.parser_compose
```

### Rewrite source examples/tests

Replace `export func` with Lua-first bindings.

Old:

```moonlift
export func add(a: i32, b: i32) -> i32
    return a + b
end
```

New:

```lua
local add = func add(a: i32, b: i32) -> i32
    return a + b
end

return add
```

### Required new tests

Add tests for the new architecture:

#### Multi-island splice IDs

```lua
local T = moon.i32
local f1 = func f1(x: @{T}) -> @{T} return x end
local f2 = func f2(x: @{T}) -> @{T} return x end
return f2
```

Must not fail with missing splice ids.

#### Func expansion

Returned function must not contain `TSlot` after eval.

#### Lua scanner correctness

These must not create islands:

```lua
local func = 1
local s = 'func nope'
local s2 = [[ region nope end ]]
-- func nope
```

These must create islands:

```lua
local f = func f() end
return func g() end
foo(region r() entry start() end end)
```

#### Type island

```lua
local Pair = type Pair = struct
    x: i32
end
```

Must return a type value with a decl dependency.

#### Named type dependency compile

```lua
local Pair = type Pair = struct
    x: i32
end

local get = func get(p: ptr(@{Pair})) -> i32
    return (*p).x
end

return get
```

Internal compile module must include `Pair` before `get`.

---

## 9. Documentation rewrite

Update docs and README to remove:

```text
export func
source modules
module item syntax
parse_module APIs
import item syntax
standalone struct/const/static/extern islands
fn/fnptr
&T pointer type
partial-token splices
enum/untagged union syntax
old LSP/document parser references
```

Replace all usage with Lua-first islands.

---

## 10. Concrete implementation order

1. **Parser surface reduction**
   - edit `parse.lua`
   - remove export/extern/const/static standalone parsing
   - restrict public islands to func/region/expr/type
   - make func always local
   - make type end-delimited

2. **Document scan rewrite**
   - add Lua scanner helpers in `parse.lua`
   - add `scan_document`
   - island detection only in Lua value position

3. **Token-window parser**
   - refactor lexer to tokenize islands into shared stream
   - add `new_parser(T, toks, first, last, opts)`
   - parse from scan token windows

4. **Runtime scan integration**
   - edit `mlua_run.lua`
   - store `runtime.scan`
   - generate carrier from `scan.lua_spans` / `scan.islands`
   - eval by island index
   - remove source slice reparsing

5. **Splice/dependency model**
   - edit `host_splice.lua`, `host_values.lua`, `host_type_values.lua`
   - remove source parsing/coercion paths
   - add deps helpers
   - add TypeDeclValue

6. **Uniform expansion**
   - edit `mlua_run.lua`
   - expand func/region/expr/type consistently
   - ensure no visible slots remain after eval

7. **Remove module user API**
   - edit `mlua_run.lua`
   - remove `ModuleValue`/`CompiledModule` public behavior
   - compile functions through internal temporary modules only

8. **Schema cleanup**
   - edit `schema/init.lua`, `schema/host.lua`
   - remove old MoonMlua/HostProgram parse model from active schema

9. **Tests/docs rewrite**
   - delete old parser-pipeline tests
   - rewrite examples to Lua-first style
   - add new architectural tests listed above

---

## 11. Definition of done

The rewrite is complete when all are true:

- `parse.lua` is the only parsing implementation.
- Runtime never reparses island source substrings.
- Splice IDs are stable across multi-island files.
- `.mlua` is Lua-first: islands appear only as Lua values.
- User-facing islands are only `func`, `region`, `expr`, `type`.
- `export`, source modules, item parsing, and implicit module assembly are gone.
- `type` islands are always end-delimited.
- Every returned host value is open-expanded.
- Function compile assembles only an internal temporary module with explicit deps.
- No regex qualified-name probing remains.
- Partial-token splices are rejected/absent.
- Old document/parser schemas and modules are not active.
- Docs/tests/examples match the implemented language.
