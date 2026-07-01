package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local ResidualLuaTrace = require("lalin.residual_luatrace")(T)
local MC = require("tests.code_ir.residual_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function reduction(op, init)
    return {
        op = op,
        init = iconst(init),
        int_semantics = sem,
        float_mode = nil,
    }
end

local function input(name)
    return Plan.input_expr(name)
end

local function inputs(n)
    local out = {}
    for i = 1, n do out[i] = { name = "x" .. tostring(i), ty = i32 } end
    return out
end

local function range_nd_producer(...)
    local extents = { ... }
    local axes = {}
    for i = 1, #extents do
        axes[i] = Stencil.StencilProducerAxis(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward)
    end
    return Stencil.StencilProducer(nil, Stencil.StencilProduceRangeND(axes))
end

local function axis(step, order)
    return Stencil.StencilProducerAxis(Code.CodeTyIndex, nil, nil, step or 1, order or Stencil.StencilProducerForward)
end

local function range_nd_axes(...)
    return Stencil.StencilProducer(nil, Stencil.StencilProduceRangeND({ ... }))
end

local function tiled_nd_producer(tile_sizes, ...)
    return Stencil.StencilProducer(nil, Stencil.StencilProduceTiledND({ ... }, tile_sizes))
end

local function window_nd_producer(boundary, before, after)
    return Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND({ axis(1) }, {
        Stencil.StencilWindowAxis(before or 1, after or 1, boundary),
    }))
end

local artifacts = {
    Plan.store_n_artifact({
        tag = "arity0_const",
        result_ty = i32,
        inputs = {},
        expr = Plan.const_expr(iconst(7), i32),
        step_num = 1,
    }),
    Plan.store_n_artifact({
        tag = "arity1_neg",
        result_ty = i32,
        inputs = inputs(1),
        expr = Plan.point_unary_expr(Stencil.StencilUnaryNeg, input("x1"), i32, { int_semantics = sem }),
        step_num = 1,
    }),
    Plan.store_n_artifact({
        tag = "arity2_add",
        result_ty = i32,
        inputs = inputs(2),
        expr = Plan.point_binary_expr(Stencil.StencilBinaryAdd, input("x1"), input("x2"), i32, { int_semantics = sem }),
        step_num = 1,
    }),
    Plan.store_n_artifact({
        tag = "arity3_select",
        result_ty = i32,
        inputs = inputs(3),
        expr = Plan.point_select_expr(Stencil.StencilPredNonZero, input("x1"), input("x2"), input("x3"), i32),
        step_num = 1,
    }),
    Plan.store_n_artifact({
        tag = "arity4_mix",
        result_ty = i32,
        inputs = inputs(4),
        expr = Plan.point_binary_expr(
            Stencil.StencilBinaryAdd,
            Plan.point_binary_expr(Stencil.StencilBinaryMul, input("x1"), input("x2"), i32, { int_semantics = sem }),
            Plan.point_binary_expr(Stencil.StencilBinarySub, input("x3"), input("x4"), i32, { int_semantics = sem }),
            i32,
            { int_semantics = sem }
        ),
        step_num = 1,
    }),
}

for i, artifact in ipairs(artifacts) do
    local shape = Plan.artifact_shape(artifact)
    assert(asdl.classof(shape) == Stencil.StencilArtifactStoreN, "artifact " .. tostring(i) .. " should be generic store_n")
    assert(#shape.inputs == i - 1, "artifact " .. tostring(i) .. " should have saturated arity " .. tostring(i - 1))
end

local nd_artifact = Plan.store_n_artifact({
    tag = "range_nd2_add",
    result_ty = i32,
    inputs = inputs(2),
    expr = Plan.point_binary_expr(Stencil.StencilBinaryAdd, input("x1"), input("x2"), i32, { int_semantics = sem }),
    producer = range_nd_producer(2, 3),
})

local nd_reduce_artifact = Plan.reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
    tag = "range_nd2_sum",
    result_ty = i32,
    item_ty = i32,
    inputs = inputs(2),
    expr = Plan.point_binary_expr(Stencil.StencilBinaryAdd, input("x1"), input("x2"), i32, { int_semantics = sem }),
    producer = range_nd_producer(2, 3),
})

local scan_artifact = Plan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
})

local exclusive_scan_artifact = Plan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    mode = Stencil.StencilScanExclusive,
    step_num = 1,
})

