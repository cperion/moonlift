-- Lua Interpreter VM — Upvalue regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end

-- find_upvalue: locate or create an open upvalue for a stack slot
local find_upvalue = host.region { TAG_NIL = I.TAG_NIL } [[
region find_upvalue(L: ptr(LuaThread), stack_index: index; found: cont(uv: ptr(UpVal)), created: cont(uv: ptr(UpVal)), oom: cont())
entry start()
    var uv: ptr(UpVal) = L.open_upvals
    jump scan()
end
block scan()
    if uv == nil then jump make_new() end
    if uv.stack_index == stack_index then jump found(uv = uv) end
    if uv.stack_index < stack_index then jump make_new() end
    uv = uv.next_open
    jump scan()
end
block make_new()
    jump oom()
end
end
]]

-- close_upvalues: close all upvalues at or above a stack index
local close_upvalues = host.region [[
region close_upvalues(L: ptr(LuaThread), from_stack_index: index; done: cont(), oom: cont())
entry start()
    var uv: ptr(UpVal) = L.open_upvals
    jump scan()
end
block scan()
    if uv == nil then jump done() end
    if uv.stack_index < from_stack_index then jump done() end
    uv.closed = *uv.v
    uv.v = &uv.closed
    uv.stack_index = 0
    let next_uv: ptr(UpVal) = uv.next_open
    L.open_upvals = next_uv
    uv = next_uv
    jump scan()
end
end
]]

-- make_lclosure: create a Lua closure from a Proto
local make_lclosure = host.region [[
region make_lclosure(L: ptr(LuaThread), proto: ptr(Proto), env: ptr(Table), base: index; ok: cont(cl: ptr(LClosure)), oom: cont())
entry start()
    jump oom()
end
end
]]

return {
    find_upvalue = find_upvalue,
    close_upvalues = close_upvalues,
    make_lclosure = make_lclosure,
}
