local pvm = require("moonlift.pvm")

local M = {}

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_aggregate_abi ~= nil then return T._moonlift_api_cache.code_aggregate_abi end

    local Code = T.MoonCode
    local Back = T.MoonBack
    local TypeSizeAlign = require("moonlift.type_size_align").Define(T)

    local api = {}

    local function scalar(ty)
        if ty == Code.CodeTyVoid then return Back.BackVoid end
        if ty == Code.CodeTyBool8 then return Back.BackBool end
        if ty == Code.CodeTyIndex then return Back.BackIndex end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then
            if ty.bits == 8 then return ty.signedness == Code.CodeSigned and Back.BackI8 or Back.BackU8 end
            if ty.bits == 16 then return ty.signedness == Code.CodeSigned and Back.BackI16 or Back.BackU16 end
            if ty.bits == 32 then return ty.signedness == Code.CodeSigned and Back.BackI32 or Back.BackU32 end
            if ty.bits == 64 then return ty.signedness == Code.CodeSigned and Back.BackI64 or Back.BackU64 end
        elseif cls == Code.CodeTyFloat then
            if ty.bits == 32 then return Back.BackF32 end
            if ty.bits == 64 then return Back.BackF64 end
        elseif cls == Code.CodeTyDataPtr or cls == Code.CodeTyCodePtr or cls == Code.CodeTyImportedCFuncPtr then
            return Back.BackPtr
        elseif cls == Code.CodeTyHandle then
            return scalar(ty.repr)
        elseif cls == Code.CodeTyLease then
            return scalar(ty.base)
        end
        return nil
    end

    local function is_view(ty)
        return pvm.classof(ty) == Code.CodeTyView or (pvm.classof(ty) == Code.CodeTyLease and is_view(ty.base))
    end

    local function view_elem(ty)
        if pvm.classof(ty) == Code.CodeTyLease then ty = ty.base end
        return pvm.classof(ty) == Code.CodeTyView and ty.elem or nil
    end

    local function is_aggregate(ty)
        local cls = pvm.classof(ty)
        return cls == Code.CodeTyNamed or cls == Code.CodeTyArray or cls == Code.CodeTySlice or cls == Code.CodeTyClosure
    end

    local function component_scalars(ty)
        if is_view(ty) then return { Back.BackPtr, Back.BackIndex, Back.BackIndex } end
        if is_aggregate(ty) then return { Back.BackPtr } end
        local s = scalar(ty)
        if s == nil then error("code_aggregate_abi: unsupported Code type " .. class_name(ty), 3) end
        return { s }
    end

    local function lowered_sig(sig)
        local sret = (#(sig.results or {}) == 1 and (is_aggregate(sig.results[1]) or is_view(sig.results[1])))
        local params, results = {}, {}
        if sret then params[#params + 1] = Back.BackPtr end
        for i = 1, #(sig.params or {}) do
            for _, s in ipairs(component_scalars(sig.params[i])) do params[#params + 1] = s end
        end
        if not sret then
            for i = 1, #(sig.results or {}) do
                for _, s in ipairs(component_scalars(sig.results[i])) do results[#results + 1] = s end
            end
        end
        return { sret = sret, result_ty = sret and sig.results[1] or nil, params = params, results = results }
    end

    local function layout(ctx, ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyNamed and ty.source_ty ~= nil and ctx ~= nil and ctx.layout_env ~= nil then
            local result = TypeSizeAlign.result(ty.source_ty, ctx.layout_env, ctx.target)
            if pvm.classof(result) == T.MoonType.TypeMemLayoutKnown then return result.layout end
        end
        return nil
    end

    local function size_align(ctx, ty)
        if is_view(ty) then return 24, 8 end
        if pvm.classof(ty) == Code.CodeTyClosure then return 16, 8 end
        local l = layout(ctx, ty)
        if l ~= nil then return l.size, l.align end
        return 1, 1
    end

    local function field_offset(ctx, ty, name)
        local l = layout(ctx, ty)
        for _, f in ipairs(l and l.fields or {}) do if f.field_name == name then return f.offset, f.ty end end
        return nil, nil
    end

    api.scalar = scalar
    api.is_view = is_view
    api.view_elem = view_elem
    api.is_aggregate = is_aggregate
    api.component_scalars = component_scalars
    api.param_back_scalar = function(ty)
        if is_view(ty) then return nil end
        if is_aggregate(ty) then return Back.BackPtr end
        return scalar(ty)
    end
    api.lowered_sig = lowered_sig
    api.has_hidden_result = function(sig) return lowered_sig(sig).sret end
    api.hidden_result_ty = function(sig) return lowered_sig(sig).result_ty end
    api.layout = layout
    api.size_align = size_align
    api.field_offset = field_offset

    T._moonlift_api_cache.code_aggregate_abi = api
    return api
end

return M
