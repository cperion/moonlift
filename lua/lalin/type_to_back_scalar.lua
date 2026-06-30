local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.type_to_back_scalar ~= nil then return T._lalin_api_cache.type_to_back_scalar end

    local Core = T.LalinCore
    local Ty = T.LalinType
    local Back = T.LalinBack

    local classify_api = require("lalin.type_classify")(T)

    function Core.Scalar:lower_core_scalar_to_back()
        return nil
    end

    function Core.ScalarBool:lower_core_scalar_to_back()
        return Back.BackBool
    end

    function Core.ScalarI8:lower_core_scalar_to_back()
        return Back.BackI8
    end

    function Core.ScalarI16:lower_core_scalar_to_back()
        return Back.BackI16
    end

    function Core.ScalarI32:lower_core_scalar_to_back()
        return Back.BackI32
    end

    function Core.ScalarI64:lower_core_scalar_to_back()
        return Back.BackI64
    end

    function Core.ScalarU8:lower_core_scalar_to_back()
        return Back.BackU8
    end

    function Core.ScalarU16:lower_core_scalar_to_back()
        return Back.BackU16
    end

    function Core.ScalarU32:lower_core_scalar_to_back()
        return Back.BackU32
    end

    function Core.ScalarU64:lower_core_scalar_to_back()
        return Back.BackU64
    end

    function Core.ScalarF32:lower_core_scalar_to_back()
        return Back.BackF32
    end

    function Core.ScalarF64:lower_core_scalar_to_back()
        return Back.BackF64
    end

    function Core.ScalarRawPtr:lower_core_scalar_to_back()
        return Back.BackPtr
    end

    function Core.ScalarIndex:lower_core_scalar_to_back()
        return Back.BackIndex
    end

    function Ty.TypeShape:lower_type_shape_to_back_scalar(ty)
        return Ty.TypeBackScalarUnavailable(ty, self)
    end

    function Ty.TypeShapeScalar:lower_type_shape_to_back_scalar(ty)
        local scalar = self.scalar:lower_core_scalar_to_back()
        if scalar == nil then return Ty.TypeBackScalarUnavailable(ty, self) end
        return Ty.TypeBackScalarKnown(scalar)
    end

    function Ty.TypeShapePointer:lower_type_shape_to_back_scalar()
        return Ty.TypeBackScalarKnown(Back.BackPtr)
    end

    function Ty.TypeShapeCallable:lower_type_shape_to_back_scalar()
        return Ty.TypeBackScalarKnown(Back.BackPtr)
    end

    function Ty.TypeShapeLease:lower_type_shape_to_back_scalar()
        local shape = classify_api.classify(self.base)
        return shape:lower_type_shape_to_back_scalar(self.base)
    end

    function Ty.TypeShapeOwned:lower_type_shape_to_back_scalar()
        local shape = classify_api.classify(self.base)
        return shape:lower_type_shape_to_back_scalar(self.base)
    end

    function Ty.HandleRepr:lower_type_handle_repr_to_back_scalar(ty, shape)
        return Ty.TypeBackScalarUnavailable(ty, shape)
    end

    function Ty.HandleReprScalar:lower_type_handle_repr_to_back_scalar(ty, shape)
        local scalar = self.scalar:lower_core_scalar_to_back()
        if scalar == nil then return Ty.TypeBackScalarUnavailable(ty, shape) end
        return Ty.TypeBackScalarKnown(scalar)
    end

    function Ty.TypeShapeHandle:lower_type_shape_to_back_scalar(ty)
        return self.repr:lower_type_handle_repr_to_back_scalar(ty, self)
    end

    function Ty.TypeShapeClosure:lower_type_shape_to_back_scalar()
        -- Tree-to-back represents closure values as addresses of the two-word
        -- { fn, ctx } descriptor while preserving the source type as Ty.TClosure
        -- in semantic IR.
        return Ty.TypeBackScalarKnown(Back.BackPtr)
    end

    local function type_to_back_scalar_result(ty)
        local shape = classify_api.classify(ty)
        return shape:lower_type_shape_to_back_scalar(ty)
    end

    local api = {
        scalar_to_back = function(scalar)
            return scalar:lower_core_scalar_to_back()
        end,
        type_to_back_scalar_result = type_to_back_scalar_result,
        result = type_to_back_scalar_result,
    }
    T._lalin_api_cache.type_to_back_scalar = api
    return api
end

return bind_context
