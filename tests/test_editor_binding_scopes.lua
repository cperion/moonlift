package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local BindingMod = require("moonlift.editor_binding_facts")
local ScopeMod = require("moonlift.editor_binding_scope_facts")
local DefMod = require("moonlift.editor_definition")
local RefMod = require("moonlift.editor_references")
local RenameMod = require("moonlift.editor_rename")
local HighlightMod = require("moonlift.editor_document_highlight")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local E = T.MoonEditor
local Analysis = AnalysisMod.Define(T)
local Bind = BindingMod.Define(T)
local Scopes = ScopeMod.Define(T)
local Def = DefMod.Define(T)
local Refs = RefMod.Define(T)
local Rename = RenameMod.Define(T)
local Highlight = HighlightMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///binding_scopes.mlua")
local src = [[
func shadow(x: i32) -> i32
    let y: i32 = x
    if x > 0 then
        let y: i32 = y
        y = y + 1
        return y
    end
    return y
end
func branch_scope(x: i32) -> i32
    if x > 0 then
        let z: i32 = x
        return z
    else
        let z: i32 = x + 1
        return z
    end
end
func forward_block(n: i32) -> i32
    return region -> i32
    entry start()
        jump done(v = n)
    end
    block done(v: i32)
        yield v
    end
    end
end
region DoneRegion(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
assert(#analysis.parse.combined.issues == 0, analysis.parse.combined.issues[1] and analysis.parse.combined.issues[1].message)
local idx = P.build_index(doc)

local function pos_at_nth(needle, nth)
    local start = 1
    local s
    for _ = 1, nth do
        s = assert(src:find(needle, start, true))
        start = s + #needle
    end
    return s - 1
end

local function q_at_nth(needle, nth)
    return E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(idx, pos_at_nth(needle, nth)).pos)
end

local function def_start_at(needle, nth)
    local d = Def.definition(q_at_nth(needle, nth), analysis)
    assert(pvm.classof(d) == E.DefinitionHit, needle .. " #" .. tostring(nth) .. " missed")
    return d.ranges[1].start_offset
end

local outer_y = pos_at_nth("y", 1)
local inner_y = pos_at_nth("y", 2)
assert(def_start_at("y", 3) == outer_y) -- inner initializer RHS reads the outer y, not the just-declared y
assert(def_start_at("y", 4) == inner_y) -- assignment target writes inner y
assert(def_start_at("y", 5) == inner_y) -- assignment RHS reads inner y
assert(def_start_at("y", 6) == inner_y) -- return inside if reads inner y
assert(def_start_at("y", 7) == outer_y) -- after if, inner y is out of scope

local facts = Bind.facts(analysis)
local function role_at(needle, nth)
    local offset = pos_at_nth(needle, nth)
    for i = 1, #facts do
        local r = facts[i].anchor.range
        if r.start_offset == offset and r.stop_offset == offset + #needle then return facts[i].role end
    end
    error("missing binding fact for " .. needle .. " #" .. tostring(nth))
end
assert(role_at("y", 4) == E.BindingWrite)
assert(role_at("y", 5) == E.BindingRead)
assert(role_at("total", 3) == E.BindingWrite)
assert(role_at("total", 4) == E.BindingRead)

local block_v = pos_at_nth("v", 2)
assert(def_start_at("v", 1) == block_v)
assert(def_start_at("v", 3) == block_v)
assert(role_at("v", 1) == E.BindingWrite)
local v_rename = Rename.rename(E.RenameQuery(q_at_nth("v", 1), "value"), analysis)
assert(pvm.classof(v_rename) == E.RenameOk and #v_rename.edits == 3)

local then_z = pos_at_nth("z", 1)
local else_z = pos_at_nth("z", 3)
assert(def_start_at("z", 2) == then_z)
assert(def_start_at("z", 4) == else_z)
local then_z_rename = Rename.rename(E.RenameQuery(q_at_nth("z", 2), "then_z"), analysis)
assert(pvm.classof(then_z_rename) == E.RenameOk and #then_z_rename.edits == 2)
for i = 1, #then_z_rename.edits do assert(then_z_rename.edits[i].range.start_offset ~= else_z) end

local total_slot_def = pos_at_nth("total", 1)
local total_entry_def = pos_at_nth("total", 2)
assert(def_start_at("total", 3) == total_slot_def)
assert(def_start_at("total", 4) == total_entry_def)

local inner_rename = Rename.rename(E.RenameQuery(q_at_nth("y", 4), "inner"), analysis)
assert(pvm.classof(inner_rename) == E.RenameOk)
assert(#inner_rename.edits == 4)
for i = 1, #inner_rename.edits do
    assert(src:sub(inner_rename.edits[i].range.start_offset + 1, inner_rename.edits[i].range.stop_offset) == "y")
    assert(inner_rename.edits[i].range.start_offset ~= outer_y)
end

local outer_refs = Refs.references(E.ReferenceQuery(q_at_nth("y", 1), true), analysis)
assert(pvm.classof(outer_refs) == E.ReferenceHit)
local saw_inner_init_rhs, saw_after_if = false, false
for i = 1, #outer_refs.ranges do
    if outer_refs.ranges[i].start_offset == pos_at_nth("y", 3) then saw_inner_init_rhs = true end
    if outer_refs.ranges[i].start_offset == pos_at_nth("y", 7) then saw_after_if = true end
    assert(outer_refs.ranges[i].start_offset ~= inner_y)
end
assert(saw_inner_init_rhs and saw_after_if)

local highlights = Highlight.highlights(q_at_nth("y", 4), analysis)
local saw_write = false
for i = 1, #highlights do
    if highlights[i].range.start_offset == pos_at_nth("y", 4) then
        assert(highlights[i].kind == E.HighlightWrite)
        saw_write = true
    end
end
assert(saw_write)

local scope_report = Scopes.report(analysis)
assert(#scope_report.scopes > 0)
assert(#scope_report.bindings > 0)
assert(#scope_report.resolutions > 0)

print("moonlift editor binding scopes ok")
