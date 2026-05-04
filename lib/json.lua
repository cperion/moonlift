-- Canonical MoonLift hosted JSON decoder.
--
-- Requires the hosted runtime (`cargo run --bin moonlift -- ...`). The decoder
-- parses JSON and builds real Lua values directly from compiled MoonLift via the
-- Lua C API.

local Host = require("moonlift.mlua_run")

if not _M_HOSTED then
    error("lib/json.lua requires the hosted MoonLift runtime", 2)
end

local mod = Host.dofile("lib/json_meta_decode.mlua")
local compiled = mod:compile()

local M = {}
M.null = nil

function M.decode(str)
    if type(str) ~= "string" then error("expected string", 2) end
    return compiled.artifact:call("json_decode_lua", str)
end

function M.free()
    if compiled then
        compiled:free()
        compiled = nil
    end
end

return M
