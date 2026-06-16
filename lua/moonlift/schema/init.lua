-- Full clean Moon* schema authored as compact ASDL text.
--
-- The .asdl files in this directory are the source of truth.  A few C-schema
-- modules still live under lua/moonlift/c/ as Lua-builder modules because they
-- are outside this schema directory migration.

local Builder = require("moonlift.asdl_builder")
local AsdlText = require("moonlift.asdl_text")

local M = {}

local SCHEMA_DIR = "lua/moonlift/schema"

local SCHEMA_ASDL_MODULES = {
    "core",
    "back",
    "dasm",
    "link",
    "type",
    "open",
    "bind",
    "sem",
    "tree",
    "code",
    "graph",
    "flow",
    "value",
    "mem",
    "effect",
    "kernel",
    "schedule",
    "lower",
    "parse",
    "host",
    "source",
    "mlua",
    "editor",
    "lsp",
    "rpc",
}

-- pvm_surface.asdl is canonical ASDL text, but it is defined by
-- moonlift.pvm_surface_model after MoonPhase (still builder-authored outside
-- lua/moonlift/schema/) has been installed in the context.  Keep this explicit
-- so adding/removing schema/*.asdl files cannot silently drift from the loader.
local SCHEMA_ASDL_EXCLUSIONS = {
    pvm_surface = "loaded by moonlift.pvm_surface_model after MoonPhase is defined",
}

local function append_all(dst, src)
    for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
end

local function schema_asdl_path(name)
    return SCHEMA_DIR .. "/" .. name .. ".asdl"
end

local function basename_without_ext(file, ext)
    return file:sub(-#ext) == ext and file:sub(1, #file - #ext) or nil
end

local function list_schema_source_files()
    if not io or not io.popen then return nil end
    local cmd = "find " .. SCHEMA_DIR .. " -maxdepth 1 -type f \\( -name '*.asdl' -o -name '*.lua' \\) -printf '%f\\n' 2>/dev/null"
    local pipe = io.popen(cmd, "r")
    if not pipe then return nil end
    local out = pipe:read("*a") or ""
    pipe:close()
    if out == "" then return nil end
    local files = {}
    for file in out:gmatch("[^\n]+") do files[#files + 1] = file end
    table.sort(files)
    return files
end

function M.schema_asdl_modules_for_test()
    local copy = {}
    for i, name in ipairs(SCHEMA_ASDL_MODULES) do copy[i] = name end
    return copy
end

function M.assert_schema_directory_sources(files)
    files = files or list_schema_source_files()
    if not files then return true, "schema source directory unavailable" end

    local expected_asdl = {}
    for _, name in ipairs(SCHEMA_ASDL_MODULES) do
        if SCHEMA_ASDL_EXCLUSIONS[name] then
            error("moonlift.schema: " .. name .. " cannot be both loaded and intentionally excluded", 2)
        end
        expected_asdl[name] = true
    end
    for name in pairs(SCHEMA_ASDL_EXCLUSIONS) do expected_asdl[name] = true end

    local actual_asdl = {}
    for _, file in ipairs(files) do
        local lua_name = basename_without_ext(file, ".lua")
        local asdl_name = basename_without_ext(file, ".asdl")
        if lua_name and file ~= "init.lua" then
            error("moonlift.schema: Lua schema builder modules are forbidden under " .. SCHEMA_DIR .. ": " .. file, 2)
        elseif asdl_name then
            actual_asdl[asdl_name] = true
            if not expected_asdl[asdl_name] then
                error("moonlift.schema: unexpected ASDL source " .. SCHEMA_DIR .. "/" .. file .. " (add it to SCHEMA_ASDL_MODULES or SCHEMA_ASDL_EXCLUSIONS)", 2)
            end
        end
    end

    for _, name in ipairs(SCHEMA_ASDL_MODULES) do
        if not actual_asdl[name] then
            error("moonlift.schema: SCHEMA_ASDL_MODULES entry has no source file: " .. schema_asdl_path(name), 2)
        end
    end
    for name in pairs(SCHEMA_ASDL_EXCLUSIONS) do
        if not actual_asdl[name] then
            error("moonlift.schema: SCHEMA_ASDL_EXCLUSIONS entry has no source file: " .. schema_asdl_path(name), 2)
        end
    end

    return true
end

function M.schema(T)
    M.assert_schema_directory_sources()

    local A = Builder.Define(T)
    local modules = {}

    for _, name in ipairs(SCHEMA_ASDL_MODULES) do
        local modname = "moonlift.schema." .. name
        local path = schema_asdl_path(name)
        local text, source_name = AsdlText.load_text(modname, path)
        local schema = AsdlText.parse_schema(T, text, source_name or path)
        append_all(modules, schema.modules)
    end

    -- C frontend/backend schema modules live under lua/moonlift/c/ and are not
    -- part of the lua/moonlift/schema/*.asdl source directory yet.
    modules[#modules + 1] = require("moonlift.c.c_type")(A)
    modules[#modules + 1] = require("moonlift.c.c_ast")(A)

    return T.MoonAsdl.Schema(modules)
end

function M.Define(T)
    local DefineSchema = require("moonlift.context_define_schema")
    return DefineSchema.define(T, M.schema(T))
end

return M
