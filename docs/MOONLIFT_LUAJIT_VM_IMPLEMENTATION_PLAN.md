# Moonlift LuaJIT VM Implementation Plan

> Living implementation plan for the Moonlift-native LuaJIT-grade VM/JIT
> experiment.
>
> Companion architecture document:
> `docs/MOONLIFT_LUAJIT_VM_ARCHITECTURE.md`

---

## 0. How To Use This Document

This is a **live task ledger**, not a static essay.

Rules:

1. Every implementation task gets a stable ID: `P<phase>.<area>.<number>`.
2. Status is represented with checkboxes:
   - `[ ]` not started
   - `[~]` in progress / partially done
   - `[x]` complete
   - `[!]` blocked
   - `[-]` deliberately deferred / cut from current milestone
3. When a task changes architecture, update both:
   - this implementation plan;
   - `docs/MOONLIFT_LUAJIT_VM_ARCHITECTURE.md` if the design contract changed.
4. Never silently change a core invariant. Add a decision note under
   **Decision Log**.
5. Implementation may be staged, but data layout and protocol tasks must not use
   toy shapes that contradict the final architecture.

---

## 1. Current Strategic Decision

We are building a **full LuaJIT-class VM/JIT in Moonlift**, not merely a toy VM.

The VM is organized around Moonlift regions:

```text
state = region/block position
transition = typed jump
external transition = typed continuation
composition = emit
sealing = function
```

Key architectural commitments:

- [x] Region-first VM architecture.
- [x] LuaJIT-like SSA IR: `IRIns`, `TRef`, `REF_BIAS`.
- [x] Snapshots are the deoptimization contract.
- [x] Interpreter opcode dispatch is a `switch`.
- [x] No Lua in the runtime hot path.
- [x] x64 backend first; arm64 later.
- [x] LuaJIT asm backend used as reference/oracle, not final linked dependency.

---

## 2. Blocking Compiler Issues Before VM Coding

These are Moonlift language/compiler blockers that affect the VM experiment.

### P0.COMP — Moonlift Compiler Readiness

- [x] **P0.COMP.001 — Diagnose `region + switch + emit` hang**
  - Result: simple `region + switch + emit` cases compile; the architectural
    issue was ad-hoc region composition living inside `open_expand.lua`.
  - Fix: introduced `lua/moonlift/region_normal_form.lua` as the explicit RNF
    composition boundary.

- [x] **P0.COMP.002 — Build small region-state-machine regression suite**
  - Added `tests/test_region_normal_form.mlua`.
  - Added `tests/test_region_normal_form_recursive.lua`.
  - Covers:
    - `emit` inside switch case;
    - emitted fragment containing switch;
    - dispatch-shaped block using switch+emit;
    - recursive emit cycle rejection.

- [ ] **P0.COMP.003 — Decide struct literal strategy**
  - Current blocker: struct literals documented but parser rejects them.
  - Options:
    - implement struct literals;
    - use constructor functions;
    - use parallel arrays for first VM core.

- [ ] **P0.COMP.004 — Decide field assignment strategy**
  - Current blocker: `p.x = y` not accepted as assignment target.
  - Options:
    - implement field assignment;
    - force explicit setters;
    - use array-backed state structures initially.

- [ ] **P0.COMP.005 — Confirm array element assignment stability**
  - Required for IR buffers, slot maps, stack, register state.

- [ ] **P0.COMP.006 — Confirm module-local region naming and references**
  - Required for generated region families.

Exit criteria for P0:

- [ ] We can compile a module containing a region-composed switch dispatch loop.
- [ ] We can define and mutate VM-state-like data structures.
- [ ] We can run a tiny region state-machine through the normal Moonlift runner.

---

## 3. Architecture Freeze Milestone

Before writing VM code, freeze the contracts that are hardest to change.

### P1.ARCH — Final Shape Documents

- [x] **P1.ARCH.001 — LuaJIT engine map**
  - File: `docs/LUAJIT_ENGINE_MAP.md`

- [x] **P1.ARCH.002 — Full Moonlift VM architecture**
  - File: `docs/MOONLIFT_LUAJIT_VM_ARCHITECTURE.md`

