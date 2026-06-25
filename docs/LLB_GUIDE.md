# LLB Guide

LLB is the Lua Language Builder workbench in `lua/llb.lua`. It is the center of
the Lalin family.

It lets ordinary Lua syntax act as a structured language surface without adding
a parser, but that is only the first layer. LLB also owns the machinery that
makes family languages compose: namespaces, roles, staged heads, fragments,
origins, diagnostics, formatting, indexing, generic regions, protocols,
processes, GPS lowering, and managed environments.

```text
Lua syntax
  -> Lua values
  -> LLB events, roles, heads, fragments, origins
  -> member-language values
  -> diagnostics, formatting, indexing, compilation
```

LLB is generic. Lalin-specific types, ownership, native CFG checking, and
backend behavior belong to Lalin. The generic region algebra belongs to LLB;
Lalin consumes it.

## Core Atoms

LLB code is built from a small set of atoms:

```text
shape       the Lua value shape
channel     how Lua delivered it
event       a value plus channel/origin information
role        normalization rule for a semantic position
slot        one staged head position
head        staged constructor
fragment    role-tagged reusable value
origin      source/provenance handle
diagnostic  structured failure report
namespace   owned language surface
zone        family partition
protocol    named behavior contract
region      generic control machine
process     event-protocol region
```

A normal user writes:

```lua
ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
  ll.ret (a + b),
}
```

A language author defines roles and heads:

```lua
local llb = require("llb")
local g = llb.grammar
local ch = llb.channel

local Mini = llb.define "Mini" {
  g.role. fields { kind = "product", unique_names = true },
  g.role. body   { kind = "array", algebra = "list" },

  g.head. fn {
    g.slot. name   [g.name]   { channel = ch.index_name },
    g.slot. params [g.fields] { channel = ch.call_table },
    g.slot. result [g.type]   { channel = ch.index_type, optional = true },
    g.slot. body   [g.body]   { channel = ch.call_table },
    emit = function(n) return Mini.ast.fn(n) end,
  },
}
```

## Channels

Channels describe Lua syntax shape:

```text
index:name       fn. add
index:type       [i32]
index:value      head [computed]
call:none        ret ()
call:value       ret (x)
call:table       { ... }
call:many        f(a, b, c)
operator:concat  ..
operator:choice  +
operator:decorate *
env:lookup       unknown global as symbol
```

Choose channels deliberately. Diagnostics are only as good as the slot/channel
model.

## Roles

Roles own normalization. Heads should stay thin.

Common role kinds:

```text
name
type
expr
array/list
product
sum/protocol
record
string
number
boolean
value
identity
```

If two heads need the same shape rule, that rule belongs in a role, not in
duplicated emit callbacks.

## Heads

A head is a staged constructor. It consumes slots in order. Each slot names:

- role
- channel
- optionality
- diagnostics label

LLB supports incomplete stages intentionally, because Lua dot/index/call syntax
arrives one step at a time.

Fast/generated heads may specialize this state machine, but reflective heads
remain the diagnostic reference.

## Fragments

Fragments are role-tagged reusable values. They preserve metaprogramming
structure after Lua evaluation.

```lua
local params = product {
  p [ptr [u8]],
  n [index],
}

local exits = conts {
  ok { value [i32] },
} + (conts {
  eof {},
  bad_digit {},
} * product {
  pos [index],
})
```

Operators:

```text
..  list/product concatenation
+  sum/protocol choice
*  decorate every protocol alternative with a product
```

`_(fragment)` is the preferred splice marker. `spread(fragment)` is the
explicit spelling.

## Namespaces And Families

A namespace is a Lua table-shaped language surface with semantic ownership
metadata. It is not just a conflict-avoidance trick.

```lua
ll.fn. add ...
schema.product. Pair ...
llpvm.task. compile ...
llisle.rule. lower ...
```

Family zones use callable namespaces:

```lua
return {
  ll { ... },
  llpvm { ... },
  schema { ... },
}
```

Tools project only the zones they own. This keeps mixed-language values
composable without hiding ownership.

## Region And GPS

LLB owns generic `region.`. Region is the shared control algebra that lets the
family compose. A region is:

```text
input product + state product + named exit protocol + transition body
```

GPS is one lowering of pull-shaped regions:

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

Do not introduce a separate semantic `stream` layer. Pull behavior is a region
protocol. Arrays, reports, diagnostic bags, backend command buffers, and text
output are materializers.

## Processes

A process is a region with an event protocol lowered to GPS.

```lua
local function body(ctx, source)
  local function gen(param, state)
    if state == 0 then
      return 1, ctx:make_event("load", { bytes = #param.source })
    end
    return nil
  end
  return gen, { source = source }, 0
end

local load = llb.process. load { "source" } (body)

for ev in load(src) do
  print(ev.seq, ev.kind)
end
```

Use processes for source loading, indexing, diagnostics, bytecode inspection,
debug stepping, and long-running compiler work. Do not use a process just to
compute one pure value.

## Origins And Diagnostics

Origins connect evaluated values to source/provenance. Diagnostics should carry
head, slot, role, event, and origin context where possible.

Generated fast paths should be diagnostically lazy:

```text
success path:
  no rich diagnostic allocation

failure path:
  replay through reflective metadata
```

## Formatting And Indexing

LLB formatting is semantic. It formats evaluated values through role/head/member
hooks. It is not a lossless Lua source formatter.

Indexing should be process-shaped so tools can consume only the events they
need:

```text
load
index
symbol
hover
diagnostic
completion
reference
definition
```

## Codegen

LLB can compile its own workbench machinery:

```text
role normalizers
fragment expanders
staged head machines
family projectors
process/event regions
format/index walkers
environment installers
```

Generated functions must carry enough metadata to answer:

```text
what semantic thing is this?
which grammar object generated it?
what source line produced it?
how do we replay reflectively?
```

Use LuaJIT debug names, chunk names, line maps, and metadata upvalues to keep
generated code inspectable.

## Design Checklist

Before a language is complete, answer:

- What roles exist?
- Which roles compose?
- Which heads are thin constructors over those roles?
- Which namespace owns each semantic primitive?
- Which reusable pieces are fragments?
- Which long operations are process/region-shaped?
- Which materializers are explicit?
- How are origins preserved?
- How do diagnostics replay on failure?
- How does formatting see evaluated values?

## Anti-Patterns

Avoid:

- raw reusable arrays with no role tag
- callbacks hiding stringly typed semantics
- heads duplicating role normalization
- hidden global installation
- coroutine-only work queues
- eager event arrays where GPS can stay pull-shaped
- compatibility shims for removed surfaces
- formatting from source text instead of semantic values
