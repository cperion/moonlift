-- Lua Interpreter VM — Table access regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local key_regions = require("experiments.lua_interpreter_vm.src.regions_key")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.TM) do I["TM_" .. k] = moon.int(v) end
I.SIZE_VALUE = moon.int(16)
I.SIZE_NODE = moon.int(40)
I.SIZE_TABLE = moon.int(104)

-- table_raw_get: direct array or hash lookup through canonical key protocol.
local table_raw_get = host.region {
    TAG_NIL = I.TAG_NIL,
    value_key_array_index = key_regions.value_key_array_index,
    value_key_hash = key_regions.value_key_hash,
    node_key_equal = key_regions.node_key_equal,
} [[
region table_raw_get(t: ptr(Table), key: Value; hit(value: Value) | miss)

entry start()
    if t == nil then jump miss() end
    emit @{value_key_array_index}(key;
        index_key = try_array,
        not_array = hash_key,
        invalid_key = miss)
end
block try_array(idx: index)
    if idx <= t.array_len then
        let v: Value = t.array[idx - 1]
        if v.tag ~= @{TAG_NIL} then jump hit(value = v) end
        jump miss()
    end
    jump hash_key()
end
block hash_key()
    if t.nodes == nil then jump miss() end
    emit @{value_key_hash}(key; ok = got_hash, invalid_key = miss)
end
block got_hash(hash: u32)
    let bucket: index = as(index, hash & t.node_mask)
    let n: ptr(Node) = t.nodes + bucket
    jump node_loop(n = n)
end
block node_loop(n: ptr(Node))
    if n == nil then jump miss() end
    if n.value.tag == @{TAG_NIL} then jump node_loop(n = n.next) end
    emit @{node_key_equal}(n, key; yes = key_hit, no = key_miss)
end
block key_hit(n: ptr(Node))
    jump hit(value = n.value)
end
block key_miss(n: ptr(Node))
    jump node_loop(n = n.next)
end
end
]]

-- table_raw_set: direct array or hash store. If existing capacity is
-- insufficient it exits through resized; callers decide whether to grow or to
-- trigger __newindex.
local table_raw_set = host.region {
    TAG_NIL = I.TAG_NIL,
    ERR_INDEX = I.ERR_INDEX,
    value_key_array_index = key_regions.value_key_array_index,
    value_key_hash = key_regions.value_key_hash,
    node_key_equal = key_regions.node_key_equal,
    node_key_equal_in_chain = key_regions.node_key_equal_in_chain,
} [[
region table_raw_set(L: ptr(LuaThread), t: ptr(Table), key: Value, value: Value;
                     stored | resized | error(code: i32) | oom)
entry start()
    if t == nil then jump error(code = @{ERR_INDEX}) end
    emit @{value_key_array_index}(key;
        index_key = try_array,
        not_array = hash_key,
        invalid_key = bad_key)
end
block try_array(idx: index)
    if idx <= t.array_cap then
        t.array[idx - 1] = value
        if value.tag ~= @{TAG_NIL} and idx > t.array_len then t.array_len = idx end
        jump stored()
    end
    jump hash_key()
end
block hash_key()
    emit @{value_key_hash}(key; ok = got_hash, invalid_key = bad_key)
end
block got_hash(hash: u32)
    if value.tag == @{TAG_NIL} then
        if t.nodes == nil then jump stored() end
        jump delete_bucket(hash = hash)
    end
    if t.nodes == nil then jump resized() end
    if t.node_count > as(index, t.node_mask) then jump resized() end
    let bucket: index = as(index, hash & t.node_mask)
    let head: ptr(Node) = t.nodes + bucket
    if head.value.tag == @{TAG_NIL} then
        head.key = key
        head.value = value
        head.next = nil
        t.node_count = t.node_count + 1
        t.shape_epoch = t.shape_epoch + 1
        jump stored()
    end
    jump node_loop(head = head, n = head)
end
block node_loop(head: ptr(Node), n: ptr(Node))
    if n == nil then jump find_free(head = head, i = as(index, 0)) end
    if n.value.tag == @{TAG_NIL} then jump node_loop(head = head, n = n.next) end
    emit @{node_key_equal_in_chain}(head, n, key; yes = update_node, no = keep_search)
end
block update_node(n: ptr(Node))
    n.value = value
    jump stored()
end
block keep_search(head: ptr(Node), n: ptr(Node))
    jump node_loop(head = head, n = n.next)
end
block find_free(head: ptr(Node), i: index)
    if i > as(index, t.node_mask) then jump resized() end
    let free: ptr(Node) = t.nodes + i
    if free.value.tag == @{TAG_NIL} then
        free.key = key
        free.value = value
        free.next = head.next
        head.next = free
        t.node_count = t.node_count + 1
        t.shape_epoch = t.shape_epoch + 1
        jump stored()
    end
    jump find_free(head = head, i = i + 1)
end
block delete_bucket(hash: u32)
    let bucket: index = as(index, hash & t.node_mask)
    let head: ptr(Node) = t.nodes + bucket
    jump delete_loop(n = head)
end
block delete_loop(n: ptr(Node))
    if n == nil then jump stored() end
    if n.value.tag == @{TAG_NIL} then jump delete_loop(n = n.next) end
    emit @{node_key_equal}(n, key; yes = delete_hit, no = delete_miss)
end
block delete_hit(n: ptr(Node))
    n.value = value
    if t.node_count > 0 then t.node_count = t.node_count - 1 end
    t.shape_epoch = t.shape_epoch + 1
    jump stored()
end
block delete_miss(n: ptr(Node))
    jump delete_loop(n = n.next)
end
block bad_key()
    jump error(code = @{ERR_INDEX})
end
end
]]

