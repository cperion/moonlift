# SpongeJIT SSA Engine Design 
Architecture exploration for a strong but non-overengineered SSA engine that lowers PUC Lua 5.5 opcode sequences into optimized canonical normal forms for fast C stencil generation and reduced stencil diversity.
**Started**: 2026-05-29 01:26:09
---

## Scout Output — 2026-05-29 01:29:52

## Files Retrieved

1. `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` (lines 1-139) - Public SSA facade: lift → optimize → normalize/hash → summarize.
2. `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` (lines 1-423) - Core typed SSA graph, value/effect/memory model, op vocabulary, exits, guards, canonical graph lines.
3. `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` (lines 1-322) - PUC opcode-sequence lifter into SSA; fact-driven specialization and GenericExit fallback points.
4. `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` (lines 1-242) - Current optimizer passes; intentionally minimal, relying on GCC for most machine-level simplification.
5. `experiments/lua_interpreter_vm/spongejit/src/ssa_normalize.lua` (lines 1-202) - Semantic normal form compression, checked facts/deps/projection, canonical graph key/hash.
6. `experiments/lua_interpreter_vm/spongejit/src/ssa_to_c.lua` (lines 1-545) - SSA → monolithic C stencil generator, hole allocation/catalog, patchable extern `__H_N` strategy.
7. `experiments/lua_interpreter_vm/spongejit/src/ssa_contract.lua` (lines 1-117) - SSA-derived tile fact transfer contracts: selector/required/checked/produced/killed.
8. `experiments/lua_interpreter_vm/spongejit/src/facts.lua` (lines 1-303) - Rich typed fact lattice: subjects, predicates, implication closure, deps, contradictions, legacy compatibility.
9. `experiments/lua_interpreter_vm/spongejit/src/fact_signature.lua` (lines 1-185) - 64-bit runtime fact ABI and mask operations.
10. `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` (lines 1-354) - Curated fact-axis/bundle enumeration for opcode windows.
11. `experiments/lua_interpreter_vm/spongejit/src/fact_schema.lua` (lines 1-223) - Older/high-level fact vocabulary and primitive rewrite schemas.
12. `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` (lines 1-710) - Bank metadata generation, pattern selection tables, hole reloc classification, patchability flags, selector C emission.
13. `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` (lines 1-471) - Grammar enumeration of PUC opcode sequences, handler-class dedupe, fact-subset compilation.
14. `experiments/lua_interpreter_vm/spongejit/src/stencil_model.lua` (lines 1-268) - Abstract stencil vocabulary and legacy/model lowering.
15. `experiments/lua_interpreter_vm/spongejit/src/puc_bytecode.lua` (lines 1-334) - PUC bytecode/static/dynamic profiling and operand-window extraction.
16. `experiments/lua_interpreter_vm/spongejit/src/enumerate.lua` (lines 1-590) - Corpus/atom-driven SSA-form enumeration and scoring.
17. `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 1-95) - Parallel foundry worker: fact axes → SSA compile → C gen → contracts/hole JSON.
18. `experiments/lua_interpreter_vm/spongejit/foundry.lua` (lines 1-284) - Foundry orchestration and multi-layer atom loop.
19. `experiments/lua_interpreter_vm/spongejit/generate_all_c.lua` (lines 1-252) - Corpus → SSA → C generation pipeline.
20. `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` (lines 1-168) - Runtime ABI: tile descs, holes, fact sigs, selector APIs.
21. `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.c` (lines 1-403) - PUC integration: opcode stream extraction, slot mapping, tile selection, copy/patch, execution, counted loop driver.
22. `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.h` (lines 1-38) - PUC image/runtime API.
23. `experiments/lua_interpreter_vm/spongejit/puc/README.md` (lines 1-113) - Current benchmark/integration status and constraints.
24. `experiments/lua_interpreter_vm/spongejit/runtime/materialize.lua` (lines 1-260) - Older LuaJIT FFI materializer proving copy/patch/link execution.
25. `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 1-136) - SSA/fact invariants and regression expectations.
26. `experiments/lua_interpreter_vm/spongejit/test_ssa_to_c.lua` (lines 1-187) - End-to-end SSA→C examples.
27. `experiments/lua_interpreter_vm/tests/test_spongejit_materialize.lua` (lines 1-35) - Materializer smoke test.
28. `experiments/lua_interpreter_vm/spongejit/bench_stencil_vs_interp.lua` (lines 1-276) - Benchmark harness for generated C vs interpreted sketches.

## Key Code

### SSA facade and compile pipeline

```lua
-- src/ssa.lua
function M.compile(ops, facts, config)
    local fs = factset(facts)
    local g = Lift.lift(ops or {}, fs, config)
    Opt.optimize(g, config)
    return summarize(g, ops or {}, fs, config)
end
```

Summary includes:

```lua
normal_form = Norm.semantic_normal_form(g),
normal_form_hash = Norm.hash(g),
active_ops = Norm.active_codegen_ops(g),
active_node_specs = active_node_specs(g),
checked_facts = Norm.checked_fact_names(g),
deps = Norm.deps(g),
projection = Norm.projection(g),
canonical_graph = Norm.canonical_graph_key(g),
```

### SSA graph model

```lua
-- src/ssa_ir.lua
local EFFECTS = {
    none = true, guard = true, frame_read = true, frame_write = true,
    heap_read = true, heap_write = true, gc_barrier = true, call = true,
    residual = true, branch = true, return_ = true,
}

local HARD_BARRIER = {
    Call = true, KnownCall = true, TailCall = true,
    Residual = true, GenericExit = true, Jump = true,
}
```

Key strengths to preserve:
- typed values (`TValue`, `I64`, `PtrTable`, etc.)
- explicit effects
- explicit memory domains (`frame`, `table`, `gc`, `call`)
- explicit guard exits/projections
- source opcode index on nodes

### Current lowering boundary

```lua
-- src/ssa_lift.lua
-- Missing facts or unsupported VM semantics become structured GenericExit nodes;
-- backend gaps are not hidden here.
```

Examples:

```lua
local function i64_from_slot(g, slot, role, pc)
    local ok, subj = has_slot(g, slot, "is_i64", { role or "value", "last" })
    if not ok then return nil end
    local tv = load_slot(g, slot, pc)
    guard(g, tv, mkfact("type", subj, "is_i64"), "GuardTypeI64", pc)
    return g:unbox_i64(tv, pc)
end
```

Unsupported or under-modeled paths:
- `FORLOOP`/`FORPREP` fact axes exist, but lifter currently residualizes them.
- `TEST`, `TESTSET`, many upvalue/metamethod/vararg/closure paths residualize.
- comparisons currently lower as boxed integer/boolean-ish values into synthetic `dest`, not real PUC skip-next control.
- `POW` residualizes.
- `GETTABUP`/`SETTABUP` residualize.
- array/field/call payload facts are partly accepted but runtime patchability is incomplete.

