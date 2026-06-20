-- Lua Interpreter VM — explicit allocator and growth boundary
-- Allocation crosses the VM boundary only through Allocator.realloc/free
-- function pointers. There is no hidden libc/malloc or PUC allocator shape here.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
I.MAX_STACK_SIZE = moon.int(const.MAX_STACK_SIZE)
I.MAX_FRAMES = moon.int(const.MAX_FRAMES)

-- Product sizes used by allocator/growth regions. These are sizes of the
-- Moonlift-native products in products.lua under the C-compatible natural ABI.
-- They are VM product facts, not imported PUC layout facts.
I.SIZE_VALUE = moon.int(16)
I.ALIGN_VALUE = moon.int(8)
I.SIZE_FRAME = moon.int(144)
I.ALIGN_FRAME = moon.int(8)
I.SIZE_NODE = moon.int(40)
I.ALIGN_NODE = moon.int(8)
I.SIZE_TABLE = moon.int(104)
I.ALIGN_TABLE = moon.int(8)
I.SIZE_STRING = moon.int(40)
I.ALIGN_STRING = moon.int(8)
I.SIZE_UPVAL = moon.int(56)
I.ALIGN_UPVAL = moon.int(8)
I.SIZE_LCLOSURE = moon.int(48)
I.ALIGN_LCLOSURE = moon.int(8)

local realloc_bytes = host.region({
    MAX_STACK_SIZE = I.MAX_STACK_SIZE,
    MAX_FRAMES = I.MAX_FRAMES,
    SIZE_VALUE = I.SIZE_VALUE,
    ALIGN_VALUE = I.ALIGN_VALUE,
    SIZE_FRAME = I.SIZE_FRAME,
    ALIGN_FRAME = I.ALIGN_FRAME,
}) [[
region realloc_bytes(G: ptr(GlobalState), old: ptr(u8), old_size: index, new_size: index, align: u32;
                     ok(ptr: ptr(u8)) | step_required | oom)
entry start()
    if G == nil then jump oom() end
    if G.allocator == nil then jump oom() end
    if G.allocator.realloc == nil then jump oom() end
    if new_size > old_size then
        let delta: index = new_size - old_size
        if G.totalbytes + delta > G.threshold then
            jump step_required()
        end
    end
    let realloc_fn: func(ptr(u8), index, index, index): u64 = as(func(ptr(u8), index, index, index): u64, G.allocator.realloc)
    let p_bits: u64 = realloc_fn(old, old_size, new_size, as(index, align))
    if new_size > as(index, 0) then
        if p_bits == as(u64, 0) then jump oom() end
    end
    let p: ptr(u8) = as(ptr(u8), p_bits)
    if new_size >= old_size then
        G.totalbytes = G.totalbytes + (new_size - old_size)
    else
        G.totalbytes = G.totalbytes - (old_size - new_size)
    end
    jump ok(ptr = p)
end
end
]]

local alloc_bytes = host.region(I) [[
region alloc_bytes(G: ptr(GlobalState), size: index, align: u32;
                   ok(ptr: ptr(u8)) | step_required | oom)
entry start()
    emit realloc_bytes(G, as(ptr(u8), as(u64, 0)), as(index, 0), size, align;
        ok = ok,
        step_required = step_required,
        oom = oom)
end
end
]]

local free_bytes = host.region [[ 
region free_bytes(G: ptr(GlobalState), ptr: ptr(u8), size: index, align: u32;
                  done)
entry start()
    if G == nil then jump done() end
    if G.allocator == nil then jump done() end
    if G.allocator.realloc == nil then jump done() end
    let realloc_fn: func(ptr(u8), index, index, index): u64 = as(func(ptr(u8), index, index, index): u64, G.allocator.realloc)
    let ignored: u64 = realloc_fn(ptr, size, as(index, 0), as(index, align))
    if G.totalbytes >= size then
        G.totalbytes = G.totalbytes - size
    else
        G.totalbytes = 0
    end
    jump done()
end
end
]]

local alloc_object = host.region(I) [[
region alloc_object(G: ptr(GlobalState), size: index, tt: u8;
                    ok(obj: ptr(GCHeader)) | step_required | oom)
entry start()
    emit alloc_bytes(G, size, as(u32, 8);
        ok = allocated,
        step_required = need_step,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    let obj: ptr(GCHeader) = as(ptr(GCHeader), ptr)
    obj.next = G.allgc
    obj.tt = tt
    obj.marked = G.currentwhite
    G.allgc = obj
    jump ok(obj = obj)
end
block need_step()
    jump step_required()
end
block out_of_mem()
    jump oom()
end
end
]]

local grow_value_array = host.region(I) [[
region grow_value_array(L: ptr(LuaThread), needed: index;
                        ok(data: ptr(Value), capacity: index) | overflow | oom)
entry start()
    if needed > @{MAX_STACK_SIZE} then jump overflow() end
    if needed <= L.stack_size then jump ok(data = L.stack, capacity = L.stack_size) end
    let old_bytes: index = L.stack_size * @{SIZE_VALUE}
    let new_bytes: index = needed * @{SIZE_VALUE}
    emit realloc_bytes(L.global, as(ptr(u8), L.stack), old_bytes, new_bytes, as(u32, @{ALIGN_VALUE});
        ok = allocated,
        step_required = step_is_oom,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    L.stack = as(ptr(Value), ptr)
    L.stack_size = needed
    jump ok(data = L.stack, capacity = L.stack_size)
end
block step_is_oom()
    jump oom()
end
block out_of_mem()
    jump oom()
end
end
]]

local grow_frame_array = host.region(I) [[
region grow_frame_array(L: ptr(LuaThread), needed: index;
                        ok(data: ptr(Frame), capacity: index) | overflow | oom)
entry start()
    if needed > @{MAX_FRAMES} then jump overflow() end
    if needed <= L.frame_cap then jump ok(data = L.frames, capacity = L.frame_cap) end
    let old_bytes: index = L.frame_cap * @{SIZE_FRAME}
    let new_bytes: index = needed * @{SIZE_FRAME}
    emit realloc_bytes(L.global, as(ptr(u8), L.frames), old_bytes, new_bytes, as(u32, @{ALIGN_FRAME});
        ok = allocated,
        step_required = step_is_oom,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    L.frames = as(ptr(Frame), ptr)
    L.frame_cap = needed
    jump ok(data = L.frames, capacity = L.frame_cap)
end
block step_is_oom()
    jump oom()
end
block out_of_mem()
    jump oom()
end
end
]]

return {
    alloc_bytes = alloc_bytes,
    realloc_bytes = realloc_bytes,
    free_bytes = free_bytes,
    alloc_object = alloc_object,
    grow_value_array = grow_value_array,
    grow_frame_array = grow_frame_array,
    SIZE_VALUE = 16,
    SIZE_FRAME = 144,
    SIZE_NODE = 40,
    SIZE_TABLE = 104,
    SIZE_STRING = 40,
    SIZE_UPVAL = 56,
    SIZE_LCLOSURE = 48,
}
