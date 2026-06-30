# Lalin ASDL Guide

This guide is the working doctrine for ASDL modeling in Lalin compiler code.
It is intentionally stricter than Terra's public ASDL examples. Lalin uses the
Terra-style ASDL runtime pattern, but compiler semantics must be schema-owned,
typed, and leaf-method driven.

## Core Rule

ASDL is the semantic model. Lua methods explain ASDL behavior; they do not create
a second untyped model beside it.

Lalin uses ASDL to make compiler Lua type-safe. Lua is still the implementation
language, but ASDL is the boundary that keeps compiler state, facts, decisions,
and IR from becoming arbitrary tables. Sidestepping ASDL in a compiler-scale
codebase recreates table soup: meanings move into conventions, bugs hide in
missing fields, and dispatch spreads through helpers instead of living on the
types that own it.

This matches ASDL's historical purpose. ASDL was created to describe compiler
IR and syntax trees with a rich algebraic type vocabulary while still targeting
low-level implementation languages. In practice it gives languages like C, and
for Lalin Lua, the missing product/sum discipline needed to build large compiler
systems without reducing every semantic object to an untyped record.

Good ASDL design is also excellent for AI-assisted maintenance because it
localizes attention. If behavior lives on the ASDL leaf that owns the semantic
case, an agent can inspect the schema, open the leaf method, and reason locally.
If behavior is spread through side tables, rule runners, handler maps, and
string dispatch, the agent has to reconstruct a hidden architecture from global
search results and is much more likely to make a bad patch.

When compiler code needs to classify a value, choose an alternative, remember a
fact, pass state, return a decision, or route to behavior, first ask what ASDL
type is missing. Add that product, union, leaf, field, projection, facet, or
result before writing implementation code.

## Products And Unions

Use products for records with named fields:

```lua
product. ScheduleEmitterCapability {
  interned,
  kind [str],
  executable [bool],
  reason [str],
  rejects [many [LalinSchedule.ScheduleReject]],
}
```

Use unions for alternatives:

```lua
sum. SchedulePlanSelection {
  ScheduleSelectionNoPlan {
    variant_unique,
    rejects [many [LalinSchedule.ScheduleReject]],
  },
  ScheduleSelectionPlanned {
    variant_unique,
    schedule [LalinSchedule.ScheduleKind],
    capability [LalinSchedule.ScheduleEmitterCapability],
    rejected_alternatives [many [LalinSchedule.ScheduleReject]],
  },
}
```

Do not encode alternatives as string tags, boolean flags, optional clusters, or
one product with many nullable fields.

## Leaf Methods Are Dispatch

For a union operation, install the method on each concrete union leaf that owns
the behavior. Calling the method is the dispatch.

Correct:

```lua
function Tree.ExprCall:typecheck(input)
  return Tree.TypeExprResult(...)
end

function Tree.ExprInt:typecheck(input)
  return Tree.TypeExprResult(...)
end
```

Wrong:

```lua
local handlers = {
  ExprCall = function(expr, input) ... end,
  ExprInt = function(expr, input) ... end,
}

function typecheck_expr(expr, input)
  return handlers[expr.kind](expr, input)
end
```

Parent union methods are only shared defaults or explicit delegation contracts.
They must not inspect child classes, `kind` strings, action names, tags, or
selector tables to choose behavior.

## Methodification

When a Lua API mainly operates on one semantic thing, make that thing an ASDL
product or union and install the API as a method on it.

Correct:

```lua
local result = request:compile()
local code = typed_module:lower_to_code(input)
local artifact = plan:materialize()
```

Wrong:

```lua
local result = compile(source, opts)
local code = lower(module, ctx, facts, flags)
local artifact = materialize(kind, payload, tables)
```

The receiver should be a deep semantic object: it owns the data, invariants,
operation vocabulary, and typed result shape. If there is no honest receiver for
an operation, the schema is probably missing a product such as
`CompilationRequest`, `TypedModule`, `CodeEmissionRequest`, `KernelPlanRequest`,
or another domain-specific value.

Free helper functions are allowed only for small implementation details whose
main subject is not an ASDL semantic value. If a helper takes an ASDL value as
the thing it is really about, move it onto that ASDL type. If a public function
takes loose Lua arguments, replace the argument bundle with an ASDL request
product and call a method on that product.

Avoid half-methodification. A method that returns a string, boolean, or selector
only so another function can branch later is still external dispatch. Prefer a
leaf method that performs the next semantic action directly, or return a typed
ASDL result union whose leaves own the next method.

## Object Wiring Is The Good Part

ASDL objects make compiler Lua sane because the semantic entrypoint is attached
to the value that owns the meaning. If the root thing is a `CompilationUnit`
ASDL value and the result should be compiled code, the clear Lua shape is:

```lua
local artifact = unit:compile(input)
```

