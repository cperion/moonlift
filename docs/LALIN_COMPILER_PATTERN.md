# Lalin Compiler Pattern

Interactive software as a live compiler, expressed in Lalin's own design
vocabulary: products, protocols, regions, blocks, emits, facts, phases, caches,
and sealed execution loops.

---

## 1. The claim

Every interactive program is a compiler.

A user does not author machine instructions. They author intent: a document, a
patch, a graph, a scene, a spreadsheet, a UI tree, a song. The machine cannot
execute intent directly. It needs narrower facts: draw commands, audio schedules,
bytecode, resolved references, layout boxes, buffer bindings, driver calls.

So every serious interactive system contains the same hidden machine:

```text
authored intent -> derived facts -> execution loop
```

The compiler pattern says: stop hiding that machine. Make it the architecture.

```text
poll input
  -> apply event to source product
  -> run memoized phases over source
  -> pull flat facts in one loop
  -> perform effects only at the seal
```

In conventional phrasing:

> Interactive software is a live compiler from authored intent to executable
> facts. It is incremental because unchanged products keep their identity. It is
> fast because phases are memoized. It is simple because the only thing that
> executes is a loop over facts.

In Lalin phrasing:

> The user-authored model is a product forest. Events are input facts.
> Application is a region. Each phase is a typed derivation from products to
> facts, exposed as an iterator protocol. The final loop is a sealed function
> that consumes facts and touches the world.

The genius of the pattern is not "use an ASDL" or "cache some callbacks". The
genius is the separation of knowledge:

```text
source products     what the user authored
application region  how events produce the next source
phases              what new facts are known at each boundary
iterators           how facts flow without intermediate collections
cache               structural reuse of already-known facts
loop                the only imperative consumer
seal                the only place effects escape
```

Lalin makes that separation typed.

---

## 2. The source is a language

The source model is not a data dump. It is the input language of the live
compiler.

The user is the programmer. The UI is the editor. Each gesture is a source edit.
Save/load stores programs in this domain language. Undo restores previous source
roots. Phases compile those roots into narrower facts.

A good source language has the same virtues as any programming language:

- clear nouns
- explicit choices
- orthogonal features
- no derived truth mixed with source truth
- typed references instead of string keys
- enough information to reproduce the user's intent
- no backend scaffolding that the user did not author

Lalin source products should say what exists together:

```lalin
struct TrackId
    value: u32,
end

struct ClipId
    value: u32,
end

struct TrackRef
    kind: u8, -- owned by visit_track
    index: u32,
end

struct Project
    tracks: view(TrackRef),
    tempo_bpm: f64,
    transport: TransportState,
    selection: SelectionRef,
end
```

Fields are products. They coexist. They use commas.

Choices are different. A runtime "or" is not a field list. In Lalin, every
semantic "or" is presumed to be a protocol until proven otherwise.

```lalin
region visit_track(store: ptr(ProjectStore), t: TrackRef;
    audio(track: ptr(AudioTrack))
  | midi(track: ptr(MidiTrack))
  | invalid(code: i32))
```

Alternatives are sums. They use `|`.

This product/sum split is the whole style:

```lalin
struct Product
    a: A,
    b: B,
end

union StoredSum
    one(x: X)
  | two(y: Y)
end

region ControlSum(input: Product;
    one(x: X)
  | two(y: Y))
```

A named product can stand in product-list position, and a named sum can stand in
protocol position:

```lalin
struct Input x: i32, y: i32 end
union Output ok(v: i32) | err(code: i32) end

func f(Input): i32
    return x + y
end

region r(Input; Output)
```

This is coherent because `Input` expands to product fields and `Output` expands
to sum alternatives. Use it when the named product or protocol is a real shared
concept; keep signatures inline when the vocabulary is local.

Use `union` only when the choice itself must be stored, queued, serialized, or
cached as a value, or when you intentionally name a reusable protocol vocabulary.
If the choice is consumed immediately and not reused, it is control, not data:
make it an inline region protocol.

---

## 3. Events are source edits, not callbacks

Input is often modeled as callback code:

```text
on_key(fn)
on_mouse(fn)
on_parameter(fn)
```

That hides architecture in a registry. Lalin wants input as facts and
application as a typed region.

