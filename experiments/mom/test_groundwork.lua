package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

ffi.cdef[[
typedef struct MomI32Builder {
    int32_t *data;
    size_t len;
    size_t cap;
} MomI32Builder;

typedef struct MomIssueBuilder {
    int32_t *tag;
    int32_t *a;
    int32_t *b;
    int32_t *c;
    int32_t *d;
    size_t len;
    size_t cap;
} MomIssueBuilder;

typedef struct MomI32Map {
    int32_t *key;
    int32_t *value;
    int32_t *state;
    size_t len;
    size_t cap;
} MomI32Map;

typedef struct MomBackIdAllocator {
    int32_t next_value;
    int32_t next_block;
    int32_t next_access;
    int32_t next_slot;
} MomBackIdAllocator;

typedef struct MomBackLocalEnv {
    int32_t *name;
    int32_t *kind;
    int32_t *scalar;
    int32_t *val;
    int32_t *aux0;
    int32_t *aux1;
    size_t len;
    size_t cap;
} MomBackLocalEnv;

typedef struct MomBackLocal {
    int32_t kind;
    int32_t scalar;
    int32_t val;
    int32_t aux0;
    int32_t aux1;
} MomBackLocal;
]]

local function compile(path)
    local mod = Host.dofile(path)
    return mod:compile()
end

local builders = compile("experiments/mom/runtime/builders.mlua")
local sets = compile("experiments/mom/runtime/sets.mlua")
local ids = compile("experiments/mom/back/ids.mlua")
local env_mod = compile("experiments/mom/back/env.mlua")
local ops = compile("experiments/mom/back/ops.mlua")

local push_i32 = builders:get("mr_i32_builder_push")
local reset_i32 = builders:get("mr_i32_builder_reset")
local overflow_i32 = builders:get("mr_i32_builder_overflowed")
local push_issue = builders:get("mr_issue_push4")
local reset_issue = builders:get("mr_issue_builder_reset")
local overflow_issue = builders:get("mr_issue_builder_overflowed")

local bi_data = ffi.new("int32_t[2]")
local bi = ffi.new("MomI32Builder")
bi.data = bi_data
bi.len = 0
bi.cap = 2
assert(tonumber(push_i32(bi, 10)) == 0)
assert(tonumber(push_i32(bi, 20)) == 1)
assert(tonumber(push_i32(bi, 30)) == 2)
assert(bi.len == 3)
assert(bi_data[0] == 10 and bi_data[1] == 20)
assert(overflow_i32(bi) == true)
reset_i32(bi)
assert(bi.len == 0 and overflow_i32(bi) == false)

local ib = ffi.new("MomIssueBuilder")
local tag = ffi.new("int32_t[1]")
local a = ffi.new("int32_t[1]")
local b = ffi.new("int32_t[1]")
local c = ffi.new("int32_t[1]")
local d = ffi.new("int32_t[1]")
ib.tag = tag; ib.a = a; ib.b = b; ib.c = c; ib.d = d; ib.len = 0; ib.cap = 1
assert(tonumber(push_issue(ib, 7, 1, 2, 3, 4)) == 0)
assert(tag[0] == 7 and a[0] == 1 and b[0] == 2 and c[0] == 3 and d[0] == 4)
assert(tonumber(push_issue(ib, 8, 5, 6, 7, 8)) == 1)
assert(ib.len == 2 and overflow_issue(ib) == true)
reset_issue(ib)
assert(ib.len == 0 and overflow_issue(ib) == false)

local map_reset = sets:get("mr_i32_map_reset")
local map_put = sets:get("mr_i32_map_put")
local map_get_or = sets:get("mr_i32_map_get_or")
local map_contains = sets:get("mr_i32_map_contains")
local map_full = sets:get("mr_i32_map_full")
local mp = ffi.new("MomI32Map")
local mk = ffi.new("int32_t[4]")
local mv = ffi.new("int32_t[4]")
local ms = ffi.new("int32_t[4]")
mp.key = mk; mp.value = mv; mp.state = ms; mp.len = 0; mp.cap = 4
map_reset(mp)
assert(mp.len == 0 and map_full(mp) == false)
assert(map_put(mp, 0, 10) == true)
assert(map_put(mp, 4, 40) == true)
assert(map_put(mp, 8, 80) == true)
assert(map_get_or(mp, 0, -1) == 10)
assert(map_get_or(mp, 4, -1) == 40)
assert(map_get_or(mp, 8, -1) == 80)
assert(map_get_or(mp, 12, -1) == -1)
assert(map_contains(mp, 4) == true and map_contains(mp, 12) == false)
assert(map_put(mp, 4, 41) == true and map_get_or(mp, 4, -1) == 41 and mp.len == 3)
assert(map_put(mp, 12, 120) == true and map_full(mp) == true)
assert(map_put(mp, 16, 160) == false)

