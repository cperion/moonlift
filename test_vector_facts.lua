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
assert(facts == Vec.VecCountedLoop(
    "func.sum_for_index.stmt.1",
    Sem.SemBindLoopIndex("func.sum_for_index.stmt.1", "i", Sem.SemTIndex),
    Sem.SemExprConstInt(Sem.SemTIndex, "0"),
    Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTIndex)),
    Vec.VecBodyFacts(
        {
            Vec.VecLocalFact(
                Sem.SemBindLocalValue("func.sum_for_index.stmt.1.body.stmt.1", "term", Sem.SemTIndex),
                Vec.VecExprBin(
                    Vec.VecBitAnd,
                    Vec.VecExprBin(
                        Vec.VecAdd,
                        Vec.VecExprBin(
                            Vec.VecMul,
                            Vec.VecExprLaneIndex(Sem.SemBindLoopIndex("func.sum_for_index.stmt.1", "i", Sem.SemTIndex), Sem.SemTIndex),
                            Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1664525"), Sem.SemTIndex),
                            Sem.SemTIndex
                        ),
                        Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1013904223"), Sem.SemTIndex),
                        Sem.SemTIndex
                    ),
                    Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1023"), Sem.SemTIndex),
                    Sem.SemTIndex
                )
            ),
        },
        {
            Vec.VecReductionAdd(
                Sem.SemCarryPort("func.sum_for_index.stmt.1.carries.carry.1", "acc", Sem.SemTIndex, Sem.SemExprConstInt(Sem.SemTIndex, "0")),
                Vec.VecExprBin(
                    Vec.VecBitAnd,
                    Vec.VecExprBin(
                        Vec.VecAdd,
                        Vec.VecExprBin(
                            Vec.VecMul,
                            Vec.VecExprLaneIndex(Sem.SemBindLoopIndex("func.sum_for_index.stmt.1", "i", Sem.SemTIndex), Sem.SemTIndex),
                            Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1664525"), Sem.SemTIndex),
                            Sem.SemTIndex
                        ),
                        Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1013904223"), Sem.SemTIndex),
                        Sem.SemTIndex
                    ),
                    Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1023"), Sem.SemTIndex),
                    Sem.SemTIndex
                )
            ),
        },
        {}
    )
))

local plan = pvm.one(V.vector_loop_plan(loop, 8))
assert(plan == Vec.VecAddReductionPlan(
    "func.sum_for_index.stmt.1",
    8,
    Sem.SemBindLoopIndex("func.sum_for_index.stmt.1", "i", Sem.SemTIndex),
    Sem.SemExprConstInt(Sem.SemTIndex, "0"),
    Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTIndex)),
    Sem.SemCarryPort("func.sum_for_index.stmt.1.carries.carry.1", "acc", Sem.SemTIndex, Sem.SemExprConstInt(Sem.SemTIndex, "0")),
    Vec.VecExprBin(
        Vec.VecBitAnd,
        Vec.VecExprBin(
            Vec.VecAdd,
            Vec.VecExprBin(
                Vec.VecMul,
                Vec.VecExprLaneIndex(Sem.SemBindLoopIndex("func.sum_for_index.stmt.1", "i", Sem.SemTIndex), Sem.SemTIndex),
                Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1664525"), Sem.SemTIndex),
                Sem.SemTIndex
            ),
            Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1013904223"), Sem.SemTIndex),
            Sem.SemTIndex
        ),
        Vec.VecExprInvariant(Sem.SemExprConstInt(Sem.SemTIndex, "1023"), Sem.SemTIndex),
        Sem.SemTIndex
    )
))

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
local no_plan = pvm.one(V.vector_loop_plan(while_loop, 8))
assert(no_plan == Vec.VecNoPlan(Vec.VecRejectLoopShape("while-loop counted-loop detection is not implemented yet")))

print("moonlift vector facts ok")
