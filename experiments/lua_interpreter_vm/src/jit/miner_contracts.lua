-- Lua VM JIT stencil-miner contracts.
--
-- This module is intentionally plain Lua.  It defines the products exchanged by
-- the empirical stencil miner before any candidate is promoted into the real
-- copy-and-patch stencil library.

local M = {}

local function copy_list(xs)
    local out = {}
    if xs then for i, v in ipairs(xs) do out[i] = v end end
    return out
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function stable_value(v)
    local tv = type(v)
    if tv == "table" then
        local parts = {}
        if #v > 0 then
            for i = 1, #v do parts[#parts + 1] = stable_value(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for _, k in ipairs(sorted_keys(v)) do
            parts[#parts + 1] = tostring(k) .. "=" .. stable_value(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

function M.StateOp(op, args)
    assert(type(op) == "string" and op ~= "", "StateOp requires op name")
    return { kind = "StateOp", op = op, args = args or {} }
end

function M.StatePattern(spec)
    assert(type(spec) == "table", "StatePattern spec table required")
    assert(type(spec.name) == "string" and spec.name ~= "", "StatePattern.name required")
    local ops = assert(spec.ops, "StatePattern.ops required")
    local p = {
        kind = "StatePattern",
        name = spec.name,
        class = spec.class or "unknown",
        ops = copy_list(ops),
        effects = copy_list(spec.effects),
        exits = copy_list(spec.exits),
        projections = copy_list(spec.projections),
        notes = spec.notes or "",
    }
    p.canonical_key = M.canonical_pattern_key(p)
    return p
end

function M.canonical_pattern_key(pattern)
    local parts = { pattern.class or "unknown" }
    for _, op in ipairs(pattern.ops or {}) do
        parts[#parts + 1] = op.op .. stable_value(op.args or {})
    end
    if pattern.effects and #pattern.effects > 0 then
        parts[#parts + 1] = "effects=" .. table.concat(pattern.effects, ",")
    end
    if pattern.exits and #pattern.exits > 0 then
        parts[#parts + 1] = "exits=" .. table.concat(pattern.exits, ",")
    end
    if pattern.projections and #pattern.projections > 0 then
        parts[#parts + 1] = "projections=" .. table.concat(pattern.projections, ",")
    end
    return table.concat(parts, "|")
end

function M.HoleMarker(spec)
    assert(type(spec) == "table", "HoleMarker spec table required")
    assert(type(spec.name) == "string" and spec.name ~= "", "HoleMarker.name required")
    assert(type(spec.kind) == "string" and spec.kind ~= "", "HoleMarker.kind required")
    return {
        kind = "HoleMarker",
        name = spec.name,
        hole_kind = spec.kind,
        width = assert(spec.width, "HoleMarker.width required"),
        bytes = assert(spec.bytes, "HoleMarker.bytes required"),
        required = spec.required ~= false,
        note = spec.note or "",
    }
end

function M.RelocMarker(spec)
    assert(type(spec) == "table", "RelocMarker spec table required")
    assert(type(spec.name) == "string" and spec.name ~= "", "RelocMarker.name required")
    assert(type(spec.symbol) == "string" and spec.symbol ~= "", "RelocMarker.symbol required")
    return {
        kind = "RelocMarker",
        name = spec.name,
        reloc_kind = spec.kind or "extern",
        symbol = spec.symbol,
        required = spec.required ~= false,
        note = spec.note or "",
    }
end

function M.StencilCandidate(spec)
    assert(type(spec) == "table", "StencilCandidate spec table required")
    assert(type(spec.name) == "string" and spec.name ~= "", "StencilCandidate.name required")
    assert(type(spec.pattern) == "table" and spec.pattern.kind == "StatePattern", "StencilCandidate.pattern required")
    return {
        kind = "StencilCandidate",
        name = spec.name,
        class = spec.class or spec.pattern.class,
        implements = spec.implements,
        pattern = spec.pattern,
        config_axes = copy_list(spec.config_axes),
        holes = copy_list(spec.holes),
        relocs = copy_list(spec.relocs),
        source = assert(spec.source, "StencilCandidate.source required"),
        note = spec.note or "",
    }
end

function M.CandidateScore(spec)
    return {
        kind = "CandidateScore",
        size = spec.size or 0,
        instruction_count = spec.instruction_count or 0,
        expected_holes = spec.expected_holes or 0,
        found_holes = spec.found_holes or 0,
        expected_relocs = spec.expected_relocs or 0,
        found_relocs = spec.found_relocs or 0,
        missing_holes = copy_list(spec.missing_holes),
        missing_relocs = copy_list(spec.missing_relocs),
        status = spec.status or "unknown",
    }
end

function M.CandidateManifest(spec)
    return {
        kind = "CandidateManifest",
        version = 1,
        generated_at = spec.generated_at or os.date("!%Y-%m-%dT%H:%M:%SZ"),
        target = spec.target or "unknown",
        source_path = spec.source_path,
        object_path = spec.object_path,
        asm_path = spec.asm_path,
        candidates = copy_list(spec.candidates),
    }
end

local function json_escape(s)
    s = tostring(s)
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\b', '\\b'):gsub('\f', '\\f')
    s = s:gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. s .. '"'
end

local function is_array(t)
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    end
    return true
end

local function encode_json(v, indent)
    indent = indent or ""
    local tv = type(v)
    if tv == "nil" then return "null" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then return tostring(v) end
    if tv == "string" then return json_escape(v) end
    if tv ~= "table" then return json_escape(tostring(v)) end

    local next_indent = indent .. "  "
    local parts = {}
    if is_array(v) then
        if #v == 0 then return "[]" end
        for i = 1, #v do parts[#parts + 1] = next_indent .. encode_json(v[i], next_indent) end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end

    local keys = sorted_keys(v)
    if #keys == 0 then return "{}" end
    for _, k in ipairs(keys) do
        parts[#parts + 1] = next_indent .. json_escape(k) .. ": " .. encode_json(v[k], next_indent)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

M.encode_json = encode_json

function M.validate_manifest(manifest)
    local errors = {}
    if type(manifest) ~= "table" or manifest.kind ~= "CandidateManifest" then
        errors[#errors + 1] = "manifest kind must be CandidateManifest"
        return false, errors
    end
    local names = {}
    for i, c in ipairs(manifest.candidates or {}) do
        if not c.name then errors[#errors + 1] = "candidate " .. i .. " missing name" end
        if c.name and names[c.name] then errors[#errors + 1] = "duplicate candidate " .. c.name end
        names[c.name] = true
        if not c.pattern_key then errors[#errors + 1] = "candidate " .. tostring(c.name) .. " missing pattern_key" end
        if not c.extracted then errors[#errors + 1] = "candidate " .. tostring(c.name) .. " missing extracted data" end
        if not c.score then errors[#errors + 1] = "candidate " .. tostring(c.name) .. " missing score" end
    end
    return #errors == 0, errors
end

return M
