package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Pipeline = require("moonlift.frontend_pipeline")
local Jit = require("moonlift.back_jit")

local T = pvm.context()
Schema.Define(T)

local J = Jit.Define(T)

local src = [[
func add_i32(a: i32, b: i32): i32
    return a + b
end

func sum_i32(xs: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
]]

local result = Pipeline.Define(T).parse_and_lower(src, { site = "test_schema_compile_pipeline" })
local program = result.program
local report = result.back_report
assert(#report.issues == 0, "back validation issues: " .. #report.issues)

local artifact = J.jit():compile(program)
local add_i32 = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer(T.MoonBack.BackFuncId("add_i32")))
assert(add_i32(20, 22) == 42)
local xs = ffi.new("int32_t[5]", { 1, 2, 3, 4, 5 })
local sum_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", artifact:getpointer(T.MoonBack.BackFuncId("sum_i32")))
assert(sum_i32(xs, 5) == 15)
artifact:free()

io.write("moonlift schema_compile_pipeline ok\n")
