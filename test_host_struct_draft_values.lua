package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")

local T = moon.T
local Ty, Tr = T.Moon2Type, T.Moon2Tree

local M = moon.module("ListDemo")
local Node = M:newstruct("Node")
Node:add_field("value", moon.i32)
Node:add_field("next", moon.ptr(Node))

local ok, err = pcall(function() M:to_asdl() end)
assert(not ok and tostring(err):match("unsealed type"))

Node:seal()
local module = M:to_asdl()
assert(#module.items == 1)
local item = module.items[1]
assert(pvm.classof(item) == Tr.ItemType)
assert(pvm.classof(item.t) == Tr.TypeDeclStruct)
assert(item.t.name == "Node")
assert(#item.t.fields == 2)
assert(item.t.fields[1].field_name == "value")
assert(item.t.fields[1].ty == moon.i32.ty)
assert(item.t.fields[2].field_name == "next")
assert(item.t.fields[2].ty == Ty.TPtr(Ty.TNamed(Ty.TypeRefGlobal("ListDemo", "Node"))))

local ok2, err2 = pcall(function() Node:add_field("late", moon.i32) end)
assert(not ok2 and tostring(err2):match("sealed type"))

local ok3, err3 = pcall(function() Node:seal() end)
assert(not ok3 and tostring(err3):match("already sealed"))

local M2 = moon.module("DupDemo")
M2:newstruct("Thing")
local ok4, err4 = pcall(function() M2:struct("Thing", {}) end)
assert(not ok4 and tostring(err4):match("duplicate type"))

print("moonlift host struct draft values ok")
