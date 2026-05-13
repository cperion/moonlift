local bit = require("bit")
local Parser = require("moonlift.lisle.parser")
local Sema = require("moonlift.lisle.sema")
local Codegen = require("moonlift.lisle.codegen_lua")

local M = {}

M.CACHE_ABI = "lisle-cache-v2"

local function sh_quote(path)
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local function ensure_dir(path)
    os.execute("mkdir -p " .. sh_quote(path) .. " >/dev/null 2>&1")
end

local function fnv1a32(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, string.byte(s, i))
        h = bit.tobit(h * 16777619)
    end
    return string.format("%08x", bit.band(h, 0xffffffff))
end

function M.cache_dir()
    return os.getenv("MOONLIFT_LISLE_CACHE_DIR") or "/tmp/moonlift-lisle-cache"
end

function M.cache_key(src, module_name)
    local tag = M.CACHE_ABI .. "\0" .. tostring(module_name or "lisle") .. "\0"
    return fnv1a32(tag .. tostring(src or ""))
end

function M.cache_path(src, module_name)
    local dir = M.cache_dir()
    local key = M.cache_key(src, module_name)
    return dir, dir .. "/" .. key .. ".lua", key
end

function M.compile_source(src, module_name)
    local forms = Parser.parse(src)
    local spec = Sema.analyze(forms)
    local code = Codegen.emit(spec, module_name)
    return code, spec
end

function M.compile_file(path, module_name)
    local f, err = io.open(path, "rb")
    if not f then error("lisle compile: cannot read file " .. tostring(path) .. ": " .. tostring(err), 2) end
    local src = f:read("*a")
    f:close()
    return M.compile_source(src, module_name or path)
end

local function load_module_from_code(code, module_name, env, chunk_name)
    local chunk, err = load(code, chunk_name or ("@" .. tostring(module_name or "lisle")), "t", env or _ENV)
    if not chunk then error("lisle compile: " .. tostring(err), 2) end
    local builder = chunk()
    local mod = builder()
    return mod
end

function M.load_source(src, module_name, env, opts)
    opts = opts or {}

    local use_cache = (opts.cache ~= false) and (os.getenv("MOONLIFT_LISLE_NOCACHE") ~= "1")
    if use_cache then
        local dir, path, key = M.cache_path(src, module_name)
        local f = io.open(path, "rb")
        if f then
            local cached_code = f:read("*a")
            f:close()
            local ok, mod_or_err = pcall(load_module_from_code, cached_code, module_name, env, "@" .. path)
            if ok then
                return mod_or_err, cached_code, nil, { cached = true, path = path, key = key }
            end
            -- Corrupt cache entry; rebuild below.
        end

        local code, spec = M.compile_source(src, module_name)
        ensure_dir(dir)
        local wf = io.open(path, "wb")
        if wf then wf:write(code); wf:close() end
        local mod = load_module_from_code(code, module_name, env, "@" .. path)
        return mod, code, spec, { cached = false, path = path, key = key }
    end

    local code, spec = M.compile_source(src, module_name)
    local mod = load_module_from_code(code, module_name, env)
    return mod, code, spec, { cached = false }
end

function M.load_file(path, module_name, env, opts)
    local f, err = io.open(path, "rb")
    if not f then error("lisle compile: cannot read file " .. tostring(path) .. ": " .. tostring(err), 2) end
    local src = f:read("*a")
    f:close()
    return M.load_source(src, module_name or path, env, opts)
end

return M
