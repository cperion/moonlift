local asdl = require("lalin.asdl")

local M = {}

local resolved_cache = setmetatable({}, { __mode = "k" })

local function class_name(v)
    local mt = type(v) == "table" and getmetatable(v) or nil
    return mt and rawget(mt, "__dsl_class") or nil
end

local function is_decl(v)
    return class_name(v) == "Decl"
end

local function append_decl_items(out, value)
    local ok, cls = pcall(asdl.classof, value)
    cls = ok and cls or nil
    if cls and tostring(cls) == "Class(LalinTree.Module)" then
        for i = 1, #(value.items or {}) do out[#out + 1] = value.items[i] end
        return
    end
    if cls and tostring(asdl.class_basename(value) or ""):match("^Item") then
        out[#out + 1] = value
        return
    end
    if is_decl(value) then
        if value.kind == "unit" then
            local unit_module = value:syntax()
            for i = 1, #unit_module.items do out[#out + 1] = unit_module.items[i] end
        else
            out[#out + 1] = value:syntax_item()
        end
    elseif type(value) == "table" then
        for i = 1, #value do append_decl_items(out, value[i]) end
    end
end

local function line_col(text, offset0)
    local line, col = 0, 0
    local limit = math.max(0, math.min(#text, offset0 or 0))
    for i = 1, limit do
        if text:byte(i) == 10 then
            line, col = line + 1, 0
        else
            col = col + 1
        end
    end
    return line, col
end

local function first_number(s)
    return tonumber(tostring(s):match(":(%d+):")) or 1
end

local function bind_context(T)
    local S = T.LalinSource
    local Pm = T.LalinParse
    local Mlua = T.LalinMlua
    local H = T.LalinHost
    local Tr = T.LalinTree
    local B = T.LalinBack
    local PositionIndex = require("lalin.source_position_index")(T)
    local Typecheck = require("lalin.tree_typecheck")(T)

    local function translate_asdl(v, seen)
        local tv = type(v)
        if tv ~= "table" then return v end
        seen = seen or {}
        if seen[v] then return seen[v] end

        local ok, cls = pcall(asdl.classof, v)
        cls = ok and cls or nil
        local cls_text = cls and tostring(cls) or ""
        local mod_name, ctor_name = cls_text:match("^Class%((Lalin[%w_]+)%.([%w_]+)%)$")
        if mod_name and ctor_name and T[mod_name] and T[mod_name][ctor_name] ~= nil then
            local ctor = T[mod_name][ctor_name]
            local fields = asdl.fields(cls) or {}
            if #fields == 0 then
                return type(ctor) == "function" and ctor() or ctor
            end
            local args = {}
            seen[v] = args
            for i = 1, #fields do
                args[i] = translate_asdl(v[fields[i].name], seen)
            end
            local out = ctor(unpack(args))
            seen[v] = out
            return out
        end

        local out = {}
        seen[v] = out
        for k, x in pairs(v) do out[k] = translate_asdl(x, seen) end
        return out
    end

    local function range(index, start0, stop0)
        start0 = math.max(0, math.min(#index.document.text, start0 or 0))
        stop0 = math.max(start0, math.min(#index.document.text, stop0 or start0))
        if stop0 == start0 and stop0 < #index.document.text then stop0 = stop0 + 1 end
        return assert(PositionIndex.range_from_offsets(index, start0, stop0))
    end

    local function anchor(index, id, kind, label, start0, stop0)
        return S.AnchorSpan(S.AnchorId(id), kind, label, range(index, start0, stop0))
    end

    local function add_dot_head_anchors(out, index, text, keyword, kind)
        local pattern = "%f[%w_]" .. keyword .. "%f[^%w_]%s*%.%s*()([_%a][_%w]*)()"
        local pos = 1
        while true do
            local _, _, s, name, e = text:find(pattern, pos)
            if not s then break end
            out[#out + 1] = anchor(index, keyword .. "." .. name .. "." .. tostring(s), kind, name, s - 1, e - 2)
            pos = e
        end
    end

    local function anchors_for_document(doc, source_ctx)
        local index = PositionIndex.build_index(doc)
        local out = {}
        local seen = {}
        for i = 1, #((source_ctx and source_ctx.anchors) or {}) do
            local a = source_ctx.anchors[i]
            local key = a.id and a.id.text
            if key and not seen[key] then
                seen[key] = true
                out[#out + 1] = a
            end
        end

        local text = doc.text or ""

        add_dot_head_anchors(out, index, text, "unit", S.AnchorModuleName)
        add_dot_head_anchors(out, index, text, "fn", S.AnchorFunctionName)
        add_dot_head_anchors(out, index, text, "export_fn", S.AnchorFunctionName)
        add_dot_head_anchors(out, index, text, "extern", S.AnchorFunctionName)
        add_dot_head_anchors(out, index, text, "struct", S.AnchorStructName)
        add_dot_head_anchors(out, index, text, "union", S.AnchorStructName)
        add_dot_head_anchors(out, index, text, "region", S.AnchorRegionName)
        add_dot_head_anchors(out, index, text, "entry", S.AnchorContinuationName)
        add_dot_head_anchors(out, index, text, "block", S.AnchorContinuationName)

        return S.AnchorSet(out)
    end

    local function parse_document(doc)
        local dsl = require("lalin").dsl
        local source_name = doc.uri and doc.uri.text or "=(lalin.lua)"
        dsl.use()
        local ok, result = pcall(function()
            return dsl.loadstring(doc.text, source_name)()
        end)

        local items, issues = {}, {}
        local source_ctx = nil
        if ok then
            source_ctx = type(result) == "table" and rawget(result, "_source_analysis") or nil
            append_decl_items(items, result)
            items = translate_asdl(items)
        else
            local line = math.max(0, first_number(result) - 1)
            issues[1] = Pm.ParseIssue(tostring(result), 0, line, 0)
        end

        local module = Tr.Module(Tr.ModuleSurface, items)
        local anchors = anchors_for_document(doc, source_ctx)
        local parts = Mlua.DocumentParts(doc, {}, anchors)
        local combined = H.MluaParseResult(H.HostDeclSet({}), module, issues)
        local parse = Mlua.DocumentParse(parts, combined, {}, anchors)
        return parse
    end

    local function analyze(doc, full)
        local parse = parse_document(doc)
        local host = H.MluaHostPipelineResult(parse.combined, H.HostReport({}), H.HostLayoutEnv({}))
        local back_report = B.BackValidationReport({})
        local type_issues = {}

        if full and #parse.combined.issues == 0 then
            local ok, result = pcall(function()
                return Typecheck.check_module(parse.combined.module, { analysis_ctx = {
                    document = doc,
                    anchors = parse.anchors,
                    source_text = doc.text,
                    uri = doc.uri.text,
                } })
            end)
            if ok and result and result.issues then
                type_issues = result.issues
            elseif not ok then
                local line = math.max(0, first_number(result) - 1)
                parse.combined.issues[#parse.combined.issues + 1] = Pm.ParseIssue(tostring(result), 0, line, 0)
            end
        end

        local analysis = Mlua.DocumentAnalysis(parse, host, type_issues, {}, back_report, parse.anchors)
        resolved_cache[analysis] = {}
        return analysis
    end

    return {
        analyze_document_light = function(doc) return analyze(doc, false) end,
        analyze_document_full = function(doc) return analyze(doc, true) end,
    }
end

function M.resolved_issues(analysis)
    return resolved_cache[analysis] or {}
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
