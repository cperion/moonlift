-- Moonlift unified lexer + Pratt parser with typed holes.
--
-- Single parsing path for all island kinds.  The lexer emits TK.hole for @{...}
-- antiquote splices; the parser creates typed MoonOpen slots from hole position.
-- No template extraction.  No text round-trip.
--
-- Architecture:
--   M.lex(src)           → token arrays + splice_map side table
--   parser_from_toks()   → Pratt parser over token arrays
--   parse_by_kind()      → dispatch by island kind
--   M.Define(T)          → public API

local byte = string.byte
local sub  = string.sub
local find = string.find

local M = {}

---------------------------------------------------------------------------
-- Token kinds (numeric, span-based)
---------------------------------------------------------------------------

local TK = {
    eof = 0, name = 1, int = 2, float = 3, string = 4, nl = 5,
    hole = 6,   -- @{lua_expr} → TK.hole with splice id
    lparen = 10, rparen = 11, lbrack = 12, rbrack = 13, lbrace = 14, rbrace = 15,
    comma = 16, colon = 17, dot = 18, semi = 19,
    plus = 20, minus = 21, star = 22, slash = 23, percent = 24, eq = 25, arrow = 26,
    eqeq = 27, ne = 28, lt = 29, le = 30, gt = 31, ge = 32,
    amp = 33, pipe = 34, caret = 35, tilde = 36,
    shl = 37, lshr = 38, ashr = 39,
    amp2 = 40, pipe2 = 41,
    -- keyword tokens (> 99 so they never collide with ASCII char checks)
    extern_kw  = 101, func_kw    = 102, const_kw   = 103, static_kw  = 104,
    type_kw    = 106,
    let_kw     = 110, var_kw     = 111, if_kw      = 112, then_kw    = 113,
    elseif_kw  = 114, else_kw    = 115, switch_kw  = 116, case_kw    = 117,
    default_kw = 118, do_kw      = 119, end_kw     = 120, while_kw   = 121,
    block_kw   = 130, control_kw = 131, jump_kw    = 132, yield_kw   = 133,
    return_kw  = 134, region_kw  = 135, entry_kw   = 136, emit_kw    = 137,
    expr_kw    = 138,
    true_kw    = 140, false_kw   = 141, nil_kw     = 142, and_kw     = 143,
    or_kw      = 144, not_kw     = 145,
    view_kw    = 150, noalias_kw = 151, readonly_kw= 152, writeonly_kw=153,
    requires_kw= 154, bounds_kw  = 155, disjoint_kw= 156, len_kw     = 157,
    same_len_kw= 158,
    as_kw      = 170,
    struct_kw  = 180,
}

local keywords = {
    ["extern"]   = TK.extern_kw,   ["func"]     = TK.func_kw,
    ["const"]    = TK.const_kw,    ["static"]   = TK.static_kw,
    ["type"]     = TK.type_kw,
    ["let"]      = TK.let_kw,      ["var"]      = TK.var_kw,
    ["if"]       = TK.if_kw,       ["then"]     = TK.then_kw,
    ["elseif"]   = TK.elseif_kw,   ["else"]     = TK.else_kw,
    ["switch"]   = TK.switch_kw,   ["case"]     = TK.case_kw,
    ["default"]  = TK.default_kw,  ["do"]       = TK.do_kw,
    ["end"]      = TK.end_kw,      ["while"]    = TK.while_kw,
    ["block"]    = TK.block_kw,    ["control"]  = TK.control_kw,
    ["jump"]     = TK.jump_kw,     ["yield"]    = TK.yield_kw,
    ["return"]   = TK.return_kw,   ["region"]   = TK.region_kw,
    ["entry"]    = TK.entry_kw,    ["emit"]     = TK.emit_kw,
    ["expr"]     = TK.expr_kw,
    ["true"]     = TK.true_kw,     ["false"]    = TK.false_kw,
    ["nil"]      = TK.nil_kw,      ["and"]      = TK.and_kw,
    ["or"]       = TK.or_kw,       ["not"]      = TK.not_kw,
    ["view"]     = TK.view_kw,     ["noalias"]  = TK.noalias_kw,
    ["readonly"] = TK.readonly_kw, ["writeonly"]= TK.writeonly_kw,
    ["requires"] = TK.requires_kw, ["bounds"]   = TK.bounds_kw,
    ["disjoint"] = TK.disjoint_kw, ["len"]      = TK.len_kw,
    ["same_len"] = TK.same_len_kw,
    ["as"]       = TK.as_kw,
    ["struct"]   = TK.struct_kw,
}

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
        splice_i = 0,
    }
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

