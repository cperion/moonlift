# Moonlift Lua-Owned DSL Language Reference

## Status

This document describes the Lua-owned Moonlift DSL implemented by
`require("moonlift.dsl")`.

The DSL is ordinary Lua. Lua performs the mechanical parse, evaluates host-time
expressions, and hands real Lua values to Moonlift DSL objects. Declaration and
control heads are hosted by `lua/llb.lua`; the Moonlift DSL grammar then
normalizes those values by role and emits explicit `MoonTree` and `MoonOpen`
ASDL.

There is no second source parser in the normal authoring path.
This is the recommended path for new generated/metaprogrammed Moonlift code.

```text
Lua syntax -> Lua values -> LLB role normalization -> Moonlift ASDL
```

For declaration/control heads, keep dotted names (`fn .add`, `region .scan`, etc.)
with a space before the name target:

```text
fn .add
region .scan
jump .done
emit .scan
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
| ret / yield | `ret (expr)` | `ret(expr)` |
| when | `when (cond) { ... }` | `when(cond){...}` |
| let / var | `let .x [i32] { 0 }` | `let.x[i32]{0}` |
| store / set | `store (place, value)` | `store(place,value)` |
| jump | `jump .loop { i = i + 1 }` | `jump.loop{i=i+1}` |
| emit | `emit .scan { args } { fills }` | `emit.scan{args}{fills}` |
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
fn .add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
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
      when (i:ge(n)) {
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

### Quick: `moon.use()` for plain `.lua` files

The simplest way to author Moonlift is to call `require("moonlift").use()` at
the top of any `.lua` file. This injects all DSL names (`fn`, `i32`, `module`,
`struct`, `region`, etc.) as Lua globals:

```lua
-- my_module.lua
local moon = require("moonlift")
moon.use()

return module "Demo" {
  fn .add { a [i32], b [i32] } [i32] { ret (a + b) },
}
```

For headers split across files, call `moon.use()` at the top of each `.lua`
file:

```lua
-- math_header.lua
require("moonlift").use()
return { fn .add { a [i32], b [i32] } [i32] }

-- math_impl.lua
require("moonlift").use()
local header = require("math_header")
return module "Math" { header[1] { ret (a + b) } }
```

### `dsl.loadstring()` — inline, isolated env

For programmatic use, `dsl.loadstring()` creates an isolated environment without
touching `_G`:

```lua
local dsl = require("moonlift.dsl")

-- One-shot: compile and execute
local module = dsl.load([[return module "Demo" { ... }]], "demo.lua")

-- From a file
local chunk = dsl.loadfile("demo.lua")
local module = chunk()

-- Module require: finds name.lua or name/init.lua, caches result
local header = dsl.require("math_header")

-- Full pipeline
module:ast()
module:typecheck()
module:lower()
module:compile()
module:emit_c_artifact()
```

### Package searcher integration

Once loaded, the DSL auto-installs a Lua `package.searchers` entry so
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
  fn .add { a [i32], b [i32] } [i32],
  fn .sub { a [i32], b [i32] } [i32],
}

-- math_impl.lua
local header = require("math_header")
return module "Math" {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
```

Strict global mode:

```lua
dsl.loadstring(src, "demo", { strict = true })
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

### Header / implementation split

The DSL's `fn` and `region` declaration chains are **curried**: supplying
params and result does not create the final declaration. It returns a
**callable LLB stage** waiting for the body. This is the header.

```lua
fn .add { a [i32], b [i32] } [i32]
```

The line above does not produce a final declaration. It produces a callable Lua
stage table.
Call it with a body table to produce the full declaration:

```lua
fn .add { a [i32], b [i32] } [i32] {
  ret (a + b),
}
```

This means headers and implementations can live in separate files:

```lua
-- math_header.lua
return {
  fn .add { a [i32], b [i32] } [i32],
  fn .sub { a [i32], b [i32] } [i32],
}
```

```lua
-- math_impl.lua
local header = require("math_header")
return module "Math" {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
```

The same pattern works for regions:

```lua
-- io_header.lua
return {
  region .read { fd [i32], buf [ptr [u8]], count [index] } { ok{n[index]}, err{code[i32]} },
  region .write { fd [i32], buf [ptr [u8]], count [index] } { ok{n[index]}, err{code[i32]} },
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
ret (acc + x)
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
    ret (a + b),
  }
```

Exported function:

```lua
export_fn .add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
  }
```

Void function:

```lua
fn .touch
  { x [i32] }
  {
    ret (),
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
      when (i:ge(n)) {
        ret (acc),
      },

      jump .loop {
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
fn .read
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
let .x [i32] { 1 }
var .i [index] { 0 }
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
jump .loop {
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
  case .ok { value } {
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
region .scan
  { p [ptr [u8]], n [index], target [i32] }
  {
    hit  { pos [index] },
    miss,
  }
  {
    entry .loop { i [index](0) } {
      when (i:ge(n)) {
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
      ret (pos),
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
  const .greeting [ptr [u8]] "hello, moonlift"
  const .nums [array [i32] [3]] { 1, 2, 3 }
  ret "done"
  ret { 1, 2, 3 }
```

Other literals (`1`, `true`, `nil`) are written with parentheses: `ret (1)`,
`ret (true)`, `ret (nil)`.
`ret` / `yield` scalar expressions follow the same rule.

Returning function values is supported only via references or splice-built
expressions (not inline Lua function syntax). For example:

```lua
fn .foo { x [i32] } [i32] { ret (x) },
fn .mk {} [fnptr[{ i32 }] [i32]] { ret (foo) },
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
be overloaded into expression trees:

```lua
i:ge(n)
i:lt(n)
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
  ret (0),
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
    ret (data[0]),
  }
```

You can slice statement bodies:

```lua
local bounds_check = stmts {
  when (i:ge(len)) {
    trap (),
  },
}

fn .get
  { data [ptr [u8]], len [index], i [index] }
  [u8]
  {
    spread(bounds_check),
    ret (data[i]),
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
value:syntax()          -- MoonTree module for modules
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
      requires {
        bounds(param, N.n),
      },
      ret (expr),
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
