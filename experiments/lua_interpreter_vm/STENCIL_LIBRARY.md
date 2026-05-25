# Moonlift Lua VM — Curated Stencil Library Design

The JIT has one backend: **copy-and-patch stencil materialization**.

Therefore the stencil library is not an optimization accessory. It is the backend vocabulary: the
set of native code phrases that a `StencilPlan` is allowed to say.

```text
VirtualState + bytecode/effects/profile
  -> StencilPlan
  -> copy / stamp / payload / fixup / publish / link
```

This document designs the first real stencil library from the current simplified JIT design and the
AWFY/PUC Lua mining evidence.

---

# 1. Design rule

A stencil is a physical implementation of a semantic contract.

```text
CodeStencil = bytes + holes + relocs + payloads + ABI + clobbers + semantic contract
```

A stencil is not valid because it is fast. It is valid because it implements either:

```text
one interpreter-derived StateOp/opcode contract
```

or:

```text
a proven-equivalent sequence of interpreter-derived contracts
```

This is what makes supernodes safe.

---

# 2. Evidence from AWFY Lua

The current PUC Lua profiler records:

```text
opcode histograms
opcode pair/triple histograms
bounded (proto, pc, opcode) traces
PC-space repeat-period spectrum
opcode autocorrelation spectrum
canonical loop motifs
```

Run:

```sh
luajit experiments/lua_interpreter_vm/tools/profile_awfy_puc.lua [awfy_dir] [quick|full]
```

Main dynamic signal from AWFY Lua:

```text
GETFIELD
TEST
MOVE
CALL
SETFIELD
SELF
ADDI
GETUPVAL
RETURN1
ADD
JMP
SETTABLE
GETTABLE
FORLOOP
MUL
```

Important mined motifs:

```text
ADD JMP LE ADDI SETTABLE
GETFIELD GETFIELD JMP TEST TEST
ADDI GETTABLE TEST FORLOOP
FORLOOP SETTABLE
SELF MOVE CALL
MOVE MOVE CALL
CALL GETFIELD GETTABLE TEST RETURN1 TEST FORLOOP SELF MOVE MOVE
GETFIELD GETFIELD ADD SETFIELD
GETFIELD GETFIELD MUL MUL ADD
```

Conclusion:

> The first useful library must be table/object/call/branch/loop shaped. Arithmetic-only stencils
> are not enough.

---

# 3. Library rings

The library is organized in four rings.

```text
Ring 0  execution skeleton: entry, exit, projection, boundary, edge
Ring 1  generic opcode roots: baseline coverage
Ring 2  fact-specialized variants: inline caches, typed arithmetic, fast loops
Ring 3  supernodes: mined recurring physical patterns
```

Ring 0 and enough of Ring 1 are required for the first baseline compiler. Rings 2 and 3 grow from
profile evidence.

---

# 4. Stencil snippet ABI v1

The library needs a concrete snippet ABI before candidate functions can become real fixtures.
Normal function-body assembly is evidence only; production stencils use this ABI.

## 4.1 Pinned registers, x86-64 SysV v1

```text
r12  L: ptr(LuaThread)
r13  frame: ptr(Frame)
r14  base: ptr(Value)        -- L.stack + frame.base
r15  constants: ptr(Value)   -- current Proto.constants
rbx  unit/context pointer    -- ExecutableUnit or per-unit side table
```

These are callee-saved under SysV, which helps boundary calls preserve VM state.

Caller-scratch inside stencils:

```text
rax rcx rdx rsi rdi r8 r9 r10 r11
xmm0-xmm7
```

Boundary stencils are responsible for ABI shuffling before C/Moonlift helper calls.

## 4.2 Value layout

```text
Value size = 16 bytes
Value.tag  @ +0 : u32
Value.aux  @ +4 : u32
Value.bits @ +8 : u64
```

Stack slot address:

```text
slot_addr(s) = r14 + s * 16
```

Most holes are therefore 32-bit displacements:

```text
slot.tag displacement
slot.aux displacement
slot.bits displacement
```

## 4.3 Location classes

```text
SLOT          Value in VM stack slot
CONST_SLOT    Value in Proto.constants
IMM_I64       stamped integer immediate
IMM_F64_BITS  stamped float bits
BITS_REG      unboxed bits register with proven tag fact
TAG_BITS_REG  tag register + bits register
VALUE_REGS    tag + aux + bits registers
ROOT_SLOT     JitRootArea slot
IC_PTR        inline-cache side record
EDGE_PTR      EdgeCell pointer
```