local table_raw_get_state = host.region { table_raw_get = table_raw_get } [[
region table_raw_get_state(t: ptr(Table), key: Value, cur: Value, depth: u16;
                           hit(cur: Value, depth: u16, value: Value) |
                           miss(cur: Value, depth: u16))
entry start()
    emit @{table_raw_get}(t, key; hit = got, miss = no)
end
block got(value: Value) jump hit(cur = cur, depth = depth, value = value) end
block no() jump miss(cur = cur, depth = depth) end
end
]]

local table_raw_set_state = host.region { table_raw_set = table_raw_set } [[
region table_raw_set_state(L: ptr(LuaThread), t: ptr(Table), key: Value, value: Value, cur: Value;
                           stored | resized(cur: Value) | error(code: i32) | oom)
entry start()
    emit @{table_raw_set}(L, t, key, value; stored = stored, resized = grew, error = error, oom = oom)
end
block grew() jump resized(cur = cur) end
end
]]

local table_grow_for_key_state = host.region [[
region table_grow_for_key_state(L: ptr(LuaThread), t: ptr(Table), key: Value, cur: Value;
                                done(cur: Value) | error(code: i32) | oom)
entry start()
    emit table_grow_for_key(L, t, key; done = grew, error = error, oom = oom)
end
block grew() jump done(cur = cur) end
end
]]

local get_table_metamethod_state = host.region [[
region get_table_metamethod_state(G: ptr(GlobalState), t: ptr(Table), event: u8, cur: Value, depth: u16;
                                  found(cur: Value, depth: u16, mm: Value) |
                                  missing(cur: Value, depth: u16))
entry start()
    emit get_table_metamethod(G, t, event; found = got, missing = no)
end
block got(mm: Value) jump found(cur = cur, depth = depth, mm = mm) end
block no() jump missing(cur = cur, depth = depth) end
end
]]

