-- Bytecode validator contract tests for the Moonlift Lua VM.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const
local bytecode = vm.bytecode

ffi.cdef [[
typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct { uint32_t word; } Instr;
typedef struct LuaThread LuaThread;
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
]]

local function set_ABC(i, op, a, b, c, k) i.word = bytecode.encode_ABC(op, a, b, c, k) end
local function set_ABx(i, op, a, bx) i.word = bytecode.encode_ABx(op, a, bx) end
local function set_AsBx(i, op, a, sbx) i.word = bytecode.encode_AsBx(op, a, sbx) end
local function set_Ax(i, op, ax) i.word = bytecode.encode_Ax(op, ax) end
local function set_sJ(i, op, sj) i.word = bytecode.encode_sJ(op, sj) end
local function set_AvBCk(i, op, a, vb, vc, k) i.word = bytecode.encode_AvBCk(op, a, vb, vc, k) end
local function set_AsC(i, op, a, b, sc, k) i.word = bytecode.encode_ABC(op, a, b, sc + bytecode.OFFSET_SC, k) end

local validate = moon.func { validate_proto = vm.validate.validate_proto } [[
validate_one(L: ptr(LuaThread), p: ptr(Proto)): i32
    return region: i32
    entry start()
        emit @{validate_proto}(L, p;
            ok = good,
            invalid = bad,
            oom = oom_bad)
    end
    block good() return 0 end
    block bad(code: i32) return code end
    block oom_bad() return -999 end
    end
end
]]:compile()

local function proto(ncode, nconst, maxstack, nchildren)
    local p = ffi.new("Proto[1]")
    local code = ffi.new("Instr[?]", math.max(ncode, 1))
    local consts = ffi.new("Value[?]", math.max(nconst, 1))
    local children = ffi.new("void*[?]", math.max(nchildren or 0, 1))
    p[0].code = code; p[0].code_len = ncode
    p[0].constants = consts; p[0].constants_len = nconst
    p[0].children = children; p[0].children_len = nchildren or 0
    p[0].maxstack = maxstack or 4
    return p, code, consts, children
end

local pass, fail = 0, 0
local function check(name, expect_ok, build)
    local p, code = proto(4, 2, 4, 1)
    build(p[0], code)
    local r = validate(ffi.cast("LuaThread*", nil), p)
    local ok = expect_ok and r == 0 or r ~= 0
    if ok then pass = pass + 1; print("  PASS " .. name)
    else fail = fail + 1; print(string.format("  FAIL %s: validator returned %d", name, r)) end
end

print("=== VM validator contract checks ===\n")

