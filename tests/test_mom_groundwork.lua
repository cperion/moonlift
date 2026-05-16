package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")
local T = require("moonlift.mom.back.back_tags")

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

-- Back scalar tags: F32, I32. Core ScalarRawPtr maps to BackPtr.
assert(is_float(T.BackF32) == true and is_float(T.BackI32) == false)
assert(scalar_to_back(T.ScalarRawPtr) == T.BackPtr)
assert(scalar_to_back(T.ScalarIndex) == T.BackIndex)
-- UnaryNeg: integer -> BackUnaryIneg, float -> BackUnaryFneg.
assert(unary(T.UnaryNeg, T.BackI32) == T.BackUnaryIneg)
assert(unary(T.UnaryNeg, T.BackF32) == T.BackUnaryFneg)
-- CmpLt: integer -> BackSIcmpLt, float -> BackFCmpLt.
assert(cmp(T.CmpLt, T.BackI32) == T.BackSIcmpLt)
assert(cmp(T.CmpLt, T.BackF32) == T.BackFCmpLt)
-- BinAdd: integer class/op Int/Add, float class/op Float/Add.
assert(bin_class(T.BinAdd, T.BackI32) == 1 and bin_code(T.BinAdd, T.BackI32) == T.BackIntAdd)
assert(bin_class(T.BinAdd, T.BackF32) == 2 and bin_code(T.BinAdd, T.BackF32) == T.BackFloatAdd)
-- Bit and shift classes.
assert(bin_class(T.BinBitAnd, T.BackI32) == 3 and bin_code(T.BinBitAnd, T.BackI32) == T.BackBitAnd)
assert(bin_class(T.BinShl, T.BackI32) == 4 and bin_code(T.BinShl, T.BackI32) == T.BackShiftLeft)

-- Phase 2: lower_cast_op (MachineCastOp → BackCastOp).
-- MachineCastOp tags are not schema-derived (hand-maintained in ops.mlua).
-- BackCastOp tags are schema-derived: BackBitcast=1, BackIreduce=2, etc.
local T_MC = {Identity=1, Bitcast=2, Ireduce=3, Sextend=4, Uextend=5, Fpromote=6, Fdemote=7, SToF=8, UToF=9, FToS=10, FToU=11}
local cast = ops:get("mb_lower_cast_op")
assert(cast(T_MC.Bitcast) == T.BackBitcast,  "Bitcast")
assert(cast(T_MC.Ireduce) == T.BackIreduce,  "Ireduce")
assert(cast(T_MC.Sextend) == T.BackSextend,  "Sextend")
assert(cast(T_MC.Uextend) == T.BackUextend,  "Uextend")
assert(cast(T_MC.Fpromote) == T.BackFpromote, "Fpromote")
assert(cast(T_MC.Fdemote) == T.BackFdemote,  "Fdemote")
assert(cast(T_MC.SToF) == T.BackSToF,       "SToF")
assert(cast(T_MC.UToF) == T.BackUToF,       "UToF")
assert(cast(T_MC.FToS) == T.BackFToS,       "FToS")
assert(cast(T_MC.FToU) == T.BackFToU,       "FToU")
-- Identity has no BackCast — returns 0.
assert(cast(T_MC.Identity) == 0,  "Identity")
-- Unknown tag.
assert(cast(99) == 0, "Unknown cast")

-- Phase 2: lower_surface_cast_op (SurfaceCastOp → MachineCastOp).
-- SurfaceCastOp tags are hand-maintained (not schema-derived).
-- MachineCastOp tags are also hand-maintained.
local T_SC = {Cast=1, Trunc=2, ZExt=3, SExt=4, Bitcast=5, SatCast=6}
local scast = ops:get("mb_lower_surface_cast_op")
assert(scast(T_SC.Cast) == T_MC.Bitcast, "SurfaceCast → MachineCastBitcast")
assert(scast(T_SC.Trunc) == T_MC.Ireduce, "SurfaceTrunc → MachineCastIreduce")
assert(scast(T_SC.ZExt) == T_MC.Uextend, "SurfaceZExt → MachineCastUextend")
assert(scast(T_SC.SExt) == T_MC.Sextend, "SurfaceSExt → MachineCastSextend")
assert(scast(T_SC.Bitcast) == T_MC.Bitcast, "SurfaceBitcast → MachineCastBitcast")
assert(scast(T_SC.SatCast) == T_MC.Bitcast, "SurfaceSatCast → MachineCastBitcast")
assert(scast(99) == 0, "Unknown surface cast")

-- Phase 2: lower_atomic_ordering (AtomicOrdering → BackAtomicOrdering).
-- Both share AtomicSeqCst = 1.
local ao = ops:get("mb_lower_atomic_ordering")
assert(ao(T.AtomicSeqCst) == T.AtomicSeqCst, "AtomicSeqCst")
assert(ao(99) == 0, "Unknown ordering")

-- Phase 2: lower_atomic_rmw_op (AtomicRmwOp → BackAtomicRmwOp).
-- Both share the same variant numbering.
local rmw = ops:get("mb_lower_atomic_rmw_op")
assert(rmw(T.AtomicRmwAdd) == T.AtomicRmwAdd, "RmwAdd")
assert(rmw(T.AtomicRmwSub) == T.AtomicRmwSub, "RmwSub")
assert(rmw(T.AtomicRmwAnd) == T.AtomicRmwAnd, "RmwAnd")
assert(rmw(T.AtomicRmwOr) == T.AtomicRmwOr, "RmwOr")
assert(rmw(T.AtomicRmwXor) == T.AtomicRmwXor, "RmwXor")
assert(rmw(T.AtomicRmwXchg) == T.AtomicRmwXchg, "RmwXchg")
assert(rmw(99) == 0, "Unknown rmw")

