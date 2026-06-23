local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local C = T.MoonCore
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
        if schema.classof(class) == Ty.TypeClassClosure then
            return { kind = "closure", closure = callee, fn_ty = fn_ty }
        end
        return { kind = "indirect", callee = callee, fn_ty = fn_ty }
    end

    function import_call_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.ImportGlobalFunc) then
            return (function(import, callee, fn_ty)

            return erased.once({ kind = "direct", module_name = import.module_name, item_name = import.item_name, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, O.ImportExtern) then
            return (function(import, callee, fn_ty)

            return erased.once({ kind = "extern", symbol = import.symbol, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, O.ImportValue) then
            return (function(_, callee, fn_ty)

            return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, O.ImportGlobalConst) then
            return (function(_, callee, fn_ty)

            return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, O.ImportGlobalStatic) then
            return (function(_, callee, fn_ty)

            return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        else
            error("erased phase moonlift_sem_import_call_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function binding_class_call_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.BindingClassGlobalFunc) then
            return (function(self, callee, fn_ty)

            return erased.once({ kind = "direct", module_name = self.module_name, item_name = self.item_name, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassExtern) then
            return (function(self, callee, fn_ty)

            return erased.once({ kind = "extern", symbol = self.symbol, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassOpenSym) then
            return (function(self, callee, fn_ty)

            if schema.classof(self.sym.kind) == C.SymKindFunc then
                return erased.once({ kind = "direct", module_name = "", item_name = self.sym.name, fn_ty = fn_ty })
            end
            return erased.once({ kind = "extern", symbol = self.sym.symbol, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassImport) then
            return (function(self, callee, fn_ty)

            return import_call_target(self.import, callee, fn_ty)
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassLocalValue) then
            return (function(_, callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassLocalCell) then
            return (function(_, callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassArg) then
            return (function(_, callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassEntryBlockParam) then
            return (function(_, callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassBlockParam) then
            return (function(_, callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassGlobalConst) then
            return (function(_, callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassGlobalStatic) then
            return (function(_, callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassOpenParam) then
            return (function(_, callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassOpenSym) then
            return (function(self, callee, fn_ty)

            local kind_cls = schema.classof(self.sym.kind)
            if kind_cls == C.SymKindFunc then
                return erased.once({ kind = "direct", module_name = "", func_name = self.sym.name, fn_ty = fn_ty })
            elseif kind_cls == C.SymKindExtern then
                return erased.once({ kind = "extern", symbol = self.sym.symbol, fn_ty = fn_ty })
            end
            return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, B.BindingClassOpenSlot) then
            return (function(self, callee, fn_ty)

            if schema.classof(self.slot) == O.SlotFunc then
                return erased.once({ kind = "unresolved", callee = callee })
            end
            return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        else
            error("erased phase moonlift_sem_binding_class_call_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function value_ref_call_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(ref, callee, fn_ty)

            return binding_class_call_target(ref.binding.class, callee, fn_ty)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefHole) then
            return (function(_, callee)
 return erased.once({ kind = "unresolved", callee = callee })
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function(_, callee)
 return erased.once({ kind = "unresolved", callee = callee })
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function(_, callee)
 return erased.once({ kind = "unresolved", callee = callee })
            end)(node, ...)
        else
            error("erased phase moonlift_sem_value_ref_call_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
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
 return erased.once({ kind = "unresolved", callee = callee })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function(callee, fn_ty)
 return erased.once({ kind = "closure", closure = callee, fn_ty = fn_ty })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function(callee, fn_ty)
 return erased.once(closure_or_indirect(callee, fn_ty))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSlotValue) then
            return (function(callee)
 return erased.once({ kind = "unresolved", callee = callee })
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUseExprFrag) then
            return (function(callee)
 return erased.once({ kind = "unresolved", callee = callee })
            end)(node, ...)
        else
            error("erased phase moonlift_sem_call_decide: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        import_call_target = import_call_target,
        binding_class_call_target = binding_class_call_target,
        value_ref_call_target = value_ref_call_target,
        callee_call_target = callee_call_target,
        decide = function(callee, fn_ty) return erased.one(callee_call_target(callee, fn_ty)) end,
    }
end

return M
