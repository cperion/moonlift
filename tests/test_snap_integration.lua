-- tests/test_snap_integration.lua
-- Integration test for snapshot capture.
-- Wires JitState → GCtrace → snap/snapmap buffers, calls snap_add_test,
-- then verifies the SnapShot header and SnapEntry records.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local Run = require("moonlift.mlua_run")

local snap_mv = Run.dofile("mlua/luajitvm/jit/snap.mlua")
local snap    = snap_mv:compile()
local snap_add = snap:get("snap_add_test")

-- =========================================================================
-- Allocate buffers
-- =========================================================================
local J_BUF      = ffi.new("uint8_t[?]", 32)
local TR_BUF     = ffi.new("uint8_t[?]", 104)
local SNAP_BUF   = ffi.new("uint8_t[?]", 256 * 16)   -- 256 SnapShot headers × 16 bytes
local SMAP_BUF   = ffi.new("uint8_t[?]", 4096 * 4)   -- 4096 SnapEntry × 4 bytes
local SLOTS_BUF  = ffi.new("int32_t[?]", 8)           -- 8 slot refs for test

local J_ptr      = ffi.cast("void *", J_BUF)
local TR_ptr     = ffi.cast("void *", TR_BUF)
local SNAP_ptr   = ffi.cast("void *", SNAP_BUF)
local SMAP_ptr   = ffi.cast("void *", SMAP_BUF)
local SLOTS_ptr  = ffi.cast("void *", SLOTS_BUF)

local J_u64  = ffi.cast("uint64_t *", J_BUF)
local TR_u64 = ffi.cast("uint64_t *", TR_BUF)
local TR_u16 = ffi.cast("uint16_t *", TR_BUF)
local TR_u32 = ffi.cast("uint32_t *", TR_BUF)
local SNAP_u32 = ffi.cast("uint32_t *", SNAP_BUF)
local SMAP_u32 = ffi.cast("uint32_t *", SMAP_BUF)

-- Wire pointers
J_u64[0]  = ffi.cast("uintptr_t", TR_ptr)   -- J.cur.trace
TR_u64[5] = ffi.cast("uintptr_t", SNAP_ptr)  -- GCtrace.snap  at offset 40
TR_u64[6] = ffi.cast("uintptr_t", SMAP_ptr)  -- GCtrace.snapmap at offset 48

-- J.cur.nins = 1, J.cur.nk = 0x8000
J_u64[1] = 1
J_u64[2] = 0x8000

-- GCtrace.nsnap = 0, nsnapmap = 0
TR_u16[8] = 0   -- nsnap at offset 16
TR_u32[9] = 0   -- nsnapmap at offset 36

-- =========================================================================
-- Test helpers
-- =========================================================================
local passed, failed = 0, 0
local function check(name, expected, actual)
    local e = tonumber(expected); local a = tonumber(actual)
    if e == a then
        passed = passed + 1
        io.write(string.format("  OK   %-42s = %d\n", name, a))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-42s expected %d, got %d\n", name, e, a))
    end
end

-- =========================================================================
-- Test 1: basic snapshot with 3 live slots
-- =========================================================================
-- slots: slot 0 → ref 0x8001, slot 1 → 0 (dead), slot 2 → ref 0x8002, slot 3 → ref 0x7FFF
SLOTS_BUF[0] = 0x8001
SLOTS_BUF[1] = 0           -- dead slot, no entry emitted
SLOTS_BUF[2] = 0x8002
SLOTS_BUF[3] = 0x7FFF
local NSLOTS = 4

local snap_idx0 = snap_add(J_ptr, SLOTS_ptr, NSLOTS, 0x8003)
check("snap_add returns snap_idx 0", 0, snap_idx0)

-- Read SnapShot header at index 0 (4 × u32)
-- p[0] = mapofs, p[1] = nslots, p[2] = nent (u16) | count (u16), p[3] = ref (u16) | depth (u16)
check("SnapShot[0].mapofs",  0,      SNAP_u32[0])   -- no prior entries
check("SnapShot[0].nslots",  NSLOTS, SNAP_u32[1])
check("SnapShot[0].nent",    3,      SNAP_u32[2])   -- slots 0, 2, 3 are live
check("SnapShot[0].ref",     0x8003, SNAP_u32[3])

-- GCtrace counters updated
check("tr.nsnap after add",    1, TR_u16[8])
check("tr.nsnapmap after add", 3, TR_u32[9])

-- Read SnapEntry records
-- Entry = (slot << 24) | (flags & 0x00FF0000) | (ref & 0xFFFF)
local function snap_slot(e)  return bit.rshift(tonumber(e), 24) end
local function snap_ref(e)   return bit.band(tonumber(e), 0xFFFF) end

check("SnapEntry[0] slot", 0,      snap_slot(SMAP_u32[0]))
check("SnapEntry[0] ref",  0x8001, snap_ref(SMAP_u32[0]))
check("SnapEntry[1] slot", 2,      snap_slot(SMAP_u32[1]))
check("SnapEntry[1] ref",  0x8002, snap_ref(SMAP_u32[1]))
check("SnapEntry[2] slot", 3,      snap_slot(SMAP_u32[2]))
check("SnapEntry[2] ref",  0x7FFF, snap_ref(SMAP_u32[2]))

-- =========================================================================
-- Test 2: second snapshot reuses snapmap correctly
-- =========================================================================
SLOTS_BUF[0] = 0x8004
SLOTS_BUF[1] = 0x8005
SLOTS_BUF[2] = 0
SLOTS_BUF[3] = 0

local snap_idx1 = snap_add(J_ptr, SLOTS_ptr, 2, 0x8006)
check("snap_add returns snap_idx 1",    1,  snap_idx1)
check("SnapShot[1].mapofs",             3,  SNAP_u32[4])   -- starts after 3 prior entries
check("SnapShot[1].nslots",             2,  SNAP_u32[5])
check("SnapShot[1].nent",               2,  SNAP_u32[6])
check("tr.nsnap = 2",                   2,  TR_u16[8])
check("tr.nsnapmap = 5",                5,  TR_u32[9])
check("SnapEntry[3] slot",              0,  snap_slot(SMAP_u32[3]))
check("SnapEntry[3] ref",               0x8004, snap_ref(SMAP_u32[3]))
check("SnapEntry[4] slot",              1,  snap_slot(SMAP_u32[4]))
check("SnapEntry[4] ref",               0x8005, snap_ref(SMAP_u32[4]))

snap:free()
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All snapshot integration tests passed")
