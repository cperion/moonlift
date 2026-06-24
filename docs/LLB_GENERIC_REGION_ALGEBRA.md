# LLB Generic Region Algebra

This document defines the implemented shared region model. It is the semantic
layer underneath LLB processes, GPS pull machines, Moonlift native regions,
LLPVM phase/task machines, parsers, schedulers, diagnostics, and other
control-shaped tools.

The goal is not to rename every control thing to `region`. The goal is to give
the Moonlift family one control algebra so separate languages do not invent
overlapping machines for the same semantics.

## Core Thesis

Every reusable control machine has this shape:

```text
region = input product + state product + named exit protocol + transition body
```

The canonical type is:

```text
Region<InputProduct, StateProduct, Protocol>
```

A run step selects exactly one protocol exit.

```text
exit payloads are products
the set of exits is a sum
resumable exits carry the next state
terminal exits do not
```

This makes the old accidental categories line up:

```text
function
  sealed region with one terminal return exit

pull sequence
  region with item(next, value...) | done protocol

process
  region with event/diagnostic/done/failed protocol

parser
  region with ok/syntax/need_more protocol

Moonlift region
  typed native CFG realization of the region algebra

LLPVM phase/task
  region over worlds, tapes, events, and task runs

LuaJIT GPS
  compact lowering ABI for pull-shaped region protocols
```

## Ownership

LLB owns the generic concepts:

```text
protocol
exit
region
region metadata
materializer
lowering target
origin/debug mapping
```

The canonical authoring head is bare `region.` in LLB/family environments:

```lua
region. scan
  { p [ptr [u8]], n [index] }
  { hit { pos [index] }, miss }
  {
    -- body is a backend/member-language payload
  }
```

Dynamic/internal authoring uses the same head as a callable stage:

```lua
region("scan")["pull"] { "p", "n" } (body_fn)
```

`llb.region(name, spec)` remains the raw constructor API for tooling that
already has a descriptor product, but DSL definitions should prefer the head
syntax above.

`region [SomeType]` keeps normal LLB symbol behavior and means a typed capture
named `region`; only `region. name` starts the region head.

Moonlift owns:

```text
native typed CFG body vocabulary
entry/block/jump/emit body vocabulary
Cranelift/native backend lowering
resource and lease checking inside native CFG
```

Moonlift does not own generic region semantics. It consumes generic LLB Region
descriptors and projects them into native typed CFG declarations when the body
uses Moonlift's entry/block/jump/emit vocabulary.

LLPVM owns:

```text
worlds
tapes
phase/task images
borrowed bytecode/runtime ABI
portable VM artifacts
```

GPS owns:

```text
gen,param,state ABI
GPS plans
GPS source/op/materializer objects
LuaJIT-oriented pull lowering
```

No language should re-own the generic concept of a resumable control machine.
Languages may own domain names for specializations. For example, LLPVM may own
`tape`, Moonlift may own native `block`, and LLB owns generic `region`.

## Protocols

A protocol is a named sum of exits.

```text
protocol Pull<T>:
  item { next: State, value: T }
  done

protocol Process<E, R>:
  event { next: State, ev: E }
  diagnostic { next: State, diag: Diagnostic }
  done { result: R }
  failed { err: Diagnostic }
```

Exit names are semantic, not status strings. A protocol exit must say what
happened in the domain.

Bad:

```text
event { kind = "error", value = ... }
```

Better:

```text
failed { err: Diagnostic }
diagnostic { next: State, diag: Diagnostic }
```

The difference matters:

```text
failed
  terminal failure

diagnostic
  resumable observation
```

## Exit Classes

Each exit has a control class.

```text
resumable
  carries next state; caller may continue the same region run

terminal
  ends the region run successfully or neutrally

failure
  terminal failure; diagnostics/error policy applies

blocking
  resumable or suspended; caller decides when to retry

effect
  semantically observable exit such as diagnostic, progress, trace, write
```

Class is not just documentation. It controls lowering and materialization.

```text
GPS lowering
  can directly encode one productive resumable exit plus terminal done

process lowering
  can encode many resumable event-like exits as ProcessEvent values

native CFG lowering
  must preserve named exits as continuation targets

LLPVM lowering
  must map exits to task events, result records, or VM status transitions
```

## Products

Inputs, states, and exit payloads are products.

A product must have one owner:

