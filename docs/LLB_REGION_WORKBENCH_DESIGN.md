# LLB Region Workbench Design

This document replaces the old stream-workbench model.

The full semantic interaction model is
[`LLB_GENERIC_REGION_ALGEBRA.md`](LLB_GENERIC_REGION_ALGEBRA.md). This document
is the workbench/runtime view: it explains why LLB uses region/protocol/GPS
vocabulary and how the current pull-shaped implementation should behave.

LLB is a region workbench. A workbench operation is a named control machine
with explicit input, explicit state, and an explicit exit protocol. A pullable
sequence is not a primitive concept. It is one region protocol among many.

The implemented head is LLB-owned and globally available from the LLB family
root:

```lua
region. name { input... } { exits... } { body... }
```

That expression creates an LLB `Region` descriptor. Member languages decide how
to consume the descriptor. Lalin consumes it as native typed control when
the body contains Lalin `entry`, `block`, `jump`, and `emit` declarations.

Canonical stack:

```text
region
  semantic control machine

protocol
  named exits of that machine

gps
  low-level LuaJIT lowering ABI
```

The old word `stream` must not be used as a semantic category. It mixed two
different ideas:

```text
pullable sequence of values
gen,param,state implementation ABI
```

In the region model these become:

```text
pullable sequence
  region with a pull protocol

gen,param,state
  GPS lowering of a region step
```

There is no compatibility stream layer in the design. LLB code should use
`region` for semantic machines, `protocol` for exits, `gps` for pull lowering,
and `materializer` for consumers.

## Core Law

Region is the algebra.

Protocol names the exits.

GPS is one lowering.

A region has this abstract shape:

```text
region R(input_product, state_product; protocol)
```

It consumes an input product and the current state product. It performs one
piece of work or a whole control transition, then exits by selecting exactly one
named protocol exit.

Examples:

```text
pull protocol:
  item(next_state, value)
  done

process protocol:
  event(next_state, event)
  diagnostic(next_state, diagnostic)
  done(result)
  failed(error)

parser protocol:
  ok(next_cursor, expr)
  syntax_error(pos, code)
  need_more(request)

scheduler protocol:
  got(job)
  empty
  stop
```

The generic workbench question is no longer:

```text
what stream do I consume?
```

It is:

```text
what region am I running?
what protocol does it exit through?
which exits are resumable?
which exits are terminal?
what materializer, if any, consumes those exits?
what lowering implements this region?
what metadata maps the lowered machine back to region/protocol semantics?
```

## Region Shape

A region is a stateful control boundary:

```text
input product
state product
protocol exits
transition machine
origin/debug metadata
```

The protocol is part of the type of the machine. It is not an ad hoc event
string convention.

```text
Region<Input, State, Protocol>
```

The machine may be interpreted reflectively, compiled to LuaJIT GPS, compiled to
Lalin CFG, represented as an LLPVM phase/task, or inspected by tooling.

## Exit Classes

Protocol exits are classified by control behavior.

Terminal exits end the region run:

```text
done(result)
failed(diagnostic)
empty
stop
```

Resumable exits return a next state:

```text
item(next_state, value)
event(next_state, event)
diagnostic(next_state, diagnostic)
blocked(next_state, reason)
```

This is the piece the old stream model hid. A pull sequence is just a protocol
whose productive exit is resumable and whose `done` exit is terminal.

## GPS Lowering

GPS is the compact LuaJIT ABI:

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

GPS is not the semantic model. It is one lowering of a region with a pull-shaped
protocol.

Mapping:

```text
done
  -> return nil

item(next_state, value)
  -> return next_state, value

event(next_state, ev)
  -> return next_state, ev

diagnostic(next_state, diag)
  -> return next_state, diag
```

`param` is the invariant product:

```text
grammar constants
compiled role/head metadata
upstream region handles
hook functions
source handles
debug maps
```

`state` is the explicit continuation product:

```text
cursor
counters
nested region states
stage index
diagnostic replay token
```

GPS can stay small and LuaJIT-friendly because region/protocol metadata lives in
LLB, not in the hot return convention.

## Materialization

Materialization is a protocol consumer.

It is valid when:

```text
the downstream ABI requires a complete buffer
the user asks for a report/result object
the optimizer needs a whole graph proof
the backend needs a flat command array
diagnostics must be rendered as a complete list
```

It must be explicit in the API or in local code shape:

```text
collect all items into an array
fold exits into one result
drain diagnostic exits into a bag
render format exits into text
build a backend command buffer
```

Forbidden hidden materialization:

```text
implicit process event queues
coroutine yield buffers
normalizers that silently build side products
tooling walkers that collect everything before the first useful exit
```

The materializer is not the region. It is a named consumer of a protocol.

## LLB Concepts In Region Terms

Roles are regions.