-- String literal scanning (returns new position after closing quote)
local function scan_string(src, i, n, quote)
    i = i + 1
    while i <= n do
        local c = byte(src, i)
        if c == 92 then       -- escape
            i = i + 1
        elseif c == quote then
            return i + 1
        elseif c == 10 then   -- newline in string: advance
        end
        i = i + 1
    end
    return i
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
                -- Unterminated antiquote: treat rest as error
                push_tok(t, TK.eof, "", i, i, line, col)
                break
            end
            local lua_expr = sub(src, i + 2, close - 1)
            t.splice_i = t.splice_i + 1
            local id = "splice." .. t.splice_i
            t.splice_map[id] = lua_expr
            push_tok(t, TK.hole, id, i, close, line, col)
            col = col + (close - i + 1)
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
                    while i <= n and is_hex(byte(src, i)) do i = i + 1 end
                    local text = sub(src, s, i - 1)
                    push_tok(t, TK.int, text, s, i - 1, line, col)
                    col = col + (i - s)
                    goto continue_lex
                end
            end
            i = i + 1
            while i <= n and is_digit(byte(src, i)) do i = i + 1 end
            -- Float: decimal point
            if i <= n and byte(src, i) == 46 and not (i < n and byte(src, i + 1) == 46) then
                is_float = true; i = i + 1
                while i <= n and is_digit(byte(src, i)) do i = i + 1 end
            end
            -- Float: exponent
            local c = byte(src, i)
            if c == 101 or c == 69 then
                is_float = true; i = i + 1
                local sign = byte(src, i)
                if sign == 43 or sign == 45 then i = i + 1 end
                while i <= n and is_digit(byte(src, i)) do i = i + 1 end
            end
            local text = sub(src, s, i - 1)
            push_tok(t, is_float and TK.float or TK.int, text, s, i - 1, line, col)
            col = col + (i - s)

        -- String literals
        elseif b == 34 then  -- '"'
            local s, sc = i, col
            i = scan_string(src, i, n, 34)
            local text = sub(src, s, i - 1)
            push_tok(t, TK.string, text, s, i - 1, line, sc)
            col = col + (i - s)

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
                              [">="]=TK.ge, ["<<"]=TK.shl, [">>"]=TK.ashr, ["&&"]=TK.amp2,
                              ["||"]=TK.pipe2 })[s2]
                if k2 then push_tok(t, k2, s2, i, i + 1, line, col); i = i + 2; col = col + 2; goto continue_lex end
            end

            -- One-char
            local k1 = ({ ["("]=TK.lparen, [")"]=TK.rparen, ["["]=TK.lbrack, ["]"]=TK.rbrack,
                          ["{"]=TK.lbrace, ["}"]=TK.rbrace, [","]=TK.comma, [":"]=TK.colon,
                          ["."]=TK.dot, [";"]=TK.semi, ["+"]=TK.plus, ["-"]=TK.minus,
                          ["*"]=TK.star, ["/"]=TK.slash, ["%"]=TK.percent, ["="]=TK.eq,
                          ["<"]=TK.lt, [">"]=TK.gt, ["&"]=TK.amp, ["|"]=TK.pipe,
                          ["^"]=TK.caret, ["~"]=TK.tilde })[ch]
            if k1 then push_tok(t, k1, ch, i, i, line, col) end
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

local function parser_from_toks(T, toks, opts)
    opts = opts or {}
    local C, Ty, B, O, Sem, Tr, Pm =
        T.MoonCore, T.MoonType, T.MoonBind, T.MoonOpen,
        T.MoonSem, T.MoonTree, T.MoonParse
    return setmetatable({
        T = T, C = C, Ty = Ty, B = B, O = O,
        Sem = Sem, Tr = Tr, Pm = Pm,
        toks = toks, i = 1, issues = {},
        value_env = opts.value_env or {},
        cont_env = opts.cont_env or {},
        region_frags = opts.region_frags or {},
        expr_frags = opts.expr_frags or {},
        protocol_types = opts.protocol_types or {},
        qualified_values = opts.qualified_values or {},
        splice_slots = {},
        splice_slots_by_id = {},
        region_seq = 0,
    }, Parser)
end

-- Token accessors
function Parser:kind(offset) return self.toks.kind[self.i + (offset or 0)] end
function Parser:text(offset) return self.toks.text[self.i + (offset or 0)] end
function Parser:start(offset) return self.toks.start[self.i + (offset or 0)] end
function Parser:stop(offset) return self.toks.stop[self.i + (offset or 0)] end
function Parser:skip_nl() while self:kind() == TK.nl do self.i = self.i + 1 end end
function Parser:skip_sep() while self:kind() == TK.nl or self:kind() == TK.semi do self.i = self.i + 1 end end
function Parser:accept(k) if self:kind() == k then self.i = self.i + 1; return true end; return false end
function Parser:accept_text(k) if self:kind() == k then local t = self:text(); self.i = self.i + 1; return t end; return nil end

function Parser:issue(msg)
    local i = self.i
    self.issues[#self.issues + 1] = self.Pm.ParseIssue(msg, self.toks.start[i] or 0, self.toks.line[i] or 0, self.toks.col[i] or 0)
end

function Parser:expect(k, msg)
    if self:accept(k) then return true end
    self:issue(msg or ("expected token " .. tostring(k)))
    return false
end

function Parser:expect_name(msg)
    if self:kind() == TK.name or self:kind() == TK.len_kw then
        local t = self:text(); self.i = self.i + 1; return t
    end
    self:issue(msg or "expected identifier")
    return ""
end

-- Identifier keywords (can be used as field names etc.)
local ident_kw = {
    [TK.extern_kw]=true, [TK.func_kw]=true, [TK.const_kw]=true, [TK.static_kw]=true,
    [TK.type_kw]=true, [TK.let_kw]=true, [TK.var_kw]=true, [TK.if_kw]=true,
    [TK.then_kw]=true, [TK.elseif_kw]=true, [TK.else_kw]=true, [TK.switch_kw]=true,
    [TK.case_kw]=true, [TK.default_kw]=true, [TK.do_kw]=true, [TK.end_kw]=true,
    [TK.block_kw]=true, [TK.control_kw]=true, [TK.jump_kw]=true, [TK.yield_kw]=true,
    [TK.return_kw]=true, [TK.region_kw]=true, [TK.entry_kw]=true, [TK.emit_kw]=true,
    [TK.expr_kw]=true, [TK.true_kw]=true, [TK.false_kw]=true, [TK.nil_kw]=true,
    [TK.and_kw]=true, [TK.or_kw]=true, [TK.not_kw]=true, [TK.view_kw]=true,
    [TK.noalias_kw]=true, [TK.readonly_kw]=true, [TK.writeonly_kw]=true,
    [TK.requires_kw]=true, [TK.bounds_kw]=true, [TK.disjoint_kw]=true,
    [TK.len_kw]=true, [TK.same_len_kw]=true, [TK.as_kw]=true,
    [TK.struct_kw]=true, [TK.while_kw]=true,
}

function Parser:expect_field_name(msg)
    local k = self:kind()
    if k == TK.name or k == TK.len_kw or ident_kw[k] then
        local t = self:text(); self.i = self.i + 1; return t
    end
    self:issue(msg or "expected field name")
    return ""
end

function Parser:is_stop(stops) return stops[self:kind()] == true end

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
    local entry = { splice_id = splice_id, slot = slot_sum, role = role }
    self.splice_slots[#self.splice_slots + 1] = entry
    self.splice_slots_by_id[key] = entry
    return entry
end

---------------------------------------------------------------------------
-- Type parsing
---------------------------------------------------------------------------

function Parser:type_name(name)
    local C, Ty = self.C, self.Ty
    local m = { void=C.ScalarVoid, bool=C.ScalarBool, i8=C.ScalarI8, i16=C.ScalarI16,
        i32=C.ScalarI32, i64=C.ScalarI64, u8=C.ScalarU8, u16=C.ScalarU16,
        u32=C.ScalarU32, u64=C.ScalarU64, f32=C.ScalarF32, f64=C.ScalarF64,
        index=C.ScalarIndex, ptr=C.ScalarRawPtr }
    if m[name] then return Ty.TScalar(m[name]) end
    return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) })))
