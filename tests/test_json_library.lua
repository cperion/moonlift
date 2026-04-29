package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Json = require("moonlift.json_library")

local compiled, err = Json.compile()
if not compiled then
    io.stderr:write("json library compile failed at " .. tostring(err.stage) .. "\n")
    for i = 1, #err.issues do io.stderr:write(tostring(err.issues[i]) .. "\n") end
    error("json library compile failed")
end

local artifact = compiled.artifact
local B2 = compiled.B2
local valid = ffi.cast("int32_t (*)(const uint8_t*, int32_t, int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("json_valid_scalar")))
local decode = ffi.cast("int32_t (*)(const uint8_t*, int32_t, int32_t*, int32_t*, int32_t, int32_t*, int32_t*, int32_t*, int32_t, int32_t*)", artifact:getpointer(B2.BackFuncId("json_decode_tape_scalar")))
local stack = ffi.new("int32_t[?]", 256)
local stack_kind = ffi.new("int32_t[?]", 256)

local function check(s)
    local buf = ffi.new("uint8_t[?]", #s)
    ffi.copy(buf, s, #s)
    return tonumber(valid(buf, #s, stack, 256))
end

local good = {
    "null",
    "true",
    "false",
    "0",
    "-12",
    "12.34",
    "1e10",
    "[1,2,3]",
    "[]",
    "{}",
    [[{"a":1,"b":[true,false,null],"c":"x\\ny","u":"\u0041"}]],
    "  [ { \"x\" : -1.25e+2 } ]  ",
}
for i = 1, #good do
    local r = check(good[i])
    assert(r == 0, "expected valid: " .. good[i] .. " got " .. r)
end

local bad = {
    "",
    "[",
    "[1,]",
    "[01]",
    [["bad\q"]],
    [["bad\u12xz"]],
    "{\"a\" 1}",
    "{\"a\":}",
    "true false",
}
for i = 1, #bad do
    local r = check(bad[i])
    assert(r ~= 0, "expected invalid: " .. bad[i])
end

local tape_src = [[{"a":[1,true,null,"x"],"b":-2.5e+3}]]
local tape_buf = ffi.new("uint8_t[?]", #tape_src)
ffi.copy(tape_buf, tape_src, #tape_src)
local cap = 64
local tags = ffi.new("int32_t[?]", cap)
local aa = ffi.new("int32_t[?]", cap)
local bb = ffi.new("int32_t[?]", cap)
local meta = ffi.new("int32_t[1]")
local count = tonumber(decode(tape_buf, #tape_src, stack, stack_kind, 256, tags, aa, bb, cap, meta))
assert(count > 0, "decode failed: " .. tostring(count))
local got = {}
for i = 0, count - 1 do got[#got + 1] = tonumber(tags[i]) end
local expect = { 3, 5, 1, 7, 8, 10, 6, 2, 5, 7, 4 }
assert(#got == #expect, "unexpected tape count " .. #got)
for i = 1, #expect do assert(got[i] == expect[i], "tag " .. i .. " expected " .. expect[i] .. " got " .. got[i]) end
assert(tape_src:sub(aa[1] + 1, aa[1] + bb[1]) == "a")
assert(tape_src:sub(aa[3] + 1, aa[3] + bb[3]) == "1")
assert(tape_src:sub(aa[6] + 1, aa[6] + bb[6]) == "x")
assert(tape_src:sub(aa[9] + 1, aa[9] + bb[9]) == "-2.5e+3")

local tape, tape_err = Json.decode_tape(compiled, tape_src, { stack_cap = 256, tape_cap = cap })
assert(tape, tostring(tape_err))
assert(tape.count == count)
assert(Json.unescape_string([[x\ny]]) == "x\ny")
assert(Json.unescape_string([[\u0041]]) == "A")

artifact:free()
print("moonlift json library ok")
