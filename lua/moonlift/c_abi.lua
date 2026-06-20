local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.c_abi ~= nil then return T._moonlift_api_cache.c_abi end

    local Core = T.MoonCore
    local Ty = T.MoonType
    local C = T.MoonC

    local classify_api = require("moonlift.type_classify").Define(T)

    local api = {}

    local function type_key(ty)
        local cls = pvm.classof(ty)
        if not cls then return sanitize(tostring(ty)) end
        if cls == Ty.TScalar then return sanitize(class_name(ty.scalar)) end
        if cls == Ty.TPtr then return "ptr_" .. type_key(ty.elem) end
        if cls == Ty.TArray then
            local count = pvm.classof(ty.count) == Ty.ArrayLenConst and tostring(ty.count.count) or "open"
            return "arr_" .. count .. "_" .. type_key(ty.elem)
        end
        if cls == Ty.TSlice then return "slice_" .. type_key(ty.elem) end
        if cls == Ty.TView then return "view_" .. type_key(ty.elem) end
        if cls == Ty.TLease then return "lease_" .. type_key(ty.base) end
        if cls == Ty.TOwned then return "owned_" .. type_key(ty.base) end
        if cls == Ty.TAccess then return "access_" .. class_name(ty.access) .. "_" .. type_key(ty.base) end
        if cls == Ty.THandle then return "handle_" .. type_key(Ty.TScalar(ty.repr.scalar)) end
        if cls == Ty.TFunc then return "fn_" .. tostring(#ty.params) .. "_" .. type_key(ty.result) end
        if cls == Ty.TClosure then return "closure_" .. tostring(#ty.params) .. "_" .. type_key(ty.result) end
        if cls == Ty.TNamed then
            local ref = ty.ref
            local rcls = pvm.classof(ref)
            if rcls == Ty.TypeRefGlobal then return sanitize(ref.module_name .. "_" .. ref.type_name) end
            if rcls == Ty.TypeRefLocal then return sanitize(ref.sym.key or ref.sym.name) end
            if rcls == Ty.TypeRefPath then
                local parts = {}
                for i = 1, #ref.path.parts do parts[#parts + 1] = ref.path.parts[i].text end
                return sanitize(table.concat(parts, "_"))
            end
            return "named_slot"
        end
        if cls == Ty.TCType then return sanitize("ctype_" .. ty.id.module_name .. "_" .. ty.id.spelling) end
        if cls == Ty.TCFuncPtr then return sanitize("cfn_" .. ty.sig.text) end
        return sanitize(class_name(ty))
    end

    local function sig_id_for(params, result)
        local parts = { "cabi" }
        for i = 1, #(params or {}) do parts[#parts + 1] = type_key(params[i]) end
        parts[#parts + 1] = "to"
        parts[#parts + 1] = type_key(result)
        return C.CBackendFuncSigId(table.concat(parts, "_"))
    end

    local project_type

    local function ensure_sig(ctx, params, result)
        local c_params = {}
        for i = 1, #(params or {}) do c_params[i] = project_type(params[i], ctx) end
        local c_result = project_type(result, ctx)
        local id = sig_id_for(params, result)
        if ctx then
            ctx.sigs = ctx.sigs or {}
            ctx.sig_order = ctx.sig_order or {}
            if ctx.sigs[id.text] == nil then
                local sig = C.CBackendFuncSig(id, c_params, c_result)
                ctx.sigs[id.text] = sig
                ctx.sig_order[#ctx.sig_order + 1] = sig
            end
        end
        return id
    end

    local function named_type_for_ref(ref)
        local rcls = pvm.classof(ref)
        if rcls == Ty.TypeRefGlobal then return C.CBackendNamed(C.CTypeId(ref.module_name, ref.type_name)) end
        if rcls == Ty.TypeRefLocal then return C.CBackendNamed(C.CTypeId("local", ref.sym.name)) end
        if rcls == Ty.TypeRefPath and #ref.path.parts > 0 then return C.CBackendNamed(C.CTypeId("", ref.path.parts[#ref.path.parts].text)) end
        error("c_abi: unresolved named type " .. class_name(ref), 3)
    end

    project_type = function(ty, ctx)
        local cls = pvm.classof(ty)
        if cls == Ty.TScalar then
            if ty.scalar == Core.ScalarVoid then return C.CBackendVoid end
            if ty.scalar == Core.ScalarBool then return C.CBackendBool8 end
            if ty.scalar == Core.ScalarRawPtr then return C.CBackendDataPtr(nil) end
            if ty.scalar == Core.ScalarIndex then return C.CBackendIndex end
            return C.CBackendScalar(ty.scalar)
        elseif cls == Ty.TPtr then
            return C.CBackendDataPtr(project_type(ty.elem, ctx))
        elseif cls == Ty.TArray then
            if pvm.classof(ty.count) ~= Ty.ArrayLenConst then error("c_abi: ABI array type requires constant length", 3) end
            return C.CBackendArray(project_type(ty.elem, ctx), ty.count.count)
        elseif cls == Ty.TSlice then
            return C.CBackendSliceDescriptor(project_type(ty.elem, ctx))
        elseif cls == Ty.TView then
            return C.CBackendViewDescriptor(project_type(ty.elem, ctx))
        elseif cls == Ty.TLease then
            return project_type(ty.base, ctx)
        elseif cls == Ty.TOwned then
            return project_type(ty.base, ctx)
        elseif cls == Ty.TAccess then
            return project_type(ty.base, ctx)
        elseif cls == Ty.THandle then
            return project_type(Ty.TScalar(ty.repr.scalar), ctx)
        elseif cls == Ty.TFunc then
            return C.CBackendCodePtr(ensure_sig(ctx, ty.params, ty.result))
        elseif cls == Ty.TClosure then
            local closure_params = { Ty.TPtr(Ty.TScalar(Core.ScalarU8)) }
            for i = 1, #ty.params do closure_params[#closure_params + 1] = ty.params[i] end
            return C.CBackendClosureDescriptor(ensure_sig(ctx, closure_params, ty.result), C.CBackendDataPtr(nil))
        elseif cls == Ty.TNamed then
            return named_type_for_ref(ty.ref)
        elseif cls == Ty.TCType then
            return C.CBackendNamed(ty.id)
        elseif cls == Ty.TCFuncPtr then
            return C.CBackendImportedCodePtr(ty.sig)
        elseif cls == Ty.TSlot then
            error("c_abi: open type slot cannot be projected to C ABI", 3)
        end
        error("c_abi: unsupported type " .. class_name(ty), 3)
    end

    local function descriptor_id(kind, elem)
        return C.CTypeId("moonlift", "ml_" .. kind .. "_" .. type_key(elem))
    end

    local function remember_type_decl(ctx, id, decl)
        if ctx == nil then return end
        ctx.types = ctx.types or {}
        ctx.type_order = ctx.type_order or ctx.types
        local key = id.module_name .. ":" .. id.spelling
        ctx.type_decls_by_id = ctx.type_decls_by_id or {}
        if ctx.type_decls_by_id[key] == nil then
            ctx.type_decls_by_id[key] = decl
            ctx.type_order[#ctx.type_order + 1] = decl
        end
    end

    local function ensure_descriptor_decl(ctx, kind, elem_ty)
        local elem = project_type(elem_ty, ctx)
        local id = descriptor_id(kind, elem_ty)
        local index = C.CBackendIndex
        local data_ptr = C.CBackendDataPtr(elem)
        local fields
        local ptr_size = ((ctx and ctx.target and ctx.target.pointer_bits) or 64) / 8
        local idx_size = ((ctx and ctx.target and ctx.target.index_bits) or 64) / 8
        local align = math.max(ptr_size, idx_size)
        local size
        if kind == "slice" then
            fields = {
                C.CBackendField(C.CBackendName("data"), data_ptr, 0, ptr_size, ptr_size),
                C.CBackendField(C.CBackendName("len"), index, ptr_size, idx_size, idx_size),
            }
            size = ptr_size + idx_size
        elseif kind == "view" then
            fields = {
                C.CBackendField(C.CBackendName("data"), data_ptr, 0, ptr_size, ptr_size),
                C.CBackendField(C.CBackendName("len"), index, ptr_size, idx_size, idx_size),
                C.CBackendField(C.CBackendName("stride"), index, ptr_size + idx_size, idx_size, idx_size),
            }
            size = ptr_size + idx_size + idx_size
        else
            error("c_abi: unknown descriptor kind " .. tostring(kind), 2)
        end
        remember_type_decl(ctx, id, C.CBackendStructDecl(id, fields, size, align))
        return C.CBackendNamed(id)
    end

    local function is_void_type(ty)
        return pvm.classof(ty) == Ty.TScalar and ty.scalar == Core.ScalarVoid
    end

    local function is_by_address_source_type(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TArray or cls == Ty.TNamed then return true end
        local tcls = classify_api.classify(ty)
        return pvm.classof(tcls) == Ty.TypeClassAggregate
    end

    local function issue(sig_id, site, reason)
        return C.CBackendIssueAbiMismatch(site, sig_id, reason)
    end

    local function lower_param(ctx, func_name, param, sig_id, out, issues)
        local name = param.name or ("arg" .. tostring(#out + 1))
        local ty = param.ty or param
        local cls = pvm.classof(ty)
        if cls == Ty.TSlot then
            issues[#issues + 1] = issue(sig_id, func_name .. ":" .. name, "open type slot has no C ABI")
            return
        end
        local source = project_type(ty, ctx)
        if cls == Ty.TView then
            out[#out + 1] = C.CBackendAbiParam(C.CBackendName(sanitize(name) .. "_data"), source, C.CBackendDataPtr(project_type(ty.elem, ctx)), C.CBackendAbiParamDescriptor)
            out[#out + 1] = C.CBackendAbiParam(C.CBackendName(sanitize(name) .. "_len"), source, C.CBackendIndex, C.CBackendAbiParamDescriptor)
            out[#out + 1] = C.CBackendAbiParam(C.CBackendName(sanitize(name) .. "_stride"), source, C.CBackendIndex, C.CBackendAbiParamDescriptor)
            return
        elseif cls == Ty.TSlice then
            ensure_descriptor_decl(ctx, "slice", ty.elem)
            out[#out + 1] = C.CBackendAbiParam(C.CBackendName(sanitize(name) .. "_data"), source, C.CBackendDataPtr(project_type(ty.elem, ctx)), C.CBackendAbiParamDescriptor)
            out[#out + 1] = C.CBackendAbiParam(C.CBackendName(sanitize(name) .. "_len"), source, C.CBackendIndex, C.CBackendAbiParamDescriptor)
            return
        elseif is_by_address_source_type(ty) then
            out[#out + 1] = C.CBackendAbiParam(C.CBackendName(sanitize(name)), source, C.CBackendDataPtr(source), C.CBackendAbiParamByAddress)
            return
        end
        out[#out + 1] = C.CBackendAbiParam(C.CBackendName(sanitize(name)), source, source, C.CBackendAbiParamDirect)
    end

    local function lower_result(ctx, func_name, result_ty, sig_id, out_params, issues)
        local cls = pvm.classof(result_ty)
        if cls == Ty.TSlot then
            issues[#issues + 1] = issue(sig_id, func_name .. ":return", "open type slot has no C ABI")
            return C.CBackendAbiResult(C.CBackendVoid, C.CBackendVoid, C.CBackendAbiResultVoid), C.CBackendVoid
        end
        local source = project_type(result_ty, ctx)
        if is_void_type(result_ty) then return C.CBackendAbiResult(source, C.CBackendVoid, C.CBackendAbiResultVoid), C.CBackendVoid end
        if cls == Ty.TView then
            ensure_descriptor_decl(ctx, "view", result_ty.elem)
            local lowered = C.CBackendAbiHiddenOutPtr(source)
            out_params[#out_params + 1] = C.CBackendAbiParam(C.CBackendName("ml_return_out"), source, lowered, C.CBackendAbiParamHiddenOut)
            return C.CBackendAbiResult(source, lowered, C.CBackendAbiResultHiddenOut), C.CBackendVoid
        elseif cls == Ty.TSlice then
            ensure_descriptor_decl(ctx, "slice", result_ty.elem)
            return C.CBackendAbiResult(source, source, C.CBackendAbiResultDescriptor), source
        elseif is_by_address_source_type(result_ty) then
            local lowered = C.CBackendAbiHiddenOutPtr(source)
            out_params[#out_params + 1] = C.CBackendAbiParam(C.CBackendName("ml_return_out"), source, lowered, C.CBackendAbiParamHiddenOut)
            return C.CBackendAbiResult(source, lowered, C.CBackendAbiResultHiddenOut), C.CBackendVoid
        end
        return C.CBackendAbiResult(source, source, C.CBackendAbiResultDirect), source
    end

    local function lowered_signature_from_abi(ctx, source_sig_id, abi_params, lowered_result, linkage, imported_sig)
        local param_tys = {}
        for i = 1, #abi_params do param_tys[i] = abi_params[i].lowered_ty end
        local sig = C.CBackendFuncSig(source_sig_id, param_tys, lowered_result)
        if ctx then
            ctx.sigs = ctx.sigs or {}
            ctx.sig_order = ctx.sig_order or {}
            if ctx.sigs[source_sig_id.text] == nil then
                ctx.sigs[source_sig_id.text] = sig
                ctx.sig_order[#ctx.sig_order + 1] = sig
            end
            ctx.abis = ctx.abis or {}
            ctx.abi_order = ctx.abi_order or {}
        end
        return sig
    end

    local function func_abi(ctx, func_name, params, result_ty, opts)
        opts = opts or {}
        local source_sig_id = opts.sig_id or sig_id_for(params, result_ty)
        local issues = {}
        local abi_params = {}
        local abi_result, lowered_result = lower_result(ctx, func_name, result_ty, source_sig_id, abi_params, issues)
        for i = 1, #(params or {}) do lower_param(ctx, func_name, params[i], source_sig_id, abi_params, issues) end
        local linkage = opts.linkage or C.CBackendLinkInternal
        local imported_sig = opts.imported_sig
        local sig = lowered_signature_from_abi(ctx, source_sig_id, abi_params, lowered_result, linkage, imported_sig)
        local abi = C.CBackendFuncAbi(source_sig_id, linkage, abi_params, abi_result, imported_sig)
        if ctx then
            ctx.abis = ctx.abis or {}
            ctx.abi_order = ctx.abi_order or {}
            if ctx.abis[source_sig_id.text] == nil then
                ctx.abis[source_sig_id.text] = abi
                ctx.abi_order[#ctx.abi_order + 1] = abi
            end
        end
        return { id = source_sig_id, sig = sig, abi = abi, issues = issues }
    end

    api.type_key = type_key
    api.sig_id_for = sig_id_for
    api.project_type = project_type
    api.ensure_sig = ensure_sig
    api.ensure_descriptor_decl = ensure_descriptor_decl
    api.func_abi = func_abi
    api.plan = func_abi

    T._moonlift_api_cache.c_abi = api
    return api
end

return M
