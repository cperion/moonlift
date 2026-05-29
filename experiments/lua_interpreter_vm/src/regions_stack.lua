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
region stack_check(L: ptr(LuaThread), needed_top: index; ok: cont(), grown: cont(), overflow: cont(), oom: cont())
entry start()
    if needed_top <= L.stack_size then
        jump ok()
    end
    if needed_top > @{MAX_STACK_SIZE} then
        jump overflow()
    end
    -- No allocator/growth backend is wired in this experiment; fail loud instead of executing past capacity.
    jump overflow()
end
end
]]

-- frame_push: allocate a new frame in L.frames[]
local frame_push = host.region { TAG_NIL = I.TAG_NIL, ERR_STACK_OVERFLOW = I.ERR_STACK_OVERFLOW } [[
region frame_push(L: ptr(LuaThread), closure: Value, base: index, top: index,
                  result_base: index, call_top: index,
                  wanted: i32, resume_mode: u16, resume_pc: index,
                  yieldable: u8;
                  ok: cont(frame: ptr(Frame)), overflow: cont(), oom: cont())
entry start()
    if L.frame_count >= L.frame_cap then
        -- No frame-array growth backend is wired in this experiment; fail loud instead of writing past capacity.
        jump overflow()
    end
    let idx: index = L.frame_count
    L.frame_count = idx + 1
    let f: ptr(Frame) = L.frames + idx
    f.closure = closure
    f.base = base
    f.top = top
    f.pc = 0
    f.wanted = wanted
    f.tailcalls = 0
    f.resume_mode = resume_mode
    f.resume_a = 0
    f.resume_b = 0
    f.resume_c = 0
    f.resume_pc = resume_pc
    f.resume_base = 0
    f.resume_value = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    f.result_base = result_base
    f.call_top = call_top
    f.yieldable = yieldable
    f.flags = 0
    f.reserved = 0
    jump ok(frame = f)
end
end
]]

-- frame_pop: remove the top frame
local frame_pop = host.region [[
region frame_pop(L: ptr(LuaThread); parent: cont(frame: ptr(Frame)), empty: cont())
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
region adjust_results(L: ptr(LuaThread), first_result: index, nactual: i32, wanted: i32, dst: index; done: cont(nplaced: i32), oom: cont())
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

-- adjust_varargs: set up base for vararg functions
local adjust_varargs = host.region [[
region adjust_varargs(L: ptr(LuaThread), cl: ptr(LClosure), func_slot: index, nargs: i32; ok: cont(base: index), oom: cont())
entry start()
    let np: i32 = as(i32, cl.proto.numparams)
    let fixargs: index = as(index, np)
    -- Vararg stack reshaping is intentionally rejected until the caller has provided an ABI-complete frame layout.
    jump oom()
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
