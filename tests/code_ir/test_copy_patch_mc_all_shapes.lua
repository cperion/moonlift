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
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local StencilBinary = require("tests.code_ir.copy_patch_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8
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

local function reduce_unary_artifact(topology)
    return StencilArtifactPlan.reduce_n_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
        tag = "unary_neg",
        inputs = { { name = "xs", ty = i32, topology = topology } },
        expr = StencilArtifactPlan.apply_unary_expr(Stencil.StencilUnaryNeg, StencilArtifactPlan.input_expr("xs"), i32, { int_semantics = sem }),
        item_ty = i32,
        result_ty = i32,
        step_num = 1,
    })
end

local function reduce_binary_artifact(lhs_topology, rhs_topology)
    return StencilArtifactPlan.reduce_n_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
        tag = "binary_add",
        inputs = {
            { name = "lhs", ty = i32, topology = lhs_topology },
            { name = "rhs", ty = i32, topology = rhs_topology },
        },
        expr = StencilArtifactPlan.apply_binary_expr(Stencil.StencilBinaryAdd, StencilArtifactPlan.input_expr("lhs"), StencilArtifactPlan.input_expr("rhs"), i32, { int_semantics = sem }),
        item_ty = i32,
        result_ty = i32,
        step_num = 1,
    })
end

local noalias_gather = StencilArtifactPlan.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1, unroll = 3, noalias = true, alignment = 16 })
local partial_noalias_gather = StencilArtifactPlan.gather_array_artifact({
    elem_ty = i32,
    index_ty = i32,
    step_num = 1,
    unroll = 2,
    noalias_pairs = {
        { "dst", "idx" },
        { "src", "idx" },
    },
})

local function count_obligations(facts, kind_cls, origin)
    local n = 0
    for _, obligation in ipairs(facts.proof_obligations or {}) do
        if pvm.classof(obligation.kind) == kind_cls and (origin == nil or obligation.origin == origin) then n = n + 1 end
    end
    return n
end

local noalias_facts = noalias_gather.instance.schedule.facts
assert(count_obligations(noalias_facts, Stencil.StencilProofUnitStride, Stencil.StencilProofCheckerDerived) == 3, "gather should prove unit stride for all three streams")
assert(count_obligations(noalias_facts, Stencil.StencilProofAlignment, Stencil.StencilProofAuthorAsserted) == 3, "global alignment fact should create one author-asserted obligation per stream")
assert(count_obligations(noalias_facts, Stencil.StencilProofNoAlias, Stencil.StencilProofAuthorAsserted) == 3, "global noalias should create pairwise author-asserted obligations")

local partial_noalias_facts = partial_noalias_gather.instance.schedule.facts
assert(count_obligations(partial_noalias_facts, Stencil.StencilProofNoAlias, Stencil.StencilProofAuthorAsserted) == 2, "partial noalias should create only the requested pairwise obligations")

local function view_topology(name)
    return Stencil.StencilTopologyViewDescriptor(
        Code.CodeValueId("v:view:" .. name),
        Code.CodeValueId("v:data:" .. name),
        Code.CodeValueId("v:len:" .. name),
        Code.CodeValueId("v:stride:" .. name),
        nil
    )
end

local function slice_topology(name)
    return Stencil.StencilTopologySliceDescriptor(
        Code.CodeValueId("v:slice:" .. name),
        Code.CodeValueId("v:data:" .. name),
        Code.CodeValueId("v:len:" .. name)
    )
end

local artifacts = {
    StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    StencilArtifactPlan.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1 }),
    StencilArtifactPlan.find_array_artifact(pred(Core.CmpEq, i32, iconst(5)), { elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1 }),
    StencilArtifactPlan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1 }),
    StencilArtifactPlan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1 }),
    StencilArtifactPlan.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1 }),
    StencilArtifactPlan.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    StencilArtifactPlan.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1 }),
    StencilArtifactPlan.count_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1 }),
    reduce_unary_artifact(),
    reduce_binary_artifact(),
    StencilArtifactPlan.select_array_artifact(Stencil.StencilPredNonZero, { cond_ty = bool8, elem_ty = i32, result_ty = i32, step_num = 1 }),
    noalias_gather,
    partial_noalias_gather,
}