The v1 selector should mostly use `SLOT`, `CONST_SLOT`, `IMM_*`, and `BITS_REG` for proven
numeric values. Full `VALUE_REGS` is useful for projection and unknown values but more expensive.

## 4.4 Continuation forms

```text
fall            next stencil falls through
branch          local label fixup
side_exit       projection + exit path
edge            jump through EdgeCell
boundary        runtime/helper boundary
return_outcome  write JitOutcome and return to vm_loop
```

## 4.5 Hole kinds

```text
slot_disp_tag
slot_disp_aux
slot_disp_bits
const_disp_tag
const_disp_aux
const_disp_bits
imm_i32
imm_i64
imm_f64_bits
tag_imm32
edge_ptr
ic_ptr
helper_ptr
projection_id
boundary_id
literal_pool_off
```

## 4.6 Relocation kinds

```text
fallthrough_label
branch_label
side_exit_label
boundary_label
helper_call
edge_target_load
literal_pool_ref
```

## 4.7 Clobbers

Every stencil declares:

```text
gpr_clobber_mask
xmm_clobber_mask
preserves_pinned_state: bool
requires_stack_alignment: bool
may_call: bool
```

A stencil that may call is a boundary stencil or composes with a boundary stencil.

---

# 5. Ring 0 — execution skeleton stencils

These make compiled code executable and recoverable.

## 5.1 Entry

```text
entry.vm_state_to_unit
```

Contract:

```text
Inputs:  L, frame, pc/base/top from interpreter gate
Outputs: pinned r12/r13/r14/r15/rbx initialized
Effect:  PURE
```

Holes/payloads:

```text
unit pointer
constants pointer or load path
entry pc metadata
```

## 5.2 Exit and outcome

```text
exit.to_interpreter_next
exit.to_interpreter_jump
exit.to_interpreter_error
exit.to_interpreter_oom
outcome.write_status
outcome.write_pc_base_top
```

Contract:

```text
Materialize required interpreter-visible state and return JitOutcome-compatible status.
```

## 5.3 Edges

```text
edge.jump_indirect
edge.resolve_miss
edge.return_to_resolver
edge.fallthrough_to_label
```

Baseline edge transfer:

```asm
jmp qword ptr [edge.target]
```

Post-publication mutation is data mutation:

```text
EdgeCell.target = new_target
```

## 5.4 Projection stencils

```text
project.slot.value_regs_to_slot
project.slot.bits_int_to_slot
project.slot.bits_num_to_slot
project.slot.const_to_slot
project.live_slots.bundle
project.root.value_to_root
project.frame.pc_top
project.thread.top
project.resume.normal
project.resume.metamethod_binary
project.error.value
project.reload_pinned_state
```

These are selected by effects:

```text
MAY_GC       -> roots
MAY_CALL_LUA -> roots + resume
MAY_THROW    -> error
side exit    -> target/interpreter projection
```

## 5.5 Boundary stencils

```text
boundary.call_helper
boundary.call_allocator
boundary.call_gc_safepoint
boundary.enter_lua_child
boundary.enter_native
boundary.call_metamethod
boundary.return_to_vm_loop
```

Contract:

```text
Projection requirements must already be satisfied or composed immediately before boundary entry.
```

---

# 6. Ring 1 — generic opcode roots

Ring 1 gives baseline coverage. These stencils are dispatch-erased opcode handlers with holes for
operands and continuations.

Unsupported opcodes terminate the compiled range.

## 6.1 Value and constant movement

```text
value.move.sB_to_sA.fall
value.load_i64.imm_to_sA.fall
value.load_f64_bits.imm_to_sA.fall
value.load_k.kB_to_sA.fall
value.load_bool.tag_to_sA.fall
value.load_nil.sA_count.fall
value.getupval.generic.sU_to_sA.fall
value.setupval.generic.sA_to_sU.boundary_or_fall
```

Why first:

```text
MOVE and constants are high-frequency glue.
Projection and supernodes reuse the same write/copy machinery.
```

## 6.2 Arithmetic roots

```text
arith.add.generic.sB_sC_to_sA.next_or_mm
arith.sub.generic.sB_sC_to_sA.next_or_mm
arith.mul.generic.sB_sC_to_sA.next_or_mm
arith.div.generic.sB_sC_to_sA.next_or_mm
arith.addi.generic.sB_imm_to_sA.next_or_mm
arith.addk.generic.sB_kC_to_sA.next_or_mm
arith.bit.generic.sB_sC_to_sA.next_or_error
arith.shift.generic.sB_sC_to_sA.next_or_error
```