- [x] **P1.ARCH.003 — Assembler reuse strategy**
  - Added to architecture doc.

- [ ] **P1.ARCH.004 — Decide TValue representation for first implementation**
  - Candidate decision: explicit `{tag, payload}` first, with helper abstraction
    allowing later NaN-boxing.

- [ ] **P1.ARCH.005 — Decide bytecode source**
  - Options:
    - LuaJIT-compatible bytecode;
    - Moonlift-defined Lua-like bytecode;
    - direct MoonTree tracing first, bytecode later.
  - Architecture currently assumes LuaJIT-style 32-bit bytecode.

- [ ] **P1.ARCH.006 — Decide number mode**
  - Options:
    - dualnum like LuaJIT;
    - always f64 with integer specialization in traces;
    - explicit int+num tags.

- [ ] **P1.ARCH.007 — Decide C API compatibility target**
  - Full Lua 5.1 API, LuaJIT API subset, or internal-only first.

- [ ] **P1.ARCH.008 — Write `VALUE_LAYOUT.md`**
  - Must specify TValue bits/struct fields, GC pointer identification, stack
    slot layout, snapshot restore layout.

- [ ] **P1.ARCH.009 — Write `IR_LAYOUT.md`**
  - Must specify exact `IRIns`, `TRef`, ref ranges, constants, opcode table,
    side-effect classification.

- [ ] **P1.ARCH.010 — Write `TRACE_LAYOUT.md`**
  - Must specify `Trace`, `SnapShot`, `SnapEntry`, exit state, mcode links.

Exit criteria for P1:

- [ ] Value, IR, Trace, Snapshot, and MCode layouts are documented enough to
  implement without redesign.

---

## 4. Repository Skeleton

### P2.SKEL — File/Module Layout

- [ ] **P2.SKEL.001 — Create `mlua/luajitvm/` root**

- [ ] **P2.SKEL.002 — Create core modules**
  - `core/value.mlua`
  - `core/object.mlua`
  - `core/state.mlua`
  - `core/bytecode.mlua`
  - `core/api.mlua`

- [ ] **P2.SKEL.003 — Create runtime modules**
  - `runtime/dispatch.mlua`
  - `runtime/arith.mlua`
  - `runtime/table.mlua`
  - `runtime/call.mlua`
  - `runtime/meta.mlua`
  - `runtime/upvalue.mlua`
  - `runtime/error.mlua`

- [ ] **P2.SKEL.004 — Create GC modules**
  - `gc/gc.mlua`
  - `gc/alloc.mlua`
  - `gc/barrier.mlua`
  - `gc/mark.mlua`
  - `gc/sweep.mlua`

- [ ] **P2.SKEL.005 — Create JIT modules**
  - `jit/trace.mlua`
  - `jit/record.mlua`
  - `jit/ir.mlua`
  - `jit/emit.mlua`
  - `jit/fold.mlua`
  - `jit/snap.mlua`
  - `jit/opt_dce.mlua`
  - `jit/opt_loop.mlua`
  - `jit/opt_sink.mlua`
  - `jit/opt_split.mlua`
  - `jit/opt_narrow.mlua`

- [ ] **P2.SKEL.006 — Create ASM modules**
  - `asm/asm_state.mlua`
  - `asm/mcode.mlua`
  - `asm/regalloc.mlua`
  - `asm/x64_emit.mlua`
  - `asm/x64_tiles.mlua`
  - `asm/x64_exit.mlua`

- [ ] **P2.SKEL.007 — Create FFI modules**
  - `ffi/ctype.mlua`
  - `ffi/cdata.mlua`
  - `ffi/ccall.mlua`

- [ ] **P2.SKEL.008 — Create generated directory**
  - `generated/opcodes.mlua`
  - `generated/ir_meta.mlua`
  - `generated/fold_rules.mlua`
  - `generated/asm_tiles_x64.mlua`

Exit criteria for P2:

- [ ] Empty/skeleton modules compile.
- [ ] Region signature stubs can be imported from a root VM module.

---

## 5. Core Layout Implementation

### P3.CORE — Values, Objects, State

- [ ] **P3.CORE.001 — Implement primitive aliases and constants**
  - `TValueTag`
  - object type tags
  - status codes
  - trace abort codes

