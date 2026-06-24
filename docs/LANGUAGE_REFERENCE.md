# Moonlift Family Language Reference

## Status

This document describes the complete `moonlift` LLB language family exposed by
`require("moonlift")`.

The family contains:

```text
moonlift.dsl
  Moonlift native-language heads, types, expressions, declarations, regions,
  modules, diagnostics, formatting, LSP indexing, and compilation hooks.

llpvm.dsl
  Low-level PVM language heads for typed bytecode languages, worlds, streams,
  records, machines, phases, tasks, and roots.

llisle.dsl
  Rule/rewrite/selection heads for lowering relations, product-shaped patterns,
  sum alternatives, strategy metadata, and process-shaped rule bodies.

llb
  The shared language-workbench substrate: symbols, fragments, origins,
  diagnostics, formatting, use sessions, language families, and processes.
```

The DSLs are ordinary Lua. Lua performs the mechanical parse, evaluates
host-time expressions, and hands real Lua values to LLB objects. Declaration,
control, LLPVM, and tooling heads are hosted by `lua/llb.lua`; each member
language normalizes those values by role and emits explicit typed values.
Moonlift core emits `MoonTree` and `MoonOpen` ASDL. LLPVM emits typed LLPVM
program specs, bytecode images, and task/run records.

There is no second source parser in the normal authoring path.
This is the recommended path for new generated/metaprogrammed Moonlift code.

```text
Lua syntax
  -> Lua values
  -> LLB family environment
  -> member-language role normalization
  -> Moonlift ASDL / LLPVM program specs / LLB process events
```

## Family Model

The authoring unit is the `moonlift` family, not a pile of manually stacked
global tables.

```lua
local moon = require("moonlift")
moon.family.use()
```

`moon.family.use()` installs the coherent authoring universe:

```text
Moonlift native language:
  ml
  moonlift

LLPVM:
  llpvm

MoonSchema:
  schema

Llisle:
  llisle

LLB:
  _
  spread
  fragments
  generic symbols
  origins
  diagnostics
  formatter/process/environment machinery
```

Unknown identifiers in a managed family environment become generic
`llb.Symbol` values. Member languages then consume symbols according to their
roles. This is why `a [ml.i32]`, `llpvm.world. raw [Expr]`,
`llpvm.record. one (...)`, and `ml.ret (a + b)` can coexist without a parser or
textual quoting.

### Namespace-first family surface

Family members are exposed as first-class LLB namespace values, not as bags of
bare globals. A namespace is still pleasant Lua field access, but it carries
semantic ownership metadata for docs, completion, diagnostics, formatting, and
zones.

```lua
ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
  ml.ret (a + b),
}

llpvm.task. compile {
  llpvm.input [ml.i32],
  llpvm.output [ml.i32],
}

llisle {
  relation. lower_expr {
    input { expr [MoonExpr], ctx [LowerCtx] },
    output { value [BackValue] },
  },
}

schema. MoonEditor {
  schema.product. DiagnosticFact {
    message [schema.str],
  },
}
```

`ml` is the preferred short Moonlift namespace. `moonlift` is kept as the long
alias and points at the same namespace value in family environments.

Namespaces can also be called to create family zones:

```lua
return {
  ml {
    ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
      ml.ret (a + b),
    },
  },

  llpvm {
    llpvm.task. compile {
      llpvm.input [ml.i32],
      llpvm.output [ml.i32],
    },
  },

  schema {
    schema. Demo {
      schema.product. Pair { left [MoonType.Type], right [MoonType.Type] },
    },
  },

  llisle {
    rule. lower_add_i32 {
      llisle.lower_expr { expr = add { lhs = P. lhs, rhs = P. rhs } [ml.i32] },
      run { ret { value = V. out } },
    },
  },
}
```

`schema. Name { ... }` uses the namespace default head and is equivalent to the
explicit `schema.module. Name { ... }`.

### Reduced family law

A good Moonlift family is reduced: one semantic primitive has one owner, and
other members reuse it instead of reimplementing it under a second surface.
Overlap is a smell unless the second form is only syntax sugar that lowers to
the owned primitive.

This is stricter than name collision handling. Collision policy decides who may
export a Lua name. Reduction decides who owns meaning.

Current semantic ownership:

```text
llb             owns authoring substrate, namespaces, fragments, origins,
                diagnostics, and family composition

moonschema.dsl  owns schema modules, product/sum schema, schema identity,
                and type-family semantics

moonlift.dsl    owns native programs, native control, native type values,
                resource discipline, and native compilation

llpvm.dsl       owns bytecode programs, bytecode streams, process/task specs,
                and PVM images

llisle.dsl      owns lowering rules, rewrite relations, and explicit
                sum-elimination semantics
```

Current semantic reuse:

```text
moonlift.dsl    uses LLB authoring/provenance/diagnostics and the shared
                type-family semantics

moonschema.dsl  uses LLB authoring/provenance/diagnostics

llpvm.dsl       uses LLB authoring/provenance/diagnostics, Moonlift native type
                values, and MoonSchema type-family semantics

llisle.dsl      uses LLB authoring/provenance/diagnostics, fragments,
                Moonlift native type values, and MoonSchema type-family
                semantics
```

This is why `schema.product` / `schema.sum` are the family source of product and
sum structure. LLPVM `lang` / `type` / `op` authoring belongs to bytecode/PVM
programs, but any general product/sum/type-family meaning should be reused from
MoonSchema, not reinvented inside LLPVM. Likewise, Moonlift native types are not
schema modules: they are native type values that can appear as operands inside
family DSLs.

The family exposes this as data:

```lua
local reduction = require("moonlift").family.reduction()
assert(reduction.owner["type-family"] == "moonschema.dsl")
assert(#reduction.smells == 0)
```

`reduction.smells` reports duplicate semantic owners as
`E_FAMILY_SEMANTIC_OVERLAP`. It also reports external semantic use as
`W_FAMILY_SEMANTIC_EXTERNAL` when a member claims to reuse a primitive that no
member in the family owns.

The family has one collision policy. Important choices:

```text
process  belongs to LLB coroutine/process streams
task     belongs to LLPVM typed process/task declarations
record   belongs to LLPVM stream records
value    is not a reserved family keyword; it is available as a user field/name
moonlift is the long alias for ml
schema   is the MoonSchema namespace, not LLPVM's internal schema directive
```

Prefer the family API for authored files and tools:

```lua
moon.family.use()
moon.family.use { scope = "env", target = env, global = false }
moon.family.load(src, name)
moon.family.loadfile(path)
```

Member-level `moon.use()` and `ll.use()` are lower-level tools for tests or
deliberately isolated member-language installs. Normal Moonlift-family source
should use `moon.family.use()`.

## Complete Family Keyword Inventory

This is the authoritative ownership table for the family authoring surface.
If a name appears in more than one member, the family policy decides the public
binding. If a name is not listed here, it is user space and unknown lookups
produce generic `llb.Symbol` values.

### Moonlift namespace exports

Moonlift native-language heads, type values, and helpers live under `ml` and
the long alias `moonlift`.

Compilation-unit and declaration heads:

```text
ml.unit
ml.struct
ml.union
ml.handle
ml.extern
ml.const
ml.static
ml.fn
ml.export_fn
ml.region
ml.expr_frag
```

Control and statement heads:

```text
ml.entry
ml.block
ml.jump
ml.emit
ml.ret
ml.yield
ml.when
ml.switch
ml.case
ml.default
ml.let
ml.var
ml.store
ml.set
ml.trap
ml.assume
ml.assert_
ml.requires
ml.afence
```

Type values and type constructors:

```text
ml.void ml.bool
ml.i8 ml.i16 ml.i32 ml.i64
ml.u8 ml.u16 ml.u32 ml.u64
ml.f32 ml.f64
ml.index ml.rawptr
ml.ptr ml.view ml.slice ml.array
ml.fnptr ml.closure
ml.lease ml.owned
ml.ro ml.wo ml.readonly ml.writeonly ml.noalias ml.noescape
ml.preserve ml.invalidate
```

Expression and fact helpers:

```text
ml.as
ml.bitcast
ml.addr
ml.deref
ml.load
ml.null
ml.is_null
ml.sizeof
ml.alignof
ml.select
ml.eq ml.ne
ml.And ml.Or ml.Not
ml.aload
ml.astore
ml.acas
ml.armw
ml.ctor
ml.bounds
ml.window_bounds
ml.disjoint
ml.same_len
```

Fragment helpers:

```text
ml.product
ml.stmts
ml.decls
ml._
ml.spread
```

Name helpers:

```text
ml.N
```

### LLPVM namespace exports

Whole-program and language definition heads:

```text
llpvm.pvm
llpvm.language
llpvm.lang
llpvm.type
llpvm.op
llpvm.world
llpvm.stream
llpvm.record
llpvm.machine
llpvm.phase
llpvm.task
llpvm.root
```

