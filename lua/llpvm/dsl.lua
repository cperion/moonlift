local llb = require("llb")
local bytecode = require("llpvm.bytecode")
local ffi = require("ffi")

local M = {}

local function class(name)
    local mt = { __llpvm_dsl_class = name }
    mt.__index = mt
    return mt
end

local Ident = class("Ident")
local Path = class("Path")
local Field = class("Field")
local Call = class("Call")
local ProgramSpec = class("ProgramSpec")
local MachineLanguage = class("MachineLanguage")
local LangSpec = class("LangSpec")
local TypeSpec = class("TypeSpec")
local OpSpec = class("OpSpec")
local WorldSpec = class("WorldSpec")
local StreamSpec = class("StreamSpec")
local RecordSpec = class("RecordSpec")
local MachineSpec = class("MachineSpec")
local PhaseSpec = class("PhaseSpec")
local TaskSpec = class("TaskSpec")
local EventSpec = class("EventSpec")
local Directive = class("Directive")
local RootSpec = class("RootSpec")
local ProgramImage = class("ProgramImage")

local function cls(v)
    local mt = type(v) == "table" and getmetatable(v) or nil
    return mt and mt.__llpvm_dsl_class or nil
end

local function is(v, mt) return type(v) == "table" and getmetatable(v) == mt end

local function die(msg, origin)
    llb.fail("llpvm.dsl: " .. msg, { primary = origin })
end

local function ident(name, origin)
    return setmetatable({ name = tostring(name), origin = origin or llb.here("llpvm-ident", { skip = 1 }) }, Ident)
end

local function ident_text(v, what)
    what = what or "name"
    if is(v, Ident) then return v.name end
    if is(v, Path) and #v.parts == 1 then return v.parts[1] end
    if llb.is(v, "Name") or llb.is(v, "Symbol") then return v.text end
    if type(v) == "string" then return v end
    die(what .. " expected, got " .. llb.repr(v), llb.origin_of(v))
end

local function make_path(parts, origin)
    return setmetatable({ parts = parts, origin = origin or llb.here("llpvm-path", { skip = 1 }) }, Path)
end

