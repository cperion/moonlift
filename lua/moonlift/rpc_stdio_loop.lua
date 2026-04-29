local pvm = require("moonlift.pvm")
local Asdl = require("moonlift.asdl")
local JsonDecode = require("moonlift.rpc_json_decode")
local LspDecode = require("moonlift.rpc_lsp_decode")
local LspEncode = require("moonlift.rpc_lsp_encode")
local Workspace = require("moonlift.editor_workspace_apply")
local OutCommands = require("moonlift.rpc_out_commands")

local M = {}

local function read_message(input)
    local len = nil
    while true do
        local line = input:read("*l")
        if not line then return nil end
        line = line:gsub("\r$", "")
        if line == "" then break end
        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k and k:lower() == "content-length" then len = tonumber(v) end
    end
    if not len then return nil, "missing Content-Length" end
    local body = input:read(len)
    if not body or #body < len then return nil, "short body" end
    return body
end

local function write_message(output, body)
    output:write("Content-Length: ", tostring(#body), "\r\n\r\n", body)
    output:flush()
end

function M.new_context()
    local T = pvm.context()
    Asdl.Define(T)
    return T
end

function M.run(opts)
    opts = opts or {}
    local input = opts.input or io.stdin
    local output = opts.output or io.stdout
    local err = opts.err or io.stderr
    local T = opts.context or M.new_context()
    local Json = JsonDecode.Define(T)
    local Decode = LspDecode.Define(T)
    local Encode = LspEncode.Define(T)
    local WorkspaceApply = Workspace.Define(T)
    local Out = OutCommands.Define(T)
    local R = T.Moon2Rpc

    local state = opts.state or WorkspaceApply.initial_state()
    local running = true
    while running do
        local body, read_err = read_message(input)
        if not body then
            if read_err and err then err:write("moonlift-lsp read error: ", read_err, "\n") end
            break
        end
        local incoming = Json.decode_message(body)
        local event = Decode.decode(incoming, state)
        local transition = WorkspaceApply.apply_event(state, event)
        state = transition.after
        local commands = Out.commands(transition)
        for i = 1, #commands do
            local cmd = commands[i]
            local cls = pvm.classof(cmd)
            if cls == R.SendMessage then
                write_message(output, Encode.encode_outgoing(cmd.outgoing))
            elseif cls == R.LogMessage then
                if err then err:write(cmd.level, ": ", cmd.message, "\n") end
            elseif cmd == R.StopServer or cls == pvm.classof(R.StopServer) then
                running = false
            end
        end
    end
    return state
end

return M
