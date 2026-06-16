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

local Graph = T.MoonGraph
local Flow = T.MoonFlow
local Value = T.MoonValue
local Mem = T.MoonMem
local Effect = T.MoonEffect
local Kernel = T.MoonKernel
local Schedule = T.MoonSchedule

local function assert_no_issues(label, issues)
    assert(#issues == 0, label .. " expected no issues, got " .. tostring(#issues))
end

local function lower_code(src)
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
    return code, contracts
end

local code, contracts = lower_code([[
extern touch(x: i32): i32 end
func fact_phases(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
    requires bounds(dst, n)
    requires bounds(src, n)
    requires disjoint(dst, src)
    let z: i32 = touch(n)
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = src[i]
        dst[i] = x
        jump loop(i = i + 1, acc = acc + i)
    end
end
]])

local graph = CodeGraph.graph(code)
assert(pvm.classof(graph.funcs[1].loops[1].id) == Graph.GraphLoopId, "Graph phase should own loop ids")
assert(#graph.funcs[1].defs > 0 and #graph.funcs[1].uses > 0, "Graph should index defs and uses")

local flow = CodeFlowFacts.facts(code, graph)
assert(flow.module == code.id)
assert(pvm.classof(flow.loops[1].loop) == Graph.GraphLoopId, "Flow loops should cite GraphLoopId")
assert(pvm.classof(flow.loops[1].domain) == Flow.FlowDomainLoop, "Flow domain should wrap Graph loop")
assert(flow.loops[1].counted ~= nil, "counted-loop recognition should remain in Flow")
local semantic = CodeFlowFacts.semantic_facts(code, graph, flow)
local normalized = nil
for _, fact in ipairs(semantic.facts or {}) do if pvm.classof(fact) == Flow.FlowLoopNormalizedCounted then normalized = fact end end
assert(normalized ~= nil, "Flow semantic facts should normalize counted loop")
assert(pvm.classof(normalized.trip_count) == Flow.FlowTripCountUnknown, "Flow must not invent exact trip-count CodeValueId")

local value = CodeValueFacts.facts(code, graph, flow)
assert(pvm.classof(value) == Value.ValueFactSet)
assert(#value.reductions > 0, "Value phase should detect loop-carried reductions before Kernel")
assert(#value.closed_forms > 0 and pvm.classof(value.closed_forms[1]) == Value.ClosedFormFact, "closed forms live in MoonValue before Kernel")
assert(pvm.classof(value.closed_forms[1].expr) ~= Value.ValueExprValue, "closed form must be an exact expression tree, not the accumulator placeholder")

local mem = CodeMemFacts.semantic_facts(code, graph, flow, value, contracts)
assert(pvm.classof(mem) == Mem.MemSemanticFactSet)
assert(#mem.backend_info > 0, "Mem phase should produce MemBackendAccessInfo for loads/stores")
local saw_backend = false
for _, info in ipairs(mem.backend_info or {}) do if pvm.classof(info) == Mem.MemBackendAccessInfo then saw_backend = true end end
assert(saw_backend, "backend info entries should use MoonMem.MemBackendAccessInfo")

local effect = CodeEffectFacts.facts(code, graph, mem, contracts)
assert(pvm.classof(effect) == Effect.EffectFactSet)
assert(#effect.calls > 0, "Effect phase should summarize calls")
assert(pvm.classof(effect.calls[1]) == Effect.CallSummary, "call summary should be MoonEffect.CallSummary")

local kernels = CodeKernelPlan.plan(code, graph, flow, value, mem, effect)
for _, plan in ipairs(kernels.plans or {}) do
    if pvm.classof(plan) == Kernel.KernelPlanned and pvm.classof(plan.body.result) == Kernel.KernelResultClosedForm then
        assert(pvm.classof(plan.body.result.closed_form) == Value.ClosedFormFact, "Kernel closed-form result should cite MoonValue.ClosedFormFact")
    end
end

local schedules = CodeSchedulePlan.plan(code, kernels, flow, value, mem, effect)
assert(pvm.classof(schedules) == Schedule.ScheduleModulePlan)
local saw_real_schedule, saw_kernel_reject, saw_schedule_reject = false, false, false
for _, plan in ipairs(kernels.plans or {}) do
    if pvm.classof(plan) == Kernel.KernelNoPlan and pvm.classof(plan.subject) == Kernel.KernelSubjectLoop and #(plan.rejects or {}) > 0 then saw_kernel_reject = true end
end
for _, sched in ipairs(schedules.schedules or {}) do
    if pvm.classof(sched) == Schedule.SchedulePlanned then
        saw_real_schedule = true
        assert(#sched.proofs > 0, "real SchedulePlanned must carry proofs")
    elseif sched.rejects ~= nil then
        assert(#sched.rejects > 0, "ScheduleNoPlan must carry rejects")
        saw_schedule_reject = true
    end
end
assert(saw_real_schedule or saw_kernel_reject or saw_schedule_reject, "semantic loops must either schedule real executable plans or reject explicitly")

io.write("moonlift semantic fact phases ok\n")