-- Phase 2: type_to_back_scalar (Type union tag → BackScalar).
-- Type tags are hand-maintained (MoonCyclic, not in T).
-- TScalar=1, TPtr=2, TFunc=6, TCFuncPtr=11 → BackScalar.
-- Extract the scalar sub-tag from the semantic Type node.
local ttbs = ops:get("mb_type_to_back_scalar")
-- TScalar with BackI32 → BackI32
assert(ttbs(1, T.BackI32) == T.BackI32, "TScalar i32")
-- TScalar with BackF32 → BackF32
assert(ttbs(1, T.BackF32) == T.BackF32, "TScalar f32")
-- TScalar with BackBool → BackBool
assert(ttbs(1, T.BackBool) == T.BackBool, "TScalar bool")
-- TScalar with BackPtr → BackPtr
assert(ttbs(1, T.BackPtr) == T.BackPtr, "TScalar rawptr")
-- TPtr → BackPtr
assert(ttbs(2, 0) == T.BackPtr, "TPtr")
-- TFunc → BackPtr
assert(ttbs(6, 0) == T.BackPtr, "TFunc")
-- TCFuncPtr → BackPtr
assert(ttbs(11, 0) == T.BackPtr, "TCFuncPtr")
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

-- CmdEntry FFI struct must match MOM CmdEntry layout (tag + w0..w16 = 18 fields).
ffi.cdef[[
typedef struct { int32_t tag, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, w16; } CmdEntry;
]]
local CmdEntry_t = ffi.typeof("CmdEntry")

-- Test lower_binary (now takes overflow, exact as separate params instead of sem_packed):
-- BinAdd, BackI32 → CmdIntBinary, dst=10, BackIntAdd, BackI32, overflow=1, exact=1, lhs=20, rhs=30
local e = CmdEntry_t()
lower_binary(T.BinAdd, T.BackI32, 10, 20, 30, 1, 1, e)
assert(e.tag == T.CmdIntBinary, "binary add i32 tag: " .. tonumber(e.tag))
assert(e.w0 == 10 and e.w1 == T.BackIntAdd and e.w2 == T.BackI32, "binary add i32 fields")
assert(e.w3 == 1 and e.w4 == 1 and e.w5 == 20 and e.w6 == 30, "binary add i32 overflow/exact/lhs/rhs")

-- BinAdd, BackF32 → CmdFloatBinary, dst=11, BackFloatAdd, BackF32, semantics=1, lhs=21, rhs=31
e = CmdEntry_t()
lower_binary(T.BinAdd, T.BackF32, 11, 21, 31, 1, 1, e)
assert(e.tag == T.CmdFloatBinary, "binary add f32 tag: " .. tonumber(e.tag))
assert(e.w0 == 11 and e.w1 == T.BackFloatAdd and e.w2 == T.BackF32, "binary add f32 fields")
assert(e.w4 == 21 and e.w5 == 31, "binary add f32 lhs/rhs")

-- BinBitAnd → CmdBitBinary, dst=12, BackBitAnd, BackI32, lhs=22, rhs=32
e = CmdEntry_t()
lower_binary(T.BinBitAnd, T.BackI32, 12, 22, 32, 0, 0, e)
assert(e.tag == T.CmdBitBinary, "binary bit and tag: " .. tonumber(e.tag))
assert(e.w0 == 12 and e.w1 == T.BackBitAnd and e.w2 == T.BackI32 and e.w3 == 22 and e.w4 == 32, "binary bit and fields")

-- BinShl → CmdShift, dst=13, BackShiftLeft, BackI32, lhs=23, rhs=33
e = CmdEntry_t()
lower_binary(T.BinShl, T.BackI32, 13, 23, 33, 0, 0, e)
assert(e.tag == T.CmdShift, "binary shl tag: " .. tonumber(e.tag))
assert(e.w0 == 13 and e.w1 == T.BackShiftLeft and e.w2 == T.BackI32 and e.w3 == 23 and e.w4 == 33, "binary shl fields")

-- Invalid binary op → CmdTrap(CMD_TRAP=57)
e = CmdEntry_t()
lower_binary(99, 5, 0, 0, 0, 0, 0, e)
assert(e.tag == T.CmdTrap, "binary invalid trap: " .. tonumber(e.tag))

-- Test lower_unary_cmd:
-- UnaryNeg, BackI32 → CmdUnary, dst=10, BackUnaryIneg, shape_tag=1, BackI32, lanes=0, value=20
e = CmdEntry_t()
lower_unary(T.UnaryNeg, T.BackI32, 10, 20, 1, e)
assert(e.tag == T.CmdUnary, "unary neg i32 tag: " .. tonumber(e.tag))
assert(e.w0 == 10 and e.w1 == T.BackUnaryIneg and e.w2 == 1 and e.w3 == T.BackI32 and e.w5 == 20, "unary neg i32 fields")

-- UnaryNeg, BackF32 → CmdUnary, dst=11, BackUnaryFneg
e = CmdEntry_t()
lower_unary(T.UnaryNeg, T.BackF32, 11, 21, 1, e)
assert(e.tag == T.CmdUnary, "unary neg f32 tag: " .. tonumber(e.tag))
assert(e.w1 == T.BackUnaryFneg, "unary neg f32 op: " .. tonumber(e.w1))

-- UnaryNot → BackUnaryBoolNot
e = CmdEntry_t()
lower_unary(T.UnaryNot, T.BackI32, 10, 20, 1, e)
assert(e.w1 == T.BackUnaryBoolNot, "unary not op: " .. tonumber(e.w1))

-- U_BIT_NOT=3 → CmdBitNot, dst=10, BackI32, value=20
-- (UnaryOp tag 3 is local bit-not, not in schema; MB_UNARY_BIT_NOT hand-maintained)
e = CmdEntry_t()
lower_unary(3, T.BackI32, 10, 20, 1, e)
assert(e.tag == T.CmdBitNot, "unary bitnot tag: " .. tonumber(e.tag))
assert(e.w0 == 10 and e.w1 == 5 and e.w2 == 20, "unary bitnot fields")

-- Test lower_compare:
-- CmpEq, BackI32 → CmdCompare, dst=10, BackIcmpEq, shape_tag=1, BackI32, lhs=20, rhs=30
e = CmdEntry_t()
lower_compare(T.CmpEq, T.BackI32, 10, 20, 30, 1, e)
assert(e.tag == T.CmdCompare, "compare eq i32 tag: " .. tonumber(e.tag))
assert(e.w0 == 10 and e.w1 == T.BackIcmpEq and e.w2 == 1 and e.w3 == T.BackI32 and e.w5 == 20 and e.w6 == 30, "compare eq i32 fields")

-- CmpEq, BackF32 → BackFCmpEq
e = CmdEntry_t()
lower_compare(T.CmpEq, T.BackF32, 10, 20, 30, 1, e)
assert(e.w1 == T.BackFCmpEq, "compare eq f32 op: " .. tonumber(e.w1))

