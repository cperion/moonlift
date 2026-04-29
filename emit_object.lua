#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local MluaParse = require("moonlift.mlua_parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
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
A2.Define(T)
local MP = MluaParse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local O = Object.Define(T)

local parsed = MP.parse(source, "@" .. input)
if #parsed.issues ~= 0 then
    for j = 1, #parsed.issues do io.stderr:write(tostring(parsed.issues[j].message or parsed.issues[j]), "\n") end
    os.exit(1)
end
local checked = TC.check_module(parsed.module)
if #checked.issues ~= 0 then
    for j = 1, #checked.issues do io.stderr:write(tostring(checked.issues[j].message or checked.issues[j]), "\n") end
    os.exit(1)
end
local program = Lower.module(checked.module)
local report = V.validate(program)
if #report.issues ~= 0 then
    for j = 1, #report.issues do io.stderr:write(tostring(report.issues[j].message or report.issues[j]), "\n") end
    os.exit(1)
end
local artifact = O.compile(program, { module_name = module_name })
artifact:write(output)
print(output)
