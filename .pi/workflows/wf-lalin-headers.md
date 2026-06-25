# Lalin Header Files — Architecture Exploration 
**Started**: 2026-05-19 17:56:00
---

## Scout Output — 2026-05-19 17:57:28

Now I have all the information needed. Here's my comprehensive report:

---

## Files Retrieved

1. **`lua/lalin/schema/tree.lua`** (full file, 1073 lines) — Core ASDL schema for all LalinTree types: Expr, Stmt, Func, ExternFunc, Item, Module, etc.
2. **`lua/lalin/schema/open.lua`** (full file) — LalinOpen schema: slots, fills, open sets, meta-facts, validation
3. **`lua/lalin/schema/host.lua`** (full file) — LalinHost schema: host decls, struct decls, exposure, access plans, layouts
4. **`lua/lalin/schema/type.lua`** (lines 1-60) — TypeRef variants including TypeRefGlobal
5. **`lua/lalin/schema/core.lua`** (lines 1-15) — Path and Name product types
6. **`lua/lalin/parse.lua`** — Extern parsing (lines 1542-1555), module parsing (lines 2416-2455), island dispatch (lines 2291-2296)
7. **`lua/lalin/frontend_pipeline.lua`** (full file) — Batch compilation pipeline: parse → open-expand → open-validate → closure-convert → typecheck → layout-resolve → tree-to-back → back-validate
8. **`lua/lalin/mlua_document_analysis.lua`** (full file) — LSP/document analysis pipeline for `.mlua` files
9. **`lua/lalin/tree_module_type.lua`** (full file) — Module environment construction: name resolution, value/type entries, env building
10. **`lua/lalin/tree_typecheck.lua`** — Typecheck dispatch for Item variants (lines 859-869)
11. **`lua/lalin/tree_to_back.lua`** — Lowering dispatch (lines 2443-2468, 2477-2523) including extern lowering and global context collection
12. **`lua/lalin/host_session.lua`** (first 120 lines) — Session/builder API foundation
13. **`lua/lalin/host_module_values.lua`** (full file) — Bundle/Module builder: item collection, compilation, moduletree assembly
14. **`lua/lalin/host_func_values.lua`** (lines 1-350) — Func value creation including `_module_extern_func` (line 318)
15. **`lua/lalin/mlua_run.lua`** (full file) — `.mlua` runtime: compiles source through frontend_pipeline → JIT → callable function
16. **`lua/lalin/init.lua`** (lines 1-80) — Public API facade: loadstring/loadfile/dofile/eval
17. **`lua/lalin/ast.lua`** (line 993) — ImportItem wrapping in ast.lua
18. **`lua/lalin/editor_symbol_facts.lua`** (lines 122-124) — ItemImport symbol extraction for LSP

---

## Key Code

### Module — The Top-Level Product

**`schema/tree.lua` lines 1031-1055:**
```lua
A.sum "ModuleHeader" {
    A.variant "ModuleSurface",      -- Before typechecking (no name)
    A.variant "ModuleTyped" {
        A.field "module_name" "string",   -- After typecheck (name known)
    },
    A.variant "ModuleOpen" {
        A.field "name" "LalinOpen.ModuleNameFacet",
        A.field "open" "LalinOpen.OpenSet",
    },
    A.variant "ModuleSem" {
        A.field "module_name" "string",
    },
    A.variant "ModuleCode" {
        A.field "module_name" "string",
    },
},
A.product "Module" {
    A.field "h" "LalinTree.ModuleHeader",
    A.field "items" (A.many "LalinTree.Item"),
    A.unique,
},
```

### Item — The Sum of All Top-Level Declarations

**`schema/tree.lua` lines 972-1015:**
```lua
A.sum "Item" {
    A.variant "ItemFunc"     { A.field "func" "LalinTree.Func" },
    A.variant "ItemExtern"   { A.field "func" "LalinTree.ExternFunc" },
    A.variant "ItemConst"    { A.field "c" "LalinTree.ConstItem" },
    A.variant "ItemStatic"   { A.field "s" "LalinTree.StaticItem" },
    A.variant "ItemImport"   { A.field "imp" "LalinTree.ImportItem" },
    A.variant "ItemType"     { A.field "t" "LalinTree.TypeDecl" },
    A.variant "ItemUseTypeDeclSlot" { A.field "slot" "LalinOpen.TypeDeclSlot" },
    A.variant "ItemUseItemsSlot"    { A.field "slot" "LalinOpen.ItemsSlot" },
    A.variant "ItemUseModule" {
        A.field "use_id" "string",
        A.field "module" "LalinTree.Module",
        A.field "fills" (A.many "LalinOpen.SlotBinding"),
    },
    A.variant "ItemUseModuleSlot" {
        A.field "use_id" "string",
        A.field "slot" "LalinOpen.ModuleSlot",
        A.field "fills" (A.many "LalinOpen.SlotBinding"),
    },
    A.variant "ItemData" { A.field "data" "LalinTree.DataItem" },
}
```

