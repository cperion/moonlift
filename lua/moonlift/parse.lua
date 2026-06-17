-- Moonlift unified lexer + Pratt parser with typed holes.
--
-- Single parsing path for all island kinds.  The lexer emits TK.hole for @{...}
-- antiquote splices; the parser creates typed MoonOpen slots from hole position.
-- No template extraction.  No text round-trip.
--
-- Architecture:
--   M.lex(src)           → token arrays + splice_map side table
--   new_parser()         → Pratt parser over token arrays
--   M.parse(kind, src)   → dispatch by island kind
--   M.Define(T)          → public API

local byte = string.byte
local sub  = string.sub
local find = string.find
local pvm  = require("moonlift.pvm")

local M = {}

---------------------------------------------------------------------------
-- Token kinds (numeric, span-based)
---------------------------------------------------------------------------

local TK = {
    eof = 0, name = 1, int = 2, float = 3, string = 4, nl = 5,
    hole = 6,   -- @{lua_expr} → TK.hole with splice id
    invalid = 7, -- unknown/invalid source character
    lparen = 10, rparen = 11, lbrack = 12, rbrack = 13, lbrace = 14, rbrace = 15,
    comma = 16, colon = 17, dot = 18, semi = 19,
    plus = 20, minus = 21, star = 22, slash = 23, percent = 24, eq = 25, arrow = 26,
    eqeq = 27, ne = 28, lt = 29, le = 30, gt = 31, ge = 32,
    amp = 33, pipe = 34, caret = 35, tilde = 36,
    shl = 37, lshr = 38, ashr = 39,
    -- keyword tokens (> 99 so they never collide with ASCII char checks)
    func_kw    = 102,
    type_kw    = 106,
    let_kw     = 110, var_kw     = 111, if_kw      = 112, then_kw    = 113,
    elseif_kw  = 114, else_kw    = 115, switch_kw  = 116, case_kw    = 117,
    default_kw = 118, do_kw      = 119, end_kw     = 120,
    block_kw   = 130, jump_kw    = 132, yield_kw   = 133,
    return_kw  = 134, region_kw  = 135, entry_kw   = 136, emit_kw    = 137,
    expr_kw    = 138, call_kw    = 139,
    true_kw    = 140, false_kw   = 141, nil_kw     = 142, and_kw     = 143,
    or_kw      = 144, not_kw     = 145,
    view_kw    = 150, noalias_kw = 151, readonly_kw= 152, writeonly_kw=153,
    requires_kw= 154, bounds_kw  = 155, disjoint_kw= 156, len_kw     = 157,
    same_len_kw= 158, window_bounds_kw = 159, noescape_kw = 169,
    invalidate_kw = 168, preserve_kw = 171,
    sizeof_kw  = 160,
    alignof_kw = 161,
    null_kw    = 162,
    is_null_kw = 163,
    trap_kw    = 164,
    lease_kw   = 165,
    handle_kw  = 166,
    invalid_kw = 167,
    as_kw      = 170,
    struct_kw  = 180,
    union_kw   = 181,
    extern_kw  = 182,
}

local keywords = {
    ["func"]     = TK.func_kw,
    ["type"]     = TK.type_kw,
    ["let"]      = TK.let_kw,      ["var"]      = TK.var_kw,
    ["if"]       = TK.if_kw,       ["then"]     = TK.then_kw,
    ["elseif"]   = TK.elseif_kw,   ["else"]     = TK.else_kw,
    ["switch"]   = TK.switch_kw,   ["case"]     = TK.case_kw,
    ["default"]  = TK.default_kw,  ["do"]       = TK.do_kw,
    ["end"]      = TK.end_kw,
    ["block"]    = TK.block_kw,
    ["jump"]     = TK.jump_kw,     ["yield"]    = TK.yield_kw,
    ["return"]   = TK.return_kw,   ["region"]   = TK.region_kw,
    ["entry"]    = TK.entry_kw,    ["emit"]     = TK.emit_kw,
    ["expr"]     = TK.expr_kw,     ["call"]     = TK.call_kw,
    ["true"]     = TK.true_kw,     ["false"]    = TK.false_kw,
    ["nil"]      = TK.nil_kw,      ["and"]      = TK.and_kw,
    ["or"]       = TK.or_kw,       ["not"]      = TK.not_kw,
    ["view"]     = TK.view_kw,     ["noalias"]  = TK.noalias_kw,
    ["readonly"] = TK.readonly_kw, ["writeonly"]= TK.writeonly_kw,
    ["noescape"] = TK.noescape_kw, ["invalidate"] = TK.invalidate_kw,
    ["preserve"] = TK.preserve_kw,
    ["requires"] = TK.requires_kw, ["bounds"]   = TK.bounds_kw,
    ["disjoint"] = TK.disjoint_kw, ["len"]      = TK.len_kw,
    ["same_len"] = TK.same_len_kw, ["window_bounds"] = TK.window_bounds_kw,
    ["sizeof"]     = TK.sizeof_kw,
    ["alignof"]    = TK.alignof_kw,
    ["null"]       = TK.null_kw,
    ["is_null"]    = TK.is_null_kw,
    ["trap"]       = TK.trap_kw,
    ["lease"]      = TK.lease_kw,
    ["handle"]     = TK.handle_kw,
    ["invalid"]    = TK.invalid_kw,
    ["as"]       = TK.as_kw,
    ["struct"]   = TK.struct_kw,
    ["union"]    = TK.union_kw,
    ["extern"]   = TK.extern_kw,
}

local token_label = {
    [TK.eof] = "end of input",
    [TK.name] = "identifier",
    [TK.int] = "integer literal",
    [TK.float] = "number literal",
    [TK.string] = "string literal",
    [TK.nl] = "newline",
    [TK.hole] = "splice @{...}",
    [TK.invalid] = "invalid token",
    [TK.lparen] = "'('",
    [TK.rparen] = "')'",
    [TK.lbrack] = "'['",
    [TK.rbrack] = "']'",
    [TK.lbrace] = "'{'",
    [TK.rbrace] = "'}'",
    [TK.comma] = "','",
    [TK.colon] = "':'",
    [TK.dot] = "'.'",
    [TK.semi] = "';'",
    [TK.plus] = "'+'",
    [TK.minus] = "'-'",
    [TK.star] = "'*'",
    [TK.slash] = "'/'",
    [TK.percent] = "'%'",
    [TK.eq] = "'='",
    [TK.arrow] = "'->'",
    [TK.eqeq] = "'=='",
    [TK.ne] = "'~='",
    [TK.lt] = "'<'",
    [TK.le] = "'<='",
    [TK.gt] = "'>'",
    [TK.ge] = "'>='",
    [TK.amp] = "'&'",
    [TK.pipe] = "'|'",
    [TK.caret] = "'^'",
    [TK.tilde] = "'~'",
    [TK.shl] = "'<<'",
    [TK.lshr] = "'>>>'",
    [TK.ashr] = "'>>'",
}

for kw, k in pairs(keywords) do
    token_label[k] = "'" .. kw .. "'"
end

-- Character classification (byte comparisons, no tables in hot path)
local function is_alpha(c) return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 end
local function is_digit(c) return c >= 48 and c <= 57 end
local function is_alnum(c) return is_alpha(c) or is_digit(c) end
local function is_space(c) return c == 32 or c == 9 or c == 13 end
local function is_hex(c) return is_digit(c) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102) end

---------------------------------------------------------------------------
-- Lexer
---------------------------------------------------------------------------

-- Create empty token arrays
local function new_tokens(src)
    return {
        src = src,
        n = 0,
        kind = {}, text = {}, start = {}, stop = {}, line = {}, col = {},
        splice_map = {},   -- splice_id → lua_expression_text
        splice_spread = {}, -- splice_id → true when written @{expr...}
        splice_i = 0,
        lex_issues = {},
    }
end

local function push_lex_issue(t, msg, offset, line, col)
    t.lex_issues[#t.lex_issues + 1] = { message = msg, offset = offset or 0, line = line or 0, col = col or 0 }
end

local function split_splice_expr(lua_expr)
    local stripped = lua_expr:match("^(.-%S)%s*%.%.%.%s*$")
    if stripped then return stripped, true end
    return lua_expr, false
end

local function advance_line_col(src, from_i, to_i, line, col)
    for pos = from_i, to_i do
        if byte(src, pos) == 10 then line = line + 1; col = 1
        else col = col + 1 end
    end
    return line, col
end

local function push_tok(t, kind, text, s, e, ln, col)
    local n = t.n + 1
    t.n = n
    t.kind[n] = kind
    t.text[n] = text
    t.start[n] = s
    t.stop[n] = e
    t.line[n] = ln
    t.col[n] = col
end

-- Scan @{...} — find matching }, returning position of closing brace
local function scan_antiquote(src, i, n)
    local depth = 1
    local j = i + 1  -- skip past '{'
    while j <= n do
        local c = byte(src, j)
        if c == 123 then        -- '{'
            depth = depth + 1
        elseif c == 125 then    -- '}'
            depth = depth - 1
            if depth == 0 then return j end
        elseif c == 34 or c == 39 then  -- string literal
            local quote = c
            j = j + 1
            while j <= n do
                local sc = byte(src, j)
                if sc == 92 then j = j + 1       -- escape
                elseif sc == quote then break end
                j = j + 1
            end
        elseif c == 45 and j < n and byte(src, j + 1) == 45 then  -- line comment
            local nl = find(src, "\n", j + 2, true)
            j = (nl or n + 1) - 1
        end
        j = j + 1
    end
    return nil
end

-- Short string literal scanning. Moonlift strings are single-line, like Lua
-- short strings; returns (next_position, closed, hit_newline).
local function scan_string(src, i, n, quote)
    i = i + 1
    while i <= n do
        local c = byte(src, i)
        if c == 92 then       -- escape next byte
            i = i + 2
        elseif c == quote then
            return i + 1, true, false
        elseif c == 10 then
            return i, false, true
        else
            i = i + 1
        end
    end
    return i, false, false
end

function M.lex(src)
    local t = new_tokens(src)
    local n = #src
    local i = 1
    local line, col = 1, 1

    while i <= n do
        local b = byte(src, i)

        -- Whitespace
        if b == 32 or b == 9 or b == 13 then
            i = i + 1; col = col + 1

        elseif b == 10 then
            push_tok(t, TK.nl, "\n", i, i, line, col)
            i = i + 1; line = line + 1; col = 1

        -- Comments
        elseif b == 45 and i < n and byte(src, i + 1) == 45 then
            if i + 3 <= n and sub(src, i, i + 3) == "--[[" then
                -- Long comment
                i = i + 4; col = col + 4
                while i < n and sub(src, i, i + 1) ~= "]]" do
                    if byte(src, i) == 10 then line = line + 1; col = 1
                    else col = col + 1 end
                    i = i + 1
                end
                if i <= n then i = i + 2; col = col + 2 end
            else
                -- Line comment
                while i <= n and byte(src, i) ~= 10 do i = i + 1; col = col + 1 end
            end

        -- Antiquote: @{lua_expr}
        elseif b == 64 and i < n and byte(src, i + 1) == 123 then  -- '@{'
            local close = scan_antiquote(src, i + 1, n)
            if not close then
                push_lex_issue(t, "unterminated splice @{...}", i, line, col)
                break
            end
            local lua_expr, is_spread = split_splice_expr(sub(src, i + 2, close - 1))
            t.splice_i = t.splice_i + 1
            local id = "splice." .. t.splice_i
            t.splice_map[id] = lua_expr
            if is_spread then t.splice_spread[id] = true end
            push_tok(t, TK.hole, id, i, close, line, col)
            line, col = advance_line_col(src, i, close, line, col)
            i = close + 1

        -- Identifiers and keywords
        elseif is_alpha(b) then
            local s = i
            i = i + 1
            while i <= n do
                local c = byte(src, i)
                if not is_alnum(c) then break end
                i = i + 1
            end
            local text = sub(src, s, i - 1)
            local kind = keywords[text] or TK.name
            push_tok(t, kind, text, s, i - 1, line, col)
            col = col + (i - s)

        -- Numbers
        elseif is_digit(b) then
            local s, is_float = i, false
            -- Hex: 0x...
            if b == 48 and i < n then
                local nb = byte(src, i + 1)
                if nb == 120 or nb == 88 then
                    i = i + 2
                    while i <= n do
                        local hc = byte(src, i)
                        if not (is_hex(hc) or hc == 95) then break end
                        i = i + 1
                    end
                    local text = sub(src, s, i - 1)
                    push_tok(t, TK.int, text, s, i - 1, line, col)
                    col = col + (i - s)
                    goto continue_lex
                end
            end
            i = i + 1
            while i <= n do
                local dc = byte(src, i)
                if not (is_digit(dc) or dc == 95) then break end
                i = i + 1
            end
            -- Float: decimal point
            if i <= n and byte(src, i) == 46 and not (i < n and byte(src, i + 1) == 46) then
                is_float = true; i = i + 1
                while i <= n do
                    local dc = byte(src, i)
                    if not (is_digit(dc) or dc == 95) then break end
                    i = i + 1
                end
            end
            -- Float: exponent
            local c = byte(src, i)
            if c == 101 or c == 69 then
                is_float = true; i = i + 1
                local sign = byte(src, i)
                if sign == 43 or sign == 45 then i = i + 1 end
                while i <= n do
                    local dc = byte(src, i)
                    if not (is_digit(dc) or dc == 95) then break end
                    i = i + 1
                end
            end
            local text = sub(src, s, i - 1)
            push_tok(t, is_float and TK.float or TK.int, text, s, i - 1, line, col)
            col = col + (i - s)

        -- String literals
        elseif b == 34 or b == 39 then  -- '"' or "'"
            local s, sl, sc = i, line, col
            local next_i, closed, hit_newline = scan_string(src, i, n, b)
            if not closed then
                push_lex_issue(t, hit_newline and "unterminated string literal before newline" or "unterminated string literal", s, sl, sc)
            end
            i = next_i
            local text = sub(src, s, math.max(s, i - 1))
            push_tok(t, TK.string, text, s, math.max(s, i - 1), sl, sc)
            line, col = advance_line_col(src, s, i - 1, sl, sc)

        -- Multi-char operators and punctuation
        else
            local ch = sub(src, i, i)

            -- Three-char
            if i + 2 <= n then
                local s3 = sub(src, i, i + 2)
                if s3 == ">>>" then push_tok(t, TK.lshr, s3, i, i + 2, line, col); i = i + 3; col = col + 3; goto continue_lex end
            end

            -- Two-char
            if i < n then
                local s2 = sub(src, i, i + 1)
                local k2 = ({ ["->"]=TK.arrow, ["=="]=TK.eqeq, ["~="]=TK.ne, ["<="]=TK.le,
                              [">="]=TK.ge, ["<<"]=TK.shl, [">>"]=TK.ashr })[s2]
                if k2 then push_tok(t, k2, s2, i, i + 1, line, col); i = i + 2; col = col + 2; goto continue_lex end
            end

            -- One-char
            local k1 = ({ ["("]=TK.lparen, [")"]=TK.rparen, ["["]=TK.lbrack, ["]"]=TK.rbrack,
                          ["{"]=TK.lbrace, ["}"]=TK.rbrace, [","]=TK.comma, [":"]=TK.colon,
                          ["."]=TK.dot, [";"]=TK.semi, ["+"]=TK.plus, ["-"]=TK.minus,
                          ["*"]=TK.star, ["/"]=TK.slash, ["%"]=TK.percent, ["="]=TK.eq,
                          ["<"]=TK.lt, [">"]=TK.gt, ["&"]=TK.amp, ["|"]=TK.pipe,
                          ["^"]=TK.caret, ["~"]=TK.tilde })[ch]
            if k1 then
                push_tok(t, k1, ch, i, i, line, col)
            else
                push_tok(t, TK.invalid, ch, i, i, line, col)
                push_lex_issue(t, "invalid character " .. string.format("%q", ch), i, line, col)
            end
            i = i + 1; col = col + 1
        end
        ::continue_lex::
    end

    push_tok(t, TK.eof, "", n + 1, n + 1, line, col)
    return t
