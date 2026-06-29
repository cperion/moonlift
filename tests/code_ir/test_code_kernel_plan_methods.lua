package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.code_kernel_plan")(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Kernel = T.LalinKernel
local Value = T.LalinValue

local subject = Kernel.KernelSubjectLoop(T.LalinGraph.GraphLoopId("loop:test"))
local domain = Flow.FlowDomainLoop(T.LalinGraph.GraphLoopId("loop:test"))
local reject_not_counted = Kernel.KernelRejectNoFacts(subject, "not-counted")
local reject_no_owner = Kernel.KernelRejectNoFacts(subject, "no-owner")
local reject_memory = Kernel.KernelRejectNoFacts(subject, "memory-reject")
local reject_effect = Kernel.KernelRejectNoFacts(subject, "effect-reject")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local acc = Code.CodeValueId("v:acc")
local zero = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
local proof = Value.AlgebraProofFlow(domain, "test proof")
local reduction = Value.ReductionFact(Value.AlgebraFactId("red:test"), domain, acc, Value.ReductionAdd, zero, zero, i32, nil, nil, proof)
local closed_form = Value.ClosedFormFact(Value.AlgebraFactId("cf:test"), reduction, zero, Value.AlgebraProofReduction(reduction, "closed form"))

local function input(spec)
    return Kernel.KernelLoopPlanInput(
        spec.counted ~= false,
        spec.has_func_id ~= false,
        spec.has_func ~= false,
        spec.rejects or {},
        { reject_not_counted },
        { reject_no_owner },
        spec.closed_form,
        spec.reduction,
        spec.skeleton_result,
        spec.trip_count or Flow.FlowTripCountNonNegative(Code.CodeValueId("trip:test"), nil)
    )
end

do
    local selection = input { counted = false, has_func_id = false }:select_kernel_loop_plan()
    assert(selection:kernel_plan_is_no_plan(), "uncounted loop must reject")
    assert(selection.rejects[1] == reject_not_counted, "uncounted loop must use counted-domain reject")
end

do
    local selection = input { has_func_id = false }:select_kernel_loop_plan()
    assert(selection:kernel_plan_is_no_plan(), "ownerless loop must reject")
    assert(selection.rejects[1] == reject_no_owner, "ownerless loop must use graph-owner reject")
end

do
    local selection = input { rejects = { reject_memory, reject_effect } }:select_kernel_loop_plan()
    assert(selection:kernel_plan_is_no_plan(), "loop rejects must prevent planning")
    assert(#selection.rejects == 2 and selection.rejects[2] == reject_effect, "semantic rejects must be preserved")
end

do
    local selection = input {
        closed_form = closed_form,
        reduction = reduction,
        trip_count = Flow.FlowTripCountUnknown("test unknown"),
    }:select_kernel_loop_plan()
    assert(selection:kernel_plan_is_closed_form(), "closed form must win over reduction")
    assert(selection.closed_form == closed_form, "closed-form fact must be returned")
    assert(selection.add_trip_unknown_proof == true, "trip-count proof bit must be carried")
end

do
    local selection = input { reduction = reduction }:select_kernel_loop_plan()
    assert(selection:kernel_plan_is_reduction(), "reduction result must be selected")
    assert(selection.reduction == reduction, "reduction fact must be returned")
end

do
    local skeleton = Kernel.KernelResultVoid
    local selection = input { skeleton_result = skeleton }:select_kernel_loop_plan()
    assert(selection:kernel_plan_is_skeleton(), "skeleton result must be selected")
    assert(selection.result == skeleton, "skeleton result must be returned")
end

do
    local selection = input {}:select_kernel_loop_plan()
    assert(selection:kernel_plan_is_original_control(), "original-control result must be the semantic default")
end

local ok = pcall(require, "lalin.code_kernel_plan_rules")
assert(not ok, "code_kernel_plan_rules must not exist")

io.write("lalin code_kernel_plan methods ok\n")
