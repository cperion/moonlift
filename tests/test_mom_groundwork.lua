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

local builders = compile("lua/moonlift/mom/runtime/builders.mlua")
local sets = compile("lua/moonlift/mom/runtime/sets.mlua")
local ids = compile("lua/moonlift/mom/back/ids.mlua")
local env_mod = compile("lua/moonlift/mom/back/env.mlua")
local ops = compile("lua/moonlift/mom/back/ops.mlua")

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

-- Phase 2: lower_cast_op (MachineCastOp → BackCastOp).
-- MachineCastOp tags: Identity=1, Bitcast=2, Ireduce=3, Sextend=4, Uextend=5,
-- Fpromote=6, Fdemote=7, SToF=8, UToF=9, FToS=10, FToU=11.
-- BackCastOp tags: Bitcast=1, Ireduce=2, Sextend=3, Uextend=4, Fpromote=5,
-- Fdemote=6, SToF=7, UToF=8, FToS=9, FToU=10.
local cast = ops:get("mb_lower_cast_op")
assert(cast(2) == 1,  "Bitcast")     -- MachineCastBitcast → BackBitcast
assert(cast(3) == 2,  "Ireduce")     -- MachineCastIreduce → BackIreduce
assert(cast(4) == 3,  "Sextend")     -- MachineCastSextend → BackSextend
assert(cast(5) == 4,  "Uextend")     -- MachineCastUextend → BackUextend
assert(cast(6) == 5,  "Fpromote")    -- MachineCastFpromote → BackFpromote
assert(cast(7) == 6,  "Fdemote")     -- MachineCastFdemote → BackFdemote
assert(cast(8) == 7,  "SToF")        -- MachineCastSToF → BackSToF
assert(cast(9) == 8,  "UToF")        -- MachineCastUToF → BackUToF
assert(cast(10) == 9, "FToS")        -- MachineCastFToS → BackFToS
assert(cast(11) == 10, "FToU")       -- MachineCastFToU → BackFToU
-- Identity (1) has no BackCast — returns 0.
assert(cast(1) == 0,  "Identity")
-- Unknown tag.
assert(cast(99) == 0, "Unknown cast")

-- Phase 2: lower_surface_cast_op (SurfaceCastOp → MachineCastOp).
-- SurfaceCastOp tags: SurfaceCast=1, SurfaceTrunc=2, SurfaceZExt=3,
-- SurfaceSExt=4, SurfaceBitcast=5, SurfaceSatCast=6.
local scast = ops:get("mb_lower_surface_cast_op")
assert(scast(1) == 2, "SurfaceCast → MachineCastBitcast")
assert(scast(2) == 3, "SurfaceTrunc → MachineCastIreduce")
assert(scast(3) == 5, "SurfaceZExt → MachineCastUextend")
assert(scast(4) == 4, "SurfaceSExt → MachineCastSextend")
assert(scast(5) == 2, "SurfaceBitcast → MachineCastBitcast")
assert(scast(6) == 2, "SurfaceSatCast → MachineCastBitcast")
assert(scast(99) == 0, "Unknown surface cast")

-- Phase 2: lower_atomic_ordering (AtomicOrdering → BackAtomicOrdering).
-- Both have one variant: AtomicSeqCst = 1.
local ao = ops:get("mb_lower_atomic_ordering")
assert(ao(1) == 1, "AtomicSeqCst")
assert(ao(99) == 0, "Unknown ordering")

-- Phase 2: lower_atomic_rmw_op (AtomicRmwOp → BackAtomicRmwOp).
-- Both share ordering: Add=1, Sub=2, And=3, Or=4, Xor=5, Xchg=6.
local rmw = ops:get("mb_lower_atomic_rmw_op")
assert(rmw(1) == 1, "RmwAdd")
assert(rmw(2) == 2, "RmwSub")
assert(rmw(3) == 3, "RmwAnd")
assert(rmw(4) == 4, "RmwOr")
assert(rmw(5) == 5, "RmwXor")
assert(rmw(6) == 6, "RmwXchg")
assert(rmw(99) == 0, "Unknown rmw")

