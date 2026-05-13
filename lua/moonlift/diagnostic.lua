-- moonlift/diagnostic.lua
-- Structured diagnostics for Moonlift runtime/compiler phases.

local M = {}

local MT = {}
MT.__index = MT

local function copy_into(dst, src)
    if not src then return dst end
    for k, v in pairs(src) do
        if v ~= nil then dst[k] = v end
    end
    return dst
end

function M.new(fields)
    local d = copy_into({ __moonlift_diagnostic = true }, fields or {})
    return setmetatable(d, MT)
end

function M.is(v)
    return type(v) == "table" and v.__moonlift_diagnostic == true
end

function M.copy(diag, patch)
    if not M.is(diag) then return M.new(patch) end
    local out = {}
    copy_into(out, diag)
    copy_into(out, patch)
    out.__moonlift_diagnostic = true
    return setmetatable(out, MT)
end

function M.split_generated_source(err)
    local s = tostring(err)
    local marker = "\n--- generated source ---\n"
    local at = s:find(marker, 1, true)
    if not at then return s, nil end
    return s:sub(1, at - 1), s:sub(at + #marker)
end

function M.extract_lua_line(err)
    local first = tostring(err):match("([^\n]+)") or tostring(err)
    local ln = first:match(":(%d+):")
    return ln and tonumber(ln) or nil
end

function M.trim_lua_prefix(message)
    local first = tostring(message):match("([^\n]+)") or tostring(message)
    return first:gsub("^.-:%d+:%s*", "")
end

function M.detect_hint(message)
    local m = tostring(message)
    if m:find("more than 200 local variables", 1, true) then
        return "Lua/LuaJIT hard-limit: one function body cannot exceed 200 locals. Split large constant tables into sub-tables or move data to runtime arrays/files."
    end
    if m:find("function arguments expected near", 1, true) then
        return "Likely generated Lua syntax drift. Check the mapped source line and island boundary around this location."
    end
    if m:find("unexpected symbol near", 1, true) then
        return "Lua parser rejected generated carrier code. Check nearby .mlua syntax and inserted island expansion output."
    end
    if m:find("'=' expected near", 1, true) then
        return "Carrier Lua saw island syntax in plain Lua context. Check island start position and surrounding Lua syntax."
    end
    if m:match("^expected token %d+") then
        return "Moonlift parser expected a different token at this location. Check island syntax around the highlighted line."
    end
    return nil
end

function M.write_temp_generated(content)
    local path = os.tmpname()
    local f = io.open(path, "wb")
    if not f then return nil end
    f:write(content or "")
    f:close()
    return path
end

function M.from_error(err, defaults)
    if M.is(err) then
        local out = M.copy(err)
        for k, v in pairs(defaults or {}) do
            if out[k] == nil then out[k] = v end
        end
        return out
    end
    local raw, generated_src = M.split_generated_source(err)
    local message = M.trim_lua_prefix(raw)
    local d = M.new(defaults)
    d.raw = tostring(raw)
    d.message = d.message or message
    d.generated_line = d.generated_line or M.extract_lua_line(raw)
    d.generated_source = d.generated_source or generated_src
    d.hint = d.hint or M.detect_hint(d.message)
    return d
end

function M.render(diag)
    if not M.is(diag) then
        diag = M.from_error(diag, { phase = "unknown" })
    end

    local out = {}
    out[#out + 1] = "Moonlift error"
    out[#out + 1] = "phase: " .. tostring(diag.phase or "unknown")
    if diag.envelope_phase then out[#out + 1] = "phase_envelope: " .. tostring(diag.envelope_phase) end
    if diag.file then out[#out + 1] = "file: " .. tostring(diag.file) end
    if diag.island_index then
        out[#out + 1] = string.format("island: #%d%s", diag.island_index,
            diag.island_kind and (" (" .. tostring(diag.island_kind) .. ")") or "")
    end
    if diag.generated_line then out[#out + 1] = "generated_line: " .. tostring(diag.generated_line) end
    if diag.src_line then
        out[#out + 1] = string.format("source: %s:%d:%d", tostring(diag.file or "<source>"), diag.src_line, diag.src_col or 1)
    elseif diag.generated_line then
        out[#out + 1] = "source: <unmapped generated line>"
    end
    out[#out + 1] = "message: " .. tostring(diag.message or "")
    if diag.hint then out[#out + 1] = "hint: " .. tostring(diag.hint) end
    if diag.generated_path then out[#out + 1] = "generated_lua: " .. tostring(diag.generated_path) end
    if diag.snippet then
        out[#out + 1] = "snippet:"
        out[#out + 1] = diag.snippet
    end
    return table.concat(out, "\n")
end

function M.raise(diag, level)
    error(M.is(diag) and diag or M.new(diag), level or 1)
end

function MT:__tostring()
    return M.render(self)
end

return M
