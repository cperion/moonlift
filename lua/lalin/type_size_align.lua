local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.type_size_align ~= nil then return T._lalin_api_cache.type_size_align end

    local Core = T.LalinCore
    local Ty = T.LalinType
    local Sem = T.LalinSem

    local classify_api = require("lalin.type_classify")(T)

    local type_layout_result

    local function known(size, align)
        return Ty.TypeMemLayoutKnown(Sem.MemLayout(size, align))
    end

    local function unknown(ty, shape)
        return Ty.TypeMemLayoutUnknown(ty, shape)
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

    function Ty.TypeMemLayoutResult:type_size_align_layout()
        return nil
    end

    function Ty.TypeMemLayoutKnown:type_size_align_layout()
        return self.layout
    end

    local function raw_layout(result)
        local layout = result:type_size_align_layout()
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

    function Core.Scalar:type_size_align_scalar_layout(target)
        error("type_size_align: scalar has no layout method", 2)
    end

    function Core.ScalarVoid:type_size_align_scalar_layout()
        return known(0, 1)
    end

    function Core.ScalarBool:type_size_align_scalar_layout()
        return known(1, 1)
    end

    function Core.ScalarI8:type_size_align_scalar_layout()
        return known(1, 1)
    end

    function Core.ScalarU8:type_size_align_scalar_layout()
        return known(1, 1)
    end

    function Core.ScalarI16:type_size_align_scalar_layout()
        return known(2, 2)
    end

    function Core.ScalarU16:type_size_align_scalar_layout()
        return known(2, 2)
    end

    function Core.ScalarI32:type_size_align_scalar_layout()
        return known(4, 4)
    end

    function Core.ScalarU32:type_size_align_scalar_layout()
        return known(4, 4)
    end

    function Core.ScalarF32:type_size_align_scalar_layout()
        return known(4, 4)
    end

    function Core.ScalarI64:type_size_align_scalar_layout()
        return known(8, 8)
    end

    function Core.ScalarU64:type_size_align_scalar_layout()
        return known(8, 8)
    end

    function Core.ScalarF64:type_size_align_scalar_layout()
        return known(8, 8)
    end

    function Core.ScalarRawPtr:type_size_align_scalar_layout(target)
        return ptr_layout(target)
    end

    function Core.ScalarIndex:type_size_align_scalar_layout(target)
        return index_layout(target)
    end

    local function named_layout_lookup(env, module_name, type_name)
        for i = 1, #(env and env.layouts or {}) do
            local layout = env.layouts[i]
            if layout.module_name == module_name and layout.type_name == type_name then
                return Sem.MemLayout(layout.size, layout.align)
            end
        end
        return nil
    end

    function Ty.TypeRef:type_size_align_matches_named_layout(layout)
        return false
    end

    function Ty.TypeRefGlobal:type_size_align_matches_named_layout(layout)
        return layout.module_name == self.module_name and layout.type_name == self.type_name
    end

    function Ty.TypeRefPath:type_size_align_matches_named_layout(layout)
        return #self.path.parts == 1 and layout.type_name == self.path.parts[1].text
    end

    function Ty.TypeRef:type_size_align_matches_local_layout(layout)
        return false
    end

    function Ty.TypeRefLocal:type_size_align_matches_local_layout(layout)
        return layout.sym == self.sym
    end

    function Sem.TypeLayout:type_size_align_for_ref(ref)
        return nil
    end

    function Sem.LayoutNamed:type_size_align_for_ref(ref)
        if ref:type_size_align_matches_named_layout(self) then return self end
        return nil
    end

    function Sem.LayoutLocal:type_size_align_for_ref(ref)
        if ref:type_size_align_matches_local_layout(self) then return self end
        return nil
    end

    local function layout_for_named_ref(ref, env)
        for i = 1, #(env and env.layouts or {}) do
            local layout = env.layouts[i]:type_size_align_for_ref(ref)
            if layout ~= nil then return layout end
        end
        return nil
    end

    function Ty.Type:type_size_align_named_layout(env)
        return nil
    end

    function Ty.TNamed:type_size_align_named_layout(env)
        return layout_for_named_ref(self.ref, env)
    end

    function Ty.TypeShape:type_size_align_shape_layout(ty, env, target)
        return unknown(ty, self)
    end

    function Ty.TypeShapeScalar:type_size_align_shape_layout(ty, env, target)
        return self.scalar:type_size_align_scalar_layout(target)
    end

    function Ty.TypeShapePointer:type_size_align_shape_layout(ty, env, target)
        return ptr_layout(target)
    end

    function Ty.TypeShapeCallable:type_size_align_shape_layout(ty, env, target)
        return ptr_layout(target)
    end

    function Ty.TypeShapeSlice:type_size_align_shape_layout(ty, env, target)
        local ptr = raw_layout(ptr_layout(target))
        local index = raw_layout(index_layout(target))
        return product_layout({ ptr, index })
    end

    function Ty.TypeShapeView:type_size_align_shape_layout(ty, env, target)
        local ptr = raw_layout(ptr_layout(target))
        local index = raw_layout(index_layout(target))
        return product_layout({ ptr, index, index })
    end

    function Ty.TypeShapeLease:type_size_align_shape_layout(ty, env, target)
        return type_layout_result(self.base, env, target)
    end

    function Ty.TypeShapeOwned:type_size_align_shape_layout(ty, env, target)
        return type_layout_result(self.base, env, target)
    end

    function Ty.HandleRepr:type_size_align_handle_layout(ty, shape, target)
        return unknown(ty, shape)
    end

    function Ty.HandleReprScalar:type_size_align_handle_layout(ty, shape, target)
        return self.scalar:type_size_align_scalar_layout(target)
    end

    function Ty.TypeShapeHandle:type_size_align_shape_layout(ty, env, target)
        return self.repr:type_size_align_handle_layout(ty, self, target)
    end

    function Ty.TypeShapeClosure:type_size_align_shape_layout(ty, env, target)
        local ptr = raw_layout(ptr_layout(target))
        return product_layout({ ptr, ptr })
    end

    function Ty.TypeShapeAggregate:type_size_align_shape_layout(ty, env)
        local layout = named_layout_lookup(env, self.module_name, self.type_name)
        if layout == nil then return unknown(ty, self) end
        return Ty.TypeMemLayoutKnown(layout)
    end

    function Ty.TypeShapeArray:type_size_align_shape_layout(ty, env, target)
        local elem_result = type_layout_result(self.elem, env, target)
        local elem_layout = elem_result:type_size_align_layout()
        if elem_layout == nil then return unknown(ty, self) end
        return known(elem_layout.size * self.count, elem_layout.align)
    end

    type_layout_result = function(ty, env, target)
        env = env or Sem.LayoutEnv({})
        local layout = ty:type_size_align_named_layout(env)
        if layout ~= nil then return Ty.TypeMemLayoutKnown(Sem.MemLayout(layout.size, layout.align)) end
        local shape = classify_api.classify(ty)
        return shape:type_size_align_shape_layout(ty, env, target)
    end

    local api = {
        scalar_layout = function(scalar, target)
            return scalar:type_size_align_scalar_layout(target)
        end,
        named_layout_lookup = named_layout_lookup,
        shape_layout = function(shape, ty, env, target)
            return shape:type_size_align_shape_layout(ty, env or Sem.LayoutEnv({}), target)
        end,
        type_layout_result = type_layout_result,
        result = function(ty, env, target)
            return type_layout_result(ty, env or Sem.LayoutEnv({}), target)
        end,
    }
    T._lalin_api_cache.type_size_align = api
    return api
end

return bind_context
