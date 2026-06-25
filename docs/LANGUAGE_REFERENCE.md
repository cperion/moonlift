# Lalin Language Reference

This is the public reference for the Lalin family exposed by:

```lua
local lalin = require("lalin")
```

Lalin source is ordinary Lua shaped by LLB. Lua parses and evaluates the file.
LLB captures the resulting values through staged heads, typed slots, fragments,
namespaces, origins, diagnostics, and generic regions. Lalin is the compiled
family member that normalizes those values into explicit ASDL.

## Loading

Use a managed family environment for normal authoring files:

```lua
local lalin = require("lalin")
lalin.family.use()

return {
  ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
    ll.ret (a + b),
  },
}
```

For isolated loading:

```lua
local lalin = require("lalin")

local unit = lalin.loadstring([[
  return {
    ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
      ll.ret (a + b),
    },
  }
]], "demo.lua")()
```

The main entry points are:

```lua
lalin.loadstring(src [, name])
lalin.loadfile(path)
lalin.dofile(path, ...)
lalin.eval(src [, name], ...)
lalin.compile(name_or_decls [, decls_or_opts [, opts]])
lalin.emit_luajit_artifact(decl [, opts])
lalin.emit_c_artifact(decl [, opts])
lalin.format(value [, opts])
lalin.format_file(path [, opts])
lalin.write_format_file(path [, opts])
```

## Family Namespaces

The family environment installs namespace values:

```text
ll / lalin  Lalin native language
schema      LalinSchema
llpvm       LLPVM
llisle      Llisle
region      generic LLB region head
_           splice marker
spread      explicit splice marker
```

Prefer `ll` for Lalin code. `lalin` is the long alias.

Namespaces are also family zones:

```lua
return {
  ll {
    ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
      ll.ret (a + b),
    },
  },

  llpvm {
    llpvm.task. compile {
      llpvm.input [ll.i32],
      llpvm.output [ll.i32],
    },
  },

  schema {
    schema. Demo {
      schema.product. Pair {
        left [schema.any],
        right [schema.any],
      },
    },
  },
}
```

Zones are semantic partitions over values. They are not lexical environments.
The namespace prefix remains the ownership marker.

## Types

Scalar types:

```lua
ll.void
ll.bool
ll.i8   ll.i16   ll.i32   ll.i64
ll.u8   ll.u16   ll.u32   ll.u64
ll.f32  ll.f64
ll.index
```

Compound type constructors:

```lua
ll.ptr [T]
ll.view [T]
ll.lease [ll.ptr [T]]
ll.owned [Handle]
ll.handle. Name [ll.u64]
ll.func_type { ll.i32, ll.i32 } [ll.i32]
ll.closure_type { ll.i32 } [ll.i32]
```

Type slots use `[]` because the content is evaluated Lua. Types are Lua values,
not strings.

```lua
a [ll.i32]
p [ll.ptr [ll.u8]]
```

## Declarations

Functions:

```lua
ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
  ll.ret (a + b),
}
```

Structs:

```lua
ll.struct. Vec2 {
  x [ll.f32],
  y [ll.f32],
}
```

Unions:

```lua
ll.union. Result {
  ok { value [ll.i32] },
  err { code [ll.i32] },
}
```

Externs:

```lua
ll.extern. puts { s [ll.ptr [ll.u8]] } [ll.i32]
```

Constants and statics:

```lua
ll.const. answer [ll.i32] (42)
ll.static. counter [ll.i32] (0)
```

## Products And Fragments

Product-shaped lists are ordinary Lua tables of typed names:

```lua
{ a [ll.i32], b [ll.i32] }
```

Reusable pieces should be fragments, not raw arrays:

```lua
local buffer = ll.product {
  p [ll.ptr [ll.u8]],
  n [ll.index],
}

ll.fn. first { _(buffer) } [ll.u8] {
  ll.ret (p[0]),
}
```

Common fragment roles:

```text
product
decls
stmts
exprs
conts
variants
```

Algebra:

```lua
params_a .. params_b       -- list/product concatenation
ok_exits + err_exits       -- protocol/sum choice
error_exits * position     -- decorate every alternative with a product
```

`_(fragment)` is the preferred splice. `spread(fragment)` is the explicit
fallback.

## Statements

Common statements:

```lua
ll.let. x [ll.i32] (1)
ll.var. acc [ll.i32] (0)
ll.set (acc) (acc + x)
ll.ret (acc)
ll.trap ()
```

Conditional statement:

```lua
ll.when (n :eq (0)) {
  ll.ret (0),
}
```

Switches require a default arm and have no fallthrough:

```lua
ll.switch (tag) {
  ll.case (0) { ll.ret (10) },
  ll.case (1) { ll.ret (20) },
  ll.default { ll.ret (-1) },
}
```

