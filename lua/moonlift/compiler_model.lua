-- Canonical compiler-world model used by MoonPhase compiler packages.

local Schema = require("moonlift.schema")

local M = {}

function M.schema(T)
    return Schema.schema(T)
end

local function bind_context(T)
    if T.MoonCompiler ~= nil then return T end
    return Schema(T)
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})