-- moonlift/dap_server.lua
-- Debug Adapter Protocol server for Moonlift.
-- Shares the STDIO loop with the LSP server.
-- Translates DAP requests → debugger core commands.
--
-- Usage:
--   local Dap = require("moonlift.dap_server")
--   local dap = Dap.new({ Back = Back, cmds = cmds, ... })
--   -- In the STDIO loop:
--   if Dap.is_dap_method(method) then dap:handle(incoming, output) end

local pvm = require("moonlift.pvm")
local Debugger = require("moonlift.debugger_core")
local Variables = require("moonlift.dap_variables")

local M = {}

local DapServer = {}
DapServer.__index = DapServer

--- Set of DAP method names (case-sensitive).
local DAP_METHODS = {
    initialize = true,
    setBreakpoints = true,
    setFunctionBreakpoints = true,
    setExceptionBreakpoints = true,
    continue = true,
    next = true,
    stepIn = true,
    stepOut = true,
    pause = true,
    stackTrace = true,
    scopes = true,
    variables = true,
    disconnect = true,
    terminate = true,
    launch = true,
    attach = true,
    configurationDone = true,
    threads = true,
    source = true,
    gotoTargets = true,
}

--- Check if a method name is a DAP method.
-- @param method  string — JSON-RPC method name
-- @return boolean
function M.is_dap_method(method)
    return DAP_METHODS[method] == true or
        (type(method) == "string" and method:match("^dap/"))
end

--- Create a new DAP server instance.
-- @param opts  table:
--   Back: MoonBack schema table (required)
--   cmds: BackCmd[] — full module command stream
--   source_uri: string — document URI
--   source_text: string — document source
--   anchor_set: AnchorSet — for breakpoint resolution
--   extrn: {[name] = function} — extern FFI functions
--   functions: {[func_id_str] = BackCmd[]} — Moonlift function bodies
-- @return DapServer instance
function M.new(opts)
    opts = opts or {}
    local self = setmetatable({
        debugger = nil,
        opts = opts,
        seq = 0,
        initialized = false,
        running = false,
        breakpoint_id_counter = 0,
        breakpoints = {},       -- {[dap_bp_id] = {verified, block_label, line, condition}}
        output = nil,           -- output stream (set during handle)
    }, DapServer)

    return self
end

--- Initialize the debugger with program commands.
function DapServer:init_with_program(cmds)
    self.debugger = Debugger.new(cmds, {
        Back = self.opts.Back,
        source_uri = self.opts.source_uri,
        source_text = self.opts.source_text,
        anchor_set = self.opts.anchor_set,
        extrn = self.opts.extrn or {},
        functions = self.opts.functions or {},
        memory_size = self.opts.memory_size,
    })
    self.debugger:init()
end

--- Handle a single DAP request.
-- @param incoming  decoded JSON message {command?, method?, arguments?, seq}
-- @param output    io output stream for writing response
function DapServer:handle(incoming, output)
    self.output = output
    local method = incoming.command or incoming.method or ""
    local args = incoming.arguments or {}
    local request_seq = incoming.seq

    if method == "initialize" then
        self:_handle_initialize(request_seq, args)
    elseif method == "launch" or method == "attach" then
        self:_handle_launch(request_seq, args)
    elseif method == "setBreakpoints" then
        self:_handle_set_breakpoints(request_seq, args)
    elseif method == "setFunctionBreakpoints" then
        self:_handle_set_function_breakpoints(request_seq, args)
    elseif method == "setExceptionBreakpoints" then
        self:_send_response(request_seq, {})
    elseif method == "continue" then
        self:_handle_continue(request_seq, args)
    elseif method == "next" then
        self:_handle_next(request_seq, args)
    elseif method == "stepIn" then
        self:_handle_step_in(request_seq, args)
    elseif method == "stepOut" then
        self:_handle_step_out(request_seq, args)
    elseif method == "pause" then
        self:_handle_pause(request_seq, args)
    elseif method == "stackTrace" then
        self:_handle_stack_trace(request_seq, args)
    elseif method == "scopes" then
        self:_handle_scopes(request_seq, args)
    elseif method == "variables" then
        self:_handle_variables(request_seq, args)
    elseif method == "disconnect" or method == "terminate" then
        self:_handle_disconnect(request_seq, args)
    elseif method == "configurationDone" then
        self:_send_response(request_seq, {})
    elseif method == "threads" then
        self:_send_response(request_seq, { threads = { { id = 1, name = "main" } } })
    elseif method == "source" then
        self:_send_response(request_seq, {})
    elseif method == "gotoTargets" then
        self:_send_response(request_seq, { gotoTargets = {} })
    elseif method == "goto" then
        self:_send_response(request_seq, {})
    else
        self:_send_response(request_seq, { success = false, message = "unsupported method: " .. method })
    end
end

--- Send a DAP success response.
function DapServer:_send_response(request_seq, body)
    self.seq = self.seq + 1
    local response = {
        type = "response",
        seq = self.seq,
        command = "request",
        request_seq = request_seq,
        success = true,
        body = body,
    }
    self:_write_json(response)
