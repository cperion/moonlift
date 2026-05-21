-- moonlift/debug_init.lua
-- Provides a helper to create a Debugger instance from a compiled .mlua module.
-- Used by tests and DAP server to instantiate the debugger with proper schema context.

local M = {}

--- Create a full debugger instance from a BackProgram and analysis context.
-- @param program  BackProgram — the compiled program (has .cmds field)
-- @param opts  table:
--   Back: MoonBack schema (required)
--   analysis_ctx: table from frontend_pipeline (has anchors, extrn, etc.)
--   source_uri: string — document URI
--   source_text: string — source text
-- @return Debugger instance, or nil, error
function M.create_debugger(program, opts)
    local Back = opts and opts.Back
    if not Back then
        return nil, "Back schema required"
    end

    local Debugger = require("moonlift.debugger_core")

    -- Extract anchors from analysis context if available
    local anchor_set = nil
    if opts.analysis_ctx and opts.analysis_ctx.anchors then
        anchor_set = opts.analysis_ctx.anchors
    end

    -- Extract extrn table
    local extrn = {}
    if opts.analysis_ctx and opts.analysis_ctx.extrn then
        extrn = opts.analysis_ctx.extrn
    end

    local cmds = program and program.cmds or {}

    local debugger = Debugger.new(cmds, {
        Back = Back,
        source_uri = opts.source_uri or "file.mlua",
        source_text = opts.source_text or "",
        anchor_set = anchor_set,
        extrn = extrn,
    })
    debugger:init()
    return debugger
end

return M
