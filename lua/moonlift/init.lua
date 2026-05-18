-- Public Moonlift Lua facade.
--
-- Unified entry API follows LuaJIT conventions:
--   moon.loadstring(src [, name [, opts]])  — compile and return a callable
--   moon.loadfile(path [, opts])            — compile and return a callable
--   moon.dofile(path [, opts, ...])         — load and immediately execute
--   moon.eval(src, ...)                     — loadstring + immediate call
--
-- Native (MOM) pipeline (explicit opt-in):
--   moon.native_loadstring(src [, name])    — compile through MOM native path
--   moon.native_loadfile(path)              — compile through MOM native path
--   moon.native_dofile(path [, opts, ...])  — compile and execute through MOM
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
local _host_mom = require("moonlift.host_mom")

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

--- Native (MOM) pipeline.

function M.native_loadstring(src, name)
    return _host_mom.native_loadstring(src, name)
end

function M.native_loadfile(path)
    local f, err = io.open(path, "rb")
    if not f then error("native_loadfile: " .. tostring(err), 2) end
    local src = f:read("*a")
    f:close()
    return _host_mom.native_loadstring(src, path)
end

function M.native_dofile(path, opts, ...)
    local call = opts and opts.call or "main"
    local ret = opts and opts.ret or "i32"
    local args_i32 = opts and opts.args_i32 or {}
    local compiled = M.native_loadfile(path)
    local ptr = compiled:get(call)
    local ffi = require("ffi")
    local nargs = #args_i32
    if ret == "void" then
        if nargs == 0 then ffi.cast("void (*)()", ptr)()
        elseif nargs == 1 then ffi.cast("void (*)(int32_t)", ptr)(args_i32[1])
        elseif nargs == 2 then ffi.cast("void (*)(int32_t,int32_t)", ptr)(args_i32[1], args_i32[2])
        elseif nargs == 3 then ffi.cast("void (*)(int32_t,int32_t,int32_t)", ptr)(args_i32[1], args_i32[2], args_i32[3])
        elseif nargs == 4 then ffi.cast("void (*)(int32_t,int32_t,int32_t,int32_t)", ptr)(args_i32[1], args_i32[2], args_i32[3], args_i32[4])
        else error("native_dofile supports up to four i32 arguments")
        end
        compiled:free()
        return
    end
    if ret == "i32" then
        local fn
        if nargs == 0 then fn = ffi.cast("int32_t (*)()", ptr)
        elseif nargs == 1 then fn = ffi.cast("int32_t (*)(int32_t)", ptr)
        elseif nargs == 2 then fn = ffi.cast("int32_t (*)(int32_t,int32_t)", ptr)
        elseif nargs == 3 then fn = ffi.cast("int32_t (*)(int32_t,int32_t,int32_t)", ptr)
        elseif nargs == 4 then fn = ffi.cast("int32_t (*)(int32_t,int32_t,int32_t,int32_t)", ptr)
        else error("native_dofile supports up to four i32 arguments")
        end
        local result = fn(args_i32[1], args_i32[2], args_i32[3], args_i32[4])
        compiled:free()
        return tonumber(result)
    end
    error("native_dofile: unsupported ret type " .. tostring(ret))
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

--- Internal: backward-compatible aliases.

M.host_mom = _host_mom

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

return M
