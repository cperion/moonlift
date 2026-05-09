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
- [x] Named protocol exit types as the architectural contract (`docs/VM_PROTOCOL_DESIGN.md`).
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

- [x] **P0.COMP.007 — Named protocol exit syntax**
  - Tagged-union variants now carry named fields: `type P = exit(field: T) | ...`
  - `region r(...) -> P` syntax lowers protocol type to continuation slots.
  - Parser, `.mlua` parser, template parser all updated.
  - `docs/PROTOCOL_SYNTAX.md` documents the surface syntax.
  - `tests/test_protocol_syntax.lua` regression suite.

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

- [x] **P1.ARCH.011 — VM protocol design**
  - File: `docs/VM_PROTOCOL_DESIGN.md`
  - Full protocol catalog: all 25 protocol types across every VM subsystem.
  - `TraceAbort` data union matching `lj_traceerr.h` TREDEF table exactly.
  - Protocol hierarchy diagram.
  - Grammar library upgrade path.
  - M0–M12 milestone-to-protocol-type mapping.

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

- [x] **P2.SKEL.001 — Create `mlua/luajitvm/` root**
  - Done. 7 subdirectories created.

- [x] **P2.SKEL.009 — Create `mlua/luajitvm/protocols.mlua` (M0)**
  - All 25 protocol types declared.
  - All data types declared: `TraceAbort` (34 variants matching TREDEF), `TraceLink`.
  - Compiles and verifies with sentinel `protocols_version() -> i32`.
  - Key syntax discoveries documented in file header comments.

- [x] **P2.SKEL.002 — Create core modules**
  - [x] `core/value.mlua`
  - [x] `core/object.mlua`
  - [x] `core/state.mlua`
  - [x] `core/bytecode.mlua`
  - [x] `core/api.mlua`

- [x] **P2.SKEL.003 — Create runtime modules**
  - [x] `runtime/dispatch.mlua`
  - [x] `runtime/arith.mlua`
  - [x] `runtime/table.mlua`
  - [x] `runtime/call.mlua`
  - [x] `runtime/meta.mlua`
  - [x] `runtime/upvalue.mlua`
  - [x] `runtime/error.mlua`

- [x] **P2.SKEL.004 — Create GC modules**
  - [x] `gc/gc.mlua`
  - [x] `gc/alloc.mlua`
  - [x] `gc/barrier.mlua`
  - [x] `gc/mark.mlua`
  - [x] `gc/sweep.mlua`

- [x] **P2.SKEL.005 — Create JIT modules**
  - [x] `jit/trace.mlua`
  - [x] `jit/record.mlua`
  - [x] `jit/ir.mlua`
  - [x] `jit/emit.mlua`
  - [x] `jit/fold.mlua`
  - [x] `jit/snap.mlua`
  - [x] `jit/opt_dce.mlua`
  - [x] `jit/opt_loop.mlua`
  - [x] `jit/opt_sink.mlua`
  - [x] `jit/opt_split.mlua`
  - [x] `jit/opt_narrow.mlua`

- [x] **P2.SKEL.006 — Create ASM modules**
  - [x] `asm/asm_state.mlua`
  - [x] `asm/mcode.mlua`
  - [x] `asm/regalloc.mlua`
  - [x] `asm/x64_emit.mlua`
  - [x] `asm/x64_tiles.mlua`
  - [x] `asm/x64_exit.mlua`

- [x] **P2.SKEL.007 — Create FFI modules**
  - [x] `ffi/ctype.mlua`
  - [x] `ffi/cdata.mlua`
  - [x] `ffi/ccall.mlua`

- [x] **P2.SKEL.008 — Create generated directory**
  - [x] `generated/opcodes.mlua`
  - [x] `generated/ir_meta.mlua`
  - [x] `generated/fold_rules.mlua`
  - [x] `generated/asm_tiles_x64.mlua`

Exit criteria for P2:

- [x] Empty/skeleton modules compile.
- [x] Region signature stubs can be imported from a root VM module.
- [x] `.mlua` module names match Lua-style require paths, e.g.
  `module "luajitvm.asm.x64_tiles"`, so `moon.require("luajitvm.asm.x64_tiles")`
  returns the intended module table.

