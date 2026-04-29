local pvm = require("moonlift.pvm")
local Symbols = require("moonlift.editor_symbol_facts")
local BindingScopes = require("moonlift.editor_binding_scope_facts")

local M = {}

local function same_range(a, b)
    return a.uri == b.uri and a.start_offset == b.start_offset and a.stop_offset == b.stop_offset
end

local function find_anchor_for_range(S, anchor_set, range, fallback_kind, label, id_text)
    for i = 1, #anchor_set.anchors do
        local a = anchor_set.anchors[i]
        if same_range(a.range, range) then return a end
    end
    return S.AnchorSpan(S.AnchorId(id_text), fallback_kind, label, range)
end

local function skip_hspace(text, i)
    while i <= #text do
        local c = text:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" then break end
        i = i + 1
    end
    return i
end

local function anchor_is_assignment_target(text, anchor)
    local i = skip_hspace(text, anchor.range.stop_offset + 1)
    return text:sub(i, i) == "=" and text:sub(i + 1, i + 1) ~= "="
end

local function subject_key(pvm, E, subject)
    local cls = pvm.classof(subject)
    if cls == E.SubjectHostStruct then return "host.struct." .. subject.decl.name end
    if cls == E.SubjectHostField then return "host.field." .. subject.owner.name .. "." .. subject.field.name end
    if cls == E.SubjectHostExpose then return "host.expose." .. subject.decl.public_name end
    if cls == E.SubjectHostAccessor then return "host.accessor." .. subject.decl.owner_name .. "." .. subject.decl.name end
    if cls == E.SubjectTreeFunc then return "tree.func." .. subject.func.name end
    if cls == E.SubjectRegionFrag then return "open.region." .. tostring(subject.frag) end
    if cls == E.SubjectExprFrag then return "open.expr." .. tostring(subject.frag) end
    if cls == E.SubjectScalar then return "scalar." .. tostring(subject.scalar) end
    if cls == E.SubjectContinuation then return "control.label." .. subject.scope.text .. "." .. subject.label.name end
    if cls == E.SubjectBinding then return "binding." .. subject.binding.id.text end
    if cls == E.SubjectBuiltin then return "builtin." .. subject.name end
    return nil
end

