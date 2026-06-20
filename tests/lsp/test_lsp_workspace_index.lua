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

local root = "/tmp/moonlift_lsp_workspace_index"
os.execute("rm -rf " .. root .. " && mkdir -p " .. root)

local helper_uri = "file://" .. root .. "/helper.mlua"
local main_uri = "file://" .. root .. "/main.mlua"
local helper_src = [[
func helper(x: i32): i32
    return x
end
]]
local main_src = [[
func main(x: i32): i32
    return helper(x)
end
]]

local f = assert(io.open(root .. "/helper.mlua", "wb"))
f:write(helper_src)
f:close()

local function pos_of(src, needle, nth)
    nth = nth or 1
    local start, s = 1, nil
    for _ = 1, nth do s = assert(src:find(needle, start, true), needle); start = s + #needle end
    local prefix = src:sub(1, s - 1)
    local line = select(2, prefix:gsub("\n", ""))
    local last = prefix:match(".*\n()") or 1
    return { line = line, character = s - last }
end

local input = table.concat({
    frame({ jsonrpc = "2.0", id = 1, method = "initialize", params = { rootUri = "file://" .. root } }),
    frame({ jsonrpc = "2.0", method = "initialized", params = {} }),
    frame({ jsonrpc = "2.0", method = "textDocument/didOpen", params = { textDocument = { uri = helper_uri, languageId = "mlua", version = 1, text = helper_src } } }),
    frame({ jsonrpc = "2.0", method = "textDocument/didOpen", params = { textDocument = { uri = main_uri, languageId = "mlua", version = 1, text = main_src } } }),
    frame({ jsonrpc = "2.0", id = 2, method = "workspace/symbol", params = { query = "helper" } }),
    frame({ jsonrpc = "2.0", id = 3, method = "textDocument/definition", params = { textDocument = { uri = main_uri }, position = pos_of(main_src, "helper") } }),
    frame({ jsonrpc = "2.0", id = 4, method = "textDocument/references", params = { textDocument = { uri = main_uri }, position = pos_of(main_src, "helper"), context = { includeDeclaration = true } } }),
    frame({ jsonrpc = "2.0", id = 5, method = "textDocument/rename", params = { textDocument = { uri = main_uri }, position = pos_of(main_src, "helper"), newName = "helper2" } }),
    frame({ jsonrpc = "2.0", id = 6, method = "shutdown", params = {} }),
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

local by_id = {}
for _, msg in ipairs(decode_frames(out:text())) do if msg.id then by_id[msg.id] = msg end end

assert(#by_id[2].result >= 1, "workspace symbols should include open .mlua files")
assert(by_id[2].result[1].location.uri == helper_uri, "workspace symbol should point at helper file")

assert(#by_id[3].result == 1, "definition should cross between open files")
assert(by_id[3].result[1].uri == helper_uri, "definition should target helper file")

local saw_main_use, saw_helper_def = false, false
for _, loc in ipairs(by_id[4].result) do
    if loc.uri == main_uri then saw_main_use = true end
    if loc.uri == helper_uri then saw_helper_def = true end
end
assert(saw_main_use and saw_helper_def, "references should include open use and open definition")

local changes = by_id[5].result.changes
assert(changes[main_uri] and changes[helper_uri], "rename should edit both open files")
assert(changes[main_uri][1].newText == "helper2")
assert(changes[helper_uri][1].newText == "helper2")

print("moonlift lsp workspace index ok")
