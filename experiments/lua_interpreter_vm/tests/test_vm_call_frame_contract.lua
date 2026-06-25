-- Frame/cache and explicit call result-base contract tests.

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
local function setint(v, x) v.tag = const.Tag.INTEGER; v.aux = 0; v.bits = ffi.cast("uint64_t", x) end
local function setclosure(v, cl) v.tag = const.Tag.LCLOSURE; v.aux = 0; v.bits = ffi.cast("uint64_t", cl) end
local function bits_i64(x) return tonumber(ffi.cast("int64_t", x)) end
local function set_ABC(i, op, a, b, c, k)
    i.word = bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(k or 0, 15), bit.lshift(b or 0, 16), bit.lshift(c or 0, 24))
end
local function set_ABx(i, op, a, bx)
    i.word = bit.bor(op, bit.lshift(a or 0, 7), bit.lshift(bx or 0, 15))
end
local function set_AsBx(i, op, a, sbx)
    set_ABx(i, op, a, (sbx or 0) + 65535)
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
    block err(code: i32) return -200 - code end
    block oom() return -999 end
    end
end
]]:compile()

-- Child: return 7
local child_code = ffi.new("Instr[2]")
set_AsBx(child_code[0], const.Op.LOADI, 0, 7)
set_ABC(child_code[1], const.Op.RETURN1, 0, 0, 0, 0)
local child_proto = ffi.new("Proto[1]")
child_proto[0].code = child_code; child_proto[0].code_len = 2; child_proto[0].maxstack = 2
local child_cl = ffi.new("LClosure[1]")
child_cl[0].proto = child_proto

-- Parent: call child into R1, load parent constant into R2, add R1+R2 into R0, return R0.
local parent_code = ffi.new("Instr[6]")
set_ABx(parent_code[0], const.Op.LOADK, 1, 0)
set_ABC(parent_code[1], const.Op.CALL, 1, 1, 2, 0)
set_ABx(parent_code[2], const.Op.LOADK, 2, 1)
set_ABC(parent_code[3], const.Op.ADD, 0, 1, 2, 0)
set_ABC(parent_code[4], const.Op.MMBIN, 1, 2, const.TM.ADD, 0)
set_ABC(parent_code[5], const.Op.RETURN1, 0, 0, 0, 0)
local parent_consts = ffi.new("Value[2]")
setclosure(parent_consts[0], child_cl)
setint(parent_consts[1], 35)
local parent_proto = ffi.new("Proto[1]")
parent_proto[0].code = parent_code; parent_proto[0].code_len = 6
parent_proto[0].constants = parent_consts; parent_proto[0].constants_len = 2; parent_proto[0].maxstack = 4
local parent_cl = ffi.new("LClosure[1]")
parent_cl[0].proto = parent_proto

local stack = ffi.new("Value[64]")
for i = 0, 63 do setnil(stack[i]) end
setclosure(stack[0], parent_cl)
setint(stack[1], 999) -- must not receive child result directly
local frames = ffi.new("Frame[8]")
frames[0].closure = stack[0]
frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0; frames[0].wanted = 1
frames[0].result_base = 1; frames[0].call_top = 1; frames[0].yieldable = 1
frames[0].resume.kind = const.Resume.NORMAL; frames[0].resume.result_base = 1; frames[0].resume.call_top = 1; frames[0].resume.wanted = 1
local global = ffi.new("GlobalState[1]")
local L = ffi.new("LuaThread[1]")
L[0].status = const.Status.OK; L[0].stack = stack; L[0].stack_size = 64; L[0].top = 1
L[0].frames = frames; L[0].frame_count = 1; L[0].frame_cap = 8; L[0].global = global
L[0].yieldable = 1; L[0].nonyieldable = 0; L[0].last_error_code = 0; L[0].flags = 0
global[0].mainthread = L

local nres = runner(L)
runner:free()
if nres ~= 1 then
    print("debug nres", nres, "last_error", L[0].last_error_code, "err_aux", L[0].err_value.aux)
    print("debug stack tags", stack[1].tag, stack[2].tag, stack[3].tag)
    print("debug frame", L[0].frame_count, frames[0].pc, frames[0].base, frames[0].top, "resume", frames[0].resume.pc, frames[0].resume.base, frames[0].resume.a)
    print("debug stack vals", bits_i64(stack[1].bits), bits_i64(stack[2].bits), bits_i64(stack[3].bits))
end
assert(nres == 1, "nested call nres mismatch: " .. tostring(nres))
assert(stack[1].tag == const.Tag.INTEGER and bits_i64(stack[1].bits) == 42, "parent result/cache reload failed")
assert(stack[2].tag == const.Tag.INTEGER and bits_i64(stack[2].bits) == 7, "child result did not land at explicit result_base")
assert(stack[3].tag == const.Tag.INTEGER and bits_i64(stack[3].bits) == 35, "parent constants were not reloaded after child return")
print("PASS VM call/frame contract")
return true
