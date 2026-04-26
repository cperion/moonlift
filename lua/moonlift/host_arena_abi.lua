local ffi = require("ffi")
local ValueProxy = require("moonlift.value_proxy")

local M = {}

local TYPED_RECORD_FAMILY = ValueProxy.register_family("host_typed_record", {})
local layouts_by_id = {}
local layouts_by_name = {}
local next_type_id = 1
local installed_cdefs = {}

local HOST_FIELD_KIND = {
    bool = 1,
    i8 = 2,
    i16 = 3,
    i32 = 4,
    i64 = 5,
    u8 = 6,
    u16 = 7,
    u32 = 8,
    u64 = 9,
    f32 = 10,
    f64 = 11,
}

local function install_cdef_once(key, source)
    if source and source ~= "" and not installed_cdefs[key] then
        ffi.cdef(source)
        installed_cdefs[key] = true
    end
end

local function pointer_ctype(ctype)
    return "const " .. ctype .. "*"
end

local function scalar_set(record, field, value)
    if field.expose_kind == "bool" then
        record[field.cfield] = value and 1 or 0
    else
        record[field.cfield] = value
    end
end

local function layout_for_type(type_id)
    local layout = layouts_by_id[tonumber(type_id)]
    if not layout then error("unknown host typed-record type_id " .. tostring(type_id), 3) end
    return layout
end

local function wrap_record(layout, storage, opts)
    opts = opts or {}
    local ref = ValueProxy.new_ref(TYPED_RECORD_FAMILY, {
        session_id = opts.session_id or 0,
        type_id = layout.type_id,
        tag = opts.tag or 0,
        value_id = opts.value_id or 0,
        index = opts.index or 0,
        reserved = opts.generation or 0,
    })
    local ptr = ffi.cast(pointer_ctype(layout.ctype), storage)
    local owner = opts.owner or { layout = layout, storage = storage }
    return ValueProxy.wrap(ref, owner, { ptr = ptr, cache = opts.cache })
end

local function ref_value(host_ref)
    local ok, value = pcall(function() return host_ref[0] end)
    if ok then return value end
    return host_ref
end

function M.wrap_record_with_ref(layout, storage, host_ref, owner, opts)
    opts = opts or {}
    local r = ref_value(host_ref)
    local proxy_ref = ValueProxy.new_ref(TYPED_RECORD_FAMILY, {
        session_id = tonumber(r.session_id),
        type_id = layout.type_id,
        tag = tonumber(r.tag),
        value_id = tonumber(r.offset),
        index = tonumber(r.offset),
        reserved = tonumber(r.generation),
    })
    local ptr = ffi.cast(pointer_ctype(layout.ctype), storage)
    return ValueProxy.wrap(proxy_ref, owner or { layout = layout }, { ptr = ptr, cache = opts.cache })
end

function M.define_record(spec)
    assert(type(spec) == "table", "record spec must be a table")
    assert(type(spec.name) == "string", "record spec missing name")
    assert(type(spec.ctype) == "string", "record spec missing ctype")
    assert(type(spec.fields) == "table", "record spec missing fields")
    install_cdef_once(spec.cdef_key or spec.name, spec.cdef)

    local layout = {
        name = spec.name,
        ctype = spec.ctype,
        type_id = spec.type_id or next_type_id,
        fields = {},
        field_order = {},
        getters = {},
        methods = spec.methods or {},
        cdef = spec.cdef,
        cdef_key = spec.cdef_key or spec.name,
    }
    if not spec.type_id then next_type_id = next_type_id + 1 end

    for i = 1, #spec.fields do
        local field = spec.fields[i]
        assert(type(field.name) == "string", "record field missing name")
        local cfield = field.cfield or field.name
        local f = {
            name = field.name,
            cfield = cfield,
            kind = field.kind or "value",
            storage_kind = field.storage_kind or field.kind or "value",
            expose_kind = field.expose_kind or field.kind or "value",
            host_kind = field.host_kind or HOST_FIELD_KIND[field.kind],
            offset = tonumber(ffi.offsetof(layout.ctype, cfield)),
            wrap = field.wrap,
        }
        layout.fields[f.name] = f
        layout.field_order[#layout.field_order + 1] = f
        if f.wrap then
            layout.getters[f.name] = function(proxy)
                local ptr = ValueProxy.ptr(proxy)
                return f.wrap(ptr[0][cfield], proxy, layout, f)
            end
        elseif f.expose_kind == "bool" then
            layout.getters[f.name] = function(proxy)
                local ptr = ValueProxy.ptr(proxy)
                return ptr[0][cfield] ~= 0
            end
        elseif f.kind == "i8" or f.kind == "i16" or f.kind == "i32" or f.kind == "i64"
            or f.kind == "u8" or f.kind == "u16" or f.kind == "u32" or f.kind == "u64"
            or f.kind == "f32" or f.kind == "f64" then
            layout.getters[f.name] = function(proxy)
                local ptr = ValueProxy.ptr(proxy)
                return tonumber(ptr[0][cfield])
            end
        else
            layout.getters[f.name] = function(proxy)
                local ptr = ValueProxy.ptr(proxy)
                return ptr[0][cfield]
            end
        end
    end

    layout.size = tonumber(ffi.sizeof(layout.ctype))
    layout.align = tonumber(ffi.alignof(layout.ctype))

    function layout:new(init, opts)
        local storage = ffi.new(self.ctype .. "[1]")
        init = init or {}
        for i = 1, #self.field_order do
            local field = self.field_order[i]
            local value = init[field.name]
            if value ~= nil then scalar_set(storage[0], field, value) end
        end
        return wrap_record(self, storage, opts)
    end

    function layout:wrap(storage, opts)
        return wrap_record(self, storage, opts)
    end

    function layout:ptr_type()
        return pointer_ctype(self.ctype)
    end

    layouts_by_id[layout.type_id] = layout
    layouts_by_name[layout.name] = layout
    return layout
end

function M.layout(name_or_id)
    if type(name_or_id) == "number" then return layouts_by_id[name_or_id] end
    return layouts_by_name[name_or_id]
end

local TypedRecordFamily = ValueProxy.family(TYPED_RECORD_FAMILY)

TypedRecordFamily.index = function(proxy, key, ref)
    local layout = layout_for_type(ref.type_id)
    local method = layout.methods[key]
    if method then return method end
    local getter = layout.getters[key]
    if not getter then return nil end
    return getter(proxy)
end

TypedRecordFamily.pairs = function(proxy, ref)
    local layout = layout_for_type(ref.type_id)
    local i = 0
    return function()
        i = i + 1
        local field = layout.field_order[i]
        if not field then return nil end
        return field.name, proxy[field.name]
    end
end

TypedRecordFamily.to_table = function(proxy, ref)
    local layout = layout_for_type(ref.type_id)
    local out = {}
    for i = 1, #layout.field_order do
        local field = layout.field_order[i]
        out[field.name] = proxy[field.name]
    end
    return out
end

TypedRecordFamily.tostring = function(_, ref)
    local layout = layout_for_type(ref.type_id)
    return "MoonHostRecord(" .. layout.name .. ")"
end

M.HOST_FIELD_KIND = HOST_FIELD_KIND
M.TYPED_RECORD_FAMILY = TYPED_RECORD_FAMILY

return M
