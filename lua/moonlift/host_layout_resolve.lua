local ffi = require("ffi")
local pvm = require("moonlift.pvm")

local M = {}

local function stable_name(text)
    text = tostring(text or "anon")
    return (text:gsub("[^%w_%.%-]", "_"))
end

local function c_ident(text)
    text = stable_name(text):gsub("[%.%-]", "_")
    if not text:match("^[A-Za-z_]") then text = "_" .. text end
    return text
end

local function align_to(offset, align)
    align = align or 1
    if align <= 1 then return offset end
    local rem = offset % align
    if rem == 0 then return offset end
    return offset + (align - rem)
end

function M.Define(T)
    local H = T.MoonHost
    local Ty = T.MoonType
    local C = T.MoonCore

    local scalar_size_align = {
        [C.ScalarBool] = { 1, 1 },
        [C.ScalarI8] = { 1, 1 }, [C.ScalarU8] = { 1, 1 },
        [C.ScalarI16] = { 2, 2 }, [C.ScalarU16] = { 2, 2 },
        [C.ScalarI32] = { 4, 4 }, [C.ScalarU32] = { 4, 4 }, [C.ScalarF32] = { 4, 4 },
        [C.ScalarI64] = { 8, 8 }, [C.ScalarU64] = { 8, 8 }, [C.ScalarF64] = { 8, 8 },
    }

    local scalar_c = {
        [C.ScalarBool] = "uint8_t",
        [C.ScalarI8] = "int8_t", [C.ScalarU8] = "uint8_t",
        [C.ScalarI16] = "int16_t", [C.ScalarU16] = "uint16_t",
        [C.ScalarI32] = "int32_t", [C.ScalarU32] = "uint32_t",
        [C.ScalarI64] = "int64_t", [C.ScalarU64] = "uint64_t",
        [C.ScalarF32] = "float", [C.ScalarF64] = "double",
        [C.ScalarRawPtr] = "void*",
        [C.ScalarIndex] = "intptr_t",
        [C.ScalarVoid] = "void",
    }

    local function host_endian()
        local u = ffi.new("uint16_t[1]", 0x0102)
        local p = ffi.cast("uint8_t*", u)
        if p[0] == 0x02 then return H.HostEndianLittle end
        return H.HostEndianBig
    end

    local function default_target_model()
        local bits = ffi.abi("64bit") and 64 or 32
        return H.HostTargetModel(bits, bits, host_endian())
    end

    local function target_bytes(bits)
        bits = tonumber(bits or 64) or 64
        return math.floor(bits / 8)
    end

    local function scalar_size_align_for(scalar, target)
        if scalar == C.ScalarRawPtr then
            local n = target_bytes((target or default_target_model()).pointer_bits)
            return n, n
        end
        if scalar == C.ScalarIndex then
            local n = target_bytes((target or default_target_model()).index_bits)
            return n, n
        end
        local got = scalar_size_align[scalar]
        if got then return got[1], got[2] end
        return 0, 1
    end

    local function bool_storage_scalar(encoding)
        if encoding == H.HostBoolI32 then return C.ScalarI32 end
        if encoding == H.HostBoolU8 then return C.ScalarU8 end
        return C.ScalarBool
    end

    local function rep_from_type(ty)
        if pvm.classof(ty) == Ty.TScalar then
            if ty.scalar == C.ScalarBool then return H.HostRepBool(H.HostBoolNative, C.ScalarBool) end
            return H.HostRepScalar(ty.scalar)
        end
        if pvm.classof(ty) == Ty.TPtr then return H.HostRepPtr(ty.elem) end
        if pvm.classof(ty) == Ty.TView then return H.HostRepView(ty.elem) end
        return H.HostRepOpaque("type")
    end

    local function rep_from_storage(field)
        local storage = field.storage
        if storage == H.HostStorageSame then return rep_from_type(field.expose_ty) end
        local cls = pvm.classof(storage)
        if cls == H.HostStorageScalar then return H.HostRepScalar(storage.scalar) end
        if cls == H.HostStorageBool then return H.HostRepBool(storage.encoding, storage.scalar) end
        if cls == H.HostStoragePtr then return H.HostRepPtr(storage.pointee) end
        if cls == H.HostStorageSlice then return H.HostRepSlice(rep_from_type(storage.elem)) end
        if cls == H.HostStorageView then return H.HostRepView(storage.elem) end
        if cls == H.HostStorageOpaque then return H.HostRepOpaque(storage.name) end
        return H.HostRepOpaque("unknown")
    end

    local function rep_size_align(rep, target)
        local cls = pvm.classof(rep)
        if cls == H.HostRepScalar then return scalar_size_align_for(rep.scalar, target) end
        if cls == H.HostRepBool then return scalar_size_align_for(rep.storage or bool_storage_scalar(rep.encoding), target) end
        if cls == H.HostRepPtr then return scalar_size_align_for(C.ScalarRawPtr, target) end
        if cls == H.HostRepRef then return scalar_size_align_for(C.ScalarRawPtr, target) end
        if cls == H.HostRepStruct then return 0, 1 end
        if cls == H.HostRepSlice then
            local ps, pa = scalar_size_align_for(C.ScalarRawPtr, target)
            local is, ia = scalar_size_align_for(C.ScalarIndex, target)
            return align_to(ps, ia) + is, math.max(pa, ia)
        end
        if cls == H.HostRepView then
            local ps, pa = scalar_size_align_for(C.ScalarRawPtr, target)
            local is, ia = scalar_size_align_for(C.ScalarIndex, target)
            local len_off = align_to(ps, ia)
            local stride_off = align_to(len_off + is, ia)
            return align_to(stride_off + is, math.max(pa, ia)), math.max(pa, ia)
        end
        return 0, 1
    end

    local function rep_c_type(rep)
        local cls = pvm.classof(rep)
        if cls == H.HostRepScalar then return scalar_c[rep.scalar] or "uint8_t" end
        if cls == H.HostRepBool then return scalar_c[rep.storage or bool_storage_scalar(rep.encoding)] or "uint8_t" end
        if cls == H.HostRepPtr or cls == H.HostRepRef then return "void*" end
        if cls == H.HostRepSlice or cls == H.HostRepView then return "void*" end
        return "uint8_t"
    end

    local function resolve_fields(decl, target)
        local repr_cls = pvm.classof(decl.repr)
        local pack_align = repr_cls == H.HostReprPacked and decl.repr.align or nil
        local fields, offset, struct_align = {}, 0, 1
        for i = 1, #decl.fields do
            local field = decl.fields[i]
            local rep = rep_from_storage(field)
            local size, align = rep_size_align(rep, target)
            if pack_align ~= nil then align = math.min(align, pack_align) end
            offset = align_to(offset, align)
            fields[i] = H.HostFieldLayout(field.id, field.name, c_ident(field.name), rep, offset, size, align)
            offset = offset + size
            if align > struct_align then struct_align = align end
        end
        if pack_align ~= nil then struct_align = math.min(struct_align, pack_align) end
        return fields, align_to(offset, struct_align), struct_align
    end

    local function cdef_for_layout(layout, decl)
        local prefix = "typedef struct " .. layout.ctype
        if decl and pvm.classof(decl.repr) == H.HostReprPacked then
            prefix = "typedef struct __attribute__((packed, aligned(" .. tostring(decl.repr.align) .. "))) " .. layout.ctype
        end
        local lines = { prefix .. " {" }
        for i = 1, #layout.fields do
            local f = layout.fields[i]
            lines[#lines + 1] = rep_c_type(f.rep) .. " " .. f.cfield .. ";"
        end
        lines[#lines + 1] = "} " .. layout.ctype .. ";"
        return H.HostCdef(layout.id, table.concat(lines, "\n"))
    end

    local function layout_from_decl(decl, target)
        target = target or default_target_model()
        local fields, size, align = resolve_fields(decl, target)
        local ctype = c_ident(decl.name)
        return H.HostTypeLayout(decl.id, decl.name, ctype, H.HostLayoutStruct, size, align, fields)
    end

    local fact_phase = pvm.phase("moonlift_host_layout_resolve", {
        [H.HostStructDecl] = function(self, target)
            local layout = layout_from_decl(self, target)
            local facts = { H.HostFactTypeLayout(layout) }
            facts[#facts + 1] = H.HostFactCdef(cdef_for_layout(layout, self))
            for i = 1, #layout.fields do
                facts[#facts + 1] = H.HostFactField(layout.id, layout.fields[i])
            end
            return pvm.T.seq(facts)
        end,
    }, { args_cache = "full" })

    local function resolve_facts(decl, target)
        local g, p, c = fact_phase(decl, target or default_target_model())
        return H.HostFactSet(pvm.drain(g, p, c))
    end

    local function resolve_layout(decl, target)
        target = target or default_target_model()
        local facts = resolve_facts(decl, target)
        for i = 1, #facts.facts do
            local fact = facts.facts[i]
            if pvm.classof(fact) == H.HostFactTypeLayout then return fact.layout, facts end
        end
        return nil, facts
    end

    local function env_from_layouts(layouts)
        return H.HostLayoutEnv(layouts or {})
    end

    return {
        phase = fact_phase,
        default_target_model = default_target_model,
        scalar_size_align_for = scalar_size_align_for,
        rep_from_storage = rep_from_storage,
        rep_size_align = rep_size_align,
        rep_c_type = rep_c_type,
        cdef_for_layout = cdef_for_layout,
        layout_from_decl = layout_from_decl,
        resolve_facts = resolve_facts,
        resolve_layout = resolve_layout,
        env_from_layouts = env_from_layouts,
    }
end

return M
