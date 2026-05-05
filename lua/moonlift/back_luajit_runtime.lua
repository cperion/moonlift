-- back_luajit_runtime.lua — runtime helpers for generated MoonBack LuaJIT code.
-- This module is intentionally small and side-effect free except for FFI cdefs.
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
typedef union moonlift_luajit_u64_box_t {
  uint64_t u;
  int64_t i;
  uint32_t u32[2];
  int32_t i32[2];
  double d;
} moonlift_luajit_u64_box_t;
]]

local M = {}

local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, arshift = bit.lshift, bit.rshift, bit.arshift
local floor, ceil, sqrt, abs = math.floor, math.ceil, math.sqrt, math.abs
local box_t = ffi.typeof("moonlift_luajit_u64_box_t")
local u8p_t = ffi.typeof("uint8_t*")
local voidp_t = ffi.typeof("void*")
local uintptr_t = ffi.typeof("uintptr_t")
local int64_t = ffi.typeof("int64_t")
local uint64_t = ffi.typeof("uint64_t")
local float_t = ffi.typeof("float")

local TWO32 = 4294967296
local TWO31 = 2147483648

function M.u8(x) return band(tonumber(x) or 0, 0xff) end
function M.u16(x) return band(tonumber(x) or 0, 0xffff) end
function M.u32(x)
  x = tonumber(x) or 0
  x = x % TWO32
  if x < 0 then x = x + TWO32 end
  return x
end
function M.s8(x) x = M.u8(x); if x >= 0x80 then return x - 0x100 end; return x end
function M.s16(x) x = M.u16(x); if x >= 0x8000 then return x - 0x10000 end; return x end
function M.s32(x) x = M.u32(x); if x >= TWO31 then return x - TWO32 end; return x end
function M.bool8(x) return x ~= nil and x ~= false and x ~= 0 and 1 or 0 end
function M.f32(x) return tonumber(ffi.cast(float_t, x)) end
function M.trunc(x) if x >= 0 then return floor(x) else return ceil(x) end end
function M.round(x)
  -- Cranelift nearest is nearest-even. LuaJIT has no direct primitive; implement it.
  local f = floor(x)
  local d = x - f
  if d < 0.5 then return f end
  if d > 0.5 then return f + 1 end
  return (f % 2 == 0) and f or (f + 1)
end
function M.bswap32(x) return M.u32(bit.bswap(x)) end
function M.popc32(x)
  x = M.u32(x)
  local c = 0
  while x ~= 0 do x = band(x, x - 1); c = c + 1 end
  return c
end
function M.clz32(x)
  x = M.u32(x)
  if x == 0 then return 32 end
  local n, bitv = 0, 0x80000000
  while band(x, bitv) == 0 do n = n + 1; bitv = rshift(bitv, 1) end
  return n
end
function M.ctz32(x)
  x = M.u32(x)
  if x == 0 then return 32 end
  local n = 0
  while band(x, 1) == 0 do n = n + 1; x = rshift(x, 1) end
  return n
end
function M.imul32(a, b)
  a, b = M.u32(a), M.u32(b)
  local alo, ahi = band(a, 0xffff), rshift(a, 16)
  local blo, bhi = band(b, 0xffff), rshift(b, 16)
  local lo = alo * blo
  local mid = alo * bhi + ahi * blo
  return M.u32(lo + lshift(band(mid, 0xffff), 16))
end
function M.sdiv32(a,b)
  a, b = M.s32(a), M.s32(b)
  if b == 0 then error("integer divide by zero") end
  if a == -2147483648 and b == -1 then error("integer divide overflow") end
  return M.u32(M.trunc(a / b))
end
function M.udiv32(a,b)
  a, b = M.u32(a), M.u32(b)
  if b == 0 then error("integer divide by zero") end
  return M.u32(floor(a / b))
end
function M.srem32(a,b)
  local q = M.s32(M.sdiv32(a,b))
  return M.u32(M.s32(a) - q * M.s32(b))
end
function M.urem32(a,b)
  a, b = M.u32(a), M.u32(b)
  if b == 0 then error("integer divide by zero") end
  return M.u32(a % b)
