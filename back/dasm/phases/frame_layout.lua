local pvm = require("lalin.pvm")
local Mx = require("back.dasm.model")

local frame_phase = pvm.phase("lalin_dasm_frame_layout", function(alloc, slot_sa)
    local D = Mx.dasm()

    local spill = alloc and alloc.spill_size or 0
    local slot = slot_sa or 0
    local total = spill + slot
    if total % 16 ~= 0 then total = total + (16 - (total % 16)) end

    return D.DFramePlan(total, spill, slot, alloc and alloc.used_callee_saved or {}, {})
end)

return {
    phase = frame_phase,
    run = function(alloc, slot_sa)
        return pvm.one(frame_phase(alloc, slot_sa))
    end,
}
