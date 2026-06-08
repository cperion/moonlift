-- test_ir_lower.lua — verify Moonlift → LuaJIT IR lowering

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm      = require("moonlift.pvm")
local A        = require("moonlift.asdl")
local Parse    = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local Lower    = require("moonlift.ir_lower")

local T = pvm.context(); A.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Tr = T.MoonTree

local function lower_src(src, label)
    local result = P.parse_module(src)
    if #result.issues ~= 0 then
        error("parse: " .. tostring(result.issues[1]))
    end
    local checked = TC.check_module(result.module)
    if #checked.issues ~= 0 then
        print("  typecheck issues: " .. #checked.issues)
    end
    for _, item in ipairs(checked.module.items) do
        if pvm.classof(item) == Tr.ItemFunc then
            print("=== " .. label .. " ===")
            local trace = Lower.lower_func(T, item.func)
            print(Lower.dump(trace))
            print()
            return trace
        end
    end
    error("no function found")
end

-- Test 1: simple add
lower_src([[
func add(x: i32, y: i32): i32
    return x + y
end
]], "add(x: i32, y: i32): i32")

-- Test 2: mul + sub
lower_src([[
func compute(a: i32, b: i32, c: i32): i32
    let t: i32 = a * b
    return t - c
end
]], "compute(a, b, c): a*b - c")

-- Test 3: comparison
lower_src([[
func max(x: i32, y: i32): i32
    if x > y then
        return x
    else
        return y
    end
end
]], "max(x, y): if x > y then x else y")

print("moonlift → IR lowering ok")
