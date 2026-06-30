package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.code_schedule_plan")(T)

local Schedule = T.LalinSchedule

local vector_form = Schedule.ScheduleVector(Schedule.LaneVector(T.LalinCode.CodeTyIndex, 4), 1, 1, Schedule.TailScalar)
local scalar_form = Schedule.ScheduleScalarIndex
local closed_form = Schedule.ScheduleClosedForm
local vector_reject = Schedule.ScheduleRejectTarget("vector-reject")
local scalar_reject = Schedule.ScheduleRejectTarget("scalar-reject")
local closed_reject = Schedule.ScheduleRejectTarget("closed-reject")

local function cap(executable, rejects)
    return Schedule.ScheduleEmitterCapability(
        executable and "ok" or "reject",
        executable,
        executable and "supported" or "rejected",
        rejects or {}
    )
end

do
    local selection = Schedule.SchedulePlanInput(vector_form, cap(true), scalar_form, cap(true)):select_kernel_schedule()
    assert(selection.form == vector_form, "vector schedule must win")
    assert(#selection.rejected_alternatives == 0, "winning vector schedule has no rejected alternatives")
end

do
    local selection = Schedule.SchedulePlanInput(vector_form, cap(false, { vector_reject }), scalar_form, cap(true)):select_kernel_schedule()
    assert(selection.form == scalar_form, "scalar schedule must be selected after vector rejection")
    assert(selection.rejected_alternatives[1] == vector_reject, "vector rejects must be retained as alternatives")
end

do
    local selection = Schedule.SchedulePlanInput(nil, nil, closed_form, cap(true)):select_kernel_schedule()
    assert(selection.form == closed_form, "closed-form schedule form must be preserved")
    assert(#selection.rejected_alternatives == 0, "non-vector plan has no vector alternatives")
end

do
    local selection = Schedule.SchedulePlanInput(vector_form, cap(false, { vector_reject }), scalar_form, cap(false, { scalar_reject })):select_kernel_schedule()
    assert(selection.rejects[1] == scalar_reject, "no-plan rejects must come from executable fallback")
end

do
    local selection = Schedule.SchedulePlanInput(nil, nil, closed_form, cap(false, { closed_reject })):select_kernel_schedule()
    assert(selection.rejects[1] == closed_reject, "scalar rejects must be preserved")
end

local ok = pcall(require, "lalin.code_schedule_plan_rules")
assert(not ok, "code_schedule_plan_rules must not exist")

io.write("lalin code_schedule_plan methods ok\n")