```lalin
struct EventRef
    kind: u8, -- owned by dispatch_event
    index: u32,
end

struct PointerMove
    x: f32,
    y: f32,
    buttons: u32,
    mods: u32,
end

struct KeyPress
    key: u32,
    mods: u32,
end

struct ParameterEdit
    target: u32,
    value: f32,
end

region dispatch_event(input: ptr(InputStore), e: EventRef;
    pointer_move(e: ptr(PointerMove))
  | key_press(e: ptr(KeyPress))
  | parameter_edit(e: ptr(ParameterEdit))
  | invalid(code: i32))
```

Then application is the pure state transition:

```lalin
region apply_event(store: ptr(AppStore), root: RootRef, e: EventRef;
    changed(next: RootRef)
  | unchanged
  | rejected(code: i32))
```

This is the compiler pattern's `Apply : (state, event) -> state`, but unboxed:
`changed`, `unchanged`, and `rejected` are control outcomes, not a result object.

Keep `apply_event` pure. It should produce the next source root, not draw, play,
allocate GPU buffers, or call plugins. Effects belong at the final seal.

Purity buys the live compiler its leverage:

- undo is previous roots
- redo is future roots
- tests are source + event -> source
- structural sharing preserves unchanged identities
- unchanged identities preserve phase cache hits

---

## 4. Phases are knowledge boundaries

A phase exists because a question has been answered.

Bad phase boundaries follow time:

```text
load -> prepare -> process -> finish
```

Good phase boundaries follow knowledge:

```text
source widgets
  -> measured widgets       -- how big is each thing under constraints?
  -> positioned draw facts   -- where does each thing go?
  -> backend commands        -- what does the renderer consume?
```

Each boundary changes vocabulary. If the vocabulary did not change, you probably
made a temporal step, not a phase.

A phase has a product input and a fact output:

```text
phase(input product, context product) -> fact stream
```

Context matters. A widget's measured size is not only a fact about the widget; it
is a fact about the widget under constraints.

```lalin
struct LayoutConstraint
    avail_w: f32,
    avail_h: f32,
end

struct Measure
    w: f32,
    h: f32,
    baseline: f32,
end

struct MeasureKey
    widget: WidgetRef,
    constraint: LayoutConstraint,
end
```

If a derived fact changes when a context fact changes, that context fact belongs
in the phase key. Otherwise the cache will lie.

---

## 5. Phases are iterators

The inspiration document's deepest implementation insight is this:

> A phase is a fact-gathering iterator, not a function returning a collection.

In Lua terms, every iterator decomposes into three roles:

```lua
local gen, param, state = phase(source)
while true do
    local next_state, fact = gen(param, state)
    if next_state == nil then break end
    state = next_state
    consume(fact)
end
```

- `gen` is the step machine
- `param` is the invariant environment
- `state` is the cursor

Lalin should express the same split as products and protocols:

```lalin
struct DrawIter
    phase_id: u32,
    node: WidgetRef,
    constraint: LayoutConstraint,
    cursor: u32,
end

struct DrawFactRef
    kind: u8, -- owned by visit_draw_fact
    index: u32,
end

region draw_start(ctx: ptr(RenderCtx), root: WidgetRef, c: LayoutConstraint;
    ready(it: DrawIter)
  | unsupported(code: i32)
  | invalid(code: i32))

region draw_next(ctx: ptr(RenderCtx), it: DrawIter;
    fact(f: DrawFactRef, next: DrawIter)
  | done
  | invalid(code: i32))
```

The final loop consumes `draw_next`:

```lalin
region visit_draw_fact(store: ptr(DrawStore), f: DrawFactRef;
    push_transform(x: f32, y: f32)
  | pop_transform
  | rect(visual: DrawVisual)
  | text(blob: TextRef, visual: DrawVisual)
  | invalid(code: i32))
```

The loop knows only fact vocabulary. It does not know widget vocabulary. That is
the separation: source tree on one side, flat facts on the other.

---

## 6. Why iterators are the right phase surface

### 6.1 Fusion

When one phase handler invokes another phase, the inner phase returns an
iterator. The outer handler wraps or concatenates that iterator. The final loop
pulls through both. No intermediate arrays are required.

```text
Panel render = once(background) + children(render, panel.children)
```

The final loop sees one stream. The implementation may traverse many nested
handlers, but values flow directly from the deepest producer to the consumer.

### 6.2 Laziness

