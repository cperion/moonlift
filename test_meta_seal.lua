package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local Q = require("moonlift.meta").Define(T)
local Seal = require("moonlift.seal_meta_to_elab").Define(T)
local Elab = T.MoonliftElab

local i32 = Q.type.i32
local bool = Q.type.bool

local x = Q.param("x", i32)
local x_expr = Q.expr.binding(Q.bind.param(x))
local one = Q.expr.int("1", i32)
local sum = Q.expr.add(i32, x_expr, one)
local ret = Q.stmt.return_value(sum)

local fn_sym = Q.sym.func("inc")
local fn = Q.func.export(fn_sym, { x }, Q.empty_open_set(), i32, { ret })
local sealed_fn = Seal.func(fn, "Demo")
assert(sealed_fn.name == "inc")
assert(sealed_fn.params[1].name == "x")
assert(sealed_fn.body[1].value.kind == "ElabExprAdd")
assert(sealed_fn.body[1].value.lhs.binding.kind == "ElabArg")
assert(sealed_fn.body[1].value.lhs.binding.index == 0)

local type_sym = Q.sym.type("Pair")
local pair_decl = Q.type_decl.struct(type_sym, {
    Q.field_type("left", i32),
    Q.field_type("right", i32),
})
local module = Q.module(Q.module_name.fixed("Demo"), Q.empty_open_set(), {
    Q.item.type(pair_decl),
    Q.item.func(fn),
})
local sealed_mod = Seal.module(module)
assert(sealed_mod.module_name == "Demo")
assert(sealed_mod.items[1].t.name == "Pair")
assert(sealed_mod.items[2].func.name == "inc")

local local_pair_ty = Q.type.local_named(type_sym)
local sealed_pair_ty = Seal.type(local_pair_ty, Seal.env("Demo"))
assert(sealed_pair_ty.module_name == "Demo")
assert(sealed_pair_ty.type_name == "Pair")

local expr_frag = Q.expr_frag({ x }, Q.empty_open_set(), sum, i32)
local sealed_expr = Seal.expr_frag(expr_frag, "Demo")
assert(sealed_expr.kind == "ElabExprAdd")
assert(sealed_expr.ty == Elab.ElabTI32)

local region_frag = Q.region_frag({ x }, Q.empty_open_set(), { ret })
local sealed_region = Seal.region_frag(region_frag, "Demo")
assert(#sealed_region == 1)
assert(sealed_region[1].kind == "ElabReturnValue")

local cond = Q.expr.bool(true, bool)
local select = Q.expr.select(cond, one, sum, i32)
local sealed_select = Seal.expr(select, Seal.env("Demo", { x }))
assert(sealed_select.kind == "ElabSelectExpr")

local open_slot = Q.slot.expr("rhs", i32)
local open_frag = Q.expr_frag({ x }, Q.open_set({ slots = { open_slot:as_slot() } }), open_slot:as_expr(), i32)
local ok, err = pcall(function() Seal.expr_frag(open_frag, "Demo") end)
assert(not ok)
assert(tostring(err):match("open slots"))

print("moonlift meta seal smoke ok")
