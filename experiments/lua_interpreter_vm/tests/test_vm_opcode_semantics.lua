-- Focused Lua 5.5 opcode semantic checks for Moonlift VM.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

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
typedef struct { uint16_t op; uint16_t a; uint16_t b; uint16_t c; uint8_t k; uint32_t bx; int32_t sbx; } Instr;
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
typedef struct { GCHeader gc; void* env; Proto* proto; void** upvals; uint8_t nupvals; } LClosure;
typedef struct {
    Value closure; uint64_t base; uint64_t top; uint64_t pc;
    int32_t wanted; int32_t tailcalls;
    uint16_t resume_mode;
    uint16_t resume_a; uint16_t resume_b; uint16_t resume_c;
    uint64_t resume_pc; uint64_t resume_base; Value resume_value;
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
} LuaThread;
typedef struct { void* allocator; Value registry; void* mainthread; } GlobalState;
]]

local scratch_raw = libmoon.moonlift_scratch_raw
local NEXT_SLOT = 200
local function scratch(elem_size, count, ctype)
    local slot = NEXT_SLOT
    NEXT_SLOT = NEXT_SLOT + 1
    return ffi.cast(ctype, scratch_raw(slot, elem_size, count))
end

local function dblbits(x)
    local u = ffi.new("union { double d; uint64_t u; }")
    u.d = x
    return u.u
end
local function bitsdbl(x)
    local u = ffi.new("union { double d; uint64_t u; }")
    u.u = x
    return tonumber(u.d)
end

local function setnil(v) v.tag = const.Tag.NIL; v.aux = 0; v.bits = 0 end
local function setint(v, x) v.tag = const.Tag.INTEGER; v.aux = 0; v.bits = ffi.cast("uint64_t", x) end
local function setnum(v, x) v.tag = const.Tag.NUM; v.aux = 0; v.bits = dblbits(x) end

local runner = moon.func { vm_resume = vm.vm_loop.vm_resume } [[
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

local function make_case(ncode, nconst)
    local code = scratch(ffi.sizeof("Instr"), ncode, "Instr*")
    for i = 0, ncode - 1 do
        code[i].op = const.Op.RETURN; code[i].a = 0; code[i].b = 1; code[i].c = 0; code[i].k = 0; code[i].bx = 0; code[i].sbx = 0
    end
    local consts = scratch(16, math.max(nconst, 1), "Value*")
    for i = 0, math.max(nconst, 1) - 1 do setnil(consts[i]) end
    local proto = scratch(1, 256, "Proto*")
    proto.code = ffi.cast("void*", code); proto.code_len = ncode
    proto.constants = ffi.cast("void*", consts); proto.constants_len = nconst
    proto.children = nil; proto.children_len = 0; proto.lineinfo = nil; proto.lineinfo_len = 0
    proto.locvars = nil; proto.locvars_len = 0; proto.upvals = nil; proto.upvals_len = 0
    proto.source = nil; proto.linedefined = -1; proto.lastlinedefined = -1
    proto.numparams = 0; proto.flag = 0; proto.maxstack = 8
    local closure = scratch(1, 64, "LClosure*")
    closure.env = nil; closure.proto = proto; closure.upvals = nil; closure.nupvals = 0
    local stack = scratch(16, 64, "Value*")
    for i = 0, 63 do setnil(stack[i]) end
    stack[0].tag = const.Tag.LCLOSURE; stack[0].aux = 0; stack[0].bits = ffi.cast("uint64_t", closure)
    local frames = scratch(1, 512, "Frame*")
    frames[0].closure = stack[0]
    frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0; frames[0].wanted = 1; frames[0].tailcalls = 0
    frames[0].resume_mode = const.Resume.NORMAL
    frames[0].resume_a = 0; frames[0].resume_b = 0; frames[0].resume_c = 0; frames[0].resume_pc = 0; frames[0].resume_base = 0
    setnil(frames[0].resume_value)
    local g = scratch(1, 128, "GlobalState*"); g.allocator = nil; setnil(g.registry)
    local L = scratch(1, 256, "LuaThread*")
    L.status = const.Status.OK; L.stack = stack; L.stack_size = 64; L.top = 1
    L.frames = frames; L.frame_count = 1; L.frame_cap = 8; L.open_upvals = nil; L.protected_top = nil; L.global = g
    setnil(L.err_value); L.hookmask = 0; L.allowhook = 0; L.hookcount = 0; L.basehookcount = 0; setnil(L.hook); L.tbc_head = 0
    g.mainthread = L
    return { code = code, consts = consts, stack = stack, L = L }
end

local pass, fail = 0, 0
local function check(name, ok, msg)
    if ok then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print("  FAIL " .. name .. (msg and (": " .. msg) or "")) end
end

print("=== VM opcode semantic checks ===\n")

-- LOADNIL A B clears R[A]..R[A+B].
do
    local c = make_case(2, 0)
    setint(c.stack[1], 11); setint(c.stack[2], 22); setint(c.stack[3], 33)
    c.code[0].op = const.Op.LOADNIL; c.code[0].a = 0; c.code[0].b = 2
    c.code[1].op = const.Op.RETURN; c.code[1].a = 0; c.code[1].b = 2
    local n = runner(c.L)
    check("LOADNIL clears A through A+B", n == 1 and c.stack[1].tag == const.Tag.NIL and c.stack[2].tag == const.Tag.NIL and c.stack[3].tag == const.Tag.NIL)
end

-- LOADKX uses the following EXTRAARG and skips it.
do
    local c = make_case(3, 2)
    setint(c.consts[0], 111); setint(c.consts[1], 222)
    c.code[0].op = const.Op.LOADKX; c.code[0].a = 0
    c.code[1].op = const.Op.EXTRAARG; c.code[1].bx = 1
    c.code[2].op = const.Op.RETURN; c.code[2].a = 0; c.code[2].b = 2
    local n = runner(c.L)
    check("LOADKX reads EXTRAARG and advances pc by 2", n == 1 and c.stack[1].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[1].bits)) == 222)
