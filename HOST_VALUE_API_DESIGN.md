# Moonlift Hosted Value API Design

Status: design target / implementation plan.

This document designs the Terra-like host-side niceties for Moonlift:

```text
types are host values
structs/unions are host values
functions/modules/fragments are host values
expressions/statements/regions can be built directly from Lua
```

The goal is Terra-like ergonomics without giving Lua objects hidden compiler
semantics.  The hosted API is only a convenient constructor layer for explicit
Moon2 ASDL values, which then flow through the normal PVM phases.

Moonlift deliberately does **not** pursue source-level generics as the primary
abstraction model.  Lua is the metalanguage.  Moonlift source is the closed,
typed object language.  Type/function/fragment families should be Lua-hosted
templates over ASDL-backed values, not a second generic language inside
Moonlift source.

Companion docs:

- `moonlift/README.md`
- `moonlift/SOURCE_GRAMMAR.md`
- `moonlift/HOSTED_CONTINUATION_LANGUAGE_PLAN.md`
- `moonlift/ASDL2_REFACTOR_MAP.md`
- `moonlift/FILE_NAMING.md`
- `docs/PVM_DISCIPLINE.md`

---

## 1. Core thesis

Terra has a pleasant host model:

```lua
local S = terralib.types.newstruct("S")
S.entries = {
    {"x", int},
    {"y", int},
}
```

Moonlift should provide the same class of convenience:

```lua
local moon = require("moonlift.host")

local M = moon.module("Demo")

local Pair = M:struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})

M:export_func("sum_pair", {
    moon.param("p", moon.ptr(Pair)),
}, moon.i32, function(fn)
    local p = fn:param("p")
    fn:return_(p:field("x") + p:field("y"))
end)

local compiled = M:compile()
local sum_pair = compiled:get("sum_pair")
```

But the semantic meaning must be ordinary Moon2 values:

```text
TypeDeclStruct("Pair", FieldDecl*)
TNamed(TypeRefLocal(TypeSym(...)))
FuncExport(...)
ExprField(... FieldByName ...)
```

No host-side table should become a second compiler IR.  Host values must either
wrap ASDL directly or be immutable drafts/events that lower to ASDL before any
semantic phase.

---

## 2. PVM design note

### Source ASDL

Existing types affected:

- `Moon2Core.TypeSym`, `FuncSym`, `Id`
- `Moon2Type.Type`, `Param`, `FieldDecl`, `VariantDecl`
- `Moon2Tree.TypeDecl`, `Item`, `Module`, `Func`, `Expr`, `Stmt`, `Place`
- `Moon2Tree.ControlStmtRegion`, `ControlExprRegion`, `BlockLabel`, `JumpArg`
- `Moon2Open.TypeSlot`, `ValueSlot`, `ExprSlot`, `ContSlot`, `SlotBinding`
- `Moon2Sem.FieldRef`, `CallTarget`, `TypeLayout`, `MemLayout`

New ASDL needed initially:

- None in the compiler core for the first implementation slice.
- Host wrapper values may be plain Lua objects if they contain explicit ASDL.
- If mutable draft builders are added, introduce a host/project ASDL event model
  rather than hidden mutable tables.

Potential later ASDL if host construction needs persistent design state:

```text
HostTypeEvent = HostBeginStruct(sym, name)
              | HostAddStructField(sym, name, ty)
              | HostSealStruct(sym)

HostTypeDraft = HostStructDraft(sym, name, fields, status)
```

User-authored fields:

- type names
- field names and order
- function names, visibility, params, result
- expression/statement builder calls
- region labels, jump arg names, continuation fill names

Derived fields excluded from host values:

- field offsets
- memory layouts
- ABI lowering classes
- backend value ids
- vectorization facts
- proof/reject decisions

### Events / Apply

Initial immutable API:

```text
moon.struct(name, fields) -> StructValue wrapping TypeDeclStruct + TNamed
module:add_type(struct) -> new/updated ModuleValue item stream
```

Mutable draft API, if added later:

```text
BeginStruct -> AddField* -> SealStruct
Apply(HostTypeDraft, HostTypeEvent) -> HostTypeDraft
```

Pure state transition:

- each event returns a new draft state
- duplicate fields or seal-after-use produce explicit host issues
- sealing produces a `TypeDecl*` ASDL value

State fields changed through structural update:

- `fields`
- `status`
- optional `issues`

### Phase boundaries

Boundary name: host value construction

- Question answered: what ASDL does this ergonomic host object represent?
- Input type: Lua API call / host wrapper value
- Output shape: Moon2 ASDL value or explicit host construction issue
- Cache key: stable symbol key + structural contents
- Extra args: host session for symbol allocation only

Boundary name: host module finalization