---

## 5. Core Layout Implementation

### P3.CORE — Values, Objects, State

- [x] **P3.CORE.001 — Implement primitive aliases and constants**
  - `core/value.mlua`: all 14 TValue tag constants (`LUA_TNIL` through `LUA_TLIGHTUD`).
  - `core/object.mlua`: 9 GC type tags, 4 mark colors, 4 header offset constants.
  - `core/state.mlua`: 6 status codes, 8 ThreadState offset constants.
  - `core/bytecode.mlua`: 96 opcode constants matching LuaJIT bcdef.h layout.

- [x] **P3.CORE.002 — Implement first TValue representation**
  - Explicit tag/payload: [tag:i32][pad:i32][payload:i64] = 16 bytes.
  - Access via typed pointer views: `ptr(i32)` for 32-bit fields, `ptr(i64)` for payload.
  - Documented in `docs/VALUE_LAYOUT.md`.

- [x] **P3.CORE.003 — Implement TValue helper functions**
  - `tv_tag`, `tv_payload` — read fields
  - `tv_set`, `tv_set_tag`, `tv_set_payload` — write fields
  - `tv_is_nil`, `tv_is_false`, `tv_is_true`, ..., `tv_is_lightud` — 12 tag predicates
  - `tv_is_pri`, `tv_is_gcv`, `tv_is_number`, `tv_is_truthy` — range predicates
  - `tv_set_nil`, `tv_set_false`, `tv_set_true`, `tv_set_int`, `tv_set_num` — convenience setters
  - `tv_get_int`, `tv_copy` — value accessors
  - All in `core/value.mlua`, tested via `tests/test_luajitvm_core.mlua`.

- [x] **P3.CORE.004 — Implement GC object headers**
  - `gc_gct`, `gc_set_gct` — type tag access
  - `gc_marked`, `gc_set_marked` — mark color access
  - `gc_is_white`, `gc_is_gray`, `gc_is_black` — color predicates
  - All in `core/object.mlua`, tested via `tests/test_luajitvm_core.mlua`.

- [x] **P3.CORE.005 — Implement string object layout skeleton**
  - `core/string.mlua`: GCstr header size (24 bytes), field offsets, u8/u32 accessors, sentinel.
  - Verified against LuaJIT FFI offset test.

- [x] **P3.CORE.006 — Implement table object layout skeleton**
  - `core/table.mlua`: GCtab (56 bytes), Node (48 bytes), array/node/metatable/asize/hmask accessors.

- [x] **P3.CORE.007 — Implement proto/function/upvalue layouts**
  - `core/proto.mlua`: GCproto (96 bytes), numparams/framesize/sizebc/k/uv/sizekgc/sizekn/sizeuv/flags/trace/chunkname/lineinfo.
  - `core/func.mlua`: GCfuncC (48 bytes base), GCfuncL (40 bytes base), ffid/nupvalues/env/pc/f/uvptr, type predicates.
  - `core/upval.mlua`: GCupval (48 bytes), closed/immutable/v/prev/next/dhash, open/closed chain access.

- [x] **P3.CORE.008 — Implement GlobalState layout**
  - `core/global.mlua`: global_State (552 bytes), GCState embedded (104 bytes), StrInternState embedded (32 bytes).
  - Accessors for: allocf/allocd, gc.total/threshold/currentwhite/state/root/gray, strtab/strmask/strnum, vmstate, mainthread, cur_L.

- [x] **P3.CORE.009 — Implement ThreadState layout**
  - `core/state.mlua`: Complete lua_State layout (96 bytes) with correct LuaJIT offsets.
  - Fields: gct, status, glref, base, top, maxstack, stack, openupval, env, cframe, stacksize.
  - Status codes: LUA_OK, LUA_YIELD, LUA_ERRRUN, LUA_ERRSYNTAX, LUA_ERRMEM, LUA_ERRERR.

