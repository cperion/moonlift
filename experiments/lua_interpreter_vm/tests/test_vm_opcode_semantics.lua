-- Focused Lua 5.5 opcode semantic checks for Lalin VM.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local lalin = require("lalin")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

local bytecode = vm.bytecode
local function pack_ABC(op, a, b, c, k) return bytecode.encode_ABC(op, a, b, c, k) end
local function pack_ABx(op, a, bx) return bytecode.encode_ABx(op, a, bx) end
local function pack_AsBx(op, a, sbx) return bytecode.encode_AsBx(op, a, sbx) end
local function pack_Ax(op, ax) return bytecode.encode_Ax(op, ax) end
local function set_ABC(i, op, a, b, c, k) i.word = pack_ABC(op, a, b, c, k) end
local function set_ABx(i, op, a, bx) i.word = pack_ABx(op, a, bx) end
local function set_AsBx(i, op, a, sbx) i.word = pack_AsBx(op, a, sbx) end
local function set_Ax(i, op, ax) i.word = pack_Ax(op, ax) end
local function set_AsC(i, op, a, b, sc, k) i.word = pack_ABC(op, a, b, sc + bytecode.OFFSET_SC, k) end
local function op_of(i) return bit.band(i.word, 127) end

local liblalin
for _, p in ipairs({ "liblalin", "./target/release/liblalin.so", "./target/debug/liblalin.so" }) do
    local ok, lib = pcall(ffi.load, p)
    if ok then liblalin = lib; break end
end
if not liblalin then error("could not load liblalin; build with cargo build --release") end

ffi.cdef [[
void* lalin_scratch_raw(int slot, int elem_size, int count);
typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct Instr { uint32_t word; } Instr;
typedef struct String { GCHeader gc; uint8_t reserved; uint32_t hash; uint64_t len; uint8_t* bytes; } String;
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

local scratch_raw = liblalin.lalin_scratch_raw
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
local function setbool(v, b) v.tag = b and const.Tag.TRUE or const.Tag.FALSE; v.aux = 0; v.bits = 0 end
local function setstr(v, text)
    local bytes = scratch(1, #text, "uint8_t*")
    for i = 1, #text do bytes[i - 1] = string.byte(text, i) end
    local s = scratch(ffi.sizeof("String"), 1, "String*")
    s.gc.next = nil; s.gc.tt = const.Tag.STR; s.gc.marked = 0
    s.reserved = 0; s.hash = 0; s.len = #text; s.bytes = bytes
    v.tag = const.Tag.STR; v.aux = 0; v.bits = ffi.cast("uint64_t", s)
end

local runner = lalin.func {
    vm_resume = vm.vm_loop.vm_resume,
    sys_realloc = vm.regions_allocator.sys_realloc,
} [[
run(L: ptr(LuaThread)): i32
    return region: i32
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
        set_ABC(code[i], const.Op.RETURN, 0, 1, 0, 0)
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
    frames[0].result_base = frames[0].base; frames[0].call_top = frames[0].top
    frames[0].resume.kind = const.Resume.NORMAL
    frames[0].resume.a = 0; frames[0].resume.b = 0; frames[0].resume.c = 0; frames[0].resume.pc = 0; frames[0].resume.base = 0
    frames[0].resume.result_base = frames[0].result_base; frames[0].resume.call_top = frames[0].call_top; frames[0].resume.wanted = frames[0].wanted
    setnil(frames[0].resume.value); frames[0].resume.errfunc_slot = 0
    frames[0].yieldable = 1; frames[0].flags = 0; frames[0].reserved = 0
    local g = scratch(1, 128, "GlobalState*"); g.allocator = nil; setnil(g.registry)
    local L = scratch(1, 256, "LuaThread*")
    L.status = const.Status.OK; L.stack = stack; L.stack_size = 64; L.top = 1
    L.frames = frames; L.frame_count = 1; L.frame_cap = 8; L.open_upvals = nil; L.protected_top = nil; L.global = g
    setnil(L.err_value); L.hookmask = 0; L.allowhook = 0; L.hookcount = 0; L.basehookcount = 0; setnil(L.hook); L.tbc_head = 0
    L.yieldable = 1; L.nonyieldable = 0; L.last_error_code = 0; L.flags = 0
    g.mainthread = L
    return { code = code, consts = consts, stack = stack, frames = frames, L = L }
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
    set_ABC(c.code[0], const.Op.LOADNIL, 0, 2, 0, 0)
    set_ABC(c.code[1], const.Op.RETURN, 0, 2, 0, 0)
    local n = runner(c.L)
    check("LOADNIL clears A through A+B", n == 1 and c.stack[1].tag == const.Tag.NIL and c.stack[2].tag == const.Tag.NIL and c.stack[3].tag == const.Tag.NIL)
end

-- LOADKX uses the following EXTRAARG and skips it.
do
    local c = make_case(3, 2)
    setint(c.consts[0], 111); setint(c.consts[1], 222)
    set_ABC(c.code[0], const.Op.LOADKX, 0, 0, 0, 0)
    set_Ax(c.code[1], const.Op.EXTRAARG, 1)
    set_ABC(c.code[2], const.Op.RETURN, 0, 2, 0, 0)
    local n = runner(c.L)
    check("LOADKX reads EXTRAARG and advances pc by 2", n == 1 and c.stack[1].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[1].bits)) == 222)
end

-- ADDI uses immediate C, not register C.
do
    local c = make_case(3, 0)
    setint(c.stack[1], 40); setint(c.stack[2], 9000)
    set_AsC(c.code[0], const.Op.ADDI, 0, 0, 2, 0)
    set_ABC(c.code[1], const.Op.MMBINI, 0, 2 + bytecode.OFFSET_SC, const.TM.ADD, 0)
    set_ABC(c.code[2], const.Op.RETURN, 0, 2, 0, 0)
    local n = runner(c.L)
    check("ADDI uses immediate operand", n == 1 and c.stack[1].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[1].bits)) == 42)
end

-- ADDK uses constant C, not register C.
do
    local c = make_case(3, 1)
    setint(c.stack[1], 40); setint(c.stack[2], 9000); setint(c.consts[0], 2)
    set_ABC(c.code[0], const.Op.ADDK, 0, 0, 0, 0)
    set_ABC(c.code[1], const.Op.MMBINK, 0, 0, const.TM.ADD, 0)
    set_ABC(c.code[2], const.Op.RETURN, 0, 2, 0, 0)
    local n = runner(c.L)
    check("ADDK uses constant operand", n == 1 and c.stack[1].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[1].bits)) == 42)
