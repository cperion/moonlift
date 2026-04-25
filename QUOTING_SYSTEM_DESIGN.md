# Moonlift Quoting / Metaprogramming / Open-Code Design

Status: current design document for the `MoonliftMeta` layer.

The `MoonliftMeta` ASDL module now exists in:

- `moonlift/lua/moonlift/asdl.lua`

An initial builder/helper API now exists in:

- `moonlift/lua/moonlift/meta.lua`

It constructs canonical `MoonliftMeta` ASDL values and installs small convenience
methods on slots, symbols, and fragments.

An initial normalization/expansion API now exists in:

- `moonlift/lua/moonlift/expand_meta.lua`

It provides `pvm.phase(...)` boundaries for structural slot filling, param
substitution, fragment expansion, module/item splice expansion, and deterministic
local-id rebasing from explicit `use_id` fields.

An initial closed-value sealing API now exists in:

- `moonlift/lua/moonlift/seal_meta_to_elab.lua`

It provides `pvm.phase(...)` boundaries for sealing closed Meta values to ordinary
`MoonliftElab` values and rejects unfilled slots / unexpanded splices with
explicit errors.

An initial source quote frontend now exists in:

- `moonlift/lua/moonlift/meta_source.lua`

It parses ordinary Moonlift source snippets against explicit Meta params/open
sets, lowers them through `Surface -> Elab`, then converts them to
`MoonliftMeta`. It also provides `$name` quote-hole preprocessing as syntax for
explicit slots/open-code holes; the holes still resolve to ASDL-visible Meta
slots/imports/params rather than hidden Lua captures.

Initial query, validation, and rewrite APIs now exist in:

- `moonlift/lua/moonlift/meta_query.lua`
- `moonlift/lua/moonlift/meta_validate.lua`
- `moonlift/lua/moonlift/rewrite_meta.lua`

Those APIs expose flat `MetaFact` walks, explicit `MetaValidationReport` values,
and ASDL-visible `MetaRewriteSet` rules. The implemented compiler today is still
the closed stack in:

- `moonlift/lua/moonlift/asdl.lua`

Current closed compiler path:

```text
MoonliftSurface -> MoonliftElab -> MoonliftSem -> MoonliftBack -> Artifact
```

This document fixes the quote design against the **current** ASDL reality:

- `Surface` now has top-level `func` / `extern func` / `const` / `static` /
  `import` / `type` items.
- `Surface` has authored type families for structs, enums, tagged unions, and
  untagged unions.
- `Elab` carries local/export functions, externs, consts, statics, imports,
  struct/union type declarations, places, loops, views, and typed expressions.
- closures are surface sugar and do **not** currently exist as a closed
  `ElabType` family; they desugar before ordinary downstream lowering.
- `Sem` is machine-facing and must not become the primary open-code layer.

The design target remains:

> Moonlift quotes are **ASDL values**, not strings. Open-code assembly happens
> in `MoonliftMeta`; closed code then enters the ordinary `Elab -> Sem -> Back`
> pipeline.

---

# 1. Core decision

Moonlift quoting should not be modeled as:

- open source strings,
- raw Lua AST tables,
- open `Surface`, or
- open `Sem`.

It should be modeled as:

```text
MoonliftMeta = open elaborated code
```

`Meta` mirrors the **closed elaborated layer** closely enough that it can seal
into ordinary `MoonliftElab` without inventing a second semantic universe.

## Why not `Surface`?

`Surface` is syntax-shaped and unresolved:

- names are still authored strings / paths,
- dot syntax may mean qualified name or field projection,
- enums/tagged unions/closures are surface sugar,
- source spans are occurrence metadata rather than semantic identity.

That is too early for reusable hygienic code values.

## Why not `Sem`?

`Sem` has already committed to machine-facing decisions:

- call target classification,
- field refs by name/offset,
- indexed address/view forms,
- storage/residence-facing distinctions,
- semantic view normalization,
- backend-sensitive result shapes.

That is too late for open-code assembly. Quotes should assemble code before
those commitments.

## Why `Elab`?

`Elab` is the current layer where code is:

- typed,
- binding-resolved,
- hygienic enough to be structurally assembled,
- still source-language-shaped enough for user metaprogramming,
- upstream of layout resolution, residence planning, and backend lowering.

So `Meta` should be an **open mirror of `Elab`**, with slots/imports/fragment-use
nodes added.

---

# 2. Architecture

## 2.1 Closed path

