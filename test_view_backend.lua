package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A1 = require("moonlift_legacy.asdl")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local Lower = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Bridge = require("moonlift.back_to_moonlift")
local J = require("moonlift_legacy.jit")

local T = pvm.context()
A1.Define(T)
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lowerer = Lower.Define(T)
local V = Validate.Define(T)
local bridge = Bridge.Define(T)
local jit_api = J.Define(T)
local B1 = T.MoonliftBack

local src = [[
export func first_from_view(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n)
    if len(v) <= 0 then
        return 0
    end
    return v[0]
end

export func second_from_strided_view(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n, 2)
    if len(v) <= 1 then
        return 0
    end
    return v[1]
end

export func sum_strided_view(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n, 2)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= len(v) then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end

export func window_sum(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n)
    let w: view(i32) = view_window(v, 1, 3)
    return w[0] + w[2]
end

export func strided_window_sum(xs: ptr(i32), n: index) -> i32
    let v: view(i32) = view(xs, n, 2)
    let w: view(i32) = view_window(v, 1, 2)
    return w[0] + w[1]
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local program = Lowerer.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)

local artifact = jit_api.jit():compile(bridge.lower_program(program))
local first = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B1.BackFuncId("first_from_view")))
local second = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B1.BackFuncId("second_from_strided_view")))
local sum = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B1.BackFuncId("sum_strided_view")))
local window_sum = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B1.BackFuncId("window_sum")))
local strided_window_sum = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", artifact:getpointer(B1.BackFuncId("strided_window_sum")))
local xs = ffi.new("int32_t[8]", { 42, 7, 9, 11, 13, 15, 17, 19 })
assert(first(xs, 0) == 0)
assert(first(xs, 3) == 42)
assert(second(xs, 1) == 0)
assert(second(xs, 4) == 9)
assert(sum(xs, 4) == 42 + 9 + 13 + 17)
assert(window_sum(xs, 8) == 7 + 11)
assert(strided_window_sum(xs, 8) == 9 + 13)
artifact:free()

print("moonlift view_backend ok")
