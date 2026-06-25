-- C frontend entry point for Lalin
-- Re-exports all C frontend modules

local function bind_context(T)
    local m = {}

    -- Lexer (non-PVM)
    m.c_lexer = require("lalin.c.c_lexer")

    -- Parser modules (non-PVM)
    m.c_decl = require("lalin.c.c_decl")(T)
    m.c_expr = require("lalin.c.c_expr")(T)
    m.c_stmt = require("lalin.c.c_stmt")(T)
    m.c_parse = require("lalin.c.c_parse")(T)

    -- PVM phases
    m.cpp_expand = require("lalin.c.cpp_expand")(T)
    m.cimport = require("lalin.c.cimport")(T)
    m.lower_c = require("lalin.c.lower_c")(T)

    -- Virtual file system
    m.vfs = require("lalin.c.vfs")

    return m
end

return bind_context