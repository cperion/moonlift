-- Lua Interpreter VM — Lua 5.5 binary chunk compatibility frontier.
-- PUC Lua is an encoding/semantic oracle only; this frontier must decode into
-- Moonlift-native Proto products and then validate them. Until the typed reader
-- is complete, the boundary rejects chunks explicitly instead of pretending that
-- internal Proto or PUC layouts are accepted.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

local load_lua55_binary_chunk = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
region load_lua55_binary_chunk(L: ptr(LuaThread), bytes: ptr(u8), len: index;
                               ok: cont(proto: ptr(Proto)),
                               format_error: cont(err: CompileError),
                               semantic_error: cont(err: CompileError),
                               oom: cont())
entry start()
    let err: CompileError = {
        code = @{ERR_RUNTIME},
        pos = { offset = 0, line = 1, col = 1 },
        token = 0
    }
    jump format_error(err = err)
end
end
]]

return {
    load_lua55_binary_chunk = load_lua55_binary_chunk,
}