-- CmpLt, BackI32 → BackSIcmpLt
e = CmdEntry_t()
lower_compare(T.CmpLt, T.BackI32, 10, 20, 30, 1, e)
assert(e.w1 == T.BackSIcmpLt, "compare lt i32 op: " .. tonumber(e.w1))

-- CmpLt, BackU32 → BackUIcmpLt
e = CmdEntry_t()
lower_compare(T.CmpLt, T.BackU32, 10, 20, 30, 1, e)
assert(e.w1 == T.BackUIcmpLt, "compare lt u32 op: " .. tonumber(e.w1))

-- CmpLt, BackF32 → BackFCmpLt
e = CmdEntry_t()
lower_compare(T.CmpLt, T.BackF32, 10, 20, 30, 1, e)
assert(e.w1 == T.BackFCmpLt, "compare lt f32 op: " .. tonumber(e.w1))

-- Test lower_cast_cmd:
-- MachineCastBitcast → CmdCast, dst=10, BackBitcast, BackI32, value=20
e = CmdEntry_t()
lower_cast(T_MC.Bitcast, T.BackI32, 10, 20, e)
assert(e.tag == T.CmdCast, "cast bitcast tag: " .. tonumber(e.tag))
assert(e.w0 == 10 and e.w1 == T.BackBitcast and e.w2 == T.BackI32 and e.w3 == 20, "cast bitcast fields")

-- MachineCastSextend → BackSextend
e = CmdEntry_t()
lower_cast(T_MC.Sextend, T.BackI32, 11, 21, e)
assert(e.w1 == T.BackSextend, "cast sextend op: " .. tonumber(e.w1))

-- MachineCastFpromote → BackFpromote
e = CmdEntry_t()
lower_cast(T_MC.Fpromote, T.BackI32, 12, 22, e)
assert(e.w1 == T.BackFpromote, "cast fpromote op: " .. tonumber(e.w1))

-- MachineCastSToF → BackSToF
e = CmdEntry_t()
lower_cast(T_MC.SToF, T.BackI32, 13, 23, e)
assert(e.w1 == T.BackSToF, "cast stof op: " .. tonumber(e.w1))

-- MachineCastIdentity → CmdTrap (no backend op)
e = CmdEntry_t()
lower_cast(T_MC.Identity, T.BackI32, 10, 20, e)
assert(e.tag == T.CmdTrap, "cast identity trap: " .. tonumber(e.tag))

-- Test structural command constructors:
local cmd_create_block = cmd_mod:get("mb_cmd_create_block")
local cmd_switch_to_block = cmd_mod:get("mb_cmd_switch_to_block")
local cmd_seal_block = cmd_mod:get("mb_cmd_seal_block")
local cmd_begin_func = cmd_mod:get("mb_cmd_begin_func")
local cmd_finish_func = cmd_mod:get("mb_cmd_finish_func")
local cmd_return_void = cmd_mod:get("mb_cmd_return_void")
local cmd_return_value = cmd_mod:get("mb_cmd_return_value")
local cmd_jump = cmd_mod:get("mb_cmd_jump")
local cmd_br_if = cmd_mod:get("mb_cmd_br_if")
local cmd_const = cmd_mod:get("mb_cmd_const")
local cmd_finalize_module = cmd_mod:get("mb_cmd_finalize_module")

-- CmdCreateBlock: w0=block_id
e = CmdEntry_t()
cmd_create_block(e, 42)
assert(e.tag == T.CmdCreateBlock, "create_block tag: " .. tonumber(e.tag))
assert(e.w0 == 42, "create_block block: " .. tonumber(e.w0))

-- CmdSwitchToBlock: w0=block_id
e = CmdEntry_t()
cmd_switch_to_block(e, 42)
assert(e.tag == T.CmdSwitchToBlock, "switch_to_block tag: " .. tonumber(e.tag))
assert(e.w0 == 42, "switch_to_block block: " .. tonumber(e.w0))

-- CmdSealBlock: w0=block_id
e = CmdEntry_t()
cmd_seal_block(e, 42)
assert(e.tag == T.CmdSealBlock, "seal_block tag: " .. tonumber(e.tag))
assert(e.w0 == 42, "seal_block block: " .. tonumber(e.w0))

-- CmdBeginFunc: w0=func_id
e = CmdEntry_t()
cmd_begin_func(e, 7)
assert(e.tag == T.CmdBeginFunc, "begin_func tag: " .. tonumber(e.tag))
assert(e.w0 == 7, "begin_func func: " .. tonumber(e.w0))

-- CmdFinishFunc
e = CmdEntry_t()
cmd_finish_func(e, 7)
assert(e.tag == T.CmdFinishFunc, "finish_func tag: " .. tonumber(e.tag))
assert(e.w0 == 7, "finish_func func: " .. tonumber(e.w0))

-- CmdReturnVoid
e = CmdEntry_t()
cmd_return_void(e)
assert(e.tag == T.CmdReturnVoid, "return_void tag: " .. tonumber(e.tag))

-- CmdReturnValue: w0=value
e = CmdEntry_t()
cmd_return_value(e, 99)
assert(e.tag == T.CmdReturnValue, "return_value tag: " .. tonumber(e.tag))
assert(e.w0 == 99, "return_value value: " .. tonumber(e.w0))

-- CmdJump: w0=dest, w1=args_aux, w2=count
e = CmdEntry_t()
cmd_jump(e, 5, 10, 2)
assert(e.tag == T.CmdJump, "jump tag: " .. tonumber(e.tag))
assert(e.w0 == 5 and e.w1 == 10 and e.w2 == 2, "jump fields")

-- CmdBrIf: w0=cond, w1=then_block, w2=then_aux, w3=then_count, w4=else_block, w5=else_aux, w6=else_count
e = CmdEntry_t()
cmd_br_if(e, 1, 2, 10, 3, 3, 20, 2)
assert(e.tag == T.CmdBrIf, "br_if tag: " .. tonumber(e.tag))
assert(e.w0 == 1 and e.w1 == 2 and e.w2 == 10 and e.w3 == 3 and e.w4 == 3 and e.w5 == 20 and e.w6 == 2, "br_if fields")

