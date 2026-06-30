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
    local Ty = T.LalinType
    local B = T.LalinBind
    local Tr = T.LalinTree

    local expr_api = require("lalin.tree_expr_type")(T)

    local header_type
    local value_ref_type
    local index_base_elem_type
    local place_type

    local function first(g, p, c)
        local xs = g
        return xs[1]
    end

    function header_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceSurface) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceTyped) then
            return (function(self)
 return single(self.ty)
            end)(node, ...)
        else
            error("phase lalin_tree_place_header_type: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function value_ref_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(self)
 return single(self.binding.ty)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function()
 return {}
            end)(node, ...)
        else
            error("phase lalin_tree_place_value_ref_type: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function index_base_elem_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.IndexBaseExpr) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBasePlace) then
            return (function(self)
 return single(self.elem)
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBaseView) then
            return (function(self)
 return single(self.view.elem)
            end)(node, ...)
        else
            error("phase lalin_tree_index_base_elem_type: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    local function header_or(h, fallback)
        local ty = first(header_type(h))
        if ty ~= nil then return single(ty) end
        if fallback ~= nil then return single(fallback) end
        return {}
    end

    function place_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceRef) then
            return (function(self)

            local ty = first(header_type(self.h)) or first(value_ref_type(self.ref))
            if ty ~= nil then return single(ty) end
            return {}
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDeref) then
            return (function(self)

            local ty = first(header_type(self.h))
            if ty ~= nil then return single(ty) end
            local base_ty = expr_api.type(self.base)
            if schema.classof(base_ty) == Ty.TPtr then return single(base_ty.elem) end
            return {}
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self)
 return header_or(self.h, first(place_type(self.base)))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceField) then
            return (function(self)
 return header_or(self.h, self.field.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceIndex) then
            return (function(self)
 return header_or(self.h, first(index_base_elem_type(self.base)))
            end)(node, ...)
        else
            error("phase lalin_tree_place_type: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    return {
        header_type = header_type,
        value_ref_type = value_ref_type,
        index_base_elem_type = index_base_elem_type,
        place_type = place_type,
        type = function(place) return first(place_type(place)) end,
    }
end

return bind_context
