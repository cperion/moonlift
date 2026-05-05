-- c_stmt.lua -- C99 statement parser (recursive descent on CParser state)
-- Produces MoonCAst Stmt ASDL values as plain Lua tables.

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
    -- Main statement dispatch
    ------------------------------------------------------------------------

    function M.parse_stmt(p)
        skip_newlines(p)
        local t = peek(p)
        if not t or t._variant == "CTokEOF" then return nil end

        -- Compound statement
        if tok_punct(p, "{") then
            return M.parse_compound_stmt(p)
        end

        -- Keyword-driven statements
        if t._variant == "CTokKeyword" then
            local kw = t.kw._variant
            if kw == "CKwIf" then
                return M.parse_if_stmt(p)
            elseif kw == "CKwFor" then
                return M.parse_for_stmt(p)
            elseif kw == "CKwWhile" then
                return M.parse_while_stmt(p)
            elseif kw == "CKwDo" then
                return M.parse_do_while_stmt(p)
            elseif kw == "CKwSwitch" then
                return M.parse_switch_stmt(p)
            elseif kw == "CKwGoto" then
                return M.parse_goto_stmt(p)
            elseif kw == "CKwContinue" then
                return M.parse_continue_stmt(p)
            elseif kw == "CKwBreak" then
                return M.parse_break_stmt(p)
            elseif kw == "CKwReturn" then
                return M.parse_return_stmt(p)
            elseif kw == "CKwCase" then
                return M.parse_case_stmt(p)
            elseif kw == "CKwDefault" then
                return M.parse_default_stmt(p)
            end
        end

        -- Labeled statement: identifier : statement
        -- We need to detect this case. Check if we see an identifier followed by :
        -- But we must be careful: ident : could be part of a ternary or a label.
        -- In C, at statement level, identifier : is always a label.
        if tok_v(p, "CTokIdent") then
            local save = p.pos
            local id_tok = peek(p)
            -- Look ahead to see if : follows
            -- Check p.tokens[p.pos + 1] after skipping newlines
            local next_pos = p.pos + 1
            while p.tokens[next_pos] and p.tokens[next_pos]._variant == "CTokNewline" do
                next_pos = next_pos + 1
            end
            if p.tokens[next_pos] and p.tokens[next_pos]._variant == "CTokPunct" and p.tokens[next_pos].text == ":" then
                advance(p) -- consume identifier
                advance(p) -- consume ':'
                local inner = M.parse_stmt(p)
                if not inner then
                    -- Empty statement after label (treat as null statement)
                    inner = { _variant = "CSExpr", expr = nil }
                end
                return { _variant = "CSLabeled", label = id_tok.name, stmt = inner }
            end
        end

        -- Check for declaration (C99 mixed declarations and statements)
        -- A declaration starts with: storage? qualifiers* type_spec
        -- To distinguish from expression, check if the current token starts a type specifier.
        if c_decl.is_type_spec_start(p) then
            -- Try to parse as declaration. This is safe because the declaration
            -- parser will only succeed if it sees a valid type specifier sequence.
            local save = p.pos
            local decl = c_decl.parse_declaration(p)
            if decl then
                return { _variant = "CBlockDecl", decl = decl }
            else
                p.pos = save
            end
        end

        -- Default: expression statement. Try to parse an expression.
        local expr = p.parse_expr(p)
        if expr then
            expect_punct(p, ";")
            return { _variant = "CSExpr", expr = expr }
        end

        -- Empty statement (just ;)
        if tok_punct(p, ";") then
            advance(p)
            return { _variant = "CSExpr", expr = nil }
        end

        return nil
    end

    ------------------------------------------------------------------------
    -- Block items (C99 mixed declarations and statements)
    ------------------------------------------------------------------------

    function M.parse_block_items(p)
        local items = {}
        while peek(p) and not tok_punct(p, "}") and not tok_v(p, "CTokEOF") do
            skip_newlines(p)
            if tok_punct(p, "}") then break end
            if tok_v(p, "CTokEOF") then break end

            local save = p.pos

            -- Try declaration first
            -- A declaration starts with: storage? qualifiers* type_spec
            if tok_kw(p, "CKwTypedef") or tok_kw(p, "CKwExtern")
                or tok_kw(p, "CKwStatic") or tok_kw(p, "CKwAuto") or tok_kw(p, "CKwRegister")
                or c_decl.is_type_spec_start(p) then
                local decl = c_decl.parse_declaration(p)
                if decl then
                    table.insert(items, { _variant = "CBlockDecl", decl = decl })
                    goto continue
                end
                p.pos = save
            end

            -- Try statement
            local stmt = M.parse_stmt(p)
            if stmt then
                table.insert(items, { _variant = "CBlockStmt", stmt = stmt })
                goto continue
            end

            -- Error recovery: skip one token
            local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
            table.insert(p.issues, { message = "expected declaration or statement", offset = off, line = 1, col = 1 })
            advance(p)

            ::continue::
        end
        return items
    end

    function M.parse_compound_stmt(p)
        -- Assumes '{' has NOT been consumed (parse it here)
        advance(p) -- consume '{'
        local items = M.parse_block_items(p)
        expect_punct(p, "}")
        return { _variant = "CSCompound", items = items }
    end

    ------------------------------------------------------------------------
    -- If statement
    ------------------------------------------------------------------------

    function M.parse_if_stmt(p)
        advance(p) -- consume 'if'
        expect_punct(p, "(")
        local cond = p.parse_expr(p)
        expect_punct(p, ")")
        local then_stmt = M.parse_stmt(p)
        if not then_stmt then
            then_stmt = { _variant = "CSExpr", expr = nil } -- null statement
        end

        local else_stmt = nil
        skip_newlines(p)
        if tok_kw(p, "CKwElse") then
            advance(p)
            else_stmt = M.parse_stmt(p)
            if not else_stmt then
                else_stmt = { _variant = "CSExpr", expr = nil }
            end
        end

        return { _variant = "CSIf", cond = cond, then_stmt = then_stmt, else_stmt = else_stmt }
    end

    ------------------------------------------------------------------------
    -- For statement
    ------------------------------------------------------------------------

    function M.parse_for_stmt(p)
        advance(p) -- consume 'for'
        expect_punct(p, "(")
        skip_newlines(p)

        local init = nil
        local cond = nil
        local incr = nil

        -- Parse for-init (declaration or expression)
        if tok_punct(p, ";") then
            -- Empty init
            advance(p)
        else
            init = M.parse_for_init(p)
        end

        skip_newlines(p)

        -- Parse condition
        if tok_punct(p, ";") then
            advance(p)
        else
            cond = p.parse_expr(p)
            expect_punct(p, ";")
        end

        skip_newlines(p)

        -- Parse increment
        if tok_punct(p, ")") then
            -- Empty increment
        else
            incr = p.parse_expr(p)
        end

        expect_punct(p, ")")

        local body = M.parse_stmt(p)
        if not body then
            body = { _variant = "CSExpr", expr = nil }
        end

        return { _variant = "CSFor", init = init, cond = cond, incr = incr, body = body }
    end

    function M.parse_for_init(p)
        -- Check if it starts as a declaration
        local save = p.pos
        if c_decl.is_type_spec_start(p) then
            -- Try to parse as declaration
            local decl = c_decl.parse_declaration(p)
            if decl then
                return { _variant = "CFInitDecl", decl = decl }
            end
            p.pos = save
        end

        -- Parse as expression
        local expr = p.parse_expr(p)
        if expr then
            expect_punct(p, ";")
            return { _variant = "CFInitExpr", expr = expr }
        end

        return nil
    end

    ------------------------------------------------------------------------
    -- While statement
    ------------------------------------------------------------------------

    function M.parse_while_stmt(p)
        advance(p) -- consume 'while'
        expect_punct(p, "(")
        local cond = p.parse_expr(p)
        expect_punct(p, ")")
        local body = M.parse_stmt(p)
        if not body then
            body = { _variant = "CSExpr", expr = nil }
        end
        return { _variant = "CSWhile", cond = cond, body = body }
    end

    ------------------------------------------------------------------------
    -- Do-while statement
    ------------------------------------------------------------------------

    function M.parse_do_while_stmt(p)
        advance(p) -- consume 'do'
        local body = M.parse_stmt(p)
        if not body then
            body = { _variant = "CSExpr", expr = nil }
        end
        if tok_kw(p, "CKwWhile") then
            advance(p)
        else
            local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
            table.insert(p.issues, { message = "expected 'while' after do body", offset = off, line = 1, col = 1 })
        end
        expect_punct(p, "(")
        local cond = p.parse_expr(p)
        expect_punct(p, ")")
        expect_punct(p, ";")
        return { _variant = "CSDoWhile", body = body, cond = cond }
    end

    ------------------------------------------------------------------------
    -- Switch statement
    ------------------------------------------------------------------------

    function M.parse_switch_stmt(p)
        advance(p) -- consume 'switch'
        expect_punct(p, "(")
        local cond = p.parse_expr(p)
        expect_punct(p, ")")
        local body = M.parse_stmt(p)
        if not body then
            body = { _variant = "CSExpr", expr = nil }
        end
        return { _variant = "CSSwitch", cond = cond, body = body }
    end

    ------------------------------------------------------------------------
    -- Goto statement
    ------------------------------------------------------------------------

    function M.parse_goto_stmt(p)
        advance(p) -- consume 'goto'
        local label = nil
        if tok_v(p, "CTokIdent") then
            label = advance(p).name
        else
            local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
            table.insert(p.issues, { message = "expected label name after 'goto'", offset = off, line = 1, col = 1 })
        end
        expect_punct(p, ";")
        return { _variant = "CSGoto", label = label or "" }
    end

    ------------------------------------------------------------------------
    -- Continue statement
    ------------------------------------------------------------------------

    function M.parse_continue_stmt(p)
        advance(p) -- consume 'continue'
        expect_punct(p, ";")
        return { _variant = "CSContinue" }
    end

    ------------------------------------------------------------------------
    -- Break statement
    ------------------------------------------------------------------------

    function M.parse_break_stmt(p)
        advance(p) -- consume 'break'
        expect_punct(p, ";")
        return { _variant = "CSBreak" }
    end

    ------------------------------------------------------------------------
    -- Return statement
    ------------------------------------------------------------------------

    function M.parse_return_stmt(p)
        advance(p) -- consume 'return'
        local expr = nil

        -- Check if the next token starts an expression (not a semicolon)
        if not tok_punct(p, ";") then
            -- Peek: if the next token is a newline, skip it
            skip_newlines(p)
            if not tok_punct(p, ";") and not tok_v(p, "CTokEOF") and not tok_punct(p, "}") then
                expr = p.parse_expr(p)
            end
        end

        expect_punct(p, ";")
        return { _variant = "CSReturn", expr = expr }
    end

    ------------------------------------------------------------------------
    -- Case and default statements
    ------------------------------------------------------------------------

    function M.parse_case_stmt(p)
        advance(p) -- consume 'case'
        local value = p.parse_expr(p)
        if not value then
            local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
            table.insert(p.issues, { message = "expected expression after 'case'", offset = off, line = 1, col = 1 })
        end
        if tok_punct(p, "...") then
            -- GNU case range extension: case lo ... hi:
            advance(p)
            local hi = p.parse_expr(p)
            expect_punct(p, ":")
            local stmt = M.parse_stmt(p)
            if not stmt then stmt = { _variant = "CSExpr", expr = nil } end
            return { _variant = "CSCase", value = value, stmt = stmt }
                -- Note: case ranges are not in the standard ASDL.
                -- For now, we treat them as a simple case with the lower bound.
                -- The semantic phase should handle this.
        end
        expect_punct(p, ":")
        local stmt = M.parse_stmt(p)
        if not stmt then stmt = { _variant = "CSExpr", expr = nil } end
        return { _variant = "CSCase", value = value, stmt = stmt }
    end

    function M.parse_default_stmt(p)
        advance(p) -- consume 'default'
        expect_punct(p, ":")
        local stmt = M.parse_stmt(p)
        if not stmt then stmt = { _variant = "CSExpr", expr = nil } end
        return { _variant = "CSDefault", stmt = stmt }
    end

    return M
end

return M
