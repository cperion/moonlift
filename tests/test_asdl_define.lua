package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local Core = T.MoonCore
local Type = T.MoonType
local Bind = T.MoonBind
local Tree = T.MoonTree
local Vec = T.MoonVec

local index_ty = Type.TScalar(Core.ScalarIndex)
local ptr_index_ty = Type.TPtr(index_ty)
local xs_binding = Bind.Binding(Core.Id("arg.xs"), "xs", ptr_index_ty, Bind.BindingClassArg(0))
local ys_binding = Bind.Binding(Core.Id("arg.ys"), "ys", ptr_index_ty, Bind.BindingClassArg(1))
local i_binding = Bind.Binding(Core.Id("control.map.loop.i"), "i", index_ty, Bind.BindingClassEntryBlockParam("control.map", "loop", 1))
local xs_expr = Tree.ExprRef(Tree.ExprSem(ptr_index_ty, T.MoonSem.ValuePlain, T.MoonSem.ConstClassNo), Bind.ValueRefBinding(xs_binding))
local ys_expr = Tree.ExprRef(Tree.ExprSem(ptr_index_ty, T.MoonSem.ValuePlain, T.MoonSem.ConstClassNo), Bind.ValueRefBinding(ys_binding))
local i_expr = Tree.ExprRef(Tree.ExprSem(index_ty, T.MoonSem.ValuePlain, T.MoonSem.ConstClassNo), Bind.ValueRefBinding(i_binding))
local len_expr = Tree.ExprLit(Tree.ExprSem(index_ty, T.MoonSem.ValuePlain, T.MoonSem.ConstClassYes(T.MoonSem.ConstInt(index_ty, "16"))), Core.LitInt("16"))

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
assert(control_expr.region.entry.label == Tree.BlockLabel("loop"))
local load_access = Vec.VecMemoryAccess(
    Vec.VecAccessId("load.xs"),
    Vec.VecAccessLoad,
    Vec.VecMemoryBaseRawAddr(xs_expr),
    Vec.VecExprId("i"),
    index_ty,
    Vec.VecAccessContiguous,
    Vec.VecAlignmentUnknown,
    Vec.VecBoundsUnknown(Vec.VecRejectUnsupportedMemory(Vec.VecAccessId("load.xs"), "test bounds proof absent"))
)
local store_access = Vec.VecMemoryAccess(
    Vec.VecAccessId("store.ys"),
    Vec.VecAccessStore,
    Vec.VecMemoryBaseRawAddr(ys_expr),
    Vec.VecExprId("i"),
    index_ty,
    Vec.VecAccessContiguous,
    Vec.VecAlignmentUnknown,
    Vec.VecBoundsUnknown(Vec.VecRejectUnsupportedMemory(Vec.VecAccessId("store.ys"), "test bounds proof absent"))
)
local alias = Vec.VecAccessNoAlias(load_access.id, store_access.id, "derived from noalias/disjoint-view source fact")
local alias_proof = Vec.VecProofAlias(alias, "load and store bases are disjoint")
local dep = Vec.VecNoDependence(load_access.id, store_access.id, alias_proof)
local store = Vec.VecStoreFact(store_access, Vec.VecExprId("value"))
local facts = Vec.VecLoopFacts(
    Vec.VecLoopId("loop.map"),
    Vec.VecLoopSourceControlRegion("loop.map", Tree.BlockLabel("loop"), Tree.BlockLabel("loop")),
    Vec.VecDomainCounted(Tree.ExprLit(Tree.ExprSem(index_ty, T.MoonSem.ValuePlain, T.MoonSem.ConstClassYes(T.MoonSem.ConstInt(index_ty, "0"))), Core.LitInt("0")), len_expr, Tree.ExprLit(Tree.ExprSem(index_ty, T.MoonSem.ValuePlain, T.MoonSem.ConstClassYes(T.MoonSem.ConstInt(index_ty, "1"))), Core.LitInt("1"))),
    { Vec.VecPrimaryInduction(i_binding, i_expr, Tree.ExprLit(Tree.ExprSem(index_ty, T.MoonSem.ValuePlain, T.MoonSem.ConstClassYes(T.MoonSem.ConstInt(index_ty, "1"))), Core.LitInt("1"))) },
    Vec.VecExprGraph({}),
    { load_access, store_access },
    { alias },
    { dep },
    {},
    { store },
    {},
    {},
    {}
)
assert(facts.aliases[1] == alias)
assert(facts.dependences[1] == dep)
assert(facts.stores[1] == store)

print("moonlift asdl ok")
