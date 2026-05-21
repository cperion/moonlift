-- Lua Interpreter VM — Coroutine regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

-- coroutine_resume: resume a LuaThread
local coroutine_resume = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
region coroutine_resume(caller: ptr(LuaThread), target: ptr(LuaThread), nargs: i32;
                        ok: cont(nres: i32),
                        yielded: cont(nres: i32),
                        dead: cont(),
                        error: cont(code: i32),
                        oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]]

-- coroutine_yield: yield from current coroutine
local coroutine_yield = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
region coroutine_yield(L: ptr(LuaThread), nres: i32;
                       yielded: cont(nres: i32),
                       not_yieldable: cont(),
                       error: cont(code: i32))
entry start()
    jump not_yieldable()
end
end
]]

return {
    coroutine_resume = coroutine_resume,
    coroutine_yield = coroutine_yield,
}
