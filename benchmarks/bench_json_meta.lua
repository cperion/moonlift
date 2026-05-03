-- Test and benchmark the metaprogrammed JSON parser (lib/json_meta.mlua).

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")

-- Load and compile the metaprogrammed JSON module
local Host = require("moonlift.host_quote")
local json_meta = Host.dofile("lib/json_meta.mlua")

assert(json_meta and json_meta.compile, "json_meta.mlua did not return a compilable module")

local compiled_meta = json_meta:compile()
local artifact = compiled_meta.artifact

-- Print what functions are available
print("=== Metaprogrammed JSON module compiled ===")
for name, _ in pairs(json_meta.signatures) do
    print("  exported: " .. name)
end

local valid_meta = ffi.cast("int32_t (*)(const uint8_t*, int32_t, int32_t*, int32_t)",
    artifact:getpointer("json_valid_scalar"))

local stack = ffi.new("int32_t[?]", 256)

local function check(s)
    local buf = ffi.new("uint8_t[?]", #s)
    ffi.copy(buf, s, #s)
    return tonumber(valid_meta(buf, #s, stack, 256))
end

-- Test valid JSON
local good = {
    "null",
    "true",
    "false",
    "0",
    "-12",
    "12.34",
    "1e10",
    "1.5e-3",
    "1E+10",
    "[1,2,3]",
    "[]",
    "{}",
    [[{"a":1,"b":[true,false,null],"c":"x\\ny","u":"\u0041"}]],
    "  [ { \"x\" : -1.25e+2 } ]  ",
    "\t\r\n 123 ",
}

print("\n=== Testing valid JSON ===")
for i = 1, #good do
    local r = check(good[i])
    if r ~= 0 then
        print(string.format("  FAIL [%d]: expected 0, got %d  input: %s", i, r, good[i]))
    else
        print(string.format("  OK   [%d]: %s", i, good[i]))
    end
end

-- Test invalid JSON
local bad = {
    "",
    "[",
    "[1,]",
    "[01]",
    [["bad\q"]],
    [["bad\u12xz"]],
    [[{"a" 1}]],
    [[{"a":}]],
    "true false",
    "tru",
    "fals",
    "nul",
    "[1 2]",
}

print("\n=== Testing invalid JSON ===")
for i = 1, #bad do
    local r = check(bad[i])
    if r == 0 then
        print(string.format("  FAIL [%d]: expected non-zero, got 0  input: %s", i, bad[i]))
    else
        print(string.format("  OK   [%d]: error at offset %d  input: %s", i, r, bad[i]))
    end
end

-- Benchmark vs original
print("\n=== Performance comparison ===")
local Json = require("moonlift.json_library")
local compiled_orig, err = Json.compile()
assert(compiled_orig, tostring(err and err.stage))
local valid_orig = ffi.cast("int32_t (*)(const uint8_t*, int32_t, int32_t*, int32_t)",
    compiled_orig.artifact:getpointer("json_valid_scalar"))

local function build_json(count)
    local parts = { "{\"items\":[" }
    for i = 1, count do
        if i > 1 then parts[#parts + 1] = "," end
        local v = (i * 17 + 3) % 1009
        parts[#parts + 1] = "{\"id\":" .. tostring(v) .. ",\"ok\":true,\"name\":\"item\\u0041\"}"
    end
    parts[#parts + 1] = "],\"tail\":null}"
    return table.concat(parts)
end

local ITERS = 10000
local quick = (arg and arg[1]) == "quick"
if quick then ITERS = 5000 end

local src = build_json(quick and 200 or 2000)
local buf = ffi.new("uint8_t[?]", #src)
ffi.copy(buf, src, #src)
local meta_stack = ffi.new("int32_t[?]", 4096)
local orig_stack = ffi.new("int32_t[?]", 4096)

-- Verify both return valid
local r1 = tonumber(valid_meta(buf, #src, meta_stack, 4096))
local r2 = tonumber(valid_orig(buf, #src, orig_stack, 4096))
print(string.format("Payload: %d bytes", #src))
assert(r1 == 0, "meta validator failed on benchmark payload: " .. tostring(r1))
assert(r2 == 0, "orig validator failed on benchmark payload: " .. tostring(r2))
print("Both validators agree: valid JSON")

-- Benchmark meta
collectgarbage("collect")
local t0 = os.clock()
local checksum = 0
for _ = 1, ITERS do
    checksum = checksum + tonumber(valid_meta(buf, #src, meta_stack, 4096))
end
local t_meta = os.clock() - t0

-- Benchmark original
collectgarbage("collect")
t0 = os.clock()
for _ = 1, ITERS do
    checksum = checksum + tonumber(valid_orig(buf, #src, orig_stack, 4096))
end
local t_orig = os.clock() - t0

print(string.format("Meta validator:  %.6f s  (%d iters, %.0f MB/s)",
    t_meta, ITERS, (#src * ITERS) / t_meta / 1e6))
print(string.format("Orig validator:  %.6f s  (%d iters, %.0f MB/s)",
    t_orig, ITERS, (#src * ITERS) / t_orig / 1e6))
print(string.format("Ratio meta/orig: %.3f", t_meta / t_orig))

compiled_meta:free()
compiled_orig.artifact:free()
print("\nDone.")
