
# Moonlift Lua DSL API Specification

## Status

Draft specification for the Lua-owned Moonlift authoring API.

This document defines a new Moonlift surface where Lua itself owns parsing. Moonlift source islands, textual antiquote, and a separate Moonlift lexer/parser are not used for normal authoring. Instead, ordinary Lua syntax constructs explicit Moonlift ASDL values through callable tables, table shapes, indexing, staged calls, operator metamethods, contextual normalization, and scoped binding objects.

The design goal is:

```text
Lua parses mechanically.
The DSL object system parses semantically.
Moonlift validates, lowers, and emits explicit ASDL.
```

---

# 1. Design Doctrine

## 1.1 Purpose

The Moonlift Lua DSL is an authoring surface for Moonlift declarations, types, expressions, statements, functions, regions, control protocols, and modules.

It is not a bytecode assembly API. It is not a string templating API. It is not a second textual Moonlift parser.

The API constructs explicit typed Moonlift values directly from Lua values.

## 1.2 Non-negotiable laws

1. **Lua owns syntax.**
   Lua parses the file. The DSL interprets Lua values, table shapes, calls, and metamethods.

2. **Moonlift owns semantics.**
   The result of authoring is explicit Moonlift ASDL or host values that construct ASDL.

3. **No hidden semantic state.**
   If a distinction matters to compilation, it must become an explicit typed value, not a string convention, callback side effect, global side table, or backend-only inference.

4. **No source generics.**
   All Moonlift object code produced by this DSL is monomorphic. Genericity is ordinary Lua code generation.

5. **No textual antiquote in this surface.**
   `@{x}` and `@{xs...}` are for legacy quoted Moonlift source. In this DSL, Lua values are already in Lua. Use direct values, `spread(xs)`, or branded fragments.

6. **Infer declarations, spell control.**
   Repeated product/protocol forms may infer their role from context. Control edges remain explicit with `jump`, `emit`, `ret`, `yield`, `when`, `switch`, etc.

7. **Ordered things use array entries.**
   Struct fields, parameters, body statements, variants, and continuation alternatives are written as ordered array entries. Record fields are for unordered maps, attributes, and named arguments.

8. **Strings are values, not source.**
   String literals are runtime string literals, names, or raw foreign text only when the receiving constructor says so. Whole Moonlift programs are not constructed by string concatenation.

---

# 2. Execution Model

## 2.1 File kind

Recommended file extension:

```text
.mld.lua
```

A `.mld.lua` file is ordinary Lua executed under a Moonlift DSL authoring environment.

Example:

```lua
return module "Demo" {
  fn .add
    { a[i32], b[i32] }
    [i32]
    {
      ret { a + b },
    },
}
```

## 2.2 Loader

The implementation provides:

```lua
local dsl = require "moonlift.dsl"

local chunk = dsl.loadfile("demo.mld.lua")
local module_value = chunk()

local artifact = module_value:emit_c_artifact {
  name = "demo",
}
```

The loader executes the file in a controlled authoring environment containing the DSL keywords, types, constructors, and name-resolution hooks.

In LuaJIT / Lua 5.1 implementations, the loader may install the environment with `setfenv`. In Lua 5.2+, it may use `_ENV`.

## 2.3 Library mode

For ordinary Lua files that do not use a controlled environment, explicit namespaces are available:

```lua
local ml = require "moonlift.dsl"

local module = ml.module "Demo" {
  ml.fn .add
    { ml.N.a[ml.i32], ml.N.b[ml.i32] }
    [ml.i32]
    {
      ml.ret { ml.S.a + ml.S.b },
    },
}
```

Library mode is more verbose. The canonical surface assumes controlled-environment mode.

---

# 3. Visual Grammar

The DSL assigns roles to Lua syntax:

| Lua syntax      | DSL meaning                                                 |
| --------------- | ----------------------------------------------------------- |
| `.name`         | fixed DSL token or simple literal name                      |
| `[expr]`        | value insertion, type slot, computed name, static parameter |
| `{ ... }`       | product, protocol, body, payload, argument map, phrase      |
| `( ... )`       | ordinary Lua call, expression call, initializer, finalizer  |
| `"text"`        | name, string literal, label, raw text depending on context  |
| `name[T]`       | typed name token                                            |
| `name[T](init)` | typed name token with initializer                           |
| `name { ... }`  | named payload / declaration alternative                     |
| `a + b`         | expression tree construction                                |
| `a .. b`        | fragment or stream composition                              |
| `#x`            | static fact query                                           |
| `pairs(x)`      | semantic reflection                                         |

The four core visual channels are:

```text
.    fixed spelling
[]   inserted value / type / computed key
{}   structure
()   computation / ordinary call
```

---

# 4. Formatting Rules

Formatting is part of the developer experience. The formatter must preserve valid Lua while making the DSL grammar visible.

## 4.1 Spaced dots in grammar zones

Use spaces around dots for declaration and control grammar paths:

```lua
fn .add
struct .Vec2
region .scan_until
entry .loop
jump .miss
emit .parse_number
```

This is valid Lua and visually distinguishes DSL grammar paths from ordinary expression field access.

## 4.2 No spaced dots in expression zones by default

Expression code uses normal Lua-style formatting:

```lua
acc + xs[i]
i:ge(n)
len(xs)
user.name
```

Use spaced dots only when the path is acting as DSL grammar.

## 4.3 Declaration layout

Canonical function layout:

```lua
fn .name
  { params }
  [result_type]
  {
    body,
  }
```

