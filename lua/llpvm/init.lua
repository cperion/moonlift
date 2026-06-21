local asdl = require("llpvm.asdl")
local ffi = require("ffi")

local M = {
    asdl = asdl,
    T = asdl.T,
    B = asdl.B,
}

local B = asdl.B.LlPvm

local Vm = {}
Vm.__index = Vm

local Abi = {}
Abi.__index = Abi

local World = {}
World.__index = World

local Stream = {}
Stream.__index = Stream

local Phase = {}
Phase.__index = Phase

local Program = {}
Program.__index = Program

local Retained = {}
Retained.__index = Retained

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

local function unwrap(v)
    if getmetatable(v) == Retained then return unwrap(v.value) end
    if type(v) == "table" and rawget(v, "__llpvm_node") ~= nil then return rawget(v, "__llpvm_node") end
    return v
end

local function symbol(v)
    v = unwrap(v)
    if type(v) == "table" then return v end
    return B.Symbol { value = tostring(v or "") }
end

M.symbol = symbol

local function scalar(name)
    local ctor = scalar_names[name]
    assert(ctor ~= nil, "unknown LLPVM scalar type: " .. tostring(name))
    return B.Scalar { scalar = B[ctor] }
end

M.void = scalar("void")
M.bool = scalar("bool")
M.i8 = scalar("i8")
M.i16 = scalar("i16")
M.i32 = scalar("i32")
M.i64 = scalar("i64")
M.u8 = scalar("u8")
M.u16 = scalar("u16")
M.u32 = scalar("u32")
M.u64 = scalar("u64")
M.f32 = scalar("f32")
M.f64 = scalar("f64")
M.index = scalar("index")
M.node = B.Handle { name = symbol("node") }

function M.handle(name)
    return B.Handle { name = symbol(name) }
end

function M.ptr(to)
    return B.Pointer { to = assert(unwrap(to), "llpvm.ptr requires a type") }
end

function M.view(item)
    return B.View { item = assert(unwrap(item), "llpvm.view requires an item type") }
end

function M.struct(name)
    return function(fields)
        return B.Struct { name = symbol(name), fields = M.fields(fields) }
    end
end

function M.field(name, typ)
    return B.Field { name = symbol(name), type = assert(unwrap(typ), "field requires a type") }
end

