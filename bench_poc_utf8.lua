-- bench_poc_utf8.lua — Benchmark Moonlift UTF-8 validator vs pure Lua
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")
local ffi = require("ffi")

-- Lua state-machine UTF-8 validator — same algorithm as Moonlift
-- Uses string.byte (natural Lua); no goto (Lua 5.1)
local function lua_string(s)
    local len = #s
    local pos, state = 1, 0
    while true do
        if pos > len then return state == 0 end
        local byte = string.byte(s, pos)
        pos = pos + 1
        if state == 0 then
            if byte < 128 then
                -- stay in state 0
            elseif byte < 192 then return false
            elseif byte < 224 then
                if byte < 194 then return false end
                state = 1
            elseif byte < 240 then
                state = 2
            elseif byte < 248 then
                state = 3
            else return false end
        elseif state == 1 then
            if byte < 128 or byte >= 192 then return false end
            state = 0
        elseif state == 2 then
            if byte < 128 or byte >= 192 then return false end
            state = 4
        elseif state == 3 then
            if byte < 128 or byte >= 192 then return false end
            state = 5
        elseif state == 4 then
            if byte < 128 or byte >= 192 then return false end
            local start_byte = string.byte(s, pos - 3)
            if start_byte == 224 and string.byte(s, pos - 2) < 160 then return false end
            if start_byte == 237 and string.byte(s, pos - 2) > 159 then return false end
            state = 0
        elseif state == 5 then
            if byte < 128 or byte >= 192 then return false end
            state = 6
        elseif state == 6 then
            if byte < 128 or byte >= 192 then return false end
            local start_byte = string.byte(s, pos - 4)
            if start_byte == 240 and string.byte(s, pos - 3) < 144 then return false end
            if start_byte == 244 and string.byte(s, pos - 3) > 143 then return false end
            if start_byte > 244 then return false end
            state = 0
        else return false end
    end
end

-- Lua state-machine UTF-8 validator — same shape, same FFI data access as Moonlift
local function lua_ffi(buf, len)
    local pos, state = 0, 0
    while true do
        if pos >= len then return state == 0 end
        local byte = tonumber(buf[pos])
        pos = pos + 1
        if state == 0 then
            if byte < 128 then
            elseif byte < 192 then return false
            elseif byte < 224 then
                if byte < 194 then return false end
                state = 1
            elseif byte < 240 then
                state = 2
            elseif byte < 248 then
                state = 3
            else return false end
        elseif state == 1 then
            if byte < 128 or byte >= 192 then return false end
            state = 0
        elseif state == 2 then
            if byte < 128 or byte >= 192 then return false end
            state = 4
        elseif state == 3 then
            if byte < 128 or byte >= 192 then return false end
            state = 5
        elseif state == 4 then
            if byte < 128 or byte >= 192 then return false end
            local start_byte = tonumber(buf[pos - 3])
            if start_byte == 224 and tonumber(buf[pos - 2]) < 160 then return false end
            if start_byte == 237 and tonumber(buf[pos - 2]) > 159 then return false end
            state = 0
        elseif state == 5 then
            if byte < 128 or byte >= 192 then return false end
            state = 6
        elseif state == 6 then
            if byte < 128 or byte >= 192 then return false end
            local start_byte = tonumber(buf[pos - 4])
            if start_byte == 240 and tonumber(buf[pos - 3]) < 144 then return false end
            if start_byte == 244 and tonumber(buf[pos - 3]) > 143 then return false end
            if start_byte > 244 then return false end
            state = 0
        else return false end
    end
end

-- Verify both produce same results
local test_data = {
    "hello world",
    "",
    "\xC2\xA9",
    "\xE2\x82\xAC",
    "\xF0\x9F\x98\x80",
    "hello \xC2\xA9 world \xE2\x82\xAC \xF0\x9F\x98\x80",
    "\x80",
    "hello\x80world",
    "\xC2",
    "\xE2\x82",
    "\xF0\x9F\x98",
    "\xC0\x80",
    "\xC1\xBF",
    "\xE0\x80\x80",
    "\xE0\x9F\x80",
    "\xED\xA0\x80",
    "\xF0\x80\x80\x80",
    "\xF4\x90\x80\x80",
    "\xFF",
    "\xFF\x80\x80\x80\x80",
}

-- Load Moonlift validator
local validate = Host.dofile("poc_utf8.mlua")

for _, s in ipairs(test_data) do
    local buf = ffi.new("uint8_t[?]", #s)
    ffi.copy(buf, s, #s)
    local moon_result = validate(buf, #s) == 0
    local str_result = lua_string(s)
    local ffi_result = lua_ffi(buf, #s)
    assert(moon_result == str_result, string.format("moon/str mismatch for %q", s))
    assert(moon_result == ffi_result, string.format("moon/ffi mismatch for %q", s))
end

-- Generate a large valid UTF-8 string for benchmarking
-- Mix of ASCII + 2-byte + 3-byte + 4-byte sequences
local function gen_utf8(size)
    local chars = {}
    local i = 1
    while i <= size do
        local r = math.random()
        if r < 0.7 then
            chars[#chars + 1] = string.char(math.random(32, 126))  -- ASCII
            i = i + 1
        elseif r < 0.85 then
            chars[#chars + 1] = "\xC2\xA9"  -- ©
            i = i + 2
        elseif r < 0.95 then
            chars[#chars + 1] = "\xE2\x82\xAC"  -- €
            i = i + 3
        else
            chars[#chars + 1] = "\xF0\x9F\x98\x80"  -- 😀
            i = i + 4
        end
    end
    return table.concat(chars)
end

local data = gen_utf8(100000)
local data_buf = ffi.new("uint8_t[?]", #data)
ffi.copy(data_buf, data, #data)

-- Time functions
local function time_it(fn, iters)
    local start = os.clock()
    for _ = 1, iters do
        fn()
    end
    return os.clock() - start
end

local ITERS = 5000

-- Warm up JIT
validate(data_buf, #data)
lua_string(data)
lua_ffi(data_buf, #data)

local moon_time = time_it(function()
    validate(data_buf, #data)
end, ITERS)

local lua_str_time = time_it(function()
    lua_string(data)
end, ITERS)

local lua_ffi_time = time_it(function()
    lua_ffi(data_buf, #data)
end, ITERS)

local data_size = #data * ITERS

print()
print(string.format("Data size: %d bytes × %d iterations = %d MB", #data, ITERS, data_size / 1e6))
print()
print(string.format("  Moonlift native (block/jump):   %6.3fs  (%5.1f ns/B  %5.1f MB/s)",
    moon_time, moon_time * 1e9 / data_size, data_size / moon_time / 1e6))
print(string.format("  Lua while-loop (string.byte):   %6.3fs  (%5.1f ns/B  %5.1f MB/s)  %5.2fx slower",
    lua_str_time, lua_str_time * 1e9 / data_size, data_size / lua_str_time / 1e6, lua_str_time / moon_time))
print(string.format("  Lua while-loop (FFI buf):       %6.3fs  (%5.1f ns/B  %5.1f MB/s)  %5.2fx slower",
    lua_ffi_time, lua_ffi_time * 1e9 / data_size, data_size / lua_ffi_time / 1e6, lua_ffi_time / moon_time))
print()
