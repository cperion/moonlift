#!/usr/bin/env luajit

-- Remove the old public context-binding ceremony from Lua modules and call sites.
--
-- The migration is deliberately mechanical:
--   * `function M.<old binder>(...)` becomes a local `bind_context(...)` factory.
--   * modules with no remaining `M.*` namespace exports return `Define` directly.
--   * modules with namespace exports return `setmetatable(M, { __call = ... })`.
--   * call sites use `module(T)` instead of a named binder field.

local roots = { "lua/moonlift", "tests" }

local function read_file(path)
    local f, err = io.open(path, "rb")
    if not f then error(err) end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, data)
    local f, err = io.open(path, "wb")
    if not f then error(err) end
    f:write(data)
    f:close()
end

local function list_lua_files()
    local files = {}
    local cmd = "find " .. table.concat(roots, " ") .. " -type f -name '*.lua' | sort"
    local pipe = assert(io.popen(cmd, "r"))
    for path in pipe:lines() do
        if not path:match("^lua/ui/") and not path:match("^tests/ui/") then
            files[#files + 1] = path
        end
    end
    pipe:close()
    return files
end

local function convert_module_source(src)
    local changed = false

    src = src:gsub("function%s+M%.Define%s*%(", function()
        changed = true
        return "local function bind_context("
    end)

    if not changed then return src, false end

    src = src:gsub("M%.Define%s*%(", "bind_context(")

    local without_local_m = src:gsub("local%s+M%s*=%s*{}%s*\n", "")
    if not without_local_m:find("M%.") then
        src = without_local_m
        src = src:gsub("\nreturn%s+M%s*$", "\nreturn bind_context")
    else
        src = src:gsub("\nreturn%s+M%s*$", [[

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})]])
    end

    return src, true
end

local function rename_private_binder(src)
    local out = src:gsub("local%s+function%s+Define%s*%(", "local function bind_context(")
    out = out:gsub("%f[%w_]Define%f[^%w_]%s*%(", "bind_context(")
    return out, out ~= src
end

local function convert_calls(src)
    local out = src

    out = out:gsub("require%(([^%)\n]+)%)%.Define%s*%(", "require(%1)(")
    out = out:gsub("([%w_]+)%.Define%s*%(", "%1(")

    return out, out ~= src
end

local files_changed = 0
local modules_changed = 0
local calls_changed = 0

for _, path in ipairs(list_lua_files()) do
    local src = read_file(path)
    local out, module_changed = convert_module_source(src)
    local out1, rename_changed = rename_private_binder(out)
    local out2, call_changed = convert_calls(out1)

    if out2 ~= src then
        write_file(path, out2)
        files_changed = files_changed + 1
        if module_changed or rename_changed then modules_changed = modules_changed + 1 end
        if call_changed then calls_changed = calls_changed + 1 end
    end
end

io.stderr:write(string.format(
    "remove_define_ceremony: %d files changed, %d module definitions changed, %d files with callsite changes\n",
    files_changed,
    modules_changed,
    calls_changed
))
