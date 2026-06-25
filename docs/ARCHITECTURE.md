# Lalin Architecture

Lalin is a LuaJIT-hosted language family built around LLB.

LLB is the central engineering artifact. It is the workbench that gives Lua
values language meaning: heads, roles, fragments, namespaces, origins,
diagnostics, formatting, indexing, regions, protocols, processes, and family
composition. Lalin is the compiled member of that family. It consumes LLB
regions and typed values, checks native semantics, and lowers the resulting
program into LuaTrace and LuaJIT bytecode copy-patch artifacts.

The main path is intentionally small:

```text
Lua source
  -> Lua values
  -> LLB family capture
  -> Lalin syntax/tree ASDL
  -> typecheck
  -> LalinCode facts
  -> kernel and schedule facts
  -> LuaTrace stencil plans
  -> LuaJIT bytecode bank
  -> loaded LuaJIT module
```

There is no Cranelift/Rust runtime path in the active architecture. C emission
and native binary stencil banks remain engineering tools for validation,
benchmarking, and optional artifact generation. They are not the default
runtime contract.

## Family Layers

LLB owns the language-workbench substrate. This is the center of the
architecture:

- symbols and namespace values
- staged heads and role normalization
- fragments and spread expansion
- origins, comments, diagnostics, formatting, and indexing hooks
- generic regions, protocols, GPS lowering, and process events
- family composition and managed `use()` sessions

Lalin is the compiled member. It owns native language semantics:

- scalar, pointer, view, handle, lease, and owned type values
- declarations, products, protocols, functions, and regions
- expression and statement semantics
- resource and ownership checking
- typecheck, lowering, and backend projection

LalinSchema owns schema/type-family semantics:

- product and sum schema declarations
- typed ASDL constructor families
- schema projection into runtime values

LLPVM owns low-level VM/task semantics:

- bytecode images and borrowed buffers
- worlds, tapes, machines, phases, tasks, and run records
- process-shaped validation and inspection

Llisle owns compiler rule semantics:

- lowering relations
- declared predicates and constructors
- product-shaped patterns and sum alternatives
- explicit rule bodies

The reduction rule is strict: if two members can express the same semantic
primitive, one member owns it and the other projects to it. Overlapping
implementations are a design bug, not a feature.

## Region Model

`region.` is the generic LLB control-machine head. This is one of the main
reasons LLB composes the whole family: the same control algebra can describe
native CFG, processes, parser steps, scheduler steps, LLPVM tasks, and backend
pull machines. A region is:

```text
input product + state product + named exit protocol + transition body
```

Streams are not a separate semantic category. A pull stream is a region with a
pull protocol. GPS is one lowering of a pull-shaped region:

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

This keeps laziness and fusion explicit. A consumer asks for the next exit; the
machine computes only enough to produce that exit. Whole arrays, reports,
diagnostic bags, backend buffers, and artifacts are materializers, not the
region itself.

Lalin consumes generic region descriptors when the body uses native Lalin
`entry`, `block`, `jump`, and `emit` vocabulary. LLPVM consumes region-shaped
work as phase/task machines. LLB processes lower event protocols to GPS.

Region composition has two runtime shapes:

```text
emit
  direct CFG splice; no frame; all exits wired at the call site

call
  instrumentable/recursive boundary; implemented as sealed function plus
  encoded exit union plus dispatch back to named exits
```

Use `emit` for ordinary internal composition. Use `call` when the region needs
its own frame for recursion, profiling, debugging, or instrumentation.

## Compiler Boundaries

The compiler is organized around semantic products, not chronological steps.
Each phase answers one question and produces a typed value or fact set.

Important boundaries:

- DSL normalization produces explicit Lalin syntax/tree values.
- Typechecking owns name, type, ownership, and control validity.
- LalinCode is the normalized compiler product used by later lowering.
- Kernel facts describe recognized loop/control/dataflow structure.
- Schedule facts describe execution policy such as vectorization and unroll.
- Stencil plans select materializable execution descriptors.
- LuaTrace/LuaJIT materializers build executable artifacts.

Schedules are not semantics. They may choose lanes, tails, grouping, and
compiler/materializer policy, but they may not invent effects, stores,
reductions, alias facts, or safety conditions.

## Backend Model

The active backend is LuaTrace bytecode copy-patch.

LuaTrace lowering emits trusted LuaJIT-shaped templates from typed stencil
plans. LuaJIT compiles those templates into bytecode. The bytecode bank stores
compiled prototypes plus patch metadata. At materialization time, Lalin patches
declared holes and loads the resulting module.

Native binary copy-patch stencils are a parallel materialization strategy for
C-compiled stencil banks. They use the same descriptor and schedule semantics
but a different artifact installer.

The backend must consume semantic facts honestly:

- type families and ABI layout
- array/view/span descriptors
- readonly, bounds, alias, and residence facts
- reductions and effect classification
- vectorization schedule policy
- target and materializer constraints

If a fact is required for correctness or performance but is not represented in
ASDL, the schema is incomplete and must be fixed before lowering is extended.

## C And Native Stencil Role

The C path is an optional projection and measurement tool. It is useful for:

- checking semantic equivalence against a simple generated target
- generating native stencil banks ahead of time
- comparing LuaJIT and C compiler performance
- making target ABI decisions explicit

It is not the main authoring runtime.

## Diagnostics

Diagnostics are structured values. They should carry:

- code
- message
- primary origin
- related origins
- head, slot, role, event, or phase context when available
- prose comments captured from source context where useful

Fast generated paths should be diagnostically lazy. They carry compact metadata
and replay through reflective machinery on failure when a rich diagnostic is
needed.

## File Map

```text
lua/llb.lua                  LLB substrate
lua/lalin/dsl/               Lalin authoring surface
lua/lalin/schema/            ASDL/schema modules
lua/lalin/frontend_pipeline.lua
                             DSL/tree/typecheck/code pipeline
lua/lalin/luajit_backend.lua LuaTrace/LuaJIT backend facade
lua/lalin/stencil_luajit.lua LuaTrace stencil lowering
lua/lalin/luajit_bc_bank.lua LuaJIT bytecode bank
lua/llpvm/                   LLPVM family member
lua/llisle/                  Llisle rule language
lua/ui/                      UI kernel and widgets
```

## Completion Law

A lowering is complete only when its full semantic family is represented,
validated, measured, and wired through the backend. Do not move upward to a
higher lowering while the lower layer still has known semantic gaps.