-- table_get: raw lookup plus chained table-valued __index; callable __index
-- exits through call_mm with the original self/key payload.
local table_get = host.region {
    TAG_NIL = I.TAG_NIL, TAG_TABLE = I.TAG_TABLE,
    ERR_INDEX = I.ERR_INDEX, ERR_LOOP = I.ERR_LOOP,
    TM_INDEX = I.TM_INDEX,
} [[
region table_get(L: ptr(LuaThread), obj: Value, key: Value;
                 value(v: Value) |
                 call_mm(mm: Value, self: Value, key: Value) |
                 type_error |
                 loop_error |
                 oom)
entry start()
    if obj.tag ~= @{TAG_TABLE} then jump type_error() end
    jump get_loop(cur = obj, depth = as(u16, 0))
end
block get_loop(cur: Value, depth: u16)
    if cur.tag ~= @{TAG_TABLE} then jump type_error() end
    let t: ptr(Table) = as(ptr(Table), cur.bits)
    emit table_raw_get_state(t, key, cur, depth; hit = raw_hit, miss = check_meta)
end
block raw_hit(cur: Value, depth: u16, value: Value)
    jump value(v = value)
end
block check_meta(cur: Value, depth: u16)
    let t: ptr(Table) = as(ptr(Table), cur.bits)
    if t.metatable == nil then jump no_index(cur = cur, depth = depth) end
    emit get_table_metamethod_state(L.global, t, as(u8, @{TM_INDEX}), cur, depth;
        found = have_index,
        missing = no_index)
end
block have_index(cur: Value, depth: u16, mm: Value)
    if mm.tag == @{TAG_TABLE} then
        if depth >= as(u16, 200) then jump loop_error() end
        jump get_loop(cur = mm, depth = depth + 1)
    end
    jump call_mm(mm = mm, self = cur, key = key)
end
block no_index(cur: Value, depth: u16)
    let nil_value: Value = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    jump value(v = nil_value)
end
block out_of_mem()
    jump oom()
end
end
]]

-- table_set: existing raw keys update directly; absent keys follow chained
-- table-valued __newindex or callable __newindex before raw insertion.
local table_set = host.region {
    TAG_TABLE = I.TAG_TABLE, TAG_NIL = I.TAG_NIL, ERR_INDEX = I.ERR_INDEX, ERR_LOOP = I.ERR_LOOP,
    TM_NEWINDEX = I.TM_NEWINDEX,
} [[
region table_set(L: ptr(LuaThread), obj: Value, key: Value, value: Value;
                 stored |
                 call_mm(mm: Value, self: Value, key: Value, value: Value) |
                 type_error |
                 loop_error |
                 oom)
entry start()
    if obj.tag ~= @{TAG_TABLE} then jump type_error() end
    jump set_loop(cur = obj, depth = as(u16, 0))
end
block set_loop(cur: Value, depth: u16)
    if cur.tag ~= @{TAG_TABLE} then jump type_error() end
    let t: ptr(Table) = as(ptr(Table), cur.bits)
    emit table_raw_get_state(t, key, cur, depth; hit = existing_key, miss = missing_key)
end
block existing_key(cur: Value, depth: u16, value: Value)
    let t: ptr(Table) = as(ptr(Table), cur.bits)
    emit table_raw_set(L, t, key, value;
        stored = did_store,
        resized = out_of_mem,
        error = set_err,
        oom = out_of_mem)
end
block missing_key(cur: Value, depth: u16)
    let t: ptr(Table) = as(ptr(Table), cur.bits)
    if t.metatable == nil then jump no_newindex(cur = cur, depth = depth) end
    emit get_table_metamethod_state(L.global, t, as(u8, @{TM_NEWINDEX}), cur, depth;
        found = have_newindex,
        missing = no_newindex)
end
block have_newindex(cur: Value, depth: u16, mm: Value)
    if mm.tag == @{TAG_TABLE} then
        if depth >= as(u16, 200) then jump loop_error() end
        jump set_loop(cur = mm, depth = depth + 1)
    end
    jump call_mm(mm = mm, self = cur, key = key, value = value)
end
block no_newindex(cur: Value, depth: u16)
    let grow_t: ptr(Table) = as(ptr(Table), cur.bits)
    emit table_raw_set_state(L, grow_t, key, value, cur;
        stored = did_store,
        resized = did_resize,
        error = set_err,
        oom = out_of_mem)
end
block did_resize(cur: Value)
    let grow_t: ptr(Table) = as(ptr(Table), cur.bits)
    emit table_grow_for_key_state(L, grow_t, key, cur;
        done = retry_raw,
        error = set_err,
        oom = out_of_mem)
end
block retry_raw(cur: Value)
    let retry_t: ptr(Table) = as(ptr(Table), cur.bits)
    emit table_raw_set(L, retry_t, key, value;
        stored = did_store,
        resized = out_of_mem,
        error = set_err,
        oom = out_of_mem)
end
block did_store()
    jump stored()
end
block set_err(code: i32)
    jump type_error()
end
block out_of_mem()
    jump oom()
end
end
]]

