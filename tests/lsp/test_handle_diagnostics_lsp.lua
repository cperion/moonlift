package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local ItemsMod = require("moonlift.editor_completion_items")
local HoverMod = require("moonlift.editor_hover")
local PositionIndex = require("moonlift.source_position_index")
local TCMod = require("moonlift.tree_typecheck")

local T = pvm.context()
A.Define(T)

local S = T.MoonSource
local E = T.MoonEditor
local Analysis = AnalysisMod.Define(T)
local Items = ItemsMod.Define(T)
local Hover = HoverMod.Define(T)
local P = PositionIndex.Define(T)
local Parse = require("moonlift.parse").Define(T)
local TC = TCMod.Define(T)

local function first_issue(src, wanted_op)
    local parsed = Parse.parse_module(src)
    local typed = TC.check_module(parsed.module)
    for i = 1, #typed.issues do
        local issue = typed.issues[i]
        if not wanted_op or issue.op == wanted_op then return issue end
    end
    error("missing issue " .. tostring(wanted_op), 2)
end

local function explain(issue)
    return TCMod.explain_type_issue(issue, { anchors = {} })
end

local d_return = explain(first_issue([[func bad(p: lease ptr(i32)): ptr(i32)
    return p
end
]], "lease escape return"))
assert(d_return.primary.message:match("lease escapes through return"))
assert(d_return.notes[1].message:match("temporary access"))

local d_call = explain(first_issue([[extern retain(p: ptr(i32)): void end
func bad(p: lease ptr(i32)): void
    retain(p)
end
]], "lease escape call"))
assert(d_call.primary.message:match("retaining parameter"))
assert(d_call.suggestions[1].message:match("noescape"))

local d_invalidate = explain(first_issue([[struct Store x: i32 end
func mutate(s: ptr(Store)): void return end
func bad(s: ptr(Store), p: lease(s) ptr(i32)): void
    mutate(s)
end
]], "lease invalidating call"))
assert(d_invalidate.primary.message:match("invalidate store"))
assert(d_invalidate.notes[1].message:match("move, free, compact"))

local d_handle = explain(first_issue([[local Voice = handle Voice : u32 invalid 0 end
func bad(v: Voice): u32
    return as(u32, v)
end
]], "handle cast"))
assert(d_handle.primary.message:match("opaque"))
assert(d_handle.suggestions[1].message:match("repr"))

local uri = S.DocUri("file:///handle_lsp.mlua")
local src = [[local Voice = handle Voice : u32 invalid 0 end
struct Store
    slot: i32,
end
func use(s: ptr(Store), v: Voice, p: lease(s) ptr(i32)): Voice
    return v
end
]]
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangMlua, src)
local analysis = Analysis.analyze_document(doc)
local idx = P.build_index(doc)
local function query_at(text, skip)
    local off = -1
    for _ = 1, (skip or 0) + 1 do
        local s = assert(src:find(text, off + 2, true))
        off = s - 1
    end
    return E.PositionQuery(uri, S.DocVersion(1), P.offset_to_pos(idx, off).pos)
end
local function has(items, label)
    for i = 1, #items do if items[i].label == label then return true end end
    return false
end

local h = Hover.hover(query_at("Voice", 1), analysis)
assert(pvm.classof(h) == E.HoverInfo)
assert(h.value:match("handle `Voice`"))
assert(h.value:match("opaque durable identity"))

local type_items = Items.items(E.CompletionQuery(query_at("slot"), E.CompletionTypePosition), analysis)
assert(has(type_items, "lease"))
assert(has(type_items, "noescape"))
assert(has(type_items, "preserve"))
assert(has(type_items, "invalidate"))
assert(has(type_items, "Voice"))

print("moonlift handle diagnostics lsp ok")
