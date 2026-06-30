package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.lower_to_back")(T)

local Code = T.LalinCode
local Flow = T.LalinFlow
local Graph = T.LalinGraph
local Kernel = T.LalinKernel
local Lower = T.LalinLower
local Schedule = T.LalinSchedule
local Value = T.LalinValue

local kernel = Kernel.KernelId("kernel:test")
local domain = Flow.FlowDomainLoop(Graph.GraphLoopId("loop:test"))
local zero = Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, T.LalinCore.LitInt("0")))
local reduction = Value.ReductionFact(Value.AlgebraFactId("red:test"), domain, Code.CodeValueId("v:acc"), Value.ReductionAdd, zero, zero, Code.CodeTyIndex, nil, nil, Value.AlgebraProofFlow(domain, "test"))
local closed_form = Value.ClosedFormFact(Value.AlgebraFactId("cf:test"), reduction, zero, Value.AlgebraProofReduction(reduction, "closed form"))
local scalar_schedule = Schedule.SchedulePlanned(Schedule.ScheduleId("schedule:scalar"), kernel, Schedule.ScheduleScalarIndex, {}, {})
local vector_schedule = Schedule.SchedulePlanned(
    Schedule.ScheduleId("schedule:vector"),
    kernel,
    Schedule.ScheduleVector(Schedule.LaneVector(Code.CodeTyIndex, 4), 1, 1, Schedule.TailScalar),
    {},
    {}
)

local function input(schedule, missing, unsupported)
    if unsupported ~= nil then return Lower.LowerEmitUnsupportedCandidate(unsupported) end
    if schedule ~= nil then return Lower.LowerEmitKernelCandidate(schedule) end
    return Lower.LowerEmitMissingScheduleCandidate(missing or "missing schedule")
end

assert(Lower.LowerEmitCodeCandidate:select_lower_emit() == Lower.LowerEmitCode)
assert(Lower.LowerEmitClosedFormCandidate:select_lower_emit() == Lower.LowerEmitClosedForm)
assert(input(scalar_schedule):select_lower_emit() == Lower.LowerEmitScalarKernel)
assert(input(vector_schedule):select_lower_emit() == Lower.LowerEmitVectorKernel)

local missing = input(nil, "kernel schedule is absent"):select_lower_emit()
assert(missing.reason == "kernel schedule is absent")

local ok = pcall(require, "lalin.lower_strategy_emit_rules")
assert(not ok, "lower_strategy_emit_rules must not exist")

io.write("lalin lower_strategy_emit methods ok\n")
