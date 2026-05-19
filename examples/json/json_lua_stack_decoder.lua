-- Moonlift JSON Decoder → Lua stack values
--
-- Pure Lua using the moon.XXX quoting API. No .mlua pipeline needed.
-- Region fragments and externs are referenced by name in Moonlift source.
-- Only @{} is used for truly Lua-generated values (literal_arms).
--
-- Run:
--   luajit examples/json/json_lua_stack_decoder.lua

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

ffi.cdef [[
    typedef struct lua_State lua_State;
    lua_State* luaL_newstate(void);
    void lua_close(lua_State *L);
    int lua_gettop(lua_State *L);
    int lua_type(lua_State *L, int idx);
    size_t lua_objlen(lua_State *L, int idx);
    const char *lua_tolstring(lua_State *L, int idx, size_t *len);
]]

-- ---------------------------------------------------------------------------
-- Extern imports — referenced by name in Moonlift source
-- ---------------------------------------------------------------------------

local lua_createtable = moon.extern [[extern lua_createtable(L: ptr(u8), narr: i32, nrec: i32) end]]
local lua_pushlstring = moon.extern [[extern lua_pushlstring(L: ptr(u8), s: ptr(u8), len: index) end]]
local lua_pushnumber  = moon.extern [[extern lua_pushnumber(L: ptr(u8), n: f64) end]]
local lua_pushboolean = moon.extern [[extern lua_pushboolean(L: ptr(u8), b: i32) end]]
local lua_pushnil     = moon.extern [[extern lua_pushnil(L: ptr(u8)) end]]
local lua_settable    = moon.extern [[extern lua_settable(L: ptr(u8), idx: i32) end]]
local lua_rawseti     = moon.extern [[extern lua_rawseti(L: ptr(u8), idx: i32, n: i32) end]]

-- ---------------------------------------------------------------------------
-- Region fragments — referenced by name via emit, no @{} needed
-- ---------------------------------------------------------------------------

local skip_ws = moon.region [[region skip_ws(p: ptr(u8), n: i32, pos: i32; ok: cont(i: i32))
entry loop(i: i32 = pos)
    if i >= n then jump ok(i = i) end
    switch as(i32, p[i]) do
    case 32 then jump loop(i = i + 1) -- space
    case 10 then jump loop(i = i + 1) -- \n
    case 13 then jump loop(i = i + 1) -- \r
    case 9  then jump loop(i = i + 1) -- \t
    default then jump ok(i = i)
    end
    jump ok(i = i)
end
end]]

