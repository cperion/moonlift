package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local JsonEncode = require("moonlift.rpc_json_encode")
local JsonDecode = require("moonlift.rpc_json_decode")
local Loop = require("moonlift.rpc_stdio_loop")

local function frame(msg)
    local body = JsonEncode.encode_lua(msg)
    return "Content-Length: " .. #body .. "\r\n\r\n" .. body
end

local Input = {}
Input.__index = Input
function Input.new(s) return setmetatable({ s = s, i = 1 }, Input) end
function Input:read(arg)
    if self.i > #self.s then return nil end
    if arg == "*l" then
        local j = self.s:find("\n", self.i, true)
        if not j then
            local out = self.s:sub(self.i)
            self.i = #self.s + 1
            return out
        end
        local out = self.s:sub(self.i, j - 1)
        self.i = j + 1
        return out
    elseif type(arg) == "number" then
        local out = self.s:sub(self.i, self.i + arg - 1)
        self.i = self.i + #out
        return out
    end
    error("unsupported read")
end

local Output = {}
Output.__index = Output
function Output.new() return setmetatable({ parts = {} }, Output) end
function Output:write(...)
    for i = 1, select("#", ...) do self.parts[#self.parts + 1] = tostring(select(i, ...)) end
end
function Output:flush() end
function Output:text() return table.concat(self.parts) end

local uri = "file:///tmp/test.mlua"
local bad = "struct User\n  active: bool\nend\n"
local good = "struct User\n  id: i32\n  active: bool32\nend\nexpose Users: view(User)\n"
local input = table.concat({
    frame({ jsonrpc = "2.0", id = 1, method = "initialize", params = { rootUri = "file:///tmp" } }),
    frame({ jsonrpc = "2.0", method = "initialized", params = {} }),
    frame({ jsonrpc = "2.0", method = "textDocument/didOpen", params = { textDocument = { uri = uri, languageId = "mlua", version = 1, text = bad } } }),
    frame({ jsonrpc = "2.0", method = "textDocument/didChange", params = { textDocument = { uri = uri, version = 2 }, contentChanges = { { text = good } } } }),
    frame({ jsonrpc = "2.0", id = 2, method = "textDocument/documentSymbol", params = { textDocument = { uri = uri } } }),
    frame({ jsonrpc = "2.0", id = 3, method = "textDocument/hover", params = { textDocument = { uri = uri }, position = { line = 0, character = 7 } } }),
    frame({ jsonrpc = "2.0", id = 4, method = "textDocument/completion", params = { textDocument = { uri = uri }, position = { line = 5, character = 0 } } }),
    frame({ jsonrpc = "2.0", method = "textDocument/didClose", params = { textDocument = { uri = uri } } }),
    frame({ jsonrpc = "2.0", id = 5, method = "shutdown", params = {} }),
    frame({ jsonrpc = "2.0", method = "exit", params = {} }),
})

local out = Output.new()
Loop.run({ input = Input.new(input), output = out, err = Output.new() })

local function decode_frames(s)
    local msgs, i = {}, 1
    while i <= #s do
        local header_end = s:find("\r\n\r\n", i, true)
        if not header_end then break end
        local header = s:sub(i, header_end - 1)
        local len = tonumber(header:match("Content%-Length:%s*(%d+)"))
        assert(len, header)
        local body_start = header_end + 4
        local body = s:sub(body_start, body_start + len - 1)
        msgs[#msgs + 1] = JsonDecode.decode_lua(body)
        i = body_start + len
    end
    return msgs
end

local msgs = decode_frames(out:text())
assert(#msgs >= 6)
assert(msgs[1].id == 1)
assert(msgs[1].result.capabilities.positionEncoding == "utf-16")

local saw_bad_diag, saw_symbols, saw_hover, saw_completion, saw_shutdown = false, false, false, false, false
local clear_diag_count = 0
for i = 1, #msgs do
    local m = msgs[i]
    if m.method == "textDocument/publishDiagnostics" then
        if #m.params.diagnostics > 0 then
            saw_bad_diag = true
            assert(m.params.diagnostics[1].code == "host.bareBoolBoundary")
        else
            clear_diag_count = clear_diag_count + 1
        end
    elseif m.id == 2 then
        saw_symbols = true
        assert(#m.result >= 1)
        assert(m.result[1].name == "User")
    elseif m.id == 3 then
        saw_hover = true
        assert(m.result.contents.value:match("host struct"))
    elseif m.id == 4 then
        saw_completion = true
        assert(#m.result.items >= 1)
    elseif m.id == 5 then
        saw_shutdown = true
        assert(m.result == JsonDecode.JSON_NULL)
    end
end
assert(saw_bad_diag and clear_diag_count >= 2 and saw_symbols and saw_hover and saw_completion and saw_shutdown)

print("moonlift integrated lsp ok")