Void-returning function:

```lua
fn .name
  { params }
  {
    body,
  }
```

Canonical region layout:

```lua
region .name
  { input_product }
  {
    protocol_alternatives,
  }
  {
    body,
  }
```

Canonical struct layout:

```lua
struct .Name {
  field_a[T],
  field_b[U],
}
```

Canonical union layout:

```lua
union .Name {
  case_a { payload_field[T] },
  case_b,
}
```

## 4.4 Named argument maps align equals

```lua
jump .loop {
  i   = i + 1,
  acc = acc + xs[i],
}
```

---

# 5. Core Value Classes

The DSL implementation exposes several internal value classes. Their concrete representation is implementation-defined, but their behavior is specified here.

## 5.1 Name token

A name token represents an unresolved spelling:

```lua
a
loop
ok
value
```

In controlled-environment mode, unknown identifiers produce name tokens.

A name token may be consumed differently depending on context:

| Context               | `x` means                              |
| --------------------- | -------------------------------------- |
| expression            | binding reference or unresolved symbol |
| union/protocol body   | no-payload alternative                 |
| name slot             | declaration/control name               |
| computed construction | symbolic name value                    |

A name token is neutral until consumed by a context.

## 5.2 Typed name token

```lua
a[i32]
xs[ro[view[i32]]]
i[index](0)
```

A typed name token represents:

```text
name + type + optional initializer
```

It is role-neutral until consumed.

Context decides whether it becomes:

| Context                 | Meaning                      |
| ----------------------- | ---------------------------- |
| function parameter list | parameter declaration        |
| region input list       | region parameter declaration |
| struct body             | field declaration            |
| block parameter list    | block parameter declaration  |
| continuation payload    | continuation payload field   |
| union variant payload   | variant payload field        |
| local declaration       | local binding type           |

## 5.3 Named payload

```lua
ok { value[i32] }
err { code[i32] }
```

A named payload represents:

```text
name + product payload
```

In protocol context, it becomes a continuation.
In union context, it becomes a variant.
In other contexts, it is rejected unless explicitly accepted.

## 5.4 Fragment

A fragment is a branded list-like value that can be inserted into a context with `spread(fragment)` or role-aware auto-flattening.

Examples:

```lua
local params = product { a[i32], b[i32] }
local body = stmts {
  let .x [i32] { 0 },
  ret { x },
}

fn .f { spread(params) } [i32] { spread(body) }
```

A context may also accept branded fragments directly:

```lua
fn .f { params } [i32] { body }
```

Only fragments with the expected role may auto-flatten.

## 5.5 Binding object

A binding object is a resolved reference:

```text
parameter binding
local binding
block binding
continuation binding
function binding
region binding
type binding
field binding
```

Expression nodes should refer to binding objects or explicit unresolved symbols, not raw strings.

## 5.6 Sentinel

Sentinels are branded values used for special meanings:

```lua
NIL
AUTO
HOLE
DONE.ast
DONE.bytecode
```

Sentinels are not ordinary tables and must be recognized by brand/metatable, not by string name.

---

# 6. Table Shape Rules

The DSL recognizes table shape.

## 6.1 Array table

An array table has only positive integer keys forming a contiguous sequence from `1` to `n`.

Array entries are ordered.

Use array entries for:

```text
field order
parameter order
statement order
variant order
continuation order
block order
argument order
```

Example:

```lua
{ a[i32], b[i32], c[i32] }
```

## 6.2 Record table

A record table has only string keys.

Record fields are unordered.

Use record fields for:

```text
named jump arguments
continuation fills
attributes
options
metadata
named construction parameters
```

Example:

```lua
jump .loop {
  i   = i + 1,
  acc = acc + xs[i],
}
```

## 6.3 Mixed table

A mixed table has array entries and record fields.

Array entries are ordered semantic children.
Record fields are attributes or options.

Example:

```lua
struct .Vec2 {
  x[f32],
  y[f32],

  packed = true,
}
```

## 6.4 Holes forbidden

Array forms must not contain holes.

Wrong:

```lua
{ a, nil, c }
```

Use `NIL` when a literal nil-like value is intended:

```lua
{ a, NIL, c }
```

## 6.5 Exotic keys

Non-string, non-number keys are reserved for implementation metadata and branded extension keys.

User-level DSL tables should avoid exotic keys unless a specific constructor documents them.

---

# 7. Names and Binding

## 7.1 Name creation

In controlled-environment mode, unknown identifiers become name tokens.

```lua
ret { a + b }
```

Here `a` and `b` are name tokens resolved inside the function body scope.

## 7.2 Declaration scope

Each declaration introduces a scope.

Function scope contains:

```text
function name
parameters
local declarations
block labels
imported module values
visible types/functions/regions
```

Region scope contains:

```text
region name
input parameters
continuations
blocks
locals inside blocks
imported module values
visible types/functions/regions
```

Block scope contains:

```text
block parameters
locals introduced in that block
outer function/region parameters
visible block labels
visible continuations
```

## 7.3 Name resolution

Resolution is role-sensitive.

In expression position:

```lua
a + b
```

`a` and `b` resolve to parameter/local/global bindings.

In jump target position:

```lua
jump .loop { i = i + 1 }
```

`loop` resolves to a block or continuation target depending on the enclosing control context.

In type position:

```lua
x[User]
```

`User` must be a type value.

## 7.4 Unresolved names

Unresolved names are allowed during construction but rejected during validation.