local view_artifacts = {
    StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, array_topology = view_topology("reduce_xs") }),
    StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, unroll = 2, array_topology = view_topology("reduce_unrolled_xs") }),
    StencilArtifactPlan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = view_topology("map_dst"), src_topology = view_topology("map_xs") }),
    StencilArtifactPlan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1, dst_topology = view_topology("zip_map_dst"), lhs_topology = view_topology("zip_map_lhs"), rhs_topology = view_topology("zip_map_rhs") }),
    StencilArtifactPlan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = view_topology("scan_dst"), array_topology = view_topology("scan_xs") }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, step_num = 1, dst_topology = view_topology("copy_dst"), src_topology = view_topology("copy_src") }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = view_topology("copy_move_dst"), src_topology = view_topology("copy_move_src") }),
    StencilArtifactPlan.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1, dst_topology = view_topology("fill_dst") }),
    StencilArtifactPlan.find_array_artifact(pred(Core.CmpEq, i32, iconst(5)), { elem_ty = i32, step_num = 1, array_topology = view_topology("find_xs") }),
    StencilArtifactPlan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1, dst_topology = view_topology("partition_dst"), array_topology = view_topology("partition_xs") }),
    StencilArtifactPlan.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1, dst_topology = view_topology("cast_dst"), src_topology = view_topology("cast_xs") }),
    StencilArtifactPlan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1, dst_topology = view_topology("compare_dst"), src_topology = view_topology("compare_xs") }),
    StencilArtifactPlan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1, dst_topology = view_topology("zip_compare_dst"), lhs_topology = view_topology("zip_compare_lhs"), rhs_topology = view_topology("zip_compare_rhs") }),
    StencilArtifactPlan.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1, dst_topology = view_topology("gather_dst"), index_topology = view_topology("gather_idx") }),
    StencilArtifactPlan.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, src_topology = view_topology("scatter_src"), index_topology = view_topology("scatter_idx") }),
    StencilArtifactPlan.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1, src_topology = view_topology("in_place_xs") }),
    StencilArtifactPlan.count_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1, array_topology = view_topology("count_xs") }),
    reduce_unary_artifact(view_topology("reduce_n_xs")),
    reduce_binary_artifact(view_topology("reduce_n_lhs"), view_topology("reduce_n_rhs")),
}

for _, artifact in ipairs(view_artifacts) do
    artifacts[#artifacts + 1] = artifact
end

local slice_artifacts = {
    StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, array_topology = slice_topology("reduce_xs") }),
    StencilArtifactPlan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = slice_topology("map_dst"), src_topology = slice_topology("map_xs") }),
    StencilArtifactPlan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1, dst_topology = slice_topology("zip_map_dst"), lhs_topology = slice_topology("zip_map_lhs"), rhs_topology = slice_topology("zip_map_rhs") }),
    StencilArtifactPlan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = slice_topology("scan_dst"), array_topology = slice_topology("scan_xs") }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, step_num = 1, dst_topology = slice_topology("copy_dst"), src_topology = slice_topology("copy_src") }),
    StencilArtifactPlan.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = slice_topology("copy_move_dst"), src_topology = slice_topology("copy_move_src") }),
    StencilArtifactPlan.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1, dst_topology = slice_topology("fill_dst") }),
    StencilArtifactPlan.find_array_artifact(pred(Core.CmpEq, i32, iconst(5)), { elem_ty = i32, step_num = 1, array_topology = slice_topology("find_xs") }),
    StencilArtifactPlan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1, dst_topology = slice_topology("partition_dst"), array_topology = slice_topology("partition_xs") }),
    StencilArtifactPlan.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1, dst_topology = slice_topology("cast_dst"), src_topology = slice_topology("cast_xs") }),
    StencilArtifactPlan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1, dst_topology = slice_topology("compare_dst"), src_topology = slice_topology("compare_xs") }),
    StencilArtifactPlan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1, dst_topology = slice_topology("zip_compare_dst"), lhs_topology = slice_topology("zip_compare_lhs"), rhs_topology = slice_topology("zip_compare_rhs") }),
    StencilArtifactPlan.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1, dst_topology = slice_topology("gather_dst"), index_topology = slice_topology("gather_idx") }),
    StencilArtifactPlan.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, src_topology = slice_topology("scatter_src"), index_topology = slice_topology("scatter_idx") }),
    StencilArtifactPlan.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1, src_topology = slice_topology("in_place_xs") }),
    StencilArtifactPlan.count_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1, array_topology = slice_topology("count_xs") }),
    reduce_unary_artifact(slice_topology("reduce_n_xs")),
    reduce_binary_artifact(slice_topology("reduce_n_lhs"), slice_topology("reduce_n_rhs")),
}

