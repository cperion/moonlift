-- Host-native artifact registry.
--
-- NativeArtifact is a typed descriptor. The actual FFI artifact pointer is a
-- process-local host resource kept in this registry.

local pvm = require("moonlift.pvm")

local seq = 0
local entries = {}

local function next_id()
    seq = seq + 1
    return "native.artifact." .. tostring(seq)
end

local function bind_context(T)
    require("moonlift.compiler_model")(T)

    local Compiler = T.MoonCompiler

    local api = {}

    local NativeArtifact = {}
    NativeArtifact.__index = NativeArtifact

    function NativeArtifact:getpointer(func)
        local entry = entries[self.descriptor.id]
        if entry == nil then error("moonlift.native_runtime: native artifact has been freed or is unknown", 2) end
        return entry.artifact:getpointer(func)
    end

    function NativeArtifact:getbytes(func, size)
        local entry = entries[self.descriptor.id]
        if entry == nil then error("moonlift.native_runtime: native artifact has been freed or is unknown", 2) end
        return entry.artifact:getbytes(func, size)
    end

    function NativeArtifact:hexbytes(func, size, cols)
        local entry = entries[self.descriptor.id]
        if entry == nil then error("moonlift.native_runtime: native artifact has been freed or is unknown", 2) end
        return entry.artifact:hexbytes(func, size, cols)
    end

    function NativeArtifact:writebytes(func, path, size)
        local entry = entries[self.descriptor.id]
        if entry == nil then error("moonlift.native_runtime: native artifact has been freed or is unknown", 2) end
        return entry.artifact:writebytes(func, path, size)
    end

    function NativeArtifact:disasm(func, opts)
        local entry = entries[self.descriptor.id]
        if entry == nil then error("moonlift.native_runtime: native artifact has been freed or is unknown", 2) end
        return entry.artifact:disasm(func, opts)
    end

    function NativeArtifact:free()
        local entry = entries[self.descriptor.id]
        if entry ~= nil then
            entry.artifact:free()
            if entry.jit and entry.jit.free then entry.jit:free() end
            entries[self.descriptor.id] = nil
        end
    end

    function NativeArtifact:__tostring()
        return "moonlift.native_runtime.NativeArtifact(" .. tostring(self.descriptor.id) .. ")"
    end

    function api.instantiate_flatline(image, opts)
        opts = opts or {}
        local jit = require("moonlift.back_jit")(T, opts.jit_opts).jit()
        for name, ptr in pairs(opts.symbols or {}) do jit:symbol(name, ptr) end
        local artifact = jit:compile(image)
        local id = next_id()
        local descriptor = Compiler.NativeArtifact("cranelift", id, image, {})
        entries[id] = { artifact = artifact, jit = jit, descriptor = descriptor }
        return descriptor
    end

    function api.wrap(descriptor)
        assert(pvm.classof(descriptor) == Compiler.NativeArtifact, "moonlift.native_runtime.wrap expects MoonCompiler.NativeArtifact")
        return setmetatable({ descriptor = descriptor }, NativeArtifact)
    end

    function api.lookup(descriptor)
        return entries[descriptor.id]
    end

    function api.free(descriptor)
        return api.wrap(descriptor):free()
    end

    return api
end

return bind_context