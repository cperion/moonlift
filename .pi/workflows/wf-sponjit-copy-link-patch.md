# SponJIT Copy-Link-Patch Exploration 
Explore Copy-Link-Patch as a future Tier 2 stencil-fusion backend above the current Tier 1 offline bank tiler. Phase 1 should document current facts before deciding architecture or experiments.
**Workflow ID**: wf-sponjit-copy-link-patch
**Started**: 2026-05-29 09:06:03
---

## Scout Output — 2026-05-29 09:26:53

## Files Retrieved

1. `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md` (lines 1-658) — Defines Copy-Link-Patch Tier 2 idea, required metadata, SSA/tape/link/projection validation questions.
2. `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` (lines 1-165) — Current Stencil IR data model: ops, values, holes, slotmaps, exits, facts.
3. `experiments/lua_interpreter_vm/spongejit/src/stencil_normalize.lua` (lines 1-164) — Canonical form/hash, checked facts/deps/projection summaries.
4. `experiments/lua_interpreter_vm/spongejit/src/stencil_to_c.lua` (lines 1-262) — C emission, `SponExecCtx`, exit writes, hole catalog output.
5. `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` (lines 1-423) — Semantic SSA graph, typed values, effects, memory tokens, exits/projections.
6. `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` (lines 1-322) — PUC op/fact → SSA lowering and structured generic exits.
7. `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` (lines 1-242) — Existing SSA cleanup passes: frame forwarding, guard dominance, barrier elim, field forwarding.
8. `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` (lines 1-280) — SSA → Stencil IR lowering, slotmaps, hole creation, exit holes.
9. `experiments/lua_interpreter_vm/spongejit/src/ssa_contract.lua` (lines 1-98) — Tile fact-transfer contracts: selector/required/checked/produced/killed/deps/exits.
10. `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` (lines 1-141) — Public compile facade; returns `active_node_specs`, `stencil`, holes, slotmaps, projection summary.
11. `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua` (lines 1-57) — Reopens serialized semantic node specs into SSA.
12. `experiments/lua_interpreter_vm/spongejit/src/facts.lua` (lines 1-303) — Rich fact lattice, dependencies, implications, contradictions.
13. `experiments/lua_interpreter_vm/spongejit/src/fact_signature.lua` (lines 1-221) — Fixed 64-bit runtime fact ABI and transfer helpers.
14. `experiments/lua_interpreter_vm/spongejit/src/fact_schema.lua` (lines 1-223) — Higher-level fact/effect/projection vocabulary.
15. `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` (lines 1-354) — Curated fact bundle generation for grammar/foundry.
16. `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` (lines 1-704) — Bank metadata generator: tile descriptors, relocs, role kinds, selectors.
17. `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` (lines 1-168) — Public bank ABI: `SponTileDesc`, holes, slotmaps, selectors.
18. `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 1-113) — Worker JSON artifacts: forms, contracts, holes, generated C chunks.
19. `experiments/lua_interpreter_vm/spongejit/src/enumerate.lua` (lines 1-594) — Corpus/window enumeration and `stencil_forms.json` writer with `active_node_specs`.
20. `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` (lines 1-482) — Complete PUC opcode grammar enumeration up to arity 4 plus exact L0.
21. `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` (lines 1-241) — Build pipeline for grammar chunks, worker artifacts, object, `stencil_library.json`.
22. `experiments/lua_interpreter_vm/spongejit/build_bank.sh` (lines 1-110) — Builds generated `libsponbank.c/.so`.
23. `experiments/lua_interpreter_vm/spongejit/build/cp_lib/libsponbank.c` (lines 1-160, 4,326,902-4,326,934, 11,567,913-11,567,953, 13,160,642-13,160,828) — Existing generated descriptor artifact.
24. `experiments/lua_interpreter_vm/spongejit/build/cp_lib/stencil_library.json` (lines 1-60) — Generated stencil catalog sample: func/size/hole roles.
25. `experiments/lua_interpreter_vm/spongejit/build/cp_lib/tmp/grammar_result_1.json` (lines 1-180) — Generated worker result sample: forms/contracts/facts/ops.
26. `experiments/lua_interpreter_vm/spongejit/build/cp_lib/build_bank.patchable.log` (lines 1-37) — Bank generation counts/exported symbols from a prior build.
27. `experiments/lua_interpreter_vm/spongejit/runtime/materialize.lua` (lines 1-260) — Older LuaJIT materializer: copy/call trampoline/literal-pool patching.
28. `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.h` (lines 1-38) — PUC runtime `SponImage`/`SponPatchedTile` structures.
29. `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.c` (lines 1-403) — PUC semantic stream, selector call, tile materialization, execution loop.
30. `experiments/lua_interpreter_vm/spongejit/puc/lsponjit.c` (lines 1-196) — PUC hot counters/image cache/runtime entry hook.
31. `experiments/lua_interpreter_vm/spongejit/puc/build_puc_sponjit.lua` (lines 1-115) — Patches vendored PUC Lua to call SponJIT hook.
32. `experiments/lua_interpreter_vm/spongejit/puc/bench_sponbank_puc.c` (lines 1-274) — Selector/copy-patch benchmark over extracted PUC opcodes.
33. `experiments/lua_interpreter_vm/spongejit/puc/bench_execute_tile.c` (lines 1-245) — Executes one selected semantic tile.
34. `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 1-120) — Current SSA/fact/contract invariants.
35. `experiments/lua_interpreter_vm/tests/test_spongejit_materialize.lua` (lines 1-33) — Smoke test for older materializer.
36. `experiments/lua_interpreter_vm/tests/test_sponjit_shadow.lua` (lines 1-169) — Shadow/foundry simulator tests.
37. `experiments/lua_interpreter_vm/spongejit/src/loader.lua` (lines 1-222) — Converts profiles/static bytecode into workloads.
38. `experiments/lua_interpreter_vm/spongejit/src/puc_bytecode.lua` (lines 1-334) — Static/dynamic PUC bytecode profile extraction.

## Key Code

### Stencil IR structure

```lua
-- stencil_ir.lua
function M.new(source_ops, config)
  return setmetatable({
    ops = {},
    values = {},
    value_order = {},
    holes = {},
    hole_by_key = {},
    slotmaps = {},
    exits = {},
    facts = {},
    source_ops = copy_array(source_ops or {}),
    config = config or {},
    next_value = 1,
    next_hole = 0,
  }, Stencil)
end
```

Stencil ops carry inputs/outputs/effect/source/hole/guard/exit/deps:

```lua
function Stencil:add(op, t)
  local n = {
    id = #self.ops + 1,
    op = op,
    inputs = copy_array(t.inputs),
    outputs = copy_array(t.outputs),
    args = t.args or {},
    effect = t.effect or "none",
    source = t.source,
    hole = t.hole,
    guard = t.guard,
    exit = t.exit,
    deps = copy_array(t.deps),
  }
  self.ops[#self.ops + 1] = n
  if n.exit then self.exits[#self.exits + 1] = { op = op, source = n.source or 0, exit = n.exit } end
  return n
end
```

### Current hole roles

Stencil IR declares patchable roles:

```lua
local PUC_PATCHABLE_ROLE = {
  unknown = true, slot = true, imm = true, const = true, bool = true,
  exit = true, fail = true, slot_store = true,
}
```

Bank role kinds:

```lua
local ROLE_KIND = {
  unknown = 0,
  slot = 1,
  imm = 2,
  const = 3,
  bool = 4,
  exit = 5,
  fail = 6,
  shape_offset = 7,
  shape_id = 8,
  metatable_offset = 9,
  field_offset = 10,
  array_base_offset = 11,
  call_target = 12,
  barrier = 13,
  slot_store = 14,
}
```

Public C ABI mirrors these as `SPON_HOLE_*`.

### SSA graph metadata

SSA values have type and optional residency:

```lua
function Graph:new_value(ty, name, facts, residency)
    local v = { id = id, ty = ty, facts = copy_array(facts), residency = residency }
    self.values[id] = v
    return id
end
```

Effects are explicit:

```lua
local EFFECTS = {
    none = true, guard = true, frame_read = true, frame_write = true,
    heap_read = true, heap_write = true, gc_barrier = true, call = true,
    residual = true, branch = true, return_ = true,
}
```

Exit projection object is currently small:

```lua
function Graph:exit_projection(reason, pc, live_slots, virtual_values)
    return {
        reason = reason or "guard_exit",
        pc = pc or 0,
        live_slots = copy_array(live_slots or { "cur" }),
        virtual_values = copy_array(virtual_values or {}),
        ok = true,
    }
end
```

### Summaries available from `SSA.compile`

`ssa.lua` returns in-memory summaries including node specs:

```lua
return {
    ok = ok,
    graph = g,
    stencil = st,
    stencil_form = form,
    stencil_hash = hash,
    stencil_key = key,
    stencil_ops = StencilNorm.active_codegen_ops(st),
    stencil_holes = st.holes,
    slotmaps = st.slotmaps,
    active_node_specs = active_node_specs(g),
    semantic_ops = semantic_ops(g),
    checked_facts = StencilNorm.checked_fact_names(st),
    checked_fact_objects = StencilNorm.checked_facts(st),
    deps = StencilNorm.deps(st),
    projection = StencilNorm.projection(st),
    stats = g.stats,
    source_ops = copy_array(source_ops or {}),
}
```

`active_node_specs` currently includes op/codegen/effect/guard/deps/inputs/outputs/output_types, but not memory tokens or value residency.

### Projection summary currently emitted by normalization

```lua
function M.projection(st)
  local exits, virtuals, reasons = 0, 0, {}
  for _, n in ipairs(st.ops or {}) do
    if n.exit then
      exits = exits + 1
      reasons[#reasons + 1] = n.exit.reason or n.op or "exit"
      if n.exit.virtual_values then virtuals = virtuals + #n.exit.virtual_values end
    end
  end
  return { ok = true, exit_obligations = exits, virtual_values = virtuals, reasons = reasons }
end
```

### Fact signature ABI

Runtime signatures are 64-bit masks:

```lua
M.SLOT_FACT_BASE = {
  i64 = 0, is_i64 = 0,
  table = 8, is_table = 8,
  shape_known = 16,
  metatable_absent = 24,
  array_hit = 32,
  bounds_ok = 40,
  known_call_target = 48,
  key_i64 = 0,
}

M.GLOBAL_FACT_BIT = {
  barrier_clean = 56,
  const_i64 = 57,
  key_const = 58,
  nonzero_i64 = 59,
  shape_payload = 60,
  array_payload = 61,
  call_target_payload = 62,
}
```

Payload facts collapse into global payload bits; payload values are not encoded in `SponFactSig`.

### Contract metadata

```lua
return {
  selector_sig = Sig.with_literal(selector),
  required_sig = Sig.with_literal(required),
  checked_sig = Sig.with_literal(checked),
  produced_sig = Sig.with_literal(produced),
  killed_sig = Sig.with_literal(killed),
  deps = copy_array(deps),
  exits = exits,
}
```

Generated `SponTileDesc` keeps only signatures, not `deps` or `exits`.

### Public bank descriptor

```c
typedef struct {
  SponTileId tile_id;
  uint32_t offset;
  uint32_t size;
  uint32_t hole_start;
  uint32_t slotmap_start;
  uint16_t len;
  uint16_t n_holes;
  uint16_t n_slotmaps;
  uint16_t flags;
  SponFactSig fact_sig;
  uint64_t pattern_key;
  SponFactSig required_sig;
  SponFactSig checked_sig;
  SponFactSig produced_sig;
  SponFactSig killed_sig;
} SponTileDesc;
```

Public holes and slotmaps:

```c
typedef struct {
  uint32_t code_offset;
  uint16_t hole_id;
  uint16_t reloc_kind;
  uint16_t role_kind;
  uint16_t op_idx;
  int32_t role_arg;
} SponHoleReloc;

typedef struct {
  uint16_t op_idx;
  uint8_t logical_slot;
  uint8_t field_kind;
} SponSlotMapEntry;
```

### Bank generator selector flow

Source generator emits selection over pattern + signatures + flags + slots:

```lua
if (t && ((t->flags & required_tile_flags) == required_tile_flags) && tile_matches_actual_slots(...)) {
  SponFactSig tfact = remap_tile_sig(t, t->fact_sig, actual_slots, n_actual_slots, pc, 1);
  SponFactSig treq = remap_tile_sig(t, t->required_sig, actual_slots, n_actual_slots, pc, 1);
  if (((tfact & ~available_sig) == 0) && ((treq & ~facts) == 0)) { chosen = tid; ... }
}
...
facts = apply_transfer(facts, chosen_t, actual_slots, n_actual_slots, pc);
```

