local schema = require("moonlift.schema_runtime")
local PositionIndex = require("moonlift.source_position_index")
local AnchorIndex = require("moonlift.source_anchor_index")
local BindingFacts = require("moonlift.editor_binding_facts")
local AnalysisStore = require("moonlift.mlua_document_analysis")

local M = {}

local scalar_names = {
    void = "ScalarVoid",
    bool = "ScalarBool",
    i8 = "ScalarI8", i16 = "ScalarI16", i32 = "ScalarI32", i64 = "ScalarI64",
    u8 = "ScalarU8", u16 = "ScalarU16", u32 = "ScalarU32", u64 = "ScalarU64",
    f32 = "ScalarF32", f64 = "ScalarF64",
    rawptr = "ScalarRawPtr", ptr = "ScalarRawPtr",
    index = "ScalarIndex",
}

local function range_contains(range, offset)
    return offset >= range.start_offset and offset <= range.stop_offset
end

local function uri_eq(a, b)
    return a == b or (a and b and a.text == b.text)
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local C = T.MoonCore
    local Ty = T.MoonType
    local Tr = T.MoonTree
    local H = T.MoonHost
    local Mlua = T.MoonMlua
    local P = PositionIndex.Define(T)
    local AI = AnchorIndex.Define(T)
    local Bindings = BindingFacts.Define(T)

    local function find_struct(analysis, name)
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if schema.classof(d) == H.HostDeclStruct and d.decl.name == name then return d.decl end
        end
        return nil
    end

    local function find_field(analysis, field_name)
        local owner, field = nil, nil
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if schema.classof(d) == H.HostDeclStruct then
                for j = 1, #d.decl.fields do
                    if d.decl.fields[j].name == field_name then
                        if field then return nil, nil end
                        owner, field = d.decl, d.decl.fields[j]
                    end
                end
            end
        end
        return owner, field
    end

    local function find_expose(analysis, name)
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if schema.classof(d) == H.HostDeclExpose and d.decl.public_name == name then return d.decl end
        end
        return nil
    end

    local function find_accessor(analysis, label)
        local owner, name = tostring(label):match("^([_%a][_%w]*)%s*:%s*([_%a][_%w]*)$")
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if schema.classof(d) == H.HostDeclAccessor then
                local ac = d.decl
                if owner and ac.owner_name == owner and ac.name == name then return ac end
                if ac.name == label then return ac end
            end
        end
        return nil
    end

    local function find_tree_type(analysis, label)
        for i = 1, #analysis.parse.combined.module.items do
            local item = analysis.parse.combined.module.items[i]
            if schema.classof(item) == Tr.ItemType and item.t and item.t.name == label then return item.t end
        end
        return nil
    end

    local function find_func(analysis, label)
        local normalized = tostring(label):gsub(":", "_")
        local function scan_module(module)
            for i = 1, #(module and module.items or {}) do
                local item = module.items[i]
                if schema.classof(item) == Tr.ItemFunc then
                    local name = schema.classof(item.func) == Tr.FuncOpen and item.func.sym.name or item.func.name
                    if name == label or name == normalized then return item.func end
                end
            end
            return nil
        end
        local found = scan_module(analysis.parse.combined.module)
        if found then return found end
        for i = 1, #(analysis.parse.islands or {}) do
            found = scan_module(analysis.parse.islands[i].module)
            if found then return found end
        end
        return nil
    end

    local function find_extern(analysis, label)
        local normalized = tostring(label):gsub(":", "_")
        local function scan_module(module)
            for i = 1, #(module and module.items or {}) do
                local item = module.items[i]
                if schema.classof(item) == Tr.ItemExtern then
                    local name = schema.classof(item.func) == Tr.ExternFuncOpen and item.func.sym.name or item.func.name
                    if name == label or name == normalized then return item.func end
                end
            end
            return nil
        end
        local found = scan_module(analysis.parse.combined.module)
        if found then return found end
        for i = 1, #(analysis.parse.islands or {}) do
            found = scan_module(analysis.parse.islands[i].module)
            if found then return found end
        end
        return nil
    end

    local function fragment_for_label(analysis, anchor_kind, fragments, label)
        local ordinal = 0
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == anchor_kind then
                ordinal = ordinal + 1
                if a.label == label then return fragments[ordinal] end
            end
        end
        return nil
    end

    local function find_region_frag(analysis, label)
        return fragment_for_label(analysis, S.AnchorRegionName, analysis.parse.combined.region_frags, label)
    end

    local function find_expr_frag(analysis, label)
        return fragment_for_label(analysis, S.AnchorExprName, analysis.parse.combined.expr_frags, label)
    end

    local function diagnostic_at(analysis, offset)
        local resolved = AnalysisStore.resolved_issues(analysis)
        local doc = analysis.parse.parts.document
        local pos_index = P.build_index(doc)
        for i = 1, #resolved do
            local ri = resolved[i]
            if ri.span then
                local proxy = {
                    start_offset = ri.span.start_offset or 0,
                    stop_offset = ri.span.end_offset or ri.span.start_offset or 0,
                }
                if range_contains(proxy, offset) then
                    local start_hit = P.offset_to_pos(pos_index, proxy.start_offset)
                    local stop_hit = P.offset_to_pos(pos_index, proxy.stop_offset)
                    local range = S.SourceRange(doc.uri, proxy.start_offset, proxy.stop_offset, start_hit.pos, stop_hit.pos)
                    local origin = E.DiagFromTransport(ri.code or "E", tostring(ri.issue))
                    local icls = schema.classof(ri.issue)
                    if icls then
                        if tostring(icls.kind or ""):match("^TypeIssue") then origin = E.DiagFromType(ri.issue) end
                    end
                    local message = tostring(ri.issue)
                    local ok, report = pcall(function()
                        local Catalog = require("moonlift.error.catalog")
                        local ctx = {}
                        for k, v in pairs(ri.analysis_ctx or {}) do ctx[k] = v end
                        ctx.resolved_span = ri.span
                        return Catalog.build_report(ri.code or "E9999", ri.issue, ri.phase or "typecheck", ctx)
                    end)
                    if ok and report and report.primary and report.primary.message then message = report.primary.message end
                    if icls and icls.kind == "TypeIssueUnresolvedValue" then message = "unresolved binding `" .. tostring(ri.issue.name or "?") .. "`" end
                    return E.DiagnosticFact(E.DiagnosticError, origin, ri.code or "E", message, range, {})
                end
            end
        end
        return nil
    end

    local function fact_subject_for_anchor(analysis, anchor, accept)
        local facts = Bindings.facts(analysis)
        for i = 1, #facts do
            local r = facts[i].anchor.range
            if r.uri == anchor.range.uri and r.start_offset == anchor.range.start_offset and r.stop_offset == anchor.range.stop_offset then
                local subject = facts[i].subject
                if accept == nil or accept(subject) then return subject end
            end
        end
        return nil
    end

    local function enclosing_island(analysis, anchor)
        local best = nil
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorHostedIsland and a.range.uri == anchor.range.uri and anchor.range.start_offset >= a.range.start_offset and anchor.range.stop_offset <= a.range.stop_offset then
                if not best or (a.range.stop_offset - a.range.start_offset) < (best.range.stop_offset - best.range.start_offset) then best = a end
            end
        end
        return best
    end

    local function continuation_subject_for_anchor(analysis, anchor)
        local subject = fact_subject_for_anchor(analysis, anchor, function(candidate)
            return schema.classof(candidate) == E.SubjectContinuation
        end)
        if subject then return subject end
        local island = enclosing_island(analysis, anchor)
        return E.SubjectContinuation(island and island.id or S.AnchorId("document"), Tr.BlockLabel(anchor.label))
    end

    local function subject_for_anchor(analysis, anchor, offset)
        if anchor.kind == S.AnchorStructName then
            local decl = find_struct(analysis, anchor.label)
            if decl then return E.SubjectHostStruct(decl) end
            local tree_type = find_tree_type(analysis, anchor.label)
            if tree_type and schema.classof(tree_type) == Tr.TypeDeclHandle then return E.SubjectType(Ty.THandle(Ty.TypeRefPath(C.Path({ C.Name(tree_type.name) })), tree_type.repr)) end
            return E.SubjectType(Ty.TNamed(Ty.TypeRefGlobal("mlua", anchor.label)))
        elseif anchor.kind == S.AnchorFieldName then
            local exact = fact_subject_for_anchor(analysis, anchor, function(candidate)
                return schema.classof(candidate) == E.SubjectHostField
            end)
            if exact then return exact end
            local owner, field = find_field(analysis, anchor.label)
            if owner and field then return E.SubjectHostField(owner, field) end
        elseif anchor.kind == S.AnchorFieldUse then
            local owner, field = find_field(analysis, anchor.label)
            if owner and field then return E.SubjectHostField(owner, field) end
            local decl = find_struct(analysis, anchor.label)
            if decl then return E.SubjectHostStruct(decl) end
            local tree_type = find_tree_type(analysis, anchor.label)
            if tree_type and schema.classof(tree_type) == Tr.TypeDeclHandle then return E.SubjectType(Ty.THandle(Ty.TypeRefPath(C.Path({ C.Name(tree_type.name) })), tree_type.repr)) end
        elseif anchor.kind == S.AnchorExposeName then
            local ex = find_expose(analysis, anchor.label)
            if ex then return E.SubjectHostExpose(ex) end
        elseif anchor.kind == S.AnchorModuleName then
            return E.SubjectTreeModule(analysis.parse.combined.module)
        elseif anchor.kind == S.AnchorFunctionName or anchor.kind == S.AnchorMethodName or anchor.kind == S.AnchorFunctionUse then
            local ac = find_accessor(analysis, anchor.label)
            if ac then return E.SubjectHostAccessor(ac) end
            local region_frag = find_region_frag(analysis, anchor.label)
            if region_frag then return E.SubjectRegionFrag(region_frag) end
            local expr_frag = find_expr_frag(analysis, anchor.label)
            if expr_frag then return E.SubjectExprFrag(expr_frag) end
            local fn = find_func(analysis, anchor.label)
            if fn then return E.SubjectTreeFunc(fn) end
            local ex = find_extern(analysis, anchor.label)
            if ex then return E.SubjectTreeExtern(ex) end
            if anchor.kind == S.AnchorMethodName or anchor.kind == S.AnchorFunctionName then
                return E.SubjectBuiltin("function " .. anchor.label)
            end
            return E.SubjectMissing("unresolved function " .. anchor.label)
        elseif anchor.kind == S.AnchorRegionName then
            local frag = find_region_frag(analysis, anchor.label)
            if frag then return E.SubjectRegionFrag(frag) end
        elseif anchor.kind == S.AnchorExprName then
            local frag = find_expr_frag(analysis, anchor.label)
            if frag then return E.SubjectExprFrag(frag) end
        elseif anchor.kind == S.AnchorParamName or anchor.kind == S.AnchorLocalName then
            return fact_subject_for_anchor(analysis, anchor, function(candidate)
                return schema.classof(candidate) == E.SubjectBinding
            end) or E.SubjectMissing("binding fact missing for " .. anchor.label)
        elseif anchor.kind == S.AnchorScalarType then
            local cname = scalar_names[anchor.label]
            if cname then return E.SubjectScalar(C[cname]) end
            return E.SubjectBuiltin(anchor.label)
        elseif anchor.kind == S.AnchorBindingUse then
            local cname = scalar_names[anchor.label]
            if cname then return E.SubjectScalar(C[cname]) end
            local decl = find_struct(analysis, anchor.label)
            if decl then return E.SubjectHostStruct(decl) end
            local tree_type = find_tree_type(analysis, anchor.label)
            if tree_type and schema.classof(tree_type) == Tr.TypeDeclHandle then return E.SubjectType(Ty.THandle(Ty.TypeRefPath(C.Path({ C.Name(tree_type.name) })), tree_type.repr)) end
            local fn = find_func(analysis, anchor.label)
            if fn then return E.SubjectTreeFunc(fn) end
            local ex = find_extern(analysis, anchor.label)
            if ex then return E.SubjectTreeExtern(ex) end
            local binding_subject = fact_subject_for_anchor(analysis, anchor, function(candidate)
                return schema.classof(candidate) == E.SubjectBinding
            end)
            if binding_subject then return binding_subject end
            local d = diagnostic_at(analysis, offset)
            if d then return E.SubjectDiagnostic(d) end
            return E.SubjectMissing("unresolved binding " .. anchor.label)
        elseif anchor.kind == S.AnchorKeyword then
            return E.SubjectKeyword(anchor.label)
        elseif anchor.kind == S.AnchorDiagnostic then
            local d = diagnostic_at(analysis, offset)
            if d then return E.SubjectDiagnostic(d) end
            return E.SubjectKeyword(anchor.label)
        elseif anchor.kind == S.AnchorBuiltinName then
            return E.SubjectBuiltin(anchor.label)
        elseif anchor.kind == S.AnchorContinuationName or anchor.kind == S.AnchorContinuationUse then
            return continuation_subject_for_anchor(analysis, anchor)
        end
        return E.SubjectMissing("no semantic subject for anchor " .. anchor.label)
    end

    local function subject_at_phase(query, analysis)
        local index = P.build_index(analysis.parse.parts.document)
        local offset_hit = P.source_pos_to_offset(index, query.pos)
        if schema.classof(offset_hit) ~= S.SourceOffsetHit then
            return E.SubjectPick(query, {}, E.SubjectMissing(offset_hit.reason))
        end
        local anchor_index = AI.build_index(analysis.anchors)
        local lookup = AI.lookup_by_position(anchor_index, query.uri, offset_hit.offset)
        if #lookup.anchors == 0 then
            return E.SubjectPick(query, {}, E.SubjectMissing("no source anchor"))
        end
        local subject = subject_for_anchor(analysis, lookup.anchors[1], offset_hit.offset)
        return E.SubjectPick(query, lookup.anchors, subject)
    end

    local function subject_at(query, analysis)
        return subject_at_phase(query, analysis)
    end

    return {
        subject_at_phase = subject_at_phase,
        subject_at = subject_at,
    }
end

return M
