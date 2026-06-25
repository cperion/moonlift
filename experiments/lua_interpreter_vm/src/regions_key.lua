-- Lua Interpreter VM — table key protocol regions.
-- Lua-visible key distinctions are centralized here so raw get/set/next/rehash
-- cannot drift. PUC Lua is an oracle for equality behavior only; no PUC table
-- layout or hash shape is imported.

local lalin = require("lalin")
local host = require("lalin.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = lalin.int(v) end

local value_key_hash = host.region {
    TAG_NIL = I.TAG_NIL,
    TAG_INTEGER = I.TAG_INTEGER,
    TAG_NUM = I.TAG_NUM,
} [[
region value_key_hash(v: Value; ok(hash: u32) | invalid_key)

entry start()
    if v.tag == @{TAG_NIL} then jump invalid_key() end
    if v.tag == @{TAG_INTEGER} then
        let h64: u64 = v.bits ^ (v.bits >> as(u64, 32))
        jump ok(hash = as(u32, h64))
    end
    if v.tag == @{TAG_NUM} then
        let n: f64 = bitcast(f64, v.bits)
        if n ~= n then jump invalid_key() end
        let i: i64 = as(i64, n)
        if as(f64, i) == n then
            let ib: u64 = as(u64, i)
            let ih: u64 = ib ^ (ib >> as(u64, 32))
            jump ok(hash = as(u32, ih))
        end
        let nh: u64 = v.bits ^ (v.bits >> as(u64, 32))
        jump ok(hash = as(u32, nh))
    end
    let raw: u64 = v.bits ^ (as(u64, v.aux) << as(u64, 32)) ^ as(u64, v.tag)
    let h: u64 = raw ^ (raw >> as(u64, 32))
    jump ok(hash = as(u32, h))
end
end
]]

local value_key_equal = host.region {
    TAG_NIL = I.TAG_NIL,
    TAG_INTEGER = I.TAG_INTEGER,
    TAG_NUM = I.TAG_NUM,
} [[
region value_key_equal(a: Value, b: Value; yes | no)

entry start()
    if a.tag == @{TAG_NIL} or b.tag == @{TAG_NIL} then jump no() end
    if a.tag == @{TAG_INTEGER} and b.tag == @{TAG_INTEGER} then
        if a.bits == b.bits then jump yes() end
        jump no()
    end
    if a.tag == @{TAG_NUM} and b.tag == @{TAG_NUM} then
        let an: f64 = bitcast(f64, a.bits)
        let bn: f64 = bitcast(f64, b.bits)
        if an == bn then jump yes() end
        jump no()
    end
    if a.tag == @{TAG_INTEGER} and b.tag == @{TAG_NUM} then
        if as(f64, as(i64, a.bits)) == bitcast(f64, b.bits) then jump yes() end
        jump no()
    end
    if a.tag == @{TAG_NUM} and b.tag == @{TAG_INTEGER} then
        if bitcast(f64, a.bits) == as(f64, as(i64, b.bits)) then jump yes() end
        jump no()
    end
    if a.tag ~= b.tag then jump no() end
    if a.aux ~= b.aux then jump no() end
    if a.bits == b.bits then jump yes() end
    jump no()
end
end
]]

local value_key_array_index = host.region {
    TAG_INTEGER = I.TAG_INTEGER,
    TAG_NUM = I.TAG_NUM,
} [[
region value_key_array_index(key: Value;
                             index_key(idx: index) |
                             not_array |
                             invalid_key)
entry start()
    if key.tag == @{TAG_INTEGER} then
        let int_part: i64 = as(i64, key.bits)
        if int_part >= 1 then jump index_key(idx = as(index, int_part)) end
        jump not_array()
    end
    if key.tag == @{TAG_NUM} then
        let n: f64 = bitcast(f64, key.bits)
        if n ~= n then jump invalid_key() end
        let i: i64 = as(i64, n)
        if i >= 1 and as(f64, i) == n then jump index_key(idx = as(index, i)) end
        jump not_array()
    end
    jump not_array()
end
end
]]

local node_key_equal = host.region { value_key_equal = value_key_equal } [[
region node_key_equal(n: ptr(Node), key: Value; yes(n: ptr(Node)) | no(n: ptr(Node)))

entry start()
    emit @{value_key_equal}(n.key, key; yes = is_equal, no = not_equal)
end
block is_equal() jump yes(n = n) end
block not_equal() jump no(n = n) end
end
]]

local node_key_equal_with_bucket = host.region { value_key_equal = value_key_equal } [[
region node_key_equal_with_bucket(bucket: index, n: ptr(Node), key: Value;
                                  yes(bucket: index, n: ptr(Node)) |
                                  no(bucket: index, n: ptr(Node)))
entry start()
    emit @{value_key_equal}(n.key, key; yes = is_equal, no = not_equal)
end
block is_equal() jump yes(bucket = bucket, n = n) end
block not_equal() jump no(bucket = bucket, n = n) end
end
]]

local node_key_equal_in_chain = host.region { value_key_equal = value_key_equal } [[
region node_key_equal_in_chain(head: ptr(Node), n: ptr(Node), key: Value;
                               yes(n: ptr(Node)) |
                               no(head: ptr(Node), n: ptr(Node)))
entry start()
    emit @{value_key_equal}(n.key, key; yes = is_equal, no = not_equal)
end
block is_equal() jump yes(n = n) end
block not_equal() jump no(head = head, n = n) end
end
]]

local rehash_key_array_index = host.region { value_key_array_index = value_key_array_index } [[
region rehash_key_array_index(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32;
                              index_key(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32, idx: index) |
                              not_array(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32) |
                              invalid_key(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32))
entry start()
    emit @{value_key_array_index}(n.key; index_key = yes, not_array = no, invalid_key = bad)
end
block yes(idx: index) jump index_key(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask, idx = idx) end
block no() jump not_array(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask) end
block bad() jump invalid_key(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask) end
end
]]

local rehash_key_hash = host.region { value_key_hash = value_key_hash } [[
region rehash_key_hash(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32;
                       ok(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32, hash: u32) |
                       invalid_key(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32))
entry start()
    emit @{value_key_hash}(n.key; ok = got_hash, invalid_key = bad)
end
block got_hash(hash: u32) jump ok(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask, hash = hash) end
block bad() jump invalid_key(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask) end
end
]]

return {
    value_key_hash = value_key_hash,
    value_key_equal = value_key_equal,
    value_key_array_index = value_key_array_index,
    node_key_equal = node_key_equal,
    node_key_equal_with_bucket = node_key_equal_with_bucket,
    node_key_equal_in_chain = node_key_equal_in_chain,
    rehash_key_array_index = rehash_key_array_index,
    rehash_key_hash = rehash_key_hash,
}
