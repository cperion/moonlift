# LLPVM DSL Specification

LLPVM public authoring is no-seam LLB.

```text
An LLPVM language is an LLB language with bytecode semantics.
```

There is no public parser, tokenizer, mutation VM, proxy authoring API, or
`pvm. Program` layer. Lua syntax produces values; LLB gives those values roles,
origins, diagnostics, formatting, process events, and environments; LLPVM lowers
them to bytecode.

## Doctrine

```text
Define a language.
Project worlds.
Record streams through generated world heads.
Create values through generated op heads.
Map phases.
Emit roots.
Validate through process events.
```

The core invariant:

```text
The language definition object is the generated DSL.
```

## Canonical surface

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
} {
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

This is the required style for maintained examples, tests, and docs.

## Definition object

```lua
language. Name { definition_declarations... }
```

returns a `MachineLanguage` object. The object owns:

```text
schema declarations
generated op heads
generated world stream heads
use() environment installation
program construction
lowering and bytecode emission
formatting
inspection/validation process hooks
```

There is no separate generation step.

## Definition declarations

A definition body accepts:

```text
type declarations for the primary language
secondary lang declarations
world declarations
machine declarations
phase declarations
fragments
```

Primary type declaration:

```lua
type. Node {
  op. Int { value [i64] },
  op. Add { left [Node], right [Node] },
}
```

Secondary language declaration:

```lua
lang. Back {
  type. Value {
    op. ConstI64 { value [i64] },
  },
}
```

World declaration:

```lua
world. raw          -- means world. raw [PrimaryLanguage]
world. lowered [Back]
```

Phase declaration:

```lua
phase. lower_expr {
  from. raw,
  to. lowered,
  entry. ll_lower_expr,
  cache. full,
}
```

## Program construction

Calling a `MachineLanguage` object authors a program:

```lua
Expr {
  raw. input {
    Int. one { value = 1 },
    Add. next { left = one, right = one },
  },

  root { next },
}
```

Generated world heads:

```lua
raw. input { ... } -- stream named input in world raw
raw { ... }        -- stream named raw in world raw
```

Generated op heads:

```lua
Int. one { value = 1 }
Add. sum { left = one, right = two }
```

Generated op heads create named `ValueSpec` values. Value names are referenced
through LLB auto-names. A root may name a stream or a value:

```lua
root { input }
root { sum }
```

A value root lowers to a one-value root stream.

## Invariants

```text
An op belongs to exactly one type.
A type belongs to exactly one language.
A world projects exactly one language.
A value belongs to exactly one world and one type.
A stream belongs to exactly one world.
A machine consumes one world and produces one world.
A phase consumes one world and produces one world.
A root names a stream, value, or phase application.
```

The syntax must make world, phase, and root boundaries visible.

## Environment model

`ll.use()` installs the definition surface:

```text
language
type
op
lang
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

A generated machine language also has `use()`:

```lua
local Expr = language. Expr { ... }
Expr.use()
```

The generated environment installs op heads and world heads for that language.
It provides capability:

```text
llpvm.language.<Name>
```

## Lowering

```text
MachineLanguage call
  -> ProgramSpec
  -> bytecode.builder records
  -> ProgramImage
  -> LLPV byte string
```

```lua
local spec = Expr { ... }
local image = spec:lower()
local bytes = image:bytecode()
```

The old mutation/proxy authoring model is not public.

## Diagnostics

Diagnostics are LLB event-aware and should include:

```text
language definition origin
op declaration origin
world declaration origin
stream declaration origin
value declaration origin
consumed slot/event
role that normalized the value
```

Examples:

```text
Add.sum missing payload field right
```

```text
value one belongs to world raw but field other expects world b
```

```text
phase lower_expr expected input world raw but got lowered
```

## Process-backed inspection and validation

Bytecode inspection and validation are processes.

```lua
ll.records(bytes)
ll.validate(bytes)
ll.inspect(bytes)
```

Canonical event kinds:

```text
header
root_op
record
diagnostic
```

Every event carries `seq`. Record/root payloads may carry semantic `index`.

## Formatting

Formatting is semantic and evaluated-value based.

Canonical style:

```lua
language. Expr
type. Node
op. Int
world. raw
raw. input
Int. one
Add. sum
root { sum }
```

The dot belongs to the keyword/head side.

## Non-goals

LLPVM is not:

```text
a parser
a bytecode assembly language
a mutation proxy API
a second Moonlift type language
a source-to-source Lua transformer
```

It is:

```text
an LLB language factory whose language objects lower directly to LLPV bytecode
```

## Final rule

If a syntax choice creates a seam between schema definition and authoring API,
it is wrong.

If a syntax choice makes the language object itself own schema, authoring,
formatting, diagnostics, process hooks, and bytecode emission, it is preferred.
