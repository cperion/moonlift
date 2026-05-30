-- Lua Interpreter VM — Coroutine regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Status) do I["THREAD_" .. k] = moon.int(v) end
for k, v in pairs(const.ThreadFlag) do I["THREAD_FLAG_" .. k] = moon.int(v) end

-- coroutine_resume: resume a LuaThread. Full re-entry remains in vm_loop;
-- this region only encodes the explicit state distinctions.
local coroutine_resume = host.region {
    ERR_RUNTIME = I.ERR_RUNTIME,
    THREAD_OK = I.THREAD_OK,
    THREAD_YIELDED = I.THREAD_YIELDED,
    THREAD_DEAD = I.THREAD_DEAD,
} [[
region coroutine_resume(caller: ptr(LuaThread), target: ptr(LuaThread), nargs: i32;
                        ok: cont(nres: i32),
                        yielded: cont(nres: i32),
                        dead: cont(),
                        error: cont(code: i32),
                        oom: cont())
entry start()
    if target == nil then
        jump error(code = @{ERR_RUNTIME})
    end
    if target.status == @{THREAD_DEAD} then
        jump dead()
    end
    if target.status == @{THREAD_OK} then
        jump error_out(code = @{ERR_RUNTIME})
    end
    if target.status == @{THREAD_YIELDED} then
        jump yielded(nres = 0)
    end
    jump error_out(code = @{ERR_RUNTIME})
end
block error_out(code: i32)
    target.last_error_code = code
    jump error(code = code)
end
end
]]

-- coroutine_yield: yield from current coroutine when yieldability data allows it.
local coroutine_yield = host.region {
    ERR_RUNTIME = I.ERR_RUNTIME,
    THREAD_YIELDED = I.THREAD_YIELDED,
} [[
region coroutine_yield(L: ptr(LuaThread), nres: i32;
                       yielded: cont(nres: i32),
                       not_yieldable: cont(),
                       error: cont(code: i32))
entry start()
    if L == nil then
        jump error(code = @{ERR_RUNTIME})
    end
    if L.nonyieldable > 0 then
        jump not_yieldable()
    end
    L.status = @{THREAD_YIELDED}
    L.coroutine.nresults = nres
    if L.frame_count > 0 then
        let f: ptr(Frame) = L.frames + (L.frame_count - 1)
        L.coroutine.resume = f.resume
    end
    jump yielded(nres = nres)
end
end
]]

return {
    coroutine_resume = coroutine_resume,
    coroutine_yield = coroutine_yield,
}
