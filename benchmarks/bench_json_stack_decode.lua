-- Benchmark: Moonlift JSON stack decoder vs pure-Lua JSON decoder.
--
-- Parses a medium-sized JSON document many times, measuring throughput.
-- The Moonlift path uses the native-code decoder from the example .mlua,
-- compiled via Cranelift.  The Lua path is a hand-rolled recursive descent
-- decoder.  If lua-cjson is installed it is also benchmarked.
--
-- Run:
--   luajit benchmarks/bench_json_stack_decode.lua          # quick
--   luajit benchmarks/bench_json_stack_decode.lua full     # full

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Make locally installed rocks visible to LuaJIT. This keeps the benchmark
-- self-contained after `luarocks --lua-version=5.1 --local install ...`.
local home = os.getenv("HOME") or ""
package.path = package.path
    .. ";" .. home .. "/.luarocks/share/lua/5.1/?.lua"
    .. ";" .. home .. "/.luarocks/share/lua/5.1/?/init.lua"
package.cpath = package.cpath
    .. ";" .. home .. "/.luarocks/lib/lua/5.1/?.so"
    .. ";" .. home .. "/.luarocks/lib64/lua/5.1/?.so"

local ffi = require("ffi")

local mode = arg and arg[1] or "quick"
local ITERS = tonumber(os.getenv("MOONLIFT_BENCH_ITERS") or (mode == "full" and "10000" or "1000"))

-- ---------------------------------------------------------------------------
-- Build the JSON test document
-- ---------------------------------------------------------------------------

