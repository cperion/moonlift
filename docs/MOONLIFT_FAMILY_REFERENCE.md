# Moonlift Family Reference

Generated from LLB family introspection.

## LLB Syntax Model

All languages in this family are ordinary Lua values built through the shared LLB substrate. Lua provides the syntax; LLB gives that syntax language meaning through heads, roles, slots, fragments, origins, environments, and family zones.

Core forms:

- `namespace.head. name` uses Lua field lookup through an LLB namespace to feed a name slot, for example `moonlift.fn. add` or `llpvm.task. compile`.
- `value [Type]` uses Lua indexing to attach a type or computed slot, for example `a [moonlift.i32]`.
- `head { ... }` uses Lua calls and tables to feed product, body, declaration, protocol, or record slots.
- `name = value` inside a table remains native Lua record syntax and is used for record/fill/map-shaped data.
- `_ (fragment)` splices a role-shaped fragment into the surrounding role.
- `left .. right` concatenates compatible product/list fragments or family zones.
- `left + right` composes compatible sum/protocol alternatives.
- `left * right` decorates sum/protocol alternatives with product-shaped payloads when the language role supports it.
- `moonlift { ... }`, `llpvm { ... }`, `asdl { ... }`, and similar forms call LLB namespace values to create family zones: explicit language scopes inside one Lua value.

In family environments, member DSLs are exposed through LLB namespace values. The namespace is a semantic owner, not just a Lua table: tools can describe it, document it, and use its call form for zones.

The dot belongs visually to the keyword side. Canonical LLB style is `moonlift.fn. add`, not `moonlift.fn .add`: the keyword/head is the syntactic operator, while the name stays clean.

There is no parser, tokenizer, antiquote layer, or string language hidden here. A source file evaluates as Lua; the resulting values already contain enough LLB metadata for diagnostics, formatting, indexing, documentation, and language-specific lowering.

## Family

- Name: `moonlift`
- Collision policy: `error`

### Provides

- `llb`
- `llb.core`
- `moonlift.types`
- `moonlift.dsl`
- `moonschema.dsl`
- `moonlift.schema`
- `llpvm.dsl`

### Requires

- `moonlift.types`
- `moonlift.schema`

### Shared names

- `diagnostic`
- `fragment`
- `origin`
- `process`
- `type_value`

### Reserved names

- `event`
- `input`
- `lang`
- `llpvm`
- `machine`
- `ml`
- `moonlift`
- `op`
- `output`
- `phase`
- `pvm`
- `record`
- `root`
- `schema`
- `stream`
- `task`
- `type`
- `world`

## Reduced Family

A reduced family has one owner for each semantic primitive. Other members reuse that primitive through explicit dependencies instead of reimplementing the same meaning under another surface.

### Semantic owners

- `authoring-substrate`: `llb`
- `bytecode-program`: `llpvm.dsl`
- `bytecode-stream`: `llpvm.dsl`
- `diagnostics`: `llb`
- `family-composition`: `llb`
- `fragments`: `llb`
- `namespaces`: `llb`
- `native-compilation`: `moonlift.dsl`
- `native-control`: `moonlift.dsl`
- `native-program`: `moonlift.dsl`
- `native-type-values`: `moonlift.dsl`
- `origins`: `llb`
- `process-task`: `llpvm.dsl`
- `product-sum-schema`: `moonschema.dsl`
- `pvm-image`: `llpvm.dsl`
- `resource-discipline`: `moonlift.dsl`
- `schema-identity`: `moonschema.dsl`
- `schema-modules`: `moonschema.dsl`
- `type-family`: `moonschema.dsl`

### Semantic reuse

- `authoring-substrate` is used by `moonlift.dsl`, `moonschema.dsl`, `llpvm.dsl`
- `diagnostics` is used by `moonlift.dsl`, `moonschema.dsl`, `llpvm.dsl`
- `family-composition` is used by `moonlift.dsl`, `moonschema.dsl`, `llpvm.dsl`
- `fragments` is used by `moonlift.dsl`, `moonschema.dsl`, `llpvm.dsl`
- `namespaces` is used by `moonlift.dsl`, `moonschema.dsl`, `llpvm.dsl`
- `native-type-values` is used by `llpvm.dsl`
- `origins` is used by `moonlift.dsl`, `moonschema.dsl`, `llpvm.dsl`
- `type-family` is used by `moonlift.dsl`, `llpvm.dsl`

### Reduction audit

- no semantic ownership overlaps

## Members