### PUC image/runtime structures

```c
typedef struct SponPatchedTile {
  SponTileId tile_id;
  uint32_t pc_start;
  uint32_t pc_end;
  void *code;
  size_t code_size;
} SponPatchedTile;

typedef struct SponImage {
  uint32_t pc_start;
  uint32_t pc_end;
  uint32_t n_tiles;
  SponFactSig entry_sig;
  SponFactSig observed_sig;
  SponPatchedTile *tiles;
} SponImage;
```

### PUC patching support

`patch_value` patches only simple PUC roles; shape/table/call-target/barrier holes refuse materialization:

```c
case SPON_HOLE_SLOT:
case SPON_HOLE_SLOT_STORE:
  return actual_slot_for_hole(...);
case SPON_HOLE_IMM:
case SPON_HOLE_CONST:
case SPON_HOLE_BOOL:
case SPON_HOLE_EXIT:
case SPON_HOLE_FAIL:
case SPON_HOLE_UNKNOWN:
  ...
default:
  /* Shape/table/call-target/barrier holes require dependency epochs and
     payload leases. Refuse the tile unless the runtime can patch them. */
  return 0;
```

### PUC materialization/execution

Each selected tile is copied into its own mmap page and called from C:

```c
memcpy(mem, src, t->size);
for (uint32_t i = 0; i < nh; i++) {
  uint32_t value = 0;
  if (!patch_value(...) || !patch_reloc(mem, &hs[i], value)) {
    munmap(mem, alloc);
    return NULL;
  }
}
mprotect(mem, alloc, PROT_READ | PROT_EXEC);
```

Execution loops tile by tile:

```c
for (uint32_t i = first; i < last_exclusive; i++) {
  SponTileFn fn = (SponTileFn)img->tiles[i].code;
  ctx->exit_kind = SPON_EXIT_NONE;
  fn(ctx);
  if (ctx->exit_kind != SPON_EXIT_NONE) {
    *resume_pc = ctx->exit_pc;
    ...
    return 2;
  }
}
return 1;
```

## Relationships

- `ssa_lift.lua` consumes PUC opcode windows + facts and builds `ssa_ir.lua` graphs.
- `ssa_opt.lua` mutates SSA nodes by marking removals and forwarding inputs.
- `ssa_to_stencil.lua` lowers active SSA nodes into `stencil_ir.lua`, adding:
  - values,
  - holes,
  - slotmaps,
  - guard exits,
  - residual/boundary/unlowered exits.
- `stencil_normalize.lua` derives form/hash/checked facts/deps/projection counts.
- `stencil_to_c.lua` emits one C function per Stencil IR form using `extern __H_N` holes to force relocations.
- `worker_compile.lua` writes:
  - `grammar_c_code_N.c`,
  - `grammar_holes_N.json`,
  - `grammar_result_N.json`.
- `build_stencils.sh` compiles worker C chunks and writes `stencil_library.json`.
- `build_bank.lua` joins:
  - symbols from `stencils.o`,
  - raw `.text`,
  - grammar forms,
  - hole catalogs,
  - objdump relocations,
  into generated `libsponbank.c`.
- `sponbank.h` is the public ABI used by:
  - PUC runtime,
  - benchmarks,
  - generated `libsponbank.c`.
- `sponjit_runtime.c` builds a semantic opcode stream from a real `Proto`, selects tiles via `spon_select_flow_flags_slots_stats`, materializes each tile independently, and stores them in `SponImage`.
- `lsponjit.c` maintains per-Proto hot counters, observed i64 signature, image pointer per PC, and calls `spon_image_execute`.

## Available Metadata

Current in-memory SSA/StenciI IR has:

- Semantic SSA nodes with:
  - op,
  - inputs/outputs,
  - output types,
  - effects,
  - guard fact,
  - deps,
  - exit reason,
  - source pc,
  - memory tokens internally.
- Stencil IR nodes with:
  - op,
  - inputs/outputs,
  - args,
  - effect,
  - source,
  - hole,
  - guard,
  - exit,
  - deps.
- Hole catalog with:
  - id,
  - role kind,
  - role arg,
  - op index,
  - type,
  - patchable flag,
  - semantic flag.
- Slotmaps:
  - stencil-local logical slot,
  - source op index,
  - operand field kind.
- Contracts:
  - selector,
  - required,
  - checked,
  - produced,
  - killed,
  - deps,
  - exits.
- Generated bank descriptor ABI exposes:
  - tile id,
  - byte offset/size,
  - pattern key,
  - arity,
  - hole slice,
  - slotmap slice,
  - flags,
  - fact-transfer signatures.
- Existing generated `libsponbank.c` artifact reports:
  - `spon_hole_count = 4326888`,
  - `spon_slotmap_count = 7241005`,
  - `spon_tile_count = 1067275`,
  - `spon_pattern_count = 472060`.

## Missing / Not Exposed Metadata

Facts from inspected files:

- `SponTileDesc` does not expose:
  - func name,
  - Stencil IR op list,
  - SSA node specs,
  - input/output endpoint contracts,
  - accepted/produced locations,
  - clobbers,
  - dependency strings,
  - exit descriptors,
  - projection recipes,
  - source op operands beyond pattern key/slotmaps.
- `SponFactSig` does not carry payload values for shape ids, field offsets, array offsets, call target addresses; it carries coarse payload bits.
- `Contract.from_result` computes `deps` and `exits`, but `build_bank.lua` only loads selector/required/checked/produced/killed into `SponTileDesc`.
- `active_node_specs` are available from `SSA.compile` and `src/enumerate.lua` outputs, but current `worker_compile.lua` form JSON does not write `active_node_specs`.
- `Graph:new_value` has optional `residency`, and some i64 ops use `"gpr0"`, but bank metadata does not expose residency.
- SSA memory tokens exist in graph nodes, but `active_node_specs` does not serialize `mem_in`/`mem_out`.
- `StencilNorm.projection` counts exits/virtual values/reasons, but does not serialize per-exit projection entries.
- PUC runtime `SponImage` stores installed tile ids and pc ranges, but not expanded summaries, exit history, dependency epochs, or projection state.
- PUC runtime materializes each tile separately and calls them through C; there is no current generated hot image with direct fallthrough between tiles.

## Generated Summary Extraction Points

Existing metadata-only inputs discovered:

- `SSA.compile(...)` return object in `src/ssa.lua`:
  - full in-memory `graph`,
  - `stencil`,
  - `active_node_specs`,
  - `stencil_ops`,
  - `stencil_holes`,
  - `slotmaps`,
  - `checked_fact_objects`,
  - `deps`,
  - `projection`.
- `src/enumerate.lua` writes `stencil_forms.json`/`.md` and stores:
  - ops,
  - facts,
  - fact axes,
  - stencil form/ops/slotmaps,
  - active node specs,
  - deps,
  - projection,
  - stats,
  - examples.
- `src/worker_compile.lua` writes per-chunk:
  - `grammar_result_N.json`,
  - `grammar_holes_N.json`,
  - `grammar_c_code_N.c`.
- `build/cp_lib/stencil_library.json` contains generated func, size, hole count, and hole roles.
- `build/cp_lib/libsponbank.c` contains generated C arrays:
  - `spon_holes`,
  - `spon_slotmaps`,
  - `spon_tiles`,
  - `spon_candidates`,
  - `spon_patterns`.
- `sponbank.h` exposes runtime APIs for tile descriptors, holes, slotmaps, selectors.
- `puc/sponjit_runtime.c` has the installed tile sequence while building `SponImage`.

## Tests / Benchmarks Relevant to Experiments

- `tests/test_spongejit_real_ssa.lua`
  - checks fact closure, contradictions, guard deps/exits, `compile_nodes`, barrier elimination, operand facts, contracts.
- `tests/test_spongejit_materialize.lua`
  - smoke test for older LuaJIT materializer.
- `puc/bench_sponbank_puc.c`
  - extracts real PUC opcodes, measures selector and copy/patch materialization.
  - reports cover arity, image bytes, image holes, selection ns/op, copy-patch ns/image/tile/hole.
- `puc/bench_execute_tile.c`
  - selects one aggregate tile, materializes it, executes repeatedly, compares against PUC loop.
- `puc/bench_sponbank_puc.lua` and `puc/bench_execute_tile.lua`
  - wrappers for compiling/running those C benchmarks.
- `tests/test_sponjit_shadow.lua`
  - exercises older shadow/foundry model and cross-atom SSA concepts.

## Observations

- Current Tier 1 selector/materializer has concrete byte/hole/slotmap/fact-transfer metadata.
- Current SSA/StenciI IR has enough first-order semantic structure in memory to name ops, effects, guard facts, deps, holes, exits, and source slots.
- The public bank ABI is narrower than the in-memory foundry metadata.
- The current generated bank is a tile library and selector, not a typed macro-instruction catalog.
- PUC runtime has installed tile ids/pc spans in `SponImage`, but no serialized summaries for those tiles.
- PUC runtime has only i64 slot observation as live runtime facts.
- Shape/field/array/call-target/barrier holes exist in Stencil IR and bank role kinds, but current PUC materializer refuses them.
- Exit state in generated C is `exit_kind`, `exit_pc`, `exit_op_idx`, `exit_hole`; projection recipes are not represented in the runtime ABI.
- Existing generated artifact and source generator show overlapping but not identical selector code in the inspected files; the source generator contains slot remapping by pc base, while the existing generated `libsponbank.c` excerpt uses a simpler current artifact selector shape.

## Knowledge-builder Output — 2026-05-29 09:29:55

### What Matters Most for This Problem

- **Metadata sufficiency at the right layer**: current in-memory SSA/Stencil IR is much richer than the public bank ABI; the answer differs depending on which artifact is treated as the “backend vocabulary.”
- **Endpoint/link semantics vs current function-shaped tiles**: Copy-Link-Patch needs linkable fragments, but today’s generated bytes are C functions with prologue/epilogue and C-call boundaries.
- **Projection correctness**: current runtime assumes frame state is already synchronized at exits; Copy-Link-Patch’s value comes partly from violating that assumption safely.
- **Fact/payload/dependency fidelity**: 64-bit fact signatures are useful for selection, but too compressed for payload-bearing table/shape/call-target specialization.
- **Experiment interpretability**: some surfaces validate Stencil IR as a semantic vocabulary; others mostly expose missing bank/runtime metadata or C-codegen artifact constraints.

---

### Non-Obvious Observations

- The current system has **two incompatible “Stencil IR” realities**:  
  in-memory Stencil IR/SSA can name ops, values, effects, guards, deps, exits, holes, and slotmaps; the generated bank ABI exposes mostly bytes, holes, slotmaps, pattern keys, and fact masks. A repo-grounded experiment must not treat conclusions about one layer as conclusions about the other.

- The public bank is not currently a typed macro-instruction catalog. It is closer to an **opaque tile library with patch sites**. The metadata needed for Copy-Link-Patch mostly exists before `build_bank.lua`, then is discarded or compressed.

- Current generated stencil bytes are **whole C functions**, not linkable basic-block fragments. They reset `ctx->exit_kind`, load `ctx->stack`, use compiler-chosen locals/registers, and return to C. That means direct fallthrough/linking cannot be inferred from the byte artifacts, even if the semantic Stencil IR has adjacent ops.

- Existing exit holes do not mean “branch target” holes. In `stencil_to_c.lua`, guard/residual exits write `ctx->exit_pc = __H_n` and return. So current `fail`/`exit` holes encode resume metadata, not continuation edges. Copy-Link-Patch’s edge taxonomy would collide with current role names unless distinguished semantically.

- Physical endpoint contracts are almost entirely absent. SSA values have types and optional residency hints, but emitted C lets the compiler choose locations. Current metadata can say “this op produces an `I64` value,” but not “this op produces `gpr0` and clobbers flags.”

- The existing `residency = "gpr0"` field is not a reliable backend contract because it is not serialized in `active_node_specs`, not exposed in bank metadata, and not enforced by C emission.

- Slotmaps are more mature than endpoint contracts, but they solve a narrower problem: mapping **canonical tile-local slot classes** to source bytecode operands. They do not describe live slots, projection obligations, or value residency.

- Slot identity is subtle: Stencil validation restricts canonical slot holes to `0..7`, while runtime actual slots may be `0..255`. This works for local tile templates but becomes a constraint for any fused representation that tries to canonicalize a whole long span as one stencil.