for _, artifact in ipairs(slice_artifacts) do
    artifacts[#artifacts + 1] = artifact
end

local build, err, src = StencilBinary.compile(T, artifacts, { stem = "test_copy_patch_mc_all_shapes" })
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))
local function bank_entry(artifact)
    for _, entry in ipairs(build.mc_bank.entries or {}) do
        if entry.symbol == artifact.symbol.text then return entry end
    end
    error("missing bank entry " .. artifact.symbol.text)
end
local default_reduce_entry = bank_entry(artifacts[1])
assert(pvm.classof(default_reduce_entry.artifact.realized) == Stencil.StencilRealizedScalar, "default MC autovector request should record scalar realization when no vector path materialized")
assert(pvm.classof(default_reduce_entry.artifact.schedule_rejects[1]) == Stencil.StencilScheduleRejectRequestedRealizedMismatch, "default MC autovector miss should record typed schedule mismatch")
local noalias_entry = bank_entry(noalias_gather)
assert(pvm.classof(noalias_entry.artifact.realized) == Stencil.StencilRealizedUnrolled, "unrolled MC gather should record unrolled realization")
assert(noalias_entry.artifact.realized.factor == 3, "unrolled MC gather should record realized factor")
assert(#noalias_entry.artifact.schedule_rejects == 0, "matching unrolled MC gather should not record schedule rejects")
assert(src:match("xs%[%(%(i %+ 1%) %* xs_stride%)%]"), "unrolled dynamic view access must parenthesize the lane index")
assert(src:match("ml_stencil_gather_array_i32_idx_i32_s1_u3%([^%)]*int32_t %*__restrict dst[^%)]*int32_t const %*__restrict src[^%)]*int32_t const %*__restrict idx"), "noalias gather facts must materialize restrict parameters")
assert(src:match("ml_stencil_gather_array_i32_idx_i32_s1_u2%([^%)]*int32_t %*dst[^%)]*int32_t const %*src[^%)]*int32_t const %*__restrict idx"), "partial noalias facts must restrict only fully disjoint parameters")
assert(not src:match("ml_stencil_gather_array_i32_idx_i32_s1_u2%([^%)]*__restrict dst"), "partial noalias must not mark dst restrict while dst/src may alias")
assert(not src:match("ml_stencil_gather_array_i32_idx_i32_s1_u2%([^%)]*__restrict src"), "partial noalias must not mark src restrict while dst/src may alias")
assert(src:match("dst = __builtin_assume_aligned%(dst, 16%)"), "known alignment facts must materialize alignment assumptions")

local xs = ffi.new("int32_t[5]", { 1, -2, 5, 0, 3 })
local ys = ffi.new("int32_t[5]", { 10, 20, 30, 40, 50 })
local out = ffi.new("int32_t[5]")
local mask = ffi.new("uint8_t[5]")
local dout = ffi.new("double[5]")
local idx = ffi.new("int32_t[5]", { 2, 0, 4, 1, 3 })

local function sym(artifact)
    return assert(build.symbols[artifact.symbol.text], artifact.symbol.text)
end

assert(sym(artifacts[1])(xs, 0, 5, 0) == 7, "reduce add")

sym(artifacts[2])(out, xs, 0, 5)
assert(out[0] == -1 and out[1] == 2 and out[2] == -5 and out[3] == 0 and out[4] == -3, "map neg")

sym(artifacts[3])(out, xs, ys, 0, 5)
assert(out[0] == 11 and out[1] == 18 and out[2] == 35 and out[3] == 40 and out[4] == 53, "zip add")

local final = sym(artifacts[4])(out, xs, 0, 5, 0)
assert(final == 7, "scan final")
assert(out[0] == 1 and out[1] == -1 and out[2] == 4 and out[3] == 4 and out[4] == 7, "scan prefix")

sym(artifacts[5])(out, xs, 0, 5)
assert(out[0] == 1 and out[1] == -2 and out[2] == 5 and out[3] == 0 and out[4] == 3, "copy")

local overlap = ffi.new("int32_t[6]", { 1, 2, 3, 4, 5, 6 })
sym(artifacts[6])(overlap + 1, overlap, 0, 5)
assert(overlap[0] == 1 and overlap[1] == 1 and overlap[2] == 2 and overlap[3] == 3 and overlap[4] == 4 and overlap[5] == 5, "copy memmove")

sym(artifacts[7])(out, 0, 5, 7)
assert(out[0] == 7 and out[1] == 7 and out[2] == 7 and out[3] == 7 and out[4] == 7, "fill")

assert(sym(artifacts[8])(xs, 0, 5) == 2, "find eq")

local split = sym(artifacts[9])(out, xs, 0, 5)
assert(split == 3, "partition split")
assert(out[0] == 1 and out[1] == 5 and out[2] == 3 and out[3] == -2 and out[4] == 0, "partition order")

sym(artifacts[10])(dout, xs, 0, 5)
assert(dout[0] == 1 and dout[1] == -2 and dout[2] == 5 and dout[3] == 0 and dout[4] == 3, "cast")

sym(artifacts[11])(mask, xs, 0, 5)
assert(mask[0] == 1 and mask[1] == 0 and mask[2] == 1 and mask[3] == 0 and mask[4] == 1, "compare")

sym(artifacts[12])(mask, xs, ys, 0, 5)
assert(mask[0] == 1 and mask[1] == 1 and mask[2] == 1 and mask[3] == 1 and mask[4] == 1, "zip compare")

sym(artifacts[13])(out, xs, idx, 0, 5)
assert(out[0] == 5 and out[1] == 1 and out[2] == 3 and out[3] == -2 and out[4] == 0, "gather")

for i = 0, 4 do out[i] = 0 end
sym(artifacts[14])(out, xs, idx, 0, 5)
assert(out[0] == -2 and out[1] == 0 and out[2] == 1 and out[3] == 3 and out[4] == 5, "scatter")

local inplace = ffi.new("int32_t[5]", { 1, -2, 5, 0, 3 })
sym(artifacts[15])(inplace, 0, 5)
assert(inplace[0] == -1 and inplace[1] == 2 and inplace[2] == -5 and inplace[3] == 0 and inplace[4] == -3, "in-place map")

assert(sym(artifacts[16])(xs, 0, 5) == 3, "count")
assert(sym(artifacts[17])(xs, 0, 5, 0) == -7, "map reduce")
assert(sym(artifacts[18])(xs, ys, 0, 5, 0) == 157, "zip reduce")
local select_mask = ffi.new("uint8_t[5]", { 1, 0, 1, 0, 1 })
sym(artifacts[19])(out, select_mask, xs, ys, 0, 5)
assert(out[0] == 1 and out[1] == 20 and out[2] == 5 and out[3] == 40 and out[4] == 3, "select")

io.write("lalin copy_patch_mc all shapes ok\n")
