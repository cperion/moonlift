-- lalin/error/span_resolvers.lua
-- Static registry of per-phase span resolver functions.
--
-- Each resolver is a pure function: (issue, analysis_ctx) → SourceSpan
-- The collector asserts that the returned span is non-nil (always, not just in tests).
--
-- Resolvers are registered statically in the RESOLVERS table, NOT via
-- dynamic set_span_resolver() calls. A nil resolver entry is a hard error
-- at collector creation time.

local Span = require("lalin.error.span")

local M = {}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function anchor_items(anchors)
    if not anchors then return {} end
    return anchors.anchors or anchors
end

local function first_anchor_with_label(anchors, label)
    if not label then return nil end
    anchors = anchor_items(anchors)
    for i = 1, #anchors do
        local a = anchors[i]
        if a.label == label then return a end
    end
    return nil
end

local function anchor_kind_name(anchor)
    local k = anchor and anchor.kind
    if type(k) == "string" then return k end
    local ok, cls = pcall(function() return require("lalin.pvm").classof(k) end)
    return ok and cls and cls.kind or tostring(k)
end

local function anchor_kind_is(anchor, kind)
    return anchor_kind_name(anchor) == kind
end

local function first_anchor_kind_label(anchors, kind, label)
    anchors = anchor_items(anchors)
    for i = 1, #anchors do
        local a = anchors[i]
        if anchor_kind_is(a, kind) and (label == nil or a.label == label) then return a end
    end
    return nil
end

local function nth_anchor_kind_label(anchors, kind, label, ordinal)
    anchors = anchor_items(anchors)
    local n = 0
    for i = 1, #anchors do
        local a = anchors[i]
        if anchor_kind_is(a, kind) and (label == nil or a.label == label) then
            n = n + 1
            if n == ordinal then return a end
        end
    end
    return nil
end

local function resolved_span(issue, analysis)
    if issue and issue.span then return issue.span end
    if analysis and analysis.resolved_span then return analysis.resolved_span end
    return nil
end

local function range_to_span(range, uri)
    if not range then return nil end
    return Span.from_source_range(range, uri)
end

local function document_from_analysis(analysis)
    if not analysis then return nil end
    if analysis.document then return analysis.document end
    return analysis.parse and analysis.parse.parts and analysis.parse.parts.document or nil
end

local function doc_uri(analysis)
    local doc = document_from_analysis(analysis)
    return (analysis and analysis.uri) or (doc and doc.uri and doc.uri.text) or "?"
end

local function doc_text(analysis)
    local doc = document_from_analysis(analysis)
    return (analysis and analysis.source_text) or (doc and doc.text) or ""
end

local function span_from_offsets(analysis, start_offset, end_offset)
    return Span.from_source_text(doc_uri(analysis), doc_text(analysis), start_offset, end_offset)
end

local function fallback_span(analysis)
    return span_from_offsets(analysis, 0, 1)
end

-------------------------------------------------------------------------------
-- Operator symbol table (duplicated from catalog.lua)
-------------------------------------------------------------------------------

local op_symbols = {
    BinAdd = "+", BinSub = "-", BinMul = "*", BinDiv = "/", BinRem = "%",
    BinBitAnd = "&", BinBitOr = "|", BinBitXor = "~", BinShl = "<<", BinLShr = ">>>", BinAShr = ">>",
    CmpEq = "==", CmpNe = "~=", CmpLt = "<", CmpLe = "<=", CmpGt = ">", CmpGe = ">=",
    LogicAnd = "&&", LogicOr = "||", UnaryNot = "not", UnaryNeg = "-", UnaryBitNot = "~",
    ["LalinCore.BinAdd"] = "+", ["LalinCore.BinSub"] = "-", ["LalinCore.BinMul"] = "*",
    ["LalinCore.BinDiv"] = "/", ["LalinCore.BinRem"] = "%",
    ["LalinCore.BinBitAnd"] = "&", ["LalinCore.BinBitOr"] = "|", ["LalinCore.BinBitXor"] = "~",
    ["LalinCore.BinShl"] = "<<", ["LalinCore.BinLShr"] = ">>>", ["LalinCore.BinAShr"] = ">>",
    ["LalinCore.CmpEq"] = "==", ["LalinCore.CmpNe"] = "~=", ["LalinCore.CmpLt"] = "<",
    ["LalinCore.CmpLe"] = "<=", ["LalinCore.CmpGt"] = ">", ["LalinCore.CmpGe"] = ">=",
    ["LalinCore.LogicAnd"] = "and", ["LalinCore.LogicOr"] = "or",
    ["LalinCore.UnaryNot"] = "not", ["LalinCore.UnaryNeg"] = "-", ["LalinCore.UnaryBitNot"] = "~",
}