end

function Parser:parse_callable_type()
    local Ty = self.Ty
    self:expect(TK.lparen); self:skip_nl()
    local params = {}
    if self:kind() ~= TK.rparen then
        while true do
            params[#params + 1] = self:parse_type()
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
        end
    end
    self:expect(TK.rparen)
    local result = Ty.TScalar(self.C.ScalarVoid)
    if self:accept(TK.arrow) then result = self:parse_type() end
    return params, result
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

    if self:accept(TK.view_kw) then
        self:expect(TK.lparen); local elem = self:parse_type(); self:expect(TK.rparen)
        return Ty.TView(elem)
    end

    if self:accept(TK.func_kw) then
        local params, result = self:parse_callable_type()
        return Ty.TFunc(params, result)
    end

    -- fn / fnptr alias
    if self:kind() == TK.name and (self:text() == "fn" or self:text() == "fnptr") then
        self.i = self.i + 1
        local params, result = self:parse_callable_type()
        return Ty.TFunc(params, result)
    end

    if self:kind() == TK.name and self:text() == "closure" then
        self.i = self.i + 1
        local params, result = self:parse_callable_type()
        return Ty.TClosure(params, result)
    end

    local name = self:expect_name("expected type")
    if name == "ptr" and self:accept(TK.lparen) then
        local elem = self:parse_type(); self:expect(TK.rparen)
        return Ty.TPtr(elem)
    end

    -- Qualified path: A.B.C
    if self:kind() == TK.dot then
        local parts = { name }
        while self:accept(TK.dot) do parts[#parts + 1] = self:expect_name("expected qualified type field") end
        local path_parts = {}
        for i = 1, #parts do path_parts[i] = C.Name(parts[i]) end
        return Ty.TNamed(Ty.TypeRefPath(C.Path(path_parts)))
    end

    return self:type_name(name)
end

---------------------------------------------------------------------------
-- Expression parsing (Pratt)
---------------------------------------------------------------------------

local lbp = {
    [TK.or_kw]   = 10, [TK.pipe2]   = 10,
    [TK.and_kw]  = 20, [TK.amp2]    = 20,
    [TK.eqeq]    = 30, [TK.ne]      = 30, [TK.lt]=30, [TK.le]=30, [TK.gt]=30, [TK.ge]=30,
    [TK.pipe]    = 40, [TK.caret]   = 45, [TK.amp]=50,
    [TK.shl]     = 55, [TK.lshr]    = 55, [TK.ashr]=55,
    [TK.plus]    = 60, [TK.minus]   = 60,
    [TK.star]    = 70, [TK.slash]   = 70, [TK.percent]=70,
    [TK.lparen]  = 90, [TK.lbrack]  = 90, [TK.dot]=90,
}

function Parser:parse_expr(rbp)
    rbp = rbp or 0
    self:skip_nl()
    local left = self:nud()
    while rbp < (lbp[self:kind()] or 0) do
        local k = self:kind(); self.i = self.i + 1
        left = self:led(k, left)
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
        self:expect(TK.lparen); local ty = self:parse_type()
        self:expect(TK.comma); local val = self:parse_expr(0); self:expect(TK.rparen)
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
        self:expect(TK.lparen); local data = self:parse_expr(0); self:expect(TK.comma)
        local len = self:parse_expr(0)
        if self:accept(TK.comma) then local stride = self:parse_expr(0); self:expect(TK.rparen)
            return Tr.ExprView(Tr.ExprSurface, Tr.ViewStrided(data, self.Ty.TScalar(C.ScalarVoid), len, stride))
        end
        self:expect(TK.rparen)
        return Tr.ExprView(Tr.ExprSurface, Tr.ViewContiguous(data, self.Ty.TScalar(C.ScalarVoid), len))
    end

    if k == TK.len_kw then
        if self:kind() ~= TK.lparen then
            return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(text))
        end
        self.i = self.i + 1; local v = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ExprLen(Tr.ExprSurface, v)
    end

    if k == TK.lparen then local e = self:parse_expr(0); self:expect(TK.rparen); return e end
    if k == TK.minus  then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNeg, self:parse_expr(80)) end
    if k == TK.not_kw then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNot, self:parse_expr(80)) end
    if k == TK.tilde  then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryBitNot, self:parse_expr(80)) end
    if k == TK.star   then return Tr.ExprDeref(Tr.ExprSurface, self:parse_expr(80)) end
    if k == TK.amp    then return Tr.ExprAddrOf(Tr.ExprSurface, self:expr_to_place(self:parse_expr(80))) end
    if k == TK.switch_kw then return self:parse_switch_expr() end
    if k == TK.emit_kw   then return self:parse_emit_expr() end
    if k == TK.block_kw  then return self:parse_control_expr_after_block() end
    if k == TK.control_kw or k == TK.region_kw then return self:parse_multi_control_expr() end

    self:issue("expected expression")
    return Tr.ExprLit(Tr.ExprSurface, C.LitInt("0"))
