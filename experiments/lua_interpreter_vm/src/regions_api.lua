-- Lua Interpreter VM — API sealing region (internal)

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

-- api_index_to_addr: decode Lua C API index conventions
local api_index_to_addr = host.region { ERR_API = I.ERR_API } [[
region api_index_to_addr(L: ptr(LuaThread), idx: i32;
                         valid: cont(slot: index),
                         pseudo_global: cont(),
                         pseudo_registry: cont(),
                         pseudo_upvalue: cont(n: i32),
                         invalid: cont())
entry start()
    -- Positive indices: 1-based from bottom of stack
    if idx > 0 then
        let slot: index = as(index, idx - 1)
        if slot < L.top then
            jump valid(slot = slot)
        end
        jump invalid()
    end
    -- Negative indices: -1-based from top of stack
    if idx < 0 then
        let abs: index = as(index, 0 - idx)
        if abs <= L.top then
            jump valid(slot = L.top - abs)
        end
        jump invalid()
    end
    -- idx == 0: invalid
    jump invalid()
end
end
]]

return {
    api_index_to_addr = api_index_to_addr,
}
