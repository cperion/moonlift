package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)
local Tr = T.Moon2Tree
local B2 = T.Moon2Back

local src = [[
export func sum(n: i32) -> i32
    block loop(i: i32 = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end

        jump loop(
            i = i + 1,
            acc = acc + i,
        )
    end
end
]]

local parsed = P.parse_module(src)
assert(#parsed.issues == 0)
assert(parsed.module.h == Tr.ModuleSurface)
assert(#parsed.module.items == 1)

local checked = TC.check_module(parsed.module)
assert(#checked.issues == 0)
local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0)

local artifact = jit_api.jit():compile(program)
local sum = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("sum")))
assert(sum(0) == 0)
assert(sum(1) == 0)
assert(sum(5) == 10)
artifact:free()

local expr_src = [[
export func fact(n: i32) -> i32
    return block loop(x: i32 = n, acc: i32 = 1) -> i32
        if x <= 1 then
            yield acc
        end
        jump loop(x = x - 1, acc = acc * x)
    end
end
]]
local parsed_expr = P.parse_module(expr_src)
assert(#parsed_expr.issues == 0)
local checked_expr = TC.check_module(parsed_expr.module)
assert(#checked_expr.issues == 0)
local program_expr = Lower.module(checked_expr.module)
assert(#V.validate(program_expr).issues == 0)
local artifact2 = jit_api.jit():compile(program_expr)
local fact = ffi.cast("int32_t (*)(int32_t)", artifact2:getpointer(B2.BackFuncId("fact")))
assert(fact(0) == 1)
assert(fact(1) == 1)
assert(fact(5) == 120)
artifact2:free()

local index_src = [[
export func count(n: index) -> index
    return block loop(i: index = 0) -> index
        if i >= n then
            yield i
        end
        jump loop(i = i + 1)
    end
end
]]
local parsed_index = P.parse_module(index_src)
assert(#parsed_index.issues == 0)
local checked_index = TC.check_module(parsed_index.module)
assert(#checked_index.issues == 0)

local item_src = [[
extern func puts(x: i32) -> i32
const answer: i32 = 42
static seed: i32 = answer
]]
local parsed_items = P.parse_module(item_src)
assert(#parsed_items.issues == 0)
assert(#parsed_items.module.items == 3)
local checked_items = TC.check_module(parsed_items.module)
assert(#checked_items.issues == 0)

local as_src = [[
export func byte_to_i32(p: ptr(u8)) -> i32
    return as(i32, p[0])
end
]]
local parsed_as = P.parse_module(as_src)
assert(#parsed_as.issues == 0, tostring(parsed_as.issues[1]))
local checked_as = TC.check_module(parsed_as.module)
assert(#checked_as.issues == 0, tostring(checked_as.issues[1]))
local program_as = Lower.module(checked_as.module)
assert(#V.validate(program_as).issues == 0)
local artifact3 = jit_api.jit():compile(program_as)
local byte_to_i32 = ffi.cast("int32_t (*)(const uint8_t*)", artifact3:getpointer(B2.BackFuncId("byte_to_i32")))
local bytes = ffi.new("uint8_t[1]", 250)
assert(byte_to_i32(bytes) == 250)
artifact3:free()

print("moonlift parse_typecheck ok")
