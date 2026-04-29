package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local SourceApply = require("moonlift.source_text_apply")
local Workspace = require("moonlift.editor_workspace_apply")
local Transition = require("moonlift.editor_transition")

local T = pvm.context()
A.Define(T)
local S = T.MoonSource
local E = T.MoonEditor
local Apply = SourceApply.Define(T)
local W = Workspace.Define(T)
local W2 = Transition.Define(T)
assert(type(W2.initial_state) == "function")

local uri1 = S.DocUri("file:///one.mlua")
local uri2 = S.DocUri("file:///two.mlua")
local function doc(uri, version, text)
    return S.DocumentSnapshot(uri, S.DocVersion(version), S.LangMlua, text)
end

local state = W.initial_state()
assert(state.mode == E.ServerCreated)
assert(#state.open_docs == 0)

local init = E.ClientInitialize(E.RpcIdNumber(1), { E.WorkspaceRoot(S.DocUri("file:///")) }, { E.ClientCapability("positionEncoding", "utf-16") })
local tr = W.apply_event(state, init)
assert(tr.before == state)
assert(tr.after.mode == E.ServerInitializing)
assert(#tr.after.roots == 1)
state = tr.after

tr = W.apply_event(state, E.ClientInitialized)
assert(tr.after.mode == E.ServerReady)
state = tr.after

local d1 = doc(uri1, 1, "hello")
tr = W.apply_event(state, E.ClientDidOpen(d1))
assert(#tr.after.open_docs == 1)
assert(tr.after.open_docs[1] == d1)
state = tr.after

local reopen = W.apply_event(state, E.ClientDidOpen(d1))
assert(#reopen.after.open_docs == 1)
assert(reopen.after.open_docs[1] == d1)
state = reopen.after

local d2 = doc(uri2, 1, "second")
state = W.apply_event(state, E.ClientDidOpen(d2)).after
assert(#state.open_docs == 2)

local r = Apply.range(d1, 1, 4)
local edit = S.DocumentEdit(uri1, S.DocVersion(2), { S.ReplaceRange(r, "ipp") })
tr = W.apply_event(state, E.ClientDidChange(edit))
assert(#tr.after.open_docs == 2)
local _, changed = W.find_doc(tr.after.open_docs, uri1)
assert(changed.text == "hippo")
assert(changed.version == S.DocVersion(2))
local _, unchanged = W.find_doc(tr.after.open_docs, uri2)
assert(unchanged == d2)
state = tr.after

local hover_query = E.PositionQuery(uri1, S.DocVersion(2), S.SourcePos(0, 1, 1))
tr = W.apply_event(state, E.ClientHover(E.RpcIdNumber(2), hover_query))
assert(tr.after == state)

tr = W.apply_event(state, E.ClientDidSave(uri1))
assert(tr.after == state)

state = W.apply_event(state, E.ClientDidClose(uri2)).after
assert(#state.open_docs == 1)
assert(state.open_docs[1].uri == uri1)

state = W.apply_event(state, E.ClientShutdown(E.RpcIdNumber(3))).after
assert(state.mode == E.ServerShutdownRequested)
state = W.apply_event(state, E.ClientExit).after
assert(state.mode == E.ServerStopped)

local stale_edit = S.DocumentEdit(uri1, S.DocVersion(1), { S.ReplaceAll("bad") })
local stale_tr = W.apply_event(state, E.ClientDidChange(stale_edit))
assert(stale_tr.after == state)

print("moonlift editor workspace apply ok")
