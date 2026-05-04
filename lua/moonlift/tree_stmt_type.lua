local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local B = T.MoonBind
    local Tr = T.MoonTree

    local stmt_env_effect

    stmt_env_effect = pvm.phase("moonlift_tree_stmt_env_effect", {
        [Tr.StmtLet] = function(self) return pvm.once(B.StmtEnvAddBinding(B.ValueEntry(self.binding.name, self.binding))) end,
        [Tr.StmtVar] = function(self) return pvm.once(B.StmtEnvAddBinding(B.ValueEntry(self.binding.name, self.binding))) end,
        [Tr.StmtSet] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtExpr] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtAssert] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtIf] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtSwitch] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtJump] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtYieldVoid] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtYieldValue] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtReturnVoid] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtReturnValue] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtControl] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtUseRegionSlot] = function() return pvm.once(B.StmtEnvNoBinding) end,
        [Tr.StmtUseRegionFrag] = function() return pvm.once(B.StmtEnvNoBinding) end,
    })

    return {
        stmt_env_effect = stmt_env_effect,
        effect = function(stmt) return pvm.one(stmt_env_effect(stmt)) end,
    }
end

return M
