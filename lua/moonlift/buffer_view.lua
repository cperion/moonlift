local ffi = require("ffi")
local ValueProxy = require("moonlift.value_proxy")

local M = {}

local RECORD_FAMILY = ValueProxy.register_family("buffer_view_record", {})
local VIEW_FAMILY = ValueProxy.register_family("buffer_view_view", {})
local layouts_by_id = {}
local layouts_by_name = {}
local view_layouts_by_id = {}
local view_layouts_by_name = {}
local next_type_id = 1
local installed_cdefs = {}

local function install_cdef_once(key, source)
    if source and source ~= "" and not installed_cdefs[key] then
        ffi.cdef(source)
        installed_cdefs[key] = true
    end
end

local function pointer_ctype(ctype)
    return "const " .. ctype .. "*"
end

local function mutable_pointer_ctype(ctype)
    return ctype .. "*"
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
    if not layout then error("unknown buffer-view record type_id " .. tostring(type_id), 3) end
    return layout
end

local function view_layout_for_type(type_id)
    local layout = view_layouts_by_id[tonumber(type_id)]
    if not layout then error("unknown buffer-view view type_id " .. tostring(type_id), 3) end
    return layout
end

local function wrap_record(layout, storage, opts)
    opts = opts or {}
    local ref = ValueProxy.new_ref(RECORD_FAMILY, {
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

local function wrap_view(layout, descriptor, opts)
    opts = opts or {}
    local ref = ValueProxy.new_ref(VIEW_FAMILY, {
        session_id = opts.session_id or 0,
        type_id = layout.type_id,
        tag = opts.tag or 0,
        value_id = opts.value_id or 0,
        index = opts.index or 0,
        reserved = opts.generation or 0,
    })
    local ptr = ffi.cast(pointer_ctype(layout.ctype), descriptor)
    local owner = opts.owner or { layout = layout, descriptor = descriptor }
    return ValueProxy.wrap(ref, owner, { ptr = ptr, cache = opts.cache })
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

    function layout:mut_ptr_type()
        return mutable_pointer_ctype(self.ctype)
    end

    layouts_by_id[layout.type_id] = layout
    layouts_by_name[layout.name] = layout
    return layout
end

function M.define_view(spec)
    assert(type(spec) == "table", "view spec must be a table")
    assert(type(spec.name) == "string", "view spec missing name")
    assert(type(spec.ctype) == "string", "view spec missing descriptor ctype")
    assert(type(spec.elem) == "table", "view spec missing elem record layout")
    install_cdef_once(spec.cdef_key or spec.name, spec.cdef)

    local layout = {
        name = spec.name,
        ctype = spec.ctype,
        type_id = spec.type_id or next_type_id,
        elem = spec.elem,
        methods = {},
        checked = spec.checked ~= false,
        cdef = spec.cdef,
        cdef_key = spec.cdef_key or spec.name,
    }
    if not spec.type_id then next_type_id = next_type_id + 1 end

    local function descriptor(proxy)
        return ValueProxy.ptr(proxy)[0]
    end

    local function element_ptr(proxy, i)
        i = tonumber(i)
        if not i then error("view index must be a number", 3) end
        local desc = descriptor(proxy)
        local len = tonumber(desc.len)
        if layout.checked and (i < 1 or i > len) then
            error("view index out of bounds: " .. tostring(i), 3)
        end
        local zero = i - 1
        return desc.data + zero * tonumber(desc.stride)
    end

    local function element_proxy(proxy, i)
        return layout.elem:wrap(element_ptr(proxy, i), { owner = proxy })
    end

    local function direct_get(field, elem_ptr)
        local value = elem_ptr[0][field.cfield]
        if field.wrap then return field.wrap(value) end
        if field.expose_kind == "bool" then return value ~= 0 end
        if field.kind == "i8" or field.kind == "i16" or field.kind == "i32" or field.kind == "i64"
            or field.kind == "u8" or field.kind == "u16" or field.kind == "u32" or field.kind == "u64"
            or field.kind == "f32" or field.kind == "f64" then
            return tonumber(value)
        end
        return value
    end

    layout.methods.data = function(proxy)
        return descriptor(proxy).data
    end
    layout.methods.descriptor = function(proxy)
        return ValueProxy.ptr(proxy)
    end
    layout.methods.at = function(proxy, i)
        return element_proxy(proxy, i)
    end
    for i = 1, #layout.elem.field_order do
        local field = layout.elem.field_order[i]
        layout.methods["get_" .. field.name] = function(proxy, index)
            return direct_get(field, element_ptr(proxy, index))
        end
    end

    function layout:new(data, len, stride, opts)
        opts = opts or {}
        local storage = ffi.new(self.ctype .. "[1]")
        storage[0].data = ffi.cast(self.elem:mut_ptr_type(), data)
        storage[0].len = len or 0
        storage[0].stride = stride or 1
        local owner = opts.owner or { layout = self, descriptor = storage, data = data }
        return wrap_view(self, storage, { owner = owner, cache = opts.cache, session_id = opts.session_id, value_id = opts.value_id, generation = opts.generation })
    end

    function layout:wrap(descriptor, opts)
        return wrap_view(self, descriptor, opts)
    end

    view_layouts_by_id[layout.type_id] = layout
    view_layouts_by_name[layout.name] = layout
    return layout
end

function M.define_view_from_host_descriptor(spec)
    assert(type(spec) == "table", "host descriptor view spec must be a table")
    assert(type(spec.descriptor) == "table", "host descriptor view spec missing descriptor")
    assert(type(spec.elem) == "table", "host descriptor view spec missing elem record layout")
    local cdef = spec.cdef
    if type(cdef) == "table" then cdef = cdef.source end
    return M.define_view({
        name = spec.name or spec.descriptor.name,
        elem = spec.elem,
        ctype = spec.descriptor.descriptor_layout.ctype,
        cdef = cdef,
        cdef_key = spec.cdef_key or spec.descriptor.descriptor_layout.ctype,
        checked = spec.checked,
        type_id = spec.type_id,
    })
end

function M.layout(name_or_id)
    if type(name_or_id) == "number" then return layouts_by_id[name_or_id] end
    return layouts_by_name[name_or_id]
end

function M.view_layout(name_or_id)
    if type(name_or_id) == "number" then return view_layouts_by_id[name_or_id] end
    return view_layouts_by_name[name_or_id]
end

local RecordFamily = ValueProxy.family(RECORD_FAMILY)

RecordFamily.index = function(proxy, key, ref)
    local layout = layout_for_type(ref.type_id)
    local method = layout.methods[key]
    if method then return method end
    local getter = layout.getters[key]
    if not getter then return nil end
    return getter(proxy)
end

RecordFamily.pairs = function(proxy, ref)
    local layout = layout_for_type(ref.type_id)
    local i = 0
    return function()
        i = i + 1
        local field = layout.field_order[i]
        if not field then return nil end
        return field.name, proxy[field.name]
    end
end

RecordFamily.to_table = function(proxy, ref)
    local layout = layout_for_type(ref.type_id)
    local out = {}
    for i = 1, #layout.field_order do
        local field = layout.field_order[i]
        out[field.name] = proxy[field.name]
    end
    return out
end

RecordFamily.tostring = function(_, ref)
    local layout = layout_for_type(ref.type_id)
    return "MoonBufferView(" .. layout.name .. ")"
end

local ViewFamily = ValueProxy.family(VIEW_FAMILY)

ViewFamily.index = function(proxy, key, ref)
    local layout = view_layout_for_type(ref.type_id)
    if type(key) == "number" then
        return layout.methods.at(proxy, key)
    end
    if key == "len" then return tonumber(ValueProxy.ptr(proxy)[0].len) end
    if key == "stride" then return tonumber(ValueProxy.ptr(proxy)[0].stride) end
    local method = layout.methods[key]
    if method then return method end
    return nil
end

ViewFamily.len = function(proxy)
    return tonumber(ValueProxy.ptr(proxy)[0].len)
end

ViewFamily.ipairs = function(proxy, ref)
    local layout = view_layout_for_type(ref.type_id)
    local i = 0
    local n = tonumber(ValueProxy.ptr(proxy)[0].len)
    return function()
        i = i + 1
        if i > n then return nil end
        return i, layout.methods.at(proxy, i)
    end
end

ViewFamily.to_table = function(proxy, ref)
    local out = {}
    local n = tonumber(ValueProxy.ptr(proxy)[0].len)
    for i = 1, n do
        local elem = proxy[i]
        out[i] = elem:to_table()
    end
    return out
end

ViewFamily.tostring = function(_, ref)
    local layout = view_layout_for_type(ref.type_id)
    return "MoonBufferViewSeq(" .. layout.name .. ")"
end

M.RECORD_FAMILY = RECORD_FAMILY
M.VIEW_FAMILY = VIEW_FAMILY

return M
