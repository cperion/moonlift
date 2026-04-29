package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local AData = require("moonlift.asdl_data")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Jit = require("moonlift.back_jit")

local T = pvm.context()
AData.Define(T)

assert(T.MoonAsdl ~= nil, "schema-as-data path should define MoonAsdl")
assert(T.Moon2Core ~= nil, "legacy-compatible schema data should define current Moon2Core")
assert(T.Moon2Back ~= nil, "legacy-compatible schema data should define current Moon2Back")

local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local J = Jit.Define(T)

local src = [[
export func add_i32(a: i32, b: i32) -> i32
    return a + b
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0, "parse issues: " .. #parsed.issues)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0, "type issues: " .. #checked.issues)
local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0, "back validation issues: " .. #report.issues)

local artifact = J.jit():compile(program)
local ptr = artifact:getpointer(T.Moon2Back.BackFuncId("add_i32"))
local add_i32 = ffi.cast("int32_t (*)(int32_t, int32_t)", ptr)
assert(add_i32(20, 22) == 42)
artifact:free()

io.write("moonlift asdl_data_compile ok\n")
