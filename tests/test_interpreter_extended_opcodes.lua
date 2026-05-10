-- tests/test_interpreter_extended_opcodes.lua
-- Extra bytecode coverage for LuaJIT VM interpreter bring-up.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local dispatch = Run.dofile("mlua/luajitvm/runtime/dispatch.mlua"):compile()

local STACK_SLOTS = 128
local TValueSize = 16
local StackBytes = STACK_SLOTS * TValueSize
local state_buf = ffi.new("uint8_t[?]", 128)
local stack_buf = ffi.new("uint8_t[?]", StackBytes)
local callinfo_buf = ffi.new("uint8_t[?]", 32 * 16)
local state_u64 = ffi.cast("uint64_t *", state_buf)
local stack_uint = tonumber(ffi.cast("uintptr_t", stack_buf))
state_u64[4] = stack_uint
state_u64[5] = stack_uint + StackBytes
state_u64[7] = stack_uint
state_u64[14] = tonumber(ffi.cast("uintptr_t", callinfo_buf))

local function reset(setup)
  ffi.fill(stack_buf, StackBytes, 0)
  ffi.fill(callinfo_buf, 32 * 16, 0)
  state_u64[4] = stack_uint
  state_u64[5] = stack_uint + StackBytes
  state_u64[7] = stack_uint
  state_u64[14] = tonumber(ffi.cast("uintptr_t", callinfo_buf))
  ffi.cast("uint32_t *", state_buf)[30] = 0
  if setup then setup() end
end

local function run(bc, setup)
  reset(setup)
  local nres = dispatch:get("vm_interp_run")(ffi.cast("void *", state_buf), ffi.cast("void *", bc), 0, 0)
  return tonumber(ffi.cast("int64_t *", stack_buf)[1]), nres
end

local function make_proto(nbc, nconst)
  local proto = ffi.new("uint8_t[?]", 96 + nbc * 4)
  local k = ffi.new("uint8_t[?]", nconst * 16)
  ffi.cast("uint64_t *", proto)[3] = tonumber(ffi.cast("uintptr_t", k))
  return proto, k, ffi.cast("uint32_t *", proto + 96)
end

local function bc_ad(op, a, d) if d < 0 then d = d + 65536 end; return op + a*256 + d*65536 end
local function bc_abc(op, a, b, c) return op + a*256 + c*65536 + b*16777216 end
local function kshort(a, d) return bc_ad(41, a, d) end
local function ret1(a) return 76 + a*256 end
local function set_slot(slot, tag, payload)
  ffi.cast("int32_t *", stack_buf)[slot*4] = tag
  ffi.cast("int64_t *", stack_buf)[slot*2 + 1] = payload or 0
end

local passed, failed = 0, 0
local function check(name, exp, got)
  if exp == got then passed = passed + 1; print(("  OK   %-24s = %s"):format(name, tostring(got)))
  else failed = failed + 1; print(("  FAIL %-24s expected %s got %s"):format(name, tostring(exp), tostring(got))) end
end

-- ISEQS / ISNES against proto string constant.
do
  local proto, k, bc = make_proto(8, 1)
  local s = ffi.new("uint8_t[?]", 32)
  ffi.cast("uint32_t *", s)[5] = 3 -- GCstr.len
  ffi.cast("int32_t *", k)[0] = 5
  ffi.cast("int64_t *", k)[1] = tonumber(ffi.cast("uintptr_t", s))
  bc[0] = 39 + 0*256 -- KSTR A=0 D=0
  bc[1] = bc_ad(6, 0, 0) -- ISEQS slot0 == const0
  bc[2] = kshort(0, 11)
  bc[3] = ret1(0)
  check("iseqs_true", 11, run(bc))
  bc[1] = bc_ad(7, 0, 0) -- ISNES false, skip kshort
  check("isnes_false_skip", tonumber(ffi.cast("uintptr_t", s)), run(bc))
end

-- ISEQN / ISNEN against proto integer constant.
do
  local proto, k, bc = make_proto(8, 1)
  ffi.cast("int32_t *", k)[0] = 3
  ffi.cast("int64_t *", k)[1] = 42
  bc[0] = kshort(0, 42)
  bc[1] = bc_ad(8, 0, 0) -- ISEQN true
  bc[2] = kshort(0, 12)
  bc[3] = ret1(0)
  check("iseqn_true", 12, run(bc))
  bc[1] = bc_ad(9, 0, 0) -- ISNEN false, skip
  check("isnen_false_skip", 42, run(bc))
end

-- ISEQP / ISNEP primitive comparisons.
do
  local bc = ffi.new("uint32_t[?]", 8)
  bc[0] = bc_ad(43, 0, 2) -- KPRI true
  bc[1] = bc_ad(10, 0, 2) -- ISEQP true
  bc[2] = kshort(0, 13)
  bc[3] = ret1(0)
  check("iseqp_true", 13, run(bc))
  bc[1] = bc_ad(11, 0, 2) -- ISNEP false, skip
  check("isnep_false_skip", 0, run(bc))
end

-- IST/ISF and copy variants.
do
  local bc = ffi.new("uint32_t[?]", 12)
  bc[0] = kshort(1, 77)
  bc[1] = bc_ad(12, 0, 1) -- ISTC A=0 D=1 copies truthy slot1
  bc[2] = ret1(0)
  check("istc_copy", 77, run(bc))
  bc[0] = bc_ad(43, 1, 0) -- slot1=nil
  bc[1] = bc_ad(13, 0, 1) -- ISFC copies falsy nil; payload remains 0
  bc[2] = kshort(0, 14)
  bc[3] = ret1(0)
  check("isfc_copy_nil", 14, run(bc))
  bc[0] = kshort(0, 1); bc[1] = bc_ad(14, 0, 0); bc[2] = kshort(0, 15); bc[3] = ret1(0)
  check("ist_true", 15, run(bc))
  bc[0] = bc_ad(43, 0, 1); bc[1] = bc_ad(15, 0, 0); bc[2] = kshort(0, 16); bc[3] = ret1(0)
  check("isf_false_tag", 16, run(bc))
