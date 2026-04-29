local pvm = require("moonlift.pvm")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local Diagnostics = require("moonlift.editor_diagnostic_facts")
local Symbols = require("moonlift.editor_symbol_facts")
local Hover = require("moonlift.editor_hover")
local Completion = require("moonlift.editor_completion_items")
local SignatureHelp = require("moonlift.editor_signature_help")
local Definition = require("moonlift.editor_definition")
local References = require("moonlift.editor_references")
local Rename = require("moonlift.editor_rename")
local Highlights = require("moonlift.editor_document_highlight")
local SemanticTokens = require("moonlift.editor_semantic_tokens")
local Folding = require("moonlift.editor_folding_ranges")
local Selection = require("moonlift.editor_selection_ranges")
local Inlay = require("moonlift.editor_inlay_hints")
local CodeActions = require("moonlift.editor_code_actions")
local AdaptMod = require("moonlift.lsp_payload_adapt")
local Capabilities = require("moonlift.lsp_capabilities")

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

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local R = T.MoonRpc
    local L = T.MoonLsp
    local Analysis = AnalysisMod.Define(T)
    local Diag = Diagnostics.Define(T)
    local Sym = Symbols.Define(T)
    local Hov = Hover.Define(T)
    local Comp = Completion.Define(T)
    local Sig = SignatureHelp.Define(T)
    local Def = Definition.Define(T)
    local Refs = References.Define(T)
    local Ren = Rename.Define(T)
    local High = Highlights.Define(T)
    local Tok = SemanticTokens.Define(T)
    local Fold = Folding.Define(T)
    local Sel = Selection.Define(T)
    local InlayHints = Inlay.Define(T)
    local Actions = CodeActions.Define(T)
    local Adapt = AdaptMod.Define(T)
    local Caps = Capabilities.Define(T)

    local function analyze_doc(doc)
        return Analysis.analyze_document(doc)
    end

    local function diagnostics_payload(doc)
        local analysis = analyze_doc(doc)
        return L.PayloadDiagnostics(Adapt.diagnostic_report(doc.uri, doc.version, Diag.diagnostics(analysis)))
    end

    local function diagnostic_document_payload(doc)
        local analysis = analyze_doc(doc)
        return L.PayloadDiagnosticDocumentReport(Adapt.diagnostic_document_report(Diag.diagnostics(analysis)))
    end

    local function result(id, payload)
        return R.SendMessage(R.RpcResult(id, payload))
    end

    local function notification(method, payload)
        return R.SendMessage(R.RpcOutgoingNotification(method, payload))
    end

    local client_initialized_class = pvm.classof(E.ClientInitialized)
    local client_exit_class = pvm.classof(E.ClientExit)
    local function is_bare(cls, event, variant, variant_class)
        return event == variant or (variant_class ~= false and cls == variant_class)
    end

    local out_commands_phase = pvm.phase("moon2_rpc_out_commands", {
        [E.Transition] = function(tr)
            local event = tr.event
            local cls = pvm.classof(event)
            local out = {}
            if cls == E.ClientInitialize then
                out[#out + 1] = result(event.id, L.PayloadInitialize(Caps.initialize_result()))
            elseif cls == E.ClientShutdown then
                out[#out + 1] = result(event.id, L.PayloadNull)
            elseif is_bare(cls, event, E.ClientExit, client_exit_class) then
                out[#out + 1] = R.StopServer
            elseif cls == E.ClientDidOpen then
                out[#out + 1] = notification("textDocument/publishDiagnostics", diagnostics_payload(event.document))
            elseif cls == E.ClientDidChange then
                local doc = find_doc(tr.after, event.edit.uri)
                if doc then out[#out + 1] = notification("textDocument/publishDiagnostics", diagnostics_payload(doc)) end
            elseif cls == E.ClientDidClose then
                out[#out + 1] = notification("textDocument/publishDiagnostics", L.PayloadDiagnostics(L.DiagnosticReport(event.uri, S.DocVersion(0), {})))
            elseif cls == E.ClientHover then
                local doc = find_doc(tr.after, event.query.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadHover(Adapt.hover(Hov.hover(event.query, analysis))))
                else
                    out[#out + 1] = result(event.id, L.PayloadHover(L.HoverNull))
                end
            elseif cls == E.ClientCompletion then
                local doc = find_doc(tr.after, event.query.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadCompletion(Adapt.completion_list(Comp.complete(event.query, analysis))))
                else
                    out[#out + 1] = result(event.id, L.PayloadCompletion(L.CompletionList(false, {})))
                end
            elseif cls == E.ClientDocumentSymbol then
                local doc = find_doc(tr.after, event.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadDocumentSymbols(Adapt.document_symbols(Sym.symbols(analysis))))
                else
                    out[#out + 1] = result(event.id, L.PayloadDocumentSymbols({}))
                end
            elseif cls == E.ClientDefinition then
                local doc = find_doc(tr.after, event.query.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    local def = Def.definition(event.query, analysis)
                    out[#out + 1] = result(event.id, L.PayloadLocations(pvm.classof(def) == E.DefinitionHit and Adapt.locations(def.ranges) or {}))
                else out[#out + 1] = result(event.id, L.PayloadLocations({})) end
            elseif cls == E.ClientReferences then
                local doc = find_doc(tr.after, event.query.position.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    local refs = Refs.references(event.query, analysis)
                    out[#out + 1] = result(event.id, L.PayloadLocations(pvm.classof(refs) == E.ReferenceHit and Adapt.locations(refs.ranges) or {}))
                else out[#out + 1] = result(event.id, L.PayloadLocations({})) end
            elseif cls == E.ClientDocumentHighlight then
                local doc = find_doc(tr.after, event.query.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadDocumentHighlights(Adapt.document_highlights(High.highlights(event.query, analysis))))
                else out[#out + 1] = result(event.id, L.PayloadDocumentHighlights({})) end
            elseif cls == E.ClientWorkspaceSymbol then
                local symbols = {}
                for i = 1, #tr.after.open_docs do
                    local analysis = analyze_doc(tr.after.open_docs[i])
                    local doc_symbols = Sym.symbols(analysis)
                    for j = 1, #doc_symbols do symbols[#symbols + 1] = doc_symbols[j] end
                end
                out[#out + 1] = result(event.id, L.PayloadWorkspaceSymbols(Adapt.workspace_symbols(symbols, event.query)))
            elseif cls == E.ClientDiagnostic then
                local doc = find_doc(tr.after, event.uri)
                if doc then out[#out + 1] = result(event.id, diagnostic_document_payload(doc))
                else out[#out + 1] = result(event.id, L.PayloadDiagnosticDocumentReport(L.DiagnosticDocumentReport("full", {}))) end
            elseif cls == E.ClientSignatureHelp then
                local doc = find_doc(tr.after, event.query.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    local help = Sig.help(event.query, analysis)
                    if pvm.classof(help) == E.SignatureHelp then
                        out[#out + 1] = result(event.id, L.PayloadSignatureHelp(Adapt.signature_help(help)))
                    else out[#out + 1] = result(event.id, L.PayloadNull) end
                else out[#out + 1] = result(event.id, L.PayloadNull) end
            elseif cls == E.ClientSemanticTokensFull then
                local doc = find_doc(tr.after, event.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadSemanticTokens(Adapt.semantic_tokens(Tok.tokens(analysis))))
                else out[#out + 1] = result(event.id, L.PayloadSemanticTokens(L.SemanticTokens({}))) end
            elseif cls == E.ClientSemanticTokensRange then
                local doc = find_doc(tr.after, event.query.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadSemanticTokens(Adapt.semantic_tokens(Tok.range_tokens(event.query, analysis))))
                else out[#out + 1] = result(event.id, L.PayloadSemanticTokens(L.SemanticTokens({}))) end
            elseif cls == E.ClientPrepareRename then
                local doc = find_doc(tr.after, event.query.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    local prepared = Ren.prepare_rename(event.query, analysis)
                    if pvm.classof(prepared) == E.PrepareRenameOk then
                        out[#out + 1] = result(event.id, L.PayloadPrepareRename(Adapt.prepare_rename(prepared)))
                    else out[#out + 1] = result(event.id, L.PayloadNull) end
                else out[#out + 1] = result(event.id, L.PayloadNull) end
            elseif cls == E.ClientRename then
                local doc = find_doc(tr.after, event.query.position.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    local rr = Ren.rename(event.query, analysis)
                    out[#out + 1] = result(event.id, L.PayloadWorkspaceEdit(pvm.classof(rr) == E.RenameOk and Adapt.workspace_edit(rr.edits) or {}))
                else out[#out + 1] = result(event.id, L.PayloadWorkspaceEdit({})) end
            elseif cls == E.ClientCodeAction then
                local doc = find_doc(tr.after, event.query.range.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadCodeActions(Adapt.code_actions(Actions.actions(event.query, analysis))))
                else out[#out + 1] = result(event.id, L.PayloadCodeActions({})) end
            elseif cls == E.ClientFoldingRange then
                local doc = find_doc(tr.after, event.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadFoldingRanges(Adapt.folding_ranges(Fold.ranges(analysis))))
                else out[#out + 1] = result(event.id, L.PayloadFoldingRanges({})) end
            elseif cls == E.ClientSelectionRange then
                local doc = (#event.positions > 0) and find_doc(tr.after, event.positions[1].uri) or nil
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadSelectionRanges(Adapt.selection_ranges(Sel.selections(event.positions, analysis))))
                else out[#out + 1] = result(event.id, L.PayloadSelectionRanges({})) end
            elseif cls == E.ClientInlayHint then
                local doc = find_doc(tr.after, event.query.uri)
                if doc then
                    local analysis = analyze_doc(doc)
                    out[#out + 1] = result(event.id, L.PayloadInlayHints(Adapt.inlay_hints(InlayHints.hints(event.query, analysis))))
                else out[#out + 1] = result(event.id, L.PayloadInlayHints({})) end
            elseif cls == E.ClientUnsupported then
                out[#out + 1] = R.SendMessage(R.RpcError(event.id, -32601, "unsupported method: " .. event.method))
            end
            return pvm.seq(out)
        end,
    })

    local function commands(transition)
        return pvm.drain(out_commands_phase(transition))
    end

    return {
        out_commands_phase = out_commands_phase,
        commands = commands,
    }
end

return M
