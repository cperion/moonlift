package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local ActionsMod = require("moonlift.editor_code_actions")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local E = T.MoonEditor
local Analysis = AnalysisMod.Define(T)
local Actions = ActionsMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///actions.mlua")
local function analyze(text)
    local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, text)
    return Analysis.analyze_document(doc), doc
end
local function full_query(doc)
    local idx = P.build_index(doc)
    local r = assert(P.range_from_offsets(idx, 0, #doc.text))
    return E.CodeActionQuery(E.RangeQuery(uri, doc.version, r), {})
end
local function edit_text(src, edit)
    return src:sub(edit.range.start_offset + 1, edit.range.stop_offset)
end

local bool_src = "struct Bad\n  active: bool\nend\n"
local bool_analysis, bool_doc = analyze(bool_src)
local bool_actions = Actions.actions(full_query(bool_doc), bool_analysis)
assert(#bool_actions == 2)
assert(bool_actions[1].kind == E.CodeActionQuickFix)
assert(bool_actions[1].diagnostics[1].code == "host.bareBoolBoundary")
assert(edit_text(bool_src, bool_actions[1].edit.edits[1]) == "bool")
assert(bool_actions[1].edit.edits[1].new_text == "bool32")
assert(bool_actions[2].edit.edits[1].new_text == "bool8")

local packed_src = "struct Bad repr(packed(3))\n  id: i32\nend\n"
local packed_analysis, packed_doc = analyze(packed_src)
local packed_actions = Actions.actions(full_query(packed_doc), packed_analysis)
assert(#packed_actions >= 3)
assert(packed_actions[1].diagnostics[1].code == "host.invalidPackedAlign")
assert(edit_text(packed_src, packed_actions[1].edit.edits[1]) == "3")
local saw4 = false
for i = 1, #packed_actions do
    if packed_actions[i].edit.edits[1].new_text == "4" then saw4 = true end
end
assert(saw4)

local dup_field_src = "struct Dup\n  id: i32\n  id: i32\nend\n"
local dup_field_analysis, dup_field_doc = analyze(dup_field_src)
local dup_field_range = assert(P.range_from_offsets(P.build_index(dup_field_doc), dup_field_src:find("id", dup_field_src:find("id") + 1, true) - 1, dup_field_src:find("id", dup_field_src:find("id") + 1, true) + 1))
local dup_field_diag = E.DiagnosticFact(E.DiagnosticError, E.DiagFromHost(T.MoonHost.HostIssueDuplicateField("Dup", "id")), "host.duplicateField", "duplicate field", dup_field_range)
local dup_field_actions = Actions.actions(E.CodeActionQuery(E.RangeQuery(uri, dup_field_doc.version, dup_field_range), { dup_field_diag }), dup_field_analysis)
assert(#dup_field_actions >= 1)
assert(dup_field_actions[1].diagnostics[1].code == "host.duplicateField")
assert(dup_field_actions[1].edit.edits[1].new_text == "id_2")

local dup_decl_src = "struct A\n  id: i32\nend\nstruct A\n  id: i32\nend\n"
local dup_decl_analysis, dup_decl_doc = analyze(dup_decl_src)
local dup_decl_actions = Actions.actions(full_query(dup_decl_doc), dup_decl_analysis)
assert(#dup_decl_actions >= 1)
assert(dup_decl_actions[1].diagnostics[1].code == "host.duplicateDecl")
assert(dup_decl_actions[1].edit.edits[1].new_text == "A_2")

local unresolved_src = "func unresolved() -> i32\n    return missing + 1\nend\n"
local unresolved_analysis, unresolved_doc = analyze(unresolved_src)
local unresolved_actions = Actions.actions(full_query(unresolved_doc), unresolved_analysis)
local saw_declare = false
for i = 1, #unresolved_actions do
    if unresolved_actions[i].diagnostics[1].code == "binding.unresolved" then
        saw_declare = true
        assert(unresolved_actions[i].title == "Declare local 'missing' as i32")
        assert(unresolved_actions[i].edit.edits[1].new_text == "    let missing: i32 = 0\n")
        assert(unresolved_actions[i].edit.edits[1].range.start_offset == unresolved_src:find("    return", 1, true) - 1)
    end
end
assert(saw_declare)

print("moonlift editor code actions ok")
