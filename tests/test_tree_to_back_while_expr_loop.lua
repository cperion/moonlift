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

local n = Bn.Binding(C.Id("arg:fact_control_expr:n"), "n", i32, Bn.BindingClassArg(0))
local x = Bn.Binding(C.Id("control:param:control.fact:loop:x"), "x", i32, Bn.BindingClassEntryBlockParam("control.fact", "loop", 1))
local acc = Bn.Binding(C.Id("control:param:control.fact:loop:acc"), "acc", i32, Bn.BindingClassEntryBlockParam("control.fact", "loop", 2))

local region = Tr.ControlExprRegion(
    "control.fact",
    i32,
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), {
        Tr.EntryBlockParam("x", i32, ref(n)),
        Tr.EntryBlockParam("acc", i32, lit("1")),
    }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpLe, ref(x), lit("1")),
            { Tr.StmtYieldValue(Tr.StmtTyped, ref(acc)) },
            {}
        ),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("loop"), {
            Tr.JumpArg("x", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinSub, ref(x), lit("1"))),
            Tr.JumpArg("acc", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinMul, ref(acc), ref(x))),
        }),
    }),
    {}
)

local fact = Tr.FuncExport("fact_control_expr", { Ty.Param("n", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtTyped, Tr.ExprControl(Tr.ExprTyped(i32), region)),
})

local module = Tr.Module(Tr.ModuleTyped("Demo"), { Tr.ItemFunc(fact) })
local program = lower.module(module)
local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)
local fact_fn = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("fact_control_expr")))
assert(fact_fn(0) == 1)
assert(fact_fn(1) == 1)
assert(fact_fn(5) == 120)
artifact:free()

print("moonlift tree_to_back_while_expr_loop control ok")
