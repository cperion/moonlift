package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local Q = require("moonlift.meta").Define(T)
local Meta = T.MoonliftMeta

local i32 = Q.type.i32
local f32 = Q.type.f32
local vf32 = Q.type.view(f32)

local x_param = Q.param("x", i32)
local x_expr = Q.expr.binding(Q.bind.param(x_param))
local one = Q.expr.int("1", i32)
local sum = Q.expr.add(i32, x_expr, one)

local bias_slot = Q.slot.expr("bias", i32)
local typed_bias = bias_slot:as_expr()
assert(typed_bias.ty == i32)
assert(bias_slot:as_slot().slot == bias_slot)

local expr_frag = Q.expr_frag(
    { x_param },
    Q.open_set({ slots = { bias_slot:as_slot() } }),
    Q.expr.add(i32, x_expr, typed_bias),
    i32
)
assert(expr_frag.params[1] == x_param)
assert(expr_frag.open.slots[1].slot == bias_slot)

local use_expr = expr_frag:use("use.bias", { one }, { bias_slot:slot_binding(one) })
assert(use_expr.frag == expr_frag)
assert(use_expr.ty == i32)
assert(use_expr.fills[1].slot.slot == bias_slot)

local body_slot = Q.slot.region("body")
local region_frag = Q.region_frag(
    { Q.param("xs", vf32), Q.param("gain", f32) },
    Q.open_set({ slots = { body_slot:as_slot() } }),
    { body_slot:as_stmt() }
)
local use_region = region_frag:use("use.body", {}, {})
assert(use_region.frag == region_frag)

local type_sym = Q.sym.type("Pair")
local pair_ty = type_sym:as_type()
local pair_decl = Q.type_decl.struct(type_sym, {
    Q.field_type("left", i32),
    Q.field_type("right", i32),
})
assert(pair_ty.sym == type_sym)
assert(pair_decl.fields[1].field_name == "left")

local fn_sym = Q.sym.func("inc")
local fn_ty = Q.type.func({ i32 }, i32)
local ret = Q.stmt.return_value(sum)
local fn = Q.func.export(fn_sym, { x_param }, Q.empty_open_set(), i32, { ret })
assert(fn.sym == fn_sym)
assert(fn.body[1] == ret)
assert(fn_sym:as_binding(fn_ty).sym == fn_sym)

local module = Q.module(Q.module_name.fixed("Demo"), Q.empty_open_set(), {
    Q.item.type(pair_decl),
    Q.item.func(fn),
})
assert(module.name.module_name == "Demo")
assert(module.items[2].func == fn)

local items_slot = Q.slot.items("extra")
local item_use = Q.item.items_slot(items_slot)
assert(item_use.slot == items_slot)

local const_sym = Q.sym.const("K")
local c = Q.const(const_sym, Q.empty_open_set(), i32, one)
local bind_const = const_sym:as_binding(i32)
assert(c.sym == const_sym)
assert(bind_const.sym == const_sym)

print("moonlift meta builder smoke ok")
