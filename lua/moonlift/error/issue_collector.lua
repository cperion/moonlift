-- moonlift/error/issue_collector.lua
-- IssueCollector: the single explicit boundary between the analysis engine
-- and the diagnostic engine.
--
-- Two implementations:
--   CollectingCollector — for LSP path: stores all issues, produces ResolvedIssue[]
--   ThrowingCollector   — for standalone path: renders first issue via terminal, throws error()
--
-- Every phase calls collector:emit(issue, phase) with raw ASDL issue nodes.
-- The collector runs the phase's span resolver, attaches the source span,
-- and asserts that the span is non-nil (always, not just in tests).

local Span = require("moonlift.error.span")
local CascadeFilter = require("moonlift.error.cascade_filter")

local M = {}

-------------------------------------------------------------------------------
-- ResolvedIssue: the canonical issue record
--
-- Guaranteed to have a non-nil .span field. The collector asserts this
-- unconditionally after running the span resolver.
-------------------------------------------------------------------------------

local function make_resolved(issue, span, phase, code, analysis_ctx)
    assert(span ~= nil, "span must be non-nil for " .. tostring(phase) .. " issue")
    return {
        issue = issue,
        span = span,
        phase = phase,
        code = code,
        analysis_ctx = analysis_ctx,
    }
end

local function report_analysis(base, resolved_span)
    local out = {}
    for k, v in pairs(base or {}) do out[k] = v end
    out.resolved_span = resolved_span
    return out
end

-------------------------------------------------------------------------------
-- Span resolver runner
-------------------------------------------------------------------------------

local function resolve_span(resolvers, phase, issue, analysis_ctx)
    local resolver = resolvers[phase]
    if not resolver then
        error("no span resolver registered for phase: " .. tostring(phase), 3)
    end
    local span = resolver(issue, analysis_ctx)
    if not span then
        error("span resolver returned nil for phase: " .. tostring(phase)
            .. " issue: " .. tostring(issue), 3)
    end
    return span
end

-------------------------------------------------------------------------------
-- CollectingCollector
--
-- Stores all issues. Produces ResolvedIssue[] via resolved_issues() method.
-- Created per analysis cycle in the LSP path.
-------------------------------------------------------------------------------

local CollectingCollector = {}
CollectingCollector.__index = CollectingCollector

function M.CollectingCollector(resolvers, analysis_ctx)
    assert(resolvers ~= nil, "span resolvers table required")
    assert(analysis_ctx ~= nil, "analysis context required")
    return setmetatable({
        resolvers = resolvers,
        analysis_ctx = analysis_ctx,
        issues = {},       -- ResolvedIssue[]
        has_errors = false,
    }, CollectingCollector)
end

function CollectingCollector:emit(issue, phase)
    local span = resolve_span(self.resolvers, phase, issue, self.analysis_ctx)
    -- Determine code
    local Catalog = require("moonlift.error.catalog")
    local code = Catalog.code_for_issue(issue)
    self.issues[#self.issues + 1] = make_resolved(issue, span, phase, code, self.analysis_ctx)
    if code ~= "W" and not code:find("^W") and code ~= "H" and not code:find("^H") then
        -- Error codes start with E
        if code:match("^E") then
            self.has_errors = true
        end
    end
end

function CollectingCollector:resolved_issues()
    return self.issues
end

function CollectingCollector:has_errors()
    return self.has_errors
end

--- Run the full pipeline: cascade filter → catalog → ErrorReport[]
function CollectingCollector:reports()
    local filtered = CascadeFilter.filter(self.issues)
    local Catalog = require("moonlift.error.catalog")
    local reports = {}
    for _, ri in ipairs(filtered) do
        local report = Catalog.build_report(ri.code, ri.issue, ri.phase,
            report_analysis(ri.analysis_ctx or self.analysis_ctx, ri.span))
        if report then
            reports[#reports + 1] = report
        end
    end
    return reports
end

--- Render to LSP diagnostics
function CollectingCollector:render_lsp()
    local reports = self:reports()
    local LSP = require("moonlift.error.present_lsp")
    return LSP.render_all(reports)
end

--- Render to terminal string
function CollectingCollector:render_terminal()
    local reports = self:reports()
    local Terminal = require("moonlift.error.present_terminal")
    return Terminal.render_all(reports, self.analysis_ctx.source_text or "")
end

-------------------------------------------------------------------------------
-- ThrowingCollector
--
-- For the standalone/metaprogramming path. On the first emit(), renders
-- via present_terminal and calls error(). Preserves the "fail fast"
-- behavior of the current raise_host_issue() while using the same
-- diagnostic pipeline.
-------------------------------------------------------------------------------

local ThrowingCollector = {}
ThrowingCollector.__index = ThrowingCollector

function M.ThrowingCollector(resolvers, analysis_ctx, catalog, terminal_renderer)
    assert(resolvers ~= nil, "span resolvers table required")
    assert(analysis_ctx ~= nil, "analysis context required")
    return setmetatable({
        resolvers = resolvers,
        analysis_ctx = analysis_ctx,
        catalog = catalog,
        terminal_renderer = terminal_renderer,
        threw = false,
    }, ThrowingCollector)
end

function ThrowingCollector:emit(issue, phase)
    if self.threw then return end  -- already throwing, don't double-report

    local span = resolve_span(self.resolvers, phase, issue, self.analysis_ctx)
    local Catalog = require("moonlift.error.catalog")
    local code = Catalog.code_for_issue(issue)

    -- Only throw on errors, not warnings/info/hints
    if code:match("^E") then
        self.threw = true
        local report = Catalog.build_report(code, issue, phase,
            report_analysis(self.analysis_ctx, span))
        local msg
        if report and self.terminal_renderer then
            msg = self.terminal_renderer(report, self.analysis_ctx.source_text or "")
        else
            msg = "error[" .. code .. "]: " .. tostring(issue)
        end
        error(msg, 3)
    end
end

--- Convenience: check if we've already thrown (for guarded phase code)
function ThrowingCollector:has_errors()
    return self.threw
end

function ThrowingCollector:resolved_issues()
    return {}
end

function ThrowingCollector:reports()
    return {}
end

-------------------------------------------------------------------------------
-- Convenience factory
-------------------------------------------------------------------------------

--- Create the right collector for the context.
-- @param opts  table with optional fields:
--   .standalone — if true, creates ThrowingCollector; otherwise CollectingCollector
--   .analysis_ctx — the analysis context object
-- @return IssueCollector
function M.create(opts)
    opts = opts or {}
    local resolvers = require("moonlift.error.span_resolvers").RESOLVERS
    local analysis_ctx = opts.analysis_ctx or {}
    if opts.standalone then
        local Catalog = require("moonlift.error.catalog")
        local Terminal = require("moonlift.error.present_terminal")
        return M.ThrowingCollector(resolvers, analysis_ctx, Catalog, Terminal.render)
    end
    return M.CollectingCollector(resolvers, analysis_ctx)
end

return M