local function path_parts(v)
    if is(v, Ident) then return { v.name } end
    if is(v, Path) then return v.parts end
    if llb.is(v, "Name") or llb.is(v, "Symbol") then return { v.text } end
    if llb.is(v, "Expr") and v.kind == "field" then
        local parts = path_parts(v.base)
        parts[#parts + 1] = v.field
        return parts
    end
    if type(v) == "string" then return { v } end
    die("path expected, got " .. llb.repr(v), llb.origin_of(v))
end

local function expr_path_parts(v)
    if llb.is(v, "Symbol") or llb.is(v, "Name") then return { v.text } end
    if llb.is(v, "Expr") and v.kind == "field" then
        local base = expr_path_parts(rawget(v, "base"))
        base[#base + 1] = rawget(v, "field")
        return base
    end
    return nil
end

local function expr_call_path(v)
    if llb.is(v, "Expr") and v.kind == "call" then return expr_path_parts(rawget(v, "callee")), rawget(v, "args") or {} end
    return nil, nil
end

Ident.__tostring = function(self) return self.name end
Ident.__index = function(self, key)
    if Ident[key] then return Ident[key] end
    if type(key) == "string" then return make_path({ self.name, key }, self.origin) end
    return setmetatable({ name = self.name, type = key, origin = llb.here("llpvm-field", { skip = 1 }) }, Field)
end
Ident.__call = function(self, ...)
    return setmetatable({ callee = self, args = { ... }, origin = llb.here("llpvm-call", { skip = 1 }) }, Call)
end

Path.__tostring = function(self) return table.concat(self.parts, ".") end
Path.__index = function(self, key)
    if Path[key] then return Path[key] end
    if type(key) ~= "string" then die("path index expects a string", self.origin) end
    local parts = {}
    for i = 1, #self.parts do parts[i] = self.parts[i] end
    parts[#parts + 1] = key
    return make_path(parts, self.origin)
end
Path.__call = function(self, ...)
    return setmetatable({ callee = self, args = { ... }, origin = llb.here("llpvm-call", { skip = 1 }) }, Call)
end

local function array_items(t)
    local out = {}
    for i = 1, #(t or {}) do
        local v = t[i]
        if llb.is(v, "Spread") then
            local frag = v.value
            if llb.is(frag, "Fragment") then
                for j = 1, #(frag.items or {}) do out[#out + 1] = frag.items[j] end
            elseif type(frag) == "table" then
                for j = 1, #frag do out[#out + 1] = frag[j] end
            else
                die("spread expects a fragment or array", v.origin)
            end
        elseif llb.is(v, "Fragment") then
            for j = 1, #(v.items or {}) do out[#out + 1] = v.items[j] end
        else
            out[#out + 1] = v
        end
    end
    return out
end

local function fields_from_table(t)
    local out = {}
    for _, v in ipairs(array_items(t or {})) do
        local raw_name = type(v) == "table" and rawget(v, "name") or nil
        local raw_type = type(v) == "table" and rawget(v, "type") or nil
        local raw_base = type(v) == "table" and rawget(v, "base") or nil
        local raw_index = type(v) == "table" and rawget(v, "index") or nil
        if is(v, Field) and raw_name ~= nil and raw_type ~= nil then out[#out + 1] = v
        elseif is(v, Field) and raw_base ~= nil and raw_index ~= nil then
            out[#out + 1] = setmetatable({ name = ident_text(raw_base, "field name"), type = raw_index, origin = rawget(v, "origin") }, Field)
        elseif llb.is(v, "Capture") then
            out[#out + 1] = setmetatable({ name = ident_text(v.subject, "field name"), type = v.value, origin = v.origin }, Field)
        elseif llb.is(v, "Expr") and v.kind == "index" then
            out[#out + 1] = setmetatable({ name = ident_text(v.base, "field name"), type = v.index, origin = v.origin }, Field)
        elseif type(v) == "table" and v.name ~= nil and v.type ~= nil then out[#out + 1] = setmetatable(v, Field)
        else die("field list expects entries like name [Type]", llb.origin_of(v)) end
    end
    return out
end

local function fragment(role, items)
    return llb.fragment(role, array_items(items or {}), llb.here("llpvm-fragment", { skip = 2 }), { algebra = "list" })
end

function M.schema(t) return fragment("llpvm_decl", t) end
function M.stream_items(t) return fragment("llpvm_stream_item", t) end
M._ = llb.spread
M.spread = llb.spread
M.llpvm = llb.zone_head {
    family = "moonlift",
    member = "llpvm.dsl",
    name = "llpvm",
    role = "programs",
}

local function is_llpvm_zone(v)
    return llb.is(v, "Zone") and (v.member == "llpvm.dsl" or v.name == "llpvm" or v.role == "llpvm")
end

local MachineLanguageFactory = {}
local MachineLanguageStage = {}

MachineLanguageFactory.__index = function(_, key)
    return setmetatable({ name = tostring(key), origin = llb.here("llpvm-language", { skip = 1 }) }, MachineLanguageStage)
end

MachineLanguageStage.__call = function(self, body)
    return setmetatable({
        name = self.name,
        body = array_items(body or {}),
        origin = self.origin,
        generated = nil,
    }, MachineLanguage)
end

local machine_language_factory = setmetatable({}, MachineLanguageFactory)

local g = llb.grammar
local ch = llb.channel
local function slot_name(slot) return slot[g.name] { channel = ch.index_name } end
local function slot_body(slot, role) return slot[role] { channel = ch.call_table } end
local function slot_index_value(slot) return slot[g.value] { channels = { ch.index_value, ch.index_name, ch.index_type } } end
local function slot_call_value(slot) return slot[g.value] { channels = { ch.call_none, ch.call_value, ch.call_table, ch.call_many } } end

local function role_list(label, allowed)
    return {
        kind = "array",
        algebra = "list",
        normalize = function(_, ctx, v)
            local out = {}
            for _, item in ipairs(array_items(v)) do
                if allowed and not allowed[cls(item)] and not (llb.is(item, "Stage") and allowed.Stage) then
                    die(label .. " received invalid item " .. tostring(cls(item) or llb.tagof(item) or type(item)), llb.origin_of(item) or (ctx and ctx.origin))
                end
                out[#out + 1] = item
            end
            return out
        end,
    }
end

local function normalize_stream_record_item(item)
    if is(item, RecordSpec) then return item end
    local parts, args = expr_call_path(item)
    if parts and #parts == 2 then
        return setmetatable({
            name = tostring(parts[2]),
            expr = setmetatable({
                callee = make_path({ parts[1], parts[2] }),
                args = { args[1] or {} },
                origin = llb.origin_of(item),
            }, Call),
            origin = llb.origin_of(item),
        }, RecordSpec)
    end
    if parts and #parts == 3 then
        return setmetatable({
            name = tostring(parts[3]),
            expr = setmetatable({
                callee = make_path({ parts[1], parts[2] }),
                args = { args[1] or {} },
                origin = llb.origin_of(item),
            }, Call),
            origin = llb.origin_of(item),
        }, RecordSpec)
    end
    return item
end

local function normalize_stream_body(t, origin)
    local out = {}
    for _, item in ipairs(array_items(t or {})) do
        item = normalize_stream_record_item(item)
        if not is(item, RecordSpec) then
            die("stream received invalid item " .. tostring(cls(item) or llb.tagof(item) or type(item)), llb.origin_of(item) or origin)
        end
        out[#out + 1] = item
    end
    return out
end

local LL = llb.define "LLPVMDsl" {
    g.role .decls (role_list("program", { LangSpec = true, WorldSpec = true, StreamSpec = true, MachineSpec = true, PhaseSpec = true, TaskSpec = true, RootSpec = true })),
    g.role .lang_body (role_list("language", { TypeSpec = true })),
    g.role .type_body (role_list("type", { OpSpec = true })),
    g.role .fields { kind = "array", algebra = "product", normalize = function(_, _, v) return fields_from_table(v) end },
    g.role .stream_body {
        kind = "array",
        algebra = "list",
        normalize = function(_, ctx, v)
            return normalize_stream_body(v, ctx and ctx.origin)
        end,
    },
    g.role .phase_body (role_list("phase", { Directive = true, Stage = true })),
    g.role .task_body (role_list("task", { Directive = true, EventSpec = true })),
    g.role .root_body (role_list("root", nil)),

    g.trait .named { apply = function(_, head) head.lsp = head.lsp or { symbol = function(n) return { name = tostring(n.name), kind = head.name, origin = n.origin, node = n } end } end },

    -- Declares an LLPVM program containing languages, worlds, streams, machines, phases, tasks, and roots.
    g.head .pvm { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.decls), emit = function(n) return setmetatable({ name = ident_text(n.name, "program name"), body = n.body or {}, origin = n.origin }, ProgramSpec) end },
    -- Declares an operation language namespace containing typed operation definitions.
    g.head .lang { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.lang_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "language name"), body = n.body or {}, origin = n.origin }, LangSpec) end },
    -- Declares a named LLPVM type family containing operation constructors.
    g.head .type { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.type_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "type name"), body = n.body or {}, origin = n.origin }, TypeSpec) end },
    -- Declares one operation constructor with product-shaped fields.
    g.head .op { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .fields, g.fields), emit = function(n) return setmetatable({ name = ident_text(n.name, "op name"), fields = n.fields or {}, origin = n.origin }, OpSpec) end },
    -- Declares a named world over a language value.
    g.head .world { g.trait .named, slot_name(g.slot .name), slot_index_value(g.slot .language), emit = function(n) return setmetatable({ name = ident_text(n.name, "world name"), language = n.language, origin = n.origin }, WorldSpec) end },
    -- Declares a bytecode or fact stream attached to a world.
    g.head .stream { g.trait .named, slot_name(g.slot .name), slot_index_value(g.slot .world), slot_body(g.slot .body, g.stream_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "stream name"), world = n.world, body = n.body or {}, origin = n.origin }, StreamSpec) end },
    -- Declares a named stream record expression.
    g.head .record { g.trait .named, slot_name(g.slot .name), slot_call_value(g.slot .expr), emit = function(n) return setmetatable({ name = ident_text(n.name, "record name"), expr = n.expr, origin = n.origin }, RecordSpec) end },
    -- Declares a reusable machine made from phase directives and stages.
    g.head .machine { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.phase_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "machine name"), body = n.body or {}, origin = n.origin }, MachineSpec) end },
    -- Declares a named phase body with input/output/cache/implementation directives.
    g.head .phase { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.phase_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "phase name"), body = n.body or {}, origin = n.origin }, PhaseSpec) end },
    -- Declares a task protocol with input/output directives and emitted event payloads.
    g.head .task { g.trait .named, slot_name(g.slot .name), slot_body(g.slot .body, g.task_body), emit = function(n) return setmetatable({ name = ident_text(n.name, "task name"), body = n.body or {}, origin = n.origin }, TaskSpec) end },
    -- Declares one task event and its payload type.
    g.head .event { g.trait .named, slot_name(g.slot .name), slot_index_value(g.slot .payload), emit = function(n) return setmetatable({ name = ident_text(n.name, "event name"), payload = n.payload, origin = n.origin }, EventSpec) end },
    -- Marks the input world, value, or stream consumed by a phase or task.
    g.head .input { slot_index_value(g.slot .value), emit = function(n) return setmetatable({ kind = "input", value = n.value, origin = n.origin }, Directive) end },
    -- Marks the output world, value, or stream produced by a phase or task.
    g.head .output { slot_index_value(g.slot .value), emit = function(n) return setmetatable({ kind = "output", value = n.value, origin = n.origin }, Directive) end },
    -- Names the source world or stream for a root or phase edge.
    g.head .from { slot_name(g.slot .value), emit = function(n) return setmetatable({ kind = "from", value = n.value, origin = n.origin }, Directive) end },
    -- Names the destination world or stream for a root or phase edge.
    g.head .to { slot_name(g.slot .value), emit = function(n) return setmetatable({ kind = "to", value = n.value, origin = n.origin }, Directive) end },
    -- Names the entry phase or machine for a root/task execution surface.
    g.head .entry { slot_name(g.slot .value), emit = function(n) return setmetatable({ kind = "entry", value = n.value, origin = n.origin }, Directive) end },
    -- Declares the cache policy or cache key for a phase.
    g.head .cache { slot_name(g.slot .value), emit = function(n) return setmetatable({ kind = "cache", value = n.value, origin = n.origin }, Directive) end },
    -- Declares a root execution plan by composing directives and stages.
    g.head .root { slot_body(g.slot .body, g.root_body), emit = function(n) return setmetatable({ body = n.body or {}, origin = n.origin }, RootSpec) end },
}

