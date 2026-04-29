package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local BackValidate = require("moonlift.back_validate")

local T = moon.T
local C, B, Tr = T.MoonCore, T.MoonBind, T.MoonTree
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local BV = BackValidate.Define(T)

local M = moon.module("Demo")
local add = M:export_func("add", {
    moon.param("a", moon.i32),
    moon.param("b", moon.i32),
}, moon.i32, function(fn)
    local a = fn:param("a")
    local b = fn:param("b")
    fn:return_(a + b)
end)

assert(add.visibility == "export")
assert(pvm.classof(add.func) == Tr.FuncExport)
assert(#add.func.body == 1)
assert(pvm.classof(add.func.body[1]) == Tr.StmtReturnValue)
local ret = add.func.body[1].value
assert(pvm.classof(ret) == Tr.ExprBinary)
assert(ret.op == C.BinAdd)
assert(pvm.classof(ret.lhs.ref.binding.class) == B.BindingClassArg)
assert(ret.lhs.ref.binding.class.index == 0)

local module = M:to_asdl()
local checked = TC.check_module(module)
assert(#checked.issues == 0, tostring(checked.issues[1]))
local program = Lower.module(checked.module)
local report = BV.validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))

-- Callback return shorthand also becomes a return statement.
local M2 = moon.module("Demo2")
M2:export_func("inc", { moon.param("x", moon.i32) }, moon.i32, function(fn)
    local x = fn:param("x")
    return x + 1
end)
M2:export_func("abs_i32", { moon.param("x", moon.i32) }, moon.i32, function(fn)
    local x = fn:param("x")
    fn:if_(x:lt(0), function(t)
        t:return_(-x)
    end, function(e)
        e:return_(x)
    end)
end)
local checked2 = TC.check_module(M2:to_asdl())
assert(#checked2.issues == 0, tostring(checked2.issues[1]))
local program2 = Lower.module(checked2.module)
local report2 = BV.validate(program2)
assert(#report2.issues == 0, tostring(report2.issues[1]))

print("moonlift host func values ok")
