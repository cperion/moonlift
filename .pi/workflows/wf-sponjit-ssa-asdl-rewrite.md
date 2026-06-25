# SpongeJIT Lua SSA Compiler ASDL Rewrite 
Design proper ASDL vocabulary for a complete rewrite of SpongeJIT Lua SSA compiler. Guides: COMPILER_PATTERN.md and PVM_GUIDE.md. Principle: SSA consumes Lua opcode semantics into least/fastest canonical representation; residency and semantic mechanics solved cleanly in separate layers.
**Workflow ID**: wf-sponjit-ssa-asdl-rewrite
**Started**: 2026-06-01 11:49:32
---

## Scout Output — 2026-06-01 11:53:48

## Files Retrieved

1. `.pi/workflows/wf-sponjit-ssa-asdl-rewrite.md` (lines 1-7) — Workflow context: ASDL/layer vocabulary rewrite, principle that SSA consumes Lua opcode semantics into canonical representation while residency/mechanics belong in separate layers.
2. `experiments/lua_interpreter_vm/SPONJIT_FOUNDRY_SSA.md` (lines 1-307) — Current foundry/SSA design notes: pipeline, atom contract, fact state, loop-boundary stance, Stencil IR role.
3. `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md` (lines 1-220) — Current architecture overview: foundry → SSA → Stencil IR → native bank; runtime/Tier2 boundaries.
4. `experiments/lua_interpreter_vm/SPONJIT_RUNTIME_DESIGN.md` (lines 1-220) — Runtime boundary/spec: runtime observes/plans/materializes, does not run SSA.
5. `experiments/lua_interpreter_vm/spongejit/src/ssa_ir.lua` (lines 1-484) — Current SSA graph model: value types, effects, memory tokens, values, nodes, exits, guards, frame/table/call operations.
6. `experiments/lua_interpreter_vm/spongejit/src/ssa_lift.lua` (lines 1-467) — Opcode/fact → semantic SSA lowering. Encodes most current Lua opcode semantic questions and rejection/boundary choices.
7. `experiments/lua_interpreter_vm/spongejit/src/facts.lua` (lines 1-306) — Fact lattice: subjects, predicates, implications, dependencies, shorthand, contradictions.
8. `experiments/lua_interpreter_vm/spongejit/src/fact_schema.lua` (lines 1-225) — Older/canonical fact vocabulary sketch: value/effect/access/call/dependency/projection kinds and per-op axes.
9. `experiments/lua_interpreter_vm/spongejit/src/ssa_fact_axes.lua` (lines 1-357) — Curated fact bundle generator for foundry enumeration; defines executable bundles and payload leases.
10. `experiments/lua_interpreter_vm/spongejit/src/fact_signature.lua` (lines 1-214) — Runtime 64-bit fact ABI: slot/global bit layout, remapping, produced/killed masks.
11. `experiments/lua_interpreter_vm/spongejit/src/opcode_coverage.lua` (lines 1-93) — Authoritative opcode coverage classes: inline, boundary, unsupported; explicitly no fallback-stub category.
12. `experiments/lua_interpreter_vm/spongejit/src/ssa.lua` (lines 1-180) — Public compile facade: lift → optimize → validate → lower to Stencil IR → normalize.
13. `experiments/lua_interpreter_vm/spongejit/src/ssa_opt.lua` (lines 1-287) — SSA-local optimizations: copy/frame/field forwarding, guard dominance, store sinking, box/unbox cleanup, DCE.
14. `experiments/lua_interpreter_vm/spongejit/src/ssa_validate.lua` (lines 1-51) — SSA invariant checks: guards/exits, frame slots, boundary/call projection requirements.
15. `experiments/lua_interpreter_vm/spongejit/src/ssa_contract.lua` (lines 1-99) — Fact-transfer contracts from Stencil IR: selector/required/checked/produced/killed/deps/exits.
16. `experiments/lua_interpreter_vm/spongejit/src/ssa_atoms.lua` (lines 1-78) — Reopens serialized typed semantic node specs; rejects unknown reopened SSA ops.
17. `experiments/lua_interpreter_vm/spongejit/src/stencil_ir.lua` (lines 1-170) — Hole-parametric Stencil IR: ops, data-hole roles, slotmaps, validation.
18. `experiments/lua_interpreter_vm/spongejit/src/ssa_to_stencil.lua` (lines 1-355) — Lowers SSA to Stencil IR, creates canonical slot classes, holes, guard payloads, boundary exits.
19. `experiments/lua_interpreter_vm/spongejit/src/stencil_normalize.lua` (lines 1-151) — Canonical form/key/hash and projection/dependency summary.
20. `experiments/lua_interpreter_vm/spongejit/src/stencil_lower.lua` (lines 1-182) — Lowers Stencil IR to native descriptor: endpoints, projections, fact contract, native byte emission.
21. `experiments/lua_interpreter_vm/spongejit/src/stencil_desc.lua` (lines 1-519) — Native stencil ABI schema/enums/validation/lowering to C ABI arrays.
22. `experiments/lua_interpreter_vm/spongejit/src/stencil_projection.lua` (lines 1-38) — Current projection recipes: synced frame and box-i64.
23. `experiments/lua_interpreter_vm/spongejit/src/stencil_native_x64.lua` (lines 1-1390) — First native x64 emitter; contains many residency/interpreter mechanics.
24. `experiments/lua_interpreter_vm/spongejit/src/grammar_enum.lua` (lines 1-531) — Grammar/foundry opcode sequence generator, fact enumeration, L0/L1 floor generation.
25. `experiments/lua_interpreter_vm/spongejit/src/worker_compile.lua` (lines 1-215) — Per-worker SSA compile + SQLite forms/pattern aliases.
26. `experiments/lua_interpreter_vm/spongejit/src/dedupe_normal_forms.lua` (lines 1-214) — Global normal-form merge and unique lowering.
27. `experiments/lua_interpreter_vm/spongejit/src/puc_bytecode.lua` (lines 1-347) — Static/dynamic PUC bytecode operand/profile extraction and loop-region collection.
28. `experiments/lua_interpreter_vm/spongejit/src/loop_regions.lua` (lines 1-188) — Structural numeric/generic loop topology recognition.
29. `experiments/lua_interpreter_vm/spongejit/src/materialize_native_x64.lua` (lines 1-370) — Mechanical copy/link/patch materializer; consumes descriptors only.
30. `experiments/lua_interpreter_vm/spongejit/include/sponbank.h` (lines 1-282) — C bank/runtime ABI: fact sig, exec ctx, descriptors, relocs, selectors.
31. `experiments/lua_interpreter_vm/spongejit/src/build_bank.lua` (lines 1-769) — Generated C bank, selector, slot remapping, fact transfer in C.
32. `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.h` (lines 1-108) — Prototype L1 interpreter/materializer public C API.
33. `experiments/lua_interpreter_vm/spongejit/runtime/sponjit_l1_interpreter.c` (lines 1-402) — Prototype C materializer/runtime path: selects bank choices, patches relocs, runs image.
34. `experiments/lua_interpreter_vm/tests/test_spongejit_real_ssa.lua` (lines 1-288) — Current SSA/fact/contract invariants and regression assertions.
35. `experiments/lua_interpreter_vm/src/contract.lua` (lines 1-19) — Lalin VM gate: `sponjit_allowed = false`.
36. `experiments/lua_interpreter_vm/src/op/protocols.lua` (lines 1-42) — Current VM opcode continuation protocols.
37. `experiments/lua_interpreter_vm/src/op/_init.lua` (lines 1-150) — Opcode-region boilerplate and protocol wiring.
38. `experiments/lua_interpreter_vm/src/op/arithmetic.lua` (lines 1-300) — Example interpreter opcode semantics for arithmetic; useful contrast with SpongeJIT SSA semantics.

