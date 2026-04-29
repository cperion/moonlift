-- Moonlift streaming JSON numeric-array scan vs lua-cjson decode.
--
-- This is a deliberately narrow JSON POC: it parses/sums a top-level array of
-- signed base-10 i32 numbers and ignores structural whitespace/brackets/commas.
-- It does not build a Lua table.  The point is to test whether Moonlift's
-- block+jump control form can express a fast byte scanner.

package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./third_party/lua-cjson/?.lua;" .. package.path
package.cpath = "./.luarocks/lib64/lua/5.1/?.so;./third_party/lua-cjson/?.so;./third_party/lua-cjson/?.dll;" .. package.cpath

local ffi = require("ffi")
local cjson = require("cjson")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Parse = require("moonlift.parse")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local Validate = require("moonlift.back_validate")
local J = require("moonlift.back_jit")

local mode = arg and arg[1] or "quick"
local quick = mode == "quick"
local COUNT = tonumber(os.getenv("MOONLIFT2_JSON_COUNT") or (quick and "10000" or "200000"))
local WARMUP = tonumber(os.getenv("MOONLIFT2_JSON_WARMUP") or (quick and "1" or "2"))
local ITERS = tonumber(os.getenv("MOONLIFT2_JSON_ITERS") or (quick and "5" or "7"))

local SRC = [[
export func json_sum_i32_array(p: ptr(u8), n: i32) -> i32
    return control -> i32
    block scan(i: i32 = 0, acc: i32 = 0, value: i32 = 0, in_num: i32 = 0, sign: i32 = 1)
        if i >= n then
            jump finish(acc = acc, value = value, in_num = in_num, sign = sign)
        end
        jump classify(i = i, acc = acc, value = value, in_num = in_num, sign = sign, c = as(i32, p[i]))
    end
    block classify(i: i32, acc: i32, value: i32, in_num: i32, sign: i32, c: i32)
        if c >= 48 then
            jump maybe_digit(i = i, acc = acc, value = value, in_num = in_num, sign = sign, c = c)
        end
        jump maybe_minus(i = i, acc = acc, value = value, in_num = in_num, sign = sign, c = c)
    end
    block maybe_digit(i: i32, acc: i32, value: i32, in_num: i32, sign: i32, c: i32)
        if c <= 57 then
            jump scan(i = i + 1, acc = acc, value = value * 10 + (c - 48), in_num = 1, sign = sign)
        end
        jump maybe_minus(i = i, acc = acc, value = value, in_num = in_num, sign = sign, c = c)
    end
    block maybe_minus(i: i32, acc: i32, value: i32, in_num: i32, sign: i32, c: i32)
        if c == 45 then
            jump scan(i = i + 1, acc = acc, value = 0, in_num = 1, sign = -1)
        end
        jump maybe_commit(i = i, acc = acc, value = value, in_num = in_num, sign = sign)
    end
    block maybe_commit(i: i32, acc: i32, value: i32, in_num: i32, sign: i32)
        if in_num ~= 0 then
            jump commit(i = i, acc = acc, value = value, sign = sign)
        end
        jump reset(i = i, acc = acc)
    end
    block commit(i: i32, acc: i32, value: i32, sign: i32)
        jump scan(i = i + 1, acc = acc + value * sign, value = 0, in_num = 0, sign = 1)
    end
    block reset(i: i32, acc: i32)
        jump scan(i = i + 1, acc = acc, value = 0, in_num = 0, sign = 1)
    end
    block finish(acc: i32, value: i32, in_num: i32, sign: i32)
        if in_num ~= 0 then
            yield acc + value * sign
        end
        yield acc
    end
    end
end
]]

local function build_json(count)
    local parts = { "[" }
    local expected = 0
    for i = 1, count do
        local v = (i * 17 + 3) % 1009
        if i % 11 == 0 then v = -v end
        expected = expected + v
        if i > 1 then parts[#parts + 1] = "," end
        parts[#parts + 1] = tostring(v)
    end
    parts[#parts + 1] = "]"
    return table.concat(parts), expected
end

local function best_of(f, ...)
    for _ = 1, WARMUP do f(...) end
    local best, result = math.huge, nil
    for _ = 1, ITERS do
        collectgarbage("collect")
        local t0 = os.clock()
        result = f(...)
        local dt = os.clock() - t0
        if dt < best then best = dt end
    end
    return best, result
end

local T = pvm.context()
A2.Define(T)
local P = Parse.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local V = Validate.Define(T)
local jit_api = J.Define(T)
local B2 = T.Moon2Back

local compile_start = os.clock()
local parsed = P.parse_module(SRC)
if #parsed.issues ~= 0 then
    for i = 1, #parsed.issues do
        local issue = parsed.issues[i]
        io.stderr:write(string.format("parse issue %d:%d: %s\n", issue.line, issue.col, issue.message))
    end
end
assert(#parsed.issues == 0, "parse issues: " .. #parsed.issues)
local checked = TC.check_module(parsed.module)
if #checked.issues ~= 0 then
    for i = 1, #checked.issues do io.stderr:write(tostring(checked.issues[i]) .. "\n") end
end
assert(#checked.issues == 0, "type issues: " .. #checked.issues)
local program = Lower.module(checked.module)
local report = V.validate(program)
assert(#report.issues == 0, "back validation issues: " .. #report.issues)
local artifact = jit_api.jit():compile(program)
local compile_time = os.clock() - compile_start

local json_sum = ffi.cast("int32_t (*)(const uint8_t*, int32_t)", artifact:getpointer(B2.BackFuncId("json_sum_i32_array")))

local src, expected = build_json(COUNT)
local buf = ffi.new("uint8_t[?]", #src)
ffi.copy(buf, src, #src)
assert(json_sum(buf, #src) == expected)

local function cjson_decode_only(s)
    return #cjson.decode(s)
end

local function cjson_decode_sum(s)
    local values = cjson.decode(s)
    local acc = 0
    for i = 1, #values do acc = acc + values[i] end
    return acc
end

assert(cjson_decode_only(src) == COUNT)
assert(cjson_decode_sum(src) == expected)

local moon_t, moon_result = best_of(json_sum, buf, #src)
local cjson_decode_t, cjson_decode_result = best_of(cjson_decode_only, src)
local cjson_t, cjson_result = best_of(cjson_decode_sum, src)

io.write(string.format("json_count %d bytes %d expected %d\n", COUNT, #src, expected))
io.write(string.format("moonlift_json_compile %.9f 0\n", compile_time))
io.write(string.format("moonlift_json_sum_i32 %.9f %d\n", moon_t, moon_result))
io.write(string.format("cjson_decode_only %.9f %d\n", cjson_decode_t, cjson_decode_result))
io.write(string.format("cjson_decode_sum_i32 %.9f %d\n", cjson_t, cjson_result))
io.write(string.format("ratio_moonlift_vs_cjson_decode %.3f\n", moon_t / cjson_decode_t))
io.write(string.format("ratio_moonlift_vs_cjson_sum %.3f\n", moon_t / cjson_t))

artifact:free()