M.meta_language = LL

local function machine_op_defs(self)
    local out = {}
    for _, item in ipairs(self.body or {}) do
        if is(item, TypeSpec) then
            for _, op in ipairs(item.body or {}) do
                if is(op, OpSpec) then
                    out[#out + 1] = {
                        type_name = item.name,
                        op_name = op.name,
                        fields = op.fields or {},
                        origin = op.origin,
                    }
                end
            end
        end
    end
    return out
end

local function complete_machine_decl(self, item)
    if is(item, TypeSpec) then return nil end
    if is(item, LangSpec) or is(item, WorldSpec) then return item end
    if is(item, MachineSpec) or is(item, PhaseSpec) or is(item, StreamSpec) or is(item, RootSpec) then return item end
    local parts, args = expr_call_path(item)
    if parts and #parts == 2 then
        return setmetatable({
            name = tostring(parts[2]),
            world = ident(parts[1], llb.origin_of(item)),
            body = normalize_stream_body(args[1] or {}, llb.origin_of(item)),
            origin = llb.origin_of(item),
        }, StreamSpec)
    end
    if llb.is_stage(item) and llb.stage_head(item) == "world" then
        return item[ident(self.name, item.origin)]
    end
    die("LLPVM language body expects type/world/machine/phase declarations", llb.origin_of(item) or self.origin)
end

