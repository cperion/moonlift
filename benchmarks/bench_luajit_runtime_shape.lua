package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")

ffi.cdef[[
typedef long intptr_t;
typedef struct {
  void* dst;
  void* src;
  intptr_t n;
  intptr_t a;
  intptr_t b;
} Param;
void *memmove(void *dest, const void *src, size_t n);
]]

local N = tonumber(arg[1]) or 2000000
local buf_a = ffi.new("uint8_t[64]")
local buf_b = ffi.new("uint8_t[64]")
local memmove = ffi.C.memmove
local Param = ffi.typeof("Param")

local rt = {}
function rt.get(cache, name)
  local fn = cache[name]
  if fn == nil then
    fn = memmove
    cache[name] = fn
  end
  return fn
end

local cache = { mv = memmove }
local reusable = Param()
local fn_up = memmove

local function generic_alloc(n)
  local sum = 0
  for i = 1, n do
    local fn = rt.get(cache, "mv")
    local p = Param(buf_a, buf_b, 0, i, i + 1)
    fn(p.dst, p.src, 0)
    sum = sum + tonumber(p.a)
  end
  return sum
end

local function generic_reuse(n)
  local sum = 0
  local p = reusable
  for i = 1, n do
    local fn = rt.get(cache, "mv")
    p.dst = buf_a
    p.src = buf_b
    p.n = 0
    p.a = i
    p.b = i + 1
    fn(p.dst, p.src, 0)
    sum = sum + tonumber(p.a)
  end
  return sum
end

local hot
local function hot_impl(n)
  local sum = 0
  local p = reusable
  local fn = fn_up
  for i = 1, n do
    p.dst = buf_a
    p.src = buf_b
    p.n = 0
    p.a = i
    p.b = i + 1
    fn(p.dst, p.src, 0)
    sum = sum + tonumber(p.a)
  end
  return sum
end

local function cold(n)
  fn_up = memmove
  hot = hot_impl
  return hot_impl(n)
end

hot = cold

local function patched_reuse(n)
  return hot(n)
end

local function direct_reuse(n)
  local sum = 0
  local p = reusable
  local fn = fn_up
  for i = 1, n do
    p.dst = buf_a
    p.src = buf_b
    p.n = 0
    p.a = i
    p.b = i + 1
    fn(p.dst, p.src, 0)
    sum = sum + tonumber(p.a)
  end
  return sum
end

local function alloc_no_c(n)
  local sum = 0
  for i = 1, n do
    local p = Param(buf_a, buf_b, 0, i, i + 1)
    sum = sum + tonumber(p.a)
  end
  return sum
end

local function reuse_no_c(n)
  local sum = 0
  local p = reusable
  for i = 1, n do
    p.dst = buf_a
    p.src = buf_b
    p.n = 0
    p.a = i
    p.b = i + 1
    sum = sum + tonumber(p.a)
  end
  return sum
end

local function bench(name, f)
  collectgarbage("collect")
  local t0 = os.clock()
  local result = f(N)
  local dt = os.clock() - t0
  io.write(string.format("%-18s %.6f  result=%d\n", name, dt, result % 1000000))
end

bench("generic_alloc", generic_alloc)
bench("generic_reuse", generic_reuse)
bench("patched_reuse", patched_reuse)
bench("direct_reuse", direct_reuse)
bench("alloc_no_c", alloc_no_c)
bench("reuse_no_c", reuse_no_c)
