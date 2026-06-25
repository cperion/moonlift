# Lalin Family Reference

Generated from LLB family introspection.

## LLB Syntax Model

All languages in this family are ordinary Lua values built through the shared LLB substrate. Lua provides the syntax; LLB gives that syntax language meaning through heads, roles, slots, fragments, origins, environments, and family zones.

Core forms:

- `namespace.head. name` uses Lua field lookup through an LLB namespace to feed a name slot, for example `lalin.fn. add` or `llpvm.task. compile`.
- `value [Type]` uses Lua indexing to attach a type or computed slot, for example `a [lalin.i32]`.
- `head { ... }` uses Lua calls and tables to feed product, body, declaration, protocol, or record slots.
- `name = value` inside a table remains native Lua record syntax and is used for record/fill/map-shaped data.
- `_ (fragment)` splices a role-shaped fragment into the surrounding role.
- `left .. right` concatenates compatible product/list fragments or family zones.
- `left + right` composes compatible sum/protocol alternatives.
- `left * right` decorates sum/protocol alternatives with product-shaped payloads when the language role supports it.
- `lalin { ... }`, `llpvm { ... }`, `asdl { ... }`, and similar forms call LLB namespace values to create family zones: explicit language scopes inside one Lua value.

In family environments, member DSLs are exposed through LLB namespace values. The namespace is a semantic owner, not just a Lua table: tools can describe it, document it, and use its call form for zones.

The dot belongs visually to the keyword side. Canonical LLB style is `lalin.fn. add`, not `lalin.fn .add`: the keyword/head is the syntactic operator, while the name stays clean.

There is no parser, tokenizer, antiquote layer, or string language hidden here. A source file evaluates as Lua; the resulting values already contain enough LLB metadata for diagnostics, formatting, indexing, documentation, and language-specific lowering.

## Family

- Name: `lalin`
- Collision policy: `error`

### Provides

- `llb`
- `llb.core`
- `lalin.types`
- `lalin.dsl`
- `lalinschema.dsl`
- `lalin.schema`
- `llpvm.dsl`
- `llisle.dsl`

### Requires

- `lalin.types`
- `lalin.schema`
- `llb.core`

### Shared names

- `diagnostic`
- `fragment`
- `origin`
- `process`
- `type_value`

### Reserved names

- `alt`
- `bind`
- `choose`
- `cost`
- `event`
- `fail`
- `input`
- `lang`
- `llisle`
- `llpvm`
- `machine`
- `ml`
- `lalin`
- `op`
- `output`
- `phase`
- `pvm`
- `record`
- `relation`
- `root`
- `rule`
- `rules`
- `run`
- `schema`
- `tape`
- `task`
- `type`
- `when`
- `world`

## Reduced Family

A reduced family has one owner for each semantic primitive. Other members reuse that primitive through explicit dependencies instead of reimplementing the same meaning under another surface.

### Semantic owners

- `authoring-substrate`: `llb`
- `bytecode-program`: `llpvm.dsl`
- `bytecode-tape`: `llpvm.dsl`
- `diagnostics`: `llb`
- `family-composition`: `llb`
- `fragments`: `llb`
- `lowering-rules`: `llisle.dsl`
- `namespaces`: `llb`
- `native-compilation`: `lalin.dsl`
- `native-control`: `lalin.dsl`
- `native-program`: `lalin.dsl`
- `native-type-values`: `lalin.dsl`
- `origins`: `llb`
- `process-task`: `llpvm.dsl`
- `product-sum-schema`: `lalinschema.dsl`
- `pvm-image`: `llpvm.dsl`
- `resource-discipline`: `lalin.dsl`
- `rewrite-relations`: `llisle.dsl`
- `schema-identity`: `lalinschema.dsl`
- `schema-modules`: `lalinschema.dsl`
- `sum-elimination`: `llisle.dsl`
- `type-family`: `lalinschema.dsl`

### Semantic reuse

