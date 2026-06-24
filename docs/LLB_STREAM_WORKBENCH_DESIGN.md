# LLB Stream Workbench Design

LLB does not merely use streams.

LLB is a stream workbench: every workbench operation is represented as an
explicit `gen,param,state` machine, and higher-level APIs are named projections
of that machine model.

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

The stream model is the common runtime substrate for:

- language processes
- source/value walkers
- role normalization
- fragment and spread expansion
- staged head construction
- family projection
- diagnostics
- indexing
- formatting
- generated LuaJIT runtime code

There is no second execution model.

```text
no coroutine process runtime
no implicit process event queue
no reflective walker that bypasses streams as its primary semantics
no compatibility path that lets old coroutine-shaped code survive quietly
```

Reflective code may still exist, but it is a stream interpreter. Compiled code is
a specialized stream machine.

## Core Law

The stream is the architectural representation of work.

It is not a convenience iterator layered over an eager compiler. It is the
demand boundary:

```text
consumer asks for next item
  -> producer computes exactly enough work for that item
  -> producer returns next_state plus payload
```

That means LLB should not eagerly build an intermediate representation just
because a phase exists. A tree, array, map, report, index, diagnostic list, or
backend command buffer is a materialized sink. It is valid only when that
consumer needs that complete shape.

Canonical rule:

```text
stream first
materialize only at named sinks
```

So the default compiler/workbench path is:

```text
source stream
  -> semantic stream transducers
  -> demand-driven consumer
```

not:

```text
source
  -> eager table
  -> eager normalized table
  -> eager diagnostics table
  -> eager index table
  -> consumer
```

Every LLB runtime operation should answer:

```text
what source stream do I consume?
what stream events do I emit?
what sink materializes the result?
what generated machine can replace this reflective machine?
what metadata maps this machine back to LLB semantics?
```

The architectural shape is:

```text
Lua source
  -> Lua values
  -> source streams
  -> semantic stream transducers
  -> sinks/materializers
```

## Materialization

Materialization is explicit architecture, not an implementation accident.

A materializer is allowed when:

```text
the downstream ABI requires a complete buffer
the consumer asks for a report/result object
the optimizer needs a whole graph proof
the user explicitly collects a stream
the backend needs a flat command array
```

The materializer must be visible in the API or local code shape:

```lua
llb.stream.collect.array(gen, param, state)
llb.stream.sink.fold(fn, init)
llb.stream.sink.drain(fn)
process:result()
```

Forbidden hidden materialization:

```text
implicit process event queues
coroutine yield buffers
normalizers that silently build side products
tooling walkers that collect everything before emitting the first event
```

Single-step streams are still streams, but they mark a real boundary:

```text
monolithic external compiler call
FFI/backend call that requires a full input value
legacy algorithm not yet decomposed into semantic transducers
```

Those boundaries should shrink over time. They must not grow into the normal
LLB style.

## Stream ABI

The canonical ABI is:

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

`param` is the immutable machine closure:

```text
grammar constants
compiled role/head metadata
upstream generators
hook functions
source handles
debug maps
```

`state` is the explicit continuation:

```text
cursor
counters
nested stream states
buffers
stage index
diagnostic replay token
```

Payloads are semantic data:

```text
raw values
normalized items
fields
variants
nodes
diagnostics
index facts
format tokens
process events
trace frames
```

Hot paths may use compact payloads. Boundaries may inflate payloads to explicit
event envelopes.

## Event Envelope

The generic stream event envelope is:

```lua
{
  __llb_tag = "StreamEvent",
  lane = "value" | "diagnostic" | "index" | "format" | "trace" | "result",
  kind = "item" | "field" | "slot" | "node" | "error" | "...",
  value = value,
  origin = origin,
  meta = meta,
}
```

Not every internal stream has to allocate this table. The envelope is the
boundary representation for tooling, diagnostics, process events, and trace
mode.

Fast path:

```text
compact payload
```

