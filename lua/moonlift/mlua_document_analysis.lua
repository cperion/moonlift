-- Stub: mlua_document_analysis was removed in the parser cleanup.
-- Provides minimal no-op API so LSP modules can still load.
-- The LSP currently has no DSL-based document analysis; this stub
-- ensures the LSP server process doesn't crash on startup.

local M = {}

function M.Define(T)
    local S = T.MoonSource

    local function empty_analysis(doc)
        local uri = doc and doc.uri and doc.uri.text or "?"
        return {
            issues = {},
            uri = uri,
            document = doc,
        }
    end

    local function analyze_document_light(doc)
        return empty_analysis(doc)
    end

    local function analyze_document_full(doc)
        return empty_analysis(doc)
    end

    return {
        analyze_document_light = analyze_document_light,
        analyze_document_full = analyze_document_full,
    }
end

function M.resolved_issues(analysis)
    return analysis and analysis.issues or {}
end

return M
