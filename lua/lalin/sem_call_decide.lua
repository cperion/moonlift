local schema = require("lalin.schema_runtime")
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
    local C = T.LalinCore
    local Ty = T.LalinType
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Tr = T.LalinTree

    local classify_api = require("lalin.type_classify")(T)

    local binding_role_call_target
    local value_ref_call_target
    local callee_call_target

    local function closure_or_indirect(callee, fn_ty)
        local shape = classify_api.classify(fn_ty)
        if schema.classof(shape) == Ty.TypeShapeClosure then
            return { kind = "closure", closure = callee, fn_ty = fn_ty }
        end
        return { kind = "indirect", callee = callee, fn_ty = fn_ty }
    end

    function binding_role_call_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.BindingRoleGlobalFunc) then
            return (function(self, callee, fn_ty)

            return single({ kind = "direct", module_name = self.module_name, item_name = self.item_name, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, B.BindingRoleExtern) then
            return (function(self, callee, fn_ty)

            return single({ kind = "extern", symbol = self.symbol, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, B.BindingRoleLocalValue) then
            return (function(_, callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingRoleLocalCell) then
            return (function(_, callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingRoleArg) then
            return (function(_, callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingRoleEntryBlockParam) then
            return (function(_, callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingRoleBlockParam) then
            return (function(_, callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingRoleGlobalConst) then
            return (function(_, callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingRoleGlobalStatic) then
            return (function(_, callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        else
            error("phase lalin_sem_binding_role_call_target: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function value_ref_call_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(ref, callee, fn_ty)

            return binding_role_call_target(ref.binding.role, callee, fn_ty)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function(_, callee)
 return single({ kind = "unresolved", callee = callee })
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function(_, callee)
 return single({ kind = "unresolved", callee = callee })
            end)(node, ...)
        else
            error("phase lalin_sem_value_ref_call_target: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    function callee_call_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprRef) then
            return (function(callee, fn_ty)

            return value_ref_call_target(callee.ref, callee, fn_ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLit) then
            return (function(callee)
 return single({ kind = "unresolved", callee = callee })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function(callee, fn_ty)
 return single({ kind = "closure", closure = callee, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function(callee, fn_ty)
 return single(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        else
            error("phase lalin_sem_call_decide: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    return {
        binding_role_call_target = binding_role_call_target,
        value_ref_call_target = value_ref_call_target,
        callee_call_target = callee_call_target,
        decide = function(callee, fn_ty) return only(callee_call_target(callee, fn_ty)) end,
    }
end

return bind_context