### Current optimizer policy

```lua
-- src/ssa_opt.lua
function M.optimize(g, config)
    -- Only pass_frame_forward (GCC can't alias HOLE references) and
    -- pass_guard_dominance (GCC doesn't know Lua guard semantics).
    -- Everything else (copy prop, box/unbox, dead store, constant fold, DCE)
    -- GCC does better than our SSA optimizer.
    pass_frame_forward(g)
    pass_guard_dominance(g)
    pass_barrier_elim(g)
    pass_field_forward(g)
    return g
end
```

Existing disabled-but-present passes:
- copy forwarding
- box/unbox elimination
- dead frame store elimination
- constant folding
- DCE

This is directly relevant to “strong but non-overengineered”: the project already wants SSA to do semantic/canonical work, while leaving final machine optimization to GCC.

### Normal form weakness

```lua
-- src/ssa_normalize.lua
local function val(v, map)
    if not v then return "" end
    if not map[v] then map[v] = "v" .. tostring(#map + 1) end
    return map[v]
end
```

Because `map` is keyed by value IDs, `#map` is normally `0`; many distinct SSA values rename to `v1`. Observed output:

```text
FrameLoad;;v1...
UnboxI64;v1;v1...
FrameLoad;;v1...
AddI64;v1,v1;v1...
```

This can weaken canonical hashing/equivalence and obscure real def-use structure.

Also:

```lua
function M.semantic_normal_form(g)
    return compress_patterns(active_semantic_ops(g))
end
```

`semantic_normal_form` is mostly an opcode sequence compressor, not a dataflow-aware canonical form.

### Patchable C stencil generation

```lua
-- src/ssa_to_c.lua
extern const char __H_0[]; ... __H_127[];
```

Holes are allocated while emitting C:

```lua
local h = holes:alloc(slot_name, n.source and (n.source - 1) or 0)
emit(string.format("int sl_%d = (int)(uintptr_t)__H_%d;", h, h))
```

Examples:
- slot holes: `R0`, `R1`, `slot_R1`
- immediates: `imm`, `sC`, `sBx`
- constants: `k_idx`, `k_i64`
- guards/exits: `fail`, `exit_*`
- payloads: `shape_offset`, `shape_id`, `field_offset`, `array_base_offset`, `call_target`, `barrier`

Important fusion:

```lua
-- BoxI64 followed by FrameStore
base[f_slot_%d].value_ = (unsigned long long)(%s);
base[f_slot_%d].tt_ = 3;
forwarded[outputs[1]] = in_v
```

So some “SSA optimization” is currently happening in codegen.

### Fact contracts

```lua
-- src/ssa_contract.lua
facts_out = (facts_in - killed) | produced | checked
```

Implementation:
- `checked`: surviving guard nodes
- `produced`: `FrameStore` whose producer chain has `BoxI64`
- `killed`: slot facts killed by stores; table/payload facts killed by calls/writes/barriers
- `required = selector - checked`

This is a good preservation point: it bridges offline SSA facts to runtime image selection.

### Runtime fact ABI

```lua
-- src/fact_signature.lua
M.SLOT_FACT_BASE = {
  i64 = 0, is_i64 = 0,
  table = 8, is_table = 8,
  shape_known = 16,
  metatable_absent = 24,
  array_hit = 32,
  bounds_ok = 40,
  known_call_target = 48,
}
```

Global/payload bits:

```lua
barrier_clean = 56,
const_i64 = 57,
key_const = 58,
nonzero_i64 = 59,
shape_payload = 60,
array_payload = 61,
call_target_payload = 62,
```

### Curated fact axes

```lua
-- src/ssa_fact_axes.lua
-- semantic bundles: facts that must travel together for a lowering to be executable
```

Good existing design:
- numeric bundles require operand slot `is_i64`
- field bundles require table type, shape, metatable absence, key const, field offset
- array bundles require table type, metatable absence, array hit, bounds, base offset
- call bundles require closure/call-target facts
- subsets emit floor, single-op bundles, prefix cumulative bundles, tiered cumulative bundles, full bundle

This should be preserved; it prevents blind powerset explosion.

### Bank selection and patchability

Runtime bank only accepts PUC-patchable tiles when requested:

```lua
-- generated by src/build_bank.lua
if (t && ((t->flags & required_tile_flags) == required_tile_flags)
    && ((t->fact_sig & ~available_sig) == 0)
    && ((t->required_sig & ~facts) == 0)
    && tile_matches_actual_slots(...)) { chosen = tid; ... }
```

Patchable roles are restricted:

```lua
local PUC_PATCHABLE_ROLES = {
  unknown, slot, imm, const, bool, exit, fail, slot_store
}
```

Non-patchable today:
- shape offset/id
- metatable offset
- field offset
- array base offset
- call target
- barrier

So field/array/call specialized stencils may compile into the bank, but are rejected by PUC image selection unless payload patching exists.

### PUC runtime image flow

```c
// puc/sponjit_runtime.c
build_semantic_stream(...)
spon_select_flow_flags_slots_stats(..., SPON_TILE_PUC_PATCHABLE, ...)
materialize_tile(...)
execute_tile_range(...)
```

Important:
- runtime does not run SSA or generate code
- runtime observes only i64 slot facts currently:

```c
SponFactSig spon_observe_i64_slots(StkId base, uint32_t max_slots) {
  if (ttisinteger(s2v(base + i))) sig |= 1 << i;
}
```

- semantic stream skips `MMBIN` companions after arithmetic
- actual slot stream maps foundry logical slots to real PUC operands
- `patch_value` refuses shape/table/call/barrier payload holes

## Relationships

### Offline foundry path

```text
grammar_enum / enumerate
  → ssa_fact_axes.axes_for_ops + subsets
  → ssa.compile
      → ssa_lift
      → ssa_opt
      → ssa_normalize/hash
  → ssa_to_c.generate
  → ssa_contract.from_result
  → worker_compile JSON/C chunks
  → gcc/objdump/nm
  → build_bank.lua
  → libsponbank.c/libsponbank.so
```

### Runtime path

```text
PUC Proto bytecode
  → build_semantic_stream opcode IDs
  → build_actual_slot_stream operand slots
  → spon_select_flow_flags_slots(...)
      pattern key + fact masks + contract transfer + actual slot compatibility
  → materialize_tile copies .text and patches holes
  → SponExecCtx execution
  → exit_kind/resume_pc back to interpreter
```

### Fact flow

```text
Rich facts in Lua foundry
  → projected to 64-bit fact signature
  → TileDesc: fact_sig, required_sig, checked_sig, produced_sig, killed_sig
  → runtime selection propagates:
      facts = (facts & ~killed) | produced | checked
```