Task and phase directive heads:

```text
llpvm.event
llpvm.input
llpvm.output
llpvm.from
llpvm.to
llpvm.entry
llpvm.cache
```

LLPVM helpers:

```text
llpvm._
llpvm.spread
```

### Schema namespace exports

MoonSchema defines product/sum/alias type families and the ASDL-shaped schema
model used by the compiler itself.

```text
schema. Name { ... }          module declaration through the namespace default head
schema.module. Name { ... }   explicit module declaration
schema.product. Name { ... }  product type
schema.sum. Name { ... }      sum type
schema.alias. Name [Type]     type alias
schema.field. name [Type]     escaped field declaration
```

Schema helpers:

```text
schema.str
schema.bool
schema.number
schema.any
schema.table_ty
schema.function_ty
schema.nil_ty
schema.interned
schema.unique
schema.variant_unique
schema.many
schema.optional
schema.ref
schema.id
schema.map
```

### LLB family helpers

LLB is the substrate, so most LLB APIs are module functions rather than globals.
The family-visible helpers are:

```text
_
spread
process
origin helpers through explicit llb require
diagnostic helpers through explicit llb require
formatting through member/family format APIs
```

Use explicit `local llb = require("llb")` for grammar authoring,
meta-protocol work, diagnostics, process definitions, and language-family
construction.

### Reserved and intentionally unreserved names

Reserved by family policy:

```text
pvm lang language type op world stream record machine phase task event
input output root ml moonlift llpvm schema
```

Shared by family policy:

```text
entry
_
spread
```

Intentionally not reserved:

```text
value
process as an LLPVM head
```

`value` is ordinary user space. `process` is the LLB coroutine/process API, not
an LLPVM declaration head.

## Reference Notation

Reference entries use this notation:

```text
head. name      dot-name slot through index:name
head[name]      computed name/value slot through index:value
head { ... }    body/product/protocol slot through call:table
head (value)    expression/value slot through call:value
head [Type]     type/value slot through index:type or index:value
```

Head tables below are written relative to their owning namespace. In family
source, prefix Moonlift heads and type values with `ml.`, LLPVM heads with
`llpvm.`, and schema heads/helpers with `schema.`. In member-only loaders such
as `require("moonlift").use()` or `require("llpvm").use()`, those same heads may
be installed bare for focused tests or isolated single-language files.

All names in managed environments are generic `llb.Symbol` values until a role
normalizes them.

## Moonlift Core Head Reference

### Units and declarations

| Head | Shape | Meaning |
|---|---|---|
| `unit` | `unit. Name { decls... }` | Optional compilation-unit/artifact wrapper. Body is an ordered declaration list. |
| `struct` | `struct. Name { fields... }` | Product data type declaration. |
| `union` | `union. Name { variants... }` | Sum data type declaration. |
| `handle` | `handle. Name { facts... }` | Durable external/resource identity type. |
| `extern` | `extern. name { params... } [result] { attrs... }` | Foreign function declaration. Result is optional for void. |
| `const` | `const. name [Type] { value }` | Typed constant declaration. |
| `static` | `static. name [Type] { value }` | Typed static declaration. |
| `fn` | `fn. name { params... } [result] { body... }` | Internal function. Result is optional for void. |
| `export_fn` | `export_fn. name { params... } [result] { body... }` | Exported function. |
| `region` | `region. name { params... } { exits... } { blocks... }` | Typed control fragment with named continuation protocol. |
| `expr_frag` | `expr_frag. name { params... } [result] { expr }` | Reusable expression fragment declaration. |

Declaration names are dot-headed:

```lua
fn. add
struct. Point
region. scan
```

Computed declaration names use brackets:

```lua
fn ["add_" .. suffix]
struct [N["Vec" .. n]]
```

The canonical style is dot names for handwritten declarations.

### Products, protocols, and fragments

| Form | Shape | Meaning |
|---|---|---|
| typed field | `name [Type]` | Product item with name and type. |
| initialized field | `name [Type](init)` | Product item with initial value, mainly block params. |
| no-payload variant | `name` | Union/protocol alternative with no payload. |
| payload variant | `name { fields... }` | Union/protocol alternative with payload product. |
| product fragment | `product { fields... }` | Reusable field/product fragment. |
| statement fragment | `stmts { statements... }` | Reusable statement fragment. |
| declaration fragment | `decls { decls... }` | Reusable declaration fragment. |
| splice | `_(fragment)` | Preferred structural splice marker. |
| explicit splice | `spread(fragment)` | Explicit alias for `_`. |

Fragment role must match the receiving context.

### Statements and control

| Head | Shape | Meaning |
|---|---|---|
| `ret` | `ret (expr)` / `ret ()` | Return from function. |
| `yield` | `yield (expr)` / `yield ()` | Yield from region/control context. |
| `when` | `when (cond) { body... }` | Conditional statement. |
| `entry` | `entry. name { params... } { body... }` | Required region/function CFG entry block. |
| `block` | `block. name { params... } { body... }` | Named CFG block. |
| `jump` | `jump. target { fills... }` | Jump to block/continuation with named payload fills. |
| `emit` | `emit. region { args... } { fills... }` | Inline/splice a region and map exits. |
| `switch` | `switch (expr) { arms... }` | Multi-way branch. Requires default. |
| `case` | `case (literal) { body... }` / `case. tag { binds... } { body... }` | Switch arm. |
| `default` | `default { body... }` | Required fallback switch arm. |
| `let` | `let. name [Type] { init }` | Immutable local binding. |
| `var` | `var. name [Type] { init }` | Mutable local cell. |
| `store` | `store (place, value)` | Store to place. |
| `set` | `set (place, value)` | Alias-style assignment/store form. |
| `trap` | `trap ()` | Trap/unreachable. |
| `assume` | `assume (cond)` | Optimizer assumption. |
| `assert_` | `assert_ (cond)` | Checked assertion. |
| `requires` | `requires { contracts... }` | Function contract block, extracted during lowering. |

No `for`, `while`, `break`, or `continue` exist in Moonlift core. Control is
jump-first. Every block path must terminate with `jump`, `yield`, `ret`, or
`trap`.

### Type reference

| Form | Meaning |
|---|---|
| `void` | No result. |
| `bool` | Boolean scalar. |
| `i8 i16 i32 i64` | Signed integer scalars. |
| `u8 u16 u32 u64` | Unsigned integer scalars. |
| `f32 f64` | Floating scalars. |
| `index` | Target index-sized integer. |
| `rawptr` | Opaque raw pointer. |
| `ptr [T]` | Pointer to `T`. |
| `view [T]` | View over `T`. |
| `slice [T]` | Slice of `T`. |
| `array [T][N]` | Fixed-size array. |
| `fnptr [{ params... }] [result]` | Function pointer type. |
| `closure [{ params... }] [result]` | Closure type. |
| `lease [T]` / `lease(origin, T)` | Borrow/lease wrapper. |
| `owned [Handle]` | Owned resource authority for a handle type. |
| `ro [T]`, `readonly [T]` | Read-only access wrapper. |
| `wo [T]`, `writeonly [T]` | Write-only access wrapper. |
| `noalias [T]` | No-alias access wrapper. |
| `noescape [T]` | No-escape access wrapper. |
| `preserve [T]` | Preserve access wrapper. |
| `invalidate [T]` | Invalidate access wrapper. |

### Expression reference

| Form | Meaning |
|---|---|
| literals | Numbers, booleans, nil, strings, and aggregate tables. |
| `name` | Runtime/reference symbol normalized by semantic phases. |
| `a + b`, `a - b`, `a * b`, `a / b`, `a % b`, `-a` | Arithmetic expression nodes. |
| `x :eq (y)`, `x :ne (y)`, `x :lt (y)`, `x :le (y)`, `x :gt (y)`, `x :ge (y)` | Comparison methods. |
| `eq(a, b)`, `ne(a, b)` | Comparison constructors. |
| `And(a, b)`, `Or(a, b)`, `Not(a)` | Boolean constructors. |
| `xs[i]` | Index expression/place. |
| `point.x` | Field expression/place. |
| `as [T] (x)` | Typed conversion. |
| `bitcast [T] (x)` | Bit reinterpretation. |
| `addr(place)` | Address of place. |
| `deref(ptr)` | Dereference pointer. |
| `load(ptr)` | Load through pointer. |
| `null [T]` | Null pointer of type `T`. |
| `is_null(p)` | Null check. |
| `sizeof [T]` | Size of type. |
| `alignof [T]` | Alignment of type. |
| `select(cond, a, b)` | Select expression. |
| `ctor("Type", "Variant", { payload... })` | Variant constructor expression. |
| `aload(T, p)` | Atomic load. |
| `astore(T, p, v)` | Atomic store statement/expression helper. |
| `acas(T, p, expected, replacement)` | Atomic compare-and-swap. |
| `armw(op, T, p, v)` | Atomic read-modify-write. |