### ImportItem

**`schema/tree.lua` lines 1024-1028:**
```lua
A.product "ImportItem" {
    A.field "path" "LalinCore.Path",
    A.unique,
}
```

**`schema/core.lua` lines 6-13:**
```lua
A.product "Name" { A.field "text" "string", A.unique }
A.product "Path" { A.field "parts" (A.many "LalinCore.Name"), A.unique }
```

### TypeRefGlobal (Type reference by module+type name)

**`schema/type.lua` lines 7-13:**
```lua
A.variant "TypeRefGlobal" {
    A.field "module_name" "string",
    A.field "type_name" "string",
},
```

Other variants: `TypeRefPath(path)`, `TypeRefLocal(sym)`, `TypeRefSlot(slot)`

### Func and ExternFunc — The Core Function Shapes

**`schema/tree.lua` lines 837-876:**
```lua
A.sum "Func" {
    A.variant "FuncLocal"           { name, params, result, body }
    A.variant "FuncExport"          { name, params, result, body }      -- bodyless = header???
    A.variant "FuncLocalContract"   { name, params, result, contracts, body }
    A.variant "FuncExportContract"  { name, params, result, contracts, body }  -- bodyless = header???
    A.variant "FuncOpen"            { sym, visibility, params, open, result, body }
}
A.sum "ExternFunc" {
    A.variant "ExternFunc"     { name, symbol, params, result }
    A.variant "ExternFuncOpen" { sym, params, result }
}
```

**Key insight**: Every `Func` variant has a `body` field. There is currently **no bodyless function type** in the ASDL. ExternFunc is the only bodyless pattern, and it's a completely separate sum type from Func.

### How `extern func` is parsed (parse.lua lines 1542-1556)

```lua
function Parser:parse_extern()
    local name = self:name_or_hint_before_lparen("expected extern function name")
    self:expect(TK.lparen); local params, _ = self:parse_param_list(); self:expect(TK.rparen)
    local result = Ty.TScalar(C.ScalarVoid)
    if self:accept(TK.arrow) then self:skip_nl(); result = self:parse_type() end
    local symbol = name
    if self:accept(TK.as_kw) then self:skip_nl(); symbol = self:expect_string("expected extern symbol string") end
    self:skip_nl(); self:expect(TK.end_kw, "expected end after extern declaration")
    return Tr.ExternFunc(name, symbol, params, result)
end
```

The extern is wrapped in `parse_module_document` (line 2444-2445) as `Tr.ItemExtern(parsed.value)`.

### How `parse_module_document` constructs modules (parse.lua lines 2416-2455)

```lua
function M.parse_module_document(T, src, opts)
    local scan = M.scan_document(src)
    local items = {}
    for i = 1, #scan.islands do
        local parsed = M.parse_island(T, scan, i, ...)
        if parsed.kind == "func" then
            local func = parsed.value
            -- Always wraps as FuncExport (never leaves FuncLocal at top level)
            if pvm.classof(func) == Tr.FuncLocal then
                func = Tr.FuncExport(func.name, func.params, func.result, func.body)
            end
            items[#items + 1] = Tr.ItemFunc(func)
        elseif parsed.kind == "extern" then
            items[#items + 1] = Tr.ItemExtern(parsed.value)
        elseif parsed.kind == "struct" or parsed.kind == "union" then
            items[#items + 1] = Tr.ItemType(parsed.value.decl)
        end
    end
    return { kind = "module", module = Tr.Module(Tr.ModuleSurface, items), scan = scan, issues = issues }
end
```

### How ItemImport is handled (currently a no-op through pipeline)

**Stage-by-stage dispatch for ItemImport:**