- `authoring-substrate` is used by `lalin.dsl`, `lalinschema.dsl`, `llpvm.dsl`, `llisle.dsl`
- `diagnostics` is used by `lalin.dsl`, `lalinschema.dsl`, `llpvm.dsl`, `llisle.dsl`
- `family-composition` is used by `lalin.dsl`, `lalinschema.dsl`, `llpvm.dsl`, `llisle.dsl`
- `fragments` is used by `lalin.dsl`, `lalinschema.dsl`, `llpvm.dsl`, `llisle.dsl`
- `namespaces` is used by `lalin.dsl`, `lalinschema.dsl`, `llpvm.dsl`, `llisle.dsl`
- `native-type-values` is used by `llpvm.dsl`, `llisle.dsl`
- `origins` is used by `lalin.dsl`, `lalinschema.dsl`, `llpvm.dsl`, `llisle.dsl`
- `type-family` is used by `lalin.dsl`, `llpvm.dsl`, `llisle.dsl`

### Reduction audit

- no semantic ownership overlaps

## Members

```lua
member. llb {
  provides { llb, llb.core }
  owns { authoring-substrate, diagnostics, family-composition, fragments, namespaces, origins }
  tooling { markdown }
}
member. lalin.dsl {
  provides { lalin.types, lalin.dsl }
  owns { native-program, native-control, native-type-values, resource-discipline, native-compilation }
  uses { authoring-substrate, diagnostics, family-composition, fragments, namespaces, origins, type-family }
  tooling { format, diagnostics, index, markdown, match }
}
member. lalinschema.dsl {
  provides { lalinschema.dsl, lalin.schema }
  owns { schema-modules, type-family, product-sum-schema, schema-identity }
  uses { authoring-substrate, diagnostics, family-composition, fragments, namespaces, origins }
  tooling { format, diagnostics, index, markdown, match }
}
member. llpvm.dsl {
  provides { llpvm.dsl }
  requires { lalin.types, lalin.schema }
  owns { bytecode-program, bytecode-tape, process-task, pvm-image }
  uses { authoring-substrate, diagnostics, family-composition, fragments, namespaces, origins, native-type-values, type-family }
  tooling { format, diagnostics, index, markdown, match }
}
member. llisle.dsl {
  provides { llisle.dsl }
  requires { llb.core }
  owns { lowering-rules, rewrite-relations, sum-elimination }
  uses { authoring-substrate, diagnostics, family-composition, fragments, namespaces, native-type-values, origins, type-family }
  tooling { format, diagnostics, index, markdown, match }
}
```

## Zones

Zones are semantic partitions inside family values. Each member may expose a zone head such as `lalin { ... }` or `llpvm { ... }`.

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

## lalin.dsl

Lalin is the typed native language member of the family. It owns functions, regions, types, resources, and native compilation projection.

Family source uses the `ml` namespace value for Lalin. `lalin` is the long alias. Call `ml { ... }` when a family value contains Lalin declarations.

```lua
ml {
  ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
    ml.ret (a + b),
  },
}
```

### Lalin LLB Surface

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

Declares a native Lalin function with typed parameters, an optional result type, and a statement body.

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

Declares a named Lalin compilation unit containing public declarations.

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

## lalinschema.dsl

LalinSchema is the ASDL/schema member of the Lalin family. It owns typed schema declarations used to define the compiler family itself.

In the full Lalin family, LalinSchema is exposed through the `schema` namespace value. Use `schema. Name { ... }` for modules, `schema.product`, `schema.sum`, `schema.alias`, `schema.field`, and schema helpers such as `schema.many`.

```lua
schema {
  schema. Demo {
    schema.product. Pair { schema.interned, left [LalinType.Type], right [LalinType.Type] },
  },
}
```

### LalinSchema LLB Surface

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

Declares a LalinSchema module: the root namespace for ASDL products, sums,
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

LLPVM is the low-level process/bytecode VM member of the Lalin family. It owns bytecode programs, task/process specs, validation, and inspection.

