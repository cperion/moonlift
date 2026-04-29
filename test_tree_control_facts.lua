package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Control = require("moonlift.tree_control_facts")

local T = pvm.context()
A.Define(T)
local Ctl = Control.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local Tr = T.Moon2Tree

local i32 = Ty.TScalar(C.ScalarI32)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end
local function has(xs, needle)
    for i = 1, #xs do if xs[i] == needle then return true end end
    return false
end

local loop = Tr.BlockLabel("loop")
local done = Tr.BlockLabel("done")
local region = Tr.ControlExprRegion(
    "control.sum",
    i32,
    Tr.EntryControlBlock(loop, {
        Tr.EntryBlockParam("i", i32, lit("0")),
        Tr.EntryBlockParam("acc", i32, lit("0")),
    }, {
        Tr.StmtJump(Tr.StmtSurface, loop, {
            Tr.JumpArg("i", lit("1")),
            Tr.JumpArg("acc", lit("2")),
        }),
    }),
    {
        Tr.ControlBlock(done, { Tr.BlockParam("result", i32) }, {
            Tr.StmtYieldValue(Tr.StmtSurface, lit("42")),
        }),
    }
)

local facts = Ctl.facts(region)
assert(has(facts.facts, Tr.ControlFactEntryBlock("control.sum", loop)))
assert(has(facts.facts, Tr.ControlFactBlock("control.sum", loop)))
assert(has(facts.facts, Tr.ControlFactBlock("control.sum", done)))
assert(has(facts.facts, Tr.ControlFactEntryParam("control.sum", loop, 1, "i", i32)))
assert(has(facts.facts, Tr.ControlFactJump("control.sum", loop, loop)))
assert(has(facts.facts, Tr.ControlFactJumpArg("control.sum", loop, loop, "i", i32)))
assert(has(facts.facts, Tr.ControlFactJumpArg("control.sum", loop, loop, "acc", i32)))
assert(has(facts.facts, Tr.ControlFactBackedge("control.sum", loop, loop)))
assert(has(facts.facts, Tr.ControlFactYieldValue("control.sum", done, i32)))

local decision = Ctl.decide(region)
assert(decision == Tr.ControlDecisionReducible("control.sum", facts.facts))

local bad = Tr.ControlStmtRegion(
    "control.bad",
    Tr.EntryControlBlock(loop, {}, { Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel("missing"), {}) }),
    {}
)
local bad_decision = Ctl.decide(bad)
assert(pvm.classof(bad_decision) == Tr.ControlDecisionIrreducible)
assert(bad_decision.reject == Tr.ControlRejectMissingLabel("control.bad", Tr.BlockLabel("missing")))

local missing_arg = Tr.ControlStmtRegion(
    "control.missing_arg",
    Tr.EntryControlBlock(loop, { Tr.EntryBlockParam("i", i32, lit("0")), Tr.EntryBlockParam("acc", i32, lit("0")) }, {
        Tr.StmtJump(Tr.StmtSurface, loop, { Tr.JumpArg("i", lit("1")) }),
    }),
    {}
)
assert(Ctl.decide(missing_arg).reject == Tr.ControlRejectMissingJumpArg("control.missing_arg", loop, "acc"))

local extra_arg = Tr.ControlStmtRegion(
    "control.extra_arg",
    Tr.EntryControlBlock(loop, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop, { Tr.JumpArg("x", lit("1")) }),
    }),
    {}
)
assert(Ctl.decide(extra_arg).reject == Tr.ControlRejectExtraJumpArg("control.extra_arg", loop, "x"))

local duplicate_arg = Tr.ControlStmtRegion(
    "control.duplicate_arg",
    Tr.EntryControlBlock(loop, { Tr.EntryBlockParam("i", i32, lit("0")) }, {
        Tr.StmtJump(Tr.StmtSurface, loop, { Tr.JumpArg("i", lit("1")), Tr.JumpArg("i", lit("2")) }),
    }),
    {}
)
assert(Ctl.decide(duplicate_arg).reject == Tr.ControlRejectDuplicateJumpArg("control.duplicate_arg", loop, "i"))

local bool_ty = Ty.TScalar(C.ScalarBool)
local wrong_type = Tr.ControlStmtRegion(
    "control.wrong_type",
    Tr.EntryControlBlock(loop, { Tr.EntryBlockParam("i", i32, lit("0")) }, {
        Tr.StmtJump(Tr.StmtSurface, loop, { Tr.JumpArg("i", Tr.ExprLit(Tr.ExprTyped(bool_ty), C.LitBool(true))) }),
    }),
    {}
)
assert(Ctl.decide(wrong_type).reject == Tr.ControlRejectJumpType("control.wrong_type", loop, "i", i32, bool_ty))

local stmt_value_yield = Tr.ControlStmtRegion(
    "control.stmt_value_yield",
    Tr.EntryControlBlock(loop, {}, { Tr.StmtYieldValue(Tr.StmtSurface, lit("1")) }),
    {}
)
assert(Ctl.decide(stmt_value_yield).reject == Tr.ControlRejectYieldOutsideRegion("value yield in statement control region"))

local expr_void_yield = Tr.ControlExprRegion(
    "control.expr_void_yield",
    i32,
    Tr.EntryControlBlock(loop, {}, { Tr.StmtYieldVoid(Tr.StmtSurface) }),
    {}
)
assert(Ctl.decide(expr_void_yield).reject == Tr.ControlRejectYieldOutsideRegion("void yield in value-producing control region"))

local expr_wrong_yield = Tr.ControlExprRegion(
    "control.expr_wrong_yield",
    i32,
    Tr.EntryControlBlock(loop, {}, { Tr.StmtYieldValue(Tr.StmtSurface, Tr.ExprLit(Tr.ExprTyped(bool_ty), C.LitBool(true))) }),
    {}
)
assert(Ctl.decide(expr_wrong_yield).reject == Tr.ControlRejectYieldType("control.expr_wrong_yield", i32, bool_ty))

local unterminated = Tr.ControlStmtRegion(
    "control.unterminated",
    Tr.EntryControlBlock(loop, {}, { Tr.StmtExpr(Tr.StmtSurface, lit("1")) }),
    {}
)
assert(Ctl.decide(unterminated).reject == Tr.ControlRejectUnterminatedBlock("control.unterminated", loop))

print("moonlift tree_control_facts ok")
