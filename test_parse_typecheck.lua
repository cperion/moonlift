package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A1 = require("moonlift_legacy.asdl")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Bridge = require("moonlift.back_to_moonlift")
local J = require("moonlift_legacy.jit")

local T = pvm.context()
A1.Define(T)
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local bridge = Bridge.Define(T)
local jit_api = J.Define(T)
local Tr = T.Moon2Tree
local B1 = T.MoonliftBack

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

local artifact = jit_api.jit():compile(bridge.lower_program(program))
local sum = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B1.BackFuncId("sum")))
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
local artifact2 = jit_api.jit():compile(bridge.lower_program(program_expr))
local fact = ffi.cast("int32_t (*)(int32_t)", artifact2:getpointer(B1.BackFuncId("fact")))
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

print("moonlift parse_typecheck ok")
