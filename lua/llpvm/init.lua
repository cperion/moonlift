local asdl = require("llpvm.asdl")
local bytecode = require("llpvm.bytecode")
local ffi = require("ffi")

local M = {
    asdl = asdl,
    T = asdl.T,
    B = asdl.B,
}

local Vm = {}
Vm.__index = Vm

local Language = {}
local LanguageMethods = {}

local TypeDecl = {}
local TypeDeclMethods = {}

local World = {}
local WorldMethods = {}

local WorldType = {}
WorldType.__index = WorldType

local Constructor = {}
Constructor.__index = Constructor

local Stream = {}
Stream.__index = Stream

local Phase = {}
Phase.__index = Phase

local Program = {}
Program.__index = Program

local Retained = {}
Retained.__index = Retained

local Type = {}
Type.__index = Type

local Value = {}
Value.__index = Value

local scalar_names = {
    void = "Void",
    bool = "Bool",
    i8 = "I8",
    i16 = "I16",
    i32 = "I32",
    i64 = "I64",
    u8 = "U8",
    u16 = "U16",
    u32 = "U32",
    u64 = "U64",
    f32 = "F32",
    f64 = "F64",
    index = "Index",
}

local integer_scalar = {
    i8 = true,
    i16 = true,
    i32 = true,
    i64 = true,
    u8 = true,
    u16 = true,
    u32 = true,
    u64 = true,
    index = true,
}

local float_scalar = {
    f32 = true,
    f64 = true,
}

local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    end
    return true
end

local function sorted_string_keys(t)
    local keys = {}
    for k in pairs(t or {}) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

local function list(v)
    if v == nil then return {} end
    if is_array(v) then return v end
    return { v }
end

local function has_key(t, key)
    for k in pairs(t) do
        if k == key then return true end
    end
    return false
end

local function unwrap(v)
    if getmetatable(v) == Retained then return unwrap(v.value) end
    return v
end

local function id_of(v, what)
    v = unwrap(v)
    assert(type(v) == "table" and v.id ~= nil, what .. " expected")
    return v.id
end

local function type_wrap(vm, kind, id, extra)
    extra = extra or {}
    extra.vm = vm
    extra.kind = kind
    extra.id = id
    return setmetatable(extra, Type)
end

local function is_type_decl(v)
    return getmetatable(unwrap(v)) == TypeDecl
end

local resolve_type

local scalar_type_names = {
    ["MoonCore.ScalarVoid"] = "void",
    ["MoonCore.ScalarBool"] = "bool",
    ["MoonCore.ScalarI8"] = "i8",
    ["MoonCore.ScalarI16"] = "i16",
    ["MoonCore.ScalarI32"] = "i32",
    ["MoonCore.ScalarI64"] = "i64",
    ["MoonCore.ScalarU8"] = "u8",
    ["MoonCore.ScalarU16"] = "u16",
    ["MoonCore.ScalarU32"] = "u32",
    ["MoonCore.ScalarU64"] = "u64",
    ["MoonCore.ScalarF32"] = "f32",
    ["MoonCore.ScalarF64"] = "f64",
    ["MoonCore.ScalarIndex"] = "index",
}

local function moonlift_type_name(v)
    return tostring(v.source_hint or v.name or v)
end

local function lower_moonlift_type_value(vm, spec)
    if type(spec) ~= "table" then return nil end
    local as_type = spec.as_type_value or spec.as_moonlift_type
    if type(as_type) ~= "function" then return nil end

    if spec.fields then
        local field_ids = {}
        for i = 1, #spec.fields do
            local f = spec.fields[i]
            local ft = resolve_type(vm, vm:_lower_type_form(f.type))
            field_ids[i] = vm.builder:field(f.name, ft.id)
        end
        return type_wrap(vm, "struct", vm.builder:struct(moonlift_type_name(spec), field_ids), { name = moonlift_type_name(spec) })
    end

    local ty = spec.as_moonlift_type and spec:as_moonlift_type() or spec:as_type_value():as_moonlift_type()
    local cls = tostring(require("moonlift.pvm").classof(ty))
    if cls == "Class(MoonType.TScalar)" then
        return vm:_scalar_type(assert(scalar_type_names[tostring(ty.scalar)], "unsupported Moonlift scalar type: " .. tostring(ty.scalar)))
    elseif cls == "Class(MoonType.TPtr)" then
        local elem = lower_moonlift_type_value(vm, { as_moonlift_type = function() return ty.elem end })
        return type_wrap(vm, "ptr", vm.builder:pointer(elem.id), { to = elem })
    elseif cls == "Class(MoonType.TView)" then
        local elem = lower_moonlift_type_value(vm, { as_moonlift_type = function() return ty.elem end })
        return type_wrap(vm, "view", vm.builder:view(elem.id), { item = elem })
    elseif cls == "Class(MoonType.TNamed)" then
        return vm:_handle_type(moonlift_type_name(spec))
    elseif cls == "Class(MoonType.THandle)" then
        return vm:_handle_type(moonlift_type_name(spec))
    end
    error("unsupported Moonlift type for LLPVM schema: " .. tostring(ty), 3)
