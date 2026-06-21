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
--   moon.emit_c_artifact(src [, opts])       — emit C/header/support artifact
--   moon.emit_c_file_artifact(path [, opts]) — execute .mlua and emit bundled C artifact
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

local _mlua_run = require("moonlift.mlua_run")

M.std = require("moonlift.std")
M.views = M.std.views
M.buffer_view = M.std.buffer_view
M.host = M.std.host
M.mlua = M.std.mlua
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

--- Load a .mlua module once and cache the result (like Lua require).
--- Searches for `name.mlua` in the current directory and relative to
--- the caller.
M._mlua_cache = {}
M._mlua_cache_order = {}
function M.require(name)
    if M._mlua_cache[name] then return M._mlua_cache[name] end
    -- Search paths: same as Lua require patterns but for .mlua
    local tried = {}
    for _, template in ipairs({
        "./?.mlua",
        "./?/init.mlua",
        "./experiments/mwui/?.mlua",
        "./experiments/mwui/?/init.mlua",
        "./experiments/mlui/?.mlua",
        "./experiments/mlui/?/init.mlua",
        "./lua/llpvm/native/?.mlua",
        "./lua/llpvm/native/?/init.mlua",
    }) do
        local path = template:gsub("%?", name)
        local f = io.open(path)
        if f then f:close()
            local ch = M.loadfile(path)
            local result = ch()
            M._mlua_cache[name] = result
            M._mlua_cache_order[#M._mlua_cache_order + 1] = name
            return result
        end
        tried[#tried + 1] = path
    end
    error("moon.require: module '" .. name .. "' not found; tried: " .. table.concat(tried, ", "))
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

function M.emit_c_artifact(src, path_or_opts, name, opts)
    if type(src) == "string" and src:find("moon%.require", 1) then
        error("moon.emit_c_artifact(src) accepts self-contained Moonlift source only; " ..
              "for .mlua modules that use moon.require, use moon.emit_c_file_artifact(path, opts) " ..
              "or moon.loadfile(path)():emit_c_artifact(opts)", 2)
    end
    local pvm = require("moonlift.pvm")
    local A2 = require("moonlift.asdl")
    local Pipeline = require("moonlift.frontend_pipeline")
    local CEmit = require("moonlift.c_emit")

    if type(path_or_opts) == "table" and opts == nil then
        opts = path_or_opts
        path_or_opts = nil
    end
    opts = opts or {}
    local T = pvm.context(); A2.Define(T)
    local pipeline_opts = { site = "emit_c_artifact", c_opts = opts, c_target = opts.c_target, target = opts.target, name = name or opts.name }
    local result = Pipeline.Define(T).parse_and_lower_c(src, pipeline_opts)
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

local function is_packable_result_value(v)
    if type(v) ~= "table" then return false end
    local kind = rawget(v, "kind") or rawget(v, "moonlift_quote_kind")
    return kind == "func" or kind == "extern_func"
        or kind == "region_frag" or kind == "expr_frag"
        or kind == "struct" or kind == "union"
end

local function pack_result_values(bundle, result)
    local packed = 0
    if is_packable_result_value(result) then
        bundle:pack(result)
        return 1
    end
    if type(result) == "table" then
        local keys = {}
        for k, v in pairs(result) do
            if type(k) == "string" and is_packable_result_value(v) then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for i = 1, #keys do
            bundle:pack(result[keys[i]])
            packed = packed + 1
        end
    end
    return packed
end

local function bundle_from_loaded_result(result, name, opts)
    opts = opts or {}
    if type(result) == "table" and type(result.to_bundle) == "function" then
        local bundle_opts = {}
        for k, v in pairs(opts) do bundle_opts[k] = v end
        bundle_opts.module_name = bundle_opts.module_name or name
        return result:to_bundle(bundle_opts)
    end

    local bundle = M.bundle(tostring(name or "mlua_module"):gsub("[^_%w]", "_"))
    if pack_result_values(bundle, result) > 0 then return bundle end
    error("loaded .mlua file did not return packable Moonlift values", 3)
end

function M.bundle_file(file_path, name, opts)
    local chunk = M.loadfile(file_path, opts)
    local result = chunk()
    name = name or tostring(file_path):match("([^/\\]+)%.mlua$") or "mlua_module"
    local bundle = M.bundle(tostring(name):gsub("[^_%w]", "_"))

    local dep_names = M._mlua_cache_order or {}
    for i = 1, #dep_names do
        pack_result_values(bundle, M._mlua_cache[dep_names[i]])
    end
    if pack_result_values(bundle, result) == 0 then
        error("loaded .mlua file did not return packable Moonlift values", 2)
    end
    return bundle
end

function M.emit_c_file_artifact(file_path, name_or_opts, opts)
    if type(name_or_opts) == "table" and opts == nil then
        opts = name_or_opts
        name_or_opts = nil
    end
    opts = opts or {}
    local name = name_or_opts or opts.name
    local bundle = M.bundle_file(file_path, name, opts)
    local emit_opts = {}
    for k, v in pairs(opts) do emit_opts[k] = v end
    emit_opts.name = emit_opts.name or name
    local artifact = bundle:emit_c_artifact(emit_opts)
    if opts.c_path or opts.source_path or opts.h_path or opts.header_path or opts.support_path or opts.combined_path or opts.single_path then
        artifact:write(opts)
    end
    return artifact
end

function M.compile_c(src, opts)
    opts = opts or {}
    local artifact = M.emit_c_artifact(src, opts)
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

function M.compile_c_file(file_path, opts)
    opts = opts or {}
    local artifact = M.emit_c_file_artifact(file_path, opts)
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
M.control = host_api.control

return M
