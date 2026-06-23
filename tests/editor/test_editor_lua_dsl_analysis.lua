package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_projection")

local T = pvm.context()
schema(T)

local S = T.MoonSource
local E = T.MoonEditor
local Mlua = T.MoonMlua

local Analysis = require("moonlift.mlua_document_analysis")(T)
local Symbols = require("moonlift.editor_symbol_facts")(T)
local Diagnostics = require("moonlift.editor_diagnostic_facts")(T)

local uri = S.DocUri("file:///editor_lua_dsl_test.lua")

local good_doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangLua, [[
require("moonlift").family.use { scope = "env", target = getfenv(1), global = false, override = true }

return moonlift.unit. EditorSmoke {
  moonlift.struct. Pair { a [moonlift.i32], b [moonlift.i32] },
  moonlift.fn. add { a [moonlift.i32], b [moonlift.i32] } [moonlift.i32] {
    moonlift.ret (a + b),
  },
}
]])

local analysis = Analysis.analyze_document_full(good_doc)
assert(pvm.classof(analysis) == Mlua.DocumentAnalysis, "analysis should be MoonMlua.DocumentAnalysis")
assert(#analysis.parse.combined.module.items == 2, "analysis should produce tree items")
assert(#analysis.parse.combined.issues == 0, "good Lua DSL document should not have parse issues")

local symbols = Symbols.symbols(analysis)
local saw_unit, saw_struct, saw_func = false, false, false
for i = 1, #symbols do
    saw_unit = saw_unit or symbols[i].name == "EditorSmoke"
    saw_struct = saw_struct or symbols[i].name == "Pair"
    saw_func = saw_func or symbols[i].name == "add"
end
assert(saw_unit, "document symbols should include unit")
assert(saw_struct, "document symbols should include struct")
assert(saw_func, "document symbols should include function")

local bad_doc = S.DocumentSnapshot(S.DocUri("file:///editor_lua_dsl_bad.lua"), S.DocVersion(1), S.LangLua, [[
require("moonlift").family.use { scope = "env", target = getfenv(1), global = false, override = true }

-- Outer unit diagnostic context.
return moonlift.unit. Bad {
  -- Returns an i32 from a deliberately invalid body.
  moonlift.fn. bad {} [moonlift.i32] {
    moonlift.ret true,
  },
}
]])

local bad = Analysis.analyze_document_full(bad_doc)
local diagnostics = Diagnostics.diagnostics(bad)
assert(#diagnostics > 0, "bad Lua DSL document should produce diagnostics")
assert(pvm.classof(diagnostics[1]) == E.DiagnosticFact, "diagnostic should be editor diagnostic fact")
local saw_context = false
local saw_outer_context = false
for i = 1, #diagnostics do
    assert(not diagnostics[i].message:match("context:"), "diagnostic message should not embed context")
    for j = 1, #(diagnostics[i].context or {}) do
        saw_context = saw_context or diagnostics[i].context[j].message:match("Returns an i32 from a deliberately invalid body%.") ~= nil
        saw_outer_context = saw_outer_context or diagnostics[i].context[j].message:match("Outer unit diagnostic context%.") ~= nil
    end
end
assert(saw_context, "editor diagnostics should include nearest declaration comment context")
assert(saw_outer_context, "editor diagnostics should include outer declaration comment context")

print("moonlift editor lua dsl analysis ok")
