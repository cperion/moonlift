package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local LLBL = require("llbl")
local C = require("llbl.c")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Ty = T.LalinType
local Value = T.LalinValue
local Stencil = T.LalinStencil
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local StencilBinary = require("tests.code_ir.copy_patch_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local bool8 = Code.CodeTyBool8
local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function pred(cmp, ty, value)
    return Stencil.StencilPredCompareConst(cmp, ty, value)
end

local function reduction(kind, init)
    return {
        kind = kind,
        init = iconst(init),
        int_semantics = sem,
        float_mode = nil,
    }
end

local function field_layout()
    return Stencil.StencilLayoutFieldProjection(
        Stencil.StencilLayoutContiguous(1),
        pair_ty,
        "right",
        4
    )
end

local artifacts = {
    StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
        elem_ty = i32,
        result_ty = i32,
        step_num = 1,
        array_layout = field_layout(),
    }),
    StencilArtifactPlan.map_array_artifact(Stencil.StencilUnaryNeg, {
        elem_ty = i32,
        result_ty = i32,
        step_num = 1,
        src_layout = field_layout(),
    }),
    StencilArtifactPlan.find_array_artifact(pred(Core.CmpEq, i32, iconst(20)), {
        elem_ty = i32,
        step_num = 1,
        array_layout = field_layout(),
    }),
    StencilArtifactPlan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(10)), {
        elem_ty = i32,
        result_ty = bool8,
        step_num = 1,
        src_layout = field_layout(),
    }),
    StencilArtifactPlan.fill_array_artifact({
        elem_ty = i32,
        value = iconst(99),
        step_num = 1,
        dst_layout = field_layout(),
    }),
}

local ffi_preamble = "typedef struct { int32_t left; int32_t right; } Demo_Pair;"
local c_decls = {
    C.typedef_struct [LLBL.N.Demo_Pair] {
        LLBL.N.left [C.i32],
        LLBL.N.right [C.i32],
    },
}
local build, err, src = StencilBinary.compile(T, artifacts, {
    stem = "test_copy_patch_mc_field_projection",
    c_decls = c_decls,
    ffi_preamble = ffi_preamble,
})
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))
assert(src:match("Demo_Pair const %*%s*__restrict%s*xs"), src)
assert(src:match("Demo_Pair %*%s*__restrict%s*dst"), src)
assert(src:match("xs%[i%]%.right"), src)
assert(src:match("dst%[i%]%.right"), src)

local xs = ffi.new("Demo_Pair[4]")
xs[0].left, xs[0].right = 1, 10
xs[1].left, xs[1].right = 2, 20
xs[2].left, xs[2].right = 3, -5
xs[3].left, xs[3].right = 4, 7

local out = ffi.new("int32_t[4]")
local mask = ffi.new("uint8_t[4]")

local function sym(artifact)
    return assert(build.symbols[artifact.symbol.text], artifact.symbol.text)
end

assert(sym(artifacts[1])(xs, 0, 4, 0) == 32, "field reduce")

sym(artifacts[2])(out, xs, 0, 4)
assert(out[0] == -10 and out[1] == -20 and out[2] == 5 and out[3] == -7, "field map")

assert(sym(artifacts[3])(xs, 0, 4) == 1, "field find")

sym(artifacts[4])(mask, xs, 0, 4)
assert(mask[0] == 0 and mask[1] == 1 and mask[2] == 0 and mask[3] == 0, "field compare")

sym(artifacts[5])(xs, 1, 3, 99)
assert(xs[0].right == 10 and xs[1].right == 99 and xs[2].right == 99 and xs[3].right == 7, "field fill")

io.write("lalin copy_patch_mc field projection ok\n")
