package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local JsonDecodeMod = require("moonlift.rpc_json_decode")
local JsonEncodeMod = require("moonlift.rpc_json_encode")
local LspDecodeMod = require("moonlift.rpc_lsp_decode")
local LspEncodeMod = require("moonlift.rpc_lsp_encode")
local WorkspaceApplyMod = require("moonlift.editor_workspace_apply")
local WorkspaceIndexMod = require("moonlift.lsp_workspace")
local DispatchMod = require("moonlift.lsp_dispatch")

local T = pvm.context()
A.Define(T)
local E = T.MoonEditor
local R = T.MoonRpc
local JsonDecode = JsonDecodeMod.Define(T)
local JsonEncode = JsonEncodeMod.Define(T)
local LspDecode = LspDecodeMod.Define(T)
local LspEncode = LspEncodeMod.Define(T)
local WorkspaceApply = WorkspaceApplyMod.Define(T)
local WorkspaceIndex = WorkspaceIndexMod.Define(T)
local Dispatch = DispatchMod.Define(T)

local path = "experiments/mwui/mwui_types.mlua"
local f = assert(io.open(path, "rb"))
local base = f:read("*a")
f:close()

local uri = "file://" .. path
local state = WorkspaceApply.initial_state()

local function heap_kb()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

local function step(message)
    local incoming = JsonDecode.decode_message(JsonEncode.encode_lua(message))
    local event = LspDecode.decode(incoming, state)
    local transition = WorkspaceApply.apply_event(state, event)
    state = WorkspaceIndex.sync_after_event(transition.after, event)
    local commands = Dispatch.commands(E.Transition(transition.before, event, state))
    for i = 1, #commands do
        local command = commands[i]
        if pvm.classof(command) == R.SendMessage then
            LspEncode.encode_outgoing(command.outgoing)
        end
    end
end

step({ jsonrpc = "2.0", id = 1, method = "initialize", params = { rootUri = "file:///home/cedric/dev/moonlift" } })
step({ jsonrpc = "2.0", method = "initialized", params = {} })
step({
    jsonrpc = "2.0",
    method = "textDocument/didOpen",
    params = { textDocument = { uri = uri, languageId = "mlua", version = 1, text = base } },
})

local edit_only_start = heap_kb()
for i = 1, 180 do
    local text = base .. "\n-- edit-only " .. tostring(i) .. " " .. string.rep("x", i % 31)
    step({
        jsonrpc = "2.0",
        method = "textDocument/didChange",
        params = { textDocument = { uri = uri, version = i + 1 }, contentChanges = { { text = text } } },
    })
end

local edit_only_finish = heap_kb()
assert(edit_only_finish - edit_only_start < 5000, ("didChange retained %.0f KB"):format(edit_only_finish - edit_only_start))

local start = heap_kb()
for i = 181, 280 do
    local text = base .. "\n-- lsp edit " .. tostring(i) .. " " .. string.rep("x", i % 31)
    step({
        jsonrpc = "2.0",
        method = "textDocument/didChange",
        params = { textDocument = { uri = uri, version = i + 1 }, contentChanges = { { text = text } } },
    })
    if i % 5 == 0 then
        step({ jsonrpc = "2.0", id = 1000 + i, method = "textDocument/diagnostic", params = { textDocument = { uri = uri } } })
        step({ jsonrpc = "2.0", id = 2000 + i, method = "textDocument/semanticTokens/full", params = { textDocument = { uri = uri } } })
        step({
            jsonrpc = "2.0",
            id = 3000 + i,
            method = "textDocument/documentHighlight",
            params = { textDocument = { uri = uri }, position = { line = 0, character = 1 } },
        })
    end
end

local finish = heap_kb()
assert(finish - start < 75000, ("LSP edit session retained %.0f KB"):format(finish - start))

local idle_start = heap_kb()
for i = 1, 300 do
    local id = i * 10
    step({ jsonrpc = "2.0", id = id + 1, method = "textDocument/diagnostic", params = { textDocument = { uri = uri } } })
    step({ jsonrpc = "2.0", id = id + 2, method = "textDocument/semanticTokens/full", params = { textDocument = { uri = uri } } })
    step({ jsonrpc = "2.0", id = id + 3, method = "textDocument/foldingRange", params = { textDocument = { uri = uri } } })
    step({
        jsonrpc = "2.0",
        id = id + 4,
        method = "textDocument/inlayHint",
        params = {
            textDocument = { uri = uri },
            range = { start = { line = 0, character = 0 }, ["end"] = { line = 20, character = 0 } },
        },
    })
end

local idle_finish = heap_kb()
assert(idle_finish - idle_start < 40000, ("idle LSP requests retained %.0f KB"):format(idle_finish - idle_start))

print("moonlift lsp edit memory regression ok")
