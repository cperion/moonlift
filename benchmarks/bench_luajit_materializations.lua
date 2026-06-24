-- Compare LuaTrace and copy-patch materialization across the stencil family.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Measure = require("moonlift.luajit_measure")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Flow = T.MoonFlow
local Schedule = T.MoonSchedule
local Stencil = T.MoonStencil
local Ty = T.MoonType
local Value = T.MoonValue
local StencilArtifactPlan = require("moonlift.stencil_artifact_plan")(T)
local StencilBank = require("moonlift.stencil_bank")(T)
local StencilLuaJIT = require("moonlift.stencil_luajit")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("MOONLIFT_LJ_MAT_BENCH_N") or (full and "2000000" or "200000"))
local samples = tonumber(os.getenv("MOONLIFT_LJ_MAT_BENCH_SAMPLES") or (full and "7" or "4"))
local rounds = tonumber(os.getenv("MOONLIFT_LJ_MAT_BENCH_ROUNDS") or (full and "3" or "1"))
local warmup = tonumber(os.getenv("MOONLIFT_LJ_MAT_BENCH_WARMUP") or (full and "3" or "2"))
local materialize_samples = tonumber(os.getenv("MOONLIFT_LJ_MAT_BUILD_SAMPLES") or (full and "5" or "3"))
local cc = os.getenv("MOONLIFT_LJ_MAT_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("MOONLIFT_LJ_MAT_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local debug_log = os.getenv("MOONLIFT_LJ_MAT_DEBUG") == "1"

local function debugf(msg)
    if debug_log then
        io.stderr:write(msg .. "\n")
        io.stderr:flush()
    end
end

local function stencil_object_cflags()
    return cflags .. " -fno-builtin -fno-builtin-memmove -fno-builtin-memcpy -fno-builtin-memset -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
end

local function stats_line(name, values)
    local s = Measure.stats(values)
    return string.format("%-34s median=%8.3fms min=%8.3fms avg=%8.3fms max=%8.3fms", name, s.median * 1000, s.min * 1000, s.avg * 1000, s.max * 1000)
end

local function measure_times(samples_n, fn)
    local out = {}
    for i = 1, samples_n do
        collectgarbage()
        local t0 = Measure.now()
        fn(i)
        out[i] = Measure.now() - t0
    end
    return out
end

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8
local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local pair_soa_ty = Code.CodeTyNamed("Demo", "PairSoA", Ty.TNamed(Ty.TypeRefGlobal("Demo", "PairSoA")))
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local ffi_preamble = "typedef struct { int32_t left; int32_t right; } Demo_Pair;"

pcall(ffi.cdef, ffi_preamble)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function u8const(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(u8, Core.LitInt(tostring(raw))))
end

local function fconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(f64, Core.LitFloat(tostring(raw))))
end

local function reduction(kind, init, ty)
    return {
        kind = kind,
        init = ty == f64 and fconst(init) or iconst(init),
        int_semantics = sem,
        float_mode = nil,
    }
end

local function reduction_fact(name, kind, init, ty)
    return Value.ReductionFact(
        Value.AlgebraFactId("reduction:bench:materialization:" .. name),
        Flow.FlowDomainFunction(Code.CodeFuncId("fn:" .. name)),
        Code.CodeValueId("v:acc:" .. name),
        kind,
        ty == f64 and fconst(init) or iconst(init),
        Value.ValueExprValue(Code.CodeValueId("v:item:" .. name)),
        ty,
        sem,
        nil,
        Value.AlgebraProofIdentity("materialization benchmark " .. name)
    )
end

local function vector_schedule(ty, lanes)
    return Schedule.ScheduleVector(Schedule.LaneVector(ty, lanes), 1, 1, Schedule.TailScalar)
end

local function merge(a, b)
    local out = {}
    for k, v in pairs(a or {}) do out[k] = v end
    for k, v in pairs(b or {}) do out[k] = v end
    return out
end

local function i32_info(extra)
    return merge({ elem_ty = i32, step_num = 1, schedule = vector_schedule(i32, 16) }, extra)
end

local function f64_info(extra)
    return merge({ elem_ty = f64, step_num = 1, schedule = vector_schedule(f64, 4) }, extra)
