package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context(); A.Define(T)
local lexer = require("moonlift.c.c_lexer")
local cp = require("moonlift.c.c_parse").Define(T)
local ci = require("moonlift.c.cimport").Define(T)
local lc = require("moonlift.c.lower_c").Define(T)

local src = "int sum(int* xs, int n) { int acc = 0; int i; for (i = 0; i < n; i = i + 1) { acc = acc + xs[i]; } return acc; }"
local r = lexer.lex(src, "t.c")
local tu, issues = cp.parse(r.tokens, r.spans)
assert(#issues == 0)
local tf, lf, ef = ci.cimport(tu.items, "test_mod")
local mm = lc.lower(tu.items, tf, lf, ef, "test_mod")

local MT = T.MoonTree
local item = mm.items[1]
local f = item.func

-- Find the StmtControl
for i, s in ipairs(f.body) do
    local cls = pvm.classof(s)
    if cls == MT.StmtControl then
        print("=== StmtControl at index " .. i .. " ===")
        local region = s.region
        print("region_id:", region.region_id and pvm.classof(region.region_id) and tostring(region.region_id) or "?")
        local entry = region.entry
        print("entry block:", pvm.classof(entry.label) and "label="..tostring(entry.label.name) or "?")
        print("entry params:", #(entry.params or {}))
        print("entry body:", #(entry.body or {}))
        for _, bs in ipairs(entry.body or {}) do
            print("  entry stmt:", pvm.classof(bs))
            if pvm.classof(bs) == MT.StmtIf then
                print("    cond:", pvm.classof(bs.cond))
                print("    then:", #(bs.then_body or {}))
                print("    else:", #(bs.else_body or {}))
            end
        end
        for bi, bl in ipairs(region.blocks or {}) do
            print(string.format("block %d: label=%s, stmts=%d", bi, bl.label.name, #(bl.body or {})))
            for _, bs in ipairs(bl.body or {}) do
                print("  stmt:", pvm.classof(bs))
            end
        end
    elseif cls == MT.StmtExpr then
        print("=== StmtExpr at index " .. i .. " ===")
        print("  expr:", pvm.classof(s.expr))
        if pvm.classof(s.expr) == MT.ExprBlock then
            print("  block result:", pvm.classof(s.expr.result))
            print("  block stmts:", #(s.expr.stmts or {}))
            for _, bs in ipairs(s.expr.stmts or {}) do
                print("    ", pvm.classof(bs))
            end
        end
    end
end
