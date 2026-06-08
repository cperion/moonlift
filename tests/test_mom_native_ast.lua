package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local NativeAst = require("moonlift.mom.parser.native_ast")
local Pipeline = require("moonlift.frontend_pipeline")
local Jit = require("moonlift.back_jit")

local T = pvm.context()
A2.Define(T)
local P = NativeAst.Define(T)
local J = Jit.Define(T)
local B = T.MoonBack

local src = [[
struct Pair
    left: i32
    right: i32
end

func add(x: i32, y: i32): i32
    return x + y
end

func sum(n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
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

local result = Pipeline.Define(T).lower_module(parsed.module, { site = "test_mom_native_ast" })
local program = result.program
local report = result.back_report
assert(#report.issues == 0, report.issues[1] and tostring(report.issues[1]) or "back issues")

local artifact = J.jit():compile(program)
local add = ffi.cast("int32_t (*)(int32_t,int32_t)", artifact:getpointer(B.BackFuncId("add")))
local sum = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B.BackFuncId("sum")))
assert(add(20, 22) == 42)
assert(sum(5) == 10)
artifact:free()
NativeAst.free_native()

print("mom native ast verification ok")