-- CmdConst: w0=dst, w1=scalar, w2=lit_tag, w3=lit_lo, w4=lit_hi
e = CmdEntry_t()
cmd_const(e, 5, T.BackBool, 0, 42, 0)
assert(e.tag == T.CmdConst, "const tag: " .. tonumber(e.tag))
assert(e.w0 == 5 and e.w1 == T.BackBool and e.w2 == 0 and e.w3 == 42 and e.w4 == 0, "const fields")

-- CmdFinalizeModule
e = CmdEntry_t()
cmd_finalize_module(e)
assert(e.tag == T.CmdFinalizeModule, "finalize_module tag: " .. tonumber(e.tag))

-- Phase 4b: New command constructors (atomic, vector, alias_fact)
do
local cmd_alias_fact = cmd_mod:get("mb_cmd_alias_fact")
local cmd_atomic_load = cmd_mod:get("mb_cmd_atomic_load")
local cmd_atomic_store = cmd_mod:get("mb_cmd_atomic_store")
local cmd_atomic_rmw = cmd_mod:get("mb_cmd_atomic_rmw")
local cmd_atomic_cas = cmd_mod:get("mb_cmd_atomic_cas")
local cmd_atomic_fence = cmd_mod:get("mb_cmd_atomic_fence")
local cmd_vec_splat = cmd_mod:get("mb_cmd_vec_splat")
local cmd_vec_binary = cmd_mod:get("mb_cmd_vec_binary")
local cmd_vec_compare = cmd_mod:get("mb_cmd_vec_compare")
local cmd_vec_select = cmd_mod:get("mb_cmd_vec_select")
local cmd_vec_mask = cmd_mod:get("mb_cmd_vec_mask")
local cmd_vec_insert_lane = cmd_mod:get("mb_cmd_vec_insert_lane")
local cmd_vec_extract_lane = cmd_mod:get("mb_cmd_vec_extract_lane")
local cmd_vec_load_info = cmd_mod:get("mb_cmd_vec_load_info")
local cmd_vec_store_info = cmd_mod:get("mb_cmd_vec_store_info")

-- CmdAliasFact: kind=1, a=10, b=20, c=30
e = CmdEntry_t()
cmd_alias_fact(e, 1, 10, 20, 30)
assert(e.tag == T.CmdAliasFact, "alias_fact tag: " .. tonumber(e.tag))
assert(e.w0 == 1 and e.w1 == 10 and e.w2 == 20 and e.w3 == 30, "alias_fact fields")

-- CmdAtomicLoad: dst=1, scalar=BackI32, base_tag=0, base_id=2, byte_offset=0, access=3, align_k=1, align_b=4, deref_k=0, deref_b=4, trap_k=0, motion_k=0, mode_k=1, ordering=AtomicSeqCst
e = CmdEntry_t()
cmd_atomic_load(e, 1, T.BackI32, 0, 2, 0, 3, 1, 4, 0, 4, 0, 0, 1, T.AtomicSeqCst)
assert(e.tag == T.CmdAtomicLoad, "atomic_load tag: " .. tonumber(e.tag))
assert(e.w0 == 1 and e.w1 == T.BackI32 and e.w13 == T.AtomicSeqCst, "atomic_load fields")

-- CmdAtomicStore: scalar=BackI32, base_tag=0, base_id=2, byte_offset=0, value=5, access=3, align_k=1, align_b=4, deref_k=0, deref_b=4, trap_k=0, motion_k=0, mode_k=2, ordering=AtomicSeqCst
e = CmdEntry_t()
cmd_atomic_store(e, T.BackI32, 0, 2, 0, 5, 3, 1, 4, 0, 4, 0, 0, 2, T.AtomicSeqCst)
assert(e.tag == T.CmdAtomicStore, "atomic_store tag: " .. tonumber(e.tag))
assert(e.w0 == T.BackI32 and e.w4 == 5 and e.w13 == T.AtomicSeqCst, "atomic_store fields")

-- CmdAtomicRmw: dst=1, op=AtomicRmwAdd, scalar=BackI32, base_tag=0, base_id=2, byte_offset=0, value=5, access=3, ..., ordering=AtomicSeqCst
e = CmdEntry_t()
cmd_atomic_rmw(e, 1, T.AtomicRmwAdd, T.BackI32, 0, 2, 0, 5, 3, 1, 4, 0, 4, 0, 0, 2, T.AtomicSeqCst)
assert(e.tag == T.CmdAtomicRmw, "atomic_rmw tag: " .. tonumber(e.tag))
assert(e.w1 == T.AtomicRmwAdd and e.w15 == T.AtomicSeqCst, "atomic_rmw fields")

-- CmdAtomicCas: dst=1, scalar=BackI32, base_tag=0, base_id=2, byte_offset=0, expected=5, replacement=6, ..., ordering=AtomicSeqCst
e = CmdEntry_t()
cmd_atomic_cas(e, 1, T.BackI32, 0, 2, 0, 5, 6, 3, 1, 4, 0, 4, 0, 0, 2, T.AtomicSeqCst)
assert(e.tag == T.CmdAtomicCas, "atomic_cas tag: " .. tonumber(e.tag))
assert(e.w0 == 1 and e.w5 == 5 and e.w6 == 6 and e.w15 == T.AtomicSeqCst, "atomic_cas fields")

-- CmdAtomicFence: ordering=AtomicSeqCst
e = CmdEntry_t()
cmd_atomic_fence(e, T.AtomicSeqCst)
assert(e.tag == T.CmdAtomicFence, "atomic_fence tag: " .. tonumber(e.tag))
assert(e.w0 == T.AtomicSeqCst, "atomic_fence ordering")

-- CmdVecSplat: dst=1, elem_scalar=BackI32, lanes=4, value=2
e = CmdEntry_t()
cmd_vec_splat(e, 1, T.BackI32, 4, 2)
assert(e.tag == T.CmdVecSplat, "vec_splat tag: " .. tonumber(e.tag))
assert(e.w0 == 1 and e.w1 == T.BackI32 and e.w2 == 4 and e.w3 == 2, "vec_splat fields")

-- CmdVecBinary: dst=1, op=BackVecIntAdd, elem_scalar=BackI32, lanes=4, lhs=2, rhs=3
e = CmdEntry_t()
cmd_vec_binary(e, 1, T.BackVecIntAdd, T.BackI32, 4, 2, 3)
assert(e.tag == T.CmdVecBinary, "vec_binary tag: " .. tonumber(e.tag))
assert(e.w1 == T.BackVecIntAdd, "vec_binary op")

