local schema = require("lalin.schema_runtime")
local llb = require("llb")
local SubjectAt = require("lalin.editor_subject_at")
local Format = require("lalin.error.format")

local function scalar_name(C, scalar)
    return Format.scalar_name(scalar)
end

local function storage_text(pvm, H, storage)
    if storage == H.HostStorageSame then return "same" end
    local cls = schema.classof(storage)
    if cls == H.HostStorageScalar then return Format.scalar_name(storage.scalar) end
    if cls == H.HostStorageBool then return "bool stored as " .. Format.scalar_name(storage.scalar) end
    if cls == H.HostStoragePtr then return "ptr" end
    if cls == H.HostStorageSlice then return "slice" end
    if cls == H.HostStorageView then return "view" end
    if cls == H.HostStorageOpaque then return storage.name end
    return tostring(storage)
end

local function find_layout(H, analysis, name)
    for i = 1, #analysis.host.layout_env.layouts do
        local layout = analysis.host.layout_env.layouts[i]
        if layout.name == name then return layout end
    end
    return nil
end

local function find_field_layout(layout, name)
    if not layout then return nil end
    for i = 1, #layout.fields do
        if layout.fields[i].name == name then return layout.fields[i] end
    end
    return nil
end

local function type_ref_name(pvm, ref)
    local cls = schema.classof(ref)
    if not cls then return tostring(ref) end
    if cls.kind == "TypeRefGlobal" then return ref.type_name end
    if cls.kind == "TypeRefLocal" then return ref.sym and ref.sym.name or tostring(ref.sym) end
    if cls.kind == "TypeRefPath" and ref.path then
        local parts = {}
        for i = 1, #(ref.path.parts or {}) do parts[i] = ref.path.parts[i].text end
        return table.concat(parts, ".")
    end
    if cls.kind == "TypeRefSlot" then return ref.slot.pretty_name end
    return cls.kind
end

local function handle_repr(pvm, Ty, repr)
    if schema.classof(repr) == Ty.HandleReprScalar then return Format.scalar_name(repr.scalar) end
    return tostring(repr)
end

local function handle_invalid(pvm, Ty, invalid)
    local cls = schema.classof(invalid)
    if cls == Ty.HandleInvalidInt then return invalid.raw end
    if cls == Ty.HandleInvalidNone then return "none" end
    return tostring(invalid)
end

local function type_decl_for_handle(analysis, Tr, name)
    for i = 1, #(analysis.parse.combined.module.items or {}) do
        local item = analysis.parse.combined.module.items[i]
        if schema.classof(item) == Tr.ItemType and item.t and schema.classof(item.t) == Tr.TypeDeclHandle and item.t.name == name then
            return item.t
        end
    end
    return nil
end

local function params_text(params)
    local out = {}
    for i = 1, #(params or {}) do out[i] = params[i].name .. ": " .. Format.type_name(params[i].ty) end
    return table.concat(out, ", ")
end

local function open_params_text(params)
    local out = {}
    for i = 1, #(params or {}) do out[i] = params[i].name .. ": " .. Format.type_name(params[i].ty) end
    return table.concat(out, ", ")
end

local function cont_text(cont)
    return cont.pretty_name .. "(" .. params_text(cont.params) .. ")"
end

local function name_ref_text(pvm, O, ref)
    local cls = schema.classof(ref)
    if cls == O.NameRefText then return ref.text end
    if cls == O.NameRefSlot then return ref.slot.pretty_name end
    return tostring(ref)
end

local function func_name_and_parts(pvm, Tr, Ty, C, func)
    local cls = schema.classof(func)
    if cls == Tr.FuncLocal or cls == Tr.FuncExport or cls == Tr.FuncLocalContract or cls == Tr.FuncExportContract then
        return func.name, func.params, func.result
    elseif cls == Tr.FuncDecl then
        return func.name, func.params, func.result
    elseif cls == Tr.FuncOpen then
        return func.sym.name, func.params, func.result
    end
    return "function", {}, Ty.TScalar(C.ScalarVoid)
end

local function extern_name_and_parts(pvm, Tr, Ty, C, func)
    local cls = schema.classof(func)
    if cls == Tr.ExternFunc then return func.name, func.symbol, func.params, func.result end
    if cls == Tr.ExternFuncOpen then return func.sym.name, func.sym.symbol, func.params, func.result end
    return "extern", "extern", {}, Ty.TScalar(C.ScalarVoid)
end

local function binding_class_text(pvm, binding)
    local cls = binding and binding.class and schema.classof(binding.class)
    if not cls then return "binding" end
    return ({
        BindingClassArg = "function parameter",
        BindingClassLocalValue = "local value",
        BindingClassLocalCell = "local cell",
        BindingClassBlockParam = "block parameter",
        BindingClassEntryBlockParam = "entry parameter",
    })[cls.kind] or cls.kind
end

local function md(lines)
    return table.concat(lines, "\n")
end