- `SponFactSig` is useful for i64/slot-style experiments but weak for table/shape/call-target experiments. Payload facts collapse into global bits like `shape_payload` or `call_target_payload`; the actual shape id, field offset, array base, or function pointer is not encoded.

- The richer hole role taxonomy is latent capability, not runtime capability. Shape/field/array/call-target/barrier roles exist in IR and bank enums, but the PUC materializer explicitly refuses them. Experiments involving those roles may mostly measure payload/lease infrastructure absence, not Stencil IR vocabulary quality.

- `Contract.from_result` computes `deps` and `exits`, but `SponTileDesc` drops them. That is a major split: selection/runtime fact transfer can proceed without the dependency/projection information that would be required for safe hotter-tier speculation.

- Existing projection metadata is count-level, not recipe-level. `StencilNorm.projection` reports exit counts, virtual value counts, and reasons; it does not record per-exit slot reconstruction. This is enough to notice exits exist, not enough to prove Copy-Link-Patch correctness.

- The current optimizer’s behavior implies an important invariant: it mostly avoids transformations that would require nontrivial exit projection. `pass_dead_frame_store` exists but is not run; frame-store deletion stops at guards/branches/returns. Today’s correctness model is effectively “frame is synchronized at exits.”

- Because the current runtime fallback resumes through `exit_pc`/`exit_op_idx` with no projection table, deleting stores across guards would be unsound in the current model. Any experiment that simulates store deletion must treat projection as the hard boundary, not as optional metadata.

- Existing tile summaries are already post-optimization. This means they may hide some seams: frame forwarding, guard dominance, barrier elimination, and field forwarding can already happen within a tile before Stencil IR emission. Seam-value measurements over current stencils may undercount opportunities that existed before tile-local optimization.

- Conversely, Tier 1 already contains aggregate tiles up to bounded arity. A seam-value experiment over installed Tier 1 images needs to separate “seams still present after offline arity growth” from “seams that would have existed between raw opcodes.” Those are different signals.

- Bank deduplication means **one code function is not necessarily one semantic template**. `worker_compile.lua` dedupes code separately from contract-bearing forms. Identical bytes can correspond to different fact contracts. Copy-Link-Patch’s template identity would therefore need descriptor-level semantics, not merely symbol/function identity.

- `stencil_hash` alone is not enough identity for patchability. The worker’s `code_key` includes both normalized stencil hash and opcode signature, implying source opcode context still affects holes/constants/slotmaps. This matters for treating stencils as reusable backend vocabulary.

- Memory/effect information is present in SSA as memory tokens but mostly lost by Stencil IR/bank summaries. Stencil ops retain coarse effects like `heap_read`, `heap_write`, `frame_write`, but not the explicit `mem_in`/`mem_out` domains needed for precise reordering or CSE.

- That loss makes some proposed Tier 2 cleanup classes much less grounded in current artifacts. Slot forwarding and guard dominance are closer to existing metadata; heap CSE, alias-sensitive load forwarding, and call/barrier reasoning need the SSA memory/dependency layer, not just bank metadata.

- Branches and returns are currently modeled as boundary exits, not internal continuations. `Jump`, `Return1`, `Call`, etc. lower to `ExitBoundary`. Therefore current Stencil IR validates “boundary recognition” more than “continuation linking.”

- Runtime `SponImage` stores installed tile ids and pc spans, but not expanded summaries, deps, exit history, projection state, or dependency epochs. It is enough to replay selected tiles, not enough to reconstruct a safe Tier 2 graph without looking elsewhere.

- Existing materialization allocates one executable page per tile and calls each tile from C. Benchmarks over this path reveal copy/patch and call-boundary costs, but they do not directly reveal whether stencil fragments are internally linkable.

- Direct fallthrough savings could be overestimated if measured against today’s per-tile C function calls/pages. That seam is partly an implementation artifact of Tier 1, distinct from the semantic store/load or guard seams Copy-Link-Patch is meant to remove.

- Exit pc indexing has an off-by-one hazard surface: SSA sources are 1-based, holes/runtime `op_idx` are often 0-based, and runtime patching uses pc bases. Any projection/link experiment has to preserve these conventions exactly or risk validating the wrong resume point.

- Current slotmaps describe bytecode operand occurrences, not interpreter-visible liveness. Projection needs “which slots must be reconstructed at this exit,” but slotmaps only say “which operands appeared in this tile.” That is an overapproximation and not a projection recipe.

- The current runtime only observes i64 slot facts. That makes i64 arithmetic spans the most revealing surface for initial backend-vocabulary validation because they exercise slots, guards, box/unbox, store/load seams, and simple exits without immediately hitting missing payload leases.

- Table/shape/field/call-target spans are less revealing for pure linkability today because they fail earlier on missing payload values, dependency epochs, unpatchable holes, and collapsed fact signatures.

- Residual/unlowered-heavy opcode sequences are also less revealing for Copy-Link-Patch. They validate fallback coverage and boundary handling, but not the viability of Stencil IR as a composable backend vocabulary.

- The strongest currently grounded invariant is: **accepted Tier 1 tiles are safe because they materialize canonical frame state and return through coarse exits.** Copy-Link-Patch’s central tension is that its performance value comes from breaking that invariant locally while needing stronger projection metadata to restore it on every exit.

---

### Knowledge Gaps

- Whether generated `grammar_result_N.json` artifacts can practically be enlarged to carry enough summaries without making the bank corpus unwieldy.
- How often real hot PUC spans contain removable seams after current Tier 1 arity selection, not merely before it.
- Whether existing `active_node_specs` are semantically complete enough to reopen useful SSA fragments, given missing memory tokens, residency, and projection data.
- How many current bank tiles have logical holes that do not correspond cleanly to relocations, since `build_bank.lua` logs mismatches but does not fail on them.

## Approach-proposer Output — 2026-05-29 09:35:00

### Approach A: Semantic Region Bank + Late Image Compiler

- **Core idea**: Replace “stencil = callable C function” with “stencil = typed region template,” and generate executable fused images only after runtime region selection/linking.

- **Key changes**:
  - Rework `stencil_ir.lua` into a richer `region_ir.lua` with:
    - explicit entry contract: slots, facts, abstract values, memory tokens
    - typed continuation exits: `ok`, `guard_exit`, `residual_exit`, `boundary_exit`
    - per-exit projection recipes
    - fact transfer and dependency obligations
  - Extend `ssa_ir.lua` / `ssa_to_stencil.lua` to preserve memory tokens, residency hints, live values, and projection data.
  - Replace `stencil_to_c.lua` as the primary ABI producer; keep it only as a Tier 1 compatibility backend.
  - Change `worker_compile.lua`, `enumerate.lua`, and `build_bank.lua` to emit a metadata-rich region catalog instead of opaque C-function bytes.
  - Extend `sponbank.h` with `SponRegionDesc`, `SponRegionEntry`, `SponRegionExit`, `SponProjectionRecipe`, dependency arrays, and payload bindings.
  - Update `puc/sponjit_runtime.c` so Tier 2 builds a linked `SponRegionImage` from selected region descriptors, validates facts/deps, then hands the whole graph to a new image compiler.

- **Tradeoff**: Optimizes for semantic correctness, projection fidelity, and future backend freedom; sacrifices immediate reuse of existing machine-code stencils and requires a new image compiler.

- **Risk**: The system may become metadata-complete before it is execution-complete; too much work could land in the custom image compiler before Copy-Link-Patch performance is measurable.

- **Rough sketch**:
  - Define a canonical region descriptor format above current Stencil IR.
  - Serialize `active_node_specs`, memory tokens, deps, exits, fact transfer, and projection recipes into the bank.
  - Build a Tier 2 planner that links region exits to successor entries symbolically.
  - Add a simple first image compiler for i64 arithmetic spans only.
  - Validate projection correctness before enabling store/load seam removal.

---

### Approach B: Native Fragment ABI with Continuation Relocations

- **Core idea**: Replace C-function stencils with raw native code fragments whose entry and exit labels are explicit relocation targets, allowing runtime copy/link/patch into one fallthrough image.

- **Key changes**:
  - Rework Stencil IR to include physical endpoint contracts:
    - fixed input registers or stack locations
    - fixed output locations
    - clobber sets
    - scratch requirements
    - continuation edge kinds
  - Replace `stencil_to_c.lua` with a low-level emitter, e.g. `stencil_to_asm.lua`, that emits naked fragments instead of C functions.
  - Distinguish hole roles:
    - data holes: slot, immediate, const, payload
    - control holes: fallthrough edge, guard edge, residual edge, projection stub edge
  - Extend `build_bank.lua` to preserve fragment symbols, label offsets, endpoint tables, branch relocations, clobbers, and projection stubs.
  - Extend `sponbank.h` with native-fragment descriptors:
    - code offset/size
    - entry offset
    - continuation exit offsets
    - physical ABI ID
    - relocation slices
    - projection recipe slices
  - Rewrite `puc/sponjit_runtime.c` materialization so one `SponImage` allocates a single executable region, copies fragments into it, patches direct branches, and enters once.

- **Tradeoff**: Optimizes for true Copy-Link-Patch mechanics and direct measurement of link/fallthrough wins; sacrifices portability and makes the ABI tightly coupled to machine-code layout.

- **Risk**: Physical endpoint contracts are hard to keep correct; compiler-generated C can no longer hide register allocation, clobbers, or calling convention details.

- **Rough sketch**:
  - Start with one architecture, likely x86-64 SysV.
  - Define a minimal physical ABI for i64 stack slots and guards.
  - Emit assembly fragments with explicit labels for `entry`, `ok`, and each exit.
  - Patch `ok` edges to successor entries and guard exits to projection/fallback stubs.
  - Benchmark against current per-tile mmap/function-call execution.

---

### Approach C: Moonlift-Style Region Source ABI

- **Core idea**: Make SpongeJIT stencils compile into Moonlift-like typed regions with named continuations, then compose those regions through typed control protocols instead of linking opaque bytes.

- **Key changes**:
  - Introduce a SpongeJIT region schema that maps SSA values, facts, frame slots, memory effects, and exits into Moonlift-style region signatures.
  - Replace or augment `stencil_to_c.lua` with a `stencil_to_region_source.lua` / `stencil_to_backcmd.lua` backend.
  - Each stencil becomes something like:
    - entry params: frame pointer, slot bindings, abstract facts, live values
    - continuations: `ok(...)`, `guard_exit(...)`, `residual_exit(...)`
    - explicit projection obligations on non-`ok` continuations
  - Bank metadata stores typed region templates, continuation protocols, fact transfer, deps, hole bindings, and projection recipes.
  - Runtime selection produces a composed region graph; composition happens by `emit`-style splicing rather than native branch relocation.
  - PUC runtime either invokes a Moonlift/Cranelift compilation path for hot images or uses an ahead-of-time cache of composed common regions.

- **Tradeoff**: Optimizes for typed control, explicit continuation contracts, and reuse of Moonlift’s region philosophy; sacrifices independence from Moonlift and makes Tier 2 closer to a JIT compiler than a pure copy-patch linker.

- **Risk**: Dynamic Lua VM facts, payload leases, and fallback projection may not map cleanly into monomorphic Moonlift regions without adding significant host/runtime ABI machinery.

- **Rough sketch**:
  - Define SpongeJIT-to-Moonlift type mappings for frame slots, TValue views, facts, and exits.
  - Generate one typed region per stencil template.
  - Compose selected regions into a larger Moonlift region with explicit continuations.
  - Compile/cache fused regions for i64-only traces first.
  - Use typed continuation signatures to force projection completeness at compile time.

---

### Comparison

- **Approach A** treats the region ABI as a semantic catalog first, with executable code generated later.
- **Approach B** treats the region ABI as a native binary contract, optimized for real byte-level Copy-Link-Patch.
- **Approach C** treats the region ABI as typed control source, aligning SpongeJIT with Moonlift-style explicit regions and continuations.

## Critique Output — 2026-05-29 09:37:17

## Approach B: Native Fragment ABI with Continuation Relocations

