package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test template values using session API
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context(); A.Define(T)
local Session = require("moonlift.host_session")
local session = Session.new({ prefix = "template_test", T = T })
local moon = session:api()
local Ty, O, Tr = T.MoonType, T.MoonOpen, T.MoonTree

-- Type parameter
local TParam = moon.type_param("T")
assert(pvm.classof(TParam.ty) == Ty.TSlot)
assert(pvm.classof(TParam.type_slot) == O.TypeSlot)
print("OK: type_param")

-- Struct template
local Vec2 = moon.struct_template("Vec2", { TParam }, function(T)
    return {
        moon.field("x", T),
        moon.field("y", T),
    }
end)
print("OK: struct_template created")

-- Create a module to instantiate into (temporary container for template expansion)
local M = moon.module("TempDemo")
local Vec2i32 = M:instantiate(Vec2, { moon.i32 })
local Vec2f64 = M:instantiate(Vec2, { moon.f64 })
assert(Vec2i32.name == "Vec2_i32")
assert(Vec2f64.name == "Vec2_f64")
assert(Vec2i32.decl.fields[1].ty == moon.i32.ty)
assert(Vec2f64.decl.fields[1].ty == moon.f64.ty)
print("OK: templates instantiated")

-- Get the module ASDL for compilation
local module = M:to_asdl()
assert(#module.items == 2)
assert(pvm.classof(module.items[1].t) == Tr.TypeDeclStruct)
assert(module.items[1].t.name == "Vec2_i32")
assert(module.items[2].t.name == "Vec2_f64")

-- Also via .mlua for direct comparison
local Host = require("moonlift.mlua_run")
local Direct = Host.eval [[return struct Direct x: i32; y: i32 end]]
assert(Direct.decl.name == "Direct")
assert(#Direct.decl.fields == 2)
print("OK: direct struct via .mlua")

print("moonlift host template values ok")
