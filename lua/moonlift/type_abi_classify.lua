local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Ty = (T.MoonType or T.Moon2Type)
    local Back = (T.MoonBack or T.Moon2Back)
    local Sem = (T.MoonSem or T.Moon2Sem)

    local scalar_api = require("moonlift.type_to_back_scalar").Define(T)
    local layout_api = require("moonlift.type_size_align").Define(T)
    local classify_api = require("moonlift.type_classify").Define(T)

    local abi_class_from_type_class
    local abi_decision

    local function known_layout(ty, env)
        local r = layout_api.result(ty, env or Sem.LayoutEnv({}))
        if pvm.classof(r) == Ty.TypeMemLayoutKnown then return r.layout end
        return nil
    end

    abi_class_from_type_class = pvm.phase("moon2_type_abi_class_from_type_class", {
        [Ty.TypeClassScalar] = function(self, ty)
            local r = scalar_api.result(ty)
            if pvm.classof(r) == Ty.TypeBackScalarKnown then
                if r.scalar == Back.BackVoid then return pvm.once(Ty.AbiIgnore) end
                return pvm.once(Ty.AbiDirect(r.scalar))
            end
            if self.scalar == (T.MoonCore or T.Moon2Core).ScalarVoid then return pvm.once(Ty.AbiIgnore) end
            return pvm.once(Ty.AbiUnknown(self))
        end,
        [Ty.TypeClassPointer] = function() return pvm.once(Ty.AbiDirect(Back.BackPtr)) end,
        [Ty.TypeClassCallable] = function() return pvm.once(Ty.AbiDirect(Back.BackPtr)) end,
        [Ty.TypeClassSlice] = function(_, ty, env)
            return pvm.once(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(16, 8)))
        end,
        [Ty.TypeClassView] = function(_, ty, env)
            return pvm.once(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(24, 8)))
        end,
        [Ty.TypeClassClosure] = function(_, ty, env)
            return pvm.once(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(16, 8)))
        end,
        [Ty.TypeClassArray] = function(_, ty, env)
            local layout = known_layout(ty, env)
            if layout == nil then return pvm.once(Ty.AbiUnknown(classify_api.classify(ty))) end
            return pvm.once(Ty.AbiIndirect(layout))
        end,
        [Ty.TypeClassAggregate] = function(_, ty, env)
            local layout = known_layout(ty, env)
            if layout == nil then return pvm.once(Ty.AbiUnknown(classify_api.classify(ty))) end
            return pvm.once(Ty.AbiIndirect(layout))
        end,
        [Ty.TypeClassUnknown] = function(self)
            return pvm.once(Ty.AbiUnknown(self))
        end,
    }, { args_cache = "last" })

    abi_decision = pvm.phase("moon2_type_abi_decision", function(ty, env)
        local class = classify_api.classify(ty)
        local abi = pvm.one(abi_class_from_type_class(class, ty, env or Sem.LayoutEnv({})))
        return Ty.AbiDecision(ty, abi)
    end, { args_cache = "last" })

    return {
        abi_class_from_type_class = abi_class_from_type_class,
        abi_decision = abi_decision,
        decide = function(ty, env) return pvm.one(abi_decision(ty, env or Sem.LayoutEnv({}))) end,
    }
end

return M
