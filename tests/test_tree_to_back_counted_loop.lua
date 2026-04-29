package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

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

local C = T.MoonCore
local Ty = T.MoonType
local Bn = T.MoonBind
local Tr = T.MoonTree
local B2 = T.MoonBack

local i32 = Ty.TScalar(C.ScalarI32)
local bool = Ty.TScalar(C.ScalarBool)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end
local function ref(binding) return Tr.ExprRef(Tr.ExprTyped(binding.ty), Bn.ValueRefBinding(binding)) end

local n = Bn.Binding(C.Id("arg:sum_to_n_control:n"), "n", i32, Bn.BindingClassArg(0))
local i = Bn.Binding(C.Id("control:param:control.sum:loop:i"), "i", i32, Bn.BindingClassEntryBlockParam("control.sum", "loop", 1))
local acc = Bn.Binding(C.Id("control:param:control.sum:loop:acc"), "acc", i32, Bn.BindingClassEntryBlockParam("control.sum", "loop", 2))

local region = Tr.ControlStmtRegion(
    "control.sum",
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), {
        Tr.EntryBlockParam("i", i32, lit("0")),
        Tr.EntryBlockParam("acc", i32, lit("0")),
    }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpGe, ref(i), ref(n)),
            { Tr.StmtReturnValue(Tr.StmtTyped, ref(acc)) },
            {}
        ),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("loop"), {
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(i), lit("1"))),
            Tr.JumpArg("acc", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(acc), ref(i))),
        }),
    }),
    {}
)

local sum = Tr.FuncExport("sum_to_n_control", { Ty.Param("n", i32) }, i32, {
    Tr.StmtControl(Tr.StmtTyped, region),
})

local module = Tr.Module(Tr.ModuleTyped("Demo"), { Tr.ItemFunc(sum) })
local program = lower.module(module)
local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)
local ptr = artifact:getpointer(B2.BackFuncId("sum_to_n_control"))
local sum_to_n = ffi.cast("int32_t (*)(int32_t)", ptr)
assert(sum_to_n(0) == 0)
assert(sum_to_n(1) == 0)
assert(sum_to_n(5) == 10)
assert(sum_to_n(10) == 45)
artifact:free()

print("moonlift tree_to_back_counted_loop control ok")