- Question answered: is the module builder closed enough to compile?
- Input type: `ModuleValue`
- Output shape: `Moon2Tree.Module(ModuleSurface | ModuleOpen)` plus host issues
- Cache key: module id + item list hash
- Extra args: symbol namespace/session

Boundary name: normal compiler pipeline

```text
Moon2Tree.Module
  -> open facts / open validate / open expand
  -> typecheck
  -> semantic decisions
  -> tree/vector lowering
  -> Moon2Back.BackProgram
```

Reflection boundaries:

```text
TypeValue -> TypeClass
TypeValue -> TypeMemLayoutResult
TypeValue -> AbiDecision
StructValue -> TypeLayout
```

These must return explicit ASDL result values, not ad-hoc Lua booleans.

### Field classification

Code-shaping fields:

- type constructors (`ptr`, `view`, `func_type`, `struct`, `union`)
- function visibility
- statement/control constructors
- continuation slots/fills

Payload fields:

- names
- literals
- source hints for diagnostics
- ordered field lists
- optional source spans

Dead fields to avoid:

- host-computed offsets
- host-computed ABI classes
- hidden capture environments
- implicit module-global type registries
- unordered Lua map field lists as semantic order

### Execution

Flat fact / command type:

- final execution remains `Moon2Back.Cmd*`
- host values do not execute directly

Push/pop stack state:

- handled by existing bind/residence/type/backend phases
- host values must not allocate stack slots directly

Final loop behavior:

- unchanged: backend consumes flat commands
- loops remain explicit block/jump regions before lowering

### Diagnostics

Expected PVM reuse:

- Type/class/layout/ABI phases should reuse across host-built and parsed source
- Open expansion should reuse fragment values by structural identity/symbol key

Possible cache failure modes:

- unstable generated symbol keys
- mutable host drafts reused after sealing
- source-string fallback hiding structural equality
- unordered table iteration changing field/item order

---

## 3. Design invariants

### 3.1 Host API is not semantic authority

The host API may be ergonomic, but semantic truth is ASDL:

```text
Lua object method call
  -> explicit Moon2 ASDL
  -> PVM phase
  -> explicit facts / decisions / rejects
```

Forbidden patterns:

- host object fields such as `offset`, `abi_class`, `backend_id` that bypass phases
- Lua closures carrying semantic context invisible to ASDL
- implicit global registries deciding type identity
- runtime function pointers used to simulate continuation fragments

### 3.2 Types are values, but typed ASDL values

A type host value must wrap a `Moon2Type.Type`:

```lua
moon.i32        -- Ty.TScalar(Core.ScalarI32)
moon.ptr(T)     -- Ty.TPtr(T.ty)
moon.view(T)    -- Ty.TView(T.ty)
```

Source strings may be retained as pretty hints, not as the primary meaning.

### 3.3 Struct identity is symbolic and stable

A named type value must carry a stable symbol:

```text
TypeSym(key, name)
TNamed(TypeRefLocal(sym))
```

The `key` is for identity/hygiene.  The `name` is for diagnostics/source-facing
pretty printing.

### 3.4 Field order is semantic

Struct fields must be passed as an ordered sequence:

```lua
moon.struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})
```

A keyed convenience form may exist only if it normalizes immediately to an
ordered list with explicit order policy.

### 3.5 Reflection returns decisions

Reflection should expose existing phases:

```lua
local class = session:classify_type(T)
local layout = session:layout_of(T)
local abi = session:abi_of(T)
```

Return ASDL-backed values such as:

```text
TypeClassScalar(...)
TypeClassAggregate(...)
TypeMemLayoutKnown(...)
AbiDirect(...)
AbiIndirect(...)
AbiUnknown(...)
```

---

## 4. Public API target

The eventual public facade should be a thin module:

```lua
local moon = require("moonlift.host")
```

This facade may re-export precise implementation files:

```text
host_type_values.lua
host_struct_values.lua
host_expr_values.lua
host_func_values.lua
host_region_values.lua
host_module_values.lua
host_session.lua
```

The facade itself must not own semantic decisions.

---

## 5. Type values

### 5.1 TypeValue shape

```lua
TypeValue = {
    kind = "type",
    ty = Moon2Type.Type,
    source_hint = "i32", -- optional
    sym = TypeSym?,      -- for named/local types
}
```

### 5.2 Constructors

```lua
moon.void
moon.bool
moon.i8;  moon.i16;  moon.i32;  moon.i64
moon.u8;  moon.u16;  moon.u32;  moon.u64
moon.f32; moon.f64
moon.index

moon.ptr(elem)
moon.array(count_expr_or_number, elem)
moon.slice(elem)
moon.view(elem)
moon.func_type(params, result)
moon.closure_type(params, result)
moon.named(module_name, type_name)
```

