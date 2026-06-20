-- Lua Interpreter VM — Value protocol regions (Lua 5.5)
-- Value dispatch: truth, type checks, integer/float split, comparisons.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

-- value_truth: TAG_NIL or TAG_FALSE → falsey, else truthy
local value_truth = host.region { TAG_NIL = I.TAG_NIL, TAG_FALSE = I.TAG_FALSE } [[
region value_truth(v: Value; truthy | falsey)

entry start()
    if v.tag == @{TAG_NIL} or v.tag == @{TAG_FALSE} then
        jump falsey()
    end
    jump truthy()
end
end
]]

-- value_as_integer: check TAG_INTEGER
local value_as_integer = host.region { TAG_INTEGER = I.TAG_INTEGER } [[
region value_as_integer(v: Value; integer(n: i64) | not_integer)

entry start()
    if v.tag == @{TAG_INTEGER} then
        jump integer(n = as(i64, v.bits))
    end
    jump not_integer()
end
end
]]

-- value_as_float: check TAG_NUM
local value_as_float = host.region { TAG_NUM = I.TAG_NUM } [[
region value_as_float(v: Value; float(n: f64) | not_float)

entry start()
    if v.tag == @{TAG_NUM} then
        jump float(n = bitcast(f64, v.bits))
    end
    jump not_float()
end
end
]]

-- value_to_number: dual-arm integer | float | not_number
local value_to_number = host.region { TAG_INTEGER = I.TAG_INTEGER, TAG_NUM = I.TAG_NUM } [[
region value_to_number(v: Value; integer(n: i64) | float(n: f64) | not_number)

entry start()
    if v.tag == @{TAG_INTEGER} then
        jump integer(n = as(i64, v.bits))
    end
    if v.tag == @{TAG_NUM} then
        jump float(n = bitcast(f64, v.bits))
    end
    jump not_number()
end
end
]]

-- value_as_string: check TAG_STR
local value_as_string = host.region { TAG_STR = I.TAG_STR } [[
region value_as_string(v: Value; string(s: ptr(String)) | not_string)

entry start()
    if v.tag == @{TAG_STR} then
        jump string(s = as(ptr(String), v.bits))
    end
    jump not_string()
end
end
]]

-- value_to_string: accepts strings. Number formatting requires allocation, rejected explicitly.
local value_to_string = host.region { TAG_STR = I.TAG_STR, ERR_RUNTIME = I.ERR_RUNTIME } [[
region value_to_string(L: ptr(LuaThread), v: Value; string(s: ptr(String)) | error(code: i32) | oom)

entry start()
    if v.tag == @{TAG_STR} then
        jump string(s = as(ptr(String), v.bits))
    end
    jump error(code = @{ERR_RUNTIME})
end
end
]]

-- value_as_table: check TAG_TABLE
local value_as_table = host.region { TAG_TABLE = I.TAG_TABLE } [[
region value_as_table(v: Value; table(t: ptr(Table)) | not_table)

entry start()
    if v.tag == @{TAG_TABLE} then
        jump table(t = as(ptr(Table), v.bits))
    end
    jump not_table()
end
end
]]

-- value_as_function: check TAG_LCLOSURE or TAG_CCLOSURE
local value_as_function = host.region { TAG_LCLOSURE = I.TAG_LCLOSURE, TAG_CCLOSURE = I.TAG_CCLOSURE } [[
region value_as_function(v: Value; lua(cl: ptr(LClosure)) | native(cl: ptr(CClosure)) | not_function)

entry start()
    if v.tag == @{TAG_LCLOSURE} then
        jump lua(cl = as(ptr(LClosure), v.bits))
    end
    if v.tag == @{TAG_CCLOSURE} then
        jump native(cl = as(ptr(CClosure), v.bits))
    end
    jump not_function()
end
end
]]

-- value_raw_equal: tag-based dispatch
-- Numbers: integer vs integer (exact i64 compare), float vs float (f64 compare).
-- Different tag = not equal (no int/float coercion in raw equality).
local value_raw_equal = host.region {
    TAG_NIL = I.TAG_NIL, TAG_FALSE = I.TAG_FALSE, TAG_TRUE = I.TAG_TRUE,
    TAG_INTEGER = I.TAG_INTEGER, TAG_NUM = I.TAG_NUM,
    TAG_STR = I.TAG_STR, TAG_LIGHTUD = I.TAG_LIGHTUD,
} [[
region value_raw_equal(a: Value, b: Value; equal | not_equal)

entry start()
    if a.tag == @{TAG_INTEGER} and b.tag == @{TAG_NUM} then
        if as(f64, as(i64, a.bits)) == bitcast(f64, b.bits) then jump equal() end
        jump not_equal()
    end
    if a.tag == @{TAG_NUM} and b.tag == @{TAG_INTEGER} then
        if bitcast(f64, a.bits) == as(f64, as(i64, b.bits)) then jump equal() end
        jump not_equal()
    end
    if a.tag ~= b.tag then jump not_equal() end
    switch a.tag do
    case 0 then jump equal()
    case 1 then jump equal()
    case 2 then jump equal()
    case 4 then
        if a.bits == b.bits then jump equal() end
        jump not_equal()
    case 5 then
        if bitcast(f64, a.bits) == bitcast(f64, b.bits) then
            jump equal()
        end
        jump not_equal()
    case 6 then
        if a.bits == b.bits then jump equal() end
        jump not_equal()
    case 3 then
        if a.bits == b.bits then jump equal() end
        jump not_equal()
    default then
        if a.bits == b.bits then jump equal() end
        jump not_equal()
    end
end
end
]]