end

function Parser:led(k, left)
    local C, Sem, Tr, B = self.C, self.Sem, self.Tr, self.B

    if k == TK.lparen then
        local args = {}
        if self:kind() ~= TK.rparen then
            repeat args[#args + 1] = self:parse_expr(0) until not self:accept(TK.comma)
        end
        self:expect(TK.rparen)
        -- select(cond, a, b) special form
        local pvm = require("moonlift.pvm")
        if pvm.classof(left) == Tr.ExprRef and pvm.classof(left.ref) == B.ValueRefName
           and left.ref.name == "select" and #args == 3 then
            return Tr.ExprSelect(Tr.ExprSurface, args[1], args[2], args[3])
        end
        return Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(left), args)
    end

    if k == TK.lbrack then
        local idx = self:parse_expr(0); self:expect(TK.rbrack)
        return Tr.ExprIndex(Tr.ExprSurface, Tr.IndexBaseExpr(left), idx)
    end

    if k == TK.dot then
        local field = self:expect_name("expected field name")
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
    if k == TK.and_kw or k == TK.amp2 then return Tr.ExprLogic(Tr.ExprSurface, C.LogicAnd, left, self:parse_expr(lbp[k])) end
    if k == TK.or_kw or k == TK.pipe2 then return Tr.ExprLogic(Tr.ExprSurface, C.LogicOr, left, self:parse_expr(lbp[k])) end

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
        if lit == C.LitInt  then return Sem.SwitchKeyRaw(expr.value.raw) end
        if lit == C.LitBool then return Sem.SwitchKeyRaw(expr.value.value and "true" or "false") end
    end
    if cls == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefName then
        return Sem.SwitchKeyRaw(expr.ref.name)
    end
    return Sem.SwitchKeyExpr(expr)
end

