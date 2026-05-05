package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local lexer = require("moonlift.c.c_lexer")
local cpp = require("moonlift.c.cpp_expand").Define(T)
local vfs = require("moonlift.c.vfs")
local c_parse = require("moonlift.c.c_parse").Define(T)
local cimport_mod = require("moonlift.c.cimport").Define(T)
local lower_mod = require("moonlift.c.lower_c").Define(T)

local function has_directives(tokens)
    for _, t in ipairs(tokens) do
        if t._variant == "CTokDirective" then return true end
    end
    return false
end

local function full_pipeline(src)
    local r = lexer.lex(src, "test.c")
    local tokens, spans, issues = r.tokens, r.spans, r.issues
    if has_directives(tokens) then
        local exp = cpp.expand(tokens, spans, issues, vfs.mock({}))
        tokens, spans = exp.tokens, exp.spans
    end
    local tu, parse_issues = c_parse.parse(tokens, spans)
    local type_facts, layout_facts, extern_funcs = cimport_mod.cimport(tu.items, "test_mod")
    local moon_module = lower_mod.lower(tu.items, type_facts, layout_facts, extern_funcs, "test_mod")
    return moon_module, tu, type_facts, layout_facts, extern_funcs
end

-- ═══════════════════════════════════════════════════════════════
-- Test: int add(int a, int b) { return a + b; }
-- ═══════════════════════════════════════════════════════════════

print("=== Test 1: int add(int a, int b) { return a + b; } ===")
local src = "int add(int a, int b) { return a + b; }"
local ok, result = pcall(full_pipeline, src)
if not ok then
    print("  FAIL: " .. tostring(result))
else
    local moon_module = result
    print(string.format("  MoonTree module: %s, %d items",
        moon_module._variant or "nil",
        #(moon_module.items or {})))
    for _, item in ipairs(moon_module.items or {}) do
        print(string.format("    [%s] %s", item._variant or "?",
            item.func and item.func.name or item.t and item.t.name or "???"))
    end
    print("  PASS")
end

-- ═══════════════════════════════════════════════════════════════
-- Test: int fib(int n) { if (n <= 1) return n; return fib(n-1) + fib(n-2); }
-- ═══════════════════════════════════════════════════════════════

print("\n=== Test 2: Fibonacci ===")
local src2 = "int fib(int n) { if (n <= 1) return n; return fib(n-1) + fib(n-2); }"
local ok, result = pcall(full_pipeline, src2)
if not ok then
    print("  FAIL: " .. tostring(result))
else
    local moon_module = result
    print(string.format("  MoonTree module: %s, %d items",
        moon_module._variant or "nil",
        #(moon_module.items or {})))
    for _, item in ipairs(moon_module.items or {}) do
        print(string.format("    [%s] %s", item._variant or "?",
            item.func and item.func.name or item.t and item.t.name or "???"))
        if item._variant == "ItemFunc" then
            print(string.format("      blocks: %d", #(item.func.body.blocks or {})))
            print(string.format("      bindings: %d", #(item.func.body.bindings or {})))
        end
    end
    print("  PASS")
end

-- ═══════════════════════════════════════════════════════════════
-- Test: void fill(int* dst, int n, int val) { for (int i=0; i<n; i++) dst[i]=val; }
-- ═══════════════════════════════════════════════════════════════

print("\n=== Test 3: For loop ===")
local src3 = "void fill(int* dst, int n, int val) { int i; for (i = 0; i < n; i = i + 1) { dst[i] = val; } }"
local ok, result = pcall(full_pipeline, src3)
if not ok then
    print("  FAIL: " .. tostring(result))
else
    local moon_module = result
    print(string.format("  MoonTree module: %s, %d items",
        moon_module._variant or "nil",
        #(moon_module.items or {})))
    for _, item in ipairs(moon_module.items or {}) do
        print(string.format("    [%s] %s", item._variant or "?",
            item.func and item.func.name or item.t and item.t.name or "???"))
        if item._variant == "ItemFunc" then
            local blocks = item.func.body.blocks or {}
            print(string.format("      blocks: %d", #blocks))
            for _, b in ipairs(blocks) do
                print(string.format("        [%s] label=%s", b._variant or "?", b.name or "?"))
            end
            print(string.format("      bindings: %d", #(item.func.body.bindings or {})))
        end
    end
    print("  PASS")
end

-- ═══════════════════════════════════════════════════════════════
-- Test: Simple loop with value accumulation
-- ═══════════════════════════════════════════════════════════════

print("\n=== Test 4: Sum array ===")
local src4 = "int sum(int* xs, int n) { int acc = 0; int i; for (i = 0; i < n; i = i + 1) { acc = acc + xs[i]; } return acc; }"
local ok, result = pcall(full_pipeline, src4)
if not ok then
    print("  FAIL: " .. tostring(result))
else
    local moon_module = result
    print(string.format("  MoonTree module: %s, %d items",
        moon_module._variant or "nil",
        #(moon_module.items or {})))
    for _, item in ipairs(moon_module.items or {}) do
        print(string.format("    [%s] %s", item._variant or "?",
            item.func and item.func.name or item.t and item.t.name or "???"))
    end
    print("  PASS")
end

print("\nDone.")