end

local function u8_info(extra)
    return merge({ elem_ty = u8, step_num = 1, schedule = vector_schedule(u8, 16) }, extra)
end

local function slice_topology(name)
    return Stencil.StencilTopologySliceDescriptor(
        Code.CodeValueId("v:slice:" .. name),
        Code.CodeValueId("v:data:" .. name),
        Code.CodeValueId("v:len:" .. name)
    )
end

local function bytespan_topology(name)
    return Stencil.StencilTopologyByteSpanDescriptor(
        Code.CodeValueId("v:bytespan:" .. name),
        Code.CodeValueId("v:data:" .. name),
        Code.CodeValueId("v:len:" .. name)
    )
end

local function view_topology(name, stride_const)
    return Stencil.StencilTopologyViewDescriptor(
        Code.CodeValueId("v:view:" .. name),
        Code.CodeValueId("v:data:" .. name),
        Code.CodeValueId("v:len:" .. name),
        Code.CodeValueId("v:stride:" .. name),
        stride_const
    )
end

local function field_topology()
    return Stencil.StencilTopologyFieldProjection(
        Stencil.StencilTopologyContiguous(1),
        pair_ty,
        "right",
        4
    )
end

local function soa_component(field_name, component_index)
    return Stencil.StencilTopologySoAComponent(
        Stencil.StencilTopologyContiguous(1),
        pair_soa_ty,
        field_name,
        component_index
    )
end