Examples:

```lua
local T = moon.i32
local P = moon.ptr(T)
local V = moon.view(T)
local F = moon.func_type({ moon.i32, moon.i32 }, moon.i32)
```

ASDL mapping:

```text
moon.i32                 -> TScalar(ScalarI32)
moon.ptr(T)              -> TPtr(T.ty)
moon.view(T)             -> TView(T.ty)
moon.func_type(ps, ret)  -> TFunc(ps.ty*, ret.ty)
```

### 5.3 Type splicing compatibility

The existing source-splice path should remain:

```lua
func f(x: @{moon.i32}) -> @{moon.i32}
    return x
end
```

But `moon.i32:moonlift_splice_source()` is only a compatibility view over the
ASDL value.

---

## 6. Field values

### 6.1 FieldValue shape

```lua
FieldValue = {
    kind = "field",
    name = "x",
    type = TypeValue,
    decl = Moon2Type.FieldDecl,
}
```

### 6.2 Constructor

```lua
moon.field(name, type_value)
```

Example:

```lua
local x = moon.field("x", moon.i32)
```

ASDL mapping:

```text
FieldDecl("x", TScalar(ScalarI32))
```

Validation questions:

- field name is a valid identifier
- field type is a `TypeValue`
- duplicate field names are reported by the struct builder
- field order is preserved

---

## 7. Struct and union values

### 7.1 StructValue shape

```lua
StructValue = {
    kind = "struct",
    name = "Pair",
    sym = TypeSym,
    fields = FieldValue*,
    decl = Moon2Tree.TypeDeclStruct or TypeDeclOpenStruct,
    ty = TypeValue(TNamed(TypeRefLocal(sym))),
}
```

The value should behave as a type value where a type is expected:

```lua
moon.ptr(Pair)
```

must be accepted and interpreted as:

```text
TPtr(Pair.ty.ty)
```

### 7.2 Closed struct constructor

```lua
local Pair = moon.struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})
```

ASDL mapping:

```text
TypeDeclStruct("Pair", [
    FieldDecl("x", TScalar(ScalarI32)),
    FieldDecl("y", TScalar(ScalarI32)),
])
```

If constructed inside a module, prefer a local symbol form:

```text
TypeDeclOpenStruct(TypeSym(key, "Pair"), fields)
TNamed(TypeRefLocal(TypeSym(key, "Pair")))
```

This gives hygiene without losing the pretty name.

### 7.3 Module-owned struct constructor

Preferred user-facing form:

```lua
local M = moon.module("Demo")

local Pair = M:struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})
```

This appends:

```text
ItemType(TypeDeclStruct/OpenStruct(...))
```

to the module item stream.

### 7.4 Union and enum sugar

Mirror the existing ASDL:

```lua
local Bits = M:union("Bits", {
    moon.field("i", moon.i32),
    moon.field("f", moon.f32),
})

local Color = M:enum("Color", { "red", "green", "blue" })

local Result = M:tagged_union("Result", {
    moon.variant("ok", moon.i32),
    moon.variant("err", moon.i32),
})
```

ASDL mapping:

```text
TypeDeclUnion(...)
TypeDeclEnumSugar(...)
TypeDeclTaggedUnionSugar(...)
```

### 7.5 Draft/seal API for recursive types

A closed constructor is best for most cases, but recursive types need a draft:

```lua
local Node = M:newstruct("Node")
Node:add_field("value", moon.i32)
Node:add_field("next", moon.ptr(Node))
Node:seal()
```

Rules:

- `Node` is usable as a named type immediately after `newstruct`.
- fields cannot be inspected as a sealed declaration before `seal`.
- adding fields after `seal` reports a host construction issue.
- `seal` emits the `TypeDecl*` item exactly once.

Recommended internal design:

```text
HostStructDraft + HostTypeEvent + Apply
```

Do not implement recursive structs by mutating a hidden field list that bypasses
host validation.

---

## 8. Parameter and binding values

### 8.1 ParamValue

```lua
moon.param("x", moon.i32)
```

ASDL mapping:

```text
Moon2Type.Param("x", TScalar(ScalarI32))
```

For function builder scopes, the parameter also has a binding:

```text
Binding(Id("arg:func:x"), "x", ty, BindingClassArg(index))
```

### 8.2 Local values

Function/region builders should expose local binding values:

```lua
local x = fn:param("x")
local tmp = fn:let("tmp", moon.i32, x + moon.int(1))
```

ASDL mapping:

```text
StmtLet(StmtSurface, binding, init)
ExprRef(ExprSurface, ValueRefBinding(binding))
```

---

## 9. Expression values

### 9.1 ExprValue shape

```lua
ExprValue = {
    kind = "expr",
    expr = Moon2Tree.Expr,
    type = TypeValue?,
}
```

