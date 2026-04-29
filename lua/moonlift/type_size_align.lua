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

    local function known(size, align)
        return Ty.TypeMemLayoutKnown(Sem.MemLayout(size, align))
    end

    scalar_layout = pvm.phase("moon2_type_scalar_mem_layout", {
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
        [Core.ScalarRawPtr] = function() return pvm.once(known(8, 8)) end,
        [Core.ScalarIndex] = function() return pvm.once(known(8, 8)) end,
    })

    named_layout_lookup = pvm.phase("moon2_type_named_layout_lookup", function(env, module_name, type_name)
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            if layout.module_name == module_name and layout.type_name == type_name then
                return Sem.MemLayout(layout.size, layout.align)
            end
        end
        return nil
    end)

    local function result_layout(result)
        if result ~= nil and pvm.classof(result) == Ty.TypeMemLayoutKnown then
            return result.layout
        end
        return nil
    end

    class_layout = pvm.phase("moon2_type_class_mem_layout", {
        [Ty.TypeClassScalar] = function(self)
            return scalar_layout(self.scalar)
        end,
        [Ty.TypeClassPointer] = function()
            return pvm.once(known(8, 8))
        end,
        [Ty.TypeClassCallable] = function()
            return pvm.once(known(8, 8))
        end,
        [Ty.TypeClassSlice] = function()
            return pvm.once(known(16, 8))
        end,
        [Ty.TypeClassView] = function()
            return pvm.once(known(24, 8))
        end,
        [Ty.TypeClassClosure] = function()
            return pvm.once(known(16, 8))
        end,
        [Ty.TypeClassAggregate] = function(self, ty, env)
            local layout = pvm.one(named_layout_lookup(env, self.module_name, self.type_name))
            if layout == nil then
                return pvm.once(Ty.TypeMemLayoutUnknown(ty, self))
            end
            return pvm.once(Ty.TypeMemLayoutKnown(layout))
        end,
        [Ty.TypeClassArray] = function(self, ty, env)
            local elem_result = pvm.one(type_layout_result(self.elem, env))
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

    type_layout_result = pvm.phase("moon2_type_mem_layout_result", function(ty, env)
        local class = classify_api.classify(ty)
        return pvm.one(class_layout(class, ty, env or Sem.LayoutEnv({})))
    end)

    local api = {
        scalar_layout = scalar_layout,
        named_layout_lookup = named_layout_lookup,
        class_layout = class_layout,
        type_layout_result = type_layout_result,
        result = function(ty, env)
            return pvm.one(type_layout_result(ty, env or Sem.LayoutEnv({})))
        end,
    }
    T._moonlift_api_cache.type_size_align = api
    return api
end

return M
