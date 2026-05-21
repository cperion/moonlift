-- test_poc_utf8.lua — Test the Moonlift UTF-8 validator
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

-- Load the Moonlift validator — auto-compiles on first call
local validate = Host.dofile("poc_utf8.mlua")

-- Helper: string → Moonlift-compatible test call
local ffi = require("ffi")
local function test_valid(s)
    local len = #s
    local buf = ffi.new("uint8_t[?]", len)
    ffi.copy(buf, s, len)
    return validate(buf, len) == 0
end

-- Test cases
local tests = {
    -- ASCII-only: always valid
    { "hello world", true },
    { "", true },

    -- 2-byte sequences: U+00A9 (©) = 0xC2 0xA9
    { "\xC2\xA9", true },

    -- 3-byte sequences: U+20AC (€) = 0xE2 0x82 0xAC
    { "\xE2\x82\xAC", true },

    -- 4-byte sequences: U+1F600 (😀) = 0xF0 0x9F 0x98 0x80
    { "\xF0\x9F\x98\x80", true },

    -- Mixed: ASCII + multi-byte
    { "hello \xC2\xA9 world \xE2\x82\xAC \xF0\x9F\x98\x80", true },

    -- Invalid: continuation byte in ground state
    { "\x80", false },
    { "hello\x80world", false },

    -- Invalid: missing continuation bytes
    { "\xC2", false },
    { "\xE2\x82", false },
    { "\xF0\x9F\x98", false },

    -- Invalid: overlong 2-byte (0xC0, 0xC1)
    { "\xC0\x80", false },
    { "\xC1\xBF", false },

    -- Invalid: overlong 3-byte (0xE0 with cont < 0xA0)
    { "\xE0\x80\x80", false },
    { "\xE0\x9F\x80", false },

    -- Invalid: surrogate (0xED with cont > 0x9F)
    { "\xED\xA0\x80", false },

    -- Invalid: overlong 4-byte (0xF0 with cont < 0x90)
    { "\xF0\x80\x80\x80", false },

    -- Invalid: beyond U+10FFFF (0xF4 with cont > 0x8F)
    { "\xF4\x90\x80\x80", false },

    -- Invalid: 0xFF start byte
    { "\xFF", false },
    { "\xFF\x80\x80\x80\x80", false },
}

local passed = 0
local failed = 0
for _, tc in ipairs(tests) do
    local input, expected = tc[1], tc[2]
    local result = test_valid(input)
    local status = result == expected and "PASS" or "FAIL"
    if status == "PASS" then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write(string.format("  %s: %q → expected %s, got %s\n", status, input, tostring(expected), tostring(result)))
    end
end

print(string.format("\nutf8 validator: %d/%d passed, %d failed\n", passed, passed + failed, failed))


if failed > 0 then
    os.exit(1)
end
