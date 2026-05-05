package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local lexer = require("moonlift.c.c_lexer")
local cpp = require("moonlift.c.cpp_expand").Define(T)
local vfs = require("moonlift.c.vfs")
local c_parse = require("moonlift.c.c_parse").Define(T)
local cimport = require("moonlift.c.cimport").Define(T)
local lower_c = require("moonlift.c.lower_c").Define(T)
local TC = require("moonlift.tree_typecheck").Define(T)
local TB = require("moonlift.tree_to_back").Define(T)
local BV = require("moonlift.back_validate").Define(T)
local LJ = require("moonlift.back_luajit").Define(T)

local function compile_c(src, files)
    local r = lexer.lex(src, "test.c")
    assert(#r.issues == 0)
    r = cpp.expand(r.tokens, r.spans, r.issues, vfs.mock(files or {}))
    assert(#r.issues == 0, r.issues[1] and r.issues[1].message)
    local tu, issues = c_parse.parse(r.tokens, r.spans)
    assert(#issues == 0, issues[1] and issues[1].message)
    local tf, lf, ef = cimport.cimport(tu.items, "test_mod")
    local mm = lower_c.lower(tu.items, tf, lf, ef, "test_mod")
    local checked = TC.check_module(mm)
    assert(#checked.issues == 0, checked.issues[1] and tostring(pvm.classof(checked.issues[1]).kind))
    local prog = TB.module(checked.module)
    local report = BV.validate(prog)
    assert(#report.issues == 0, report.issues[1] and report.issues[1].message)
    return LJ.compile(prog), tf, lf, ef
end

local header = [[
typedef struct { int x; int y; } Point;
int abs(int x);
]]

local artifact, type_facts, layout_facts = compile_c([[
#include "point.h"
int dist(Point* a, Point* b) {
    int dx = a->x - b->x;
    int dy = a->y - b->y;
    return dx * dx + dy * dy;
}
int setx(Point* p, int v) {
    p->x = v;
    return p->x;
}
int abs_x(Point* p) {
    return abs(p->x);
}
]], { ["point.h"] = header })

assert(#layout_facts == 1)
assert(layout_facts[1].type.spelling == "Point")
assert(#layout_facts[1].fields == 2)
assert(layout_facts[1].fields[1].name == "x" and layout_facts[1].fields[1].offset == 0)
assert(layout_facts[1].fields[2].name == "y" and layout_facts[1].fields[2].offset == 4)

ffi.cdef(header)
local Point = ffi.typeof("Point")
local a = Point({3, 4})
local b = Point({0, 0})
assert(artifact.module.dist(a, b) == 25)
assert(artifact.module.setx(a, -77) == -77)
assert(a.x == -77)
assert(artifact.module.abs_x(a) == 77)

print("moonlift test_c_struct_fields ok")
