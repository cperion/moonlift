package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")

-- Same functions, same types, same operations.
local MOM_SRC = [[
func ret7(): i32 return 7 end
func add(x: i32, y: i32): i32 return x + y end
func mul_add(a: i32, b: i32, c: i32): i32 return a * b + c end
func neg(x: i32): i32 return -x end
func lt(a: i32, b: i32): bool return a < b end
func eq(a: i32, b: i32): bool return a == b end
func ge(a: i32, b: i32): bool return a >= b end
]]

-- ============================================================
-- MOM frontend
-- ============================================================
local mom = require("moonlift.host_mom")

-- ============================================================
-- Lua frontend (builder API — no .mlua parsing overhead)
-- ============================================================
local moon = require("moonlift.host")

local function lua_compile()
    local M = moon.module("bench")
    M:export_func("ret7", {}, moon.i32, function(fn) fn:return_(moon.int(7)) end)
    M:export_func("add", {moon.param("a", moon.i32), moon.param("b", moon.i32)}, moon.i32, function(fn)
        fn:return_(fn:param("a"):add(fn:param("b")))
    end)
    M:export_func("mul_add", {moon.param("a", moon.i32), moon.param("b", moon.i32), moon.param("c", moon.i32)}, moon.i32, function(fn)
        fn:return_(fn:param("a"):mul(fn:param("b")):add(fn:param("c")))
    end)
    M:export_func("neg", {moon.param("x", moon.i32)}, moon.i32, function(fn)
        fn:return_(fn:param("x"):neg())
    end)
    M:export_func("lt", {moon.param("a", moon.i32), moon.param("b", moon.i32)}, moon.bool, function(fn)
        fn:return_(fn:param("a"):lt(fn:param("b")))
    end)
    M:export_func("eq", {moon.param("a", moon.i32), moon.param("b", moon.i32)}, moon.bool, function(fn)
        fn:return_(fn:param("a"):eq(fn:param("b")))
    end)
    M:export_func("ge", {moon.param("a", moon.i32), moon.param("b", moon.i32)}, moon.bool, function(fn)
        fn:return_(fn:param("a"):ge(fn:param("b")))
    end)
    local compiled = M:compile()
    compiled:free()
end

-- Verify both produce correct output
local c = mom(MOM_SRC)
local add_ptr = ffi.cast("int32_t (*)(int32_t, int32_t)", c:get("add"))
assert(add_ptr(20, 22) == 42)
c:free()

lua_compile()

local WARMUP = 50
local TRIALS = 500

print("Warming up...")
for i = 1, WARMUP do
    mom(MOM_SRC):free()
    lua_compile()
end
collectgarbage()

print(string.format("Benchmarking: %d trials per frontend", TRIALS))
print()

local t0 = os.clock()
for i = 1, TRIALS do
    mom(MOM_SRC):free()
end
local t_mom = os.clock() - t0
collectgarbage()

local t0 = os.clock()
for i = 1, TRIALS do
    lua_compile()
end
local t_lua = os.clock() - t0
collectgarbage()

local per_mom = t_mom / TRIALS * 1000
local per_lua = t_lua / TRIALS * 1000

print(string.format("%-20s %10s %10s %12s %10s", "Frontend", "Trials", "Total(s)", "ms/trial", "comp/s"))
print(string.rep("-", 70))
print(string.format("%-20s %10d %10.3f %12.3f %10d", "MOM", TRIALS, t_mom, per_mom, math.floor(TRIALS / t_mom)))
print(string.format("%-20s %10d %10.3f %12.3f %10d", "Lua frontend", TRIALS, t_lua, per_lua, math.floor(TRIALS / t_lua)))
print(string.rep("-", 70))
print(string.format("MOM is %.2fx faster", t_lua / t_mom))