-- Phase 2: type_to_back_scalar (Type union tag → BackScalar).
-- Type tags: TScalar=1, TPtr=2, TFunc=6, TCFuncPtr=11 → BackScalar.
-- Extract the scalar sub-tag from the semantic Type node.
-- scalar=5 is Core I32, scalar=11 is Core F32.
local ttbs = ops:get("mb_type_to_back_scalar")
-- TScalar with I32 → BackI32 (5)
assert(ttbs(1, 5) == 5, "TScalar i32")
-- TScalar with F32 → BackF32 (11)
assert(ttbs(1, 11) == 11, "TScalar f32")
-- TScalar with Bool → BackBool (2)
assert(ttbs(1, 2) == 2, "TScalar bool")
-- TScalar with RawPtr → BackPtr (13)
assert(ttbs(1, 13) == 13, "TScalar rawptr")
-- TPtr → BackPtr (13)
assert(ttbs(2, 0) == 13, "TPtr")
-- TFunc → BackPtr (13)
assert(ttbs(6, 0) == 13, "TFunc")
-- TCFuncPtr → BackPtr (13)
assert(ttbs(11, 0) == 13, "TCFuncPtr")
-- Unsupported types → 0
assert(ttbs(3, 0) == 0, "TArray unsupported")
assert(ttbs(4, 0) == 0, "TSlice unsupported")
assert(ttbs(5, 0) == 0, "TView unsupported")
assert(ttbs(7, 0) == 0, "TClosure unsupported")
assert(ttbs(99, 0) == 0, "Unknown type")

ops.artifact:free()

-- Phase 3: Command-producing functions (back/cmd.mlua)
local cmd_mod = compile("lua/moonlift/mom/back/cmd.mlua")

local lower_binary = cmd_mod:get("mb_lower_binary")
local lower_unary = cmd_mod:get("mb_lower_unary_cmd")
local lower_compare = cmd_mod:get("mb_lower_compare")
local lower_cast = cmd_mod:get("mb_lower_cast_cmd")

-- CmdEntry FFI struct must match MOM struct layout.
ffi.cdef[[
typedef struct { int32_t tag, a, b, c, d, e, f; } CmdEntry;
]]
local CmdEntry_t = ffi.typeof("CmdEntry")

-- Test lower_binary:
-- BIN_ADD=1, I32=5 → CmdIntBinary(CMD_INT_BINARY=33, dst=10, BACK_INT_ADD=1, scalar=5, lhs=20, rhs=30)
-- sem_packed: BackIntWrap=1, BackIntMayLose=1 → (1<<16)|1 = 65537
local e = CmdEntry_t()
lower_binary(1, 5, 10, 20, 30, 65537, e)
assert(e.tag == 33, "binary add i32 tag: " .. tonumber(e.tag))
assert(e.a == 10 and e.b == 1 and e.c == 5, "binary add i32 fields")
assert(e.d == 65537 and e.e == 20 and e.f == 30, "binary add i32 sem/lhs/rhs")

-- BIN_ADD=1, F32=11 → CmdFloatBinary(CMD_FLOAT_BINARY=38, dst=11, BACK_FLOAT_ADD=1, scalar=11, lhs=21, rhs=31)
-- Float sem = BackFloatStrict = 1
e = CmdEntry_t()
lower_binary(1, 11, 11, 21, 31, 1, e)
assert(e.tag == 38, "binary add f32 tag: " .. tonumber(e.tag))
assert(e.a == 11 and e.b == 1 and e.c == 11, "binary add f32 fields")
assert(e.e == 21 and e.f == 31, "binary add f32 lhs/rhs")

-- BIN_BIT_AND=6 → CmdBitBinary(CMD_BIT_BINARY=34, dst=12, BACK_BIT_AND=1, scalar=5, lhs=22, rhs=32)
e = CmdEntry_t()
lower_binary(6, 5, 12, 22, 32, 0, e)
assert(e.tag == 34, "binary bit and tag: " .. tonumber(e.tag))
assert(e.a == 12 and e.b == 1 and e.c == 5 and e.d == 22 and e.e == 32, "binary bit and fields")

-- BIN_SHL=9 → CmdShift(CMD_SHIFT=36, dst=13, BACK_SHIFT_LEFT=1, scalar=5, lhs=23, rhs=33)
e = CmdEntry_t()
lower_binary(9, 5, 13, 23, 33, 0, e)
assert(e.tag == 36, "binary shl tag: " .. tonumber(e.tag))
assert(e.a == 13 and e.b == 1 and e.c == 5 and e.d == 23 and e.e == 33, "binary shl fields")

-- Invalid binary op → CmdTrap(CMD_TRAP=57)
e = CmdEntry_t()
lower_binary(99, 5, 0, 0, 0, 0, e)
assert(e.tag == 57, "binary invalid trap: " .. tonumber(e.tag))

