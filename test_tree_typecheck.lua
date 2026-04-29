package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local J = require("moonlift.back_jit")
local Validate = require("moonlift.back_validate")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")

local T = pvm.context()
A2.Define(T)
local jit_api = J.Define(T)
local validate = Validate.Define(T)
local TC = Typecheck.Define(T)
local lower = TreeToBack.Define(T)

local C = T.Moon2Core
local Ty = T.Moon2Type
local B = T.Moon2Bind
local Tr = T.Moon2Tree
local B2 = T.Moon2Back

local i32 = Ty.TScalar(C.ScalarI32)
local bool = Ty.TScalar(C.ScalarBool)
local function lit(raw) return Tr.ExprLit(Tr.ExprSurface, C.LitInt(raw)) end
local function bool_lit(v) return Tr.ExprLit(Tr.ExprSurface, C.LitBool(v)) end
local function name(n) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(n)) end

local region = Tr.ControlStmtRegion(
    "control.sum.typecheck",
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), {
        Tr.EntryBlockParam("i", i32, lit("0")),
        Tr.EntryBlockParam("acc", i32, lit("0")),
    }, {
        Tr.StmtIf(Tr.StmtSurface,
            Tr.ExprCompare(Tr.ExprSurface, C.CmpGe, name("i"), name("n")),
            { Tr.StmtReturnValue(Tr.StmtSurface, name("acc")) },
            {}
        ),
        Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel("loop"), {
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, name("i"), lit("1"))),
            Tr.JumpArg("acc", Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, name("acc"), name("i"))),
        }),
    }),
    {}
)

local module = Tr.Module(Tr.ModuleSurface, {
    Tr.ItemFunc(Tr.FuncExport("sum_typechecked", { Ty.Param("n", i32) }, i32, {
        Tr.StmtControl(Tr.StmtSurface, region),
    })),
})

local checked = TC.check_module(module)
assert(#checked.issues == 0)
assert(pvm.classof(checked.module.h) == Tr.ModuleTyped)
local typed_func = checked.module.items[1].func
local typed_region = typed_func.body[1].region
local typed_jump = typed_region.entry.body[2]
assert(typed_jump.h == Tr.StmtTyped)
assert(pvm.classof(typed_jump.args[1].value.h) == Tr.ExprTyped)
assert(pvm.classof(typed_region.entry.body[1].cond.h) == Tr.ExprTyped)

local program = lower.module(checked.module)
local report = validate.validate(program)
assert(#report.issues == 0)
local jit = jit_api.jit()
local artifact = jit:compile(program)
local f = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("sum_typechecked")))
assert(f(0) == 0)
assert(f(1) == 0)
assert(f(5) == 10)
artifact:free()

local bad = Tr.Module(Tr.ModuleSurface, {
    Tr.ItemFunc(Tr.FuncExport("bad", { Ty.Param("n", i32) }, i32, {
        Tr.StmtReturnValue(Tr.StmtSurface, bool_lit(true)),
        Tr.StmtExpr(Tr.StmtSurface, name("missing")),
    })),
})
local bad_checked = TC.check_module(bad)
assert(#bad_checked.issues >= 1)
assert(bad_checked.issues[1] == Tr.TypeIssueExpected("return", i32, bool))

print("moonlift tree_typecheck ok")
