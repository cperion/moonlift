local pvm = require("moonlift.pvm")

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

    scalar_to_back = pvm.phase("moon2_type_scalar_to_back", {
        [Core.ScalarBool] = function() return pvm.once(Back.BackBool) end,
        [Core.ScalarI8] = function() return pvm.once(Back.BackI8) end,
        [Core.ScalarI16] = function() return pvm.once(Back.BackI16) end,
        [Core.ScalarI32] = function() return pvm.once(Back.BackI32) end,
        [Core.ScalarI64] = function() return pvm.once(Back.BackI64) end,
        [Core.ScalarU8] = function() return pvm.once(Back.BackU8) end,
        [Core.ScalarU16] = function() return pvm.once(Back.BackU16) end,
        [Core.ScalarU32] = function() return pvm.once(Back.BackU32) end,
        [Core.ScalarU64] = function() return pvm.once(Back.BackU64) end,
        [Core.ScalarF32] = function() return pvm.once(Back.BackF32) end,
        [Core.ScalarF64] = function() return pvm.once(Back.BackF64) end,
        [Core.ScalarRawPtr] = function() return pvm.once(Back.BackPtr) end,
        [Core.ScalarIndex] = function() return pvm.once(Back.BackIndex) end,
        [Core.ScalarVoid] = function() return pvm.empty() end,
    })

    type_to_back_scalar_result = pvm.phase("moon2_type_to_back_scalar_result", {
        [Ty.TypeClassScalar] = function(self, ty)
            local values = pvm.drain(scalar_to_back(self.scalar))
            if #values == 0 then
                return pvm.once(Ty.TypeBackScalarUnavailable(ty, self))
            end
            return pvm.once(Ty.TypeBackScalarKnown(values[1]))
        end,
        [Ty.TypeClassPointer] = function(_, ty)
            return pvm.once(Ty.TypeBackScalarKnown(Back.BackPtr))
        end,
        [Ty.TypeClassCallable] = function(_, ty)
            return pvm.once(Ty.TypeBackScalarKnown(Back.BackPtr))
        end,
        [Ty.TypeClassArray] = function(self, ty)
            return pvm.once(Ty.TypeBackScalarUnavailable(ty, self))
        end,
        [Ty.TypeClassSlice] = function(self, ty)
            return pvm.once(Ty.TypeBackScalarUnavailable(ty, self))
        end,
        [Ty.TypeClassView] = function(self, ty)
            return pvm.once(Ty.TypeBackScalarUnavailable(ty, self))
        end,
        [Ty.TypeClassClosure] = function(self, ty)
            return pvm.once(Ty.TypeBackScalarUnavailable(ty, self))
        end,
        [Ty.TypeClassAggregate] = function(self, ty)
            return pvm.once(Ty.TypeBackScalarUnavailable(ty, self))
        end,
        [Ty.TypeClassUnknown] = function(self, ty)
            return pvm.once(Ty.TypeBackScalarUnavailable(ty, self))
        end,
    })

    local api = {
        scalar_to_back = scalar_to_back,
        type_to_back_scalar_result = function(ty)
            local class = classify_api.classify(ty)
            return type_to_back_scalar_result(class, ty)
        end,
        result = function(ty)
            return pvm.one(type_to_back_scalar_result(classify_api.classify(ty), ty))
        end,
    }
    T._moonlift_api_cache.type_to_back_scalar = api
    return api
end

return M
