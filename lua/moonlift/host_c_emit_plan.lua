local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = (T.MoonHost or T.Moon2Host)

    local phase = pvm.phase("moon2_host_c_emit_plan", {
        [H.HostFactSet] = function(self, header_name)
            local layouts, views, sources = {}, {}, {}
            for i = 1, #self.facts do
                local fact = self.facts[i]
                local cls = pvm.classof(fact)
                if cls == H.HostFactTypeLayout then
                    layouts[#layouts + 1] = fact.layout
                elseif cls == H.HostFactViewDescriptor then
                    views[#views + 1] = fact.descriptor
                elseif cls == H.HostFactCdef then
                    sources[#sources + 1] = fact.cdef.source
                end
            end
            return pvm.once(H.HostCPlan(header_name or "moon2_host.h", table.concat(sources, "\n\n"), layouts, views))
        end,
    }, { args_cache = "full" })

    local function plan(facts, header_name)
        return pvm.one(phase(facts, header_name or "moon2_host.h"))
    end

    return {
        phase = phase,
        plan = plan,
    }
end

return M