Nothing runs until the loop pulls. If a hit-test phase stops after the first hit,
all later subtrees stay cold. If an audio block fills early, later generators do
not run. No cancel protocol is needed; pulling simply stops.

### 6.3 O(depth) live memory

During a pull, only the path from root to current leaf is live. Completed
subtrees are cached. Future subtrees have not started. A collection-returning
pipeline tends toward O(tree size) intermediate memory; an iterator pipeline
stays proportional to traversal depth plus cache storage.

### 6.4 Cache hits are just iterators

On cache hit, the phase returns an iterator over cached facts. On miss, it
returns a recording iterator. The consumer sees the same protocol either way.
That is why caching can be transparent.

---

## 7. Recursion is flattening

This is the other key insight from the original compiler-pattern document:

> Recursion is not a traversal problem to solve later. Recursion is iterator
> nesting, and iterator nesting is what flattens trees into streams.

A phase calls itself on children:

```text
render(panel) = once(panel_background) + children(render, panel.children)
```

Each child call returns an iterator. `children` maps the phase over child refs
and concatenates the returned iterators. The final loop pulls through that nested
structure and sees one flat stream of facts. There is no separate flattening pass.
The recursion *is* the flattening.

In Lalin terms, a recursive phase is a family of iterator products and
protocols whose `next` machine may enter child iterators before resuming parent
state:

```lalin
struct RenderIter
    node: WidgetRef,
    child_index: index,
    child: ChildIterRef,
    state: u8,
end

region render_next(ctx: ptr(RenderCtx), it: RenderIter;
    fact(f: DrawFactRef, next: RenderIter)
  | done
  | invalid(code: i32))
```

The iterator state is the recursion stack made explicit. Each nested child
iterator is also a cache boundary. Unchanged subtrees replay as cached streams;
changed subtrees record fresh streams; the consumer cannot tell which occurred.

### 7.1 Functions give recursion its stack for free

This is the region/function seam, and it is mechanical, not stylistic.

A recursive phase handler is packaged as a function. A function call allocates a
stack frame. That frame stores the continuation of the parent computation for
free:

```text
emit my pre-fact
call child phase          -- child gets its own frame
resume here automatically -- parent frame was the stack
emit my post-fact
```

That "resume here" is the whole trick. If the process is written as one giant
flat region or dispatcher with a tag field and a program counter, the call stack
is gone. You must invent the stack yourself: a product containing frames, cursors,
program counters, child indices, pending post-actions, and whatever else the
parent would have remembered naturally.

So the seam is:

```text
function = product-to-product call boundary; gives stack frames for recursion
region   = product + protocol control graph; gives zero-cost local composition
```

Use **functions** where recursion needs a stack. Use **regions** inside that
recursive step to express decisions, outcomes, and local CFG composition. If you
need a recursive process to be suspendable, cacheable, serializable, or replayed
as a fact stream, reify the necessary part of the stack as an iterator product —
but understand that you are now paying explicitly for what function calls gave
for free.

The compiler-pattern stack is therefore:

```text
recursive descent stack  -> ordinary function calls
stream suspension state  -> iterator products
local branching          -> region protocols
sub-machine composition  -> emit/fill wiring
```

Do not flatten recursive structure into a hand-written dispatcher unless you
really want to own the stack product yourself.

### 7.2 The canonical push/pop form

Containment flattens to push/pop markers around child streams:

```text
render(Clip) = PushClip + children(render, Clip.children) + PopClip
render(Rect) = Rect
```

The loop sees:

```text
PushClip(800, 600)
Rect(...)
Rect(...)
PopClip
```

The tree disappeared. What remains is a linear fact stream with structured
markers.

### 7.3 State is a stack

When containment linearizes to push/pop, the execution state is naturally a
stack: transform stack, clip stack, style stack, scope stack. Position and
context flow through the loop's stack, not through every cached fact.

That matters for caching. If facts contain absolute positions, a sibling's size
change invalidates every later sibling. If facts are local and wrapped in
`push_transform(x, y) ... pop_transform`, unchanged child facts still hit cache;
only the parent's transform facts change.

### 7.4 Layers are not recursion classes

Do not create one phase per recursive type family just because the source is
recursive. Iterator nesting already handles recursion.

Layers exist where vocabulary changes:

```text
Widget source     what did the user author?
Layout facts      what size/position was resolved?
Draw facts        what should the renderer consume?
```

