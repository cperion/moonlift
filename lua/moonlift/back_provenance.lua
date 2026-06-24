-- moonlift/back_provenance.lua
-- BackProvenanceMap: reverse index from BackCmd position to source AST span.
--
-- Constructed during lowering by recording every AST node→BackCmd[] mapping.
-- Lua-side backend provenance for diagnostic rendering.
--
-- Usage:
--   local provenance = BackProvenance.new()
--   provenance:record(cmd_start, cmd_end, source_range, doc_uri)
--   local span = provenance:resolve(cmd_index)  → SourceSpan | nil

local Span = require("moonlift.error.span")

local M = {}

local ProvenanceMap = {}
ProvenanceMap.__index = ProvenanceMap

function M.new()
    return setmetatable({
        entries = {},   -- { cmd_start, cmd_end, span }[]
    }, ProvenanceMap)
end

--- Record an entry for a range of backend commands.
-- Storage strategies:
--   1. If source_range is provided, a SourceSpan is computed from it.
--   2. If only name is provided (no source_range), the entry stores the name
--      for later resolution via the anchor index (LSP path).
--
-- At least one of source_range or name must be set; if neither is provided,
-- the entry is silently skipped.
--
-- @param cmd_start  first command index (1-based)
-- @param cmd_end    last command index (inclusive, 1-based)
-- @param source_range  MoonSource.Range (optional — with .start_offset, .stop_offset, .start, .stop)
-- @param doc_uri    string URI of the source document (required if source_range is set)
-- @param name       string item/function name for anchor-index resolution (optional)
function ProvenanceMap:record(cmd_start, cmd_end, source_range, doc_uri, name)
    if source_range then
        -- Full span resolution from source range
        local span = Span.from_offsets(
            doc_uri,
            source_range.start_offset,
            source_range.stop_offset,
            (source_range.start and source_range.start.line or 0) + 1,
            (source_range.start and source_range.start.utf16_col or 0) + 1,
            (source_range.stop and source_range.stop.line or 0) + 1,
            (source_range.stop and source_range.stop.utf16_col or 0) + 1
        )
        self.entries[#self.entries + 1] = {
            cmd_start = cmd_start,
            cmd_end = cmd_end,
            span = span,
        }
    elseif name then
        -- Name-only entry; span will be resolved later via anchor index
        self.entries[#self.entries + 1] = {
            cmd_start = cmd_start,
            cmd_end = cmd_end,
            name = name,
        }
    end
    -- If neither source_range nor name, silently skip
end

--- Resolve a single command index to a source span.
-- Only returns spans that were fully resolved at recording time.
-- For name-only entries (recorded without source_range), returns nil.
-- Use :resolve_entry() to get the raw entry for name-based resolution.
--
-- @param cmd_index  1-based index into the BackCmd array
-- @return SourceSpan or nil if not found
function ProvenanceMap:resolve(cmd_index)
    for _, entry in ipairs(self.entries) do
        if cmd_index >= entry.cmd_start and cmd_index <= entry.cmd_end then
            return entry.span
        end
    end
    return nil
end

--- Resolve a single command index to the raw provenance entry.
-- Returns the full entry table even if no source span was recorded,
-- allowing callers to resolve the name via an external index.
--
-- @param cmd_index  1-based index into the BackCmd array
-- @return table { cmd_start, cmd_end, span?, name? } or nil
function ProvenanceMap:resolve_entry(cmd_index)
    for _, entry in ipairs(self.entries) do
        if cmd_index >= entry.cmd_start and cmd_index <= entry.cmd_end then
            return entry
        end
    end
    return nil
end

--- Resolve a range of command indices to the encompassing source span.
-- Only considers entries with fully-resolved spans (not name-only entries).
-- @param start_idx  1-based start index
-- @param end_idx    1-based end index
-- @return SourceSpan or nil
function ProvenanceMap:resolve_range(start_idx, end_idx)
    local merged = nil
    for _, entry in ipairs(self.entries) do
        if entry.span and entry.cmd_start >= start_idx and entry.cmd_end <= end_idx then
            if not merged then
                merged = entry.span
            else
                -- Extend span to cover both ranges
                if entry.span.start_offset < merged.start_offset then
                    merged.start_offset = entry.span.start_offset
                    merged.start_line = entry.span.start_line
                    merged.start_col = entry.span.start_col
                end
                if entry.span.end_offset > merged.end_offset then
                    merged.end_offset = entry.span.end_offset
                    merged.end_line = entry.span.end_line
                    merged.end_col = entry.span.end_col
                end
            end
        end
    end
    return merged
end

return M