function Parser:parse_switch_stmt()
    local Tr, Sem = self.Tr, self.Sem
    local value = self:parse_expr(0)
    self:expect(TK.do_kw, "expected do after switch expression")
    self:skip_nl()
    local arms = {}
    while self:kind() == TK.case_kw do
        self.i = self.i + 1  -- consume 'case'
        local key_expr = self:parse_expr(0)
        self:expect(TK.then_kw, "expected then after case expression")
        local body = self:parse_stmt_until({ [TK.case_kw]=true, [TK.default_kw]=true, [TK.end_kw]=true })
        arms[#arms + 1] = Tr.SwitchStmtArm(self:switch_key_from_expr(key_expr), body)
        self:skip_nl()
    end
    self:expect(TK.default_kw, "expected default in switch")
    self:expect(TK.then_kw, "expected then after default")
    local default_body = self:parse_stmt_until({ [TK.end_kw]=true })
    self:expect(TK.end_kw, "expected end after switch")
    return Tr.StmtSwitch(Tr.StmtSurface, value, arms, {}, default_body)
end

function Parser:parse_switch_expr()
    local Tr, Sem = self.Tr, self.Sem
    local value = self:parse_expr(0)
    self:expect(TK.do_kw, "expected do after switch expression")
    self:skip_nl()
    local arms = {}
    while self:kind() == TK.case_kw do
        self.i = self.i + 1
        local key_expr = self:parse_expr(0)
        self:expect(TK.then_kw, "expected then after case expression")
        local body, result = self:parse_expr_block({ [TK.case_kw]=true, [TK.default_kw]=true, [TK.end_kw]=true })
        arms[#arms + 1] = Tr.SwitchExprArm(self:switch_key_from_expr(key_expr), body, result)
        self:skip_nl()
    end
    self:expect(TK.default_kw, "expected default in switch")
    self:expect(TK.then_kw, "expected then after default")
    local default_body, default_expr = self:parse_expr_block({ [TK.end_kw]=true })
    self:expect(TK.end_kw, "expected end after switch")
    return Tr.ExprSwitch(Tr.ExprSurface, value, arms, default_body, default_expr)
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

-- Block expression: block name(params = init) -> T body end
function Parser:parse_control_expr_after_block()
    local Tr = self.Tr
    local label = Tr.BlockLabel(self:expect_name("expected block label"))
    local params = self:parse_block_params(true)
    self:expect(TK.arrow, "expected -> for block expression")
    local result_ty = self:parse_type()
    local body = self:parse_stmt_until({ [TK.end_kw]=true })
    self:expect(TK.end_kw)
    return Tr.ExprControl(Tr.ExprSurface,
        Tr.ControlExprRegion(self:next_region_id(label.name), result_ty,
            Tr.EntryControlBlock(label, params, body), {}))
end

-- Multi-block control: control -> T entry ... end block ... end end
function Parser:parse_multi_control_expr()
    local Tr = self.Tr
    self:expect(TK.arrow, "expected -> after control/region")
    local result_ty = self:parse_type()
    self:skip_nl()
    if not (self:accept(TK.entry_kw) or self:accept(TK.block_kw)) then self:expect(TK.entry_kw, "expected entry block") end
    local entry_label = Tr.BlockLabel(self:expect_name("expected block label"))
    local entry_params = self:parse_block_params(true)
    local entry_body = self:parse_stmt_until({ [TK.end_kw]=true, [TK.block_kw]=true })
    if self:kind() == TK.end_kw then self.i = self.i + 1 end
    local blocks = {}
    self:skip_nl()
    while self:kind() == TK.block_kw do
        self.i = self.i + 1
        local label = Tr.BlockLabel(self:expect_name("expected block label"))
        local params = self:parse_block_params(false)
        local body = self:parse_stmt_until({ [TK.end_kw]=true })
        self:expect(TK.end_kw)
        blocks[#blocks + 1] = Tr.ControlBlock(label, params, body)
        self:skip_nl()
    end
    self:expect(TK.end_kw, "expected control end")
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
            local name = self:expect_name("expected block parameter")
            self:expect(TK.colon)
            local ty = self:parse_type()
            if entry then
                self:expect(TK.eq, "entry block params need initializers")
                params[#params + 1] = Tr.EntryBlockParam(name, ty, self:parse_expr(0))
            else
                params[#params + 1] = Tr.BlockParam(name, ty)
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
        end
    end
    self:expect(TK.rparen)
    return params
end

function Parser:parse_jump_args()
    local Tr = self.Tr
    local args = {}
    self:expect(TK.lparen); self:skip_nl()
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

-- Region fragment reference (for emit)
function Parser:parse_region_frag_ref()
    local O = self.O
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.RegionFragSlot(self:splice_key("region_frag", id), id)
        self:record_splice_slot(id, O.SlotRegionFrag(slot), "region_frag")
        return O.RegionFragRefSlot(slot)
    end
    local name = self:expect_name("expected region fragment name after emit")
    return O.RegionFragRefName(name), name
end

function Parser:parse_expr_frag_ref()
    local O = self.O
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.ExprFragSlot(self:splice_key("expr_frag", id), id)
        self:record_splice_slot(id, O.SlotExprFrag(slot), "expr_frag")
        return O.ExprFragRefSlot(slot), "splice." .. id
    end
    local name = self:expect_name("expected expression fragment name after emit")
    return O.ExprFragRefName(name), name
end

function Parser:parse_emit_stmt()
    local Tr, O = self.Tr, self.O
    local frag_ref, use_suffix = self:parse_region_frag_ref()
    local frag_name_str = type(use_suffix) == "string" and use_suffix or tostring(use_suffix)
    local args, cont_fills = {}, {}
    self:expect(TK.lparen, "expected '(' after emitted fragment name")
    self:skip_nl()
    if self:kind() ~= TK.rparen and self:kind() ~= TK.semi then
        while true do
            args[#args + 1] = self:parse_expr(0)
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
    self:expect(TK.rparen, "expected ')' after emit")
    return Tr.StmtUseRegionFrag(Tr.StmtSurface,
        "emit." .. frag_name_str .. "." .. tostring(self.i), frag_ref, args, {}, cont_fills)
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
            args[#args + 1] = self:parse_expr(0)
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
    return "control." .. prefix .. "." .. tostring(self.region_seq)
end

function Parser:parse_stmt()
    local Tr, B, C = self.Tr, self.B, self.C
    self:skip_nl()

    -- Hole: @{stmt_source} in statement position (region body splice)
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = self.O.RegionSlot(self:splice_key("region_body", id), id)
        self:record_splice_slot(id, self.O.SlotRegion(slot), "region_body")
        return Tr.StmtUseRegionSlot(Tr.StmtSurface, slot)
    end

    if self:accept(TK.emit_kw) then return self:parse_emit_stmt() end

    if self:accept(TK.let_kw) or self:accept(TK.var_kw) then
        local is_var = self.toks.kind[self.i - 1] == TK.var_kw
        local name = self:expect_name()
        local ty
        if self:kind() == TK.colon then
            self.i = self.i + 1; ty = self:parse_type()
        else
            ty = self.Ty.TScalar(self.C.ScalarVoid)  -- sentinel: infer
        end
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
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.comma)
        local len = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractBounds(base, len)
    elseif self:accept(TK.disjoint_kw) then
        self:expect(TK.lparen); local a = self:parse_expr(0); self:expect(TK.comma)
        local b = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractDisjoint(a, b)
    elseif self:accept(TK.same_len_kw) then
        self:expect(TK.lparen); local a = self:parse_expr(0); self:expect(TK.comma)
        local b = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractSameLen(a, b)
    elseif self:accept(TK.noalias_kw) then
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractNoAlias(base)
    elseif self:accept(TK.readonly_kw) then
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractReadonly(base)
    elseif self:accept(TK.writeonly_kw) then
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.rparen)
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
    self:skip_nl()
    if self:kind() == TK.rparen then return params, contracts end
    while true do
        self:skip_nl()
        local mods = {}
        while self:kind() == TK.noalias_kw or self:kind() == TK.readonly_kw or self:kind() == TK.writeonly_kw do
            mods[#mods + 1] = self:kind(); self.i = self.i + 1
        end
        local name = self:expect_name("expected parameter name")
        self:expect(TK.colon, "expected ':' in parameter")
        params[#params + 1] = Ty.Param(name, self:parse_type())
        -- Convert modifiers to contracts
        local ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
        for i = 1, #mods do
            if mods[i] == TK.noalias_kw then contracts[#contracts + 1] = Tr.ContractNoAlias(ref)
            elseif mods[i] == TK.readonly_kw then contracts[#contracts + 1] = Tr.ContractReadonly(ref)
            elseif mods[i] == TK.writeonly_kw then contracts[#contracts + 1] = Tr.ContractWriteonly(ref) end
        end
        if not self:accept(TK.comma) then break end
        self:skip_nl()
    end
    return params, contracts
end

---------------------------------------------------------------------------
-- Top-level declaration parsing
---------------------------------------------------------------------------

function Parser:parse_extern_func()
    local Tr = self.Tr
    local name = self:expect_name("expected extern function name")
    self:expect(TK.lparen); local params = self:parse_param_list(); self:expect(TK.rparen)
    local result = self.Ty.TScalar(self.C.ScalarVoid)
    if self:accept(TK.arrow) then result = self:parse_type() end
    return Tr.ExternFunc(name, name, params, result)
end

function Parser:parse_func()
    local Tr, Ty, C = self.Tr, self.Ty, self.C
    local name = self:expect_name("expected function name")
    self:expect(TK.lparen); local params, contracts = self:parse_param_list(); self:expect(TK.rparen)
    local result = Ty.TScalar(C.ScalarVoid)
    if self:accept(TK.arrow) then result = self:parse_type() end
    self:skip_nl()
    while self:kind() == TK.requires_kw do
        contracts[#contracts + 1] = self:parse_contract()
        self:skip_nl()
    end
    local body = self:parse_stmt_until({ [TK.end_kw]=true })
    self:expect(TK.end_kw, "expected end after function")
    if #contracts > 0 then
        return Tr.FuncLocalContract(name, params, result, contracts, body)
    end
    return Tr.FuncLocal(name, params, result, body)
end

-- Structure: struct Name [repr(packed(N))] field: Type ... end
function Parser:parse_struct()
    local Tr, Ty = self.Tr, self.Ty
    local name = self:expect_name("expected struct name")
    self:skip_nl()
    local fields = {}
    while self:kind() ~= TK.end_kw and self:kind() ~= TK.eof do
        self:skip_nl()
        if self:kind() == TK.end_kw then break end
        local fname = self:expect_field_name("expected struct field name")
        self:expect(TK.colon, "expected ':' in struct field")
        fields[#fields + 1] = Ty.FieldDecl(fname, self:parse_type())
        self:skip_nl()
    end
    self:expect(TK.end_kw, "expected end after struct")
    return Tr.TypeDeclStruct(name, fields)
end

-- Continuation params for region fragments
function Parser:parse_cont_params(owner_name)
    local O, Tr = self.O, self.Tr
    local cont_slots, slots = {}, {}
    while self:kind() ~= TK.rparen and self:kind() ~= TK.eof do
        local name = self:expect_name("expected continuation parameter name")
        self:expect(TK.colon, "expected ':' in continuation parameter")
        self:expect_name()  -- consume 'cont'
        self:expect(TK.lparen)
        local params = {}
        self:skip_nl()
        if self:kind() ~= TK.rparen then
            while true do
                local pname = self:expect_name("expected continuation arg name")
                self:expect(TK.colon)
                params[#params + 1] = Tr.BlockParam(pname, self:parse_type())
                self:skip_nl()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
            end
        end
        self:expect(TK.rparen)
        local slot = O.ContSlot("cont:" .. owner_name .. ":" .. name .. ":" .. tostring(#slots + 1), name, params)
        cont_slots[name] = slot
        slots[#slots + 1] = slot
        self:skip_nl()
        if not self:accept(TK.comma) then break end
        self:skip_nl()
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
    if self:kind() ~= TK.rparen then
        while true do
            local pname = self:expect_name("expected parameter name")
            self:expect(TK.colon)
            local ty = self:parse_type()
            local param = O.OpenParam("param:" .. owner_name .. ":" .. pname .. ":" .. tostring(#params + 1), pname, ty)
            params[#params + 1] = param
            param_bindings[pname] = B.Binding(C.Id("open-param:" .. owner_name .. ":" .. pname), pname, ty, B.BindingClassOpenParam(param))
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        end
    end
    return params, param_bindings
end

-- Region fragment: region name(params; conts) -> Protocol | entry ... end [block ... end]* end
function Parser:parse_region_frag()
    local O, B, C, Tr = self.O, self.B, self.C, self.Tr
    -- Name (or hole)
    local name_ref
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.NameSlot(self:splice_key("name", id), id)
        self:record_splice_slot(id, O.SlotName(slot), "name")
        name_ref = O.NameRefSlot(slot)
    else
        name_ref = O.NameRefText(self:expect_name("expected region fragment name"))
    end
    local pvm = require("moonlift.pvm")
    local name_key = pvm.classof(name_ref) == O.NameRefText and name_ref.text or ("__hole_" .. name_ref.slot.key)

    self:expect(TK.lparen)
    local params, param_bindings = self:parse_open_params(name_key)
    local cont_slots, slots = {}, {}
    self:skip_nl()
    if self:accept(TK.semi) then
        self:skip_nl()
        cont_slots, slots = self:parse_cont_params(name_key)
    end
    self:expect(TK.rparen)
    self:skip_nl()

    -- Protocol result?
    if self:accept(TK.arrow) then
        if #slots > 0 then self:issue("region cannot mix inline continuations with protocol result") end
        local protocol_ty = self:parse_type()
        cont_slots, slots = self:cont_slots_from_protocol(protocol_ty, name_key)
        self:skip_nl()
    end

    if not (self:accept(TK.entry_kw) or self:accept(TK.block_kw)) then
        self:expect(TK.entry_kw, "expected entry block in region fragment")
    end
    local entry_label = Tr.BlockLabel(self:expect_name("expected entry label"))
    local entry_params = self:parse_block_params(true)
    local old_value_env, old_cont_env = self.value_env, self.cont_env
    self.value_env, self.cont_env = param_bindings, cont_slots
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
    self.value_env, self.cont_env = old_value_env, old_cont_env
    self:expect(TK.end_kw, "expected end after region fragment")

    return O.RegionFrag(name_ref, params, slots, O.OpenSet({}, {}, {}, {}),
        Tr.EntryControlBlock(entry_label, entry_params, body), blocks)
end

-- Expression fragment: expr name(params) -> T body end
function Parser:parse_expr_frag()
    local O, B, C = self.O, self.B, self.C
    local name_ref
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = O.NameSlot(self:splice_key("name", id), id)
        self:record_splice_slot(id, O.SlotName(slot), "name")
        name_ref = O.NameRefSlot(slot)
    else
        name_ref = O.NameRefText(self:expect_name("expected expression fragment name"))
    end
    local pvm = require("moonlift.pvm")
    local name_key = pvm.classof(name_ref) == O.NameRefText and name_ref.text or ("__hole_" .. name_ref.slot.key)

    self:expect(TK.lparen)
    local params, param_bindings = self:parse_open_params(name_key)
    self:expect(TK.rparen)
    self:expect(TK.arrow, "expected -> in expression fragment")
    local result = self:parse_type()
    local old_value_env = self.value_env
    self.value_env = param_bindings
    local body = self:parse_expr(0)
    self:skip_nl()
    self.value_env = old_value_env
    self:expect(TK.end_kw, "expected end after expression fragment")
    return O.ExprFrag(name_ref, params, O.OpenSet({}, {}, {}, {}), body, result)
end

-- Type declaration: type Name = struct/union/enum ... end  OR  type Name = A | B(i32)
function Parser:parse_type_item()
    local Tr, Ty = self.Tr, self.Ty
    local name = self:expect_name("expected type name")
    self:expect(TK.eq, "expected '=' in type item")
    if self:accept(TK.struct_kw) then
        local fields = self:parse_type_fields()
        return Tr.ItemType(Tr.TypeDeclStruct(name, fields))
    end
    -- Tagged union
    local variants = self:parse_tagged_union_variants()
    if self:kind() == TK.end_kw then self.i = self.i + 1 end
    -- Record protocol type for region dispatch
    self.protocol_types[name] = variants
    return Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(name, variants))
end

function Parser:parse_type_fields()
    local Ty = self.Ty
    local fields = {}
    self:skip_nl()
    while self:kind() ~= TK.end_kw and self:kind() ~= TK.eof do
        local fname = self:expect_field_name("expected field name")
        self:expect(TK.colon, "expected ':' in field declaration")
        fields[#fields + 1] = Ty.FieldDecl(fname, self:parse_type())
        self:skip_nl()
        if self:accept(TK.comma) then self:skip_nl() end
    end
    self:expect(TK.end_kw, "expected end after type declaration")
    return fields
end

function Parser:parse_tagged_union_variants()
    local Ty = self.Ty
    local variants = {}
    while self:kind() ~= TK.eof do
        self:skip_nl()
        local name = self:expect_field_name("expected tagged union variant")
        local payload = Ty.TScalar(self.C.ScalarVoid)
        local fields = {}
        if self:accept(TK.lparen) then
            self:skip_nl()
            if self:kind() == TK.rparen then
                self.i = self.i + 1  -- empty ()
            elseif self:kind() == TK.name and self:kind(1) == TK.colon then
                -- Named fields
                while self:kind() ~= TK.rparen and self:kind() ~= TK.eof do
                    local fname = self:expect_field_name("expected tagged union field name")
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
        variants[#variants + 1] = Ty.VariantDecl(name, payload, fields)
        self:skip_nl()
        if not self:accept(TK.pipe) then break end
    end
    return variants
end

function Parser:parse_const()
    local Tr = self.Tr
    local name = self:expect_name("expected const name")
    self:expect(TK.colon)
    local ty = self:parse_type()
    self:expect(TK.eq)
    return Tr.ItemConst(Tr.ConstItem(name, ty, self:parse_expr(0)))
end

function Parser:parse_static()
    local Tr = self.Tr
    local name = self:expect_name("expected static name")
    self:expect(TK.colon)
    local ty = self:parse_type()
    self:expect(TK.eq)
    return Tr.ItemStatic(Tr.StaticItem(name, ty, self:parse_expr(0)))
end

-- Item parsing (for compilation unit building via moon.compile)
function Parser:parse_item()
    local Tr = self.Tr
    self:skip_nl()

    -- Hole: @{items}
    if self:kind() == TK.hole then
        local id = self:text(); self.i = self.i + 1
        local slot = self.O.ItemsSlot(self:splice_key("module_items", id), id)
        self:record_splice_slot(id, self.O.SlotItems(slot), "module_items")
        return Tr.ItemUseItemsSlot(slot)
    end

    if self:accept(TK.func_kw) then return Tr.ItemFunc(self:parse_func()) end
    if self:accept(TK.extern_kw) then self:expect(TK.func_kw); return Tr.ItemExtern(self:parse_extern_func()) end
    if self:accept(TK.const_kw) then return self:parse_const() end
    if self:accept(TK.static_kw) then return self:parse_static() end
    if self:accept(TK.type_kw) then return self:parse_type_item() end
    if self:accept(TK.struct_kw) then return Tr.ItemType(self:parse_struct()) end

    self:issue("expected item")
    self.i = self.i + 1
    return nil
end

-- Parse items from source (used by host_splice for source escapes)
function M.parse_items(T, src)
    local toks = M.lex(src)
    local p = parser_from_toks(T, toks, {})
    p:skip_sep()
    local items = {}
    while p:kind() ~= TK.eof and p:kind() ~= TK.end_kw do
        local item = p:parse_item()
        if item ~= nil then items[#items + 1] = item end
        p:skip_sep()
    end
    if p:kind() == TK.end_kw then p.i = p.i + 1 end
    return { module = p.Tr.Module(p.Tr.ModuleSurface, items), issues = p.issues }
end

function M.parse_type_string(T, src)
    local toks = M.lex("func __t__(x: " .. src .. ") -> void end")
    local p = parser_from_toks(T, toks, {})
    p:expect(TK.func_kw); p:expect_name()
    p:expect(TK.lparen); p:expect_name()
    p:expect(TK.colon)
    local ty = p:parse_type()
    if #p.issues > 0 then error("type parse error: " .. tostring(p.issues[1]), 2) end
    return ty
end

function M.parse_func(T, src, opts)
    local toks = M.lex(src); local p = parser_from_toks(T, toks, opts)
    p:skip_sep(); p:expect(TK.func_kw); return { func = p:parse_func(), splice_slots = p.splice_slots, issues = p.issues }
end

function M.parse_region_frag(T, src, opts)
    local toks = M.lex(src); local p = parser_from_toks(T, toks, opts)
    p:skip_sep(); p:expect(TK.region_kw); return { frag = p:parse_region_frag(), splice_slots = p.splice_slots, issues = p.issues }
end

function M.parse_expr_frag(T, src, opts)
    local toks = M.lex(src); local p = parser_from_toks(T, toks, opts)
    p:skip_sep(); p:expect(TK.expr_kw); return { frag = p:parse_expr_frag(), splice_slots = p.splice_slots, issues = p.issues }
end

function M.parse_struct(T, src, opts)
    local toks = M.lex(src); local p = parser_from_toks(T, toks, opts)
    p:skip_sep(); p:expect(TK.struct_kw); return { struct = p:parse_struct(), splice_slots = p.splice_slots, issues = p.issues }
end

function M.parse_extern_func(T, src, opts)
    local toks = M.lex(src); local p = parser_from_toks(T, toks, opts)
    p:skip_sep(); p:expect(TK.extern_kw); p:expect(TK.func_kw)
    return { func = p:parse_extern_func(), splice_slots = p.splice_slots, issues = p.issues }
end

function M.parse_type_item(T, src, opts)
    local toks = M.lex(src); local p = parser_from_toks(T, toks, opts)
    p:skip_sep(); p:expect(TK.type_kw)
    local item = p:parse_type_item()
    return { item = item, splice_slots = p.splice_slots, issues = p.issues, protocol_types = p.protocol_types }
end

function M.parse_const(T, src, opts)
    local toks = M.lex(src); local p = parser_from_toks(T, toks, opts)
    p:skip_sep(); p:expect(TK.const_kw); return { item = p:parse_const(), splice_slots = p.splice_slots, issues = p.issues }
end

function M.parse_static(T, src, opts)
    local toks = M.lex(src); local p = parser_from_toks(T, toks, opts)
    p:skip_sep(); p:expect(TK.static_kw); return { item = p:parse_static(), splice_slots = p.splice_slots, issues = p.issues }
end

-- Parse a statement list from source (used by host_splice for region_body)
function M.parse_stmt_list(T, src, opts)
    local wrapped = "func __stmts__(x: i32) -> i32\n" .. src .. "\n    return x\nend"
    local result = M.parse_func(T, wrapped, opts)
    if #result.issues > 0 then return nil, result.issues end
    if result.func and result.func.body then
        local body = {}
        for i = 1, #result.func.body do body[i] = result.func.body[i] end
        return body, {}
    end
    return nil, { T.MoonParse.ParseIssue("source stmt list: could not extract body", 0, 0, 0) }
end

---------------------------------------------------------------------------
-- Island dispatch (called by eval_island)
---------------------------------------------------------------------------

-- Parse an island by its kind string, returning { value = ..., splice_slots = ..., issues = ... }
function M.parse_island(T, kind, src, opts)
    opts = opts or {}
    if kind == "func" then
        local r = M.parse_func(T, src, opts)
        return { value = r.func, splice_slots = r.splice_slots, issues = r.issues }
    elseif kind == "region" then
        local r = M.parse_region_frag(T, src, opts)
        return { value = r.frag, splice_slots = r.splice_slots, issues = r.issues }
    elseif kind == "expr" then
        local r = M.parse_expr_frag(T, src, opts)
        return { value = r.frag, splice_slots = r.splice_slots, issues = r.issues }
    elseif kind == "struct" then
        local r = M.parse_struct(T, src, opts)
        return { value = r.struct, splice_slots = r.splice_slots, issues = r.issues }
    elseif kind == "extern" then
        local r = M.parse_extern_func(T, src, opts)
        return { value = r.func, splice_slots = r.splice_slots, issues = r.issues }
    elseif kind == "type" then
        local r = M.parse_type_item(T, src, opts)
        return { value = r.item, splice_slots = r.splice_slots, issues = r.issues,
                 protocol_types = r.protocol_types }
    elseif kind == "const" then
        local r = M.parse_const(T, src, opts)
        return { value = r.item, splice_slots = r.splice_slots, issues = r.issues }
    elseif kind == "static" then
        local r = M.parse_static(T, src, opts)
        return { value = r.item, splice_slots = r.splice_slots, issues = r.issues }
    elseif kind == "module" then
        -- Legacy: parse as module items
        local r = M.parse_module(T, src, opts)
        return { value = r.module, splice_slots = r.splice_slots, issues = r.issues,
                 protocol_types = r.protocol_types }
    else
        error("unsupported island kind: " .. tostring(kind), 2)
    end
end

function M.Define(T)
    return {
        TK = TK,
        lex = M.lex,
        parser_from_toks = function(toks, opts) return parser_from_toks(T, toks, opts) end,
        parse_func = function(src, opts) return M.parse_func(T, src, opts) end,
        parse_region_frag = function(src, opts) return M.parse_region_frag(T, src, opts) end,
        parse_expr_frag = function(src, opts) return M.parse_expr_frag(T, src, opts) end,
        parse_struct = function(src, opts) return M.parse_struct(T, src, opts) end,
        parse_extern_func = function(src, opts) return M.parse_extern_func(T, src, opts) end,
        parse_type_item = function(src, opts) return M.parse_type_item(T, src, opts) end,
        parse_const = function(src, opts) return M.parse_const(T, src, opts) end,
        parse_static = function(src, opts) return M.parse_static(T, src, opts) end,
        parse_module = function(src, opts) return M.parse_module(T, src, opts) end,
        parse_stmt_list = function(src, opts) return M.parse_stmt_list(T, src, opts) end,
        parse_type_string = function(src) return M.parse_type_string(T, src) end,
        parse_island = function(kind, src, opts) return M.parse_island(T, kind, src, opts) end,
    }
end

M.TK = TK

return M
