package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local JsonEncode = require("moonlift.rpc_json_encode")
local JsonDecode = require("moonlift.rpc_json_decode")
local Loop = require("moonlift.rpc_stdio_loop")

local function frame(msg)
    local body = JsonEncode.encode_lua(msg)
    return "Content-Length: " .. #body .. "\r\n\r\n" .. body
end

local Input = {}; Input.__index = Input
function Input.new(s) return setmetatable({ s = s, i = 1 }, Input) end
function Input:read(arg)
    if self.i > #self.s then return nil end
    if arg == "*l" then
        local j = self.s:find("\n", self.i, true)
        if not j then local out = self.s:sub(self.i); self.i = #self.s + 1; return out end
        local out = self.s:sub(self.i, j - 1); self.i = j + 1; return out
    elseif type(arg) == "number" then
        local out = self.s:sub(self.i, self.i + arg - 1); self.i = self.i + #out; return out
    end
end
local Output = {}; Output.__index = Output
function Output.new() return setmetatable({ parts = {} }, Output) end
function Output:write(...) for i = 1, select("#", ...) do self.parts[#self.parts + 1] = tostring(select(i, ...)) end end
function Output:flush() end
function Output:text() return table.concat(self.parts) end

local uri = "file:///tmp/nav.mlua"
local src = "struct User\n  id: i32\n  active: bool32\nend\nexpose Users: view(User)\nfunc User:is_active(self: ptr(User)) -> bool\n  return true\nend\nfunc count_to(n: i32) -> i32\n    return block loop(i: i32 = 0) -> i32\n        if i >= n then yield i end\n        jump loop(i = i + 1)\n    end\nend\n"
local function pos_of(needle, nth)
    nth = nth or 1
    local start, s = 1, nil
    for _ = 1, nth do s = assert(src:find(needle, start, true)); start = s + #needle end
    local prefix = src:sub(1, s - 1)
    local line = select(2, prefix:gsub("\n", ""))
    local last = prefix:match(".*\n()") or 1
    return { line = line, character = s - last }
end
local input = table.concat({
    frame({ jsonrpc = "2.0", id = 1, method = "initialize", params = {} }),
    frame({ jsonrpc = "2.0", method = "textDocument/didOpen", params = { textDocument = { uri = uri, languageId = "mlua", version = 1, text = src } } }),
    frame({ jsonrpc = "2.0", id = 2, method = "textDocument/definition", params = { textDocument = { uri = uri }, position = pos_of("User", 3) } }),
    frame({ jsonrpc = "2.0", id = 3, method = "textDocument/references", params = { textDocument = { uri = uri }, position = pos_of("User", 1), context = { includeDeclaration = true } } }),
    frame({ jsonrpc = "2.0", id = 4, method = "textDocument/semanticTokens/full", params = { textDocument = { uri = uri } } }),
    frame({ jsonrpc = "2.0", id = 5, method = "textDocument/documentHighlight", params = { textDocument = { uri = uri }, position = pos_of("User", 1) } }),
    frame({ jsonrpc = "2.0", id = 6, method = "textDocument/prepareRename", params = { textDocument = { uri = uri }, position = pos_of("User", 3) } }),
    frame({ jsonrpc = "2.0", id = 7, method = "textDocument/rename", params = { textDocument = { uri = uri }, position = pos_of("User", 1), newName = "Person" } }),
    frame({ jsonrpc = "2.0", id = 8, method = "workspace/symbol", params = { query = "User" } }),
    frame({ jsonrpc = "2.0", id = 9, method = "textDocument/definition", params = { textDocument = { uri = uri }, position = pos_of("loop", 2) } }),
    frame({ jsonrpc = "2.0", id = 10, method = "textDocument/references", params = { textDocument = { uri = uri }, position = pos_of("loop", 1), context = { includeDeclaration = true } } }),
    frame({ jsonrpc = "2.0", id = 11, method = "shutdown", params = {} }),
    frame({ jsonrpc = "2.0", method = "exit", params = {} }),
})
local out = Output.new()
Loop.run({ input = Input.new(input), output = out, err = Output.new() })

local function decode_frames(s)
    local msgs, i = {}, 1
    while i <= #s do
        local h = s:find("\r\n\r\n", i, true); if not h then break end
        local len = tonumber(s:sub(i, h - 1):match("Content%-Length:%s*(%d+)")); assert(len)
        local b = s:sub(h + 4, h + 3 + len)
        msgs[#msgs + 1] = JsonDecode.decode_lua(b)
        i = h + 4 + len
    end
    return msgs
end
local msgs = decode_frames(out:text())
local by_id = {}
for i = 1, #msgs do if msgs[i].id then by_id[msgs[i].id] = msgs[i] end end
assert(#by_id[2].result >= 1)
assert(#by_id[3].result >= 3)
assert(#by_id[4].result.data > 0 and #by_id[4].result.data % 5 == 0)
assert(#by_id[5].result >= 3)
assert(by_id[5].result[1].kind == 1)
assert(by_id[6].result.placeholder == "User")
assert(by_id[6].result.range.start.line == 4)
local changes = by_id[7].result.changes[uri]
assert(#changes >= 3)
assert(changes[1].newText == "Person")
assert(#by_id[8].result >= 1)
assert(by_id[8].result[1].location.uri == uri)
assert(#by_id[9].result == 1)
assert(by_id[9].result[1].uri == uri)
assert(#by_id[10].result == 2)
assert(by_id[10].result[1].uri == uri)

print("moonlift lsp navigation tokens ok")
