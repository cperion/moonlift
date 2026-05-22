-- Lua Interpreter VM — Source-byte lexer regions (first Lua 5.5 slice)

local moon = require("moonlift")
local host = require("moonlift.host")
local pconst = require("experiments.lua_interpreter_vm.src.parser_constants")

local V = {}
for k, v in pairs(pconst.Tok) do V["TOK_" .. k] = moon.int(v) end
for k, v in pairs(pconst.Kw) do V["KW_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ParseErr) do V["PERR_" .. k] = moon.int(v) end

local make_lex_error = host.region(V) [[
region make_lex_error(cu: ptr(CompileUnit), code: i32, token: u16;
                      error: cont(err: CompileError))
entry start()
    let err: CompileError = {
        code = code,
        pos = { offset = cu.lexer.pos, line = cu.lexer.line, col = cu.lexer.col },
        token = token
    }
    jump error(err = err)
end
end
]]

local byte_is_name_start = host.region [[
region byte_is_name_start(c: u8; yes: cont(), no: cont())
entry start()
    if c >= 65 and c <= 90 then jump yes() end
    if c >= 97 and c <= 122 then jump yes() end
    if c == 95 then jump yes() end
    jump no()
end
end
]]

local byte_is_name_continue = host.region [[
region byte_is_name_continue(c: u8; yes: cont(), no: cont())
entry start()
    if c >= 65 and c <= 90 then jump yes() end
    if c >= 97 and c <= 122 then jump yes() end
    if c >= 48 and c <= 57 then jump yes() end
    if c == 95 then jump yes() end
    jump no()
end
end
]]

local byte_is_digit = host.region [[
region byte_is_digit(c: u8; yes: cont(), no: cont())
entry start()
    if c >= 48 and c <= 57 then jump yes() end
    jump no()
end
end
]]

local keyword_kind = host.region(V) [[
region keyword_kind(bytes: ptr(u8), start: index, len: index;
                    keyword: cont(kind: u16), name: cont())
entry check_len()
    if len == 5 then
        if bytes[start] == 108 and bytes[start + 1] == 111 and bytes[start + 2] == 99 and bytes[start + 3] == 97 and bytes[start + 4] == 108 then
            jump keyword(kind = as(u16, @{KW_LOCAL}))
        end
    end
    if len == 6 then
        if bytes[start] == 114 and bytes[start + 1] == 101 and bytes[start + 2] == 116 and bytes[start + 3] == 117 and bytes[start + 4] == 114 and bytes[start + 5] == 110 then
            jump keyword(kind = as(u16, @{KW_RETURN}))
        end
    end
    jump name()
end
end
]]

local lex_next = host.region(V) [[
region lex_next(cu: ptr(CompileUnit);
                token: cont(tok: Token),
                lexical_error: cont(err: CompileError),
                oom: cont())
entry start()
    if cu.lexer.has_lookahead ~= 0 then
        cu.lexer.current = cu.lexer.lookahead
        cu.lexer.has_lookahead = 0
        jump token(tok = cu.lexer.current)
    end
    jump skip_space(pos = cu.lexer.pos, line = cu.lexer.line, col = cu.lexer.col)
end
block skip_space(pos: index, line: i32, col: i32)
    if pos >= cu.lexer.src.len then jump eof(pos = pos, line = line, col = col) end
    let c: u8 = cu.lexer.src.bytes[pos]
    if c == 32 or c == 9 then jump skip_space(pos = pos + 1, line = line, col = col + 1) end
    if c == 10 then jump skip_space(pos = pos + 1, line = line + 1, col = 1) end
    if c == 13 then jump skip_space(pos = pos + 1, line = line + 1, col = 1) end
    cu.lexer.pos = pos
    cu.lexer.line = line
    cu.lexer.col = col
    if c >= 65 and c <= 90 then jump scan_name(i = pos + 1, h = as(u32, c)) end
    if c >= 97 and c <= 122 then jump scan_name(i = pos + 1, h = as(u32, c)) end
    if c == 95 then jump scan_name(i = pos + 1, h = as(u32, c)) end
    if c >= 48 and c <= 57 then jump scan_int(i = pos + 1, value = as(i64, c - 48)) end
    jump operator_dispatch(pos = pos, c = c)
end
block eof(pos: index, line: i32, col: i32)
    let tok: Token = { kind = as(u16, @{TOK_EOF}), start = pos, len = 0, line = line, aux = 0, bits = 0 }
    cu.lexer.pos = pos
    cu.lexer.line = line
    cu.lexer.col = col
    cu.lexer.current = tok
    jump token(tok = tok)
end
block scan_name(i: index, h: u32)
    if i >= cu.lexer.src.len then jump finish_name(i = i, h = h) end
    let c: u8 = cu.lexer.src.bytes[i]
    if c >= 65 and c <= 90 then jump scan_name(i = i + 1, h = h * 33 + as(u32, c)) end
    if c >= 97 and c <= 122 then jump scan_name(i = i + 1, h = h * 33 + as(u32, c)) end
    if c >= 48 and c <= 57 then jump scan_name(i = i + 1, h = h * 33 + as(u32, c)) end
    if c == 95 then jump scan_name(i = i + 1, h = h * 33 + as(u32, c)) end
    jump finish_name(i = i, h = h)
end
block finish_name(i: index, h: u32)
    let start_pos: index = cu.lexer.pos
    let l: index = i - start_pos
    if l == 5 then
        if cu.lexer.src.bytes[start_pos] == 108 and cu.lexer.src.bytes[start_pos + 1] == 111 and cu.lexer.src.bytes[start_pos + 2] == 99 and cu.lexer.src.bytes[start_pos + 3] == 97 and cu.lexer.src.bytes[start_pos + 4] == 108 then
            jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_LOCAL}))
        end
    end
    if l == 6 then
        if cu.lexer.src.bytes[start_pos] == 114 and cu.lexer.src.bytes[start_pos + 1] == 101 and cu.lexer.src.bytes[start_pos + 2] == 116 and cu.lexer.src.bytes[start_pos + 3] == 117 and cu.lexer.src.bytes[start_pos + 4] == 114 and cu.lexer.src.bytes[start_pos + 5] == 110 then
            jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_RETURN}))
        end
    end
    jump finish_name_token(i = i, h = h, kind = as(u16, @{TOK_NAME}))
