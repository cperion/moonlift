-- lalin/error/registry.lua
-- Issue Registry: collects raw issues from all compiler phases,
-- groups by root cause, deduplicates, and produces ErrorReport trees.
--
-- The key insight: when a name doesn't resolve, every downstream use
-- of that name produces a cascade. The registry tracks root causes
-- and suppresses downstream noise. The user sees ONE error, not 47.

local Report = require("lalin.error.report")
local Span = require("lalin.error.span")
local Catalog = require("lalin.error.catalog")

local M = {}

-------------------------------------------------------------------------------
-- Registry
-------------------------------------------------------------------------------

function M.new()
    return {
        issues = {},            -- all issues, in emission order
        issue_data = {},        -- parallel array: { phase, code, root_key }
        unresolved_names = {},  -- name → index of first unresolved-name issue
        span_index = {},        -- span_key → {issue_indices}
        root_groups = {},       -- root_idx → { child_indices }
        source_cache = {},      -- uri → source_text
    }
end

-------------------------------------------------------------------------------
-- Source registration
--
-- The registry needs source text to render spans. Register it before
-- emitting issues.
-------------------------------------------------------------------------------

function M.register_source(registry, uri, text)
    registry.source_cache[uri] = text
end

-------------------------------------------------------------------------------
-- Issue emission
-------------------------------------------------------------------------------

function M.emit(registry, issue, phase, analysis)
    analysis = analysis or {}
    local idx = #registry.issues + 1

    -- Determine the catalog code for this issue
    local code = Catalog.code_for_issue(issue)

    -- Determine if this is a root cause or a cascade
    local root_key = nil

    -- Unresolved names are root causes
    local asdl = require("lalin.asdl")
    local issue_class = asdl.class_basename(issue)
    if pvm then
        if issue_class then
            if issue_class == "TypeIssueUnresolvedValue" and issue.name then
                root_key = "unresolved:" .. issue.name
                if not registry.unresolved_names[issue.name] then
                    registry.unresolved_names[issue.name] = idx
                end
            end
        end
    end

    -- Check if this issue cascades from an unresolved name
    local is_cascade = false
    if not root_key then
        -- Type mismatches involving void are often cascades
        local function is_void_type(ty)
            if not ty then return false end
            if type(ty) == "string" and ty == "void" then return true end
            local ty_class = pvm and asdl.class_basename(ty)
            if ty_class then
                return ty_class == "TScalar" and ty.scalar
                    and asdl.class_basename(ty.scalar) == "ScalarVoid"
            end
            return false
        end

        local issue_kind = issue_class or issue.kind

        if issue_kind == "TypeIssueExpected"
            or issue_kind == "TypeIssueNotCallable"
            or issue_kind == "TypeIssueNotIndexable"
            or issue_kind == "TypeIssueNotPointer"
            or issue_kind == "TypeIssueInvalidUnary"
            or issue_kind == "TypeIssueInvalidBinary"
            or issue_kind == "TypeIssueInvalidCompare"
            or issue_kind == "TypeIssueInvalidLogic" then
            -- Check if any type in the issue is void (unresolved)
            if is_void_type(issue.expected) or is_void_type(issue.actual)
                or is_void_type(issue.ty)
                or is_void_type(issue.lhs) or is_void_type(issue.rhs) then
                -- Try to find the unresolved name that caused this
                local site = issue.site or ""
                for name, _ in pairs(registry.unresolved_names) do
                    if site:find(name, 1, true) then
                        root_key = "unresolved:" .. name
                        is_cascade = true
                        break
                    end
                end
                if not root_key then
                    -- Generic void cascade — suppress but don't attach to a root
                    is_cascade = true
                end
            end
        end

        -- Binding resolution failures for names we already reported
        if issue_kind == "BindingUnresolved" and issue.use
            and issue.use.anchor and issue.use.anchor.label then
            local name = issue.use.anchor.label
            if registry.unresolved_names[name] then
                root_key = "unresolved:" .. name
                is_cascade = true
            end
        end
    end

    -- Dedup: check if we already have an issue at the same span with the same code
    local span_key = "none"
    if issue.span then
        span_key = Span.key(issue.span)
    elseif issue.offset then
        span_key = "off:" .. tostring(issue.offset)
    end

    local is_dup = false
    local existing = registry.span_index[span_key]
    if existing then
        for i = 1, #existing do
            local prev_idx = existing[i]
            if registry.issue_data[prev_idx].code == code then
                is_dup = true
                break
            end
        end
    end

    if is_dup then return end

    -- Record the issue
    registry.issues[idx] = issue
    registry.issue_data[idx] = {
        phase = phase,
        code = code,
        root_key = root_key,
        is_cascade = is_cascade,
    }

    -- Update span index
    if not registry.span_index[span_key] then
        registry.span_index[span_key] = {}
    end
    registry.span_index[span_key][#registry.span_index[span_key] + 1] = idx
end

-------------------------------------------------------------------------------
-- Batch emission
-------------------------------------------------------------------------------

function M.emit_all(registry, issues, phase, analysis)
    for i = 1, #issues do
        M.emit(registry, issues[i], phase, analysis)
    end
end

-------------------------------------------------------------------------------
-- Report generation
--
-- After all issues are emitted, call this to get the final list of
-- ErrorReports. Cascade issues are suppressed; root causes get all
-- their context.
-------------------------------------------------------------------------------

function M.reports(registry)
    local reports = {}

    for i = 1, #registry.issues do
        local data = registry.issue_data[i]
        if not data then goto continue end

        -- Skip cascade issues (they're noise from a root cause)
        if data.is_cascade then goto continue end

        local issue = registry.issues[i]
        local analysis = {
            source_text = nil,
            in_scope_names = {},
        }

        -- Build source text from cache for span rendering
        if issue.span and issue.span.uri then
            analysis.source_text = registry.source_cache[issue.span.uri]
        elseif issue.offset and registry.source_cache then
            -- Try to find source text from any registered source
            for uri, text in pairs(registry.source_cache) do
                analysis.source_text = text
                analysis.uri = uri
                break
            end
        end

        -- Add in-scope names for "did you mean?" suggestions
        analysis.in_scope_names = {}
        for name, _ in pairs(registry.unresolved_names) do
            -- Names that are unresolved are NOT candidates
        end
        -- Additional scope names can be added via analysis

        local report = Catalog.build_report(data.code, issue, data.phase, analysis)

        -- Add phase context if not already set
        if not report.phase_context and data.phase then
            report = Report.with_phase_context(report, data.phase)
        end

        reports[#reports + 1] = report

        ::continue::
    end

    return reports
end

-------------------------------------------------------------------------------
-- Statistics
-------------------------------------------------------------------------------

function M.stats(registry)
    local total = #registry.issues
    local roots = 0
    local cascades = 0
    local by_code = {}

    for i = 1, total do
        local data = registry.issue_data[i]
        if data then
            if data.is_cascade then
                cascades = cascades + 1
            else
                roots = roots + 1
            end
            by_code[data.code] = (by_code[data.code] or 0) + 1
        end
    end

    return {
        total = total,
        roots = roots,
        cascades = cascades,
        by_code = by_code,
    }
end

return M
