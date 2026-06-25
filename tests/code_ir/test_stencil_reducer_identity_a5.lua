package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local ReductionAlgebra = require("lalin.reduction_algebra")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(ty, raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(raw))))
end

local function reduction(kind, init)
    return {
        kind = kind,
        init = init,
        int_semantics = sem,
        float_mode = nil,
    }
end

local function raw_identity(artifact)
    return ReductionAlgebra.literal_identity_raw(artifact.instance.descriptor.mode.reducer.identity)
end

local add = Plan.reduce_array_artifact(reduction(Value.ReductionAdd, iconst(i32, 0)), nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
})
assert(raw_identity(add) == "0", "add identity should be derived as 0")
assert(Plan.artifact_shape(add).identity == add.instance.descriptor.mode.reducer.identity, "shape should expose reducer identity")

local max_u8 = Plan.reduce_array_artifact(reduction(Value.ReductionMax, nil), nil, {
    elem_ty = u8,
    result_ty = u8,
    step_num = 1,
})
assert(raw_identity(max_u8) == "0", "unsigned max identity should be derived as 0")

local min_u8 = Plan.reduce_array_artifact(reduction(Value.ReductionMin, nil), nil, {
    elem_ty = u8,
    result_ty = u8,
    step_num = 1,
})
assert(raw_identity(min_u8) == "255", "unsigned min identity should be derived as max value")

local seeded_add = Plan.reduce_array_artifact(reduction(Value.ReductionAdd, iconst(i32, 1)), nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
})
assert(raw_identity(seeded_add) == "0", "source reduction seed must not become the reducer identity")

io.write("stencil A5 reducer identity ok\n")
