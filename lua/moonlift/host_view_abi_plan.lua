local pvm = require("moonlift.pvm")
local HostLayoutFacts = require("moonlift.host_layout_facts")

local M = {}

local function last_path_part(path)
    if not path or not path.parts or #path.parts == 0 then return nil end
    return path.parts[#path.parts].text
end

function M.Define(T)
    local H = (T.MoonHost or T.Moon2Host)
    local Ty = (T.MoonType or T.Moon2Type)
    local HF = HostLayoutFacts.Define(T)

    local function layout_name_for_type(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TNamed then
            local ref = ty.ref
            local rcls = pvm.classof(ref)
            if rcls == Ty.TypeRefGlobal then return ref.type_name end
            if rcls == Ty.TypeRefLocal then return ref.sym.name end
            if rcls == Ty.TypeRefPath then return last_path_part(ref.path) end
        end
        return nil
    end

    local function find_layout(env, ty)
        local name = layout_name_for_type(ty)
        if name == nil then return nil end
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            if layout.name == name or layout.ctype == name then return layout end
        end
        return nil
    end

    local function descriptor_for_elem(elem_ty, env, opts)
        local layout = find_layout(env, elem_ty)
        if not layout then return nil end
        local descriptor, cdef = HF.view_descriptor_for_layout(layout, opts or { name = layout.name .. "View" })
        return descriptor, cdef, layout
    end

    local subject_phase = pvm.phase("moon2_host_view_abi_plan_subject", {
        [H.HostExposeType] = function(self, env)
            local layout = find_layout(env, self.ty)
            if layout then return pvm.once(layout) end
            return pvm.empty()
        end,
        [H.HostExposePtr] = function(self, env)
            local layout = find_layout(env, self.pointee)
            if layout then return pvm.once(layout) end
            return pvm.empty()
        end,
        [H.HostExposeView] = function(self, env)
            local descriptor = descriptor_for_elem(self.elem, env)
            if descriptor then return pvm.once(descriptor) end
            return pvm.empty()
        end,
    }, { args_cache = "full" })

    local expose_fact_phase = pvm.phase("moon2_host_view_abi_plan", {
        [H.HostExposeDecl] = function(self, env, target)
            local facts = {}
            if pvm.classof(self.subject) == H.HostExposeView then
                local descriptor, cdef = descriptor_for_elem(self.subject.elem, env, { name = self.public_name, target_model = target })
                if descriptor then
                    local layout = descriptor.descriptor_layout
                    facts[#facts + 1] = H.HostFactTypeLayout(layout)
                    facts[#facts + 1] = H.HostFactCdef(cdef)
                    for i = 1, #layout.fields do
                        facts[#facts + 1] = H.HostFactField(layout.id, layout.fields[i])
                    end
                    facts[#facts + 1] = H.HostFactViewDescriptor(descriptor)
                    for i = 1, #self.facets do
                        facts[#facts + 1] = H.HostFactExpose(self.public_name, descriptor.id, self.facets[i])
                    end
                else
                    for i = 1, #self.facets do
                        facts[#facts + 1] = H.HostFactExpose(self.public_name, H.HostLayoutId(self.public_name, self.public_name), self.facets[i])
                    end
                end
            else
                local g, p, c = subject_phase(self.subject, env)
                local resolved_values = pvm.drain(g, p, c)
                local resolved = resolved_values[1]
                local layout_id = H.HostLayoutId(self.public_name, self.public_name)
                if resolved ~= nil and pvm.classof(resolved) == H.HostTypeLayout then layout_id = resolved.id end
                for i = 1, #self.facets do
                    facts[#facts + 1] = H.HostFactExpose(self.public_name, layout_id, self.facets[i])
                end
            end
            return pvm.T.seq(facts)
        end,
    }, { args_cache = "full" })

    local function plan_subject(subject, env)
        local g, p, c = subject_phase(subject, env)
        local values = pvm.drain(g, p, c)
        return values[1]
    end

    local function plan_facts(expose, env, target)
        local g, p, c = expose_fact_phase(expose, env, target)
        return H.HostFactSet(pvm.drain(g, p, c))
    end

    return {
        subject_phase = subject_phase,
        phase = expose_fact_phase,
        layout_name_for_type = layout_name_for_type,
        find_layout = find_layout,
        plan_subject = plan_subject,
        plan_facts = plan_facts,
    }
end

return M