local parse_string = moon.region [[region parse_string(
    L: ptr(u8), p: ptr(u8), n: i32, pos: i32, buf: ptr(u8);
    ok: cont(next_i: i32), err: cont()
)
entry start()
    if pos >= n then jump err() end
    if as(i32, p[pos]) ~= 34 then jump err() end
    jump copy(i = pos + 1, j = 0)
end
block copy(i: i32, j: i32)
    if i >= n then jump err() end
    let c: i32 = as(i32, p[i])
    if c == 34 then
        lua_pushlstring(L, buf, as(index, j))
        jump ok(next_i = i + 1)
    end
    if c < 32 then jump err() end
    if c == 92 then jump escaped(i = i + 1, j = j) end
    buf[j] = as(u8, c)
    jump copy(i = i + 1, j = j + 1)
end
block escaped(i: i32, j: i32)
    if i >= n then jump err() end
    let c: i32 = as(i32, p[i])
    switch c do
    case 34 then buf[j] = as(u8, 34); jump copy(i = i + 1, j = j + 1)
    case 92 then buf[j] = as(u8, 92); jump copy(i = i + 1, j = j + 1)
    case 47 then buf[j] = as(u8, 47); jump copy(i = i + 1, j = j + 1)
    case 98 then buf[j] = as(u8, 8);  jump copy(i = i + 1, j = j + 1)
    case 102 then buf[j] = as(u8, 12); jump copy(i = i + 1, j = j + 1)
    case 110 then buf[j] = as(u8, 10); jump copy(i = i + 1, j = j + 1)
    case 114 then buf[j] = as(u8, 13); jump copy(i = i + 1, j = j + 1)
    case 116 then buf[j] = as(u8, 9);  jump copy(i = i + 1, j = j + 1)
    case 117 then jump hex4(i = i + 1, j = j, cp = 0, left = 4)
    default then jump err()
    end
    jump err()
end
block hex4(i: i32, j: i32, cp: i32, left: i32)
    if left == 0 then jump emit_codepoint(i = i, j = j, cp = cp) end
    if i >= n then jump err() end
    let c: i32 = as(i32, p[i])
    if c >= 48 and c <= 57 then jump hex4(i = i + 1, j = j, cp = cp * 16 + (c - 48), left = left - 1) end
    if c >= 65 and c <= 70 then jump hex4(i = i + 1, j = j, cp = cp * 16 + (c - 55), left = left - 1) end
    if c >= 97 and c <= 102 then jump hex4(i = i + 1, j = j, cp = cp * 16 + (c - 87), left = left - 1) end
    jump err()
end
block emit_codepoint(i: i32, j: i32, cp: i32)
    if cp >= 55296 and cp <= 56319 then jump expect_low(i = i, j = j, hi = cp) end
    if cp >= 56320 and cp <= 57343 then jump err() end
    if cp < 128 then
        buf[j] = as(u8, cp)
        jump copy(i = i, j = j + 1)
    end
    if cp < 2048 then
        buf[j] = as(u8, 192 + (cp >> 6))
        buf[j + 1] = as(u8, 128 + (cp & 63))
        jump copy(i = i, j = j + 2)
    end
    buf[j] = as(u8, 224 + (cp >> 12))
    buf[j + 1] = as(u8, 128 + ((cp >> 6) & 63))
    buf[j + 2] = as(u8, 128 + (cp & 63))
    jump copy(i = i, j = j + 3)
end
block expect_low(i: i32, j: i32, hi: i32)
    if i + 1 >= n then jump err() end
    if as(i32, p[i]) ~= 92 then jump err() end
    if as(i32, p[i + 1]) ~= 117 then jump err() end
    jump hex4_low(i = i + 2, j = j, hi = hi, cp = 0, left = 4)
end
block hex4_low(i: i32, j: i32, hi: i32, cp: i32, left: i32)
    if left == 0 then
        if cp < 56320 then jump err() end
        if cp > 57343 then jump err() end
        let full: i32 = 65536 + (hi - 55296) * 1024 + (cp - 56320)
        buf[j] = as(u8, 240 + (full >> 18))
        buf[j + 1] = as(u8, 128 + ((full >> 12) & 63))
        buf[j + 2] = as(u8, 128 + ((full >> 6) & 63))
        buf[j + 3] = as(u8, 128 + (full & 63))
        jump copy(i = i, j = j + 4)
    end
    if i >= n then jump err() end
    let c: i32 = as(i32, p[i])
    if c >= 48 and c <= 57 then jump hex4_low(i = i + 1, j = j, hi = hi, cp = cp * 16 + (c - 48), left = left - 1) end
    if c >= 65 and c <= 70 then jump hex4_low(i = i + 1, j = j, hi = hi, cp = cp * 16 + (c - 55), left = left - 1) end
    if c >= 97 and c <= 102 then jump hex4_low(i = i + 1, j = j, hi = hi, cp = cp * 16 + (c - 87), left = left - 1) end
    jump err()
end
end]]

