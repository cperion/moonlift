-- moonlift/dap_breakpoint_resolver.lua
-- Maps DAP source-line breakpoints to Moonlift block label names.
-- Uses the anchor index (AnchorContinuationName anchors) to find
-- which block label corresponds to a given source line.
--
-- Defines via bind_context(T) pattern to access MoonSource schema types.

local pvm = require("moonlift.pvm")

local function bind_context(T)
    local S = T.MoonSource
    local PositionIndex = require("moonlift.source_position_index")(T)
    local AnchorIndex = require("moonlift.source_anchor_index")(T)

    --- Resolve a source line to block label anchors.
    -- For DAP setBreakpoints: given a document URI and line number,
    -- find the AnchorContinuationName anchors at that line.
    --
    -- @param doc_uri  string — document URI
    -- @param line  number — 0-based line number (LSP convention)
    -- @param source_text  string — document source text
    -- @param anchor_set  AnchorSet — anchors from the analysis context
    -- @return array of {block_label, source_range}
    local function resolve_line(doc_uri, line, source_text, anchor_set)
        local document = S.DocumentSnapshot(
            S.DocUri(doc_uri), S.DocVersion(1), S.LangMoonlift, source_text)
        local pos_index = PositionIndex.build_index(document)
        local anchor_index = AnchorIndex.build_index(anchor_set)

        -- Convert line number to byte offset range (one-line span)
        local line_start = PositionIndex.byte_offset_at_byte_col(pos_index, line, 0)
        if pvm.classof(line_start) ~= S.SourceOffsetHit then
            return {}
        end
        local start_offset = line_start.offset
        local line_span = pos_index.lines[line + 1]
        if not line_span then return {} end
        local end_offset = line_span.next_offset

        -- Build a SourceRange for the line
        local line_range = S.SourceRange(
            S.DocUri(doc_uri), start_offset, end_offset,
            S.SourcePos(line, 0, 0),
            S.SourcePos(line, math.max(1, end_offset - start_offset), 0))

        -- Query anchors at this line's byte range
        local lookup = AnchorIndex.lookup_by_range(anchor_index, line_range)

        -- Filter for AnchorContinuationName anchors
        local results = {}
        for _, anchor in ipairs(lookup.anchors) do
            if anchor.kind == S.AnchorContinuationName then
                results[#results + 1] = {
                    block_label = anchor.label,
                    source_range = anchor.range,
                }
            end
        end
        return results
    end

    --- Reverse map: given a block label, find its source range.
    -- Used by DAP stackTrace to highlight the current block.
    --
    -- @param block_label  string
    -- @param anchor_set  AnchorSet
    -- @return SourceRange or nil
    local function resolve_block_label(block_label, anchor_set)
        local anchor_index = AnchorIndex.build_index(anchor_set)
        for _, anchor in ipairs(anchor_index.anchors) do
            if anchor.kind == S.AnchorContinuationName
               and anchor.label == block_label then
                return anchor.range
            end
        end
        return nil
    end

    return {
        resolve_line = resolve_line,
        resolve_block_label = resolve_block_label,
    }
end

return bind_context