-- Public Moonlift Lua facade.
--
-- Unified entry API follows LuaJIT conventions:
--   moon.loadstring(src [, name [, opts]])  — compile and return a callable
--   moon.loadfile(path [, opts])            — compile and return a callable
--   moon.dofile(path [, opts, ...])         — load and immediately execute
--   moon.eval(src, ...)                     — loadstring + immediate call
--
-- Object emission:
--   moon.emit_object(src [, path [, name]])  — emit .o bytes (hosted pipeline)
--   moon.emit_shared(src [, path [, name]])  — emit .so/.dylib (hosted pipeline)
--
-- Builder API (unchanged):
--   moon.module("name"), moon.func(...), etc.

local M = {}

M.pvm = require("moonlift.pvm")
M.triplet = require("moonlift.triplet")
M.asdl_context = require("moonlift.asdl_context")
M.asdl_lexer = require("moonlift.asdl_lexer")
M.asdl_parser = require("moonlift.asdl_parser")
M.asdl_model = require("moonlift.asdl_model")
M.asdl_builder = require("moonlift.asdl_builder")
M.schema = require("moonlift.schema")
M.context_define_schema = require("moonlift.context_define_schema")
M.phase_model = require("moonlift.phase_model")
M.phase_builder = require("moonlift.phase_builder")
M.pvm_surface_model = require("moonlift.pvm_surface_model")
M.pvm_surface_builder = require("moonlift.pvm_surface_builder")
M.pvm_surface_region_values = require("moonlift.pvm_surface_region_values")
M.pvm_surface_schema_values = require("moonlift.pvm_surface_schema_values")
M.pvm_surface_cache_values = require("moonlift.pvm_surface_cache_values")
M.pvm_surface_union_values = require("moonlift.pvm_surface_union_values")
M.type_ref_classify_surface = require("moonlift.type_ref_classify_surface")
M.quote = require("moonlift.quote")
M.ast = require("moonlift.ast")
M.back_program = require("moonlift.back_program")
M.back_target_model = require("moonlift.back_target_model")
M.back_inspect = require("moonlift.back_inspect")
M.back_diagnostics = require("moonlift.back_diagnostics")
M.back_object = require("moonlift.back_object")
M.link_target_model = require("moonlift.link_target_model")
M.link_plan_validate = require("moonlift.link_plan_validate")
M.link_command_plan = require("moonlift.link_command_plan")
M.link_execute = require("moonlift.link_execute")
M.vec_inspect = require("moonlift.vec_inspect")
M.region_compose = require("moonlift.region_compose")

local _mlua_run = require("moonlift.mlua_run")

M.std = require("moonlift.std")
M.views = M.std.views
M.buffer_view = M.std.buffer_view
M.host = M.std.host
M.lsp = require("moonlift.rpc_stdio_loop")

--- Hosted-Lua pipeline (current mlua_run behavior).

function M.loadstring(src, chunk_name, opts)
    return _mlua_run.loadstring(src, chunk_name, opts)
end

function M.loadfile(path, opts)
    return _mlua_run.loadfile(path, opts)
end

function M.dofile(path, opts, ...)
    return _mlua_run.dofile(path, opts, ...)
end

function M.eval(src, chunk_name, ...)
    return _mlua_run.eval(src, chunk_name, ...)
end

function M.current_runtime()
    return _mlua_run.current_runtime()
end

--- Object/shared emission through the hosted (PVM) pipeline.

function M.emit_object(src, path, name)
    local _ = _mlua_run
    local pvm = require("moonlift.pvm")
    local A2 = require("moonlift.asdl")
    local Pipeline = require("moonlift.frontend_pipeline")
    local Object = require("moonlift.back_object")

    local T = pvm.context(); A2.Define(T)
    local O = Object.Define(T)
    local program = Pipeline.Define(T).parse_and_lower(src, { site = "emit_object" }).program
    name = name or "moonlift_object"
    local artifact = O.compile(program, { module_name = name })
    local bytes = artifact:bytes()
    if path then
        local f = assert(io.open(path, "wb"))
        f:write(bytes)
        f:close()
    end
    return bytes
end

function M.emit_shared(src, path, name, opts)
    local _ = _mlua_run
    local pvm = require("moonlift.pvm")
    local A2 = require("moonlift.asdl")
    local Pipeline = require("moonlift.frontend_pipeline")
    local Object = require("moonlift.back_object")
    local LinkTarget = require("moonlift.link_target_model")
    local LinkValidate = require("moonlift.link_plan_validate")
    local LinkCommand = require("moonlift.link_command_plan")
    local LinkExecute = require("moonlift.link_execute")

    local T = pvm.context(); A2.Define(T)
    local Link = T.MoonLink
    local O = Object.Define(T)
    local LT = LinkTarget.Define(T)
    local LV = LinkValidate.Define(T)
    local LC = LinkCommand.Define(T)
    local LE = LinkExecute.Define(T)
    local program = Pipeline.Define(T).parse_and_lower(src, { site = "emit_shared" }).program

    name = name or "moonlift_shared"
    local keep_object = opts and opts.keep_object
    local object_path = keep_object or (os.tmpname() .. ".o")
    local object = O.compile(program, { module_name = name })
    object:write(object_path)

    local link_plan = Link.LinkPlan(
        LT.default_object(),
        Link.LinkArtifactSharedLibrary,
        Link.LinkTool(Link.LinkerSystemCc, Link.LinkPath("cc")),
        Link.LinkPath(path or "lib" .. name .. ".so"),
        { Link.LinkInputObject(Link.LinkPath(object_path)) },
        Link.LinkExportAll,
        Link.LinkExternRequireResolved,
        {}
    )
    local link_report = LV.validate(link_plan)
    if #link_report.issues ~= 0 then
        local msgs = {}
        for j = 1, #link_report.issues do msgs[#msgs + 1] = tostring(link_report.issues[j].message or link_report.issues[j]) end
        error("emit_shared link validation failed: " .. table.concat(msgs, "\n"), 2)
    end
    local commands = LC.plan(link_plan)
    local result = LE.execute(commands)
    if not keep_object then os.remove(object_path) end

    local LinkFailed = T.MoonLink.LinkFailed
    if pvm.classof(result) == LinkFailed then
        error("emit_shared link failed", 2)
    end
    return path
end

--- Internal: CLI entry point for standalone binaries.

M._mom_cli_run = function(argv)
    return require("moonlift.mom_cli").run(argv)
end

function M.context(opts)
    return M.pvm.context(opts)
end

function M.Define(T)
    return require("moonlift.asdl").Define(T)
end

--- Expose the unified moon.XXX quoting API (host.lua).
-- These override the backward-compatible mlua_run functions
-- with the new quoting/shaping API.
local host_api = require("moonlift.host")
for k, v in pairs(host_api) do
    if M[k] == nil then
        M[k] = v
    end
end
-- Explicitly re-export the unified stmts
M.stmts = host_api.stmts
M.func = host_api.func
M.region = host_api.region
M.expr_frag = host_api.expr_frag
M.struct = host_api.struct
M.union = host_api.union
M.extern = host_api.extern
M.type = host_api.type
M.expr = host_api.expr
M.params = host_api.params
M.fields = host_api.fields
M.variants = host_api.variants
M.conts = host_api.conts
M.blocks = host_api.blocks
M.entry_params = host_api.entry_params

return M
