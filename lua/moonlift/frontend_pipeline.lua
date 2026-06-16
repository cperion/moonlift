-- moonlift/frontend_pipeline.lua
-- Batch compilation pipeline: parses, typechecks, lowers, and validates
-- a Moonlift source module using the Issue Stream collector.
--
-- For the standalone compiler path. Uses ThrowingCollector so that
-- the first semantic error produces a rich E0xxx formatted error
-- message and halts compilation — preserving the "fail fast" behavior
-- while using the same pipeline as the LSP.

local pvm = require("moonlift.pvm")

local M = {}

local function assert_no_cmd_trap(T, program, site)
    local Back = T.MoonBack
    for i = 1, #(program and program.cmds or {}) do
        local cmd = program.cmds[i]
        if cmd == Back.CmdTrap or pvm.classof(cmd) == Back.CmdTrap or cmd.kind == "CmdTrap" then
            error((site or "frontend lowering") .. " produced CmdTrap at command #" .. tostring(i)
                .. "; unsupported lowering must fail before native code emission", 3)
        end
    end
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
    local KernelValidate = require("moonlift.kernel_validate").Define(T)
    local CodeLowerPlan = require("moonlift.code_lower_plan").Define(T)
    local CodeType = require("moonlift.code_type").Define(T)
    local CodeToBack = require("moonlift.code_to_back").Define(T)
    local CodeToC = require("moonlift.code_to_c").Define(T)
    local LowerToBack = require("moonlift.lower_to_back").Define(T)
    local LowerToC = require("moonlift.lower_to_c").Define(T)
    local Validate = require("moonlift.back_validate").Define(T)
    local CValidate = require("moonlift.c_validate").Define(T)
    local Errors = require("moonlift.error")
    local function lower_module(module, opts)
        opts = opts or {}
        local site = opts.site or "frontend"

        -- Standalone callers get fail-fast diagnostics; LSP/document analysis
        -- passes a CollectingCollector so all issues can be published.
        local analysis_ctx = opts.analysis_ctx or {}
        local collector = opts.collector or Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS,
            analysis_ctx,
            Errors.Catalog,
            Errors.Terminal.render
        )

        local expanded = OpenExpand.module(module, opts.expand_env)
        local open_report = OpenValidate.validate(OpenFacts.facts_of_module(expanded), collector)
        -- ThrowingCollector throws on first issue — no assert_no_issues needed

        local closed = ClosureConvert.module(expanded)
        local checked = Typecheck.check_module(closed, { collector = collector, layout_env = opts.layout_env })

        local resolved = Layout.module(checked.module, opts.layout_env)
        local code_module, code_contracts = TreeToCode.module_with_contracts(resolved, { layout_env = opts.layout_env, target = opts.target, module_id = opts.module_id })
        if code_module == nil then error(site .. " lowering failed: tree_to_code produced nil module", 2) end
        local code_report = CodeValidate.validate(code_module, collector)
        local graph = CodeGraph.graph(code_module)
        local flow_facts = CodeFlowFacts.facts(code_module, graph)
        local flow_semantics = CodeFlowFacts.semantic_facts(code_module, graph, flow_facts)
        local value_facts = CodeValueFacts.facts(code_module, graph, flow_facts)
        local mem_semantics = CodeMemFacts.semantic_facts(code_module, graph, flow_facts, value_facts, code_contracts)
        local mem_facts = CodeMemFacts.facts(code_module, graph, flow_facts, value_facts, code_contracts)
        local effect_facts = CodeEffectFacts.facts(code_module, graph, mem_semantics, code_contracts)
        local kernel_plan = CodeKernelPlan.plan(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts)
        local schedule_plan = CodeSchedulePlan.plan(code_module, kernel_plan, flow_facts, value_facts, mem_semantics, effect_facts, opts.target_model or opts.back_target_model)
        local lower_plan = CodeLowerPlan.plan(code_module, graph, kernel_plan, schedule_plan, T.MoonLower.LowerTargetBack)
        local kernel_report = KernelValidate.validate(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts, kernel_plan, schedule_plan, lower_plan, { collector = collector })

        local program = LowerToBack.module(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts, kernel_plan, schedule_plan, lower_plan)
        if program == nil then error(site .. " lowering failed: code_to_back produced nil program", 2) end
        if not _G.MOONLIFT_ALLOW_TRAP then
            assert_no_cmd_trap(T, program, site)
        end

        local back_report = Validate.validate(program, collector)

        return {
            expanded = expanded,
            open_report = open_report,
            closed = closed,
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
            provenance = nil,
        }
    end

    local function lower_module_to_c(module, opts)
        opts = opts or {}

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
        local open_report = OpenValidate.validate(OpenFacts.facts_of_module(expanded), collector)
        local closed = ClosureConvert.module(expanded)
        local checked = Typecheck.check_module(closed, { collector = collector, layout_env = opts.layout_env, target = c_target, c_target = c_target })
        local layout_env = opts.layout_env
        if layout_env == nil then
            local ModuleType = require("moonlift.tree_module_type").Define(T)
            layout_env = T.MoonSem.LayoutEnv(ModuleType.env(checked.module, c_target).layouts)
        end
        c_opts.layout_env = layout_env
        local resolved = Layout.module(checked.module, layout_env, c_target)
        assert_no_c_phase_unreachable(resolved, opts.site or "C frontend")
        local code_module, code_contracts = TreeToCode.module_with_contracts(resolved, { layout_env = layout_env, target = c_target, module_id = opts.module_id })
        if code_module == nil then error((opts.site or "C frontend") .. " lowering failed: tree_to_code produced nil module", 2) end
        local code_report = CodeValidate.validate(code_module, collector)
        local graph = CodeGraph.graph(code_module)
        local flow_facts = CodeFlowFacts.facts(code_module, graph)
        local flow_semantics = CodeFlowFacts.semantic_facts(code_module, graph, flow_facts)
        local value_facts = CodeValueFacts.facts(code_module, graph, flow_facts)
        local mem_semantics = CodeMemFacts.semantic_facts(code_module, graph, flow_facts, value_facts, code_contracts)
        local mem_facts = CodeMemFacts.facts(code_module, graph, flow_facts, value_facts, code_contracts)
        local effect_facts = CodeEffectFacts.facts(code_module, graph, mem_semantics, code_contracts)
        local kernel_plan = CodeKernelPlan.plan(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts)
        local schedule_plan = CodeSchedulePlan.plan(code_module, kernel_plan, flow_facts, value_facts, mem_semantics, effect_facts, opts.target_model or opts.back_target_model)
        local lower_plan = CodeLowerPlan.plan(code_module, graph, kernel_plan, schedule_plan, T.MoonLower.LowerTargetC)
        local kernel_report = KernelValidate.validate(code_module, graph, flow_facts, value_facts, mem_semantics, effect_facts, kernel_plan, schedule_plan, lower_plan, { collector = collector })
        c_opts.validate = false
        local c_unit = LowerToC.module(code_module, lower_plan, c_opts)
        local c_report = CValidate.validate(c_unit, collector)

        return {
            expanded = expanded,
            open_report = open_report,
            closed = closed,
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

    local function parse_and_lower(src, opts)
        opts = opts or {}
        local site = opts.site or "frontend"
        local analysis_ctx = opts.analysis_ctx or {}
        analysis_ctx.source_text = analysis_ctx.source_text or src
        analysis_ctx.uri = analysis_ctx.uri or opts.chunk_name or opts.name or "?"

        -- Create ThrowingCollector for parse phase
        local Errors = require("moonlift.error")
        local collector = Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS,
            analysis_ctx,
            Errors.Catalog,
            Errors.Terminal.render
        )

        local parsed = Parse.parse_module(src, { collector = collector })
        -- ThrowingCollector throws on parse errors — no assert_no_issues needed

        -- Build anchors from parse scan for precise span resolution
        local S = T.MoonSource
        local PositionIndex = require("moonlift.source_position_index").Define(T)
        local doc = S.DocumentSnapshot(S.DocUri(analysis_ctx.uri or "?"), S.DocVersion(1), S.LangMoonlift, src)
        local index = PositionIndex.build_index(doc)
        local toks = parsed.scan.toks
        local n = toks.n or 0
        local anchors = {}
        local counter = 0
        local function aid(prefix) counter = counter + 1; return prefix .. "." .. counter end
        local keyword_set = {
            ["func"]=true,["region"]=true,["expr"]=true,["struct"]=true,["union"]=true,["handle"]=true,["extern"]=true,
            ["entry"]=true,["block"]=true,["if"]=true,["then"]=true,["elseif"]=true,["else"]=true,
            ["switch"]=true,["case"]=true,["default"]=true,["do"]=true,["end"]=true,
            ["return"]=true,["yield"]=true,["jump"]=true,["emit"]=true,
            ["let"]=true,["var"]=true,["as"]=true,["select"]=true,
            ["assert"]=true,["len"]=true,["view"]=true,["lease"]=true,["invalid"]=true,
            ["noescape"]=true,["invalidate"]=true,["preserve"]=true,
            ["and"]=true,["or"]=true,["not"]=true,
        }
        local opaque_set = {
            ["+"]=true,["-"]=true,["*"]=true,["/"]=true,["%"]=true,["="]=true,
            ["=="]=true,["~="]=true,["<"]=true,["<="]=true,[">"]=true,[">="]=true,
            ["&"]=true,["|"]=true,["^"]=true,["~"]=true,["<<"]=true,[">>"]=true,[">>>"]=true,
            ["["]=true, ["]"]=true, ["("]=true, [")"]=true, ["."]=true, [","]=true, [":"]=true,
        }
        local function add_anchor(prefix, kind, label, start, stop)
            local range = assert(PositionIndex.range_from_offsets(index, start, stop))
            anchors[#anchors + 1] = S.AnchorSpan(S.AnchorId(aid(prefix)), kind, label, range)
        end
        local TK = require("moonlift.parse").TK
        local function add_emit_use_anchor(i, start)
            local j = i + 1
            while toks.kind[j] == TK.nl do j = j + 1 end
            if j > n then return end
            local frag = (toks.kind[j] == TK.hole) and "nil" or tostring(toks.text[j] or "")
            while j <= n and toks.kind[j] ~= TK.lparen do j = j + 1 end
            if j > n then return end
            local depth = 0
            while j <= n do
                if toks.kind[j] == TK.lparen then depth = depth + 1
                elseif toks.kind[j] == TK.rparen then
                    depth = depth - 1
                    if depth == 0 then
                        local after = j + 1
                        local stop = toks.stop[j] or (toks.start[j] or start + 1)
                        add_anchor("emit-use", S.AnchorOpaque("emit-use"), "emit." .. frag .. "." .. tostring(after), start, stop)
                        return
                    end
                end
                j = j + 1
            end
        end
        local after_decl = nil
        local def_next = nil
        for i = 1, n do
            local text = toks.text[i]
            local start = (toks.start[i] or 1) - 1
            local stop = toks.stop[i] or start
            if text and text ~= "" then
                if keyword_set[text] then
                    add_anchor("kw", S.AnchorKeyword, text, start, stop)
                    if text == "emit" then add_emit_use_anchor(i, start) end
                    if text == "func" then after_decl = S.AnchorFunctionName
                    elseif text == "region" then after_decl = S.AnchorRegionName
                    elseif text == "expr" then after_decl = S.AnchorExprName
                    elseif text == "struct" or text == "handle" then after_decl = S.AnchorStructName
                    elseif text == "block" or text == "entry" then after_decl = S.AnchorContinuationName
                    elseif text == "let" or text == "var" then def_next = S.AnchorLocalName
                    end
                elseif text:match("^[_%a][_%w]*$") then
                    local nxt = toks.text[i + 1]
                    local prv = toks.text[i - 1]
                    local kind = S.AnchorBindingUse
                    if after_decl then
                        kind = after_decl
                        after_decl = nil
                    elseif def_next then
                        kind = def_next
                        def_next = nil
                    elseif prv == "emit" or nxt == "(" then
                        kind = S.AnchorFunctionUse
                    end
                    add_anchor("tok", kind, text, start, stop)
                elseif opaque_set[text] then
                    add_anchor("op", S.AnchorOpaque("operator"), text, start, stop)
                end
            end
        end
        analysis_ctx.anchors = anchors

        local result = lower_module(parsed.module, { collector = collector, analysis_ctx = analysis_ctx })
        result.parsed = parsed
        return result
    end

    local function parse_and_lower_c(src, opts)
        opts = opts or {}
        local analysis_ctx = opts.analysis_ctx or {}
        analysis_ctx.source_text = analysis_ctx.source_text or src
        analysis_ctx.uri = analysis_ctx.uri or opts.chunk_name or opts.name or "?"

        local collector = Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS,
            analysis_ctx,
            Errors.Catalog,
            Errors.Terminal.render
        )

        local parsed = Parse.parse_module(src, { collector = collector })

        -- Keep the same analysis context shape as parse_and_lower.  The C path
        -- does not invoke MoonBack/provenance construction.
        if analysis_ctx.anchors == nil then analysis_ctx.anchors = {} end

        local c_opts = {}
        for k, v in pairs(opts) do c_opts[k] = v end
        c_opts.collector = collector
        c_opts.analysis_ctx = analysis_ctx
        local result = lower_module_to_c(parsed.module, c_opts)
        result.parsed = parsed
        return result
    end

    return {
        lower_module = lower_module,
        lower_module_to_c = lower_module_to_c,
        parse_and_lower = parse_and_lower,
        parse_and_lower_c = parse_and_lower_c,
        assert_no_cmd_trap = function(program, site) return assert_no_cmd_trap(T, program, site) end,
        assert_no_c_phase_unreachable = assert_no_c_phase_unreachable,
    }
end

return M
