#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Erase = require("lalin.pvm_erase")

local in_path = arg[1]
local out_path = arg[2]

if not in_path then
    io.stderr:write("usage: luajit scripts/pvm_erase.lua <input.lua> [output.lua]\n")
    os.exit(2)
end

local out, report = Erase.transform_file(in_path, out_path)
if out_path then
    io.stderr:write(Erase.report_string(report), "\n")
else
    io.stderr:write(Erase.report_string(report), "\n")
    io.write(out)
end
