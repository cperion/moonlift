-- lalin/debugger_core.lua
-- Debugger state machine: stepping modes, breakpoint table, pause/resume,
-- variable inspection, and coordination between the interpreter and DAP server.

local pvm = require("lalin.pvm")
local llb = require("llb")
local Interpreter = require("lalin.debug_interpreter")

local M = {}

local Debugger = {}
Debugger.__index = Debugger

--- States
local STATE_IDLE = "idle"
local STATE_RUNNING = "running"
local STATE_PAUSED = "paused"
local STATE_TERMINATED = "terminated"

--- Create a new debugger instance.
-- @param cmds  BackCmd[] — the flat command stream to debug
-- @param opts  table:
--   Back: LalinBack schema table (required, passed to interpreter)
--   source_uri: string — document URI for breakpoint resolution
--   source_text: string — document source text
--   anchor_set: AnchorSet — for anchor-based breakpoint resolution
--   extrn: {[name] = function} — extern functions for interpreter
--   functions: {[func_id] = BackCmd[]} — direct function bodies
--   memory_size: number — flat address space size for interpreter
function M.new(cmds, opts)
    opts = opts or {}
    local self = setmetatable({
        state = STATE_IDLE,
        interpreter = nil,
        cmds = cmds,
        Back = opts.Back,
        breakpoints = {},       -- {[label_key] = {enabled, condition_fn, hit_count, temporary, region_id}}
        source_lines_to_block = {},  -- line_number (0-based) → {block_label, region_id}[]
        current_block = nil,
        last_event = nil,
        event_handlers = {},    -- {[event_type] = {handler_fn, ...}}
        opts = opts,
    }, Debugger)

    return self
end

