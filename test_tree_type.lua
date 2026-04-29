package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local ExprType = require("moonlift.tree_expr_type")
local PlaceType = require("moonlift.tree_place_type")
local StmtType = require("moonlift.tree_stmt_type")
local ModuleType = require("moonlift.tree_module_type")

local T = pvm.context()
A.Define(T)
local E = ExprType.Define(T)
local P = PlaceType.Define(T)
local S = StmtType.Define(T)
local M = ModuleType.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local B = T.Moon2Bind
local Sem = T.Moon2Sem
local Tr = T.Moon2Tree

local i32 = Ty.TScalar(C.ScalarI32)
local bool = Ty.TScalar(C.ScalarBool)
local ptr_i32 = Ty.TPtr(i32)
local binding = B.Binding(C.Id("x"), "x", i32, B.BindingClassLocalValue)
local ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefBinding(binding))
assert(E.type(ref) == i32)
assert(E.type(Tr.ExprCompare(Tr.ExprSurface, C.CmpEq, ref, ref)) == bool)
assert(E.type(Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, ref, ref)) == i32)
assert(E.type(Tr.ExprField(Tr.ExprSurface, ref, Sem.FieldByName("field", i32))) == i32)
assert(E.type(Tr.ExprArray(Tr.ExprSurface, i32, { ref, ref })) == Ty.TArray(Ty.ArrayLenConst(2), i32))

local ptr_binding = B.Binding(C.Id("p"), "p", ptr_i32, B.BindingClassLocalValue)
local ptr_ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefBinding(ptr_binding))
assert(P.type(Tr.PlaceDeref(Tr.PlaceSurface, ptr_ref)) == i32)
assert(P.type(Tr.PlaceRef(Tr.PlaceSurface, B.ValueRefBinding(binding))) == i32)
assert(P.type(Tr.PlaceField(Tr.PlaceSurface, Tr.PlaceRef(Tr.PlaceTyped(i32), B.ValueRefBinding(binding)), Sem.FieldByName("field", bool))) == bool)

local effect = S.effect(Tr.StmtLet(Tr.StmtTyped, binding, ref))
assert(effect == B.StmtEnvAddBinding(B.ValueEntry("x", binding)))

local module = Tr.Module(Tr.ModuleTyped("Demo"), {
    Tr.ItemFunc(Tr.FuncExport("f", { Ty.Param("x", i32) }, i32, {})),
    Tr.ItemExtern(Tr.ExternFunc("puts", "puts", { Ty.Param("x", i32) }, i32)),
    Tr.ItemConst(Tr.ConstItem("answer", i32, Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt("42")))),
    Tr.ItemStatic(Tr.StaticItem("global", i32, Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt("1")))),
    Tr.ItemType(Tr.TypeDeclStruct("Pair", { Ty.FieldDecl("left", i32), Ty.FieldDecl("right", i32) })),
})
local env = M.env(module)
assert(env.module_name == "Demo")
assert(#env.values == 4)
assert(#env.types == 1)
assert(env.types[1] == B.TypeEntry("Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))))

print("moonlift tree_type ok")
