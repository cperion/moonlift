-- Real Lalin benchmark for JIT structural product functions.
--
-- This decomposes the earlier single timing into loop baseline, aggregate ABI
-- load cost, inline flag classification, helper-call classification, and
-- aggregate helper calls.  It benchmarks compiled Lalin only; it does not
-- count Lua planners, LuaJIT byte probes, or fake native runners as JIT work.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")
local jit = require("experiments.lua_interpreter_vm.src.jit")
local C = jit.constants
local F = jit.funcs

local N = tonumber(arg[1]) or 10000000

ffi.cdef [[
typedef struct BenchJitEffect { uint64_t flags; } BenchJitEffect;
]]

local base_flags = bit.bor(
    C.Effect.MAY_ALLOC,
    C.Effect.MAY_GC,
    C.Effect.MAY_CALL_LUA
)

local e = ffi.new("BenchJitEffect[1]")
e[0].flags = base_flags

local counted_loop = lalin.func [[
jit_bench_counted_loop(n: index): u64
    return region: u64
    entry start()
        jump loop(i = as(index, 0), acc = as(u64, 0))
    end
    block loop(i: index, acc: u64)
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + (as(u64, i) & as(u64, 1)))
    end
    end
end
]]

local aggregate_load_loop = lalin.func [[
jit_bench_aggregate_load(e: Effect, n: index): u64
    return region: u64
    entry start()
        jump loop(i = as(index, 0), acc = as(u64, 0))
    end
    block loop(i: index, acc: u64)
        if i >= n then yield acc end
        let flags: u64 = e.flags | (as(u64, i) & as(u64, 3))
        jump loop(i = i + 1, acc = acc + (flags & as(u64, 255)))
    end
    end
end
]]

local scalar_inline_loop = lalin.func {
    E_ALLOC = lalin.int(C.Effect.MAY_ALLOC),
    E_GC = lalin.int(C.Effect.MAY_GC),
    E_CALL = lalin.int(C.Effect.MAY_CALL_LUA),
    E_BRANCH = lalin.int(C.Effect.MAY_BRANCH),
    E_THROW = lalin.int(C.Effect.MAY_THROW),
    P_ROOTS = lalin.int(C.ProjectionReq.ROOTS),
    P_RESUME = lalin.int(C.ProjectionReq.RESUME),
    P_TARGET = lalin.int(C.ProjectionReq.TARGET),
    P_ERROR = lalin.int(C.ProjectionReq.ERROR),
    B_ALLOC = lalin.int(C.BoundaryReq.ALLOCATOR),
    B_GC = lalin.int(C.BoundaryReq.GC_SAFEPOINT),
    B_CALL = lalin.int(C.BoundaryReq.LUA_CALL),
    B_RET = lalin.int(C.BoundaryReq.VM_RETURN),
} [[
jit_bench_scalar_inline(flags_in: u64, n: index): u64
    return region: u64
    entry start()
        jump loop(i = as(index, 0), acc = as(u64, 0))
    end
    block loop(i: index, acc: u64)
        if i >= n then yield acc end
        let f: u64 = flags_in | (as(u64, i) & as(u64, 3))
        var p: u64 = 0
        var b: u64 = 0
        if (f & as(u64, @{E_ALLOC})) ~= 0 or (f & as(u64, @{E_GC})) ~= 0 then
            p = p | as(u64, @{P_ROOTS})
        end
        if (f & as(u64, @{E_CALL})) ~= 0 then
            p = p | as(u64, @{P_ROOTS}) | as(u64, @{P_RESUME})
            b = b | as(u64, @{B_CALL})
        end
        if (f & as(u64, @{E_BRANCH})) ~= 0 then
            p = p | as(u64, @{P_TARGET})
        end
        if (f & as(u64, @{E_THROW})) ~= 0 then
            p = p | as(u64, @{P_ERROR})
            b = b | as(u64, @{B_RET})
        end
        if (f & as(u64, @{E_ALLOC})) ~= 0 then b = b | as(u64, @{B_ALLOC}) end
        if (f & as(u64, @{E_GC})) ~= 0 then b = b | as(u64, @{B_GC}) end
        jump loop(i = i + 1, acc = acc + p + b)
    end
    end
end
]]