| Dimension | Score | Assessment |
|---|---:|---|
| **Coupling** | **4/5 high** | Strongly couples SpongeJIT IR, codegen, bank metadata, runtime materialization, relocation format, ISA, calling convention, and executable-memory policy. It removes dependence on C compiler-shaped functions, but replaces it with a tighter native ABI contract. |
| **Cohesion** | **4/5 good, with danger** | As a Tier 2 backend, the concept is cohesive: native fragments, explicit labels, continuation exits, clobbers, and relocations all serve Copy-Link-Patch directly. The danger is mixing semantic region facts/projection data with machine-layout metadata too early. |
| **Migration cost** | **5/5 very high** | This is a deep replacement of `stencil_to_c.lua`, `build_bank.lua`, `sponbank.h`, generated artifacts, relocation handling, and `puc/sponjit_runtime.c`. Existing C-function tiles cannot simply become linkable fragments. |
| **SpongeJIT philosophy fit** | **5/5** | This is the most literal realization of Copy-Link-Patch: copy native fragments, link continuations, patch data/control holes, enter once. It directly attacks the current per-tile mmap/function-call boundary. |
| **Moonlift philosophy fit** | **3/5 mixed** | Explicit continuations and typed control edges fit Moonlift’s philosophy. Raw physical endpoint contracts, ISA-specific relocs, and low-level fragment ABI are less Moonlift-like than typed region composition. |
| **Correctness risk** | **5/5 high** | The hardest risks are physical endpoint soundness, projection correctness, fact/dependency fidelity, and confusing current `exit`/`fail` holes with true branch targets. Current runtime correctness assumes frame state is synchronized at exits; this approach wants to break that invariant safely. |
| **Runtime complexity** | **5/5 high** | The runtime becomes an image linker: layout fragments, patch branches, manage projection/fallback stubs, validate facts/deps, allocate one executable region, handle W^X/cache flushing, and preserve resume semantics. |
| **Build/foundry impact** | **5/5 high** | The foundry must preserve labels, continuation offsets, clobbers, physical ABI IDs, branch relocs, projection slices, and likely architecture-specific metadata. The current bank already has millions of descriptors; richer fragment metadata may be large. |
| **Experimentability** | **3/5 moderate** | It is the best way to measure real Copy-Link-Patch mechanics, but early benchmarks may mostly measure removal of current C-call/page overhead rather than semantic fusion value. Narrow i64/guard spans are the most interpretable first surface. |

## Verdict

**Yes with major caveats.**

Approach B is the most faithful choice if the goal is to validate real byte-level Copy-Link-Patch rather than merely richer semantic planning. It directly addresses the present mismatch: current stencils are callable C functions, not linkable fragments.

The cost is that it moves SpongeJIT into a much more dangerous layer: physical ABI design, native code layout, relocation correctness, projection obligations, and runtime image linking.

## Strongest risks

1. **Projection correctness**
   - Current exits assume frame state is already synchronized.
   - Copy-Link-Patch gains value by avoiding redundant stores/loads, but that makes every guard/residual exit require exact reconstruction.

2. **Physical endpoint contracts**
   - Registers, flags, scratch space, stack alignment, clobbers, and call boundaries must be explicit and enforced.
   - C codegen previously hid all of this.

3. **Control-hole ambiguity**
   - Existing `exit`/`fail` holes are resume metadata writes, not branch/link targets.
   - Native continuation relocations need a distinct semantic category.

4. **Fact/payload/dependency insufficiency**
   - `SponFactSig` is too compressed for shape IDs, field offsets, call targets, and dependency epochs.
   - Current PUC runtime refuses many payload-bearing holes.

5. **Benchmark interpretation**
   - Comparing against today’s per-tile mmap/function-call execution may overstate wins from Copy-Link-Patch itself.

## Essential safeguards if chosen

- Treat projection recipes as mandatory before allowing store/load seam removal.
- Keep unsupported hole roles fail-loud rather than silently patching approximations.
- Constrain the first experiments to i64 slots, guards, simple immediates, and simple exits.
- Validate native fragments with shadow execution against the interpreter/Tier 1 path.
- Add descriptor-level checks for clobbers, endpoint contracts, relocation kinds, and exit pc conventions.
- Preserve Tier 1 C-function tiles as the fallback and comparison baseline.

**Bottom line:** Approach B is high-risk, high-upside, and architecturally disruptive, but it is the clearest path to proving whether SpongeJIT Copy-Link-Patch can work as a true native fragment backend.

## Documenter Output — 2026-05-29 09:38:47

# Architectural Decision: SpongeJIT Copy-Link-Patch Native Fragment ABI

**Workflow:** `wf-sponjit-copy-link-patch`  
**Decision:** Choose **Approach B: Native Fragment ABI with Continuation Relocations**.

## Intended repo doc update targets

Primary target:

- `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md`

Supporting targets likely affected by the eventual design:

- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua`
- `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua`
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.c`

---

## Goal

Enable SpongeJIT Tier 2 to validate real byte-level Copy-Link-Patch by moving beyond callable C-function stencils toward native code fragments with explicit entry points, continuation exits, physical endpoint contracts, and relocatable control/data holes, while preserving the current Tier 1 C-function tile system as the fallback and comparison baseline.

---

## Incentives

The current Tier 1 bank proves that SpongeJIT can select, copy, patch, and execute offline-generated tiles, but it does not prove that stencils are linkable fragments. Existing generated stencil bytes are whole C functions with compiler-chosen locals/registers, prologue/epilogue behavior, and C-call boundaries. Runtime materialization copies each selected tile into its own executable page and invokes each tile through C. This makes current benchmarks useful for selector and copy/patch costs, but not sufficient to validate direct fallthrough, native continuation linking, or store/load seam removal.

The richer semantic metadata needed for Copy-Link-Patch mostly exists before bank generation, in SSA and Stencil IR, but is discarded or compressed in the public bank ABI. `SponTileDesc` exposes byte offsets, sizes, holes, slotmaps, pattern keys, and fact masks, but not SSA node specs, dependency strings, projection recipes, physical endpoint contracts, clobbers, or continuation labels. Current exit holes are resume metadata writes, not branch targets. Current projection metadata is count-level, not recipe-level. Therefore, a Tier 2 backend needs a distinct native-fragment ABI rather than treating the existing C-function tile ABI as linkable.

---

## Current State

### SSA and Stencil IR

SpongeJIT currently lowers PUC opcode windows into semantic SSA using:

- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua`

SSA values carry types, facts, optional residency hints, effects, guards, memory tokens, exits, and dependencies. However, not all of this survives into serialized bank metadata. `active_node_specs` currently includes op/codegen/effect/guard/deps/inputs/outputs/output types, but not memory tokens or reliable physical residency contracts.

Stencil IR, defined in `stencil_ir.lua`, contains ops, values, holes, slotmaps, exits, facts, source ops, and config. Stencil ops carry inputs, outputs, args, effect, source, hole, guard, exit, and deps. This is semantically richer than the public bank ABI and can describe guards, effects, exits, and hole roles.

### Current generated C-function backend

`stencil_to_c.lua` emits one C function per stencil form. It uses `extern __H_N` holes to force relocations. Guard and residual exits write metadata into `SponExecCtx`, including `exit_kind`, `exit_pc`, `exit_op_idx`, and `exit_hole`, then return to C. These exit/fail holes are resume metadata, not native branch targets.

The generated stencil bytes are therefore function-shaped, not fragment-shaped. They do not expose explicit native entry labels, continuation labels, clobber sets, physical input/output locations, or branch relocation sites suitable for direct linking.

### Bank ABI

The public bank ABI is defined in:

- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h`

`SponTileDesc` exposes:

- tile id
- code offset/size
- hole slice
- slotmap slice
- arity
- flags
- pattern key
- fact-transfer signatures

`SponHoleReloc` exposes code offset, hole id, relocation kind, role kind, op index, and role arg. `SponSlotMapEntry` maps canonical tile-local slot classes to source bytecode operands.

This ABI supports Tier 1 selection and materialization, but it is not a typed macro-instruction catalog. It does not expose function names, Stencil IR op lists, SSA node specs, endpoint contracts, clobbers, dependency strings, exit descriptors, projection recipes, or accepted/produced physical locations.

### Runtime materialization

The PUC runtime uses:

- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.h`
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.c`
- `experiments/lua_interpreter_vm/spongejit/puc/lsponjit.c`

`SponImage` stores selected patched tiles and their PC spans. Each selected tile is copied into its own executable mapping, patched, marked executable, and called as a `SponTileFn`. Execution loops tile-by-tile through C. If a tile exits, the runtime resumes using the coarse exit metadata.

Current runtime facts are primarily i64 slot observations. Payload-bearing roles such as shape ids, field offsets, array offsets, call targets, and barrier-related holes exist in IR/bank enums, but the PUC materializer refuses them because dependency epochs and payload leases are not implemented.

### Design tension

Tier 1 correctness relies on the invariant that accepted tiles materialize canonical frame state and return through coarse exits. Copy-Link-Patch’s performance value comes from breaking that invariant locally: avoiding redundant frame stores/loads, linking fragments directly, and entering a fused image once. That requires stronger projection metadata, explicit native continuation semantics, and physical ABI contracts that do not exist today.

---

## Chosen Target

### Approach

The chosen design direction is **Approach B: Native Fragment ABI with Continuation Relocations**.

This approach replaces C-function-shaped stencils, for Tier 2 purposes, with raw native code fragments whose entry and exit labels are explicit relocation targets. A Tier 2 image is built by copying selected fragments into one executable region, patching data holes and control holes, linking successful continuations to successor entries, and entering the image once.

Approach B was chosen because it is the most literal realization of Copy-Link-Patch. It directly addresses the present mismatch: current stencils are callable C functions, but Copy-Link-Patch needs linkable fragments.

### Architecture

The Tier 2 direction requires a native-fragment ABI containing:

- explicit fragment entry offsets
- explicit continuation exit offsets
- physical input contracts
- physical output contracts
- clobber sets
- scratch requirements
- data relocation holes
- control relocation holes
- projection recipe references
- physical ABI identifier
- architecture-specific relocation metadata

The current overloaded hole vocabulary must be separated into at least two semantic classes:

| Class | Meaning |
|---|---|
| Data holes | slot, slot store, immediate, const, bool, payload values |
| Control holes | fallthrough edge, guard edge, residual edge, boundary edge, projection-stub edge |

Existing `exit`/`fail` holes cannot be reused as native branch targets without distinction, because today they encode resume metadata writes.

The runtime Tier 2 materializer becomes an image linker:

1. Select a sequence of fragment descriptors.
2. Validate available facts and required facts.
3. Validate supported hole roles.
4. Allocate one executable image region.
5. Copy native fragments into the region.
6. Patch data holes.
7. Patch continuation relocations.
8. Patch guard/residual exits to projection/fallback stubs.
9. Enter the image once.
10. On exit, resume through the interpreter/Tier 1-compatible fallback path using correct projection state.

The first ABI surface is constrained to simple native fragments for i64 slot arithmetic, guards, immediates, and simple exits.

### Relationship to current Tier 1

Tier 1 remains the fallback and comparison baseline. The existing C-function tile bank, selector, copy/patch materializer, and per-tile execution loop are not discarded as part of the decision. They remain useful for:

- validating semantic tile selection
- measuring baseline selector/copy-patch behavior
- falling back when Tier 2 cannot support a hole role, dependency, projection, or fragment ABI case
- comparing Tier 2 fused-image execution against current per-tile mmap/function-call execution

Tier 2 is a new backend direction above Tier 1, not a reinterpretation of current C-function stencils as already-linkable fragments.

### Why Approach A was not chosen

Approach A, Semantic Region Bank + Late Image Compiler, would prioritize a metadata-rich semantic catalog and generate executable fused images later. It has stronger semantic/projection focus, but sacrifices immediate validation of byte-level Copy-Link-Patch mechanics and requires a new image compiler before performance can be measured. The critique identified the risk that the system could become metadata-complete before it is execution-complete.

### Why Approach C was not chosen

Approach C, Moonlift-Style Region Source ABI, would map SpongeJIT stencils into typed regions with named continuations and compose them through a Moonlift-like region protocol. This aligns with typed control and explicit continuation contracts, but makes Tier 2 closer to a JIT/compiler integration path than a pure copy-link-patch linker. The workflow identified risk around mapping dynamic Lua VM facts, payload leases, and fallback projection into monomorphic Moonlift regions without substantial host/runtime ABI machinery.

### Tradeoffs acknowledged

Approach B sacrifices portability and simplicity. It introduces tight coupling between SpongeJIT IR, native code emission, bank metadata, runtime materialization, relocation format, ISA, calling convention, and executable-memory policy. It also requires replacing or augmenting `stencil_to_c.lua` with a low-level native emitter, likely architecture-specific at first.

This cost is accepted because Approach B directly tests the central Copy-Link-Patch claim: whether native fragments can be copied, linked, patched, and executed as one fused image with direct continuations.