- [x] **P3.CORE.010 — Implement bytecode format and decoders**
  - `bc_op`, `bc_a`, `bc_b`, `bc_c`, `bc_d`.
  - 96 opcode constants.
  - All in `core/bytecode.mlua`, tested via `tests/test_luajitvm_core.mlua`.

Exit criteria for P3:

- [x] TValue helpers pass direct runner tests.
- [x] Bytecode can be decoded.
- [x] GC header accessors work on ptr(u8) memory.
- [x] All 6 GC object type layouts (GCstr, GCtab, GCproto, GCfuncC/L, GCupval) have offset constants and accessors.
- [x] GlobalState and ThreadState have complete offset constants and accessors.
- [x] All layout modules compile and verify sentinel values.

---

## 6. Region Protocol Stubs

### P4.PROTO — Control Protocol Surface

- [x] **P4.PROTO.001 — Create M0 protocol type file**
  - `mlua/luajitvm/protocols.mlua` compiles and verifies.

- [x] **P4.PROTO.002 — Stub interpreter region signatures**
  - `vm_loop` → `InterpResult` ✔ `runtime/dispatch.mlua`
  - `vm_bc_add`, `vm_bc_sub`, `vm_bc_mul` → `OpcodeResult` ✔ `runtime/arith.mlua`
  - `vm_bc_call`, `vm_bc_ret` → `OpcodeResult`/`ReturnResult` ✔ `runtime/call.mlua`

- [x] **P4.PROTO.003 — Stub runtime object region signatures**
  - `table_get` → `TableGet` ✔ `runtime/table.mlua`
  - `table_set` → `TableSet` ✔ `runtime/table.mlua`
  - `metamethod_binop` → `MetamethodResult` ✔ `runtime/meta.mlua`

- [x] **P4.PROTO.004 — Stub GC region signatures**
  - `gc_alloc` → `AllocResult` ✔ `gc/alloc.mlua`
  - `gc_step` → `GCStepResult` ✔ `gc/alloc.mlua`
  - `gc_barrier_fwd`, `gc_barrier_back` → `BarrierResult` ✔ `gc/barrier.mlua`

- [x] **P4.PROTO.005 — Stub trace region signatures**
  - `trace_record_root` → `TraceRecord` ✔ `jit/trace.mlua`
  - `trace_record_side` → `TraceRecordSide` ✔ `jit/trace.mlua`
  - `trace_commit` → `TraceCommit` ✔ `jit/trace.mlua`

- [x] **P4.PROTO.006 — Stub IR region signatures**
  - `ir_emit` → `IREmit` ✔ `jit/ir.mlua`
  - `ir_fold` → `FoldResult` ✔ `jit/ir.mlua`
  - `snap_add` → `SnapAdd` ✔ `jit/snap.mlua`
  - `snap_restore` → `SnapRestore` ✔ `jit/snap.mlua`
  - `rec_getslot` → `SlotGet` ✔ `jit/record.mlua`
  - `rec_bc_add`, `rec_bc_tgetv`, `rec_bc_call` → `Rec*` ✔ `jit/record.mlua`

- [x] **P4.PROTO.007 — Stub optimizer region signatures**
  - `opt_dce` → `DCEResult` ✔ `jit/opt_dce.mlua`
  - `opt_loop` → `LoopOptResult` ✔ `jit/opt_loop.mlua`
  - `opt_sink` → `SinkResult` ✔ `jit/opt_sink.mlua`
  - `opt_narrow` → `NarrowResult` ✔ `jit/opt_narrow.mlua`
  - `optimize_trace` → `OptResult` ✔ `asm/asm_state.mlua`

- [x] **P4.PROTO.008 — Stub assembler region signatures**
  - `asm_trace` → `AsmResult` ✔ `asm/asm_state.mlua`
  - `x64_asm_one_ir` → `TileResult` ✔ `asm/x64_tiles.mlua`
  - `ra_alloc` → `RAAlloc` ✔ `asm/regalloc.mlua`
  - `ra_dest` → `RADest` ✔ `asm/regalloc.mlua`
  - `mcode_reserve` → `MCodeReserve` ✔ `asm/mcode.mlua`
  - `patch_trace_link` → `PatchBranch` ✔ `asm/mcode.mlua`
  - `emit_exit_stub` → `ExitStubResult` ✔ `asm/mcode.mlua`

