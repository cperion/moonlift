-- Direct MoonBack -> host-native relocatable object emission.
--
-- Encodes the flat MoonBack.BackProgram command stream as the MLBT v3 binary
-- wire format and sends it to the Rust/Cranelift object backend for .o output.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")

ffi.cdef [[
typedef struct moonlift_bytes_t { uint8_t* data; size_t len; } moonlift_bytes_t;

const char* moonlift_last_error_message(void);
int moonlift_object_compile_binary(const uint8_t* data, size_t len, const char* module_name, moonlift_bytes_t* out);
void moonlift_bytes_free(uint8_t* data, size_t len);
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
    error("moonlift.back_object: could not load Rust moonlift library: " .. tostring(last_err))
end

local function cstring(text)
    text = tostring(text)
    return ffi.new("char[?]", #text + 1, text)
end

function M.Define(T, opts)
    local Back = T.MoonBack or T.MoonBack
    assert(Back, "moonlift.back_object.Define expects MoonBack/MoonBack in the context")
    local lib = load_library(opts and opts.libpath or nil)
    local binary_api = require("moonlift.back_command_binary").Define(T)

    local function last_error()
        local p = lib.moonlift_last_error_message()
        return p ~= nil and ffi.string(p) or "unknown moonlift ffi error"
    end
    local function check_ok(rc, context)
        if rc == 0 then error(context .. ": " .. last_error(), 3) end
    end

    local ObjectArtifact = {}
    ObjectArtifact.__index = ObjectArtifact
    function ObjectArtifact:bytes()
        return self._bytes
    end
    function ObjectArtifact:write(path)
        local out = assert(io.open(path, "wb"))
        out:write(self._bytes)
        out:close()
        return path
    end

    local function compile(program, compile_opts)
        assert(pvm.classof(program) == Back.BackProgram, "moonlift.back_object compile expects MoonBack.BackProgram")
        compile_opts = compile_opts or {}
        local payload = binary_api.encode(program)
        local buf = ffi.new("uint8_t[?]", #payload)
        ffi.copy(buf, payload, #payload)
        local out = ffi.new("moonlift_bytes_t[1]")
        check_ok(
            lib.moonlift_object_compile_binary(buf, #payload, cstring(compile_opts.module_name or "moonlift_object"), out),
            "moonlift.back_object compile_binary"
        )
        local bytes = ffi.string(out[0].data, tonumber(out[0].len))
        lib.moonlift_bytes_free(out[0].data, out[0].len)
        return setmetatable({ _bytes = bytes }, ObjectArtifact)
    end

    return {
        lib = lib,
        compile = compile,
    }
end

return M
