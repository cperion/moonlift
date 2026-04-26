local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local H = T.Moon2Host
    local Tr = T.Moon2Tree

    local phase = pvm.phase("moon2_mlua_loop_expand", {
        [H.MluaLoopControlStmt] = function(self)
            return pvm.once(H.MluaLoopExpandResult(self.region.entry, self.region.blocks, {}))
        end,
        [H.MluaLoopControlExpr] = function(self)
            return pvm.once(H.MluaLoopExpandResult(self.region.entry, self.region.blocks, {}))
        end,
        [Tr.ControlStmtRegion] = function(self)
            return pvm.once(H.MluaLoopExpandResult(self.entry, self.blocks, {}))
        end,
        [Tr.ControlExprRegion] = function(self)
            return pvm.once(H.MluaLoopExpandResult(self.entry, self.blocks, {}))
        end,
    })

    return {
        phase = phase,
        expand = function(loop_source) return pvm.one(phase(loop_source)) end,
    }
end

return M
