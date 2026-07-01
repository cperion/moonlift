# Native Template Architecture

This document is the binding architecture for Lalin's native compiler.

The historical filename says "residual", but the target architecture is
residualless. "Residual" was a bag for undefined implementation: missing
template methods, fallback C, host glue, exact precompiled stencils, unsupported
control flow, and arbitrary code generation. That bag is an architectural smell.
The native compiler must not represent it.

The native backend is a copy-patch compiler:

```text
Lalin semantic ASDL
  -> native loop/template algebra
  -> semantic saturation
  -> template graph
  -> copy plan
  -> copy binary templates
  -> patch typed holes
  -> executable native code
```

There is no "uncovered" result, no fallback residual category, and no exact
stencil archive as the bank. If a valid Lalin semantic leaf belongs to native
compilation, it owns a native method. If the method is missing, Lua errors
loudly. Missing implementation is not compiler data.

## Sources

The design is informed by:

- Copy-and-Patch Compilation:
  <https://fredrikbk.com/publications/copy-and-patch.pdf>
- Copy-and-Patch arXiv record:
  <https://arxiv.org/abs/2011.13127>
- PyPy/RPython JIT docs:
  <https://rpython.readthedocs.io/en/latest/jit/pyjitpl5.html>
- Applying a Tracing JIT to an Interpreter:
  <https://pypy.org/posts/2009/03/applying-tracing-jit-to-interpreter-3287844903778799266.html>
- Futhark performance guide:
  <https://futhark.readthedocs.io/en/stable/performance.html>
- Futhark redomap paper:
  <https://www.futhark-lang.org/publications/array16.pdf>

See also `docs/COPY_PATCH_TEMPLATE_ENUMERATION_NOTES.md`.

## Root Principles

1. The native compiler is complete by construction over the ASDL semantics it
   claims to compile.
2. Missing native support is a missing ASDL method or hard implementation error,
   not a typed fallback value.
3. Copy-patch handles code, data, and structured control flow through templates
   and typed holes.
4. C can be a bank-build implementation language for templates, but it is not a
   runtime fallback category.
5. Host calls, ABI bridges, and runtime services are explicit native template
   nodes or support calls, not residual code.
6. Saturation is semantic algebra closure, not Cartesian product enumeration.
7. The bank stores patchable binary templates and supertemplates, not exact
   final loop functions.
8. ASDL is the vocabulary. Lua methods implement behavior on the ASDL leaves.

## Forbidden Concepts

These are not part of the architecture:

```text
ResidualFunctionPlan
CResidual*
StencilRequiresCompile
NeedsResidualC
Uncovered*
Coverage*
fallback native path
exact embedded MC bank as the main bank
exact-cell bank enumeration
cell.kind
producer.kind
shape.kind
artifact_shape(...).kind
string dispatch
side-table planning
budget/cap-defined semantics
```

Some of those names may still exist in the current code while the hard-yank is
in progress. They are legacy code, not design.

## Copy-Patch Meaning

Copy-patch means:

```text
precompiled binary template
  + typed holes
  + runtime coordinates
  -> copied and patched executable code
```

A template is not an exact function. A template is a reusable binary
implementation of a semantic fragment or selected fused semantic form.

Typical holes:

- immediates;
- constants;
- field offsets;
- SoA component indices;
- affine coefficients and offsets;
- strides when a stride-hole template is explicitly chosen;
- branch targets;
- loop backedges;
- continuation targets;
- call targets;
- stack/frame offsets;
- runtime support symbol addresses.

The runtime copies template bytes into executable memory, patches holes with
typed coordinates, seals memory, and exposes the resulting native entrypoints.

## The Native ASDL Tower

The native compiler should be a tower of ASDL values and methods:

```text
Code/Kernel facts
  -> NativeAlgebraForm
  -> NativeSaturation
  -> NativeTemplateGraph
  -> NativeCopyPlan
  -> NativeExecutable
```

