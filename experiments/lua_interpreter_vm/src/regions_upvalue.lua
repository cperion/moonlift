-- Lua Interpreter VM — Upvalue regions

local lalin = require("lalin")
local host = require("lalin.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = lalin.int(v) end
I.SIZE_UPVAL = lalin.int(56)
I.SIZE_LCLOSURE = lalin.int(48)
I.SIZE_PTR = lalin.int(8)

local alloc_open_upvalue = host.region { TAG_NIL = I.TAG_NIL, SIZE_UPVAL = I.SIZE_UPVAL } [[
region alloc_open_upvalue(L: ptr(LuaThread), stack_index: index, prev: ptr(UpVal), next_uv: ptr(UpVal);
                          made(uv: ptr(UpVal)) | oom)
entry start()
    emit alloc_bytes(L.global, as(index, @{SIZE_UPVAL}), as(u32, 8);
        ok = allocated,
        step_required = out_of_mem,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    let uv: ptr(UpVal) = as(ptr(UpVal), ptr)
    uv.gc.next = L.global.allgc
    uv.gc.tt = as(u8, @{TAG_NIL})
    uv.gc.marked = L.global.currentwhite
    L.global.allgc = as(ptr(GCHeader), uv)
    uv.v = L.stack + stack_index
    uv.closed = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    uv.stack_index = stack_index
    uv.next_open = next_uv
    if prev == nil then
        L.open_upvals = uv
    else
        prev.next_open = uv
    end
    jump made(uv = uv)
end
block out_of_mem()
    jump oom()
end
end
]]

-- find_upvalue: locate or create an open upvalue for a stack slot. The open
-- list is kept in descending stack_index order, so close_upvalues can stop as
-- soon as it reaches a slot below the closing boundary.
local find_upvalue = host.region { alloc_open_upvalue = alloc_open_upvalue } [[
region find_upvalue(L: ptr(LuaThread), stack_index: index; found(uv: ptr(UpVal)) | created(uv: ptr(UpVal)) | oom)

entry start()
    let head: ptr(UpVal) = L.open_upvals
    if head == nil then jump make_new(prev = as(ptr(UpVal), as(u64, 0)), next = head) end
    if head.stack_index == stack_index then jump found(uv = head) end
    if head.stack_index < stack_index then jump make_new(prev = as(ptr(UpVal), as(u64, 0)), next = head) end
    jump scan(prev = head, uv = head.next_open)
end
block scan(prev: ptr(UpVal), uv: ptr(UpVal))
    if uv == nil then jump make_new(prev = prev, next = uv) end
    if uv.stack_index == stack_index then jump found(uv = uv) end
    if uv.stack_index < stack_index then jump make_new(prev = prev, next = uv) end
    jump scan(prev = uv, uv = uv.next_open)
end
block make_new(prev: ptr(UpVal), next: ptr(UpVal))
    emit @{alloc_open_upvalue}(L, stack_index, prev, next; made = made_uv, oom = out_of_mem)
end
block made_uv(uv: ptr(UpVal))
    jump created(uv = uv)
end
block out_of_mem()
    jump oom()
end
end
]]

local capture_upvalue_slot = host.region { find_upvalue = find_upvalue } [[
region capture_upvalue_slot(L: ptr(LuaThread), cl: ptr(LClosure), i: index, stack_index: index;
                            done(cl: ptr(LClosure), i: index, uv: ptr(UpVal)) | oom)
entry start()
    emit @{find_upvalue}(L, stack_index; found = got, created = got, oom = oom)
end
block got(uv: ptr(UpVal))
    jump done(cl = cl, i = i, uv = uv)
end
end
]]

-- close_upvalues: close all upvalues at or above a stack index
local close_upvalues = host.region [[
region close_upvalues(L: ptr(LuaThread), from_stack_index: index; done | oom)

entry start()
    jump scan(uv = L.open_upvals)
end
block scan(uv: ptr(UpVal))
    if uv == nil then jump done() end
    if uv.stack_index < from_stack_index then jump done() end
    uv.closed = *uv.v
    uv.v = &uv.closed
    uv.stack_index = 0
    let next_uv: ptr(UpVal) = uv.next_open
    L.open_upvals = next_uv
    jump scan(uv = next_uv)
end
end
]]

-- make_lclosure: create a Lua closure from a Proto and capture its upvalues.
-- Upvalue descriptors are Lalin-native Proto facts: instack captures from
-- the current frame stack, otherwise the parent closure's upvalue object is
-- shared.
local make_lclosure = host.region { TAG_LCLOSURE = I.TAG_LCLOSURE, TAG_NIL = I.TAG_NIL, SIZE_LCLOSURE = I.SIZE_LCLOSURE, SIZE_PTR = I.SIZE_PTR } [[
region make_lclosure(L: ptr(LuaThread), parent: ptr(LClosure), proto: ptr(Proto), env: ptr(Table), base: index; ok(cl: ptr(LClosure)) | oom)

entry start()
    if proto == nil then jump oom() end
    let up_bytes: index = proto.upvals_len * as(index, @{SIZE_PTR})
    emit alloc_bytes(L.global, as(index, @{SIZE_LCLOSURE}) + up_bytes, as(u32, 8);
        ok = allocated,
        step_required = out_of_mem,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    let cl: ptr(LClosure) = as(ptr(LClosure), ptr)
    cl.gc.next = L.global.allgc
    cl.gc.tt = as(u8, @{TAG_LCLOSURE})
    cl.gc.marked = L.global.currentwhite
    L.global.allgc = as(ptr(GCHeader), cl)
    cl.env = env
    cl.proto = proto
    cl.nupvals = as(u8, proto.upvals_len)
    if proto.upvals_len == 0 then
        cl.upvals = as(ptr(ptr(UpVal)), as(u64, 0))
        jump ok(cl = cl)
    end
    cl.upvals = as(ptr(ptr(UpVal)), ptr + as(index, @{SIZE_LCLOSURE}))
    jump fill(i = as(index, 0), cl = cl)
end
block fill(i: index, cl: ptr(LClosure))
    if i >= proto.upvals_len then jump ok(cl = cl) end
    let desc: UpValDesc = proto.upvals[i]
    if desc.instack ~= 0 then
        let slot: index = base + as(index, desc.index)
        emit capture_upvalue_slot(L, cl, i, slot; done = got_uv, oom = out_of_mem)
    end
    if parent == nil then jump out_of_mem() end
    cl.upvals[i] = parent.upvals[as(index, desc.index)]
    jump fill(i = i + 1, cl = cl)
end
block got_uv(cl: ptr(LClosure), i: index, uv: ptr(UpVal))
    cl.upvals[i] = uv
    jump fill(i = i + 1, cl = cl)
end
block out_of_mem()
    jump oom()
end
end
]]

return {
    alloc_open_upvalue = alloc_open_upvalue,
    find_upvalue = find_upvalue,
    capture_upvalue_slot = capture_upvalue_slot,
    close_upvalues = close_upvalues,
    make_lclosure = make_lclosure,
}
