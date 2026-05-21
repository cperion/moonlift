-- VM end-to-end test: memory via ffi.load(libmoonlift) scratch, construct Proto, run vm_resume
-- Uses the Rust backend's scratch allocator

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

-- Load the moonlift shared library for scratch allocator
local libmoon
local ok, err = pcall(function()
    libmoon = ffi.load("libmoonlift")
end)
if not ok then
    -- Try alternative paths
    local paths = {"./target/release/libmoonlift.so", "./target/debug/libmoonlift.so"}
    for _, p in ipairs(paths) do
        local ok2 = pcall(function() libmoon = ffi.load(p) end)
        if ok2 then break end
    end
end

if not libmoon then
    print("FAIL: Could not load libmoonlift.so. Build with 'cargo build --release' first.")
    return nil
end

ffi.cdef [[
    void* moonlift_scratch_raw(int slot, int elem_size, int count);
]]

-- Get scratch function
local scratch_raw = libmoon.moonlift_scratch_raw

-- Build Proto struct layouts (must match products.lua declarations)
-- GCHeader: next:ptr(8) + tt:u8(1) + marked:u8(1) = 16 bytes (with padding)
-- Proto: GCHeader(16) + code:ptr(8) + code_len:index(8) +
--        constants:ptr(8) + constants_len:index(8) +
--        children:ptr(8) + children_len:index(8) +
--        lineinfo:ptr(8) + lineinfo_len:index(8) +
--        locvars:ptr(8) + locvars_len:index(8) +
--        upvals:ptr(8) + upvals_len:index(8) +
--        source:ptr(8) +
--        linedefined:i32(4) + lastlinedefined:i32(4) +
--        numparams:u8(1) + is_vararg:u8(1) + maxstack:u16(2) = 134 bytes

ffi.cdef [[
    typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
    typedef struct {
        GCHeader gc;
        void* code; uint64_t code_len;
        void* constants; uint64_t constants_len;
        void** children; uint64_t children_len;
        int32_t* lineinfo; uint64_t lineinfo_len;
        void* locvars; uint64_t locvars_len;
        void* upvals; uint64_t upvals_len;
        void* source;
        int32_t linedefined; int32_t lastlinedefined;
        uint8_t numparams; uint8_t is_vararg; uint16_t maxstack;
    } Proto;
    typedef struct {
        uint16_t op; uint16_t a; uint16_t b; uint16_t c; uint32_t bx; int32_t sbx;
    } Instr;
    typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
    typedef struct {
        void* gc_next; uint8_t tt; uint8_t marked;
        void* env; Proto* proto;
        void** upvals; uint8_t nupvals;
    } LClosure;
    typedef struct {
        GCHeader gc; uint8_t status;
        Value* stack; uint64_t stack_size; uint64_t top;
        void* frames; uint64_t frame_count; uint64_t frame_cap;
        void* open_upvals; void* protected_top;
        void* global; Value err_value;
        uint8_t hookmask; uint8_t allowhook;
        int32_t hookcount; int32_t basehookcount; Value hook;
    } LuaThread;
    typedef struct {
        Value closure; uint64_t base; uint64_t top; uint64_t pc;
        int32_t wanted; int32_t tailcalls;
        uint16_t resume_mode;
        uint16_t resume_a; uint16_t resume_b; uint16_t resume_c;
        uint64_t resume_pc; uint64_t resume_base; Value resume_value;
    } Frame;
    typedef struct { void* allocator; Value registry; void* mainthread; } GlobalState;
]]

-- Allocate memory
local scratch = function(slot, elem_size, count)
    return ffi.cast("uint8_t*", scratch_raw(slot, elem_size, count))
end

print("=== Building Proto === ")

-- Constants: [42.0]
local consts_mem = scratch(1, 16, 1)
local consts = ffi.cast("Value(*)[1]", consts_mem)
consts[0][0].tag = const.Tag.NUM
consts[0][0].aux = 0
consts[0][0].bits = ffi.cast("uint64_t", 42.0)

