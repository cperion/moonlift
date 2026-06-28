package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local lalin = require("lalin")
local Measure = require("lalin.luajit_measure")

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_SOURCE_SHAPE_N") or (full and "1000000" or "200000"))
local compile_samples = tonumber(os.getenv("LALIN_SOURCE_SHAPE_COMPILE_SAMPLES") or (full and "5" or "3"))
local runtime_samples = tonumber(os.getenv("LALIN_SOURCE_SHAPE_RUNTIME_SAMPLES") or (full and "7" or "4"))
local rounds = tonumber(os.getenv("LALIN_SOURCE_SHAPE_ROUNDS") or (full and "3" or "1"))
local cc = os.getenv("CC") or "gcc"
local gcc_cflags = os.getenv("LALIN_SOURCE_SHAPE_GCC_CFLAGS") or "-std=gnu99 -O3 -march=native"
local native_residual = os.getenv("LALIN_SOURCE_SHAPE_NATIVE_RESIDUAL") ~= "0"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function exec_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function stats_line(name, values)
    local s = Measure.stats(values)
    return string.format("%-34s median=%8.3fms min=%8.3fms avg=%8.3fms max=%8.3fms", name, s.median * 1000, s.min * 1000, s.avg * 1000, s.max * 1000)
end

local main_source = [=[
return unit. SourceShapeBench {
  fn. sum_i32 { xs [ptr [i32]], n [index] } [i32] {
    requires { bounds (xs)(n), readonly(xs) },

    lln.loop. i [lln.range { 0, n }] [lln.i32] {
      lln.fold. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = xs[i],
      },
    },
  },

  fn. zip_add_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    lln.loop. i [lln.range { 0, n }] {
      set (dst[i])(lhs[i] + rhs[i]),
    },
  },

  fn. fused_reduce_i32 { lhs [ptr [i32]], rhs [ptr [i32]], bias [ptr [i32]], n [index] } [i32] {
    requires {
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      bounds (bias)(n), readonly(bias),
    },

    lln.loop. i [lln.range { 0, n }] [lln.i32] {
      lln.fold. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = (lhs[i] * rhs[i]) + bias[i],
      },
    },
  },

  fn. scan_sum_i32 { dst [ptr [i32]], xs [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop. i [lln.range { 0, n }] {
      lln.scan. acc [lln.i32] {
        init = 0,
        by = lln.add,
        step = xs[i],
        into = dst[i],
      },
    },
  },

  fn. scatter_reduce_add_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    lln.loop. i [lln.range { 0, n }] {
      set (dst[idx[i]])(dst[idx[i]] + src[i]),
    },
  },
}
]=]