### Normal form/dataflow relationship

Current `normal_form_hash` depends on:

```text
canonical_graph_key(g)
+ sorted checked fact guard keys
+ deps
```

But `semantic_normal_form` is mostly human/coarse and sequence-oriented. The canonical graph key is closer to the real dedupe key but currently has value-renaming problems and includes patchable immediates as literal args.

## Observations

1. **Preserve the current architectural split.** Runtime selection/copy/patch is intentionally simple and does not run SSA. SSA belongs offline in the foundry.

2. **Current SSA is “linear effect SSA”, not CFG SSA.** That fits opcode-window stencils. A strong-but-not-overengineered redesign likely should keep linear regions + explicit exits, not introduce full global CFG/phi machinery unless loop-body image SSA requires it.

3. **Normal forms are currently too weak for stencil diversity reduction.**
   - `semantic_normal_form` is an op-sequence compressor.
   - composite patterns are exact sequence matches.
   - patchable immediates diversify hashes:
     - `LOADI 1`, `LOADI 2`, `LOADI 42` produce same semantic NF but different hashes.
   - current canonical value renaming appears broken (`#map + 1` on non-array map).

4. **Patchable operands need abstraction in canonical forms.**
   C generation treats immediates/constants/slots as holes, but canonical hashing often includes their concrete values (`ConstI64 value=7`, `slot=R0`). A better SSA normal form probably needs:
   - hole variables for patchable immediates/constants/slots
   - equality/alias constraints for slot relationships
   - concrete literals only when they affect stencil shape, not runtime patch values.

5. **Good existing infrastructure to preserve:**
   - `ssa_ir` typed values/effects/exits/memory domains
   - `facts.lua` rich fact records and implication/dependency closure
   - `ssa_fact_axes.lua` curated semantic fact bundles
   - `fact_signature.lua` compact runtime ABI
   - `ssa_contract.lua` fact transfer masks
   - `build_bank.lua` slotmaps and patchability filtering
   - `sponjit_runtime.c` image-entry model, not per-dispatch tile calls

6. **Codegen currently owns some semantic simplification.**
   `ssa_to_c.lua` fuses `BoxI64 + FrameStore` and tracks `forwarded`. If the SSA engine becomes “fully lowered normal forms”, some of this should likely move into SSA/canonical lowering, leaving codegen as a straightforward emitter.

7. **Optimizer intentionally relies on GCC, but SSA still must do Lua-semantic opts.**
   GCC cannot know:
   - redundant Lua guards
   - fact domination
   - frame slot equivalence through patchable holes
   - Lua value tagging invariants
   - fact kills/leases across VM effects

8. **PUC patchability is a major constraint.**
   Integrated runtime currently filters to `SPON_TILE_PUC_PATCHABLE`; payload-specialized field/array/call tiles are excluded because `patch_value` refuses shape/field/array/call/barrier holes. SSA design should separate:
   - canonical semantic form
   - patchable hole contract
   - runtime payload availability

9. **Fact lifetime is partly handled after the fact by contracts, not during lifting.**
   Lifter consults one immutable entry `FactSet`; it does not update facts after stores/effects while lowering a multi-op window. Contracts later kill/produce facts for inter-tile flow. For intra-tile lowering, this can be conservative-safe if every use is guarded at runtime, but it is not a strong symbolic state model.

10. **PUC 5.5 opcode semantics are only partially represented.**
    Grammar lists many opcodes, but lifter only specializes a subset. Several PUC semantics are simplified:
    - compare ops as value-producing, not branch/skip
    - loop ops residualized despite fact axes
    - metamethod companion handling mainly in runtime stream skipping, not SSA semantics
    - upvalues/table payloads incomplete for integrated runtime

11. **The strongest immediate design target appears to be a canonical lowering layer between lift and codegen.**
    It would preserve current SSA graph/effect model but add:
    - stable value numbering/renaming
    - patch-hole abstraction
    - slot-state/value-state tracking
    - explicit lowered C-ready primitives
    - guard/fact normalization
    - simple def-use canonicalization
    - no heavy global optimizer or register allocator, since GCC handles final machine optimization.

## Knowledge-builder Output — 2026-05-29 01:32:57

### What Matters Most for This Problem

- **Semantic canonicalization, not classic machine optimization**: the SSA engine’s main value is reducing stencil diversity while preserving Lua semantics and fact contracts; GCC handles low-level code cleanup.
- **Patchable-hole abstraction**: runtime-patched slots/immediates/constants must not unnecessarily diversify canonical forms, but their equality/aliasing relationships remain semantically important.
- **Fact soundness across offline/runtime boundary**: checked, required, produced, and killed facts are part of the executable contract, not just optimizer metadata.
- **Lowering completeness for C stencils**: “fully lowered” means codegen receives simple, explicit, C-ready operations with no hidden semantic rewrites.
- **PUC Lua control semantics**: opcode windows are not just arithmetic traces; comparisons, tests, loops, metamethod companions, exits, and resume PCs affect correctness.
- **Bank/runtime constraints**: the runtime cannot run SSA and currently only patches a restricted class of holes, so canonical forms must align with what the bank can actually select and materialize.

---

### Non-Obvious Observations

- **This is closer to an offline partial evaluator than a normal JIT SSA optimizer.**  
  A normal JIT optimizer improves one hot trace or method. SpongeJIT is manufacturing a reusable stencil bank ahead of time. The key output is not merely faster code, but fewer distinct canonical stencil shapes that remain patchable and selectable at runtime.

- **Canonical equivalence is constrained by runtime materialization, not just semantics.**  
  Two opcode windows may be semantically equivalent after abstracting immediates, but they are not necessarily the same stencil if their hole roles, patchability class, slot aliasing, exit behavior, or fact-transfer contract differ.

- **The current normal form under-represents dataflow.**  
  `semantic_normal_form` mostly compresses opcode sequences, while the real diversity problem lives in def-use structure, frame slot relationships, guards, constants, and patch holes. The broken value renaming in `ssa_normalize.lua` makes this worse: distinct values can collapse to the same canonical name, hiding important structure.

- **Over-canonicalization can be unsound.**  
  Abstracting `LOADI 1` and `LOADI 42` is often desirable, but concrete values may matter when they affect control, table keys, shape payloads, array bounds, or fact implications. The normal form must distinguish “patch value” from “semantic discriminator.”

- **Fact contracts are part of the IR semantics.**  
  Guards are not disposable checks; surviving guards become `checked` facts, frame stores can produce slot facts, and effects kill facts. Optimizations that remove, reorder, or fuse nodes must preserve the resulting `required/checked/produced/killed` masks.