-- value_equal: raw_equal, then primitive false for unequal values.
local value_equal = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
region value_equal(L: ptr(LuaThread), a: Value, b: Value; result(is_equal: bool) | call_mm(mm: Value) | error(code: i32) | oom)

entry try_raw()
    emit value_raw_equal(a, b; equal = yes, not_equal = check_meta)
end
block yes()
    jump result(is_equal = true)
end
block check_meta()
    jump result(is_equal = false)
end
end
]]

-- value_less_than: integer fast path, float fast path, string compare, else error
local value_less_than = host.region {
    TAG_INTEGER = I.TAG_INTEGER, TAG_NUM = I.TAG_NUM,
    TAG_STR = I.TAG_STR, ERR_COMPARE = I.ERR_COMPARE,
} [[
region value_less_than(L: ptr(LuaThread), a: Value, b: Value; result(is_lt: bool) | call_mm(mm: Value) | error(code: i32) | oom)

entry start()
    if a.tag == @{TAG_INTEGER} and b.tag == @{TAG_INTEGER} then
        jump result(is_lt = as(i64, a.bits) < as(i64, b.bits))
    end
    if a.tag == @{TAG_NUM} and b.tag == @{TAG_NUM} then
        jump result(is_lt = bitcast(f64, a.bits) < bitcast(f64, b.bits))
    end
    if a.tag == @{TAG_INTEGER} and b.tag == @{TAG_NUM} then
        jump result(is_lt = as(f64, as(i64, a.bits)) < bitcast(f64, b.bits))
    end
    if a.tag == @{TAG_NUM} and b.tag == @{TAG_INTEGER} then
        jump result(is_lt = bitcast(f64, a.bits) < as(f64, as(i64, b.bits)))
    end
    if a.tag == @{TAG_STR} and b.tag == @{TAG_STR} then
        let sa: ptr(String) = as(ptr(String), a.bits)
        let sb: ptr(String) = as(ptr(String), b.bits)
        jump str_loop(i = as(index, 0), sa = sa, sb = sb)
    end
    jump error(code = @{ERR_COMPARE})
end
block str_loop(i: index, sa: ptr(String), sb: ptr(String))
    if i >= sa.len or i >= sb.len then
        jump result(is_lt = sa.len < sb.len)
    end
    let ca: u8 = sa.bytes[i]
    let cb: u8 = sb.bytes[i]
    if ca < cb then jump result(is_lt = true) end
    if ca > cb then jump result(is_lt = false) end
    jump str_loop(i = i + 1, sa = sa, sb = sb)
end
end
]]

-- value_less_equal: integer fast path, float fast path, string compare, then error
local value_less_equal = host.region {
    TAG_INTEGER = I.TAG_INTEGER, TAG_NUM = I.TAG_NUM,
    TAG_STR = I.TAG_STR, ERR_COMPARE = I.ERR_COMPARE,
} [[
region value_less_equal(L: ptr(LuaThread), a: Value, b: Value; result(is_le: bool) | call_mm(mm: Value, fallback_lt: bool) | error(code: i32) | oom)

entry start()
    if a.tag == @{TAG_INTEGER} and b.tag == @{TAG_INTEGER} then
        jump result(is_le = as(i64, a.bits) <= as(i64, b.bits))
    end
    if a.tag == @{TAG_NUM} and b.tag == @{TAG_NUM} then
        jump result(is_le = bitcast(f64, a.bits) <= bitcast(f64, b.bits))
    end
    if a.tag == @{TAG_INTEGER} and b.tag == @{TAG_NUM} then
        jump result(is_le = as(f64, as(i64, a.bits)) <= bitcast(f64, b.bits))
    end
    if a.tag == @{TAG_NUM} and b.tag == @{TAG_INTEGER} then
        jump result(is_le = bitcast(f64, a.bits) <= as(f64, as(i64, b.bits)))
    end
    if a.tag == @{TAG_STR} and b.tag == @{TAG_STR} then
        let sa: ptr(String) = as(ptr(String), a.bits)
        let sb: ptr(String) = as(ptr(String), b.bits)
        jump str_le_loop(i = as(index, 0), sa = sa, sb = sb)
    end
    jump error(code = @{ERR_COMPARE})
end
block str_le_loop(i: index, sa: ptr(String), sb: ptr(String))
    if i >= sa.len or i >= sb.len then
        jump result(is_le = sa.len <= sb.len)
    end
    let ca: u8 = sa.bytes[i]
    let cb: u8 = sb.bytes[i]
    if ca < cb then jump result(is_le = true) end
    if ca > cb then jump result(is_le = false) end
    jump str_le_loop(i = i + 1, sa = sa, sb = sb)
end
end
]]

-- make_integer: construct an integer Value from i64
-- Inline expressions; no separate function needed.

-- make_float: construct a float Value from f64

-- resolve_rk: resolve a register-or-constant operand.
-- Used by SETTABUP, SETTABLE, SETTI, SETFIELD, MMBINI, MMBINK.
local resolve_rk = host.region [[
region resolve_rk(L: ptr(LuaThread), base: index, k: u8, c: u16, constants: ptr(Value); value(v: Value))

entry start()
    if k == 1 then
        jump value(v = constants[as(index, c)])
    end
    jump value(v = L.stack[base + as(index, c)])
end
end
]]

return {
    value_truth = value_truth,
    value_as_integer = value_as_integer,
    value_as_float = value_as_float,
    value_to_number = value_to_number,
    value_as_string = value_as_string,
    value_to_string = value_to_string,
    value_as_table = value_as_table,
    value_as_function = value_as_function,
    value_raw_equal = value_raw_equal,
    value_equal = value_equal,
    value_less_than = value_less_than,
    value_less_equal = value_less_equal,
    resolve_rk = resolve_rk,
}
