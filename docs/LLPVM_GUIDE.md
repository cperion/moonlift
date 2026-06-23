# LLPVM Programmer Guide

LLPVM is Moonlift's low-level PVM bytecode surface. Public authoring is a
no-seam LLB language object:

```text
LLPVM language definition
  is an LLB language
  is the Lua authoring API
  is the bytecode emitter
  is the formatter/process owner
```

There is no public `ll.vm` mutation API and no public `pvm. Program` authoring
surface. The canonical shape is:

```lua
local moon = require("moonlift")
local ll = require("llpvm")

moon.use()
ll.use()

return language. Expr {
  type. Node {
    op. Int { value [i64] },
    op. Add { left [Node], right [Node] },
  },

  world. raw,
} {
  raw. input {
    Int. one { value = 1 },
    Int. two { value = 2 },
    Add. sum { left = one, right = two },
  },

  root { sum },
}
```

## Public module

```lua
local ll = require("llpvm")
```

Public API:

```lua
ll.language. Name { ... } -- define an LLPVM-backed LLB language object
ll.use(opts)              -- install LLPVM definition heads into an environment
ll.loadstring(src, name)  -- load a DSL chunk
ll.loadfile(path)         -- load a DSL file
ll.load(src, name)        -- load and evaluate a DSL chunk

ll.bytecode(value)        -- encode ProgramSpec/ProgramImage/ASDL program
ll.bytebuffer(bytes)      -- copy a Lua string into uint8_t[] for FFI

ll.records(bytes)         -- raw process stream over LLPV bytecode records
ll.validate(bytes)        -- validation/inspection process over records
ll.inspect(bytes)         -- collect ll.validate(bytes) events into a table

ll.format(value, opts)    -- format evaluated LLPVM DSL values
ll.format_file(path)
ll.write_format_file(path)

ll.schema(items)          -- fragment helper for definition declarations
ll.stream_items(items)    -- fragment helper for stream values
ll._(fragment)            -- structural splice marker
ll.spread(fragment)       -- explicit alias for ll._

ll.asdl, ll.T, ll.B       -- ASDL context/builders for tools and tests
```

Removed public API:

```text
ll.vm
pvm. Program
vm.language
vm.world
vm.seq
vm.phase
vm.program
mutation-style type construction
proxy stream construction
bytecode assembly helpers as authoring syntax
```

## Environment model

LLPVM depends on Moonlift type names. Compose environments explicitly:

```lua
local moon = require("moonlift")
local ll = require("llpvm")

moon.use()
ll.use()
```

`ll.use()` provides the LLPVM definition surface:

```text
language
type
op
world
machine
phase
from
to
entry
cache
root
_
spread
```

It does not install `pvm`.

A generated machine language has its own `use()`:

```lua
local Expr = language. Expr {
  type. Node { op. Int { value [i64] } },
  world. raw,
}

Expr.use()

return Expr {
  raw. input { Int. one { value = 1 } },
  root { one },
}
```

For isolated environments:

```lua
local env = {}
moon.use { scope = "env", target = env, global = false }
ll.use { scope = "env", target = env, global = false }
```

Generated language environments provide capability `llpvm.language.<Name>`.

## Definition body

A language definition contains the primary operation schema plus optional
secondary language schemas, worlds, machines, and phases.

```lua
language. Expr {
  type. Node {
    op. Int { value [i64] },
    op. Add { left [Node], right [Node] },
  },

  lang. Back {
    type. Value {
      op. ConstI64 { value [i64] },
    },
  },

  world. raw,
  world. lowered [Back],

  phase. lower_expr {
    from. raw,
    to. lowered,
    entry. ll_lower_expr,
    cache. full,
  },
}
```

`world. raw` inside the primary language definition means `world. raw [Expr]`.
Worlds for secondary languages stay explicit, for example `world. lowered
[Back]`.

## Program body

Calling the language object authors a program in that language.

```lua
Expr {
  raw. input {
    Int. one { value = 1 },
    Int. two { value = 2 },
    Add. sum { left = one, right = two },
  },

  root {
    input,
    sum,
    lower_expr (input),
  },
}
```

Generated world heads create streams:

```lua
raw. input { ... } -- stream named input in world raw
raw { ... }        -- stream named raw in world raw
```

Generated op heads create named values:

```lua
Int. one { value = 1 }
Add. sum { left = one, right = two }
```

Value names are referenceable through LLB auto-names. `root { sum }` is valid and
creates a root stream containing that value.

## Lowering

The lowering path is direct:

```text
LLB language object
  -> ProgramSpec
  -> bytecode.builder records
  -> ProgramImage
  -> LLPV byte string
```

```lua
local spec = Expr {
  raw. input { Int. one { value = 1 } },
  root { one },
}

local image = spec:lower()
local bytes = image:bytecode()
image:write("program.llpv")
```

Shorthands:

```lua
spec:bytecode()
ll.bytecode(spec)
ll.bytecode(image)
Expr:bytecode { ... }
```

## Process-backed inspection and validation

LLPVM bytecode inspection is process-shaped.

```lua
for ev in ll.records(bytes) do
  print(ev.seq, ev.kind)
end
```

Validation wraps records and returns a summary:

```lua
local h = ll.validate:start(bytes)
for ev in h:events() do
  if ev.kind == "diagnostic" then
    print(ev.code, ev.message)
  end
end

assert(h:result().valid)
```

`ll.inspect(bytes)` collects all events from `ll.validate(bytes)`.

Every process event has `seq`. Domain payloads may have `index`.

## Formatting

Formatting is semantic. It formats evaluated LLPVM DSL values, not arbitrary Lua
tokens.

```lua
print(ll.format(spec, { width = 100, indent = 2 }))
```

Canonical style:

```lua
language. Expr
lang. Back
type. Node
op. Int
world. raw
raw. input
Int. one
Add. sum
from. raw
to. lowered
entry. ll_lower_expr
cache. full
```

## Runtime boundary

The native runtime borrows bytecode images. Do not pass DSL values, ProgramSpec
objects, or ProgramImage Lua objects to native runtime APIs. Pass byte strings or
explicit FFI byte buffers.

## Doctrine

LLPVM languages are LLB languages with bytecode semantics.

```text
LLB gives the fast Lua authoring surface.
LLPVM gives the typed bytecode/runtime substrate.
```

The language definition is not a separate generator step. The definition object
is the generated DSL.
