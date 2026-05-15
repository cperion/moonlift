package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local NativeAst = require("experiments.mom.parser.native_ast")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Jit = require("moonlift.back_jit")

local T = pvm.context()
A2.Define(T)
local P = NativeAst.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local J = Jit.Define(T)
local B = T.MoonBack

local src = [[
struct Pair
    left: i32
    right: i32
end

func add(x: i32, y: i32) -> i32
    return x + y
end

func sum(n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + i)
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0, parsed.issues[1] and tostring(parsed.issues[1]) or "parse issues")
assert(#parsed.module.items == 3)

local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0, checked.issues[1] and tostring(checked.issues[1]) or "type issues")

local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0, report.issues[1] and tostring(report.issues[1]) or "back issues")

local artifact = J.jit():compile(program)
local add = ffi.cast("int32_t (*)(int32_t,int32_t)", artifact:getpointer(B.BackFuncId("add")))
local sum = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B.BackFuncId("sum")))
assert(add(20, 22) == 42)
assert(sum(5) == 10)
artifact:free()
NativeAst.free_native()

print("mom native ast verification ok")