Recommended schema names may change, but the roles must remain explicit.

```text
NativeCompileRequest
  module/function
  target
  template bank
  runtime support policy

NativeAlgebraForm
  producer/control skeleton
  access projections
  body expression graph
  consumer/sink
  schedule intent
  proofs/facts

NativeSaturation
  primitive basis
  fused forms
  selected supertemplates

NativeTemplateGraph
  template nodes
  control edges
  value edges
  entry
  exits

NativeCopyPlan
  graph
  layout
  copy order
  patch bindings
  elided jumps

NativeExecutable
  symbol
  entrypoint
  installed code
```

The API shape should be method-owned:

```lua
local form = func:to_native_algebra(request)
local saturation = form:saturate_native(request)
local graph = saturation:select_native_template_graph(request)
local plan = graph:select_native_copy_plan(request)
local executable = plan:install_native(request)
```

No free helper should own the semantic step when an ASDL receiver exists.

## Native Algebra

The native algebra is the normalized semantic language for loops and stencil-like
work. It is not a storage format.

Required families:

```text
NativeProducer =
  Range1D
| RangeND
| TiledND
| WindowND
| PullStream

NativeAccess =
  Contiguous
| Affine
| ViewDescriptor
| SliceDescriptor
| ByteSpanDescriptor
| FieldProjection
| SoAComponent
| Indexed

NativeBody =
  Input
| Const
| Unary
| Binary
| Compare
| Select
| Cast
| Predicate
| WindowInput
| Tuple

NativeConsumer =
  Store
| Reduce
| Scan
| Scatter
| ScatterReduce
| Partition
| Find
| HorizontalConsumers

NativeSchedule =
  Scalar
| Vector
| Unrolled
| Tiled
```

These names describe ASDL sums/products. They are not `kind` strings.

## Saturation

Saturation is required, but it must be semantic.

Correct:

```text
primitive semantic atoms
  -> legal fusion/rewrite rules
  -> normalized fused forms
  -> selected template basis
```

Wrong:

```text
producer x layout x scalar x input_count x point x sink x schedule
```

Stage 0 is the primitive semantic basis:

- producer/control leaves;
- access leaves;
- body atoms;
- operator leaves;
- consumer leaves;
- schedule leaves;
- proof requirement leaves;
- type and ABI shape leaves.

Stage 1 is algebraic fusion closure:

- map/map fusion;
- map-to-store;
- map-to-reduce, i.e. redomap;
- map-to-scan when legal;
- horizontal fusion over the same producer;
- field/SoA/view projection composition;
- window-neighborhood map/store;
- window reduction;
- indexed/scatter forms when proofs allow them;
- tupled reductions when algebraic laws prove them.

Stage 2 selects supertemplates:

- common fused forms;
- forms that materially improve copied code;
- forms that reduce runtime assembly overhead;
- forms whose shape is common enough to justify a binary template.

Stage 2 is not "all fused forms up to a cap." It is an implementation basis
chosen from saturated semantics.

## Fusion Rules

Fusion rules are ASDL methods. They do not live in rule tables.

Example method shape:

```text
NativeConsumerStore:fuse_native_producer(input)
NativeConsumerReduce:fuse_native_producer(input)
NativeAccessFieldProjection:compose_native_access(input)
NativeBodyBinary:fuse_native_body(input)
```

A legal fusion returns a typed fused form. An illegal user semantic condition
returns a typed diagnostic or proof failure only when that is a true language
semantic. Missing implementation is not a result.

No API should return:

```text
Unsupported
Uncovered
NeedsResidual
NotImplemented
```

for valid native semantics. It should fail loudly by missing method or hard
implementation error.

## Template Graph

A single native function can be assembled from multiple template fragments and
selected supertemplates. The template graph is the implementation assembly
graph.

It is not a new semantic IR. Semantics remain in the native algebra and
saturated forms. The graph says how selected binary templates are stitched.

