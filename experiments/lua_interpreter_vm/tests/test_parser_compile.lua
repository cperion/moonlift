package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const
local pconst = vm.parser_const
local function op_of(i) return bit.band(i.word, 127) end

require("experiments.lua_interpreter_vm.tools.vm_ffi_schema").apply(ffi)
assert(ffi.sizeof("CompileUnit") >= 320, "CompileUnit FFI schema is stale")

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

local runner = moon.func {
    validate_proto = validate_proto,
    vm_resume = vm_resume,
    sys_realloc = vm.regions_allocator.sys_realloc,
} [[
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
    frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0; frames[0].wanted = 1; frames[0].resume.kind = const.Resume.NORMAL
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
lex_case("global goto ^", {
    pconst.Kw.GLOBAL, pconst.Kw.GOTO, pconst.Tok.CARET, pconst.Tok.EOF,
})
lex_case("if then else elseif end while do for in repeat until break function and or not % // { } [ ] : & | ~ << >>", {
    pconst.Kw.IF, pconst.Kw.THEN, pconst.Kw.ELSE, pconst.Kw.ELSEIF, pconst.Kw.END,
    pconst.Kw.WHILE, pconst.Kw.DO, pconst.Kw.FOR, pconst.Kw.IN, pconst.Kw.REPEAT,
    pconst.Kw.UNTIL, pconst.Kw.BREAK, pconst.Kw.FUNCTION, pconst.Kw.AND, pconst.Kw.OR,
    pconst.Kw.NOT, pconst.Tok.PERCENT, pconst.Tok.SLASHSLASH, pconst.Tok.LBRACE,
    pconst.Tok.RBRACE, pconst.Tok.LBRACKET, pconst.Tok.RBRACKET, pconst.Tok.COLON,
    pconst.Tok.AMP, pconst.Tok.PIPE, pconst.Tok.TILDE, pconst.Tok.LTLT, pconst.Tok.GTGT,
    pconst.Tok.EOF,
})

compile_case("return", { const.Op.RETURN0 })
compile_case("local x = 1", { const.Op.LOADI, const.Op.RETURN0 })
run_case("return 1 + 2", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 3)
run_case("local x = 41 return x + 1", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 42)
run_case("local x = 1; -- comment\nlocal y = 2 return x + y", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 3)
run_case("return 2 + 3 * 4", { const.Op.LOADI, const.Op.LOADI, const.Op.LOADI, const.Op.MUL, const.Op.MMBIN, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 14)
run_case("return 9 - 3 * 2", { const.Op.LOADI, const.Op.LOADI, const.Op.LOADI, const.Op.MUL, const.Op.MMBIN, const.Op.SUB, const.Op.MMBIN, const.Op.RETURN1 }, 3)
compile_case("local x return x", { const.Op.LOADNIL, const.Op.RETURN1 })
run_case("local x = 1 x = x + 4 return x", { const.Op.LOADI, const.Op.LOADI, const.Op.ADD, const.Op.MMBIN, const.Op.RETURN1 }, 5)
run_case("return 10 % 4", { const.Op.LOADI, const.Op.LOADI, const.Op.MOD, const.Op.MMBIN, const.Op.RETURN1 }, 2)
run_case("return 10 // 4", { const.Op.LOADI, const.Op.LOADI, const.Op.IDIV, const.Op.MMBIN, const.Op.RETURN1 }, 2)
run_case("local x = 0 x = x - 7 return x // 3", { const.Op.LOADI, const.Op.LOADI, const.Op.SUB, const.Op.MMBIN, const.Op.LOADI, const.Op.IDIV, const.Op.MMBIN, const.Op.RETURN1 }, -3)
run_case("local x = 0 x = x - 7 return x % 3", { const.Op.LOADI, const.Op.LOADI, const.Op.SUB, const.Op.MMBIN, const.Op.LOADI, const.Op.MOD, const.Op.MMBIN, const.Op.RETURN1 }, 2)
run_case("return 6 & 3", { const.Op.LOADI, const.Op.LOADI, const.Op.BAND, const.Op.MMBIN, const.Op.RETURN1 }, 2)
run_case("local x = 0 for i = 1, 5 do x = x + i end return x", { const.Op.LOADI, const.Op.LOADI, const.Op.LOADI, const.Op.LOADI, const.Op.FORPREP, const.Op.ADD, const.Op.MMBIN, const.Op.FORLOOP, const.Op.RETURN1 }, 15)
run_case("local x = 0 for i = 5, 1, 2 do x = x + i end return x", { const.Op.LOADI, const.Op.LOADI, const.Op.LOADI, const.Op.LOADI, const.Op.FORPREP, const.Op.ADD, const.Op.MMBIN, const.Op.FORLOOP, const.Op.RETURN1 }, 0)
compile_case("return 9 / 3", { const.Op.LOADI, const.Op.LOADI, const.Op.DIV, const.Op.MMBIN, const.Op.RETURN1 })
print("NEG trailing return check")
assert(compile_status("return 1 local x = 2") < 0, "return must reject trailing statements")
print("NEG done")

-- The compiled closures are process-lifetime test fixtures. Avoid explicit free
-- here because larger compiler wrappers can spend unbounded time in backend
-- teardown on some LuaJIT/libmoonlift builds; process exit reclaims them.
return true