local nd_source = [=[
return unit. SourceShapeNDAffineBench {
  fn. nd_column_major_store { dst [ptr [i32]], src [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    lln.loop { i, j } [lln.range_nd { { 0, 2 }, { 0, 3 } }] {
      set (dst[j * 2 + i])(src[i * 3 + j]),
    },
  },
}
]=]

local session = lalin.use { scope = "env" }

local function load_decl(source)
    return assert(session:loadstring(source, "bench_lalin_source_shapes.lua"))()
end

local function plan_source(source, name, stem_prefix, copy_patch)
    local decl = load_decl(source)
    return lalin.plan_luajit_artifact(decl, {
        name = name,
        stem = stem_prefix .. "_" .. copy_patch .. "_plan",
        copy_patch = copy_patch,
        native_residual = native_residual and copy_patch == "mc" or nil,
    })
end

local function build_setup_mc_bank(plan, stem_prefix)
    if #(plan.artifacts or {}) == 0 then return nil end
    local bank, err = plan.backend.build_mc_bank(plan.artifacts, {
        stem = stem_prefix .. "_mc_bank_setup",
    })
    assert(bank ~= nil, tostring(err))
    return bank
end

local mc_plan_main = plan_source(main_source, "SourceShapeBench", "source_shapes_main", "mc")
local bc_plan_main = plan_source(main_source, "SourceShapeBench", "source_shapes_main", "bc")
local mc_plan_nd = plan_source(nd_source, "SourceShapeNDAffineBench", "source_shapes_nd", "mc")
local mc_bank_main = build_setup_mc_bank(mc_plan_main, "source_shapes_main")
local mc_bank_nd = build_setup_mc_bank(mc_plan_nd, "source_shapes_nd")

local function compile_once(plan, copy_patch, serial, name, stem_prefix, mc_bank)
    return lalin.emit_luajit_plan_artifact(plan, {
        path = "target/luajit_bench/" .. stem_prefix .. "_" .. copy_patch .. "_" .. tostring(serial) .. ".lua",
        name = name,
        stem = stem_prefix .. "_" .. copy_patch .. "_" .. tostring(serial),
        copy_patch = copy_patch,
        mc_bank = copy_patch == "mc" and mc_bank or nil,
        native_residual = native_residual and copy_patch == "mc" or nil,
    })
end

local function measure_compile(plan, copy_patch, name, stem_prefix, mc_bank)
    local times, last = {}, nil
    for i = 1, compile_samples do
        collectgarbage()
        local t0 = Measure.now()
        last = compile_once(plan, copy_patch, i, name, stem_prefix, mc_bank)
        times[i] = Measure.now() - t0
    end
    return times, last
end

os.execute("mkdir -p target/luajit_bench")

local mc_compile, mc_artifact = measure_compile(mc_plan_main, "mc", "SourceShapeBench", "source_shapes_main", mc_bank_main)
local bc_compile, bc_artifact = measure_compile(bc_plan_main, "bc", "SourceShapeBench", "source_shapes_main")
local nd_mc_compile, nd_mc_artifact = measure_compile(mc_plan_nd, "mc", "SourceShapeNDAffineBench", "source_shapes_nd", mc_bank_nd)
local mc = assert(loadfile(mc_artifact.path))()
local bc = assert(loadfile(bc_artifact.path))()
local nd_mc = assert(loadfile(nd_mc_artifact.path))()

local c_path = "target/luajit_bench/source_shapes_baseline.c"
local so_path = "target/luajit_bench/source_shapes_baseline.so"
write_file(c_path, [=[
#include <stdint.h>

int32_t gcc_sum_i32(const int32_t *xs, int32_t n) {
  uint32_t acc = 0;
  for (int32_t i = 0; i < n; ++i) acc += (uint32_t)xs[i];
  return (int32_t)acc;
}

void gcc_zip_add_i32(int32_t *dst, const int32_t *lhs, const int32_t *rhs, int32_t n) {
  for (int32_t i = 0; i < n; ++i) dst[i] = (int32_t)((uint32_t)lhs[i] + (uint32_t)rhs[i]);
}

int32_t gcc_fused_reduce_i32(const int32_t *lhs, const int32_t *rhs, const int32_t *bias, int32_t n) {
  uint32_t acc = 0;
  for (int32_t i = 0; i < n; ++i) acc += ((uint32_t)lhs[i] * (uint32_t)rhs[i]) + (uint32_t)bias[i];
  return (int32_t)acc;
}

void gcc_scan_sum_i32(int32_t *dst, const int32_t *xs, int32_t n) {
  uint32_t acc = 0;
  for (int32_t i = 0; i < n; ++i) { acc += (uint32_t)xs[i]; dst[i] = (int32_t)acc; }
}

void gcc_scatter_reduce_add_i32(int32_t *dst, const int32_t *src, const int32_t *idx, int32_t n) {
  for (int32_t i = 0; i < n; ++i) dst[idx[i]] = (int32_t)((uint32_t)dst[idx[i]] + (uint32_t)src[i]);
}
]=])
assert(exec_ok(table.concat({ shell_quote(cc), gcc_cflags, "-fPIC -shared", shell_quote(c_path), "-o", shell_quote(so_path) }, " ")), "gcc baseline compile failed")

ffi.cdef [[
int32_t gcc_sum_i32(const int32_t *xs, int32_t n);
void gcc_zip_add_i32(int32_t *dst, const int32_t *lhs, const int32_t *rhs, int32_t n);
int32_t gcc_fused_reduce_i32(const int32_t *lhs, const int32_t *rhs, const int32_t *bias, int32_t n);
void gcc_scan_sum_i32(int32_t *dst, const int32_t *xs, int32_t n);
void gcc_scatter_reduce_add_i32(int32_t *dst, const int32_t *src, const int32_t *idx, int32_t n);
]]
local gcc = ffi.load(so_path)

local xs = ffi.new("int32_t[?]", n)
local ys = ffi.new("int32_t[?]", n)
local bias = ffi.new("int32_t[?]", n)
local idx = ffi.new("int32_t[?]", n)
local out = ffi.new("int32_t[?]", n)
local bins = ffi.new("int32_t[?]", n)
for i = 0, n - 1 do
    xs[i] = bit.tobit((i % 97) - 48)
    ys[i] = bit.tobit((i % 31) - 15)
    bias[i] = bit.tobit((i % 17) - 8)
    idx[i] = i
end

local function checksum(buf)
    return bit.tobit(buf[0] + buf[math.floor((n - 1) / 2)] + buf[n - 1])
end

local function clear_bins()
    ffi.fill(bins, ffi.sizeof("int32_t") * n, 0)
end

local function nd_check(mod)
    local src6 = ffi.new("int32_t[6]", { 1, 2, 3, 4, 5, 6 })
    local dst6 = ffi.new("int32_t[6]")
    mod.nd_column_major_store(dst6, src6, 6)
    return bit.tobit(dst6[0] + dst6[1] * 10 + dst6[2] * 100 + dst6[3] * 1000 + dst6[4] * 10000 + dst6[5] * 100000)
end

local cases = {
    { name = "mc sum", fn = function() return mc.sum_i32(xs, n) end },
    { name = "bc sum", fn = function() return bc.sum_i32(xs, n) end },
    { name = "gcc sum", fn = function() return gcc.gcc_sum_i32(xs, n) end },

    { name = "mc zip_add", fn = function() mc.zip_add_i32(out, xs, ys, n); return checksum(out) end },
    { name = "bc zip_add", fn = function() bc.zip_add_i32(out, xs, ys, n); return checksum(out) end },
    { name = "gcc zip_add", fn = function() gcc.gcc_zip_add_i32(out, xs, ys, n); return checksum(out) end },

    { name = "mc fused_reduce", fn = function() return mc.fused_reduce_i32(xs, ys, bias, n) end },
    { name = "bc fused_reduce", fn = function() return bc.fused_reduce_i32(xs, ys, bias, n) end },
    { name = "gcc fused_reduce", fn = function() return gcc.gcc_fused_reduce_i32(xs, ys, bias, n) end },

    { name = "mc scan", fn = function() mc.scan_sum_i32(out, xs, n); return checksum(out) end },
    { name = "bc scan", fn = function() bc.scan_sum_i32(out, xs, n); return checksum(out) end },
    { name = "gcc scan", fn = function() gcc.gcc_scan_sum_i32(out, xs, n); return checksum(out) end },

    { name = "mc scatter_reduce", fn = function() clear_bins(); mc.scatter_reduce_add_i32(bins, xs, idx, n); return checksum(bins) end },
    { name = "bc scatter_reduce", fn = function() clear_bins(); bc.scatter_reduce_add_i32(bins, xs, idx, n); return checksum(bins) end },
    { name = "gcc scatter_reduce", fn = function() clear_bins(); gcc.gcc_scatter_reduce_add_i32(bins, xs, idx, n); return checksum(bins) end },

    { name = "mc nd_affine_fixed", fn = function() return nd_check(nd_mc) end },
}

print(string.format("Lalin source-shape benchmark mode=%s n=%d compile_samples=%d runtime_samples=%d rounds=%d native_residual=%s", mode, n, compile_samples, runtime_samples, rounds, tostring(native_residual)))
print(stats_line("source compile+materialize mc", mc_compile))
print(stats_line("source compile+materialize bc", bc_compile))
print(stats_line("source compile+materialize mc nd", nd_mc_compile))
for _, result in ipairs(Measure.measure(cases, {
    samples = runtime_samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do
    print(Measure.format_result(result))
end