local function op_symbol_name(op)
    if not op then return "?" end
    local s = tostring(op)
    if op_symbols[s] then return op_symbols[s] end
    local short = s:match("^LalinCore%.(.+)$")
    if short and op_symbols[short] then return op_symbols[short] end
    return s
end

-------------------------------------------------------------------------------
-- Site string → anchor range resolution
--
-- Mirrors the logic from editor_error_reports.lua's site_range() and
-- operator_range() functions.
-------------------------------------------------------------------------------

local function site_range_from_anchors(anchors, analysis, site)
    site = tostring(site or "")

    local field_name = site:match("^struct field '([^']+)'$")
                    or site:match('^struct field "([^"]+)"$')
                    or site:match("^field%s+([_%a][_%w]*)$")
    if field_name then
        local a = first_anchor_kind_label(anchors, "AnchorFieldName", field_name)
        if a then return a.range end
    end

    -- 1. Variable/param bindings
    local name = site:match("^let%s+([_%a][_%w]*)")
              or site:match("^var%s+([_%a][_%w]*)")
              or site:match("^block param%s+([_%a][_%w]*)")
    if name then
        local a = first_anchor_with_label(anchors, name)
        if a then return a.range end
    end

    -- 2. Keyword sites
    local keyword_map = {
        ["return"] = "return", ["yield"] = "yield", ["yield value"] = "yield",
        ["if cond"] = "if", ["if branches"] = "if",
        ["select cond"] = "if", ["select branches"] = "if",
        ["switch key"] = "switch", ["switch arm"] = "switch",
        ["assert"] = "assert", ["not"] = "not",
        ["const"] = "const", ["static"] = "static",
        ["view data"] = "view", ["view len"] = "view", ["view stride"] = "view",
        ["view window start"] = "view", ["view window len"] = "view",
    }
    local kw = keyword_map[site]
    if kw then
        local a = first_anchor_kind_label(anchors, "AnchorKeyword", kw)
        if a then return a.range end
    end

    -- 3. Function-like sites (S.AnchorFunctionUse or S.AnchorKeyword)
    local func_sites = {
        ["call"] = true, ["call arg"] = true,
        ["len"] = true,
        ["bounds base"] = true, ["bounds len"] = true,
        ["window_bounds base"] = true, ["window_bounds base_len"] = true,
        ["window_bounds start"] = true, ["window_bounds len"] = true,
        ["disjoint lhs"] = true, ["disjoint rhs"] = true,
        ["same_len lhs"] = true, ["same_len rhs"] = true,
        ["memory contract base"] = true,
    }
    if func_sites[site] then
        local a = first_anchor_kind_label(anchors, "AnchorFunctionUse", site)
               or first_anchor_kind_label(anchors, "AnchorKeyword", site)
        if a then return a.range end
    end

    -- 4. Operator/punctuation sites
    local op_map = {
        ["set"] = "=",
        ["index"] = "[",
    }
    local op = op_map[site]
    if op then
        local a = first_anchor_kind_label(anchors, "AnchorOpaque", op)
        if a then return a.range end
    end

    -- 5. Named ref sites
    if site:match("^[_%a][_%w]*$") then
        local a = first_anchor_kind_label(anchors, "AnchorBindingUse", site)
               or first_anchor_kind_label(anchors, "AnchorFunctionUse", site)
        if a then return a.range end
    end

    return nil
end

local function operator_range_from_anchors(anchors, op, ordinal)
    local sym = op_symbol_name(op)
    local kind
    if sym == "and" or sym == "or" then
        kind = "AnchorKeyword"
    else
        kind = "AnchorOpaque"
    end
    local a = nth_anchor_kind_label(anchors, kind, sym, ordinal or 1)
    return a and a.range or nil
end

local function call_span_from_callee_range(range, analysis)
    if not range then return nil end
    local text = doc_text(analysis)
    local start_offset = range.start_offset or 0
    local i = range.stop_offset or start_offset
    while i < #text do
        local b = text:byte(i + 1)
        if b == 32 or b == 9 then i = i + 1 else break end
    end
    if text:sub(i + 1, i + 1) ~= "(" then
        return range_to_span(range, doc_uri(analysis))
    end
    local depth = 0
    local j = i
    while j < #text do
        local ch = text:sub(j + 1, j + 1)
        if ch == "(" then depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then return span_from_offsets(analysis, start_offset, j + 1) end
        elseif ch == "\n" or ch == "\r" then
            break
        end
        j = j + 1
    end
    return span_from_offsets(analysis, start_offset, math.max(range.stop_offset or start_offset, i + 1))