Required shape:

```text
NativeTemplateGraph
  nodes [many NativeTemplateNode]
  control_edges [many NativeControlEdge]
  value_edges [many NativeValueEdge]
  entry [NativeTemplateNodeRef]
  exits [many NativeTemplateNodeRef]
```

Node examples:

```text
LoopHeaderTemplate
LoopLatchTemplate
LoadAccessTemplate
StoreAccessTemplate
UnaryTemplate
BinaryTemplate
CompareTemplate
BranchTemplate
ReduceUpdateTemplate
ScanStepTemplate
RuntimeCallTemplate
SupertemplateNode
```

Control edge examples:

```text
FallthroughEdge
ConditionalBranchEdge
LoopBackedgeEdge
ExitEdge
ContinuationEdge
RuntimeCallReturnEdge
```

Value edge examples:

```text
RegisterValueEdge
StackSlotValueEdge
RuntimeParamEdge
PatchCoordinateEdge
AccumulatorValueEdge
```

The copy plan chooses placement and can elide jumps when a control edge becomes
fallthrough after layout. Non-fallthrough edges become branch/continuation holes.

This is how copy-patch handles structured control flow. Control flow is not a
reason to invent residual code.

## Family Axes, Holes, And Runtime Params

Every piece of data in native template compilation must be classified.

### Family Axes

Family axes select a binary template because they change instruction or control
shape:

- producer leaf and rank;
- loop/control skeleton;
- operation leaf;
- operand/result type shape;
- consumer/sink leaf;
- reduction operation and type;
- scan mode;
- scatter semantics;
- access projection constructor when address generation changes;
- schedule strategy when binary code changes;
- ABI/register protocol shape;
- target ISA, pointer width, endianness, and calling convention;
- proof requirement shape when it changes emitted code.

### Patch Coordinates

Patch coordinates fill holes:

- scalar constants;
- predicate constants;
- field offsets;
- component indices;
- affine terms and offsets;
- window offsets;
- branch targets;
- loop backedges;
- continuation targets;
- call targets;
- frame offsets;
- runtime support symbol addresses.

Patch coordinates are not family axes unless a leaf method explicitly chooses a
specialized template whose instruction shape changes.

### Runtime Parameters

Runtime parameters stay ABI parameters:

- base pointers;
- dynamic lengths;
- dynamic starts/stops;
- dynamic descriptor fields;
- user values consumed by the loop;
- dynamic external initialization values.

Runtime parameters are not holes unless a template leaf explicitly defines that
choice.

## Register Protocol

Copy-patch needs a typed register/value protocol to avoid combinatorial
explosion.

Required ASDL:

```text
NativeRegisterProtocol
  live_inputs
  produced_outputs
  pass_through_values
  clobbers
  abi_param_classes
  continuation
```

Pass-through values are crucial. A template must not specialize on values it
does not inspect. If a fragment only carries a value to a later fragment, the
protocol records pass-through. It does not multiply template families.

This is the main anti-explosion lesson from copy-patch.

## Bank Contents

The native bank stores:

```text
NativeTemplate
  family
  target
  register protocol
  code blob
  holes
  metadata

NativeSupertemplate
  saturated form
  family
  register protocol
  code blob
  holes
  metadata

NativeTemplateBank
  templates
  supertemplates
  target
  runtime support symbols
```

The bank does not store:

- exact final function bytes by symbol;
- every Cartesian combination;
- residual C source;
- implementation TODOs;
- "uncovered" reports;
- arbitrary profile caps as semantics.

## Bank Build

The bank build is AOT template construction:

1. Consume `NativeTemplateBankRequest`.
2. Consume a semantic saturation result.
3. For each selected template or supertemplate, generate template source or
   lower-level template code.
4. Compile once with the selected AOT compiler.
5. Extract binary code and relocation records.
6. Project raw tool output to ASDL hole/relocation leaves.
7. Emit `NativeTemplateBank`.

