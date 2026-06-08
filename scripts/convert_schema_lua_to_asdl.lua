#!/usr/bin/env luajit
-- Convert Lua-builder schema modules under lua/moonlift/schema/ to compact ASDL text.
--
-- This is a one-shot migration/generation tool.  It intentionally converts
-- only files in lua/moonlift/schema and skips init.lua.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Builder = require("moonlift.asdl_builder")
local AsdlText = require("moonlift.asdl_text")

local T = pvm.context()
local A = Builder.Define(T)

local function module_name_from_path(path)
    local rel = assert(path:match("^lua/(.+)%.lua$"), "unexpected path: " .. path)
    rel = rel:gsub("/", ".")
    if rel:sub(-5) == ".init" then rel = rel:sub(1, -6) end
    return rel
end

local files = {}
local pipe = assert(io.popen("find lua/moonlift/schema -maxdepth 1 -type f -name '*.lua' | sort"))
for path in pipe:lines() do
    if not path:match("/init%.lua$") then files[#files + 1] = path end
end
pipe:close()

for _, path in ipairs(files) do
    local modname = module_name_from_path(path)
    package.loaded[modname] = nil
    local build = assert(require(modname), "schema module did not return a builder function: " .. modname)
    local module = build(A)
    local out_path = path:gsub("%.lua$", ".asdl")
    AsdlText.write_file(out_path, AsdlText.emit_module(T, module))
    io.stderr:write(path, " -> ", out_path, "\n")
end