```text
raw value + role context
  -> normalized(value)
  -> field(next_state, field)
  -> item(next_state, item)
  -> variant(next_state, variant)
  -> failed(diagnostic)
```

Role collection is a materializer over the role protocol.

Spreads are protocol splices.

```text
spread(fragment)
  -> emit each item/field/variant exit of the fragment's role protocol
```

Heads are deterministic region state machines over channel events.

```text
head state + channel event
  -> next head state
  -> constructed(value)
  -> failed(diagnostic)
```

The public no-parentheses Lua surface is a materializing command interface over
the same head region.

Processes are regions with an event protocol.

```text
process state
  -> event(next_state, ev)
  -> diagnostic(next_state, diag)
  -> done(result)
  -> failed(error)
```

Formatting is a region with a text/token protocol.

```text
format state
  -> chunk(next_state, text)
  -> done
```

Indexing is a region with a tooling fact protocol.

```text
index state
  -> symbol(next_state, symbol)
  -> hover(next_state, hover)
  -> diagnostic(next_state, diagnostic)
  -> done
```

Family projection is a region router.

```text
family value + projection state
  -> zone(next_state, zone)
  -> member_event(next_state, event)
  -> done
```

## Lalin And Region

Lalin's `region` is a concrete compiled realization of the same algebra:

```text
input product
native CFG blocks
named continuation protocol
exactly one selected exit
```

The generic LLB region is broader. It may lower to Lalin CFG, LuaJIT GPS,
LLPVM task/phase machinery, or reflective tooling.

Lalin function:

```text
sealed region with one return continuation
```

Lalin emit:

```text
region composition by protocol splicing
```

The shared concept is not owned by Lalin alone. Lalin owns the native CFG
lowering and the typed source-level control syntax. LLB owns the generic region
algebra.

## LLPVM And Region

LLPVM does not own `stream`. Its typed sequence vocabulary is `tape`.

LLPVM phases and tasks are region-shaped:

```text
phase input tape + args
  -> output(tape)
  -> diagnostic(event)
  -> failed(status)
```

LLPVM may lower a region protocol into bytecode, tapes, recordings, or run
records. Those are backend products, not the generic LLB concept.

## Public Naming Doctrine

Use these names:

```text
region
  semantic control machine

protocol
  named exits

exit
  one named continuation of a protocol

materializer
  consumer that turns protocol exits into a complete value

gps
  gen,param,state lowering ABI

tape
  LLPVM typed bytecode/runtime sequence

lane
  LalinKernel memory/data lane
```

Do not introduce:

```text
stream as semantic category
stream as family language head
stream as compatibility layer
```

If an implementation object still needs a compact LuaJIT name, use `gps`.

## Codegen Model

Codegen compiles region machines.

Reflective runtime:

```text
interprets region/protocol metadata
builds rich diagnostics directly
```

Compiled runtime:

```text
specializes a region to a GPS or native machine
keeps protocol ids, line maps, and fallback metadata
replays errors through reflective region semantics
```

Generated functions must answer:

```text
which region am I?
which protocol exits can I produce?
which grammar object generated me?
which reflective region do I replay through?
which source/generated line maps describe me?
```

The generated machine may return compact GPS payloads. The debug metadata maps
those payloads back to region and protocol exits.

## Diagnostics

Diagnostics are protocol exits, not side effects.

Fast path:

```text
no diagnostic allocation
compact exit ids
```

Failure path:

```text
inflate region id
inflate protocol exit id
recover generated source location
replay reflective diagnostic construction
render user source + generated source + grammar origin
```

This preserves LLB's diagnostic richness while keeping compiled paths small.

## Migration Rule

The old stream document is gone. New work must not add new semantic APIs named
`stream`.

Renames implied by this model:

```text
stream ABI
  -> GPS ABI

stream machine
  -> region lowering / GPS machine

stream spec/plan
  -> region spec / region plan

stream sink
  -> materializer

process stream
  -> process region / process GPS lowering

role stream
  -> role region / role protocol

format stream
  -> format region / chunk protocol

index stream
  -> index region / fact protocol
```

Implementation names that cross the LLB public or language-family boundary must
use the new vocabulary. Ordinary domain docs may still use stream when the
domain literally means an external byte stream, token stream, UI render stream,
or other non-LLB concept.

## Completion Checklist

- [x] GPS ABI exists in LLB.
- [x] Processes are pull-driven GPS machines.
- [x] Role, spread, head, family, diagnostics, index, and formatting paths have
  pull-shaped implementation surfaces.
- [x] LLB docs now define region/protocol/GPS as the semantic model.
- [x] Rename the old public pull module to region/GPS/materializer surfaces.
- [x] Rename role/spread/head/family implementation methods away from stream.
- [x] Express process definitions as regions with event protocols.
- [x] Express role definitions through region-native role protocol heads.
- [ ] Compile source-generated region machines with debug metadata.
- [x] Update code comments and tests after the implementation hard yank.
