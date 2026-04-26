package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.host_quote")

local function u8buf(s)
    local buf = ffi.new("uint8_t[?]", #s)
    ffi.copy(buf, s, #s)
    return buf, #s
end

-- Host Lua manufactures distinct fragment names and constants.  The generated
-- object-language primitive is still a typed continuation region.
local byte_patterns = Host.eval [[
local function expect_byte(tag, byte, err_code)
    return region expect_@{tag}(p: ptr(u8), pos: i32; ok: cont(next: i32), fail: cont(pos: i32, code: i32))
    entry start()
        if zext<i32>(p[pos]) == @{byte} then
            jump ok(next = pos + 1)
        end
        jump fail(pos = pos, code = @{err_code})
    end
    end
end

local expect_A = expect_byte(65, 65, 10)
local expect_B = expect_byte(66, 66, 20)
local expect_C = expect_byte(67, 67, 30)

return module
export func parse_ABC(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit @{expect_A}(p, 0; ok = got_A, fail = bad_A)
    end
    block got_A(next: i32)
        emit @{expect_B}(p, next; ok = got_B, fail = bad_B)
    end
    block got_B(next: i32)
        emit @{expect_C}(p, next; ok = done, fail = bad_C)
    end
    block done(next: i32)
        yield next
    end
    block bad_A(pos: i32, code: i32)
        yield 0 - code
    end
    block bad_B(pos: i32, code: i32)
        yield 0 - code
    end
    block bad_C(pos: i32, code: i32)
        yield 0 - code
    end
    end
end

export func parse_A_or_B(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit @{expect_A}(p, 0; ok = done, fail = try_B)
    end
    block try_B(pos: i32, code: i32)
        emit @{expect_B}(p, 0; ok = done, fail = bad)
    end
    block done(next: i32)
        yield next
    end
    block bad(pos: i32, code: i32)
        yield 0 - code
    end
    end
end
end
]]

local bm = byte_patterns:compile()
local abc, nabc = u8buf("ABC")
local axc, naxc = u8buf("AXC")
local zzz, nzzz = u8buf("ZZZ")
local bbb, nbbb = u8buf("BBB")
assert(bm:get("parse_ABC")(abc, nabc) == 3)
assert(bm:get("parse_ABC")(axc, naxc) == -20)
assert(bm:get("parse_ABC")(zzz, nzzz) == -10)
assert(bm:get("parse_A_or_B")(abc, nabc) == 1)
assert(bm:get("parse_A_or_B")(bbb, nbbb) == 1)
assert(bm:get("parse_A_or_B")(zzz, nzzz) == -20)
bm:free()

-- Host-generated expression fragments can be specialized by constants and then
-- used inside region loops.
local score_patterns = Host.eval [[
local function positive_after(tag, pivot)
    return expr positive_after_@{tag}(x: i32) -> i32
        select(x > @{pivot}, x - @{pivot}, 0)
    end
end

local score_after_50 = positive_after(50, 50)
local score_after_60 = positive_after(60, 60)

local scan_score = region scan_score(p: ptr(u8), n: i32; done: cont(a: i32, b: i32))
entry loop(i: i32 = 0, a: i32 = 0, b: i32 = 0)
    if i >= n then jump done(a = a, b = b) end
    let v: i32 = zext<i32>(p[i])
    jump loop(i = i + 1, a = a + emit @{score_after_50}(v), b = b + emit @{score_after_60}(v))
end
end

local score_pair = func score_pair(p: ptr(u8), n: i32) -> i32
    return region -> i32
    entry start()
        emit scan_score(p, n; done = out)
    end
    block out(a: i32, b: i32)
        yield a * 100 + b
    end
    end
end

return score_pair
]]

local score_pair = score_patterns:compile()
local bs, ns = u8buf(string.char(40, 55, 65))
-- score_after_50: 0 + 5 + 15 = 20; score_after_60: 0 + 0 + 5 = 5
assert(score_pair(bs, ns) == 2005)
score_pair:free()

-- Continuation adapters: the fragment reports rich exits, while the caller
-- adapts them into a compact return convention.
local adapter_patterns = Host.eval [[
local classify_byte = region classify_byte(p: ptr(u8), pos: i32; digit: cont(value: i32), alpha: cont(value: i32), other: cont(value: i32))
entry start()
    let c: i32 = zext<i32>(p[pos])
    if c >= 48 then
        if c <= 57 then jump digit(value = c - 48) end
    end
    if c >= 65 then
        if c <= 90 then jump alpha(value = c - 65) end
    end
    jump other(value = c)
end
end

local compact_class = func compact_class(p: ptr(u8)) -> i32
    return region -> i32
    entry start()
        emit classify_byte(p, 0; digit = d, alpha = a, other = o)
    end
    block d(value: i32)
        yield value
    end
    block a(value: i32)
        yield 100 + value
    end
    block o(value: i32)
        yield 1000 + value
    end
    end
end

return compact_class
]]

local compact_class = adapter_patterns:compile()
local bd = u8buf("7")
local ba = u8buf("C")
local bo = u8buf("!")
assert(compact_class(bd) == 7)
assert(compact_class(ba) == 102)
assert(compact_class(bo) == 1033)
compact_class:free()

print("moonlift host metaprogramming patterns ok")
