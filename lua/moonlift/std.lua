-- Moonlift standard library facade.
--
-- This module is intentionally a Lua convenience surface over existing ASDL/PVM
-- facts and executable Moonlift libraries.  It does not introduce a second JSON
-- runtime or a separate compiler IR; JSON still goes through the indexed-tape
-- Moonlift library path.

local M = {}

M.pvm = require("moonlift.pvm")
M.host = require("moonlift.host")
M.mlua = require("moonlift.host_quote")
M.views = require("moonlift.buffer_view")
M.buffer_view = M.views

local json_compiled = nil

local Json = {}
M.json = Json

local function json_library()
    return require("moonlift.json_library")
end

local function json_codegen()
    return require("moonlift.json_codegen")
end

function Json.library()
    return json_library()
end

function Json.codegen()
    return json_codegen()
end

function Json.source()
    return json_library().source()
end

function Json.compile(opts)
    opts = opts or {}
    if json_compiled ~= nil and not opts.fresh then return json_compiled end
    local compiled, err = json_library().compile()
    if not compiled then return nil, err end
    if not opts.fresh then json_compiled = compiled end
    return compiled, nil
end

function Json.compiled()
    local compiled, err = Json.compile()
    if not compiled then error("moonlift.std.json compile failed at " .. tostring(err and err.stage), 2) end
    return compiled
end

function Json.free()
    if json_compiled and json_compiled.artifact then json_compiled.artifact:free() end
    json_compiled = nil
end

function Json.decoder(opts)
    return json_library().doc_decoder(Json.compiled(), opts)
end

function Json.decode(src, opts)
    return Json.decoder(opts):decode(src)
end

function Json.parse(src, opts)
    return json_library().parse(Json.compiled(), src, opts)
end

function Json.get_i32(src, key, opts)
    local doc, err = Json.decode(src, opts)
    if not doc then return nil, err end
    return doc:get_i32(key)
end

function Json.get_bool(src, key, opts)
    local doc, err = Json.decode(src, opts)
    if not doc then return nil, err end
    return doc:get_bool(key)
end

function Json.project(fields, opts)
    return json_codegen().project(fields, opts)
end

function Json.projector(fields, opts)
    return Json.project(fields, opts)
end

function Json.decode_project(fields, src, opts)
    local projector = Json.project(fields, opts)
    local out, err = projector:decode_table(src)
    projector:free()
    return out, err
end

function Json.decode_project_view(fields, src, opts)
    local projector = Json.project(fields, opts)
    local view = projector:new_view(opts and opts.view or nil)
    local out, err = projector:decode_into_view(src, view)
    projector:free()
    return out, err
end

Json.null = json_library().null

local Builtins = {}
M.builtins = Builtins

function Builtins.source(name)
    if name == "json" then return Json.source() end
    error("unknown Moonlift builtin library: " .. tostring(name), 2)
end

function Builtins.compile(name, opts)
    if name == "json" then return Json.compile(opts) end
    error("unknown Moonlift builtin library: " .. tostring(name), 2)
end

return M
