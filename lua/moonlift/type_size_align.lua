local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.type_size_align ~= nil then return T._moonlift_api_cache.type_size_align end

    local Core = T.MoonCore
    local Ty = T.MoonType
    local Sem = T.MoonSem

    local classify_api = require("moonlift.type_classify").Define(T)

    local scalar_layout
    local class_layout
    local type_layout_result
    local named_layout_lookup
    local result_layout

    local function known(size, align)
        return Ty.TypeMemLayoutKnown(Sem.MemLayout(size, align))
    end

    local function target_bits(target, field)
        if target ~= nil and target.c_target ~= nil then target = target.c_target end
        local bits
        if target ~= nil then bits = target[field] end
        if bits == nil and field == "index_bits" and target ~= nil then bits = target.pointer_bits end
        bits = bits or 64
        if bits ~= 32 and bits ~= 64 then
            error("type_size_align: unsupported C layout target " .. field .. "=" .. tostring(bits), 3)
        end
        return bits
    end

    local function layout_from_bits(bits)
        local bytes = bits / 8
        return known(bytes, bytes)
    end

    local function ptr_layout(target)
        return layout_from_bits(target_bits(target, "pointer_bits"))
    end

    local function index_layout(target)
        return layout_from_bits(target_bits(target, "index_bits"))
    end

    local function raw_layout(result)
        local layout = result_layout(result)
        assert(layout ~= nil, "internal layout helper expected known layout")
        return layout
    end

    local function align_up(n, align)
        return math.floor((n + align - 1) / align) * align
    end

    local function product_layout(fields)
        local offset, max_align = 0, 1
        for i = 1, #fields do
            local f = fields[i]
            offset = align_up(offset, f.align)
            offset = offset + f.size
            if f.align > max_align then max_align = f.align end
        end
        return known(align_up(offset, max_align), max_align)
    end

    scalar_layout = pvm.phase("moonlift_type_scalar_mem_layout", {
        [Core.ScalarVoid] = function() return pvm.once(known(0, 1)) end,
        [Core.ScalarBool] = function() return pvm.once(known(1, 1)) end,
        [Core.ScalarI8] = function() return pvm.once(known(1, 1)) end,
        [Core.ScalarU8] = function() return pvm.once(known(1, 1)) end,
        [Core.ScalarI16] = function() return pvm.once(known(2, 2)) end,
        [Core.ScalarU16] = function() return pvm.once(known(2, 2)) end,
        [Core.ScalarI32] = function() return pvm.once(known(4, 4)) end,
        [Core.ScalarU32] = function() return pvm.once(known(4, 4)) end,
        [Core.ScalarF32] = function() return pvm.once(known(4, 4)) end,
        [Core.ScalarI64] = function() return pvm.once(known(8, 8)) end,
        [Core.ScalarU64] = function() return pvm.once(known(8, 8)) end,
        [Core.ScalarF64] = function() return pvm.once(known(8, 8)) end,
        [Core.ScalarRawPtr] = function(_, target) return pvm.once(ptr_layout(target)) end,
        [Core.ScalarIndex] = function(_, target) return pvm.once(index_layout(target)) end,
    })

    named_layout_lookup = pvm.phase("moonlift_type_named_layout_lookup", function(env, module_name, type_name)
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            if layout.module_name == module_name and layout.type_name == type_name then
                return Sem.MemLayout(layout.size, layout.align)
            end
        end
        return nil
    end)

    function result_layout(result)
        if result ~= nil and pvm.classof(result) == Ty.TypeMemLayoutKnown then
            return result.layout
        end
        return nil
    end

    local function layout_for_named_ref(ref, env)
        env = env or Sem.LayoutEnv({})
        local ref_cls = pvm.classof(ref)
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            local layout_cls = pvm.classof(layout)
            if ref_cls == Ty.TypeRefGlobal and layout_cls == Sem.LayoutNamed
                and layout.module_name == ref.module_name and layout.type_name == ref.type_name then
                return layout
            end
            if ref_cls == Ty.TypeRefPath and layout_cls == Sem.LayoutNamed
                and #ref.path.parts == 1 and layout.type_name == ref.path.parts[1].text then
                return layout
            end
            if ref_cls == Ty.TypeRefLocal and layout_cls == Sem.LayoutLocal and layout.sym == ref.sym then
                return layout
            end
        end
        return nil
    end

    class_layout = pvm.phase("moonlift_type_class_mem_layout", {
        [Ty.TypeClassScalar] = function(self, ty, env, target)
            return scalar_layout(self.scalar, target)
        end,
        [Ty.TypeClassPointer] = function(self, ty, env, target)
            return pvm.once(ptr_layout(target))
        end,
        [Ty.TypeClassCallable] = function(self, ty, env, target)
            return pvm.once(ptr_layout(target))
        end,
        [Ty.TypeClassSlice] = function(self, ty, env, target)
            local ptr = raw_layout(ptr_layout(target))
            local index = raw_layout(index_layout(target))
            return pvm.once(product_layout({ ptr, index }))
        end,
        [Ty.TypeClassView] = function(self, ty, env, target)
            local ptr = raw_layout(ptr_layout(target))
            local index = raw_layout(index_layout(target))
            return pvm.once(product_layout({ ptr, index, index }))
        end,
        [Ty.TypeClassClosure] = function(self, ty, env, target)
            local ptr = raw_layout(ptr_layout(target))
            return pvm.once(product_layout({ ptr, ptr }))
        end,
        [Ty.TypeClassAggregate] = function(self, ty, env)
            local layout = pvm.one(named_layout_lookup(env, self.module_name, self.type_name))
            if layout == nil then
                return pvm.once(Ty.TypeMemLayoutUnknown(ty, self))
            end
            return pvm.once(Ty.TypeMemLayoutKnown(layout))
        end,
        [Ty.TypeClassArray] = function(self, ty, env, target)
            local elem_result = pvm.one(type_layout_result(self.elem, env, target))
            local elem_layout = result_layout(elem_result)
            if elem_layout == nil then
                return pvm.once(Ty.TypeMemLayoutUnknown(ty, self))
            end
            return pvm.once(known(elem_layout.size * self.count, elem_layout.align))
        end,
        [Ty.TypeClassUnknown] = function(self, ty)
            return pvm.once(Ty.TypeMemLayoutUnknown(ty, self))
        end,
    })

    type_layout_result = pvm.phase("moonlift_type_mem_layout_result", function(ty, env, target)
        env = env or Sem.LayoutEnv({})
        if pvm.classof(ty) == Ty.TNamed then
            local layout = layout_for_named_ref(ty.ref, env)
            if layout ~= nil then return Ty.TypeMemLayoutKnown(Sem.MemLayout(layout.size, layout.align)) end
        end
        local class = classify_api.classify(ty)
        return pvm.one(class_layout(class, ty, env, target))
    end)

    local api = {
        scalar_layout = scalar_layout,
        named_layout_lookup = named_layout_lookup,
        class_layout = class_layout,
        type_layout_result = type_layout_result,
        result = function(ty, env, target)
            return pvm.one(type_layout_result(ty, env or Sem.LayoutEnv({}), target))
        end,
    }
    T._moonlift_api_cache.type_size_align = api
    return api
end

return M
