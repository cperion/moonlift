# DynASM Backend Re-Architecture (ASDL-First, PVM-Native, Complete)

## Status
Design specification for a full rewrite of `back/dasm` using the methodology in `PVM_GUIDE.md`:

- ASDL first
- explicit `pvm.phase` boundaries
- lazy pull execution + memoized identities
- flatten-early machine command stream
- deterministic single-pass emitter

This document is intentionally **complete** (no deferred “later”, no placeholder backend gaps).

---

## 1) Hard requirements

1. Backend API must stay compatible with existing JIT backend usage:
   - `Define(T) -> { jit = function() ... end }`
   - `jit:symbol(name, ptr)`
   - `jit:compile(program: MoonBack.BackProgram)`
   - `artifact:getpointer(func)`
   - `artifact:free()`
2. Input is **only** ASDL `MoonBack.BackProgram`.
3. All `MoonBack.Cmd` variants are handled explicitly.
4. Multi-compile in one process is guaranteed safe (no DynASM state bleed).
5. No silent drops of IR semantics.
6. Control-flow correctness includes block params / edge args (phi semantics).
7. Full scalar + float + vector semantics supported; vector lowered by deterministic scalarization pass.

---

## 2) ASDL-first architecture

## 2.1 Existing schema used as source IR

- Source IR remains `MoonBack` from `lua/moonlift/schema/back.lua`.
- Validation remains mandatory (`moonlift.back_validate`).

## 2.2 New internal ASDL module: `MoonDasm`

Add new schema file: `lua/moonlift/schema/dasm.lua`.

`MoonDasm` models every internal compiler stage as typed immutable values.

### Core ID products
- `DModuleId(text)`
- `DFuncId(text)`
- `DBlockId(text)`
- `DValId(text)`
- `DDataId(text)`
- `DExternId(text)`
- `DSigId(text)`
- `DStackSlotId(text)`
- `DVRegId(text)`
- `DPhysRegId(number)`
- `DLabelId(text)`

### Type + class modeling
- `DRegClass = DGpr | DXmm`
- `DScalarKind = DBool | DI8 | DI16 | DI32 | DI64 | DU8 | DU16 | DU32 | DU64 | DF32 | DF64 | DPtr | DIndex`
- `DShape = DShapeScalar(DScalarKind) | DShapeVec(DScalarKind elem, number lanes)`
- `DValueClass = DValueGpr(DScalarKind) | DValueXmm(DScalarKind) | DValueVec(DScalarKind elem, number lanes)`

### Structured module/function IR
- `DSignature(params: DScalarKind*, results: DScalarKind*)`
- `DDataDecl(size, align, inits: DDataInit*)`
- `DExternDecl(symbol, sig: DSigId)`
- `DFuncDecl(sig: DSigId, visibility: string)`
- `DModuleDecl(sigs, datas, externs, funcs, func_order, data_order, extern_order)`

### CFG + edge-arg model
- `DBlockParam(value: DValId, shape: DShape)`
- `DEdgeArg(src: DValId, dst_param: DValId)`
- `DTerminator`
  - `DTermJump(dest: DBlockId, args: DValId*)`
  - `DTermBrIf(cond, then_dest, then_args, else_dest, else_args)`
  - `DTermSwitch(value, ty, cases, default_dest)`
  - `DTermReturnVoid`
  - `DTermReturnValue(value)`
  - `DTermTrap`
- `DBlock(id, params, body: DNodeCmd*, term: DTerminator)`
- `DFuncCFG(id, sig, blocks, entry_block, stack_slots, value_shapes)`

### MIR / LIR model
- `DMOperand`
  - `DMOpVReg(DVRegId)`
  - `DMOpImmI64(string raw)`
  - `DMOpLabel(DLabelId)`
  - `DMOpMem(base: DVRegId, index: DVRegId?, scale: number, disp: number)`
- `DMInst(opcode: string, defs: DVRegId*, uses: DMOperand*, clobbers: DPhysRegId*)`
- `DMBlock(id, insts: DMInst*, term: DTerminator)`
- `DMFunc(id, blocks, vreg_classes, constraints, abi_info)`

