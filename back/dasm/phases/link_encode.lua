local pvm = require("moonlift.pvm")

local link_phase = pvm.phase("moonlift_dasm_link_encode", function(plan)
    return plan
end)

return {
    phase = link_phase,
    run = function(plan)
        return pvm.one(link_phase(plan))
    end,
}