Debug/tooling path:

```text
full event envelope
```

## Sources

Every raw authoring shape becomes a source stream.

```lua
llb.stream.source.value(v)
llb.stream.source.array(t)
llb.stream.source.record(t)
llb.stream.source.fragment(f)
llb.stream.source.zone(z)
llb.stream.source.family_bundle(b)
llb.stream.source.stage(stage)
```

Array source:

```text
{ a, b, _(fragment) }
  -> item(a)
  -> item(b)
  -> spread(fragment)
```

Record source:

```text
{ x = 1, y = 2 }
  -> field("x", 1)
  -> field("y", 2)
```

Family source:

```text
FamilyBundle
  -> zone(member="moonlift.dsl", items=...)
  -> zone(member="llpvm.dsl", items=...)
```

## Transducers

A transducer consumes one stream and returns another stream:

```lua
transduce(ctx, gen, param, state) -> out_gen, out_param, out_state
```

LLB transducers include:

```text
role normalizer
fragment/spread expander
head slot machine
family projector
diagnostic checker
indexer
formatter
process implementation
```

A sink materializes a stream:

```lua
llb.stream.collect.array(gen, param, state)
llb.stream.collect.map(gen, param, state)
llb.stream.sink.drain(fn)
```

The sink is the only place where a stream becomes an intermediate
representation.

## Roles

A role is semantically a stream transducer.

```text
raw stream
  -> role stream
  -> sink
```

Examples:

```text
array role:
  raw item stream -> normalized item stream

product role:
  raw item stream -> field stream

sum/protocol role:
  raw item stream -> variant stream

record role:
  raw field stream -> normalized field stream
```

For API ergonomics, compiled roles may expose a direct collect function:

```lua
lang.compiled.roles.params.collect(ctx, raw_value) -> table
```

But that direct function is an optimized sink over the role stream, not a
separate semantic model.

Canonical compiled role shape:

```lua
lang.compiled.roles[name] = {
  stream = role_stream_fn,
  collect = role_collect_fn,
  meta = role_meta,
}
```

## Fragments And Spreads

Fragments are role-tagged streams:

```lua
{
  __llb_tag = "Fragment",
  role = "decls",
  source = stream_source,
}
```

A spread is stream splice syntax:

```text
spread(fragment)
  -> check role
  -> inline fragment stream

spread(table)
  -> source stream
  -> normalize through current role
  -> inline normalized stream
```

Compiled spread expanders are per-role splice machines.

```lua
lang.compiled.spreads.decls.stream(ctx, spread) -> gen,param,state
```

## Heads

A head is a deterministic stream state machine over channel events.

```lua
fn. add { a [i32] } [i32] { ret(a) }
```

Produces:

```text
index:name(add)
call:table(params)
index:type(i32)
call:table(body)
```

The head machine consumes the event stream:

```text
state 0 expects name
state 1 expects params
state 2 expects optional result or body
state 3 expects body
done emits node
```

Canonical compiled head shape:

```lua
lang.compiled.heads.fn = {
  stream = head_stream_fn,
  construct = fast_metamethod_head,
  meta = head_meta,
}
```

The public Lua metamethod path is a specialized sink over the same head stream.

Bad-slot paths replay through the reflective stream interpreter using generated
debug metadata.

## Processes

A process is a named stream program.

Canonical definition:

```lua
local records = llb.process. records {
  stream = function(ctx, bytes)
    return gen, param, state
  end,
}
```

The function-call shorthand is allowed only because the function itself is a
stream factory:

```lua
local records = llb.process. records (function(ctx, bytes)
  return gen, param, state
end)
```

Process context helpers create events. They do not yield and do not enqueue.

```lua
ctx:event("header", payload)      -> ProcessEvent
ctx:diagnostic(spec)              -> ProcessEvent
ctx:make_event("record", payload) -> ProcessEvent
```

The generator returns those events explicitly:

