package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local CopyPatchLuaTrace = require("lalin.copy_patch_luatrace")(T)
local MC = require("tests.code_ir.copy_patch_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function input(name)
    return Plan.input_expr(name)
end

local function inputs(n)
    local out = {}
    for i = 1, n do out[i] = { name = "x" .. tostring(i), ty = i32 } end
    return out
end

local artifacts = {
    Plan.apply_n_array_artifact({
        tag = "arity0_const",
        result_ty = i32,
        inputs = {},
        expr = Plan.const_expr(iconst(7), i32),
        step_num = 1,
    }),
    Plan.apply_n_array_artifact({
        tag = "arity1_neg",
        result_ty = i32,
        inputs = inputs(1),
        expr = Plan.apply_unary_expr(Stencil.StencilUnaryNeg, input("x1"), i32, { int_semantics = sem }),
        step_num = 1,
    }),
    Plan.apply_n_array_artifact({
        tag = "arity2_add",
        result_ty = i32,
        inputs = inputs(2),
        expr = Plan.apply_binary_expr(Stencil.StencilBinaryAdd, input("x1"), input("x2"), i32, { int_semantics = sem }),
        step_num = 1,
    }),
    Plan.apply_n_array_artifact({
        tag = "arity3_select",
        result_ty = i32,
        inputs = inputs(3),
        expr = Plan.apply_select_expr(Stencil.StencilPredNonZero, input("x1"), input("x2"), input("x3"), i32),
        step_num = 1,
    }),
    Plan.apply_n_array_artifact({
        tag = "arity4_mix",
        result_ty = i32,
        inputs = inputs(4),
        expr = Plan.apply_binary_expr(
            Stencil.StencilBinaryAdd,
            Plan.apply_binary_expr(Stencil.StencilBinaryMul, input("x1"), input("x2"), i32, { int_semantics = sem }),
            Plan.apply_binary_expr(Stencil.StencilBinarySub, input("x3"), input("x4"), i32, { int_semantics = sem }),
            i32,
            { int_semantics = sem }
        ),
        step_num = 1,
    }),
}

for i, artifact in ipairs(artifacts) do
    local shape = Plan.artifact_shape(artifact)
    assert(shape.kind == "apply_n_array", "artifact " .. tostring(i) .. " should be generic apply_n")
    assert(#shape.inputs == i - 1, "artifact " .. tostring(i) .. " should have saturated arity " .. tostring(i - 1))
end

local function exercise(symbols, label)
    local out = ffi.new("int32_t[5]")
    local x1 = ffi.new("int32_t[5]", { 1, 0, -3, 4, 5 })
    local x2 = ffi.new("int32_t[5]", { 10, 20, 30, 40, 50 })
    local x3 = ffi.new("int32_t[5]", { -10, -20, -30, -40, -50 })
    local x4 = ffi.new("int32_t[5]", { 2, 3, 4, 5, 6 })

    assert(symbols[artifacts[1].symbol.text], label .. " missing arity0")(out, 0, 5)
    for i = 0, 4 do assert(out[i] == 7, label .. " arity0") end

    assert(symbols[artifacts[2].symbol.text], label .. " missing arity1")(out, x1, 0, 5)
    assert(out[0] == -1 and out[1] == 0 and out[2] == 3 and out[3] == -4 and out[4] == -5, label .. " arity1")

    assert(symbols[artifacts[3].symbol.text], label .. " missing arity2")(out, x1, x2, 0, 5)
    assert(out[0] == 11 and out[1] == 20 and out[2] == 27 and out[3] == 44 and out[4] == 55, label .. " arity2")

    assert(symbols[artifacts[4].symbol.text], label .. " missing arity3")(out, x1, x2, x3, 0, 5)
    assert(out[0] == 10 and out[1] == -20 and out[2] == 30 and out[3] == 40 and out[4] == 50, label .. " arity3")

    assert(symbols[artifacts[5].symbol.text], label .. " missing arity4")(out, x1, x2, x3, x4, 0, 5)
    assert(out[0] == -2 and out[1] == -23 and out[2] == -124 and out[3] == 115 and out[4] == 194, label .. " arity4")
end

local mc, mc_err, mc_src = MC.compile(T, artifacts, { stem = "test_stencil_apply_n" })
assert(mc ~= nil, tostring(mc_err) .. "\n" .. tostring(mc_src))
exercise(mc.symbols, "mc")

local bc = assert(CopyPatchLuaTrace.realize_artifacts(artifacts, { stem = "test_stencil_apply_n_bc" }))
exercise(bc.symbols, "bc")

io.write("stencil apply_n ok\n")
