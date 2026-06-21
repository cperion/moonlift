local pvm = require("pvm")
local Asdl = require("llpvm.asdl")
local ffi = require("ffi")

local M = {}

local T = Asdl.T.LlPvm

M.MAGIC = "LLPV"
M.VERSION = 2

M.TAG = {
    symbol = 1,
    type_scalar = 10,
    type_handle = 11,
    type_pointer = 12,
    type_view = 13,
    type_struct = 14,
    field = 20,
    op_kind = 30,
    abi = 40,
    world = 50,
    payload_nil = 60,
    payload_bool = 61,
    payload_int = 62,
    payload_float = 63,
    payload_string = 64,
    payload_ref = 65,
    op = 70,
    arg_nil = 80,
    arg_bool = 81,
    arg_int = 82,
    arg_float = 83,
    arg_string = 84,
    arg_ref = 85,
    args = 90,
    stream_empty = 100,
    stream_once = 101,
    stream_seq = 102,
    stream_concat = 103,
    stream_phase_map = 104,
    machine_region = 110,
    cache_none = 120,
    cache_full = 121,
    cache_record = 122,
    phase = 130,
    root = 140,
}

local scalar_code = {
    [T.Void] = 0,
    [T.Bool] = 1,
    [T.I8] = 2,
    [T.I16] = 3,
    [T.I32] = 4,
    [T.I64] = 5,
    [T.U8] = 6,
    [T.U16] = 7,
    [T.U32] = 8,
    [T.U64] = 9,
    [T.F32] = 10,
    [T.F64] = 11,
    [T.Index] = 12,
}

local cache_code = {
    [T.NoCache] = M.TAG.cache_none,
    [T.FullCache] = M.TAG.cache_full,
    [T.RecordOnly] = M.TAG.cache_record,
}

local Encoder = {}
Encoder.__index = Encoder

local i64_union_t = ffi.typeof("union { int64_t i; uint8_t b[8]; }")
local f64_union_t = ffi.typeof("union { double f; uint8_t b[8]; }")

