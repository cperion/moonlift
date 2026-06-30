package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.code_lower_plan")(T)

local Code = T.LalinCode
local Flow = T.LalinFlow
local Graph = T.LalinGraph
local Kernel = T.LalinKernel
local Lower = T.LalinLower
local Schedule = T.LalinSchedule
local Value = T.LalinValue

local kernel_id = Kernel.KernelId("kernel:test")
local schedule_id = Schedule.ScheduleId("schedule:test")
local subject = Kernel.KernelSubjectLoop(Graph.GraphLoopId("loop:test"))
local domain = Flow.FlowDomainLoop(Graph.GraphLoopId("loop:test"))
local proof = Kernel.KernelEquivalenceProof({})
local body = Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, Flow.FlowTripCountUnknown("test"), nil),
    {},
    {},
    {},
    Kernel.KernelResultOriginalControl("test"),
    proof
)
local kplan = Kernel.KernelPlanned(kernel_id, subject, body)
local no_plan = Kernel.KernelNoPlan(subject, { Kernel.KernelRejectNoFacts(subject, "kernel rejected") })
local sched = Schedule.SchedulePlanned(schedule_id, kernel_id, Schedule.ScheduleScalarIndex, {}, {})

local cf_reduction = Value.ReductionFact(
    Value.AlgebraFactId("red:test"),
    domain,
    Code.CodeValueId("v:acc"),
    Value.ReductionAdd,
    Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, T.LalinCore.LitInt("0"))),
    Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, T.LalinCore.LitInt("1"))),
    Code.CodeTyIndex,
    nil,
    nil,
    Value.AlgebraProofFlow(domain, "test")
)
local cf = Value.ClosedFormFact(
    Value.AlgebraFactId("cf:test"),
    cf_reduction,
    Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, T.LalinCore.LitInt("42"))),
    Value.AlgebraProofReduction(cf_reduction, "closed form")
)
local cf_body = Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, Flow.FlowTripCountUnknown("test"), nil),
    {},
    {},
    {},
    Kernel.KernelResultClosedForm(cf),
    proof
)
local cf_plan = Kernel.KernelPlanned(kernel_id, subject, cf_body)
local cf_sched = Schedule.SchedulePlanned(schedule_id, kernel_id, Schedule.ScheduleClosedForm, {}, {})

local function input(fields)
    if fields.closed_form ~= nil then return Lower.LowerFragmentClosedFormCandidate(fields.closed_form) end
    if fields.closed_form_missing_reason ~= nil then return Lower.LowerFragmentClosedFormMissing(fields.closed_form_missing_reason) end
    if fields.kernel ~= nil and fields.schedule ~= nil then return Lower.LowerFragmentKernelCandidate(fields.kernel, fields.schedule) end
    if fields.kernel ~= nil then return Lower.LowerFragmentNoSchedule(fields.no_schedule_reason or "missing schedule") end
    if fields.kernel_no_plan ~= nil then return Lower.LowerFragmentKernelRejected(fields.kernel_no_plan_reason or "kernel rejected") end
    return Lower.LowerFragmentNoCandidate
end

do
    local selection = input { kernel = cf_plan, schedule = cf_sched, closed_form = cf }:select_lower_fragment()
    assert(selection.closed_form == cf)
end

do
    local selection = input {
        kernel = kplan,
        schedule = cf_sched,
        closed_form_missing_reason = "closed-form schedule lacks fact",
    }:select_lower_fragment()
    assert(selection.reason == "closed-form schedule lacks fact")
end

do
    local selection = input { kernel = kplan, schedule = sched }:select_lower_fragment()
    assert(selection == Lower.LowerSelectKernel)
end

do
    local selection = input { kernel = kplan, no_schedule_reason = "no schedule selected" }:select_lower_fragment()
    assert(selection.reason == "no schedule selected")
end

do
    local selection = input { kernel_no_plan = no_plan, kernel_no_plan_reason = "kernel plan rejected" }:select_lower_fragment()
    assert(selection.reason == "kernel plan rejected")
end

do
    local selection = input {}:select_lower_fragment()
    assert(selection == Lower.LowerSelectNone)
end

local ok = pcall(require, "lalin.code_lower_plan_rules")
assert(not ok, "code_lower_plan_rules must not exist")

io.write("lalin code_lower_plan methods ok\n")
