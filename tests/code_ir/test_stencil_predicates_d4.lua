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
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local range_pred = Stencil.StencilPredRange(i32, Core.CmpGe, iconst(0), Core.CmpLe, iconst(10))
local compound_pred = Stencil.StencilPredAnd({
    range_pred,
    Stencil.StencilPredNot(Stencil.StencilPredCompareConst(Core.CmpEq, i32, iconst(5))),
})
local finite_pred = Stencil.StencilPredIsFinite(f64)

local artifacts = {
    Plan.compare_array_artifact(range_pred, { elem_ty = i32, result_ty = bool8, step_num = 1 }),
    Plan.compare_array_artifact(compound_pred, { elem_ty = i32, result_ty = bool8, step_num = 1 }),
    Plan.compare_array_artifact(finite_pred, { elem_ty = f64, result_ty = bool8, step_num = 1 }),
}

local function expect_u8(out, values, label)
    for i = 1, #values do
        assert(out[i - 1] == values[i], label .. " at " .. tostring(i))
    end
end

local function exercise(symbols, label)
    local xs = ffi.new("int32_t[5]", { -1, 0, 5, 10, 11 })
    local out = ffi.new("uint8_t[5]")

    assert(symbols[artifacts[1].symbol.text], label .. " missing range predicate")(out, xs, 0, 5)
    expect_u8(out, { 0, 1, 1, 1, 0 }, label .. " range")

    assert(symbols[artifacts[2].symbol.text], label .. " missing compound predicate")(out, xs, 0, 5)
    expect_u8(out, { 0, 1, 0, 1, 0 }, label .. " compound")

    local inf = 1 / 0
    local nan = 0 / 0
    local fs = ffi.new("double[4]", { 0, inf, nan, -2.5 })
    local fout = ffi.new("uint8_t[4]")
    assert(symbols[artifacts[3].symbol.text], label .. " missing finite predicate")(fout, fs, 0, 4)
    expect_u8(fout, { 1, 0, 0, 1 }, label .. " finite")
end

local mc, mc_err, mc_src = MC.compile(T, artifacts, { stem = "test_stencil_predicates_d4" })
assert(mc ~= nil, tostring(mc_err) .. "\n" .. tostring(mc_src))
assert(mc_src:match("isfinite"), "MC predicate source should emit float-class predicate")
exercise(mc.symbols, "mc")

local bc = assert(CopyPatchLuaTrace.realize_artifacts(artifacts, { stem = "test_stencil_predicates_d4_bc" }))
exercise(bc.symbols, "bc")

io.write("stencil D4 predicates ok\n")
