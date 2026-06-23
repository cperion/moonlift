-- C frontend entry point for Moonlift
-- Re-exports all C frontend modules

local function bind_context(T)
    local m = {}

    -- Lexer (non-PVM)
    m.c_lexer = require("moonlift.c.c_lexer")

    -- Parser modules (non-PVM)
    m.c_decl = require("moonlift.c.c_decl")(T)
    m.c_expr = require("moonlift.c.c_expr")(T)
    m.c_stmt = require("moonlift.c.c_stmt")(T)
    m.c_parse = require("moonlift.c.c_parse")(T)

    -- PVM phases
    m.cpp_expand = require("moonlift.c.cpp_expand")(T)
    m.cimport = require("moonlift.c.cimport")(T)
    m.lower_c = require("moonlift.c.lower_c")(T)

    -- Virtual file system
    m.vfs = require("moonlift.c.vfs")

    return m
end

return bind_context