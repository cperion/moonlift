package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Code = T.LalinCode
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local CopyPatchLuaTrace = require("lalin.copy_patch_luatrace")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)

local artifact = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
    exact_trip_count = 64,
})

local facts = artifact.instance.schedule.facts
assert(pvm.classof(facts.trip_count) == Stencil.StencilTripCountExact)
assert(facts.trip_count.count == 64)

local saw_trip_obligation = false
for _, obligation in ipairs(facts.proof_obligations or {}) do
    if pvm.classof(obligation.kind) == Stencil.StencilProofTripCount
        and pvm.classof(obligation.kind.trip_count) == Stencil.StencilTripCountExact then
        saw_trip_obligation = true
    end
end
assert(saw_trip_obligation, "exact trip-count fact should create a proof obligation")

local trace_plan = CopyPatchLuaTrace.plan_artifact(artifact)
assert(trace_plan.loop_plan.tail_strategy == "no_tail_trip_count_multiple", "exact trip count should remove generic tail when divisible by group")

io.write("stencil D5 trip count ok\n")
