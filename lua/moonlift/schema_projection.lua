-- MoonSchema runtime projection facade.
--
-- This defines the runtime class context from canonical MoonSchema Lua modules.
-- The internal projection value vocabulary is still MoonAsdl, but users enter
-- through MoonSchema and this projection facade, not through an ASDL source API.

local Schema = require("moonlift.schema")

local M = {}

function M.schema(T)
    return Schema.schema(T)
end

local function bind_context(T)
    return Schema(T)
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})