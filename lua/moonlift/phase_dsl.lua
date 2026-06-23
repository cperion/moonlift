-- LLB surface for complete MoonPhase compiler-package graph values.

local llb = require("llb")
local pvm = require("moonlift.pvm")
local PhaseModel = require("moonlift.phase_model")
local PhaseValidate = require("moonlift.phase_validate")

local M = {}

local function ensure(T)
    PhaseModel.Define(T)
    return T.MoonPhase
end

local T = pvm.context()
local P = ensure(T)

local function type_ref(spec)
    if type(spec) == "table" then
        local cls = pvm.classof(spec)
        if cls == P.TypeRef or spec == P.TypeRefAny or cls == P.TypeRefValue then return spec end
        if llb.is(spec, "Capture") and llb.is(spec.subject, "Symbol") then
            local module_name = spec.subject.text
            local type_name = spec.value
            if llb.is(type_name, "Symbol") or llb.is(type_name, "Name") then type_name = type_name.text end
            if type(module_name) == "string" and type(type_name) == "string" then
                return P.TypeRef(module_name, type_name)
            end
        end
        if llb.is(spec, "Expr") and spec.kind == "field" and llb.is(spec.base, "Symbol") and type(spec.field) == "string" then
            return P.TypeRef(spec.base.text, spec.field)
        end
    end
    if spec == nil or spec == "any" or spec == "*" then return P.TypeRefAny end
    if type(spec) == "string" then
        error("phase_dsl: world type refs use structured names, write world. name [MoonTree.Module], not world. name [\"MoonTree.Module\"]", 3)
    end
    error("phase_dsl: type ref must be a structured MoonPhase.TypeRef or dotted LLB symbol like MoonTree.Module", 3)
end

local function ident_text(v, what)
    if llb.is(v, "Name") or llb.is(v, "Symbol") then return v.text end
    if type(v) == "string" then return v end
    error("phase_dsl: expected " .. what, 3)
end

local function world_id(v) return P.WorldId(ident_text(v, "world name")) end
local function phase_id(v) return P.PhaseId(ident_text(v, "phase name")) end
local function machine_id(v) return P.MachineId(ident_text(v, "machine name")) end
local function root_id(v) return P.RootId(ident_text(v, "root name")) end
local function package_id(v) return P.PackageId(ident_text(v, "package name")) end

local function cache_policy(spec)
    if spec == P.CacheIdentity or spec == P.CacheNode or spec == P.CacheFull or spec == P.CacheNone then return spec end
    spec = ident_text(spec or "identity", "cache policy")
    if spec == "identity" then return P.CacheIdentity end
    if spec == "node" then return P.CacheNode end
    if spec == "full" or spec == "args" then return P.CacheFull end
    if spec == "none" then return P.CacheNone end
    error("phase_dsl: unknown cache policy " .. tostring(spec), 3)
end

local function machine_abi(spec)
    if spec == P.MachineAbiStatusReturning or spec == P.MachineAbiPure or spec == P.MachineAbiProcess or spec == P.MachineAbiC or spec == P.MachineAbiCranelift then return spec end
    spec = ident_text(spec or "status_returning", "machine ABI")
    if spec == "status" or spec == "status_returning" then return P.MachineAbiStatusReturning end
    if spec == "pure" then return P.MachineAbiPure end
    if spec == "process" or spec == "process_events" then return P.MachineAbiProcess end
    if spec == "c" or spec == "c_abi" then return P.MachineAbiC end
    if spec == "cranelift" then return P.MachineAbiCranelift end
    error("phase_dsl: unknown machine ABI " .. tostring(spec), 3)
end

local function classof(v) return pvm.classof(v) end

local function part(kind, value)
    return { __moon_phase_dsl_part = kind, value = value }
end

local function part_kind(v)
    return type(v) == "table" and rawget(v, "__moon_phase_dsl_part") or nil
end

local function unwrap(v)
    if part_kind(v) then return v.value end
    return v
end

local function stage_machine_ref(v)
    if llb.is_stage(v) and llb.stage_head(v) == "machine" and v.raw and v.raw.name then
        return machine_id(v.raw.name)
    end
    return nil
end

local function string_array(v, what)
    if v == nil then return {} end
    if type(v) ~= "table" then error("phase_dsl: " .. what .. " expects table", 3) end
    local out = {}
    for i = 1, #v do out[#out + 1] = tostring(v[i]) end
    return out
end