-- CmdVecCompare: dst=1, op=BackVecIcmpEq, elem_scalar=BackI32, lanes=4, lhs=2, rhs=3
e = CmdEntry_t()
cmd_vec_compare(e, 1, T.BackVecIcmpEq, T.BackI32, 4, 2, 3)
assert(e.tag == T.CmdVecCompare, "vec_compare tag: " .. tonumber(e.tag))
assert(e.w1 == T.BackVecIcmpEq, "vec_compare op")

-- CmdVecSelect: dst=1, elem_scalar=BackI32, lanes=4, mask=5, then_val=6, else_val=7
e = CmdEntry_t()
cmd_vec_select(e, 1, T.BackI32, 4, 5, 6, 7)
assert(e.tag == T.CmdVecSelect, "vec_select tag: " .. tonumber(e.tag))
assert(e.w3 == 5 and e.w4 == 6 and e.w5 == 7, "vec_select fields")

-- CmdVecMask: dst=1, op=BackVecMaskNot, elem_scalar=BackI32, lanes=4, args_aux=10, count=2
e = CmdEntry_t()
cmd_vec_mask(e, 1, T.BackVecMaskNot, T.BackI32, 4, 10, 2)
assert(e.tag == T.CmdVecMask, "vec_mask tag: " .. tonumber(e.tag))
assert(e.w1 == T.BackVecMaskNot and e.w4 == 10 and e.w5 == 2, "vec_mask fields")

-- CmdVecInsertLane: dst=1, elem_scalar=BackI32, lanes=4, value=2, lane_value=3, lane=0
e = CmdEntry_t()
cmd_vec_insert_lane(e, 1, T.BackI32, 4, 2, 3, 0)
assert(e.tag == T.CmdVecInsertLane, "vec_insert_lane tag: " .. tonumber(e.tag))
assert(e.w3 == 2 and e.w4 == 3 and e.w5 == 0, "vec_insert_lane fields")

-- CmdVecExtractLane: dst=1, scalar=BackI32, value=2, lane=0
e = CmdEntry_t()
cmd_vec_extract_lane(e, 1, T.BackI32, 2, 0)
assert(e.tag == T.CmdVecExtractLane, "vec_extract_lane tag: " .. tonumber(e.tag))
assert(e.w1 == T.BackI32 and e.w2 == 2 and e.w3 == 0, "vec_extract_lane fields")

-- CmdVecLoadInfo: dst=1, elem_scalar=BackI32, lanes=4, base_tag=0, base_id=2, byte_offset=0, access=3, align_k=1, align_b=4, deref_k=0, deref_b=4, trap_k=0, motion_k=0, mode_k=1
e = CmdEntry_t()
cmd_vec_load_info(e, 1, T.BackI32, 4, 0, 2, 0, 3, 1, 4, 0, 4, 0, 0, 1)
assert(e.tag == T.CmdVecLoadInfo, "vec_load_info tag: " .. tonumber(e.tag))
assert(e.w0 == 1 and e.w1 == T.BackI32 and e.w2 == 4, "vec_load_info dst/scalar/lanes")

-- CmdVecStoreInfo: elem_scalar=BackI32, lanes=4, base_tag=0, base_id=2, byte_offset=0, value=5, access=3, align_k=1, align_b=4, deref_k=0, deref_b=4, trap_k=0, motion_k=0, mode_k=2
e = CmdEntry_t()
cmd_vec_store_info(e, T.BackI32, 4, 0, 2, 0, 5, 3, 1, 4, 0, 4, 0, 0, 2)
assert(e.tag == T.CmdVecStoreInfo, "vec_store_info tag: " .. tonumber(e.tag))
assert(e.w0 == T.BackI32 and e.w1 == 4 and e.w5 == 5, "vec_store_info fields")
end -- Phase 4b do block

cmd_mod.artifact:free()

-- Phase 4: Expression lowering (back/expr_lower.mlua)
local expr_mod = compile("lua/moonlift/mom/back/expr_lower.mlua")
local lower_lit = expr_mod:get("mb_lower_lit")
local lower_ref = expr_mod:get("mb_lower_ref")
local lower_unary = expr_mod:get("mb_lower_unary_expr")
local lower_binary = expr_mod:get("mb_lower_binary_expr")
local lower_compare = expr_mod:get("mb_lower_compare_expr")
local lower_select = expr_mod:get("mb_lower_select_expr")

-- Phase 4: Expression lowering tests
-- Command buffer stride: 18 (MLBT v3: tag + w0..w16).
-- st layout for expr_lower: st[0]=cmd_count, st[1]=next_value, st[2]=cap
do
local CMD_STRIDE = 18
local ecap = 64
local st = ffi.new("int32_t[3]", 0, 0, ecap)
local cmds = ffi.new("int32_t[?]", ecap * CMD_STRIDE)

local TK_INT = 2
local TK_TRUE = T.TK_TRUE
local TK_PLUS = T.TK_PLUS
local TK_EQEQ = T.TK_EQEQ
local TK_MINUS = T.TK_MINUS
local ST_RETURN_VOID = 6
local ST_RETURN_VALUE = 7
local ST_EXPR = 4
local EX_LIT = 1
local val = lower_lit(TK_INT, st, cmds)
assert(val == 1, "lit val: " .. tonumber(val))
assert(st[0] == 1, "cmd count after lit: " .. tonumber(st[0]))
assert(st[1] == 1, "next val after lit: " .. tonumber(st[1]))
assert(cmds[0] == T.CmdConst, "cmd tag: " .. tonumber(cmds[0]))
assert(cmds[1] == 1, "cmd dst: " .. tonumber(cmds[1]))   -- val=1
assert(cmds[2] == T.BackI32, "cmd scalar: " .. tonumber(cmds[2]))

-- Test lower_lit with bool: TK_TRUE → scalar=BackBool
local st2 = ffi.new("int32_t[3]", 1, 1, ecap)
local cmds2 = ffi.new("int32_t[?]", ecap * CMD_STRIDE)
cmds2[0] = -1  -- sentinel
lower_lit(TK_TRUE, st2, cmds2)
-- new entry at index CMD_STRIDE (offset CMD_STRIDE from start)
assert(cmds2[CMD_STRIDE + 0] == T.CmdConst, "bool cmd tag")
assert(cmds2[CMD_STRIDE + 2] == T.BackBool, "bool scalar: " .. tonumber(cmds2[CMD_STRIDE + 2]))

