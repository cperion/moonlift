local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.type_classify ~= nil then return T._moonlift_api_cache.type_classify end

    local Ty = T.MoonType

    local array_len_count
    local classify_type
    local classify_type_ref

    function array_len_count(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.ArrayLenConst) then
            return (function(self)

            return erased.once(self.count)
            end)(node, ...)
        elseif schema.isa(node, Ty.ArrayLenExpr) then
            return (function()

            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Ty.ArrayLenSlot) then
            return (function()

            return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_type_array_len_count: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function classify_type_ref(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TypeRefGlobal) then
            return (function(self)

            return erased.once(Ty.TypeClassAggregate(self.module_name, self.type_name))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefPath) then
            return (function()

            return erased.once(Ty.TypeClassUnknown)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefLocal) then
            return (function()

            return erased.once(Ty.TypeClassUnknown)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefSlot) then
            return (function()

            return erased.once(Ty.TypeClassUnknown)
            end)(node, ...)
        else
            error("erased phase moonlift_type_ref_classify: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function classify_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TScalar) then
            return (function(self)

            return erased.once(Ty.TypeClassScalar(self.scalar))
            end)(node, ...)
        elseif schema.isa(node, Ty.TPtr) then
            return (function(self)

            return erased.once(Ty.TypeClassPointer(self.elem))
            end)(node, ...)
        elseif schema.isa(node, Ty.TArray) then
            return (function(self)

            local counts = array_len_count(self.count)
            if #counts == 0 then
                return erased.once(Ty.TypeClassUnknown)
            end
            return erased.once(Ty.TypeClassArray(self.elem, counts[1]))
            end)(node, ...)
        elseif schema.isa(node, Ty.TSlice) then
            return (function(self)

            return erased.once(Ty.TypeClassSlice(self.elem))
            end)(node, ...)
        elseif schema.isa(node, Ty.TView) then
            return (function(self)

            return erased.once(Ty.TypeClassView(self.elem))
            end)(node, ...)
        elseif schema.isa(node, Ty.TLease) then
            return (function(self)

            return erased.once(Ty.TypeClassLease(self.base, self.origin))
            end)(node, ...)
        elseif schema.isa(node, Ty.TOwned) then
            return (function(self)

            return erased.once(Ty.TypeClassOwned(self.base))
            end)(node, ...)
        elseif schema.isa(node, Ty.TAccess) then
            return (function(self)

            return classify_type(self.base)
            end)(node, ...)
        elseif schema.isa(node, Ty.THandle) then
            return (function(self)

            return erased.once(Ty.TypeClassHandle(self.repr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TFunc) then
            return (function(self)

            return erased.once(Ty.TypeClassCallable(self.params, self.result))
            end)(node, ...)
        elseif schema.isa(node, Ty.TClosure) then
            return (function(self)

            return erased.once(Ty.TypeClassClosure(self.params, self.result))
            end)(node, ...)
        elseif schema.isa(node, Ty.TNamed) then
            return (function(self)

            return classify_type_ref(self.ref)
            end)(node, ...)
        elseif schema.isa(node, Ty.TSlot) then
            return (function()

            return erased.once(Ty.TypeClassUnknown)
            end)(node, ...)
        elseif schema.isa(node, Ty.TCType) then
            return (function()

            return erased.once(Ty.TypeClassUnknown)
            end)(node, ...)
        elseif schema.isa(node, Ty.TCFuncPtr) then
            return (function()

            return erased.once(Ty.TypeClassUnknown)
            end)(node, ...)
        else
            error("erased phase moonlift_type_classify: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local api = {
        array_len_count = array_len_count,
        classify_type_ref = classify_type_ref,
        classify_type = classify_type,
        classify = function(ty)
            return erased.one(classify_type(ty))
        end,
    }
    T._moonlift_api_cache.type_classify = api
    return api
end

return M
