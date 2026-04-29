package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local BackValidate = require("moonlift.back_validate")

local T = moon.T
local Tr = T.Moon2Tree
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local BV = BackValidate.Define(T)

local M = moon.module("PlaceDemo")
M:export_func("store_first", {
    moon.param("p", moon.ptr(moon.i32)),
    moon.param("v", moon.i32),
}, moon.i32, function(fn)
    local p = fn:param("p")
    local v = fn:param("v")
    fn:set(p:index_place(0), v)
    fn:return_(p:index(0))
end)

local module = M:to_asdl()
local fn = module.items[1].func
assert(pvm.classof(fn.body[1]) == Tr.StmtSet)
assert(pvm.classof(fn.body[1].place) == Tr.PlaceIndex)
assert(pvm.classof(fn.body[2]) == Tr.StmtReturnValue)
assert(pvm.classof(fn.body[2].value) == Tr.ExprIndex)

local checked = TC.check_module(module)
assert(#checked.issues == 0, tostring(checked.issues[1]))
local program = Lower.module(checked.module)
local report = BV.validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))

local M2 = moon.module("AddrDemo")
M2:export_func("addr_roundtrip", { moon.param("x", moon.i32) }, moon.ptr(moon.i32), function(fn)
    return moon.addr_of(fn:place("x"))
end)
local checked_addr = TC.check_module(M2:to_asdl())
assert(#checked_addr.issues == 0, tostring(checked_addr.issues[1]))
local ret = checked_addr.module.items[1].func.body[1].value
assert(pvm.classof(ret) == Tr.ExprAddrOf)

print("moonlift host place values ok")
