package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

local parse_abc_fn = Host.eval [[
local match_a = region(p: ptr(u8), n: i32, pos: i32;
                       ok: cont(next: i32), err: cont(errpos: i32, code: i32))
entry start()
    if pos >= n then jump err(errpos = pos, code = 1) end
    if as(i32, p[pos]) == 97 then jump ok(next = pos + 1) end
    jump err(errpos = pos, code = 2)
end
end

local match_b = region(p: ptr(u8), n: i32, pos: i32;
                       ok: cont(next: i32), err: cont(errpos: i32, code: i32))
entry start()
    if pos >= n then jump err(errpos = pos, code = 1) end
    if as(i32, p[pos]) == 98 then jump ok(next = pos + 1) end
    jump err(errpos = pos, code = 2)
end
end

local match_c = region(p: ptr(u8), n: i32, pos: i32;
                       ok: cont(next: i32), err: cont(errpos: i32, code: i32))
entry start()
    if pos >= n then jump err(errpos = pos, code = 1) end
    if as(i32, p[pos]) == 99 then jump ok(next = pos + 1) end
    jump err(errpos = pos, code = 2)
end
end

local parse_abc = func(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit @{match_a}(p, n, 0; ok = got_a, err = fail)
    end
    block got_a(next: i32)
        emit @{match_b}(p, n, next; ok = got_b, err = fail)
    end
    block got_b(next: i32)
        emit @{match_c}(p, n, next; ok = got_c, err = fail)
    end
    block got_c(next: i32)
        yield next
    end
    block fail(errpos: i32, code: i32)
        yield 0 - code
    end
    end
end
return parse_abc
]]

local c_parse = parse_abc_fn:compile()

-- ONE_OR_MORE: also inline
local parse_xs_fn = Host.eval [[
local match_x = region(p: ptr(u8), n: i32, pos: i32;
                       ok: cont(next: i32), err: cont(errpos: i32, code: i32))
entry start()
    if pos >= n then jump err(errpos = pos, code = 1) end
    if as(i32, p[pos]) == 120 then jump ok(next = pos + 1) end
    jump err(errpos = pos, code = 2)
end
end

local parse_xs = func(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit @{match_x}(p, n, 0; ok = more, err = fail)
    end
    block more(next: i32)
        emit @{match_x}(p, n, next; ok = more, err = done)
    end
    block done(errpos: i32, code: i32)
        yield errpos
    end
    block fail(errpos: i32, code: i32)
        yield 0 - code
    end
    end
end
return parse_xs
]]

local c_one_or_more = parse_xs_fn:compile()

-- Digit parser
local parse_digit_fn = Host.eval [[
local match_digit = region(p: ptr(u8), n: i32, pos: i32;
                            ok: cont(next: i32, value: i32),
                            err: cont(errpos: i32, code: i32))
entry start()
    if pos >= n then jump err(errpos = pos, code = 1) end
    let c: i32 = as(i32, p[pos])
    if c >= 48 then
        if c <= 57 then
            jump ok(next = pos + 1, value = c - 48)
        end
    end
    jump err(errpos = pos, code = 2)
end
end

local parse_digit = func(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit @{match_digit}(p, n, 0; ok = got, err = fail)
    end
    block got(next: i32, value: i32)
        yield value
    end
    block fail(errpos: i32, code: i32)
        yield 0 - code
    end
    end
end
return parse_digit
]]

local c_digit = parse_digit_fn:compile()

-- Two-digit: sequential emit accumulating result through block params
local parse_two_fn = Host.eval [[
local match_digit = region(p: ptr(u8), n: i32, pos: i32;
                            ok: cont(next: i32, value: i32),
                            err: cont(errpos: i32, code: i32))
entry start()
    if pos >= n then jump err(errpos = pos, code = 1) end
    let c: i32 = as(i32, p[pos])
    if c >= 48 then
        if c <= 57 then
            jump ok(next = pos + 1, value = c - 48)
        end
    end
    jump err(errpos = pos, code = 2)
end
end

local parse_two = func(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit @{match_digit}(p, n, 0; ok = first, err = fail)
    end
    block first(next: i32, value: i32)
        emit @{match_digit}(p, n, next; ok = second, err = fail)
    end
    block second(next: i32, value: i32)
        yield next
    end
    block fail(errpos: i32, code: i32)
        yield 0 - code
    end
    end
end
return parse_two
]]

local c_two = parse_two_fn:compile()

-- Tests
local function buf(s)
    local b = ffi.new("uint8_t[?]", #s)
    ffi.copy(b, s, #s)
    return b, #s
end

do
    local b, n = buf("abcdef")
    assert(c_parse(b, n) == 3, "abc at start")
    print("parse abc @ 'abcdef' = 3 ✓")
end
do
    local b, n = buf("abxdef")
    assert(c_parse(b, n) == -2, "fail at x")
    print("parse abc @ 'abxdef' = -2 ✓")
end
do
    local b, n = buf("a")
    assert(c_parse(b, n) == -1, "eof")
    print("parse abc @ 'a'      = -1 ✓")
end
do
    local b, n = buf("xxxxyz")
    local r = c_one_or_more(b, n)
    assert(r == 4, "4 x's, got " .. tostring(r))
    print("one_or_more x @ 'xxxxyz' = 4 ✓")
end
do
    local b, n = buf("yz")
    assert(c_one_or_more(b, n) == -2, "no x at start")
    print("one_or_more x @ 'yz'   = -2 ✓")
end
do
    local b, n = buf("7")
    assert(c_digit(b, n) == 7, "digit 7")
    print("parse digit @ '7'     = 7  ✓")
end
do
    local b, n = buf("z")
    assert(c_digit(b, n) == -2, "not a digit")
    print("parse digit @ 'z'     = -2 ✓")
end
do
    local b, n = buf("42xx")
    local r = c_two(b, n)
    assert(r == 2, "two-digit 42, expect pos 2 (after both digits), got " .. tostring(r))
    print("parse two-digit @ '42xx' = 2 ✓")
end

c_parse:free()
c_one_or_more:free()
c_digit:free()
c_two:free()
print("\n=== combinator ===")