Lua `and`, `or`, `not`, `<`, `<=`, `>`, `>=`, `==`, and `~=` cannot be
overloaded into expression trees. Use the listed constructors/methods.

## LLPVM Head Reference

LLPVM is the typed bytecode/program side of the family.

| Head | Shape | Meaning |
|---|---|---|
| `pvm` | `pvm. Name { decls... }` | Whole LLPVM program. |
| `language` | `language. Name { decls... }` | Reusable generated LLPVM machine-language object. |
| `lang` | `lang. Name { types... }` | Language/schema declaration inside a program. |
| `type` | `type. Name { ops... }` | Operation sum/type family. |
| `op` | `op. Name { fields... }` | Operation constructor payload shape. |
| `world` | `world. name [Lang]` | Named world backed by a language/schema. |
| `stream` | `stream. name [world] { records... }` | Named stream of bytecode records. |
| `record` | `record. name (OpValue)` | Named stream item. |
| `machine` | `machine. name { directives... }` | Execution machine declaration. |
| `phase` | `phase. name { directives... }` | Compiler/runtime phase declaration. |
| `task` | `task. name { directives/events... }` | Typed process/task declaration. |
| `event` | `event. name [Type]` | Task event payload declaration. |
| `input` | `input [Type]` | Task input type. |
| `output` | `output [Type]` | Task output type. |
| `from` | `from. world` | Phase input world. |
| `to` | `to. world` | Phase output world. |
| `entry` | `entry. symbol` | Machine/phase entry symbol. |
| `cache` | `cache. mode` | Cache policy directive. |
| `root` | `root { roots... }` | Program root stream/record/phase references. |

LLPVM records use generated language constructors:

```lua
record. one (Node.Int { value = 1 })
record. add (Node.Add { left = one, right = two })
```

Typed task declarations are structural:

```lua
task. compile {
  input [i32],
  output [i32],
  event. progress [i32],
  event. diagnostic [i32],
}
```

Task declarations and task runs lower to `LlPvm.TaskSpec` and
`LlPvm.TaskRun`. Runtime streams still use LLB `process`.

## LLB Substrate Reference

LLB is documented in depth in `docs/LLB_GUIDE.md` and
`docs/LLB_ATOM_PROTOCOL_MODEL.md`. This section lists the family-relevant API
surface.

### Family and environment API

| API | Meaning |
|---|---|
| `llb.family. name { members... }` | Define a language family. |
| `family.use { opts... }` | Install family exports into an environment. |
| `family.env { opts... }` | Create isolated family environment. |
| `family.load(src, name)` | Load source through family environment. |
| `family.loadfile(path)` | Load file through family environment. |
| `family.reduction()` | Inspect semantic owners, semantic reuse, and reduction smells. |
| `family.prefer { name = member }` | Return family with collision preferences. |
| `family.only { capabilities... }` | Project family by capabilities. |
| `family.subtract "member"` | Remove a member. |
| `family .. other` / `family + other` | Checked family composition. |
| `family - "member"` | Family subtraction. |

Family methods are dot-only. Do not use colon syntax.

### Symbol, origin, and diagnostic API

| API | Meaning |
|---|---|
| `llb.symbol(name)` | Generic authoring symbol. |
| `llb.name(name)` | Generic name value. |
| `llb.N.name`, `llb.N["name"]` | Name helper. |
| `llb.here(kind)` | Capture current origin. |
| `llb.at(origin, value)` | Attach/thread origin. |
| `llb.origin_of(value)` | Inspect origin. |
| `llb.provenance(value)` | Inspect provenance chain. |
| `llb.diagnostic { ... }` | Build structured diagnostic. |
| `llb.diagnostics()` | Build diagnostic bag. |
| `llb.fail(message, spec)` | Raise structured grammar failure. |

### Fragment and formatting API

| API | Meaning |
|---|---|
| `llb.fragment(role, items, origin, opts)` | Build role-tagged fragment. |
| `llb._(value)` | Preferred structural splice marker. |
| `llb.spread(value)` | Explicit splice alias. |
| `fragment_a .. fragment_b` | Product/list append. |
| `fragment_a + fragment_b` | Sum/protocol choice. |
| `sum_fragment * product_fragment` | Decorate alternatives. |
| `llb.format(value, opts)` | Semantic formatting. |
| `llb.render(doc, opts)` | Render LLB doc algebra. |

### Process API

| API | Meaning |
|---|---|
| `llb.process. name (function(ctx, ...) ... end)` | Define coroutine-backed event stream. |
| `process:start(...)` | Start resumable process handle. |
| `process(...)` | Iterate process events directly. |
| `handle:events()` | Iterate emitted events. |
| `handle:result()` | Final process result. |
| `ctx. event_kind { payload... }` | Emit process event through dot head. |
| `ctx:event(kind, payload)` | Emit process event dynamically. |
| `ctx. error { ... }` | Emit diagnostic/error event. |
| `ctx:consume(n)` | Account work budget. |
| `ctx:cancelled()` | Check cancellation. |

### Grammar/meta API

| API | Meaning |
|---|---|
| `llb.define "Name" { ... }` | Define an LLB language. |
| `llb.grammar.role. name { ... }` | Define a role. |
| `llb.grammar.head. name { ... }` | Define a staged head. |
| `llb.grammar.slot. name [role] { ... }` | Define a slot. |
| `llb.grammar.trait. name { ... }` | Define reusable grammar behavior. |
| `llb.channel.*` | Slot channel constants. |
| `llb.protocol(name, spec)` | Define public protocol object. |
| `llb.describe(value)` | Inspect a language value/object. |
| `llb.describe_head(lang, name)` | Inspect head definition. |
| `llb.describe_role(lang, name)` | Inspect role definition. |

## Removed and Non-Syntax Forms

These forms are not part of the language family:

```text
.mld.lua source files
text parser/tokenizer authoring path
LLPVM process. name declarations
LLPVM value. name records
string-name canonical declarations such as fn("add", ...)
mutation-style ll.vm authoring
implicit hidden language dependency installs
angle-bracket type arguments
Moonlift source generics
for / while / break / continue in Moonlift control
fallthrough switch cases
```

Lua strings remain ordinary Lua values where a head explicitly accepts a string
or literal expressions. The canonical explicit artifact root is dot-headed:
`unit. Demo { ... }`.

For declaration/control heads, canonical formatting puts the dot on the keyword
side (`fn. add`, `region. scan`, etc.)
with a space before the name target:

```text
fn. add
region. scan
jump. done
emit. scan
```

For single-expression/condition keyword-style forms, use the canonical DSL forms
below to keep intent obvious:

```text
ret (expr)      -- scalar / expression form
yield (expr)    -- scalar / expression form
when (cond) { ... }
```

`ret` and `yield` scalar expressions are written with `()` unless the argument is
a Lua syntax form that is already naturally paren-less (string/aggregate literals).
`when` keeps the paren form for consistency.

Lua tokenization does not treat this as semantic syntax, but the visual rule keeps
declaration/control heads and statement forms distinct from ordinary function calls.

Canonical argument rule:

- `ret`/`yield`: parenthesized form for values generally, except string and aggregate literals that are naturally paren-less in Lua.
- `when`: keep condition in `()`.
- `jump`/`emit`: remain `(...)` (control invocation syntax still needs parens).

This is the central rule:

```text
[] means Lua already evaluated this expression.
```

So:

```lua
x [T]
ptr [T]
fn [name]
as [T](x)
```

carry actual Lua values, not textual splice holes.

## Spacing Convention

A space is placed between every DSL keyword and what follows it, and between
every name and its type bracket. Lua table-access syntax (`[T]`) includes the
space for readability even though Lua does not require it:

```text
name [Type]           -- parameter/field/entry typing
keyword (value)       -- statement or expression keyword
keyword .name         -- declared name, block label, region target
keyword { body }      -- body, continuation, switch arm
```

Concrete rules:

| Form | Do | Don't |
|------|----|----- |
| typed name | `x [i32]` | `x[i32]` |
| type constructor | `ptr [u8]` | `ptr[u8]` |
| cast | `as [i32] (x)` | `as[i32](x)` |
| comparison method | `i :ge (n)` | `i:ge(n)` |
| ret / yield | `ret (expr)` | `ret(expr)` |
| when | `when (cond) { ... }` | `when(cond){...}` |
| let / var | `let. x [i32] { 0 }` | `let.x[i32]{0}` |
| store / set | `store (place, value)` | `store(place,value)` |
| jump | `jump. loop { i = i + 1 }` | `jump.loop{i=i+1}` |
| emit | `emit. scan { args } { fills }` | `emit.scan{args}{fills}` |
| switch | `switch (value) { ... }` | `switch(value){...}` |
| trap / assert_ / assume | `trap ()` | `trap()` |
| afence | `afence ()` | `afence()` |
| requires | `requires { ... }` | `requires{...}` |