The call is ordinary Lua object wiring, but the receiver and result are ASDL.
`CompilationUnit:compile` calls methods on child ASDL values. Those children
call methods on their children. Each step constructs typed ASDL products/unions
for the next semantic layer. The compiler becomes a tower of typed values and
owned methods instead of a pile of external passes guessing node shapes.

This is why leaf ownership matters. The object method gives Lua a simple local
interface, while ASDL keeps the data and dispatch type-safe. The method chain
should read like:

```lua
module:lower_to_code(...)
func:lower_to_code(...)
stmt:lower_to_code(...)
expr:lower_to_code(...)
```

Each method returns declared ASDL results, not loose tables. The root method is
then easy to call from the rest of Lua, and the internal compiler remains typed.

## Methods Are Ideally Pure

An ASDL semantic method should be a pure function whenever possible:

```lua
result = receiver:operation(input)
```

The receiver is an ASDL value. The input is an ASDL value. The result is an ASDL
value. The method should not mutate the receiver, mutate child nodes, write
hidden fields, update side tables, depend on ambient globals, or smuggle facts
through external caches.

If the method needs accumulated facts, pass a typed ASDL input product and return
a typed ASDL result product/union. If it derives a new world, return a projection
or facet. If it rejects, return a typed reject/diagnostic. Side effects belong at
explicit runtime or IO boundaries, not in ordinary compiler semantics.

## Constructors Compose ASDL

ASDL constructors in migrated compiler semantics must consume other ASDL values
and primitive scalar fields declared by the schema.

Do not pass ad hoc Lua records into ASDL constructors to smuggle untyped state
through a typed node:

```lua
-- Wrong: capability is an untyped Lua record.
Schedule.ScheduleSelectionPlanned(kind, {
  executable = true,
  kind = "scalar",
  rejects = {},
}, {})
```

Define the payload as ASDL and pass the ASDL value:

```lua
local capability = Schedule.ScheduleEmitterCapability(
  "scalar",
  true,
  "supported by current semantic emitters",
  {}
)
return Schedule.ScheduleSelectionPlanned(kind, capability, {})
```

If a constructor argument is conceptually a record, decision, capability, fact,
context, buffer, payload, or result, define that thing as an ASDL product or
union.

## Inputs And Results

Semantic method inputs and results must be explicit ASDL products or other named
ASDL values.

Do not pass:

- generic `ctx`, `env`, `state`, or option bags
- hidden Lua fields
- loose Lua tables
- ad hoc `{ ok = ... }`, `{ kind = ... }`, or `{ tag = ... }` result records
- multiple Lua return values for a semantic operation

If an operation can succeed, fail, reject, choose, classify, explain, or lower,
define an ASDL result product or union for that operation.

## No Any, No Table, No Map Type

Lalin ASDL must not provide `any`, `table`, `table_ty`, `map`,
userdata-like escape hatches, or equivalent catch-all field types for compiler
semantics.

If a value cannot be typed precisely, the schema is incomplete. Stop and model
the missing shape.

A keyed relation is not a `map`. Model it as a named ASDL product with fields
for the key and value, then carry `many [ThatEntry]`. The entry type is where
the relation gets a name, can grow methods, and can be reviewed as compiler
semantics instead of hiding as a side table.

## No Side Tables

Side tables are not semantic state. A Lua table keyed by ASDL nodes, symbols,
classes, tags, handles, or strings is forbidden when it carries compiler facts,
decisions, diagnostics, lowering results, type facts, layout facts, control-flow
facts, or backend facts.

Move those facts into ASDL:

- a product field when the fact is intrinsic to that phase value
- a projection when a phase derives a new shape
- a facet when several semantic planes align to a shared spine
- a result union when the fact is an operation outcome

## No Nil Passthrough

Do not let `nil` mean success, failure, absence, unknown, unsupported, default,
unchanged, no-op, or "keep going" by convention.

Use `optional [T]` only for a real nullable field whose absence is local and
obvious. If nil represents a semantic alternative or decision, define a union
leaf such as `Missing`, `Rejected`, `Unsupported`, `Unchanged`, or a more precise
domain name.

A method may return nil only when the parent ASDL method contract explicitly
says "operation not supported by this leaf" and the caller handles exactly that
contract.

## Smells

These are architecture bugs, not shortcuts:

- manual variant dispatch with `schema.classof`, `.kind`, `.tag`, strings, or
  `if/elseif` chains
- handler maps, visitor tables, rule tables, or selector tables
- side maps keyed by nodes, symbols, classes, handles, or strings
- stringly typed modes, actions, capabilities, or result kinds
- boolean protocol flags such as `ok`, `done`, `valid`, `has_x`, or `enabled`
  standing in for a result union
- optional soup: nullable fields, mode strings, and boolean switches in one
  product to represent alternatives
- large mutable contexts, even if wrapped as one ASDL product
- ASDL constructors accepting Lua records as payloads
- hidden fields on ASDL values
- compatibility shims that convert ASDL into old `{ kind = ... }` tables
- parent methods that inspect leaf shape and choose behavior
- catch-all variants such as `Other`, `Custom`, `Opaque`, `Unknown`, `Raw`, or
  `UserData` unless they are terminal diagnostic/rejection leaves with precise
  reasons