- **The lifter currently treats entry facts as immutable inside a tile.**  
  This is safe only insofar as runtime guards and later contract kills preserve correctness. But for stronger intra-tile optimization, stores, calls, heap writes, and barriers imply a symbolic fact lifetime problem. Otherwise the lifter may specialize later ops using stale entry assumptions.

- **Codegen currently owns semantic lowering responsibilities.**  
  `ssa_to_c.lua` fuses `BoxI64 + FrameStore`, forwards frame values, and emits specialized C patterns. That means the “SSA normal form” is not yet the final lowered form; some canonical diversity and semantic identity are decided too late, after hashing/normalization.

- **GCC reliance has a sharp boundary.**  
  GCC can fold arithmetic, remove dead locals, and optimize C expressions. It cannot understand Lua tags, frame slot facts, guard dominance, fact kills, patch-hole aliasing, or tile selection contracts. Those must remain explicit in SSA-level reasoning.

- **Patchability is currently the biggest practical limiter on specialization.**  
  Field/array/call-specialized SSA forms may be generated offline, but PUC runtime rejects non-`SPON_TILE_PUC_PATCHABLE` tiles when payload holes require shape offsets, field offsets, array bases, call targets, or barriers. Canonical SSA strength alone will not make those stencils usable unless their hole contracts match runtime capabilities.

- **Slot identity is both abstract and concrete.**  
  For bank reuse, logical slots like `R0`, `R1`, `R2` should often be canonicalized. But runtime selection still verifies actual slot compatibility. Therefore the meaningful invariant is not the literal slot number; it is the pattern of slot equality, reads, writes, and role mapping.

- **Exit behavior participates in stencil identity.**  
  Guards, `GenericExit`, residual paths, fail holes, and resume PCs are not incidental. Two forms with identical arithmetic but different bailout points or resume semantics cannot be blindly merged.

- **PUC opcode windows are linear, but not semantically straight-line.**  
  The existing “linear effect SSA” fits stencil windows, but opcodes like `EQ`, `LT`, `LE`, `TEST`, `TESTSET`, `FORLOOP`, `FORPREP`, calls, and metamethod companions encode control decisions. Treating them as value-producing arithmetic-like nodes risks canonical forms that are fast but not faithful.

- **The `MMBIN` handling split is risky.**  
  Runtime semantic stream construction skips metamethod companion opcodes after arithmetic, while SSA lowering residualizes or specializes selected operations. This means opcode-window identity partly lives outside SSA. Any stronger normal form must account for the fact that the runtime stream has already transformed the bytecode sequence.

- **The fact-axis system is a guardrail against combinatorial explosion.**  
  The curated bundles are not just convenience; they encode which facts must travel together for a lowering to be executable. A stronger SSA engine that ignores this could produce many theoretically valid but practically unselectable forms.

- **The hash key must balance semantic reuse against ABI stability.**  
  If concrete immediates and slots remain in hashes, stencil diversity stays high. If hashes ignore too much, bank entries may collide across incompatible patch contracts. The canonical graph key is therefore an ABI-facing artifact, not merely an internal cache key.

- **Memory domains are central despite the small optimizer.**  
  Frame, table, GC, and call effects determine which facts and forwarded values survive. This matters more here than in many toy SSA optimizers because a wrong fact after a heap write or call can select an invalid stencil.

- **“Fully lowered” does not mean “fully optimized.”**  
  The desired form should expose simple C-emittable primitives and explicit effects. It does not need register allocation, global value numbering over arbitrary CFGs, machine scheduling, or aggressive algebraic optimization. The specialized value is semantic lowering and canonicalization.

- **The runtime observes only a small subset of the rich fact lattice.**  
  Offline SSA can reason about many facts, but runtime currently observes mainly i64 slot facts. Any canonical form depending on facts outside the runtime-observable/projected ABI must be backed by selector metadata, patch payloads, or checked guards. Otherwise it may exist in the bank but never be chosen safely.

- **Produced facts from stores are subtle.**  
  A `FrameStore` produced by a `BoxI64` can establish an i64 fact for later tiles. But that depends on the producer chain surviving normalization and on no intervening effect killing the slot fact. This creates a hidden invariant between SSA node identity, optimizer rewrites, and contract generation.

- **Residualization is a correctness valve and a diversity source.**  
  `GenericExit` keeps unsupported semantics safe, but if many opcodes residualize, canonical forms may converge trivially around exits instead of useful lowered work. Conversely, specializing too much without payload patchability creates unusable bank entries.

- **C stencil generation makes aliasing more important than usual.**  
  The comment that GCC cannot alias through `HOLE` references explains why frame forwarding exists in SSA. The generated C shape affects what GCC can prove. Thus the SSA normal form must consider how facts and holes appear to C, not just abstract IR semantics.

---

### Knowledge Gaps

- Exact intended semantic coverage for PUC Lua 5.5 branch-like opcodes: `EQ`, `LT`, `LE`, `TEST`, `TESTSET`, `FORPREP`, `FORLOOP`.
- Whether payload patchability for shape/table/array/call/barrier holes is in scope for the near-term SSA design.
- Empirical stencil diversity sources: how much diversity currently comes from immediates, slots, guard facts, residual exits, or payload holes.
- Whether canonical hash stability is expected across foundry runs/builds, or only within one generation run.

## Approach-proposer Output — 2026-05-29 01:34:31

### Approach A: Evolutionary Linear SSA Canonicalizer
- **Core idea**: Keep the current linear effect-SSA architecture, but add a canonical lowering pass that makes patch holes, value numbering, slot state, guards, and C-ready primitives explicit before hashing/codegen.
- **Key changes**:
  - Extend `src/ssa_normalize.lua` with stable value renaming, hole abstraction, slot-equivalence constraints, and dataflow-aware canonical keys.
  - Add a lowering/canonicalization pass after `ssa_opt.lua`, possibly `src/ssa_lower.lua`.
  - Move codegen-only rewrites from `src/ssa_to_c.lua` into SSA lowering, especially `BoxI64 + FrameStore` fusion and frame forwarding.
  - Preserve `ssa_ir.lua`, `ssa_contract.lua`, `ssa_fact_axes.lua`, and runtime bank model.
- **Tradeoff**: Optimizes for low migration cost and immediate stencil diversity reduction; sacrifices deeper handling of branch-like opcodes and complex control semantics.
- **Risk**: The existing IR may accumulate too many special cases if lowering and normalization are layered onto it without clear boundaries.
- **Rough sketch**:
  - Fix canonical value numbering in `ssa_normalize.lua`.
  - Introduce canonical hole descriptors for slots, immediates, constants, exits, and patchability class.
  - Normalize logical slots by equality/role pattern rather than literal `R0`, `R1`, etc.
  - Add a pass that lowers common Lua-specialized idioms into explicit C-ready ops such as `StoreI64Slot`, `GuardSlotI64`, `AddI64Slot`.
  - Make `ssa_to_c.lua` mostly emit already-lowered nodes instead of performing semantic rewrites.

