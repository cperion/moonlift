local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.type_to_back_scalar ~= nil then return T._moonlift_api_cache.type_to_back_scalar end

    local Core = T.MoonCore
    local Ty = T.MoonType
    local Back = T.MoonBack

    local scalar_to_back
    local type_to_back_scalar_result

    local classify_api = require("moonlift.type_classify").Define(T)

    function scalar_to_back(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Core.ScalarBool) then
            return (function()
 return erased.once(Back.BackBool)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarI8) then
            return (function()
 return erased.once(Back.BackI8)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarI16) then
            return (function()
 return erased.once(Back.BackI16)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarI32) then
            return (function()
 return erased.once(Back.BackI32)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarI64) then
            return (function()
 return erased.once(Back.BackI64)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarU8) then
            return (function()
 return erased.once(Back.BackU8)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarU16) then
            return (function()
 return erased.once(Back.BackU16)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarU32) then
            return (function()
 return erased.once(Back.BackU32)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarU64) then
            return (function()
 return erased.once(Back.BackU64)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarF32) then
            return (function()
 return erased.once(Back.BackF32)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarF64) then
            return (function()
 return erased.once(Back.BackF64)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarRawPtr) then
            return (function()
 return erased.once(Back.BackPtr)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarIndex) then
            return (function()
 return erased.once(Back.BackIndex)
            end)(node, ...)
        elseif schema.isa(node, Core.ScalarVoid) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_type_scalar_to_back: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function type_to_back_scalar_result(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TypeClassScalar) then
            return (function(self, ty)

            local values = scalar_to_back(self.scalar)
            if #values == 0 then
                return erased.once(Ty.TypeBackScalarUnavailable(ty, self))
            end
            return erased.once(Ty.TypeBackScalarKnown(values[1]))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassPointer) then
            return (function(_, ty)

            return erased.once(Ty.TypeBackScalarKnown(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassCallable) then
            return (function(_, ty)

            return erased.once(Ty.TypeBackScalarKnown(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassArray) then
            return (function(self, ty)

            return erased.once(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassSlice) then
            return (function(self, ty)

            return erased.once(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassView) then
            return (function(self, ty)

            return erased.once(Ty.TypeBackScalarUnavailable(ty, self))
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
                if #values > 0 then return erased.once(Ty.TypeBackScalarKnown(values[1])) end
            end
            return erased.once(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassClosure) then
            return (function()

            -- Tree-to-back represents closure values as addresses of the
            -- two-word { fn, ctx } descriptor while preserving the source
            -- type as Ty.TClosure in semantic IR.
            return erased.once(Ty.TypeBackScalarKnown(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassAggregate) then
            return (function(self, ty)

            return erased.once(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassUnknown) then
            return (function(self, ty)

            return erased.once(Ty.TypeBackScalarUnavailable(ty, self))
            end)(node, ...)
        else
            error("erased phase moonlift_type_to_back_scalar_result: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local api = {
        scalar_to_back = scalar_to_back,
        type_to_back_scalar_result = function(ty)
            local class = classify_api.classify(ty)
            return type_to_back_scalar_result(class, ty)
        end,
        result = function(ty)
            return erased.one(type_to_back_scalar_result(classify_api.classify(ty), ty))
        end,
    }
    T._moonlift_api_cache.type_to_back_scalar = api
    return api
end

return M
