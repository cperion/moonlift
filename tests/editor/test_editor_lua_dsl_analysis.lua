package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local schema = require("moonlift.asdl")

local T = pvm.context()
schema.Define(T)

local S = T.MoonSource
local E = T.MoonEditor
local Mlua = T.MoonMlua

local Analysis = require("moonlift.mlua_document_analysis").Define(T)
local Symbols = require("moonlift.editor_symbol_facts").Define(T)
local Diagnostics = require("moonlift.editor_diagnostic_facts").Define(T)

local uri = S.DocUri("file:///editor_lua_dsl_test.lua")

local good_doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangLua, [[
require("moonlift").use()

return module "EditorSmoke" {
  struct .Pair { a [i32], b [i32] },
  fn .add { a [i32], b [i32] } [i32] {
    ret (a + b),
  },
}
]])

local analysis = Analysis.analyze_document_full(good_doc)
assert(pvm.classof(analysis) == Mlua.DocumentAnalysis, "analysis should be MoonMlua.DocumentAnalysis")
assert(#analysis.parse.combined.module.items == 2, "analysis should produce tree items")
assert(#analysis.parse.combined.issues == 0, "good Lua DSL document should not have parse issues")

local symbols = Symbols.symbols(analysis)
local saw_module, saw_struct, saw_func = false, false, false
for i = 1, #symbols do
    saw_module = saw_module or symbols[i].name == "EditorSmoke"
    saw_struct = saw_struct or symbols[i].name == "Pair"
    saw_func = saw_func or symbols[i].name == "add"
end
assert(saw_module, "document symbols should include module")
assert(saw_struct, "document symbols should include struct")
assert(saw_func, "document symbols should include function")

local bad_doc = S.DocumentSnapshot(S.DocUri("file:///editor_lua_dsl_bad.lua"), S.DocVersion(1), S.LangLua, [[
require("moonlift").use()

return module "Bad" {
  fn .bad {} [i32] {
    ret true,
  },
}
]])

local bad = Analysis.analyze_document_full(bad_doc)
local diagnostics = Diagnostics.diagnostics(bad)
assert(#diagnostics > 0, "bad Lua DSL document should produce diagnostics")
assert(pvm.classof(diagnostics[1]) == E.DiagnosticFact, "diagnostic should be editor diagnostic fact")

print("moonlift editor lua dsl analysis ok")