### Risks acknowledged

The chosen approach carries the risks identified in critique:

1. **Projection correctness**  
   Current exits assume synchronized frame state. Store/load seam removal is unsafe unless every guard/residual exit has an exact projection recipe.

2. **Physical endpoint contracts**  
   Registers, flags, scratch space, stack alignment, clobbers, and call boundaries must be explicit and enforced. C codegen no longer hides these details.

3. **Control-hole ambiguity**  
   Existing `exit`/`fail` holes are not branch/link targets. Native continuation relocations need distinct semantics.

4. **Fact/payload/dependency insufficiency**  
   `SponFactSig` is too compressed for shape ids, field offsets, call targets, payload leases, and dependency epochs. Current PUC runtime refuses many payload-bearing holes.

5. **Benchmark interpretation**  
   Early comparisons against current per-tile mmap/function-call execution may overstate Copy-Link-Patch wins by measuring removal of implementation overhead rather than semantic fusion value.

---

## Required Safeguards

The decision includes the critique’s safeguards as mandatory boundaries for the Tier 2 direction:

- Projection recipes are mandatory before enabling store/load seam removal.
- Unsupported hole roles must fail loudly rather than being patched approximately.
- First experiments are constrained to i64 slots, guards, simple immediates, and simple exits.
- Native fragments must be validated with shadow execution against interpreter/Tier 1 behavior.
- Descriptor-level checks must cover clobbers, endpoint contracts, relocation kinds, and exit PC conventions.
- Tier 1 C-function tiles remain the fallback and comparison baseline.

---

## Experiment Boundaries

Initial experiments should avoid payload-heavy and dependency-heavy cases. The most interpretable first surface is i64 arithmetic and guard-heavy spans because current runtime fact observation already supports i64 slot facts and those spans exercise slots, guards, box/unbox behavior, store/load seams, and simple exits.

Initial experiments should not treat table/shape/field/call-target spans as the primary validation surface because they currently fail earlier on missing payload values, dependency epochs, unpatchable holes, and compressed fact signatures.

Residual-heavy or unlowered opcode sequences are also not the main validation target because they mostly test fallback coverage and boundary handling rather than native fragment linkability.

---

## Migration Implications

The migration from Tier 1 C-function stencils to Tier 2 native fragments is high cost and cross-cutting. It affects:

- IR metadata preservation
- code emission
- bank generation
- public bank ABI
- runtime materialization
- executable memory layout
- relocation handling
- projection/fallback machinery
- testing and benchmarking

The key migration implication is that existing C-function tile bytes cannot simply become linkable fragments. Tier 2 needs a new fragment descriptor and native emission path with explicit physical endpoint and continuation metadata. Tier 1 should remain intact while Tier 2 is introduced experimentally.

## Planner Output — 2026-05-29 09:56:44

## Goal

Plan a staged migration from C-function SpongeJIT stencils to one conforming native fragment ABI used by both Tier 1 floor selection and Tier 2 hot-region composition.

## Plan

1. **Freeze current baseline first**
   - Inspect and record behavior of:
     - `spongejit/src/stencil_to_c.lua`
     - `spongejit/src/build_bank.lua`
     - `spongejit/puc/sponjit_runtime.c`
     - `spongejit/puc/lsponjit.c`
   - Keep existing C-function path buildable as a temporary migration baseline, but label it non-conforming and do not extend it with new features.

2. **Add native fragment ABI types before changing codegen**
   - Extend `spongejit/include/sponbank.h` with the spec’s descriptor enums/types:
     - physical ABI
     - locations/value types
     - endpoints
     - data relocations
     - control relocations
     - fact/effect/projection/dependency descriptors
     - fragment descriptors
   - Add accessor declarations such as:
     - `spon_bank_fragment_count`
     - `spon_get_fragment`
     - `spon_fragment_data`
     - `spon_fragment_endpoints`
     - `spon_fragment_data_relocs`
     - `spon_fragment_control_relocs`
   - Keep old `SponTileDesc` declarations temporarily for baseline tests only.

3. **Introduce a Lua-side fragment metadata schema**
   - Add `spongejit/src/fragment_ir.lua`.
   - Implement constructors and validators for:
     - `PhysicalAbiDesc`
     - `FragmentDesc`
     - `EndpointDesc`
     - `LocationDesc`
     - `DataRelocDesc`
     - `ControlRelocDesc`
     - `ProjectionDesc`
     - `DependencyDesc`
   - The first validator should reject:
     - missing `ENTRY`
     - missing fact transfer
     - non-success endpoint without projection
     - unsupported payload/dependency roles
     - C-function-shaped metadata pretending to be a fragment

4. **Preserve required SSA metadata**
   - Modify `spongejit/src/ssa.lua` `active_node_specs()` to serialize:
     - `source`
     - `mem_in`
     - `mem_out`
     - value residency
     - exit object
   - Modify `spongejit/src/ssa_atoms.lua` if needed so reopened node specs preserve the new fields.
   - Add tests proving `compile_nodes(r.active_node_specs)` round-trips memory/residency/exit metadata.

5. **Add projection recipe generation**
   - Add `spongejit/src/fragment_projection.lua`.
   - Initially support only:
     - `PROJ_SYNCED_FRAME`
     - simple i64 register/slot projections
     - `BOX_I64` projection entries
   - Wire this into SSA/stencil summaries so every guard/residual/boundary exit has either a synced-frame projection or an explicit recipe.
   - Do not enable store/load seam deletion until projection tests pass.

6. **Lower Stencil IR to abstract fragment descriptors**
   - Add `spongejit/src/stencil_to_fragment.lua`.
   - Consume current `Stencil` ops and produce fragment metadata, not machine code yet.
   - Initial conforming surface:
     - `LoadSlot`
     - `StoreI64Slot`
     - `GuardI64`
     - `UnboxI64`
     - `ConstI64` / `ConstI64Hole`
     - `AddI64`, `SubI64`, `MulI64`
     - simple success continuation
     - guard failure exit
   - Reject table/shape/field/array/call/barrier fragments for now.

7. **Define the first physical ABI**
   - Add `spongejit/src/fragment_abi_x64.lua`.
   - Define one x86-64 SysV ABI descriptor:
     - `ctx` location
     - frame/base location
     - scratch GPRs
     - preserved/clobbered registers
     - stack alignment
     - flag clobber policy
   - Make every fragment reference this ABI id.

8. **Add offline native fragment emitter**
   - Add `spongejit/src/fragment_to_asm.lua`.
   - Emit assembler, not runtime-encoded instructions.
   - Generate explicit labels for:
     - entry
     - ok continuation
     - guard fail
     - boundary/return stubs
   - Generate distinct relocation symbols for:
     - data holes
     - control holes
   - Do not reuse current `exit`/`fail` holes as branch targets.

9. **Update worker pipeline experimentally**
   - Modify `spongejit/src/worker_compile.lua` to optionally emit fragment metadata/asm when `SPON_FRAGMENT_BACKEND=1`.
   - Write new JSON artifacts:
     - `grammar_fragments_N.json`
     - `grammar_fragment_relocs_N.json`
     - `grammar_fragment_asm_N.S`
   - Keep current `grammar_c_code_N.c` output until native fragment execution gates pass.

10. **Add fragment build script**
    - Add `spongejit/build_fragments.sh`.
    - Compile generated `.S` chunks to `.o`.
    - Link into `build/cp_lib/fragments.o`.
    - Extract:
      - symbols
      - `.text`
      - objdump relocations
      - endpoint label offsets
    - Keep this separate from `build_stencils.sh` during migration.

11. **Generate a native fragment bank**
    - Add `spongejit/src/build_fragment_bank.lua`.
    - Emit descriptor arrays matching the new `sponbank.h` ABI.
    - Emit selector candidate tables using the same pattern/fact-transfer logic currently in `build_bank.lua`.
    - For Tier 1, preserve offline-saturated arity selection: longest legal fragment span first, with fact flow and slot remapping.

12. **Add metadata conformance tests**
    - Add Lua tests for:
      - descriptor validation
      - endpoint completeness
      - control/data reloc separation
      - projection completeness
      - unsupported hole rejection
      - i64 fragment catalog generation
    - Gate with existing:
      - `tests/test_spongejit_real_ssa.lua`

13. **Implement dry-run linker validation before execution**
    - Add C or Lua dry-run tests that select fragment sequences and validate:
      - ABI compatibility
      - canonical slot resolution
      - fact transfer
      - endpoint compatibility
      - clobber safety
      - projection completeness
      - layout/control-target resolution
    - No executable memory yet.

14. **Add native image linker**
    - Add `spongejit/puc/sponjit_fragment_linker.c`.
    - Add declarations to `spongejit/puc/sponjit_runtime.h`.
    - Implement:
      - single executable allocation
      - fragment layout
      - data relocation patching
      - control relocation patching
      - projection/fallback stub installation
      - atomic publication only after full validation
    - Unsupported relocation/dependency/projection kinds must reject the image.

15. **Convert floor/Tier 1 execution to fragments**
    - Modify `spongejit/puc/sponjit_runtime.c` so `spon_image_build` can build a native-fragment floor image behind a feature flag.
    - Modify `spon_image_execute` to enter one linked image, not loop over C-function tiles.
    - Initial floor policy should keep frame state synchronized unless projection metadata proves otherwise.

16. **Keep current path as migration fallback only**
    - Add build/runtime flag:
      - default: current C-function baseline until fragment floor passes gates
      - opt-in: native fragment floor
    - Do not add new optimizations to `stencil_to_c.lua`.
    - Once native L0/i64 floor passes execution tests, switch default to native fragments.

17. **Add execution equivalence tests**
    - Add a new C benchmark/test similar to `bench_execute_tile.c`, but using linked fragments.
    - Validate:
      - i64 ADDI/ADD/SUB/MUL sequences
      - guard success
      - guard failure resume pc/op idx
      - frame state after exit
      - no unsupported role silently patches

18. **Add Tier 2 online composition path**
    - Modify `spongejit/puc/lsponjit.c` after Tier 1 works.
    - Reuse the same fragment selector/linker.
    - Tier 2 only changes policy:
      - longer stable traces
      - fewer bridges
      - register endpoints preserved across fragments
      - projection-validated seam removal
    - It must not use a second ABI or runtime instruction generation.

19. **Benchmark gates**
    - Keep current baseline benchmarks running:
      - `puc/bench_sponbank_puc.c`
      - `puc/bench_execute_tile.c`
    - Add:
      - `puc/bench_sponfragment_link.c`
      - `puc/bench_execute_fragment.c`
    - Required gates:
      - selection still covers L0 floor
      - native fragment image builds reject invalid cases
      - i64 linked image matches interpreter behavior
      - no regression in existing baseline unless feature flag is enabled

20. **Final migration cleanup**
    - After native fragment floor covers required L0/i64 surface:
      - stop generating C-function banks by default
      - mark `stencil_to_c.lua` legacy/test-only
      - remove runtime dependency on `SponTileFn`
      - make `SponFragmentDesc` the only maintained bank ABI

## Files to Modify

- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` - add native fragment ABI structs/enums/accessors.
- `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` - serialize memory/residency/exit metadata.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua` - preserve reopened metadata.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` - add validation hooks needed by fragment lowering, without overloading old holes.
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` - optional fragment backend artifact emission.
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.h` - add fragment image/linker declarations.
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.c` - route image build/execute through native fragment linker under migration flag.
- `experiments/lua_interpreter_vm/spongejit/puc/lsponjit.c` - later Tier 2 policy using same fragment linker.
- `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` - later stop default C-function bank generation after native gates pass.
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` - extend SSA metadata invariants.

## New Files

- `experiments/lua_interpreter_vm/spongejit/src/fragment_ir.lua` - descriptor schema and validation.
- `experiments/lua_interpreter_vm/spongejit/src/fragment_abi_x64.lua` - first physical ABI definition.
- `experiments/lua_interpreter_vm/spongejit/src/fragment_projection.lua` - projection recipe generation.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua` - Stencil IR to fragment descriptor lowering.
- `experiments/lua_interpreter_vm/spongejit/src/fragment_to_asm.lua` - offline native assembly emitter.
- `experiments/lua_interpreter_vm/spongejit/src/build_fragment_bank.lua` - generated native fragment bank.
- `experiments/lua_interpreter_vm/spongejit/build_fragments.sh` - fragment build pipeline.
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_fragment_linker.c` - runtime copy/link/patch image linker.
- `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua` - metadata/conformance tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua` - projection recipe tests.
- `experiments/lua_interpreter_vm/spongejit/puc/bench_sponfragment_link.c` - linker/materialization benchmark.
- `experiments/lua_interpreter_vm/spongejit/puc/bench_execute_fragment.c` - execution equivalence benchmark.

