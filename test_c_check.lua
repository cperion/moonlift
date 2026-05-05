package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context()
A.Define(T)

local lexer = require("moonlift.c.c_lexer")
local c_parse = require("moonlift.c.c_parse").Define(T)
local cimport_mod = require("moonlift.c.cimport").Define(T)
local lower_mod = require("moonlift.c.lower_c").Define(T)

local function compile_c(src)
    local r = lexer.lex(src, "test.c")
    local tu, issues = c_parse.parse(r.tokens, r.spans)
    if #issues > 0 then
        for _, i in ipairs(issues) do print("PARSE: " .. i.message) end
        return nil
    end
    local tf, lf, ef = cimport_mod.cimport(tu.items, "test_mod")
    local mm = lower_mod.lower(tu.items, tf, lf, ef, "test_mod")
    return mm
end

local src = "int add(int a, int b) { return a + b; }"
local mm = compile_c(src)
if mm then
    print("type:", type(mm))
    print("class:", tostring(pvm.classof(mm)))
    local MT = T.MoonTree
    print("is Module?", pvm.classof(mm) == MT.Module)
    if mm.items then
        print("items:", #mm.items)
        for i, item in ipairs(mm.items) do
            print(string.format("  [%d] type=%s class=%s", i, type(item), tostring(pvm.classof(item))))
            if pvm.classof(item) == MT.ItemFunc then
                print(string.format("      func.name=%s", item.func.name))
            end
        end
    end
else
    print("compile_c returned nil")
end