local function hover_doc(signature, details)
    local lines = { "```lalin", signature, "```" }
    if details and #details > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "---"
        lines[#lines + 1] = ""
        for i = 1, #details do lines[#lines + 1] = details[i] end
    end
    return md(lines)
end

local function pad_right(s, width)
    s = tostring(s or "")
    if #s >= width then return s end
    return s .. string.rep(" ", width - #s)
end

local function host_struct_details(pvm, H, decl, layout)
    local details = { "**Host Struct**", "" }
    details[#details + 1] = "- Fields: `" .. tostring(#decl.fields) .. "`"
    if layout then
        details[#details + 1] = "- Layout: size `" .. tostring(layout.size) .. "`, align `" .. tostring(layout.align) .. "`, repr `" .. tostring(decl.repr) .. "`"
    else
        details[#details + 1] = "- Layout: unavailable"
    end
    details[#details + 1] = ""
    local rows = {}
    local field_w, type_w = #"field", #"type"
    for i = 1, #decl.fields do
        local f = decl.fields[i]
        local fl = find_field_layout(layout, f.name)
        local row = {
            field = f.name,
            ty = Format.type_name(f.expose_ty),
            storage = storage_text(pvm, H, f.storage),
            layout = fl and ("offset " .. tostring(fl.offset) .. ", size " .. tostring(fl.size)) or "",
        }
        rows[#rows + 1] = row
        if #row.field > field_w then field_w = #row.field end
        if #row.ty > type_w then type_w = #row.ty end
    end
    details[#details + 1] = "```lalin"
    for i = 1, #rows do
        local row = rows[i]
        local layout_comment = row.layout ~= "" and (" -- " .. row.layout) or ""
        details[#details + 1] = pad_right(row.field .. ":", field_w + 1) .. " " .. pad_right(row.ty, type_w) .. layout_comment
    end
    details[#details + 1] = "```"
    return details
end

local function bind_context(T)
    local E = T.LalinEditor
    local C = T.LalinCore
    local Ty = T.LalinType
    local Tr = T.LalinTree
    local O = T.LalinOpen
    local H = T.LalinHost
    local Subject = SubjectAt(T)

    local function comment_context_for_pick(pick, analysis)
        if not pick or not pick.anchors or #pick.anchors == 0 then return nil end
        local anchor = pick.anchors[1]
        if not anchor.range or not anchor.range.start then return nil end
        local doc = analysis.parse.parts.document
        local source_name = doc.uri and doc.uri.text or "=(lalin.lua)"
        llb.source.register(source_name, doc.text or "")
        return llb.source.leading_comment {
            source = source_name,
            file = source_name,
            line = anchor.range.start.line + 1,
        }
    end

    local function details_with_comment(details, context)
        if not context or context == "" then return details end
        local out = { "**Documentation**", "", context, "" }
        for i = 1, #(details or {}) do out[#out + 1] = details[i] end
        return out
    end

    local function hover_from_pick_phase(pick, analysis)
        local subject = pick.subject
        local range = (#pick.anchors > 0 and pick.anchors[1].range) or analysis.anchors.anchors[1].range
        local cls = schema.classof(subject)
        local comment_context = comment_context_for_pick(pick, analysis)
        local function doc(signature, details)
            return hover_doc(signature, details_with_comment(details, comment_context))
        end
        if cls == E.SubjectScalar then
            return E.HoverInfo(E.MarkupMarkdown, doc(scalar_name(C, subject.scalar), { "scalar value type" }), range)
        elseif cls == E.SubjectType then
            local ty = subject.ty
            local details = {}
            if schema.classof(ty) == Ty.THandle then
                local handle_name = type_ref_name(pvm, ty.ref)
                local decl = type_decl_for_handle(analysis, Tr, handle_name)
                details[#details + 1] = "- handle: durable copyable identity"
                details[#details + 1] = "- repr: " .. handle_repr(pvm, Ty, ty.repr)
                if decl then
                    details[#details + 1] = "- invalid: " .. handle_invalid(pvm, Ty, decl.invalid)
                    for i = 1, #(decl.facts or {}) do
                        local fact = decl.facts[i]
                        local fcls = schema.classof(fact)
                        if fcls == Ty.HandleDomain then details[#details + 1] = "- domain: " .. type_ref_name(pvm, fact.domain) end
                        if fcls == Ty.HandleTarget then details[#details + 1] = "- target: " .. type_ref_name(pvm, fact.target) end
                    end
                end
                details[#details + 1] = "- access: resolve through a store region to obtain a lease"
            elseif schema.classof(ty) == Ty.TOwned then
                details[#details + 1] = "- owned authority: must be discharged or transferred exactly once"
            elseif schema.classof(ty) == Ty.TLease then
                details[#details + 1] = "- lease: temporary no-escape access fact"
            end
            return E.HoverInfo(E.MarkupMarkdown, doc(Format.type_name(ty), details), range)
        elseif cls == E.SubjectHostStruct then
            local decl = subject.decl
            local layout = find_layout(H, analysis, decl.name)
            return E.HoverInfo(E.MarkupMarkdown, doc("struct " .. decl.name, host_struct_details(pvm, H, decl, layout)), range)
        elseif cls == E.SubjectHostField then
            local owner, field = subject.owner, subject.field
            local layout = find_layout(H, analysis, owner.name)
            local fl = find_field_layout(layout, field.name)
            local details = { "- host field", "- storage: " .. storage_text(pvm, H, field.storage) }
            if fl then details[#details + 1] = "- layout: offset " .. fl.offset .. ", size " .. fl.size .. ", align " .. fl.align end
            return E.HoverInfo(E.MarkupMarkdown, doc(owner.name .. "." .. field.name .. ": " .. Format.type_name(field.expose_ty), details), range)
        elseif cls == E.SubjectHostExpose then
            local ex = subject.decl
            return E.HoverInfo(E.MarkupMarkdown, doc("expose " .. ex.public_name, { "- host expose", "- boundary exposure", "- facets: " .. tostring(#ex.facets), "- subject: " .. tostring(schema.classof(ex.subject) and schema.classof(ex.subject).kind or ex.subject) }), range)
        elseif cls == E.SubjectHostAccessor then
            local ac = subject.decl
            return E.HoverInfo(E.MarkupMarkdown, doc(ac.owner_name .. ":" .. ac.name, { "- host accessor" }), range)
        elseif cls == E.SubjectTreeFunc then
            local f = subject.func
            local name, params, result = func_name_and_parts(pvm, Tr, Ty, C, f)
            return E.HoverInfo(E.MarkupMarkdown, doc("func " .. name .. "(" .. params_text(params) .. "): " .. Format.type_name(result), { "- params: " .. tostring(#params), "- boundary: sealed function call" }), range)
        elseif cls == E.SubjectTreeExtern then
            local f = subject.func
            local name, symbol, params, result = extern_name_and_parts(pvm, Tr, Ty, C, f)
            return E.HoverInfo(E.MarkupMarkdown, doc("extern " .. name .. "(" .. params_text(params) .. "): " .. Format.type_name(result), { "- params: " .. tostring(#params), "- symbol: " .. tostring(symbol), "- boundary: imported C/host function" }), range)
        elseif cls == E.SubjectRegionFrag then
            local frag = subject.frag
            local conts = {}
            for i = 1, #(frag.conts or {}) do conts[#conts + 1] = cont_text(frag.conts[i]) end
            return E.HoverInfo(E.MarkupMarkdown, doc("region " .. name_ref_text(pvm, O, frag.name) .. "(" .. open_params_text(frag.params) .. ")", { "- region fragment", "- runtime params: " .. tostring(#frag.params), "- exits: " .. (#conts > 0 and table.concat(conts, " | ") or "none"), "- composition: emit splices CFG; call seals through a result boundary" }), range)
        elseif cls == E.SubjectExprFrag then
            local frag = subject.frag
            return E.HoverInfo(E.MarkupMarkdown, doc("expr " .. name_ref_text(pvm, O, frag.name) .. "(" .. open_params_text(frag.params) .. "): " .. Format.type_name(frag.result), { "- expr fragment", "- composition: emit in expression position" }), range)
        elseif cls == E.SubjectBinding then
            local binding = subject.binding
            return E.HoverInfo(E.MarkupMarkdown, doc(binding.name .. ": " .. Format.type_name(binding.ty), { "- " .. binding_class_text(pvm, binding) }), range)
        elseif cls == E.SubjectContinuation then
            local label = subject.label.name
            local signature = label
            for i = 1, #analysis.anchors.anchors do
                local a = analysis.anchors.anchors[i]
                if a.kind == T.LalinSource.AnchorContinuationName and a.label == label then
                    for j = 1, #(analysis.parse.combined.region_frags or {}) do
                        local frag = analysis.parse.combined.region_frags[j]
                        for k = 1, #(frag.conts or {}) do
                            if frag.conts[k].pretty_name == label then signature = cont_text(frag.conts[k]) end
                        end
                    end
                end
            end
            return E.HoverInfo(E.MarkupMarkdown, doc(signature, { "- continuation label / CFG target" }), range)
        elseif cls == E.SubjectKeyword then
            return E.HoverInfo(E.MarkupPlainText, "Lalin keyword: " .. subject.text, range)
        elseif cls == E.SubjectBuiltin then
            return E.HoverInfo(E.MarkupMarkdown, "Lalin builtin `" .. subject.name .. "`", range)
        elseif cls == E.SubjectDiagnostic then
            return E.HoverInfo(E.MarkupMarkdown, subject.diagnostic.message, subject.diagnostic.range)
        end
        return E.HoverMissing("no hover for subject")
    end

    local function hover_phase(query, analysis)
        local pick = Subject.subject_at(query, analysis)
        return hover_from_pick_phase(pick, analysis)
    end

    local function hover(query, analysis)
        return hover_phase(query, analysis)
    end

    return {
        hover_phase = hover_phase,
        hover_from_pick_phase = hover_from_pick_phase,
        hover = hover,
    }
end

return bind_context