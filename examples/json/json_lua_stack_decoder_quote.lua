-- Lalin JSON Decoder → Lua stack values
--
-- Generated with plain Lua metaprogramming (string building + loadstring).
-- The same algorithm as the Lalin decoder, but generated as pure Lua.
-- Shows how Lalin's metaprogramming philosophy applies to ANY target.
--
-- Run:
--   luajit examples/json/json_lua_stack_decoder_quote.lua

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")

ffi.cdef [[
    typedef struct lua_State lua_State;
    lua_State* luaL_newstate(void);
    void lua_close(lua_State *L);
    int lua_gettop(lua_State *L);
    int lua_type(lua_State *L, int idx);
    size_t lua_objlen(lua_State *L, int idx);
    const char *lua_tolstring(lua_State *L, int idx, size_t *len);
    void lua_createtable(void *L, int narr, int nrec);
    void lua_pushlstring(void *L, const char *s, size_t len);
    void lua_pushnumber(void *L, double n);
    void lua_pushboolean(void *L, int b);
    void lua_pushnil(void *L);
    void lua_settable(void *L, int idx);
    void lua_rawseti(void *L, int idx, int n);
]]

local C = ffi.C

-- Build the decoder source line by line
local src = {}

local function line(fmt, ...)
    src[#src + 1] = fmt and string.format(fmt, ...) or ""
end

line('local ffi = require("ffi")')
line('local C = ffi.C')
line("local bit = require('bit')")
line("local function skip_ws(p, n, i)")
line("    while i < n do")
line("        local c = p[i]")
line("        if c ~= 32 and c ~= 10 and c ~= 13 and c ~= 9 then break end")
line("        i = i + 1")
line("    end")
line("    return i")
line("end")
line("")

-- parse_string: handles escapes and unicode
line("local function parse_string(L, p, n, i, buf)")
line("    if i >= n or p[i] ~= 34 then return -1 end")
line("    local j = 0; i = i + 1")
line("    while i < n do")
line("        local c = p[i]")
line("        if c == 34 then")
line("            C.lua_pushlstring(L, buf, j); return i + 1")
line("        end")
line("        if c < 32 then return -1 end")
line("        if c == 92 then")
line("            i = i + 1; if i >= n then return -1 end; c = p[i]")
line("            if c == 34 or c == 92 or c == 47 then buf[j] = c")
line("            elseif c == 98 then buf[j] = 8")
line("            elseif c == 102 then buf[j] = 12")
line("            elseif c == 110 then buf[j] = 10")
line("            elseif c == 114 then buf[j] = 13")
line("            elseif c == 116 then buf[j] = 9")
line("            elseif c == 117 then")
line("                local cp = 0")
line("                for k = 1, 4 do")
line("                    i = i + 1; if i >= n then return -1 end; c = p[i]")
line("                    if c >= 48 and c <= 57 then cp = cp * 16 + (c - 48)")
line("                    elseif c >= 65 and c <= 70 then cp = cp * 16 + (c - 55)")
line("                    elseif c >= 97 and c <= 102 then cp = cp * 16 + (c - 87)")
line("                    else return -1 end")
line("                end")
line("                if cp < 128 then buf[j] = cp")
line("                elseif cp < 2048 then")
line("                    buf[j] = 192 + bit.rshift(cp, 6)")
line("                    buf[j+1] = 128 + bit.band(cp, 63); j = j + 1")
line("                else")
line("                    buf[j] = 224 + bit.rshift(cp, 12)")
line("                    buf[j+1] = 128 + bit.band(bit.rshift(cp,6),63); j = j + 1")
line("                    buf[j+1] = 128 + bit.band(cp,63); j = j + 1")
line("                end")
line("            else return -1 end")
line("            j = j + 1; i = i + 1")
line("        else")
line("            buf[j] = c; j = j + 1; i = i + 1")
line("        end")
line("    end")
line("    return -1")
line("end")
line("")

-- parse_number
line("local function parse_number(L, p, n, i)")
line("    if i >= n then return -1 end")
line("    local sig = 1")
line("    if p[i] == 45 then sig = -1; i = i + 1 end")
line("    if i >= n or p[i] < 48 or p[i] > 57 then return -1 end")
line("    local val = 0")
line("    while i < n and p[i] >= 48 and p[i] <= 57 do")
line("        val = val * 10 + (p[i] - 48); i = i + 1")
line("    end")
line("    if i < n and p[i] == 46 then")
line("        i = i + 1; local frac = 0; local div = 1")
line("        while i < n and p[i] >= 48 and p[i] <= 57 do")
line("            frac = frac * 10 + (p[i] - 48); div = div * 10; i = i + 1")
line("        end")
line("        val = val + frac / div")
line("    end")
line("    C.lua_pushnumber(L, sig * val); return i")
line("end")
line("")

-- Forward declarations for mutual recursion
line("local parse_value, parse_array, parse_object")
line("")

-- parse_value: dispatches by first byte
line("parse_value = function(L, p, n, i, buf)")
line("    i = skip_ws(p, n, i)")
line("    if i >= n then return -1 end")
line("    local c = p[i]")
line("    if c == 34 then return parse_string(L, p, n, i, buf) end")
line("    if c == 91 then return parse_array(L, p, n, i, buf) end")
line("    if c == 123 then return parse_object(L, p, n, i, buf) end")
line("    if c == 116 and n-i>=4 and p[i+1]==114 and p[i+2]==117 and p[i+3]==101 then")
line("        C.lua_pushboolean(L, 1); return i + 4")
line("    end")
line("    if c == 102 and n-i>=5 and p[i+1]==97 and p[i+2]==108 and p[i+3]==115 and p[i+4]==101 then")
line("        C.lua_pushboolean(L, 0); return i + 5")
line("    end")
line("    if c == 110 and n-i>=4 and p[i+1]==117 and p[i+2]==108 and p[i+3]==108 then")
line("        C.lua_pushnil(L); return i + 4")
line("    end")
line("    return parse_number(L, p, n, i)")
line("end")
line("")

-- parse_array
line("parse_array = function(L, p, n, i, buf)")
line("    if p[i] ~= 91 then return -1 end")
line("    C.lua_createtable(L, 16, 0)")
line("    i = skip_ws(p, n, i + 1)")
line("    if i >= n then return -1 end")
line("    if p[i] == 93 then return i + 1 end")
line("    local idx = 1")
line("    while true do")
line("        i = parse_value(L, p, n, i, buf)")
line("        if i < 0 then return -1 end")
line("        C.lua_rawseti(L, -2, idx); idx = idx + 1")
line("        i = skip_ws(p, n, i)")
line("        if i >= n then return -1 end")
line("        if p[i] == 93 then return i + 1 end")
line("        if p[i] ~= 44 then return -1 end")
line("        i = skip_ws(p, n, i + 1)")
line("    end")
line("end")
line("")

-- parse_object
line("parse_object = function(L, p, n, i, buf)")
line("    if p[i] ~= 123 then return -1 end")
line("    C.lua_createtable(L, 0, 16)")
line("    i = skip_ws(p, n, i + 1)")
line("    if i >= n then return -1 end")
line("    if p[i] == 125 then return i + 1 end")
line("    while true do")
line("        if p[i] ~= 34 then return -1 end")
line("        i = parse_string(L, p, n, i, buf)")
line("        if i < 0 then return -1 end")
line("        i = skip_ws(p, n, i)")
line("        if i >= n or p[i] ~= 58 then return -1 end")
line("        i = parse_value(L, p, n, i + 1, buf)")
line("        if i < 0 then return -1 end")
line("        C.lua_settable(L, -3)")
line("        i = skip_ws(p, n, i)")
line("        if i >= n then return -1 end")
line("        if p[i] == 125 then return i + 1 end")
line("        if p[i] ~= 44 then return -1 end")
line("        i = skip_ws(p, n, i + 1)")
line("    end")
line("end")
line("")

-- Main entry: decode_json(L, json_str, len, buf) → bytes consumed or -1
line("return function(L, json, n, buf)")
line("    local p = ffi.cast('uint8_t *', json)")
line("    local i = parse_value(L, p, n, 0, buf)")
line("    if i < 0 then return -1 end")
line("    i = skip_ws(p, n, i)")
line("    if i == n then return i end")
line("    return -1")
line("end")

-- Compile
local source = table.concat(src, "\n")
local decode_fn, err = loadstring(source, "=json_generated")
if not decode_fn then error("compile failed: " .. tostring(err), 2) end
local decode_json_str = decode_fn()

-- ---------------------------------------------------------------------------
-- Execution test
-- ---------------------------------------------------------------------------

local function decode_into_new_state(json)
    local L = C.luaL_newstate()
    local buf = ffi.new("uint8_t[?]", #json + 1)
    local parsed_end = decode_json_str(L, json, #json, buf)
    return L, parsed_end
end

local function close(L) C.lua_close(L) end

-- Basic
local L, parsed = decode_into_new_state("[true,false,null,42]")
assert(parsed == 20)
assert(C.lua_gettop(L) == 1 and C.lua_type(L, 1) == 5 and C.lua_objlen(L, 1) == 4)
close(L)

-- String
L, parsed = decode_into_new_state('"hello"')
assert(parsed == 7)
local lenp = ffi.new("size_t[1]")
local s = C.lua_tolstring(L, 1, lenp)
assert(tonumber(lenp[0]) == 5 and ffi.string(s, 5) == "hello")
close(L)

-- Object
L, parsed = decode_into_new_state('{"a":1}')
assert(parsed > 0); close(L)

-- Nested
L, parsed = decode_into_new_state('{"features":["Splices","Regions","ASDL"]}')
assert(parsed > 0); close(L)

-- Complex
L, parsed = decode_into_new_state([[{"name":"Lalin","fast":true,"version":2.0,"features":["Splices","Regions","ASDL"],"overhead":null}]])
assert(parsed > 0); close(L)

-- Error cases
for _, bad in ipairs({ "", "tru", "[1,]", "{", "+1", '"unclosed' }) do
    L, parsed = decode_into_new_state(bad)
    assert(parsed < 0, "expected invalid: " .. bad); close(L)
end

-- Escapes
L, parsed = decode_into_new_state('"he\\\\llo"')
assert(parsed > 0); s = C.lua_tolstring(L, 1, lenp)
assert(ffi.string(s, tonumber(lenp[0])) == "he\\llo"); close(L)

L, parsed = decode_into_new_state('"line1\\nline2"')
assert(parsed > 0); s = C.lua_tolstring(L, 1, lenp)
assert(ffi.string(s, tonumber(lenp[0])) == "line1\nline2"); close(L)

L, parsed = decode_into_new_state('"\\u0041\\u0042\\u0043"')
assert(parsed > 0); s = C.lua_tolstring(L, 1, lenp)
assert(ffi.string(s, tonumber(lenp[0])) == "ABC"); close(L)

print("Lalin string-built JSON decoder ok")
return { fn = decode_json_str }