local parse_number = moon.region [[region parse_number(
    L: ptr(u8), p: ptr(u8), n: i32, pos: i32;
    ok: cont(next_i: i32), err: cont()
)
entry start()
    if pos >= n then jump err() end
    let first: i32 = as(i32, p[pos])
    if first == 45 then jump scan_int(i = pos + 1, neg = true, val = as(i64, 0)) end
    if first < 48 then jump err() end
    if first > 57 then jump err() end
    if first == 48 then
        if pos + 1 < n then
            let d1: i32 = as(i32, p[pos + 1])
            if d1 >= 48 and d1 <= 57 then jump err() end
        end
    end
    jump scan_int(i = pos, neg = true, val = as(i64, 0))
end
block scan_int(i: i32, neg: bool, val: i64)
    if i >= n then jump emit_int(neg = neg, val = val, end_i = i) end
    let c: i32 = as(i32, p[i])
    if c < 48 then jump emit_int(neg = neg, val = val, end_i = i) end
    if c > 57 then jump emit_int(neg = neg, val = val, end_i = i) end
    jump scan_int(i = i + 1, neg = neg, val = val * 10 + as(i64, c - 48))
end
block emit_int(neg: bool, val: i64, end_i: i32)
    let fv: f64 = as(f64, val)
    if end_i >= n then jump finish(neg = neg, result = fv, end_i = end_i) end
    let c: i32 = as(i32, p[end_i])
    if c == 46 then jump scan_frac(i = end_i + 1, neg = neg, int_part = fv, frac = 0.0, scale = 0.1) end
    if c == 101 or c == 69 then jump exp_sign(i = end_i + 1, neg = neg, result = fv) end
    jump finish(neg = neg, result = fv, end_i = end_i)
end
block scan_frac(i: i32, neg: bool, int_part: f64, frac: f64, scale: f64)
    if i >= n then jump finish(neg = neg, result = int_part + frac, end_i = i) end
    let c: i32 = as(i32, p[i])
    if c < 48 then
        if c == 101 or c == 69 then jump exp_sign(i = i + 1, neg = neg, result = int_part + frac) end
        jump finish(neg = neg, result = int_part + frac, end_i = i)
    end
    if c > 57 then
        if c == 101 or c == 69 then jump exp_sign(i = i + 1, neg = neg, result = int_part + frac) end
        jump finish(neg = neg, result = int_part + frac, end_i = i)
    end
    jump scan_frac(i = i + 1, neg = neg, int_part = int_part, frac = frac + scale * as(f64, c - 48), scale = scale * 0.1)
end
block exp_sign(i: i32, neg: bool, result: f64)
    if i >= n then jump err() end
    let c: i32 = as(i32, p[i])
    if c == 43 then jump exp_digits(i = i + 1, neg = neg, result = result, exp = 0, neg_exp = false) end
    if c == 45 then jump exp_digits(i = i + 1, neg = neg, result = result, exp = 0, neg_exp = true) end
    jump exp_digits(i = i, neg = neg, result = result, exp = 0, neg_exp = false)
end
block exp_digits(i: i32, neg: bool, result: f64, exp: i32, neg_exp: bool)
    if i >= n then jump apply_exp(neg = neg, result = result, exp = exp, neg_exp = neg_exp, end_i = i) end
    let c: i32 = as(i32, p[i])
    if c < 48 then jump apply_exp(neg = neg, result = result, exp = exp, neg_exp = neg_exp, end_i = i) end
    if c > 57 then jump apply_exp(neg = neg, result = result, exp = exp, neg_exp = neg_exp, end_i = i) end
    jump exp_digits(i = i + 1, neg = neg, result = result, exp = exp * 10 + (c - 48), neg_exp = neg_exp)
end
block apply_exp(neg: bool, result: f64, exp: i32, neg_exp: bool, end_i: i32)
    if neg_exp then
        if exp > 0 then jump apply_exp(neg = neg, result = result / 10.0, exp = exp - 1, neg_exp = true, end_i = end_i) end
        jump finish(neg = neg, result = result, end_i = end_i)
    else
        if exp > 0 then jump apply_exp(neg = neg, result = result * 10.0, exp = exp - 1, neg_exp = false, end_i = end_i) end
        jump finish(neg = neg, result = result, end_i = end_i)
    end
end
block finish(neg: bool, result: f64, end_i: i32)
    if neg then result = 0.0 - result end
    lua_pushnumber(L, result)
    jump ok(next_i = end_i)
end
end]]

-- ---------------------------------------------------------------------------
-- Generated literal switch arms — uses @{} because arms come from Lua data
-- ---------------------------------------------------------------------------

