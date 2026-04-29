local M = {}
M.JSON_NULL = {}

local function utf8_cp(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40)) end
    if cp < 0x10000 then return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40)) end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + (math.floor(cp / 0x1000) % 0x40), 0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
end

local function decode_lua(s)
    local i, n = 1, #s
    local function err(msg) error("json decode error at " .. tostring(i) .. ": " .. msg, 0) end
    local function ws() while i <= n and s:sub(i, i):match("[%s]") do i = i + 1 end end
    local parse_value
    local function parse_string()
        i = i + 1
        local out, k = {}, 0
        while i <= n do
            local c = s:byte(i)
            if c == 34 then i = i + 1; return table.concat(out) end
            if c == 92 then
                local e = s:byte(i + 1)
                if not e then err("unfinished escape") end
                if e == 34 then k=k+1; out[k]='"'; i=i+2
                elseif e == 92 then k=k+1; out[k]="\\"; i=i+2
                elseif e == 47 then k=k+1; out[k]="/"; i=i+2
                elseif e == 98 then k=k+1; out[k]="\b"; i=i+2
                elseif e == 102 then k=k+1; out[k]="\f"; i=i+2
                elseif e == 110 then k=k+1; out[k]="\n"; i=i+2
                elseif e == 114 then k=k+1; out[k]="\r"; i=i+2
                elseif e == 116 then k=k+1; out[k]="\t"; i=i+2
                elseif e == 117 then
                    local function hex(pos)
                        local h = s:sub(pos, pos + 3)
                        return h:match("^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") and tonumber(h, 16) or nil
                    end
                    local cp = hex(i + 2)
                    if not cp then err("invalid unicode escape") end
                    local consumed = 6
                    if cp >= 0xD800 and cp <= 0xDBFF and s:byte(i + 6) == 92 and s:byte(i + 7) == 117 then
                        local cp2 = hex(i + 8)
                        if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
                            cp = 0x10000 + ((cp - 0xD800) * 0x400) + (cp2 - 0xDC00)
                            consumed = 12
                        else cp = 0xFFFD end
                    elseif cp >= 0xD800 and cp <= 0xDFFF then cp = 0xFFFD end
                    k=k+1; out[k]=utf8_cp(cp); i=i+consumed
                else err("invalid escape") end
            else
                if c < 32 then err("control character in string") end
                k=k+1; out[k]=string.char(c); i=i+1
            end
        end
        err("unterminated string")
    end
    local function parse_number()
        local start = i
        if s:sub(i,i) == "-" then i=i+1 end
        if s:sub(i,i) == "0" then i=i+1
        elseif s:sub(i,i):match("%d") then while i <= n and s:sub(i,i):match("%d") do i=i+1 end
        else err("invalid number") end
        if s:sub(i,i) == "." then i=i+1; if not s:sub(i,i):match("%d") then err("invalid fraction") end; while i <= n and s:sub(i,i):match("%d") do i=i+1 end end
        local c = s:sub(i,i)
        if c == "e" or c == "E" then i=i+1; c=s:sub(i,i); if c == "+" or c == "-" then i=i+1 end; if not s:sub(i,i):match("%d") then err("invalid exponent") end; while i <= n and s:sub(i,i):match("%d") do i=i+1 end end
        return tonumber(s:sub(start, i - 1))
    end
    local function parse_array()
        i=i+1; ws(); local out={}
        if s:sub(i,i) == "]" then i=i+1; return out end
        while true do
            out[#out+1] = parse_value(); ws()
            local c=s:sub(i,i)
            if c == "]" then i=i+1; return out end
            if c ~= "," then err("expected ',' or ']'") end
            i=i+1; ws()
        end
    end
    local function parse_object()
        i=i+1; ws(); local out={}
        if s:sub(i,i) == "}" then i=i+1; return out end
        while true do
            if s:sub(i,i) ~= '"' then err("expected object key") end
            local key=parse_string(); ws(); if s:sub(i,i) ~= ":" then err("expected ':'") end
            i=i+1; ws(); out[key]=parse_value(); ws()
            local c=s:sub(i,i)
            if c == "}" then i=i+1; return out end
            if c ~= "," then err("expected ',' or '}'") end
            i=i+1; ws()
        end
    end
    function parse_value()
        ws(); local c=s:sub(i,i)
        if c == '"' then return parse_string() end
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == "t" and s:sub(i,i+3)=="true" then i=i+4; return true end
        if c == "f" and s:sub(i,i+4)=="false" then i=i+5; return false end
        if c == "n" and s:sub(i,i+3)=="null" then i=i+4; return M.JSON_NULL end
        if c == "-" or c:match("%d") then return parse_number() end
        err("unexpected value")
    end
    local v=parse_value(); ws(); if i <= n then err("trailing garbage") end
    return v
end

local function is_array(t)
    local n = 0
    for k in pairs(t) do if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end; if k > n then n = k end end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

function M.Define(T)
    local R = T.MoonRpc
    local E = T.MoonEditor

    local function lua_to_value(v)
        local tv = type(v)
        if v == M.JSON_NULL or tv == "nil" then return R.JsonNull end
        if tv == "boolean" then return R.JsonBool(v) end
        if tv == "number" then return R.JsonNumber(tostring(v)) end
        if tv == "string" then return R.JsonString(v) end
        if tv == "table" then
            local arr, n = is_array(v)
            if arr then
                local xs = {}; for i = 1, n do xs[i] = lua_to_value(v[i]) end
                return R.JsonArray(xs)
            end
            local ms = {}
            for k, val in pairs(v) do ms[#ms + 1] = R.JsonMember(k, lua_to_value(val)) end
            table.sort(ms, function(a,b) return a.key < b.key end)
            return R.JsonObject(ms)
        end
        return R.JsonNull
    end

    local function value_to_lua(v)
        local cls = require("moonlift.pvm").classof(v)
        if v == R.JsonNull then return M.JSON_NULL end
        if cls == R.JsonBool then return v.value end
        if cls == R.JsonNumber then return tonumber(v.raw) end
        if cls == R.JsonString then return v.value end
        if cls == R.JsonArray then local out={}; for i=1,#v.values do out[i]=value_to_lua(v.values[i]) end; return out end
        if cls == R.JsonObject then local out={}; for i=1,#v.members do out[v.members[i].key]=value_to_lua(v.members[i].value) end; return out end
        return nil
    end

    local function id_from_lua(v)
        if v == nil or v == M.JSON_NULL then return E.RpcIdNone end
        if type(v) == "number" then return E.RpcIdNumber(v) end
        if type(v) == "string" then return E.RpcIdString(v) end
        return E.RpcIdNone
    end

    local function decode_message(body)
        local ok, msg = pcall(decode_lua, body)
        if not ok then return R.RpcInvalid(msg) end
        if type(msg) ~= "table" then return R.RpcInvalid("JSON-RPC body is not an object") end
        if type(msg.method) ~= "string" then return R.RpcInvalid("missing JSON-RPC method") end
        local params = lua_to_value(msg.params)
        if msg.id ~= nil then return R.RpcRequest(id_from_lua(msg.id), msg.method, params) end
        return R.RpcIncomingNotification(msg.method, params)
    end

    return {
        JSON_NULL = M.JSON_NULL,
        decode_lua = decode_lua,
        lua_to_value = lua_to_value,
        value_to_lua = value_to_lua,
        id_from_lua = id_from_lua,
        decode_message = decode_message,
    }
end

M.decode_lua = decode_lua
return M