local nd_scan_artifact = Plan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    producer = range_nd_producer(2, 3),
    axis = Stencil.StencilAxisRef(2),
})

local nd_axis_reduce_artifact = Plan.reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
    tag = "range_nd2_axis2_sum",
    result_ty = i32,
    item_ty = i32,
    inputs = inputs(1),
    expr = input("x1"),
    producer = range_nd_producer(2, 3),
    scope = Stencil.StencilReduceScopeAxes({ Stencil.StencilAxisRef(2) }, Stencil.StencilAccessRef("dst")),
})

local nd_step_artifact = Plan.store_n_artifact({
    tag = "range_nd2_step_add",
    result_ty = i32,
    inputs = inputs(2),
    expr = Plan.point_binary_expr(Stencil.StencilBinaryAdd, input("x1"), input("x2"), i32, { int_semantics = sem }),
    producer = range_nd_axes(axis(2), axis(2)),
})

local nd_find_artifact = Plan.find_array_artifact(Stencil.StencilPredCompareConst(Core.CmpGt, i32, iconst(4)), {
    elem_ty = i32,
    not_found = iconst(-1),
    producer = range_nd_producer(2, 3),
})

local nd_scatter_reduce_artifact = Plan.scatter_reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
    tag = "range_nd2_scatter_sum",
    result_ty = i32,
    item_ty = i32,
    index_ty = i32,
    inputs = inputs(1),
    expr = input("x1"),
    producer = range_nd_producer(2, 3),
})

local tiled_artifact = Plan.store_n_artifact({
    tag = "tiled_nd2_add",
    result_ty = i32,
    inputs = inputs(2),
    expr = Plan.point_binary_expr(Stencil.StencilBinaryAdd, input("x1"), input("x2"), i32, { int_semantics = sem }),
    producer = tiled_nd_producer({ 2, 2 }, axis(1), axis(1)),
})

local tiled_reduce_artifact = Plan.reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
    tag = "tiled_nd2_sum",
    result_ty = i32,
    item_ty = i32,
    inputs = inputs(1),
    expr = input("x1"),
    producer = tiled_nd_producer({ 2, 2 }, axis(1), axis(1)),
})

local tiled_scan_artifact = Plan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    producer = tiled_nd_producer({ 2, 2 }, axis(1), axis(1)),
    axis = Stencil.StencilAxisRef(2),
})

local window_artifacts = {
    Plan.store_n_artifact({
        tag = "window_reject_center",
        result_ty = i32,
        inputs = inputs(1),
        expr = input("x1"),
        producer = window_nd_producer(Stencil.StencilWindowBoundaryReject, 0, 0),
    }),
    Plan.store_n_artifact({
        tag = "window_clamp_center",
        result_ty = i32,
        inputs = inputs(1),
        expr = input("x1"),
        producer = window_nd_producer(Stencil.StencilWindowBoundaryClamp, 1, 1),
    }),
    Plan.store_n_artifact({
        tag = "window_wrap_center",
        result_ty = i32,
        inputs = inputs(1),
        expr = input("x1"),
        producer = window_nd_producer(Stencil.StencilWindowBoundaryWrap, 2, 0),
    }),
    Plan.store_n_artifact({
        tag = "window_zero_center",
        result_ty = i32,
        inputs = inputs(1),
        expr = input("x1"),
        producer = window_nd_producer(Stencil.StencilWindowBoundaryZero, 0, 2),
    }),
}

local window_neighbor_artifacts = {
    Plan.store_n_artifact({
        tag = "window_neighbor_clamp",
        result_ty = i32,
        inputs = inputs(1),
        expr = Stencil.StencilPointWindowInput(Stencil.StencilAccessRef("x1"), {
            Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), -1),
        }),
        producer = window_nd_producer(Stencil.StencilWindowBoundaryClamp, 1, 1),
    }),
    Plan.store_n_artifact({
        tag = "window_neighbor_wrap",
        result_ty = i32,
        inputs = inputs(1),
        expr = Stencil.StencilPointWindowInput(Stencil.StencilAccessRef("x1"), {
            Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), -1),
        }),
        producer = window_nd_producer(Stencil.StencilWindowBoundaryWrap, 1, 1),
    }),
    Plan.store_n_artifact({
        tag = "window_neighbor_zero",
        result_ty = i32,
        inputs = inputs(1),
        expr = Stencil.StencilPointWindowInput(Stencil.StencilAccessRef("x1"), {
            Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), -1),
        }),
        producer = window_nd_producer(Stencil.StencilWindowBoundaryZero, 1, 1),
    }),
}