end

local function box_from_parts(lo, hi)
  local b = box_t()
  b.u32[0] = M.u32(lo)
  b.u32[1] = M.u32(hi)
  return b
end
local function parts_from_box(b)
  return tonumber(b.u32[0]), tonumber(b.u32[1])
end
function M.pack_u64(lo, hi) return box_from_parts(lo, hi).u end
function M.pack_i64(lo, hi) return box_from_parts(lo, hi).i end
function M.unpack_u64(x) local b=box_t(); b.u=ffi.cast(uint64_t, x); return parts_from_box(b) end
function M.unpack_i64(x) local b=box_t(); b.i=ffi.cast(int64_t, x); return parts_from_box(b) end
local function parse_u64_decimal(raw)
  raw = tostring(raw)
  local lo, hi = 0, 0
  for i = 1, #raw do
    local c = raw:byte(i)
    if c >= 48 and c <= 57 then
      local d = c - 48
      local x = lo * 10 + d
      local carry = floor(x / TWO32)
      lo = x - carry * TWO32
      hi = (hi * 10 + carry) % TWO32
    end
  end
  return M.u32(lo), M.u32(hi)
end
function M.const_u64(raw) return parse_u64_decimal(raw) end
function M.const_i64(raw)
  raw = tostring(raw)
  if raw:sub(1,1) == "-" then
    local lo, hi = parse_u64_decimal(raw:sub(2))
    return M.u64_sub(0, 0, lo, hi)
  end
  return parse_u64_decimal(raw)
end
function M.u64_to_number(lo, hi) return M.u32(lo) + M.u32(hi) * TWO32 end
function M.i64_to_number(lo, hi)
  hi = M.u32(hi)
  local n = M.u32(lo) + hi * TWO32
  if hi >= TWO31 then n = n - TWO32 * TWO32 end
  return n
end

local function u64_bin(a_lo,a_hi,b_lo,b_hi,op)
  local r = box_t(); r.u = op(M.pack_u64(a_lo,a_hi), M.pack_u64(b_lo,b_hi)); return parts_from_box(r)
end
local function i64_bin(a_lo,a_hi,b_lo,b_hi,op)
  local r = box_t(); r.i = op(M.pack_i64(a_lo,a_hi), M.pack_i64(b_lo,b_hi)); return parts_from_box(r)
end
function M.u64_add(a,b,c,d) return u64_bin(a,b,c,d,function(x,y) return x+y end) end
function M.u64_sub(a,b,c,d) return u64_bin(a,b,c,d,function(x,y) return x-y end) end
function M.u64_mul(a,b,c,d)
  a,b,c,d = M.u32(a), M.u32(b), M.u32(c), M.u32(d)
  if b == 0 and d == 0 then
    local p = a * c
    if p < 9007199254740992 then
      local hi = floor(p / TWO32)
      return M.u32(p - hi * TWO32), M.u32(hi)
    end
  end
  return u64_bin(a,b,c,d,function(x,y) return x*y end)
end
function M.i64_sdiv(a,b,c,d) if c==0 and d==0 then error("integer divide by zero") end; return i64_bin(a,b,c,d,function(x,y) return x/y end) end
function M.u64_udiv(a,b,c,d) if c==0 and d==0 then error("integer divide by zero") end; return u64_bin(a,b,c,d,function(x,y) return x/y end) end
function M.i64_srem(a,b,c,d) if c==0 and d==0 then error("integer divide by zero") end; return i64_bin(a,b,c,d,function(x,y) return x%y end) end
function M.u64_urem(a,b,c,d) if c==0 and d==0 then error("integer divide by zero") end; return u64_bin(a,b,c,d,function(x,y) return x%y end) end
function M.u64_band(a,b,c,d) return band(a,c), band(b,d) end
function M.u64_bor(a,b,c,d) return M.u32(bor(a,c)), M.u32(bor(b,d)) end
function M.u64_bxor(a,b,c,d) return M.u32(bxor(a,c)), M.u32(bxor(b,d)) end
function M.u64_bnot(a,b) return M.u32(bnot(a)), M.u32(bnot(b)) end
function M.u64_shl(lo,hi,n)
  n = band(tonumber(n) or 0, 63)
  lo, hi = M.u32(lo), M.u32(hi)
  if n == 0 then return lo, hi end
  if n < 32 then return M.u32(lshift(lo,n)), M.u32(bor(lshift(hi,n), rshift(lo,32-n))) end
  return 0, M.u32(lshift(lo,n-32))
