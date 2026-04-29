local pvm = require("moonlift.pvm")
local JsonDecode = require("moonlift.rpc_json_decode")
local PositionIndex = require("moonlift.source_position_index")

local M = {}

local function uri_eq(a, b)
    return a == b or (a and b and a.text == b.text)
end

local function find_doc(state, uri)
    for i = 1, #state.open_docs do
        if uri_eq(state.open_docs[i].uri, uri) then return state.open_docs[i] end
    end
    return nil
end

local function language(S, lang)
    if lang == "mlua" then return S.LangMlua end
    if lang == "moonlift" then return S.LangMoonlift end
    if lang == "lua" then return S.LangLua end
    return S.LangUnknown(tostring(lang or ""))
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local R = T.MoonRpc
    local Decode = JsonDecode.Define(T)
    local P = PositionIndex.Define(T)

    local function text_document_uri(params)
        return params and params.textDocument and params.textDocument.uri or params and params.uri or ""
    end

    local function version_from(params, doc)
        local v = params and params.textDocument and params.textDocument.version
        if v == nil and params then v = params.version end
        if v == nil and doc then v = doc.version.value end
        return S.DocVersion(tonumber(v) or 0)
    end

    local function source_pos(doc, line, character)
        if doc then
            local index = P.build_index(doc)
            local hit = P.byte_offset_at_utf16_col(index, tonumber(line) or 0, tonumber(character) or 0)
            if pvm.classof(hit) == S.SourceOffsetHit then
                local pos = P.offset_to_pos(index, hit.offset)
                if pvm.classof(pos) == S.SourcePositionHit then return pos.pos end
            end
        end
        return S.SourcePos(tonumber(line) or 0, tonumber(character) or 0, tonumber(character) or 0)
    end

    local function source_range(doc, uri, range)
        local index = P.build_index(doc)
        local s = range.start or range["start"] or {}
        local e = range["end"] or range.stop or {}
        local sh = P.byte_offset_at_utf16_col(index, tonumber(s.line) or 0, tonumber(s.character) or 0)
        local eh = P.byte_offset_at_utf16_col(index, tonumber(e.line) or 0, tonumber(e.character) or 0)
        if pvm.classof(sh) ~= S.SourceOffsetHit or pvm.classof(eh) ~= S.SourceOffsetHit then
            return assert(P.range_from_offsets(index, 0, 0))
        end
        return assert(P.range_from_offsets(index, sh.offset, eh.offset))
    end

    local function position_query(params, state)
        local uri = S.DocUri(text_document_uri(params))
        local doc = find_doc(state, uri)
        local pos = params and params.position or {}
        return E.PositionQuery(uri, version_from(params, doc), source_pos(doc, pos.line, pos.character))
    end

    local function range_query(params, state)
        local uri = S.DocUri(text_document_uri(params))
        local doc = find_doc(state, uri)
        local r = params and params.range
        local range
        if doc and r then range = source_range(doc, uri, r)
        else
            local fallback = doc or S.DocumentSnapshot(uri, S.DocVersion(0), S.LangMlua, "")
            range = assert(P.range_from_offsets(P.build_index(fallback), 0, 0))
        end
        return E.RangeQuery(uri, version_from(params, doc), range)
    end

    local function did_change(params, state)
        local uri = S.DocUri(text_document_uri(params))
        local doc = find_doc(state, uri)
        local version = version_from(params, doc)
        local changes = {}
        local content_changes = params.contentChanges or {}
        for i = 1, #content_changes do
            local ch = content_changes[i]
            if ch.range and doc then
                changes[#changes + 1] = S.ReplaceRange(source_range(doc, uri, ch.range), ch.text or "")
            else
                changes = { S.ReplaceAll(ch.text or "") }
            end
        end
        return E.ClientDidChange(S.DocumentEdit(uri, version, changes))
    end

    local function decode(incoming, state)
        local cls = pvm.classof(incoming)
        if cls == R.RpcInvalid then return E.ClientIgnoredNotification("invalid:" .. incoming.reason) end
        local method = incoming.method
        local id = incoming.id or E.RpcIdNone
        local params = Decode.value_to_lua(incoming.params)
        if params == JsonDecode.JSON_NULL then params = {} end

        if method == "initialize" then
            local roots = {}
            if params.rootUri then roots[#roots + 1] = E.WorkspaceRoot(S.DocUri(params.rootUri)) end
            if type(params.workspaceFolders) == "table" then
                for i = 1, #params.workspaceFolders do
                    if params.workspaceFolders[i].uri then roots[#roots + 1] = E.WorkspaceRoot(S.DocUri(params.workspaceFolders[i].uri)) end
                end
            end
            return E.ClientInitialize(id, roots, {})
        elseif method == "initialized" then return E.ClientInitialized
        elseif method == "shutdown" then return E.ClientShutdown(id)
        elseif method == "exit" then return E.ClientExit
        elseif method == "textDocument/didOpen" then
            local td = params.textDocument or {}
            return E.ClientDidOpen(S.DocumentSnapshot(S.DocUri(td.uri or ""), S.DocVersion(tonumber(td.version) or 0), language(S, td.languageId), td.text or ""))
        elseif method == "textDocument/didChange" then return did_change(params, state)
        elseif method == "textDocument/didClose" then return E.ClientDidClose(S.DocUri(text_document_uri(params)))
        elseif method == "textDocument/didSave" then return E.ClientDidSave(S.DocUri(text_document_uri(params)))
        elseif method == "textDocument/hover" then return E.ClientHover(id, position_query(params, state))
        elseif method == "textDocument/definition" then return E.ClientDefinition(id, position_query(params, state))
        elseif method == "textDocument/references" then return E.ClientReferences(id, E.ReferenceQuery(position_query(params, state), params.context and params.context.includeDeclaration == true))
        elseif method == "textDocument/documentHighlight" then return E.ClientDocumentHighlight(id, position_query(params, state))
        elseif method == "textDocument/documentSymbol" then return E.ClientDocumentSymbol(id, S.DocUri(text_document_uri(params)))
        elseif method == "workspace/symbol" then return E.ClientWorkspaceSymbol(id, tostring(params.query or ""))
        elseif method == "textDocument/diagnostic" then return E.ClientDiagnostic(id, S.DocUri(text_document_uri(params)))
        elseif method == "textDocument/completion" then return E.ClientCompletion(id, position_query(params, state))
        elseif method == "textDocument/signatureHelp" then return E.ClientSignatureHelp(id, position_query(params, state))
        elseif method == "textDocument/semanticTokens/full" then return E.ClientSemanticTokensFull(id, S.DocUri(text_document_uri(params)))
        elseif method == "textDocument/semanticTokens/range" then return E.ClientSemanticTokensRange(id, range_query(params, state))
        elseif method == "textDocument/prepareRename" then return E.ClientPrepareRename(id, position_query(params, state))
        elseif method == "textDocument/rename" then return E.ClientRename(id, E.RenameQuery(position_query(params, state), tostring(params.newName or "")))
        elseif method == "textDocument/codeAction" then return E.ClientCodeAction(id, E.CodeActionQuery(range_query(params, state), {}))
        elseif method == "textDocument/foldingRange" then return E.ClientFoldingRange(id, S.DocUri(text_document_uri(params)))
        elseif method == "textDocument/selectionRange" then
            local qs = {}
            local positions = params.positions or {}
            for i = 1, #positions do
                local p2 = { textDocument = params.textDocument, position = positions[i] }
                qs[i] = position_query(p2, state)
            end
            return E.ClientSelectionRange(id, qs)
        elseif method == "textDocument/inlayHint" then return E.ClientInlayHint(id, range_query(params, state))
        end
        if cls == R.RpcRequest then return E.ClientUnsupported(id, method) end
        return E.ClientIgnoredNotification(method)
    end

    return { decode = decode }
end

return M