-- Test lower_binary_expr: TK_PLUS, scalar=BackI32, left=2, right=3
-- Should emit CmdIntBinary, dst=2, BackIntAdd, BackI32, sem=65537, lhs=2, rhs=3
local st3 = ffi.new("int32_t[3]", 0, 1, ecap)
local cmds3 = ffi.new("int32_t[?]", ecap * CMD_STRIDE)
local r = lower_binary(TK_PLUS, T.BackI32, 2, 3, st3, cmds3)
assert(r == 2, "binary result val: " .. tonumber(r))
assert(cmds3[0] == T.CmdIntBinary, "binary tag: " .. tonumber(cmds3[0]))
assert(cmds3[1] == 2, "binary dst: " .. tonumber(cmds3[1]))
assert(cmds3[2] == T.BackIntAdd, "binary op: " .. tonumber(cmds3[2]))
assert(cmds3[3] == T.BackI32, "binary scalar: " .. tonumber(cmds3[3]))
assert(cmds3[4] == 65537, "binary sem: " .. tonumber(cmds3[4]))
assert(cmds3[5] == 2, "binary lhs: " .. tonumber(cmds3[5]))
assert(cmds3[6] == 3, "binary rhs: " .. tonumber(cmds3[6]))

-- Test lower_compare: TK_EQEQ, scalar=BackI32, lhs=4, rhs=5
-- → CmdCompare, dst=3, BackIcmpEq, shape=1, BackI32, lhs=4, rhs=5
local st4 = ffi.new("int32_t[3]", 0, 2, ecap)
local cmds4 = ffi.new("int32_t[?]", ecap * CMD_STRIDE)
r = lower_compare(TK_EQEQ, T.BackI32, 4, 5, st4, cmds4)
assert(r == 3, "compare result val: " .. tonumber(r))
assert(cmds4[0] == T.CmdCompare, "compare tag: " .. tonumber(cmds4[0]))
assert(cmds4[1] == 3, "compare dst: " .. tonumber(cmds4[1]))
assert(cmds4[2] == T.BackIcmpEq, "compare op: " .. tonumber(cmds4[2]))
assert(cmds4[3] == 1, "compare shape: " .. tonumber(cmds4[3]))
assert(cmds4[4] == T.BackI32, "compare scalar: " .. tonumber(cmds4[4]))

-- Test lower_unary_expr: TK_MINUS, scalar=BackI32, child=6
-- → CmdUnary, dst=4, BackUnaryIneg, shape=1, BackI32, value=6
local st5 = ffi.new("int32_t[3]", 0, 3, ecap)
local cmds5 = ffi.new("int32_t[?]", ecap * CMD_STRIDE)
r = lower_unary(TK_MINUS, T.BackI32, 6, st5, cmds5)
assert(r == 4, "unary result val: " .. tonumber(r))
assert(cmds5[0] == T.CmdUnary, "unary tag: " .. tonumber(cmds5[0]))
assert(cmds5[1] == 4, "unary dst: " .. tonumber(cmds5[1]))
assert(cmds5[2] == T.BackUnaryIneg, "unary op: " .. tonumber(cmds5[2]))
assert(cmds5[3] == 1, "unary shape: " .. tonumber(cmds5[3]))
assert(cmds5[4] == T.BackI32, "unary scalar: " .. tonumber(cmds5[4]))
assert(cmds5[5] == 6, "unary child: " .. tonumber(cmds5[5]))

-- Test lower_select: scalar=BackI32, cond=7, then=8, else=9
-- → CmdSelect, dst=5, shape=1, cond=7, then=8, else=9
local st6 = ffi.new("int32_t[3]", 0, 4, ecap)
local cmds6 = ffi.new("int32_t[?]", ecap * CMD_STRIDE)
r = lower_select(T.BackI32, 7, 8, 9, st6, cmds6)
assert(r == 5, "select result val: " .. tonumber(r))
assert(cmds6[0] == T.CmdSelect, "select tag: " .. tonumber(cmds6[0]))
assert(cmds6[1] == 5, "select dst: " .. tonumber(cmds6[1]))
assert(cmds6[3] == 7, "select cond: " .. tonumber(cmds6[3]))
assert(cmds6[4] == 8, "select then: " .. tonumber(cmds6[4]))
assert(cmds6[5] == 9, "select else: " .. tonumber(cmds6[5]))

expr_mod.artifact:free()
end -- expr_lower do-block

-- Phase 5: Statement lowering (back/stmt_lower.mlua)
-- st layout for stmt_lower: st[0]=cmd_count, st[1]=next_value, st[2]=next_block, st[3]=cap
do
local STMT_CMD_STRIDE = 18
local scap = 64
local EX_LIT = 1
local TK_INT = 2
local ST_RETURN_VOID = 6
local ST_RETURN_VALUE = 7
local ST_EXPR = 4
local stmt_mod = compile("lua/moonlift/mom/back/stmt_lower.mlua")
local lower_return_void = stmt_mod:get("mb_lower_return_void")
local lower_return_value = stmt_mod:get("mb_lower_return_value")
local lower_expr_stmt = stmt_mod:get("mb_lower_expr_stmt")

-- Test ST_RETURN_VOID
local st_rv = ffi.new("int32_t[4]", 0, 0, 0, scap)
local cmds_rv = ffi.new("int32_t[?]", scap * STMT_CMD_STRIDE)
lower_return_void(st_rv, cmds_rv)
assert(st_rv[0] == 1, "return void cmd count: " .. tonumber(st_rv[0]))
assert(cmds_rv[0] == T.CmdReturnVoid, "return void tag: " .. tonumber(cmds_rv[0]))

