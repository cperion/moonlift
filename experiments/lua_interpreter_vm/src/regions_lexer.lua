-- Lua Interpreter VM — Source-byte lexer regions (first Lua 5.5 slice)

local lalin = require("lalin")
local host = require("lalin.host")
local pconst = require("experiments.lua_interpreter_vm.src.parser_constants")

local V = {}
for k, v in pairs(pconst.Tok) do V["TOK_" .. k] = lalin.int(v) end
for k, v in pairs(pconst.Kw) do V["KW_" .. k] = lalin.int(v) end
for k, v in pairs(pconst.ParseErr) do V["PERR_" .. k] = lalin.int(v) end

local make_lex_error = host.region(V) [[
region make_lex_error(cu: ptr(CompileUnit), code: i32, token: u16;
                      error(err: CompileError))
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
region byte_is_name_start(c: u8; yes | no)

entry start()
    if c >= 65 and c <= 90 then jump yes() end
    if c >= 97 and c <= 122 then jump yes() end
    if c == 95 then jump yes() end
    jump no()
end
end
]]

local byte_is_name_continue = host.region [[
region byte_is_name_continue(c: u8; yes | no)

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
region byte_is_digit(c: u8; yes | no)

entry start()
    if c >= 48 and c <= 57 then jump yes() end
    jump no()
end
end
]]

local keyword_kind = host.region(V) [[
region keyword_kind(bytes: ptr(u8), start: index, len: index;
                    keyword(kind: u16) | name)
entry check_len()
    if len == 2 then
        if bytes[start] == 105 and bytes[start + 1] == 102 then jump keyword(kind = as(u16, @{KW_IF})) end
        if bytes[start] == 105 and bytes[start + 1] == 110 then jump keyword(kind = as(u16, @{KW_IN})) end
        if bytes[start] == 100 and bytes[start + 1] == 111 then jump keyword(kind = as(u16, @{KW_DO})) end
        if bytes[start] == 111 and bytes[start + 1] == 114 then jump keyword(kind = as(u16, @{KW_OR})) end
    end
    if len == 3 then
        if bytes[start] == 110 and bytes[start + 1] == 105 and bytes[start + 2] == 108 then jump keyword(kind = as(u16, @{KW_NIL})) end
        if bytes[start] == 101 and bytes[start + 1] == 110 and bytes[start + 2] == 100 then jump keyword(kind = as(u16, @{KW_END})) end
        if bytes[start] == 102 and bytes[start + 1] == 111 and bytes[start + 2] == 114 then jump keyword(kind = as(u16, @{KW_FOR})) end
        if bytes[start] == 97 and bytes[start + 1] == 110 and bytes[start + 2] == 100 then jump keyword(kind = as(u16, @{KW_AND})) end
        if bytes[start] == 110 and bytes[start + 1] == 111 and bytes[start + 2] == 116 then jump keyword(kind = as(u16, @{KW_NOT})) end
    end
    if len == 4 then
        if bytes[start] == 116 and bytes[start + 1] == 114 and bytes[start + 2] == 117 and bytes[start + 3] == 101 then jump keyword(kind = as(u16, @{KW_TRUE})) end
        if bytes[start] == 101 and bytes[start + 1] == 108 and bytes[start + 2] == 115 and bytes[start + 3] == 101 then jump keyword(kind = as(u16, @{KW_ELSE})) end
        if bytes[start] == 103 and bytes[start + 1] == 111 and bytes[start + 2] == 116 and bytes[start + 3] == 111 then jump keyword(kind = as(u16, @{KW_GOTO})) end
    end
    if len == 5 then
        if bytes[start] == 108 and bytes[start + 1] == 111 and bytes[start + 2] == 99 and bytes[start + 3] == 97 and bytes[start + 4] == 108 then jump keyword(kind = as(u16, @{KW_LOCAL})) end
        if bytes[start] == 102 and bytes[start + 1] == 97 and bytes[start + 2] == 108 and bytes[start + 3] == 115 and bytes[start + 4] == 101 then jump keyword(kind = as(u16, @{KW_FALSE})) end
        if bytes[start] == 119 and bytes[start + 1] == 104 and bytes[start + 2] == 105 and bytes[start + 3] == 108 and bytes[start + 4] == 101 then jump keyword(kind = as(u16, @{KW_WHILE})) end
        if bytes[start] == 117 and bytes[start + 1] == 110 and bytes[start + 2] == 116 and bytes[start + 3] == 105 and bytes[start + 4] == 108 then jump keyword(kind = as(u16, @{KW_UNTIL})) end
        if bytes[start] == 98 and bytes[start + 1] == 114 and bytes[start + 2] == 101 and bytes[start + 3] == 97 and bytes[start + 4] == 107 then jump keyword(kind = as(u16, @{KW_BREAK})) end
    end
    if len == 6 then
        if bytes[start] == 114 and bytes[start + 1] == 101 and bytes[start + 2] == 116 and bytes[start + 3] == 117 and bytes[start + 4] == 114 and bytes[start + 5] == 110 then jump keyword(kind = as(u16, @{KW_RETURN})) end
        if bytes[start] == 101 and bytes[start + 1] == 108 and bytes[start + 2] == 115 and bytes[start + 3] == 101 and bytes[start + 4] == 105 and bytes[start + 5] == 102 then jump keyword(kind = as(u16, @{KW_ELSEIF})) end
        if bytes[start] == 114 and bytes[start + 1] == 101 and bytes[start + 2] == 112 and bytes[start + 3] == 101 and bytes[start + 4] == 97 and bytes[start + 5] == 116 then jump keyword(kind = as(u16, @{KW_REPEAT})) end
        if bytes[start] == 103 and bytes[start + 1] == 108 and bytes[start + 2] == 111 and bytes[start + 3] == 98 and bytes[start + 4] == 97 and bytes[start + 5] == 108 then jump keyword(kind = as(u16, @{KW_GLOBAL})) end
    end
    if len == 8 then
        if bytes[start] == 102 and bytes[start + 1] == 117 and bytes[start + 2] == 110 and bytes[start + 3] == 99 and bytes[start + 4] == 116 and bytes[start + 5] == 105 and bytes[start + 6] == 111 and bytes[start + 7] == 110 then jump keyword(kind = as(u16, @{KW_FUNCTION})) end
    end
    jump name()
end
end
]]