-- table_next: iterate over table array part first, then hash nodes.
local table_next = host.region {
    TAG_NIL = I.TAG_NIL,
    TAG_INTEGER = I.TAG_INTEGER,
    node_key_equal_with_bucket = key_regions.node_key_equal_with_bucket,
} [[
region table_next(L: ptr(LuaThread), t: ptr(Table), key: Value;
                  pair(key: Value, value: Value) |
                  done |
                  invalid_key)
entry start()
    if t == nil then
        jump invalid_key()
    end
    if key.tag == @{TAG_NIL} then
        jump array_loop(i = as(index, 0))
    end
    if key.tag == @{TAG_INTEGER} then
        let int_part: i64 = as(i64, key.bits)
        if int_part >= 1 then
            let idx: index = as(index, int_part)
            if idx <= t.array_len then
                if t.array[idx - 1].tag == @{TAG_NIL} then
                    jump invalid_key()
                end
                jump array_loop(i = idx)
            end
        end
    end
    jump find_hash(i = as(index, 0))
end
block array_loop(i: index)
    if i >= t.array_len then
        jump hash_loop(i = as(index, 0))
    end
    let v: Value = t.array[i]
    if v.tag ~= @{TAG_NIL} then
        let out_key: Value = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, i + 1) }
        jump pair(key = out_key, value = v)
    end
    jump array_loop(i = i + 1)
end
block find_hash(i: index)
    if t.nodes == nil then
        jump invalid_key()
    end
    if i > as(index, t.node_mask) then
        jump invalid_key()
    end
    let n: ptr(Node) = t.nodes + i
    jump find_node(bucket = i, n = n)
end
block find_node(bucket: index, n: ptr(Node))
    if n == nil then
        jump find_hash(i = bucket + 1)
    end
    if n.value.tag == @{TAG_NIL} then jump find_node(bucket = bucket, n = n.next) end
    emit @{node_key_equal_with_bucket}(bucket, n, key; yes = found_hash_key, no = keep_find_hash)
end
block found_hash_key(bucket: index, n: ptr(Node))
    jump emit_after(bucket = bucket, n = n.next)
end
block keep_find_hash(bucket: index, n: ptr(Node))
    jump find_node(bucket = bucket, n = n.next)
end
block emit_after(bucket: index, n: ptr(Node))
    if n == nil then
        jump hash_loop(i = bucket + 1)
    end
    if n.value.tag ~= @{TAG_NIL} then
        jump pair(key = n.key, value = n.value)
    end
    jump emit_after(bucket = bucket, n = n.next)
end
block hash_loop(i: index)
    if t.nodes == nil then
        jump done()
    end
    if i > as(index, t.node_mask) then
        jump done()
    end
    let n: ptr(Node) = t.nodes + i
    jump emit_node(bucket = i, n = n)
end
block emit_node(bucket: index, n: ptr(Node))
    if n == nil then
        jump hash_loop(i = bucket + 1)
    end
    if n.value.tag ~= @{TAG_NIL} then
        jump pair(key = n.key, value = n.value)
    end
    jump emit_node(bucket = bucket, n = n.next)