```lua
member. llb {
  provides { llb, llb.core }
  owns { authoring-substrate, diagnostics, family-composition, fragments, namespaces, origins }
  tooling { markdown }
}
member. moonlift.dsl {
  provides { moonlift.types, moonlift.dsl }
  owns { native-program, native-control, native-type-values, resource-discipline, native-compilation }
  uses { authoring-substrate, diagnostics, family-composition, fragments, namespaces, origins, type-family }
  tooling { format, diagnostics, index, markdown, match }
}
member. moonschema.dsl {
  provides { moonschema.dsl, moonlift.schema }
  owns { schema-modules, type-family, product-sum-schema, schema-identity }
  uses { authoring-substrate, diagnostics, family-composition, fragments, namespaces, origins }
  tooling { format, diagnostics, index, markdown, match }
}
member. llpvm.dsl {
  provides { llpvm.dsl }
  requires { moonlift.types, moonlift.schema }
  owns { bytecode-program, bytecode-stream, process-task, pvm-image }
  uses { authoring-substrate, diagnostics, family-composition, fragments, namespaces, origins, native-type-values, type-family }
  tooling { format, diagnostics, index, markdown, match }
}
```

## Zones

Zones are semantic partitions inside family values. Each member may expose a zone head such as `moonlift { ... }` or `llpvm { ... }`.

## Tooling

- `family.format(value, opts)`
- `family.diagnostics(value, opts)`
- `family.index(value, opts)`
- `family.reduction()`
- `family.markdown(opts)`

## Member References

## llb

Shared Lua Language Builder substrate installed into every family environment.

### Core Exports

- `llb`: the singleton workbench API for origins, diagnostics, fragments, families, formatting, and markdown.
- `_` / `spread`: splice a role-shaped fragment into a surrounding role.
- `N`: explicit generated-name factory for metaprogrammed symbols.
- `here`, `at_origin`, `with_origin`: provenance helpers for Lua factories.

### Grammar Bootstrap

- `llb.grammar.role`: declares a named semantic role and its normalization contract.
- `llb.grammar.head`: declares a staged constructor head made from slots and traits.
- `llb.grammar.slot`: declares one consumed input position for a head.
- `llb.grammar.trait`: declares reusable behavior applied to heads.
- `llb.grammar.protocol`: declares a named protocol surface for language authors.
- `llb.grammar.scalar` and `llb.grammar.type_ctor`: declare type-like exports.
- `llb.grammar.helper`: exposes a named Lua helper into a language environment.
- `llb.grammar.pass` / `llb.grammar.phase`: declares semantic analysis passes.
- `llb.grammar.lsp`: declares language-server integration hooks.

## moonlift.dsl

Moonlift is the typed native language member of the family. It owns functions, regions, types, resources, and native compilation projection.

Family source uses the `ml` namespace value for Moonlift. `moonlift` is the long alias. Call `ml { ... }` when a family value contains Moonlift declarations.

```lua
ml {
  ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
    ml.ret (a + b),
  },
}
```

### Moonlift LLB Surface

### Exports

- `And`
- `N`
- `Not`
- `Or`
- `_`
- `alignof`
- `as`
- `bitcast`
- `block`
- `boolean`
- `const`
- `conts`
- `decls`
- `emit`
- `entry`
- `eq`
- `export_fn`
- `expr`
- `expr_frag`
- `extern`
- `fn`
- `handle`
- `identity`
- `import`
- `jump`
- `let`
- `name`
- `ne`
- `null`
- `number`
- `params`
- `region`
- `select`
- `sizeof`
- `spread`
- `static`
- `stmts`
- `string`
- `struct`
- `type`
- `union`
- `unit`
- `value`
- `var`
- `variants`

### Roles

```lua
role. boolean { kind = "boolean" }
role. conts { kind = "array", algebra = "sum", payload = "product" }
role. decls { kind = "array" }
role. expr { kind = "expr" }
role. identity { kind = "identity" }
role. name { kind = "name" }
role. number { kind = "number" }
role. params { kind = "array" }
role. stmts { kind = "array" }
role. string { kind = "string" }
role. type { kind = "type" }
role. value { kind = "value" }
role. variants { kind = "array", algebra = "sum", payload = "product" }
```

- `boolean` — kind=boolean
- `conts` — kind=array, algebra=sum, payload=product
- `decls` — kind=array
- `expr` — kind=expr
- `identity` — kind=identity
- `name` — kind=name
- `number` — kind=number
- `params` — kind=array
- `stmts` — kind=array
- `string` — kind=string
- `type` — kind=type
- `value` — kind=value
- `variants` — kind=array, algebra=sum, payload=product

### Heads

#### `block`

Declares an internal region block with typed parameters and terminating statements.