```text
source text
  -> MoonliftSurface
  -> MoonliftElab
  -> MoonliftSem
  -> MoonliftBack
  -> Artifact
```

## 2.2 Open-code path

```text
builder API / source quote frontend / future hosted parser
  -> MoonliftMeta
  -> structural assembly / slot filling / normalization / closedness validation
  -> MoonliftElab
  -> MoonliftSem
  -> MoonliftBack
  -> Artifact
```

## 2.3 Non-negotiable rule

If it changes generated code, it must be visible as ASDL:

- runtime params,
- imports,
- slots,
- fragment/function/module values,
- explicit open code nodes.

No hidden Lua captures, mutable builder-side context bags, or string
substitution protocols may control quote meaning.

---

# 3. Public nouns

The public quote system should expose four common quote values.

## 3.1 Expr fragment

An inline expression template.

```text
MetaExprFrag(interface, body, result_type)
```

Use it for:

- scalar formulas,
- address/value computations,
- expression-level intrinsics,
- small branchless code shapes such as `select(...)`.

## 3.2 Region fragment

An inline statement-sequence template.

```text
MetaRegionFrag(interface, body)
```

Use it for:

- loop bodies,
- statements with local binders,
- stores / updates,
- small control-flow regions,
- DSP/audio kernel steps.

## 3.3 Function template

A callable, graph-visible function item.

```text
MetaFuncLocal(sym, params, open, result, body)
MetaFuncExport(sym, params, open, result, body)
```

Functions are not “fragments with a policy flag.” A function has item identity,
can be called, can be exported/local, and seals to `ElabFuncLocal` or
`ElabFuncExport`.

## 3.4 Module template

A package of items.

```text
MetaModule(interface, items)
```

A module can assemble:

- functions,
- extern declarations,
- consts,
- statics,
- imports,
- struct/union type declarations,
- item/module splices.

---

# 4. Interface model

Every quote/template has an explicit interface. The interface has three classes
of nonlocal meaning.

## 4.1 Runtime params

Runtime values received by a fragment/function.

Examples:

```text
x: f32
xs: view(f32)
n: index
out: &f32
```

These become binding references inside the quote.

## 4.2 Imports

Fixed nonlocal dependencies.

Imports are not holes. They are stable outside dependencies that are part of a
quote's structural meaning.

Import families should cover at least:

- imported values,
- imported global functions,
- imported extern functions,
- imported consts,
- imported statics,
- imported named types,
- imported layout information.

This matches the current closed compiler's dependency on value/type/layout
environments.

## 4.3 Slots

Compile-time structural holes filled during assembly.

Slot kinds should be explicit ASDL variants, not string tags:

- type slot,
- expr slot,
- place slot,
- domain slot,
- region slot,
- function slot,
- const slot,
- static slot,
- type-declaration slot,
- item-list slot,
- module slot.

Use a slot when the quote is intentionally abstract over structure.
Use an import when the quote depends on a fixed external thing.

---

# 5. Hygiene and identity

## 5.1 No implicit capture

A quote may refer only to:

- declared params,
- declared imports,
- declared slots,
- locally introduced binders,
- sibling symbols introduced by module assembly.

Unbound names are errors by default.

## 5.2 Deterministic binder ids

Current `Elab` binders carry string ids. `Meta` must preserve structural
identity by making generated/local binder ids deterministic.

Do not use random gensyms.

A binder id should be derived from structural information such as:

- owning quote/template identity,
- source/structural path,
- binder role,
- fragment-use site path when a fragment is expanded.

The printed name can be friendly; the semantic id must be stable.

## 5.3 Structural substitution only

Slot filling and fragment expansion are structural operations over ASDL values.
They are never textual substitution.

---

# 6. `MoonliftMeta` shape

This is the intended shape, not yet implemented. Exact constructor names may be
adjusted during implementation, but the semantic distinctions below must remain
explicit.

## 6.1 Types

`MetaType` should mirror current `ElabType`, plus type slots.

Current `ElabType` families to mirror:

- void / bool,
- signed and unsigned integer widths,
- float widths,
- index,
- pointer,
- array,
- slice,
- view,
- function,
- named type.

Important current-reality note:

- `Surface` has `closure(T...) -> R`, but current `ElabType` does not. Closure
  syntax is surface sugar over a struct/function/context representation. Source
  quotes may accept closure syntax, but `Meta` core should not pretend closure is
  an ordinary closed `ElabType` unless the closed ASDL grows such a type.