Exit criteria for P4:

- [x] The full region protocol surface compiles.
- [x] Architecture doc and code signatures match.
- [x] VM modules import canonical protocol types from
  `moon.require("luajitvm.protocols")`; canonical protocol type declarations are
  no longer duplicated in subsystem files. One-off local helper regions use
  inline continuation parameters instead of ad-hoc local protocol types.

---

## 7. Interpreter Bring-Up

### P5.INT — Switch Dispatch and Core Opcodes

- [x] **P5.INT.001 — Implement `vm_loop` switch dispatch**
  - `runtime/dispatch.mlua`: region-based dispatch loop with `switch op do`.
  - Reads BCIns from `ptr(u32)` array, decodes op/A/B/C/D fields inline.
  - Stack access via typed pointer views (`ptr(i32)` for tags, `ptr(i64)` for payloads).
  - ThreadState extended with `TS_OFF_PC` (i32 instruction offset).

- [x] **P5.INT.002 — Implement constant/move opcodes**
  - KSHORT: sign-extended 16-bit literal → integer slot.
  - MOV: copy 16-byte TValue between stack slots.

- [x] **P5.INT.003 — Implement integer arithmetic fast path**
  - ADDVV, SUBVV, MULVV: slot[dest] = slot[src1] op slot[src2].
  - All operands read as i32 from payload, result stored with LUA_TINT tag.

- [x] **P5.INT.004 — Implement comparisons and conditional branches**
  - ISLT, ISGE, ISEQV, ISNEV: `as(i32, bool)` works for arithmetic skip-offset.
  - JMP: unconditional signed 16-bit offset branch.
  - Pattern: `skip = 2 - as(i32, bv < cv)`; jump dispatch at `ip + skip`.

- [x] **P5.INT.005 — Implement LOOP/hotcount skeleton**
  - LOOP: back-edge branch with signed 16-bit offset works.
  - Hotcount mechanism deferred (no JIT integration yet).

- [x] **P5.INT.006 — Implement RET**
  - RET: D = nresults+1, exits via `returned(nresults)` protocol.
  - RET0: returns 0 results.
  - RET1: returns 1 result from slot A.

- [x] **P5.INT.007 — Add interpreter tests using Moonlift runner**
  - `tests/test_interpreter_run.lua`: FFI-backed smoke tests.
  - 8 tests: KSHORT, MOV, arithmetic, sum, JMP, LOOP, SUBVV, MULVV.
  - Stack buffers allocated with LuaJIT FFI, ThreadState wired manually.
  - No `Host.eval`.

Exit criteria for P5:

- [x] A small bytecode program executes through `vm_loop`.
- [x] LOOP branches correctly (hotcount mechanism deferred).
- [x] Return path is typed and explicit (`returned(nresults)` protocol).
- [x] ISLT/ISGE/ISEQV/ISNEV work via `as(i32, bool)` arithmetic offset.

---

## 8. GC Bring-Up

### P6.GC — Allocation and Barriers

- [x] **P6.GC.001 — Implement arena/allocator skeleton**
  - `gc/alloc.mlua`: gc_init_object, gc_link, gc_init_and_link, mark helpers.
  - Allocation done by host (FFI in tests); Moonlift does header init + intrusive list maintenance.
  - Bump allocator deferred (Moonlift lacks ptr arithmetic for arena+offset).

- [x] **P6.GC.002 — Implement gc_alloc protocol**
  - gc_init_and_link(G, obj, gct): reads currentwhite from G[32], inits header, links into G.allgc.

- [x] **P6.GC.003 — Implement GC object initialization helpers**
  - gc_init_object: sets next=NULL, marked=currentwhite, gct=type tag.
  - gc_mark_black/gc_mark_gray: update marked byte.
  - gc_is_white/gc_is_black: query marked color.

