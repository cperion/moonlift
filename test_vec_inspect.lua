package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Inspect = require("moonlift.vec_inspect")

local T = pvm.context()
A2.Define(T)
local V = T.Moon2Vec
local I = Inspect.Define(T)

local loop = V.VecLoopId("loop")
local facts = V.VecLoopFacts(loop, V.VecLoopSourceRejected(V.VecRejectUnsupportedLoop(loop, "test source")), V.VecDomainRejected(V.VecRejectUnsupportedLoop(loop, "test domain")), {}, V.VecExprGraph({}), {}, {}, {}, {}, {}, {}, {}, { V.VecRejectUnsupportedLoop(loop, "test") })
local reject = V.VecRejectUnsupportedLoop(loop, "test")
local shape = V.VecLoopScalar(loop, { reject })
local decision = V.VecLoopDecision(facts, V.VecIllegal({ reject }), V.VecScheduleScalar({ reject }), shape, { V.VecShapeScore(shape, 1, 0, "test") })

local item = I.decision(decision)
assert(pvm.classof(item) == V.VecScheduleInspection)
assert(item.loop == loop)
assert(item.legality == decision.legality)
assert(item.schedule == decision.schedule)
assert(#item.considered == 1)

local report = I.decisions({ decision })
assert(pvm.classof(report) == V.VecInspectionReport)
assert(#report.schedules == 1 and report.schedules[1] == item)

print("moonlift vec_inspect ok")
