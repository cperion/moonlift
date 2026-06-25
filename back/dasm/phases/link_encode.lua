local pvm = require("lalin.pvm")

local link_phase = pvm.phase("lalin_dasm_link_encode", function(plan)
    return plan
end)

return {
    phase = link_phase,
    run = function(plan)
        return pvm.one(link_phase(plan))
    end,
}