end
function M.u64_shr(lo,hi,n)
  n = band(tonumber(n) or 0, 63)
  lo, hi = M.u32(lo), M.u32(hi)
  if n == 0 then return lo, hi end
  if n < 32 then return M.u32(bor(rshift(lo,n), lshift(hi,32-n))), M.u32(rshift(hi,n)) end
  return M.u32(rshift(hi,n-32)), 0
end
function M.i64_shr(lo,hi,n)
  n = band(tonumber(n) or 0, 63)
  lo, hi = M.u32(lo), M.u32(hi)
  if n == 0 then return lo, hi end
  if n < 32 then return M.u32(bor(rshift(lo,n), lshift(hi,32-n))), M.u32(arshift(hi,n)) end
  local fill = hi >= TWO31 and 0xffffffff or 0
  return M.u32(arshift(hi,n-32)), fill
end
function M.u64_rotl(lo,hi,n)
  n = band(tonumber(n) or 0, 63)
  if n == 0 then return M.u32(lo), M.u32(hi) end
  local a,b = M.u64_shl(lo,hi,n)
  local c,d = M.u64_shr(lo,hi,64-n)
  return M.u64_bor(a,b,c,d)
end
function M.u64_rotr(lo,hi,n)
  n = band(tonumber(n) or 0, 63)
  if n == 0 then return M.u32(lo), M.u32(hi) end
  local a,b = M.u64_shr(lo,hi,n)
  local c,d = M.u64_shl(lo,hi,64-n)
  return M.u64_bor(a,b,c,d)
end
function M.u64_eq(a,b,c,d) return a == c and b == d end
function M.u64_lt(a,b,c,d) b,d=M.u32(b),M.u32(d); if b ~= d then return b < d end; return M.u32(a) < M.u32(c) end
function M.u64_le(a,b,c,d) return M.u64_eq(a,b,c,d) or M.u64_lt(a,b,c,d) end
function M.i64_lt(a,b,c,d)
  b,d=M.u32(b),M.u32(d)
  local sb, sd = b >= TWO31, d >= TWO31
  if sb ~= sd then return sb end
  return M.u64_lt(a,b,c,d)
end
function M.i64_le(a,b,c,d) return M.u64_eq(a,b,c,d) or M.i64_lt(a,b,c,d) end
function M.u64_popcnt(lo,hi) return M.popc32(lo) + M.popc32(hi), 0 end
function M.u64_clz(lo,hi) hi=M.u32(hi); if hi ~= 0 then return M.clz32(hi), 0 end; return 32 + M.clz32(M.u32(lo)), 0 end
function M.u64_ctz(lo,hi) lo=M.u32(lo); if lo ~= 0 then return M.ctz32(lo), 0 end; return 32 + M.ctz32(M.u32(hi)), 0 end
function M.u64_bswap(lo,hi) return M.u32(bit.bswap(hi)), M.u32(bit.bswap(lo)) end
function M.sext64(width, x)
  if width == 8 then x=M.u8(x); if x >= 0x80 then return x, 0xffffffff else return x, 0 end end
  if width == 16 then x=M.u16(x); if x >= 0x8000 then return x, 0xffffffff else return x, 0 end end
  x=M.u32(x); if x >= TWO31 then return x, 0xffffffff else return x, 0 end
end
function M.uext64(_, x) return M.u32(x), 0 end

function M.null_ptr() return ffi.cast(voidp_t, 0) end
function M.alloc_aligned(size, align)
  size = tonumber(size) or 0; align = tonumber(align) or 1
  if align < 1 or band(align, align - 1) ~= 0 then error("alignment must be a positive power of two") end
  local alloc = size + align
  if alloc < 1 then alloc = 1 end
  local owner = ffi.new("uint8_t[?]", alloc)
  local addr = ffi.cast(uintptr_t, owner)
  local rem = tonumber(addr % ffi.cast(uintptr_t, align))
  local add = (align - rem) % align
  -- Return a pointer derived from the owner cdata, not from an integer address,
  -- so LuaJIT keeps the allocation association stable across GC.
  return owner, ffi.cast(u8p_t, owner) + add
