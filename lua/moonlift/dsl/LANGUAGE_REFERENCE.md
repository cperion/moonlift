# Moonlift Lua-Owned DSL Language Reference

## Status

This document describes the Lua-owned Moonlift DSL implemented by
`require("moonlift.dsl")`.

The DSL is ordinary Lua. Lua performs the mechanical parse, evaluates host-time
expressions, and hands real Lua values to Moonlift DSL objects. The DSL then
normalizes those values by role and emits explicit `MoonSyntax`, `MoonTree`,
and `MoonOpen` ASDL.

There is no second source parser in the normal authoring path.

```text
Lua syntax -> Lua values -> DSL role normalization -> Moonlift ASDL
```

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

## Design Rule

Moonlift structure uses `{}`.

Lua computation and language leaves use `()` only when ordinary Lua syntax
requires or benefits from it.

Canonical examples:

```lua
fn .add
  { a [i32], b [i32] }
  [i32]
  {
    ret { a + b },
  }
```

```lua
region .scan
  { p [ptr [u8]], n [index], target [i32] }
  {
    hit  { pos [index] },
    miss,
  }
  {
    entry .loop { i [index](0) } {
      when { i:ge(n) } {
        jump .miss { pos = i },
      },

      jump .loop {
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

```lua
local dsl = require("moonlift.dsl")

local chunk = dsl.loadfile("demo.mld.lua")
local module = chunk()

local tree_module = module:ast()
local checked = module:typecheck()
local lowered = module:lower()
```

String loading:

```lua
local chunk = dsl.loadstring([[
return module "Demo" {
  fn .id { x [i32] } [i32] {
    ret { x },
  },
}
]], "demo")
```

Strict global mode:

```lua
local chunk = dsl.loadstring(src, "demo", { strict = true })
```

In strict mode, assignment to a previously unknown global is rejected.

## Modules

```lua
return module "Demo" {
  declarations...
}
```

Module bodies are ordered declaration arrays. Record fields are reserved for
attributes/options where a constructor documents them.

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
spread(decls_fragment)
```

In this Lua-owned DSL, module composition is done by Lua `require` and value
splicing (`[]` / `spread(...)`), not by a DSL `import` declaration.

### Header-style module pattern

Because declaration arrays are first-class Lua tables, split header-style DSL
composition into two files naturally:

```lua
-- types_decl.lua
local dsl = require("moonlift.dsl")
return dsl.loadstring([[
return {
  struct .Point { x [f32], y [f32] },
  union .Result {
    ok { value[i32] },
    err { code[i32] },
  },
  const .Magic [u8] { 0x80 },
}
]], "types_decl")()
```

```lua
-- demo/ops.mld.lua
local header = require("types_decl")
local dsl = require("moonlift.dsl")

return module "DemoOps" {
  spread(header),

  fn .read { p [ptr [u8]], n [i32] } [i32] {
    entry .start {} {
      jump .done { x = as [i32] (n) },
    },

    block .done { x [i32] } {
      ret { x },
    },
  },
}
```

The key difference is: required values enter through normal Lua
`require` + `[]`/`spread` flow, not textual import directives.

This keeps contracts (`struct`, `union`, `handle`, signatures, `const`) in one
declaration unit and runtime behavior (regions/functions) in another, while
staying entirely in Lua data and values with no textual antiquote layer.

## Names

Fixed names use spaced-dot grammar:

```lua
fn .add
struct .Vec2
region .scan
jump .loop
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
ret { acc + x }
```

Here `acc` and `x` are name tokens resolved later by Moonlift semantic phases.

For generated names inside arrays, use `N`:

```lua
local fields = {}
for i = 1, 4 do
  fields[#fields + 1] = N["x" .. i] [f32]
end

struct .Vec4 {
  spread(fields),
}
```

### Grepability

With dotted declaration names, grep can index DSL structure directly:

```text
# Declaration headers
rg '^\s*(fn|export_fn|struct|union|handle|extern|const|static|expr_frag|region)\s+\.[A-Za-z_][A-Za-z0-9_]*' path/to/dsl/*.md

# CFG structure (entry/block labels, jumps, emits)
rg '\b(entry|block|jump|emit)\s+\.[A-Za-z_][A-Za-z0-9_]*' path/to/*.mlua path/to/*.lua

# Dot-name declarations in the DSL test corpus
rg '^\s*(fn|export_fn|struct|union|handle|extern|const|static|expr_frag|region|entry|block|jump|emit)\s+\.[A-Za-z_][A-Za-z0-9_]*' tests/frontend/test_dsl_lua_owned.lua
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
entry .loop { i [index](0), acc [i32](0) } {
  ...
}
```

## Structs

```lua
struct .Vec2 {
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

struct .Point {
  spread(xy),
  z [f32],
}
```

## Unions

```lua
union .Result {
  ok  { value [i32] },
  err { code [i32] },
  none,
}
```

Union alternatives are ordered array entries. Payload alternatives use named
payload table syntax. No-payload alternatives use bare name tokens.

## Handles

```lua
handle .SessionRef {
  invalid = 0,
}
```

With optional facts:

