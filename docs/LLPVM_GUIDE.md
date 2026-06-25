# LLPVM Programmer Guide

LLPVM is Lalin's low-level PVM bytecode surface. Public authoring is a
no-seam LLB language object:

```text
LLPVM language definition
  is an LLB language
  is the Lua authoring API
  is the bytecode emitter
  is the formatter/process owner
```

There is no public `ll.vm` mutation API. The public authoring root is the
LLB-backed `pvm. Name { ... }` program head. The canonical shape is:

```lua
local lalin = require("lalin")
local ll = require("llpvm")

lalin.family.use()

return pvm. Expr {
  lang. Expr {
    type. Node {
      op. Int { value [i64] },
      op. Add { left [Node], right [Node] },
    },
  },

  world. raw [Expr],

  tape. raw_items [raw] {
    record. one (Node.Int { value = 1 }),
    record. two (Node.Int { value = 2 }),
    record. add_node (Node.Add { left = one, right = two }),
  },

  root { raw_items, add_node },
}
```

## Public module

```lua
local ll = require("llpvm")
```

Public API:

```lua
ll.language. Name { ... } -- define a reusable machine-language object
ll.use(opts)              -- install LLPVM definition heads into an environment
ll.loadstring(src, name)  -- load a DSL chunk
ll.loadfile(path)         -- load a DSL file
ll.load(src, name)        -- load and evaluate a DSL chunk

ll.bytecode(value)        -- encode ProgramSpec/ProgramImage
ll.bytebuffer(bytes)      -- copy a Lua string into uint8_t[] for FFI

ll.records(bytes)         -- process tape over LLPV bytecode records
ll.validate(bytes)        -- validation/inspection process over records
ll.inspect(bytes)         -- collect ll.validate(bytes) events into a table

ll.task_run(name, status, events, steps)
ll.task_event(seq, kind, payload)
ll.task_step(index, phase, machine, status)
ll.record_task(name, handle, steps)

ll.format(value, opts)    -- format evaluated LLPVM DSL values
ll.format_file(path)
ll.write_format_file(path)

ll.schema(items)          -- fragment helper for definition declarations
ll.tape_items(items)    -- fragment helper for tape values
ll._(fragment)            -- structural splice marker
ll.spread(fragment)       -- explicit alias for ll._

```

Removed public API:

```text
ll.vm
vm.language
vm.world
vm.seq
vm.phase
vm.program
mutation-style type construction
proxy tape construction
bytecode assembly helpers as authoring syntax
```

## Environment model

LLPVM depends on Lalin type values. The preferred authoring environment is
the Lalin language family:

```lua
local lalin = require("lalin")

lalin.family.use()
```

The family installs Lalin DSL exports and LLPVM DSL exports as one coherent
environment. It validates language capability dependencies and rejects
undeclared export collisions.

For isolated environments:

```lua
local env = {}
lalin.family.use { scope = "env", target = env, global = false }
```

`ll.use()` remains the low-level member install for tests and tools that want
only the LLPVM definition surface after Lalin types are already installed.
It provides:

```text
pvm
language
lang
type
op
world
tape
record
machine
phase
task
event
input
output
from
to
entry
cache
root
_
spread
```

`pvm` is the canonical program root. `language. Name { ... }` remains available
as a reusable machine-language object for embedded tools, but complete program
authoring should prefer `pvm. Name { ... }`.

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
lalin.use { scope = "env", target = env, global = false }
ll.use { scope = "env", target = env, global = false }
```

Prefer the family form unless the test is explicitly checking member-level
capability failures.

Generated language environments provide capability `llpvm.language.<Name>`.

## Definition body

A program contains language schemas, worlds, tapes, machines, phases, task
specifications, and roots in one explicit body.

```lua
pvm. Expr {
  lang. Expr {
    type. Node {
      op. Int { value [i64] },
      op. Add { left [Node], right [Node] },
    },
  },

  lang. Back {
    type. Value {
      op. ConstI64 { value [i64] },
    },
  },

  world. raw [Expr],
  world. lowered [Back],

  phase. lower_expr {
    from. raw,
    to. lowered,
    entry. ll_lower_expr,
    cache. full,
  },
}
```

World language is explicit. Use `world. raw [Expr]`, not implicit primary-world
rules. The explicit form is less magical and keeps whole-program loading
independent from declaration order.

## Program body

Tapes, records, and roots live in the same `pvm` body.

```lua
tape. raw_items [raw] {
  record. one (Node.Int { value = 1 }),
  record. two (Node.Int { value = 2 }),
  record. add_node (Node.Add { left = one, right = two }),
}

root {
  raw_items,
  add_node,
  lower_expr (raw_items),
}
```

`tape. name [world]` creates a tape in a world. `record. name (Type.Op { ...
})` records a named bytecode record. Record names are referenceable through LLB
auto-names.

Avoid using DSL keywords as tape or record names. For example, prefer
`raw_items` over `input`, because `input` is also the task input directive.

Reusable machine languages still support generated world/op heads after their
own `.use()`:

```lua
local Expr = ll.language. Expr {
  type. Node {
    op. Int { value [i64] },
  },
  world. raw,
}

Expr.use()
local spec = Expr {
  raw. raw_items {
    Int. one { value = 1 },
  },
  root { one },
}
```

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
local spec = ll.load([[
return pvm. Expr {
  lang. Expr {
    type. Node { op. Int { value [i64] }, },
  },
  world. raw [Expr],
  tape. raw_items [raw] {
    record. one (Node.Int { value = 1 }),
  },
  root { raw_items, one },
}
]], "expr.lua")

local image = spec:lower()
local bytes = image:bytecode()
image:write("program.llpv")
```

Shorthands:

```lua
spec:bytecode()
ll.bytecode(spec)
ll.bytecode(image)
```

Reusable machine-language objects also support `Expr:bytecode { ... }` after
their language-specific environment is installed, but the complete whole-program
path is `pvm. Name { ... }`.

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

## Task specifications and run records

LLPVM owns typed task declarations and run summaries. This is the common
place for progress tracking, validation events, LSP indexing events, source
analysis events, phase progress, and debugger stepping.

```lua
local spec = task. compile {
  input [i32],
  output [i32],
  event. progress [i32],
  event. diagnostic [i32],
}

local asdl = spec:asdl()
```

The ASDL shape is:

```text
LlPvm.TaskSpec {
  name   : Symbol
  input  : Type
  output : Type
  events : TaskEventSpec[]
}

LlPvm.TaskRun {
  task    : Symbol
  status  : string
  events  : TaskRunEvent[]
  steps   : TaskStepRun[]
}
```

Runtime helpers build the same typed records:

```lua
local run = ll.task_run("compile", "done", {
  ll.task_event(1, "progress", "typecheck"),
}, {
  ll.task_step(1, "typecheck", "hosted_typecheck", "done"),
})
```

Lalin phase execution reports include `report.run`, an
`LlPvm.TaskRun`. That means progress is not a compiler-local trace format.
It is an LLPVM task value that tools can inspect, serialize, and project.

## Formatting

Formatting is semantic. It formats evaluated LLPVM DSL values, not arbitrary Lua
tokens.

```lua
print(ll.format(spec, { width = 100, indent = 2 }))
```

Canonical style:

```lua
pvm. Expr
lang. Back
type. Node
op. Int
world. raw [Expr]
tape. raw_items [raw]
record. one (Node.Int { ... })
from. raw
to. lowered
entry. ll_lower_expr
cache. full
task. compile
event. progress [i32]
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
