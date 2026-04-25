package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Source = require("moonlift.source")
local VecFacts = require("moonlift.vector_facts")

local T = pvm.context()
A.Define(T)
local S = Source.Define(T)
local V = VecFacts.Define(T)

local Sem = T.MoonliftSem
local Vec = T.MoonliftVec

local sem = S.sem_module([[
func sum_for_index(n: index) -> index
    for i in 0..n with acc: index = 0 do
        let term: index = (i * 1664525 + 1013904223) & 1023
        next acc = acc + term
    end
    return acc
end
]])

local loop = sem.items[1].func.body[1].loop
local facts = pvm.one(V.vector_loop_facts(loop))
assert(facts.loop == Vec.VecLoopId("func.sum_for_index.stmt.1"))
assert(facts.domain == Vec.VecDomainCounted(
    Sem.SemExprConstInt(Sem.SemTIndex, "0"),
    Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTIndex)),
    Sem.SemExprConstInt(Sem.SemTIndex, "1")
))
assert(#facts.inductions == 1)
assert(facts.inductions[1] == Vec.VecPrimaryInduction(
    Sem.SemBindLoopIndex("func.sum_for_index.stmt.1", "i", Sem.SemTIndex),
    Sem.SemExprConstInt(Sem.SemTIndex, "0"),
    Sem.SemExprConstInt(Sem.SemTIndex, "1")
))
assert(#facts.exprs.exprs > 0)
assert(#facts.reductions == 1)
assert(#facts.rejects == 0)
assert(pvm.classof(facts.reductions[1]) == Vec.VecReductionAdd)

local range_found = false
for i = 1, #facts.ranges do
    if pvm.classof(facts.ranges[i]) == Vec.VecRangeBitAnd and facts.ranges[i].max_value == "1023" then
        range_found = true
    end
end
assert(range_found, "expected bitand range proof fact")

local decision = pvm.one(V.vector_loop_decision(loop, 8, 1))
assert(decision.facts == facts)
assert(decision.chosen == Vec.VecLoopVector(
    Vec.VecLoopId("func.sum_for_index.stmt.1"),
    Vec.VecVectorShape(Vec.VecElemIndex, 8),
    1,
    Vec.VecTailScalar,
    decision.chosen.proofs
))
assert(#decision.chosen.proofs >= 3)

local chunk_decision = pvm.one(V.vector_loop_decision(loop, 4, 4, 1048576))
assert(pvm.classof(chunk_decision.chosen) == Vec.VecLoopChunkedNarrowVector)
assert(chunk_decision.chosen.narrow_shape == Vec.VecVectorShape(Vec.VecElemI32, 4))
assert(chunk_decision.chosen.unroll == 4)
assert(chunk_decision.chosen.chunk_elems == 1048576)
assert(pvm.classof(chunk_decision.chosen.narrow_proof) == Vec.VecProofNarrowSafe)

local unrolled_module = pvm.one(V.vector_module(sem, nil, 2, 4))
assert(unrolled_module.source == sem)
assert(#unrolled_module.funcs == 1)
assert(pvm.classof(unrolled_module.funcs[1]) == Vec.VecFuncVector)
assert(#unrolled_module.funcs[1].blocks > 0, "expected VecBlock skeleton for ordinary vector decision")

local vec_module = pvm.one(V.vector_module(sem, nil, 4, 4, 1048576))
assert(vec_module.source == sem)
assert(#vec_module.funcs == 1)
assert(pvm.classof(vec_module.funcs[1]) == Vec.VecFuncVector)
assert(vec_module.funcs[1].decisions[1] == chunk_decision)
assert(#vec_module.funcs[1].blocks > 0, "expected VecBlock skeleton for chunked narrow vector decision")

local not_yet = S.sem_module([[
func sum_while(n: index) -> index
    while i < n with i: index = 0, acc: index = 0 do
        let term: index = (i * 1664525 + 1013904223) & 1023
        next i = i + 1
        next acc = acc + term
    end
    return acc
end
]])
local while_loop = not_yet.items[1].func.body[1].loop
local scalar_decision = pvm.one(V.vector_loop_decision(while_loop, 8, 1))
assert(pvm.classof(scalar_decision.chosen) == Vec.VecLoopScalar)
assert(#scalar_decision.chosen.vector_rejects == 1)
assert(scalar_decision.chosen.vector_rejects[1] == Vec.VecRejectUnsupportedLoop(
    Vec.VecLoopId("func.sum_while.stmt.1"),
    "while-loop counted-loop detection is not implemented yet"
))

local p_param = Sem.SemParam("p", Sem.SemTPtrTo(Sem.SemTIndex))
local n_param = Sem.SemParam("n", Sem.SemTIndex)
local map_loop_id = "loop.map_in_place"
local map_index = Sem.SemBindLoopIndex(map_loop_id, "i", Sem.SemTIndex)
local p_binding = Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTIndex))
local n_binding = Sem.SemBindArg(1, "n", Sem.SemTIndex)
local map_view = Sem.SemViewContiguous(Sem.SemExprBinding(p_binding), Sem.SemTIndex, Sem.SemExprBinding(n_binding))
local map_load = Sem.SemExprIndex(Sem.SemIndexBaseView(map_view), Sem.SemExprBinding(map_index), Sem.SemTIndex)
local map_place = Sem.SemPlaceIndex(Sem.SemIndexBaseView(map_view), Sem.SemExprBinding(map_index), Sem.SemTIndex)
local map_loop = Sem.SemOverStmt(
    map_loop_id,
    Sem.SemIndexPort("i", Sem.SemTIndex),
    Sem.SemDomainRange(Sem.SemExprBinding(n_binding)),
    {},
    { Sem.SemStmtSet(map_place, Sem.SemExprAdd(Sem.SemTIndex, map_load, Sem.SemExprConstInt(Sem.SemTIndex, "1"))) },
    {}
)
local map_facts = pvm.one(V.vector_loop_facts(map_loop))
assert(#map_facts.memory == 2, "expected load and store memory facts")
assert(#map_facts.stores == 1, "expected store fact")
assert(#map_facts.dependences == 1, "expected explicit dependence fact")
assert(pvm.classof(map_facts.dependences[1]) == Vec.VecNoDependence)
local map_decision = pvm.one(V.vector_loop_decision(map_loop, 2, 2))
assert(pvm.classof(map_decision.chosen) == Vec.VecLoopVector)

local q_binding = Sem.SemBindArg(2, "q", Sem.SemTPtrTo(Sem.SemTIndex))
local q_view = Sem.SemViewContiguous(Sem.SemExprBinding(q_binding), Sem.SemTIndex, Sem.SemExprBinding(n_binding))
local unknown_loop = Sem.SemOverStmt(
    "loop.map_unknown_alias",
    Sem.SemIndexPort("i", Sem.SemTIndex),
    Sem.SemDomainRange(Sem.SemExprBinding(n_binding)),
    {},
    { Sem.SemStmtSet(
        Sem.SemPlaceIndex(Sem.SemIndexBaseView(q_view), Sem.SemExprBinding(Sem.SemBindLoopIndex("loop.map_unknown_alias", "i", Sem.SemTIndex)), Sem.SemTIndex),
        Sem.SemExprAdd(Sem.SemTIndex,
            Sem.SemExprIndex(Sem.SemIndexBaseView(map_view), Sem.SemExprBinding(Sem.SemBindLoopIndex("loop.map_unknown_alias", "i", Sem.SemTIndex)), Sem.SemTIndex),
            Sem.SemExprConstInt(Sem.SemTIndex, "1"))
    ) },
    {}
)
local unknown_facts = pvm.one(V.vector_loop_facts(unknown_loop))
assert(#unknown_facts.dependences == 1)
assert(pvm.classof(unknown_facts.dependences[1]) == Vec.VecDependenceUnknown)
local unknown_decision = pvm.one(V.vector_loop_decision(unknown_loop, 2, 2))
assert(pvm.classof(unknown_decision.chosen) == Vec.VecLoopScalar)

print("moonlift vector facts ok")
