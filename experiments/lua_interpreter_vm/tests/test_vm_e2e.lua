-- VM end-to-end test (Lua 5.5): memory via ffi.load(libmoonlift) scratch, construct Proto, run vm_resume

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

local function pack_ABC(op, a, b, c, k)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(k or 0, 15), bit.lshift(b or 0, 16), bit.lshift(c or 0, 24))
end
local function pack_ABx(op, a, bx)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(bx or 0, 15))
end
local function pack_AsBx(op, a, sbx)
    return bit.bor(op, bit.lshift(a or 0, 7), bit.lshift((sbx or 0) + 65535, 15))
end
local function set_ABC(i, op, a, b, c, k) i.word = pack_ABC(op, a, b, c, k) end
local function set_ABx(i, op, a, bx) i.word = pack_ABx(op, a, bx) end
local function set_AsBx(i, op, a, sbx) i.word = pack_AsBx(op, a, sbx) end
local function op_of(i) return bit.band(i.word, 127) end

-- Load the moonlift shared library for scratch allocator
local libmoon
local ok, err = pcall(function()
    libmoon = ffi.load("libmoonlift")
end)
if not ok then
    local paths = {"./target/release/libmoonlift.so", "./target/debug/libmoonlift.so"}
    for _, p in ipairs(paths) do
        local ok2 = pcall(function() libmoon = ffi.load(p) end)
        if ok2 then break end
    end
end

if not libmoon then
    print("FAIL: Could not load libmoonlift.so. Build with 'cargo build --release' first.")
    os.exit(1)
end

ffi.cdef [[
    void* moonlift_scratch_raw(int slot, int elem_size, int count);
]]
local scratch_raw = libmoon.moonlift_scratch_raw

-- Struct layouts matching products.lua (Lua 5.5)
-- Instr: op(2)+a(2)+b(2)+c(2)+k(1)+pad(3)+bx(4)+sbx(4) = 20 bytes
-- LuaThread/Frame include explicit ABI/result/yield contract fields.
-- Proto: is_vararg → flag

ffi.cdef [[
    typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
    typedef struct { uint32_t word; } Instr;
    typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
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
        uint8_t numparams; uint8_t flag; uint16_t maxstack;
    } Proto;
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
        uint64_t tbc_head;
        int32_t yieldable; int32_t nonyieldable; int32_t last_error_code; uint32_t flags;
    } LuaThread;
    typedef struct {
        uint16_t kind;
        uint16_t a; uint16_t b; uint16_t c;
        uint64_t pc; uint64_t base; uint64_t result_base; uint64_t call_top;
        int32_t wanted;
        Value value;
        uint64_t errfunc_slot;
    } ResumeState;
    typedef struct {
        Value closure; uint64_t base; uint64_t top; uint64_t pc;
        int32_t wanted; int32_t tailcalls;
        uint64_t result_base; uint64_t call_top;
        ResumeState resume;
        uint8_t yieldable; uint8_t flags; uint16_t reserved;
    } Frame;
    typedef struct { void* allocator; Value registry; void* mainthread; uint32_t vm_abi_version; uint32_t native_abi_version; } GlobalState;
]]

local scratch = function(slot, elem_size, count)
    return ffi.cast("uint8_t*", scratch_raw(slot, elem_size, count))
end

print("=== Building Proto (Lua 5.5) === ")

-- Constants: [42.0] (TAG_NUM = 5 in Lua 5.5)
local consts_mem = scratch(1, 16, 1)
local consts = ffi.cast("Value(*)[1]", consts_mem)
consts[0][0].tag = const.Tag.NUM
consts[0][0].aux = 0
local num_bits = ffi.new("union { double d; uint64_t u; }")
num_bits.d = 42.0
consts[0][0].bits = num_bits.u

