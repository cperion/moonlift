local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Ty = (T.MoonType or T.Moon2Type)
    local B = (T.MoonBind or T.Moon2Bind)
    local Tr = (T.MoonTree or T.Moon2Tree)

    local expr_api = require("moonlift.tree_expr_type").Define(T)

    local header_type
    local value_ref_type
    local index_base_elem_type
    local place_type

    local function first(g, p, c)
        local xs = pvm.drain(g, p, c)
        return xs[1]
    end

    header_type = pvm.phase("moon2_tree_place_header_type", {
        [Tr.PlaceSurface] = function() return pvm.empty() end,
        [Tr.PlaceTyped] = function(self) return pvm.once(self.ty) end,
        [Tr.PlaceOpen] = function(self) return pvm.once(self.ty) end,
        [Tr.PlaceSem] = function(self) return pvm.once(self.ty) end,
    })

    value_ref_type = pvm.phase("moon2_tree_place_value_ref_type", {
        [B.ValueRefBinding] = function(self) return pvm.once(self.binding.ty) end,
        [B.ValueRefSlot] = function(self) return pvm.once(self.slot.ty) end,
        [B.ValueRefFuncSlot] = function(self) return pvm.once(self.slot.fn_ty) end,
        [B.ValueRefConstSlot] = function(self) return pvm.once(self.slot.ty) end,
        [B.ValueRefStaticSlot] = function(self) return pvm.once(self.slot.ty) end,
        [B.ValueRefName] = function() return pvm.empty() end,
        [B.ValueRefPath] = function() return pvm.empty() end,
    })

    index_base_elem_type = pvm.phase("moon2_tree_index_base_elem_type", {
        [Tr.IndexBaseExpr] = function() return pvm.empty() end,
        [Tr.IndexBasePlace] = function(self) return pvm.once(self.elem) end,
        [Tr.IndexBaseView] = function(self) return pvm.once(self.view.elem) end,
    })

    local function header_or(h, fallback)
        local ty = first(header_type(h))
        if ty ~= nil then return pvm.once(ty) end
        if fallback ~= nil then return pvm.once(fallback) end
        return pvm.empty()
    end

    place_type = pvm.phase("moon2_tree_place_type", {
        [Tr.PlaceRef] = function(self)
            local ty = first(header_type(self.h)) or first(value_ref_type(self.ref))
            if ty ~= nil then return pvm.once(ty) end
            return pvm.empty()
        end,
        [Tr.PlaceDeref] = function(self)
            local ty = first(header_type(self.h))
            if ty ~= nil then return pvm.once(ty) end
            local base_ty = expr_api.type(self.base)
            if pvm.classof(base_ty) == Ty.TPtr then return pvm.once(base_ty.elem) end
            return pvm.empty()
        end,
        [Tr.PlaceDot] = function(self) return header_or(self.h, first(place_type(self.base))) end,
        [Tr.PlaceField] = function(self) return header_or(self.h, self.field.ty) end,
        [Tr.PlaceIndex] = function(self) return header_or(self.h, first(index_base_elem_type(self.base))) end,
        [Tr.PlaceSlotValue] = function(self) return header_or(self.h, self.slot.ty) end,
    })

    return {
        header_type = header_type,
        value_ref_type = value_ref_type,
        index_base_elem_type = index_base_elem_type,
        place_type = place_type,
        type = function(place) return first(place_type(place)) end,
    }
end

return M
