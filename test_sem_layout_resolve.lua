package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Layout = require("moonlift.sem_layout_resolve")

local T = pvm.context()
A.Define(T)
local L = Layout.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local B = T.Moon2Bind
local Sem = T.Moon2Sem
local Tr = T.Moon2Tree
local H = T.Moon2Host

local i32 = Ty.TScalar(C.ScalarI32)
local i32_rep = H.HostRepScalar(C.ScalarI32)
local pair = Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))
local env = Sem.LayoutEnv({
    Sem.LayoutNamed("Demo", "Pair", {
        Sem.FieldLayout("left", 0, i32),
        Sem.FieldLayout("right", 4, i32),
    }, 8, 4),
})

local right_name = Sem.FieldByName("right", i32)
assert(L.field(right_name, pair, env) == Sem.FieldByOffset("right", 4, i32, i32_rep))
assert(L.field(Sem.FieldByOffset("left", 0, i32, i32_rep), pair, env) == Sem.FieldByOffset("left", 0, i32, i32_rep))
assert(L.field(Sem.FieldByName("missing", i32), pair, env) == Sem.FieldByName("missing", i32))

local binding = B.Binding(C.Id("p"), "p", pair, B.BindingClassLocalValue)
local base_place = Tr.PlaceRef(Tr.PlaceTyped(pair), B.ValueRefBinding(binding))
local field_place = Tr.PlaceField(Tr.PlaceTyped(i32), base_place, right_name)
assert(L.place(field_place, env) == Tr.PlaceField(Tr.PlaceTyped(i32), base_place, Sem.FieldByOffset("right", 4, i32, i32_rep)))

local base_expr = Tr.ExprRef(Tr.ExprTyped(pair), B.ValueRefBinding(binding))
local field_expr = Tr.ExprField(Tr.ExprTyped(i32), base_expr, right_name)
assert(L.expr(field_expr, env) == Tr.ExprField(Tr.ExprTyped(i32), base_expr, Sem.FieldByOffset("right", 4, i32, i32_rep)))

local module = Tr.Module(Tr.ModuleTyped("Demo"), {
    Tr.ItemFunc(Tr.FuncLocal("get_right", {}, i32, {
        Tr.StmtReturnValue(Tr.StmtTyped, field_expr),
    })),
})
local resolved = L.module(module, env)
assert(resolved.items[1].func.body[1].value.field == Sem.FieldByOffset("right", 4, i32, i32_rep))

print("moonlift sem_layout_resolve ok")