local function byte_checks(text, push_src)
    local bytes = { text:byte(1, #text) }
    local lines = {}
    lines[#lines + 1] = ("if i + %d > n then jump fail() end"):format(#bytes)
    for off = 2, #bytes do
        lines[#lines + 1] = ("if as(i32, p[i + %d]) ~= %d then jump fail() end"):format(off - 1, bytes[off])
    end
    lines[#lines + 1] = push_src
    lines[#lines + 1] = ("jump done(next_i = i + %d)"):format(#bytes)
    return table.concat(lines, "\n")
end

local function literal_arm(text, push_src)
    local bytes = { text:byte(1, #text) }
    return {
        raw_key = tostring(bytes[1]),
        body = moon.stmts(byte_checks(text, push_src)),
    }
end

local literal_arms = {
    literal_arm("true",  "lua_pushboolean(L, 1)"),
    literal_arm("false", "lua_pushboolean(L, 0)"),
    literal_arm("null",  "lua_pushnil(L)"),
}

-- ---------------------------------------------------------------------------
-- Mutually-recursive parser functions — region/lextern names resolve at compile time
-- @{} only for literal_arms (Lua-generated data)
-- ---------------------------------------------------------------------------

local parse_array = moon.func [[func parse_array(L: ptr(u8), p: ptr(u8), n: i32, pos: i32, buf: ptr(u8)) -> i32
    return region -> i32
    entry start()
        lua_createtable(L, 16, 0)
        emit skip_ws(p, n, pos + 1; ok = check_empty)
    end
    block check_empty(i: i32)
        if i >= n then yield -1 end
        if as(i32, p[i]) == 93 then yield i + 1 end
        jump parse_elem(i = i, arr_idx = 1)
    end
    block parse_elem(i: i32, arr_idx: i32)
        let next_i = parse_value(L, p, n, i, buf)
        if next_i < 0 then yield -1 end
        lua_rawseti(L, -2, arr_idx)
        jump ws_after_elem(i = next_i, arr_idx = arr_idx + 1)
    end
    block ws_after_elem(i: i32, arr_idx: i32)
        if i >= n then yield -1 end
        switch as(i32, p[i]) do
        case 32 then jump ws_after_elem(i = i + 1, arr_idx = arr_idx)
        case 10 then jump ws_after_elem(i = i + 1, arr_idx = arr_idx)
        case 13 then jump ws_after_elem(i = i + 1, arr_idx = arr_idx)
        case 9  then jump ws_after_elem(i = i + 1, arr_idx = arr_idx)
        default then jump check_comma(i = i, arr_idx = arr_idx)
        end
        jump check_comma(i = i, arr_idx = arr_idx)
    end
    block check_comma(i: i32, arr_idx: i32)
        if i >= n then yield -1 end
        let c = as(i32, p[i])
        if c == 93 then yield i + 1 end
        if c == 44 then jump ws_before_elem(i = i + 1, arr_idx = arr_idx) end
        yield -1
    end
    block ws_before_elem(i: i32, arr_idx: i32)
        if i >= n then yield -1 end
        switch as(i32, p[i]) do
        case 32 then jump ws_before_elem(i = i + 1, arr_idx = arr_idx)
        case 10 then jump ws_before_elem(i = i + 1, arr_idx = arr_idx)
        case 13 then jump ws_before_elem(i = i + 1, arr_idx = arr_idx)
        case 9  then jump ws_before_elem(i = i + 1, arr_idx = arr_idx)
        default then jump parse_elem(i = i, arr_idx = arr_idx)
        end
        jump parse_elem(i = i, arr_idx = arr_idx)
    end
    end
end]]

local parse_object = moon.func [[func parse_object(L: ptr(u8), p: ptr(u8), n: i32, pos: i32, buf: ptr(u8)) -> i32
    return region -> i32
    entry start()
        lua_createtable(L, 0, 16)
        emit skip_ws(p, n, pos + 1; ok = check_empty)
    end
    block check_empty(i: i32)
        if i >= n then yield -1 end
        if as(i32, p[i]) == 125 then yield i + 1 end
        jump parse_key(i = i)
    end
    block parse_key(i: i32)
        if as(i32, p[i]) ~= 34 then yield -1 end
        emit parse_string(L, p, n, i, buf; ok = check_colon, err = fail)
    end
    block check_colon(next_i: i32)
        emit skip_ws(p, n, next_i; ok = check_colon_char)
    end
    block check_colon_char(i: i32)
        if i >= n then yield -1 end
        if as(i32, p[i]) ~= 58 then yield -1 end
        emit skip_ws(p, n, i + 1; ok = parse_val)
    end
    block parse_val(i: i32)
        let after_val = parse_value(L, p, n, i, buf)
        if after_val < 0 then yield -1 end
        lua_settable(L, -3)
        emit skip_ws(p, n, after_val; ok = check_comma)
    end
    block check_comma(i: i32)
        if i >= n then yield -1 end
        let c = as(i32, p[i])
        if c == 125 then yield i + 1 end
        if c == 44 then emit skip_ws(p, n, i + 1; ok = parse_key) end
        yield -1
    end
    block fail()
        yield -1
    end
    end
end]]

-- Build literal switch arms as Moonlift source text via string concatenation.
-- This avoids the expander thunk issue with the values binder.
local function literal_arm_src(text, push_src)
    local bytes = { text:byte(1, #text) }
    local lines = {}
    lines[#lines + 1] = "case " .. bytes[1] .. " then"
    lines[#lines + 1] = ("    if i + %d > n then jump fail() end"):format(#bytes)
    for off = 2, #bytes do
        lines[#lines + 1] = ("    if as(i32, p[i + %d]) ~= %d then jump fail() end"):format(off - 1, bytes[off])
    end
    lines[#lines + 1] = "    " .. push_src
    lines[#lines + 1] = ("    jump done(next_i = i + %d)"):format(#bytes)
    return table.concat(lines, "\n")
end

local literal_arms_src = {
    literal_arm_src("true",  "lua_pushboolean(L, 1)"),
    literal_arm_src("false", "lua_pushboolean(L, 0)"),
    literal_arm_src("null",  "lua_pushnil(L)"),
}

local parse_value_src = [[func parse_value(L: ptr(u8), p: ptr(u8), n: i32, pos: i32, buf: ptr(u8)) -> i32
    return region -> i32
    entry start()
        emit skip_ws(p, n, pos; ok = dispatch)
    end
    block dispatch(i: i32)
        if i >= n then yield -1 end
        switch as(i32, p[i]) do
]] .. table.concat(literal_arms_src, "\n") .. [[
        case 34 then emit parse_string(L, p, n, i, buf; ok = done, err = fail)
        case 91 then
            let next_i = parse_array(L, p, n, i, buf)
            if next_i < 0 then jump fail() end
            jump done(next_i = next_i)
        case 123 then
            let next_i = parse_object(L, p, n, i, buf)
            if next_i < 0 then jump fail() end
            jump done(next_i = next_i)
        default then
            emit parse_number(L, p, n, i; ok = done, err = fail)
        end
        jump fail()
    end
    block done(next_i: i32)
        yield next_i
    end
    block fail()
        yield -1
    end
    end
end]]

local parse_value = moon.func(parse_value_src)

local decode_json_to_lua_stack = moon.func [[func decode_json_to_lua_stack(L: ptr(u8), p: ptr(u8), n: i32, buf: ptr(u8)) -> i32
    return region -> i32
    entry start()
        let after_value = parse_value(L, p, n, 0, buf)
        if after_value < 0 then yield -1 end
        emit skip_ws(p, n, after_value; ok = finish)
    end
    block finish(i: i32)
        if i == n then yield i end
        yield -1
    end
    end
end]]

-- ---------------------------------------------------------------------------
-- Execution test
-- ---------------------------------------------------------------------------

local module = moon.module("json_lua_stack_decoder")
module:add_func(lua_createtable)
module:add_func(lua_pushlstring)
module:add_func(lua_pushnumber)
module:add_func(lua_pushboolean)
module:add_func(lua_pushnil)
module:add_func(lua_settable)
module:add_func(lua_rawseti)
module:add_region(skip_ws)
module:add_region(parse_string)
module:add_region(parse_number)
module:add_func(parse_array)
module:add_func(parse_object)
module:add_func(parse_value)
module:add_func(decode_json_to_lua_stack)
local compiled_module = module:compile()
local compiled = compiled_module:get("decode_json_to_lua_stack")

local function decode_into_new_state(json)
    local C = ffi.C
    local L = C.luaL_newstate()
    local p = ffi.cast("uint8_t *", json)
    local buf = ffi.new("uint8_t[?]", #json + 1)
    local parsed_end = compiled(L, p, #json, buf)
    return L, parsed_end
end

local function close(L) ffi.C.lua_close(L) end

local L, parsed = decode_into_new_state("[true,false,null,42]")
assert(parsed == 20)
assert(ffi.C.lua_gettop(L) == 1)
assert(ffi.C.lua_type(L, 1) == 5)
assert(ffi.C.lua_objlen(L, 1) == 4)
close(L)

L, parsed = decode_into_new_state('"hello"')
assert(parsed == 7)
assert(ffi.C.lua_type(L, 1) == 4)
local lenp = ffi.new("size_t[1]")
local s = ffi.C.lua_tolstring(L, 1, lenp)
assert(tonumber(lenp[0]) == 5)
assert(ffi.string(s, lenp[0]) == "hello")
close(L)

L, parsed = decode_into_new_state('{"a":1}')
assert(parsed > 0)
assert(ffi.C.lua_gettop(L) == 1)
assert(ffi.C.lua_type(L, 1) == 5)
close(L)

L, parsed = decode_into_new_state('{"features":["Splices","Regions","ASDL"]}')
assert(parsed > 0)
assert(ffi.C.lua_gettop(L) == 1)
assert(ffi.C.lua_type(L, 1) == 5)
close(L)

L, parsed = decode_into_new_state([[{"name":"Moonlift","fast":true,"version":2.0,"features":["Splices","Regions","ASDL"],"overhead":null}]])
assert(parsed > 0)
assert(ffi.C.lua_gettop(L) == 1)
assert(ffi.C.lua_type(L, 1) == 5)
close(L)

for _, bad in ipairs({ "", "tru", "[1,]", "{", "+1", "01", '"unclosed' }) do
    L, parsed = decode_into_new_state(bad)
    assert(parsed < 0, "expected invalid JSON: " .. bad)
    close(L)
end

L, parsed = decode_into_new_state('"he\\\\llo"')
assert(parsed > 0)
s = ffi.C.lua_tolstring(L, 1, lenp)
assert(ffi.string(s, tonumber(lenp[0])) == "he\\llo")
close(L)

L, parsed = decode_into_new_state('"line1\\nline2"')
assert(parsed > 0)
s = ffi.C.lua_tolstring(L, 1, lenp)
assert(ffi.string(s, tonumber(lenp[0])) == "line1\nline2")
close(L)

L, parsed = decode_into_new_state('"tab\\there"')
assert(parsed > 0)
s = ffi.C.lua_tolstring(L, 1, lenp)
assert(ffi.string(s, tonumber(lenp[0])) == "tab\there")
close(L)

L, parsed = decode_into_new_state('"quote\\"inside"')
assert(parsed > 0)
s = ffi.C.lua_tolstring(L, 1, lenp)
assert(ffi.string(s, tonumber(lenp[0])) == 'quote"inside')
close(L)

L, parsed = decode_into_new_state('"\\u0041\\u0042\\u0043"')
assert(parsed > 0)
s = ffi.C.lua_tolstring(L, 1, lenp)
assert(ffi.string(s, tonumber(lenp[0])) == "ABC")
close(L)

L, parsed = decode_into_new_state('"\\uD83D\\uDE00"')
assert(parsed > 0)
s = ffi.C.lua_tolstring(L, 1, lenp)
assert(tonumber(lenp[0]) == 4)
assert(string.byte(ffi.string(s, 4), 1) == 0xF0)
close(L)

compiled_module:free()
print("Moonlift Lua-stack JSON decoder ok")
return "Moonlift Lua-stack JSON decoder ok"