Diagnostics must include:

```text
unresolved name
source location
expected role
available nearby bindings
suggestions when possible
```

Example diagnostic:

```text
error: unresolved expression name 'acount'
  in function sum, body block loop
  did you mean 'acc'?
```

## 7.5 Shadowing

Local declarations may shadow outer bindings only when the constructor explicitly allows it.

Recommended default:

```text
parameters may not shadow parameters
block parameters may not shadow function parameters unless explicit
locals may not shadow locals in the same block
module declarations may not silently replace prior declarations
```

A future `shadow` modifier may permit intentional shadowing.

---

# 8. Types

## 8.1 Scalar types

The DSL provides scalar type values:

```lua
void
bool

i8
i16
i32
i64

u8
u16
u32
u64

f32
f64

index
```

`void` is valid only as a function result type or explicit void marker.

## 8.2 Type application with brackets

Type constructors use bracket syntax:

```lua
ptr[u8]
view[i32]
array[i32][16]
func_type[{ i32, i32 }][i32]
closure_type[{ i32 }][i32]
```

Recommended aliases:

```lua
fnptr[{ i32, i32 }][i32]
closure[{ i32 }][i32]
```

## 8.3 Access and ownership wrappers

Access wrappers are type constructors:

```lua
ro[T]          -- readonly T
wo[T]          -- writeonly T
noalias[T]
noescape[T]
invalidate[T]
preserve[T]
lease[T]
owned[T]
```

Long-form aliases are also available:

```lua
readonly[T]
writeonly[T]
```

Examples:

```lua
xs[ro[view[i32]]]
dst[wo[ptr[u8]]]
pool[preserve[ptr[VoicePool]]]
session[owned[SessionRef]]
state[lease(pool, ptr[VoiceState])]
```

## 8.4 Lease with origin

Lease may be called when an origin is required:

```lua
lease(pool, ptr[VoiceState])
lease(app, view[u8])
```

This constructs a lease type tied to a specific origin binding or origin fact.

## 8.5 Named types

A struct, union, handle, or imported type declaration is itself a type value.

```lua
local Vec2 =
  struct .Vec2 {
    x[f32],
    y[f32],
  }

fn .length { v[Vec2] } [f32] {
  ...
}
```

## 8.6 Type slots

Square brackets after a declaration head or typed name are type slots.

```lua
x[i32]
fn .add { a[i32], b[i32] } [i32] { ... }
p[ptr[u8]]
as[i32](x)
bitcast[u64](bits)
```

The expression inside `[]` must evaluate to a type value unless the specific constructor documents another static parameter role.

## 8.7 Computed types

Types are Lua values and may be computed:

```lua
local T = i32

fn["id_" .. T.name]
  { x[T] }
  [T]
  {
    ret { x },
  }
```

---

# 9. Products

A product is an ordered list of named typed fields.

Products appear in:

```text
function parameters
region input parameters
struct fields
block parameters
continuation payloads
union variant payloads
named products
```

## 9.1 Product entries

Canonical product entry:

```lua
name[Type]
```

With initializer:

```lua
name[Type](init)
```

Examples:

```lua
{ a[i32], b[i32] }
{ i[index](0), acc[i32](0) }
{ data[ptr[u8]], len[index], stride[index] }
```

## 9.2 Product context inference

The same syntax means different declarations depending on context:

```lua
struct .Point {
  x[f32],
  y[f32],
}
```

`x[f32]` and `y[f32]` are fields.

```lua
fn .add { a[i32], b[i32] } [i32] { ... }
```

`a[i32]` and `b[i32]` are parameters.

```lua
entry .loop { i[index](0), acc[i32](0) } { ... }
```

`i[index](0)` and `acc[i32](0)` are block parameters with initializers.

## 9.3 Product fragments

```lua
local XY = product {
  x[f32],
  y[f32],
}

struct .Point {
  spread(XY),
  z[f32],
}
```

A product fragment may auto-flatten only in a product context.

---

# 10. Protocols and Sums

Protocols and unions are sums of named alternatives.

## 10.1 Named alternative

Canonical form:

```lua
ok { value[i32] }
err { code[i32] }
```

No-payload alternative:

```lua
none
missing
closed
```

## 10.2 Protocol context

In a region declaration:

```lua
region .parse
  { p[ptr[u8]], n[index] }
  {
    ok  { value[i32], next[index] },
    err { pos[index], code[i32] },
  }
  {
    ...
  }
```

`ok` and `err` become continuations.

## 10.3 Union context

In a union declaration:

```lua
union .Result {
  ok  { value[i32] },
  err { code[i32] },
  none,
}
```

`ok`, `err`, and `none` become variants.

## 10.4 Ordering

Alternative order is semantic and must be preserved.

Use array entries, not record fields, for protocol/union alternatives.

Correct:

```lua
{
  ok { value[i32] },
  err { code[i32] },
}
```

Avoid:

```lua
{
  ok = { value = i32 },
  err = { code = i32 },
}
```

The latter may be accepted only as an explicit unordered map form by constructors that do not care about order.

---

# 11. Modules

## 11.1 Module declaration

```lua
return module "Demo" {
  declarations...
}
```

Module name may be literal or computed:

```lua
module[name] {
  ...
}
```

## 11.2 Module body

A module body is an ordered list of declarations.

Allowed entries:

```text
struct
union
handle
extern
fn
region
expr_frag
region_frag
const
module-level aliases
imports
bundles/fragments
```