- [ ] **P3.CORE.002 — Implement first TValue representation**
  - explicit tag/payload or selected final representation.

- [ ] **P3.CORE.003 — Implement TValue helper regions/functions**
  - tag checks;
  - int/num conversion;
  - GC pointer extraction;
  - boolean truthiness.

- [ ] **P3.CORE.004 — Implement GC object headers**
  - common header fields;
  - object type tags;
  - pointer casts/helpers.

- [ ] **P3.CORE.005 — Implement string object layout skeleton**

- [ ] **P3.CORE.006 — Implement table object layout skeleton**

- [ ] **P3.CORE.007 — Implement proto/function/upvalue layouts**

- [ ] **P3.CORE.008 — Implement GlobalState layout**

- [ ] **P3.CORE.009 — Implement ThreadState layout**

- [ ] **P3.CORE.010 — Implement bytecode format and decoders**
  - `bc_op`, `bc_a`, `bc_b`, `bc_c`, `bc_d`.

Exit criteria for P3:

- [ ] A minimal state object can be initialized.
- [ ] Bytecode can be decoded.
- [ ] TValue helpers pass direct runner tests.

---

## 6. Region Protocol Stubs

### P4.PROTO — Control Protocol Surface

- [ ] **P4.PROTO.001 — Stub interpreter region signatures**
  - `vm_loop`
  - `vm_bc_add`
  - `vm_bc_call`
  - `vm_bc_ret`
  - `vm_bc_loop`

- [ ] **P4.PROTO.002 — Stub runtime object region signatures**
  - `table_get`
  - `table_set`
  - `metamethod_binop`

- [ ] **P4.PROTO.003 — Stub GC region signatures**
  - `gc_alloc`
  - `gc_step`
  - `gc_barrier_obj`
  - `gc_barrier_back`

- [ ] **P4.PROTO.004 — Stub trace region signatures**
  - `trace_start`
  - `trace_record_root`
  - `trace_record_side`
  - `trace_commit`

- [ ] **P4.PROTO.005 — Stub IR region signatures**
  - `ir_emit`
  - `fold_ir`
  - `snap_add`

- [ ] **P4.PROTO.006 — Stub optimizer region signatures**
  - `optimize_trace`
  - `opt_dce`
  - `opt_loop`
  - `opt_sink`

- [ ] **P4.PROTO.007 — Stub assembler region signatures**
  - `asm_trace`
  - `ra_alloc`
  - `ra_dest`
  - `x64_asm_one_ir`

Exit criteria for P4:

- [ ] The full region protocol surface compiles.
- [ ] Architecture doc and code signatures match.

---

## 7. Interpreter Bring-Up

### P5.INT — Switch Dispatch and Core Opcodes

- [ ] **P5.INT.001 — Implement `vm_loop` switch dispatch**
  - Must use `switch`, not an if-chain.

- [ ] **P5.INT.002 — Implement constant/move opcodes**

- [ ] **P5.INT.003 — Implement integer arithmetic fast path**
  - ADD/SUB/MUL first.

- [ ] **P5.INT.004 — Implement comparisons and conditional branches**

- [ ] **P5.INT.005 — Implement LOOP/hotcount skeleton**

- [ ] **P5.INT.006 — Implement RET**

- [ ] **P5.INT.007 — Add interpreter tests using Moonlift runner**
  - No `Host.eval`.

Exit criteria for P5:

- [ ] A small bytecode program executes through `vm_loop`.
- [ ] LOOP increments hotcount.
- [ ] Return path is typed and explicit.

---

## 8. GC Bring-Up

### P6.GC — Allocation and Barriers

- [ ] **P6.GC.001 — Implement arena/allocator skeleton**

- [ ] **P6.GC.002 — Implement `gc_alloc` protocol**

- [ ] **P6.GC.003 — Implement GC object initialization helpers**

- [ ] **P6.GC.004 — Implement barrier protocol stubs**

- [ ] **P6.GC.005 — Implement minimal mark/sweep or bump-only debug mode**
  - Must preserve final object headers and barrier call sites.

- [ ] **P6.GC.006 — Add allocation tests**

Exit criteria for P6:

