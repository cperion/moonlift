package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local lalin = require("lalin")
local Machines = require("lalin.compiler_machines")
local Abi = require("lalin.compiler_abi")

local session = lalin.use { scope = "env" }

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
local T = asdl.context_of(module_ast)
local C = T.LalinCompiler

local checked = Machines.typecheck_module(module_ast, nil, { opts = { context = T, site = "test_compiler_code_result" } })

local abi = Abi(T)

local c_code = Machines.checked_to_c_code(checked, nil, { opts = { context = T, site = "test_compiler_code_result_c" } })
assert(asdl.classof(c_code) == C.CodeResult)
local c_report = abi.validate_code_result(c_code)
assert(#c_report.issues == 0)

local c_unit = Machines.code_to_c(c_code, nil, { opts = { context = T, site = "test_compiler_code_result_c" } })
assert(tostring(asdl.classof(c_unit)):match("LalinC%.CBackendUnit"))

local bad_report = abi.validate_code_result(c_code.module)
assert(#bad_report.issues == 1)
assert(asdl.classof(bad_report.issues[1]) == C.CodeResultIssueUnexpectedValue)

io.write("lalin compiler_code_result ok\n")
