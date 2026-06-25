package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
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
local StencilBinary = require("tests.code_ir.stencil_binary_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local bool8 = Code.CodeTyBool8
local pair_ty = Code.CodeTyNamed("Demo", "PairSoA", Ty.TNamed(Ty.TypeRefGlobal("Demo", "PairSoA")))
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function reduction(kind, init)
    return {
        kind = kind,
        init = iconst(init),
        int_semantics = sem,
        float_mode = nil,
    }
end

local function soa_component(field_name, component_index)
    return Stencil.StencilTopologySoAComponent(
        Stencil.StencilTopologyContiguous(1),
        pair_ty,
        field_name,
        component_index
    )
end

local function access_named(desc, name)
    for _, access in ipairs(desc.accesses or {}) do
        if access.name == name then return access end
    end
    error("missing descriptor access " .. tostring(name))
end

local artifacts = {
    StencilArtifactPlan.zip_map_array_artifact(Stencil.StencilBinaryAdd, {
        lhs_ty = i32,
        rhs_ty = i32,
        result_ty = i32,
        step_num = 1,
        dst_topology = soa_component("sum", 2),
        lhs_topology = soa_component("left", 0),
        rhs_topology = soa_component("right", 1),
    }),
    StencilArtifactPlan.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, {
        lhs_ty = i32,
        rhs_ty = i32,
        mapped_ty = i32,
        result_ty = i32,
        step_num = 1,
        lhs_topology = soa_component("left", 0),
        rhs_topology = soa_component("right", 1),
    }),
    StencilArtifactPlan.zip_compare_array_artifact(Core.CmpLt, {
        lhs_ty = i32,
        rhs_ty = i32,
        result_ty = bool8,
        step_num = 1,
        dst_topology = soa_component("lt", 2),
        lhs_topology = soa_component("left", 0),
        rhs_topology = soa_component("right", 1),
    }),
    StencilArtifactPlan.partition_array_artifact(Stencil.StencilPredGtConst(iconst(0)), {
        elem_ty = i32,
        step_num = 1,
        dst_topology = soa_component("positive_then_rest", 1),
        array_topology = soa_component("left", 0),
    }),
}

for _, artifact in ipairs(artifacts) do
    for _, access in ipairs(artifact.instance.descriptor.accesses or {}) do
        local top = access.topology
        if pvm.classof(top) ~= Stencil.StencilTopologyScalar then
            assert(pvm.classof(top) == Stencil.StencilTopologySoAComponent, "access should keep SoA component topology")
            assert(top.record_ty == pair_ty, "SoA component should keep record type")
        end
    end
end

local build, err, src = StencilBinary.compile(T, artifacts, {
    stem = "test_stencil_bank_soa_components",
})
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))
assert(src:match("_soa_left_c0"), src)
assert(src:match("_soa_right_c1"), src)
assert(src:match("_soa_sum_c2"), src)
assert(not src:match("%.left"), "SoA C source should use component buffers, not AoS field loads")

local left = ffi.new("int32_t[5]", { 1, -2, 5, 0, 3 })
local right = ffi.new("int32_t[5]", { 10, 20, -5, 7, 4 })
local out = ffi.new("int32_t[5]")
local mask = ffi.new("uint8_t[5]")

local function sym(artifact)
    return assert(build.symbols[artifact.symbol.text], artifact.symbol.text)
end

sym(artifacts[1])(out, left, right, 0, 5)
assert(out[0] == 11 and out[1] == 18 and out[2] == 0 and out[3] == 7 and out[4] == 7, "SoA zip map")

assert(sym(artifacts[2])(left, right, 0, 5, 0) == 43, "SoA zip reduce")

sym(artifacts[3])(mask, left, right, 0, 5)
assert(mask[0] == 1 and mask[1] == 1 and mask[2] == 0 and mask[3] == 1 and mask[4] == 1, "SoA zip compare")

assert(sym(artifacts[4])(out, left, 0, 5) == 3, "SoA partition split")
assert(out[0] == 1 and out[1] == 5 and out[2] == 3 and out[3] == -2 and out[4] == 0, "SoA partition order")

assert(access_named(artifacts[1].instance.descriptor, "lhs").topology.field_name == "left")

io.write("lalin stencil_bank SoA components ok\n")