---

### Approach B: New Hole-Parametric Stencil IR
- **Core idea**: Treat current SSA as a semantic lifting IR, then lower into a separate canonical “Stencil IR” whose only purpose is reusable, patchable, C-emittable stencil shapes.
- **Key changes**:
  - Add a new module, e.g. `src/stencil_ir.lua` or `src/ssa_stencil_lower.lua`.
  - `ssa_lift.lua` still produces typed/effectful SSA.
  - `ssa_opt.lua` still performs Lua-semantic cleanup.
  - New Stencil IR contains explicit primitives, hole parameters, fact contract references, exits, and memory effects.
  - `ssa_normalize.lua` hashes Stencil IR instead of raw SSA.
  - `ssa_to_c.lua` emits from Stencil IR rather than full SSA.
- **Tradeoff**: Optimizes for architectural cleanliness and stable canonical forms; sacrifices short-term implementation simplicity because it introduces a second IR.
- **Risk**: If Stencil IR is too broad, it duplicates SSA; if too narrow, lifter/codegen escape hatches will reappear.
- **Rough sketch**:
  - Define a small closed vocabulary: frame loads/stores, unbox/box, arithmetic, guards, exits, table payload ops, calls/residuals.
  - Represent every runtime-patched value as a typed hole with role and equality constraints.
  - Lower SSA into Stencil IR with explicit fact-kill/fact-produce annotations.
  - Hash only Stencil IR shape plus hole contract plus exit/fact contract, not concrete patch values.
  - Update C generation and bank metadata to consume the same hole table used by the canonical hash.

---

### Approach C: Bounded Control-Region SSA
- **Core idea**: Upgrade the SSA engine from purely linear effect SSA to bounded region SSA with explicit local control exits, while still keeping runtime materialization as simple copy/patch.
- **Key changes**:
  - Extend `ssa_ir.lua` with lightweight block/continuation concepts, not full global CFG/phi machinery.
  - Teach `ssa_lift.lua` to lower branch-like PUC opcodes more faithfully: `EQ`, `LT`, `LE`, `TEST`, `TESTSET`, `FORPREP`, `FORLOOP`.
  - Normalize control regions by canonical block order, exit kind, resume PC, and patch-hole contract.
  - Keep unsupported paths as explicit `GenericExit`.
  - `ssa_to_c.lua` emits structured C for bounded branches or early exits.
- **Tradeoff**: Optimizes for semantic coverage and correctness for PUC control opcodes; sacrifices simplicity and likely delays immediate diversity wins.
- **Risk**: Could drift toward a real compiler CFG, violating the “non-overengineered” goal unless region size and control forms are tightly bounded.
- **Rough sketch**:
  - Model opcode windows as small regions with explicit exits rather than only linear node streams.
  - Add canonical block parameters only where needed for loop/test semantics.
  - Lower compare/test opcodes according to PUC skip-next/resume behavior.
  - Include exit structure in canonical hashes and contracts.
  - Keep runtime unchanged: selected tiles are still copied, patched, and executed as single stencil images.

---

### Comparison

Pick **Approach A** if the goal is the fastest path to a stronger SSA engine with minimal disruption. It directly fixes weak canonicalization, abstracts patch holes, and moves semantic rewrites out of codegen.

Pick **Approach B** if the desired long-term architecture is a clean foundry pipeline where SSA explains semantics and a separate Stencil IR defines reusable C stencil shapes. This is probably the best balance of strength and maintainability, but costs more upfront.

Pick **Approach C** if correct handling of PUC branch/test/loop opcode windows is the priority. It gives the most semantic headroom, but is the riskiest and easiest to overbuild.

## Critique Output — 2026-05-29 01:36:13

### Approach A: Evolutionary Linear SSA Canonicalizer

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 3/5 | Keeps existing modules, but risks further entangling `ssa_normalize.lua`, `ssa_opt.lua`, and `ssa_to_c.lua` unless boundaries are strict. |
| **Cohesion** | 3/5 | Improves SSA responsibility, but canonicalization, lowering, and emission may remain blurred. |
| **Migration cost** | 2/5 | Lowest disruption: existing IR, contracts, runtime, and bank model mostly stay intact. |
| **Philosophy fit** | 5/5 | Matches the current linear effect-SSA, offline foundry, GCC-for-machine-opts philosophy. |
| **Risk** | 2/5 | Mostly known territory. Main risk is architectural accretion rather than correctness explosion. |
| **Testability** | 5/5 | Can be validated incrementally: value renaming, hole abstraction, hash stability, then codegen rewrites. |
| **Performance potential** | 3/5 | Can improve generated C shape and reduce duplicate stencils, but does not cleanly separate semantic SSA from stencil ABI. |
| **Stencil diversity reduction** | 4/5 | Directly attacks current diversity sources: broken value renaming, concrete slots/immediates, codegen-only rewrites. |

**Verdict**: Yes with caveats  
**Key concern**: Avoid turning the existing SSA/normalizer/codegen stack into a pile of special-case canonicalization rules.

---

### Approach B: New Hole-Parametric Stencil IR

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 5/5 | Best separation: semantic SSA explains Lua behavior; Stencil IR describes reusable, patchable, C-emittable shapes. |
| **Cohesion** | 5/5 | Gives each layer a crisp job: lift semantics, optimize semantic facts, lower to stencil shape, hash/emit/materialize. |
| **Migration cost** | 4/5 | Requires touching normalization, C generation, hole allocation, bank metadata, and tests. Not trivial. |
| **Philosophy fit** | 5/5 | Strongly matches SpongeJIT’s actual model: offline partial evaluation into reusable stencil images, simple runtime copy/patch. |
| **Risk** | 3/5 | Main risk is scope creep: if Stencil IR becomes a second full compiler IR, it duplicates SSA and becomes overbuilt. |
| **Testability** | 4/5 | Can be tested as a pure lowering/hash/emission boundary, though migration touches more pipeline stages than A. |
| **Performance potential** | 5/5 | Highest practical upside: better stencil reuse, simpler generated C, fewer codegen-side semantic hacks, no added runtime cost. |
| **Stencil diversity reduction** | 5/5 | Best fit for canonicalizing holes, slot equality, fact contracts, exits, and patchability without losing ABI-relevant distinctions. |

**Verdict**: Strong yes  
**Key concern**: Keep Stencil IR narrow: it should be a stencil-shape ABI, not a general replacement for SSA.

**How to shape Approach B so it stays strong but non-overengineered**