```text
LLB generic product
  role/protocol metadata and structural composition

MoonSchema/ASDL product
  persistent typed compiler/runtime value

Moonlift product
  native ABI/product typed value

LLPVM product
  bytecode image/runtime product
```

The same semantic product can be projected into several owners, but the family
must know which projection is canonical at each boundary.

Rule:

```text
If two languages can express the same product or sum semantics, one is the
canonical owner and the other is a projection/lowering.
```

This prevents duplicated product/sum languages inside the family.

## Region Metadata

Every region-shaped object needs enough metadata to answer:

```text
what region is this?
what protocol does it implement?
which exits are terminal/resumable/failure/blocking/effect?
what input product does it consume?
what state product does it carry?
which language/family owns it?
what origin created it?
what lowering target currently implements it?
how do diagnostics replay reflectively?
```

Minimum metadata:

```text
id
name
owner
input_product
state_product
protocol
body_kind
origin
lowerings
debug_map
```

Body kind can be:

```text
reflective Lua closure
GPS plan
Moonlift CFG
LLPVM phase/task graph
generated LuaJIT source
foreign callable
```

## Lowering Targets

A lowering target is not the semantic object. It is a way to run or materialize
a region.

### GPS Lowering

GPS is valid when a protocol can be represented as:

```text
productive resumable exit -> return next_state, payload...
terminal done             -> return nil
```

For protocols with multiple productive exits, GPS must either:

```text
encode exit id in payload
specialize to one selected exit class
lower through process/event protocol
or reject the lowering
```

No implicit loss of exit identity is allowed.

### Process Lowering

Process lowering is valid when protocol exits are observable workbench events.

```text
event/diagnostic/progress/index/trace
  -> ProcessEvent payload

done(result)
  -> result event or handle result

failed(err)
  -> failed status with diagnostic
```

Process lowering must preserve:

```text
event order
origin
diagnostic bag behavior
budget/cancellation behavior
result value
failure value
```

### Moonlift Native Lowering

Moonlift lowering is valid when input/state/exit payload products have native
types and the body can be expressed as typed CFG.

The mapping is:

```text
generic region input product
  -> Moonlift region params

generic protocol exits
  -> Moonlift continuation protocol

generic state product
  -> block params / carried loop state

generic emit composition
  -> Moonlift emit continuation wiring
```

Moonlift native lowering must preserve resource rules:

```text
owned values discharge exactly once
leases do not escape invalidly
continuation payload restrictions are respected
every path terminates by jump/emit/return
```

### LLPVM Lowering

LLPVM lowering is valid when the region belongs to a portable compiler/runtime
machine.

The mapping is:

```text
input product
  -> world/tape/task input

state product
  -> VM state, task run, or phase cursor

protocol exits
  -> task events, phase output world, diagnostics, result records
```

LLPVM should not re-invent region semantics. It should project generic regions
into portable VM artifacts.

## Composition

Region composition is exit wiring.

```text
emit child_region(input)
  child.exit_a -> local continuation A
  child.exit_b -> local continuation B
```

This is the same idea behind:

```text
Moonlift emit
parser combinators
pull map/filter/take fusion
process pipelines
scheduler retries
diagnostic/index walkers
```

Composition must be checked against protocol compatibility.

Compatibility requires:

```text
the child input product can be constructed
every required child exit is handled
handled exit payloads match the receiving products
resumable/terminal classes are preserved or explicitly transformed
failure exits are not silently dropped
diagnostic exits are not silently materialized away
origins/provenance compose
```

## Adapters

Adapters are explicit region transformers.

Examples:

```text
map
  Pull<A> -> Pull<B>

filter
  Pull<A> -> Pull<A>

collect
  Pull<A> -> terminal array result

as_process
  Protocol P -> ProcessEvent protocol

as_gps
  Pull protocol -> GPS lowering

as_native
  typed region -> Moonlift CFG lowering
```

Adapters must declare what they do to each exit:

```text
preserve
rename
map payload
materialize
drop with proof
turn into failure
```

Dropping an exit without a proof is illegal.

## Materializers

Materializers consume protocol exits into complete values.

Examples:

```text
Pull.item* + done
  -> array

Diagnostic* + done
  -> DiagnosticBag

FormatChunk* + done
  -> string

BackCmd* + done
  -> flat backend command buffer
```