### Allocation + frame model
- `DAllocLoc = DLocReg(DPhysRegId) | DLocStack(number offset, number size, number align)`
- `DValueAlloc(vreg: DVRegId, loc: DAllocLoc)`
- `DFrameLayout(stack_size, spill_size, outgoing_size, callee_saved: DPhysRegId*, slot_offsets)`
- `DLIRInst(opcode, phys_defs, phys_uses, mem, imm, label)`
- `DLIRFunc(id, blocks, allocs, frame)`

### Emit plan model
- `DGlobalEntry(kind: string, key: string, label: DLabelId, slot_index: number)`
- `DFragment(offset: number, args: number*, bytes: string)`
- `DFuncPointer(func: DFuncId, global_slot: number)`
- `DEmitPlan(globals: DGlobalEntry*, fragments: DFragment*, func_ptrs: DFuncPointer*, code_size_hint: number)`

This gives fully typed intermediate states; no untyped Lua tables are phase outputs.

---

## 3) Phase graph (all phases are PVM boundaries)

Each phase is explicit `pvm.phase(...)`.

## 3.1 Module phases

1. `moonlift_dasm_collect_module(program: MoonBack.BackProgram) -> MoonDasm.DModuleDecl`
   - Collect declarations and function bodies.
   - Reject duplicate/undefined contract violations (defensive; validate already ran).

2. `moonlift_dasm_normalize_module(decl: DModuleDecl) -> DModuleDecl`
   - Deterministic order and canonical label/id assignment.
   - Assign stable function/data/extern ordinal indices.

3. `moonlift_dasm_emit_plan(module_lir: DLIRFunc*, module_decl: DModuleDecl, symbols) -> DEmitPlan`
   - Global table layout and label mapping.

4. `moonlift_dasm_link_encode(plan: DEmitPlan) -> runtime artifact`

## 3.2 Per-function phases

1. `moonlift_dasm_build_cfg(func_decl + body_cmds) -> DFuncCFG`
2. `moonlift_dasm_type_values(cfg) -> DFuncCFG`
3. `moonlift_dasm_vector_scalarize(cfg) -> DFuncCFG`
4. `moonlift_dasm_address_normalize(cfg) -> DFuncCFG`
5. `moonlift_dasm_phi_lower(cfg) -> DFuncCFG`
6. `moonlift_dasm_select_mir(cfg) -> DMFunc`
7. `moonlift_dasm_abi_lower_sysv(mir) -> DMFunc`
8. `moonlift_dasm_regalloc(mir) -> DLIRFunc`
9. `moonlift_dasm_frame_layout(lir) -> DLIRFunc`
10. `moonlift_dasm_emit_dynasm(lir, module_decl) -> DFragment*`

All phase outputs are ASDL nodes (`MoonDasm`), not ad-hoc mutable maps.

---

## 4) Command coverage (complete)

## 4.1 Module-level commands

- `CmdTargetModel`: consumed by collect/normalize, influences legality checks and lowering strategy.
- `CmdCreateSig`, `CmdDeclareFunc`, `CmdDeclareExtern`, `CmdDeclareData`, `CmdDataInitZero`, `CmdDataInit`: fully represented in `DModuleDecl`.
- `CmdFinalizeModule`: mandatory terminal assertion.

## 4.2 Function-structure commands

- `CmdBeginFunc`, `CmdFinishFunc`
- `CmdCreateBlock`, `CmdSwitchToBlock`, `CmdSealBlock`
- `CmdBindEntryParams`, `CmdAppendBlockParam`
- `CmdCreateStackSlot`

All are represented in CFG with block params and stack slot specs.

## 4.3 Scalar, float, memory, call, control

All scalar/float/memory/call/control commands are lowered with full semantics.

## 4.4 Vector commands

No runtime “unsupported vector op” path in final architecture.