There is no source-level `for`, `while`, `break`, or `continue`. Lalin control
is jump-first.

## Regions

`region.` is the generic LLB control-machine head. Lalin consumes it as native
typed control when the body uses Lalin block vocabulary.

```lua
region. scan
  { p [ll.ptr [ll.u8]], n [ll.index], target [ll.u8] }
  {
    hit { pos [ll.index] },
    miss { pos [ll.index] },
  }
  {
    ll.entry. loop { i [ll.index] } {
      ll.when (i :ge (n)) {
        ll.jump. miss { pos = i },
      },

      ll.when (p[i] :eq (target)) {
        ll.jump. hit { pos = i },
      },

      ll.jump. loop { i = i + 1 },
    },
  }
```

A region is:

```text
input product + state product + named exit protocol + transition body
```

Functions are sealed regions with one return product. Use regions for internal
control. Use functions for raw product-return ABI boundaries.

## Emit

`emit` composes regions by wiring every callee exit to local behavior.

```lua
ll.emit scan(p, n, target; {
  hit = ll.block. found,
  miss = ll.block. not_found,
})
```

Every exit must be handled. If filling a continuation feels annoying, the
protocol is telling you about an unhandled case.

## Region Call

`emit` is the normal internal composition form: it splices the callee region
directly into the caller CFG and wires every exit locally.

`call` preserves a region boundary. Use it when the region needs its own frame:

- recursion
- debugging
- profiling
- instrumentation
- ABI-like isolation without losing named exits

Semantically, a region call is sugar for:

```text
sealed function
  -> encoded exit union
  -> dispatch back to the region protocol exits
```

That means `call` handles recursion while preserving the caller-facing protocol.

## Expressions

Operators are Lua-shaped but produce Lalin expressions:

```lua
a + b
a - b
a * b
a / b
p[i]
value.field
fn_call(a, b)
```

Comparison style uses readable method calls with spacing:

```lua
i :lt (n)
i :le (n)
i :eq (0)
i :ne (sentinel)
i :ge (n)
i :gt (n)
```

Conversions:

```lua
ll.as [ll.i32] (x)
```

Do not use angle-bracket type arguments.

## Contracts

Contracts are semantic facts, not comments.

```lua
ll.fn. sum { xs [ll.ptr [ll.i32]], n [ll.index] } [ll.i32] {
  ll.requires {
    ll.bounds(xs, n),
    ll.readonly(xs),
  },

  -- body
}
```

Contracts feed lowering and diagnostics. If the backend needs a fact, it should
be represented explicitly.

## Ownership

`owned T` values must be discharged or transferred exactly once. They cannot be
silently copied. Leases describe temporary access to owned or store-managed
resources.

Important rules:

- owned values cannot be fields of aggregates
- owned values cannot be copied
- region calls cannot carry owned or lease payloads; use `emit`
- handle representation casts are explicit trust boundaries

## Formatting

Lalin formatting is semantic. It formats evaluated Lalin/LLB values, not
arbitrary Lua text.

```sh
luajit scripts/lalinfmt.lua demo.lua
luajit scripts/lalinfmt.lua --check demo.lua
luajit scripts/lalinfmt.lua --write demo.lua
```

Programmatic API:

```lua
local text = require("lalin").format(value)
local text = require("lalin").format_file("demo.lua")
require("lalin").write_format_file("demo.lua")
```

## Diagnostics

Lalin reports structured diagnostics with source origins. Common early errors:

```text
parameter expects name [type]
field expects name [type]
region body expects entry/block declarations
function body cannot mix CFG blocks with ordinary statements
expected product fragment, got stmt fragment
unresolved name
invalid jump payload
owned value not discharged
```

Factory helpers should thread origins so generated declarations point back to
the caller abstraction.

## Compilation

Compile a declaration list:

```lua
local module = lalin.compile("demo", {
  ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
    ll.ret (a + b),
  },
})

print(module.add(3, 4))
```

Emit a LuaJIT artifact:

```lua
local artifact = lalin.emit_luajit_artifact(decls, {
  name = "Demo",
  path = "target/artifacts/demo.lua",
})

artifact:write()
```

The artifact path uses the LuaTrace bytecode copy-patch backend described in
`docs/ARCHITECTURE.md`.

## Non-Negotiable Rules

1. Lua owns genericity; Lalin receives monomorphic programs.
2. Types are values in `[]`, not strings.
3. No angle-bracket type arguments.
4. No source-level `for`, `while`, `break`, or `continue`.
5. Every block path terminates with return, jump, emit, trap, or equivalent.
6. Switches require a default arm and have no fallthrough.
7. Region protocols are explicit named exits.
8. Semantic facts belong in ASDL, not comments or strings.
9. Fragments are role-tagged values.
10. Backends consume validated facts; they do not infer hidden semantics.
