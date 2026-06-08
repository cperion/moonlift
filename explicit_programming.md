# Explicit Programming
## A Philosophy of Systems Design

---

## Preface

This document is about a way of designing software. It has a name —
*explicit programming* — because it deserves one, and because giving it a
name makes it easier to recognize, teach, and defend.

The discipline is not new in its individual pieces. Sum types come from
ML in the 1970s. Continuation-passing style comes from Reynolds in 1972.
ASDL has been used to specify compilers for thirty years. State machines
are older than computers. What is new is the synthesis: a coherent
methodology that takes an abstract idea about a system and walks it,
step by step, into a curated set of types and a working implementation
where the types *are* the design and the design *is* the implementation.

The methodology is presented through Moonlift, a language built
specifically for explicit programming. Moonlift is not the only place
where the discipline can be practiced — many of the principles transfer
to other languages, often awkwardly — but it is the first language where
the discipline is *native* rather than retrofitted. Reading this
document, you will learn how to think in the paradigm; you will also
learn Moonlift, because Moonlift is the most direct expression of the
paradigm currently available.

This is a technical document. It is structured like a guide: short
chapters, each one a unit, each one delivering one tool. It is not a
manifesto. The claims it makes are strong, but they are grounded.

---

## Table of contents

**Part I — The paradigm**

1. What explicit programming is
2. The two structures every system has
3. Why implicit-ness is the enemy
4. Data types and continuation types
5. The dual tree

**Part II — The discipline**

6. From idea to types: the procedure
7. Finding the data types
8. Finding the control types
9. The unified rule: one type system, two consumption modes
10. Composition
11. Metaprogramming as a design tool

**Part III — Moonlift, the medium**

12. Why Moonlift is the language of explicit programming
13. The minimal Moonlift you need
14. Regions, fragments, and emit
15. ASDL as the historical antecedent
16. What's free in Moonlift that's hard elsewhere

**Part IV — Worked examples**

17. A small example: parsing a JSON value
18. A medium example: an HTTP request lifecycle
19. A large example: designing a scheduler

**Part V — Anti-patterns**

20. Stringly-typed exits
21. Boolean returns where variants belong
22. Hidden state
23. Premature functions

**Part VI — Boundaries and implications**

24. When explicit programming doesn't apply
25. What this means for language design
26. What this means for engineering practice
27. Closing

---

# Part I — The paradigm

## Chapter 1: What explicit programming is

Explicit programming is a discipline of system design in which every
distinction that matters to the system's behavior is represented
explicitly in the source — as a typed value, a named transition, or a
declared protocol — and the compiler is given the means to check that
the representations are consistent.

The definition is more usefully stated negatively. **Explicit
programming is the refusal of implicit-ness.** Every common programming
paradigm accepts some category of meaning as implicit — hidden in
runtime dispatch, scattered across files, encoded in convention,
buried in compiler-generated state machines. Explicit programming
treats each such hiding place as a defect to be eliminated.

The defect is not aesthetic. Hidden meaning is the source of most
software complexity. When the compiler cannot see a distinction, neither
can the type checker, neither can the IDE, neither can the optimizer,
and — most importantly — neither can the human reading the code in six
months. The system's *real* behavior lives somewhere the tooling cannot
reach, and the gap between what the source says and what the system
does becomes the territory in which bugs, misunderstandings, and
maintenance disasters live.

Consider a small example: a function that authenticates a user. In a
typical language, its signature is:

```
fn authenticate(creds): Result<User, AuthError>
```

This looks explicit. It is not. The signature hides the following
distinctions:

- *Account locked* and *invalid credentials* are both `AuthError`
  variants, but the caller's handling differs: one shows "wrong
  password," the other shows "account locked until 3pm." The
  distinction is real but lives in pattern-matching code at every call
  site, not in the type.
- *Rate limited* might or might not be in `AuthError`. If it isn't, it
  becomes an exception or a side channel. If it is, the caller needs
  to know to look for it. The author of the function and the author
  of the caller may have different mental models, and the compiler
  cannot help.
- *Database error* might be encoded as an `AuthError` variant, or
  silently bubbled up through `?`, or returned as `None` and lost
  entirely. Different callers will encounter different versions of
  reality.
- The *path* through the function — did it check the password? did it
  consult the rate limiter? did it write to the audit log? — is not
  in the type. It is inferred from reading the body.

A more explicit version of the same operation declares a typed
control protocol:

```moonlift
region authenticate(
    creds: ptr(Credentials),
    store: ptr(SessionStore);

    success:             cont(user_id: u64, session_token: ptr(u8)),
    invalid_credentials: cont(),
    account_locked:      cont(unlock_at: i64),
    requires_2fa:        cont(challenge_id: u64),
    rate_limited:        cont(retry_after_seconds: i32))
```

This is a signature that declares, exhaustively, every outcome the
operation can produce and what data each outcome carries. The compiler
checks that every emit site of `authenticate` provides a destination
for every named exit. The compiler checks that the types of the
continuation parameters match. A reader of this signature knows
*everything* about what the operation can do, before reading a line of
its body. There is no remaining hidden behavior. The function is
*explicit*.

This is the core move of explicit programming. Every distinction that
matters becomes a named, typed entity in the source. The compiler is
then a *partner* in design, because the partner can see the design.

### Summary

Explicit programming makes every behaviorally-meaningful distinction
visible in the source as a typed value, a named exit, or a declared
protocol. It refuses the hiding places — runtime dispatch, exceptions,
convention, generated state machines — where meaning normally lives.
The result is source code that the compiler, the tooling, and the human
reader all see the same way.

---

## Chapter 2: The two structures every system has

Every system, regardless of size or domain, has exactly two structures
that determine its behavior. Most languages give you a type system for
one of them. Explicit programming gives you a type system for both.

The two structures are:

1. **The data structure** — what information exists in the system, what
   shapes it takes, what invariants hold over it.

2. **The control structure** — what can happen in the system, in what
   order, with what state transitions, and through what externally
   observable exits.

These are independent. A system can have rich data and simple control
(a static configuration file, a math library). It can have rich control
and simple data (a parser whose state machine has many states but whose
intermediate values are bytes). Most real systems have both rich, and
the two interact in specific ways: data flows through control
transitions, control depends on the values of data.

The history of programming language design is the history of typing the
first structure. From the integer types of FORTRAN to the dependent
types of Idris, sixty years of effort have gone into making the data
structure precise, checkable, and expressive. This effort has
succeeded. We can now describe data shapes with great precision, and
the compiler can enforce the descriptions.

The control structure received almost none of this attention. The
field of programming languages decided in the late 1960s that
structured programming — `if`, `while`, `for`, function calls — was
sufficient surface syntax for control flow, and stopped. The
mechanisms added since then (exceptions, generators, async/await,
effect systems) are workarounds for the absence of a real type system
for control. They patch specific symptoms; they do not address the
underlying gap.

The consequence is asymmetric: data is precise, control is informal.
A typical function signature in a modern language tells you what types
of values go in and one type of value comes out. It tells you almost
nothing about *what happens* between the two — how many ways the
function can exit, what those ways carry, what order the exits can
occur in, what side effects happen along the way.

Explicit programming says: control has structure, that structure is
type-able, and typing it is just as important as typing the data. The
language must support both, the compiler must check both, the designer
must specify both, and the design process must produce both as
co-equal artifacts.

In Moonlift, the two structures appear in the source with parallel
syntax:

```moonlift
-- The data structure: what things are
struct Connection
    fd: i32
    buffer: ptr(u8)
    buffer_len: i32
end

union AuthState
    unauthenticated()
    authenticated(user_id: u64)
    expired(last_seen: i64)
end

-- The control structure: what can happen
region handle_request(
    conn: ptr(Connection),
    auth: ptr(AuthState);

    completed: cont(bytes_written: i32),
    closed:    cont(),
    error:     cont(code: i32))
```

The struct declares a data shape. The union declares a sum over data
shapes. The region declares a control protocol — a set of named,
typed exits and the parameters they carry. All three are first-class.
All three are checked by the compiler. All three are how you design
this system; none of them is an afterthought.

### Summary

Every system has a data structure (what information exists) and a
control structure (what can happen). Languages have spent sixty years
typing the first one. Explicit programming requires typing both, with
equal rigor and parallel notation. The design of a system is the
co-design of these two structures.

---

## Chapter 3: Why implicit-ness is the enemy

To understand why explicit programming insists so strongly on
visibility, it helps to enumerate the places implicit meaning normally
lives, and what it costs.

**Implicit-ness in dispatch.** Object-oriented languages hide method
selection in a vtable. When code calls `x.frobnicate()`, the actual
function executed depends on the runtime type of `x`, which the source
does not name. To understand the call, the reader must determine the
possible runtime types — which may not be apparent from the local
code — and look up the implementation in each. The compiler usually
cannot tell which implementation will run, so it cannot inline, cannot
specialize, and often cannot even prove the call will not crash.

**Implicit-ness in sequencing.** Functional languages with monadic I/O
hide ordering inside the bind operator. The expression
`do x <- read; y <- write; return (x, y)` looks like a sequence, but
the actual order of effects depends on the monad's bind
implementation, which the reader must reconstruct mentally. Refactoring
that "looks safe" can rearrange effects in non-obvious ways.

**Implicit-ness in error propagation.** Exceptions are the canonical
example. A function might throw any exception its callees throw,
unless it catches them. The set of possible exit paths is not visible
in the signature. Checked exceptions tried to fix this; they were
abandoned because they did not compose. The underlying problem is that
exceptions are control flow that is not in the source.

**Implicit-ness in async state machines.** `async fn` in Rust, JavaScript,
Python, and Swift compiles into a state machine the programmer does
not write. The state machine has states (the suspension points), it
has transitions (the awaited operations), and it has data (the
captured environment). All three are real. None are in the source.
Reasoning about the actual control flow of an async function requires
mentally reconstructing the state machine the compiler generates.

**Implicit-ness in convention.** Every codebase has conventions —
naming patterns, "we always pass a context here," "errors get logged
through this object," "this function must be called before that one."
Conventions are control flow encoded in human memory. New team
members violate them. Refactors break them. The compiler cannot help.

**Implicit-ness in runtime registries.** Frameworks that "wire things
up at startup" — dependency injection, event listener registration,
plugin loading — defer to runtime what could have been specified in
source. The system's wiring graph is real, but it lives only as the
state of various tables at runtime, after the program has booted.
Diagrams of "how it all connects" become necessary documentation
because the source cannot show it.

In each case, the cost is the same:

1. The compiler cannot help, because it cannot see the structure.
2. The tooling (IDE, refactor, static analysis) cannot help, for the
   same reason.
3. The reader must reconstruct the structure mentally, which is slow
   and error-prone.
4. The optimizer must conservatively assume the worst, which leaves
   performance on the table.
5. The system's actual behavior drifts from any written description of
   it, because the actual behavior was never written down — only the
   computation that produces it was written down.

The argument of explicit programming is that these costs compound, and
that the historical reasons for accepting them — "control flow doesn't
need types," "exceptions are convenient," "vtables enable
polymorphism" — were never well-founded. They were accepted because
nobody knew how to do otherwise without paying some other cost.

The thesis of explicit programming, demonstrated by Moonlift, is that
the other cost is not necessary. You can have control flow that is
typed, dispatch that is visible, sequencing that is on the page,
errors that are in the signature, async that is just regions with
suspension points, and wiring that is structural. The historical
tradeoffs no longer apply because the techniques to avoid them now
exist.

### Summary

Hidden meaning in software has predictable costs: the compiler cannot
help, the tooling cannot help, the human reader must reconstruct what
the source omits, and the system's real behavior drifts from any
description of it. Explicit programming refuses these costs by
refusing the hiding places.

---

## Chapter 4: Data types and continuation types

To do explicit programming, you need two type systems. One for data,
one for control. This chapter introduces both at a conceptual level.
Later chapters give the methodology for arriving at the right types in
each.

### 4.1 The data type system

The data type system describes what information exists. Its primitives
are familiar:

- **Scalars**: integers, floating-point, booleans, pointers.
- **Products** (also called records or structs): aggregates of named,
  typed fields. A `struct User { id: u64, name: ptr(u8), age: i32 }`
  is a product.
- **Sums** (also called tagged unions or variants): values that are
  one of a fixed set of shapes. A `union Result { ok(i32) | err(i32) }`
  is a sum.
- **Arrays and views**: sequences of homogeneous values with bounded
  length.

The data type system answers: *what does this value look like?* It
admits checking: every operation on a value must be compatible with
the value's type, every field access must reference a real field,
every pattern match must cover all variants.

The data type system is well understood. Most modern languages have a
version of it. Moonlift's version is described in chapters 13 and 14.

### 4.2 The control type system

The control type system describes what can happen. Its primitives are
less familiar:

- **Regions**: typed control fragments with declared protocols.
- **Continuations**: named exits of a region, each carrying typed
  parameters.
- **Emits**: invocations of a region that splice its control flow
  into the caller's, filling each of the callee's continuations with
  one of the caller's blocks.
- **Blocks**: named states within a region, each with typed
  parameters, reachable by jumps.
- **Jumps**: transitions from one block to another, or from a block
  to a continuation, carrying typed arguments.

The control type system answers: *what can happen here, and where can
it go?* It admits checking: every region must declare its exits, every
emit must fill every exit with a block of matching type, every jump
must target a block that exists with parameters of matching type,
every path through a region must end at one of the declared exits
(no fallthrough, no leaks).

The control type system is the contribution of explicit programming.
It has historical antecedents (continuation-passing style, structured
operational semantics, Statecharts), but until Moonlift no language
combined it with a data type system and a native compiler. The
treatment in this document is the first time the discipline of using
it for design has been written down.

### 4.3 The parallel structure

The two type systems are structurally parallel. This parallel is
important and worth seeing clearly:

| Concept                  | Data type system               | Control type system                |
|--------------------------|--------------------------------|------------------------------------|
| Atomic unit              | Scalar value                   | Block (a named state)              |
| Composition by product   | Struct (named fields)          | Block parameters (named values held in this state) |
| Composition by sum       | Tagged union (named variants)  | Continuation set (named exits a region can take) |
| Refinement / inhabitation| Constructor: `ok(42)`          | Jump: `jump ok(value = 42)`        |
| Consumption              | Pattern match on variants      | Caller's blocks bound to each continuation |
| Reuse                    | Type alias / generic           | Region fragment (and Lua factory)  |
| Composition operator     | Field access, variant tag check| Emit (splices a region's control)  |

Every row of this table is a place where the two type systems answer
the same structural question for their respective domains. Sums on the
left, continuation sets on the right. Products on the left, block
parameters on the right. The mental machinery you use to design data
types transfers directly to the design of control types, with one
substitution: where you would have constructed and consumed a value
later, you instead jump and resume now.

### 4.4 What "continuation type" actually means

A *continuation*, in the language used throughout this document, is a
named exit slot of a region. It has a name (`ok`, `err`, `closed`,
`retry`) and a typed parameter list (`ok: cont(value: i32, pos: i32)`).
At the declaration site of the region, the continuation is *abstract*:
the region's body will eventually `jump` to it, but the region does
not know what happens after that jump. At the emit site of the region,
the continuation is *filled*: the caller specifies which of its own
blocks should receive control when the region exits through this
continuation.

A *continuation type* — what we mean when we talk about the type
system for control — is the set of continuations a region declares
along with their parameter signatures. Two regions with the same
continuation type can be substituted for each other. A region with
continuation type `(ok: cont(i32), err: cont(i32))` is exactly as
expressive a control fragment as another with the same signature; they
differ only in their bodies.

The continuation type is to control what the struct type is to data.
Just as you can have two structs with the same fields but different
intended use, you can have two regions with the same continuation
protocol but different bodies. Just as the struct's field set is what
the compiler checks when you access fields, the region's continuation
set is what the compiler checks when you emit and fill exits.

### 4.5 The relationship to functions

A function is a degenerate region. It has exactly one entry, exactly
one exit (`return`), and that exit carries one value (the return
type). Languages with only functions are languages with a control
type system of trivial expressive power — every operation can do
exactly one thing on exit.

Regions generalize functions in two directions:

1. *Multiple named exits*: a region can exit through any of several
   continuations, each carrying its own payload.
2. *Zero-cost composition*: emitting a region into another is not a
   call; it is a structural splice. The two regions' control graphs
   merge.

When the control flow of an operation is settled — one entry, one
exit, no need to compose with anything — a function is the right
primitive. When the control flow has structure — multiple outcomes,
typed transitions, composition with other operations — a region is
the right primitive. The design principle is: **compose with regions,
seal with functions.**

### Summary

Explicit programming requires two type systems: a data type system
(scalars, products, sums, views) and a control type system (regions,
continuations, blocks, jumps). The two are structurally parallel —
every primitive in one has a counterpart in the other. Functions are
a special case of regions, useful when control flow is settled.

---

## Chapter 5: The dual tree

The output of designing a system in the explicit programming paradigm
is a structure we will call the *dual tree*. It has two co-equal
halves, and together they fully specify the system.

This chapter introduces the dual tree as a concept. Part II of this
document is the procedure for deriving one from an idea.

### 5.1 The two halves

The **data tree** is a forest of type definitions — structs, unions,
type aliases. It describes every value the system holds: persistent
state, intermediate computation results, parameters, returned values,
events. Every distinct shape of information has a node in this tree.

The **control tree** is a forest of region declarations — region
signatures and the protocols they declare. It describes every
distinct *operation* the system performs: every state transition,
every typed transformation, every coordinated sequence of state
changes. Every distinct shape of behavior has a node in this tree.

The two trees are not independent. The data tree's types appear as
the parameter types of regions, as the payload types of continuations,
as the field types of blocks. The control tree's regions consume,
produce, and transform values from the data tree. The trees are *dual*
in the sense that designing one constrains the other: a continuation
named `success` carrying a `user_id: u64` must reference a data type
where `user_id` makes sense, and the data type's definition is
informed by the control protocols that produce and consume it.

### 5.2 An example of the dual tree

Consider the design of a small system: a function that reads a line
from a buffer until a newline or end-of-buffer.

The data tree contains:

```moonlift
struct LineResult
    start: i32      -- byte offset where the line starts
    length: i32     -- byte length of the line (excluding newline)
    terminator: i32 -- the byte that ended the line, or -1 if EOF
end
```

Or, equivalently, the same information can be carried in a tagged
union:

```moonlift
union LineOutcome
    found(start: i32, length: i32, terminator: i32)
    eof(start: i32, length: i32)
end
```

The control tree contains:

```moonlift
region read_line(
    buffer: ptr(u8),
    buffer_len: i32,
    start: i32;

    found: cont(start: i32, length: i32, terminator: i32),
    eof:   cont(start: i32, length: i32))
```

Notice that the same information appears twice in the design: once as
data (the `LineOutcome` union), once as control (the `read_line`
region's two continuations). This is not redundancy. The data
representation describes *what* the result is — a value that can be
stored, passed around, pattern-matched later. The control
representation describes *how* the result is delivered — by jumping
to one of two blocks immediately. The designer must choose which
representation is appropriate for a given consumption pattern.

Often the choice is obvious. If the result will be acted on
immediately by the caller's control flow, the region form is
preferred — no allocation, no temporary value, the caller's blocks
*are* the match arms. If the result must be stored, returned across a
boundary, or pattern-matched in multiple places, the union form is
preferred.

Sometimes the design includes both. A region that produces a
`LineOutcome` value and exits through a single `done` continuation is
a legitimate composition: it lets the caller store the value or
inspect it as needed. But for most internal operations, the region
form is the natural shape, and the union form is reserved for
values that genuinely need to live as data.

### 5.3 The structural property

The dual tree has a structural property that single-tree designs
lack: **every distinction that matters appears as structure in one of
the two trees.** There are no places where meaning hides. The data
tree contains every value the system manipulates; the control tree
contains every operation the system performs. If a piece of meaning
is not represented in either tree, it is not part of the design — it
is implicit, and the implicit-ness is a bug to be fixed.

This property is what makes explicit programming a *discipline*. The
designer can check, at any point, whether some aspect of the system
is captured by the design. If a behavior cannot be located on the
dual tree, the design is incomplete. If two pieces of behavior are
tangled in the same node, the design is insufficiently factored. The
dual tree is the artifact you produce, and the artifact you defend.

### 5.4 Reading the dual tree

A dual tree is also a *document*. A reader who is handed only the
type declarations and region signatures — no bodies, no comments —
can derive substantial understanding of the system:

- The data types tell them what the system holds.
- The region signatures tell them what operations the system performs.
- The continuation protocols tell them what outcomes each operation
  can produce and what data each outcome carries.
- The composition relationships (which regions emit which) tell them
  how operations are sequenced.

A well-designed dual tree is, on inspection, a *specification* of the
system, with no separate specification document required. The
implementation lives in the bodies; the design lives in the
signatures; the two are the same artifact, written in the same
language, in the same file, kept consistent by the same compiler.

### 5.5 The map ahead

The rest of this document is structured around the dual tree. Part II
gives the procedure for deriving one from an abstract idea. Part III
explains how Moonlift's specific features (regions, fragments, emits,
splicing) serve the dual-tree design process. Part IV walks through
three worked examples of building dual trees for real systems. Part V
catalogs the anti-patterns that produce malformed dual trees. Part VI
discusses the limits and the implications.

A reader who learns one thing from this document should learn this:
*the dual tree is the unit of system design*. Every system you build
in this paradigm produces one. Every design decision is a decision
about its shape. Every refactor is a transformation on it. The dual
tree is the design, the documentation, and the implementation, all at
once.

### Summary

The output of explicit-programming design is the dual tree: a data
type forest and a control type forest, mutually constraining, jointly
sufficient to specify the system. Every distinction that matters
appears as structure in one of the two trees. The dual tree is the
design artifact, and Moonlift's source code is its native notation.

---

# Part II — The discipline

## Chapter 6: From idea to types — the procedure

Given an abstract idea about a system you want to build, how do you
arrive at the dual tree? This chapter gives the procedure. The
remaining chapters of Part II elaborate each step.

The procedure has six steps. They are not strictly sequential — design
is iterative, and later steps will send you back to earlier ones — but
they are a coherent order for an initial pass.

**Step 1: Name the system's purpose.** State, in one sentence, what
the system does and for whom. "Decode a JSON document into a Lua
table." "Serve HTTPS requests with low tail latency." "Schedule tasks
across N OS threads with work-stealing." This sentence will discipline
every later step; if a candidate type or region cannot be justified
against this sentence, it does not belong.

**Step 2: Identify the inputs and outputs.** What does the system
receive, and what does it produce? Inputs are external to the system;
outputs are external; together they define the system's interface.
Inputs and outputs are always data — they cross a boundary, so they
must be representable as values. This step produces the *outermost*
nodes of the data tree.

**Step 3: Identify the outermost operation.** The system, as a whole,
is one operation: it takes the inputs and produces the outputs. Name
that operation. Decide what its possible outcomes are. Each outcome
becomes a continuation in the outermost region. This step produces
the *root* of the control tree.

**Step 4: Decompose recursively.** The outermost operation is composed
of smaller operations. Identify them. For each, repeat steps 2 and 3:
what does it consume, what does it produce, what outcomes does it
have? Each sub-operation is a node in the control tree; its inputs and
outputs may introduce new nodes in the data tree.

**Step 5: Identify the persistent state.** Some information must
survive across operations: connection state, cached results,
allocation pools, registries. This is the system's *internal* data,
distinct from inputs and outputs. Each piece of persistent state is a
data type that appears as a parameter to many regions — passed
through, mutated through controlled interfaces, never hidden in a
global.

**Step 6: Identify the metaprogramming axes.** Look at the trees you
have. Where do you see repetition? N regions with similar protocols
varying in one parameter? N data types with similar shapes? Each
repetition is a candidate for a Lua factory — a generator that
produces the monomorphic variants from a single source. This step
collapses accidental duplication and reveals the genuine variation
points.

The output of these six steps is the initial dual tree. It will be
wrong in places. You will discover, while filling in the region
bodies, that some continuation should have been a different shape,
that some data type should have been split or merged, that some
operation should have been factored differently. This is normal.
**Design is iterative; the dual tree is what you iterate on.** When
the bodies fill in cleanly and the compiler stops complaining, the
dual tree is right.

The remaining chapters of Part II elaborate the harder steps. Step 7
(deriving the data types) and Step 8 (deriving the control types) are
the substance of the discipline.

### Summary

The procedure from idea to dual tree has six steps: name the purpose,
identify inputs/outputs, identify the outermost operation, decompose
recursively, identify persistent state, identify metaprogramming axes.
The procedure is iterative; the dual tree is the artifact you refine.

---

## Chapter 7: Finding the data types

The data type system is the better-studied half of the dual tree, and
the discipline for deriving it has been established by prior work —
most directly, by the COMPILER_PATTERN methodology that originated in
Moonlift's own design. This chapter gives the rules in their explicit-
programming form.

### 7.1 The first rule: every "or" is a sum

When you describe the system in prose and say "this is a track *or* a
clip," "the connection is *either* open or closed," "the response is
*one of* success, redirect, or error" — you have identified a sum
type. Write it down as a tagged union. Each `or` becomes a variant.

Do not encode sums as enums of integers with magic numbers. Do not
encode sums as strings ("`status == 'open'`"). Do not encode sums as
booleans paired with conditional data ("`is_error: bool, error_code:
i32`"). The compiler must see the discriminant *as* a discriminant; if
it cannot, the exhaustiveness check fails and every consumer must
write defensive code.

```moonlift
-- Wrong: encoded as an integer + payload
struct Result
    kind: i32    -- 0 = ok, 1 = err, 2 = ??? — what does the reader do?
    value: i32
end

-- Right: encoded as a sum
union Result
    ok(value: i32)
    err(code: i32)
end
```

The right form admits exhaustive case analysis: every consumer must
handle both variants, and the compiler enforces it. The wrong form
admits silent bugs: a consumer that handles `kind == 0` and `kind == 1`
will silently ignore `kind == 2` when (not if) it appears.

### 7.2 The second rule: every "and" is a product

When you describe a piece of information and say "a user *has* an id,
*and* a name, *and* an age" — you have identified a product type.
Write it down as a struct. Each `and` becomes a field.

Do not encode products as flat lists ("`[id, name, age]`"). Do not
encode products as parallel arrays. Do not encode products as
strings with internal structure. Use the struct.

This rule is easier than the first because no modern language refuses
to provide structs. The discipline is to *use* them — to refuse the
temptation to "just pass a few extra parameters" or "stash this in a
context object" when the right shape is a named, typed aggregate.

### 7.3 The third rule: no derived data in source

If a value can be computed from other values in the system, it is not
source data. It is derived. The source data tree contains only the
*minimal* set of values from which everything else can be reconstructed.

The most common violation is caching results in the source. A cache is
not source — it is a phase output, computed on demand from the source.
Storing the cached value next to the source data tangles two
different kinds of information: the *truth* (authored by the user, or
arrived via input) and the *computation* (a function of the truth,
recomputable on demand). When the source changes, the cache becomes
stale; the system must remember to invalidate it; bugs follow.

Keep the source data minimal. Compute the rest. If the computation is
expensive, memoize at the phase boundary, not in the source.

### 7.4 The fourth rule: structure over keys

When tempted to identify a value by a string key — "the
`'transport.position'` element," "the field named `metadata.author`" —
ask whether the structure should encode the identification directly.
Strings are escape hatches; they bypass the type system. A struct with
a named field is a typed identifier. A union with named variants is a
typed discriminant. A view with positional indices is a typed
sequence.

Strings appear in source data when they are *genuinely* user-authored
text (a document's content, a username) or *genuinely* opaque to the
system (an opaque token, a URL the system does not parse). They do
not appear as the system's internal identification scheme.

### 7.5 The fifth rule: cross-references are typed handles

When one data type needs to refer to another — a comment refers to a
post, an order line refers to a product — the reference is a typed
handle, not a string, not a pointer to a possibly-stale memory
location. The handle is an opaque identifier whose meaning is
resolved by a typed lookup.

```moonlift
struct Comment
    post_id: PostId       -- typed handle, not ptr(Post)
    author_id: UserId
    text: ptr(u8)
end
```

The benefit is that the source data is serializable, comparable, and
storable without dragging in the entire object graph. Resolution
happens at the consumption site, where the lookup is explicit and the
failure modes are visible.

### 7.6 The sixth rule: events are also data

The inputs to the system — the events it receives over time — are
themselves a data type. They form a sum: every kind of event the
system can receive is a variant. The system's evolution is described
by a pure reducer:

```
apply : (state, event): state
```

This is not a separate concept. The event type is just another node
in the data tree. The reducer is just another region in the control
tree. The discipline of explicit programming applies uniformly to
input, state, and output, because all three are data and the operations
that transform them are control.

### 7.7 The procedure for finding the data types

1. Write down the system's purpose (Step 1 of Chapter 6).
2. List the system's inputs and outputs. Each is a candidate data
   type. For each, ask: is this a product, a sum, or a scalar? Apply
   rules 7.1 and 7.2.
3. List the system's persistent state. For each piece, ask the same
   question. Apply rules 7.1 and 7.2.
4. For each data type so far, check rule 7.3: is anything in here
   derived? Remove it; it belongs as a phase output.
5. For each data type so far, check rule 7.4: are any of the
   identifiers strings that should be structure? Promote them.
6. For each cross-reference between data types, check rule 7.5: is
   this a typed handle or a raw pointer? Make it a handle.
7. Identify the event type (rule 7.6).

The output of this procedure is the data half of the dual tree. It
will be revised — designing the control tree always sends you back
here to add or split types — but the initial pass produces a defensible
starting point.

### Summary

The data half of the dual tree is derived by six rules: sums are
unions, products are structs, derived data is not source, structure
replaces string keys, cross-references are typed handles, events are
also data. The result is a minimal, type-safe representation of every
value the system holds.

---

## Chapter 8: Finding the control types

The control type system is the new half. This chapter gives the
analogous discipline for deriving it.

The procedure is structurally parallel to Chapter 7, with continuation
protocols and regions in place of sums and structs. The same kinds of
mistakes (encoding sums as integers, encoding products as tuples)
have analogs in the control domain (encoding multi-outcome operations
as `bool` returns, encoding state machines as imperative flags), and
the rules forbid them for the same reasons.

### 8.1 The first rule: every "what could happen next" is a continuation

When you describe an operation in prose and say "it might *succeed,*
*or* it might *time out,* *or* it might *fail with an error code*" —
you have identified a control sum: a continuation set. Each "or"
becomes a continuation in the region's protocol.

Do not encode continuations as a single return value with a
discriminant field. Do not encode continuations as a `bool` plus a
side-channel for error data. Do not encode "what happened" as a string
the caller parses. Use the continuation protocol.

```moonlift
-- Wrong: outcome encoded in a return value
func read_bytes(fd: i32, buf: ptr(u8), n: i32): i32
    -- returns bytes read, or -1 on error, or 0 on EOF
    -- caller must know the convention
end

-- Right: outcome encoded as control
region read_bytes(fd: i32, buf: ptr(u8), max: i32;
    got:     cont(bytes: i32),
    eof:     cont(),
    error:   cont(code: i32))
```

The right form admits exhaustive handling: every emit site must
provide a destination for `got`, `eof`, and `error`. The compiler
enforces it. The wrong form admits silent bugs: a caller that handles
positive returns and `-1` will silently misinterpret `0` (EOF) as a
successful zero-byte read, which is a different thing.

### 8.2 The second rule: every continuation's payload is exactly its receiver's needs

When you declare a continuation, ask: *what does the caller need to
know, in order to act on this outcome?* Pass exactly that. No more
(passing extra fields makes the protocol harder to satisfy at emit
sites and harder to refactor). No less (forcing the caller to look up
information after the fact reintroduces the boundary-crossing the
explicit protocol was meant to eliminate).

A continuation `parsed: cont(value: ParsedValue, bytes_consumed: i32)`
should pass `bytes_consumed` because the caller will need it to
advance its cursor. It should *not* pass the original input buffer
pointer, because the caller already has it (it passed it in). It
should *not* omit `bytes_consumed`, because then the caller has to
guess how far the parse went.

The payload is the *minimum sufficient* information for the receiver
to continue.

### 8.3 The third rule: no implicit fallthrough

Every path through a region must end at one of its declared
continuations, by explicit `jump`. There is no fallthrough; there is
no "default return"; there is no implicit "continue to the next
statement after the region." The compiler enforces this rule as a
control validation fact (see LANGUAGE_REFERENCE §10.7).

The discipline this rule imposes is significant: when you write a
region, you must account for every code path. If you have an
`if`-`else`, both branches must end with a jump (or terminate by
recursion into another block). If you have a switch, every arm must
end with a jump and the default must be handled. There is no place
for implicit control flow to hide.

This is the analog of "no derived data in source" from the data side.
Just as the data tree contains the minimum sufficient information,
the control tree contains *only* the explicitly declared transitions.
If a transition is not in the tree, it does not exist.

### 8.4 The fourth rule: structure over flags

When tempted to encode a state machine as a struct with a `state: i32`
field that integer-tags the current state — stop. The state machine
should be a region with named blocks, where each block *is* a state.
The transitions are jumps with typed parameters. The compiler then
checks that you don't jump to a state with the wrong parameters, and
the reader sees the state machine in the source.

This is the most consequential rule in this chapter. State machines
are the heart of most non-trivial control logic, and they are the
single most common place where implicit control flow lives. The
typical encoding — a `state` integer plus a big `switch` somewhere —
hides the transitions, scatters the state-carried data across struct
fields, and forces the reader to reconstruct the machine from the
imperative code.

Regions invert this. The state machine *is* the region. Each block is
a state, named and typed. Each jump is a transition, typed. The
machine is on the page.

```moonlift
-- Wrong: state machine as flags
struct Parser
    state: i32      -- 0=idle, 1=in_string, 2=in_escape, 3=done
    pos: i32
    accum: ptr(u8)
    accum_len: i32
end

func parse_step(p: ptr(Parser), byte: i32): i32
    if p.state == 0 then
        if byte == 34 then p.state = 1; return 0
        -- ... etc, every branch updates p.state and p.accum_len
    end
    -- ...
end

-- Right: state machine as region
region parse_string(input: ptr(u8), n: i32, start: i32, accum: ptr(u8);
    done: cont(end_pos: i32, length: i32),
    err:  cont(at: i32, code: i32))
entry idle(pos: i32 = start, acc_len: i32 = 0)
    if pos >= n then jump err(at = pos, code = 1) end
    let c: i32 = as(i32, input[pos])
    switch c do
    case 34 then jump done(end_pos = pos + 1, length = acc_len)
    case 92 then jump escape(pos = pos + 1, acc_len = acc_len)
    default then
        accum[acc_len] = as(u8, c)
        jump idle(pos = pos + 1, acc_len = acc_len + 1)
    end
end
block escape(pos: i32, acc_len: i32)
    if pos >= n then jump err(at = pos, code = 2) end
    let c: i32 = as(i32, input[pos])
    -- ... handle escape, then:
    jump idle(pos = pos + 1, acc_len = acc_len + 1)
end
end
```

The right form admits inspection: every state is named, every
transition is explicit, every parameter the state carries is in the
block's signature. The wrong form requires the reader to mentally
correlate `p.state` values with `if` branches scattered through the
function.

### 8.5 The fifth rule: compose with emit, seal with func

When designing an operation, ask whether its outcome is *settled* or
*structured*.

- Settled: the operation has one obvious outcome (a value, possibly an
  error in a uniform way), and is called from many places that all
  want the same shape. Use a `func`.
- Structured: the operation has multiple outcomes, each with distinct
  data, and callers may want different control flow for each. Use a
  `region`.

Use `func` when sealing an abstraction whose interface is stable. Use
`region` when composing within a control flow whose structure matters.
The two are not in opposition — a system has both — but most
nontrivial operations are regions, and the common mistake is to write
them as functions, force the caller to dispatch on a return value,
and lose the structure.

### 8.6 The sixth rule: forward, don't translate

When one region emits another, the inner region's continuations should
forward to the outer region's continuations as directly as possible.
If the inner region exits through `err`, the outer region should
either forward that to its own `err` (`emit inner(...; err = err)`) or
handle it in a block that itself jumps to a meaningful exit. The
discipline is to avoid *translating* error codes, *re-wrapping*
values, or *materializing* intermediate results that exist only to be
unpacked at the next layer.

This rule is the control-side analog of "structural sharing" in
persistent data structures: when nothing changes, nothing is copied.
When an inner outcome is exactly an outer outcome, forward it.

### 8.7 The procedure for finding the control types

1. For each operation identified in step 3 or step 4 of Chapter 6,
   list its possible outcomes. Each is a candidate continuation.
   Apply rule 8.1.
2. For each continuation, determine its payload — the minimum
   sufficient information for the receiver. Apply rule 8.2.
3. For each region body you sketch, ensure every path terminates at
   a continuation. Apply rule 8.3.
4. For each state machine in the design, write it as a region with
   blocks-as-states. Apply rule 8.4.
5. For each operation, decide: function or region? Apply rule 8.5.
6. For each composition of regions, ensure inner continuations
   forward directly. Apply rule 8.6.

The output is the control half of the dual tree. As with the data
half, it will be revised — implementing region bodies always reveals
missing continuations or misplaced state — but the initial pass
produces a defensible starting point.

### Summary

The control half of the dual tree is derived by six rules: outcomes
are continuations, payloads are minimal-sufficient, no fallthrough,
state machines are regions with named blocks, compose with emit and
seal with func, forward continuations directly. The result is a
type-safe representation of every operation the system performs.

---

## Chapter 9: The unified rule — one type system, two consumption modes

Chapters 7 and 8 presented the data type discipline and the control
type discipline as parallel structures. This chapter makes the
parallel precise: **there is one type system, used in two consumption
modes.**

### 9.1 The parallel revisited

A tagged union in the data type system declares: "a value of this
type is *one of* these variants, each carrying its own typed payload."

A continuation set in the control type system declares: "an exit
from this region is *one of* these continuations, each carrying its
own typed payload."

The structure is identical. The difference is consumption:

- A data sum is consumed *later*, by pattern matching on the
  discriminant. The value can be stored, copied, returned across
  abstraction boundaries, ignored, or matched multiple times.
- A control sum is consumed *now*, by transferring control to the
  appropriate continuation block. The "value" is never stored; the
  transfer is the consumption.

The compiler treats both as instances of the same underlying concept:
a typed alternative with named variants and typed payloads. The
syntactic distinction (`union` declaration vs `region` continuation
list) reflects the consumption-mode distinction, not a type-system-
level difference.

### 9.2 The same shape, two declarations

The Moonlift language reference notes (§5.6) that a tagged union may
be used as a region result protocol:

> When a tagged union is used as a region result protocol
> (`region r(...): Scanner`), its variants become exits and named
> variant fields become continuation parameters.

This is not a coincidence. It is the language acknowledging the
underlying unification. A `union ParseOutcome { ok(...) | err(...) }`
declared once can be used either way: as a return type for a function
(consumed by later pattern match) or as a region protocol (consumed
by immediate jump).

The designer's choice between the two forms is determined by the
consumption pattern, not by the structure of the alternatives:

- If the result will flow across an abstraction boundary, be stored,
  or be examined more than once: use it as a data union.
- If the result will be acted on immediately by the caller's control
  flow: use it as a region protocol.

The unification is not just notational. It is a recognition that
*alternation with typed payloads* is a single conceptual primitive in
explicit programming. Sum types and continuation sets are two
syntactic surfaces over the same idea.

### 9.3 What this means for design

When you are designing a system and you face a "this could be one of
several outcomes" decision, you are not first deciding "is this a sum
type or a continuation set?" — you are deciding "what are the
alternatives, and what does each carry?" That is the same question in
either consumption mode. You answer it once.

Then, *separately*, you ask: "how will this be consumed?" If the
answer is "stored or examined later," the alternatives become a union.
If the answer is "acted on immediately by branching," the alternatives
become a region protocol. The choice is a late binding on a single
underlying type.

The practical consequence: **the discipline of finding sum types
(Chapter 7) and the discipline of finding continuation sets
(Chapter 8) are the same discipline.** The rules in Chapter 7 about
"every or is a sum, no strings, no flags" are the same rules in
Chapter 8 about "every outcome is a continuation, no return codes, no
bool flags," because both chapters are giving rules for the same
underlying type-system primitive in different consumption contexts.

A designer who internalizes this stops treating data and control as
two separate puzzles. They become one puzzle — *what are the
alternatives this system has at each point* — with a small additional
step at the end: *and which alternatives will be consumed by storage,
which by immediate branching?*

### 9.4 The parallel for products

The unification extends to product types. A struct declares a product
of typed fields. A block declares a product of typed parameters —
the values that this state carries. Both are products. Both name
their components. Both are checked by the compiler.

The same kind of consumption-mode distinction applies. A struct's
fields are read by field-access expressions, anywhere the struct
value is in scope. A block's parameters are read inside the block's
body, after a jump to the block has bound them. Same primitive, two
consumption modes.

### 9.5 The full table

The unified view, in one table:

| Type-system primitive          | Data consumption (later)  | Control consumption (now)         |
|--------------------------------|---------------------------|-----------------------------------|
| Named product of typed parts   | `struct`                  | Block parameters                  |
| Named sum of typed alternatives| `union`                   | Continuation set on a region      |
| Atomic construction            | Constructor: `ok(42)`     | Jump: `jump ok(value = 42)`       |
| Atomic destruction             | Pattern match on variants | Caller's blocks bound to continuations |

Every row has a single underlying primitive, surfaced two ways.

### 9.6 Why this matters for the methodology

When you sit down to design a system, you are not deriving two
unrelated forests. You are deriving *one* forest of alternatives and
products, and then deciding for each node which consumption mode it
serves. This collapses what looks like two disciplines into one, and
makes the design process linear instead of branching.

The single discipline is: **find the right typed alternatives and the
right typed products for your system.** The dual tree is what you get
when you record both, with the consumption mode marked on each.

### Summary

There is one type system in explicit programming, with two
consumption modes. Sums and continuation sets are the same primitive,
consumed differently. Products and block parameters are the same
primitive, consumed differently. The design discipline is to derive
the right alternatives and products, then choose consumption modes.
The dual tree is the result.

---

## Chapter 10: Composition

Designing the dual tree node by node produces a collection. Designing
the dual tree well requires knowing how nodes fit together. This
chapter is about composition.

### 10.1 The two composition operators

The data type system has one fundamental composition operator: types
appear as fields of other types. `struct User { friends: view(UserId) }`
expresses "users have other users as friends" by making `UserId`
appear in `User`. Sums compose with products, products compose with
sums, views compose with both. The compiler tracks all of it.

The control type system has *two* fundamental composition operators:

1. **Sequential composition** within a region: blocks in the same
   region jump to each other. Information flows through jump
   arguments. The composition is internal to one region.

2. **Hierarchical composition** between regions: one region *emits*
   another, splicing the callee's control flow into the caller's. The
   callee's continuations are bound to the caller's blocks. The
   composition crosses region boundaries.

Both are zero-cost in Moonlift. Sequential composition is just a
labeled jump in the compiled CFG. Hierarchical composition (emit) is a
splice — the emitted region's body is inlined at the emit site, with
its continuation jumps rewritten to target the caller's bound blocks.
There is no call frame, no return address, no runtime indirection.
The compiler sees one merged graph.

### 10.2 Emit is not call

This deserves emphasis. In a traditional language, when one function
calls another, there is a stack frame, a return address, a calling
convention, and possibly inlining if the compiler decides. The
abstraction has a runtime cost (frame setup) and an optimization cost
(the compiler must prove the call is safe to inline). The interface
is "one entry, one return."

In Moonlift, when one region emits another, there is no frame. The
emitted region's body is *spliced* into the caller's control graph at
parse time. The emitted region's blocks become blocks of the merged
graph (with unique internal labels). The emitted region's
continuation jumps become jumps to the blocks the caller bound to
those continuations. The result is one graph that the backend
compiles as if you had written it inline.

This changes what composition *is* in the explicit programming model.
Composition is structural, not operational. You compose by saying
"here, where I would have written some control flow, instead splice
in the body of *this* region." The compiler does the splicing. The
backend sees the result. There is no abstraction tax.

### 10.3 Continuation forwarding

The most common form of composition is *forwarding*: the caller binds
one of the callee's continuations directly to one of its own. The
forwarded continuation does not even appear as a block in the caller's
body; the compiler resolves it as a direct jump.

```moonlift
region outer(input: ptr(u8), n: i32;
    ok: cont(result: i32),
    err: cont(code: i32))
entry start()
    emit inner(input, n;
        success = ok,         -- forward: inner's success becomes outer's ok
        failure = err)        -- forward: inner's failure becomes outer's err
end
end
```

The forwarding pattern is the analog, in the control domain, of
returning a value unchanged: the operation does not transform the
inner outcome, it just passes it through. The compiler emits no code
for the forward; it rewrites the inner jump to target the caller's
binding directly.

### 10.4 Translation

The dual of forwarding is *translation*: the caller binds a callee's
continuation to a block of its own, where some additional work
happens before exiting through one of the caller's continuations.

```moonlift
region outer(...; ok: cont(result: i32), err: cont(code: i32))
entry start()
    emit inner(...; success = handle_success, failure = err)
end
block handle_success(intermediate: i32)
    -- Translate the inner result into the outer result.
    let final: i32 = intermediate * 2
    jump ok(result = final)
end
end
```

Translation happens when the caller needs to do something with the
inner result before exiting. It is not free in the sense that the
translation block must run, but it is not a function call either —
the block is just another block in the merged graph, and the jump
from inner to the translation block to outer's `ok` is a chain of
direct jumps the backend can sometimes collapse further.

### 10.5 Choice composition

When the caller wants to invoke one of several inner regions based on
a condition, the composition is *choice*:

```moonlift
if condition then
    emit handler_a(args; done = out)
else
    emit handler_b(args; done = out)
end
```

Each branch emits a different region, both forwarding their `done`
exits to the same outer continuation `out`. The compiled CFG branches
on `condition`, splices the appropriate inner body, and converges at
`out`.

The switch-based form generalizes to many alternatives:

```moonlift
switch tag do
case 0 then emit handler_0(args; done = out)
case 1 then emit handler_1(args; done = out)
case 2 then emit handler_2(args; done = out)
default then jump out(value = -1)
end
```

Each arm emits a different handler, all converging at `out`. This is
how Moonlift expresses dispatch tables — and how the JSON decoder
expresses its keyword and value dispatch, with the arms generated by
a Lua factory.

### 10.6 Iteration as composition

Iteration in Moonlift is not a separate primitive. It is composition
of a region with itself, via jumps that return to an earlier block.

```moonlift
region sum_view(xs: view(i32);
    done: cont(total: i32))
entry loop(i: i32 = 0, acc: i32 = 0)
    if i >= len(xs) then jump done(total = acc) end
    jump loop(i = i + 1, acc = acc + xs[i])
end
end
```

The `loop` block jumps to itself with updated arguments. This is a
loop. It is also a state machine where the state is `(i, acc)` and
the transition is "advance by one, accumulate." Both descriptions
are correct because in explicit programming, loops *are* state
machines, and state machines *are* regions with self-jumping blocks.

There is no `while`, no `for`, no `break`, no `continue` in Moonlift.
These constructs are conveniences that hide the state machine; in
their place, the state machine is on the page. The discipline this
imposes — that you must always name your loop's state and its
transitions — produces clearer code and more accurate types.

### 10.7 The depth of composition

A well-designed system in explicit programming has many layers of
composition. The outermost region is the system's top-level
operation. It emits sub-regions that handle major phases. Those
sub-regions emit further regions for specific transitions. The
deepest regions handle individual operations on bytes or values.

At each layer, the composition is by emit-and-forward (or
emit-and-translate, occasionally). The compiler splices everything
into one CFG. The optimizer sees the whole pipeline. Inlining
decisions, register allocation, and code layout all happen across the
entire merged graph, not across function-call boundaries.

This is why Moonlift's JSON decoder can outperform hand-tuned C
extensions: the C extension's hot path crosses several function-call
boundaries that the C compiler cannot inline through (because the
calls go through the Lua C API). The Moonlift decoder has *no
boundaries* on its hot path. The whole decoder, from byte to Lua
value, is one merged graph that Cranelift compiles as one piece.

### Summary

Composition in the control type system has two operators: sequential
composition (jumps within a region) and hierarchical composition
(emit between regions). Emit is a structural splice, not a call.
Forwarding, translation, choice, and iteration are all expressed in
the same composition primitives. The result is that a complete system
is one merged CFG that the backend compiles as one piece — no
boundary costs, no abstraction tax.

---

## Chapter 11: Metaprogramming as a design tool

The Moonlift source language has no generics. There are no type
parameters, no angle brackets, no template instantiation, no monad
transformers. This is a deliberate restriction, and it is one of the
features that makes Moonlift native to explicit programming.

In place of generics, Moonlift uses Lua as a metaprogramming layer.
A Lua function can return a Moonlift type, function, region, or
declaration. The Lua function is the *factory*; the Moonlift value is
the *concrete output*. The compiler sees only the concrete output.

### 11.1 Why generics are inadequate

Generics are an attempt to express "this code works for many types,
filled in later." They work for simple cases. They become unwieldy
for hard cases, because the parametric machinery (constraints,
where clauses, higher-kinded types, monad transformers) is itself a
language that must be learned, and the compiler errors from this
language are notoriously difficult.

More importantly, generics commit you to monomorphizing at compile
time anyway — `Vec<i32>` and `Vec<String>` are different types at
runtime, and the compiler generates code for each. Generics are
metaprogramming, but they are metaprogramming in a constrained
language whose primary purpose is to be parametric.

If you are going to metaprogram, why not metaprogram in a real
programming language? That is the question Moonlift answers
affirmatively. Lua is the meta-language. It is full-featured, it has
its own ecosystem, it runs the Moonlift compiler itself, and any
metaprogramming task — from "generate N variants of this region" to
"compute an optimal jump table" to "load a schema from disk and
generate the corresponding types" — is a normal Lua program.

### 11.2 The factory pattern

A *region factory* is a Lua function that returns a region. The
function takes whatever parameters distinguish the variants — a tag, a
constant, a sub-region to emit — and produces a concrete monomorphic
region with those values spliced in.

```lua
local function expect_byte(tag_name, expected_byte, err_code)
    return region @{"expect_" .. tag_name}(
        p: ptr(u8), n: i32, pos: i32;
        ok:  cont(next: i32),
        err: cont(at: i32, code: i32))
    entry start()
        if pos >= n then jump err(at = pos, code = @{err_code}) end
        if as(i32, p[pos]) == @{expected_byte} then
            jump ok(next = pos + 1)
        end
        jump err(at = pos, code = @{err_code})
    end
    end
end

local expect_open_brace  = expect_byte("open_brace",  123, 10)
local expect_close_brace = expect_byte("close_brace", 125, 11)
local expect_colon       = expect_byte("colon",       58,  12)
```

Three distinct regions, each monomorphic, each named, each with the
appropriate byte and error code baked in. The Lua function is the
generator; the three regions are the concrete output. The Moonlift
compiler sees three independent regions and compiles each
independently. There is no runtime overhead for the parameterization
— the parameters are constants in the compiled code.

### 11.3 The data factory pattern

The same pattern applies to data types. A Lua function can return a
struct or union, with fields or variants generated from data:

```lua
local function make_state_struct(fields)
    return struct @{name}(@{fields_to_decls(fields)...}) end
end

local Connection = make_state_struct({
    {"fd", moon.i32},
    {"buffer", moon.ptr(moon.u8)},
    {"length", moon.i32},
})
```

Or, more commonly in practice, the data type is parametric in a
small way — for example, a buffer struct whose element type varies:

```lua
local function make_ring_buffer(element_type, name)
    return struct @{name}
        data: ptr(@{element_type})
        head: u32
        tail: u32
        mask: u32
    end
end

local IntRing  = make_ring_buffer(moon.i32, "IntRing")
local TaskRing = make_ring_buffer(moon.ptr(Task), "TaskRing")
```

Two distinct, monomorphic struct types. No runtime polymorphism. The
compiler sees both as ordinary struct declarations.

### 11.4 When to factor with metaprogramming

Metaprogramming is a power tool. The discipline is to use it only
when the repetition is genuine — when you have N concrete variants
that share a structure and differ in well-defined parameters.

Premature metaprogramming is a hazard. If you have two variants that
look similar, write them out twice. If a third appears, look at all
three together and ask: is the variation parametric, or are these
three different things that happen to look alike? If the variation is
parametric, factor with a Lua function. If the three are different,
keep them separate.

The signal that metaprogramming is appropriate is *that the variation
has a small, named axis*. "These N regions differ only in which byte
they expect" — axis: the byte. "These N data types differ only in the
element type" — axis: the element type. "These N switch arms differ
only in the literal they match and the value they produce" — axis: a
pair of constants.

The counter-signal is "these N things kind of look alike but they do
different things." In that case, the structural similarity is
incidental, and forcing them into a factory creates fragile coupling.

### 11.5 Splicing as a typed operation

Lua values do not splice into Moonlift source as raw text. They splice
as typed ASDL values. A spliced type must be a type. A spliced
expression must be an expression. A spliced parameter list must be a
list of parameter values.

This is enforced by the parser. A Lua expression at a splice site is
evaluated when the `.mlua` file loads, and the resulting value is
checked against the expected splice kind for that position. The
LANGUAGE_REFERENCE §14 documents the splice positions and expected
kinds.

The discipline this enforces is significant. It means metaprogramming
cannot produce syntactically invalid code (the parser catches it
before lowering), and it cannot produce semantically incoherent code
(the typechecker catches it before backend emission). The Lua
metaprogramming layer extends the language, but it cannot violate
the language's rules.

### 11.6 The design lesson

Metaprogramming, used well, is a *design simplifier*. It collapses
accidental duplication while preserving the underlying structure. A
system designed with explicit programming and Moonlift might have a
data tree with 50 nodes, but most of those nodes might be generated
from 5 factories. The conceptual surface is small; the concrete
output is rich.

The lesson for the designer is to *recognize* the axes of variation
in the system, name them in Lua, and let the Moonlift compiler see
only the monomorphic results. The compiler stays simple; the design
stays small; the runtime stays fast.

### Summary

Moonlift has no generics. Instead, Lua serves as a metaprogramming
layer where factories generate monomorphic types, functions, and
regions. The pattern is to identify axes of variation, parameterize
factories over them, and let Lua produce the concrete output. The
compiler sees only the monomorphic result. Metaprogramming collapses
accidental duplication and reveals the genuine variation in a system.

---

# Part III — Moonlift, the medium

## Chapter 12: Why Moonlift is the language of explicit programming

Explicit programming is a methodology, not a language. It can be
practiced — clumsily — in many languages. The question this chapter
addresses is why Moonlift is described in this document as *the*
language of explicit programming, rather than one of several
candidates.

The answer has three parts: native support for the discipline,
absence of conflicting features, and ergonomic alignment between the
language and the design process.

### 12.1 Native support

A language natively supports explicit programming when:

1. Both type systems (data and control) are first-class language
   features, not library encodings.
2. Both are checked by the compiler with the same rigor.
3. The composition primitives (emit, jump, fragment splicing) are in
   the source language, not buried in runtime machinery.
4. The metaprogramming layer is full-featured and operates on typed
   ASDL values, not strings.
5. The backend compiles the whole thing efficiently, without
   abstraction tax for the discipline.

Moonlift checks all five boxes. The data type system is in the
source. The control type system is in the source. Regions, emits,
jumps, and fragments are language constructs. Lua is the
metaprogramming layer, with ASDL-typed splicing. Cranelift produces
native machine code with no overhead for the abstractions.

No other production language checks all five. Some come close in
specific dimensions: Erlang has typed protocols (gen_server
behaviors) but no static control type system; Rust has algebraic
data types but no typed continuations; Idris has dependent types but
no native multi-exit control. The combination Moonlift offers is
specific to Moonlift.

### 12.2 Absence of conflicting features

A language *conflicts with* explicit programming when it provides
features that hide meaning even if the designer tries to be explicit.
Exceptions are the canonical example: a language with exceptions
allows control flow to escape any function at any point, regardless
of whether the function's signature acknowledges it. A designer who
wants to be explicit must either ban exceptions by convention (which
the compiler does not enforce) or work around them at every layer.

Moonlift has no exceptions. Control flow exits through declared
continuations or not at all. There is no `try`, no `catch`, no
implicit unwinding. If an operation can fail, the failure is in the
protocol.

Moonlift also has no implicit conversions, no operator overloading
that hides cost, no inheritance, no method dispatch by runtime type.
Each of these is a feature that, if present, would let implicit
meaning sneak back in. Their absence is not a limitation; it is a
feature of the language.

The trade-off is real: programmers used to these conveniences
experience friction at first. The friction is the discipline being
imposed. A `Result` value pattern-match looks more verbose than a
`try`-`catch`; it is also more honest, and the compiler can check it.

### 12.3 Ergonomic alignment

The third criterion is the hardest to articulate but the most
practically important. A language is *ergonomically aligned* with a
methodology when the natural way to write code in the language is the
right way to design code under the methodology.

In Moonlift, the natural way to write a function with multiple
outcomes is a region with multiple continuations — the syntax for
that case is direct (`region foo(...; ok: cont(...), err: cont(...))`).
The natural way to write a state machine is a region with named
blocks — the syntax for that case is direct (`entry s1(...) ...
block s2(...) ...`). The natural way to handle a multi-byte parse
is a region fragment with emit and forwarding — direct syntax again.

There is no version of any of these that is *easier* to write the
wrong way (with hidden state, with stringly-typed exits, with
implicit fallthrough). Moonlift does not have a `state: i32` plus
big-switch idiom that beginners reach for and old hands tolerate. The
fastest path to working code goes through the disciplined design.

This is a property of the language. It is not automatic — bad
designs can be written in Moonlift, as in any language — but the path
of least resistance leads to good designs. That is what
ergonomic alignment means, and it is what makes Moonlift teachable.

### Summary

Moonlift is the language of explicit programming because it provides
native support for both type systems, lacks the conflicting features
that hide meaning in other languages, and aligns its ergonomics with
the design discipline. The fastest path to working code in Moonlift
is the disciplined path.

---

## Chapter 13: The minimal Moonlift you need

This chapter is a compressed tour of Moonlift syntax sufficient to
read the examples in the rest of this document. It is not a
replacement for the LANGUAGE_REFERENCE, which is the authoritative
specification. The goal here is to make the rest of the document
self-contained for a reader who has not yet studied Moonlift in
depth.

### 13.1 Scalar types

```
i8, i16, i32, i64    -- signed integers
u8, u16, u32, u64    -- unsigned integers
f32, f64             -- floating-point
bool                 -- boolean
index                -- pointer-sized integer (sizes, offsets)
```

A literal: `42`, `42u64`, `3.14`, `true`.

### 13.2 Pointers and views

```
ptr(T)               -- pointer to T
view(T)              -- bounded sequence of T (pointer + length)
```

Dereference: `*p` or `xs[i]`. Pointer arithmetic: `p + offset`.
Bounds-checked indexing for views: `xs[i]`. View construction:
`view(p, length)`.

### 13.3 Structs

```moonlift
struct User
    id: u64
    name: ptr(u8)
    age: i32
end
```

Field access: `u.name`. Struct values are usually accessed through
pointers (`ptr(User)`), since structs do not have value semantics in
the typical sense — they live in memory at known addresses.

### 13.4 Unions (tagged sums)

```moonlift
union Result
    ok(value: i32)
    err(code: i32)
end
```

Construction: produced by a region exiting through the corresponding
continuation when the union is used as a result protocol, or via
explicit constructor expressions when used as data.

### 13.5 Functions

```moonlift
local add = func(a: i32, b: i32): i32
    return a + b
end
```

Functions have one entry, one return. Use them for settled
abstractions.

### 13.6 Regions (the core)

```moonlift
local scan_until = region scan(
    p: ptr(u8), n: i32, target: i32;

    hit: cont(pos: i32),
    miss: cont(pos: i32))

entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
```

Anatomy:

- Header line: `region name(runtime_params; continuations)`.
- `entry block_name(params)`: the entry block, with parameters that
  must be supplied at emit sites or have defaults.
- Additional blocks: `block name(params) ... end`.
- Body of each block: statements ending in a `jump` to another block
  or a continuation, or a `yield`/`return` if the region is used as
  an expression or function body.

Every path through every block must end in an explicit termination.

### 13.7 Emit

```moonlift
emit scan_until(p, n, 65;
    hit = found,
    miss = missing)
```

This emits the `scan_until` region, binding its `hit` continuation to
a block named `found` in the caller, and its `miss` continuation to a
block named `missing` in the caller. The caller must define both
blocks with parameter types matching the continuation signatures.

### 13.8 Jump

```moonlift
jump found(pos = 42)
```

Transfer control to a block named `found`, passing `42` as the value
of its `pos` parameter. The block must exist in the current region (or
be a continuation slot bound by the emit site).

### 13.9 Switch

```moonlift
switch tag do
case 0 then jump handler_zero()
case 1 then jump handler_one(value = something)
case 2 then jump handler_two()
default then jump unknown()
end
```

Switch is the structural alternative to chained if-else for
multi-arm dispatch. Every arm must terminate explicitly.

### 13.10 Lua splicing

```moonlift
@{lua_expression}    -- splice a single typed value
@{lua_array...}      -- spread a list of typed values into a list position
```

Splices are evaluated at parse time. The Lua expression must produce
a typed value (or a list of them) appropriate for the splice
position. See LANGUAGE_REFERENCE §14 for the complete table of
positions and expected types.

### 13.11 Externs

```moonlift
local write = extern write(fd: i32, buf: ptr(u8), n: index): index end
```

Externs declare imported symbols — typically C functions resolved at
link time. They appear in the source as typed callees and can be
invoked like any function.

### Summary

This is the minimum syntax to read the examples in Part IV. The
LANGUAGE_REFERENCE document is the complete specification. Most
Moonlift syntax is intuitive once you internalize that regions are
the central primitive and emit-and-jump is how everything composes.

---

## Chapter 14: Regions, fragments, and emit (in depth)

This chapter deepens the treatment of the core composition primitive
of Moonlift. A reader who has internalized this chapter can read
production Moonlift code fluently.

### 14.1 Regions are typed control fragments

A region is a typed unit of control flow with:

- A name (or an inferred one from a Lua assignment target).
- A runtime parameter list (the data flowing in).
- A continuation list (the typed exits flowing out).
- A body: one entry block and zero or more additional blocks.

The continuation list is the region's *contract* with its callers.
Every emit site of the region must bind every continuation. The
compiler enforces this; an emit that omits a continuation is a
control validation error.

### 14.2 Region fragments

A region used with `emit` is a *fragment* — a piece of control flow
that is spliced into the caller's CFG. The fragment is monomorphic;
it has no type parameters, no polymorphism. If you want variants,
you write a Lua factory that produces multiple monomorphic regions
(Chapter 11).

The splicing process:

1. At each emit site, the compiler inlines the emitted region's body.
2. The emitted region's blocks become blocks of the merged graph,
   with internal labels that don't collide.
3. The emitted region's jumps to its continuations are rewritten as
   jumps to the blocks the caller bound.
4. The merged graph is what the backend compiles.

There is no runtime cost for the abstraction. The cost paid by the
designer — naming the fragment, declaring its protocol — is recovered
in clarity and composability.

### 14.3 Forwarding vs translation revisited

When a caller binds an inner continuation to one of its own
continuations *directly* (without an intermediate block), the
compiler resolves the binding as continuation forwarding:

```moonlift
region outer(...; ok: cont(v: i32), err: cont(c: i32))
entry start()
    emit inner(...; success = ok, failure = err)   -- direct forward
end
end
```

The compiler does not generate a block for the forward; it rewrites
inner's jumps to target outer's bound destinations directly.

When the caller binds to a *block* that does some work before
jumping further, the binding is translation:

```moonlift
region outer(...; ok: cont(v: i32), err: cont(c: i32))
entry start()
    emit inner(...; success = handle_success, failure = err)
end
block handle_success(intermediate: i32)
    let doubled: i32 = intermediate * 2
    jump ok(v = doubled)
end
end
```

The translation block runs only when inner exits through `success`.
It does its work and then exits through `ok` (forwarded to outer's
caller).

### 14.4 The lifecycle of a region

A region has a lifecycle in the compilation pipeline (covered in more
detail in LANGUAGE_REFERENCE §15 and the PVM guide):

1. **Parse**: the source is parsed into ASDL nodes. The region's
   structure is captured as a typed tree.
2. **Typecheck**: the region's parameters, continuations, blocks, and
   jumps are checked for consistency. Names are resolved.
3. **Control validation**: every path through every block is verified
   to terminate at a continuation or another block.
4. **Open expansion**: at emit sites, the region's continuations
   ("open slots") are bound to the caller's blocks.
5. **Lowering**: the region is lowered to flat backend commands
   (`BackCmd` values).
6. **Backend emission**: Cranelift produces machine code.

The designer interacts mainly with steps 1-3. The compiler enforces
the discipline; the designer authors the structure.

### 14.5 The protocol is the documentation

A consequence of region design is that the *protocol* — the
continuation list — is the operation's documentation. A reader of
the protocol learns, before reading a line of the body:

- What data the operation consumes (runtime parameters).
- What outcomes it can produce (continuations).
- What data each outcome carries (continuation parameters).

If the protocol does not communicate the operation's behavior, the
protocol is wrong — either too vague (a single `done` continuation
that buries all outcomes in one payload) or too detailed (
continuations whose existence is implementation noise).

The discipline of designing good protocols is the discipline of
*choosing the right vocabulary* for talking about the operation. It
is the same discipline as choosing struct fields for a data type:
enough to communicate, not so many that the consumer is overwhelmed.

### Summary

Regions are typed control fragments with named, typed exits.
Composition is structural: emit splices the region into the caller's
CFG, with continuations bound directly to blocks. Forwarding is
zero-cost; translation introduces a block but no call frame. The
protocol of a region is its documentation; designing it well is the
designer's primary control-side responsibility.

---

## Chapter 15: ASDL as the historical antecedent

The COMPILER_PATTERN document describes a methodology for building
interactive software using ASDL — Abstract Syntax Description
Language — as the substrate for explicit modeling. This document
generalizes that methodology, and identifies Moonlift as the
language where explicit modeling becomes native rather than
substrate-based. This chapter records the relationship.

### 15.1 What ASDL is

ASDL is a meta-language for declaring algebraic data types,
originally developed in the SUIF compiler project and later adopted
by Python (for the AST) and many compiler frameworks. An ASDL
declaration looks like:

```
module Audio {
    Track = AudioTrack(clip: Clip*, volume: int, pan: int)
          | MidiTrack(clip: Clip*, instrument: int)

    Clip = Clip(source: string, start: int, end: int)
}
```

It is a way of declaring data types with products and sums,
independently of any particular host language. The host language
(C, Lua, Python, OCaml) consumes the ASDL declaration and produces
language-specific bindings.

ASDL became central to the explicit-programming discipline because
its constraints — sums and products, named variants, no inheritance,
no implicit conversion — encode the data-side rules of Chapter 7.
An ASDL declaration is, by construction, the kind of minimal,
typed, sum-and-product representation that the discipline requires.

### 15.2 PVM and the compiler pattern

The COMPILER_PATTERN document develops a complete methodology — the
PVM framework — for using ASDL to model interactive software. Source
ASDL captures the user-authored program. Event ASDL captures the
input. Phases gather facts as iterators. The loop consumes facts.
Caching is a side effect of full iteration.

This methodology *works*. It produced Moonlift itself: Moonlift's
compiler is implemented in Lua using PVM, with the language's
internal structures modeled as ASDL values. Every concept in the
Moonlift compiler — types, expressions, statements, regions, blocks,
continuations — has an ASDL representation.

### 15.3 The recognition

In implementing Moonlift, a recognition emerged: the discipline ASDL
encodes for *building a compiler* is the same discipline that
*Moonlift's own type system encodes for any system*. The structural
constraints (sums, products, named, typed, no derived data,
structure over keys) are not specific to compiler implementation —
they are general principles of good system modeling.

And Moonlift, by being its own ASDL — by providing structs and
unions and regions as first-class language constructs — makes the
ASDL discipline available natively. You do not need to declare an
ASDL schema in one language and consume it from another. The
Moonlift source language *is* the schema.

### 15.4 What ASDL still offers

ASDL remains useful in two scenarios where Moonlift's type system
is not the right tool:

1. **Cross-language data interchange**: when a system needs to
   exchange typed values with components written in other languages,
   an ASDL schema serves as the lingua franca. Moonlift can consume
   such schemas (via a Lua loader) and produce corresponding struct
   and union declarations.

2. **External tooling and code generation**: when types must be
   visible to documentation generators, IDE plugins, or external
   verifiers, ASDL provides a portable representation. Moonlift's
   types are already PVM values internally, so this is more a
   formalization than a translation.

In neither scenario does ASDL replace Moonlift's native type system
for in-Moonlift design. The native type system is the design
medium; ASDL is a useful interchange and tooling format.

### 15.5 The lesson

The lesson of the historical antecedent is that the discipline of
explicit programming is not new. People have been arriving at it for
decades, through ASDL, through structured operational semantics,
through state-chart formalisms, through algebraic effect systems.
What is new is the synthesis: a language where the discipline is
*native*, where you do not have to opt in by adopting a separate
modeling layer, where the design language and the implementation
language are the same.

A practitioner who has used ASDL or similar tools will find Moonlift
familiar. A practitioner who has not will find that learning Moonlift
also teaches the underlying methodology, because the methodology and
the language are designed together.

### Summary

ASDL is the historical antecedent of explicit programming — a
language-neutral way to encode the data-side discipline. The
COMPILER_PATTERN document developed a complete methodology around
ASDL for interactive software. Moonlift internalizes this discipline
in its type system, eliminating the need for a separate modeling
substrate. The discipline is the same; the medium is now native.

---

## Chapter 16: What's free in Moonlift that's hard elsewhere

A useful way to understand a language is to enumerate what it makes
easy that other languages make hard, and vice versa. This chapter
gives the asymmetries that matter for explicit programming.

### 16.1 Exhaustive multi-outcome operations

In Moonlift, declaring that an operation has N possible outcomes is
the signature itself:

```moonlift
region authenticate(...;
    success: cont(user_id: u64, token: ptr(u8)),
    invalid_credentials: cont(),
    account_locked: cont(unlock_at: i64),
    requires_2fa: cont(challenge_id: u64),
    rate_limited: cont(retry_after: i32))
```

In most other languages, this requires a tagged union return type
and pattern matching at every call site. The pattern matching is
verbose; refactoring the union is fragile; the compiler enforces
exhaustiveness only if the language supports it (Rust, ML-family,
modern TypeScript) and the programmer remembers to opt in. The
Moonlift form forces exhaustiveness at the emit site, with no
opt-out.

### 16.2 Zero-cost abstraction

Region emit is a structural splice. Composition has zero runtime
cost. In languages with function-call abstractions (most), composing
operations costs a stack frame; inlining is an optimization the
compiler may or may not perform; the programmer cannot rely on it
for correctness or performance.

In Moonlift, "compose by emit" is the abstraction primitive *and* the
runtime cost is zero by construction. There is no inliner decision to
worry about; the splicing happens at the source level.

This makes deep composition viable. A system can have many layers of
emitted regions without paying for the layers. The optimizer sees a
flat CFG.

### 16.3 State machines as source

State machines are first-class. Each state is a block; each
transition is a jump; each state's data is the block's parameters.
The compiler checks transition validity.

In every other mainstream language, state machines are encoded
imperatively: a `state` variable, an outer switch, scattered
mutation. Reading such code is reconstruction work; verifying
correctness is human inspection. In Moonlift, the state machine is
the code; reading is direct; verification is mechanical.

### 16.4 Suspension without runtime support

Suspension and resumption — the operations that async runtimes
provide — are expressible in Moonlift as ordinary regions. A
"suspended computation" is a state struct (the env) plus a small tag
(the resume step). Resuming is jumping to the right block with the
state struct as argument.

This means asynchronous programming in Moonlift does not require an
async runtime, an event loop in the language, or compiler-generated
state machines. The "runtime" is something you build, as a normal
program, in the language itself (Chapters 17-19 of Part IV walk
through this for a scheduler).

In other languages, async is either a built-in feature with its own
semantics (JavaScript, Python, Swift) or a major library ecosystem
(tokio in Rust, asyncio in Python). In both cases, the user writes
code that *looks sequential* and the runtime hides the state
machine. In Moonlift, the user writes the state machine, and there
is no hidden runtime.

The trade-off is real: code that *looks* sequential is easier for
beginners. Moonlift code looks like state machines because it *is*
state machines, and beginners must learn to read them. Once learned,
the explicit form is more honest.

### 16.5 Native machine code

Moonlift compiles to native machine code through Cranelift. There is
no interpreter, no VM, no GC, no runtime that consumes CPU outside
what the program explicitly does. The compiled output is comparable
in performance to hand-tuned C, and in some cases (like the JSON
decoder) better, because the explicit programming model eliminates
the optimization barriers that C compilers cannot see through.

In garbage-collected languages, the discipline of explicit
programming is still valuable, but the GC remains a hidden runtime
component. In C and Rust, native compilation is available, but the
language's lack of typed continuations forces the discipline to be
encoded laboriously by hand. Moonlift gets both: the discipline and
the performance.

### 16.6 Live metaprogramming

Lua is a real programming language used at compile time. Loops,
functions, modules, libraries — all available for code generation.
This is qualitatively different from template metaprogramming in
C++, where the meta-language is a constrained sub-language with its
own learning curve; or from procedural macros in Rust, which require
a separate crate and a more involved development workflow.

The Lua metaprogramming layer makes "I have N similar things that
vary in a small parameter" trivial to factor. It also makes "I want
to load a schema from disk and generate types" practical. The cost
is that Lua is dynamically typed, so meta-level bugs are caught at
the splice point rather than earlier. In practice this is acceptable
because the resulting Moonlift code is type-checked.

### 16.7 What's hard

Honesty requires the reverse. Moonlift makes some things harder than
mainstream languages do:

- **Sequential-looking code.** When you write a state machine, it
  looks like a state machine. Translating "do A, then B, then C
  sequentially" into "block start jumps to block A, block A jumps to
  block B, block B jumps to block C" is more verbose than imperative
  code. The verbosity is the explicit-ness; it cannot be reduced
  without re-introducing implicit control flow.

- **Closures and higher-order programming.** Moonlift does not have
  general closures. Functions are first-class values, but they
  capture nothing. State that survives across "function calls" must
  be explicit struct pointers passed as parameters. This is a real
  trade-off; some patterns from functional programming do not
  translate cleanly.

- **Dynamic dispatch.** No vtables, no interfaces, no traits with
  dynamic dispatch. If you want polymorphic behavior, you express it
  as a switch on a tag or as a Lua factory that generates
  specialized monomorphic regions. This is more design work than
  declaring an interface and writing implementations.

- **Garbage collection.** Moonlift does not have GC. Memory
  management is manual or arena-based. For applications where memory
  lifetimes are simple, this is a non-issue; for applications with
  complex sharing, it is real work.

The trade-offs are deliberate. Each "hard" item corresponds to a
form of implicit-ness that mainstream languages accept and Moonlift
refuses. The hardness is the discipline being imposed; the benefit
is the visibility and the performance.

### Summary

Moonlift makes exhaustive multi-outcome operations, zero-cost
composition, state machines as source, suspension without runtime
support, native code, and live metaprogramming free or near-free. It
makes sequential-looking code, closures, dynamic dispatch, and
implicit memory management harder. The trade-offs follow directly
from the discipline.

---

# Part IV — Worked examples

## Chapter 17: A small example — parsing a JSON value

This chapter walks through the design of a small system: a parser
that consumes a single JSON value (number, string, boolean, null,
object, array) from a byte buffer and produces a typed result. The
purpose is to make every step of the Chapter 6 procedure concrete.

### 17.1 Step 1: Name the purpose

"Given a byte buffer containing UTF-8 JSON text and a starting
position, parse one JSON value and return its bounds and type, or
report a parse error."

### 17.2 Step 2: Identify inputs and outputs

Inputs:
- A pointer to the buffer's first byte.
- The length of the buffer.
- The starting position (offset from the first byte).

Outputs:
- On success: the value's type (one of string, number, object, etc.),
  the byte offsets at which it starts and ends, and possibly
  type-specific extracted data (the numeric value for numbers, the
  decoded string for strings, etc.).
- On failure: the position where parsing failed and an error code.

### 17.3 Step 3: Identify the outermost operation

The outermost operation is "parse one value." Its possible outcomes:

- A string was parsed.
- A number was parsed.
- The literal `true`, `false`, or `null` was parsed.
- An object was parsed (we will not recurse into its contents in this
  example; the result is the object's bounds).
- An array was parsed (same as object — bounds only).
- A parse error occurred.

This gives us seven candidate continuations. Let us simplify: the
three literals can share one continuation that carries which literal
was found. Objects and arrays can share one continuation that
distinguishes them by a tag. The error continuation carries the
position and code.

```moonlift
region parse_value(
    buf: ptr(u8),
    n: i32,
    start: i32;

    string:   cont(end_pos: i32, content_start: i32, content_len: i32),
    number:   cont(end_pos: i32, value: f64),
    literal:  cont(end_pos: i32, kind: i32),    -- 0=true, 1=false, 2=null
    aggregate:cont(end_pos: i32, kind: i32),    -- 0=object, 1=array
    error:    cont(at: i32, code: i32))
```

### 17.4 Step 4: Decompose

The body of `parse_value` will first skip whitespace, then look at
the first non-whitespace byte to dispatch. So we need:

- A region `skip_whitespace(buf, n, start; ok: cont(pos: i32))`.
- A region `parse_string(buf, n, start; ...)` with its own protocol.
- A region `parse_number(buf, n, start; ...)`.
- A region `parse_literal(buf, n, start, expected_keyword; ...)` —
  with a Lua factory that produces the three concrete variants for
  `true`, `false`, `null`.
- Regions `parse_object` and `parse_array` (bounds only, no recursion
  for this example).

Each of these is a node in the control tree. Each has its own
continuation protocol, derived by the same procedure.

`skip_whitespace`:

```moonlift
region skip_whitespace(buf: ptr(u8), n: i32, start: i32;
    ok: cont(pos: i32))
entry loop(i: i32 = start)
    if i >= n then jump ok(pos = i) end
    switch as(i32, buf[i]) do
    case 32 then jump loop(i = i + 1)   -- space
    case 10 then jump loop(i = i + 1)   -- newline
    case 13 then jump loop(i = i + 1)   -- carriage return
    case 9  then jump loop(i = i + 1)   -- tab
    default then jump ok(pos = i)
    end
end
end
```

One continuation: `ok`. The operation always succeeds (whitespace
might be zero-length). The continuation carries the position of the
first non-whitespace byte.

`parse_literal`, as a Lua factory:

```lua
local function make_parse_literal(name, expected_bytes, return_kind)
    return region @{"parse_literal_" .. name}(
        buf: ptr(u8), n: i32, start: i32;
        ok:  cont(end_pos: i32, kind: i32),
        err: cont(at: i32, code: i32))
    entry check(i: i32 = 0)
        if i >= @{#expected_bytes} then
            jump ok(end_pos = start + @{#expected_bytes}, kind = @{return_kind})
        end
        if start + i >= n then jump err(at = start + i, code = 100) end
        if as(i32, buf[start + i]) ~= @{expected_bytes[i + 1]} then
            jump err(at = start + i, code = 101)
        end
        jump check(i = i + 1)
    end
    end
end

local parse_true  = make_parse_literal("true",  {116, 114, 117, 101}, 0)
local parse_false = make_parse_literal("false", {102, 97, 108, 115, 101}, 1)
local parse_null  = make_parse_literal("null",  {110, 117, 108, 108}, 2)
```

Three monomorphic regions, generated from one factory. The bytes are
the ASCII codes for `t-r-u-e`, `f-a-l-s-e`, `n-u-l-l`.

### 17.5 Step 5: Identify persistent state

For this small example, there is no persistent state — the parser is
stateless across calls. The buffer and position flow through as
parameters; no global accumulator, no parser context struct.

For a larger parser (one that handles streaming input, or one that
builds a full AST), persistent state would appear: a parse context
holding allocators, error message buffers, configuration flags. The
discipline is that this state appears as a typed struct passed by
pointer to every region that needs it — never as a global.

### 17.6 Step 6: Identify metaprogramming axes

We already identified one: `parse_literal` has three concrete variants
generated from a factory. Another is the dispatch in `parse_value`,
which can be expressed using a Lua-generated switch:

```moonlift
-- In the body of parse_value, after skip_whitespace returns pos:
region parse_value_dispatch(
    buf: ptr(u8), n: i32, pos: i32;
    string: cont(...), number: cont(...), literal: cont(...),
    aggregate: cont(...), error: cont(...))
entry start()
    if pos >= n then jump error(at = pos, code = 1) end
    switch as(i32, buf[pos]) do
    case 34 then emit parse_string(buf, n, pos; ok = string, err = error)
    case 123 then emit parse_object_bounds(buf, n, pos; ok = aggregate_obj, err = error)
    case 91 then emit parse_array_bounds(buf, n, pos; ok = aggregate_arr, err = error)
    case 116 then emit @{parse_true}(buf, n, pos; ok = literal_handler, err = error)
    case 102 then emit @{parse_false}(buf, n, pos; ok = literal_handler, err = error)
    case 110 then emit @{parse_null}(buf, n, pos; ok = literal_handler, err = error)
    default then
        -- could be a number; first byte is digit or minus
        emit parse_number(buf, n, pos; ok = number, err = error)
    end
end
block literal_handler(end_pos: i32, kind: i32)
    jump literal(end_pos = end_pos, kind = kind)
end
block aggregate_obj(end_pos: i32)
    jump aggregate(end_pos = end_pos, kind = 0)
end
block aggregate_arr(end_pos: i32)
    jump aggregate(end_pos = end_pos, kind = 1)
end
end
```

Notice the structure of the dispatch: each case emits a sub-parser
whose own continuation protocol is forwarded to (or translated into)
the outer `parse_value` continuations. The literals share a handler
block that translates `(end_pos, kind)` into the outer `literal`
continuation. The aggregates have separate handler blocks because
the inner regions don't carry the kind themselves.

### 17.7 The dual tree

We can now sketch the dual tree for this small system.

**Data tree:**
- The buffer is a `ptr(u8)` with a length.
- Continuation payloads are tuples of position, length, kind, and
  value — no persistent data types are needed for this example.
- The error continuation carries `(at, code)`.

**Control tree:**
- `parse_value` (root)
  - `skip_whitespace`
  - `parse_value_dispatch`
    - `parse_string`
    - `parse_object_bounds`
    - `parse_array_bounds`
    - `parse_true`, `parse_false`, `parse_null` (factory-generated)
    - `parse_number`

The control tree captures the structure of the parser. The data tree
is mostly leaf-level (positions, lengths, codes). For this example,
the system's complexity is mostly control.

### 17.8 What this example demonstrates

Three things:

1. The dual tree is not an abstraction over the implementation — it
   *is* the implementation. The signatures we sketched are the
   parser. Filling in the bodies completes the program.

2. The discipline of "every outcome is a continuation" produces a
   parser whose error handling is exhaustive by construction. Every
   emit site of every sub-parser must specify what happens on `err`.
   No silent error paths exist.

3. Metaprogramming (the literal factory) collapses what would
   otherwise be repetitive code. The factory takes the variation
   (which keyword, what bytes, what kind tag) and produces three
   monomorphic regions. The Moonlift compiler sees three independent
   parsers; the source has one definition.

The actual production version of this parser (in
`examples/json/json_lua_stack_decoder.mlua`) is about 500 lines and
outperforms hand-tuned C JSON libraries by 2× because the control
graph is one merged CFG with no library boundaries on the hot path.

### Summary

The JSON value parser shows the dual-tree procedure on a small,
real system. The control tree dominates; the data tree is minimal.
Metaprogramming produces the repetitive literal parsers. The
resulting design is exhaustive, composable, and the bodies follow
mechanically from the protocols.

---

## Chapter 18: A medium example — an HTTP request lifecycle

This chapter develops the dual tree for a more substantial system:
the lifecycle of a single HTTP/1.1 request handled by a connection.
The example introduces persistent state, asynchronous suspension,
and protocol-stack composition.

### 18.1 Purpose

"Given a connected TCP socket and an event loop, parse one HTTP/1.1
request, dispatch it to an application handler, and write the
response back to the socket. Handle errors, connection close, and
keep-alive."

### 18.2 Inputs, outputs, persistent state

Inputs:
- A TCP socket file descriptor.
- An event loop handle (for suspension and resumption).
- A handler function or region that maps requests to responses.

Outputs:
- Bytes written to the socket.
- A decision: connection closed, or kept alive for the next request.

Persistent state for one connection:

```moonlift
struct HttpConn
    fd: i32
    event_loop: ptr(EventLoop)
    buffer: ptr(u8)
    buffer_cap: i32
    buffer_len: i32       -- bytes currently in buffer
    parse_state: i32      -- where parser left off across suspensions
    request_method: i32   -- enum: GET, POST, PUT, etc.
    request_path_start: i32
    request_path_len: i32
    request_content_length: i32
    response_buffer: ptr(u8)
    response_len: i32
end
```

This struct holds everything that survives across suspensions for one
connection. It is the "environment" of the connection's state
machine. The structure of this struct is determined by the *union* of
fields needed at each suspension point — a metaprogramming pass
could derive it automatically; for clarity we write it explicitly.

### 18.3 The outermost region

The outermost operation is "handle one HTTP request on this
connection." Its outcomes:

- The request was handled successfully; the connection should be
  kept alive for the next request.
- The request was handled successfully; the client requested close
  (or HTTP/1.0 default behavior); the connection should be closed.
- A protocol error occurred; the connection should be closed with an
  error response.
- The connection was closed by the client before a complete request.

```moonlift
region handle_one_request(conn: ptr(HttpConn);
    keep_alive: cont(),
    close:      cont(),
    error:      cont(code: i32),
    client_closed: cont())
```

### 18.4 Decomposition

The body of `handle_one_request` is a sequence of phases:

1. Read bytes until a complete request line and headers are buffered.
2. Parse the request line and headers.
3. If there is a body (POST/PUT with Content-Length), read it.
4. Invoke the application handler with the parsed request.
5. Format the response into the response buffer.
6. Write the response to the socket.
7. Decide keep-alive or close based on headers.

Each phase is a region. Each suspension point — read from socket,
write to socket — is an emit to a region that submits an io_uring
operation and exits through a suspension continuation that the
scheduler will resume.

Sketches:

```moonlift
region read_until_headers_complete(conn: ptr(HttpConn);
    headers_complete: cont(headers_end: i32),
    error: cont(code: i32),
    client_closed: cont())
entry try_parse()
    -- Look for "\r\n\r\n" in conn.buffer[conn.parse_state .. conn.buffer_len]
    emit find_header_terminator(conn.buffer, conn.buffer_len, conn.parse_state;
        found = headers_done,
        not_yet = need_more)
end
block headers_done(end_pos: i32)
    jump headers_complete(headers_end = end_pos)
end
block need_more(searched_to: i32)
    conn.parse_state = searched_to
    if conn.buffer_len >= conn.buffer_cap then
        jump error(code = 413)   -- buffer full, request too large
    end
    emit io_read(conn.event_loop, conn.fd,
                 conn.buffer + as(index, conn.buffer_len),
                 conn.buffer_cap - conn.buffer_len;
        got_bytes = read_done,
        eof = client_closed,
        error = io_error)
end
block read_done(n: i32)
    conn.buffer_len = conn.buffer_len + n
    jump try_parse()
end
block io_error(code: i32)
    jump error(code = code)
end
end
```

This region has the structure of a coroutine: it tries to parse;
if more bytes are needed, it suspends on `io_read`; when bytes
arrive, the scheduler resumes at `read_done`, which loops back to
`try_parse`. The suspension is explicit — there is no "await," no
generated state machine. The state is in `conn` (the explicit
environment) and the resume point is the block the scheduler
jumps to.

### 18.5 The suspension protocol

The `io_read` region (sketched in earlier chapters of our design
discussion) is the bridge to the event loop:

```moonlift
region io_read(loop: ptr(EventLoop), fd: i32, buf: ptr(u8), n: i32;
    got_bytes: cont(received: i32),
    eof: cont(),
    error: cont(code: i32))
```

Its body submits an io_uring read operation, sets the task's resume
information so the scheduler knows where to come back, and exits
back to the scheduler via a special "suspend" mechanism. When the
io_uring completion arrives, the scheduler examines the resume tag
and jumps back into the appropriate continuation.

The key point for the design: from the perspective of
`read_until_headers_complete`, `io_read` is just another region with
typed continuations. The asynchronous nature is *hidden in the
implementation of io_read*, not in the type signature. The caller
emits it like any other region; the suspension is the implementation
detail.

### 18.6 The full control tree

Sketched (each node is a region):

- `handle_one_request`
  - `read_until_headers_complete`
    - `find_header_terminator`
    - `io_read` (suspends)
  - `parse_request_line_and_headers`
    - Many small sub-parsers (method, path, version, header lines)
  - `read_body_if_needed`
    - `io_read` (may suspend)
  - `dispatch_to_handler`
    - The application handler (a region or function provided by the
      user)
  - `format_response`
  - `write_response`
    - `io_write` (may suspend, possibly multiple times for large
      responses)
  - `decide_keep_alive`

Each node has a typed protocol. Each emit binds protocols to blocks.
The compiler enforces consistency. The resulting compiled code is
one merged CFG that the optimizer handles as a single function.

### 18.7 The data tree

- `HttpConn` — the connection state (introduced above).
- `EventLoop` — the scheduler handle.
- Method enum, status code enum (each a union with named variants
  for each HTTP method or status).
- The application handler's request/response types — application-
  specific.

The data tree is small relative to the control tree because most of
the system's complexity is control. This is typical for protocol
implementations: lots of operations, modest data.

### 18.8 What this example demonstrates

Three things beyond what Chapter 17 showed:

1. **Persistent state belongs in an explicit struct.** The `HttpConn`
   struct holds everything that survives across suspensions. It is
   passed as a pointer to every region that needs it. It is never a
   global.

2. **Asynchronous suspension is a region with continuations.** The
   `io_read` region's protocol is no different from any other
   region's; the fact that completion is asynchronous is an
   implementation detail of `io_read`'s body. The caller's code looks
   sequential because it is sequential — emit, get result, continue.

3. **The control tree is the architecture.** A reader of the
   signatures alone — no bodies — learns the structure of the HTTP
   server: what phases there are, what can go wrong at each, what
   data each phase produces. The implementation is in the bodies, but
   the design is in the protocols.

### Summary

The HTTP request lifecycle is a substantial example. It introduces
persistent state in an explicit struct, suspension via region
continuations, and a deep control tree. The signatures alone
constitute a specification of the server's behavior. The discipline
scales from small parsers to full protocol implementations without
changing.

---

## Chapter 19: A large example — designing a scheduler

This chapter develops the dual tree for a substantial system: a
work-stealing task scheduler. The scheduler is generic infrastructure;
once built, it can run any task that fits the scheduler's task
protocol. We design it from scratch using the explicit programming
procedure.

### 19.1 Purpose

"Schedule a large dynamic set of lightweight tasks across N OS
threads, with work-stealing for load balancing, suspension on
asynchronous I/O, and minimal overhead per task transition."

### 19.2 Inputs, outputs, persistent state

The scheduler does not have classical inputs and outputs; it is a
service. What it accepts:

- Spawn requests: "run this task with this state."
- Completion notifications: "this I/O is done, the task can resume."
- Shutdown signals.

What it produces:

- Tasks running and completing.
- Side effects of those tasks (I/O, etc.).

Persistent state:

- One `M` (OS thread) per logical CPU. Each `M` owns:
  - A work-stealing deque of ready `Task` pointers.
  - A slab allocator for `Task` structs.
  - An io_uring instance for asynchronous I/O.
  - A reference to the scheduler-wide global state.
- One scheduler-wide state with:
  - A global run queue (fallback for tasks that overflow local
    deques).
  - A list of all `M`s for stealing.
  - Shutdown flags.

```moonlift
struct Task
    env: ptr(u8)        -- per-task state struct, type-erased
    resume_step: u32    -- defunctionalized "where to resume"
    -- The env's actual type is known at the resume site; the env
    -- pointer is cast to the right type by the dispatcher.
end

struct M
    id: i32
    local_deque: ptr(Deque)
    slab: ptr(TaskSlab)
    ring: ptr(IoUringRing)
    scheduler: ptr(Scheduler)
    parked: u32         -- 0 = running, 1 = parked
end

struct Scheduler
    ms: ptr(M)          -- array of M's
    m_count: i32
    global_runq: ptr(GlobalRunq)
    shutdown: u32       -- 0 = running, 1 = shutting down
end
```

### 19.3 The outermost regions

The scheduler is a service, so there is no single "outermost"
operation. There are multiple top-level regions, each serving a
purpose:

```moonlift
-- The main scheduler loop for one M.
region run_scheduler(m: ptr(M);
    shutdown_complete: cont())

-- Spawn a new task.
region spawn(m: ptr(M), env: ptr(u8), initial_step: u32;
    spawned: cont(task: ptr(Task)),
    out_of_memory: cont())

-- Submit an I/O operation that suspends the current task.
region suspend_on_io(m: ptr(M), task: ptr(Task), op: ptr(IoUringSqe);
    suspended: cont())
```

`run_scheduler` is the per-thread main loop. `spawn` is the
public API for adding new work. `suspend_on_io` is called from
within a task's region body when it needs to wait for I/O.

### 19.4 The scheduler loop

```moonlift
region run_scheduler(m: ptr(M);
    shutdown_complete: cont())
entry next()
    if atomic_load(u32, &m.scheduler.shutdown) == 1 then
        jump shutdown_complete()
    end
    emit drain_cqes(m; done = pick_task)
end
block pick_task()
    emit deque_pop(m.local_deque;
        got = dispatch,
        empty = try_global)
end
block try_global()
    emit global_runq_pop(m.scheduler.global_runq;
        got = dispatch,
        empty = try_steal)
end
block try_steal()
    emit steal_from_random_victim(m;
        got = dispatch,
        empty = park,
        race = next)            -- transient race, retry pick
end
block dispatch(task: ptr(Task))
    emit dispatch_task(m, task; resumed = next)
end
block park()
    emit park_m(m;
        woke = next,
        shutdown = shutdown_complete)
end
end
```

The scheduler's structure is on the page. Every transition is
explicit. The reader can see: try local deque, fall back to global,
fall back to steal, fall back to park. Each fallback is a
continuation; each is type-checked.

### 19.5 The Chase-Lev deque as a sub-system

The work-stealing deque is itself a sub-system with its own dual
tree. It is small enough to give in full.

**Data:**

```moonlift
struct Deque
    top: u64        -- thieves' index (monotonically increasing)
    bottom: u64     -- owner's index (monotonically increasing)
    mask: u64       -- ring size - 1
    array: ptr(u64) -- ring of Task pointers (cast to u64 for atomic ops)
end
```

**Control:**

```moonlift
region deque_push(d: ptr(Deque), task: u64;
    ok: cont(),
    full: cont())

region deque_pop(d: ptr(Deque);
    got: cont(task: u64),
    empty: cont())

region deque_steal(d: ptr(Deque);
    got: cont(task: u64),
    empty: cont(),
    race: cont())
```

Three operations, each with a few typed exits. The `race`
continuation on `deque_steal` exposes the concurrency control: when
the thief races with the owner on the last element, the operation
fails with `race` and the caller decides whether to retry.

The bodies of these regions use `atomic_load`, `atomic_store`, and
`atomic_cas` (the seq-cst atomics we added) to implement the
Chase-Lev protocol correctly. The atomic operations are explicit;
every memory ordering decision is visible.

### 19.6 The task dispatcher

The dispatcher is where defunctionalized continuations become
control flow. Each task has a `resume_step` tag indicating where to
resume. The dispatcher is a switch on this tag, with arms generated
by a Lua factory from a registry of resume points.

```moonlift
local function build_task_dispatcher(resume_points)
    local arms = {}
    for i, point in ipairs(resume_points) do
        arms[i] = { raw_key = tostring(i), body = moon.stmts(function(b)
            b:emit(point.handler,
                { b:var("m"), b:var("task") },
                { resumed = "resumed" })
        end))
    end

    return region dispatch_task(m: ptr(M), task: ptr(Task);
        resumed: cont())
    entry start()
        switch task.resume_step do
        @{arms...}
        default then jump resumed()  -- unknown step, drop
        end
    end
    end
end
```

The dispatcher is generated once at compile time from the union of
all resume points across the program. Each handler is a region with
the same protocol — `(m: ptr(M), task: ptr(Task)): resumed`. The
handler's body uses the task's env pointer (cast to the appropriate
type) to recover its state and continue.

### 19.7 Spawning and suspending

```moonlift
region spawn(m: ptr(M), env: ptr(u8), initial_step: u32;
    spawned: cont(task: ptr(Task)),
    out_of_memory: cont())
entry alloc()
    emit slab_acquire(m.slab;
        got = init,
        full = out_of_memory)
end
block init(slot: ptr(Task))
    slot.env = env
    slot.resume_step = initial_step
    emit deque_push(m.local_deque, as(u64, slot);
        ok = ok_pushed,
        full = ok_pushed)    -- if local is full, fall back to global
end
block ok_pushed()
    jump spawned(task = slot)
end
end
```

```moonlift
region suspend_on_io(m: ptr(M), task: ptr(Task), op: ptr(IoUringSqe);
    suspended: cont())
entry submit()
    op.user_data = as(u64, task)
    emit io_uring_submit(m.ring, op;
        submitted = done,
        full = back_pressure)
end
block done()
    jump suspended()
end
block back_pressure()
    -- io_uring submission queue full; flush and retry.
    emit io_uring_flush(m.ring; done = submit)
end
end
```

Each region is small, each has a tight protocol, each composes via
emit with no overhead.

### 19.8 The full control tree

The scheduler's control tree, sketched:

- `run_scheduler`
  - `drain_cqes`
    - `reap_cqe` (the io_uring primitive)
    - `dispatch_task`
  - `deque_pop`
  - `global_runq_pop`
  - `steal_from_random_victim`
    - `deque_steal`
  - `dispatch_task`
    - The handler regions registered by user code
  - `park_m`
- `spawn`
  - `slab_acquire`
  - `deque_push`
- `suspend_on_io`
  - `io_uring_submit`
  - `io_uring_flush`

This is the entire scheduler as a control tree. Approximately 15
regions, each with 2-4 continuations. The bodies fit in a few
hundred lines of Moonlift. The compiled output is one CFG.

### 19.9 The data tree

- `Task`, `M`, `Scheduler` — top-level state structs.
- `Deque`, `GlobalRunq`, `TaskSlab` — sub-system state.
- `IoUringRing`, `IoUringSqe`, `IoUringCqe` — io_uring kernel structs.
- Various tags and enums (resume steps, M states, etc.).

The data tree is larger than in the HTTP example because the
scheduler is infrastructure that maintains substantial state. The
discipline is the same: every distinct kind of information is a
named, typed entity in the source.

### 19.10 What this example demonstrates

Four things:

1. **The methodology scales.** The same procedure (purpose, I/O,
   outermost operation, decompose, persistent state, metaprogramming)
   that derived a 500-line JSON parser also derives a multi-thousand-
   line scheduler. The discipline is invariant; the size of the
   resulting trees is what changes.

2. **Concurrency primitives fit the model.** The Chase-Lev deque,
   with its three operations and explicit `race` continuation,
   demonstrates that subtle concurrent algorithms are expressible in
   the discipline. Each atomic operation is a visible step; each
   race condition is a named continuation.

3. **Defunctionalized continuations are how you bridge static and
   dynamic dispatch.** The task dispatcher's switch-on-resume-step is
   how the scheduler resumes work at the right point without needing
   runtime closures. The "what to resume" is a static enum; the
   environment is an explicit struct pointer. No heap allocation
   per task transition; no hidden runtime.

4. **The scheduler has no abstraction over the user.** It is just
   regions. User code can spawn tasks, submit I/O, suspend, and
   resume — all by emitting the scheduler's regions. There is no
   API in the traditional sense, only a control surface.

### Summary

The scheduler example shows the methodology applied to substantial
infrastructure. The dual tree has many nodes; each is small; each
has a tight protocol. The same primitives that built the JSON parser
build the scheduler. The discipline does not change with size.

---

# Part V — Anti-patterns

## Chapter 20: Stringly-typed exits

The most common anti-pattern when writing code in any language is
encoding semantic distinctions in strings. In explicit programming,
this manifests as continuations that carry strings instead of typed
discriminants.

### 20.1 The pattern

```moonlift
-- Anti-pattern: a single "result" continuation with a string status.
region parse_request(...;
    result: cont(status: ptr(u8), data: ptr(u8)))
```

The caller now must compare strings (`status == "ok"`?
`status == "error"`?) to know what happened. The compiler cannot
help. Misspellings, status values added without corresponding
handlers, and case mismatches all produce silent failures.

### 20.2 The fix

Replace the single continuation with multiple typed continuations:

```moonlift
region parse_request(...;
    ok: cont(data: ptr(u8), data_len: i32),
    bad_request: cont(at: i32),
    too_long: cont(),
    timeout: cont())
```

Now every outcome is a typed variant. The compiler enforces that
every emit site handles all of them. The semantic distinctions are
in the control type system, where they can be checked.

### 20.3 Why it happens

Strings are tempting because they're flexible. Adding a new status
seems easy — just emit a new string. The cost is invisible until a
caller forgets to handle the new value, which happens months later
in production.

The discipline is to refuse strings as discriminants from the start.
If you find yourself writing a status string, stop and ask: what are
the possible values? If the answer is a small, named set, those are
continuations. If the answer is "I don't know yet," your design is
incomplete; figure out the set before writing the region.

### Summary

Strings as exit discriminants defeat the type system. Replace them
with multiple typed continuations. The discipline is to never write
status strings; always name the outcomes as continuations.

---

## Chapter 21: Boolean returns where variants belong

A close relative of stringly-typed exits is the boolean return
pattern: an operation returns `bool` to indicate success or failure,
with the actual data smuggled through an out-parameter or a side
channel.

### 21.1 The pattern

```moonlift
-- Anti-pattern: success encoded as bool, data via side channel.
func parse_int(s: ptr(u8), n: i32, out: ptr(i32)): bool
    -- returns true on success, with the value written to *out
    -- returns false on failure, with *out unspecified
end
```

The caller writes:

```moonlift
let value: i32 = 0
if parse_int(s, n, &value) then
    -- use value
else
    -- handle error, but what was the error?
end
```

The error has no representation. The data flow is awkward (an out-
parameter for what is conceptually a return value). The caller can
accidentally use `value` after a `false` return.

### 21.2 The fix

Use a region with two continuations:

```moonlift
region parse_int(s: ptr(u8), n: i32;
    ok:  cont(value: i32),
    err: cont(at: i32, code: i32))
```

The caller emits:

```moonlift
emit parse_int(s, n;
    ok = got_value,
    err = parse_failed)
```

Each outcome has its own block, with its own typed parameters. The
data flow is direct (the value flows through the continuation
parameter, not an out-parameter). The error carries meaningful data
(position and code). The compiler enforces that both outcomes are
handled.

### 21.3 The deeper issue

Boolean returns are a degenerate case of stringly-typed exits: they
encode a binary distinction in a primitive, and force the caller to
recover the rest of the semantics from convention. The fix is the
same: use the type system. Multiple continuations, each carrying its
relevant data.

### Summary

Booleans as success/failure indicators force out-parameters and
hide error information. Replace with a region having `ok` and `err`
continuations (or however many outcomes are real). The compiler then
ensures complete handling.

---

## Chapter 22: Hidden state

The third common anti-pattern is hiding state — storing information
in places where the type system does not see it, then relying on
runtime checks to maintain consistency.

### 22.1 The pattern

Global variables, thread-local storage, hidden fields in opaque
context objects, framework-managed state that the compiler cannot
inspect. Anywhere you can store information that affects behavior
without that storage being part of an operation's signature.

```moonlift
-- Anti-pattern: a global "current request" the parser writes to.
expose CurrentRequest: Request

region parse_request(...)
entry start()
    -- ... parses, writes fields to CurrentRequest ...
end
end
```

The signature of `parse_request` says nothing about `CurrentRequest`.
The caller has no way to know that the parser modifies global state.
Multiple concurrent calls would corrupt the global.

### 22.2 The fix

Make the state explicit as a parameter:

```moonlift
region parse_request(req: ptr(Request);
    ok: cont(), err: cont(code: i32))
entry start()
    -- ... parses, writes fields to *req ...
end
end
```

Now the signature acknowledges that `parse_request` takes a `Request`
to populate. The caller passes the request they want populated. No
global, no hidden coupling.

### 22.3 The deeper issue

Hidden state is a refusal to be explicit about data flow. The
discipline insists that every piece of state an operation accesses
appears in its signature. This makes the data flow visible, makes
concurrency safe (different threads pass different state structs),
and lets the compiler check consistency.

The fix is sometimes verbose. A connection state struct passed to
every region that handles a connection looks like a lot of parameter
plumbing. The plumbing is the explicit-ness; it cannot be removed
without re-introducing the hidden coupling. In practice, Moonlift's
region fragments make the plumbing reasonable — the connection
pointer flows through emit chains naturally.

### Summary

Hidden state — globals, thread-locals, framework-managed context —
defeats the type system's ability to track data flow. Make all state
explicit as struct parameters. The verbosity is the discipline;
without it, concurrency and refactoring become unsafe.

---

## Chapter 23: Premature functions

The fourth anti-pattern is the most subtle: writing a `func` where a
`region` is the right primitive. Premature functions hide
multi-outcome operations behind single-return signatures, forcing
callers to recover the outcomes from the returned value's structure.

### 23.1 The pattern

```moonlift
union ParseResult
    success(value: i32, end_pos: i32)
    failure(at: i32, code: i32)
end

func parse_thing(s: ptr(u8), n: i32, pos: i32): ParseResult
    -- ... returns either success(...) or failure(...) ...
end
```

This looks reasonable. It uses a tagged union for the return type,
which is more honest than a bool or a string. The caller pattern-
matches on the result.

The issue is that pattern-matching on the result is a *re-dispatch*.
The function constructed a `success` or `failure` value, returned it
across an abstraction boundary, and the caller now switches on the
tag to figure out what happened. Two dispatches for one logical
choice.

### 23.2 The fix

If the result will be consumed by immediate branching (which it
almost always is), use a region:

```moonlift
region parse_thing(s: ptr(u8), n: i32, pos: i32;
    success: cont(value: i32, end_pos: i32),
    failure: cont(at: i32, code: i32))
```

The caller emits, binds blocks, and the dispatch happens once at
the splice point. The compiler eliminates the intermediate value
construction.

### 23.3 When functions are correct

Functions are correct when the result is going to be *stored* or
*passed across boundaries* — when the value's life as data is real.
A function returning an integer to be stored in a struct field is a
function. A function returning a connection handle to be remembered
across many operations is a function. The discipline of Chapter 8.5
applies: compose with regions, seal with functions.

The anti-pattern is using a function for an operation whose result
is consumed by immediate dispatch. That operation should be a region.

### Summary

A `func` returning a tagged union forces the caller to re-dispatch on
the return value. When the result is consumed by immediate branching,
use a region. Reserve functions for operations whose results have
real life as data (storage, boundary crossing).

---

# Part VI — Boundaries and implications

## Chapter 24: When explicit programming doesn't apply

Honesty requires acknowledging the cases where this discipline is the
wrong tool. Explicit programming is not universally appropriate. This
chapter identifies the cases where it does not pay off, so the reader
can choose tools deliberately.

### 24.1 Throwaway scripts

A 50-line script that reads a file, transforms some data, and writes
the output has no architecture worth designing. The discipline of
deriving a dual tree is overhead for a system whose control structure
is "do these things in order, then exit." Use Python or Lua or your
preferred quick-script language. The discipline is for systems that
will be read again.

### 24.2 Exploratory programming

When you are trying to understand a problem you have not solved
before, premature commitment to types is a hazard. You may not know
what the alternatives are yet. You may not know what the
continuations should be. Sketching loose code, throwing it away,
and trying again is the right process.

Explicit programming applies after you understand the shape of the
problem. The discipline is for *committing* a design, not
discovering one. Use a notebook, a REPL, or paper-and-pencil for
exploration. Bring the result to Moonlift when you know what you're
building.

### 24.3 Domains with genuinely dynamic behavior

Some domains are intrinsically dynamic: a plugin system where users
load arbitrary code at runtime, a configuration system where the
configuration shape varies wildly across deployments, a debugger
that introspects unknown processes. In these domains, the *fact* that
the shape is unknown is itself the design constraint.

Explicit programming can express dynamism — through tagged unions
that enumerate the possible shapes, through metaprogramming that
generates types from runtime data — but if the dynamism is
fundamental, a more dynamic substrate (a Lua interpreter, an
embedded scripting language) may be the right choice for the dynamic
part, with Moonlift handling the static framework around it.

The discipline of Moonlift's host language is precisely this: Lua is
the dynamic component, Moonlift the static one, and the two
collaborate. For a domain where the dynamic component dominates, the
balance tips toward more Lua and less Moonlift.

### 24.4 Domains with established external interfaces

If the system you are building must conform to an established C API
or library interface, you may have less freedom than the discipline
prefers. Externs let Moonlift call C functions, but the C signatures
may force lossy conversions (Result patterns into errno + return
value, multiple outcomes into a single return). The discipline still
provides value (your internal control flow can be explicit), but the
boundary friction is real.

This is not a reason to avoid Moonlift for such systems; it is a
reason to be honest about the friction and accept it as the cost of
interoperating.

### 24.5 Single-developer micro-services

A small service maintained by one person, where the entire system is
in that person's head, may not benefit much from explicit
programming. The discipline shines when multiple people read the
code, when the code outlives its author's memory, or when changes
must be made without re-deriving the original design. For a small,
single-author system, simpler tools may suffice.

This said: most systems become large, become multi-author, and
outlive their authors' memory. The discipline that looks like
overhead at 500 lines pays back at 50,000 lines. The decision to
adopt explicit programming is often a decision about *the future of
the codebase*, not its present.

### Summary

Explicit programming is the wrong tool for throwaway scripts,
exploratory programming, intrinsically dynamic domains, and small
single-author systems. It is the right tool for systems that will be
read again, maintained, extended, audited, or composed with other
systems. The discipline is a long-term investment.

---

## Chapter 25: What this means for language design

This chapter steps back from Moonlift specifically to ask what
explicit programming, as a paradigm, implies for the design of
future programming languages.

### 25.1 Typed control is the missing axis

Programming language research has spent sixty years on data types.
The results are impressive: dependent types, refinement types,
linear types, gradual types, effect types. Each is a substantial
addition to the field.

The control side has been comparatively neglected. Structured
programming (if, while, for) was the last major change to general-
purpose control syntax. Exceptions, generators, async/await, and
effect systems are all attempts to retrofit control behavior onto a
language whose control type system is trivial.

Moonlift demonstrates that typed control — regions, continuations,
typed jumps, typed emits — is implementable, checkable, and
practical. The implementation is not exotic; Cranelift handles it
without difficulty. The type discipline is no more complex than
struct-and-union typing.

The question for future language designers is: why should control
remain second-class? If we can type it, and the typing produces
better software, what justification remains for languages that don't?

The honest answer is "legacy." Existing languages cannot easily
retrofit typed control without breaking compatibility. New languages
have no such excuse. The next generation of systems languages —
whatever takes the place of Rust, Go, and C++ in the 2030s — has
the opportunity to take typed control seriously from the start.

### 25.2 The dual-tree as a design artifact

Most languages produce, as a side effect, a single artifact: source
code that is the implementation. Some produce a second: type
declarations that are the (partial) specification. Few produce a
third: a structured design document that exists separately from the
code.

The dual tree is a single artifact that serves all three roles:
implementation (bodies), specification (signatures), and design
document (the structure of the tree itself). This is unusual. It is
also what makes explicit programming sustainable for large systems:
the design does not drift from the code because they are the same
file.

Future languages might take this further. A language could provide
explicit visualization of the dual tree (an IDE that renders the
control tree as a diagram, navigable and editable). A language
could support "stub mode" — write only signatures, run the
typechecker, get a report of what's missing. A language could
generate documentation directly from the dual tree, with no
separate documentation step.

These are all extensions of the recognition that the dual tree is
the unit of design, and the language is the medium for authoring it.

### 25.3 Metaprogramming as a real language

Lua-as-metaprogramming is a deliberate choice in Moonlift, but the
deeper principle is that *metaprogramming should be a real
programming language*, not a constrained sub-language. C++ templates
and Rust macros are both metaprogramming systems with their own
learning curves; both fall short of "you already know how to program,
metaprogram using the same skills."

Future languages should treat the metaprogramming layer as
first-class. Whether through a host language (like Lua here) or
through compile-time evaluation of the language itself (Zig's
approach, with caveats), the meta-layer should be where the genuine
power of metaprogramming lives. The base language should remain
small, with metaprogramming providing the variation that other
languages encode in generics.

### 25.4 Native compilation as standard

Moonlift compiles to native code through Cranelift. This is, in
2026, an unusual choice for a high-level language; more typical
choices are interpretation (Python, Lua) or bytecode (Java, C#) or
WebAssembly (newer languages targeting portability).

But native compilation through a modern backend (Cranelift, LLVM)
is increasingly accessible. The trade-off of "high-level language"
versus "native performance" is less sharp than it was a decade ago.
Future languages should be willing to compile natively, with the
expectation that good language design produces good native code.

Cranelift specifically has a property that makes this practical:
it's a Rust library with a clean API, no LLVM-scale build burden,
no version conflicts with the graphics stack, and a tier of
performance suitable for production. It is, increasingly, the
right default for new languages that want native code without the
LLVM commitment.

### Summary

Future language design has four lessons from explicit programming:
typed control is implementable and worth implementing; the dual
tree is a useful unit of design; metaprogramming should be a real
language, not a constrained sub-language; native compilation is
increasingly accessible and should be a default. None of these is
exotic; all are within reach for the next generation of systems
languages.

---

## Chapter 26: What this means for engineering practice

This chapter discusses the implications for working engineers and
the teams they're part of. It is less technical, more practical.

### 26.1 Code review changes

When the dual tree is the design, code review changes shape. The
reviewer can review the dual tree first — the type declarations and
region signatures, without bodies — and challenge the *design*
before challenging the *implementation*. "Why does this region have
five continuations? Could it be three?" "Should this field be a sum
type?" These are design questions, and they are answerable from the
signatures alone.

Body review becomes secondary. If the signatures are right, the
bodies follow mechanically; if the bodies are wrong, the fix is
local. The expensive review work happens at the signature level,
where the decisions matter most.

### 26.2 Specification and implementation converge

In traditional engineering, the specification and the implementation
are different documents written by different people in different
languages. They drift. Maintaining alignment is a discipline that
costs effort and routinely fails.

In explicit programming, the specification *is* the implementation's
signatures. There is no drift because there is no separate document.
A spec change is a signature change is a body change. The compiler
maintains alignment.

This is a substantial reduction in long-term documentation cost. The
trade-off is upfront cost: signatures must be designed carefully,
not casually. The investment pays off in months and years.

### 26.3 Onboarding

A new engineer joining a team can read the dual tree to understand
the system. The structure is in the source, organized by region and
type. There is no separate architecture document to find, no folklore
about "which globals you can read," no informal "which files matter."
The dual tree shows what matters.

This is significant for teams with turnover. Institutional knowledge
that traditionally lives in senior engineers' heads (or wikis that
go stale) lives in the dual tree, where it is always current.

### 26.4 Tooling implications

IDE support for explicit programming is qualitatively different.
"Find references" on a region finds every emit site. "Find all
implementations" on a continuation finds every block bound to it.
"Find unused" can identify continuations no one fills (dead code in
the protocol). Refactoring "rename continuation" is mechanical and
exhaustive.

The Moonlift LSP provides these features. They are not separate
tools or plugins; they are direct queries against the dual tree's
structure. Future LSPs for explicit-programming languages should
support similar queries as primitives.

### 26.5 Testing implications

Testing changes character. Property tests become more natural —
because regions are nearly pure (state mutation only on jumps), they
can be invoked in tight loops with no setup/teardown, and properties
like "for all inputs, the region exits through one of its declared
continuations" are mechanically checkable.

Differential testing against reference implementations is easy: run
both, compare outcomes per continuation. Coverage analysis can be
done at the continuation level: was every continuation of every
region exercised by some test? If not, that's a gap.

Unit tests for individual regions are tight and fast. Integration
tests for compositions of regions are straightforward because the
compositions are explicit.

### Summary

Explicit programming changes engineering practice in five ways: code
review focuses on signatures, specification and implementation
converge, onboarding is faster, tooling supports structural queries,
and testing becomes more property-oriented. The discipline scales to
teams and codebases, not just to individual programs.

---

## Chapter 27: Closing

This document has argued that explicit programming is a coherent,
practical, and broadly applicable discipline for designing software.
It has shown that the discipline requires two type systems — for
data and for control — that the two are structurally parallel, and
that the design process produces a dual tree containing both. It has
demonstrated, through worked examples, that the discipline scales
from small parsers to substantial infrastructure.

Moonlift was used throughout as the medium of explanation because
Moonlift is the language built for this discipline. The argument is
not that Moonlift is the only place where explicit programming can
be practiced — many of its principles transfer to other languages,
sometimes awkwardly — but that Moonlift is the language where the
discipline is *native* and where the path of least resistance leads
to good designs.

The discipline is not new in its individual pieces. Sum types,
continuation-passing style, ASDL, state machines, algebraic data
types, structured concurrency — each has been around for decades.
What is new is the synthesis: a coherent design methodology that
combines all of these into a single practice, with a language that
supports the practice natively.

A reader who has internalized this document should leave with:

1. A vocabulary for the paradigm — explicit programming, dual tree,
   data types and control types, regions and continuations,
   composition by emit.
2. A procedure for designing systems — six steps from purpose to
   dual tree, with rules for finding the right types and the right
   protocols.
3. A catalog of failure modes — stringly-typed exits, boolean
   returns where variants belong, hidden state, premature functions.
4. A sense of when the discipline applies and when it doesn't.
5. A working knowledge of Moonlift sufficient to read its source and
   begin designing in it.

The remaining work is to *apply* the discipline. Take a system you
are about to design — a parser, a service, an interpreter, a
scheduler, a UI layer, anything — and walk it through the procedure.
Derive the data types. Derive the control types. Build the dual
tree. Then implement. The first attempt will be wrong; iterate. The
second will be closer. By the fifth system, the procedure will be
internalized.

Software is, in the end, made of decisions. Most of those decisions
are about distinctions: this value is one of these alternatives, this
operation has one of these outcomes, this state can transition to
one of these next states. Explicit programming makes those
distinctions visible. The compiler, the tooling, and the human
reader can then see them, and the system becomes one that can be
read, maintained, audited, and trusted.

That is the discipline. The rest is practice.

---

*End of document.*