end
function M.ptr_add_bytes(ptr, off_lo, off_hi)
  off_lo, off_hi = M.u32(off_lo), M.u32(off_hi or 0)
  if off_hi == 0 and off_lo == 0 then return ptr end
  if off_hi == 0 and off_lo < 2147483648 then
    return ffi.cast(u8p_t, ptr) + off_lo
  end
  local base = ffi.cast(uintptr_t, ptr)
  local off = M.pack_u64(off_lo, off_hi)
  return ffi.cast(u8p_t, base + off)
end
function M.ptr_add_num(ptr, off) return ffi.cast(u8p_t, ptr) + tonumber(off) end
function M.ptr_offset(ptr, idx_lo, idx_hi, elem_size, const_offset)
  local off_lo, off_hi = M.u64_mul(idx_lo, idx_hi or 0, elem_size or 1, 0)
  if const_offset and const_offset ~= 0 then
    local clo, chi = M.const_i64(tostring(const_offset))
    off_lo, off_hi = M.u64_add(off_lo, off_hi, clo, chi)
  end
  return M.ptr_add_bytes(ptr, off_lo, off_hi)
end

function M.load_u64(ptr) local b=box_t(); b.u=ffi.cast("uint64_t*", ptr)[0]; return parts_from_box(b) end
function M.load_i64(ptr) local b=box_t(); b.i=ffi.cast("int64_t*", ptr)[0]; return parts_from_box(b) end
function M.store_u64(ptr, lo, hi) ffi.cast("uint64_t*", ptr)[0] = M.pack_u64(lo,hi) end
function M.store_i64(ptr, lo, hi) ffi.cast("int64_t*", ptr)[0] = M.pack_i64(lo,hi) end

local scalar_bytes = { Bool=1,I8=1,U8=1,I16=2,U16=2,I32=4,U32=4,I64=8,U64=8,F32=4,F64=8,Ptr=ffi.abi("64bit") and 8 or 4,Index=ffi.abi("64bit") and 8 or 4 }
function M.scalar_bytes(sn) return scalar_bytes[sn] or error("unknown scalar "..tostring(sn)) end

function M.data_zero(ptr, offset, size) ffi.fill(ffi.cast(u8p_t, ptr) + offset, size, 0) end
function M.data_init(ptr, offset, sn, kind, raw)
  local p = ffi.cast(u8p_t, ptr) + offset
  if kind == "N" then ffi.fill(p, scalar_bytes[sn], 0); return end
  if sn == "Bool" then ffi.cast("uint8_t*", p)[0] = (raw == true or raw == "1" or raw == 1) and 1 or 0; return end
  if sn == "I8" then ffi.cast("int8_t*", p)[0] = tonumber(raw); return end
  if sn == "U8" then ffi.cast("uint8_t*", p)[0] = tonumber(raw); return end
  if sn == "I16" then ffi.cast("int16_t*", p)[0] = tonumber(raw); return end
  if sn == "U16" then ffi.cast("uint16_t*", p)[0] = tonumber(raw); return end
  if sn == "I32" then ffi.cast("int32_t*", p)[0] = tonumber(raw); return end
  if sn == "U32" then ffi.cast("uint32_t*", p)[0] = tonumber(raw); return end
  if sn == "I64" then ffi.cast("int64_t*", p)[0] = ffi.cast(int64_t, raw); return end
  if sn == "U64" or sn == "Index" or sn == "Ptr" then ffi.cast("uint64_t*", p)[0] = ffi.cast(uint64_t, raw); return end
  if sn == "F32" then ffi.cast("float*", p)[0] = tonumber(raw); return end
  if sn == "F64" then ffi.cast("double*", p)[0] = tonumber(raw); return end
  error("unsupported data init scalar "..tostring(sn))
end

return M
