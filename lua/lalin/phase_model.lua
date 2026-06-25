-- Canonical compiler phase/wiring model, authored as LalinSchema data.

local S = require("lalin.schema.dsl")

local M = {}

local function phase_module()
    return require("lalin.schema.phase")
end

function M.schema(T)
    return S.to_asdl_schema(T, { phase_module() })
end

local function bind_context(T)
    if T.LalinPhase ~= nil then return T end
    return S.define(T, { phase_module() })
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})