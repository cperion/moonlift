local Decode = require("moonlift.rpc_json_decode")

local M = {}
M.JSON_NULL = Decode.JSON_NULL

local ESC = { ['\\'] = '\\\\', ['"'] = '\\"', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encode_string(s)
    return '"' .. tostring(s):gsub('[%z\1-\31\\"]', function(ch)
        return ESC[ch] or string.format("\\u%04X", ch:byte())
    end) .. '"'
end

local function is_array(t)
    local n = 0
    for k in pairs(t) do if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end; if k > n then n = k end end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

local function encode_lua(v)
    if v == M.JSON_NULL or v == nil then return "null" end
    local tv = type(v)
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then return tostring(v) end
    if tv == "string" then return encode_string(v) end
    if tv == "table" then
        local arr, n = is_array(v)
        local parts = {}
        if arr then
            for i = 1, n do parts[i] = encode_lua(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        for i = 1, #keys do
            local k = keys[i]
            parts[i] = encode_string(k) .. ":" .. encode_lua(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("json encode: unsupported " .. tv, 2)
end

function M.Define(T)
    local DecodeT = Decode.Define(T)
    return {
        JSON_NULL = M.JSON_NULL,
        encode_lua = encode_lua,
        value_to_lua = DecodeT.value_to_lua,
    }
end

M.encode_lua = encode_lua
return M