end

resolve_type = function(vm, spec)
    spec = unwrap(spec)
    if getmetatable(spec) == Type then return spec end
    if getmetatable(spec) == TypeDecl then return spec:resolved_type() end
    local lowered = lower_moonlift_type_value(vm, spec)
    if lowered then return lowered end
    if type(spec) == "table" and spec.id then return spec end
    error("LLPVM type expected", 3)
end

function M.symbol(v)
    return tostring(v or "")
end

function M.cache(mode)
    return mode
end

function Vm:_scalar_type(name)
    local key = "scalar:" .. name
    local cached = self.types[key]
    if cached then return cached end
    local id = self.builder:scalar(assert(scalar_names[name], "unknown scalar type: " .. tostring(name)))
    local t = type_wrap(self, "scalar", id, { name = name })
    self.types[key] = t
    return t
end

function Vm:_handle_type(name)
    local key = "handle:" .. name
    local cached = self.types[key]
    if cached then return cached end
    local id = self.builder:handle(name)
    local t = type_wrap(self, "handle", id, { name = name })
    self.types[key] = t
    return t
end

function Vm:_lower_type_form(spec)
    spec = unwrap(spec)
    if getmetatable(spec) == Type then return spec end
    if getmetatable(spec) == TypeDecl then return spec:resolved_type() end
    local lowered = lower_moonlift_type_value(self, spec)
    if lowered then return lowered end
    if type(spec) ~= "table" then error("LLPVM type form expected", 3) end
    error("unknown LLPVM type form; use Moonlift type values", 3)
end

local function field_list(vm, fields)
    fields = fields or {}
    local out = {}
    if is_array(fields) then
        for i = 1, #fields do
            local f = fields[i]
            assert(type(f) == "table" and f.name ~= nil and f.type ~= nil, "array payload schemas must contain field values")
            out[i] = {
                name = f.name,
                spec = f.type,
                type = resolve_type(vm, vm:_lower_type_form(f.type)),
            }
        end
    else
        for i, k in ipairs(sorted_string_keys(fields)) do
            local spec = fields[k]
            out[i] = {
                name = k,
                spec = spec,
                type = resolve_type(vm, vm:_lower_type_form(spec)),
            }
        end
    end
    return out
end

function TypeDeclMethods:resolved_type()
    if not self.__resolved_type then
        rawset(self, "__resolved_type", self.language.vm:_handle_type(self.qualified_name))
    end
    return self.__resolved_type
end