- parallel arrays that should be one list of ASDL products
- mutating ASDL nodes after construction instead of deriving a projection,
  facet, or result

## Source And Lower Phases

Source ASDL and lower ASDL have different jobs.

Source schemas model authored language facts: user-visible entities, domain
variants, containment, references, and typed source forms.

Lower schemas model consumed decisions: resolved names, type facts, layout,
control, schedules, machine plans, backend artifacts, diagnostics, and reject
reasons.

Do not bloat source nodes with later-phase facts. Create a lower projection,
spine, facet, or result type.

## Entity, Variant, Projection, Spine, Facet

Use this vocabulary when deciding what schema shape is missing:

- Entity: a stable user/compiler-visible thing with identity.
- Variant: a real domain alternative; model it as an ASDL union.
- Projection: a derived phase shape.
- Spine: a shared alignment/header product carrying identity, topology, order,
  addressability, or ranges for later branches.
- Facet: one semantic plane aligned to a spine, such as type, layout, control,
  lowering, memory, schedule, or backend facts.

## Terra Runtime Pattern

Lalin follows the useful Terra ASDL runtime mechanics:

- a context defines a closed schema vocabulary before implementation code runs
- products are checked records with named fields
- sums create a parent class plus concrete constructor classes
- nullary constructors are real singleton ASDL values
- parent membership is for type checking and shared defaults
- methods are installed on ASDL classes using normal Lua method syntax
- `unique` products and variants express schema-level identity and interning

Lalin's compiler rewrite doctrine is stricter than Terra's examples: do not use
`.kind` dispatch in migrated compiler semantics.

## Harness Pattern

The useful lesson from the Terra compiler-pattern harnesses is not a permission
to build more Lua plumbing. The useful lesson is that each ASDL semantic
boundary can be made visible, testable, and measurable as a local unit.

A semantic boundary is a method attached to an ASDL receiver:

```lua
checked = source:check(input)
lowered = checked:lower(input)
machine = lowered:define_machine(input)
```

The receiver is ASDL. The input should be ASDL when the operation needs more
than primitive scalars. The result is ASDL. That shape is the harness contract.

For each important boundary, a harness can provide:

- an implementation artifact for `Receiver:method`
- a focused test that constructs the receiver ASDL value and calls the method
- a bench when the method is on a hot path
- a profile script when allocation or dispatch shape matters
- a backend-specific artifact only when the backend is a real typed boundary

This helps because the agent does not need to rediscover where behavior lives.
The schema names the receiver, the method name names the semantic operation,
and the harness names the expected result. Missing work becomes a failing local
stub instead of a hidden convention in a giant pass.

Correct harness shape:

```lua
local source = Fixture.new_source_spec(T)
local checked = source:check(input)

assert(Checked.Spec:is(checked))
```

Wrong harness shape:

```lua
local checked = check_source({
  kind = "Spec",
  tokens = tokens,
  parser = parser,
})

assert(checked.kind == "CheckedSpec")
```

The wrong version teaches the compiler to accept ad hoc input tables and
stringly typed result records. That defeats the point of ASDL. A harness must
make the typed path easier than the untyped path.

Whole-pipeline harnesses are still useful, but they should prove composition of
typed phases:

```text
Source ASDL
  -> :check()
  -> Checked ASDL
  -> :lower()
  -> Lowered ASDL
  -> :define_machine()
  -> Machine ASDL/artifact
```

These tests should not become a substitute for local leaf-method tests. They
answer a different question: "Do the ASDL phase products connect?" Local tests
answer: "Does this receiver method implement this semantic boundary?"

Shared fixtures are useful when they build canonical ASDL towers that several
tests need. They are dangerous when they become generic mutable context bags.
A good fixture returns named ASDL roots. A bad fixture returns a loose table of
knobs, caches, handler maps, and optional fields that every test interprets by
convention.

Scaffolding can be useful for AI-assisted work because it can generate the
expected files for each declared boundary: implementation, test, bench, and
profile. The generated implementation must fail loudly until the method is
filled in. The generated test must construct ASDL inputs and assert ASDL
outputs. It must not scaffold `{ kind = ... }` compatibility tables.

The rule is simple: harnesses may make ASDL method work easier to find, run,
and measure. They must never introduce a second untyped protocol beside ASDL.

## Repair Procedure

When tempted to write untyped Lua plumbing:

1. Stop implementation work.
2. Name the missing semantic thing.
3. Add the ASDL product, union, leaf, field, projection, facet, or result.
4. Install behavior on the concrete leaf types that own it.
5. Return ASDL values from semantic methods.
6. Let tests fail loudly until call sites are moved to the typed shape.

The answer to unclear compiler semantics is more precise ASDL, not more Lua
dispatch.