local window_reduce_artifact = Plan.reduce_n_artifact(reduction(Value.ReductionAdd, 0), nil, {
    tag = "window_sum_clamp",
    result_ty = i32,
    item_ty = i32,
    inputs = inputs(1),
    expr = input("x1"),
    producer = window_nd_producer(Stencil.StencilWindowBoundaryClamp, 1, 1),
    scope = Stencil.StencilReduceScopeWindow({ Stencil.StencilAxisRef(1) }, Stencil.StencilAccessRef("dst")),
})

do
    local shape = Plan.artifact_shape(nd_artifact)
    assert(asdl.classof(shape.producer) == Stencil.StencilProducerExecRangeND, "RangeND StoreN should carry a producer execution plan")
    assert(shape.producer.rank == 2, "RangeND StoreN should preserve rank")
    local reduce_shape = Plan.artifact_shape(nd_reduce_artifact)
    assert(asdl.classof(reduce_shape.producer) == Stencil.StencilProducerExecRangeND, "RangeND ReduceN should carry a producer execution plan")
    assert(reduce_shape.producer.rank == 2, "RangeND ReduceN should preserve rank")
    assert(asdl.classof(Plan.artifact_shape(scan_artifact)) == Stencil.StencilArtifactScanN, "scan should lower through ScanN")
    assert(asdl.classof(Plan.artifact_shape(nd_scan_artifact).producer) == Stencil.StencilProducerExecRangeND, "RangeND ScanN should carry a producer execution plan")
    assert(Plan.artifact_shape(nd_scan_artifact).axis.index == 2, "RangeND ScanN should preserve scan axis")
    assert(asdl.classof(Plan.artifact_shape(nd_axis_reduce_artifact).reduce_scope) == Stencil.StencilReduceExecAxes, "RangeND axis reduce should preserve reduce scope")
    assert(asdl.classof(Plan.artifact_shape(nd_step_artifact).producer) == Stencil.StencilProducerExecRangeND, "non-unit RangeND should carry a producer execution plan")
    assert(asdl.classof(Plan.artifact_shape(nd_find_artifact).producer) == Stencil.StencilProducerExecRangeND, "RangeND FindN should carry a producer execution plan")
    assert(asdl.classof(Plan.artifact_shape(nd_scatter_reduce_artifact).producer) == Stencil.StencilProducerExecRangeND, "RangeND ScatterReduceN should carry a producer execution plan")
    assert(asdl.classof(Plan.artifact_shape(tiled_artifact).producer) == Stencil.StencilProducerExecTiledND, "TiledND StoreN should carry a producer execution plan")
    assert(asdl.classof(Plan.artifact_shape(tiled_reduce_artifact).producer) == Stencil.StencilProducerExecTiledND, "TiledND ReduceN should carry a producer execution plan")
    assert(asdl.classof(Plan.artifact_shape(tiled_scan_artifact).producer) == Stencil.StencilProducerExecTiledND, "TiledND ScanN should carry a producer execution plan")
    for _, artifact in ipairs(window_artifacts) do
        assert(asdl.classof(Plan.artifact_shape(artifact).producer) == Stencil.StencilProducerExecWindowND, "WindowND StoreN should carry a producer execution plan")
    end
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

local mc, mc_err, mc_src = MC.compile(T, artifacts, { stem = "test_stencil_store_n" })
assert(mc ~= nil, tostring(mc_err) .. "\n" .. tostring(mc_src))
exercise(mc.symbols, "mc")

