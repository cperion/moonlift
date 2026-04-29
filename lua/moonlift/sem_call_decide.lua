local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Ty = T.MoonType
    local O = T.MoonOpen
    local B = T.MoonBind
    local Sem = T.MoonSem
    local Tr = T.MoonTree

    local classify_api = require("moonlift.type_classify").Define(T)

    local import_call_target
    local binding_class_call_target
    local value_ref_call_target
    local callee_call_target

    local function closure_or_indirect(callee, fn_ty)
        local class = classify_api.classify(fn_ty)
        if pvm.classof(class) == Ty.TypeClassClosure then
            return Sem.CallClosure(callee, fn_ty)
        end
        return Sem.CallIndirect(callee, fn_ty)
    end

    import_call_target = pvm.phase("moon2_sem_import_call_target", {
        [O.ImportGlobalFunc] = function(import, callee, fn_ty)
            return pvm.once(Sem.CallDirect(import.module_name, import.item_name, fn_ty))
        end,
        [O.ImportExtern] = function(import, callee, fn_ty)
            return pvm.once(Sem.CallExtern(import.symbol, fn_ty))
        end,
        [O.ImportValue] = function(_, callee, fn_ty)
            return pvm.once(closure_or_indirect(callee, fn_ty))
        end,
        [O.ImportGlobalConst] = function(_, callee, fn_ty)
            return pvm.once(closure_or_indirect(callee, fn_ty))
        end,
        [O.ImportGlobalStatic] = function(_, callee, fn_ty)
            return pvm.once(closure_or_indirect(callee, fn_ty))
        end,
    }, { args_cache = "last" })

    binding_class_call_target = pvm.phase("moon2_sem_binding_class_call_target", {
        [B.BindingClassGlobalFunc] = function(self, callee, fn_ty)
            return pvm.once(Sem.CallDirect(self.module_name, self.item_name, fn_ty))
        end,
        [B.BindingClassExtern] = function(self, callee, fn_ty)
            return pvm.once(Sem.CallExtern(self.symbol, fn_ty))
        end,
        [B.BindingClassFuncSym] = function(self, callee, fn_ty)
            return pvm.once(Sem.CallDirect("", self.sym.name, fn_ty))
        end,
        [B.BindingClassExternSym] = function(self, callee, fn_ty)
            return pvm.once(Sem.CallExtern(self.sym.symbol, fn_ty))
        end,
        [B.BindingClassImport] = function(self, callee, fn_ty)
            return import_call_target(self.import, callee, fn_ty)
        end,
        [B.BindingClassLocalValue] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassLocalCell] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassArg] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassEntryBlockParam] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassBlockParam] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassGlobalConst] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassGlobalStatic] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassOpenParam] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassConstSym] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassStaticSym] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassFuncSlot] = function(_, callee, fn_ty) return pvm.once(Sem.CallUnresolved(callee)) end,
        [B.BindingClassConstSlot] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassStaticSlot] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.BindingClassValueSlot] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
    }, { args_cache = "last" })

    value_ref_call_target = pvm.phase("moon2_sem_value_ref_call_target", {
        [B.ValueRefBinding] = function(ref, callee, fn_ty)
            return binding_class_call_target(ref.binding.class, callee, fn_ty)
        end,
        [B.ValueRefFuncSlot] = function(_, callee) return pvm.once(Sem.CallUnresolved(callee)) end,
        [B.ValueRefName] = function(_, callee) return pvm.once(Sem.CallUnresolved(callee)) end,
        [B.ValueRefPath] = function(_, callee) return pvm.once(Sem.CallUnresolved(callee)) end,
        [B.ValueRefSlot] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.ValueRefConstSlot] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [B.ValueRefStaticSlot] = function(_, callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
    }, { args_cache = "last" })

    callee_call_target = pvm.phase("moon2_sem_call_decide", {
        [Tr.ExprRef] = function(callee, fn_ty)
            return value_ref_call_target(callee.ref, callee, fn_ty)
        end,
        [Tr.ExprLit] = function(callee) return pvm.once(Sem.CallUnresolved(callee)) end,
        [Tr.ExprDot] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprUnary] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprBinary] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprCompare] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprLogic] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprCast] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprMachineCast] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprIntrinsic] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprAddrOf] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprDeref] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprCall] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprField] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprIndex] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprAgg] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprArray] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprIf] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprSelect] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprSwitch] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprControl] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprBlock] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprClosure] = function(callee, fn_ty) return pvm.once(Sem.CallClosure(callee, fn_ty)) end,
        [Tr.ExprView] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprLoad] = function(callee, fn_ty) return pvm.once(closure_or_indirect(callee, fn_ty)) end,
        [Tr.ExprSlotValue] = function(callee) return pvm.once(Sem.CallUnresolved(callee)) end,
        [Tr.ExprUseExprFrag] = function(callee) return pvm.once(Sem.CallUnresolved(callee)) end,
    }, { args_cache = "last" })

    return {
        import_call_target = import_call_target,
        binding_class_call_target = binding_class_call_target,
        value_ref_call_target = value_ref_call_target,
        callee_call_target = callee_call_target,
        decide = function(callee, fn_ty) return pvm.one(callee_call_target(callee, fn_ty)) end,
    }
end

return M
