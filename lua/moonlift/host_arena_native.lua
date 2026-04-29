local ffi = require("ffi")
local HostAbi = require("moonlift.host_arena_abi")
local ValueProxy = require("moonlift.value_proxy")

local M = {}

local KIND = {
    RECORD = 1,
}

if not rawget(_G, "__moonlift_host_arena_native_cdef") then
    ffi.cdef[[
    typedef struct moonlift_host_session_t moonlift_host_session_t;

    typedef struct MoonHostRef {
        uint64_t session_id;
        uint32_t generation;
        uint32_t kind;
        uint32_t type_id;
        uint32_t tag;
        uint64_t offset;
    } MoonHostRef;

    typedef struct MoonHostPtr {
        void* ptr;
        uint64_t session_id;
        uint32_t generation;
        uint32_t kind;
        uint32_t type_id;
        uint32_t tag;
    } MoonHostPtr;

    typedef struct MoonHostRecordSpec {
        uint32_t type_id;
        uint32_t tag;
        size_t size;
        size_t align;
        size_t first_field;
        size_t field_count;
    } MoonHostRecordSpec;

    typedef struct MoonHostFieldInit {
        uint32_t kind;
        size_t offset;
        int64_t i64_value;
        uint64_t u64_value;
        double f64_value;
    } MoonHostFieldInit;

    const char* moonlift_last_error_message(void);
    moonlift_host_session_t* moonlift_host_session_new(void);
    void moonlift_host_session_free(moonlift_host_session_t*);
    uint64_t moonlift_host_session_id(const moonlift_host_session_t*);
    uint32_t moonlift_host_session_generation(const moonlift_host_session_t*);
    int moonlift_host_session_reset(moonlift_host_session_t*);
    int moonlift_host_alloc_record(moonlift_host_session_t*, uint32_t type_id, uint32_t tag, size_t size, size_t align, MoonHostRef* out_ref, MoonHostPtr* out_ptr);
    int moonlift_host_alloc_records(moonlift_host_session_t*, const MoonHostRecordSpec* specs, size_t specs_len, const MoonHostFieldInit* fields, size_t fields_len, MoonHostRef* out_refs, MoonHostPtr* out_ptrs);
    int moonlift_host_ptr_for_ref(const moonlift_host_session_t*, MoonHostRef ref, MoonHostPtr* out_ptr);
    ]]
    rawset(_G, "__moonlift_host_arena_native_cdef", true)
end

local function load_library(libpath)
    if libpath and libpath ~= "" then return ffi.load(libpath) end
    local ext, prefix
    if ffi.os == "OSX" then ext, prefix = ".dylib", "lib"
    elseif ffi.os == "Windows" then ext, prefix = ".dll", ""
    else ext, prefix = ".so", "lib" end
    local candidates = {
        os.getenv("MOONLIFT_LIB"),
        "./target/debug/" .. prefix .. "moonlift" .. ext,
        "./target/release/" .. prefix .. "moonlift" .. ext,
        prefix .. "moonlift" .. ext,
        "moonlift",
    }
    local last_err
    for i = 1, #candidates do
        local path = candidates[i]
        if path and path ~= "" then
            local ok, lib = pcall(ffi.load, path)
            if ok then return lib end
            last_err = lib
        end
    end
    error("moonlift.host_arena_native: could not load moonlift library: " .. tostring(last_err))
end

local function last_error(lib)
    local p = lib.moonlift_last_error_message()
    if p == nil then return "unknown moonlift host arena error" end
    return ffi.string(p)
end

local Session = {}
Session.__index = Session

function M.session(opts)
    opts = opts or {}
    local lib = opts.lib or M.lib or load_library(opts.libpath)
    M.lib = lib
    local ptr = lib.moonlift_host_session_new()
    if ptr == nil then error(last_error(lib)) end
    return setmetatable({ _lib = lib, _ptr = ffi.gc(ptr, lib.moonlift_host_session_free) }, Session)
end

function Session:id()
    return tonumber(self._lib.moonlift_host_session_id(self._ptr))
end

function Session:generation()
    return tonumber(self._lib.moonlift_host_session_generation(self._ptr))
end

function Session:reset()
    if self._lib.moonlift_host_session_reset(self._ptr) == 0 then error(last_error(self._lib)) end
end

function Session:free()
    if self._ptr ~= nil then
        ffi.gc(self._ptr, nil)
        self._lib.moonlift_host_session_free(self._ptr)
        self._ptr = nil
    end
end

local function fill_field_init(dst, field, value)
    if not field.host_kind then
        error("field '" .. tostring(field.name) .. "' of layout cannot be initialized by HostArena record builder")
    end
    dst.kind = field.host_kind
    dst.offset = field.offset
    dst.i64_value = 0
    dst.u64_value = 0
    dst.f64_value = 0
    local storage_kind = field.storage_kind or field.kind
    if field.expose_kind == "bool" then
        local encoded = value and 1 or 0
        if storage_kind == "i8" or storage_kind == "i16" or storage_kind == "i32" or storage_kind == "i64" then
            dst.i64_value = encoded
        else
            dst.u64_value = encoded
        end
    elseif storage_kind == "i8" or storage_kind == "i16" or storage_kind == "i32" or storage_kind == "i64" then
        dst.i64_value = value
    elseif storage_kind == "u8" or storage_kind == "u16" or storage_kind == "u32" or storage_kind == "u64" then
        dst.u64_value = value
    elseif storage_kind == "f32" or storage_kind == "f64" then
        dst.f64_value = value
    else
        error("unsupported HostArena field kind " .. tostring(storage_kind))
    end
