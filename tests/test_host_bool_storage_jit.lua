package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Lower = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

ffi.cdef[[
typedef struct MoonliftBool32User {
    int32_t id;
    int32_t active;
} MoonliftBool32User;
]]

local T = pvm.context()
A2.Define(T)
local C = T.MoonCore
local Ty = T.MoonType
local B = T.MoonBind
local Sem = T.MoonSem
local Tr = T.MoonTree
local H = T.MoonHost
local B2 = T.MoonBack

local Lowerer = Lower.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)

local bool_ty = Ty.TScalar(C.ScalarBool)
local user_ty = Ty.TNamed(Ty.TypeRefGlobal("Demo", "User"))
local user_ptr_ty = Ty.TPtr(user_ty)
local active_field = Sem.FieldByOffset("active", 4, bool_ty, H.HostRepBool(H.HostBoolI32, C.ScalarI32))

local p_binding = B.Binding(C.Id("arg:set_active:p"), "p", user_ptr_ty, B.BindingClassArg(0))
local flag_binding = B.Binding(C.Id("arg:set_active:flag"), "flag", bool_ty, B.BindingClassArg(1))
local p_expr = Tr.ExprRef(Tr.ExprTyped(user_ptr_ty), B.ValueRefBinding(p_binding))
local flag_expr = Tr.ExprRef(Tr.ExprTyped(bool_ty), B.ValueRefBinding(flag_binding))
local active_place = Tr.PlaceField(
    Tr.PlaceTyped(bool_ty),
    Tr.PlaceDeref(Tr.PlaceTyped(user_ty), p_expr),
    active_field
)
local active_expr = Tr.ExprField(Tr.ExprTyped(bool_ty), p_expr, active_field)

local func = Tr.FuncExport("set_active", {
    Ty.Param("p", user_ptr_ty),
    Ty.Param("flag", bool_ty),
}, bool_ty, {
    Tr.StmtSet(Tr.StmtTyped, active_place, flag_expr),
    Tr.StmtReturnValue(Tr.StmtTyped, active_expr),
})
local module = Tr.Module(Tr.ModuleTyped("BoolStorage"), { Tr.ItemFunc(func) })
local program = Lowerer.module(module)
local report = V.validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))

local saw_i32_store = false
local saw_i32_load = false
local saw_bool_compare = false
for i = 1, #program.cmds do
    local cmd = program.cmds[i]
    if pvm.classof(cmd) == T.MoonBack.CmdStoreInfo and pvm.classof(cmd.ty) == T.MoonBack.BackShapeScalar and cmd.ty.scalar == T.MoonBack.BackI32 then saw_i32_store = true end
    if pvm.classof(cmd) == T.MoonBack.CmdLoadInfo and pvm.classof(cmd.ty) == T.MoonBack.BackShapeScalar and cmd.ty.scalar == T.MoonBack.BackI32 then saw_i32_load = true end
    if pvm.classof(cmd) == T.MoonBack.CmdCompare and cmd.op == T.MoonBack.BackIcmpNe then saw_bool_compare = true end
end
assert(saw_i32_store, "expected bool32 store through i32 storage")
assert(saw_i32_load, "expected bool32 load through i32 storage")
assert(saw_bool_compare, "expected bool32 load compare-to-zero")

local artifact = jit_api.jit():compile(program)
local set_active = ffi.cast("bool (*)(MoonliftBool32User*, bool)", artifact:getpointer(B2.BackFuncId("set_active")))
local user = ffi.new("MoonliftBool32User[1]")
user[0].id = 7
user[0].active = 123
assert(set_active(user, false) == false)
assert(user[0].active == 0)
assert(set_active(user, true) == true)
assert(user[0].active == 1)
artifact:free()

print("moonlift host_bool_storage_jit ok")
