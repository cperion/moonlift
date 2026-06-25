# Workflow 
**Started**: 2026-05-21 20:36:20
---

## Knowledge-builder Output — 2026-05-21 20:39:01

### What Matters Most for This Problem

- **Semantic fidelity under dynamic control:** Lua VM operations are not simple value transforms; many can call Lua, allocate, collect, throw, yield, or mutate VM state.
- **Hot-path shape vs protocol clarity:** idiomatic Lalin wants explicit protocols, but a fast interpreter cannot turn every micro-outcome into boxed/tagged results or C-ABI calls.
- **Safepoint/root invariants:** GC, errors, calls, and metamethods all require the VM stack, PC, frame, and temporary values to be in a recoverable state.
- **Boundary placement:** Lalin `region`/`emit` is zero-cost control composition; `func` is a sealed ABI boundary. Copying C helper/function boundaries risks hiding protocols and adding overhead.
- **Storage vs dispatch discipline:** Lua tags/opcodes/metamethod flags are storage facts; the meaningful dispatch consumers should be named control regions/protocols.

### Non-Obvious Observations

- **The VM dispatch loop is not just opcode dispatch.** Each opcode branch also decides whether control remains in the fast loop, enters call machinery, invokes a metamethod, runs GC, raises an error, or returns from a frame. A design that treats opcodes as “handlers returning status” recreates C’s hidden protocol problem.

- **Lalin `switch` maps naturally to bytecode dispatch, but computed-goto-style copying is philosophically and mechanically tense.** Lalin does support indirect calls, but a function-pointer dispatch table forces all handlers through one monolithic signature and hides typed outcomes in mutated VM state/status codes. That loses the main benefit of regions: typed, inline control edges.

- **Opcode handler granularity affects register pressure.** If every opcode-region continuation carries the full VM product—`L`, `pc`, `base`, `top`, `ci`, temporary operands, result count—then the explicit protocol becomes expensive. The constraint is not “avoid protocols”; it is that protocol payloads must reflect real control facts, not mechanically thread every mutable C local.

- **The Lua call protocol is the center, not a side path.** `CALL`, `RETURN`, tail calls, metamethod calls, hooks, finalizers, and native/C callbacks all share the same underlying “enter/leave frame with variable stack effects” protocol. If table/metamethod slow paths invent their own call convention, error unwinding and GC rooting will diverge.

- **Lua calls are stack effects, not Lalin returns.** Lua multiple returns, varargs, wanted-result counts, and tail calls are naturally represented by stack intervals/counts and frame transitions. Treating them as normal Lalin function returns would box a dynamic protocol into data and obscure frame replacement semantics.

- **PC/base/top synchronization is a safepoint invariant.** PUC Lua often relies on subtle conventions: save `pc` before anything that can throw, update `top` before calls, restore `base` after stack growth. In Lalin those cannot remain macro folklore; every region that may allocate/call/error needs a clear precondition about which VM fields are committed.

- **Lalin locals and continuation parameters are not GC roots.** This is probably the biggest hidden constraint. Any `TValue` held only in SSA/register/block params is invisible to a Lua GC unless explicitly stored in the VM’s root set. Therefore allocation, table growth, string interning, metamethod invocation, and error creation constrain where temporaries may live.

- **Stack/table reallocation invalidates raw pointers.** PUC-style code commonly caches `StkId ra`, table node pointers, or array slots. In Lalin, holding `ptr(TValue)` across stack growth, table rehash, GC, or metamethod call is unsafe unless the protocol guarantees no relocation. This interacts directly with `noalias`/`readonly` facts.

- **Table slow paths are arbitrary re-entry points.** `__index`, `__newindex`, arithmetic metamethods, concat, compare, and length can call user Lua. They can mutate the table/metatable, trigger GC, resize stacks, and raise errors. A “miss” is not merely `nil`; it is a control fork into the same VM call/error/GC machinery.

- **Metatable negative caches are semantic state, not mere optimization.** Lua table flags that record absent metamethods are invalidated by metatable mutation. If modeled as plain product fields without an explicit invalidation protocol, fast paths can silently become wrong.

- **Write barriers are hidden protocols in C macros.** C code hides GC invariants inside `setobj`, `luaC_barrier`, `luaC_barriert`, etc. Lalin field assignment is too direct: every store of a collectable value into a collectable object has a color/debt invariant attached. The design must make those stores recognizable as protocol-bearing operations.

- **Incremental GC makes allocation outcomes richer than `ok/oom`.** Allocation can repay debt, run marking work, trigger finalizers, resize structures, or enter emergency behavior. Even if the hot path sees only “pointer returned,” the surrounding protocol must preserve roots and frame state before the allocation.

- **Error handling is not just an `err(code)` continuation.** Lua errors carry an object, current frame/PC, protected-call target, stack restoration policy, and sometimes message construction allocation. A single global error exit loses the dynamic protected-call stack that C implements with `setjmp`/`longjmp`.

- **Protected calls are dynamic control delimiters.** `pcall`/host-protected entry points catch only errors inside a dynamic extent. In Lalin terms, this means error continuations are parameterized by current handler state; they are not equivalent to returning a status from every helper.

- **OOM while raising an error is a distinct invariant.** Lua implementations have special cases for memory errors, emergency GC, and avoiding recursive allocation while constructing error objects. A clean protocol model has to account for “cannot allocate the diagnostic” as more than another ordinary error.

- **C API/native callbacks are hostile boundaries.** A Lua C function conventionally returns an int number of results and mutates the Lua stack; it may also longjmp/error through the VM. Lalin regions cannot be consumed by C directly, so these boundaries inevitably seal rich internal protocols into conventional ABI/status/stack effects.

- **Debug hooks and coroutines, if in scope, change the hot-loop contract.** Count/line hooks can run arbitrary code between instructions; yields are nonlocal but resumable. They are easy to omit in a minilua prototype, but difficult to add later if the VM state product does not already distinguish error, return, yield, and resume edges.

- **`TValue` is storage, not semantics.** A tagged value representation is necessary, but “number/string/table/function/nil” should not become a semantic union passed around as results. The meaningful operation is the consumer: arithmetic dispatch, truthiness, table indexing, callability, comparison, etc.

- **Instruction decode placement has semantic consequences.** PUC macros make operand decode and `pc++` look mechanical, but slow paths need the correct saved PC for errors, hooks, and resumes. Lalin’s explicit blocks expose this, which is good, but copying C macro layout can preserve the ambiguity.

- **Minilua vs full PUC Lua is not a linear feature ladder.** Tables, metamethods, calls, errors, and GC are mutually entangled. A “fast core first, GC/errors/metamethods later” design can paint itself into a corner if stack/root/call protocols are not chosen with those slow paths in mind.

### Knowledge Gaps

- The shared scout context was empty, so these observations are based on Lalin docs/source patterns and Lua VM semantics rather than concrete scout findings.
- Need target scope: Lua 5.1/minilua subset vs Lua 5.4-like features, bytecode compatibility, C API compatibility, coroutines/debug hooks/finalizers.
- Need performance target: switch-dispatch baseline, direct-threading comparison, or “fast enough” pedagogical interpreter.
- Need GC requirement: exact moving/non-moving/incremental/generational, and whether all heap objects are Lalin-owned or externally allocated.
