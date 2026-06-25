-- c_parse.lua -- Parser orchestrator for Lalin C frontend
-- Entry point: combines declaration, expression, and statement parsers
-- and drives top-level parsing of a C translation unit.

local M = {}

local function bind_context(T)
    local CA = T.LalinCAst
    local c_decl = require("lalin.c.c_decl")(T)
    local c_expr = require("lalin.c.c_expr")(T)
    local c_stmt = require("lalin.c.c_stmt")(T)

    -- Local helper: skip newlines in the parser state
    local function skip_newlines(p)
        while p.pos <= #p.tokens and p.tokens[p.pos]._variant == "CTokNewline" do
            p.pos = p.pos + 1
        end
    end

    function M.parse(tokens, spans)
        -- Create parser state
        local p = c_decl.new_parser(tokens, spans)

        -- Add expression and statement methods to the parser state
        for k, v in pairs(c_expr) do
            p[k] = v
        end
        for k, v in pairs(c_stmt) do
            p[k] = v
        end

        -- Add c_decl methods as well (though they're already callable directly)
        for k, v in pairs(c_decl) do
            if type(v) == "function" and k ~= "Define" and k ~= "new_parser" then
                p[k] = v
            end
        end

        -- Ensure cross-references: statement parser needs expression and decl parsers,
        -- expression parser needs decl parser. These were already set up via imports
        -- in the individual bind_context() calls. But we also need parse_type_name and
        -- parse_declaration on p for cross-module calls via p:method().
        -- These are already added by the loop above.

        local items = {}
        while p.pos <= #tokens do
            -- Skip leading newlines
            skip_newlines(p)
            if p.pos > #tokens then break end
            if p.tokens[p.pos]._variant == "CTokEOF" then break end

            -- Save position for backtracking
            local save_pos = p.pos

            -- Try function definition first (peek for { after declarator)
            local fd = c_decl.parse_func_def(p)
            if fd then
                items[#items + 1] = { _variant = "CATopFuncDef", func = fd }
                goto continue
            end

            -- Restore and try declaration
            p.pos = save_pos
            local d = c_decl.parse_declaration(p)
            if d then
                items[#items + 1] = { _variant = "CATopDecl", decl = d }
                goto continue
            end

            -- Error recovery: skip one token
            local off = p.spans[p.pos] and p.spans[p.pos].start_offset or 0
            table.insert(p.issues, {
                message = "unexpected token at top level",
                offset = off,
                line = 1,
                col = 1,
            })
            p.pos = p.pos + 1

            ::continue::
        end

        return { _variant = "TranslationUnit", items = items }, p.issues
    end

    return M
end

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})