local M = {}

local function pct_decode(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function pct_encode_path(path)
    return (tostring(path):gsub("[^A-Za-z0-9%-%._~/]", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

function M.uri_text(uri)
    return type(uri) == "table" and uri.text or tostring(uri or "")
end

function M.uri_to_path(uri)
    local text = M.uri_text(uri)
    local path = text:match("^file://(.*)$")
    if not path then return nil end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return pct_decode(path)
end

function M.path_to_uri(path)
    return "file://" .. pct_encode_path(path)
end

function M.same_uri(a, b)
    return M.uri_text(a) == M.uri_text(b)
end

return M