local lex_next = host.region(V) [[
region lex_next(cu: ptr(CompileUnit);
                token(tok: Token) |
                lexical_error(err: CompileError) |
                oom)
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
    if c == 45 and pos + 1 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 45 then jump skip_comment(pos = pos + 2, line = line, col = col + 2) end
    end
    cu.lexer.pos = pos
    cu.lexer.line = line
    cu.lexer.col = col
    if c >= 65 and c <= 90 then jump scan_name(i = pos + 1, h = as(u32, c)) end
    if c >= 97 and c <= 122 then jump scan_name(i = pos + 1, h = as(u32, c)) end
    if c == 95 then jump scan_name(i = pos + 1, h = as(u32, c)) end
    if c >= 48 and c <= 57 then jump scan_int(i = pos + 1, value = as(i64, c - 48)) end
    if c == 34 or c == 39 then jump scan_string(i = pos + 1, quote = c) end
    jump operator_dispatch(pos = pos, c = c)
end
block skip_comment(pos: index, line: i32, col: i32)
    if pos >= cu.lexer.src.len then jump eof(pos = pos, line = line, col = col) end
    let c: u8 = cu.lexer.src.bytes[pos]
    if c == 10 then jump skip_space(pos = pos + 1, line = line + 1, col = 1) end
    if c == 13 then jump skip_space(pos = pos + 1, line = line + 1, col = 1) end
    jump skip_comment(pos = pos + 1, line = line, col = col + 1)
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
    if l == 2 then
        if cu.lexer.src.bytes[start_pos] == 105 and cu.lexer.src.bytes[start_pos + 1] == 102 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_IF})) end
        if cu.lexer.src.bytes[start_pos] == 105 and cu.lexer.src.bytes[start_pos + 1] == 110 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_IN})) end
        if cu.lexer.src.bytes[start_pos] == 100 and cu.lexer.src.bytes[start_pos + 1] == 111 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_DO})) end
        if cu.lexer.src.bytes[start_pos] == 111 and cu.lexer.src.bytes[start_pos + 1] == 114 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_OR})) end
    end
    if l == 3 then
        if cu.lexer.src.bytes[start_pos] == 110 and cu.lexer.src.bytes[start_pos + 1] == 105 and cu.lexer.src.bytes[start_pos + 2] == 108 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_NIL})) end
        if cu.lexer.src.bytes[start_pos] == 101 and cu.lexer.src.bytes[start_pos + 1] == 110 and cu.lexer.src.bytes[start_pos + 2] == 100 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_END})) end
        if cu.lexer.src.bytes[start_pos] == 102 and cu.lexer.src.bytes[start_pos + 1] == 111 and cu.lexer.src.bytes[start_pos + 2] == 114 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_FOR})) end
        if cu.lexer.src.bytes[start_pos] == 97 and cu.lexer.src.bytes[start_pos + 1] == 110 and cu.lexer.src.bytes[start_pos + 2] == 100 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_AND})) end
        if cu.lexer.src.bytes[start_pos] == 110 and cu.lexer.src.bytes[start_pos + 1] == 111 and cu.lexer.src.bytes[start_pos + 2] == 116 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_NOT})) end
    end
    if l == 4 then
        if cu.lexer.src.bytes[start_pos] == 116 and cu.lexer.src.bytes[start_pos + 1] == 114 and cu.lexer.src.bytes[start_pos + 2] == 117 and cu.lexer.src.bytes[start_pos + 3] == 101 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_TRUE})) end
        if cu.lexer.src.bytes[start_pos] == 116 and cu.lexer.src.bytes[start_pos + 1] == 104 and cu.lexer.src.bytes[start_pos + 2] == 101 and cu.lexer.src.bytes[start_pos + 3] == 110 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_THEN})) end
        if cu.lexer.src.bytes[start_pos] == 101 and cu.lexer.src.bytes[start_pos + 1] == 108 and cu.lexer.src.bytes[start_pos + 2] == 115 and cu.lexer.src.bytes[start_pos + 3] == 101 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_ELSE})) end
        if cu.lexer.src.bytes[start_pos] == 103 and cu.lexer.src.bytes[start_pos + 1] == 111 and cu.lexer.src.bytes[start_pos + 2] == 116 and cu.lexer.src.bytes[start_pos + 3] == 111 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_GOTO})) end
    end
    if l == 5 then
        if cu.lexer.src.bytes[start_pos] == 108 and cu.lexer.src.bytes[start_pos + 1] == 111 and cu.lexer.src.bytes[start_pos + 2] == 99 and cu.lexer.src.bytes[start_pos + 3] == 97 and cu.lexer.src.bytes[start_pos + 4] == 108 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_LOCAL})) end
        if cu.lexer.src.bytes[start_pos] == 102 and cu.lexer.src.bytes[start_pos + 1] == 97 and cu.lexer.src.bytes[start_pos + 2] == 108 and cu.lexer.src.bytes[start_pos + 3] == 115 and cu.lexer.src.bytes[start_pos + 4] == 101 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_FALSE})) end
        if cu.lexer.src.bytes[start_pos] == 119 and cu.lexer.src.bytes[start_pos + 1] == 104 and cu.lexer.src.bytes[start_pos + 2] == 105 and cu.lexer.src.bytes[start_pos + 3] == 108 and cu.lexer.src.bytes[start_pos + 4] == 101 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_WHILE})) end
        if cu.lexer.src.bytes[start_pos] == 117 and cu.lexer.src.bytes[start_pos + 1] == 110 and cu.lexer.src.bytes[start_pos + 2] == 116 and cu.lexer.src.bytes[start_pos + 3] == 105 and cu.lexer.src.bytes[start_pos + 4] == 108 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_UNTIL})) end
        if cu.lexer.src.bytes[start_pos] == 98 and cu.lexer.src.bytes[start_pos + 1] == 114 and cu.lexer.src.bytes[start_pos + 2] == 101 and cu.lexer.src.bytes[start_pos + 3] == 97 and cu.lexer.src.bytes[start_pos + 4] == 107 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_BREAK})) end
    end
    if l == 6 then
        if cu.lexer.src.bytes[start_pos] == 114 and cu.lexer.src.bytes[start_pos + 1] == 101 and cu.lexer.src.bytes[start_pos + 2] == 116 and cu.lexer.src.bytes[start_pos + 3] == 117 and cu.lexer.src.bytes[start_pos + 4] == 114 and cu.lexer.src.bytes[start_pos + 5] == 110 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_RETURN})) end
        if cu.lexer.src.bytes[start_pos] == 101 and cu.lexer.src.bytes[start_pos + 1] == 108 and cu.lexer.src.bytes[start_pos + 2] == 115 and cu.lexer.src.bytes[start_pos + 3] == 101 and cu.lexer.src.bytes[start_pos + 4] == 105 and cu.lexer.src.bytes[start_pos + 5] == 102 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_ELSEIF})) end
        if cu.lexer.src.bytes[start_pos] == 114 and cu.lexer.src.bytes[start_pos + 1] == 101 and cu.lexer.src.bytes[start_pos + 2] == 112 and cu.lexer.src.bytes[start_pos + 3] == 101 and cu.lexer.src.bytes[start_pos + 4] == 97 and cu.lexer.src.bytes[start_pos + 5] == 116 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_REPEAT})) end
        if cu.lexer.src.bytes[start_pos] == 103 and cu.lexer.src.bytes[start_pos + 1] == 108 and cu.lexer.src.bytes[start_pos + 2] == 111 and cu.lexer.src.bytes[start_pos + 3] == 98 and cu.lexer.src.bytes[start_pos + 4] == 97 and cu.lexer.src.bytes[start_pos + 5] == 108 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_GLOBAL})) end
    end
    if l == 8 then
        if cu.lexer.src.bytes[start_pos] == 102 and cu.lexer.src.bytes[start_pos + 1] == 117 and cu.lexer.src.bytes[start_pos + 2] == 110 and cu.lexer.src.bytes[start_pos + 3] == 99 and cu.lexer.src.bytes[start_pos + 4] == 116 and cu.lexer.src.bytes[start_pos + 5] == 105 and cu.lexer.src.bytes[start_pos + 6] == 111 and cu.lexer.src.bytes[start_pos + 7] == 110 then jump finish_name_token(i = i, h = h, kind = as(u16, @{KW_FUNCTION})) end
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
block scan_string(i: index, quote: u8)
    if i >= cu.lexer.src.len then
        emit make_lex_error(cu, @{PERR_UNEXPECTED_CHAR}, as(u16, 0); error = lex_err)
    end
    let c: u8 = cu.lexer.src.bytes[i]
    if c == quote then jump finish_string(i = i + 1) end
    if c == 10 or c == 13 then
        emit make_lex_error(cu, @{PERR_UNEXPECTED_CHAR}, as(u16, 0); error = lex_err)
    end
    jump scan_string(i = i + 1, quote = quote)
