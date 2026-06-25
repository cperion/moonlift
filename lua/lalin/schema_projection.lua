-- LalinSchema runtime projection facade.
--
-- This defines the runtime class context from canonical LalinSchema Lua modules.
-- The internal projection value vocabulary is still LalinAsdl, but users enter
-- through LalinSchema and this projection facade, not through an ASDL source API.

local Schema = require("lalin.schema")

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