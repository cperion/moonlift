package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.schema_projection")
local Diagnostics = require("moonlift.back_diagnostics")

local T = pvm.context()
A(T)
local B = T.MoonBack
local D = Diagnostics(T)

local program = B.BackProgram({ B.CmdFinalizeModule })
local report = D.diagnostics(program, nil, {})
assert(pvm.classof(report) == B.BackDiagnosticsReport)
assert(pvm.classof(report.inspection) == B.BackInspectionReport)
assert(#report.disassembly == 0)

print("moonlift back_diagnostics ok")