Generic roots preserve interpreter semantics and may branch to metamethod/error continuations.
Specialized variants below make hot paths fast.

## 6.3 Branch and compare roots

```text
branch.jmp.target
branch.test.sA.true_or_false
branch.testset.sB_to_sA.true_or_false
cmp.eq.generic.sA_sB.true_or_false_or_mm
cmp.lt.generic.sA_sB.true_or_false_or_mm
cmp.le.generic.sA_sB.true_or_false_or_mm
cmp.eqi.generic.sA_imm.true_or_false
cmp.lti.generic.sA_imm.true_or_false
cmp.lei.generic.sA_imm.true_or_false
```

Why first:

```text
TEST/JMP/compare dominate AWFY control flow.
Fallthrough layout quality matters here.
```

## 6.4 Loop roots

```text
loop.forprep.generic.sA_Bx.next_or_skip
loop.forloop.generic.sA_Bx.loop_or_exit
```

The generic form handles integer/float loop semantics and slow conversion/error cases.

## 6.5 Table roots

```text
table.new.generic.sA_size.next_or_oom
table.gettable.generic.sT_sK_to_sA.next_or_slow
table.geti.generic.sT_imm_to_sA.next_or_slow
table.getfield.generic.sT_kName_to_sA.next_or_slow
table.settable.generic.sT_sK_sV.next_or_slow_or_barrier
table.seti.generic.sT_imm_sV.next_or_slow_or_barrier
table.setfield.generic.sT_kName_sV.next_or_slow_or_barrier
table.self.generic.sObj_kName_to_sA_sA1.next_or_slow
```

Why first:

```text
GETFIELD/SETFIELD/GETTABLE/SETTABLE/SELF dominate AWFY.
```

## 6.6 Call and return roots

```text
call.generic.sF_args.boundary
call.tail_generic.sF_args.boundary
call.self_generic.sObj_kName_args.boundary
return.generic.sA_count
return.zero
return.one.sA
```

`CALL` is a boundary-heavy opcode. Generic call stencils are mostly projection + boundary setup.
Specialized call variants are required for performance.

---

# 7. Ring 2 — fact-specialized variants

Ring 2 is selected from `VirtualState` facts, inline-cache records, and profile data.

## 7.1 Numeric arithmetic variants

```text
arith.add_i64.known.sB_sC_to_sA.fall
arith.sub_i64.known.sB_sC_to_sA.fall
arith.mul_i64.known.sB_sC_to_sA.fall
arith.add_i64_guarded.sB_sC_to_sA.next_or_exit
arith.sub_i64_guarded.sB_sC_to_sA.next_or_exit
arith.mul_i64_guarded.sB_sC_to_sA.next_or_exit
arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit
arith.addi_i64.known_bitsreg_imm.to_bitsreg.fall
arith.add_f64_guarded.sB_sC_to_sA.next_or_exit
arith.mul_f64_guarded.sB_sC_to_sA.next_or_exit
```

Notes:

```text
integer add/sub/mul wrap
no overflow side exit
float variants use f64 bits
side exits project target/interpreter state
```

## 7.2 Compare/test variants

```text
branch.truthy.sA.true_or_false
branch.falsey.sA.true_or_false
cmp.eq_i64_guarded.sA_sB.true_or_false_or_exit
cmp.lt_i64_guarded.sA_sB.true_or_false_or_exit
cmp.le_i64_guarded.sA_sB.true_or_false_or_exit
cmp.eqi_i64_guarded.sA_imm.true_or_false_or_exit
cmp.lti_i64_guarded.sA_imm.true_or_false_or_exit
```

## 7.3 Fast loop variants

```text
loop.forprep_i64.sA_Bx.next_or_skip_or_exit
loop.forloop_i64.sA_Bx.loop_or_exit
loop.forloop_i64_counter_reg.loop_or_exit
```

These are high priority because AWFY has strong `FORLOOP` and loop-period signals.

## 7.4 Table inline-cache variants

### Field get/set

```text
table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow
table.setfield_shape_ic1.sT_kName_sV.next_or_slow_or_barrier
table.getfield_nometa_ic1.sT_kName_to_sA.next_or_slow
table.setfield_nometa_ic1.sT_kName_sV.next_or_slow_or_barrier
```

Contract:

```text
guard table tag
guard table shape/epoch or array/hash layout fact
guard absent metamethod when required
perform direct slot/node access
record dependency on shape/metatable epoch
```