### Lua no-parens rule

Lua omits parentheses for single literal arguments. The DSL follows this:
no `()` for a single literal, `()` required for expressions and multi-arity.

```lua
ret 42               -- numeric literal, no parens
ret "done"           -- string literal, no parens
ret { 1, 2, 3 }      -- table literal, no parens
ret true             -- boolean literal, no parens
ret (a + b)           -- expression, parens required
ret ()                -- void return, parens required

assert_ (cond)         -- expression, parens required
store (place, value)   -- multi-arity, parens required
aload (i32, p)         -- multi-arity
```

This convention makes DSL source grep-shaped: `rg 'ret \('` finds returns,
`rg 'jump \.'` finds jumps, `rg 'x \[i32\]'` finds typed names.

## Design Rule

Moonlift structure uses `{}`.

Lua computation and language leaves use `()` when ordinary Lua syntax requires it.

Canonical examples:

```lua
fn. add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
  }
```

```lua
region. scan
  { p [ptr [u8]], n [index], target [i32] }
  {
    hit  { pos [index] },
    miss,
  }
  {
    entry. loop { i [index](0) } {
      when (i :ge (n)) {
        jump. miss { pos = i },
      },

      jump. loop {
        i = i + 1,
      },
    },
  }
```

## Why This Works

Lua table syntax already models the shapes Moonlift cares about:

```text
array table   -> ordered product/body/protocol entries
record table  -> unordered named maps/fills/options
mixed table   -> ordered children plus attributes
[]            -> evaluated host value in a type/name/static slot
()            -> host-time call or leaf expression construction
```

Moonlift does not need a new parser to understand products, protocols, bodies,
or continuation maps. The shape is already present in the Lua value.

## Loading

### Quick: `moon.family.use()` for plain `.lua` files

The simplest way to author Moonlift-family code is to call
`require("moonlift").family.use()` at the top of any `.lua` file. This injects
the family namespace values as Lua globals:

```lua
-- my_module.lua
local moon = require("moonlift")
moon.family.use()

return {
  ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
    ml.ret (a + b),
  },
}
```

For headers split across files, call `moon.family.use()` at the top of each
`.lua` file:

```lua
-- math_header.lua
require("moonlift").family.use()
return { ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] }

-- math_impl.lua
require("moonlift").family.use()
local header = require("math_header")
return { header[1] { ml.ret (a + b) } }
```

### Family loading — inline, isolated env

For programmatic use, `moon.family.load()` creates an isolated environment
without touching `_G`:

```lua
local moon = require("moonlift")

-- One-shot: compile and execute
local decls = moon.family.load([[return { ... }]], "demo.lua")

-- From a file
local chunk = moon.family.loadfile("demo.lua")
local decls = chunk()

-- Full pipeline
local unit_value = moon.unit("Demo", decls)
unit_value:ast()
unit_value:typecheck()
unit_value:lower()
unit_value:compile()
unit_value:emit_c_artifact()
```

`require("moonlift.dsl").load()` remains the Moonlift-core member loader. Use
the family loader when code may use LLPVM heads, shared LLB helpers, or family
collision policy.

### Package searcher integration

Once loaded, the Moonlift core DSL auto-installs a Lua `package.searchers` entry so
plain `require("foo")` automatically finds `foo.lua` files:

```lua
local dsl = require("moonlift.dsl")
dsl.loadstring([[...]], "main")  -- triggers searcher install

-- Now any .lua file can require other .lua files:
local header = require("math_header")  -- finds math_header.lua
```

This enables header/impl split across files with zero ceremony:

```lua
-- math_header.lua
return {
  fn. add { a [i32], b [i32] } [i32],
  fn. sub { a [i32], b [i32] } [i32],
}

-- math_impl.lua
local header = require("math_header")
return {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
```

Strict global mode:

```lua
dsl.loadstring(src, "demo", { strict = true })
```

In strict mode, assignment to a previously unknown global is rejected.

## Lua Modules and Moonlift Units

```lua
return {
  declarations...
}
```

The canonical Lua file returns a plain Lua table. That table is the Lua module
value, and its array part is the ordered Moonlift declaration list.

Supported declaration entries:

```text
struct
union
handle
extern
const
static
fn
export_fn
region
expr_frag
_(decls_fragment)
```

In this Lua-owned DSL, source composition is done by Lua `require` and value
splicing (`[]` / `_(...)`), not by a DSL `import` declaration.

Moonlift creates a compilation unit when you explicitly project the Lua value:

```lua
local decls = require("math_impl")
local native = require("moonlift").compile("Math", decls)
```

When the source file itself wants to carry artifact metadata, use `unit. Name`:

```lua
return unit. Math {
  fn. add { a [i32], b [i32] } [i32] { ret (a + b) },
}
```

## LLPVM Family Surface

LLPVM is part of the Moonlift family because the bootstrap/compiler-runtime
side needs a typed bytecode language with the same no-parser authoring model.
The complete LLPVM reference is `docs/LLPVM_GUIDE.md`; this section defines the
family-level shape.

```lua
llpvm.pvm. Expr {
  llpvm.lang. Expr {
    llpvm.type. Node {
      llpvm.op. Int { value [ml.i64] },
      llpvm.op. Add { left [Node], right [Node] },
    },
  },

  llpvm.world. raw [Expr],

  llpvm.stream. raw_items [raw] {
    llpvm.record. one (Node.Int { value = 1 }),
    llpvm.record. two (Node.Int { value = 2 }),
    llpvm.record. add_node (Node.Add { left = one, right = two }),
  },

  llpvm.task. compile {
    llpvm.input [ml.i32],
    llpvm.output [ml.i32],
    llpvm.event. progress [ml.i32],
  },

  llpvm.root {
    raw_items,
    add_node,
  },
}
```

## Llisle Family Surface

Llisle is the family rule language for compiler lowering, rewriting, and
backend selection. It does not introduce a parser or a callback registry.
It maps directly onto existing family algebra:

```text
relation       typed product-to-product question
project        classification/projection relation into family facts
predicate      declared guard semantic primitive
constructor    declared output/effect semantic primitive
rule           sum arm that may satisfy a relation
relation call  product-shaped pattern
when           product/sum of guards
choose         local sum elimination
alt            local sum arm
run            process-shaped construction body
emit           process effect
ret            output product
```

Canonical Llisle island shape:

```lua
llisle {
  project. classify_expr {
    input { expr [MoonExpr] },
    output { class [ExprClassFact] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  relation. lower_expr {
    input { expr [MoonExpr], ctx [LowerCtx] },
    output { value [BackValue] },
    effects { cmd [BackCmd], diagnostic [Diagnostic] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  predicate. has_type [has_type_impl] {
    input { value [Any], ty [Any] },
    pure,
  },

  predicate. fits_imm32 [fits_imm32_impl] {
    input { value [Any] },
    pure,
  },

  constructor. add_i32_imm [build_add_i32_imm],

  constructor. add_i32 [build_add_i32],

  rule. add_i32 {
    llisle.lower_expr {
      expr = add { lhs = P. lhs, rhs = P. rhs } [ml.i32],
      ctx = P. ctx,
    },

    when {
      (P. lhs :has_type (ml.i32)) * (P. rhs :has_type (ml.i32)),
    },

    choose {
      alt. imm {
        when { (P. rhs :fits_imm32 ()) + (P. rhs :is_const ()) },
        cost (1),
        run {
          emit. cmd {
            add_i32_imm { dst = V. out, lhs = P. lhs, imm = P. rhs },
          },
          ret { value = V. out },
        },
      },

      alt. reg {
        cost (2),
        run {
          emit. cmd {
            add_i32 { dst = V. out, lhs = P. lhs, rhs = P. rhs },
          },
          ret { value = V. out },
        },
      },
    },
  },
}
```

Inside a dedicated Llisle island, use the language through LLB and write the
heads bare. This is the same managed-environment pattern used by the other
family DSLs:

```lua
local Llisle = require("llisle")
local env = require("moonlift").family.env { scope = "env", base = _G }
Llisle.use { scope = "env", target = env, base = env, global = false }

local function has_type(value, ty)
  return value.ty == ty
end

local function build_add_i32(fields)
  return { op = "add_i32", dst = fields.dst, lhs = fields.lhs, rhs = fields.rhs }
end

local function rules()
  return llisle {
    relation. lower_expr {
      input { expr [MoonExpr], ctx [LowerCtx] },
      output { value [BackValue] },
    },

    predicate. has_type [has_type] {
      input { value [Any], ty [Any] },
      pure,
    },

    constructor. add_i32 [build_add_i32],

    rule. add_i32 {
      llisle.lower_expr {
        expr = add { lhs = P. lhs, rhs = P. rhs } [ml.i32],
        ctx = P. ctx,
      },
      when { (P. lhs :has_type (ml.i32)) * (P. rhs :has_type (ml.i32)) },
      run { ret { value = V. out } },
    },
  }
end
```

