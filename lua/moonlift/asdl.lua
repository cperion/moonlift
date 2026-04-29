-- Canonical Moonlift schema facade.
--
-- The source of truth is the Lua-hosted schema-as-data modules under
-- lua/moonlift/schema/.  This facade intentionally defines the clean Moon*
-- namespace, not historical Moon* modules.

local Schema = require("moonlift.schema")

local M = {}

function M.schema(T)
    return Schema.schema(T)
end

function M.Define(T)
    return Schema.Define(T)
end

return M
