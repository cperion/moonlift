-- Benchmark: Moonlift JSON decoder implementation comparison
--
-- Compares:
--   1) JSON DSL .mlua module (examples/json/json_lua_stack_decoder.mlua)
--   2) Pre-DSL Moonlift quoting style (examples/json/json_lua_stack_decoder.lua)
--   3) Generated Lua-decoder string code path (examples/json/json_lua_stack_decoder_quote.lua)
--
-- Example:
--   luajit benchmarks/bench_json_dsl_vs_legacy.lua [quick|full]

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

ffi.cdef [[
    typedef struct lua_State lua_State;
    lua_State* luaL_newstate(void);
    void lua_close(lua_State *L);
    void lua_settop(lua_State *L, int idx);
]]

local C = ffi.C

local mode = arg and arg[1] or "quick"
local ITERS = tonumber(os.getenv("MOONLIFT_BENCH_ITERS") or (mode == "full" and "1200" or "250"))
local WARMUP = tonumber(os.getenv("MOONLIFT_BENCH_WARMUP") or (mode == "full" and "8" or "3"))
local USERS = tonumber(os.getenv("MOONLIFT_BENCH_USERS") or (mode == "full" and "3000" or "1200"))

local function now()
    return os.clock()
end

local function format_ms(sec)
    return string.format("%.3f", sec * 1000.0)
end

local function format_mb_per_s(sec, bytes, iters)
    if sec <= 0 then return "inf" end
    local total_bytes = bytes * iters
    return string.format("%.2f", (total_bytes / sec) / (1024 * 1024))
end

-- Build a stable medium JSON payload.
local function make_json(users)
    local parts = { '{"users":[' }
    for i = 1, users do
        if i > 1 then parts[#parts + 1] = "," end
        local active = (i % 2 == 0) and "true" or "false"
        parts[#parts + 1] = string.format(
            '{"id":%d,"name":"user_%07d","active":%s,"score":%.3f,"tags":[%d,%d,%d]}',
            i, i, active, 50 + (i % 2000) * 0.37, i % 97, (i * 17) % 99, (i * 29) % 97
        )
    end
    parts[#parts + 1] = '],"ok":true,"count":'
    parts[#parts + 1] = tostring(users)
    parts[#parts + 1] = '}'
    return table.concat(parts)
end

local JSON = make_json(USERS)
local JSON_LEN = #JSON

-- Compile/load all three implementations.
local t0 = now()
local dsl = nil
local dsl_ok_compile = true
local t_dsl_compile = 0.0
do
    local ok, result = pcall(function()
        return Host.dofile("examples/json/json_lua_stack_decoder.mlua")
    end)
    if ok then
        dsl = result
        t_dsl_compile = now() - t0
    else
        dsl_ok_compile = false
        io.write("dsl compile failed, continuing with legacy and quote paths:\n")
        io.write("  " .. tostring(result) .. "\n")
    end
end

local t1 = now()
local legacy = dofile("examples/json/json_lua_stack_decoder.lua")
local legacy_fn = assert(legacy.fn, "legacy loader did not return fn")
local t_legacy_compile = now() - t1

local t2 = now()
local quote = dofile("examples/json/json_lua_stack_decoder_quote.lua")
local quote_fn = assert(quote.fn, "quote loader did not return fn")
local t_quote_compile = now() - t2

-- Shared decoder state for stack-based decoders.
local legacy_state = {
    L = C.luaL_newstate(),
    buf = ffi.new("uint8_t[?]", JSON_LEN + 16),
    p = ffi.cast("uint8_t *", JSON)
}

local quote_state = {
    L = C.luaL_newstate(),
    buf = ffi.new("uint8_t[?]", JSON_LEN + 16)
}

local function legacy_decode_once()
    C.lua_settop(legacy_state.L, 0)
    return tonumber(legacy_fn(legacy_state.L, legacy_state.p, JSON_LEN, legacy_state.buf))
end

local function quote_decode_once()
    C.lua_settop(quote_state.L, 0)
    return tonumber(quote_fn(quote_state.L, JSON, JSON_LEN, quote_state.buf))
end

local function dsl_decode_once()
    local value, err = dsl.decode_or_nil(JSON)
    if value ~= nil then return 1 end
    error(("dsl decode failed at offset %d"):format(err and err.offset or 0), 2)
end

local function bench_case(name, fn)
    for _ = 1, WARMUP do fn() end
    collectgarbage("collect")

    local total = 0.0
    local best = math.huge
    local last
    for _ = 1, ITERS do
        local t = now()
        last = fn()
        local dt = now() - t
        total = total + dt
        if dt < best then best = dt end
    end
    return {
        name = name,
        mean = total / ITERS,
        best = best,
        last = last,
        total = total,
    }
end

local has_dsl = dsl ~= nil
local dsl_ok
if has_dsl then
    dsl_ok = dsl.decode_or_nil(JSON)
    if dsl_ok == nil then
        io.write("dsl warmup decode failed, skipping DSL path\n")
        has_dsl = false
    end
end

local legacy_ok = legacy_decode_once()
local quote_ok = quote_decode_once()
if legacy_ok ~= JSON_LEN or quote_ok ~= JSON_LEN then
    error("legacy/quote warmup decode mismatch")
end

local dsl_result = nil
if has_dsl then
    dsl_result = bench_case("dsl_mlua", dsl_decode_once)
end
local legacy_result = bench_case("legacy_moon", legacy_decode_once)
local quote_result = bench_case("quote_generated", quote_decode_once)

print("Moonlift JSON DSL vs legacy decode benchmark")
print(string.format("payload_bytes=%d", JSON_LEN))
print(string.format("iters=%d warmup=%d users=%d", ITERS, WARMUP, USERS))
if has_dsl then
    print(string.format("compile_ms dsl=%.3f legacy=%.3f quote=%.3f",
        t_dsl_compile * 1000.0,
        t_legacy_compile * 1000.0,
        t_quote_compile * 1000.0))
else
    print(string.format("compile_ms legacy=%.3f quote=%.3f", t_legacy_compile * 1000.0, t_quote_compile * 1000.0))
    if not dsl_ok_compile then
        print("compile_ms dsl: n/a (compile failed)")
    end
    if has_dsl == false and dsl_ok == nil then
        print("decode_ms dsl: n/a (decode warmup failed)")
    elseif not dsl_ok_compile then
        print("decode_ms dsl: n/a (compile failed)")
    end
end
print("decode_ms (mean,best)")
print(string.format("  %-16s %9s %9s  %10s MiB/s",
    "path", "mean", "best", "throughput"))

local function print_row(result)
    local mean_ms = format_ms(result.mean)
    local best_ms = format_ms(result.best)
    local throughput = format_mb_per_s(result.mean, JSON_LEN, ITERS)
    print(string.format("  %-16s %9s %9s  %10s",
        result.name, mean_ms, best_ms, throughput))
end

if dsl_result then
    print_row(dsl_result)
else
    print(string.format("  %-16s %9s %9s  %10s", "dsl_mlua", "n/a", "n/a", "n/a"))
end
print_row(legacy_result)
print_row(quote_result)

if dsl_result then
    print(string.format("ratio dsl_vs_legacy: %.2fx faster", legacy_result.mean / dsl_result.mean))
    print(string.format("ratio dsl_vs_quote: %.2fx faster", quote_result.mean / dsl_result.mean))
else
    print("ratio dsl_vs_legacy: n/a")
    print("ratio dsl_vs_quote: n/a")
end

C.lua_close(legacy_state.L)
C.lua_close(quote_state.L)
if dsl and dsl.close then pcall(dsl.close) end
