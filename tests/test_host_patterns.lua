package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

local function u8buf(s)
    local buf = ffi.new("uint8_t[?]", #s)
    ffi.copy(buf, s, #s)
    return buf, #s
end

-- Pattern 1: scanner fragment with success/failure continuations.
-- The caller decides what success/failure mean; the fragment only routes control.
local scan_until = Host.eval [[
local scan_until = region(p: ptr(u8), n: i32, target: i32; hit: cont(pos: i32), miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end

return scan_until
]]

local find_byte = Host.eval [[
local scan_until = region(p: ptr(u8), n: i32, target: i32; hit: cont(pos: i32), miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end

local find_byte = func(p: ptr(u8), n: i32, target: i32): i32
    return region: i32
    entry start()
        emit @{scan_until}(p, n, target; hit = found, miss = missing)
    end
    block found(pos: i32)
        yield pos
    end
    block missing(pos: i32)
        yield -1
    end
    end
end

return find_byte
]]

local prefix_len_or_all = Host.eval [[
local scan_until = region(p: ptr(u8), n: i32, target: i32; hit: cont(pos: i32), miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end

local prefix_len_or_all = func(p: ptr(u8), n: i32, target: i32): i32
    return region: i32
    entry start()
        emit @{scan_until}(p, n, target; hit = found, miss = missing)
    end
    block found(pos: i32)
        yield pos
    end
    block missing(pos: i32)
        yield pos
    end
    end
end

return prefix_len_or_all
]]

local c_find = find_byte:compile()
local c_prefix = prefix_len_or_all:compile()
local buf, n = u8buf("abc-def")
assert(c_find(buf, n, string.byte("-")) == 3)
assert(c_find(buf, n, string.byte("z")) == -1)
assert(c_prefix(buf, n, string.byte("-")) == 3)
assert(c_prefix(buf, n, string.byte("z")) == n)
c_find:free()
c_prefix:free()

-- Pattern 2: parser combinator style. A digit parser fragment returns a new
-- parse position and accumulator through a continuation. The consumer composes
-- it twice without runtime callbacks.
local parse_two_digits = Host.eval [[
local parse_digit_acc = region(p: ptr(u8), n: i32, pos: i32, acc: i32; ok: cont(pos2: i32, acc: i32), err: cont(errpos: i32, code: i32))
entry start()
    let c: i32 = as(i32, p[pos])
    if c >= 48 then
        if c <= 57 then
            jump ok(pos2 = pos + 1, acc = acc * 10 + c - 48)
        end
    end
    jump err(errpos = pos, code = 2)
end
end

local parse_two_digits = func(p: ptr(u8), n: i32): i32
    return region: i32
    entry start()
        emit @{parse_digit_acc}(p, n, 0, 0; ok = got_one, err = bad1)
    end
    block got_one(pos2: i32, acc: i32)
        emit @{parse_digit_acc}(p, n, pos2, acc; ok = done, err = bad2)
    end
    block done(pos2: i32, acc: i32)
        yield acc
    end
    block bad1(errpos: i32, code: i32)
        yield 0 - code
    end
    block bad2(errpos: i32, code: i32)
        yield 0 - code
    end
    end
end

return parse_two_digits
]]

local c_parse = parse_two_digits:compile()
local b12, n12 = u8buf("42xx")
local bbad, nbad = u8buf("4axx")
assert(c_parse(b12, n12) == 42)
assert(c_parse(bbad, nbad) == -2)
c_parse:free()

-- Pattern 3: reducer fragment. Internal loop state is hidden in the fragment;
-- the caller only receives typed exits.
local sum_before_byte = Host.eval [[
local sum_until = region(p: ptr(u8), n: i32, sentinel: i32; done: cont(sum: i32, pos: i32), eof: cont(pos: i32))
entry loop(i: i32 = 0, sum: i32 = 0)
    if i >= n then jump eof(pos = i) end
    let v: i32 = as(i32, p[i])
    if v == sentinel then jump done(sum = sum, pos = i) end
    jump loop(i = i + 1, sum = sum + v)
end
end

local sum_before_byte = func(p: ptr(u8), n: i32, sentinel: i32): i32
    return region: i32
    entry start()
        emit @{sum_until}(p, n, sentinel; done = found, eof = missing)
    end
    block found(sum: i32, pos: i32)
        yield sum
    end
    block missing(pos: i32)
        yield -1
    end
    end
end

return sum_before_byte
]]

local c_sum = sum_before_byte:compile()
local bsum, nsum = u8buf(string.char(1, 2, 3, 255, 9))
assert(c_sum(bsum, nsum, 255) == 6)
assert(c_sum(bsum, nsum, 7) == -1)
c_sum:free()

-- Pattern 4: expression fragments are staged scalar combinators and can be used
-- inside continuation-region code.
local score = Host.eval [[
local clamp_nonneg = expr(x: i32): i32
    select(x < 0, 0, x)
end

local score_scan = region(p: ptr(u8), n: i32; done: cont(score: i32))
entry loop(i: i32 = 0, score: i32 = 0)
    if i >= n then jump done(score = score) end
    let v: i32 = as(i32, p[i]) - 50
    jump loop(i = i + 1, score = score + emit @{clamp_nonneg}(v))
end
end

local score = func(p: ptr(u8), n: i32): i32
    return region: i32
    entry start()
        emit @{score_scan}(p, n; done = out)
    end
    block out(score: i32)
        yield score
    end
    end
end

return score
]]

local c_score = score:compile()
local bscore, nscore = u8buf(string.char(40, 50, 52, 60))
assert(c_score(bscore, nscore) == 12)
c_score:free()

print("moonlift host patterns ok")
