local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.stencil_methods ~= nil then return T._lalin_api_cache.stencil_methods end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Kernel = T.LalinKernel
    local SM = T.LalinStencilMachine
    local Stencil = T.LalinStencil
    local Value = T.LalinValue

    local function const_int_value(value)
        if asdl.classof(value) == Value.ValueExprConst
            and asdl.classof(value.const) == Code.CodeConstLiteral
            and asdl.classof(value.const.literal) == Core.LitInt then
            return tonumber(value.const.literal.raw)
        end
        return nil
    end

    local function const_ty(value)
        if asdl.classof(value) == Value.ValueExprConst and value.const ~= nil then return value.const.ty end
        return nil
    end

    function Core.UnaryOp:stencil_unary_op() return nil end
    function Core.UnaryNeg:stencil_unary_op() return Stencil.StencilUnaryNeg end
    function Core.UnaryBitNot:stencil_unary_op() return Stencil.StencilUnaryBitNot end
    function Core.UnaryNot:stencil_unary_op() return Stencil.StencilUnaryBoolNot end

    function Core.BinaryOp:stencil_binary_op() return nil end
    function Core.BinAdd:stencil_binary_op() return Stencil.StencilBinaryAdd end
    function Core.BinSub:stencil_binary_op() return Stencil.StencilBinarySub end
    function Core.BinMul:stencil_binary_op() return Stencil.StencilBinaryMul end
    function Core.BinDiv:stencil_binary_op() return Stencil.StencilBinaryDiv end
    function Core.BinRem:stencil_binary_op() return Stencil.StencilBinaryMod end
    function Core.BinBitAnd:stencil_binary_op() return Stencil.StencilBinaryAnd end
    function Core.BinBitOr:stencil_binary_op() return Stencil.StencilBinaryOr end
    function Core.BinBitXor:stencil_binary_op() return Stencil.StencilBinaryXor end
    function Core.BinShl:stencil_binary_op() return Stencil.StencilBinaryShl end
    function Core.BinLShr:stencil_binary_op() return Stencil.StencilBinaryLShr end
    function Core.BinAShr:stencil_binary_op() return Stencil.StencilBinaryAShr end

    local function same_source_type(a, b)
        if a == b then return true end
        if a == nil or b == nil then return false end
        return tostring(a) == tostring(b)
    end

    function Code.CodeType:stencil_supported_type() return false end
    function Code.CodeTyInt:stencil_supported_type() return true end
    function Code.CodeTyFloat:stencil_supported_type() return true end
    function Code.CodeTyIndex:stencil_supported_type() return true end
    function Code.CodeTyBool8:stencil_supported_type() return true end
    function Code.CodeTyDataPtr:stencil_supported_type() return true end
    function Code.CodeTyCodePtr:stencil_supported_type() return true end
    function Code.CodeTyNamed:stencil_supported_type() return true end
    function Code.CodeTyArray:stencil_supported_type() return true end
    function Code.CodeTySlice:stencil_supported_type() return true end
    function Code.CodeTyView:stencil_supported_type() return true end
    function Code.CodeTyByteSpan:stencil_supported_type() return true end
    function Code.CodeTyHandle:stencil_supported_type() return true end
    function Code.CodeTyLease:stencil_supported_type() return true end
    function Code.CodeTyClosure:stencil_supported_type() return true end
    function Code.CodeTyImportedC:stencil_supported_type() return true end
    function Code.CodeTyImportedCFuncPtr:stencil_supported_type() return true end
    function Code.CodeTyVector:stencil_supported_type() return true end

    function Code.CodeType:stencil_same_type(other) return self == other end
    function Code.CodeType:stencil_same_int() return false end
    function Code.CodeType:stencil_same_float() return false end
    function Code.CodeType:stencil_same_data_ptr() return false end
    function Code.CodeType:stencil_same_code_ptr() return false end
    function Code.CodeType:stencil_same_named() return false end
    function Code.CodeType:stencil_same_array() return false end
    function Code.CodeType:stencil_same_slice() return false end
    function Code.CodeType:stencil_same_view() return false end
    function Code.CodeType:stencil_same_handle() return false end
    function Code.CodeType:stencil_same_lease() return false end
    function Code.CodeType:stencil_same_closure() return false end
    function Code.CodeType:stencil_same_imported_c() return false end
    function Code.CodeType:stencil_same_imported_c_func_ptr() return false end
    function Code.CodeType:stencil_same_vector() return false end

    function Code.CodeTyInt:stencil_same_type(other) return other:stencil_same_int(self.bits, self.signedness) end
    function Code.CodeTyInt:stencil_same_int(bits, signedness) return self.bits == bits and self.signedness == signedness end
    function Code.CodeTyFloat:stencil_same_type(other) return other:stencil_same_float(self.bits) end
    function Code.CodeTyFloat:stencil_same_float(bits) return self.bits == bits end
    function Code.CodeTyDataPtr:stencil_same_type(other) return other:stencil_same_data_ptr(self.pointee) end
    function Code.CodeTyDataPtr:stencil_same_data_ptr(pointee)
        if self.pointee == nil or pointee == nil then return self.pointee == pointee end
        return self.pointee:stencil_same_type(pointee)
    end
    function Code.CodeTyCodePtr:stencil_same_type(other) return other:stencil_same_code_ptr(self.sig) end
    function Code.CodeTyCodePtr:stencil_same_code_ptr(sig) return self.sig == sig end
    function Code.CodeTyNamed:stencil_same_type(other) return other:stencil_same_named(self.module_name, self.type_name) end
    function Code.CodeTyNamed:stencil_same_named(module_name, type_name) return self.module_name == module_name and self.type_name == type_name end
    function Code.CodeTyArray:stencil_same_type(other) return other:stencil_same_array(self.elem, self.count) end
    function Code.CodeTyArray:stencil_same_array(elem, count) return self.count == count and self.elem:stencil_same_type(elem) end
    function Code.CodeTySlice:stencil_same_type(other) return other:stencil_same_slice(self.elem) end
    function Code.CodeTySlice:stencil_same_slice(elem) return self.elem:stencil_same_type(elem) end
    function Code.CodeTyView:stencil_same_type(other) return other:stencil_same_view(self.elem) end
    function Code.CodeTyView:stencil_same_view(elem) return self.elem:stencil_same_type(elem) end
    function Code.CodeTyHandle:stencil_same_type(other) return other:stencil_same_handle(self.repr, self.source_ty) end
    function Code.CodeTyHandle:stencil_same_handle(repr, source_ty) return self.repr:stencil_same_type(repr) and same_source_type(self.source_ty, source_ty) end
    function Code.CodeTyLease:stencil_same_type(other) return other:stencil_same_lease(self.base, self.source_ty) end
    function Code.CodeTyLease:stencil_same_lease(base, source_ty) return self.base:stencil_same_type(base) and same_source_type(self.source_ty, source_ty) end
    function Code.CodeTyClosure:stencil_same_type(other) return other:stencil_same_closure(self.sig) end
    function Code.CodeTyClosure:stencil_same_closure(sig) return self.sig == sig end
    function Code.CodeTyImportedC:stencil_same_type(other) return other:stencil_same_imported_c(self.id) end
    function Code.CodeTyImportedC:stencil_same_imported_c(id) return self.id == id or (self.id.module_name == id.module_name and self.id.spelling == id.spelling) end
    function Code.CodeTyImportedCFuncPtr:stencil_same_type(other) return other:stencil_same_imported_c_func_ptr(self.sig) end
    function Code.CodeTyImportedCFuncPtr:stencil_same_imported_c_func_ptr(sig) return self.sig == sig end
    function Code.CodeTyVector:stencil_same_type(other) return other:stencil_same_vector(self.elem, self.lanes) end
    function Code.CodeTyVector:stencil_same_vector(elem, lanes) return self.lanes == lanes and self.elem:stencil_same_type(elem) end

    function Code.CodeType:stencil_is_index_data_type() return false end
    function Code.CodeTyInt:stencil_is_index_data_type() return true end
    function Code.CodeTyIndex:stencil_is_index_data_type() return true end
    function Code.CodeType:stencil_reduction_supported() return false end
    function Code.CodeTyInt:stencil_reduction_supported(reduction_kind, elem_ty)
        if not elem_ty:stencil_same_type(self) then return false end
        return reduction_kind == Value.ReductionAdd or reduction_kind == Value.ReductionMul
            or reduction_kind == Value.ReductionAnd or reduction_kind == Value.ReductionOr or reduction_kind == Value.ReductionXor
            or reduction_kind == Value.ReductionMin or reduction_kind == Value.ReductionMax
    end
    function Code.CodeTyFloat:stencil_reduction_supported(reduction_kind, elem_ty)
        if not elem_ty:stencil_same_type(self) then return false end
        return reduction_kind == Value.ReductionAdd or reduction_kind == Value.ReductionMul
            or reduction_kind == Value.ReductionMin or reduction_kind == Value.ReductionMax
    end

    function Code.CodeType:stencil_bits() return nil end
    function Code.CodeTyInt:stencil_bits() return tonumber(self.bits) end
    function Code.CodeTyFloat:stencil_bits() return tonumber(self.bits) end
    function Code.CodeTyIndex:stencil_bits() return 64 end
    function Code.CodeTyBool8:stencil_bits() return 8 end

    local function predicate_from_cmp_const(op, operand_ty, cexpr, const_on_left)
        if asdl.classof(cexpr) ~= Value.ValueExprConst then return nil end
        if const_on_left then
            if op == Core.CmpLt then op = Core.CmpGt
            elseif op == Core.CmpLe then op = Core.CmpGe
            elseif op == Core.CmpGt then op = Core.CmpLt
            elseif op == Core.CmpGe then op = Core.CmpLe end
        end
        if op == Core.CmpEq or op == Core.CmpNe or op == Core.CmpLt or op == Core.CmpLe or op == Core.CmpGt or op == Core.CmpGe then
            return Stencil.StencilPredCompareConst(op, operand_ty, cexpr)
        end
        return nil
    end

    local function access_ref(name)
        return Stencil.StencilAccessRef(name)
    end

    local function input_expr(name)
        return Stencil.StencilPointInput(access_ref(name))
    end

    local function const_expr(value, ty)
        return Stencil.StencilPointConst(value, ty)
    end

    local function point_unary_expr(op, arg, result_ty)
        return Stencil.StencilPointUnary(op, arg, result_ty, nil, nil)
    end

    local function point_binary_expr(op, left, right, result_ty, int_semantics)
        return Stencil.StencilPointBinary(op, left, right, result_ty, int_semantics, nil)
    end

    local function point_cast_expr(op, arg, from, to)
        return Stencil.StencilPointCast(op, arg, from, to)
    end

    local function point_predicate_expr(pred, arg, result_ty)
        return Stencil.StencilPointPredicate(pred, arg, result_ty)
    end

    local function point_compare_expr(cmp, left, right, result_ty)
        return Stencil.StencilPointCompare(cmp, left, right, result_ty)
    end

    local function point_select_expr(cond, then_expr, else_expr, result_ty)
        return Stencil.StencilPointSelect(Stencil.StencilPredNonZero, cond, then_expr, else_expr, result_ty)
    end

    local function scalar_input_expr(value, state)
        local name = "x" .. tostring(#state.inputs + 1)
        state.inputs[#state.inputs + 1] = SM.StencilMachinePointInput(
            name,
            nil,
            nil,
            value,
            nil,
            nil,
            nil,
            nil,
            Stencil.StencilLayoutScalar(value),
            Stencil.StencilAccessRead,
            true,
            nil,
            {}
        )
        return input_expr(name)
    end

    function SM.StencilMachineExprBindings:lookup(id)
        for _, binding in ipairs(self.bindings or {}) do
            if binding.value_id.text == id.text then return binding end
        end
        return nil
    end

    function SM.StencilMachineExprFactInput:has_seen(id)
        for _, seen_id in ipairs(self.seen or {}) do
            if seen_id.text == id.text then return true end
        end
        return false
    end

    function SM.StencilMachineExprFactInput:with_seen(id)
        local seen = {}
        for i, seen_id in ipairs(self.seen or {}) do seen[i] = seen_id end
        seen[#seen + 1] = id
        return SM.StencilMachineExprFactInput(self.kernel_expr, self.bindings, seen)
    end

    function SM.StencilMachineExprFactInput:with_expr(expr)
        return SM.StencilMachineExprFactInput(expr, self.bindings, self.seen)
    end

    function SM.StencilMachineExprFactInput:fact_for_expr(expr)
        if expr == nil then return nil, "missing stencil expression" end
        return expr:stencil_expr_fact(self:with_expr(expr))
    end

    function SM.StencilMachineExprFactInput:fact_for_value(value)
        return self:fact_for_expr(Kernel.KernelExprAlgebra(value))
    end

    function Kernel.KernelExpr:stencil_expr_fact()
        return nil, "unsupported store stencil expression"
    end

    function Kernel.KernelExprKernelValue:stencil_expr_fact(input)
        if input:has_seen(self.value) then return nil, "cyclic kernel binding" end
        local binding = input.bindings:lookup(self.value)
        if binding == nil then return nil, "missing kernel binding " .. self.value.text end
        local fact, err = input:with_seen(self.value):fact_for_expr(binding.kernel_expr)
        if fact == nil then return nil, err end
        return SM.StencilMachineExprKernelValue(self.value, fact), nil
    end

    function Kernel.KernelExprLaneLoad:stencil_expr_fact()
        return SM.StencilMachineExprLoad(self.lane, self.index), nil
    end

    function Kernel.KernelExprAlgebra:stencil_expr_fact(input)
        return self.expr:stencil_expr_fact(input)
    end

    function Value.ValueExpr:stencil_expr_fact()
        return nil, "unsupported store stencil expression"
    end

    function Value.ValueExprConst:stencil_expr_fact()
        return SM.StencilMachineExprFill(self), nil
    end

    function Value.ValueExprValue:stencil_expr_fact(input)
        local id = Kernel.KernelValueId("kval:" .. self.value.text)
        local binding = input.bindings:lookup(id)
        if binding == nil then return SM.StencilMachineExprFill(self), nil end
        if input:has_seen(id) then return nil, "cyclic kernel binding" end
        local fact, err = input:with_seen(id):fact_for_expr(binding.kernel_expr)
        if fact == nil then return nil, err end
        return SM.StencilMachineExprKernelValue(id, fact), nil
    end

    function Value.ValueExprUnary:stencil_expr_fact(input)
        local fact, err = input:fact_for_value(self.value)
        if fact == nil then return nil, err end
        return SM.StencilMachineExprUnary(self.op:stencil_unary_op(), fact, self.ty), nil
    end

    function Value.ValueExprCast:stencil_expr_fact(input)
        local fact, err = input:fact_for_value(self.value)
        if fact == nil then return nil, err end
        return SM.StencilMachineExprCast(self.op, fact, self.from, self.to), nil
    end

    function Value.ValueExprAdd:stencil_expr_fact(input)
        local lhs, lhs_err = input:fact_for_value(self.a)
        if lhs == nil then return nil, lhs_err end
        local rhs, rhs_err = input:fact_for_value(self.b)
        if rhs == nil then return nil, rhs_err end
        return SM.StencilMachineExprBinary(Stencil.StencilBinaryAdd, lhs, rhs, self.ty, self.sem), nil
    end

    function Value.ValueExprSub:stencil_expr_fact(input)
        local lhs, lhs_err = input:fact_for_value(self.a)
        if lhs == nil then return nil, lhs_err end
        local rhs, rhs_err = input:fact_for_value(self.b)
        if rhs == nil then return nil, rhs_err end
        return SM.StencilMachineExprBinary(Stencil.StencilBinarySub, lhs, rhs, self.ty, self.sem), nil
    end

    function Value.ValueExprMul:stencil_expr_fact(input)
        local lhs, lhs_err = input:fact_for_value(self.a)
        if lhs == nil then return nil, lhs_err end
        local rhs, rhs_err = input:fact_for_value(self.b)
        if rhs == nil then return nil, rhs_err end
        return SM.StencilMachineExprBinary(Stencil.StencilBinaryMul, lhs, rhs, self.ty, self.sem), nil
    end

    function Value.ValueExprDiv:stencil_expr_fact(input)
        local lhs, lhs_err = input:fact_for_value(self.a)
        if lhs == nil then return nil, lhs_err end
        local rhs, rhs_err = input:fact_for_value(self.b)
        if rhs == nil then return nil, rhs_err end
        return SM.StencilMachineExprBinary(Stencil.StencilBinaryDiv, lhs, rhs, self.ty, self.sem), nil
    end

    function Value.ValueExprRem:stencil_expr_fact(input)
        local lhs, lhs_err = input:fact_for_value(self.a)
        if lhs == nil then return nil, lhs_err end
        local rhs, rhs_err = input:fact_for_value(self.b)
        if rhs == nil then return nil, rhs_err end
        return SM.StencilMachineExprBinary(Stencil.StencilBinaryMod, lhs, rhs, self.ty, self.sem), nil
    end

    function Value.ValueExprBinary:stencil_expr_fact(input)
        local lhs, lhs_err = input:fact_for_value(self.a)
        if lhs == nil then return nil, lhs_err end
        local rhs, rhs_err = input:fact_for_value(self.b)
        if rhs == nil then return nil, rhs_err end
        local op = self.op:stencil_binary_op()
        if op == nil then return nil, "unsupported binary value expression" end
        return SM.StencilMachineExprBinary(op, lhs, rhs, self.ty, self.sem), nil
    end

    function Value.ValueExprCmp:stencil_expr_fact(input)
        local lhs, lhs_err = input:fact_for_value(self.a)
        if lhs == nil then return nil, lhs_err end
        local rhs, rhs_err = input:fact_for_value(self.b)
        if rhs == nil then return nil, rhs_err end
        return SM.StencilMachineExprCmp(self.op, lhs, rhs, Code.CodeTyBool8), nil
    end

    function Value.ValueExprSelect:stencil_expr_fact(input)
        local cond, cond_err = input:fact_for_value(self.cond)
        if cond == nil then return nil, cond_err end
        local t, t_err = input:fact_for_value(self.t)
        if t == nil then return nil, t_err end
        local f, f_err = input:fact_for_value(self.f)
        if f == nil then return nil, f_err end
        return SM.StencilMachineExprSelect(cond, t, f), nil
    end

    local function lane_key(lane, index)
        local id = lane and lane.id and lane.id.text or tostring(lane)
        return id .. "@" .. tostring(index)
    end

    function SM.StencilMachinePointClass:point_input_named(name)
        for _, input in ipairs(self.inputs or {}) do
            if input.name == name then return input end
        end
        return nil
    end

    function SM.StencilMachinePointClass:single_point_input()
        if #(self.inputs or {}) ~= 1 then return nil end
        return self.inputs[1]
    end

    function SM.StencilMachinePointClass:all_inputs_primary()
        for _, input in ipairs(self.inputs or {}) do
            if input.index_primary ~= true then return false end
        end
        return true
    end

    function Stencil.StencilPointExpr:stencil_single_input_expr() return nil end
    function Stencil.StencilPointInput:stencil_single_input_expr(point_class)
        return point_class:point_input_named(self.access.name)
    end

    function Stencil.StencilPointExpr:stencil_const_int() return nil end
    function Stencil.StencilPointConst:stencil_const_int()
        return const_int_value(self.value)
    end

    function Stencil.StencilPointExpr:stencil_index_input() return nil end
    function Stencil.StencilPointInput:stencil_index_input(point_class)
        return point_class:point_input_named(self.access.name)
    end
    function Stencil.StencilPointCast:stencil_index_input(point_class)
        return self.arg:stencil_index_input(point_class)
    end
    function Stencil.StencilPointBinary:stencil_index_input(point_class)
        local lc, rc = self.left:stencil_const_int(), self.right:stencil_const_int()
        if (self.op == Stencil.StencilBinaryMul and rc == 1)
            or (self.op == Stencil.StencilBinaryAdd and rc == 0)
            or (self.op == Stencil.StencilBinarySub and rc == 0) then
            return self.left:stencil_index_input(point_class)
        end
        if (self.op == Stencil.StencilBinaryMul and lc == 1)
            or (self.op == Stencil.StencilBinaryAdd and lc == 0) then
            return self.right:stencil_index_input(point_class)
        end
        return nil
    end

    function Stencil.StencilPointExpr:stencil_predicate_operand() return nil, nil end
    function Stencil.StencilPointPredicate:stencil_predicate_operand(point_class)
        local input = self.arg:stencil_single_input_expr(point_class)
        if input == nil then return nil, nil end
        return input, self.pred
    end
    function Stencil.StencilPointCompare:stencil_predicate_operand(point_class)
        local input = self.left:stencil_single_input_expr(point_class)
        if input == nil then return nil, nil end
        return self.right:stencil_compare_const_predicate_for_input(input, self.cmp)
    end

    function Stencil.StencilPointExpr:stencil_compare_const_predicate_for_input()
        return nil, nil
    end

    function Stencil.StencilPointConst:stencil_compare_const_predicate_for_input(input, cmp)
        return input, Stencil.StencilPredCompareConst(cmp, input.ty, self.value)
    end

    local function point_input_for_load(expr, state)
        local key = lane_key(expr.lane, expr.index)
        local existing = state.by_key[key]
        if existing ~= nil then return input_expr(existing.name), existing.ty end
        local name = "x" .. tostring(#state.inputs + 1)
        local input = SM.StencilMachinePointInput(
            name,
            expr.lane,
            expr.index,
            nil,
            nil,
            nil,
            expr.lane.elem_ty,
            nil,
            nil,
            nil,
            false,
            nil,
            {}
        )
        state.by_key[key] = input
        state.inputs[#state.inputs + 1] = input
        return input_expr(name), input.ty
    end

    function SM.StencilMachineExprFact:to_stencil_point_expr()
        return nil, nil, "unsupported store stencil expression"
    end

    function SM.StencilMachineExprFact:stencil_const_int()
        return nil
    end

    function SM.StencilMachineExprFact:stencil_compare_const_predicate()
        return nil
    end

    function SM.StencilMachineExprKernelValue:to_stencil_point_expr(state)
        return self.binding:to_stencil_point_expr(state)
    end

    function SM.StencilMachineExprLoad:to_stencil_point_expr(state)
        return point_input_for_load(self, state)
    end

    function SM.StencilMachineExprFill:to_stencil_point_expr(state)
        local ty = const_ty(self.value)
        if ty == nil then return scalar_input_expr(self.value, state), nil end
        return const_expr(self.value, ty), ty
    end

    function SM.StencilMachineExprFill:stencil_const_int()
        return const_int_value(self.value)
    end

    function SM.StencilMachineExprLoad:stencil_compare_const_predicate(op, lhs_expr, lhs_ty, rhs, rhs_expr, rhs_ty)
        return rhs:stencil_compare_const_predicate_from_left_load(op, lhs_expr, lhs_ty, rhs_expr, rhs_ty)
    end

    function SM.StencilMachineExprFact:stencil_compare_const_predicate_from_left_load()
        return nil
    end

    function SM.StencilMachineExprFill:stencil_compare_const_predicate_from_left_load(op, lhs_expr, lhs_ty)
        return predicate_from_cmp_const(op, lhs_ty, self.value, false), lhs_expr
    end

    function SM.StencilMachineExprFill:stencil_compare_const_predicate(op, op_expr, op_ty, rhs, rhs_expr, rhs_ty)
        return rhs:stencil_compare_const_predicate_from_left_fill(op, self.value, rhs_expr, rhs_ty)
    end

    function SM.StencilMachineExprFact:stencil_compare_const_predicate_from_left_fill()
        return nil
    end

    function SM.StencilMachineExprLoad:stencil_compare_const_predicate_from_left_fill(op, const_value, rhs_expr, rhs_ty)
        return predicate_from_cmp_const(op, rhs_ty, const_value, true), rhs_expr
    end

    function SM.StencilMachineExprUnary:to_stencil_point_expr(state)
        if self.op == nil then return nil, nil, "unsupported unary stencil operator" end
        local arg, _, err = self.value:to_stencil_point_expr(state)
        if arg == nil then return nil, nil, err end
        return point_unary_expr(self.op, arg, self.result_ty), self.result_ty
    end

    function SM.StencilMachineExprCast:to_stencil_point_expr(state)
        local arg, _, err = self.value:to_stencil_point_expr(state)
        if arg == nil then return nil, nil, err end
        return point_cast_expr(self.op, arg, self.src_ty, self.result_ty), self.result_ty
    end

    function SM.StencilMachineExprBinary:to_stencil_point_expr(state)
        if self.op == nil then return nil, nil, "unsupported binary stencil operator" end
        local lhs, _, lhs_err = self.lhs:to_stencil_point_expr(state)
        if lhs == nil then return nil, nil, lhs_err end
        local rhs, _, rhs_err = self.rhs:to_stencil_point_expr(state)
        if rhs == nil then return nil, nil, rhs_err end
        return point_binary_expr(self.op, lhs, rhs, self.result_ty, self.int_semantics), self.result_ty
    end

    function SM.StencilMachineExprCmp:to_stencil_point_expr(state)
        local lhs, lhs_ty, lhs_err = self.lhs:to_stencil_point_expr(state)
        if lhs == nil then return nil, nil, lhs_err end
        local rhs, rhs_ty, rhs_err = self.rhs:to_stencil_point_expr(state)
        if rhs == nil then return nil, nil, rhs_err end
        local pred, arg = self.lhs:stencil_compare_const_predicate(self.op, lhs, lhs_ty, self.rhs, rhs, rhs_ty)
        if pred ~= nil then return point_predicate_expr(pred, arg, self.result_ty), self.result_ty end
        return point_compare_expr(self.op, lhs, rhs, self.result_ty), self.result_ty
    end

    function SM.StencilMachineExprSelect:to_stencil_point_expr(state)
        local cond, _, cond_err = self.cond:to_stencil_point_expr(state)
        if cond == nil then return nil, nil, cond_err end
        local t, result_ty, t_err = self.then_fact:to_stencil_point_expr(state)
        if t == nil then return nil, nil, t_err end
        local f, _, f_err = self.else_fact:to_stencil_point_expr(state)
        if f == nil then return nil, nil, f_err end
        return point_select_expr(cond, t, f, result_ty), result_ty
    end

    local function classify_expr(expr)
        local state = { inputs = {}, by_key = {} }
        local point_expr, result_ty, err = expr:to_stencil_point_expr(state)
        if point_expr == nil then return nil, err end
        return SM.StencilMachinePointClass(point_expr, state.inputs, result_ty, expr:stencil_const_int())
    end

    function SM.StencilMachinePointClass:select_index_lane()
        local input = self.expr:stencil_index_input(self)
        if input ~= nil then return { lane = input.lane, index = input.index } end
        return nil
    end

    local function copy_inputs(inputs)
        local out = {}
        for i, input in ipairs(inputs or {}) do out[i] = input end
        return out
    end

    local function append_input_once(inputs, input)
        for _, existing in ipairs(inputs or {}) do
            if existing.name == input.name then return inputs end
        end
        inputs[#inputs + 1] = input
        return inputs
    end

    local function specialize_scalar_inputs(inputs, ty)
        local out = {}
        for i, input in ipairs(inputs or {}) do
            if input.scalar_value ~= nil and input.ty == nil then
                out[i] = asdl.with(input, { ty = ty })
            else
                out[i] = input
            end
        end
        return out
    end

    function SM.StencilMachineStoreSelectInput:store_n_info(inputs, dst_layout, store_mode)
        local point_class = self.class
        inputs = inputs or point_class.inputs
        store_mode = store_mode or self.store_mode
        if store_mode == nil and self.copy_semantics ~= nil then
            store_mode = Stencil.StencilStoreCopy(self.copy_semantics)
        end
        local result_ty = point_class.result_ty or self.dst_elem_ty
        return SM.StencilMachineSelectionInfo(
            self.step_num, self.producer,
            nil, result_ty, nil, nil,
            nil, nil, nil,
            self.dst, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            nil, nil,
            dst_layout or self.dst_layout, nil, nil, nil,
            specialize_scalar_inputs(inputs, result_ty),
            point_class.expr,
            self.start, self.stop, self.start_expr, self.stop_expr,
            nil, nil, store_mode,
            "expr" .. tostring(#(inputs or {})),
            nil, nil, nil, nil
        )
    end

    local function indexed_layout(parent, idx, step_num)
        return Stencil.StencilLayoutIndexed(parent, access_ref(idx.name), idx.ty or idx.elem_ty, step_num or 1)
    end

    function SM.StencilMachineStoreSelectInput:select_store_stencil()
        local point_class = self.class
        if self.store_index_primary == true and (point_class.result_ty == nil or point_class.result_ty:stencil_same_type(self.dst_elem_ty))
            and point_class:all_inputs_primary() and (point_class.result_ty or self.dst_elem_ty):stencil_supported_type() and self.dst_elem_ty:stencil_supported_type() then
            return SM.StencilMachineSelectStoreN(self:store_n_info(), {})
        end
        if self.store_index_primary == true and (point_class.result_ty == nil or point_class.result_ty:stencil_same_type(self.dst_elem_ty))
            and (point_class.result_ty or self.dst_elem_ty):stencil_supported_type() and self.dst_elem_ty:stencil_supported_type() then
            local inputs, ok = copy_inputs(point_class.inputs), true
            for i, input in ipairs(inputs) do
                if input.index_primary ~= true then
                    local idx = input.index_lane
                    if idx == nil or not idx.ty:stencil_is_index_data_type() then ok = false; break end
                    inputs[i] = asdl.with(input, { layout = indexed_layout(input.layout, idx, self.step_num) })
                    append_input_once(inputs, idx)
                end
            end
            if ok then
                return SM.StencilMachineSelectStoreN(self:store_n_info(inputs, nil, nil), {})
            end
        end
        if self.store_index_lane ~= nil
            and (point_class.result_ty == nil or point_class.result_ty:stencil_same_type(self.dst_elem_ty)) and point_class:all_inputs_primary()
            and self.store_index_lane.elem_ty:stencil_is_index_data_type() and (point_class.result_ty or self.dst_elem_ty):stencil_supported_type() and self.dst_elem_ty:stencil_supported_type() then
            local idx = SM.StencilMachinePointInput(
                "dst_idx",
                nil,
                nil,
                nil,
                self.store_index_lane.base,
                self.store_index_lane.base_expr,
                self.store_index_lane.elem_ty,
                self.store_index_lane.elem_ty,
                self.store_index_lane.layout,
                Stencil.StencilAccessIndex,
                true,
                nil,
                {}
            )
            local inputs = copy_inputs(point_class.inputs)
            append_input_once(inputs, idx)
            return SM.StencilMachineSelectStoreN(
                self:store_n_info(
                    inputs,
                    indexed_layout(self.dst_layout, idx, self.step_num),
                    Stencil.StencilStoreScatter(self.scatter_conflicts or Stencil.StencilScatterUniqueIndices)
                ),
                {}
            )
        end
        return nil, "unsupported store stencil shape"
    end

    function SM.StencilMachineScanSelectInput:select_scan_stencil()
        local input = self.class:single_point_input()
        if input ~= nil and self.store_index_primary == true and input.index_primary == true
            and self.result_ty:stencil_same_type(self.dst_elem_ty)
            and self.result_ty:stencil_reduction_supported(self.reduction_kind, input.ty) then
            return SM.StencilMachineSelectScan(self.reduction, SM.StencilMachineSelectionInfo(
                self.step_num, self.producer,
                input.ty, self.result_ty, nil, nil,
                self.init, self.mode, self.axis,
                self.dst, input.base, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil,
                self.dst_layout, input.layout, nil, nil,
                {},
                nil,
                nil, nil, self.start_expr, self.stop_expr,
                nil, nil, nil, nil, nil, nil, nil, nil
            ), { self.dst_expr, input.base_expr, self.start_expr, self.stop_expr, self.init_expr })
        end
        return nil, "unsupported scan stencil shape"
    end

    function SM.StencilMachineFindSelectInput:select_find_stencil()
        local input = self.class:single_point_input()
        if input ~= nil and input.index_primary == true and self.not_found_minus_one == true and input.ty:stencil_supported_type() then
            return SM.StencilMachineSelectFind(self.pred, SM.StencilMachineSelectionInfo(
                self.step_num, self.producer,
                input.ty, nil, nil, nil,
                nil, nil, nil,
                nil, input.base, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil,
                nil, input.layout, nil, nil,
                {},
                nil,
                self.start, self.stop, self.start_expr, self.stop_expr,
                self.pred, nil, nil, nil, nil, nil, nil, nil
            ), { input.base_expr, self.start_expr, self.stop_expr })
        end
        return nil, "unsupported find stencil shape"
    end

    function SM.StencilMachinePartitionSelectInput:select_partition_stencil()
        local input = self.class:single_point_input()
        if input ~= nil and self.store_index_primary == true and input.index_primary == true
            and input.ty:stencil_same_type(self.dst_elem_ty) and input.ty:stencil_supported_type() and self.dst_elem_ty:stencil_supported_type() then
            return SM.StencilMachineSelectPartition(self.pred, SM.StencilMachineSelectionInfo(
                self.step_num, self.producer,
                input.ty, nil, nil, nil,
                nil, nil, nil,
                self.dst, input.base, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil,
                self.dst_layout, input.layout, nil, nil,
                {},
                nil,
                self.start, self.stop, self.start_expr, self.stop_expr,
                self.pred, self.semantics, nil, nil, nil, nil, nil, nil
            ), { self.dst_expr, input.base_expr, self.start_expr, self.stop_expr })
        end
        return nil, "unsupported partition stencil shape"
    end

    function SM.StencilMachineReduceSelectInput:select_reduce_stencil()
        local point_class = self.class
        if point_class:all_inputs_primary()
            and self.result_ty:stencil_reduction_supported(self.reduction_kind, point_class.result_ty) then
            return SM.StencilMachineSelectReduceN(SM.StencilMachineSelectionInfo(
                self.step_num, self.producer,
                nil, self.result_ty, point_class.result_ty, nil,
                self.init, nil, nil,
                nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil,
                nil, nil, nil, nil,
                point_class.inputs,
                point_class.expr,
                nil, nil, self.start_expr, self.stop_expr,
                nil, nil, nil,
                "expr" .. tostring(#(point_class.inputs or {})),
                nil, nil, nil, nil
            ), {})
        end
        local pred_input, pred = point_class.expr:stencil_predicate_operand(point_class)
        if pred_input ~= nil and pred_input.index_primary == true and self.reduction_add == true
            and self.init_zero == true and self.result_i32 == true then
            return SM.StencilMachineSelectCount(pred, SM.StencilMachineSelectionInfo(
                self.step_num, self.producer,
                pred_input.ty, self.result_ty, nil, nil,
                self.init, nil, nil,
                nil, pred_input.base, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                nil, nil,
                nil, pred_input.layout, nil, nil,
                {},
                nil,
                nil, nil, self.start_expr, self.stop_expr,
                pred, nil, nil, nil, nil, nil, nil, nil
            ), { pred_input.base_expr, self.start_expr, self.stop_expr })
        end
        return nil, "unsupported reduction stencil contribution"
    end

    function SM.StencilMachineStorePlanInput:reject_reason(suffix)
        return ("store stencil is not ready: planned=%s returns_void=%s counted_positive=%s single_store=%s dst_base_present=%s class_ready=%s (%s)"):format(
            tostring(self.planned), tostring(self.returns_void), tostring(self.counted_positive),
            tostring(self.single_store), tostring(self.dst_base_present), tostring(self.class_ready),
            tostring(suffix or "no matching plan")
        )
    end

    function SM.StencilMachineReducePlanInput:reject_reason(suffix)
        return ("reduction stencil is not ready: planned=%s result_reduction=%s returns_reduction=%s counted_positive=%s class_ready=%s (%s)"):format(
            tostring(self.planned), tostring(self.result_reduction), tostring(self.returns_reduction),
            tostring(self.counted_positive), tostring(self.class_ready), tostring(suffix or "no matching plan")
        )
    end

    local api = {}

    function SM.StencilMachineSelected:stencil_artifact_kind() return nil end
    function SM.StencilMachineSelected:stencil_artifact_op() return nil end
    function SM.StencilMachineSelected:stencil_artifact_info() return self.info end
    function SM.StencilMachineSelected:stencil_artifact_args() return self.args end

    function SM.StencilMachineSelectStoreN:stencil_artifact_kind() return "store_n" end
    function SM.StencilMachineSelectReduceN:stencil_artifact_kind() return "reduce_n" end
    function SM.StencilMachineSelectScan:stencil_artifact_kind() return "scan" end
    function SM.StencilMachineSelectFind:stencil_artifact_kind() return "find" end
    function SM.StencilMachineSelectPartition:stencil_artifact_kind() return "partition" end
    function SM.StencilMachineSelectCount:stencil_artifact_kind() return "count" end
    function SM.StencilMachineSelectScatterReduce:stencil_artifact_kind() return "scatter_reduce" end

    function SM.StencilMachineSelectFind:stencil_artifact_op() return self.op end
    function SM.StencilMachineSelectPartition:stencil_artifact_op() return self.op end
    function SM.StencilMachineSelectCount:stencil_artifact_op() return self.op end

    function api.classify_expr(expr, bindings)
        local fact, err = api.expr_fact(expr, bindings or SM.StencilMachineExprBindings({}))
        if fact == nil then return nil, err end
        local class = classify_expr(fact)
        if class == nil then return nil, "unsupported store stencil expression" end
        return class
    end

    function api.select_index_lane(class)
        local lane = class:select_index_lane()
        return lane or nil, lane == nil and "expression is not an index lane" or nil
    end

    function api.select_store_stencil(input)
        return input:select_store_stencil()
    end

    function api.select_scan_stencil(input)
        return input:select_scan_stencil()
    end

    function api.select_find_stencil(input)
        return input:select_find_stencil()
    end

    function api.select_partition_stencil(input)
        return input:select_partition_stencil()
    end

    function api.select_reduce_stencil(input)
        return input:select_reduce_stencil()
    end

    function SM.StencilMachineStorePlanInput:plan_store_stencil()
        local plan_ready = self.planned == true
            and self.returns_void == true
            and self.counted_positive == true
            and self.single_store == true
            and self.dst_base_present == true
            and self.class_ready == true
        if not plan_ready then return nil, self:reject_reason() end
        local selected, err = self.selection:select_store_stencil()
        if selected == nil then return nil, self:reject_reason(err) end
        return SM.StencilMachineStorePlan(selected), nil
    end

    function api.plan_store(input)
        return input:plan_store_stencil()
    end

    function SM.StencilMachineReducePlanInput:plan_reduce_stencil()
        local plan_ready = self.planned == true
            and self.result_reduction == true
            and self.returns_reduction == true
            and self.counted_positive == true
            and self.class_ready == true
        if not plan_ready then return nil, self:reject_reason() end
        local selected, err = self.selection:select_reduce_stencil()
        if selected == nil then return nil, self:reject_reason(err) end
        return SM.StencilMachineReducePlan(self.reduction, selected), nil
    end

    function api.plan_reduce(input)
        return input:plan_reduce_stencil()
    end

    function api.expr_fact(expr, bindings)
        return SM.StencilMachineExprFactInput(expr, bindings or SM.StencilMachineExprBindings({}), {}):fact_for_expr(expr)
    end

    T._lalin_api_cache.stencil_methods = api
    return api
end

return bind_context