Record fields in a module body are attributes:

```lua
module "Demo" {
  target = "c",
  visibility = "public",

  fn .add { a[i32], b[i32] } [i32] {
    ret { a + b },
  },
}
```

## 11.3 Returned value

A module expression returns a module host value.

The returned value may be:

```text
compiled
emitted to C
emitted to object/shared artifact
inspected
typechecked
pretty-printed
used as dependency by another module
```

---

# 12. Declarations

## 12.1 Struct

```lua
struct .Name {
  fields...
}
```

Example:

```lua
struct .Vec2 {
  x[f32],
  y[f32],
}
```

Computed name:

```lua
struct["Vec" .. n] {
  spread(fields),
}
```

Attributes:

```lua
struct .Header {
  magic[u32],
  version[u16],

  packed = true,
  align = 4,
}
```

## 12.2 Union

```lua
union .Name {
  variants...
}
```

Example:

```lua
union .Result {
  ok  { value[i32] },
  err { code[i32] },
  none,
}
```

Variant constructor expressions are generated by the declaration value:

```lua
Result.ok(42)
Result.err(7)
Result.none()
```

or by DSL constructor helpers:

```lua
variant(Result.ok, 42)
```

## 12.3 Handle

Canonical handle declaration:

```lua
handle .SessionRef
  [u32]
  {
    invalid = 0,
    target = SessionRecord,
    domain = SessionStore,
  }
```

Equivalent compact form may be accepted:

```lua
handle .SessionRef [u32] {
  invalid = 0,
  target = SessionRecord,
  domain = SessionStore,
}
```

Fields:

| Field     | Meaning                                    |
| --------- | ------------------------------------------ |
| `invalid` | invalid raw representation value           |
| `target`  | logical target product type                |
| `domain`  | owner/store domain type                    |
| `repr`    | representation type, if not given by `[T]` |

## 12.4 Extern

Extern function declaration:

```lua
extern .write
  { fd[i32], buf[ptr[u8]], count[index] }
  [index]
  {
    symbol = "write",
    abi = "c",
  }
```

Void extern:

```lua
extern .trap
  { code[i32] }
  {
    symbol = "moon_trap",
    abi = "c",
  }
```

## 12.5 Function

```lua
fn .name
  { params }
  [result]
  {
    body
  }
```

Example:

```lua
fn .add
  { a[i32], b[i32] }
  [i32]
  {
    ret { a + b },
  }
```

Void function:

```lua
fn .zero
  { dst[ptr[u8]], n[index] }
  {
    ret {},
  }
```

## 12.6 Region

```lua
region .name
  { input_product }
  {
    continuation_protocol
  }
  {
    body
  }
```

Example:

```lua
region .scan_until
  { p[ptr[u8]], n[index], target[i32] }
  {
    hit  { pos[index] },
    miss { pos[index] },
  }
  {
    entry .loop
      { i[index](0) }
      {
        when { i:ge(n) } {
          jump .miss { pos = i },
        },

        when { eq { as[i32](p[i]), target } } {
          jump .hit { pos = i },
        },

        jump .loop {
          i = i + 1,
        },
      },
  }
```

## 12.7 Anonymous declarations

Declarations may be anonymous when assigned to Lua locals or module fields:

```lua
local Add =
  fn
    { a[i32], b[i32] }
    [i32]
    {
      ret { a + b },
    }
```

The implementation may infer a stable internal name from the assignment site when available. Otherwise it must generate a unique internal name.

---

# 13. Statement Bodies

A statement body is an ordered array table of statement values.

Example:

```lua
{
  let .acc [i32] { 0 },

  entry .loop { i[index](0) } {
    when { i:ge(n) } {
      ret { acc },
    },

    jump .loop {
      i   = i + 1,
      acc = acc + xs[i],
    },
  },
}
```

## 13.1 Body entries

Each array entry must be a statement, block declaration, control construct, fragment, or accepted declaration.

Record fields in a body are metadata unless a constructor explicitly accepts them.

## 13.2 Fragments in bodies

```lua
local common = stmts {
  let .x [i32] { 0 },
  let .y [i32] { 1 },
}

fn .f {} [i32] {
  spread(common),
  ret { x + y },
}
```

---

# 14. Statements

## 14.1 Return

```lua
ret { expr }
ret {}
```

`ret {}` is a void return.

## 14.2 Yield

```lua
yield .ok { value = x, next = i }
yield .err { pos = i, code = 1 }
```

Inside regions, `yield` exits through a continuation-like result. If the region uses direct `jump` to named continuations, `yield` may be reserved for expression fragments or explicitly returned region results depending on backend policy.

Canonical region exit uses `jump .continuation`.

## 14.3 Let

```lua
let .x [i32] { 0 }
let .sum [i32] { a + b }
```

`let` introduces an immutable local binding.

## 14.4 Var

```lua
var .i [index] { 0 }
```

`var` introduces a mutable local binding.

## 14.5 Assignment

Lua assignment is host assignment and must not be used for Moonlift object assignment.

Use:

```lua
set .x { value }
```

or:

```lua
set { x, value }
```

Examples:

```lua
set .i { i + 1 }
set { xs[i], value }
```

## 14.6 Store

Memory store:

```lua
store { dst[i], 0 }
store { ptr, value }
```

## 14.7 Load

Explicit load expression:

```lua
load(ptr)
load(ptr, i32)
```

The second form may specify the expected type if not inferable.

## 14.8 Conditional

Use `when` for object-language conditional control:

```lua
when { cond } {
  statements...
}
```

With else:

```lua
when { cond } {
  then_statements...
} {
  else_statements...
}
```

Named form:

```lua
when { cond }
  :then_ {
    ...
  }
  :else_ {
    ...
  }
```

`if` is Lua host-time conditional and must not be confused with object-language conditional construction.

## 14.9 Switch

```lua
switch { value } {
  case .zero { 0 } {
    ret { 0 },
  },

  case .one { 1 } {
    ret { 1 },
  },

  default {
    ret { -1 },
  },
}
```

Variant switch:

```lua
switch { r } {
  case .ok { value } {
    ret { value },
  },

  case .err { code } {
    ret { -code },
  },

  default {
    ret { 0 },
  },
}
```

## 14.10 Block

Entry block:

```lua
entry .loop
  { i[index](0), acc[i32](0) }
  {
    statements...
  }
```

Non-entry block:

```lua
block .done
  { acc[i32] }
  {
    ret { acc },
  }
```

Block parameters are typed name tokens. Initializers are required for `entry` block parameters unless provided by enclosing semantics.

## 14.11 Jump

```lua
jump .loop {
  i   = i + 1,
  acc = acc + xs[i],
}
```

Jump target is explicit.

Named arguments must totally assign the target block or continuation payload. Missing, extra, or wrong-typed arguments are validation errors.

## 14.12 Emit

Region emit:

```lua
emit .scan_until
  { p, n, target }
  {
    hit  = block.found,
    miss = block.missing,
  }
```

If block labels are in scope, direct label values may be accepted:

```lua
emit .scan_until { p, n, target } {
  hit  = found,
  miss = missing,
}
```

The first table is ordered runtime arguments.
The second table is a named continuation-fill map.

## 14.13 Call

Function or expression-style region call:

```lua
call .foo { a, b }
```

For ordinary expression calls, prefer function-call expression syntax if the callee is known:

```lua
foo(a, b)
```

Use `call` when the operation must be represented explicitly as a statement or when the callee is a region/function value requiring DSL dispatch.

## 14.14 Trap and assume

```lua
trap { code }
assume { cond }
```

These lower to Moonlift intrinsics or control constructs depending on target semantics.

---

# 15. Expressions

## 15.1 Expression lifting

In expression position, Lua values are lifted:

| Lua value         | Moonlift expression                                      |
| ----------------- | -------------------------------------------------------- |
| number            | integer or float literal, inferred later                 |
| string            | runtime string literal unless context says name/raw text |
| boolean           | bool literal                                             |
| name token        | binding reference or unresolved symbol                   |
| typed binding     | binding reference                                        |
| expression object | itself                                                   |
| function value    | function reference, if typed                             |
| declaration value | declaration reference, if valid in expression position   |

## 15.2 Arithmetic operators

Supported expression operators:

```lua
a + b
a - b
a * b
a / b
a % b
-a
a ^ b
```

These construct expression trees, not host computations, when either operand is an expression-like DSL value.

## 15.3 Bitwise operators

If the host Lua version supports bitwise operators, the DSL may overload:

```lua
a & b
a | b
a ~ b
~a
a << b
a >> b
```

In LuaJIT / Lua 5.1 mode, use explicit constructors or the `bit` module wrapper because native bitwise syntax is not standard there.

Canonical portable forms:

```lua
band { a, b }
bor  { a, b }
bxor { a, b }
bnot { a }
shl  { a, n }
shr  { a, n }
```

## 15.4 Comparisons

Lua comparison operators return host booleans and must not be the canonical expression comparison syntax.

Do not rely on:

```lua
i >= n
x == y
```

Use method or constructor forms:

```lua
i:ge(n)
i:gt(n)
i:le(n)
i:lt(n)
x:eq(y)
x:ne(y)

ge { i, n }
lt { i, n }
eq { x, y }
ne { x, y }
```

## 15.5 Boolean expressions

Lua `and`, `or`, and `not` cannot be overloaded.

Use:

```lua
And { a, b }
Or  { a, b }
Not { a }
```

or method forms:

```lua
a:land(b)
a:lor(b)
a:lnot()
```

## 15.6 Indexing

```lua
xs[i]
p[i]
```

Indexing constructs a Moonlift index/place expression when the receiver is expression-like.

## 15.7 Field access

```lua
user.id
point.x
```

In expression position, ordinary dot access constructs a field access expression when the receiver is expression-like.

Grammar paths use spaced-dot style:

```lua
fn .add
jump .loop
```

Expression field access uses normal style:

```lua
user.id
```

## 15.8 Calls

```lua
foo(a, b)
```

Constructs a function-call expression if `foo` is a Moonlift callable binding or function value.

For intrinsic calls:

```lua
len(xs)
sizeof[T]()
alignof[T]()
as[i32](x)
bitcast[u64](bits)
is_null(p)
null[ptr[u8]]
```

## 15.9 Casts

Semantic conversion:

```lua
as[i32](x)
as[f64](x)
```

Representation reinterpretation:

```lua
bitcast[u64](bits)
bitcast[f64](raw)
```

## 15.10 Address and dereference

Portable constructor forms:

```lua
addr(place)
deref(ptr)
load(ptr)
```

Optional method forms:

```lua
place:addr()
ptr:deref()
ptr:load()
```

Because Lua does not have overloadable prefix `&` or `*`, symbolic forms are canonical.

---

# 16. Control Regions

## 16.1 Region meaning