function M.fields(spec)
    local out = {}
    if spec == nil then return out end
    if is_array(spec) then
        for i = 1, #spec do out[#out + 1] = assert(unwrap(spec[i]), "field list contains nil") end
        return out
    end
    local keys = sorted_string_keys(spec)
    for i = 1, #keys do
        local k = keys[i]
        out[#out + 1] = M.field(k, spec[k])
    end
    return out
end

local payload_builders = {}

payload_builders["nil"] = function() return B.Nil end
payload_builders.boolean = function(v) return B.BoolValue { value = v } end
payload_builders.number = function(v)
    if v % 1 == 0 then return B.IntValue { value = v } end
    return B.FloatValue { value = v }
end
payload_builders.string = function(v) return B.StringValue { value = v } end

local function payload_value(v)
    v = unwrap(v)
    if type(v) == "table" then return v end
    local build = payload_builders[type(v)]
    assert(build ~= nil, "unsupported LLPVM op payload value: " .. type(v))
    return build(v)
end

local function arg_value(v)
    v = unwrap(v)
    if type(v) == "table" then return v end
    local tv = type(v)
    if tv == "nil" then return B.ArgNil end
    if tv == "boolean" then return B.ArgBool { value = v } end
    if tv == "number" then
        if v % 1 == 0 then return B.ArgInt { value = v } end
        return B.ArgFloat { value = v }
    end
    if tv == "string" then return B.ArgString { value = v } end
    error("unsupported LLPVM arg value: " .. tv, 3)
end

function M.ref_payload(raw)
    return B.RefValue { value = raw }
end

function M.ref_arg(raw)
    return B.ArgRef { value = raw }
end

function M.args(values)
    local out = {}
    values = values or {}
    if is_array(values) then
        for i, v in ipairs(values) do out[i] = arg_value(v) end
    else
        local keys = sorted_string_keys(values)
        for i = 1, #keys do out[#out + 1] = arg_value(values[keys[i]]) end
    end
    return B.Args { values = out }
end

function M.op_kind(name)
    return function(fields)
        return B.OpKind { name = symbol(name), payload = M.fields(fields) }
    end
end

M.op = M.op_kind

function M.cache(mode)
    mode = unwrap(mode)
    if mode == nil or mode == true or mode == "full" then return B.CachePolicy { mode = B.FullCache } end
    if mode == false or mode == "none" or mode == "off" then return B.CachePolicy { mode = B.NoCache } end
    if mode == "record" or mode == "record_only" then return B.CachePolicy { mode = B.RecordOnly } end
    if type(mode) == "table" then return mode end
    error("unknown LLPVM cache policy: " .. tostring(mode), 2)
end

local function stream_wrap(vm, node)
    return setmetatable({ vm = vm, __llpvm_node = node }, Stream)
end

local function world_wrap(vm, abi, node)
    return setmetatable({ vm = vm, abi = abi, __llpvm_node = node }, World)
end

local function phase_wrap(vm, node)
    return setmetatable({ vm = vm, __llpvm_node = node }, Phase)
end

function Abi:_make_op(kind_name, payload_spec)
    payload_spec = payload_spec or {}
    local payload = {}
    if is_array(payload_spec) then
        for i = 1, #payload_spec do payload[i] = payload_value(payload_spec[i]) end
    else
        local fields = {}
        for _, op_kind in ipairs(self.__op_kinds) do
            if op_kind.name.value == kind_name then
                fields = op_kind.payload or {}
                break
            end
        end
        for i = 1, #fields do
            local name = fields[i].name.value
            if payload_spec[name] == nil then
                payload[i] = B.Nil
            else
                payload[i] = payload_value(payload_spec[name])
            end
        end
    end
    return B.Op { world = self:world().__llpvm_node, kind = symbol(kind_name), payload = payload }
end

function Abi:world(name)
    name = name or self.name
    if self.__worlds[name] == nil then
        self.__worlds[name] = world_wrap(self.vm, self, B.World { name = symbol(name), abi = self.__llpvm_node })
    end
    return self.__worlds[name]
end

local function abi_wrap(vm, node, op_kinds)
    local self = setmetatable({
        vm = vm,
        name = node.name.value,
        __llpvm_node = node,
        __op_kinds = op_kinds,
        __worlds = {},
    }, Abi)
    for _, op_kind in ipairs(op_kinds) do
        local op_name = op_kind.name.value
        self[op_name] = function(payload_spec) return self:_make_op(op_name, payload_spec) end
    end
    return self
end

function Vm:abi(name)
    return function(spec)
        spec = spec or {}
        local ops = {}
        local keys = sorted_string_keys(spec)
        for i = 1, #keys do
            local k = keys[i]
            if k ~= "version" and k ~= "resource_type" then
                ops[#ops + 1] = M.op_kind(k)(spec[k])
            end
        end
        local node = B.Abi {
            name = symbol(name),
            version = spec.version or 1,
            ops = ops,
            resource_type = spec.resource_type and unwrap(spec.resource_type) or nil,
        }
        local abi = abi_wrap(self, node, ops)
        self.abis[#self.abis + 1] = abi
        return abi
    end
end

function Vm:world(name)
    return function(spec)
        spec = spec or {}
        local abi = assert(spec.abi, "vm.world requires abi")
        local abi_node = unwrap(abi)
        local world = world_wrap(self, abi, B.World { name = symbol(name), abi = abi_node })
        self.worlds[#self.worlds + 1] = world
        return world
    end
end

local function stream_node(v)
    v = unwrap(v)
    assert(v ~= nil, "stream expected")
    return v
end

function Vm:empty(world)
    return stream_wrap(self, B.Empty { world = unwrap(world) })
end

function Vm:once(op)
    return stream_wrap(self, B.Once { op = unwrap(op) })
end

function Vm:seq(world)
    return function(ops)
        ops = list(ops)
        local out = {}
        for i = 1, #ops do out[i] = unwrap(ops[i]) end
        return stream_wrap(self, B.Seq { world = unwrap(world), ops = out })
    end
end

function Vm:concat(streams)
    local out = {}
    for i, stream in ipairs(list(streams)) do out[i] = stream_node(stream) end
    return stream_wrap(self, B.Concat { streams = out })
end

function Vm:machine(name)
    return function(spec)
        spec = spec or {}
        local node = B.RegionMachine {
            name = symbol(name),
            input = unwrap(assert(spec.from or spec.input, "machine requires input/from world")),
            output = unwrap(assert(spec.to or spec.output, "machine requires output/to world")),
            entry_symbol = symbol(spec.entry or spec.entry_symbol or name),
        }
        self.machines[#self.machines + 1] = node
        return node
    end
end

function Vm:phase(name)
    return function(spec)
        spec = spec or {}
        local machine = unwrap(assert(spec.machine, "phase requires machine"))
        local node = B.Phase {
            name = symbol(name),
            input = unwrap(assert(spec.from or spec.input, "phase requires input/from world")),
            output = unwrap(assert(spec.to or spec.output, "phase requires output/to world")),
            machine = machine,
            cache = M.cache(spec.cache),
        }
        self.phases[#self.phases + 1] = node
        return phase_wrap(self, node)
    end
end

function Phase:with_args(args)
    args = M.args(args or {})
    return setmetatable({ vm = self.vm, phase = self, args = args }, {
        __call = function(bound, input)
            return stream_wrap(bound.vm, B.PhaseMap {
                phase = unwrap(bound.phase),
                input = stream_node(input),
                args = bound.args,
            })
        end,
    })
end

function Phase:__call(arg)
    if getmetatable(arg) == Stream or (type(arg) == "table" and rawget(arg, "__llpvm_node") ~= nil) then
        return self:with_args({})(arg)
    end
    return self:with_args(arg or {})
end

function Stream:drain()
    local node = self.__llpvm_node
    local cls = require("pvm").classof(node)
    if cls == M.T.LlPvm.Empty then return {} end
    if cls == M.T.LlPvm.Once then return { node.op } end
    if cls == M.T.LlPvm.Seq then return node.ops end
    if cls == M.T.LlPvm.Concat then
        local out = {}
        for _, stream in ipairs(node.streams) do
            local chunk = stream_wrap(self.vm, stream):drain()
            for i = 1, #chunk do out[#out + 1] = chunk[i] end
        end
        return out
    end
    return { node }
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
    local root_nodes = {}
    for i, root in ipairs(list(roots)) do root_nodes[i] = stream_node(root) end
    local abis, worlds = {}, {}
    for i, abi in ipairs(self.abis) do abis[i] = unwrap(abi) end
    for i, world in ipairs(self.worlds) do worlds[i] = unwrap(world) end
    for _, abi in ipairs(self.abis) do
        for _, world in pairs(abi.__worlds) do worlds[#worlds + 1] = unwrap(world) end
    end
    local node = B.Program {
        abis = abis,
        worlds = worlds,
        machines = self.machines,
        phases = self.phases,
        roots = root_nodes,
    }
    return setmetatable({ vm = self, __llpvm_node = node }, Program)
end

function Program:bytecode()
    return require("llpvm.bytecode").encode(self.__llpvm_node)
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
    config = config or {}
    local self = setmetatable({
        config = config,
        generation = 1,
        abis = {},
        worlds = {},
        machines = {},
        phases = {},
        retained = {},
    }, Vm)
    self.abi = function(name) return Vm.abi(self, name) end
    self.world = function(name) return Vm.world(self, name) end
    self.empty = function(world) return Vm.empty(self, world) end
    self.once = function(op) return Vm.once(self, op) end
    self.seq = function(world) return Vm.seq(self, world) end
    self.concat = function(streams) return Vm.concat(self, streams) end
    self.machine = function(name) return Vm.machine(self, name) end
    self.phase = function(name) return Vm.phase(self, name) end
    self.program = function(roots) return Vm.program(self, roots) end
    self.retain = function(value) return Vm.retain(self, value) end
    self.rebuild = function(fn) return Vm.rebuild(self, fn) end
    return self
end

M.payload = payload_value
M.arg = arg_value

function M.bytecode(program)
    return require("llpvm.bytecode").encode(program)
end

function M.bytebuffer(bytes)
    assert(type(bytes) == "string", "llpvm.bytebuffer expects a string")
    local buf = ffi.new("uint8_t[?]", #bytes)
    ffi.copy(buf, bytes, #bytes)
    return buf, #bytes
end

return M
