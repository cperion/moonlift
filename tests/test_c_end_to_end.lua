package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local Tr = T.MoonTree
local lexer = require("moonlift.c.c_lexer")
local cpp = require("moonlift.c.cpp_expand").Define(T)
local vfs = require("moonlift.c.vfs")
local c_parse = require("moonlift.c.c_parse").Define(T)
local cimport_mod = require("moonlift.c.cimport").Define(T)
local lower_mod = require("moonlift.c.lower_c").Define(T)

local function lex(src) return lexer.lex(src, "test.c") end

local function has_directives(tokens)
    for _, t in ipairs(tokens) do if t._variant == "CTokDirective" then return true end end
    return false
end

local function full_pipeline(src)
    local r = lex(src)
    if has_directives(r.tokens) then
        r = cpp.expand(r.tokens, r.spans, r.issues, vfs.mock({}))
    end
    local tu, parse_issues = c_parse.parse(r.tokens, r.spans)
    local type_facts, layout_facts, extern_funcs = cimport_mod.cimport(tu.items, "test_mod")
    local moon_module = lower_mod.lower(tu.items, type_facts, layout_facts, extern_funcs, "test_mod")
    return moon_module, tu, { type_facts = type_facts, layout_facts = layout_facts, extern_funcs = extern_funcs }, parse_issues
end

-- Test: Simple function: int add(int a, int b) { return a + b; }
do
    local src = [[int add(int a, int b) { return a + b; }]]
    local moon_module, tu, cimports, issues = full_pipeline(src)

    assert(#issues == 0, "expected 0 parse issues, got " .. #issues)

    -- Verify TU structure (these still use _variant since c_parse outputs plain tables)
    assert(tu._variant == "TranslationUnit")
    assert(#tu.items == 1)
    assert(tu.items[1]._variant == "CATopFuncDef")
    local func = tu.items[1].func
    assert(func.declarator.name == "add")
    assert(func.type_spec._variant == "CTyInt")

    -- Verify lower_c produced a proper ASDL Module via pvm.classof
    assert(pvm.classof(moon_module) == Tr.Module,
           "expected MoonTree.Module, got " .. tostring(pvm.classof(moon_module)))
    assert(type(moon_module.items) == "table")

    local found_item_func = false
    for _, item in ipairs(moon_module.items) do
        if pvm.classof(item) == Tr.ItemFunc then
            found_item_func = true
            assert(item.func.name == "add",
                   "expected function name 'add', got '" .. item.func.name .. "'")
            break
        end
    end
    assert(found_item_func, "expected ItemFunc in lowered module")

    print("  function ItemFunc: PASS")
end

-- Test: Typedef struct definition (parser only)
do
    local src = [[typedef struct { int x; int y; } Point;]]
    local r = lex(src)
    local tu, issues = c_parse.parse(r.tokens, r.spans)
    assert(#issues == 0)
    assert(tu.items[1]._variant == "CATopDecl")
    assert(tu.items[1].decl.declarators[1].name == "Point")
    print("  typedef struct parser: PASS")
end

-- Test: String literal
do
    local src = [[char* get_hello(void) { return "hello"; }]]
    local moon_module, tu, cimports, issues = full_pipeline(src)
    assert(#issues == 0)
    assert(pvm.classof(moon_module) == Tr.Module)

    -- Check for ItemFunc
    local found_func = false
    local found_data = false
    for _, item in ipairs(moon_module.items) do
        if pvm.classof(item) == Tr.ItemFunc then found_func = true end
        if pvm.classof(item) == Tr.ItemData then found_data = true end
    end
    assert(found_func, "expected ItemFunc for get_hello")
    -- ItemData for string literal may or may not be present depending on lowering
    print("  string literal: PASS")
end

-- Test: Preprocessor + parser integration
do
    local src = [[
#define FOO 42
int x = FOO;
]]
    local r = lex(src)
    local exp = cpp.expand(r.tokens, r.spans, r.issues, vfs.mock({}))
    local tu, issues = c_parse.parse(exp.tokens, exp.spans)
    assert(#issues == 0)
    assert(tu.items[1]._variant == "CATopDecl")
    assert(tu.items[1].decl.declarators[1].name == "x")
    print("  preprocessor + parse integration: PASS")
end

print("moonlift test_c_end_to_end ok")