- Treat current SSA as the **semantic authority**.
- Treat Stencil IR as the **materialization/canonicalization authority**.
- Keep the runtime unchanged: no SSA, no dynamic lowering, no optimizer; only select, copy, patch, execute.
- Hash Stencil IR by:
  - operation shape,
  - typed hole roles,
  - hole equality/alias constraints,
  - exit behavior,
  - patchability class,
  - fact contract shape.
- Do not hash concrete patch values unless they affect stencil shape or semantics.
- Preserve `ssa_contract.lua`, `ssa_fact_axes.lua`, and `fact_signature.lua` as first-class constraints.
- Keep unsupported or unpatchable semantics explicit via exits/residuals rather than smuggling complexity into runtime.
- Move codegen-only semantic rewrites, such as `BoxI64 + FrameStore` fusion, into the SSA→Stencil lowering boundary.

This gives Approach B the architectural cleanliness of a second IR without turning it into a full CFG compiler.

---

### Approach C: Bounded Control-Region SSA

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 2/5 | Control regions would affect `ssa_ir.lua`, lifter, optimizer, normalizer, codegen, contracts, and tests together. |
| **Cohesion** | 3/5 | More faithful for branch-like opcodes, but broadens SSA’s responsibility significantly. |
| **Migration cost** | 5/5 | Deepest rewrite. The current engine is intentionally linear effect SSA. |
| **Philosophy fit** | 3/5 | Fits eventual PUC semantic completeness, but risks violating the non-overengineered stencil-foundry model. |
| **Risk** | 5/5 | Highest risk of drifting into full compiler CFG/phi machinery. |
| **Testability** | 3/5 | Can test bounded regions, but correctness space grows sharply around resume PCs, exits, loops, and skip-next semantics. |
| **Performance potential** | 4/5 | Could unlock better branch/test/loop stencils, but only after substantial semantic work. |
| **Stencil diversity reduction** | 3/5 | Helps correctness and coverage more than immediate canonical diversity. It does not primarily solve hole abstraction. |

**Verdict**: Significant concerns  
**Key concern**: Prevent bounded control regions from becoming a general-purpose CFG compiler.

---

### Summary

- **Recommended**: **Approach B — New Hole-Parametric Stencil IR**.  
  It best matches the actual system boundary: semantic SSA offline, canonical patchable stencil shape offline, simple runtime copy/patch. It has more migration cost than A, but it gives the cleanest long-term answer to stencil diversity, hole abstraction, codegen simplification, and fact-contract stability.

- **Dark horse**: **Approach C**.  
  If PUC branch/test/loop correctness becomes the top priority, C has the most semantic upside. But it should not be the first move for the stated goal.

- **Avoid**: **Approach C as the primary near-term architecture**.  
  It solves a real future problem, but not the core current bottleneck: canonical reusable stencil shapes. Approach B is the better strong-but-not-overengineered path.

## Documenter Output — 2026-05-29 01:38:46

# Architectural Decision: Hole-Parametric Stencil IR After Semantic SSA for SpongeJIT

## Goal

Enable SpongeJIT to manufacture fewer, more reusable, patchable C stencil shapes by inserting a new hole-parametric Stencil IR after semantic SSA: semantic SSA remains responsible for Lua meaning, facts, guards, and effects, while Stencil IR becomes the canonical materialization shape used for hashing, C emission, hole contracts, and bank/runtime compatibility.

## Incentives

SpongeJIT’s current SSA pipeline already lifts PUC Lua opcode windows into a typed, effectful SSA graph, optimizes it lightly, generates C, and builds a runtime-selectable stencil bank. The main limitation is not low-level code quality; GCC already handles most machine-level cleanup. The concrete pain point is stencil diversity and weak canonicalization: `ssa_normalize.lua` has broken value renaming, `semantic_normal_form` is mostly sequence compression rather than dataflow canonicalization, concrete slots and immediates leak into hashes even when they are runtime-patchable, and `ssa_to_c.lua` performs semantic rewrites such as `BoxI64 + FrameStore` fusion too late, after normalization. A dedicated Stencil IR directly addresses this by separating Lua-semantic SSA from reusable, patchable stencil shape.

## Current State

SpongeJIT currently has an offline foundry pipeline and a simple runtime materialization pipeline.

The offline path is:

```text
grammar_enum / enumerate
  → ssa_fact_axes.axes_for_ops + subsets
  → ssa.compile
      → ssa_lift
      → ssa_opt
      → ssa_normalize/hash
  → ssa_to_c.generate
  → ssa_contract.from_result
  → worker_compile JSON/C chunks
  → gcc/objdump/nm
  → build_bank.lua
  → libsponbank.c/libsponbank.so
```

The runtime path is:

```text
PUC Proto bytecode
  → build_semantic_stream opcode IDs
  → build_actual_slot_stream operand slots
  → spon_select_flow_flags_slots(...)
  → materialize_tile copies .text and patches holes
  → SponExecCtx execution
  → exit_kind/resume_pc back to interpreter
```

The public SSA entry point is `experiments/lua_interpreter_vm/spongejit/src/ssa.lua`:

```lua
function M.compile(ops, facts, config)
    local fs = factset(facts)
    local g = Lift.lift(ops or {}, fs, config)
    Opt.optimize(g, config)
    return summarize(g, ops or {}, fs, config)
end
```

The summary currently includes:

- `normal_form`
- `normal_form_hash`
- `active_ops`
- `active_node_specs`
- `checked_facts`
- `deps`
- `projection`
- `canonical_graph`

The semantic SSA graph is defined in `src/ssa_ir.lua`. It already has important properties that must remain the semantic foundation:

- typed values such as `TValue`, `I64`, `PtrTable`
- explicit effects such as `guard`, `frame_read`, `frame_write`, `heap_read`, `heap_write`, `gc_barrier`, `call`, `residual`, `branch`, `return_`
- memory domains such as `frame`, `table`, `gc`, `call`
- explicit guards and exits
- source opcode indices on nodes
- hard barriers such as `Call`, `KnownCall`, `TailCall`, `Residual`, `GenericExit`, and `Jump`

`src/ssa_lift.lua` lowers PUC opcode windows into SSA using entry facts. Missing facts or unsupported VM semantics become structured `GenericExit` nodes rather than hidden backend assumptions. For example, integer slot specialization checks facts, emits a guard, then unboxes:

```lua
local function i64_from_slot(g, slot, role, pc)
    local ok, subj = has_slot(g, slot, "is_i64", { role or "value", "last" })
    if not ok then return nil end
    local tv = load_slot(g, slot, pc)
    guard(g, tv, mkfact("type", subj, "is_i64"), "GuardTypeI64", pc)
    return g:unbox_i64(tv, pc)
end
```

The lifter is intentionally incomplete. Several PUC semantics residualize today, including `FORLOOP`, `FORPREP`, `TEST`, `TESTSET`, many upvalue/metamethod/vararg/closure paths, `POW`, `GETTABUP`, and `SETTABUP`. Comparison opcodes are simplified as value-producing forms rather than faithful PUC skip-next control.

