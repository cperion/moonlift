local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local AnchorIndex = require("moonlift.source_anchor_index")

local M = {}

local scalar_labels = {
    ScalarVoid = "void", ScalarBool = "bool",
    ScalarI8 = "i8", ScalarI16 = "i16", ScalarI32 = "i32", ScalarI64 = "i64",
    ScalarU8 = "u8", ScalarU16 = "u16", ScalarU32 = "u32", ScalarU64 = "u64",
    ScalarF32 = "f32", ScalarF64 = "f64",
    ScalarRawPtr = "rawptr", ScalarIndex = "index",
}

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function class_name(node)
    local cls = pvm.classof(node)
    return cls and cls.kind or tostring(node)
end

local function active_parameter_between(text, open_pos, cursor_pos)
    local depth = 0
    local active = 0
    for i = open_pos + 1, cursor_pos do
        local c = text:sub(i, i)
        if c == "(" or c == "[" or c == "{" then
            depth = depth + 1
        elseif c == ")" or c == "]" or c == "}" then
            if depth > 0 then depth = depth - 1 end
        elseif c == "," and depth == 0 then
            active = active + 1
        end
    end
    return active
end

local function find_call_context(text, offset)
    local depth = 0
    local open_pos = nil
    for i = offset, 1, -1 do
        local c = text:sub(i, i)
        if c == ")" then
            depth = depth + 1
        elseif c == "(" then
            if depth == 0 then open_pos = i; break end
            depth = depth - 1
        end
    end
    if not open_pos then return nil, "not inside call" end
    local before = text:sub(1, open_pos - 1)
    local callee = before:match("([_%a][_%w%.:]*)%s*$")
    if not callee or callee == "" then return nil, "missing callee" end
    local active = active_parameter_between(text, open_pos, offset)
    local start0 = open_pos - 1 - #callee
    return { callee = callee, active_parameter = active, start_offset = start0, stop_offset = start0 + #callee }
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local C = T.MoonCore
    local Ty = T.MoonType
    local H = T.MoonHost
    local Tr = T.MoonTree
    local Mlua = T.MoonMlua
    local P = PositionIndex.Define(T)
    local AI = AnchorIndex.Define(T)

    local function scalar_name(scalar)
        for k, v in pairs(C) do
            if v == scalar and scalar_labels[k] then return scalar_labels[k] end
        end
        return tostring(scalar)
    end

    local function type_name(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TScalar then return scalar_name(ty.scalar) end
        if cls == Ty.TPtr then return "ptr(" .. type_name(ty.elem) .. ")" end
        if cls == Ty.TSlice then return "slice(" .. type_name(ty.elem) .. ")" end
        if cls == Ty.TView then return "view(" .. type_name(ty.elem) .. ")" end
        if cls == Ty.TArray then return "array(" .. type_name(ty.elem) .. ")" end
        if cls == Ty.TFunc then return "func(...) -> " .. type_name(ty.result) end
        if cls == Ty.TClosure then return "closure(...) -> " .. type_name(ty.result) end
        if cls == Ty.TNamed then
            local ref = ty.ref
            local rcls = pvm.classof(ref)
            if rcls == Ty.TypeRefGlobal then return ref.type_name end
            if rcls == Ty.TypeRefLocal then return ref.sym.name end
            if rcls == Ty.TypeRefPath then
                local parts = {}
                for i = 1, #ref.path.parts do parts[i] = ref.path.parts[i].text end
                return table.concat(parts, ".")
            end
            return "named"
        end
        if cls == Ty.TSlot then return "slot" end
        return class_name(ty)
    end

    local function func_parts(func)
        local cls = pvm.classof(func)
        if cls == Tr.FuncLocal or cls == Tr.FuncExport or cls == Tr.FuncLocalContract or cls == Tr.FuncExportContract then
            return func.name, func.params, func.result
        elseif cls == Tr.FuncOpen then
            return func.sym.name, func.params, func.result
        end
        return nil, {}, Ty.TScalar(C.ScalarVoid)
    end

    local function make_signature(name, params, result, documentation)
        local ps, labels = {}, {}
        for i = 1, #params do
            local p = params[i]
            local label = p.name .. ": " .. type_name(p.ty)
            labels[i] = label
            ps[i] = E.SignatureParameter(label, "")
        end
        local label = name .. "(" .. table.concat(labels, ", ") .. ") -> " .. type_name(result)
        return E.SignatureInfo(label, documentation or "", ps)
    end

    local function add_func_signature(out, aliases, func, documentation)
        local name, params, result = func_parts(func)
        if not name then return end
        local sig = make_signature(name, params, result, documentation or "Moonlift function")
        out[name] = out[name] or {}; out[name][#out[name] + 1] = sig
        if aliases then
            for i = 1, #aliases do
                out[aliases[i]] = out[aliases[i]] or {}; out[aliases[i]][#out[aliases[i]] + 1] = sig
            end
        end
    end

    local function find_struct(analysis, name)
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclStruct and d.decl.name == name then return d.decl end
        end
        return nil
    end

    local function find_field(owner, name)
        if not owner then return nil end
        for i = 1, #owner.fields do if owner.fields[i].name == name then return owner.fields[i] end end
        return nil
    end

    local function fragment_names(analysis, kind)
        local out = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == kind then out[#out + 1] = a.label end
        end
        return out
    end

    local function signature_from_params(name, params, result, documentation)
        return make_signature(name, params, result, documentation)
    end

    local function region_signature(name, params)
        local labels, ps = {}, {}
        for i = 1, #params do
            local label = params[i].name .. ": " .. type_name(params[i].ty)
            labels[i] = label
            ps[i] = E.SignatureParameter(label, "")
        end
        return E.SignatureInfo(name .. "(" .. table.concat(labels, ", ") .. ") -> region", "Moonlift region fragment", ps)
    end

    local function signature_catalog(analysis)
        local catalog = {}
        for i = 1, #analysis.parse.combined.module.items do
            local item = analysis.parse.combined.module.items[i]
            if pvm.classof(item) == Tr.ItemFunc then
                add_func_signature(catalog, nil, item.func, "Moonlift function")
            elseif pvm.classof(item) == Tr.ItemExtern then
                local f = item.func
                local name = f.name or (f.sym and f.sym.name) or "extern"
                local params = f.params or {}
                local result = f.result or Ty.TScalar(C.ScalarVoid)
                local sig = signature_from_params(name, params, result, "extern function")
                catalog[name] = catalog[name] or {}; catalog[name][#catalog[name] + 1] = sig
            end
        end
        local expr_names = fragment_names(analysis, S.AnchorExprName)
        for i = 1, #analysis.parse.combined.expr_frags do
            local name = expr_names[i] or ("expr" .. tostring(i))
            local frag = analysis.parse.combined.expr_frags[i]
            catalog[name] = catalog[name] or {}
            catalog[name][#catalog[name] + 1] = signature_from_params(name, frag.params, frag.result, "Moonlift expr fragment")
        end
        local region_names = fragment_names(analysis, S.AnchorRegionName)
        for i = 1, #analysis.parse.combined.region_frags do
            local name = region_names[i] or ("region" .. tostring(i))
            local frag = analysis.parse.combined.region_frags[i]
            catalog[name] = catalog[name] or {}
            catalog[name][#catalog[name] + 1] = region_signature(name, frag.params)
        end
        for i = 1, #analysis.parse.combined.decls.decls do
            local d = analysis.parse.combined.decls.decls[i]
            if pvm.classof(d) == H.HostDeclAccessor then
                local ac = d.decl
                local name = ac.owner_name .. ":" .. ac.name
                local aliases = { ac.name, ac.owner_name .. "." .. ac.name }
                local cls = pvm.classof(ac)
                if cls == H.HostAccessorMoonlift then
                    add_func_signature(catalog, aliases, ac.func, "Moonlift host accessor")
                    if catalog[ac.func.name] then catalog[name] = catalog[ac.func.name] end
                elseif cls == H.HostAccessorField then
                    local owner = find_struct(analysis, ac.owner_name)
                    local field = find_field(owner, ac.field_name)
                    local result = field and field.expose_ty or Ty.TScalar(C.ScalarVoid)
                    local params = { Ty.Param("self", Ty.TPtr(Ty.TNamed(Ty.TypeRefGlobal("mlua", ac.owner_name)))) }
                    local sig = make_signature(name, params, result, "host field accessor")
                    catalog[name] = catalog[name] or {}; catalog[name][#catalog[name] + 1] = sig
                    for j = 1, #aliases do catalog[aliases[j]] = catalog[aliases[j]] or {}; catalog[aliases[j]][#catalog[aliases[j]] + 1] = sig end
                else
                    local sig = E.SignatureInfo(name .. "(self, ...)", "Lua host accessor", { E.SignatureParameter("self", "host receiver") })
                    catalog[name] = catalog[name] or {}; catalog[name][#catalog[name] + 1] = sig
                    for j = 1, #aliases do catalog[aliases[j]] = catalog[aliases[j]] or {}; catalog[aliases[j]][#catalog[aliases[j]] + 1] = sig end
                end
            end
        end
        catalog["moonlift.json.decode"] = { E.SignatureInfo("moonlift.json.decode(src, opts)", "Decode JSON bytes through the Moonlift indexed-tape JSON library.", { E.SignatureParameter("src", "JSON source bytes"), E.SignatureParameter("opts", "decoder options") }) }
        catalog["moonlift.json.get_i32"] = { E.SignatureInfo("moonlift.json.get_i32(src, key, opts)", "Read an i32 field from a decoded JSON document.", { E.SignatureParameter("src", "JSON source bytes"), E.SignatureParameter("key", "raw object key"), E.SignatureParameter("opts", "decoder options") }) }
        catalog["moonlift.json.get_bool"] = { E.SignatureInfo("moonlift.json.get_bool(src, key, opts)", "Read a bool field from a decoded JSON document.", { E.SignatureParameter("src", "JSON source bytes"), E.SignatureParameter("key", "raw object key"), E.SignatureParameter("opts", "decoder options") }) }
        return catalog
    end

    local signature_context_phase = pvm.phase("moon2_editor_signature_context", {
        [E.PositionQuery] = function(query, analysis)
            local doc = analysis.parse.parts.document
            local index = P.build_index(doc)
            local hit = P.source_pos_to_offset(index, query.pos)
            if pvm.classof(hit) ~= S.SourceOffsetHit then return pvm.once(E.SignatureNoCall(hit.reason)) end
            local offset = hit.offset
            local context, reason = find_call_context(doc.text, offset)
            if not context then return pvm.once(E.SignatureNoCall(reason)) end
            local anchor_index = AI.build_index(analysis.anchors)
            local lookup = AI.lookup_by_position(anchor_index, query.uri, offset)
            local in_hosted_source = false
            for i = 1, #lookup.anchors do
                if lookup.anchors[i].kind == S.AnchorHostedIsland or lookup.anchors[i].kind == S.AnchorIslandBody or lookup.anchors[i].kind == S.AnchorBuiltinName then
                    in_hosted_source = true
                    break
                end
            end
            if not in_hosted_source and not context.callee:match("^moonlift%.") then
                return pvm.once(E.SignatureNoCall("not in Moonlift or builtin call context"))
            end
            local r = assert(P.range_from_offsets(index, context.start_offset, context.stop_offset))
            return pvm.once(E.SignatureCall(context.callee, context.active_parameter, r))
        end,
    }, { args_cache = "full" })

    local signature_help_phase = pvm.phase("moon2_editor_signature_help", {
        [E.PositionQuery] = function(query, analysis)
            local context = pvm.one(signature_context_phase(query, analysis))
            if pvm.classof(context) ~= E.SignatureCall then return pvm.once(E.SignatureHelpMissing(context.reason)) end
            local catalog = signature_catalog(analysis)
            local signatures = catalog[context.callee]
            if (not signatures or #signatures == 0) and context.callee:find(":", 1, true) then
                signatures = catalog[context.callee:gsub("^.-:", "")]
            end
            if not signatures or #signatures == 0 then return pvm.once(E.SignatureHelpMissing("unknown callee: " .. context.callee)) end
            return pvm.once(E.SignatureHelp(signatures, 0, context.active_parameter))
        end,
    }, { args_cache = "full" })

    local function context(query, analysis)
        return pvm.one(signature_context_phase(query, analysis))
    end

    local function help(query, analysis)
        return pvm.one(signature_help_phase(query, analysis))
    end

    return {
        signature_context_phase = signature_context_phase,
        signature_help_phase = signature_help_phase,
        context = context,
        help = help,
    }
end

return M
