package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local DiagMod = require("moonlift.editor_diagnostic_facts")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local E = T.Moon2Editor
local H = T.Moon2Host
local O = T.Moon2Open
local Tr = T.Moon2Tree
local B = T.Moon2Back
local V = T.Moon2Vec
local Analysis = AnalysisMod.Define(T)
local Diag = DiagMod.Define(T)

local uri = S.DocUri("file:///diag.mlua")
local function doc(text)
    return S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, text)
end

local parse_bad = Analysis.analyze_document(doc([[expr Bad() -> i32
    @
end
]]))
local parse_diags = Diag.diagnostics(parse_bad)
assert(#parse_diags >= 1)
assert(parse_diags[1].severity == E.DiagnosticError)
assert(pvm.classof(parse_diags[1].origin) == E.DiagFromParse)
assert(parse_diags[1].code == "parse")
assert(parse_diags[1].message:match("expected expression"))
assert(parse_diags[1].range.uri == uri)
assert(parse_diags[1].range.start.line >= 1)

local host_bad = Analysis.analyze_document(doc("struct Bad\n  active: bool\nend\n"))
local host_diags = Diag.diagnostics(host_bad)
assert(#host_diags == 1)
assert(pvm.classof(host_diags[1].origin) == E.DiagFromHost)
assert(pvm.classof(host_diags[1].origin.issue) == H.HostIssueBareBoolInBoundaryStruct)
assert(host_diags[1].code == "host.bareBoolBoundary")
assert(host_diags[1].range.start_offset <= (host_bad.parse.parts.document.text:find("active", 1, true) - 1))
assert(host_diags[1].range.stop_offset >= (host_bad.parse.parts.document.text:find("active", 1, true) - 1))

local dup = Analysis.analyze_document(doc("struct Dup\n id: i32\n id: i32\nend\n"))
local dup_diags = Diag.diagnostics(dup)
assert(#dup_diags == 1)
assert(dup_diags[1].code == "host.duplicateField")
assert(pvm.classof(dup_diags[1].origin.issue) == H.HostIssueDuplicateField)

local dup_decl = Analysis.analyze_document(doc("struct A\n id: i32\nend\nstruct A\n id: i32\nend\n"))
local dup_decl_diags = Diag.diagnostics(dup_decl)
assert(#dup_decl_diags == 1)
assert(dup_decl_diags[1].code == "host.duplicateDecl")

local bad_align = Analysis.analyze_document(doc("struct Bad repr(packed(3))\n id: i32\nend\n"))
local bad_align_diags = Diag.diagnostics(bad_align)
assert(#bad_align_diags == 1)
assert(bad_align_diags[1].code == "host.invalidPackedAlign")

local unresolved = Analysis.analyze_document(doc("func unresolved() -> i32\n    return missing + 1\nend\n"))
local unresolved_diags = Diag.diagnostics(unresolved)
local saw_unresolved = false
for i = 1, #unresolved_diags do
    if unresolved_diags[i].code == "binding.unresolved" then
        saw_unresolved = true
        assert(pvm.classof(unresolved_diags[i].origin) == E.DiagFromBindingResolution)
        assert(unresolved_diags[i].message:match("missing"))
        assert(unresolved.parse.parts.document.text:sub(unresolved_diags[i].range.start_offset + 1, unresolved_diags[i].range.stop_offset) == "missing")
    end
    assert(unresolved_diags[i].code ~= "type.invalidBinary")
end
assert(saw_unresolved)

local invalid_binary_src = "func bad_binary() -> i32\n    return 1 + true\nend\n"
local invalid_binary = Analysis.analyze_document(doc(invalid_binary_src))
local invalid_binary_diags = Diag.diagnostics(invalid_binary)
local saw_invalid_binary = false
for i = 1, #invalid_binary_diags do
    if invalid_binary_diags[i].code == "type.invalidBinary" then
        saw_invalid_binary = true
        assert(pvm.classof(invalid_binary_diags[i].origin) == E.DiagFromType)
        assert(invalid_binary_diags[i].message:match("invalid binary operands"))
        assert(invalid_binary_src:sub(invalid_binary_diags[i].range.start_offset + 1, invalid_binary_diags[i].range.stop_offset) == "+")
    end
end
assert(saw_invalid_binary)

local return_src = "func wrong_return() -> bool\n    return 1\nend\n"
local return_bad = Analysis.analyze_document(doc(return_src))
local return_diags = Diag.diagnostics(return_bad)
local saw_expected = false
for i = 1, #return_diags do
    if return_diags[i].code == "type.expected" then
        saw_expected = true
        assert(return_diags[i].message:match("return expected bool, got i32"))
        assert(return_src:sub(return_diags[i].range.start_offset + 1, return_diags[i].range.stop_offset) == "return")
    end
end
assert(saw_expected)

local parsed = host_bad.parse
local base = host_bad.host
local synthetic = T.Moon2Mlua.DocumentAnalysis(
    parsed,
    base,
    O.ValidationReport({ O.IssueOpenModuleName }),
    { Tr.TypeIssueUnresolvedValue("missing") },
    {},
    {},
    { V.VecRejectUnsupportedLoop(V.VecLoopId("loop"), "test") },
    B.BackValidationReport({ B.BackIssueMissingFinalize }),
    host_bad.anchors
)
local synthetic_diags = Diag.diagnostics(synthetic)
local saw_open, saw_type, saw_vec, saw_back = false, false, false, false
for i = 1, #synthetic_diags do
    local origin = synthetic_diags[i].origin
    if pvm.classof(origin) == E.DiagFromOpen then saw_open = true end
    if pvm.classof(origin) == E.DiagFromType then saw_type = true end
    if pvm.classof(origin) == E.DiagFromVectorReject then saw_vec = true end
    if pvm.classof(origin) == E.DiagFromBack then
        saw_back = true
        assert(synthetic_diags[i].code == "back.missingFinalize")
        assert(synthetic_diags[i].message:match("missing finalization"))
    end
end
assert(saw_open and saw_type and saw_back)
assert(not saw_vec)

Diag.document_diagnostics_phase:reset()
pvm.drain(Diag.document_diagnostics_phase(host_bad))
pvm.drain(Diag.document_diagnostics_phase(host_bad))
local report = pvm.report({ Diag.document_diagnostics_phase })[1]
assert(report.calls == 2 and report.hits == 1)

print("moonlift editor diagnostic facts ok")
