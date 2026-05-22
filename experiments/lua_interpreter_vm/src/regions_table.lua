-- Lua Interpreter VM — Table access regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.TM) do I["TM_" .. k] = moon.int(v) end

-- table_raw_get: direct array or hash lookup
local table_raw_get = host.region { TAG_INTEGER = I.TAG_INTEGER, TAG_NIL = I.TAG_NIL } [[
region table_raw_get(t: ptr(Table), key: Value; hit: cont(value: Value), miss: cont())
entry start()
    -- Try array part first (Lua 5.5 integer keys address the array part)
    if key.tag == @{TAG_INTEGER} and t.array_len > 0 then
        let int_part: i64 = as(i64, key.bits)
        if int_part >= 1 then
            let idx: index = as(index, int_part)
            if idx <= t.array_len then
                let v: Value = t.array[idx - 1]
                if v.tag ~= @{TAG_NIL} then
                    jump hit(value = v)
                end
                jump miss()
            end
        end
    end
    if t.nodes == nil then
        jump miss()
    end
    jump bucket_loop(i = as(index, 0))
end
block bucket_loop(i: index)
    if i > as(index, t.node_mask) then
        jump miss()
    end
    let n: ptr(Node) = t.nodes + i
    jump node_loop(i = i, n = n)
end
block node_loop(i: index, n: ptr(Node))
    if n == nil then
        jump bucket_loop(i = i + 1)
    end
    if n.value.tag ~= @{TAG_NIL} and n.key.tag == key.tag and n.key.bits == key.bits then
        jump hit(value = n.value)
    end
    jump node_loop(i = i, n = n.next)
end
end
]]

-- table_raw_set: direct array or hash store
local table_raw_set = host.region { TAG_INTEGER = I.TAG_INTEGER, TAG_NIL = I.TAG_NIL, ERR_INDEX = I.ERR_INDEX } [[
region table_raw_set(L: ptr(LuaThread), t: ptr(Table), key: Value, value: Value;
                     stored: cont(), resized: cont(), error: cont(code: i32), oom: cont())
entry start()
    -- Try array part first (Lua 5.5 integer keys address the array part)
    if key.tag == @{TAG_INTEGER} and t.array_len > 0 then
        let int_part: i64 = as(i64, key.bits)
        if int_part >= 1 then
            let idx: index = as(index, int_part)
            if idx <= t.array_len then
                t.array[idx - 1] = value
                jump stored()
            end
        end
    end
    if key.tag == @{TAG_NIL} then
        jump error(code = @{ERR_INDEX})
    end
    if t.nodes == nil then
        jump resized()
    end
    jump bucket_loop(i = as(index, 0))
end
block bucket_loop(i: index)
    if i > as(index, t.node_mask) then
        jump resized()
    end
    let n: ptr(Node) = t.nodes + i
    jump node_loop(i = i, n = n)
end
block node_loop(i: index, n: ptr(Node))
    if n == nil then
        jump bucket_loop(i = i + 1)
    end
    if n.value.tag ~= @{TAG_NIL} and n.key.tag == key.tag and n.key.bits == key.bits then
        n.value = value
        jump stored()
    end
    jump node_loop(i = i, n = n.next)
end
end
]]

-- table_get: raw_get then metamethod fallback
local table_get = host.region {
    TAG_NIL = I.TAG_NIL, TAG_TABLE = I.TAG_TABLE,
    ERR_INDEX = I.ERR_INDEX, ERR_LOOP = I.ERR_LOOP,
    TM_INDEX = I.TM_INDEX,
} [[
region table_get(L: ptr(LuaThread), obj: Value, key: Value;
                 value: cont(v: Value),
                 call_mm: cont(mm: Value, self: Value, key: Value),
                 type_error: cont(),
                 loop_error: cont(),
                 oom: cont())
entry start()
    if obj.tag ~= @{TAG_TABLE} then
        jump type_error()
    end
    let t: ptr(Table) = as(ptr(Table), obj.bits)
    emit table_raw_get(t, key;
        hit = raw_hit,
        miss = check_meta)
end
block raw_hit(value: Value)
    jump value(v = value)
end
block check_meta()
    let t: ptr(Table) = as(ptr(Table), obj.bits)
    if t.metatable ~= nil then
        emit get_table_metamethod(L.global, t, as(u8, @{TM_INDEX});
            found = have_index,
            missing = no_index)
    end
    let nil_value: Value = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    jump value(v = nil_value)
end
block have_index(mm: Value)
    jump call_mm(mm = mm, self = obj, key = key)
end
block no_index()
    let nil_value: Value = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    jump value(v = nil_value)
end
block out_of_mem()
    jump oom()
end
end
]]

-- table_set: raw_set then metamethod fallback
local table_set = host.region {
    TAG_TABLE = I.TAG_TABLE, TAG_NIL = I.TAG_NIL, ERR_INDEX = I.ERR_INDEX, ERR_LOOP = I.ERR_LOOP,
    TM_NEWINDEX = I.TM_NEWINDEX,
} [[
region table_set(L: ptr(LuaThread), obj: Value, key: Value, value: Value;
                 stored: cont(),
                 call_mm: cont(mm: Value, self: Value, key: Value, value: Value),
                 type_error: cont(),
                 loop_error: cont(),
                 oom: cont())
entry start()
    if obj.tag ~= @{TAG_TABLE} then
        jump type_error()
    end
    let t: ptr(Table) = as(ptr(Table), obj.bits)
    emit table_raw_set(L, t, key, value;
        stored = did_store,
        resized = did_resize,
        error = set_err,
        oom = out_of_mem)
end
block did_store()
    jump stored()
end
block did_resize()
    jump check_meta()
end
block check_meta()
    let t: ptr(Table) = as(ptr(Table), obj.bits)
    if t.metatable ~= nil then
        emit get_table_metamethod(L.global, t, as(u8, @{TM_NEWINDEX});
            found = have_newindex,
            missing = no_newindex)
    end
    jump oom()
end
block have_newindex(mm: Value)
    jump call_mm(mm = mm, self = obj, key = key, value = value)
end
block no_newindex()
    jump oom()
end
block set_err(code: i32)
    jump type_error()
end
block out_of_mem()
    jump oom()
end
end
]]

-- table_next: iterate over table
local table_next = host.region { TAG_NIL = I.TAG_NIL } [[
region table_next(L: ptr(LuaThread), t: ptr(Table), key: Value;
                  pair: cont(key: Value, value: Value),
                  done: cont(),
                  invalid_key: cont())
entry start()
    jump done()
end
end
]]

-- table_resize: resize array/hash parts
local table_resize = host.region [[
region table_resize(L: ptr(LuaThread), t: ptr(Table), new_array_len: index, new_hash_power: u32;
                    done: cont(), oom: cont())
entry start()
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
}