-- Test ST_RETURN_VALUE with a literal expr
-- Create an expr tape with EX_LIT, tok_kind=TK_INT
local etag = ffi.new("int32_t[1]", EX_LIT)
local ea = ffi.new("int32_t[1]", TK_INT)
local eb = ffi.new("int32_t[1]", 0)
local ec = ffi.new("int32_t[1]", 0)
local ed = ffi.new("int32_t[1]", 0)
local st_rv2 = ffi.new("int32_t[4]", 0, 0, 0, scap)
local cmds_rv2 = ffi.new("int32_t[?]", scap * STMT_CMD_STRIDE)
lower_return_value(etag, ea, eb, ec, ed, 0, st_rv2, cmds_rv2)
assert(st_rv2[0] >= 2, "return value cmd count: " .. tonumber(st_rv2[0]))
-- First cmd should be CmdConst for the literal
assert(cmds_rv2[0] == T.CmdConst, "return value const tag: " .. tonumber(cmds_rv2[0]))
-- Last cmd should be CmdReturnValue at offset (st_rv2[0]-1)*STMT_CMD_STRIDE
local last_cmd_offset = (st_rv2[0] - 1) * STMT_CMD_STRIDE
assert(cmds_rv2[last_cmd_offset] == T.CmdReturnValue, "return value cmd tag: " .. tonumber(cmds_rv2[last_cmd_offset]))

-- Test ST_EXPR with a literal expr
local st_ex = ffi.new("int32_t[4]", 0, 0, 0, scap)
local cmds_ex = ffi.new("int32_t[?]", scap * STMT_CMD_STRIDE)
lower_expr_stmt(etag, ea, eb, ec, ed, 0, st_ex, cmds_ex)
assert(st_ex[0] == 1, "expr stmt cmd count: " .. tonumber(st_ex[0]))
assert(cmds_ex[0] == T.CmdConst, "expr stmt const tag: " .. tonumber(cmds_ex[0]))

-- Test lower_if_stmt: if with else
-- Build: 
--   expr[0] = EX_LIT(TK_INT)   -- cond (simplified: constant true)
--   stmt[0] = ST_RETURN_VOID   -- then-body (1 stmt)
--   stmt[1] = ST_RETURN_VOID   -- else-body (1 stmt)
--   slist[0]=0, slist[1]=1
local e_tag = ffi.new("int32_t[3]", EX_LIT, EX_LIT, 0)  -- expr[0]=EX_LIT, expr[1]=EX_LIT
local e_a = ffi.new("int32_t[3]", TK_INT, TK_INT, 0)
local e_b = ffi.new("int32_t[3]", 0, 0, 0)
local e_c = ffi.new("int32_t[3]", 0, 0, 0)
local e_d = ffi.new("int32_t[3]", 0, 0, 0)
local s_tag = ffi.new("int32_t[2]", ST_RETURN_VOID, ST_RETURN_VOID)  -- stmt tags
local s_tok = ffi.new("int32_t[2]", 0, 0)
local s_a = ffi.new("int32_t[2]", 0, 0)
local s_b = ffi.new("int32_t[2]", 0, 0)
local s_c = ffi.new("int32_t[2]", 0, 0)
local s_d = ffi.new("int32_t[2]", 0, 0)
local s_e = ffi.new("int32_t[2]", 0, 0)
local slist = ffi.new("int32_t[2]", 0, 1)   -- slist[0]=0, slist[1]=1
local st_if = ffi.new("int32_t[4]", 0, 0, 100, scap)  -- st[0]=cmd_count, st[1]=next_val, st[2]=next_block, st[3]=scap

local lower_if = stmt_mod:get("mb_lower_if_stmt")
lower_if(0, 0, 1, 1, 1, e_tag, e_a, e_b, e_c, e_d, s_tag, s_tok, s_a, s_b, s_c, s_d, s_e, slist, st_if, cmds_rv)
-- First cmd is the condition literal, after that block cmds follow.
local ci = 1  -- skip condition const
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdCreateBlock, "if create then: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdCreateBlock, "if create else: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdCreateBlock, "if create join: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdBrIf, "if br_if: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdSwitchToBlock, "if switch then: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
-- then-body: CmdReturnVoid
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdReturnVoid, "if then return void: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
-- jump to join
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdJump, "if then->join: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
-- switch to else
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdSwitchToBlock, "if switch then: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
-- then-body: CmdReturnVoid
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdReturnVoid, "if then return void: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
-- jump to join
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdJump, "if then->join: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1
-- switch to else block
assert(cmds_rv[ci*STMT_CMD_STRIDE+0] == T.CmdSwitchToBlock, "if switch else: " .. tonumber(cmds_rv[ci*STMT_CMD_STRIDE+0])); ci = ci + 1

-- Test lower_if_stmt: if with NO else
local st_if2 = ffi.new("int32_t[4]", 0, 0, 100, scap)
local cmds_if2 = ffi.new("int32_t[?]", scap * STMT_CMD_STRIDE)
local slist2 = ffi.new("int32_t[1]", 0)
lower_if(0, 0, 1, -1, 0, e_tag, e_a, e_b, e_c, e_d, s_tag, s_tok, s_a, s_b, s_c, s_d, s_e, slist2, st_if2, cmds_if2)
-- Skip condition (CmdConst), then: 3x create, 1x br_if, switch then, return void, jump join, switch else, jump join, switch join
local ci2 = 1  -- skip condition const
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdCreateBlock, "if2 create then"); ci2 = ci2 + 1
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdCreateBlock, "if2 create else"); ci2 = ci2 + 1
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdCreateBlock, "if2 create join"); ci2 = ci2 + 1
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdBrIf, "if2 br_if"); ci2 = ci2 + 1
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdSwitchToBlock, "if2 switch then"); ci2 = ci2 + 1
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdReturnVoid, "if2 then return void"); ci2 = ci2 + 1
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdJump, "if2 then->join"); ci2 = ci2 + 1
-- Else block switch always emitted (CFG completeness)
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdSwitchToBlock, "if2 switch else"); ci2 = ci2 + 1
-- No else body (else_start=-1), so jump to join immediately
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdJump, "if2 else->join"); ci2 = ci2 + 1
-- Join block
assert(cmds_if2[ci2*STMT_CMD_STRIDE+0] == T.CmdSwitchToBlock, "if2 switch join"); ci2 = ci2 + 1

-- Total cmds for if-no-else: 1 cond + 3 create + 1 br_if + 1 then_switch + 1 then_body + 1 then_jump + 1 else_switch + 1 else_jump + 1 join_switch = 11
-- Total cmds for if-with-else: 1 cond + 3 create + 1 br_if + 1 then_switch + 1 then_body + 1 then_jump + 1 else_switch + 1 else_body + 1 else_jump + 1 join_switch = 12
assert(st_if2[0] == 11, "if no else cmd count: " .. tonumber(st_if2[0]))
assert(st_if[0] == 12, "if with else cmd count: " .. tonumber(st_if[0]))