C may be used here as a template authoring language. That does not make runtime
C a residual fallback. It is just one way to produce binary templates.

Raw compiler/readelf/object data is IO boundary data. Before it affects
semantics, it must become ASDL:

```text
NativeRelocation =
  Rel32
| AbsPtr
| UnsupportedRelocationForThisTarget

NativePatchHole =
  Imm32
| Imm64
| Ptr
| Rel32
| BranchTarget
| FieldOffset
| ComponentIndex
| Stride
```

`UnsupportedRelocationForThisTarget` is a build error for the template authoring
pipeline. It is not a runtime fallback result.

## Runtime Installation

Runtime installation is:

```text
NativeTemplateGraph
  -> NativeCopyPlan
  -> allocate executable memory
  -> copy selected template code blobs
  -> bind holes with typed patch coordinates
  -> patch holes
  -> seal memory
  -> NativeExecutable
```

The ASDL method chain should be direct:

```lua
local plan = graph:select_native_copy_plan(input)
local executable = plan:install_native(input)
```

There is no lookup of exact precompiled final function bytes.

## Host Calls And Runtime Services

Host calls are not residual code. They are explicit semantics.

Required native nodes:

```text
NativeRuntimeCallTemplate
NativeForeignCallTemplate
NativeHostSymbol
NativeCallProtocol
```

If Lalin allows a host call inside a native loop, that call has an ASDL leaf and
a template method. If the method is missing, native compilation is incomplete.

ABI bridges and module entry wrappers should also be native templates or
runtime-support stubs with explicit ASDL call protocol values.

## Error Model

The native compiler has only these failure classes:

1. User/program semantic error.
2. Proof failure for a required law or safety condition.
3. Target build error while producing the bank.
4. Missing implementation, visible as absent method or hard internal error.

It must not encode missing implementation as normal compiler data.

Examples:

```text
alias proof failed                -> typed proof diagnostic
invalid reduction law             -> typed semantic diagnostic
object relocation unsupported     -> bank build error
missing NativeBodyFoo method      -> loud implementation error
```

There is no:

```text
NativeUncovered
NeedsResidual
TryFallback
```

## Method Ownership

The final code should read like object-oriented ASDL:

```lua
function Native.NativeBodyBinary:select_native_template(input)
  ...
end

function Native.NativeControlBranch:append_native_graph(input)
  ...
end

function Native.NativeCopyPlan:install_native(input)
  ...
end
```

Not:

```lua
local handlers = {
  Binary = ...,
  Branch = ...,
}

return handlers[node.kind](node, ctx)
```

ASDL leaves own their semantics. Parent methods are shared defaults or explicit
contracts only.

## Current Code Is Legacy

The current codebase still contains names and paths from the residual/exact-bank
model. These must be hard-yanked:

```text
lua/lalin/residual_native.lua
lua/lalin/residual_mc.lua
lua/lalin/residual_mc_intern_set.lua
lua/lalin/schema/residual.lua
ResidualFunctionPlan
CResidual*
StencilArtifactStorage
StencilStoredExactMC
StencilStoredPatchTemplateMC
StencilRequiresCompile
MaterializedExactStencil as architecture
embedded exact MC bank APIs
```

No compatibility wrapper should preserve those names as public architecture.
During the rewrite, code may be broken until callers are moved to the new native
template API.

## Implementation Target

The target public shape is:

```lua
local native = require("lalin.native")

local request = Native.NativeCompileRequest(module, target, bank, runtime)
local compiled = request:compile_native()
```

Internally:

```lua
local form = func:to_native_algebra(input)
local saturation = form:saturate_native(input)
local graph = saturation:select_native_template_graph(input)
local plan = graph:select_native_copy_plan(input)
local executable = plan:install_native(input)
```

Every object in that chain is ASDL. Every semantic branch is a leaf method.
Every missing native case is loud.
