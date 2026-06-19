-- Hosted JIT backend.
--
-- This module has the same public shape as moonlift.back_jit, but it runs inside
-- the Rust host binary.  The host owns one moonlift::Jit and exposes
-- _host_compile_binary(payload): HostedArtifact userdata. No cdylib FFI JIT
-- boundary is used on this path.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")

local M = {}

local function id_text(node)
    return type(node) == "string" and node or node.text
end

local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", [['"'"']]) .. "'"
end

local function run_command_capture(command)
    local pipe, err = io.popen(command .. " 2>&1", "r")
    if pipe == nil then return nil, err or ("could not start command: " .. tostring(command)) end
    local out = pipe:read("*a")
    local ok, why, code = pipe:close()
    if ok == nil or ok == false then
        local suffix = why ~= nil and code ~= nil and (" (" .. tostring(why) .. " " .. tostring(code) .. ")") or ""
        return nil, (out ~= "" and out or ("command failed: " .. tostring(command))) .. suffix
    end
    return out
end

local function host_objdump_machine(explicit_machine)
    if explicit_machine ~= nil then return explicit_machine end
    local arch, err = run_command_capture("uname -m")
    if arch == nil then error("hosted_jit: could not detect host architecture for objdump: " .. tostring(err)) end
    arch = arch:gsub("%s+$", "")
    if arch == "x86_64" or arch == "amd64" then return "i386:x86-64" end
    if arch == "aarch64" or arch == "arm64" then return "aarch64" end
    error("hosted_jit: unsupported host architecture for objdump utility: " .. tostring(arch))
end

local function format_hex_bytes(bytes, cols)
    cols = cols or 16
    local lines = {}
    for i = 1, #bytes, cols do
        local chunk = {}
        local last = math.min(i + cols - 1, #bytes)
        for j = i, last do chunk[#chunk + 1] = string.format("%02x", bytes:byte(j)) end
        lines[#lines + 1] = string.format("%04x: %s", i - 1, table.concat(chunk, " "))
    end
    return table.concat(lines, "\n")
end

function M.Define(T, _opts)
    local Back = T.MoonBack
    local binary_api = require("moonlift.back_command_binary").Define(T)

    local Artifact = {}
    Artifact.__index = Artifact

    function Artifact:getpointer(func)
        local ptr = self._raw:getpointer(id_text(func))
        if ptr == 0 then error("hosted artifact:getpointer returned null", 2) end
        return ffi.cast("const void *", ptr)
    end

    function Artifact:getbytes(func, size)
        local n = tonumber(size or 128)
        if n == nil or n < 1 then error("hosted_jit artifact:getbytes expects a positive byte count") end
        return ffi.string(ffi.cast("const char*", self:getpointer(func)), n)
    end

    function Artifact:hexbytes(func, size, cols)
        return format_hex_bytes(self:getbytes(func, size), cols)
    end

    function Artifact:writebytes(func, path, size)
        local out = assert(io.open(path, "wb"))
        out:write(self:getbytes(func, size))
        out:close()
        return path
    end

    function Artifact:disasm(func, opts)
        opts = opts or {}
        local bytes = tonumber(opts.bytes or 128)
        if bytes == nil or bytes < 1 then error("hosted_jit artifact:disasm expects opts.bytes >= 1") end
        local path = opts.path or (os.tmpname() .. ".bin")
        self:writebytes(func, path, bytes)
        local machine = host_objdump_machine(opts.machine)
        local arch_flags = machine == "i386:x86-64" and "-Mintel " or ""
        local command = string.format("%s -D %s-b binary -m %s %s %s", opts.objdump or "objdump", arch_flags, shell_quote(machine), opts.flags or "", shell_quote(path))
        local out, err = run_command_capture(command)
        if not opts.keep then os.remove(path) end
        if out == nil then error("hosted_jit artifact:disasm failed: " .. tostring(err)) end
        return out, path
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
        local payload = binary_api.encode(program)
        local artifact = assert(_host_compile_binary(payload), "hosted binary compile failed")
        return setmetatable({ _raw = artifact }, Artifact)
    end

    function Jit:peek(program, func, opts)
        local artifact = self:compile(program)
        local disasm, path = artifact:disasm(func, opts)
        return artifact, disasm, path
    end

    function Jit:free() end

    return {
        jit = function() return setmetatable({}, Jit) end,
    }
end

return M
