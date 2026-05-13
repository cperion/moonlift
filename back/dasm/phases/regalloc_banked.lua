local pvm = require("moonlift.pvm")
local regalloc = require("back.dasm.regalloc")
local Mx = require("back.dasm.model")

local function value_class(D, B, sk)
    local scalar = sk and B[sk] or B.BackI64
    if sk == "BackF32" or sk == "BackF64" then
        return D.DValueXmm(scalar)
    end
    return D.DValueGpr(scalar)
end

local regalloc_phase = pvm.phase("moonlift_dasm_regalloc_banked", function(pf, value_scalars)
    local D = Mx.dasm()
    local B = Mx.back()

    local body = Mx.phase_func_cmds(pf)
    local regmap, spilled, used_callee_saved, spill_sa = regalloc.allocate(body, value_scalars or {})

    local allocs = {}
    for key, reg in pairs(regmap or {}) do
        allocs[#allocs + 1] = D.DValueAlloc(
            D.DVirtualRegId(key),
            D.DLocReg(D.DPhysRegId(reg)),
            value_class(D, B, value_scalars and value_scalars[key])
        )
    end
    for key, off in pairs(spilled or {}) do
        allocs[#allocs + 1] = D.DValueAlloc(
            D.DVirtualRegId(key),
            D.DLocStack(off, 8, 8),
            value_class(D, B, value_scalars and value_scalars[key])
        )
    end

    local cs = {}
    for reg, yes in pairs(used_callee_saved or {}) do
        if yes then cs[#cs + 1] = D.DPhysRegId(reg) end
    end
    table.sort(cs, function(a, b) return a.number < b.number end)

    return D.DBankedRegalloc(allocs, cs, spill_sa or 0)
end)

return {
    phase = regalloc_phase,
    run = function(phase_func, value_scalars)
        local D = Mx.dasm()
        if pvm.classof(phase_func) ~= D.DPhaseFunc then
            error("regalloc_banked.run expects MoonDasm.DPhaseFunc", 2)
        end
        return pvm.one(regalloc_phase(phase_func, value_scalars or {}))
    end,
}
