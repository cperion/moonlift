-- c_decl.lua -- C99 declaration parser (type specifiers, declarators, declarations)
-- Pure Lua recursive-descent parser producing MoonCAst ASDL plain tables.
-- Methods operate on a CParser state { tokens, spans, pos, issues, typedefs }.

local M = {}

function M.Define(T)
    local CA = T.MoonCAst

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

    local function expect(p, variant_name)
        local t = peek(p)
        if t and t._variant == variant_name then
            p.pos = p.pos + 1
            return t
        end
        local msg = "expected " .. variant_name .. " but got " .. (t and t._variant or "nil")
        local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
        table.insert(p.issues, { message = msg, offset = off, line = 1, col = 1 })
        return nil
    end

    local function expect_punct(p, text)
        local t = peek(p)
        if t and t._variant == "CTokPunct" and t.text == text then
            p.pos = p.pos + 1
            return t
        end
        local msg = "expected '" .. text .. "' but got " .. (t and (t._variant == "CTokPunct" and t.text or t._variant) or "nil")
        local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
        table.insert(p.issues, { message = msg, offset = off, line = 1, col = 1 })
        return nil
    end

    local function is_typedef_name(p)
        local t = peek(p)
        if t and t._variant == "CTokIdent" then
            return p.typedefs[t.name] == true
        end
        return false
    end

    local function mk_issue(message, pos, lines)
        return { message = message, offset = pos or 0, line = 1, col = 1 }
    end

    -- Parse a qualifier token and return its ASDL variant.
    -- Advances the token stream if a qualifier is found.
    -- Returns nil if current token is not a qualifier (does not advance).
    local function parse_qualifier(p)
        local t = peek(p)
        if not t or t._variant ~= "CTokKeyword" then
            return nil
        end
        local kw = t.kw._variant
        local q
        if kw == "CKwConst" then
            q = { _variant = "CQualConst" }
        elseif kw == "CKwRestrict" or kw == "CKwRestrict2" then
            q = { _variant = "CQualRestrict" }
        elseif kw == "CKwVolatile" then
            q = { _variant = "CQualVolatile" }
        elseif kw == "CKwInline" or kw == "CKwInline2" then
            q = { _variant = "CQualInline" }
        else
            return nil
        end
        advance(p)
        return q
    end

    -- Parse zero or more qualifiers and return them in a list.
    local function parse_qualifiers(p)
        local quals = {}
        while true do
            local q = parse_qualifier(p)
            if not q then break end
            table.insert(quals, q)
        end
        return quals
    end

    -- Parse a storage class specifier. Returns nil if not a storage class.
    local function parse_storage(p)
        local t = peek(p)
        if not t or t._variant ~= "CTokKeyword" then return nil end
        local kw = t.kw._variant
        local s
        if kw == "CKwTypedef" then
            s = { _variant = "CStorageTypedef" }
        elseif kw == "CKwExtern" then
            s = { _variant = "CStorageExtern" }
        elseif kw == "CKwStatic" then
            s = { _variant = "CStorageStatic" }
        elseif kw == "CKwAuto" then
            s = { _variant = "CStorageAuto" }
        elseif kw == "CKwRegister" then
            s = { _variant = "CStorageRegister" }
        else
            return nil
        end
        advance(p)
        return s
    end

    ------------------------------------------------------------------------
    -- Type specifier parsing
    ------------------------------------------------------------------------

    -- Returns true if the current token can start a type specifier.
    function M.is_type_spec_start(p)
        local t = peek(p)
        if not t then return false end
        if t._variant == "CTokKeyword" then
            local kw = t.kw._variant
            return kw == "CKwVoid"      or kw == "CKwChar"     or kw == "CKwShort"
                or kw == "CKwInt"       or kw == "CKwLong"     or kw == "CKwFloat"
                or kw == "CKwDouble"    or kw == "CKwSigned"   or kw == "CKwUnsigned"
                or kw == "CKwBool"      or kw == "CKwComplex"  or kw == "CKwStruct"
                or kw == "CKwUnion"     or kw == "CKwEnum"     or kw == "CKwSizeof"
        end
        if t._variant == "CTokIdent" then
            return p.typedefs[t.name] == true
        end
        -- GNU __typeof__ / typeof is not a keyword in C99 but a GCC extension
        -- handled by checking for the specific identifier
        if t._variant == "CTokIdent" then
            return t.name == "typeof" or t.name == "__typeof__"
        end
        return false
    end

    function M.parse_type_spec(p)
        local t = peek(p)
        if not t then return nil end

        -- Handle typedef names (CTyNamed)
        if is_typedef_name(p) then
            local name = advance(p).name
            return { _variant = "CTyNamed", name = name }
        end

        -- Handle GNU typeof extension
        if tok_v(p, "CTokIdent") and (t.name == "typeof" or t.name == "__typeof__") then
            advance(p)
            expect_punct(p, "(")
            local expr = p.parse_expr(p)
            expect_punct(p, ")")
            return { _variant = "CTyTypeof", expr = expr }
        end

        -- Handle struct / union
        if tok_kw(p, "CKwStruct") or tok_kw(p, "CKwUnion") then
            local kind_tok = advance(p)
            local kind = { _variant = kind_tok.kw._variant == "CKwStruct"
                and "CStructKindStruct" or "CStructKindUnion" }
            local name = nil
            local members = nil

            -- Check for optional tag name
            if tok_v(p, "CTokIdent") then
                name = advance(p).name
            end

            -- Check for body
            if tok_punct(p, "{") then
                advance(p)
                members = M.parse_field_decls(p)
                expect_punct(p, "}")
                -- Semicolon after } is NOT consumed here; it's consumed by the
                -- declaration parser that called parse_type_spec.
            end

            return { _variant = "CTyStructOrUnion", kind = kind, name = name, members = members }
        end

        -- Handle enum
        if tok_kw(p, "CKwEnum") then
            advance(p)
            local name = nil
            local enumerators = nil

            if tok_v(p, "CTokIdent") then
                name = advance(p).name
            end

            if tok_punct(p, "{") then
                advance(p)
                enumerators = M.parse_enumerators(p)
                expect_punct(p, "}")
            end

            return { _variant = "CTyEnum", name = name, enumerators = enumerators }
        end

        -- Handle basic type specifier combinations (loop to collect all specifier keywords)
        local has_signed = false
        local has_unsigned = false
        local has_long = false
        local has_long_long = false
        local has_short = false
        local has_int = false
        local has_char = false
        local has_double = false
        local has_float = false
        local has_void = false
        local has_bool = false
        local has_complex = false

        -- Collect all specifier keywords
        while peek(p) and peek(p)._variant == "CTokKeyword" do
            local kw = peek(p).kw._variant
            if kw == "CKwSigned" then advance(p); has_signed = true
            elseif kw == "CKwUnsigned" then advance(p); has_unsigned = true
            elseif kw == "CKwLong" then
                advance(p)
                if has_long then has_long_long = true else has_long = true end
            elseif kw == "CKwShort" then advance(p); has_short = true
            elseif kw == "CKwInt" then advance(p); has_int = true
            elseif kw == "CKwChar" then advance(p); has_char = true
            elseif kw == "CKwDouble" then advance(p); has_double = true
            elseif kw == "CKwFloat" then advance(p); has_float = true
            elseif kw == "CKwVoid" then advance(p); has_void = true
            elseif kw == "CKwBool" then advance(p); has_bool = true
            elseif kw == "CKwComplex" then advance(p); has_complex = true
            else break end
        end

        -- Determine the resulting TypeSpec variant
        if has_void then return { _variant = "CTyVoid" } end
        if has_bool then return { _variant = "CTyBool" } end
        if has_complex then return { _variant = "CTyComplex" } end

        -- For char types: signed char, unsigned char, or just char
        if has_char then
            if has_unsigned then return { _variant = "CTyUnsigned" } end
            if has_signed then return { _variant = "CTySigned" } end
            return { _variant = "CTyChar" }
        end

        -- For floating point
        if has_double then
            if has_long then return { _variant = "CTyLongDouble" } end
            return { _variant = "CTyDouble" }
        end
        if has_float then return { _variant = "CTyFloat" } end

        -- For integer types: determine base width
        if has_long_long then
            if has_unsigned then return { _variant = "CTyUnsigned" }
            elseif has_signed then return { _variant = "CTySigned" }
            else return { _variant = "CTyLongLong" } end
        end
        if has_long then
            if has_unsigned then return { _variant = "CTyUnsigned" }
            elseif has_signed then return { _variant = "CTySigned" }
            else return { _variant = "CTyLong" } end
        end
        if has_short then
            if has_unsigned then return { _variant = "CTyUnsigned" }
            elseif has_signed then return { _variant = "CTySigned" }
            else return { _variant = "CTyShort" } end
        end

        -- Plain int or signed/unsigned without following type keyword
        if has_unsigned then return { _variant = "CTyUnsigned" } end
        if has_signed then return { _variant = "CTySigned" } end
        if has_int then return { _variant = "CTyInt" } end

        -- No specifier found
        return nil
    end

    ------------------------------------------------------------------------
    -- Declarator parsing (the spiral rule)
    ------------------------------------------------------------------------

    -- Check if the current position could be the start of a declarator.
    -- Used to disambiguate parenthesized declarators from function call syntax.
    local function is_declarator_start(p, abstract_ok)
        local t = peek(p)
        if not t then return false end
        if t._variant == "CTokIdent" then return true end
        if t._variant == "CTokPunct" and t.text == "*" then return true end
        if t._variant == "CTokPunct" and t.text == "(" then
            -- Could be a parenthesized declarator or an abstract function type.
            -- We optimistically assume it is; the caller will backtrack if needed.
            return true
        end
        if abstract_ok then
            -- For abstract declarators, qualifiers after a pointer * are valid
            if t._variant == "CTokKeyword" then
                local kw = t.kw._variant
                return kw == "CKwConst" or kw == "CKwRestrict" or kw == "CKwRestrict2"
                    or kw == "CKwVolatile" or kw == "CKwInline" or kw == "CKwInline2"
            end
        end
        return false
    end

    function M.parse_declarator(p, abstract_ok)
        -- Step 1: Collect prefix pointers (outermost in C declaration syntax)
        local pointers = {}
        while tok_punct(p, "*") do
            advance(p)
            local quals = parse_qualifiers(p)
            local qt = {}
            for _, q in ipairs(quals) do
                table.insert(qt, q)
            end
            table.insert(pointers, { _variant = "CDerivedPointer", qualifiers = qt })
        end

        -- Step 2: Parse the "core" of the declarator (ident or parenthesized)
        local name = nil
        local inner_derived = {}

        if tok_v(p, "CTokIdent") then
            local tok = advance(p)
            name = tok.name
        elseif tok_punct(p, "(") and is_declarator_start(p, abstract_ok) then
            advance(p) -- consume '('
            -- Parenthesized declarator: parse inner, then expect ')'
            local inner = M.parse_declarator(p, abstract_ok)
            if not expect_punct(p, ")") then
                -- Error recovery: skip to )
                while peek(p) and not tok_punct(p, ")") and not tok_v(p, "CTokEOF") do
                    advance(p)
                end
                if peek(p) then advance(p) end
            end
            name = inner.name
            inner_derived = inner.derived
        elseif abstract_ok then
            -- Abstract declarator: name stays nil, inner_derived stays empty
        else
            -- Not a declarator at all
            return nil
        end

        -- Step 3: Collect postfix derived types (arrays and functions)
        local postfix_derived = {}
        while peek(p) do
            if tok_punct(p, "[") then
                advance(p) -- consume '['
                local size = nil
                if not tok_punct(p, "]") then
                    skip_newlines(p)
                    if not tok_punct(p, "]") then
                        size = p.parse_expr(p)
                        skip_newlines(p)
                    end
                end
                expect_punct(p, "]")
                table.insert(postfix_derived, { _variant = "CDerivedArray", size = size })
            elseif tok_punct(p, "(") then
                -- Function parameters. Check this is not the beginning of a
                -- block (which would be after the declarator in a function definition).
                -- We check by looking ahead: if after () there is another (
                -- or [, this is part of the declarator.
                -- Mark position and try to parse params.
                local save = p.pos
                advance(p) -- consume '('

                -- Check for empty parameter list: ()
                if tok_punct(p, ")") then
                    advance(p)
                    table.insert(postfix_derived, {
                        _variant = "CDerivedFunction",
                        params = {},
                        variadic = false,
                    })
                else
                    local params, variadic = M.parse_param_list(p)
                    if not expect_punct(p, ")") then
                        -- Error recovery
                        while peek(p) and not tok_punct(p, ")") and not tok_v(p, "CTokEOF") do
                            advance(p)
                        end
                        if peek(p) then advance(p) end
                    end
                    table.insert(postfix_derived, {
                        _variant = "CDerivedFunction",
                        params = params,
                        variadic = variadic,
                    })
                end
            else
                break
            end
        end

        -- Step 4: Build combined derived list
        -- Order: inner_derived first, then postfix_derived, then pointers
        local all_derived = {}
        for _, d in ipairs(inner_derived) do
            table.insert(all_derived, d)
        end
        for _, d in ipairs(postfix_derived) do
            table.insert(all_derived, d)
        end
        for _, ptr in ipairs(pointers) do
            table.insert(all_derived, ptr)
        end

        -- Check for initializer
        local init = nil
        if tok_punct(p, "=") then
            advance(p)
            init = M.parse_initializer(p)
        end

        return { name = name, derived = all_derived, initializer = init }
    end

    ------------------------------------------------------------------------
    -- Field declarator (for struct/union members including bitfields)
    ------------------------------------------------------------------------

    function M.parse_field_declarator(p)
        local decl = nil
        local bit_width = nil

        -- Check for unnamed bitfield (just : expr) or named declarator
        if is_declarator_start(p, true) then
            decl = M.parse_declarator(p, true)
        end

        -- Check for bitfield width
        if tok_punct(p, ":") then
            advance(p)
            bit_width = p.parse_expr(p)
        end

        return { declarator = decl, bit_width = bit_width }
    end

    ------------------------------------------------------------------------
    -- Field declarations (struct/union body)
    ------------------------------------------------------------------------

    function M.parse_field_decls(p)
        local fields = {}
        while peek(p) and not tok_punct(p, "}") and not tok_v(p, "CTokEOF") do
            skip_newlines(p)
            if tok_punct(p, "}") then break end

            local save = p.pos
            -- Parse: qualifiers* type_spec field_declarator (, field_declarator)* ;
            local quals = parse_qualifiers(p)
            local ts = M.parse_type_spec(p)
            if not ts then
                -- Error recovery: skip to ; or }
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected type specifier in field declaration", offset = off, line = 1, col = 1 })
                while peek(p) and not tok_punct(p, ";") and not tok_punct(p, "}") and not tok_v(p, "CTokEOF") do
                    advance(p)
                end
                if tok_punct(p, ";") then advance(p) end
                break
            end

            -- Parse field declarators
            local decls = {}
            local first = true
            while true do
                if not first then
                    if not tok_punct(p, ",") then break end
                    advance(p)
                end
                first = false
                skip_newlines(p)
                local fd = M.parse_field_declarator(p)
                table.insert(decls, fd)
                skip_newlines(p)
            end

            expect_punct(p, ";")

            -- Check for flexible array member: last field with empty array
            -- (already handled: array declarator with nil size is CDerivedArray{size=nil})

            table.insert(fields, { type_spec = ts, declarators = decls })
        end
        return fields
    end

    ------------------------------------------------------------------------
    -- Enumerator list parsing
    ------------------------------------------------------------------------

    function M.parse_enumerators(p)
        local enumerators = {}
        skip_newlines(p)
        while peek(p) and not tok_punct(p, "}") and not tok_v(p, "CTokEOF") do
            skip_newlines(p)
            if tok_punct(p, "}") then break end

            if tok_v(p, "CTokIdent") then
                local name = advance(p).name
                local value = nil
                if tok_punct(p, "=") then
                    advance(p)
                    value = p.parse_expr(p)
                end
                table.insert(enumerators, { name = name, value = value })

                skip_newlines(p)
                if tok_punct(p, ",") then
                    advance(p)
                    skip_newlines(p)
                else
                    break
                end
            else
                -- Error: expected identifier
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected enumerator name", offset = off, line = 1, col = 1 })
                advance(p)
            end
        end
        return enumerators
    end

    ------------------------------------------------------------------------
    -- Parameter declaration
    ------------------------------------------------------------------------

    function M.parse_param_decl(p)
        skip_newlines(p)
        local quals = parse_qualifiers(p)
        local ts = M.parse_type_spec(p)
        if not ts then return nil end

        local decl = nil
        -- Check if there is a declarator (not just a type spec)
        if is_declarator_start(p, true) then
            decl = M.parse_declarator(p, true)
        end

        return { type_spec = ts, qualifiers = quals, declarator = decl }
    end

    function M.parse_param_list(p)
        local params = {}
        local variadic = false

        skip_newlines(p)

        -- Check for void parameter (C style: int f(void))
        if tok_kw(p, "CKwVoid") and (tok_punct(p, ")") or tok_punct(p, ",")) then
            -- "void" as sole param means no params
            local pd = M.parse_param_decl(p)
            if pd then table.insert(params, pd) end
            return params, false
        end

        while peek(p) and not tok_punct(p, ")") and not tok_v(p, "CTokEOF") do
            skip_newlines(p)

            -- Check for variadic ...
            if tok_punct(p, "...") then
                advance(p)
                variadic = true
                break
            end

            local pd = M.parse_param_decl(p)
            if pd then
                table.insert(params, pd)
            else
                break
            end

            skip_newlines(p)
            if tok_punct(p, ",") then
                advance(p)
            elseif tok_punct(p, ")") or tok_punct(p, "...") then
                -- will be handled next iteration
            else
                break
            end
        end

        return params, variadic
    end

    ------------------------------------------------------------------------
    -- Full declaration
    ------------------------------------------------------------------------

    function M.parse_declaration(p)
        local save = p.pos

        -- Parse optional storage class
        local storage = parse_storage(p)
        local had_typedef = storage and storage._variant == "CStorageTypedef"

        -- Parse qualifiers (before type spec)
        local quals = parse_qualifiers(p)

        -- Parse type specifier
        local ts = M.parse_type_spec(p)
        if not ts then
            p.pos = save
            return nil
        end

        -- Parse declarators (comma-separated)
        local decls = {}
        if not tok_punct(p, ";") then
            while true do
                skip_newlines(p)
                if tok_punct(p, ";") then break end

                local decl = M.parse_declarator(p, false)
                if not decl then break end
                table.insert(decls, decl)

                skip_newlines(p)
                if tok_punct(p, ",") then
                    advance(p)
                else
                    break
                end
            end
        end

        -- Register typedef names
        if had_typedef then
            for _, d in ipairs(decls) do
                if d.name then
                    p.typedefs[d.name] = true
                end
            end
        end

        -- Expect semicolon (but also check for end of compound stmt / EOF)
        skip_newlines(p)
        if tok_punct(p, ";") then
            advance(p)
        elseif not tok_punct(p, "}") and not tok_v(p, "CTokEOF") then
            local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
            table.insert(p.issues, { message = "expected ';' after declaration", offset = off, line = 1, col = 1 })
            -- Recovery: skip to ; or }
            while peek(p) and not tok_punct(p, ";") and not tok_punct(p, "}") and not tok_v(p, "CTokEOF") do
                advance(p)
            end
            if tok_punct(p, ";") then advance(p) end
        end

        return { storage = storage, qualifiers = quals, type_spec = ts, declarators = decls }
    end

    ------------------------------------------------------------------------
    -- Function definition
    ------------------------------------------------------------------------

    function M.parse_func_def(p)
        local save = p.pos

        -- Parse optional storage class
        local storage = parse_storage(p)

        -- Parse qualifiers (before type spec)
        local quals = parse_qualifiers(p)

        -- Parse type specifier
        local ts = M.parse_type_spec(p)
        if not ts then
            p.pos = save
            return nil
        end

        -- Parse declarator (must produce a function type, i.e., have a DerivedFunction)
        local decl = M.parse_declarator(p, false)
        if not decl then
            p.pos = save
            return nil
        end

        -- A function definition requires a { body after the declarator.
        -- Also handle K&R-style: check for declaration list before {
        skip_newlines(p)

        -- K&R-style parameter declarations: if we see a type spec or qualifier,
        -- skip them (old-style). We don't fully support K&R, but we skip to {
        while peek(p) and tok_punct(p, ";") do
            -- Old-style parameter declarations: int f(x, y) int x; int y; { ... }
            -- Skip them by looking for declarations before {
            advance(p) -- consume ;
            skip_newlines(p)
        end

        if not tok_punct(p, "{") then
            p.pos = save
            return nil
        end

        -- Parse body
        advance(p) -- consume '{'
        local items = p.parse_block_items(p)
        expect_punct(p, "}")

        local body = { _variant = "CSCompound", items = items }

        return {
            storage = storage,
            qualifiers = quals,
            type_spec = ts,
            declarator = decl,
            body = body,
        }
    end

    ------------------------------------------------------------------------
    -- Type name (for sizeof, casts, compound literals)
    ------------------------------------------------------------------------

    function M.parse_type_name(p)
        local ts = M.parse_type_spec(p)
        if not ts then return nil end

        local derived = {}
        if is_declarator_start(p, true) then
            local ad = M.parse_declarator(p, true)
            if ad then
                derived = ad.derived
            end
        end

        return { type_spec = ts, derived = derived }
    end

    ------------------------------------------------------------------------
    -- Initializer parsing
    ------------------------------------------------------------------------

    function M.parse_initializer(p)
        skip_newlines(p)
        if tok_punct(p, "{") then
            return M.parse_init_list(p)
        end
        -- Use assign_expr, NOT comma_expr: commas in a declaration separate
        -- declarators and must not be consumed as part of the initializer value.
        local e = p.parse_assign_expr(p)
        if e then
            return { _variant = "CInitExpr", expr = e }
        end
        return nil
    end

    function M.parse_init_list(p)
        -- Assumes '{' has been consumed.
        local items = {}
        skip_newlines(p)
        while peek(p) and not tok_punct(p, "}") and not tok_v(p, "CTokEOF") do
            skip_newlines(p)
            if tok_punct(p, "}") then break end

            local designators = nil

            -- Check for designated initializer
            if tok_punct(p, "[") then
                -- Array designator: [expr] or [expr ... expr]
                designators = {}
                while tok_punct(p, "[") or tok_punct(p, ".") do
                    local d = nil
                    if tok_punct(p, "[") then
                        advance(p) -- consume '['
                        local lo = p.parse_expr(p)
                        if tok_punct(p, "...") then
                            advance(p)
                            local hi = p.parse_expr(p)
                            d = { _variant = "CDesigRange", lo = lo, hi = hi }
                        else
                            d = { _variant = "CDesigIndex", index = lo }
                        end
                        expect_punct(p, "]")
                    elseif tok_punct(p, ".") then
                        advance(p)
                        if tok_v(p, "CTokIdent") then
                            d = { _variant = "CDesigField", name = advance(p).name }
                        else
                            local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                            table.insert(p.issues, { message = "expected field name after '.' in designator", offset = off, line = 1, col = 1 })
                            break
                        end
                    end
                    if d then
                        table.insert(designators, d)
                    end
                    skip_newlines(p)
                end
                -- After designators, expect =
                if tok_punct(p, "=") then
                    advance(p)
                end
            elseif tok_punct(p, ".") and tok_v(p, "CTokIdent") then
                -- Field designator: .ident = initializer
                -- Note: .ident style requires lookahead beyond just "." ident
                -- We need to check if it's a field designator or just a field access
                -- In initializer context, ".ident" always starts a designator.
                designators = {}
                while tok_punct(p, ".") or tok_punct(p, "[") do
                    local d = nil
                    if tok_punct(p, ".") then
                        advance(p)
                        if tok_v(p, "CTokIdent") then
                            d = { _variant = "CDesigField", name = advance(p).name }
                        end
                    elseif tok_punct(p, "[") then
                        advance(p)
                        local lo = p.parse_expr(p)
                        if tok_punct(p, "...") then
                            advance(p)
                            local hi = p.parse_expr(p)
                            d = { _variant = "CDesigRange", lo = lo, hi = hi }
                        else
                            d = { _variant = "CDesigIndex", index = lo }
                        end
                        expect_punct(p, "]")
                    end
                    if d then table.insert(designators, d) end
                    skip_newlines(p)
                end
                if tok_punct(p, "=") then
                    advance(p)
                end
            end

            -- Parse the value initializer
            local val = M.parse_initializer(p)
            if val then
                if designators and #designators > 0 then
                    table.insert(items, { designator = designators, value = val })
                else
                    table.insert(items, { designator = nil, value = val })
                end
            else
                -- Error: expected initializer
                local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
                table.insert(p.issues, { message = "expected initializer value", offset = off, line = 1, col = 1 })
            end

            skip_newlines(p)
            if tok_punct(p, ",") then
                advance(p)
                skip_newlines(p)
            elseif tok_punct(p, "}") then
                break
            else
                break
            end
        end

        return { _variant = "CInitList", items = items }
    end

    ------------------------------------------------------------------------
    -- Parser state initialization
    ------------------------------------------------------------------------

    function M.new_parser(tokens, spans)
        return {
            tokens = tokens,
            spans = spans,
            pos = 1,
            issues = {},
            typedefs = {},
        }
    end

    return M
end

return M
