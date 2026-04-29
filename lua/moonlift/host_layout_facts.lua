local pvm = require("moonlift.pvm")
local ffi = require("ffi")

local M = {}

function M.Define(T)
    local H = T.Moon2Host
    local C = T.Moon2Core
    local Ty = T.Moon2Type

    local scalar_by_kind = {
        bool = C.ScalarU8,
        i8 = C.ScalarI8,
        i16 = C.ScalarI16,
        i32 = C.ScalarI32,
        i64 = C.ScalarI64,
        u8 = C.ScalarU8,
        u16 = C.ScalarU16,
        u32 = C.ScalarU32,
        u64 = C.ScalarU64,
        f32 = C.ScalarF32,
        f64 = C.ScalarF64,
        ptr = C.ScalarRawPtr,
        rawptr = C.ScalarRawPtr,
        index = C.ScalarIndex,
    }

    local size_align_by_kind = {
        bool = { 1, 1 },
        i8 = { 1, 1 },
        u8 = { 1, 1 },
        i16 = { 2, 2 },
        u16 = { 2, 2 },
        i32 = { 4, 4 },
        u32 = { 4, 4 },
        f32 = { 4, 4 },
        i64 = { 8, 8 },
        u64 = { 8, 8 },
        f64 = { 8, 8 },
    }

    local function stable_name(text)
        text = tostring(text or "anon")
        return (text:gsub("[^%w_%.%-]", "_"))
    end

    local function scalar_for_kind(kind)
        return scalar_by_kind[tostring(kind or "")]
    end

    local function host_endian()
        local u = ffi.new("uint16_t[1]", 0x0102)
        local p = ffi.cast("uint8_t*", u)
        if p[0] == 0x02 then return H.HostEndianLittle end
        return H.HostEndianBig
    end

    local function default_target_model()
        local pointer_bits = ffi.abi("64bit") and 64 or 32
        return H.HostTargetModel(pointer_bits, pointer_bits, host_endian())
    end

    local function target_bytes(bits)
        bits = tonumber(bits or 64) or 64
        return math.floor(bits / 8)
    end

    local function size_align_for_kind(kind, target)
        kind = tostring(kind or "")
        if kind == "ptr" or kind == "rawptr" then
            local n = target_bytes((target or default_target_model()).pointer_bits)
            return n, n
        end
        if kind == "index" then
            local n = target_bytes((target or default_target_model()).index_bits)
            return n, n
        end
        local got = size_align_by_kind[kind]
        if got then return got[1], got[2] end
        return 0, 1
    end

    local function bool_encoding_for_storage(kind)
        kind = tostring(kind or "")
        if kind == "i32" or kind == "u32" then return H.HostBoolI32 end
        if kind == "bool" or kind == "u8" or kind == "i8" then return H.HostBoolU8 end
        return H.HostBoolNative
    end

    local function rep_for_field(field)
        local storage_kind = field.storage_kind or field.kind
        local expose_kind = field.expose_kind or field.kind
        local storage = scalar_for_kind(storage_kind)
        if expose_kind == "bool" then
            return H.HostRepBool(bool_encoding_for_storage(storage_kind), storage or C.ScalarU8)
        end
        if storage then return H.HostRepScalar(storage) end
        return H.HostRepOpaque(tostring(storage_kind or expose_kind or "unknown"))
    end

    local function field_layout(layout, field, target)
        local storage_kind = field.storage_kind or field.kind
        local size, align = size_align_for_kind(storage_kind, target)
        local key = stable_name((layout.name or layout.ctype or "layout") .. "." .. field.name)
        return H.HostFieldLayout(
            H.HostFieldId(key, field.name),
            field.name,
            field.cfield or field.name,
            rep_for_field(field),
            field.offset or 0,
            size,
            align
        )
    end

    local function layout_id(layout, opts)
        opts = opts or {}
        local name = opts.name or layout.name or layout.ctype or "HostLayout"
        local key = opts.key or name
        return H.HostLayoutId(stable_name(key), name)
    end

    local function align_to(offset, align)
        align = align or 1
        if align <= 1 then return offset end
        local rem = offset % align
        if rem == 0 then return offset end
        return offset + (align - rem)
    end

    local function descriptor_c_ident(name)
        name = stable_name(name):gsub("[%.%-]", "_")
        if not name:match("^[A-Za-z_]") then name = "_" .. name end
        return name
    end

    local function named_layout_type(type_layout, opts)
        opts = opts or {}
        return Ty.TNamed(Ty.TypeRefGlobal(opts.module_name or "host", type_layout.name))
    end

    local function view_descriptor_layout(type_layout, opts)
        opts = opts or {}
        local target = opts.target_model or default_target_model()
        local ptr_size, ptr_align = size_align_for_kind("ptr", target)
        local index_size, index_align = size_align_for_kind("index", target)
        local align = math.max(ptr_align, index_align)
        local data_offset = 0
        local len_offset = align_to(data_offset + ptr_size, index_align)
        local stride_offset = align_to(len_offset + index_size, index_align)
        local size = align_to(stride_offset + index_size, align)
        local name = opts.descriptor_layout_name or ("MoonView_" .. descriptor_c_ident(type_layout.name))
        local ctype = opts.ctype or name
        local id = H.HostLayoutId(stable_name(opts.key or name), name)
        local fields = {
            H.HostFieldLayout(H.HostFieldId(stable_name(name .. ".data"), "data"), "data", "data", H.HostRepPtr(named_layout_type(type_layout, opts)), data_offset, ptr_size, ptr_align),
            H.HostFieldLayout(H.HostFieldId(stable_name(name .. ".len"), "len"), "len", "len", H.HostRepScalar(C.ScalarIndex), len_offset, index_size, index_align),
            H.HostFieldLayout(H.HostFieldId(stable_name(name .. ".stride"), "stride"), "stride", "stride", H.HostRepScalar(C.ScalarIndex), stride_offset, index_size, index_align),
        }
        return H.HostTypeLayout(id, name, ctype, H.HostLayoutViewDescriptor, size, align, fields)
    end

    local function view_descriptor_cdef(type_layout, descriptor_layout)
        return H.HostCdef(descriptor_layout.id, table.concat({
            "typedef struct " .. descriptor_layout.ctype .. " {",
            type_layout.ctype .. "* data;",
            "intptr_t len;",
            "intptr_t stride;",
            "} " .. descriptor_layout.ctype .. ";",
        }, "\n"))
    end

    local function view_descriptor_for_layout(type_layout, opts)
        opts = opts or {}
        local descriptor_layout = view_descriptor_layout(type_layout, opts)
        local abi
        if opts.contiguous then
            abi = H.HostViewAbiContiguous(type_layout)
        else
            abi = H.HostViewAbiStrided(type_layout, opts.stride_unit or H.HostStrideElements)
        end
        local name = opts.name or (type_layout.name .. "View")
        local id = H.HostLayoutId(stable_name(opts.view_key or name), name)
        return H.HostViewDescriptor(id, name, abi, descriptor_layout), view_descriptor_cdef(type_layout, descriptor_layout)
    end

    local function fact_set_for_view_descriptor(type_layout, opts)
        local descriptor, cdef = view_descriptor_for_layout(type_layout, opts)
        local layout = descriptor.descriptor_layout
        local facts = {
            H.HostFactTypeLayout(layout),
            H.HostFactCdef(cdef),
        }
        for i = 1, #layout.fields do
            facts[#facts + 1] = H.HostFactField(layout.id, layout.fields[i])
        end
        facts[#facts + 1] = H.HostFactViewDescriptor(descriptor)
        return H.HostFactSet(facts), descriptor, layout
    end

    local function type_layout_from_buffer_view(layout, opts)
        opts = opts or {}
        local target = opts.target_model or default_target_model()
        local fields = {}
        for i = 1, #(layout.field_order or {}) do
            fields[i] = field_layout(layout, layout.field_order[i], target)
        end
        return H.HostTypeLayout(
            layout_id(layout, opts),
            opts.name or layout.name,
            opts.ctype or layout.ctype,
            opts.kind or H.HostLayoutStruct,
            layout.size or 0,
            layout.align or 1,
            fields
        )
    end

    local access_plan_phase = pvm.phase("moon2_host_access_plan", {
        [H.HostTypeLayout] = function(self)
            local subject = H.HostAccessRecord(self)
            local entries = {}
            entries[#entries + 1] = H.HostAccessEntry(H.HostAccessMethod("ptr"), H.HostAccessPointerCast(self))
            for i = 1, #self.fields do
                local field = self.fields[i]
                if pvm.classof(field.rep) == H.HostRepBool then
                    entries[#entries + 1] = H.HostAccessEntry(H.HostAccessField(field.name), H.HostAccessDecodeBool(field))
                else
                    entries[#entries + 1] = H.HostAccessEntry(H.HostAccessField(field.name), H.HostAccessDirectField(field))
                end
            end
            entries[#entries + 1] = H.HostAccessEntry(H.HostAccessPairs, H.HostAccessIterateFields(self.id))
            entries[#entries + 1] = H.HostAccessEntry(H.HostAccessToTable, H.HostAccessMaterializeTable(subject))
            return pvm.once(H.HostAccessPlan(subject, entries))
        end,
    })

    local view_access_plan_phase = pvm.phase("moon2_host_view_access_plan", {
        [H.HostViewDescriptor] = function(self)
            local subject = H.HostAccessView(self)
            local elem_layout = self.abi.elem_layout
            local entries = {
                H.HostAccessEntry(H.HostAccessLen, H.HostAccessViewLen(self)),
                H.HostAccessEntry(H.HostAccessData, H.HostAccessViewData(self)),
                H.HostAccessEntry(H.HostAccessStride, H.HostAccessViewStride(self)),
                H.HostAccessEntry(H.HostAccessIndex, H.HostAccessViewIndex(self)),
            }
            for i = 1, #elem_layout.fields do
                local field = elem_layout.fields[i]
                entries[#entries + 1] = H.HostAccessEntry(H.HostAccessMethod("get_" .. field.name), H.HostAccessViewFieldAt(self, field))
            end
            entries[#entries + 1] = H.HostAccessEntry(H.HostAccessToTable, H.HostAccessMaterializeTable(subject))
            return pvm.once(H.HostAccessPlan(subject, entries))
        end,
    })

    local function access_plan(layout)
        return pvm.one(access_plan_phase(layout))
    end

    local function view_access_plan(descriptor)
        return pvm.one(view_access_plan_phase(descriptor))
    end

    local function expose_mode(opts)
        opts = opts or {}
        if opts.expose then return opts.expose end
        return H.HostExposeProxy(
            opts.proxy_kind or H.HostProxyBufferView,
            opts.cache or H.HostProxyCacheNone,
            opts.mutability or H.HostReadonly,
            opts.bounds or H.HostBoundsChecked
        )
    end

    local function owner_mode(opts)
        opts = opts or {}
        return opts.owner or H.HostOwnerBufferView
    end

    local function view_plan(type_layout, opts)
        local access = access_plan(type_layout)
        return H.HostViewPlan(type_layout, owner_mode(opts), expose_mode(opts), access)
    end

    local function producer_plan(name, kind, outputs)
        return H.HostProducerPlan(name, kind or H.HostProducerLowLevelMoonlift, outputs or {})
    end

    local function fact_set_for_buffer_view(layout, opts)
        opts = opts or {}
        local ty = type_layout_from_buffer_view(layout, opts)
        local access = access_plan(ty)
        local view = H.HostViewPlan(ty, owner_mode(opts), expose_mode(opts), access)
        local facts = { H.HostFactTypeLayout(ty) }
        if layout.cdef and layout.cdef ~= "" then
            facts[#facts + 1] = H.HostFactCdef(H.HostCdef(ty.id, layout.cdef))
        end
        for i = 1, #ty.fields do
            facts[#facts + 1] = H.HostFactField(ty.id, ty.fields[i])
        end
        facts[#facts + 1] = H.HostFactExpose(ty.name, ty.id, H.HostExposeFacet(H.HostExposeLua, H.HostExposeAbiDefault, view.expose))
        facts[#facts + 1] = H.HostFactAccessPlan(access)
        facts[#facts + 1] = H.HostFactViewPlan(view)
        facts[#facts + 1] = H.HostFactProducer(producer_plan(opts.producer_name or ty.name, opts.producer_kind or H.HostProducerLowLevelMoonlift, { ty }))
        return H.HostFactSet(facts), ty, view
    end

    return {
        scalar_for_kind = scalar_for_kind,
        rep_for_field = rep_for_field,
        default_target_model = default_target_model,
        size_align_for_kind = size_align_for_kind,
        field_layout = field_layout,
        view_descriptor_layout = view_descriptor_layout,
        view_descriptor_for_layout = view_descriptor_for_layout,
        fact_set_for_view_descriptor = fact_set_for_view_descriptor,
        type_layout_from_buffer_view = type_layout_from_buffer_view,
        access_plan = access_plan,
        view_access_plan = view_access_plan,
        view_plan = view_plan,
        fact_set_for_buffer_view = fact_set_for_buffer_view,
        producer_plan = producer_plan,
    }
end

return M