| Phase | File:Line | Behavior |
|---|---|---|
| TreeModuleType (env entries) | `tree_module_type.lua:119,135` | `return pvm.empty()` — contributes nothing |
| OpenFacts | `open_facts.lua:368` | `return pvm.empty()` — no meta-facts |
| OpenExpand | `open_expand.lua:930` | `return pvm.once(self)` — identity |
| OpenRewrite | `open_rewrite.lua:342` | `return pvm.once(self)` — identity |
| Typecheck | `tree_typecheck.lua:861` | `return pvm.once(Tr.TypeItemResult({ self }, {}))` — pass through |
| SemLayoutResolve | `sem_layout_resolve.lua:346` | `return pvm.once(self)` — identity |
| TreeToBack | `tree_to_back.lua:1098,2567` | `return pvm.once(Tr.TreeBackItemResult({}))` — emits no commands; item_name returns path |

### How ItemUseModule is handled (the only real cross-module reference)

| Phase | File:Line | Behavior |
|---|---|---|
| Typecheck | `tree_typecheck.lua:865-867` | Recursively typechecks nested module |
| OpenExpand | `open_expand.lua:946-950` | Expands module, flattens items into parent |
| OpenFacts | `open_facts.lua:372` | Emits `MetaFactModuleUse(use_id)` |
| TreeToBack | `tree_to_back.lua:2463-2468` | Wraps in `with_module_context`, lowers all items |
| TreeToBack (globals) | `tree_to_back.lua:2504-2505` | Recursively collects const/static globals |
| TreeModuleType | `tree_module_type.lua:122-124` | Recursively collects item layouts |
| TreeModuleType (env) | `tree_module_type.lua:138-140` | Recursively collects env entries |

### How TypeRefGlobal is constructed and used

**Construction** — never from parser, only from builder API:
- `tree_module_type.lua:67-70` — `TypeDeclStruct/Union/EnumSugar/TaggedUnionSugar` entries use `Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name))`
- `host_struct_values.lua:125,149,234,251,257` — Builder struct/enum/tagged_union types use `Ty.TypeRefGlobal(module_name, name)`
- `host_type_values.lua:168` — `api.named(module_name, type_name)` creates `Ty.TNamed(Ty.TypeRefGlobal(module_name, type_name))`
- `host_layout_facts.lua:139` — Layout facts reference types as `Ty.TypeRefGlobal("host", layout_name)`
- `editor_signature_help.lua:218` — Host field accessor uses `Ty.TypeRefGlobal("mlua", owner_name)`

**Resolution** — matched against `Sem.LayoutNamed`:
- `tree_typecheck.lua:101-102` — Layout matching: `layout.module_name == ref.module_name and layout.type_name == ref.type_name`
- `sem_layout_resolve.lua:68-70` — Looks up in layout_env by module_name and type_name
- `type_size_align.lua:64-66` — Size/align resolution
- `type_classify.lua:28-29` — Classifies as `TypeClassAggregate(module_name, type_name)`

### frontend_pipeline.lua — Full Pipeline

**`frontend_pipeline.lua` (full, 85 lines):**

The pipeline is:
1. `Parse.parse_module(src)` — returns `{ module = Tr.Module(ModuleSurface, items), scan, issues }`
2. Builds anchors for LSP span resolution from scan tokens
3. `OpenExpand.module(module, expand_env)` — expands open fragments/slots
4. `OpenValidate.validate(OpenFacts.facts_of_module(expanded))` — validates open completeness
5. `ClosureConvert.module(expanded)` — rewrites closures
6. `Typecheck.check_module(closed)` — type checks, returns `Tr.Module(ModuleTyped(name), items)`
7. `Layout.module(checked.module, layout_env)` — resolves struct layouts
8. `Lower.module(resolved)` — tree-to-back lowering → `BackProgram`
9. `BackValidate.validate(program)` — validates backend commands
10. Returns: `{ expanded, open_report, closed, checked, resolved, program, back_report, provenance }`

### mlua_document_analysis.lua — Document Analysis

**`mlua_document_analysis.lua` (full, ~160 lines):**

Per-island analysis for LSP. For each island in a `.mlua` document:
1. `ParseApi.parse_island(scan, i, ...)` parses the island
2. For `struct`: creates `HostDeclStruct` + `Tr.ItemType(TypeDeclStruct(...))`
3. For `func`: wraps as `Tr.ItemFunc(parsed.value)`
4. For `extern`: wraps as `Tr.ItemExtern(parsed.value)` (same as parse_module)
5. For `region`/`expr`: adds to frag lists
6. Runs `HostValidate.validate(decls)` for host validation
7. If items exist: calls `Pipeline.lower_module(combined.module, ...)` for type checking + lowering
8. Returns `DocumentAnalysis(parse, host, open_report, type_issues, ..., back_report, anchors)`

