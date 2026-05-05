-- cpp_expand.lua -- C preprocessor operating on token streams
-- Takes tokens/spans from c_lexer, returns expanded token stream
-- with no directive tokens and all macros expanded.
--
-- Local module, not a PVM phase directly, but follows the Define(T) pattern
-- for consistency with the rest of the C frontend.

local pvm = require("moonlift.pvm")
local bit = require("bit")
local M = {}

-----------------------------------------------------------------------------
-- Local utility helpers
-----------------------------------------------------------------------------

local function is_ident(tok)
    return type(tok) == "table" and tok._variant == "CTokIdent"
end

local function is_punct(tok, text)
    return type(tok) == "table" and tok._variant == "CTokPunct"
           and (text == nil or tok.text == text)
end

local function is_newline(tok)
    return type(tok) == "table" and tok._variant == "CTokNewline"
end

local function is_directive(tok)
    return type(tok) == "table" and tok._variant == "CTokDirective"
end

local function is_eof(tok)
    return type(tok) == "table" and tok._variant == "CTokEOF"
end

local function dir_kind(tok)
    if is_directive(tok) and type(tok.kind) == "table" then
        return tok.kind._variant
    end
    return nil
end

-- Return the textual representation of a token (for ## pasting and diagnostics)
local function token_text(tok)
    if tok._variant == "CTokIdent" then return tok.name end
    if tok._variant == "CTokKeyword" then
        local kw = tok.kw._variant
        local map = {
            CKwAuto = "auto", CKwBreak = "break", CKwCase = "case",
            CKwChar = "char", CKwConst = "const", CKwContinue = "continue",
            CKwDefault = "default", CKwDo = "do", CKwDouble = "double",
            CKwElse = "else", CKwEnum = "enum", CKwExtern = "extern",
            CKwFloat = "float", CKwFor = "for", CKwGoto = "goto",
            CKwIf = "if", CKwInline = "inline", CKwInt = "int",
            CKwLong = "long", CKwRegister = "register", CKwRestrict = "restrict",
            CKwReturn = "return", CKwShort = "short", CKwSigned = "signed",
            CKwSizeof = "sizeof", CKwStatic = "static", CKwStruct = "struct",
            CKwSwitch = "switch", CKwTypedef = "typedef", CKwUnion = "union",
            CKwUnsigned = "unsigned", CKwVoid = "void", CKwVolatile = "volatile",
            CKwWhile = "while",
            CKwBool = "_Bool", CKwComplex = "_Complex",
            CKwInline2 = "__inline", CKwRestrict2 = "__restrict",
        }
        return map[kw] or ("<keyword:" .. kw .. ">")
    end
    if tok._variant == "CTokIntLiteral" then return tok.raw .. tok.suffix end
    if tok._variant == "CTokFloatLiteral" then return tok.raw .. tok.suffix end
    if tok._variant == "CTokCharLiteral" then return tok.raw end
    if tok._variant == "CTokStringLiteral" then
        return tok.prefix .. '"' .. tok.raw .. '"'
    end
    if tok._variant == "CTokPunct" then return tok.text end
    if tok._variant == "CTokNewline" then return "\n" end
    if tok._variant == "CTokEOF" then return "" end
    if tok._variant == "CTokDirective" then return "" end
    return ""
end

-- Create a token from a text string (for ## pasting results).
local function token_from_text(text)
    if text == "" then return nil end
    if text:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
        return { _variant = "CTokIdent", name = text }
    end
    if text:match("^[0-9]+[uUlL]?$") then
        local raw, suffix = text:match("^([0-9]+)([uUlL]*)$")
        return { _variant = "CTokIntLiteral", raw = raw or text, suffix = suffix or "" }
    end
    if text:match("^0[xX][0-9a-fA-F]+") then
        return { _variant = "CTokIntLiteral", raw = text, suffix = "" }
    end
    if text == "..." then
        return { _variant = "CTokPunct", text = "..." }
    end
    if text == "->" or text == "++" or text == "--" or text == "<<"
    or text == ">>" or text == "<=" or text == ">=" or text == "=="
    or text == "!=" or text == "&&" or text == "||" then
        return { _variant = "CTokPunct", text = text }
    end
    if #text == 1 and text:match("[%+%-%*%%/%%<>=!&|%^%~%?%(%)%{%}%[%];:%.,#]") then
        return { _variant = "CTokPunct", text = text }
    end
    if text:match("^%.") then return { _variant = "CTokPunct", text = text } end
    return { _variant = "CTokPunct", text = text }
end

-- Deep-copy a list of tokens
local function copy_token_list(toks)
    local out = {}
    for i, t in ipairs(toks) do
        out[i] = t
    end
    return out
end

-----------------------------------------------------------------------------
-- Macro table
-----------------------------------------------------------------------------

local function make_macro_table(line_counter_ref, file_uri_ref)
    -- Separate backing table to avoid method name collisions
    local entries = {}

    -- Built-in macros
    entries.__STDC__ = {
        kind = "object",
        body = { { _variant = "CTokIntLiteral", raw = "1", suffix = "" } },
    }
    entries.__STDC_VERSION__ = {
        kind = "object",
        body = { { _variant = "CTokIntLiteral", raw = "199901", suffix = "L" } },
    }
    entries.__moonlift__ = {
        kind = "object",
        body = { { _variant = "CTokIntLiteral", raw = "1", suffix = "" } },
    }
    entries.__COUNTER__ = {
        kind = "object_dynamic",
        dynamic_fn = function()
            local val = line_counter_ref.counter_val or 0
            line_counter_ref.counter_val = val + 1
            return { { _variant = "CTokIntLiteral", raw = tostring(val), suffix = "" } }
        end,
    }
    entries.__LINE__ = {
        kind = "object_dynamic",
        dynamic_fn = function()
            return { { _variant = "CTokIntLiteral", raw = tostring(line_counter_ref.n), suffix = "" } }
        end,
    }
    entries.__FILE__ = {
        kind = "object_dynamic",
        dynamic_fn = function()
            return { { _variant = "CTokStringLiteral", raw = file_uri_ref.s, prefix = "" } }
        end,
    }

    local macros = {}
    function macros:add(name, macro)
        entries[name] = macro
    end

    function macros:remove(name)
        entries[name] = nil
    end

    function macros:lookup(name)
        return entries[name]
    end

    return macros
end

-----------------------------------------------------------------------------
-- Expression evaluator for #if / #elif
-----------------------------------------------------------------------------

-- Parse an integer literal from a token, returning value in [0, 2^64).
local function parse_int_literal(tok)
    if tok._variant == "CTokIntLiteral" then
        local raw = tok.raw
        -- Strip any trailing suffix characters from raw (defensive: lexer
        -- should keep raw suffix-free, but built-in macros might be hand-crafted)
        local numeric = raw:match("^([0-9]+)") or raw:match("^0[xX]([0-9a-fA-F]+)") or raw
        local val
        if raw:sub(1, 2):lower() == "0x" then
            val = tonumber(numeric, 16)
        elseif raw:sub(1, 1) == "0" and #raw > 1 then
            val = tonumber(numeric, 8)
        else
            val = tonumber(numeric, 10)
        end
        val = val or 0
        return math.floor(val) % 2^64
    end
    if tok._variant == "CTokCharLiteral" then
        local raw = tok.raw
        if raw and #raw > 0 then
            local c = raw:sub(2, 2)
            if c == "\\" then
                local esc = raw:sub(3, 3)
                local esc_map = { n = 10, t = 9, r = 13, ["0"] = 0, ["\\"] = 92, ["'"] = 39, ['"'] = 34 }
                return esc_map[esc] or 0
            end
            return c:byte() or 0
        end
        return 0
    end
    if type(tok) == "number" then return tok end
    return 0
end

-- Pre-process "defined" operator in the token stream for #if evaluation.
-- Replaces `defined(NAME)` and `defined NAME` with 1 or 0.
local function preprocess_defined(tokens, macro_table)
    local out = {}
    local i = 1
    while i <= #tokens do
        local tok = tokens[i]
        if is_ident(tok) and tok.name == "defined" then
            if i + 1 <= #tokens then
                local next = tokens[i + 1]
                if is_punct(next, "(") then
                    local j = i + 2
                    if j <= #tokens and is_ident(tokens[j]) then
                        local name = tokens[j].name
                        local val = macro_table:lookup(name) and 1 or 0
                        if j + 1 <= #tokens and is_punct(tokens[j + 1], ")") then
                            out[#out + 1] = { _variant = "CTokIntLiteral", raw = tostring(val), suffix = "" }
                            i = j + 2
                        else
                            out[#out + 1] = { _variant = "CTokIntLiteral", raw = "0", suffix = "" }
                            i = j + 1
                        end
                    else
                        out[#out + 1] = { _variant = "CTokIntLiteral", raw = "0", suffix = "" }
                        i = i + 2
                    end
                elseif is_ident(next) then
                    local name = next.name
                    local val = macro_table:lookup(name) and 1 or 0
                    out[#out + 1] = { _variant = "CTokIntLiteral", raw = tostring(val), suffix = "" }
                    i = i + 2
                else
                    out[#out + 1] = { _variant = "CTokIntLiteral", raw = "0", suffix = "" }
                    i = i + 1
                end
            else
                out[#out + 1] = tok
                i = i + 1
            end
        else
            out[#out + 1] = tok
            i = i + 1
        end
    end
    return out
end

-- Expand macros in a token list for #if evaluation (before defined processing).
local function expand_if_tokens(tokens, macro_table, disabled, line_counter_ref, file_uri_ref)
    local out = {}
    for _, tok in ipairs(tokens) do
        if is_ident(tok) and not disabled[tok.name] then
            local macro = macro_table:lookup(tok.name)
            if macro then
                if macro.kind == "object" then
                    for _, bt in ipairs(macro.body) do
                        out[#out + 1] = bt
                    end
                elseif macro.kind == "object_dynamic" then
                    local body = macro.dynamic_fn()
                    for _, bt in ipairs(body) do
                        out[#out + 1] = bt
                    end
                else
                    -- Function-like evaluated as identifier -> 0
                    out[#out + 1] = tok
                end
            else
                out[#out + 1] = tok
            end
        else
            out[#out + 1] = tok
        end
    end
    return out
end

-- Tokenize a token list into an intermediate form for the expression evaluator.
local function tokenize_expr(tokens)
    local out = {}
    for _, tok in ipairs(tokens) do
        if tok._variant == "CTokIntLiteral" or tok._variant == "CTokCharLiteral" then
            out[#out + 1] = { type = "num", val = parse_int_literal(tok) }
        elseif tok._variant == "CTokIdent" then
            out[#out + 1] = { type = "num", val = 0 }
        elseif is_punct(tok, "(") then
            out[#out + 1] = { type = "lp" }
        elseif is_punct(tok, ")") then
            out[#out + 1] = { type = "rp" }
        elseif is_punct(tok, "?") then
            out[#out + 1] = { type = "op", prec = 1, text = "?" }
        elseif is_punct(tok, ":") then
            out[#out + 1] = { type = "op", prec = 1, text = ":" }
        elseif is_punct(tok, "||") then
            out[#out + 1] = { type = "op", prec = 2, text = "||" }
        elseif is_punct(tok, "&&") then
            out[#out + 1] = { type = "op", prec = 3, text = "&&" }
        elseif is_punct(tok, "|") then
            out[#out + 1] = { type = "op", prec = 4, text = "|" }
        elseif is_punct(tok, "^") then
            out[#out + 1] = { type = "op", prec = 5, text = "^" }
        elseif is_punct(tok, "&") then
            out[#out + 1] = { type = "op", prec = 6, text = "&" }
        elseif is_punct(tok, "==") then
            out[#out + 1] = { type = "op", prec = 7, text = "==" }
        elseif is_punct(tok, "!=") then
            out[#out + 1] = { type = "op", prec = 7, text = "!=" }
        elseif is_punct(tok, "<") then
            out[#out + 1] = { type = "op", prec = 8, text = "<" }
        elseif is_punct(tok, ">") then
            out[#out + 1] = { type = "op", prec = 8, text = ">" }
        elseif is_punct(tok, "<=") then
            out[#out + 1] = { type = "op", prec = 8, text = "<=" }
        elseif is_punct(tok, ">=") then
            out[#out + 1] = { type = "op", prec = 8, text = ">=" }
        elseif is_punct(tok, "<<") then
            out[#out + 1] = { type = "op", prec = 9, text = "<<" }
        elseif is_punct(tok, ">>") then
            out[#out + 1] = { type = "op", prec = 9, text = ">>" }
        elseif is_punct(tok, "+") then
            out[#out + 1] = { type = "op", prec = 10, text = "+" }
        elseif is_punct(tok, "-") then
            out[#out + 1] = { type = "op", prec = 10, text = "-" }
        elseif is_punct(tok, "*") then
            out[#out + 1] = { type = "op", prec = 11, text = "*" }
        elseif is_punct(tok, "/") then
            out[#out + 1] = { type = "op", prec = 11, text = "/" }
        elseif is_punct(tok, "%") then
            out[#out + 1] = { type = "op", prec = 11, text = "%" }
        elseif is_punct(tok, "~") then
            out[#out + 1] = { type = "unary", prec = 12, text = "~" }
        elseif is_punct(tok, "!") then
            out[#out + 1] = { type = "unary", prec = 12, text = "!" }
        elseif tok._variant == "CTokNewline" or tok._variant == "CTokEOF" then
            -- skip
        else
            -- Unknown token -> skip
        end
    end
    return out
end

-- Apply a binary operator.
local function apply_binop(op, a, b)
    a = a % 2^64
    b = b % 2^64
    if op == "+" then return (a + b) % 2^64 end
    if op == "-" then return (a - b) % 2^64 end
    if op == "*" then return (a * b) % 2^64 end
    if op == "/" then
        if b == 0 then return 0 end
        return math.floor(a / b) % 2^64
    end
    if op == "%" then
        if b == 0 then return 0 end
        return (a % b) % 2^64
    end
    if op == "<<" then return (bit.lshift(a, b)) % 2^64 end
    if op == ">>" then return (bit.rshift(a, b)) % 2^64 end
    if op == "<" then
        local sa = a >= 2^63 and (a - 2^64) or a
        local sb = b >= 2^63 and (b - 2^64) or b
        return sa < sb and 1 or 0
    end
    if op == ">" then
        local sa = a >= 2^63 and (a - 2^64) or a
        local sb = b >= 2^63 and (b - 2^64) or b
        return sa > sb and 1 or 0
    end
    if op == "<=" then
        local sa = a >= 2^63 and (a - 2^64) or a
        local sb = b >= 2^63 and (b - 2^64) or b
        return sa <= sb and 1 or 0
    end
    if op == ">=" then
        local sa = a >= 2^63 and (a - 2^64) or a
        local sb = b >= 2^63 and (b - 2^64) or b
        return sa >= sb and 1 or 0
    end
    if op == "==" then return a == b and 1 or 0 end
    if op == "!=" then return a ~= b and 1 or 0 end
    if op == "&" then return bit.band(a, b) end
    if op == "|" then return bit.bor(a, b) end
    if op == "^" then return bit.bxor(a, b) end
    if op == "&&" then return (a ~= 0 and b ~= 0) and 1 or 0 end
    if op == "||" then return (a ~= 0 or b ~= 0) and 1 or 0 end
    return 0
end

-- Apply a unary operator.
local function apply_unary(op, a)
    a = a % 2^64
    if op == "+" then return a end
    if op == "-" then return (-a) % 2^64 end
    if op == "~" then return bit.bnot(a) % 2^64 end
    if op == "!" then return (a == 0) and 1 or 0 end
    return a
end

-- Evaluate a pre-tokenized expression using precedence climbing.
local function eval_expr_tokens(toks, idx)
    local function primary(idx)
        if idx > #toks then return 0, idx end
        local t = toks[idx]
        if t.type == "num" then
            return t.val % 2^64, idx + 1
        end
        if t.type == "lp" then
            local val, ni = eval_ternary(idx + 1)
            if ni <= #toks and toks[ni].type == "rp" then
                return val, ni + 1
            end
            return 0, ni
        end
        if t.type == "unary" then
            local val, ni = primary(idx + 1)
            return apply_unary(t.text, val), ni
        end
        return 0, idx + 1
    end

    local function unary(idx)
        if idx > #toks then return 0, idx end
        local t = toks[idx]
        if t.type == "unary" then
            local val, ni = unary(idx + 1)
            return apply_unary(t.text, val), ni
        end
        return primary(idx)
    end

    local function binary(idx, min_prec)
        local left, ni = unary(idx)
        while ni <= #toks do
            local t = toks[ni]
            if t.type ~= "op" then break end
            if t.prec < min_prec then break end
            if t.text == "?" then
                local then_val, ni2 = eval_ternary(ni + 1)
                if ni2 <= #toks and toks[ni2].type == "op" and toks[ni2].text == ":" then
                    local else_val, ni3 = eval_ternary(ni2 + 1)
                    left = (left ~= 0) and then_val or else_val
                    ni = ni3
                else
                    ni = ni2
                end
            else
                local op = t.text
                local right, ni2 = binary(ni + 1, min_prec + 1)
                left = apply_binop(op, left, right)
                ni = ni2
            end
        end
        return left, ni
    end

    local function eval_ternary(idx)
        return binary(idx, 1)
    end

    local val, _ = eval_ternary(idx)
    return val % 2^64
end

-- Full #if expression evaluator:
-- 1. Macro-expand tokens
-- 2. Pre-process "defined" operator
-- 3. Evaluate the resulting expression
local function eval_if(tokens, macro_table, disabled, line_counter_ref, file_uri_ref)
    local expanded = expand_if_tokens(tokens, macro_table, disabled, line_counter_ref, file_uri_ref)
    local with_defined = preprocess_defined(expanded, macro_table)
    local toks = tokenize_expr(with_defined)
    if #toks == 0 then return 0 end
    return eval_expr_tokens(toks, 1)
end

-----------------------------------------------------------------------------
-- Macro expansion engine
-----------------------------------------------------------------------------

-- Collect function-like macro arguments from a token stream.
-- Returns { args = { { token1, token2, ... }, ... }, next_i = index after closing paren }
local function collect_args(tokens, start_i)
    local args = {}
    local current_arg = {}
    local depth = 0
    local i = start_i

    if i > #tokens or not is_punct(tokens[i], "(") then
        return nil, i
    end
    depth = 1
    i = i + 1

    while i <= #tokens and depth > 0 do
        local tok = tokens[i]
        if is_punct(tok, "(") then
            depth = depth + 1
            if depth > 1 then
                current_arg[#current_arg + 1] = tok
            end
            i = i + 1
        elseif is_punct(tok, ")") then
            depth = depth - 1
            if depth == 0 then
                args[#args + 1] = current_arg
                i = i + 1
                break
            end
            current_arg[#current_arg + 1] = tok
            i = i + 1
        elseif is_punct(tok, ",") and depth == 1 then
            args[#args + 1] = current_arg
            current_arg = {}
            i = i + 1
        elseif is_newline(tok) then
            i = i + 1
        else
            current_arg[#current_arg + 1] = tok
            i = i + 1
        end
    end

    return args, i
end

-- Strip newlines from a token list.
local function strip_newlines(toks)
    local out = {}
    for _, tok in ipairs(toks) do
        if not is_newline(tok) then
            out[#out + 1] = tok
        end
    end
    return out
end

-- Get the parameter index for a token, or nil if not a param.
local function param_index(tok, params)
    if is_ident(tok) then
        for i, p in ipairs(params) do
            if tok.name == p then return i end
        end
    end
    return nil
end

-- Fully expand a token list (for argument expansion before substitution).
local function fully_expand_args(tokens, macro_table, disabled, line_counter_ref, file_uri_ref)
    local out = {}
    for _, tok in ipairs(tokens) do
        if is_ident(tok) and not disabled[tok.name] then
            local macro = macro_table:lookup(tok.name)
            if macro and macro.kind == "object" then
                local new_disabled = {}
                for k, v in pairs(disabled) do new_disabled[k] = v end
                new_disabled[tok.name] = true
                local expanded = fully_expand_args(macro.body, macro_table, new_disabled,
                                                   line_counter_ref, file_uri_ref)
                for _, et in ipairs(expanded) do
                    out[#out + 1] = et
                end
            elseif macro and macro.kind == "object_dynamic" then
                local body = macro.dynamic_fn()
                for _, bt in ipairs(body) do
                    out[#out + 1] = bt
                end
            else
                out[#out + 1] = tok
            end
        else
            out[#out + 1] = tok
        end
    end
    return out
end

-- Stringify a list of tokens: turn them into a single string literal token.
local function stringify_tokens(toks)
    local parts = {}
    for i, tok in ipairs(toks) do
        if i > 1 then
            parts[#parts + 1] = " "
        end
        parts[#parts + 1] = token_text(tok)
    end
    local str = table.concat(parts)
    return { _variant = "CTokStringLiteral", raw = str, prefix = "" }
end

-- Expand a function-like macro body (after args have been collected).
-- Phases:
--   1. # stringification
--   2. Parameter substitution (with expansion for non-##-adjacent params)
--   3. ## token pasting (with GCC ,##__VA_ARGS__ extension)
--   4. Rescan
local function expand_function_like(macro, macro_name, args, macro_table, disabled,
                                     line_counter_ref, file_uri_ref)
    local new_disabled = {}
    for k, v in pairs(disabled) do new_disabled[k] = v end
    new_disabled[macro_name] = true

    local params = macro.params or {}
    local variadic = macro.variadic or false
    local body = copy_token_list(macro.body)

    -- Phase 1: # stringification
    local phase1 = {}
    local j = 1
    while j <= #body do
        if is_punct(body[j], "#") and j + 1 <= #body then
            local next_tok = body[j + 1]
            local pi = param_index(next_tok, params)
            if pi then
                local arg_toks = args[pi] or {}
                phase1[#phase1 + 1] = stringify_tokens(arg_toks)
                j = j + 2
            elseif is_ident(next_tok) and next_tok.name == "__VA_ARGS__" and variadic then
                local va_args = args[#args] or {}
                phase1[#phase1 + 1] = stringify_tokens(va_args)
                j = j + 2
            else
                phase1[#phase1 + 1] = body[j]
                j = j + 1
            end
        else
            phase1[#phase1 + 1] = body[j]
            j = j + 1
        end
    end

    -- Phase 2: Parameter substitution
    local paste_positions = {}
    for j = 1, #phase1 do
        if is_punct(phase1[j], "##") then
            paste_positions[j] = true
        end
    end

    local function is_adjacent_to_paste(j)
        if paste_positions[j - 1] then return true end
        if paste_positions[j + 1] then return true end
        return false
    end

    local phase2 = {}
    for j = 1, #phase1 do
        local tok = phase1[j]
        if is_punct(tok, "##") then
            phase2[#phase2 + 1] = tok
        else
            local pi = param_index(tok, params)
            if pi then
                local arg_toks = args[pi] or {}
                if is_adjacent_to_paste(j) then
                    local clean = strip_newlines(arg_toks)
                    for _, at in ipairs(clean) do
                        phase2[#phase2 + 1] = at
                    end
                else
                    local expanded = fully_expand_args(arg_toks, macro_table, disabled,
                                                       line_counter_ref, file_uri_ref)
                    for _, et in ipairs(expanded) do
                        phase2[#phase2 + 1] = et
                    end
                end
            elseif is_ident(tok) and tok.name == "__VA_ARGS__" and variadic then
                local va_args = args[#args] or {}
                -- GCC `,##__VA_ARGS__` extension.
                -- Detect pattern: comma at phase1[j-2], ## at phase1[j-1], __VA_ARGS__ at phase1[j].
                if paste_positions[j - 1] and (j - 2) >= 1 and is_punct(phase1[j - 2], ",") then
                    if #va_args == 0 then
                        -- Empty VA: remove both the comma and ## from phase2
                        if #phase2 >= 2 and is_punct(phase2[#phase2], "##") then
                            phase2[#phase2] = nil
                        end
                        if #phase2 >= 1 and is_punct(phase2[#phase2], ",") then
                            phase2[#phase2] = nil
                        end
                    else
                        -- Non-empty VA: keep comma, remove ##, insert va_args without pasting
                        if #phase2 >= 1 and is_punct(phase2[#phase2], "##") then
                            phase2[#phase2] = nil
                        end
                        local clean = strip_newlines(va_args)
                        for _, at in ipairs(clean) do
                            phase2[#phase2 + 1] = at
                        end
                    end
                elseif is_adjacent_to_paste(j) then
                    local clean = strip_newlines(va_args)
                    for _, at in ipairs(clean) do
                        phase2[#phase2 + 1] = at
                    end
                else
                    local expanded = fully_expand_args(va_args, macro_table, disabled,
                                                       line_counter_ref, file_uri_ref)
                    for _, et in ipairs(expanded) do
                        phase2[#phase2 + 1] = et
                    end
                end
            else
                phase2[#phase2 + 1] = tok
            end
        end
    end

    -- Phase 3: ## token pasting
    local phase3 = {}
    j = 1
    while j <= #phase2 do
        if is_punct(phase2[j], "##") then
            local next_tok = phase2[j + 1]
            j = j + 2
            if next_tok then
                local left_tok = phase3[#phase3]
                if left_tok then
                    local combined = token_from_text(token_text(left_tok) .. token_text(next_tok))
                    if combined then
                        phase3[#phase3] = combined
                    end
                else
                    phase3[#phase3 + 1] = next_tok
                end
            end
        else
            phase3[#phase3 + 1] = phase2[j]
            j = j + 1
        end
    end

    -- Phase 4: Rescan with this macro disabled
    return expand_token_list(phase3, macro_table, new_disabled,
                             line_counter_ref, file_uri_ref)
end

-- Expand a list of tokens using the macro table and disabled set.
-- Returns an array of tokens (plain token objects, no spans).
function expand_token_list(tokens, macro_table, disabled, line_counter_ref, file_uri_ref)
    local result = {}
    local i = 1
    while i <= #tokens do
        local tok = tokens[i]
        if is_ident(tok) and not disabled[tok.name] then
            local macro = macro_table:lookup(tok.name)
            if macro then
                if macro.kind == "object" then
                    local new_disabled = {}
                    for k, v in pairs(disabled) do new_disabled[k] = v end
                    new_disabled[tok.name] = true
                    local expanded = expand_token_list(macro.body, macro_table,
                                                       new_disabled,
                                                       line_counter_ref, file_uri_ref)
                    for _, et in ipairs(expanded) do
                        result[#result + 1] = et
                    end
                    i = i + 1
                elseif macro.kind == "object_dynamic" then
                    local body = macro.dynamic_fn()
                    local new_disabled = {}
                    for k, v in pairs(disabled) do new_disabled[k] = v end
                    new_disabled[tok.name] = true
                    local expanded = expand_token_list(body, macro_table,
                                                       new_disabled,
                                                       line_counter_ref, file_uri_ref)
                    for _, et in ipairs(expanded) do
                        result[#result + 1] = et
                    end
                    i = i + 1
                else
                    -- Function-like: check for ( after skipping newlines
                    local look = i + 1
                    while look <= #tokens and is_newline(tokens[look]) do
                        look = look + 1
                    end
                    if look <= #tokens and is_punct(tokens[look], "(") then
                        local args, next_i = collect_args(tokens, look)
                        if args then
                            local expanded = expand_function_like(macro, tok.name, args,
                                                                  macro_table, disabled,
                                                                  line_counter_ref, file_uri_ref)
                            for _, et in ipairs(expanded) do
                                result[#result + 1] = et
                            end
                            i = next_i
                        else
                            result[#result + 1] = tok
                            i = i + 1
                        end
                    else
                        result[#result + 1] = tok
                        i = i + 1
                    end
                end
            else
                result[#result + 1] = tok
                i = i + 1
            end
        else
            result[#result + 1] = tok
            i = i + 1
        end
    end
    return result
end

-----------------------------------------------------------------------------
-- Directive parsing helpers
-----------------------------------------------------------------------------

-- Parse a #define directive. Updates macro_table.
local function parse_define(tokens, spans, macro_table, line_counter_ref, file_uri_ref)
    local i = 2  -- skip CTokDirective

    while i <= #tokens and is_newline(tokens[i]) do i = i + 1 end
    if i > #tokens or not is_ident(tokens[i]) then
        return
    end
    local name = tokens[i].name
    i = i + 1

    while i <= #tokens and is_newline(tokens[i]) do i = i + 1 end

    local is_func_like = false
    local params = {}
    local variadic = false

    if i <= #tokens and is_punct(tokens[i], "(") then
        -- Determine function-like by checking if `(` is adjacent to macro name
        -- (no whitespace between name and paren in source).
        local name_idx = nil
        for j = 2, #tokens do
            if is_ident(tokens[j]) and tokens[j].name == name then
                name_idx = j
                break
            end
        end
        if name_idx and spans[name_idx] and spans[i] then
            if spans[name_idx].stop_offset + 1 == spans[i].start_offset then
                is_func_like = true
            end
        end

        if is_func_like then
            i = i + 1  -- skip (
            while i <= #tokens and is_newline(tokens[i]) do i = i + 1 end

            if i > #tokens then return end

            if is_punct(tokens[i], "...") then
                variadic = true
                i = i + 1
                while i <= #tokens and is_newline(tokens[i]) do i = i + 1 end
                if i <= #tokens and is_punct(tokens[i], ")") then
                    i = i + 1
                end
            else
                while i <= #tokens do
                    while i <= #tokens and is_newline(tokens[i]) do i = i + 1 end
                    if i > #tokens then break end

                    if is_punct(tokens[i], "...") then
                        variadic = true
                        i = i + 1
                        break
                    end

                    if is_punct(tokens[i], ")") then
                        i = i + 1
                        break
                    end

                    if is_ident(tokens[i]) then
                        params[#params + 1] = tokens[i].name
                        i = i + 1
                    elseif is_punct(tokens[i], ",") then
                        i = i + 1
                    else
                        i = i + 1
                    end
                end

                if variadic then
                    while i <= #tokens and is_newline(tokens[i]) do i = i + 1 end
                    if i <= #tokens and is_punct(tokens[i], ")") then
                        i = i + 1
                    end
                end
            end
        end
    end

    -- Collect body tokens
    local body = {}
    while i <= #tokens do
        if not is_newline(tokens[i]) then
            body[#body + 1] = tokens[i]
        end
        i = i + 1
    end

    if is_func_like then
        macro_table:add(name, {
            kind = "function",
            params = params,
            variadic = variadic,
            body = body,
        })
    else
        macro_table:add(name, {
            kind = "object",
            body = body,
        })
    end
end

-- Parse a #include directive. Returns { kind, path } or nil.
local function parse_include(tokens, spans)
    local i = 2
    while i <= #tokens and is_newline(tokens[i]) do i = i + 1 end
    if i > #tokens then return nil end

    local tok = tokens[i]

    -- Angle include: <path>
    if tok._variant == "CTokPunct" and tok.text == "<" then
        local path_parts = {}
        i = i + 1
        while i <= #tokens do
            if is_newline(tokens[i]) then
                i = i + 1
            elseif tokens[i]._variant == "CTokPunct" and tokens[i].text == ">" then
                i = i + 1
                break
            else
                path_parts[#path_parts + 1] = token_text(tokens[i])
                i = i + 1
            end
        end
        return { kind = "angle", path = table.concat(path_parts) }
    end

    -- Quoted include: "path".  Lexer keeps the quotes in tok.raw; VFS
    -- resolution expects the path payload.
    if tok._variant == "CTokStringLiteral" then
        local raw = tok.raw or ""
        local path = raw
        if #raw >= 2 and raw:sub(1, 1) == '"' and raw:sub(#raw, #raw) == '"' then
            path = raw:sub(2, #raw - 1)
        end
        return { kind = "quoted", path = path }
    end

    return nil
end

-- Resolve an include via VFS.
local function resolve_include(inc, vfs, current_dir)
    if not vfs or not vfs.resolve_include then
        return nil, "no VFS provider"
    end
    local resolved_path, content = vfs.resolve_include(inc.kind, inc.path, current_dir)
    if not resolved_path then
        return nil, "cannot find include: " .. inc.kind .. " " .. inc.path
    end
    return resolved_path, content
end

-- Deep copy a span (for output).
local function copy_span(sp)
    if not sp then
        return { uri = "<unknown>", start_offset = 0, stop_offset = 0 }
    end
    return { uri = sp.uri, start_offset = sp.start_offset, stop_offset = sp.stop_offset }
end

-----------------------------------------------------------------------------
-- Internal processing core (shared state across recursive includes)
-----------------------------------------------------------------------------

-- Process a token stream with shared preprocessor state.
-- state: { macro_table, line_counter_ref, file_uri_ref, cond_stack, include_stack, vfs, out_issues }
local function process_file(tokens, spans, state)
    local macro_table = state.macro_table
    local line_counter_ref = state.line_counter_ref
    local file_uri_ref = state.file_uri_ref
    local cond_stack = state.cond_stack
    local include_stack = state.include_stack
    local vfs = state.vfs
    local out_issues = state.issues

    local out_tokens = {}
    local out_spans = {}

    local function is_active()
        if #cond_stack == 0 then return true end
        return cond_stack[#cond_stack].active
    end

    local i = 1
    while i <= #tokens do
        local tok = tokens[i]
        local sp = spans[i] or {}

        -- Track line number
        if is_newline(tok) then
            line_counter_ref.n = line_counter_ref.n + 1
        end

        if is_directive(tok) then
            local dkind = dir_kind(tok)

            -- Collect tokens on this directive line (excludes trailing newline)
            local dir_tokens = {}
            local dir_spans = {}
            local j = i
            while j <= #tokens do
                if is_newline(tokens[j]) then break end
                if is_eof(tokens[j]) then break end
                dir_tokens[#dir_tokens + 1] = tokens[j]
                dir_spans[#dir_spans + 1] = spans[j]
                j = j + 1
            end

            if dkind == "CDirDefine" then
                if is_active() then
                    parse_define(dir_tokens, dir_spans, macro_table, line_counter_ref, file_uri_ref)
                end

            elseif dkind == "CDirUndef" then
                if is_active() then
                    local k = 2
                    while k <= #dir_tokens and is_newline(dir_tokens[k]) do k = k + 1 end
                    if k <= #dir_tokens and is_ident(dir_tokens[k]) then
                        macro_table:remove(dir_tokens[k].name)
                    end
                end

            elseif dkind == "CDirInclude" then
                if is_active() then
                    local inc = parse_include(dir_tokens, dir_spans)
                    if inc then
                        local current_dir = nil
                        if file_uri_ref.s then
                            local uri_str = file_uri_ref.s
                            local last_slash = uri_str:match("^(.+)/[^/]*$")
                            if last_slash then
                                current_dir = last_slash
                            end
                        end

                        local resolved_path, content = resolve_include(inc, vfs, current_dir)
                        if resolved_path then
                            if include_stack[resolved_path] then
                                out_issues[#out_issues + 1] = {
                                    message = "recursive #include of " .. resolved_path,
                                    offset = sp.start_offset or 0,
                                }
                            else
                                include_stack[resolved_path] = true

                                local lexer = require("moonlift.c.c_lexer")
                                local lex_result = lexer.lex(content or "", resolved_path)
                                local inc_tokens = lex_result.tokens
                                local inc_spans = lex_result.spans
                                local inc_issues = lex_result.issues

                                for _, iss in ipairs(inc_issues) do
                                    out_issues[#out_issues + 1] = iss
                                end

                                local saved_uri = file_uri_ref.s
                                local saved_line = line_counter_ref.n

                                file_uri_ref.s = resolved_path
                                line_counter_ref.n = 1

                                local exp_result = process_file(inc_tokens, inc_spans, state)

                                line_counter_ref.n = saved_line
                                file_uri_ref.s = saved_uri

                                for idx, et in ipairs(exp_result.tokens) do
                                    -- Included files have their own EOF sentinel; keep only
                                    -- the translation unit's final EOF, otherwise the C
                                    -- parser stops at the end of the first include.
                                    if not is_eof(et) then
                                        out_tokens[#out_tokens + 1] = et
                                        out_spans[#out_spans + 1] = exp_result.spans[idx]
                                    end
                                end

                                include_stack[resolved_path] = nil
                            end
                        else
                            out_issues[#out_issues + 1] = {
                                message = "cannot find include file: " .. (inc.path or "?"),
                                offset = sp.start_offset or 0,
                            }
                        end
                    else
                        out_issues[#out_issues + 1] = {
                            message = "malformed #include directive",
                            offset = sp.start_offset or 0,
                        }
                    end
                end

            elseif dkind == "CDirIf" then
                if is_active() then
                    local cond_tokens = {}
                    for k = 2, #dir_tokens do
                        if not is_newline(dir_tokens[k]) then
                            cond_tokens[#cond_tokens + 1] = dir_tokens[k]
                        end
                    end
                    local result = eval_if(cond_tokens, macro_table, {},
                                           line_counter_ref, file_uri_ref)
                    local was_true = result ~= 0
                    cond_stack[#cond_stack + 1] = {
                        active = was_true,
                        was_true = was_true,
                        else_seen = false,
                    }
                else
                    cond_stack[#cond_stack + 1] = {
                        active = false, was_true = false, else_seen = false,
                    }
                end

            elseif dkind == "CDirIfdef" then
                if is_active() then
                    local k = 2
                    while k <= #dir_tokens and is_newline(dir_tokens[k]) do k = k + 1 end
                    local name = (k <= #dir_tokens and is_ident(dir_tokens[k])) and dir_tokens[k].name or ""
                    local defined = macro_table:lookup(name) ~= nil
                    cond_stack[#cond_stack + 1] = {
                        active = defined, was_true = defined, else_seen = false,
                    }
                else
                    cond_stack[#cond_stack + 1] = {
                        active = false, was_true = false, else_seen = false,
                    }
                end

            elseif dkind == "CDirIfndef" then
                if is_active() then
                    local k = 2
                    while k <= #dir_tokens and is_newline(dir_tokens[k]) do k = k + 1 end
                    local name = (k <= #dir_tokens and is_ident(dir_tokens[k])) and dir_tokens[k].name or ""
                    local defined = macro_table:lookup(name) ~= nil
                    cond_stack[#cond_stack + 1] = {
                        active = not defined, was_true = not defined, else_seen = false,
                    }
                else
                    cond_stack[#cond_stack + 1] = {
                        active = false, was_true = false, else_seen = false,
                    }
                end

            elseif dkind == "CDirElif" then
                if #cond_stack == 0 then
                    out_issues[#out_issues + 1] = {
                        message = "#elif without #if",
                        offset = sp.start_offset or 0,
                    }
                elseif cond_stack[#cond_stack].else_seen then
                    out_issues[#out_issues + 1] = {
                        message = "#elif after #else",
                        offset = sp.start_offset or 0,
                    }
                else
                    local top = cond_stack[#cond_stack]
                    if top.was_true then
                        top.active = false
                    else
                        local cond_tokens = {}
                        for k = 2, #dir_tokens do
                            if not is_newline(dir_tokens[k]) then
                                cond_tokens[#cond_tokens + 1] = dir_tokens[k]
                            end
                        end
                        local result = eval_if(cond_tokens, macro_table, {},
                                               line_counter_ref, file_uri_ref)
                        local now_true = result ~= 0
                        top.active = now_true
                        if now_true then
                            top.was_true = true
                        end
                    end
                end

            elseif dkind == "CDirElse" then
                if #cond_stack == 0 then
                    out_issues[#out_issues + 1] = {
                        message = "#else without #if",
                        offset = sp.start_offset or 0,
                    }
                elseif cond_stack[#cond_stack].else_seen then
                    out_issues[#out_issues + 1] = {
                        message = "duplicate #else",
                        offset = sp.start_offset or 0,
                    }
                else
                    local top = cond_stack[#cond_stack]
                    top.else_seen = true
                    top.active = not top.was_true
                end

            elseif dkind == "CDirEndif" then
                if #cond_stack == 0 then
                    out_issues[#out_issues + 1] = {
                        message = "#endif without #if",
                        offset = sp.start_offset or 0,
                    }
                else
                    table.remove(cond_stack)
                end

            elseif dkind == "CDirError" then
                if is_active() then
                    local msg_parts = {}
                    for k = 2, #dir_tokens do
                        if not is_newline(dir_tokens[k]) then
                            msg_parts[#msg_parts + 1] = token_text(dir_tokens[k])
                        end
                    end
                    out_issues[#out_issues + 1] = {
                        message = "#error: " .. table.concat(msg_parts, " "),
                        offset = sp.start_offset or 0,
                    }
                end

            elseif dkind == "CDirPragma" then
                -- silently ignore

            elseif dkind == "CDirLine" then
                if is_active() then
                    local k = 2
                    while k <= #dir_tokens and is_newline(dir_tokens[k]) do k = k + 1 end
                    if k <= #dir_tokens and dir_tokens[k]._variant == "CTokIntLiteral" then
                        local new_line = tonumber(dir_tokens[k].raw)
                        if new_line then
                            line_counter_ref.n = new_line
                        end
                        k = k + 1
                        while k <= #dir_tokens and is_newline(dir_tokens[k]) do k = k + 1 end
                        if k <= #dir_tokens and dir_tokens[k]._variant == "CTokStringLiteral" then
                            file_uri_ref.s = dir_tokens[k].raw
                        end
                    end
                end
            end

            -- Advance past directive line
            i = j

        else
            -- Non-directive token
            if is_active() and not is_newline(tok) and not is_eof(tok) then
                -- Accumulate a run of non-directive tokens for macro expansion
                local run_start = i
                while i <= #tokens and not is_directive(tokens[i]) and not is_newline(tokens[i]) do
                    i = i + 1
                end

                local run_tokens = {}
                for k = run_start, i - 1 do
                    run_tokens[#run_tokens + 1] = tokens[k]
                end

                local expanded = expand_token_list(run_tokens, macro_table, {},
                                                   line_counter_ref, file_uri_ref)
                for _, et in ipairs(expanded) do
                    out_tokens[#out_tokens + 1] = et
                    out_spans[#out_spans + 1] = {
                        uri = file_uri_ref.s,
                        start_offset = 0,
                        stop_offset = 0,
                    }
                end

            elseif is_active() and is_newline(tok) then
                out_tokens[#out_tokens + 1] = tok
                out_spans[#out_spans + 1] = copy_span(sp)
                i = i + 1

            elseif is_eof(tok) then
                out_tokens[#out_tokens + 1] = tok
                out_spans[#out_spans + 1] = copy_span(sp)
                i = i + 1

            else
                i = i + 1
            end
        end
    end

    return { tokens = out_tokens, spans = out_spans }
end

-----------------------------------------------------------------------------
-- Public API
-----------------------------------------------------------------------------

function M.Define(T)
    local CA = T.MoonCAst
    local Source = T.MoonSource

    function M.expand(tokens, spans, issues, vfs, include_dir)
        local line_counter_ref = { n = 1, counter_val = 0 }
        local file_uri_ref = { s = (spans[1] and spans[1].uri) or "<source>" }

        local state = {
            macro_table = make_macro_table(line_counter_ref, file_uri_ref),
            line_counter_ref = line_counter_ref,
            file_uri_ref = file_uri_ref,
            cond_stack = {},
            include_stack = {},
            vfs = vfs,
            issues = issues,
        }

        local result = process_file(tokens, spans, state)

        -- Check for unterminated conditionals
        if #state.cond_stack > 0 then
            issues[#issues + 1] = {
                message = "unterminated #if/#ifdef/#ifndef block",
            }
        end

        return {
            tokens = result.tokens,
            spans = result.spans,
            issues = issues,
        }
    end

    return { expand = M.expand }
end

return M
