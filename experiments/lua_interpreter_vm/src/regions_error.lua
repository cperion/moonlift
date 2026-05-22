-- Lua Interpreter VM — Error, protected-call, and TBC regions (Lua 5.5)

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.TM) do I["TM_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do I["RESUME_" .. k] = moon.int(v) end

-- build_error_object: construct a Value error from code
local build_error_object = host.region { TAG_NIL = I.TAG_NIL, TAG_STR = I.TAG_STR, ERR_RUNTIME = I.ERR_RUNTIME } [[
region build_error_object(L: ptr(LuaThread), code: i32, culprit: Value;
                          built: cont(err: Value), oom: cont())
entry start()
    jump built(err = { tag = @{TAG_NIL}, aux = as(u32, code), bits = 0 })
end
end
]]

-- tbc_close_chain: walk L.tbc_head from topmost to level, calling __close on each.
-- Updates L.tbc_head as slots are closed.
local tbc_close_chain = host.region {
    TAG_NIL = I.TAG_NIL, TAG_FALSE = I.TAG_FALSE, TAG_TABLE = I.TAG_TABLE,
    TAG_STR = I.TAG_STR, TAG_LCLOSURE = I.TAG_LCLOSURE, TAG_CCLOSURE = I.TAG_CCLOSURE,
    ERR_RUNTIME = I.ERR_RUNTIME, TM_CLOSE = I.TM_CLOSE,
    RESUME_TBC_CLOSE = I.RESUME_TBC_CLOSE,
} [[
region tbc_close_chain(L: ptr(LuaThread), level: index;
                       done: cont(),
                       error: cont(code: i32),
                       oom: cont())
entry start()
    if L.tbc_head <= level then jump done() end
    let top_idx: index = L.tbc_head
    let val: Value = L.stack[top_idx]
    L.tbc_head = 0
    jump check_next(i = top_idx - 1, val = val)
end
block check_next(i: index, val: Value)
    if i > level then
        if L.stack[i].tag ~= @{TAG_NIL} then
            L.tbc_head = i
        end
    end
    if i > level then
        jump check_next(i = i - 1, val = L.stack[i])
    end
    -- Now close top_idx's variable
    if val.tag == @{TAG_NIL} or val.tag == @{TAG_FALSE} then
        jump done()
    end
    -- Look for __close metamethod
    emit tbc_get_close(val;
        found = have_close,
        missing = no_close)
end
block have_close(mm: Value)
    -- __close invocation re-enters the VM and needs a full dynamic continuation.
    -- Until that path is wired, fail loudly instead of silently skipping it.
    jump error(code = @{ERR_RUNTIME})
end
block no_close()
    jump done()
end
end
]]

-- Helper: get __close metamethod from a value
local tbc_get_close = host.region {
    TAG_TABLE = I.TAG_TABLE, TAG_STR = I.TAG_STR, TAG_NIL = I.TAG_NIL,
    TM_CLOSE = I.TM_CLOSE,
} [[
region tbc_get_close(obj: Value; found: cont(mm: Value), missing: cont())
entry start()
    if obj.tag == @{TAG_TABLE} then
        let t: ptr(Table) = as(ptr(Table), obj.bits)
        if t.metatable ~= nil then
            let key: Value = { tag = @{TAG_STR}, bits = 0, aux = as(u32, @{TM_CLOSE}) }
            emit table_raw_get(t.metatable, key;
                hit = got_mm,
                miss = no_mm)
        end
    end
    jump missing()
end
block got_mm(value: Value)
    if value.tag ~= @{TAG_NIL} then
        jump found(mm = value)
    end
    jump missing()
end
block no_mm()
    jump missing()
end
end
]]

-- raise_error: drain TBC chain, unwind frames looking for ProtectedFrame
local raise_error = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
region raise_error(L: ptr(LuaThread), err: Value;
                   caught: cont(frame: ptr(Frame), handler: ptr(ProtectedFrame)),
                   uncaught: cont(code: i32))
entry start()
    let pf: ptr(ProtectedFrame) = L.protected_top
    if pf ~= nil then
        let level: index = pf.stack_top
        emit tbc_close_chain(L, level;
            done = found_pf,
            error = uncaught_err,
            oom = out_of_mem)
    end
    jump uncaught_check()
end
block found_pf()
    let pf: ptr(ProtectedFrame) = L.protected_top
    let frame_idx: index = pf.frame_index
    if frame_idx < L.frame_count then
        L.frame_count = frame_idx + 1
    end
    let frame: ptr(Frame) = L.frames + frame_idx
    L.top = pf.stack_top
    L.protected_top = pf.previous
    L.stack[pf.handler_slot] = err
    jump caught(frame = frame, handler = pf)
end
block uncaught_check()
    let pf: ptr(ProtectedFrame) = L.protected_top
    if pf ~= nil then
        let frame_idx: index = pf.frame_index
        if frame_idx < L.frame_count then
            L.frame_count = frame_idx + 1
        end
        let frame: ptr(Frame) = L.frames + frame_idx
        L.top = pf.stack_top
        L.protected_top = pf.previous
        L.stack[pf.handler_slot] = err
        jump caught(frame = frame, handler = pf)
    end
    L.err_value = err
    jump uncaught(code = @{ERR_RUNTIME})
end
block uncaught_err(code: i32)
    L.err_value = err
    jump uncaught(code = code)
end
block out_of_mem()
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
    jump failure(err = { tag = @{TAG_NIL}, aux = @{ERR_RUNTIME}, bits = 0 })
end
end
]]

return {
    build_error_object = build_error_object,
    tbc_close_chain = tbc_close_chain,
    raise_error = raise_error,
    enter_protected = enter_protected,
    leave_protected = leave_protected,
    protected_call = protected_call,
}
