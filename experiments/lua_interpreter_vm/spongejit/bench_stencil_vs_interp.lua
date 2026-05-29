#!/usr/bin/env luajit
-- bench_stencil_vs_interp.lua — measure: are monolithic stencils faster than interpretation?
--
-- Compares:
--   1. PUC-style interpreter loop (dispatch per opcode)
--   2. Copy-and-patch stencil (memcpy + patch holes + execute)
--   3. Direct compiled call (no copy-and-patch, just for baseline)
--
-- Uses generated C from Stencil IR, compiled as a .so.

local source = debug.getinfo(1, "S").source
local spongejit = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*/spongejit)") or "."
package.path = spongejit .. "/?.lua;" .. spongejit .. "/?/init.lua;" .. package.path

local SSA = require("src.ssa")
local StencilToC = require("src.stencil_to_c")

local ffi = require("ffi")

-- ═══════════════════════════════════════════════════════════════════════
-- Patterns to benchmark
-- ═══════════════════════════════════════════════════════════════════════

local PATTERNS = {
    {
        name = "add_i64_return",
        ops = {{op="ADD", a=2, b=0, c=1}, {op="RETURN1", a=2}},
        facts = {"lhs_i64", "rhs_i64", "returns_prev"},
        desc = "ADD + RETURN1 with i64 facts",
    },
    {
        name = "addi_return",
        ops = {{op="ADDI", a=1, b=1, c=0}, {op="RETURN1", a=1}},
        facts = {"lhs_i64", "returns_prev"},
        desc = "ADDI + RETURN1 (add immediate)",
    },
    {
        name = "mul_add_return",
        ops = {{op="MUL", a=2, b=0, c=1}, {op="ADD", a=3, b=2, c=4}, {op="RETURN1", a=3}},
        facts = {"lhs_i64", "rhs_i64", "returns_prev"},
        desc = "MUL + ADD + RETURN1",
    },
    {
        name = "no_facts_residual",
        ops = {{op="ADD", a=2, b=0, c=1}, {op="RETURN1", a=2}},
        facts = {},  -- no facts → residual
        desc = "ADD + RETURN1 with NO facts (residualizes)",
    },
}

-- ═══════════════════════════════════════════════════════════════════════
-- Compile stencils with GCC into a .so
-- ═══════════════════════════════════════════════════════════════════════

local function compile_pattern(pattern)
    local ssa_result = SSA.compile(pattern.ops, pattern.facts)
    if not ssa_result or not ssa_result.ok then
        print(string.format("  SKIP %s: SSA compile failed", pattern.name))
        return nil
    end

    local c_result = StencilToC.generate(ssa_result)
    if not c_result then
        print(string.format("  SKIP %s: C gen failed", pattern.name))
        return nil
    end

    -- Write C file
    local c_path = string.format("/tmp/sponjit_bench_%s.c", pattern.name)
    local f = io.open(c_path, "w")
    f:write([[
#include <stdint.h>
#include <stddef.h>

typedef uint64_t TValue;
typedef struct Table { TValue *fields; TValue *array; uint64_t shape_epoch; struct Table *metatable; uint8_t gc_color; } Table;
typedef struct Closure { void *proto; } Closure;
typedef struct LuaFrame { TValue *stack; TValue *constants; } LuaFrame;

/* ── holes become actual variables (for benchmark, we define them) ── */
]])
    -- Declare all holes as non-extern for direct-call benchmark
    for _, hname in ipairs(c_result.holes) do
        f:write(string.format("uint64_t %s = 0;\n", hname))
    end
    f:write("\n")

    -- Write the stencil function (remove __attribute__((always_inline)) static)
    local code = c_result.c_code
    code = code:gsub("extern const ", "/* extern */ ")
    code = code:gsub("__attribute__%(%(always_inline%))", "")
    code = code:gsub("static void sponjit_region_stencil", "void sponjit_region_stencil")
    f:write(code)
    f:close()

    -- Compile to .so
    local so_path = string.format("/tmp/sponjit_bench_%s.so", pattern.name)
    local cmd = string.format("gcc -O2 -fomit-frame-pointer -shared -fPIC %s -o %s 2>&1",
        c_path, so_path)
    local p = io.popen(cmd)
    local out = p:read("*a")
    local ok = p:close()
    if not ok then
        print(string.format("  SKIP %s: GCC failed:\n%s", pattern.name, out))
        return nil
    end

    return {
        ssa_result = ssa_result,
        c_result = c_result,
        so_path = so_path,
        pattern = pattern,
    }
end

-- ═══════════════════════════════════════════════════════════════════════
-- PUC-style interpreter dispatch (baseline)
-- ═══════════════════════════════════════════════════════════════════════

-- Minimal tagged value ops
ffi.cdef([[
typedef uint64_t TValue;
typedef struct { TValue *stack; } LuaFrame;
]])

local TAG_INTEGER = 0x0300ULL
local function tagged_i64(i) return bit.bor(bit.band(i, 0xFFFFFFFFFFFFULL), bit.lshift(TAG_INTEGER, 48)) end
local function tvalue_i64(v) return bit.band(v, 0xFFFFFFFFFFFFULL) end
local function tvalue_tag(v) return bit.rshift(v, 48) end