end

local function span_after_range_on_line(range, analysis)
    if not range then return nil end
    local text = doc_text(analysis)
    if text == "" then return nil end
    local s = range.stop_offset or range.start_offset or 0
    if s < 0 then s = 0 end
    if s > #text then s = #text end
    while s < #text do
        local b = text:byte(s + 1)
        if b == 32 or b == 9 then s = s + 1 else break end
    end
    local e = s
    while e < #text do
        local b = text:byte(e + 1)
        if b == 10 or b == 13 then break end
        e = e + 1
    end
    while e > s do
        local b = text:byte(e)
        if b == 32 or b == 9 then e = e - 1 else break end
    end
    if e <= s then return nil end
    return span_from_offsets(analysis, s, e)
end

-------------------------------------------------------------------------------
-- Ordinal tracker for operator issues
--
-- Tracks how many times each operator-op combination has been seen,
-- so that the Nth instance of an operator issue maps to the Nth
-- occurrence of that operator in the source.
-------------------------------------------------------------------------------

local function new_ordinal_tracker()
    return {}
end

local function call_range_from_anchors(anchors, analysis, issue)
    local tracker = analysis._call_ordinal_tracker
    if not tracker then
        tracker = {}
        analysis._call_ordinal_tracker = tracker
    end
    local key = "call"
    tracker[key] = (tracker[key] or 0) + 1
    local a = nth_anchor_kind_label(anchors, "AnchorFunctionUse", nil, tracker[key])
    return a and a.range or nil
end

local function ordinal_for(tracker, issue)
    local cls = require("lalin.pvm").classof(issue)
    local kind = cls and cls.kind or ""
    local key = kind
    if issue.op then
        key = key .. ":" .. op_symbol_name(issue.op)
    end
    if kind == "TypeIssueInvalidLogic" then
        key = key .. ":logic"
    end
    tracker[key] = (tracker[key] or 0) + 1
    return tracker[key]
end

-------------------------------------------------------------------------------
-- Per-phase resolvers
-------------------------------------------------------------------------------

