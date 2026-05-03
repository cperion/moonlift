-- Hosted JIT backend.
--
-- This module has the same public shape as moonlift.back_jit, but it runs inside
-- the Rust host binary.  The host owns one moonlift::Jit and exposes
-- _host_compile(tape) -> HostedArtifact userdata.  No cdylib FFI JIT boundary is
-- used on this path.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")

local M = {}

local function id_text(node)
    return type(node) == "string" and node or node.text
end

function M.Define(T, _opts)
    local Back = T.MoonBack
    local tape_api = require("moonlift.back_command_tape").Define(T)

    local Artifact = {}
    Artifact.__index = Artifact

    function Artifact:getpointer(func)
        local ptr = self._raw:getpointer(id_text(func))
        if ptr == 0 then error("hosted artifact:getpointer returned null", 2) end
        return ffi.cast("const void *", ptr)
    end

    function Artifact:cfunction(func)
        return self._raw:cfunction(id_text(func))
    end

    function Artifact:call(func, ...)
        return self._raw:call(id_text(func), ...)
    end

    function Artifact:free()
        if self._raw ~= nil then
            self._raw:free()
            self._raw = nil
        end
    end

    local Jit = {}
    Jit.__index = Jit

    function Jit:symbol(name, ptr)
        _host_symbol(name, tonumber(ffi.cast("uintptr_t", ptr)))
    end

    function Jit:compile(program)
        assert(pvm.classof(program) == Back.BackProgram, "hosted_jit compile expects MoonBack.BackProgram")
        local tape = tape_api.encode(program)
        local artifact = assert(_host_compile(tape.payload), "hosted compile failed")
        return setmetatable({ _raw = artifact }, Artifact)
    end

    function Jit:peek(_program, _func, _opts)
        error("hosted_jit: disassembly/peek is not wired for hosted artifacts yet", 2)
    end

    function Jit:free() end

    return {
        jit = function() return setmetatable({}, Jit) end,
    }
end

return M
