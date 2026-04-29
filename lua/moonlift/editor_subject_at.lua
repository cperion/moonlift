local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local AnchorIndex = require("moonlift.source_anchor_index")
local Diagnostics = require("moonlift.editor_diagnostic_facts")
local BindingFacts = require("moonlift.editor_binding_facts")

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
    local S = T.Moon2Source
    local E = T.Moon2Editor
    local C = T.Moon2Core
    local Ty = T.Moon2Type
    local Tr = T.Moon2Tree
    local H = T.Moon2Host
    local Mlua = T.Moon2Mlua
    local P = PositionIndex.Define(T)
    local AI = AnchorIndex.Define(T)
    local Diag = Diagnostics.Define(T)
    local Bindings = BindingFacts.Define(T)

    local function find_struct(analysis, name)
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclStruct and d.decl.name == name then return d.decl end
        end
        return nil
    end

    local function find_field(analysis, field_name)
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclStruct then
                for j = 1, #d.decl.fields do
                    if d.decl.fields[j].name == field_name then return d.decl, d.decl.fields[j] end
                end
            end
        end
        return nil, nil
    end

    local function find_expose(analysis, name)
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclExpose and d.decl.public_name == name then return d.decl end
        end
        return nil
    end

    local function find_accessor(analysis, label)
        local owner, name = tostring(label):match("^([_%a][_%w]*)%s*:%s*([_%a][_%w]*)$")
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclAccessor then
                local ac = d.decl
                if owner and ac.owner_name == owner and ac.name == name then return ac end
                if ac.name == label then return ac end
            end
        end
        return nil
    end

    local function find_func(analysis, label)
        local normalized = tostring(label):gsub(":", "_")
        for i = 1, #analysis.parse.combined.module.items do
            local item = analysis.parse.combined.module.items[i]
            if item.func then
                local name = item.func.name or (item.func.sym and item.func.sym.name)
                if name == label or name == normalized then return item.func end
            end
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
        local diags = Diag.diagnostics(analysis)
        for i = 1, #diags do
            local d = diags[i]
            if uri_eq(d.range.uri, analysis.parse.parts.document.uri) and range_contains(d.range, offset) then return d end
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
            return pvm.classof(candidate) == E.SubjectContinuation
        end)
        if subject then return subject end
        local island = enclosing_island(analysis, anchor)
        return E.SubjectContinuation(island and island.id or S.AnchorId("document"), Tr.BlockLabel(anchor.label))
    end

    local function subject_for_anchor(analysis, anchor, offset)
        if anchor.kind == S.AnchorStructName then
            local decl = find_struct(analysis, anchor.label)
            if decl then return E.SubjectHostStruct(decl) end
            return E.SubjectType(Ty.TNamed("mlua", anchor.label))
        elseif anchor.kind == S.AnchorFieldName or anchor.kind == S.AnchorFieldUse then
            local owner, field = find_field(analysis, anchor.label)
            if owner and field then return E.SubjectHostField(owner, field) end
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
        elseif anchor.kind == S.AnchorRegionName then
            local frag = find_region_frag(analysis, anchor.label)
            if frag then return E.SubjectRegionFrag(frag) end
        elseif anchor.kind == S.AnchorExprName then
            local frag = find_expr_frag(analysis, anchor.label)
            if frag then return E.SubjectExprFrag(frag) end
        elseif anchor.kind == S.AnchorParamName or anchor.kind == S.AnchorLocalName then
            return fact_subject_for_anchor(analysis, anchor, function(candidate)
                return pvm.classof(candidate) == E.SubjectBinding
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
            local fn = find_func(analysis, anchor.label)
            if fn then return E.SubjectTreeFunc(fn) end
            local binding_subject = fact_subject_for_anchor(analysis, anchor, function(candidate)
                return pvm.classof(candidate) == E.SubjectBinding
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

    local subject_at_phase = pvm.phase("moon2_editor_subject_at", function(query, analysis)
        local index = P.build_index(analysis.parse.parts.document)
        local offset_hit = P.source_pos_to_offset(index, query.pos)
        if pvm.classof(offset_hit) ~= S.SourceOffsetHit then
            return E.SubjectPick(query, {}, E.SubjectMissing(offset_hit.reason))
        end
        local anchor_index = AI.build_index(analysis.anchors)
        local lookup = AI.lookup_by_position(anchor_index, query.uri, offset_hit.offset)
        if #lookup.anchors == 0 then
            return E.SubjectPick(query, {}, E.SubjectMissing("no source anchor"))
        end
        local subject = subject_for_anchor(analysis, lookup.anchors[1], offset_hit.offset)
        return E.SubjectPick(query, lookup.anchors, subject)
    end, { args_cache = "full" })

    local function subject_at(query, analysis)
        return pvm.one(subject_at_phase(query, analysis))
    end

    return {
        subject_at_phase = subject_at_phase,
        subject_at = subject_at,
    }
end

return M
