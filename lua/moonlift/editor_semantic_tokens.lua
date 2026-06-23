local schema = require("moonlift.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function overlaps(a, b)
    return a.uri == b.uri and a.start_offset < b.stop_offset and b.start_offset < a.stop_offset
end

local function bind_context(T)
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
        if a.kind == S.AnchorBindingUse then return E.TokVariable, {} end
        if a.kind == S.AnchorDiagnostic then return E.TokKeyword, { E.TokModDiagnostic } end
        return nil, nil
    end

    local function tokens_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Mlua.DocumentAnalysis) then
            return (function(analysis)

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
        local filtered = {}
        local last_uri, last_stop = nil, -1
        for i = 1, #out do
            local r = out[i].range
            local uri = r.uri and r.uri.text or ""
            if uri ~= last_uri or r.start_offset >= last_stop then
                filtered[#filtered + 1] = out[i]
                last_uri, last_stop = uri, r.stop_offset
            end
        end
        return as_list(filtered)
            end)(node, ...)
        else
            error("phase moonlift_editor_semantic_tokens: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function range_tokens_phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, E.RangeQuery) then
            return (function(query, analysis)

        local all = tokens_phase(analysis)
        local out = {}
        for i = 1, #all do if overlaps(all[i].range, query.range) then out[#out + 1] = all[i] end end
        return as_list(out)
            end)(node, ...)
        else
            error("phase moonlift_editor_semantic_tokens_range: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function tokens(analysis)
        return tokens_phase(analysis)
    end

    local function range_tokens(query, analysis)
        return range_tokens_phase(query, analysis)
    end

    return {
        tokens_phase = tokens_phase,
        range_tokens_phase = range_tokens_phase,
        tokens = tokens,
        range_tokens = range_tokens,
    }
end

return bind_context