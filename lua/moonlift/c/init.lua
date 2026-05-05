-- C frontend entry point for Moonlift
-- Re-exports all C frontend modules

local M = {}

function M.Define(T)
    local m = {}

    -- Lexer (non-PVM)
    m.c_lexer = require("moonlift.c.c_lexer")

    -- Parser modules (non-PVM)
    m.c_decl = require("moonlift.c.c_decl").Define(T)
    m.c_expr = require("moonlift.c.c_expr").Define(T)
    m.c_stmt = require("moonlift.c.c_stmt").Define(T)
    m.c_parse = require("moonlift.c.c_parse").Define(T)

    -- PVM phases
    m.cpp_expand = require("moonlift.c.cpp_expand").Define(T)
    m.cimport = require("moonlift.c.cimport").Define(T)
    m.lower_c = require("moonlift.c.lower_c").Define(T)

    -- Virtual file system
    m.vfs = require("moonlift.c.vfs")

    return m
end

return M