check("valid LOADK; RETURN1", true, function(p, code)
    p.code_len = 2; p.constants_len = 1; p.maxstack = 2
    set_ABx(code[0], const.Op.LOADK, 0, 0)
    set_ABC(code[1], const.Op.RETURN1, 0, 0, 0, 0)
end)
check("bad opcode 85", false, function(p, code)
    p.code_len = 1; set_ABC(code[0], 85, 0, 0, 0, 0)
end)
check("A >= maxstack", false, function(p, code)
    p.code_len = 1; p.maxstack = 1; set_ABC(code[0], const.Op.MOVE, 1, 0, 0, 0)
end)
check("LOADK constant out of bounds", false, function(p, code)
    p.code_len = 1; p.constants_len = 1; set_ABx(code[0], const.Op.LOADK, 0, 1)
end)
check("LOADKX missing EXTRAARG", false, function(p, code)
    p.code_len = 2; p.constants_len = 1; set_ABx(code[0], const.Op.LOADKX, 0, 0); set_ABC(code[1], const.Op.RETURN1, 0, 0, 0, 0)
end)
check("standalone EXTRAARG", false, function(p, code)
    p.code_len = 1; set_ABx(code[0], const.Op.EXTRAARG, 0, 0)
end)
check("ADD not followed by MMBIN", false, function(p, code)
    p.code_len = 2; set_ABC(code[0], const.Op.ADD, 0, 0, 1, 0); set_ABC(code[1], const.Op.RETURN1, 0, 0, 0, 0)
end)
check("ADDK not followed by MMBINK", false, function(p, code)
    p.code_len = 2; p.constants_len = 1; set_ABC(code[0], const.Op.ADDK, 0, 0, 0, 0); set_ABC(code[1], const.Op.MMBIN, 0, 0, const.TM.ADD, 0)
end)
check("valid ADD paired with matching MMBIN", true, function(p, code)
    p.code_len = 2; p.maxstack = 3
    set_ABC(code[0], const.Op.ADD, 0, 1, 2, 0)
    set_ABC(code[1], const.Op.MMBIN, 1, 2, const.TM.ADD, 0)
end)
check("ADD paired with wrong metamethod event", false, function(p, code)
    p.code_len = 2; p.maxstack = 3
    set_ABC(code[0], const.Op.ADD, 0, 1, 2, 0)
    set_ABC(code[1], const.Op.MMBIN, 1, 2, const.TM.SUB, 0)
end)
check("ADD paired with wrong MMBIN operands", false, function(p, code)
    p.code_len = 2; p.maxstack = 4
    set_ABC(code[0], const.Op.ADD, 0, 1, 2, 0)
    set_ABC(code[1], const.Op.MMBIN, 2, 1, const.TM.ADD, 0)
end)
check("valid ADDI paired with matching MMBINI", true, function(p, code)
    p.code_len = 2; p.maxstack = 2
    set_AsC(code[0], const.Op.ADDI, 0, 0, 2, 0)
    set_ABC(code[1], const.Op.MMBINI, 0, 2 + bytecode.OFFSET_SC, const.TM.ADD, 0)
end)
check("ADDK paired with wrong metamethod event", false, function(p, code)
    p.code_len = 2; p.constants_len = 1; p.maxstack = 2
    set_ABC(code[0], const.Op.ADDK, 0, 0, 0, 0)
    set_ABC(code[1], const.Op.MMBINK, 0, 0, const.TM.SUB, 0)
end)
check("jump target out of range", false, function(p, code)
    p.code_len = 1; set_sJ(code[0], const.Op.JMP, 99)
end)
check("LOADKX Ax constant out of bounds", false, function(p, code)
    p.code_len = 2; p.constants_len = 1; set_ABx(code[0], const.Op.LOADKX, 0, 0); set_Ax(code[1], const.Op.EXTRAARG, 1)
end)
check("comparison must be followed by JMP", false, function(p, code)
    p.code_len = 2; set_ABC(code[0], const.Op.EQ, 0, 0, 1, 0); set_ABC(code[1], const.Op.RETURN1, 0, 0, 0, 0)
end)
check("TEST must be followed by JMP", false, function(p, code)
    p.code_len = 2; set_ABC(code[0], const.Op.TEST, 0, 0, 0, 0); set_ABC(code[1], const.Op.RETURN1, 0, 0, 0, 0)
end)
check("NEWTABLE k=1 missing EXTRAARG", false, function(p, code)
    p.code_len = 1; set_AvBCk(code[0], const.Op.NEWTABLE, 0, 1, 1, 1)
end)
check("SETLIST k=1 missing EXTRAARG", false, function(p, code)
    p.code_len = 1; set_AvBCk(code[0], const.Op.SETLIST, 0, 1, 1, 1)
end)
check("EXTRAARG after NEWTABLE k=0 invalid", false, function(p, code)
    p.code_len = 2; set_AvBCk(code[0], const.Op.NEWTABLE, 0, 1, 1, 0); set_Ax(code[1], const.Op.EXTRAARG, 3)
end)
check("valid NEWTABLE k=1 EXTRAARG", true, function(p, code)
    p.code_len = 2; set_AvBCk(code[0], const.Op.NEWTABLE, 0, 1, 1, 1); set_Ax(code[1], const.Op.EXTRAARG, 3)
end)
check("valid JMP sJ in range", true, function(p, code)
    p.code_len = 2; set_sJ(code[0], const.Op.JMP, 1); set_ABC(code[1], const.Op.RETURN1, 0, 0, 0, 0)
end)
check("valid FORLOOP Bx target", true, function(p, code)
    p.code_len = 2; p.maxstack = 5; set_ABC(code[0], const.Op.RETURN1, 0, 0, 0, 0); set_ABx(code[1], const.Op.FORLOOP, 0, 1)
end)
check("CALL register window exceeds maxstack", false, function(p, code)
    p.code_len = 1; p.maxstack = 2; set_ABC(code[0], const.Op.CALL, 1, 3, 1, 0)
end)
check("CLOSURE child index out of bounds", false, function(p, code)
    p.code_len = 1; p.children_len = 1; set_ABx(code[0], const.Op.CLOSURE, 0, 1)
end)

validate:free()
print(string.format("\n=== %d/%d passed ===", pass, pass + fail))
assert(fail == 0)
return true