--- Parse resolver: offset-based
-- Issue has .offset field (1-based Lua string index)
function M.parse_resolver(issue, analysis)
    local prior = resolved_span(issue, analysis)
    if prior then return prior end
    local text = doc_text(analysis)
    local offset = math.max(0, (tonumber(issue.offset) or 1) - 1)
    local stop = math.min(#text, offset + 1)
    return span_from_offsets(analysis, offset, stop)
end

--- Host resolver: anchor-based
-- HostIssue carries field_name, type_name, or name fields
function M.host_resolver(issue, analysis)
    local prior = resolved_span(issue, analysis)
    if prior then return prior end
    local anchors = analysis.anchors or {}
    local pvm = require("lalin.pvm")
    local cls = pvm.classof(issue)
    if cls and cls.kind == "HostIssueBareBoolInBoundaryStruct" and issue.field_name then
        local field = first_anchor_kind_label(anchors, "AnchorFieldName", tostring(issue.field_name))
        if field and field.range then
            local best = nil
            for _, a in ipairs(anchor_items(anchors)) do
                if anchor_kind_is(a, "AnchorScalarType") and a.label == "bool"
                   and a.range and a.range.start_offset >= field.range.stop_offset then
                    if not best or a.range.start_offset < best.range.start_offset then best = a end
                end
            end
            if best then return range_to_span(best.range, doc_uri(analysis)) end
            return range_to_span(field.range, doc_uri(analysis))
        end
    end
    local labels = { issue.field_name, issue.type_name, issue.name }
    for _, label in ipairs(labels) do
        if label then
            local text = type(label) == "string" and label or tostring(label)
            local a = first_anchor_with_label(anchors, text)
            if a and a.range then
                return range_to_span(a.range, doc_uri(analysis))
            end
        end
    end
    -- Fallback: try the full doc range
    return fallback_span(analysis)
end

--- Open resolver: anchor or fallback
-- OpenIssue validation — try to find a relevant anchor
function M.open_resolver(issue, analysis)
    local prior = resolved_span(issue, analysis)
    if prior then return prior end
    -- Try to find source position from slot key or use_id
    local anchors = analysis.anchors or {}
    local label = nil
    if issue.slot then
        label = issue.slot.key or tostring(issue.slot)
    end
    if not label and issue.use_id then
        label = tostring(issue.use_id)
    end
    if not label and issue.import then
        label = tostring(issue.import)
    end
    if label then
        -- Search anchor labels for a match
        local function strip_quote(s)
            return (s:gsub("^['\"]", ""):gsub("['\"]$", ""))
        end
        local clean = strip_quote(label)
        anchors = anchor_items(anchors)
        for i = 1, #anchors do
            local a = anchors[i]
            if a.label == label or a.label == clean then
                if a.range then return range_to_span(a.range, doc_uri(analysis)) end
            end
            -- Also try matching against anchor id text (contains label)
            local id_text = a.id and a.id.text or ""
            if id_text == label or id_text:find(label, 1, true) then
                if a.range then return range_to_span(a.range, doc_uri(analysis)) end
            end
        end
    end
    return fallback_span(analysis)
end

--- Binding resolver: direct anchor range
function M.binding_resolver(issue, analysis)
    local prior = resolved_span(issue, analysis)
    if prior then return prior end
    local use = issue.use
    if use and use.anchor and use.anchor.range then
        return range_to_span(use.anchor.range, doc_uri(analysis))
    end
    return fallback_span(analysis)
end

--- Typecheck resolver: site string + operator ordinal
-- TypeIssue variants carry a .site string and sometimes .op
function M.typecheck_resolver(issue, analysis)
    local prior = resolved_span(issue, analysis)
    if prior then return prior end
    local anchors = analysis.anchors or {}
    if type(anchors) ~= "table" or #anchors == 0 then
        -- No anchors available; try offset-based fallback
        local pvm = require("lalin.pvm")
        local cls2 = pvm.classof(issue)
        if cls2 and cls2.kind == "TypeIssueUnresolvedValue" and issue.name then
            -- Without anchors, we can't resolve position. Fall through.
        end
    end
    local cls = require("lalin.pvm").classof(issue)
    local kind = cls and cls.kind or ""

    -- Unresolved value: label → anchor
    if kind == "TypeIssueUnresolvedValue" and issue.name then
        local a = first_anchor_with_label(anchors, issue.name)
        if a and a.range then return range_to_span(a.range, doc_uri(analysis)) end
    end

    -- Unresolved path: first segment → anchor
    if kind == "TypeIssueUnresolvedPath" and issue.path and issue.path.parts then
        local first = issue.path.parts[1] and issue.path.parts[1].text
        if first then
            local a = first_anchor_with_label(anchors, first)
            if a and a.range then return range_to_span(a.range, doc_uri(analysis)) end
        end
    end

    -- Call arity/callability: point at the callee token.  The issues only
    -- carry the generic site string `call`, so use source-order call anchors.
    if kind == "TypeIssueArgCount" or kind == "TypeIssueNotCallable" then
        local range = call_range_from_anchors(anchors, analysis, issue)
        if range then return call_span_from_callee_range(range, analysis) end
    end

    -- Type mismatches: site → anchor
    if kind == "TypeIssueExpected" or kind == "TypeIssueArgCount"
       or kind == "TypeIssueNotCallable" or kind == "TypeIssueNotIndexable"
       or kind == "TypeIssueNotPointer" then
        local site = issue.site or ""
        if site == "call" or site == "call arg" then
            local range = call_range_from_anchors(anchors, analysis, issue)
            if range then return call_span_from_callee_range(range, analysis) end
        end
        local range = site_range_from_anchors(anchors, analysis, site)
        if range then
            if site == "return" or site == "yield" or site == "yield value" then
                return span_after_range_on_line(range, analysis) or range_to_span(range, doc_uri(analysis))
            end
            return range_to_span(range, doc_uri(analysis))
        end
    end

    -- Operator issues: operator symbol → anchor (ordinal-aware)
    if kind == "TypeIssueInvalidUnary" or kind == "TypeIssueInvalidBinary"
       or kind == "TypeIssueInvalidCompare" or kind == "TypeIssueInvalidLogic" then
        local ordinal_tracker = analysis._ordinal_tracker
        if not ordinal_tracker then
            ordinal_tracker = new_ordinal_tracker()
            analysis._ordinal_tracker = ordinal_tracker
        end
        local ord = ordinal_for(ordinal_tracker, issue)
        local range = operator_range_from_anchors(anchors, issue.op, ord)
        if range then return range_to_span(range, doc_uri(analysis)) end
    end

    -- Control flow: label → anchor
    if kind == "TypeIssueMissingJumpTarget" or kind == "TypeIssueInvalidControl" then
        if issue.label and issue.label.name then
            local a = first_anchor_with_label(anchors, issue.label.name)
            if a and a.range then return range_to_span(a.range, doc_uri(analysis)) end
        end
    end

    -- Jump args: name → anchor
    if kind == "TypeIssueMissingJumpArg" or kind == "TypeIssueExtraJumpArg"
       or kind == "TypeIssueDuplicateJumpArg" then
        if issue.name then
            local a = first_anchor_with_label(anchors, issue.name)
            if a and a.range then return range_to_span(a.range, doc_uri(analysis)) end
        end
    end

    -- Unexpected yield: yield keyword → anchor
    if kind == "TypeIssueUnexpectedYield" then
        local a = first_anchor_kind_label(anchors, "AnchorKeyword", "yield")
        if a and a.range then return range_to_span(a.range, doc_uri(analysis)) end
    end

    -- Variant issues
    if kind == "TypeIssueUnknownVariant" or kind == "TypeIssueVariantPayloadMismatch"
       or kind == "TypeIssueDuplicateVariant" then
        local label = issue.variant_name or issue.field_name or issue.name
        if label then
            local a = first_anchor_with_label(anchors, label)
            if a and a.range then return range_to_span(a.range, doc_uri(analysis)) end
        end
    end

    return fallback_span(analysis)
end

--- Backend resolver: provenance map lookup
-- BackIssue variants carry .func, .block, .value, .sig, .data, .extern, .slot, .index
--
-- Resolution strategy (tried in order):
--   1. If issue.index is set, look up the provenance entry by cmd index.
--      If the entry has a fully-resolved span, return it directly.
--   2. If the entry has a name (not a span), look up the name in the
--      anchor index to get the source range.
--   3. If no index match, try the named entity fields (.func, .block, etc.)
--      and look them up in the anchor index.
--   4. Fall back to nil (caller handles with full-range fallback).
function M.backend_resolver(issue, analysis)
    local prior = resolved_span(issue, analysis)
    if prior then return prior end
    local provenance = analysis.back_provenance
    if not provenance then return fallback_span(analysis) end

    -- Step 1 & 2: Resolve via command index
    if issue.index then
        local span = provenance:resolve(issue.index)
        if span then return span end

        -- No direct span — try name-based resolution via anchor index
        local entry = provenance:resolve_entry(issue.index)
        if entry and entry.name then
            local anchors = analysis.anchors or {}
            local a = first_anchor_with_label(anchors, entry.name)
            if a and a.range then return range_to_span(a.range, doc_uri(analysis)) end

            -- Also try matching via AnchorFunctionName / AnchorStructName etc.
            -- by scanning all anchors for a matching label
            for _, anchor in ipairs(anchor_items(anchors)) do
                if anchor.label == entry.name then
                    if anchor.range then return range_to_span(anchor.range, doc_uri(analysis)) end
                end
            end
        end
    end

    -- Step 3: Try named entity (func, block, value, etc.)
    local name_field = issue.func or issue.block or issue.value
                       or issue.sig or issue.data or issue.extern or issue.slot
    if name_field then
        -- Try the name's text field if it's an ASDL identifier
        local name = type(name_field) == "table" and name_field.text or nil
        if name then
            local anchors = analysis.anchors or {}
            local a = first_anchor_with_label(anchors, name)
            if a and a.range then return range_to_span(a.range, doc_uri(analysis)) end
        end
    end

    return fallback_span(analysis)
end

--- Link resolver: no per-keystroke span available
-- Link validation is batch-only. Returns nil — the caller should handle.
function M.link_resolver(issue, analysis)
    return resolved_span(issue, analysis) or fallback_span(analysis)
end

-------------------------------------------------------------------------------
-- Static resolver table
--
-- Every phase must have an entry. A nil entry causes a hard assertion
-- failure at collector creation time.
-------------------------------------------------------------------------------

M.RESOLVERS = {
    parse = M.parse_resolver,
    host = M.host_resolver,
    open = M.open_resolver,
    binding = M.binding_resolver,
    typecheck = M.typecheck_resolver,
    backend = M.backend_resolver,
    link = M.link_resolver,
}

--- Validate that all phase names have resolvers
-- @param phase_names  list of strings (e.g., {"parse", "host", "open", ...})
-- @return nil on success, error string on failure
function M.validate(phase_names)
    for _, name in ipairs(phase_names) do
        if not M.RESOLVERS[name] then
            return "missing span resolver for phase: " .. name
        end
    end
    return nil
end

return M
