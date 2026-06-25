local schema = require("lalin.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.type_to_back_scalar ~= nil then return T._lalin_api_cache.type_to_back_scalar end

    local Core = T.LalinCore
    local Ty = T.LalinType
    local Back = T.LalinBack

    local scalar_to_back
    local type_to_back_scalar_result

    local classify_api = require("lalin.type_classify")(T)

    function scalar_to_back(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Core.ScalarBool) then
            return (function()
 return single(Back.BackBool)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarI8) then
            return (function()
 return single(Back.BackI8)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarI16) then
            return (function()
 return single(Back.BackI16)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarI32) then
            return (function()
 return single(Back.BackI32)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarI64) then
            return (function()
 return single(Back.BackI64)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarU8) then
            return (function()
 return single(Back.BackU8)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarU16) then
            return (function()
 return single(Back.BackU16)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarU32) then
            return (function()
 return single(Back.BackU32)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarU64) then
            return (function()
 return single(Back.BackU64)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarF32) then
            return (function()
 return single(Back.BackF32)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarF64) then
            return (function()
 return single(Back.BackF64)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarRawPtr) then
            return (function()
 return single(Back.BackPtr)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarIndex) then
            return (function()
 return single(Back.BackIndex)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarVoid) then
            return (function()
 return {}
            end)(node, ...)
        else
            error("phase lalin_type_scalar_to_back: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function type_to_back_scalar_result(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TypeClassScalar) then
            return (function(self, ty)

            local values = scalar_to_back(self.scalar)
            if #values == 0 then
                return single(Ty.TypeBackScalarUnavailable(ty, self))
            end
            return single(Ty.TypeBackScalarKnown(values[1]))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassPointer) then
            return (function(_, ty)

            return single(Ty.TypeBackScalarKnown(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassCallable) then
            return (function(_, ty)

            return single(Ty.TypeBackScalarKnown(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassArray) then
            return (function(self, ty)

            return single(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassSlice) then
            return (function(self, ty)

            return single(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassView) then
            return (function(self, ty)

            return single(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassLease) then
            return (function(self, ty)

            local class = classify_api.classify(self.base)
            return type_to_back_scalar_result(class, self.base)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassOwned) then
            return (function(self, ty)

            local class = classify_api.classify(self.base)
            return type_to_back_scalar_result(class, self.base)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassHandle) then
            return (function(self, ty)

            if schema.classof(self.repr) == Ty.HandleReprScalar then
                local values = scalar_to_back(self.repr.scalar)
                if #values > 0 then return single(Ty.TypeBackScalarKnown(values[1])) end
            end
            return single(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassClosure) then
            return (function()

            -- Tree-to-back represents closure values as addresses of the
            -- two-word { fn, ctx } descriptor while preserving the source
            -- type as Ty.TClosure in semantic IR.
            return single(Ty.TypeBackScalarKnown(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassAggregate) then
            return (function(self, ty)

            return single(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassUnknown) then
            return (function(self, ty)

            return single(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        else
            error("phase lalin_type_to_back_scalar_result: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local api = {
        scalar_to_back = scalar_to_back,
        type_to_back_scalar_result = function(ty)
            local class = classify_api.classify(ty)
            return type_to_back_scalar_result(class, ty)
        end,
        result = function(ty)
            return only(type_to_back_scalar_result(classify_api.classify(ty), ty))
        end,
    }
    T._lalin_api_cache.type_to_back_scalar = api
    return api
end

return bind_context