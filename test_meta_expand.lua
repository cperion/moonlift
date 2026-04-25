package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local Q = require("moonlift.meta").Define(T)
local Expand = require("moonlift.expand_meta").Define(T)
local Seal = require("moonlift.seal_meta_to_elab").Define(T)
local Meta = T.MoonliftMeta

local i32 = Q.type.i32
local x = Q.param("x", i32)
local x_expr = Q.expr.binding(Q.bind.param(x))
local one = Q.expr.int("1", i32)
local two = Q.expr.int("2", i32)

local rhs = Q.slot.expr("rhs", i32)
local expr_frag = Q.expr_frag({ x }, Q.open_set({ slots = { rhs:as_slot() } }), Q.expr.add(i32, x_expr, rhs:as_expr()), i32)
local use = expr_frag:use("inc_use", { one }, { rhs:slot_binding(two) })
local expanded = Expand.expr(use)
assert(expanded.kind == "MetaExprAdd")
assert(expanded.lhs.raw == "1")
assert(expanded.rhs.raw == "2")
local sealed = Seal.expr(expanded, Seal.env("Demo"))
assert(sealed.kind == "ElabExprAdd")
assert(sealed.lhs.raw == "1")
assert(sealed.rhs.raw == "2")

local body = Q.slot.region("body")
local region_frag = Q.region_frag({ x }, Q.open_set({ slots = { body:as_slot() } }), {
    Q.stmt.let("tmp", "tmp", i32, x_expr),
    body:as_stmt(),
})
local body_stmt = Q.stmt.expr(Q.expr.add(i32, x_expr, two))
local region_use = region_frag:use("region_use", { one }, { body:slot_binding({ body_stmt }) })
local expanded_region = Expand.stmt(region_use)
assert(#expanded_region == 2)
assert(expanded_region[1].id == "region_use.tmp")
assert(expanded_region[1].init.raw == "1")
assert(expanded_region[2].expr.lhs.raw == "1")

local type_slot = Q.slot.type("T")
local typed = Q.type.ptr(type_slot:as_type())
local expanded_ty = Expand.type(typed, Expand.env(Q.fill_set({ type_slot:slot_binding(i32) })))
assert(expanded_ty.elem == i32)

local type_sym = Q.sym.type("Pair")
local extra_slot = Q.slot.items("extra")
local module_template = Q.module(Q.module_name.fixed("Template"), Q.empty_open_set(), {
    Q.item.items_slot(extra_slot),
})
local const_sym = Q.sym.const("K")
local const_item = Q.item.const(Q.const(const_sym, Q.empty_open_set(), i32, one))
local module_use = Q.item.module("module_use", module_template, { extra_slot:slot_binding({ const_item }) })
local expanded_items = Expand.items({ module_use })
assert(#expanded_items == 1)
assert(expanded_items[1].c.sym == const_sym)

print("moonlift meta expand smoke ok")
