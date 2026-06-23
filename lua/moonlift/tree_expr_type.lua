local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.tree_expr_type ~= nil then return T._moonlift_api_cache.tree_expr_type end

    local C = T.MoonCore
    local Ty = T.MoonType
    local B = T.MoonBind
    local O = T.MoonOpen
    local Sem = T.MoonSem
    local Tr = T.MoonTree

    local header_type
    local value_ref_type
    local call_target_type
    local expr_type

    local function first(g, p, c)
        local xs = pvm.drain(g, p, c)
        return xs[1]
    end

    local function bool_ty()
        return Ty.TScalar(C.ScalarBool)
    end

    local function scalar_void()
        return Ty.TScalar(C.ScalarVoid)
    end

    function header_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprSurface) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprTyped) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprOpen) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        else
            error("erased phase moonlift_tree_expr_header_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function value_ref_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(self)
 return erased.once(self.binding.ty)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefHole) then
            return (function(self)

            local slot_cls = schema.classof(self.slot)
            if slot_cls == O.SlotFunc then return erased.once(self.slot.slot.fn_ty) end
            if slot_cls == O.SlotValue or slot_cls == O.SlotConst or slot_cls == O.SlotStatic then return erased.once(self.slot.slot.ty) end
            if slot_cls == O.SlotExpr or slot_cls == O.SlotPlace then return erased.once(self.slot.slot.ty or nil) end
            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_tree_value_ref_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    call_target_type = function(target)
        return target.fn_ty
    end

    local function header_or(h, fallback)
        local ty = first(header_type(h))
        if ty ~= nil then return pvm.once(ty) end
        if fallback ~= nil then return pvm.once(fallback) end
        return pvm.empty()
    end

    local function index_base_elem(base)
        local cls = schema.classof(base)
        if cls == Tr.IndexBaseView then return base.view.elem end
        if cls == Tr.IndexBasePlace then return base.elem end
        return nil
    end

    local function result_of_callable(fn_ty)
        local cls = schema.classof(fn_ty)
        if cls == Ty.TFunc or cls == Ty.TClosure then return fn_ty.result end
        return nil
    end

    function expr_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprLit) then
            return (function(self)
 return header_or(self.h, scalar_void())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprRef) then
            return (function(self)

            local ty = first(header_type(self.h)) or first(value_ref_type(self.ref))
            if ty ~= nil then return erased.once(ty) end
            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function(self)
 return header_or(self.h, first(expr_type(self.base)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(self)
 return header_or(self.h, first(expr_type(self.value)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(self)
 return header_or(self.h, first(expr_type(self.lhs)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(self)
 return header_or(self.h, bool_ty())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(self)
 return header_or(self.h, bool_ty())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function(self)
 return header_or(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function(self)
 return header_or(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function(self)
 return header_or(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function(self)

            local ty = first(header_type(self.h))
            if ty ~= nil then return erased.once(ty) end
            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLen) then
            return (function(self)
 return header_or(self.h, Ty.TScalar(C.ScalarIndex))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(self)
 return header_or(self.h, self.field.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(self)
 return header_or(self.h, index_base_elem(self.base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(self)
 return header_or(self.h, Ty.TArray(Ty.ArrayLenConst(#self.elems), self.elem_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(self)
 return header_or(self.h, first(expr_type(self.then_expr)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(self)
 return header_or(self.h, first(expr_type(self.then_expr)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(self)
 return header_or(self.h, first(expr_type(self.default_expr)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function(self)
 return header_or(self.h, self.region.result_ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(self)
 return header_or(self.h, first(expr_type(self.result)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function(self)
 return header_or(self.h, Ty.TClosure(self.params, self.result))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function(self)
 return header_or(self.h)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicLoad) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicRmw) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicCas) then
            return (function(self)
 return erased.once(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSlotValue) then
            return (function(self)
 return header_or(self.h, self.slot.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUseExprFrag) then
            return (function(self)
 return header_or(self.h)
            end)(node, ...)
        else
            error("erased phase moonlift_tree_expr_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local api = {
        header_type = header_type,
        value_ref_type = value_ref_type,
        call_target_type = call_target_type,
        expr_type = expr_type,
        type = function(expr) return first(expr_type(expr)) end,
    }
    T._moonlift_api_cache.tree_expr_type = api
    return api
end

return M