A region is a typed control fragment:

```text
input product -> named continuation protocol
```

It contains blocks and jumps. Every path must explicitly terminate by jumping to a block/continuation, returning, yielding, trapping, or emitting into a filled continuation.

## 16.2 Region header

```lua
region .name
  { input_product }
  {
    continuation_protocol
  }
  {
    region_body
  }
```

## 16.3 Continuations

Continuation alternatives use named payload forms:

```lua
{
  ok { value[i32], next[index] },
  err { pos[index], code[i32] },
}
```

No-payload continuation:

```lua
{
  done,
  failed { code[i32] },
}
```

## 16.4 Blocks

Every region must contain exactly one entry block unless an explicit region body form states otherwise.

```lua
entry .start {} {
  ...
}
```

Non-entry blocks are declared with `block`.

```lua
block .again { i[index] } {
  ...
}
```

## 16.5 Jumps

A jump is a typed state transition.

```lua
jump .again {
  i = i + 1,
}
```

The target’s payload/product must be fully assigned.

## 16.6 Emits

An emit splices a sub-region into the current region.

```lua
emit .parse_number { p, n, i } {
  ok  = number_ok,
  err = parse_err,
}
```

Emit fill names must cover every declared continuation of the emitted region unless a partial-fill form is explicitly used.

## 16.7 Region fragments

A region fragment is a reusable typed control component.

```lua
local scan =
  region_frag .scan
    { p[ptr[u8]], n[index] }
    {
      ok { pos[index] },
      miss,
    }
```

A fragment may be emitted from multiple regions.

---

# 17. Functions

## 17.1 Function meaning

A function is a sealed region with an ABI boundary and one return continuation.

## 17.2 Function declaration

```lua
fn .name
  { params }
  [result]
  {
    body
  }
```

Void function:

```lua
fn .name
  { params }
  {
    body
  }
```

## 17.3 Function calls

Expression call:

```lua
f(a, b)
```

Statement call:

```lua
call .f { a, b }
```

Indirect call:

```lua
call_fp(fp, x)
```

## 17.4 Function references

Named functions are Lua host values and can be passed to constructors:

```lua
local Add =
  fn .add { a[i32], b[i32] } [i32] {
    ret { a + b },
  }

local Use =
  fn .use { x[i32], y[i32] } [i32] {
    ret { Add(x, y) },
  }
```

---

# 18. Memory, Ownership, and Access

## 18.1 Pointers

Pointer type:

```lua
ptr[T]
```

Load:

```lua
load(p)
deref(p)
```

Store:

```lua
store { p, value }
store { xs[i], value }
```

Pointer arithmetic:

```lua
p + offset
```

## 18.2 Views

View type:

```lua
view[T]
ro[view[T]]
```

View operations:

```lua
len(xs)
xs[i]
```

## 18.3 Access facts

Access facts are type wrappers:

```lua
ro[ptr[T]]
wo[ptr[T]]
noalias[ptr[T]]
noescape[ptr[T]]
invalidate[ptr[T]]
preserve[ptr[T]]
```

## 18.4 Leases

Temporary access:

```lua
lease[ptr[T]]
lease(origin, ptr[T])
lease(pool, view[T])
```

Lease values may not escape the dynamic extent that granted them unless an explicit typed protocol carries them.

## 18.5 Owned values

Ownership obligation type:

```lua
owned[T]
```

Owned values must be consumed, transferred, yielded, or returned exactly once according to typed control flow.

No implicit destructors are assumed.

---

# 19. Splicing, Spread, and Generation

## 19.1 No antiquote in pure Lua DSL

There is no `@{x}` in this surface.

Old quoted-source style:

```lua
moon.stmts { T = i32 } [[ let x: @{T} = 0 ]]
```

Pure Lua DSL:

```lua
let .x [T] { 0 }
```

## 19.2 Direct insertion

Because the authoring language is Lua, Lua values are passed directly:

```lua
local T = i32
local name = "id_i32"

fn[name]
  { x[T] }
  [T]
  {
    ret { x },
  }
```

## 19.3 Spread

Lua has no built-in table spread syntax. Use:

```lua
spread(xs)
```

Example:

```lua
local params = product {
  a[i32],
  b[i32],
}

fn .add
  { spread(params) }
  [i32]
  {
    ret { a + b },
  }
```

## 19.4 Role-aware auto-flattening

A context may auto-flatten branded fragments of the expected role:

```lua
fn .add
  { params }
  [i32]
  {
    body,
  }
```

This is accepted only if `params` is a product fragment and `body` is a statement fragment.

## 19.5 Generated names

Use bracket name slots:

```lua
fn["add_" .. T.name]
  { a[T], b[T] }
  [T]
  {
    ret { a + b },
  }
```

Generated fields:

```lua
local fields = {}

for i = 1, N do
  fields[#fields + 1] = N["x" .. i][i32]
end

struct["Pack" .. N] {
  spread(fields),
}
```

`N[...]` constructs a computed name token.

---

# 20. Name Slots

## 20.1 Dot name

Use dot name for fixed simple identifiers:

```lua
fn .add
struct .Vec2
jump .loop
```

## 20.2 Bracket name

Use bracket name for computed or unusual names:

```lua
fn[name]
struct["Vec" .. n]
fn["operator+"]
region["parse-number"]
```

## 20.3 Name token namespace

When a computed name token is needed inside a table entry:

```lua
N["x" .. i][T]
```

`N[...]` returns a name token, which can then be typed, called, or used as a symbolic name.

