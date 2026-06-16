local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_lower_plan ~= nil then return T._moonlift_api_cache.code_lower_plan end

    local Kernel = T.MoonKernel
    local Schedule = T.MoonSchedule
    local Lower = T.MoonLower
    local CodeGraph = require("moonlift.code_graph").Define(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts").Define(T)
    local CodeValueFacts = require("moonlift.code_value_facts").Define(T)
    local CodeMemFacts = require("moonlift.code_mem_facts").Define(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts").Define(T)
    local CodeKernelPlan = require("moonlift.code_kernel_plan").Define(T)
    local CodeSchedulePlan = require("moonlift.code_schedule_plan").Define(T)

    local api = {}

    local function graph_indexes(graph)
        local loops, funcs = {}, {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            funcs[fg.func.text] = fg
            for _, loop in ipairs(fg.loops or {}) do loops[loop.id.text] = loop end
        end
        return funcs, loops
    end

    local function kernels_by_loop(kernels)
        local planned, no_plan = {}, {}
        for _, plan in ipairs(kernels and kernels.plans or {}) do
            local cls = pvm.classof(plan)
            if cls == Kernel.KernelPlanned and pvm.classof(plan.subject) == Kernel.KernelSubjectLoop then planned[plan.subject.loop.text] = plan end
            if cls == Kernel.KernelNoPlan and pvm.classof(plan.subject) == Kernel.KernelSubjectLoop then no_plan[plan.subject.loop.text] = plan end
        end
        return planned, no_plan
    end

    local function schedule_by_kernel(schedules)
        local out = {}
        for _, sched in ipairs(schedules and schedules.schedules or {}) do out[sched.kernel.text] = sched end
        return out
    end

    local function block_set_for(loop)
        local set = {}
        for _, bid in ipairs(loop and loop.body or {}) do set[bid.block.text] = true end
        return set
    end

    local function loop_result_closed_form(kernel_plan)
        local result = kernel_plan and kernel_plan.body and kernel_plan.body.result or nil
        if pvm.classof(result) == Kernel.KernelResultClosedForm then return result.closed_form end
        return nil
    end

    local function reject_summary(rejects)
        local out = {}
        for _, reject in ipairs(rejects or {}) do out[#out + 1] = tostring(pvm.classof(reject) or reject) end
        return #out > 0 and table.concat(out, ",") or "no detailed rejects"
    end

    local function schedule_summary(sched)
        if sched == nil then return "no schedule was produced" end
        if pvm.classof(sched) == Schedule.ScheduleNoPlan then return "schedule rejected: " .. reject_summary(sched.rejects) end
        return "schedule selected"
    end

    local function add_loop_code_fallback(func, loop, cover, fragments, covered, issues, reason)
        local issue = Lower.LowerIssueFallback(cover, reason)
        issues[#issues + 1] = issue
        fragments[#fragments + 1] = Lower.LowerFragment(
            Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":loop_fallback:" .. sanitize(loop.id.text)),
            cover,
            Lower.LowerStrategyCode(reason),
            { Lower.LowerProofFallback(reason) },
            { issue }
        )
        for block in pairs(block_set_for(loop)) do covered[block] = true end
    end

    local function plan_func(func, graph_func, kernel_for_loop, kernel_no_plan_for_loop, schedule_for_kernel, issues)
        local fragments, covered = {}, {}
        local function add(fragment)
            fragments[#fragments + 1] = fragment
            return fragment
        end

        for _, loop in ipairs(graph_func and graph_func.loops or {}) do
            local kplan = kernel_for_loop[loop.id.text]
            local cover = Lower.LowerCoverLoop(loop.id)
            if kplan ~= nil then
                local sched = schedule_for_kernel[kplan.id.text]
                if sched ~= nil and pvm.classof(sched) == Schedule.SchedulePlanned then
                    local strategy, proofs
                    local cf = loop_result_closed_form(kplan)
                    if sched.kind == Schedule.ScheduleClosedForm then
                        if cf == nil then
                            add_loop_code_fallback(func, loop, cover, fragments, covered, issues, "explicit Code fallback because ScheduleClosedForm has no ClosedFormFact")
                        else
                            strategy = Lower.LowerStrategyClosedForm(kplan.id, cf)
                            proofs = { Lower.LowerProofKernel(kplan.id, "planned semantic closed-form kernel"), Lower.LowerProofSchedule(sched.id, "closed-form schedule has a LowerToBack emitter") }
                        end
                    else
                        strategy = Lower.LowerStrategyKernel(kplan.id, sched.id)
                        proofs = { Lower.LowerProofKernel(kplan.id, "planned semantic kernel"), Lower.LowerProofSchedule(sched.id, "kernel schedule has a LowerToBack emitter") }
                    end
                    if strategy ~= nil then
                        add(Lower.LowerFragment(
                            Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":semantic:" .. sanitize(loop.id.text)),
                            cover,
                            strategy,
                            proofs,
                            {}
                        ))
                        for block in pairs(block_set_for(loop)) do covered[block] = true end
                    end
                else
                    local cf = loop_result_closed_form(kplan)
                    local skipped = cf and ("closed-form fact " .. tostring(cf.id and cf.id.text or cf)) or ("kernel " .. kplan.id.text)
                    add_loop_code_fallback(func, loop, cover, fragments, covered, issues, "explicit Code fallback for " .. skipped .. ": " .. schedule_summary(sched))
                end
            else
                local no_plan = kernel_no_plan_for_loop[loop.id.text]
                if no_plan ~= nil then
                    add_loop_code_fallback(func, loop, cover, fragments, covered, issues, "explicit Code fallback because KernelNoPlan rejected loop: " .. reject_summary(no_plan.rejects))
                end
            end
        end

        for _, block in ipairs(func.blocks or {}) do
            if not covered[block.id.text] then
                add(Lower.LowerFragment(
                    Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":block:" .. sanitize(block.id.text)),
                    Lower.LowerCoverBlock(func.id, block.id),
                    Lower.LowerStrategyCode("ordinary Code lowering for uncovered block"),
                    { Lower.LowerProofCoverage("block is not covered by a kernel fragment") },
                    {}
                ))
                covered[block.id.text] = true
            end
        end

        if #fragments == 0 then
            local issue = Lower.LowerIssueGap(func.id, "function has no Code blocks to cover")
            issues[#issues + 1] = issue
        end
        return Lower.LowerFuncPlan(func.id, fragments)
    end

    local function plan(code_module, graph, kernels, schedules, target)
        graph = graph or CodeGraph.graph(code_module)
        if kernels == nil then
            local flow = CodeFlowFacts.facts(code_module, graph)
            local value = CodeValueFacts.facts(code_module, graph, flow)
            local mem = CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
            local effect = CodeEffectFacts.facts(code_module, graph, mem, nil)
            kernels = CodeKernelPlan.plan(code_module, graph, flow, value, mem, effect)
            schedules = schedules or CodeSchedulePlan.plan(code_module, kernels, flow, value, mem, effect, nil)
        end
        schedules = schedules or CodeSchedulePlan.plan(code_module, kernels, nil, nil, nil, nil, nil)
        target = target or Lower.LowerTargetBack

        local graph_funcs = graph_indexes(graph)
        local kernel_for_loop, kernel_no_plan_for_loop = kernels_by_loop(kernels)
        local schedule_for_kernel = schedule_by_kernel(schedules)
        local funcs, issues = {}, {}
        for _, func in ipairs(code_module.funcs or {}) do funcs[#funcs + 1] = plan_func(func, graph_funcs[func.id.text], kernel_for_loop, kernel_no_plan_for_loop, schedule_for_kernel, issues) end
        return Lower.LowerModule(code_module.id, target, kernels, schedules, funcs, issues)
    end

    api.plan = plan
    api.module = plan

    T._moonlift_api_cache.code_lower_plan = api
    return api
end

return M