The outer `llisle { ... }` is the zone/container. Relation calls such as
`llisle.lower_expr { ... }` remain namespace calls because relations are dynamic
entries under the Llisle namespace. Declarations, binders, guards, alternatives,
process heads, and fragments are bare inside a Llisle island.

Rules compose as normal LLB fragments:

```lua
local scalar_rules = rules {
  rule. lower_const_i32 { ... },
}

local arith_rules = rules {
  rule. lower_add_i32 { ... },
}

return llisle {
  relation. lower_expr { ... },
  _(scalar_rules .. arith_rules),
}
```

Executable use:

```lua
local engine = llisle.compile(rules, {
  fresh = function(name, id)
    return { kind = "tmp", name = name, id = id }
  end,
})

local result = assert(engine:run("lower_expr", {
  expr = { kind = "add", ty = ml.i32, lhs = lhs, rhs = rhs },
  ctx = ctx,
}))
```

The engine is deliberately Lua-integrated, but not registry-defined. Llisle owns relation structure, projection structure, predicate declarations, constructor declarations, pattern binding, guard order, local `choose` alternatives, costs, effects, and returns. Lua implementations are explicit values spliced through `[]` on `predicate.` and `constructor.` declarations. There is no `host.` directive, no `predicates` compile registry, and no `builders` compile registry.

`P.*` binders capture matched inputs, `V.*` binders allocate stable fresh values
inside one rule execution, and `T.*` is reserved for type-level binders. A
successful run returns `{ output, effects, rule, alt, cost, bindings }`; failure
returns `nil, diagnostic_like_table`.

Binder paths are symbolic family paths, not private string slots. A rule may bind
the whole subject as `P.expr` and then use `P.expr.lhs.ty` in guards or emitted
payloads. Field lookup accepts ordinary Lua string keys, `llb.Symbol`/`llb.Name`
keys, and shared symbols supplied to `llisle.compile { symbols = ... }`. This is
what lets Llisle rules operate over Moonlift, MoonSchema, kernel, and backend
facts without translating those facts into a separate record universe.

`bind` may appear before `when` inside a rule or alternative. This expresses
recursive lowering directly:

```lua
bind. inner {
  llisle.classify_expr { expr = P. expr.value },
}
when { V. inner.class.kind :eq (load) }
```

The LuaJIT C stencil backend uses this shape end-to-end for stencil lowering.
ASDL kernel/value nodes are adapted into shared facts, Llisle recursively
classifies expressions and stencil scalar type families, then Llisle owns two
levels of decision. `plan_store_stencil` and `plan_reduce_stencil` gate
readiness: planned kernel, counted positive loop, return shape, single-store or
reduction result, enriched class, and concrete selector availability.
`select_store_stencil` and `select_reduce_stencil` then choose the concrete
stencil vocabulary, op, provider `info`, and ordered machine argument list.
Every concrete stencil selection constructor declares its payload contract in
Llisle: `input { info [...], args [StencilArgList] }` or
`input { op [Any], info [...], args [StencilArgList] }`, and
`output { selection [...] }`. Plan constructors similarly expose
`output { plan [...] }`. The vocabulary is therefore inspectable by LLB tooling
instead of being only a Lua builder convention.
Stencil type admissibility is part of the rule layer: scalar element/result
types are classified as integer, float, index, or bool8; same-type constraints,
index-array constraints, unary and binary op/type support, cast legality, and
reduction support are checked before artifact construction. The LuaJIT lowering
layer consumes the selected plan to build the final machine and artifact call;
it does not own the stencil decision matrix.

The next LuaJIT lowering layer is also Llisle-owned. `luajit_lower` adapts
kernel plans, flow facts, provider availability, return-shape checks, counted
loop facts, and scheduled stencil readiness into a
`LuaJITKernelLoweringCandidate`. Llisle then selects the concrete lowering
strategy by cost across selected stencil reductions, skeletons, and stores. Lua
builds only the selected machine; it no longer owns a procedural trial ladder
or a separate vector-reduction path. Vectorization is carried by the selected
`MoonStencil.StencilInstance.schedule` and realized by the C stencil compiler
policy.

The stencil layer is performance-gated as a vocabulary, not as isolated
examples. Run `luajit benchmarks/bench_luajit_stencil_matrix.lua full` to
measure every C stencil shape against a direct GCC loop baseline.
The next layer is gated by
`luajit benchmarks/bench_luajit_lower_stencil_matrix.lua full`, which asserts
that MoonCode loops select the expected stencil vocabulary and compares the
lowered LuaJIT wrapper with the raw artifact call.
Array skeletons that are not plain stores or reductions are represented in the
kernel schema before lowering: `KernelEffectScan`, `KernelEffectPartition`,
`KernelEffectCopy`, and `KernelResultFind`. LuaJIT consumes those semantic
facts through Llisle selectors for `scan_array`, `partition_array`,
overlap-aware `copy_array`, and `find_array`.
The ordinary counted-loop planner now infers prefix scans and no-overlap array
copies directly as `KernelEffectScan` and `KernelEffectCopy`. When copy overlap
is unproven, it selects `StencilCopyMemMove` instead of rejecting the loop. The
planner also recognizes early-exit primary-index searches as `KernelResultFind`.
Stable partition is function-level because it is a two-pass fragment, not a
single-loop store; `code_kernel_plan` emits `KernelEffectPartition` for that
shape. The lower stencil matrix covers all 18 vocabulary cells.

Kernel planning uses the same split. `code_kernel_plan` assembles graph, flow,
value, memory, and effect facts into a `KernelLoopPlanCandidate`; Llisle selects
the semantic outcome. The rule layer owns no-plan rejection priority and kernel
result priority: closed forms win over reductions, reductions win over skeleton
results, skeleton results win over original control, and closed-form plans carry
the explicit unknown-trip proof bit when Flow cannot provide an exact trip
count. Lua then constructs the selected MoonKernel ASDL value.

Schedule planning is Llisle-owned at the strategy boundary. `code_schedule_plan`
builds `KernelScheduleCandidate` values from planned kernels, target vector
facts, and emitter capability checks. Llisle selects executable vectors first,
falls back to scalar or closed-form schedules when vector support rejects, keeps
those vector rejects as rejected alternatives, and emits `ScheduleNoPlan` only
when the executable fallback also rejects.

LLPVM heads:

```text
pvm. Name { ... }          whole LLPVM program
lang. Name { ... }         typed bytecode language/schema
language. Name { ... }     reusable generated LLPVM language object
type. Name { ... }         sum/type family in a bytecode language
op. Name { fields }        operation constructor payload shape
world. name [Lang]         named operation world
stream. name [world] { ... } bytecode record stream
record. name (OpValue)     named stream record
machine. name { ... }      execution machine declaration
phase. name { ... }        phase declaration
task. name { ... }         typed process/task declaration
event. name [Type]         task event payload
input [Type]               task input type or phase input directive
output [Type]              task output type or phase output directive
from. world                phase input world
to. world                  phase output world
entry. symbol              phase entry symbol
cache. mode                phase cache policy
root { ... }               program roots
```

The hard naming rule is:

```text
record  is the LLPVM stream item head
task    is the LLPVM typed process declaration head
process is the LLB coroutine/process helper
value   is ordinary user space
```

Use `task. compile { ... }` when progress/event structure is part of the typed
compiler/runtime model. Use `llb.process. name(function(ctx, ...) ... end)` for
the coroutine that actually streams events.

Moonlift phase execution reports expose `LlPvm.TaskRun` records, so compiler
progress, validation, source analysis, LSP indexing, and debugger stepping can
share one typed run/event model.

## LLB Family Surface

LLB is not a separate syntax layer. It is the substrate that makes the family
work.

Family-visible LLB concepts:

```text
generic symbols       unknown identifiers in managed environments
fragments             role-shaped reusable lists/products/sums
_ / spread            structural splice markers
origins/provenance    diagnostic blame across helpers/factories
diagnostics           structured failures and notes
formatting            semantic formatting of evaluated DSL values
processes             coroutine-backed event streams
families              dependency/collision/environment policy
```

Preferred family metaprogramming is fragment-shaped:

```lua
local xy = product {
  x [f32],
  y [f32],
}

struct. Point {
  _(xy),
  z [f32],
}
```

Use functions when computing one value. Use fragments when composing
role-shaped values. Use processes when work should stream events, diagnostics,
progress, or debugger steps.

### Header / implementation split

The DSL's `fn` and `region` declaration chains are **curried**: supplying
params and result does not create the final declaration. It returns a
**callable LLB stage** waiting for the body. This is the header.