`MetaTSlot(type_slot)` is the open-code addition.

## 6.2 Bindings

`MetaBinding` should mirror current `ElabBinding`, plus slot/import symbol forms:

- param,
- local immutable value,
- local mutable cell,
- arg,
- loop carry,
- loop index,
- global func,
- global const,
- global static,
- extern,
- imported value,
- function slot,
- const/static slot where needed.

## 6.3 Places

`MetaPlace` should mirror current `ElabPlace`:

- binding place,
- deref place,
- field place,
- index place.

This is important. Addressability must not be smuggled through generic
expressions. Open code needs explicit place slots/forms when the user is
abstracting over lvalues.

## 6.4 Domains and loops

`MetaDomain` should mirror current `ElabDomain`, plus domain slots:

- range(stop),
- range(start, stop),
- zip-equal,
- value domain,
- domain slot.

`MetaLoop` should mirror current `ElabLoop`:

- while statement loop,
- over/domain statement loop,
- while expression loop,
- over/domain expression loop,
- carry ports,
- index ports,
- explicit next/carry updates,
- expression-loop exit classification where the closed layer still carries it.

Even if the preferred user source syntax is now `for ... in` / `while ... with`,
`Meta` should mirror the actual closed elaborated loop nouns until the closed
ASDL changes.

## 6.5 Expressions

`MetaExpr` should mirror current `ElabExpr`, plus open-code additions.

Current `ElabExpr` families to mirror include:

- literals with explicit type,
- binding expression,
- unary and binary operations,
- address-of place,
- deref,
- scalar casts/conversions,
- intrinsic call,
- ordinary call,
- field/index,
- aggregate and array literals,
- `if` expression,
- `select` expression,
- `switch` expression,
- loop expression,
- block expression,
- view construction forms.

Open-code additions include:

- expression slot value,
- expression-fragment use.

Do **not** collapse code-shape-sensitive forms:

- `if` and `select` remain distinct,
- `switch` remains distinct,
- intrinsics remain explicit,
- view construction remains explicit.

## 6.6 Statements

`MetaStmt` should mirror current `ElabStmt`, plus region-use/slot nodes.

Current `ElabStmt` families to mirror:

- let,
- var,
- set place,
- expr statement,
- if,
- switch,
- return void/value,
- break,
- break value where the current closed layer still supports expression-loop
  infrastructure,
- continue,
- loop statement.

Open-code additions:

- use region slot,
- use region fragment.

## 6.7 Items and modules

`MetaItem` should mirror current `ElabItem`, plus item/module splice nodes.

Current `ElabItem` families to mirror:

- function item,
- extern function item,
- const item,
- static item,
- import item,
- type item.

Current `ElabTypeDecl` families to mirror:

- struct,
- union.

Current-reality note:

- `Surface` has enum and tagged union type declarations, but they desugar before
  or during elaboration into closed type/const structure. `Meta` source quote
  syntax may accept enum/tagged-union sugar, but the core open elaborated layer
  should mirror the current `ElabTypeDecl` families unless closed `Elab` grows
  explicit enum/tagged-union declarations.

---

# 7. Suggested ASDL skeleton

This skeleton intentionally shows the added open-code nouns without enumerating
every arithmetic constructor. Implementation should expand the `Meta*` families
to mirror the current `Elab*` families in `moonlift/lua/moonlift/asdl.lua`.

