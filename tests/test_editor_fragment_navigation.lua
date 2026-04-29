package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local DefMod = require("moonlift.editor_definition")
local RefMod = require("moonlift.editor_references")
local RenameMod = require("moonlift.editor_rename")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local E = T.Moon2Editor
local Analysis = AnalysisMod.Define(T)
local Def = DefMod.Define(T)
local Refs = RefMod.Define(T)
local Rename = RenameMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///fragments.mlua")
local src = [[
expr Inc(x: i32) -> i32
    x + 1
end
func use_inc(x: i32) -> i32
    return emit Inc(x)
end
region Done(x: i32; done: cont(v: i32))
entry start()
    jump done(v = x)
end
end
func use_region(x: i32) -> i32
    return region -> i32
    entry start()
        emit Done(x; done = out)
    end
    block out(v: i32)
        yield v
    end
    end
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
assert(#analysis.parse.combined.issues == 0, analysis.parse.combined.issues[1] and analysis.parse.combined.issues[1].message)
local idx = P.build_index(doc)
local function q_at_nth(needle, nth)
    local start = 1
    local s
    for _ = 1, nth do
        s = assert(src:find(needle, start, true))
        start = s + #needle
    end
    return E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(idx, s - 1).pos)
end

local inc_def = Def.definition(q_at_nth("Inc", 2), analysis)
assert(pvm.classof(inc_def) == E.DefinitionHit)
assert(src:sub(inc_def.ranges[1].start_offset + 1, inc_def.ranges[1].stop_offset) == "Inc")
local inc_refs = Refs.references(E.ReferenceQuery(q_at_nth("Inc", 1), true), analysis)
assert(pvm.classof(inc_refs) == E.ReferenceHit and #inc_refs.ranges == 2)
local inc_rename = Rename.rename(E.RenameQuery(q_at_nth("Inc", 2), "IncOne"), analysis)
assert(pvm.classof(inc_rename) == E.RenameOk and #inc_rename.edits == 2)

local region_def = Def.definition(q_at_nth("Done", 2), analysis)
assert(pvm.classof(region_def) == E.DefinitionHit)
assert(src:sub(region_def.ranges[1].start_offset + 1, region_def.ranges[1].stop_offset) == "Done")
local region_refs = Refs.references(E.ReferenceQuery(q_at_nth("Done", 1), true), analysis)
assert(pvm.classof(region_refs) == E.ReferenceHit and #region_refs.ranges == 2)
local region_rename = Rename.rename(E.RenameQuery(q_at_nth("Done", 2), "DoneRegion"), analysis)
assert(pvm.classof(region_rename) == E.RenameOk and #region_rename.edits == 2)

print("moonlift editor fragment navigation ok")