end

---------------------------------------------------------------------------
-- Parser
---------------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function new_parser_internal(T, toks, first, limit, opts)
    opts = opts or {}
    local C, Ty, B, O, Sem, Tr, Pm =
        T.MoonCore, T.MoonType, T.MoonBind, T.MoonOpen,
        T.MoonSem, T.MoonTree, T.MoonParse
    local p = setmetatable({
        T = T, C = C, Ty = Ty, B = B, O = O,
        Sem = Sem, Tr = Tr, Pm = Pm,
        toks = toks,
        i = first or 1,
        first = first or 1,
        limit = limit or toks.n,
        issues = {},
        value_env = opts.value_env or {},
        cont_env = opts.cont_env or {},
        protocol_types = opts.protocol_types or {},
        product_types = opts.product_types or {},
        name_hint = opts.name_hint,
        splice_slots = {},
        splice_slots_by_id = {},
        region_seq = 0,
        region_scope = opts.region_scope,
        anonymous = false,
        anon_counter = 0,
    }, Parser)
    local window_start = toks.start[p.first] or 0
    local window_stop = toks.stop[p.limit] or math.huge
    if not p.region_scope then
        p.region_scope = tostring(p.first or 1) .. "_" .. tostring(window_start or 0) .. "_" .. tostring(p.limit or 0) .. "_" .. tostring(window_stop or 0)
    end
    for _, issue in ipairs(toks.lex_issues or {}) do
        local off = issue.offset or 0
        if off >= window_start and off <= window_stop then
            p.issues[#p.issues + 1] = Pm.ParseIssue(issue.message, off, issue.line, issue.col)
        end
    end
    return p
end

-- Token accessors (limit-aware)
function Parser:_idx(offset)
    local j = self.i + (offset or 0)
    if j > self.limit then return nil end
    return j
end
function Parser:kind(offset)
    local j = self:_idx(offset)
    if not j then return TK.eof end
    return self.toks.kind[j]
end
function Parser:text(offset)
    local j = self:_idx(offset)
    if not j then return "" end
    return self.toks.text[j]
end
function Parser:start(offset)
    local j = self:_idx(offset)
    if not j then return 0 end
    return self.toks.start[j]
end
function Parser:stop(offset)
    local j = self:_idx(offset)
    if not j then return 0 end
    return self.toks.stop[j]
end
function Parser:skip_nl() while self:kind() == TK.nl do self.i = self.i + 1 end end
function Parser:skip_sep() while self:kind() == TK.nl or self:kind() == TK.semi do self.i = self.i + 1 end end
function Parser:accept(k) if self:kind() == k then self.i = self.i + 1; return true end; return false end
function Parser:accept_text(k) if self:kind() == k then local t = self:text(); self.i = self.i + 1; return t end; return nil end
function Parser:accept_result_marker() return self:accept(TK.colon) or self:accept(TK.arrow) end
function Parser:expect_result_marker(msg)
    if self:accept_result_marker() then return true end
    self:issue(msg or ("expected ':' before result type, got " .. self:token_desc(0)))
    return false
end
function Parser:accept_trailing_comma_before(close_k)
    local save = self.i
    self:skip_nl()
    if self:accept(TK.comma) then
        self:skip_nl()
        if self:kind() == close_k then return true end
    end
    self.i = save
    return false
end

function Parser:token_label(k)
    return token_label[k] or ("token " .. tostring(k))
end

function Parser:token_desc(offset)
    local k = self:kind(offset)
    local txt = self:text(offset)
    local label = self:token_label(k)
    if k == TK.name and txt ~= "" then
        return label .. " '" .. txt .. "'"
    end
    if (k == TK.int or k == TK.float or k == TK.string or k == TK.invalid) and txt ~= "" then
        return label .. " " .. txt
    end
    if k == TK.eof then
        return label
    end
    return label
end

function Parser:issue(msg)
    local i = self.i
    self.issues[#self.issues + 1] = self.Pm.ParseIssue(msg, self.toks.start[i] or 0, self.toks.line[i] or 0, self.toks.col[i] or 0)
end

function Parser:expect(k, msg)
    if self:accept(k) then return true end
    local expected = self:token_label(k)
    local got = self:token_desc(0)
    self:issue(msg or ("expected " .. expected .. ", got " .. got))
    return false
end

function Parser:expect_name(msg)
    if self:kind() == TK.name or self:kind() == TK.len_kw then
        local t = self:text(); self.i = self.i + 1; return t
    end
    self:issue((msg or "expected identifier") .. ", got " .. self:token_desc(0))
    if self:kind() == TK.invalid then self.i = self.i + 1 end
    return ""
end

function Parser:expect_string(msg)
    if self:kind() == TK.string then
        local text = self:text(); self.i = self.i + 1
        local loader = loadstring or load
        local fn, err = loader("return " .. text)
        if fn then
            local ok, value = pcall(fn)
            if ok and type(value) == "string" then return value end
        end
        self:issue("invalid string literal" .. (err and (": " .. tostring(err)) or ""))
        return ""
    end
    self:issue((msg or "expected string literal") .. ", got " .. self:token_desc(0))
    if self:kind() == TK.invalid then self.i = self.i + 1 end
    return ""
end

-- Identifier keywords (can be used as field names etc.)
local ident_kw = {
    [TK.func_kw]=true,
    [TK.type_kw]=true, [TK.let_kw]=true, [TK.var_kw]=true, [TK.if_kw]=true,
    [TK.then_kw]=true, [TK.elseif_kw]=true, [TK.else_kw]=true, [TK.switch_kw]=true,
    [TK.case_kw]=true, [TK.default_kw]=true, [TK.do_kw]=true, [TK.end_kw]=true,
    [TK.block_kw]=true, [TK.jump_kw]=true, [TK.yield_kw]=true,
    [TK.return_kw]=true, [TK.region_kw]=true, [TK.entry_kw]=true, [TK.emit_kw]=true,
    [TK.expr_kw]=true, [TK.call_kw]=true, [TK.true_kw]=true, [TK.false_kw]=true, [TK.nil_kw]=true,
    [TK.and_kw]=true, [TK.or_kw]=true, [TK.not_kw]=true, [TK.view_kw]=true,
    [TK.noalias_kw]=true, [TK.readonly_kw]=true, [TK.writeonly_kw]=true,
    [TK.requires_kw]=true, [TK.bounds_kw]=true, [TK.disjoint_kw]=true,
    [TK.len_kw]=true, [TK.same_len_kw]=true, [TK.window_bounds_kw]=true, [TK.as_kw]=true,
    [TK.noescape_kw]=true, [TK.invalidate_kw]=true, [TK.preserve_kw]=true,
    [TK.sizeof_kw]=true, [TK.alignof_kw]=true, [TK.null_kw]=true,
    [TK.is_null_kw]=true, [TK.trap_kw]=true, [TK.lease_kw]=true,
    [TK.handle_kw]=true, [TK.invalid_kw]=true,
    [TK.struct_kw]=true,
    [TK.union_kw]=true,
    [TK.extern_kw]=true,
}

function Parser:expect_field_name(msg)
    local k = self:kind()
    if k == TK.name or k == TK.len_kw or ident_kw[k] then
        local t = self:text(); self.i = self.i + 1; return t
    end
    self:issue((msg or "expected field name") .. ", got " .. self:token_desc(0))
    if self:kind() == TK.invalid then self.i = self.i + 1 end
    return ""
end

-- Name resolution for islands with optional name (func/region/expr).
-- Priority: explicit name > name_hint from Lua assignment > anonymous.
function Parser:name_or_hint_before_lparen(msg)
    if self:kind() == TK.lparen then
        if self.name_hint then return self.name_hint end
        -- Truly anonymous — generate a placeholder name.
        self.anonymous = true
        return "_anon_" .. tostring(self.anon_counter)
    end
    return self:expect_name(msg)
end

function Parser:name_ref_or_hint_before_lparen(msg)
    local O = self.O
    if self:kind() == TK.lparen then
        if self.name_hint then return O.NameRefText(self.name_hint) end
        self.anonymous = true
        return O.NameRefText("_anon_" .. tostring(self.anon_counter))
    end
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.NameSlot(self:splice_key("name", id), id)
        self:record_splice_slot(id, O.SlotName(slot), "name")
        return O.NameRefSlot(slot)
    end
    return O.NameRefText(self:expect_name(msg))
end

function Parser:is_stop(stops) return stops[self:kind()] == true end

---------------------------------------------------------------------------
-- Splice expression reading
---------------------------------------------------------------------------

-- For fragment references (emit/call position), read a Lua expression
-- but STOP at '(' — those parens belong to the emit arguments.
function Parser:read_splice_expr_no_parens(msg)
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        return id
    end
    local start_i = self.i
    local name = self:expect_name(msg)
    -- Only consume dot chains, not () or [] — those are emit-level syntax.
    while self:kind() == TK.dot do
        self.i = self.i + 1
        self:expect_name("expected field name after '.'")
    end
    return name
end

-- Read a Lua expression (any expression valid in type position)
-- and return the expression text.  Handles bare names, table.field chains,
-- function calls, indexing, and @{...} holes.
-- Note: in fragment ref positions, use read_splice_expr_no_parens instead
-- because () and [] belong to the emit/call argument syntax.
function Parser:read_splice_expr(msg)
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        return id
    end
    local start_i = self.i
    local name = self:expect_name(msg)
    -- Consume postfix chains: .field, (args), [idx]
    while true do
        local k = self:kind()
        if k == TK.dot then
            self.i = self.i + 1
            self:expect_name("expected field name after '.'")
        elseif k == TK.lparen then
            self.i = self.i + 1; self:skip_nl()
            local depth = 1
            while depth > 0 and self:kind() ~= TK.eof do
                if self:kind() == TK.lparen then depth = depth + 1
                elseif self:kind() == TK.rparen then depth = depth - 1 end
                if depth > 0 then self.i = self.i + 1; self:skip_nl() end
            end
            if self:kind() == TK.rparen then self.i = self.i + 1 end
        elseif k == TK.lbrack then
            self.i = self.i + 1; self:skip_nl()
            local depth = 1
            while depth > 0 and self:kind() ~= TK.eof do
                if self:kind() == TK.lbrack then depth = depth + 1
                elseif self:kind() == TK.rbrack then depth = depth - 1 end
                if depth > 0 then self.i = self.i + 1; self:skip_nl() end
            end
            if self:kind() == TK.rbrack then self.i = self.i + 1 end
        else
            break
        end
    end
    local stop_i = self.i - 1
    -- Reconstruct expression text from token byte positions.
    if start_i <= stop_i then
        local src = self.toks.src
        local s = self.toks.start[start_i]
        local e = self.toks.stop[stop_i]
        if s and e then return sub(src, s, e) end
    end
    return name
end

---------------------------------------------------------------------------
-- Splice slot support
---------------------------------------------------------------------------

function Parser:splice_key(role, id)
    return "splice:" .. role .. ":" .. tostring(id)
end

function Parser:record_splice_slot(splice_id, slot_sum, role)
    local key = tostring(role) .. ":" .. tostring(splice_id)
    local existing = self.splice_slots_by_id[key]
    if existing then return existing end
    local splice_text = self.toks.splice_map[splice_id] or splice_id
    local entry = { splice_id = splice_id, splice_text = splice_text, slot = slot_sum, role = role, spread = self.toks.splice_spread[splice_id] or false }
    self.splice_slots[#self.splice_slots + 1] = entry
    self.splice_slots_by_id[key] = entry
    return entry
end

function Parser:spread_expr_slot(role, id)
    local slot = self.O.ExprSlot(self:splice_key(role, id), id, nil)
    self:record_splice_slot(id, self.O.SlotExpr(slot), role)
    return slot
end

function Parser:spread_type_slot(role, id)
    local slot = self.O.TypeSlot(self:splice_key(role, id), id)
    self:record_splice_slot(id, self.O.SlotType(slot), role)
    return slot
end

function Parser:spread_region_slot(role, id)
    local slot = self.O.RegionSlot(self:splice_key(role, id), id)
    self:record_splice_slot(id, self.O.SlotRegion(slot), role)
    return slot
end

local function spread_sentinel(role, slot)
    return "__moonlift_spread_" .. role .. ":" .. slot.key
end

function Parser:param_from_value(v)
    local pvm = require("moonlift.pvm")
    if pvm.classof(v) == self.Ty.Param then return v end
    if type(v) == "table" and v.decl and pvm.classof(v.decl) == self.Ty.Param then return v.decl end
    return nil
end

function Parser:block_param_from_value(v)
    local pvm = require("moonlift.pvm")
    if pvm.classof(v) == self.Tr.BlockParam then return v end
    local p = self:param_from_value(v)
    if p then return self.Tr.BlockParam(p.name, p.ty) end
    return nil
end

function Parser:entry_param_from_value(v)
    local pvm = require("moonlift.pvm")
    if pvm.classof(v) == self.Tr.EntryBlockParam then return v end
    if type(v) == "table" and v.decl and pvm.classof(v.decl) == self.Tr.EntryBlockParam then return v.decl end
    return nil
end

---------------------------------------------------------------------------
-- Type parsing
---------------------------------------------------------------------------

function Parser:type_name(name)
    local O, C, Ty = self.O, self.C, self.Ty
    local m = { void=C.ScalarVoid, bool=C.ScalarBool, i8=C.ScalarI8, i16=C.ScalarI16,
        i32=C.ScalarI32, i64=C.ScalarI64, u8=C.ScalarU8, u16=C.ScalarU16,
        u32=C.ScalarU32, u64=C.ScalarU64, f32=C.ScalarF32, f64=C.ScalarF64,
        index=C.ScalarIndex, ptr=C.ScalarRawPtr }
    if m[name] then return Ty.TScalar(m[name]) end
    -- All non-scalar type names become splice slots, resolved post-parse.
    -- Same-file names (Arena) and cross-file names (M.T.Arena) take the
    -- same path: slot → fill → resolved type.
    local slot = O.TypeSlot(self:splice_key("type", name), name)
    self:record_splice_slot(name, O.SlotType(slot), "type")
    return Ty.TSlot(slot)
end

function Parser:parse_callable_type()
    local Ty = self.Ty
    self:expect(TK.lparen); self:skip_nl()
    local params = {}
    if self:kind() ~= TK.rparen then
        while true do
            if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
                local id = self:text(); self.i = self.i + 1
                params[#params + 1] = Ty.TSlot(self:spread_type_slot("type_list", id))
            else
                params[#params + 1] = self:parse_type()
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        end
    end
    self:expect(TK.rparen)
    local result = Ty.TScalar(self.C.ScalarVoid)
    if self:accept_result_marker() then self:skip_nl(); result = self:parse_type() end
    return params, result
end

function Parser:parse_handle_repr()
    local C, Ty = self.C, self.Ty
    local name = self:expect_name("expected handle representation scalar")
    local m = {
        i8=C.ScalarI8, i16=C.ScalarI16, i32=C.ScalarI32, i64=C.ScalarI64,
        u8=C.ScalarU8, u16=C.ScalarU16, u32=C.ScalarU32, u64=C.ScalarU64,
        index=C.ScalarIndex,
    }
    if not m[name] then
        self:issue("handle representation must be an integer scalar")
        return Ty.HandleReprScalar(C.ScalarU32)
    end
    return Ty.HandleReprScalar(m[name])
end

function Parser:parse_type()
    local O, Ty, C = self.O, self.Ty, self.C

    -- Hole: @{type_value}
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.TypeSlot(self:splice_key("type", id), id)
        self:record_splice_slot(id, O.SlotType(slot), "type")
        return Ty.TSlot(slot)
    end

    if self:accept(TK.lbrack) then
        self:skip_nl()
        local count = 0
        if self:kind() == TK.int then count = tonumber(self:text()) or 0; self.i = self.i + 1
        else self:issue("expected array length") end
        self:skip_nl(); self:expect(TK.rbrack)
        local elem = self:parse_type()
        return Ty.TArray(Ty.ArrayLenConst(count), elem)
    end

    if self:accept(TK.view_kw) then
        self:expect(TK.lparen); self:skip_nl(); local elem = self:parse_type(); self:skip_nl(); self:expect(TK.rparen)
        return Ty.TView(elem)
    end

    if self:accept(TK.lease_kw) then
        self:skip_nl()
        local origin = Ty.LeaseOriginUnknown
        if self:accept(TK.lparen) then
            self:skip_nl()
            origin = Ty.LeaseOriginParam(self:expect_name("expected lease origin parameter name"))
            self:skip_nl(); self:expect(TK.rparen, "expected ')' after lease origin")
            self:skip_nl()
        end
        return Ty.TLease(self:parse_type(), origin)
    end

    if self:accept(TK.handle_kw) then
        self:expect(TK.lparen); self:skip_nl()
        local ref_name = self:expect_name("expected handle type name")
        local parts = { ref_name }
        while self:accept(TK.dot) do parts[#parts + 1] = self:expect_name("expected handle type path segment") end
        self:skip_nl(); self:expect(TK.comma, "expected ',' before handle representation")
        self:skip_nl(); local repr = self:parse_handle_repr()
        self:skip_nl(); self:expect(TK.rparen)
        local path_parts = {}
        for i = 1, #parts do path_parts[i] = C.Name(parts[i]) end
        return Ty.THandle(Ty.TypeRefPath(C.Path(path_parts)), repr)
    end

    if self:accept(TK.func_kw) then
        local params, result = self:parse_callable_type()
        return Ty.TFunc(params, result)
    end

    if self:kind() == TK.name and self:text() == "closure" then
        self.i = self.i + 1
        local params, result = self:parse_callable_type()
        return Ty.TClosure(params, result)
    end

    if self:kind() == TK.name and self:text() == "ptr" and self:kind(1) == TK.lparen then
        self.i = self.i + 2  -- skip name + lparen
        self:skip_nl()
        local elem = self:parse_type()
        self:skip_nl(); self:expect(TK.rparen)
        return Ty.TPtr(elem)
    end

    local expr = self:read_splice_expr("expected type")
    return self:type_name(expr)
end

---------------------------------------------------------------------------
-- Expression parsing (Pratt)
---------------------------------------------------------------------------

local lbp = {
    [TK.or_kw]   = 10,
    [TK.and_kw]  = 20,
    [TK.eqeq]    = 30, [TK.ne]      = 30, [TK.lt]=30, [TK.le]=30, [TK.gt]=30, [TK.ge]=30,
    [TK.pipe]    = 40, [TK.caret]   = 45, [TK.amp]=50,
    [TK.shl]     = 55, [TK.lshr]    = 55, [TK.ashr]=55,
    [TK.plus]    = 60, [TK.minus]   = 60,
    [TK.star]    = 70, [TK.slash]   = 70, [TK.percent]=70,
    [TK.lparen]  = 90, [TK.lbrack]  = 90, [TK.lbrace] = 90, [TK.dot]=90,
}

function Parser:parse_expr(rbp)
    rbp = rbp or 0
    self:skip_nl()
    local left = self:nud()
    self:skip_nl()
    while rbp < (lbp[self:kind()] or 0) do
        local k = self:kind(); self.i = self.i + 1
        left = self:led(k, left)
        self:skip_nl()
    end
    return left
end

function Parser:nud()
    local C, B, Tr, O = self.C, self.B, self.Tr, self.O
    local k = self:kind()
    local text = self:text()
    self.i = self.i + 1

    -- Hole: @{expr_value}
    if k == TK.hole then
        local slot = O.ExprSlot(self:splice_key("expr", text), text, nil)
        self:record_splice_slot(text, O.SlotExpr(slot), "expr")
        return Tr.ExprSlotValue(Tr.ExprSurface, slot)
    end

    if k == TK.as_kw then
        self:expect(TK.lparen); self:skip_nl(); local ty = self:parse_type(); self:skip_nl()
        self:expect(TK.comma); local val = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, ty, val)
    end

    if k == TK.int    then return Tr.ExprLit(Tr.ExprSurface, C.LitInt(text)) end
    if k == TK.float  then return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(text)) end
    if k == TK.string then return Tr.ExprLit(Tr.ExprSurface, C.LitString(text)) end
    if k == TK.true_kw  then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(true)) end
    if k == TK.false_kw then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(false)) end
    if k == TK.nil_kw   then return Tr.ExprLit(Tr.ExprSurface, C.LitNil) end

    if k == TK.name then
        local binding = self.value_env[text]
        if binding then return Tr.ExprRef(Tr.ExprSurface, B.ValueRefBinding(binding)) end
        return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(text))
    end

    if k == TK.view_kw then
        self:expect(TK.lparen); self:skip_nl(); local data = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local len = self:parse_expr(0); self:skip_nl()
        if self:accept(TK.comma) then local stride = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
            return Tr.ExprView(Tr.ExprSurface, Tr.ViewStrided(data, self.Ty.TScalar(C.ScalarVoid), len, stride))
        end
        self:expect(TK.rparen)
        return Tr.ExprView(Tr.ExprSurface, Tr.ViewContiguous(data, self.Ty.TScalar(C.ScalarVoid), len))
    end

    if k == TK.len_kw then
        if self:kind() ~= TK.lparen then
            return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(text))
        end
        self.i = self.i + 1; local v = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ExprLen(Tr.ExprSurface, v)
    end

    if k == TK.sizeof_kw then
        self:expect(TK.lparen); self:skip_nl(); local ty = self:parse_type(); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ExprSizeOf(Tr.ExprSurface, ty)
    end
    if k == TK.alignof_kw then
        self:expect(TK.lparen); self:skip_nl(); local ty = self:parse_type(); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ExprAlignOf(Tr.ExprSurface, ty)
    end
    if k == TK.null_kw then
        self:expect(TK.lparen); self:skip_nl(); local ty = self:parse_type(); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ExprNull(Tr.ExprSurface, ty)
    end
    if k == TK.is_null_kw then
        self:expect(TK.lparen); local v = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ExprIsNull(Tr.ExprSurface, v)
    end

    if k == TK.lparen then local e = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen); return e end
    if k == TK.minus  then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNeg, self:parse_expr(80)) end
    if k == TK.not_kw then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNot, self:parse_expr(80)) end
    if k == TK.tilde  then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryBitNot, self:parse_expr(80)) end
    if k == TK.star   then return Tr.ExprDeref(Tr.ExprSurface, self:parse_expr(80)) end
    if k == TK.amp    then return Tr.ExprAddrOf(Tr.ExprSurface, self:expr_to_place(self:parse_expr(80))) end
    if k == TK.lbrace then
        -- Anonymous struct literal: { field = expr, ... }
        local left_name = nil
        local fields = {}
        self:skip_nl()
        if self:kind() ~= TK.rbrace then
            while true do
                local fname = self:expect_name("expected field name")
                self:expect(TK.eq, "expected '=' after field name")
                fields[#fields + 1] = Tr.FieldInit(fname, self:parse_expr(0), 0)
                self:skip_sep()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
                if self:kind() == TK.rbrace then break end
            end
        end
        self:expect(TK.rbrace)
        local ty = self.Ty.TScalar(self.C.ScalarVoid)
        return Tr.ExprAgg(Tr.ExprSurface, ty, fields)
    end

    if k == TK.lbrack then
        -- Array literal: [elem1, elem2, ...]
        local elems = {}
        self:skip_nl()
        if self:kind() ~= TK.rbrack then
            while true do
                elems[#elems + 1] = self:parse_expr(0)
                self:skip_nl()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
                if self:kind() == TK.rbrack then break end
            end
        end
        self:expect(TK.rbrack)
        return Tr.ExprArray(Tr.ExprSurface, self.Ty.TScalar(self.C.ScalarVoid), elems)
    end

    if k == TK.switch_kw then return self:parse_switch_expr() end
    if k == TK.emit_kw   then return self:parse_emit_expr() end
    if k == TK.block_kw  then return self:parse_control_expr_after_block() end
    if k == TK.region_kw then return self:parse_multi_control_expr() end

    if k == TK.invalid then
        self:issue("invalid token in expression: " .. text)
    else
        self:issue("expected expression, got " .. self:token_label(k))
    end
    return Tr.ExprLit(Tr.ExprSurface, C.LitInt("0"))
end

function Parser:led(k, left)
    local C, Sem, Tr, B = self.C, self.Sem, self.Tr, self.B
    local pvm = require("moonlift.pvm")

    if k == TK.lparen then
        local atomic_rmw_by_name = {
            atomic_fetch_add = C.AtomicRmwAdd,
            atomic_fetch_sub = C.AtomicRmwSub,
            atomic_fetch_and = C.AtomicRmwAnd,
            atomic_fetch_or = C.AtomicRmwOr,
            atomic_fetch_xor = C.AtomicRmwXor,
            atomic_xchg = C.AtomicRmwXchg,
        }
        local left_name = nil
        if pvm.classof(left) == Tr.ExprRef and pvm.classof(left.ref) == B.ValueRefName then left_name = left.ref.name end
        if left_name == "atomic_load" then
            self:skip_nl(); local ty = self:parse_type(); self:skip_nl(); self:expect(TK.comma)
            local addr = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
            return Tr.ExprAtomicLoad(Tr.ExprSurface, ty, addr, C.AtomicSeqCst)
        elseif atomic_rmw_by_name[left_name] ~= nil then
            self:skip_nl(); local ty = self:parse_type(); self:skip_nl(); self:expect(TK.comma)
            local addr = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
            local value = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
            return Tr.ExprAtomicRmw(Tr.ExprSurface, atomic_rmw_by_name[left_name], ty, addr, value, C.AtomicSeqCst)
        elseif left_name == "atomic_cas" then
            self:skip_nl(); local ty = self:parse_type(); self:skip_nl(); self:expect(TK.comma)
            local addr = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
            local expected = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
            local replacement = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
            return Tr.ExprAtomicCas(Tr.ExprSurface, ty, addr, expected, replacement, C.AtomicSeqCst)
        end
        local args = {}
        self:skip_nl()
        if self:kind() ~= TK.rparen then
            while true do
                if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
                    local id = self:text(); self.i = self.i + 1
                    args[#args + 1] = Tr.ExprSlotValue(Tr.ExprSurface, self:spread_expr_slot("expr_list", id))
                else
                    args[#args + 1] = self:parse_expr(0)
                end
                self:skip_nl()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
                if self:kind() == TK.rparen then break end
            end
        end
        self:expect(TK.rparen)
        if pvm.classof(left) == Tr.ExprDot and pvm.classof(left.base) == Tr.ExprRef
           and pvm.classof(left.base.ref) == B.ValueRefName then
            if left.name ~= "from_repr" then
                return Tr.ExprCtor(Tr.ExprSurface, left.base.ref.name, left.name, args)
            end
        end
        -- select(cond, a, b) special form
        if pvm.classof(left) == Tr.ExprRef and pvm.classof(left.ref) == B.ValueRefName
           and left.ref.name == "select" and #args == 3 then
            return Tr.ExprSelect(Tr.ExprSurface, args[1], args[2], args[3])
        end
        -- bitcast(T, value): explicit reinterpret cast.  `as(T, value)` is the
        -- semantic conversion form; VM value-payload code needs a guaranteed
        -- no-conversion bit reinterpret for float payloads.
        if pvm.classof(left) == Tr.ExprRef and pvm.classof(left.ref) == B.ValueRefName
           and left.ref.name == "bitcast" and #args == 2 then
            local ty_expr = args[1]
            if pvm.classof(ty_expr) ~= Tr.ExprRef or pvm.classof(ty_expr.ref) ~= B.ValueRefName then
                self:issue("bitcast first argument must be a type name")
                return Tr.ExprCall(Tr.ExprSurface, left, args)
            end
            local ty = self:type_name(ty_expr.ref.name)
            return Tr.ExprCast(Tr.ExprSurface, C.SurfaceBitcast, ty, args[2])
        end
        return Tr.ExprCall(Tr.ExprSurface, left, args)
    end

    if k == TK.lbrack then
        local idx = self:parse_expr(0); self:skip_nl(); self:expect(TK.rbrack)
        return Tr.ExprIndex(Tr.ExprSurface, Tr.IndexBaseExpr(left), idx)
    end

    if k == TK.lbrace then
        -- Struct literal: TypeName{ field = expr, ... }
        self:skip_nl()
        local left_name = nil
        if pvm.classof(left) == Tr.ExprRef and pvm.classof(left.ref) == B.ValueRefName then left_name = left.ref.name end
        local fields = {}
        if self:kind() ~= TK.rbrace then
            while true do
                local fname = self:expect_name("expected field name")
                self:expect(TK.eq, "expected '=' after field name")
                fields[#fields + 1] = Tr.FieldInit(fname, self:parse_expr(0), 0)
                self:skip_sep()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
                if self:kind() == TK.rbrace then break end
            end
        end
        self:expect(TK.rbrace)
        local ty
        if left_name then
            ty = self.Ty.TNamed(self.Ty.TypeRefPath(self.C.Path({ self.C.Name(left_name) })))
        else
            ty = self.Ty.TScalar(self.C.ScalarVoid)
        end
        return Tr.ExprAgg(Tr.ExprSurface, ty, fields)
    end

    if k == TK.dot then
        local field = self:expect_field_name("expected field name")
        return Tr.ExprDot(Tr.ExprSurface, left, field)
    end

    local bin = { [TK.plus]=C.BinAdd, [TK.minus]=C.BinSub, [TK.star]=C.BinMul,
        [TK.slash]=C.BinDiv, [TK.percent]=C.BinRem, [TK.amp]=C.BinBitAnd,
        [TK.pipe]=C.BinBitOr, [TK.caret]=C.BinBitXor,
        [TK.shl]=C.BinShl, [TK.lshr]=C.BinLShr, [TK.ashr]=C.BinAShr }
    local cmp = { [TK.eqeq]=C.CmpEq, [TK.ne]=C.CmpNe, [TK.lt]=C.CmpLt,
        [TK.le]=C.CmpLe, [TK.gt]=C.CmpGt, [TK.ge]=C.CmpGe }

    if bin[k] then return Tr.ExprBinary(Tr.ExprSurface, bin[k], left, self:parse_expr(lbp[k])) end
    if cmp[k] then return Tr.ExprCompare(Tr.ExprSurface, cmp[k], left, self:parse_expr(lbp[k])) end
    if k == TK.and_kw then return Tr.ExprLogic(Tr.ExprSurface, C.LogicAnd, left, self:parse_expr(lbp[k])) end
    if k == TK.or_kw then return Tr.ExprLogic(Tr.ExprSurface, C.LogicOr, left, self:parse_expr(lbp[k])) end

    self:issue("unknown infix operator")
    return left
end

function Parser:expr_to_place(expr)
    local Tr, B, pvm = self.Tr, self.B, require("moonlift.pvm")
    local cls = pvm.classof(expr)
    if cls == Tr.ExprRef   then return Tr.PlaceRef(Tr.PlaceSurface, expr.ref) end
    if cls == Tr.ExprDeref then return Tr.PlaceDeref(Tr.PlaceSurface, expr.value) end
    if cls == Tr.ExprDot   then return Tr.PlaceDot(Tr.PlaceSurface, self:expr_to_place(expr.base), expr.name) end
    if cls == Tr.ExprIndex then return Tr.PlaceIndex(Tr.PlaceSurface, expr.base, expr.index) end
    self:issue("assignment target is not a place")
    return Tr.PlaceRef(Tr.PlaceSurface, B.ValueRefName("<bad-place>"))
end

---------------------------------------------------------------------------
-- Statement parsing
---------------------------------------------------------------------------

local stmt_stops = { [TK.end_kw]=true, [TK.else_kw]=true, [TK.elseif_kw]=true,
    [TK.case_kw]=true, [TK.default_kw]=true, [TK.block_kw]=true }

function Parser:parse_stmt_until(stops)
    local out = {}
    self:skip_sep()
    while not self:is_stop(stops) and self:kind() ~= TK.eof do
        out[#out + 1] = self:parse_stmt()
        self:skip_sep()
    end
    return out
end

function Parser:parse_if_stmt(is_elseif)
    local Tr = self.Tr
    local cond = self:parse_expr(0)
    self:skip_nl()
    self:expect(TK.then_kw, "expected then")
    local then_body = self:parse_stmt_until({ [TK.else_kw]=true, [TK.elseif_kw]=true, [TK.end_kw]=true })
    local else_body = {}
    if self:accept(TK.elseif_kw) then
        else_body = { self:parse_if_stmt(true) }
    elseif self:accept(TK.else_kw) then
        else_body = self:parse_stmt_until({ [TK.end_kw]=true })
    end
    if not is_elseif then self:expect(TK.end_kw, "expected end") end
    return Tr.StmtIf(Tr.StmtSurface, cond, then_body, else_body)
end

function Parser:switch_key_from_expr(expr)
    local C, Sem, Tr, B, pvm = self.C, self.Sem, self.Tr, self.B, require("moonlift.pvm")
    local cls = pvm.classof(expr)
    if cls == Tr.ExprLit then
        local lit = pvm.classof(expr.value)
        if lit == C.LitInt  then return { kind = "raw", raw = expr.value.raw } end
        if lit == C.LitBool then return { kind = "raw", raw = expr.value.value and "true" or "false" } end
    end
    if cls == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefName then
        return { kind = "raw", raw = expr.ref.name }
    end
    return { kind = "expr", expr = expr }
end

function Parser:parse_variant_switch_case()
    local Tr, Ty, C = self.Tr, self.Ty, self.C
    self:expect(TK.dot, "expected '.' before variant switch arm name")
    local variant_name = self:expect_field_name("expected variant name")
    local binds = {}
    if self:accept(TK.lparen) then
        self:skip_nl()
        if self:kind() ~= TK.rparen then
            while true do
                binds[#binds + 1] = Tr.VariantBind(self:expect_field_name("expected variant bind name"), Ty.TScalar(C.ScalarVoid))
                self:skip_nl()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
                if self:kind() == TK.rparen then break end
            end
        end
        self:expect(TK.rparen, "expected ')' after variant binds")
    end
    return variant_name, binds
end

function Parser:parse_switch_stmt()
    local Tr, Sem = self.Tr, self.Sem
    local value = self:parse_expr(0)
    self:skip_nl()
    self:expect(TK.do_kw, "expected do after switch expression")
    self:skip_nl()
    local arms, variant_arms = {}, {}
    while self:kind() == TK.case_kw or (self:kind() == TK.hole and self.toks.splice_spread[self:text()]) do
        if self:kind() == TK.hole then
            local id = self:text(); self.i = self.i + 1
            local slot = self:spread_region_slot("switch_stmt_arm_list", id)
            arms[#arms + 1] = Tr.SwitchStmtArm(spread_sentinel("switch_stmt_arm_list", slot), {})
        else
            self.i = self.i + 1  -- consume 'case'
            if self:kind() == TK.dot then
                local variant_name, binds = self:parse_variant_switch_case()
                self:skip_nl()
                self:expect(TK.then_kw, "expected then after variant case")
                local body = self:parse_stmt_until({ [TK.case_kw]=true, [TK.default_kw]=true, [TK.end_kw]=true })
                variant_arms[#variant_arms + 1] = Tr.SwitchVariantStmtArm(variant_name, binds, body)
            else
                local key_expr = self:parse_expr(0)
                self:skip_nl()
                self:expect(TK.then_kw, "expected then after case expression")
                local body = self:parse_stmt_until({ [TK.case_kw]=true, [TK.default_kw]=true, [TK.end_kw]=true })
                local stmt_key = self:switch_key_from_expr(key_expr)
                arms[#arms + 1] = Tr.SwitchStmtArm(stmt_key.raw or "", body)
            end
        end
        self:skip_nl()
    end
    self:expect(TK.default_kw, "expected default in switch")
    self:expect(TK.then_kw, "expected then after default")
    local default_body = self:parse_stmt_until({ [TK.end_kw]=true })
    self:expect(TK.end_kw, "expected end after switch")
    return Tr.StmtSwitch(Tr.StmtSurface, value, arms, variant_arms, default_body)
end

function Parser:parse_switch_expr()
    local Tr, Sem = self.Tr, self.Sem
    local value = self:parse_expr(0)
    self:skip_nl()
    self:expect(TK.do_kw, "expected do after switch expression")
    self:skip_nl()
    local arms, variant_arms = {}, {}
    while self:kind() == TK.case_kw or (self:kind() == TK.hole and self.toks.splice_spread[self:text()]) do
        if self:kind() == TK.hole then
            local id = self:text(); self.i = self.i + 1
            local slot = self:spread_region_slot("switch_expr_arm_list", id)
            arms[#arms + 1] = Tr.SwitchExprArm(spread_sentinel("switch_expr_arm_list", slot), {}, Tr.ExprLit(Tr.ExprSurface, self.C.LitInt("0")))
        else
            self.i = self.i + 1
            if self:kind() == TK.dot then
                local variant_name, binds = self:parse_variant_switch_case()
                self:skip_nl()
                self:expect(TK.then_kw, "expected then after variant case")
                local body, result = self:parse_expr_block({ [TK.case_kw]=true, [TK.default_kw]=true, [TK.end_kw]=true })
                variant_arms[#variant_arms + 1] = Tr.SwitchVariantExprArm(variant_name, binds, body, result)
            else
                local key_expr = self:parse_expr(0)
                self:skip_nl()
                self:expect(TK.then_kw, "expected then after case expression")
                local body, result = self:parse_expr_block({ [TK.case_kw]=true, [TK.default_kw]=true, [TK.end_kw]=true })
                local expr_key = self:switch_key_from_expr(key_expr)
                arms[#arms + 1] = Tr.SwitchExprArm(expr_key.raw or "", body, result)
            end
        end
        self:skip_nl()
    end
    self:expect(TK.default_kw, "expected default in switch")
    self:expect(TK.then_kw, "expected then after default")
    local default_body, default_expr = self:parse_expr_block({ [TK.end_kw]=true })
    self:expect(TK.end_kw, "expected end after switch")
    return Tr.ExprSwitch(Tr.ExprSurface, value, arms, variant_arms, default_body, default_expr)
end

function Parser:parse_expr_block(stops)
    local stmts = {}
    self:skip_sep()
    while not self:is_stop(stops) and self:kind() ~= TK.eof do
        stmts[#stmts + 1] = self:parse_stmt()
        self:skip_sep()
    end
    if #stmts == 0 then
        self:issue("expected expression in switch arm")
        return {}, self.Tr.ExprLit(self.Tr.ExprSurface, self.C.LitInt("0"))
    end
    local last = stmts[#stmts]
    stmts[#stmts] = nil
    local pvm = require("moonlift.pvm")
    if pvm.classof(last) ~= self.Tr.StmtExpr then
        self:issue("expected expression as last item in switch arm")
        return stmts, self.Tr.ExprLit(self.Tr.ExprSurface, self.C.LitInt("0"))
    end
    return stmts, last.expr
end

-- Block expression: block name(params = init): T body end
function Parser:parse_control_expr_after_block()
    local Tr = self.Tr
    local label = Tr.BlockLabel(self:expect_name("expected block label"))
    local params = self:parse_block_params(true)
    self:expect_result_marker("expected ':' for block expression result type")
    self:skip_nl()
    local result_ty = self:parse_type()
    local body = self:parse_stmt_until({ [TK.end_kw]=true })
    self:expect(TK.end_kw)
    return Tr.ExprControl(Tr.ExprSurface,
        Tr.ControlExprRegion(self:next_region_id(label.name), result_ty,
            Tr.EntryControlBlock(label, params, body), {}))
end

-- Multi-block region expression: region: T entry ... end block ... end end
function Parser:parse_multi_control_expr()
    local Tr = self.Tr
    self:expect_result_marker("expected ':' after region")
    self:skip_nl()
    local result_ty = self:parse_type()
    self:skip_nl()
    if not (self:accept(TK.entry_kw) or self:accept(TK.block_kw)) then self:expect(TK.entry_kw, "expected entry block") end
    local entry_label = Tr.BlockLabel(self:expect_name("expected block label"))
    local entry_params = self:parse_block_params(true)
    local entry_body = self:parse_stmt_until({ [TK.end_kw]=true, [TK.block_kw]=true })
    if self:kind() == TK.end_kw then self.i = self.i + 1 end
    local blocks = {}
    self:skip_nl()
    while self:kind() == TK.block_kw or (self:kind() == TK.hole and self.toks.splice_spread[self:text()]) do
        if self:kind() == TK.hole then
            local id = self:text(); self.i = self.i + 1
            local slot = self:spread_region_slot("control_block_list", id)
            blocks[#blocks + 1] = Tr.ControlBlock(Tr.BlockLabel(spread_sentinel("control_block_list", slot)), {}, {})
        else
            self.i = self.i + 1
            local label = Tr.BlockLabel(self:expect_name("expected block label"))
            local params = self:parse_block_params(false)
            local body = self:parse_stmt_until({ [TK.end_kw]=true })
            self:expect(TK.end_kw)
            blocks[#blocks + 1] = Tr.ControlBlock(label, params, body)
        end
        self:skip_nl()
    end
    self:expect(TK.end_kw, "expected region end")
    return Tr.ExprControl(Tr.ExprSurface,
        Tr.ControlExprRegion(self:next_region_id(entry_label.name), result_ty,
            Tr.EntryControlBlock(entry_label, entry_params, entry_body), blocks))
end

-- Control statement: block name(params = init) body end
function Parser:parse_stmt_control_after_block()
    local Tr = self.Tr
    local label = Tr.BlockLabel(self:expect_name("expected block label"))
    local params = self:parse_block_params(true)
    local body = self:parse_stmt_until({ [TK.end_kw]=true })
    self:expect(TK.end_kw)
    return Tr.StmtControl(Tr.StmtSurface,
        Tr.ControlStmtRegion(self:next_region_id(label.name),
            Tr.EntryControlBlock(label, params, body), {}))
end

function Parser:parse_block_params(entry)
    local Tr = self.Tr
    local params = {}
    self:expect(TK.lparen); self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            self:skip_nl()
            if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
                local id = self:text(); self.i = self.i + 1
                local role = entry and "entry_param_list" or "block_param_list"
                local slot = self:spread_region_slot(role, id)
                if entry then
                    params[#params + 1] = Tr.EntryBlockParam(spread_sentinel(role, slot), self.Ty.TScalar(self.C.ScalarVoid), Tr.ExprLit(Tr.ExprSurface, self.C.LitInt("0")))
                else
                    params[#params + 1] = Tr.BlockParam(spread_sentinel(role, slot), self.Ty.TScalar(self.C.ScalarVoid))
                end
            else
                local name = self:expect_name("expected block parameter")
                self:expect(TK.colon)
                local ty = self:parse_type()
                if entry then
                    self:skip_nl()
                    self:expect(TK.eq, "entry block params need initializers")
                    params[#params + 1] = Tr.EntryBlockParam(name, ty, self:parse_expr(0))
                else
                    params[#params + 1] = Tr.BlockParam(name, ty)
                end
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        end
    end
    self:expect(TK.rparen)
    return params
end

function Parser:parse_jump_args()
    local Tr = self.Tr
    local args = {}
    if self:kind() ~= TK.lparen then return args end
    self.i = self.i + 1; self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            self:skip_nl()
            local name = self:expect_name("expected jump arg name")
            self:expect(TK.eq, "expected '=' in jump arg")
            args[#args + 1] = Tr.JumpArg(name, self:parse_expr(0))
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        end
    end
    self:expect(TK.rparen)
    return args
end

-- Region fragment reference (for emit/call).
-- Every name creates a splice slot resolved through bindings.
function Parser:parse_region_frag_ref(keyword)
    local O = self.O
    local name
    if self:kind() == TK.hole then
        name = self:text(); self.i = self.i + 1
    else
        name = self:expect_name("expected region fragment name after " .. (keyword or "emit/call"))
    end
    local slot = O.RegionFragSlot(self:splice_key("region_frag", name), name)
    self:record_splice_slot(name, O.SlotRegionFrag(slot), "region_frag")
    return O.RegionFragRefSlot(slot), name
end

function Parser:parse_expr_frag_ref()
    local O = self.O
    local name
    if self:kind() == TK.hole then
        name = self:text(); self.i = self.i + 1
    else
        name = self:expect_name("expected expression fragment name after emit")
    end
    local slot = O.ExprFragSlot(self:splice_key("expr_frag", name), name)
    self:record_splice_slot(name, O.SlotExprFrag(slot), "expr_frag")
    return O.ExprFragRefSlot(slot), name
end

function Parser:parse_region_use_stmt(mode, keyword)
    local Tr, O = self.Tr, self.O
    local frag_ref, use_suffix = self:parse_region_frag_ref(keyword)
    local frag_name_str = type(use_suffix) == "string" and use_suffix or tostring(use_suffix)
    local args, cont_fills = {}, {}
    self:expect(TK.lparen, "expected '(' after " .. keyword .. " fragment name")
    self:skip_nl()
    if self:kind() ~= TK.rparen and self:kind() ~= TK.semi then
        while true do
            if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
                local id = self:text(); self.i = self.i + 1
                args[#args + 1] = Tr.ExprSlotValue(Tr.ExprSurface, self:spread_expr_slot("expr_list", id))
            else
                args[#args + 1] = self:parse_expr(0)
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.semi or self:kind() == TK.rparen then break end
        end
    end
    self:skip_nl()
    if self:accept(TK.semi) then
        self:skip_nl()
        while self:kind() ~= TK.rparen and self:kind() ~= TK.eof do
            local name = self:expect_name("expected continuation fill name")
            self:expect(TK.eq, "expected '=' in continuation fill")
            local label = self:expect_name("expected block label in continuation fill")
            if self.cont_env and self.cont_env[label] then
                cont_fills[#cont_fills + 1] = O.ContBinding(name, O.ContTargetSlot(self.cont_env[label]))
            else
                cont_fills[#cont_fills + 1] = O.ContBinding(name, O.ContTargetLabel(Tr.BlockLabel(label)))
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
        end
    end
    self:expect(TK.rparen, "expected ')' after " .. keyword)
    return Tr.StmtUseRegionFrag(Tr.StmtSurface, mode,
        keyword .. "." .. frag_name_str .. "." .. tostring(self.i), frag_ref, args, {}, cont_fills)
end

function Parser:parse_emit_stmt()
    return self:parse_region_use_stmt(self.Tr.RegionUseEmit, "emit")
end

function Parser:parse_call_stmt()
    return self:parse_region_use_stmt(self.Tr.RegionUseCall, "call")
end

function Parser:parse_emit_expr()
    local Tr = self.Tr
    local frag_ref, use_suffix = self:parse_expr_frag_ref()
    local frag_name = type(use_suffix) == "string" and use_suffix or tostring(use_suffix)
    local args = {}
    self:expect(TK.lparen, "expected '(' in emit expr")
    self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
                local id = self:text(); self.i = self.i + 1
                args[#args + 1] = Tr.ExprSlotValue(Tr.ExprSurface, self:spread_expr_slot("expr_list", id))
            else
                args[#args + 1] = self:parse_expr(0)
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        end
    end
    self:expect(TK.rparen)
    return Tr.ExprUseExprFrag(Tr.ExprSurface, "emit.expr." .. frag_name .. "." .. tostring(self.i), frag_ref, args, {})
end

function Parser:next_region_id(prefix)
    self.region_seq = self.region_seq + 1
    return "control." .. tostring(self.region_scope or "document") .. "." .. prefix .. "." .. tostring(self.region_seq)
end

function Parser:parse_atomic_stmt_if_present()
    local Tr, C = self.Tr, self.C
    if self:kind() ~= TK.name then return nil end
    local name = self:text()
    if name == "atomic_store" then
        self.i = self.i + 1
        self:expect(TK.lparen, "expected '(' after atomic_store")
        self:skip_nl(); local ty = self:parse_type(); self:skip_nl(); self:expect(TK.comma)
        local addr = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local value = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
        return Tr.StmtAtomicStore(Tr.StmtSurface, ty, addr, value, C.AtomicSeqCst)
    elseif name == "atomic_fence" then
        self.i = self.i + 1
        self:expect(TK.lparen, "expected '(' after atomic_fence")
        self:skip_nl(); self:expect(TK.rparen)
        return Tr.StmtAtomicFence(Tr.StmtSurface, C.AtomicSeqCst)
    end
    return nil
end

function Parser:parse_stmt()
    local Tr, B, C = self.Tr, self.B, self.C
    self:skip_nl()

    local atomic_stmt = self:parse_atomic_stmt_if_present()
    if atomic_stmt ~= nil then return atomic_stmt end

    -- Hole: @{stmt_source} in statement position (region body splice).
    -- Unless followed by '(' — that's an expression call, fall through.
    if self:kind() == TK.hole and self:kind(1) ~= TK.lparen then
        local id = self:text(); self.i = self.i + 1
        local slot = self.O.RegionSlot(self:splice_key("region_body", id), id)
        self:record_splice_slot(id, self.O.SlotRegion(slot), "region_body")
        return Tr.StmtUseRegionSlot(Tr.StmtSurface, slot)
    end

    if self:accept(TK.emit_kw) then return self:parse_emit_stmt() end
    if self:accept(TK.call_kw) then return self:parse_call_stmt() end

    if self:accept(TK.let_kw) or self:accept(TK.var_kw) then
        local is_var = self.toks.kind[self.i - 1] == TK.var_kw
        local name = self:expect_name()
        local ty
        if self:kind() == TK.colon then
            self.i = self.i + 1; ty = self:parse_type()
        else
            ty = self.Ty.TScalar(self.C.ScalarVoid)  -- sentinel: infer
        end
        self:skip_nl()
        self:expect(TK.eq)
        local init = self:parse_expr(0)
        local binding = B.Binding(C.Id("local:" .. name), name, ty,
            is_var and B.BindingClassLocalCell or B.BindingClassLocalValue)
        return is_var and Tr.StmtVar(Tr.StmtSurface, binding, init)
                       or Tr.StmtLet(Tr.StmtSurface, binding, init)
    end

    if self:accept(TK.if_kw) then return self:parse_if_stmt() end
    if self:accept(TK.switch_kw) then return self:parse_switch_stmt() end

    if self:accept(TK.return_kw) then
        if self:kind() == TK.nl or self:kind() == TK.end_kw then return Tr.StmtReturnVoid(Tr.StmtSurface) end
        return Tr.StmtReturnValue(Tr.StmtSurface, self:parse_expr(0))
    end
    if self:accept(TK.yield_kw) then
        if self:kind() == TK.nl or self:kind() == TK.end_kw then return Tr.StmtYieldVoid(Tr.StmtSurface) end
        return Tr.StmtYieldValue(Tr.StmtSurface, self:parse_expr(0))
    end

    if self:accept(TK.jump_kw) then
        local name = self:expect_name()
        local args = self:parse_jump_args()
        if self.cont_env and self.cont_env[name] then
            return Tr.StmtJumpCont(Tr.StmtSurface, self.cont_env[name], args)
        end
        return Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(name), args)
    end

    if self:accept(TK.block_kw) then return self:parse_stmt_control_after_block() end

    if self:accept(TK.trap_kw) then
        return Tr.StmtTrap(Tr.StmtSurface)
    end

    -- Expression or assignment
    local e = self:parse_expr(0)
    if self:accept(TK.eq) then
        return Tr.StmtSet(Tr.StmtSurface, self:expr_to_place(e), self:parse_expr(0))
    end
    return Tr.StmtExpr(Tr.StmtSurface, e)
end

---------------------------------------------------------------------------
-- Contracts
---------------------------------------------------------------------------

function Parser:parse_contract()
    local Tr = self.Tr
    self:expect(TK.requires_kw, "expected requires")
    if self:accept(TK.bounds_kw) then
        self:expect(TK.lparen); self:skip_nl(); local base = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local len = self:parse_expr(0); self:accept_trailing_comma_before(TK.rparen); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ContractBounds(base, len)
    elseif self:accept(TK.window_bounds_kw) then
        self:expect(TK.lparen); self:skip_nl(); local base = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local base_len = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local start = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local len = self:parse_expr(0); self:accept_trailing_comma_before(TK.rparen); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ContractWindowBounds(base, base_len, start, len)
    elseif self:accept(TK.disjoint_kw) then
        self:expect(TK.lparen); self:skip_nl(); local a = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local b = self:parse_expr(0); self:accept_trailing_comma_before(TK.rparen); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ContractDisjoint(a, b)
    elseif self:accept(TK.same_len_kw) then
        self:expect(TK.lparen); self:skip_nl(); local a = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local b = self:parse_expr(0); self:accept_trailing_comma_before(TK.rparen); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ContractSameLen(a, b)
    elseif self:accept(TK.noalias_kw) then
        self:expect(TK.lparen); self:skip_nl(); local base = self:parse_expr(0); self:accept_trailing_comma_before(TK.rparen); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ContractNoAlias(base)
    elseif self:accept(TK.readonly_kw) then
        self:expect(TK.lparen); self:skip_nl(); local base = self:parse_expr(0); self:accept_trailing_comma_before(TK.rparen); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ContractReadonly(base)
    elseif self:accept(TK.writeonly_kw) then
        self:expect(TK.lparen); self:skip_nl(); local base = self:parse_expr(0); self:accept_trailing_comma_before(TK.rparen); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ContractWriteonly(base)
    end
    self:issue("expected contract predicate")
    return Tr.ContractNoAlias(Tr.ExprRef(Tr.ExprSurface, self.B.ValueRefName("<bad-contract>")))
end

---------------------------------------------------------------------------
-- Parameter parsing
---------------------------------------------------------------------------

function Parser:parse_param_list()
    local Ty, Tr, B = self.Ty, self.Tr, self.B
    local params, contracts = {}, {}
    local function append_product_params(product_name)
        local fields = self.product_types[product_name]
        if not fields then return false end
        for i = 1, #fields do
            local f = fields[i]
            params[#params + 1] = Ty.Param(f.field_name, f.ty)
        end
        return true
    end
    self:skip_nl()
    if self:kind() == TK.rparen then return params, contracts end
    while true do
        self:skip_nl()
        if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
            local id = self:text(); self.i = self.i + 1
            local slot = self:spread_region_slot("param_list", id)
            params[#params + 1] = Ty.Param(spread_sentinel("param_list", slot), Ty.TScalar(self.C.ScalarVoid))
        else
            local mods = {}
            while self:kind() == TK.noalias_kw or self:kind() == TK.readonly_kw or self:kind() == TK.writeonly_kw or self:kind() == TK.noescape_kw or self:kind() == TK.invalidate_kw or self:kind() == TK.preserve_kw do
                mods[#mods + 1] = self:kind(); self.i = self.i + 1
            end
            local name = self:expect_name("expected parameter name")
            if self:kind() ~= TK.colon and #mods == 0 and append_product_params(name) then
                -- Product type in product-list position: expand its fields as params.
            else
                self:expect(TK.colon, "expected ':' in parameter")
                local ty = self:parse_type()
                for i = 1, #mods do
                    if mods[i] == TK.noescape_kw then ty = Ty.TLease(ty, Ty.LeaseOriginUnknown) end
                end
                params[#params + 1] = Ty.Param(name, ty)
                -- Convert modifiers to contracts
                local ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
                for i = 1, #mods do
                    if mods[i] == TK.noalias_kw then contracts[#contracts + 1] = Tr.ContractNoAlias(ref)
                    elseif mods[i] == TK.readonly_kw then contracts[#contracts + 1] = Tr.ContractReadonly(ref)
                    elseif mods[i] == TK.writeonly_kw then contracts[#contracts + 1] = Tr.ContractWriteonly(ref)
                    elseif mods[i] == TK.invalidate_kw then contracts[#contracts + 1] = Tr.ContractInvalidate(ref)
                    elseif mods[i] == TK.preserve_kw then contracts[#contracts + 1] = Tr.ContractPreserve(ref) end
                end
            end
        end
        if not self:accept(TK.comma) then break end
        self:skip_nl()
        if self:kind() == TK.rparen then break end
    end
    return params, contracts
end

---------------------------------------------------------------------------
-- Top-level declaration parsing
---------------------------------------------------------------------------

function Parser:parse_extern()
    local Tr, Ty, C = self.Tr, self.Ty, self.C
    local name = self:name_or_hint_before_lparen("expected extern function name")
    self:expect(TK.lparen); local params, _ = self:parse_param_list(); self:expect(TK.rparen)
    local result = Ty.TScalar(C.ScalarVoid)
    if self:accept_result_marker() then self:skip_nl(); result = self:parse_type() end
    local symbol = name
    if self:accept(TK.as_kw) then
        self:skip_nl()
        symbol = self:expect_string("expected extern symbol string")
    end
    self:skip_nl()
    -- Bodyless extern — accept without `end`
    if self:kind() == TK.end_kw then
        self.i = self.i + 1
    elseif self:kind() ~= TK.eof then
        -- Fallback: try `end` if not EOF
        self:expect(TK.end_kw, "expected end after extern declaration")
    end
    return Tr.ExternFunc(name, symbol, params, result)
end

function Parser:parse_func()
    local Tr, Ty, C, O = self.Tr, self.Ty, self.C, self.O
    -- Impl from header: func @{header_ref} body ... end
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        self:skip_nl()
        local body = self:parse_stmt_until({ [TK.end_kw]=true })
        self:expect(TK.end_kw, "expected end after func impl")
        local slot = O.FuncSlot(self:splice_key("func", id), id, Ty.TScalar(C.ScalarVoid))
        self:record_splice_slot(id, O.SlotFunc(slot), "func")
        return { kind = "func_impl", body = body, slot = slot }
    end
    local name = self:name_or_hint_before_lparen("expected function name")
    if self:accept(TK.colon) then
        local method = self:expect_name("expected method name")
        name = name .. "_" .. method
    end
    self:expect(TK.lparen); local params, contracts = self:parse_param_list(); self:expect(TK.rparen)
    local result = Ty.TScalar(C.ScalarVoid)
    if self:accept_result_marker() then self:skip_nl(); result = self:parse_type() end
    self:skip_nl()
    while self:kind() == TK.requires_kw do
        contracts[#contracts + 1] = self:parse_contract()
        self:skip_nl()
    end
    -- Bodyless declaration (header mode)
    if self:kind() == TK.end_kw or self:kind() == TK.eof or self:kind() == TK.nl then
        if self:kind() == TK.end_kw then self.i = self.i + 1 end
        self:skip_nl()
        return Tr.FuncDecl(name, params, result)
    end
    local body = self:parse_stmt_until({ [TK.end_kw]=true })
    self:expect(TK.end_kw, "expected end after function")
    if #contracts > 0 then
        return Tr.FuncLocalContract(name, params, result, contracts, body)
    end
    return Tr.FuncLocal(name, params, result, body)
end

-- Continuation params for region fragments
function Parser:parse_cont_params(owner_name)
    local O, Tr = self.O, self.Tr
    local cont_slots, slots = {}, {}
    local function parse_cont_payload()
        local params = {}
        self:skip_nl()
        if self:kind() ~= TK.rparen then
            while true do
                self:skip_nl()
                if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
                    local id = self:text(); self.i = self.i + 1
                    local slot = self:spread_region_slot("block_param_list", id)
                    params[#params + 1] = Tr.BlockParam(spread_sentinel("block_param_list", slot), self.Ty.TScalar(self.C.ScalarVoid))
                else
                    local pname = self:expect_name("expected continuation arg name")
                    self:expect(TK.colon)
                    params[#params + 1] = Tr.BlockParam(pname, self:parse_type())
                end
                self:skip_nl()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
                if self:kind() == TK.rparen then break end
            end
        end
        self:expect(TK.rparen)
        return params
    end
    while self:kind() ~= TK.rparen and self:kind() ~= TK.eof do
        if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
            local id = self:text(); self.i = self.i + 1
            -- Spread holes (@{expr...}) are always filled post-parse via the chain binder.
            local value = nil
            if type(value) == "table" then
                local pvm = require("moonlift.pvm")
                for j = 1, #value do
                    local raw = value[j]
                    local slot
                    if pvm.classof(raw) == O.ContSlot then
                        slot = raw
                    elseif type(raw) == "table" and raw.name then
                        local params = {}
                        local src = raw.block_params or (raw.cont and raw.cont.block_params) or raw.params or {}
                        for k = 1, #src do
                            local bp = self:block_param_from_value(src[k])
                            if bp then params[#params + 1] = bp end
                        end
                        slot = O.ContSlot("cont:" .. owner_name .. ":" .. raw.name .. ":splice:" .. tostring(j), raw.name, params)
                    end
                    if slot then
                        cont_slots[slot.pretty_name] = slot
                        slots[#slots + 1] = slot
                    end
                end
            else
                local slot = self:spread_region_slot("cont_slot_list", id)
                slots[#slots + 1] = O.ContSlot(spread_sentinel("cont_slot_list", slot), spread_sentinel("cont_slot_list", slot), {})
            end
        else
            local name = self:expect_name("expected continuation parameter name")
            local params = {}
            if self:accept(TK.colon) then
                self:issue("removed continuation syntax; use 'name(...)' or bare 'name'")
                if self:kind() == TK.name or ident_kw[self:kind()] then self.i = self.i + 1 end
                if self:accept(TK.lparen) then parse_cont_payload() end
            elseif self:accept(TK.lparen) then
                params = parse_cont_payload()
            end
            local slot = O.ContSlot("cont:" .. owner_name .. ":" .. name .. ":" .. tostring(#slots + 1), name, params)
            cont_slots[name] = slot
            slots[#slots + 1] = slot
        end
        self:skip_nl()
        if self:accept(TK.pipe) then
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        elseif self:kind() == TK.rparen or self:kind() == TK.eof then
            break
        else
            self:issue("expected '|' between continuation alternatives")
            if self:kind() == TK.comma or self:kind() == TK.semi then self.i = self.i + 1; self:skip_nl() end
        end
    end
    return cont_slots, slots
end

function Parser:protocol_name_from_type(ty)
    local pvm = require("moonlift.pvm")
    if pvm.classof(ty) == self.Ty.TNamed and pvm.classof(ty.ref) == self.Ty.TypeRefPath
       and #ty.ref.path.parts == 1 then
        return ty.ref.path.parts[1].text
    end
    return nil
end

function Parser:cont_slots_from_protocol(protocol_ty, owner_name)
    local name = self:protocol_name_from_type(protocol_ty)
    if not name then self:issue("region protocol result must be a named type"); return {}, {} end
    local variants = self.protocol_types[name]
    if not variants then self:issue("unknown region protocol type: " .. name); return {}, {} end
    local cont_slots, slots = {}, {}
    for i = 1, #variants do
        local v = variants[i]
        local params = {}
        for j = 1, #(v.fields or {}) do
            local f = v.fields[j]
            params[#params + 1] = self.Tr.BlockParam(f.field_name, f.ty)
        end
        local slot = self.O.ContSlot("cont:" .. owner_name .. ":" .. v.name .. ":" .. tostring(i), v.name, params)
        cont_slots[v.name] = slot
        slots[#slots + 1] = slot
    end
    return cont_slots, slots
end

function Parser:parse_open_params(owner_name)
    local O, B, C = self.O, self.B, self.C
    local params, param_bindings = {}, {}
    self:skip_nl()
    local function append_product_open_params(product_name)
        local fields = self.product_types[product_name]
        if not fields then return false end
        for i = 1, #fields do
            local f = fields[i]
            local param = O.OpenParam("param:" .. owner_name .. ":" .. f.field_name .. ":product:" .. product_name .. ":" .. tostring(i), f.field_name, f.ty)
            params[#params + 1] = param
            param_bindings[param.name] = B.Binding(C.Id("open-param:" .. owner_name .. ":" .. param.name), param.name, param.ty, B.BindingClassOpenParam(param))
        end
        return true
    end
    if self:kind() ~= TK.rparen and self:kind() ~= TK.semi then
        while true do
            self:skip_nl()
            if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
                local id = self:text(); self.i = self.i + 1
                -- Spread holes (@{expr...}) are always filled post-parse via the chain binder.
                local value = nil
                if type(value) == "table" then
                    for j = 1, #value do
                        local raw = value[j]
                        local param
                        local pvm = require("moonlift.pvm")
                        if pvm.classof(raw) == O.OpenParam then
                            param = raw
                        else
                            local p = self:param_from_value(raw)
                            if p then param = O.OpenParam("param:" .. owner_name .. ":" .. p.name .. ":splice:" .. tostring(j), p.name, p.ty) end
                        end
                        if param then
                            params[#params + 1] = param
                            param_bindings[param.name] = B.Binding(C.Id("open-param:" .. owner_name .. ":" .. param.name), param.name, param.ty, B.BindingClassOpenParam(param))
                        end
                    end
                else
                    local slot = self:spread_region_slot("open_param_list", id)
                    params[#params + 1] = O.OpenParam(spread_sentinel("open_param_list", slot), spread_sentinel("open_param_list", slot), self.Ty.TScalar(self.C.ScalarVoid))
                end
            else
                local pname = self:expect_name("expected parameter name")
                if self:kind() ~= TK.colon and append_product_open_params(pname) then
                    -- Product type in product-list position: expand its fields as open params.
                else
                    self:expect(TK.colon)
                    local ty = self:parse_type()
                    local param = O.OpenParam("param:" .. owner_name .. ":" .. pname .. ":" .. tostring(#params + 1), pname, ty)
                    params[#params + 1] = param
                    param_bindings[pname] = B.Binding(C.Id("open-param:" .. owner_name .. ":" .. pname), pname, ty, B.BindingClassOpenParam(param))
                end
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen or self:kind() == TK.semi then break end
        end
    end
    return params, param_bindings
end

-- Region fragment: region name(params; conts): Protocol | entry ... end [block ... end]* end
function Parser:parse_region_frag()
    local O, B, C, Tr = self.O, self.B, self.C, self.Tr
    -- Impl from header: region @{header_ref} body ... end
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        self:skip_nl()
        -- Parse body blocks (entry + named blocks) without header signature.
        local saved_value_env, saved_cont_env = self.value_env, self.cont_env
        self.value_env, self.cont_env = {}, {}
        if not (self:accept(TK.entry_kw) or self:accept(TK.block_kw)) then
            self:expect(TK.entry_kw, "expected entry block in region impl")
        end
        local entry_label = Tr.BlockLabel(self:expect_name("expected entry label"))
        local entry_params = self:parse_block_params(true)
        local body = self:parse_stmt_until({ [TK.end_kw]=true, [TK.block_kw]=true })
        if self:kind() == TK.end_kw then self.i = self.i + 1 end
        local blocks = {}
        self:skip_nl()
        while self:kind() == TK.block_kw do
            self.i = self.i + 1
            local label = Tr.BlockLabel(self:expect_name("expected fragment block label"))
            local block_params = self:parse_block_params(false)
            local block_body = self:parse_stmt_until({ [TK.end_kw]=true })
            self:expect(TK.end_kw)
            blocks[#blocks + 1] = Tr.ControlBlock(label, block_params, block_body)
            self:skip_nl()
        end
        self.value_env, self.cont_env = saved_value_env, saved_cont_env
        self:expect(TK.end_kw, "expected end after region impl")
        local slot = O.RegionSlot(self:splice_key("region", id), id)
        self:record_splice_slot(id, O.SlotRegion(slot), "region")
        return { kind = "region_impl",
            entry = Tr.EntryControlBlock(entry_label, entry_params, body),
            blocks = blocks, slot = slot }
    end
    -- Name, hole, or Lua assignment-inferred name.
    local name_ref = self:name_ref_or_hint_before_lparen("expected region fragment name")
    local pvm = require("moonlift.pvm")
    local name_key = pvm.classof(name_ref) == O.NameRefText and name_ref.text or ("__hole_" .. name_ref.slot.key)

    self:expect(TK.lparen)
    local params, param_bindings = self:parse_open_params(name_key)
    local cont_slots, slots = {}, {}
    self:skip_nl()
    if self:accept(TK.semi) then
        self:skip_nl()
        if (self:kind() == TK.name or ident_kw[self:kind()]) and self.protocol_types[self:text()] ~= nil then
            local protocol_name = self:text(); self.i = self.i + 1
            cont_slots, slots = self:cont_slots_from_protocol(self.Ty.TNamed(self.Ty.TypeRefPath(self.C.Path({ self.C.Name(protocol_name) }))), name_key)
            self:skip_nl()
        else
            cont_slots, slots = self:parse_cont_params(name_key)
        end
    end
    self:expect(TK.rparen)
    self:skip_nl()

    -- Protocol result?
    if self:accept_result_marker() then
        if #slots > 0 then self:issue("region cannot mix inline continuations with protocol result") end
        self:skip_nl()
        local protocol_ty = self:parse_type()
        cont_slots, slots = self:cont_slots_from_protocol(protocol_ty, name_key)
        self:skip_nl()
    end

    -- Bodyless declaration (header mode) — just signature, no entry/blocks
    if self:kind() == TK.end_kw or self:kind() == TK.eof or self:kind() == TK.nl then
        if self:kind() == TK.end_kw then self.i = self.i + 1 end
        self:skip_nl()
        return O.RegionFragDecl(name_ref, params, slots)
    end

    local saved_value_env, saved_cont_env = self.value_env, self.cont_env
    self.value_env, self.cont_env = param_bindings, cont_slots
    if not (self:accept(TK.entry_kw) or self:accept(TK.block_kw)) then
        self:expect(TK.entry_kw, "expected entry block in region fragment")
    end
    local entry_label = Tr.BlockLabel(self:expect_name("expected entry label"))
    local entry_params = self:parse_block_params(true)
    local body = self:parse_stmt_until({ [TK.end_kw]=true, [TK.block_kw]=true })
    if self:kind() == TK.end_kw then self.i = self.i + 1 end
    local blocks = {}
    self:skip_nl()
    while self:kind() == TK.block_kw or (self:kind() == TK.hole and self.toks.splice_spread[self:text()]) do
        if self:kind() == TK.hole then
            local id = self:text(); self.i = self.i + 1
            local slot = self:spread_region_slot("control_block_list", id)
            blocks[#blocks + 1] = Tr.ControlBlock(Tr.BlockLabel(spread_sentinel("control_block_list", slot)), {}, {})
        else
            self.i = self.i + 1
            local label = Tr.BlockLabel(self:expect_name("expected fragment block label"))
            local block_params = self:parse_block_params(false)
            local block_body = self:parse_stmt_until({ [TK.end_kw]=true })
            self:expect(TK.end_kw)
            blocks[#blocks + 1] = Tr.ControlBlock(label, block_params, block_body)
        end
        self:skip_nl()
    end
    self.value_env, self.cont_env = saved_value_env, saved_cont_env
    self:expect(TK.end_kw, "expected end after region fragment")

    return O.RegionFrag(name_ref, params, slots, O.OpenSet({}, {}, {}, {}),
        Tr.EntryControlBlock(entry_label, entry_params, body), blocks)
end

-- Expression fragment: expr name(params): T body end
function Parser:parse_expr_frag()
    local O, B, C = self.O, self.B, self.C
    local name_ref = self:name_ref_or_hint_before_lparen("expected expression fragment name")
    local pvm = require("moonlift.pvm")
    local name_key = pvm.classof(name_ref) == O.NameRefText and name_ref.text or ("__hole_" .. name_ref.slot.key)

    self:expect(TK.lparen)
    local params, param_bindings = self:parse_open_params(name_key)
    self:expect(TK.rparen)
    self:expect_result_marker("expected ':' in expression fragment")
    self:skip_nl()
    local result = self:parse_type()
    local saved_value_env = self.value_env
    self.value_env = param_bindings
    local body = self:parse_expr(0)
    self:skip_nl()
    self.value_env = saved_value_env
    self:expect(TK.end_kw, "expected end after expression fragment")
    return O.ExprFrag(name_ref, params, O.OpenSet({}, {}, {}, {}), body, result)
end

-- Type declaration islands: `struct Name ... end`, `struct ... end`,
-- `union Name ... end`, `union ... end`, `handle Name : repr [invalid n] end`.
-- Name is optional when inferred from a Lua assignment.
function Parser:parse_struct_island()
    local Tr, Ty = self.Tr, self.Ty
    local name
    local next_is_field = (self:kind() == TK.name or ident_kw[self:kind()]) and self:kind(1) == TK.colon
    if self.name_hint and (self:kind() == TK.nl or self:kind() == TK.end_kw or next_is_field) then
        name = self.name_hint
    elseif self:kind() == TK.nl or self:kind() == TK.end_kw or next_is_field then
        -- Truly anonymous struct — no name at all.
        name = "_anon_struct_" .. tostring(self.anon_counter)
        self.anonymous = true
    else
        name = self:expect_name("expected struct name")
    end
    local fields = {}
    self:skip_nl()
    while self:kind() ~= TK.end_kw and self:kind() ~= TK.eof do
        if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
            local id = self:text(); self.i = self.i + 1
            local slot = self:spread_region_slot("field_list", id)
            fields[#fields + 1] = Ty.FieldDecl(spread_sentinel("field_list", slot), Ty.TScalar(self.C.ScalarVoid))
        else
            local fname = self:expect_field_name("expected field name")
            self:expect(TK.colon, "expected ':' in field declaration")
            fields[#fields + 1] = Ty.FieldDecl(fname, self:parse_type())
        end
        self:skip_nl()
        if self:accept(TK.comma) then
            self:skip_nl()
            if self:kind() == TK.end_kw then break end
        elseif self:kind() == TK.end_kw or self:kind() == TK.eof then
            break
        else
            self:issue("expected ',' between struct fields")
            if self:kind() == TK.semi or self:kind() == TK.pipe then self.i = self.i + 1; self:skip_nl() end
        end
    end
    self:expect(TK.end_kw, "expected end after struct")
    self.product_types[name] = fields
    return {
        name = name,
        decl = Tr.TypeDeclStruct(name, fields),
        protocol_variants = nil,
    }
end

-- Union type island: `union Name variant | variant end`, `union variant | variant end`.
-- Name is optional when inferred from a Lua assignment.
function Parser:parse_union_island()
    local Tr, Ty = self.Tr, self.Ty
    local name
    local k1 = self:kind(1)
    local first_is_name = (self:kind() == TK.name or ident_kw[self:kind()])
    local current_starts_variant = first_is_name and (k1 == TK.pipe or k1 == TK.lparen or k1 == TK.end_kw)
    if first_is_name and k1 == TK.nl then
        local j = self.i + 1
        while self.toks.kind[j] == TK.nl do j = j + 1 end
        local kj = self.toks.kind[j]
        current_starts_variant = (kj == TK.pipe or kj == TK.end_kw)
    end
    if self.name_hint and (self:kind() == TK.nl or self:kind() == TK.end_kw or current_starts_variant) then
        name = self.name_hint
    elseif self:kind() == TK.nl or self:kind() == TK.end_kw or current_starts_variant then
        name = "_anon_union_" .. tostring(self.anon_counter)
        self.anonymous = true
    else
        name = self:expect_name("expected union name")
    end
    local variants = {}
    while self:kind() ~= TK.eof and self:kind() ~= TK.end_kw do
        self:skip_nl()
        if self:kind() == TK.hole and self.toks.splice_spread[self:text()] then
            local id = self:text(); self.i = self.i + 1
            local slot = self:spread_region_slot("variant_list", id)
            variants[#variants + 1] = Ty.VariantDecl(spread_sentinel("variant_list", slot), Ty.TScalar(self.C.ScalarVoid), {})
        else
            local vname = self:expect_field_name("expected variant name")
            local payload = Ty.TScalar(self.C.ScalarVoid)
            local fields = {}
            if self:accept(TK.lparen) then
                self:skip_nl()
                if self:kind() == TK.rparen then
                    self.i = self.i + 1
                elseif (self:kind() == TK.name or ident_kw[self:kind()]) and self:kind(1) == TK.colon then
                    while self:kind() ~= TK.rparen and self:kind() ~= TK.eof do
                        local fname = self:expect_field_name("expected variant field name")
                        self:expect(TK.colon)
                        fields[#fields + 1] = Ty.FieldDecl(fname, self:parse_type())
                        self:skip_nl()
                        if not self:accept(TK.comma) then break end
                        self:skip_nl()
                        if self:kind() == TK.rparen then break end
                    end
                    self:expect(TK.rparen)
                else
                    payload = self:parse_type()
                    self:expect(TK.rparen)
                end
            end
            variants[#variants + 1] = Ty.VariantDecl(vname, payload, fields)
        end
        self:skip_nl()
        if self:accept(TK.pipe) then
            self:skip_nl()
            if self:kind() == TK.end_kw then break end
        elseif self:kind() == TK.end_kw or self:kind() == TK.eof then
            break
        else
            self:issue("expected '|' between union variants")
            if self:kind() == TK.comma or self:kind() == TK.semi then self.i = self.i + 1; self:skip_nl() end
        end
    end
    self:expect(TK.end_kw, "expected end after union")
    self.protocol_types[name] = variants
    return {
        name = name,
        decl = Tr.TypeDeclTaggedUnionSugar(name, variants),
        protocol_variants = variants,
    }
end

function Parser:parse_handle_island()
    local Tr, Ty = self.Tr, self.Ty
    local name
    if self.name_hint and (self:kind() == TK.colon or self:kind() == TK.invalid_kw or self:kind() == TK.end_kw) then
        name = self.name_hint
    else
        name = self:expect_name("expected handle name")
    end
    self:expect_result_marker("expected ':' before handle representation")
    self:skip_nl()
    local repr = self:parse_handle_repr()
    local invalid = Ty.HandleInvalidNone
    self:skip_nl()
    if self:accept(TK.invalid_kw) then
        self:skip_nl()
        if self:kind() == TK.int then
            invalid = Ty.HandleInvalidInt(self:text())
            self.i = self.i + 1
        else
            self:issue("expected integer invalid handle value")
        end
    end
    self:skip_nl()
    self:expect(TK.end_kw, "expected end after handle")
    return {
        name = name,
        decl = Tr.TypeDeclHandle(name, repr, invalid),
        protocol_variants = nil,
    }
end

local function parse_result(kind, value, p)
    return {
        kind = kind,
        value = value,
        splice_slots = p.splice_slots,
        issues = p.issues,
        protocol_types = p.protocol_types,
        product_types = p.product_types,
    }
end

---------------------------------------------------------------------------
-- Lua-aware document scanner
---------------------------------------------------------------------------

-- Scan a Lua string until the closing quote.
local function skip_lua_short_string(src, i, quote)
    i = i + 1
    while i <= #src do
        local c = byte(src, i)
        if c == 92 then
            i = i + 1
        elseif c == quote then
            return i + 1
        elseif c == 10 then
            return i
        end
        i = i + 1
    end
    return #src + 1
end

-- Find the matching close long bracket.
local function skip_lua_long_bracket(src, start)
    local eqs = 0
    local j = start + 1
    while j <= #src and byte(src, j) == 61 do eqs = eqs + 1; j = j + 1 end
    if j > #src or byte(src, j) ~= 91 then return nil end
    local close_pat = "]" .. string.rep("=", eqs) .. "]"
    local close = find(src, close_pat, j + 1, true)
    if not close then return nil end
    return close + #close_pat
end

-- Line comment or long comment.
local function skip_lua_comment(src, i)
    if i + 3 <= #src and sub(src, i + 1, i + 3) == "[[" then
        local close = find(src, "]]", i + 4, true)
        if close then return close + 2 end
        return #src + 1
    end
    local nl = find(src, "\n", i + 1, true)
    return (nl or #src + 1) + (nl and 1 or 0)
end

local moonlift_kw = {}
for k, _ in pairs(keywords) do moonlift_kw[k] = true end

-- Tokenize a single island from the original source, appending tokens to the
-- shared token stream. Returns (first_tok, last_tok, stop_byte).
local function tokenize_island(src, island_kind, start_byte, toks)
    local first_tok = toks.n + 1
    local n = #src
    local i = start_byte
    local line, col = 1, 1
    for pos = 1, math.min(start_byte - 1, #src) do
        if byte(src, pos) == 10 then line = line + 1; col = 1 else col = col + 1 end
    end

    local end_open = {
        [TK.if_kw]=true, [TK.switch_kw]=true,
        [TK.block_kw]=true, [TK.entry_kw]=true,
        [TK.region_kw]=true, [TK.expr_kw]=true,
    }
    -- Exclude the island's own start keyword so depth tracking is correct:
    -- the initial keyword sets depth=1, and its matching `end` brings depth to 0.
    -- Remove it from end_open entirely so it doesn't count as an opener.
    local start_kw = ({ ["func"]=TK.func_kw, ["region"]=TK.region_kw, ["expr"]=TK.expr_kw,
                          ["struct"]=TK.struct_kw, ["union"]=TK.union_kw,
                          ["handle"]=TK.handle_kw,
                          ["extern"]=TK.extern_kw })[island_kind]
    if start_kw then end_open[start_kw] = nil end
    -- struct/union/extern islands only terminate at their own `end`.
    -- Field/variant/parameter names may reuse control keywords such as
    -- `block`/`yield`, so don't treat nested control keywords as island nesting.
    if island_kind == "struct" or island_kind == "union" or island_kind == "handle" or island_kind == "extern" then end_open = {} end
    local depth = 1

    while i <= n and depth > 0 do
        local b = byte(src, i)
        if b == 32 or b == 9 or b == 13 then
            i = i + 1; col = col + 1
        elseif b == 10 then
            push_tok(toks, TK.nl, "\n", i, i, line, col)
            i = i + 1; line = line + 1; col = 1
        elseif b == 45 and i < n and byte(src, i + 1) == 45 then
            if i + 3 <= n and sub(src, i, i + 3) == "--[[" then
                i = i + 4; col = col + 4
                while i < n and sub(src, i, i + 1) ~= "]]" do
                    if byte(src, i) == 10 then line = line + 1; col = 1
                    else col = col + 1 end
                    i = i + 1
                end
                if i <= n then i = i + 2; col = col + 2 end
            else
                while i <= n and byte(src, i) ~= 10 do i = i + 1; col = col + 1 end
            end
        elseif b == 64 and i < n and byte(src, i + 1) == 123 then
            local close = scan_antiquote(src, i + 1, n)
            if not close then
                push_lex_issue(toks, "unterminated splice @{...}", i, line, col)
                break
            end
            local lua_expr, is_spread = split_splice_expr(sub(src, i + 2, close - 1))
            toks.splice_i = toks.splice_i + 1
            local id = "splice." .. toks.splice_i
            toks.splice_map[id] = lua_expr
            if is_spread then toks.splice_spread[id] = true end
            push_tok(toks, TK.hole, id, i, close, line, col)
            line, col = advance_line_col(src, i, close, line, col)
            i = close + 1
        elseif is_alpha(b) then
            local s = i
            i = i + 1
            while i <= n do
                local c = byte(src, i)
                if not is_alnum(c) then break end
                i = i + 1
            end
            local text = sub(src, s, i - 1)
            local kind = keywords[text] or TK.name
            push_tok(toks, kind, text, s, i - 1, line, col)
            col = col + (i - s)
            if end_open[kind] then
                depth = depth + 1
            elseif kind == TK.end_kw then
                depth = depth - 1
                if depth == 0 then
                    return first_tok, toks.n, i - 1
                end
            end
        elseif is_digit(b) then
            local s, is_float = i, false
            if b == 48 and i < n then
                local nb = byte(src, i + 1)
                if nb == 120 or nb == 88 then
                    i = i + 2
                    while i <= n do
                        local hc = byte(src, i)
                        if not (is_hex(hc) or hc == 95) then break end
                        i = i + 1
                    end
                    push_tok(toks, TK.int, sub(src, s, i - 1), s, i - 1, line, col)
                    col = col + (i - s)
                    goto continue_tok
                end
            end
            i = i + 1
            while i <= n do
                local dc = byte(src, i)
                if not (is_digit(dc) or dc == 95) then break end
                i = i + 1
            end
            if i <= n and byte(src, i) == 46 and not (i < n and byte(src, i + 1) == 46) then
                is_float = true; i = i + 1
                while i <= n do
                    local dc = byte(src, i)
                    if not (is_digit(dc) or dc == 95) then break end
                    i = i + 1
                end
            end
            local c = byte(src, i)
            if c == 101 or c == 69 then
                is_float = true; i = i + 1
                local sign = byte(src, i); if sign == 43 or sign == 45 then i = i + 1 end
                while i <= n do
                    local dc = byte(src, i)
                    if not (is_digit(dc) or dc == 95) then break end
                    i = i + 1
                end
            end
            push_tok(toks, is_float and TK.float or TK.int, sub(src, s, i - 1), s, i - 1, line, col)
            col = col + (i - s)
        elseif b == 34 or b == 39 then
            local s, sl, sc = i, line, col
            local next_i, closed, hit_newline = scan_string(src, i, n, b)
            if not closed then
                push_lex_issue(toks, hit_newline and "unterminated string literal before newline" or "unterminated string literal", s, sl, sc)
            end
            i = next_i
            push_tok(toks, TK.string, sub(src, s, math.max(s, i - 1)), s, math.max(s, i - 1), sl, sc)
            line, col = advance_line_col(src, s, i - 1, sl, sc)
        else
            local ch = sub(src, i, i)
            if i + 2 <= n and sub(src, i, i + 2) == ">>>" then
                push_tok(toks, TK.lshr, ">>>", i, i + 2, line, col); i = i + 3; col = col + 3
                goto continue_tok
            end
            if i < n then
                local s2 = sub(src, i, i + 1)
                local k2 = ({ ["->"]=TK.arrow, ["=="]=TK.eqeq, ["~="]=TK.ne, ["<="]=TK.le,
                              [">="]=TK.ge, ["<<"]=TK.shl, [">>"]=TK.ashr })[s2]
                if k2 then push_tok(toks, k2, s2, i, i + 1, line, col); i = i + 2; col = col + 2; goto continue_tok end
            end
            local k1 = ({ ["("]=TK.lparen, [")"]=TK.rparen, ["["]=TK.lbrack, ["]"]=TK.rbrack,
                          ["{"]=TK.lbrace, ["}"]=TK.rbrace, [","]=TK.comma, [":"]=TK.colon,
                          ["."]=TK.dot, [";"]=TK.semi, ["+"]=TK.plus, ["-"]=TK.minus,
                          ["*"]=TK.star, ["/"]=TK.slash, ["%"]=TK.percent, ["="]=TK.eq,
                          ["<"]=TK.lt, [">"]=TK.gt, ["&"]=TK.amp, ["|"]=TK.pipe,
                          ["^"]=TK.caret, ["~"]=TK.tilde })[ch]
            if k1 then
                push_tok(toks, k1, ch, i, i, line, col)
            else
                push_tok(toks, TK.invalid, ch, i, i, line, col)
                push_lex_issue(toks, "invalid character " .. string.format("%q", ch), i, line, col)
            end
            i = i + 1; col = col + 1
        end
        ::continue_tok::
    end
    return first_tok, toks.n, i - 1
end

local function infer_lua_assignment_name(src, island_start)
    local p = island_start - 1
    while p >= 1 do
        local c = byte(src, p)
        if c == 32 or c == 9 or c == 13 or c == 10 then p = p - 1 else break end
    end
    if p < 1 then return nil end
    if byte(src, p) ~= 61 then return nil end
    -- Reject <= >= == ~=
    local before_eq = byte(src, p - 1)
    if before_eq == 60 or before_eq == 62 or before_eq == 61 or before_eq == 126 then return nil end
    p = p - 1
    while p >= 1 do
        local c = byte(src, p)
        if c == 32 or c == 9 or c == 13 or c == 10 then p = p - 1 else break end
    end
    -- The LHS could be a simple name, or a table.field path.
    -- Walk back to find the last identifier segment.
    local full_start = p
    local e = p
    while p >= 1 do
        local c = byte(src, p)
        if is_alpha(c) or is_digit(c) or c == 95 then p = p - 1 else break end
    end
    p = p + 1
    if p > e or not (is_alpha(byte(src, p)) or byte(src, p) == 95) then return nil end
    local name = sub(src, p, e)
    -- Build the full table path by walking further back for dots.
    local full_path = name
    local prev = p - 1
    while prev >= 1 do
        local c = byte(src, prev)
        if c == 10 then break end  -- newline: stop, path doesn't span lines
        if c == 32 or c == 9 or c == 13 then
            prev = prev - 1
        elseif c == 46 then  -- '.'
            -- Found a dot: read the preceding identifier.
            local ie = prev - 1
            local ib = ie
            while ib >= 1 do
                local dc = byte(src, ib)
                if is_alpha(dc) or is_digit(dc) or dc == 95 then ib = ib - 1 else break end
            end
            ib = ib + 1
            if ib > ie or not (is_alpha(byte(src, ib)) or byte(src, ib) == 95) then break end
            local seg = sub(src, ib, ie)
            full_path = seg .. "." .. full_path
            prev = ib - 1
        else
            break
        end
    end
    return name, full_path
end

-- Lua-aware document scanner.
function M.scan_document(src)
    local toks = new_tokens(src)
    local islands = {}
    local n = #src
    local i = 1

    local island_kind_map = {
        ["func"] = "func", ["region"] = "region", ["expr"] = "expr",
        ["struct"] = "struct", ["union"] = "union", ["handle"] = "handle", ["extern"] = "extern",
    }

    while i <= n do
        local b = byte(src, i)
        if b == 10 then
            i = i + 1
        elseif b == 32 or b == 9 or b == 13 then
            i = i + 1
        elseif b == 39 then  -- single-quoted Lua string
            i = skip_lua_short_string(src, i, 39)
        elseif b == 34 then  -- double-quoted Lua string
            i = skip_lua_short_string(src, i, 34)
        elseif b == 91 then  -- possibly long bracket
            local after = skip_lua_long_bracket(src, i)
            if after then
                i = after
            else
                -- Ordinary '[' in Lua code (indexing/table access), not a long string.
                -- Must advance to avoid scanner stalling.
                i = i + 1
            end
        elseif b == 45 and i < n and byte(src, i + 1) == 45 then
            i = skip_lua_comment(src, i)
        elseif is_alpha(b) or b == 95 then
            local s = i
            i = i + 1
            while i <= n do
                local c = byte(src, i)
                if not (is_alpha(c) or is_digit(c)) then break end
                i = i + 1
            end
            local word = sub(src, s, i - 1)
            local target_kind = island_kind_map[word]

            if target_kind then
                -- Check preceding non-whitespace, non-nl character or word
                local prev = 0
                local prev_word = nil
                for p = s - 1, 1, -1 do
                    local pc = byte(src, p)
                    if pc == 10 then
                        prev = 1; break
                    elseif pc == 32 or pc == 9 or pc == 13 then
                        -- skip horizontal whitespace
                    else
                        -- Check if this is a letter/underscore (part of a Lua keyword)
                        if is_alpha(pc) or pc == 95 then
                            local ws = p
                            while ws > 1 and (is_alpha(byte(src, ws - 1)) or is_digit(byte(src, ws - 1))) do
                                ws = ws - 1
                            end
                            prev_word = sub(src, ws, p)
                        end
                        if pc == 61 or pc == 40 or pc == 44 or pc == 123 or pc == 91 or pc == 59 then
                            prev = 1; break
                        elseif prev_word == "return" or prev_word == "end" then
                            prev = 1; break
                        else
                            prev = -1; break
                        end
                    end
                end
                if prev >= 0 then
                    local first_tok, last_tok, stop_byte = tokenize_island(src, target_kind, s, toks)
                    local holes = {}
                    for hi = first_tok, last_tok do
                        if toks.kind[hi] == TK.hole then holes[#holes + 1] = toks.text[hi] end
                    end
                    local name_hint, lhs_path = infer_lua_assignment_name(src, s)
                    islands[#islands + 1] = {
                        kind = target_kind, first_tok = first_tok, last_tok = last_tok,
                        start = s, stop = stop_byte or s, holes = holes,
                        name_hint = name_hint,
                        lhs_path = lhs_path,
                    }
                    i = (stop_byte or s) + 1
                end
            end
        else
            i = i + 1
        end
    end

    return { src = src, toks = toks, islands = islands, splice_map = toks.splice_map, splice_spread = toks.splice_spread }
end

---------------------------------------------------------------------------
-- Public parse API using token windows
---------------------------------------------------------------------------

function M.parse_island(T, scan, island_index, opts)
    opts = opts or {}
    local toks = scan.toks
    local island = scan.islands[island_index]
    if not island then error("no island at index " .. tostring(island_index), 2) end

    if opts.name_hint == nil then opts.name_hint = island.name_hint end
    local p = new_parser_internal(T, toks, island.first_tok, island.last_tok, opts)
    p:skip_sep()

    local value
    if island.kind == "func" then
        p:expect(TK.func_kw)
        value = p:parse_func()
    elseif island.kind == "region" then
        p:expect(TK.region_kw)
        value = p:parse_region_frag()
    elseif island.kind == "expr" then
        p:expect(TK.expr_kw)
        value = p:parse_expr_frag()
    elseif island.kind == "struct" then
        p:expect(TK.struct_kw)
        value = p:parse_struct_island()
    elseif island.kind == "union" then
        p:expect(TK.union_kw)
        value = p:parse_union_island()
    elseif island.kind == "handle" then
        p:expect(TK.handle_kw)
        value = p:parse_handle_island()
    elseif island.kind == "extern" then
        p:expect(TK.extern_kw)
        value = p:parse_extern()
    else
        error("unsupported island kind: " .. tostring(island.kind), 2)
    end

    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after " .. island.kind .. " island") end
    return {
        kind = island.kind,
        value = value,
        splice_slots = p.splice_slots,
        issues = p.issues,
        protocol_types = p.protocol_types,
        product_types = p.product_types,
    }
end

function M.parse_type_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    local ty = p:parse_type()
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after type") end
    return { kind = "type_expr", value = ty, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_stmt_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    local stmts = p:parse_stmt_until({})
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after statement list") end
    return { kind = "stmt_list", value = stmts, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_expr_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    local expr = p:parse_expr(0)
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after expression") end
    return { kind = "expr", value = expr, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_func_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    p:accept(TK.func_kw)  -- optional, may already be implied by moon.func
    local value = p:parse_func()
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after function") end
    -- Func impl from header returns {kind="func_impl", body, slot}
    -- The slot is already recorded in splice_slots.
    return { kind = "func", value = value, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_region_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    p:accept(TK.region_kw)  -- optional, may already be implied by moon.region
    local value = p:parse_region_frag()
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after region") end
    return { kind = "region", value = value, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_struct_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    p:accept(TK.struct_kw)  -- optional, may already be implied by moon.struct
    local value = p:parse_struct_island()
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after struct") end
    return { kind = "struct", value = value, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_union_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    p:accept(TK.union_kw)  -- optional, may already be implied by moon.union
    local value = p:parse_union_island()
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after union") end
    return { kind = "union", value = value, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_extern_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    p:accept(TK.extern_kw)  -- optional, may already be implied by moon.extern
    local value = p:parse_extern()
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after extern") end
    return { kind = "extern", value = value, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_handle_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    p:accept(TK.handle_kw)  -- optional, may already be implied by moon.handle
    local value = p:parse_handle_island()
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after handle") end
    return { kind = "handle", value = value, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_expr_frag_string(T, src, opts)
    local toks = M.lex(src)
    local p = new_parser_internal(T, toks, 1, toks.n, opts or {})
    p:skip_sep()
    p:accept(TK.expr_kw)  -- optional, may already be implied by moon.expr_frag
    local value = p:parse_expr_frag()
    p:skip_sep()
    if p:kind() ~= TK.eof then p:issue("unexpected token after expr fragment") end
    return { kind = "expr_frag", value = value, splice_slots = p.splice_slots,
             issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_module_document(T, src, opts)
    opts = opts or {}
    local pvm = require("moonlift.pvm")
    local Tr = T.MoonTree
    local Ty = T.MoonType
    local C = T.MoonCore
    local O = T.MoonOpen
    local scan = M.scan_document(src)
    local items, issues, all_slots = {}, {}, {}
    local protocol_types = opts.protocol_types or {}
    local product_types = opts.product_types or {}
    local collector = opts.collector
    for i = 1, #scan.islands do
        local parsed = M.parse_island(T, scan, i, {
            protocol_types = protocol_types,
            product_types = product_types,
        })
        for j = 1, #parsed.issues do
            local issue = parsed.issues[j]
            issues[#issues + 1] = issue
            if collector then collector:emit(issue, "parse") end
        end
        for j = 1, #parsed.splice_slots do all_slots[#all_slots + 1] = parsed.splice_slots[j] end
        protocol_types = parsed.protocol_types or protocol_types
        product_types = parsed.product_types or product_types
        if parsed.kind == "func" then
            local func = parsed.value
            local cls = pvm.classof(func)
            if cls == Tr.FuncLocal then
                func = Tr.FuncExport(func.name, func.params, func.result, func.body)
            elseif cls == Tr.FuncLocalContract then
                func = Tr.FuncExportContract(func.name, func.params, func.result, func.contracts, func.body)
            end
            items[#items + 1] = Tr.ItemFunc(func)
        elseif parsed.kind == "struct" or parsed.kind == "union" or parsed.kind == "handle" then
            items[#items + 1] = Tr.ItemType(parsed.value.decl)
        elseif parsed.kind == "extern" then
            items[#items + 1] = Tr.ItemExtern(parsed.value)
        end
    end
    local module = Tr.Module(Tr.ModuleSurface, items)
    -- Resolve intra-module TypeSlots from the module's own ItemType entries.
    local defs = {}
    for _, item in ipairs(items) do
        if pvm.classof(item) == Tr.ItemType then
            local d = item.t
            if d and d.name then
                local cls = pvm.classof(d)
                if cls == Tr.TypeDeclHandle then
                    defs[d.name] = Ty.THandle(Ty.TypeRefPath(C.Path({ C.Name(d.name) })), d.repr)
                else
                    defs[d.name] = Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(d.name) })))
                end
            end
        end
    end
    if next(defs) then
        local bindings = {}
        for _, ss in ipairs(all_slots) do
            if pvm.classof(ss.slot) == O.SlotType then
                local name = ss.splice_text or ss.splice_id
                local ty = defs[name]
                if ty then
                    bindings[#bindings + 1] = O.SlotBinding(ss.slot, O.SlotValueType(ty))
                end
            end
        end
        if #bindings > 0 then
            local open_expand = require("moonlift.open_expand")
            local e = open_expand.Define(T)
            local env = e.empty_env()
            env = e.env_with_fills(env, bindings)
            module = e.expand_module(module, env)
        end
    end
    return {
        kind = "module",
        module = module,
        scan = scan,
        issues = issues,
        protocol_types = protocol_types,
        product_types = product_types,
    }
end

function M.Define(T)
    return {
        TK = TK,
        lex = M.lex,
        scan_document = M.scan_document,
        parse_island = function(scan, island_index, opts) return M.parse_island(T, scan, island_index, opts) end,
        parse_type = function(src, opts) return M.parse_type_string(T, src, opts) end,
        parse_stmts = function(src, opts) return M.parse_stmt_string(T, src, opts) end,
        parse_expr = function(src, opts) return M.parse_expr_string(T, src, opts) end,
        parse_func = function(src, opts) return M.parse_func_string(T, src, opts) end,
        parse_region = function(src, opts) return M.parse_region_string(T, src, opts) end,
        parse_struct = function(src, opts) return M.parse_struct_string(T, src, opts) end,
        parse_union = function(src, opts) return M.parse_union_string(T, src, opts) end,
        parse_extern = function(src, opts) return M.parse_extern_string(T, src, opts) end,
        parse_handle = function(src, opts) return M.parse_handle_string(T, src, opts) end,
        parse_expr_frag = function(src, opts) return M.parse_expr_frag_string(T, src, opts) end,
        parse_module = function(src, opts) return M.parse_module_document(T, src, opts) end,
    }
end

-----------------------------------------------------------------------------
-- explain_parse_issue: explains a single ParseIssue
-----------------------------------------------------------------------------

local function explain_parse_issue(issue, analysis)
    local resolvers = require("moonlift.error.span_resolvers")
    local span = resolvers.parse_resolver(issue, analysis)
    local msg = issue.message or "unexpected token"

    -- Enrich the message with construct context if available
    local notes = {}
    local suggestions = {}

    -- Detect common Moonlift-specific parse situations
    local m = msg:match("expected '(.-)', got")
    if m then
        if m == "end" then
            notes[#notes + 1] = { message = "an open construct has not been closed" }
            notes[#notes + 1] = { message = "check that every `region`, `func`, `if`, `switch`, or `block` has a matching `end`" }
        elseif m == "then" then
            notes[#notes + 1] = { message = "`if` and `case` expressions require `then` before the body" }
            suggestions[#suggestions + 1] = { message = "add `then` after the condition" }
        elseif m == "do" then
            notes[#notes + 1] = { message = "`switch` requires `do` before the first `case`: `switch expr do case ... end`" }
            suggestions[#suggestions + 1] = { message = "add `do` after the switch expression" }
        elseif m == "'='" then
            notes[#notes + 1] = { message = "assignment and block parameter initialization require `=`" }
        elseif m == "')" then
            notes[#notes + 1] = { message = "there may be a missing comma or extra argument in this list" }
        end
    end

    -- Unterminated construct (E0102)
    if issue.construct then
        local construct = issue.construct
        local name = issue.name or ""
        return {
            code = "E0102",
            severity = "error",
            phase_context = "while parsing this file",
            primary = {
                span = span,
                message = construct .. " " .. (name ~= "" and ("`" .. name .. "` ") or "") .. "is not terminated",
            },
            notes = {
                { message = "every " .. construct .. " must be closed with `end`" },
            },
            suggestions = {
                { message = "add `end` at the end of this " .. construct },
            },
        }
    end

    -- Missing keyword (E0103)
    if issue.keyword or issue.expected then
        local keyword = issue.keyword or issue.expected or "?"
        local context = issue.context or ""
        local knotes = {}
        local ksuggestions = {}
        if keyword == "do" and context == "switch" then
            knotes[#knotes + 1] = { message = "`switch` requires `do` before the first `case`: `switch expr do case ... end`" }
            ksuggestions[#ksuggestions + 1] = { message = "write `switch ... do`" }
        elseif keyword == "then" then
            knotes[#knotes + 1] = { message = "`if` and `case` require `then` before the body" }
            ksuggestions[#ksuggestions + 1] = { message = "add `then` after the condition" }
        elseif keyword == "end" then
            knotes[#knotes + 1] = { message = "this construct must be closed with `end`" }
            ksuggestions[#ksuggestions + 1] = { message = "add `end` to close the " .. (context ~= "" and context or "construct") }
        else
            knotes[#knotes + 1] = { message = "expected `" .. keyword .. "` here" }
            ksuggestions[#ksuggestions + 1] = { message = "insert `" .. keyword .. "`" }
        end
        return {
            code = "E0103",
            severity = "error",
            phase_context = "while parsing this file",
            primary = {
                span = span,
                message = "expected `" .. keyword .. "`" .. (context ~= "" and (" in " .. context) or ""),
            },
            notes = knotes,
            suggestions = ksuggestions,
        }
    end

    -- Default: parse error (E0101)
    return {
        code = "E0101",
        severity = "error",
        phase_context = "while parsing this file",
        primary = { span = span, message = msg },
        notes = notes,
        suggestions = suggestions,
    }
end

M.explain_parse_issue = explain_parse_issue

M.TK = TK

return M
