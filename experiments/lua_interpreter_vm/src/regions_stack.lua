-- Lua Interpreter VM — Stack and frame regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
I.MAX_STACK_SIZE = moon.int(const.MAX_STACK_SIZE)
I.MAX_FRAMES = moon.int(const.MAX_FRAMES)

-- stack_check: ensure stack has room for needed_top elements
local stack_check = host.region {
    MAX_STACK_SIZE = I.MAX_STACK_SIZE,
    ERR_STACK_OVERFLOW = I.ERR_STACK_OVERFLOW,
} [[
region stack_check(L: ptr(LuaThread), needed_top: index; ok | grown | overflow | oom)

entry start()
    if needed_top <= L.stack_size then
        jump ok()
    end
    if needed_top > @{MAX_STACK_SIZE} then
        jump overflow()
    end
    emit grow_value_array(L, needed_top;
        ok = did_grow,
        overflow = did_overflow,
        oom = out_of_mem)
end
block did_grow(data: ptr(Value), capacity: index)
    jump grown()
end
block did_overflow()
    jump overflow()
end
block out_of_mem()
    jump oom()
end
end
]]

-- frame_push: allocate a new frame in L.frames[]
local frame_push = host.region { TAG_NIL = I.TAG_NIL, ERR_STACK_OVERFLOW = I.ERR_STACK_OVERFLOW } [[
region frame_push(L: ptr(LuaThread), closure: Value, base: index, top: index,
                  result_base: index, call_top: index,
                  wanted: i32, resume: ResumeState,
                  yieldable: u8;
                  ok(frame: ptr(Frame)) | overflow | oom)
entry start()
    if L.frame_count >= L.frame_cap then
        emit grow_frame_array(L, L.frame_count + 1;
            ok = frame_storage_ready,
            overflow = frame_overflow,
            oom = frame_oom)
    end
    jump frame_storage_ready(data = L.frames, capacity = L.frame_cap)
end
block frame_storage_ready(data: ptr(Frame), capacity: index)
    let idx: index = L.frame_count
    L.frame_count = idx + 1
    let f: ptr(Frame) = L.frames + idx
    f.closure = closure
    f.base = base
    f.top = top
    f.pc = 0
    f.wanted = wanted
    f.tailcalls = 0
    f.result_base = result_base
    f.call_top = call_top
    f.resume = resume
    f.yieldable = yieldable
    f.flags = 0
    f.reserved = 0
    jump ok(frame = f)
end
block frame_overflow()
    jump overflow()
end
block frame_oom()
    jump oom()
end
end
]]

-- frame_pop: remove the top frame
local frame_pop = host.region [[
region frame_pop(L: ptr(LuaThread); parent(frame: ptr(Frame)) | empty)

entry start()
    if L.frame_count == 0 then
        jump empty()
    end
    L.frame_count = L.frame_count - 1
    if L.frame_count == 0 then
        jump empty()
    end
    let pf: ptr(Frame) = L.frames + (L.frame_count - 1)
    jump parent(frame = pf)
end
end
]]

-- adjust_results: copy and pad results for caller expectations.
-- The dst parameter is the call's explicit result base; callers must never
-- substitute parent.base for a call destination.
local adjust_results = host.region { TAG_NIL = I.TAG_NIL } [[
region adjust_results(L: ptr(LuaThread), first_result: index, nactual: i32, wanted: i32, dst: index; done(nplaced: i32) | oom)

entry start()
    if wanted >= 0 then
        let n: i32 = nactual
        if n > wanted then n = wanted end
        if 0 >= n then
            jump fill_loop(i = 0, wanted = wanted)
        end
        jump copy_loop(i = 0, n = n, dst = dst, first = first_result, wanted = wanted)
    else
        jump done(nplaced = nactual)
    end
end
block copy_loop(i: i32, n: i32, dst: index, first: index, wanted: i32)
    if i >= n then jump fill_loop(i = i, wanted = wanted) end
    L.stack[dst + as(index, i)] = L.stack[first + as(index, i)]
    jump copy_loop(i = i + 1, n = n, dst = dst, first = first, wanted = wanted)
end
block fill_loop(i: i32, wanted: i32)
    if i >= wanted then jump done(nplaced = wanted) end
    L.stack[dst + as(index, i)].tag = @{TAG_NIL}
    jump fill_loop(i = i + 1, wanted = wanted)
end
end
]]

-- adjust_varargs: Lua 5.5 varargs are kept explicitly in the frame's incoming
-- argument window. Fixed parameters occupy R[0..numparams-1]; extra arguments
-- remain immediately after them and OP_VARARG copies from that range.
local adjust_varargs = host.region { TAG_NIL = I.TAG_NIL } [[
region adjust_varargs(L: ptr(LuaThread), cl: ptr(LClosure), func_slot: index, nargs: i32; ok(base: index) | oom)

entry start()
    let base: index = func_slot + 1
    let np: i32 = as(i32, cl.proto.numparams)
    if nargs >= np then jump ok(base = base) end
    jump fill_missing(i = nargs, np = np, base = base)
end
block fill_missing(i: i32, np: i32, base: index)
    if i >= np then jump ok(base = base) end
    L.stack[base + as(index, i)] = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    jump fill_missing(i = i + 1, np = np, base = base)
end
end
]]

return {
    stack_check = stack_check,
    frame_push = frame_push,
    frame_pop = frame_pop,
    adjust_results = adjust_results,
    adjust_varargs = adjust_varargs,
}
