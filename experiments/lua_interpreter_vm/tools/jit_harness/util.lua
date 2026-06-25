-- util.lua
-- Shared helpers for the Lua VM JIT harness.

local M = {}

local bit_ok, bit = pcall(require, "bit")

function M.shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", [['"'"']]) .. "'"
end

function M.path_exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

function M.read_file(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local data = f:read("*a")
    f:close()
    return data
end

function M.write_file(path, data)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    f:write(data or "")
    f:close()
    return true
end

function M.mkdir_p(path)
    if not path or path == "" then return true end
    local cmd = "mkdir -p " .. M.shell_quote(path)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

function M.dirname(path)
    local d = tostring(path):match("^(.*)/[^/]*$")
    if not d or d == "" then return "." end
    return d
end

function M.basename(path)
    return tostring(path):match("([^/]+)$") or tostring(path)
end

function M.abspath(path)
    path = tostring(path or ".")
    if path:sub(1, 1) == "/" then return path end
    local p = io.popen("pwd", "r")
    local cwd = p and p:read("*l") or "."
    if p then p:close() end
    return cwd .. "/" .. path
end

function M.find_repo_root(start)
    local dir = M.abspath(start or ".")
    -- If start is a file-like path, begin at its directory.
    if not M.path_exists(dir .. "/Cargo.toml") and dir:match("%.[%w_]+$") then
        dir = M.dirname(dir)
    end
    for _ = 1, 12 do
        if M.path_exists(dir .. "/Cargo.toml") and M.path_exists(dir .. "/lua/lalin/init.lua") then
            return dir
        end
        local parent = M.dirname(dir)
        if parent == dir then break end
        dir = parent
    end
    return nil
end

function M.stable_hash(text)
    text = tostring(text or "")
    -- 32-bit FNV-1a, returned as hex. LuaJIT bit ops are signed, so normalize.
    if bit_ok then
        local h = 2166136261
        for i = 1, #text do
            h = bit.bxor(h, text:byte(i))
            h = bit.tobit(h * 16777619)
        end
        return string.format("%08x", tonumber(bit.band(h, 0xffffffff)))
    end
    local h = 2166136261
    for i = 1, #text do
        -- djb2 fallback for non-LuaJIT runtimes without bit ops.
        h = (h * 33 + text:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

local function json_escape(s)
    s = tostring(s or "")
    s = s:gsub('\\', '\\\\')
         :gsub('"', '\\"')
         :gsub('\b', '\\b')
         :gsub('\f', '\\f')
         :gsub('\n', '\\n')
         :gsub('\r', '\\r')
         :gsub('\t', '\\t')
    s = s:gsub("[%z\1-\31]", function(c)
        return string.format("\\u%04x", c:byte())
    end)
    return s
end
M.json_escape = json_escape

local function is_array(t)
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false, 0 end
        if k > n then n = k end
    end
    for i = 1, n do
        if t[i] == nil then return false, n end
    end
    return true, n
end

local function sorted_keys(t)
    local keys = {}
    for k, _ in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function M.to_json(value, indent)
    indent = indent or 0
    local tv = type(value)
    if tv == "nil" then return "null" end
    if tv == "boolean" then return value and "true" or "false" end
    if tv == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "null" end
        return tostring(value)
    end
    if tv == "string" then return '"' .. json_escape(value) .. '"' end
    if tv ~= "table" then return '"' .. json_escape(tostring(value)) .. '"' end

    local pad = string.rep("  ", indent)
    local child = string.rep("  ", indent + 1)
    local arr, n = is_array(value)
    if arr then
        if n == 0 then return "[]" end
        local parts = {}
        for i = 1, n do parts[i] = child .. M.to_json(value[i], indent + 1) end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
    end

    local keys = sorted_keys(value)
    if #keys == 0 then return "{}" end
    local parts = {}
    for _, k in ipairs(keys) do
        table.insert(parts, child .. '"' .. json_escape(k) .. '": ' .. M.to_json(value[k], indent + 1))
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
end

function M.write_json(path, value)
    M.mkdir_p(M.dirname(path))
    return M.write_file(path, M.to_json(value, 0) .. "\n")
end

function M.json_decode(text)
    local ok, cjson = pcall(require, "cjson.safe")
    if not ok or not cjson then ok, cjson = pcall(require, "cjson") end
    if ok and cjson and cjson.decode then
        local value, err = cjson.decode(text)
        if value ~= nil then return value end
        return nil, err
    end

    -- Small pure-Lua fallback for harness-generated JSON. lua-cjson is preferred
    -- when available, but the CLI should remain usable in a fresh checkout.
    local i, n = 1, #text
    local parse_value
    local function skip_ws()
        local _, e = text:find("^[%s\r\n\t]*", i)
        i = (e or i - 1) + 1
    end
    local function parse_string()
        if text:sub(i, i) ~= '"' then return nil, "expected string" end
        i = i + 1
        local out = {}
        while i <= n do
            local c = text:sub(i, i)
            if c == '"' then i = i + 1; return table.concat(out) end
            if c == "\\" then
                local e = text:sub(i + 1, i + 1)
                if e == '"' or e == "\\" or e == "/" then table.insert(out, e); i = i + 2
                elseif e == "b" then table.insert(out, "\b"); i = i + 2
                elseif e == "f" then table.insert(out, "\f"); i = i + 2
                elseif e == "n" then table.insert(out, "\n"); i = i + 2
                elseif e == "r" then table.insert(out, "\r"); i = i + 2
                elseif e == "t" then table.insert(out, "\t"); i = i + 2
                elseif e == "u" then
                    local hex = text:sub(i + 2, i + 5)
                    local cp = tonumber(hex, 16) or 63
                    table.insert(out, cp < 128 and string.char(cp) or "?")
                    i = i + 6
                else return nil, "bad escape" end
            else
                table.insert(out, c); i = i + 1
            end
        end
        return nil, "unterminated string"
    end
    local function parse_number()
        local s, e = text:find("^-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
        if not s then return nil, "expected number" end
        local num = tonumber(text:sub(s, e))
        i = e + 1
        return num
    end
    local function parse_array()
        i = i + 1
        local arr = {}
        skip_ws()
        if text:sub(i, i) == "]" then i = i + 1; return arr end
        while true do
            local v, err = parse_value(); if err then return nil, err end
            table.insert(arr, v)
            skip_ws()
            local c = text:sub(i, i)
            if c == "]" then i = i + 1; return arr end
            if c ~= "," then return nil, "expected comma or ]" end
            i = i + 1
        end
    end
    local function parse_object()
        i = i + 1
        local obj = {}
        skip_ws()
        if text:sub(i, i) == "}" then i = i + 1; return obj end
        while true do
            skip_ws()
            local k, err = parse_string(); if err then return nil, err end
            skip_ws()
            if text:sub(i, i) ~= ":" then return nil, "expected colon" end
            i = i + 1
            local v; v, err = parse_value(); if err then return nil, err end
            obj[k] = v
            skip_ws()
            local c = text:sub(i, i)
            if c == "}" then i = i + 1; return obj end
            if c ~= "," then return nil, "expected comma or }" end
            i = i + 1
        end
    end
    function parse_value()
        skip_ws()
        local c = text:sub(i, i)
        if c == '"' then return parse_string() end
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == "-" or c:match("%d") then return parse_number() end
        if text:sub(i, i + 3) == "true" then i = i + 4; return true end
        if text:sub(i, i + 4) == "false" then i = i + 5; return false end
        if text:sub(i, i + 3) == "null" then i = i + 4; return nil end
        return nil, "unexpected JSON token at byte " .. tostring(i)
    end
    local value, err = parse_value()
    if err then return nil, err end
    return value
end

function M.read_json(path)
    local text, err = M.read_file(path)
    if not text then return nil, err end
    return M.json_decode(text)
end

function M.run_capture(command)
    local p = io.popen(command .. " 2>&1", "r")
    if not p then return false, "", "popen failed" end
    local out = p:read("*a")
    local ok, why, code = p:close()
    local success = ok == true or ok == 0
    return success, out, why, code
end

function M.sorted_pairs(t)
    local keys = sorted_keys(t)
    local i = 0
    return function()
        i = i + 1
        local k = keys[i]
        if k ~= nil then return k, t[k] end
    end
end

return M
