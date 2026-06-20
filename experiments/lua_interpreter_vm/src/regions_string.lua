-- Lua Interpreter VM — String regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
I.SIZE_STRING = moon.int(40)

-- string_hash: compute Lua-compatible string hash
local string_hash = host.region [[
region string_hash(bytes: ptr(u8), len: index, seed: u32; done(hash: u32))
entry start()
    let h: u32 = seed
    jump loop(i = as(index, 0), h = h)
end
block loop(i: index, h: u32)
    if i >= len then jump done(hash = h) end
    let nh: u32 = h * 5 + as(u32, bytes[i])
    jump loop(i = i + 1, h = nh)
end
end
]]

-- string_intern: find or create an interned string. The String payload bytes
-- are allocated in one VM-owned block after the String header.
local string_intern = host.region { TAG_STR = I.TAG_STR, SIZE_STRING = I.SIZE_STRING } [[
region string_intern(L: ptr(LuaThread), bytes: ptr(u8), len: index;
                     found(s: ptr(String)) |
                     created(s: ptr(String)) |
                     oom)
entry start()
    if L == nil then jump oom() end
    if L.global == nil then jump oom() end
    let st: ptr(StringTable) = L.global.string_table
    if st == nil then jump oom() end
    if st.buckets == nil then jump oom() end
    emit string_hash(bytes, len, as(u32, 0); done = have_hash)
end
block have_hash(hash: u32)
    let st: ptr(StringTable) = L.global.string_table
    jump bucket_loop(i = as(index, 0), hash = hash, st = st)
end
block bucket_loop(i: index, hash: u32, st: ptr(StringTable))
    if i >= st.bucket_count then jump allocate_new() end
    let s: ptr(String) = st.buckets[i]
    jump chain_loop(i = i, hash = hash, st = st, s = s)
end
block chain_loop(i: index, hash: u32, st: ptr(StringTable), s: ptr(String))
    if s == nil then jump bucket_loop(i = i + 1, hash = hash, st = st) end
    if s.hash == hash and s.len == len then
        jump bytes_loop(i = i, hash = hash, st = st, s = s, j = as(index, 0))
    end
    jump chain_loop(i = i, hash = hash, st = st, s = as(ptr(String), s.gc.next))
end
block bytes_loop(i: index, hash: u32, st: ptr(StringTable), s: ptr(String), j: index)
    if j >= len then jump found(s = s) end
    if s.bytes[j] ~= bytes[j] then
        jump chain_loop(i = i, hash = hash, st = st, s = as(ptr(String), s.gc.next))
    end
    jump bytes_loop(i = i, hash = hash, st = st, s = s, j = j + 1)
end
block allocate_new()
    emit alloc_bytes(L.global, as(index, @{SIZE_STRING}) + len + 1, as(u32, 8);
        ok = allocated,
        step_required = out_of_mem,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    let s: ptr(String) = as(ptr(String), ptr)
    s.gc.tt = as(u8, @{TAG_STR})
    s.gc.marked = L.global.currentwhite
    s.reserved = 0
    s.len = len
    s.bytes = ptr + as(index, @{SIZE_STRING})
    s.bytes[len] = 0
    jump copy_bytes(s = s, i = as(index, 0), h = as(u32, 0))
end
block copy_bytes(s: ptr(String), i: index, h: u32)
    if i >= len then jump insert_new(s = s, hash = h) end
    s.bytes[i] = bytes[i]
    let nh: u32 = h * 5 + as(u32, bytes[i])
    jump copy_bytes(s = s, i = i + 1, h = nh)
end
block insert_new(s: ptr(String), hash: u32)
    let st: ptr(StringTable) = L.global.string_table
    let bucket: index = as(index, hash) % st.bucket_count
    s.hash = hash
    s.gc.next = as(ptr(GCHeader), st.buckets[bucket])
    st.buckets[bucket] = s
    st.nuse = st.nuse + 1
    jump created(s = s)
end
block out_of_mem()
    jump oom()
end
end
]]

-- string_concat_range: concatenate stack values that are already strings.
-- Non-string conversion/metamethod selection remains a typed call_mm/error
-- distinction instead of pretending primitive success.
local string_concat_range = host.region { TAG_STR = I.TAG_STR, ERR_CONCAT = I.ERR_CONCAT, SIZE_STRING = I.SIZE_STRING } [[
region string_concat_range(L: ptr(LuaThread), first: index, last: index;
                           done(s: ptr(String)) |
                           call_mm(mm: Value) |
                           error(code: i32) |
                           oom)
entry start()
    jump measure(i = first, total = as(index, 0))
end
block measure(i: index, total: index)
    if i > last then jump allocate(total = total) end
    let v: Value = L.stack[i]
    if v.tag ~= @{TAG_STR} then jump error(code = @{ERR_CONCAT}) end
    let s: ptr(String) = as(ptr(String), v.bits)
    jump measure(i = i + 1, total = total + s.len)
end
block allocate(total: index)
    emit alloc_bytes(L.global, total + 1, as(u32, 8);
        ok = bytes_allocated,
        step_required = out_of_mem,
        oom = out_of_mem)
end
block bytes_allocated(ptr: ptr(u8))
    jump copy_value(i = first, out = ptr, pos = as(index, 0))
end
block copy_value(i: index, out: ptr(u8), pos: index)
    if i > last then jump intern(out = out, total = pos) end
    let v: Value = L.stack[i]
    let s: ptr(String) = as(ptr(String), v.bits)
    jump copy_byte(i = i, s = s, out = out, pos = pos, j = as(index, 0))
end
block copy_byte(i: index, s: ptr(String), out: ptr(u8), pos: index, j: index)
    if j >= s.len then jump copy_value(i = i + 1, out = out, pos = pos + s.len) end
    out[pos + j] = s.bytes[j]
    jump copy_byte(i = i, s = s, out = out, pos = pos, j = j + 1)
end
block intern(out: ptr(u8), total: index)
    out[total] = 0
    emit string_intern(L, out, total;
        found = got_string,
        created = got_string,
        oom = out_of_mem)
end
block got_string(s: ptr(String))
    jump done(s = s)
end
block out_of_mem()
    jump oom()
end
end
]]

return {
    string_hash = string_hash,
    string_intern = string_intern,
    string_concat_range = string_concat_range,
}
