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

### Approach C: Lalin-Style Region Source ABI

- **Core idea**: Make SpongeJIT stencils compile into Lalin-like typed regions with named continuations, then compose those regions through typed control protocols instead of linking opaque bytes.

- **Key changes**:
  - Introduce a SpongeJIT region schema that maps SSA values, facts, frame slots, memory effects, and exits into Lalin-style region signatures.
  - Replace or augment `stencil_to_c.lua` with a `stencil_to_region_source.lua` / `stencil_to_backcmd.lua` backend.
  - Each stencil becomes something like:
    - entry params: frame pointer, slot bindings, abstract facts, live values
    - continuations: `ok(...)`, `guard_exit(...)`, `residual_exit(...)`
    - explicit projection obligations on non-`ok` continuations
  - Bank metadata stores typed region templates, continuation protocols, fact transfer, deps, hole bindings, and projection recipes.
  - Runtime selection produces a composed region graph; composition happens by `emit`-style splicing rather than native branch relocation.
  - PUC runtime either invokes a Lalin/Cranelift compilation path for hot images or uses an ahead-of-time cache of composed common regions.

- **Tradeoff**: Optimizes for typed control, explicit continuation contracts, and reuse of Lalin’s region philosophy; sacrifices independence from Lalin and makes Tier 2 closer to a JIT compiler than a pure copy-patch linker.

- **Risk**: Dynamic Lua VM facts, payload leases, and fallback projection may not map cleanly into monomorphic Lalin regions without adding significant host/runtime ABI machinery.

- **Rough sketch**:
  - Define SpongeJIT-to-Lalin type mappings for frame slots, TValue views, facts, and exits.
  - Generate one typed region per stencil template.
  - Compose selected regions into a larger Lalin region with explicit continuations.
  - Compile/cache fused regions for i64-only traces first.
  - Use typed continuation signatures to force projection completeness at compile time.

---

### Comparison

- **Approach A** treats the region ABI as a semantic catalog first, with executable code generated later.
- **Approach B** treats the region ABI as a native binary contract, optimized for real byte-level Copy-Link-Patch.
- **Approach C** treats the region ABI as typed control source, aligning SpongeJIT with Lalin-style explicit regions and continuations.

## Critique Output — 2026-05-29 09:37:17

## Approach B: Native Fragment ABI with Continuation Relocations

| Dimension | Score | Assessment |
|---|---:|---|
| **Coupling** | **4/5 high** | Strongly couples SpongeJIT IR, codegen, bank metadata, runtime materialization, relocation format, ISA, calling convention, and executable-memory policy. It removes dependence on C compiler-shaped functions, but replaces it with a tighter native ABI contract. |
| **Cohesion** | **4/5 good, with danger** | As a Tier 2 backend, the concept is cohesive: native fragments, explicit labels, continuation exits, clobbers, and relocations all serve Copy-Link-Patch directly. The danger is mixing semantic region facts/projection data with machine-layout metadata too early. |
| **Migration cost** | **5/5 very high** | This is a deep replacement of `stencil_to_c.lua`, `build_bank.lua`, `sponbank.h`, generated artifacts, relocation handling, and `puc/sponjit_runtime.c`. Existing C-function tiles cannot simply become linkable fragments. |
| **SpongeJIT philosophy fit** | **5/5** | This is the most literal realization of Copy-Link-Patch: copy native fragments, link continuations, patch data/control holes, enter once. It directly attacks the current per-tile mmap/function-call boundary. |
| **Lalin philosophy fit** | **3/5 mixed** | Explicit continuations and typed control edges fit Lalin’s philosophy. Raw physical endpoint contracts, ISA-specific relocs, and low-level fragment ABI are less Lalin-like than typed region composition. |
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

Approach C, Lalin-Style Region Source ABI, would map SpongeJIT stencils into typed regions with named continuations and compose them through a Lalin-like region protocol. This aligns with typed control and explicit continuation contracts, but makes Tier 2 closer to a JIT/compiler integration path than a pure copy-link-patch linker. The workflow identified risk around mapping dynamic Lua VM facts, payload leases, and fallback projection into monomorphic Lalin regions without substantial host/runtime ABI machinery.

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

## Scout Output — 2026-05-30 19:00:27

## Files Retrieved

1. `experiments/lua_interpreter_vm/spongejit/src/fragment_ir.lua` (lines 1-489) — Current native-fragment schema, enums, validation, ABI lowering.
2. `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua` (lines 1-197) — Current Stencil IR → abstract fragment descriptor lowering.
3. `experiments/lua_interpreter_vm/spongejit/src/fragment_projection.lua` (lines 1-45) — Current projection recipe helpers.
4. `experiments/lua_interpreter_vm/spongejit/src/fragment_abi_x64.lua` (lines 1-20) — Current x86-64 SysV fragment ABI descriptor.
5. `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` (lines 1-255) — Public C ABI declarations for fragments.
6. `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 1-108) — Worker artifact generation path.
7. `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` (lines 1-162) — Public SSA compile facade and serialized active node specs.
8. `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua` (lines 1-76) — Reopening serialized SSA node specs.
9. `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` (lines 1-424) — Typed SSA graph, memory/effect/exit/value metadata.
10. `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` (lines 1-268) — SSA → Stencil IR lowering and hole creation.
11. `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` (lines 1-179) — Current semantic Stencil IR and validation.
12. `experiments/lua_interpreter_vm/spongejit/src/stencil_normalize.lua` (lines 1-164) — Canonical forms/hashes/projection summary.
13. `experiments/lua_interpreter_vm/spongejit/src/ssa_contract.lua` (lines 1-98) — Fact-transfer contracts.
14. `experiments/lua_interpreter_vm/spongejit/src/fact_signature.lua` (lines 1-221) — 64-bit fact signature ABI.
15. `experiments/lua_interpreter_vm/spongejit/src/facts.lua` (lines 1-303) — Fact lattice, deps, implications, contradictions.
16. `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` (lines 1-322) — PUC opcode/facts → semantic SSA lowering.
17. `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` (lines 1-242) — Current SSA optimization passes.
18. `experiments/lua_interpreter_vm/spongejit/src/ssa_validate.lua` (lines 1-44) — SSA invariant checks.
19. `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` (lines 1-354) — Curated fact bundle generation.
20. `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` (lines 1-482) — Grammar enumeration and L0 generation.
21. `experiments/lua_interpreter_vm/spongejit/src/enumerate.lua` (lines 1-594) — Corpus/window form enumeration.
22. `experiments/lua_interpreter_vm/spongejit/foundry.lua` (lines 1-270) — Current foundry entry point.
23. `experiments/lua_interpreter_vm/spongejit/Makefile` (lines 1-24) — SpongeJIT test-only build target.
24. `experiments/lua_interpreter_vm/spongejit/puc/README.md` (lines 1-10) — PUC integration status.
25. `experiments/lua_interpreter_vm/spongejit/bench/README.md` (lines 1-42) — Planned measurement harness.
26. `experiments/lua_interpreter_vm/README.md` (lines 1-132) — Current VM/SpongeJIT status summary.
27. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-87) — VM contract and SponJIT gate.
28. `experiments/lua_interpreter_vm/src/contract.lua` (lines 1-19) — Machine-readable VM gate.
29. `experiments/lua_interpreter_vm/src/vm_loop.lua` (lines 1-178) — Lalin VM loop, no SpongeJIT integration.
30. `experiments/lua_interpreter_vm/src/products.lua` (lines 1-131) — Lalin VM product layouts.
31. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-230) — VM dispatch region structure.
32. `experiments/lua_interpreter_vm/src/regions_native.lua` (lines 1-83) — Explicit native ABI boundary.
33. `experiments/lua_interpreter_vm/src/jit/stencil_codegen.lua` (lines 1-51) — Older small StateOp stencil generator shim.
34. `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 1-151) — SSA/fact/contract tests.
35. `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua` (lines 1-133) — Fragment IR validation tests.
36. `experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua` (lines 1-41) — Projection tests.
37. `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua` (lines 1-129) — End-to-end fragment lowering tests.
38. `experiments/lua_interpreter_vm/tests/test_spongejit_retirement.lua` (lines 1-65) — Legacy tile-token retirement check.
39. `experiments/lua_interpreter_vm/tests/test_vm_abi_contract.lua` (lines 1-64) — VM ABI gate test.
40. `experiments/lua_interpreter_vm/tests/test_vm_smoke.lua` (lines 1-70) — VM module smoke test with SponJIT gate assertion.
41. `experiments/lua_interpreter_vm/tests/test_sponjit_shadow.lua` (lines 1-169) — Older non-executing shadow simulator tests.
42. `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md` (lines 1-899) — Native Fragment ABI specification.
43. `experiments/lua_interpreter_vm/SPONJIT_FOUNDRY_SSA.md` (lines 1-130, 630-719) — Foundry/SSA design/status notes.
44. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 640-710) — Current native-fragment architecture notes.
45. `experiments/lua_interpreter_vm/SPONJIT_RUNTIME_DESIGN.md` (lines 1-80) — Runtime design document, partly stale.
46. `experiments/lua_interpreter_vm/tools/sponjit_shadow/README.md` (lines 1-202) — Older shadow simulator docs.
47. `experiments/lua_interpreter_vm/tools/jit_harness/candidate_emit.lua` (lines 1-140) — Older Lalin/GCC stencil kernel emitter.
48. `experiments/lua_interpreter_vm/tools/jit_harness/candidate_compile.lua` (lines 1-160) — Older object compilation path.
49. `experiments/lua_interpreter_vm/tools/jit_harness/lowering_plan.lua` (lines 1-160) — Older candidate/fact lowering planner.
50. `experiments/lua_interpreter_vm/benchmarks/bench_stencil_vs_vm.lua` (lines 1-120) — Older C monolithic stencil vs VM benchmark.

## Key Code

### Fragment IR schema and validation

```lua
M.PHYSICAL_ABI = { x86_64_sysv_spon_v1 = true }
M.PHYSICAL_ABI_ID = { x86_64_sysv_spon_v1 = 1 }

M.DATA_RELOC_KIND = {
  slot = true, slot_store = true, imm = true, const = true, bool = true,
  shape_offset = true, shape_id = true, metatable_offset = true,
  field_offset = true, array_base_offset = true, call_target = true, barrier = true,
}

M.CONTROL_RELOC_KIND = {
  fallthrough = true,
  guard_fail = true,
  residual = true,
  boundary = true,
  projection_stub = true,
}

M.FRAGMENT_FLAG = { ABSTRACT = 1, NATIVE = 2, PUC_PATCHABLE = 4 }
```

Validation requires a physical ABI, abstract layout for non-executable fragments, clobbers, one entry endpoint, at least one ok endpoint, fact transfer, explicit projection ranges for non-success endpoints, separated data/control relocs, and rejects dependencies unless allowed.

```lua
if #(f.clobbers or {}) == 0 then err(errors, "fragment must declare clobbers") end
...
if entry_count ~= 1 then err(errors, "fragment requires exactly one entry endpoint") end
if ok_count < 1 then err(errors, "fragment requires at least one ok endpoint") end
...
if PAYLOAD_ROLE[role] and not f.allow_payload_roles then
  err(errors, "unsupported payload data reloc role: " .. tostring(role))
end
...
if #(f.dependencies or {}) > 0 and not f.allow_dependencies then
  err(errors, "unsupported dependencies in native fragment descriptor")
end
```

### Current abstract fragment lowering surface

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
  I64BinOp = true,
  I64UnaryOp = true,
  CmpI64 = true,
  ExitBoundary = true,
  ExitResidual = true,
  ExitUnlowered = true,
}

local SUPPORTED_DATA_ROLE = {
  slot = true,
  slot_store = true,
  imm = true,
  const = true,
  bool = true,
}
```

Fragments are emitted as abstract/non-executable:

```lua
layout = {
  mode = "abstract_fragment",
  executable = false,
  code_offsets = "abstract_zero",
  reason = "metadata-only fragment descriptor; no native assembler offsets emitted",
}
```

### Projection recipes

```lua
function M.synced_frame(exit, source)
  return {
    kind = "SYNCED_FRAME",
    reason = exit and exit.reason or "exit",
    pc = exit and exit.pc or source or 0,
    entries = {},
  }
end

function M.for_exit(st, n, config)
  return M.synced_frame(n and n.exit, n and n.source)
end
```

### Public C fragment ABI

```c
typedef uint32_t SponFragmentId;

typedef struct {
  SponFragmentId fragment_id;
  uint32_t pc_start;
  uint32_t pc_end;
} SponFragmentChoice;

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

Declared fragment selector/accessor APIs exist in `sponbank.h`; grep found no implementation in the current tree.

### Stencil IR no longer accepts `exit`/`fail` as data holes

```lua
assert(t.role_kind ~= "exit" and t.role_kind ~= "fail",
       "exit/fail are control endpoints, not data holes")
```

Stencil validation also reports holes with `role_kind == "exit"` or `"fail"` as errors.

### SSA metadata preserved for fragment work

`active_node_specs()` serializes node source, memory tokens, exits, and residencies:

```lua
out[#out + 1] = {
  op = n.op,
  codegen_op = n.codegen_op,
  args = n.args or {},
  effect = n.effect,
  guard_fact = n.guard and n.guard.fact,
  deps = n.deps or {},
  inputs = n.inputs or {},
  outputs = n.outputs or {},
  input_types = input_types,
  input_residencies = input_residencies,
  output_types = output_types,
  output_residencies = output_residencies,
  source = n.source,
  mem_in = copy_map(n.mem_in),
  mem_out = copy_map(n.mem_out),
  exit = n.exit and copy_map(n.exit) or nil,
}
```

### Worker output path

```lua
local frag_result = StencilToFragment.generate(r, { facts = facts })
...
Util.write_json(tmp("grammar_fragments_" .. ci .. ".json"), { fragments = fragments_in_order })
Util.write_json(tmp("grammar_result_" .. ci .. ".json"), {
  forms = forms_in_order,
  compiles = lc,
  ok = lok,
  ssa_ok = lssa_ok,
  rejected = lrejected,
})
```

No `grammar_c_code_N.c` or `grammar_holes_N.json` writes remain in `worker_compile.lua`.

### VM gate

```lua
return {
    vm_abi_version = 2,
    native_abi_version = 2,
    validator_contract_version = 2,
    sponjit_allowed = false,
    required_gates = {
        "lua55_tm_order",
        "bytecode_validator_complete",
        ...
    },
}
```

`VM_CONTRACT.md` states SponJIT integration is not allowed until validator/frame/native/error/coroutine/allocator gates are tested.

## Relationships

- Current SpongeJIT metadata path in code:

```text
opcode sequence + fact bundle
→ ssa_lift.lua / ssa_ir.lua
→ ssa_opt.lua
→ ssa_to_stencil.lua / stencil_ir.lua
→ stencil_normalize.lua
→ stencil_to_fragment.lua
→ fragment_ir.lua ABI-lowered metadata
→ worker_compile.lua JSON artifacts
```

- `StencilToFragment.generate()` consumes the full `SSA.compile()` result, not only a raw stencil:
  - uses `ssa_result.stencil`
  - computes fact transfer via `ssa_contract.lua`
  - copies `active_node_specs`, `stencil_ops`, `slotmaps`, `source_ops`
  - emits endpoints, projections, data relocs, control relocs, clobbers, and ABI-lowered tables.

- `ssa_to_stencil.lua` still creates data holes for payload-capable roles (`shape_offset`, `shape_id`, `metatable_offset`, `field_offset`, `array_base_offset`, `call_target`, `barrier`), but `stencil_to_fragment.lua` currently rejects all data roles except `slot`, `slot_store`, `imm`, `const`, and `bool`.

- `fragment_ir.lua` keeps both string-level descriptor metadata and an `abi` table with numeric C-ABI-shaped enum fields.

- `sponbank.h` declares native fragment ABI structs and selectors, but the current tree has no generated `libsponbank.c`, no `build_bank.lua`, no `build_stencils.sh`, and no C implementation of the declared functions.

- Lalin interpreter VM integration is separate:
  - `src/vm_loop.lua` dispatches bytecode through Lalin regions.
  - `src/contract.lua` has `sponjit_allowed = false`.
  - `spongejit/puc/README.md` says no maintained executable PUC integration exists until a native fragment linker exists.
  - `experiments/lua_interpreter_vm/README.md` states SpongeJIT is not the execution engine for `src/vm_loop.lua`.

- Older non-current harnesses remain outside the maintained `spongejit/` path:
  - `tools/sponjit_shadow/` is a non-executing economic simulator.
  - `tools/jit_harness/` can emit/compile Lalin or GCC stencil kernels.
  - `benchmarks/bench_stencil_vs_vm.lua` still contains a standalone C “stencil” benchmark.

## Observations

- Current `experiments/lua_interpreter_vm/spongejit/` contains no `.c` files and no `.sh` files.
- Current `experiments/lua_interpreter_vm/spongejit/runtime/` is empty.
- Current `experiments/lua_interpreter_vm/spongejit/puc/` contains only `README.md`.
- Current `experiments/lua_interpreter_vm/spongejit/build/` and `build/cp_lib/` do not exist.
- Grep under maintained SpongeJIT source/tests for stale tile tokens (`SponTile`, `SponHoleReloc`, `SPON_HOLE_`, `stencil_to_c`, `grammar_c_code`, `grammar_holes`, etc.) returned no matches excluding `test_spongejit_retirement.lua`.
- Grep over all `experiments/lua_interpreter_vm` found old tile names only in `SPONJIT_COPY_LINK_PATCH.md` and the retirement test.
- `sponbank.h` includes `SponLocationDesc`, but no `spon_fragment_locations()` accessor is declared.
- Lua ABI-lowered projections include `pc` and `reason`; C `SponProjectionEntry` contains only `kind`, `value_type`, `logical_slot`, and `value_index`.
- Lua ABI-lowered fragments carry `locations` and `clobbers` arrays; C `SponFragmentDesc` does not include location/clobber start/count fields.
- `Grammar.generate_all(1)` currently returns 25 handler-equivalence sequences.
- `Grammar.generate_all(2)` returns 750.
- `Grammar.generate_all(3)` returns 18,875.
- `Grammar.generate_all(4)` returns 472,000.
- `Grammar.generate_l0_all()` returns 85 single-op L0 entries.
- `foundry.lua` comments say it uses native-fragment metadata directly, but its `lower_forms()` currently builds template summaries from `stencil_forms.forms`; it does not call `StencilToFragment`.
- `grammar_enum.lua` forms include stencil form/op/slotmap/contract data; `enumerate.lua` corpus forms include `active_node_specs`, deps, and projection summaries.
- `worker_compile.lua` consumes pre-split `grammar_chunk_N.json`; grep found no current chunk-splitting build script under `spongejit/`.
- `SPONJIT_COPY_LINK_PATCH.md` status says “draft specification; not implemented.”
- `SPONJIT_FOUNDRY_SSA.md` top status still says “semantic SSA → hole-parametric Stencil IR → C stencil → object/relocation mining,” while later lines state the current boundary is “semantic SSA → Stencil IR shape → abstract native-fragment descriptor.”
- `SPONJIT_RUNTIME_DESIGN.md` top status still references an experimental PUC runtime prototype and C bank path; current `spongejit/puc/README.md` says executable PUC integration was removed.
- `experiments/lua_interpreter_vm/README.md` explicitly warns that the interpreter VM and SpongeJIT are not one integrated JIT system today.
- Filtered git status for SponJIT files showed no modified SpongeJIT files; `experiments/lua_interpreter_vm/src/init.lua` is modified and now imports `regions_semantic` and `regions_lower`.

Commands run and results:

```text
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
→ ok - real SponJIT fact + SSA invariants

luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua
→ ok - SpongeJIT fragment IR validation

luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua
→ ok - SpongeJIT fragment projection

luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua
→ ok - SpongeJIT stencil to native fragment

luajit experiments/lua_interpreter_vm/tests/test_spongejit_retirement.lua
→ ok - SpongeJIT legacy tile ABI retired from maintained source

(cd experiments/lua_interpreter_vm/spongejit && make test)
→ all SpongeJIT tests passed
```

Worker smoke with a temporary `grammar_chunk_1.json` produced:

```text
grammar_chunk_1.json
grammar_fragments_1.json
grammar_result_1.json
```

and reported:

```text
compiles=11
ssa_ok=11
fragments=6
rejected=5
forms=6
```

No `grammar_c_code_1.c` or `grammar_holes_1.json` was produced.

## Knowledge-builder Output — 2026-05-30 19:04:41

### What Matters Most for This Problem

- **Truthfulness of the ABI boundary**: Lua fragment metadata, JSON artifacts, `sponbank.h`, docs, and any future generated bank must describe the same thing without lossy gaps.
- **Abstract vs executable phase separation**: current fragments are validated metadata, not native code. That distinction is now central.
- **Projection and resume correctness**: current `SYNCED_FRAME` projection is safe but intentionally does not unlock the main Copy-Link-Patch optimization.
- **Physical endpoint contracts**: endpoint locations, clobbers, and value residency are now the hard correctness surface.
- **Selector identity and fact transfer**: pattern keys, fact signatures, slot remapping, and source opcode identity are not yet fully aligned.
- **Integration gates**: SpongeJIT is currently separate from both PUC execution and the Lalin Lua VM; the VM contract explicitly forbids SponJIT integration for now.
- **Sequencing after the hard-yank**: the old C-function path is gone, so the design space is cleaner but has no maintained executable baseline.

---

### Non-Obvious Observations

#### The hard-yank changed the problem shape

- The original architectural decision kept Tier 1 C-function tiles as fallback and baseline, but the executed work hard-yanked them. That is a major shift: future work no longer has a maintained selector/materializer/runtime oracle inside SpongeJIT.

- The old risk was “someone might mistake callable C stencils for linkable fragments.” That risk is mostly gone. The new risk is subtler: **abstract fragment metadata may be mistaken for an executable native-fragment backend**.

- Current SpongeJIT now has a relatively solid **metadata backend**, not a runnable Copy-Link-Patch backend. Tests prove schema invariants, retirement of tile names, projection presence, and i64 lowering shape — not native execution, layout, patching, or resume behavior.

- The retirement test makes `SponTile`, `SponHoleReloc`, `SPON_HOLE_*`, `stencil_to_c`, and old C artifacts semantically toxic under maintained SpongeJIT paths. That is valuable: it prevents accidental dual-ABI drift.

- But the absence of a runnable old path means performance comparisons against “per-tile mmap/function-call overhead” are now historical, not reproducible from the maintained tree.

#### The current ABI is not yet self-consistent across layers

- Lua fragment descriptors carry `locations` and `clobbers`; `sponbank.h` defines `SponLocationDesc`, but exposes no `spon_fragment_locations()` accessor and no clobber descriptor/accessor. A C bank generated strictly from the header would lose key Approach B metadata.

- Lua projections carry `pc` and `reason`; C `SponProjectionEntry` carries only kind/value/slot/value_index. That loses resume semantics at exactly the boundary where projection correctness matters.

- `SponEndpointDesc` has `location_start`/`n_locations`, but without a public location array accessor those fields cannot be interpreted by C users.

- Lua ABI-lowered metadata uses 1-based starts/indices (`endpoint_start = 1`, `projection_start = 1`, endpoint indices into Lua arrays). The C ABI does not state index origin. This is an off-by-one hazard waiting at the generated-bank boundary.

- `fragment_ir.lua` emits both string-level descriptors and numeric ABI-lowered tables. That dual form is useful for debugging, but it creates a hidden invariant: every field with semantics must survive the string → numeric lowering. Currently some do not.

- `reloc_kind` is still `0` in ABI-lowered data/control relocs because fragments are abstract. That is fine for metadata, but any executable interpretation before real relocation encoding exists would be false confidence.

#### Endpoint contracts currently satisfy the validator more than the backend philosophy

- All endpoints currently share the same abstract locations: `ctx` in `rdi`, synced frame in `ctx.stack`, plus an “abstract endpoint contract” immediate. This is a context ABI, not a value-flow ABI.

- Because entry, ok, and exit endpoints all look physically similar, the metadata cannot yet express “this fragment produces I64 in register X consumed by the next fragment.” That blocks the actual register-preserving Copy-Link-Patch value proposition.

- Fragment clobbers currently come from the x64 ABI descriptor and conservatively include caller-saved GPRs and flags. Safe, but it makes cross-fragment register liveness effectively impossible to prove.

- SSA value residency is serialized, but `"gpr0"` is not mapped to concrete x64 registers or endpoint locations. Residency is preserved as metadata, not enforced as a physical contract.

- Current descriptors declare an `ok` endpoint but do not emit a success/fallthrough control relocation. The success edge is therefore implicit. The spec warns against implicit fallthrough unless explicitly marked; current metadata has not closed that loop.

#### Projection is safe but deliberately non-optimizing

- Every current non-success endpoint uses `SYNCED_FRAME`. That preserves the old safety invariant: frame state must already be interpreter-visible at exits.

- This means store/load seam deletion remains semantically disallowed. The central Copy-Link-Patch benefit — locally breaking frame synchronization and repairing it via projection — is not exercised yet.

- The presence of projection objects should not be overread. They currently certify “we did not desynchronize frame state,” not “we can reconstruct unsynced values.”

- `BOX_I64` exists in the projection enum, but normal lowering fuses `BoxI64 + FrameStore` into `StoreI64Slot`; there is not yet a shared, exercised projection/codegen contract for boxing virtual i64 values.

- Slotmaps still describe operand occurrences, not liveness. `SYNCED_FRAME` avoids needing liveness precision; richer projections will not.

#### Fact and selector identity have hidden coupling gaps

- `StencilToFragment.generate(r, { facts = facts })` depends on callers passing the original facts. `SSA.compile()` returns `factset`, not `facts`, and `ssa_contract.lua` falls back to `{}` if facts are absent. Direct calls can silently produce weaker selector signatures.

- Fragment `pattern_key` is currently derived from `ssa_result.stencil_hash`. Worker dedupe also includes opcode signature and fact-transfer contract, but `SponFragmentDesc` exposes only one `pattern_key`. Selection over bytecode may need source-op identity that the fragment descriptor does not itself preserve numerically.

- Contract exits and stencil exits are both present, but there is no strong cross-check that `contract.exits`, fragment endpoints, control relocs, and projection ranges describe the same exit set.

- Payload-capable data roles exist in Stencil IR and C enums, but fragment lowering rejects them. That is a safety win: payload/dependency holes cannot accidentally materialize with dummy values.

- The safe first surface is therefore narrower than “Tier 1 floor coverage.” Many L0/table/call/barrier cases remain intentionally outside the fragment backend.

#### The pipeline is split in a way tests do not expose

- `worker_compile.lua` emits `grammar_fragments_N.json`, but there is no current chunk-splitting build script, fragment bank generator, generated C bank, or C implementation of the `sponbank.h` selectors/accessors.

- `foundry.lua` claims it uses native-fragment metadata directly, but `lower_forms()` builds template summaries from stencil form data and does not call `StencilToFragment`. The worker path and foundry path are not the same backend path.

- `sponbank.h` declares a fairly complete selector/accessor API, but no implementation exists. The header is currently a promise/spec surface, not a linkable ABI.

- Current tests validate Lua descriptors, not C ABI consumption. The most important lossy boundaries — JSON → generated arrays → C accessors → runtime linker — are untested because they do not exist yet.

#### The Lalin VM contract changes the integration constraints

- The current Lalin Lua VM explicitly has `sponjit_allowed = false`. SponJIT integration is gated on bytecode validation, frame/cache rules, native ABI, allocator, errors, and coroutine/yield semantics.

- PUC runtime integration was removed, but much SpongeJIT vocabulary still comes from PUC-style opcode windows and `SponExecCtx` with stack/constants/scratch/exit fields.

