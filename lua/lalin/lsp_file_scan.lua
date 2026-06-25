local Uri = require("lalin.lsp_uri")

local M = {}

local ignored_dirs = {
    [".git"] = true,
    [".hg"] = true,
    [".svn"] = true,
    ["target"] = true,
    ["node_modules"] = true,
    [".direnv"] = true,
    [".cache"] = true,
}

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function should_keep(path, max_bytes)
    local f = io.open(path, "rb")
    if not f then return false end
    local size = f:seek("end") or 0
    f:close()
    return size <= max_bytes
end

local function find_command(root)
    local parts = { "find ", shell_quote(root), " -type d \\( " }
    local first = true
    for name in pairs(ignored_dirs) do
        if not first then parts[#parts + 1] = " -o " end
        first = false
        parts[#parts + 1] = "-name " .. shell_quote(name)
    end
    parts[#parts + 1] = " \\) -prune -o -type f \\( -name '*.mlua' -o -name '*.mld.lua' \\) -print 2>/dev/null"
    return table.concat(parts)
end

function M.scan(root, opts)
    opts = opts or {}
    local max_files = opts.max_files or 2000
    local max_bytes = opts.max_bytes or 1024 * 1024
    local out = {}
    if not root or root == "" then return out end
    local pipe = io.popen(find_command(root), "r")
    if not pipe then return out end
    for path in pipe:lines() do
        if #out >= max_files then break end
        if should_keep(path, max_bytes) then
            out[#out + 1] = {
                path = path,
                uri = Uri.path_to_uri(path),
            }
        end
    end
    pipe:close()
    table.sort(out, function(a, b) return a.path < b.path end)
    return out
end

return M