### 9.2 Literal constructors

```lua
moon.int(1)
moon.float("1.5")
moon.bool_lit(true)
moon.nil_lit()
```

ASDL mapping:

```text
ExprLit(ExprSurface, LitInt("1"))
ExprLit(ExprSurface, LitFloat("1.5"))
ExprLit(ExprSurface, LitBool(true))
ExprLit(ExprSurface, LitNil)
```

### 9.3 Operator constructors

Lua metamethods may build expression ASDL:

```lua
x + y       -> ExprBinary(... BinAdd ...)
x - y       -> ExprBinary(... BinSub ...)
x * y       -> ExprBinary(... BinMul ...)
-x          -> ExprUnary(... UnaryNeg ...)
```

Lua cannot overload every Moonlift operator cleanly, so provide named methods:

```lua
x:eq(y)
x:ne(y)
x:lt(y)
x:le(y)
x:gt(y)
x:ge(y)
x:band(y)
x:bor(y)
x:bxor(y)
x:shl(y)
x:lshr(y)
x:ashr(y)
x:select(then_value, else_value)
```

### 9.4 Field and index access

```lua
p:field("x")
xs:index(i)
```

ASDL mapping:

```text
ExprField(h, base, FieldByName("x", ty_or_unknown))
ExprIndex(h, IndexBaseExpr(base), index)
```

The host API must not compute field offsets.  Offset resolution belongs to
`sem_layout_resolve.lua` and related phases.

### 9.5 Calls and intrinsics

```lua
fn_ref:call(args)
moon.intrinsic("popcount", { x })
x:as(moon.i32)
```

ASDL mapping:

```text
ExprCall(... CallUnresolved/CallDirect ..., args)
ExprIntrinsic(... IntrinsicPopcount ..., args)
ExprCast(... SurfaceCastOp ..., ty, value)
```

---

## 10. Statement and function builders

### 10.1 Function builder API

```lua
M:export_func("add", {
    moon.param("a", moon.i32),
    moon.param("b", moon.i32),
}, moon.i32, function(fn)
    local a = fn:param("a")
    local b = fn:param("b")
    fn:return_(a + b)
end)
```

ASDL mapping:

```text
FuncExport("add", params, result, [
    StmtReturnValue(StmtSurface,
        ExprBinary(ExprSurface, BinAdd, ExprRef(a), ExprRef(b)))
])
```

### 10.2 Statement methods

```lua
fn:let(name, ty, init)
fn:var(name, ty, init)
fn:set(place, value)
fn:expr(expr)
fn:if_(cond, then_builder, else_builder?)
fn:return_(expr?)
```

These build `Moon2Tree.Stmt` values.

### 10.3 Function value shape

```lua
FuncValue = {
    kind = "func",
    name = "add",
    visibility = VisibilityExport,
    params = ParamValue*,
    result = TypeValue,
    func = Moon2Tree.Func,
    type = TypeValue(TFunc(...)),
}
```

---

## 11. Module values

### 11.1 ModuleValue shape

```lua
ModuleValue = {
    kind = "module",
    name = "Demo",
    items = ItemValue*,
    module = Moon2Tree.Module?, -- produced on finalization
    session = HostSession,
}
```

### 11.2 API

```lua
local M = moon.module("Demo")

M:add_type(Pair)
M:add_func(f)
M:struct(...)
M:union(...)
M:export_func(...)
M:extern_func(...)
M:const(...)
M:static(...)

local tree_module = M:to_asdl()
local compiled = M:compile()
```

`to_asdl()` must be deterministic and should not silently mutate semantic state.

---

## 12. Region, block, and continuation values

Moonlift should expose its distinctive control model directly.

### 12.1 Region fragment builder

Target API:

```lua
local scan_until = moon.region_frag("scan_until", {
    moon.param("p", moon.ptr(moon.u8)),
    moon.param("n", moon.i32),
    moon.param("target", moon.i32),
}, {
    hit = moon.cont({ moon.param("pos", moon.i32) }),
    miss = moon.cont({ moon.param("pos", moon.i32) }),
}, function(r)
    local loop = r:entry("loop", {
        moon.entry_param("i", moon.i32, moon.int(0)),
    })

    loop:if_(r:param("i"):ge(r:param("n")), function()
        r:jump(r.conts.miss, { pos = r:param("i") })
    end)

    r:jump(loop, { i = r:param("i") + moon.int(1) })
end)
```

ASDL mapping:

```text
RegionFrag(params, open_set_with_cont_slots, EntryControlBlock, ControlBlock*)
```

### 12.2 Inline region builder