`src/ssa_opt.lua` is intentionally minimal:

```lua
function M.optimize(g, config)
    pass_frame_forward(g)
    pass_guard_dominance(g)
    pass_barrier_elim(g)
    pass_field_forward(g)
    return g
end
```

The project already relies on GCC for copy propagation, arithmetic folding, dead locals, and similar machine-level cleanup. SSA-level optimization exists for Lua-specific semantics GCC cannot see: guard dominance, frame slot equivalence, fact lifetimes, value tagging, and memory-domain effects.

The current normalizer in `src/ssa_normalize.lua` is too weak for the target use case. `semantic_normal_form` mostly compresses opcode sequences, and the canonical graph value-renaming code is flawed because it uses `#map + 1` on a non-array table:

```lua
local function val(v, map)
    if not v then return "" end
    if not map[v] then map[v] = "v" .. tostring(#map + 1) end
    return map[v]
end
```

This can collapse distinct SSA values to the same canonical name and obscure real def-use structure. Concrete immediates and slots also remain present in canonical hashes even when they correspond to runtime patch holes.

`src/ssa_to_c.lua` currently emits monolithic C stencils and allocates holes during emission. It uses patchable extern symbols such as:

```c
extern const char __H_0[];
```

Hole roles include slots, immediates, constants, guards, exits, and payloads such as shape offsets, field offsets, array base offsets, call targets, and barriers. Codegen also performs semantic simplification, notably fusing `BoxI64` followed by `FrameStore` into direct tagged integer writes. This means the current SSA normal form is not the final lowered stencil shape; some semantic identity is decided after hashing.

Fact contracts are generated by `src/ssa_contract.lua` and are part of executable tile semantics:

```text
facts_out = (facts_in - killed) | produced | checked
```

Contracts derive:

- `checked` from surviving guards
- `produced` from frame stores whose producer chain proves facts such as `BoxI64`
- `killed` from stores, calls, heap writes, and barriers
- `required = selector - checked`

These contracts bridge rich offline SSA facts to compact runtime fact masks.

Runtime fact signatures are defined in `src/fact_signature.lua`. The runtime ABI is a 64-bit mask with slot facts such as `is_i64`, `table`, `shape_known`, `array_hit`, and global/payload bits such as `barrier_clean`, `const_i64`, `key_const`, `shape_payload`, `array_payload`, and `call_target_payload`.

`src/ssa_fact_axes.lua` defines curated fact bundles for opcode windows. These bundles are important because they prevent blind powerset explosion and encode facts that must travel together for a lowering to be executable.

The runtime bank and selector are generated by `src/build_bank.lua`. Runtime selection requires compatible pattern keys, fact masks, slot mappings, tile flags, and patchability. PUC integration currently requests `SPON_TILE_PUC_PATCHABLE`. Only a restricted set of hole roles is PUC-patchable today:

```lua
local PUC_PATCHABLE_ROLES = {
  unknown, slot, imm, const, bool, exit, fail, slot_store
}
```

Payload holes such as shape offsets, field offsets, array bases, call targets, and barriers are not currently patchable by the PUC runtime. As a result, specialized field/array/call stencils may be generated offline but rejected by runtime image selection.

The runtime in `puc/sponjit_runtime.c` does not run SSA or generate code. It observes only a small subset of facts, currently mainly i64 slot facts, then selects, copies, patches, and executes prebuilt stencils.

## Chosen Target

### Approach

The chosen design is **Approach B: New Hole-Parametric Stencil IR**.

Current SSA remains the semantic lifting and optimization IR. A new Stencil IR is introduced after SSA optimization and before normalization, hashing, C generation, and bank metadata generation. Stencil IR is the canonical representation of reusable, patchable, C-emittable stencil shapes.

This approach was chosen because it best matches SpongeJIT’s actual architecture:

- SSA explains Lua semantics.
- Stencil IR defines the materializable stencil ABI.
- Runtime remains simple: select, copy, patch, execute.
- Canonicalization can abstract runtime-patched values without erasing ABI-relevant distinctions.
- Codegen no longer owns semantic rewrites.

### Architecture

The revised offline pipeline is:

```text
grammar_enum / enumerate
  → ssa_fact_axes.axes_for_ops + subsets
  → ssa.compile
      → ssa_lift.lua          -- semantic Lua opcode lowering
      → ssa_opt.lua           -- Lua-semantic SSA cleanup
      → Stencil IR lowering   -- new boundary
      → Stencil IR normalize/hash
  → ssa_to_c.lua              -- emit from Stencil IR
  → ssa_contract.lua          -- preserve fact transfer semantics
  → worker_compile JSON/C chunks
  → gcc/objdump/nm
  → build_bank.lua
  → libsponbank.c/libsponbank.so
```

The new module was proposed as a dedicated file such as:

- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua`
- or `experiments/lua_interpreter_vm/spongejit/src/ssa_stencil_lower.lua`

The exact filename is less important than the boundary: this module owns the lowering from semantic SSA graph to hole-parametric stencil shape.

Stencil IR must contain:

- a small closed vocabulary of C-ready operations
- typed hole parameters
- hole roles
- hole equality and alias constraints
- explicit exits and residual paths
- memory effects relevant to materialization
- fact contract references or annotations
- patchability class
- enough structure for canonical hashing and C emission to consume the same shape

The closed operation vocabulary should cover the already-supported stencil concepts from SSA and codegen, including:

- frame loads and stores
- unbox and box operations
- integer arithmetic
- guards
- exits and `GenericExit`/residual behavior
- table payload operations where already represented
- calls and residuals where already represented
- explicit memory effects needed for frame, table, GC, and call domains

Every runtime-patched value must be represented as a typed hole rather than as an incidental literal in the canonical shape. Hole categories include the roles already present in `ssa_to_c.lua` and `build_bank.lua`:

- slot holes
- slot-store holes
- immediates
- constants
- booleans
- exits/fail targets
- payload holes such as shape, field, array, call target, and barrier payloads

Stencil IR hashing must include:

- operation shape
- typed hole roles
- hole equality and alias constraints
- exit behavior
- patchability class
- fact contract shape

Stencil IR hashing must not include concrete patch values unless those values affect stencil shape or semantics. This directly addresses the current problem where concrete immediates and slots unnecessarily diversify hashes.

`src/ssa_normalize.lua` changes role: it should normalize and hash Stencil IR rather than raw semantic SSA. The canonical key must be dataflow-aware and must preserve ABI-relevant distinctions such as hole roles, slot equality, exits, and fact contracts.

`src/ssa_to_c.lua` changes role: it should emit C from already-lowered Stencil IR rather than performing semantic rewrites itself. Rewrites such as `BoxI64 + FrameStore` fusion move to the SSA-to-Stencil lowering boundary.

`src/ssa_contract.lua`, `src/ssa_fact_axes.lua`, and `src/fact_signature.lua` remain first-class constraints. Fact contracts are part of executable stencil semantics and must remain consistent across lowering, hashing, C generation, and bank metadata.

The runtime architecture remains unchanged:

```text
PUC runtime
  → observe available facts
  → select bank tile by pattern/facts/slots/flags
  → copy tile image
  → patch supported holes
  → execute