- [ ] Runtime objects can be allocated through final `gc_alloc` protocol.
- [ ] Store paths visibly route through barrier-aware edges.

---

## 9. IR and Trace Core

### P7.IR — LuaJIT-Like SSA Core

- [ ] **P7.IR.001 — Implement `IRIns` layout**

- [ ] **P7.IR.002 — Implement `TRef` helpers**

- [ ] **P7.IR.003 — Implement REF_BIAS constant/ref space**

- [ ] **P7.IR.004 — Implement IR buffer grow/append helpers**

- [ ] **P7.IR.005 — Implement constant interning basics**

- [ ] **P7.IR.006 — Implement CSE chain storage**

- [ ] **P7.IR.007 — Implement Trace layout**

- [ ] **P7.IR.008 — Implement Snapshot/SnapEntry layout**

Exit criteria for P7:

- [ ] IR buffers can append constants and instructions.
- [ ] Refs distinguish constants/instructions correctly.
- [ ] Trace and snapshot memory layout is stable.

---

## 10. IR Emit, FOLD, and Snapshots

### P8.EMIT — On-The-Fly Optimizing Emitter

- [ ] **P8.EMIT.001 — Implement raw IR append**

- [ ] **P8.EMIT.002 — Implement `ir_emit` protocol**
  - exits: result, retry, need_snapshot, overflow, abort.

- [ ] **P8.EMIT.003 — Implement minimal CSE**

- [ ] **P8.EMIT.004 — Implement fold dispatcher skeleton**

- [ ] **P8.EMIT.005 — Implement fold rules for integer ADD/SUB/MUL constants**

- [ ] **P8.EMIT.006 — Implement guard emission + `need_snapshot` edge**

- [ ] **P8.EMIT.007 — Implement `snap_add` for stack slots**

- [ ] **P8.EMIT.008 — Add IR emit/fold/snapshot tests**

Exit criteria for P8:

- [ ] `ir_emit` folds constants and CSEs repeated expressions.
- [ ] Guard emission produces snapshots.

---

## 11. Recorder Bring-Up

### P9.REC — Root Trace Recording

- [ ] **P9.REC.001 — Implement trace_start**

- [ ] **P9.REC.002 — Implement slot map initialization**

- [ ] **P9.REC.003 — Implement `rec_getslot` / SLOAD**

- [ ] **P9.REC.004 — Implement recorder ADD/SUB/MUL**

- [ ] **P9.REC.005 — Implement recorder comparisons and guards**

- [ ] **P9.REC.006 — Implement recorder LOOP stop**

- [ ] **P9.REC.007 — Implement trace_finalize skeleton**

- [ ] **P9.REC.008 — Add tests recording a numeric loop into IR**

Exit criteria for P9:

- [ ] A root numeric loop records to SSA IR with SLOADs, arithmetic, guards,
  LOOP marker, and snapshots.

---

## 12. Optimizer Bring-Up

### P10.OPT — First Pipeline

- [ ] **P10.OPT.001 — Implement DCE mark-from-snapshots**

- [ ] **P10.OPT.002 — Implement DCE backward propagation**

- [ ] **P10.OPT.003 — Implement basic loop optimization skeleton**

- [ ] **P10.OPT.004 — Implement substitution table**

- [ ] **P10.OPT.005 — Implement PHI insertion for simple induction values**

- [ ] **P10.OPT.006 — Defer sinking with explicit disabled exit**

- [ ] **P10.OPT.007 — Add optimizer tests**

Exit criteria for P10:

- [ ] Numeric loop trace survives DCE and has sane loop structure.
- [ ] Unsupported optimization paths use typed exits, not silent fallthrough.

---

## 13. x64 Backend Bring-Up

### P11.ASM — MCode, Register Allocation, x64 Tiles

- [ ] **P11.ASM.001 — Implement MCode arena skeleton**

- [ ] **P11.ASM.002 — Implement x64 byte emission helpers**
  - Use LuaJIT as reference/oracle.
  - Preserve attribution if translating routines.

- [ ] **P11.ASM.003 — Implement AsmState layout**

- [ ] **P11.ASM.004 — Implement RegSet helpers**

- [ ] **P11.ASM.005 — Implement minimal register allocator**

