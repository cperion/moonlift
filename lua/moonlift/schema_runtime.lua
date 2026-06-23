-- Minimal MoonSchema runtime facade.
--
-- Generated/erased phase code depends on this for schema value identity and
-- structural update instead of pulling in the legacy PVM phase/cache boundary.

local M = {}

M.NIL = {}

local SCHEMA_CONTEXT = nil

local function get_schema_context()
    if SCHEMA_CONTEXT ~= nil then return SCHEMA_CONTEXT end
    SCHEMA_CONTEXT = require("moonlift.schema_context")
    return SCHEMA_CONTEXT
end

function M.context(opts)
    local ctx = get_schema_context().NewContext(opts)
    local orig = ctx.Define
    function ctx:Define(text)
        orig(self, text)
        return self
    end
    return ctx
end

function M.classof(node)
    if type(node) ~= "table" then return false end
    local mt = getmetatable(node)
    return (mt and mt.__class) or false
end

function M.class(value)
    if type(value) ~= "table" then return false end
    if rawget(value, "__class") == value then return value end
    return M.classof(value)
end

function M.isa(node, class_or_singleton)
    local node_class = M.classof(node)
    if not node_class then return false end
    if node_class == class_or_singleton then return true end
    local target_class = M.class(class_or_singleton)
    if not target_class then return false end
    return node_class == target_class or (target_class.members and target_class.members[node_class]) or false
end

function M.with(node, overrides)
    local cls = M.classof(node)
    if not cls or not cls.__fields then
        error("schema.with: not a schema node", 2)
    end
    return cls.__with(node, overrides, M.NIL)
end

return M
