local pvm = require("moonlift.pvm")

local M = {}
local Server = {}
Server.__index = Server

local JSON_NULL = {}
M.JSON_NULL = JSON_NULL

local function is_array(t)
    local n = 0
    for k in pairs(t) do if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false, 0 end; if k > n then n = k end end
    for i = 1, n do if t[i] == nil then return false, 0 end end
    return true, n
end
local esc = { ["\\"] = "\\\\", ["\""] = "\\\"", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function enc_string(s) return '"' .. s:gsub('[%z\1-\31\\"]', function(c) return esc[c] or string.format("\\u%04X", c:byte()) end) .. '"' end
function M.json_encode(v)
    if v == JSON_NULL or v == nil then return "null" end
    local tv = type(v)
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then return tostring(v) end
    if tv == "string" then return enc_string(v) end
    if tv == "table" then
        local arr, n = is_array(v)
        local out = {}
        if arr then for i = 1, n do out[i] = M.json_encode(v[i]) end; return "[" .. table.concat(out, ",") .. "]" end
        local keys = {}; for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end; table.sort(keys)
        for i = 1, #keys do local k = keys[i]; out[i] = enc_string(k) .. ":" .. M.json_encode(v[k]) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    error("json encode unsupported " .. tv)
end

local function utf8_cp(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end
function M.json_decode(s)
    local i, n = 1, #s
    local function err(m) error("json decode at " .. i .. ": " .. m, 2) end
    local function ws() while i <= n and (s:byte(i) == 32 or s:byte(i) == 9 or s:byte(i) == 10 or s:byte(i) == 13) do i = i + 1 end end
    local parse
    local function str()
        i = i + 1; local out = {}
        while i <= n do
            local b = s:byte(i)
            if b == 34 then i = i + 1; return table.concat(out) end
            if b == 92 then
                local e = s:sub(i + 1, i + 1)
                if e == '"' or e == "\\" or e == "/" then out[#out + 1] = e; i = i + 2
                elseif e == "b" then out[#out + 1] = "\b"; i = i + 2
                elseif e == "f" then out[#out + 1] = "\f"; i = i + 2
                elseif e == "n" then out[#out + 1] = "\n"; i = i + 2
                elseif e == "r" then out[#out + 1] = "\r"; i = i + 2
                elseif e == "t" then out[#out + 1] = "\t"; i = i + 2
                elseif e == "u" then local cp = tonumber(s:sub(i + 2, i + 5), 16) or 0; out[#out + 1] = utf8_cp(cp); i = i + 6
                else err("bad escape") end
            else out[#out + 1] = string.char(b); i = i + 1 end
        end
        err("unterminated string")
    end
    local function num()
        local st = i
        if s:sub(i, i) == "-" then i = i + 1 end
        while s:sub(i, i):match("%d") do i = i + 1 end
        if s:sub(i, i) == "." then i = i + 1; while s:sub(i, i):match("%d") do i = i + 1 end end
        local c = s:sub(i, i); if c == "e" or c == "E" then i = i + 1; c = s:sub(i, i); if c == "+" or c == "-" then i = i + 1 end; while s:sub(i, i):match("%d") do i = i + 1 end end
        return tonumber(s:sub(st, i - 1))
    end
    local function arr()
        i = i + 1; ws(); local out = {}; if s:sub(i, i) == "]" then i = i + 1; return out end
        while true do out[#out + 1] = parse(); ws(); local c = s:sub(i, i); if c == "]" then i = i + 1; return out end; if c ~= "," then err("expected , or ]") end; i = i + 1 end
    end
    local function obj()
        i = i + 1; ws(); local out = {}; if s:sub(i, i) == "}" then i = i + 1; return out end
        while true do ws(); if s:sub(i, i) ~= '"' then err("expected string key") end; local k = str(); ws(); if s:sub(i, i) ~= ":" then err("expected :") end; i = i + 1; out[k] = parse(); ws(); local c = s:sub(i, i); if c == "}" then i = i + 1; return out end; if c ~= "," then err("expected , or }") end; i = i + 1 end
    end
    function parse()
        ws(); local c = s:sub(i, i)
        if c == '"' then return str() end
        if c == "{" then return obj() end
        if c == "[" then return arr() end
        if c == "t" and s:sub(i, i + 3) == "true" then i = i + 4; return true end
        if c == "f" and s:sub(i, i + 4) == "false" then i = i + 5; return false end
        if c == "n" and s:sub(i, i + 3) == "null" then i = i + 4; return JSON_NULL end
        return num()
    end
    local v = parse(); ws(); return v
end

local function lsp_pos(pos) return { line = pos.line, character = pos.character } end
local function lsp_range(r) return { start = lsp_pos(r.start), ["end"] = lsp_pos(r.stop) } end
local function severity(d)
    local L = d and pvm.classof(d.severity) and tostring(d.severity) or ""
    if L:match("DiagError") then return 1 elseif L:match("DiagWarning") then return 2 elseif L:match("DiagInfo") then return 3 end
    return 4
end
local symbol_kind_num = { SymFile = 1, SymModule = 2, SymStruct = 23, SymField = 8, SymFunction = 12, SymProperty = 7, SymVariable = 13 }
local function sym_kind(k) return symbol_kind_num[tostring(k):match("%.([_%w]+)$") or tostring(k)] or 13 end

local function diag_json(d) return { range = lsp_range(d.range), severity = severity(d), source = d.source, message = d.message } end
local function symbol_json(s)
    local children = {}
    for i = 1, #s.children do children[i] = symbol_json(s.children[i]) end
    return { name = s.name, kind = sym_kind(s.kind), range = lsp_range(s.range), selectionRange = lsp_range(s.selection_range), children = children }
end
local function completion_json(c) return { label = c.label, kind = c.kind, detail = c.detail, insertText = c.insert_text } end

local function doc_uri(params) return params and params.textDocument and params.textDocument.uri end
local function doc_version(params) return params and params.textDocument and params.textDocument.version or 0 end
local function doc_text(params)
    if params and params.textDocument and params.textDocument.text then return params.textDocument.text end
    local changes = params and params.contentChanges
    if type(changes) == "table" and #changes > 0 then return changes[#changes].text end
    return nil
end

function M.new(opts)
    opts = opts or {}
    local p = require("moonlift.pvm")
    local T = require("moonlift.lsp_asdl").context()
    return setmetatable({ T = T, L = T.MoonliftLsp, docs = {}, diag = require("moonlift.lsp_diagnostics").Define(T), symbols = require("moonlift.lsp_symbols").Define(T), hover = require("moonlift.lsp_hover").Define(T), completion = require("moonlift.lsp_completion").Define(T) }, Server)
end

function Server:document(uri) return self.docs[uri] end
function Server:set_document(uri, version, text) local d = self.L.Document(uri, version or 0, text or ""); self.docs[uri] = d; return d end
function Server:diagnostics(uri)
    local doc = self.docs[uri]
    if not doc then return {} end
    local ds = self.diag.diagnostics(doc); local out = {}; for i = 1, #ds do out[i] = diag_json(ds[i]) end; return out
end
function Server:publish_diagnostics(uri) return { jsonrpc = "2.0", method = "textDocument/publishDiagnostics", params = { uri = uri, diagnostics = self:diagnostics(uri) } } end

function Server:handle(req)
    local method, params, id = req.method, req.params or {}, req.id
    if method == "initialize" then
        return { jsonrpc = "2.0", id = id, result = { serverInfo = { name = "moonlift-lsp", version = "0.1" }, capabilities = { positionEncoding = "utf-16", textDocumentSync = { openClose = true, change = 1 }, hoverProvider = true, documentSymbolProvider = true, completionProvider = { triggerCharacters = { ":", "(", " ", "." } } } } }
    elseif method == "initialized" then return nil
    elseif method == "shutdown" then return { jsonrpc = "2.0", id = id, result = JSON_NULL }
    elseif method == "exit" then os.exit(0)
    elseif method == "textDocument/didOpen" then local uri = doc_uri(params); self:set_document(uri, doc_version(params), doc_text(params)); return self:publish_diagnostics(uri)
    elseif method == "textDocument/didChange" then local uri = doc_uri(params); self:set_document(uri, doc_version(params), doc_text(params) or (self.docs[uri] and self.docs[uri].text) or ""); return self:publish_diagnostics(uri)
    elseif method == "textDocument/didClose" then local uri = doc_uri(params); self.docs[uri] = nil; return { jsonrpc = "2.0", method = "textDocument/publishDiagnostics", params = { uri = uri, diagnostics = {} } }
    elseif method == "textDocument/documentSymbol" then local doc = self.docs[doc_uri(params)]; local out = {}; if doc then local syms = self.symbols.symbols(doc); for i = 1, #syms do out[i] = symbol_json(syms[i]) end end; return { jsonrpc = "2.0", id = id, result = out }
    elseif method == "textDocument/hover" then local doc = self.docs[doc_uri(params)]; local h = doc and self.hover.hover(doc, self.L.Position(params.position.line or 0, params.position.character or 0)); return { jsonrpc = "2.0", id = id, result = h and { contents = { kind = "markdown", value = h.markdown }, range = lsp_range(h.range) } or JSON_NULL }
    elseif method == "textDocument/completion" then local doc = self.docs[doc_uri(params)]; local out = {}; if doc then local cs = self.completion.complete(doc, self.L.Position(params.position.line or 0, params.position.character or 0)); for i = 1, #cs do out[i] = completion_json(cs[i]) end end; return { jsonrpc = "2.0", id = id, result = { isIncomplete = false, items = out } }
    end
    if id ~= nil then return { jsonrpc = "2.0", id = id, error = { code = -32601, message = "method not found" } } end
    return nil
end

local function read_message(input)
    local len
    while true do
        local line = input:read("*l")
        if not line then return nil end
        if line == "" or line == "\r" then break end
        local n = line:match("^[Cc]ontent%-[Ll]ength:%s*(%d+)")
        if n then len = tonumber(n) end
    end
    if not len then return nil end
    return input:read(len)
end
local function write_message(output, obj)
    if not obj then return end
    local body = M.json_encode(obj)
    output:write("Content-Length: " .. tostring(#body) .. "\r\n\r\n" .. body)
    output:flush()
end
function Server:run_stdio(input, output)
    input, output = input or io.stdin, output or io.stdout
    while true do
        local body = read_message(input)
        if not body then break end
        local ok, req = pcall(M.json_decode, body)
        local resp = ok and self:handle(req) or { jsonrpc = "2.0", id = JSON_NULL, error = { code = -32700, message = tostring(req) } }
        write_message(output, resp)
    end
end

return M