local function machine_decls(self)
    local types, decls = {}, {}
    for _, item in ipairs(self.body or {}) do
        if is(item, TypeSpec) then types[#types + 1] = item end
    end
    decls[#decls + 1] = setmetatable({ name = self.name, body = types, origin = self.origin }, LangSpec)
    for _, item in ipairs(self.body or {}) do
        local decl = complete_machine_decl(self, item)
        if decl then decls[#decls + 1] = decl end
    end
    return decls
end

local function generated_value_head(type_name, op_name)
    local head = {}
    head.__index = function(_, value_name)
        return function(payload)
            return setmetatable({
                name = tostring(value_name),
                expr = setmetatable({
                    callee = make_path({ type_name, op_name }),
                    args = { payload or {} },
                    origin = llb.here("llpvm-value", { skip = 1 }),
                }, Call),
                origin = llb.here("llpvm-value", { skip = 1 }),
            }, RecordSpec)
        end
    end
    return setmetatable({}, head)
end

local function generated_world_head(world_name)
    local head = {}
    head.__index = function(_, stream_name)
        return function(body)
            return setmetatable({
                name = tostring(stream_name),
                world = ident(world_name),
                body = array_items(body or {}),
                origin = llb.here("llpvm-stream", { skip = 1 }),
            }, StreamSpec)
        end
    end
    head.__call = function(_, body)
        return setmetatable({
            name = tostring(world_name),
            world = ident(world_name),
            body = array_items(body or {}),
            origin = llb.here("llpvm-stream", { skip = 1 }),
        }, StreamSpec)
    end
    return setmetatable({}, head)
end

function MachineLanguage:program(body)
    local decls = machine_decls(self)
    for _, item in ipairs(array_items(body or {})) do decls[#decls + 1] = item end
    return setmetatable({
        name = self.name,
        body = decls,
        extra_body = array_items(body or {}),
        origin = self.origin,
        language = self,
    }, ProgramSpec)
end

MachineLanguage.__call = function(self, body)
    return self:program(body)
end

function MachineLanguage:make_env(opts)
    opts = opts or {}
    local env = M.make_env { base = opts.base or opts.target or _G }
    env.language = machine_language_factory
    env.pvm = nil
    for _, op in ipairs(machine_op_defs(self)) do
        env[op.op_name] = generated_value_head(op.type_name, op.op_name)
    end
    for _, item in ipairs(self.body or {}) do
        local decl = complete_machine_decl(self, item)
        if is(decl, WorldSpec) then env[decl.name] = generated_world_head(decl.name) end
    end
    return env
end

function MachineLanguage:use(opts)
    opts = opts or {}
    local exports = self:make_env(opts)
    return llb.use(LL, {
        scope = opts.scope or (opts.global == false and "env" or "permanent"),
        target = opts.target or _G,
        base = exports,
        exports = exports,
        lang_exports = false,
        helpers = false,
        strict = opts.strict,
        strict_message = "unknown LLPVM machine DSL global ",
        override = opts.override ~= false,
        auto_names = opts.auto_names ~= false,
        mode = opts.mode,
        requires = opts.requires or { "moonlift.types" },
        provides = opts.provides or { "llpvm.language." .. self.name },
    })
end

function MachineLanguage:loadstring(src, name, opts)
    opts = opts or {}
    local target = opts.env or {}
    if opts.env == nil then require("moonlift").use { scope = "env", target = target, global = false, searcher = false } end
    local session = self:use { scope = "env", target = target, global = false, strict = opts.strict, auto_names = opts.auto_names, base = opts.base, mode = opts.mode }
    local fn, err = (loadstring or load)(src, name or ("=(" .. self.name .. ".llpvm)"))
    if not fn then error(err, 2) end
    if setfenv then setfenv(fn, session.env) end
    return fn
end

function MachineLanguage:load(src, name, opts) return self:loadstring(src, name, opts)() end
function MachineLanguage:loadfile(path, opts) local f = assert(io.open(path, "rb")); local src = f:read("*a") or ""; f:close(); return self:loadstring(src, "@" .. path, opts) end
function MachineLanguage:lower(body, opts) return self:program(body):lower(opts) end
function MachineLanguage:bytecode(body, opts) return self:program(body):bytecode(opts) end
function MachineLanguage:format(value, opts) return M.format(value, opts) end
function MachineLanguage:file_text(value, opts) return M.file_text(value, opts) end
function MachineLanguage:records(bytes) return M.records(bytes) end
function MachineLanguage:validate(bytes) return M.validate(bytes) end
function MachineLanguage:inspect(bytes) return M.inspect(bytes) end
function MachineLanguage:describe() return { tag = "LLPVMMachineLanguage", name = self.name, ops = machine_op_defs(self) } end

local scalar_names = {
    void = "Void", bool = "Bool", i8 = "I8", i16 = "I16", i32 = "I32", i64 = "I64",
    u8 = "U8", u16 = "U16", u32 = "U32", u64 = "U64", f32 = "F32", f64 = "F64", index = "Index",
}

local scalar_type_names = {
    ["MoonCore.ScalarVoid"] = "void", ["MoonCore.ScalarBool"] = "bool",
    ["MoonCore.ScalarI8"] = "i8", ["MoonCore.ScalarI16"] = "i16", ["MoonCore.ScalarI32"] = "i32", ["MoonCore.ScalarI64"] = "i64",
    ["MoonCore.ScalarU8"] = "u8", ["MoonCore.ScalarU16"] = "u16", ["MoonCore.ScalarU32"] = "u32", ["MoonCore.ScalarU64"] = "u64",
    ["MoonCore.ScalarF32"] = "f32", ["MoonCore.ScalarF64"] = "f64", ["MoonCore.ScalarIndex"] = "index",
}

local integer_scalar = { i8 = true, i16 = true, i32 = true, i64 = true, u8 = true, u16 = true, u32 = true, u64 = true, index = true }
local float_scalar = { f32 = true, f64 = true }

local Lower = {}
Lower.__index = Lower

local function lower_new(spec, opts)
    return setmetatable({
        spec = spec,
        opts = opts or {},
        builder = bytecode.builder(),
        scalar_types = {},
        languages = {},
        types = {},
        op_defs = {},
        op_type_by_name = {},
        worlds = {},
        streams = {},
        values = {},
        machines = {},
        phases = {},
        roots = {},
    }, Lower)
end

function Lower:scalar_type(name)
    local t = self.scalar_types[name]
    if not t then
        t = { kind = "scalar", name = name, id = self.builder:scalar(assert(scalar_names[name], "unknown scalar type: " .. tostring(name))) }
        self.scalar_types[name] = t
    end
    return t
end

function Lower:handle_type(name)
    return { kind = "handle", name = name, id = self.builder:handle(name) }
end

local function moonlift_type_value(v)
    if type(v) ~= "table" then return nil end
    local as_type = v.as_type_value or v.as_moonlift_type
    if type(as_type) ~= "function" then return nil end
    return v.as_moonlift_type and v:as_moonlift_type() or v:as_type_value():as_moonlift_type()
end

function Lower:resolve_type(ref, current_lang)
    if is(ref, Ident) or llb.is(ref, "Name") or llb.is(ref, "Symbol") then
        local name = ident_text(ref, "type reference")
        local by_lang = current_lang and self.types[current_lang]
        if by_lang and by_lang[name] then return by_lang[name] end
        for _, types in pairs(self.types) do if types[name] then return types[name] end end
        die("unknown LLPVM type " .. name, llb.origin_of(ref))
    elseif is(ref, Path) then
        if #ref.parts == 2 and self.types[ref.parts[1]] and self.types[ref.parts[1]][ref.parts[2]] then return self.types[ref.parts[1]][ref.parts[2]] end
        die("unknown LLPVM type path " .. tostring(ref), ref.origin)
    elseif type(ref) == "table" and ref.__llpvm_lowered_type then
        return ref
    end
    local ty = ref
    if type(ref) == "table" then
        local ok, c = pcall(function() return tostring(require("moonlift.pvm").classof(ref)) end)
        if not ok or not c or not c:match("^Class%(MoonType%.") then ty = moonlift_type_value(ref) end
    else
        ty = moonlift_type_value(ref)
    end
    if ty then
        if type(ty) == "table" and ty.scalar ~= nil then
            return self:scalar_type(assert(scalar_type_names[tostring(ty.scalar)], "unsupported scalar"))
        end
        local pvm = require("moonlift.pvm")
        local cls = tostring(pvm.classof(ty))
        if cls == "Class(MoonType.TScalar)" then return self:scalar_type(assert(scalar_type_names[tostring(ty.scalar)], "unsupported scalar")) end
        if cls == "Class(MoonType.TPtr)" then local elem = self:resolve_type(ty.elem, current_lang); return { kind = "ptr", id = self.builder:pointer(elem.id), elem = elem } end
        if cls == "Class(MoonType.TView)" then local elem = self:resolve_type(ty.elem, current_lang); return { kind = "view", id = self.builder:view(elem.id), elem = elem } end
        if cls == "Class(MoonType.TNamed)" or cls == "Class(MoonType.THandle)" then return self:handle_type(tostring(ref.name or ref.type_name or ref)) end
    end
    die("LLPVM type expected", llb.origin_of(ref))
end

local function directive(item)
    if is(item, Directive) then return item end
    if llb.is(item, "Stage") and item.head and item.head.name == "machine" and item.raw then
        return setmetatable({ kind = "machine", value = item.raw.name, origin = item.origin }, Directive)
    end
    die("phase/machine body expects from/to/entry/cache/machine directives", llb.origin_of(item))
end

local function directives(items)
    local out = {}
    for _, item in ipairs(items or {}) do local d = directive(item); out[d.kind] = d.value end
    return out
end

function Lower:resolve_language(ref)
    local name = ident_text(ref, "language reference")
    local lang = self.languages[name]
    if not lang then die("unknown LLPVM language " .. name, llb.origin_of(ref)) end
    return lang
end

function Lower:resolve_world(ref)
    local name = ident_text(ref, "world reference")
    local w = self.worlds[name]
    if not w then die("unknown LLPVM world " .. name, llb.origin_of(ref)) end
    return w
end

function Lower:payload_value(v)
    if is(v, Ident) then
        local val = self.values[v.name]
        if not val then die("unknown LLPVM value " .. v.name, v.origin) end
        return self.builder:ref_payload(val.id)
    elseif llb.is(v, "Name") or llb.is(v, "Symbol") then
        local name = ident_text(v, "value reference")
        local val = self.values[name]
        if not val then die("unknown LLPVM value " .. name, llb.origin_of(v)) end
        return self.builder:ref_payload(val.id)
    end
    if is(v, Call) then
        local val = self:constructor_call(v, self.current_world)
        return self.builder:ref_payload(val.id)
    elseif llb.is(v, "Expr") and v.kind == "call" then
        local val = self:constructor_call(v, self.current_world)
        return self.builder:ref_payload(val.id)
    end
    return self.builder:payload(v)
end

local function validate_scalar(field, value)
    if field.type.kind ~= "scalar" then return end
    local name = field.type.name
    if name == "void" then assert(value == nil, "field '" .. field.name .. "' expects nil")
    elseif name == "bool" then assert(type(value) == "boolean", "field '" .. field.name .. "' expects bool")
    elseif integer_scalar[name] then assert(type(value) == "number" and value % 1 == 0, "field '" .. field.name .. "' expects integer " .. name)
    elseif float_scalar[name] then assert(type(value) == "number", "field '" .. field.name .. "' expects number " .. name) end
end

function Lower:constructor_call(expr, world)
    local args = is(expr, Call) and rawget(expr, "args") or (llb.is(expr, "Expr") and rawget(expr, "kind") == "call" and rawget(expr, "args")) or {}
    local parts
    if llb.is(expr, "Expr") and rawget(expr, "kind") == "call" then
        parts = expr_path_parts(rawget(expr, "callee"))
    end
    if not parts then
        local callee = is(expr, Call) and rawget(expr, "callee") or (llb.is(expr, "Expr") and rawget(expr, "kind") == "call" and rawget(expr, "callee"))
        parts = path_parts(callee)
    end
    local type_name, op_name
    if #parts == 2 then
        if world then
            local exported_type = self.op_type_by_name[tostring(world.language) .. "." .. tostring(parts[1])]
            if exported_type then
                type_name, op_name = exported_type, parts[1]
            else
                type_name, op_name = parts[1], parts[2]
            end
        else
            type_name, op_name = parts[1], parts[2]
        end
    elseif #parts == 3 then
        if world and world.language ~= parts[1] then die("constructor " .. tostring(expr.callee) .. " is not in world language " .. world.language, expr.origin) end
        type_name, op_name = parts[2], parts[3]
    else die("constructor path must be Type.Op or Lang.Type.Op", expr.origin) end
    world = world or self.current_world
    if not world then die("constructor call requires a stream/world context", expr.origin) end
    local type_def = self.types[world.language] and self.types[world.language][type_name]
    if not type_def then die("world " .. world.name .. " has no type " .. type_name, expr.origin) end
    local op = self.op_defs[world.language .. "." .. type_name .. "." .. op_name]
    if not op then die("type " .. type_name .. " has no op " .. op_name, expr.origin) end
    local payload = args and args[1] or {}
    assert(type(payload) == "table", "LLPVM constructor payload must be a table")
    local used, ids = {}, {}
    for i, field in ipairs(op.fields) do
        assert(payload[field.name] ~= nil, "missing LLPVM payload field: " .. op.qualified_name .. "." .. field.name)
        local raw = payload[field.name]
        if field.type.kind == "scalar" then validate_scalar(field, raw) end
        if field.type.kind == "handle" and field.type.language then
            local val = self.values[ident_text(raw, "value reference")]
            if val then raw = val end
        end
        if type(raw) == "table" and raw.__llpvm_value then
            assert(raw.world == world, "field '" .. field.name .. "' value belongs to another world")
            ids[i] = self.builder:ref_payload(raw.id)
        else
            ids[i] = self:payload_value(raw)
        end
        used[field.name] = true
    end
    for k in pairs(payload) do assert(used[k], "unknown LLPVM payload field: " .. op.qualified_name .. "." .. tostring(k)) end
    return { __llpvm_value = true, id = self.builder:op(world.id, op.qualified_name, ids), world = world, type = type_def, kind = op_name, qualified_kind = op.qualified_name, payload = payload }
end

function Lower:build_languages()
    for _, decl in ipairs(self.spec.body or {}) do
        if is(decl, LangSpec) then
            if self.languages[decl.name] then die("duplicate language " .. decl.name, decl.origin) end
            self.languages[decl.name] = { name = decl.name, types = {}, abi = nil }
            self.types[decl.name] = {}
            for _, t in ipairs(decl.body or {}) do
                local q = decl.name .. "." .. t.name
                self.types[decl.name][t.name] = { __llpvm_lowered_type = true, kind = "handle", language = decl.name, name = t.name, qualified_name = q, id = self.builder:handle(q) }
            end
        end
    end
    for _, decl in ipairs(self.spec.body or {}) do
        if is(decl, LangSpec) then
            local op_kind_ids = {}
            for _, t in ipairs(decl.body or {}) do
                for _, op in ipairs(t.body or {}) do
                    local fields, field_ids = {}, {}
                    for i, f in ipairs(op.fields or {}) do
                        local field_name = rawget(f, "name")
                        local field_type = rawget(f, "type")
                        if (field_name == nil or field_type == nil) and rawget(f, "base") ~= nil and rawget(f, "index") ~= nil then
                            field_name = ident_text(rawget(f, "base"), "field name")
                            field_type = rawget(f, "index")
                        end
                        field_name = ident_text(field_name, "field name")
                        local ft = self:resolve_type(field_type, decl.name)
                        fields[i] = { name = field_name, type = ft }
                        field_ids[i] = self.builder:field(field_name, ft.id)
                    end
                    local q = t.name .. "." .. op.name
                    local id = self.builder:op_kind(q, field_ids)
                    op_kind_ids[#op_kind_ids + 1] = id
                    self.op_defs[decl.name .. "." .. q] = { name = op.name, qualified_name = q, fields = fields, id = id }
                    self.op_type_by_name[decl.name .. "." .. op.name] = t.name
                end
            end
            self.languages[decl.name].abi = self.builder:abi(decl.name, 1, op_kind_ids, 0)
        end
    end
end

function Lower:build_worlds()
    for _, decl in ipairs(self.spec.body or {}) do
        if is(decl, WorldSpec) then
            local lang = self:resolve_language(decl.language)
            self.worlds[decl.name] = { name = decl.name, language = lang.name, id = self.builder:world(decl.name, lang.abi) }
        end
    end
end

function Lower:build_machines_phases()
    for _, decl in ipairs(self.spec.body or {}) do
        if is(decl, MachineSpec) then
            local d = directives(decl.body)
            local from = self:resolve_world(assert(d.from, "machine requires from"))
            local to = self:resolve_world(assert(d.to, "machine requires to"))
            self.machines[decl.name] = { name = decl.name, input = from, output = to, id = self.builder:machine(decl.name, from.id, to.id, ident_text(d.entry or decl.name, "entry")) }
        end
    end
    for _, decl in ipairs(self.spec.body or {}) do
        if is(decl, PhaseSpec) then
            local d = directives(decl.body)
            local from = self:resolve_world(assert(d.from, "phase requires from"))
            local to = self:resolve_world(assert(d.to, "phase requires to"))
            local machine = d.machine and self.machines[ident_text(d.machine, "machine reference")]
            if not machine then
                local name = decl.name
                machine = { name = name, input = from, output = to, id = self.builder:machine(name, from.id, to.id, ident_text(d.entry or name, "entry")) }
                self.machines[name] = machine
            end
            local cache_id = self.builder:cache(d.cache and ident_text(d.cache, "cache policy") or nil)
            self.phases[decl.name] = { name = decl.name, input = from, output = to, id = self.builder:phase(decl.name, from.id, to.id, machine.id, cache_id) }
        end
    end
end

function Lower:build_streams()
    for _, decl in ipairs(self.spec.body or {}) do
        if is(decl, StreamSpec) then
            local world = self:resolve_world(decl.world)
            local old = self.current_world
            self.current_world = world
            local values, ids = {}, {}
            for i, item in ipairs(decl.body or {}) do
                local val = self:constructor_call(item.expr, world)
                self.values[item.name] = val
                values[i], ids[i] = val, val.id
            end
            self.current_world = old
            self.streams[decl.name] = { name = decl.name, world = world, id = self.builder:seq(world.id, ids), ops = values }
        end
    end
end

function Lower:root_stream(item)
    if llb.is(item, "Head") and item.spec and item.spec.name then
        item = ident(item.spec.name, llb.origin_of(item))
    end
    if is(item, Ident) or llb.is(item, "Name") or llb.is(item, "Symbol") then
        local name = ident_text(item, "root reference")
        local s = self.streams[name]
        if s then return s end
        local v = self.values[name]
        if v then
            return { name = name, world = v.world, id = self.builder:seq(v.world.id, { v.id }), ops = { v } }
        end
        die("unknown root stream or value " .. name, llb.origin_of(item))
    elseif is(item, Call) or (llb.is(item, "Expr") and item.kind == "call") then
        local callee = is(item, Call) and item.callee or item.callee
        local args = is(item, Call) and item.args or item.args
        local phase = self.phases[ident_text(callee, "phase reference")]
        if not phase then die("unknown phase " .. tostring(item.callee), item.origin) end
        local input = self:root_stream(args[1])
        assert(input.world == phase.input, "phase input stream has wrong world")
        local args_id = self.builder:args({})
        return { name = phase.name .. "(" .. (input.name or "stream") .. ")", world = phase.output, id = self.builder:phase_map(phase.id, input.id, args_id), ops = {} }
    end
    die("root expects stream or phase(stream)", llb.origin_of(item))
end

function Lower:build_roots()
    for _, decl in ipairs(self.spec.body or {}) do
        if is(decl, RootSpec) then for _, item in ipairs(decl.body or {}) do self.roots[#self.roots + 1] = self:root_stream(item) end end
    end
    if #self.roots == 0 then die("LLPVM program requires root { ... }", self.spec.origin) end
end

function ProgramSpec:lower(opts)
    if self.language then
        self.body = machine_decls(self.language)
        for _, item in ipairs(array_items(rawget(self, "extra_body") or {})) do
            self.body[#self.body + 1] = complete_machine_decl(self.language, item) or item
        end
    end
    local l = lower_new(self, opts)
    l:build_languages()
    l:build_worlds()
    l:build_machines_phases()
    l:build_streams()
    l:build_roots()
    local root_ids, root_ops = {}, {}
    for i, s in ipairs(l.roots) do root_ids[i] = s.id end
    for i, op in ipairs(l.roots[1].ops or {}) do root_ops[i] = op.id end
    return setmetatable({ spec = self, lowering = l, root_ids = root_ids, root_ops = root_ops }, ProgramImage)
end

function ProgramImage:bytecode() return self.lowering.builder:finish(self.root_ids, self.root_ops) end
function ProgramImage:write(path) local bytes = self:bytecode(); local f = assert(io.open(path, "wb")); f:write(bytes); f:close(); return path, #bytes end
function ProgramSpec:bytecode(opts) return self:lower(opts):bytecode() end
function ProgramSpec:write(path, opts) return self:lower(opts):write(path) end
function ProgramSpec:format(opts) return M.format(self, opts) end

local function collect_programs(out, value)
    if value == nil then return out end
    if is(value, ProgramSpec) or is(value, ProgramImage) then
        out[#out + 1] = value
        return out
    end
    if llb.is(value, "Spread") then return collect_programs(out, value.value) end
    if llb.is(value, "Fragment") then
        for i = 1, #(value.items or {}) do collect_programs(out, value.items[i]) end
        return out
    end
    if is_llpvm_zone(value) then
        for i = 1, #(value.items or {}) do collect_programs(out, value.items[i]) end
        return out
    end
    if llb.is(value, "Zone") then return out end
    if llb.is(value, "FamilyBundle") then
        for _, z in ipairs(value.zones or {}) do collect_programs(out, z) end
        return out
    end
    if type(value) == "table" then
        local body = rawget(value, "programs") or rawget(value, "body") or rawget(value, "items")
        if body ~= nil and body ~= value then return collect_programs(out, body) end
        for i = 1, #value do collect_programs(out, value[i]) end
        for k, v in pairs(value) do
            if type(k) ~= "number" then
                if is(v, ProgramSpec) or is(v, ProgramImage) or is_llpvm_zone(v) or llb.is(v, "FamilyBundle") or llb.is(v, "Spread") then
                    collect_programs(out, v)
                end
            end
        end
        return out
    end
    return out
end

function M.to_program(value)
    if is(value, ProgramSpec) or is(value, ProgramImage) then return value end
    local programs = collect_programs({}, value)
    if #programs == 0 then return nil end
    if #programs > 1 then die("LLPVM projection expected one program value, got " .. tostring(#programs), llb.origin_of(value)) end
    return programs[1]
end

local function process_type_asdl(ref)
    local asdl_mod = require("llpvm.asdl")
    local T = asdl_mod.T.LlPvm
    local ty = ref
    if type(ref) == "table" then
        local ok, c = pcall(function() return tostring(require("moonlift.pvm").classof(ref)) end)
        if not ok or not c or not c:match("^Class%(MoonType%.") then ty = moonlift_type_value(ref) end
    else
        ty = moonlift_type_value(ref)
    end
    if ty then
        if type(ty) == "table" and ty.scalar ~= nil then
            local scalar_name = assert(scalar_type_names[tostring(ty.scalar)], "unsupported process scalar type")
            return T.Scalar(T[assert(scalar_names[scalar_name])])
        end
        local pvm = require("moonlift.pvm")
        local cls = tostring(pvm.classof(ty))
        if cls == "Class(MoonType.TScalar)" then
            local scalar_name = assert(scalar_type_names[tostring(ty.scalar)], "unsupported process scalar type")
            return T.Scalar(T[assert(scalar_names[scalar_name])])
        end
    end
    local name = ident_text(ref, "process type")
    for fq, scalar_name in pairs(scalar_type_names) do
        if name == fq or name:find(fq, 1, true) then
            return T.Scalar(T[assert(scalar_names[scalar_name])])
        end
    end
    local scalar = scalar_names[name]
    if scalar then return T.Scalar(T[scalar]) end
    return T.Handle(T.Symbol(name))
end

function TaskSpec:asdl()
    local asdl_mod = require("llpvm.asdl")
    local T = asdl_mod.T.LlPvm
    local input, output, events = nil, nil, {}
    for _, item in ipairs(self.body or {}) do
        if is(item, Directive) and item.kind == "input" then input = process_type_asdl(item.value)
        elseif is(item, Directive) and item.kind == "output" then output = process_type_asdl(item.value)
        elseif is(item, EventSpec) then events[#events + 1] = T.TaskEventSpec(T.Symbol(item.name), process_type_asdl(item.payload))
        end
    end
    return T.TaskSpec(T.Symbol(self.name), assert(input, "task requires input [T]"), assert(output, "task requires output [T]"), events)
end

local doc = llb.doc
local function fmt_ref(v) if is(v, Ident) or is(v, Path) then return tostring(v) end; if llb.is(v, "Name") or llb.is(v, "Symbol") then return v.text end; return tostring(v) end
local block
local function fmt_type_ref(v)
    if is(v, Ident) or is(v, Path) then return tostring(v) end
    if llb.is(v, "Name") or llb.is(v, "Symbol") then
        for fq, scalar_name in pairs(scalar_type_names) do
            if tostring(v.text):find(fq, 1, true) then return scalar_name end
        end
        return v.text
    end
    if type(v) == "table" then
        local ok, c = pcall(function() return tostring(require("moonlift.pvm").classof(v)) end)
        if ok and c == "Class(MoonType.TScalar)" then return assert(scalar_type_names[tostring(v.scalar)], "unsupported scalar") end
    end
    local text = tostring(v)
    for fq, scalar_name in pairs(scalar_type_names) do
        if text:find(fq, 1, true) then return scalar_name end
    end
    return tostring(v)
end
local function fmt_value(v, f)
    if is(v, Ident) or is(v, Path) then return doc.text(tostring(v)) end
    if is(v, Field) then return doc.group { v.name, " [", fmt_type_ref(v.type), "]" } end
    if is(v, Call) then return doc.group { fmt_value(v.callee, f), " ", block(v.args or {}, f, fmt_value) } end
    if llb.is(v, "Name") or llb.is(v, "Symbol") then return doc.text(v.text) end
    if llb.is(v, "Head") and v.spec and v.spec.name then return doc.text(v.spec.name) end
    if type(v) == "table" then
        local ok, c = pcall(function() return tostring(require("moonlift.pvm").classof(v)) end)
        if ok and c and c:match("^Class%(MoonType%.") then return doc.text(fmt_type_ref(v)) end
    end
    if type(v) == "table" then
        f.seen = f.seen or {}
        if f.seen[v] then return doc.text("<cycle>") end
        f.seen[v] = true
        local keys, items = {}, {}
        for k in pairs(v) do
            if type(k) ~= "number" and k ~= "origin" and k ~= "__llb_tag" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for i, k in ipairs(keys) do items[i] = doc.group { tostring(k), " = ", fmt_value(v[k], f) } end
        local out = block(items, f, function(x) return x end)
        f.seen[v] = nil
        return out
    end
    if type(v) == "string" then return doc.text(string.format("%q", v)) end
    return doc.text(tostring(v))
end
function block(items, f, fmt)
    if #(items or {}) == 0 then return doc.text("{}") end
    local parts = {}
    for i = 1, #items do parts[#parts + 1] = fmt(items[i], f); parts[#parts + 1] = ","; if i < #items then parts[#parts + 1] = doc.line() end end
    return doc.concat { "{", doc.indent({ doc.line(), parts }, f.indent_width), doc.line(), "}" }
end
local fmt_spec
local function machine_definition_format_body(machine)
    local out = {}
    for _, item in ipairs(machine.body or {}) do
        if is(item, TypeSpec) then out[#out + 1] = item
        else
            local decl = complete_machine_decl(machine, item)
            if decl then out[#out + 1] = decl end
        end
    end
    return out
end

fmt_spec = function(v, f)
    if is(v, MachineLanguage) then return doc.concat { "language. ", v.name, " ", block(machine_definition_format_body(v), f, fmt_spec) } end
    if is(v, ProgramSpec) and v.language then
        local def_body, machine_decl_count = machine_definition_format_body(v.language), #machine_decls(v.language)
        local program_body = {}
        for i = machine_decl_count + 1, #(v.body or {}) do
            program_body[#program_body + 1] = complete_machine_decl(v.language, v.body[i]) or v.body[i]
        end
        return doc.concat { "language. ", v.name, " ", block(def_body, f, fmt_spec), " ", block(program_body, f, fmt_spec) }
    end
    if is(v, ProgramSpec) then return doc.concat { "pvm. ", v.name, " ", block(v.body, f, fmt_spec) } end
    if is(v, LangSpec) then return doc.concat { "lang. ", v.name, " ", block(v.body, f, fmt_spec) } end
    if is(v, TypeSpec) then return doc.concat { "type. ", v.name, " ", block(v.body, f, fmt_spec) } end
    if is(v, OpSpec) then return doc.concat { "op. ", v.name, " ", block(v.fields or {}, f, fmt_value) } end
    if is(v, WorldSpec) then return doc.group { "world. ", v.name, " [", fmt_ref(v.language), "]" } end
    if is(v, StreamSpec) then return doc.group { fmt_ref(v.world), ". ", v.name, " ", block(v.body, f, fmt_spec) } end
    if is(v, RecordSpec) then
        if is(v.expr, Call) then
            local parts = path_parts(v.expr.callee)
            local op_name = (#parts == 2 and parts[2] == v.name) and parts[1] or parts[#parts]
            return doc.group { op_name, ". ", v.name, " ", fmt_value((v.expr.args or {})[1] or {}, f) }
        end
        return doc.group { "record. ", v.name, " (", fmt_value(v.expr, f), ")" }
    end
    if is(v, MachineSpec) then return doc.concat { "machine. ", v.name, " ", block(v.body, f, fmt_spec) } end
    if is(v, PhaseSpec) then return doc.concat { "phase. ", v.name, " ", block(v.body, f, fmt_spec) } end
    if is(v, TaskSpec) then return doc.concat { "task. ", v.name, " ", block(v.body, f, fmt_spec) } end
    if is(v, EventSpec) then return doc.group { "event. ", v.name, " [", fmt_type_ref(v.payload), "]" } end
    if is(v, Directive) and (v.kind == "input" or v.kind == "output") then return doc.group { v.kind, " [", fmt_type_ref(v.value), "]" } end
    if is(v, Directive) then return doc.group { v.kind, ". ", fmt_ref(v.value) } end
    if is(v, RootSpec) then return doc.group { "root ", block(v.body, f, fmt_value) } end
    return fmt_value(v, f)
end
function M.doc(value, opts) return fmt_spec(value, setmetatable({ opts = opts or {}, width = opts and opts.width or 100, indent_width = opts and opts.indent or 2, seen = {} }, llb.FormatContext)) end
function M.format(value, opts) return llb.render(M.doc(value, opts or {}), opts or {}) end
function M.file_text(value, opts) return table.concat({ 'local ll = require("llpvm")', 'll.use()', '', 'return ' .. M.format(value, opts), '' }, "\n") end

function M.make_env(opts)
    opts = opts or {}
    local env = {}; for k, v in pairs(opts.base or opts.target or _G) do env[k] = v end
    env.llpvm = M.llpvm
    env.language = machine_language_factory
    for _, name in ipairs({ "pvm", "lang", "type", "op", "world", "stream", "record", "machine", "phase", "task", "event", "input", "output", "from", "to", "entry", "cache", "root" }) do env[name] = LL.exports[name] end
    env.schema, env.stream_items, env._, env.spread = M.schema, M.stream_items, llb.spread, llb.spread
    return env
end

local LLPVM_NAMESPACE_KEYS = {
    "language", "pvm", "lang", "type", "op", "world", "stream", "record",
    "machine", "phase", "task", "event", "input", "output", "from", "to",
    "entry", "cache", "root", "schema", "stream_items", "_", "spread",
}

function M.namespace(opts)
    local env = M.make_env { base = opts and opts.base or {} }
    local exports = {}
    for _, name in ipairs(LLPVM_NAMESPACE_KEYS) do exports[name] = env[name] end
    return llb.namespace {
        family = "moonlift",
        member = "llpvm.dsl",
        name = "llpvm",
        exports = exports,
        zone = M.llpvm,
    }
end

function M.make_family_env(opts)
    return { llpvm = M.namespace(opts) }
end

function M.use(opts)
    opts = opts or {}; local exports = M.make_env(opts)
    return llb.use(LL, { scope = opts.scope or (opts.global == false and "env" or "permanent"), target = opts.target or _G, base = exports, exports = exports, lang_exports = false, helpers = false, strict = opts.strict, strict_message = "unknown LLPVM DSL global ", override = opts.override ~= false, auto_names = opts.auto_names ~= false, mode = opts.mode, requires = opts.requires or { "moonlift.types" }, provides = opts.provides or { "llpvm.dsl" } })
end
function M.loadstring(src, name, opts)
    opts = opts or {}
    local target = opts.env or {}
    if opts.env == nil then require("moonlift").use { scope = "env", target = target, global = false, searcher = false } end
    local session = M.use { scope = "env", target = target, global = false, strict = opts.strict, auto_names = opts.auto_names, base = opts.base, mode = opts.mode }
    local fn, err = (loadstring or load)(src, name or "=(llpvm.dsl)"); if not fn then error(err, 2) end; if setfenv then setfenv(fn, session.env) end; return fn
end
function M.loadfile(path, opts) local f = assert(io.open(path, "rb")); local src = f:read("*a") or ""; f:close(); return M.loadstring(src, "@" .. path, opts) end
function M.load(src, name, opts) return M.loadstring(src, name, opts)() end
function M.describe(value)
    if is(value, MachineLanguage) then return value:describe() end
    if is(value, ProgramSpec) then return { tag = "LLPVMProgram", name = value.name, declarations = #(value.body or {}) } end
    if is(value, LangSpec) then return { tag = "LLPVMLanguage", name = value.name, types = #(value.body or {}) } end
    if is(value, TaskSpec) then return { tag = "LLPVMTask", name = value.name, body = #(value.body or {}) } end
    return llb.describe(value or LL)
end
function M.describe_head(name) return LL:describe_head(name) end
function M.describe_role(name) return LL:describe_role(name) end
function M.bytebuffer(bytes) local buf = ffi.new("uint8_t[?]", #bytes); ffi.copy(buf, bytes, #bytes); return buf, #bytes end

local tag_names = {}
for name, tag in pairs(bytecode.TAG or {}) do tag_names[tag] = name end

local function u32(bytes, at)
    local b0, b1, b2, b3 = bytes:byte(at, at + 3)
    if not b3 then return nil end
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

M.records = llb.process. records (function(ctx, bytes)
    assert(type(bytes) == "string", "llpvm.records expects a byte string")
    local function diagnostic_event(param, code, message, extra)
        local ev = param.ctx:diagnostic_event {
            severity = "error",
            code = code,
            message = message,
        }
        if extra then
            for k, v in pairs(extra) do ev[k] = v end
        end
        return ev
    end

    local function gen(param, state)
        local phase = state.phase
        local bytes0 = param.bytes
        if phase == "start" then
            if #bytes0 < 20 then
                return { phase = "result", count = 0 }, diagnostic_event(param, "E_LLPVM_SHORT_IMAGE", "LLPVM image is shorter than the 20-byte header", { bytes = #bytes0 })
            end
            local magic = bytes0:sub(1, 4)
            local version = u32(bytes0, 5)
            local root_stream_id = u32(bytes0, 9)
            local root_op_count = u32(bytes0, 13)
            local root_op_table_offset = u32(bytes0, 17)
            return {
                phase = magic == "LLPV" and "root_op" or "bad_magic",
                root_op_index = 1,
                root_op_count = root_op_count,
                root_op_table_offset = root_op_table_offset,
                table_start = root_op_table_offset + 1,
                offset = root_op_table_offset + 1 + root_op_count * 4,
                count = 0,
                magic = magic,
            }, param.ctx:make_event("header", {
                magic = magic,
                version = version,
                root_stream_id = root_stream_id,
                root_op_count = root_op_count,
                root_op_table_offset = root_op_table_offset,
                bytes = #bytes0,
            })
        end

        if phase == "bad_magic" then
            return { phase = "result", count = 0 }, diagnostic_event(param, "E_LLPVM_BAD_MAGIC", "LLPVM image has bad magic", { magic = state.magic })
        end

        if phase == "root_op" then
            local i = state.root_op_index
            if i <= state.root_op_count then
                local next_state = {}
                for k, v in pairs(state) do next_state[k] = v end
                next_state.root_op_index = i + 1
                return next_state, param.ctx:make_event("root_op", {
                    index = i,
                    id = u32(bytes0, state.table_start + (i - 1) * 4),
                    offset = state.table_start + (i - 1) * 4,
                })
            end
            local next_state = {}
            for k, v in pairs(state) do next_state[k] = v end
            next_state.phase = "record"
            state = next_state
            phase = "record"
        end

        if phase == "record" then
            local offset = state.offset
            if offset > #bytes0 then
                return { phase = "done", count = state.count }, param.ctx:make_event("result", { result = { records = state.count, bytes = #bytes0 } })
            end
            if offset + 4 > #bytes0 then
                return { phase = "result", count = state.count }, diagnostic_event(param, "E_LLPVM_TRUNCATED_RECORD_HEADER", "LLPVM record header is truncated", { offset = offset })
            end
            local tag = bytes0:byte(offset)
            local payload_bytes = u32(bytes0, offset + 1)
            local payload_offset = offset + 5
            local next_offset = payload_offset + payload_bytes
            if next_offset - 1 > #bytes0 then
                return { phase = "result", count = state.count }, diagnostic_event(param, "E_LLPVM_TRUNCATED_RECORD_PAYLOAD", "LLPVM record payload is truncated", {
                    offset = offset,
                    tag = tag,
                    payload_bytes = payload_bytes,
                })
            end
            local count = state.count + 1
            local next_state = {}
            for k, v in pairs(state) do next_state[k] = v end
            next_state.offset = next_offset
            next_state.count = count
            return next_state, param.ctx:make_event("record", {
                index = count,
                offset = offset,
                tag = tag,
                tag_name = tag_names[tag],
                payload_offset = payload_offset,
                payload_bytes = payload_bytes,
            })
        end

        if phase == "result" then
            return { phase = "done", count = state.count or 0 }, param.ctx:make_event("result", { result = { records = state.count or 0, bytes = #bytes0 } })
        end

        if phase == "done" then
            return nil
        end
        return nil
    end
    return gen, { ctx = ctx, bytes = bytes }, { phase = "start" }
end)

local function clean_event_payload(ev)
    local out = {}
    for k, v in pairs(ev or {}) do
        if k ~= "__llb_tag" and k ~= "process" and k ~= "seq" and k ~= "kind" and k ~= "origin" then out[k] = v end
    end
    return out
end

M.validate = llb.process. validate (function(ctx, bytes)
    local handle = M.records:start(bytes)
    local upstream, up_param, up_state = llb.stream.raw(handle:stream())
    local function gen(param, state)
        if state.done then return nil end
        local r = { upstream(up_param, state.up_state) }
        if r[1] == nil then
            state.done = true
            return state, param.ctx:make_event("result", { result = {
                valid = state.valid,
                records = state.records,
                root_ops = state.root_ops,
                bytes = type(param.bytes) == "string" and #param.bytes or 0,
            } })
        end
        state.up_state = r[1]
        local ev = r[2]
        local payload = clean_event_payload(ev)
        if ev.kind == "diagnostic" then
            state.valid = false
            local out = payload.diagnostic and param.ctx:diagnostic_event(payload.diagnostic) or param.ctx:make_event("diagnostic", payload)
            for k, v in pairs(payload) do
                if k ~= "diagnostic" then out[k] = v end
            end
            return state, out
        elseif ev.kind == "header" then
            if ev.magic ~= "LLPV" then state.valid = false end
        elseif ev.kind == "root_op" then
            state.root_ops = state.root_ops + 1
        elseif ev.kind == "record" then
            state.records = state.records + 1
        end
        return state, param.ctx:make_event(ev.kind, payload)
    end
    return gen, { ctx = ctx, bytes = bytes }, { up_state = up_state, valid = true, records = 0, root_ops = 0 }
end)

function M.inspect(bytes)
    local out = {}
    for ev in M.validate(bytes) do out[#out + 1] = ev end
    return out
end

M.Ident, M.Path, M.Field, M.Call = Ident, Path, Field, Call
M.ProgramSpec, M.ProgramImage, M.MachineLanguage = ProgramSpec, ProgramImage, MachineLanguage
M.TaskSpec, M.EventSpec = TaskSpec, EventSpec
M.language = machine_language_factory
return M