## Key Code

### SSA graph currently mixes semantic, memory, exit, and residency facts

`ssa_ir.lua` defines value types/effects/codegen names and stores `residency` on SSA values:

```lua
local VALUE_TYPES = {
    TValue = true, I64 = true, F64 = true, Bool = true,
    PtrTable = true, PtrClosure = true, Shape = true,
    FieldAddr = true, Void = true, Unknown = true,
}

local EFFECTS = {
    none = true, guard = true, frame_read = true, frame_write = true,
    heap_read = true, heap_write = true, gc_barrier = true, call = true,
    branch = true, return_ = true,
}
```

```lua
function Graph:new_value(ty, name, facts, residency)
    ...
    local v = { id = id, ty = ty, facts = copy_array(facts), residency = residency }
```

Memory is split into frame/table/gc/call tokens:

```lua
g.mem = {
    frame = g:new_memory("frame", "entry"),
    table = g:new_memory("table", "entry"),
    gc = g:new_memory("gc", "entry"),
    call = g:new_memory("call", "entry"),
}
```

Exits are currently synced-frame-shaped by default:

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

### SSA lift answers opcode/fact semantic questions directly

`ssa_lift.lua` answers:
- is opcode inline, boundary, or rejected?
- which facts are enough?
- which guards are emitted?
- what projection/boundary reason exists?
- which opcodes become exact VM handoff?