- [x] **P6.GC.004 — Implement barrier protocol stubs**
  - `gc/barrier.mlua`: gc_barrier_fwd, gc_barrier_back as no-op stubs.
  - Call sites preserved; real implementation when incremental GC lands.

- [x] **P6.GC.005 — Minimal mark helpers**
  - Mark colors: WHITE0/WHITE1/GRAY/BLACK.
  - No sweep or full GC cycle yet (deferred to incremental GC phase).

- [x] **P6.GC.006 — Add allocation tests**
  - `tests/test_gc_alloc.lua`: FFI-allocated objects, init+link, verify headers, intrusive list, mark ops.

Exit criteria for P6:

- [x] Runtime objects can be allocated through gc_init_and_link.
- [x] Store paths visibly route through barrier-aware edges (stubs).
- [x] GC headers verified: next=NULL, marked=currentwhite, gct=type tag.
- [x] Intrusive allgc list maintained (G.root → obj3 → obj2 → obj1 → NULL).

---

## 9. IR and Trace Core

### P7.IR — LuaJIT-Like SSA Core

- [x] **P7.IR.001 — Implement `IRIns` layout**
  - `jit/ir.mlua`: IRIns as packed u64, field offsets, op/type/op1/op2 accessors.
  - `docs/IR_LAYOUT.md` documents the 8-byte layout.
  - Tests: `tests/test_ir_layout.lua` (8 tests).

- [x] **P7.IR.002 — Implement `TRef` helpers**
  - TRef = (IRType << 24) | IRRef, REF_BIAS constant, ref classification.

- [x] **P7.IR.003 — Implement REF_BIAS constant/ref space**
  - REF_BIAS = 0x8000; constants below, instructions above.
  - REF_FIRST = 0x8001; REF_NIL = 0x7FFF.

- [x] **P7.IR.004 — Implement IR buffer grow/append helpers**
  - `jit/emit.mlua`: ir_emit region appends instructions; nins counter tracks fill.
  - Emit regions write directly to `ptr(u64)` IR buffer.

- [x] **P7.IR.005 — Implement constant interning basics**
  - `ir_emit_const` region interns KINT constants below REF_BIAS.
  - Scans downward from nk; reuses existing equal constant.

- [x] **P7.IR.006 — Implement CSE chain storage**
  - `ir_emit` uses `prev` field (bits 48-63) as CSE hash chain link.
  - Full CSE requires hash table; current: emit writes prev=0 (no chain).

- [x] **P7.IR.007 — Implement Trace layout**
  - `jit/trace.mlua`: full GCtrace/SnapShot/SnapEntry layout, 30 consts + 19 funcs.
  - Sentinel = 208; verified against LuaJIT lj_jit.h.
  - `docs/TRACE_LAYOUT.md` documents the layout.

- [x] **P7.IR.008 — Implement Snapshot/SnapEntry layout**
  - SnapShot: mapofs/ref/mcofs/nslots/topslot/nent/count fields.
  - SnapEntry: slot+flags+ref packed in u32.
  - Snap buffer append/read in `jit/snap.mlua`.

Exit criteria for P7:

- [x] IR buffers can append constants and instructions.
- [x] Refs distinguish constants/instructions correctly.
- [x] Trace and snapshot memory layout is stable.

---

## 10. IR Emit, FOLD, and Snapshots

### P8.EMIT — On-The-Fly Optimizing Emitter

- [x] **P8.EMIT.001 — Implement raw IR append**
  - `ir_emit` region: pack IRIns into u64, write at irbuf[nins], increment nins.
  - Guard bit check determines snapshot requirement.

- [x] **P8.EMIT.002 — Implement `ir_emit` protocol**
  - `jit/emit.mlua`: exits: result(ref), overflow, guard_emitted(ref).
  - Shortcut: guard exits go to `guard_emitted` not `need_snapshot` (snap called separately).

- [-] **P8.EMIT.003 — Implement minimal CSE**
  - Deferred. CSE chain infrastructure in place; hash lookup not yet wired.

- [x] **P8.EMIT.004 — Implement fold dispatcher skeleton**
  - `jit/fold.mlua`: `fold_ins` region with const folding, identity removal,
    commutative normalization.

