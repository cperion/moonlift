package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")

local T = moon.T
local Ty, O, Tr = T.MoonType, T.MoonOpen, T.MoonTree

local TParam = moon.type_param("T")
assert(pvm.classof(TParam.ty) == Ty.TSlot)
assert(pvm.classof(TParam.type_slot) == O.TypeSlot)

local Vec2 = moon.struct_template("Vec2", { TParam }, function(T)
    return {
        moon.field("x", T),
        moon.field("y", T),
    }
end)

local M = moon.module("TemplateDemo")
local Vec2i32 = M:instantiate(Vec2, { moon.i32 })
local Vec2f64 = M:instantiate(Vec2, { moon.f64 })
assert(Vec2i32.name == "Vec2_i32")
assert(Vec2f64.name == "Vec2_f64")
assert(Vec2i32.decl.fields[1].ty == moon.i32.ty)
assert(Vec2f64.decl.fields[1].ty == moon.f64.ty)

local module = M:to_asdl()
assert(#module.items == 2)
assert(pvm.classof(module.items[1].t) == Tr.TypeDeclStruct)
assert(module.items[1].t.name == "Vec2_i32")
assert(module.items[2].t.name == "Vec2_f64")

local ok, err = pcall(function() M:instantiate(Vec2, {}) end)
assert(not ok and tostring(err):match("expected 1 args"))

print("moonlift host template values ok")