local reset_ids = ids:get("mb_ids_reset_func")
local fresh_value = ids:get("mb_fresh_value")
local fresh_block = ids:get("mb_fresh_block")
local fresh_access = ids:get("mb_fresh_access")
local fresh_slot = ids:get("mb_fresh_slot")
local ida = ffi.new("MomBackIdAllocator")
reset_ids(ida)
assert(fresh_value(ida) == 1 and fresh_value(ida) == 2)
assert(fresh_block(ida) == 1)
assert(fresh_access(ida) == 1)
assert(fresh_slot(ida) == 1)
reset_ids(ida)
assert(fresh_value(ida) == 1 and fresh_block(ida) == 1)

local env_reset = env_mod:get("mb_env_reset")
local env_mark = env_mod:get("mb_env_mark")
local env_truncate = env_mod:get("mb_env_truncate")
local env_overflowed = env_mod:get("mb_env_overflowed")
local bind_scalar = env_mod:get("mb_env_bind_scalar")
local bind_view = env_mod:get("mb_env_bind_view")
local lookup = env_mod:get("mb_env_lookup")
local lookup_into = env_mod:get("mb_env_lookup_into")
local kind_is_value = env_mod:get("mb_local_kind_is_value")
local kind_is_view = env_mod:get("mb_local_kind_is_view")

local e = ffi.new("MomBackLocalEnv")
local n = ffi.new("int32_t[3]")
local k = ffi.new("int32_t[3]")
local s = ffi.new("int32_t[3]")
local v = ffi.new("int32_t[3]")
local x = ffi.new("int32_t[3]")
local y = ffi.new("int32_t[3]")
e.name = n; e.kind = k; e.scalar = s; e.val = v; e.aux0 = x; e.aux1 = y; e.len = 0; e.cap = 3
assert(tonumber(bind_scalar(e, 101, 5, 11)) == 0)
local mark = env_mark(e)
assert(tonumber(bind_view(e, 202, 7, 21, 22, 23)) == 1)
assert(tonumber(bind_scalar(e, 101, 6, 12)) == 2)
assert(lookup(e, 101) == 2)
assert(lookup(e, 202) == 1)
assert(lookup(e, 303) == -1)
local out = ffi.new("MomBackLocal")
assert(lookup_into(e, 101, out) == true)
assert(out.kind == 1 and out.scalar == 6 and out.val == 12)
assert(kind_is_value(out.kind) == true and kind_is_view(out.kind) == false)
assert(lookup_into(e, 202, out) == true)
assert(out.kind == 2 and out.scalar == 7 and out.val == 21 and out.aux0 == 22 and out.aux1 == 23)
assert(kind_is_view(out.kind) == true)
assert(tonumber(bind_scalar(e, 303, 5, 31)) == 3)
assert(e.len == 4 and env_overflowed(e) == true)
env_truncate(e, mark)
assert(e.len == mark and lookup(e, 202) == -1 and lookup(e, 101) == 0 and env_overflowed(e) == false)
env_reset(e)
assert(e.len == 0 and lookup(e, 101) == -1)

local is_float = ops:get("mb_is_float_scalar")
local scalar_to_back = ops:get("mb_core_scalar_to_back")
local unary = ops:get("mb_lower_unary_op")
local cmp = ops:get("mb_lower_compare_op")
local bin_class = ops:get("mb_binary_class")
local bin_code = ops:get("mb_binary_op_code")

-- Back scalar tags: F32=11, I32=5. Core ScalarRawPtr=13 maps to BackPtr=13.
assert(is_float(11) == true and is_float(5) == false)
assert(scalar_to_back(13) == 13)
assert(scalar_to_back(14) == 14)
-- UnaryNeg: integer -> BackUnaryIneg(1), float -> BackUnaryFneg(2).
assert(unary(1, 5) == 1)
assert(unary(1, 11) == 2)
-- CmpLt: integer -> BackSIcmpLt(3), float -> BackFCmpLt(13).
assert(cmp(3, 5) == 3)
assert(cmp(3, 11) == 13)
-- BinAdd: integer class/op Int/Add, float class/op Float/Add.
assert(bin_class(1, 5) == 1 and bin_code(1, 5) == 1)
assert(bin_class(1, 11) == 2 and bin_code(1, 11) == 1)
-- Bit and shift classes.
assert(bin_class(6, 5) == 3 and bin_code(6, 5) == 1)
assert(bin_class(10, 5) == 4 and bin_code(10, 5) == 2)

ops.artifact:free()
env_mod.artifact:free()
ids.artifact:free()
sets.artifact:free()
builders.artifact:free()

print("mom groundwork ok")