- [x] **P8.EMIT.005 — Implement fold rules for integer ADD/SUB/MUL constants**
  - 15 fold tests pass: ADD/SUB/MUL identity, const folding, commutativity.

- [x] **P8.EMIT.006 — Implement guard emission + snapshot edge**
  - IRT_GUARD flag set in type byte for SLOAD with type guard.
  - `snap_add` called for guard instructions.

- [x] **P8.EMIT.007 — Implement `snap_add` for stack slots**
  - `jit/snap.mlua`: `snap_add` region with iter+commit blocks.
  - 23 snapshot integration tests pass.

- [x] **P8.EMIT.008 — Add IR emit/fold/snapshot tests**
  - `tests/test_emit_integration.lua` (5 tests)
  - `tests/test_fold_integration.lua` (15 tests)
  - `tests/test_snap_integration.lua` (23 tests)

Exit criteria for P8:

- [x] `ir_emit` folds constants and CSEs repeated expressions (partial: folding done, CSE deferred).
- [x] Guard emission produces snapshots.

---

## 11. Recorder Bring-Up

### P9.REC — Root Trace Recording

- [x] **P9.REC.001 — Implement trace_start / trace_init**
  - `jit/record.mlua`: `trace_init` region initialises JitState IR buffer,
    sets nins=REF_BIAS+1, nk=REF_BIAS, seeds snap buffer.

- [x] **P9.REC.002 — Implement slot map initialization**
  - Slot map: j32[slot*2] = TRef. Initialized to 0 (unrecorded).

- [x] **P9.REC.003 — Implement `rec_getslot` / SLOAD**
  - `rec_sload` region: emits IR_SLOAD with IRT_INT | IRT_GUARD.
  - First access allocates; subsequent reuse slot map.

- [x] **P9.REC.004 — Implement recorder ADD/SUB/MUL**
  - `rec_arith` region: emits IR_ADD/SUB/MUL, routes through fold/emit.

- [-] **P9.REC.005 — Implement recorder comparisons and guards**
  - Deferred. ISLT/ISGE emit comparison guard IR not yet in recorder.

- [-] **P9.REC.006 — Implement recorder LOOP stop**
  - Stub only. LOOP back-edge detection deferred.

- [-] **P9.REC.007 — Implement trace_finalize skeleton**
  - Deferred. Trace commit/patch not yet implemented.

- [x] **P9.REC.008 — Add tests recording a numeric loop into IR**
  - `tests/test_record_integration.lua` (31 tests): trace_init, rec_sload, rec_arith.

Exit criteria for P9:

- [~] A root numeric loop records to SSA IR with SLOADs, arithmetic, guards,
  LOOP marker, and snapshots. (SLOADs + arith + guards done; LOOP stop deferred)

---

## 12. Optimizer Bring-Up

### P10.OPT — First Pipeline

- [x] **P10.OPT.001 — Implement DCE mark-from-snapshots**
  - `jit/opt_dce.mlua`: Phase 1 marks all guard/SLOAD/LOOP instructions live.
  - Shortcut: marks from snapshots not yet done (marks side-effect instructions directly).

- [x] **P10.OPT.002 — Implement DCE backward propagation**
  - `dce_pass` region: backward scan propagates liveness from live operands;
    dead instructions replaced with IR_NOP.
  - 17 DCE integration tests pass.

- [-] **P10.OPT.003 — Implement basic loop optimization skeleton**
  - `jit/opt_loop.mlua`: stub only.

- [-] **P10.OPT.004 — Implement substitution table**
  - Deferred.

- [-] **P10.OPT.005 — Implement PHI insertion for simple induction values**
  - Deferred.

- [-] **P10.OPT.006 — Defer sinking with explicit disabled exit**
  - `jit/opt_sink.mlua`: stub with `disabled()` exit. Correct.

