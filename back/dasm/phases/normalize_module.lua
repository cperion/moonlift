local pvm = require("moonlift.pvm")
local Mx = require("back.dasm.model")

local PHASE = nil
local function phase()
    if PHASE then return PHASE end
    local D = Mx.dasm()

    PHASE = pvm.phase("moonlift_dasm_normalize_module", {
        [D.DPhaseModule] = function(mod)
            local d = Mx.phase_module_maps(mod)

            local fkeys, ekeys, dkeys = {}, {}, {}
            for i = 1, #d.fkeys do fkeys[i] = d.fkeys[i] end
            for i = 1, #d.ekeys do ekeys[i] = d.ekeys[i] end
            for i = 1, #d.dkeys do dkeys[i] = d.dkeys[i] end
            table.sort(fkeys)
            table.sort(ekeys)
            table.sort(dkeys)

            local labels = { funcs = {}, externs = {}, datas = {} }
            for i, k in ipairs(fkeys) do labels.funcs[k] = "->F_" .. tostring(i) .. "_" .. Mx.to_label(k) end
            for i, k in ipairs(ekeys) do labels.externs[k] = "->E_" .. tostring(i) .. "_" .. Mx.to_label(k) end
            for i, k in ipairs(dkeys) do labels.datas[k] = "->D_" .. tostring(i) .. "_" .. Mx.to_label(k) end

            return pvm.once(Mx.make_phase_module(d.sigs, d.funcs, d.externs, d.datas, fkeys, ekeys, dkeys, labels))
        end,
    })

    return PHASE
end

return {
    phase = function() return phase() end,
    run = function(mod)
        return pvm.one(phase()(mod))
    end,
}
