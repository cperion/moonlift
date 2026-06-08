local pvm = require("moonlift.pvm")

local M = {}

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function node_key(x)
    local cls = pvm.classof(x)
    if not cls then return tostring(x) end
    local fields = cls.__fields
    if not fields or #fields == 0 then return class_name(cls) end
    local parts = { class_name(cls), "(" }
    for i, f in ipairs(fields) do
        if i > 1 then parts[#parts + 1] = "," end
        local v = x[f.name]
        if type(v) == "table" and not pvm.classof(v) then
            parts[#parts + 1] = "["
            for j = 1, #v do
                if j > 1 then parts[#parts + 1] = "," end
                parts[#parts + 1] = node_key(v[j])
            end
            parts[#parts + 1] = "]"
        else
            parts[#parts + 1] = node_key(v)
        end
    end
    parts[#parts + 1] = ")"
    return table.concat(parts)
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.type_to_c ~= nil then return T._moonlift_api_cache.type_to_c end

    local Core = T.MoonCore
    local Ty = T.MoonType
    local C = T.MoonC

    local CAbi = require("moonlift.c_abi").Define(T)

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

    local function scalar_to_c(scalar)
        if scalar == Core.ScalarVoid then return C.CBackendVoid end
        if scalar == Core.ScalarBool then return C.CBackendBool8 end
        if scalar == Core.ScalarRawPtr then return C.CBackendDataPtr(nil) end
        if scalar == Core.ScalarIndex then return C.CBackendIndex end
        if scalar == Core.ScalarI8 or scalar == Core.ScalarI16 or scalar == Core.ScalarI32 or scalar == Core.ScalarI64
            or scalar == Core.ScalarU8 or scalar == Core.ScalarU16 or scalar == Core.ScalarU32 or scalar == Core.ScalarU64
            or scalar == Core.ScalarF32 or scalar == Core.ScalarF64 then
            return C.CBackendScalar(scalar)
        end
        error("type_to_c: unsupported scalar " .. class_name(scalar), 2)
    end

    local function sig_text(params, result)
        local parts = { "fn" }
        for i = 1, #params do
            parts[#parts + 1] = (i == 1) and "_" or "_"
            parts[#parts + 1] = node_key(params[i]):gsub("[^%w_]+", "_")
        end
        parts[#parts + 1] = "__"
        parts[#parts + 1] = node_key(result):gsub("[^%w_]+", "_")
        return table.concat(parts)
    end

    local function func_sig_id(params, result)
        return C.CBackendFuncSigId(sig_text(params, result))
    end

    local function ensure_sig(ctx, params, result)
        local id = func_sig_id(params, result)
        if ctx then
            ctx.sigs = ctx.sigs or {}
            ctx.sig_order = ctx.sig_order or {}
            if ctx.sigs[id.text] == nil then
                local sig = C.CBackendFuncSig(id, params, result)
                ctx.sigs[id.text] = sig
                ctx.sig_order[#ctx.sig_order + 1] = sig
            end
        end
        return id
    end

    local type_to_c
    type_to_c = function(ty, ctx)
        local cls = pvm.classof(ty)
        if cls == Ty.TScalar then
            return scalar_to_c(ty.scalar)
        elseif cls == Ty.TPtr then
            return C.CBackendDataPtr(type_to_c(ty.elem, ctx))
        elseif cls == Ty.TFunc then
            return CAbi.project_type(ty, ctx)
        elseif cls == Ty.TCFuncPtr then
            return C.CBackendImportedCodePtr(ty.sig)
        elseif cls == Ty.TCType then
            return C.CBackendNamed(ty.id)
        elseif cls == Ty.TNamed then
            return CAbi.project_type(ty, ctx)
        elseif cls == Ty.TArray then
            if pvm.classof(ty.count) ~= Ty.ArrayLenConst then
                error("type_to_c: dynamic array length reached C projection; typechecking must reject ArrayLenExpr before backend lowering", 2)
            end
            return C.CBackendArray(type_to_c(ty.elem, ctx), ty.count.count)
        elseif cls == Ty.TSlice then
            return CAbi.ensure_descriptor_decl(ctx, "slice", ty.elem)
        elseif cls == Ty.TView then
            return CAbi.ensure_descriptor_decl(ctx, "view", ty.elem)
        elseif cls == Ty.TClosure then
            return CAbi.project_type(ty, ctx)
        elseif cls == Ty.TSlot then
            error("type_to_c: open type slot cannot be projected to C", 2)
        end
        error("type_to_c: unsupported type " .. class_name(ty), 2)
    end

    api.scalar_to_c = scalar_to_c
    api.type_to_c = type_to_c
    api.func_sig_id = func_sig_id
    api.ensure_sig = ensure_sig
    api.ensure_descriptor_decl = CAbi.ensure_descriptor_decl
    api.default_target = default_target
    api.type_key = node_key

    T._moonlift_api_cache.type_to_c = api
    return api
end

return M
