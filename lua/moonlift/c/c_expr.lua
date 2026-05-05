-- c_expr.lua -- C99 expression parser (precedence-based recursive descent)
-- All functions operate on a CParser state { tokens, spans, pos, issues, typedefs }.

local M = {}

function M.Define(T)
    local CA = T.MoonCAst
    local c_decl = require("moonlift.c.c_decl").Define(T)

    ------------------------------------------------------------------------
    -- Helpers
    ------------------------------------------------------------------------

    local function peek(p)
        return p.tokens[p.pos]
    end

    local function advance(p)
        local t = p.tokens[p.pos]
        p.pos = p.pos + 1
        return t
    end

    local function skip_newlines(p)
        while peek(p) and peek(p)._variant == "CTokNewline" do
            p.pos = p.pos + 1
        end
    end

    local function tok_v(p, variant_name)
        local t = peek(p)
        return t ~= nil and t._variant == variant_name
    end

    local function tok_kw(p, kw_variant)
        local t = peek(p)
        return t ~= nil and t._variant == "CTokKeyword" and t.kw._variant == kw_variant
    end

    local function tok_punct(p, text)
        local t = peek(p)
        return t ~= nil and t._variant == "CTokPunct" and t.text == text
    end

    local function expect_punct(p, text)
        local t = peek(p)
        if t and t._variant == "CTokPunct" and t.text == text then
            p.pos = p.pos + 1
            return t
        end
        local msg = "expected '" .. text .. "'"
        local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
        table.insert(p.issues, { message = msg, offset = off, line = 1, col = 1 })
        return nil
    end

    ------------------------------------------------------------------------
    -- String literal concatenation
    ------------------------------------------------------------------------

    -- Consume adjacent string literals and combine them into one.
    -- Returns the combined string literal ASDL node, or nil if no string at current pos.
    local function parse_string_literal(p)
        if not tok_v(p, "CTokStringLiteral") then return nil end
        local combined_raw = ""
        while tok_v(p, "CTokStringLiteral") do
            local tok = advance(p)
            combined_raw = combined_raw .. tok.raw:sub(2, #tok.raw - 1) -- strip quotes
        end
        return { _variant = "CEStrLit", raw = combined_raw }
    end

    ------------------------------------------------------------------------
    -- Precedence levels from lowest to highest
    ------------------------------------------------------------------------

    function M.parse_expr(p)
        return M.parse_comma_expr(p)
    end

    -- Level 1: comma operator (left-associative)
    function M.parse_comma_expr(p)
        local left = M.parse_assign_expr(p)
        if not left then return nil end
        while tok_punct(p, ",") do
            advance(p)
            local right = M.parse_assign_expr(p)
            if not right then break end
            left = { _variant = "CEComma", left = left, right = right }
        end
        return left
    end

    -- Level 2: assignment operators (right-associative)
    local assign_ops = {
        ["="] = "CAssign",    ["+="] = "CAddAssign", ["-="] = "CSubAssign",
        ["*="] = "CMulAssign", ["/="] = "CDivAssign", ["%="] = "CModAssign",
        ["<<="] = "CShlAssign", [">>="] = "CShrAssign",
        ["&="] = "CAndAssign", ["^="] = "CXorAssign", ["|="] = "COrAssign",
    }

    function M.parse_assign_expr(p)
        local left = M.parse_ternary_expr(p)
        if not left then return nil end
        local t = peek(p)
        if t and t._variant == "CTokPunct" and assign_ops[t.text] then
            local op_variant = assign_ops[t.text]
            advance(p)
            local right = M.parse_assign_expr(p) -- right-associative
            if not right then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after assignment operator", offset = off, line = 1, col = 1 })
                return left
            end
            return { _variant = "CEAssign", op = { _variant = op_variant }, left = left, right = right }
        end
        return left
    end

    -- Level 3: ternary conditional (right-associative)
    function M.parse_ternary_expr(p)
        local cond = M.parse_log_or_expr(p)
        if not cond then return nil end
        if tok_punct(p, "?") then
            advance(p)
            local then_expr = M.parse_expr(p) -- parse full expr (comma allowed between ? and :)
            if not then_expr then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression in ternary", offset = off, line = 1, col = 1 })
                return cond
            end
            if not expect_punct(p, ":") then
                return cond
            end
            local else_expr = M.parse_ternary_expr(p) -- right-associative
            if not else_expr then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after ':' in ternary", offset = off, line = 1, col = 1 })
                return cond
            end
            return { _variant = "CETernary", cond = cond, then_expr = then_expr, else_expr = else_expr }
        end
        return cond
    end

    -- Level 4: logical OR (left-associative)
    function M.parse_log_or_expr(p)
        local left = M.parse_log_and_expr(p)
        if not left then return nil end
        while tok_punct(p, "||") do
            advance(p)
            local right = M.parse_log_and_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = "CBinLogOr" }, left = left, right = right }
        end
        return left
    end

    -- Level 5: logical AND (left-associative)
    function M.parse_log_and_expr(p)
        local left = M.parse_bit_or_expr(p)
        if not left then return nil end
        while tok_punct(p, "&&") do
            advance(p)
            local right = M.parse_bit_or_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = "CBinLogAnd" }, left = left, right = right }
        end
        return left
    end

    -- Level 6: bitwise OR (left-associative)
    function M.parse_bit_or_expr(p)
        local left = M.parse_bit_xor_expr(p)
        if not left then return nil end
        while tok_punct(p, "|") do
            advance(p)
            local right = M.parse_bit_xor_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = "CBinBitOr" }, left = left, right = right }
        end
        return left
    end

    -- Level 7: bitwise XOR (left-associative)
    function M.parse_bit_xor_expr(p)
        local left = M.parse_bit_and_expr(p)
        if not left then return nil end
        while tok_punct(p, "^") do
            advance(p)
            local right = M.parse_bit_and_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = "CBinBitXor" }, left = left, right = right }
        end
        return left
    end

    -- Level 8: bitwise AND (left-associative)
    function M.parse_bit_and_expr(p)
        local left = M.parse_equality_expr(p)
        if not left then return nil end
        while tok_punct(p, "&") do
            advance(p)
            local right = M.parse_equality_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = "CBinBitAnd" }, left = left, right = right }
        end
        return left
    end

    -- Level 9: equality (left-associative)
    function M.parse_equality_expr(p)
        local left = M.parse_relational_expr(p)
        if not left then return nil end
        while tok_punct(p, "==") or tok_punct(p, "!=") do
            local op_text = advance(p).text
            local op = op_text == "==" and "CBinEq" or "CBinNe"
            local right = M.parse_relational_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = op }, left = left, right = right }
        end
        return left
    end

    -- Level 10: relational (left-associative)
    function M.parse_relational_expr(p)
        local left = M.parse_shift_expr(p)
        if not left then return nil end
        while tok_punct(p, "<") or tok_punct(p, "<=") or tok_punct(p, ">") or tok_punct(p, ">=") do
            local op_text = advance(p).text
            local op
            if op_text == "<" then op = "CBinLt"
            elseif op_text == "<=" then op = "CBinLe"
            elseif op_text == ">" then op = "CBinGt"
            else op = "CBinGe" end
            local right = M.parse_shift_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = op }, left = left, right = right }
        end
        return left
    end

    -- Level 11: shift (left-associative)
    function M.parse_shift_expr(p)
        local left = M.parse_additive_expr(p)
        if not left then return nil end
        while tok_punct(p, "<<") or tok_punct(p, ">>") do
            local op_text = advance(p).text
            local op = op_text == "<<" and "CBinShl" or "CBinShr"
            local right = M.parse_additive_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = op }, left = left, right = right }
        end
        return left
    end

    -- Level 12: additive (left-associative)
    function M.parse_additive_expr(p)
        local left = M.parse_multiplicative_expr(p)
        if not left then return nil end
        while tok_punct(p, "+") or tok_punct(p, "-") do
            local op_text = advance(p).text
            local op = op_text == "+" and "CBinAdd" or "CBinSub"
            local right = M.parse_multiplicative_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = op }, left = left, right = right }
        end
        return left
    end

    -- Level 13: multiplicative (left-associative)
    function M.parse_multiplicative_expr(p)
        local left = M.parse_cast_expr(p)
        if not left then return nil end
        while tok_punct(p, "*") or tok_punct(p, "/") or tok_punct(p, "%") do
            local op_text = advance(p).text
            local op
            if op_text == "*" then op = "CBinMul"
            elseif op_text == "/" then op = "CBinDiv"
            else op = "CBinMod" end
            local right = M.parse_cast_expr(p)
            if not right then break end
            left = { _variant = "CEBinary", op = { _variant = op }, left = left, right = right }
        end
        return left
    end

    -- Level 14: cast and unary (right-associative)
    function M.parse_cast_expr(p)
        -- A cast expression is: (type_name) cast_expr
        -- To distinguish from parenthesized expression, we check if the
        -- tokens after ( form a valid type name.
        if tok_punct(p, "(") then
            local save = p.pos
            advance(p) -- consume '('

            -- Check if we have a type specifier start at this position.
            -- Save position, try to parse a type name, and check if ) follows.
            local after_paren = p.pos
            if c_decl.is_type_spec_start(p) then
                local tn = c_decl.parse_type_name(p)
                if tn and tok_punct(p, ")") then
                    advance(p) -- consume ')'
                    local expr = M.parse_cast_expr(p) -- cast applies to next expression
                    if expr then
                        return { _variant = "CECast", type_name = tn, expr = expr }
                    end
                end
            end

            -- Not a cast: restore position and parse as unary expression
            p.pos = save
        end

        return M.parse_unary_expr(p)
    end

    -- Level 14 (continued): unary expressions (right-associative)
    function M.parse_unary_expr(p)
        skip_newlines(p)

        -- Prefix increment/decrement
        if tok_punct(p, "++") then
            advance(p)
            local operand = M.parse_unary_expr(p)
            if not operand then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after '++'", offset = off, line = 1, col = 1 })
                return nil
            end
            return { _variant = "CEPreInc", operand = operand }
        end

        if tok_punct(p, "--") then
            advance(p)
            local operand = M.parse_unary_expr(p)
            if not operand then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after '--'", offset = off, line = 1, col = 1 })
                return nil
            end
            return { _variant = "CEPreDec", operand = operand }
        end

        -- Address-of
        if tok_punct(p, "&") then
            advance(p)
            local operand = M.parse_cast_expr(p)
            if not operand then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after '&'", offset = off, line = 1, col = 1 })
                return nil
            end
            return { _variant = "CEAddrOf", operand = operand }
        end

        -- Dereference
        if tok_punct(p, "*") then
            advance(p)
            local operand = M.parse_cast_expr(p)
            if not operand then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after '*'", offset = off, line = 1, col = 1 })
                return nil
            end
            return { _variant = "CEDeref", operand = operand }
        end

        -- Unary plus
        if tok_punct(p, "+") then
            advance(p)
            local operand = M.parse_cast_expr(p)
            if not operand then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after '+'", offset = off, line = 1, col = 1 })
                return nil
            end
            return { _variant = "CEPlus", operand = operand }
        end

        -- Unary minus
        if tok_punct(p, "-") then
            advance(p)
            local operand = M.parse_cast_expr(p)
            if not operand then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after '-'", offset = off, line = 1, col = 1 })
                return nil
            end
            return { _variant = "CEMinus", operand = operand }
        end

        -- Bitwise NOT
        if tok_punct(p, "~") then
            advance(p)
            local operand = M.parse_cast_expr(p)
            if not operand then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after '~'", offset = off, line = 1, col = 1 })
                return nil
            end
            return { _variant = "CEBitNot", operand = operand }
        end

        -- Logical NOT
        if tok_punct(p, "!") then
            advance(p)
            local operand = M.parse_cast_expr(p)
            if not operand then
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression after '!'", offset = off, line = 1, col = 1 })
                return nil
            end
            return { _variant = "CENot", operand = operand }
        end

        -- sizeof: sizeof expr or sizeof(type)
        if tok_kw(p, "CKwSizeof") then
            advance(p)
            -- sizeof without parentheses: sizeof expr (unary expression)
            -- sizeof with parentheses: could be sizeof(type) or sizeof(expr)
            if tok_punct(p, "(") then
                local save = p.pos
                advance(p) -- consume '('

                -- Try parsing as type name first
                if c_decl.is_type_spec_start(p) then
                    local tn = c_decl.parse_type_name(p)
                    if tn and tok_punct(p, ")") then
                        advance(p) -- consume ')'
                        return { _variant = "CESizeofType", type_name = tn }
                    end
                end

                -- Restore and parse as sizeof(expr)
                p.pos = save
                advance(p) -- consume '('
                local expr = M.parse_expr(p)
                if expr then
                    expect_punct(p, ")")
                end
                if expr then
                    return { _variant = "CESizeofExpr", expr = expr }
                end
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected expression or type in sizeof", offset = off, line = 1, col = 1 })
                return nil
            else
                -- sizeof unary-expression (without parens)
                local operand = M.parse_unary_expr(p)
                if operand then
                    return { _variant = "CESizeofExpr", expr = operand }
                end
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected unary expression after sizeof", offset = off, line = 1, col = 1 })
                return nil
            end
        end

        -- Fall through to postfix expression
        return M.parse_postfix_expr(p)
    end

    -- Level 15: postfix expressions (left-associative)
    function M.parse_postfix_expr(p)
        skip_newlines(p)
        local left = M.parse_primary_expr(p)
        if not left then return nil end

        while peek(p) do
            skip_newlines(p)
            if tok_punct(p, "[") then
                -- Array subscript
                advance(p)
                local index = M.parse_expr(p)
                if index then
                    expect_punct(p, "]")
                    left = { _variant = "CESubscript", base = left, index = index }
                else
                    local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                    table.insert(p.issues, { message = "expected expression in subscript", offset = off, line = 1, col = 1 })
                    break
                end
            elseif tok_punct(p, "(") then
                -- Function call
                advance(p)
                local args = M.parse_argument_list(p)
                expect_punct(p, ")")
                left = { _variant = "CECall", callee = left, args = args }
            elseif tok_punct(p, ".") then
                -- Member access
                advance(p)
                if tok_v(p, "CTokIdent") then
                    local field_name = advance(p).name
                    left = { _variant = "CEDot", base = left, field = field_name }
                else
                    local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                    table.insert(p.issues, { message = "expected field name after '.'", offset = off, line = 1, col = 1 })
                    break
                end
            elseif tok_punct(p, "->") then
                -- Pointer member access
                advance(p)
                if tok_v(p, "CTokIdent") then
                    local field_name = advance(p).name
                    left = { _variant = "CEArrow", base = left, field = field_name }
                else
                    local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                    table.insert(p.issues, { message = "expected field name after '->'", offset = off, line = 1, col = 1 })
                    break
                end
            elseif tok_punct(p, "++") then
                -- Postfix increment
                advance(p)
                left = { _variant = "CEPostInc", operand = left }
            elseif tok_punct(p, "--") then
                -- Postfix decrement
                advance(p)
                left = { _variant = "CEPostDec", operand = left }
            else
                break
            end
        end

        return left
    end

    -- Primary expressions
    function M.parse_primary_expr(p)
        skip_newlines(p)
        local t = peek(p)
        if not t then return nil end

        -- Integer literal
        if t._variant == "CTokIntLiteral" then
            local tok = advance(p)
            return { _variant = "CEIntLit", raw = tok.raw, suffix = tok.suffix or "" }
        end

        -- Float literal
        if t._variant == "CTokFloatLiteral" then
            local tok = advance(p)
            return { _variant = "CEFloatLit", raw = tok.raw, suffix = tok.suffix or "" }
        end

        -- Char literal
        if t._variant == "CTokCharLiteral" then
            local tok = advance(p)
            return { _variant = "CECharLit", raw = tok.raw }
        end

        -- String literal (with concatenation)
        if t._variant == "CTokStringLiteral" then
            return parse_string_literal(p)
        end

        -- Identifier
        if t._variant == "CTokIdent" then
            local tok = advance(p)

            -- Check for C boolean literals (C99 _Bool values come from stdbool.h
            -- macros true/false, but they are identifiers that resolve to 1/0).
            -- We treat them as regular identifiers; upper phases handle them.

            local name = tok.name

            -- Check for compound literal: (type_name){init}
            -- This should not match here -- compound literals are handled in postfix
            -- as (type_name){...} patterns. But if the identifier is followed by
            -- something unexpected, it might be part of a larger construct.

            -- Check for GNU __FUNCTION__ and __func__
            if name == "__func__" or name == "__FUNCTION__" then
                return { _variant = "CEStrLit", raw = name }
            end

            return { _variant = "CEIdent", name = name }
        end

        -- Parenthesized expression or compound literal or GNU statement expression
        if tok_punct(p, "(") then
            local before_paren = p.pos
            advance(p) -- consume '('

            -- GNU statement expression: ({ stmts; expr })
            if tok_punct(p, "{") then
                advance(p) -- consume '{'
                local items = p.parse_block_items(p)
                local result_expr = nil

                -- The last expression statement in a GNU statement expression
                -- provides the result value.
                if #items > 0 then
                    local last = items[#items]
                    if last._variant == "CBlockStmt" and last.stmt._variant == "CSExpr" then
                        result_expr = last.stmt.expr
                    end
                end

                expect_punct(p, "}")
                if not expect_punct(p, ")") then
                    -- Recovery
                end

                return { _variant = "CEStmtExpr", items = items, result = result_expr }
            end

            -- Could be (type_name){ ... } compound literal, or (expr)
            -- Try to parse as type name first.
            local after_paren = p.pos
            if c_decl.is_type_spec_start(p) then
                local tn = c_decl.parse_type_name(p)
                if tn and tok_punct(p, ")") then
                    advance(p) -- consume ')'

                    -- Compound literal: (type_name){ ... }
                    if tok_punct(p, "{") then
                        advance(p) -- consume '{'
                        local init = c_decl.parse_init_list(p)
                        return { _variant = "CECompoundLit", type_name = tn, initializer = init }
                    end

                    -- (type_name) followed by something other than {.
                    -- This is NOT a compound literal. The (type)expr cast form is
                    -- handled in parse_cast_expr, which runs before parse_unary_expr.
                    -- If we are here in parse_primary_expr, it means this (type)
                    -- was NOT meant as a cast, or the type name detection was wrong.
                    -- Restore to '(' and try parsing as parenthesized expression.
                    p.pos = before_paren
                else
                    p.pos = before_paren
                end
            else
                p.pos = before_paren
            end

            -- Parse as parenthesized expression.
            advance(p) -- consume '(' again
            local expr = M.parse_expr(p)
            if expr then
                expect_punct(p, ")")
                return { _variant = "CEParen", expr = expr }
            end

            -- If we couldn't parse anything, it's an error
            local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
            table.insert(p.issues, { message = "expected expression after '('", offset = off, line = 1, col = 1 })
            return nil
        end

        -- Note: compound literal (type_name){init} is handled in postfix parsing
        -- after a parenthesized type name.

        -- No primary expression found
        return nil
    end

    ------------------------------------------------------------------------
    -- Argument list for function calls
    ------------------------------------------------------------------------

    function M.parse_argument_list(p)
        local args = {}
        if tok_punct(p, ")") then
            return args
        end
        while true do
            skip_newlines(p)
            if tok_punct(p, ")") then break end
            local arg = M.parse_assign_expr(p)
            if arg then
                table.insert(args, arg)
            else
                break
            end
            skip_newlines(p)
            if tok_punct(p, ",") then
                advance(p)
            elseif tok_punct(p, ")") then
                break
            else
                break
            end
        end
        return args
    end

    return M
end

return M
