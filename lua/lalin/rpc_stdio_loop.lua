local pvm = require("lalin.pvm")
local Asdl = require("lalin.schema_projection")
local JsonDecode = require("lalin.rpc_json_decode")
local LspDecode = require("lalin.rpc_lsp_decode")
local LspEncode = require("lalin.rpc_lsp_encode")
local Workspace = require("lalin.editor_workspace_apply")
local LspWorkspace = require("lalin.lsp_workspace")
local LspDispatch = require("lalin.lsp_dispatch")
local Dap = require("lalin.dap_server")

local M = {}

local function rss_kb()
    local f = io.open("/proc/self/status", "r")
    if not f then return 0 end
    for line in f:lines() do
        local n = line:match("^VmRSS:%s+(%d+)%s+kB")
        if n then
            f:close()
            return tonumber(n) or 0
        end
    end
    f:close()
    return 0
end

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

local function raw_method(body)
    return body:match('"method"%s*:%s*"([^"]+)"') or "?"
end

function M.new_context()
    local T = pvm.context()
    Asdl(T)
    return T
end

function M.run(opts)
    opts = opts or {}
    local input = opts.input or io.stdin
    local output = opts.output or io.stdout
    local err = opts.err or io.stderr
    local T = opts.context or M.new_context()
    local Json = JsonDecode(T)
    local Decode = LspDecode(T)
    local Encode = LspEncode(T)
    local WorkspaceApply = Workspace(T)
    local WorkspaceIndex = LspWorkspace(T)
    local Dispatch = LspDispatch(T)
    local E = T.LalinEditor
    local R = T.LalinRpc
    local memlog = os.getenv("LALIN_LSP_MEMLOG") == "1"

    -- Optional DAP handler for shared STDIO loop
    local dap_handler = opts.dap_handler

    local state = opts.state or WorkspaceApply.initial_state()
    local running = true
    local message_count = 0
    while running do
        local body, read_err = read_message(input)
        if not body then
            if read_err and err then err:write("lalin-lsp read error: ", read_err, "\n") end
            break
        end
        local before_heap, before_rss
        if memlog then
            collectgarbage("collect")
            before_heap = collectgarbage("count")
            before_rss = rss_kb()
            err:write(
                "lalin-lsp recv ",
                "msg=", tostring(message_count + 1),
                " method=", raw_method(body),
                " body=", tostring(#body),
                " heap_kb=", tostring(math.floor(before_heap)),
                " rss_kb=", tostring(before_rss),
                "\n"
            )
        end
        local ok, incoming = pcall(Json.decode_message, body)
        if not ok then
            if err then err:write("lalin-lsp decode error: ", tostring(incoming), "\n") end
            collectgarbage("collect")
            message_count = message_count + 1
        else
        local method = incoming.method or incoming.command or ""

        -- Check if this is a DAP message (if a DAP handler is registered)
        if dap_handler and Dap.is_dap_method(method) then
            dap_handler:handle(incoming, output)
        else
            local commands = {}
            local event = nil
            local ok_dispatch, dispatch_err = pcall(function()
            -- Existing LSP dispatch
            event = Decode.decode(incoming, state)
            local transition = WorkspaceApply.apply_event(state, event)
            state = WorkspaceIndex.sync_after_event(transition.after, event)
            transition = E.Transition(transition.before, event, state)
            commands = Dispatch.commands(transition)
            end)
            if not ok_dispatch then
                if err then err:write("lalin-lsp dispatch error method=", tostring(method), ": ", tostring(dispatch_err), "\n") end
                commands = {}
            end
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
            message_count = message_count + 1
            if message_count % 32 == 0 then
                collectgarbage("collect")
            else
                collectgarbage("step", 400)
            end
            if memlog then
                collectgarbage("collect")
                local after_heap = collectgarbage("count")
                local after_rss = rss_kb()
                local event_cls = pvm.classof(event)
                err:write(
                    "lalin-lsp mem ",
                    "msg=", tostring(message_count),
                    " method=", tostring(method),
                    " event=", tostring(event_cls and event_cls.kind or "?"),
                    " body=", tostring(#body),
                    " cmds=", tostring(#commands),
                    " open=", tostring(#(state.open_docs or {})),
                    " heap_kb=", tostring(math.floor(after_heap)),
                    " heap_delta=", tostring(math.floor(after_heap - before_heap)),
                    " rss_kb=", tostring(after_rss),
                    " rss_delta=", tostring(after_rss - before_rss),
                    "\n"
                )
            end
        end
        end
    end
    return state
end

return M