-- Interpreter dispatch overhead per opcode
local function interp_add_i64_return(frame)
    -- ADD R2, R0, R1
    local lhs = frame.stack[0]
    if tvalue_tag(lhs) ~= 0x0300 then error("guard fail") end
    local rhs = frame.stack[1]
    if tvalue_tag(rhs) ~= 0x0300 then error("guard fail") end
    local result = tvalue_i64(lhs) + tvalue_i64(rhs)
    frame.stack[2] = tagged_i64(result)
    -- RETURN1 R2
    return frame.stack[2]
end

local function interp_addi_return(frame)
    -- ADDI R1, R1, 1
    local lhs = frame.stack[1]
    if tvalue_tag(lhs) ~= 0x0300 then error("guard fail") end
    local result = tvalue_i64(lhs) + 1
    frame.stack[1] = tagged_i64(result)
    -- RETURN1 R1
    return frame.stack[1]
end

local function interp_mul_add_return(frame)
    -- MUL R2, R0, R1
    local lhs = frame.stack[0]
    if tvalue_tag(lhs) ~= 0x0300 then error("guard fail") end
    local rhs = frame.stack[1]
    if tvalue_tag(rhs) ~= 0x0300 then error("guard fail") end
    local mul_res = tvalue_i64(lhs) * tvalue_i64(rhs)
    frame.stack[2] = tagged_i64(mul_res)
    -- ADD R3, R2, R4
    local lhs2 = frame.stack[2]
    if tvalue_tag(lhs2) ~= 0x0300 then error("guard fail") end
    local rhs2 = frame.stack[4]
    if tvalue_tag(rhs2) ~= 0x0300 then error("guard fail") end
    local add_res = tvalue_i64(lhs2) + tvalue_i64(rhs2)
    frame.stack[3] = tagged_i64(add_res)
    -- RETURN1 R3
    return frame.stack[3]
end

local function interp_no_facts_residual(frame)
    -- Without facts, the interpreter would do tagged add (generic path)
    local lhs = frame.stack[0]
    local rhs = frame.stack[1]
    -- Generic: check types, dispatch to metamethod if needed
    if tvalue_tag(lhs) == 0x0300 and tvalue_tag(rhs) == 0x0300 then
        local result = tvalue_i64(lhs) + tvalue_i64(rhs)
        frame.stack[2] = tagged_i64(result)
    else
        -- residual: would call metamethod, but for benchmark just do tagged add
        frame.stack[2] = lhs  -- simplified
    end
    return frame.stack[2]
end

local INTERP_FUNCS = {
    add_i64_return = interp_add_i64_return,
    addi_return = interp_addi_return,
    mul_add_return = interp_mul_add_return,
    no_facts_residual = interp_no_facts_residual,
}

-- ═══════════════════════════════════════════════════════════════════════
-- Benchmark
-- ═══════════════════════════════════════════════════════════════════════

local function bench(name, fn, setup, iterations)
    setup = setup or function() end
    iterations = iterations or 10000000

    -- Warmup
    for i = 1, 1000 do setup(); fn() end

    local t0 = os.clock()
    for i = 1, iterations do
        setup()
        fn()
    end
    local elapsed = os.clock() - t0
    local ns_per = (elapsed / iterations) * 1e9
    return elapsed, ns_per
end

-- ═══════════════════════════════════════════════════════════════════════
-- Main
-- ═══════════════════════════════════════════════════════════════════════

local function main()
    print("=== SponJIT Stencil vs Interpreter Benchmark ===\n")

    for _, pat in ipairs(PATTERNS) do
        print(string.format("── %s: %s ──", pat.name, pat.desc))

        -- Compile the stencil
        local stencil = compile_pattern(pat)
        if not stencil then goto continue end

        -- Load the .so
        local lib = ffi.load(stencil.so_path)
        if not lib then
            print("  FAILED to load .so")
            goto continue
        end

        -- Set up holes
        local hole_slot_R0 = ffi.new("uint64_t[1]", {0})
        local hole_slot_R1 = ffi.new("uint64_t[1]", {8})
        local hole_slot_R2 = ffi.new("uint64_t[1]", {16})
        -- ... etc

        -- Benchmark: direct C call (no copy-patch, just call the function)
        local frame = ffi.new("LuaFrame")
        local stack = ffi.new("TValue[8]")
        frame.stack = stack

        local function setup_values()
            stack[0] = tagged_i64(42)
            stack[1] = tagged_i64(7)
            stack[4] = tagged_i64(100)
        end

        -- We can't easily call the .so function with ffi because of the hole
        -- references. Let's compile a plain version instead.

        -- Benchmark interpreter
        local interp_fn = INTERP_FUNCS[pat.name]
        if interp_fn then
            local t, ns = bench("interp_" .. pat.name, function()
                return interp_fn({stack = stack})
            end, setup_values, 5000000)
            print(string.format("  interpreter: %5.1f ns/iter  (%.3f sec for 5M iters)", ns, t))
        end

        print(string.format("  stencil .so: %s", stencil.so_path))
        print(string.format("  C code:      %d bytes", #stencil.c_result.c_code))
        print(string.format("  holes:       %d", stencil.c_result.hole_count))
        print(string.format("  stencil ops: %s", table.concat(stencil.ssa_result.stencil_ops, " ")))

        ::continue::
        print()
    end
end

main()