---

# 21. Contextual Inference

## 21.1 Inference table

| Context              | Input form           | Meaning                          |
| -------------------- | -------------------- | -------------------------------- |
| function params      | `a[T]`               | function parameter               |
| region input         | `a[T]`               | region input parameter           |
| struct body          | `x[T]`               | struct field                     |
| block params         | `i[T](init)`         | block parameter with initializer |
| continuation payload | `value[T]`           | payload field                    |
| union payload        | `value[T]`           | variant payload field            |
| protocol body        | `ok { ... }`         | continuation declaration         |
| union body           | `ok { ... }`         | variant declaration              |
| union/protocol body  | `none`               | no-payload alternative           |
| statement body       | `ret { x }`          | return statement                 |
| statement body       | `jump .loop { ... }` | jump statement                   |
| expression position  | `a`                  | binding reference                |
| type slot            | `[T]`                | type annotation                  |
| name slot            | `.foo` / `[name]`    | declaration/control name         |

## 21.2 Rejected inference

Control edges are not inferred from bare named payloads.

Wrong:

```lua
loop { i = i + 1 }
```

Use:

```lua
jump .loop { i = i + 1 }
```

Wrong:

```lua
scan_until { p, n, target } { hit = found }
```

Use:

```lua
emit .scan_until { p, n, target } { hit = found }
```

## 21.3 Principle

```text
Infer repeated declaration shape.
Do not infer control effects.
```

---

# 22. Diagnostics

## 22.1 Source locations

Every DSL constructor should capture source location when practical.

Source locations must be attached to:

```text
declarations
fields
parameters
statements
expressions
blocks
jumps
emits
continuation fills
generated fragments where possible
```

## 22.2 Shape errors

Example:

```lua
struct .Bad {
  ok { x[i32] },
}
```

Diagnostic:

```text
error: struct body expects field entries like x[i32]
  got named payload ok { ... }
```

## 22.3 Role errors

Example:

```lua
fn .f { a[i32] } [i32] {
  spread(fields),
}
```

Diagnostic:

```text
error: expected statement fragment in function body
  got field/product fragment
```

## 22.4 Binding errors

Example:

```lua
ret { acount + 1 }
```

Diagnostic:

```text
error: unresolved expression name 'acount'
  did you mean 'acc'?
```

## 22.5 Control errors

Examples:

```text
missing jump argument
extra jump argument
jump target not found
continuation fill missing
block without terminating control edge
duplicate block label
duplicate continuation
emit continuation not filled
```

## 22.6 Type errors

Examples:

```text
wrong argument type
invalid cast
invalid store
use of void value
owned value dropped
lease escapes
access invalidated while lease live
```

---

# 23. Reflection and Debugging

## 23.1 tostring

Every DSL object should implement useful string rendering.

Examples:

```lua
tostring(i32)
-- "i32"

tostring(ptr[u8])
-- "ptr[u8]"

tostring(a + b)
-- "add(a, b)"

tostring(fn_value)
-- "fn Demo.add(a: i32, b: i32): i32"
```

## 23.2 pairs

Semantic objects may implement `pairs`.

```lua
for name, field in pairs(Vec2) do
  print(name, field.type)
end
```

For ordered declarations, `pairs` must use stable declaration order if exposed.

## 23.3 length

`#` may expose static facts:

```lua
#params     -- number of entries
#body       -- number of statements
#stream     -- number of ops
#type       -- layout size, if known and documented
```

`#type` must not silently trigger target-dependent layout unless the type has been layout-resolved.

---

# 24. Strictness and Safety

## 24.1 Strict environment

The controlled environment must support strict mode.

In strict mode:

```text
unknown names become unresolved symbols only in expression/declaration contexts
accidental host global reads are rejected
accidental host global writes are rejected
typos produce diagnostics
```

## 24.2 Escape hatches

Escape hatches must be visually explicit.

Examples:

```lua
raw_asdl(value)
raw_c [[ ... ]]
unsafe {
  ...
}
```

## 24.3 Host-time branching

Lua `if`, `for`, and `while` are host-time constructs.

Example:

```lua
local body = {}

for i = 1, N do
  body[#body + 1] = call .step { i }
end
```

This generates Moonlift statements.

Object-time branching uses `when` or `switch`.

## 24.4 Host-time variables

Lua locals are host variables.

Moonlift locals are created with `let` or `var`.

Do not confuse:

```lua
local x = 1        -- Lua host variable
let .x [i32] { 1 } -- Moonlift local binding
```

---

# 25. Canonical Examples

## 25.1 Simple add

```lua
return module "Demo" {
  fn .add
    { a[i32], b[i32] }
    [i32]
    {
      ret { a + b },
    },
}
```

## 25.2 Struct and function

```lua
return module "Geometry" {
  struct .Vec2 {
    x[f32],
    y[f32],
  },

  fn .dot
    { a[Vec2], b[Vec2] }
    [f32]
    {
      ret { a.x * b.x + a.y * b.y },
    },
}
```

## 25.3 Loop with block/jump

```lua
return module "Demo" {
  fn .sum
    { xs[ro[view[i32]]] }
    [i32]
    {
      entry .loop
        { i[index](0), acc[i32](0) }
        {
          when { i:ge(len(xs)) } {
            ret { acc },
          },

          jump .loop {
            i   = i + 1,
            acc = acc + xs[i],
          },
        },
    },
}
```

## 25.4 Region with protocol

