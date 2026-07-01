# Copy-Patch Template Enumeration Notes

This note records the research pass for redesigning the Lalin native bank from
first principles. It is intentionally local and operational: it should guide the
next rewrite of `residual_mc_intern_set.lua`, the embedded bank generator, and
the ASDL vocabulary around patch-template coverage.

## Sources Read

- Copy-and-Patch Compilation, Haoran Xu and Fredrik Kjolstad:
  <https://fredrikbk.com/publications/copy-and-patch.pdf>
- Copy-and-Patch arXiv record:
  <https://arxiv.org/abs/2011.13127>
- PyPy/RPython JIT docs:
  <https://rpython.readthedocs.io/en/latest/jit/pyjitpl5.html>
- Applying a Tracing JIT to an Interpreter, PyPy:
  <https://pypy.org/posts/2009/03/applying-tracing-jit-to-interpreter-3287844903778799266.html>
- RPython JIT hint source notes:
  <https://github.com/reingart/pypy/blob/master/rpython/rlib/jit.py>
- The Impact of Meta-Tracing on VM Design and Implementation:
  <https://tratt.net/laurie/research/pubs/html/bolz_tratt__the_impact_of_metatracing_on_vm_design_and_implementation/>
- Futhark performance guide:
  <https://futhark.readthedocs.io/en/stable/performance.html>
- Design and GPGPU Performance of Futhark's Redomap Construct:
  <https://www.futhark-lang.org/publications/array16.pdf>
- Futhark PLDI paper:
  <https://elsman.com/pdf/pldi17.pdf>

## Copy-Patch Lessons

Copy-patch is a baseline compiler architecture, not a compression format for
already fully generated exact functions. The bank contains binary stencils:
precompiled code fragments with known holes. Runtime compilation selects
stencils, copies their code bytes into executable memory, and patches holes such
as literals, stack offsets, branch targets, and call targets.

The paper's stencil library is organized around semantic program fragments:
bytecode opcodes, AST nodes, and deliberately selected supernodes. Supernodes
represent common subtrees or bytecode sequences where combining nodes improves
machine code. This is not the same as enumerating every product of producer,
layout, scalar type, point expression, sink, and schedule. The library can still
be large, but its units are semantic implementation fragments.

Important numbers from the paper:

- WebAssembly implementation: 1666 stencils, 35 kB.
- High-level language implementation: 98,831 stencils, 17.5 MB.

Those numbers matter because they show that a large stencil library is normal,
but also that it is structured. It is not a blind all-axis expansion. The paper
explicitly calls out Cartesian growth as a problem.

The most important anti-explosion trick is local relevance. A stencil only cares
about its own true inputs. Values that must pass through but are not inspected by
the stencil are represented with a longest/pass-through type, preventing
exponential growth in all possible live-register type combinations. In Lalin
terms, a template should not specialize on every fact carried through a loop
unless that fact changes generated instructions for that template.

The copy-patch runtime builds a CPS call graph. It plans register/value flow,
selects stencil configurations, copies stencils in depth-first order, and elides
fallthrough jumps when adjacent copied fragments make the jump unnecessary.
Remaining jumps correspond to real control flow: branches, loops, and calls.

Implication for Lalin: the bank should not contain one monolithic stencil for
every fused whole loop. It should contain composable binary templates for loop
semantic fragments plus selected supertemplates for hot/common fused shapes.

## PyPy Lessons

PyPy's tracing JIT does not enumerate all possible program loops. It observes
hot loops and specializes around a loop identity. In RPython terms, green
variables identify the loop/program position; red variables are runtime state.
The JIT traces the actual loop path, produces guards for assumptions, and falls
back or builds bridges when guards fail.

For interpreter JITs, the crucial trick is to make the loop identity correspond
to the interpreted program's loop, not the interpreter dispatch loop. PyPy does
this by adding program-counter-like values to the position key. Then tracing
unrolls the bytecode dispatch until an application-level backward jump closes a
loop.

Promotion is powerful but dangerous. Promoting a runtime value to a constant
adds guards and enables constant folding, but over-promotion creates code
explosion. The same warning applies directly to patch-template coordinates:
only values that materially change instruction selection should become family
axes; values merely inserted into existing instruction operands should be holes.

Implication for Lalin: distinguish three classes explicitly:

- Identity axes: values that define the semantic loop/template family.
- Patch coordinates: values inserted into holes of an already selected template.
- Runtime parameters: ordinary ABI values passed to the copied code.

Do not promote patch coordinates into family axes unless doing so buys a real
instruction shape.

## Futhark Lessons

Futhark treats SOACs as semantic algebra, not storage categories. `map`,
`reduce`, `scan`, and related constructs compose through fusion rules. Map can
generally be a producer; reduce/scan-like SOACs are consumers. Fusion is based
on a dependency graph, not source adjacency. Horizontal fusion combines
independent consumers of the same input into one traversal.

Futhark's redomap is not a user-facing bank family. It is a compiler-synthesized
operator that results from map-reduce fusion. The compiler fuses compositions
aggressively, including producer-consumer and horizontal fusion, and then lowers
the fused semantic operator to efficient code. This is the correct analogue for
Lalin: SOAC composition should remain semantic; the bank stores implementation
templates for the resulting normalized semantic forms.

