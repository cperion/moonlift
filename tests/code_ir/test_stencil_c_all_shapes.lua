package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Value = T.MoonValue
local Stencil = T.MoonStencil
local StencilC = require("moonlift.stencil_c")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8
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
    StencilC.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilC.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilC.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1 }),
    StencilC.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1 }),
    StencilC.copy_array_artifact({ elem_ty = i32, step_num = 1 }),
    StencilC.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    StencilC.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1 }),
    StencilC.find_array_artifact(Stencil.StencilPredEqConst(iconst(5)), { elem_ty = i32, step_num = 1 }),
    StencilC.partition_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, step_num = 1 }),
    StencilC.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1 }),
    StencilC.compare_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1 }),
    StencilC.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1 }),
    StencilC.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1 }),
    StencilC.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    StencilC.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1 }),
    StencilC.count_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, step_num = 1 }),
    StencilC.map_reduce_array_artifact(Stencil.StencilUnaryNeg, reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1 }),
    StencilC.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1 }),
}

local view_artifacts = {
    StencilC.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, array_topology = view_topology("reduce_xs") }),
    StencilC.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = view_topology("map_dst"), src_topology = view_topology("map_xs") }),
    StencilC.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1, dst_topology = view_topology("zip_map_dst"), lhs_topology = view_topology("zip_map_lhs"), rhs_topology = view_topology("zip_map_rhs") }),
    StencilC.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = view_topology("scan_dst"), array_topology = view_topology("scan_xs") }),
    StencilC.copy_array_artifact({ elem_ty = i32, step_num = 1, dst_topology = view_topology("copy_dst"), src_topology = view_topology("copy_src") }),
    StencilC.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = view_topology("copy_move_dst"), src_topology = view_topology("copy_move_src") }),
    StencilC.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1, dst_topology = view_topology("fill_dst") }),
    StencilC.find_array_artifact(Stencil.StencilPredEqConst(iconst(5)), { elem_ty = i32, step_num = 1, array_topology = view_topology("find_xs") }),
    StencilC.partition_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, step_num = 1, dst_topology = view_topology("partition_dst"), array_topology = view_topology("partition_xs") }),
    StencilC.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1, dst_topology = view_topology("cast_dst"), src_topology = view_topology("cast_xs") }),
    StencilC.compare_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1, dst_topology = view_topology("compare_dst"), src_topology = view_topology("compare_xs") }),
    StencilC.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1, dst_topology = view_topology("zip_compare_dst"), lhs_topology = view_topology("zip_compare_lhs"), rhs_topology = view_topology("zip_compare_rhs") }),
    StencilC.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1, dst_topology = view_topology("gather_dst"), index_topology = view_topology("gather_idx") }),
    StencilC.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, src_topology = view_topology("scatter_src"), index_topology = view_topology("scatter_idx") }),
    StencilC.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1, src_topology = view_topology("in_place_xs") }),
    StencilC.count_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, step_num = 1, array_topology = view_topology("count_xs") }),
    StencilC.map_reduce_array_artifact(Stencil.StencilUnaryNeg, reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, array_topology = view_topology("map_reduce_xs") }),
    StencilC.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, lhs_topology = view_topology("zip_reduce_lhs"), rhs_topology = view_topology("zip_reduce_rhs") }),
}

for _, artifact in ipairs(view_artifacts) do
    artifacts[#artifacts + 1] = artifact
end

local slice_artifacts = {
    StencilC.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, array_topology = slice_topology("reduce_xs") }),
    StencilC.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = slice_topology("map_dst"), src_topology = slice_topology("map_xs") }),
    StencilC.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1, dst_topology = slice_topology("zip_map_dst"), lhs_topology = slice_topology("zip_map_lhs"), rhs_topology = slice_topology("zip_map_rhs") }),
    StencilC.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = slice_topology("scan_dst"), array_topology = slice_topology("scan_xs") }),
    StencilC.copy_array_artifact({ elem_ty = i32, step_num = 1, dst_topology = slice_topology("copy_dst"), src_topology = slice_topology("copy_src") }),
    StencilC.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = slice_topology("copy_move_dst"), src_topology = slice_topology("copy_move_src") }),
    StencilC.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1, dst_topology = slice_topology("fill_dst") }),
    StencilC.find_array_artifact(Stencil.StencilPredEqConst(iconst(5)), { elem_ty = i32, step_num = 1, array_topology = slice_topology("find_xs") }),
    StencilC.partition_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, step_num = 1, dst_topology = slice_topology("partition_dst"), array_topology = slice_topology("partition_xs") }),
    StencilC.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1, dst_topology = slice_topology("cast_dst"), src_topology = slice_topology("cast_xs") }),
    StencilC.compare_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1, dst_topology = slice_topology("compare_dst"), src_topology = slice_topology("compare_xs") }),
    StencilC.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1, dst_topology = slice_topology("zip_compare_dst"), lhs_topology = slice_topology("zip_compare_lhs"), rhs_topology = slice_topology("zip_compare_rhs") }),
    StencilC.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1, dst_topology = slice_topology("gather_dst"), index_topology = slice_topology("gather_idx") }),
    StencilC.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, src_topology = slice_topology("scatter_src"), index_topology = slice_topology("scatter_idx") }),
    StencilC.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1, src_topology = slice_topology("in_place_xs") }),
    StencilC.count_array_artifact(Stencil.StencilPredGtConst(iconst(0)), { elem_ty = i32, step_num = 1, array_topology = slice_topology("count_xs") }),
    StencilC.map_reduce_array_artifact(Stencil.StencilUnaryNeg, reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, array_topology = slice_topology("map_reduce_xs") }),
    StencilC.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, lhs_topology = slice_topology("zip_reduce_lhs"), rhs_topology = slice_topology("zip_reduce_rhs") }),
}

for _, artifact in ipairs(slice_artifacts) do
    artifacts[#artifacts + 1] = artifact
end

local build, err, src = StencilC.compile_artifacts(artifacts, { stem = "test_stencil_c_all_shapes" })
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))

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

io.write("moonlift stencil_c all shapes ok\n")
