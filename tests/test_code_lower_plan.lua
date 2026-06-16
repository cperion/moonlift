package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context()
Schema.Define(T)

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
local LowerToBack = require("moonlift.lower_to_back").Define(T)
local BackValidate = require("moonlift.back_validate").Define(T)

local Graph = T.MoonGraph
local Value = T.MoonValue
local Effect = T.MoonEffect
local Kernel = T.MoonKernel
local Schedule = T.MoonSchedule
local Lower = T.MoonLower

local function assert_no_issues(label, report)
    assert(#(report.issues or report) == 0, label .. " expected no issues, got " .. tostring(#(report.issues or report)))
end

local function lower_all(src)
    local parsed = Parse.parse_module(src)
    assert_no_issues("parse", parsed.issues)
    local expanded = OpenExpand.module(parsed.module)
    assert_no_issues("open", OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
    local closed = ClosureConvert.module(expanded)
    local checked = Typecheck.check_module(closed)
    assert_no_issues("typecheck", checked.issues)
    local resolved = Layout.module(checked.module)
    local code, contracts = TreeToCode.module_with_contracts(resolved)
    assert_no_issues("code", CodeValidate.validate(code).issues)
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

local code, graph, flow, value, mem, effect, kernels, schedules, lowered = lower_all([[
func sum_loop(n: i32): i32
    let one: i32 = 1
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + one, acc = acc + i)
    end
end
]])

assert(graph.module == code.id)
assert(pvm.classof(graph.funcs[1].loops[1].id) == Graph.GraphLoopId, "loops are GraphLoopId-keyed")
assert(pvm.classof(value) == Value.ValueFactSet, "Value phase should produce ValueFactSet")
assert(pvm.classof(effect) == Effect.EffectFactSet, "Effect phase should produce EffectFactSet")
assert(pvm.classof(kernels) == Kernel.KernelModulePlan, "Kernel phase should produce KernelModulePlan")
assert(pvm.classof(schedules) == Schedule.ScheduleModulePlan, "Schedule phase should produce ScheduleModulePlan")
assert(pvm.classof(lowered.funcs[1]) == Lower.LowerFuncPlan, "Lower should use LowerFuncPlan fragments")
assert(Lower["LowerFunc" .. "Kernel"] == nil and Lower["LowerFunc" .. "Code"] == nil, "old LowerFunc constructors must be hard-yanked")

local saw_code, saw_semantic, semantic_fallback = false, false, false
for _, fragment in ipairs(lowered.funcs[1].fragments or {}) do
    local cls = pvm.classof(fragment.strategy)
    if cls == Lower.LowerStrategyCode then saw_code = true end
    if cls == Lower.LowerStrategyKernel or cls == Lower.LowerStrategyClosedForm then
        saw_semantic = true
        for _, issue in ipairs(fragment.issues or {}) do if pvm.classof(issue) == Lower.LowerIssueFallback then semantic_fallback = true end end
    end
end
assert(saw_semantic, "supported semantic loops should select real LowerStrategyKernel/ClosedForm")
assert(not semantic_fallback, "supported semantic fragment must not carry fallback issues")
assert(saw_code, "Lower plan should preserve Code fragments around semantic covers")

for _, plan in ipairs(kernels.plans or {}) do
    if pvm.classof(plan) == Kernel.KernelPlanned then
        assert(plan.schedule == nil, "KernelPlanned must not carry schedule choices")
    end
end
assert(#schedules.schedules > 0, "Schedule phase owns kernel schedule choices")

local program = LowerToBack.module(code, graph, flow, value, mem, effect, kernels, schedules, lowered)
assert_no_issues("back", BackValidate.validate(program).issues)

local planned_kernel=nil
for _,p in ipairs(kernels.plans or {}) do if pvm.classof(p)==Kernel.KernelPlanned then planned_kernel=planned_kernel or p end end
assert(planned_kernel~=nil, "test needs planned kernel")
local first_fragment=lowered.funcs[1].fragments[1]
local bad_fragment=Lower.LowerFragment(first_fragment.id, first_fragment.cover, Lower.LowerStrategyKernel(planned_kernel.id, Schedule.ScheduleId("schedule:missing")), first_fragment.proofs, first_fragment.issues)
local bad_lower=Lower.LowerModule(lowered.module, lowered.target, lowered.kernels, lowered.schedules, { Lower.LowerFuncPlan(lowered.funcs[1].func, { bad_fragment }) }, lowered.issues)
local ok, err = pcall(function() LowerToBack.module(code, graph, flow, value, mem, effect, kernels, schedules, bad_lower) end)
assert(not ok and tostring(err):find("missing schedule", 1, true), "LowerToBack must fail loud for dangling semantic strategies")

local unsafe_code, unsafe_graph, unsafe_flow, unsafe_value, unsafe_mem, unsafe_effect, unsafe_kernels, unsafe_schedules, unsafe_lowered = lower_all([[
func plain(n: i32): i32
    return n + 1
end
]])
assert(#unsafe_lowered.funcs[1].fragments > 0, "non-loop function still has Code fragments")
for _, fragment in ipairs(unsafe_lowered.funcs[1].fragments or {}) do
    assert(pvm.classof(fragment.strategy) == Lower.LowerStrategyCode, "non-loop function should remain Code fallback")
end

io.write("moonlift code_lower_plan semantic fragments ok\n")