```asdl
module MoonliftMeta {
    MetaTypeSlot   = (string key, string pretty_name) unique
    MetaExprSlot   = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaPlaceSlot  = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaDomainSlot = (string key, string pretty_name) unique
    MetaRegionSlot = (string key, string pretty_name) unique
    MetaFuncSlot   = (string key, string pretty_name, MoonliftMeta.MetaType fn_ty) unique
    MetaConstSlot  = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaStaticSlot = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaTypeDeclSlot = (string key, string pretty_name) unique
    MetaItemsSlot  = (string key, string pretty_name) unique
    MetaModuleSlot = (string key, string pretty_name) unique

    MetaSlot = MetaSlotType(MoonliftMeta.MetaTypeSlot slot) unique
             | MetaSlotExpr(MoonliftMeta.MetaExprSlot slot) unique
             | MetaSlotPlace(MoonliftMeta.MetaPlaceSlot slot) unique
             | MetaSlotDomain(MoonliftMeta.MetaDomainSlot slot) unique
             | MetaSlotRegion(MoonliftMeta.MetaRegionSlot slot) unique
             | MetaSlotFunc(MoonliftMeta.MetaFuncSlot slot) unique
             | MetaSlotConst(MoonliftMeta.MetaConstSlot slot) unique
             | MetaSlotStatic(MoonliftMeta.MetaStaticSlot slot) unique
             | MetaSlotTypeDecl(MoonliftMeta.MetaTypeDeclSlot slot) unique
             | MetaSlotItems(MoonliftMeta.MetaItemsSlot slot) unique
             | MetaSlotModule(MoonliftMeta.MetaModuleSlot slot) unique

    MetaParam = (string key, string name, MoonliftMeta.MetaType ty) unique

    MetaValueImport = MetaImportValue(string key, string name, MoonliftMeta.MetaType ty) unique
                    | MetaImportGlobalFunc(string key, string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                    | MetaImportGlobalConst(string key, string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                    | MetaImportGlobalStatic(string key, string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                    | MetaImportExtern(string key, string symbol, MoonliftMeta.MetaType ty) unique

    MetaTypeImport = (string key, string local_name, MoonliftMeta.MetaType ty) unique
    MetaFieldType = (string field_name, MoonliftMeta.MetaType ty) unique
    MetaTypeLayout = MetaLayoutNamed(string module_name, string type_name, MoonliftMeta.MetaFieldType* fields) unique

    MetaInterface = (
        MoonliftMeta.MetaParam* params,
        MoonliftMeta.MetaValueImport* value_imports,
        MoonliftMeta.MetaTypeImport* type_imports,
        MoonliftMeta.MetaTypeLayout* layouts,
        MoonliftMeta.MetaSlot* slots
    ) unique

    -- Mirror ElabType, plus MetaTSlot.
    MetaType = MetaTVoid
             | MetaTBool
             | MetaTI8 | MetaTI16 | MetaTI32 | MetaTI64
             | MetaTU8 | MetaTU16 | MetaTU32 | MetaTU64
             | MetaTF32 | MetaTF64
             | MetaTIndex
             | MetaTPtr(MoonliftMeta.MetaType elem) unique
             | MetaTArray(MoonliftMeta.MetaExpr count, MoonliftMeta.MetaType elem) unique
             | MetaTSlice(MoonliftMeta.MetaType elem) unique
             | MetaTView(MoonliftMeta.MetaType elem) unique
             | MetaTFunc(MoonliftMeta.MetaType* params, MoonliftMeta.MetaType result) unique
             | MetaTNamed(string module_name, string type_name) unique
             | MetaTSlot(MoonliftMeta.MetaTypeSlot slot) unique

    -- These families must mirror current Elab in full during implementation.
    MetaBinding = ...
    MetaPlace = ...
    MetaIndexBase = ...
    MetaDomain = ...
    MetaLoop = ...
    MetaExpr = ... | MetaExprSlotValue(...) | MetaExprUseExprFrag(...)
    MetaStmt = ... | MetaStmtUseRegionSlot(...) | MetaStmtUseRegionFrag(...)
    MetaFunc = MetaFuncLocal(...) | MetaFuncExport(...)
    MetaExternFunc = (...)
    MetaConst = (...)
    MetaStatic = (...)
    MetaImport = (...)
    MetaTypeDecl = MetaStruct(...) | MetaUnion(...)
    MetaItem = ... | MetaItemUseItemsSlot(...) | MetaItemUseModule(...)
    MetaModule = (MoonliftMeta.MetaInterface interface, MoonliftMeta.MetaItem* items) unique

    MetaExprFrag = (MoonliftMeta.MetaInterface interface, MoonliftMeta.MetaExpr body, MoonliftMeta.MetaType result) unique
    MetaRegionFrag = (MoonliftMeta.MetaInterface interface, MoonliftMeta.MetaStmt* body) unique

    MetaSlotValue = MetaSlotValueType(MoonliftMeta.MetaType ty) unique
                  | MetaSlotValueExpr(MoonliftMeta.MetaExpr expr) unique
                  | MetaSlotValuePlace(MoonliftMeta.MetaPlace place) unique
                  | MetaSlotValueDomain(MoonliftMeta.MetaDomain domain) unique
                  | MetaSlotValueRegion(MoonliftMeta.MetaStmt* body) unique
                  | MetaSlotValueFunc(MoonliftMeta.MetaFunc func) unique
                  | MetaSlotValueConst(MoonliftMeta.MetaConst c) unique
                  | MetaSlotValueStatic(MoonliftMeta.MetaStatic s) unique
                  | MetaSlotValueTypeDecl(MoonliftMeta.MetaTypeDecl t) unique
                  | MetaSlotValueItems(MoonliftMeta.MetaItem* items) unique
                  | MetaSlotValueModule(MoonliftMeta.MetaModule module) unique

    MetaSlotBinding = (MoonliftMeta.MetaSlot slot, MoonliftMeta.MetaSlotValue value) unique
}
```