- `VM_CONTRACT.md` says PUC layouts and control behavior must not become implementation dependencies. That puts pressure on any future runtime ABI that still resembles the removed PUC runtime.

- `SponExecCtx.exit_hole` remains even though `exit`/`fail` holes were retired as data holes. This is a small but telling legacy seam: runtime exit state still remembers the old model.

- Lalin already has explicit typed native-boundary regions and continuation protocols. That makes the physical native fragment ABI tension sharper: SpongeJIT’s fragment ABI must either remain clearly separate or eventually align with the VM’s typed control/data contracts. The current code does neither yet; it is isolated.

#### Current solid pieces narrow future freedom

- The clean removal of C-function stencils means future designs should not rely on “temporarily” resurrecting C tiles without knowingly violating the new invariant.

- The validator now enforces separated data/control relocs, non-empty endpoint locations, clobbers, projection ranges, abstract offsets, and payload rejection. These are now real constraints, not just documentation.

- Because the current fragment backend is abstract-only, executable work must preserve the abstract/native distinction. Any native fragment using `abstract_zero` offsets would violate the most important current safety boundary.

- The i64-only fragment surface is a genuine low-risk validation surface, but it is not a floor compiler. Treating it as Tier 1 coverage would overstate the current backend.

---

### Knowledge Gaps

- Whether `sponbank.h` is intended to be the final public ABI or only a placeholder, given missing location/clobber/projection-resume exposure.

- What the canonical selector identity should be: source opcode pattern, stencil hash, fragment id, contract tuple, or some combination.

- How `SponExecCtx` is supposed to relate to the Lalin VM’s `Value`, `Frame`, `LuaThread`, allocator, error, and yield contracts.

- Whether future executable fragments are expected to target a custom x64 emitter only, or interact with Lalin’s existing native backend at any boundary.

- How runtime facts will be observed now that maintained PUC execution integration is gone.

- How large `grammar_fragments_N.json` becomes at arity 4 under the current rejection rules, and whether the metadata budget remains realistic.

## Approach-proposer Output — 2026-05-30 19:05:16

### Approach A: Fragment ABI as the Product

- **Core idea**: Make the native fragment ABI the single source of truth, then grow from abstract descriptors into executable x64 copy/link/patch images.

- **Key changes**:
  - Treat `fragment_ir.lua` + `sponbank.h` as one shared ABI contract that must be lossless.
  - Close current ABI gaps: locations, clobbers, projection resume data, index origins, fact signatures, selector identity.
  - Add a real fragment bank generator and native linker/runtime around `SponFragmentDesc`.
  - Keep SpongeJIT isolated from Lalin VM integration until VM gates allow it.

- **Tradeoff**: Optimizes for literal Copy-Link-Patch validation and clear native-fragment ownership; sacrifices portability and delays Lalin integration.

- **Risk**: The ABI may harden too early around x64/SponExecCtx assumptions before projection, runtime facts, and VM integration are fully understood.

- **Rough sketch**:
  - Declare the Lua fragment schema authoritative and generate/validate C ABI-shaped metadata from it.
  - Build an executable/non-executable phase split: abstract descriptors must never be linked.
  - Add an x64 fragment emitter with explicit endpoint labels and control relocations.
  - Build a standalone fragment linker/test harness for i64/guard spans.
  - Only later connect to PUC-like or Lalin runtime entry points.

---

### Approach B: Lalin Region Assimilation

- **Core idea**: Stop treating SpongeJIT fragments as a separate executable ABI and reinterpret them as Lalin typed regions with explicit continuation protocols.

- **Key changes**:
  - Map SpongeJIT SSA/stencil fragments into Lalin region signatures.
  - Put truth in Lalin’s typed control/data contracts rather than `sponbank.h`.
  - Represent exits as typed continuations: `ok`, `guard_exit`, `residual_exit`, `boundary_exit`.
  - Let Lalin/Cranelift own physical ABI, register allocation, object emission, and native execution.
  - Keep SpongeJIT as a specialization/planning frontend, not an independent native backend.

- **Tradeoff**: Optimizes for typed integration, projection checking, and reuse of the existing compiler stack; sacrifices the pure “copy prebuilt native bytes and patch branches” model.

- **Risk**: The project may drift from Copy-Link-Patch into “just another JIT compiler,” losing the original low-latency offline-fragment thesis.

- **Rough sketch**:
  - Define a SpongeJIT-fragment-to-Lalin-region mapping.
  - Convert endpoint locations into typed continuation parameters.
  - Convert projection recipes into required continuation arguments.
  - Use Lalin object/JIT emission for executable fused regions.
  - Enable VM integration only through existing `VM_CONTRACT` gates.

---

### Approach C: Semantic Planner First, Execution Deferred

- **Core idea**: Treat the current abstract fragment backend as a semantic linking/projection verifier first, and postpone native execution until the optimizer and contracts prove real Tier 2 value.

- **Key changes**:
  - Put truth in SSA/fragment semantic contracts, not native layout.
  - Build a region planner that links abstract fragments, tracks facts, endpoints, deps, and projections.
  - Add an abstract execution/shadow model to validate resume behavior and seam-removal legality.
  - Use measurements over real opcode/fact corpora to decide which executable backend is worth building later.
  - Keep `sponbank.h` as provisional until planner results determine the minimal needed runtime ABI.

- **Tradeoff**: Optimizes for correctness, projection discipline, and avoiding premature native ABI commitments; sacrifices near-term executable Copy-Link-Patch benchmarks.

- **Risk**: It may become a metadata/verifier project with no performance proof, especially now that the old C-function baseline is gone.

- **Rough sketch**:
  - Make abstract fragment linking explicit: success edges, guard exits, residual exits, boundary exits.
  - Add projection completeness checks beyond `SYNCED_FRAME`.
  - Model store/load seam removal only when projections can reconstruct state.
  - Run corpus-scale analysis over accepted/rejected spans and projected savings.
  - Choose native x64 or Lalin execution only after the semantic planner stabilizes.

---

### Comparison

- Pick **Approach A** if the goal is to prove real byte-level Copy-Link-Patch as originally imagined.
- Pick **Approach B** if the goal is coherent Lalin integration and typed execution safety.
- Pick **Approach C** if the main uncertainty is still semantic correctness and whether Tier 2 has enough optimization value to justify a native backend.

## Critique Output — 2026-05-30 19:06:49

### Approach A: Fragment ABI as the Product

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Tightly binds `fragment_ir.lua`, `sponbank.h`, x64 emission, linker/runtime, relocation formats, and likely `SponExecCtx` assumptions. Keeps Lalin isolated, but hardens a native ABI boundary. |
| **Cohesion** | 4/5 | Very coherent for literal Copy-Link-Patch: one fragment ABI, explicit endpoints, relocs, projection, linker. |
| **Migration cost** | 4/5 | Requires closing ABI gaps, adding bank generator, native emitter, linker, executable tests, and runtime harness. No old C-function baseline remains. |
| **Philosophy fit** | 4/5 | Strong SpongeJIT fit: copy bytes, link continuations, patch holes. Weaker Lalin fit because it owns a separate physical ABI instead of typed region composition. |
| **Risk** | 4/5 | High correctness risk around physical endpoints, projection/resume, fact identity, and premature x64/`SponExecCtx` hardening. |
| **Testability** | 4/5 | Good if abstract/non-executable vs native/executable phases stay explicit. Can build standalone i64/guard linker experiments before VM integration. |

**Verdict**: Yes with caveats
**Key concern**: Do not freeze the current incomplete ABI. Locations, clobbers, projection resume data, selector identity, and index origins must be lossless before executable fragments depend on them.

---

### Approach B: Lalin Region Assimilation

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 4/5 | Strongly couples SpongeJIT planning to Lalin region types, compiler pipeline, VM gates, and Cranelift/backend semantics. |
| **Cohesion** | 3/5 | Coherent if SpongeJIT becomes a specialization frontend, but less cohesive as Copy-Link-Patch because the byte-copy/link/patch thesis largely disappears. |
| **Migration cost** | 5/5 | Requires replacing the current fragment ABI direction with a SpongeJIT→Lalin region mapping and waiting on VM integration gates. |
| **Philosophy fit** | 3/5 | Excellent Lalin fit: typed continuations, explicit control protocols, backend-owned ABI. Mixed SpongeJIT fit: it risks becoming “just another JIT compiler.” |
| **Risk** | 4/5 | Lowers native ABI correctness risk, but raises product/architecture risk: dynamic Lua facts, projection, payload leases, and fallback semantics may not map cleanly. |
| **Testability** | 3/5 | Mapping/projection can be tested incrementally, but useful execution experiments depend on broader Lalin/VM integration readiness. |

**Verdict**: Significant concerns
**Key concern**: Preserve the Copy-Link-Patch thesis. If Lalin owns physical ABI and emission, SpongeJIT may lose the thing it was supposed to prove.

---

### Approach C: Semantic Planner First, Execution Deferred

| Dimension | Score (1-5) | Rationale |
|-----------|-------------|-----------|
| **Coupling** | 2/5 | Keeps native, Lalin, and runtime boundaries loose while semantic contracts stabilize. Lowest risk of binding unrelated layers prematurely. |
| **Cohesion** | 4/5 | Cohesive around current reality: abstract fragments, endpoint/projection validation, fact/dependency tracking, and seam-legality analysis. |
| **Migration cost** | 2/5 | Builds on existing abstract fragment metadata and tests. Avoids immediate assembler/linker/runtime work. |
| **Philosophy fit** | 4/5 | Fits Lalin’s explicit-contract philosophy and current SpongeJIT metadata-first state, though it delays literal byte-level Copy-Link-Patch. |
| **Risk** | 3/5 | Lower correctness risk, but higher strategic risk: it can become a verifier project with no performance proof. |
| **Testability** | 5/5 | Best immediate experiment surface: abstract linking, projection completeness, fact flow, rejection rates, corpus-scale opportunity analysis. |

**Verdict**: Yes with caveats
**Key concern**: Experiments must be decision-driving. If it only accumulates metadata without proving seam value or projection feasibility, it stalls Tier 2.

---

### Summary

- **Recommended**: **Approach C — Semantic Planner First**. Given the current post-hard-yank state, the largest danger is hardening the wrong ABI before projection, endpoint, selector, and runtime facts are understood. C gives the most useful near-term correctness experiments with the least boundary debt.
- **Dark horse**: **Approach A — Fragment ABI as the Product**. It has the highest upside if the goal is true byte-level Copy-Link-Patch, but only after the ABI is made lossless and executable/non-executable phases stay strict.
- **Avoid**: **Approach B — Lalin Region Assimilation**, unless the project goal shifts from Copy-Link-Patch validation to Lalin-native JIT integration.

## Documenter Output — 2026-05-30 19:10:38

# SponJIT Tier 2 Semantic Fragment Planner Specification

**Target file:** `experiments/lua_interpreter_vm/SPONJIT_TIER2_PLANNER_SPEC.md`
**Workflow:** `wf-sponjit-copy-link-patch`
**Approved direction:** Tier 2 Semantic Fragment Planner first, before executable native x64 Copy-Link-Patch.

---

## Goal

Build a Tier 2 SponJIT semantic fragment planner that links and validates abstract native-fragment descriptors, tracks facts/endpoints/dependencies/projections, and proves projection and seam-removal legality before committing to executable x64 copy-link-patch code generation or runtime integration.

---

## Problem Statement

SponJIT has moved past the old C-function tile backend. The current maintained path produces validated **abstract native-fragment metadata**, not executable code. This is a cleaner foundation for Copy-Link-Patch because it removes the misleading old assumption that callable C stencils were already linkable fragments.

However, the new risk is hardening the wrong executable ABI too early. Current fragment descriptors still have unresolved gaps around endpoint contracts, selector identity, projection resume data, index origins, fact payloads, and runtime fact observation. Current projections are safe but non-optimizing: `SYNCED_FRAME` preserves the old invariant that frame state is already interpreter-visible at exits. That does not yet prove the central Tier 2 optimization: locally removing redundant frame stores/loads and reconstructing state at exits.

The approved next step is therefore **not** an x64 assembler, native linker, PUC runtime, or Lalin VM integration. The next step is a semantic planner that operates on abstract fragments and answers whether fragment linking, fact flow, projection, and seam-removal legality are correct and valuable enough to justify the later executable backend.

---

## Current State

### Maintained SpongeJIT pipeline

The current maintained metadata path is:

```text
opcode sequence + fact bundle
→ ssa_lift.lua / ssa_ir.lua
→ ssa_opt.lua
→ ssa_to_stencil.lua / stencil_ir.lua
→ stencil_normalize.lua
→ stencil_to_fragment.lua
→ fragment_ir.lua ABI-lowered metadata
→ worker_compile.lua JSON artifacts
```

Important files:

- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_to_fragment.lua`
- `experiments/lua_interpreter_vm/spongejit/src/fragment_ir.lua`
- `experiments/lua_interpreter_vm/spongejit/src/fragment_projection.lua`
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua`

`worker_compile.lua` now emits:

- `grammar_fragments_N.json`
- `grammar_result_N.json`

It no longer emits:

- `grammar_c_code_N.c`
- `grammar_holes_N.json`

The old C-function stencil path was retired from maintained SpongeJIT source.

### SSA metadata preservation

`ssa.lua` now serializes metadata needed for fragment planning:

- node source PC
- `mem_in`
- `mem_out`
- exit objects
- input/output types
- input/output residencies

`ssa_atoms.lua` reopens serialized node specs while preserving this metadata. Guards in `ssa_ir.lua` preserve source PC.

This means the planner can reason from semantic SSA summaries rather than only from stencil op names.

### Stencil IR status

`stencil_ir.lua` is now semantic fragment-oriented metadata, not C-ready ABI.

Important invariant:

```lua
assert(t.role_kind ~= "exit" and t.role_kind ~= "fail",
       "exit/fail are control endpoints, not data holes")
```

`exit` and `fail` are not data holes. They are control/projection concepts.

Stencil IR still supports payload-capable data roles such as:

- `shape_offset`
- `shape_id`
- `metatable_offset`
- `field_offset`
- `array_base_offset`
- `call_target`
- `barrier`

But current fragment lowering rejects payload/dependency-heavy roles.

### Fragment IR status

`fragment_ir.lua` defines the current native-fragment metadata schema and validator.

Important enums include:

- `PHYSICAL_ABI`
- `DATA_RELOC_KIND`
- `CONTROL_RELOC_KIND`
- `FRAGMENT_FLAG`
- projection kinds such as `SYNCED_FRAME` and `BOX_I64`

Current validation requires, among other things:

- physical ABI
- abstract/non-executable layout for abstract fragments
- declared clobbers
- exactly one entry endpoint
- at least one ok endpoint
- fact transfer metadata
- separated data/control relocations
- projection ranges for non-success endpoints
- rejection of unsupported payload roles unless explicitly allowed
- rejection of dependencies unless explicitly allowed

Current fragments are metadata-only:

```lua
layout = {
  mode = "abstract_fragment",
  executable = false,
  code_offsets = "abstract_zero",
  reason = "metadata-only fragment descriptor; no native assembler offsets emitted",
}
```

Any executable interpretation of `abstract_zero` offsets would violate the current safety boundary.

### Fragment lowering surface

`stencil_to_fragment.lua` currently supports a narrow i64/slot/guard/simple-exit surface, including:

- `LoadSlot`
- `StoreI64Slot`
- `GuardI64`
- `UnboxI64`
- `ConstI64`
- `ConstI64Hole`
- `AddI64`
- `SubI64`
- `MulI64`
- `I64BinOp`
- `I64UnaryOp`
- `CmpI64`
- `ExitBoundary`
- `ExitResidual`
- `ExitUnlowered`

Supported data roles are currently:

- `slot`
- `slot_store`
- `imm`
- `const`
- `bool`

Payload roles are intentionally rejected.

### Projection status

`fragment_projection.lua` currently emits safe synced-frame projections:

```lua
{
  kind = "SYNCED_FRAME",
  reason = exit and exit.reason or "exit",
  pc = exit and exit.pc or source or 0,
  entries = {},
}
```

This preserves the old safety invariant: the interpreter-visible frame is already synchronized at exits.

It does **not** yet prove that unsynchronized values can be reconstructed. Therefore store/load seam deletion remains disallowed.

### Public C ABI status

`sponbank.h` declares a fragment-oriented C ABI with types such as:

- `SponFragmentId`
- `SponFragmentDesc`
- `SponEndpointDesc`
- `SponDataReloc`
- `SponControlReloc`
- `SponProjectionEntry`

But there is no generated C bank, selector implementation, native linker, or executable runtime in the current maintained tree.

Known ABI gaps from the workflow:

- Lua fragment descriptors carry `locations` and `clobbers`; `sponbank.h` does not yet expose complete clobber/location accessors.
- Lua projections carry `pc` and `reason`; `SponProjectionEntry` does not preserve all resume semantics.
- Lua ABI-lowered data uses 1-based starts/indices; the C ABI does not yet state index origin.
- `reloc_kind` is still `0` for abstract fragments.
- `sponbank.h` is currently a promise/spec surface, not a linkable implementation.

For the planner direction, `sponbank.h` remains provisional. The semantic planner must not treat the current C header as proof that executable ABI details are final.

### Runtime and VM integration status

The maintained SpongeJIT tree currently has no executable PUC runtime integration:

- `spongejit/puc/` contains only `README.md`.
- `spongejit/runtime/` is empty.
- There are no maintained SpongeJIT `.c` runtime files.
- The old C-function tile runtime/materializer was removed or retired.

The Lalin VM contract currently forbids SponJIT integration:

```lua
sponjit_allowed = false
```

`VM_CONTRACT.md` requires VM gates around bytecode validation, frame/cache rules, native ABI, allocator behavior, errors, coroutine/yield semantics, and related runtime contracts before SponJIT may integrate with the VM.

---

## Chosen Target

The approved direction is **Approach C: Semantic Planner First, Execution Deferred**.

This direction treats the current abstract fragment backend as a semantic linking and projection verifier. The planner should validate fragment composition, fact transfer, endpoint compatibility, dependency handling, projection completeness, and seam-removal legality before any executable native x64 backend is built.

This was chosen because the current post-hard-yank state has a strong metadata foundation but no executable backend. The largest immediate danger is freezing an incomplete native ABI before projection, endpoint, selector, and runtime fact semantics are understood.

---

## Architecture

### Planner input

The planner consumes abstract fragment descriptors produced by:

- `StencilToFragment.generate(...)`
- `worker_compile.lua` fragment JSON artifacts
- future corpus/foundry enumeration paths once they are aligned with fragment metadata

A fragment descriptor includes:

- source ops
- stencil ops
- active SSA node specs
- slotmaps
- endpoints
- locations
- clobbers
- data relocs
- control relocs
- projections
- fact transfer signatures
- dependencies, if any
- abstract layout metadata

### Planner output

The planner produces a semantic linked-region result, not machine code.

The result must record:

- accepted fragment instances
- rejected fragment instances and reasons
- explicit success, guard, residual, boundary, and unlowered edges
- fact state before and after each fragment
- endpoint compatibility checks
- projection obligations per non-success exit
- dependency obligations
- seam-removal candidates
- seam-removal legality results
- corpus/opportunity metrics

The planner output is an analysis artifact and validation gate. It is not executable.

### Data model concepts

The planner model is centered on existing fragment concepts:

| Concept | Source |
|---|---|
| Fragment template | `fragment_ir.lua` descriptor |
| Endpoint | `EndpointDesc` / Lua endpoint metadata |
| Data relocation | `DataRelocDesc` / `SponDataReloc` |
| Control relocation | `ControlRelocDesc` / `SponControlReloc` |
| Projection recipe | `fragment_projection.lua` / fragment projection array |
| Fact transfer | `ssa_contract.lua` selector/required/checked/produced/killed signatures |
| SSA semantics | `active_node_specs` from `ssa.lua` |
| Slot mapping | Stencil/fragment `slotmaps` |
| Dependencies | fragment dependency metadata, currently rejected unless allowed |

The planner must make success edges explicit. Current descriptors declare `ok` endpoints, but the semantic planner must not rely on implicit fallthrough as proof of linkability.

---

## Planner Responsibilities

The Tier 2 semantic planner is responsible for the following.

### 1. Descriptor validation

Before planning, every fragment must satisfy the existing `fragment_ir.lua` validation rules and the planner’s semantic checks.

The planner must reject:

- executable use of abstract fragments
- fragments with missing entry/ok endpoints
- non-success endpoints without projection
- data relocs using control roles
- control relocs using data roles
- unsupported payload roles
- unsupported dependencies
- ambiguous index origins
- incomplete projection ranges
- incomplete fact-transfer metadata

### 2. Abstract linking

The planner links fragments symbolically.

It must represent:

- `ok` success edges
- guard exits
- residual exits
- boundary exits
- unlowered exits

This is semantic linking only. No native branch offsets, executable layout, or mmap behavior is involved.

### 3. Fact-flow tracking

The planner tracks facts across fragment instances using the existing contract model:

- selector facts
- required facts
- checked facts
- produced facts
- killed facts

It must preserve the distinction between available facts, required facts, checked facts, and transferred facts.

It must also account for the known gap that direct calls to `StencilToFragment.generate(...)` depend on callers passing the original fact set. Silent weakening of selector signatures is not acceptable for planner decisions.

### 4. Endpoint compatibility

The planner checks that linked endpoints are semantically compatible.

Current endpoint locations are conservative and mostly describe context/frame access, not true register-preserving value flow. The planner must therefore treat current endpoint compatibility as semantic/abstract, not as proof of physical register linkability.

SSA value residency such as `"gpr0"` is preserved metadata, but it is not yet a concrete x64 endpoint contract.

### 5. Projection completeness

Every non-success exit must have a projection.

Current `SYNCED_FRAME` projections are valid but non-optimizing. They certify that frame state remains synchronized; they do not authorize store/load seam deletion.

The planner must distinguish:

- exits that are safe because the frame is already synchronized
- exits that would require explicit reconstruction of unsynchronized values
- exits whose projection is incomplete and must reject the plan

### 6. Seam-removal legality

The planner may model store/load seam removal only as a semantic analysis.

It must not declare a seam removable unless projection can reconstruct the interpreter-visible state at every possible exit.

Until richer projection recipes are available, `SYNCED_FRAME` keeps the old invariant and does not unlock store/load seam deletion.

### 7. Dependency handling

Payload/dependency-heavy fragments remain outside the first planner surface.

The planner must fail loudly for unsupported dependency obligations rather than accepting dummy payloads, dummy epochs, or approximate leases.

### 8. Corpus-scale opportunity analysis

The planner should run over real opcode/fact corpora and report decision-driving metrics:

- accepted spans
- rejected spans
- rejection reasons
- exit/projection shapes
- fact-flow failures
- unsupported role/dependency frequency
- seam opportunities
- seam opportunities blocked by projection
- estimated value of future executable work

The purpose is to decide whether Tier 2 has enough semantic optimization value to justify the native linker phase.

---

## Required Invariants

1. **Abstract fragments are not executable.**
   `layout.executable = false` and `code_offsets = "abstract_zero"` must never be interpreted as native code layout.

2. **No C-function tile fallback exists in maintained SpongeJIT.**
   The old `SponTile`, `SponHoleReloc`, `SPON_HOLE_*`, `stencil_to_c`, `grammar_c_code`, and `grammar_holes` path remains retired.

3. **`exit` and `fail` are not data holes.**
   They are control/projection concepts.

4. **Data and control relocations stay separate.**
   Data roles such as `slot` and `imm` must not be used as control edges; control roles such as `guard_fail` must not be data relocs.

5. **Every fragment has exactly one entry and at least one ok endpoint.**

6. **Every non-success endpoint has a projection.**

7. **Unsupported payload/dependency roles fail loudly.**

8. **Store/load seam removal requires projection proof.**
   No frame desynchronization is allowed merely because a projection object exists.

9. **SSA metadata must remain preserved.**
   Source PC, memory tokens, exits, and value residencies are planner inputs.

10. **Planner success is not native success.**
    A valid semantic plan is a prerequisite for native linking, not evidence that native linking already works.

11. **Lalin VM integration remains gated.**
    `sponjit_allowed = false` remains authoritative until VM contract gates are satisfied.

---

## Validation Gates

### Existing gates that must remain green

Current SpongeJIT tests must continue to pass:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_ir.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_fragment_projection.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_to_fragment.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_retirement.lua
(cd experiments/lua_interpreter_vm/spongejit && make test)
```

### New planner gates

The semantic planner direction requires gates for:

1. descriptor conformance before planning
2. explicit abstract edge construction
3. fact-flow validation across linked fragments
4. endpoint compatibility validation
5. projection completeness validation
6. contract exit / fragment endpoint / control reloc / projection alignment
7. dependency rejection or validation
8. seam-removal legality validation
9. corpus-scale accepted/rejected/opportunity metrics

### Native backend gate

Executable native work must not begin from abstract descriptors alone. Before a native linker is allowed, the project must have decision-driving planner evidence and a lossless executable ABI boundary.

---

## Non-Goals

The Tier 2 semantic planner does **not**:

- emit x64 assembly
- allocate executable memory
- patch native branches
- implement a native image linker
- implement a generated C fragment bank
- finalize `sponbank.h` as an executable ABI
- integrate with the Lalin VM
- resurrect the old C-function tile backend
- claim Tier 1 floor coverage
- support payload-heavy shape/table/call-target/barrier fragments
- remove frame stores/loads without projection proof
- benchmark native Copy-Link-Patch performance

---

## Relationship to Future Native x64 Copy-Link-Patch

The future native x64 backend remains possible, but it is downstream of the planner.

If the planner proves semantic value and correctness, a future native backend must still close the known ABI gaps:

- lossless location exposure
- clobber exposure
- projection resume data
- explicit index origins
- selector identity
- concrete relocation kinds
- executable/non-executable phase separation
- explicit success/control edges
- concrete mapping from SSA residency to physical registers

The future native linker would consume stabilized fragment/planner contracts and then copy native fragments, patch data/control relocations, install projection/fallback stubs, and enter one executable image.

That work is not part of the planner phase.

---

## Relationship to Lalin VM Gates

SponJIT remains separate from the Lalin interpreter VM.

The VM contract currently states:

```lua
sponjit_allowed = false
```

SponJIT must not become an execution engine for `src/vm_loop.lua` until the VM gates around validation, frame/cache semantics, native ABI, allocator behavior, errors, coroutine/yield behavior, and related runtime contracts are satisfied.

The planner may produce semantic evidence useful to future VM integration, but it must not depend on PUC runtime layouts or bypass Lalin’s VM contract.

Approach B, Lalin Region Assimilation, was not chosen for this phase. The planner should therefore remain a SpongeJIT semantic validation layer, not a Lalin region compiler.

---

## Risks

1. **Verifier project risk**
   The planner could accumulate metadata without producing decision-driving evidence for Tier 2 value.

2. **False executable confidence**
   Abstract fragment metadata could be mistaken for a runnable native backend.

3. **Projection weakness**
   `SYNCED_FRAME` is safe but does not unlock the main Copy-Link-Patch optimization.

4. **Endpoint under-specification**
   Current endpoint locations do not yet express true register-preserving value flow.

5. **Fact identity gaps**
   Pattern keys, source opcode identity, stencil hashes, fact signatures, and contracts are not yet fully aligned.

6. **No maintained executable baseline**
   The old C-function tile path is gone, so performance comparison must wait for a future executable harness.

7. **ABI hardening risk**
   Freezing `sponbank.h` or x64 assumptions too early could preserve the wrong boundary.

8. **VM integration risk**
   Lalin VM integration remains explicitly gated and must not be assumed.

---

## Initial Implementation Slices

### Slice 1: Make abstract linking explicit

Build planner logic that turns fragment descriptors into an explicit semantic graph with:

- entry nodes
- ok edges
- guard exits
- residual exits
- boundary exits
- unlowered exits

No executable layout is involved.

### Slice 2: Cross-check exits and projections

Validate that contract exits, fragment endpoints, control relocs, and projection ranges describe the same exit obligations.

Reject plans where they diverge.

### Slice 3: Track fact flow across linked fragments

Use selector/required/checked/produced/killed signatures to validate linked fragment sequences.

Record rejection reasons for missing facts or invalid transfers.

### Slice 4: Validate projection completeness

Keep `SYNCED_FRAME` as the safe baseline.

Add planner checks that distinguish synced-frame exits from exits that would require real reconstruction.

### Slice 5: Model seam-removal legality

Analyze store/load seam candidates, but do not remove them unless projection can reconstruct state at every exit.

### Slice 6: Run corpus-scale opportunity analysis

Measure accepted spans, rejected spans, unsupported roles, projection blockers, and potential seam value over generated grammar/corpus artifacts.

### Slice 7: Decide whether to proceed to native backend

Use planner results to decide whether the next phase should be native x64 Copy-Link-Patch, continued semantic planning, or a different integration strategy.

The planner phase itself does not make that executable-backend decision.

## Knowledge-builder Output — 2026-05-30 19:24:40

### What Matters Most for This Problem

- **Dual-tree clarity:** SponJIT Tier 2 needs an explicit data tree and explicit control tree, not just prose plus Lua tables.
- **Phase separation:** SSA, Stencil IR, abstract fragments, planner results, native fragments, and runtime images must be different phase products.
- **Typed alternatives over flags/strings:** endpoint kinds, projection classes, rejection reasons, fragment phase, layout mode, and fact/dependency states should be typed variants.
- **Named control protocols:** planning, linking, projection checking, seam legality, and future runtime exit must be expressed as named outcomes, not booleans or status strings.
- **No false executability:** current fragments are abstract metadata; the spec must make that structurally impossible to confuse with native code.

---

## Core Design Insight

The current SponJIT docs describe many correct concepts — fragments, endpoints, relocs, facts, projections, planner outputs — but an explicit-programming spec should reorganize them as a **dual tree**:

```text
SponJIT Tier 2 design =
  data tree:    every value/state/artifact the system manipulates
  control tree: every phase, state machine, and possible outcome
