-- Thin public facade for ASDL-backed hosted value construction.
-- Semantic construction lives in host_*_values.lua; this module only exposes a
-- default session plus constructors for explicit sessions.

local Session = require("moonlift.host_session")

local default_session = Session.new({ prefix = "default" })
local M = default_session:api()
M.default_session = default_session
M.region_compose = require("moonlift.region_compose")
M.parser_compose = require("moonlift.parser_compose")

function M.new_session(opts)
    return Session.new(opts)
end

function M.session(opts)
    return Session.new(opts)
end

function M.classify_type(ty)
    return default_session:classify_type(ty)
end

function M.size_align(ty, env)
    return default_session:size_align(ty, env)
end

function M.abi_of(ty, env)
    return default_session:abi_of(ty, env)
end

function M.layout_of(ty)
    return default_session:layout_of(ty)
end

return M
