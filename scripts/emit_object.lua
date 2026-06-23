#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.schema_projection")
local Pipeline = require("moonlift.frontend_pipeline")
local Object = require("moonlift.back_object")

local function usage()
    io.stderr:write("usage: luajit emit_object.lua input.mlua -o output.o [--module-name name]\n")
    os.exit(2)
end

local input, output, module_name
local i = 1
while i <= #(arg or {}) do
    local a = arg[i]
    if a == "-o" then
        i = i + 1
        output = arg[i] or usage()
    elseif a == "--module-name" then
        i = i + 1
        module_name = arg[i] or usage()
    elseif a == "-h" or a == "--help" then
        usage()
    elseif not input then
        input = a
    else
        usage()
    end
    i = i + 1
end
if not input or not output then usage() end
module_name = module_name or input:gsub("[/\\]", "_"):gsub("%.mlua$", "")

local f, err = io.open(input, "rb")
if not f then io.stderr:write(tostring(err), "\n"); os.exit(1) end
local source = f:read("*a")
f:close()

local T = pvm.context()
A2(T)
local O = Object(T)
local ok, lowered_or_err = pcall(function()
    return Pipeline(T).parse_and_lower(source, { site = "emit_object.lua" })
end)
if not ok then io.stderr:write(tostring(lowered_or_err), "\n"); os.exit(1) end
local program = lowered_or_err.program
local artifact = O.compile(program, { module_name = module_name })
artifact:write(output)
print(output)
