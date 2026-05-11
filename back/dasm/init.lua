-- back/dasm/init.lua — DynASM backend entry point
--
-- Drop-in replacement for moonlift.back_jit / moonlift.hosted_jit.
-- Implements Define(T) → { jit = function() ... end }.

local M = {}

function M.Define(T, opts)
    local mod = require("back.dasm.compile")

    local Artifact = {}
    Artifact.__index = Artifact
    function Artifact:getpointer(fid)
        return self._c:getpointer(fid)
    end
    function Artifact:free()
        if self._c then self._c:free(); self._c = nil end
    end

    local Jit = {}
    Jit.__index = Jit
    function Jit:compile(program)
        local compiled = mod.compile(program)
        return setmetatable({_c = compiled}, Artifact)
    end
    function Jit:free() end

    return { jit = function() return setmetatable({}, Jit) end }
end

return M
