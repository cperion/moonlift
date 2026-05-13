-- back/dasm/init.lua — DynASM backend entry point
--
-- Drop-in replacement for moonlift.back_jit.
-- Implements Define(T) → { jit = function() ... end } with the same
-- API shape as the Cranelift back_jit module.

local M = {}

function M.Define(T, opts)
    local Back = T.MoonBack or T.MoonBack
    assert(Back, "back.dasm.Define expects MoonBack in the context")

    require("back.dasm.model").set_context(T)
    local mod = require("back.dasm.compile")
    local isel = require("back.dasm.isel_x64")

    local function id_text(node)
        return type(node) == "string" and node or (node and node.text) or nil
    end

    local Artifact = {}
    Artifact.__index = Artifact
    function Artifact:getpointer(func)
        local k = id_text(func)
        return self._c:getpointer(k)
    end
    function Artifact:getbytes(func, size)
        local n = tonumber(size or 128)
        local ptr = self:getpointer(func)
        return require("ffi").string(require("ffi").cast("const char*", ptr), n)
    end
    function Artifact:free()
        if self._c then self._c:free(); self._c = nil end
    end

    local Jit = {}
    Jit.__index = Jit
    function Jit:symbol(name, ptr)
        self._symbols[name] = ptr
    end
    function Jit:compile(program)
        local compiled = mod.compile(program, self._symbols)
        return setmetatable({_c = compiled}, Artifact)
    end
    function Jit:reload_rules(path)
        local ok, err = isel.reload_lisle_dispatch(path)
        if not ok then error(err, 2) end
        return true
    end
    function Jit:watch_rules(enabled)
        return isel.set_lisle_autoreload(enabled ~= false)
    end
    function Jit:free() end

    return {
        jit = function()
            return setmetatable({_symbols = {}}, Jit)
        end,
    }
end

return M
