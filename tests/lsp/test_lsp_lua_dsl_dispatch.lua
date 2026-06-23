package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_projection")

local T = pvm.context()
schema.Define(T)

local S = T.MoonSource
local E = T.MoonEditor
local R = T.MoonRpc
local L = T.MoonLsp

local Dispatch = require("moonlift.lsp_dispatch").Define(T)
assert(Dispatch.document_events_process, "LSP exposes document process")

local uri = S.DocUri("file:///lsp_lua_dsl_test.lua")
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangLua, [[
require("moonlift").family.use { scope = "env", target = getfenv(1), global = false, override = true }

return moonlift.unit. LspSmoke {
  moonlift.fn. add { a [moonlift.i32], b [moonlift.i32] } [moonlift.i32] {
    moonlift.ret (a + b),
  },
}
]])

local state = E.WorkspaceState(E.ServerReady, {}, {}, { doc }, E.WorkspaceIndex(1, {}))

local symbol_cmds = Dispatch.commands(E.Transition(
    state,
    E.ClientDocumentSymbol(E.RpcIdNumber(1), uri),
    state
))

assert(#symbol_cmds == 1, "documentSymbol should emit one command")
assert(pvm.classof(symbol_cmds[1]) == R.SendMessage, "documentSymbol command should send message")
assert(pvm.classof(symbol_cmds[1].outgoing) == R.RpcResult, "documentSymbol should be an RPC result")
assert(pvm.classof(symbol_cmds[1].outgoing.payload) == L.PayloadDocumentSymbols, "documentSymbol payload class")
assert(#symbol_cmds[1].outgoing.payload.symbols > 0, "documentSymbol should return symbols")

local lsp_events = {}
for ev in Dispatch.document_events_process(doc, { symbols = true }) do
    lsp_events[#lsp_events + 1] = ev
end
local saw_index, saw_symbol = false, false
for _, ev in ipairs(lsp_events) do
    if ev.kind == "index" then saw_index = true end
    if ev.kind == "symbol" then saw_symbol = true end
end
assert(saw_index and saw_symbol, "LSP document process yields index and symbol events")

local bad_uri = S.DocUri("file:///lsp_lua_dsl_bad.lua")
local bad_doc = S.DocumentSnapshot(bad_uri, S.DocVersion(1), S.LangLua, [[
require("moonlift").family.use { scope = "env", target = getfenv(1), global = false, override = true }

return moonlift.unit. Bad {
  moonlift.fn. bad {} [moonlift.i32] {
    moonlift.ret true,
  },
}
]])
local bad_state = E.WorkspaceState(E.ServerReady, {}, {}, { bad_doc }, E.WorkspaceIndex(1, {}))

local diag_cmds = Dispatch.commands(E.Transition(
    bad_state,
    E.ClientDiagnostic(E.RpcIdNumber(2), bad_uri),
    bad_state
))

assert(#diag_cmds == 1, "diagnostic should emit one command")
assert(pvm.classof(diag_cmds[1]) == R.SendMessage, "diagnostic command should send message")
assert(pvm.classof(diag_cmds[1].outgoing) == R.RpcResult, "diagnostic should be an RPC result")
assert(pvm.classof(diag_cmds[1].outgoing.payload) == L.PayloadDiagnosticDocumentReport, "diagnostic payload class")
assert(#diag_cmds[1].outgoing.payload.report.items > 0, "diagnostic should return items")

print("moonlift lsp lua dsl dispatch ok")
