local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.tree_expr_type ~= nil then return T._moonlift_api_cache.tree_expr_type end

    local C = T.Moon2Core
    local Ty = T.Moon2Type
    local B = T.Moon2Bind
    local Sem = T.Moon2Sem
    local Tr = T.Moon2Tree

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

    header_type = pvm.phase("moon2_tree_expr_header_type", {
        [Tr.ExprSurface] = function() return pvm.empty() end,
        [Tr.ExprTyped] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprOpen] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprSem] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprCode] = function(self) return pvm.once(self.ty) end,
    })

    value_ref_type = pvm.phase("moon2_tree_value_ref_type", {
        [B.ValueRefBinding] = function(self) return pvm.once(self.binding.ty) end,
        [B.ValueRefSlot] = function(self) return pvm.once(self.slot.ty) end,
        [B.ValueRefFuncSlot] = function(self) return pvm.once(self.slot.fn_ty) end,
        [B.ValueRefConstSlot] = function(self) return pvm.once(self.slot.ty) end,
        [B.ValueRefStaticSlot] = function(self) return pvm.once(self.slot.ty) end,
        [B.ValueRefName] = function() return pvm.empty() end,
        [B.ValueRefPath] = function() return pvm.empty() end,
    })

    call_target_type = pvm.phase("moon2_tree_call_target_type", {
        [Sem.CallDirect] = function(self) return pvm.once(self.fn_ty) end,
        [Sem.CallExtern] = function(self) return pvm.once(self.fn_ty) end,
        [Sem.CallIndirect] = function(self) return pvm.once(self.fn_ty) end,
        [Sem.CallClosure] = function(self) return pvm.once(self.fn_ty) end,
        [Sem.CallUnresolved] = function() return pvm.empty() end,
    })

    local function header_or(h, fallback)
        local ty = first(header_type(h))
        if ty ~= nil then return pvm.once(ty) end
        if fallback ~= nil then return pvm.once(fallback) end
        return pvm.empty()
    end

    local function index_base_elem(base)
        local cls = pvm.classof(base)
        if cls == Tr.IndexBaseView then return base.view.elem end
        if cls == Tr.IndexBasePlace then return base.elem end
        return nil
    end

    local function result_of_callable(fn_ty)
        local cls = pvm.classof(fn_ty)
        if cls == Ty.TFunc or cls == Ty.TClosure then return fn_ty.result end
        return nil
    end

    expr_type = pvm.phase("moon2_tree_expr_type", {
        [Tr.ExprLit] = function(self) return header_or(self.h, scalar_void()) end,
        [Tr.ExprRef] = function(self)
            local ty = first(header_type(self.h)) or first(value_ref_type(self.ref))
            if ty ~= nil then return pvm.once(ty) end
            return pvm.empty()
        end,
        [Tr.ExprDot] = function(self) return header_or(self.h, first(expr_type(self.base))) end,
        [Tr.ExprUnary] = function(self) return header_or(self.h, first(expr_type(self.value))) end,
        [Tr.ExprBinary] = function(self) return header_or(self.h, first(expr_type(self.lhs))) end,
        [Tr.ExprCompare] = function(self) return header_or(self.h, bool_ty()) end,
        [Tr.ExprLogic] = function(self) return header_or(self.h, bool_ty()) end,
        [Tr.ExprCast] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprMachineCast] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprIntrinsic] = function(self) return header_or(self.h) end,
        [Tr.ExprAddrOf] = function(self) return header_or(self.h) end,
        [Tr.ExprDeref] = function(self) return header_or(self.h) end,
        [Tr.ExprCall] = function(self)
            local ty = first(header_type(self.h))
            if ty ~= nil then return pvm.once(ty) end
            local fn_ty = first(call_target_type(self.target))
            local result = fn_ty and result_of_callable(fn_ty)
            if result ~= nil then return pvm.once(result) end
            return pvm.empty()
        end,
        [Tr.ExprLen] = function(self) return header_or(self.h, Ty.TScalar(C.ScalarIndex)) end,
        [Tr.ExprField] = function(self) return header_or(self.h, self.field.ty) end,
        [Tr.ExprIndex] = function(self) return header_or(self.h, index_base_elem(self.base)) end,
        [Tr.ExprAgg] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprArray] = function(self) return header_or(self.h, Ty.TArray(Ty.ArrayLenConst(#self.elems), self.elem_ty)) end,
        [Tr.ExprIf] = function(self) return header_or(self.h, first(expr_type(self.then_expr))) end,
        [Tr.ExprSelect] = function(self) return header_or(self.h, first(expr_type(self.then_expr))) end,
        [Tr.ExprSwitch] = function(self) return header_or(self.h, first(expr_type(self.default_expr))) end,
        [Tr.ExprControl] = function(self) return header_or(self.h, self.region.result_ty) end,
        [Tr.ExprBlock] = function(self) return header_or(self.h, first(expr_type(self.result))) end,
        [Tr.ExprClosure] = function(self) return header_or(self.h, Ty.TClosure(self.params, self.result)) end,
        [Tr.ExprView] = function(self) return header_or(self.h) end,
        [Tr.ExprLoad] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprSlotValue] = function(self) return header_or(self.h, self.slot.ty) end,
        [Tr.ExprUseExprFrag] = function(self) return header_or(self.h, self.frag.result) end,
    })

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