```

The runtime must not run SSA, lower Stencil IR, generate code, or optimize dynamically.

### Boundary Responsibilities

| Layer | Responsibility |
|---|---|
| `ssa_lift.lua` / semantic SSA | Interpret PUC opcode windows using facts; emit typed values, guards, effects, exits, and residuals. |
| `ssa_opt.lua` | Perform Lua-semantic SSA cleanup that GCC cannot understand, such as guard dominance and frame/value forwarding. |
| New Stencil IR lowering | Convert semantic SSA into canonical, hole-parametric, C-ready stencil shape. Move codegen-side semantic rewrites here. |
| Stencil IR normalization/hash | Produce canonical keys from operation shape, holes, alias constraints, exits, patchability, and fact contract shape. |
| `ssa_to_c.lua` | Emit C from Stencil IR without deciding semantic identity late. |
| `ssa_contract.lua` | Preserve checked/required/produced/killed fact transfer semantics. |
| `build_bank.lua` | Consume tile metadata, hole roles, patchability, selectors, and contracts. |
| `puc/sponjit_runtime.c` | Select, copy, patch, execute. No SSA or dynamic lowering. |

### Invariants

The decision preserves these invariants:

1. **SSA is the semantic authority.** Lua opcode meaning, guards, exits, memory effects, and fact dependencies originate in semantic SSA.

2. **Stencil IR is the materialization and canonicalization authority.** It defines reusable stencil shape, patch holes, patchability class, and C-emittable operations.

3. **Runtime remains simple.** Runtime does not run SSA, Stencil IR lowering, or code generation.

4. **Fact contracts are semantic, not advisory.** `checked`, `required`, `produced`, and `killed` facts must remain consistent with guards, stores, effects, and exits.

5. **Patch-hole abstraction must preserve constraints.** Concrete patch values are abstracted, but hole role, type, equality, aliasing, patchability, and semantic-discriminator status remain part of identity.

6. **Exit behavior participates in stencil identity.** Guards, fail holes, `GenericExit`, residual paths, exit kind, and resume behavior cannot be ignored during canonicalization.

7. **Memory effects remain explicit.** Frame, table, GC, and call effects determine fact kills and value forwarding.

8. **Unsupported or unpatchable semantics remain explicit.** They are represented through exits/residuals or rejected by patchability constraints, not hidden in runtime complexity.

## Rejected Alternatives

### Approach A: Evolutionary Linear SSA Canonicalizer

Approach A would keep the existing linear effect-SSA architecture and add stronger canonicalization directly into the current SSA/normalizer/codegen stack.

It was not chosen as the target architecture because, while it has the lowest migration cost and fits the current system well, it risks further entangling `ssa_normalize.lua`, `ssa_opt.lua`, and `ssa_to_c.lua`. It improves immediate canonicalization but does not create as clean a separation between semantic SSA and stencil ABI shape.

Approach A remains the lower-disruption path, but the decision favors the cleaner boundary of Approach B.

### Approach C: Bounded Control-Region SSA

Approach C would extend the current linear SSA model with bounded control regions to represent branch-like PUC opcodes more faithfully, including comparisons, tests, loops, exits, and resume PCs.

It was not chosen as the primary architecture because it addresses future semantic coverage more than the current core problem of canonical reusable stencil shapes. It has the highest migration cost and the greatest risk of becoming a general CFG/phi compiler, which conflicts with the strong-but-non-overengineered goal.

## Tradeoffs Acknowledged

Approach B has higher migration cost than Approach A. It touches normalization, C generation, hole allocation, bank metadata, and tests. It introduces a second IR boundary, which must be kept narrow to avoid duplicating semantic SSA.

This cost is accepted because the separation is the cleanest fit for SpongeJIT’s model: semantic SSA for Lua meaning, Stencil IR for reusable materializable shapes, and runtime for copy/patch execution only.

Approach B does not primarily solve branch/test/loop semantic coverage. Those remain known gaps in the current lifter and may still residualize. This is acceptable because the selected objective is canonical stencil reuse and hole abstraction, not full PUC control-region modeling.

## Risks Acknowledged

The main risk is scope creep. If Stencil IR becomes a second full compiler IR, it will duplicate SSA and become overbuilt.

The second risk is making Stencil IR too narrow. If it cannot represent the real stencil ABI, semantic escape hatches will reappear in `ssa_to_c.lua`, recreating the current problem where codegen decides semantic identity late.

Additional known risks:

- hash keys may over-abstract and merge incompatible patch contracts if hole roles, aliases, exits, patchability, or fact contracts are omitted
- hash keys may under-abstract and preserve unnecessary stencil diversity if concrete patch values remain in canonical identity
- fact contracts may become unsound if lowering removes or fuses nodes without preserving checked/produced/killed semantics
- payload-specialized stencils may still be unusable by the PUC runtime unless their holes match current patchability constraints
- unsupported PUC control semantics remain residualized until separately addressed

## Guidance for Keeping the Design Strong but Non-Overengineered

The Stencil IR must be a **stencil-shape ABI**, not a general replacement for SSA.

The design should keep these boundaries strict:

- semantic SSA explains Lua behavior
- Stencil IR describes canonical patchable C stencil shape
- runtime selects, copies, patches, and executes only

Stencil IR should hash only shape-relevant information:

- operation shape
- typed hole roles
- equality and alias constraints
- exit behavior
- patchability class
- fact contract shape

It should not hash concrete runtime patch values unless they affect stencil shape or semantics.

Existing infrastructure to preserve as first-class constraints:

- `src/ssa_ir.lua`
- `src/ssa_lift.lua`
- `src/ssa_opt.lua`
- `src/ssa_contract.lua`
- `src/ssa_fact_axes.lua`
- `src/fact_signature.lua`
- `src/build_bank.lua`
- `puc/sponjit_runtime.c`

Semantic rewrites currently hidden in `ssa_to_c.lua`, especially `BoxI64 + FrameStore` fusion and frame forwarding decisions, belong at the SSA-to-Stencil lowering boundary.

Unsupported or unpatchable cases should remain explicit through exits, residuals, contracts, or patchability filtering. They should not be hidden by adding dynamic SSA behavior to the runtime.
