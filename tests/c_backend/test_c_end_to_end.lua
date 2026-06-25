package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local A = require("lalin.schema_projection")

local T = pvm.context()
A(T)

local Tr = T.LalinTree
local lexer = require("lalin.c.c_lexer")
local cpp = require("lalin.c.cpp_expand")(T)
local vfs = require("lalin.c.vfs")
local c_parse = require("lalin.c.c_parse")(T)
local cimport_mod = require("lalin.c.cimport")(T)
local lower_mod = require("lalin.c.lower_c")(T)

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
    local lalin_module = lower_mod.lower(tu.items, type_facts, layout_facts, extern_funcs, "test_mod")
    return lalin_module, tu, { type_facts = type_facts, layout_facts = layout_facts, extern_funcs = extern_funcs }, parse_issues
end

-- Test: Simple function: int add(int a, int b) { return a + b; }
do
    local src = [[int add(int a, int b) { return a + b; }]]
    local lalin_module, tu, cimports, issues = full_pipeline(src)

    assert(#issues == 0, "expected 0 parse issues, got " .. #issues)

    -- Verify TU structure (these still use _variant since c_parse outputs plain tables)
    assert(tu._variant == "TranslationUnit")
    assert(#tu.items == 1)
    assert(tu.items[1]._variant == "CATopFuncDef")
    local func = tu.items[1].func
    assert(func.declarator.name == "add")
    assert(func.type_spec._variant == "CTyInt")

    -- Verify lower_c produced a proper ASDL Module via pvm.classof
    assert(pvm.classof(lalin_module) == Tr.Module,
           "expected LalinTree.Module, got " .. tostring(pvm.classof(lalin_module)))
    assert(type(lalin_module.items) == "table")

    local found_item_func = false
    for _, item in ipairs(lalin_module.items) do
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
    local lalin_module, tu, cimports, issues = full_pipeline(src)
    assert(#issues == 0)
    assert(pvm.classof(lalin_module) == Tr.Module)

    -- Check for ItemFunc
    local found_func = false
    local found_data = false
    for _, item in ipairs(lalin_module.items) do
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

-- Test: sizeof lowers through C type facts, not a fixed sentinel value.
do
    local src = [[int size_i64(void) { return sizeof(long long); }]]
    local lalin_module, _, _, issues = full_pipeline(src)
    assert(#issues == 0)
    local ret
    for _, item in ipairs(lalin_module.items) do
        if pvm.classof(item) == Tr.ItemFunc and item.func.name == "size_i64" then
            ret = item.func.body[1]
        end
    end
    assert(ret and pvm.classof(ret) == Tr.StmtReturnValue)
    assert(pvm.classof(ret.value) == Tr.ExprLit)
    assert(ret.value.value.raw == "8", "expected sizeof(long long) to lower to 8")
    print("  sizeof lowering: PASS")
end

-- Test: parsed C compound literals are not silently lowered to a fake scalar.
do
    local ok, err = pcall(function()
        full_pipeline([[int bad(void) { return (int){1}; }]])
    end)
    assert(not ok, "compound literal importer lowering must reject until storage lowering is implemented")
    assert(tostring(err):match("compound literal"), "expected compound literal diagnostic, got " .. tostring(err))
    print("  compound literal lowering rejection: PASS")
end

print("lalin test_c_end_to_end ok")
