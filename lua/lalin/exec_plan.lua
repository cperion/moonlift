local pvm = require("lalin.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.exec_plan ~= nil then return T._lalin_api_cache.exec_plan end

    local Exec = T.LalinExec
    local Stencil = T.LalinStencil

    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local ExecPlanRules = require("lalin.exec_plan_rules")(T)

    local api = {}

    local function block_ids(func)
        local out = {}
        for _, block in ipairs(func.blocks or {}) do out[#out + 1] = block.id end
        return out
    end

    local function func_fragment_id(func, suffix)
        return Exec.ExecFragmentId("exec:" .. sanitize(func.id.text) .. ":" .. suffix)
    end

    local function scalar_func_fragment(func)
        local blocks = block_ids(func)
        return Exec.ExecFragment(
            func_fragment_id(func, "blocks"),
            func.id,
            blocks,
            Exec.ExecFragmentScalarBlocks(blocks)
        )
    end

    local function artifact_index(artifacts)
        local out = {}
        for _, artifact in ipairs(artifacts or {}) do
            if artifact.instance ~= nil and artifact.instance.id ~= nil then out[artifact.instance.id.text] = artifact end
        end
        return out
    end

    local function graph_loop_indexes(graph)
        local loop_to_func, loop_by_id = {}, {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do
                loop_to_func[loop.id.text] = fg.func
                loop_by_id[loop.id.text] = loop
            end
        end
        return loop_to_func, loop_by_id
    end

    local function domain_func_id(domain, loop_to_func)
        local cls = pvm.classof(domain)
        if cls == T.LalinFlow.FlowDomainFunction then return domain.func end
        if cls == T.LalinFlow.FlowDomainBlockRange then return domain.func end
        if cls == T.LalinFlow.FlowDomainLoop then return loop_to_func[domain.loop.text] end
        return nil
    end

    local function kernel_func_id(kernel_plan, loop_to_func)
        local subject = kernel_plan and kernel_plan.subject or nil
        local cls = pvm.classof(subject)
        if cls == T.LalinKernel.KernelSubjectFunction then return subject.func end
        if cls == T.LalinKernel.KernelSubjectFragment then return subject.func end
        if cls == T.LalinKernel.KernelSubjectLoop then return loop_to_func[subject.loop.text] end
        if cls == T.LalinKernel.KernelSubjectDomain then return domain_func_id(subject.domain, loop_to_func) end
        return nil
    end

    local function append_unique_block(out, seen, id)
        if id ~= nil and not seen[id.text] then
            seen[id.text] = true
            out[#out + 1] = id
        end
    end

    local function domain_blocks(domain, loop_by_id)
        local cls = pvm.classof(domain)
        if cls == T.LalinFlow.FlowDomainBlockRange then return { domain.entry, domain.exit } end
        if cls == T.LalinFlow.FlowDomainLoop then
            local loop = loop_by_id[domain.loop.text]
            local out, seen = {}, {}
            append_unique_block(out, seen, loop and loop.header and loop.header.block)
            for _, block in ipairs(loop and loop.body or {}) do append_unique_block(out, seen, block.block) end
            return out
        end
        return {}
    end

    local function kernel_blocks(kernel_plan, loop_by_id)
        local subject = kernel_plan and kernel_plan.subject or nil
        local cls = pvm.classof(subject)
        if cls == T.LalinKernel.KernelSubjectFragment then return { subject.entry, subject.exit } end
        if cls == T.LalinKernel.KernelSubjectLoop then return domain_blocks(T.LalinFlow.FlowDomainLoop(subject.loop), loop_by_id) end
        if cls == T.LalinKernel.KernelSubjectDomain then return domain_blocks(subject.domain, loop_by_id) end
        return {}
    end

    local function kernel_plan_index(kernels)
        local out = {}
        for _, plan in ipairs(kernels and kernels.plans or {}) do
            if plan.id ~= nil then out[plan.id.text] = plan end
        end
        return out
    end

    local function stencil_decisions(graph, kernels, stencil_plan, artifacts)
        local entries, by_func = {}, {}
        local by_instance = artifact_index(artifacts)
        local loop_to_func, loop_by_id = graph_loop_indexes(graph)
        local by_kernel = kernel_plan_index(kernels)
        for i, entry in ipairs(stencil_plan and stencil_plan.selections or {}) do
            local selection = entry.selection
            local selected = pvm.classof(selection) == Stencil.StencilSelected
            local artifact = selected and by_instance[selection.instance.id.text] or nil
            local kernel_plan = by_kernel[entry.kernel.text]
            local func_id = kernel_func_id(kernel_plan, loop_to_func)
            local rule_selection, err = ExecPlanRules:run("select_exec_fragment", { fragment = {
                stencil_selected = selected,
                has_artifact = artifact ~= nil,
                has_func = func_id ~= nil,
                selected_reason = "selected stencil artifact has executable function owner",
                unselected_reason = "stencil plan entry did not select an artifact",
                missing_artifact_reason = selected and ("selected stencil instance has no artifact " .. selection.instance.id.text) or "selected stencil instance has no artifact",
                missing_func_reason = "selected stencil kernel has no owning Code function",
            } }, "selection", "no exec fragment selected")
            if rule_selection == nil then error("exec_plan: " .. tostring(err), 2) end
            if rule_selection.kind == ExecPlanRules.kind.stencil then
                local blocks = kernel_blocks(kernel_plan, loop_by_id)
                local fragment = Exec.ExecFragment(
                    Exec.ExecFragmentId("exec:" .. sanitize(func_id.text) .. ":stencil:" .. tostring(i)),
                    func_id,
                    blocks,
                    Exec.ExecFragmentStencil(artifact, {}, Exec.ExecResultVoid)
                )
                entries[#entries + 1] = Exec.ExecPlanEntry(entry.kernel, Exec.ExecMaterializeStencil(fragment, rule_selection.reason))
                local list = by_func[func_id.text]
                if list == nil then list = {}; by_func[func_id.text] = list end
                list[#list + 1] = fragment
            elseif rule_selection.kind == ExecPlanRules.kind.skip then
                entries[#entries + 1] = Exec.ExecPlanEntry(entry.kernel, Exec.ExecSkipStencil(rule_selection.reason))
            else
                error("exec_plan: unsupported exec fragment selection " .. tostring(rule_selection.kind), 2)
            end
        end
        return entries, by_func
    end

    local function default_stencil_plan(module, kernels)
        return Stencil.StencilModulePlan(module.id, kernels, {})
    end

    local function plan(module, opts)
        opts = opts or {}
        local graph = opts.graph or CodeGraph.graph(module)
        local flow = opts.flow or CodeFlowFacts.facts(module, graph)
        local value = opts.value or CodeValueFacts.facts(module, graph, flow)
        local mem = opts.mem or CodeMemFacts.semantic_facts(module, graph, flow, value, opts.contracts)
        local effect = opts.effect or CodeEffectFacts.facts(module, graph, mem, opts.contracts)
        local kernels = opts.kernels or CodeKernelPlan.plan(module, graph, flow, value, mem, effect)
        local stencil_plan = opts.stencil or default_stencil_plan(module, kernels)
        local entries, stencil_by_func = stencil_decisions(graph, kernels, stencil_plan, opts.artifacts)

        local funcs = {}
        for _, func in ipairs(module.funcs or {}) do
            local fragments = {}
            for _, fragment in ipairs(stencil_by_func[func.id.text] or {}) do fragments[#fragments + 1] = fragment end
            fragments[#fragments + 1] = scalar_func_fragment(func)
            funcs[#funcs + 1] = Exec.ExecFuncPlan(func.id, fragments)
        end

        return Exec.ExecModulePlan(module.id, stencil_plan, entries, funcs)
    end

    api.plan = plan
    api.module = plan

    T._lalin_api_cache.exec_plan = api
    return api
end

return bind_context
