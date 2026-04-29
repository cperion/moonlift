package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local SubjectMod = require("moonlift.editor_subject_at")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local E = T.Moon2Editor
local C = T.Moon2Core
local Analysis = AnalysisMod.Define(T)
local Subject = SubjectMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///subject.mlua")
local src = [[
local lua = 1
struct User
    id: i32
    active: bool32
end
expose Users: view(User)
func User:is_active(self: ptr(User)) -> bool
    return true
end
region Done(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
expr FortyTwo() -> i32
    42
end
module Math
    export func two() -> i32
        return 2
    end
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local idx = P.build_index(doc)
local function query_at(text)
    local s = assert(src:find(text, 1, true))
    local pos = P.offset_to_pos(idx, s - 1).pos
    return E.PositionQuery(uri, S.DocVersion(1), pos)
end

local struct_pick = Subject.subject_at(query_at("User"), analysis)
assert(pvm.classof(struct_pick.subject) == E.SubjectHostStruct)
assert(#struct_pick.anchors > 0)

local field_pick = Subject.subject_at(query_at("id"), analysis)
assert(pvm.classof(field_pick.subject) == E.SubjectHostField)

local scalar_pick = Subject.subject_at(query_at("i32"), analysis)
assert(pvm.classof(scalar_pick.subject) == E.SubjectScalar)
assert(scalar_pick.subject.scalar == C.ScalarI32)

local expose_pick = Subject.subject_at(query_at("Users"), analysis)
assert(pvm.classof(expose_pick.subject) == E.SubjectHostExpose)

local method_pick = Subject.subject_at(query_at("User:is_active"), analysis)
assert(pvm.classof(method_pick.subject) == E.SubjectHostAccessor or pvm.classof(method_pick.subject) == E.SubjectTreeFunc)

local region_pick = Subject.subject_at(query_at("Done"), analysis)
assert(pvm.classof(region_pick.subject) == E.SubjectRegionFrag)

local expr_pick = Subject.subject_at(query_at("FortyTwo"), analysis)
assert(pvm.classof(expr_pick.subject) == E.SubjectExprFrag)

local module_pick = Subject.subject_at(query_at("Math"), analysis)
assert(pvm.classof(module_pick.subject) == E.SubjectTreeModule)

local opaque_pos = P.offset_to_pos(idx, assert(src:find("lua = 1", 1, true)) - 1).pos
local opaque = Subject.subject_at(E.PositionQuery(uri, S.DocVersion(1), opaque_pos), analysis)
assert(pvm.classof(opaque.subject) == E.SubjectMissing)

Subject.subject_at_phase:reset()
pvm.drain(Subject.subject_at_phase(query_at("User"), analysis))
pvm.drain(Subject.subject_at_phase(query_at("User"), analysis))
local report = pvm.report({ Subject.subject_at_phase })[1]
assert(report.calls == 2 and report.hits == 1)

print("moonlift editor subject at ok")