```lua
fn:return_region(moon.i32, function(r)
    local loop = r:entry("loop", {
        moon.entry_param("i", moon.i32, moon.int(0)),
        moon.entry_param("acc", moon.i32, moon.int(0)),
    })

    loop:if_(loop.i:ge(n), function()
        r:yield_(loop.acc)
    end)

    r:jump(loop, {
        i = loop.i + moon.int(1),
        acc = loop.acc + xs:index(loop.i),
    })
end)
```

ASDL mapping:

```text
ExprControl(ControlExprRegion(...))
```

### 12.3 `jump` vs `emit` in builder API

Preserve the source-language distinction:

```lua
r:jump(block, args)
```

maps to:

```text
StmtJump / StmtJumpCont
```

while:

```lua
r:emit(scan_until, { p, n, target }, { hit = found, miss = missing })
```

maps to:

```text
StmtUseRegionFrag(... SlotBinding(SlotCont(...), SlotValueCont(...)) ...)
```

Expression fragments similarly use:

```lua
moon.emit_expr(clamp_nonneg, { x })
```

mapping to:

```text
ExprUseExprFrag
```

---

## 13. Lua-hosted templates and open slot values

### 13.1 Type parameters are host values, not source generics

```lua
local T = moon.type_param("T")
```

ASDL mapping:

```text
TypeSlot(key, "T")
TSlot(slot)
OpenSet(... SlotType(slot) ...)
```

### 13.2 Struct templates live in Lua

```lua
local Vec2 = moon.struct_template("Vec2", { T }, function(T)
    return {
        moon.field("x", T),
        moon.field("y", T),
    }
end)

local Vec2i = M:instantiate(Vec2, { moon.i32 })
```

Instantiation creates/fills explicit slots:

```text
SlotBinding(SlotType(T_slot), SlotValueType(TScalar(ScalarI32)))
```

Then lowers to an ordinary named struct declaration with a stable generated
`TypeSym`.

### 13.3 Expression/region fragment templates

Fragment families should be Lua-hosted templates using the existing open system:

```lua
local clamp = moon.expr_frag("clamp", { T }, { moon.param("x", T) }, T, function(e)
    ...
end)

moon.emit_expr(clamp:instantiate({ T = moon.i32 }), { x })
```

No specialization should be hidden in Lua-only caches.  Specialization identity
must be visible through symbols/fills.  Do not add source-level generic
constraints/inference/monomorphization; Lua is the metalanguage for those
abstractions.

---

## 14. Reflection/session API

### 14.1 Session value

```lua
local session = moon.session()
local M = session:module("Demo")
```

Session owns:

- symbol allocation policy
- optional compile cache
- optional artifact lifetime tracking
- access to PVM context and phase definitions

### 14.2 Reflection queries

```lua
session:classify_type(T)  -- TypeClass
session:size_align(T)     -- TypeMemLayoutResult
session:abi_of(T)         -- AbiDecision
session:layout_of(S)      -- TypeLayout / TypeMemLayoutResult
```

These are phase calls.  They must not inspect host object internals beyond the
ASDL values.

### 14.3 Ergonomic helpers

Helpers may exist:

```lua
T:is_scalar()
T:is_pointer()
```

but they should be thin wrappers around `TypeClass` decisions and should expose
unknown/reject cases rather than returning misleading booleans.

---

## 15. Error model

Host construction should report structured issues before falling back to raw Lua
errors where possible.

`Moon2Host` now defines explicit hosted construction issues:

```text
HostIssueInvalidName(site, name)
HostIssueExpected(site, expected, actual)
HostIssueDuplicateField(type_name, field_name)
HostIssueDuplicateType(module_name, type_name)
HostIssueDuplicateFunc(module_name, func_name)
HostIssueUnsealedType(module_name, type_name)
HostIssueSealedMutation(type_name)
HostIssueAlreadySealed(type_name)
HostIssueUnknownBinding(site, name)
HostIssueInvalidEmitFill(fragment_name, fill_name)
HostIssueMissingEmitFill(fragment_name, fill_name)
HostIssueArgCount(site, expected, actual)
HostReport(issues)
```

Implementation may still use Lua errors for low-level API misuse, but meaningful
host construction failures should be represented with these ASDL issue values
and raised/reported through `host_issue_values.lua`:

```text
TypeIssue...
ValidationIssue...
ControlReject...
BackValidationIssue...
```

---

## 16. File layout

Use precise file names matching Moonlift discipline.

Recommended initial files:

```text
lua/moonlift/host_type_values.lua
lua/moonlift/host_struct_values.lua
lua/moonlift/host_expr_values.lua
lua/moonlift/host_func_values.lua
lua/moonlift/host_region_values.lua
lua/moonlift/host_module_values.lua
lua/moonlift/host_session.lua
lua/moonlift/host.lua
```