```lua
fn. add { a [i32], b [i32] } [i32]
```

The line above does not produce a final declaration. It produces a callable Lua
stage table.
Call it with a body table to produce the full declaration:

```lua
fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}
```

This means headers and implementations can live in separate files:

```lua
-- math_header.lua
return {
  fn. add { a [i32], b [i32] } [i32],
  fn. sub { a [i32], b [i32] } [i32],
}
```

```lua
-- math_impl.lua
local header = require("math_header")
return {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
```

The same pattern works for regions:

```lua
-- io_header.lua
return {
  region. read { fd [i32], buf [ptr [u8]], count [index] } { ok{n[index]}, err{code[i32]} },
  region. write { fd [i32], buf [ptr [u8]], count [index] } { ok{n[index]}, err{code[i32]} },
}
```

What this unlocks:
- **Contract-first design**: sign the protocol before any implementation
- **Signature reuse**: same callable stage can be implemented differently per target
- **Factories**: generate callable stages from parameters; fill bodies later
- **Library mode**: modules export callable stages for callers to wire up

The callable stage is an ordinary Lua value — storable, passable, exportable.
No textual import directives. No parser. No antiquote.

## Names

Fixed names use spaced-dot grammar:

```lua
fn. add
struct. Vec2
region. scan
jump. loop
```

All declaration names (module items, regions, blocks, labels, and other header
positions) are dot-headed by construction. Plain names are reserved for
runtime variables and binds such as `x`, `acc`, and `n`.

Computed names use brackets:

```lua
fn[name]
struct["Vec" .. n]
```

Name tokens in DSL environments are created on demand:

```lua
ret (acc + x)
```

Here `acc` and `x` are name tokens resolved later by Moonlift semantic phases.

For generated names inside arrays, use `N`:

```lua
local fields = {}
for i = 1, 4 do
  fields[#fields + 1] = N["x" .. i] [f32]
end

struct. Vec4 {
  _(fields),
}
```

### Grepability

With dotted declaration names, grep can index DSL structure directly:

```text
# Declaration headers
rg '^\s*(fn|export_fn|struct|union|handle|extern|const|static|expr_frag|region)\.\s+[A-Za-z_][A-Za-z0-9_]*' path/to/dsl/*.md

# CFG structure (entry/block labels, jumps, emits)
rg '\b(entry|block|jump|emit)\.\s+[A-Za-z_][A-Za-z0-9_]*' path/to/*.lua

# Dot-name declarations in the DSL test corpus
rg '^\s*(fn|export_fn|struct|union|handle|extern|const|static|expr_frag|region|entry|block|jump|emit)\.\s+[A-Za-z_][A-Za-z0-9_]*' tests/frontend/test_dsl_lua_owned.lua
```

I verified these against the DSL reference + `tests/frontend/test_dsl_lua_owned.lua`;
no non-dot declaration names appear in that corpus.

## Types

Scalar type values:

```lua
void
bool
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64
index
rawptr
```

Compound type constructors:

```lua
ptr [u8]
view [i32]
slice [u8]
array [i32][16]
fnptr[{ i32, i32 }] [i32]
closure[{ i32 }] [i32]
lease [ptr [u8]]
lease(origin, ptr [u8])
owned [SessionRef]
```

Access wrappers:

```lua
ro [view [i32]]
wo [ptr [u8]]
readonly [view [i32]]
writeonly [ptr [u8]]
noalias [ptr [u8]]
noescape [ptr [u8]]
preserve [ptr [u8]]
invalidate [ptr [u8]]
```

Because `[]` is normal Lua indexing, each type argument is already a Lua value.
No textual type splice is performed.

## Products

Products are ordered array tables of typed names:

```lua
{ a [i32], b [i32] }
```

They appear as:

```text
function parameters
region parameters
struct fields
block parameters
continuation payload fields
union variant fields
```

Initializer form:

```lua
i [index](0)
acc [i32](0)
```

Used in entry block parameters:

```lua
entry. loop { i [index](0), acc [i32](0) } {
  ...
}
```

## Structs

```lua
struct. Vec2 {
  x [f32],
  y [f32],
}
```

Generated fields:

```lua
local xy = product {
  x [f32],
  y [f32],
}

struct. Point {
  _(xy),
  z [f32],
}
```

## Unions

```lua
union. Result {
  ok  { value [i32] },
  err { code [i32] },
  none,
}
```

Union alternatives are ordered array entries. Payload alternatives use named
payload table syntax. No-payload alternatives use bare name tokens.

## Handles

```lua
handle. SessionRef {
  invalid = 0,
}
```

With optional facts:

```lua
handle. SessionRef {
  invalid = 0,
  domain = "SessionStore",
  target = "SessionRecord",
}
```

## Externs

```lua
extern. write
  { fd [i32], buf [ptr [u8]], count [index] }
  [index]
  {
    symbol = "write",
  }
```

Void extern:

```lua
extern. trap
  { code [i32] }
  {
    symbol = "moon_trap",
  }
```

## Constants And Statics

```lua
const. answer [i32] { 42 }
static. zero [i32] { 0 }
```

The type slot receives the actual Lua value `i32`.

## Functions

```lua
fn. add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
  }
```

Exported function:

```lua
export_fn. add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
  }
```

Void function:

```lua
fn. touch
  { x [i32] }
  {
    ret (),
  }
```

A function body may be a plain statement list or a control-region body with
`entry` and `block` declarations:

```lua
fn. sum
  { n [i32] }
  [i32]
  {
    entry. loop { i [i32](0), acc [i32](0) } {
      when (i :ge (n)) {
        ret (acc),
      },

      jump. loop {
        i = i + 1,
        acc = acc + i,
      },
    },
  }
```

### Contracts

Functions may carry typed contract annotations via the `requires` keyword inside
the function body. `requires` consumes a `{}` table of contract constructors:

```lua
fn. read
  { buf [ptr [u8]], count [index] }
  [index]
  {
    requires {
      bounds(buf, count),
      noalias(buf),
    },
    ret (count),
  }
```

Available contract constructors:

```lua
bounds(base, len)              -- requires bounds(base, len)
window_bounds(base, base_len, start, len)
disjoint(a, b)                 -- requires disjoint(a, b)
same_len(a, b)                 -- requires same_len(a, b)
noalias(base)                  -- requires noalias(base)
readonly(base)                 -- requires readonly(base)
writeonly(base)                -- requires writeonly(base)
```

`noalias`, `readonly`, and `writeonly` act as both type wrappers
(`noalias[ptr[u8]]`) and contract constructors (`noalias(buf)`) — the
`[]` form produces a `Ty.TAccess` type, the `()` form produces a
`Tr.Contract*` node.

`requires` items are extracted from the function body during lowering — they
are not statements and do not appear in the emitted code.

## Statements

Return:

```lua
ret (value)
ret (1)
ret "done"
ret { 1, 2, 3 }
ret ()
```

Yield:

```lua
yield (value)
yield (1)
yield "done"
yield { 1, 2, 3 }
yield ()
```

Local values:

```lua
let. x [i32] { 1 }
var. i [index] { 0 }
```

Assignment:

```lua
store (dst[i], value)
set (dst[i], value)
```

Conditional:

```lua
when (cond) {
  body...
}
```

Jump:

```lua
jump. loop {
  i = i + 1,
  acc = acc + x,
}
```

Trap and assumptions:

```lua
trap ()
assume (cond)
assert_ (cond)
```

Atomic statements:

```lua
astore(i32, p, v)    -- atomic store
afence()             -- atomic fence
```

## Switch

Literal cases:

```lua
switch (x) {
  case (0) {
    ret 1,
  },

  default {
    ret 2,
  },
}
```

Variant-oriented cases use name-token cases:

```lua
switch (r) {
  case. ok { value } {
    ret (value),
  },

  default {
    ret (0),
  },
}
```

## Regions

Regions are named control fragments:

```lua
region. scan
  { p [ptr [u8]], n [index], target [i32] }
  {
    hit  { pos [index] },
    miss,
  }
  {
    entry. loop { i [index](0) } {
      when (i :ge (n)) {
        jump. miss { pos = i },
      },

      jump. loop {
        i = i + 1,
      },
    },
  }
```

Region parts:

```text
first table  -> input product
second table -> continuation protocol
third table  -> entry/block body
```

The body must contain one `entry` block and zero or more `block` declarations.

## Emit

Emit splices a region fragment into the current control flow:

```lua
emit. scan { p, n, target } {
  hit  = found,
  miss = failed,
}
```

Continuation fill maps are record tables. Fill values are block labels/name
tokens.

Example:

```lua
fn. find
  { p [ptr [u8]], n [index] }
  [i32]
  {
    entry. start {} {
      emit. scan { p, n, 65 } {
        hit  = done,
        miss = done,
      },
    },

    block. done { pos [i32] } {
      ret (pos),
    },
  }
```