### Array/index get/set

```text
table.geti_array_i64_ic1.sT_imm_to_sA.next_or_slow
table.gettable_array_i64_ic1.sT_sK_to_sA.next_or_slow
table.seti_array_i64_ic1.sT_imm_sV.next_or_slow_or_barrier
table.settable_array_i64_ic1.sT_sK_sV.next_or_slow_or_barrier
```

These support Sieve/List/array-heavy motifs.

## 7.5 SELF and method-call variants

```text
table.self_field_ic1.sObj_kName_to_sFunc_sSelf.next_or_slow
call.known_lclosure.sF_args.enter_lua
call.known_cclosure.sF_args.enter_native
call.known_native_fast.sF_args.return_or_yield_or_error
```

AWFY has very strong `SELF MOVE CALL` and `MOVE MOVE CALL` motifs. Method-call stencils are
therefore first-class, not an afterthought.

## 7.6 Return variants

```text
return.one.sA_to_parent.fall_or_exit
return.zero.to_parent.fall_or_exit
return.tail_known_lclosure
```

Return appears frequently in AWFY traces and composes with benchmark inner loops.

---

# 8. Ring 3 — curated supernodes

Supernodes are promoted only when motif evidence and codegen evidence agree.

The following are the first curated candidates.

## 8.1 Method call supernodes

```text
super.method_self_move_call.ic1
    SELF sObj kName -> sFunc,sSelf
    MOVE/COPY args
    CALL known/IC target
```

Evidence:

```text
SELF MOVE CALL
SELF MOVE MOVE CALL
MOVE MOVE CALL
CALL GETFIELD ...
```

Why:

```text
method dispatch is AWFY's object model hot path
combines field IC + receiver copy + call boundary setup
```

## 8.2 Field chain + branch

```text
super.field_field_test_branch.ic1
    GETFIELD sObj k1 -> t
    GETFIELD t k2 -> v
    TEST/JMP v
```

Evidence:

```text
GETFIELD GETFIELD JMP TEST TEST
TEST GETFIELD GETFIELD JMP
GETFIELD GETFIELD LT/LTI
```

Why:

```text
object state checks dominate Richards/Havlak/Json-style code
```

## 8.3 Field update

```text
super.field_field_add_setfield.ic1
    GETFIELD obj k1
    GETFIELD obj k2
    ADD/MUL/SUB
    SETFIELD obj k3
```

Evidence:

```text
GETFIELD GETFIELD ADD SETFIELD
GETFIELD GETFIELD MUL MUL ADD
GETFIELD ADD SETFIELD
```

Why:

```text
object numeric state update, especially NBody/Richards-like code
```

## 8.4 Array loop body

```text
super.array_get_test_forloop.ic1
    ADDI index
    GETTABLE/GETI array index
    TEST
    FORLOOP
```

Evidence:

```text
ADDI GETTABLE TEST FORLOOP
GETTABLE TEST FORLOOP ADDI
```

Why:

```text
array traversal with truthiness checks
```

## 8.5 Array set loop body

```text
super.array_set_forloop.ic1
    SETTABLE/SETI
    FORLOOP
```

Evidence:

```text
FORLOOP SETTABLE
SETTABLE FORLOOP
```

Why:

```text
Sieve/storage/list-style loops
```

## 8.6 While-style table update loop

```text
super.while_table_update_i64.ic1
    LE/LT guard
    ADDI induction
    SETTABLE/SETI
    ADD/JMP backedge
```

Evidence:

```text
ADD JMP LE ADDI SETTABLE
LE ADDI SETTABLE ADD JMP
```

Why:

```text
captures while-loop mutation patterns not represented as FORLOOP
```

## 8.7 Constructor/object initialization bundle

```text
super.newtable_setfield_bundle.small
    NEWTABLE
    repeated SETFIELD
```

Evidence:

```text
NEWTABLE GETUPVAL SETFIELD
SETFIELD SETFIELD SETFIELD
```

Why:

```text
AWFY object construction and module setup generate many field stores
```

## 8.8 Numeric loop arithmetic bundle

```text
super.i64_loop_add_mul_accum
    load fields/slots
    MUL/MUL/ADD or ADD/MUL
    store result
    FORLOOP/JMP
```

Evidence:

```text
MUL MUL ADD
GETFIELD GETFIELD MUL MUL ADD
ADD SETFIELD ... FORLOOP
```

Why:

```text
NBody/Mandelbrot numeric kernels need larger arithmetic phrases than opcode pairs
```

---

# 9. Baseline MVP stencil set

The smallest useful baseline library is not the full curated set. It is:

## Required Ring 0

```text
entry.vm_state_to_unit
exit.to_interpreter_next
exit.to_interpreter_jump
outcome.write_status
edge.jump_indirect
edge.resolve_miss
project.slot.bits_int_to_slot
project.slot.value_regs_to_slot
project.live_slots.bundle
project.frame.pc_top
project.thread.top
boundary.call_helper
boundary.return_to_vm_loop
```

## Required Ring 1

```text
value.move.sB_to_sA.fall
value.load_i64.imm_to_sA.fall
value.load_k.kB_to_sA.fall
value.load_bool.tag_to_sA.fall
value.load_nil.sA_count.fall
arith.add.generic.sB_sC_to_sA.next_or_mm
arith.addi.generic.sB_imm_to_sA.next_or_mm
branch.jmp.target
branch.test.sA.true_or_false
cmp.lt.generic.sA_sB.true_or_false_or_mm
cmp.eq.generic.sA_sB.true_or_false_or_mm
loop.forprep.generic.sA_Bx.next_or_skip
loop.forloop.generic.sA_Bx.loop_or_exit
return.one.sA
return.zero
```

## First Ring 2 additions

```text
arith.add_i64_guarded.sB_sC_to_sA.next_or_exit
arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit
branch.truthy.sA.true_or_false
loop.forloop_i64.sA_Bx.loop_or_exit
```

This MVP can compile numeric/control-heavy bytecode ranges while safely exiting around tables/calls.

---

# 10. AWFY-priority stencil set

To become useful on AWFY-like Lua, add these next:

```text
table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow
table.setfield_shape_ic1.sT_kName_sV.next_or_slow_or_barrier
table.gettable_array_i64_ic1.sT_sK_to_sA.next_or_slow
table.settable_array_i64_ic1.sT_sK_sV.next_or_slow_or_barrier
table.self_field_ic1.sObj_kName_to_sFunc_sSelf.next_or_slow
call.known_lclosure.sF_args.enter_lua
call.known_cclosure.sF_args.enter_native
super.method_self_move_call.ic1
super.field_field_test_branch.ic1
super.field_field_add_setfield.ic1
super.array_get_test_forloop.ic1
super.array_set_forloop.ic1
```

This set follows the dynamic evidence directly.

---

# 11. Promotion checklist

A candidate becomes a `CodeStencil` only if it has:

```text
stable design name
semantic contract
expanded StateOp/opcode contract
input StateShape
output StateShape
Effect
BoundaryRequirement
ProjectionRequirement
DependencyRequirement
StencilConfig axes
body byte range
holes
relocs
payloads
ABI metadata
clobber metadata
materialization test
execution test against interpreter behavior
negative/dependency invalidation test when speculative
profile evidence or explicit MVP requirement
```

A supernode additionally needs:

```text
expanded equivalent sequence
proof/test that outputs/effects/projections/dependencies match expansion
measurement that it reduces hot bytes, branches, or materialization cost
```

---

# 12. Executable v0 library surface

The first semantic library surface lives at:

```text
experiments/lua_interpreter_vm/src/jit/stencil_library.lua
```

It contains two things:

```text
1. the curated CodeStencilSpec catalog from this document
2. plain-Lua semantic executors for the first promoted baseline stencils
```

The first physical fixture/materializer surface lives at:

```text
experiments/lua_interpreter_vm/src/jit/stencil_fixtures.lua
```

It contains executable x86-64 `StencilFixture` seed bytes for the promoted straight-line subset and
a copy/stamp/fixup materializer. A fixture is promoted only when it can be executed and checked
against the interpreter/semantic contract. Non-executable byte-shaped fixtures stay in miner evidence,
not in the library.

The semantic executor is not the hot path. It is the promotion oracle: every native fixture must
match these contracts before it can become a real copy-and-patch `CodeStencil`.

Current correctness tests:

```sh
luajit experiments/lua_interpreter_vm/tests/test_jit_stencil_library.lua
luajit experiments/lua_interpreter_vm/tests/test_jit_native_stencils.lua
luajit experiments/lua_interpreter_vm/tests/test_jit_native_blocks.lua
luajit experiments/lua_interpreter_vm/tests/test_jit_native_outcomes.lua
luajit experiments/lua_interpreter_vm/tests/test_jit_baseline_planner.lua
luajit experiments/lua_interpreter_vm/tests/test_jit_coverage.lua
```