`host.lua` is allowed only as a thin facade.  Semantic construction belongs in
the precise files above.

Tests mirror files:

```text
test_host_type_values.lua
test_host_struct_values.lua
test_host_expr_values.lua
test_host_func_values.lua
test_host_region_values.lua
test_host_module_values.lua
test_host_session.lua
```

---

## 17. Compatibility with current `host_quote.lua`

The current hosted syntax layer should keep working:

```lua
local Host = require("moonlift.host_quote")
```

New APIs can initially reuse its compile path, but the direction is:

```text
host_quote.lua source bootstrap
  -> host values / direct ASDL construction
  -> normal compiler pipeline
```

not:

```text
permanent source-string-only host API
```

Migration path:

1. Keep `host_quote.lua` public.
2. Add `moonlift.host` as new direct-value facade.
3. Let `host_quote.lua` accept/splice new `TypeValue`, `StructValue`,
   `ExprFragValue`, and `RegionFragValue` objects.
4. Gradually replace internals that store only source strings with ASDL-backed
   values.

---

## 18. Example: struct and function builder

Target user code:

```lua
local moon = require("moonlift.host")

local M = moon.module("Demo")

local Pair = M:struct("Pair", {
    moon.field("x", moon.i32),
    moon.field("y", moon.i32),
})

M:export_func("sum_pair", {
    moon.param("p", moon.ptr(Pair)),
}, moon.i32, function(fn)
    local p = fn:param("p")
    fn:return_(p:field("x") + p:field("y"))
end)

local compiled = M:compile()
local sum_pair = compiled:get("sum_pair")
```

Equivalent source:

```moonlift
type Pair = struct
    x: i32
    y: i32
end

export func sum_pair(p: ptr(Pair)) -> i32
    return p.x + p.y
end
```

Equivalent ASDL outline:

```text
Module(ModuleSurface, [
  ItemType(TypeDeclStruct("Pair", [
    FieldDecl("x", TScalar(ScalarI32)),
    FieldDecl("y", TScalar(ScalarI32)),
  ])),
  ItemFunc(FuncExport("sum_pair",
    [Param("p", TPtr(TNamed(TypeRefLocal(pair_sym))))],
    TScalar(ScalarI32),
    [StmtReturnValue(ExprField(
      ExprSurface,
      ExprRef(ExprSurface, ValueRefBinding(p_binding)),
      FieldByName("x", TScalar(ScalarI32))
    ) + ...)]
  ))
])
```

---

## 19. Example: Terra-like recursive struct draft

Target user code:

```lua
local M = moon.module("ListDemo")

local Node = M:newstruct("Node")
Node:add_field("value", moon.i32)
Node:add_field("next", moon.ptr(Node))
Node:seal()
```

Design meaning:

```text
BeginStruct(node_sym, "Node")
AddStructField(node_sym, "value", i32)
AddStructField(node_sym, "next", ptr(TNamed(node_sym)))
SealStruct(node_sym)
```

Final ASDL:

```text
ItemType(TypeDeclOpenStruct(node_sym, [
  FieldDecl("value", TScalar(ScalarI32)),
  FieldDecl("next", TPtr(TNamed(TypeRefLocal(node_sym)))),
]))
```

---

## 20. Example: continuation fragment builder

Target user code:

```lua
local scan_until = moon.region_frag("scan_until", {
    moon.param("p", moon.ptr(moon.u8)),
    moon.param("n", moon.i32),
    moon.param("target", moon.i32),
}, {
    hit = moon.cont({ moon.param("pos", moon.i32) }),
    miss = moon.cont({ moon.param("pos", moon.i32) }),
}, function(r)
    local loop = r:entry("loop", {
        moon.entry_param("i", moon.i32, moon.int(0)),
    })

    r:if_(r.i:ge(r.n), function()
        r:jump(r.conts.miss, { pos = r.i })
    end)

    r:if_(r.p:index(r.i):as(moon.i32):eq(r.target), function()
        r:jump(r.conts.hit, { pos = r.i })
    end)

    r:jump(loop, { i = r.i + moon.int(1) })
end)
```

Use:

```lua
fn:return_region(moon.i32, function(r)
    local start = r:entry("start")
    local found = r:block("found", { moon.param("pos", moon.i32) }, function(b)
        r:yield_(b.pos)
    end)
    local missing = r:block("missing", { moon.param("pos", moon.i32) }, function()
        r:yield_(moon.int(-1))
    end)

    start:emit(scan_until, { p, n, target }, {
        hit = found,
        miss = missing,
    })
end)
```

ASDL distinction remains:

```text
jump -> StmtJump / StmtJumpCont
emit -> StmtUseRegionFrag + SlotBinding(SlotCont, SlotValueCont)
```

---

## 21. Implementation checklist