Futhark also treats many layout operations as "free" views until use forces
materialization. Arrays of tuples use structure-of-arrays representation, making
zip/unzip cheap in many cases. The broader lesson is that layout transforms are
semantic access projections. They should influence template selection only when
they change address-generation code.

Implication for Lalin: template enumeration should be driven by normalized
loop/SOAC forms after fusion and view/layout normalization, not by raw source
surface combinations.

## Correct Lalin Bank Model

The bank is a fast copy-patch compiler for Lalin loop semantics.

The semantic flow should be:

```text
Lalin loop/source semantics
  -> Code/Kernel facts
  -> normalized StencilInstance or stencil-fragment graph
  -> PatchTemplateFamily selection
  -> binary template selection
  -> copy contiguous fragments
  -> patch typed holes
  -> TCC residual glue for calls/wrappers/remaining host integration
```

The bank is not:

- an exact artifact archive,
- a table of all Cartesian combinations,
- a set of "SOAC family names",
- a dedupe pass over generated cells,
- a fallback cache.

The bank is:

- a typed implementation vocabulary for loop semantic fragments,
- a set of patchable binary templates,
- a small set of selected supertemplates for important fused shapes,
- a selector that maps normalized ASDL semantics to templates and holes.

## Enumeration Doctrine

Template enumeration must start from the language loop grammar, not from the
machine-bank axes.

Correct root domains:

- producer/control skeletons: range, ND range, tiled range, window, pull/stream
  protocol shapes;
- body expression fragments: input, const, unary, binary, compare, select, cast,
  predicate, window input;
- sink consumers: store, reduce, scan, scatter, scatter-reduce, partition/find
  only when those are real normalized sinks;
- access projections: contiguous, affine, view/slice/bytespan descriptors,
  field projection, SoA component, indexed access;
- schedule fragments: scalar, vector, unroll/tail/reduction strategy only when
  they change binary code shape.

Bad root domains:

- arbitrary `producer x layout x scalar x input_count x point x sink x schedule`
  products;
- exact "cell" records;
- budget-limited enumeration as architecture;
- synthetic stage names that do not correspond to ASDL semantics.

## Axis Classification

Family axes should be fixed only when they alter instruction shape or control
shape:

- producer leaf/rank/order/tile/window shape;
- operation leaf and type;
- sink leaf and reduction/scan/scatter semantics;
- layout constructor shape when address-generation differs;
- schedule strategy when generated code differs;
- ABI/register protocol shape;
- target ISA/endianness/calling convention.

Patch coordinates should be holes:

- scalar constants;
- field offsets;
- SoA component indices;
- affine offsets/terms when emitted as immediates;
- window offsets;
- strides only for explicit stride-hole templates;
- branch/call targets;
- stack/frame offsets if used by a stencil protocol.

Runtime parameters should remain ABI parameters:

- base pointers;
- dynamic lengths;
- dynamic starts/stops;
- dynamic view strides already modeled by descriptors;
- external init values;
- values that the loop naturally consumes per call.

## Supertemplate Policy

Supertemplates should be selected by semantic frequency and instruction benefit,
not generated by full expansion.

Good supertemplate candidates:

- map-to-store chains;
- map-to-reduce/redomap;
- map-to-scan;
- horizontal map/reduce consumers over the same producer;
- window-neighborhood map/store and window reduction;
- field/SoA projection plus simple arithmetic;
- common predicate/select store and reduce forms.

Bad supertemplate candidates:

- every possible depth of expression tree;
- every possible arity stack;
- all combinations of layout and sink when the layout is just a pass-through
  address projection;
- variants that differ only by values that can be holes.

## ASDL Consequences

The next schema should model template compilation, not enumeration mechanics.
Likely missing values:

- `StencilTemplateFragment`: semantic binary-template fragment.
- `StencilTemplateSupernode`: selected fused semantic fragment.
- `StencilTemplateGraph`: CPS/copy graph of fragments for a normalized loop.
- `StencilTemplateSelectorResult`: selected fragment/template plus holes.
- `StencilTemplateHolePlan`: typed mapping from semantic coordinate to binary
  hole.
- `StencilTemplateRegisterProtocol`: ABI/register/pass-through shape.
- `StencilTemplateCoverage`: whether a normalized loop is fully template-covered
  or needs residual C.

Methods should live on ASDL leaves:

```text
StencilProducerShape*:select_template_fragment(input)
StencilPointExpr*:select_template_fragment(input)
StencilSink*:select_template_fragment(input)
StencilAccessLayout*:select_template_fragment(input)
StencilSchedule*:select_template_fragment(input)
StencilTemplateGraph:copy_patch(input)
```

No selector tables, kind strings, cell records, or side maps.

## Current Rewrite Warning

The current typed template stream is better than the old exact-cell archive, but
it is still too close to a Cartesian product. Its measured default size was
440,748 template entries at `input_count_max = 3`. With the rough current
estimate of about 348 bytes/template, that implies around 153 MB before source
strings, metadata, object overhead, and final binary overhead. That number is
not a target; it is evidence that the enumeration is still wrong.

The next rewrite should delete broad template-seed cross-products and replace
them with a normalized loop/SOAC grammar plus selected supertemplates.

