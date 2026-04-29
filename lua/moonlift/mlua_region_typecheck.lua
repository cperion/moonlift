local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = (T.MoonHost or T.Moon2Host)
    local O = (T.MoonOpen or T.Moon2Open)

    local phase = pvm.phase("moon2_mlua_region_typecheck", {
        [O.RegionFrag] = function(self)
            -- The current RegionFrag ASDL already carries typed OpenParam and
            -- continuation slot declarations. Deeper jump/yield validation is
            -- performed by tree_control_facts/tree_typecheck after expansion;
            -- this phase is the explicit .mlua boundary that records the region
            -- protocol result as an ASDL value.
            return pvm.once(H.MluaRegionTypeResult(self, {}))
        end,
    })

    return {
        phase = phase,
        check = function(frag) return pvm.one(phase(frag)) end,
    }
end

return M
