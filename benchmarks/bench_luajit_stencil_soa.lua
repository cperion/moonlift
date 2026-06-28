-- Benchmark real DSL SoA stencils against direct GCC loops.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")
local Measure = require("lalin.luajit_measure")

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_LJ_SOA_STENCIL_BENCH_N") or (full and "1000000" or "120000"))
local samples = tonumber(os.getenv("LALIN_LJ_SOA_STENCIL_BENCH_SAMPLES") or (full and "5" or "3"))
local rounds = tonumber(os.getenv("LALIN_LJ_SOA_STENCIL_BENCH_ROUNDS") or (full and "3" or "2"))
local cc = os.getenv("LALIN_LJ_SOA_STENCIL_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("LALIN_LJ_SOA_STENCIL_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local stencil_cflags = os.getenv("LALIN_LJ_SOA_STENCIL_BENCH_STENCIL_CFLAGS")
    or "-std=c99 -O3 -march=native -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local source = [=[
return unit. SoABench {
  struct. PairSoA {
    left [i32],
    right [i32],
    total [i32],
  },

  fn. soa_zip_add { total [ptr [i32]], left [ptr [i32]], right [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(total, n), writeonly(total), soa_component(total, PairSoA, "total", 2),
      bounds(left, n), readonly(left), soa_component(left, PairSoA, "left", 0),
      bounds(right, n), readonly(right), soa_component(right, PairSoA, "right", 1),
      disjoint(total, left), disjoint(total, right), disjoint(left, right),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },
      jump. done {},
    },

    block. body { i [i32] } {
      store (total[i], left[i] + right[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. soa_zip_sum { left [ptr [i32]], right [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds(left, n), readonly(left), soa_component(left, PairSoA, "left", 0),
      bounds(right, n), readonly(right), soa_component(right, PairSoA, "right", 1),
      disjoint(left, right),
    },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },
      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + (left[i] + right[i]) },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },
}
]=]

local session = lalin.use { scope = "env" }
local decl = assert(session:loadstring(source, "bench_luajit_stencil_soa.lua"))()
local plan = lalin.plan_luajit_artifact(decl, {
    name = "SoABench",
    stem = "bench_luajit_stencil_soa",
})
local bank = assert(plan.backend.build_mc_bank(plan.artifacts, {
    stem = "bench_luajit_stencil_soa",
    cc = cc,
    cflags = stencil_cflags,
}))
local artifact = lalin.emit_luajit_plan_artifact(plan, {
    path = "target/luajit_bench/bench_luajit_stencil_soa_artifact.lua",
    name = "SoABench",
    stem = "bench_luajit_stencil_soa",
    mc_bank = bank,
})
local compiled = assert(loadfile(artifact.path))()

os.execute("mkdir -p target/luajit_bench")
local c_path = "target/luajit_bench/stencil_soa_baseline.c"
local so_path = "target/luajit_bench/stencil_soa_baseline.so"
write_file(c_path, [=[
#include <stdint.h>

void gcc_soa_zip_add(int32_t *total, const int32_t *left, const int32_t *right, int32_t n) {
    for (int32_t i = 0; i < n; i++) total[i] = (int32_t)((uint32_t)left[i] + (uint32_t)right[i]);
}

int32_t gcc_soa_zip_sum(const int32_t *left, const int32_t *right, int32_t n) {
    uint32_t acc = 0;
    for (int32_t i = 0; i < n; i++) acc = (uint32_t)(acc + (uint32_t)((uint32_t)left[i] + (uint32_t)right[i]));
    return (int32_t)acc;
}
]=])
local cmd = table.concat({ shell_quote(cc), cflags, "-fPIC -shared", shell_quote(c_path), "-o", shell_quote(so_path) }, " ")
local ok = os.execute(cmd)
assert(ok == true or ok == 0, "gcc baseline failed: " .. cmd)

ffi.cdef([[
void gcc_soa_zip_add(int32_t *total, const int32_t *left, const int32_t *right, int32_t n);
int32_t gcc_soa_zip_sum(const int32_t *left, const int32_t *right, int32_t n);
]])
local gcc = ffi.load(so_path)

local left = ffi.new("int32_t[?]", n)
local right = ffi.new("int32_t[?]", n)
local total = ffi.new("int32_t[?]", n)
local mid = math.floor(n / 2)
for i = 0, n - 1 do
    left[i] = (i % 97) - 48
    right[i] = (i % 53) + 3
    total[i] = 0
end

local cases = {
    { name = "lowered SoA zip_map", fn = function() compiled.soa_zip_add(total, left, right, n); return total[mid] end },
    { name = "gcc SoA zip_map", fn = function() gcc.gcc_soa_zip_add(total, left, right, n); return total[mid] end },
    { name = "lowered SoA zip_reduce", fn = function() return compiled.soa_zip_sum(left, right, n) end },
    { name = "gcc SoA zip_reduce", fn = function() return gcc.gcc_soa_zip_sum(left, right, n) end },
}

print(string.format("LuaJIT SoA stencil benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
for _, result in ipairs(Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do
    print(Measure.format_result(result))
end