Examples:

```lua
local NUMERIC_FOR = { FORPREP = true, FORLOOP = true }
local GENERIC_FOR = { TFORPREP = true, TFORCALL = true, TFORLOOP = true }

local BOUNDARY_REASON = {
    LOADKX = "extraarg_boundary",
    LFALSESKIP = "branch_skip_boundary",
    EQ = "comparison_boundary", LT = "comparison_boundary", LE = "comparison_boundary",
    ...
}
```

```lua
local function lower_loop_region_boundary(g, op, pc, ev)
    local reason = NUMERIC_FOR[op] and "numeric_for_region_boundary" or "generic_for_region_boundary"
    return boundary(g, op, pc, ev, reason)
end
```

I64 arithmetic consumes facts and rejects missing ones:

```lua
local lhs = i64_from_slot(g, ev.b, "lhs", pc)
if not lhs then return reject(g, op, pc, ev, "missing_lhs_i64_fact") end
...
if real_op == "MOD" or real_op == "IDIV" then
    guard_nonzero_i64(g, rhs, Facts.value("rhs"), pc)
    native = g:i64_binop(real_op, lhs, rhs, pc)
```

Table/field accesses require payload leases:

```lua
shape_payload = has_slot(g, ev.b, "shape_eq", { "shape", "table" })
if not shape_payload then return reject(g, op, pc, ev, "missing_shape_payload_fact") end
...
local off_ok = has_k(g, ev.c or 0, "field_offset")
if not off_ok then return reject(g, op, pc, ev, "missing_field_offset_fact") end
```

### Fact lattice currently contains semantic facts plus residency shorthand

`facts.lua` subjects:

```lua
function M.value(id) return M.subject("value", id) end
function M.slot(id) return M.subject("slot", id) end
function M.table_ref(id) return M.subject("table", id) end
function M.callsite(id) return M.subject("callsite", id) end
function M.pc(id) return M.subject("pc", id) end
function M.memory(id) return M.subject("memory", id) end
function M.global_subject() return M.subject("global", "*") end
```

Dependencies are attached by predicate:

```lua
local DEP_BY_PREDICATE = {
    shape_eq = { "shape_epoch" },
    shape_known = { "shape_epoch" },
    field_offset = { "shape_epoch" },
    metatable_absent = { "metatable_epoch" },
    ...
    barrier_clean = { "gc_barrier_protocol" },
}
```

Residency exists as shorthand facts:

```lua
value_in_rax = function() return M.fact("residency", M.value("last"), "in_reg", "rax", "observed") end,
value_in_rcx = function() return M.fact("residency", M.value("last"), "in_reg", "rcx", "observed") end,
```

### Fact axes build executable bundles, not blind powersets

`ssa_fact_axes.lua` says the contract is between grammar enumeration, SSA lowering, bank selection, runtime patching:

```lua
-- facts that must travel together for a lowering to be executable
-- (type + guard lease + payload lease)
```

Field get bundle:

```lua
make_bundle(bundles, "field_get:" .. n .. ":" .. pc, {
  ax_slot(table_slot, "is_table", {role="table"}),
  ax_slot(table_slot, "shape_known", {role="shape"}),
  ax_slot(table_slot, "shape_eq", {role="shape", value=pc_id(pc)}),
  ax_slot(table_slot, "metatable_absent", {role="metatable"}),
  ax_k(k, "key_const", {role="key"}),
  ax_k(k, "field_offset", {role="field_offset", value=pc_id(pc)}),
}, {tier=3, pc=pc, op=n})
```

Array get bundle:

```lua
ax_slot(table_slot, "array_hit", {role="array"}),
ax_slot(table_slot, "bounds_ok", {role="bounds"}),
ax_slot(table_slot, "array_base_offset", {role="array_payload", value=pc_id(pc)}),
ax_slot(table_slot, "array_len_offset", {role="array_payload", value=pc_id(pc)}),
```

