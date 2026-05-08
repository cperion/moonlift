-- tests/test_gc_alloc.lua
-- GC allocation smoke test: FFI-backed objects, Moonlift header init + linking.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

-- Compile modules
local alloc_mv   = Run.dofile("mlua/luajitvm/gc/alloc.mlua")
local barrier_mv = Run.dofile("mlua/luajitvm/gc/barrier.mlua")
local alloc   = alloc_mv:compile()
local barrier = barrier_mv:compile()

-- Create a minimal global_State buffer (576 bytes for extended layout)
local G_buf  = ffi.new("uint8_t[?]", 576)
local G_ptr  = ffi.cast("void *", G_buf)
local G_u64  = ffi.cast("uint64_t *", G_buf)

-- Initialize GlobalState: currentwhite = WHITE1 (1), gc_root = NULL
G_buf[32] = 1       -- gc.currentwhite = WHITE1
G_u64[5]  = 0       -- gc.root = NULL (offset 40)

-- Helper: read u8 at byte offset
local function u8_at(buf, off)
    return buf[off]
end

-- Helper: read u64 at byte offset
local function u64_at(buf, off)
    local p = ffi.cast("uint64_t *", ffi.cast("uint8_t *", buf) + off)
    return tonumber(p[0])
end

-- Create raw object memory (32 bytes each)
local obj1 = ffi.new("uint8_t[?]", 32)
local obj2 = ffi.new("uint8_t[?]", 32)
local obj3 = ffi.new("uint8_t[?]", 32)
local obj1_ptr = ffi.cast("void *", obj1)
local obj2_ptr = ffi.cast("void *", obj2)
local obj3_ptr = ffi.cast("void *", obj3)

-- Init with different types and link
alloc:get("gc_init_and_link")(G_ptr, obj1_ptr, 0)  -- GCT_STR
alloc:get("gc_init_and_link")(G_ptr, obj2_ptr, 4)  -- GCT_FUNC
alloc:get("gc_init_and_link")(G_ptr, obj3_ptr, 7)  -- GCT_TAB

-- Verify headers
local function check(name, expected, actual)
    if expected == actual then
        print(string.format("  OK   %-25s = %d", name, actual))
    else
        error(string.format("  FAIL %-25s expected %d, got %d", name, expected, actual))
    end
end

-- Check obj1 (STR): marked=1(WHITE1), gct=0, next should point to NULL (was linked first, so last in list)
check("obj1 marked", 1, u8_at(obj1, 8))
check("obj1 gct",    0, u8_at(obj1, 9))

-- Check obj2 (FUNC): marked=1, gct=4, next should point to obj1
check("obj2 marked", 1, u8_at(obj2, 8))
check("obj2 gct",    4, u8_at(obj2, 9))
check("obj2 next",   ffi.cast("uint64_t", obj1_ptr), u64_at(obj2, 0))

-- Check obj3 (TAB): marked=1, gct=7, next should point to obj2
check("obj3 marked", 1, u8_at(obj3, 8))
check("obj3 gct",    7, u8_at(obj3, 9))
check("obj3 next",   ffi.cast("uint64_t", obj2_ptr), u64_at(obj3, 0))

-- Check G.gc_root points to obj3 (most recently linked)
check("G.root", ffi.cast("uint64_t", obj3_ptr), tonumber(G_u64[5]))

-- Test mark helpers
alloc:get("gc_mark_black")(obj1_ptr)
check("obj1 black", 3, u8_at(obj1, 8))  -- GC_BLACK = 3

alloc:get("gc_mark_gray")(obj2_ptr)
check("obj2 gray", 2, u8_at(obj2, 8))   -- GC_GRAY = 2

-- Test is_white / is_black
local is_white_fn = alloc:get("gc_is_white")
local is_black_fn = alloc:get("gc_is_black")

-- obj1 is black, so is_white(obj1, WHITE1=1) should be false
assert(not is_white_fn(obj1_ptr, 1), "black obj should not be white")
-- obj2 is gray, so is_white(obj2, WHITE1=1) should be false
assert(not is_white_fn(obj2_ptr, 1), "gray obj should not be white")
-- obj3 is still white(1), so is_white(obj3, WHITE1=1) should be true
assert(is_white_fn(obj3_ptr, 1), "white obj should be white")
-- obj1 is black
assert(is_black_fn(obj1_ptr), "obj1 should be black")

-- Barrier regions: verify they compile (regions can't be called directly from Lua)
assert(barrier:get("barrier_const_check")() == 1, "barrier sentinel")

alloc:free()
barrier:free()
print("\nAll GC allocation tests passed")
