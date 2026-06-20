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

local function list_or_single(results)
    if results == nil then return {} end
    if pvm.classof(results) then return { results } end
    return results
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_type ~= nil then return T._moonlift_api_cache.code_type end

    local Core = T.MoonCore
    local Ty = T.MoonType
    local Code = T.MoonCode
    local C = T.MoonC

    local api = {}

    local function default_target(opts)
        opts = opts or {}
        local dialect = opts.dialect or C.CBackendC99
        if type(dialect) == "string" then
            if dialect == "c11" then dialect = C.CBackendC11
            elseif dialect == "gnu" or dialect == "gnu99" or dialect == "gnuc" then dialect = C.CBackendGnuC
            elseif dialect == "clang" then dialect = C.CBackendClangC
            else dialect = C.CBackendC99 end
        end
        local platform = opts.platform or C.CBackendHostedNative
        if type(platform) == "string" then
            if platform == "freestanding" then platform = C.CBackendFreestanding
            elseif platform == "wasm" or platform == "wasm-capable" then platform = C.CBackendWasmCapable
            elseif platform == "embedded" then platform = C.CBackendEmbedded
            else platform = C.CBackendHostedNative end
        end
        local endian = opts.endian or C.CBackendLittleEndian
        if type(endian) == "string" then
            endian = (endian == "big" or endian == "be") and C.CBackendBigEndian or C.CBackendLittleEndian
        end
        return C.CBackendTarget(
            dialect,
            platform,
            opts.pointer_bits or 64,
            opts.index_bits or opts.pointer_bits or 64,
            endian,
            opts.hosted ~= false
        )
    end

    local function normalize_target(target_or_opts)
        if pvm.classof(target_or_opts) == C.CBackendTarget then return target_or_opts end
        return default_target(target_or_opts)
    end

    local function target_facts(target_or_opts)
        local target = normalize_target(target_or_opts)
        return {
            target = target,
            pointer_bits = target.pointer_bits,
            index_bits = target.index_bits,
            endian = target.endian,
            hosted = target.hosted,
        }
    end

    local function scalar_to_code(scalar)
        if scalar == Core.ScalarVoid then return Code.CodeTyVoid end
        if scalar == Core.ScalarBool then return Code.CodeTyBool8 end
        if scalar == Core.ScalarRawPtr then return Code.CodeTyDataPtr(nil) end
        if scalar == Core.ScalarIndex then return Code.CodeTyIndex end
        if scalar == Core.ScalarI8 then return Code.CodeTyInt(8, Code.CodeSigned) end
        if scalar == Core.ScalarI16 then return Code.CodeTyInt(16, Code.CodeSigned) end
        if scalar == Core.ScalarI32 then return Code.CodeTyInt(32, Code.CodeSigned) end
        if scalar == Core.ScalarI64 then return Code.CodeTyInt(64, Code.CodeSigned) end
        if scalar == Core.ScalarU8 then return Code.CodeTyInt(8, Code.CodeUnsigned) end
        if scalar == Core.ScalarU16 then return Code.CodeTyInt(16, Code.CodeUnsigned) end
        if scalar == Core.ScalarU32 then return Code.CodeTyInt(32, Code.CodeUnsigned) end
        if scalar == Core.ScalarU64 then return Code.CodeTyInt(64, Code.CodeUnsigned) end
        if scalar == Core.ScalarF32 then return Code.CodeTyFloat(32) end
        if scalar == Core.ScalarF64 then return Code.CodeTyFloat(64) end
        error("code_type: unsupported scalar " .. class_name(scalar), 2)
    end

    local function int_scalar(bits, signedness)
        if signedness == Code.CodeSigned then
            if bits == 8 then return Core.ScalarI8 end
            if bits == 16 then return Core.ScalarI16 end
            if bits == 32 then return Core.ScalarI32 end
            if bits == 64 then return Core.ScalarI64 end
        elseif signedness == Code.CodeUnsigned then
            if bits == 8 then return Core.ScalarU8 end
            if bits == 16 then return Core.ScalarU16 end
            if bits == 32 then return Core.ScalarU32 end
            if bits == 64 then return Core.ScalarU64 end
        end
        error("code_type: unsupported integer width/signedness " .. tostring(bits), 3)
    end

    local function float_scalar(bits)
        if bits == 32 then return Core.ScalarF32 end
        if bits == 64 then return Core.ScalarF64 end
        error("code_type: unsupported float width " .. tostring(bits), 3)
    end

    local function named_type_name(ref, ctx)
        local rcls = pvm.classof(ref)
        if rcls == Ty.TypeRefGlobal then return ref.module_name, ref.type_name end
        if rcls == Ty.TypeRefLocal then return "local", ref.sym.name end
        if rcls == Ty.TypeRefPath and #ref.path.parts > 0 then return (ctx and ctx.module_name) or "", ref.path.parts[#ref.path.parts].text end
        error("code_type: unresolved named type " .. class_name(ref), 3)
    end

    local function canonical_named_source_ty(ty, module_name, type_name)
        local ref = ty and ty.ref
        if pvm.classof(ref) == Ty.TypeRefPath and module_name ~= nil and module_name ~= "" then
            return Ty.TNamed(Ty.TypeRefGlobal(module_name, type_name))
        end
        return ty
    end

    local code_type_key

    local function normalize_code_results(results)
        results = list_or_single(results)
        if #results == 1 and results[1] == Code.CodeTyVoid then return {} end
        return results
    end

    code_type_key = function(ty)
        if ty == Code.CodeTyVoid then return "void" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        if ty == Code.CodeTyIndex then return "index" end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if cls == Code.CodeTyDataPtr then return "ptr_" .. (ty.pointee and code_type_key(ty.pointee) or "opaque") end
        if cls == Code.CodeTyCodePtr then return "codeptr_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyNamed then return "named_" .. sanitize(ty.module_name) .. "_" .. sanitize(ty.type_name) end
        if cls == Code.CodeTyArray then return "arr_" .. tostring(ty.count) .. "_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTySlice then return "slice_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTyView then return "view_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTyHandle then return "handle_" .. code_type_key(ty.repr) end
        if cls == Code.CodeTyLease then return "lease_" .. code_type_key(ty.base) end
        if cls == Code.CodeTyClosure then return "closure_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyImportedC then return "ctype_" .. sanitize(ty.id.module_name) .. "_" .. sanitize(ty.id.spelling) end
        if cls == Code.CodeTyImportedCFuncPtr then return "cfuncptr_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyVector then return "vec_" .. tostring(ty.lanes) .. "_" .. code_type_key(ty.elem) end
        error("code_type: unsupported CodeType " .. class_name(ty), 2)
    end

    local function code_sig_id(params, results)
        results = normalize_code_results(results)
        local parts = { "codesig" }
        for i = 1, #(params or {}) do parts[#parts + 1] = code_type_key(params[i]) end
        parts[#parts + 1] = "to"
        if #results == 0 then
            parts[#parts + 1] = "void"
        else
            for i = 1, #results do parts[#parts + 1] = code_type_key(results[i]) end
        end
        return Code.CodeSigId(table.concat(parts, "_"))
    end

    local function remember_code_sig(ctx, sig)
        if ctx == nil then return sig end
        ctx.code_sigs = ctx.code_sigs or {}
        ctx.code_sig_order = ctx.code_sig_order or {}
        if ctx.code_sigs[sig.id.text] == nil then
            ctx.code_sigs[sig.id.text] = sig
            ctx.code_sig_order[#ctx.code_sig_order + 1] = sig
        end
        return ctx.code_sigs[sig.id.text]
    end

    local function ensure_code_sig(ctx, params, results)
        results = normalize_code_results(results)
        local id = code_sig_id(params or {}, results)
        remember_code_sig(ctx, Code.CodeSig(id, params or {}, results))
        return id
    end

    local type_to_code
    type_to_code = function(ty, ctx)
        local cls = pvm.classof(ty)
        if cls == Ty.TScalar then
            return scalar_to_code(ty.scalar)
        elseif cls == Ty.TPtr then
            return Code.CodeTyDataPtr(type_to_code(ty.elem, ctx))
        elseif cls == Ty.TArray then
            if pvm.classof(ty.count) ~= Ty.ArrayLenConst then
                error("code_type: dynamic array length reached CodeType projection; typechecking must reject ArrayLenExpr before backend lowering", 2)
            end
            return Code.CodeTyArray(type_to_code(ty.elem, ctx), ty.count.count)
        elseif cls == Ty.TSlice then
            return Code.CodeTySlice(type_to_code(ty.elem, ctx))
        elseif cls == Ty.TView then
            return Code.CodeTyView(type_to_code(ty.elem, ctx))
        elseif cls == Ty.TLease then
            return Code.CodeTyLease(type_to_code(ty.base, ctx), ty)
        elseif cls == Ty.TOwned then
            return type_to_code(ty.base, ctx)
        elseif cls == Ty.TAccess then
            return type_to_code(ty.base, ctx)
        elseif cls == Ty.THandle then
            local rcls = pvm.classof(ty.repr)
            if rcls == Ty.HandleReprScalar then
                return Code.CodeTyHandle(scalar_to_code(ty.repr.scalar), ty)
            end
            error("code_type: unsupported handle repr " .. class_name(ty.repr), 2)
        elseif cls == Ty.TFunc then
            local params = {}
            for i = 1, #ty.params do params[i] = type_to_code(ty.params[i], ctx) end
            local result = type_to_code(ty.result, ctx)
            return Code.CodeTyCodePtr(ensure_code_sig(ctx, params, { result }))
        elseif cls == Ty.TClosure then
            local params = {}
            for i = 1, #ty.params do params[i] = type_to_code(ty.params[i], ctx) end
            local result = type_to_code(ty.result, ctx)
            return Code.CodeTyClosure(ensure_code_sig(ctx, params, { result }))
        elseif cls == Ty.TNamed then
            local module_name, type_name = named_type_name(ty.ref, ctx)
            return Code.CodeTyNamed(module_name, type_name, canonical_named_source_ty(ty, module_name, type_name))
        elseif cls == Ty.TCType then
            return Code.CodeTyImportedC(ty.id)
        elseif cls == Ty.TCFuncPtr then
            return Code.CodeTyImportedCFuncPtr(ty.sig)
        elseif cls == Ty.TSlot then
            error("code_type: open type slot cannot be projected to MoonCode", 2)
        end
        error("code_type: unsupported MoonType " .. class_name(ty), 2)
    end

    local function c_backend_sig_id(code_sig_id_value)
        return C.CBackendFuncSigId(code_sig_id_value.text)
    end

    local function c_backend_closure_sig_id(code_sig_id_value)
        return C.CBackendFuncSigId("closure_" .. code_sig_id_value.text)
    end

    local code_type_to_c

    local function code_sig_result_to_c(ctx, sig)
        local results = sig.results or {}
        if #results == 0 then return C.CBackendVoid end
        if #results == 1 then return code_type_to_c(results[1], ctx) end
        error("code_type: C backend cannot spell multi-result CodeSig " .. sig.id.text, 3)
    end

    local function ensure_c_backend_sig(ctx, sig_id)
        local id = c_backend_sig_id(sig_id)
        local sig = ctx and ctx.code_sigs and ctx.code_sigs[sig_id.text]
        if sig and ctx then
            ctx.sigs = ctx.sigs or {}
            ctx.sig_order = ctx.sig_order or {}
            if ctx.sigs[id.text] == nil then
                local params = {}
                for i = 1, #sig.params do params[i] = code_type_to_c(sig.params[i], ctx) end
                local result = code_sig_result_to_c(ctx, sig)
                local c_sig = C.CBackendFuncSig(id, params, result)
                ctx.sigs[id.text] = c_sig
                ctx.sig_order[#ctx.sig_order + 1] = c_sig
            end
        end
        return id
    end

    local function ensure_c_backend_closure_sig(ctx, sig_id)
        local id = c_backend_closure_sig_id(sig_id)
        local sig = ctx and ctx.code_sigs and ctx.code_sigs[sig_id.text]
        if sig and ctx then
            ctx.sigs = ctx.sigs or {}
            ctx.sig_order = ctx.sig_order or {}
            if ctx.sigs[id.text] == nil then
                local params = { C.CBackendDataPtr(nil) }
                for i = 1, #sig.params do params[#params + 1] = code_type_to_c(sig.params[i], ctx) end
                local result = code_sig_result_to_c(ctx, sig)
                local c_sig = C.CBackendFuncSig(id, params, result)
                ctx.sigs[id.text] = c_sig
                ctx.sig_order[#ctx.sig_order + 1] = c_sig
            end
        end
        return id
    end

    code_type_to_c = function(ty, ctx)
        if ty == Code.CodeTyVoid then return C.CBackendVoid end
        if ty == Code.CodeTyBool8 then return C.CBackendBool8 end
        if ty == Code.CodeTyIndex then return C.CBackendIndex end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then return C.CBackendScalar(int_scalar(ty.bits, ty.signedness)) end
        if cls == Code.CodeTyFloat then return C.CBackendScalar(float_scalar(ty.bits)) end
        if cls == Code.CodeTyDataPtr then return C.CBackendDataPtr(ty.pointee and code_type_to_c(ty.pointee, ctx) or nil) end
        if cls == Code.CodeTyCodePtr then return C.CBackendCodePtr(ensure_c_backend_sig(ctx, ty.sig)) end
        if cls == Code.CodeTyNamed then return C.CBackendNamed(C.CTypeId(ty.module_name, ty.type_name)) end
        if cls == Code.CodeTyArray then return C.CBackendArray(code_type_to_c(ty.elem, ctx), ty.count) end
        if cls == Code.CodeTySlice then return C.CBackendSliceDescriptor(code_type_to_c(ty.elem, ctx)) end
        if cls == Code.CodeTyView then return C.CBackendViewDescriptor(code_type_to_c(ty.elem, ctx)) end
        if cls == Code.CodeTyHandle then return code_type_to_c(ty.repr, ctx) end
        if cls == Code.CodeTyLease then return code_type_to_c(ty.base, ctx) end
        if cls == Code.CodeTyClosure then return C.CBackendClosureDescriptor(ensure_c_backend_closure_sig(ctx, ty.sig), C.CBackendDataPtr(nil)) end
        if cls == Code.CodeTyImportedC then return C.CBackendNamed(ty.id) end
        if cls == Code.CodeTyImportedCFuncPtr then return C.CBackendImportedCodePtr(ty.sig) end
        if cls == Code.CodeTyVector then return C.CBackendVector(code_type_to_c(ty.elem, ctx), ty.lanes) end
        error("code_type: unsupported CodeType for C backend " .. class_name(ty), 2)
    end

    local function type_to_c(ty, ctx)
        return code_type_to_c(type_to_code(ty, ctx), ctx)
    end

    local function ensure_type_sig(ctx, params, result)
        local code_params = {}
        for i = 1, #(params or {}) do code_params[i] = type_to_code(params[i], ctx) end
        local code_result = type_to_code(result, ctx)
        return ensure_code_sig(ctx, code_params, { code_result })
    end

    api.default_target = default_target
    api.normalize_target = normalize_target
    api.target_facts = target_facts
    api.scalar_to_code = scalar_to_code
    api.type_to_code = type_to_code
    api.code_type_key = code_type_key
    api.code_sig_id = code_sig_id
    api.ensure_code_sig = ensure_code_sig
    api.ensure_type_sig = ensure_type_sig
    api.c_backend_sig_id = c_backend_sig_id
    api.c_backend_closure_sig_id = c_backend_closure_sig_id
    api.ensure_c_backend_sig = ensure_c_backend_sig
    api.ensure_c_backend_closure_sig = ensure_c_backend_closure_sig
    api.code_type_to_c = code_type_to_c
    api.type_to_c = type_to_c

    T._moonlift_api_cache.code_type = api
    return api
end

return M
