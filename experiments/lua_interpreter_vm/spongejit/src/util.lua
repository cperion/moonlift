-- util.lua
-- Shared helpers for the Lua VM JIT harness.

local M = {}

local cjson = require("cjson")
if cjson.encode_keep_buffer then cjson.encode_keep_buffer(false) end
if cjson.encode_empty_table_as_object then cjson.encode_empty_table_as_object(false) end

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
        local u = tonumber(bit.band(h, 0xffffffff))
        if u < 0 then u = u + 4294967296 end
        return string.format("%08x", u)
    end
    local h = 2166136261
    for i = 1, #text do
        -- djb2 fallback for non-LuaJIT runtimes without bit ops.
        h = (h * 33 + text:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

local function sorted_keys(t)
    local keys = {}
    for k, _ in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function M.write_json(path, value)
    M.mkdir_p(M.dirname(path))
    return M.write_file(path, cjson.encode(value) .. "\n")
end

function M.write_jsonl(path, rows)
    M.mkdir_p(M.dirname(path))
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    for _, row in ipairs(rows or {}) do
        f:write(cjson.encode(row), "\n")
    end
    f:close()
    return true
end

function M.json_decode(text)
    return cjson.decode(text)
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
