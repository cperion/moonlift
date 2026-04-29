package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local Mlua = T.Moon2Mlua
local H = T.Moon2Host
local O = T.Moon2Open
local Tr = T.Moon2Tree
local B = T.Moon2Back
local Analysis = AnalysisMod.Define(T)

local uri = S.DocUri("file:///analysis.mlua")
local src = [[
struct User
    id: i32
    active: bool32
end
expose Users: view(User)
region Done(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
expr FortyTwo() -> i32
    42
end
func sum_to(n: index) -> i32
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + 1)
    end
end
func once() -> i32
    return block done() -> i32
        yield 0
    end
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
assert(pvm.classof(analysis) == Mlua.DocumentAnalysis)
assert(pvm.classof(analysis.host) == H.MluaHostPipelineResult)
assert(#analysis.parse.combined.issues == 0)
assert(#analysis.host.report.issues == 0)
assert(#analysis.host.layout_env.layouts == 1)
assert(#analysis.host.facts.facts > 0)
assert(pvm.classof(analysis.open_report) == O.ValidationReport)
assert(#analysis.open_report.issues == 0)
assert(pvm.classof(analysis.back_report) == B.BackValidationReport)
assert(#analysis.parse.combined.region_frags == 1)
assert(#analysis.parse.combined.expr_frags == 1)
assert(#analysis.control_facts >= 4)
assert(#analysis.vector_decisions >= 2)
assert(#analysis.vector_rejects >= 1)

local saw_view_descriptor, saw_access, saw_lua, saw_terra, saw_c = false, false, false, false, false
for i = 1, #analysis.host.facts.facts do
    local fact = analysis.host.facts.facts[i]
    if pvm.classof(fact) == H.HostFactViewDescriptor then saw_view_descriptor = true end
    if pvm.classof(fact) == H.HostFactAccessPlan then saw_access = true end
    if pvm.classof(fact) == H.HostFactLuaFfi then saw_lua = true end
    if pvm.classof(fact) == H.HostFactTerra then saw_terra = true end
    if pvm.classof(fact) == H.HostFactC then saw_c = true end
end
assert(saw_view_descriptor and saw_access and saw_lua and saw_terra and saw_c)

local bad_bool = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, "struct Bad\n  active: bool\nend\n")
local bad = Analysis.analyze_document(bad_bool)
assert(#bad.host.report.issues == 1)
assert(pvm.classof(bad.host.report.issues[1]) == H.HostIssueBareBoolInBoundaryStruct)

local type_bad = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, "func bad() -> i32\n  return missing\nend\n")
local type_bad_analysis = Analysis.analyze_document(type_bad)
assert(#type_bad_analysis.type_issues >= 1)
assert(pvm.classof(type_bad_analysis.type_issues[1]) == Tr.TypeIssueUnresolvedValue)

Analysis.document_analysis_phase:reset()
local parsed = analysis.parse
pvm.drain(Analysis.document_analysis_phase(parsed))
pvm.drain(Analysis.document_analysis_phase(parsed))
local report = pvm.report({ Analysis.document_analysis_phase })[1]
assert(report.calls == 2 and report.hits == 1)

print("moonlift mlua document analysis ok")