--- Initialize: create interpreter and build source-line mapping.
function Debugger:init()
    if not self.Back then
        error("debugger_core: Back schema required")
    end
    self.interpreter = Interpreter.new(self.cmds, {
        Back = self.Back,
        extrn = self.opts.extrn or {},
        functions = self.opts.functions or {},
        memory_size = self.opts.memory_size,
    })
    self.interpreter.event_handler = function(event_type, data)
        self:_on_interpreter_event(event_type, data)
    end
    self.state = STATE_PAUSED

    -- Build source-lines-to-block mapping from anchor set
    if self.opts.anchor_set and self.opts.source_uri and self.opts.source_text then
        local ok, resolver = pcall(require, "lalin.dap_breakpoint_resolver")
        if ok then
            local lines = {}
            local text = self.opts.source_text
            local start = 1
            for line_text in text:gmatch("([^\n]*)\n?") do
                lines[#lines + 1] = line_text
                start = start + #line_text + 1
            end
            -- Handle last line without trailing newline
            if start <= #text then
                lines[#lines + 1] = text:sub(start)
            end
            for line_no = 0, #lines - 1 do
                local blocks = resolver.resolve_line(
                    self.opts.source_uri, line_no,
                    self.opts.source_text, self.opts.anchor_set)
                if #blocks > 0 then
                    self.source_lines_to_block[line_no] = blocks
                end
            end
        end
    end

    return self
end

--- Start execution (pauses at first block boundary).
function Debugger:start()
    if self.state ~= STATE_PAUSED then
        return nil, "debugger not paused"
    end
    self.state = STATE_RUNNING
    local block = self.interpreter:step_block()
    self.state = STATE_PAUSED
    self.current_block = block
    return block
end

--- Step one block transition.
function Debugger:step_block()
    if self.state ~= STATE_PAUSED then
        return nil, "not paused"
    end
    self.state = STATE_RUNNING
    local block = self.interpreter:step_block()
    self.state = STATE_PAUSED
    self.current_block = block
    if self.interpreter.terminated then
        self.state = STATE_TERMINATED
    end
    return block
end

--- Continue until breakpoint or termination.
function Debugger:continue()
    if self.state ~= STATE_PAUSED then
        return nil, "not paused"
    end
    self.state = STATE_RUNNING
    local result = self.interpreter:continue_until(function(bid)
        return self:_check_breakpoints(bid)
    end)
    self.state = STATE_PAUSED
    self.last_event = result
    if result.type == "terminated" then
        self.state = STATE_TERMINATED
    end
    return result
end

--- Poll interpreter state (for non-blocking integration).
function Debugger:poll()
    if self.state == STATE_RUNNING and self.interpreter.paused then
        self.state = STATE_PAUSED
    end
    if self.interpreter and self.interpreter.terminated then
        self.state = STATE_TERMINATED
    end
    return self.state
end

--- Set a breakpoint on a block label.
-- @param block_label  string — block label name (e.g. "loop", "start")
-- @param opts  {condition_fn, region_id, temporary}
-- @return breakpoint key string
function Debugger:set_breakpoint(block_label, opts)
    opts = opts or {}
    local key = block_label .. (opts.region_id and ":" .. opts.region_id or "")
    self.breakpoints[key] = {
        enabled = true,
        condition_fn = opts.condition_fn,
        hit_count = 0,
        temporary = opts.temporary or false,
        region_id = opts.region_id,
    }
    return key
end

--- Remove a breakpoint.
function Debugger:clear_breakpoint(key)
    self.breakpoints[key] = nil
end

--- Get current variable values (block parameters).
function Debugger:get_variables()
    if not self.interpreter then return {} end
    local regs = self.interpreter:read_all_registers()
    -- Filter to block param registers (those matching the naming pattern)
    local vars = {}
    for name, value in pairs(regs) do
        -- Skip internal register names (synthetic values like v1, v2)
        if not name:match("^v%d+$") and not name:match("^addr") then
            -- Extract just the param name from the full BackValId
            -- Format: "ctl:{nonce}:{region}:{label}:{param}"
            local param_name = name:match(":([^:]+)$")
            if param_name then
                vars[param_name] = value
            else
                vars[name] = value
            end
        end
    end
    return vars
end

--- Get a stack trace (breadcrumb trail of block transitions).
function Debugger:stack_trace()
    local stack = {}
    if self.current_block then
        stack[#stack + 1] = {
            block = self.current_block,
            params = self:get_variables(),
        }
    end
    -- Include interpreter call stack
    if self.interpreter and self.interpreter.call_stack then
        for _, frame in ipairs(self.interpreter.call_stack) do
            stack[#stack + 1] = {
                block = frame.current_block,
                params = frame.registers or {},
            }
        end
    end
    return stack
end

--- Map a source line to block label names using the anchor index.
-- @param line  number — 0-based line number
-- @return array of {block_label, region_id} or empty array
function Debugger:resolve_line_to_block(line)
    return self.source_lines_to_block[line] or {}
end

--- Internal breakpoint check, called by interpreter at each block entry.
function Debugger:_check_breakpoints(bid)
    local label = self:_parse_block_label(bid)
    if not label then return false end

    -- Check exact label match
    local bp = self.breakpoints[label]
    if bp and bp.enabled then
        bp.hit_count = (bp.hit_count or 0) + 1
        -- Evaluate condition
        if bp.condition_fn then
            local vars = self:get_variables()
            if not bp.condition_fn(vars) then return false end
        end
        if bp.temporary then
            self.breakpoints[label] = nil
        end
        self:_on_interpreter_event("breakpoint", { block = bid, label = label })
        return true
    end

    -- Check region-qualified match: "label:region"
    local region_id = self:_parse_region_id(bid)
    if region_id then
        local qualified_key = label .. ":" .. region_id
        local bp2 = self.breakpoints[qualified_key]
        if bp2 and bp2.enabled then
            bp2.hit_count = (bp2.hit_count or 0) + 1
            if bp2.condition_fn then
                local vars = self:get_variables()
                if not bp2.condition_fn(vars) then return false end
            end
            if bp2.temporary then
                self.breakpoints[qualified_key] = nil
            end
            self:_on_interpreter_event("breakpoint", { block = bid, label = label, region = region_id })
            return true
        end
    end

    return false
end

--- Parse a BackBlockId to extract the label name.
-- Format: "ctl:{nonce}:{region}:{label}"
function Debugger:_parse_block_label(bid)
    if type(bid) == "string" then
        local parts = {}
        for part in bid:gmatch("[^:]+") do
            parts[#parts + 1] = part
        end
        if #parts >= 4 then return parts[#parts] end
        return nil
    end
    if bid and bid.text then
        local parts = {}
        for part in bid.text:gmatch("[^:]+") do
            parts[#parts + 1] = part
        end
        if #parts >= 4 then return parts[#parts] end
    end
    return nil
end

--- Parse a BackBlockId to extract the region id.
-- Format: "ctl:{nonce}:{region}:{label}"
function Debugger:_parse_region_id(bid)
    local text = type(bid) == "string" and bid or (bid and bid.text)
    if not text then return nil end
    local parts = {}
    for part in text:gmatch("[^:]+") do
        parts[#parts + 1] = part
    end
    if #parts >= 3 then return parts[#parts - 1] end
    return nil
end

--- Register an event handler.
-- @param event_type  string — "paused", "terminated", "breakpoint", "trap"
-- @param fn  function(event_data)
function Debugger:on(event_type, fn)
    if not self.event_handlers[event_type] then
        self.event_handlers[event_type] = {}
    end
    self.event_handlers[event_type][#self.event_handlers[event_type] + 1] = fn
end

function Debugger:_on_interpreter_event(event_type, data)
    for _, handler in ipairs(self.event_handlers[event_type] or {}) do
        handler(data)
    end
end

--- Pause execution.
function Debugger:pause()
    if self.interpreter then
        self.interpreter:pause()
    end
end

--- Check if debugger has terminated.
function Debugger:is_terminated()
    return self.state == STATE_TERMINATED or
        (self.interpreter and self.interpreter.terminated)
end

--- Get the current state name.
function Debugger:get_state()
    return self.state
end

local function make_debug_event(ctx, debugger, kind, payload)
    payload = payload or {}
    payload.state = debugger:get_state()
    payload.terminated = debugger:is_terminated()
    payload.variables = debugger:get_variables()
    payload.stack = debugger:stack_trace()
    return ctx:make_event(kind, payload)
end

function Debugger:process(commands)
    return M.process:start(self, commands or {})
end

local function debugger_process_body(ctx, debugger, commands)
    commands = commands or { "init", "start" }
    local function command_event(param, command)
        local debugger0 = param.debugger
        local op = type(command) == "table" and command.op or command
        if op == "init" then
            local ok, err = pcall(function() debugger0:init() end)
            if ok then return make_debug_event(param.ctx, debugger0, "initialized", { command = command }) end
            return param.ctx:make_event("error", { code = "E_DEBUG_INIT", message = tostring(err), command = command })
        elseif op == "start" then
            local block, err = debugger0:start()
            if block then return make_debug_event(param.ctx, debugger0, "paused", { reason = "entry", block = block, command = command }) end
            return param.ctx:make_event("error", { code = "E_DEBUG_START", message = tostring(err), command = command })
        elseif op == "step" or op == "next" or op == "step_block" then
            local block, err = debugger0:step_block()
            if block then return make_debug_event(param.ctx, debugger0, "step", { block = block, command = command }) end
            if debugger0:is_terminated() then return make_debug_event(param.ctx, debugger0, "terminated", { command = command }) end
            return param.ctx:make_event("error", { code = "E_DEBUG_STEP", message = tostring(err), command = command })
        elseif op == "continue" then
            local result, err = debugger0:continue()
            if result then
                local kind = result.type == "terminated" and "terminated" or "paused"
                return make_debug_event(param.ctx, debugger0, kind, { reason = result.type, result = result, command = command })
            end
            return param.ctx:make_event("error", { code = "E_DEBUG_CONTINUE", message = tostring(err), command = command })
        elseif op == "pause" then
            debugger0:pause()
            return make_debug_event(param.ctx, debugger0, "paused", { reason = "pause", command = command })
        elseif op == "breakpoint" then
            local key = debugger0:set_breakpoint(command.block or command.label, command)
            return make_debug_event(param.ctx, debugger0, "breakpoint", { key = key, command = command })
        elseif op == "clear_breakpoint" then
            debugger0:clear_breakpoint(command.key)
            return make_debug_event(param.ctx, debugger0, "breakpoint_cleared", { key = command.key, command = command })
        elseif op == "variables" then
            return make_debug_event(param.ctx, debugger0, "variables", { command = command })
        elseif op == "stack" then
            return make_debug_event(param.ctx, debugger0, "stack", { command = command })
        end
        return param.ctx:make_event("error", { code = "E_DEBUG_COMMAND", message = "unknown debugger process command " .. tostring(op), command = command })
    end

    local function gen(param, state)
        if state.phase == "state" then
            state.phase = "command"
            return state, param.ctx:make_event("state", {
                state = param.debugger:get_state(),
                terminated = param.debugger:is_terminated(),
            })
        end
        if state.phase == "command" then
            local command = param.commands[state.index]
            if command == nil then
                state.phase = "result"
            elseif param.ctx:cancelled() then
                state.phase = "cancelled_result"
                return state, make_debug_event(param.ctx, param.debugger, "cancelled", { command = command })
            else
                state.index = state.index + 1
                return state, command_event(param, command)
            end
        end
        if state.phase == "cancelled_result" then
            state.phase = "done"
            return state, param.ctx:make_event("result", { result = {
                state = param.debugger:get_state(),
                terminated = param.debugger:is_terminated(),
                cancelled = true,
            } })
        end
        if state.phase == "result" then
            state.phase = "done"
            return state, param.ctx:make_event("result", { result = {
                state = param.debugger:get_state(),
                terminated = param.debugger:is_terminated(),
            } })
        end
        return nil
    end

    return gen, { ctx = ctx, debugger = debugger, commands = commands }, { phase = "state", index = 1 }
end

M.process = llb.process. debugger { "debugger", "commands" } (debugger_process_body)

return M