end

--- Send a DAP event.
function DapServer:_send_event(event_type, body)
    self.seq = self.seq + 1
    local event = {
        type = "event",
        seq = self.seq,
        event = event_type,
        body = body or {},
    }
    self:_write_json(event)
end

--- Write a JSON message with Content-Length framing.
function DapServer:_write_json(obj)
    if not self.output then return end
    local cjson = require("cjson")
    local body = cjson.encode(obj)
    self.output:write("Content-Length: ", tostring(#body), "\r\n\r\n", body)
    self.output:flush()
end

-- DAP initialize handler
function DapServer:_handle_initialize(request_seq, args)
    self.initialized = true
    self:_send_response(request_seq, {
        supportsConfigurationDoneRequest = true,
        supportsSetVariable = false,
        supportsConditionalBreakpoints = true,
        supportsFunctionBreakpoints = true,
        supportsStepInTargetsRequest = false,
        supportsGotoTargetsRequest = false,
        supportsCompletionsRequest = false,
        supportTerminateDebuggee = true,
        supportsExceptionInfoRequest = true,
        supportsExceptionOptions = true,
    })
end

-- DAP launch handler: compile and start debugger
function DapServer:_handle_launch(request_seq, args)
    if not self.opts.cmds then
        self:_send_response(request_seq, {
            success = false,
            message = "no program commands provided",
        })
        return
    end
    self:init_with_program(self.opts.cmds)
    self.running = true

    -- Register pause event handler
    self.debugger:on("breakpoint", function(data)
        self:_send_event("stopped", {
            reason = "breakpoint",
            description = data.label and ("breakpoint at " .. data.label) or "breakpoint hit",
            threadId = 1,
            allThreadsStopped = true,
        })
    end)

    self.debugger:on("trap", function(data)
        self:_send_event("stopped", {
            reason = "exception",
            description = "trap in user code",
            threadId = 1,
            allThreadsStopped = true,
        })
    end)

    -- Start execution (pauses at first block boundary)
    self.debugger:start()

    self:_send_response(request_seq, {})

    -- Send initial stopped event (paused at entry)
    self:_send_event("stopped", {
        reason = "entry",
        description = "paused at module entry",
        threadId = 1,
        allThreadsStopped = true,
    })
end

-- DAP setBreakpoints handler: map source lines to block labels
function DapServer:_handle_set_breakpoints(request_seq, args)
    local source = args.source
    local source_path = source and source.path or self.opts.source_uri or "unknown"
    local lines = args.lines or {}
    local breakpoints = args.breakpoints or {}
    local resolved = {}

    for i, line in ipairs(lines) do
        local bp_info = breakpoints[i] or {}
        local condition = bp_info.condition

        -- Resolve line to block labels using anchor index
        local resolver = require("moonlift.dap_breakpoint_resolver")
        local blocks = resolver.resolve_line(
            source_path, line - 1,  -- DAP line numbers are 1-based
            self.opts.source_text or "",
            self.opts.anchor_set or { anchors = {} })

        if #blocks > 0 then
            for _, blk in ipairs(blocks) do
                local bp_id = self.breakpoint_id_counter + 1
                self.breakpoint_id_counter = bp_id
                self.breakpoints[bp_id] = {
                    verified = true,
                    block_label = blk.block_label,
                    line = line,
                    condition = condition,
                }

                -- Register with debugger
                local condition_fn = nil
                if condition and #condition > 0 then
                    condition_fn = function(vars)
                        -- Simple variable substitution: $name → value
                        local expr = condition
                        for k, v in pairs(vars) do
                            expr = expr:gsub("%$" .. k, tostring(v))
                        end
                        local ok, result = pcall(load("return " .. expr))
                        if ok then
                            return result
                        end
                        return false
                    end
                end
                if self.debugger then
                    self.debugger:set_breakpoint(blk.block_label, {
                        condition_fn = condition_fn,
                    })
                end

                resolved[#resolved + 1] = {
                    id = bp_id,
                    verified = true,
                    line = line,
                }
            end
        else
            -- No block at this line: unverified breakpoint
            local bp_id = self.breakpoint_id_counter + 1
            self.breakpoint_id_counter = bp_id
            self.breakpoints[bp_id] = {
                verified = false,
                line = line,
            }
            resolved[#resolved + 1] = {
                id = bp_id,
                verified = false,
                line = line,
            }
        end
    end

    self:_send_response(request_seq, { breakpoints = resolved })
end

-- DAP setFunctionBreakpoints handler
function DapServer:_handle_set_function_breakpoints(request_seq, args)
    local resolved = {}
    for _, bp in ipairs(args.breakpoints or {}) do
        -- Map function names to entry block labels
        -- Convention: function "foo" has entry block label "func:foo"
        local block_label = "func:" .. bp.name
        local bp_id = self.breakpoint_id_counter + 1
        self.breakpoint_id_counter = bp_id

        if self.debugger then
            self.debugger:set_breakpoint(block_label)
        end

        resolved[#resolved + 1] = {
            id = bp_id,
            verified = true,
            name = bp.name,
        }
    end
    self:_send_response(request_seq, { breakpoints = resolved })
end

-- DAP continue handler
function DapServer:_handle_continue(request_seq, args)
    if self.debugger and not self.debugger:is_terminated() then
        -- Poll first to see if we're paused
        self.debugger:poll()
        if self.debugger:get_state() == "paused" then
            local result = self.debugger:continue()
            if result and result.type == "terminated" then
                self:_send_response(request_seq, { allThreadsContinued = true })
                self:_send_event("terminated", {})
                self:_send_event("exited", { exitCode = 0 })
                return
            end
        end
    end
    self:_send_response(request_seq, { allThreadsContinued = true })
end

-- DAP next handler (step over block)
function DapServer:_handle_next(request_seq, args)
    if self.debugger then
        self.debugger:poll()
        if self.debugger:get_state() == "paused" then
            local block = self.debugger:step_block()
            self:_send_response(request_seq, {})
            -- Send stopped event
            if self.debugger:is_terminated() then
                self:_send_event("terminated", {})
                self:_send_event("exited", { exitCode = 0 })
            else
                self:_send_event("stopped", {
                    reason = "step",
                    threadId = 1,
                    allThreadsStopped = true,
                })
            end
            return
        end
    end
    self:_send_response(request_seq, { success = false, message = "not paused" })
end

-- DAP stepIn handler (same as next for block-level stepping)
function DapServer:_handle_step_in(request_seq, args)
    self:_handle_next(request_seq, args)
end

-- DAP stepOut handler (continue until region exit)
function DapServer:_handle_step_out(request_seq, args)
    -- Continue until a region exit (CmdReturn or CmdTrap)
    if self.debugger then
        self.debugger:poll()
        if self.debugger:get_state() == "paused" then
            local result = self.debugger:continue()
            self:_send_response(request_seq, {})
            if result and result.type == "terminated" then
                self:_send_event("terminated", {})
                self:_send_event("exited", { exitCode = 0 })
            else
                self:_send_event("stopped", {
                    reason = "step",
                    threadId = 1,
                    allThreadsStopped = true,
                })
            end
            return
        end
    end
    self:_send_response(request_seq, { success = false, message = "not paused" })
end

-- DAP pause handler
function DapServer:_handle_pause(request_seq, args)
    if self.debugger then
        self.debugger:pause()
    end
    self:_send_response(request_seq, {})
end

-- DAP stackTrace handler
function DapServer:_handle_stack_trace(request_seq, args)
    if not self.debugger then
        self:_send_response(request_seq, { stackFrames = {}, totalFrames = 0 })
        return
    end
    local stack = self.debugger:stack_trace()
    local frames = {}
    local resolver = require("moonlift.dap_breakpoint_resolver")

    for i, frame in ipairs(stack) do
        local block_text = frame.block or "?"
        local label = self.debugger:_parse_block_label(block_text) or block_text
        local region = self.debugger:_parse_region_id(block_text) or "?"

        -- Format param values into name
        local params_str = ""
        local param_count = 0
        for pname, pval in pairs(frame.params or {}) do
            if param_count > 0 then params_str = params_str .. ", " end
            params_str = params_str .. pname .. "=" .. tostring(pval)
            param_count = param_count + 1
        end
        local frame_name = region .. ":" .. label
        if #params_str > 0 then
            frame_name = frame_name .. "(" .. params_str .. ")"
        end

        -- Try to resolve source location
        local line = 0
        local column = 1
        if self.opts.anchor_set and label then
            local range = resolver.resolve_block_label(label, self.opts.anchor_set)
            if range and range.start then
                line = range.start.line + 1  -- 1-based for DAP
                column = range.start.utf16_col + 1
            end
        end

        frames[#frames + 1] = {
            id = i,
            name = frame_name,
            source = { path = self.opts.source_uri or "unknown.mlua" },
            line = line,
            column = column,
        }
    end

    self:_send_response(request_seq, {
        stackFrames = frames,
        totalFrames = #frames,
    })
end

-- DAP scopes handler
function DapServer:_handle_scopes(request_seq, args)
    local var_count = 0
    if self.debugger then
        local vars = self.debugger:get_variables()
        for _ in pairs(vars) do
            var_count = var_count + 1
        end
    end
    self:_send_response(request_seq, {
        scopes = {{
            name = "Block Parameters",
            variablesReference = 1,
            namedVariables = var_count,
            expensive = false,
        }}
    })
end

-- DAP variables handler
function DapServer:_handle_variables(request_seq, args)
    if not self.debugger then
        self:_send_response(request_seq, { variables = {} })
        return
    end
    local vars = self.debugger:get_variables()
    local formatted = Variables.format_variables(vars)
    self:_send_response(request_seq, { variables = formatted })
end

-- DAP disconnect handler
function DapServer:_handle_disconnect(request_seq, args)
    self.running = false
    self.debugger = nil
    self:_send_response(request_seq, {})
end

return M
