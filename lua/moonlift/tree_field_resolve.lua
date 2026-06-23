local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
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
            if not field then return erased.empty() end
            return erased.once(ref_for_field(field))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self, layout)

            local field = find_field(layout, self.name)
            if not field then return erased.empty() end
            return erased.once(ref_for_field(field))
            end)(node, ...)
        elseif schema.isa(node, H.HostFieldLayout) then
            return (function(self)

            return erased.once(ref_for_field(self))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_field_resolve: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function resolve(node, layout)
        local g, p, c = phase(node, layout)
        local values = pvm.drain(g, p, c)
        return values[1]
    end

    return {
        phase = phase,
        resolve = resolve,
        ty_from_rep = ty_from_rep,
    }
end

return M
