package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift")
local Machines = require("moonlift.compiler_machines")
local Abi = require("moonlift.compiler_abi")

local session = moon.use { scope = "env" }

local src = [[
return unit. CodeResultSmoke {
    fn. add
        { a [i32], b [i32] }
        [i32]
        {
            ret (a + b),
        },
}
]]

local decl = session:loadstring(src, "compiler_code_result_test.lua")()
local module_ast = decl:ast()
local T = rawget(pvm.classof(module_ast), "__context")
local C = T.MoonCompiler

local checked = Machines.typecheck_module(module_ast, nil, { opts = { context = T, site = "test_compiler_code_result" } })

local abi = Abi(T)

local c_code = Machines.checked_to_c_code(checked, nil, { opts = { context = T, site = "test_compiler_code_result_c" } })
assert(pvm.classof(c_code) == C.CodeResult)
local c_report = abi.validate_code_result(c_code)
assert(#c_report.issues == 0)

local c_unit = Machines.code_to_c(c_code, nil, { opts = { context = T, site = "test_compiler_code_result_c" } })
assert(tostring(pvm.classof(c_unit)):match("MoonC%.CBackendUnit"))

local bad_report = abi.validate_code_result(c_code.module)
assert(#bad_report.issues == 1)
assert(pvm.classof(bad_report.issues[1]) == C.CodeResultIssueWrongClass)

io.write("moonlift compiler_code_result ok\n")
