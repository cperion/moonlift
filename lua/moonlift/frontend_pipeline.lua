-- moonlift/frontend_pipeline.lua
-- Compilation pipeline: typechecks, lowers, and validates a MoonTree module.
-- The DSL produces closed MoonTree directly; no parse or open-module phase needed.

local pvm = require("moonlift.pvm")
local llb = require("llb")

local M = {}

local function progress(ctx, name, payload)
    if not ctx then return end
    payload = payload or {}
    payload.name = name
    ctx. phase (payload)
end

local function assert_no_c_phase_unreachable(root, site)
    local Coverage = require("moonlift.c_coverage")
    local phase_unreachable = {}
    for _, table_ in pairs(Coverage.all_tables()) do
        for variant, c in pairs(table_) do
            if c.status == "phase_unreachable" then phase_unreachable[variant] = c.reason end
        end
    end

    local seen = {}
    local found = {}
    local function walk(node)
        if type(node) ~= "table" or seen[node] then return end
        seen[node] = true
        local cls = pvm.classof(node)
        if cls then
            local kind = cls.kind
            if kind ~= nil and phase_unreachable[kind] then
                found[#found + 1] = tostring(kind) .. ": " .. phase_unreachable[kind]
            end
            local fields = cls.__fields or {}
            for i = 1, #fields do walk(node[fields[i].name]) end
        else
            for _, value in pairs(node) do walk(value) end
        end
    end
    walk(root)
    if #found > 0 then
        table.sort(found)
        error((site or "C frontend") .. " phase boundary failed before tree_to_code/code_to_c; phase_unreachable construct(s) remain:\n" .. table.concat(found, "\n"), 3)
    end
end

function M.Define(T)
    local OpenFacts = require("moonlift.open_facts").Define(T)
    local OpenValidate = require("moonlift.open_validate").Define(T)
    local OpenExpand = require("moonlift.open_expand").Define(T)
    local SurfaceResolve = require("moonlift.surface_resolve").Define(T)
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
    local KernelValidate = require("moonlift.kernel_validate").Define(T)
    local CodeLowerPlan = require("moonlift.code_lower_plan").Define(T)
    local CodeType = require("moonlift.code_type").Define(T)
    local LowerToBack = require("moonlift.lower_to_back").Define(T)
    local LowerToC = require("moonlift.lower_to_c").Define(T)
    local Validate = require("moonlift.back_validate").Define(T)
    local CValidate = require("moonlift.c_validate").Define(T)
    local BackTarget = require("moonlift.back_target_model").Define(T)
    local Errors = require("moonlift.error")
    local function lower_module(module, opts)
        opts = opts or {}
        local process_ctx = opts.process_ctx
        local site = opts.site or "frontend"
        local target_model = opts.target_model or opts.back_target_model or BackTarget.default_native()
        local target = opts.target or BackTarget.host_target(target_model)

        local analysis_ctx = opts.analysis_ctx or {}
        local collector = opts.collector or Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS,
            analysis_ctx,
            Errors.Catalog,
            Errors.Terminal.render
        )

        local expanded = OpenExpand.module(module, opts.expand_env)
        progress(process_ctx, "open_expand", { module = expanded })
        local surfaced = SurfaceResolve.module(expanded)
        progress(process_ctx, "surface_resolve", { module = surfaced })
        local open_report = OpenValidate.validate(OpenFacts.facts_of_module(surfaced), collector)
        progress(process_ctx, "open_validate", { report = open_report })

        local closed = ClosureConvert.module(surfaced)
        progress(process_ctx, "closure_convert", { module = closed })
        local checked = Typecheck.check_module(closed, { collector = collector, layout_env = opts.layout_env })
        progress(process_ctx, "typecheck", { result = checked, module = checked and checked.module })

        local layout_env = opts.layout_env
        do
            local ModuleType = require("moonlift.tree_module_type").Define(T)
            local generated_env = ModuleType.env(checked.module, target)
            if layout_env == nil then
                layout_env = T.MoonSem.LayoutEnv(generated_env.layouts)
            else
                local merged, seen = {}, {}
                local function key(layout)
                    local cls = pvm.classof(layout)
                    if cls == T.MoonSem.LayoutNamed then return "named\0" .. tostring(layout.module_name) .. "\0" .. tostring(layout.type_name) end
                    if cls == T.MoonSem.LayoutLocal then return "local\0" .. tostring(layout.sym and layout.sym.name or layout) end
                    return tostring(layout)
                end
                for _, layout in ipairs(layout_env.layouts or {}) do local k = key(layout); if not seen[k] then seen[k] = true; merged[#merged + 1] = layout end end
                for _, layout in ipairs(generated_env.layouts or {}) do local k = key(layout); if not seen[k] then seen[k] = true; merged[#merged + 1] = layout end end
                layout_env = T.MoonSem.LayoutEnv(merged)
            end
        end
        progress(process_ctx, "layout_env", { layout_env = layout_env })
        local resolved = Layout.module(checked.module, layout_env, target)
        progress(process_ctx, "layout_resolve", { module = resolved })
        local code_module, code_contracts = TreeToCode.module_with_contracts(resolved, { layout_env = layout_env, target = target, module_id = opts.module_id })
        if code_module == nil then error(site .. " lowering failed: tree_to_code produced nil module", 2) end
        progress(process_ctx, "tree_to_code", { code_module = code_module, code_contracts = code_contracts })
        local code_report = CodeValidate.validate(code_module, collector)
        progress(process_ctx, "code_validate", { report = code_report })
        local graph = CodeGraph.graph(code_module)
        progress(process_ctx, "code_graph", { graph = graph })
        local flow_facts = CodeFlowFacts.facts(code_module, graph)
        local flow_semantics = CodeFlowFacts.semantic_facts(code_module, graph, flow_facts)
        progress(process_ctx, "flow_facts", { facts = flow_facts, semantics = flow_semantics })
        local value_facts = CodeValueFacts.facts(code_module, graph, flow_facts)
        progress(process_ctx, "value_facts", { facts = value_facts })
        local mem_semantics = CodeMemFacts.semantic_facts(code_module, graph, flow_facts, value_facts, code_contracts)
        local mem_facts = CodeMemFacts.facts(code_module, graph, flow_facts, value_facts, code_contracts)
        progress(process_ctx, "memory_facts", { facts = mem_facts, semantics = mem_semantics })
        local effect_facts = CodeEffectFacts.facts(code_module, graph, mem_semantics, code_contracts)
        progress(process_ctx, "effect_facts", { facts = effect_facts })
        local kernel_plan = CodeKernelPlan.plan(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts)
        progress(process_ctx, "kernel_plan", { plan = kernel_plan })
        local schedule_plan = CodeSchedulePlan.plan(code_module, kernel_plan, flow_facts, value_facts, mem_semantics, effect_facts, target_model)
        progress(process_ctx, "schedule_plan", { plan = schedule_plan })
        local lower_plan = CodeLowerPlan.plan(code_module, graph, kernel_plan, schedule_plan, T.MoonLower.LowerTargetBack)
        progress(process_ctx, "lower_plan", { plan = lower_plan, target = "back" })
        local kernel_report = KernelValidate.validate(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts, kernel_plan, schedule_plan, lower_plan, { collector = collector })
        progress(process_ctx, "kernel_validate", { report = kernel_report })

        local program = LowerToBack.module(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts, kernel_plan, schedule_plan, lower_plan, { layout_env = layout_env, target = target })
        if program == nil then error(site .. " lowering failed: code_to_back produced nil program", 2) end
        progress(process_ctx, "lower_to_back", { program = program })
        -- CmdTrap is a real Back terminator used for source/generated trap paths
        -- (for example exhaustive variant-dispatch defaults). Unsupported lowering
        -- must fail at the lowering site; the presence of CmdTrap itself is not an
        -- unsupported-lowering sentinel.

        local back_report = Validate.validate(program, collector)
        progress(process_ctx, "back_validate", { report = back_report })

        return {
            checked = checked,
            resolved = resolved,
            code_module = code_module,
            code_contracts = code_contracts,
            code_report = code_report,
            graph = graph,
            flow_facts = flow_facts,
            flow_semantics = flow_semantics,
            value_facts = value_facts,
            mem_facts = mem_facts,
            mem_semantics = mem_semantics,
            effect_facts = effect_facts,
            kernel_plan = kernel_plan,
            schedule_plan = schedule_plan,
            kernel_report = kernel_report,
            lower_plan = lower_plan,
            program = program,
            back_report = back_report,
        }
    end

    local function lower_module_to_c(module, opts)
        opts = opts or {}
        local process_ctx = opts.process_ctx

        local analysis_ctx = opts.analysis_ctx or {}
        local collector = opts.collector or Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS,
            analysis_ctx,
            Errors.Catalog,
            Errors.Terminal.render
        )

        local c_target = CodeType.default_target(opts.c_target or opts)
        local c_opts = {}
        for k, v in pairs(opts.c_opts or {}) do c_opts[k] = v end
        for k, v in pairs(opts) do if c_opts[k] == nil then c_opts[k] = v end end
        c_opts.target = c_target
        c_opts.c_target = c_target

        local expanded = OpenExpand.module(module, opts.expand_env)
        progress(process_ctx, "open_expand", { module = expanded, target = "c" })
        local surfaced = SurfaceResolve.module(expanded)
        progress(process_ctx, "surface_resolve", { module = surfaced, target = "c" })
        local open_report = OpenValidate.validate(OpenFacts.facts_of_module(surfaced), collector)
        progress(process_ctx, "open_validate", { report = open_report, target = "c" })
        local closed = ClosureConvert.module(surfaced)
        progress(process_ctx, "closure_convert", { module = closed, target = "c" })
        local checked = Typecheck.check_module(closed, { collector = collector, layout_env = opts.layout_env, target = c_target, c_target = c_target })
        progress(process_ctx, "typecheck", { result = checked, module = checked and checked.module, target = "c" })
        local layout_env = opts.layout_env
        do
            local ModuleType = require("moonlift.tree_module_type").Define(T)
            local generated_env = ModuleType.env(checked.module, c_target)
            if layout_env == nil then
                layout_env = T.MoonSem.LayoutEnv(generated_env.layouts)
            else
                local merged, seen = {}, {}
                local function key(layout)
                    local cls = pvm.classof(layout)
                    if cls == T.MoonSem.LayoutNamed then return "named\0" .. tostring(layout.module_name) .. "\0" .. tostring(layout.type_name) end
                    if cls == T.MoonSem.LayoutLocal then return "local\0" .. tostring(layout.sym and layout.sym.name or layout) end
                    return tostring(layout)
                end
                for _, layout in ipairs(layout_env.layouts or {}) do local k = key(layout); if not seen[k] then seen[k] = true; merged[#merged + 1] = layout end end
                for _, layout in ipairs(generated_env.layouts or {}) do local k = key(layout); if not seen[k] then seen[k] = true; merged[#merged + 1] = layout end end
                layout_env = T.MoonSem.LayoutEnv(merged)
            end
        end
        c_opts.layout_env = layout_env
        progress(process_ctx, "layout_env", { layout_env = layout_env, target = "c" })
        local resolved = Layout.module(checked.module, layout_env, c_target)
        progress(process_ctx, "layout_resolve", { module = resolved, target = "c" })
        assert_no_c_phase_unreachable(resolved, opts.site or "C frontend")
        local code_module, code_contracts = TreeToCode.module_with_contracts(resolved, { layout_env = layout_env, target = c_target, module_id = opts.module_id })
        if code_module == nil then error((opts.site or "C frontend") .. " lowering failed: tree_to_code produced nil module", 2) end
        progress(process_ctx, "tree_to_code", { code_module = code_module, code_contracts = code_contracts, target = "c" })
        local code_report = CodeValidate.validate(code_module, collector)
        progress(process_ctx, "code_validate", { report = code_report, target = "c" })
        local graph = CodeGraph.graph(code_module)
        progress(process_ctx, "code_graph", { graph = graph, target = "c" })
        local flow_facts = CodeFlowFacts.facts(code_module, graph)
        local flow_semantics = CodeFlowFacts.semantic_facts(code_module, graph, flow_facts)
        progress(process_ctx, "flow_facts", { facts = flow_facts, semantics = flow_semantics, target = "c" })
        local value_facts = CodeValueFacts.facts(code_module, graph, flow_facts)
        progress(process_ctx, "value_facts", { facts = value_facts, target = "c" })
        local mem_semantics = CodeMemFacts.semantic_facts(code_module, graph, flow_facts, value_facts, code_contracts)
        local mem_facts = CodeMemFacts.facts(code_module, graph, flow_facts, value_facts, code_contracts)
        progress(process_ctx, "memory_facts", { facts = mem_facts, semantics = mem_semantics, target = "c" })
        local effect_facts = CodeEffectFacts.facts(code_module, graph, mem_semantics, code_contracts)
        progress(process_ctx, "effect_facts", { facts = effect_facts, target = "c" })
        local kernel_plan = CodeKernelPlan.plan(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts)
        progress(process_ctx, "kernel_plan", { plan = kernel_plan, target = "c" })
        local schedule_plan = CodeSchedulePlan.plan(code_module, kernel_plan, flow_facts, value_facts, mem_semantics, effect_facts, opts.target_model or opts.back_target_model)
        progress(process_ctx, "schedule_plan", { plan = schedule_plan, target = "c" })
        local lower_plan = CodeLowerPlan.plan(code_module, graph, kernel_plan, schedule_plan, T.MoonLower.LowerTargetC)
        progress(process_ctx, "lower_plan", { plan = lower_plan, target = "c" })
        local kernel_report = KernelValidate.validate(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts, kernel_plan, schedule_plan, lower_plan, { collector = collector })
        progress(process_ctx, "kernel_validate", { report = kernel_report, target = "c" })
        c_opts.validate = false
        local c_unit = LowerToC.module(code_module, lower_plan, c_opts)
        progress(process_ctx, "lower_to_c", { c_unit = c_unit, target = "c" })
        local c_report = CValidate.validate(c_unit, collector)
        progress(process_ctx, "c_validate", { report = c_report, target = "c" })

        return {
            checked = checked,
            resolved = resolved,
            code_module = code_module,
            code_contracts = code_contracts,
            code_report = code_report,
            graph = graph,
            flow_facts = flow_facts,
            flow_semantics = flow_semantics,
            value_facts = value_facts,
            mem_facts = mem_facts,
            mem_semantics = mem_semantics,
            effect_facts = effect_facts,
            kernel_plan = kernel_plan,
            schedule_plan = schedule_plan,
            kernel_report = kernel_report,
            lower_plan = lower_plan,
            c_unit = c_unit,
            c_report = c_report,
        }
    end

    local lower_module_process = llb.process. moonlift_lower_module (function(ctx, module, opts)
        opts = opts or {}
        local run_opts = {}
        for k, v in pairs(opts) do run_opts[k] = v end
        run_opts.process_ctx = ctx
        ctx. start { target = "back", site = run_opts.site or "frontend" }
        local ok, result = pcall(lower_module, module, run_opts)
        if not ok then
            ctx. error {
                code = "E_MOONLIFT_LOWER",
                message = tostring(result),
                target = "back",
            }
            return nil
        end
        ctx. done { target = "back", result = result }
        return result
    end)

    local lower_module_to_c_process = llb.process. moonlift_lower_module_to_c (function(ctx, module, opts)
        opts = opts or {}
        local run_opts = {}
        for k, v in pairs(opts) do run_opts[k] = v end
        run_opts.process_ctx = ctx
        ctx. start { target = "c", site = run_opts.site or "C frontend" }
        local ok, result = pcall(lower_module_to_c, module, run_opts)
        if not ok then
            ctx. error {
                code = "E_MOONLIFT_LOWER_C",
                message = tostring(result),
                target = "c",
            }
            return nil
        end
        ctx. done { target = "c", result = result }
        return result
    end)

    return {
        lower_module = lower_module,
        lower_module_to_c = lower_module_to_c,
        lower_module_process = lower_module_process,
        lower_module_to_c_process = lower_module_to_c_process,
        assert_no_c_phase_unreachable = assert_no_c_phase_unreachable,
    }
end

return M
