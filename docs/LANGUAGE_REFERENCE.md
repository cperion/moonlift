# Lalin Language Reference

This is the public reference for the Lalin language exposed by:

```lua
local lalin = require("lalin")
```

Lalin source is ordinary Lua shaped by LLBL. Lua parses and evaluates the file.
LLBL captures the resulting values through staged heads, typed slots, fragments,
namespaces, origins, diagnostics, and generic regions. Lalin is the compiled
language member that normalizes those values into explicit ASDL.

## Loading

Use a managed language environment for normal authoring files:

```lua
local lalin = require("lalin")
lalin.language.use()

return {
  lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
    lln.ret (a + b),
  },
}
```

For isolated loading:

```lua
local lalin = require("lalin")

local unit = lalin.loadstring([[
  return {
    lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
      lln.ret (a + b),
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
lalin.plan_luajit_artifact(decl [, opts])
lalin.emit_luajit_plan_artifact(plan [, opts])
lalin.emit_luajit_artifact(decl [, opts])
lalin.emit_c_artifact(decl [, opts])
lalin.format(value [, opts])
lalin.format_file(path [, opts])
lalin.write_format_file(path [, opts])
```

## Language Namespaces

The language environment installs namespace values:

```text
lln / lalin  Lalin native language
schema      LalinSchema
llpvm       LLPVM
region      generic LLBL region head
_           splice marker
spread      explicit splice marker
```

Prefer `lln` for Lalin code. `lalin` is the long alias.

Namespaces are also language zones:

```lua
return {
  lln {
    lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
      lln.ret (a + b),
    },
  },

  llpvm {
    llpvm.task. compile {
      llpvm.input [lln.i32],
      llpvm.output [lln.i32],
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
lln.void
lln.bool
lln.i8   lln.i16   lln.i32   lln.i64
lln.u8   lln.u16   lln.u32   lln.u64
lln.f32  lln.f64
lln.index
```

Compound type constructors:

```lua
lln.ptr [T]
lln.view [T]
lln.lease [lln.ptr [T]]
lln.owned [Handle]
lln.handle. Name [lln.u64]
lln.func_type { lln.i32, lln.i32 } [lln.i32]
lln.closure_type { lln.i32 } [lln.i32]
```

Type slots use `[]` because the content is evaluated Lua. Types are Lua values,
not strings.

```lua
a [lln.i32]
p [lln.ptr [lln.u8]]
```

## Declarations

Functions:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

Structs:

```lua
lln.struct. Vec2 {
  x [lln.f32],
  y [lln.f32],
}
```

Unions:

```lua
lln.union. Result {
  ok { value [lln.i32] },
  err { code [lln.i32] },
}
```

Externs:

```lua
lln.extern. puts { s [lln.ptr [lln.u8]] } [lln.i32]
```

Constants and statics:

```lua
lln.const. answer [lln.i32] (42)
lln.static. counter [lln.i32] (0)
```

## Products And Fragments

Product-shaped lists are ordinary Lua tables of typed names:

```lua
{ a [lln.i32], b [lln.i32] }
```

Reusable pieces should be fragments, not raw arrays:

```lua
local buffer = lln.product {
  p [lln.ptr [lln.u8]],
  n [lln.index],
}

lln.fn. first { _(buffer) } [lln.u8] {
  lln.ret (p[0]),
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
lln.let. x [lln.i32] (1)
lln.var. acc [lln.i32] (0)
set (acc)(acc + x)
lln.ret (acc)
lln.trap ()
```

Conditional statement:

```lua
lln.when (n :eq (0)) {
  lln.ret (0),
}
```

Switches require a default arm and have no fallthrough:

```lua
lln.switch (tag) {
  lln.case (0) { lln.ret (10) },
  lln.case (1) { lln.ret (20) },
  lln.default { lln.ret (-1) },
}
```

There is no source-level `for`, `while`, `break`, or `continue`. Lalin control
is jump-first.

## Regions

`region.` is the generic LLBL control-machine head. Lalin consumes it as native
typed control when the body uses Lalin block vocabulary.

```lua
region. scan
  { p [lln.ptr [lln.u8]], n [lln.index], target [lln.u8] }
  {
    hit { pos [lln.index] },
    miss { pos [lln.index] },
  }
  {
    lln.entry. loop { i [lln.index] } {
      lln.when (i :ge (n)) {
        lln.jump. miss { pos = i },
      },

      lln.when (p[i] :eq (target)) {
        lln.jump. hit { pos = i },
      },

      lln.jump. loop { i = i + 1 },
    },
  }
```

A region is:

```text
input product + state product + named exit protocol + transition body
```