function M.Define(T)
    local S = T.MoonSource
    local C = T.MoonCore
    local Ty = T.MoonType
    local Tr = T.MoonTree
    local B = T.MoonBind
    local E = T.MoonEditor
    local H = T.MoonHost
    local Mlua = T.MoonMlua
    local Sym = Symbols.Define(T)
    local ScopeFacts = BindingScopes.Define(T)

    local function find_struct(analysis, name)
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclStruct and d.decl.name == name then return d.decl end
        end
        return nil
    end

    local function find_field(analysis, name)
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclStruct then
                for j = 1, #d.decl.fields do
                    if d.decl.fields[j].name == name then return d.decl, d.decl.fields[j] end
                end
            end
        end
        return nil, nil
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

    local scalar_type_names = {
        void = C.ScalarVoid, bool = C.ScalarBool,
        i8 = C.ScalarI8, i16 = C.ScalarI16, i32 = C.ScalarI32, i64 = C.ScalarI64,
        u8 = C.ScalarU8, u16 = C.ScalarU16, u32 = C.ScalarU32, u64 = C.ScalarU64,
        f32 = C.ScalarF32, f64 = C.ScalarF64,
        rawptr = C.ScalarRawPtr, index = C.ScalarIndex,
        bool8 = C.ScalarBool, bool32 = C.ScalarBool,
    }

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

    local function same_island(analysis, a, b)
        local ai, bi = enclosing_island(analysis, a), enclosing_island(analysis, b)
        return ai ~= nil and bi ~= nil and ai.id == bi.id
    end

    local function continuation_fallback_scope(analysis, anchor)
        local island = enclosing_island(analysis, anchor)
        return island and island.id or S.AnchorId("document")
    end

    local function continuation_def_anchors(analysis)
        local out = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorContinuationName then out[#out + 1] = a end
        end
        return out
    end

    local function continuation_def_for_use(analysis, defs, use_anchor)
        local best_before, best_after = nil, nil
        for i = 1, #defs do
            local d = defs[i]
            if d.label == use_anchor.label and same_island(analysis, d, use_anchor) then
                if d.range.start_offset <= use_anchor.range.start_offset then
                    if not best_before or d.range.start_offset > best_before.range.start_offset then best_before = d end
                else
                    if not best_after or d.range.start_offset < best_after.range.start_offset then best_after = d end
                end
            end
        end
        return best_before or best_after
    end

    local function continuation_def_subject(anchor)
        return E.SubjectContinuation(anchor.id, Tr.BlockLabel(anchor.label))
    end

    local function continuation_use_subject(analysis, defs, anchor)
        local def = continuation_def_for_use(analysis, defs, anchor)
        if def then return continuation_def_subject(def) end
        return E.SubjectContinuation(continuation_fallback_scope(analysis, anchor), Tr.BlockLabel(anchor.label))
    end

    local function type_after_anchor(analysis, anchor)
        local text = analysis.parse.parts.document.text
        local tail = text:sub(anchor.range.stop_offset + 1, math.min(#text, anchor.range.stop_offset + 80))
        local name = tail:match("^%s*:%s*([_%a][_%w]*)")
        if name and scalar_type_names[name] then return Ty.TScalar(scalar_type_names[name]) end
        if name then return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) }))) end
        return Ty.TScalar(C.ScalarVoid)
    end

    local function binding_scope_text(analysis, anchor)
        local island = enclosing_island(analysis, anchor)
        return island and island.id.text or "document"
    end

    local function binding_for_def(analysis, anchor, ordinal)
        local entry_label = anchor.id.text:match("cont%.param%.entry%.([_%a][_%w]*)%.")
        local block_label = anchor.id.text:match("cont%.param%.block%.([_%a][_%w]*)%.")
        local class
        if entry_label then
            class = B.BindingClassEntryBlockParam(binding_scope_text(analysis, anchor), entry_label, ordinal or 0)
        elseif block_label then
            class = B.BindingClassBlockParam(binding_scope_text(analysis, anchor), block_label, ordinal or 0)
        elseif anchor.kind == S.AnchorParamName then
            class = B.BindingClassArg(ordinal or 0)
        else
            class = B.BindingClassLocalValue
        end
        return B.Binding(C.Id("editor.binding." .. anchor.id.text), anchor.label, type_after_anchor(analysis, anchor), class)
    end

    local function local_def_anchors(analysis)
        local out = {}
        local ordinal_by_island = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorParamName or a.kind == S.AnchorLocalName then
                local island = enclosing_island(analysis, a)
                local key = island and island.id.text or "document"
                ordinal_by_island[key] = (ordinal_by_island[key] or 0) + 1
                out[#out + 1] = { anchor = a, binding = binding_for_def(analysis, a, ordinal_by_island[key]) }
            end
        end
        return out
    end

    local function local_def_for_use(analysis, defs, use_anchor)
        local best = nil
        for i = 1, #defs do
            local d = defs[i]
            if d.anchor.label == use_anchor.label and same_island(analysis, d.anchor, use_anchor) and d.anchor.range.start_offset <= use_anchor.range.start_offset then
                if not best or d.anchor.range.start_offset > best.anchor.range.start_offset then best = d end
            end
        end
        return best
    end

    local binding_facts_phase = pvm.phase("moon2_editor_binding_facts", {
        [Mlua.DocumentAnalysis] = function(analysis)
        local facts = {}
        local scope_report = ScopeFacts.report(analysis)
        local resolved_by_range = {}
        for i = 1, #scope_report.resolutions do
            local res = scope_report.resolutions[i]
            if pvm.classof(res) == E.BindingResolved then
                local r = res.use.anchor.range
                resolved_by_range[r.uri.text .. ":" .. r.start_offset .. ":" .. r.stop_offset] = res
            end
        end
        local symbols = Sym.symbols(analysis)
        for i = 1, #symbols do
            local sym = symbols[i]
            local anchor = find_anchor_for_range(S, analysis.anchors, sym.selection_range, S.AnchorBindingDef, sym.name, "binding.def." .. sym.id.text)
            local key = subject_key(pvm, E, sym.subject)
            facts[#facts + 1] = E.BindingFact(key and E.SymbolId(key) or sym.id, E.BindingDef, sym.subject, anchor)
        end
        local cont_defs = continuation_def_anchors(analysis)
        for i = 1, #scope_report.bindings do
            local binding = scope_report.bindings[i].binding
            facts[#facts + 1] = E.BindingFact(E.SymbolId("binding." .. binding.id.text), E.BindingDef, E.SubjectBinding(binding), scope_report.bindings[i].anchor)
        end
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorBindingUse then
                local decl = find_struct(analysis, a.label)
                if decl then
                    facts[#facts + 1] = E.BindingFact(E.SymbolId("host.struct." .. decl.name), E.BindingTypeUse, E.SubjectHostStruct(decl), a)
                else
                    local r = a.range
                    local resolved = resolved_by_range[r.uri.text .. ":" .. r.start_offset .. ":" .. r.stop_offset]
                    if resolved then
                        local binding = resolved.binding.binding
                        facts[#facts + 1] = E.BindingFact(E.SymbolId("binding." .. binding.id.text), resolved.use.role, E.SubjectBinding(binding), a)
                    end
                end
            elseif a.kind == S.AnchorScalarType then
                facts[#facts + 1] = E.BindingFact(E.SymbolId("scalar." .. a.label), E.BindingTypeUse, E.SubjectBuiltin(a.label), a)
            elseif a.kind == S.AnchorFieldUse then
                local owner, field = find_field(analysis, a.label)
                if owner and field then
                    local role = anchor_is_assignment_target(analysis.parse.parts.document.text, a) and E.BindingWrite or E.BindingRead
                    facts[#facts + 1] = E.BindingFact(E.SymbolId("host.field." .. owner.name .. "." .. field.name), role, E.SubjectHostField(owner, field), a)
                end
            elseif a.kind == S.AnchorFunctionUse then
                local ac = find_accessor(analysis, a.label)
                if ac then
                    facts[#facts + 1] = E.BindingFact(E.SymbolId("host.accessor." .. ac.owner_name .. "." .. ac.name), E.BindingCall, E.SubjectHostAccessor(ac), a)
                else
                    local region_frag = find_region_frag(analysis, a.label)
                    local expr_frag = find_expr_frag(analysis, a.label)
                    if region_frag then
                        facts[#facts + 1] = E.BindingFact(E.SymbolId(subject_key(pvm, E, E.SubjectRegionFrag(region_frag))), E.BindingCall, E.SubjectRegionFrag(region_frag), a)
                    elseif expr_frag then
                        facts[#facts + 1] = E.BindingFact(E.SymbolId(subject_key(pvm, E, E.SubjectExprFrag(expr_frag))), E.BindingCall, E.SubjectExprFrag(expr_frag), a)
                    else
                        local fn = find_func(analysis, a.label)
                        if fn then
                            local name = fn.name or (fn.sym and fn.sym.name) or a.label
                            facts[#facts + 1] = E.BindingFact(E.SymbolId("tree.func." .. name), E.BindingCall, E.SubjectTreeFunc(fn), a)
                        end
                    end
                end
            elseif a.kind == S.AnchorContinuationName then
                local subject = continuation_def_subject(a)
                facts[#facts + 1] = E.BindingFact(E.SymbolId(subject_key(pvm, E, subject)), E.BindingDef, subject, a)
            elseif a.kind == S.AnchorContinuationUse then
                local subject = continuation_use_subject(analysis, cont_defs, a)
                facts[#facts + 1] = E.BindingFact(E.SymbolId(subject_key(pvm, E, subject)), E.BindingUse, subject, a)
            end
        end
        return pvm.seq(facts)
        end,
    })

    local function facts(analysis)
        return pvm.drain(binding_facts_phase(analysis))
    end

    return {
        binding_facts_phase = binding_facts_phase,
        facts = facts,
        subject_key = function(subject) return subject_key(pvm, E, subject) end,
    }
end

return M
