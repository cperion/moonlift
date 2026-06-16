package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context()
Schema.Define(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Graph = T.MoonGraph
local Flow = T.MoonFlow
local Value = T.MoonValue
local Mem = T.MoonMem
local Effect = T.MoonEffect
local Kernel = T.MoonKernel
local Schedule = T.MoonSchedule
local Lower = T.MoonLower
local Back = T.MoonBack

local origin = Code.CodeOriginGenerated("schema smoke")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local func_id = Code.CodeFuncId("fn:smoke")
local sig_id = Code.CodeSigId("sig:smoke")
local block_id = Code.CodeBlockId("block:entry")
local inst_id = Code.CodeInstId("inst:load")
local ptr = Code.CodeValueId("v:ptr")
local n = Code.CodeValueId("v:n")
local loaded = Code.CodeValueId("v:loaded")
local lease_ty = Code.CodeTyLease(ptr_i32, T.MoonType.TScalar(Core.ScalarI32))
assert(lease_ty.base == ptr_i32, "CodeTyLease should preserve source lease boundary")
local view = Code.CodeValueId("v:view")
local view_make = Code.CodeInstViewMake(view, i32, ptr, n, Code.CodeValueId("v:stride"))
assert(view_make.elem_ty == i32, "CodeInstViewMake stores element type")

local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local load_inst = Code.CodeInst(inst_id, Code.CodeInstLoad(loaded, Code.CodePlaceDeref(ptr, i32, 4), access), origin)
local term = Code.CodeTerm(Code.CodeTermId("term:return"), Code.CodeTermReturn({ loaded }), origin)
local block = Code.CodeBlock(block_id, "entry", {}, { load_inst }, term, origin)
local sig = Code.CodeSig(sig_id, { ptr_i32, i32 }, { i32 })
local func = Code.CodeFunc(func_id, "smoke", Code.CodeLinkageLocal, sig_id, {
    Code.CodeParam(ptr, "ptr", ptr_i32, origin),
    Code.CodeParam(n, "n", i32, origin),
}, {}, block_id, { block }, origin)
local module = Code.CodeModule(Code.CodeModuleId("module:smoke"), { sig }, {}, {}, {}, {}, { func }, origin)
assert(module.funcs[1].id == func_id)

local gb = Graph.GraphBlockId(func_id, block_id)
local gref = Graph.GraphInstRef(func_id, block_id, inst_id)
local gedge = Graph.GraphEdge(gb, gb, "self")
local gdef = Graph.GraphDef(loaded, gref, nil)
local guse = Graph.GraphUse(ptr, gref, nil, "load.place:deref.addr")
local loop_id = Graph.GraphLoopId("loop:smoke")
local gloop = Graph.GraphLoop(loop_id, func_id, gb, { gb }, { gedge }, {})
local graph = Graph.CodeGraph(module.id, { Graph.CodeFuncGraph(func_id, { gedge }, { gdef }, { guse }, { gloop }) })
assert(graph.funcs[1].loops[1].id == loop_id)

local domain = Flow.FlowDomainLoop(loop_id)
local counted = Flow.FlowCountedDomain(Code.CodeValueId("v:i0"), n, Code.CodeValueId("v:step"), true)
local induction = Flow.FlowInduction(Code.CodeValueId("v:i"), i32, counted.start, counted.step, Flow.FlowPrimaryInduction, Flow.FlowRangeDerived(Code.CodeValueId("v:i"), Flow.FlowBoundConst("0"), Flow.FlowBoundValue(n), "smoke"))
local flow_loop = Flow.FlowLoopFacts(loop_id, domain, counted, { gb }, { induction }, {}, {})
local flow_edge = Flow.FlowEdgeFact(gedge, { Flow.FlowEdgeArg(counted.step, induction.value) })
local flow = Flow.FlowFactSet(module.id, { domain }, { flow_edge }, { flow_loop }, { induction.range }, {})
local trip = Flow.FlowTripCountUnknown("no explicit trip count value")
local flow_sem = Flow.FlowSemanticFactSet(module.id, { Flow.FlowLoopNormalizedCounted(loop_id, counted, Flow.FlowLoopIncreasing, trip) })
assert(flow.loops[1].loop == loop_id and flow_sem.facts[1].trip_count == trip)

local proof = Value.AlgebraProofFlow(domain, "flow proof")
local expr_i = Value.ValueExprValue(induction.value)
local affine = Value.ValueExprAffine(Value.AffineExpr("0", { Value.AffineTerm(induction.value, "1") }, i32, nil))
local reduction = Value.ReductionFact(Value.AlgebraFactId("red:sum"), domain, Code.CodeValueId("v:acc"), Value.ReductionAdd, Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0"))), expr_i, i32, nil, nil, proof)
local closed = Value.ClosedFormFact(Value.AlgebraFactId("cf:sum"), reduction, affine, Value.AlgebraProofReduction(reduction, "closed form smoke"))
local values = Value.ValueFactSet(module.id, { Value.ValueExprFact(induction.value, affine, proof), Value.ValueRangeFact(Value.ValueRangeInt(induction.value, Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0"))), Value.ValueExprValue(n), false, proof)) }, { reduction }, { closed })
assert(values.closed_forms[1].reduction == reduction)

local contract = Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(ptr, n), origin)
local mem_proof = Mem.MemProofContract(contract, "bounds")
local object = Mem.MemObjectFact(Mem.MemObjectId("obj:ptr"), func_id, Mem.MemObjectContract, Mem.MemProvContract(contract), i32, Mem.MemExtentElements(n, i32, "bounds"), Mem.MemStrideUnit)
local mem_access = Mem.MemAccessFact(Mem.MemAccessId("access:load"), func_id, gb, inst_id, Mem.MemLoad, Code.CodePlaceDeref(ptr, i32, 4), access, Mem.MemBaseValue(ptr), Mem.MemIndexInduction(induction, 4, 0), Mem.MemAccessContiguous, Mem.MemAlignKnown(4), Mem.MemBoundsAssumed(mem_proof), Mem.MemNonTrapping("bounds"))
local interval = Mem.MemAccessInterval(mem_access.id, object.id, loop_id, mem_access.index, Flow.FlowBoundConst("1"), 4, 0, "one element")
local backend = Mem.MemBackendAccessInfo(mem_access.id, mem_access.trap, mem_access.alignment, mem_access.bounds, 4, true, { mem_proof })
local lease = Mem.MemLeaseGrant(Mem.MemLeaseId("lease:ptr"), domain, ptr, nil, object.id, Mem.MemBaseValue(ptr), object.extent, object.stride, mem_proof)
local relation = Mem.MemObjectsSameLen(object.id, object.id, mem_proof)
local mem = Mem.MemSemanticFactSet(module.id, { object }, { lease }, { mem_access }, { interval }, { Mem.MemAccessInBounds(interval, mem_proof) }, { Mem.MemObjectReadonly(object.id, mem_proof) }, {}, { relation }, { backend }, { mem_proof })
assert(mem.backend_info[1].access == mem_access.id and mem.leases[1].object == object.id)

local call = Effect.CallSummary(func_id, nil, { Effect.EffectRead(Effect.EffectObjectMem(object.id), mem_proof), Effect.EffectNoTrap("smoke") })
local effects = Effect.EffectFactSet(module.id, { call }, { Effect.InstEffect(inst_id, call.effects) }, { Effect.TermEffect(block_id, {}) })
assert(effects.calls[1].effects[1].object.object == object.id)

local stream = Kernel.KernelStream(Kernel.KernelStreamId("stream:ptr"), object.id, { mem_access.id }, mem_access.base, i32, mem_access.pattern, { backend })
local kbody = Kernel.KernelBody(Kernel.KernelDomainFlow(domain, trip, induction.value), { stream }, { Kernel.KernelBinding(Kernel.KernelValueId("kv:i"), i32, Kernel.KernelExprAlgebra(expr_i)) }, { Kernel.KernelEffectFold(reduction), Kernel.KernelEffectCall(call) }, Kernel.KernelResultClosedForm(closed), Kernel.KernelEquivalenceProof({ Kernel.KernelProofFlow(domain, "counted") }))
local kplan = Kernel.KernelPlanned(Kernel.KernelId("kernel:smoke"), Kernel.KernelSubjectLoop(loop_id), kbody)
local kmod = Kernel.KernelModulePlan(module.id, flow, values, mem, effects, { kplan })
assert(kmod.plans[1].body.result.closed_form == closed and kmod.plans[1].body.streams[1].backend_info[1] == backend)
assert(Kernel["Kernel" .. "Schedule" .. "Vector"] == nil and Kernel["KernelFunc" .. "Plan"] == nil, "old Kernel schedule/function-plan shapes must be removed")

local target = Schedule.ScheduleTarget(Back.BackTargetModel(Back.BackTargetNative, {}))
local sched = Schedule.SchedulePlanned(Schedule.ScheduleId("schedule:smoke"), kplan.id, Schedule.ScheduleScalarIndex, { Schedule.ScheduleProofTarget("scalar") }, { Schedule.ScheduleRejectTarget("no vector proof") })
local smod = Schedule.ScheduleModulePlan(module.id, target, { sched })
assert(smod.schedules[1].kernel == kplan.id)

local fragment = Lower.LowerFragment(Lower.LowerFragmentId("frag:loop"), Lower.LowerCoverLoop(loop_id), Lower.LowerStrategyKernel(kplan.id, sched.id), { Lower.LowerProofKernel(kplan.id, "planned"), Lower.LowerProofSchedule(sched.id, "scheduled") }, {})
local fallback = Lower.LowerFragment(Lower.LowerFragmentId("frag:block"), Lower.LowerCoverBlock(func_id, block_id), Lower.LowerStrategyCode("fallback"), { Lower.LowerProofFallback("code") }, { Lower.LowerIssueFallback(Lower.LowerCoverBlock(func_id, block_id), "smoke") })
local lower = Lower.LowerModule(module.id, Lower.LowerTargetBack, kmod, smod, { Lower.LowerFuncPlan(func_id, { fragment, fallback }) }, {})
assert(lower.funcs[1].fragments[1].strategy.kernel == kplan.id)
assert(Lower["LowerFunc" .. "Kernel"] == nil and Lower["LowerFunc" .. "Code"] == nil, "old LowerFunc constructors must be removed")

io.write("moonlift schema_core ok\n")