## Risks

- Projection correctness is the main blocker; do not remove frame sync until recipes are complete.
- Physical ABI mistakes can corrupt VM state; start with i64-only fragments.
- Current `exit`/`fail` holes must not be reused as control relocations.
- Keeping the C path too long risks accidental dual-ABI maintenance; keep it baseline-only.
- Early speedups may mostly measure removal of C-call/mmap overhead, not semantic fusion.

## Edit-planner Output — 2026-05-29 11:10:33

### Precondition Checks

- Confirm these anchors still exist:
  - `experiments/lua_interpreter_vm/spongejit/src/ssa.lua`: `active_node_specs(g)` starts around line 54.
  - `src/ssa_atoms.lua`: `M.reopen_node_specs` starts around line 12.
  - `src/stencil_ir.lua`: `PUC_PATCHABLE_ROLE` around line 21, `Stencil:hole` around line 88, `M.validate` around line 135.
  - `src/ssa_to_stencil.lua`: guard `fail` hole allocation around lines 197-220; exit hole allocation around lines 256-267.
  - `src/worker_compile.lua`: imports `StencilToC` around line 12 and writes `grammar_c_code_N.c` around lines 88-92.
- Confirm no worker starts from generated `build/cp_lib/libsponbank.c`; this first slice changes source/schema/tests, not generated artifacts.
- Confirm `luajit` is available from repo root.

---

### Files to Modify

#### `experiments/lua_interpreter_vm/spongejit/include/sponbank.h`

**Goal**: Hard-replace public tile/C-function ABI declarations with native fragment ABI declarations.

**Edit blocks**

1. **Lines 8-9**: Modify typedefs.
   - Before:
     ```c
     typedef uint64_t SponFactSig;
     typedef uint32_t SponTileId;
     ```
   - After:
     ```c
     typedef uint64_t SponFactSig;
     typedef uint32_t SponFragmentId;
     ```

2. **Lines 26-156**: Remove all tile-specific structs/accessors/selectors.
   - Remove:
     - `SponTileChoice`
     - `SponSelectStats` only if it names tiles; re-add as fragment-neutral if needed.
     - `SponHoleReloc`
     - `SponTileDesc`
     - `SPON_TILE_PUC_PATCHABLE`
     - `SPON_HOLE_*`
     - all `spon_bank_tile_*`, `spon_get_tile`, `spon_tile_*`, `spon_select_*` declarations.
   - Add fragment-native enums/structs:
     ```c
     typedef struct {
       SponFragmentId fragment_id;
       uint32_t pc_start;
       uint32_t pc_end;
     } SponFragmentChoice;

     typedef struct {
       uint64_t pattern_probes;
       uint64_t candidate_checks;
       uint32_t choices;
     } SponSelectStats;
     ```
   - Add enums:
     - `SPON_ABI_X86_64_SYSV_SPON_V1`
     - `SPON_VALUE_TVALUE`, `SPON_VALUE_I64`, `SPON_VALUE_BOOL`, `SPON_VALUE_PTR`, `SPON_VALUE_UNKNOWN`
     - `SPON_LOC_NONE`, `SPON_LOC_REG`, `SPON_LOC_CTX_FIELD`, `SPON_LOC_FRAME_SLOT`, `SPON_LOC_IMMEDIATE`
     - `SPON_ENDPOINT_ENTRY`, `SPON_ENDPOINT_OK`, `SPON_ENDPOINT_GUARD_EXIT`, `SPON_ENDPOINT_RESIDUAL_EXIT`, `SPON_ENDPOINT_BOUNDARY_EXIT`, `SPON_ENDPOINT_UNLOWERED_EXIT`
     - `SPON_DATA_RELOC_SLOT`, `SPON_DATA_RELOC_SLOT_STORE`, `SPON_DATA_RELOC_IMM`, `SPON_DATA_RELOC_CONST`, `SPON_DATA_RELOC_BOOL`
     - `SPON_CONTROL_RELOC_FALLTHROUGH`, `SPON_CONTROL_RELOC_GUARD_FAIL`, `SPON_CONTROL_RELOC_RESIDUAL`, `SPON_CONTROL_RELOC_BOUNDARY`, `SPON_CONTROL_RELOC_PROJECTION_STUB`
     - `SPON_PROJ_SYNCED_FRAME`, `SPON_PROJ_BOX_I64`
   - Add structs:
     ```c
     typedef struct {
       uint16_t kind;
       uint16_t value_type;
       uint16_t reg;
       uint16_t reserved;
       int32_t index;
     } SponLocationDesc;

     typedef struct {
       uint16_t kind;
       uint16_t flags;
       uint32_t location_start;
       uint16_t n_locations;
       uint16_t projection_start;
       uint16_t n_projections;
     } SponEndpointDesc;

     typedef struct {
       uint32_t code_offset;
       uint16_t reloc_kind;
       uint16_t role_kind;
       uint16_t op_idx;
       int32_t role_arg;
     } SponDataReloc;

     typedef struct {
       uint32_t code_offset;
       uint16_t reloc_kind;
       uint16_t edge_kind;
       uint16_t endpoint_index;
       int32_t target_delta;
     } SponControlReloc;

     typedef struct {
       uint16_t kind;
       uint16_t value_type;
       uint16_t logical_slot;
       uint16_t value_index;
     } SponProjectionEntry;

     typedef struct {
       const char *name;
     } SponDependencyDesc;

     typedef struct {
       SponFragmentId fragment_id;
       uint32_t offset;
       uint32_t size;
       uint32_t endpoint_start;
       uint32_t data_reloc_start;
       uint32_t control_reloc_start;
       uint32_t slotmap_start;
       uint32_t projection_start;
       uint32_t dependency_start;
       uint16_t len;
       uint16_t n_endpoints;
       uint16_t n_data_relocs;
       uint16_t n_control_relocs;
       uint16_t n_slotmaps;
       uint16_t n_projections;
       uint16_t n_dependencies;
       uint16_t flags;
       uint16_t physical_abi;
       uint16_t reserved;
       uint64_t pattern_key;
       SponFactSig selector_sig;
       SponFactSig required_sig;
       SponFactSig checked_sig;
       SponFactSig produced_sig;
       SponFactSig killed_sig;
     } SponFragmentDesc;
     ```
   - Add accessors:
     ```c
     uint32_t spon_bank_fragment_count(void);
     uint32_t spon_bank_pattern_count(void);
     const SponFragmentDesc *spon_get_fragment(SponFragmentId id);
     const unsigned char *spon_fragment_data(SponFragmentId id);
     const SponEndpointDesc *spon_fragment_endpoints(SponFragmentId id, uint32_t *out_n);
     const SponDataReloc *spon_fragment_data_relocs(SponFragmentId id, uint32_t *out_n);
     const SponControlReloc *spon_fragment_control_relocs(SponFragmentId id, uint32_t *out_n);
     const SponSlotMapEntry *spon_fragment_slotmaps(SponFragmentId id, uint32_t *out_n);
     ```

**Patterns to enforce**
- No `Tile` names remain in this header.
- Data reloc roles and control reloc roles are separate enums.

**Danger zones**
- Keep `SponExecCtx` and `SPON_EXIT_*`; they are still fallback/projection runtime state, not tile ABI.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua`

**Goal**: Preserve source PC on guards so serialized SSA metadata is meaningful.

**Edit blocks**

1. **Lines 192-199 inside `Graph:guard`**: Modify `self:add` table.
   - Before:
     ```lua
     return self:add(guard_op, {
         inputs = { subject },
         effect = "guard",
         guard = { fact = fact, key = Facts.guard_key(fact) },
         exit = self:exit_projection("guard:" .. tostring(fact.predicate), pc),
         deps = copy_array(fact.deps),
     })
     ```
   - After:
     ```lua
     return self:add(guard_op, {
         inputs = { subject },
         source = pc,
         effect = "guard",
         guard = { fact = fact, key = Facts.guard_key(fact) },
         exit = self:exit_projection("guard:" .. tostring(fact.predicate), pc),
         deps = copy_array(fact.deps),
     })
     ```

**Danger zones**
- Do not change memory token creation here.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa.lua`

**Goal**: Serialize SSA metadata required by fragment validation: source, memory tokens, exits, and value residency.

**Edit blocks**

1. **After `copy_array` around lines 28-31**: Add `copy_map`.
   ```lua
   local function copy_map(t)
       local out = {}
       for k, v in pairs(t or {}) do out[k] = v end
       return out
   end
   ```

2. **Lines 54-75 `active_node_specs(g)`**: Replace body with richer serialization.
   - Add per-node fields:
     - `source = n.source`
     - `mem_in = copy_map(n.mem_in)`
     - `mem_out = copy_map(n.mem_out)`
     - `exit = n.exit and copy_map(n.exit) or nil`
     - `input_types`
     - `input_residencies`
     - `output_residencies`
   - Existing fields must remain:
     - `op`, `codegen_op`, `args`, `effect`, `guard_fact`, `deps`, `inputs`, `outputs`, `output_types`.

**Patterns**
- Use shallow copies only; match existing `copy_array` style.
- Keep `active_node_specs` local.

