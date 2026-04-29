local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = (T.MoonHost or T.Moon2Host)
    local Sem = (T.MoonSem or T.Moon2Sem)
    local Ty = (T.MoonType or T.Moon2Type)
    local Tr = (T.MoonTree or T.Moon2Tree)
    local C = (T.MoonCore or T.Moon2Core)

    local function ty_from_rep(rep)
        local cls = pvm.classof(rep)
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

    local phase = pvm.phase("moon2_tree_field_resolve", {
        [Tr.ExprDot] = function(self, layout)
            local field = find_field(layout, self.name)
            if not field then return pvm.empty() end
            return pvm.once(ref_for_field(field))
        end,
        [Tr.PlaceDot] = function(self, layout)
            local field = find_field(layout, self.name)
            if not field then return pvm.empty() end
            return pvm.once(ref_for_field(field))
        end,
        [H.HostFieldLayout] = function(self)
            return pvm.once(ref_for_field(self))
        end,
    }, { args_cache = "full" })

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