end

local RecordBuilder = {}
RecordBuilder.__index = RecordBuilder

function Session:record_builder(layout, opts)
    opts = opts or {}
    assert(layout and layout.ctype, "record_builder expects a HostAbi layout")
    local capacity = opts.capacity or 16
    local field_capacity = math.max(1, capacity * #layout.field_order)
    return setmetatable({
        session = self,
        layout = layout,
        tag = opts.tag or 0,
        specs_cap = 0,
        fields_cap = 0,
        specs = nil,
        fields = nil,
        refs = nil,
        ptrs = nil,
    }, RecordBuilder):reserve(capacity, field_capacity)
end

function RecordBuilder:reserve(record_cap, field_cap)
    record_cap = math.max(1, record_cap or 1)
    field_cap = math.max(1, field_cap or record_cap * #self.layout.field_order)
    if record_cap > self.specs_cap then
        self.specs = ffi.new("MoonHostRecordSpec[?]", record_cap)
        self.refs = ffi.new("MoonHostRef[?]", record_cap)
        self.ptrs = ffi.new("MoonHostPtr[?]", record_cap)
        self.specs_cap = record_cap
    end
    if field_cap > self.fields_cap then
        self.fields = ffi.new("MoonHostFieldInit[?]", field_cap)
        self.fields_cap = field_cap
    end
    return self
end

function RecordBuilder:prepare(inits)
    local layout = self.layout
    local n = #inits
    local field_total = 0
    for i = 1, n do
        local init = inits[i] or {}
        for j = 1, #layout.field_order do
            local field = layout.field_order[j]
            if init[field.name] ~= nil then field_total = field_total + 1 end
        end
    end
    self:reserve(n, field_total)

    local field_index = 0
    for i = 1, n do
        local spec = self.specs[i - 1]
        spec.type_id = layout.type_id
        spec.tag = self.tag
        spec.size = layout.size
        spec.align = layout.align
        spec.first_field = field_index
        local first = field_index
        local init = inits[i] or {}
        for j = 1, #layout.field_order do
            local field = layout.field_order[j]
            local value = init[field.name]
            if value ~= nil then
                fill_field_init(self.fields[field_index], field, value)
                field_index = field_index + 1
            end
        end
        spec.field_count = field_index - first
    end
    return n, field_total
end

function RecordBuilder:build_many(inits)
    assert(type(inits) == "table", "build_many expects a table of initializers")
    local n, field_total = self:prepare(inits)
    if n == 0 then return {} end
    local session = self.session
    if session._lib.moonlift_host_alloc_records(session._ptr, self.specs, n, self.fields, field_total, self.refs, self.ptrs) == 0 then
        error(last_error(session._lib))
    end
    local out = {}
    for i = 1, n do
        local typed_ptr = ffi.cast(self.layout:ptr_type(), self.ptrs[i - 1].ptr)
        out[i] = HostAbi.wrap_record_with_ref(self.layout, typed_ptr, self.refs[i - 1], session, { tag = self.tag })
    end
    return out
end

function RecordBuilder:build_one(init)
    local out = self:build_many({ init or {} })
    return out[1]
end

function Session:alloc_record(layout, init, opts)
    return self:record_builder(layout, opts):build_one(init)
end

function Session:alloc_records(layout, inits, opts)
    return self:record_builder(layout, opts):build_many(inits)
end

local function cfield(value, name)
    local ok, got = pcall(function() return value[name] end)
    if ok then return got end
    return nil
end

local function to_host_ref(value_or_ref)
    local value_ref
    if ValueProxy.is_proxy(value_or_ref) then
        value_ref = value_or_ref:raw_ref()[0]
    else
        value_ref = value_or_ref
    end
    local host_ref = ffi.new("MoonHostRef")
    host_ref.session_id = value_ref.session_id
    host_ref.generation = cfield(value_ref, "reserved") or cfield(value_ref, "generation")
    host_ref.kind = cfield(value_ref, "kind") or KIND.RECORD
    host_ref.type_id = value_ref.type_id
    host_ref.tag = value_ref.tag
    host_ref.offset = cfield(value_ref, "value_id") or cfield(value_ref, "offset")
    return host_ref
end

function Session:ptr_for_ref(value_or_ref)
    local ptr = ffi.new("MoonHostPtr[1]")
    local host_ref = to_host_ref(value_or_ref)
    if self._lib.moonlift_host_ptr_for_ref(self._ptr, host_ref, ptr) == 0 then return nil, last_error(self._lib) end
    return ptr[0]
end

M.KIND = KIND
M.Session = Session
M.RecordBuilder = RecordBuilder
M.load_library = load_library

return M
