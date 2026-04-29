package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Facts = require("moonlift.vec_loop_facts")
local Decide = require("moonlift.vec_loop_decide")

local T = pvm.context()
A.Define(T)
local F = Facts.Define(T)
local D = Decide.Define(T)
local C = T.Moon2Core
local Ty = T.Moon2Type
local B = T.Moon2Bind
local Tr = T.Moon2Tree
local V = T.Moon2Vec

local i32 = Ty.TScalar(C.ScalarI32)
local bool = Ty.TScalar(C.ScalarBool)
local function lit(raw) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(raw)) end
local function ref(binding) return Tr.ExprRef(Tr.ExprTyped(binding.ty), B.ValueRefBinding(binding)) end

local i = B.Binding(C.Id("control:param:control.sum:loop:i"), "i", i32, B.BindingClassEntryBlockParam("control.sum", "loop", 1))
local acc = B.Binding(C.Id("control:param:control.sum:loop:acc"), "acc", i32, B.BindingClassEntryBlockParam("control.sum", "loop", 2))
local n = B.Binding(C.Id("arg:n"), "n", i32, B.BindingClassArg(0))
local xs = B.Binding(C.Id("arg:xs"), "xs", Ty.TScalar(C.ScalarRawPtr), B.BindingClassArg(1))
local xs_i = Tr.ExprIndex(Tr.ExprTyped(i32), Tr.IndexBaseView(Tr.ViewContiguous(ref(xs), i32, ref(n))), ref(i))

local region = Tr.ControlExprRegion(
    "control.sum",
    i32,
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), {
        Tr.EntryBlockParam("i", i32, lit("0")),
        Tr.EntryBlockParam("acc", i32, lit("0")),
    }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpGe, ref(i), ref(n)),
            { Tr.StmtYieldValue(Tr.StmtTyped, ref(acc)) },
            {}
        ),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("loop"), {
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(i), lit("1"))),
            Tr.JumpArg("acc", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(acc), xs_i)),
        }),
    }),
    {}
)