end

-- ISTYPE / ISNUM.
do
  local bc = ffi.new("uint32_t[?]", 8)
  bc[0] = kshort(0, 21)
  bc[1] = bc_ad(16, 0, 3) -- ISTYPE int
  bc[2] = kshort(0, 17)
  bc[3] = ret1(0)
  check("istype_int", 17, run(bc))
  bc[1] = bc_ad(17, 0, 0) -- ISNUM
  check("isnum_int", 17, run(bc))
end

-- KCDATA copies typed cdata constants.
do
  local proto, k, bc = make_proto(4, 1)
  ffi.cast("int32_t *", k)[0] = 12
  ffi.cast("int64_t *", k)[1] = 123456
  bc[0] = bc_ad(40, 0, 0)
  bc[1] = ret1(0)
  check("kcdata_payload", 123456, run(bc))
end

-- LEN for strings and raw table array length; LEN metamethod exits explicitly.
do
  local bc = ffi.new("uint32_t[?]", 4)
  local s = ffi.new("uint8_t[?]", 32)
  ffi.cast("uint32_t *", s)[5] = 5
  bc[0] = bc_abc(21, 0, 1, 0)
  bc[1] = ret1(0)
  check("len_string", 5, run(bc, function() set_slot(1, 5, tonumber(ffi.cast("uintptr_t", s))) end))

  local tab = ffi.new("uint8_t[?]", 56)
  local arr = ffi.new("uint8_t[?]", 16 * 4)
  ffi.cast("uint64_t *", tab)[2] = tonumber(ffi.cast("uintptr_t", arr))
  ffi.cast("uint32_t *", tab)[12] = 4
  ffi.cast("int32_t *", arr)[0] = 3; ffi.cast("int64_t *", arr)[1] = 1
  ffi.cast("int32_t *", arr)[4] = 3; ffi.cast("int64_t *", arr)[3] = 2
  ffi.cast("int32_t *", arr)[8] = 3; ffi.cast("int64_t *", arr)[5] = 3
  check("len_table", 3, run(bc, function() set_slot(1, 8, tonumber(ffi.cast("uintptr_t", tab))) end))

  local mt = ffi.new("uint8_t[?]", 56)
  local mtarr = ffi.new("uint8_t[?]", 16 * 8)
  ffi.cast("uint64_t *", mt)[2] = tonumber(ffi.cast("uintptr_t", mtarr))
  ffi.cast("uint32_t *", mt)[12] = 8
  ffi.cast("int32_t *", mtarr)[7*4] = 9
  ffi.cast("int64_t *", mtarr)[7*2 + 1] = 777
  ffi.cast("uint64_t *", tab)[4] = tonumber(ffi.cast("uintptr_t", mt))
  tab[10] = 0 -- clear negative metamethod cache after installing metatable
  local _, status = run(bc, function() set_slot(1, 8, tonumber(ffi.cast("uintptr_t", tab))) end)
  check("len_meta_exit", -509, status)
end

-- TGETR/TSETR raw table access for existing array slots.
do
  local bc = ffi.new("uint32_t[?]", 8)
  local tab = ffi.new("uint8_t[?]", 56)
  local arr = ffi.new("uint8_t[?]", 16 * 4)
  ffi.cast("uint64_t *", tab)[2] = tonumber(ffi.cast("uintptr_t", arr))
  ffi.cast("uint32_t *", tab)[12] = 4
  bc[0] = bc_abc(64, 3, 1, 2) -- TSETR value slot3 into table slot1/key slot2
  bc[1] = bc_abc(59, 0, 1, 2) -- TGETR slot0 = table[key]
  bc[2] = ret1(0)
  check("tsetr_tgetr_array", 654, run(bc, function()
    set_slot(1, 8, tonumber(ffi.cast("uintptr_t", tab)))
    set_slot(2, 3, 2)
    set_slot(3, 3, 654)
  end))
end

-- Function headers are interpreter no-ops.
do
  local bc = ffi.new("uint32_t[?]", 4)
  bc[0] = 89 -- FUNCF
  bc[1] = kshort(0, 88)
  bc[2] = ret1(0)
  check("funcf_noop", 88, run(bc))
end

-- ITERL/IITERL branch while slot A is non-nil.
do
  local bc = ffi.new("uint32_t[?]", 8)
  bc[0] = kshort(0, 1)
  bc[1] = bc_ad(82, 0, 1) -- non-nil slot0: jump to pc=3
  bc[2] = kshort(0, 99)   -- skipped
  bc[3] = ret1(0)
  check("iterl_branch", 1, run(bc))
  bc[0] = bc_ad(43, 0, 0) -- nil
  bc[1] = bc_ad(83, 0, 1) -- IITERL nil: fallthrough to kshort 22
  bc[2] = kshort(0, 22)
  bc[3] = ret1(0)
  check("iiterl_fallthrough", 22, run(bc))
end

dispatch:free()
if failed > 0 then error(failed .. " extended interpreter tests FAILED") end
print(string.format("extended interpreter opcodes ok (%d passed)", passed))