### Runtime fact ABI is compact 64-bit signature

`fact_signature.lua`:

```lua
M.SLOT_FACT_BASE = {
  i64 = 0, is_i64 = 0, is_number = 0, is_f64 = 0,
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

### Stencil IR distinguishes data holes from control endpoints

`stencil_ir.lua`:

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
  array_len_offset = true,
  upvalue = true,
  call_target = true,
  barrier = true,
}
```

```lua
assert(t.role_kind ~= "exit" and t.role_kind ~= "fail",
       "exit/fail are control endpoints, not data holes")
```

### SSA → Stencil lowering creates canonical slot classes and payload holes

`ssa_to_stencil.lua` builds slot classes from source opcode operands:

```lua
local function build_slot_classes(source_ops)
  local concrete_to_class, class_to_concrete, occurrences = {}, {}, {}
  ...
  for pc, op in ipairs(source_ops or {}) do
    ...
    for _, field in ipairs(SLOT_FIELDS_BY_OP[oname] or {}) do
      local conc = tonumber(op[field])
      ...
      local cls = class_for(conc)
      occurrences[cls][#occurrences[cls] + 1] =
        {op_idx = pc - 1, field_kind = FIELD_KIND[field] or 0, concrete = conc}
```

GuardShape creates semantic data holes:

```lua
local off = st:hole({ role_kind = "shape_offset", ... semantic = true })
local sid = st:hole({ role_kind = "shape_id", ... semantic = true })
st:add("GuardShape", { ... args = { shape_offset = off.id, shape_id = sid.id } })
```

Boundary/call/return/jump become `ExitBoundary`:

```lua
elseif op == "Boundary" or op == "Jump" or op == "Return1" or op == "Return0" or op == "Call" ... then
  st:add("ExitBoundary", { inputs = ins, source = pc,
    args = { op = op, opcode = args.opcode, reason = args.reason },
    exit = n.exit, effect = n.effect or "branch" })
```

### Contracts derive selector/required/checked/produced/killed facts from Stencil IR

`ssa_contract.lua`:

```lua
if n.guard and n.guard.fact then
  checked = Sig.bor(checked, Sig.encode({remap_fact_to_canonical(n.guard.fact, st)}))
end
...
if n.op == "StoreSlot" or n.op == "StoreI64Slot" then
  killed = Sig.bor(killed, Sig.slot_kill(slot))
  if n.op == "StoreI64Slot" then produced = Sig.bor(produced, Sig.i64_slot(slot)) end
end
...
local required = Sig.minus(selector, checked)
```

### Native descriptor requires explicit endpoints/projections/relocs/fact transfer

`stencil_desc.lua` endpoint kinds:

```lua
M.ENDPOINT_KIND = {
  entry = true,
  ok = true,
  guard_exit = true,
  boundary_exit = true,
}
```

Control reloc kinds:

```lua
M.CONTROL_RELOC_KIND = {
  fallthrough = true,
  guard_fail = true,
  boundary = true,
  projection_stub = true,
}
```

Validation requires projections for non-success endpoints:

```lua
if ep.kind ~= "entry" and ep.kind ~= "ok" then
  if nproj <= 0 then
    err(errors, "non-success endpoint without projection: " .. tostring(ep.kind))
```

### Current projection layer is minimal

`stencil_projection.lua`:

```lua
function M.synced_frame(exit, source)
  return {
    kind = "SYNCED_FRAME",
    reason = exit and exit.reason or "exit",
    pc = exit and exit.pc or source or 0,
    entries = {},
  }
end
```

```lua
function M.for_exit(st, n, config)
  return M.synced_frame(n and n.exit, n and n.source)
end
```

`BOX_I64` exists but `for_exit` currently returns synced-frame only.

### Native x64 emitter contains many interpreter/residency details

`stencil_native_x64.lua` hardcodes PUC tags and `SponExecCtx` offsets:

```lua
local LUA_VNUMINT = 3
local LUA_VNUMFLT = 19
local LUA_VTABLE = 69

local CTX_STACK = 0
local CTX_K = 8
local CTX_EXIT_KIND = 16 + 256 * 16
...
local REG_POOL = { "rax", "rcx", "rdx", "r8", "r9" }
```