---

## Relationships — How the Pieces Connect

### Data Flow for `.mlua` files:

```
.mlua source
  → parse_module_document()      [parse.lua:2416]
    → scan_document() splits into islands (func/struct/union/extern islands)
    → Each island parsed separately
    → Items collected into Tr.Module(ModuleSurface, items)
  → frontend_pipeline.parse_and_lower()   [frontend_pipeline.lua:52]
    → Parse.parse_module() → Module(ModuleSurface, items)
    → OpenExpand.module()  → expand open fragments
    → ClosureConvert.module() → rewrite closures
    → Typecheck.check_module() → Module(ModuleTyped(name), items)
    → Layout.module() → resolve struct layouts
    → Lower.module()  → BackCmd[] 
    → BackValidate.validate() → verify backend invariants
  → back_jit.compile(program) → native code
```

### The Builder API flow (host_module_values.lua):

```
lalin.bundle("mod")
  → :struct/union/func/extern_func/const/static/region/import
  → items[] accumulates Item values
  → :to_asdl() → Tr.Module(ModuleTyped(name), items)
  → :compile() → frontend_pipeline + JIT
```

### How TypeRefGlobal connects module boundaries:

```
Module A: TypeDeclStruct("Foo", fields)
  → tree_module_type: type_entry(TypeRefGlobal("A", "Foo"))
  → env.types[] includes { name="Foo", ty=TNamed(TypeRefGlobal("A","Foo")) }

Module B: var x: MyType
  → parser creates TypeRefPath(["MyType"])
  → typecheck resolves to TypeRefGlobal("A", "Foo") via env lookup
  → LayoutNamed("A", "Foo", fields, size, align) resolved from layout_env
```

### Cross-module gap:

The ASDL has `ItemImport` and `ItemUseModule` variants, but:
- **Parser never produces them** — the module parser (parse.lua:2416) only creates ItemFunc/ItemExtern/ItemType
- **ItemImport is a pass-through no-op** at every pipeline stage — contributes nothing to env, emits no backend commands
- **ItemUseModule** is used (by the open fragment expansion system) — it embeds a full `Module` tree that gets recursively processed
- **No syntax exists** for referencing items from another module in source

### ModuleHeader state machine:

```
ModuleSurface (parser output, no name)
  → [typecheck] → ModuleTyped(module_name)  (module_name is "" for top-level, or derived from ModuleOpen)
  → [layout]    → ModuleSem(module_name)
  → [lowering]  → ModuleCode(module_name)
```

For ModuleOpen: `open_expand.lua:630` promotes to `ModuleTyped(name.module_name)` when open set is empty.

---

## Observations

1. **The parser has an `import` syntax in the legacy archive** (`museum/gps.lua/archive/` shows `parse_item` handling `import Demo`), but the current `parse.lua` has **no import parsing**. This was removed during the migration to the island-based parser.

2. **`ItemImport` is a vestigial structure** — fully defined in ASDL, wrapped by `ast.lua:993`, handled as a no-op identity at every pipeline stage. It exists as a scaffolding concept but produces zero backend commands.

3. **`TypeRefGlobal` is alive in the builder API** but has **no source syntax** — you can't write `let x: "mod".Foo` or `import mod.Foo` in Lalin source. Instead, users write `@{mod.Foo}` splices.

4. **The extern function pattern** (`extern func name() -> T end`) is the closest existing model for a "header": bodyless, type-signature-only, declares an external dependency. But it has no module path — just a linker symbol name. A Lalin header would need to carry a module path and a type-checked signature that another `.mlua` file implements.

5. **Five ModuleHeader states** (`Surface` → `Typed` → `Sem` → `Code`, plus `Open`) indicates that modules progress through named stages. A header file could plausibly produce a `ModuleTyped` or `ModuleSem` without ever reaching `ModuleCode` (since headers have no code to lower).

6. **The `Func` sum type has no bodyless variant** — every `FuncLocal`, `FuncExport`, `FuncLocalContract`, `FuncExportContract`, and `FuncOpen` carries a `body` field. A header function declaration would need either a new `Func` variant or a modification to an existing variant to allow empty/replaced body.

7. **`ItemUseModule` is the workhorse for cross-module references** — it embeds a full `Module` tree and every pipeline stage recursively processes it. This is the pattern a header system would likely extend: compile a header `.mlua` file into a `Module`, then reference it via `ItemUseModule` with the appropriate `use_id`.