All vector commands are handled by `vector_scalarize`:
- `CmdVecSplat`
- `CmdVecBinary`
- `CmdVecCompare`
- `CmdVecSelect`
- `CmdVecMask`
- `CmdVecInsertLane`
- `CmdVecExtractLane`
- vector-typed `CmdLoadInfo` / `CmdStoreInfo`

Resulting scalar CFG then follows the same backend pipeline.

---

## 5) Control-flow correctness (phi/block-param)

`phi_lower` is mandatory and explicit:

1. Build predecessor edge map.
2. For each destination block with params, derive edge copies from edge args.
3. Split critical edges where both source has multiple succ and dest has multiple preds.
4. Insert `ParallelCopy` node before jump terminator on each edge.
5. Resolve copy cycles with guaranteed temporary stack slot in frame layout.

After this phase:
- terminators carry no semantic block args,
- all param transfer is explicit copy code,
- allocator sees ordinary defs/uses.

---

## 6) Register allocation (two-bank, complete)

Allocator is global linear-scan over block order with live interval unions across CFG.

- **GPR bank**: rax,rcx,rdx,rbx,rsi,rdi,r8,r9,r10,r11,r12,r13,r14,r15 (`rsp` reserved, `rbp` frame pointer fixed).
- **XMM bank**: xmm0..xmm15.

Rules:
- integer/pointer/index/bool values -> GPR
- f32/f64 values -> XMM
- call ABI constraints fixed at boundaries
- spills inserted by class to typed stack slots
- call-clobber barriers handled by split intervals and reload points

No mixed-bank ambiguity allowed.

---

## 7) ABI model (SysV AMD64)

Handled entirely in ABI lowering phase:

- integer args: rdi,rsi,rdx,rcx,r8,r9 then stack
- float args: xmm0..xmm7 then stack
- integer return: rax
- float return: xmm0
- caller-saved/callee-saved modeled explicitly in MIR clobber metadata
- stack aligned to 16 bytes at each call boundary

`CmdMemcpy` and `CmdMemset` are lowered as ABI calls to resolved extern symbols (`memcpy`, `memset`) with normal clobber handling.

---

## 8) DynASM emission model (state-safe by construction)

No global mutable DynASM parser state sharing between compiles.

Introduce `dynasm_session.lua`:
- each compile obtains a fresh session object encapsulating all mutable assembler state.
- session lifetime = one module compile.
- no `debug.setupvalue` hacks.
- no `package.loaded` reload tricks.

Labels are compiler-generated and sanitized by construction:
- function labels: `->F_<n>`
- extern labels: `->E_<n>`
- data labels: `->D_<n>`
- block labels: `L_<f>_<b>`

No user text ids flow directly to assembler labels.

---

## 9) Artifact/runtime memory ownership

Artifact contains:
- executable mapping handle + size
- function pointer map
- data owner references
- optional disassembly cache metadata

`artifact:free()` is idempotent and releases code + state once.

W^X policy:
- map RW for encode
- `mprotect` RX before callable exposure

---

## 10) Validation and diagnostics integration

Compilation entrypoint does:
1. `back_validate.validate_ll(program)`; fail-fast on any issue.
2. Optional inspect report (`back_inspect`) for debug mode.
3. Optional phase timing + reuse report (`pvm.report_string`) for compiler profiling.

---

## 11) File plan — files to edit

This section is the explicit requested edit map.

## 11.1 Existing files to edit

### Schema wiring
- `lua/moonlift/schema/init.lua`
  - Register/load new `schema/dasm.lua` module.
- `lua/moonlift/schema/back.lua`
  - Add `BackTargetDynasmJit` variant to `BackTarget` (explicit target identity).

### DynASM public entrypoint
- `back/dasm/init.lua`
  - Keep API shape; replace internals to call phase pipeline driver.

### DynASM compiler driver
- `back/dasm/compile.lua`
  - Replace monolithic compiler with orchestrator invoking PVM phases in fixed order.

### DynASM emission/runtime glue
- `back/dasm/encode_x64.lua`
  - Convert into stateless emission helpers used by session object.
- `back/dasm/abi_sysv.lua`
  - Replace static table-only file with full ABI constraints helper API.
