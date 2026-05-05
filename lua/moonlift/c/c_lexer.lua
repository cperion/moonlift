-- c_lexer.lua — C99 tokenizer
-- Pure Lua module, NOT a PVM phase.
-- Entry point: M.lex(source, source_uri) → { tokens, spans, issues }

local M = {}

-- Keyword table: string → CKeyword variant name
local keywords = {
    auto = "CKwAuto",       ["break"] = "CKwBreak", case = "CKwCase",
    char = "CKwChar",       const = "CKwConst",     continue = "CKwContinue",
    ["default"] = "CKwDefault", ["do"] = "CKwDo",    double = "CKwDouble",
    ["else"] = "CKwElse",   enum = "CKwEnum",       extern = "CKwExtern",
    float = "CKwFloat",     ["for"] = "CKwFor",      ["goto"] = "CKwGoto",
    ["if"] = "CKwIf",        inline = "CKwInline",   int = "CKwInt",
    long = "CKwLong",       ["register"] = "CKwRegister", restrict = "CKwRestrict",
    ["return"] = "CKwReturn", short = "CKwShort",   signed = "CKwSigned",
    sizeof = "CKwSizeof",   static = "CKwStatic",   struct = "CKwStruct",
    switch = "CKwSwitch",   typedef = "CKwTypedef", union = "CKwUnion",
    unsigned = "CKwUnsigned", void = "CKwVoid",     volatile = "CKwVolatile",
    ["while"] = "CKwWhile",
    ["_Bool"] = "CKwBool",       ["_Complex"] = "CKwComplex",
    __inline = "CKwInline2",     __restrict = "CKwRestrict2",
}

-- Directive table: string → CDirectiveKind variant name
local directives = {
    define = "CDirDefine",  undef = "CDirUndef",
    include = "CDirInclude", ["if"] = "CDirIf",
    ifdef = "CDirIfdef",    ifndef = "CDirIfndef",
    elif = "CDirElif",      ["else"] = "CDirElse",
    endif = "CDirEndif",    ["error"] = "CDirError",
    pragma = "CDirPragma",  line = "CDirLine",
}

-- Multi-character punctuators, longest match first
local puncts = {
    "<<=", ">>=", "...",
    "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=",
    "&&", "||", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
    "##",
}

-- Single-char punctuators
local single_punct = {
    ["{"] = true, ["}"] = true, ["("] = true, [")"] = true,
    ["["] = true, ["]"] = true, [";"] = true, [":"] = true,
    [","] = true, ["."] = true, ["~"] = true, ["?"] = true,
    ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true,
    ["%"] = true, ["<"] = true, [">"] = true, ["="] = true,
    ["!"] = true, ["&"] = true, ["|"] = true, ["^"] = true,
    ["#"] = true,
}

local function is_ident_start(c)
    if not c then return false end
    return c:match("[a-zA-Z_]") ~= nil
end

local function is_ident_cont(c)
    if not c then return false end
    return c:match("[a-zA-Z0-9_]") ~= nil
end

local function is_digit(c)
    if not c then return false end
    return c:match("[0-9]") ~= nil
end

local function is_hex_digit(c)
    if not c then return false end
    return c:match("[0-9a-fA-F]") ~= nil
end

local function is_oct_digit(c)
    if not c then return false end
    return c:match("[0-7]") ~= nil
end

local function is_space(c)
    if not c then return false end
    return c == " " or c == "\t" or c == "\v" or c == "\f" or c == "\r"
end

-- Preprocess: resolve \\\n line continuations
local function resolve_continuations(source)
    return source:gsub("\\\n", "")
end

