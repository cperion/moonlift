local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local B = T.MoonBind
    local Tr = T.MoonTree

    local stmt_env_effect

    function stmt_env_effect(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtLet) then
            return (function(self)
 return erased.once(B.StmtEnvAddBinding(B.ValueEntry(self.binding.name, self.binding)))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function(self)
 return erased.once(B.StmtEnvAddBinding(B.ValueEntry(self.binding.name, self.binding)))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJump) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function()
 return erased.once(B.StmtEnvNoBinding)
            end)(node, ...)
        else
            error("erased phase moonlift_tree_stmt_env_effect: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        stmt_env_effect = stmt_env_effect,
        effect = function(stmt) return erased.one(stmt_env_effect(stmt)) end,
    }
end

return M