**Danger zones**
- Do not serialize full `g.values` table; only node-local input/output summaries.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua`

**Goal**: Reopen serialized SSA specs without losing memory/residency/exit metadata.

**Edit blocks**

1. **After `local vmap = {}` around line 15**: Add helpers:
   ```lua
   local function copy_array(xs) ... end
   local function copy_map(t) ... end
   ```

2. **Lines 17-21 `mapped_input`**: Accept type/residency.
   - Change signature to:
     ```lua
     local function mapped_input(old, ty, residency)
     ```
   - When creating placeholder value:
     ```lua
     vmap[old] = g:new_value(ty or "Unknown", nil, nil, residency)
     ```

3. **Lines 23-33 `mapped_outputs`**: Pass output residency.
   - Use:
     ```lua
     local residency = spec.output_residencies and spec.output_residencies[i]
     local nv = g:new_value(ty, nil, nil, residency)
     ```

4. **Lines 36-53 main loop**:
   - When mapping inputs:
     ```lua
     local ty = spec.input_types and spec.input_types[i]
     local residency = spec.input_residencies and spec.input_residencies[i]
     ins[#ins + 1] = mapped_input(old, ty, residency)
     ```
   - Exit handling:
     ```lua
     local exit = spec.exit and copy_map(spec.exit) or nil
     ```
     Keep old synthetic exit fallback only when `spec.exit` is nil.
   - In `g:add`, include:
     ```lua
     mem_in = copy_map(spec.mem_in),
     mem_out = copy_map(spec.mem_out),
     source = spec.source or pc,
     ```

**Danger zones**
- Preserve compatibility with old specs in tests by retaining synthetic guard/residual exit fallback.

---

#### `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua`

**Goal**: Stop treating `exit`/`fail` as patchable hole roles; Stencil IR becomes fragment-oriented metadata, not C-ready ABI.

**Edit blocks**

1. **Lines 1-5 comment**: Rewrite to remove “C-ready”.
   - After:
     ```lua
     -- stencil_ir.lua -- semantic stencil shape IR for native fragment lowering.
     --
     -- Semantic SSA remains the Lua semantics authority. This module defines
     -- hole-parametric operation shape consumed by normalization, contracts,
     -- fragment metadata validation, and later native emission.
     ```

2. **Lines 21-24**: Replace `PUC_PATCHABLE_ROLE`.
   - Before:
     ```lua
     local PUC_PATCHABLE_ROLE = {
       unknown = true, slot = true, imm = true, const = true, bool = true,
       exit = true, fail = true, slot_store = true,
     }
     M.PUC_PATCHABLE_ROLE = PUC_PATCHABLE_ROLE
     ```
   - After:
     ```lua
     local DATA_HOLE_ROLE = {
       unknown = true,
       slot = true,
       slot_store = true,
       imm = true,
       const = true,
       bool = true,
       shape_offset = true,
       shape_id = true,
       metatable_offset = true,
       field_offset = true,
       array_base_offset = true,
       call_target = true,
       barrier = true,
     }
     M.DATA_HOLE_ROLE = DATA_HOLE_ROLE
     ```

3. **Lines 60-67 `Stencil:new_value`**: Add residency/facts.
   - Change signature:
     ```lua
     function Stencil:new_value(ty, source, residency, facts)
     ```
   - Value table:
     ```lua
     local v = { id = id, ty = ty or "Unknown", source = source, residency = residency, facts = copy_array(facts) }
     ```

4. **Lines 88-105 `Stencil:hole`**:
   - Use `DATA_HOLE_ROLE` for default `patchable`.
   - Add explicit assertion/rejection:
     ```lua
     assert(t.role_kind ~= "exit" and t.role_kind ~= "fail",
            "exit/fail are control endpoints, not data holes")
     ```
   - Replace `PUC_PATCHABLE_ROLE[...]` with `DATA_HOLE_ROLE[...]`.

5. **Lines 135-163 `M.validate`**:
   - Add error if any hole has `role_kind == "exit"` or `"fail"`.
   - Keep canonical slot validation for `slot`/`slot_store`.

**Danger zones**
- Do not remove `st.exits`; fragment lowering needs it.
- Shape/table/call-target roles remain valid data roles in Stencil IR but must be rejected by first-slice fragment lowering.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua`

**Goal**: Remove control holes from Stencil IR and preserve value residency in stencil values.

**Edit blocks**

1. **Lines 132-142 `map_value` / `new_output`**:
   - Change `st:new_value(...)` calls to pass residency/facts:
     ```lua
     vmap[vid] = st:new_value(vv and vv.ty or "Unknown", vid, vv and vv.residency, vv and vv.facts)
     ```
     and same in `new_output`.

2. **Lines 197-220 guard lowering**:
   - Remove every `local fh = st:hole({ role_kind = "fail", ... })`.
   - Remove `hole = fh` from these `st:add` calls:
     - `GuardI64`
     - `GuardTable`
     - `GuardShape`
     - `GuardMetatableAbsent`
     - `GuardBounds`
     - `GuardCallTarget`
   - Keep semantic payload holes like `shape_offset`, `shape_id`, `metatable_offset`, `call_target`.

3. **Lines 256-267 exit lowering**:
   - Remove `role = ...` and `st:hole({ role_kind = "exit", ... })`.
   - Add exits without holes:
     ```lua
     st:add("ExitResidual", { inputs = ins, source = pc, args = args, exit = n.exit, effect = "residual" })
     st:add("ExitBoundary", { inputs = ins, source = pc, args = { op = op }, exit = n.exit, effect = n.effect or "return" })
     st:add("ExitUnlowered", { inputs = ins, source = pc, args = { op = op }, exit = n.exit, effect = "residual" })
     ```

**Danger zones**
- Existing C emitter would break; that is intended in hard-yank migration.
- Do not remove `exit = n.exit`; fragment projection depends on it.

---

#### `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua`

**Goal**: Stop producing C-function artifacts; emit fragment metadata artifacts.

**Edit blocks**

1. **Line 1 comment**:
   - Change “SSA compile + C codegen” to “SSA compile + native fragment metadata”.

2. **Line 12**:
   - Replace:
     ```lua
     local StencilToC = require("src.stencil_to_c")
     ```
   - With:
     ```lua
     local StencilToFragment = require("src.stencil_to_fragment")
     ```

3. **Lines 34-37 locals**:
   - Replace:
     ```lua
     local forms_by_key = {}
     local code_by_key = {}
     local forms_in_order = {}
     ...
     local c_blocks, all_holes = {}, {}
     ```
   - With:
     ```lua
     local forms_by_key = {}
     local fragments_in_order = {}
     local forms_in_order = {}
     ```

4. **Lines 65-76 C generation block**:
   - Remove `code_by_key` dedupe and `StencilToC.generate`.
   - Add:
     ```lua
     local frag_result = StencilToFragment.generate(r, { facts = facts })
     if not frag_result.ok then
       goto fragment_rejected
     end
     local fragment = frag_result.fragment
     ```
   - Store `fragment = fragment` in form table.
   - Add label before count increment:
     ```lua
     ::fragment_rejected::
     ```

5. **Lines 88-92 artifact writes**:
   - Remove writing:
     - `grammar_c_code_N.c`
     - `grammar_holes_N.json`
   - Add:
     ```lua
     Util.write_json(tmp("grammar_fragments_" .. ci .. ".json"), { fragments = fragments_in_order })
     Util.write_json(tmp("grammar_result_" .. ci .. ".json"), { forms = forms_in_order, compiles = lc, ok = lok })
     ```

**Danger zones**
- Lua labels cannot jump over local variable declarations in invalid ways. Put `::fragment_rejected::` at same lexical level as current loop body.

---

#### `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua`

**Goal**: Extend existing SSA invariants to check memory/residency/exit round-trip.

**Edit blocks**

1. **After current compile_nodes test around lines 48-55**: Add assertions:
   ```lua
   local saw_mem = false
   local saw_residency = false
   local saw_exit = false
   for _, spec in ipairs(base.active_node_specs or {}) do
       if spec.source ~= nil then assert_true(type(spec.source) == "number", "source must serialize as number") end
       if spec.mem_in and spec.mem_in.frame then saw_mem = true end
       for _, rloc in ipairs(spec.output_residencies or {}) do
           if rloc == "gpr0" then saw_residency = true end
       end
       if spec.exit and spec.exit.reason then saw_exit = true end
   end
   assert_true(saw_mem, "active_node_specs must preserve memory input tokens")
   assert_true(saw_residency, "active_node_specs must preserve value residency")
   assert_true(saw_exit, "active_node_specs must preserve exit objects")
   ```

2. **In same block after reopening**:
   - Assert reopened specs still contain memory/residency:
     ```lua
     local rr = SSA.compile_nodes(base.active_node_specs, {})
     local saw_reopened_residency = false
     for _, spec in ipairs(rr.active_node_specs or {}) do
       for _, rloc in ipairs(spec.output_residencies or {}) do
         if rloc == "gpr0" then saw_reopened_residency = true end
       end
     end
     assert_true(saw_reopened_residency, "compile_nodes must round-trip residency")
     ```

---

### New Files

#### `experiments/lua_interpreter_vm/spongejit/src/fragment_ir.lua`

**Purpose**: Schema constructors and validators for the unified native fragment ABI.

**Contents sketch**
- Local helpers: `copy_array`, `has_kind`, `err`.
- Export enums:
  - `M.PHYSICAL_ABI`
  - `M.VALUE_TYPE`
  - `M.LOCATION_KIND`
  - `M.ENDPOINT_KIND`
  - `M.DATA_RELOC_KIND`
  - `M.CONTROL_RELOC_KIND`
  - `M.PROJECTION_KIND`
- Constructors:
  - `M.location(t)`
  - `M.endpoint(t)`
  - `M.data_reloc(t)`
  - `M.control_reloc(t)`
  - `M.projection(t)`
  - `M.fragment(t)`
- Validator:
  ```lua
  function M.validate_fragment(f)
      local errors = {}
      ...
      return #errors == 0, errors
  end
  ```
- Validation rules:
  - exactly one `entry` endpoint required.
  - at least one `ok` endpoint required.
  - every non-`ok`, non-`entry` endpoint needs a projection.
  - `data_relocs` must not use `exit`, `fail`, `guard_fail`, `fallthrough`.
  - `control_relocs` must not use data roles.
  - `fact_transfer` must contain selector/required/checked/produced/killed.
  - first slice rejects dependencies/payload roles unless explicitly marked unsupported.

---

#### `experiments/lua_interpreter_vm/spongejit/src/fragment_abi_x64.lua`

**Purpose**: First physical ABI descriptor: x86-64 SysV SpongeJIT fragment ABI v1.

**Contents sketch**
```lua
local M = {}

M.ID = "x86_64_sysv_spon_v1"

function M.desc()
  return {
    id = M.ID,
    arch = "x86_64",
    calling_convention = "sysv",
    ctx = { kind = "reg", reg = "rdi", ty = "ptr" },
    scratch_gprs = { "rax", "rcx", "rdx", "r8", "r9", "r10", "r11" },
    value_gprs = { "rax", "r10", "r11" },
    clobbers = { "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "flags" },
    stack_alignment = 16,
  }
end

return M
```

---

#### `experiments/lua_interpreter_vm/spongejit/src/fragment_projection.lua`

**Purpose**: Produce mandatory projection recipes for fragment exits.

**Contents sketch**
- `M.synced_frame(exit, source)` returns:
  ```lua
  {
    kind = "SYNCED_FRAME",
    reason = exit and exit.reason or "exit",
    pc = exit and exit.pc or source or 0,
    entries = {},
  }
  ```
- `M.for_exit(st, n, config)` initially always returns synced-frame projection.
- `M.validate_projection(p)` checks kind and pc.

**Important**
- Do not implement unsynced frame/store-load seam removal here.

---

#### `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua`

**Purpose**: Lower Stencil IR to abstract native fragment descriptors for i64/slot/guard surface.

**Imports required**
```lua
local FragmentIR = require("src.fragment_ir")
local Abi = require("src.fragment_abi_x64")
local Projection = require("src.fragment_projection")
local Contract = require("src.ssa_contract")
```

**Contents sketch**
- Supported ops table:
  ```lua
  local SUPPORTED_OP = {
    LoadSlot = true,
    StoreI64Slot = true,
    GuardI64 = true,
    UnboxI64 = true,
    ConstI64 = true,
    ConstI64Hole = true,
    AddI64 = true,
    SubI64 = true,
    MulI64 = true,
    ExitBoundary = true,
    ExitResidual = true,
    ExitUnlowered = true,
  }
  ```
- Supported data hole roles:
  ```lua
  slot=true, slot_store=true, imm=true, const=true, bool=true
  ```
- Public API:
  ```lua
  function M.generate(ssa_result, config)
      local fragment, errors = M.lower_result(ssa_result, config)
      return { ok = fragment ~= nil, fragment = fragment, errors = errors or {} }
  end
  ```
- `lower_result` should:
  - consume `ssa_result.stencil`.
  - compute contract via `Contract.from_result`.
  - create `entry` and `ok` endpoints.
  - create guard/boundary/residual endpoints from `n.exit`.
  - create `control_relocs` from guard/boundary/residual ops.
  - create `data_relocs` from supported holes only.
  - copy `slotmaps`, `deps`, `active_node_specs`, `stencil_ops`.
  - reject unsupported ops and unsupported hole roles loudly.
  - call `FragmentIR.validate_fragment`.

---

#### `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua`

**Purpose**: Unit tests for fragment descriptor validation.

**Test cases**
- Valid minimal fragment with `entry` + `ok` + fact transfer passes.
- Missing `entry` fails.
- Missing fact transfer fails.
- Data reloc with role `fail` or `exit` fails.
- Non-success endpoint without projection fails.
- Control reloc using data role fails.

---

#### `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua`

**Purpose**: Projection recipe tests.

**Test cases**
- `Projection.synced_frame` produces `kind == "SYNCED_FRAME"`.
- Compiling an i64 guard span and lowering to fragment gives every guard exit a projection.
- Projection pc equals SSA/stencil source pc convention, not arbitrary zero.

---

#### `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua`

**Purpose**: End-to-end first-slice descriptor tests for i64 slot arithmetic.

**Test cases**
- Compile:
  ```lua
  { { op = "ADDI", a = 1, b = 1, c = 1 } }
  ```
  with `R1 is_i64` fact.
- Lower via `StencilToFragment.generate`.
- Assert:
  - `ok == true`
  - physical ABI id is `x86_64_sysv_spon_v1`
  - has `entry`, `ok`, `guard_exit`
  - has data relocs for `slot`, `slot_store`, `imm`
  - has control reloc for `guard_fail`
  - no data reloc has role `fail` or `exit`
  - fact transfer includes checked/produced/killed signatures.
- Compile a table/shape example and assert fragment generation rejects unsupported payload roles.

---

### Files to Delete / Retire Immediately

#### `experiments/lua_interpreter_vm/spongejit/src/stencil_to_c.lua`
- Delete. It is the old C-function ABI emitter.

#### `experiments/lua_interpreter_vm/spongejit/test_stencil_to_c.lua`
- Delete or replace with `test_spongejit_stencil_to_fragment.lua`.

#### `experiments/lua_interpreter_vm/spongejit/generate_all_c.lua`
- Delete; C bank generation is not a maintained path.

#### `experiments/lua_interpreter_vm/spongejit/bench_real.lua`
#### `experiments/lua_interpreter_vm/spongejit/bench_stencil_vs_interp.lua`
- Delete or leave for later only if all `require("src.stencil_to_c")` imports are removed now.

---

### Order of Operations

1. Modify `ssa_ir.lua`, `ssa.lua`, and `ssa_atoms.lua` first.
2. Run:
   ```sh
   luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
   ```
3. Modify `stencil_ir.lua` and `ssa_to_stencil.lua` to remove control holes.
4. Add `fragment_ir.lua`, `fragment_abi_x64.lua`, and `fragment_projection.lua`.
5. Add `stencil_to_fragment.lua`.
6. Add the three new fragment tests.
7. Modify `worker_compile.lua` to emit fragment metadata instead of C.
8. Replace `sponbank.h` tile ABI with fragment ABI.
9. Delete/retire C-emitter files and stale C-emitter tests/scripts.
10. Run all relevant tests.

---

### Testing Strategy

Run incrementally:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
```

After adding fragment schema:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua
```

After adding projection:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua
```

After adding stencil lowering:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua
```

Final first-slice check:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua
```

Also grep for stale C path:

```sh
rg 'stencil_to_c|SponTile|spon_get_tile|grammar_c_code|grammar_holes' experiments/lua_interpreter_vm/spongejit
```

Expected after this slice: no maintained source path imports `src.stencil_to_c`.

---

### Pattern Memo

- `exit` / `fail` are control endpoints, never data holes.
- First fragment surface supports only i64/slot/guard/simple-exit ops.
- Unsupported payload roles must reject loudly.
- Every non-success endpoint requires projection.
- SSA specs must preserve `source`, `mem_in`, `mem_out`, `exit`, and value residency.
- Native fragment ABI uses `Fragment`, not `Tile`, naming everywhere touched.

## Worker Output — 2026-05-29 11:21:59

## Completed
Implemented the hard-yank native fragment ABI foundation for SpongeJIT:

- Added native fragment schema/ABI/projection/lowering modules.
- Preserved SSA source/memory/exit/residency metadata through `active_node_specs` and `compile_nodes`.
- Removed `exit`/`fail` as Stencil IR data holes; they are now control endpoints only.
- Added Stencil IR → native fragment descriptor lowering for i64/slot/guard/simple-exit surface.
- Replaced worker output with `grammar_fragments_*.json` metadata; no C code/hole artifacts.
- Replaced public bank header tile naming with fragment naming.
- Retired old C-function bank/build/runtime paths fail-loud or deleted planned C-emitter files.
- Added conformance/projection/lowering tests.

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/src/fragment_ir.lua` - new fragment ABI schema and validator.
- `experiments/lua_interpreter_vm/spongejit/src/fragment_abi_x64.lua` - new x86-64 SysV fragment ABI descriptor.
- `experiments/lua_interpreter_vm/spongejit/src/fragment_projection.lua` - new mandatory projection recipe helpers.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua` - new Stencil IR → fragment descriptor lowering.
- `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` - serializes source, mem tokens, exits, input/output types and residencies.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua` - reopens serialized specs preserving metadata.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` - guards now preserve source pc.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` - native-fragment semantic stencil IR; rejects `exit`/`fail` holes.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` - removes control holes and preserves value residency/facts.
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` - emits fragment metadata artifacts.
- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` - replaced tile ABI with fragment ABI declarations.
- `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` - retired fail-loud stub.
- `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` - retired fail-loud stub.
- `experiments/lua_interpreter_vm/spongejit/build_bank.sh` - retired fail-loud stub.
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.h` - fragment image naming.
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.c` - fail-loud non-tile runtime boundary stub.
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` - added metadata round-trip assertions.
- `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua` - new validator tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua` - new projection tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua` - new lowering tests.

Deleted retired C-function paths:
- `experiments/lua_interpreter_vm/spongejit/src/stencil_to_c.lua`
- `experiments/lua_interpreter_vm/spongejit/test_stencil_to_c.lua`
- `experiments/lua_interpreter_vm/spongejit/generate_all_c.lua`
- `experiments/lua_interpreter_vm/spongejit/bench_real.lua`
- `experiments/lua_interpreter_vm/spongejit/bench_stencil_vs_interp.lua`
- `experiments/lua_interpreter_vm/benchmarks/bench_pipeline.lua`

## Tests
Passed:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua
```

Also verified `worker_compile.lua` emits `grammar_fragments_1.json` and does not emit `grammar_c_code_1.c` or `grammar_holes_1.json`.

## Notes
- The old C-function runtime/materializer cannot coherently survive the header ABI replacement, so it was replaced with a fail-loud fragment-runtime boundary stub rather than preserved as a dual ABI.
- Unsupported payload/dependency-heavy fragments reject loudly in the new lowering path.

## Reviewer Output — 2026-05-29 11:26:40

## Files Reviewed
- `experiments/lua_interpreter_vm/spongejit/src/fragment_ir.lua` (lines 1-213)
- `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua` (lines 1-166)
- `experiments/lua_interpreter_vm/spongejit/src/fragment_projection.lua` (lines 1-39)
- `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` (lines 55-91)
- `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua` (lines 14-72)
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` (lines 18-156)
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` (lines 141-267)
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 37-106)
- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` (lines 1-243)
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.c` (lines 1-44)
- `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_*.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua`
- Legacy PUC benchmark/hack files found by grep.

## Critical (must fix)
- `experiments/lua_interpreter_vm/spongejit/puc/bench_sponbank_puc.c:36` / `bench_execute_tile.c:33` / `puc/build_puc_bank_hack.lua:36` - Legacy C-function tile ABI paths remain live and bypass `sponbank.h` by declaring `SponTileId`, `SponTileDesc`, `SponHoleReloc`, `SPON_HOLE_EXIT`, and `SPON_HOLE_FAIL` locally. The Lua wrappers still compile/link these against `build/cp_lib/libsponbank.so` if a stale bank exists. This violates the hard-yank: retire/delete these or make them fail-loud before compiling.
- `experiments/lua_interpreter_vm/spongejit/src/fragment_ir.lua:172-174` - Projection validation can be spoofed by setting `n_projections > 0` without an actual projection object or valid `projection_start` into `f.projections`. Since the C ABI only has flattened projection ranges, this can accept descriptors with no usable projection recipe. Validate `projection_start`, `n_projections`, range bounds, and projection kinds against `f.projections`.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua:140-153` vs `include/sponbank.h:77-203` - Emitted fragment metadata is not directly ABI-coherent: `physical_abi` is a string, `pattern_key` is `stencil_hash` string, reloc/endpoint kinds are strings, and fact signatures are literal-string objects, while the public ABI defines numeric fields. If this JSON is intended as the bank input, add an explicit lowering/mapping layer or emit ABI-shaped numeric metadata now.

## Warnings (should fix)
- `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua:115-116` - Entry/ok endpoints are emitted with no locations, and `fragment_ir.lua` does not require endpoint input/output locations or clobbers. This is under-specified for Approach B’s physical endpoint contract and will block real native linking.
- `experiments/lua_interpreter_vm/spongejit/puc/sponjit_runtime.c:13-43` - Runtime stubs silently return failure/zero facts. `spon_image_build`/`execute` returning `0` is safe, but `spon_observe_i64_slots` returning `0` silently erases the only currently useful runtime fact surface. Prefer preserving i64 observation or making the unavailable fragment runtime explicitly diagnostic under tracing.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua:101,122,131` - All data/control relocations use `code_offset = 0`. Acceptable before an assembler exists, but descriptors should be marked abstract/non-executable or validator should reject them for any executable/native-bank mode.
- `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua:31-54` - Tests cover ADDI guard/data-reloc surface but not the “simple-exit” part: no `RETURN`, `JUMP`, residual, or unlowered exit lowering is asserted. Add explicit boundary/residual/unlowered projection/control-reloc tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua:49-81` - Round-trip tests assert residency after reopen but not `mem_in`, `mem_out`, or `exit` after reopen. Add assertions for all newly serialized metadata.

## Suggestions (consider)
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua:83-84` - `grammar_result` embeds full fragments inside each form while also writing `grammar_fragments`. Consider storing only `fragment_id` in forms to avoid large duplicated JSON and identity drift.
- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h:217-243` - Header declares fragment selector APIs, but `build_bank.lua` is now a fail-loud stub. Either add a fail-loud stub implementation for these symbols or move declarations behind the future fragment-bank generator to avoid accidental link confusion.
- Add a grep-style retirement test that fails on `SponTile`, `SponHoleReloc`, `SPON_HOLE_EXIT`, `src.stencil_to_c`, `grammar_c_code`, and `grammar_holes` under maintained source paths.

## Summary
The core Lua Stencil/SSA changes are directionally correct: `exit`/`fail` are no longer created as data holes, and SSA metadata preservation is mostly implemented. The hard-yank is incomplete, though: legacy tile benchmarks/hacks can still execute stale C-function banks, projection validation is too weak for flattened ABI descriptors, and emitted fragment JSON is not yet coherently mapped to the public C ABI.

## Worker Output — 2026-05-29 17:53:01

## Completed

Continued the interrupted repair in `wf-sponjit-copy-link-patch` from the existing working tree.

Key repairs completed:
- Removed stale generated legacy build artifacts under `experiments/lua_interpreter_vm/spongejit/build`.
- Confirmed old PUC benchmark/runtime/hack files are deleted; only `puc/README.md` remains.
- Updated docs to remove references to deleted C-function stencil/build/PUC paths.
- Strengthened `fragment_ir.lua` ABI lowering:
  - fixed deterministic uint64 pattern-key literal generation
  - added numeric `hi/lo` ABI fields for uint64 keys/signatures
  - ensured payload data reloc enum coverage matches the C ABI
- Confirmed fragment validation covers projection ranges/kinds, explicit abstract offsets, endpoint locations, clobbers, and abstract/non-executable layout.
- Confirmed worker output emits `grammar_fragments_N.json` / `grammar_result_N.json` only, with no C artifacts.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/src/fragment_ir.lua` - fixed uint64 ABI literal generation, added numeric hi/lo lowering fields, completed data reloc enum coverage.
- `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua` - added ABI literal/numeric-field assertions.
- `experiments/lua_interpreter_vm/README.md` - updated SpongeJIT status/build/test docs to native-fragment-only.
- `experiments/lua_interpreter_vm/SPONJIT_FOUNDRY_SSA.md` - removed stale C bank/build references.
- `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` - removed stale C emission/build-pipeline references.

Also preserved/verified prior interrupted-worker changes across:
- `spongejit/src/stencil_to_fragment.lua`
- `spongejit/src/fragment_projection.lua`
- `spongejit/src/ssa.lua`
- `spongejit/src/ssa_atoms.lua`
- `spongejit/src/stencil_ir.lua`
- `spongejit/src/ssa_to_stencil.lua`
- `spongejit/src/worker_compile.lua`
- `spongejit/include/sponbank.h`
- SpongeJIT fragment tests and retirement test.

## Tests / Commands Run

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
# ok - real SponJIT fact + SSA invariants

luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua
# ok - SpongeJIT fragment IR validation

luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua
# ok - SpongeJIT fragment projection

luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua
# ok - SpongeJIT stencil to native fragment

luajit experiments/lua_interpreter_vm/tests/test_spongejit_retirement.lua
# ok - SpongeJIT legacy tile ABI retired from maintained source

(cd experiments/lua_interpreter_vm/spongejit && make test)
# all SpongeJIT tests passed
```

Worker smoke:

```sh
(cd experiments/lua_interpreter_vm/spongejit && \
  SPON_TMP="$tmp" MAX_FACT_COMBOS=8 WORKER_PROGRESS_SEQS=1 \
  luajit src/worker_compile.lua 1)
```

Result:
- produced `grammar_fragments_1.json`
- produced `grammar_result_1.json`
- did **not** produce `grammar_c_code_1.c`
- did **not** produce `grammar_holes_1.json`

Retirement grep:

```sh
rg -n "SponTile|SponHoleReloc|SPON_HOLE_|grammar_c_code|grammar_holes|spon_get_tile|spon_tile_|stencil_to_c|bench_execute_tile|bench_sponbank_puc|build_puc_bank_hack|build_puc_sponjit|fuse_stencils" experiments/lua_interpreter_vm -g '!SPONJIT_COPY_LINK_PATCH.md' -g '!**/test_spongejit_retirement.lua'
```

Result: no matches.

## Notes

Remaining intentional limitations:
- Fragment descriptors are still abstract/non-executable.
- Code offsets are valid only as explicit `abstract_zero`.
- No native assembler/linker exists yet.
- No maintained PUC executable integration exists yet.
- Payload/dependency-heavy fragments still reject loudly.
