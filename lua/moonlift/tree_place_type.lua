local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local Ty = T.MoonType
    local B = T.MoonBind
    local O = T.MoonOpen
    local Tr = T.MoonTree

    local expr_api = require("moonlift.tree_expr_type").Define(T)

    local header_type
    local value_ref_type
    local index_base_elem_type
    local place_type

    local function first(g, p, c)
        local xs = pvm.drain(g, p, c)
        return xs[1]
    end

    function header_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceSurface) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceTyped) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceOpen) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        else
            error("erased phase moonlift_tree_place_header_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function value_ref_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(self)
 return erased.once(self.binding.ty)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefHole) then
            return (function(self)

            local slot_cls = schema.classof(self.slot)
            if slot_cls == O.SlotFunc then return erased.once(self.slot.slot.fn_ty) end
            if slot_cls == O.SlotValue or slot_cls == O.SlotConst or slot_cls == O.SlotStatic then return erased.once(self.slot.slot.ty) end
            if slot_cls == O.SlotExpr or slot_cls == O.SlotPlace then return erased.once(self.slot.slot.ty or nil) end
            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_tree_place_value_ref_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function index_base_elem_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.IndexBaseExpr) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBasePlace) then
            return (function(self)
 return erased.once(self.elem)
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBaseView) then
            return (function(self)
 return erased.once(self.view.elem)
            end)(node, ...)
        else
            error("erased phase moonlift_tree_index_base_elem_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function header_or(h, fallback)
        local ty = first(header_type(h))
        if ty ~= nil then return pvm.once(ty) end
        if fallback ~= nil then return pvm.once(fallback) end
        return pvm.empty()
    end

    function place_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceRef) then
            return (function(self)

            local ty = first(header_type(self.h)) or first(value_ref_type(self.ref))
            if ty ~= nil then return erased.once(ty) end
            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDeref) then
            return (function(self)

            local ty = first(header_type(self.h))
            if ty ~= nil then return erased.once(ty) end
            local base_ty = expr_api.type(self.base)
            if schema.classof(base_ty) == Ty.TPtr then return erased.once(base_ty.elem) end
            return erased.empty()
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
        elseif schema.isa(node, Tr.PlaceSlotValue) then
            return (function(self)
 return header_or(self.h, self.slot.ty)
            end)(node, ...)
        else
            error("erased phase moonlift_tree_place_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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

return M