-- Test lower_unary_cmd:
-- U_NEG=1, I32=5 → CmdUnary(21, dst=10, BACK_UNARY_INEG=1, shape_tag=1, scalar=5, value=20)
e = CmdEntry_t()
lower_unary(1, 5, 10, 20, 1, e)
assert(e.tag == 21, "unary neg i32 tag: " .. tonumber(e.tag))
assert(e.a == 10 and e.b == 1 and e.c == 1 and e.d == 5 and e.e == 20, "unary neg i32 fields")

-- U_NEG=1, F32=11 → CmdUnary(21, dst=11, BACK_UNARY_FNEG=2)
e = CmdEntry_t()
lower_unary(1, 11, 11, 21, 1, e)
assert(e.tag == 21, "unary neg f32 tag: " .. tonumber(e.tag))
assert(e.b == 2, "unary neg f32 op: " .. tonumber(e.b))

-- U_NOT=2 → BACK_UNARY_BOOL_NOT=4
e = CmdEntry_t()
lower_unary(2, 5, 10, 20, 1, e)
assert(e.b == 4, "unary not op: " .. tonumber(e.b))

-- U_BIT_NOT=3 → BACK_UNARY_BNOT=3
e = CmdEntry_t()
lower_unary(3, 5, 10, 20, 1, e)
assert(e.b == 3, "unary bitnot op: " .. tonumber(e.b))

-- Test lower_compare:
-- CMP_EQ=1, I32=5 → CmdCompare(23, dst=10, BACK_ICMP_EQ=1, shape_tag=1, scalar=5, lhs=20, rhs=30)
e = CmdEntry_t()
lower_compare(1, 5, 10, 20, 30, 1, e)
assert(e.tag == 23, "compare eq i32 tag: " .. tonumber(e.tag))
assert(e.a == 10 and e.b == 1 and e.c == 1 and e.d == 5 and e.e == 20 and e.f == 30, "compare eq i32 fields")

-- CMP_EQ=1, F32=11 → BACK_FCMP_EQ=11
e = CmdEntry_t()
lower_compare(1, 11, 10, 20, 30, 1, e)
assert(e.b == 11, "compare eq f32 op: " .. tonumber(e.b))

-- CMP_LT=3, I32=5 → BACK_SICMP_LT=3
e = CmdEntry_t()
lower_compare(3, 5, 10, 20, 30, 1, e)
assert(e.b == 3, "compare lt i32 op: " .. tonumber(e.b))

-- CMP_LT=3, U32=9 → BACK_UICMP_LT=7
e = CmdEntry_t()
lower_compare(3, 9, 10, 20, 30, 1, e)
assert(e.b == 7, "compare lt u32 op: " .. tonumber(e.b))

-- CMP_LT=3, F32=11 → BACK_FCMP_LT=13
e = CmdEntry_t()
lower_compare(3, 11, 10, 20, 30, 1, e)
assert(e.b == 13, "compare lt f32 op: " .. tonumber(e.b))

-- Test lower_cast_cmd:
-- MC_BITCAST=2 → CmdCast(CMD_CAST=24, dst=10, BACK_BITCAST=1, scalar=5, value=20)
e = CmdEntry_t()
lower_cast(2, 5, 10, 20, e)
assert(e.tag == 24, "cast bitcast tag: " .. tonumber(e.tag))
assert(e.a == 10 and e.b == 1 and e.c == 5 and e.d == 20, "cast bitcast fields")

-- MC_SEXTEND=4 → BACK_SEXTEND=3
e = CmdEntry_t()
lower_cast(4, 5, 11, 21, e)
assert(e.b == 3, "cast sextend op: " .. tonumber(e.b))

-- MC_FPROMOTE=6 → BACK_FPROMOTE=5
e = CmdEntry_t()
lower_cast(6, 5, 12, 22, e)
assert(e.b == 5, "cast fpromote op: " .. tonumber(e.b))

-- MC_STOF=8 → BACK_STOF=7
e = CmdEntry_t()
lower_cast(8, 5, 13, 23, e)
assert(e.b == 7, "cast stof op: " .. tonumber(e.b))

-- MC_IDENTITY=1 → CmdTrap (no backend op)
e = CmdEntry_t()
lower_cast(1, 5, 10, 20, e)
assert(e.tag == 57, "cast identity trap: " .. tonumber(e.tag))

cmd_mod.artifact:free()