-- Instructions: LOADK R0 K0, RETURN R0 2  (Instr = 20 bytes in Lua 5.5)
local code_mem = scratch(2, 20, 2)
local code = ffi.cast("Instr(*)[2]", code_mem)
set_ABx(code[0][0], const.Op.LOADK, 0, 0)
set_ABC(code[0][1], const.Op.RETURN, 0, 2, 0, 0)

-- Proto
local proto_mem = scratch(3, 1, 256)
local proto = ffi.cast("Proto*", proto_mem)
proto.code = ffi.cast("void*", code)
proto.code_len = 2
proto.constants = ffi.cast("void*", consts)
proto.constants_len = 1
proto.maxstack = 1; proto.numparams = 0; proto.flag = 0
proto.linedefined = -1; proto.lastlinedefined = -1

-- LClosure
local closure_mem = scratch(4, 1, 64)
local closure = ffi.cast("LClosure*", closure_mem)
closure.proto = proto; closure.env = nil; closure.nupvals = 0

-- Stack: 64 Values
local STACK_N = 64
local stack_mem = scratch(5, 16, STACK_N)
local stack = ffi.cast("Value*", stack_mem)
for i = 0, STACK_N - 1 do
    stack[i].tag = const.Tag.NIL; stack[i].aux = 0; stack[i].bits = 0
end
stack[0].tag = const.Tag.LCLOSURE; stack[0].aux = 0
stack[0].bits = ffi.cast("uint64_t", closure)

-- Frames: 8
local frames_mem = scratch(6, 1, 512)
local frames = ffi.cast("Frame*", frames_mem)
frames[0].closure.tag = const.Tag.LCLOSURE
frames[0].closure.aux = 0
frames[0].closure.bits = ffi.cast("uint64_t", closure)
frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0
frames[0].wanted = 1; frames[0].resume.kind = const.Resume.NORMAL
frames[0].result_base = frames[0].base; frames[0].call_top = frames[0].top
frames[0].yieldable = 1; frames[0].flags = 0; frames[0].reserved = 0

-- Global state
local gstate_mem = scratch(7, 1, 64)
local gstate = ffi.cast("GlobalState*", gstate_mem)

-- LuaThread
local thread_mem = scratch(8, 1, 256)
local thread = ffi.cast("LuaThread*", thread_mem)
thread.stack = stack; thread.stack_size = STACK_N; thread.top = 1
thread.frames = frames; thread.frame_count = 1; thread.frame_cap = 8
thread.global = gstate; thread.status = const.Status.OK
thread.tbc_head = 0
thread.yieldable = 1; thread.nonyieldable = 0; thread.last_error_code = 0; thread.flags = 0

print("Proto built. Instructions:")
print("  [0] LOADK  R0 K0")
print("  [1] RETURN R0 2")
local show_k = ffi.new("union { double d; uint64_t u; }")
show_k.u = consts[0][0].bits
print("  K[0] =", show_k.d)
print("  Thread frames:", thread.frame_count)
print()

-- Compile wrapper that calls vm_resume
local vr = vm.vm_loop.vm_resume
print("Compiling vm_resume wrapper...")
local runner = moon.func {
    vm_resume = vr,
    sys_realloc = vm.regions_allocator.sys_realloc,
} [[
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
    os.exit(1)
end

print("Calling vm_resume...")
local result = compiled(thread, 0)
compiled:free()

print()
if result >= 0 then
    print("SUCCESS: vm_resume returned", result)
    local expect_tag = const.Tag.NUM
    print("Stack[1] tag:", stack[1].tag, "(expect", expect_tag, "= TAG_NUM)")
    if stack[1].tag == expect_tag then
        local out_bits = ffi.new("union { double d; uint64_t u; }")
        out_bits.u = stack[1].bits
        local val = out_bits.d
        print("Stack[1] value:", val, "(expect 42)")
        if math.abs(val - 42.0) < 0.001 then
            print("\n*** VM EXECUTED return 42 SUCCESSFULLY ***")
        end
    end
else
    print("FAIL: vm_resume returned error code", result)
    print("Thread status:", thread.status)
end