A single phase may recurse through several type families if they answer the same
question. Split phases only when the intermediate vocabulary earns its existence:
it enables reuse, independent caching, clearer ownership, or a real knowledge
boundary.

### 7.5 Sub-phases, not passes

Parent and child questions often depend on each other: a parent needs child
sizes, while a child size depends on parent constraints. Do not think in global
passes. Think in sub-phases with explicit keys:

```text
measure(node, constraint) -> Measure
render(node, constraint)  -> DrawFact stream
```

A render handler calls `measure(child, width)` when it needs child sizes. If that
measurement is cached, the "first pass" is one lookup. If not, only that subtree
is measured. The traditional passes interleave lazily, driven by demand.

---

## 8. How to implement the cache

This is the mechanical heart of the compiler pattern.

### 8.1 Cache keys

A phase cache key must include every fact that can affect the output:

```lalin
struct PhaseKey
    phase_id: u32,
    input_kind: u32,
    input_index: u32,
    input_generation: u64,
    context_hash: u64,
end
```

In a PVM-style implementation, structural identity can replace explicit hashes:
if products are interned, immutable ASDL values, the key can be the tuple of
phase identity and product identities. But the rule is the same: if changing a
thing can change the facts, that thing is part of the key.

Good key ingredients:

- phase id or function identity
- source product identity
- context product identity
- factory specialization parameters
- target/platform facts when they affect output

Bad key ingredients:

- mutable global state
- callback identity
- current time
- hidden options
- strings that encode meaning not represented as products

If those affect output, make them explicit context products.

### 8.2 Cache entry states

A robust cache needs at least three states:

```lalin
union CacheEntryState
    empty
  | recording(buffer: CacheBufferRef)
  | ready(buffer: CacheBufferRef, count: index)
end
```

`recording` matters for sharing: if two consumers request the same phase result
while the first is still being drained, the second can read from the in-flight
recording rather than recomputing.

Optional states are useful in production:

```lalin
union CacheEntryStateEx
    empty
  | recording(buffer: CacheBufferRef)
  | ready(buffer: CacheBufferRef, count: index)
  | failed(code: i32)
  | poisoned(generation: u64)
end
```

Use `failed` only for deterministic phase failures. Do not cache transient I/O
unless the I/O result is itself an explicit input product.

### 8.3 Miss path

On miss:

1. Allocate a recording buffer.
2. Mark entry `recording`.
3. Run the phase handler lazily as the consumer pulls.
4. Append each yielded fact to the buffer before returning it downstream.
5. If the iterator reaches `done`, commit `ready(buffer, count)`.
6. If the iterator stops early, abandon or keep a partial recording as
   implementation policy, but do not advertise it as a full ready cache entry.

The essential invariant:

```text
only full iteration commits a complete cache entry
```

This avoids a subtle bug: early consumers should not make later consumers believe
a phase has no more facts.

### 8.4 Hit path

On hit, return a simple iterator over the cached buffer:

```lalin
struct SeqIter
    buffer: CacheBufferRef,
    index: index,
    count: index,
end

region seq_next(cache: ptr(PhaseCache), it: SeqIter;
    fact(f: FactRef, next: SeqIter)
  | done
  | invalid(code: i32))
```

The hit path should be boring: bounds check, load fact, increment index. That is
why it JITs well and why cache hits become cheap enough to use per frame.

### 8.5 In-flight sharing

If an entry is `recording`, a second consumer should not recompute. It should
attach as a reader.

```lalin
struct RecordingReader
    buffer: CacheBufferRef,
    index: index,
end
```

Reader behavior:

- if requested index is already recorded, replay it
- if requested index is not yet recorded and producer is still active, pull the
  producer until the fact exists or the producer finishes
- if producer finishes, observe `ready`
- if producer fails, observe the same failure

This is how two parents can share one child phase during the same drain.

### 8.6 Invalidation by structural identity

Do not walk the old tree and delete cache entries by hand. Prefer immutable,
interned products.

When an edit creates a new root:

- changed nodes get new identities
- unchanged nodes keep old identities
- phase keys for unchanged nodes still hit
- phase keys for changed nodes miss

Invalidation becomes a consequence of identity, not a separate algorithm.

If you cannot intern everything, use explicit generation fields on stable refs:

```lalin
struct NodeRef
    index: u32,
    generation: u64,
end
```

A cache key containing `(index, generation)` naturally misses when the node is
replaced.