The `...` entries are not permission for helper-table semantics. They mean:
copy the current closed `Elab` distinction set into the open layer deliberately.

---

# 8. Source quote syntax direction

The final syntax is not implemented yet. The recommended user-facing shape is:

```moonlift
quote expr (params...) [slots...] -> T
    expr
end

quote region (params...) [slots...]
    stmt*
end

quote func name(params...) [slots...] -> T
    stmt*
end

quote module [slots...]
    item*
end
```

Examples:

```moonlift
quote expr (x: f32) [bias: expr f32] -> f32
    fma(x, x, $bias)
end
```

```moonlift
quote region (xs: view(f32), gain: f32) [body: region]
    for i in xs do
        xs[i] = xs[i] * gain
        $body
    end
end
```

```moonlift
quote func process(xs: view(f32), gain: f32) -> void [step: region]
    for i in xs do
        $step
    end
end
```

The `$slot` spelling is only a proposed surface marker. Semantically it lowers
to explicit `Meta*Slot` / `Meta*Use*` ASDL nodes. Any source or builder fragment/module use must also carry an explicit deterministic `use_id`, because local binder rebasing is structural and must not depend on random gensyms or object identity.

---

# 9. Builder API direction

The Lua API should build the same `MoonliftMeta` ASDL values as source quotes.
The Lua surface may use strings for convenience, but strings are only a frontend.
They must parse/elaborate into `Meta` immediately.

Example direction:

```lua
local q = require("moonlift.meta")

local f32 = q.type.f32
local vf32 = q.type.view(f32)

local body = q.slot.region("body")

local frag = q.region {
    params = {
        q.param("xs", vf32),
        q.param("gain", f32),
    },
    slots = { body },
    source = [[
        for i in xs do
            xs[i] = xs[i] * gain
            $body
        end
    ]],
}
```

The meaning of `frag` is its `MetaRegionFrag` ASDL identity, not the original
source string or builder table.

---

# 10. Assembly semantics

## 10.1 Fragment use

Fragment use is a `Meta`-level assembly node.

- expression fragment use appears in `MetaExpr`,
- region fragment use appears in `MetaStmt`,
- item/module splices appear in `MetaItem`.

These nodes may survive inside `Meta` for caching and transformation, but they
must normalize away before ordinary `Elab -> Sem` lowering.

## 10.2 Function use

Function use is different from fragment use.

A function is graph-visible and callable. Calling a function should lower to
ordinary call structure, not inline expansion, unless an explicit transformation
chooses to inline it.

## 10.3 Slot filling

Slot filling takes `MetaSlotBinding*` and returns a new `Meta` value.

It must be a pure structural transform:

```text
meta_with_slots(meta, bindings) -> meta
```

No mutation of existing ASDL nodes.

## 10.4 Closedness

A `Meta` value is closed when:

- all slots are filled or intentionally resolved,
- all fragment-use/splice nodes are expanded where required,
- all imports are present in the sealing environment,
- all local binder ids have deterministic final identities,
- no open-only nodes remain in the output target.

Only closed `Meta` can seal to `Elab`.

---

# 11. Sealing to `Elab`

The closure boundary is explicit:

```text
Meta -> Elab
```

Expansion and sealing use explicit ASDL inputs:

- `MetaFillSet(slot_bindings)`
- `MetaParamBinding(param, value)`
- `MetaExpandEnv(fills, params, rebase_prefix)`
- `MetaSealParamEntry(param, index)`
- `MetaSealEnv(module_name, params)`

These make slot filling, fragment argument substitution, deterministic rebasing,
module identity, and runtime-param-to-`ElabArg` mapping visible to PVM caches
instead of hiding them in opaque Lua context tables.

Suggested sealing phases:

- `seal_meta_type_to_elab`
- `seal_meta_place_to_elab`
- `seal_meta_expr_to_elab`
- `seal_meta_region_to_elab`
- `seal_meta_func_to_elab`
- `seal_meta_const_to_elab`
- `seal_meta_static_to_elab`
- `seal_meta_type_decl_to_elab`
- `seal_meta_module_to_elab`

