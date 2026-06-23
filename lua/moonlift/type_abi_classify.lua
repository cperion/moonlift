local schema = require("moonlift.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function bind_context(T)
    local Ty = T.MoonType
    local Back = T.MoonBack
    local Sem = T.MoonSem

    local scalar_api = require("moonlift.type_to_back_scalar")(T)
    local layout_api = require("moonlift.type_size_align")(T)
    local classify_api = require("moonlift.type_classify")(T)

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
                if r.scalar == Back.BackVoid then return single(Ty.AbiIgnore) end
                return single(Ty.AbiDirect(r.scalar))
            end
            if self.scalar == T.MoonCore.ScalarVoid then return single(Ty.AbiIgnore) end
            return single(Ty.AbiUnknown(self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassPointer) then
            return (function()
 return single(Ty.AbiDirect(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassCallable) then
            return (function()
 return single(Ty.AbiDirect(Back.BackPtr))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassSlice) then
            return (function(_, ty, env)

            return single(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(16, 8)))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassView) then
            return (function(_, ty, env)

            return single(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(24, 8)))
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
            if schema.classof(r) == Ty.TypeBackScalarKnown then return single(Ty.AbiDirect(r.scalar)) end
            return single(Ty.AbiUnknown(self))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassClosure) then
            return (function(_, ty, env)

            return single(Ty.AbiDescriptor(known_layout(ty, env) or Sem.MemLayout(16, 8)))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassArray) then
            return (function(_, ty, env)

            local layout = known_layout(ty, env)
            if layout == nil then return single(Ty.AbiUnknown(classify_api.classify(ty))) end
            return single(Ty.AbiIndirect(layout))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassAggregate) then
            return (function(_, ty, env)

            local layout = known_layout(ty, env)
            if layout == nil then return single(Ty.AbiUnknown(classify_api.classify(ty))) end
            return single(Ty.AbiIndirect(layout))
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeClassUnknown) then
            return (function(self)

            return single(Ty.AbiUnknown(self))
            end)(node, ...)
        else
            error("phase moonlift_type_abi_class_from_type_class: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function abi_decision(ty, env)
        local class = classify_api.classify(ty)
        local abi = only(abi_class_from_type_class(class, ty, env or Sem.LayoutEnv({})))
        return Ty.AbiDecision(ty, abi)
    end

    return {
        abi_class_from_type_class = abi_class_from_type_class,
        abi_decision = abi_decision,
        decide = function(ty, env) return abi_decision(ty, env or Sem.LayoutEnv({})) end,
    }
end

return bind_context