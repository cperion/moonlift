package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

-- ── C frontend ──
local lexer = require("moonlift.c.c_lexer")
local c_parse = require("moonlift.c.c_parse").Define(T)
local cimport_mod = require("moonlift.c.cimport").Define(T)
local lower_mod = require("moonlift.c.lower_c").Define(T)

-- ── Moonlift pipeline ──
local Typecheck = require("moonlift.tree_typecheck")
local SemLayout = require("moonlift.sem_layout_resolve")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local Jit = require("moonlift.back_jit")
local OpenFacts = require("moonlift.open_facts")
local OpenValidate = require("moonlift.open_validate")
local OpenExpand = require("moonlift.open_expand")

local OF = OpenFacts.Define(T)
local OV = OpenValidate.Define(T)
local OE = OpenExpand.Define(T)
local TC = Typecheck.Define(T)
local Layout = SemLayout.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local jit_api = Jit.Define(T)

local function compile_c_to_moontree(src)
    local r = lexer.lex(src, "test.c")
    local tu, issues = c_parse.parse(r.tokens, r.spans)
    if #issues > 0 then
        for _, i in ipairs(issues) do print("  PARSE: " .. i.message) end
        return nil
    end
    local tf, lf, ef = cimport_mod.cimport(tu.items, "test_mod")
    local mm = lower_mod.lower(tu.items, tf, lf, ef, "test_mod")
    return mm
end

local function moontree_to_native(mm)
    local ok, expanded = pcall(OE.module, mm)
    if not ok then return nil, "open_expand: " .. tostring(expanded) end
    local open_facts = OF.facts_of_module(expanded)
    local open_report = OV.validate(open_facts)
    if #open_report.issues ~= 0 then return nil, "open_validate: " .. #open_report.issues .. " issues" end
    local checked = TC.check_module(expanded)
    if #checked.issues ~= 0 then
        print("  typecheck issues:")
        for i = 1, math.min(3, #checked.issues) do
            print("    " .. tostring(checked.issues[i]))
        end
        return nil, "typecheck: " .. #checked.issues .. " issues"
    end
    local resolved = Layout.module(checked.module, {})
    local program = Lower.module(resolved)
    local report = V.validate(program)
    if #report.issues ~= 0 then return nil, "back_validate: " .. #report.issues .. " issues" end
    local artifact = jit_api.jit():compile(program)
    return artifact
end

local function compile_c(src, func_name)
    local mm = compile_c_to_moontree(src)
    if not mm then return nil, "c frontend failed" end
    local MT = T.MoonTree
    local func = nil
    for _, item in ipairs(mm.items or {}) do
        if pvm.classof(item) == MT.ItemFunc and item.func.name == func_name then
            func = item.func
            break
        end
    end
    if not func then return nil, "function not found" end
    print(string.format("  MoonTree: params=%d, body_stmts=%d",
        #(func.params or {}), #(func.body or {})))
    local artifact, errmsg = moontree_to_native(mm)
    if not artifact then return nil, errmsg or "moontree_to_native returned nil" end
    local BackId = T.MoonBack.BackFuncId
    local ptr = artifact:getpointer(BackId(func_name))
    if not ptr then return nil, "getpointer returned nil for " .. func_name end
    return ptr, artifact
end

-- ═══════════════════════════════════════════════════════════════
-- Benchmark 1: sum array — int sum(int* xs, int n)
-- ═══════════════════════════════════════════════════════════════

print("=== Benchmark 1: array sum ===")
local sum_src = "int sum(int* xs, int n) { int acc = 0; int i; for (i = 0; i < n; i = i + 1) { acc = acc + xs[i]; } return acc; }"

print("  Compiling with Moonlift C frontend...")
local moon_ptr, art = compile_c(sum_src, "sum")
if not moon_ptr then
    print("  FAILED: " .. tostring(art))
else
    local moon_sum = ffi.cast("int32_t (*)(const int32_t*, int32_t)", moon_ptr)

    -- Verify correctness
    local test_arr = ffi.new("int32_t[5]", {1, 2, 3, 4, 5})
    local r = moon_sum(test_arr, 5)
    print(string.format("  sum([1,2,3,4,5]) = %d (expected 15)", r))
    assert(r == 15, "wrong result")

    -- Benchmark
    local N = 1000
    local arr = ffi.new("int32_t[?]", N)
    for i = 0, N-1 do arr[i] = i + 1 end

    local ITER = 100000
    local start = os.clock()
    local acc = 0
    for _ = 1, ITER do
        acc = moon_sum(arr, N)
    end
    local elapsed = os.clock() - start
    local ops = ITER * N
    print(string.format("  Moonlift: %d elements x %d iters = %d ops in %.3fs = %.0f ns/elem",
        N, ITER, ops, elapsed, elapsed * 1e9 / ops))
    if art then art:free() end
end

-- ═══════════════════════════════════════════════════════════════
-- Benchmark 2: fibonacci — int fib(int n)
-- ═══════════════════════════════════════════════════════════════

print("\n=== Benchmark 2: fibonacci ===")
local fib_src = "int fib(int n) { if (n <= 1) return n; return fib(n-1) + fib(n-2); }"

print("  Compiling with Moonlift C frontend...")
local fib_ptr, art2 = compile_c(fib_src, "fib")
if not fib_ptr then
    print("  FAILED: " .. tostring(art2))
else
    local moon_fib = ffi.cast("int32_t (*)(int32_t)", fib_ptr)

    local r = moon_fib(10)
    print(string.format("  fib(10) = %d (expected 55)", r))
    assert(r == 55, "wrong result")

    local ITER = 5000000
    local start = os.clock()
    local acc = 0
    for _ = 1, ITER do
        acc = moon_fib(20)
    end
    local elapsed = os.clock() - start
    print(string.format("  Moonlift: fib(20) x %d calls in %.3fs = %.0f ns/call",
        ITER, elapsed, elapsed * 1e9 / ITER))
    if art2 then art2:free() end
end

-- ═══════════════════════════════════════════════════════════════
-- Benchmark 3: clamp — int clamp(int x, int lo, int hi)
-- ═══════════════════════════════════════════════════════════════

print("\n=== Benchmark 3: clamp ===")
local clamp_src = "int clamp(int x, int lo, int hi) { if (x < lo) return lo; if (x > hi) return hi; return x; }"

print("  Compiling with Moonlift C frontend...")
local clamp_ptr, art3 = compile_c(clamp_src, "clamp")
if not clamp_ptr then
    print("  FAILED: " .. tostring(art3))
else
    local moon_clamp = ffi.cast("int32_t (*)(int32_t, int32_t, int32_t)", clamp_ptr)

    local r = moon_clamp(50, 0, 100)
    print(string.format("  clamp(50, 0, 100) = %d (expected 50)", r))
    assert(r == 50, "wrong result")
    assert(moon_clamp(-5, 0, 100) == 0, "clamp low wrong")
    assert(moon_clamp(200, 0, 100) == 100, "clamp high wrong")

    local ITER = 200000000
    local start = os.clock()
    local acc = 0
    for i = 1, ITER do
        acc = moon_clamp(i % 200, 20, 180)
    end
    local elapsed = os.clock() - start
    print(string.format("  Moonlift: clamp x %d calls in %.3fs = %.1f ns/call",
        ITER, elapsed, elapsed * 1e9 / ITER))
    if art3 then art3:free() end
end

print("\nDone.")
