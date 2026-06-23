-- Public Moonlift Lua facade — DSL-only.
--
-- Entry API:
--   moon.loadstring(src [, name])  — compile DSL source and return a callable module
--   moon.loadfile(path)            — compile DSL file and return a callable module
--   moon.dofile(path, ...)         — load and immediately execute
--   moon.eval(src, ...)            — loadstring + immediate call
--
-- Object emission (hosted pipeline):
--   moon.emit_object(decl [, path [, name]])
--   moon.emit_shared(decl [, path [, name [, opts]]])
--   moon.emit_c_artifact(decl [, opts])
--
-- Low-level modules are exposed for direct use.

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
M.ast = require("moonlift.ast")
M.dsl = require("moonlift.dsl")
M.back_program = require("moonlift.back_program")
M.back_target_model = require("moonlift.back_target_model")
M.back_inspect = require("moonlift.back_inspect")
M.back_diagnostics = require("moonlift.back_diagnostics")
M.back_object = require("moonlift.back_object")
M.link_target_model = require("moonlift.link_target_model")
M.link_plan_validate = require("moonlift.link_plan_validate")
M.link_command_plan = require("moonlift.link_command_plan")
M.link_execute = require("moonlift.link_execute")
M.region_compose = require("moonlift.region_compose")
M.code_type = require("moonlift.code_type")
M.code_validate = require("moonlift.code_validate")
M.tree_to_code = require("moonlift.tree_to_code")
M.code_to_c = require("moonlift.code_to_c")
M.code_to_back = require("moonlift.code_to_back")
M.c_validate = require("moonlift.c_validate")
M.c_emit = require("moonlift.c_emit")
M.c_helpers = require("moonlift.c_helpers")
M.c_tcc = require("moonlift.c_tcc")

M.lsp = require("moonlift.rpc_stdio_loop")

--- Hosted load/compile via DSL.

function M.loadstring(src, chunk_name)
    local ds = require("moonlift.dsl")
    return ds.load(src, chunk_name or "=loadstring")
end

function M.loadfile(path)
    local f = assert(io.open(path, "r"))
    local src = f:read("*a")
    f:close()
    return M.loadstring(src, path)
end

function M.dofile(path, ...)
    local chunk = M.loadfile(path)
    return chunk(...)
end

function M.eval(src, chunk_name, ...)
    local chunk = M.loadstring(src, chunk_name or "=eval")
    return chunk(...)
end

--- Object/shared emission from a DSL declaration.

function M.emit_object(decl, path, name)
    local pvm = require("moonlift.pvm")
    local A2 = require("moonlift.asdl")
    local Pipeline = require("moonlift.frontend_pipeline")
    local Object = require("moonlift.back_object")

    local T = pvm.context(); A2.Define(T)
    local O = Object.Define(T)
    local module_ast = rawget(decl, "__module_ast") or decl
    local result = Pipeline.Define(T).lower_module(module_ast, { site = "emit_object" })
    name = name or "moonlift_object"
    local artifact = O.compile(result.program, { module_name = name })
    local bytes = artifact:bytes()
    if path then
        local f = assert(io.open(path, "wb"))
        f:write(bytes)
        f:close()
    end
    return bytes
end

function M.emit_shared(decl, path, name, opts)
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
    local module_ast = rawget(decl, "__module_ast") or decl
    local result = Pipeline.Define(T).lower_module(module_ast, { site = "emit_shared" })

    name = name or "moonlift_shared"
    local keep_object = opts and opts.keep_object
    local object_path = keep_object or (os.tmpname() .. ".o")
    local object = O.compile(result.program, { module_name = name })
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
    local result_link = LE.execute(commands)
    if not keep_object then os.remove(object_path) end

    local LinkFailed = T.MoonLink.LinkFailed
    if pvm.classof(result_link) == LinkFailed then
        error("emit_shared link failed", 2)
    end
    return path
end

function M.emit_c_artifact(decl, path_or_opts, name, opts)
    if type(path_or_opts) == "table" and opts == nil then
        opts = path_or_opts
        path_or_opts = nil
    end
    opts = opts or {}
    local pvm = require("moonlift.pvm")
    local A2 = require("moonlift.asdl")
    local Pipeline = require("moonlift.frontend_pipeline")
    local CEmit = require("moonlift.c_emit")

    local T = pvm.context(); A2.Define(T)
    local module_ast = rawget(decl, "__module_ast") or decl
    local pipeline_opts = { site = "emit_c_artifact", c_opts = opts, c_target = opts.c_target, target = opts.target, name = name or opts.name }
    local result = Pipeline.Define(T).lower_module_to_c(module_ast, pipeline_opts)
    if #result.c_report.issues ~= 0 then
        local msgs = {}
        for i = 1, #result.c_report.issues do msgs[#msgs + 1] = tostring(result.c_report.issues[i]) end
        error("emit_c_artifact validation failed: " .. table.concat(msgs, "\n"), 2)
    end
    local artifact = CEmit.Define(T).emit_artifact(result.c_unit, opts)
    function artifact:write(write_opts)
        write_opts = write_opts or {}
        if type(write_opts) == "string" then write_opts = { c_path = write_opts } end
        local function write(path, text)
            local f = assert(io.open(path, "wb"))
            f:write(text or "")
            f:close()
        end
        if write_opts.c_path or write_opts.source_path then write(write_opts.c_path or write_opts.source_path, self.source) end
        if write_opts.h_path or write_opts.header_path then write(write_opts.h_path or write_opts.header_path, self.header) end
        if write_opts.support_path then write(write_opts.support_path, self.support) end
        if write_opts.combined_path or write_opts.single_path then write(write_opts.combined_path or write_opts.single_path, self.combined) end
        return self
    end
    if path_or_opts then artifact:write(path_or_opts) end
    if opts.c_path or opts.source_path or opts.h_path or opts.header_path or opts.support_path or opts.combined_path or opts.single_path then
        artifact:write(opts)
    end
    return artifact
end

function M.compile_c(decl, opts)
    opts = opts or {}
    local artifact = M.emit_c_artifact(decl, opts)
    if opts.c_path or opts.source_path or opts.h_path or opts.header_path or opts.support_path or opts.combined_path or opts.single_path then
        artifact:write(opts)
    end
    local c_src = artifact.combined
    local CTcc = require("moonlift.c_tcc")
    if opts.runner == "libtcc" or opts.use_libtcc or os.getenv("MOONLIFT_C_USE_LIBTCC") == "1" then
        local session, err = CTcc.compile(c_src, opts.libtcc_opts or { libraries = { "m" } })
        if not session then error(err and err.message or "libtcc compile failed", 2) end
        return session, c_src
    end
    return c_src
end

function M.context(opts)
    return M.pvm.context(opts)
end

function M.Define(T)
    return require("moonlift.asdl").Define(T)
end

return M