- [ ] **P11.ASM.006 — Implement tiles for KINT/SLOAD/ADD/SUB/MUL/RET**

- [ ] **P11.ASM.007 — Implement guard compare + exit jump tile**

- [ ] **P11.ASM.008 — Implement exit stub skeleton**

- [ ] **P11.ASM.009 — Implement mcode commit/cache sync abstraction**

- [ ] **P11.ASM.010 — Add disassembly comparison tests vs LuaJIT oracle where
  practical**

Exit criteria for P11:

- [ ] A simple trace can be assembled to executable x64 mcode.
- [ ] Guard exits jump to an exit stub.

---

## 14. Deoptimization and Side Exits

### P12.EXIT — Snapshot Restore Runtime

- [ ] **P12.EXIT.001 — Implement ExitState layout**

- [ ] **P12.EXIT.002 — Implement exit stub register save convention**

- [ ] **P12.EXIT.003 — Implement `snap_restore` for stack slots**

- [ ] **P12.EXIT.004 — Resume interpreter after guard failure**

- [ ] **P12.EXIT.005 — Implement hot exit counter**

- [ ] **P12.EXIT.006 — Start side trace from hot exit**

- [ ] **P12.EXIT.007 — Patch parent exit to side trace**

Exit criteria for P12:

- [ ] A failing guard restores interpreter state correctly.
- [ ] Repeated hot exit records and links a side trace.

---

## 15. Runtime Semantics Expansion

### P13.RUNTIME — Lua Semantics Beyond Numeric Loops

- [ ] **P13.RUNTIME.001 — Implement string interning**

- [ ] **P13.RUNTIME.002 — Implement table array/hash lookup**

- [ ] **P13.RUNTIME.003 — Implement table store + barriers**

- [ ] **P13.RUNTIME.004 — Implement metamethod lookup and negative cache**

- [ ] **P13.RUNTIME.005 — Implement Lua calls/returns**

- [ ] **P13.RUNTIME.006 — Implement closures/upvalues**

- [ ] **P13.RUNTIME.007 — Implement varargs**

- [ ] **P13.RUNTIME.008 — Implement coroutines/yield protocol**

- [ ] **P13.RUNTIME.009 — Implement base library subset**

Exit criteria for P13:

- [ ] Nontrivial Lua-like programs run in interpreter.
- [ ] Recorder either records supported fast paths or aborts explicitly.

---

## 16. FFI Milestone

### P14.FFI — CType, CData, C Calls

- [ ] **P14.FFI.001 — Implement CType primitive table**

- [ ] **P14.FFI.002 — Implement pointer/array/struct CType layouts**

- [ ] **P14.FFI.003 — Implement CData allocation**

- [ ] **P14.FFI.004 — Implement cdata index/store**

- [ ] **P14.FFI.005 — Implement x64 C call ABI classification**

- [ ] **P14.FFI.006 — Implement interpreter FFI calls**

- [ ] **P14.FFI.007 — Implement JIT lowering for simple C calls**

Exit criteria for P14:

- [ ] Basic cdata arithmetic/access and simple C calls work.

---

## 17. Self-Hosting Milestone

### P15.SELF — Bootstrap Experiment

- [ ] **P15.SELF.001 — Compile VM/JIT once with current Moonlift pipeline**

- [ ] **P15.SELF.002 — Run Moonlift compiler workload under VM**

- [ ] **P15.SELF.003 — JIT hot compiler paths**

- [ ] **P15.SELF.004 — Compile VM/JIT using itself**

- [ ] **P15.SELF.005 — Verify stage1/stage2 output equivalence**

Exit criteria for P15:

- [ ] Self-hosted rebuild succeeds.

---

## 18. Testing Policy

- [ ] **TEST.001 — All `.mlua` tests use the Moonlift runner directly**
  - Do not use `Host.eval` for runtime behavior tests.

- [ ] **TEST.002 — Every region protocol gets at least one compile test**

- [ ] **TEST.003 — Every layout gets size/offset tests where possible**

- [ ] **TEST.004 — Interpreter tests compare expected stack/results**

- [ ] **TEST.005 — IR tests dump/compare stable textual IR**

- [ ] **TEST.006 — Optimizer tests compare before/after IR**