- [x] **P10.OPT.007 — Add optimizer tests**
  - `tests/test_dce_integration.lua` (17 tests).

  **Shortcut documented:**
  ```
  Temporary shortcut:
    What:  dce_pass takes (irbuf, marks, nins) not (J, tr).
    Why:   JitState/trace lookup not yet wired.
    Final-compatible because: irbuf+nins accessible from J.cur.ir+J.cur.nins.
    Removal task: P12 wiring — wrap dce_pass in opt_dce(J, tr) region.
  ```

Exit criteria for P10:

- [x] DCE backward propagation eliminates dead instructions.
- [-] Loop optimization deferred; unsupported path uses `not_loop()` typed exit.

---

## 13. x64 Backend Bring-Up

### P11.ASM — MCode, Register Allocation, x64 Tiles

- [x] **P11.ASM.001 — Implement MCode arena skeleton**
  - `asm/mcode.mlua`: mcode_init, mc_reserve, mc_emit_byte/u32 regions.
  - Code grows DOWNWARD (LuaJIT style); mctop/mcbot in JitState j64[4]/j64[5].

- [x] **P11.ASM.002 — Implement x64 byte emission helpers**
  - `asm/x64_emit.mlua`: emit_mov_rr, emit_add_rr, emit_sub_rr, emit_imul_rr,
    emit_mov_ri32, emit_ret, emit_push/pop_r as one-off regions with inline
    `ok/full/abort` continuations.
  - 16 tests pass including execution of generated code via mmap(RWX).

- [x] **P11.ASM.003 — Implement AsmState layout**
  - AsmState: A[0..3]=free_regs, A[4..259]=regmap, A[260..267]=exit_stub_addr.
  - rdi (register 7) reserved as Lua base pointer; excluded from free set.

- [x] **P11.ASM.004 — Implement RegSet helpers**
  - bit_scan_low, ra_get/set/clear/free_regs/assigned as funcs.
  - FREE_REGS_ALL = 0x0F47 (rax,rcx,rdx,rsi,r8-r11).

- [x] **P11.ASM.005 — Implement minimal register allocator**
  - `asm/regalloc.mlua`: `ra_alloc`/`ra_dest` are proper regions with canonical
    `protocols.RAAlloc`/`protocols.RADest` exits.
  - Backward linear scan; no remat/spill yet (`fail` exit on exhaustion).
  - `asm_state.mlua` still keeps small local regmap helpers for backward-scan
    bookkeeping, but the architectural allocator entrypoints are regions.

- [x] **P11.ASM.006 — Implement tiles for KINT/SLOAD/ADD/SUB/MUL/RET**
  - `asm/x64_tiles.mlua`: `x64_asm_one_ir` is a `switch` region.
  - Individual tiles `x64_ir_kint`, `x64_ir_sload`, `x64_ir_add`, `x64_ir_sub`,
    `x64_ir_mul`, `x64_ir_retf` are regions returning canonical `TileResult`.
  - `asm_state.mlua` backward scan composes the tile dispatcher with `emit`.

- [x] **P11.ASM.007 — Implement guard compare + exit jump tile**
  - `x64_ir_sload`: CMP [rdi+slot*16], LUA_TINT; JNE exit_stub; MOV dst, payload.
  - IRT_GUARD flag detection via IR type byte.

- [x] **P11.ASM.008 — Implement exit stub skeleton**
  - Single shared deopt stub: MOV rax, DEOPT_SENTINEL; RET.
  - Emitted first (highest address); guards jump upward to it.
  - **Shortcut:** single stub instead of per-snapshot stubs.

- [-] **P11.ASM.009 — Implement mcode commit/cache sync abstraction**
  - Deferred. mmap(RWX) used directly in tests.