-- Phase 4: Expression lowering (back/expr_lower.mlua)
local expr_mod = compile("lua/moonlift/mom/back/expr_lower.mlua")
local lower_lit = expr_mod:get("mb_lower_lit")
local lower_ref = expr_mod:get("mb_lower_ref")
local lower_unary = expr_mod:get("mb_lower_unary_expr")
local lower_binary = expr_mod:get("mb_lower_binary_expr")
local lower_compare = expr_mod:get("mb_lower_compare_expr")
local lower_select = expr_mod:get("mb_lower_select_expr")

-- Command buffer: flat array of 7-int cmd entries.
-- st = { cmd_count, next_value, capacity }
local cap = 64
local st = ffi.new("int32_t[3]", 0, 0, cap)
local cmds = ffi.new("int32_t[?]", cap * 7)

-- Test lower_lit: TK_INT=2 → CmdConst(20, val=1, scalar=B_I32=5, tok=2)
local val = lower_lit(2, st, cmds)
assert(val == 1, "lit val: " .. tonumber(val))
assert(st[0] == 1, "cmd count after lit: " .. tonumber(st[0]))
assert(st[1] == 1, "next val after lit: " .. tonumber(st[1]))
assert(cmds[0] == 20, "cmd tag: " .. tonumber(cmds[0]))  -- CMD_CONST
assert(cmds[1] == 1, "cmd dst: " .. tonumber(cmds[1]))   -- val=1
assert(cmds[2] == 5, "cmd scalar: " .. tonumber(cmds[2])) -- B_I32

-- Test lower_lit with bool: TK_TRUE=140 → scalar=B_BOOL=2
local st2 = ffi.new("int32_t[3]", 1, 1, cap)
local cmds2 = ffi.new("int32_t[?]", cap * 7)
cmds2[0] = -1  -- sentinel
lower_lit(140, st2, cmds2)
-- new entry at index 1 (offset 7)
assert(cmds2[7] == 20, "bool cmd tag")
assert(cmds2[9] == 2, "bool scalar: " .. tonumber(cmds2[9]))

-- Test lower_binary_expr: TK_PLUS=20, scalar=B_I32=5, left=2, right=3
-- Should emit CmdIntBinary(33, dst=2, BACK_INT_ADD=1, scalar=5, sem=65537, lhs=2, rhs=3)
local st3 = ffi.new("int32_t[3]", 0, 1, cap)
local cmds3 = ffi.new("int32_t[?]", cap * 7)
local r = lower_binary(20, 5, 2, 3, st3, cmds3)
assert(r == 2, "binary result val: " .. tonumber(r))
assert(cmds3[0] == 33, "binary tag: " .. tonumber(cmds3[0]))  -- CMD_INT_BINARY
assert(cmds3[1] == 2, "binary dst: " .. tonumber(cmds3[1]))
assert(cmds3[2] == 1, "binary op: " .. tonumber(cmds3[2]))    -- BACK_INT_ADD
assert(cmds3[3] == 5, "binary scalar: " .. tonumber(cmds3[3]))
assert(cmds3[4] == 65537, "binary sem: " .. tonumber(cmds3[4]))
assert(cmds3[5] == 2, "binary lhs: " .. tonumber(cmds3[5]))
assert(cmds3[6] == 3, "binary rhs: " .. tonumber(cmds3[6]))

-- Test lower_compare: TK_EQEQ=27, scalar=B_I32=5, lhs=4, rhs=5
-- → CmdCompare(23, dst=3, BACK_ICMP_EQ=1, shape=1, scalar=5, lhs=4, rhs=5)
local st4 = ffi.new("int32_t[3]", 0, 2, cap)
local cmds4 = ffi.new("int32_t[?]", cap * 7)
r = lower_compare(27, 5, 4, 5, st4, cmds4)
assert(r == 3, "compare result val: " .. tonumber(r))
assert(cmds4[0] == 23, "compare tag: " .. tonumber(cmds4[0]))
assert(cmds4[1] == 3, "compare dst: " .. tonumber(cmds4[1]))
assert(cmds4[2] == 1, "compare op: " .. tonumber(cmds4[2]))   -- BACK_ICMP_EQ
assert(cmds4[3] == 1, "compare shape: " .. tonumber(cmds4[3]))
assert(cmds4[4] == 5, "compare scalar: " .. tonumber(cmds4[4]))

