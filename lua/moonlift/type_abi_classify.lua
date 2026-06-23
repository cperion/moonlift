local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local Ty = T.MoonType
    local Back = T.MoonBack
    local Sem = T.MoonSem

    local scalar_api = require("moonlift.type_to_back_scalar").Define(T)
    local layout_api = require("moonlift.type_size_align").Define(T)
    local classify_api = require("moonlift.type_classify").Define(T)

    local abi_class_from_type_class
    local abi_decision

    local function known_layout(ty, env)
        local r = layout_api.result(ty, env or Sem.LayoutEnv({}))
        if schema.classof(r) == Ty.TypeMemLayoutKnown then return r.layout end
        return nil
    end

    function abi_class_from_type_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TypeClassScalar) then
            return (function(self, ty)

            local r = scalar_api.result(ty)
            if schema.classof(r) == Ty.TypeBackScalarKnown then
                if r.scalar == Back.BackVoid then return erased.once(Ty.AbiIgnore) end
                return erased.once(Ty.AbiDirect(r.scalar))
            end
            if self.scalar == T.MoonCore.ScalarVoid then return erased.once(Ty.AbiIgnore) end
            return erased.once(Ty.AbiUnknown(self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassPointer) then
            return (function()
 return erased.once(Ty.AbiDirect(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassCallable) then
            return (function()
 return erased.once(Ty.AbiDirect(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassSlice) then
            return (function(_, ty, env)

            return erased.once(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(16, 8)))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassView) then
            return (function(_, ty, env)

            return erased.once(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(24, 8)))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassLease) then
            return (function(self, ty, env)

            local base_class = classify_api.classify(self.base)
            return abi_class_from_type_class(base_class, self.base, env)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassOwned) then
            return (function(self, ty, env)

            local base_class = classify_api.classify(self.base)
            return abi_class_from_type_class(base_class, self.base, env)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassHandle) then
            return (function(self, ty)

            local r = scalar_api.result(ty)
            if schema.classof(r) == Ty.TypeBackScalarKnown then return erased.once(Ty.AbiDirect(r.scalar)) end
            return erased.once(Ty.AbiUnknown(self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassClosure) then
            return (function(_, ty, env)

            return erased.once(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(16, 8)))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassArray) then
            return (function(_, ty, env)

            local layout = known_layout(ty, env)
            if layout == nil then return erased.once(Ty.AbiUnknown(classify_api.classify(ty))) end
            return erased.once(Ty.AbiIndirect(layout))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassAggregate) then
            return (function(_, ty, env)

            local layout = known_layout(ty, env)
            if layout == nil then return erased.once(Ty.AbiUnknown(classify_api.classify(ty))) end
            return erased.once(Ty.AbiIndirect(layout))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassUnknown) then
            return (function(self)

            return erased.once(Ty.AbiUnknown(self))
            end)(node, ...)
        else
            error("erased phase moonlift_type_abi_class_from_type_class: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function abi_decision(ty, env)
        local class = classify_api.classify(ty)
        local abi = erased.one(abi_class_from_type_class(class, ty, env or Sem.LayoutEnv({})))
        return Ty.AbiDecision(ty, abi)
    end

    return {
        abi_class_from_type_class = abi_class_from_type_class,
        abi_decision = abi_decision,
        decide = function(ty, env) return abi_decision(ty, env or Sem.LayoutEnv({})) end,
    }
end

return M
