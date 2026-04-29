package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.host_quote")

local function u8buf(s)
    local buf = ffi.new("uint8_t[?]", #s)
    ffi.copy(buf, s, #s)
    return buf, #s
end

-- Pattern 1: scanner fragment with success/failure continuations.
-- The caller decides what success/failure mean; the fragment only routes control.
local scanner_mod = Host.eval [[
local scan_until = region scan_until(p: ptr(u8), n: i32, target: i32; hit: cont(pos: i32), miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end

return module
export func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32
    entry start()
        emit scan_until(p, n, target; hit = found, miss = missing)
    end
    block found(pos: i32)
        yield pos
    end
    block missing(pos: i32)
        yield -1
    end
    end
end

export func prefix_len_or_all(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32
    entry start()
        emit scan_until(p, n, target; hit = found, miss = missing)
    end
    block found(pos: i32)
        yield pos
    end
    block missing(pos: i32)
        yield pos
    end
    end
end
end
]]

local scanner = scanner_mod:compile()
local buf, n = u8buf("abc-def")
assert(scanner:get("find_byte")(buf, n, string.byte("-")) == 3)
assert(scanner:get("find_byte")(buf, n, string.byte("z")) == -1)
assert(scanner:get("prefix_len_or_all")(buf, n, string.byte("-")) == 3)
assert(scanner:get("prefix_len_or_all")(buf, n, string.byte("z")) == n)
scanner:free()

-- Pattern 2: parser combinator style. A digit parser fragment returns a new
-- parse position and accumulator through a continuation. The consumer composes
-- it twice without runtime callbacks.
local parse_mod = Host.eval [[
local parse_digit_acc = region parse_digit_acc(p: ptr(u8), n: i32, pos: i32, acc: i32; ok: cont(pos2: i32, acc: i32), err: cont(errpos: i32, code: i32))
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

local parse_two_digits = func parse_two_digits(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit parse_digit_acc(p, n, 0, 0; ok = got_one, err = bad1)
    end
    block got_one(pos2: i32, acc: i32)
        emit parse_digit_acc(p, n, pos2, acc; ok = done, err = bad2)
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

local parse_two_digits = parse_mod:compile()
local b12, n12 = u8buf("42xx")
local bbad, nbad = u8buf("4axx")
assert(parse_two_digits(b12, n12) == 42)
assert(parse_two_digits(bbad, nbad) == -2)
parse_two_digits:free()

-- Pattern 3: reducer fragment. Internal loop state is hidden in the fragment;
-- the caller only receives typed exits.
local reduce_mod = Host.eval [[
local sum_until = region sum_until(p: ptr(u8), n: i32, sentinel: i32; done: cont(sum: i32, pos: i32), eof: cont(pos: i32))
entry loop(i: i32 = 0, sum: i32 = 0)
    if i >= n then jump eof(pos = i) end
    let v: i32 = as(i32, p[i])
    if v == sentinel then jump done(sum = sum, pos = i) end
    jump loop(i = i + 1, sum = sum + v)
end
end

local sum_before_byte = func sum_before_byte(p: ptr(u8), n: i32, sentinel: i32) -> i32
    return region -> i32
    entry start()
        emit sum_until(p, n, sentinel; done = found, eof = missing)
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

local sum_before_byte = reduce_mod:compile()
local bsum, nsum = u8buf(string.char(1, 2, 3, 255, 9))
assert(sum_before_byte(bsum, nsum, 255) == 6)
assert(sum_before_byte(bsum, nsum, 7) == -1)
sum_before_byte:free()

-- Pattern 4: expression fragments are staged scalar combinators and can be used
-- inside continuation-region code.
local expr_mod = Host.eval [[
local clamp_nonneg = expr clamp_nonneg(x: i32) -> i32
    select(x < 0, 0, x)
end

local score_scan = region score_scan(p: ptr(u8), n: i32; done: cont(score: i32))
entry loop(i: i32 = 0, score: i32 = 0)
    if i >= n then jump done(score = score) end
    let v: i32 = as(i32, p[i]) - 50
    jump loop(i = i + 1, score = score + emit clamp_nonneg(v))
end
end

local score = func score(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit score_scan(p, n; done = out)
    end
    block out(score: i32)
        yield score
    end
    end
end

return score
]]

local score = expr_mod:compile()
local bscore, nscore = u8buf(string.char(40, 50, 52, 60))
assert(score(bscore, nscore) == 12)
score:free()

print("moonlift host patterns ok")
