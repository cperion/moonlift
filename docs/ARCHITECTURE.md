# Lalin Architecture

Lalin is a LuaJIT-hosted dialect of the LLBL language.

LLBL is the central engineering artifact: the extensible language workbench and the
bootstrap language used to define member dialects. It gives Lua values dialect
meaning through heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, regions, protocols, processes, and language composition.
Lalin is the compiled dialect in that language. It consumes LLBL regions and typed
values, checks native semantics, and lowers the resulting program into LuaJIT
artifacts.

The main path is intentionally small:

```text
Lua source
  -> Lua values
  -> LLBL language capture
  -> Lalin syntax/tree ASDL
  -> typecheck
  -> LalinCode facts
  -> kernel and schedule facts
  -> LuaTrace stencil plans or C stencil plans
  -> LuaJIT copy+residual artifact
  -> loaded LuaJIT module
```

There is no Cranelift/Rust runtime path in the active architecture. C emission
and native MC banks are the fast artifact path and remain useful for validation,
benchmarking, and optional artifact generation.

## Language Layers

LLBL owns the extensible language substrate. This is the center of the
architecture:

- symbols and namespace values
- staged heads and role normalization
- fragments and spread expansion
- origins, comments, diagnostics, formatting, and indexing hooks
- generic regions, protocols, GPS lowering, and process events
- language composition and managed `use()` sessions

The `llbl` member is the identity element of language composition. Composing a
language with `llbl.core_language()` returns the other language when no rename or
preference override is requested. Every language therefore shares the same bare
substrate by default: symbol creation, source/generated symbol provenance,
origin tracking, diagnostics, fragments, regions, the formatting document
model, and language export ownership.

The identity-owned service surface is:

```text
llbl.shared.symbols
llbl.shared.origins
llbl.shared.diagnostics
llbl.shared.fragments
llbl.shared.regions
llbl.shared.formatting
llbl.shared.languages
```

Symbol resolution is shared, but symbol meaning is not. LLBL resolves a symbol
to a language binding:

```lua
local binding = language:resolve_symbol(sym)
```

The binding says which language member exported the name, whether the source was
generated, and whether the symbol is unresolved. Lalin, LLPVM, LalinSchema, and
other dialects decide what that binding means semantically.

The language audit records more than ownership. It records:

```text
owns / uses
resolves / formats / indexes / lowers / materializes
```

Those capability axes are the review surface for existing dialects.

LLBL bootstraps itself in two stages:

- `llbl.kernel`: the small Lua stage-0 substrate that owns primitive values,
  origins, diagnostics, GPS, regions, stage-0 grammar records, and the dialect
  compiler.
- `llbl.self`: the stage-1 `llbl` dialect, built by `lua/llbl/bootstrap.lua` using
  the stage-0 substrate.
- `llbl.grammar`: the public grammar facade backed by `llbl.self`; it emits the
  same declaration records expected by the dialect compiler, but the facade
  itself is now an LLBL dialect surface.
- `llbl.bootstrap.machines`: region-backed bootstrap machines for work such as
  role normalization and doc rendering.

Lalin is the compiled member. It owns native language semantics:

- scalar, pointer, view, handle, lease, and owned type values
- declarations, products, protocols, functions, and regions
- expression and statement semantics
- resource and ownership checking
- typecheck, lowering, and backend projection

LalinSchema owns schema/type-language semantics:

- product and sum schema declarations
- typed ASDL constructor families
- schema projection into runtime values

LLPVM owns low-level VM/task semantics:

- bytecode images and borrowed buffers
- worlds, tapes, machines, phases, tasks, and run records
- process-shaped validation and inspection

The reduction rule is strict: if two members can express the same semantic
primitive, one member owns it and the other projects to it. Overlapping
implementations are a design bug, not a feature.

## Region Model

`region.` is the generic LLBL control-machine head. This is one of the main
reasons LLBL composes the whole language: the same control algebra can describe
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
work as phase/task machines. LLBL processes lower event protocols to GPS.

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

The active fast backend architecture is copy+residual. Emitted LuaJIT artifacts
default to `copy_patch_mc` bank stencils plus TCC residual glue; `lalin.compile`
defaults to `copy_patch_bc`.

This split is intentional:

- `copy_patch_mc` owns the hot stencil bodies. They are generated as C through
  the LLBL C dialect, compiled by GCC/compatible C compilers, extracted into the
  MC bank, and installed as executable bytes.
- The residual JIT owns glue around selected bank stencils. It is compiled by
  TCC and should stay at coarse function/stencil boundaries; it must not become
  an element-by-element FFI strategy.
- `copy_patch_bc` remains the bytecode semantic path and fallback/probe surface.

LuaTrace lowering emits trusted LuaJIT-shaped functions from typed stencil
plans. LuaJIT compiles those functions into bytecode. The BC bank stores exact
compiled prototypes with artifact fingerprints; materialization loads the
selected bytecode entry without bytecode holes.

Native binary stencils are C-compiled `copy_patch_mc` bank entries with no
runtime holes. The emitted artifact installs those bank bytes, then the residual
JIT compiles thin TCC wrappers that call the installed bank stencils at coarse
function boundaries.
Artifact emission does not perform an ad hoc MC bank build; native emission is
plan -> prebuilt bank -> residual glue. The direct API enforces this by requiring
`mc_bank` for `copy_patch = "mc"`, while `copy_patch = "bc"` may still build a
local bytecode bank because BC is the semantic artifact itself.

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
- generating native MC banks ahead of time
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
lua/llbl.lua                  LLBL substrate
lua/lalin/dsl/               Lalin authoring surface
lua/lalin/schema/            ASDL/schema modules
lua/lalin/frontend_pipeline.lua
                             DSL/tree/typecheck/code pipeline
lua/lalin/luajit_backend.lua LuaTrace/LuaJIT backend facade
lua/lalin/copy_patch_luatrace.lua LuaTrace stencil lowering
lua/lalin/copy_patch_bc.lua LuaJIT BC bank
lua/lalin/copy_patch_mc.lua MC bank extraction and installation
lua/lalin/c_tcc.lua TCC residual compiler binding
lua/llpvm/                   LLPVM language member
lua/ui/                      UI kernel and widgets
```

## Completion Law

A lowering is complete only when its full semantic language is represented,
validated, measured, and wired through the backend. Do not move upward to a
higher lowering while the lower layer still has known semantic gaps.
