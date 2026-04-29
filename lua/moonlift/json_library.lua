local ffi = require("ffi")

local M = {}
M.null = {}

local TAG_ARRAY_BEGIN = 1
local TAG_ARRAY_END = 2
local TAG_OBJECT_BEGIN = 3
local TAG_OBJECT_END = 4
local TAG_KEY_SLICE = 5
local TAG_STRING_SLICE = 6
local TAG_NUMBER_SLICE = 7
local TAG_TRUE = 8
local TAG_FALSE = 9
local TAG_NULL = 10

M.TAG = {
    ARRAY_BEGIN = TAG_ARRAY_BEGIN,
    ARRAY_END = TAG_ARRAY_END,
    OBJECT_BEGIN = TAG_OBJECT_BEGIN,
    OBJECT_END = TAG_OBJECT_END,
    KEY_SLICE = TAG_KEY_SLICE,
    STRING_SLICE = TAG_STRING_SLICE,
    NUMBER_SLICE = TAG_NUMBER_SLICE,
    TRUE = TAG_TRUE,
    FALSE = TAG_FALSE,
    NULL = TAG_NULL,
}

local function read_all(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

function M.source()
    return read_all("lib/json.moon2")
end

local function compile_source(src)
    local pvm = require("moonlift.pvm")
    local A2 = require("moonlift.asdl")
    local Parse = require("moonlift.parse")
    local Typecheck = require("moonlift.tree_typecheck")
    local TreeToBack = require("moonlift.tree_to_back")
    local Validate = require("moonlift.back_validate")
    local J = require("moonlift.back_jit")

    local T = pvm.context()
    A2.Define(T)
    local P = Parse.Define(T)
    local TC = Typecheck.Define(T)
    local Lower = TreeToBack.Define(T)
    local V = Validate.Define(T)
    local jit_api = J.Define(T)

    local parsed = P.parse_module(src)
    if #parsed.issues ~= 0 then return nil, { stage = "parse", issues = parsed.issues } end
    local checked = TC.check_module(parsed.module)
    if #checked.issues ~= 0 then return nil, { stage = "type", issues = checked.issues } end
    local program = Lower.module(checked.module)
    local report = V.validate(program)
    if #report.issues ~= 0 then return nil, { stage = "validate", issues = report.issues } end
    local artifact = jit_api.jit():compile(program)
    return { artifact = artifact, T = T, B2 = (T.MoonBack or T.Moon2Back) }, nil
end

function M.compile()
    local compiled, err = compile_source(M.source())
    if not compiled then return nil, err end
    local artifact, B2 = compiled.artifact, compiled.B2
    compiled.valid = ffi.cast("int32_t (*)(const uint8_t*, int32_t, int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("json_valid_scalar")))
    compiled.decode_tape = ffi.cast("int32_t (*)(const uint8_t*, int32_t, int32_t*, int32_t*, int32_t, int32_t*, int32_t*, int32_t*, int32_t, int32_t*)", artifact:getpointer(B2.BackFuncId("json_decode_tape_scalar")))
    compiled.index_tape = ffi.cast("int32_t (*)(const int32_t*, int32_t, int32_t*, int32_t, int32_t*, int32_t*, int32_t*, int32_t*, int32_t*, int32_t*, int32_t*)", artifact:getpointer(B2.BackFuncId("json_index_tape_scalar")))
    compiled.find_field_raw = ffi.cast("int32_t (*)(const uint8_t*, const int32_t*, const int32_t*, const int32_t*, const int32_t*, const int32_t*, const int32_t*, int32_t, const uint8_t*, int32_t)", artifact:getpointer(B2.BackFuncId("json_find_field_raw_scalar")))
    compiled.read_i32 = ffi.cast("int32_t (*)(const uint8_t*, const int32_t*, const int32_t*, const int32_t*, int32_t, int32_t*)", artifact:getpointer(B2.BackFuncId("json_read_i32_scalar")))
    compiled.read_bool = ffi.cast("int32_t (*)(const int32_t*, int32_t, int32_t*)", artifact:getpointer(B2.BackFuncId("json_read_bool_scalar")))
    return compiled, nil
end

local function hex_value(c)
    local b = c:byte(1)
    if b >= 48 and b <= 57 then return b - 48 end
    if b >= 65 and b <= 70 then return b - 55 end
    if b >= 97 and b <= 102 then return b - 87 end
    return 0
end

local function utf8_encode(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40)) end
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
end

function M.unescape_string(raw)
    if not raw:find("\\", 1, true) then return raw end
    local out = {}
    local i = 1
    while i <= #raw do
        local c = raw:sub(i, i)
        if c ~= "\\" then
            out[#out + 1] = c
            i = i + 1
        else
            local e = raw:sub(i + 1, i + 1)
            if e == '"' or e == "\\" or e == "/" then out[#out + 1] = e; i = i + 2
            elseif e == "b" then out[#out + 1] = "\b"; i = i + 2
            elseif e == "f" then out[#out + 1] = "\f"; i = i + 2
            elseif e == "n" then out[#out + 1] = "\n"; i = i + 2
            elseif e == "r" then out[#out + 1] = "\r"; i = i + 2
            elseif e == "t" then out[#out + 1] = "\t"; i = i + 2
            elseif e == "u" then
                local cp = hex_value(raw:sub(i + 2, i + 2)) * 4096 + hex_value(raw:sub(i + 3, i + 3)) * 256 + hex_value(raw:sub(i + 4, i + 4)) * 16 + hex_value(raw:sub(i + 5, i + 5))
                out[#out + 1] = utf8_encode(cp)
                i = i + 6
            else
                out[#out + 1] = e
                i = i + 2
            end
        end
    end
    return table.concat(out)
end

local JsonDoc = {}
JsonDoc.__index = JsonDoc

local JsonDocDecoder = {}
JsonDocDecoder.__index = JsonDocDecoder

local function u8buf(src)
    local n = #src
    local buf = ffi.new("uint8_t[?]", n)
    ffi.copy(buf, src, n)
    return buf, n
end

function M.decode_tape(compiled, src, opts)
    opts = opts or {}
    local n = #src
    local stack_cap = opts.stack_cap or 1024
    local tape_cap = opts.tape_cap or math.max(16, n)
    local buf = ffi.new("uint8_t[?]", n)
    ffi.copy(buf, src, n)
    local stack_next = ffi.new("int32_t[?]", stack_cap)
    local stack_kind = ffi.new("int32_t[?]", stack_cap)
    local tags = ffi.new("int32_t[?]", tape_cap)
    local aa = ffi.new("int32_t[?]", tape_cap)
    local bb = ffi.new("int32_t[?]", tape_cap)
    local meta = ffi.new("int32_t[1]")
    local count = tonumber(compiled.decode_tape(buf, n, stack_next, stack_kind, stack_cap, tags, aa, bb, tape_cap, meta))
    if count < 0 then return nil, -count end
    return {
        src = src,
        buf = buf,
        stack_next = stack_next,
        stack_kind = stack_kind,
        tags = tags,
        a = aa,
        b = bb,
        meta = meta,
        count = count,
    }, nil
end

function M.index_tape(compiled, tape, opts)
    opts = opts or {}
    local count = tape.count
    local stack_cap = opts.stack_cap or 1024
    local stack = ffi.new("int32_t[?]", stack_cap)
    local parent = ffi.new("int32_t[?]", count)
    local first_child = ffi.new("int32_t[?]", count)
    local next_sibling = ffi.new("int32_t[?]", count)
    local child_count = ffi.new("int32_t[?]", count)
    local key_index = ffi.new("int32_t[?]", count)
    local end_index = ffi.new("int32_t[?]", count)
    local last_child = ffi.new("int32_t[?]", count)
    local root = tonumber(compiled.index_tape(tape.tags, count, stack, stack_cap, parent, first_child, next_sibling, child_count, key_index, end_index, last_child))
    if root < 0 then return nil, -root end
    tape.index_stack = stack
    tape.parent = parent
    tape.first_child = first_child
    tape.next_sibling = next_sibling
    tape.child_count = child_count
    tape.key_index = key_index
    tape.end_index = end_index
    tape.last_child = last_child
    tape.root = root
    return tape, nil
end

function M.parse(compiled, src, opts)
    opts = opts or {}
    local tape, err = M.decode_tape(compiled, src, opts)
    if not tape then return nil, err end
    local indexed, index_err = M.index_tape(compiled, tape, opts)
    if not indexed then return nil, index_err end
    indexed.compiled = compiled
    indexed._key_cache = {}
    indexed._out = ffi.new("int32_t[1]")
    return setmetatable(indexed, JsonDoc), nil
end

local function alloc_doc_buffers(compiled, opts)
    opts = opts or {}
    local byte_cap = opts.byte_cap or opts.bytes or 4096
    local tape_cap = opts.tape_cap or byte_cap
    local stack_cap = opts.stack_cap or 1024
    local doc = {
        compiled = compiled,
        src = "",
        buf = ffi.new("uint8_t[?]", byte_cap),
        byte_cap = byte_cap,
        stack_next = ffi.new("int32_t[?]", stack_cap),
        stack_kind = ffi.new("int32_t[?]", stack_cap),
        tags = ffi.new("int32_t[?]", tape_cap),
        a = ffi.new("int32_t[?]", tape_cap),
        b = ffi.new("int32_t[?]", tape_cap),
        meta = ffi.new("int32_t[1]"),
        index_stack = ffi.new("int32_t[?]", stack_cap),
        parent = ffi.new("int32_t[?]", tape_cap),
        first_child = ffi.new("int32_t[?]", tape_cap),
        next_sibling = ffi.new("int32_t[?]", tape_cap),
        child_count = ffi.new("int32_t[?]", tape_cap),
        key_index = ffi.new("int32_t[?]", tape_cap),
        end_index = ffi.new("int32_t[?]", tape_cap),
        last_child = ffi.new("int32_t[?]", tape_cap),
        tape_cap = tape_cap,
        stack_cap = stack_cap,
        count = 0,
        root = -1,
        _key_cache = {},
        _out = ffi.new("int32_t[1]"),
    }
    return setmetatable(doc, JsonDoc)
end

local function ensure_decoder_capacity(self, n)
    if n > self.byte_cap then
        self.byte_cap = n
        self.doc.byte_cap = n
        self.doc.buf = ffi.new("uint8_t[?]", n)
    end
    if n > self.tape_cap then
        self.tape_cap = n
        self.doc.tape_cap = n
        self.doc.tags = ffi.new("int32_t[?]", n)
        self.doc.a = ffi.new("int32_t[?]", n)
        self.doc.b = ffi.new("int32_t[?]", n)
        self.doc.parent = ffi.new("int32_t[?]", n)
        self.doc.first_child = ffi.new("int32_t[?]", n)
        self.doc.next_sibling = ffi.new("int32_t[?]", n)
        self.doc.child_count = ffi.new("int32_t[?]", n)
        self.doc.key_index = ffi.new("int32_t[?]", n)
        self.doc.end_index = ffi.new("int32_t[?]", n)
        self.doc.last_child = ffi.new("int32_t[?]", n)
    end
end

function M.doc_decoder(compiled, opts)
    opts = opts or {}
    local doc = alloc_doc_buffers(compiled, opts)
    return setmetatable({ compiled = compiled, doc = doc, byte_cap = doc.byte_cap, tape_cap = doc.tape_cap, stack_cap = doc.stack_cap }, JsonDocDecoder)
end

function JsonDocDecoder:decode(src)
    local n, ptr
    if type(src) == "string" then
        n, ptr = #src, src
    else
        ptr = src.ptr or src[1]
        n = src.n or src[2]
    end
    ensure_decoder_capacity(self, n)
    local doc = self.doc
    ffi.copy(doc.buf, ptr, n)
    doc.src = type(src) == "string" and src or nil
    local count = tonumber(self.compiled.decode_tape(doc.buf, n, doc.stack_next, doc.stack_kind, self.stack_cap, doc.tags, doc.a, doc.b, self.tape_cap, doc.meta))
    if count < 0 then return nil, -count end
    local root = tonumber(self.compiled.index_tape(doc.tags, count, doc.index_stack, self.stack_cap, doc.parent, doc.first_child, doc.next_sibling, doc.child_count, doc.key_index, doc.end_index, doc.last_child))
    if root < 0 then return nil, -root end
    doc.count = count
    doc.root = root
    return doc, nil
end

function JsonDoc:key_buffer(key)
    local cached = self._key_cache[key]
    if cached then return cached.ptr, cached.n end
    local ptr, n = u8buf(key)
    self._key_cache[key] = { ptr = ptr, n = n }
    return ptr, n
end

function JsonDoc:find_field_raw(key, object_idx)
    object_idx = object_idx or self.root
    local key_ptr, key_len = self:key_buffer(key)
    local idx = tonumber(self.compiled.find_field_raw(self.buf, self.tags, self.a, self.b, self.first_child, self.next_sibling, self.key_index, object_idx, key_ptr, key_len))
    if idx < 0 then return nil end
    return idx
end

function JsonDoc:get_i32(key, object_idx)
    local idx = self:find_field_raw(key, object_idx)
    if idx == nil then return nil, "missing" end
    local rc = tonumber(self.compiled.read_i32(self.buf, self.tags, self.a, self.b, idx, self._out))
    if rc ~= 0 then return nil, "type" end
    return tonumber(self._out[0]), nil
end

function JsonDoc:get_bool(key, object_idx)
    local idx = self:find_field_raw(key, object_idx)
    if idx == nil then return nil, "missing" end
    local rc = tonumber(self.compiled.read_bool(self.tags, idx, self._out))
    if rc ~= 0 then return nil, "type" end
    return self._out[0] ~= 0, nil
end

function JsonDoc:child_count_of(idx)
    return tonumber(self.child_count[idx or self.root])
end

M.JsonDoc = JsonDoc
M.JsonDocDecoder = JsonDocDecoder

return M