local function make_json()
    local parts = { '{"users":[' }
    for i = 1, 50 do
        if i > 1 then parts[#parts + 1] = "," end
        parts[#parts + 1] = string.format(
            '{"name":"user_%04d","age":%d,"active":%s,"score":%.1f}',
            i, 20 + (i % 50), i % 3 == 0 and "true" or "false", 50 + i * 0.7
        )
    end
    parts[#parts + 1] = '],"ok":true,"count":50}'
    return table.concat(parts)
end

local JSON = make_json()
local JSON_LEN = #JSON

-- ---------------------------------------------------------------------------
-- Lua C API declarations
-- ---------------------------------------------------------------------------

ffi.cdef [[
    typedef struct lua_State lua_State;
    lua_State* luaL_newstate(void);
    void lua_close(lua_State *L);
    void lua_createtable(lua_State *L, int narr, int nrec);
    void lua_pushlstring(lua_State *L, const char *s, size_t len);
    void lua_pushnumber(lua_State *L, double n);
    void lua_pushboolean(lua_State *L, int b);
    void lua_pushnil(lua_State *L);
    void lua_settable(lua_State *L, int idx);
    void lua_rawseti(lua_State *L, int idx, int n);
    void lua_settop(lua_State *L, int idx);
    int lua_gettop(lua_State *L);
    int lua_type(lua_State *L, int idx);
    size_t lua_objlen(lua_State *L, int idx);
]]

local C = ffi.C

-- ---------------------------------------------------------------------------
-- Moonlift decoder: load and compile
-- ---------------------------------------------------------------------------

io.write("  Compiling Moonlift decoder ... ")
io.flush()
local t_compile = os.clock()

local ml_result = dofile("examples/json/json_lua_stack_decoder.lua")
local compiled_module = ml_result.artifact
local compiled = ml_result.fn

print(string.format("%.3fs", os.clock() - t_compile))

-- Verify it works on the benchmark input
local json_p = ffi.cast("uint8_t *", JSON)
do
    local L = C.luaL_newstate()
    local buf = ffi.new("uint8_t[?]", JSON_LEN + 1)
    local endpos = compiled(L, json_p, JSON_LEN, buf)
    assert(tonumber(endpos) == JSON_LEN, "Moonlift decoder failed on benchmark input: endpos=" .. tonumber(endpos))
    C.lua_close(L)
end

-- ---------------------------------------------------------------------------
-- Generated Lua decoder (codegen via string building + loadstring)
-- ---------------------------------------------------------------------------

local gen_result = dofile("examples/json/json_lua_stack_decoder_quote.lua")
local gen_decode = gen_result.fn

-- Verify
local gen_buf = ffi.new("uint8_t[?]", JSON_LEN + 1)
do
    local L = C.luaL_newstate()
    local endpos = gen_decode(L, JSON, JSON_LEN, gen_buf)
    assert(tonumber(endpos) == JSON_LEN, "generated decoder failed")
    C.lua_close(L)
end

-- ---------------------------------------------------------------------------
-- Pure-Lua JSON decoder (recursive descent, no lpeg, no cjson)
-- ---------------------------------------------------------------------------

local function lua_json_decode(str, pos)
    pos = pos or 1

    local function skip_ws()
        while pos <= #str do
            local c = str:byte(pos)
            if c == 32 or c == 9 or c == 10 or c == 13 then pos = pos + 1
            else break end
        end
    end

    local function decode_value()
        skip_ws()
        if pos > #str then error("unexpected end") end
        local c = str:byte(pos)
        if c == 34 then return decode_string()
        elseif c == 91 then return decode_array()
        elseif c == 123 then return decode_object()
        elseif c == 116 then
            if str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
            error("expected true")
        elseif c == 102 then
            if str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
            error("expected false")
        elseif c == 110 then
            if str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
            error("expected null")
        else
            return decode_number()
        end
    end

    function decode_string()
        pos = pos + 1
        local start = pos
        while pos <= #str do
            local c = str:byte(pos)
            if c == 34 then
                local s = str:sub(start, pos - 1)
                pos = pos + 1; return s
            elseif c == 92 then
                local parts = { str:sub(start, pos - 1) }
                pos = pos + 1
                while pos <= #str do
                    local ec = str:byte(pos)
                    if ec == 34 then
                        parts[#parts + 1] = str:sub(start, pos - 1)
                        pos = pos + 1; return table.concat(parts)
                    elseif ec == 92 then
                        parts[#parts + 1] = str:sub(start, pos - 1)
                        pos = pos + 1
                        local esc = str:byte(pos)
                        if esc == 117 then
                            parts[#parts + 1] = str:sub(pos - 1, pos + 4)
                            pos = pos + 5
                        else
                            parts[#parts + 1] = str:sub(pos - 1, pos)
                            pos = pos + 1
                        end
                        start = pos
                    else
                        pos = pos + 1
                    end
                end
                error("unterminated string")
            else
                pos = pos + 1
            end
        end
        error("unterminated string")
    end

    function decode_number()
        local start = pos
        if str:byte(pos) == 45 then pos = pos + 1 end
        while pos <= #str and str:byte(pos) >= 48 and str:byte(pos) <= 57 do pos = pos + 1 end
        if pos <= #str and str:byte(pos) == 46 then
            pos = pos + 1
            while pos <= #str and str:byte(pos) >= 48 and str:byte(pos) <= 57 do pos = pos + 1 end
        end
        if pos <= #str and (str:byte(pos) == 101 or str:byte(pos) == 69) then
            pos = pos + 1
            if pos <= #str and (str:byte(pos) == 43 or str:byte(pos) == 45) then pos = pos + 1 end
            while pos <= #str and str:byte(pos) >= 48 and str:byte(pos) <= 57 do pos = pos + 1 end
        end
        return tonumber(str:sub(start, pos - 1))
    end

    function decode_array()
        pos = pos + 1; skip_ws()
        local arr = {}
        if pos <= #str and str:byte(pos) == 93 then pos = pos + 1; return arr end
        while true do
            arr[#arr + 1] = decode_value()
            skip_ws()
            if pos > #str then error("unterminated array") end
            local c = str:byte(pos)
            if c == 93 then pos = pos + 1; return arr end
            if c == 44 then pos = pos + 1
            else error("expected , or ]") end
        end
    end

    function decode_object()
        pos = pos + 1; skip_ws()
        local obj = {}
        if pos <= #str and str:byte(pos) == 125 then pos = pos + 1; return obj end
        while true do
            skip_ws()
            local key = decode_string()
            skip_ws()
            if str:byte(pos) ~= 58 then error("expected :") end
            pos = pos + 1
            local val = decode_value()
            obj[key] = val
            skip_ws()
            if pos > #str then error("unterminated object") end
            local c = str:byte(pos)
            if c == 125 then pos = pos + 1; return obj end
            if c == 44 then pos = pos + 1
            else error("expected , or }") end
        end
    end

    local result = decode_value()
    return result, pos
end

-- Verify Lua decoder
do
    local result, endpos = lua_json_decode(JSON)
    assert(result ~= nil, "Lua decoder failed on benchmark input")
end

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

local function bench(name, fn, iters)
    collectgarbage("collect")
    local checksum = 0
    local t0 = os.clock()
    for _ = 1, iters do
        checksum = checksum + fn()
    end
    local dt = os.clock() - t0
    local ns_per_byte = dt / iters / JSON_LEN * 1e9
    local mb_per_sec = JSON_LEN * iters / dt / 1e6
    print(string.format("  %-28s %8.3fs  %7.1f ns/B  %7.1f MB/s  chk=%d",
        name, dt, ns_per_byte, mb_per_sec, checksum))
    return dt
end

-- ---------------------------------------------------------------------------
-- Run
-- ---------------------------------------------------------------------------

print(string.format("bench_json_stack_decode  mode=%s  iters=%d  json_len=%d",
    mode, ITERS, JSON_LEN))
print()

-- Moonlift benchmark
-- Reuse one lua_State. Creating/closing a Lua state per decode is several
-- microseconds of host-side overhead and completely drowns the native parser.
local moonlift_L = C.luaL_newstate()
local decode_buf = ffi.new("uint8_t[?]", JSON_LEN + 1)

local function moonlift_decode()
    local endpos = compiled(moonlift_L, json_p, JSON_LEN, decode_buf)
    C.lua_settop(moonlift_L, 0)
    return endpos == JSON_LEN and 1 or 0
end

-- Warmup
for _ = 1, math.max(1, math.floor(ITERS / 10)) do moonlift_decode() end

local t_moonlift = bench("moonlift_json_stack", moonlift_decode, ITERS)

-- Generated Lua benchmark
local gen_state = C.luaL_newstate()
local function gen_decode_run()
    local endpos = gen_decode(gen_state, JSON, JSON_LEN, gen_buf)
    C.lua_settop(gen_state, 0)
    return endpos == JSON_LEN and 1 or 0
end

for _ = 1, math.max(1, math.floor(ITERS / 10)) do gen_decode_run() end

local t_gen = bench("generated_lua_json", gen_decode_run, ITERS)

-- Pure-Lua benchmark
local function lua_decode()
    local result, endpos = lua_json_decode(JSON)
    return endpos
end

for _ = 1, math.max(1, math.floor(ITERS / 10)) do lua_decode() end

local t_lua = bench("pure_lua_json", lua_decode, ITERS)

-- cjson benchmark (if available)
local has_cjson, cjson_mod = pcall(require, "cjson")
local t_cjson = nil
if has_cjson then
    local function cjson_decode()
        local result = cjson_mod.decode(JSON)
        return result and 1 or 0
    end
    for _ = 1, math.max(1, math.floor(ITERS / 10)) do cjson_decode() end
    t_cjson = bench("cjson_decode", cjson_decode, ITERS)
else
    print("  (cjson not available — install lua-cjson for comparison)")
end

-- dkjson benchmark (if available)
local has_dkjson, dkjson_mod = pcall(require, "dkjson")
local t_dkjson = nil
if has_dkjson then
    local function dkjson_decode()
        local result = dkjson_mod.decode(JSON)
        return result and 1 or 0
    end
    for _ = 1, math.max(1, math.floor(ITERS / 10)) do dkjson_decode() end
    t_dkjson = bench("dkjson_decode", dkjson_decode, ITERS)
else
    print("  (dkjson not available — install dkjson for comparison)")
end

print()
print(string.format("  moonlift / lua speedup:    %.2fx", t_lua / t_moonlift))
if t_cjson then print(string.format("  moonlift / cjson speedup:  %.2fx", t_cjson / t_moonlift)) end
if t_dkjson then print(string.format("  moonlift / dkjson speedup: %.2fx", t_dkjson / t_moonlift)) end

-- Cleanup
C.lua_close(moonlift_L)
C.lua_close(gen_state)
compiled_module:free()