Functions are sealed regions with one return product. Use regions for internal
control. Use functions for raw product-return ABI boundaries.

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
lln.as [lln.i32] (x)
```

Do not use angle-bracket type arguments.

## Contracts

Contracts are semantic facts, not comments.

```lua
lln.fn. sum { xs [lln.ptr [lln.i32]], n [lln.index] } [lln.i32] {
  lln.requires {
    lln.bounds (xs)(n),
    lln.readonly(xs),
  },

  -- body
}
```

Contracts feed lowering and diagnostics. If the backend needs a fact, it should
be represented explicitly.

## Native Loops And Stencil-Shaped Work

`lln.loop` is the source head for regular native loop domains. It is not a
general `for` or `while`: it authors structured facts that flow through
`Code -> Flow -> Kernel -> Stencil`.

One-dimensional range:

```lua
lln.fn. sum { xs [lln.ptr [lln.i32]], n [lln.index] } [lln.i32] {
  lln.requires {
    lln.bounds (xs)(n),
    lln.readonly(xs),
  },

  lln.loop. i [lln.range { 0, n }] [lln.i32] {
    lln.fold. acc [lln.i32] {
      init = 0,
      by = lln.add,
      step = xs[i],
    },
  },
}
```

Stores and pointwise bodies:

```lua
lln.loop. i [lln.range { 0, n }] {
  set (dst[i])(lhs[i] + rhs[i]),
}
```

`select` lowers to a branchless apply body when the condition and arms are
stencil-pure:

```lua
lln.loop. i [lln.range { 0, n }] {
  set (dst[i])(select (lhs[i] :gt (0))(lhs[i])(rhs[i])),
}
```

N-dimensional ranges use a product of induction variables:

```lua
lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
  set (dst[i * w + j])(src[i * w + j]),
}
```

The current frontend recognizes compact row-major affine indexing, non-zero
starts and non-unit producer steps for that compact form, and fixed-coefficient
affine expressions such as `j * 2 + i` as typed affine layouts. Broader dynamic
affine normalization remains a backend gap.

Window domains expose neighbor reads in the body:

```lua
lln.loop { i } [lln.window_nd {
  axes = { { 0, n } },
  windows = { { 1, 1, boundary = "clamp" } },
}] {
  set (dst[i])(xs[i - 1] + xs[i] + xs[i + 1]),
}
```

`lln.scan` over `lln.tiled_nd` is an axis scan over the logical domain. Tile
shape is a traversal/materialization policy; it does not reset prefix state by
itself.

```lua
lln.loop { i, j } [lln.tiled_nd {
  axes = { { 0, h }, { 0, w } },
  tiles = { 4, 8 },
}] {
  lln.scan. acc [lln.i32] {
    init = 0,
    by = lln.add,
    axis = 2,
    step = xs[i * w + j],
    into = dst[i * w + j],
  },
}
```

Scatter-reduce is recognized from immediate indexed read-modify-write forms for
the current reducer vocabulary:

```lua
lln.loop. i [lln.range { 0, n }] {
  set (bins[idx[i]])(bins[idx[i]] + src[i])
}
```

Contracts such as `bounds`, `readonly`, `writeonly`, and `disjoint` are consumed
by these paths. Unsupported loop shapes should be rejected through typed facts
or fall back through the semantic path; they should not silently become
element-level FFI code.

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

Lalin formatting is semantic. It formats evaluated Lalin/LLBL values, not
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
  lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
    lln.ret (a + b),
  },
})

print(module.add(3, 4))
```

Emit a LuaJIT artifact:

```lua
local artifact = lalin.emit_luajit_artifact(decls, {
  name = "Demo",
  path = "target/artifacts/demo.lua",
  copy_patch = "bc",
})

artifact:write()
```

`lalin.compile` uses the LuaTrace BC copy-patch path by default. It is the
portable semantic path and does not require the native stencil toolchain.

`lalin.emit_luajit_artifact` defaults to the fast copy+residual path:

```text
typed stencil plans
  -> copy_patch_mc bank stencils
  -> embedded/installed MC bytes
  -> TCC residual glue
  -> loaded LuaJIT module
```

The residual glue calls installed bank stencils at coarse function boundaries.
It is not an element-level FFI lowering strategy. For debugging or direct
bank-call comparison, pass `native_residual = false` to
`lalin.emit_luajit_artifact`. The generated banks are no-hole artifacts:
selection picks an already materialized entry, and residual glue links calls to
that entry.

The MC path requires an already selected and built `MCStencilBank`; it does not
build one during artifact emission. Use the explicit planning split when
driving the native path from Lua:

```lua
local plan = lalin.plan_luajit_artifact(decls, {
  name = "Demo",
  copy_patch = "mc",
})

local bank = assert(plan.backend.build_mc_bank(plan.artifacts, {
  stem = "demo_aot_bank",
}))

local artifact = lalin.emit_luajit_plan_artifact(plan, {
  name = "Demo",
  path = "target/artifacts/demo.lua",
  mc_bank = bank,
})
```

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
