local pvm = require("moonlift.pvm")
local JsonDecode = require("moonlift.rpc_json_decode")
local JsonEncode = require("moonlift.rpc_json_encode")

local M = {}

function M.Define(T)
    local E = T.MoonEditor
    local R = T.MoonRpc
    local L = T.MoonLsp
    local Decode = JsonDecode.Define(T)
    local Encode = JsonEncode.Define(T)

    local function id_lua(id)
        local cls = pvm.classof(id)
        if id == E.RpcIdNone then return JsonEncode.JSON_NULL end
        if cls == E.RpcIdNumber then return id.value end
        if cls == E.RpcIdString then return id.value end
        return JsonEncode.JSON_NULL
    end

    local function pos_lua(pos)
        return { line = pos.line, character = pos.character }
    end

    local function range_lua(range)
        return { start = pos_lua(range.start), ["end"] = pos_lua(range.stop) }
    end

    local function markup_kind(kind)
        if kind == E.MarkupMarkdown then return "markdown" end
        return "plaintext"
    end

    local function diag_lua(d)
        return { range = range_lua(d.range), severity = d.severity, code = d.code, source = "moonlift", message = d.message }
    end

    local function hover_lua(h)
        if h == L.HoverNull then return JsonEncode.JSON_NULL end
        return { contents = { kind = markup_kind(h.kind), value = h.value }, range = range_lua(h.range) }
    end

    local function completion_item_lua(item)
        return { label = item.label, kind = item.kind, detail = item.detail, documentation = item.documentation, insertText = item.insert_text }
    end

    local function completion_list_lua(list)
        local items = {}
        for i = 1, #list.items do items[i] = completion_item_lua(list.items[i]) end
        return { isIncomplete = list.incomplete, items = items }
    end

    local function symbol_lua(sym)
        local children = {}
        for i = 1, #sym.children do children[i] = symbol_lua(sym.children[i]) end
        return { name = sym.name, detail = sym.detail, kind = sym.kind, range = range_lua(sym.range), selectionRange = range_lua(sym.selection_range), children = children }
    end

    local function location_lua(loc)
        return { uri = loc.uri.text, range = range_lua(loc.range) }
    end

    local function workspace_symbol_lua(sym)
        return { name = sym.name, detail = sym.detail, kind = sym.kind, location = location_lua(sym.location), containerName = sym.container_name }
    end

    local function signature_help_lua(help)
        local signatures = {}
        for i = 1, #help.signatures do
            local sig = help.signatures[i]
            local params = {}
            for j = 1, #sig.params do
                params[j] = { label = sig.params[j].label, documentation = sig.params[j].documentation }
            end
            signatures[i] = { label = sig.label, documentation = sig.documentation, parameters = params }
        end
        return { signatures = signatures, activeSignature = help.active_signature, activeParameter = help.active_parameter }
    end

    local function text_edit_lua(edit)
        return { range = range_lua(edit.range), newText = edit.new_text }
    end

    local function document_highlight_lua(highlight)
        return { range = range_lua(highlight.range), kind = highlight.kind }
    end

    local function prepare_rename_lua(prepared)
        return { range = range_lua(prepared.range), placeholder = prepared.placeholder }
    end

    local function payload_lua(payload)
        local cls = pvm.classof(payload)
        if payload == L.PayloadNull then return JsonEncode.JSON_NULL end
        if cls == L.PayloadInitialize then
            local caps = JsonDecode.decode_lua(payload.result.capabilities_json)
            return { capabilities = caps, serverInfo = { name = payload.result.server_name } }
        elseif cls == L.PayloadDiagnostics then
            local ds = {}
            for i = 1, #payload.report.diagnostics do ds[i] = diag_lua(payload.report.diagnostics[i]) end
            return { uri = payload.report.uri.text, version = payload.report.version.value, diagnostics = ds }
        elseif cls == L.PayloadDiagnosticDocumentReport then
            local items = {}
            for i = 1, #payload.report.items do items[i] = diag_lua(payload.report.items[i]) end
            return { kind = payload.report.kind, items = items }
        elseif cls == L.PayloadHover then
            return hover_lua(payload.hover)
        elseif cls == L.PayloadCompletion then
            return completion_list_lua(payload.completion)
        elseif cls == L.PayloadDocumentSymbols then
            local out = {}
            for i = 1, #payload.symbols do out[i] = symbol_lua(payload.symbols[i]) end
            return out
        elseif cls == L.PayloadWorkspaceSymbols then
            local out = {}
            for i = 1, #payload.symbols do out[i] = workspace_symbol_lua(payload.symbols[i]) end
            return out
        elseif cls == L.PayloadSignatureHelp then
            return signature_help_lua(payload.help)
        elseif cls == L.PayloadLocations then
            local out = {}
            for i = 1, #payload.locations do out[i] = location_lua(payload.locations[i]) end
            return out
        elseif cls == L.PayloadDocumentHighlights then
            local out = {}
            for i = 1, #payload.highlights do out[i] = document_highlight_lua(payload.highlights[i]) end
            return out
        elseif cls == L.PayloadPrepareRename then
            return prepare_rename_lua(payload.result)
        elseif cls == L.PayloadSemanticTokens then
            local data = {}
            for i = 1, #payload.tokens.data do data[i] = payload.tokens.data[i] end
            return { data = data }
        elseif cls == L.PayloadWorkspaceEdit then
            local changes = {}
            for i = 1, #payload.edits do
                local we = payload.edits[i]
                local edits = {}
                for j = 1, #we.edits do edits[j] = text_edit_lua(we.edits[j]) end
                changes[we.uri.text] = edits
            end
            return { changes = changes }
        elseif cls == L.PayloadCodeActions then
            local out = {}
            for i = 1, #payload.actions do
                local a = payload.actions[i]
                local diagnostics = {}
                for j = 1, #a.diagnostics do diagnostics[j] = diag_lua(a.diagnostics[j]) end
                local changes = {}
                for j = 1, #a.edits do
                    local we = a.edits[j]
                    local edits = {}
                    for k = 1, #we.edits do edits[k] = text_edit_lua(we.edits[k]) end
                    changes[we.uri.text] = edits
                end
                out[i] = { title = a.title, kind = a.kind, diagnostics = diagnostics, edit = { changes = changes } }
            end
            return out
        elseif cls == L.PayloadFoldingRanges then
            local out = {}
            for i = 1, #payload.ranges do
                local r = payload.ranges[i]
                out[i] = { startLine = r.start_line, startCharacter = r.start_character, endLine = r.end_line, endCharacter = r.end_character, kind = r.kind }
            end
            return out
        elseif cls == L.PayloadSelectionRanges then
            local function selection_lua(sel)
                local node = { range = range_lua(sel.range) }
                if #sel.parents > 0 then
                    node.parent = selection_lua(sel.parents[1])
                end
                return node
            end
            local out = {}
            for i = 1, #payload.ranges do out[i] = selection_lua(payload.ranges[i]) end
            return out
        elseif cls == L.PayloadInlayHints then
            local out = {}
            for i = 1, #payload.hints do out[i] = { position = pos_lua(payload.hints[i].position), label = payload.hints[i].label, kind = payload.hints[i].kind } end
            return out
        elseif cls == L.PayloadError then
            return { code = payload.code, message = payload.message }
        end
        return JsonEncode.JSON_NULL
    end

    local function outgoing_lua(outgoing)
        local cls = pvm.classof(outgoing)
        if cls == R.RpcResult then
            return { jsonrpc = "2.0", id = id_lua(outgoing.id), result = payload_lua(outgoing.payload) }
        elseif cls == R.RpcError then
            return { jsonrpc = "2.0", id = id_lua(outgoing.id), error = { code = outgoing.code, message = outgoing.message } }
        elseif cls == R.RpcOutgoingNotification then
            return { jsonrpc = "2.0", method = outgoing.method, params = payload_lua(outgoing.payload) }
        end
        return nil
    end

    local function encode_outgoing(outgoing)
        return Encode.encode_lua(outgoing_lua(outgoing))
    end

    return {
        payload_lua = payload_lua,
        outgoing_lua = outgoing_lua,
        encode_outgoing = encode_outgoing,
    }
end

return M