end

-- ADDI uses immediate C, not register C.
do
    local c = make_case(3, 0)
    setint(c.stack[1], 40); setint(c.stack[2], 9000)
    c.code[0].op = const.Op.ADDI; c.code[0].a = 0; c.code[0].b = 0; c.code[0].c = 2
    c.code[1].op = const.Op.MMBINI; c.code[1].a = 0; c.code[1].b = 2; c.code[1].c = const.TM.ADD
    c.code[2].op = const.Op.RETURN; c.code[2].a = 0; c.code[2].b = 2
    local n = runner(c.L)
    check("ADDI uses immediate operand", n == 1 and c.stack[1].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[1].bits)) == 42)
end

-- ADDK uses constant C, not register C.
do
    local c = make_case(3, 1)
    setint(c.stack[1], 40); setint(c.stack[2], 9000); setint(c.consts[0], 2)
    c.code[0].op = const.Op.ADDK; c.code[0].a = 0; c.code[0].b = 0; c.code[0].c = 0
    c.code[1].op = const.Op.MMBINK; c.code[1].a = 0; c.code[1].b = 0; c.code[1].c = const.TM.ADD
    c.code[2].op = const.Op.RETURN; c.code[2].a = 0; c.code[2].b = 2
    local n = runner(c.L)
    check("ADDK uses constant operand", n == 1 and c.stack[1].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[1].bits)) == 42)
end

-- ADD on TAG_NUM reinterprets f64 payload bits; it must not numerically
-- convert the u64 payload to f64.
do
    local c = make_case(3, 0)
    setnum(c.stack[1], 1.5); setnum(c.stack[2], 2.25)
    c.code[0].op = const.Op.ADD; c.code[0].a = 2; c.code[0].b = 0; c.code[0].c = 1
    c.code[1].op = const.Op.MMBIN; c.code[1].a = 0; c.code[1].b = const.TM.ADD; c.code[1].c = 0
    c.code[2].op = const.Op.RETURN; c.code[2].a = 2; c.code[2].b = 2
    local n = runner(c.L)
    local got = bitsdbl(c.stack[3].bits)
    check("ADD preserves f64 payload semantics", n == 1 and c.stack[3].tag == const.Tag.NUM and math.abs(got - 3.75) < 1e-12, "got " .. tostring(got))
end

-- RETURN1 carries A through the return path.
do
    local c = make_case(1, 0)
    setint(c.stack[1], 111); setint(c.stack[2], 222)
    c.code[0].op = const.Op.RETURN1; c.code[0].a = 1
    local n = runner(c.L)
    check("RETURN1 returns R[A]", n == 1 and c.stack[2].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[2].bits)) == 222)
end

runner:free()
print(string.format("\n=== %d/%d passed ===\n", pass, pass + fail))
if fail > 0 then os.exit(1) end