## Expression Fragments

Expression fragments are reusable typed expression components:

```lua
expr_frag. inc
  { x [i32] }
  [i32]
  {
    x + 1
  }
```

They lower to `MoonOpen.ExprFrag` module items.

## Expressions

Literals:

```lua
1
1.5
true
nil
"bytes"
{ 1, 2, 3 }
```

Floating literals map to `f64` when present in `f64`-typed positions.
Lua string literals are emitted as `LitString` and default-type to `ptr(u8)`.
Because these are Lua calls, the no-parens form only applies to Lua's special
single-argument forms:

```lua
  const. greeting [ptr [u8]] "hello, moonlift"
  const. nums [array [i32] [3]] { 1, 2, 3 }
  ret "done"
  ret { 1, 2, 3 }
```

Other literals (`1`, `true`, `nil`) are written with parentheses: `ret (1)`,
`ret (true)`, `ret (nil)`.
`ret` / `yield` scalar expressions follow the same rule.

Returning function values is supported only via references or splice-built
expressions (not inline Lua function syntax). For example:

```lua
fn. foo { x [i32] } [i32] { ret (x) },
fn. mk {} [fnptr[{ i32 }] [i32]] { ret (foo) },
```

Aggregate literals (expression position):

```lua
{ x = 1, y = 2 }           -- struct literal, typed by context
{ 1, 2, 3 }                -- array literal, typed by expected array type
```

Name references:

```lua
x
acc
```

Arithmetic:

```lua
a + b
a - b
a * b
a / b
a % b
-a
```

Comparisons use methods or constructors because Lua comparison operators cannot
be overloaded into expression trees. Default style puts spaces before the
method colon and before the argument list so comparison methods read like
Moonlift operators:

```lua
i :ge (n)
i :lt (n)
eq(a, b)
ne(a, b)
```

Boolean logic uses constructors because Lua `and`, `or`, and `not` cannot be
overloaded:

```lua
And(a, b)
Or(a, b)
Not(a)
```

Index and field:

```lua
xs[i]
point.x
```

Casts:

```lua
as [i32](x)
bitcast [u64](bits)
```

Pointer and size helpers:

```lua
addr(place)
deref(ptr)
load(ptr)
null [ptr [u8]]
is_null(p)
sizeof [i32]
alignof [i32]
```

Select:

```lua
select(cond, a, b)
```

### Atomics

```lua
aload(i32, p)                    -- atomic load
acas(i32, p, expected, replacement)  -- atomic compare-and-swap
armw("add", i32, p, v)           -- atomic read-modify-write
```

RMW ops: `"add"`, `"sub"`, `"band"`, `"bor"`, `"bxor"`, `"xchg"`.

### Variant constructor

```lua
ctor("Result", "ok", { 42 })
ctor("Result", "err", { 7 })
```

Returns an `Expr` tree node. The type name and variant name are strings;
payload arguments are an ordered table of expression values.

## Fragments And Splicing

Lua has no spread syntax, so Moonlift uses `_ (value)` as the preferred splice
marker. `spread(value)` remains available as the explicit fallback, especially
in scopes where `_` is shadowed by a local variable.

Product fragment:

```lua
local xy = product {
  x [f32],
  y [f32],
}

struct. Vec2 {
  _(xy),
}
```

Statement fragment:

```lua
local done = stmts {
  ret (0),
}

fn. f {} [i32] {
  _(done),
}
```

Declaration fragment:

```lua
local decls = decls {
  struct. A { x [i32] },
  struct. B { y [i32] },
}

return {
  _(decls),
}
```

The fragment role must match the receiving context.

## Host-Time Generation

Because the DSL is Lua, generation is ordinary Lua.

```lua
local function make_vec(n, T)
  local fields = {}

  for i = 1, n do
    fields[#fields + 1] = N["x" .. i] [T]
  end

  return struct["Vec" .. n] {
    _(fields),
  }
end

return {
  make_vec(2, f32),
  make_vec(3, f32),
  make_vec(4, f32),
}
```

No source generics are needed. Lua performs generation; Moonlift receives
monomorphic ASDL.

## Power: Natural Slicing Without A Parser

The DSL naturally models slicing of programs because every syntactic component
is already a Lua value.

You can build a slice of parameters:

```lua
local view_params = product {
  data [ptr [u8]],
  len [index],
  stride [index],
}
```

Use it in multiple declarations:

```lua
struct. ViewU8 {
  _(view_params),
}

fn. first
  { _(view_params) }
  [u8]
  {
    ret (data[0]),
  }
```

You can slice statement bodies:

```lua
local bounds_check = stmts {
  when (i :ge (len)) {
    trap (),
  },
}

fn. get
  { data [ptr [u8]], len [index], i [index] }
  [u8]
  {
    _(bounds_check),
    ret (data[i]),
  }
```

You can slice control protocols:

```lua
local hit_miss = conts {
  hit { pos [index] },
  miss {},
}

region. scan_a
  { p [ptr [u8]], n [index] }
  { _(hit_miss) }
  {
    entry. start {} {
      jump. miss {},
    },
  }
```

This is not textual macro expansion. The slices are typed Lua values with roles.
The normalizer rejects a product fragment in a statement body, a statement
fragment in a struct, or a malformed continuation payload.

This is the main power of the layer:

```text
program parts are ordinary values
program shapes are ordinary Lua tables
Moonlift still receives explicit ASDL
```

The result is a metaprogramming surface with no parser debt.

## Reflection And Methods

DSL unit/declaration values expose:

```lua
value:syntax()          -- MoonTree module for units
value:ast()             -- lowered MoonTree item/module
value:typecheck(opts)   -- tree typecheck result
value:lower(opts)       -- frontend lower_module result
value:compile(opts)     -- JIT compile through backend pipeline
value:emit_c_artifact(opts)
```

Fragments support `#fragment` and `tostring(fragment)`.

## Diagnostics

The DSL fails early for role-shape mistakes:

```text
parameter expects name [type]
field expects name [type]
region body expects entry/block declarations
function body cannot mix entry/block declarations with ordinary statements
expected product fragment, got stmt
```

Semantic errors are reported by existing Moonlift phases after ASDL lowering:

```text
unresolved names
wrong argument type
invalid cast
bad jump payload
unterminated control block
owned/lease violations
```

## Grammar Summary

```lua
return unit. Name {
  struct. Name {
    field [T],
  },

  union. Name {
    variant { payload [T] },
    none,
  },

  fn. name
    { param [T] }
    [Result]
    {
      requires {
        bounds(param, N.n),
      },
      ret (expr),
    },

  region. name
    { input [T] }
    {
      ok { value [T] },
      err,
    }
    {
      entry. start {} {
        jump. ok { value = input },
      },
    },
}
```

The surface remains Lua, but the grammar mirrors Moonlift’s algebra:

```text
products    -> ordered tables of typed names
protocols   -> ordered tables of named alternatives
bodies      -> ordered tables of statements/blocks
maps/fills  -> record tables
type slots  -> evaluated Lua values in []
generation  -> ordinary Lua
```

No parser is hiding behind the DSL. Lua is the parser; Moonlift owns the
semantics.

## Formatting

Moonlift has semantic formatting for format-owned DSL files.

A format-owned file is ordinary Lua whose meaningful output is the evaluated
Moonlift value it returns. The formatter evaluates the file, formats the
returned Moonlift/LLB value, and emits canonical DSL Lua. It is not a general
Lua source formatter and does not preserve comments or arbitrary Lua
metaprogramming shape.

Canonical API:

```lua
local moon = require("moonlift")
moon.family.use()

local M = {
  fn. add { a [i32], b [i32] } [i32] {
    ret (a + b),
  },
}

print(moon.format(M))
```

Format-owned file API:

```lua
local text = require("moonlift").format_file("demo.lua")
require("moonlift").write_format_file("demo.lua")
```

Family reference generation:

```lua
local moon = require("moonlift")

local md = moon.markdown { title = "Moonlift Family Reference" }
moon.write_markdown("docs/MOONLIFT_FAMILY_REFERENCE.md")
```

`moon.markdown` delegates to the Moonlift family. The family writes the common
reference frame, then delegates to each language member. Moonlift, MoonSchema,
LLPVM, and Llisle own their semantic sections; plain LLB language metadata
fills in the generated head, role, export, and pass tables.

The generated reference always starts with the shared LLB syntax model. This is
intentional: Moonlift-family languages all use the same Lua mechanics for dot
heads, index/type slots, table/call slots, fragments, algebra, zones, origins,
formatting, diagnostics, and indexing.

CLI:

```sh
luajit scripts/moonfmt.lua demo.lua
luajit scripts/moonfmt.lua --check demo.lua
luajit scripts/moonfmt.lua --write demo.lua
```

