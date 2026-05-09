-- tests/test_x64_emit.lua
-- Integration test for the x64 instruction emitter.
-- Emits real x64 machine code via the Moonlift regions, then
-- executes it through LuaJIT FFI to verify correctness.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi  = require("ffi")
local Run  = require("moonlift.mlua_run")

-- Compile both modules
local mcode_mv = Run.dofile("mlua/luajitvm/asm/mcode.mlua")
local mcode    = mcode_mv:compile()
local emit_mv  = Run.dofile("mlua/luajitvm/asm/x64_emit.mlua")
local emit     = emit_mv:compile()

-- FFI helpers
ffi.cdef([[
void *mmap(void *addr, size_t len, int prot, int flags, int fd, long offset);
int munmap(void *addr, size_t len);
int mprotect(void *addr, size_t len, int prot);
]])
local PROT_READ  = 0x1
local PROT_WRITE = 0x2
local PROT_EXEC  = 0x4
local MAP_PRIVATE   = 0x02
local MAP_ANON      = 0x20

local function alloc_rwx(size)
    local p = ffi.C.mmap(nil, size, PROT_READ + PROT_WRITE + PROT_EXEC,
                         MAP_PRIVATE + MAP_ANON, -1, 0)
    assert(p ~= nil and p ~= ffi.cast("void*", -1), "mmap failed")
    return p
end

-- JitState buffer (64 bytes)
local J_BUF = ffi.new("uint8_t[64]")
local J_ptr = ffi.cast("void *", J_BUF)
local J_u64 = ffi.cast("uint64_t *", J_BUF)

-- x64 machine code buffer (RWX memory, 4096 bytes)
local MCODE_SIZE = 4096
local MCODE_PTR = alloc_rwx(MCODE_SIZE)

local mcode_init_fn = mcode:get("mcode_init_test")
local mc_byte_fn    = mcode:get("mc_emit_byte_test")

local mov_rr_fn  = emit:get("test_mov_rr")
local add_rr_fn  = emit:get("test_add_rr")
local mov_ri_fn  = emit:get("test_mov_ri32")
local ret_fn     = emit:get("test_ret")

local passed, failed = 0, 0
local function check(n, exp, got)
    local e, g = tonumber(exp), tonumber(got)
    if e == g then
        passed = passed + 1
        io.write(string.format("  OK   %-42s = %s\n", n, g))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-42s expected %s got %s\n", n, e, g))
    end
end

-- =========================================================================
-- Helper: read bytes from mcode buffer above current mctop position
-- (code grows downward, so emitted bytes are ABOVE mctop after emission)
-- =========================================================================
local function mc_top_ptr()
    return ffi.cast("uint8_t *", J_u64[4])
end

local function byte_at(offset_from_top)
    return tonumber(mc_top_ptr()[offset_from_top])
end

-- =========================================================================
-- Test 1: MOV rax (0), rbx (3)   → REX.W 89 C3
-- =========================================================================
print("--- x64 instruction encoding ---")

-- Reset mcode buffer
ffi.fill(J_BUF, 64, 0)
mcode_init_fn(J_ptr, MCODE_PTR, MCODE_SIZE)

assert(mov_rr_fn(J_ptr, 0, 3) == 0, "mov_rr failed")
-- Code was emitted downward: 3 bytes above mctop
-- Encoding: REX 48, opcode 89, ModRM C3
check("MOV rax,rbx byte0 = 48h", 0x48, byte_at(0))
check("MOV rax,rbx byte1 = 89h", 0x89, byte_at(1))
check("MOV rax,rbx byte2 = D8h", 0xD8, byte_at(2))

-- =========================================================================
-- Test 2: ADD rcx (1), rdx (2)   → REX.W 01 D1
-- =========================================================================
assert(add_rr_fn(J_ptr, 1, 2) == 0, "add_rr failed")
check("ADD rcx,rdx byte0 = 48h", 0x48, byte_at(0))
check("ADD rcx,rdx byte1 = 01h", 0x01, byte_at(1))
check("ADD rcx,rdx byte2 = D1h", 0xD1, byte_at(2))

-- =========================================================================
-- Test 3: MOV rax, 42  → REX.W C7 C0 2A 00 00 00
-- =========================================================================
assert(mov_ri_fn(J_ptr, 0, 42) == 0, "mov_ri32 failed")
check("MOV rax,42 byte0 = 48h", 0x48, byte_at(0))
check("MOV rax,42 byte1 = C7h", 0xC7, byte_at(1))
check("MOV rax,42 byte2 = C0h", 0xC0, byte_at(2))
check("MOV rax,42 byte3 = 2Ah", 42,   byte_at(3))
check("MOV rax,42 byte4 = 00h", 0x00, byte_at(4))

-- =========================================================================
-- Test 4: RET → C3
-- =========================================================================
assert(ret_fn(J_ptr) == 0, "ret failed")
check("RET byte0 = C3h", 0xC3, byte_at(0))

-- =========================================================================
-- Test 5: Emit a complete function and execute it
-- Compile:  MOV rax, 0x1234  ;  RET
-- Call it and verify it returns 0x1234.
-- =========================================================================
print("\n--- execute generated code ---")

ffi.fill(J_BUF, 64, 0)
mcode_init_fn(J_ptr, MCODE_PTR, MCODE_SIZE)

-- Emit in reverse order (code grows down):
-- First emit RET (this will be at the highest address, executed last)
-- Then emit MOV rax, 0x1234 (emitted below RET)
-- The entry point is the LOWEST address after all emissions.

assert(ret_fn(J_ptr) == 0)
assert(mov_ri_fn(J_ptr, 0, 0x1234) == 0)  -- rax = 0x1234

-- Entry point = mctop (lowest address of emitted code)
local entry = ffi.cast("int64_t (*)(void)", mc_top_ptr())
local result = entry()
check("execute: MOV rax,0x1234; RET returns 0x1234", 0x1234, result)

-- =========================================================================
-- Test 6: Emit rax = rax + rdi (function: return x + y)
-- x in rdi (arg0 on Linux), y in rsi (arg1)  → result in rax
-- =========================================================================
ffi.fill(J_BUF, 64, 0)
mcode_init_fn(J_ptr, MCODE_PTR, MCODE_SIZE)

-- Emit: RET; ADD rax, rsi; MOV rax, rdi
assert(ret_fn(J_ptr) == 0)
assert(add_rr_fn(J_ptr, 0, 6) == 0)  -- ADD rax, rsi
assert(mov_rr_fn(J_ptr, 0, 7) == 0)  -- MOV rax, rdi

local add_fn = ffi.cast("int64_t (*)(int64_t, int64_t)", mc_top_ptr())
check("add(3,4)=7",   7, add_fn(3, 4))
check("add(10,20)=30",30, add_fn(10, 20))
check("add(-1,1)=0",  0, add_fn(-1, 1))

-- Cleanup
ffi.C.munmap(MCODE_PTR, MCODE_SIZE)
mcode:free()
emit:free()

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All x64 emit tests passed")
