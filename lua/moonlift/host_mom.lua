-- moonlift/host_mom.lua — executable source compiler entry point used by the
-- standalone mom binary.
--
-- This path uses the production Moonlift semantic pipeline: parse → open_expand →
-- open_validate → closure_convert → typecheck → layout → lower → validate → Cranelift.  It intentionally does
-- not use the incomplete parser-tape lowering path.

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local FrontendPipeline = require("moonlift.frontend_pipeline")
local BackJit = require("moonlift.back_jit")
local Object = require("moonlift.back_object")

local M = {}

local function compile_program(source)
    local T = pvm.context()
    A2.Define(T)
    local pipeline = FrontendPipeline.Define(T)
    local result = pipeline.parse_and_lower(source, { site = "MOM host pipeline" })
    return T, result.program
end

local Compiled = {}
Compiled.__index = Compiled

function Compiled:get(name)
    return self.artifact:getpointer(name)
end

function Compiled:cfunction(name)
    return self.artifact:cfunction(name)
end

function Compiled:free()
    if self.artifact then
        self.artifact:free()
        self.artifact = nil
    end
    if self.jit then
        self.jit:free()
        self.jit = nil
    end
end

function M.native_loadstring(src, _name)
    local T, program = compile_program(tostring(src))
    local J = BackJit.Define(T)
    local jit = J.jit()
    local artifact = jit:compile(program)
    return setmetatable({ jit = jit, artifact = artifact }, Compiled)
end

function M.native_loadfile(path)
    local f, err = io.open(path, "rb")
    if not f then error("native_loadfile: " .. tostring(err), 2) end
    local src = f:read("*a")
    f:close()
    return M.native_loadstring(src, path)
end

function M.native_dofile(path, opts, ...)
    local call = opts and opts.call or "main"
    local ret = opts and opts.ret or "i32"
    local args_i32 = opts and opts.args_i32 or {}
    local compiled = M.native_loadfile(path)
    local ptr = compiled:get(call)
    local ffi = require("ffi")
    local nargs = #args_i32
    local result
    if ret == "void" then
        if nargs == 0 then ffi.cast("void (*)()", ptr)()
        elseif nargs == 1 then ffi.cast("void (*)(int32_t)", ptr)(args_i32[1])
        elseif nargs == 2 then ffi.cast("void (*)(int32_t,int32_t)", ptr)(args_i32[1], args_i32[2])
        elseif nargs == 3 then ffi.cast("void (*)(int32_t,int32_t,int32_t)", ptr)(args_i32[1], args_i32[2], args_i32[3])
        elseif nargs == 4 then ffi.cast("void (*)(int32_t,int32_t,int32_t,int32_t)", ptr)(args_i32[1], args_i32[2], args_i32[3], args_i32[4])
        else error("native_dofile supports up to four i32 arguments", 2) end
    elseif ret == "i32" then
        local fn
        if nargs == 0 then fn = ffi.cast("int32_t (*)()", ptr)
        elseif nargs == 1 then fn = ffi.cast("int32_t (*)(int32_t)", ptr)
        elseif nargs == 2 then fn = ffi.cast("int32_t (*)(int32_t,int32_t)", ptr)
        elseif nargs == 3 then fn = ffi.cast("int32_t (*)(int32_t,int32_t,int32_t)", ptr)
        elseif nargs == 4 then fn = ffi.cast("int32_t (*)(int32_t,int32_t,int32_t,int32_t)", ptr)
        else error("native_dofile supports up to four i32 arguments", 2) end
        result = tonumber(fn(args_i32[1], args_i32[2], args_i32[3], args_i32[4]))
    else
        compiled:free()
        error("native_dofile: unsupported ret type " .. tostring(ret), 2)
    end
    compiled:free()
    return result
end

function M.compile(source)
    return M.native_loadstring(source)
end

function M.wire(source)
    local T, program = compile_program(tostring(source))
    return require("moonlift.back_command_binary").Define(T).encode(program)
end

function M.emit_object(source, path, module_name)
    local T, program = compile_program(tostring(source))
    local O = Object.Define(T)
    local artifact = O.compile(program, { module_name = module_name or "mom_object" })
    local bytes = artifact:bytes()
    if path then artifact:write(path) end
    return bytes
end

function M.status()
    return {
        ready = true,
        integration_ready = true,
        native_compiler_ready = false,
        pipeline = "production Lua semantic pipeline: parse/open_expand/open_validate/closure_convert/typecheck/layout/lower/validate/mlbt/cranelift",
        not_done = {
            "native .mlua source scanner/island pipeline",
            "native MoonTree AST materialization",
            "native open/bind/typecheck/layout phases",
            "native tree_to_back and control-region lowering parity",
            "native validation/diagnostics/vectorization parity",
            "replacement of Lua semantic compiler modules",
        },
    }
end

return setmetatable(M, {
    __call = function(_, source)
        return M.native_loadstring(source)
    end,
})
