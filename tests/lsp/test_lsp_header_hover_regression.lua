package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

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

local path = "daw_moonlift_type_cfg_design.mlua"
local f = assert(io.open(path, "rb"))
local src = f:read("*a")
f:close()

local uri = "file://" .. path
local input = table.concat({
    frame({ jsonrpc = "2.0", id = 1, method = "initialize", params = {} }),
    frame({ jsonrpc = "2.0", method = "textDocument/didOpen", params = { textDocument = { uri = uri, languageId = "mlua", version = 1, text = src } } }),
    frame({ jsonrpc = "2.0", id = 2, method = "textDocument/hover", params = { textDocument = { uri = uri }, position = { line = 0, character = 0 } } }),
    frame({ jsonrpc = "2.0", id = 3, method = "textDocument/diagnostic", params = { textDocument = { uri = uri } } }),
    frame({ jsonrpc = "2.0", id = 4, method = "shutdown", params = {} }),
    frame({ jsonrpc = "2.0", method = "exit", params = {} }),
})

local out = Output.new()
Loop.run({ input = Input.new(input), output = out, err = Output.new() })

local by_id = {}
for _, msg in ipairs(decode_frames(out:text())) do if msg.id then by_id[msg.id] = msg end end
assert(by_id[2] and by_id[2].result)
assert(by_id[3] and by_id[3].result and by_id[3].result.kind == "full")

print("moonlift lsp header hover regression ok")