-- Test lower_unary_expr: TK_MINUS=21, scalar=B_I32=5, child=6
-- → CmdUnary(21, dst=4, BACK_UNARY_INEG=1, shape=1, scalar=5, value=6)
local st5 = ffi.new("int32_t[3]", 0, 3, cap)
local cmds5 = ffi.new("int32_t[?]", cap * 7)
r = lower_unary(21, 5, 6, st5, cmds5)
assert(r == 4, "unary result val: " .. tonumber(r))
assert(cmds5[0] == 21, "unary tag: " .. tonumber(cmds5[0]))
assert(cmds5[1] == 4, "unary dst: " .. tonumber(cmds5[1]))
assert(cmds5[2] == 1, "unary op: " .. tonumber(cmds5[2]))    -- BACK_UNARY_INEG
assert(cmds5[3] == 1, "unary shape: " .. tonumber(cmds5[3]))
assert(cmds5[4] == 5, "unary scalar: " .. tonumber(cmds5[4]))
assert(cmds5[5] == 6, "unary child: " .. tonumber(cmds5[5]))

-- Test lower_select: scalar=B_I32=5, cond=7, then=8, else=9
-- → CmdSelect(42, dst=5, shape=1, cond=7, then=8, else=9)
local st6 = ffi.new("int32_t[3]", 0, 4, cap)
local cmds6 = ffi.new("int32_t[?]", cap * 7)
r = lower_select(5, 7, 8, 9, st6, cmds6)
assert(r == 5, "select result val: " .. tonumber(r))
assert(cmds6[0] == 42, "select tag: " .. tonumber(cmds6[0]))
assert(cmds6[1] == 5, "select dst: " .. tonumber(cmds6[1]))
assert(cmds6[3] == 7, "select cond: " .. tonumber(cmds6[3]))
assert(cmds6[4] == 8, "select then: " .. tonumber(cmds6[4]))
assert(cmds6[5] == 9, "select else: " .. tonumber(cmds6[5]))

expr_mod.artifact:free()

-- Phase 5: Statement lowering (back/stmt_lower.mlua)
local stmt_mod = compile("lua/moonlift/mom/back/stmt_lower.mlua")
local lower_return_void = stmt_mod:get("mb_lower_return_void")
local lower_return_value = stmt_mod:get("mb_lower_return_value")
local lower_expr_stmt = stmt_mod:get("mb_lower_expr_stmt")

-- Test ST_RETURN_VOID
local st_rv = ffi.new("int32_t[3]", 0, 0, cap)
local cmds_rv = ffi.new("int32_t[?]", cap * 7)
lower_return_void(st_rv, cmds_rv)
assert(st_rv[0] == 1, "return void cmd count: " .. tonumber(st_rv[0]))
assert(cmds_rv[0] == 55, "return void tag: " .. tonumber(cmds_rv[0]))

-- Test ST_RETURN_VALUE with a literal expr
-- Create an expr tape with EX_LIT(1), tok_kind=TK_INT(2)
local etag = ffi.new("int32_t[1]", 1)   -- EX_LIT
local ea = ffi.new("int32_t[1]", 2)     -- TK_INT
local eb = ffi.new("int32_t[1]", 0)
local ec = ffi.new("int32_t[1]", 0)
local ed = ffi.new("int32_t[1]", 0)
local st_rv2 = ffi.new("int32_t[3]", 0, 0, cap)
local cmds_rv2 = ffi.new("int32_t[?]", cap * 7)
lower_return_value(etag, ea, eb, ec, ed, 0, st_rv2, cmds_rv2)
assert(st_rv2[0] >= 2, "return value cmd count: " .. tonumber(st_rv2[0]))
-- First cmd should be CMD_CONST(20) for the literal
assert(cmds_rv2[0] == 20, "return value const tag: " .. tonumber(cmds_rv2[0]))
-- Last cmd should be CMD_RETURN_VALUE(56)
assert(cmds_rv2[7] == 56, "return value cmd tag: " .. tonumber(cmds_rv2[7]))

-- Test ST_EXPR with a literal expr
local st_ex = ffi.new("int32_t[3]", 0, 0, cap)
local cmds_ex = ffi.new("int32_t[?]", cap * 7)
lower_expr_stmt(etag, ea, eb, ec, ed, 0, st_ex, cmds_ex)
assert(st_ex[0] == 1, "expr stmt cmd count: " .. tonumber(st_ex[0]))
assert(cmds_ex[0] == 20, "expr stmt const tag: " .. tonumber(cmds_ex[0]))

