-- Lua Interpreter VM — Metamethod regions (Lua 5.5)

local lalin = require("lalin")
local host = require("lalin.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = lalin.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = lalin.int(v) end
for k, v in pairs(const.TM) do I["TM_" .. k] = lalin.int(v) end

-- get_metamethod: lookup metamethod from any value's metatable
local get_metamethod = host.region { TAG_TABLE = I.TAG_TABLE } [[
region get_metamethod(G: ptr(GlobalState), obj: Value, event: u8;
                      found(mm: Value) | missing)
entry start()
    if obj.tag == @{TAG_TABLE} then
        let t: ptr(Table) = as(ptr(Table), obj.bits)
        emit get_table_metamethod(G, t, event;
            found = have_mm,
            missing = no_mm)
    end
    jump missing()
end
block have_mm(mm: Value)
    jump found(mm = mm)
end
block no_mm()
    jump missing()
end
end
]]

-- get_table_metamethod: lookup from table's metatable (uses flags cache)
local get_table_metamethod = host.region { TAG_STR = I.TAG_STR, TAG_NIL = I.TAG_NIL } [[
region get_table_metamethod(G: ptr(GlobalState), t: ptr(Table), event: u8;
                            found(mm: Value) | missing)
entry start()
    if t.metatable == nil then
        jump missing()
    end
    let name: ptr(String) = G.tmname[as(index, event)]
    if name == nil then
        jump missing()
    end
    let key: Value = { tag = @{TAG_STR}, aux = 0, bits = as(u64, name) }
    emit table_raw_get(t.metatable, key;
        hit = got,
        miss = no_mm)
end
block got(value: Value)
    if value.tag == @{TAG_NIL} then
        jump missing()
    end
    jump found(mm = value)
end
block no_mm()
    jump missing()
end
end
]]

-- binop_dispatch: check integer, then float, then metamethod
local binop_dispatch = host.region {
    TAG_INTEGER = I.TAG_INTEGER, TAG_NUM = I.TAG_NUM,
} [[
region binop_dispatch(L: ptr(LuaThread), lhs: Value, rhs: Value, event: u8;
                      fast_integer(x: i64, y: i64) |
                      fast_float(x: f64, y: f64) |
                      call_mm(mm: Value) |
                      type_error)
entry start()
    if lhs.tag == @{TAG_INTEGER} and rhs.tag == @{TAG_INTEGER} then
        jump fast_integer(x = as(i64, lhs.bits), y = as(i64, rhs.bits))
    end
    if lhs.tag == @{TAG_NUM} and rhs.tag == @{TAG_NUM} then
        jump fast_float(x = bitcast(f64, lhs.bits), y = bitcast(f64, rhs.bits))
    end
    emit get_metamethod(L.global, lhs, event;
        found = left_mm,
        missing = try_right)
end
block left_mm(mm: Value)
    jump call_mm(mm = mm)
end
block try_right()
    emit get_metamethod(L.global, rhs, event;
        found = right_mm,
        missing = no_mm)
end
block right_mm(mm: Value)
    jump call_mm(mm = mm)
end
block no_mm()
    jump type_error()
end
end
]]

-- unop_dispatch: same for unary ops
local unop_dispatch = host.region {
    TAG_INTEGER = I.TAG_INTEGER, TAG_NUM = I.TAG_NUM,
} [[
region unop_dispatch(L: ptr(LuaThread), v: Value, event: u8;
                      fast_integer(x: i64) |
                      fast_float(x: f64) |
                      call_mm(mm: Value) |
                      type_error)
entry start()
    if v.tag == @{TAG_INTEGER} then
        jump fast_integer(x = as(i64, v.bits))
    end
    if v.tag == @{TAG_NUM} then
        jump fast_float(x = bitcast(f64, v.bits))
    end
    emit get_metamethod(L.global, v, event;
        found = have_mm,
        missing = no_mm)
end
block have_mm(mm: Value)
    jump call_mm(mm = mm)
end
block no_mm()
    jump type_error()
end
end
]]

-- prepare_metamethod_call: set up stack for metamethod invocation
local prepare_metamethod_call = host.region [[
region prepare_metamethod_call(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
                               mm: Value, nargs: i32, wanted: i32, resume: ResumeState;
                               prepared | error(code: i32) | oom)
entry start()
    frame.pc = pc
    frame.resume = resume
    frame.resume.pc = pc + 1
    frame.resume.base = base
    frame.resume.result_base = base
    frame.resume.call_top = top
    frame.resume.wanted = wanted
    L.stack[base] = mm
    L.top = base + as(index, nargs) + 1
    jump prepared()
end
end
]]

return {
    get_metamethod = get_metamethod,
    get_table_metamethod = get_table_metamethod,
    binop_dispatch = binop_dispatch,
    unop_dispatch = unop_dispatch,
    prepare_metamethod_call = prepare_metamethod_call,
}
