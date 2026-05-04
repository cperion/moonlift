-- MoonLift standard library facade.

local M = {}

M.pvm = require("moonlift.pvm")
M.host = require("moonlift.host")
M.mlua = require("moonlift.host_quote")
M.views = require("moonlift.buffer_view")
M.buffer_view = M.views
M.region_compose = require("moonlift.region_compose")
M.compose = M.region_compose

local Json = {}
M.json = Json

local json_mod = nil
local function hosted_json()
    if json_mod == nil then json_mod = require("json") end
    return json_mod
end

function Json.decode(src)
    return hosted_json().decode(src)
end

function Json.free()
    if json_mod and json_mod.free then json_mod.free() end
    json_mod = nil
end

Json.null = nil

local Builtins = {}
M.builtins = Builtins

function Builtins.source(name)
    error("MoonLift builtin source access was removed for `" .. tostring(name) .. "`; use hosted runtime libraries", 2)
end

function Builtins.compile(name, opts)
    error("MoonLift builtin compilation was removed for `" .. tostring(name) .. "`; use hosted runtime libraries", 2)
end

return M