end
block finish_name_token(i: index, h: u32, kind: u16)
    let start_pos: index = cu.lexer.pos
    let l: index = i - start_pos
    let tok: Token = { kind = kind, start = start_pos, len = l, line = cu.lexer.line, aux = 0, bits = as(u64, h) }
    cu.lexer.pos = i
    cu.lexer.col = cu.lexer.col + as(i32, l)
    cu.lexer.current = tok
    jump token(tok = tok)
end
block scan_int(i: index, value: i64)
    if i >= cu.lexer.src.len then jump finish_int(i = i, value = value) end
    let c: u8 = cu.lexer.src.bytes[i]
    if c >= 48 and c <= 57 then jump scan_int(i = i + 1, value = value * 10 + as(i64, c - 48)) end
    jump finish_int(i = i, value = value)
end
block finish_int(i: index, value: i64)
    let start_pos: index = cu.lexer.pos
    let l: index = i - start_pos
    let tok: Token = { kind = as(u16, @{TOK_INT}), start = start_pos, len = l, line = cu.lexer.line, aux = 0, bits = as(u64, value) }
    cu.lexer.pos = i
    cu.lexer.col = cu.lexer.col + as(i32, l)
    cu.lexer.current = tok
    jump token(tok = tok)
end
block operator_dispatch(pos: index, c: u8)
    if c == 43 then jump one_byte(pos = pos, kind = as(u16, @{TOK_PLUS})) end
    if c == 61 then jump one_byte(pos = pos, kind = as(u16, @{TOK_ASSIGN})) end
    if c == 59 then jump one_byte(pos = pos, kind = as(u16, @{TOK_SEMI})) end
    if c == 40 then jump one_byte(pos = pos, kind = as(u16, @{TOK_LPAREN})) end
    if c == 41 then jump one_byte(pos = pos, kind = as(u16, @{TOK_RPAREN})) end
    emit make_lex_error(cu, @{PERR_UNEXPECTED_CHAR}, as(u16, 0); error = lex_err)
end
block one_byte(pos: index, kind: u16)
    let tok: Token = { kind = kind, start = pos, len = 1, line = cu.lexer.line, aux = 0, bits = as(u64, cu.lexer.src.bytes[pos]) }
    cu.lexer.pos = pos + 1
    cu.lexer.col = cu.lexer.col + 1
    cu.lexer.current = tok
    jump token(tok = tok)
end
block lex_err(err: CompileError)
    jump lexical_error(err = err)
end
end
]]

return {
    make_lex_error = make_lex_error,
    byte_is_name_start = byte_is_name_start,
    byte_is_name_continue = byte_is_name_continue,
    byte_is_digit = byte_is_digit,
    keyword_kind = keyword_kind,
    lex_next = lex_next,
}