-- Test lower_if_stmt: if with else
-- Build: 
--   expr[0] = EX_LIT(TK_INT)   -- cond (simplified: constant true)
--   expr data: expr_tag[0]=1, expr_a[0]=2
--   stmt[0] = ST_RETURN_VOID   -- then-body (1 stmt)
--   stmt[1] = ST_RETURN_VOID   -- else-body (1 stmt)
--   slist[0]=0, slist[1]=1
local e_tag = ffi.new("int32_t[3]", 1, 1, 0)  -- expr[0]=EX_LIT, expr[1]=EX_LIT
local e_a = ffi.new("int32_t[3]", 2, 2, 0)
local e_b = ffi.new("int32_t[3]", 0, 0, 0)
local e_c = ffi.new("int32_t[3]", 0, 0, 0)
local e_d = ffi.new("int32_t[3]", 0, 0, 0)
local s_tag = ffi.new("int32_t[2]", 6, 6)  -- stmt[0]=ST_RETURN_VOID, stmt[1]=ST_RETURN_VOID
local s_tok = ffi.new("int32_t[2]", 0, 0)
local s_a = ffi.new("int32_t[2]", 0, 0)
local s_b = ffi.new("int32_t[2]", 0, 0)
local s_c = ffi.new("int32_t[2]", 0, 0)
local s_d = ffi.new("int32_t[2]", 0, 0)
local s_e = ffi.new("int32_t[2]", 0, 0)
local slist = ffi.new("int32_t[2]", 0, 1)   -- slist[0]=0, slist[1]=1
local st_if = ffi.new("int32_t[4]", 0, 10, cap, 100)  -- next_val starts at 10, next_block at 100