-- Build lazy line offset table
local function build_lines(source)
    local lines = { 1 }
    for i = 1, #source do
        local c = source:sub(i, i)
        if c == "\n" then
            lines[#lines + 1] = i + 1
        end
    end
    -- Trim trailing empty entries for source ending in newline
    if #source > 0 and source:sub(-1) == "\n" then
        lines[#lines] = nil
    end
    return lines
end

-- Offset → (line, col)
local function offset_to_line_col(lines, offset)
    -- Binary search for the line containing offset
    local lo, hi = 1, #lines
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if lines[mid] <= offset then
            lo = mid
        else
            hi = mid - 1
        end
    end
    if #lines == 0 then return 1, offset end
    local line_start = lines[lo]
    return lo, offset - line_start + 1
end

-- Issue helper
local function issue(message, offset, lines)
    local line, col = offset_to_line_col(lines, offset)
    return { message = message, offset = offset, line = line, col = col }
end

-- Token builder for MoonCAst types
local function TK(tokens, spans, CA, source_uri, start_byte, stop_byte)
    return function(asdl_val)
        tokens[#tokens + 1] = asdl_val
        spans[#spans + 1] = { uri = source_uri, start_offset = start_byte, stop_offset = stop_byte }
    end
end

-- Main lexer
function M.lex(source, source_uri)
    source = resolve_continuations(source)
    local lines = build_lines(source)
    local tokens = {}
    local spans = {}
    local issues = {}
    local uri = tostring(source_uri or "<source>")
    local i = 1
    local n = #source

    local function emit(token_type, start_byte, stop_byte, token_val)
        stop_byte = stop_byte or i - 1
        tokens[#tokens + 1] = token_val
        spans[#spans + 1] = { uri = uri, start_offset = start_byte, stop_offset = stop_byte }
    end

    local function read_ident(start)
        local j = start
        while j <= n and is_ident_cont(source:sub(j, j)) do
            j = j + 1
        end
        return source:sub(start, j - 1), j
    end

    local function read_digits(start)
        local j = start
        while j <= n and is_digit(source:sub(j, j)) do
            j = j + 1
        end
        return source:sub(start, j - 1), j
    end

    local function skip_block_comment(start)
        -- start is at '/', next must be '*' (caller ensured this)
        local j = start + 2
        while j < n do
            if source:sub(j, j + 1) == "*/" then
                return j + 2
            end
            j = j + 1
        end
        issues[#issues + 1] = issue("unterminated block comment", start, lines)
        return n + 1
    end

    local function read_line_comment(start)
        local j = start + 2
        while j <= n and source:sub(j, j) ~= "\n" do
            j = j + 1
        end
        return j
    end

    local function read_char_literal(start)
        local j = start + 1  -- skip opening '
        while j <= n do
            local c = source:sub(j, j)
            if c == "\\" then
                j = j + 2
            elseif c == "'" then
                return j + 1
            elseif c == "\n" then
                break
            else
                j = j + 1
            end
        end
        issues[#issues + 1] = issue("unterminated character literal", start, lines)
        return j
    end

    -- Concatenated string literals handled in parser; lexer produces individual tokens
    local function read_string_literal(start)
        local j = start + 1  -- skip opening "
        while j <= n do
            local c = source:sub(j, j)
            if c == "\\" then
                j = j + 2
            elseif c == "\"" then
                return j + 1
            elseif c == "\n" then
                break
            else
                j = j + 1
            end
        end
        issues[#issues + 1] = issue("unterminated string literal", start, lines)
        return j
    end

    local function read_prefix_string(start)
        -- Wide string L"..." or u"..." etc.
        local j = start + 1
        if j <= n and source:sub(j, j) == "\"" then
            return read_string_literal(j)
        end
        -- Just the prefix character, fall through as identifier
        return start + 1
    end

    -- Read a number literal (integer or float)
    local function read_number(start)
        local j = start
        local raw = ""
        local suffix = ""
        local is_float = false

        -- Hex prefix: 0x or 0X
        if source:sub(j, j + 1):lower() == "0x" then
            raw = source:sub(j, j + 1)
            j = j + 2
            while j <= n and is_hex_digit(source:sub(j, j)) do
                raw = raw .. source:sub(j, j)
                j = j + 1
            end
            -- Hex float: 0x...p... or 0x...P...
            if j <= n and source:sub(j, j):lower() == "." then
                is_float = true
                raw = raw .. "."
                j = j + 1
                while j <= n and is_hex_digit(source:sub(j, j)) do
                    raw = raw .. source:sub(j, j)
                    j = j + 1
                end
            end
            if j <= n and source:sub(j, j):lower() == "p" then
                is_float = true
                raw = raw .. source:sub(j, j)
                j = j + 1
                if j <= n and (source:sub(j, j) == "+" or source:sub(j, j) == "-") then
                    raw = raw .. source:sub(j, j)
                    j = j + 1
                end
                while j <= n and is_digit(source:sub(j, j)) do
                    raw = raw .. source:sub(j, j)
                    j = j + 1
                end
            end
        else
            -- Decimal or octal
            while j <= n and is_digit(source:sub(j, j)) do
                raw = raw .. source:sub(j, j)
                j = j + 1
            end
            -- Fractional part
            if j <= n and source:sub(j, j) == "." then
                is_float = true
                raw = raw .. "."
                j = j + 1
                while j <= n and is_digit(source:sub(j, j)) do
                    raw = raw .. source:sub(j, j)
                    j = j + 1
                end
            end
            -- Exponent
            if j <= n and source:sub(j, j):lower() == "e" then
                is_float = true
                raw = raw .. source:sub(j, j)
                j = j + 1
                if j <= n and (source:sub(j, j) == "+" or source:sub(j, j) == "-") then
                    raw = raw .. source:sub(j, j)
                    j = j + 1
                end
                while j <= n and is_digit(source:sub(j, j)) do
                    raw = raw .. source:sub(j, j)
                    j = j + 1
                end
            end
        end

        -- Float suffix
        if is_float then
            if j <= n and source:sub(j, j):lower() == "f" then
                suffix = source:sub(j, j)
                j = j + 1
            elseif j <= n and source:sub(j, j):lower() == "l" then
                suffix = source:sub(j, j)
                j = j + 1
            end
        else
            -- Integer suffix: u, l, ll, ul, ull, lu, llu
            if j <= n and source:sub(j, j):lower() == "u" then
                suffix = suffix .. source:sub(j, j)
                j = j + 1
            end
            if j <= n and source:sub(j, j):lower() == "l" then
                suffix = suffix .. source:sub(j, j)
                j = j + 1
                if j <= n and source:sub(j, j):lower() == "l" then
                    suffix = suffix .. source:sub(j, j)
                    j = j + 1
                end
            end
            if #suffix == 0 and j <= n and source:sub(j, j):lower() == "u" then
                suffix = suffix .. source:sub(j, j)
                j = j + 1
            end
        end

        return raw, suffix, j, is_float
    end

    -- Parse preprocessor directive after # token
    local function parse_directive(start)
        -- start is at the character after #
        local j = start
        -- skip whitespace
        while j <= n and is_space(source:sub(j, j)) do j = j + 1 end
        local ident_start = j
        local name, j = read_ident(j)
        local dir_kind = directives[name]
        if not dir_kind then
            return nil, j
        end
        return dir_kind, j
    end

    -- Main loop
    while i <= n do
        local c = source:sub(i, i)

        -- Whitespace
        if is_space(c) then
            i = i + 1
        -- Newline
        elseif c == "\n" then
            emit("newline", i, i, { _variant = "CTokNewline" })
            i = i + 1
        -- Block comment
        elseif c == "/" and i + 1 <= n and source:sub(i + 1, i + 1) == "*" then
            i = skip_block_comment(i)
        -- Line comment
        elseif c == "/" and i + 1 <= n and source:sub(i + 1, i + 1) == "/" then
            i = read_line_comment(i)
        -- Preprocessor directive (only at start of logical line)
        elseif c == "#" then
            local dir_kind, after = parse_directive(i + 1)
            if dir_kind then
                local dir_val = { _variant = "CTokDirective", kind = { _variant = dir_kind } }
                emit("directive", i, after - 1, dir_val)
                i = after
            else
                -- # is a punctuator when not a directive (e.g., in macro body)
                emit("punct", i, i, { _variant = "CTokPunct", text = "#" })
                i = i + 1
            end
        -- Character literal
        elseif c == "'" then
            local start = i
            local after = read_char_literal(start)
            local raw = source:sub(start, after - 1)
            emit("charlit", start, after - 1, { _variant = "CTokCharLiteral", raw = raw })
            i = after
        -- String literal
        elseif c == "\"" then
            local start = i
            local after = read_string_literal(start)
            local raw = source:sub(start, after - 1)
            emit("strlit", start, after - 1, { _variant = "CTokStringLiteral", raw = raw, prefix = "" })
            i = after
        -- Wide/prefix string literal
        elseif c:lower() == "l" and i + 1 <= n and source:sub(i + 1, i + 1) == "\"" then
            local start = i
            local prefix = source:sub(i, i)
            i = i + 1  -- skip prefix
            local after = read_string_literal(i)
            local raw = source:sub(i, after - 1)
            emit("strlit", start, after - 1, { _variant = "CTokStringLiteral", raw = raw, prefix = prefix })
            i = after
        -- Identifier or keyword
        elseif is_ident_start(c) then
            local start = i
            local ident, j = read_ident(i)
            local kw = keywords[ident]
            if kw then
                emit("keyword", start, j - 1, { _variant = "CTokKeyword", kw = { _variant = kw } })
            else
                emit("ident", start, j - 1, { _variant = "CTokIdent", name = ident })
            end
            i = j
        -- Number literal
        elseif is_digit(c) then
            local start = i
            local raw, suffix, j, is_float = read_number(i)
            if is_float then
                emit("floatlit", start, j - 1, { _variant = "CTokFloatLiteral", raw = raw, suffix = suffix })
            else
                emit("intlit", start, j - 1, { _variant = "CTokIntLiteral", raw = raw, suffix = suffix })
            end
            i = j
        -- Multi-character punctuators
        else
            local matched = false
            for _, p in ipairs(puncts) do
                if source:sub(i, i + #p - 1) == p then
                    emit("punct", i, i + #p - 1, { _variant = "CTokPunct", text = p })
                    i = i + #p
                    matched = true
                    break
                end
            end
            if not matched then
                -- Single character punctuator
                if single_punct[c] then
                    emit("punct", i, i, { _variant = "CTokPunct", text = c })
                    i = i + 1
                else
                    -- Unrecognized character
                    issues[#issues + 1] = issue("unrecognized character: " .. (c:byte() and ("0x" .. string.format("%02x", c:byte())) or "EOF"), i, lines)
                    i = i + 1
                end
            end
        end
    end

    -- Emit EOF token
    emit("eof", n + 1, n + 1, { _variant = "CTokEOF" })

    return {
        tokens = tokens,
        spans = spans,
        issues = issues,
    }
end

return M
