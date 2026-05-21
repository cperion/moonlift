package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do I["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.TM) do I["TM_" .. k] = moon.int(v) end

-- Load op_loadbool in isolation
local ok, err = pcall(function()
    local r = host.region { TAG_TRUE = I.TAG_TRUE, TAG_FALSE = I.TAG_FALSE } [[
region op_loadbool(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
                   next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    var val: Value = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    if b ~= 0 then
        val = { tag = @{TAG_TRUE}, aux = 0, bits = 0 }
    else
        val = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    end
    L.stack[base + as(index, a)] = val
    if c ~= 0 then
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]
    print("op_loadbool:", r and "OK" or "FAIL")
end)
if not ok then print("op_loadbool FAIL:", err) end

-- Load op_move in isolation
local ok2, err2 = pcall(function()
    return host.region [[
region op_move(L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, bx: u32, sbx: i32;
               next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    L.stack[base + as(index, a)] = L.stack[base + as(index, b)]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]]
end)
if ok2 then print("op_move OK") else print("op_move FAIL:", err2) end