local scalar_helper_loop = lalin.func {
    proj = F.jit_effect_projection_flags,
    bound = F.jit_effect_boundary_flags,
} [[
jit_bench_scalar_helpers(flags_in: u64, n: index): u64
    return region: u64
    entry start()
        jump loop(i = as(index, 0), acc = as(u64, 0))
    end
    block loop(i: index, acc: u64)
        if i >= n then yield acc end
        let f: u64 = flags_in | (as(u64, i) & as(u64, 3))
        let p: u64 = @{proj}(f)
        let b: u64 = @{bound}(f)
        jump loop(i = i + 1, acc = acc + p + b)
    end
    end
end
]]

local aggregate_helper_loop = lalin.func {
    proj = F.jit_effect_projection_flags,
    bound = F.jit_effect_boundary_flags,
} [[
jit_bench_aggregate_helpers(e: Effect, n: index): u64
    return region: u64
    entry start()
        jump loop(i = as(index, 0), acc = as(u64, 0))
    end
    block loop(i: index, acc: u64)
        if i >= n then yield acc end
        let f: u64 = e.flags | (as(u64, i) & as(u64, 3))
        let p: u64 = @{proj}(f)
        let b: u64 = @{bound}(f)
        jump loop(i = i + 1, acc = acc + p + b)
    end
    end
end
]]

local aggregate_flag_call_loop = lalin.func {
    has = F.jit_effect_has_flag,
    E_ALLOC = lalin.int(C.Effect.MAY_ALLOC),
} [[
jit_bench_aggregate_flag_call(e: Effect, n: index): u64
    return region: u64
    entry start()
        jump loop(i = as(index, 0), acc = as(u64, 0))
    end
    block loop(i: index, acc: u64)
        if i >= n then yield acc end
        if @{has}(e, as(u64, @{E_ALLOC})) then
            jump loop(i = i + 1, acc = acc + as(u64, 1))
        end
        jump loop(i = i + 1, acc = acc)
    end
    end
end
]]

local compiled = {
    counted = assert(counted_loop:compile()),
    aggregate_load = assert(aggregate_load_loop:compile()),
    scalar_inline = assert(scalar_inline_loop:compile()),
    scalar_helpers = assert(scalar_helper_loop:compile()),
    aggregate_helpers = assert(aggregate_helper_loop:compile()),
    aggregate_flag_call = assert(aggregate_flag_call_loop:compile()),
}

local rows = {}
local function bench(name, fn)
    fn() -- warmup, outside timing
    collectgarbage("collect")
    local t0 = os.clock()
    local result = fn()
    local dt = os.clock() - t0
    local ns = dt * 1e9 / N
    rows[#rows + 1] = { name = name, ns = ns, result = tostring(result) }
    return ns, result
end

local base_ns = bench("counted loop", function() return compiled.counted(N) end)
bench("aggregate load", function() return compiled.aggregate_load(e, N) end)
bench("scalar inline classify", function() return compiled.scalar_inline(base_flags, N) end)
bench("scalar helper classify", function() return compiled.scalar_helpers(base_flags, N) end)
bench("aggregate helper classify", function() return compiled.aggregate_helpers(e, N) end)
bench("aggregate has-flag call", function() return compiled.aggregate_flag_call(e, N) end)

print(string.format("Lalin structural decomposition: n=%d", N))
print(string.format("%-28s %12s %12s  %s", "case", "ns/iter", "net ns", "result"))
for _, row in ipairs(rows) do
    print(string.format("%-28s %12.3f %12.3f  %s", row.name, row.ns, row.ns - base_ns, row.result))
end

for _, c in pairs(compiled) do c:free() end