It tracks native value locations:

```lua
local loc, free = {}, {}
...
loc[v] = { kind = "slot", hole = n.hole }
loc[out] = { kind = "tvalue_regs", value_reg = value_reg, tag_reg = tag_reg }
loc[outv] = { kind = "reg", reg = l.reg }
```

It has a special seam optimization:

```lua
if l and l.kind == "boxed_i64_reg" then
  -- Forward an i64 value that was just stored/boxed earlier in the same stencil.
  loc[outv] = { kind = "reg", reg = l.reg }
```

### C bank selector remaps slot facts and applies fact transfer

`build_bank.lua` generated C selector:

```c
static SponFactSig remap_stencil_sig(..., SponFactSig sig, ...)
```

It remaps logical slot bits through actual slotmap. Transfer:

```c
facts &= ~killed;
facts |= produced;
facts |= checked;
return facts;
```

Candidate acceptance:

```c
SponFactSig available_sig = observed_sig | facts;
...
if (((fsel & ~available_sig) == 0) && ((freq & ~facts) == 0)) {
  chosen = fid;
```

### Runtime ABI exposes frame, constants, scratch, upvalues, primitive hooks

`sponbank.h`:

```c
struct SponExecCtx {
  void *stack;
  SponTValueABI *k;
  SponTValueABI scratch[256];
  uint32_t exit_kind;
  uint32_t exit_pc;
  uint32_t exit_op_idx;
  uint32_t exit_hole;
  SponTValueABI **upvals;
  SponPrimitiveTable *prims;
};
```

`SponStencilDesc` includes:

```c
SponFactSig selector_sig;
SponFactSig required_sig;
SponFactSig checked_sig;
SponFactSig produced_sig;
SponFactSig killed_sig;
```

### Loop regions are structural, not scalar SSA facts

`loop_regions.lua` creates records with topology:

```lua
return {
  kind = "numeric_for_region",
  base = base,
  prep_pc = prep_pc,
  body_entry_pc = prep_pc + 1,
  loop_pc = loop_pc,
  exit_pc = loop_pc + 1,
  slot_window = slot_window(base, base + 3),
  state_slots = { ... },
  edges = {
    enter_body = { from_pc = prep_pc, to_pc = prep_pc + 1 },
    skip = { from_pc = prep_pc, to_pc = loop_pc + 1 },
    continue_loop = { from_pc = loop_pc, to_pc = prep_pc + 1 },
    done = { from_pc = loop_pc, to_pc = loop_pc + 1 },
  },
}
```

### VM integration is gated off

`experiments/lua_interpreter_vm/src/contract.lua`:

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

## Relationships

Current data flow:

```text
grammar/corpus opcode windows
  -> ssa_fact_axes.lua builds fact bundles
  -> ssa_lift.lua consumes opcode semantics + facts into ssa_ir.lua graph
  -> ssa_opt.lua normalizes graph
  -> ssa_validate.lua checks graph
  -> ssa_to_stencil.lua lowers graph to Stencil IR
  -> stencil_normalize.lua builds canonical key/hash/form
  -> worker_compile.lua writes per-worker forms + pattern aliases
  -> dedupe_normal_forms.lua merges by stencil_hash and lowers one representative
  -> stencil_lower.lua builds native descriptor
  -> stencil_native_x64.lua emits bytes/relocs
  -> stencil_desc.lua ABI-lowers metadata
  -> build_bank.lua emits C bank + selector
  -> materialize_native_x64.lua / runtime C copies, links, patches, runs
```

Semantic authority boundaries currently observed:

- `ssa_lift.lua` is where Lua opcode semantics and fact consequences become SSA.
- `ssa_opt.lua` is where interpreter-shaped frame traffic is reduced.
- `stencil_ir.lua` is canonical materialization shape, not the semantic authority.
- `stencil_desc.lua`/`sponbank.h` are runtime ABI contracts.
- Runtime/materializer does not run SSA and only consumes descriptors/relocs/fact masks.

Current module “questions” answered:

- `opcode_coverage.lua`: “Is this opcode inline, exact boundary, or unsupported?”
- `facts.lua`: “What facts exist, imply each other, contradict, and depend on epochs?”
- `ssa_fact_axes.lua`: “Which foundry fact bundles are meaningful/executable for this opcode window?”
- `ssa_lift.lua`: “Given opcode + facts, what semantic SSA operations, guards, exits, or rejections result?”
- `ssa_ir.lua`: “What are SSA values/effects/memory tokens/exits?”
- `ssa_opt.lua`: “Which semantic redundancies are removed before stencil formation?”
- `ssa_to_stencil.lua`: “How do semantic SSA nodes become hole-parametric stencil ops and slotmaps?”
- `stencil_normalize.lua`: “What canonical normal form/hash represents this stencil?”
- `ssa_contract.lua`: “What facts are selected, checked, produced, killed, and required?”
- `stencil_lower.lua`: “Can this Stencil IR become an executable native descriptor?”
- `stencil_desc.lua`: “Is descriptor ABI complete and valid?”
- `stencil_native_x64.lua`: “How do supported Stencil IR ops become x64 bytes/relocs?”
- `build_bank.lua`: “How are descriptors packed and selected at runtime?”
- `materialize_native_x64.lua` / `sponjit_l1_interpreter.c`: “How are selected descriptors patched into executable images?”

## Observations

Raw leaks / couplings found:

- SSA values carry `residency = "gpr0"` in `ssa_ir.lua`; tests assert residency round-trips through `active_node_specs`.
- `ssa_ir.lua` `CODEGEN_OP` names already anticipate lower/codegen vocabulary.
- `ssa_to_stencil.lua` builds canonical slot classes from concrete opcode operands and source fields.
- `stencil_native_x64.lua` owns a separate native location lattice: `slot`, `reg`, `tvalue_regs`, `const_pool`, `boxed_i64_reg`, `upvalue_cell`.
- Native emitter hardcodes PUC TValue tags (`3`, `19`, `69`) and `SponExecCtx` offsets.
- Projection currently mostly means `SYNCED_FRAME`; `BOX_I64` exists but is not used by `for_exit`.
- Fact state is split between rich `Facts.fact` records, 64-bit `SponFactSig`, payload holes/relocs, and dependency strings.
- Payload facts such as `shape_eq`, `field_offset`, `array_base_offset`, `array_len_offset`, `target_eq` collapse into coarse global payload bits in `fact_signature.lua`.
- `ssa_lift.lua` rejects many cases unless payload facts are present; unsupported facts/opcodes become structured compile failures, not fallback stubs.
- Loop opcodes are explicitly boundary handoffs; loop-region data exists separately in `loop_regions.lua`.
- Boundary stencils are considered exact native descriptors with `semantic_mode = "boundary"`.
- Runtime selector uses opcode pattern key plus fact masks; normal-form dedupe key is only canonical stencil hash, not source opcode/fact contract.
- Store/load seam facts are represented through slotmaps, fact transfer, and native local forwarding, not a distinct high-level seam vocabulary.
- VM integration remains closed via `sponjit_allowed = false`; current runtime paths are prototype/bank/materializer paths.

## Knowledge-builder Output — 2026-06-01 11:56:48

### What Matters Most for This Problem

- **Layer authority:** each ASDL vocabulary must answer one real question and consume decisions from the previous layer.
- **Semantic exhaustiveness:** Lua opcode meaning, guard conditions, boundary exits, and unsupported cases must be typed and closed, not stringly/ad hoc.
- **Normal-form correctness:** dedupe is only sound if everything that affects selector/contract/projection/exits is represented in the normal form or explicitly kept as alias metadata.
- **Fact/payload separation:** observed facts, guard facts, payload leases, epoch deps, produced/killed masks, and ABI bit signatures are different things.
- **Projection and residency separation:** SSA should describe Lua semantic state and exit obligations; placement/native layers decide registers, scratch slots, synced frames, relocs.
- **Runtime ABI stability:** runtime/materializer must consume flat descriptors and masks, never rediscover Lua opcode semantics or run SSA.

---

### Non-Obvious Observations

#### 1. The honest layer stack is question-based, not file-based

The current pipeline already implies these distinct vocabularies:

| Layer | Question answered | Belongs here | Must not belong here |
|---|---|---|---|
| **Source candidate** | “What bytecode region and observed evidence are we compiling?” | opcode sequence, operands, pc, constants refs, loop topology, observed facts, payload leases | SSA ops, native regs, descriptor masks |
| **Semantic SSA** | “What does this Lua bytecode mean under these facts?” | canonical value ops, guards, effects, virtual frame state, semantic exits | opcode strings as behavior switches, x64 locations, C ABI offsets |
| **Semantic normal form** | “Are two lowered programs equivalent?” | canonical op/value structure, checked facts, deps, projection obligations, abstract slot classes | concrete source slots except alias mapping, native placement |
| **Stencil/materialization form** | “What flat parametric executable shape must be emitted?” | holes, endpoint roles, slotmaps, data-hole roles, control endpoints | Lua opcode semantics, register allocation |
| **Placement/residency** | “Where do values live while emitting/running?” | registers, scratch slots, boxed temporaries, forwarding seams, relocs | semantic facts, Lua opcode decisions |
| **Runtime ABI** | “What stable C/bank format is selected and patched?” | packed descriptors, fact masks, endpoint/projection records, relocs | SSA graphs, rich fact objects, source semantics |

The dangerous current leak is that `ssa_ir.lua`, `ssa_to_stencil.lua`, and `stencil_native_x64.lua` collectively blur semantic state, materialization shape, and residency.

#### 2. “Fact” is overloaded into at least five different concepts

The scout data shows one word covering:

- observed runtime evidence,
- semantic preconditions,
- guard predicates,
- payload leases,
- dependency epochs,
- selector bits,
- produced/killed transfer masks.

Those cannot share one ASDL role. For example, `shape_eq` as a semantic guard is not the same as the `shape_payload` ABI bit, and neither is the same as a concrete `shape_id` hole. The rewrite must preserve this distinction or normal-form dedupe and runtime selection become unsound.

#### 3. Current dedupe implies a hidden invariant that may already be false

`worker_compile.lua` says dedupe key is only `stencil_hash`; `contract_key` is retained but not part of equivalence. Yet `ssa_contract.lua` computes `selector_sig` from the original input facts.

That means dedupe is only sound if:

> the contract is fully derivable from the canonical stencil/normal form and independent of extra source facts.

But curated fact bundles can contain facts not consumed by guards. If those facts affect `selector_sig`/`required_sig` but not `stencil_hash`, two source candidates may collapse to one representative with the wrong selector contract.

This is a normal-form boundary issue, not merely a database issue.

#### 4. Opcode names are code-shaping source data; most should be dead after SSA

`ADD`, `ADDI`, `ADDK`, etc. are source distinctions used to choose lowering. Once consumed, the semantic form should carry canonical arithmetic meaning, not the original opcode identity.

Exceptions are payload-like obligations: exact boundary reason, pc, source constant reference, or resume location. Those are not behavior dispatch anymore; they are deopt/projection payloads.

The ASDL classification discipline matters here: opcode kind is usually **code-shaping**, pc/reason is often **payload**, and many operand distinctions become **dead** after canonicalization.

#### 5. Boundary is not fallback

Current coverage has `inline`, `boundary`, `unsupported`, and explicitly no fallback-stub category. That implies three distinct control outcomes:

- inline semantic lowering succeeded,
- exact VM handoff is the intended semantic result,
- compilation rejects the candidate.

A boundary stencil is still an exact executable descriptor. Treating it as “failed inline lowering” would leak compile failure into runtime execution and obscure missing semantics.

#### 6. Loop regions are structural source/control, not scalar facts

`loop_regions.lua` produces topology: body entry, exit pc, continue edge, slot window, state slots. That is not equivalent to facts like “slot i64” or “pc boundary”.

Current SSA boundaries numeric/generic loop opcodes. If loops are ever brought into SSA, they need a region/control vocabulary, not a bag of predicates. Encoding loop topology as independent facts would lose the multi-edge invariant.

#### 7. Frame slots have two identities that must not collapse

A Lua frame slot is:

1. a semantic Lua VM register/local participating in bytecode meaning, and
2. a physical/interpreter stack address in `SponExecCtx`.

SSA may need the first. Placement/ABI owns the second.

Current `exit_projection` defaulting to a synced frame hides this distinction. The semantic exit obligation is “these Lua values must be reconstructable at this pc”; `SYNCED_FRAME`, `BOX_I64`, scratch slots, and actual stack stores are projection/materialization choices.

#### 8. Projection is a control protocol, not a side field

Guard failure, boundary handoff, return, call handoff, and loop boundary all have different continuation obligations. The current projection layer mostly returns `SYNCED_FRAME`, while `BOX_I64` exists but is unused.

