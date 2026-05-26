-- object_mine.lua
-- Mines machine code bytes, holes, relocations, body ranges, and clobbers
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.12

local M = {}
local util = require("tools.jit_harness.util")

-- Mine a compiled object file
function M.mine_object(obj, spec, config)
    config = config or {}

    local result = {
        object_id = obj.id,
        symbol = obj.symbol,
        valid = obj.compiled ~= false,
        errors = {},
        object_path = obj.object_path,
    }

    if obj.compiled == false then
        result.valid = false
        table.insert(result.errors, obj.error or "object was not compiled")
        result.body_range = { offset = 0, size = 0 }
        result.holes = {}
        result.relocs = {}
        result.clobbers = { registers = {}, mask = 0 }
        return result
    end

    local bytes, read_err
    if obj.object_path then bytes, read_err = util.read_file(obj.object_path) end
    if not bytes then
        result.valid = false
        table.insert(result.errors, read_err or "object file not readable")
        bytes = ""
    end

    result.body_range = M.find_body_range(obj, obj.symbol, config)
    result.holes = M.find_holes(bytes, spec and spec.hole_markers or {})
    result.relocs = M.normalize_relocs(M.find_relocations(obj, obj.symbol))
    result.clobbers = M.classify_clobbers(obj, result.body_range)
    result.object_size = #bytes
    return result
end

-- Find the body range of a symbol in an object file
function M.find_body_range(obj, symbol, config)
    config = config or {}

    local size = obj.size_bytes or 0
    if obj.object_path then
        local bytes = util.read_file(obj.object_path)
        if bytes then size = #bytes end
    end
    -- Until a full ELF/Mach-O section parser lands, the safe mined range is the
    -- object payload as an opaque artifact. This is deterministic and explicit.
    return { symbol = symbol, offset = 0, size = size }
end

-- Find hole markers in compiled bytes
function M.find_holes(bytes, markers)
    markers = markers or {}

    local holes = {}

    -- Candidate kernels currently do not emit marker payloads. Recognize only
    -- explicit marker strings supplied by the emitter/spec.
    for _, marker in ipairs(markers) do
        local needle = marker.bytes or marker.marker or marker.name
        if needle and bytes then
            local start = 1
            while true do
                local i = bytes:find(needle, start, true)
                if not i then break end
                table.insert(holes, { offset = i - 1, size = #needle, kind = marker.kind or "marker", name = marker.name })
                start = i + 1
            end
        end
    end
    return holes
end

-- Find relocations in compiled object
function M.find_relocations(obj, symbol)
    local relocs = {}
    if not obj.object_path then return relocs end
    local cmd = "objdump -r " .. util.shell_quote(obj.object_path)
    local ok, out = util.run_capture(cmd)
    if not ok then return relocs end
    for line in out:gmatch("[^\n]+") do
        local off, kind, sym = line:match("^%s*([0-9a-fA-F]+)%s+([%w_%-]+)%s+(.+)$")
        if off and kind and sym then
            table.insert(relocs, { offset = tonumber(off, 16) or 0, kind = kind, symbol = sym:gsub("%s+$", "") })
        end
    end
    return relocs
end

-- Classify clobber set (registers written by stencil)
function M.classify_clobbers(obj, body)
    -- Unknown until instruction analysis lands. Empty means "not classified",
    -- not "preserves all"; verification/export keep that distinction via mask=0.
    return { registers = {}, mask = 0, classified = false }
end

-- Normalize relocations to canonical form
function M.normalize_relocs(relocs)
    local normalized = {}

    for _, reloc in ipairs(relocs) do
        table.insert(normalized, {
            offset = reloc.offset,
            kind = reloc.kind,
            symbol = reloc.symbol,
        })
    end

    table.sort(normalized, function(a, b) return a.offset < b.offset end)

    return normalized
end

-- Report mining results
function M.report_mining(result)
    print("\n=== Object Mining ===")
    print(string.format("Object: %s", result.object_id or "unknown"))
    print(string.format("Symbol: %s", result.symbol or "unknown"))

    if result.body_range then
        print(string.format("Body range: offset=%d, size=%d",
            result.body_range.offset, result.body_range.size))
    end

    if result.holes then
        print(string.format("Holes found: %d", #result.holes))
    end

    if result.relocs then
        print(string.format("Relocations: %d", #result.relocs))
    end

    if result.clobbers then
        print(string.format("Clobbered registers: %d", #result.clobbers))
    end
end

return M
