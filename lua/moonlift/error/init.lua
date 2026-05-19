-- moonlift/error/init.lua
-- Error management facade: unified API for the error system.
--
-- Usage:
--
--   local Errors = require("moonlift.error")
--
--   -- Create a registry for a compilation session
--   local reg = Errors.registry()
--   Errors.register_source(reg, uri, source_text)
--
--   -- Emit issues from any phase
--   Errors.emit(reg, issue, "typecheck", analysis)
--
--   -- Get final reports (cascade-suppressed, deduplicated)
--   local reports = Errors.reports(reg)
--
--   -- Render to terminal
--   print(Errors.render_terminal(reports, reg.source_cache))
--
--   -- Render to LSP diagnostics
--   local diags = Errors.render_lsp(reports)

local M = {}

-- Re-export all sub-modules
M.Span = require("moonlift.error.span")
M.Report = require("moonlift.error.report")
M.Catalog = require("moonlift.error.catalog")
M.Registry = require("moonlift.error.registry")
M.Suggest = require("moonlift.error.suggest")
M.Terminal = require("moonlift.error.present_terminal")
M.LSP = require("moonlift.error.present_lsp")

-- New Issue Stream modules
M.CollectingCollector = require("moonlift.error.issue_collector").CollectingCollector
M.ThrowingCollector = require("moonlift.error.issue_collector").ThrowingCollector
M.CascadeFilter = require("moonlift.error.cascade_filter")
M.SpanResolvers = require("moonlift.error.span_resolvers")

-- Formatting utilities (shared across explainers)
M.Format = require("moonlift.error.format")

-------------------------------------------------------------------------------
-- Convenience API
-------------------------------------------------------------------------------

function M.registry()
    return M.Registry.new()
end

function M.register_source(registry, uri, text)
    return M.Registry.register_source(registry, uri, text)
end

function M.emit(registry, issue, phase, analysis)
    return M.Registry.emit(registry, issue, phase, analysis)
end

function M.emit_all(registry, issues, phase, analysis)
    return M.Registry.emit_all(registry, issues, phase, analysis)
end

function M.reports(registry)
    return M.Registry.reports(registry)
end

function M.render_terminal(reports, source_cache)
    return M.Terminal.render_from_registry(reports, source_cache or {})
end

local function is_resolved_issue(x)
    return type(x) == "table" and x.issue ~= nil and x.phase ~= nil and x.primary == nil
end

local function report_analysis(base, span)
    local out = {}
    for k, v in pairs(base or {}) do out[k] = v end
    out.resolved_span = span
    return out
end

function M.report_from_resolved(ri, analysis_ctx)
    local ctx = report_analysis(ri.analysis_ctx or analysis_ctx or {}, ri.span)
    return M.Catalog.build_report(ri.code or M.Catalog.code_for_issue(ri.issue), ri.issue, ri.phase, ctx)
end

function M.reports_from_resolved(resolved, analysis_ctx)
    local reports = {}
    for i = 1, #(resolved or {}) do
        reports[#reports + 1] = M.report_from_resolved(resolved[i], analysis_ctx)
    end
    return reports
end

function M.render_lsp(reports_or_resolved, analysis_ctx)
    if reports_or_resolved and reports_or_resolved[1] and is_resolved_issue(reports_or_resolved[1]) then
        return M.LSP.render_all(M.reports_from_resolved(reports_or_resolved, analysis_ctx))
    end
    return M.LSP.render_all(reports_or_resolved or {})
end

-------------------------------------------------------------------------------
-- Quick single-error rendering
--
-- For one-off errors (e.g. parse errors, compile failures)
-- where you don't need the full registry pipeline.
-------------------------------------------------------------------------------

function M.quick_error(code, message, span, source_text)
    local report = M.Catalog.build_report(code, {
        message = message,
        span = span,
    }, nil, { source_text = source_text })
    return M.Terminal.render(report, source_text)
end

return M