```lua
return module "Scan" {
  region .scan_until
    { p[ptr[u8]], n[index], target[i32] }
    {
      hit  { pos[index] },
      miss { pos[index] },
    }
    {
      entry .loop
        { i[index](0) }
        {
          when { i:ge(n) } {
            jump .miss { pos = i },
          },

          when { eq { as[i32](p[i]), target } } {
            jump .hit { pos = i },
          },

          jump .loop {
            i = i + 1,
          },
        },
    },
}
```

## 25.5 Generated vector family

```lua
local function make_vec(n, T)
  local fields = {}

  for i = 1, n do
    fields[#fields + 1] = N["x" .. i][T]
  end

  return struct["Vec" .. n] {
    spread(fields),
  }
end

return module "Vectors" {
  make_vec(2, f32),
  make_vec(3, f32),
  make_vec(4, f32),
}
```

## 25.6 Generated identity functions

```lua
local function make_id(T)
  local name = "id_" .. T.name

  return fn[name]
    { x[T] }
    [T]
    {
      ret { x },
    }
end

return module "Ids" {
  make_id(i32),
  make_id(f32),
  make_id(u64),
}
```

## 25.7 Union and switch

```lua
return module "Results" {
  union .Result {
    ok  { value[i32] },
    err { code[i32] },
  },

  fn .unwrap_or_zero
    { r[Result] }
    [i32]
    {
      switch { r } {
        case .ok { value } {
          ret { value },
        },

        case .err { code } {
          ret { 0 },
        },

        default {
          ret { 0 },
        },
      },
    },
}
```

---

# 26. Implementation Sketch

## 26.1 Object roles

Recommended metatable roles:

```text
Env             unknown name creation, declaration capture
NameToken       __index, __call, __newindex?, __tostring
TypedName       __call for initializer
DeclarationHead __index / __call / __newindex for staged declarations
Type            __index / __call / __tostring
Expr            arithmetic operators, indexing, calls, tostring
Stmt            statement value
BlockHead       staged block creation
JumpHead        target selection
EmitHead        target selection and staged fills
Fragment        __concat, __len, __call, spread support
Module          emit/compile/reflection methods
Diagnostic      structured errors
```

## 26.2 Neutral syntax nodes

The parser layer should first produce neutral syntax nodes:

```text
Name("x")
TypedName("x", T)
TypedNameInit("x", T, init)
NamedPayload("ok", product)
ProductFragment([...])
ProtocolFragment([...])
StmtFragment([...])
ExprNode(...)
```

Then context normalizers consume them.

## 26.3 Context normalizers

Required normalizers:

```text
normalize_module_body
normalize_struct_body
normalize_union_body
normalize_product
normalize_protocol
normalize_params
normalize_block_params
normalize_stmt_body
normalize_stmt
normalize_expr
normalize_type
normalize_name_slot
normalize_jump_args
normalize_emit_fills
```

Each normalizer must reject valid-looking values that are invalid in that role.

## 26.4 ASDL emission

After normalization, each declaration emits canonical Moonlift ASDL:

```text
TypeDeclStruct
TypeDeclUnion
TypeDeclHandle
ExternDecl
FuncDecl
RegionDecl
BlockDecl
StmtReturn
StmtJump
StmtEmit
ExprAdd
ExprCall
ExprLoad
...
```

No backend should need to inspect Lua tables directly after ASDL emission.

---

# 27. Migration from Existing `.mlua`

## 27.1 Existing source-island style

Existing style:

```lua
local T = moon.i32

return func @{name}(x: @{T}): @{T}
  return x
end
```

New style:

```lua
return fn[name]
  { x[T] }
  [T]
  {
    ret { x },
  }
```

## 27.2 Existing spread

Existing style:

```moonlift
func make_pack(@{params...}): Pack
  @{body...}
end
```

New style:

```lua
fn .make_pack
  { spread(params) }
  [Pack]
  {
    spread(body),
  }
```

## 27.3 Existing table builders

Existing table-builder values can be adapted into branded fragments:

```lua
local params = from_legacy_params(old_params)
local body = from_legacy_stmts(old_body)
```

Then:

```lua
fn .f { params } [i32] { body }
```

---

# 28. Summary Card

```text
Lua-owned Moonlift DSL:

.     fixed DSL token
[]    inserted value / type / computed name
{}    product / protocol / body / payload / argument map
()    ordinary call / initializer / finalizer

a[T]          typed name token
a[T](init)    typed name token with initializer
ok { ... }    named payload
none          no-payload alternative in protocol/union context

fn .name { params } [result] { body }
struct .Name { fields }
union .Name { variants }
region .name { input } { protocol } { body }

Infer declaration roles.
Spell control effects.

Use:
  jump .target { named_args }
  emit .region { args } { fills }
  ret { expr }
  when { cond } { body }

Do not use:
  source strings for semantics
  @{} in pure Lua DSL
  Lua assignment for Moonlift assignment
  Lua if for object-time control
  Lua comparisons for expression comparisons

Everything lowers to explicit ASDL.
```

---

# 29. Final Doctrine

This DSL is not a prettier constructor library.

It is a Lua grammar of values whose shapes mirror Moonlift’s algebra:

```text
product positions accept product shapes
sum/protocol positions accept named alternatives
control positions accept explicit control statements
expression positions accept expression values
type slots accept type values
name slots accept literal or computed names
```

The surface is poetic because Lua is doing the parsing.

The machine remains inspectable because Moonlift receives explicit ASDL.