```lua
block. name { name [Type], ... } { stmt, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `params` role=`params` channel=`call:table`
- ` { stmt, ... }` -> `body` role=`stmts` channel=`call:table`

Traits: `control_block`

#### `const`

Declares a typed compile-time constant value.

```lua
const. name [Type] { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` [Type]` -> `ty` role=`type` channel=`index:type`
- ` { ... }` -> `value` role=`value` channel=`call:none,call:value,call:table,call:many`

Traits: `declaration`

#### `emit`

Splices a region into the current CFG and binds its continuation exits to local targets.

```lua
emit. name { ... } { ... }
```

Slots:

- `. name` -> `target` role=`name` channel=`index:name`
- ` { ... }` -> `args` role=`value` channel=`call:table`
- ` { ... }` -> `fills` role=`value` channel=`call:table`

Traits: `statement`

#### `entry`

Declares a region entry block with typed block parameters and terminating statements.

```lua
entry. name { name [Type], ... } { stmt, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `params` role=`params` channel=`call:table`
- ` { stmt, ... }` -> `body` role=`stmts` channel=`call:table`

Traits: `control_block`

#### `export_fn`

Declares a native function that is exported across the generated module boundary.

```lua
export_fn. name { name [Type], ... } [Type] { stmt, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `params` role=`params` channel=`call:table`
- ` [Type]` -> `result` role=`type` channel=`index:type` optional
- ` { stmt, ... }` -> `body` role=`stmts` channel=`call:table`

Traits: `declaration`

#### `expr_frag`

Declares a reusable expression fragment sealed by a result type.

```lua
expr_frag. name { name [Type], ... } [Type] { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `params` role=`params` channel=`call:table`
- ` [Type]` -> `result` role=`type` channel=`index:type`
- ` { ... }` -> `body` role=`value` channel=`call:none,call:value,call:table,call:many`

Traits: `declaration`

#### `extern`

Declares an imported host or C function signature plus boundary options.

```lua
extern. name { name [Type], ... } [Type] { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `params` role=`params` channel=`call:table`
- ` [Type]` -> `result` role=`type` channel=`index:type` optional
- ` { ... }` -> `opts` role=`value` channel=`call:table`

Traits: `declaration`

#### `fn`

Declares a native Moonlift function with typed parameters, an optional result type, and a statement body.

```lua
fn. name { name [Type], ... } [Type] { stmt, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `params` role=`params` channel=`call:table`
- ` [Type]` -> `result` role=`type` channel=`index:type` optional
- ` { stmt, ... }` -> `body` role=`stmts` channel=`call:table`

Traits: `declaration`

#### `handle`

Declares a nominal handle type for durable external or store-resolved identity.

```lua
handle. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `opts` role=`value` channel=`call:table`

Traits: `declaration`

#### `import`

Imports declarations or fragments produced by another Lua module or factory.

```lua
import { ... }
```

Slots:

- ` { ... }` -> `target` role=`value` channel=`call:none,call:value,call:table,call:many`

Traits: `declaration`

#### `jump`

Transfers control to a named entry, block, or continuation with explicit argument fills.

```lua
jump. name { ... }
```

Slots:

- `. name` -> `target` role=`name` channel=`index:name`
- ` { ... }` -> `args` role=`value` channel=`call:table`

Traits: `statement`

#### `let`

Binds an immutable typed local value initialized by an expression.

```lua
let. name [Type] { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` [Type]` -> `ty` role=`type` channel=`index:type`
- ` { ... }` -> `init` role=`value` channel=`call:none,call:value,call:table,call:many`

Traits: `statement`

#### `region`

Declares a typed control region whose exits are named continuation alternatives.

```lua
region. name { name [Type], ... } { ok { ... }, err { ... } } { stmt, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `params` role=`params` channel=`call:table`
- ` { ok { ... }, err { ... } }` -> `conts` role=`conts` channel=`call:table`
- ` { stmt, ... }` -> `body` role=`stmts` channel=`call:table`

Traits: `declaration`

#### `static`

Declares a typed static data item emitted with the module.

```lua
static. name [Type] { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` [Type]` -> `ty` role=`type` channel=`index:type`
- ` { ... }` -> `value` role=`value` channel=`call:none,call:value,call:table,call:many`

Traits: `declaration`

#### `struct`

Declares a product type with named, typed fields and stable field order.

```lua
struct. name { name [Type], ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `fields` role=`params` channel=`call:table`

Traits: `declaration`

#### `union`

Declares a sum type whose variants may carry typed product payloads.

```lua
union. name { ok { ... }, err { ... } }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ok { ... }, err { ... } }` -> `variants` role=`variants` channel=`call:table`

Traits: `declaration`

#### `unit`

Declares a named Moonlift compilation unit containing public declarations.

```lua
unit. name { decl, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { decl, ... }` -> `body` role=`decls` channel=`call:table`

Traits: `declaration`

#### `var`

Binds a mutable typed local storage slot initialized by an expression.

```lua
var. name [Type] { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` [Type]` -> `ty` role=`type` channel=`index:type`
- ` { ... }` -> `init` role=`value` channel=`call:none,call:value,call:table,call:many`

Traits: `statement`

### Passes

- `llb.head_checks`

## moonschema.dsl

MoonSchema is the ASDL/schema member of the Moonlift family. It owns typed schema declarations used to define the compiler family itself.

In the full Moonlift family, MoonSchema is exposed through the `schema` namespace value. Use `schema. Name { ... }` for modules, `schema.product`, `schema.sum`, `schema.alias`, `schema.field`, and schema helpers such as `schema.many`.

```lua
schema {
  schema. Demo {
    schema.product. Pair { schema.interned, left [MoonType.Type], right [MoonType.Type] },
  },
}
```

### MoonSchema LLB Surface

### Exports

- `And`
- `N`
- `Not`
- `Or`
- `_`
- `alias`
- `alignof`
- `any`
- `as`
- `bitcast`
- `bool`
- `boolean`
- `decls`
- `eq`
- `expr`
- `field`
- `function_ty`
- `id`
- `identity`
- `interned`
- `many`
- `map`
- `name`
- `ne`
- `nil_ty`
- `null`
- `number`
- `optional`
- `product`
- `product_body`
- `ref`
- `schema`
- `schema_type`
- `select`
- `sizeof`
- `spread`
- `str`
- `string`
- `sum`
- `sum_body`
- `table_ty`
- `type`
- `unique`
- `value`
- `variant_unique`

### Roles

```lua
role. boolean { kind = "boolean" }
role. decls { kind = "array" }
role. expr { kind = "expr" }
role. identity { kind = "identity" }
role. name { kind = "name" }
role. number { kind = "number" }
role. product_body { kind = "array" }
role. schema_type { kind = "value" }
role. string { kind = "string" }
role. sum_body { kind = "array" }
role. type { kind = "type" }
role. value { kind = "value" }
```

- `boolean` — kind=boolean
- `decls` — kind=array
- `expr` — kind=expr
- `identity` — kind=identity
- `name` — kind=name
- `number` — kind=number
- `product_body` — kind=array
- `schema_type` — kind=value
- `string` — kind=string
- `sum_body` — kind=array
- `type` — kind=type
- `value` — kind=value

### Heads

#### `alias`

Declares a type alias to another schema type path.

```lua
alias. name [Type]
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` [Type]` -> `target` role=`schema_type` channel=`index:type,index:value`

#### `field`

Declares a field when the field name collides with a schema helper or Lua
reserved word.

```lua
field. name [Type]
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` [Type]` -> `target` role=`schema_type` channel=`index:type,index:value`

#### `product`

Declares a product type with named fields.

```lua
product. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`product_body` channel=`call:table`

#### `schema`

Declares a MoonSchema module: the root namespace for ASDL products, sums,
and aliases.

```lua
schema. name { decl, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { decl, ... }` -> `decls` role=`decls` channel=`call:table`

#### `sum`

Declares a sum type with named variants.

```lua
sum. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`sum_body` channel=`call:table`

### Passes

- `llb.head_checks`

## llpvm.dsl

LLPVM is the low-level process/bytecode VM member of the Moonlift family. It owns bytecode programs, task/process specs, validation, and inspection.

Family source uses the `llpvm` namespace value. Call `llpvm { ... }` when a family value carries LLPVM programs next to Moonlift declarations.

```lua
llpvm {
  llpvm.task. compile {
    llpvm.input [ml.i32],
    llpvm.output [ml.i32],
    llpvm.event. progress [ml.i32],
  },
}
```

### LLPVM LLB Surface

### Exports

- `And`
- `N`
- `Not`
- `Or`
- `_`
- `alignof`
- `as`
- `bitcast`
- `boolean`
- `cache`
- `decls`
- `entry`
- `eq`
- `event`
- `expr`
- `fields`
- `from`
- `identity`
- `input`
- `lang`
- `lang_body`
- `machine`
- `name`
- `ne`
- `null`
- `number`
- `op`
- `output`
- `phase`
- `phase_body`
- `pvm`
- `record`
- `root`
- `root_body`
- `select`
- `sizeof`
- `spread`
- `stream`
- `stream_body`
- `string`
- `task`
- `task_body`
- `to`
- `type`
- `type_body`
- `value`
- `world`

### Roles

```lua
role. boolean { kind = "boolean" }
role. decls { kind = "array", algebra = "list" }
role. expr { kind = "expr" }
role. fields { kind = "array", algebra = "product" }
role. identity { kind = "identity" }
role. lang_body { kind = "array", algebra = "list" }
role. name { kind = "name" }
role. number { kind = "number" }
role. phase_body { kind = "array", algebra = "list" }
role. root_body { kind = "array", algebra = "list" }
role. stream_body { kind = "array", algebra = "list" }
role. string { kind = "string" }
role. task_body { kind = "array", algebra = "list" }
role. type { kind = "type" }
role. type_body { kind = "array", algebra = "list" }
role. value { kind = "value" }
```

- `boolean` — kind=boolean
- `decls` — kind=array, algebra=list
- `expr` — kind=expr
- `fields` — kind=array, algebra=product
- `identity` — kind=identity
- `lang_body` — kind=array, algebra=list
- `name` — kind=name
- `number` — kind=number
- `phase_body` — kind=array, algebra=list
- `root_body` — kind=array, algebra=list
- `stream_body` — kind=array, algebra=list
- `string` — kind=string
- `task_body` — kind=array, algebra=list
- `type` — kind=type
- `type_body` — kind=array, algebra=list
- `value` — kind=value

### Heads

#### `cache`

Declares the cache policy or cache key for a phase.

```lua
cache. name
```

Slots:

- `. name` -> `value` role=`name` channel=`index:name`

#### `entry`

Names the entry phase or machine for a root/task execution surface.

```lua
entry. name
```

Slots:

- `. name` -> `value` role=`name` channel=`index:name`

#### `event`

Declares one task event and its payload type.

```lua
event. name. name
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- `. name` -> `payload` role=`value` channel=`index:value,index:name,index:type`

Traits: `named`

#### `from`

Names the source world or stream for a root or phase edge.

```lua
from. name
```

Slots:

- `. name` -> `value` role=`name` channel=`index:name`

#### `input`

Marks the input world, value, or stream consumed by a phase or task.

```lua
input. name
```

Slots:

- `. name` -> `value` role=`value` channel=`index:value,index:name,index:type`

#### `lang`

Declares an operation language namespace containing typed operation definitions.

```lua
lang. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`lang_body` channel=`call:table`

Traits: `named`

#### `machine`

Declares a reusable machine made from phase directives and stages.

```lua
machine. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`phase_body` channel=`call:table`

Traits: `named`

#### `op`

Declares one operation constructor with product-shaped fields.

```lua
op. name { name [Type], ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { name [Type], ... }` -> `fields` role=`fields` channel=`call:table`

Traits: `named`

#### `output`

Marks the output world, value, or stream produced by a phase or task.

```lua
output. name
```

Slots:

- `. name` -> `value` role=`value` channel=`index:value,index:name,index:type`

#### `phase`

Declares a named phase body with input/output/cache/implementation directives.

```lua
phase. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`phase_body` channel=`call:table`

Traits: `named`

#### `pvm`

Declares an LLPVM program containing languages, worlds, streams, machines, phases, tasks, and roots.

```lua
pvm. name { decl, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { decl, ... }` -> `body` role=`decls` channel=`call:table`

Traits: `named`

#### `record`

Declares a named stream record expression.

```lua
record. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `expr` role=`value` channel=`call:none,call:value,call:table,call:many`

Traits: `named`

#### `root`

Declares a root execution plan by composing directives and stages.

```lua
root { ... }
```

Slots:

- ` { ... }` -> `body` role=`root_body` channel=`call:table`

#### `stream`

Declares a bytecode or fact stream attached to a world.

```lua
stream. name. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- `. name` -> `world` role=`value` channel=`index:value,index:name,index:type`
- ` { ... }` -> `body` role=`stream_body` channel=`call:table`

Traits: `named`

#### `task`

Declares a task protocol with input/output directives and emitted event payloads.

```lua
task. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`task_body` channel=`call:table`

Traits: `named`

#### `to`

Names the destination world or stream for a root or phase edge.

```lua
to. name
```

Slots:

- `. name` -> `value` role=`name` channel=`index:name`

#### `type`

Declares a named LLPVM type family containing operation constructors.

```lua
type. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`type_body` channel=`call:table`

Traits: `named`

#### `world`

Declares a named world over a language value.

```lua
world. name. name
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- `. name` -> `language` role=`value` channel=`index:value,index:name,index:type`

Traits: `named`

### Passes

- `llb.head_checks`
