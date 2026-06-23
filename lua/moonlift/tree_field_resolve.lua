local schema = require("moonlift.schema_runtime")
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
    local H = T.MoonHost
    local Sem = T.MoonSem
    local Ty = T.MoonType
    local Tr = T.MoonTree
    local C = T.MoonCore

    local function ty_from_rep(rep)
        local cls = schema.classof(rep)
        if cls == H.HostRepScalar then return Ty.TScalar(rep.scalar) end
        if cls == H.HostRepBool then return Ty.TScalar(C.ScalarBool) end
        if cls == H.HostRepPtr then return Ty.TPtr(rep.pointee) end
        if cls == H.HostRepView then return Ty.TView(rep.elem) end
        if cls == H.HostRepSlice then return Ty.TSlice(Ty.TScalar(C.ScalarU8)) end
        return Ty.TScalar(C.ScalarRawPtr)
    end

    local function find_field(layout, name)
        for i = 1, #layout.fields do
            local field = layout.fields[i]
            if field.name == name or field.cfield == name then return field end
        end
        return nil
    end

    local function ref_for_field(field)
        return Sem.FieldByOffset(field.name, field.offset, ty_from_rep(field.rep), field.rep)
    end

    local function phase(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprDot) then
            return (function(self, layout)

            local field = find_field(layout, self.name)
            if not field then return {} end
            return single(ref_for_field(field))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self, layout)

            local field = find_field(layout, self.name)
            if not field then return {} end
            return single(ref_for_field(field))
            end)(node, ...)
        elseif schema.isa(node, H.HostFieldLayout) then
            return (function(self)

            return single(ref_for_field(self))
            end)(node, ...)
        else
            error("phase moonlift_tree_field_resolve: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function resolve(node, layout)
        local g, p, c = phase(node, layout)
        local values = g
        return values[1]
    end

    return {
        phase = phase,
        resolve = resolve,
        ty_from_rep = ty_from_rep,
    }
end

return bind_context