Family source uses the `llpvm` namespace value. Call `llpvm { ... }` when a family value carries LLPVM programs next to Lalin declarations.

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
- `tape`
- `tape_body`
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
role. tape_body { kind = "array", algebra = "list" }
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
- `tape_body` — kind=array, algebra=list
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

Names the source world or tape for a root or phase edge.

```lua
from. name
```

Slots:

- `. name` -> `value` role=`name` channel=`index:name`

#### `input`

Marks the input world, value, or tape consumed by a phase or task.

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

Marks the output world, value, or tape produced by a phase or task.

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

Declares an LLPVM program containing languages, worlds, tapes, machines, phases, tasks, and roots.

```lua
pvm. name { decl, ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { decl, ... }` -> `body` role=`decls` channel=`call:table`

Traits: `named`

#### `record`

Declares a named tape record expression.

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

#### `tape`

Declares a bytecode or fact tape attached to a world.

```lua
tape. name. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- `. name` -> `world` role=`value` channel=`index:value,index:name,index:type`
- ` { ... }` -> `body` role=`tape_body` channel=`call:table`

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

Names the destination world or tape for a root or phase edge.

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

## llisle.dsl

Llisle is the lowering/rewrite/selection rule member of the Lalin family. It expresses compiler choices as typed relations, projection/classification relations, declared predicates, declared constructors, product-shaped patterns, sum alternatives, and process-shaped rule bodies.

Lua implementations are explicit values spliced through `[]` on `predicate.` and `constructor.` declarations. Llisle owns the semantic names; Lua supplies implementation values without a side-table registry.

Canonical Llisle source is normally authored as a Llisle island: install the Llisle member into the authoring environment, use `llisle { ... }` as the zone/container, and write the body with bare Llisle heads. Use `llisle.*` prefixes only when crossing a mixed-family boundary without installing the member island.

```lua
llisle {
  project. classify_expr {
    input { expr [LalinExpr] },
    output { class [ExprClassFact] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  relation. lower_expr {
    input { expr [LalinExpr], ctx [LowerCtx] },
    output { value [BackValue] },
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

  constructor. add_i32 [build_add_i32],

  rule. add_i32 {
    llisle.lower_expr {
      expr = add { lhs = P. lhs, rhs = P. rhs } [ml.i32],
      ctx = P. ctx,
    },

    when {
      (P. lhs :has_type (ml.i32)) * (P. rhs :has_type (ml.i32)),
    },

    run {
      emit. cmd { add_i32 { dst = V. out, lhs = P. lhs, rhs = P. rhs } },
      ret { value = V. out },
    },
  },
}
```

Stencil descriptor planning is split into Llisle plan and selector relations.
`plan_store_stencil` and `plan_reduce_stencil` own readiness gates over planned
kernels, counted positive loops, return shape, single-store or reduction shape,
and enriched class availability. `select_store_stencil` and
`select_reduce_stencil` own concrete stencil vocabulary, op, provider `info`,
and ordered machine argument lists.
Each concrete stencil constructor declares its Llisle product contract for
`info`, `args`, optional `op`, and `selection`, so family docs, tests, and LSP
indexing can inspect the vocabulary without executing the builder.
Use `luajit benchmarks/bench_luajit_stencil_matrix.lua full` as the bottom-up
performance gate for the complete C stencil vocabulary against GCC loops.
Use `luajit benchmarks/bench_luajit_lower_stencil_matrix.lua full` for the next
layer: LalinCode loop lowering must select the expected stencil vocabulary and
run at raw-stencil speed for the vocabulary represented by the current kernel
plan.
Non-store/non-reduction array skeletons are explicit LalinKernel semantics:
`KernelEffectScan`, `KernelEffectPartition`, `KernelEffectCopy`, and
`KernelResultFind`. Llisle owns their stencil descriptor selection through
`scan_array`, `partition_array`, overlap-aware `copy_array`, and `find_array`
constructors.
The counted-loop kernel planner currently infers prefix scan and copy skeletons
from ordinary LalinCode loops. Proven-independent copies lower as no-overlap
copies; unproven source/destination overlap lowers as `StencilCopyMemMove`.
Early-exit primary-index searches lower as `find_array`. Stable partition is a
function-level two-pass fragment and lowers through `KernelEffectPartition`.
The lower stencil matrix covers 18/18 vocabulary cells.

### Llisle LLB Surface

### Exports

- `And`
- `N`
- `Not`
- `Or`
- `_`
- `alignof`
- `alt`
- `alt_body`
- `ambiguity`
- `as`
- `bind`
- `bitcast`
- `boolean`
- `choose`
- `choose_body`
- `constructor`
- `constructor_body`
- `cost`
- `coverage`
- `decls`
- `effects`
- `emit`
- `eq`
- `expr`
- `fail`
- `fields`
- `guard_body`
- `identity`
- `input`
- `name`
- `ne`
- `null`
- `number`
- `output`
- `payload_body`
- `predicate`
- `predicate_body`
- `project`
- `pure`
- `relation`
- `relation_body`
- `ret`
- `rule`
- `rule_body`
- `rules`
- `rules_body`
- `run`
- `run_body`
- `select`
- `sizeof`
- `spread`
- `strategy`
- `strategy_body`
- `string`
- `type`
- `value`
- `when`

### Roles

```lua
role. alt_body { kind = "array", algebra = "list" }
role. boolean { kind = "boolean" }
role. choose_body { kind = "array", algebra = "list" }
role. constructor_body { kind = "array", algebra = "list" }
role. decls { kind = "array", algebra = "list" }
role. expr { kind = "expr" }
role. fields { kind = "array", algebra = "product" }
role. guard_body { kind = "array", algebra = "product" }
role. identity { kind = "identity" }
role. name { kind = "name" }
role. number { kind = "number" }
role. payload_body { kind = "array", algebra = "product" }
role. predicate_body { kind = "array", algebra = "list" }
role. relation_body { kind = "array", algebra = "list" }
role. rule_body { kind = "array", algebra = "list" }
role. rules_body { kind = "array", algebra = "list" }
role. run_body { kind = "array", algebra = "list" }
role. strategy_body { kind = "array", algebra = "list" }
role. string { kind = "string" }
role. type { kind = "type" }
role. value { kind = "value" }
```

- `alt_body` — kind=array, algebra=list
- `boolean` — kind=boolean
- `choose_body` — kind=array, algebra=list
- `constructor_body` — kind=array, algebra=list
- `decls` — kind=array, algebra=list
- `expr` — kind=expr
- `fields` — kind=array, algebra=product
- `guard_body` — kind=array, algebra=product
- `identity` — kind=identity
- `name` — kind=name
- `number` — kind=number
- `payload_body` — kind=array, algebra=product
- `predicate_body` — kind=array, algebra=list
- `relation_body` — kind=array, algebra=list
- `rule_body` — kind=array, algebra=list
- `rules_body` — kind=array, algebra=list
- `run_body` — kind=array, algebra=list
- `strategy_body` — kind=array, algebra=list
- `string` — kind=string
- `type` — kind=type
- `value` — kind=value

### Heads

#### `alt`

Declares one alternative inside choose.

```lua
alt. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`alt_body` channel=`call:table`

Traits: `named`

#### `ambiguity`

Selects ambiguity behavior.

```lua
ambiguity. name
```

Slots:

- `. name` -> `value` role=`name` channel=`index:name`

#### `bind`

Binds a produced local value from a relation call or expression.

```lua
bind. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`payload_body` channel=`call:table`

Traits: `named`

#### `choose`

Declares a local sum elimination inside a rule body.

```lua
choose { ... }
```

Slots:

- ` { ... }` -> `body` role=`choose_body` channel=`call:table`

#### `constructor`

Declares a semantic constructor used by ret/emit payload construction. The optional [] slot carries the Lua implementation value.

```lua
constructor. name [value] { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` [value]` -> `impl` role=`value` channel=`index:value`
- ` { ... }` -> `body` role=`constructor_body` channel=`call:table` optional

Traits: `named`

#### `cost`

Assigns cost metadata used by best-cost selection.

```lua
cost { ... }
```

Slots:

- ` { ... }` -> `value` role=`value` channel=`call:none,call:value,call:table,call:many`

#### `coverage`

Selects coverage behavior.

```lua
coverage. name
```

Slots:

- `. name` -> `value` role=`name` channel=`index:name`

#### `effects`

Declares process effects yielded by a relation.

```lua
effects { name [Type], ... }
```

Slots:

- ` { name [Type], ... }` -> `fields` role=`fields` channel=`call:table`

#### `emit`

Emits one process event/effect.

```lua
emit. name { ... }
```

Slots:

- `. name` -> `channel` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`payload_body` channel=`call:table`

#### `fail`

Fails the current rule or alternative with a diagnostic reason.

```lua
fail. name { ... }
```

Slots:

- `. name` -> `reason` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`payload_body` channel=`call:table`

#### `input`

Declares the input product of a relation.

```lua
input { name [Type], ... }
```

`Type` is the already evaluated Lua value inside `[]`. For compiler-family
relations this should normally be the real ASDL class value, for example
`input { expr [Tr.Expr] }`. Guards may then dispatch with `P.expr :is
(Tr.ExprLit)`, which uses ASDL runtime class identity instead of string
dispatch records.

Slots:

- ` { name [Type], ... }` -> `fields` role=`fields` channel=`call:table`

#### `output`

Declares the output product of a relation.

```lua
output { name [Type], ... }
```

Slots:

- ` { name [Type], ... }` -> `fields` role=`fields` channel=`call:table`

#### `predicate`

Declares a semantic predicate used by guards. The optional [] slot carries the Lua implementation value.

```lua
predicate. name [value] { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` [value]` -> `impl` role=`value` channel=`index:value`
- ` { ... }` -> `body` role=`predicate_body` channel=`call:table`

Traits: `named`

#### `project`

Declares a projection relation. Projection turns family values into LalinSchema-backed facts.

```lua
project. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`relation_body` channel=`call:table`

Traits: `named`

#### `pure`

Marks a predicate as pure.

```lua
pure
```

Slots: none

#### `relation`

Declares a typed product-to-product relation. Rules satisfy relations.

```lua
relation. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`relation_body` channel=`call:table`

Traits: `named`

#### `ret`

Returns the output product of a relation.

```lua
ret { ... }
```

Slots:

- ` { ... }` -> `body` role=`payload_body` channel=`call:table`

#### `rule`

Declares one rule: a relation pattern, guards, and a process body.

```lua
rule. name { ... }
```

Slots:

- `. name` -> `name` role=`name` channel=`index:name`
- ` { ... }` -> `body` role=`rule_body` channel=`call:table`

Traits: `named`

#### `rules`

Groups rule alternatives as a reusable fragment.

```lua
rules { ... }
```

Slots:

- ` { ... }` -> `body` role=`rules_body` channel=`call:table`

#### `run`

Declares the selected process-shaped body of a rule or alternative.

```lua
run { ... }
```

Slots:

- ` { ... }` -> `body` role=`run_body` channel=`call:table`

#### `select`

Selects the rule/alternative selection policy.

```lua
select. name
```

Slots:

- `. name` -> `value` role=`name` channel=`index:name`

#### `strategy`

Declares sum-elimination policy for relation or choice alternatives.

```lua
strategy { ... }
```

Slots:

- ` { ... }` -> `body` role=`strategy_body` channel=`call:table`

#### `when`

Declares guard predicates for a rule or alternative.

```lua
when { ... }
```

Slots:

- ` { ... }` -> `body` role=`guard_body` channel=`call:table`

### Passes

- `llb.head_checks`