### 8.7 Determinism requirement

A phase handler must be pure with respect to its key.

```text
same phase id + same input product + same context product => same facts
```

If a handler reads hidden mutable state, caching becomes unsound. If it depends
on time, random numbers, device state, or file contents, those facts must be
explicit inputs or the phase must be sealed as an effectful boundary and not
memoized as a pure phase.

### 8.8 Diagnostics

A real implementation should expose cache reports:

```text
phase name
calls
hits
misses
shared in-flight reads
recorded fact count
bytes retained
abandoned partial recordings
```

Without reports, caching becomes folklore. With reports, phase design becomes
measurable: if a phase misses too often, inspect its key; if it records too many
facts, inspect its boundary; if it is always consumed fully, maybe a collection is
acceptable; if it is often consumed partially, iterator laziness is paying rent.

---

## 9. Phase combinators

The iterator algebra should be closed: every combinator takes iterators and
returns an iterator.

Core combinators:

```text
once(fact)             one fact
empty                  no facts
seq(buffer)            cached facts
children(phase, view)  map phase over child refs and concatenate
concat(a, b)           run a then b
concat_all(xs)         run N iterators in sequence
map(iter, f)           transform facts
filter(iter, pred)     skip facts
take(iter, n)          stop early
flatmap(iter, f)       fact -> iterator, then flatten
```

Lalin regions can represent these as iterator state machines. Lua factories
can generate specialized iterator families for concrete fact types.

Important law:

```text
combinators must preserve lazy pull semantics
```

If `concat` eagerly drains the left iterator into an array, fusion is lost. If
`children` eagerly lowers every child, virtualization is lost. If `filter` runs
past the consumer's stop point, laziness is lost.

---

## 10. Design method

### Step 1 — State the compiler sentence

```text
This system compiles ______ authored by ______ into ______ consumed by ______.
```

Examples:

```text
The UI compiles widget products authored by gestures into draw facts consumed by
an immediate-mode renderer.

The synth compiles patch/program products and host events into scheduled voice
and audio facts consumed by the audio callback.
```

If the sentence is vague, the architecture will be vague.

### Step 2 — Harvest source products

List what survives save/load and undo. These are source products. Exclude caches,
positions, resolved refs, GPU handles, file descriptors, and backend state unless
the user actually authored them.

### Step 3 — Interrogate every "or"

For each choice:

```text
Consumed immediately?  -> region protocol
Stored for later?      -> encoded product + owning consumer region
No consumer?           -> delete it
```

### Step 4 — Define event facts

Events are the edit language. Keep them typed and closed. Avoid callbacks and
stringly command registries.

### Step 5 — Define application

Application is a pure region from `(root, event)` to one of:

```lalin
region apply_event(store: ptr(Store), root: RootRef, e: EventRef;
    changed(next: RootRef)
  | unchanged
  | rejected(code: i32))
```

### Step 6 — Find knowledge boundaries

For every proposed phase, ask:

```text
What new facts are known after this phase?
What vocabulary disappears?
What vocabulary appears?
What context changes the answer?
Who consumes the facts?
```

If no vocabulary changes, merge the phase.

### Step 7 — Give each encoded kind one owner

Every `kind: u8` comment should name an owner region:

```lalin
struct WidgetRef
    kind: u8, -- owned by visit_widget
    index: u32,
end
```

If you cannot name the owner, the tag is speculation.

### Step 8 — Design iterator protocols

Each fact stream needs a start and next protocol, or an equivalent factory that
returns an iterator product.

```lalin
region phase_start(ctx: ptr(Ctx), input: InputRef;
    ready(it: Iter)
  | invalid(code: i32))

region phase_next(ctx: ptr(Ctx), it: Iter;
    fact(f: FactRef, next: Iter)
  | done
  | invalid(code: i32))
```

### Step 9 — Seal the loop

Only the final loop performs effects:

```lalin
func render_frame(app: ptr(App), surface: ptr(Surface)): i32
```

Inside that function, immediately re-enter regions and protocols. Encode status
as integers only at the seal.

---

## 11. Compact example: UI rendering

### Source products

```lalin
struct WidgetRef
    kind: u8, -- owned by visit_widget
    index: u32,
end

struct Button
    label: TextRef,
    visual: DrawVisual,
end

struct Row
    children: view(WidgetRef),
    spacing: f32,
end

struct Root
    child: WidgetRef,
end
```

