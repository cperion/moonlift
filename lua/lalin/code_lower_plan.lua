local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_lower_plan ~= nil then return T._lalin_api_cache.code_lower_plan end

    local Kernel = T.LalinKernel
    local Schedule = T.LalinSchedule
    local Lower = T.LalinLower
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local CodeSchedulePlan = require("lalin.code_schedule_plan")(T)

    local api = {}
    local block_set_for

    function Schedule.KernelSchedule:lower_plan_is_planned_schedule() return false end
    function Schedule.SchedulePlanned:lower_plan_is_planned_schedule() return true end
    function Schedule.KernelSchedule:lower_plan_is_closed_form_schedule() return false end
    function Schedule.SchedulePlanned:lower_plan_is_closed_form_schedule()
        return self.kind == Schedule.ScheduleClosedForm
    end

    function Kernel.KernelResult:lower_plan_closed_form_fact() return nil end
    function Kernel.KernelResultClosedForm:lower_plan_closed_form_fact() return self.closed_form end

    function Lower.LowerFragmentPlanInput:select_lower_fragment()
        if self.kernel ~= nil then
            if self.schedule ~= nil and self.schedule:lower_plan_is_planned_schedule() then
                if self.schedule:lower_plan_is_closed_form_schedule() then
                    if self.closed_form ~= nil then return Lower.LowerSelectClosedForm(self.closed_form) end
                    return Lower.LowerSelectFallback(self.closed_form_missing_reason)
                end
                return Lower.LowerSelectKernel
            end
            return Lower.LowerSelectFallback(self.no_schedule_reason)
        end
        if self.kernel_no_plan ~= nil then return Lower.LowerSelectFallback(self.kernel_no_plan_reason) end
        return Lower.LowerSelectNone
    end

    function Lower.LowerFragmentSelection:lower_plan_is_closed_form() return false end
    function Lower.LowerSelectClosedForm:lower_plan_is_closed_form() return true end
    function Lower.LowerFragmentSelection:lower_plan_is_kernel() return false end
    function Lower.LowerSelectKernel:lower_plan_is_kernel() return true end
    function Lower.LowerFragmentSelection:lower_plan_is_fallback() return false end
    function Lower.LowerSelectFallback:lower_plan_is_fallback() return true end
    function Lower.LowerFragmentSelection:lower_plan_is_none() return false end
    function Lower.LowerSelectNone:lower_plan_is_none() return true end

    function Lower.LowerFragmentSelection:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
        error("code_lower_plan: unsupported lower fragment selection", 2)
    end

    function Lower.LowerSelectClosedForm:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
        fragments[#fragments + 1] = Lower.LowerFragment(
            Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":semantic:" .. sanitize(loop.id.text)),
            cover,
            Lower.LowerStrategyClosedForm(kplan.id, self.closed_form),
            {
                Lower.LowerProofKernel(kplan.id, "planned semantic closed-form kernel"),
                Lower.LowerProofSchedule(sched.id, "closed-form schedule has a semantic lowering emitter"),
            },
            {}
        )
        for block in pairs(block_set_for(loop)) do covered[block] = true end
    end

    function Lower.LowerSelectKernel:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
        fragments[#fragments + 1] = Lower.LowerFragment(
            Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":semantic:" .. sanitize(loop.id.text)),
            cover,
            Lower.LowerStrategyKernel(kplan.id, sched.id),
            {
                Lower.LowerProofKernel(kplan.id, "planned semantic kernel"),
                Lower.LowerProofSchedule(sched.id, "kernel schedule has a semantic lowering emitter"),
            },
            {}
        )
        for block in pairs(block_set_for(loop)) do covered[block] = true end
    end

    function Lower.LowerSelectFallback:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
        local issue = Lower.LowerIssueFallback(cover, self.reason)
        issues[#issues + 1] = issue
        fragments[#fragments + 1] = Lower.LowerFragment(
            Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":loop_fallback:" .. sanitize(loop.id.text)),
            cover,
            Lower.LowerStrategyCode(self.reason),
            { Lower.LowerProofFallback(self.reason) },
            { issue }
        )
        for block in pairs(block_set_for(loop)) do covered[block] = true end
    end

    function Lower.LowerSelectNone:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched) end

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
            local cls = asdl.classof(plan)
            if cls == Kernel.KernelPlanned and asdl.classof(plan.subject) == Kernel.KernelSubjectLoop then planned[plan.subject.loop.text] = plan end
            if cls == Kernel.KernelNoPlan and asdl.classof(plan.subject) == Kernel.KernelSubjectLoop then no_plan[plan.subject.loop.text] = plan end
        end
        return planned, no_plan
    end

    local function schedule_by_kernel(schedules)
        local out = {}
        for _, sched in ipairs(schedules and schedules.schedules or {}) do out[sched.kernel.text] = sched end
        return out
    end

    block_set_for = function(loop)
        local set = {}
        for _, bid in ipairs(loop and loop.body or {}) do set[bid.block.text] = true end
        return set
    end

    local function loop_body_count(loop)
        return #(loop and loop.body or {})
    end

    local function ordered_loops(graph_func)
        local loops = {}
        for i, loop in ipairs(graph_func and graph_func.loops or {}) do
            loops[#loops + 1] = { loop = loop, ordinal = i, blocks = loop_body_count(loop) }
        end
        table.sort(loops, function(a, b)
            if a.blocks ~= b.blocks then return a.blocks < b.blocks end
            local at = a.loop and a.loop.id and a.loop.id.text or ""
            local bt = b.loop and b.loop.id and b.loop.id.text or ""
            if at ~= bt then return at < bt end
            return a.ordinal < b.ordinal
        end)
        return loops
    end

    local function can_claim_loop(loop, covered)
        for block in pairs(block_set_for(loop)) do
            if covered[block] then return false end
        end
        return true
    end

    local function loop_result_closed_form(kernel_plan)
        local result = kernel_plan and kernel_plan.body and kernel_plan.body.result or nil
        if asdl.classof(result) == Kernel.KernelResultClosedForm then return result.closed_form end
        return nil
    end

    local function reject_summary(rejects)
        local out = {}
        for _, reject in ipairs(rejects or {}) do out[#out + 1] = tostring(asdl.classof(reject) or reject) end
        return #out > 0 and table.concat(out, ",") or "no detailed rejects"
    end

    local function schedule_summary(sched)
        if sched == nil then return "no schedule was produced" end
        if asdl.classof(sched) == Schedule.ScheduleNoPlan then return "schedule rejected: " .. reject_summary(sched.rejects) end
        return "schedule selected"
    end

    local function lower_fragment_input(loop, kplan, no_plan, sched)
        local cf = loop_result_closed_form(kplan)
        local skipped
        if cf ~= nil then
            skipped = "closed-form fact " .. tostring(cf.id and cf.id.text or cf)
        elseif kplan ~= nil then
            skipped = "kernel " .. kplan.id.text
        else
            skipped = "loop " .. loop.id.text
        end

        return Lower.LowerFragmentPlanInput(
            kplan,
            no_plan,
            sched,
            cf,
            "explicit Code fallback because ScheduleClosedForm has no ClosedFormFact",
            "explicit Code fallback for " .. skipped .. ": " .. schedule_summary(sched),
            no_plan ~= nil and ("explicit Code fallback because KernelNoPlan rejected loop: " .. reject_summary(no_plan.rejects)) or ""
        )
    end

    local function plan_func(func, graph_func, kernel_for_loop, kernel_no_plan_for_loop, schedule_for_kernel, issues)
        local fragments, covered = {}, {}
        local function add(fragment)
            fragments[#fragments + 1] = fragment
            return fragment
        end

        for _, ordered in ipairs(ordered_loops(graph_func)) do
            local loop = ordered.loop
            if can_claim_loop(loop, covered) then
                local kplan = kernel_for_loop[loop.id.text]
                local cover = Lower.LowerCoverLoop(loop.id)
                local sched = kplan ~= nil and schedule_for_kernel[kplan.id.text] or nil
                local no_plan = kernel_no_plan_for_loop[loop.id.text]
                local selection = lower_fragment_input(loop, kplan, no_plan, sched):select_lower_fragment()
                selection:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
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

    T._lalin_api_cache.code_lower_plan = api
    return api
end

return bind_context