function TypeDeclMethods:define_op(name, payload_spec)
    assert(not self.language.__sealed, "cannot define LLPVM constructors after language is sealed")
    assert(type(name) == "string" and name ~= "", "LLPVM op name must be a non-empty string")
    assert(type(payload_spec) == "table", "LLPVM op payload schema must be a table")
    assert(self.__ops_by_name[name] == nil, "duplicate LLPVM op: " .. self.qualified_name .. "." .. name)
    local op = {
        owner = self,
        name = name,
        qualified_name = self.name .. "." .. name,
        payload_spec = payload_spec,
        fields = nil,
    }
    self.__ops_by_name[name] = op
    self.__ops[#self.__ops + 1] = op
    return op
end

TypeDecl.__index = function(self, key)
    local method = TypeDeclMethods[key]
    if method then return method end
    return rawget(self, key)
end

TypeDecl.__newindex = function(self, key, value)
    if type(key) == "string" and key:sub(1, 2) == "__" then
        rawset(self, key, value)
        return
    end
    if type(key) == "string" then
        self:define_op(key, value)
        return
    end
    rawset(self, key, value)
end

Language.__index = function(self, key)
    local method = LanguageMethods[key]
    if method then return method end
    local typ = self.__types_by_field[key]
    if typ then return typ end
    return rawget(self, key)
end

Language.__newindex = function(self, key, value)
    if self.__sealed then error("cannot mutate LLPVM language after it is sealed", 2) end
    if type(key) == "string" and getmetatable(value) == TypeDecl then
        self:install_type(key, value)
        return
    end
    rawset(self, key, value)
end

local function language_new_type(language, name)
    assert(not language.__sealed, "cannot define LLPVM types after language is sealed")
    local type_name = tostring(name)
    assert(type_name ~= "", "LLPVM type name must be non-empty")
    return setmetatable({
        language = language,
        name = type_name,
        qualified_name = language.name .. "." .. type_name,
        __ops = {},
        __ops_by_name = {},
    }, TypeDecl)
end

Language.__call = function(self, name)
    local typ = language_new_type(self, name)
    self:install_type(typ.name, typ)
    return typ
end

function LanguageMethods:install_type(field_name, typ)
    assert(not self.__sealed, "cannot install LLPVM type after language is sealed")
    assert(typ.language == self, "cannot install a type from another LLPVM language")
    assert(self.__types_by_field[field_name] == nil, "duplicate LLPVM type field: " .. field_name)
    rawset(typ, "field_name", field_name)
    self.__types_by_field[field_name] = typ
    self.__types[#self.__types + 1] = typ
    rawset(self, field_name, typ)
end

function LanguageMethods:seal(version, resource_type)
    if self.__sealed then return self end
    local op_kind_ids = {}
    for _, typ in ipairs(self.__types) do
        typ:resolved_type()
        for _, op in ipairs(typ.__ops) do
            op.fields = field_list(self.vm, op.payload_spec)
            local field_ids = {}
            for i, field in ipairs(op.fields) do
                field_ids[i] = self.vm.builder:field(field.name, field.type.id)
            end
            op_kind_ids[#op_kind_ids + 1] = self.vm.builder:op_kind(op.qualified_name, field_ids)
        end
    end
    local resource = resource_type and resolve_type(self.vm, self.vm:_lower_type_form(resource_type)).id or 0
    self.id = self.vm.builder:abi(self.name, version or 1, op_kind_ids, resource)
    self.__sealed = true
    self.vm.abis[#self.vm.abis + 1] = self
    return self
end

function LanguageMethods:world(name)
    self:seal()
    name = name or self.name
    if self.__worlds[name] == nil then
        local id = self.vm.builder:world(name, self.id)
        local world = setmetatable({
            vm = self.vm,
            language = self,
            abi = self,
            id = id,
            name = name,
            __types = {},
        }, World)
        for _, typ in ipairs(self.__types) do
            world.__types[typ.field_name or typ.name] = setmetatable({ world = world, type = typ, __ctors = {} }, WorldType)
        end
        self.__worlds[name] = world
        self.vm.worlds[#self.vm.worlds + 1] = world
    end
    return self.__worlds[name]
end

World.__index = function(self, key)
    local method = WorldMethods[key]
    if method then return method end
    local typ = self.__types[key]
    if typ then return typ end
    return rawget(self, key)
end

function WorldMethods:empty()
    local id = self.vm.builder:empty(self.id)
    return setmetatable({ vm = self.vm, id = id, kind = "empty", world = self, ops = {} }, Stream)
end

function WorldMethods:once(value)
    value = unwrap(value)
    assert(getmetatable(value) == Value, "world:once expects a typed LLPVM value")
    assert(value.world == self, "world:once value belongs to another world")
    local id = self.vm.builder:once(value.id)
    return setmetatable({ vm = self.vm, id = id, kind = "once", world = self, ops = { value } }, Stream)
end

function WorldMethods:seq(values)
    values = list(values)
    local op_ids = {}
    local ops = {}
    for i = 1, #values do
        local value = unwrap(values[i])
        assert(getmetatable(value) == Value, "world:seq expects typed LLPVM values")
        assert(value.world == self, "world:seq value belongs to another world")
        op_ids[i] = value.id
        ops[i] = value
    end
    local id = self.vm.builder:seq(self.id, op_ids)
    return setmetatable({ vm = self.vm, id = id, kind = "seq", world = self, ops = ops }, Stream)
end

function WorldMethods:program(roots)
    return self.vm:program(roots)
end

local function validate_scalar_value(field, scalar_name, value)
    if scalar_name == "void" then
        assert(value == nil, "field '" .. field.name .. "' expects void/nil")
    elseif scalar_name == "bool" then
        assert(type(value) == "boolean", "field '" .. field.name .. "' expects bool")
    elseif integer_scalar[scalar_name] then
        assert(type(value) == "number" and value % 1 == 0, "field '" .. field.name .. "' expects integer " .. scalar_name)
    elseif float_scalar[scalar_name] then
        assert(type(value) == "number", "field '" .. field.name .. "' expects number " .. scalar_name)
    end
end

local function payload_id_for_field(world, field, value)
    value = unwrap(value)
    if is_type_decl(field.spec) then
        assert(getmetatable(value) == Value, "field '" .. field.name .. "' expects " .. field.spec.qualified_name)
        assert(value.type == field.spec, "field '" .. field.name .. "' expects " .. field.spec.qualified_name)
        assert(value.world == world, "field '" .. field.name .. "' value belongs to another world")
        return world.vm.builder:ref_payload(value.id)
    end
    if field.type.kind == "scalar" then validate_scalar_value(field, field.type.name, value) end
    return world.vm.builder:payload(value)
end

function Constructor:__call(payload_spec)
    local op = self.op
    payload_spec = payload_spec or {}
    assert(type(payload_spec) == "table", "LLPVM constructor payload must be a named table")
    assert(not is_array(payload_spec) or #payload_spec == 0, "LLPVM constructors require named payload fields")
    local used = {}
    local payload_ids = {}
    local payload_values = {}
    for i, field in ipairs(op.fields or {}) do
        assert(has_key(payload_spec, field.name), "missing LLPVM payload field: " .. op.qualified_name .. "." .. field.name)
        local value = payload_spec[field.name]
        used[field.name] = true
        payload_ids[i] = payload_id_for_field(self.world, field, value)
        payload_values[i] = value
    end
    for k in pairs(payload_spec) do
        assert(used[k], "unknown LLPVM payload field: " .. op.qualified_name .. "." .. tostring(k))
    end
    local id = self.world.vm.builder:op(self.world.id, op.qualified_name, payload_ids)
    return setmetatable({
        vm = self.world.vm,
        id = id,
        world = self.world,
        type = self.type,
        type_name = self.type.name,
        kind = op.name,
        qualified_kind = op.qualified_name,
        payload = payload_values,
    }, Value)
end

function WorldType:__index(key)
    local op = self.type.__ops_by_name[key]
    if op then
        local ctor = self.__ctors[key]
        if ctor == nil then
            ctor = setmetatable({
                world = self.world,
                type = self.type,
                op = op,
                name = op.name,
                qualified_name = op.qualified_name,
            }, Constructor)
            self.__ctors[key] = ctor
        end
        return ctor
    end
    return rawget(WorldType, key)
end

function Vm:language(name)
    name = tostring(name)
    assert(name ~= "", "LLPVM language name must be non-empty")
    assert(self.languages_by_name[name] == nil, "duplicate LLPVM language: " .. name)
    local language = setmetatable({
        vm = self,
        id = nil,
        name = name,
        __types = {},
        __types_by_field = {},
        __worlds = {},
        __sealed = false,
    }, Language)
    self.languages_by_name[name] = language
    self.languages[#self.languages + 1] = language
    return language
end

function Vm:concat(streams)
    streams = list(streams)
    local stream_ids = {}
    local ops = {}
    local world = nil
    for i = 1, #streams do
        local s = unwrap(streams[i])
        assert(getmetatable(s) == Stream, "vm:concat expects streams")
        if world == nil then
            world = s.world
        else
            assert(s.world == world, "vm:concat streams must share one world")
        end
        stream_ids[i] = id_of(s, "stream")
        for j = 1, #(s.ops or {}) do ops[#ops + 1] = s.ops[j] end
    end
    local id = self.builder:concat(stream_ids)
    return setmetatable({ vm = self, id = id, kind = "concat", world = world, ops = ops }, Stream)
end

function Vm:machine(name)
    return function(spec)
        spec = spec or {}
        local input = assert(spec.from or spec.input, "machine requires input/from world")
        local output = assert(spec.to or spec.output, "machine requires output/to world")
        local id = self.builder:machine(name, id_of(input, "input world"), id_of(output, "output world"), spec.entry or spec.entry_symbol or name)
        local machine = { vm = self, id = id, name = name, input = input, output = output }
        self.machines[#self.machines + 1] = machine
        return machine
    end
end

function Vm:phase(name)
    return function(spec)
        spec = spec or {}
        local input = assert(spec.from or spec.input, "phase requires input/from world")
        local output = assert(spec.to or spec.output, "phase requires output/to world")
        local machine = assert(spec.machine, "phase requires machine")
        local cache_id = self.builder:cache(spec.cache)
        local id = self.builder:phase(name, id_of(input, "input world"), id_of(output, "output world"), id_of(machine, "machine"), cache_id)
        local phase = setmetatable({ vm = self, id = id, name = name, input = input, output = output }, Phase)
        self.phases[#self.phases + 1] = phase
        return phase
    end
end

local function arg_id(vm, v)
    v = unwrap(v)
    if getmetatable(v) == Value then return vm.builder:ref_arg(v.id) end
    return vm.builder:arg(v)
end

function Phase:with_args(args)
    local values = {}
    args = args or {}
    if is_array(args) then
        for i = 1, #args do values[i] = arg_id(self.vm, args[i]) end
    else
        for i, k in ipairs(sorted_string_keys(args)) do values[i] = arg_id(self.vm, args[k]) end
    end
    local args_id = self.vm.builder:args(values)
    return setmetatable({ vm = self.vm, phase = self, args_id = args_id }, {
        __call = function(bound, input)
            input = unwrap(input)
            assert(getmetatable(input) == Stream, "phase input must be an LLPVM stream")
            assert(input.world == bound.phase.input, "phase input stream has the wrong world")
            local id = bound.vm.builder:phase_map(bound.phase.id, id_of(input, "input stream"), bound.args_id)
            return setmetatable({
                vm = bound.vm,
                id = id,
                kind = "phase_map",
                world = bound.phase.output,
                input = input,
                ops = { { id = id, kind = "phase_map", world = bound.phase.output } },
            }, Stream)
        end,
    })
end

function Phase:__call(arg)
    if getmetatable(unwrap(arg)) == Stream then return self:with_args({})(arg) end
    return self:with_args(arg or {})
end

function Stream:drain()
    local out = {}
    for i = 1, #(self.ops or {}) do out[i] = self.ops[i] end
    return out
end

function Stream:one()
    local ops = self:drain()
    assert(#ops == 1, "stream:one expected exactly one op, got " .. tostring(#ops))
    return ops[1]
end

function Stream:each(fn)
    local ops = self:drain()
    for i = 1, #ops do fn(ops[i], i) end
    return self
end

function Vm:program(roots)
    roots = list(roots)
    local root_ids = {}
    local root_ops = {}
    for i = 1, #roots do
        local s = unwrap(roots[i])
        root_ids[i] = id_of(s, "root stream")
        if i == 1 then
            for j = 1, #(s.ops or {}) do root_ops[j] = id_of(s.ops[j], "root op") end
        end
    end
    return setmetatable({ vm = self, root_ids = root_ids, root_ops = root_ops }, Program)
end

function Program:bytecode()
    return self.vm.builder:finish(self.root_ids, self.root_ops)
end

function Program:write(path)
    local f = assert(io.open(path, "wb"))
    local bytes = self:bytecode()
    f:write(bytes)
    f:close()
    return path, #bytes
end

function Vm:retain(value)
    local retained = setmetatable({ vm = self, value = value, generation = self.generation }, Retained)
    self.retained[#self.retained + 1] = retained
    return retained
end

function Vm:rebuild(fn)
    self.generation = self.generation + 1
    return fn(self)
end

function Retained:get()
    return self.value
end

function M.vm(config)
    if type(config) == "string" then config = { name = config } end
    config = config or {}
    local self = setmetatable({
        config = config,
        generation = 1,
        builder = bytecode.builder(),
        types = {},
        languages = {},
        languages_by_name = {},
        abis = {},
        worlds = {},
        machines = {},
        phases = {},
        retained = {},
    }, Vm)
    self.language = function(name) return Vm.language(self, name) end
    self.concat = function(streams) return Vm.concat(self, streams) end
    self.machine = function(name) return Vm.machine(self, name) end
    self.phase = function(name) return Vm.phase(self, name) end
    self.program = function(roots) return Vm.program(self, roots) end
    self.retain = function(value) return Vm.retain(self, value) end
    self.rebuild = function(fn) return Vm.rebuild(self, fn) end
    return self
end

function M.bytecode(program)
    if getmetatable(program) == Program then return program:bytecode() end
    return bytecode.encode(program)
end

function M.bytebuffer(bytes)
    assert(type(bytes) == "string", "llpvm.bytebuffer expects a string")
    local buf = ffi.new("uint8_t[?]", #bytes)
    ffi.copy(buf, bytes, #bytes)
    return buf, #bytes
end

return M
