local M = {}

local PlaceValue = {}
PlaceValue.__index = PlaceValue
PlaceValue.__moonlift_host_place_value = true

local function get_place_value(v)
    if type(v) ~= "table" then return nil end
    local mt = getmetatable(v)
    if mt == PlaceValue then return v end
    if mt and mt.__moonlift_host_place_value and type(v.as_place_value) == "function" then return v:as_place_value() end
    return nil
end

function PlaceValue:as_place_value()
    return self
end

function PlaceValue:as_moonlift_place()
    return self.place
end

function PlaceValue:__tostring()
    return "MoonPlaceValue(" .. tostring(self.source_hint or self.place) .. ")"
end

function M.Install(api, session)
    local T = session.T
    local B, Tr = T.MoonBind, T.MoonTree

    local function place_value(place, ty, source_hint, extra)
        local v = extra or {}
        v.kind = "place"
        v.session = session
        v.place = place
        v.type = ty and api.as_type_value(ty, "place type must be a type value") or nil
        v.source_hint = source_hint
        return setmetatable(v, PlaceValue)
    end

    local function coerce(v, site)
        local p = get_place_value(v)
        if p then return p end
        error((site or "expected place value") .. ": got " .. type(v), 3)
    end

    function api.place_from_asdl(place, ty, source_hint, extra)
        return place_value(place, ty, source_hint, extra)
    end

    function api.as_place_value(v, site)
        return coerce(v, site)
    end

    function api.as_moonlift_place(v, site)
        return coerce(v, site).place
    end

    function api.place_ref(binding, ty, source_hint)
        return place_value(Tr.PlaceRef(Tr.PlaceSurface, B.ValueRefBinding(binding)), ty, source_hint or binding.name, { binding = binding })
    end

    local ExprValue = api.ExprValue

    function ExprValue:place()
        assert(self.binding ~= nil, "only binding-backed expression values can be viewed as places")
        return api.place_ref(self.binding, self.type, self.source_hint)
    end

    function ExprValue:index_place(index)
        local idx = api.as_expr_value(index, "index_place expects expression index")
        local elem_ty = self.element_type
        assert(elem_ty ~= nil, "index_place requires the base expression to carry element type metadata")
        return place_value(Tr.PlaceIndex(Tr.PlaceSurface, Tr.IndexBaseExpr(self.expr), idx.expr), elem_ty, (self.source_hint or "<expr>") .. "[" .. (idx.source_hint or "<idx>") .. "]")
    end

    function ExprValue:deref_place()
        local pointee = self.pointee_type or self.element_type
        assert(pointee ~= nil, "deref_place requires the expression to carry pointee type metadata")
        return place_value(Tr.PlaceDeref(Tr.PlaceSurface, self.expr), pointee, "*(" .. tostring(self.source_hint or "<expr>") .. ")")
    end

    function PlaceValue:field(name, ty)
        assert(type(name) == "string" and name ~= "", "place field expects a field name")
        local field_ty = ty
        if field_ty == nil and self.type and self.type.fields_by_name then field_ty = self.type.fields_by_name[name] end
        assert(field_ty ~= nil, "place field type is required unless the base place carries struct field metadata")
        local ft = api.as_type_value(field_ty, "place field type must be a type value")
        return place_value(Tr.PlaceField(Tr.PlaceSurface, self.place, T.MoonSem.FieldByName(name, ft.ty)), ft, (self.source_hint or "<place>") .. "." .. name)
    end

    api.PlaceValue = PlaceValue
end

return M
