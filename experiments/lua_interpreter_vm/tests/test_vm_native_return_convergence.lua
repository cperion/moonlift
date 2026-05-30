-- Native-call success converges with Lua-call return adjustment in the VM loop.
-- A native function writes its result at NativeCallContext.result_base and
-- returns NativeResult.OK; the interpreter must resume the Lua caller at pc+1
-- and execute the following RETURN1 without treating native success as a VM
-- runtime error.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const
local bytecode = vm.bytecode

local libmoon
for _, p in ipairs({ "libmoonlift", "./target/release/libmoonlift.so", "./target/debug/libmoonlift.so" }) do
    local ok, lib = pcall(ffi.load, p)
    if ok then libmoon = lib; break end
end
if not libmoon then error("could not load libmoonlift; build with cargo build --release") end

ffi.cdef [[
void* moonlift_scratch_raw(int slot, int elem_size, int count);
typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct Instr { uint32_t word; } Instr;
typedef struct {
    GCHeader gc;
    Instr* code; uint64_t code_len;
    Value* constants; uint64_t constants_len;
    void** children; uint64_t children_len;
    int32_t* lineinfo; uint64_t lineinfo_len;
    void* locvars; uint64_t locvars_len;
    void* upvals; uint64_t upvals_len;
    void* source;
    int32_t linedefined; int32_t lastlinedefined;
    uint8_t numparams; uint8_t flag; uint16_t maxstack;
} Proto;
typedef struct { GCHeader gc; void* env; Proto* proto; void** upvals; uint8_t nupvals; } LClosure;
typedef struct { uint32_t abi_version; uint32_t flags; uint8_t* addr; void* name; } NativeFunc;
typedef struct {
    uint16_t kind;
    uint16_t a; uint16_t b; uint16_t c;
    uint64_t pc; uint64_t base; uint64_t result_base; uint64_t call_top;
    int32_t wanted;
    Value value;
    uint64_t errfunc_slot;
} ResumeState;
typedef struct {
    uint64_t func_slot; int32_t nargs; int32_t wanted;
    uint64_t result_base; uint64_t stack_top;
    uint8_t yieldable; uint8_t reserved;
    ResumeState resume;
} NativeCallContext;
typedef struct { uint8_t status; int32_t nresults; Value err; uint64_t stack_needed; uint8_t* continuation; } NativeCallResult;
typedef struct { GCHeader gc; void* env; NativeFunc* fn; Value* upvals; uint8_t nupvals; } CClosure;
typedef struct {
    Value closure; uint64_t base; uint64_t top; uint64_t pc;
    int32_t wanted; int32_t tailcalls;
    uint64_t result_base; uint64_t call_top;
    ResumeState resume;
    uint8_t yieldable; uint8_t flags; uint16_t reserved;
} Frame;
typedef struct {
    GCHeader gc; uint8_t status;
    Value* stack; uint64_t stack_size; uint64_t top;
    Frame* frames; uint64_t frame_count; uint64_t frame_cap;
    void* open_upvals; void* protected_top;
    void* global; Value err_value;
    uint8_t hookmask; uint8_t allowhook;
    int32_t hookcount; int32_t basehookcount; Value hook;
    uint64_t tbc_head;
    int32_t yieldable; int32_t nonyieldable; int32_t last_error_code; uint32_t flags;
} LuaThread;
typedef struct { void* allocator; Value registry; void* mainthread; uint32_t vm_abi_version; uint32_t native_abi_version; } GlobalState;
]]

local scratch_raw = libmoon.moonlift_scratch_raw
local NEXT_SLOT = 500
local function scratch(elem_size, count, ctype)
    local slot = NEXT_SLOT
    NEXT_SLOT = NEXT_SLOT + 1
    return ffi.cast(ctype, scratch_raw(slot, elem_size, count))
end

local function setnil(v) v.tag = const.Tag.NIL; v.aux = 0; v.bits = 0 end
local function setint(v, x) v.tag = const.Tag.INTEGER; v.aux = 0; v.bits = ffi.cast("uint64_t", x) end
local function setlclosure(v, cl) v.tag = const.Tag.LCLOSURE; v.aux = 0; v.bits = ffi.cast("uint64_t", cl) end
local function setcclosure(v, cl) v.tag = const.Tag.CCLOSURE; v.aux = 0; v.bits = ffi.cast("uint64_t", cl) end
local function set_ABC(i, op, a, b, c, k) i.word = bytecode.encode_ABC(op, a, b, c, k) end

