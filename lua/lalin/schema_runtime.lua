-- Minimal LalinSchema runtime facade.
--
-- Generated phase code depends on this for schema value identity and
-- structural update instead of pulling in the legacy PVM phase/cache boundary.

local M = {}

M.NIL = {}

local SCHEMA_CONTEXT = nil

local function get_schema_context()
    if SCHEMA_CONTEXT ~= nil then return SCHEMA_CONTEXT end
    SCHEMA_CONTEXT = require("lalin.schema_context")
    return SCHEMA_CONTEXT
end

function M.context(opts)
    return get_schema_context().NewContext(opts)
end

function M.classof(node)
    if type(node) ~= "table" then return false end
    local mt = getmetatable(node)
    return (mt and mt.__class) or false
end

function M.class(value)
    return get_schema_context().Class(value)
end

function M.class_name(value)
    return get_schema_context().ClassName(value)
end

function M.class_basename(value)
    return get_schema_context().ClassBasename(value)
end

function M.context_of(value)
    return get_schema_context().ContextOf(value)
end

function M.fields(value)
    return get_schema_context().Fields(value)
end

function M.members(value)
    return get_schema_context().Members(value)
end

function M.is_sum_parent(value)
    return get_schema_context().IsSumParent(value)
end

function M.isa(node, class_or_singleton)
    local node_class = M.classof(node)
    if not node_class then return false end
    if node_class == class_or_singleton then return true end
    local target_class = M.class(class_or_singleton)
    if not target_class then return false end
    local members = M.members(target_class)
    return node_class == target_class or (members and members[node_class]) or false
end

function M.with(node, overrides)
    return get_schema_context().With(node, overrides, M.NIL)
end

return M
