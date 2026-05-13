-- moonlift/error/report.lua
-- Structured error report: the central artifact of the error system.
--
-- An ErrorReport is NOT a string. It is a tree that can be rendered
-- to terminal, LSP, JSON, or any future format. Every error the
-- compiler emits becomes an ErrorReport before it reaches the user.

local M = {}

-------------------------------------------------------------------------------
-- Report construction
-------------------------------------------------------------------------------

function M.new(fields)
    return {
        code = fields.code or "E0000",
        severity = fields.severity or "error",   -- error | warning | info | hint
        phase_context = fields.phase_context,     -- "while type-checking this function"

        primary = fields.primary or {
            span = nil,
            message = "unknown error",
            label = nil,
        },

        secondary = fields.secondary or {},       -- { span, label }[]
        notes = fields.notes or {},               -- { message }[]
        suggestions = fields.suggestions or {},   -- { message, replacement? }[]
        children = fields.children or {},         -- ErrorReport[]
    }
end

-------------------------------------------------------------------------------
-- Convenience constructors
-------------------------------------------------------------------------------

function M.error(code, message, span, label)
    return M.new({
        code = code,
        severity = "error",
        primary = { span = span, message = message, label = label },
    })
end

function M.warning(code, message, span, label)
    return M.new({
        code = code,
        severity = "warning",
        primary = { span = span, message = message, label = label },
    })
end

function M.info(code, message, span, label)
    return M.new({
        code = code,
        severity = "info",
        primary = { span = span, message = message, label = label },
    })
end

-------------------------------------------------------------------------------
-- Report mutation (functional — returns new report)
-------------------------------------------------------------------------------

function M.with_note(report, message)
    local r = M.copy(report)
    r.notes[#r.notes + 1] = { message = message }
    return r
end

function M.with_suggestion(report, message, replacement)
    local r = M.copy(report)
    r.suggestions[#r.suggestions + 1] = {
        message = message,
        replacement = replacement,
    }
    return r
end

function M.with_secondary(report, span, label)
    local r = M.copy(report)
    r.secondary[#r.secondary + 1] = { span = span, label = label }
    return r
end

function M.with_child(report, child)
    local r = M.copy(report)
    r.children[#r.children + 1] = child
    return r
end

function M.with_phase_context(report, ctx)
    local r = M.copy(report)
    r.phase_context = ctx
    return r
end

-------------------------------------------------------------------------------
-- Copy
-------------------------------------------------------------------------------

function M.copy(report)
    local out = {}
    for k, v in pairs(report) do
        if k == "primary" then
            -- Deep copy the primary table
            local pc = {}
            for pk, pv in pairs(v) do pc[pk] = pv end
            out[k] = pc
        elseif type(v) == "table" then
            local copy = {}
            for i, item in ipairs(v) do
                if type(item) == "table" then
                    local ic = {}
                    for ik, iv in pairs(item) do ic[ik] = iv end
                    copy[i] = ic
                else
                    copy[i] = item
                end
            end
            out[k] = copy
        else
            out[k] = v
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- Queries
-------------------------------------------------------------------------------

function M.is_error(report)
    return report.severity == "error"
end

function M.is_warning(report)
    return report.severity == "warning"
end

function M.has_span(report)
    return report.primary and report.primary.span ~= nil
end

-- Count total diagnostics including children
function M.count(report)
    local n = 1
    for i = 1, #report.children do
        n = n + M.count(report.children[i])
    end
    return n
end

-- Collect all suggestions (including from children)
function M.all_suggestions(report)
    local out = {}
    for i = 1, #report.suggestions do out[#out + 1] = report.suggestions[i] end
    for i = 1, #report.children do
        local child_s = M.all_suggestions(report.children[i])
        for j = 1, #child_s do out[#out + 1] = child_s[j] end
    end
    return out
end

return M
