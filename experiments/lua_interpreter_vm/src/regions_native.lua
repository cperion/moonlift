-- Lua Interpreter VM — explicit native ABI boundary.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.NativeResult) do I["NATIVE_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

local invoke_native = host.region(I) [[
region invoke_native(L: ptr(LuaThread), cl: ptr(CClosure), ctx: NativeCallContext;
                     returned: cont(nres: i32),
                     yielded: cont(nres: i32),
                     error: cont(err: Value),
                     oom: cont(),
                     stack_grow: cont(needed: index),
                     reenter_lua: cont(),
                     invalid: cont())
entry start()
    if L == nil then jump invalid() end
    if cl == nil then jump invalid() end
    if cl.fn == nil then jump invalid() end
    if cl.fn.addr == nil then jump invalid() end
    var ctx_cell: NativeCallContext = ctx
    var result: NativeCallResult = {
        status = as(u8, @{NATIVE_INVALID}),
        nresults = 0,
        err = { tag = 0, aux = @{ERR_CALL}, bits = 0 },
        stack_needed = 0,
        continuation = nil
    }
    let fn: func(ptr(LuaThread), ptr(CClosure), ptr(NativeCallContext), ptr(NativeCallResult)) -> index = as(func(ptr(LuaThread), ptr(CClosure), ptr(NativeCallContext), ptr(NativeCallResult)) -> index, cl.fn.addr)
    let rc: index = fn(L, cl, &ctx_cell, &result)
    if rc ~= as(index, 0) then jump invalid() end
    emit decode_native_result(&result;
        returned = returned,
        yielded = yielded,
        error = error,
        oom = oom,
        stack_grow = stack_grow,
        reenter_lua = reenter_lua,
        invalid = invalid)
end
end
]]

local decode_native_result = host.region(I) [[
region decode_native_result(result: ptr(NativeCallResult);
                            returned: cont(nres: i32),
                            yielded: cont(nres: i32),
                            error: cont(err: Value),
                            oom: cont(),
                            stack_grow: cont(needed: index),
                            reenter_lua: cont(),
                            invalid: cont())
entry start()
    if result == nil then
        jump invalid()
    end
    switch result.status do
    case 0 then
        jump returned(nres = result.nresults)
    case 1 then
        jump error(err = result.err)
    case 2 then
        jump yielded(nres = result.nresults)
    case 3 then
        jump oom()
    case 4 then
        jump stack_grow(needed = result.stack_needed)
    case 5 then
        jump reenter_lua()
    case 6 then
        jump invalid()
    default then
        jump invalid()
    end
end
end
]]

return { invoke_native = invoke_native, decode_native_result = decode_native_result }