local facts = F.facts(region)
assert(facts.loop == V.VecLoopId("control.sum"))
assert(facts.source == V.VecLoopSourceControlRegion("control.sum", Tr.BlockLabel("loop"), Tr.BlockLabel("loop")))
assert(facts.domain == V.VecDomainCounted(lit("0"), ref(n), lit("1")))
assert(#facts.inductions == 1)
assert(facts.inductions[1] == V.VecPrimaryInduction(i, lit("0"), lit("1")))
assert(#facts.reductions == 1)
assert(pvm.classof(facts.reductions[1]) == V.VecReductionAdd)
assert(facts.reductions[1].accumulator == acc)
assert(facts.reductions[1].value == V.VecExprId("jump.acc.rhs"))
assert(#facts.memory == 1)
assert(facts.memory[1] == V.VecMemoryAccess(V.VecAccessId("jump.acc.rhs"), V.VecAccessLoad, V.VecMemoryBaseView(Tr.ViewContiguous(ref(xs), i32, ref(n))), V.VecExprId("jump.acc.rhs.index"), i32, V.VecAccessContiguous, V.VecAlignmentUnknown, V.VecBoundsUnknown(V.VecRejectUnsupportedMemory(V.VecAccessId("jump.acc.rhs"), "bounds proof deferred"))))
assert(#facts.rejects == 0)

local target = V.VecTargetModel(V.VecTargetCraneliftJit, {
    V.VecTargetVectorBits(128),
    V.VecTargetSupportsShape(V.VecVectorShape(V.VecElemI32, 4)),
})
local decision = D.decide(facts, target)
assert(pvm.classof(decision.chosen) == V.VecLoopVector)
assert(decision.chosen.shape == V.VecVectorShape(V.VecElemI32, 4))
assert(decision.chosen.unroll == 1)
assert(decision.considered[1].elems_per_iter == 4)

local unsupported = D.decide(facts, V.VecTargetModel(V.VecTargetNamed("scalar-only"), { V.VecTargetVectorBits(128) }))
assert(pvm.classof(unsupported.chosen) == V.VecLoopScalar)
assert(#unsupported.chosen.vector_rejects == 1)

local unsupported_region = Tr.ControlExprRegion(
    "control.unsupported",
    i32,
    Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, { Tr.StmtYieldValue(Tr.StmtTyped, lit("0")) }),
    {}
)
local rejected = F.facts(unsupported_region)
assert(pvm.classof(rejected.domain) == V.VecDomainRejected)
assert(#rejected.rejects == 1)
assert(rejected.source == V.VecLoopSourceRejected(V.VecRejectUnsupportedLoop(V.VecLoopId("control.unsupported"), "missing self backedge jump")))

local acc_first = B.Binding(C.Id("control:param:control.swapped:loop:acc"), "acc", i32, B.BindingClassEntryBlockParam("control.swapped", "loop", 1))
local i_second = B.Binding(C.Id("control:param:control.swapped:loop:i"), "i", i32, B.BindingClassEntryBlockParam("control.swapped", "loop", 2))
local swapped = Tr.ControlExprRegion(
    "control.swapped",
    i32,
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), {
        Tr.EntryBlockParam("acc", i32, lit("0")),
        Tr.EntryBlockParam("i", i32, lit("0")),
    }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpLe, ref(n), ref(i_second)),
            { Tr.StmtYieldValue(Tr.StmtTyped, ref(acc_first)) },
            {}
        ),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("loop"), {
            Tr.JumpArg("acc", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(acc_first), ref(i_second))),
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(i_second), lit("1"))),
        }),
    }),
    {}
)
local swapped_facts = F.facts(swapped)
assert(swapped_facts.domain == V.VecDomainCounted(lit("0"), ref(n), lit("1")))
assert(swapped_facts.inductions[1] == V.VecPrimaryInduction(i_second, lit("0"), lit("1")))
assert(swapped_facts.reductions[1].accumulator == acc_first)
assert(#swapped_facts.rejects == 0)

local ys = B.Binding(C.Id("arg:ys"), "ys", Ty.TScalar(C.ScalarRawPtr), B.BindingClassArg(2))
local map_i = B.Binding(C.Id("control:param:control.map:loop:i"), "i", i32, B.BindingClassEntryBlockParam("control.map", "loop", 1))
local map_xs_i = Tr.ExprIndex(Tr.ExprTyped(i32), Tr.IndexBaseView(Tr.ViewContiguous(ref(xs), i32, ref(n))), ref(map_i))
local map_ys_i = Tr.PlaceIndex(Tr.PlaceTyped(i32), Tr.IndexBaseView(Tr.ViewContiguous(ref(ys), i32, ref(n))), ref(map_i))
local map_region = Tr.ControlStmtRegion(
    "control.map",
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), { Tr.EntryBlockParam("i", i32, lit("0")) }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpGe, ref(map_i), ref(n)),
            { Tr.StmtYieldVoid(Tr.StmtTyped) },
            {}
        ),
        Tr.StmtSet(Tr.StmtTyped, map_ys_i, map_xs_i),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("loop"), {
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(map_i), lit("1"))),
        }),
    }),
    {}
)
local map_facts = F.facts(map_region)
assert(map_facts.source == V.VecLoopSourceControlRegion("control.map", Tr.BlockLabel("loop"), Tr.BlockLabel("loop")))
assert(map_facts.domain == V.VecDomainCounted(lit("0"), ref(n), lit("1")))
assert(#map_facts.memory == 2)
assert(#map_facts.aliases == 1)
assert(pvm.classof(map_facts.aliases[1]) == V.VecAliasUnknown)
assert(#map_facts.dependences == 1)
assert(pvm.classof(map_facts.dependences[1]) == V.VecDependenceUnknown)
assert(#map_facts.stores == 1)
assert(map_facts.stores[1].access.access_kind == V.VecAccessStore)
assert(map_facts.stores[1].access.pattern == V.VecAccessContiguous)
assert(#map_facts.rejects == 0)
local map_decision = D.decide(map_facts, target)
assert(pvm.classof(map_decision.chosen) == V.VecLoopScalar)
assert(#map_decision.chosen.vector_rejects == 1)

local inplace_i = B.Binding(C.Id("control:param:control.inplace:loop:i"), "i", i32, B.BindingClassEntryBlockParam("control.inplace", "loop", 1))
local inplace_ys_i = Tr.PlaceIndex(Tr.PlaceTyped(i32), Tr.IndexBaseView(Tr.ViewContiguous(ref(ys), i32, ref(n))), ref(inplace_i))
local inplace_region = Tr.ControlStmtRegion(
    "control.inplace",
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), { Tr.EntryBlockParam("i", i32, lit("0")) }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpGe, ref(inplace_i), ref(n)),
            { Tr.StmtYieldVoid(Tr.StmtTyped) },
            {}
        ),
        Tr.StmtSet(Tr.StmtTyped, inplace_ys_i, Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, Tr.ExprIndex(Tr.ExprTyped(i32), Tr.IndexBaseView(Tr.ViewContiguous(ref(ys), i32, ref(n))), ref(inplace_i)), lit("1"))),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("loop"), {
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(inplace_i), lit("1"))),
        }),
    }),
    {}
)
local inplace_facts = F.facts(inplace_region)
assert(#inplace_facts.memory == 2)
assert(#inplace_facts.aliases == 1)
assert(pvm.classof(inplace_facts.aliases[1]) == V.VecAccessSameBase)
assert(#inplace_facts.dependences == 1)
assert(pvm.classof(inplace_facts.dependences[1]) == V.VecNoDependence)
assert(#inplace_facts.rejects == 0)

local stride_i = B.Binding(C.Id("control:param:control.stride:loop:i"), "i", i32, B.BindingClassEntryBlockParam("control.stride", "loop", 1))
local stride_acc = B.Binding(C.Id("control:param:control.stride:loop:acc"), "acc", i32, B.BindingClassEntryBlockParam("control.stride", "loop", 2))
local stride_xs_i = Tr.ExprIndex(Tr.ExprTyped(i32), Tr.IndexBaseView(Tr.ViewStrided(ref(xs), i32, ref(n), lit("2"))), ref(stride_i))
local stride_region = Tr.ControlExprRegion(
    "control.stride",
    i32,
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), {
        Tr.EntryBlockParam("i", i32, lit("0")),
        Tr.EntryBlockParam("acc", i32, lit("0")),
    }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpGe, ref(stride_i), ref(n)),
            { Tr.StmtYieldValue(Tr.StmtTyped, ref(stride_acc)) },
            {}
        ),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("loop"), {
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(stride_i), lit("1"))),
            Tr.JumpArg("acc", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(stride_acc), stride_xs_i)),
        }),
    }),
    {}
)
local stride_facts = F.facts(stride_region)
assert(#stride_facts.memory == 1)
assert(stride_facts.memory[1].pattern == V.VecAccessStrided(2))
local stride_decision = D.decide(stride_facts, target)
assert(pvm.classof(stride_decision.chosen) == V.VecLoopScalar)
assert(#stride_decision.chosen.vector_rejects == 1)
assert(pvm.classof(stride_decision.chosen.vector_rejects[1]) == V.VecRejectUnsupportedMemory)

local unit_stride_i = B.Binding(C.Id("control:param:control.unit_stride:loop:i"), "i", i32, B.BindingClassEntryBlockParam("control.unit_stride", "loop", 1))
local unit_stride_acc = B.Binding(C.Id("control:param:control.unit_stride:loop:acc"), "acc", i32, B.BindingClassEntryBlockParam("control.unit_stride", "loop", 2))
local unit_stride_xs_i = Tr.ExprIndex(Tr.ExprTyped(i32), Tr.IndexBaseView(Tr.ViewStrided(ref(xs), i32, ref(n), lit("1"))), ref(unit_stride_i))
local unit_stride_region = Tr.ControlExprRegion(
    "control.unit_stride",
    i32,
    Tr.EntryControlBlock(Tr.BlockLabel("loop"), {
        Tr.EntryBlockParam("i", i32, lit("0")),
        Tr.EntryBlockParam("acc", i32, lit("0")),
    }, {
        Tr.StmtIf(Tr.StmtTyped,
            Tr.ExprCompare(Tr.ExprTyped(bool), C.CmpGe, ref(unit_stride_i), ref(n)),
            { Tr.StmtYieldValue(Tr.StmtTyped, ref(unit_stride_acc)) },
            {}
        ),
        Tr.StmtJump(Tr.StmtTyped, Tr.BlockLabel("loop"), {
            Tr.JumpArg("i", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(unit_stride_i), lit("1"))),
            Tr.JumpArg("acc", Tr.ExprBinary(Tr.ExprTyped(i32), C.BinAdd, ref(unit_stride_acc), unit_stride_xs_i)),
        }),
    }),
    {}
)
local unit_stride_facts = F.facts(unit_stride_region)
assert(#unit_stride_facts.memory == 1)
assert(unit_stride_facts.memory[1].pattern == V.VecAccessContiguous)
local unit_stride_decision = D.decide(unit_stride_facts, target)
assert(pvm.classof(unit_stride_decision.chosen) == V.VecLoopVector)

print("moonlift vec_loop_facts_decide ok")