end

-- ADD on TAG_NUM reinterprets f64 payload bits; it must not numerically
-- convert the u64 payload to f64.
do
    local c = make_case(3, 0)
    setnum(c.stack[1], 1.5); setnum(c.stack[2], 2.25)
    set_ABC(c.code[0], const.Op.ADD, 2, 0, 1, 0)
    set_ABC(c.code[1], const.Op.MMBIN, 0, 1, const.TM.ADD, 0)
    set_ABC(c.code[2], const.Op.RETURN, 2, 2, 0, 0)
    local n = runner(c.L)
    local got = bitsdbl(c.stack[3].bits)
    check("ADD preserves f64 payload semantics", n == 1 and c.stack[3].tag == const.Tag.NUM and math.abs(got - 3.75) < 1e-12, "got " .. tostring(got))
end

-- Mixed integer/float arithmetic is primitive Lua numeric behavior, not a
-- metamethod fallback.
do
    local c = make_case(3, 0)
    setint(c.stack[1], 2); setnum(c.stack[2], 1.5)
    set_ABC(c.code[0], const.Op.ADD, 2, 0, 1, 0)
    set_ABC(c.code[1], const.Op.MMBIN, 0, 1, const.TM.ADD, 0)
    set_ABC(c.code[2], const.Op.RETURN, 2, 2, 0, 0)
    local n = runner(c.L)
    check("ADD int+float is primitive numeric", n == 1 and c.stack[3].tag == const.Tag.NUM and math.abs(bitsdbl(c.stack[3].bits) - 3.5) < 1e-12)
end

-- Lua division always produces a float, including integer operands.
do
    local c = make_case(3, 0)
    setint(c.stack[1], 9); setint(c.stack[2], 3)
    set_ABC(c.code[0], const.Op.DIV, 2, 0, 1, 0)
    set_ABC(c.code[1], const.Op.MMBIN, 0, 1, const.TM.DIV, 0)
    set_ABC(c.code[2], const.Op.RETURN, 2, 2, 0, 0)
    local n = runner(c.L)
    check("DIV int/int returns numeric float", n == 1 and c.stack[3].tag == const.Tag.NUM and math.abs(bitsdbl(c.stack[3].bits) - 3.0) < 1e-12)
end

-- Integer modulo and integer floor-division opcode paths no longer fail loud
-- for primitive integer operands.
do
    local c = make_case(3, 0)
    setint(c.stack[1], 10); setint(c.stack[2], 4)
    set_ABC(c.code[0], const.Op.MOD, 2, 0, 1, 0)
    set_ABC(c.code[1], const.Op.MMBIN, 0, 1, const.TM.MOD, 0)
    set_ABC(c.code[2], const.Op.RETURN, 2, 2, 0, 0)
    local n = runner(c.L)
    check("MOD integer primitive path", n == 1 and c.stack[3].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[3].bits)) == 2)
end

do
    local c = make_case(3, 1)
    setint(c.stack[1], 10); setint(c.consts[0], 4)
    set_ABC(c.code[0], const.Op.IDIVK, 2, 0, 0, 0)
    set_ABC(c.code[1], const.Op.MMBINK, 0, 0, const.TM.IDIV, 0)
    set_ABC(c.code[2], const.Op.RETURN, 2, 2, 0, 0)
    local n = runner(c.L)
    check("IDIVK integer primitive path", n == 1 and c.stack[3].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[3].bits)) == 2)