```lua
handle .SessionRef {
  invalid = 0,
  domain = "SessionStore",
  target = "SessionRecord",
}
```

## Externs

```lua
extern .write
  { fd [i32], buf [ptr [u8]], count [index] }
  [index]
  {
    symbol = "write",
  }
```

Void extern:

```lua
extern .trap
  { code [i32] }
  {
    symbol = "moon_trap",
  }
```

## Constants And Statics

```lua
const .answer [i32] { 42 }
static .zero [i32] { 0 }
```

The type slot receives the actual Lua value `i32`.

## Functions

```lua
fn .add
  { a [i32], b [i32] }
  [i32]
  {
    ret { a + b },
  }
```

Exported function:

```lua
export_fn .add
  { a [i32], b [i32] }
  [i32]
  {
    ret { a + b },
  }
```

Void function:

```lua
fn .touch
  { x [i32] }
  {
    ret {},
  }
```

A function body may be a plain statement list or a control-region body with
`entry` and `block` declarations:

```lua
fn .sum
  { n [i32] }
  [i32]
  {
    entry .loop { i [i32](0), acc [i32](0) } {
      when { i:ge(n) } {
        ret { acc },
      },

      jump .loop {
        i = i + 1,
        acc = acc + i,
      },
    },
  }
```

## Statements

Return:

```lua
ret { value }
ret {}
```

Yield:

```lua
yield { value }
yield {}
```

Local values:

```lua
let .x [i32] { 1 }
var .i [index] { 0 }
```

Assignment:

```lua
store { dst[i], value }
set { dst[i], value }
```

Conditional:

```lua
when { cond } {
  body...
}
```

Jump:

```lua
jump .loop {
  i = i + 1,
  acc = acc + x,
}
```

Trap and assumptions:

```lua
trap()
assume { cond }
assert_ { cond }
```

## Switch

Literal cases:

```lua
switch { x } {
  case_value(0) {
    ret { 1 },
  },

  default {
    ret { 2 },
  },
}
```

Variant-oriented cases use name-token cases:

```lua
switch { r } {
  case .ok { value } {
    ret { value },
  },

  default {
    ret { 0 },
  },
}
```

## Regions

Regions are named control fragments:

```lua
region .scan
  { p [ptr [u8]], n [index], target [i32] }
  {
    hit  { pos [index] },
    miss,
  }
  {
    entry .loop { i [index](0) } {
      when { i:ge(n) } {
        jump .miss { pos = i },
      },

      jump .loop {
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
emit .scan { p, n, target } {
  hit  = found,
  miss = failed,
}
```

Continuation fill maps are record tables. Fill values are block labels/name
tokens.

Example:

```lua
fn .find
  { p [ptr [u8]], n [index] }
  [i32]
  {
    entry .start {} {
      emit .scan { p, n, 65 } {
        hit  = done,
        miss = done,
      },
    },

    block .done { pos [i32] } {
      ret { pos },
    },
  }
```

## Expression Fragments

Expression fragments are reusable typed expression components:

```lua
expr_frag .inc
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
true
"bytes"
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
be overloaded into expression trees:

```lua
i:ge(n)
i:lt(n)
eq { a, b }
ne { a, b }
```

Boolean logic uses constructors because Lua `and`, `or`, and `not` cannot be
overloaded:

```lua
And { a, b }
Or  { a, b }
Not { a }
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

## Fragments And Spread

Lua has no spread syntax, so the DSL uses `spread(value)`.

Product fragment:

```lua
local xy = product {
  x [f32],
  y [f32],
}

struct .Vec2 {
  spread(xy),
}
```

Statement fragment:

```lua
local done = stmts {
  ret { 0 },
}

fn .f {} [i32] {
  spread(done),
}
```

Declaration fragment:

```lua
local decls = decls {
  struct .A { x [i32] },
  struct .B { y [i32] },
}

return module "M" {
  spread(decls),
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
    spread(fields),
  }
end

return module "Vectors" {
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
struct .ViewU8 {
  spread(view_params),
}

fn .first
  { spread(view_params) }
  [u8]
  {
    ret { data[0] },
  }
```

You can slice statement bodies:

```lua
local bounds_check = stmts {
  when { i:ge(len) } {
    trap(),
  },
}

fn .get
  { data [ptr [u8]], len [index], i [index] }
  [u8]
  {
    spread(bounds_check),
    ret { data[i] },
  }
```

You can slice control protocols:

```lua
local hit_miss = {
    hit  { pos [index] },
  miss,
}

region .scan_a
  { p [ptr [u8]], n [index] }
  { spread(hit_miss) }
  {
    entry .start {} {
      jump .miss {},
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

DSL module/declaration values expose:

```lua
value:syntax()          -- MoonSyntax module for modules
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
return module "Name" {
  struct .Name {
    field [T],
  },

  union .Name {
    variant { payload [T] },
    none,
  },

  fn .name
    { param [T] }
    [Result]
    {
      ret { expr },
    },

  region .name
    { input [T] }
    {
      ok { value [T] },
      err,
    }
    {
      entry .start {} {
        jump .ok { value = input },
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
