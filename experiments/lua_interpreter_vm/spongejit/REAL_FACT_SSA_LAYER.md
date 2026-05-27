# SponJIT Real Fact + SSA Layer

The foundry is only as strong as its fact and SSA layer. Runtime SponJIT must remain
copy/patch/link, but the offline foundry must become a real optimizing compiler over
Lua VM semantics.

This document replaces the "first slice" SSA mentality. Facts are not strings. SSA is
not a list of node names. The fact/SSA layer is the system brain.

## Goal

Given an observed Lua bytecode window plus an assumption signature, produce:

1. A typed SSA graph representing exact VM semantics under those assumptions.
2. A closed set of checked facts, derived facts, invalidation dependencies, and guard exits.
3. An optimized residual-free or residual-minimized graph.
4. A semantic normal form stable enough to be cached, recursively atomized, and lowered to stencils.

Runtime does **not** optimize. Runtime observes facts, canonicalizes signatures, selects artifacts,
patches holes, and executes. All intelligence lives here.

## Non-negotiable invariants

1. **No untyped fact strings inside optimization.** Strings may exist only at IO boundaries.
2. **Every assumption has a subject.** Example: `slot(3) is i64`, `table(slot(1)) has shape S`, not `lhs_i64`.
3. **Every checked fact has a guard or proof.** If a fact enters codegen, it is either statically implied or guarded.
4. **Every guard has an exit projection.** Exit projection restores enough VM state to resume/interpreter-run.
5. **Effects are explicit.** Frame writes, heap writes, calls, barriers, and residual exits are SSA effects.
6. **Memory has identity.** Frame slots, table fields, arrays, globals, and GC state are distinct memory domains.
7. **Normal forms are graph-derived.** No source-pattern-only normal forms like hardcoded `FIELD_ADDI_UPDATE` as the authority.
8. **Facts form a lattice.** Closure, contradiction, implication, and invalidation are explicit operations.
9. **Recursive atoms reopen as semantics.** An atom carries typed SSA semantics, not just active op names.
10. **If the SSA cannot prove it, it must guard or residualize.** No silent optimistic lowering.

## Fact model

A fact is:

```lua
Fact {
  kind        -- type, shape, field, array, call, liveness, residency, gc, control
  subject     -- ValueRef, SlotRef, TableRef, ProtoRef, PCRef, MemoryRef
  predicate   -- is_i64, shape_eq, key_const, metatable_absent, target_eq, etc.
  value       -- optional payload: shape id, function id, constant, offset, arity
  source      -- observed | guard | implied | static | atom
  confidence  -- proven | assumed | profiled
  deps        -- invalidation deps: shape_epoch, proto_epoch, metatable_epoch, gc_epoch...
}
```

### Core fact domains

| Domain | Examples | Enables |
|---|---|---|
| Type | `value is i64`, `value is f64`, `value is table`, `value is closure` | unbox removal, native arithmetic |
| Constant | `value == 7`, `key == "x"`, `nargs == 2` | immediate patching, branch folding |
| Shape | `table.shape == S`, `field("x").offset == 24` | direct field load/store |
| Metatable | `metatable absent`, `no __index`, `no __newindex` | no metamethod residual |
| Array | `key is int`, `bounds ok`, `array part present` | direct array load/store |
| Call | `target == proto/function`, `arity known`, `callee leaf` | call specialization/inlining |
| Frame | `slot N contains V`, `slot N dead`, `slot N overwritten` | store elimination, forwarding |
| Liveness | `value dead after pc`, `result returned`, `slot reused` | DCE, final store removal |
| Residency | `value in rax`, `i64 in rcx`, `flags live` | load/unbox/box elimination |
| GC/barrier | `barrier clean`, `black/white impossible`, `no alloc` | barrier removal |
| Control | `branch direction known`, `loop bound known`, `backedge stable` | branch folding, loop guards |

### Fact operations

The fact engine must provide:

```lua
FactSet:add(fact)
FactSet:close()                 -- implication closure
FactSet:contradictions()        -- impossible signatures rejected before SSA
FactSet:implies(fact)
FactSet:guards_required()       -- facts that need runtime guards
FactSet:deps()                  -- invalidation keys
FactSet:canonical_key()         -- cache key component
FactSet:project(subjects)       -- facts relevant to a subgraph/atom
FactSet:merge(other)            -- compose atom facts
```

Examples of closure:

- `table.shape == S` implies `value is table`.
- `shape S field "x" offset O` plus `key == "x"` implies `field_offset == O`.
- `metatable absent` implies no `__index`/`__newindex` metamethod.
- `call target == F` implies `known_call_target` and maybe `arity == F.arity`.
- `slot N contains V` plus `V is i64` implies `slot N is i64`.

## SSA IR model

SSA must model values, memory, effects, and exits explicitly.

### Value classes

```lua
Value {
  id
  ty          -- TValue, I64, F64, Bool, PtrTable, PtrClosure, Shape, FieldAddr, Void
  facts       -- FactRefs known for this value
  residency   -- optional physical constraint/preference
}
```

### Memory domains

```lua
Memory {
  frame       -- Lua stack/frame slots
  table_shape -- shape/field layout observations
  table_array -- array part
  globals
  gc
  call_world
}
```

Operations consume and produce memory tokens when they affect or observe mutable state.
This is what makes load forwarding and store elimination correct.

Examples:

```lua
v, frame2 = FrameLoad(frame1, slot)
frame2    = FrameStore(frame1, slot, v)
shape     = GuardShape(table, expected_shape, exit)
v         = FieldLoad(table, field_offset, table_shape_mem)
table_mem2 = FieldStore(table_mem1, table, field_offset, v)
gc2       = BarrierCheck(gc1, table, v, exit)
```

### Guard model

Guards are first-class nodes:

```lua
Guard {
  subject
  fact
  deps
  exit_projection
}
```

A guard is removable only if the fact is already proven in the dominating fact environment.
A guard is movable only if its subject and memory dependencies dominate the new location.

### Exit projection

Every guard/residual/call exit carries projection:

```lua
ExitProjection {
  pc
  base
  live_slots
  virtual_values
  pending_results
  reason
}
```

Projection is the contract that lets aggressive SSA remain safe. If projection cannot be
built, the optimization is illegal.

## Optimizer architecture

Passes should operate on typed graph + fact environment, not op-name strings.

### Phase order

1. **Fact canonicalization**
   - Parse observed facts into typed facts.
   - Close implication lattice.
   - Reject contradictions.
   - Produce canonical signature key.

2. **Bytecode lift**
   - Decode PUC Lua op operands.
   - Create slots, constants, proto refs, upvalue refs.
   - Emit typed SSA with explicit frame/table/gc/call memory.

3. **Fact application**
   - Insert guards for assumed facts.
   - Attach derived facts to values.
   - Replace generic VM operations with specialized ops when proven/guarded.

4. **Sparse propagation**
   - Type propagation.
   - Constant propagation.
   - Shape/field propagation.
   - Residency/liveness propagation.

5. **Memory SSA optimization**
   - Frame load/store forwarding.
   - Dead frame store elimination.
   - Field load forwarding across shape-stable regions.
   - Barrier elimination when GC facts prove clean.

6. **Semantic simplification**
   - Box/unbox cancellation.
   - Guard dedupe/dominance.
   - Metamethod residual removal under metatable facts.
   - Bounds-check elimination.
   - Branch folding.

7. **Atom reopening**
   - Inline selected atom SSA graphs.
   - Rename values/memory tokens.
   - Merge fact environments.
   - Optimize across old atom boundaries.

8. **Normal-form derivation**
   - Canonicalize graph by semantic operations, guards, exits, deps, and holes.
   - Hash graph structure, not source opcode spelling.

9. **Lowerability validation**
   - Every active node covered by stencil or residual.
   - Every hole has patch contract.
   - Register/residency constraints satisfiable.
   - Projection obligations satisfied.

## Important optimizations unlocked

### Numeric paths

- `TValue -> guard_i64 -> unbox_i64 -> add_i64 -> box_i64` becomes direct native chain.
- If consumer wants native i64, avoid reboxing.
- If producer already gave native i64, avoid unbox.
- Constant RHS becomes immediate arithmetic.

### Table field paths

Under shape + key + metatable facts:

```text
GETFIELD x; ADDI 1; SETFIELD x
```

becomes:

```text
GuardShape(table, S)
old = FieldLoad(table, offset_x)
GuardI64(old)
new = AddI64(Unbox(old), 1)
FieldStore(table, offset_x, Box(new))
```

Then memory SSA can remove redundant frame traffic and stencil lowering can emit a fused
field-increment artifact.

### Array paths

Under array-hit + key-i64 + bounds facts:

- remove hash lookup
- remove metamethod residual
- remove bounds check when proven
- direct load/store at `array_base + index * sizeof(TValue)`

### Call paths

Under target + arity facts:

- direct known-call boundary
- optional leaf-call specialization
- recursive absorption of callee prefix as an atom
- call exit projection knows exact result slots

## File plan

The current `src/ssa.lua` should become a facade. Real pieces:

| File | Responsibility |
|---|---|
| `src/facts.lua` | Fact objects, lattice, closure, canonical keys, contradictions |
| `src/ssa_ir.lua` | Typed SSA graph, values, memory tokens, guards, exits |
| `src/ssa_lift.lua` | PUC Lua opcode + operand semantics to SSA |
| `src/ssa_apply_facts.lua` | Guard insertion and specialized operation selection |
| `src/ssa_opt.lua` | Typed optimization passes |
| `src/ssa_normalize.lua` | Semantic normal form and hashing |
| `src/ssa_atoms.lua` | Atom serialization/reopening/renaming |
| `src/ssa_validate.lua` | Invariants, projection, coverage, residency validation |
| `src/ssa.lua` | Public facade preserving `compile`, `compile_nodes`, `semantic_normal_form` |

## Test requirements

Before calling this real, we need tests for:

1. Fact closure and contradictions.
2. Guard insertion exactly matches checked facts.
3. Every guard has exit projection.
4. Frame store/load forwarding with explicit slot identity.
5. Dead store elimination respects calls/residuals/barriers.
6. Table field load/store forwarding respects shape/metatable deps.
7. Barrier elimination only under valid GC facts.
8. Normal form is stable under alpha-renaming.
9. Atom reopening preserves semantics and improves across boundaries.
10. Lowering rejects uncovered active nodes loudly.

## Success metrics

A real layer should show measurable improvements:

- More layer-1/layer-2 discovered forms from atom reopening.
- Fewer active SSA nodes per template.
- Fewer guards per template for equivalent checked facts.
- Fewer residual boundaries.
- Lower total pack bytes for same coverage.
- Higher corpus coverage under 50 MB budget.

## Implementation stance

No more one-off pattern hacks as the source of truth. Patterns may be used as tests or
fused-stencil names, but the canonical result must come from typed facts + typed SSA +
explicit memory/effect semantics.
