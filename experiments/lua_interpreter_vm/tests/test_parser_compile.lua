package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const
local pconst = vm.parser_const
local function op_of(i) return bit.band(i.word, 127) end

ffi.cdef [[
typedef struct String String;
typedef struct Proto Proto;
typedef struct FuncBuilder FuncBuilder;
typedef struct CompileArena CompileArena;
typedef struct LabelDesc LabelDesc;
typedef struct GCHeader { void* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct Value { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct Instr { uint32_t word; } Instr;
typedef struct LocVar { String* name; uint64_t startpc; uint64_t endpc; } LocVar;
typedef struct UpValDesc { String* name; uint8_t instack; uint16_t index; } UpValDesc;
struct Proto {
    GCHeader gc;
    Instr* code; uint64_t code_len;
    Value* constants; uint64_t constants_len;
    Proto** children; uint64_t children_len;
    int32_t* lineinfo; uint64_t lineinfo_len;
    LocVar* locvars; uint64_t locvars_len;
    UpValDesc* upvals; uint64_t upvals_len;
    String* source;
    int32_t linedefined; int32_t lastlinedefined;
    uint8_t numparams; uint8_t flag; uint16_t maxstack;
};
typedef struct SourceView { uint8_t* bytes; uint64_t len; String* source_name; } SourceView;
typedef struct SourcePos { uint64_t offset; int32_t line; int32_t col; } SourcePos;
typedef struct CompileError { int32_t code; SourcePos pos; uint16_t token; } CompileError;
typedef struct Token { uint16_t kind; uint64_t start; uint64_t len; int32_t line; uint32_t aux; uint64_t bits; } Token;
typedef struct Lexer { SourceView src; uint64_t pos; int32_t line; int32_t col; Token current; Token lookahead; uint8_t has_lookahead; } Lexer;
typedef struct InstrVec { Instr* data; uint64_t len; uint64_t cap; } InstrVec;
typedef struct ValueVec { Value* data; uint64_t len; uint64_t cap; } ValueVec;
typedef struct ProtoPtrVec { Proto** data; uint64_t len; uint64_t cap; } ProtoPtrVec;
typedef struct LocVarVec { LocVar* data; uint64_t len; uint64_t cap; } LocVarVec;
typedef struct UpValDescVec { UpValDesc* data; uint64_t len; uint64_t cap; } UpValDescVec;
typedef struct CompileLocal { uint64_t name_start; uint64_t name_len; uint32_t hash; uint16_t reg; uint8_t kind; } CompileLocal;
struct LabelDesc { String* name; uint64_t pc; int32_t line; uint16_t nactvar; };
struct FuncBuilder {
    FuncBuilder* parent; Proto* out_proto;
    InstrVec code; ValueVec constants; ProtoPtrVec children; LocVarVec locvars; UpValDescVec upvals;
    CompileLocal* locals; uint64_t locals_len; uint64_t locals_cap;
    LabelDesc* labels; uint64_t labels_len; uint64_t labels_cap;
    LabelDesc* gotos; uint64_t gotos_len; uint64_t gotos_cap;
    uint64_t firstlocal; uint16_t nactvar; uint16_t freereg; uint16_t maxstack;
    uint64_t pc; uint64_t lasttarget; uint8_t numparams; uint8_t flag;
};
typedef struct ExpDesc { uint16_t kind; uint32_t info; uint32_t aux; uint64_t t; uint64_t f; Value value; } ExpDesc;
typedef struct CompileUnit { CompileArena* arena; Lexer lexer; FuncBuilder* root; FuncBuilder* current; ExpDesc expr_tmp; ExpDesc expr_tmp2; ExpDesc expr_tmp3; Token token_tmp; uint16_t tmp_reg; } CompileUnit;
typedef struct { GCHeader gc; void* env; Proto* proto; void** upvals; uint8_t nupvals; } LClosure;
typedef struct {
    Value closure; uint64_t base; uint64_t top; uint64_t pc;
    int32_t wanted; int32_t tailcalls;
    uint16_t resume_mode;
    uint16_t resume_a; uint16_t resume_b; uint16_t resume_c;
    uint64_t resume_pc; uint64_t resume_base; Value resume_value;
    uint64_t result_base; uint64_t call_top;
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

local compile_region = vm.regions_compiler.compile_lua_source_into
local wrapper = moon.func { compile_lua_source_into = compile_region } [[
compile_text(cu: ptr(CompileUnit), b: ptr(FuncBuilder), p: ptr(Proto), bytes: ptr(u8), n: index, code: ptr(Instr), locals: ptr(CompileLocal)) -> i32
    return region -> i32
    entry start()
        emit @{compile_lua_source_into}(cu, b, p, bytes, n, code, as(index, 32), locals, as(index, 16);
            ok = ok,
            syntax_error = syntax_bad,
            semantic_error = semantic_bad,
            limit_error = limit_bad,
            oom = oom_bad)
    end
    block ok(proto: ptr(Proto)) yield as(i32, proto.code_len) end
    block syntax_bad(err: CompileError) yield 0 - err.code end
    block semantic_bad(err: CompileError) yield -100 - err.code end
    block limit_bad(err: CompileError) yield -200 - err.code end
    block oom_bad() yield -999 end
    end
end
]]

local compiled = assert(wrapper:compile())

local validate_proto = vm.validate.validate_proto
local vm_resume = vm.vm_loop.vm_resume
local lex_next = vm.regions_lexer.lex_next
local lex_runner = moon.func { lex_next = lex_next, TOK_EOF = moon.int(pconst.Tok.EOF) } [[
lex_kinds(cu: ptr(CompileUnit), bytes: ptr(u8), n: index, out: ptr(u16), max: index) -> i32
    return region -> i32
    entry start()
        cu.lexer.src = { bytes = bytes, len = n, source_name = nil }
        cu.lexer.pos = 0
        cu.lexer.line = 1
        cu.lexer.col = 1
        cu.lexer.has_lookahead = 0
        jump loop(count = as(index, 0))
    end
    block loop(count: index)
        if count >= max then return -900 end
        cu.token_tmp.aux = as(u32, count)
        emit @{lex_next}(cu; token = got, lexical_error = lex_bad, oom = oom_bad)
    end
    block got(tok: Token)
        let count: index = as(index, cu.token_tmp.aux)
        out[count] = tok.kind
        if tok.kind == @{TOK_EOF} then return as(i32, count + 1) end
        jump loop(count = count + 1)
    end
    block lex_bad(err: CompileError) return 0 - err.code end
    block oom_bad() return -999 end
    end
end
]]:compile()

local runner = moon.func { validate_proto = validate_proto, vm_resume = vm_resume } [[
run_proto(L: ptr(LuaThread), p: ptr(Proto)) -> i32
    return region -> i32
    entry start()
        emit @{validate_proto}(L, p; ok = valid, invalid = invalid, oom = oom_bad)
    end
    block valid()
        emit @{vm_resume}(L, 0;
            ok = done,
            yielded = yielded,
            runtime_error = runtime_bad,
            oom = oom_bad)
    end
    block done(nres: i32) return nres end
    block yielded(nres: i32) return -100 - nres end
    block runtime_bad(code: i32) return -200 - code end
    block invalid(code: i32) return -300 - code end
    block oom_bad() return -999 end
    end
end
]]:compile()

local function compile_case(src, expected_ops)
    local cu = ffi.new("CompileUnit[1]")
    local b = ffi.new("FuncBuilder[1]")
    local p = ffi.new("Proto[1]")
    local code = ffi.new("Instr[128]")
    local locals = ffi.new("CompileLocal[32]")
    local bytes = ffi.new("uint8_t[?]", #src)
    ffi.copy(bytes, src, #src)
    local n = compiled(cu, b, p, bytes, #src, code, locals)
    assert(n == #expected_ops, string.format("%q code_len: got %d expected %d", src, n, #expected_ops))
    for i, op in ipairs(expected_ops) do
        local got = op_of(code[i - 1])
        assert(got == op, string.format("%q op[%d]: got %d expected %d", src, i - 1, got, op))
    end
    print("PASS", src)
    return p, code
end

local function make_thread(proto)
    local closure = ffi.new("LClosure[1]")
    closure[0].proto = proto
    local stack = ffi.new("Value[64]")
    for i = 0, 63 do stack[i].tag = const.Tag.NIL; stack[i].aux = 0; stack[i].bits = 0 end
    stack[0].tag = const.Tag.LCLOSURE; stack[0].bits = ffi.cast("uint64_t", closure)
    local frames = ffi.new("Frame[8]")
    frames[0].closure = stack[0]
    frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0; frames[0].wanted = 1; frames[0].resume_mode = const.Resume.NORMAL
    frames[0].result_base = frames[0].base; frames[0].call_top = frames[0].top
    frames[0].yieldable = 1; frames[0].flags = 0; frames[0].reserved = 0
    local global = ffi.new("GlobalState[1]")
    local L = ffi.new("LuaThread[1]")
    L[0].status = const.Status.OK; L[0].stack = stack; L[0].stack_size = 64; L[0].top = 1
    L[0].frames = frames; L[0].frame_count = 1; L[0].frame_cap = 8; L[0].global = global
    L[0].yieldable = 1; L[0].nonyieldable = 0; L[0].last_error_code = 0; L[0].flags = 0
    global[0].mainthread = L
    return L, stack, closure, frames, global
end

local function bits_i64(x) return tonumber(ffi.cast("int64_t", x)) end

local function compile_status(src)
    local cu = ffi.new("CompileUnit[1]")
    local b = ffi.new("FuncBuilder[1]")
    local p = ffi.new("Proto[1]")
    local code = ffi.new("Instr[128]")
    local locals = ffi.new("CompileLocal[32]")
    local bytes = ffi.new("uint8_t[?]", #src)
    ffi.copy(bytes, src, #src)
    return compiled(cu, b, p, bytes, #src, code, locals)
end

local function lex_case(src, expected)
    local cu = ffi.new("CompileUnit[1]")
    local out = ffi.new("uint16_t[64]")
    local bytes = ffi.new("uint8_t[?]", #src)
    ffi.copy(bytes, src, #src)
    local n = lex_runner(cu, bytes, #src, out, 64)
    assert(n == #expected, string.format("lex %q count got %d expected %d", src, n, #expected))
    for i, kind in ipairs(expected) do
        assert(out[i - 1] == kind, string.format("lex %q token %d got %d expected %d", src, i, out[i - 1], kind))
    end
    print("LEX", src)
end

local function run_case(src, expected_ops, expect_int)
    local p, code = compile_case(src, expected_ops)
    local L, stack = make_thread(p)
    assert(code ~= nil)
    local nres = runner(L, p)
    assert(nres == 1, string.format("%q vm nres: got %d", src, nres))
    assert(stack[1].tag == const.Tag.INTEGER, string.format("%q result tag: got %d", src, stack[1].tag))
    assert(bits_i64(stack[1].bits) == expect_int, string.format("%q result: got %d expected %d", src, bits_i64(stack[1].bits), expect_int))
    print("RUN", src, "=>", expect_int)
end

lex_case("-- comment\nreturn 'abc' == name ~= nil ... .. :: <= >= < > - * / ,", {
    pconst.Kw.RETURN, pconst.Tok.STRING, pconst.Tok.EQ, pconst.Tok.NAME, pconst.Tok.NE,
    pconst.Kw.NIL, pconst.Tok.DOTDOTDOT, pconst.Tok.DOTDOT, pconst.Tok.COLONCOLON,
    pconst.Tok.LE, pconst.Tok.GE, pconst.Tok.LT, pconst.Tok.GT,
    pconst.Tok.MINUS, pconst.Tok.STAR, pconst.Tok.SLASH, pconst.Tok.COMMA, pconst.Tok.EOF,
})

run_case("return 1 + 2", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 3)
run_case("local x = 41 return x + 1", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 42)
run_case("local x = 1; -- comment\nlocal y = 2 return x + y", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 3)
run_case("return 2 + 3 * 4", { const.Op.LOADI, const.Op.LOADI, const.Op.LOADI, const.Op.MUL, const.Op.MMBIN, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 14)
run_case("return 9 - 3 * 2", { const.Op.LOADI, const.Op.LOADI, const.Op.LOADI, const.Op.MUL, const.Op.MMBIN, const.Op.SUB, const.Op.MMBIN, const.Op.RETURN1 }, 3)
compile_case("return 9 / 3", { const.Op.LOADI, const.Op.LOADI, const.Op.DIV, const.Op.MMBIN, const.Op.RETURN1 })
assert(compile_status("return 1 local x = 2") < 0, "return must reject trailing statements")

compiled:free()
lex_runner:free()
runner:free()
return true