end

-- Inlined scalar ops: LOADI/LOADF/LOADTRUE/NOT/TEST/JMP should preserve handler semantics.
do
    local c = make_case(7, 0)
    set_ABC(c.code[0], const.Op.LOADTRUE, 0, 0, 0, 0)
    set_ABC(c.code[1], const.Op.NOT, 1, 0, 0, 0)
    set_ABC(c.code[2], const.Op.TEST, 1, 0, 0, 0) -- false and c=0: no skip
    set_AsBx(c.code[3], const.Op.JMP, 0, 2)
    set_AsBx(c.code[4], const.Op.LOADI, 2, 13)
    set_AsBx(c.code[5], const.Op.LOADI, 2, 42)
    set_ABC(c.code[6], const.Op.RETURN, 2, 2, 0, 0)
    c.frames[0].top = 4; c.L.top = 4
    local n = runner(c.L)
    check("LOADTRUE/NOT/TEST/JMP inline semantics", n == 1 and c.stack[3].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[3].bits)) == 42)
end

do
    local c = make_case(2, 0)
    set_AsBx(c.code[0], const.Op.LOADF, 0, 42)
    set_ABC(c.code[1], const.Op.RETURN, 0, 2, 0, 0)
    local n = runner(c.L)
    check("LOADF inline stores f64 payload", n == 1 and c.stack[1].tag == const.Tag.NUM and math.abs(bitsdbl(c.stack[1].bits) - 42.0) < 1e-12)
end

-- Inlined compare ops keep numeric fast paths and LT falls back for strings.
do
    local c = make_case(5, 0)
    setnum(c.stack[1], 42.0); setnum(c.stack[2], 42.0)
    set_ABC(c.code[0], const.Op.EQ, 1, 0, 1, 0) -- true => skip failure
    set_AsBx(c.code[1], const.Op.JMP, 0, 3)
    set_AsBx(c.code[2], const.Op.LOADI, 2, 42)
    set_ABC(c.code[3], const.Op.RETURN, 2, 2, 0, 0)
    set_AsBx(c.code[4], const.Op.LOADI, 2, 13)
    c.frames[0].top = 4; c.L.top = 4
    local n = runner(c.L)
    check("EQ numeric inline semantics", n == 1 and c.stack[3].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[3].bits)) == 42)
end

do
    local c = make_case(5, 0)
    setint(c.stack[1], 42); setnum(c.stack[2], 42.0)
    set_ABC(c.code[0], const.Op.EQ, 1, 0, 1, 0)
    set_AsBx(c.code[1], const.Op.JMP, 0, 3)
    set_AsBx(c.code[2], const.Op.LOADI, 2, 42)
    set_ABC(c.code[3], const.Op.RETURN, 2, 2, 0, 0)
    set_AsBx(c.code[4], const.Op.LOADI, 2, 13)
    c.frames[0].top = 4; c.L.top = 4
    local n = runner(c.L)
    check("EQ int/float exact numeric equality", n == 1 and c.stack[3].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[3].bits)) == 42)
end

do
    local c = make_case(6, 0)
    setstr(c.stack[1], "a"); setstr(c.stack[2], "b")
    set_ABC(c.code[0], const.Op.LT, 1, 0, 1, 0) -- string fallback true => success path
    set_AsBx(c.code[1], const.Op.JMP, 0, 3)
    set_AsBx(c.code[2], const.Op.LOADI, 2, 42)
    set_ABC(c.code[3], const.Op.RETURN, 2, 2, 0, 0)
    set_AsBx(c.code[4], const.Op.LOADI, 2, 13)
    set_ABC(c.code[5], const.Op.RETURN, 2, 2, 0, 0)
    c.frames[0].top = 4; c.L.top = 4
    local n = runner(c.L)
    check("LT string fallback semantics", n == 1 and c.stack[3].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[3].bits)) == 42)
end

-- LEN on strings returns byte length without using a runtime side channel.
do
    local c = make_case(2, 0)
    setstr(c.stack[1], "hello")
    set_ABC(c.code[0], const.Op.LEN, 1, 0, 0, 0)
    set_ABC(c.code[1], const.Op.RETURN1, 1, 0, 0, 0)
    local n = runner(c.L)
    check("LEN string primitive semantics", n == 1 and c.stack[2].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[2].bits)) == 5)
end

-- RETURN1 carries A through the return path.
do
    local c = make_case(1, 0)
    setint(c.stack[1], 111); setint(c.stack[2], 222)
    set_ABC(c.code[0], const.Op.RETURN1, 1, 0, 0, 0)
    local n = runner(c.L)
    check("RETURN1 returns R[A]", n == 1 and c.stack[2].tag == const.Tag.INTEGER and tonumber(ffi.cast("int64_t", c.stack[2].bits)) == 222)
end

runner:free()
print(string.format("\n=== %d/%d passed ===\n", pass, pass + fail))
if fail > 0 then os.exit(1) end
