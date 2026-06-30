return function(T)
    local C = T.LalinCore
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local function void_ty()
        return Ty.TScalar(C.ScalarVoid)
    end

    local function canonical_type(scope, ty)
        return ty:typecheck_tree_canonical(scope)
    end

    local function append_all(out, values)
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    end

    local function type_eq(a, b)
        return a == b
    end

    function Ty.Type:typecheck_tree_field_lookup_base()
        return self
    end

    function Ty.TPtr:typecheck_tree_field_lookup_base()
        return self.elem
    end

    function Ty.TAccess:typecheck_tree_field_lookup_base()
        return self.base:typecheck_tree_field_lookup_base()
    end

    function Ty.TLease:typecheck_tree_field_lookup_base()
        return self.base:typecheck_tree_field_lookup_base()
    end

    local function field_layout_for(scope, ty, field_name)
        ty = canonical_type(scope, ty):typecheck_tree_field_lookup_base()
        local ref = ty:typecheck_tree_named_ref()
        if ref == nil then return nil end
        for i = 1, #scope.layouts do
            local layout = scope.layouts[i]
            if layout:typecheck_tree_matches_ref(ref) then return layout:typecheck_tree_field_layout(field_name) end
        end
        return nil
    end

    function Tr.ExprHeader:typecheck_tree_typed_ty()
        return nil
    end

    function Tr.ExprTyped:typecheck_tree_typed_ty()
        return self.ty
    end

    function Tr.PlaceHeader:typecheck_tree_typed_ty()
        return nil
    end

    function Tr.PlaceTyped:typecheck_tree_typed_ty()
        return self.ty
    end

    function C.Scalar:typecheck_tree_cast_bits() return nil end
    function C.ScalarBool:typecheck_tree_cast_bits() return 8 end
    function C.ScalarI8:typecheck_tree_cast_bits() return 8 end
    function C.ScalarI16:typecheck_tree_cast_bits() return 16 end
    function C.ScalarI32:typecheck_tree_cast_bits() return 32 end
    function C.ScalarI64:typecheck_tree_cast_bits() return 64 end
    function C.ScalarU8:typecheck_tree_cast_bits() return 8 end
    function C.ScalarU16:typecheck_tree_cast_bits() return 16 end
    function C.ScalarU32:typecheck_tree_cast_bits() return 32 end
    function C.ScalarU64:typecheck_tree_cast_bits() return 64 end
    function C.ScalarF32:typecheck_tree_cast_bits() return 32 end
    function C.ScalarF64:typecheck_tree_cast_bits() return 64 end
    function C.ScalarIndex:typecheck_tree_cast_bits() return 64 end

    function C.Scalar:typecheck_tree_cast_is_float() return false end
    function C.ScalarF32:typecheck_tree_cast_is_float() return true end
    function C.ScalarF64:typecheck_tree_cast_is_float() return true end

    function C.Scalar:typecheck_tree_cast_is_signed_int() return false end
    function C.ScalarI8:typecheck_tree_cast_is_signed_int() return true end
    function C.ScalarI16:typecheck_tree_cast_is_signed_int() return true end
    function C.ScalarI32:typecheck_tree_cast_is_signed_int() return true end
    function C.ScalarI64:typecheck_tree_cast_is_signed_int() return true end

    function C.Scalar:typecheck_tree_cast_is_unsigned_int() return false end
    function C.ScalarBool:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarU8:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarU16:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarU32:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarU64:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarIndex:typecheck_tree_cast_is_unsigned_int() return true end

    function C.Scalar:typecheck_tree_cast_is_int() return self:typecheck_tree_cast_is_signed_int() or self:typecheck_tree_cast_is_unsigned_int() end

    function Ty.Type:typecheck_tree_scalar_cast_op(op, to)
        if op == C.SurfaceCast and self == to then return C.MachineCastIdentity end
        return nil
    end
    function Ty.TScalar:typecheck_tree_scalar_cast_op(op, to)
        return to:typecheck_tree_scalar_cast_from(op, self.scalar)
    end
    function Ty.TPtr:typecheck_tree_scalar_cast_op(op, to)
        if op == C.SurfaceCast
            and asdl.classof(to) == Ty.TPtr
            and (type_eq(self.pointee, to.pointee) or tostring(self.pointee) == tostring(to.pointee))
        then
            return C.MachineCastIdentity
        end
        return nil
    end
    function Ty.Type:typecheck_tree_scalar_cast_from() return nil end
    function Ty.TScalar:typecheck_tree_scalar_cast_from(op, from)
        return op:typecheck_tree_machine_cast(from, self.scalar)
    end

    function C.SurfaceCastOp:typecheck_tree_machine_cast() return nil end
    function C.SurfaceBitcast:typecheck_tree_machine_cast(from, to) return C.MachineCastBitcast end
    function C.SurfaceTrunc:typecheck_tree_machine_cast(from, to) return C.MachineCastIreduce end
    function C.SurfaceSExt:typecheck_tree_machine_cast(from, to) return C.MachineCastSextend end
    function C.SurfaceZExt:typecheck_tree_machine_cast(from, to) return C.MachineCastUextend end
    function C.SurfaceSatCast:typecheck_tree_machine_cast() return nil end
    function C.SurfaceCast:typecheck_tree_machine_cast(from, to)
        if from == to then return C.MachineCastIdentity end
        local from_bits = from:typecheck_tree_cast_bits()
        local to_bits = to:typecheck_tree_cast_bits()
        if from_bits == nil or to_bits == nil then return nil end
        local from_float = from:typecheck_tree_cast_is_float()
        local to_float = to:typecheck_tree_cast_is_float()
        if from_float and to_float then
            if from_bits < to_bits then return C.MachineCastFpromote end
            if from_bits > to_bits then return C.MachineCastFdemote end
            return C.MachineCastBitcast
        end
        if from_float and to:typecheck_tree_cast_is_int() then
            return to:typecheck_tree_cast_is_signed_int() and C.MachineCastFToS or C.MachineCastFToU
        end
        if from:typecheck_tree_cast_is_int() and to_float then
            return from:typecheck_tree_cast_is_signed_int() and C.MachineCastSToF or C.MachineCastUToF
        end
        if from:typecheck_tree_cast_is_int() and to:typecheck_tree_cast_is_int() then
            if from_bits > to_bits then return C.MachineCastIreduce end
            if from_bits < to_bits then
                return from:typecheck_tree_cast_is_signed_int() and C.MachineCastSextend or C.MachineCastUextend
            end
            return C.MachineCastBitcast
        end
        return nil
    end

    function B.ValueRefBinding:typecheck_tree_ref()
        return Tr.TypeValueRefResult(self, self.binding.ty, {})
    end

    function B.ValueRefName:typecheck_tree_ref(input)
        local binding = input.scope:typecheck_tree_lookup_value(self.name)
        if binding ~= nil then return B.ValueRefBinding(binding):typecheck_tree_ref() end
        return Tr.TypeValueRefResult(self, void_ty(), { Tr.TypeIssueUnresolvedValue(self.name) })
    end

    function B.ValueRefPath:typecheck_tree_ref()
        return Tr.TypeValueRefResult(self, void_ty(), { Tr.TypeIssueUnresolvedPath(self.path) })
    end

    function Tr.ExprLit:typecheck_tree_expr()
        local ty = self.value:typecheck_tree_literal()
        return Tr.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(ty), self.value), ty, {})
    end

    function Tr.ExprLit:typecheck_tree_expr_expected(input)
        local ty = self.value:typecheck_tree_literal_expected(input.expected)
        if input.expected ~= nil
            and ty:typecheck_tree_is_integer_scalar()
            and input.expected:typecheck_tree_is_integer_scalar()
        then
            ty = input.expected
        end
        return Tr.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(ty), self.value), ty, {})
    end

    function Tr.ExprRef:typecheck_tree_expr(input)
        local ref_result = self.ref:typecheck_tree_ref(Tr.TypeValueRefInput(input.scope))
        return Tr.TypeExprResult(Tr.ExprRef(Tr.ExprTyped(ref_result.ty), ref_result.ref), ref_result.ty, ref_result.issues)
    end

    function Tr.ExprDot:typecheck_tree_expr(input)
        local base = self.base:typecheck_tree_expr(input)
        local typed_ty = self.h:typecheck_tree_typed_ty()
        local field = field_layout_for(input.scope, base.ty, self.name)
        if field ~= nil then
            local ref = Sem.FieldByName(field.field_name, field.ty)
            return Tr.TypeExprResult(Tr.ExprField(Tr.ExprTyped(field.ty), base.expr, ref), field.ty, base.issues)
        end
        if typed_ty ~= nil then return Tr.TypeExprResult(Tr.ExprDot(Tr.ExprTyped(typed_ty), base.expr, self.name), typed_ty, base.issues) end
        return Tr.TypeExprResult(Tr.ExprDot(Tr.ExprTyped(void_ty()), base.expr, self.name), void_ty(), base.issues)
    end

    function Tr.ExprCast:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local ty = canonical_type(input.scope, self.ty)
        local machine_op = value.ty:typecheck_tree_scalar_cast_op(self.op, ty)
        if machine_op == nil and self.op == C.SurfaceCast and tostring(value.ty) == tostring(ty) then
            machine_op = C.MachineCastIdentity
        end
        if machine_op ~= nil then
            return Tr.TypeExprResult(Tr.ExprMachineCast(Tr.ExprTyped(ty), machine_op, ty, value.expr), ty, value.issues)
        end
        return Tr.TypeExprResult(Tr.ExprCast(Tr.ExprTyped(ty), self.op, ty, value.expr), ty, value.issues)
    end

    function Tr.ExprCast:typecheck_tree_expr_expected(input)
        return self:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Tr.ExprMachineCast:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local ty = canonical_type(input.scope, self.ty)
        return Tr.TypeExprResult(Tr.ExprMachineCast(Tr.ExprTyped(ty), self.op, ty, value.expr), ty, value.issues)
    end

    function Tr.ExprUnary:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, value.issues)
        local ty = self.op:typecheck_tree_unary_result(value.ty)
        if ty == nil then
            issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryInvalidOperator(tostring(self.op)), value.ty)
            ty = value.ty
        end
        return Tr.TypeExprResult(Tr.ExprUnary(Tr.ExprTyped(ty), self.op, value.expr), ty, issues)
    end

    function Tr.ExprBinary:typecheck_tree_expr(input)
        local lhs = self.lhs:typecheck_tree_expr(input)
        local rhs = self.op:typecheck_tree_binary_rhs(self.rhs, input, lhs.ty)
        if lhs.ty:typecheck_tree_is_integer_scalar()
            and rhs.ty:typecheck_tree_is_integer_scalar()
            and rawget(rhs.expr, "value") ~= nil
            and tostring(asdl.classof(rawget(rhs.expr, "value"))):find("LalinCore.Lit", 1, true)
        then
            rhs = Tr.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(lhs.ty), rhs.expr.value), lhs.ty, rhs.issues)
        end
        local issues = {}
        append_all(issues, lhs.issues)
        append_all(issues, rhs.issues)
        local ty = self.op:typecheck_tree_binary_result(lhs.ty, rhs.ty)
        if ty == nil then
            issues[#issues + 1] = Tr.TypeIssueInvalidBinary(tostring(self.op), lhs.ty, rhs.ty)
            ty = lhs.ty
        end
        return Tr.TypeExprResult(Tr.ExprBinary(Tr.ExprTyped(ty), self.op, lhs.expr, rhs.expr), ty, issues)
    end

    function Tr.ExprLogic:typecheck_tree_expr(input)
        local lhs = self.lhs:typecheck_tree_expr(input)
        local rhs = self.rhs:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, lhs.issues)
        append_all(issues, rhs.issues)
        local ty = self.op:typecheck_tree_logic_result(lhs.ty, rhs.ty)
        if ty == nil then
            issues[#issues + 1] = Tr.TypeIssueInvalidLogic(tostring(self.op), lhs.ty, rhs.ty)
            ty = Ty.TScalar(C.ScalarBool)
        end
        return Tr.TypeExprResult(Tr.ExprLogic(Tr.ExprTyped(ty), self.op, lhs.expr, rhs.expr), ty, issues)
    end

    local function type_conditional_expr(expr, input)
        local cond = expr.cond:typecheck_tree_expr_expected(Tr.TypeExpectedExprInput(input.scope, Ty.TScalar(C.ScalarBool)))
        local then_expr = expr.then_expr:typecheck_tree_expr(input)
        local else_expr = expr.else_expr:typecheck_tree_expr_expected(Tr.TypeExpectedExprInput(input.scope, then_expr.ty))
        local issues = {}
        append_all(issues, cond.issues)
        append_all(issues, then_expr.issues)
        append_all(issues, else_expr.issues)
        if not type_eq(then_expr.ty, else_expr.ty) then
            issues[#issues + 1] = Tr.TypeIssueExpected("conditional branch", then_expr.ty, else_expr.ty)
        end
        return cond, then_expr, else_expr, issues
    end

    function Tr.ExprIf:typecheck_tree_expr(input)
        local cond, then_expr, else_expr, issues = type_conditional_expr(self, input)
        return Tr.TypeExprResult(Tr.ExprIf(Tr.ExprTyped(then_expr.ty), cond.expr, then_expr.expr, else_expr.expr), then_expr.ty, issues)
    end

    function Tr.ExprSelect:typecheck_tree_expr(input)
        local cond, then_expr, else_expr, issues = type_conditional_expr(self, input)
        return Tr.TypeExprResult(Tr.ExprSelect(Tr.ExprTyped(then_expr.ty), cond.expr, then_expr.expr, else_expr.expr), then_expr.ty, issues)
    end

    function Tr.ExprCompare:typecheck_tree_expr(input)
        local lhs = self.lhs:typecheck_tree_expr(input)
        local rhs = self.rhs:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, lhs.issues)
        append_all(issues, rhs.issues)
        if not type_eq(lhs.ty, rhs.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidCompare(tostring(self.op), lhs.ty, rhs.ty) end
        local ty = Ty.TScalar(C.ScalarBool)
        return Tr.TypeExprResult(Tr.ExprCompare(Tr.ExprTyped(ty), self.op, lhs.expr, rhs.expr), ty, issues)
    end

    function Tr.ExprControl:typecheck_tree_expr(input)
        local stmt_input = Tr.TypeStmtInput(input.scope, self.region.result_ty, Tr.TypeYieldValue(self.region.result_ty))
        local region = self.region:typecheck_tree_control_expr_region(Tr.TypeControlInput(stmt_input, self.region.region_id))
        return Tr.TypeExprResult(Tr.ExprControl(Tr.ExprTyped(self.region.result_ty), region.region), self.region.result_ty, region.issues)
    end

    function Tr.ExprAddrOf:typecheck_tree_expr(input)
        local place = self.place:typecheck_tree_place(input.scope:typecheck_tree_place_input())
        local ty = Ty.TPtr(place.ty)
        return Tr.TypeExprResult(Tr.ExprAddrOf(Tr.ExprTyped(ty), place.place), ty, place.issues)
    end

    function Tr.ExprDeref:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, value.issues)
        local ty = value.ty:typecheck_tree_deref_result()
        if ty == nil then
            issues[#issues + 1] = Tr.TypeIssueNotPointer(value.ty)
            ty = void_ty()
        end
        return Tr.TypeExprResult(Tr.ExprDeref(Tr.ExprTyped(ty), value.expr), ty, issues)
    end

    function Tr.ExprCall:typecheck_tree_expr(input)
        local callee = self.callee:typecheck_tree_expr(input)
        local result_ty, param_tys = callee.ty:typecheck_tree_callable_result()
        local issues = {}
        append_all(issues, callee.issues)
        if result_ty == nil then
            issues[#issues + 1] = Tr.TypeIssueNotCallable(callee.ty)
            result_ty, param_tys = void_ty(), {}
        end
        if #self.args ~= #(param_tys or {}) then
            issues[#issues + 1] = Tr.TypeIssueArgCount("call", #(param_tys or {}), #self.args)
        end
        local args = {}
        for i = 1, #self.args do
            local expected = param_tys and param_tys[i] or nil
            local arg = expected ~= nil
                and self.args[i]:typecheck_tree_expr_expected(Tr.TypeExpectedExprInput(input.scope, expected))
                or self.args[i]:typecheck_tree_expr(input)
            append_all(issues, arg.issues)
            if expected ~= nil and not type_eq(expected, arg.ty) then
                issues[#issues + 1] = Tr.TypeIssueExpected("call arg", expected, arg.ty)
            end
            args[#args + 1] = arg.expr
        end
        return Tr.TypeExprResult(Tr.ExprCall(Tr.ExprTyped(result_ty), callee.expr, args), result_ty, issues)
    end

    function Tr.ExprLoad:typecheck_tree_expr(input)
        local addr = self.addr:typecheck_tree_expr_expected(Tr.TypeExpectedExprInput(input.scope, Ty.TPtr(self.ty)))
        local issues = {}
        append_all(issues, addr.issues)
        if not type_eq(Ty.TPtr(self.ty), addr.ty) then
            issues[#issues + 1] = Tr.TypeIssueExpected("load addr", Ty.TPtr(self.ty), addr.ty)
        end
        return Tr.TypeExprResult(Tr.ExprLoad(Tr.ExprTyped(self.ty), self.ty, addr.expr), self.ty, issues)
    end

    function Tr.ExprLen:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, value.issues)
        local ty = value.ty:typecheck_tree_len_result()
        if ty == nil then
            issues[#issues + 1] = Tr.TypeIssueNotIndexable(value.ty)
            ty = Ty.TScalar(C.ScalarIndex)
        end
        return Tr.TypeExprResult(Tr.ExprLen(Tr.ExprTyped(ty), value.expr), ty, issues)
    end

    function Tr.IndexBase:typecheck_tree_index_base()
        return Tr.TypeIndexBaseResult(self, void_ty(), { Tr.TypeIssueNotIndexable(void_ty()) })
    end

    function Tr.IndexBaseExpr:typecheck_tree_index_base(input)
        local base = self.base:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
        local issues = {}
        append_all(issues, base.issues)
        local elem = base.ty:typecheck_tree_index_elem()
        if elem == nil then
            issues[#issues + 1] = Tr.TypeIssueNotIndexable(base.ty)
            elem = void_ty()
        end
        return Tr.TypeIndexBaseResult(Tr.IndexBaseExpr(base.expr), elem, issues)
    end

    function Tr.IndexBasePlace:typecheck_tree_index_base(input)
        local place = self.base:typecheck_tree_place(Tr.TypePlaceInput(input.scope))
        local elem = place.ty:typecheck_tree_index_elem() or self.elem
        local issues = {}
        append_all(issues, place.issues)
        if elem == nil then
            issues[#issues + 1] = Tr.TypeIssueNotIndexable(place.ty)
            elem = void_ty()
        end
        return Tr.TypeIndexBaseResult(Tr.IndexBasePlace(place.place, elem), elem, issues)
    end

    function Tr.IndexBaseView:typecheck_tree_index_base(input)
        local view = self.view:typecheck_tree_view(Tr.TypeViewInput(input.scope))
        local elem = view.view:typecheck_tree_elem()
        return Tr.TypeIndexBaseResult(Tr.IndexBaseView(view.view), elem, view.issues)
    end

    function Tr.ExprIndex:typecheck_tree_expr(input)
        local base = self.base:typecheck_tree_index_base(Tr.TypeIndexBaseInput(input.scope))
        local index = self.index:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, base.issues)
        append_all(issues, index.issues)
        if not index.ty:typecheck_tree_is_integer_scalar() then
            issues[#issues + 1] = Tr.TypeIssueExpected("index", Ty.TScalar(C.ScalarIndex), index.ty)
        end
        return Tr.TypeExprResult(Tr.ExprIndex(Tr.ExprTyped(base.elem), base.base, index.expr), base.elem, issues)
    end

    function Tr.PlaceRef:typecheck_tree_place(input)
        local ref_result = self.ref:typecheck_tree_ref(Tr.TypeValueRefInput(input.scope))
        return Tr.TypePlaceResult(Tr.PlaceRef(Tr.PlaceTyped(ref_result.ty), ref_result.ref), ref_result.ty, ref_result.issues)
    end

    function Tr.PlaceDeref:typecheck_tree_place(input)
        local base = self.base:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
        local issues = {}
        append_all(issues, base.issues)
        local ty = base.ty:typecheck_tree_deref_result()
        if ty == nil then
            issues[#issues + 1] = Tr.TypeIssueNotPointer(base.ty)
            ty = void_ty()
        end
        return Tr.TypePlaceResult(Tr.PlaceDeref(Tr.PlaceTyped(ty), base.expr), ty, issues)
    end

    function Tr.PlaceDot:typecheck_tree_place(input)
        local base = self.base:typecheck_tree_place(input)
        local typed_ty = self.h:typecheck_tree_typed_ty()
        local field = field_layout_for(input.scope, base.ty, self.name)
        if field ~= nil then
            local ref = Sem.FieldByName(field.field_name, field.ty)
            return Tr.TypePlaceResult(Tr.PlaceField(Tr.PlaceTyped(field.ty), base.place, ref), field.ty, base.issues)
        end
        if typed_ty ~= nil then return Tr.TypePlaceResult(Tr.PlaceDot(Tr.PlaceTyped(typed_ty), base.place, self.name), typed_ty, base.issues) end
        return Tr.TypePlaceResult(Tr.PlaceDot(Tr.PlaceTyped(void_ty()), base.place, self.name), void_ty(), base.issues)
    end

    function Tr.PlaceIndex:typecheck_tree_place(input)
        local base = self.base:typecheck_tree_index_base(Tr.TypeIndexBaseInput(input.scope))
        local index = self.index:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
        local issues = {}
        append_all(issues, base.issues)
        append_all(issues, index.issues)
        if not index.ty:typecheck_tree_is_integer_scalar() then
            issues[#issues + 1] = Tr.TypeIssueExpected("index", Ty.TScalar(C.ScalarIndex), index.ty)
        end
        return Tr.TypePlaceResult(Tr.PlaceIndex(Tr.PlaceTyped(base.elem), base.base, index.expr), base.elem, issues)
    end

    function Tr.Expr:typecheck_tree_expr_expected(input)
        local result = self:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
        if input.expected ~= nil
            and result.ty:typecheck_tree_is_integer_scalar()
            and input.expected:typecheck_tree_is_integer_scalar()
            and asdl.classof(result.expr) == Tr.ExprLit
        then
            return Tr.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(input.expected), result.expr.value), input.expected, result.issues)
        end
        return result
    end

    function Tr.ExprAgg:typecheck_tree_expr_expected(input)
        return input.expected:typecheck_tree_expr_agg_expected(self, input)
    end

    function Tr.ExprAgg:typecheck_tree_expr(input)
        local fields = {}
        local issues = {}
        for i = 1, #(self.fields or {}) do
            local field = self.fields[i]
            local value = field.value:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
            append_all(issues, value.issues)
            fields[#fields + 1] = Tr.FieldInit(field.name, value.expr, field.offset)
        end
        return Tr.TypeExprResult(Tr.ExprAgg(Tr.ExprTyped(self.ty), self.ty, fields), self.ty, issues)
    end

    function Ty.Type:typecheck_tree_expr_agg_expected(expr, input)
        return expr:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Ty.TNamed:typecheck_tree_expr_agg_expected(expr, input)
        return Tr.ExprAgg(Tr.ExprSurface, self, expr.fields):typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Ty.TClosure:typecheck_tree_expr_agg_expected(expr, input)
        return Tr.ExprAgg(Tr.ExprSurface, self, expr.fields):typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Tr.ExprArray:typecheck_tree_expr_expected(input)
        return input.expected:typecheck_tree_expr_array_expected(self, input)
    end

    function Ty.Type:typecheck_tree_expr_array_expected(expr, input)
        return expr:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Ty.TArray:typecheck_tree_expr_array_expected(expr, input)
        local expected_count = self.count:typecheck_tree_const_count()
        local issues = {}
        if expected_count ~= nil and expected_count ~= #expr.elems then
            issues[#issues + 1] = Tr.TypeIssueExpected("array length", self, Ty.TArray(Ty.ArrayLenConst(#expr.elems), self.elem))
        end
        local elems = {}
        for i = 1, #expr.elems do
            local elem_result = expr.elems[i]:typecheck_tree_expr_expected(Tr.TypeExpectedExprInput(input.scope, self.elem))
            for j = 1, #elem_result.issues do issues[#issues + 1] = elem_result.issues[j] end
            if elem_result.ty ~= self.elem then issues[#issues + 1] = Tr.TypeIssueExpected("array elem", self.elem, elem_result.ty) end
            elems[#elems + 1] = elem_result.expr
        end
        local ty = Ty.TArray(Ty.ArrayLenConst(#elems), self.elem)
        return Tr.TypeExprResult(Tr.ExprArray(Tr.ExprTyped(ty), self.elem, elems), ty, issues)
    end
end
