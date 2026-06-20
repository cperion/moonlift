-- Focused protocol tests for final-form table regions.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

ffi.cdef [[
void* malloc(size_t size);
void free(void* ptr);
typedef struct GCHeader { struct GCHeader* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct Value { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct Node { Value key; Value value; struct Node* next; } Node;
typedef struct String { GCHeader gc; uint8_t reserved; uint32_t hash; uint64_t len; uint8_t* bytes; } String;
typedef struct Table {
    GCHeader gc;
    uint32_t flags;
    uint64_t array_len;
    uint64_t array_cap;
    Value* array;
    uint32_t node_mask;
    uint64_t node_count;
    Node* nodes;
    Node* lastfree;
    struct Table* metatable;
    uint32_t shape_epoch;
    GCHeader* weak_next;
    uint8_t finalizer_state;
    uint8_t reserved;
} Table;
typedef struct Allocator { uint32_t abi_version; uint32_t flags; uint8_t* userdata; uint8_t* alloc; uint8_t* realloc; uint8_t* free; } Allocator;
typedef struct LuaThread LuaThread;
typedef struct FinalizerQueue { GCHeader* eligible; GCHeader* pending; GCHeader* running; } FinalizerQueue;
typedef struct StringTable { void* buckets; uint64_t bucket_count; uint64_t nuse; } StringTable;
typedef struct GlobalState {
    Allocator* allocator; Value registry; LuaThread* mainthread;
    GCHeader* allgc; GCHeader* gray; GCHeader* grayagain;
    GCHeader* weak_values; GCHeader* weak_keys; GCHeader* ephemeron; GCHeader* all_weak;
    FinalizerQueue finalizers; GCHeader** sweep_cursor; StringTable* string_table; void* tmname;
    uint8_t currentwhite; uint8_t gcstate;
    uint64_t totalbytes; uint64_t estimate; uint64_t threshold; uint64_t gcdebt;
    int32_t gcpause; int32_t gcstepmul; Value panic;
    uint32_t vm_abi_version; uint32_t native_abi_version;
} GlobalState;
struct LuaThread { GCHeader gc; uint8_t status; void* stack; uint64_t stack_size; uint64_t top; void* frames; uint64_t frame_count; uint64_t frame_cap; void* open_upvals; void* protected_top; GlobalState* global; };
]]

local route_next = moon.func { table_next = vm.regions_table.table_next } [[
route_next(t: ptr(Table), key: Value): i32
    return region: i32
    entry start()
        emit @{table_next}(as(ptr(LuaThread), as(u64, 0)), t, key;
            pair = got_pair,
            done = done,
            invalid_key = invalid)
    end
    block got_pair(key: Value, value: Value)
        if value.tag == 4 then
            if value.bits == as(u64, as(i64, 11)) then return 11 end
            if value.bits == as(u64, as(i64, 33)) then return 33 end
            if value.bits == as(u64, as(i64, 100)) then return 100 end
            if value.bits == as(u64, as(i64, 200)) then return 200 end
        end
        return -10
    end
    block done()
        return -1
    end
    block invalid()
        return -2
    end
    end
end
]]:compile()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end
local function vnil()
    return ffi.new("Value", { tag = const.Tag.NIL, aux = 0, bits = 0 })
end
local function vint(x)
    return ffi.new("Value", { tag = const.Tag.INTEGER, aux = 0, bits = ffi.cast("uint64_t", x) })
end
local function vnum(x)
    local u = ffi.new("union { double d; uint64_t u; }")
    u.d = x
    return ffi.new("Value", { tag = const.Tag.NUM, aux = 0, bits = u.u })
end
local function vtable(tptr)
    return ffi.new("Value", { tag = const.Tag.TABLE, aux = 0, bits = ffi.cast("uint64_t", tptr) })
end
local function vstring(sptr)
    return ffi.new("Value", { tag = const.Tag.STR, aux = 0, bits = ffi.cast("uint64_t", sptr) })
end
local function new_string(text)
    local bytes = ffi.new("uint8_t[?]", #text)
    ffi.copy(bytes, text, #text)
    local s = ffi.new("String[1]")
    s[0].len = #text; s[0].bytes = bytes; s[0].hash = 0
    return s, bytes
end

print("=== VM table protocol checks ===\n")

local arr = ffi.new("Value[4]")
for i = 0, 3 do arr[i] = vnil() end
arr[1] = vint(11)
arr[3] = vint(33)
local t = ffi.new("Table[1]")
t[0].array_len = 4
t[0].array_cap = 4
t[0].array = arr
t[0].node_mask = 0
t[0].nodes = nil

check("table_next starts at first non-nil array slot", route_next(t, vnil()) == 11)
check("table_next continues after integer array key", route_next(t, vint(2)) == 33)
check("table_next rejects absent array key", route_next(t, vint(1)) == -2)
check("table_next finishes after last array key", route_next(t, vint(4)) == -1)

local nodes = ffi.new("Node[2]")
nodes[0].key = vint(10); nodes[0].value = vint(100); nodes[0].next = nil
nodes[1].key = vint(20); nodes[1].value = vint(200); nodes[1].next = nil
local ht = ffi.new("Table[1]")
ht[0].array_len = 0
ht[0].array_cap = 0
ht[0].array = nil
ht[0].node_mask = 1
ht[0].nodes = nodes
check("table_next enters hash part", route_next(ht, vnil()) == 100)
check("table_next validates absent key", route_next(ht, vint(99)) == -2)

local route_set = moon.func { table_raw_set = vm.regions_table.table_raw_set } [[
route_set(t: ptr(Table), key: Value, value: Value): i32
    return region: i32
    entry start()
        emit @{table_raw_set}(as(ptr(LuaThread), as(u64, 0)), t, key, value;
            stored = stored,
            resized = resized,
            error = err,
            oom = oom)
    end
    block stored() return 1 end
    block resized() return 2 end
    block err(code: i32) return 0 - code end
    block oom() return -99 end
    end
end
]]:compile()

local arr2 = ffi.new("Value[2]")
arr2[0] = vnil(); arr2[1] = vnil()
local at = ffi.new("Table[1]")
at[0].array_len = 0; at[0].array_cap = 2; at[0].array = arr2
at[0].node_mask = 0; at[0].nodes = nil
check("table_raw_set inserts within existing array capacity", route_set(at, vint(2), vint(55)) == 1 and at[0].array_len == 2 and tonumber(arr2[1].bits) == 55)

local nodes2 = ffi.new("Node[2]")
for i = 0, 1 do nodes2[i].key = vnil(); nodes2[i].value = vnil(); nodes2[i].next = nil end
local ht2 = ffi.new("Table[1]")
ht2[0].array_len = 0; ht2[0].array_cap = 0; ht2[0].array = nil
ht2[0].node_mask = 1; ht2[0].node_count = 0; ht2[0].nodes = nodes2
check("table_raw_set inserts into existing hash capacity", route_set(ht2, vint(7), vint(77)) == 1 and ht2[0].node_count == 1)
check("table_raw_set updates existing hash key", route_set(ht2, vint(7), vint(88)) == 1 and ht2[0].node_count == 1)

local route_get = moon.func { table_raw_get = vm.regions_table.table_raw_get } [[
route_get(t: ptr(Table), key: Value): i32
    return region: i32
    entry start()
        emit @{table_raw_get}(t, key; hit = hit, miss = miss)
    end
    block hit(value: Value)
        if value.tag == 4 then return as(i32, value.bits) end
        return -3
    end
    block miss() return -1 end
    end
end
]]:compile()

local nodes3 = ffi.new("Node[4]")
for i = 0, 3 do nodes3[i].key = vnil(); nodes3[i].value = vnil(); nodes3[i].next = nil end
local kt = ffi.new("Table[1]")
kt[0].array_len = 0; kt[0].array_cap = 0; kt[0].array = nil
kt[0].node_mask = 3; kt[0].node_count = 0; kt[0].nodes = nodes3
check("table_raw_set canonicalizes int/float hash equality", route_set(kt, vint(42), vint(420)) == 1 and route_get(kt, vnum(42.0)) == 420)
check("table_raw_set deletes hash entries with nil value", route_set(kt, vnum(42.0), vnil()) == 1 and route_get(kt, vint(42)) == -1 and kt[0].node_count == 0)

local realloc_cb = ffi.cast("uint64_t (*)(uint8_t*, uint64_t, uint64_t, uint64_t)",
    function(old, old_size, new_size, align)
        if new_size == 0 then
            if old ~= nil then ffi.C.free(old) end
            return ffi.cast("uint64_t", 0)
        end
        local p = ffi.C.malloc(tonumber(new_size))
        if p == nil then return ffi.cast("uint64_t", 0) end
        return ffi.cast("uint64_t", ffi.cast("uintptr_t", p))
    end)
local alloc = ffi.new("Allocator[1]")
alloc[0].realloc = ffi.cast("uint8_t*", realloc_cb)
local G = ffi.new("GlobalState[1]")
G[0].allocator = alloc; G[0].threshold = 1024 * 1024; G[0].totalbytes = 0
local L = ffi.new("LuaThread[1]")
L[0].global = G

local route_resize = moon.func { table_resize = vm.regions_table.table_resize } [[
route_resize(L: ptr(LuaThread), t: ptr(Table), array_len: index, hash_power: u32): i32
    return region: i32
    entry start()
        emit @{table_resize}(L, t, array_len, hash_power; done = done, oom = oom)
    end
    block done() return 1 end
    block oom() return -1 end
    end
end
]]:compile()

local old_nodes = ffi.new("Node[2]")
for i = 0, 1 do old_nodes[i].key = vnil(); old_nodes[i].value = vnil(); old_nodes[i].next = nil end
old_nodes[0].key = vint(99); old_nodes[0].value = vint(990); old_nodes[0].next = nil
old_nodes[1].key = vnum(3.0); old_nodes[1].value = vint(30); old_nodes[1].next = nil
local rt = ffi.new("Table[1]")
rt[0].array_len = 0; rt[0].array_cap = 0; rt[0].array = nil
rt[0].node_mask = 1; rt[0].node_count = 2; rt[0].nodes = old_nodes
check("table_resize rehashes existing hash entries", route_resize(L, rt, 4, 3) == 1 and route_get(rt, vint(99)) == 990)
check("table_resize moves canonical integral numeric key into array part", route_get(rt, vint(3)) == 30 and rt[0].array_len == 3)

local route_grow = moon.func { table_grow_for_key = vm.regions_table.table_grow_for_key } [[
route_grow(L: ptr(LuaThread), t: ptr(Table), key: Value): i32
    return region: i32
    entry start()
        emit @{table_grow_for_key}(L, t, key; done = done, error = err, oom = oom)
    end
    block done() return 1 end
    block err(code: i32) return 0 - code end
    block oom() return -99 end
    end
end
]]:compile()

local gt = ffi.new("Table[1]")
gt[0].array_len = 0; gt[0].array_cap = 0; gt[0].array = nil; gt[0].nodes = nil; gt[0].node_mask = 0; gt[0].node_count = 0
check("table_grow_for_key expands array capacity for integer key", route_grow(L, gt, vint(5)) == 1 and gt[0].array_cap >= 5)
check("table_raw_set stores after explicit grow", route_set(gt, vint(5), vint(505)) == 1 and route_get(gt, vint(5)) == 505)

local route_table_get = moon.func { table_get = vm.regions_table.table_get } [[
route_table_get(L: ptr(LuaThread), obj: Value, key: Value): i32
    return region: i32
    entry start()
        emit @{table_get}(L, obj, key;
            value = got_value,
            call_mm = call_mm,
            type_error = type_error,
            loop_error = loop_error,
            oom = oom)
    end
    block got_value(v: Value)
        if v.tag == 4 then return as(i32, v.bits) end
        if v.tag == 0 then return -1 end
        return -9
    end
    block call_mm(mm: Value, self: Value, key: Value) return -20 end
    block type_error() return -30 end
    block loop_error() return -40 end
    block oom() return -99 end
    end
end
]]:compile()

local route_table_set = moon.func { table_set = vm.regions_table.table_set } [[
route_table_set(L: ptr(LuaThread), obj: Value, key: Value, value: Value): i32
    return region: i32
    entry start()
        emit @{table_set}(L, obj, key, value;
            stored = stored,
            call_mm = call_mm,
            type_error = type_error,
            loop_error = loop_error,
            oom = oom)
    end
    block stored() return 1 end
    block call_mm(mm: Value, self: Value, key: Value, value: Value) return -20 end
    block type_error() return -30 end
    block loop_error() return -40 end
    block oom() return -99 end
    end
end
]]:compile()

local index_name = new_string("__index")
local newindex_name = new_string("__newindex")
local tmnames = ffi.new("String*[?]", const.TM.N)
tmnames[const.TM.INDEX] = index_name
tmnames[const.TM.NEWINDEX] = newindex_name
G[0].tmname = ffi.cast("void*", tmnames)

local fallback_nodes = ffi.new("Node[4]")
for i = 0, 3 do fallback_nodes[i].key = vnil(); fallback_nodes[i].value = vnil(); fallback_nodes[i].next = nil end
local fallback = ffi.new("Table[1]")
fallback[0].array_len = 0; fallback[0].array_cap = 0; fallback[0].array = nil; fallback[0].node_mask = 3; fallback[0].node_count = 0; fallback[0].nodes = fallback_nodes
assert(route_set(fallback, vint(9), vint(900)) == 1)

local mt_nodes = ffi.new("Node[8]")
for i = 0, 7 do mt_nodes[i].key = vnil(); mt_nodes[i].value = vnil(); mt_nodes[i].next = nil end
local mt = ffi.new("Table[1]")
mt[0].array_len = 0; mt[0].array_cap = 0; mt[0].array = nil; mt[0].node_mask = 7; mt[0].node_count = 0; mt[0].nodes = mt_nodes
assert(route_set(mt, vstring(index_name), vtable(fallback)) == 1)

local main_nodes = ffi.new("Node[4]")
for i = 0, 3 do main_nodes[i].key = vnil(); main_nodes[i].value = vnil(); main_nodes[i].next = nil end
local main = ffi.new("Table[1]")
main[0].array_len = 0; main[0].array_cap = 0; main[0].array = nil; main[0].node_mask = 3; main[0].node_count = 0; main[0].nodes = main_nodes; main[0].metatable = mt
check("table_get follows table-valued __index chain", route_table_get(L, vtable(main), vint(9)) == 900)

local dest_nodes = ffi.new("Node[4]")
for i = 0, 3 do dest_nodes[i].key = vnil(); dest_nodes[i].value = vnil(); dest_nodes[i].next = nil end
local dest = ffi.new("Table[1]")
dest[0].array_len = 0; dest[0].array_cap = 0; dest[0].array = nil; dest[0].node_mask = 3; dest[0].node_count = 0; dest[0].nodes = dest_nodes
assert(route_set(mt, vstring(newindex_name), vtable(dest)) == 1)
check("table_set follows table-valued __newindex chain", route_table_set(L, vtable(main), vint(11), vint(1100)) == 1 and route_get(dest, vint(11)) == 1100 and route_get(main, vint(11)) == -1)

route_table_set:free()
route_table_get:free()
route_grow:free()
route_resize:free()
realloc_cb:free()
route_get:free()
route_set:free()
route_next:free()
print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
