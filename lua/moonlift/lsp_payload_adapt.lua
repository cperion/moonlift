local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local E = T.MoonEditor
    local L = T.MoonLsp

    local symbol_kind_number = {
        [E.SymFile] = 1, [E.SymModule] = 2, [E.SymNamespace] = 3, [E.SymPackage] = 4,
        [E.SymClass] = 5, [E.SymMethod] = 6, [E.SymProperty] = 7, [E.SymField] = 8,
        [E.SymConstructor] = 9, [E.SymEnum] = 10, [E.SymInterface] = 11,
        [E.SymFunction] = 12, [E.SymVariable] = 13, [E.SymConstant] = 14,
        [E.SymString] = 15, [E.SymNumber] = 16, [E.SymBoolean] = 17, [E.SymArray] = 18,
        [E.SymObject] = 19, [E.SymKey] = 20, [E.SymNull] = 21, [E.SymEnumMember] = 22,
        [E.SymStruct] = 23, [E.SymEvent] = 24, [E.SymOperator] = 25, [E.SymTypeParameter] = 26,
    }

    local completion_kind_number = {
        [E.CompletionText] = 1, [E.CompletionMethod] = 2, [E.CompletionFunction] = 3,
        [E.CompletionConstructor] = 4, [E.CompletionField] = 5, [E.CompletionVariable] = 6,
        [E.CompletionClass] = 7, [E.CompletionInterface] = 8, [E.CompletionModule] = 9,
        [E.CompletionProperty] = 10, [E.CompletionUnit] = 11, [E.CompletionValue] = 12,
        [E.CompletionEnum] = 13, [E.CompletionKeyword] = 14, [E.CompletionSnippet] = 15,
        [E.CompletionColor] = 16, [E.CompletionFile] = 17, [E.CompletionReference] = 18,
        [E.CompletionFolder] = 19, [E.CompletionEnumMember] = 20, [E.CompletionConstant] = 21,
        [E.CompletionStruct] = 22, [E.CompletionEvent] = 23, [E.CompletionOperator] = 24,
        [E.CompletionTypeParameter] = 25,
    }

    local token_type_number = {
        [E.TokNamespace] = 0, [E.TokType] = 1, [E.TokClass] = 2, [E.TokEnum] = 3,
        [E.TokInterface] = 4, [E.TokStruct] = 5, [E.TokTypeParameter] = 6,
        [E.TokParameter] = 7, [E.TokVariable] = 8, [E.TokProperty] = 9,
        [E.TokEnumMember] = 10, [E.TokEvent] = 11, [E.TokFunction] = 12,
        [E.TokMethod] = 13, [E.TokMacro] = 14, [E.TokKeyword] = 15,
        [E.TokModifier] = 16, [E.TokComment] = 17, [E.TokString] = 18,
        [E.TokNumber] = 19, [E.TokRegexp] = 20, [E.TokOperator] = 21,
        [E.TokDecorator] = 22,
    }
    local code_action_kind_string = {
        [E.CodeActionQuickFix] = "quickfix",
        [E.CodeActionRefactor] = "refactor",
        [E.CodeActionSource] = "source",
        [E.CodeActionOrganizeImports] = "source.organizeImports",
    }

    local highlight_kind_number = {
        [E.HighlightText] = 1,
        [E.HighlightRead] = 2,
        [E.HighlightWrite] = 3,
    }

    local token_mod_bit = {
        [E.TokModDeclaration] = 1, [E.TokModDefinition] = 2, [E.TokModReadonly] = 4,
        [E.TokModStatic] = 8, [E.TokModDeprecated] = 16, [E.TokModAbstract] = 32,
        [E.TokModAsync] = 64, [E.TokModModification] = 128, [E.TokModDocumentation] = 256,
        [E.TokModDefaultLibrary] = 512, [E.TokModMutable] = 1024, [E.TokModExported] = 2048,
        [E.TokModStorage] = 4096, [E.TokModDiagnostic] = 8192,
    }

    local function position(pos)
        return L.ProtocolPosition(pos.line, pos.utf16_col)
    end

    local function range(r)
        return L.ProtocolRange(position(r.start), position(r.stop))
    end

    local function diagnostic_severity(sev)
        if sev == E.DiagnosticError then return 1 end
        if sev == E.DiagnosticWarning then return 2 end
        if sev == E.DiagnosticInformation then return 3 end
        return 4
    end

    local function diagnostic(d)
        return L.DiagnosticPayload(range(d.range), diagnostic_severity(d.severity), d.code, d.message)
    end

    local function diagnostic_payloads(diagnostics)
        local out = {}
        for i = 1, #diagnostics do out[i] = diagnostic(diagnostics[i]) end
        return out
    end

    local function diagnostic_report(uri, version, diagnostics)
        return L.DiagnosticReport(uri, version, diagnostic_payloads(diagnostics))
    end

    local function diagnostic_document_report(diagnostics)
        return L.DiagnosticDocumentReport("full", diagnostic_payloads(diagnostics))
    end

    local function hover(h)
        local cls = pvm.classof(h)
        if cls == E.HoverInfo then
            return L.Hover(h.kind, h.value, range(h.range))
        end
        return L.HoverNull
    end

    local function completion_list(items)
        local out = {}
        for i = 1, #items do
            local item = items[i]
            out[i] = L.CompletionPayload(item.label, completion_kind_number[item.kind] or 1, item.detail, item.documentation, item.insert_text)
        end
        return L.CompletionList(false, out)
    end

    local function symbol_payload(symbol, children)
        return L.DocumentSymbolPayload(
            symbol.name,
            symbol.detail,
            symbol_kind_number[symbol.kind] or 13,
            range(symbol.range),
            range(symbol.selection_range),
            children or {}
        )
    end

    local function document_symbols(symbols)
        local by_parent, by_id = {}, {}
        for i = 1, #symbols do
            local sym = symbols[i]
            by_id[sym.id.text] = sym
            local parent = sym.parent and sym.parent.text or "root"
            local bucket = by_parent[parent]
            if not bucket then bucket = {}; by_parent[parent] = bucket end
            bucket[#bucket + 1] = sym
        end
        local function build(sym)
            local raw_children = by_parent[sym.id.text] or {}
            local children = {}
            for i = 1, #raw_children do children[i] = build(raw_children[i]) end
            return symbol_payload(sym, children)
        end
        local roots = by_parent.root or {}
        local out = {}
        for i = 1, #roots do out[i] = build(roots[i]) end
        return out
    end

    local function signature_help(help)
        if pvm.classof(help) ~= E.SignatureHelp then return nil end
        local signatures = {}
        for i = 1, #help.signatures do
            local sig = help.signatures[i]
            local params = {}
            for j = 1, #sig.params do
                params[j] = L.SignatureParameterPayload(sig.params[j].label, sig.params[j].documentation)
            end
            signatures[i] = L.SignatureInformationPayload(sig.label, sig.documentation, params)
        end
        return L.SignatureHelpPayload(signatures, help.active_signature, help.active_parameter)
    end

    local function locations(ranges)
        local out = {}
        for i = 1, #ranges do out[i] = L.Location(ranges[i].uri, range(ranges[i])) end
        return out
    end

    local function workspace_symbols(symbols, query)
        query = tostring(query or ""):lower()
        local out = {}
        for i = 1, #symbols do
            local s = symbols[i]
            if query == "" or s.name:lower():find(query, 1, true) or s.detail:lower():find(query, 1, true) then
                out[#out + 1] = L.WorkspaceSymbolPayload(s.name, s.detail, symbol_kind_number[s.kind] or 13, L.Location(s.range.uri, range(s.selection_range)), s.parent and s.parent.text or "")
            end
        end
        return out
    end

    local function document_highlights(highlights)
        local out = {}
        for i = 1, #highlights do
            out[i] = L.DocumentHighlightPayload(range(highlights[i].range), highlight_kind_number[highlights[i].kind] or 1)
        end
        return out
    end

    local function prepare_rename(prepared)
        if pvm.classof(prepared) ~= E.PrepareRenameOk then return nil end
        return L.PrepareRenamePayload(range(prepared.range), prepared.placeholder)
    end

    local function workspace_edit(edits)
        local by_uri, order = {}, {}
        for i = 1, #edits do
            local edit = edits[i]
            local key = edit.range.uri.text
            if not by_uri[key] then by_uri[key] = {}; order[#order + 1] = edit.range.uri end
            local bucket = by_uri[key]
            bucket[#bucket + 1] = L.TextEditPayload(range(edit.range), edit.new_text)
        end
        local out = {}
        for i = 1, #order do out[i] = L.WorkspaceEditPayload(order[i], by_uri[order[i].text]) end
        return out
    end

    local function code_actions(actions)
        local out = {}
        for i = 1, #actions do
            local a = actions[i]
            local diagnostics = {}
            for j = 1, #a.diagnostics do diagnostics[j] = diagnostic(a.diagnostics[j]) end
            out[i] = L.CodeActionPayload(a.title, code_action_kind_string[a.kind] or "quickfix", diagnostics, workspace_edit(a.edit.edits))
        end
        return out
    end

    local function folding_ranges(ranges)
        local out = {}
        for i = 1, #ranges do
            local r = ranges[i].range
            out[i] = L.FoldingRangePayload(r.start.line, r.start.utf16_col, r.stop.line, r.stop.utf16_col, ranges[i].kind)
        end
        return out
    end

    local function selection_ranges(ranges)
        local out = {}
        for i = 1, #ranges do
            local parents = {}
            for j = 1, #ranges[i].parents do parents[j] = L.SelectionRangePayload(range(ranges[i].parents[j]), {}) end
            out[i] = L.SelectionRangePayload(range(ranges[i].range), parents)
        end
        return out
    end

    local function inlay_hints(hints)
        local out = {}
        for i = 1, #hints do out[i] = L.InlayHintPayload(position(hints[i].pos), hints[i].label, hints[i].kind) end
        return out
    end

    local function semantic_tokens(spans)
        table.sort(spans, function(a, b)
            if a.range.start.line ~= b.range.start.line then return a.range.start.line < b.range.start.line end
            return a.range.start.utf16_col < b.range.start.utf16_col
        end)
        local data, n = {}, 0
        local prev_line, prev_col = 0, 0
        for i = 1, #spans do
            local span = spans[i]
            local line = span.range.start.line
            local col = span.range.start.utf16_col
            local len = math.max(1, span.range.stop.utf16_col - span.range.start.utf16_col)
            local mods = 0
            for j = 1, #span.modifiers do mods = mods + (token_mod_bit[span.modifiers[j]] or 0) end
            n = n + 1; data[n] = line - prev_line
            n = n + 1; data[n] = (line == prev_line) and (col - prev_col) or col
            n = n + 1; data[n] = len
            n = n + 1; data[n] = token_type_number[span.token_type] or 0
            n = n + 1; data[n] = mods
            prev_line, prev_col = line, col
        end
        return L.SemanticTokens(data)
    end

    return {
        position = position,
        range = range,
        diagnostic = diagnostic,
        diagnostic_payloads = diagnostic_payloads,
        diagnostic_report = diagnostic_report,
        diagnostic_document_report = diagnostic_document_report,
        hover = hover,
        completion_list = completion_list,
        document_symbols = document_symbols,
        signature_help = signature_help,
        locations = locations,
        workspace_symbols = workspace_symbols,
        document_highlights = document_highlights,
        prepare_rename = prepare_rename,
        workspace_edit = workspace_edit,
        code_actions = code_actions,
        folding_ranges = folding_ranges,
        selection_ranges = selection_ranges,
        inlay_hints = inlay_hints,
        semantic_tokens = semantic_tokens,
    }
end

return M
