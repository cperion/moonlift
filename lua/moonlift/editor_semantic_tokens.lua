local pvm = require("moonlift.pvm")

local M = {}

local function overlaps(a, b)
    return a.uri == b.uri and a.start_offset < b.stop_offset and b.start_offset < a.stop_offset
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local Mlua = T.MoonMlua

    local function token_for_anchor(a)
        if a.kind == S.AnchorKeyword then return E.TokKeyword, {} end
        if a.kind == S.AnchorScalarType then return E.TokType, { E.TokModDefaultLibrary } end
        if a.kind == S.AnchorStructName then return E.TokStruct, { E.TokModDefinition } end
        if a.kind == S.AnchorFieldName then return E.TokProperty, { E.TokModDefinition } end
        if a.kind == S.AnchorFieldUse then return E.TokProperty, {} end
        if a.kind == S.AnchorFunctionName or a.kind == S.AnchorMethodName then return E.TokFunction, { E.TokModDefinition } end
        if a.kind == S.AnchorFunctionUse then return E.TokFunction, {} end
        if a.kind == S.AnchorParamName then return E.TokParameter, { E.TokModDefinition } end
        if a.kind == S.AnchorLocalName then return E.TokVariable, { E.TokModDefinition } end
        if a.kind == S.AnchorRegionName or a.kind == S.AnchorExprName then return E.TokFunction, { E.TokModDefinition } end
        if a.kind == S.AnchorContinuationName then return E.TokFunction, { E.TokModDefinition } end
        if a.kind == S.AnchorContinuationUse then return E.TokFunction, {} end
        if a.kind == S.AnchorBuiltinName then return E.TokNamespace, { E.TokModDefaultLibrary } end
        if a.kind == S.AnchorPackedAlign then return E.TokNumber, { E.TokModStorage } end
        if a.kind == S.AnchorExposeName or a.kind == S.AnchorModuleName then return E.TokNamespace, { E.TokModDefinition } end
        if a.kind == S.AnchorBindingUse then return E.TokType, {} end
        if a.kind == S.AnchorDiagnostic then return E.TokKeyword, { E.TokModDiagnostic } end
        return nil, nil
    end

    local tokens_phase = pvm.phase("moon2_editor_semantic_tokens", {
        [Mlua.DocumentAnalysis] = function(analysis)
        local out = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            local tt, mods = token_for_anchor(a)
            if tt and a.range.stop_offset > a.range.start_offset then
                out[#out + 1] = E.SemanticTokenSpan(a.range, tt, mods)
            end
        end
        table.sort(out, function(a, b)
            if a.range.start.line ~= b.range.start.line then return a.range.start.line < b.range.start.line end
            if a.range.start.utf16_col ~= b.range.start.utf16_col then return a.range.start.utf16_col < b.range.start.utf16_col end
            return a.range.stop_offset < b.range.stop_offset
        end)
        return pvm.seq(out)
        end,
    })

    local range_tokens_phase = pvm.phase("moon2_editor_semantic_tokens_range", {
        [E.RangeQuery] = function(query, analysis)
        local all = pvm.drain(tokens_phase(analysis))
        local out = {}
        for i = 1, #all do if overlaps(all[i].range, query.range) then out[#out + 1] = all[i] end end
        return pvm.seq(out)
        end,
    }, { args_cache = "full" })

    local function tokens(analysis)
        return pvm.drain(tokens_phase(analysis))
    end

    local function range_tokens(query, analysis)
        return pvm.drain(range_tokens_phase(query, analysis))
    end

    return {
        tokens_phase = tokens_phase,
        range_tokens_phase = range_tokens_phase,
        tokens = tokens,
        range_tokens = range_tokens,
    }
end

return M