local lower_if = stmt_mod:get("mb_lower_if_stmt")
lower_if(0, 0, 1, 1, 1, e_tag, e_a, e_b, e_c, e_d, s_tag, s_tok, s_a, s_b, s_c, s_d, s_e, slist, st_if, cmds_rv)
-- First cmd is the condition literal, after that block cmds follow.
-- Condition: CMD_CONST(20, val=11, B_I32=5, TK_INT=2)
local ci = 1  -- skip condition const
assert(cmds_rv[ci*7+0] == 12, "if create then: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
assert(cmds_rv[ci*7+0] == 12, "if create else: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
assert(cmds_rv[ci*7+0] == 12, "if create join: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
assert(cmds_rv[ci*7+0] == 53, "if br_if: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
assert(cmds_rv[ci*7+0] == 13, "if switch then: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
-- then-body: CMD_RETURN_VOID
assert(cmds_rv[ci*7+0] == 55, "if then return void: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
-- jump to join
assert(cmds_rv[ci*7+0] == 52, "if then->join: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
-- switch to else
assert(cmds_rv[ci*7+0] == 13, "if switch else: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
-- else-body: CMD_RETURN_VOID
assert(cmds_rv[ci*7+0] == 55, "if else return void: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
-- jump to join
assert(cmds_rv[ci*7+0] == 52, "if else->join: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1
-- switch to join
assert(cmds_rv[ci*7+0] == 13, "if switch join: " .. tonumber(cmds_rv[ci*7+0])); ci = ci + 1

-- Test lower_if_stmt: if with NO else
local st_if2 = ffi.new("int32_t[4]", 0, 10, cap, 100)
local cmds_if2 = ffi.new("int32_t[?]", cap * 7)
local slist2 = ffi.new("int32_t[1]", 0)
lower_if(0, 0, 1, -1, 0, e_tag, e_a, e_b, e_c, e_d, s_tag, s_tok, s_a, s_b, s_c, s_d, s_e, slist2, st_if2, cmds_if2)
-- Skip condition (CMD_CONST), then: 3x create, 1x br_if, switch then, return void, jump join, switch else, jump join, switch join
local ci2 = 1  -- skip condition const
assert(cmds_if2[ci2*7+0] == 12, "if2 create then"); ci2 = ci2 + 1
assert(cmds_if2[ci2*7+0] == 12, "if2 create else"); ci2 = ci2 + 1
assert(cmds_if2[ci2*7+0] == 12, "if2 create join"); ci2 = ci2 + 1
assert(cmds_if2[ci2*7+0] == 53, "if2 br_if"); ci2 = ci2 + 1
assert(cmds_if2[ci2*7+0] == 13, "if2 switch then"); ci2 = ci2 + 1
assert(cmds_if2[ci2*7+0] == 55, "if2 then return void"); ci2 = ci2 + 1
assert(cmds_if2[ci2*7+0] == 52, "if2 then->join"); ci2 = ci2 + 1
-- Else block switch always emitted (CFG completeness)
assert(cmds_if2[ci2*7+0] == 13, "if2 switch else"); ci2 = ci2 + 1
-- No else body (else_start=-1), so jump to join immediately
assert(cmds_if2[ci2*7+0] == 52, "if2 else->join"); ci2 = ci2 + 1
-- Join block
assert(cmds_if2[ci2*7+0] == 13, "if2 switch join"); ci2 = ci2 + 1

-- Total cmds for if-no-else: 1 cond + 3 create + 1 br_if + 1 then_switch + 1 then_body + 1 then_jump + 1 else_switch + 1 else_jump + 1 join_switch = 11
-- Total cmds for if-with-else: 1 cond + 3 create + 1 br_if + 1 then_switch + 1 then_body + 1 then_jump + 1 else_switch + 1 else_body + 1 else_jump + 1 join_switch = 12
assert(st_if2[0] == 11, "if no else cmd count: " .. tonumber(st_if2[0]))
assert(st_if[0] == 12, "if with else cmd count: " .. tonumber(st_if[0]))

stmt_mod.artifact:free()

-- Phase 6: Control analysis (back/control.mlua)
local ctrl_mod = compile("lua/moonlift/mom/back/control.mlua")
local push_fact = ctrl_mod:get("mb_push_fact")
local push_reject = ctrl_mod:get("mb_push_reject")
local validate = ctrl_mod:get("mb_validate_control")

-- Build a valid fact tape: one block + one jump to that block.
-- fact_tag[0]=CF_BLOCK(2), fact_a=label_id=1, fact_b=0
-- fact_tag[1]=CF_JUMP(5), fact_a=region=0, fact_b=target=1
local cf_cap = 64
local cf_tag = ffi.new("int32_t[?]", cf_cap)
local cf_a = ffi.new("int32_t[?]", cf_cap)
local cf_b = ffi.new("int32_t[?]", cf_cap)
local cf_c = ffi.new("int32_t[?]", cf_cap)
local cf_d = ffi.new("int32_t[?]", cf_cap)
local cf_e = ffi.new("int32_t[?]", cf_cap)
local cf_f = ffi.new("int32_t[?]", cf_cap)
local cf_cnt = ffi.new("int32_t[1]", 0)
push_fact(2, 1, 0, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
push_fact(5, 0, 1, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
assert(cf_cnt[0] == 2, "fact count: " .. tonumber(cf_cnt[0]))

-- Map for label index
local map_cap = 16
local mkey = ffi.new("int32_t[?]", map_cap)
local mval = ffi.new("int32_t[?]", map_cap)
local mst = ffi.new("int32_t[?]", map_cap)
-- Reject arrays
local r_tag = ffi.new("int32_t[?]", cf_cap)
local r_a = ffi.new("int32_t[?]", cf_cap)
local r_b = ffi.new("int32_t[?]", cf_cap)
local r_c = ffi.new("int32_t[?]", cf_cap)
local r_cnt = ffi.new("int32_t[1]", 0)

-- Validate: should return Reducible(1)
local result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], false, 0, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 1, "valid control should be reducible: " .. tonumber(result))

-- Test: jump to missing label
cf_cnt[0] = 0; r_cnt[0] = 0
-- Clear the map
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(5, 0, 99, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], false, 0, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "missing label should be irreducible: " .. tonumber(result))
assert(r_cnt[0] >= 1, "missing label should produce reject")

-- Test: duplicate label
cf_cnt[0] = 0; r_cnt[0] = 0
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(2, 42, 0, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
push_fact(2, 42, 0, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], false, 0, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "duplicate label should be irreducible: " .. tonumber(result))

-- Test: yield void in expr region
cf_cnt[0] = 0; r_cnt[0] = 0
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(7, 0, 0, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], true, 5, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "yield void in expr region should be irreducible: " .. tonumber(result))

-- Test: yield value type mismatch
cf_cnt[0] = 0; r_cnt[0] = 0
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(8, 0, 0, 3, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
-- result_scalar=5, actual=3 → mismatch
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], true, 5, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "yield type mismatch should be irreducible: " .. tonumber(result))

-- Test: yield value in stmt region
cf_cnt[0] = 0; r_cnt[0] = 0
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(8, 0, 0, 5, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], false, 0, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "yield value in stmt region should be irreducible: " .. tonumber(result))

ctrl_mod.artifact:free()

-- Phase 7: Backend validation (back/validate.mlua)
local val_mod = compile("lua/moonlift/mom/back/validate.mlua")
local validate = val_mod:get("mb_validate")
local mb_has = val_mod:get("mb_has")
local mb_add = val_mod:get("mb_add")

local cap = 64
local ct = ffi.new("int32_t[?]", cap)
local ca = ffi.new("int32_t[?]", cap)
local cb = ffi.new("int32_t[?]", cap)
local cc_arr = ffi.new("int32_t[?]", cap)
local cd = ffi.new("int32_t[?]", cap)
local ce = ffi.new("int32_t[?]", cap)
local cf = ffi.new("int32_t[?]", cap)
local it = ffi.new("int32_t[?]", cap)
local ia = ffi.new("int32_t[?]", cap)
local ib = ffi.new("int32_t[?]", cap)
local ic = ffi.new("int32_t[?]", cap)
local icnt = ffi.new("int32_t[1]", 0)
local ms = ffi.new("int32_t[64]")  -- 8 maps × 8
local mk = ffi.new("int32_t[64]")

-- Map ops test
assert(mb_has(ms, mk, 42, 8) == 0, "empty has")
mb_add(ms, mk, 42, 8)
assert(mb_has(ms, mk, 42, 8) == 1, "has after add")
for i = 0, 7 do ms[i] = 0 end

-- Empty program → 2 issues
icnt[0] = 0
validate(ct, ca, cb, cc_arr, cd, ce, cf, 0, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 2, "empty: " .. tonumber(icnt[0]))

-- Valid: create_sig + declare_func + begin + const + return + finish + finalize
-- CmdCreateSig(2): a=sig_id=10
-- CmdDeclareFunc(9): a=vis=0, b=func_id=20, c=sig_id=10
-- CmdBeginFunc(11): a=func_id=20
-- CmdConst(20): a=val_id=40
-- CmdReturnVoid(55): no refs
-- CmdFinishFunc(58): a=func_id=20
-- CmdFinalizeModule(59)
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=2; ca[0]=10; cb[0]=0; cc_arr[0]=0                         -- CmdCreateSig sig=10
ct[1]=9; ca[1]=0; cb[1]=20; cc_arr[1]=10                         -- CmdDeclareFunc vis=0 func=20 sig=10
ct[2]=11; ca[2]=20                                                -- CmdBeginFunc func=20
ct[3]=20; ca[3]=40                                                -- CmdConst val=40
ct[4]=55                                                          -- CmdReturnVoid
ct[5]=58; ca[5]=20                                                -- CmdFinishFunc func=20
ct[6]=59                                                          -- CmdFinalizeModule
validate(ct, ca, cb, cc_arr, cd, ce, cf, 7, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 0, "valid program issues: " .. tonumber(icnt[0]))

-- Duplicate sig
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=2; ca[0]=10
ct[1]=2; ca[1]=10
ct[2]=59
validate(ct, ca, cb, cc_arr, cd, ce, cf, 3, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 1, "dup sig: " .. tonumber(icnt[0]))
assert(it[0] == 9, "dup sig tag: " .. tonumber(it[0]))

-- Missing sig reference in declare_func
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=9; ca[0]=0; cb[0]=20; cc_arr[0]=99  -- CmdDeclareFunc sig=99 (not created)
ct[1]=59
validate(ct, ca, cb, cc_arr, cd, ce, cf, 2, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 1, "missing sig ref: " .. tonumber(icnt[0]))

-- Missing block
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=11; ca[0]=1      -- CmdBeginFunc
ct[1]=13; ca[1]=99     -- CmdSwitchToBlock block=99 (not created)
ct[2]=58; ca[2]=1      -- CmdFinishFunc
ct[3]=59
validate(ct, ca, cb, cc_arr, cd, ce, cf, 4, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] >= 1, "missing block: " .. tonumber(icnt[0]))

-- Nested function
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=11; ca[0]=1      -- CmdBeginFunc A
ct[1]=11; ca[1]=2      -- CmdBeginFunc B (nested!)
ct[2]=58; ca[2]=2      -- CmdFinishFunc B
ct[3]=59               -- CmdFinalizeModule
validate(ct, ca, cb, cc_arr, cd, ce, cf, 4, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 1, "nested: " .. tonumber(icnt[0]))
assert(it[0] == 5, "nested tag: " .. tonumber(it[0]))

-- Cmd outside function
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=20; ca[0]=40     -- CmdConst outside func
ct[1]=59
validate(ct, ca, cb, cc_arr, cd, ce, cf, 2, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] >= 1, "outside func: " .. tonumber(icnt[0]))

val_mod.artifact:free()

val_mod.artifact:free()

env_mod.artifact:free()
ids.artifact:free()
sets.artifact:free()
builders.artifact:free()

print("mom groundwork ok")

env_mod.artifact:free()
ids.artifact:free()
sets.artifact:free()
builders.artifact:free()

print("mom groundwork ok")
