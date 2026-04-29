package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local BindingMod = require("moonlift.editor_binding_facts")
local DefMod = require("moonlift.editor_definition")
local RefMod = require("moonlift.editor_references")
local RenameMod = require("moonlift.editor_rename")
local HighlightMod = require("moonlift.editor_document_highlight")
local PositionIndex = require("moonlift.source_position_index")

local T = pvm.context()
A.Define(T)
local S = T.Moon2Source
local E = T.Moon2Editor
local Analysis = AnalysisMod.Define(T)
local Bind = BindingMod.Define(T)
local Def = DefMod.Define(T)
local Refs = RefMod.Define(T)
local Rename = RenameMod.Define(T)
local Highlight = HighlightMod.Define(T)
local P = PositionIndex.Define(T)

local uri = S.DocUri("file:///binding.mlua")
local src = [[
struct User
    id: i32
    active: bool32
end
expose Users: view(User)
func User:is_active(self: ptr(User)) -> bool
    return true
end
func get_id(self: ptr(User)) -> i32
    return self.id
end
func add(a: i32, b: i32) -> i32
    return a
end
func local_scope(input_value: i32) -> i32
    let local_value: i32 = input_value
    return local_value
end
func count_to(n: i32) -> i32
    return block loop(i: i32 = 0) -> i32
        if i >= n then yield i end
        jump loop(i = i + 1)
    end
end
region DoneRegion(n: i32; done: cont(total: i32))
entry start(total: i32 = 0)
    jump done(total = total)
end
end
module ScopedLoops
    func left(n: i32) -> i32
        return block loop(i: i32 = 0) -> i32
            if i >= n then yield i end
            jump loop(i = i + 1)
        end
    end
    func right(n: i32) -> i32
        return block loop(i: i32 = 0) -> i32
            if i >= n then yield i end
            jump loop(i = i + 1)
        end
    end
end
expr Use() -> i32
    add(1, 2)
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
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

local function q_at_text(needle, delta)
    local s = assert(src:find(needle, 1, true))
    return E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(idx, s - 1 + (delta or 0)).pos)
end

local facts = Bind.facts(analysis)
local saw_struct_def, saw_struct_use = false, false
for i = 1, #facts do
    if facts[i].id == E.SymbolId("host.struct.User") and facts[i].role == E.BindingDef then saw_struct_def = true end
    if facts[i].id == E.SymbolId("host.struct.User") and facts[i].role == E.BindingTypeUse then saw_struct_use = true end
end
assert(saw_struct_def and saw_struct_use)

local def = Def.definition(q_at_nth("User", 3), analysis) -- User in expose Users: view(User)
assert(pvm.classof(def) == E.DefinitionHit)
assert(#def.ranges >= 1)
assert(src:sub(def.ranges[1].start_offset + 1, def.ranges[1].stop_offset) == "User")

local refs = Refs.references(E.ReferenceQuery(q_at_nth("User", 1), true), analysis)
assert(pvm.classof(refs) == E.ReferenceHit)
assert(#refs.ranges >= 3)

local highlights = Highlight.highlights(q_at_nth("User", 1), analysis)
assert(#highlights >= 3)
for i = 1, #highlights do assert(highlights[i].kind == E.HighlightText) end

local prepared = Rename.prepare_rename(q_at_nth("User", 3), analysis)
assert(pvm.classof(prepared) == E.PrepareRenameOk)
assert(src:sub(prepared.range.start_offset + 1, prepared.range.stop_offset) == "User")

local rename = Rename.rename(E.RenameQuery(q_at_nth("User", 1), "Person"), analysis)
assert(pvm.classof(rename) == E.RenameOk)
assert(#rename.edits >= 3)
for i = 1, #rename.edits do assert(rename.edits[i].new_text == "Person") end

local field_def = Def.definition(q_at_nth("id", 3), analysis) -- id in self.id
assert(pvm.classof(field_def) == E.DefinitionHit)
assert(src:sub(field_def.ranges[1].start_offset + 1, field_def.ranges[1].stop_offset) == "id")
local field_refs = Refs.references(E.ReferenceQuery(q_at_nth("id", 1), true), analysis)
assert(pvm.classof(field_refs) == E.ReferenceHit and #field_refs.ranges >= 2)
local field_rename = Rename.rename(E.RenameQuery(q_at_nth("id", 3), "user_id"), analysis)
assert(pvm.classof(field_rename) == E.RenameOk and #field_rename.edits >= 2)

local call_def = Def.definition(q_at_nth("add", 2), analysis) -- call in expr Use
assert(pvm.classof(call_def) == E.DefinitionHit)
assert(src:sub(call_def.ranges[1].start_offset + 1, call_def.ranges[1].stop_offset) == "add")
local call_refs = Refs.references(E.ReferenceQuery(q_at_nth("add", 1), true), analysis)
assert(pvm.classof(call_refs) == E.ReferenceHit and #call_refs.ranges >= 2)
local call_rename = Rename.rename(E.RenameQuery(q_at_nth("add", 2), "add_i32"), analysis)
assert(pvm.classof(call_rename) == E.RenameOk and #call_rename.edits >= 2)

local local_def = Def.definition(q_at_nth("input_value", 2), analysis)
assert(pvm.classof(local_def) == E.DefinitionHit)
assert(src:sub(local_def.ranges[1].start_offset + 1, local_def.ranges[1].stop_offset) == "input_value")
local local_refs = Refs.references(E.ReferenceQuery(q_at_nth("local_value", 1), true), analysis)
assert(pvm.classof(local_refs) == E.ReferenceHit and #local_refs.ranges >= 2)
local local_rename = Rename.rename(E.RenameQuery(q_at_nth("local_value", 2), "result_value"), analysis)
assert(pvm.classof(local_rename) == E.RenameOk and #local_rename.edits >= 2)

local loop_def = Def.definition(q_at_nth("loop", 2), analysis) -- loop in jump loop(...)
assert(pvm.classof(loop_def) == E.DefinitionHit)
assert(#loop_def.ranges == 1)
assert(src:sub(loop_def.ranges[1].start_offset + 1, loop_def.ranges[1].stop_offset) == "loop")
local loop_refs = Refs.references(E.ReferenceQuery(q_at_nth("loop", 1), true), analysis)
assert(pvm.classof(loop_refs) == E.ReferenceHit and #loop_refs.ranges >= 2)
local loop_rename = Rename.rename(E.RenameQuery(q_at_nth("loop", 2), "again"), analysis)
assert(pvm.classof(loop_rename) == E.RenameOk and #loop_rename.edits >= 2)
local block_param_def = Def.definition(q_at_text("i >= n"), analysis)
assert(pvm.classof(block_param_def) == E.DefinitionHit)
assert(src:sub(block_param_def.ranges[1].start_offset + 1, block_param_def.ranges[1].stop_offset) == "i")
local jump_arg_def = Def.definition(q_at_text("i = i + 1"), analysis)
assert(pvm.classof(jump_arg_def) == E.DefinitionHit)
assert(src:sub(jump_arg_def.ranges[1].start_offset + 1, jump_arg_def.ranges[1].stop_offset) == "i")

local cont_slot_def = Def.definition(q_at_nth("done", 2), analysis) -- done in jump done(...)
assert(pvm.classof(cont_slot_def) == E.DefinitionHit)
assert(src:sub(cont_slot_def.ranges[1].start_offset + 1, cont_slot_def.ranges[1].stop_offset) == "done")
local cont_slot_refs = Refs.references(E.ReferenceQuery(q_at_nth("done", 1), true), analysis)
assert(pvm.classof(cont_slot_refs) == E.ReferenceHit and #cont_slot_refs.ranges >= 2)

local scoped_loop_refs = Refs.references(E.ReferenceQuery(q_at_nth("loop", 3), true), analysis)
assert(pvm.classof(scoped_loop_refs) == E.ReferenceHit and #scoped_loop_refs.ranges == 2)
for i = 1, #scoped_loop_refs.ranges do
    local before = src:sub(1, scoped_loop_refs.ranges[i].start_offset)
    assert(before:find("func left", 1, true))
    assert(not before:find("func right", 1, true))
end

local bad = Rename.rename(E.RenameQuery(q_at_nth("User", 1), "not valid"), analysis)
assert(pvm.classof(bad) == E.RenameRejected)

local scalar_rename = Rename.rename(E.RenameQuery(q_at_nth("i32", 1), "numberish"), analysis)
assert(pvm.classof(scalar_rename) == E.RenameRejected)

print("moonlift editor binding navigation ok")
