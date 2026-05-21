-- Lua Interpreter VM — Error and protected-call regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

-- build_error_object: construct a Value error from code
local build_error_object = host.region { TAG_NIL = I.TAG_NIL, TAG_STR = I.TAG_STR, ERR_RUNTIME = I.ERR_RUNTIME } [[
region build_error_object(L: ptr(LuaThread), code: i32, culprit: Value;
                          built: cont(err: Value), oom: cont())
entry start()
    -- Minimal explicit error object: carry the compact error code in aux until string allocation exists.
    jump built(err = { tag = @{TAG_NIL}, aux = as(u32, code), bits = 0 })
end
end
]]

-- raise_error: unwind frames looking for ProtectedFrame
local raise_error = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
region raise_error(L: ptr(LuaThread), err: Value;
                   caught: cont(frame: ptr(Frame), handler: ptr(ProtectedFrame)),
                   uncaught: cont(code: i32))
entry start()
    -- Check protected frames
    let pf: ptr(ProtectedFrame) = L.protected_top
    if pf ~= nil then
        -- Found protection boundary
        let frame_idx: index = pf.frame_index
        if frame_idx < L.frame_count then
            L.frame_count = frame_idx + 1
        end
        let frame: ptr(Frame) = L.frames + frame_idx
        L.top = pf.stack_top
        L.protected_top = pf.previous
        -- Place error on stack
        L.stack[pf.handler_slot] = err
        jump caught(frame = frame, handler = pf)
    end
    -- No protection: record the payload and report a runtime error at the sealed boundary.
    L.err_value = err
    jump uncaught(code = @{ERR_RUNTIME})
end
end
]]

-- enter_protected: push a ProtectedFrame
local enter_protected = host.region [[
region enter_protected(L: ptr(LuaThread), frame_index: index, stack_top: index,
                       handler_slot: index, errfunc_slot: index;
                       done: cont(pf: ptr(ProtectedFrame)), oom: cont())
entry start()
    -- ProtectedFrame storage is not present in LuaThread; allocation must come from the runtime allocator.
    jump oom()
end
end
]]

-- leave_protected: pop a ProtectedFrame
local leave_protected = host.region [[
region leave_protected(L: ptr(LuaThread), pf: ptr(ProtectedFrame); done: cont())
entry start()
    L.protected_top = pf.previous
    jump done()
end
end
]]

-- protected_call: implement pcall/xpcall
local protected_call = host.region { ERR_RUNTIME = I.ERR_RUNTIME, TAG_NIL = I.TAG_NIL } [[
region protected_call(L: ptr(LuaThread), func_slot: index, nargs: i32, wanted: i32, errfunc_slot: index;
                      success: cont(nres: i32),
                      failure: cont(err: Value),
                      oom: cont())
entry start()
    -- pcall cannot be represented safely without ProtectedFrame allocation.
    jump failure(err = { tag = @{TAG_NIL}, aux = @{ERR_RUNTIME}, bits = 0 })
end
end
]]

return {
    build_error_object = build_error_object,
    raise_error = raise_error,
    enter_protected = enter_protected,
    leave_protected = leave_protected,
    protected_call = protected_call,
}