- [x] **P11.ASM.010 — Add tests**
  - `tests/test_x64_emit.lua` (16 tests, including RWX execution)
  - `tests/test_asm_pipeline.lua` (13 tests: KINT+RETF, ADD, SUB, MUL, chained
    arithmetic, NOP skip, SLOAD from stack, guards pass/fail)

  **Shortcut documented:**
  ```
  Temporary shortcut:
    What:  asm_trace(A, J, ir_buf, nins) not asm_trace(J, tr).
    Why:   GCtrace lookup via JitState not yet wired.
    Final-compatible because: ir_buf = J.cur.ir, nins = J.cur.nins.
    Removal task: P12 wiring.
  What:  single shared deopt stub instead of per-snapshot/per-exit stubs.
    Why:   snapshot restore and exit-state layout are not wired yet.
    Final-compatible because: guard sites already branch through an explicit exit
      edge; P12 will replace the sentinel stub with real snapshot restore stubs.
    Removal task: P12 deopt wiring.
  ```

  **P11.ASM.REFACTOR — [x] Region-based tile dispatch restored**
  - `x64_tiles.mlua` contains `x64_asm_one_ir` as a switch region.
  - Individual x64 tile families are regions returning canonical `TileResult`.
  - `asm_state.mlua` backward scan uses `emit tiles.x64_asm_one_ir(...)`.
  - Follow-up: move remaining local regmap bookkeeping in `asm_state.mlua` onto
    `emit ra_alloc`/`emit ra_dest` when spill/remat support lands.

Exit criteria for P11:

- [x] A simple trace assembles to executable x64 mcode.
- [x] Guard exits jump to an exit stub.
- [x] Tile dispatch is a switch region (`x64_asm_one_ir`).

---

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

### D006 — Named protocol exit syntax

- Status: accepted and implemented.
- Decision: tagged-union types with named variant fields (`type P = exit(field: T) | ...`)
  serve as protocol types. `region r(...) -> P` lowers to continuation slots.
- Implementation: `lua/moonlift/parse.lua`, `lua/moonlift/mlua_parse.lua`,
  `lua/moonlift/mlua_lex.lua`, `lua/moonlift/schema/type.lua`.
- Tests: `tests/test_protocol_syntax.lua`, `tests/test_parse_type_items.lua`.
- Docs: `PROTOCOL_SYNTAX.md`.
- Rationale: every VM subsystem boundary maps to a named protocol type; the
  `-> ProtocolType` syntax makes the boundary visible and compiler-checked.

### D007 — VM protocol design document as canonical contract

- Status: accepted.
- Decision: `docs/VM_PROTOCOL_DESIGN.md` is the canonical source for all VM
  protocol types. Architecture and implementation plan reference it; neither
  duplicates the type definitions.
- Rationale: single authoritative catalog prevents drift between design docs
  and implementation.

---

## 21. Current Blockers

- [x] **Region composition is now first-class enough to start VM skeleton work.**
  - Implemented RNF in `lua/moonlift/region_normal_form.lua`.
  - `open_expand.lua` now delegates control-region composition to RNF.

- [x] **Named protocol exit syntax is implemented (D006).**
  - `type P = exit(field: T) | ...` and `region r(...) -> P` work end-to-end.
  - Protocol types declared at module scope seed continuation slots for
    following region definitions in the same `.mlua` file.

- [!] Struct literals not implemented.
- [!] Struct field assignment not implemented.

---

## 22. Next Immediate Actions

1. [x] Design Region Normal Form (RNF).
2. [x] Replace ad-hoc region emit expansion with RNF lowering.
3. [x] Add regression tests for region composition shapes.
4. [x] Design and implement named protocol exit syntax (`type P = ...`, `region r() -> P`).
5. [x] Write `docs/VM_PROTOCOL_DESIGN.md` — full VM protocol catalog.
6. [x] Create `mlua/luajitvm/protocols.mlua` — M0 protocol type declarations.
7. [x] Create `mlua/luajitvm/` skeleton (P2.SKEL) — 42 files across core/runtime/gc/jit/asm/ffi/generated.
8. [x] Stub all region signatures using protocol types (P4.PROTO) — vm_loop, table_get/set, gc_alloc/step/barrier, trace_record, ir_emit, snap_add/restore, opt_dce/loop/sink, asm_trace, ra_alloc/dest, x64_asm_one_ir, rec_bc_*, ffi_*, cdata_index.
9. [x] Create `VALUE_LAYOUT.md`, `IR_LAYOUT.md`, `TRACE_LAYOUT.md` drafts.

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