-- Instructions: LOADK R0 K0, RETURN R0 2
local code_mem = scratch(2, 16, 2)
local code = ffi.cast("Instr(*)[2]", code_mem)
code[0][0].op = const.Op.LOADK; code[0][0].a = 0; code[0][0].bx = 0
code[0][1].op = const.Op.RETURN; code[0][1].a = 0; code[0][1].b = 2

-- Proto (allocate via big scratch)
local proto_mem = scratch(0, 1, 256)
local proto = ffi.cast("Proto*", proto_mem)
proto.code = ffi.cast("void*", code)
proto.code_len = 2
proto.constants = ffi.cast("void*", consts)
proto.constants_len = 1
proto.maxstack = 1; proto.numparams = 0
proto.linedefined = -1; proto.lastlinedefined = -1

-- LClosure
local closure_mem = scratch(0, 1, 64)
local closure = ffi.cast("LClosure*", closure_mem)
closure.proto = proto; closure.env = nil; closure.nupvals = 0

-- Stack: 64 Values
local STACK_N = 64
local stack_mem = scratch(0, 16, STACK_N)
local stack = ffi.cast("Value*", stack_mem)
for i = 0, STACK_N - 1 do
    stack[i].tag = const.Tag.NIL; stack[i].aux = 0; stack[i].bits = 0
end
stack[0].tag = const.Tag.LCLOSURE; stack[0].aux = 0
stack[0].bits = ffi.cast("uint64_t", closure)

-- Frames: 8
local frames_mem = scratch(0, 1, 512)
local frames = ffi.cast("Frame*", frames_mem)
frames[0].closure.tag = const.Tag.LCLOSURE
frames[0].closure.aux = 0
frames[0].closure.bits = ffi.cast("uint64_t", closure)
frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0
frames[0].wanted = 1; frames[0].resume_mode = const.Resume.NORMAL

-- Global state (minimal)
local gstate_mem = scratch(0, 1, 64)
local gstate = ffi.cast("GlobalState*", gstate_mem)

-- LuaThread
local thread_mem = scratch(0, 1, 256)
local thread = ffi.cast("LuaThread*", thread_mem)
thread.stack = stack; thread.stack_size = STACK_N; thread.top = 1
thread.frames = frames; thread.frame_count = 1; thread.frame_cap = 8
thread.global = gstate; thread.status = const.Status.OK

print("Proto built. Instructions:")
print("  [0] LOADK  R0 K0")
print("  [1] RETURN R0 2")
print("  K[0] =", ffi.cast("double", consts[0][0].bits))
print("  Thread frames:", thread.frame_count)
print()

-- Compile wrapper that calls vm_resume
local vr = vm.vm_loop.vm_resume
print("Compiling vm_resume wrapper...")
local runner = moon.func { vm_resume = vr } [[
run_vm(L: ptr(LuaThread), nargs: i32) -> i32
    return region -> i32
    entry start()
        emit @{vm_resume}(L, nargs; ok = done,
            yielded = did_yield, runtime_error = err, oom = oom_exit)
    end
    block done(nres: i32) return nres end
    block did_yield(nres: i32) return -100 - nres end
    block err(code: i32) return -200 - code end
    block oom_exit() return -999 end
    end
end
]]

local ok, compiled = pcall(function() return runner:compile() end)
if not ok then
    print("FAIL: wrapper compilation error:", compiled)
    return
end

print("Calling vm_resume...")
local result = compiled:get("run_vm")(thread, 0)
compiled:free()

print()
if result >= 0 then
    print("SUCCESS: vm_resume returned", result)
    print("Stack[1] tag:", stack[1].tag, "(expect", const.Tag.NUM, "= 4)")
    if stack[1].tag == const.Tag.NUM then
        local val = ffi.cast("double", stack[1].bits)
        print("Stack[1] value:", val, "(expect 42)")
        if math.abs(val - 42.0) < 0.001 then
            print("\n*** VM EXECUTED return 42 SUCCESSFULLY ***")
        end
    end
else
    print("FAIL: vm_resume returned error code", result)
    print("Thread status:", thread.status)
    print("Thread err_value tag:", thread.err_value.tag)
end