- `back/dasm/regalloc.lua`
  - Replace with two-bank allocator (or keep as compatibility shim delegating to new allocator).

### Tests (existing)
- `tests/test_dasm_backend_smoke.lua`
  - Ensure smoke tests cover sequential multi-compile and extern/data calls under new pipeline.
- `tests/test_dasm_backend_full.lua`
  - Update to final parity contract and phase-debug toggles.

## 11.2 New files to add

### New schema module
- `lua/moonlift/schema/dasm.lua`
  - Defines `MoonDasm` ASDL types.

### PVM phase modules (new)
- `back/dasm/phases/collect_module.lua`
- `back/dasm/phases/normalize_module.lua`
- `back/dasm/phases/build_cfg.lua`
- `back/dasm/phases/type_values.lua`
- `back/dasm/phases/vector_scalarize.lua`
- `back/dasm/phases/address_normalize.lua`
- `back/dasm/phases/phi_lower.lua`
- `back/dasm/phases/select_mir.lua`
- `back/dasm/phases/abi_lower_sysv.lua`
- `back/dasm/phases/regalloc_banked.lua`
- `back/dasm/phases/frame_layout.lua`
- `back/dasm/phases/emit_dynasm.lua`
- `back/dasm/phases/link_encode.lua`

### DynASM session and model helpers
- `back/dasm/dynasm_session.lua`
  - Per-compile isolated assembler state object.
- `back/dasm/model.lua`
  - Shared constructors/helpers for `MoonDasm` ASDL nodes.

### Dedicated phase tests (new)
- `tests/test_dasm_phase_collect.lua`
- `tests/test_dasm_phase_cfg_phi.lua`
- `tests/test_dasm_phase_vector_scalarize.lua`
- `tests/test_dasm_phase_regalloc_banked.lua`
- `tests/test_dasm_phase_emit_link.lua`

---

## 12) Acceptance test matrix (mandatory)

The rewritten backend is accepted only if it passes:

1. Existing scalar/control/call/memory parity tests:
   - `tests/test_back_add_i32.lua`
   - `tests/test_back_branch_select.lua`
   - `tests/test_back_call.lua`
   - `tests/test_back_extern_mem.lua`
   - `tests/test_back_memory_data.lua`
   - `tests/test_back_indirect_stmt.lua`
   - `tests/test_back_cast_intrinsic_switch.lua`
   - `tests/test_back_zero_alias_ops.lua`
2. Vector tests (through scalarization):
   - `tests/test_back_vector_smoke.lua`
   - `tests/test_back_vector_select_smoke.lua`
3. Control-region loop tests from tree lowering:
   - `tests/test_tree_to_back_counted_loop.lua`
   - related control multi-block suites.
4. Sequential stress:
   - compile+run hundreds of different programs in one process with no state leakage.

---

## 13) Determinism + reproducibility guarantees

- No hash-order iteration in emitted ordering.
- All function/data/extern order derived from declaration sequence.
- Label names generated from deterministic ordinal assignment.
- Identical `BackProgram` + symbol table => identical action fragments and code bytes.

---

## 14) Why this is PVM-guide compliant

- **ASDL typed layers**: `MoonBack` -> `MoonDasm` CFG/MIR/LIR/emit plan.
- **Boundary discipline**: each lowering step is a named `pvm.phase`.
- **Flatten early**: final emitted representation is flat fragment stream.
- **Identity caching**: phase caching keyed by interned ASDL inputs.
- **Diagnostics**: `pvm.report_string` available for every major phase.

This is not a patch architecture; it is a full typed compiler pipeline.

---

## 15) Implementation order (no semantic gaps)

1. Add `MoonDasm` schema + schema wiring.
2. Implement collect/normalize/build_cfg/type_values.
3. Implement vector scalarization + address normalization.
4. Implement phi lowering.
5. Implement MIR selection + ABI lowering.
6. Implement two-bank regalloc + frame layout.
7. Implement dynasm session + emission + link/encode.
8. Wire `compile.lua` orchestration.
9. Run full acceptance matrix.

No stage is optional in final architecture.
