package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local schema = require("moonlift.asdl")

local T = pvm.context()
schema.Define(T)

local S = T.MoonSource
local E = T.MoonEditor
local R = T.MoonRpc
local L = T.MoonLsp

local Dispatch = require("moonlift.lsp_dispatch").Define(T)

local uri = S.DocUri("file:///lsp_lua_dsl_test.lua")
local doc = S.DocumentSnapshot(uri, S.DocVersion(1), S.LangLua, [[
require("moonlift").use()

return module "LspSmoke" {
  fn .add { a [i32], b [i32] } [i32] {
    ret (a + b),
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

local bad_uri = S.DocUri("file:///lsp_lua_dsl_bad.lua")
local bad_doc = S.DocumentSnapshot(bad_uri, S.DocVersion(1), S.LangLua, [[
require("moonlift").use()

return module "Bad" {
  fn .bad {} [i32] {
    ret true,
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