### Phase 0 — design/documentation

- [x] Write hosted value API design document.
- [x] Add README pointer to this document.
- [x] Decide public facade name: `moonlift.host` vs extending
      `moonlift.host_quote`.
- [x] Decide initial symbol key policy for host-created local types/functions.

### Phase 1 — ASDL-backed `TypeValue`

Files:

```text
host_type_values.lua
test_host_type_values.lua
```

Tasks:

- [x] Define `TypeValue` wrapper containing `Moon2Type.Type`.
- [x] Implement scalar singletons: `void`, `bool`, ints, uints, floats, `index`.
- [x] Implement `ptr`, `array`, `slice`, `view`, `func_type`, `closure_type`.
- [x] Implement `named` / local named type wrapper.
- [x] Implement `moonlift_splice_source()` compatibility.
- [x] Tests assert ASDL class/fields, not only string spelling.
- [x] Tests verify current `host_quote.lua` can splice new type values.

### Phase 2 — fields, structs, unions, enums

Files:

```text
host_struct_values.lua
test_host_struct_values.lua
```

Tasks:

- [x] Define `FieldValue` wrapper.
- [x] Implement `field(name, ty)`.
- [x] Define `StructValue` as type-like wrapper.
- [x] Implement closed `struct(name, fields)`.
- [x] Implement module-owned `M:struct(name, fields)`.
- [x] Implement `union`, `enum`, `tagged_union` wrappers.
- [x] Preserve field order deterministically.
- [x] Reject duplicate field names with explicit host issue/error.
- [x] Ensure `moon.ptr(StructValue)` works.
- [x] Lower module-owned type declarations to `ItemType`.

### Phase 3 — module/session facade

Files:

```text
host_module_values.lua
host_session.lua
host.lua
test_host_module_values.lua
test_host_session.lua
```

Tasks:

- [x] Implement `moon.session()`.
- [x] Implement deterministic symbol allocation in session.
- [x] Implement `moon.module(name)` / `session:module(name)`.
- [x] Implement `ModuleValue:add_type`, `add_func`, `to_asdl`.
- [x] Implement `ModuleValue:compile()` through existing parse-free pipeline.
- [x] Make `host.lua` a thin facade only.
- [x] Verify generated `Moon2Tree.Module` passes typecheck/back validation for
      simple scalar functions.

### Phase 4 — expression values

Files:

```text
host_expr_values.lua
test_host_expr_values.lua
```

Tasks:

- [x] Define `ExprValue` wrapper.
- [x] Implement literal constructors.
- [x] Implement refs from bindings/params.
- [x] Implement arithmetic metamethods.
- [x] Implement named compare/bit/shift/select methods.
- [x] Implement cast/intrinsic helpers.
- [x] Implement `load`, `addr_of`, and richer place-producing helpers. (`field`, `index`, binding-place, indexed-place, deref-place, place-field, `load`, and `addr_of` helpers exist; backend lowering covers scalar loads, pointer deref, indexed addresses, deref addresses, resolved field offsets, and stores through those places.)
- [x] Ensure field access emits `FieldByName`, not host-computed offsets.
- [x] Tests compare built ASDL against expected `Expr*` nodes.

### Phase 5 — function builder

Files:

```text
host_func_values.lua
test_host_func_values.lua
```

Tasks:

- [x] Define `ParamValue` and function-scope binding values.
- [x] Implement `M:func` and `M:export_func`.
- [x] Implement statement methods: `let`, `var`, `set`, `expr`, `if_`, `return_`.
- [x] Ensure function params become `BindingClassArg(index)` bindings.
- [x] Lower functions directly to `FuncLocal` / `FuncExport`.
- [x] Compile and run `add`, `select`, and simple pointer load/store examples. (`test_host_value_jit.lua`, `test_host_addr_load_jit.lua`, and `test_host_field_jit.lua` execute scalar/conditional/fragment/region, pointer load/store, and struct field store/load functions.)

### Phase 6 — recursive draft/seal structs

Files:

```text
host_struct_values.lua
test_host_struct_draft_values.lua
```

Tasks:

- [x] Implement `M:newstruct(name)` returning a draft named type.
- [x] Implement `draft:add_field(name, ty)`.
- [x] Implement `draft:seal()`.
- [x] Forbid mutation after seal.
- [x] Forbid module finalization with unsealed drafts.
- [x] Ensure self-references lower to named type references. (Current first slice uses `TNamed(TypeRefGlobal(module, name))`; local-symbol hygiene remains a later refinement.)
- [x] Consider adding explicit host event/apply ASDL if draft complexity grows. (Current draft complexity is covered by `Moon2Host.HostIssue`; a separate event/apply state is intentionally deferred until mutable drafts need replay/history.)

