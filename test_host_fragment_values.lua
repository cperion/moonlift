package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")
local OpenFacts = require("moonlift.open_facts")
local OpenValidate = require("moonlift.open_validate")
local OpenExpand = require("moonlift.open_expand")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local BackValidate = require("moonlift.back_validate")

local T = moon.T
local Tr = T.Moon2Tree
local OF = OpenFacts.Define(T)
local OV = OpenValidate.Define(T)
local OE = OpenExpand.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local BV = BackValidate.Define(T)

local clamp = moon.expr_frag("clamp_nonneg", { moon.param("x", moon.i32) }, moon.i32, function(f)
    local x = f:param("x")
    return x:lt(0):select(0, x)
end)

local M = moon.module("FragDemo")
M:export_func("score", { moon.param("x", moon.i32) }, moon.i32, function(fn)
    local x = fn:param("x")
    fn:return_(moon.emit_expr(clamp, { x }) + 1)
end)

local module = M:to_asdl()
local expr = module.items[1].func.body[1].value.lhs
assert(pvm.classof(expr) == Tr.ExprUseExprFrag)

local expanded = OE.module(module)
local open_report = OV.validate(OF.facts_of_module(expanded))
assert(#open_report.issues == 0, tostring(open_report.issues[1]))
local checked = TC.check_module(expanded)
assert(#checked.issues == 0, tostring(checked.issues[1]))
local program = Lower.module(checked.module)
local report = BV.validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))

local TParam = moon.type_param("T")
local identity_template = moon.expr_frag_template("identity", { TParam }, function(Ty)
    return {
        params = { moon.param("x", Ty) },
        result = Ty,
        body = function(f) return f:param("x") end,
    }
end)
local identity_i32 = identity_template:instantiate({ moon.i32 })
local M2 = moon.module("GenericFragDemo")
M2:export_func("id", { moon.param("x", moon.i32) }, moon.i32, function(fn)
    return moon.emit_expr(identity_i32, { fn:param("x") })
end)
local expanded2 = OE.module(M2:to_asdl())
local checked2 = TC.check_module(expanded2)
assert(#checked2.issues == 0, tostring(checked2.issues[1]))

print("moonlift host fragment values ok")
