-- Canonical compiler-world model used by LalinPhase compiler packages.

local Schema = require("lalin.schema")

local M = {}

function M.schema(T)
    return Schema.schema(T)
end

local function bind_context(T)
    if T.LalinCompiler ~= nil then return T end
    return Schema(T)
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})