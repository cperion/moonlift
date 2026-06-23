local schema = require("moonlift.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function bind_context(T)
    local B = T.MoonBind
    local Tr = T.MoonTree

    local stmt_env_effect

    function stmt_env_effect(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtLet) then
            return (function(self)
 return single(B.StmtEnvAddBinding(B.ValueEntry(self.binding.name, self.binding)))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function(self)
 return single(B.StmtEnvAddBinding(B.ValueEntry(self.binding.name, self.binding)))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJump) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function()
 return single(B.StmtEnvNoBinding)
            end)(node, ...)
        else
            error("phase moonlift_tree_stmt_env_effect: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        stmt_env_effect = stmt_env_effect,
        effect = function(stmt) return only(stmt_env_effect(stmt)) end,
    }
end

return bind_context