### Source consumer

```lalin
region visit_widget(store: ptr(UiStore), w: WidgetRef;
    button(b: ptr(Button))
  | row(r: ptr(Row))
  | invalid(code: i32))
```

### Measurement phase

```lalin
struct MeasureKey
    widget: WidgetRef,
    constraint: LayoutConstraint,
end

region measure_widget(ctx: ptr(UiCtx), w: WidgetRef, c: LayoutConstraint;
    ready(size: Measure)
  | invalid(code: i32))
```

### Draw phase iterator

```lalin
struct DrawIter
    widget: WidgetRef,
    constraint: LayoutConstraint,
    cursor: u32,
end

region render_start(ctx: ptr(UiCtx), w: WidgetRef, c: LayoutConstraint;
    ready(it: DrawIter)
  | invalid(code: i32))

region render_next(ctx: ptr(UiCtx), it: DrawIter;
    fact(f: DrawFactRef, next: DrawIter)
  | done
  | invalid(code: i32))
```

### Draw fact consumer

```lalin
region visit_draw_fact(store: ptr(DrawStore), f: DrawFactRef;
    push_transform(x: f32, y: f32)
  | pop_transform
  | rect(visual: DrawVisual)
  | text(t: TextRef, visual: DrawVisual)
  | invalid(code: i32))
```

### Execution law

The renderer loop calls `render_next`, then `visit_draw_fact`. It maintains
transform, clip, and backend state. It never switches on `WidgetRef.kind`. It
never calls `visit_widget`. The source vocabulary has been compiled away.

---

## 12. Compact example: audio graph scheduling

A graph authored by the user is not the thing the audio callback should execute.
The callback needs a schedule.

```lalin
struct NodeRef
    kind: u8, -- owned by visit_node
    index: u32,
end

struct GraphRef
    index: u32,
    generation: u64,
end

struct ScheduledStep
    node: NodeRef,
    input0: BufferId,
    input1: BufferId,
    output: BufferId,
end

struct ScheduleIter
    graph: GraphRef,
    cursor: u32,
end
```

Scheduling is a phase:

```lalin
region schedule_audio(ctx: ptr(AudioCtx), graph: GraphRef;
    ready(it: ScheduleIter)
  | cycle(node: NodeRef)
  | unsupported(code: i32))

region schedule_next(ctx: ptr(AudioCtx), it: ScheduleIter;
    step(s: ScheduledStep, next: ScheduleIter)
  | done)
```

The audio callback consumes `ScheduledStep`. It does not traverse source nodes,
resolve cables, discover cycles, or decide buffer allocation. Those questions
belong to phases before the seal.

---

## 13. Anti-patterns

### Callback architecture

```text
button.on_click(function() ... end)
```

Hidden control. Replace with event facts and `apply_event`.

### Result object pipeline

```text
parse() -> ParseResult -> switch later
```

Delayed control in a box. Replace with a region protocol unless the result must
be stored.

### Derived fields in source

```lalin
struct Widget
    children: view(WidgetRef),
    cached_width: f32,
end
```

If width is derived, it belongs to a measurement phase, not the source product.

### Scattered tag switches

If five files inspect `kind`, one region is missing. Name the owner protocol.

### Eager phase arrays

If every phase builds a complete array before the next begins, fusion and
laziness are gone. Use iterators unless the collection itself is a meaningful
phase output.

### Hidden context in phase handlers

If a phase reads global style, target DPI, locale, sample rate, or feature flags,
those are context products. Put them in the key.

### Effectful phases

A memoized phase must be deterministic. File I/O, GPU calls, plugin execution,
clock reads, and random numbers belong at seals or must be represented as
explicit input facts.

---

## 14. Final doctrine

```text
The source is a language.
Events are edits.
Apply is pure.
Products hold facts that coexist.
Protocols name choices consumed by control.
Stored choices are encoded products with one owner region.
Phases answer knowledge questions.
Phases return iterators, not arrays.
Functions/iterator products provide the recursion stack.
Caching is what full iteration commits.
Structural identity is invalidation.
The loop is the only execution.
Effects happen only at seals.
```

The compiler pattern is not a framework trick. It is a way to make interactive
software honest: every layer states what it knows, every choice has an owner,
every cache key is a product, every fact stream has a protocol, and every effect
is pushed to the boundary where it can be seen.
