local pvm = require("moonlift.pvm")

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.kernel_validate ~= nil then return T._moonlift_api_cache.kernel_validate end

    local Graph = T.MoonGraph
    local Flow = T.MoonFlow
    local Value = T.MoonValue
    local Mem = T.MoonMem
    local Effect = T.MoonEffect
    local Kernel = T.MoonKernel
    local Schedule = T.MoonSchedule
    local Lower = T.MoonLower

    local KernelEmitSupport = require("moonlift.kernel_emit_support")(T)

    local api = {}

    local function add(ctx, kind, message)
        local issue = { kind = kind, message = message }
        ctx.issues[#ctx.issues + 1] = issue
        if ctx.collector and ctx.collector.emit then pcall(function() ctx.collector:emit(issue, "semantic-lowering") end) end
    end

    local function same_module(ctx, label, code, phase)
        if phase ~= nil and phase.module ~= nil and code ~= nil and phase.module ~= code.id then
            add(ctx, "module-mismatch", label .. " module id does not match CodeModule")
        end
    end

    local function index_code(code)
        local idx = { funcs = {}, blocks_by_func = {}, blocks = {} }
        for _, func in ipairs(code and code.funcs or {}) do
            idx.funcs[func.id.text] = func
            idx.blocks_by_func[func.id.text] = {}
            for _, block in ipairs(func.blocks or {}) do
                idx.blocks[func.id.text .. "\0" .. block.id.text] = block
                idx.blocks_by_func[func.id.text][block.id.text] = block
            end
        end
        return idx
    end

    local function index_graph(graph)
        local loops, funcs = {}, {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            funcs[fg.func.text] = fg
            for _, loop in ipairs(fg.loops or {}) do loops[loop.id.text] = loop end
        end
        return funcs, loops
    end

    local function index_mem(mem)
        local backend, access = {}, {}
        for _, a in ipairs(mem and mem.accesses or {}) do access[a.id.text] = a end
        for _, info in ipairs(mem and mem.backend_info or {}) do backend[info.access.text] = info end
        return access, backend
    end

    local function index_value(value)
        local reductions, closed = {}, {}
        for _, r in ipairs(value and value.reductions or {}) do reductions[tostring(r)] = true end
        for _, cf in ipairs(value and value.closed_forms or {}) do closed[tostring(cf)] = true end
        return reductions, closed
    end

    local function index_kernel(kernels)
        local planned, no_plan = {}, {}
        for _, plan in ipairs(kernels and kernels.plans or {}) do
            local cls = pvm.classof(plan)
            if cls == Kernel.KernelPlanned then planned[plan.id.text] = plan end
            if cls == Kernel.KernelNoPlan and pvm.classof(plan.subject) == Kernel.KernelSubjectLoop then no_plan[plan.subject.loop.text] = plan end
        end
        return planned, no_plan
    end

    local function index_schedule(schedules)
        local planned, all = {}, {}
        for _, sched in ipairs(schedules and schedules.schedules or {}) do
            all[sched.kernel.text] = sched
            if pvm.classof(sched) == Schedule.SchedulePlanned then planned[sched.id.text] = sched end
        end
        return planned, all
    end

    local function backend_safe(info)
        return info ~= nil and pvm.classof(info.trap) == Mem.MemNonTrapping and pvm.classof(info.bounds) ~= Mem.MemBoundsUnknown
    end

    local function kernel_expr_refs(expr, out)
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprKernelValue then out[#out + 1] = expr.value.text end
        if cls == Kernel.KernelExprLoad then return end
    end

    local function validate_kernel(ctx, graph_loops, mem_backend, value, kernels)
        if kernels == nil then add(ctx, "missing-kernel", "missing KernelModulePlan"); return end
        local reductions, closed = index_value(value)
        for _, plan in ipairs(kernels.plans or {}) do
            local cls = pvm.classof(plan)
            if cls == Kernel.KernelNoPlan then
                if #(plan.rejects or {}) == 0 then add(ctx, "kernel-noplan-without-reject", "KernelNoPlan has no rejects") end
            elseif cls == Kernel.KernelPlanned then
                if pvm.classof(plan.subject) == Kernel.KernelSubjectLoop and graph_loops[plan.subject.loop.text] == nil then add(ctx, "missing-loop", "kernel cites missing graph loop " .. plan.subject.loop.text) end
                if pvm.classof(plan.body.equivalence) ~= Kernel.KernelEquivalenceProof or #(plan.body.equivalence.proofs or {}) == 0 then add(ctx, "missing-kernel-proof", "KernelPlanned has no equivalence proofs") end
                local binding_ids = {}
                for _, binding in ipairs(plan.body.bindings or {}) do binding_ids[binding.id.text] = true end
                for _, binding in ipairs(plan.body.bindings or {}) do
                    local refs = {}; kernel_expr_refs(binding.expr, refs)
                    for _, ref in ipairs(refs) do if not binding_ids[ref] then add(ctx, "dangling-kernel-binding", "KernelBinding references missing KernelValueId " .. ref) end end
                end
                for _, stream in ipairs(plan.body.streams or {}) do
                    for _, info in ipairs(stream.backend_info or {}) do
                        local canonical = mem_backend[info.access.text]
                        if canonical == nil then add(ctx, "missing-backend-info", "kernel stream cites missing MemBackendAccessInfo " .. info.access.text)
                        elseif not backend_safe(canonical) then add(ctx, "unsafe-backend-info", "kernel stream cites unsafe MemBackendAccessInfo " .. info.access.text) end
                    end
                end
                for _, effect in ipairs(plan.body.effects or {}) do
                    if pvm.classof(effect) == Kernel.KernelEffectStore then
                        local refs = {}; kernel_expr_refs(effect.value, refs)
                        for _, ref in ipairs(refs) do if not binding_ids[ref] then add(ctx, "dangling-kernel-effect", "KernelEffectStore references missing KernelValueId " .. ref) end end
                    end
                end
                local rcls = pvm.classof(plan.body.result)
                if rcls == Kernel.KernelResultClosedForm and not closed[tostring(plan.body.result.closed_form)] then add(ctx, "missing-closed-form", "kernel result cites a ClosedFormFact outside ValueFactSet") end
                if rcls == Kernel.KernelResultReduction and not reductions[tostring(plan.body.result.reduction)] then add(ctx, "missing-reduction", "kernel result cites a ReductionFact outside ValueFactSet") end
            end
        end
    end

    local function validate_schedule(ctx, kernels_by_id, schedules, flow)
        if schedules == nil then add(ctx, "missing-schedule", "missing ScheduleModulePlan"); return end
        for _, sched in ipairs(schedules.schedules or {}) do
            local cls = pvm.classof(sched)
            if kernels_by_id[sched.kernel.text] == nil then add(ctx, "missing-kernel", "schedule cites missing planned kernel " .. sched.kernel.text) end
            if cls == Schedule.SchedulePlanned then
                if #(sched.proofs or {}) == 0 then add(ctx, "missing-schedule-proof", "schedule " .. sched.id.text .. " has no proofs") end
                local kplan = kernels_by_id[sched.kernel.text]
                if kplan ~= nil then
                    local target = schedules.target and schedules.target.target or nil
                    local cap = KernelEmitSupport.classify(kplan, sched.kind, target, flow)
                    if not cap.executable then add(ctx, "schedule-not-executable", "SchedulePlanned is not executable by semantic lowering: " .. tostring(cap.reason)) end
                end
            elseif cls == Schedule.ScheduleNoPlan then
                if #(sched.rejects or {}) == 0 then add(ctx, "schedule-noplan-without-reject", "ScheduleNoPlan for " .. sched.kernel.text .. " has no rejects") end
            end
        end
    end

    local function cover_blocks(ctx, cover, code_idx, graph_loops)
        local out = {}
        local cls = pvm.classof(cover)
        if cls == Lower.LowerCoverFunction then
            if code_idx.funcs[cover.func.text] == nil then add(ctx, "missing-func", "cover cites missing function " .. cover.func.text); return out end
            for bid in pairs(code_idx.blocks_by_func[cover.func.text] or {}) do out[cover.func.text .. "\0" .. bid] = true end
        elseif cls == Lower.LowerCoverBlock then
            if code_idx.blocks[cover.func.text .. "\0" .. cover.block.text] == nil then add(ctx, "missing-block", "cover cites missing block " .. cover.func.text .. ":" .. cover.block.text) end
            out[cover.func.text .. "\0" .. cover.block.text] = true
        elseif cls == Lower.LowerCoverBlockRange then
            local func = code_idx.funcs[cover.func.text]
            if func == nil then add(ctx, "missing-func", "range cover cites missing function " .. cover.func.text); return out end
            if code_idx.blocks[cover.func.text .. "\0" .. cover.entry.text] == nil then add(ctx, "missing-block", "range cover cites missing entry " .. cover.entry.text) end
            if code_idx.blocks[cover.func.text .. "\0" .. cover.exit.text] == nil then add(ctx, "missing-block", "range cover cites missing exit " .. cover.exit.text) end
            local active = false
            for _, block in ipairs(func.blocks or {}) do
                if block.id == cover.entry then active = true end
                if active then out[cover.func.text .. "\0" .. block.id.text] = true end
                if block.id == cover.exit then break end
            end
        elseif cls == Lower.LowerCoverLoop then
            local loop = graph_loops[cover.loop.text]
            if loop == nil then add(ctx, "missing-loop", "cover cites missing loop " .. cover.loop.text); return out end
            for _, gb in ipairs(loop.body or {}) do
                local key = gb.func.text .. "\0" .. gb.block.text
                if code_idx.blocks[key] == nil then add(ctx, "missing-block", "loop cover cites missing block " .. key) end
                out[key] = true
            end
        end
        return out
    end

    local function validate_strategy(ctx, fragment, kernels_by_id, schedules_by_id, schedules_by_kernel, closed)
        local strategy = fragment.strategy
        local cls = pvm.classof(strategy)
        if cls == Lower.LowerStrategyCode then return end
        if cls == Lower.LowerStrategyKernel then
            local kplan = kernels_by_id[strategy.kernel.text]
            if kplan == nil then add(ctx, "missing-kernel", "LowerStrategyKernel cites missing KernelPlanned " .. strategy.kernel.text) end
            local sched = schedules_by_id[strategy.schedule.text]
             if sched == nil then add(ctx, "missing-schedule", "LowerStrategyKernel cites missing SchedulePlanned " .. strategy.schedule.text)
            elseif sched.kernel ~= strategy.kernel then add(ctx, "strategy-schedule-mismatch", "LowerStrategyKernel schedule does not target the cited kernel") end
        elseif cls == Lower.LowerStrategyClosedForm then
            local kplan = kernels_by_id[strategy.kernel.text]
            if kplan == nil then add(ctx, "missing-kernel", "LowerStrategyClosedForm cites missing KernelPlanned " .. strategy.kernel.text)
            elseif pvm.classof(kplan.body.result) ~= Kernel.KernelResultClosedForm or kplan.body.result.closed_form ~= strategy.fact then add(ctx, "strategy-closed-form-mismatch", "LowerStrategyClosedForm fact does not match KernelResultClosedForm") end
            local sched = schedules_by_kernel[strategy.kernel.text]
            if sched == nil or pvm.classof(sched) ~= Schedule.SchedulePlanned or sched.kind ~= Schedule.ScheduleClosedForm then add(ctx, "missing-schedule", "LowerStrategyClosedForm requires SchedulePlanned(ScheduleClosedForm) for kernel " .. strategy.kernel.text) end
            if not closed[tostring(strategy.fact)] then add(ctx, "missing-closed-form", "LowerStrategyClosedForm cites ClosedFormFact outside ValueFactSet") end
        else
            add(ctx, "unsupported-strategy", "Lower strategy is not executable by semantic lowering without a dedicated emitter: " .. tostring(cls or strategy))
        end
    end


    local function validate_lower(ctx, code_idx, graph_loops, kernels_by_id, schedules_by_id, schedules_by_kernel, closed, lower)
        if lower == nil then add(ctx, "missing-lower", "missing LowerModule"); return end
        local func_plan_count, covered = {}, {}
        for _, func_plan in ipairs(lower.funcs or {}) do
            func_plan_count[func_plan.func.text] = (func_plan_count[func_plan.func.text] or 0) + 1
            if code_idx.funcs[func_plan.func.text] == nil then add(ctx, "missing-func", "lower cites missing function " .. func_plan.func.text) end
            for _, fragment in ipairs(func_plan.fragments or {}) do
                validate_strategy(ctx, fragment, kernels_by_id, schedules_by_id, schedules_by_kernel, closed)
                for key in pairs(cover_blocks(ctx, fragment.cover, code_idx, graph_loops)) do
                    if covered[key] ~= nil then add(ctx, "overlap", "Code block covered by multiple fragments: " .. key) end
                    covered[key] = fragment.id.text
                end
            end
        end
        for func_id in pairs(code_idx.funcs) do
            if (func_plan_count[func_id] or 0) == 0 then add(ctx, "missing-lower-func", "Code function has no LowerFuncPlan: " .. func_id) end
            if (func_plan_count[func_id] or 0) > 1 then add(ctx, "duplicate-lower-func", "Code function has multiple LowerFuncPlans: " .. func_id) end
        end
        for func_id, blocks in pairs(code_idx.blocks_by_func) do
            for block_id in pairs(blocks) do
                local key = func_id .. "\0" .. block_id
                if covered[key] == nil then add(ctx, "gap", "Code block has no executable Lower fragment: " .. key) end
            end
        end
    end

    local function validate(code, graph, flow, value, mem, effect, kernels, schedules, lower, opts)
        local ctx = { issues = {}, collector = opts and opts.collector }
        same_module(ctx, "Graph", code, graph)
        same_module(ctx, "Flow", code, flow)
        same_module(ctx, "Value", code, value)
        same_module(ctx, "Mem", code, mem)
        same_module(ctx, "Effect", code, effect)
        same_module(ctx, "Kernel", code, kernels)
        same_module(ctx, "Schedule", code, schedules)
        same_module(ctx, "Lower", code, lower)

        local code_idx = index_code(code)
        local _, graph_loops = index_graph(graph)
        local _, mem_backend = index_mem(mem)
        local _, closed = index_value(value)
        local kernels_by_id = index_kernel(kernels)
        local planned_schedules_by_id, schedules_by_kernel = index_schedule(schedules)
        validate_kernel(ctx, graph_loops, mem_backend, value, kernels)
        validate_schedule(ctx, kernels_by_id, schedules, flow)
        validate_lower(ctx, code_idx, graph_loops, kernels_by_id, planned_schedules_by_id, schedules_by_kernel, closed, lower)
        return ctx
    end

    api.validate = validate

    T._moonlift_api_cache.kernel_validate = api
    return api
end

return bind_context