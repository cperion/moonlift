-- Define ASDL context modules from MoonAsdl.Schema data.
--
-- This first implementation deliberately bridges through the existing ASDL text
-- parser.  It makes schema-as-data the source boundary now, while keeping direct
-- context construction as a later implementation detail.

local pvm = require("moonlift.pvm")
local Emit = require("moonlift.asdl_emit")

local M = {}

function M.define(T, schema)
    local A = assert(T.MoonAsdl, "context_define_schema.define expects MoonAsdl to be defined in the context")
    if pvm.classof(schema) ~= A.Schema then error("context_define_schema.define expects MoonAsdl.Schema", 2) end
    local text = Emit.emit_with(A, schema)
    T:Define(text)
    return T, text
end

return M