```

The important shift is that “fragment descriptor” should not be the root concept. It currently blends several things:

- semantic fragment meaning
- abstract descriptor metadata
- ABI-lowered numeric fields
- future native layout
- future runtime image requirements

An explicit spec should split those into phase-specific data types.

---

# Structured Spec Outline

## 1. Purpose

One sentence:

> SponJIT Tier 2 semantically links abstract native-fragment descriptors, validates facts/endpoints/projections/seams, and produces decision-driving planner artifacts before any executable Copy-Link-Patch backend is allowed.

This keeps the approved direction clear: **planner first, execution deferred**.

---

## 2. Data Tree

### 2.1 Source Data vs Derived Phase Outputs

The spec should explicitly define which values are source at each boundary.

#### Foundry source data

```text
SemanticOpStream
FactInputSet
FactAxisConfig
OpcodeWindow
RuntimeObservationSample
```

These are inputs from bytecode/profile/fact enumeration.

#### SSA phase output

```text
SsaGraph
SsaNodeSpec
SsaValueSpec
MemoryToken
ExitProjectionSeed
EffectSummary
```

Derived from semantic ops + facts.

#### Stencil phase output

```text
StencilShape
StencilOp
StencilValue
DataHole
SlotMap
StencilExit
```

Derived from SSA. Important invariant:

```text
DataHole = slot | slot_store | imm | const | bool | payload_role ...
```

`exit` and `fail` are not data holes.

#### Fragment phase output

```text
AbstractFragmentTemplate
Endpoint
EndpointLocationContract
DataReloc
ControlReloc
ProjectionRecipe
FactTransfer
DependencyObligation
EffectContract
```

Derived from Stencil + contracts.

#### Planner phase output

```text
FragmentInstance
LinkedRegionPlan
PlanEdge
FactTrace
ProjectionObligation
SeamCandidate
SeamLegalityResult
PlannerReport
```

Derived from fragment catalog + planning request.

#### Future native phase output

```text
NativeFragmentTemplate
ConcreteRelocEncoding
ImageLayout
PatchPlan
LinkedImage
RuntimeExitStub
```

Not part of the current planner phase.

---

## 3. Typed Alternatives Instead of Flags and Strings

The explicit spec should replace vague strings/flags with typed variants.

### Fragment phase

Instead of:

```lua
layout = { executable = false, code_offsets = "abstract_zero" }
```

Use:

```text
FragmentBody =
  AbstractBody(reason: AbstractReason)
| NativeBody(text_ref, entry_offset, reloc_table)
```

This makes abstract fragments structurally non-executable.

### Endpoint kind

```text
EndpointKind =
  Entry
| Ok
| GuardExit
| ResidualExit
| BoundaryExit
| ReturnExit
| BranchTrue
| BranchFalse
| UnloweredExit
```

### Control edge

```text
ControlEdge =
  SuccessEdge(from_ok, to_entry)
| GuardFailEdge(from_guard, projection)
| ResidualEdge(resume)
| BoundaryEdge(resume)
| ReturnEdge(result)
| ProjectionStubEdge(projection)
```

### Projection recipe

```text
ProjectionRecipe =
  SyncedFrame(resume_pc, resume_op_idx)
| ReconstructFrame(resume_pc, resume_op_idx, entries)
| VirtualProjection(resume_pc, entries, deps)
```

Current implementation only has the safe first case.

### Projection entry

```text
ProjectionEntry =
  FromSlot(dst_slot, src_slot, value_type)
| FromRegister(dst_slot, location, value_type)
| Const(dst_slot, value)
| BoxI64(dst_slot, source)
| CopyTValue(dst_slot, source)
```

### Fact carrier

```text
FactCarrier =
  Signature64(mask)
| PayloadLease(kind, payload, dependency)
```

This prevents treating `SponFactSig` as if it contained payload values.

### Rejection reason

Instead of string reasons:

```text
PlanRejection =
  UnsupportedOp(op)
| UnsupportedDataRole(role)
| MissingRequiredFact(fact)
| PayloadUnavailable(role)
| DependencyUnsupported(kind)
| MissingProjection(endpoint)
| ProjectionSourceClobbered(location)
| EndpointIncompatible(producer, consumer)
| AbstractFragmentUsedAsExecutable(fragment_id)
| VmGateClosed(gate)
```

---

## 4. Control Tree

The spec should name the major regions/protocols even if implemented in Lua later.

### 4.1 Top-level planner protocol

```text
region plan_tier2_span(request: PlanningRequest;
  accepted: cont(plan: LinkedRegionPlan, report: PlannerReport),
  rejected: cont(report: RejectionReport),
  deferred: cont(reason: PlannerDeferral))
```

`deferred` is important: some failures are not semantic rejection; they mean “native ABI/runtime not ready.”

---

### 4.2 Descriptor validation protocol

```text
region validate_fragment(fragment: AbstractFragmentTemplate;
  valid: cont(fragment: ValidFragmentTemplate),
  invalid: cont(reason: FragmentValidationError))
```

This avoids `ok = true/false`.

---

### 4.3 Candidate selection protocol

```text
region select_candidate(pc: SourcePc, facts: FactState, catalog: FragmentCatalog;
  selected: cont(candidate: FragmentCandidate),
  no_candidate: cont(reason: SelectionFailure))
```

---

### 4.4 Fact-flow protocol

```text
region transfer_facts(instance: FragmentInstance, facts_in: FactState;
  facts_ok: cont(facts_out: FactState),
  missing_required: cont(fact: FactAtom),
  contradicted: cont(fact: FactAtom),
  payload_unavailable: cont(obligation: PayloadObligation))
```

---

### 4.5 Edge compatibility protocol

```text
region check_edge(producer: Endpoint, consumer: Endpoint, live: LiveState;
  compatible: cont(edge: PlanEdge),
  needs_bridge: cont(requirement: BridgeRequirement),
  incompatible: cont(reason: EndpointIncompatibility))
```

Current endpoint metadata is too abstract to prove physical register compatibility, so this protocol should explicitly distinguish semantic compatibility from physical compatibility.

---

### 4.6 Projection protocol

```text
region validate_exit_projection(endpoint: NonSuccessEndpoint, frame: FrameState;
  synced_safe: cont(recipe: SyncedFrameProjection),
  reconstructable: cont(recipe: ReconstructingProjection),
  incomplete: cont(reason: ProjectionFailure))
```

This is central. Current `SYNCED_FRAME` means “safe because nothing was desynchronized,” not “projection is powerful.”

---

### 4.7 Seam legality protocol

```text
region analyze_seam(seam: SeamCandidate, exits: ExitSet, frame: FrameState;
  removable: cont(proof: SeamRemovalProof),
  blocked_by_projection: cont(exit: NonSuccessEndpoint),
  blocked_by_effect: cont(effect: EffectConflict),
  blocked_by_dependency: cont(dep: DependencyObligation),
  not_candidate: cont())
```

This prevents the planner from reporting a seam as removable merely because a projection object exists.

---

## 5. State Machines

### 5.1 Planner state machine

Should be written as explicit states:

```text
Start(request)
LoadCandidates(pc, facts)
ValidateCandidate(candidate)
Instantiate(candidate, slot_mapping)
CheckFacts(instance, facts)
BuildEdges(instance, frontier)
ValidateProjections(instance, exits)
AnalyzeSeams(plan)
Accept(plan, report)
Reject(report)
```

No hidden planner state in side tables.

---

### 5.2 Frame synchronization state

This should be a typed variant, not a boolean:

```text
FrameState =
  Synced
| Unsynced(pending_writes, virtual_values, live_locations)
```

Current planner should mostly remain in `Synced`.

Store/load seam removal is only legal from `Unsynced` if every non-success exit has a valid reconstruction recipe.

---

### 5.3 Fragment phase state

```text
FragmentPhase =
  SemanticStencil
| AbstractFragment
| AbiLoweredMetadata
| NativeFragment
| LinkedRuntimeImage
```

This prevents abstract descriptors from being consumed by native linker code.

---

### 5.4 Runtime image lifecycle, future only

```text
ImageState =
  Unbuilt
| Validating
| LayoutAssigned
| PatchedWritable
| Executable
| Published
| Invalidated(reason)
```

This belongs to future runtime/native specs, not the current planner implementation.

---

## 6. Phase Boundaries

The spec should define phase boundaries as immutable products:

```text
Semantic ops + facts
  -> SSA result

SSA result
  -> Stencil shape

Stencil shape
  -> Abstract fragment template

Fragment templates + planning request
  -> Linked semantic plan

Linked semantic plan
  -> Planner report / backend decision

Only later:
Linked semantic plan + native fragments
  -> Patch plan

Patch plan
  -> Runtime image
```

Important rule:

> Derived summaries may be memoized at phase boundaries, but must not become source data.

Examples of derived data that should not be treated as source truth:

- `stencil_hash`
- `pattern_key`
- numeric ABI enum fields
- start/count flattened-array ranges
- fact signatures derived from richer fact objects
- projection counts derived from projection recipes
- `abstract_zero` offsets

---

## 7. Relation to Existing Specs

### `SPONJIT_TIER2_PLANNER_SPEC.md`

This should become the immediate home for the explicit data/control tree.

It already has the right direction, but should be strengthened by adding:

- explicit data tree section
- explicit control protocols
- typed rejection reasons
- frame-state model
- phase-product table
- anti-pattern checklist

### `SPONJIT_COPY_LINK_PATCH.md`

This should be treated as the **future native ABI spec**, downstream of the planner.

It should not be the source of truth for planner semantics because it is concerned with:

- native text offsets
- relocation encodings
- physical ABI
- image layout
- runtime patching

The planner spec should feed it, not depend on it.

### `SPONJIT_RUNTIME_DESIGN.md`

This appears stale relative to the hard-yank. It should either be archived or rewritten around:

```text
FragmentTemplate, not TileTemplate
FragmentImage, not tile image
named runtime exit protocol, not exit_kind flags
explicit image lifecycle state machine
```

### `sponbank.h`

Treat as provisional wire/ABI surface, not the semantic design root.

Current known gaps map directly to explicit-programming violations:

- locations/clobbers exist in Lua but are not losslessly exposed
- projection `pc/reason` is not preserved in C projection entries
- index origins are implicit
- flags compress typed alternatives

---

## 8. Anti-patterns to Avoid

### 1. Stringly exits

Bad:

```text
reason = "guard:i64"
kind = "abstract_zero"
```

Good:

```text
GuardExit(predicate, resume)
AbstractBody(reason)
```

### 2. Boolean results for validation

Bad:

```lua
return { ok = false, errors = ... }
```

Spec-level good:

```text
valid(fragment) | invalid(reason)
```

Lua may implement this as tagged tables, but the spec should name the variants.

### 3. Flags as semantic state

Bad:

```text
flags = ABSTRACT | PUC_PATCHABLE
```

Good:

```text
FragmentBody = AbstractBody | NativeBody
Patchability = PatchableDataRoles(...)
```

Flags may exist only in final wire encoding.

### 4. Hidden state in context structs

`SponExecCtx`-style blobs are acceptable only at runtime boundaries. Planner semantics should expose:

- frame state
- facts
- exit projection state
- dependency leases
- live values

as typed data.

### 5. Implicit success fallthrough

An `ok` endpoint is not enough. The planner should produce an explicit success edge:

```text
SuccessEdge(fragment_a.ok, fragment_b.entry)
```

### 6. Premature native ABI hardening

Do not freeze x64 register contracts, `sponbank.h`, or relocation encodings before planner evidence shows what endpoint/projection information is actually required.

### 7. Treating current projection presence as optimization proof

`SYNCED_FRAME` proves safety by preserving the old invariant. It does not authorize frame desynchronization or store/load deletion.

---

## 9. Spec Checklist

A proper explicit-programming SponJIT Tier 2 spec should let a reader answer:

- What is source data, and what is derived?
- What exact phase product does each module produce?
- What are all fragment endpoint alternatives?
- What are all planner rejection alternatives?
- What are all projection recipe alternatives?
- What state does the planner carry between fragments?
- What state machine selects, validates, links, and rejects candidates?
- Which outcomes are consumed immediately as control protocols?
- Which outcomes become data because they cross phase/runtime boundaries?
- Which fields are semantic truth, and which are ABI-lowered wire encodings?
- Why is an abstract fragment impossible to execute by mistake?

If the spec cannot answer one of those structurally, the design still contains implicit meaning.

## Scout Output — 2026-05-31 13:02:58

## Files Retrieved

1. `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` (lines 1-322) — SpongeJIT SSA lowering. `FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, `TFORLOOP` are not specialized; they fall to `GenericExit`.
2. `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` (lines 1-424) — SSA graph/effects/exits. No loop-specific SSA ops exist.
3. `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` (lines 1-268) — SSA → Stencil IR. `FOR*`/`TFOR*` slotmaps include only operand `a`; generic exits lower to `ExitResidual`.
4. `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` (lines 1-179) — Stencil IR op/hole vocabulary. No loop ops; `exit`/`fail` are forbidden as data holes.
5. `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua` (lines 1-197) — Abstract native-stencil descriptor lowering. Supports `ExitResidual`; no branch/backedge endpoint model.
6. `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua` (lines 1-489) — Native stencil metadata schema/enums/validator.
7. `experiments/lua_interpreter_vm/spongejit/src/stencil_projection.lua` (lines 1-45) — Current projections are `SYNCED_FRAME` / `BOX_I64`.
8. `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` (lines 1-354) — Fact-axis generation. Numeric `FORPREP`/`FORLOOP` get i64 facts for `A`, `A+1`, `A+2`; generic `TFOR*` gets none.
9. `experiments/lua_interpreter_vm/spongejit/src/facts.lua` (lines 1-303) — Fact lattice includes shorthand `loop_i64`.
10. `experiments/lua_interpreter_vm/spongejit/src/fact_signature.lua` (lines 1-221) — 64-bit fact ABI, slot facts limited to canonical slots `0..7`.
11. `experiments/lua_interpreter_vm/spongejit/src/ssa_contract.lua` (lines 1-98) — Selector/required/checked/produced/killed signatures and hard-exit fact killing.
12. `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` (lines 1-482) — Grammar includes `FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, `TFORLOOP`; exact L0 floor generation includes all concrete opcodes.
13. `experiments/lua_interpreter_vm/spongejit/src/loader.lua` (lines 1-120) — Profile loader infers `loop_i64` for `FORPREP`/`FORLOOP`.
14. `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 1-164) — Worker emits SSA normal forms into SQLite, not executable code.
15. `experiments/lua_interpreter_vm/spongejit/src/dedupe_normal_forms.lua` (lines 1-222) — Merges forms and lowers unique representatives to abstract stencil descriptors.
16. `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` (lines 1-700) — Generates abstract C metadata bank/selectors from SQLite.
17. `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` (lines 1-255) — Public stencil descriptor ABI.
18. `experiments/lua_interpreter_vm/spongejit/src/puc_bytecode.lua` (lines 1-334) — PUC bytecode dump/trace parsing into opcode events with `a/b/c/k/bx/sbx/ax/word`.
19. `.vendor/Lua/lopcodes.h` (lines 327-333) — PUC opcode comments for `FORLOOP`, `FORPREP`, `TFORPREP`, `TFORCALL`, `TFORLOOP`.
20. `.vendor/Lua/lvm.c` (lines 120-290, 1831-1905) — PUC runtime semantics for numeric and generic for loops.
21. `.vendor/Lua/lparser.c` (lines 1659-1725) — PUC parser/codegen layout for numeric/generic `for`.
22. `experiments/lua_interpreter_vm/src/bytecode.lua` (lines 1-106) — Lua 5.5 bytecode field decoder/encoder.
23. `experiments/lua_interpreter_vm/src/constants.lua` (lines 1-120, 160-168) — Opcode numbers and `RESUME_TFORLOOP_CALL`.
24. `experiments/lua_interpreter_vm/src/opcodes.lua` (lines 1-170, 650-805) — Lalin VM dispatch arg modes and loop opcode handler wiring.
25. `experiments/lua_interpreter_vm/src/op/loop.lua` (lines 1-135) — Lalin VM loop opcode handlers.
26. `experiments/lua_interpreter_vm/src/validate.lua` (lines 300-350) — Bytecode validator loop target/window checks.
27. `experiments/lua_interpreter_vm/src/regions_codegen.lua` (lines 970-992) and `src/regions_lower.lua` (lines 780-808) — Lalin compiler emits `FORPREP` placeholder and patches `FORLOOP`.
28. `experiments/lua_interpreter_vm/src/regions_resume.lua` (lines 1-170) — Resume protocol has `TFORLOOP_CALL`.
29. `experiments/lua_interpreter_vm/tests/test_vm_bytecode_decoder_contract.lua` (lines 1-33) — Tests `FORLOOP` uses `Bx`.
30. `experiments/lua_interpreter_vm/tests/test_vm_validation_contract.lua` (lines 1-210) — Tests valid `FORLOOP` target; no TFOR tests.
31. `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 1-151) and `test_spongejit_stencil_lower.lua` (lines 1-129) — SpongeJIT invariants; no loop-specialized tests.
32. `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md` (lines 1-170, 470-600, 663-919) — Native stencil terminology/constraints.
33. `experiments/lua_interpreter_vm/SPONJIT_TIER2_PLANNER_SPEC.md` (lines 1-220, 380-545, 620-660) — Planner constraints: explicit edges, projections, seam legality.
34. `experiments/lua_interpreter_vm/VM_CONTRACT.md` (lines 1-90) — JIT must consume only validated bytecode; loop register windows are part of validator contract.
35. Older harness files:
   - `tools/jit_harness/candidate_emit.lua` (lines 614-688) — Older simplified C lowering for `FORPREP`/`FORLOOP`.
   - `tools/jit_harness/lowering_plan.lua` (lines 1-160) — Older lowering names `forprep_i64_guarded`, `forloop_i64_guarded`.
   - `tools/jit_harness/seed_l0.lua` (lines 1-100) — Older L0 seeds include `FORLOOP_i64`, `FORPREP_i64`.
   - `tools/sponjit_shadow/catalog.lua` (lines 100-135) — Older shadow catalog has `FORLOOP_i64`.

## Key Code

### Current SpongeJIT behavior: all FOR/TFOR residualize

```lua
-- ssa_lift.lua
...
elseif op == "JMP" then g:jump(pc, ev); terminal = true
else terminal = generic_exit(g, op, pc, ev, "opcode_not_specialized") end
```

Empirical current output:

```text
FORPREP   -> GenericExit -> ExitResidual reason generic:FORPREP
FORLOOP   -> GenericExit -> ExitResidual reason generic:FORLOOP
TFORPREP  -> GenericExit -> ExitResidual reason generic:TFORPREP
TFORCALL  -> GenericExit -> ExitResidual reason generic:TFORCALL
TFORLOOP  -> GenericExit -> ExitResidual reason generic:TFORLOOP
```

Descriptor lowering accepts these as abstract residual stencils:

```text
entry + ok + residual_exit
control reloc: residual
projection: SYNCED_FRAME
data relocs: none
```

### Current loop fact axes

```lua
-- ssa_fact_axes.lua
local function bundle_for(bundles, n, op, pc)
  local a = op.a or 0
  make_bundle(bundles, "for:" .. n .. ":" .. pc, {
    ax_slot(reg(a), "is_i64", {role="index"}),
    ax_slot(reg(a + 1), "is_i64", {role="limit"}),
    ax_slot(reg(a + 2), "is_i64", {role="step"}),
  }, {tier=2, pc=pc, op=n})
end
```

Only numeric `FORPREP`/`FORLOOP` use this. `TFOR*` has no fact bundle.

### Current slotmaps for FOR are incomplete for loop state

```lua
-- ssa_to_stencil.lua
SLOT_FIELDS_BY_OP = {
  ...
  FORPREP={"a"}, FORLOOP={"a"}, TFORPREP={"a"}, TFORCALL={"a"}, TFORLOOP={"a"},
}
```

Numeric loop state actually involves at least `A`, `A+1`, `A+2`, and loop variable around `A+3`.

### PUC numeric for obligations

```c
/* .vendor/Lua/lvm.c */
OP_FORPREP:
  - convert/check init, limit, step
  - step == 0 errors
  - may skip loop with pc += Bx + 1
  - integer path rewrites stack to count / step / control variable
  - float path rewrites stack to limit / step / control variable

OP_FORLOOP:
  - integer path checks count > 0
  - decrements count
  - idx = idx + step
  - updates control variable
  - pc -= Bx on continue
  - float path uses floatforloop
  - calls updatetrap(ci)
```

### PUC generic for obligations

```c
OP_TFORPREP:
  - swap control and closing variables
  - create to-be-closed upvalue
  - pc += Bx
  - immediately proceeds to TFORCALL

OP_TFORCALL:
  - copies function/state/control into call frame
  - calls iterator with 2 args and C wanted results
  - may call/yield/error

OP_TFORLOOP:
  - tests iterator result/control value for nil
  - pc -= Bx on continue
```

### Lalin VM loop handlers differ from PUC oracle

`src/op/loop.lua` implements numeric loops as:

```lalin
FORPREP:
  prepared = init - step
  R[A] = prepared
  pc = pc + bx + 1

FORLOOP:
  idx = R[A] + R[A+2]
  R[A] = idx
  if step sign comparison vs R[A+1] passes:
      R[A+3] = R[A]
      pc = pc - bx
  else pc = pc + 1
```

Generic handlers:

```lalin
TFORPREP: pc = pc + bx
TFORCALL: jump error(ERR_RUNTIME)
TFORLOOP:
  if R[A+2] ~= nil:
      R[A] = R[A+2]
      pc = pc - bx
```

### Bytecode field facts

```lua
-- bytecode.lua
OP  = word & 127
A   = (word >> 7) & 255
B   = (word >> 16) & 255
C   = (word >> 24) & 255
Bx  = (word >> 15) & 131071
sBx = Bx - 65535
sJ  = Ax - 16777215
```

Dispatch uses `ARGS_ABX` for:

```lua
FORLOOP, FORPREP, TFORPREP, TFORLOOP
```

`JMP` uses `sJ`, not `sBx`.

### Current stencil ABI lacks loop/branch-specific endpoints

Current endpoint kinds:

```c
SPON_ENDPOINT_ENTRY
SPON_ENDPOINT_OK
SPON_ENDPOINT_GUARD_EXIT
SPON_ENDPOINT_RESIDUAL_EXIT
SPON_ENDPOINT_BOUNDARY_EXIT
SPON_ENDPOINT_UNLOWERED_EXIT
```

Current control reloc kinds:

```c
SPON_CONTROL_RELOC_FALLTHROUGH
SPON_CONTROL_RELOC_GUARD_FAIL
SPON_CONTROL_RELOC_RESIDUAL
SPON_CONTROL_RELOC_BOUNDARY
SPON_CONTROL_RELOC_PROJECTION_STUB
```

No current `loop_backedge`, `branch_true`, `branch_false`, or `loop_exit` control relocation exists.

## Relationships

- PUC bytecode extraction:
  - `tools/jit_harness/puc_proto_dump.c` and `puc_trace_operands.c`
  - parsed by `spongejit/src/puc_bytecode.lua`
  - yields events with `op/a/b/c/k/bx/sbx/ax/word`.

- SpongeJIT foundry path:
  ```text
  grammar/profile opcode events
  → ssa_fact_axes.lua facts
  → ssa_lift.lua
  → ssa_opt.lua
  → ssa_to_stencil.lua
  → stencil_lower.lua
  → dedupe_normal_forms.lua
  → build_bank.lua
  ```

- Loop facts exist before lowering:
  - `loop_i64` shorthand in `facts.lua`
  - slot-specific numeric loop bundle in `ssa_fact_axes.lua`
  - loader infers `loop_i64` for numeric `FOR*`.

- Loop semantics are not consumed by `ssa_lift.lua`.
  - The facts can appear in selector signatures, but no `ForPrepI64`/`ForLoopI64` SSA node is emitted.

- Current abstract descriptor bank can represent residual loop fallback stencils, but not specialized loop control:
  - residual endpoint yes
  - conditional backedge no
  - branch/loop endpoints no
  - branch target/data/control relocation for `Bx` not currently emitted.

## Observations

- Numeric `FORPREP`/`FORLOOP` currently compile successfully only because `GenericExit` is valid and lowers to `ExitResidual`.

- `TFORPREP`, `TFORCALL`, and `TFORLOOP` are present in grammar and opcode metadata but have no SpongeJIT facts or lowering beyond residual fallback.

- Current numeric loop fact axes name `R[A]`, `R[A+1]`, `R[A+2]`, but current slotmaps for `FOR*` include only operand `A`.

- With facts for `R0`, `R1`, `R2`, current `FORLOOP` selector signature becomes `0x7`, while slotmaps contain only logical slot for `A`.

- Current C projection ABI exposes only `{kind, value_type, logical_slot, value_index}`; Lua projection metadata has `pc` and `reason`, but generated C projection entries do not preserve them.

- Current `stencil_lower.lua` only creates `guard_fail` control relocs for `GuardI64`; residual loop fallback gets a `residual` control reloc.

- `TFORCALL` is a may-call/may-yield operation by PUC semantics; current Copy-Link-Patch docs say initial validation should reject `may_call`, `may_gc`, `may_throw`, or `may_yield` unless fallback/projection behavior is specified.

- Tests cover bytecode `FORLOOP` as `Bx` and one valid `FORLOOP` validator target. There are no SpongeJIT loop-lowering tests and no VM `TFOR*` validation tests found.

- The maintained SpongeJIT runtime is abstract metadata only: `spongejit/puc/README.md` says old PUC executable integration was removed; `spongejit/runtime/` is empty.

- Existing generated files under `spongejit/build/sponbank` are stale fragment-era artifacts and are ignored by the retirement test; source now names `SponStencil*`.

## Knowledge-builder Output — 2026-05-31 13:08:02

### What Matters Most for This Problem

- **Semantic oracle choice:** PUC loop semantics and Lalin VM loop semantics are not interchangeable.
- **Control topology:** `FORPREP`/`FORLOOP` are not straight-line opcodes; they introduce normal multi-continuation edges and backedges.
- **Slot-window correctness:** loop state spans multiple registers, but current SpongeJIT slotmaps record only `A`.
- **Normal-form dedupe safety:** deduping by stencil hash/source-op shape can erase operand-, contract-, and topology-sensitive loop distinctions.
- **Projection correctness:** loops mutate frame state before branching; every exit edge needs exact resume state.
- **Numeric vs generic separation:** numeric `for` is arithmetic/control; generic `for` is call/yield/TBC/resume machinery.
- **Copy-Link-Patch fit:** loops are the first case that really stress whether stencils are regions with explicit edges, not linear tiles.

---

### Non-Obvious Observations

- Current loop “support” is only residualization. `FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, and `TFORLOOP` compile because `GenericExit` lowers to `ExitResidual`, not because SpongeJIT understands loop semantics.

