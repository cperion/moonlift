-- Benchmark real Moonlift DSL CFG lowering through LuaTrace stencils vs Cranelift.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local moon = require("moonlift")
local Measure = require("moonlift.luajit_measure")

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("MOONLIFT_LJ_CFG_BENCH_N") or (full and "5000000" or "350000"))
local samples = tonumber(os.getenv("MOONLIFT_LJ_CFG_BENCH_SAMPLES") or (full and "9" or "5"))
local rounds = tonumber(os.getenv("MOONLIFT_LJ_CFG_BENCH_ROUNDS") or (full and "4" or "2"))
local warmup = tonumber(os.getenv("MOONLIFT_LJ_CFG_BENCH_WARMUP") or (full and "4" or "2"))

local source = [=[
return fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
  requires { bounds(xs, n), readonly(xs) },

  entry. start {} {
    jump. loop { i = 0, acc = 0 },
  },

  block. loop { i [i32], acc [i32] } {
    when (i :lt (n)) {
      jump. body { i = i, acc = acc },
    },

    jump. done { acc = acc },
  },

  block. body { i [i32], acc [i32] } {
    jump. loop { i = i + 1, acc = acc + xs[i] },
  },

  block. done { acc [i32] } {
    ret (acc),
  },
}
]=]

local decl = moon.loadstring(source, "bench_luajit_cfg_luatrace_vs_cranelift.lua")
local xs = ffi.new("int32_t[?]", n)
local expected = 0
for i = 0, n - 1 do
    xs[i] = bit.tobit(i * 17 + 11)
    expected = bit.tobit(expected + xs[i])
end

local cranelift_fn = decl:compile({ backend = "cranelift" })
local cranelift_sum = ffi.cast("int32_t (*)(int32_t *, int32_t)", cranelift_fn:getpointer("sum_i32"))
assert(tonumber(cranelift_sum(xs, n)) == expected, "cranelift result mismatch")

local source_artifact = moon.emit_luajit_artifact(decl, {
    name = "bench_luajit_cfg_luatrace",
    path = "target/luajit_bench/bench_luajit_cfg_luatrace.lua",
    stencil_provider = "lua_trace",
})
assert(source_artifact.source:match("Generated Moonlift LuaJIT LuaTrace artifact"), "expected LuaTrace artifact")
assert(source_artifact.source:match("local function ml_stencil_reduce_array_i32_add_to_i32_s1"), "expected emitted LuaTrace reduction")
assert(not source_artifact.source:match("__ml_install"), "LuaTrace artifact must not install binary stencils")
assert(#(source_artifact.artifacts or {}) > 0, "expected selected stencil artifact")
assert(source_artifact.bank == nil, "LuaTrace artifact should not build a binary bank")

local loader = loadstring or load
local chunk, load_err = loader(source_artifact.source, "@bench_luajit_cfg_luatrace")
assert(chunk ~= nil, tostring(load_err) .. "\n" .. source_artifact.source)
local source_module = chunk()
assert(tonumber(source_module.sum_i32(xs, n)) == expected, "LuaTrace source artifact result mismatch")

local cases = {
    {
        name = "cranelift cfg sum_i32",
        fn = function() return tonumber(cranelift_sum(xs, n)) end,
    },
    {
        name = "luatrace cfg sum_i32",
        fn = function() return tonumber(source_module.sum_i32(xs, n)) end,
    },
}

print(string.format(
    "Moonlift real CFG LuaTrace vs Cranelift benchmark mode=%s n=%d samples=%d rounds=%d warmup=%d",
    mode,
    n,
    samples,
    rounds,
    warmup
))
print("source artifact: " .. tostring(source_artifact.path) .. " bytes=" .. tostring(#source_artifact.source))
for _, result in ipairs(Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = warmup,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do
    print(Measure.format_result(result))
end

if cranelift_fn.free then cranelift_fn:free() end
