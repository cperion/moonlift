package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.schema_projection")

local T = pvm.context()
A(T)

local Core = T.MoonCore
local Type = T.MoonType
local Bind = T.MoonBind
local Tree = T.MoonTree

local index_ty = Type.TScalar(Core.ScalarIndex)
local ptr_index_ty = Type.TPtr(index_ty)
local xs_binding = Bind.Binding(Core.Id("arg.xs"), "xs", ptr_index_ty, Bind.BindingClassArg(0))
local i_binding = Bind.Binding(Core.Id("control.sum.loop.i"), "i", index_ty, Bind.BindingClassEntryBlockParam("control.sum", "loop", 1))
local xs_expr = Tree.ExprRef(Tree.ExprTyped(ptr_index_ty), Bind.ValueRefBinding(xs_binding))
local i_expr = Tree.ExprRef(Tree.ExprTyped(index_ty), Bind.ValueRefBinding(i_binding))
local len_expr = Tree.ExprLit(Tree.ExprTyped(index_ty), Core.LitInt("16"))

local zero_expr = Tree.ExprLit(Tree.ExprTyped(index_ty), Core.LitInt("0"))
local one_expr = Tree.ExprLit(Tree.ExprTyped(index_ty), Core.LitInt("1"))
local acc_binding = Bind.Binding(Core.Id("control.sum.loop.acc"), "acc", index_ty, Bind.BindingClassEntryBlockParam("control.sum", "loop", 2))
local acc_expr = Tree.ExprRef(Tree.ExprTyped(index_ty), Bind.ValueRefBinding(acc_binding))
local control_expr = Tree.ExprControl(Tree.ExprTyped(index_ty), Tree.ControlExprRegion(
    "control.sum",
    index_ty,
    Tree.EntryControlBlock(Tree.BlockLabel("loop"), {
        Tree.EntryBlockParam("i", index_ty, zero_expr),
        Tree.EntryBlockParam("acc", index_ty, zero_expr),
    }, {
        Tree.StmtYieldValue(Tree.StmtSurface, acc_expr),
        Tree.StmtJump(Tree.StmtSurface, Tree.BlockLabel("loop"), {
            Tree.JumpArg("i", one_expr),
            Tree.JumpArg("acc", acc_expr),
        }),
    }),
    {}
))

assert(xs_expr.ref.binding == xs_binding)
assert(i_expr.ref.binding == i_binding)
assert(control_expr.region.entry.label == Tree.BlockLabel("loop"))

print("moonlift schema projection define ok")
