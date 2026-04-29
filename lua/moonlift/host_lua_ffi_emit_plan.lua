local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = (T.MoonHost or T.Moon2Host)

    local phase = pvm.phase("moon2_host_lua_ffi_emit_plan", {
        [H.HostFactSet] = function(self, module_name)
            local cdefs, access_plans = {}, {}
            for i = 1, #self.facts do
                local fact = self.facts[i]
                local cls = pvm.classof(fact)
                if cls == H.HostFactCdef then
                    cdefs[#cdefs + 1] = fact.cdef
                elseif cls == H.HostFactAccessPlan then
                    access_plans[#access_plans + 1] = fact.plan
                end
            end
            return pvm.once(H.HostLuaFfiPlan(module_name or "moon2_host", cdefs, access_plans))
        end,
    }, { args_cache = "full" })

    local function plan(facts, module_name)
        return pvm.one(phase(facts, module_name or "moon2_host"))
    end

    return {
        phase = phase,
        plan = plan,
    }
end

return M
