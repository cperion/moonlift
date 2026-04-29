package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local J = require("moonlift.back_jit")
local Validate = require("moonlift.back_validate")
local TreeToBack = require("moonlift.tree_to_back")

local T = pvm.context()
A2.Define(T)
local jit_api = J.Define(T)
local validate = Validate.Define(T)
local lower = TreeToBack.Define(T)

local C = T.Moon2Core
local Ty = T.Moon2Type
local Bn = T.Moon2Bind
local Tr = T.Moon2Tree
local B2 = T.Moon2Back

local i32 = Ty.TScalar(C.ScalarI32)
local bool = Ty.TScalar(C.ScalarBool)
local function arg_binding(index, name)
    return Bn.Binding(C.Id("arg:" .. name), name, i32, Bn.BindingClassArg(index))
end
local a = arg_binding(0, "a")
local b = arg_binding(1, "b")
local function ref(binding, ty)
    return Tr.ExprRef(Tr.ExprTyped(ty or i32), Bn.ValueRefBinding(binding))
end

local add = Tr.FuncExport("add_i32_tree", { Ty.Param("a", i32), Ty.Param("b", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtTyped, Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(a), ref(b))),
})

local max = Tr.FuncExport("max_i32_tree", { Ty.Param("a", i32), Ty.Param("b", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtTyped,
        Tr.ExprSelect(Tr.ExprTyped(i32),
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpGt, ref(a), ref(b)),
            ref(a),
            ref(b))),
})

local module = Tr.Module(Tr.ModuleTyped("Demo"), { Tr.ItemFunc(add), Tr.ItemFunc(max) })
local program = lower.module(module)
local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)
local add_ptr = artifact:getpointer(B2.BackFuncId("add_i32_tree"))
local add_fn = ffi.cast("int32_t (*)(int32_t, int32_t)", add_ptr)
assert(add_fn(20, 22) == 42)
assert(add_fn(-5, 3) == -2)
local max_ptr = artifact:getpointer(B2.BackFuncId("max_i32_tree"))
local max_fn = ffi.cast("int32_t (*)(int32_t, int32_t)", max_ptr)
assert(max_fn(4, 9) == 9)
assert(max_fn(12, 7) == 12)
artifact:free()

print("moonlift tree_to_back_add_select ok")