stmt_mod.artifact:free()
end -- stmt_lower do-block

-- Phase 6: Control analysis (back/control.mlua)
local ctrl_mod = compile("lua/moonlift/mom/back/control.mlua")
local push_fact = ctrl_mod:get("mb_push_fact")
local push_reject = ctrl_mod:get("mb_push_reject")
local validate = ctrl_mod:get("mb_validate_control")

-- Build a valid fact tape: one block + one jump to that block.
-- CF_BLOCK, label_id=1
-- CF_JUMP, region=0, target=1
local cf_cap = 64
local cf_tag = ffi.new("int32_t[?]", cf_cap)
local cf_a = ffi.new("int32_t[?]", cf_cap)
local cf_b = ffi.new("int32_t[?]", cf_cap)
local cf_c = ffi.new("int32_t[?]", cf_cap)
local cf_d = ffi.new("int32_t[?]", cf_cap)
local cf_e = ffi.new("int32_t[?]", cf_cap)
local cf_f = ffi.new("int32_t[?]", cf_cap)
local cf_cnt = ffi.new("int32_t[1]", 0)
push_fact(T.CF_BLOCK, 1, 0, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
push_fact(T.CF_JUMP, 0, 1, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
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
push_fact(T.CF_JUMP, 0, 99, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], false, 0, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "missing label should be irreducible: " .. tonumber(result))
assert(r_cnt[0] >= 1, "missing label should produce reject")

-- Test: duplicate label
cf_cnt[0] = 0; r_cnt[0] = 0
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(T.CF_BLOCK, 42, 0, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
push_fact(T.CF_BLOCK, 42, 0, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], false, 0, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "duplicate label should be irreducible: " .. tonumber(result))

-- Test: yield void in expr region
cf_cnt[0] = 0; r_cnt[0] = 0
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(T.CF_YIELD_VOID, 0, 0, 0, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], true, 5, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "yield void in expr region should be irreducible: " .. tonumber(result))

-- Test: yield value type mismatch
cf_cnt[0] = 0; r_cnt[0] = 0
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(T.CF_YIELD_VALUE, 0, 0, 3, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
-- result_scalar=BackI32, actual=3 → mismatch
result = validate(cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f,
    cf_cnt[0], true, 5, mkey, mval, mst, map_cap, r_tag, r_a, r_b, r_c, r_cnt, cf_cap)
assert(result == 2, "yield type mismatch should be irreducible: " .. tonumber(result))

-- Test: yield value in stmt region
cf_cnt[0] = 0; r_cnt[0] = 0
for i = 0, map_cap - 1 do mst[i] = 0 end
push_fact(T.CF_YIELD_VALUE, 0, 0, T.BackI32, 0, 0, 0, cf_tag, cf_a, cf_b, cf_c, cf_d, cf_e, cf_f, cf_cnt, cf_cap)
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
ct[0]=T.CmdCreateSig; ca[0]=10; cb[0]=0; cc_arr[0]=0                         -- CmdCreateSig sig=10
ct[1]=T.CmdDeclareFunc; ca[1]=0; cb[1]=20; cc_arr[1]=10                         -- CmdDeclareFunc vis=0 func=20 sig=10
ct[2]=T.CmdBeginFunc; ca[2]=20                                                -- CmdBeginFunc func=20
ct[3]=T.CmdConst; ca[3]=40                                                -- CmdConst val=40
ct[4]=T.CmdReturnVoid                                                          -- CmdReturnVoid
ct[5]=T.CmdFinishFunc; ca[5]=20                                                -- CmdFinishFunc func=20
ct[6]=T.CmdFinalizeModule                                                          -- CmdFinalizeModule
validate(ct, ca, cb, cc_arr, cd, ce, cf, 7, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 0, "valid program issues: " .. tonumber(icnt[0]))

-- Duplicate sig
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=T.CmdCreateSig; ca[0]=10
ct[1]=T.CmdCreateSig; ca[1]=10
ct[2]=T.CmdFinalizeModule
validate(ct, ca, cb, cc_arr, cd, ce, cf, 3, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 1, "dup sig: " .. tonumber(icnt[0]))
assert(it[0] == T.BackIssueDuplicateSig, "dup sig tag: " .. tonumber(it[0]))

-- Missing sig reference in declare_func
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=T.CmdDeclareFunc; ca[0]=0; cb[0]=20; cc_arr[0]=99  -- CmdDeclareFunc sig=99 (not created)
ct[1]=T.CmdFinalizeModule
validate(ct, ca, cb, cc_arr, cd, ce, cf, 2, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 1, "missing sig ref: " .. tonumber(icnt[0]))

-- Missing block
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=T.CmdBeginFunc; ca[0]=1      -- CmdBeginFunc
ct[1]=T.CmdSwitchToBlock; ca[1]=99     -- CmdSwitchToBlock block=99 (not created)
ct[2]=T.CmdFinishFunc; ca[2]=1      -- CmdFinishFunc
ct[3]=T.CmdFinalizeModule
validate(ct, ca, cb, cc_arr, cd, ce, cf, 4, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] >= 1, "missing block: " .. tonumber(icnt[0]))

-- Nested function
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=T.CmdBeginFunc; ca[0]=1      -- CmdBeginFunc A
ct[1]=T.CmdBeginFunc; ca[1]=2      -- CmdBeginFunc B (nested!)
ct[2]=T.CmdFinishFunc; ca[2]=2      -- CmdFinishFunc B
ct[3]=T.CmdFinalizeModule               -- CmdFinalizeModule
validate(ct, ca, cb, cc_arr, cd, ce, cf, 4, it, ia, ib, ic, icnt, cap, ms, mk, 8)
assert(icnt[0] == 1, "nested: " .. tonumber(icnt[0]))
assert(it[0] == T.BackIssueNestedFunction, "nested tag: " .. tonumber(it[0]))

-- Cmd outside function
icnt[0] = 0; for i = 0, 63 do ms[i] = 0 end
ct[0]=T.CmdConst; ca[0]=40     -- CmdConst outside func
ct[1]=T.CmdFinalizeModule
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
