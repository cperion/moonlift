package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local T = pvm.context()
require("moonlift.schema").Define(T)

local Parse = require("moonlift.parse").Define(T)
local OpenFacts = require("moonlift.open_facts").Define(T)
local OpenValidate = require("moonlift.open_validate").Define(T)
local OpenExpand = require("moonlift.open_expand").Define(T)
local ClosureConvert = require("moonlift.closure_convert").Define(T)
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToCode = require("moonlift.tree_to_code").Define(T)
local CodeValidate = require("moonlift.code_validate").Define(T)
local CodeGraph = require("moonlift.code_graph").Define(T)
local CodeFlowFacts = require("moonlift.code_flow_facts").Define(T)
local CodeValueFacts = require("moonlift.code_value_facts").Define(T)
local CodeMemFacts = require("moonlift.code_mem_facts").Define(T)
local CodeEffectFacts = require("moonlift.code_effect_facts").Define(T)
local CodeKernelPlan = require("moonlift.code_kernel_plan").Define(T)
local CodeSchedulePlan = require("moonlift.code_schedule_plan").Define(T)
local CodeLowerPlan = require("moonlift.code_lower_plan").Define(T)
local KernelValidate = require("moonlift.kernel_validate").Define(T)

local Kernel = T.MoonKernel
local Schedule = T.MoonSchedule
local Lower = T.MoonLower

local function assert_no(label, issues)
    assert(#issues == 0, label .. " issues " .. tostring(#issues) .. (issues[1] and (": " .. tostring(issues[1].kind) .. " " .. tostring(issues[1].message)) or ""))
end

local function lower_all(src)
    local parsed = Parse.parse_module(src); assert_no("parse", parsed.issues)
    local expanded = OpenExpand.module(parsed.module); assert_no("open", OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
    local closed = ClosureConvert.module(expanded)
    local checked = Typecheck.check_module(closed); assert_no("typecheck", checked.issues)
    local resolved = Layout.module(checked.module)
    local code, contracts = TreeToCode.module_with_contracts(resolved); assert_no("code", CodeValidate.validate(code).issues)
    local graph = CodeGraph.graph(code)
    local flow = CodeFlowFacts.facts(code, graph)
    local value = CodeValueFacts.facts(code, graph, flow)
    local mem = CodeMemFacts.semantic_facts(code, graph, flow, value, contracts)
    local effect = CodeEffectFacts.facts(code, graph, mem, contracts)
    local kernels = CodeKernelPlan.plan(code, graph, flow, value, mem, effect)
    local schedules = CodeSchedulePlan.plan(code, kernels, flow, value, mem, effect)
    local lower = CodeLowerPlan.plan(code, graph, kernels, schedules, Lower.LowerTargetBack)
    return code, graph, flow, value, mem, effect, kernels, schedules, lower
end

local code, graph, flow, value, mem, effect, kernels, schedules, lower = lower_all([[
func sum_loop(n: i32): i32
 return block loop(i: i32 = 0, acc: i32 = 0): i32
  if i >= n then yield acc end
  jump loop(i = i + 1, acc = acc + i)
 end
end
]])

local report = KernelValidate.validate(code, graph, flow, value, mem, effect, kernels, schedules, lower)
assert_no("kernel_validate valid pipeline", report.issues)

local first_fragment = lower.funcs[1].fragments[1]
local bad_fragment = Lower.LowerFragment(
    first_fragment.id,
    first_fragment.cover,
    Lower.LowerStrategyKernel(Kernel.KernelId("kernel:missing"), Schedule.ScheduleId("schedule:missing")),
    first_fragment.proofs,
    first_fragment.issues
)
local bad_lower = Lower.LowerModule(lower.module, lower.target, lower.kernels, lower.schedules, { Lower.LowerFuncPlan(lower.funcs[1].func, { bad_fragment }) }, lower.issues)
report = KernelValidate.validate(code, graph, flow, value, mem, effect, kernels, schedules, bad_lower)
local saw_missing_kernel, saw_missing_schedule = false, false
for _, issue in ipairs(report.issues) do
    if issue.kind == "missing-kernel" then saw_missing_kernel = true end
    if issue.kind == "missing-schedule" then saw_missing_schedule = true end
end
assert(saw_missing_kernel and saw_missing_schedule, "dangling semantic LowerStrategy must fail validation")

local planned_kernel = nil
for _, plan in ipairs(kernels.plans or {}) do if pvm.classof(plan) == Kernel.KernelPlanned then planned_kernel = planned_kernel or plan end end
assert(planned_kernel ~= nil, "test needs a planned kernel")
local bad_schedules = Schedule.ScheduleModulePlan(schedules.module, schedules.target, { Schedule.ScheduleNoPlan(planned_kernel.id, {}) })
report = KernelValidate.validate(code, graph, flow, value, mem, effect, kernels, bad_schedules, lower)
local saw_empty_schedule_reject = false
for _, issue in ipairs(report.issues) do if issue.kind == "schedule-noplan-without-reject" then saw_empty_schedule_reject = true end end
assert(saw_empty_schedule_reject, "ScheduleNoPlan without rejects must fail validation")

local bad_lower_missing_func = Lower.LowerModule(lower.module, lower.target, lower.kernels, lower.schedules, {}, lower.issues)
report = KernelValidate.validate(code, graph, flow, value, mem, effect, kernels, schedules, bad_lower_missing_func)
local saw_missing_lower_func, saw_gap = false, false
for _, issue in ipairs(report.issues) do
    if issue.kind == "missing-lower-func" then saw_missing_lower_func = true end
    if issue.kind == "gap" then saw_gap = true end
end
assert(saw_missing_lower_func and saw_gap, "missing LowerFuncPlan and block coverage gaps must fail validation")

io.write("moonlift kernel_validate ok\n")
