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
    return Lower.LowerEmitInput(schedule, missing or "missing schedule", unsupported or "unsupported strategy")
end

assert(Lower.LowerStrategyCode("ordinary"):select_lower_emit(input()):lower_emit_is_code())
assert(Lower.LowerStrategyClosedForm(kernel, closed_form):select_lower_emit(input()):lower_emit_is_closed_form())
assert(Lower.LowerStrategyKernel(kernel, scalar_schedule.id):select_lower_emit(input(scalar_schedule)):lower_emit_is_scalar_kernel())
assert(Lower.LowerStrategyKernel(kernel, vector_schedule.id):select_lower_emit(input(vector_schedule)):lower_emit_is_vector_kernel())

local missing = Lower.LowerStrategyKernel(kernel, scalar_schedule.id):select_lower_emit(input(nil, "kernel schedule is absent"))
assert(missing:lower_emit_is_missing_schedule())
assert(missing.reason == "kernel schedule is absent")

local ok = pcall(require, "lalin.lower_strategy_emit_rules")
assert(not ok, "lower_strategy_emit_rules must not exist")

io.write("lalin lower_strategy_emit methods ok\n")
