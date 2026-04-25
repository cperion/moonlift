package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local Q = require("moonlift.meta").Define(T)
local Source = require("moonlift.meta_source").Define(T)
local Expand = require("moonlift.expand_meta").Define(T)
local Seal = require("moonlift.seal_meta_to_elab").Define(T)

local i32 = Q.type.i32
local x = Q.param("x", i32)
local rhs = Q.slot.expr("rhs", i32)
local open = Q.open_set({ slots = { rhs:as_slot() } })

local frag = Source.expr_frag("x + rhs", { x }, open, i32, "Demo")
assert(frag.body.kind == "MetaExprAdd")
assert(frag.body.lhs.binding.param == x)
assert(frag.body.rhs.slot == rhs)

local expanded = Expand.expr(frag:use("src_use", { Q.expr.int("1", i32) }, { rhs:slot_binding(Q.expr.int("2", i32)) }))
assert(expanded.lhs.raw == "1")
assert(expanded.rhs.raw == "2")
local sealed = Seal.expr(expanded, Seal.env("Demo"))
assert(sealed.kind == "ElabExprAdd")

local stmt_frag = Source.region_frag_stmt("return x + rhs", { x }, open, "Demo", i32)
assert(stmt_frag.body[1].kind == "MetaReturnValue")
assert(stmt_frag.body[1].value.rhs.slot == rhs)

local source_func = Source.func([[export func add_rhs(x: i32) -> i32
return x + rhs
end]], open, "Demo")
assert(source_func.params[1].name == "x")
assert(source_func.body[1].value.lhs.binding.param == source_func.params[1])
assert(source_func.body[1].value.rhs.slot == rhs)

local source_const = Source.const([[const K: i32 = rhs]], open, "Demo")
assert(source_const.value.slot == rhs)

local mod = Source.module([[const K: i32 = rhs]], open, "Demo")
assert(mod.items[1].c.value.slot == rhs)

print("moonlift meta source smoke ok")