Current microbench harnesses:

```sh
luajit experiments/lua_interpreter_vm/benchmarks/bench_jit_stencils.lua [iters]
luajit experiments/lua_interpreter_vm/benchmarks/bench_jit_native_stencils.lua [iters]
luajit experiments/lua_interpreter_vm/benchmarks/bench_jit_native_blocks.lua [iters]
luajit experiments/lua_interpreter_vm/benchmarks/bench_jit_native_outcomes.lua [iters]
luajit experiments/lua_interpreter_vm/benchmarks/bench_jit_baseline_planner.lua [iters]
luajit experiments/lua_interpreter_vm/benchmarks/bench_jit_object_baseline.lua [iters]
luajit experiments/lua_interpreter_vm/tools/report_jit_coverage.lua [profile_dir]
```

The semantic stencil benchmark compares the semantic executor against a small decoded/switch
reference interpreter for the same opcode shape. The native stencil benchmark executes one
materialized stencil through a tiny LuaJIT FFI wrapper. The native block benchmark concatenates
multiple copied/stamped stencils into one executable unit and pays one FFI call for the whole block.
The native outcome benchmark uses the two-argument wrapper `(Value* base, NativeJitOutcome* out)`
and measures observable OK/side-exit/branch paths. The baseline planner benchmark compiles a small
bytecode word range into block nodes automatically, then executes the resulting native unit. The
coverage report compares current and proposed planner/stencil sets against the AWFY dynamic opcode
profile, because speed only matters in proportion to time spent on the fast path.

Current executable baseline planner coverage includes:

```text
ADD
ADDI
CALL
GETFIELD
GETTABLE
GETUPVAL
JMP
LFALSESKIP
LOADFALSE
LOADI
LOADK
LOADNIL
LOADTRUE
MOVE
RETURN0
RETURN1
SELF
SETFIELD
SETTABLE
TEST
```

On the latest AWFY/PUC profile this covers **82.04%** of dynamic opcodes and **65.93%** of dynamic
opcode pairs. The next coverage step is GETTABUP, comparisons, loops, TAILCALL/RETURN, and NEWTABLE.

---

# 13. Miner workflow

## 13.1 Dynamic profile miner

```sh
luajit experiments/lua_interpreter_vm/tools/profile_awfy_puc.lua [awfy_dir] [quick|full]
```

Outputs:

```text
aggregate_opcode_hist.tsv
aggregate_pairs.tsv
aggregate_triples.tsv
aggregate_period_spectrum.tsv
aggregate_opcode_autocorr.tsv
aggregate_motifs.tsv
PROFILE_REPORT.md
```

Use this to choose families and supernodes.

## 13.2 Candidate byte miner

```sh
luajit experiments/lua_interpreter_vm/tools/mine_stencils.lua
```

Outputs:

```text
candidates.mlua
candidates.o
candidates.asm
candidate_manifest.json
candidate_report.md
```

Use this to learn byte shapes, hole positions, relocations, and Cranelift codegen behavior.

## 13.3 Promotion path

```text
profile evidence
  -> StatePattern candidate
  -> Moonlift candidate kernel / partial-evaluated interpreter region
  -> object bytes + asm
  -> StencilFixture
  -> tests
  -> CodeStencil
```

The output of mining is evidence. The output of promotion is library.

---

# 14. Open design tasks

Before production extraction:

```text
1. Implement snippet ABI generation without normal function prologue/epilogue noise.
2. Extract real object sections/relocations instead of relying on objdump text.
3. Add clobber inference or explicit clobber declarations.
4. Map PUC opcode profile motifs to Moonlift VM opcode/StateOp patterns.
5. Add table-shape and inline-cache products before table IC stencils.
6. Add projection-bundle generation from liveness.
7. Measure materialization latency separately from generated-code speed.
```

---

# 15. Final curated direction

The library should be built in this order:

```text
1. Ring 0 execution skeleton and projection stencils
2. Ring 1 value/load/branch/return/loop/arithmetic roots
3. Ring 2 integer arithmetic + truthy branch + i64 FORLOOP variants
4. Ring 2 GETFIELD/SETFIELD/GETTABLE/SETTABLE inline-cache variants
5. Ring 2 SELF/CALL known-target variants
6. Ring 3 method-call, field-chain, field-update, and array-loop supernodes
```

This ordering gives a working baseline compiler first, then follows the strongest AWFY evidence.
