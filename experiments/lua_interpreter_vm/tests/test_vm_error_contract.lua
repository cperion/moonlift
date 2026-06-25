-- Explicit VM error-state contract tests.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

ffi.cdef [[
typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;
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

local function setnil(v) v.tag = const.Tag.NIL; v.aux = 0; v.bits = 0 end
local function set_ABC(i, op, a, b, c, k)
    i.word = bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(k or 0, 15), bit.lshift(b or 0, 16), bit.lshift(c or 0, 24))
end

local runner = lalin.func {
    vm_resume = vm.vm_loop.vm_resume,
    sys_realloc = vm.regions_allocator.sys_realloc,
} [[
run(L: ptr(LuaThread)): i32
    return region: i32
    entry start()
        emit @{vm_resume}(L, 0;
            ok = ok,
            yielded = yielded,
            runtime_error = err,
            oom = oom)
    end
    block ok(nres: i32) return nres end
    block yielded(nres: i32) return -100 - nres end
    block err(code: i32) return 0 - code end
    block oom() return -999 end
    end
end
]]:compile()

local code = ffi.new("Instr[1]")
set_ABC(code[0], 85, 0, 0, 0, 0)
local proto = ffi.new("Proto[1]")
proto[0].code = code; proto[0].code_len = 1; proto[0].maxstack = 2
local closure = ffi.new("LClosure[1]")
closure[0].proto = proto
local stack = ffi.new("Value[16]")
for i = 0, 15 do setnil(stack[i]) end
stack[0].tag = const.Tag.LCLOSURE; stack[0].bits = ffi.cast("uint64_t", closure)
local frames = ffi.new("Frame[2]")
frames[0].closure = stack[0]
frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0; frames[0].wanted = 1
frames[0].result_base = 1; frames[0].call_top = 1; frames[0].yieldable = 1
frames[0].resume.kind = const.Resume.NORMAL; frames[0].resume.result_base = 1; frames[0].resume.call_top = 1; frames[0].resume.wanted = frames[0].wanted
local global = ffi.new("GlobalState[1]")
local L = ffi.new("LuaThread[1]")
L[0].status = const.Status.OK; L[0].stack = stack; L[0].stack_size = 16; L[0].top = 1
L[0].frames = frames; L[0].frame_count = 1; L[0].frame_cap = 2; L[0].global = global
L[0].yieldable = 1; L[0].nonyieldable = 0; L[0].last_error_code = 0; L[0].flags = 0
global[0].mainthread = L

local r = runner(L)
runner:free()
assert(r == -const.Err.BAD_OPCODE, "runtime error code mismatch: " .. tostring(r))
assert(L[0].status == const.Status.RUNTIME_ERROR, "thread status not runtime error")
assert(L[0].last_error_code == const.Err.BAD_OPCODE, "last_error_code mismatch")
assert(L[0].err_value.aux == const.Err.BAD_OPCODE, "err_value.aux mismatch")
print("PASS VM error contract")
return true