- The existing fact machinery already creates numeric loop facts for `A`, `A+1`, and `A+2`, but those facts are currently not consumed by loop lowering. They only influence selector signatures. This creates a deceptive state: the foundry appears loop-aware, but the lowering layer is not.

- Current loop slotmaps are under-specified. `ssa_to_stencil.lua` maps all `FOR*`/`TFOR*` ops as `{ "a" }`, but numeric loops require at least the loop register window around `A..A+2`, and Lalin’s current handler also writes `A+3`. Any selector fact remapping using only `A` cannot safely remap facts for limit/step/control slots.

- This slotmap gap can make fact signatures wrong for nonzero loop bases. A selector signature requiring facts for canonical `R0/R1/R2` cannot be remapped correctly if only the `A` occurrence is recorded.

- The `loop_i64` shorthand is not equivalent to the curated slot-specific loop facts. `loop_i64` describes a value-like “loop_index” fact, while the 64-bit runtime signature only encodes slot facts for `R0..R7`. Treating these as interchangeable would silently weaken runtime selection.

- PUC numeric `FORPREP` is not the simple Lalin-style `idx = init - step`. PUC rewrites stack layout into count/step/control for integer loops, computes an unsigned iteration count, handles `step == 0`, conversion failures, mininteger edge cases, and may skip the loop. A naive i64 arithmetic lowering would be observably different.

- PUC `FORLOOP` also differs from the Lalin VM handler. PUC decrements a count and updates the control variable; Lalin’s handler increments an index and compares against a limit. These can diverge on overflow, step edge cases, and prepared-stack layout.

- The PUC/Lalin mismatch is not just implementation detail. It means SpongeJIT must not borrow Lalin’s loop lowering as the semantic oracle for PUC bytecode without proving equivalence under the intended bytecode/version contract.

- `FORPREP` has two normal continuations: enter body or skip to after the loop. Current stencil endpoints have only `ok` plus exit-like endpoints. A specialized `FORPREP` cannot be represented as a single success endpoint without losing control semantics.

- `FORLOOP` has two normal continuations: backedge continue or fallthrough exit. Neither is a guard failure or residual exit. Current control reloc kinds lack `loop_backedge`, `branch_true`, `branch_false`, or `loop_exit`.

- Current descriptor lowering emits no explicit success/fallthrough control reloc. That is already a known abstraction gap, but loops make it critical: an `ok` endpoint cannot tell whether success means “next pc,” “skip target,” “backedge target,” or “loop exit.”

- `FORLOOP` uses unsigned `Bx` as a backward distance in Lua 5.5-style bytecode, not signed `sBx`. Current SpongeJIT helper logic mentions `sBx` for `FORPREP`/`FORLOOP` immediates. That is harmless while loops residualize, but unsafe for real lowering.

- PC indexing becomes much riskier with loops. PUC uses `pc += Bx + 1` for `FORPREP` skip and `pc -= Bx` for `FORLOOP` continue, while SpongeJIT metadata mixes 1-based Lua source indexes and 0-based runtime `op_idx` conventions. A one-off error changes loop target, not just exit metadata.

- Normal-form dedupe is especially dangerous for loops because current dedupe keeps one representative descriptor for many source-pattern aliases. For ordinary immediates, late patching can recover per-instance operands. For loop control operands, `Bx` determines graph topology, not just a scalar value.

- `stencil_hash`/normal form can ignore operand table contents such as branch offsets. That is acceptable for template dedupe only if the planner later binds each instance’s control target from actual bytecode. Current selector/build metadata does not yet expose that as a first-class control binding.

- `worker_compile.lua` dedupes by normal form and explicitly does not include the contract in the dedupe key. For loop facts, this can collapse zero-fact residual forms and i64-fact forms into one representative contract. That is safe only for residual fallback; it is unsafe once loop specialization depends on facts.

- Pattern aliases are opcode-pattern based. `build_bank.lua` packs opcode bytes and length, not loop target operands. Therefore all `FORLOOP` bytecodes of the same opcode pattern are candidate-equivalent even if their backedges target different regions.

- The current greedy selector is linear: choose a stencil, then advance `pc += len`. That is incompatible with executing or planning real loop control flow. A loop stencil’s next executable PC is data-dependent and may be backward.

- Current `ExitResidual` for loops is a hard boundary and kills facts. A specialized loop would need edge-specific fact transfer: continue edge, fallthrough edge, error edge, trap edge, and possibly residual edge can have different fact states.

- Numeric loop lowering would need multi-slot frame transfer. `StoreI64Slot` currently handles single-slot produced/killed facts. PUC `FORPREP` rewrites several slots at once; `FORLOOP` mutates loop state every iteration.

- Step-zero is not represented by current facts. There is a global `nonzero_i64` bit, but no slot-specific “step nonzero” fact for `A+2`. Any lowering relying only on `is_i64` still has to account for step-zero behavior.

- Step sign is also absent from facts. For a Lalin-style compare loop, sign controls branch condition. PUC’s count-based integer loop avoids repeated sign comparison, but then `FORPREP` must exactly compute count.

- PUC `FORLOOP` calls `updatetrap(ci)`. Even a pure i64 numeric loop has an asynchronous/runtime-observation obligation. A tight Copy-Link-Patch loop that never checks trap/debug/interruption state would not match PUC behavior.

- Generic `for` is qualitatively different from numeric `for`. `TFORPREP` swaps control/closing variables and creates a to-be-closed upvalue. `TFORCALL` calls the iterator and can allocate, yield, throw, and resume. `TFORLOOP` depends on call results. Treating `TFOR*` as “loop branch opcodes” like numeric `FOR*` is unsound.

- PUC generic loop slot layout differs from Lalin’s simplified handlers. PUC `TFORLOOP` checks `A+3`; Lalin’s current handler checks `A+2` and copies into `A`. That is a concrete semantic divergence, not merely a naming difference.

- `TFORCALL` interacts with Lalin’s resume protocol (`RESUME_TFORLOOP_CALL`). SpongeJIT’s current endpoint vocabulary has no equivalent continuation type.

- Current projections are `SYNCED_FRAME`. That is safe only if the frame is already in interpreter-visible state at every exit. Loop optimization pressure goes in the opposite direction: keeping loop counters/control values virtual or in registers across a backedge.

- For loop projections are edge-sensitive. Exiting before `FORPREP`, after successful preparation, after a skipped loop, after a continued `FORLOOP`, or after loop fallthrough all require different frame/PC states.

- Copy-Link-Patch seam removal across loops requires loop-carried value semantics. Current SSA is mostly acyclic and straight-line; there are no loop phis/backedge value contracts.

- The bytecode validator currently checks loop target ranges and register windows, but the findings do not show strong guarantees for paired `FORPREP`/`FORLOOP`, matching `A`, or valid `TFORPREP`→`TFORCALL`→`TFORLOOP` structure. Loop specialization cannot safely assume parser-produced structure unless that contract is explicit.

- L0 floor coverage currently survives because residual loop stencils exist. Adding partial loop specialization risks breaking that if residual zero-fact forms are deduped away, rejected by lowering, or no longer selected as fallback.

- Existing stale/generated bank artifacts are a risk for loop experiments. Since current SpongeJIT is metadata-only and abstract, any measurement or behavior claim must ensure it is not accidentally reading old generated artifacts.

---

### What Must Be True Before Implementation Is Safe

- The semantic target must be fixed: PUC loop semantics, Lalin VM semantics, or an explicitly proven common subset.
- Loop bytecode validation must guarantee register windows, target ranges, and structural pairing needed by the chosen semantics.
- Loop slotmaps must cover the full loop register window, not just operand `A`.
- `Bx`/target operands must become explicit control bindings, not ordinary immediates or representative-source metadata.
- Endpoint/control-reloc vocabulary must distinguish normal loop continue, loop exit, skip, boundary, residual, guard, trap, and call/yield exits.
- Normal-form dedupe must not discard fact contracts or operand topology needed to instantiate a safe loop stencil.
- Projection recipes must describe exact frame and PC state for every loop edge.
- Numeric and generic loops must not share a lowering model unless their very different obligations are represented.
- Runtime trap/debug/yield/error obligations must be explicit before executable loop stencils bypass the interpreter loop.

---

### Knowledge Gaps

- Whether SpongeJIT’s future loop lowering is intended to target PUC bytecode semantics or Lalin VM bytecode semantics.
- Whether the validator will enforce paired numeric/generic loop structure strongly enough for JIT assumptions.
- How current generated abstract bank artifacts handle loop aliases at full arity after dedupe.
- Whether planner data structures are expected to support cyclic regions or only acyclic linked spans.
- How trap/debug-hook behavior should be represented in SpongeJIT contracts.

## Approach-proposer Output — 2026-05-31 13:09:55

### Approach A: PUC-Exact Branching Loop Fragments

- **Core idea**: Lower numeric `FORPREP`/`FORLOOP` into PUC-semantics-native branching fragments with explicit loop control edges; keep `TFOR*` outside the first native surface.

- **Key changes**:
  - Add loop-specific SSA/stencil ops: `ForPrepI64Puc`, `ForLoopI64Puc`, possibly `LoopTrapCheck`.
  - Use PUC semantics as the oracle, not Lalin’s simplified loop handlers.
  - Extend endpoint/control vocabulary:
    - endpoints: `loop_body`, `loop_skip`, `loop_backedge`, `loop_done`, `loop_trap`, `loop_error`
    - relocs: `LOOP_SKIP`, `LOOP_BACKEDGE`, `LOOP_DONE`, `TRAP`, `ERROR`
  - Slotmaps for numeric loops cover full window: `A`, `A+1`, `A+2`, `A+3`.
  - Treat `Bx` as a control binding, not as an ordinary immediate.
  - Normal-form dedupe separates:
    - reusable loop template
    - per-instance topology binding: source PC, body PC, exit PC, backedge PC
    - fact contract variant
  - Fact contracts become edge-sensitive:
    - entry requirements: i64 facts for loop state
    - `FORPREP` produces prepared loop state
    - `FORLOOP` has different transfers on continue vs done
    - residual/error/trap exits kill or project facts conservatively.
  - `TFORPREP`/`TFORCALL`/`TFORLOOP` remain residual/call-yield boundaries until TBC/yield/resume semantics are modeled.

- **Tradeoff**: Best fit for literal Copy-Link-Patch loop materialization; highest semantic and projection burden.

- **Risk**: PUC numeric loop semantics are subtle: count rewriting, step-zero behavior, overflow/mininteger cases, skip edges, trap updates, and exact PC math all become native-fragment obligations.

- **Rough sketch**:
  - Introduce PUC-specific numeric loop SSA ops.
  - Add full loop register-window slotmaps and slot fact remapping.
  - Add loop control endpoint/reloc variants.
  - Make dedupe preserve topology aliases and fact-contract variants.
  - Generate abstract loop fragments first; native materialization later patches skip/backedge/done branches.

---

### Approach B: Structured Loop Region Planner

- **Core idea**: Do not lower `FORPREP` and `FORLOOP` as independent fragments; recognize validated loop structures and plan them as one cyclic semantic region.

- **Key changes**:
  - Add a loop-region builder that pairs numeric `FORPREP`/`FORLOOP` and captures:
    - preheader
    - body entry
    - latch/backedge
    - loop exit
    - skip edge
  - Represent numeric loop state with explicit loop-carried values or phis.
  - Keep semantic dialect explicit:
    - PUC dialect for PUC bytecode streams
    - Lalin dialect only for Lalin VM bytecode, never implicitly shared.
  - Generic `TFOR*` becomes a separate `GenericForRegion` class with call/yield/resume/TBC obligations, not a numeric-loop variant.
  - Endpoint vocabulary lives at planner level first:
    - `LoopEnter`
    - `LoopBody`
    - `LoopBackedge`
    - `LoopExit`
    - `LoopSkip`
    - `CallYield`
    - `ResumeTFOR`
  - `Bx` is consumed by the region builder to construct CFG topology, not emitted as a hole.
  - Normal-form dedupe is graph-shaped:
    - key includes loop dialect, control shape, opcode pattern, body shape, and fact-contract class
    - aliases store actual PC topology and operand bindings.
  - Fact contracts become region contracts:
    - entry facts
    - loop-invariant facts
    - loop-carried facts
    - backedge transfer
    - exit transfer
    - call/yield invalidation for generic loops.

- **Tradeoff**: Optimizes for semantic correctness and planner clarity before native ABI hardening; sacrifices immediate byte-level Copy-Link-Patch reuse of tiny loop opcode fragments.

- **Risk**: This becomes a small loop compiler with cyclic SSA and fixed-point fact analysis, rather than a simple stencil linker.

- **Rough sketch**:
  - Extend validator/planner to expose structured loop regions.
  - Convert paired numeric loops into semantic cyclic regions.
  - Add region-level fact-flow and projection checks.
  - Keep generic `TFOR*` as modeled call/yield regions but non-materializable.
  - Later lower accepted loop regions into native fragments or Lalin regions.

---

### Approach C: Interpreter-Owned Loop Shell, Body-Only Fusion

- **Core idea**: Keep `FORPREP`/`FORLOOP`/`TFOR*` under interpreter or VM control, and use SpongeJIT only to fuse straight-line loop bodies between loop-control boundaries.

- **Key changes**:
  - Numeric `FORPREP`/`FORLOOP` lower to explicit loop-shell boundary descriptors, not native arithmetic/control fragments.
  - The loop shell owns:
    - exact PUC or VM loop semantics
    - `Bx` target calculation
    - trap/debug/yield/error behavior
    - loop register-window mutation.
  - SpongeJIT plans/materializes only acyclic spans inside the loop body.
  - Generic `TFOR*` is entirely shell-owned because `TFORCALL` may call, yield, throw, allocate, and resume.
  - Endpoint vocabulary:
    - `LoopShellEntry`
    - `LoopBodyEntry`
    - `LoopBodyReturn`
    - `LoopLatchBoundary`
    - `LoopExitBoundary`
    - `GenericForBoundary`
  - No native loop backedge reloc is introduced yet; body fragments return to the shell.
  - Normal-form dedupe remains mostly straight-line:
    - body fragments dedupe as existing abstract stencils
    - loop shell aliases store `A`, full register window, `Bx`, body range, latch PC, exit PC.
  - Fact contracts are conservative:
    - loop shell may export safe body-entry facts, e.g. known i64 loop variable
    - body fragments transfer facts normally
    - facts are filtered or killed at shell reentry/latch boundaries.
  - Copy-Link-Patch materialization is acyclic:
    - one fused body image
    - entered each iteration by the shell
    - no native cyclic image yet.

- **Tradeoff**: Optimizes for correctness and near-term use of existing straight-line fragment planning; sacrifices loop-control speedups and cross-iteration register preservation.

- **Risk**: If loop bodies are small, shell reentry overhead may dominate and fail to prove the value of full loop Copy-Link-Patch.

- **Rough sketch**:
  - Mark loop opcodes as structural boundaries, not residual “unknowns.”
  - Add loop-shell metadata carrying full operand topology and `Bx` targets.
  - Plan/fuse body spans between shell boundaries.
  - Let the shell execute numeric/generic loop control exactly.
  - Use planner metrics to decide whether native cyclic loop fragments are worth building later.

---

### Comparison

- Pick **Approach A** to pursue true native Copy-Link-Patch for loops immediately, with explicit branch/backedge materialization.
- Pick **Approach B** if loop correctness, cyclic control modeling, and projection/fact reasoning should be proven before any native ABI commitment.
- Pick **Approach C** if the priority is safe loop-body acceleration while deferring native loop-control lowering entirely.

## Knowledge-builder Output — 2026-05-31 13:53:29

### What Matters Most

- Preserve the current boundary: **foundry workers produce SSA-consumed normal forms only; byte code must be derived after global dedupe**.
- Keep abstract and native stencil products structurally distinct.
- Make every materializer decision depend on explicit descriptor data, not on Lua-only `source_ops`, string roles, or representative artifacts.
- Do not let native code generation depend on facts/opcode operands that were intentionally treated as aliases by normal-form dedupe.

### Non-Obvious Constraints and Insights

- The current pipeline is already split correctly for native bytes:
  `worker_compile.lua` stops at SSA normal forms, and `dedupe_normal_forms.lua` lowers each unique form once. Real x86-64 emission must live **after** this dedupe point or be content-addressed by the same dedupe key. Emitting bytes per worker/per opcode sequence would reintroduce pre-dedupe identity and break the foundry model.

- The dedupe key is only `stencil_hash`; the contract is explicitly **not** part of the key. Therefore native bytes for a deduped stencil must be invariant across all source fact/opcode aliases collapsed into that form. If a fact variant changes code shape, guard presence, branch shape, or patch layout, it is no longer merely metadata and must become a distinct normal form or distinct post-dedupe native variant.

- The selector pattern key is opcode-pattern based, not operand based. Operands such as slots, immediates, constants, and branch targets are instance bindings. A native stencil body cannot bake those into bytes at generation time unless they are represented as relocs patched from the actual bytecode at materialization time.

- Current `SponDataReloc` is too thin for a real materializer. It has `role_kind`, `op_idx`, and `role_arg`, but it drops the richer Lua role names like `"sC"`, `"k_i64"`, or `"bool_val"`. For native patching, `role_kind = imm` is not enough; the materializer must know which bytecode field/semantic operand supplies the value.

- `reloc_kind` is currently always lowered as `0`, and `code_offset_kind = "abstract_zero"` is Lua-only. In C, a materializer would see `code_offset = 0` and `reloc_kind = 0` with no way to distinguish “abstract placeholder” from “real offset zero.” Native stencils need nonzero relocation kinds plus a clear convention for offset, width, signedness, addend, and PC-relative base.

- Control relocs are also abstract. `guard_fail`, `residual`, and `boundary` relocs point to endpoint indices, but they do not yet carry enough resume/projection data for emitted bytes or stubs. Lua projections contain `pc` and `reason`; C `SponProjectionEntry` does not. That loses exactly the data needed for guard/residual exits.

- Endpoint and location metadata is internally generated, but `sponbank.h` exposes no `spon_stencil_locations()` accessor. `SponEndpointDesc` has `location_start`/`n_locations`, yet C users cannot retrieve the location array. Similarly, clobbers exist in Lua ABI metadata but are not emitted/exposed in the C bank. A native materializer cannot validate physical endpoint contracts from the public ABI today.

- The current endpoint contracts are semantic placeholders: `ctx in rdi`, synced frame in `ctx.stack`, abstract contract marker. They do not express real value flow such as “I64 output in rax consumed by next stencil.” Thus they are safe for abstract descriptors but not proof of linkable native fragments.

- Success control is still implicit. The selector advances `pc += len`, and `stencil_lower.lua` emits control relocs only for guards and exits. Real copy-link-patch needs explicit success/fallthrough semantics; otherwise the materializer cannot distinguish “fall through to next stencil” from “return to caller” from “internal branch target.”

- The generated C selector has a hidden native-safety issue: if no candidate matches, it unconditionally falls back to L0 via `spon_l0_stencil_for_opcode`, without rechecking `required_stencil_flags`. Once native and abstract stencils coexist, a native-only materializer must not accidentally receive an abstract L0 fallback.

- Current C bank arrays use mixed index conventions. Descriptor starts are rewritten into flattened shard-array offsets with dummy element zero; `control_reloc.endpoint_index` remains a local Lua-style 1-based endpoint index. A materializer must not consume these fields without a normalized accessor/convention.

- `spon_stencil_data(id)` currently returns `NULL`, and descriptor `offset/size` are zero. A native milestone must make `SPON_STENCIL_NATIVE` imply: nonzero size, retrievable bytes, valid offset range, and no abstract-zero relocs.

- Slot patching depends on slotmaps. Fact remapping only supports canonical slots `0..7`, and selector slot remapping rejects actual slots `>= 8` when actual slots are supplied. The first native surface is therefore constrained to small-slot cases unless the fact ABI and selector remapping are widened.

- Fixed-width x86 encodings are important for dedupe safety. If immediate size, displacement size, or branch encoding varies by runtime operand value, then the operand is no longer a simple patch value. The first native stencils should use conservative fixed-width patch sites so all aliases share identical bytes.

- Payload roles remain unsafe for first native materialization. `shape_id`, `field_offset`, `call_target`, `barrier`, etc. exist in vocabularies but require payload leases/dependencies. The current lowering intentionally rejects them; native byte stencils must preserve that fail-loud behavior.

### Minimal Correct Milestone Constraints

The minimal correct native milestone is not “some x86 bytes exist.” It must prove one post-dedupe stencil can be materialized without crossing semantic boundaries:

- one globally deduped i64/slot/guard stencil marked `SPON_STENCIL_NATIVE`
- nonzero byte body retrievable through the C bank
- all data/control relocs have real offsets and relocation kinds
- abstract descriptors are rejected by the materializer
- patch values come only from explicit relocs + actual bytecode + slotmaps
- guard failure has enough endpoint/projection metadata to resume correctly
- no payload roles, dependencies, loops, calls, heap accesses, or unsynced-frame projections
- selector fallback cannot hand abstract L0 stencils to the native materializer

The milestone’s correctness hinges on preserving this invariant:

> Native bytes are a derived body for one canonical normal form; every per-instance difference must be represented as explicit relocation/materializer data, never hidden in the representative source ops or facts.

## Documenter Output — 2026-05-31 14:31:38

# Native Byte-Stencil Milestone Documentation

## Goal

Record the implemented SpongeJIT milestone that moves the maintained foundry output from abstract metadata-only stencil descriptors to a native x86-64 byte-stencil bank for the supported first surface, including descriptor/ABI extensions, generated bank byte arrays/accessors, default full-bank build stats, tests/log artifacts, and remaining non-implemented runtime gaps.

## Incentives

This milestone addresses the prior gap where SpongeJIT could describe native-stencil metadata but could not emit or bank actual native byte bodies. The implemented work makes supported stencil forms carry concrete x86-64 bytes, real data/control relocation offsets, endpoint/projection metadata, and C ABI-lowered descriptors. It keeps the foundry invariant that byte bodies are derived after global normal-form dedupe: per-instance operands remain relocation inputs, not baked into representative source operands.

## Current State

### Native x86-64 byte emitter

Implemented in:

- `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua`

The emitter produces executable x86-64 raw function-body bytes for the first supported stencil surface. It emits fixed-width patch sites and returns:

```lua
{
  bytes = bytes,
  code_hex = bytes_to_hex(bytes),
  code_size = #bytes,
  data_relocs = data_relocs,
  control_relocs = control_relocs,
  layout = {
    mode = "native_bytes",
    executable = true,
    arch = "x86_64",
    encoding = "raw_function_body",
    entry_offset = 0,
    code_size = #bytes,
    fixed_width_patch_sites = true,
  },
}
```

Supported emitted operations include i64 slot load/store/guard/unbox/arithmetic, constants, `LOADK`, `LOADNIL`, `LOADTRUE`/bool constants, `MOVE`, comparisons, simple residual/boundary/unlowered exits, and local exit stubs.

The emitted body assumes:

- `ctx` in `rdi`
- cached `ctx->stack` in `r11`
- `SponExecCtx` offsets matching `sponbank.h`
- success path sets `ctx->exit_kind = SPON_EXIT_NONE` and returns
- guard/residual/boundary/unlowered stubs set `exit_kind`, `exit_pc`, `exit_op_idx`, `exit_hole`, then return

### Descriptor lowering

Implemented in:

- `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_abi_x64.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_projection.lua`

`stencil_lower.lua` now invokes `StencilNativeX64.emit(...)` and creates native executable stencil descriptors:

```lua
executable = true
layout = native.layout
code_hex = native.code_hex
code_size = native.code_size
data_relocs = native.data_relocs
control_relocs = native.control_relocs
```

`stencil_desc.lua` validates native stencils as `schema = "spon.stencil.native.v1"` and requires:

- executable native byte layout
- non-empty `code_hex`
- positive `code_size`
- explicit clobbers
- one entry endpoint
- at least one ok endpoint
- endpoint location contracts
- projection ranges for non-success endpoints
- concrete relocation kinds for native relocs
- separated data/control reloc semantics

Relocation kinds now include:

```text
unknown, abs32, abs32s, plt32, pc32, abs64, abs8
```

Current simple data roles remain:

```text
slot, slot_store, imm, const, bool
```

Payload/dependency-heavy roles still reject loudly.

### Public C ABI extensions

Implemented in:

- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h`

The public ABI is stencil-based:

- `SponStencilId`
- `SponStencilDesc`
- `SponEndpointDesc`
- `SponLocationDesc`
- `SponDataReloc`
- `SponControlReloc`
- `SponProjectionEntry`
- `SponDependencyDesc`

Notable extensions present:

- `SponTValueABI`
- `SponExecCtx`
- `SPON_STENCIL_NATIVE`
- relocation encoding enum: `SPON_RELOC_ABS32`, `SPON_RELOC_ABS32S`, `SPON_RELOC_PC32`, `SPON_RELOC_ABS64`, `SPON_RELOC_ABS8`
- `SponDataReloc.addend`
- `SponProjectionEntry.pc`
- `spon_stencil_locations(...)`
- `spon_stencil_data(...)`

### Foundry/build pipeline

Implemented pipeline:

```text
grammar enumeration
→ worker SQLite normal forms
→ global normal-form dedupe
→ lower one representative per unique form to native stencil descriptor/bytes
→ build C bank shards + selector + libsponbank.so
```

Key files:

- `spongejit/build_stencils.sh`
- `spongejit/src/worker_compile.lua`
- `spongejit/src/dedupe_normal_forms.lua`
- `spongejit/src/build_bank.lua`
- `spongejit/build_bank.sh`

`worker_compile.lua` stops at SSA normal forms. `dedupe_normal_forms.lua` globally merges by `stencil_hash` and lowers each unique supported form once. `build_bank.lua` consumes `stencil_bank.sqlite` and emits C shard/index files.

### Generated bank byte arrays/accessors

`build_bank.lua` now emits shard arrays for:

```c
SponStencilDesc
unsigned char              // native byte bodies
SponEndpointDesc
SponLocationDesc
SponDataReloc
SponControlReloc
SponSlotMapEntry
SponProjectionEntry
SponDependencyDesc
```

Generated accessor API includes:

```c
spon_bank_stencil_count
spon_bank_pattern_count
spon_get_stencil
spon_stencil_data
spon_stencil_endpoints
spon_stencil_locations
spon_stencil_data_relocs
spon_stencil_control_relocs
spon_stencil_slotmaps
spon_stencil_projections
spon_stencil_dependencies
spon_l0_stencil_for_opcode
```

The selector API remains available for greedy/flow/flags/slot-aware selection over `SponStencilDesc`.

## Implemented Target

The implemented milestone is a native byte-stencil foundation, not a runtime materializer.

It verifies that supported normal forms can produce:

- native x86-64 bytes
- nonzero code size
- native stencil flag `SPON_STENCIL_NATIVE`
- concrete relocation offsets
- concrete relocation kinds
- endpoint/location/projection metadata
- generated C byte arrays
- C accessors returning descriptor slices and byte bodies

## Default Full L1 Native Bank Stats

From:

- `experiments/lua_interpreter_vm/spongejit/build/stencil_bank/build_config.env`
- `experiments/lua_interpreter_vm/spongejit/build/stencil_bank/grammar_chunk_manifest.json`
- `experiments/lua_interpreter_vm/spongejit/build/sponbank/sponbank_build_manifest.json`

Default build config:

```text
CHUNKS=128
WORKERS=16
MAX_ARITY=4
MAX_FACT_COMBOS=32
FACT_AXIS_MODE=curated
WORKER_PROGRESS_SEQS=1000
```

Grammar/foundry plan:

```text
sequences=472060
estimated_compiles=8311921
chunks=128
max_sequence_combos=31
```

Generated native bank manifest:

```text
stencils=66709
max_id=66709
patterns=471158
candidates=631168
pattern_aliases=631168
chunks=2
rows_per_shard=50000
seconds=16
```

Shard counts:

| Shard | Stencils | Byte counter | Endpoints | Locations | Data relocs | Control relocs | Slotmaps | Projections | Dependencies |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 50,000 | 6,027,924 | 173,816 | 521,448 | 201,170 | 73,816 | 344,822 | 73,816 | 0 |
| 2 | 16,709 | 2,475,291 | 60,387 | 181,161 | 109,336 | 26,969 | 117,207 | 26,969 | 0 |

## Verification

### Native byte execution test

Implemented in:

- `experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua`

This test mmap-copies emitted bytes and calls them through:

```c
void (*)(SponExecCtx *)
```

Verified cases include:

- `ADDI` success path updates i64 slot value/tag
- `ADDI` guard failure sets `ctx.exit_kind = SPON_EXIT_GUARD`
- `LOADTRUE`
- `LOADNIL`
- `MOVE`
- `LOADK`

It also verifies native descriptor properties:

- executable stencil
- nonzero `code_hex` / `code_size`
- native flag `2`
- real data reloc offsets
- `abs64` immediate patch site
- `pc32` guard control relocation
- slot tag displacement patch sites

### Descriptor/lowering tests

Relevant tests:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_desc.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_projection.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_lower.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua
```

`test_spongejit_stencil_lower.lua` verifies:

- i64 arithmetic lowers to executable native bytes
- native flag is set
- endpoint locations and clobbers exist
- slot/slot_store/imm data relocs exist
- guard_fail control reloc exists
- native data/control relocs are not abstract
- boundary/residual/unlowered exits have projections
- payload/table/shape surfaces reject loudly

### Maintained test target

`experiments/lua_interpreter_vm/spongejit/Makefile` includes:

```sh
make test
```

which runs the SpongeJIT test suite including:

- real SSA invariants
- loop region tests
- stencil descriptor validation
- stencil projection
- stencil lowering
- native stencil byte execution
- retirement-token check

### Build artifacts/logs

Observed generated artifacts include:

```text
build/stencil_bank/grammar_chunk_manifest.json
build/stencil_bank/grammar_worker_N.sqlite
build/stencil_bank/worker_N.log
build/stencil_bank/stencil_bank.sqlite
build/sponbank/bank_chunk_1.c
build/sponbank/bank_chunk_2.c
build/sponbank/bank_index.c
build/sponbank/libsponbank.so
build/sponbank/sponbank_build_manifest.json
```

Example worker log shape:

```text
[W1] DONE seqs=3688 compiles=64937 ssa_ok=53387 rejected=11550 unique_forms=7606
```

## Remaining Gaps

Implemented native bytes do **not** yet mean a working Copy-Link-Patch runtime exists.

Remaining gaps captured by the current code/docs:

- no native stencil linker/materializer
- no copy/link/patch `LinkedImage`
- no Lalin VM integration
- no maintained PUC runtime integration
- no online Tier 2 fusion planner execution path
- no runtime patching/execution of generated `libsponbank.so` stencils
- no payload leases/dependency epochs for shape/table/call-target/barrier roles
- no unsynced-frame projection or store/load seam removal
- no loop/backedge/native cyclic control lowering
- no call/yield/error-capable generic-loop materialization
- first native surface is x86-64 SysV only
- emitted bytes currently return to caller through local success/exit stubs rather than being linked into one fused image
- selector/materializer support remains constrained by current slot remapping and fact-signature limits

The verified milestone is therefore: **native byte bodies and ABI-backed bank artifacts exist for supported first-surface stencils; runtime image linking and VM execution remain future work.**

## Documenter Output — 2026-05-31 14:48:25

# Native Materializer Update

## Goal

Append the implemented native materializer milestone: native x86-64 SpongeJIT stencils now carry an explicit `fallthrough` control relocation, can be copied into one image, have data relocations patched from concrete opcode/slot/constant bindings, and can link a `pc32` success jump to the next stencil for first-surface tests.

## Incentives

The previous native byte-stencil milestone produced executable bytes and bank metadata, but each stencil still returned through its local success stub. That verified native byte emission but not Copy-Link-Patch-style chaining. This update records the first maintained materializer path that copies multiple native stencils into one image and patches a success edge from one stencil to the next.

## Current State

### Explicit fallthrough control relocation

Implemented in:

- `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua`

After emitting stencil operations, the native emitter now emits an explicit success jump:

```lua
local ok_off = a:jmp32(ok_label)
control_relocs[#control_relocs + 1] = StencilDesc.control_reloc({
  code_offset = ok_off,
  code_offset_kind = "x86_64_rel32",
  reloc_kind = "pc32",
  edge_kind = "fallthrough",
  endpoint_index = ok_endpoint_index,
  source = 0,
})
```

If a materializer does not patch this relocation, the `pc32` jump targets the local `ok` endpoint stub, which sets:

```c
ctx->exit_kind = SPON_EXIT_NONE
```

and returns.

### Native materializer

Implemented in:

- `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua`

`M.materialize(entries, opts)` performs mechanical copy/link/patch:

1. Requires at least one stencil entry.
2. Rejects non-executable stencils.
3. Decodes each stencil’s `code_hex`.
4. Appends all stencil bytes into one image buffer.
5. Records each entry’s base offset and size.
6. Patches data relocations:
   - `slot` / `slot_store` → actual slot displacement plus addend
   - `imm` → explicit immediate binding or source opcode immediate field
   - `const` → constant-pool index displacement
   - `bool` → boolean tag
   - unsupported data roles fail loudly
7. Patches `fallthrough` control relocations:
   - only for non-final entries
   - requires `reloc_kind == "pc32"`
   - patches target to the next stencil’s base offset
8. Returns:

```lua
{
  ok = true,
  bytes = bytes,
  code_size = #bytes,
  entries = norm,
}
```

The materializer currently patches only fallthrough control edges. Guard/residual/boundary/unlowered exits remain local stencil exit stubs.

### mmap helper

`materialize_native_x64.lua` also provides:

- `Materialize.alloc_executable(bytes)`
- `Materialize.free_executable(mem, n)`

The allocation helper uses LuaJIT FFI with `mmap`, maps memory as `PROT_READ | PROT_WRITE | PROT_EXEC`, copies the materialized byte image with `memcpy`, and returns the executable pointer and size. `free_executable` calls `munmap`.

### New test

Implemented in:

- `experiments/lua_interpreter_vm/tests/test_spongejit_materialize_native.lua`

Verified cases:

1. **Two linked `ADDI` stencils**
   - First stencil has explicit `fallthrough` `pc32` reloc.
   - Second stencil also has a local fallthrough reloc, but as final entry it remains local.
   - Success case: `10 + 7 + 8 = 25`.
   - Guard failure in the first stencil sets `SPON_EXIT_GUARD`; second stencil does not run.

2. **`LOADK` linked into `ADDI`**
   - Constant-pool relocation is patched from concrete opcode operand `b = 2`.
   - `k[2] = 37`, then linked `ADDI +5` produces `42`.

## Chosen Target

The implemented target is a first-surface native x86-64 materializer for already-built `SponStencil` descriptors. It does not run SSA, normalize forms, infer semantics, or consume representative-only operands. All instance-specific variation enters through explicit relocation records plus concrete entry bindings.

## Rebuilt L1 Bank Stats After Fallthrough

Sources:

- `experiments/lua_interpreter_vm/spongejit/build/stencil_bank/build_config.env`
- `experiments/lua_interpreter_vm/spongejit/build/stencil_bank/grammar_chunk_manifest.json`
- `experiments/lua_interpreter_vm/spongejit/build/sponbank/sponbank_build_manifest.json`

Build config:

```text
CHUNKS=128
WORKERS=16
MAX_ARITY=4
MAX_FACT_COMBOS=32
FACT_AXIS_MODE=curated
WORKER_PROGRESS_SEQS=1000
```

Grammar/foundry plan:

```text
sequences=472060
estimated_compiles=8311921
chunks=128
max_sequence_combos=31
```

Generated bank manifest:

```text
stencils=66709
max_id=66709
patterns=471158
candidates=631168
pattern_aliases=631168
chunks=2
rows_per_shard=50000
seconds=16
```

Shard counts after fallthrough relocs:

| Shard | Stencils | Native bytes | Endpoints | Locations | Data relocs | Control relocs | Slotmaps | Projections | Dependencies |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 50,000 | 6,277,924 | 173,816 | 521,448 | 201,170 | 123,816 | 344,822 | 73,816 | 0 |
| 2 | 16,709 | 2,558,836 | 60,387 | 181,161 | 109,336 | 43,678 | 117,207 | 26,969 | 0 |
| **Total** | **66,709** | **8,836,760** | **234,203** | **702,609** | **310,506** | **167,494** | **462,029** | **100,785** | **0** |

## Verification Logs

Materializer test:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_materialize_native.lua
# ok - SpongeJIT native materializer links stencils
```

Maintained SpongeJIT test target includes the materializer test:

```sh
(cd experiments/lua_interpreter_vm/spongejit && make test)
# ok - real SponJIT fact + SSA invariants
# ok - SpongeJIT loop region recognition
# ok - SpongeJIT stencil IR validation
# ok - SpongeJIT stencil projection
# ok - SpongeJIT stencil to native stencil
# ok - SpongeJIT native stencil bytes execute
# ok - SpongeJIT native materializer links stencils
# ok - SpongeJIT retired ABI names absent from maintained source
```

Example rebuilt worker logs:

```text
[W1] DONE seqs=3688 compiles=64937 ssa_ok=53387 rejected=11550 unique_forms=7606
[W128] DONE seqs=3688 compiles=64936 ssa_ok=52868 rejected=12068 unique_forms=7619
```

This update supersedes the prior “no native materializer” status for the first-surface Lua materializer harness.

## Scout Output — 2026-05-31 19:26:45

## Files Retrieved

1. `spongejit/src/ssa_lift.lua` (lines 1-327) — Main opcode semantics boundary. Missing facts/unsupported semantics become `GenericExit`.
2. `spongejit/src/ssa_ir.lua` (lines 1-424) — Defines `Residual`, `GenericExit`, residual effect, hard barriers, exit projections.
3. `spongejit/src/ssa_to_stencil.lua` (lines 1-268) — Lowers `GenericExit`/`Residual` to `ExitResidual`; jumps/returns/calls to `ExitBoundary`.
4. `spongejit/src/stencil_ir.lua` (lines 1-179) — Stencil op vocabulary includes `ExitResidual`; forbids `exit`/`fail` as data holes.
5. `spongejit/src/stencil_lower.lua` (lines 1-151) — Native descriptor lowering; supports `ExitResidual` as first-surface op.
6. `spongejit/src/stencil_desc.lua` (lines 1-489) — Native stencil descriptor enums/validation, including residual endpoint/control reloc IDs.
7. `spongejit/src/stencil_native_x64.lua` (lines 1-586) — Emits native bytes; residual stubs set `SPON_EXIT_RESIDUAL`.
8. `spongejit/src/materialize_native_x64.lua` (lines 1-262) — Lua copy/link/patch materializer; patches fallthrough only.
9. `spongejit/include/sponbank.h` (lines 1-255) — Public ABI: `SPON_EXIT_RESIDUAL`, residual endpoint, residual control reloc.
10. `spongejit/src/build_bank.lua` (lines 1-700) — Generated bank/selectors; L0 fallback and fact transfer.
11. `spongejit/src/grammar_enum.lua` (lines 1-482) — Opcode grammar and exact L0 generation for opcodes 0..84.
12. `spongejit/src/ssa_fact_axes.lua` (lines 1-354) — Fact bundle generation; loops intentionally have no scalar i64 fact axes.
13. `spongejit/runtime/sponjit_l1_interpreter.c` (lines 1-306) — C prototype materializer/runtime; patches fallthrough only.
14. `tests/test_spongejit_l0_bank_coverage.lua` (lines 1-68) — Tests every opcode 0..84 has native L0 bank bytes.
15. `tests/test_spongejit_stencil_lower.lua` (lines 1-129) — Tests residual endpoint/control/projection lowering.
16. `tests/test_spongejit_real_ssa.lua` (lines 1-151) — Tests loop opcodes remain `GenericExit` residual region boundaries.
17. `tests/test_spongejit_bank_materialize.lua` (lines 1-279) — Tests generated bank selection/materialization for ADDI spans.
18. `SPONJIT_FOUNDRY_SSA.md` (lines 1-306) — Foundry design and loop residual boundary stance.
19. `SPONJIT_COPY_LINK_PATCH.md` (lines 1-170, 340-440, 470-570, 700-820) — Native stencil ABI, residual endpoints/control relocs/projection rules.
20. `SPONJIT_RUNTIME_DESIGN.md` (lines 1-150, 600-999) — Future runtime/floor/fallback design.
21. Generated evidence:
   - `build/stencil_bank/build_config.env` (lines 1-7)
   - `build/stencil_bank/grammar_chunk_manifest.json` (line 1)
   - `build/sponbank/sponbank_build_manifest.json` (line 1)
   - `build/sponbank/bank_index.c` (lines 46-61, 523954-524083)

## Key Code

### Residual is emitted by SSA lowering

```lua
-- ssa_lift.lua
local function generic_exit(g, opcode, pc, ev, reason)
    g:generic_exit(opcode, pc, { reason = reason or "generic", event = ev })
    return true
end
```

Unsupported or insufficiently proven opcodes call this with reasons like:

- `opcode_not_specialized`
- `missing_lhs_i64_fact`
- `missing_table_shape_facts`
- `call_boundary`
- `numeric_for_region_boundary`
- `generic_for_region_boundary`

Loop opcodes are explicit residual region boundaries:

```lua
elseif NUMERIC_FOR[op] or GENERIC_FOR[op] then
    terminal = lower_loop_region_boundary(g, op, pc, ev)
```

### SSA residual node

```lua
function Graph:generic_exit(opcode, pc, args)
    args = args or {}
    args.opcode = opcode
    self:add("GenericExit", {
        source = pc,
        effect = "residual",
        args = args,
        exit = self:exit_projection("generic:" .. tostring(opcode), pc),
    })
end
```

### SSA → Stencil residual

```lua
-- ssa_to_stencil.lua
elseif op == "GenericExit" or op == "Residual" then
  st:add("ExitResidual", {
    inputs = ins,
    source = pc,
    args = args,
    exit = n.exit,
    effect = "residual"
  })
```

### Native descriptor/ABI residual vocabulary

```c
// sponbank.h
SPON_EXIT_RESIDUAL = 2
SPON_ENDPOINT_RESIDUAL_EXIT = 4
SPON_CONTROL_RELOC_RESIDUAL = 3
```

### Native byte emitter residual stub

```lua
-- stencil_native_x64.lua
if n.op == "ExitResidual" then return SPON_EXIT_RESIDUAL end
...
if n.op == "ExitResidual" then return "residual" end
```

For `ExitResidual`, emitted code jumps to a local exit stub that writes:

```lua
ctx->exit_kind = SPON_EXIT_RESIDUAL
ctx->exit_pc = source
ctx->exit_op_idx = source - 1
ctx->exit_hole = 0
ret
```

### Materializer only links fallthrough

```lua
-- materialize_native_x64.lua
if edge == "fallthrough" and i < #norm then
  patch_u32(image, site, target - (site + 4))
end
```

Residual/guard/boundary control relocs are not patched to projection/fallback stubs in the current Lua materializer; they remain local stubs.

### Selector L0 fallback

```c
// generated bank_index.c
if (!chosen) {
  chosen = spon_l0_stencil_for_opcode(bc[pc] & 0xffu);
  chosen_f = spon_get_stencil(chosen);
  chosen_s = find_shard(chosen);
  chosen_len = 1;
  if (!chosen_f || ((chosen_f->flags & required_stencil_flags) != required_stencil_flags)) break;
}
```

## Opcode Coverage Facts

Current generated L0 bank evidence:

- opcodes checked: `0..84`
- missing L0 stencils: `0`
- all L0 descriptors have native flag and byte bodies
- L0 semantic classes from generated bank:
  - `8` ok-only native stencils
  - `4` boundary stencils
  - `73` residual stencils

No-fact L0 genuinely implemented without residual:

```text
MOVE
LOADI
LOADK
LOADKX
LOADFALSE
LFALSESKIP
LOADTRUE
LOADNIL
```

No-fact L0 boundary stencils:

```text
JMP
RETURN
RETURN0
RETURN1
```

No-fact L0 residual stencils include:

```text
LOADF
GETUPVAL SETUPVAL GETTABUP GETTABLE GETI GETFIELD
SETTABUP SETTABLE SETI SETFIELD NEWTABLE SELF
most arithmetic without facts
MMBIN MMBINI MMBINK
NOT LEN CONCAT CLOSE TBC TEST TESTSET
CALL TAILCALL
FORLOOP FORPREP TFORPREP TFORCALL TFORLOOP
SETLIST CLOSURE VARARG GETVARG ERRNNIL VARARGPREP EXTRAARG
```

Loop L0 residual reasons:

```text
FORPREP/FORLOOP  -> numeric_for_region_boundary
TFOR*            -> generic_for_region_boundary
```

Fact-specialized native lowering exists for some i64 surfaces:

```text
ADDI
ADDK/SUBK/MULK
BANDK/BORK/BXORK
ADD/SUB/MUL
BAND/BOR/BXOR
UNM/BNOT
EQ/LT/LE
EQI/LTI/LEI/GTI/GEI
```

Surfaces represented as residual or rejected beyond current native boundary include table/shape/array/call payloads, unsupported i64 ops like div/mod/idiv/shifts in native emitter, loops, metamethods, upvalues, close/TBC, vararg, and generic calls.

## Generated Bank Evidence

Current build config:

```text
CHUNKS=128
WORKERS=16
MAX_ARITY=4
MAX_FACT_COMBOS=32
FACT_AXIS_MODE=curated
```

Generated grammar/foundry plan:

```text
sequences=472060
estimated_compiles=8311921
max_sequence_combos=31
```

Generated bank manifest:

```text
stencils=66709
patterns=471158
candidates=631168
chunks=2
```

SQLite bank stats observed:

```text
unique_forms=225560
lowered_stencils=66709
lower_rejected=158851
ssa_ok=6807626
ssa_rejected=1504295
```

Lowered stencil class counts from current `stencil_bank.sqlite`:

```text
total lowered stencils: 66709
residual-containing:    63066
boundary-containing:      838
guarded non-residual:    2099
ok-only:                  706
```

Endpoint/control presence among lowered stencils:

```text
entry endpoints:       66709
ok endpoints:          66709
residual_exit:         63066
guard_exit:            28502
boundary_exit:           838

fallthrough relocs:    66709
residual relocs:       63066
guard_fail relocs:     28502
boundary relocs:         838
SYNCED_FRAME proj:     66003
```

## Relationships

Data flow:

```text
opcode + facts
→ ssa_lift.lua
  - concrete semantics if supported/proven
  - GenericExit residual if unsupported/missing facts
→ ssa_ir.lua
→ ssa_to_stencil.lua
  - GenericExit/Residual => ExitResidual
→ stencil_lower.lua
  - ExitResidual => residual_exit endpoint
→ stencil_native_x64.lua
  - residual control reloc + local residual stub
→ build_bank.lua
  - ABI arrays + selector + L0 table
→ materialize_native_x64.lua / sponjit_l1_interpreter.c
  - copy bytes, patch data, patch fallthrough only