end
block finish_string(i: index)
    let start_pos: index = cu.lexer.pos
    let l: index = i - start_pos
    let payload_len: index = l - 2
    let tok: Token = { kind = as(u16, @{TOK_STRING}), start = start_pos + 1, len = payload_len, line = cu.lexer.line, aux = 0, bits = as(u64, start_pos + 1) }
    cu.lexer.pos = i
    cu.lexer.col = cu.lexer.col + as(i32, l)
    cu.lexer.current = tok
    jump token(tok = tok)
end
block operator_dispatch(pos: index, c: u8)
    if c == 43 then jump one_byte(pos = pos, kind = as(u16, @{TOK_PLUS})) end
    if c == 45 then jump one_byte(pos = pos, kind = as(u16, @{TOK_MINUS})) end
    if c == 42 then jump one_byte(pos = pos, kind = as(u16, @{TOK_STAR})) end
    if c == 47 and pos + 1 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 47 then jump two_byte(pos = pos, kind = as(u16, @{TOK_SLASHSLASH})) end
    end
    if c == 47 then jump one_byte(pos = pos, kind = as(u16, @{TOK_SLASH})) end
    if c == 37 then jump one_byte(pos = pos, kind = as(u16, @{TOK_PERCENT})) end
    if c == 35 then jump one_byte(pos = pos, kind = as(u16, @{TOK_HASH})) end
    if c == 94 then jump one_byte(pos = pos, kind = as(u16, @{TOK_CARET})) end
    if c == 44 then jump one_byte(pos = pos, kind = as(u16, @{TOK_COMMA})) end
    if c == 59 then jump one_byte(pos = pos, kind = as(u16, @{TOK_SEMI})) end
    if c == 40 then jump one_byte(pos = pos, kind = as(u16, @{TOK_LPAREN})) end
    if c == 41 then jump one_byte(pos = pos, kind = as(u16, @{TOK_RPAREN})) end
    if c == 123 then jump one_byte(pos = pos, kind = as(u16, @{TOK_LBRACE})) end
    if c == 125 then jump one_byte(pos = pos, kind = as(u16, @{TOK_RBRACE})) end
    if c == 91 then jump one_byte(pos = pos, kind = as(u16, @{TOK_LBRACKET})) end
    if c == 93 then jump one_byte(pos = pos, kind = as(u16, @{TOK_RBRACKET})) end
    if c == 38 then jump one_byte(pos = pos, kind = as(u16, @{TOK_AMP})) end
    if c == 124 then jump one_byte(pos = pos, kind = as(u16, @{TOK_PIPE})) end
    if c == 61 and pos + 1 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 61 then jump two_byte(pos = pos, kind = as(u16, @{TOK_EQ})) end
    end
    if c == 126 and pos + 1 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 61 then jump two_byte(pos = pos, kind = as(u16, @{TOK_NE})) end
    end
    if c == 60 and pos + 1 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 61 then jump two_byte(pos = pos, kind = as(u16, @{TOK_LE})) end
        if cu.lexer.src.bytes[pos + 1] == 60 then jump two_byte(pos = pos, kind = as(u16, @{TOK_LTLT})) end
    end
    if c == 62 and pos + 1 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 61 then jump two_byte(pos = pos, kind = as(u16, @{TOK_GE})) end
        if cu.lexer.src.bytes[pos + 1] == 62 then jump two_byte(pos = pos, kind = as(u16, @{TOK_GTGT})) end
    end
    if c == 46 and pos + 2 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 46 and cu.lexer.src.bytes[pos + 2] == 46 then jump three_byte(pos = pos, kind = as(u16, @{TOK_DOTDOTDOT})) end
    end
    if c == 46 and pos + 1 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 46 then jump two_byte(pos = pos, kind = as(u16, @{TOK_DOTDOT})) end
    end
    if c == 58 and pos + 1 < cu.lexer.src.len then
        if cu.lexer.src.bytes[pos + 1] == 58 then jump two_byte(pos = pos, kind = as(u16, @{TOK_COLONCOLON})) end
    end
    if c == 61 then jump one_byte(pos = pos, kind = as(u16, @{TOK_ASSIGN})) end
    if c == 60 then jump one_byte(pos = pos, kind = as(u16, @{TOK_LT})) end
    if c == 62 then jump one_byte(pos = pos, kind = as(u16, @{TOK_GT})) end
    if c == 58 then jump one_byte(pos = pos, kind = as(u16, @{TOK_COLON})) end
    if c == 126 then jump one_byte(pos = pos, kind = as(u16, @{TOK_TILDE})) end
    if c == 46 then jump one_byte(pos = pos, kind = as(u16, @{TOK_DOT})) end
    emit make_lex_error(cu, @{PERR_UNEXPECTED_CHAR}, as(u16, 0); error = lex_err)
end
block one_byte(pos: index, kind: u16)
    let tok: Token = { kind = kind, start = pos, len = 1, line = cu.lexer.line, aux = 0, bits = as(u64, cu.lexer.src.bytes[pos]) }
    cu.lexer.pos = pos + 1
    cu.lexer.col = cu.lexer.col + 1
    cu.lexer.current = tok
    jump token(tok = tok)
end
block two_byte(pos: index, kind: u16)
    let tok: Token = { kind = kind, start = pos, len = 2, line = cu.lexer.line, aux = 0, bits = as(u64, cu.lexer.src.bytes[pos]) }
    cu.lexer.pos = pos + 2
    cu.lexer.col = cu.lexer.col + 2
    cu.lexer.current = tok
    jump token(tok = tok)
end
block three_byte(pos: index, kind: u16)
    let tok: Token = { kind = kind, start = pos, len = 3, line = cu.lexer.line, aux = 0, bits = as(u64, cu.lexer.src.bytes[pos]) }
    cu.lexer.pos = pos + 3
    cu.lexer.col = cu.lexer.col + 3
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