These phases should produce ordinary current `MoonliftElab` values. After this
boundary, the existing compiler path continues unchanged.

---

# 12. PVM phase plan

The quote system should use explicit `pvm.phase(...)` boundaries.

## 12.1 Construction / parsing

- `parse_source_quote_to_meta_expr_frag`
- `parse_source_quote_to_meta_region_frag`
- `parse_source_quote_to_meta_func`
- `parse_source_quote_to_meta_module`
- builder construction helpers that directly return `Meta` ASDL values

## 12.2 Interface/env synthesis

- `meta_interface_value_env`
- `meta_interface_type_env`
- `meta_interface_layout_env`
- `meta_module_scope_env`

These phases produce explicit environments used by source-quote elaboration and
sealing. Hidden `ctx` bags must not carry semantics.

## 12.3 Normalization / assembly

- `meta_with_slots`
- `meta_expand_expr_frag_uses`
- `meta_expand_region_frag_uses`
- `meta_expand_item_splices`
- `meta_alpha_normalize`
- `meta_validate_closedness`

## 12.4 Sealing

- `seal_meta_*_to_elab`

All meaningful dispatch in these stages should be through ASDL variants and
`pvm.phase(...)`, not raw string/type helper switches.

---

# 13. Codegen design consequences

The quote system exists partly to let Lua metaprograms shape low-level Moonlift
code deliberately. That shaping must be structural.

Do preserve explicit forms for:

- `select` as branchless/dataflow choose,
- `if` as control flow,
- `switch` as dispatch,
- explicit loop carries and `next`,
- range/view/zip domains,
- intrinsics such as `fma`, rotates, popcount, etc.,
- view construction forms,
- function vs fragment boundaries.

Do not encode those choices as:

- backend hints in strings,
- Lua booleans on builder objects,
- comments/pragmas,
- ad hoc Rust-side IR.

If a code-shape choice matters, it belongs in ASDL.

---

# 14. Implementation staging

The ASDL step is intentionally **not phased**: `MoonliftMeta` exists as one coherent open-code vocabulary in `moonlift/lua/moonlift/asdl.lua`.

Operational implementation can still be staged honestly:

1. [x] Implement builder-created `MetaExprFrag` and `MetaRegionFrag` construction.
2. [x] Implement deterministic binder-id rebasing for fragment expansion through explicit `use_id` fields.
3. [x] Implement `meta_with_slots` / expansion structurally for every slot kind.
4. [x] Implement sealing-time closedness validation for unfilled slots and unexpanded splices.
5. [x] Implement initial `Meta -> Elab` sealing.
6. [x] Route sealed `Elab` through the existing `Elab -> Sem -> Back` path.
7. [x] Add source-string quote parsing after the ASDL/phase spine exists.
8. [x] Add module/function/const/static/type-item assembly operations.
9. [x] Add quote-time walk/query/rewrite APIs over `Meta`.

Do not start by designing only syntax. The ASDL layer and sealing boundary are the architecture.

---

# 15. Current non-goals

The quote system should not initially implement:

- a second backend IR,
- open `Sem`,
- textual macro expansion,
- implicit Lua capture,
- random gensym hygiene,
- direct Rust-side quote handling,
- hosted parser/session integration.

Future hosted integration may provide nicer syntax and object lifetimes, but it
must still converge to the same `MoonliftMeta` ASDL layer.

---

# 16. Summary

The fixed design is:

1. Keep the closed compiler path:

   ```text
   Surface -> Elab -> Sem -> Back
   ```

2. Add one open-code layer:

   ```text
   Meta
   ```

3. Make `Meta` an open mirror of current `Elab`, not open source and not open
   machine semantics.

4. Represent all quote dependencies as:

   ```text
   params / imports / slots
   ```

5. Keep fragments, functions, consts, statics, type declarations, items, and
   modules as distinct ASDL nouns.

6. Normalize and fill slots structurally inside `Meta`.

7. Seal closed `Meta` into ordinary `Elab`.

8. Let the existing compiler continue:

   ```text
   Elab -> Sem -> Back -> Artifact
   ```

That gives Moonlift Terra-like metaprogramming ergonomics without inheriting a
string/template macro architecture. The quote system is a typed open-code
compiler layer, not a source interpolation feature.
