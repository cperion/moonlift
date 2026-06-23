local pvm = require("moonlift.pvm")
local llb = require("llb")
local AnalysisMod = require("moonlift.mlua_document_analysis")
local WorkspaceMod = require("moonlift.lsp_workspace")
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
local Diagnostics = require("moonlift.editor_diagnostic_facts")
local SubjectAt = require("moonlift.editor_subject_at")
local BindingFacts = require("moonlift.editor_binding_facts")
local AdaptMod = require("moonlift.lsp_payload_adapt")
local Capabilities = require("moonlift.lsp_capabilities")

local M = {}

local function id_set(ids)
    local out = {}
    for i = 1, #(ids or {}) do out[ids[i]] = true end
    return out
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local R = T.MoonRpc
    local L = T.MoonLsp
    local Analysis = AnalysisMod.Define(T)
    local Workspace = WorkspaceMod.Define(T)
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
    local Diag = Diagnostics.Define(T)
    local Subject = SubjectAt.Define(T)
    local Bindings = BindingFacts.Define(T)
    local Adapt = AdaptMod.Define(T)
    local Caps = Capabilities.Define(T)
    local analysis_cache = setmetatable({}, { __mode = "k" })
    local diagnostic_analysis_cache = setmetatable({}, { __mode = "k" })
    local diagnostics_disabled = os.getenv("MOONLIFT_LSP_DISABLE_DIAGNOSTICS") == "1"
    local memlog = os.getenv("MOONLIFT_LSP_MEMLOG") == "1"

    local analyze_document_phase = pvm.phase("moonlift_lsp_analyze_document", function(doc)
        return Analysis.analyze_document_light(doc)
    end)

    local diagnostic_document_phase = pvm.phase("moonlift_lsp_diagnostic_document", function(doc)
        return Analysis.analyze_document_full(doc)
    end)

    local function log_analysis(stage, mode, doc)
        if memlog then
            io.stderr:write(
                "moonlift-lsp analyze ", stage,
                " mode=", mode,
                " uri=", doc.uri.text,
                " version=", tostring(doc.version.value),
                " bytes=", tostring(#doc.text),
                " heap_kb=", tostring(math.floor(collectgarbage("count"))),
                "\n"
            )
        end
    end

    local function analyze_doc(doc)
        local cached = analysis_cache[doc]
        if cached then return cached end
        log_analysis("begin", "light", doc)
        local analysis = pvm.one(analyze_document_phase:triplet_uncached(doc))
        log_analysis("end", "light", doc)
        analysis_cache[doc] = analysis
        return analysis
    end

    local function analyze_doc_diagnostic(doc)
        local cached = diagnostic_analysis_cache[doc]
        if cached then return cached end
        log_analysis("begin", "diagnostic", doc)
        local analysis = pvm.one(diagnostic_document_phase:triplet_uncached(doc))
        log_analysis("end", "diagnostic", doc)
        diagnostic_analysis_cache[doc] = analysis
        return analysis
    end

    local function analyze_doc_safe(doc)
        local ok, analysis = pcall(analyze_doc, doc)
        if ok then return analysis end
        return nil, tostring(analysis)
    end

    local function analyze_doc_diagnostic_safe(doc)
        local ok, analysis = pcall(analyze_doc_diagnostic, doc)
        if ok then return analysis end
        return nil, tostring(analysis)
    end

    local document_events_process = llb.process. lsp_document (function(ctx, doc, opts)
        opts = opts or {}
        local mode = opts.mode or "light"
        ctx. load {
            language = "moonlift",
            uri = doc.uri.text,
            version = doc.version.value,
            bytes = #(doc.text or ""),
            mode = mode,
        }

        local analysis, err
        if mode == "diagnostic" then
            analysis, err = analyze_doc_diagnostic_safe(doc)
        else
            analysis, err = analyze_doc_safe(doc)
        end
        if not analysis then
            ctx. error {
                code = "E_LSP_ANALYSIS",
                message = tostring(err),
                uri = doc.uri.text,
                version = doc.version.value,
            }
            return nil
        end

        ctx. index {
            language = "moonlift",
            uri = doc.uri.text,
            version = doc.version.value,
            mode = mode,
            analysis = analysis,
        }

        if opts.symbols then
            local symbols = Sym.symbols(analysis)
            for i = 1, #symbols do
                ctx. symbol {
                    uri = doc.uri.text,
                    version = doc.version.value,
                    symbol = symbols[i],
                }
            end
        end

        if opts.hover then
            ctx. hover {
                uri = doc.uri.text,
                version = doc.version.value,
                query = opts.hover,
                hover = Hov.hover(opts.hover, analysis),
            }
        end

        if opts.diagnostics and not diagnostics_disabled then
            local diagnostics = Diag.diagnostics(analysis)
            for i = 1, #diagnostics do
                ctx:event("diagnostic", {
                    uri = doc.uri.text,
                    version = doc.version.value,
                    diagnostic = diagnostics[i],
                })
            end
        end

        return analysis
    end)

    local function collect_document_events(doc, opts)
        local out = {}
        local handle = document_events_process:start(doc, opts or {})
        for ev in handle:events() do out[#out + 1] = ev end
        return out, handle:result(), handle.diagnostics
    end

    local function document_symbols_from_process(doc)
        local events = collect_document_events(doc, { symbols = true })
        local symbols = {}
        for i = 1, #events do
            if events[i].kind == "symbol" then symbols[#symbols + 1] = events[i].symbol end
        end
        return symbols
    end

    local function hover_from_process(doc, query)
        local events = collect_document_events(doc, { hover = query })
        for i = 1, #events do
            if events[i].kind == "hover" then return events[i].hover end
        end
        return nil
    end

    local function diagnostics_from_process(doc)
        if diagnostics_disabled then return {} end
        local events = collect_document_events(doc, { mode = "diagnostic", diagnostics = true })
        local diagnostics = {}
        for i = 1, #events do
            if events[i].kind == "diagnostic" and events[i].diagnostic then diagnostics[#diagnostics + 1] = events[i].diagnostic end
        end
        return diagnostics
    end

    local function workspace_analyses(state)
        local out = {}
        for _, doc in ipairs(Workspace.open_documents(state)) do
            local analysis = analyze_doc_safe(doc)
            if analysis then out[#out + 1] = analysis end
        end
        return out
    end

    local function result(id, payload)
        return R.SendMessage(R.RpcResult(id, payload))
    end

    local function add_unique_range(out, seen, range)
        local key = range.uri.text .. ":" .. tostring(range.start_offset) .. ":" .. tostring(range.stop_offset)
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = range
        end
    end

    local function fallback_ids_for_pick(pick)
        local label = pick and pick.anchors and pick.anchors[1] and pick.anchors[1].label
        if not label or label == "" then return {} end
        return {
            "tree.func." .. label,
            "host.struct." .. label,
            "host.expose." .. label,
        }
    end

    local function subject_ids_at(query, analysis)
        local pick = Subject.subject_at(query, analysis)
        local label = pick and pick.anchors and pick.anchors[1] and pick.anchors[1].label or nil
        local cls = pvm.classof(pick.subject)
        if cls == E.SubjectKeyword or cls == E.SubjectDiagnostic then return {}, label end
        local id = cls ~= E.SubjectMissing and Bindings.subject_key(pick.subject) or nil
        if id then return { id }, label end
        return fallback_ids_for_pick(pick), label
    end

    local function label_anchor_matches(a, label, include_declaration)
        if a.label ~= label then return false end
        if a.kind == S.AnchorFunctionUse or a.kind == S.AnchorBindingUse or a.kind == S.AnchorFieldUse then return true end
        if include_declaration and (a.kind == S.AnchorFunctionName or a.kind == S.AnchorMethodName or a.kind == S.AnchorStructName or a.kind == S.AnchorExposeName) then return true end
        return false
    end

    local function workspace_ranges_for_subjects(state, ids, include_declaration, fallback_label)
        local wanted = id_set(ids)
        local ranges, seen = {}, {}
        for _, analysis in ipairs(workspace_analyses(state)) do
            local facts = Bindings.facts(analysis)
            for i = 1, #facts do
                if wanted[facts[i].id.text] and (include_declaration or facts[i].role ~= E.BindingDef) then
                    add_unique_range(ranges, seen, facts[i].anchor.range)
                end
            end
            if fallback_label and fallback_label ~= "" then
                for i = 1, #analysis.anchors.anchors do
                    local a = analysis.anchors.anchors[i]
                    if label_anchor_matches(a, fallback_label, include_declaration) then
                        add_unique_range(ranges, seen, a.range)
                    end
                end
            end
        end
        return ranges
    end

    local function workspace_definition_ranges(state, ids)
        local wanted = id_set(ids)
        local ranges, seen = {}, {}
        for _, analysis in ipairs(workspace_analyses(state)) do
            local facts = Bindings.facts(analysis)
            for i = 1, #facts do
                if wanted[facts[i].id.text] and facts[i].role == E.BindingDef then
                    add_unique_range(ranges, seen, facts[i].anchor.range)
                end
            end
        end
        return ranges
    end

    local function valid_identifier(name)
        return type(name) == "string" and name:match("^[_%a][_%w]*$") ~= nil
    end

    local function workspace_rename_edits(state, ids, fallback_label, new_name)
        if not valid_identifier(new_name) then return {} end
        local edits, seen = {}, {}
        local ranges = workspace_ranges_for_subjects(state, ids, true, fallback_label)
        for i = 1, #ranges do
            local r = ranges[i]
            local key = r.uri.text .. ":" .. tostring(r.start_offset) .. ":" .. tostring(r.stop_offset)
            if not seen[key] then
                seen[key] = true
                edits[#edits + 1] = E.RenameEdit(r, new_name)
            end
        end
        return edits
    end

    local function empty_report()
        return L.DiagnosticDocumentReport("full", {})
    end

    local function with_doc(state, uri, id, empty_payload, fn)
        local doc = Workspace.document_for_uri(state, uri)
        if not doc then return result(id, empty_payload) end
        local analysis = analyze_doc_safe(doc)
        if not analysis then return result(id, empty_payload) end
        return result(id, fn(doc, analysis))
    end

    local function with_doc_diagnostic(state, uri, id, empty_payload, fn)
        local doc = Workspace.document_for_uri(state, uri)
        if not doc then return result(id, empty_payload) end
        local analysis = analyze_doc_diagnostic_safe(doc)
        if not analysis then return result(id, empty_payload) end
        return result(id, fn(doc, analysis))
    end

    local function diagnostic_document_payload(doc)
        if diagnostics_disabled then return L.PayloadDiagnosticDocumentReport(empty_report()) end
        return L.PayloadDiagnosticDocumentReport(Adapt.diagnostic_document_report(diagnostics_from_process(doc)))
    end

    local client_exit_class = pvm.classof(E.ClientExit)
    local function is_bare(cls, event, variant, variant_class)
        return event == variant or (variant_class ~= false and cls == variant_class)
    end

    local dispatch_phase = pvm.phase("moonlift_lsp_dispatch", function(tr)
        local event = tr.event
        local cls = pvm.classof(event)
        local state = tr.after
        local out = {}

        if cls == E.ClientInitialize then
            out[#out + 1] = result(event.id, L.PayloadInitialize(Caps.initialize_result()))
        elseif cls == E.ClientShutdown then
            out[#out + 1] = result(event.id, L.PayloadNull)
        elseif is_bare(cls, event, E.ClientExit, client_exit_class) then
            out[#out + 1] = R.StopServer
        elseif cls == E.ClientDidOpen or cls == E.ClientDidChange or cls == E.ClientDidClose or cls == E.ClientDidSave then
            -- Pull diagnostics only.
        elseif cls == E.ClientHover then
            out[#out + 1] = with_doc(state, event.query.uri, event.id, L.PayloadHover(L.HoverNull), function(_, analysis)
                return L.PayloadHover(Adapt.hover(hover_from_process(_, event.query) or Hov.hover(event.query, analysis)))
            end)
        elseif cls == E.ClientCompletion then
            out[#out + 1] = with_doc(state, event.query.uri, event.id, L.PayloadCompletion(L.CompletionList(false, {})), function(_, analysis)
                return L.PayloadCompletion(Adapt.completion_list(Comp.complete(event.query, analysis)))
            end)
        elseif cls == E.ClientDocumentSymbol then
            out[#out + 1] = with_doc(state, event.uri, event.id, L.PayloadDocumentSymbols({}), function(_, analysis)
                return L.PayloadDocumentSymbols(Adapt.document_symbols(document_symbols_from_process(_) or Sym.symbols(analysis)))
            end)
        elseif cls == E.ClientDefinition then
            out[#out + 1] = with_doc(state, event.query.uri, event.id, L.PayloadLocations({}), function(_, analysis)
                local ids = subject_ids_at(event.query, analysis)
                local ranges = #ids > 0 and workspace_definition_ranges(state, ids) or {}
                if #ranges == 0 then
                    local def = Def.definition(event.query, analysis)
                    ranges = pvm.classof(def) == E.DefinitionHit and def.ranges or {}
                end
                return L.PayloadLocations(Adapt.locations(ranges))
            end)
        elseif cls == E.ClientReferences then
            out[#out + 1] = with_doc(state, event.query.position.uri, event.id, L.PayloadLocations({}), function(_, analysis)
                local ids, label = subject_ids_at(event.query.position, analysis)
                local ranges = #ids > 0 and workspace_ranges_for_subjects(state, ids, event.query.include_declaration, label) or {}
                if #ranges == 0 then
                    local refs = Refs.references(event.query, analysis)
                    ranges = pvm.classof(refs) == E.ReferenceHit and refs.ranges or {}
                end
                return L.PayloadLocations(Adapt.locations(ranges))
            end)
        elseif cls == E.ClientDocumentHighlight then
            out[#out + 1] = with_doc(state, event.query.uri, event.id, L.PayloadDocumentHighlights({}), function(_, analysis)
                return L.PayloadDocumentHighlights(Adapt.document_highlights(High.highlights(event.query, analysis)))
            end)
        elseif cls == E.ClientWorkspaceSymbol then
            local symbols = {}
            for _, analysis in ipairs(workspace_analyses(state)) do
                local doc_symbols = Sym.symbols(analysis)
                for j = 1, #doc_symbols do symbols[#symbols + 1] = doc_symbols[j] end
            end
            out[#out + 1] = result(event.id, L.PayloadWorkspaceSymbols(Adapt.workspace_symbols(symbols, event.query)))
        elseif cls == E.ClientDiagnostic then
            local doc = Workspace.document_for_uri(state, event.uri)
            out[#out + 1] = result(event.id, doc and diagnostic_document_payload(doc) or L.PayloadDiagnosticDocumentReport(empty_report()))
        elseif cls == E.ClientSignatureHelp then
            out[#out + 1] = with_doc(state, event.query.uri, event.id, L.PayloadNull, function(_, analysis)
                local help = Sig.help(event.query, analysis)
                if pvm.classof(help) == E.SignatureHelp then return L.PayloadSignatureHelp(Adapt.signature_help(help)) end
                return L.PayloadNull
            end)
        elseif cls == E.ClientSemanticTokensFull then
            out[#out + 1] = with_doc(state, event.uri, event.id, L.PayloadSemanticTokens(L.SemanticTokens({})), function(_, analysis)
                return L.PayloadSemanticTokens(Adapt.semantic_tokens(Tok.tokens(analysis)))
            end)
        elseif cls == E.ClientSemanticTokensRange then
            out[#out + 1] = with_doc(state, event.query.uri, event.id, L.PayloadSemanticTokens(L.SemanticTokens({})), function(_, analysis)
                return L.PayloadSemanticTokens(Adapt.semantic_tokens(Tok.range_tokens(event.query, analysis)))
            end)
        elseif cls == E.ClientPrepareRename then
            out[#out + 1] = with_doc(state, event.query.uri, event.id, L.PayloadNull, function(_, analysis)
                local prepared = Ren.prepare_rename(event.query, analysis)
                if pvm.classof(prepared) == E.PrepareRenameOk then return L.PayloadPrepareRename(Adapt.prepare_rename(prepared)) end
                return L.PayloadNull
            end)
        elseif cls == E.ClientRename then
            out[#out + 1] = with_doc(state, event.query.position.uri, event.id, L.PayloadWorkspaceEdit({}), function(_, analysis)
                local ids, label = subject_ids_at(event.query.position, analysis)
                local edits = #ids > 0 and workspace_rename_edits(state, ids, label, event.query.new_name) or {}
                if #edits == 0 then
                    local rr = Ren.rename(event.query, analysis)
                    edits = pvm.classof(rr) == E.RenameOk and rr.edits or {}
                end
                return L.PayloadWorkspaceEdit(Adapt.workspace_edit(edits))
            end)
        elseif cls == E.ClientCodeAction then
            out[#out + 1] = with_doc_diagnostic(state, event.query.range.uri, event.id, L.PayloadCodeActions({}), function(_, analysis)
                return L.PayloadCodeActions(Adapt.code_actions(Actions.actions(event.query, analysis)))
            end)
        elseif cls == E.ClientFoldingRange then
            out[#out + 1] = with_doc(state, event.uri, event.id, L.PayloadFoldingRanges({}), function(_, analysis)
                return L.PayloadFoldingRanges(Adapt.folding_ranges(Fold.ranges(analysis)))
            end)
        elseif cls == E.ClientSelectionRange then
            local uri = (#event.positions > 0) and event.positions[1].uri or S.DocUri("")
            out[#out + 1] = with_doc(state, uri, event.id, L.PayloadSelectionRanges({}), function(_, analysis)
                return L.PayloadSelectionRanges(Adapt.selection_ranges(Sel.selections(event.positions, analysis)))
            end)
        elseif cls == E.ClientInlayHint then
            out[#out + 1] = with_doc(state, event.query.uri, event.id, L.PayloadInlayHints({}), function(_, analysis)
                return L.PayloadInlayHints(Adapt.inlay_hints(InlayHints.hints(event.query, analysis)))
            end)
        elseif cls == E.ClientUnsupported then
            out[#out + 1] = R.SendMessage(R.RpcError(event.id, -32601, "unsupported method: " .. event.method))
        end

        return out
    end, { node_cache = "none", args_cache = "none" })

    local function commands(transition)
        return pvm.one(dispatch_phase(transition))
    end

    return {
        analyze_document_phase = analyze_document_phase,
        diagnostic_document_phase = diagnostic_document_phase,
        document_events_process = document_events_process,
        dispatch_phase = dispatch_phase,
        commands = commands,
    }
end

return M
