local pvm = require("moonlift.pvm")
local Mx = require("back.dasm.model")

local emit_phase = pvm.phase("moonlift_dasm_emit_dynasm", function(bundle)
    local D = Mx.dasm()
    return D.DEmitPlan({}, bundle.fragments or {}, {}, 0)
end)

return {
    phase = emit_phase,
    run = function(fragments)
        local D = Mx.dasm()
        local bundle = D.DFragmentBundle(fragments or {})
        return pvm.one(emit_phase(bundle))
    end,
}