That means the existing vocabulary cannot yet express the difference between:

- value already present as TValue,
- virtual i64 needing boxing,
- slot already synced,
- heap/table state requiring no projection,
- boundary that kills all facts.

Normal form equivalence must include these obligations, otherwise two stencils can look identical while requiring different runtime reconstruction.

#### 9. Payload leases are executable bundles, not optional facts

`ssa_fact_axes.lua` shows table field lowering needs facts that travel together: table type, shape, metatable absence, key const, field offset.

Non-obvious consequence: `field_offset` alone is not a harmless extra payload. Without `metatable_absent` and shape equality, direct field access would bypass Lua semantics incorrectly. The semantic layer must treat these bundles as atomic enough for soundness, even if individual predicates remain separately named.

#### 10. Runtime fact compression is lossy by design

`fact_signature.lua` collapses rich payload facts into coarse global bits such as `shape_payload`, `array_payload`, `call_target_payload`.

That is acceptable only below the semantic/materialization boundary. Above it, ASDL must retain role, subject, pc/key association, and dependency. Otherwise a payload bit can accidentally authorize the wrong hole.

The ABI bitmask is a transport format, not the source of semantic truth.

#### 11. Store/load seam forwarding is a placement optimization revealing a semantic equality

The native emitter has `boxed_i64_reg` forwarding across a store/box seam. That should not appear as SSA residency.

The semantic fact is value identity: the value just computed, stored, and later boxed/reloaded is the same SSA value. Placement may exploit that by keeping it in a register. If SSA records “in rax” or “boxed_i64_reg”, the semantic normal form becomes polluted by one backend’s optimization.

#### 12. Effects are semantic, not merely scheduling annotations

Frame writes, heap writes, GC barriers, calls, and hard exits drive fact killing and dependency obligations. `ssa_contract.lua` kills facts on call/boundary/heap writes.

Therefore effect tokens belong in semantic SSA/normal form. Native placement may schedule around them, but it must not invent or reinterpret them. If optimization removes or sinks stores without preserving produced/killed masks, runtime fact state becomes unsound.

#### 13. Stencil IR is currently doing two jobs

It is both:

- a canonical materialization shape for dedupe/hash, and
- a near-codegen instruction vocabulary consumed by x64.

That creates tension. Some stencil ops are semantic-ish (`GuardShape`, `FieldLoad`), while others are materialization-ish (`BoxI64Scratch`, holes, relocs). The rewrite needs a sharp distinction between “canonical meaning” and “emittable shape”, even if they remain adjacent phases.

#### 14. Source ASDL should not absorb foundry mechanics as semantics

Curated fact axes are a generator/exploration vocabulary: “which executable bundles should the foundry enumerate?” Runtime observed facts are source evidence. Semantic facts are consumed preconditions.

Those are related but not identical. If the ASDL treats foundry axes as the compiler’s semantic source language, bank generation mechanics will leak into ordinary runtime compilation.

#### 15. Runtime/materializer must remain a loop over flat facts

The guide principle “the loop is the only execution” maps here to the bank/runtime side: runtime selects a descriptor, remaps masks, patches relocs, and runs native code. It must not branch on Lua opcode semantics or inspect SSA.

`SponStencilDesc`, relocs, endpoints, projections, and masks are therefore the runtime-facing flat command layer. Anything richer than that is compiler state.

---

### Risks to Avoid

- Putting residency/register/scratch information in SSA values.
- Letting opcode strings survive as downstream semantic dispatch.
- Treating boundary exits as fallback failures.
- Hashing normal forms without including contract/projection obligations.
- Collapsing rich payload facts into ABI bits before materialization.
- Modeling loop regions as unrelated scalar facts.
- Defaulting every exit to synced-frame projection.
- Allowing runtime selector/materializer to rediscover Lua semantics.
- Treating generated summaries like `active_node_specs`, `stencil_ops`, or `projection` as source truth.
- Mixing source slot numbers with canonical slot classes without explicit alias metadata.

---

### Knowledge Gaps

- Whether the rewrite intends to use Lalin/PVM ASDL directly or only borrow its design discipline.
- The desired scope of inline loop handling versus permanent loop-boundary stance.
- The complete Lua opcode semantic target set for the first rewritten vocabulary.
- The exact runtime payload-lease representation expected outside the foundry prototype.