### Phase 7 — region/block/continuation builder

Files:

```text
host_region_values.lua
test_host_region_values.lua
```

Tasks:

- [x] Define `ContValue`, `BlockValue`, `RegionValue`, `RegionFragValue` wrappers. (Initial implementation has `ContValue`, `BlockValue`, `RegionFragValue`, `RegionBuilder`, and `BlockBuilder`; a persistent standalone `RegionValue` remains future polish.)
- [x] Implement `cont(params)`.
- [x] Implement `entry_param(name, ty, init)`.
- [x] Implement inline `return_region(result_ty, builder)`.
- [x] Implement `region_frag(name, runtime_params, cont_params, builder)`.
- [x] Implement `jump(block_or_cont, named_args)`.
- [x] Implement `yield_(expr?)`.
- [x] Implement `emit(region_frag, runtime_args, cont_fills)`.
- [x] Ensure `jump` and `emit` lower to distinct ASDL variants.
- [x] Compile and run jump-first continuation-region examples. (`test_host_value_jit.lua` executes an inline counted region; `test_host_region_values.lua` validates a region-fragment `emit` path through backend validation.)

### Phase 8 — expression fragments and Lua-hosted open values

Files:

```text
open_fragment_values.lua
test_open_fragment_values.lua
```

Tasks:

- [x] Implement ASDL-backed `expr_frag` builder.
- [x] Implement `emit_expr(frag, args)`.
- [x] Implement `type_param(name)` using `TypeSlot` / `TSlot`.
- [x] Implement slot fills for type-param instantiation.
- [x] Implement `struct_template` and `instantiate` for simple type parameters.
- [x] Tests cover Lua-hosted `Vec2(T)`-style instantiation.
- [x] Tests cover Lua-hosted expression fragment specialization.

### Phase 9 — reflection phase wrappers

Files:

```text
host_session.lua
test_host_reflection.lua
```

Tasks:

- [x] Implement `session:classify_type(T)` returning `TypeClass`.
- [x] Implement `session:size_align(T)` returning `TypeMemLayoutResult`.
- [x] Implement `session:abi_of(T)` returning `AbiDecision`.
- [x] Implement `session:layout_of(StructValue)` returning layout decision/result.
- [x] Ensure helpers do not bypass semantic phases for classify/size/ABI. (`layout_of` creates explicit `TypeLayout` facts from host struct ASDL for use by those phases.)
- [x] Tests assert unknown/reject paths are explicit.

### Phase 10 — integration and migration

Files:

```text
host_quote.lua
host.lua
README.md
IMPLEMENTATION_CHECKLIST.md
```

Tasks:

- [x] Make hosted source splicing accept all new host value classes where cross-context ASDL is safe. (`test_host_quote_value_splice.lua` covers `TypeValue` source splicing; direct ASDL fragment values remain direct-builder values rather than cross-context source-quote payloads.)
- [x] Keep existing `Host.eval`, `Host.loadfile`, `.mlua` behavior working.
- [x] Add examples comparing source quote vs direct builder ASDL.
- [x] Add README documentation for direct hosted value API.
- [x] Update implementation checklist as phases land.
- [x] Add end-to-end tests that compile and execute builder-created modules.

---

## 22. Acceptance criteria

The feature is ready when all of these are true:

- [x] A user can create scalar/pointer/view/function types as host values.
- [x] A user can create structs/unions/enums as host values.
- [x] Struct declarations become ordinary `ItemType(TypeDecl*)` ASDL.
- [x] A user can build and compile a module without source strings.
- [x] Function params, locals, expressions, and returns lower to `Moon2Tree` ASDL.
- [x] Field access goes through `FieldByName` and semantic layout resolution. (Expression/place field nodes emit `FieldByName`; host module compilation supplies explicit layout facts and backend lowering handles resolved offset field places.)
- [x] Recursive struct drafts are possible without hidden compiler state.
- [x] Region fragments can be built and emitted with explicit continuation fills.
- [x] Type slots/fills work for at least simple Lua-hosted struct templates.
- [x] Reflection APIs return ASDL decisions/results.
- [x] Existing hosted source syntax remains compatible.
- [x] All implementation files follow Moonlift naming discipline.

---

## 23. Summary

The missing Terra-like niceties should be added as a hosted value layer:

```text
TypeValue / StructValue / ExprValue / FuncValue / RegionValue / ModuleValue
```

But every value must lower to explicit Moon2 ASDL before semantic work:

```text
nice Lua API
  -> Moon2 ASDL
  -> PVM phases
  -> facts / decisions / rejects
  -> Moon2Back commands
```

This gives Moonlift Terra-style convenience while preserving the core Moonlift
advantage: meaning remains explicit, inspectable, cacheable, and phase-owned.
