local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")

local M = {}

local function append_symbol(out, sym)
    out[#out + 1] = sym
end

local function find_anchor(anchor_set, kind, label)
    for i = 1, #anchor_set.anchors do
        local a = anchor_set.anchors[i]
        if (kind == nil or a.kind == kind) and (label == nil or a.label == label) then
            return a
        end
    end
    return nil
end

local function func_name(pvm, Tr, func)
    local cls = pvm.classof(func)
    if cls == Tr.FuncOpen then return func.sym.name end
    return func.name
end

local function type_decl_name(pvm, Tr, decl)
    local cls = pvm.classof(decl)
    if cls == Tr.TypeDeclOpenStruct or cls == Tr.TypeDeclOpenUnion then return decl.sym.name end
    return decl.name
end

local function const_name(pvm, Tr, item)
    local cls = pvm.classof(item)
    if cls == Tr.ConstItemOpen or cls == Tr.StaticItemOpen then return item.sym.name end
    return item.name
end

function M.Define(T)
    local S = (T.MoonSource or T.Moon2Source)
    local E = (T.MoonEditor or T.Moon2Editor)
    local Mlua = (T.MoonMlua or T.Moon2Mlua)
    local H = (T.MoonHost or T.Moon2Host)
    local Tr = (T.MoonTree or T.Moon2Tree)
    local P = PositionIndex.Define(T)
    local ROOT = E.SymbolId("root")

    local function full_range(analysis)
        local index = P.build_index(analysis.parse.parts.document)
        return assert(P.range_from_offsets(index, 0, #analysis.parse.parts.document.text))
    end

    local function range_for(analysis, kind, label)
        local a = find_anchor(analysis.anchors, kind, label) or find_anchor(analysis.anchors, nil, label)
        return a and a.range or full_range(analysis)
    end

    local symbol_facts_phase = pvm.phase("moon2_editor_symbol_facts", {
        [Mlua.DocumentAnalysis] = function(analysis)
            local symbols = {}
            local seen = {}
            local function emit(id_text, parent, name, kind, detail, range, selection, subject)
                if seen[id_text] then return end
                seen[id_text] = true
                append_symbol(symbols, E.SymbolFact(E.SymbolId(id_text), parent or ROOT, name, kind, detail or "", range, selection or range, subject))
            end

            for i = 1, #analysis.anchors.anchors do
                local a = analysis.anchors.anchors[i]
                if a.kind == S.AnchorModuleName then
                    emit("tree.module." .. a.label, ROOT, a.label, E.SymModule, "Moonlift module", a.range, a.range, E.SubjectTreeModule(analysis.parse.combined.module))
                elseif a.kind == S.AnchorContinuationName then
                    emit("control.label." .. a.id.text, ROOT, a.label, E.SymEvent, "control label", a.range, a.range, E.SubjectContinuation(a.id, Tr.BlockLabel(a.label)))
                end
            end

            for i = 1, #analysis.parse.combined.decls.decls do
                local decl = analysis.parse.combined.decls.decls[i]
                local cls = pvm.classof(decl)
                if cls == H.HostDeclStruct then
                    local s = decl.decl
                    local range = range_for(analysis, S.AnchorStructName, s.name)
                    local id = "host.struct." .. s.name
                    emit(id, ROOT, s.name, E.SymStruct, "host struct", range, range, E.SubjectHostStruct(s))
                    for j = 1, #s.fields do
                        local f = s.fields[j]
                        local fr = range_for(analysis, S.AnchorFieldName, f.name)
                        emit(id .. ".field." .. f.name, E.SymbolId(id), f.name, E.SymField, "host field", fr, fr, E.SubjectHostField(s, f))
                    end
                elseif cls == H.HostDeclExpose then
                    local ex = decl.decl
                    local range = range_for(analysis, S.AnchorExposeName, ex.public_name)
                    emit("host.expose." .. ex.public_name, ROOT, ex.public_name, E.SymInterface, "host expose", range, range, E.SubjectHostExpose(ex))
                elseif cls == H.HostDeclAccessor then
                    local ac = decl.decl
                    local owner = ac.owner_name or "host"
                    local name = ac.name or "accessor"
                    local range = range_for(analysis, S.AnchorFunctionName, owner .. ":" .. name)
                    emit("host.accessor." .. owner .. "." .. name, ROOT, owner .. ":" .. name, E.SymMethod, "host accessor", range, range, E.SubjectHostAccessor(ac))
                end
            end

            for i = 1, #analysis.parse.combined.module.items do
                local item = analysis.parse.combined.module.items[i]
                local cls = pvm.classof(item)
                if cls == Tr.ItemFunc then
                    local name = func_name(pvm, Tr, item.func)
                    local range = range_for(analysis, S.AnchorFunctionName, name)
                    local kind = name:find(":", 1, true) and E.SymMethod or E.SymFunction
                    emit("tree.func." .. name, ROOT, name, kind, "Moonlift function", range, range, E.SubjectTreeFunc(item.func))
                elseif cls == Tr.ItemExtern then
                    local name = item.func.name or item.func.sym.name
                    local range = range_for(analysis, S.AnchorFunctionName, name)
                    emit("tree.extern." .. name, ROOT, name, E.SymFunction, "extern function", range, range, E.SubjectTreeModule(analysis.parse.combined.module))
                elseif cls == Tr.ItemConst then
                    local name = const_name(pvm, Tr, item.c)
                    local range = range_for(analysis, nil, name)
                    emit("tree.const." .. name, ROOT, name, E.SymConstant, "const", range, range, E.SubjectTreeModule(analysis.parse.combined.module))
                elseif cls == Tr.ItemStatic then
                    local name = const_name(pvm, Tr, item.s)
                    local range = range_for(analysis, nil, name)
                    emit("tree.static." .. name, ROOT, name, E.SymVariable, "static", range, range, E.SubjectTreeModule(analysis.parse.combined.module))
                elseif cls == Tr.ItemImport then
                    local name = item.imp.path.parts[#item.imp.path.parts].text
                    local range = range_for(analysis, nil, name)
                    emit("tree.import." .. name, ROOT, name, E.SymModule, "import", range, range, E.SubjectTreeModule(analysis.parse.combined.module))
                elseif cls == Tr.ItemType then
                    local name = type_decl_name(pvm, Tr, item.t)
                    local range = range_for(analysis, S.AnchorStructName, name)
                    emit("tree.type." .. name, ROOT, name, E.SymStruct, "type", range, range, E.SubjectTreeModule(analysis.parse.combined.module))
                end
            end

            local region_ordinal = 0
            for i = 1, #analysis.anchors.anchors do
                local a = analysis.anchors.anchors[i]
                if a.kind == S.AnchorRegionName then
                    region_ordinal = region_ordinal + 1
                    local frag = analysis.parse.combined.region_frags[region_ordinal]
                    if frag then emit("open.region." .. tostring(frag), ROOT, a.label, E.SymFunction, "region fragment", a.range, a.range, E.SubjectRegionFrag(frag)) end
                end
            end

            local expr_ordinal = 0
            for i = 1, #analysis.anchors.anchors do
                local a = analysis.anchors.anchors[i]
                if a.kind == S.AnchorExprName then
                    expr_ordinal = expr_ordinal + 1
                    local frag = analysis.parse.combined.expr_frags[expr_ordinal]
                    if frag then emit("open.expr." .. tostring(frag), ROOT, a.label, E.SymFunction, "expr fragment", a.range, a.range, E.SubjectExprFrag(frag)) end
                end
            end

            return pvm.seq(symbols)
        end,
    })

    local function symbols(analysis)
        return pvm.drain(symbol_facts_phase(analysis))
    end

    local function symbol_tree(analysis)
        return E.SymbolTree(symbols(analysis))
    end

    return {
        symbol_facts_phase = symbol_facts_phase,
        symbols = symbols,
        symbol_tree = symbol_tree,
    }
end

return M
