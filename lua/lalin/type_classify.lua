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
    if T._lalin_api_cache.type_classify ~= nil then return T._lalin_api_cache.type_classify end

    local Ty = T.LalinType

    local array_len_count
    local classify_type
    local classify_type_ref

    function array_len_count(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.ArrayLenConst) then
            return (function(self)

            return single(self.count)
            end)(node, ...)
        elseif schema.isa(node, Ty.ArrayLenExpr) then
            return (function()

            return {}
            end)(node, ...)
        else
            error("phase lalin_type_array_len_count: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function classify_type_ref(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TypeRefGlobal) then
            return (function(self)

            return single(Ty.TypeShapeAggregate(self.module_name, self.type_name))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefPath) then
            return (function()

            return single(Ty.TypeShapeUnknown)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefLocal) then
            return (function()

            return single(Ty.TypeShapeUnknown)
            end)(node, ...)
        else
            error("phase lalin_type_ref_classify: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function classify_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TScalar) then
            return (function(self)

            return single(Ty.TypeShapeScalar(self.scalar))
            end)(node, ...)
        elseif schema.isa(node, Ty.TPtr) then
            return (function(self)

            return single(Ty.TypeShapePointer(self.elem))
            end)(node, ...)
        elseif schema.isa(node, Ty.TArray) then
            return (function(self)

            local counts = array_len_count(self.count)
            if #counts == 0 then
                return single(Ty.TypeShapeUnknown)
            end
            return single(Ty.TypeShapeArray(self.elem, counts[1]))
            end)(node, ...)
        elseif schema.isa(node, Ty.TSlice) then
            return (function(self)

            return single(Ty.TypeShapeSlice(self.elem))
            end)(node, ...)
        elseif schema.isa(node, Ty.TView) then
            return (function(self)

            return single(Ty.TypeShapeView(self.elem))
            end)(node, ...)
        elseif schema.isa(node, Ty.TLease) then
            return (function(self)

            return single(Ty.TypeShapeLease(self.base, self.origin))
            end)(node, ...)
        elseif schema.isa(node, Ty.TOwned) then
            return (function(self)

            return single(Ty.TypeShapeOwned(self.base))
            end)(node, ...)
        elseif schema.isa(node, Ty.TAccess) then
            return (function(self)

            return classify_type(self.base)
            end)(node, ...)
        elseif schema.isa(node, Ty.THandle) then
            return (function(self)

            return single(Ty.TypeShapeHandle(self.repr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TFunc) then
            return (function(self)

            return single(Ty.TypeShapeCallable(self.params, self.result))
            end)(node, ...)
        elseif schema.isa(node, Ty.TClosure) then
            return (function(self)

            return single(Ty.TypeShapeClosure(self.params, self.result))
            end)(node, ...)
        elseif schema.isa(node, Ty.TNamed) then
            return (function(self)

            return classify_type_ref(self.ref)
            end)(node, ...)
        elseif schema.isa(node, Ty.TCType) then
            return (function()

            return single(Ty.TypeShapeUnknown)
            end)(node, ...)
        elseif schema.isa(node, Ty.TCFuncPtr) then
            return (function()

            return single(Ty.TypeShapeUnknown)
            end)(node, ...)
        else
            error("phase lalin_type_classify: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    local api = {
        array_len_count = array_len_count,
        classify_type_ref = classify_type_ref,
        classify_type = classify_type,
        classify = function(ty)
            return only(classify_type(ty))
        end,
    }
    T._lalin_api_cache.type_classify = api
    return api
end

return bind_context
