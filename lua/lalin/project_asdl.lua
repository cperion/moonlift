-- Project tracking schema projection.

local S = require("lalin.schema.dsl")

local M = {}

local function project_module()
    return require("lalin.schema.project")
end

function M.schema(T)
    return S.to_asdl_schema(T, { project_module() })
end

local function bind_context(T)
    if T.LalinProject ~= nil then return T end
    return S.define(T, { project_module() })
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})