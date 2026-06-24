local schema = require("moonlift.schema_runtime")
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

local function id_set(ids)
    local out = {}
    for i = 1, #(ids or {}) do out[ids[i]] = true end
    return out
end

local function bind_context(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local R = T.MoonRpc
    local L = T.MoonLsp
    local Analysis = AnalysisMod(T)
    local Workspace = WorkspaceMod(T)
    local Sym = Symbols(T)
    local Hov = Hover(T)
    local Comp = Completion(T)
    local Sig = SignatureHelp(T)
    local Def = Definition(T)
    local Refs = References(T)
    local Ren = Rename(T)
    local High = Highlights(T)
    local Tok = SemanticTokens(T)
    local Fold = Folding(T)
    local Sel = Selection(T)
    local InlayHints = Inlay(T)
    local Actions = CodeActions(T)
    local Diag = Diagnostics(T)
    local Subject = SubjectAt(T)
    local Bindings = BindingFacts(T)
    local Adapt = AdaptMod(T)
    local Caps = Capabilities(T)
    local analysis_cache = setmetatable({}, { __mode = "k" })
    local diagnostic_analysis_cache = setmetatable({}, { __mode = "k" })
    local diagnostics_disabled = os.getenv("MOONLIFT_LSP_DISABLE_DIAGNOSTICS") == "1"
    local memlog = os.getenv("MOONLIFT_LSP_MEMLOG") == "1"

    local function analyze_document_phase(doc)
        return Analysis.analyze_document_light(doc)
    end

    local function diagnostic_document_phase(doc)
        return Analysis.analyze_document_full(doc)
    end

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
        local analysis = analyze_document_phase(doc)
        log_analysis("end", "light", doc)
        analysis_cache[doc] = analysis
        return analysis
    end

    local function analyze_doc_diagnostic(doc)
        local cached = diagnostic_analysis_cache[doc]
        if cached then return cached end
        log_analysis("begin", "diagnostic", doc)
        local analysis = diagnostic_document_phase(doc)
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

    local function lsp_document_process_body(ctx, doc, opts)
        opts = opts or {}
        local function gen(param, state)
            local doc0, opts0, mode = param.doc, param.opts, param.mode
            local uri, version = doc0.uri.text, doc0.version.value
            if state.phase == "load" then
                state.phase = "analyze"
                return state, param.ctx:make_event("load", {
                    language = "moonlift",
                    uri = uri,
                    version = version,
                    bytes = #(doc0.text or ""),
                    mode = mode,
                })
            end

            if state.phase == "analyze" then
                local analysis, err
                if mode == "diagnostic" then
                    analysis, err = analyze_doc_diagnostic_safe(doc0)
                else
                    analysis, err = analyze_doc_safe(doc0)
                end
                if not analysis then
                    state.phase = "done"
                    return state, param.ctx:make_event("error", {
                        code = "E_LSP_ANALYSIS",
                        message = tostring(err),
                        uri = uri,
                        version = version,
                    })
                end
                state.analysis = analysis
                state.phase = "symbols"
                return state, param.ctx:make_event("index", {
                    language = "moonlift",
                    uri = uri,
                    version = version,
                    mode = mode,
                    analysis = analysis,
                })
            end

            if state.phase == "symbols" then
                if opts0.symbols then
                    state.symbols = state.symbols or Sym.symbols(state.analysis)
                    state.symbol_index = state.symbol_index or 1
                    local symbol = state.symbols[state.symbol_index]
                    if symbol ~= nil then
                        state.symbol_index = state.symbol_index + 1
                        return state, param.ctx:make_event("symbol", {
                            uri = uri,
                            version = version,
                            symbol = symbol,
                        })
                    end
                end
                state.phase = "hover"
            end

            if state.phase == "hover" then
                state.phase = "diagnostics"
                if opts0.hover then
                    return state, param.ctx:make_event("hover", {
                        uri = uri,
                        version = version,
                        query = opts0.hover,
                        hover = Hov.hover(opts0.hover, state.analysis),
                    })
                end
            end

            if state.phase == "diagnostics" then
                if opts0.diagnostics and not diagnostics_disabled then
                    state.diagnostics = state.diagnostics or Diag.diagnostics(state.analysis)
                    state.diagnostic_index = state.diagnostic_index or 1
                    local diagnostic = state.diagnostics[state.diagnostic_index]
                    if diagnostic ~= nil then
                        state.diagnostic_index = state.diagnostic_index + 1
                        return state, param.ctx:make_event("diagnostic", {
                            uri = uri,
                            version = version,
                            diagnostic = diagnostic,
                        })
                    end
                end
                state.phase = "result"
            end

            if state.phase == "result" then
                state.phase = "done"
                return state, param.ctx:make_event("result", { result = state.analysis })
            end

            return nil
        end
        return gen, { ctx = ctx, doc = doc, opts = opts, mode = opts.mode or "light" }, { phase = "load" }
    end

    local document_events_process = llb.process. lsp_document { "doc", "opts" } (lsp_document_process_body)

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
        local cls = schema.classof(pick.subject)
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

    local client_exit_class = schema.classof(E.ClientExit)
    local function is_bare(cls, event, variant, variant_class)
        return event == variant or (variant_class ~= false and cls == variant_class)
    end

    local function dispatch_phase(tr)
        local event = tr.event
        local cls = schema.classof(event)
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
                    ranges = schema.classof(def) == E.DefinitionHit and def.ranges or {}
                end
                return L.PayloadLocations(Adapt.locations(ranges))
            end)
        elseif cls == E.ClientReferences then
            out[#out + 1] = with_doc(state, event.query.position.uri, event.id, L.PayloadLocations({}), function(_, analysis)
                local ids, label = subject_ids_at(event.query.position, analysis)
                local ranges = #ids > 0 and workspace_ranges_for_subjects(state, ids, event.query.include_declaration, label) or {}
                if #ranges == 0 then
                    local refs = Refs.references(event.query, analysis)
                    ranges = schema.classof(refs) == E.ReferenceHit and refs.ranges or {}
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
                if schema.classof(help) == E.SignatureHelp then return L.PayloadSignatureHelp(Adapt.signature_help(help)) end
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
                if schema.classof(prepared) == E.PrepareRenameOk then return L.PayloadPrepareRename(Adapt.prepare_rename(prepared)) end
                return L.PayloadNull
            end)
        elseif cls == E.ClientRename then
            out[#out + 1] = with_doc(state, event.query.position.uri, event.id, L.PayloadWorkspaceEdit({}), function(_, analysis)
                local ids, label = subject_ids_at(event.query.position, analysis)
                local edits = #ids > 0 and workspace_rename_edits(state, ids, label, event.query.new_name) or {}
                if #edits == 0 then
                    local rr = Ren.rename(event.query, analysis)
                    edits = schema.classof(rr) == E.RenameOk and rr.edits or {}
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
    end

    local function commands(transition)
        return dispatch_phase(transition)
    end

    return {
        analyze_document_phase = analyze_document_phase,
        diagnostic_document_phase = diagnostic_document_phase,
        document_events_process = document_events_process,
        dispatch_phase = dispatch_phase,
        commands = commands,
    }
end

return bind_context