```

Residual effects on facts:

- `ExitResidual`, `ExitBoundary`, and `ExitUnlowered` are hard exits in `ssa_contract.lua`.
- Hard exits kill all slot facts and table/payload facts.
- Generated selector applies transfer after every selected stencil:
  ```c
  facts &= ~killed;
  facts |= produced;
  facts |= checked;
  ```

## Observations

- “L0 coverage” currently means every opcode has a native stencil descriptor and byte body. It does **not** mean every opcode’s semantics are implemented natively.
- Most L0 opcodes are residual native stencils: they enter native code, set `SPON_EXIT_RESIDUAL`, and return.
- Current residual stencils still expose an `ok` endpoint and fallthrough reloc, but their entry path jumps to the residual stub before the local ok stub.
- Current Lua and C materializers only patch success/fallthrough links. Guard/residual/boundary exits are local stubs, not external projection/fallback trampolines yet.
- Loop bytecodes are explicitly treated as structural region boundaries, not scalar opcode stencils.
- Tests assert residual behavior directly:
  - `test_spongejit_stencil_lower.lua` checks residual endpoint/control/projection.
  - `test_spongejit_real_ssa.lua` checks `FOR*`/`TFOR*` become `GenericExit`.
  - `test_spongejit_l0_bank_coverage.lua` checks native L0 bytes, not semantic execution.
- Docs and code agree on the design distinction: residual is a control/projection/fallback concept, not a data hole and not an implementation of the opcode’s native semantics.

## Knowledge-builder Output — 2026-05-31 19:29:18

### What Matters Most for This Problem

- **Opcode coverage truthfulness:** “native L0 coverage” currently means byte-body coverage, not semantic coverage.
- **Residual as semantic boundary:** residual is the main mechanism preserving correctness for unsupported or insufficiently proven opcodes.
- **No-residual meaning:** removing residuals means removing the project’s dominant fallback semantics, not just deleting an exit kind.
- **Fact-flow implications:** residual exits currently kill facts and prevent unsupported semantics from leaking into linked regions.
- **Coverage accounting:** most generated stencils are residual-containing, so headline bank size/coverage overstates native semantic implementation.
- **Copy-Link-Patch validity:** a no-residual architecture must distinguish truly composable native semantics from “native code that immediately exits.”

---

### Non-Obvious Observations

- The current bank has **complete descriptor coverage but sparse semantic coverage**. Every opcode has a native L0 byte body, yet 73 of 85 L0 opcodes are residual stencils. The system can say “all opcodes have native bytes” only because residual stubs count as native byte bodies.

- Residuals are not a minor fallback path; they dominate the corpus. In the generated bank, `63066 / 66709` lowered stencils contain residual exits. That means the current foundry is mostly a classifier and boundary generator, with a comparatively small island of implemented native semantics.

- “Native stencil” currently conflates two different states:
  - executable native bytes implementing opcode semantics,
  - executable native bytes that report `SPON_EXIT_RESIDUAL`.

  A no-residual architecture would need to break that equivalence conceptually, because native executability is not the same as semantic implementability.

- L0 coverage currently hides unsupported semantics behind local residual stubs. Without residuals, L0 coverage would collapse from “all opcodes” to the small subset whose semantics are actually emitted: mostly simple loads, moves, constants, returns/jumps as boundaries, and fact-proven i64 arithmetic/comparison surfaces.

- Residual is the current safety valve for both **unsupported opcodes** and **unsupported fact states**. For example, arithmetic without required i64 facts becomes residual, while arithmetic with facts may lower to native i64 code. Removing residuals would expose the difference between “opcode unsupported” and “opcode supported only under a fact contract.”

- Residuals currently preserve correctness by acting as **hard fact barriers**. `ssa_contract.lua` kills slot/table/payload facts at hard exits. That prevents unsupported semantics from inheriting stale optimistic facts across a fallback boundary.

- A no-residual architecture cannot simply keep the same fact-transfer model. Residual currently provides a conservative “facts are no longer trusted” boundary for unknown semantics. Without it, every selected stencil must either transfer facts precisely or be excluded from native composition.

- Current greedy selection depends on residual L0 fallback for progress. If no candidate matches, generated selector falls back to an L0 stencil. Since most L0 stencils are residual, selection can always make forward progress without implementing semantics. A no-residual architecture loses that hidden progress guarantee.

- “Residual L0” is doing two jobs at once:
  - bytecode coverage for selector completeness,
  - semantic escape for unimplemented behavior.

  Those are different invariants. The current architecture benefits from their overlap, but no-residual Copy-Link-Patch would have to treat them as separate concerns.

- Residual stencils still declare `entry`, `ok`, and `fallthrough` metadata, but their actual entry path jumps to a residual stub before normal success. That means descriptor topology can imply a success continuation even when the executable behavior never reaches it.

- The explicit `fallthrough` relocation exists on every stencil, including residual stencils. For residual stencils, this is mostly structural uniformity, not evidence that the stencil participates in successful linked execution.

- Current materializers patch only fallthrough edges. Guard, residual, and boundary exits remain local stubs. Therefore the current Copy-Link-Patch runtime model is still “link successes, return on anything else,” not full control/projection linking.

- Residuals are currently local-exit semantics, not external fallback trampolines. The byte body writes `ctx->exit_kind = SPON_EXIT_RESIDUAL`, sets resume metadata, and returns. That is less compositional than a full continuation-based architecture.

- A no-residual architecture would make guard and boundary exits proportionally more important. Today residuals absorb most hard cases; without them, remaining exits would need much sharper semantic classification.

- Loop opcodes are explicitly residual region boundaries. This means current L0 loop “coverage” proves only that loops are recognized as non-straight-line boundaries, not that numeric or generic loop semantics are implemented.

- Residuals are also standing in for policy uncertainty. Reasons like `numeric_for_region_boundary`, `generic_for_region_boundary`, `call_boundary`, and `missing_table_shape_facts` encode “not this backend yet,” not just “unknown opcode.”

- The current architecture has a strong invariant: **unsupported semantics may still produce native bytes, but those bytes must only report residual and return**. That invariant is safe but directly conflicts with a no-residual interpretation of native coverage.

- Bank statistics need two separate meanings:
  - descriptor/native-byte coverage,
  - semantic native implementation coverage.

  Current counts mostly measure the former. A no-residual architecture would be judged by the latter.

- The huge residual-containing count means many multi-op stencils are likely “partially useful prefix + residual tail” or “residual boundary included in the form.” Such stencils are valuable for graceful fallback, but weak evidence for fully fused Copy-Link-Patch regions.

- Residuals constrain optimization freedom. Since a residual exit can occur after some native work, frame/projection state must already be safe at that point. This reinforces the synced-frame invariant and blocks more aggressive unsynced-frame seam removal.

- No-residual Copy-Link-Patch raises the semantic bar from “can resume when unsupported” to “do not select unsupported.” That changes the architecture from permissive coverage to selective exactness.

- The existing tests accurately reflect the current contract: they verify native L0 bytes and residual behavior, not native semantic execution for all opcodes. Those tests would not be sufficient evidence for a no-residual architecture.

- Residual is currently a correctness boundary, a coverage shim, a fact killer, a loop/call/table deferral marker, and a selector progress mechanism. Removing it would remove several coupled safety properties at once.

## Planner Output — 2026-05-31 19:40:14

## Goal

Make SponJIT no-residual and semantically truthful: unsupported cases are rejected or implemented exactly, never represented as runtime residual stubs.

## Plan

1. **Write the no-residual contract first**
   - Update docs to define three legal outcomes only:
     - semantically exact inline native stencil
     - semantically exact helper-backed native stencil
     - compile/selection rejection
   - Define that `boundary` is legal only for real VM control transfer, not unsupported fallback.

2. **Introduce semantic coverage metadata**
   - Add a central opcode coverage table mapping every opcode `0..84` to:
     - family
     - implementation mode: `inline`, `helper`, `boundary`, or `unsupported`
     - required facts, if any
     - exact helper id, if helper-backed
     - effects: may call, may yield, may throw, may GC, writes frame, etc.
   - Use this table from SSA lowering, tests, bank metrics, and L0 coverage checks.

3. **Remove residual from SSA**
   - In `spongejit/src/ssa_ir.lua`:
     - remove `Residual` / `GenericExit` as graph nodes
     - remove `residual` as an effect category
     - add explicit graph rejection state, e.g. `g:reject(opcode, pc, reason, event)`
     - add an exact helper node, e.g. `OpcodeHelper`, for opcodes implemented by runtime helpers
   - In `spongejit/src/ssa_lift.lua`:
     - replace all `generic_exit(...)` calls with either:
       - exact helper lowering when coverage table says helper exists
       - `g:reject(...)` when unsupported
     - missing fact cases must not become stencils unless a generic exact helper exists.
   - In `spongejit/src/ssa.lua`:
     - make `SSA.compile(...)` return `ok=false` with structured rejection data when `g.rejected`.
   - Update `ssa_validate.lua`, `ssa_atoms.lua`, `ssa_opt.lua`, and `ssa_contract.lua` to remove residual hard-exit handling.

4. **Remove residual/unlowered from Stencil IR**
   - In `stencil_ir.lua`:
     - remove `ExitResidual`
     - remove `ExitUnlowered` as an accepted operation for unsupported lowering
     - add `OpcodeHelper` / `HelperCall` stencil op.
   - In `ssa_to_stencil.lua`:
     - lower `OpcodeHelper` to helper stencil ops
     - lower real returns/jumps/calls only to typed boundary ops when semantically modeled
     - return lowering errors for unsupported SSA ops; do not synthesize fallback exits.
   - In `stencil_normalize.lua`:
     - remove residual form names and codegen names
     - add canonical names for helper-backed exact ops.

5. **Update descriptor and C ABI**
   - In `sponbank.h` and `stencil_desc.lua`:
     - remove:
       - `SPON_EXIT_RESIDUAL`
       - `SPON_ENDPOINT_RESIDUAL_EXIT`
       - `SPON_CONTROL_RELOC_RESIDUAL`
       - residual endpoint/control enum values
     - add exactness metadata:
       - `SPON_STENCIL_EXACT`
       - semantic implementation enum: inline/helper/boundary
       - helper id/effect metadata
     - ensure L0 descriptors require `SPON_STENCIL_NATIVE | SPON_STENCIL_EXACT`.
   - Treat `SPON_EXIT_UNLOWERED` similarly: remove it as unsupported-runtime fallback, or reserve only for internal fatal materializer error, not normal execution.

6. **Add exact helper infrastructure**
   - Add helper ABI to runtime context:
     - helper table pointer
     - helper availability mask/version
     - bytecode/proto/constant/frame metadata needed by helpers
   - Add native helper call emission in `stencil_native_x64.lua`:
     - call exact helper by id
     - if helper returns OK, continue/fallthrough
     - if helper returns VM boundary/yield/error, set boundary state and return
   - Helpers must execute exact opcode semantics; they are not residual fallback.

7. **Update native emitter**
   - In `stencil_native_x64.lua`:
     - remove residual stub emission
     - remove `op_exit_kind(ExitResidual)`
     - emit only:
       - success fallthrough
       - guard failure
       - real semantic boundary/error/yield paths
       - exact helper calls
   - Ensure any unsupported native op returns lowering error, not a byte body.

8. **Update materializers**
   - In `materialize_native_x64.lua` and `runtime/sponjit_l1_interpreter.c`:
     - reject any descriptor without `SPON_STENCIL_EXACT`
     - reject residual edge ids if encountered
     - patch only semantically valid fallthroughs
     - validate helper availability before building an image
     - fail projection if selector does not cover the requested span.
   - No materializer path may treat missing coverage as executable fallback.

9. **Fix selector semantics**
   - In `build_bank.lua` generated selector:
     - remove implicit `spon_l0_stencil_for_opcode(...)` fallback for no candidate
     - select L0 only through normal candidate/pattern tables
     - if no candidate matches, return incomplete selection status.
   - Add `SponSelectResult` or extend `SponSelectStats` with:
     - status
     - covered_end
     - first_uncovered_pc
     - no_candidate opcode
     - inline/helper/boundary choice counts.
   - Materializers must require full coverage.

10. **Make L0 coverage truthful**
    - Change `test_spongejit_l0_bank_coverage.lua` so L0 coverage means:
      - nonzero descriptor
      - native bytes
      - exact semantic flag
      - no residual/unlowered endpoint/control reloc
      - implementation class is inline/helper/boundary-exact.
    - During migration only, allow `SPON_ALLOW_L0_GAPS=1` to report missing opcodes without passing final strict tests.
    - Final strict mode requires all opcodes `0..84` covered exactly.

11. **Implement opcode families cleanly**
    - **Simple loads/moves/constants**
      - Verify exactness for `MOVE`, `LOADI`, `LOADK`, `LOADKX`, `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`, `LOADNIL`.
      - `LFALSESKIP` and `LOADKX` need real PC/EXTRAARG behavior, not current straight-line simplification.
    - **Arithmetic/bitwise/comparison**
      - Keep fact-proven i64 inline fast paths.
      - Add exact generic helpers for no-fact/metamethod-capable cases.
      - Audit comparison/test opcodes for Lua bytecode skip semantics.
    - **Tables/upvalues/fields/arrays**
      - Exact helper first.
      - Shape/payload-specialized native paths only after payload leases/dependencies are modeled.
    - **Calls/returns/vararg/closure**
      - Exact helper or typed boundary protocol.
      - Boundary must mean real VM transfer, not unsupported fallback.
    - **Branches/tests/jumps**
      - Add real branch/skip/target metadata or exact boundary helpers.
      - Do not link through variable-control stencils until branch edges are modeled.
    - **Numeric/generic loops**
      - No residual loop boundaries.
      - First implementation should be exact loop-shell/helper coverage.
      - Later native cyclic loop lowering can be separate.
    - **TBC/close/errors/metamethod-heavy ops**
      - Exact helpers with conservative fact killing and explicit may-throw/may-yield metadata.

12. **Update fact contracts**
    - In `ssa_contract.lua`:
      - helper-backed exact ops conservatively kill facts they may invalidate
      - inline stencils retain precise produced/checked/killed facts
      - boundary helpers kill facts as appropriate
      - no residual hard-exit transfer remains.

13. **Update foundry and metrics**
    - In `worker_compile.lua`:
      - record SSA rejection reasons by opcode/fact reason
      - distinguish compile rejection from lower rejection.
    - In `dedupe_normal_forms.lua`:
      - lower only exact descriptors
      - record semantic implementation class.
    - In `build_bank.lua` manifest:
      - add counts for inline/helper/boundary exact stencils
      - add L0 exact coverage count
      - add unsupported opcode/fact rejection table
      - fail strict build if any residual/unlowered descriptor exists.

14. **Update generated artifacts**
    - Delete stale generated banks after ABI changes:
      - `spongejit/build/stencil_bank`
      - `spongejit/build/sponbank`
    - Rebuild only after no-residual schema is in place.
    - Generated manifests must include no-residual metrics.

15. **Update tests**
    - Add `test_spongejit_no_residual.lua`
      - grep maintained source/docs/generated ABI for forbidden residual runtime tokens.
    - Update:
      - `test_spongejit_real_ssa.lua`
      - `test_spongejit_stencil_desc.lua`
      - `test_spongejit_stencil_lower.lua`
      - `test_spongejit_native_stencil_bytes.lua`
      - `test_spongejit_materialize_native.lua`
      - `test_spongejit_bank_materialize.lua`
      - `test_spongejit_l0_bank_coverage.lua`
    - Add helper-specific tests:
      - helper descriptor validation
      - helper byte execution
      - helper fact killing
      - selector chooses inline when facts exist and helper when generic exact semantics are needed.
    - Add selector no-progress tests:
      - unsupported opcode with no helper returns no full selection
      - materializer rejects partial selection.

16. **Verification commands**

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_desc.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_lower.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_materialize_native.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_bank_materialize.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_l0_bank_coverage.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_no_residual.lua

(cd experiments/lua_interpreter_vm/spongejit && make test)
(cd experiments/lua_interpreter_vm/spongejit && make stencils && make bank)
```

Final grep gate:

```sh
rg -n "Residual|residual|SPON_EXIT_RESIDUAL|SPON_ENDPOINT_RESIDUAL|SPON_CONTROL_RELOC_RESIDUAL|ExitResidual|GenericExit" \
  experiments/lua_interpreter_vm/spongejit \
  experiments/lua_interpreter_vm/SPONJIT_*.md
```

Expected final result: no maintained-runtime/design matches.

## Files to Modify

- `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md` - remove residual design category; define exact/helper/reject.
- `experiments/lua_interpreter_vm/SPONJIT_FOUNDRY_SSA.md` - update foundry contract and coverage meaning.
- `experiments/lua_interpreter_vm/SPONJIT_RUNTIME_DESIGN.md` - remove residual exit/linking model.
- `experiments/lua_interpreter_vm/SPONJIT_TIER2_PLANNER_SPEC.md` - replace residual edges with unsupported rejection / exact boundary.
- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` - ABI enum/struct updates.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` - remove residual nodes/effects; add rejection/helper model.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` - replace generic exits with helper or rejection.
- `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` - expose structured rejection.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_validate.lua` - remove residual validation.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua` - remove residual reopen fallback.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` - replace residual hard-barrier assumptions.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_contract.lua` - exact/helper fact transfer.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` - no `ExitResidual`/`ExitUnlowered`; add helper lowering.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` - remove residual op vocabulary.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_normalize.lua` - remove residual forms.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua` - exact semantic descriptor validation.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua` - reject unsupported; lower helpers.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua` - remove residual stubs; add helper calls.
- `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua` - reject non-exact/partial plans.
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` - rejection metrics.
- `experiments/lua_interpreter_vm/spongejit/src/dedupe_normal_forms.lua` - exact-only lowering metrics.
- `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` - no fallback selector; exact coverage manifest.
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.c` - no residual projection; helper validation.
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.h` - helper/runtime ABI.
- SpongeJIT tests listed above.

## New Files

- `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` - authoritative opcode coverage table.
- `experiments/lua_interpreter_vm/spongejit/src/helper_abi.lua` - Lua-side helper IDs/effects.
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_helpers.h` - C helper ABI.
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_helpers.c` - exact helper dispatch skeleton/tests.
- `experiments/lua_interpreter_vm/spongejit/src/report_semantic_coverage.lua` - coverage/manifest reporter.
- `experiments/lua_interpreter_vm/tests/test_spongejit_no_residual.lua` - no-residual invariant test.
- `experiments/lua_interpreter_vm/tests/test_spongejit_helper_stencils.lua` - helper descriptor/execution tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_selector_no_fallback.lua` - selector failure/coverage tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_semantic_l0_coverage.lua` - exact L0 coverage.

## Final Invariants

- No maintained runtime/design category named residual.
- Unsupported opcode/fact cases produce compile/lower/select failure, not stencils.
- Every native stencil has exact semantic metadata.
- L0 coverage means exact semantic coverage.
- Selector has no hidden progress fallback.
- Materializer links only exact native stencils.
- Helper-backed stencils are exact semantic implementations, not fallback stubs.
- Missing coverage appears in metrics as unsupported, never as native bytes.
- Generated bank contains no residual endpoints, relocs, exit kinds, or stubs.

## Risks

- Exact helper coverage for all opcodes may require substantial VM/runtime ABI work.
- Existing “native L0 coverage” numbers will drop until helpers are implemented.
- Boundary exits can become residual-by-another-name unless tightly specified.
- Lua loop/call/TBC semantics are subtle; use exact helpers before native specialization.
- ABI changes require deleting and regenerating all bank artifacts.

## Edit-planner Output — 2026-05-31 19:50:29

### Precondition Checks

- Confirm current grep still finds residual runtime/design tokens:
  ```sh
  rg -n "Residual|residual|GenericExit|ExitUnlowered|SPON_EXIT_RESIDUAL|SPON_ENDPOINT_RESIDUAL|SPON_CONTROL_RELOC_RESIDUAL" \
    experiments/lua_interpreter_vm/spongejit experiments/lua_interpreter_vm/SPONJIT_*.md
  ```
- Confirm generated artifacts are treated as disposable:
  - `experiments/lua_interpreter_vm/spongejit/build/stencil_bank`
  - `experiments/lua_interpreter_vm/spongejit/build/sponbank`
- Confirm current terminology is `SponStencil*`, not `SponTile*`/fragment.
- Do **not** add opcode helper files (`helper_abi.lua`, `OpcodeHelper`, `HelperCall`, C opcode helper dispatch). Legitimate runtime primitives such as mmap/copy/patch remain allowed.

---

### Files to Modify

#### `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` *(new)*

**Goal**: Add one authoritative no-helper semantic coverage table.

**Contents sketch**:
```lua
local Constants = require("experiments.lua_interpreter_vm.src.constants")

local M = {}

M.MODE = {
  inline = "inline",          -- real native semantic lowering
  boundary = "boundary",      -- exact VM handoff before real control-transfer opcode
  unsupported = "unsupported",
}

local INLINE_NO_FACT = {
  MOVE=true, LOADI=true, LOADFALSE=true, LOADTRUE=true, LOADNIL=true, LOADK=true,
}

local INLINE_FACTED = {
  ADDI=true,
  ADD=true, SUB=true, MUL=true,
  ADDK=true, SUBK=true, MULK=true,
  BAND=true, BOR=true, BXOR=true,
  BANDK=true, BORK=true, BXORK=true,
  UNM=true, BNOT=true,
}

local BOUNDARY = {
  JMP=true, RETURN=true, RETURN0=true, RETURN1=true,
  CALL=true, TAILCALL=true,
  FORPREP=true, FORLOOP=true, TFORPREP=true, TFORCALL=true, TFORLOOP=true,
}

function M.classify(op) ... end
function M.is_inline_candidate(op) ... end
function M.is_boundary(op) ... end
function M.all_opcode_names() ... end
return M
```

