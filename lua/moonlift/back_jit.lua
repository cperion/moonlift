-- Direct Moon2Back -> Rust/Cranelift tape replay.
--
-- This is the executable backend boundary for the current ASDL2 compiler path.
-- It encodes the flat Moon2Back.BackProgram command stream as BackCommandTape
-- and sends that single semantic tape to Rust.  It intentionally does not pass
-- through MoonliftBack, moonlift_legacy.asdl, or per-command Lua FFI replay.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")

ffi.cdef [[
typedef struct moonlift_jit_t moonlift_jit_t;
typedef struct moonlift_artifact_t moonlift_artifact_t;

const char* moonlift_last_error_message(void);

moonlift_jit_t* moonlift_jit_new(void);
void moonlift_jit_free(moonlift_jit_t*);
int moonlift_jit_symbol(moonlift_jit_t*, const char* name, const void* ptr);
moonlift_artifact_t* moonlift_jit_compile_tape(moonlift_jit_t*, const char* payload);

void moonlift_artifact_free(moonlift_artifact_t*);
const void* moonlift_artifact_getpointer(const moonlift_artifact_t*, const char* func);
]]

local M = {}

local function load_library(libpath)
    if libpath ~= nil then return ffi.load(libpath) end
    local ext, prefix
    if ffi.os == "OSX" then ext, prefix = ".dylib", "lib"
    elseif ffi.os == "Windows" then ext, prefix = ".dll", ""
    else ext, prefix = ".so", "lib" end
    local candidates = {
        "./target/release/" .. prefix .. "moonlift" .. ext,
        "./target/debug/" .. prefix .. "moonlift" .. ext,
        prefix .. "moonlift" .. ext,
        "moonlift",
    }
    local last_err
    for i = 1, #candidates do
        local ok, lib = pcall(ffi.load, candidates[i])
        if ok then return lib end
        last_err = lib
    end
    error("moonlift.back_jit: could not load Rust moonlift library: " .. tostring(last_err))
end

local function cstring(text)
    text = tostring(text)
    return ffi.new("char[?]", #text + 1, text)
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
    if arch == nil then error("moonlift.back_jit: could not detect host architecture for objdump: " .. tostring(err)) end
    arch = arch:gsub("%s+$", "")
    if arch == "x86_64" or arch == "amd64" then return "i386:x86-64" end
    if arch == "aarch64" or arch == "arm64" then return "aarch64" end
    error("moonlift.back_jit: unsupported host architecture for objdump utility: " .. tostring(arch))
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

function M.Define(T, opts)
    local Back = T.Moon2Back
    local Core = T.Moon2Core
    assert(Back and Core, "moonlift.back_jit.Define expects moonlift.asdl in the context")
    local lib = load_library(opts and opts.libpath or nil)
    local tape_api = require("moonlift.back_command_tape").Define(T)

    local function id_text(node) return type(node) == "string" and node or node.text end
    local function last_error()
        local p = lib.moonlift_last_error_message()
        return p ~= nil and ffi.string(p) or "unknown moonlift ffi error"
    end
    local function check_ok(rc, context)
        if rc == 0 then error(context .. ": " .. last_error(), 3) end
    end
    local function check_ptr(ptr, context)
        if ptr == nil or ptr == ffi.NULL then error(context .. ": " .. last_error(), 3) end
        return ptr
    end

    local Artifact = {}
    Artifact.__index = Artifact
    function Artifact:getpointer(func)
        return check_ptr(lib.moonlift_artifact_getpointer(self._raw, cstring(id_text(func))), "moonlift.back_jit artifact:getpointer")
    end
    function Artifact:getbytes(func, size)
        local n = tonumber(size or 128)
        if n == nil or n < 1 then error("moonlift.back_jit artifact:getbytes expects a positive byte count") end
        return ffi.string(ffi.cast("const char*", self:getpointer(func)), n)
    end
    function Artifact:hexbytes(func, size, cols) return format_hex_bytes(self:getbytes(func, size), cols) end
    function Artifact:writebytes(func, path, size)
        local out = assert(io.open(path, "wb")); out:write(self:getbytes(func, size)); out:close(); return path
    end
    function Artifact:disasm(func, opts)
        opts = opts or {}
        local bytes = tonumber(opts.bytes or 128)
        if bytes == nil or bytes < 1 then error("moonlift.back_jit artifact:disasm expects opts.bytes >= 1") end
        local path = opts.path or (os.tmpname() .. ".bin")
        self:writebytes(func, path, bytes)
        local machine = host_objdump_machine(opts.machine)
        local arch_flags = machine == "i386:x86-64" and "-Mintel " or ""
        local command = string.format("%s -D %s-b binary -m %s %s %s", opts.objdump or "objdump", arch_flags, shell_quote(machine), opts.flags or "", shell_quote(path))
        local out, err = run_command_capture(command)
        if not opts.keep then os.remove(path) end
        if out == nil then error("moonlift.back_jit artifact:disasm failed: " .. tostring(err)) end
        return out, path
    end
    function Artifact:free()
        if self._raw ~= nil and self._raw ~= ffi.NULL then lib.moonlift_artifact_free(self._raw); self._raw = ffi.NULL end
    end

    local Jit = {}
    Jit.__index = Jit
    function Jit:symbol(name, ptr)
        check_ok(lib.moonlift_jit_symbol(self._raw, cstring(name), ffi.cast("const void*", ptr)), "moonlift.back_jit jit:symbol")
    end
    function Jit:compile(program)
        assert(pvm.classof(program) == Back.BackProgram, "moonlift.back_jit compile expects Moon2Back.BackProgram")
        local tape = tape_api.encode(program)
        local raw_artifact = check_ptr(lib.moonlift_jit_compile_tape(self._raw, cstring(tape.payload)), "moonlift.back_jit jit:compile_tape")
        return setmetatable({ _raw = raw_artifact }, Artifact)
    end
    function Jit:peek(program, func, opts)
        local artifact = self:compile(program)
        local disasm, path = artifact:disasm(func, opts)
        return artifact, disasm, path
    end
    function Jit:free()
        if self._raw ~= nil and self._raw ~= ffi.NULL then lib.moonlift_jit_free(self._raw); self._raw = ffi.NULL end
    end

    return {
        lib = lib,
        jit = function()
            return setmetatable({ _raw = check_ptr(lib.moonlift_jit_new(), "moonlift.back_jit jit_new") }, Jit)
        end,
    }
end

return M