Materialization is explicit and local. It is not the default representation.

This preserves the pull property:

```text
region run computes only demanded exits
materializer decides when all exits are needed
fusion may remove intermediate payloads
early stop is legal when the protocol/materializer allows it
```

## Effects As Exits

Effects should be modeled as protocol exits when they affect control or
observability.

```text
diagnostic
progress
blocked
need_more
retry
write
trace
failed
```

This is more concrete than effect annotations because the payload and control
class are checked.

Effects that are only implementation details may remain inside a lowering, but
they cannot affect semantic results.

## Diagnostics

Diagnostics are protocol exits and/or failure payloads.

Rules:

```text
diagnostic exit
  resumable observation

failed exit
  terminal failure

reflective replay
  mandatory for generated fast paths that cannot build rich diagnostics inline
```

Generated or lowered regions must carry debug metadata:

```text
region id
protocol id
exit id
source origin
generated source name
line map
reflective fallback
local payload names if needed
```

This keeps fast paths small without making diagnostics blind.

## Origins And Provenance

Origins attach to:

```text
region declaration
protocol declaration
exit declaration
input/state/product fields
body nodes
lowered generated functions
materializer sites
composition edges
```

When composing regions, provenance is a stack, not one nearest comment.

Diagnostic renderers should be able to show:

```text
user source that authored the region
grammar source that declared the role/head/protocol
generated source that failed
composition edge that wired the exit
semantic comments attached along the path
```

## Cancellation, Budget, And Blocking

Cancellation and budget are control exits, not hidden side effects.

A process-style region may expose:

```text
budget_exhausted { next, remaining }
cancelled
blocked { next, reason }
```

GPS lowering may implement budget by checking counters in state, but the
semantic outcome should still be represented as an exit when the caller can
observe it.

## Type Interoperability

Region algebra depends on family symbol/type interoperability.

Rules:

```text
types inside [] are Lua values
ASDL/MoonSchema types are first-class values
symbols carry semantic identity across family members
namespaces prevent accidental collisions
families define which type/protocol symbols are shared
```

A generic region should not use stringly type names. It should refer to the same
type values the rest of the family uses.

## Equality And Identity

Region identity has two layers:

```text
semantic identity
  owner + name + protocol + product shapes

lowering identity
  backend + generated version/hash + target options
```

Two lowerings may be equivalent for the same region. They are not the same
object.

Caching keys must include:

```text
region semantic id
input/state/protocol type ids
lowering target
relevant backend options
dependent family version/hash
```

## Naming Rules

Use:

```text
region
protocol
exit
materializer
gps
tape
lane
phase
task
process
parser
```

Do not use `stream` as an LLB architectural category.

The word is still acceptable when it literally names an external domain thing:

```text
byte stream
token stream
file stream
UI render stream
network stream
```

Inside LLB semantics, use protocol names instead:

```text
pull protocol
event protocol
chunk protocol
fact protocol
```

## Implementation Shape

The implementation should move in this order.

1. Add protocol descriptors.
2. Add region descriptors.
3. Re-express existing LLB role/process/format/index GPS machines as regions.
4. Add adapter/materializer descriptors.
5. Add lowering registry: reflective, GPS, process, Moonlift, LLPVM.
6. Add debug metadata and reflective replay hooks.
7. Add checks for exit coverage and exit class preservation.
8. Add family integration and namespace policy.
9. Add source-generated GPS codegen from region plans.
10. Add Moonlift and LLPVM projections only after the generic descriptors are
    complete.

Do not start by adding backend-specific shortcuts. The generic semantic object
must exist first.

## Semantic Interaction Checklist

Before accepting a new region/protocol feature, answer:

```text
Who owns this semantic concept?
Is this a new concept or a projection of an existing one?
What protocol exits exist?
Which exits are terminal, resumable, failure, blocking, or effect exits?
What are the input, state, and exit payload products?
Are those products canonical or projected?
Can it lower to GPS without losing exit identity?
Can it lower to Moonlift native CFG?
Can it lower to LLPVM phase/task form?
What materializers are legal?
What exits can be fused?
What exits may be dropped, and what proof allows it?
How are diagnostics represented?
How are origins and comments preserved?
How does cancellation/budget interact?
What type values are referenced through []?
What is the cache key?
What family namespace owns the exported names?
```

If any answer is unclear, the design is not ready for implementation.