local cases = {}
local function add_case(name, artifact, run)
    cases[#cases + 1] = { name = name, artifact = artifact, run = run }
end

local reduce_i32 = reduction(Value.ReductionAdd, 0, i32)
local reduce_f64 = reduction(Value.ReductionAdd, 0, f64)

add_case("i32_reduce_add", StencilArtifactPlan.reduce_array_artifact(
    reduction_fact("i32_reduce_add", Value.ReductionAdd, 0, i32),
    nil,
    i32_info({ result_ty = i32 })
), function(fn, data) return fn(data.xs_i32, 0, data.n, 0) end)

add_case("i32_map_neg", StencilArtifactPlan.map_array_artifact(
    Stencil.StencilUnaryNeg,
    i32_info({ result_ty = i32 })
), function(fn, data) fn(data.out_i32, data.xs_i32, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("i32_zip_map_add", StencilArtifactPlan.zip_map_array_artifact(
    Stencil.StencilBinaryAdd,
    i32_info({ lhs_ty = i32, rhs_ty = i32, result_ty = i32 })
), function(fn, data) fn(data.out_i32, data.xs_i32, data.ys_i32, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("i32_scan_add", StencilArtifactPlan.scan_array_artifact(
    reduce_i32,
    nil,
    i32_info({ result_ty = i32 })
), function(fn, data)
    local final = fn(data.out_i32, data.xs_i32, 0, data.n, 0)
    return bit.tobit(final + data:checksum_i32(data.out_i32))
end)

add_case("i32_copy", StencilArtifactPlan.copy_array_artifact(
    i32_info({})
), function(fn, data) fn(data.out_i32, data.xs_i32, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("i32_copy_memmove", StencilArtifactPlan.copy_array_artifact(
    i32_info({ semantics = Stencil.StencilCopyMemMove })
), function(fn, data) fn(data.out_i32, data.xs_i32, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("i32_fill", StencilArtifactPlan.fill_array_artifact(
    i32_info({ value = iconst(7) })
), function(fn, data) fn(data.out_i32, 0, data.n, 7); return data:checksum_i32(data.out_i32) end)

add_case("i32_find_miss", StencilArtifactPlan.find_array_artifact(
    Stencil.StencilPredEqConst(iconst(-2147483648)),
    i32_info({})
), function(fn, data) return fn(data.xs_i32, 0, data.n) end)

add_case("i32_partition", StencilArtifactPlan.partition_array_artifact(
    Stencil.StencilPredGtConst(iconst(0)),
    i32_info({})
), function(fn, data)
    local split = fn(data.out_i32, data.xs_i32, 0, data.n)
    return bit.tobit(split + data:checksum_i32(data.out_i32))
end)

add_case("i32_cast_to_f64", StencilArtifactPlan.cast_array_artifact(
    Core.MachineCastSToF,
    i32_info({ src_ty = i32, dst_ty = f64 })
), function(fn, data) fn(data.out_f64, data.xs_i32, 0, data.n); return data:checksum_f64(data.out_f64) end)

add_case("i32_compare_gt", StencilArtifactPlan.compare_array_artifact(
    Stencil.StencilPredGtConst(iconst(0)),
    i32_info({ result_ty = bool8 })
), function(fn, data) fn(data.mask, data.xs_i32, 0, data.n); return data:checksum_u8(data.mask) end)

add_case("i32_zip_compare_lt", StencilArtifactPlan.zip_compare_array_artifact(
    Core.CmpLt,
    i32_info({ lhs_ty = i32, rhs_ty = i32, result_ty = bool8 })
), function(fn, data) fn(data.mask, data.xs_i32, data.ys_i32, 0, data.n); return data:checksum_u8(data.mask) end)

add_case("i32_gather", StencilArtifactPlan.gather_array_artifact(
    i32_info({ index_ty = i32 })
), function(fn, data) fn(data.out_i32, data.xs_i32, data.idx, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("i32_scatter", StencilArtifactPlan.scatter_array_artifact(
    i32_info({ index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices })
), function(fn, data) fn(data.out_i32, data.xs_i32, data.idx, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("i32_in_place_neg_x2", StencilArtifactPlan.in_place_map_array_artifact(
    Stencil.StencilUnaryNeg,
    i32_info({})
), function(fn, data)
    fn(data.inplace_i32, 0, data.n)
    fn(data.inplace_i32, 0, data.n)
    return data:checksum_i32(data.inplace_i32)
end)

add_case("i32_count_gt", StencilArtifactPlan.count_array_artifact(
    Stencil.StencilPredGtConst(iconst(0)),
    i32_info({})
), function(fn, data) return fn(data.xs_i32, 0, data.n) end)

add_case("i32_map_reduce_neg_add", StencilArtifactPlan.map_reduce_array_artifact(
    Stencil.StencilUnaryNeg,
    reduce_i32,
    nil,
    i32_info({ mapped_ty = i32, result_ty = i32 })
), function(fn, data) return fn(data.xs_i32, 0, data.n, 0) end)

add_case("i32_zip_reduce_add", StencilArtifactPlan.zip_reduce_array_artifact(
    Stencil.StencilBinaryAdd,
    reduce_i32,
    nil,
    i32_info({ lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32 })
), function(fn, data) return fn(data.xs_i32, data.ys_i32, 0, data.n, 0) end)

add_case("f64_reduce_add", StencilArtifactPlan.reduce_array_artifact(
    reduction_fact("f64_reduce_add", Value.ReductionAdd, 0, f64),
    nil,
    f64_info({ result_ty = f64 })
), function(fn, data) return fn(data.xs_f64, 0, data.n, 0) end)

add_case("f64_map_neg", StencilArtifactPlan.map_array_artifact(
    Stencil.StencilUnaryNeg,
    f64_info({ result_ty = f64 })
), function(fn, data) fn(data.out_f64, data.xs_f64, 0, data.n); return data:checksum_f64(data.out_f64) end)

add_case("f64_zip_map_add", StencilArtifactPlan.zip_map_array_artifact(
    Stencil.StencilBinaryAdd,
    f64_info({ lhs_ty = f64, rhs_ty = f64, result_ty = f64 })
), function(fn, data) fn(data.out_f64, data.xs_f64, data.ys_f64, 0, data.n); return data:checksum_f64(data.out_f64) end)

add_case("u8_bytespan_copy", StencilArtifactPlan.copy_array_artifact(
    u8_info({ dst_topology = bytespan_topology("copy_dst"), src_topology = bytespan_topology("copy_src") })
), function(fn, data) fn(data.out_u8, data.xs_u8, 0, data.n); return data:checksum_u8(data.out_u8) end)

add_case("u8_bytespan_fill", StencilArtifactPlan.fill_array_artifact(
    u8_info({ value = u8const(127), dst_topology = bytespan_topology("fill_dst") })
), function(fn, data) fn(data.out_u8, 0, data.n, 127); return data:checksum_u8(data.out_u8) end)

add_case("u8_bytespan_compare_gt", StencilArtifactPlan.compare_array_artifact(
    Stencil.StencilPredGtConst(u8const(127)),
    u8_info({ result_ty = bool8, dst_topology = bytespan_topology("compare_dst"), src_topology = bytespan_topology("compare_xs") })
), function(fn, data) fn(data.mask, data.xs_u8, 0, data.n); return data:checksum_u8(data.mask) end)

add_case("u8_bytespan_count_gt", StencilArtifactPlan.count_array_artifact(
    Stencil.StencilPredGtConst(u8const(127)),
    u8_info({ array_topology = bytespan_topology("count_xs") })
), function(fn, data) return fn(data.xs_u8, 0, data.n) end)

add_case("i32_slice_reduce_add", StencilArtifactPlan.reduce_array_artifact(
    reduction_fact("i32_slice_reduce_add", Value.ReductionAdd, 0, i32),
    nil,
    i32_info({ result_ty = i32, array_topology = slice_topology("reduce_xs") })
), function(fn, data) return fn(data.xs_i32, 0, data.n, 0) end)

add_case("i32_slice_copy", StencilArtifactPlan.copy_array_artifact(
    i32_info({ dst_topology = slice_topology("copy_dst"), src_topology = slice_topology("copy_src") })
), function(fn, data) fn(data.out_i32, data.xs_i32, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("i32_view_stride_reduce", StencilArtifactPlan.reduce_array_artifact(
    reduction_fact("i32_view_stride_reduce", Value.ReductionAdd, 0, i32),
    nil,
    i32_info({ result_ty = i32, array_topology = view_topology("reduce_xs") })
), function(fn, data) return fn(data.xs_i32_strided, 0, data.n, 0, 2) end)

add_case("i32_view_stride_map", StencilArtifactPlan.map_array_artifact(
    Stencil.StencilUnaryNeg,
    i32_info({ result_ty = i32, dst_topology = view_topology("map_dst"), src_topology = view_topology("map_xs") })
), function(fn, data)
    fn(data.out_i32_strided, data.xs_i32_strided, 0, data.n, 2, 2)
    return data:checksum_i32_stride(data.out_i32_strided, 2)
end)

add_case("i32_view_const_stride_reduce", StencilArtifactPlan.reduce_array_artifact(
    reduction_fact("i32_view_const_stride_reduce", Value.ReductionAdd, 0, i32),
    nil,
    i32_info({ result_ty = i32, array_topology = view_topology("reduce_const_xs", 2) })
), function(fn, data) return fn(data.xs_i32_strided, 0, data.n, 0) end)

add_case("field_reduce_right", StencilArtifactPlan.reduce_array_artifact(
    reduction_fact("field_reduce_right", Value.ReductionAdd, 0, i32),
    nil,
    i32_info({ result_ty = i32, array_topology = field_topology() })
), function(fn, data) return fn(data.pairs, 0, data.n, 0) end)

add_case("field_map_neg_right", StencilArtifactPlan.map_array_artifact(
    Stencil.StencilUnaryNeg,
    i32_info({ result_ty = i32, src_topology = field_topology() })
), function(fn, data) fn(data.out_i32, data.pairs, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("field_compare_right_gt", StencilArtifactPlan.compare_array_artifact(
    Stencil.StencilPredGtConst(iconst(0)),
    i32_info({ result_ty = bool8, src_topology = field_topology() })
), function(fn, data) fn(data.mask, data.pairs, 0, data.n); return data:checksum_u8(data.mask) end)

add_case("soa_zip_map_add", StencilArtifactPlan.zip_map_array_artifact(
    Stencil.StencilBinaryAdd,
    i32_info({
        lhs_ty = i32,
        rhs_ty = i32,
        result_ty = i32,
        dst_topology = soa_component("sum", 2),
        lhs_topology = soa_component("left", 0),
        rhs_topology = soa_component("right", 1),
    })
), function(fn, data) fn(data.out_i32, data.soa_left, data.soa_right, 0, data.n); return data:checksum_i32(data.out_i32) end)

add_case("soa_zip_reduce_add", StencilArtifactPlan.zip_reduce_array_artifact(
    Stencil.StencilBinaryAdd,
    reduce_i32,
    nil,
    i32_info({
        lhs_ty = i32,
        rhs_ty = i32,
        mapped_ty = i32,
        result_ty = i32,
        lhs_topology = soa_component("left", 0),
        rhs_topology = soa_component("right", 1),
    })
), function(fn, data) return fn(data.soa_left, data.soa_right, 0, data.n, 0) end)

add_case("soa_zip_compare_lt", StencilArtifactPlan.zip_compare_array_artifact(
    Core.CmpLt,
    i32_info({
        lhs_ty = i32,
        rhs_ty = i32,
        result_ty = bool8,
        dst_topology = soa_component("lt", 2),
        lhs_topology = soa_component("left", 0),
        rhs_topology = soa_component("right", 1),
    })
), function(fn, data) fn(data.mask, data.soa_left, data.soa_right, 0, data.n); return data:checksum_u8(data.mask) end)

local artifacts = {}
local lua_artifacts = {}
for i = 1, #cases do
    artifacts[i] = cases[i].artifact
    lua_artifacts[i] = StencilLuaJIT.lua_trace_artifact(cases[i].artifact)
end

local function make_data(n_)
    local data = { n = n_ }
    data.xs_i32 = ffi.new("int32_t[?]", n_)
    data.ys_i32 = ffi.new("int32_t[?]", n_)
    data.out_i32 = ffi.new("int32_t[?]", n_)
    data.inplace_i32 = ffi.new("int32_t[?]", n_)
    data.idx = ffi.new("int32_t[?]", n_)
    data.mask = ffi.new("uint8_t[?]", n_)
    data.xs_u8 = ffi.new("uint8_t[?]", n_)
    data.out_u8 = ffi.new("uint8_t[?]", n_)
    data.xs_i32_strided = ffi.new("int32_t[?]", n_ * 2)
    data.out_i32_strided = ffi.new("int32_t[?]", n_ * 2)
    data.pairs = ffi.new("Demo_Pair[?]", n_)
    data.soa_left = ffi.new("int32_t[?]", n_)
    data.soa_right = ffi.new("int32_t[?]", n_)
    data.xs_f64 = ffi.new("double[?]", n_)
    data.ys_f64 = ffi.new("double[?]", n_)
    data.out_f64 = ffi.new("double[?]", n_)
    for i = 0, n_ - 1 do
        local x = ((i % 31) - 15) * 17 + (i % 5)
        local y = ((i % 17) - 8) * 11 - (i % 3)
        data.xs_i32[i] = bit.tobit(x)
        data.ys_i32[i] = bit.tobit(y)
        data.inplace_i32[i] = bit.tobit(x)
        data.idx[i] = n_ - 1 - i
        data.xs_u8[i] = (i * 37 + 11) % 256
        data.xs_i32_strided[i * 2] = bit.tobit(x)
        data.xs_i32_strided[i * 2 + 1] = -123456789
        data.out_i32_strided[i * 2] = 0
        data.out_i32_strided[i * 2 + 1] = -987654321
        data.pairs[i].left = bit.tobit(y)
        data.pairs[i].right = bit.tobit(x)
        data.soa_left[i] = bit.tobit(x)
        data.soa_right[i] = bit.tobit(y)
        data.xs_f64[i] = x * 0.25
        data.ys_f64[i] = y * 0.5
    end
    function data:checksum_i32(xs)
        return bit.tobit(xs[0] + xs[math.floor((self.n - 1) / 2)] + xs[self.n - 1])
    end
    function data:checksum_u8(xs)
        return tonumber(xs[0]) + tonumber(xs[math.floor((self.n - 1) / 2)]) + tonumber(xs[self.n - 1])
    end
    function data:checksum_i32_stride(xs, stride)
        return bit.tobit(xs[0] + xs[math.floor((self.n - 1) / 2) * stride] + xs[(self.n - 1) * stride])
    end
    function data:checksum_f64(xs)
        return tonumber(xs[0]) + tonumber(xs[math.floor((self.n - 1) / 2)]) + tonumber(xs[self.n - 1])
    end
    return data
end

os.execute("mkdir -p target/luajit_bench")

local lua_bc_build_times = {}
local lua_bc_realize_times = {}
local lua_bc_bank
local lua_bc_realization
for i = 1, materialize_samples do
    collectgarbage()
    debugf("luatrace bc build " .. tostring(i))
    local t0 = Measure.now()
    local bank, bank_err = StencilLuaJIT.build_bytecode_bank(lua_artifacts, {
        stem = "bench_luajit_materializations_bc_" .. tostring(i),
    })
    lua_bc_build_times[i] = Measure.now() - t0
    assert(bank ~= nil, tostring(bank_err))

    collectgarbage()
    debugf("luatrace bc realize " .. tostring(i))
    local t1 = Measure.now()
    local realization, realize_err = StencilLuaJIT.realize_bytecode_artifacts(lua_artifacts, { bank = bank })
    lua_bc_realize_times[i] = Measure.now() - t1
    assert(realization ~= nil, tostring(realize_err))
    lua_bc_bank = bank
    lua_bc_realization = realization
end

local bank_times = {}
local install_times = {}
local copy_realization
for i = 1, materialize_samples do
    collectgarbage()
    debugf("copy build " .. tostring(i))
    local t0 = Measure.now()
    local bank, bank_err = StencilBank.build_binary_bank(artifacts, {
        stem = "bench_luajit_materializations_matrix_" .. tostring(i),
        cc = cc,
        cflags = stencil_object_cflags(),
        preamble = ffi_preamble,
    })
    bank_times[i] = Measure.now() - t0
    assert(bank ~= nil, tostring(bank_err))

    collectgarbage()
    debugf("copy install " .. tostring(i))
    local t1 = Measure.now()
    local realization, realize_err = StencilBank.realize_binary_artifacts(artifacts, { bank = bank, preamble = ffi_preamble })
    install_times[i] = Measure.now() - t1
    assert(realization ~= nil, tostring(realize_err))
    copy_realization = realization
end

debugf("make data")
local data = make_data(n)

print(string.format(
    "MoonLuaJIT materialization matrix mode=%s n=%d artifacts=%d runtime_samples=%d rounds=%d warmup=%d materialize_samples=%d",
    mode,
    n,
    #cases,
    samples,
    rounds,
    warmup,
    materialize_samples
))
print("cc: " .. cc .. " " .. stencil_object_cflags())
print(stats_line("luatrace build bytecode bank all", lua_bc_build_times))
print(stats_line("luatrace load bytecode bank all", lua_bc_realize_times))
print(stats_line("copy-patch build bank all", bank_times))
print(stats_line("copy-patch install bank all", install_times))

local runtime_cases = {}
for _, case in ipairs(cases) do
    local symbol = case.artifact.symbol.text
    local lua_bc_fn = assert(lua_bc_realization.symbols[symbol], symbol)
    local copy_fn = assert(copy_realization.symbols[symbol], symbol)
    debugf("validate luatrace bc " .. case.name)
    local lua_bc_value = case.run(lua_bc_fn, data)
    debugf("validate copy-patch " .. case.name)
    local copy_value = case.run(copy_fn, data)
    if type(lua_bc_value) == "number" and type(copy_value) == "number" then
        assert(math.abs(lua_bc_value - copy_value) < 1e-6, case.name .. " bytecode result mismatch: " .. tostring(lua_bc_value) .. " vs " .. tostring(copy_value))
    else
        assert(lua_bc_value == copy_value, case.name .. " bytecode result mismatch: " .. tostring(lua_bc_value) .. " vs " .. tostring(copy_value))
    end
    runtime_cases[#runtime_cases + 1] = {
        name = "ltbc " .. case.name,
        fn = function() return case.run(lua_bc_fn, data) end,
    }
    runtime_cases[#runtime_cases + 1] = {
        name = "cp " .. case.name,
        fn = function() return case.run(copy_fn, data) end,
    }
end

local results = Measure.measure(runtime_cases, {
    samples = samples,
    rounds = rounds,
    warmup = warmup,
    jit_opts = { "hotloop=3", "hotexit=2" },
})

for i = 1, #results do print(Measure.format_result(results[i])) end