local function impl_from(kind, spec)
    spec = spec or {}
    if kind == "moonlift" then return P.ImplMoonlift(assert(spec.module or spec.module_name, "impl.moonlift requires module"), assert(spec.func or spec.function_name or spec.symbol, "impl.moonlift requires func/function_name/symbol")) end
    if kind == "lua" then return P.ImplLua(assert(spec.module or spec.module_name, "impl.lua requires module"), assert(spec.func or spec.function_name or spec.symbol, "impl.lua requires func/function_name/symbol")) end
    if kind == "c" then return P.ImplC(assert(spec.symbol, "impl.c requires symbol")) end
    if kind == "cranelift" then return P.ImplCranelift(assert(spec.symbol, "impl.cranelift requires symbol")) end
    if kind == "external" then return P.ImplExternal(assert(spec.capability, "impl.external requires capability")) end
    error("phase_dsl: unknown impl kind " .. tostring(kind), 3)
end

local g = llb.grammar

local Lang = llb.define "MoonPhaseDsl" {
    g.role .package_body { kind = "array" },
    g.role .machine_body { kind = "array" },
    g.role .phase_body { kind = "array" },
    g.role .root_body { kind = "array" },
    g.role .record { kind = "record" },

    g.head .package {
        g.slot .name [g.string],
        g.slot .body [g.package_body],
        emit = function(n)
            local worlds, machines, phases, roots = {}, {}, {}, {}
            for i = 1, #n.body do
                local item = unwrap(n.body[i])
                local cls = classof(item)
                if cls == P.World then worlds[#worlds + 1] = item
                elseif cls == P.Machine then machines[#machines + 1] = item
                elseif cls == P.Phase then phases[#phases + 1] = item
                elseif cls == P.Root then roots[#roots + 1] = item
                else error("phase_dsl: package body expects world, machine, phase, or root", 2) end
            end
            return PhaseValidate.assert_valid(P.Package(package_id(n.name), worlds, machines, phases, roots))
        end,
    },

    g.head .world {
        g.slot .name [g.name],
        g.slot .ty [g.value] { channel = "index:value" },
        emit = function(n) return P.World(world_id(n.name), type_ref(n.ty)) end,
    },

    g.head .machine {
        g.slot .name [g.name],
        g.slot .body [g.machine_body],
        emit = function(n)
            local input, output, diagnostics, abi, impl, capabilities = nil, nil, nil, P.MachineAbiStatusReturning, nil, {}
            for i = 1, #n.body do
                local item = unwrap(n.body[i])
                local kind = part_kind(n.body[i])
                if kind == "from" then input = item
                elseif kind == "to" then output = item
                elseif kind == "diagnostics" then diagnostics = item
                elseif kind == "abi" then abi = item
                elseif kind == "impl" then impl = item
                elseif kind == "capabilities" then capabilities = item
                else error("phase_dsl: unexpected machine entry", 2) end
            end
            if not input then error("phase_dsl: machine requires from. world", 2) end
            if not output then error("phase_dsl: machine requires to. world", 2) end
            if not impl then error("phase_dsl: machine requires impl. kind {...}", 2) end
            return P.Machine(machine_id(n.name), input, output, diagnostics, abi, impl, capabilities)
        end,
    },

    g.head .phase {
        g.slot .name [g.name],
        g.slot .body [g.phase_body],
        emit = function(n)
            local input, output, diagnostics, cache, deterministic, machine = nil, nil, nil, P.CacheIdentity, true, nil
            for i = 1, #n.body do
                local raw = n.body[i]
                local item = unwrap(raw)
                local kind = part_kind(raw)
                local mref = stage_machine_ref(raw)
                if kind == "from" then input = item
                elseif kind == "to" then output = item
                elseif kind == "diagnostics" then diagnostics = item
                elseif kind == "cache" then cache = item
                elseif kind == "deterministic" then deterministic = item
                elseif kind == "machine" then machine = item
                elseif mref then machine = mref
                else error("phase_dsl: unexpected phase entry", 2) end
            end
            if not input then error("phase_dsl: phase requires from. world", 2) end
            if not output then error("phase_dsl: phase requires to. world", 2) end
            if not machine then error("phase_dsl: phase requires machine. name", 2) end
            return P.Phase(phase_id(n.name), input, output, diagnostics, cache, deterministic, machine)
        end,
    },

    g.head .from {
        g.slot .world [g.name],
        emit = function(n) return part("from", world_id(n.world)) end,
    },

    g.head .to {
        g.slot .world [g.name],
        emit = function(n) return part("to", world_id(n.world)) end,
    },

    g.head .diagnostics {
        g.slot .world [g.name],
        emit = function(n) return part("diagnostics", world_id(n.world)) end,
    },

    g.head .cache {
        g.slot .policy [g.name],
        emit = function(n) return part("cache", cache_policy(n.policy)) end,
    },

    g.head .deterministic {
        g.slot .value [g.boolean],
        emit = function(n) return part("deterministic", n.value) end,
    },

    g.head .abi {
        g.slot .abi_name [g.name],
        emit = function(n) return part("abi", machine_abi(n.abi_name)) end,
    },

    g.head .impl {
        g.slot .impl_name [g.name],
        g.slot .body [g.record],
        emit = function(n) return part("impl", impl_from(ident_text(n.impl_name, "impl kind"), n.body)) end,
    },

    g.head .capabilities {
        g.slot .names [g.value],
        emit = function(n) return part("capabilities", string_array(n.names, "capabilities")) end,
    },

    g.head .root {
        g.slot .name [g.name],
        g.slot .body [g.root_body],
        emit = function(n)
            local input, output = nil, nil
            for i = 1, #n.body do
                local item = unwrap(n.body[i])
                local kind = part_kind(n.body[i])
                if kind == "from" then input = item
                elseif kind == "to" then output = item
                else error("phase_dsl: root body expects from. world and to. world", 2) end
            end
            if not input then error("phase_dsl: root requires from. world", 2) end
            if not output then error("phase_dsl: root requires to. world", 2) end
            return P.Root(root_id(n.name), input, output)
        end,
    },
}

function M.Define(context)
    P = ensure(context)
    return Lang:env { exports = { _T = context, _P = context.MoonPhase } }
end

function M.use(opts)
    opts = opts or {}
    opts.provides = opts.provides or { "moonphase.dsl" }
    local session = Lang:use(opts)
    function session:loadstring(src, chunkname, load_opts)
        return Lang:loadstring(src, chunkname, load_opts or { env = self.env })
    end
    function session:loadfile(path, load_opts)
        local f, err = io.open(path, "rb")
        if not f then error(err, 2) end
        local src = f:read("*a") or ""
        f:close()
        return self:loadstring(src, "@" .. path, load_opts)
    end
    function session:dofile(path, ...)
        local chunk = self:loadfile(path)
        return chunk(...)
    end
    return session
end

function M.env(opts) return Lang:env(opts) end
function M.loadstring(src, chunkname, opts) return Lang:loadstring(src, chunkname, opts) end
function M.loadfile(path, opts) return Lang:loadfile(path, opts) end

M.Language = Lang
M.T = T
M.P = P

-- Formatting ----------------------------------------------------------------

local doc = llb.doc

local function id_text(v)
    if type(v) == "table" and v.value ~= nil then return tostring(v.value) end
    if type(v) == "table" and v.text ~= nil then return tostring(v.text) end
    return tostring(v)
end

local function type_ref_text(v)
    local cls = pvm.classof(v)
    if cls == P.TypeRefAny then return "any" end
    if cls == P.TypeRefValue then return "value. " .. tostring(v.field_name) end
    if cls == P.TypeRef then return tostring(v.module_name) .. "." .. tostring(v.type_name) end
    return tostring(v)
end

local function cache_text(v)
    if v == P.CacheIdentity then return "identity" end
    if v == P.CacheNode then return "node" end
    if v == P.CacheFull then return "full" end
    if v == P.CacheNone then return "none" end
    return tostring(v)
end

local function abi_text(v)
    if v == P.MachineAbiStatusReturning then return "status_returning" end
    if v == P.MachineAbiPure then return "pure" end
    if v == P.MachineAbiProcess then return "process" end
    if v == P.MachineAbiC then return "c" end
    if v == P.MachineAbiCranelift then return "cranelift" end
    return tostring(v)
end

local function record_doc(t)
    local keys, parts = {}, {}
    local n = #(t or {})
    if n > 0 then
        for i = 1, n do parts[i] = string.format("%q", tostring(t[i])) end
        return doc.concat { "{", doc.indent({ doc.line(), doc.join(doc.concat { ",", doc.line() }, parts), "," }, 2), doc.line(), "}" }
    end
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for i, k in ipairs(keys) do
        local v = t[k]
        parts[i] = doc.group { tostring(k), " = ", type(v) == "string" and string.format("%q", v) or tostring(v) }
    end
    if #parts == 0 then return doc.text("{}") end
    return doc.concat { "{", doc.indent({ doc.line(), doc.join(doc.concat { ",", doc.line() }, parts), "," }, 2), doc.line(), "}" }
end

local function body_block(items, f)
    if #items == 0 then return doc.text("{}") end
    local parts = {}
    for i = 1, #items do parts[i] = M.format_doc(items[i], f) end
    return doc.concat { "{", doc.indent({ doc.line(), doc.join(doc.concat { ",", doc.line() }, parts), "," }, f.indent_width or 2), doc.line(), "}" }
end

function M.format_doc(value, f)
    f = getmetatable(f) == llb.FormatContext and f or setmetatable({ indent_width = 2, seen = {} }, llb.FormatContext)
    local cls = type(value) == "table" and pvm.classof(value) or nil
    if cls == P.Package then
        local items = {}
        for i = 1, #(value.worlds or {}) do items[#items + 1] = value.worlds[i] end
        for i = 1, #(value.machines or {}) do items[#items + 1] = value.machines[i] end
        for i = 1, #(value.phases or {}) do items[#items + 1] = value.phases[i] end
        for i = 1, #(value.roots or {}) do items[#items + 1] = value.roots[i] end
        return doc.concat { "package. ", id_text(value.id), " ", body_block(items, f) }
    elseif cls == P.World then
        return doc.group { "world. ", id_text(value.id), " [", type_ref_text(value.ty), "]" }
    elseif cls == P.Machine then
        local items = {
            part("from", value.input),
            part("to", value.output),
            part("impl", value.impl),
        }
        if tostring(value.abi) ~= tostring(P.MachineAbiStatusReturning) then items[#items + 1] = part("abi", value.abi) end
        if value.diagnostics then items[#items + 1] = part("diagnostics", value.diagnostics) end
        if #(value.capabilities or {}) > 0 then items[#items + 1] = part("capabilities", value.capabilities) end
        return doc.concat { "machine. ", id_text(value.id), " ", body_block(items, f) }
    elseif cls == P.Phase then
        local items = {
            part("from", value.input),
            part("to", value.output),
            part("machine", value.machine),
        }
        if tostring(value.cache) ~= tostring(P.CacheIdentity) then items[#items + 1] = part("cache", value.cache) end
        if value.deterministic == false then items[#items + 1] = part("deterministic", value.deterministic) end
        if value.diagnostics then items[#items + 1] = part("diagnostics", value.diagnostics) end
        return doc.concat { "phase. ", id_text(value.id), " ", body_block(items, f) }
    elseif cls == P.Root then
        return doc.concat { "root. ", id_text(value.id), " ", body_block({ part("from", value.input), part("to", value.output) }, f) }
    end

    if part_kind(value) == "from" then return doc.group { "from. ", id_text(value.value) } end
    if part_kind(value) == "to" then return doc.group { "to. ", id_text(value.value) } end
    if part_kind(value) == "diagnostics" then return doc.group { "diagnostics. ", id_text(value.value) } end
    if part_kind(value) == "cache" then return doc.group { "cache. ", cache_text(value.value) } end
    if part_kind(value) == "abi" then return doc.group { "abi. ", abi_text(value.value) } end
    if part_kind(value) == "deterministic" then return doc.group { "deterministic ", tostring(value.value) } end
    if part_kind(value) == "machine" then return doc.group { "machine. ", id_text(value.value) } end
    if part_kind(value) == "capabilities" then return doc.group { "capabilities ", record_doc(value.value) } end
    if part_kind(value) == "impl" then
        local impl = value.value
        local icls = pvm.classof(impl)
        if icls == P.ImplMoonlift then return doc.group { "impl. moonlift ", record_doc { module = impl.module_name, func = impl.function_name } } end
        if icls == P.ImplLua then return doc.group { "impl. lua ", record_doc { module = impl.module_name, func = impl.function_name } } end
        if icls == P.ImplC then return doc.group { "impl. c ", record_doc { symbol = impl.symbol } } end
        if icls == P.ImplCranelift then return doc.group { "impl. cranelift ", record_doc { symbol = impl.symbol } } end
        if icls == P.ImplExternal then return doc.group { "impl. external ", record_doc { capability = impl.capability } } end
    end
    return doc.text(tostring(value))
end

function M.format(value, opts)
    return llb.render(M.format_doc(value, setmetatable({ indent_width = opts and opts.indent or 2, seen = {} }, llb.FormatContext)), opts or {})
end

function M.file_text(value, opts)
    return table.concat({
        'local Phase = require("moonlift.phase_dsl")',
        'Phase.use()',
        '',
        'return ' .. M.format(value, opts),
        '',
    }, "\n")
end

return M