Canonical output includes the Moonlift prelude:

```lua
local moon = require("moonlift")
moon.family.use()

return {
  ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
    ml.ret (a + b),
  },
}
```

Formatting defaults keep short function and region signatures on one line and
break them by width. Predicate comparisons use method-style layout:

```lua
i :lt (n)
value :eq (target)
as [i32] (p[i]) :ne (sentinel)
```

Long predicates break at the operator:

```lua
as [i32] (buffer[index + offset])
  :ne (sentinel)
```

Factories that generate Moonlift declarations should thread origins so
diagnostics point to the abstraction call site:

```lua
local moon = require("moonlift")
moon.family.use()

local function checked_add(name, origin)
  origin = origin or here("checked_add")
  return ml.fn:at(origin) [at_origin(origin, name)] {
    a [ml.i32],
    b [ml.i32],
  } [ml.i32] {
    ml.ret (a + b),
  }
end
```

## `moon.family.use()` sessions

`moon.family.use()` is the Moonlift-family wrapper over LLB family use sessions.
LLB supplies the shared substrate (`llb`, `_`, `spread`, process helpers,
origin helpers, and generic symbols). Moonlift, LLPVM, and MoonSchema are
installed as namespace values (`ml`/`moonlift`, `llpvm`, `schema`). LLB manages
environment installation, auto-names, collision policy, and cleanup.

Most authoring files ignore the return value:

```lua
require("moonlift").family.use()

return {
  ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
    ml.ret (a + b),
  },
}
```

When explicit access is useful, use the returned session:

```lua
local use = require("moonlift").family.use { scope = "env" }
local env = use.env
local add_head = env.ml.fn
```

Scopes:

```lua
require("moonlift").family.use()                       -- permanent global install
local s = require("moonlift").family.use { scope = "scoped" }
s:close()                                             -- remove what this session installed
local isolated = require("moonlift").family.use { scope = "env" }
```

Moonlift loaders and formatting use isolated `scope = "env"` sessions, so
`moon.loadstring`, `moon.loadfile`, and `moon.format_file` do not mutate `_G`.

The family namespace values are callable zone heads:

```lua
return {
  ml {
    ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
      ml.ret (a + b),
    },
  },

  llpvm {
    llpvm.task. compile {
      llpvm.input [ml.i32],
      llpvm.output [ml.i32],
      llpvm.event. progress [ml.i32],
    },
  },

  schema {
    schema. Demo {
      schema.product. Pair { left [MoonType.Type], right [MoonType.Type] },
    },
  },
}
```

Use `ml { ... }`, `llpvm { ... }`, and `schema { ... }` when one Lua value
contains multiple family languages. `moonlift { ... }` is the long spelling of
the `ml` zone. `moon.compile("Name", value)` recursively projects only Moonlift
declarations; LLPVM APIs recursively project only LLPVM programs. Zones are
semantic partitions over values. They do not create lexical environments; the
namespace prefix is still the lexical ownership marker.

The same family value is also the tooling boundary:

```lua
local value = moon.family.loadfile("program.lua")()

print(moon.family.format(value))

local diagnostics = moon.family.diagnostics(value)
if diagnostics:has_errors() then
  print(diagnostics:render())
end

local index = moon.family.index(value)

local reduction = moon.family.reduction()
assert(reduction.owner["type-family"] == "moonschema.dsl")
```

Formatting delegates each owned value to its member language. Diagnostics run
Moonlift projection/syntax/typecheck and LLPVM projection/lowering/task checks.
Indexing returns a family index with zone facts and member symbols. Reduction
returns the semantic owner/reuse graph and any overlap/external-use smells.

`moon.family.use()` options are forwarded to LLB where possible:

```lua
require("moonlift").use {
  scope = "permanent",
  strict = false,
  override = false,
  auto_names = true,
}
```

## Fragment algebra

Moonlift uses LLB fragment algebra for reusable, checked composition of DSL
structure.

Products/lists compose with `..`:

```lua
local buffer_params = product {
  p [ptr [u8]],
  n [index],
}

local scan_params = buffer_params .. product {
  target [i32],
}
```

Protocols compose with `+`:

```lua
local success = conts {
  hit { pos [index] },
}

local failure = conts {
  miss { pos [index] },
}

local scan_exits = success + failure
```

A product can decorate every continuation alternative with `*`:

```lua
local at_pos = product {
  pos [index],
}

local parse_errors = conts {
  eof {},
  bad_digit {},
  overflow {},
} * at_pos
```

Equivalent protocol:

```lua
conts {
  eof { pos [index] },
  bad_digit { pos [index] },
  overflow { pos [index] },
}
```

A region can use the composed fragments directly:

```lua
local parse_exits = conts {
  ok { value [i32], pos [index] },
} + (conts {
  eof {},
  bad_digit {},
  overflow {},
} * product {
  pos [index],
})

region. parse_i32 { p [ptr [u8]], n [index] } parse_exits {
  entry. start {} {
    jump. eof { pos = 0 },
  },
}
```

Supported Moonlift fragment roles:

```text
product  -- product fields/params; `..` and `*`
stmts    -- statement lists; `..`
decls    -- declaration lists; `..`
exprs    -- expression lists; `..`
conts    -- continuation protocols; `+` and `*`
variants -- union variants; `+` and `*`
```

Each role constructor can be called with no argument to create the identity
fragment for that role:

```lua
local params = product()
local body = stmts()
local exits = conts()
```

This is the preferred pattern for conditional metaprogramming:

```lua
local function maybe_indexed(include_index)
  local params = product {
    p [ptr [u8]],
  }

  if include_index then
    params = params .. product {
      i [index],
    }
  end

  return params
end
```

For sum/protocol identities, use `+` to add alternatives:

```lua
local exits = conts()

if want_ok then
  exits = exits + conts {
    ok {},
  }
end

if want_error then
  exits = exits + conts {
    err { code [i32] },
  }
end
```

Bad algebra is rejected early. Examples:

```lua
product { a [i32] } + product { b [i32] } -- wrong operator
product { a [i32] } .. conts { ok {} }    -- role mismatch
conts { ok {} } + conts { ok {} }         -- duplicate alternative
```

### Preferred metaprogramming style

Fragment algebra is the preferred way to metaprogram Moonlift DSL structure.
Factories should return role-tagged fragments instead of raw Lua arrays when
producing reusable pieces of declarations, parameters, statements, expressions,
continuation protocols, or union variants.

Prefer:

```lua
local function buffer_params()
  return product {
    p [ptr [u8]],
    n [index],
  }
end

local function positioned_errors()
  return conts {
    eof {},
    bad_digit {},
    overflow {},
  } * product {
    pos [index],
  }
end

local params = buffer_params() .. product {
  radix [i32],
}

local exits = conts {
  ok { value [i32], pos [index] },
} + positioned_errors()
```

Avoid raw table plumbing for reusable DSL pieces:

```lua
local out = {}
out[#out + 1] = p [ptr [u8]]
out[#out + 1] = n [index]
return out
```

Raw Lua tables are still useful inside a factory, but the public result of a
Moonlift metaprogramming helper should normally be a fragment with an explicit
role. This preserves role information, enables early diagnostics, keeps
composition readable, and lets formatting/rendering recover canonical DSL
structure after evaluation.

## LuaJIT copy-and-patch artifact emission

Moonlift can emit a self-contained LuaJIT source artifact that embeds selected native stencil bytes and installs them with copy-and-patch at load time.

```lua
local moon = require("moonlift")
moon.use { scope = "env" }

local sum_i32 = fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
  requires { bounds(xs, n), readonly(xs) },

  entry. start {} { jump. loop { i = 0, acc = 0 }, },

  block. loop { i [i32], acc [i32] } {
    when (i :lt (n)) {
      jump. body { i = i, acc = acc },
    },

    jump. done { acc = acc },
  },

  block. body { i [i32], acc [i32] } {
    jump. loop { i = i + 1, acc = acc + xs[i] },
  },

  block. done { acc [i32] } {
    ret(acc),
  },
}

local artifact = moon.emit_luajit_artifact(sum_i32, {
  path = "target/artifacts/sum_i32.lua",
  name = "SumI32",
  stem = "sum_i32",
})
```

The emitted `.lua` file contains residual LuaJIT wrapper code plus embedded native stencil byte strings. Loading the file checks the runtime target, copies the embedded stencil bytes to executable memory, patches relocation holes, casts the installed addresses to FFI function pointers, and returns the generated module table.

```lua
local mod = assert(loadfile("target/artifacts/sum_i32.lua"))()
print(mod.sum_i32(xs, n))
```

This path uses the same Moonlift frontend and MoonStencil schedule/artifact selection as the normal compiler. The LuaJIT copy-and-patch backend only realizes already-selected `StencilArtifact` values; it does not re-lower loops or keep a separate vector/reduction machine.
