# Moonlift Splicing Architecture — Hard-Pass Redesign

Status: corrected design document. Implementation has not started.

This is a hard refactor plan. It deliberately permits broad schema and phase
breakage. The goal is not to preserve the current text-splice pipeline; the goal
is to replace it with a role-aware ASDL splice pipeline built on MoonOpen slots.

---

## Table of Contents

1.  [Incentive](#1-incentive)
2.  [Non-negotiable invariants](#2-non-negotiable-invariants)
3.  [Current model — what breaks](#3-current-model--what-breaks)
4.  [Target model overview](#4-target-model-overview)
5.  [Architecture diagram](#5-architecture-diagram)
6.  [Hard-refactor decisions](#6-hard-refactor-decisions)
7.  [MoonOpen slots — the central abstraction](#7-moonopen-slots--the-central-abstraction)
8.  [Schema changes](#8-schema-changes)
9.  [Template model and source locations](#9-template-model-and-source-locations)
10. [Parser with holes](#10-parser-with-holes)
11. [Splice roles and coercion](#11-splice-roles-and-coercion)
12. [Host value protocol](#12-host-value-protocol)
13. [Open expansion changes](#13-open-expansion-changes)
14. [Runtime pipeline](#14-runtime-pipeline)
15. [File-by-file plan](#15-file-by-file-plan)
16. [Implementation snippet shapes](#16-implementation-snippet-shapes)
17. [User-facing examples](#17-user-facing-examples)
18. [Migration strategy](#18-migration-strategy)
19. [What is removed](#19-what-is-removed)
20. [Open questions intentionally deferred](#20-open-questions-intentionally-deferred)

---

## 1. Incentive

The current splicing model has several properties that confuse users and create
fragile compiler behavior:

| Problem | Symptom |
|---|---|
| No role enforcement at the splice site | A Lua number `42` splices as raw source text `42` everywhere, including nonsensical positions. |
| Strings mean raw source implicitly | `"i32"` in a type position works by accident; `"hello"` in expression position becomes the identifier `hello`, not a string literal. |
| `moonlift_splice_source()` is the primary protocol | Every value must flatten to source text. ASDL values cannot be injected directly. |
| Source round-trip is the only path | `@{...}` → Lua eval → source string → lex → parse → ASDL. Type and structure information is lost during render. |
| Heuristic expected-splice guessing | `expected_splice()` in `mlua_host_model.lua` guesses splice role from text prefixes. Nested `as(...)`, comma-separated params, and nontrivial grammar contexts fail. |
| Duplicated validation | `host_eval.lua` and `mlua_run.lua` classify and validate splice values independently. |
| Declaration/module splicing is not native | Splicing module items requires raw source strings. |
| Fragment emits use textual name lookup | `emit @{frag}` eventually becomes a string name lookup, not a direct fragment value. |
| Diagnostics lose original locations | Rendered source is parsed after concatenation, so diagnostics point at generated text rather than the `.mlua` site. |

The goal is not to patch these individually. The goal is to replace the semantic
model.

---

## 2. Non-negotiable invariants

1. **A normal splice is never raw source text.**
   A splice evaluates to a Lua value. That Lua value is coerced according to a
   parser-known role into ASDL or into a MoonOpen slot binding.

2. **Raw source is explicit.**
   The only supported raw-source escape is `moon.source("...")`. A bare Lua
   string is never implicitly treated as Moonlift source.

3. **The parser owns role determination.**
   `mlua_host_model.lua` only segments template text and Lua splice expressions.
   It does not guess whether a splice is an expression, type, emit target, name,
   item list, etc.

4. **There is one coercion point.**
   All Lua-value-to-ASDL / Lua-value-to-slot-binding logic lives in
   `lua/moonlift/host_splice.lua`.

5. **MoonOpen slots are the splice-hole representation.**
   Parser holes become `TypeSlot`, `ExprSlot`, `ItemsSlot`, `RegionFragSlot`,
   etc. The host splice layer fills those slots. Open expansion resolves them.

6. **No slot-bearing splice artifact reaches typecheck/lowering/backend.**
   After `open_expand`, the tree may still contain literal wrapper nodes such as
   `NameRefText`, but it must not contain `TSlot`, `ExprSlotValue`,
   `ItemUseItemsSlot`, `RegionFragRefSlot`, `ExprFragRefSlot`, `NameRefSlot`, or
   any unexpanded slot use.

7. **Validation happens before typecheck.**
   If open expansion cannot eliminate every slot-bearing node, the pipeline must
   fail with an open validation issue before typecheck or lowering.

8. **Lua `nil` and `false` are valid splice results.**
   Runtime splice maps must distinguish “missing splice value” from “splice
   value is nil/false”.

9. **Source locations survive template lexing.**
   Template tokens and hole tokens carry original `.mlua` source ranges. The
   parser does not diagnose against synthetic concatenated text.

---

## 3. Current model — what breaks

Current pipeline:

```text
.mlua file
   │
   ▼
mlua_document.lua: segment into LuaOpaque + HostedIsland
   │
   ▼
mlua_host_model.lua: parse_template
   │   ┌── TemplateText("region R() entry start() let y: i32 = ")
   │   ├── TemplateSplice(splice.1, expected=SpliceExpr, lua_source="x")
   │   └── TemplateText("end end")
   │
   ▼
host_eval.lua / mlua_run.lua
   │   ┌── pcall loadstring("return (x)") → Lua value, e.g. 42
   │   ├── classify value with duplicated rules
   │   └── validate against guessed expectation
   │
   ▼
host_template_parse.lua / mlua_run.lua render path
   │   ┌── call moonlift_splice_source() or tostring-ish conversion
   │   ├── concatenate: "... let y: i32 = 42 ..."
   │   └── feed rendered source to parse.lua
   │
   ▼
parse.lua: normal source parser
   │
   ▼
MoonTree / MoonOpen ASDL with no knowledge of splice origin
```

Specific breakages:

- `expected_splice()` is heuristic. It has no real parser state and cannot know
  nested grammatical roles.
- Lua strings are overloaded: sometimes identifiers, sometimes raw source,
  sometimes intended string literals.
- Type host values are flattened to strings even though the ASDL type already
  exists.
- Region/expr fragments are flattened to names and looked up again.
- Diagnostics use post-render offsets.
- Host eval and runtime runner disagree because they each implement their own
  value classification.

---

## 4. Target model overview

```text
.mlua file
   │
   ▼
mlua_document.lua
   │   Segments document into LuaOpaque and HostedIsland.
   │
   ▼
mlua_host_model.lua
   │   Produces HostTemplate parts only:
   │     TemplateText(source occurrence)
   │     TemplateSplicePart(id, lua source occurrence)
   │   No expected role is computed here.
   │
   ▼
parse.lua template lexer
   │   TemplateText       → normal Moonlift tokens with original ranges
   │   TemplateSplicePart → TK.hole token carrying splice id + source range
   │
   ▼
parse.lua template parser
   │   Parser sees TK.hole in real grammar context.
   │   It creates role-specific slot-use nodes and records:
   │     splice_id → MoonOpen.Slot
   │
   ▼
Lua splice eval
   │   Each splice Lua expression is evaluated.
   │   Result map stores present/value, preserving nil and false.
   │
   ▼
host_splice.lua
   │   For each parser-created slot:
   │     coerce Lua value according to slot role
   │     produce MoonOpen.SlotBinding
   │
   ▼
open_expand.lua
   │   Expands slots using the fill set.
   │   Resolves fragment refs, name refs, item slots, type slots, expr slots.
   │
   ▼
open_validate.lua
   │   Fails if any slot-bearing artifact remains.
   │
   ▼
typecheck → layout/lowering → backend
   │   These phases see ordinary expanded ASDL.
```

Key examples:

| Source site | Parser-created slot/use | Host fill |
|---|---|---|
| `x: @{T}` | `Ty.TSlot(TypeSlot(splice.1))` | `SlotBinding(SlotType, SlotValueType(...))` |
| `return @{K}` | `Tr.ExprSlotValue(ExprSlot(splice.2))` | `SlotBinding(SlotExpr, SlotValueExpr(...))` |
| module body `@{items}` | `Tr.ItemUseItemsSlot(ItemsSlot(splice.3))` | `SlotBinding(SlotItems, SlotValueItems(...))` |
| `emit @{frag}(... )` | `Tr.StmtUseRegionFrag(..., RegionFragRefSlot(...))` | `SlotBinding(SlotRegionFrag, SlotValueRegionFrag(...))` |
| expr `emit @{frag}(... )` | `Tr.ExprUseExprFrag(..., ExprFragRefSlot(...))` | `SlotBinding(SlotExprFrag, SlotValueExprFrag(...))` |
| `func @{name}(...` | `NameRefSlot(NameSlot(splice.4))` | `SlotBinding(SlotName, SlotValueName("..."))` |

---

## 5. Architecture diagram

```text
                        .mlua file
                            │
                            ▼
                  ┌─────────────────────┐
                  │  mlua_document.lua  │
                  │  DocumentParts       │
                  └────────┬────────────┘
                           │
                           ▼
                  ┌─────────────────────┐
                  │ mlua_host_model.lua │
                  │ HostTemplate        │
                  │ Text | SplicePart   │
                  │ NO expected role    │
                  └────────┬────────────┘
                           │
                           ▼
                  ┌──────────────────────────────┐
                  │ parse.lua template lexer      │
                  │                              │
                  │ lex_template(template)        │
                  │   Text   → normal tokens      │
                  │   Splice → TK.hole            │
                  │ all tokens have source ranges │
                  └────────┬─────────────────────┘
                           │
                           ▼
                  ┌──────────────────────────────┐
                  │ parse.lua template parser     │
                  │                              │
                  │ consumes TK.hole only in      │
                  │ explicit role-known sites     │
                  │                              │
                  │ emits ASDL slot-use nodes     │
                  │ and splice_slots map          │
                  └────────┬─────────────────────┘
                           │
                           ▼
                  ┌──────────────────────┐
                  │ Lua splice eval      │
                  │                      │
                  │ id → {present,value} │
                  │ nil/false preserved  │
                  └────────┬─────────────┘
                           │
                           ▼
                  ┌──────────────────────┐
                  │ host_splice.lua      │
                  │                      │
                  │ single coercion      │
                  │ point; returns       │
                  │ SlotBinding values   │
                  └────────┬─────────────┘
                           │
                           ▼
                  ┌──────────────────────┐
                  │ open_expand.lua      │
                  │                      │
                  │ resolves all slots   │
                  │ and slot refs        │
                  └────────┬─────────────┘
                           │
                           ▼
                  ┌──────────────────────┐
                  │ open_validate.lua    │
                  │                      │
                  │ rejects leftovers    │
                  └────────┬─────────────┘
                           │
                           ▼
                  ┌──────────────────────┐
                  │ typecheck/lower/back │
                  └──────────────────────┘
```

---

## 6. Hard-refactor decisions

This section resolves the implementation gaps that would otherwise make the
redesign ambiguous.

### 6.1 Expression slots have optional type

Current `ExprSlot` and `PlaceSlot` have mandatory `ty` fields. That does not fit
parser-created expression holes because the parser often does not know the
expected type.

Refactor:

```lua
A.product "ExprSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.field "ty" (A.optional "MoonType.Type"),
    A.unique,
}

A.product "PlaceSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.field "ty" (A.optional "MoonType.Type"),
    A.unique,
}
```

Typecheck should never need to infer an unexpanded splice slot in the normal
pipeline because `open_expand + open_validate` runs first. If an unexpanded slot
leaks into typecheck, typecheck reports a hard open-pipeline bug or an explicit
unexpanded-slot issue.

### 6.2 Name splices require a real name reference type

A `NameSlot` cannot be returned where the schema expects a raw Lua string. This
is corrected by adding `MoonOpen.NameRef` and changing only the AST fields that
can legally contain spliceable names.

Do **not** make `expect_name()` globally return a slot. Most parser name sites
still require concrete strings: local variable names, parameter names, field
names, import path components, etc. Instead, add role-specific parser functions:

```lua
Parser:parse_name_ref(site)       -- accepts TK.name or TK.hole
Parser:expect_plain_name(site)    -- accepts only concrete token names
```

Schema:

```lua
A.product "NameSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.unique,
}

A.sum "NameRef" {
    A.variant "NameRefText" {
        A.field "text" "string",
        A.variant_unique,
    },
    A.variant "NameRefSlot" {
        A.field "slot" "MoonOpen.NameSlot",
        A.variant_unique,
    },
}
```

Fields that become `NameRef` include declarations and labels where user-facing
identifier splicing is wanted:

- `MoonTree.FuncLocal.name`
- `MoonTree.FuncExport.name`
- `MoonTree.FuncLocalContract.name`
- `MoonTree.FuncExportContract.name`
- `MoonTree.ExternFunc.name` where it is a Moonlift identifier
- `MoonTree.ConstItem.name`
- `MoonTree.StaticItem.name`
- `MoonTree.TypeDecl*.name`
- `MoonTree.BlockLabel.name`
- `MoonOpen.ExprFrag.name`
- `MoonOpen.RegionFrag.name`

Fields that remain plain strings unless specifically redesigned later:

- local bindings and parameter names
- field names
- extern symbol strings
- import path text
- generated internal ids and use ids

After expansion, every `NameRefSlot` must become `NameRefText`. Downstream phases
use a helper such as `name_text(ref)` and should assert that slot refs are gone.

### 6.3 Fragment emit splicing uses ref sums, not parallel node variants

Use one representation:

```lua
RegionFragRef = RegionFragRefName | RegionFragRefSlot
ExprFragRef   = ExprFragRefName   | ExprFragRefSlot
```

Then change existing nodes:

```lua
StmtUseRegionFrag { ..., frag: MoonOpen.RegionFragRef, ... }
ExprUseExprFrag   { ..., frag: MoonOpen.ExprFragRef,   ... }
```

Do **not** add separate `StmtUseRegionFragSlot` and `ExprUseExprFragSlot` nodes.
That duplicates the representation and complicates every phase.

### 6.4 ASDL sum dispatch must use actual variant classes

This is wrong:

```lua
if pvm.classof(slot) == O.Slot then ... end
```

`pvm.classof(O.SlotType(...))` is `O.SlotType`, not `O.Slot`.

Correct approaches:

```lua
local cls = pvm.classof(slot)
if cls == O.SlotType then ... end
if cls == O.SlotExpr then ... end
```

or:

```lua
if O.Slot:isclassof(slot) then ... end
```

The new `host_splice.lua` must dispatch on concrete slot wrapper variants
(`O.SlotType`, `O.SlotExpr`, etc.) and direct slot products where useful.

### 6.5 Runtime splice maps preserve nil and false

Never use this for splice results:

```lua
luamap[id] = fn()
assert(luamap[id])
```

It loses nil and rejects false. Use records:

```lua
local ok, value = pcall(fn)
if ok then
    luamap[id] = { present = true, value = value }
else
    issues[#issues + 1] = ...
end
```

Lookup:

```lua
local rec = luamap[id]
if not rec or not rec.present then error("missing splice value: " .. id) end
local value = rec.value -- may be nil or false
```

### 6.6 Runtime stores host values separately from ASDL fragment envs

Current `mlua_run.lua` stores fragment host values in maps for Lua visibility.
`open_expand` expects arrays of `MoonOpen.RegionFrag` and `MoonOpen.ExprFrag`.

The hard refactor should split these explicitly:

```lua
runtime.host_region_values_by_name = { name → RegionFragValue }
runtime.host_expr_values_by_name   = { name → ExprFragValue }

runtime.region_frags_asdl = { RegionFrag, ... }
runtime.expr_frags_asdl   = { ExprFrag, ... }
```

When a host fragment value is adopted, register both the host value and its ASDL
fragment.

### 6.7 `moon.source` remains explicit but is not the primary protocol

The invariant “a splice is never source text” means normal values do not render
to source. `moon.source("...")` is the explicit escape hatch. It is parsed at
the coercion point into ASDL for the required role and then filled as ASDL.

So `moon.source` is permitted, but it is an explicit parse step inside
`host_splice.lua`, not implicit text concatenation.

---

## 7. MoonOpen slots — the central abstraction

Moonlift already has a slot/fill system. A splice hole is a parser-created slot
plus a later slot binding.

### 7.1 Existing slot families

Current `schema/open.lua` already contains:

```text
TypeSlot       { key, pretty_name }
ValueSlot      { key, pretty_name, ty }
ExprSlot       { key, pretty_name, ty }
PlaceSlot      { key, pretty_name, ty }
DomainSlot     { key, pretty_name }
RegionSlot     { key, pretty_name }
ContSlot       { key, pretty_name, params }
FuncSlot       { key, pretty_name, fn_ty }
ConstSlot      { key, pretty_name, ty }
StaticSlot     { key, pretty_name, ty }
TypeDeclSlot   { key, pretty_name }
ItemsSlot      { key, pretty_name }
ModuleSlot     { key, pretty_name }
```

The refactor adjusts `ExprSlot.ty` and `PlaceSlot.ty` to optional and adds:

```text
RegionFragSlot { key, pretty_name }
ExprFragSlot   { key, pretty_name }
NameSlot       { key, pretty_name }
```

### 7.2 Slot sum

Existing variants remain:

```text
SlotType
SlotValue
SlotExpr
SlotPlace
SlotDomain
SlotRegion
SlotCont
SlotFunc
SlotConst
SlotStatic
SlotTypeDecl
SlotItems
SlotModule
```

Add:

```text
SlotRegionFrag
SlotExprFrag
SlotName
```

### 7.3 Slot values

Existing variants remain:

```text
SlotValueType       { ty }
SlotValueExpr       { expr }
SlotValuePlace      { place }
SlotValueDomain     { domain }
SlotValueRegion     { body }
SlotValueCont       { label }
SlotValueContSlot   { slot }
SlotValueFunc       { func }
SlotValueConst      { c }
SlotValueStatic     { s }
SlotValueTypeDecl   { t }
SlotValueItems      { items }
SlotValueModule     { module }
```

Add:

```text
SlotValueRegionFrag { frag: MoonOpen.RegionFrag }
SlotValueExprFrag   { frag: MoonOpen.ExprFrag }
SlotValueName       { text: string }
```

### 7.4 Slot use nodes

Examples of existing slot-use nodes:

```text
MoonType.TSlot
MoonTree.ExprSlotValue
MoonTree.PlaceSlotValue
MoonTree.DomainSlotValue
MoonTree.StmtUseRegionSlot
MoonTree.ItemUseItemsSlot
MoonTree.ItemUseModuleSlot
```

New or changed ref-based uses:

```text
MoonOpen.NameRefSlot
MoonOpen.RegionFragRefSlot
MoonOpen.ExprFragRefSlot
```

---

## 8. Schema changes

### 8.1 `lua/moonlift/schema/open.lua`

Add name refs and fragment refs:

```lua
A.product "NameSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.unique,
}

A.sum "NameRef" {
    A.variant "NameRefText" {
        A.field "text" "string",
        A.variant_unique,
    },
    A.variant "NameRefSlot" {
        A.field "slot" "MoonOpen.NameSlot",
        A.variant_unique,
    },
}

A.product "RegionFragSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.unique,
}

A.product "ExprFragSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.unique,
}

A.sum "RegionFragRef" {
    A.variant "RegionFragRefName" {
        A.field "name" "MoonOpen.NameRef",
        A.variant_unique,
    },
    A.variant "RegionFragRefSlot" {
        A.field "slot" "MoonOpen.RegionFragSlot",
        A.variant_unique,
    },
}

A.sum "ExprFragRef" {
    A.variant "ExprFragRefName" {
        A.field "name" "MoonOpen.NameRef",
        A.variant_unique,
    },
    A.variant "ExprFragRefSlot" {
        A.field "slot" "MoonOpen.ExprFragSlot",
        A.variant_unique,
    },
}
```

Change expression/place slots:

```lua
A.product "ExprSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.field "ty" (A.optional "MoonType.Type"),
    A.unique,
}

A.product "PlaceSlot" {
    A.field "key" "string",
    A.field "pretty_name" "string",
    A.field "ty" (A.optional "MoonType.Type"),
    A.unique,
}
```

Extend `Slot`:

```lua
A.variant "SlotRegionFrag" {
    A.field "slot" "MoonOpen.RegionFragSlot",
    A.variant_unique,
},
A.variant "SlotExprFrag" {
    A.field "slot" "MoonOpen.ExprFragSlot",
    A.variant_unique,
},
A.variant "SlotName" {
    A.field "slot" "MoonOpen.NameSlot",
    A.variant_unique,
},
```

Extend `SlotValue`:

```lua
A.variant "SlotValueRegionFrag" {
    A.field "frag" "MoonOpen.RegionFrag",
    A.variant_unique,
},
A.variant "SlotValueExprFrag" {
    A.field "frag" "MoonOpen.ExprFrag",
    A.variant_unique,
},
A.variant "SlotValueName" {
    A.field "text" "string",
    A.variant_unique,
},
```

Change fragment names to `NameRef` if fragment definitions can be name-spliced:

```lua
A.product "ExprFrag" {
    A.field "name" "MoonOpen.NameRef",
    ...
}

A.product "RegionFrag" {
    A.field "name" "MoonOpen.NameRef",
    ...
}
```

If this is too invasive for the first commit, keep fragment definition names
plain strings initially and allow slot refs only at use sites. The final hard
refactor should make names consistently `NameRef` where user-facing declaration
name splicing is supported.

### 8.2 `lua/moonlift/schema/tree.lua`

Change fragment use nodes:

```lua
-- Before:
A.variant "StmtUseRegionFrag" {
    A.field "h" "MoonTree.StmtHeader",
    A.field "use_id" "string",
    A.field "frag_name" "string",
    A.field "args" (A.many "MoonTree.Expr"),
    A.field "fills" (A.many "MoonOpen.SlotBinding"),
    A.field "cont_fills" (A.many "MoonOpen.ContBinding"),
    A.variant_unique,
}

-- After:
A.variant "StmtUseRegionFrag" {
    A.field "h" "MoonTree.StmtHeader",
    A.field "use_id" "string",
    A.field "frag" "MoonOpen.RegionFragRef",
    A.field "args" (A.many "MoonTree.Expr"),
    A.field "fills" (A.many "MoonOpen.SlotBinding"),
    A.field "cont_fills" (A.many "MoonOpen.ContBinding"),
    A.variant_unique,
}
```

```lua
-- Before:
A.variant "ExprUseExprFrag" {
    A.field "h" "MoonTree.ExprHeader",
    A.field "use_id" "string",
    A.field "frag_name" "string",
    A.field "args" (A.many "MoonTree.Expr"),
    A.field "fills" (A.many "MoonOpen.SlotBinding"),
    A.variant_unique,
}

-- After:
A.variant "ExprUseExprFrag" {
    A.field "h" "MoonTree.ExprHeader",
    A.field "use_id" "string",
    A.field "frag" "MoonOpen.ExprFragRef",
    A.field "args" (A.many "MoonTree.Expr"),
    A.field "fills" (A.many "MoonOpen.SlotBinding"),
    A.variant_unique,
}
```

Change selected declaration and label names to `MoonOpen.NameRef`:

```lua
A.product "BlockLabel" {
    A.field "name" "MoonOpen.NameRef",
    A.unique,
}

A.variant "FuncLocal" {
    A.field "name" "MoonOpen.NameRef",
    ...
}

A.variant "FuncExport" {
    A.field "name" "MoonOpen.NameRef",
    ...
}

A.variant "ConstItem" {
    A.field "name" "MoonOpen.NameRef",
    ...
}

A.variant "StaticItem" {
    A.field "name" "MoonOpen.NameRef",
    ...
}

A.variant "TypeDeclStruct" {
    A.field "name" "MoonOpen.NameRef",
    ...
}
```

Every phase that currently reads `node.name` as a string must use a helper:

```lua
local function name_text(O, ref)
    local cls = pvm.classof(ref)
    if cls == O.NameRefText then return ref.text end
    error("unexpanded name slot", 2)
end
```

During transition, constructors/helpers can wrap literal strings:

```lua
local function N(O, text) return O.NameRefText(text) end
```

### 8.3 `lua/moonlift/schema/type.lua`

`TypeRefPath` currently uses `MoonCore.Path`, which is a concrete path of names.
Type-position splices should use `TSlot`, not path-component splices. Therefore
no path-component name slot is needed for type names in the first design.

`TypeRefSlot` already exists and can remain as a lower-level open type ref.
Parser-created type splices use `Ty.TSlot(TypeSlot(...))`.

Array lengths can support holes later using existing `ArrayLenSlot`. If `@{n}`
is parsed in array length position, create an `ExprSlot` and wrap it as
`ArrayLenSlot` or `ArrayLenExpr(ExprSlotValue(...))` depending on current type
semantics.

### 8.4 `lua/moonlift/schema/host.lua`

Remove splice expectations from templates:

```lua
-- Remove entirely:
A.sum "SpliceExpectation" { ... }
```

Change `TemplateSplice`:

```lua
A.product "TemplateSplice" {
    A.field "id" "string",
    A.field "lua_source" "MoonSource.SourceOccurrence",
    A.unique,
}
```

Change `TemplatePartText` to carry source occurrence/range, not only text:

```lua
A.product "TemplatePartText" {
    A.field "source" "MoonSource.SourceOccurrence",
    A.unique,
}
```

Add parser output records:

```lua
A.product "TemplateSpliceSlot" {
    A.field "splice_id" "string",
    A.field "slot" "MoonOpen.Slot",
    A.field "role" "string",       -- diagnostic/debug only
    A.field "site" "MoonSource.SourceRange",
    A.unique,
}

A.product "TemplateParseWithSlots" {
    A.field "splice_slots" (A.many "MoonHost.TemplateSpliceSlot"),
    A.unique,
}
```

`HostSpliceResult` should no longer carry an expected role. It can either be
removed from the runtime path or simplified to:

```lua
A.product "HostSpliceValue" {
    A.field "splice_id" "string",
    A.field "ref" "MoonHost.HostValueRef",
    A.unique,
}
```

For `mlua_run.lua`, a plain Lua table map is acceptable because this path is an
execution boundary rather than a persistent ASDL report.

### 8.5 `lua/moonlift/schema/source.lua`

`SourceSlice` can stay as text, but template parts need occurrences. The
host-model builder must compute `SourceOccurrence` for every text and splice
part from the parent document range.

If exact UTF-16 columns are not needed immediately, store byte offsets correctly
first and compute full `SourceRange` through existing source-position utilities.

---

## 9. Template model and source locations

### 9.1 Responsibilities

`mlua_host_model.lua` must only do lexical template segmentation:

- copy literal Moonlift text into `TemplateText`
- copy Lua antiquote source into `TemplateSplice`
- assign stable splice ids: `splice.1`, `splice.2`, ...
- attach original source ranges

It must not inspect surrounding Moonlift grammar.

### 9.2 Template parts

```text
HostTemplate
  kind_word: "region" | "expr" | "module" | "func" | ...
  parts:
    TemplateText(SourceOccurrence)
    TemplateSplicePart(TemplateSplice(id, lua_source_occurrence))
```

The `TemplateSplice` source occurrence covers only the Lua expression inside
`@{...}`. The generated `TK.hole` token should use the full antiquote range if
available, or at least the `@{` start position, so diagnostics point to the
splice site.

### 9.3 Template lexer

The template lexer is not `table.concat(parts)` followed by normal `lex`. It is
a token-buffer builder:

```lua
function M.lex_template(template)
    local toks = new_token_buffer()
    for _, part in ipairs(template.parts) do
        if pvm.classof(part) == H.TemplateText then
            lex_text_occurrence_into(toks, part.text.source)
        elseif pvm.classof(part) == H.TemplateSplicePart then
            push_hole_token(toks, part.splice.id, part.splice.lua_source.range)
        end
    end
    push_eof(toks)
    return toks
end
```

Important details:

- tokens keep original start/stop/line/col
- hole tokens keep splice id in `toks.text[i]`
- hole tokens keep a source range suitable for diagnostics
- the token buffer may have no single `src` string; parser errors must rely on
  token ranges, not string offsets into synthetic text

---

## 10. Parser with holes

### 10.1 Token kind

Add:

```lua
TK.hole = 999
```

`self:text()` on a hole returns the splice id.

### 10.2 Parser state

Parser instances gain:

```lua
splice_slots = {},       -- array of MoonHost.TemplateSpliceSlot
splice_slots_by_id = {}, -- optional duplicate check
```

Helper:

```lua
function Parser:record_splice_slot(splice_id, slot_sum, role)
    if self.splice_slots_by_id[splice_id] then
        self:issue("duplicate splice id: " .. splice_id)
    end
    local site = self:current_range()
    local ss = self.H.TemplateSpliceSlot(splice_id, slot_sum, role, site)
    self.splice_slots[#self.splice_slots + 1] = ss
    self.splice_slots_by_id[splice_id] = ss
    return ss
end
```

Slot key helper:

```lua
function Parser:splice_key(role, id)
    return "splice:" .. role .. ":" .. tostring(id)
end
```

### 10.3 Type position

```lua
function Parser:parse_type()
    if self:kind() == TK.hole then
        local id = self:text()
        self.i = self.i + 1
        local slot = self.O.TypeSlot(self:splice_key("type", id), id)
        self:record_splice_slot(id, self.O.SlotType(slot), "type")
        return self.Ty.TSlot(slot)
    end

    -- normal type parsing...
end
```

`"i32"` as a Lua string in this position is an error. User must pass `moon.i32`
or `moon.source("i32")`.

### 10.4 Expression prefix position

```lua
function Parser:parse_prefix_expr()
    if self:kind() == TK.hole then
        local id = self:text()
        self.i = self.i + 1
        local slot = self.O.ExprSlot(self:splice_key("expr", id), id, pvm.NIL)
        self:record_splice_slot(id, self.O.SlotExpr(slot), "expr")
        return self.Tr.ExprSlotValue(self.Tr.ExprSurface, slot)
    end

    -- normal prefix expression parsing...
end
```

Expression slot fill rules:

| Lua value | Expr ASDL |
|---|---|
| number integer-ish | `ExprLit(LitInt(raw))` |
| number non-integer | `ExprLit(LitFloat(raw))` |
| boolean | `ExprLit(LitBool(value))` |
| nil | `ExprLit(LitNil)` |
| string | `ExprLit(LitString(bytes))` |
| expression host value | its ASDL expr |
| `moon.source("...")` | parse as expression source, then ASDL |

### 10.5 Name positions

Do not change generic `expect_name()` to accept holes. Add:

```lua
function Parser:parse_name_ref(msg)
    if self:kind() == TK.hole then
        local id = self:text()
        self.i = self.i + 1
        local slot = self.O.NameSlot(self:splice_key("name", id), id)
        self:record_splice_slot(id, self.O.SlotName(slot), "name")
        return self.O.NameRefSlot(slot)
    end
    return self.O.NameRefText(self:expect_name(msg))
end
```

Use `parse_name_ref()` only at name-splice-enabled sites, for example:

- function declaration names
- type declaration names
- const/static item names
- region/expr fragment declaration names
- block labels, if label splicing is supported

For local variables and parameters, keep plain concrete strings until there is a
clear reason to support name splices there.

### 10.6 Emit region fragment target

```lua
function Parser:parse_region_frag_ref()
    if self:kind() == TK.hole then
        local id = self:text()
        self.i = self.i + 1
        local slot = self.O.RegionFragSlot(self:splice_key("region_frag", id), id)
        self:record_splice_slot(id, self.O.SlotRegionFrag(slot), "region_frag")
        return self.O.RegionFragRefSlot(slot), "splice." .. id
    end

    local name = self.O.NameRefText(self:expect_name("expected region fragment name"))
    return self.O.RegionFragRefName(name), name.text
end

function Parser:parse_emit_stmt()
    local frag_ref, use_suffix = self:parse_region_frag_ref()
    local args, fills, cont_fills = self:parse_emit_args_and_fills()
    return self.Tr.StmtUseRegionFrag(
        self.Tr.StmtSurface,
        "emit." .. tostring(use_suffix) .. "." .. tostring(self.i),
        frag_ref,
        args,
        fills,
        cont_fills)
end
```

### 10.7 Emit expression fragment target

```lua
function Parser:parse_expr_frag_ref()
    if self:kind() == TK.hole then
        local id = self:text()
        self.i = self.i + 1
        local slot = self.O.ExprFragSlot(self:splice_key("expr_frag", id), id)
        self:record_splice_slot(id, self.O.SlotExprFrag(slot), "expr_frag")
        return self.O.ExprFragRefSlot(slot), "splice." .. id
    end

    local name = self.O.NameRefText(self:expect_name("expected expression fragment name"))
    return self.O.ExprFragRefName(name), name.text
end
```

### 10.8 Module item position

`parse_module_item()` should return an array because a single hole can expand to
zero, one, or many module items.

```lua
function Parser:parse_module_item()
    self:skip_nl()
    if self:kind() == TK.hole then
        local id = self:text()
        self.i = self.i + 1
        local slot = self.O.ItemsSlot(self:splice_key("items", id), id)
        self:record_splice_slot(id, self.O.SlotItems(slot), "module_items")
        return { self.Tr.ItemUseItemsSlot(slot) }
    end

    -- normal item parsing returns { item }
end
```

### 10.9 Region body statement splice

A hole in statement position inside a region body can mean “splice region
statements”, using existing `RegionSlot`:

```lua
function Parser:parse_stmt()
    self:skip_nl()
    if self:kind() == TK.hole then
        local id = self:text()
        self.i = self.i + 1
        local slot = self.O.RegionSlot(self:splice_key("region_body", id), id)
        self:record_splice_slot(id, self.O.SlotRegion(slot), "region_body")
        return self.Tr.StmtUseRegionSlot(self.Tr.StmtSurface, slot)
    end

    -- normal statement parsing...
end
```

This is separate from `emit @{frag}(... )`, which splices a fragment value and
uses continuation/param semantics.

### 10.10 Template parse entrypoints

Add new entrypoints alongside or replacing source-only parsers:

```lua
Parse.parse_module_template(template, opts)
Parse.parse_func_template(template, opts)
Parse.parse_region_frag_template(template, opts)
Parse.parse_expr_frag_template(template, opts)
```

Return shapes:

```lua
{
    value = ...,              -- module / func / region parse product / expr parse product
    splice_slots = { ... },   -- array of TemplateSpliceSlot
    issues = { ... },
    anchors = ...,            -- if applicable
}
```

For backward-compatible internal parse functions, source-only entrypoints can
still call the same parser with `M.lex(src)` and no hole tokens.

---

## 11. Splice roles and coercion

### 11.1 New module: `lua/moonlift/host_splice.lua`

This is the only module that turns Lua values into MoonOpen slot bindings.

Inputs:

```lua
Splice.fill(session, slot_sum_or_slot, value, site)
```

Output:

```lua
MoonOpen.SlotBinding
```

`slot_sum_or_slot` may be either an `O.Slot*` wrapper or a direct slot product.
The parser records wrapper variants (`O.SlotType(slot)` etc.), so the primary
path should dispatch on wrapper variants.

### 11.2 Roles

| Slot wrapper | Role string | Fill function |
|---|---|---|
| `O.SlotType` | `type` | `fill_type` |
| `O.SlotExpr` | `expr` | `fill_expr` |
| `O.SlotPlace` | `place` | `fill_place` |
| `O.SlotDomain` | `domain` | `fill_domain` |
| `O.SlotRegion` | `region_body` | `fill_region_body` |
| `O.SlotRegionFrag` | `region_frag` | `fill_region_frag` |
| `O.SlotExprFrag` | `expr_frag` | `fill_expr_frag` |
| `O.SlotName` | `name` | `fill_name` |
| `O.SlotItems` | `module_items` | `fill_items` |
| `O.SlotModule` | `module` | `fill_module` |
| `O.SlotFunc` | `func` | `fill_func` |
| `O.SlotConst` | `const` | `fill_const` |
| `O.SlotStatic` | `static` | `fill_static` |
| `O.SlotTypeDecl` | `type_decl` | `fill_type_decl` |
| `O.SlotCont` | `cont` | `fill_cont` |

### 11.3 Dispatch shape

```lua
local pvm = require("moonlift.pvm")

local M = {}

function M.fill(session, slot, value, site)
    local O = session.T.MoonOpen
    local cls = pvm.classof(slot)

    -- Slot sum variants, preferred parser representation.
    if cls == O.SlotType then return M.fill_type(session, slot.slot, value, site) end
    if cls == O.SlotExpr then return M.fill_expr(session, slot.slot, value, site) end
    if cls == O.SlotPlace then return M.fill_place(session, slot.slot, value, site) end
    if cls == O.SlotDomain then return M.fill_domain(session, slot.slot, value, site) end
    if cls == O.SlotRegion then return M.fill_region_body(session, slot.slot, value, site) end
    if cls == O.SlotRegionFrag then return M.fill_region_frag(session, slot.slot, value, site) end
    if cls == O.SlotExprFrag then return M.fill_expr_frag(session, slot.slot, value, site) end
    if cls == O.SlotName then return M.fill_name(session, slot.slot, value, site) end
    if cls == O.SlotItems then return M.fill_items(session, slot.slot, value, site) end
    if cls == O.SlotModule then return M.fill_module(session, slot.slot, value, site) end
    if cls == O.SlotFunc then return M.fill_func(session, slot.slot, value, site) end
    if cls == O.SlotConst then return M.fill_const(session, slot.slot, value, site) end
    if cls == O.SlotStatic then return M.fill_static(session, slot.slot, value, site) end
    if cls == O.SlotTypeDecl then return M.fill_type_decl(session, slot.slot, value, site) end
    if cls == O.SlotCont then return M.fill_cont(session, slot.slot, value, site) end

    -- Direct slot products are accepted for convenience/tests.
    if cls == O.TypeSlot then return M.fill_type(session, slot, value, site) end
    if cls == O.ExprSlot then return M.fill_expr(session, slot, value, site) end
    if cls == O.ItemsSlot then return M.fill_items(session, slot, value, site) end
    if cls == O.RegionFragSlot then return M.fill_region_frag(session, slot, value, site) end
    if cls == O.ExprFragSlot then return M.fill_expr_frag(session, slot, value, site) end
    if cls == O.NameSlot then return M.fill_name(session, slot, value, site) end

    error((site or "splice") .. ": unsupported splice slot " .. tostring(slot), 2)
end
```

### 11.4 Type slot coercion

Accepted:

- host type value (`as_type_value()` or canonical type value)
- direct `MoonType.Type` ASDL node
- explicit `moon.source("...")`, parsed as a type

Rejected:

- bare string
- number/boolean/nil
- fragment values

```lua
function M.fill_type(session, slot, value, site)
    local T = session.T
    local O, Ty = T.MoonOpen, T.MoonType

    local ty = nil

    if type(value) == "table" and type(value.as_type_value) == "function" then
        ty = value:as_type_value().ty
    elseif type(value) == "table" and Ty.Type:isclassof(value) then
        ty = value
    elseif M.is_source(value) then
        ty = M.parse_source_as_type(session, value.source, site)
    end

    if not ty then
        error((site or "splice") .. ": expected type value, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotType(slot), O.SlotValueType(ty))
end
```

### 11.5 Expression slot coercion

Accepted:

- number → integer or float literal
- boolean → bool literal
- nil → nil literal
- string → string literal
- expression host value
- direct `MoonTree.Expr` ASDL node
- explicit `moon.source("...")`, parsed as expression

```lua
function M.fill_expr(session, slot, value, site)
    local T = session.T
    local C, Tr, O = T.MoonCore, T.MoonTree, T.MoonOpen
    local tv = type(value)
    local expr = nil

    if tv == "number" then
        local raw = tostring(value)
        if value == math.floor(value) then
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitInt(raw))
        else
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitFloat(raw))
        end
    elseif tv == "boolean" then
        expr = Tr.ExprLit(Tr.ExprSurface, C.LitBool(value))
    elseif tv == "nil" then
        expr = Tr.ExprLit(Tr.ExprSurface, C.LitNil)
    elseif tv == "string" then
        expr = Tr.ExprLit(Tr.ExprSurface, C.LitString(value))
    elseif type(value) == "table" and type(value.as_expr_value) == "function" then
        expr = value:as_expr_value().expr
    elseif type(value) == "table" and Tr.Expr:isclassof(value) then
        expr = value
    elseif M.is_source(value) then
        expr = M.parse_source_as_expr(session, value.source, site)
    end

    if not expr then
        error((site or "splice") .. ": expected expression value, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotExpr(slot), O.SlotValueExpr(expr))
end
```

### 11.6 Name slot coercion

Accepted:

- bare Lua string matching Moonlift identifier grammar
- host value implementing `moonlift_splice("name", ...)`

Rejected:

- `moon.source(...)` by default. Source and identifiers are intentionally
  separate. If a raw identifier escape is desired, use `moon.ident("...")` or
  just a bare string in a name role.

```lua
local ident_pat = "^[_%a][_%w]*$"

function M.fill_name(session, slot, value, site)
    local O = session.T.MoonOpen
    if type(value) ~= "string" then
        error((site or "splice") .. ": expected identifier string, got " .. M.kind_of(value), 2)
    end
    if not value:match(ident_pat) then
        error((site or "splice") .. ": invalid Moonlift identifier " .. string.format("%q", value), 2)
    end
    return O.SlotBinding(O.SlotName(slot), O.SlotValueName(value))
end
```

### 11.7 Region body slot coercion

A `RegionSlot` means “inline these statements here”, not “emit a fragment”.

Accepted:

- region body host value, if one exists
- array of `MoonTree.Stmt`
- explicit `moon.source("...")`, parsed as statement list

Output:

```lua
O.SlotBinding(O.SlotRegion(slot), O.SlotValueRegion(stmts))
```

### 11.8 Region fragment slot coercion

A `RegionFragSlot` means `emit @{frag}(... )` target.

Accepted:

- canonical region fragment host value
- direct `MoonOpen.RegionFrag` ASDL node

Output:

```lua
O.SlotBinding(O.SlotRegionFrag(slot), O.SlotValueRegionFrag(frag))
```

Do not lower this to `SlotValueRegion(body)`. Fragment emit expansion requires
fragment params, continuations, open slots, entry block, and blocks.

### 11.9 Expression fragment slot coercion

Accepted:

- expression fragment host value
- direct `MoonOpen.ExprFrag` ASDL node

Output:

```lua
O.SlotBinding(O.SlotExprFrag(slot), O.SlotValueExprFrag(frag))
```

### 11.10 Module item slot coercion

Accepted:

- array of `MoonTree.Item`
- single `MoonTree.Item`
- module host value
- direct `MoonTree.Module`
- explicit `moon.source("...")`, parsed as module body/items
- higher-level host builders that can produce items

Output:

```lua
O.SlotBinding(O.SlotItems(slot), O.SlotValueItems(items))
```

Empty arrays are valid and splice zero items.

### 11.11 Source escape parsing

`moon.source` coercion must parse the string according to the requested role:

| Role | Parser function |
|---|---|
| type | `Parse.parse_type_source(source)` or parser helper |
| expr | `Parse.parse_expr(source)` |
| region_body | `Parse.parse_stmt_list(source)` |
| module_items | `Parse.parse_module(source)` / body-only helper |

Source escape parse errors are reported at the splice site and include the
source string parse issue.

---

## 12. Host value protocol

`host_splice.lua` owns final coercion. Host values may participate by exposing:

```lua
value:moonlift_splice(role, session, site)
```

This method returns a role-appropriate ASDL value or a primitive string for
`name`. It does **not** return source text except for `SourceValue`, whose whole
purpose is explicit source escape.

### 12.1 Dispatch policy

For each role, `host_splice` should check obvious primitive/direct ASDL cases
first, then call protocol methods for host wrapper values.

```lua
local function protocol(value, role, session, site)
    if (type(value) == "table" or type(value) == "userdata")
       and type(value.moonlift_splice) == "function" then
        return value:moonlift_splice(role, session, site)
    end
    return nil
end
```

### 12.2 TypeValue

```lua
function TypeValue:moonlift_splice(role, session, site)
    if role == "type" then return self.ty end
    error((site or "splice") .. ": type value cannot splice as " .. role, 2)
end
```

### 12.3 RegionFragValue

```lua
function RegionFragValue:moonlift_splice(role, session, site)
    if role == "region_frag" then return self.frag end
    if role == "module_items" then
        -- Optional: expose generated fragment declaration as item(s), if the
        -- compiler represents fragment declarations as module items in the new
        -- schema. Otherwise reject.
    end
    error((site or "splice") .. ": region fragment cannot splice as " .. role, 2)
end
```

### 12.4 ExprFragValue

```lua
function ExprFragValue:moonlift_splice(role, session, site)
    if role == "expr_frag" then return self.frag end
    error((site or "splice") .. ": expression fragment cannot splice as " .. role, 2)
end
```

### 12.5 SourceValue

```lua
function SourceValue:moonlift_splice(role, session, site)
    if role == "expr" or role == "type" or role == "region_body" or role == "module_items" then
        return self
    end
    error((site or "splice") .. ": source cannot splice as " .. role, 2)
end
```

### 12.6 ModuleValue / FuncValue / StructValue

Each high-level host value should implement only the roles it semantically
supports:

- ModuleValue → `module`, `module_items`
- FuncValue → `func`, maybe `module_items`
- StructValue → `type`, `type_decl`, maybe `module_items`

No host value should implement fallback raw source splicing as its primary
behavior.

---

## 13. Open expansion changes

### 13.1 Lookup slot value

Add cases to `lookup_slot_value`:

```lua
[O.SlotRegionFrag] = function(self, env)
    local v = slot_value(self, env)
    if v == nil then return pvm.empty() end
    return pvm.once(v)
end,

[O.SlotExprFrag] = function(self, env)
    local v = slot_value(self, env)
    if v == nil then return pvm.empty() end
    return pvm.once(v)
end,

[O.SlotName] = function(self, env)
    local v = slot_value(self, env)
    if v == nil then return pvm.empty() end
    return pvm.once(v)
end,
```

### 13.2 Name expansion

Add:

```lua
local expand_name_ref

expand_name_ref = pvm.phase("moonlift_open_expand_name_ref", {
    [O.NameRefText] = function(self) return pvm.once(self) end,
    [O.NameRefSlot] = function(self, env)
        local values = pvm.drain(lookup_slot_value(O.SlotName(self.slot), env))
        if #values == 1 and pvm.classof(values[1]) == O.SlotValueName then
            return pvm.once(O.NameRefText(values[1].text))
        end
        return pvm.once(self)
    end,
}, { args_cache = "last" })
```

Every expander for a node with `NameRef` fields must call `expand_name_ref`.

### 13.3 Fragment ref resolution

Add helpers:

```lua
local function name_ref_text(ref, env)
    local expanded = one(expand_name_ref, ref, env)
    if pvm.classof(expanded) == O.NameRefText then return expanded.text end
    return nil
end

local function lookup_region_frag_ref(ref, env)
    local cls = pvm.classof(ref)
    if cls == O.RegionFragRefName then
        local name = name_ref_text(ref.name, env)
        if not name then return pvm.NIL end
        return lookup_region_frag(name, env)
    elseif cls == O.RegionFragRefSlot then
        local values = pvm.drain(lookup_slot_value(O.SlotRegionFrag(ref.slot), env))
        if #values == 1 and pvm.classof(values[1]) == O.SlotValueRegionFrag then
            return values[1].frag
        end
        return pvm.NIL
    end
    return pvm.NIL
end

local function lookup_expr_frag_ref(ref, env)
    local cls = pvm.classof(ref)
    if cls == O.ExprFragRefName then
        local name = name_ref_text(ref.name, env)
        if not name then return pvm.NIL end
        return lookup_expr_frag(name, env)
    elseif cls == O.ExprFragRefSlot then
        local values = pvm.drain(lookup_slot_value(O.SlotExprFrag(ref.slot), env))
        if #values == 1 and pvm.classof(values[1]) == O.SlotValueExprFrag then
            return values[1].frag
        end
        return pvm.NIL
    end
    return pvm.NIL
end
```

### 13.4 Region fragment expansion must change the special region path

Current `open_expand.lua` expands region fragment uses in `expand_region_stmts`,
not merely in the generic `expand_stmt` phase. Therefore update
`expand_region_frag_use()`:

```lua
local function expand_region_frag_use(stmt, env)
    local frag = lookup_region_frag_ref(stmt.frag, env)
    if frag == pvm.NIL then
        -- Keep unexpanded use, but expand args/fills/name refs where possible.
        -- open_validate will reject it later if still unresolved.
        return pvm.with(stmt, {
            h = one(expand_stmt_header, stmt.h, env),
            args = expand_exprs(stmt.args, env),
            frag = expand_region_frag_ref_shallow(stmt.frag, env),
        }), {}
    end

    -- Existing logic follows:
    --   resolve cont fills
    --   bind runtime params
    --   rebase labels
    --   expand entry/body/blocks
    --   return jump + generated blocks
end
```

Also update this check:

```lua
if cls == Tr.StmtUseRegionFrag then
    local jump, more_blocks = expand_region_frag_use(stmt, env)
    ...
end
```

It stays structurally the same, but `expand_region_frag_use` now resolves
`RegionFragRefName` or `RegionFragRefSlot`.

### 13.5 Expression fragment expansion

Change `ExprUseExprFrag` case:

```lua
[Tr.ExprUseExprFrag] = function(self, env)
    local frag = lookup_expr_frag_ref(self.frag, env)
    if frag == pvm.NIL then
        return pvm.once(pvm.with(self, {
            h = one(expand_expr_header, self.h, env),
            args = expand_exprs(self.args, env),
            frag = expand_expr_frag_ref_shallow(self.frag, env),
        }))
    end
    local local_env = env_with_fills_and_params(env, self.fills, frag_param_bindings(frag.params, self.args, env))
    return expand_expr(frag.body, local_env)
end
```

### 13.6 Item slots already mostly work

Existing `ItemUseItemsSlot` expansion is already the intended mechanism:

```lua
[Tr.ItemUseItemsSlot] = function(self, env)
    local values = pvm.drain(lookup_slot_value(O.SlotItems(self.slot), env))
    if #values == 1 and pvm.classof(values[1]) == O.SlotValueItems then
        return pvm.children(function(item) return expand_item(item, env) end, values[1].items)
    end
    return pvm.once(self)
end
```

Keep this and make parser-created module-item holes use it.

### 13.7 Open validation

Add validation issues for new unresolved slot refs:

```text
IssueUnfilledRegionFragSlot
IssueUnfilledExprFragSlot
IssueUnfilledNameSlot
IssueUnexpandedRegionFragRef
IssueUnexpandedExprFragRef
IssueUnexpandedNameRef
```

Validation should run after open expansion and before typecheck. If anything
slot-bearing remains, fail immediately.

---

## 14. Runtime pipeline

### 14.1 `mlua_run.lua` no longer renders templates

Remove:

- `splice_to_source()`
- `render_template()`
- `validate_splice_value()`
- `splice_value_kind()`
- `splice_expectation_accepts()`
- `splice_expected_name()`

Replace `Runtime:eval_island()` with:

```lua
function Runtime:eval_island(step_index, closures)
    local step = assert(self.program.steps[step_index], "unknown island step " .. tostring(step_index))
    local Parse = require("moonlift.parse").Define(self.T)
    local Splice = require("moonlift.host_splice")
    local OpenExpand = require("moonlift.open_expand").Define(self.T)
    local OpenValidate = require("moonlift.open_validate").Define(self.T)
    local O = self.T.MoonOpen

    -- 1. Evaluate splice Lua expressions. Preserve nil/false.
    local values = {}
    for _, part in ipairs(step.template.parts) do
        if pvm.classof(part) == self.T.MoonHost.TemplateSplicePart then
            local id = part.splice.id
            local fn = assert(closures and closures[id], "missing splice closure " .. id)
            local ok, value = pcall(fn)
            if not ok then error("Moonlift splice eval failed at " .. id .. ": " .. tostring(value), 2) end
            values[id] = { present = true, value = value }
            self:adopt_host_value(value)
        end
    end

    -- 2. Parse template with holes.
    local parsed
    local kind = step.template.kind_word
    if kind == "region" then
        parsed = Parse.parse_region_frag_template(step.template, self:parse_opts())
    elseif kind == "expr" then
        parsed = Parse.parse_expr_frag_template(step.template, self:parse_opts())
    elseif kind == "module" then
        parsed = Parse.parse_module_template(step.template, self:parse_opts())
    elseif kind == "func" then
        parsed = Parse.parse_func_template(step.template, self:parse_opts())
    else
        error("unsupported hosted island kind: " .. tostring(kind), 2)
    end
    if #parsed.issues ~= 0 then error("Moonlift parse failed: " .. tostring(parsed.issues[1]), 2) end

    -- 3. Coerce Lua values into slot bindings.
    local bindings = {}
    for i = 1, #parsed.splice_slots do
        local ss = parsed.splice_slots[i]
        local rec = values[ss.splice_id]
        if not rec or not rec.present then error("missing splice value: " .. ss.splice_id, 2) end
        bindings[#bindings + 1] = Splice.fill(self.session, ss.slot, rec.value, "splice " .. ss.splice_id)
    end

    -- 4. Expand with existing fragments plus splice fills.
    local env = OpenExpand.env_with_frags(self.region_frags_asdl, self.expr_frags_asdl)
    env = OpenExpand.env_with_fills(env, bindings) -- new public helper
    local expanded = self:expand_parsed_value(OpenExpand, parsed.value, env, kind)

    -- 5. Validate no open artifacts remain.
    local report = OpenValidate.value(expanded)
    if #report.issues ~= 0 then error("Moonlift open expansion failed: " .. tostring(report.issues[1]), 2) end

    -- 6. Wrap/register result as host value.
    return self:wrap_expanded_island(kind, expanded, parsed)
end
```

### 14.2 Public open-expand helper

Add a public helper instead of depending on local `merge_fills`:

```lua
function env_with_fills(env, bindings)
    local merged = {}
    for i = 1, #env.fills.bindings do merged[#merged + 1] = env.fills.bindings[i] end
    for i = 1, #bindings do merged[#merged + 1] = bindings[i] end
    return O.ExpandEnv(env.region_frags, env.expr_frags, O.FillSet(merged), env.conts, env.params, env.rebase_prefix)
end
```

Export it from `open_expand.lua`.

### 14.3 Translation closure generation

Existing generated Lua can keep producing closures:

```lua
entries[#entries + 1] = string.format("[%q] = function() return (%s) end", id, lua_source)
```

The nil/false fix is in `eval_island`, not necessarily in generated Lua.

### 14.4 Host eval phase

`host_eval.lua` can be simplified drastically:

- execute Lua opaque steps
- evaluate template splice Lua expressions if needed for analysis mode
- return raw host value refs or raw values wrapped for reporting
- do not classify against expected roles
- do not validate role compatibility

Role compatibility is only checked in `host_splice.lua`, because only parser
slots know roles.

---

## 15. File-by-file plan

| Step | File | Action |
|---:|---|---|
| 1 | `lua/moonlift/schema/open.lua` | Add `NameSlot`, `NameRef`, `RegionFragSlot`, `ExprFragSlot`, `RegionFragRef`, `ExprFragRef`; make `ExprSlot.ty` and `PlaceSlot.ty` optional; add new `Slot` and `SlotValue` variants. |
| 2 | `lua/moonlift/schema/tree.lua` | Change fragment use nodes from `frag_name: string` to `frag: RegionFragRef/ExprFragRef`. Change selected declaration/label names to `NameRef`. |
| 3 | `lua/moonlift/schema/host.lua` | Remove `SpliceExpectation`; remove `TemplateSplice.expected`; make template text/splice carry `SourceOccurrence`; add `TemplateSpliceSlot`. |
| 4 | Regenerate/define ASDL | Update all generated constructors/classes through the project schema definition path. |
| 5 | `lua/moonlift/name_ref.lua` or helper section | Add helpers: `text(O, ref)`, `literal(O, string)`, `is_resolved(O, ref)`, validation helpers. |
| 6 | `lua/moonlift/mlua_host_model.lua` | Delete `expected_splice()` and `in_as_type_argument()`. Compute template source occurrences. |
| 7 | `lua/moonlift/parse.lua` | Add `TK.hole`; add template lexer; add `record_splice_slot`; add role-specific hole parsing; add template entrypoints. |
| 8 | `lua/moonlift/host_splice.lua` | New file. Central role dispatch and coercion. Explicit source parse helpers. |
| 9 | `lua/moonlift/host_values.lua` and host value modules | Add `moonlift_splice(role, session, site)` methods. Keep `moonlift_splice_source()` only for debug/display during transition. |
| 10 | `lua/moonlift/open_expand.lua` | Add lookup cases; add name ref expansion; update fragment ref expansion; export `env_with_fills`; update all name fields. |
| 11 | `lua/moonlift/open_facts.lua` | Collect facts from new refs/slots. Emit `MetaFactSlot` for `NameRefSlot`, `RegionFragRefSlot`, `ExprFragRefSlot`. |
| 12 | `lua/moonlift/open_validate.lua` | Add unresolved issues for new slot/ref variants. Ensure validation runs before typecheck. |
| 13 | `lua/moonlift/open_rewrite.lua` | Update rewrite traversal for `ExprUseExprFrag.frag`, `StmtUseRegionFrag.frag`, `NameRef` fields. |
| 14 | `lua/moonlift/tree_typecheck.lua` | Remove assumptions that unexpanded expr/place slots have concrete types. Reject/leak-check unexpanded slots. Use `NameRefText` helper for names. |
| 15 | `lua/moonlift/tree_expr_type.lua`, `tree_module_type.lua`, etc. | Update for optional slot types and `NameRef` fields. |
| 16 | Backend/lowering files | Replace string-name field access with resolved-name helper. Assert names are resolved. |
| 17 | Editor/LSP files | Update symbol/hover/reference facts for `NameRefText`; optionally point `NameRefSlot` diagnostics at splice sites. |
| 18 | `lua/moonlift/host_eval.lua` | Remove expectation validation. Eval only. |
| 19 | `lua/moonlift/mlua_run.lua` | Remove render path. Parse templates with holes, fill slots, open-expand, validate. Split host fragment maps from ASDL fragment arrays. |
| 20 | `lua/moonlift/host_template_parse.lua` | Delete or reduce to source-only helper for `moon.source`. No template render path. |
| 21 | Tests | Add role tests and migration tests. Delete/update tests that relied on implicit raw strings. |
| 22 | Examples/lib docs | Update all `@{"i32"}` and raw-string source patterns to `moon.i32` or `moon.source(...)`. |
| 23 | `LANGUAGE_REFERENCE.md` | Rewrite splice sections to describe role-aware ASDL splicing. |

---

## 16. Implementation snippet shapes

### 16.1 `host_splice.lua` skeleton

```lua
local pvm = require("moonlift.pvm")

local M = {}

function M.kind_of(value)
    local tv = type(value)
    if tv == "nil" or tv == "number" or tv == "boolean" or tv == "string" then return tv end
    if tv == "table" then
        local kind = rawget(value, "moonlift_quote_kind") or rawget(value, "kind")
        if kind then return kind end
        if type(value.as_type_value) == "function" then return "type" end
        if type(value.as_expr_value) == "function" then return "expr" end
        local cls = pvm.classof(value)
        if cls then return tostring(cls) end
    end
    return tv
end

function M.is_source(value)
    return type(value) == "table"
       and (rawget(value, "moonlift_quote_kind") == "source" or rawget(value, "kind") == "source")
end

local function protocol(value, role, session, site)
    if (type(value) == "table" or type(value) == "userdata")
       and type(value.moonlift_splice) == "function" then
        return value:moonlift_splice(role, session, site)
    end
    return nil
end

function M.fill(session, slot, value, site)
    local O = session.T.MoonOpen
    local cls = pvm.classof(slot)

    if cls == O.SlotType then return M.fill_type(session, slot.slot, value, site) end
    if cls == O.SlotExpr then return M.fill_expr(session, slot.slot, value, site) end
    if cls == O.SlotRegion then return M.fill_region_body(session, slot.slot, value, site) end
    if cls == O.SlotRegionFrag then return M.fill_region_frag(session, slot.slot, value, site) end
    if cls == O.SlotExprFrag then return M.fill_expr_frag(session, slot.slot, value, site) end
    if cls == O.SlotName then return M.fill_name(session, slot.slot, value, site) end
    if cls == O.SlotItems then return M.fill_items(session, slot.slot, value, site) end
    if cls == O.SlotModule then return M.fill_module(session, slot.slot, value, site) end
    if cls == O.SlotTypeDecl then return M.fill_type_decl(session, slot.slot, value, site) end
    if cls == O.SlotFunc then return M.fill_func(session, slot.slot, value, site) end
    if cls == O.SlotConst then return M.fill_const(session, slot.slot, value, site) end
    if cls == O.SlotStatic then return M.fill_static(session, slot.slot, value, site) end
    if cls == O.SlotCont then return M.fill_cont(session, slot.slot, value, site) end

    if cls == O.TypeSlot then return M.fill_type(session, slot, value, site) end
    if cls == O.ExprSlot then return M.fill_expr(session, slot, value, site) end
    if cls == O.RegionSlot then return M.fill_region_body(session, slot, value, site) end
    if cls == O.RegionFragSlot then return M.fill_region_frag(session, slot, value, site) end
    if cls == O.ExprFragSlot then return M.fill_expr_frag(session, slot, value, site) end
    if cls == O.NameSlot then return M.fill_name(session, slot, value, site) end
    if cls == O.ItemsSlot then return M.fill_items(session, slot, value, site) end

    error((site or "splice") .. ": unsupported splice slot " .. tostring(slot), 2)
end

return M
```

### 16.2 Parser template entrypoint shape

```lua
function M.parse_module_template(T, template, opts)
    local p = parser_from_tokens(T, M.lex_template(template), opts)
    p.H = T.MoonHost
    p.splice_slots = {}
    p.splice_slots_by_id = {}

    local module = p:parse_module_body()

    return {
        value = module,
        module = module,
        splice_slots = p.splice_slots,
        issues = p.issues,
    }
end
```

### 16.3 Name helper shape

```lua
local pvm = require("moonlift.pvm")

local M = {}

function M.literal(T, text)
    return T.MoonOpen.NameRefText(text)
end

function M.text(T, ref, site)
    local O = T.MoonOpen
    if type(ref) == "string" then return ref end -- temporary migration shim only
    local cls = pvm.classof(ref)
    if cls == O.NameRefText then return ref.text end
    if cls == O.NameRefSlot then error((site or "name") .. ": unexpanded name slot", 2) end
    error((site or "name") .. ": expected NameRef", 2)
end

return M
```

### 16.4 `mlua_host_model.lua` corrected splice construction

```lua
parts[#parts + 1] = H.TemplateSplicePart(H.TemplateSplice(
    "splice." .. tostring(splice_i),
    lua_source_occurrence))
```

No expected field. No line-prefix guessing.

---

## 17. User-facing examples

### 17.1 Type splice

```lua
local moon = require("moonlift.host")
local T = moon.i32

return func id(x: @{T}) -> @{T}
    return x
end
```

Parser sees `TK.hole` in type position and creates a `TypeSlot`.
`host_splice.fill_type()` receives a `TypeValue` and emits
`SlotBinding(SlotType(slot), SlotValueType(TScalar(i32)))`.

### 17.2 Expression splice

```lua
local K = 42

return func answer() -> i32
    return @{K}
end
```

Lua number `42` becomes `ExprLit(LitInt("42"))`.

```lua
local greeting = "hello"

return func greet() -> ptr(u8)
    return @{greeting}
end
```

Lua string `"hello"` in expression role becomes a Moonlift string literal. It is
not treated as the identifier `hello` and not parsed as raw source.

### 17.3 Explicit raw source escape

```lua
local raw = moon.source("x + 1")

return func f(x: i32) -> i32
    return @{raw}
end
```

`moon.source` is parsed as an expression because the parser-created slot role is
`expr`.

### 17.4 Name splice

```lua
local name = "parse_i32"

return func @{name}(p: ptr(u8), n: i32) -> i32
    return 0
end
```

Parser uses `NameRefSlot`. `host_splice.fill_name()` validates the Lua string as
a Moonlift identifier and fills `SlotValueName("parse_i32")`.

### 17.5 Region fragment emit splice

```lua
local scanner = make_scanner(65)

return func parse_A(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit @{scanner}(p, n; hit = done, miss = bad)
    end
    block done(pos: i32)
        yield pos
    end
    block bad(pos: i32)
        yield -1
    end
    end
end
```

Parser creates `RegionFragRefSlot`. `host_splice.fill_region_frag()` fills a
`SlotValueRegionFrag`. `open_expand` resolves the slot to the fragment ASDL and
uses the normal fragment expansion logic.

### 17.6 Module item splice

```lua
local helpers = {
    moon.extern_func("puts", { moon.param("s", moon.ptr(moon.u8)) }, moon.i32),
    moon.func("helper", ...),
}

return module
    @{helpers}

    export func main() -> i32
        return helper()
    end
end
```

Parser creates `ItemsSlot`. `host_splice.fill_items()` converts the Lua array to
`SlotValueItems`. `open_expand` expands those items inline.

### 17.7 Region body splice

```lua
local stmts = make_debug_counter_stmts()

return region counter() -> i32
entry start()
    @{stmts}
    yield 0
end
end
```

A hole in statement position creates `RegionSlot` and fills with
`SlotValueRegion(stmts)`.

---

## 18. Migration strategy

This is a hard refactor, so the plan is not “keep everything green after every
line”. The plan is to break deliberately in controlled layers and restore the
pipeline from the schema outward.

### 18.1 Phase 1 — schema and constructors

- Add new schema variants.
- Change fields to `NameRef` and fragment refs.
- Update constructors in parser and host builders enough for the project to load.
- Add temporary helper wrappers for literal names.

Expected breakage: many phases that read `.name` as a string.

### 18.2 Phase 2 — mechanical traversal repair

Update traversal-only phases:

- `open_facts.lua`
- `open_rewrite.lua`
- editor fact collectors
- diagnostic collectors
- residence/binding gathering
- simple type helper modules

Goal: everything traverses the new node shapes without semantic completion.

### 18.3 Phase 3 — open expansion semantics

Implement:

- `lookup_slot_value` additions
- `expand_name_ref`
- fragment ref resolution
- region fragment expansion path update
- expr fragment expansion update
- item slots from parser holes
- `env_with_fills` public helper

Goal: open expansion can eliminate every parser-created splice slot.

### 18.4 Phase 4 — parser template path

Implement:

- `TK.hole`
- source-range-preserving template lexer
- role-specific hole parsing
- template parse entrypoints
- splice slot recording

At this point source-only parsing may still work through old entrypoints.
Template parsing starts producing ASDL with slots.

### 18.5 Phase 5 — host splice coercion

Implement `host_splice.lua` and host value protocols. Add unit tests for each
role without running the full `.mlua` runner.

### 18.6 Phase 6 — runtime switch

Replace `mlua_run.lua` render path with:

```text
eval Lua splice closures → parse template with holes → fill slots → open_expand → validate → wrap result
```

Delete role validation from `mlua_run.lua` and `host_eval.lua`.

### 18.7 Phase 7 — downstream cleanup

Update typecheck/lowering/backend to consume resolved `NameRefText` and assert
no unresolved slot refs. Remove temporary string-name shims when possible.

### 18.8 Phase 8 — tests/examples/docs

Add tests:

- number/boolean/nil/string expression splices
- type splices with TypeValue
- bare string in type position fails
- `moon.source` in type/expr/item roles
- module item splice with empty/single/multiple items
- region body splice
- region fragment emit splice
- expression fragment emit splice
- name splice valid/invalid identifiers
- nil splice preserves value
- false splice preserves value
- diagnostics point to original `.mlua` splice site

Update examples and language reference.

---

## 19. What is removed

| Removed | Replacement |
|---|---|
| `moonlift_splice_source()` as primary semantics | `host_splice.lua` role coercion and `moonlift_splice(role, ...)` protocol |
| `expected_splice()` | Parser-owned role detection via `TK.hole` context |
| `in_as_type_argument()` | Real type parser context |
| `TemplateSplice.expected` | Parser output `TemplateSpliceSlot(splice_id, slot, role, site)` |
| `SpliceExpectation` | Slot wrapper variant is the role |
| `render_template()` | Template lexer with hole tokens |
| `splice_to_source()` | Slot binding coercion |
| `validate_splice_value()` in runtime | `host_splice.fill()` role-specific validation |
| `host_template_parse.lua` render+parse path | Source-only helpers for explicit `moon.source`, or deletion |
| `StmtUseRegionFrag.frag_name` | `StmtUseRegionFrag.frag: RegionFragRef` |
| `ExprUseExprFrag.frag_name` | `ExprUseExprFrag.frag: ExprFragRef` |
| implicit raw-source Lua strings | strings are literals in expr role, identifiers in name role, errors elsewhere |
| duplicated host value classification | `host_splice.kind_of` and role fillers |

`moonlift_splice_source()` may remain temporarily for debug display and legacy
printing, but it must not define splice semantics.

---

## 20. Open questions intentionally deferred

These should not block the first implementation unless encountered directly.

1. **NameRef everywhere or selected sites only?**
   This document recommends selected user-facing declaration/label sites. Local
   variables and params can stay concrete strings initially.

2. **Typed expression slots?**
   Parser-created expression slots use unknown/optional type. Later, expected
   type can be propagated from annotations or call signatures for better early
   validation.

3. **Array length role.**
   Existing `ArrayLenSlot` can support `@{n}` in array type lengths, but this can
   be added after core type/expr/item/fragment splices work.

4. **Place/domain splices.**
   The slot system supports them, but parser role sites should be added only
   where syntax demands them.

5. **Fragment definitions as module items.**
   If region/expr fragments become first-class module items, `RegionFragValue`
   and `ExprFragValue` can splice as `module_items`. Otherwise they should only
   splice as emit targets.

6. **Incremental/LSP source map precision.**
   The architecture requires original ranges. The first implementation can store
   byte-accurate ranges and improve UTF-16 position fidelity as a follow-up.

---

## Postscript

The key insight remains:

> MoonOpen slots already are splice holes.

The hard refactor removes the current bypass where host values are flattened to
source before the slot system can see them. The parser now creates typed holes,
the host layer fills them once, and open expansion eliminates them before normal
compiler phases run.