local producer_artifacts = { nd_artifact, nd_reduce_artifact, nd_scan_artifact, nd_axis_reduce_artifact, nd_step_artifact, nd_find_artifact, nd_scatter_reduce_artifact, tiled_artifact, tiled_reduce_artifact, tiled_scan_artifact }
for _, artifact in ipairs(window_artifacts) do producer_artifacts[#producer_artifacts + 1] = artifact end
for _, artifact in ipairs(window_neighbor_artifacts) do producer_artifacts[#producer_artifacts + 1] = artifact end
producer_artifacts[#producer_artifacts + 1] = window_reduce_artifact

local mc_nd, mc_nd_err, mc_nd_src = MC.compile(T, producer_artifacts, { stem = "test_stencil_store_n_producers" })
assert(mc_nd ~= nil, tostring(mc_nd_err) .. "\n" .. tostring(mc_nd_src))
do
    local out = ffi.new("int32_t[6]")
    local x1 = ffi.new("int32_t[6]", { 1, 2, 3, 4, 5, 6 })
    local x2 = ffi.new("int32_t[6]", { 10, 20, 30, 40, 50, 60 })
    assert(mc_nd.symbols[nd_artifact.symbol.text], "mc missing RangeND StoreN")(out, x1, x2, 0, 2, 0, 3)
    for i = 0, 5 do
        assert(out[i] == x1[i] + x2[i], "RangeND StoreN row-major element " .. tostring(i))
    end
    local sum = assert(mc_nd.symbols[nd_reduce_artifact.symbol.text], "mc missing RangeND ReduceN")(x1, x2, 0, 2, 0, 3, 0)
    assert(sum == 231, "RangeND ReduceN row-major sum")
    assert(mc_nd.symbols[nd_scan_artifact.symbol.text], "mc missing RangeND axis ScanN")(out, x1, 0, 2, 0, 3, 0)
    assert(out[0] == 1 and out[1] == 3 and out[2] == 6 and out[3] == 4 and out[4] == 9 and out[5] == 15, "RangeND axis-2 ScanN row prefixes")
    local reduced = ffi.new("int32_t[2]")
    assert(mc_nd.symbols[nd_axis_reduce_artifact.symbol.text], "mc missing RangeND axis ReduceN")(reduced, x1, 0, 2, 0, 3)
    assert(reduced[0] == 6 and reduced[1] == 15, "RangeND axis-2 ReduceN row sums")
    assert(mc_nd.symbols[nd_step_artifact.symbol.text], "mc missing stepped RangeND StoreN")(out, x1, x2, 0, 4, 0, 6)
    for i = 0, 5 do
        assert(out[i] == x1[i] + x2[i], "stepped RangeND compact row-major element " .. tostring(i))
    end
    local found = assert(mc_nd.symbols[nd_find_artifact.symbol.text], "mc missing RangeND FindN")(x1, 0, 2, 0, 3)
    assert(found == 4, "RangeND FindN returns compact row-major index")
    local bins = ffi.new("int32_t[2]", { 0, 0 })
    local idx = ffi.new("int32_t[6]", { 0, 1, 0, 1, 0, 1 })
    assert(mc_nd.symbols[nd_scatter_reduce_artifact.symbol.text], "mc missing RangeND ScatterReduceN")(bins, x1, idx, 0, 2, 0, 3)
    assert(bins[0] == 9 and bins[1] == 12, "RangeND ScatterReduceN indexed sums")

    assert(mc_nd.symbols[tiled_artifact.symbol.text], "mc missing TiledND StoreN")(out, x1, x2, 0, 2, 0, 3)
    for i = 0, 5 do
        assert(out[i] == x1[i] + x2[i], "TiledND StoreN element " .. tostring(i))
    end
    sum = assert(mc_nd.symbols[tiled_reduce_artifact.symbol.text], "mc missing TiledND ReduceN")(x1, 0, 2, 0, 3, 0)
    assert(sum == 21, "TiledND ReduceN sum")
    assert(mc_nd.symbols[tiled_scan_artifact.symbol.text], "mc missing TiledND axis ScanN")(out, x1, 0, 2, 0, 3, 0)
    assert(out[0] == 1 and out[1] == 3 and out[2] == 6 and out[3] == 4 and out[4] == 9 and out[5] == 15, "TiledND axis-2 ScanN row prefixes")

    for _, artifact in ipairs(window_artifacts) do
        assert(mc_nd.symbols[artifact.symbol.text], "mc missing WindowND StoreN")(out, x1, 0, 6)
        for i = 0, 5 do
            assert(out[i] == x1[i], "WindowND center iteration element " .. tostring(i))
        end
    end
    assert(mc_nd.symbols[window_neighbor_artifacts[1].symbol.text], "mc missing WindowND clamp neighbor")(out, x1, 0, 6)
    assert(out[0] == 1 and out[1] == 1 and out[2] == 2 and out[3] == 3 and out[4] == 4 and out[5] == 5, "WindowND clamp neighbor")
    assert(mc_nd.symbols[window_neighbor_artifacts[2].symbol.text], "mc missing WindowND wrap neighbor")(out, x1, 0, 6)
    assert(out[0] == 6 and out[1] == 1 and out[2] == 2 and out[3] == 3 and out[4] == 4 and out[5] == 5, "WindowND wrap neighbor")
    assert(mc_nd.symbols[window_neighbor_artifacts[3].symbol.text], "mc missing WindowND zero neighbor")(out, x1, 0, 6)
    assert(out[0] == 0 and out[1] == 1 and out[2] == 2 and out[3] == 3 and out[4] == 4 and out[5] == 5, "WindowND zero neighbor")
    assert(mc_nd.symbols[window_reduce_artifact.symbol.text], "mc missing WindowND local ReduceN")(out, x1, 0, 6)
    assert(out[0] == 4 and out[1] == 6 and out[2] == 9 and out[3] == 12 and out[4] == 15 and out[5] == 17, "WindowND local clamp sum")
end

local bc_nd = assert(ResidualLuaTrace.realize_artifacts({
    nd_artifact,
    nd_reduce_artifact,
    nd_scan_artifact,
    nd_axis_reduce_artifact,
    nd_step_artifact,
    nd_find_artifact,
    nd_scatter_reduce_artifact,
}, { stem = "test_stencil_store_n_range_nd_bc" }))
do
    local out = ffi.new("int32_t[6]")
    local x1 = ffi.new("int32_t[6]", { 1, 2, 3, 4, 5, 6 })
    local x2 = ffi.new("int32_t[6]", { 10, 20, 30, 40, 50, 60 })
    assert(bc_nd.symbols[nd_artifact.symbol.text], "bc missing RangeND StoreN")(out, x1, x2, 0, 2, 0, 3)
    for i = 0, 5 do
        assert(out[i] == x1[i] + x2[i], "BC RangeND StoreN row-major element " .. tostring(i))
    end
    local sum = assert(bc_nd.symbols[nd_reduce_artifact.symbol.text], "bc missing RangeND ReduceN")(x1, x2, 0, 2, 0, 3, 0)
    assert(sum == 231, "BC RangeND ReduceN row-major sum")
    assert(bc_nd.symbols[nd_scan_artifact.symbol.text], "bc missing RangeND axis ScanN")(out, x1, 0, 2, 0, 3, 0)
    assert(out[0] == 1 and out[1] == 3 and out[2] == 6 and out[3] == 4 and out[4] == 9 and out[5] == 15, "BC RangeND axis-2 ScanN row prefixes")
    local reduced = ffi.new("int32_t[2]")
    assert(bc_nd.symbols[nd_axis_reduce_artifact.symbol.text], "bc missing RangeND axis ReduceN")(reduced, x1, 0, 2, 0, 3)
    assert(reduced[0] == 6 and reduced[1] == 15, "BC RangeND axis-2 ReduceN row sums")
    assert(bc_nd.symbols[nd_step_artifact.symbol.text], "bc missing stepped RangeND StoreN")(out, x1, x2, 0, 4, 0, 6)
    for i = 0, 5 do
        assert(out[i] == x1[i] + x2[i], "BC stepped RangeND compact row-major element " .. tostring(i))
    end
    local found = assert(bc_nd.symbols[nd_find_artifact.symbol.text], "bc missing RangeND FindN")(x1, 0, 2, 0, 3)
    assert(found == 4, "BC RangeND FindN returns compact row-major index")
    local bins = ffi.new("int32_t[2]", { 0, 0 })
    local idx = ffi.new("int32_t[6]", { 0, 1, 0, 1, 0, 1 })
    assert(bc_nd.symbols[nd_scatter_reduce_artifact.symbol.text], "bc missing RangeND ScatterReduceN")(bins, x1, idx, 0, 2, 0, 3)
    assert(bins[0] == 9 and bins[1] == 12, "BC RangeND ScatterReduceN indexed sums")
end
local bc_tiled_ok, bc_tiled_err = pcall(function()
    ResidualLuaTrace.realize_artifacts({ tiled_artifact }, { stem = "test_stencil_store_n_tiled_bc" })
end)
assert(not bc_tiled_ok and tostring(bc_tiled_err):find("tiled_nd", 1, true) ~= nil, "LuaTrace should still reject TiledND producers until its producer loop exists")
local bc_window_ok, bc_window_err = pcall(function()
    ResidualLuaTrace.realize_artifacts({ window_neighbor_artifacts[1], window_reduce_artifact }, { stem = "test_stencil_store_n_window_bc" })
end)
assert(not bc_window_ok and tostring(bc_window_err):find("window_nd", 1, true) ~= nil, "LuaTrace should reject WindowND window-relative consumers with a producer-shaped error")

local bc = assert(ResidualLuaTrace.realize_artifacts(artifacts, { stem = "test_stencil_store_n_bc" }))
exercise(bc.symbols, "bc")

local scan_build, scan_err, scan_src = MC.compile(T, { scan_artifact, exclusive_scan_artifact }, { stem = "test_stencil_scan_n" })
assert(scan_build ~= nil, tostring(scan_err) .. "\n" .. tostring(scan_src))
local scan_bc = assert(ResidualLuaTrace.realize_artifacts({ scan_artifact, exclusive_scan_artifact }, { stem = "test_stencil_scan_n_bc" }))
do
    local function exercise_scan(symbols, label)
        local out = ffi.new("int32_t[5]")
        local xs = ffi.new("int32_t[5]", { 1, 2, 3, 4, 5 })
        local final = assert(symbols[scan_artifact.symbol.text], label .. " missing ScanN inclusive")(out, xs, 0, 5, 0)
        assert(final == 15, label .. " ScanN inclusive final")
        assert(out[0] == 1 and out[1] == 3 and out[2] == 6 and out[3] == 10 and out[4] == 15, label .. " ScanN inclusive")
        final = assert(symbols[exclusive_scan_artifact.symbol.text], label .. " missing ScanN exclusive")(out, xs, 0, 5, 0)
        assert(final == 15, label .. " ScanN exclusive final")
        assert(out[0] == 0 and out[1] == 1 and out[2] == 3 and out[3] == 6 and out[4] == 10, label .. " ScanN exclusive")
    end
    exercise_scan(scan_build.symbols, "mc")
    exercise_scan(scan_bc.symbols, "bc")
end

do
    local function unary_artifact(tag, op)
        return Plan.store_n_artifact({
            tag = "bc_unary_" .. tag,
            result_ty = i32,
            inputs = inputs(1),
            expr = Plan.point_unary_expr(op, input("x1"), i32, { int_semantics = sem }),
            step_num = 1,
        })
    end

    local cases = {
        { "identity", Stencil.StencilUnaryIdentity, function(a) return a end },
        { "neg", Stencil.StencilUnaryNeg, function(a) return bit.tobit(-a) end },
        { "bitnot", Stencil.StencilUnaryBitNot, function(a) return bit.bnot(a) end },
        { "boolnot", Stencil.StencilUnaryBoolNot, function(a) return a == 0 and 1 or 0 end },
    }
    local unary_artifacts = {}
    for _, case in ipairs(cases) do unary_artifacts[#unary_artifacts + 1] = unary_artifact(case[1], case[2]) end

    local bc_unary = assert(ResidualLuaTrace.realize_artifacts(unary_artifacts, { stem = "test_stencil_store_n_unary_bc" }))
    local out = ffi.new("int32_t[5]")
    local x1 = ffi.new("int32_t[5]", { 8, 0, -16, 31, -42 })
    for i, case in ipairs(cases) do
        local fn = assert(bc_unary.symbols[unary_artifacts[i].symbol.text], "bc missing unary op " .. case[1])
        fn(out, x1, 0, 5)
        for j = 0, 4 do
            assert(out[j] == case[3](x1[j]), "BC unary " .. case[1] .. " mismatch at " .. tostring(j))
        end
    end
end

do
    local function binary_artifact(tag, op)
        return Plan.store_n_artifact({
            tag = "bc_binary_" .. tag,
            result_ty = i32,
            inputs = inputs(2),
            expr = Plan.point_binary_expr(op, input("x1"), input("x2"), i32, { int_semantics = sem }),
            step_num = 1,
        })
    end

    local cases = {
        { "add", Stencil.StencilBinaryAdd, function(a, b) return bit.tobit(a + b) end },
        { "sub", Stencil.StencilBinarySub, function(a, b) return bit.tobit(a - b) end },
        { "mul", Stencil.StencilBinaryMul, function(a, b) return bit.tobit(a * b) end },
        { "div", Stencil.StencilBinaryDiv, function(a, b) return math.floor(a / b) end },
        { "mod", Stencil.StencilBinaryMod, function(a, b) return a % b end },
        { "and", Stencil.StencilBinaryAnd, function(a, b) return bit.band(a, b) end },
        { "or", Stencil.StencilBinaryOr, function(a, b) return bit.bor(a, b) end },
        { "xor", Stencil.StencilBinaryXor, function(a, b) return bit.bxor(a, b) end },
        { "shl", Stencil.StencilBinaryShl, function(a, b) return bit.tobit(bit.lshift(a, bit.band(b, 31))) end },
        { "lshr", Stencil.StencilBinaryLShr, function(a, b) return bit.tobit(bit.rshift(a, bit.band(b, 31))) end },
        { "ashr", Stencil.StencilBinaryAShr, function(a, b) return bit.tobit(bit.arshift(a, bit.band(b, 31))) end },
        { "min", Stencil.StencilBinaryMin, function(a, b) return a < b and a or b end },
        { "max", Stencil.StencilBinaryMax, function(a, b) return a > b and a or b end },
    }
    local binary_artifacts = {}
    for _, case in ipairs(cases) do binary_artifacts[#binary_artifacts + 1] = binary_artifact(case[1], case[2]) end

    local bc_binary = assert(ResidualLuaTrace.realize_artifacts(binary_artifacts, { stem = "test_stencil_store_n_binary_bc" }))
    local out = ffi.new("int32_t[5]")
    local x1 = ffi.new("int32_t[5]", { 8, 9, 16, 31, 42 })
    local x2 = ffi.new("int32_t[5]", { 2, 3, 4, 5, 6 })
    for i, case in ipairs(cases) do
        local fn = assert(bc_binary.symbols[binary_artifacts[i].symbol.text], "bc missing binary op " .. case[1])
        fn(out, x1, x2, 0, 5)
        for j = 0, 4 do
            assert(out[j] == case[3](x1[j], x2[j]), "BC binary " .. case[1] .. " mismatch at " .. tostring(j))
        end
    end
end

do
    local function reduce_artifact(tag, kind, init)
        local red = reduction(kind, init)
        return Plan.reduce_n_artifact(red, nil, {
            tag = "bc_reduce_" .. tag,
            result_ty = i32,
            item_ty = i32,
            inputs = inputs(1),
            expr = input("x1"),
            step_num = 1,
        }), red
    end

    local function fold(init, xs, f)
        local acc = init
        for i = 0, 4 do acc = f(acc, xs[i]) end
        return acc
    end

    local cases = {
        { "add", Value.ReductionAdd, 0, function(init, xs) return fold(init, xs, function(a, b) return bit.tobit(a + b) end) end },
        { "mul", Value.ReductionMul, 1, function(init, xs) return fold(init, xs, function(a, b) return bit.tobit(a * b) end) end },
        { "and", Value.ReductionAnd, -1, function(init, xs) return fold(init, xs, function(a, b) return bit.band(a, b) end) end },
        { "or", Value.ReductionOr, 0, function(init, xs) return fold(init, xs, function(a, b) return bit.bor(a, b) end) end },
        { "xor", Value.ReductionXor, 0, function(init, xs) return fold(init, xs, function(a, b) return bit.bxor(a, b) end) end },
        { "min", Value.ReductionMin, 100, function(init, xs) return fold(init, xs, function(a, b) return a < b and a or b end) end },
        { "max", Value.ReductionMax, -100, function(init, xs) return fold(init, xs, function(a, b) return a > b and a or b end) end },
    }
    local reduce_artifacts = {}
    for _, case in ipairs(cases) do
        reduce_artifacts[#reduce_artifacts + 1] = reduce_artifact(case[1], case[2], case[3])
    end

    local bc_reduce = assert(ResidualLuaTrace.realize_artifacts(reduce_artifacts, { stem = "test_stencil_store_n_reduce_bc" }))
    local x1 = ffi.new("int32_t[5]", { 1, 2, 3, 4, 5 })
    for i, case in ipairs(cases) do
        local fn = assert(bc_reduce.symbols[reduce_artifacts[i].symbol.text], "bc missing reduction " .. case[1])
        local got = fn(x1, 0, 5, case[3])
        assert(got == case[4](case[3], x1), "BC reduction " .. case[1] .. " mismatch")
    end
end

io.write("stencil store_n ok\n")
