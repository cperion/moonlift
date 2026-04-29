local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.type_classify ~= nil then return T._moonlift_api_cache.type_classify end

    local Ty = T.Moon2Type

    local array_len_count
    local classify_type
    local classify_type_ref

    array_len_count = pvm.phase("moon2_type_array_len_count", {
        [Ty.ArrayLenConst] = function(self)
            return pvm.once(self.count)
        end,
        [Ty.ArrayLenExpr] = function()
            return pvm.empty()
        end,
        [Ty.ArrayLenSlot] = function()
            return pvm.empty()
        end,
    })

    classify_type_ref = pvm.phase("moon2_type_ref_classify", {
        [Ty.TypeRefGlobal] = function(self)
            return pvm.once(Ty.TypeClassAggregate(self.module_name, self.type_name))
        end,
        [Ty.TypeRefPath] = function()
            return pvm.once(Ty.TypeClassUnknown)
        end,
        [Ty.TypeRefLocal] = function()
            return pvm.once(Ty.TypeClassUnknown)
        end,
        [Ty.TypeRefSlot] = function()
            return pvm.once(Ty.TypeClassUnknown)
        end,
    })

    classify_type = pvm.phase("moon2_type_classify", {
        [Ty.TScalar] = function(self)
            return pvm.once(Ty.TypeClassScalar(self.scalar))
        end,
        [Ty.TPtr] = function(self)
            return pvm.once(Ty.TypeClassPointer(self.elem))
        end,
        [Ty.TArray] = function(self)
            local counts = pvm.drain(array_len_count(self.count))
            if #counts == 0 then
                return pvm.once(Ty.TypeClassUnknown)
            end
            return pvm.once(Ty.TypeClassArray(self.elem, counts[1]))
        end,
        [Ty.TSlice] = function(self)
            return pvm.once(Ty.TypeClassSlice(self.elem))
        end,
        [Ty.TView] = function(self)
            return pvm.once(Ty.TypeClassView(self.elem))
        end,
        [Ty.TFunc] = function(self)
            return pvm.once(Ty.TypeClassCallable(self.params, self.result))
        end,
        [Ty.TClosure] = function(self)
            return pvm.once(Ty.TypeClassClosure(self.params, self.result))
        end,
        [Ty.TNamed] = function(self)
            return classify_type_ref(self.ref)
        end,
        [Ty.TSlot] = function()
            return pvm.once(Ty.TypeClassUnknown)
        end,
    })

    local api = {
        array_len_count = array_len_count,
        classify_type_ref = classify_type_ref,
        classify_type = classify_type,
        classify = function(ty)
            return pvm.one(classify_type(ty))
        end,
    }
    T._moonlift_api_cache.type_classify = api
    return api
end

return M