local function put_byte(out, x)
    out[#out + 1] = string.char(x % 256)
end

local function put_u32(out, x)
    x = math.floor(x or 0)
    out[#out + 1] = string.char(
        x % 256,
        math.floor(x / 256) % 256,
        math.floor(x / 65536) % 256,
        math.floor(x / 16777216) % 256
    )
end

local function read_u32_string(s, at)
    local b0, b1, b2, b3 = s:byte(at, at + 3)
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function find_stream_seq_ids(records, root_id)
    local pos = 1
    while pos + 4 <= #records do
        local tag = records:byte(pos)
        local size = read_u32_string(records, pos + 1)
        local payload = pos + 5
        local next_pos = payload + size
        assert(next_pos - 1 <= #records, "malformed encoded LLPVM records")
        if tag == M.TAG.stream_seq and size >= 12 then
            local id = read_u32_string(records, payload)
            if id == root_id then
                local n = read_u32_string(records, payload + 8)
                local ids = {}
                for i = 1, n do
                    ids[i] = read_u32_string(records, payload + 8 + i * 4)
                end
                return ids
            end
        end
        pos = next_pos
    end
    error("LLPVM bytecode root stream is not a seq stream", 2)
end

local function put_i64(out, x)
    local u = i64_union_t()
    u.i = x or 0
    for i = 0, 7 do put_byte(out, u.b[i]) end
end

local function put_f64(out, x)
    local u = f64_union_t()
    u.f = x or 0
    for i = 0, 7 do put_byte(out, u.b[i]) end
end

local function put_string(out, s)
    s = tostring(s or "")
    put_u32(out, #s)
    out[#out + 1] = s
end

local function record(out, tag, body)
    put_byte(out, tag)
    local body_out = {}
    body(body_out)
    local bytes = table.concat(body_out)
    put_u32(out, #bytes)
    out[#out + 1] = bytes
end

local function new_encoder()
    return setmetatable({
        out = {},
        ids = {},
        objects = {},
    }, Encoder)
end

function Encoder:id(node)
    local id = self.ids[node]
    if id then return id end
    id = #self.objects + 1
    self.ids[node] = id
    self.objects[id] = node
    self:emit_node(id, node)
    return id
end

function Encoder:ids_of(xs)
    local out = {}
    for i = 1, #(xs or {}) do out[i] = self:id(xs[i]) end
    return out
end

local function put_id_list(out, ids)
    put_u32(out, #ids)
    for i = 1, #ids do put_u32(out, ids[i]) end
end

function Encoder:emit_node(id, node)
    local cls = pvm.classof(node)
    assert(cls, "llpvm bytecode can encode ASDL nodes only")

    if cls == T.Symbol then
        return record(self.out, M.TAG.symbol, function(out)
            put_u32(out, id)
            put_string(out, node.value)
        end)
    end

    if cls == T.Scalar then
        return record(self.out, M.TAG.type_scalar, function(out)
            put_u32(out, id)
            put_u32(out, assert(scalar_code[node.scalar], "unknown scalar type"))
        end)
    end
    if cls == T.Handle then
        local name = self:id(node.name)
        return record(self.out, M.TAG.type_handle, function(out) put_u32(out, id); put_u32(out, name) end)
    end
    if cls == T.Pointer then
        local to = self:id(node.to)
        return record(self.out, M.TAG.type_pointer, function(out) put_u32(out, id); put_u32(out, to) end)
    end
    if cls == T.View then
        local item = self:id(node.item)
        return record(self.out, M.TAG.type_view, function(out) put_u32(out, id); put_u32(out, item) end)
    end
    if cls == T.Struct then
        local name = self:id(node.name)
        local fields = self:ids_of(node.fields)
        return record(self.out, M.TAG.type_struct, function(out)
            put_u32(out, id); put_u32(out, name); put_id_list(out, fields)
        end)
    end

    if cls == T.Field then
        local name = self:id(node.name)
        local ty = self:id(node.type)
        return record(self.out, M.TAG.field, function(out) put_u32(out, id); put_u32(out, name); put_u32(out, ty) end)
    end

    if cls == T.OpKind then
        local name = self:id(node.name)
        local payload = self:ids_of(node.payload)
        return record(self.out, M.TAG.op_kind, function(out)
            put_u32(out, id); put_u32(out, name); put_id_list(out, payload)
        end)
    end

    if cls == T.Abi then
        local name = self:id(node.name)
        local ops = self:ids_of(node.ops)
        local resource = node.resource_type and self:id(node.resource_type) or 0
        return record(self.out, M.TAG.abi, function(out)
            put_u32(out, id); put_u32(out, name); put_u32(out, node.version); put_u32(out, resource); put_id_list(out, ops)
        end)
    end

    if cls == T.World then
        local name = self:id(node.name)
        local abi = self:id(node.abi)
        return record(self.out, M.TAG.world, function(out) put_u32(out, id); put_u32(out, name); put_u32(out, abi) end)
    end

    if cls == T.Nil then
        return record(self.out, M.TAG.payload_nil, function(out) put_u32(out, id) end)
    end
    if cls == T.BoolValue then
        return record(self.out, M.TAG.payload_bool, function(out) put_u32(out, id); put_byte(out, node.value and 1 or 0) end)
    end
    if cls == T.IntValue then
        return record(self.out, M.TAG.payload_int, function(out) put_u32(out, id); put_i64(out, node.value) end)
    end
    if cls == T.FloatValue then
        return record(self.out, M.TAG.payload_float, function(out) put_u32(out, id); put_f64(out, node.value) end)
    end
    if cls == T.StringValue then
        return record(self.out, M.TAG.payload_string, function(out) put_u32(out, id); put_string(out, node.value) end)
    end
    if cls == T.RefValue then
        return record(self.out, M.TAG.payload_ref, function(out) put_u32(out, id); put_u32(out, node.value) end)
    end

    if cls == T.Op then
        local world = self:id(node.world)
        local kind = self:id(node.kind)
        local payload = self:ids_of(node.payload)
        return record(self.out, M.TAG.op, function(out)
            put_u32(out, id); put_u32(out, world); put_u32(out, kind); put_id_list(out, payload)
        end)
    end

    if cls == T.ArgNil then return record(self.out, M.TAG.arg_nil, function(out) put_u32(out, id) end) end
    if cls == T.ArgBool then return record(self.out, M.TAG.arg_bool, function(out) put_u32(out, id); put_byte(out, node.value and 1 or 0) end) end
    if cls == T.ArgInt then return record(self.out, M.TAG.arg_int, function(out) put_u32(out, id); put_i64(out, node.value) end) end
    if cls == T.ArgFloat then return record(self.out, M.TAG.arg_float, function(out) put_u32(out, id); put_f64(out, node.value) end) end
    if cls == T.ArgString then return record(self.out, M.TAG.arg_string, function(out) put_u32(out, id); put_string(out, node.value) end) end
    if cls == T.ArgRef then return record(self.out, M.TAG.arg_ref, function(out) put_u32(out, id); put_u32(out, node.value) end) end

    if cls == T.Args then
        local values = self:ids_of(node.values)
        return record(self.out, M.TAG.args, function(out) put_u32(out, id); put_id_list(out, values) end)
    end

    if cls == T.Empty then
        local world = self:id(node.world)
        return record(self.out, M.TAG.stream_empty, function(out) put_u32(out, id); put_u32(out, world) end)
    end
    if cls == T.Once then
        local op = self:id(node.op)
        return record(self.out, M.TAG.stream_once, function(out) put_u32(out, id); put_u32(out, op) end)
    end
    if cls == T.Seq then
        local world = self:id(node.world)
        local ops = self:ids_of(node.ops)
        return record(self.out, M.TAG.stream_seq, function(out) put_u32(out, id); put_u32(out, world); put_id_list(out, ops) end)
    end
    if cls == T.Concat then
        local streams = self:ids_of(node.streams)
        return record(self.out, M.TAG.stream_concat, function(out) put_u32(out, id); put_id_list(out, streams) end)
    end
    if cls == T.PhaseMap then
        local phase = self:id(node.phase)
        local input = self:id(node.input)
        local args = self:id(node.args)
        return record(self.out, M.TAG.stream_phase_map, function(out) put_u32(out, id); put_u32(out, phase); put_u32(out, input); put_u32(out, args) end)
    end

    if cls == T.RegionMachine then
        local name = self:id(node.name)
        local input = self:id(node.input)
        local output = self:id(node.output)
        local entry = self:id(node.entry_symbol)
        return record(self.out, M.TAG.machine_region, function(out) put_u32(out, id); put_u32(out, name); put_u32(out, input); put_u32(out, output); put_u32(out, entry) end)
    end

    if cls == T.CachePolicy then
        return record(self.out, assert(cache_code[node.mode], "unknown cache mode"), function(out) put_u32(out, id) end)
    end

    if cls == T.Phase then
        local name = self:id(node.name)
        local input = self:id(node.input)
        local output = self:id(node.output)
        local machine = self:id(node.machine)
        local cache = self:id(node.cache)
        return record(self.out, M.TAG.phase, function(out)
            put_u32(out, id); put_u32(out, name); put_u32(out, input); put_u32(out, output); put_u32(out, machine); put_u32(out, cache)
        end)
    end

    error("unsupported LLPVM bytecode node: " .. tostring(cls.kind or cls), 2)
end

function M.encode_program(program)
    local enc = new_encoder()
    local roots = {}
    for _, abi in ipairs(program.abis or {}) do enc:id(abi) end
    for _, world in ipairs(program.worlds or {}) do enc:id(world) end
    for _, machine in ipairs(program.machines or {}) do enc:id(machine) end
    for _, phase in ipairs(program.phases or {}) do enc:id(phase) end
    for i, root in ipairs(program.roots or {}) do roots[i] = enc:id(root) end
    assert(#roots > 0, "LLPVM bytecode program requires at least one root")
    local records = table.concat(enc.out)
    local root_id = roots[1]
    local root_ids = find_stream_seq_ids(records, root_id)
    local header = {}
    header[#header + 1] = M.MAGIC
    put_u32(header, M.VERSION)
    put_u32(header, root_id)
    put_u32(header, #root_ids)
    put_u32(header, 20)
    local root_table = {}
    for i = 1, #root_ids do put_u32(root_table, root_ids[i]) end
    return table.concat(header) .. table.concat(root_table) .. records
end

function M.encode(value)
    local node = value
    if type(value) == "table" and rawget(value, "__llpvm_node") ~= nil then node = rawget(value, "__llpvm_node") end
    local cls = pvm.classof(node)
    if cls == T.Program then return M.encode_program(node) end
    error("llpvm.bytecode.encode expects LlPvm.Program", 2)
end

return M