**Patterns**:
- No `helper` mode.
- Unsupported means compile/lower/select failure, not fallback.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua`

**Goal**: Remove residual SSA nodes/effect and add structured rejection plus explicit boundary nodes.

**Edit blocks**:
1. **Lines 26-30**: Remove `residual` from `EFFECTS`.
   - After:
     ```lua
     heap_read = true, heap_write = true, gc_barrier = true, call = true,
     branch = true, return_ = true,
     ```

2. **Lines 52-67**: Remove `Residual` and `GenericExit` from `CODEGEN_OP`; add:
   ```lua
   Boundary = "boundary",
   ```

3. **Lines 82-84**: Replace hard barrier table.
   - Before includes `Residual = true, GenericExit = true`.
   - After:
     ```lua
     local HARD_BARRIER = {
       Call = true, KnownCall = true, TailCall = true, Boundary = true, Jump = true,
     }
     ```

4. **Lines 95-107 `Graph.new`**: Add rejection fields:
   ```lua
   rejected = false,
   rejections = {},
   ```

5. **After `Graph:exit_projection` around line 170**: Add:
   ```lua
   function Graph:reject(opcode, pc, reason, event)
     self.rejected = true
     self.rejections[#self.rejections + 1] = {
       opcode = opcode, pc = pc or 0, reason = reason or "unsupported", event = event,
     }
     return true
   end

   function Graph:boundary(opcode, pc, event, reason)
     return self:add("Boundary", {
       source = pc,
       effect = "branch",
       args = { opcode = opcode, reason = reason or "vm_boundary", event = event },
       exit = self:exit_projection("boundary:" .. tostring(opcode), pc),
     })
   end
   ```

6. **Lines 352-383**: Delete `Graph:residual` and `Graph:generic_exit`.

7. **Lines 398-404 `Graph:validate`**:
   - Remove residual effect check.
   - Add:
     ```lua
     if n.op == "Boundary" and not n.exit then errors[#errors + 1] = "Boundary without exit at node " .. n.id end
     if n.effect == "call" and not n.exit then errors[#errors + 1] = "call without exit at node " .. n.id end
     ```

**Danger zones**:
- `Graph:reject` must not create a node.
- `Boundary` is not unsupported fallback; only `ssa_lift.lua` may create it for whitelisted VM control-transfer opcodes.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua`

**Goal**: Replace residual progress with rejection or exact boundary.

**Edit blocks**:
1. **Lines 1-5 comment**: Replace “GenericExit” wording with “structured rejection or exact VM boundary”.

2. **After imports lines 7-8**:
   ```lua
   local Coverage = require("src.opcode_coverage")
   ```

3. **Lines 58-61**: Replace `generic_exit` helper with:
   ```lua
   local function reject(g, opcode, pc, ev, reason)
     return g:reject(opcode, pc, reason or "unsupported_opcode_or_fact", ev)
   end

   local function boundary(g, opcode, pc, ev, reason)
     g:boundary(opcode, pc, ev, reason)
     return true
   end
   ```

4. **Lines 121-123 `lower_loop_region_boundary`**:
   ```lua
   return boundary(g, op, pc, ev, reason)
   ```

5. **Lines 132-180 arithmetic/unary lowering**:
   - Replace every `generic_exit(...)` with `reject(...)`.
   - Add supported native i64 op filter before creating `I64BinOp`:
     ```lua
     local SUPPORTED_I64_BIN = { ADD=true, SUB=true, MUL=true, BAND=true, BOR=true, BXOR=true }
     if not SUPPORTED_I64_BIN[real_op] then
       return reject(g, op, pc, ev, "i64_op_not_semantically_lowered")
     end
     ```
   - For `lower_i64_cmp`, replace whole body with:
     ```lua
     return reject(g, op, pc, ev, "comparison_control_not_lowered")
     ```
     until branch/skip endpoints are implemented.

6. **Lines 185-198 `lower_load`**:
   - Keep `LOADI`, `LOADTRUE`, `LOADFALSE`, `LOADNIL`, `LOADK`.
   - Reject `LFALSESKIP`, `LOADF`, `LOADKX`:
     ```lua
     elseif op == "LFALSESKIP" then return reject(g, op, pc, ev, "lfalseskip_branch_not_lowered")
     elseif op == "LOADF" then return reject(...)
     elseif op == "LOADKX" then return reject(...)
     ```
   - Replace final `generic_exit` with `reject`.

7. **Lines 209-287 table/array/call lowering**:
   - Replace all missing fact / unsupported payload `generic_exit` calls with `reject`.
   - Replace `lower_call` with exact boundary for all calls:
     ```lua
     local function lower_call(g, op, pc, ev)
       return boundary(g, op, pc, ev, "call_boundary")
     end
     ```

8. **Lines 299-326 main dispatch**:
   - Before dispatch, optionally classify:
     ```lua
     local cov = Coverage.classify(op)
     ```
   - Keep existing inline dispatch for supported candidates.
   - For `CALL`, `TAILCALL`, loops use boundary.
   - Replace final `else` with:
     ```lua
     else terminal = reject(g, op, pc, ev, "opcode_not_supported")
     end
     ```
   - After each iteration:
     ```lua
     if g.rejected then break end
     ```

**Danger zones**:
- Do not create boundary for arbitrary unsupported opcodes like `GETUPVAL`, `GETTABLE`, `POW`, `LOADF`.
- Missing facts for arithmetic must reject, not boundary.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa.lua`

**Goal**: Propagate structured rejection without lowering to Stencil IR.

**Edit blocks**:
1. **Before `summarize` line 96**: Add `rejection_errors(g)` helper converting `g.rejections` to strings.

2. **Lines 96-134 `summarize`**:
   - At top:
     ```lua
     if g.rejected then
       return {
         ok = false,
         errors = rejection_errors(g),
         rejections = copy_array(g.rejections),
         graph = g,
         factset = g.factset,
         stencil = nil,
         stencil_form = {},
         stencil_hash = nil,
         stencil_key = nil,
         stencil_ops = {},
         stencil_holes = {},
         slotmaps = {},
         active_node_specs = active_node_specs(g),
         semantic_ops = semantic_ops(g),
         checked_facts = {},
         checked_fact_objects = {},
         deps = {},
         projection = { ok = false, exit_obligations = 0, virtual_values = 0, reasons = {} },
         stats = g.stats,
         source_ops = copy_array(source_ops or {}),
       }
     end
     ```
   - Only call `Lower.lower` after this block.

3. **Lines 142-147 `compile` / `compile_nodes`**:
   - `Opt.optimize` should still be safe, but may be skipped if `g.rejected`.
   - Ensure returned result includes `rejections`.

**Danger zones**:
- Worker relies on `r.ok`; rejected compiles must not have fake empty native forms.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua`

**Goal**: Reopened unknown nodes reject; no synthetic residual/unlowered recovery.

**Edit blocks**:
1. **Lines 52-58 synthetic exit fallback**:
   - Remove `spec.op == "Residual"` case.
   - Keep guard/call fallback only.

2. **Before `g:add` around line 59**:
   ```lua
   if not IR.CODEGEN_OP[spec.op or spec.codegen_op] then
     g:reject(spec.op or spec.codegen_op, spec.source or pc, "unknown_reopened_node", spec)
     break
   end
   ```

**Danger zones**:
- `MysteryNativeOp` must now produce `ok=false`, not `ExitUnlowered`.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_validate.lua`

**Goal**: Treat rejection as compile failure; remove residual validation.

**Edit blocks**:
1. **After existing `g.invalid` block lines 8-13**:
   ```lua
   if g.rejected then
     for _, r in ipairs(g.rejections or {}) do
       add(errors, string.format("rejected %s at pc %s: %s", tostring(r.opcode), tostring(r.pc), tostring(r.reason)))
     end
     return false, errors
   end
   ```

2. **Lines 22-24**:
   - Remove `Residual` / `GenericExit` from exit projection check.
   - Keep call nodes.

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua`

**Goal**: Remove residual barrier assumptions.

**Edit blocks**:
1. **Line 105 comment**: Replace “Calls/residuals” with “Calls/boundaries”.

2. **Line 166 comment**: Replace “another heap write/call/residual” with “another heap write/call/boundary”.

3. **Line 236 `M.optimize`**:
   ```lua
   if g.invalid or g.rejected then return g end
   ```

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_contract.lua`

**Goal**: Remove residual/unlowered hard exits.

**Edit blocks**:
1. **Lines 50-52**:
   - Replace:
     ```lua
     return n.op == "ExitResidual" or n.op == "ExitBoundary" or n.op == "ExitUnlowered"
     ```
   - With:
     ```lua
     return n.op == "ExitBoundary"
     ```

---

#### `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua`

**Goal**: Lower only supported SSA or exact VM boundaries; no residual/unlowered stencil ops.

**Edit blocks**:
1. **Lines 249-255**:
   - Remove `GenericExit`/`Residual` branch.
   - Add `Boundary` to boundary branch:
     ```lua
     elseif op == "Boundary" or op == "Jump" or op == "Return1" or op == "Return0" or op == "Call" or op == "KnownCall" or op == "TailCall" then
       st:add("ExitBoundary", { inputs = ins, source = pc, args = { op = op, opcode = args.opcode, reason = args.reason }, exit = n.exit, effect = n.effect or "branch" })
     else
       error("unsupported SSA op reached stencil lowering: " .. tostring(op))
     end
     ```

**Danger zones**:
- Do not synthesize `ExitUnlowered`.

---

#### `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua`

**Goal**: Remove residual/unlowered Stencil IR operations.

**Edit blocks**:
1. **Lines 15-18 `KNOWN_OP`**:
   - Remove `ExitResidual = true` and `ExitUnlowered = true`.
   - Keep `ExitBoundary = true`.

---

#### `experiments/lua_interpreter_vm/spongejit/src/stencil_normalize.lua`

**Goal**: Remove residual/unlowered canonical forms.

**Edit blocks**:
1. **Lines 31-34 `IMPORTANT`**:
   - Remove `ExitResidual` and `ExitUnlowered`.

2. **Lines 42-45 `CODEGEN_OP`**:
   - Remove `ExitResidual = "residual_boundary"` and `ExitUnlowered = "unlowered_boundary"`.

---

#### `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua`

**Goal**: Only lower exact native stencils and exact boundaries.

**Edit blocks**:
1. **Lines 11-31 `SUPPORTED_OP`**:
   - Remove `CmpI64` if comparison is not implemented with branch semantics.
   - Remove `ExitResidual` and `ExitUnlowered`.
   - Keep `ExitBoundary`.

2. **Lines 91-95 `EXIT_KIND_BY_OP`**:
   - Replace with:
     ```lua
     local EXIT_KIND_BY_OP = {
       ExitBoundary = "boundary_exit",
     }
     ```

3. **Lines 139-158 descriptor construction**:
   - Add:
     ```lua
     exact = true,
     semantic_mode = "inline",
     ```
   - If stencil ops contain only/terminal `ExitBoundary`, set `semantic_mode = "boundary"`.

**Danger zones**:
- Boundary descriptors must represent VM handoff, not arbitrary unsupported fallback.

---

#### `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua`

**Goal**: Remove residual/unlowered ABI categories and add exactness flag.

**Edit blocks**:
1. **Lines 30-38 endpoint enums**:
   - Remove `residual_exit`, `unlowered_exit`.
   - New IDs:
     ```lua
     M.ENDPOINT_KIND_ID = { entry = 1, ok = 2, guard_exit = 3, boundary_exit = 4 }
     ```

2. **Lines 54-61 control relocs**:
   - Remove `residual`.
   - New IDs:
     ```lua
     M.CONTROL_RELOC_KIND_ID = { fallthrough = 1, guard_fail = 2, boundary = 3, projection_stub = 4 }
     ```

3. **Line 65 `STENCIL_FLAG`**:
   ```lua
   M.STENCIL_FLAG = { ABSTRACT = 1, NATIVE = 2, PUC_PATCHABLE = 4, EXACT = 8, BOUNDARY = 16 }
   ```

4. **Lines 108-109 role word guards**:
   - Remove `residual` from `DATA_WORDS_AS_CONTROL`.
   - Keep `boundary`.

5. **Lines 206-236 `M.stencil`**:
   - Add fields:
     ```lua
     exact = t.exact == true,
     semantic_mode = t.semantic_mode or (t.executable and "inline" or "abstract"),
     ```
   - Do not infer exactness automatically except where caller passes it.

6. **Lines 290-374 `validate_stencil`**:
   - If `f.executable`, require:
     ```lua
     if f.exact ~= true then err(errors, "native stencil missing exact semantic flag") end
     if f.semantic_mode ~= "inline" and f.semantic_mode ~= "boundary" then err(...) end
     ```
   - Reject any endpoint/control kind containing residual/unlowered as unknown.

7. **Lines 440-476 ABI lowering**:
   - Include exact/boundary flags:
     ```lua
     local flags = f.executable and M.STENCIL_FLAG.NATIVE or M.STENCIL_FLAG.ABSTRACT
     if f.exact then flags = bit.bor(flags, M.STENCIL_FLAG.EXACT) end
     if f.semantic_mode == "boundary" then flags = bit.bor(flags, M.STENCIL_FLAG.BOUNDARY) end
     ```

---

#### `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua`

**Goal**: Remove residual/unlowered stubs.

**Edit blocks**:
1. **Lines 21-25 constants**:
   - Remove `SPON_EXIT_RESIDUAL` and `SPON_EXIT_UNLOWERED`.
   - Renumber only if coordinated with `sponbank.h`; recommended:
     ```lua
     local SPON_EXIT_NONE = 0
     local SPON_EXIT_GUARD = 1
     local SPON_EXIT_BOUNDARY = 2
     local SPON_EXIT_RUNTIME_ERROR = 3
     ```

2. **Lines 273-285**:
   - Replace `op_exit_kind` with guard/boundary only.
   - Replace `control_edge_kind` with:
     ```lua
     if n.op == "GuardI64" then return "guard_fail" end
     return "boundary"
     ```

3. **Lines 527-545**:
   - Change branch to:
     ```lua
     elseif op == "ExitBoundary" then
     ```
   - No `ExitResidual` or `ExitUnlowered`.

---

#### `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua`

**Goal**: Reject non-exact stencils and remove residual edge vocabulary.

**Edit blocks**:
1. **Lines 20-22 `CONTROL_EDGE_BY_ID`**:
   ```lua
   local CONTROL_EDGE_BY_ID = {
     [1] = "fallthrough", [2] = "guard_fail", [3] = "boundary", [4] = "projection_stub",
   }
   ```

2. **Lines 170-184 `materialize` entry validation**:
   - After executable/code check, add:
     ```lua
     local flags = tonumber(st.abi and st.abi.stencil and st.abi.stencil.flags or st.flags or 0) or 0
     if st.exact == false or (st.exact ~= true and bit.band(flags, 8) == 0) then
       error("cannot materialize non-exact stencil at entry " .. tostring(i))
     end
     ```

3. **Lines 210-222 control loop**:
   - Explicitly reject unknown residual edge if seen:
     ```lua
     if edge == "residual" then error("residual control edge is retired") end
     ```

---

#### `experiments/lua_interpreter_vm/spongejit/include/sponbank.h`

**Goal**: C ABI no longer exposes residual/unlowered progress.

**Edit blocks**:
1. **Lines 29-34 exit enum**:
   - Replace with:
     ```c
     enum {
       SPON_EXIT_NONE = 0,
       SPON_EXIT_GUARD = 1,
       SPON_EXIT_BOUNDARY = 2,
       SPON_EXIT_RUNTIME_ERROR = 3,
       SPON_EXIT_BARRIER = 4
     };
     ```

2. **Lines 56-58 stencil flags**:
   ```c
   SPON_STENCIL_EXACT = 1u << 3,
   SPON_STENCIL_BOUNDARY = 1u << 4
   ```

3. **Lines 100-105 endpoint enum**:
   - Remove residual/unlowered:
     ```c
     SPON_ENDPOINT_ENTRY = 1,
     SPON_ENDPOINT_OK = 2,
     SPON_ENDPOINT_GUARD_EXIT = 3,
     SPON_ENDPOINT_BOUNDARY_EXIT = 4
     ```

4. **Lines 124-128 control enum**:
   - Remove residual:
     ```c
     SPON_CONTROL_RELOC_FALLTHROUGH = 1,
     SPON_CONTROL_RELOC_GUARD_FAIL = 2,
     SPON_CONTROL_RELOC_BOUNDARY = 3,
     SPON_CONTROL_RELOC_PROJECTION_STUB = 4
     ```

5. **Lines 42-47 `SponSelectStats`**:
   - Extend:
     ```c
     uint32_t status;
     uint32_t covered_end;
     uint32_t first_uncovered_pc;
     uint32_t no_candidate_opcode;
     ```
   - Add enum:
     ```c
     enum { SPON_SELECT_OK = 0, SPON_SELECT_NO_CANDIDATE = 1, SPON_SELECT_CAPACITY = 2 };
     ```

---

#### `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua`

**Goal**: Generated selector must not use L0 as hidden progress fallback.

**Edit blocks**:
1. **Lines 391-439 generated `select_flow_impl` string**:
   - Remove block lines 422-427:
     ```c
     if (!chosen) { chosen = spon_l0_stencil_for_opcode(...); ... }
     ```
   - Replace with:
     ```c
     if (!chosen) {
       if (stats) {
         stats->status = SPON_SELECT_NO_CANDIDATE;
         stats->covered_end = pc;
         stats->first_uncovered_pc = pc;
         stats->no_candidate_opcode = bc ? (bc[pc] & 0xffu) : 0;
       }
       break;
     }
     ```
   - At function start initialize `status=SPON_SELECT_OK`, `covered_end=start`.
   - After loop set `covered_end=pc`; if `pc == end`, status OK.

2. **Line 632 `add_pattern_candidate`**:
   - Keep L0 table population only for exact native descriptors.
   - To do this, pass descriptor flags into `add_pattern_candidate` from `load_pattern_aliases`.

3. **Lines 638-650 `load_pattern_aliases` SQL**:
   - Select `u.stencil_json`.
   - Decode flags and pass to `add_pattern_candidate`.
   - Do not set L0 for non-exact descriptors.

4. **Lines 690-707 summary**:
   - Add manifest metrics:
     - `l0_exact_covered`
     - `l0_missing`
     - `semantic_inline_stencils`
     - `semantic_boundary_stencils`
   - Do not fail build on missing L0 unless `SPON_STRICT_SEMANTIC_L0=1`.

---

#### `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua`

**Goal**: Record compile rejections as first-class metrics.

**Edit blocks**:
1. **DB schema around lines 52-73**:
   - Add table:
     ```sql
     CREATE TABLE ssa_rejections (
       reason TEXT PRIMARY KEY,
       count INTEGER NOT NULL
     );
     ```

2. **Around lines 92-146 loop**:
   - Add local table `rejection_counts = {}`.
   - When `not r.ok`, increment by each `r.rejections[i].reason` or `"unknown"`.

3. **Before COMMIT around line 157**:
   - Insert rejection counts into `ssa_rejections`.

---

#### `experiments/lua_interpreter_vm/spongejit/src/dedupe_normal_forms.lua`

**Goal**: Preserve rejection metrics and ensure only exact descriptors are banked.

**Edit blocks**:
1. **Schema lines 42-77**:
   - Add aggregate table `ssa_rejections(reason TEXT PRIMARY KEY, count INTEGER NOT NULL)`.

2. **Worker merge loop lines 89-132**:
   - Merge worker `ssa_rejections`.

3. **Lowering loop lines 156-176**:
   - Assert lower successes are exact:
     ```lua
     if lower.ok and lower.stencil.exact ~= true then error("lowered non-exact stencil") end
     ```

4. **Stats lines 190-207**:
   - Add `semantic_exact_stencils`, `semantic_lower_failures`.

---

#### `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.c`

**Goal**: Runtime projection only accepts exact native stencils; no residual/unlowered returns.

**Edit blocks**:
1. **Lines 216-218 selector call**:
   - Required flags:
     ```c
     SPON_STENCIL_NATIVE | SPON_STENCIL_EXACT
     ```

2. **Lines 222-228 descriptor validation**:
   - Require exact:
     ```c
     if (!d || (d->flags & (SPON_STENCIL_NATIVE | SPON_STENCIL_EXACT)) != (SPON_STENCIL_NATIVE | SPON_STENCIL_EXACT) || d->size == 0) return -1;
     ```

3. **Lines 281-294**:
   - Replace `SPON_EXIT_UNLOWERED` returns with `SPON_EXIT_RUNTIME_ERROR`.

4. **Lines 260-271 control reloc patching**:
   - If `r->edge_kind == SPON_CONTROL_RELOC_RESIDUAL`, no longer possible; add default rejection for unknown edge kinds.

---

#### `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.h`

**Goal**: Match exit enum changes.

**Edit blocks**:
- No struct changes required.
- Update comments to say project fails if selector cannot fully cover span; no fallback stencil is synthesized.

---

#### `experiments/lua_interpreter_vm/spongejit/Makefile`

**Goal**: Run no-residual source gate and new semantic coverage tests.

**Edit blocks**:
1. **`test` target lines 24-33**:
   - Add:
     ```make
     cd $(ROOT)/.. && $(LUAROCKS_ENV) $(LUA) experiments/lua_interpreter_vm/tests/test_spongejit_no_residual.lua
     ```

2. **`test-bank` target lines 35-38**:
   - Replace `test_spongejit_l0_bank_coverage.lua` with `test_spongejit_semantic_l0_coverage.lua`.
   - Add `test_spongejit_selector_no_fallback.lua`.

---

### Tests to Update/Add

#### Update `tests/test_spongejit_real_ssa.lua`

- Lines 149-160 loop section:
  - Replace `GenericExit` expectations with `Boundary`.
  - Assert `prep.ok == true`, `prep_node.op == "Boundary"`, reason `numeric_for_region_boundary`.
- Add tests:
  ```lua
  local bad = SSA.compile({ { op = "ADDI", a=1,b=1,c=1 } }, {})
  assert_true(not bad.ok)
  assert_true((bad.rejections or {})[1].reason == "missing_lhs_i64_fact")
  ```
- Change `MysteryNativeOp` reopen expectation to `ok=false`.

#### Update `tests/test_spongejit_stencil_lower.lua`

- Delete residual/unlowered blocks lines 108-126.
- Add:
  - `POW` no facts rejects at SSA compile.
  - `LFALSESKIP` rejects until branch skip lowering exists.
  - `RETURN1` still lowers as `boundary_exit`.
  - Every lowered native stencil has `exact == true` and ABI flag `SPON_STENCIL_EXACT`.

#### Update `tests/test_spongejit_stencil_desc.lua`

- Remove residual/unlowered endpoint acceptance.
- Add:
  - native executable descriptor without `exact=true` fails.
  - endpoint kind `residual_exit` fails unknown.
  - control reloc `residual` fails unknown.

#### Update `tests/test_spongejit_native_stencil_bytes.lua`

- Update exit enum numbers if changed.
- Assert ADDI descriptor has exact flag.
- Add unsupported compile case for `LOADF` or `POW`.

#### Update `tests/test_spongejit_materialize_native.lua`

- Ensure `lower()` asserts `fr.stencil.exact == true`.
- Add materializer rejection for a copied stencil with `exact=false`.

#### Update `tests/test_spongejit_bank_materialize.lua`

- FFI `SponSelectStats` struct must include new fields.
- `select_entries` must assert `pc == #ops`; if not, include stats in error.
- Add unsupported selection case:
  - bytecode `[LOADF]` or `[ADDI]` with no i64 facts.
  - Assert selector returns `out_n == 0` or `stats.status == SPON_SELECT_NO_CANDIDATE`.
  - Assert no L0 fallback choice appears.

#### Replace/retire `tests/test_spongejit_l0_bank_coverage.lua`

New file: `tests/test_spongejit_semantic_l0_coverage.lua`.

**Purpose**:
- Generated L0 entries may have gaps during transition.
- Any existing L0 entry must be native + exact + no residual/unlowered endpoint/control.
- `SPON_STRICT_SEMANTIC_L0=1` requires all opcodes `0..84`.

#### Add `tests/test_spongejit_selector_no_fallback.lua`

**Purpose**:
- Generated selector does not synthesize L0 fallback.
- Missing coverage yields partial/no selection status.

#### Add `tests/test_spongejit_no_residual.lua`

**Purpose**:
- Scan maintained SpongeJIT source and `SPONJIT_*.md`.
- Forbidden tokens:
  - `SPON_EXIT_RESIDUAL`
  - `SPON_ENDPOINT_RESIDUAL`
  - `SPON_CONTROL_RELOC_RESIDUAL`
  - `ExitResidual`
  - `GenericExit`
  - `residual_boundary`
  - `unlowered_boundary`
  - `OpcodeHelper`
  - `HelperCall`
  - `SPON_STENCIL_HELPER`
- Exclude generated `build/` and the test file itself.

---

### Docs to Modify

#### `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md`

- Lines 100-118: remove `RESIDUAL` endpoint/control target; remove `helper address` as opcode escape wording.
- Lines 500-514: remove `is_residual`; replace with `implementation = inline|boundary`.
- Lines 719-720: replace “guard/residual/projection” with “guard/boundary/projection”.
- Add normative rule:
  > Unsupported opcode/fact cases MUST reject at compile, lower, or select time. They MUST NOT be represented as native stencils that immediately exit.

#### `experiments/lua_interpreter_vm/SPONJIT_FOUNDRY_SSA.md`

- Lines 31-36 loop stance: replace “residual region boundaries” with “exact VM boundary handoff or unsupported until loop-region lowering”.
- Lines 190-200 current surface: remove “residual/unlowered”.
- Add semantic coverage section explaining gaps are expected during transition.

#### `experiments/lua_interpreter_vm/SPONJIT_RUNTIME_DESIGN.md`

- Remove residual/unlowered edge/runtime outcome sections around lines 383-399, 722-725, 1165-1167.
- Replace with:
  - `GuardExitEdge`
  - `BoundaryExitEdge`
  - `RuntimeError` only for non-opcode materializer/runtime failure.

#### `experiments/lua_interpreter_vm/SPONJIT_TIER2_PLANNER_SPEC.md`

- Lines 302-314 endpoint alternatives: remove `ResidualExit`, `UnloweredExit`.
- Lines 375-392 reloc/edge alternatives: remove residual/unlowered.
- Add planner rejection variant:
  ```text
  UnsupportedOpcodeOrFacts(op, reason)
  ```

---

### Generated Artifacts

Delete after ABI/schema edits, before rebuild:

```sh
rm -rf experiments/lua_interpreter_vm/spongejit/build/stencil_bank
rm -rf experiments/lua_interpreter_vm/spongejit/build/sponbank
```

---

### Order of Operations

1. Add `src/opcode_coverage.lua`.
2. Update SSA rejection/boundary model: `ssa_ir.lua`, `ssa_lift.lua`, `ssa.lua`, `ssa_validate.lua`, `ssa_atoms.lua`, `ssa_opt.lua`.
3. Run SSA tests; fix compile rejection behavior.
4. Remove residual/unlowered from Stencil IR/normalization/lowering/native emitter.
5. Update descriptor ABI and C header.
6. Update Lua materializer.
7. Update worker/dedupe/build-bank selector semantics.
8. Update runtime C prototype.
9. Update tests.
10. Update docs.
11. Delete generated artifacts and rebuild.
12. Run full verification.

---

### Verification Commands

Incremental:

```sh
luajit experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_desc.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_stencil_lower.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_materialize_native.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_no_residual.lua
```

Build/bank:

```sh
(cd experiments/lua_interpreter_vm/spongejit && make stencils && make bank)
luajit experiments/lua_interpreter_vm/tests/test_spongejit_semantic_l0_coverage.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_selector_no_fallback.lua
luajit experiments/lua_interpreter_vm/tests/test_spongejit_bank_materialize.lua
(cd experiments/lua_interpreter_vm/spongejit && make test-c-interp)
```

Transitional strict gate:

```sh
SPON_STRICT_SEMANTIC_L0=1 luajit experiments/lua_interpreter_vm/tests/test_spongejit_semantic_l0_coverage.lua
```

Final grep gate:

```sh
rg -n "Residual|residual|GenericExit|ExitResidual|ExitUnlowered|SPON_EXIT_RESIDUAL|SPON_ENDPOINT_RESIDUAL|SPON_CONTROL_RELOC_RESIDUAL|OpcodeHelper|HelperCall|SPON_STENCIL_HELPER" \
  experiments/lua_interpreter_vm/spongejit \
  experiments/lua_interpreter_vm/SPONJIT_*.md
```

Expected final result: no maintained source/design matches except explicit no-residual test allowlist.

---

### Pattern Memo

- Unsupported opcode/fact = compile/lower/select failure, never runtime residual.
- No opcode helper escape hatch.
- Boundary is legal only for explicit VM control-transfer handoff.
- Native stencil must be `NATIVE | EXACT`; exact boundary stencils additionally carry `BOUNDARY`.
- Selector must not use hidden L0 fallback for progress.
- L0 gaps are transitional metrics, not failures unless strict semantic coverage is enabled.

## Worker Output — 2026-05-31 20:17:03

## Completed

Implemented the no-residual SponJIT cleanup across the maintained native-stencil path.

Key changes:
- Removed residual/unlowered runtime categories from SSA, Stencil IR, descriptor ABI, native emitter, materializers, selector, docs, and maintained gates.
- Unsupported opcode/fact cases now become structured compile/lower/select failures.
- Added exact semantic coverage metadata: native stencils must be `NATIVE | EXACT`; boundary stencils are marked separately.
- Removed hidden L0 selector fallback; missing coverage reports `SPON_SELECT_NO_CANDIDATE`.
- Added semantic opcode coverage table and semantic L0 audit tests.
- Rebuilt stencil/bank artifacts:
  - `stencils=4663`
  - `semantic_inline_stencils=1313`
  - `semantic_boundary_stencils=3350`
  - `exact L0 entries=32`
  - `missing exact L0 opcodes=53`

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` - new exact inline/boundary/unsupported coverage table.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_*.lua` - rejection/boundary model, no residual SSA nodes.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_*.lua` - no residual/unlowered ops; exact native descriptor validation/emission.
- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` - removed residual ABI enums, added exact/boundary flags and selector status fields.
- `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` - selector no longer synthesizes L0 fallback; manifest reports semantic coverage.
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` / `dedupe_normal_forms.lua` - structured rejection metrics and exact-only lowering.
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.*` - requires exact native stencils; runtime errors replace old unlowered returns.
- `experiments/lua_interpreter_vm/tests/test_spongejit_*` - updated/added no-fallback, semantic L0, exact materialization, and retired-token gates.
- `experiments/lua_interpreter_vm/SPONJIT_*.md` and `spongejit/bench/README.md` - docs updated to exact/reject semantics.

## Verification

Passed:
```sh
(cd experiments/lua_interpreter_vm/spongejit && make test)
(cd experiments/lua_interpreter_vm/spongejit && make stencils)
(cd experiments/lua_interpreter_vm/spongejit && make bank)
(cd experiments/lua_interpreter_vm/spongejit && make test-bank)
```

No retired fallback/helper tokens in maintained source/docs:
```sh
rg ... experiments/lua_interpreter_vm/spongejit experiments/lua_interpreter_vm/SPONJIT_*.md -g '!**/build/**'
# no matches
```

## Notes

Strict total semantic L0 coverage is intentionally not green yet:
```sh
SPON_STRICT_SEMANTIC_L0=1 luajit experiments/lua_interpreter_vm/tests/test_spongejit_semantic_l0_coverage.lua
```

It reports 53 missing exact L0 opcodes, including float loads, table/upvalue ops, div/mod/pow/shifts, comparisons/tests, vararg/closure/TBC, etc. This is now explicit missing coverage, not hidden behind runtime fallback stubs.

## Worker Output — 2026-05-31 20:57:07

## Completed

Implemented substantially more no-residual SponJIT opcode coverage:

- Added inline native `LOADF` support with F64 immediate patching and `LUA_VNUMFLT` tagging.
- Added exact i64 shift lowering/emission for:
  - `SHL`, `SHR`
  - `SHLI`, `SHRI`
- Added exact VM-boundary coverage for structural/control opcodes:
  - `LOADKX`
  - `LFALSESKIP`
  - `EQ`, `LT`, `LE`, `EQK`
  - `EQI`, `LTI`, `LEI`, `GTI`, `GEI`
  - `TEST`, `TESTSET`
- Preserved explicit rejection for unsupported opcodes like table/upvalue/vararg/closure/div/mod/pow/etc.
- Rebuilt stencil DB and generated bank.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` - added `ConstF64`.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` - LOADF, shifts, and boundary classifications.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` - F64 constants/holes.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` - F64 stencil ops.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_normalize.lua` - F64 canonical/codegen names.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua` - F64 native lowering support.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua` - F64 value type ABI metadata.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua` - F64 emission and exact Lua shift semantics.
- `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua` - LOADF f64 immediate patching.
- `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` - expanded inline/boundary coverage.
- `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` - added F64 value type.
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.c` - C patching for LOADF f64 immediates.
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.h` - LOADF/F64 constants.
- `experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua` - LOADF, shifts, boundary tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_lower.lua` - LFALSESKIP boundary test update.
- `experiments/lua_interpreter_vm/tests/test_spongejit_selector_no_fallback.lua` - unsupported case updated.
- `experiments/lua_interpreter_vm/tests/test_spongejit_bank_materialize.lua` - unsupported case updated.

Generated bank rebuilt under:

- `experiments/lua_interpreter_vm/spongejit/build/stencil_bank`
- `experiments/lua_interpreter_vm/spongejit/build/sponbank`

## Verification

Passed:

```sh
(cd experiments/lua_interpreter_vm/spongejit && make test)
(cd experiments/lua_interpreter_vm/spongejit && make stencils)
(cd experiments/lua_interpreter_vm/spongejit && make bank)
(cd experiments/lua_interpreter_vm/spongejit && make test-bank)
```

No residual/helper tokens in maintained source/docs:

```sh
rg ... -g '!**/build/**'
# no matches
```

## Coverage Delta

Rebuilt bank manifest:

- Exact L0 entries: `51`
- Missing exact L0 opcodes: `34`
- Previous recorded exact L0 entries: `32`
- Delta: `+19`

Newly covered in this run includes:

`LOADF`, `LOADKX`, `LFALSESKIP`, `SHLI`, `SHRI`, `SHL`, `SHR`, comparisons, and tests.

Remaining strict missing opcodes:

```text
GETUPVAL SETUPVAL GETTABUP GETTABLE GETI GETFIELD SETTABUP SETTABLE SETI SETFIELD
NEWTABLE SELF MODK POWK DIVK IDIVK MOD POW DIV IDIV
MMBIN MMBINI MMBINK LEN CONCAT CLOSE TBC SETLIST CLOSURE VARARG GETVARG ERRNNIL VARARGPREP EXTRAARG
```

## Worker Output — 2026-05-31 21:10:21

## Completed

Continued SponJIT exact opcode coverage with a substantial boundary-modeling pass.

Exact L0 coverage increased:

- **Before:** 51/85
- **After:** 66/85
- **Delta:** +15 opcodes

Newly covered opcodes:

```text
MMBIN MMBINI MMBINK
LEN CONCAT
CLOSE TBC
NEWTABLE SETLIST CLOSURE
VARARG GETVARG ERRNNIL VARARGPREP EXTRAARG
```

These are modeled as exact `SPON_EXIT_BOUNDARY` VM handoff stencils, not residuals/helpers/fallbacks.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` - expanded exact boundary coverage table.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` - added structured boundary reasons and `LEN` boundary lowering.
- `experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua` - added native boundary execution coverage.
- `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_lower.lua` - added descriptor/projection tests for new boundary opcodes.
- `experiments/lua_interpreter_vm/tests/test_spongejit_bank_materialize.lua` - added generated-bank selector/materializer boundary tests.

Rebuilt generated bank artifacts under:

- `experiments/lua_interpreter_vm/spongejit/build/stencil_bank`
- `experiments/lua_interpreter_vm/spongejit/build/sponbank`

## Verification

Passed:

```sh
(cd experiments/lua_interpreter_vm/spongejit && make test)
(cd experiments/lua_interpreter_vm/spongejit && make stencils)
(cd experiments/lua_interpreter_vm/spongejit && make bank)
(cd experiments/lua_interpreter_vm/spongejit && make test-bank)
```

Generated bank manifest:

```text
stencils=29247
semantic_inline_stencils=1514
semantic_boundary_stencils=27733
exact L0 entries=66
missing exact L0 opcodes=19
```

Remaining missing opcodes:

```text
GETUPVAL SETUPVAL GETTABUP GETTABLE GETI GETFIELD
SETTABUP SETTABLE SETI SETFIELD SELF
MODK POWK DIVK IDIVK MOD POW DIV IDIV
```

## Notes

Deliberately left unsupported:

- Table/upvalue/field/array/`SELF` opcodes: still need payload leases/dependency-safe table layout semantics.
- `DIV`/`IDIV`/`MOD`/`POW` families: need exact Lua numeric semantics, zero/overflow/error behavior, and float/integer rules before native coverage.

## Worker Output — 2026-05-31 21:35:15

## Completed

Continued the no-residual opcode coverage pass.

New exact opcode coverage added:

```text
MODK DIVK IDIVK
MOD  DIV  IDIV
```

Coverage changed:

```text
Exact L0: 66/85 -> 72/85
Delta: +6
```

Implemented semantics:
- `IDIV` / `IDIVK`: native i64 Lua floor-division, including negative quotient adjustment and `-1` special case.
- `MOD` / `MODK`: native i64 Lua floor-modulo, including negative remainder adjustment and `-1` special case.
- `DIV` / `DIVK`: native i64-to-f64 division with `LUA_VNUMFLT` result tagging.
- Zero divisor for integer division/modulo is guarded and exits through normal guard projection, not residual/fallback.
- K-operand arithmetic now patches explicit i64 constant payloads for `abs64 const` relocs instead of confusing constant index with constant value.

Rebuilt generated stencils/bank.

Generated bank manifest now reports:

```text
stencils=24897
semantic_inline_stencils=883
semantic_boundary_stencils=24014
exact L0 entries=72
missing exact L0 opcodes=13
```

Remaining missing exact L0 opcodes:

```text
GETUPVAL SETUPVAL GETTABUP GETTABLE GETI GETFIELD
SETTABUP SETTABLE SETI SETFIELD SELF
POWK POW
```

These remain unsupported because their exact semantics are not explicit enough yet:
- table/upvalue/field/SELF need payload leases, layout/offset contracts, metatable/metamethod behavior, and barrier semantics;
- `POW`/`POWK` need exact Lua numeric/pow semantics and type/metamethod handling.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua`
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_normalize.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua`
- `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua`
- `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua`
- `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua`
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.c`
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.h`
- `experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_bank_materialize.lua`
- regenerated `experiments/lua_interpreter_vm/spongejit/build/...`

## Verification

Passed:

```sh
(cd experiments/lua_interpreter_vm/spongejit && make test)
(cd experiments/lua_interpreter_vm/spongejit && make stencils)
(cd experiments/lua_interpreter_vm/spongejit && make bank)
(cd experiments/lua_interpreter_vm/spongejit && make test-bank)
```

No residual/helper/fallback tokens in maintained source/docs:

```sh
rg ... -g '!**/build/**'
# no matches
```

## Worker Output — 2026-05-31 22:00:36

## Completed

Continued SponJIT no-residual opcode coverage with real native field-specialized table support.

Implemented exact fact-specialized native semantics for:

- `GETFIELD`
- `SETFIELD`
- `SELF`

These are **not generic table fallbacks**. They require explicit facts/payloads:
- table is `LUA_VTABLE`
- `shape_eq` payload
- `metatable_absent`
- `key_const`
- `field_offset` payload
- `SETFIELD` also requires `barrier_clean`

Native x64 now emits:
- table tag guard
- shape-id guard via `shape_offset` + `shape_id`
- metatable-absent guard via `metatable_offset`
- raw TValue field load/store via `field_offset`

`POW`/`POWK`, generic table/array ops, and upvalue ops remain unsupported.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` - strict field payload/barrier requirements; generic array/table still reject.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` - patchable payload holes for shape/metatable/field roles; SELF aux slot mapping.
- `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` - marks `GETFIELD`/`SETFIELD`/`SELF` as fact-required inline candidates.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua` - allows supported field payload roles/deps and table guard/field ops.
- `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua` - emits native table guards and raw field load/store.
- `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua` - patches table payload roles.
- `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.*` - C materializer payload patch fields.
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` - updated strict field fact/barrier assertions.
- `experiments/lua_interpreter_vm/tests/test_spongejit_stencil_lower.lua` - field descriptor validation tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_native_stencil_bytes.lua` - native execution tests for `GETFIELD`, `SETFIELD`, `SELF`.
- `experiments/lua_interpreter_vm/tests/test_spongejit_bank_materialize.lua` - generated-bank selector/materializer tests for field variants.
- Rebuilt generated artifacts under:
  - `experiments/lua_interpreter_vm/spongejit/build/stencil_bank`
  - `experiments/lua_interpreter_vm/spongejit/build/sponbank`

## Verification

Passed:

```sh
(cd experiments/lua_interpreter_vm/spongejit && make test)
(cd experiments/lua_interpreter_vm/spongejit && make stencils)
(cd experiments/lua_interpreter_vm/spongejit && make bank)
(cd experiments/lua_interpreter_vm/spongejit && make test-bank)
```

No residual/helper/fallback tokens found in maintained source/docs excluding generated build output.

## Coverage

Exact L0 coverage:

```text
72/85 -> 75/85
Delta: +3
```

Newly covered exact L0 entries:

```text
GETFIELD SETFIELD SELF
```

Generated bank manifest:

```text
stencils=35833
semantic_inline_stencils=2549
semantic_boundary_stencils=33284
exact L0 entries=75
missing exact L0 opcodes=10
```

Remaining missing:

```text
GETUPVAL SETUPVAL GETTABUP GETTABLE GETI SETTABUP SETTABLE SETI POWK POW
```

Unsupported reasons:
- upvalues need exact open/closed upvalue layout semantics
- generic table/array ops need honest hash/array/metamethod/bounds/payload modeling
- `POW`/`POWK` need exact Lua numeric + metamethod semantics before native coverage

## Reviewer Output — 2026-06-01 10:55:27

## Files Reviewed
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` (lines 56-245)
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 53-220)

## Critical (must fix)
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua:141` - `pass_dead_frame_store` does not treat `gc_barrier`/call-like effects as observation points. A store can be removed if overwritten after a `BarrierCheck`, leaving the interpreter frame unsynced while the barrier primitive/GC/runtime may observe it. Example shape: `ADDI R1; SETFIELD ... R1` with barrier; later overwrite `R1`. The value is available in registers for the field store/barrier, but the frame slot may remain stale during the barrier call.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua:93` - `pass_guard_dominance` only clears dominance at `IR.HARD_BARRIER`, not on frame writes. A guard for `slot:R0 is_table` can dominate past `FrameStore R0 = nil/i64/...`, causing a later guard on `R0` to be removed unsafely. This directly interacts with the new store/load forwarding and dead-store removal because removed guards are no longer observation points.

## Warnings (should fix)
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua:145-150` - The ADDI^4 invariant checks counts only. It proves there is one `store_i64_slot`, but not that it is the final sync store for PC/op 4. A bug that kept an early store and deleted the final store could still satisfy the count. Assert the remaining `StoreI64Slot` source/op index corresponds to the last ADDI, and that no generic `store_slot`/intermediate frame stores remain.
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua:146` - Removing `FrameStore` nodes does not rewire frame memory tokens. Active node specs can now serialize `mem_in` references to removed frame-store tokens, which is risky for planner/projection consumers that treat memory tokens as ordering evidence.
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua:133-150` - The new test covers the success-path accumulator normalization, but not guard/boundary/barrier sync blockers. Add negative tests such as “store before guard must remain”, “store before boundary must remain”, and “store before non-eliminated barrier must remain”.

## Suggestions (consider)
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua:86-99` - Instead of clearing all guard dominance on every `FrameStore`, invalidate guard keys by written slot unless the stored value is proven to preserve the fact, e.g. `BoxI64` preserving `is_i64`. This keeps the ADDI^4 optimization while avoiding stale fact dominance.
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua:145-150` - Also inspect active SSA node removals or `r.stencil.ops` directly; `stencil_ops` loses source/detail needed to prove final-frame-sync semantics.

## Summary
The ADDI^4 optimization direction is reasonable, and the final-store preservation logic is better than deleting all stores not read later. The main semantic risks are observation-point completeness and fact invalidation: guards/barriers/boundaries must stop store sinking unless the optimizer can prove the frame/fact state remains valid.

## Reviewer Output — 2026-06-01 11:09:22

## Files Reviewed
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` (lines 83-187, 259-282)
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 132-187)

## Critical (must fix)
- None. The previous critical issues appear addressed:
  - `ssa_opt.lua:152-181` now treats `gc_barrier`, `call`, `guard`, `branch`, `return_`, heap effects, etc. as frame observation points for dead frame-store removal.
  - `ssa_opt.lua:106-119` now invalidates slot guard dominance on `FrameStore`, unless the stored value proves the guarded predicate.

## Warnings (should fix)
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua:147` - The ADDI^4 test still checks only opcode counts. It does not prove the remaining `StoreI64Slot` is the final sync store for the last ADDI. Assert the remaining store’s source/op index corresponds to the final ADDI.
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua:156` - The guard invalidation test message says “guard after overwritten slot must remain live,” but the test only creates one guard before the overwrite. Add a second guard after the `FrameStore` to directly exercise the fixed dominance invalidation path.

## Suggestions (consider)
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua:176` - Add a dead-store memory-token regression test: remove an overwritten store with no observation point and assert no active node’s `mem_in.frame` still references the removed store’s `mem_out.frame`.

## Summary
The two prior critical correctness problems are fixed in `ssa_opt.lua`: barriers/call-like effects now block store sinking, and frame writes invalidate stale slot guard dominance. Remaining concerns are test-strength issues rather than current code correctness blockers.

## Reviewer Output — 2026-06-01 11:11:49

## Files Reviewed
- `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` (lines 83-187, 259-282)
- `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 132-207)

## Critical (must fix)
- None.

## Warnings (should fix)
- None.

## Suggestions (consider)
- None.

## Summary
The prior outstanding items are addressed. `ssa_opt.lua` now treats barrier/call-like effects as frame observation points, invalidates slot guard dominance on frame writes, bypasses removed frame memory tokens, and the strengthened tests now assert final-store source, post-write guard preservation, barrier blocking, and token bypass behavior.

## Worker Output — 2026-06-01 13:10:18

## Completed

Confirmed: I read `experiments/lua_interpreter_vm/spongejit/ssa_asdl/REWRITE_PLAN.md` top-to-bottom and rechecked `spongejit_lua_ssa.asdl` module/product names.

Implemented and corrected the new LuaCompile tree under:

`experiments/lua_interpreter_vm/spongejit/lua_compile/`

The file manifest now matches the rewrite plan exactly: 50 planned files, no extra files.

## LuaCompile Files Added/Changed

- `init.lua`
- `schema.lua`
- `builders.lua`
- `validate.lua`
- `diagnostics.lua`
- `errors.lua`
- `lua_src_from_puc_decode.lua`
- `lua_src_window_collect.lua`
- `lua_src_slot_alias.lua`
- `lua_src_validate.lua`
- `lua_src_to_lua_region_recognize.lua`
- `lua_region_validate.lua`
- `lua_fact_from_runtime_observe.lua`
- `lua_fact_from_foundry_bundle.lua`
- `lua_fact_payload_lease.lua`
- `lua_fact_closure.lua`
- `lua_fact_contradiction.lua`
- `lua_fact_validate.lua`
- `lua_src_to_lua_sem_lower.lua`
- `lua_sem_env.lua`
- `lua_sem_guard.lua`
- `lua_sem_write.lua`
- `lua_sem_boundary.lua`
- `lua_sem_reject.lua`
- `lua_sem_validate.lua`
- `lua_sem_to_lua_nf_normalize.lua`
- `lua_nf_expr_canonicalize.lua`
- `lua_nf_guard_reduce.lua`
- `lua_nf_write_reduce.lua`
- `lua_nf_projection_reduce.lua`
- `lua_nf_key.lua`
- `lua_nf_validate.lua`
- `lua_nf_to_lua_contract_derive.lua`
- `lua_contract_fact_use.lua`
- `lua_contract_projection.lua`
- `lua_contract_dependency.lua`
- `lua_contract_key.lua`
- `lua_contract_validate.lua`
- `lua_nf_to_lua_place_plan.lua`
- `lua_place_projection_plan.lua`
- `lua_place_validate.lua`
- `lua_nf_to_lalin_out_lower.lua`
- `lalin_out_abi.lua`
- `lalin_out_emit.lua`
- `lalin_out_projection.lua`
- `lalin_out_validate.lua`
- `lua_compile_unit.lua`
- `lua_compile_to_normal_form.lua`
- `lua_compile_to_lalin_kernel.lua`
- `lua_compile_validate.lua`

Removed in `lua_compile/`: none.

## Tests Added

- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_src.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_fact.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_region.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_sem.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_nf.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_contract.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lalin_out.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_pipeline.lua`

## Verification

Passed:

```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do
  luajit "$t"
done
```

All 9 tests passed.

Also verified:
- LuaCompile manifest exactly matches planned file list.
- No versioned rewrite folder/name remains.
- No old descriptor/bank/materializer API references in new LuaCompile tree/tests.

## Generic / Non-ASDL File Names

No unplanned generic/non-ASDL file names remain. The only generic-looking root files (`schema.lua`, `builders.lua`, `validate.lua`, `diagnostics.lua`, `errors.lua`, `init.lua`) are exactly the root files required by `REWRITE_PLAN.md`.

## Worker Output — 2026-06-01 13:18:44

## Completed

Read in full before editing:
- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/REWRITE_PLAN.md`
- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
- Current `experiments/lua_interpreter_vm/spongejit/lua_compile/` tree

Implemented explicit 85/85 opcode coverage for the new LuaCompile path.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_from_puc_decode.lua`
  - Added explicit decode entries for:
    - `CLOSE`, `GETI`, `GETTABLE`, `GETTABUP`
    - `MMBIN`, `MMBINI`, `MMBINK`
    - `SETI`, `SETTABLE`, `SETTABUP`, `TBC`
  - Added binop decoding helper for `MMBIN*`.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_sem_lower.lua`
  - Reworked into an explicit semantic decision table covering all 85 real `LuaSrc.Op` alternatives.
  - Keeps simple representable opcodes as consumed LuaSem.
  - Uses exact `BoundaryObservation` only for VM/language boundary/control cases.
  - Uses structured rejection for unsupported ordinary opcodes.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/errors.lua`
  - Added rejection aliases:
    - `semantic_not_implemented`
    - `requires_fact_bundle`

- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_src.lua`
  - Added ASDL-derived decode coverage check.

- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_sem.lua`
  - Added ASDL-derived semantic decision coverage check.

- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_pipeline.lua`
  - Updated expected unsupported ordinary opcode rejection to `MissingPayloadLease`.
  - Added unknown opcode rejection check.

## Coverage

```text
real_ops=85
decode=85
semantic=85
```

## Verification

Passed:

```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do
  luajit "$t"
done
```

All LuaCompile tests passed.

Also checked no forbidden old-path/versioned/helper tokens in the new LuaCompile tree/tests:

```sh
rg -n "ssa2|SponDesc|SponTile|SponStencil|stencil_desc|materialize|build_bank|sponbank|OpcodeHelper|HelperCall" \
  experiments/lua_interpreter_vm/spongejit/lua_compile \
  experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua
# no output
```

## Worker Output — 2026-06-01 13:25:42

## Completed

Read before editing:
- Full `experiments/lua_interpreter_vm/spongejit/ssa_asdl/REWRITE_PLAN.md`
- Full `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
- Current LuaCompile files/tests relevant to this pass

Implemented honest LuaCompile support ledger and expanded real LuaSem/LuaNF support.

## Support Ledger

Before this pass:

```text
semantic=13
boundary=38
reject=34
```

After this pass:

```text
semantic=35
boundary=38
reject=12
```

Moved from `reject` to `semantic`:

```text
MULK MODK IDIVK BANDK BORK BXORK SHLI SHRI
MUL MOD IDIV BAND BOR BXOR SHL SHR
UNM BNOT
DIVK DIV POWK POW
```

Remaining structured ordinary rejections:

```text
GETFIELD GETI GETTABLE GETTABUP GETUPVAL
SETFIELD SETI SETTABLE SETTABUP SETUPVAL
SELF NOT
```

Notes:
- Table/upvalue/field/SELF remain `MissingPayloadLease`/structured rejection.
- `NOT` remains rejected because current ASDL has `LuaSem.Bool`, but no dynamic Bool-as-`TValue` slot write representation yet.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_sem_lower.lua`
  - Added real i64 semantics for requested K/immediate/register/unary ops.
  - Added f64 `DIV`/`DIVK`/`POW`/`POWK` using `IsF64` / `ConstF64`.
  - Decision table now reports `semantic` / `boundary` / `reject`.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_sem_to_lua_nf_normalize.lua`
  - Added real F64 normalization.
  - Fixed `BoxF64` lowering so it preserves expression value instead of dropping to dummy zero.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_runtime_observe.lua`
  - Added `const_f64` observation mapping.

- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_sem.lua`
  - Added support ledger assertions:
    - `semantic=35`
    - `boundary=38`
    - `reject=12`
  - Added missing-evidence and table-op rejection checks.

- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_nf.lua`
  - Added behavior tests for:
    - `MULK`
    - `IDIV`
    - `BAND`
    - `SHL`
    - `UNM`
    - `BNOT`
    - F64 `DIV`

## Verification

Passed:

```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do
  luajit "$t"
done
```

Output included:

```text
ok - SpongeJIT LuaCompile LuaSem (semantic/boundary/reject 35/38/12)
ok - SpongeJIT LuaCompile LuaSrc (decode coverage 85/85)
```

Forbidden-token check also passed; no `ssa2`, old descriptor/bank/materializer/stencil adapter, or helper fallback tokens found in LuaCompile tree/tests.

## Worker Output — 2026-06-01 13:40:32

## Completed

Continued SpongeJIT LuaCompile real support and eliminated the remaining ordinary opcode decision rejections.

Final LuaCompile ledger:

```text
semantic=47
boundary=38
reject=0
```

Implemented real semantic lowering for:

```text
GETFIELD GETI GETTABLE GETTABUP GETUPVAL
SETFIELD SETI SETTABLE SETTABUP SETUPVAL
SELF NOT
```

These are not fake boundaries. Table/array/field paths require explicit facts/payload leases and reject structurally when evidence is absent.

## ASDL Changes

- Added `LuaNF.UpvalueTValue(up)` for normalized upvalue reads.
- Extended `LuaSem.BarrierAfterStore(...)` and `LuaNF.BarrierAfterStore(...)` to carry the required `LuaFact.PayloadLease`.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_sem_lower.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_sem_to_lua_nf_normalize.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_nf_to_lua_contract_derive.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_runtime_observe.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_foundry_bundle.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_sem_write.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_fact.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_sem.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_nf.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_contract.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_pipeline.lua`

## Verification

Passed:

```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do
  luajit "$t"
done
```

Output includes:

```text
ok - SpongeJIT LuaCompile LuaSem (semantic/boundary/reject 47/38/0)
ok - SpongeJIT LuaCompile LuaSrc (decode coverage 85/85)
```

Forbidden-token check passed:

```sh
rg -n "ssa2|SponDesc|SponTile|SponStencil|stencil_desc|materialize|build_bank|sponbank|OpcodeHelper|HelperCall" ...
# no output
```

## Notes

No opcode remains in the LuaCompile decision table as `reject`. Evidence-gated table/upvalue/array operations still correctly reject at compile time when required facts or payload leases are absent.

## Worker Output — 2026-06-01 14:06:44

## Completed
Filled LuaCompile fact/evidence support gaps.

- Added ASDL-driven LuaFact coverage ledger:
  - subjects: `8/8`
  - predicates: `24/24`
  - dependencies: `8/8`
  - payload leases: `5/5`
- Completed runtime and foundry evidence import for all LuaFact subjects, predicates, dependency aliases, and payload leases including `CallTargetPayload`.
- Strengthened payload/fact validation, closure implications, and contradiction detection.
- Tightened semantic lowering evidence matching:
  - shape facts must match shape payloads
  - field facts/payloads must match shape + key identity
  - array facts require coherent array payload/bounds evidence
  - barrier use requires barrier fact + payload
- Strengthened contract derivation so payload uses and payload dependencies survive into `LuaContract.Contract`.
- Added behavior tests proving runtime/foundry evidence drives:
  - `GETFIELD`, `GETI`, `GETTABLE`, `GETTABUP`
  - `SETFIELD`, `SETI`, `SETTABLE`, `SETTABUP`, `SETUPVAL`
  - `SELF`
- Added structural rejection tests for missing/mismatched fact bundles.

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_runtime_observe.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_from_foundry_bundle.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_payload_lease.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_validate.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_closure.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_fact_contradiction.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_src_to_lua_sem_lower.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_nf_to_lua_contract_derive.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_fact.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_sem.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_nf.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_contract.lua`

## Verification
Passed:

```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do
  luajit "$t"
done
```

Output includes:

```text
ok - SpongeJIT LuaCompile LuaFact (subjects/predicates/dependencies/payloads 8/24/8/5)
ok - SpongeJIT LuaCompile LuaSem (semantic/boundary/reject 47/38/0)
ok - SpongeJIT LuaCompile LuaSrc (decode coverage 85/85)
```

Forbidden-token check also passed with no output:

```sh
rg -n "ssa2|SponDesc|SponTile|SponStencil|stencil_desc|materialize|build_bank|sponbank|OpcodeHelper|HelperCall" \
  experiments/lua_interpreter_vm/spongejit/lua_compile \
  experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua
```

## Notes
No remaining fact/evidence gaps are known for the current ASDL and the 47 semantic lowerings. `CallTargetPayload` is now imported/validated/closed, though no current semantic lowering consumes it yet.

## Worker Output — 2026-06-01 14:29:33

## Completed

Replaced the LalinOut scaffold with real Lalin source emission and validation.

What now compiles through Lalin:
- `ADDI + RETURN1` emits Lalin, compiles with `lalin.loadstring`, executes, and returns `42` through a typed output protocol.
- Non-terminal slot write (`ADDI` without return) emits/compiles/executes and reports written slot/value.
- Boundary exit (`CALL`) emits/compiles/executes and reports boundary tag/PC/reason.
- `f64 DIV` emits/compiles/executes and returns `10.5`.

Unsupported cases are now rejected before emission by `lalin_out_validate.lua`, including:
- `PowF64` (`unsupported_nf:F64.PowF64`) because Lalin source has no exact pow primitive and no helper fallback is allowed.
- Dynamic TValue truthiness / `NOT` (`unsupported_nf:Bool.NotTValue...`).
- Table/field/array/upvalue writes, barriers, and unsupported TValue forms at LalinOut.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_emit.lua`
  - Emits real Lalin source for supported `LalinOut.Kernel`.
  - Emits typed output pointer protocol.
  - Handles i64 arithmetic/bit/shift/unary, f64 div, slot writes, return/boundary/jump/loop/guard protocol exits.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_abi.lua`
  - Replaced old compatibility ABI naming with LuaCompile/LalinOut protocol params.
  - Collects typed kernel inputs from LuaNF.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_nf_to_lalin_out_lower.lua`
  - Uses NF-derived LalinOut ABI params.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_validate.lua`
  - Adds structural support validation before emission.
  - Rejects unsupported NF forms with explicit `unsupported_nf:*` reasons.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/validate.lua`
  - Removed leaked old runtime ABI name.

- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lalin_out.lua`
  - Now tests real source emission, hosted Lalin compilation, execution, boundary output, f64 div, and structured LalinOut rejection.

## Verification

Passed:

```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do luajit "$t"; done
```

Output:

```text
ok - SpongeJIT LuaCompile LuaContract
ok - SpongeJIT LuaCompile LuaFact (subjects/predicates/dependencies/payloads 8/24/8/5)
ok - SpongeJIT LuaCompile LuaNF
ok - SpongeJIT LuaCompile LuaRegion
ok - SpongeJIT LuaCompile LuaSem (semantic/boundary/reject 47/38/0)
ok - SpongeJIT LuaCompile LuaSrc (decode coverage 85/85)
ok - SpongeJIT LuaCompile LalinOut (emits and compiles Lalin source)
ok - SpongeJIT LuaCompile pipeline
ok - SpongeJIT LuaCompile schema
```

Forbidden old-path token check passed with no output.

## Worker Output — 2026-06-01 14:43:37

## Completed

Implemented honest LalinOut backend coverage beyond arithmetic for the current LuaCompile NF vocabulary.

Read before editing:
- `ssa_asdl/REWRITE_PLAN.md`
- `ssa_asdl/spongejit_lua_ssa.asdl`
- all `lalin_out_*.lua`
- `lua_sem_to_lua_nf_normalize.lua`
- `lua_nf_to_lua_contract_derive.lua`
- current `test_spongejit_lua_compile_*.lua`
- relevant Lalin language docs for pointer/output params, bools, numeric ops, field/index syntax, and source emission validity.

LalinOut support ledger:
- Before: representative arithmetic/boundary/f64-div compiled; dynamic `NOT`, field/array/upvalue writes, barriers, opaque TValue forms rejected; `PowF64` rejected.
- After: `45/47` semantic NF families validate + emit + Lalin-compile.
- Remaining structured blockers: `POW`, `POWK` via `unsupported_nf:F64.PowF64`.

Implemented:
- Typed protocol events for field/array/upvalue reads/writes and barriers.
- Dynamic `NOT` / TValue truthiness over supported TValue inputs via typed value-kind/bool params.
- Opaque TValue output protocol kinds for source slot, const, upvalue, field, array, table, closure.
- LalinOut ABI extensions with event/address/payload tags.
- Support ledger test covering all 47 semantic opcode families.

## Files Changed

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_abi.lua`
  - Added event/address/payload protocol tags and params.
  - Added dynamic TValue input param naming.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_emit.lua`
  - Emits typed protocol code for opaque TValue values, memory events, barriers, dynamic NOT/truthiness.
  - Exposes event/address/payload enums to tests.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_validate.lua`
  - Validates field/array/upvalue writes, barriers, bounds guards, payload-backed guards, dynamic TValue bool forms.
  - Keeps `PowF64` as structured rejection: `unsupported_nf:F64.PowF64`.

- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_sem_to_lua_nf_normalize.lua`
  - Fixed false boolean normalization with ASDL false/nil handling.

- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lalin_out.lua`
  - Reworked protocol harness for expanded ABI.
  - Added compile/execute checks for `GETFIELD`, `GETI`, `SETFIELD`, `SETI`, `SETUPVAL`, `SELF`, `NOT`.
  - Added full 47-family LalinOut support ledger.

## Verification

Passed:

```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do luajit "$t"; done
```

Output includes:

```text
ok - SpongeJIT LuaCompile LalinOut (semantic backend ledger 45/47 compiled, 2 structured PowF64 blockers)
```

Forbidden old-path token check passed with no matches:

```sh
rg -n "ssa2|SponDesc|SponTile|SponStencil|stencil_desc|materialize|build_bank|sponbank|OpcodeHelper|HelperCall" \
  experiments/lua_interpreter_vm/spongejit/lua_compile \
  experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua
```

## Notes

Remaining blocker is exact and intentional:
- `PowF64` has no Lalin source primitive and no explicit primitive-table ABI in LalinOut/contract yet.
- It remains rejected in `lalin_out_validate.lua` as `unsupported_nf:F64.PowF64`; no hidden helper/fallback was introduced.

## Worker Output — 2026-06-01 14:49:41

## Completed
Implemented `LuaNF.PowF64` in LalinOut using an explicit primitive function pointer ABI.

- Added `lua_compile_prim_pow_f64: func(f64, f64) -> f64`
- `PowF64(lhs, rhs)` now emits `lua_compile_prim_pow_f64(lhs, rhs)`
- Validation requires the primitive param when `PowF64` is present
- POW/POWK now compile and execute in tests via a LuaJIT FFI callback
- LalinOut ledger is now `47/47 compiled, 0 structured blockers`

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_abi.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_emit.lua`
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lalin_out_validate.lua`
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lalin_out.lua`

## Verification
Passed:

```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do luajit "$t"; done
```

Output:

```text
ok - SpongeJIT LuaCompile LuaContract
ok - SpongeJIT LuaCompile LuaFact (subjects/predicates/dependencies/payloads 8/24/8/5)
ok - SpongeJIT LuaCompile LuaNF
ok - SpongeJIT LuaCompile LuaRegion
ok - SpongeJIT LuaCompile LuaSem (semantic/boundary/reject 47/38/0)
ok - SpongeJIT LuaCompile LuaSrc (decode coverage 85/85)
ok - SpongeJIT LuaCompile LalinOut (semantic backend ledger 47/47 compiled, 0 structured blockers)
ok - SpongeJIT LuaCompile pipeline
ok - SpongeJIT LuaCompile schema
```

Forbidden old-path token check also passed with no matches.

## Worker Output — 2026-06-01 15:29:04

## Completed
Replaced the maintained offline SpongeJIT foundry path with the new LuaCompile ASDL pipeline.

New maintained flow:
```text
opcode windows + facts/evidence
-> LuaCompile.Unit
-> LuaNF + LuaContract
-> LalinOut.Kernel + emitted Lalin source
-> semantic representative key
```

## Files Changed
- `experiments/lua_interpreter_vm/spongejit/lua_compile/lua_compile_foundry.lua` - new LuaCompile foundry compiler/deduper/artifact writer.
- `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` - now LuaCompile foundry worker; no old SSA/stencil imports.
- `experiments/lua_interpreter_vm/spongejit/foundry.lua` - now runs LuaCompile foundry, not old SSA/StenciI.
- `experiments/lua_interpreter_vm/spongejit/build_stencils.sh` - historical filename, now builds LuaCompile foundry artifacts.
- `experiments/lua_interpreter_vm/spongejit/build_bank.sh` - quarantined fail-loud old runtime bank entrypoint.
- `experiments/lua_interpreter_vm/spongejit/Makefile` - added `lua-compile-foundry`, `test-lua-compile`, `test-lua-compile-foundry`.
- `experiments/lua_interpreter_vm/spongejit/lua_compile/schema.lua` - schema path now works from repo root or `spongejit/`.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_foundry.lua` - new offline foundry replacement tests.
- `experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_pipeline.lua` - updated LuaCompile manifest for new module.

## Artifact Output
Maintained foundry artifacts now live under:
```text
experiments/lua_interpreter_vm/spongejit/build/lua_compile_foundry/
```

Key files:
- `lua_compile_representatives.json`
- `lua_compile_representatives.md`
- `lua_compile_worker_N.json`
- `lua_compile_chunk_N.json`
- `lua_compile_chunk_manifest.json`

Schema:
```text
sponjit.lua_compile_foundry.v1
```

## Verification
Passed:
```sh
for t in experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua; do luajit "$t"; done

(cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile-foundry)
(cd experiments/lua_interpreter_vm/spongejit && make test-lua-compile)

(cd experiments/lua_interpreter_vm/spongejit && \
  CHUNKS=2 WORKERS=2 MAX_ARITY=2 MAX_FACT_COMBOS=4 make lua-compile-foundry)
```

Build output:
```text
windows=88
reps=19
compiles=87
ok=87
rejected=0
```

Forbidden-token check passed for LuaCompile tree/tests:
```sh
rg -n "ssa2|SponDesc|SponTile|SponStencil|stencil_desc|materialize|build_bank|sponbank|OpcodeHelper|HelperCall" \
  experiments/lua_interpreter_vm/spongejit/lua_compile \
  experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_*.lua
# no output
```

## Notes
- `src/worker_compile.lua` is now the maintained LuaCompile worker entrypoint.
- `foundry.lua` now uses LuaCompile and writes LuaCompile representative artifacts.
- `build_stencils.sh` remains as a historical filename but no longer emits old stencils.
- `build_bank.sh`, old `src.ssa*`, `ssa_to_stencil`, `stencil_*`, `src/enumerate.lua`, `src/grammar_enum.lua`, `src/dedupe_normal_forms.lua`, and `src/build_bank.lua` remain historical/quarantined unless separately removed.
- No runtime integration or bytecode execution claims were added.