```lua
return next_state, ctx:event("header", payload)
```

There is no coroutine backend and no hidden queue.

Process result values are final materializations. A process may emit many
events lazily and then emit one `result` event containing a report. That report
does not justify precomputing the earlier event stream.

## Diagnostics

Diagnostics are a stream lane.

```text
semantic stream
  -> diagnostic transducer
  -> diagnostic events
  -> diagnostic sink
```

Generated fast paths should not allocate diagnostics on success. Failures call a
diagnostic replay function that uses debug metadata to recover:

```text
generated function
generated line
language
role/head/slot
grammar origin
user origin
reflective replay function
```

## Debug Metadata

Every generated stream machine must be registered:

```lua
llb.codegen.register(fn, {
  id = "Moonlift.head.fn.v3",
  kind = "head",
  language = "moonlift.dsl",
  head = "fn",
  source_name = "@llb.codegen/moonlift/head/fn/v3",
  source_text = generated_source,
  line_map = line_map,
  origin = grammar_origin,
  reflective = reflective_stream_fn,
})
```

Required answers:

```text
what semantic object am I?
what grammar object generated me?
what source line produced me?
how do I replay reflectively?
```

LuaJIT `debug` is used only for metadata recovery, tracing, profiling, and
failure paths. Hot success paths carry compact ids or no diagnostic objects.

## Families

Families are stream routers.

Input:

```text
plain table
zone
family bundle
member-owned value
fragment
```

Output:

```text
member event stream
```

Compiled family projectors are generated from the family contract:

```lua
family.compiled.project.moonlift(gen,param,state)
family.compiled.project.llpvm(gen,param,state)
family.compiled.project.all(gen,param,state)
```

No generic recursive table walker should be the primary path.

## Codegen

LLB codegen compiles stream graphs.

```text
source
  -> spread expansion
  -> role normalization
  -> head construction
  -> diagnostics/index/format
  -> sink
```

Output is always GPS-shaped:

```lua
return function(param, state)
  ...
end
```

Even when the public API is a callable head, the implementation is either:

```text
generated GPS machine
```

or:

```text
specialized sink over a GPS machine
```

## Public Surface

Canonical stream module:

```lua
llb.stream.from.*
llb.stream.spec.*
llb.stream.op.*
llb.stream.sink.*
llb.stream.collect.*
llb.stream.compile(plan)
llb.stream.run(plan)
```

Canonical process:

```lua
llb.process. name {
  stream = function(ctx, ...)
    return gen, param, state
  end,
}
```

Canonical compiled roles:

```lua
lang.compiled.roles[name].stream
lang.compiled.roles[name].collect
```

Canonical compiled heads:

```lua
lang.compiled.heads[name].stream
lang.compiled.heads[name].construct
```

## Removed Model

Removed:

```text
coroutine process backend
ctx.event as implicit yield/queue
event-array process bodies as the normal implementation style
ad hoc walkers as primary semantics
normalizers that are not stream transducers or stream sinks
family projectors that bypass stream routing
formatter/indexer dispatch as non-stream primary path
```

Allowed temporarily only as reference during migration:

```text
reflective stream interpreter
reflective diagnostic replay
```

## Completion Checklist

- [x] GPS stream ABI.
- [x] Stream module surface: live streams, specs, ops, sinks, collectors.
- [x] Process handles run GPS streams.
- [x] Process context has no implicit queue.
- [x] All in-tree processes return explicit GPS streams.
- [x] Byte inspection, validation, LSP document events, and debugger commands are pull-shaped.
- [x] Monolithic compiler/phase boundaries are named materializing stream boundaries.
- [ ] Role normalizers expose stream and collect forms.
- [ ] Spread expanders expose stream splice forms.
- [ ] Head machines expose stream and construct forms.
- [ ] Family projectors are stream routers.
- [ ] Diagnostics/index/format run as stream transducers.
- [ ] Codegen emits registered GPS machines for hot paths.
