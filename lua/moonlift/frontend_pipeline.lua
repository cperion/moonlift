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

function M.Define(T)
    local Parse = require("moonlift.parse").Define(T)
    local OpenFacts = require("moonlift.open_facts").Define(T)
    local OpenValidate = require("moonlift.open_validate").Define(T)
    local OpenExpand = require("moonlift.open_expand").Define(T)
    local ClosureConvert = require("moonlift.closure_convert").Define(T)
    local Typecheck = require("moonlift.tree_typecheck").Define(T)
    local Layout = require("moonlift.sem_layout_resolve").Define(T)
    local Lower = require("moonlift.tree_to_back").Define(T)
    local Validate = require("moonlift.back_validate").Define(T)
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
        local checked = Typecheck.check_module(closed, { collector = collector })

        local resolved = Layout.module(checked.module, opts.layout_env)
        local program, provenance = Lower.module(resolved)
        if program == nil then error(site .. " lowering failed: tree_to_back produced nil program", 2) end
        if not _G.MOONLIFT_ALLOW_TRAP then
            assert_no_cmd_trap(T, program, site)
        end
        -- Attach provenance map to analysis context for span resolution
        if provenance then
            analysis_ctx.back_provenance = provenance
        end

        local back_report = Validate.validate(program, collector)

        return {
            expanded = expanded,
            open_report = open_report,
            closed = closed,
            checked = checked,
            resolved = resolved,
            program = program,
            back_report = back_report,
            provenance = provenance,
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
            ["func"]=true,["region"]=true,["expr"]=true,["struct"]=true,["union"]=true,["extern"]=true,
            ["entry"]=true,["block"]=true,["if"]=true,["then"]=true,["elseif"]=true,["else"]=true,
            ["switch"]=true,["case"]=true,["default"]=true,["do"]=true,["end"]=true,
            ["return"]=true,["yield"]=true,["jump"]=true,["emit"]=true,
            ["let"]=true,["var"]=true,["as"]=true,["select"]=true,
            ["assert"]=true,["len"]=true,["view"]=true,["and"]=true,["or"]=true,["not"]=true,
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
                    elseif text == "struct" then after_decl = S.AnchorStructName
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

    return {
        lower_module = lower_module,
        parse_and_lower = parse_and_lower,
        assert_no_cmd_trap = function(program, site) return assert_no_cmd_trap(T, program, site) end,
    }
end

return M