end
end
]]

-- table_resize: allocate fresh array/hash storage and rehash all existing hash
-- entries through the same canonical key protocol used by raw get/set.
local table_resize = host.region {
    TAG_NIL = I.TAG_NIL,
    TAG_INTEGER = I.TAG_INTEGER,
    SIZE_VALUE = I.SIZE_VALUE,
    SIZE_NODE = I.SIZE_NODE,
    value_key_array_index = key_regions.value_key_array_index,
    value_key_hash = key_regions.value_key_hash,
    rehash_key_array_index = key_regions.rehash_key_array_index,
    rehash_key_hash = key_regions.rehash_key_hash,
} [[
region table_resize(L: ptr(LuaThread), t: ptr(Table), new_array_len: index, new_hash_power: u32;
                    done | oom)
entry start()
    if L == nil then jump oom() end
    if L.global == nil then jump oom() end
    if t == nil then jump oom() end
    let hash_count: index = as(index, 1) << as(index, new_hash_power)
    let array_bytes: index = new_array_len * as(index, @{SIZE_VALUE})
    let node_bytes: index = hash_count * as(index, @{SIZE_NODE})
    emit alloc_bytes(L.global, array_bytes + node_bytes, as(u32, 8);
        ok = allocated,
        step_required = out_of_mem,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    let new_array: ptr(Value) = as(ptr(Value), ptr)
    let nodes: ptr(Node) = as(ptr(Node), ptr + (new_array_len * as(index, @{SIZE_VALUE})))
    jump init_array(i = as(index, 0), new_array = new_array, nodes = nodes,
                    old_array = t.array, old_array_len = t.array_len,
                    old_nodes = t.nodes, old_mask = t.node_mask)
end
block init_array(i: index, new_array: ptr(Value), nodes: ptr(Node), old_array: ptr(Value), old_array_len: index, old_nodes: ptr(Node), old_mask: u32)
    if i >= new_array_len then jump init_nodes(i = as(index, 0), new_array = new_array, nodes = nodes, old_nodes = old_nodes, old_mask = old_mask) end
    new_array[i].tag = @{TAG_NIL}
    new_array[i].aux = 0
    new_array[i].bits = 0
    if old_array ~= nil and i < old_array_len then
        new_array[i] = old_array[i]
    end
    jump init_array(i = i + 1, new_array = new_array, nodes = nodes,
                    old_array = old_array, old_array_len = old_array_len,
                    old_nodes = old_nodes, old_mask = old_mask)
end
block init_nodes(i: index, new_array: ptr(Value), nodes: ptr(Node), old_nodes: ptr(Node), old_mask: u32)
    let hash_count: index = as(index, 1) << as(index, new_hash_power)
    if i >= hash_count then jump commit(new_array = new_array, nodes = nodes, old_nodes = old_nodes, old_mask = old_mask) end
    nodes[i].key.tag = @{TAG_NIL}
    nodes[i].key.aux = 0
    nodes[i].key.bits = 0
    nodes[i].value.tag = @{TAG_NIL}
    nodes[i].value.aux = 0
    nodes[i].value.bits = 0
    nodes[i].next = nil
    jump init_nodes(i = i + 1, new_array = new_array, nodes = nodes, old_nodes = old_nodes, old_mask = old_mask)
end
block commit(new_array: ptr(Value), nodes: ptr(Node), old_nodes: ptr(Node), old_mask: u32)
    let hash_count: index = as(index, 1) << as(index, new_hash_power)
    t.array = new_array
    t.array_cap = new_array_len
    if t.array_len > new_array_len then t.array_len = new_array_len end
    t.nodes = nodes
    t.node_mask = as(u32, hash_count - 1)
    t.node_count = 0
    t.lastfree = nil
    t.shape_epoch = t.shape_epoch + 1
    if old_nodes == nil then jump done() end
    jump rehash_bucket(i = as(index, 0), old_nodes = old_nodes, old_mask = old_mask)
end
block rehash_bucket(i: index, old_nodes: ptr(Node), old_mask: u32)
    if i > as(index, old_mask) then jump done() end
    let n: ptr(Node) = old_nodes + i
    jump rehash_node(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask)
end
block rehash_node(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32)
    if n == nil then jump rehash_bucket(i = i + 1, old_nodes = old_nodes, old_mask = old_mask) end
    if n.value.tag == @{TAG_NIL} then jump rehash_node(i = i, n = n.next, old_nodes = old_nodes, old_mask = old_mask) end
    emit @{rehash_key_array_index}(i, n, old_nodes, old_mask;
        index_key = rehash_array,
        not_array = rehash_hash,
        invalid_key = skip_old)
end
block rehash_array(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32, idx: index)
    if idx <= t.array_cap then
        t.array[idx - 1] = n.value
        if idx > t.array_len then t.array_len = idx end
        jump rehash_node(i = i, n = n.next, old_nodes = old_nodes, old_mask = old_mask)
    end
    jump rehash_hash(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask)
end
block rehash_hash(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32)
    emit @{rehash_key_hash}(i, n, old_nodes, old_mask; ok = rehash_hash_got, invalid_key = skip_old)
end
block rehash_hash_got(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32, hash: u32)
    let bucket: index = as(index, hash & t.node_mask)
    let head: ptr(Node) = t.nodes + bucket
    if head.value.tag == @{TAG_NIL} then
        head.key = n.key
        head.value = n.value
        head.next = nil
        t.node_count = t.node_count + 1
        jump rehash_node(i = i, n = n.next, old_nodes = old_nodes, old_mask = old_mask)
    end
    jump rehash_find_free(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask, head = head, free_i = as(index, 0))
end
block rehash_find_free(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32, head: ptr(Node), free_i: index)
    if free_i > as(index, t.node_mask) then jump out_of_mem() end
    let free: ptr(Node) = t.nodes + free_i
    if free.value.tag == @{TAG_NIL} then
        free.key = n.key
        free.value = n.value
        free.next = head.next
        head.next = free
        t.node_count = t.node_count + 1
        jump rehash_node(i = i, n = n.next, old_nodes = old_nodes, old_mask = old_mask)
    end
    jump rehash_find_free(i = i, n = n, old_nodes = old_nodes, old_mask = old_mask, head = head, free_i = free_i + 1)
end
block skip_old(i: index, n: ptr(Node), old_nodes: ptr(Node), old_mask: u32)
    jump rehash_node(i = i, n = n.next, old_nodes = old_nodes, old_mask = old_mask)
end
block out_of_mem()
    jump oom()
end
end
]]

local table_grow_for_key = host.region {
    TAG_INTEGER = I.TAG_INTEGER,
    TAG_NUM = I.TAG_NUM,
    ERR_INDEX = I.ERR_INDEX,
} [[
region table_grow_for_key(L: ptr(LuaThread), t: ptr(Table), key: Value;
                          done | error(code: i32) | oom)
entry start()
    if t == nil then jump error(code = @{ERR_INDEX}) end
    jump choose_hash_power(power = as(u32, 2))
end
block choose_hash_power(power: u32)
    let count: index = as(index, 1) << as(index, power)
    if count <= t.node_count + 1 then jump choose_hash_power(power = power + 1) end
    if t.nodes ~= nil and count <= as(index, t.node_mask) + 1 then jump choose_hash_power(power = power + 1) end
    if key.tag == @{TAG_INTEGER} then
        let int_part: i64 = as(i64, key.bits)
        if int_part >= 1 then jump array_need(idx = as(index, int_part), cap = t.array_cap, hash_power = power) end
    end
    if key.tag == @{TAG_NUM} then
        let n: f64 = bitcast(f64, key.bits)
        if n ~= n then jump bad_key() end
        let i: i64 = as(i64, n)
        if i >= 1 and as(f64, i) == n then jump array_need(idx = as(index, i), cap = t.array_cap, hash_power = power) end
    end
    emit table_resize(L, t, t.array_cap, power; done = done, oom = oom)
end
block array_need(idx: index, cap: index, hash_power: u32)
    if cap >= idx then
        emit table_resize(L, t, cap, hash_power; done = done, oom = oom)
    end
    if cap == 0 then jump array_need(idx = idx, cap = as(index, 4), hash_power = hash_power) end
    jump array_need(idx = idx, cap = cap * 2, hash_power = hash_power)
end
block bad_key()
    jump error(code = @{ERR_INDEX})
end
end
]]

local table_new = host.region { TAG_TABLE = I.TAG_TABLE, TAG_NIL = I.TAG_NIL, SIZE_TABLE = I.SIZE_TABLE, SIZE_VALUE = I.SIZE_VALUE, SIZE_NODE = I.SIZE_NODE } [[
region table_new(L: ptr(LuaThread), array_len: index, hash_power: u32;
                 ok(v: Value) | oom)
entry start()
    let hash_count: index = as(index, 1) << as(index, hash_power)
    let array_bytes: index = array_len * as(index, @{SIZE_VALUE})
    let node_bytes: index = hash_count * as(index, @{SIZE_NODE})
    let total_bytes: index = as(index, @{SIZE_TABLE}) + array_bytes + node_bytes
    emit alloc_bytes(L.global, total_bytes, as(u32, 8);
        ok = allocated,
        step_required = out_of_mem,
        oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    let t: ptr(Table) = as(ptr(Table), ptr)
    let arr: ptr(Value) = as(ptr(Value), ptr + as(index, @{SIZE_TABLE}))
    let nodes: ptr(Node) = as(ptr(Node), ptr + as(index, @{SIZE_TABLE}) + (array_len * as(index, @{SIZE_VALUE})))
    t.gc.next = L.global.allgc
    t.gc.tt = as(u8, @{TAG_TABLE})
    t.gc.marked = L.global.currentwhite
    L.global.allgc = as(ptr(GCHeader), t)
    t.flags = 0
    t.array_len = 0
    let hash_count: index = as(index, 1) << as(index, hash_power)
    t.array_cap = array_len
    t.array = arr
    t.node_mask = as(u32, hash_count - 1)
    t.node_count = 0
    t.nodes = nodes
    t.lastfree = nil
    t.metatable = nil
    t.shape_epoch = 0
    t.weak_next = nil
    t.finalizer_state = 0
    t.reserved = 0
    jump init_array(t = t, i = as(index, 0))
end
block init_array(t: ptr(Table), i: index)
    if i >= t.array_cap then jump init_nodes(t = t, i = as(index, 0)) end
    t.array[i].tag = @{TAG_NIL}
    t.array[i].aux = 0
    t.array[i].bits = 0
    jump init_array(t = t, i = i + 1)
end
block init_nodes(t: ptr(Table), i: index)
    let hash_count: index = as(index, t.node_mask) + 1
    if i >= hash_count then jump finish(t = t) end
    t.nodes[i].key.tag = @{TAG_NIL}
    t.nodes[i].key.aux = 0
    t.nodes[i].key.bits = 0
    t.nodes[i].value.tag = @{TAG_NIL}
    t.nodes[i].value.aux = 0
    t.nodes[i].value.bits = 0
    t.nodes[i].next = nil
    jump init_nodes(t = t, i = i + 1)
end
block finish(t: ptr(Table))
    let out: Value = { tag = @{TAG_TABLE}, aux = 0, bits = as(u64, t) }
    jump ok(v = out)
end
block out_of_mem()
    jump oom()
end
end
]]

return {
    table_raw_get = table_raw_get,
    table_raw_set = table_raw_set,
    table_get = table_get,
    table_set = table_set,
    table_next = table_next,
    table_resize = table_resize,
    table_grow_for_key = table_grow_for_key,
    table_new = table_new,
}
