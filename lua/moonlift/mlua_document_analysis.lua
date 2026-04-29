local pvm = require("moonlift.pvm")
local DocumentParse = require("moonlift.mlua_document_parse")
local HostPipeline = require("moonlift.mlua_host_pipeline")
local OpenFacts = require("moonlift.open_facts")
local OpenValidate = require("moonlift.open_validate")
local TreeTypecheck = require("moonlift.tree_typecheck")
local TreeControlFacts = require("moonlift.tree_control_facts")
local VecLoopFacts = require("moonlift.vec_loop_facts")
local VecLoopDecide = require("moonlift.vec_loop_decide")
local TreeToBack = require("moonlift.tree_to_back")
local BackValidate = require("moonlift.back_validate")

local M = {}

local function module_name_from_uri(uri)
    local text = uri.text or "mlua"
    local name = text:match("([^/%\\]+)$") or text
    name = name:gsub("%.[^%.]*$", "")
    name = name:gsub("[^%w_]", "_")
    if name == "" then name = "mlua" end
    return name
end

function M.Define(T)
    local Mlua = T.Moon2Mlua
    local O = T.Moon2Open
    local Tr = T.Moon2Tree
    local V = T.Moon2Vec
    local B = T.Moon2Back
    local Parse = DocumentParse.Define(T)
    local Pipeline = HostPipeline.Define(T)
    local OF = OpenFacts.Define(T)
    local OV = OpenValidate.Define(T)
    local Typecheck = TreeTypecheck.Define(T)
    local Control = TreeControlFacts.Define(T)
    local VecFacts = VecLoopFacts.Define(T)
    local VecDecide = VecLoopDecide.Define(T)
    local ToBack = TreeToBack.Define(T)
    local Back = BackValidate.Define(T)

    local function append_all(out, xs)
        for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end
    end

    local function default_vec_target()
        local facts = { V.VecTargetVectorBits(128) }
        local shapes = {
            V.VecVectorShape(V.VecElemI32, 4),
            V.VecVectorShape(V.VecElemU32, 4),
            V.VecVectorShape(V.VecElemI64, 2),
            V.VecVectorShape(V.VecElemU64, 2),
        }
        for i = 1, #shapes do facts[#facts + 1] = V.VecTargetSupportsShape(shapes[i]) end
        return V.VecTargetModel(V.VecTargetCraneliftJit, facts)
    end

    local function merge_open_reports(...)
        local issues = {}
        for i = 1, select("#", ...) do
            local report = select(i, ...)
            append_all(issues, report.issues)
        end
        return O.ValidationReport(issues)
    end

    local function open_report_for(parse)
        -- Validate the executable module/open-slot surface. Standalone fragment
        -- parameter imports are authored fragment interfaces, not unfilled uses;
        -- they become meaningful open facts when a module item actually uses or
        -- expands the fragment.
        return merge_open_reports(OV.validate(OF.facts_of_module(parse.combined.module)))
    end

    local collect_regions_from_expr
    local collect_regions_from_view
    local collect_regions_from_place
    local collect_regions_from_stmts

    collect_regions_from_expr = function(expr, out)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprControl then out[#out + 1] = expr.region
        elseif cls == Tr.ExprBlock then
            collect_regions_from_stmts(expr.stmts, out)
            collect_regions_from_expr(expr.result, out)
        elseif cls == Tr.ExprIf then
            collect_regions_from_expr(expr.cond, out); collect_regions_from_expr(expr.then_expr, out); collect_regions_from_expr(expr.else_expr, out)
        elseif cls == Tr.ExprSelect then
            collect_regions_from_expr(expr.cond, out); collect_regions_from_expr(expr.then_expr, out); collect_regions_from_expr(expr.else_expr, out)
        elseif cls == Tr.ExprBinary or cls == Tr.ExprCompare or cls == Tr.ExprLogic then
            collect_regions_from_expr(expr.lhs, out); collect_regions_from_expr(expr.rhs, out)
        elseif cls == Tr.ExprUnary then collect_regions_from_expr(expr.value, out)
        elseif cls == Tr.ExprCast or cls == Tr.ExprMachineCast then collect_regions_from_expr(expr.value, out)
        elseif cls == Tr.ExprCall then for i = 1, #expr.args do collect_regions_from_expr(expr.args[i], out) end
        elseif cls == Tr.ExprLen then collect_regions_from_expr(expr.value, out)
        elseif cls == Tr.ExprField then collect_regions_from_expr(expr.base, out)
        elseif cls == Tr.ExprIndex then collect_regions_from_expr(expr.index, out)
        elseif cls == Tr.ExprView then collect_regions_from_view(expr.view, out)
        elseif cls == Tr.ExprUseExprFrag then for i = 1, #expr.args do collect_regions_from_expr(expr.args[i], out) end
        end
    end

    collect_regions_from_view = function(view, out)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr then collect_regions_from_expr(view.base, out)
        elseif cls == Tr.ViewContiguous then collect_regions_from_expr(view.data, out); collect_regions_from_expr(view.len, out)
        elseif cls == Tr.ViewStrided then collect_regions_from_expr(view.data, out); collect_regions_from_expr(view.len, out); collect_regions_from_expr(view.stride, out)
        elseif cls == Tr.ViewRestrided then collect_regions_from_view(view.base, out); collect_regions_from_expr(view.stride, out)
        elseif cls == Tr.ViewWindow then collect_regions_from_view(view.base, out); collect_regions_from_expr(view.start, out); collect_regions_from_expr(view.len, out)
        elseif cls == Tr.ViewRowBase then collect_regions_from_view(view.base, out); collect_regions_from_expr(view.row_offset, out)
        elseif cls == Tr.ViewInterleaved then collect_regions_from_expr(view.data, out); collect_regions_from_expr(view.len, out); collect_regions_from_expr(view.stride, out); collect_regions_from_expr(view.lane, out)
        elseif cls == Tr.ViewInterleavedView then collect_regions_from_view(view.base, out); collect_regions_from_expr(view.stride, out); collect_regions_from_expr(view.lane, out)
        end
    end

    collect_regions_from_place = function(place, out)
        local cls = pvm.classof(place)
        if cls == Tr.PlaceDeref then collect_regions_from_expr(place.base, out)
        elseif cls == Tr.PlaceDot or cls == Tr.PlaceField then collect_regions_from_place(place.base, out)
        elseif cls == Tr.PlaceIndex then collect_regions_from_expr(place.index, out)
        end
    end

    collect_regions_from_stmts = function(stmts, out)
        for i = 1, #stmts do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtControl then out[#out + 1] = stmt.region
            elseif cls == Tr.StmtLet or cls == Tr.StmtVar then collect_regions_from_expr(stmt.init, out)
            elseif cls == Tr.StmtSet then collect_regions_from_place(stmt.place, out); collect_regions_from_expr(stmt.value, out)
            elseif cls == Tr.StmtExpr then collect_regions_from_expr(stmt.expr, out)
            elseif cls == Tr.StmtAssert then collect_regions_from_expr(stmt.cond, out)
            elseif cls == Tr.StmtIf then collect_regions_from_expr(stmt.cond, out); collect_regions_from_stmts(stmt.then_body, out); collect_regions_from_stmts(stmt.else_body, out)
            elseif cls == Tr.StmtSwitch then
                collect_regions_from_expr(stmt.value, out)
                for j = 1, #stmt.arms do collect_regions_from_stmts(stmt.arms[j].body, out) end
                collect_regions_from_stmts(stmt.default_body, out)
            elseif cls == Tr.StmtJump or cls == Tr.StmtJumpCont then for j = 1, #stmt.args do collect_regions_from_expr(stmt.args[j].value, out) end
            elseif cls == Tr.StmtYieldValue or cls == Tr.StmtReturnValue then collect_regions_from_expr(stmt.value, out)
            elseif cls == Tr.StmtUseRegionFrag then for j = 1, #stmt.args do collect_regions_from_expr(stmt.args[j], out) end
            end
        end
    end

    local function collect_regions(module, parse)
        local out = {}
        for i = 1, #module.items do
            local item = module.items[i]
            if pvm.classof(item) == Tr.ItemFunc then collect_regions_from_stmts(item.func.body, out) end
        end
        -- Standalone region fragments are interfaces until a module expands/uses
        -- them. Control/vector facts are gathered from typed executable control
        -- regions, not from unexpanded fragment source.
        return out
    end

    local function control_facts_for(regions)
        local facts = {}
        for i = 1, #regions do append_all(facts, Control.facts(regions[i]).facts) end
        return facts
    end

    local function vector_for(regions, target)
        local decisions, rejects = {}, {}
        target = target or default_vec_target()
        for i = 1, #regions do
            local facts = VecFacts.facts(regions[i])
            append_all(rejects, facts.rejects)
            local decision = VecDecide.decide(facts, target)
            decisions[#decisions + 1] = decision
            if pvm.classof(decision.chosen) == V.VecLoopScalar then append_all(rejects, decision.chosen.vector_rejects) end
        end
        return decisions, rejects
    end

    local function back_report_for(module, parse_issues, type_issues)
        if #parse_issues > 0 or #type_issues > 0 then return B.BackValidationReport({}) end
        return Back.validate(ToBack.module(module))
    end

    local document_analysis_phase = pvm.phase("moon2_mlua_document_analysis", function(document_parse, target)
        local module_name = module_name_from_uri(document_parse.parts.document.uri)
        local host = Pipeline.run(document_parse.combined, module_name, target)
        local open_report = open_report_for(document_parse)
        local typed = Typecheck.check_module(document_parse.combined.module)
        local regions = collect_regions(typed.module, document_parse)
        local control_facts = control_facts_for(regions)
        local vector_decisions, vector_rejects = vector_for(regions, target)
        local back_report = back_report_for(typed.module, document_parse.combined.issues, typed.issues)
        return Mlua.DocumentAnalysis(
            document_parse,
            host,
            open_report,
            typed.issues,
            control_facts,
            vector_decisions,
            vector_rejects,
            back_report,
            document_parse.anchors
        )
    end, { args_cache = "full" })

    local function analyze_parse(document_parse, target)
        return pvm.one(document_analysis_phase(document_parse, target))
    end

    local function analyze_document(document, target)
        return analyze_parse(Parse.parse_document(document), target)
    end

    return {
        document_analysis_phase = document_analysis_phase,
        analyze_parse = analyze_parse,
        analyze_document = analyze_document,
    }
end

return M
