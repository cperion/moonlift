-- benchmark_backends.lua
-- Compare back_luajit (LuaJIT tracer) vs back_jit (Rust/Cranelift)
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local T = pvm.context()
A2.Define(T)

local mlua_parse = require("moonlift.mlua_parse").Define(T)
local OE = require("moonlift.open_expand").Define(T)
local OF = require("moonlift.open_facts").Define(T)
local OV = require("moonlift.open_validate").Define(T)
local TC = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local Lower = require("moonlift.tree_to_back").Define(T)
local VBE = require("moonlift.back_validate").Define(T)
local BL = require("moonlift.back_luajit").Define(T)
local BJ = require("moonlift.back_jit").Define(T)

local function compile_both(src)
    local parsed = mlua_parse.parse(src, "bench")
    assert(#parsed.issues == 0, "parse: " .. tostring(parsed.issues[1] and parsed.issues[1].message))
    local expanded = OE.module(parsed.module)
    local orpt = OV.validate(OF.facts_of_module(expanded))
    assert(#orpt.issues == 0, "open validate: " .. #orpt.issues)
    local checked = TC.check_module(expanded)
    assert(#checked.issues == 0, "typecheck: " .. #checked.issues)
    local resolved = Layout.module(checked.module, {})
    local program = Lower.module(resolved)
    local vrpt = VBE.validate(program)
    assert(#vrpt.issues == 0, "back validate: " .. #vrpt.issues)
    
    local lj_result = BL.compile(program)
    
    local cl_jit = BJ.jit()
    local artifact = cl_jit:compile(program)
    
    return program, lj_result, artifact, cl_jit
end

local function bench(name, fn_lj, fn_cl, cast_lj, cast_cl, args, N, iters)
    local lj_fn = cast_lj and ffi.cast(cast_lj, fn_lj) or fn_lj
    local cl_fn = cast_cl and ffi.cast(cast_cl, fn_cl) or fn_cl
    
    -- Warmup
    lj_fn(unpack(args))
    cl_fn(unpack(args))
    
    local lj_total = 0LL
    local t0 = os.clock()
    for _ = 1, iters do lj_total = lj_total + lj_fn(unpack(args)) end
    local lj_t = os.clock() - t0
    
    local cl_total = 0LL
    t0 = os.clock()
    for _ = 1, iters do cl_total = cl_total + cl_fn(unpack(args)) end
    local cl_t = os.clock() - t0
    
    return {
        name = name,
        lj_t = lj_t, cl_t = cl_t,
        lj_total = lj_total, cl_total = cl_total,
        ratio = lj_t / cl_t,
    }
end

print("=== Moonlift Backend Benchmark: LuaJIT vs Cranelift ===\n")

local results = {}

-- ── Benchmark 1: Integer arithmetic ──
do
    local src = [[
export func add(x: i32, y: i32) -> i32
    return x + y
end
]]
    local _, ljr, art, jit = compile_both(src)
    local cl_ptr = art:getpointer(T.MoonBack.BackFuncId("add"))
    local r = bench("add(i32,i32)",
        ljr.add, cl_ptr,
        nil, "int32_t(*)(int32_t,int32_t)",
        {20, 22}, 0, 2000000)
    results[#results+1] = r
    art:free()
    jit:free()
end

-- ── Benchmark 2: Fibonacci (conditional recursion pattern) ──
do
    local src = [[
export func fib(n: i32) -> i32
    if n <= 1 then return n end
    return fib(n - 1) + fib(n - 2)
end
]]
    local _, ljr, art, jit = compile_both(src)
    local cl_ptr = art:getpointer(T.MoonBack.BackFuncId("fib"))
    local r = bench("fib(35)",
        ljr.fib, cl_ptr,
        nil, "int32_t(*)(int32_t)",
        {35}, 0, 5)
    results[#results+1] = r
    art:free()
    jit:free()
end

-- ── Benchmark 3: Counting loop (block params) ──
do
    local src = [[
export func count(n: i32) -> i32
    block loop(i: i32 = 0, acc: i32 = 0)
        if i >= n then return acc end
        jump loop(i = i + 1, acc = acc + i)
    end
end
]]
    local _, ljr, art, jit = compile_both(src)
    local cl_ptr = art:getpointer(T.MoonBack.BackFuncId("count"))
    local r = bench("count(10000)",
        ljr.count, cl_ptr,
        nil, "int32_t(*)(int32_t)",
        {10000}, 0, 2000)
    results[#results+1] = r
    art:free()
    jit:free()
end

-- ── Benchmark 4: Branchy (if-else) ──
do
    local src = [[
export func sign(x: i32) -> i32
    if x < 0 then return -1 end
    if x > 0 then return 1 end
    return 0
end
]]
    local _, ljr, art, jit = compile_both(src)
    local cl_ptr = art:getpointer(T.MoonBack.BackFuncId("sign"))
    local r = bench("sign(42)",
        ljr.sign, cl_ptr,
        nil, "int32_t(*)(int32_t)",
        {42}, 0, 2000000)
    results[#results+1] = r
    art:free()
    jit:free()
end

-- ── Benchmark 5: Multiply-heavy ──
do
    local src = [[
export func dot(a: i32, b: i32, c: i32) -> i32
    return a * b + c
end
]]
    local _, ljr, art, jit = compile_both(src)
    local cl_ptr = art:getpointer(T.MoonBack.BackFuncId("dot"))
    local r = bench("dot(3,7,11)",
        ljr.dot, cl_ptr,
        nil, "int32_t(*)(int32_t,int32_t,int32_t)",
        {3, 7, 11}, 0, 2000000)
    results[#results+1] = r
    art:free()
    jit:free()
end

-- ── Benchmark 6: Select (branchless) ──
do
    local src = [[
export func abs_v(x: i32) -> i32
    return select(x < 0, -x, x)
end
]]
    local _, ljr, art, jit = compile_both(src)
    local cl_ptr = art:getpointer(T.MoonBack.BackFuncId("abs_v"))
    local r = bench("abs(-42)",
        ljr.abs_v, cl_ptr,
        nil, "int32_t(*)(int32_t)",
        {-42}, 0, 2000000)
    results[#results+1] = r
    art:free()
    jit:free()
end

-- ── Summary ──
print(string.format("%-25s %10s %10s %8s", "Benchmark", "LuaJIT", "Cranelift", "Ratio"))
print(string.rep("-", 55))
for _, r in ipairs(results) do
    print(string.format("%-25s %9.4fs %9.4fs %7.1fx",
        r.name, r.lj_t, r.cl_t, r.ratio))
end

-- Average ratio
local total_ratio = 0
for _, r in ipairs(results) do total_ratio = total_ratio + r.ratio end
print(string.format("\nAverage slowdown: %.1fx", total_ratio / #results))