local native_cb = ffi.cast("uint64_t (*)(LuaThread*, CClosure*, NativeCallContext*, NativeCallResult*)",
    function(L, cl, ctx, result)
        local dst = tonumber(ctx.result_base)
        L.stack[dst].tag = const.Tag.INTEGER
        L.stack[dst].aux = 0
        L.stack[dst].bits = ffi.cast("uint64_t", 42)
        result.status = const.NativeResult.OK
        result.nresults = 1
        return ffi.cast("uint64_t", 0)
    end)

local runner = moon.func {
    vm_resume = vm.vm_loop.vm_resume,
    sys_realloc = vm.regions_allocator.sys_realloc,
} [[
run(L: ptr(LuaThread)) -> i32
    return region -> i32
    entry start()
        emit @{vm_resume}(L, 0;
            ok = done,
            yielded = yielded,
            runtime_error = err,
            oom = oom)
    end
    block done(nres: i32) return nres end
    block yielded(nres: i32) return -100 - nres end
    block err(code: i32) return -200 - code end
    block oom() return -999 end
    end
end
]]:compile()

local code = scratch(ffi.sizeof("Instr"), 2, "Instr*")
set_ABC(code[0], const.Op.CALL, 0, 1, 2, 0)
set_ABC(code[1], const.Op.RETURN1, 0, 0, 0, 0)

local proto = scratch(ffi.sizeof("Proto"), 1, "Proto*")
proto.code = code; proto.code_len = 2
proto.constants = nil; proto.constants_len = 0
proto.children = nil; proto.children_len = 0
proto.lineinfo = nil; proto.lineinfo_len = 0
proto.locvars = nil; proto.locvars_len = 0; proto.upvals = nil; proto.upvals_len = 0
proto.source = nil; proto.linedefined = -1; proto.lastlinedefined = -1
proto.numparams = 0; proto.flag = 0; proto.maxstack = 4

local lua_cl = scratch(ffi.sizeof("LClosure"), 1, "LClosure*")
lua_cl.proto = proto; lua_cl.env = nil; lua_cl.upvals = nil; lua_cl.nupvals = 0

local native_fn = scratch(ffi.sizeof("NativeFunc"), 1, "NativeFunc*")
native_fn.abi_version = const.Abi.NATIVE_VERSION
native_fn.flags = 0
native_fn.addr = ffi.cast("uint8_t*", native_cb)
native_fn.name = nil

local native_cl = scratch(ffi.sizeof("CClosure"), 1, "CClosure*")
native_cl.fn = native_fn; native_cl.env = nil; native_cl.upvals = nil; native_cl.nupvals = 0

local stack = scratch(ffi.sizeof("Value"), 32, "Value*")
for i = 0, 31 do setnil(stack[i]) end
setlclosure(stack[0], lua_cl)
setcclosure(stack[1], native_cl)

local frames = scratch(ffi.sizeof("Frame"), 4, "Frame*")
frames[0].closure = stack[0]
frames[0].base = 1; frames[0].top = 2; frames[0].pc = 0
frames[0].wanted = 1; frames[0].tailcalls = 0
frames[0].result_base = 1; frames[0].call_top = 2
frames[0].resume.kind = const.Resume.NORMAL
frames[0].resume.result_base = 1; frames[0].resume.call_top = 2; frames[0].resume.wanted = 1
setnil(frames[0].resume.value)
frames[0].yieldable = 1; frames[0].flags = 0; frames[0].reserved = 0

local global = scratch(ffi.sizeof("GlobalState"), 1, "GlobalState*")
global.allocator = nil; setnil(global.registry); global.vm_abi_version = const.Abi.VM_VERSION; global.native_abi_version = const.Abi.NATIVE_VERSION
local L = scratch(ffi.sizeof("LuaThread"), 1, "LuaThread*")
L.status = const.Status.OK; L.stack = stack; L.stack_size = 32; L.top = 2
L.frames = frames; L.frame_count = 1; L.frame_cap = 4; L.open_upvals = nil; L.protected_top = nil; L.global = global
setnil(L.err_value); L.hookmask = 0; L.allowhook = 0; L.hookcount = 0; L.basehookcount = 0; setnil(L.hook); L.tbc_head = 0
L.yieldable = 1; L.nonyieldable = 0; L.last_error_code = 0; L.flags = 0
global.mainthread = L

local nres = runner(L)
runner:free()
native_cb:free()

assert(nres == 1, "native call did not return one result: " .. tostring(nres))
assert(stack[1].tag == const.Tag.INTEGER, "native result tag mismatch: " .. tostring(stack[1].tag))
assert(tonumber(ffi.cast("int64_t", stack[1].bits)) == 42, "native result value mismatch")
assert(frames[0].pc == 1, "native return did not resume caller at instruction after CALL")

print("PASS VM native return convergence")
return true
