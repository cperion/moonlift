-- Lua Interpreter VM — GC protocol regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.GCColor) do I["COLOR_" .. k] = moon.int(v) end
for k, v in pairs(const.GCState) do I["GCSTATE_" .. k] = moon.int(v) end

-- alloc_object: attempt allocation through the explicit VM allocator boundary.
-- Raw libc/malloc semantics are intentionally not embedded here; allocation
-- must eventually return through ok/step_required/oom explicitly.
local alloc_object = host.region [[
region alloc_object(G: ptr(GlobalState), size: index, tt: u8;
                    ok: cont(obj: ptr(GCHeader)),
                    step_required: cont(),
                    oom: cont())
entry start()
    if G == nil then
        jump oom()
    end
    if G.allocator == nil then
        jump oom()
    end
    if G.totalbytes > G.threshold then
        jump step_required()
    end
    -- Allocator extern bridge is not wired yet. Fail loud instead of hiding
    -- a null-pointer/errno/malloc convention in VM semantics.
    jump oom()
end
end
]]

-- gc_check: check if GC step is needed
local gc_check = host.region [[
region gc_check(L: ptr(LuaThread); ok: cont(), step: cont(), oom: cont())
entry start()
    let G: ptr(GlobalState) = L.global
    if G.totalbytes > G.threshold then
        jump step()
    end
    jump ok()
end
end
]]

-- gc_step: one atomic GC step
local gc_step = host.region [[
region gc_step(L: ptr(LuaThread); done: cont(), oom: cont())
entry start()
    jump done()
end
end
]]

-- mark_value: mark an object from a Value reference
local mark_value = host.region { TAG_STR = I.TAG_STR, TAG_TABLE = I.TAG_TABLE,
    TAG_LCLOSURE = I.TAG_LCLOSURE, TAG_CCLOSURE = I.TAG_CCLOSURE,
    TAG_USERDATA = I.TAG_USERDATA, TAG_THREAD = I.TAG_THREAD,
} [[
region mark_value(G: ptr(GlobalState), v: Value; done: cont(), pushed_gray: cont(), oom: cont())
entry start()
    if v.tag == @{TAG_STR} then
        jump done()
    end
    if v.tag == @{TAG_TABLE} then
        let t: ptr(Table) = as(ptr(Table), v.bits)
        emit mark_object(G, as(ptr(GCHeader), t);
            done = mark_done,
            pushed_gray = gray_done,
            oom = out_of_mem)
    end
    if v.tag == @{TAG_LCLOSURE} then
        let cl: ptr(LClosure) = as(ptr(LClosure), v.bits)
        emit mark_object(G, as(ptr(GCHeader), cl);
            done = mark_done,
            pushed_gray = gray_done,
            oom = out_of_mem)
    end
    if v.tag == @{TAG_CCLOSURE} then
        let cl: ptr(CClosure) = as(ptr(CClosure), v.bits)
        emit mark_object(G, as(ptr(GCHeader), cl);
            done = mark_done,
            pushed_gray = gray_done,
            oom = out_of_mem)
    end
    jump done()
end
block mark_done()
    jump done()
end
block gray_done()
    jump pushed_gray()
end
block out_of_mem()
    jump oom()
end
end
]]

-- mark_object: mark an object from a GCHeader pointer
local mark_object = host.region { COLOR_BLACK = I.COLOR_BLACK, COLOR_GRAY = I.COLOR_GRAY } [[
region mark_object(G: ptr(GlobalState), obj: ptr(GCHeader);
                   done: cont(), pushed_gray: cont(), oom: cont())
entry start()
    if obj == nil then
        jump done()
    end
    if obj.marked ~= @{COLOR_BLACK} then
        obj.marked = @{COLOR_GRAY}
        jump pushed_gray()
    end
    jump done()
end
end
]]

-- propagate_gray: process gray objects
local propagate_gray = host.region [[
region propagate_gray(G: ptr(GlobalState); done: cont(), empty: cont(), oom: cont())
entry start()
    jump empty()
end
end
]]

-- sweep_step: sweep one page of objects
local sweep_step = host.region [[
region sweep_step(G: ptr(GlobalState), limit: index; done: cont(), more: cont(), oom: cont())
entry start()
    jump done()
end
end
]]

-- write_barrier: barrier after write into black container
local write_barrier = host.region {
    TAG_STR = I.TAG_STR, TAG_TABLE = I.TAG_TABLE, TAG_LCLOSURE = I.TAG_LCLOSURE,
    TAG_CCLOSURE = I.TAG_CCLOSURE, TAG_USERDATA = I.TAG_USERDATA, TAG_THREAD = I.TAG_THREAD,
    TAG_PROTO = I.TAG_PROTO, COLOR_BLACK = I.COLOR_BLACK,
} [[
region write_barrier(G: ptr(GlobalState), parent: ptr(GCHeader), child: Value;
                     clean: cont(), barriered: cont())
entry start()
    if parent ~= nil and parent.marked == @{COLOR_BLACK} then
        if child.tag == @{TAG_STR} or child.tag == @{TAG_TABLE} or child.tag == @{TAG_LCLOSURE} or child.tag == @{TAG_CCLOSURE} or child.tag == @{TAG_USERDATA} or child.tag == @{TAG_THREAD} or child.tag == @{TAG_PROTO} then
            jump barriered()
        end
    end
    jump clean()
end
end
]]

-- write_barrier_back: backward barrier
local write_barrier_back = host.region [[
region write_barrier_back(G: ptr(GlobalState), parent: ptr(GCHeader); done: cont())
entry start()
    jump done()
end
end
]]

return {
    alloc_object = alloc_object,
    gc_check = gc_check,
    gc_step = gc_step,
    mark_value = mark_value,
    mark_object = mark_object,
    propagate_gray = propagate_gray,
    sweep_step = sweep_step,
    write_barrier = write_barrier,
    write_barrier_back = write_barrier_back,
}
