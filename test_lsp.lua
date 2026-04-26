package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local Lsp = require("moonlift.lsp_server")
local server = Lsp.new()

local init = server:handle({ jsonrpc = "2.0", id = 1, method = "initialize", params = {} })
assert(init.result.capabilities.hoverProvider == true)
assert(init.result.capabilities.documentSymbolProvider == true)

local uri = "file:///tmp/demo.mlua"
local src = [[
struct User {
    id: i32
    active: bool32
}

expose view(User) as Users {
    lua readonly checked
    c
}

func User:is_active(self: ptr(User)) -> bool {
    return true
}
]]

local pub = server:handle({ jsonrpc = "2.0", method = "textDocument/didOpen", params = { textDocument = { uri = uri, version = 1, text = src } } })
assert(pub.method == "textDocument/publishDiagnostics")
assert(#pub.params.diagnostics == 0)

local syms = server:handle({ jsonrpc = "2.0", id = 2, method = "textDocument/documentSymbol", params = { textDocument = { uri = uri } } })
assert(#syms.result >= 3)
assert(syms.result[1].name == "User")
assert(#syms.result[1].children == 2)

local hover = server:handle({ jsonrpc = "2.0", id = 3, method = "textDocument/hover", params = { textDocument = { uri = uri }, position = { line = 2, character = 8 } } })
assert(hover.result and hover.result.contents.value:match("Signed 32"))

local comp = server:handle({ jsonrpc = "2.0", id = 4, method = "textDocument/completion", params = { textDocument = { uri = uri }, position = { line = 1, character = 0 } } })
assert(#comp.result.items > 0)

local bad = [[struct Bad {
    ok: i32
    no: bool
}
]]
local pub2 = server:handle({ jsonrpc = "2.0", method = "textDocument/didChange", params = { textDocument = { uri = uri, version = 2 }, contentChanges = { { text = bad } } } })
assert(#pub2.params.diagnostics >= 1)

local close = server:handle({ jsonrpc = "2.0", method = "textDocument/didClose", params = { textDocument = { uri = uri } } })
assert(#close.params.diagnostics == 0)

print("moonlift lsp ok")
