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
local Sem = T.MoonSem
local Tr = T.MoonTree
local B2 = T.MoonBack

local i32 = Ty.TScalar(C.ScalarI32)
local bool = Ty.TScalar(C.ScalarBool)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end
local function ref(binding) return Tr.ExprRef(Tr.ExprTyped(binding.ty), Bn.ValueRefBinding(binding)) end

local n = Bn.Binding(C.Id("arg:first_three_or_n:n"), "n", i32, Bn.BindingClassArg(0))
local read_i = Bn.Binding(C.Id("control:param:control.find:read:i"), "i", i32, Bn.BindingClassEntryBlockParam("control.find", "read", 1))
local found_i = Bn.Binding(C.Id("control:param:control.find:found:i"), "i", i32, Bn.BindingClassBlockParam("control.find", "found", 1))

local region = Tr.ControlExprRegion(
    "control.find",
    i32,
    Tr.EntryControlBlock(Tr.BlockLabel("read"), {
        Tr.EntryBlockParam("i", i32, lit("0")),
    }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpGe, ref(read_i), ref(n)),
            { Tr.StmtYieldValue(Tr.StmtTyped, ref(n)) },
            {}
        ),
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpEq, ref(read_i), lit("3")),
            { Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("found"), { Tr.JumpArg("i", ref(read_i)) }) },
            {}
        ),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("read"), {
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(read_i), lit("1"))),
        }),
    }),
    {
        Tr.ControlBlock(Tr.BlockLabel("found"), { Tr.BlockParam("i", i32) }, {
            Tr.StmtYieldValue(Tr.StmtTyped, ref(found_i)),
        }),
    }
)

local fn = Tr.FuncExport("first_three_or_n", { Ty.Param("n", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtTyped, Tr.ExprControl(Tr.ExprTyped(i32), region)),
})

local exit_region = Tr.ControlStmtRegion(
    "control.exit",
    Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, { Tr.StmtYieldVoid(Tr.StmtTyped) }),
    {}
)
local exit_fn = Tr.FuncExport("control_stmt_exit", {}, i32, {
    Tr.StmtControl(Tr.StmtTyped, exit_region),
    Tr.StmtReturnValue(Tr.StmtTyped, lit("7")),
})

local sw_n = Bn.Binding(C.Id("arg:control_switch:n"), "n", i32, Bn.BindingClassArg(0))
local switch_region = Tr.ControlExprRegion(
    "control.switch",
    i32,
    Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, {
        Tr.StmtSwitch(Tr.StmtTyped, ref(sw_n), {
            Tr.SwitchStmtArm(Sem.SwitchKeyRaw("0"), { Tr.StmtYieldValue(Tr.StmtTyped, lit("10")) }),
            Tr.SwitchStmtArm(Sem.SwitchKeyRaw("1"), { Tr.StmtYieldValue(Tr.StmtTyped, lit("11")) }),
        }, { Tr.StmtYieldValue(Tr.StmtTyped, lit("12")) }),
    }),
    {}
)
local switch_fn = Tr.FuncExport("control_switch", { Ty.Param("n", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtTyped, Tr.ExprControl(Tr.ExprTyped(i32), switch_region)),
})

local module = Tr.Module(Tr.ModuleTyped("Demo"), { Tr.ItemFunc(fn), Tr.ItemFunc(exit_fn), Tr.ItemFunc(switch_fn) })
local program = lower.module(module)
local report = validate.validate(program)
assert(#report.issues == 0)

local jit = jit_api.jit()
local artifact = jit:compile(program)
local f = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("first_three_or_n")))
assert(f(0) == 0)
assert(f(2) == 2)
assert(f(3) == 3)
assert(f(5) == 3)
local g = ffi.cast("int32_t (*)()", artifact:getpointer(B2.BackFuncId("control_stmt_exit")))
assert(g() == 7)
local h = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("control_switch")))
assert(h(0) == 10)
assert(h(1) == 11)
assert(h(2) == 12)
artifact:free()

print("moonlift tree_to_back_control_multiblock ok")
