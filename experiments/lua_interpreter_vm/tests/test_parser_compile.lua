package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

ffi.cdef [[
typedef struct String String;
typedef struct Proto Proto;
typedef struct FuncBuilder FuncBuilder;
typedef struct CompileArena CompileArena;
typedef struct LabelDesc LabelDesc;
typedef struct GCHeader { void* next; uint8_t tt; uint8_t marked; } GCHeader;
typedef struct Value { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
typedef struct Instr { uint16_t op; uint16_t a; uint16_t b; uint16_t c; uint8_t k; uint32_t bx; int32_t sbx; } Instr;
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
typedef struct CompileUnit { CompileArena* arena; Lexer lexer; FuncBuilder* root; FuncBuilder* current; ExpDesc expr_tmp; ExpDesc expr_tmp2; Token token_tmp; } CompileUnit;
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

local function run_case(src, expected_ops)
    local cu = ffi.new("CompileUnit[1]")
    local b = ffi.new("FuncBuilder[1]")
    local p = ffi.new("Proto[1]")
    local code = ffi.new("Instr[32]")
    local locals = ffi.new("CompileLocal[16]")
    local bytes = ffi.new("uint8_t[?]", #src)
    ffi.copy(bytes, src, #src)
    local n = compiled(cu, b, p, bytes, #src, code, locals)
    assert(n == #expected_ops, string.format("%q code_len: got %d expected %d", src, n, #expected_ops))
    for i, op in ipairs(expected_ops) do
        assert(code[i - 1].op == op, string.format("%q op[%d]: got %d expected %d", src, i - 1, code[i - 1].op, op))
    end
    print("PASS", src)
end

run_case("return 1 + 2", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 })
run_case("local x = 41 return x + 1", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 })

compiled:free()
return true