- [ ] **TEST.007 — ASM tests compare disassembly or machine-code behavior**

- [ ] **TEST.008 — Deopt tests assert exact restored stack/pc state**

---

## 19. Live Documentation Maintenance Protocol

When editing code, update docs as follows:

### 19.1 If a task is started

- Change `[ ]` to `[~]` in this file.
- Add implementation file path under the task if useful.

### 19.2 If a task is completed

- Change `[~]` or `[ ]` to `[x]`.
- Add a short completion note if the result differs from the plan.
- Add tests performed.

### 19.3 If a task is blocked

- Change checkbox to `[!]`.
- Add:
  - blocker reason;
  - reproducer path if any;
  - proposed options.

### 19.4 If architecture changes

- Update `docs/MOONLIFT_LUAJIT_VM_ARCHITECTURE.md`.
- Add entry to Decision Log below.
- If the change affects layouts, update or create:
  - `docs/VALUE_LAYOUT.md`
  - `docs/IR_LAYOUT.md`
  - `docs/TRACE_LAYOUT.md`

### 19.5 If a shortcut is introduced

Shortcuts are allowed only if they preserve final interfaces.

Document shortcut as:

```text
Temporary shortcut:
  What:
  Why:
  Final-compatible because:
  Removal task:
```

---

## 20. Decision Log

### D001 — Region-first architecture

- Status: accepted.
- Decision: VM internals are modeled as typed region state machines.
- Rationale: LuaJIT's hardest invariants are control-flow protocols.

### D002 — LuaJIT-like SSA IR

- Status: accepted.
- Decision: use `IRIns`, `TRef`, and `REF_BIAS` style IR.
- Rationale: proven low-level model and compatible with LuaJIT design study.

### D003 — Assembler reuse strategy

- Status: accepted.
- Decision: LuaJIT backend is reference/oracle; final backend is Moonlift-native.
- Rationale: `lj_asm.c` is not standalone and would drag in LuaJIT internals.

### D004 — x64 first

- Status: accepted.
- Decision: x64 backend before arm64.
- Rationale: smaller immediate target, easier oracle comparison.

### D005 — Region Normal Form compiler boundary

- Status: accepted and implemented.
- Decision: region `emit` composition is a dedicated RNF pass/module, not hidden
  as ad-hoc syntax-tree expansion in `open_expand.lua`.
- Implementation: `lua/moonlift/region_normal_form.lua`.
- Rationale: the VM uses regions as its core CFG composition mechanism, so block
  import, alpha-renaming, continuation routing, and recursive-cycle detection
  must be explicit compiler infrastructure.

---

## 21. Current Blockers

- [x] **Region composition is now first-class enough to start VM skeleton work.**
  - Implemented RNF in `lua/moonlift/region_normal_form.lua`.
  - `open_expand.lua` now delegates control-region composition to RNF.
  - Regression tests cover switch+emit dispatch shapes and recursive emit cycle
    rejection.

- [!] Struct literals not implemented.
- [!] Struct field assignment not implemented.

---

## 22. Next Immediate Actions

1. [x] Design Region Normal Form (RNF) as the clean compiler boundary for
   composed control graphs.
2. [x] Replace ad-hoc region emit expansion with RNF lowering:
   emit-site -> imported blocks + entry jump + typed continuation routes.
3. [x] Add regression tests for emit inside switch arms, switch inside emitted
   fragments, continuation forwarding, dispatch-style blocks, and recursive
   emit rejection.
4. [ ] Create `VALUE_LAYOUT.md`, `IR_LAYOUT.md`, `TRACE_LAYOUT.md` drafts.
5. [ ] Create `mlua/luajitvm/` skeleton once RNF is viable.

---

## 23. Completion Definition

The experiment reaches its first full success when:

- [ ] A Lua-like program runs in the interpreter.
- [ ] A hot numeric loop records into SSA IR.
- [ ] The trace optimizes through DCE/LOOP.
- [ ] x64 machine code is emitted.
- [ ] A guard side exit restores interpreter state.
- [ ] A hot side exit records and links a side trace.
- [ ] The runtime path contains no Lua.
- [ ] The VM/JIT can compile a meaningful Moonlift compiler workload.
