-- MOM schema: load all ASDL schema modules.
-- Registers .mlua modules into package.preload so cyclic .mlua files can
-- require() them despite being .mlua (not .lua) files.

local Host = require("moonlift.mlua_run")

local DIR = "experiments/mom/schema/"

local cache = {}

local function preload(name)
    if cache[name] then return cache[name] end
    local path = DIR .. name .. ".mlua"
    local ok, mod = pcall(Host.dofile, path)
    if ok then
        cache[name] = mod
        package.preload["mom.schema." .. name] = function() return mod end
    else
        io.stderr:write("mom: " .. name .. " FAIL (" .. tostring(mod) .. ")\n")
    end
    return mod
end

-- Load in dependency order
preload("MoonCore")
preload("MoonBack")
preload("MoonSource")
preload("MoonLink")
preload("MoonCyclic")  -- uses package.preload for its require() calls
preload("MoonDasm")
preload("MoonMlua")
preload("MoonEditorLspRpc")

local M = {}
for name, mod in pairs(cache) do
    M[name] = mod
end
return M
