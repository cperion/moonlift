return function(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local function i32_ty() return Ty.TScalar(C.ScalarI32) end
    local function f64_ty() return Ty.TScalar(C.ScalarF64) end
    local function u8_ty() return Ty.TScalar(C.ScalarU8) end
    local function void_ty() return Ty.TScalar(C.ScalarVoid) end

    local function type_eq(a, b)
        if a == b then return true end
        if a == nil or b == nil then return false end
        return tostring(a) == tostring(b)
    end

    function C.Scalar:typecheck_tree_is_bool() return false end
    function C.ScalarBool:typecheck_tree_is_bool() return true end

    function C.Scalar:typecheck_tree_is_integer_scalar() return false end
    function C.ScalarI8:typecheck_tree_is_integer_scalar() return true end
    function C.ScalarI16:typecheck_tree_is_integer_scalar() return true end
    function C.ScalarI32:typecheck_tree_is_integer_scalar() return true end
    function C.ScalarI64:typecheck_tree_is_integer_scalar() return true end
    function C.ScalarU8:typecheck_tree_is_integer_scalar() return true end
    function C.ScalarU16:typecheck_tree_is_integer_scalar() return true end
    function C.ScalarU32:typecheck_tree_is_integer_scalar() return true end
    function C.ScalarU64:typecheck_tree_is_integer_scalar() return true end
    function C.ScalarIndex:typecheck_tree_is_integer_scalar() return true end

    function C.Scalar:typecheck_tree_is_float_scalar() return false end
    function C.ScalarF32:typecheck_tree_is_float_scalar() return true end
    function C.ScalarF64:typecheck_tree_is_float_scalar() return true end

    function C.Scalar:typecheck_tree_is_numeric_scalar()
        return self:typecheck_tree_is_integer_scalar() or self:typecheck_tree_is_float_scalar()
    end

    function C.Scalar:typecheck_tree_is_void_scalar() return false end
    function C.ScalarVoid:typecheck_tree_is_void_scalar() return true end

    function Ty.Type:typecheck_tree_is_bool() return false end
    function Ty.TScalar:typecheck_tree_is_bool() return self.scalar:typecheck_tree_is_bool() end
    function Ty.Type:typecheck_tree_is_integer_scalar() return false end
    function Ty.TScalar:typecheck_tree_is_integer_scalar() return self.scalar:typecheck_tree_is_integer_scalar() end
    function Ty.Type:typecheck_tree_is_float_scalar() return false end
    function Ty.TScalar:typecheck_tree_is_float_scalar() return self.scalar:typecheck_tree_is_float_scalar() end
    function Ty.Type:typecheck_tree_is_numeric_scalar() return false end
    function Ty.TScalar:typecheck_tree_is_numeric_scalar() return self.scalar:typecheck_tree_is_numeric_scalar() end

    function Ty.Type:typecheck_tree_is_atomic_value_type() return false end
    function Ty.TScalar:typecheck_tree_is_atomic_value_type()
        return self:typecheck_tree_is_integer_scalar() or self:typecheck_tree_is_bool()
    end
    function Ty.TPtr:typecheck_tree_is_atomic_value_type() return true end

    function Ty.Type:typecheck_tree_rejects_atomic_rmw_arithmetic() return false end
    function Ty.TPtr:typecheck_tree_rejects_atomic_rmw_arithmetic() return true end

    function Ty.Type:typecheck_tree_callable_result() return nil, nil end
    function Ty.TFunc:typecheck_tree_callable_result() return self.result, self.params end
    function Ty.TClosure:typecheck_tree_callable_result() return self.result, self.params end

    function Ty.Type:typecheck_tree_bin_add(rhs_ty) return nil end
    function Ty.Type:typecheck_tree_bin_add_integer_lhs(lhs_ty) return nil end
    function Ty.TPtr:typecheck_tree_bin_add(rhs_ty)
        if rhs_ty:typecheck_tree_is_integer_scalar() then return self end
        return nil
    end
    function Ty.TPtr:typecheck_tree_bin_add_integer_lhs(lhs_ty) return self end
    function Ty.TScalar:typecheck_tree_bin_add(rhs_ty)
        if self:typecheck_tree_is_integer_scalar() then return rhs_ty:typecheck_tree_bin_add_integer_lhs(self) end
        return nil
    end
    function Ty.Type:typecheck_tree_bin_sub(rhs_ty) return nil end
    function Ty.TPtr:typecheck_tree_bin_sub(rhs_ty)
        if rhs_ty:typecheck_tree_is_integer_scalar() then return self end
        return nil
    end

    function Ty.Type:typecheck_tree_same_binary_result(rhs_ty) return nil end
    function Ty.TScalar:typecheck_tree_same_binary_result(rhs_ty)
        if type_eq(self, rhs_ty) and (self:typecheck_tree_is_numeric_scalar() or self:typecheck_tree_is_integer_scalar()) then return self end
        if self:typecheck_tree_is_integer_scalar() and rhs_ty:typecheck_tree_is_integer_scalar() then return self end
        return nil
    end

    function Ty.Type:typecheck_tree_same_integer_binary_result(rhs_ty) return nil end
    function Ty.TScalar:typecheck_tree_same_integer_binary_result(rhs_ty)
        if self:typecheck_tree_is_integer_scalar() and rhs_ty:typecheck_tree_is_integer_scalar() then return self end
        return nil
    end

    function C.BinaryOp:typecheck_tree_binary_result(lhs_ty, rhs_ty) return lhs_ty:typecheck_tree_same_binary_result(rhs_ty) end
    function C.BinaryOp:typecheck_tree_binary_rhs(expr, input, lhs_ty)
        return expr:typecheck_tree_expr(input)
    end
    function C.BinAdd:typecheck_tree_binary_result(lhs_ty, rhs_ty)
        return lhs_ty:typecheck_tree_bin_add(rhs_ty) or lhs_ty:typecheck_tree_same_binary_result(rhs_ty)
    end
    function C.BinAdd:typecheck_tree_binary_rhs(expr, input, lhs_ty)
        if lhs_ty:typecheck_tree_is_integer_scalar() then
            return expr:typecheck_tree_expr_expected(Tr.TypeExpectedExprInput(input.scope, lhs_ty))
        end
        return expr:typecheck_tree_expr(input)
    end
    function C.BinSub:typecheck_tree_binary_result(lhs_ty, rhs_ty)
        return lhs_ty:typecheck_tree_bin_sub(rhs_ty) or lhs_ty:typecheck_tree_same_binary_result(rhs_ty)
    end
    function C.BinSub:typecheck_tree_binary_rhs(expr, input, lhs_ty)
        if lhs_ty:typecheck_tree_is_integer_scalar() then
            return expr:typecheck_tree_expr_expected(Tr.TypeExpectedExprInput(input.scope, lhs_ty))
        end
        return expr:typecheck_tree_expr(input)
    end
    function C.BinBitAnd:typecheck_tree_binary_result(lhs_ty, rhs_ty) return lhs_ty:typecheck_tree_same_integer_binary_result(rhs_ty) end
    function C.BinBitOr:typecheck_tree_binary_result(lhs_ty, rhs_ty) return lhs_ty:typecheck_tree_same_integer_binary_result(rhs_ty) end
    function C.BinBitXor:typecheck_tree_binary_result(lhs_ty, rhs_ty) return lhs_ty:typecheck_tree_same_integer_binary_result(rhs_ty) end
    function C.BinShl:typecheck_tree_binary_result(lhs_ty, rhs_ty) return lhs_ty:typecheck_tree_same_integer_binary_result(rhs_ty) end
    function C.BinLShr:typecheck_tree_binary_result(lhs_ty, rhs_ty) return lhs_ty:typecheck_tree_same_integer_binary_result(rhs_ty) end
    function C.BinAShr:typecheck_tree_binary_result(lhs_ty, rhs_ty) return lhs_ty:typecheck_tree_same_integer_binary_result(rhs_ty) end

    function C.LogicOp:typecheck_tree_logic_result(lhs_ty, rhs_ty) return nil end
    function C.LogicAnd:typecheck_tree_logic_result(lhs_ty, rhs_ty)
        if lhs_ty:typecheck_tree_is_bool() and rhs_ty:typecheck_tree_is_bool() then return Ty.TScalar(C.ScalarBool) end
        return nil
    end
    function C.LogicOr:typecheck_tree_logic_result(lhs_ty, rhs_ty)
        if lhs_ty:typecheck_tree_is_bool() and rhs_ty:typecheck_tree_is_bool() then return Ty.TScalar(C.ScalarBool) end
        return nil
    end

    function C.UnaryOp:typecheck_tree_unary_result() return nil end
    function C.UnaryNot:typecheck_tree_unary_result(value_ty) return value_ty:typecheck_tree_unary_not_result() end
    function C.UnaryNeg:typecheck_tree_unary_result(value_ty) return value_ty:typecheck_tree_unary_neg_result() end
    function C.UnaryBitNot:typecheck_tree_unary_result(value_ty) return value_ty:typecheck_tree_unary_bitnot_result() end

    function Ty.Type:typecheck_tree_unary_not_result() return nil end
    function Ty.TScalar:typecheck_tree_unary_not_result()
        if self:typecheck_tree_is_bool() then return Ty.TScalar(C.ScalarBool) end
        return nil
    end

    function Ty.Type:typecheck_tree_unary_neg_result() return nil end
    function Ty.TScalar:typecheck_tree_unary_neg_result()
        if self:typecheck_tree_is_numeric_scalar() then return self end
        return nil
    end

    function Ty.Type:typecheck_tree_unary_bitnot_result() return nil end
    function Ty.TScalar:typecheck_tree_unary_bitnot_result()
        if self:typecheck_tree_is_integer_scalar() then return self end
        return nil
    end

    function Ty.Type:typecheck_tree_deref_result() return nil end
    function Ty.TPtr:typecheck_tree_deref_result() return self.elem end

    function Ty.Type:typecheck_tree_len_result() return nil end
    function Ty.TArray:typecheck_tree_len_result() return Ty.TScalar(C.ScalarIndex) end
    function Ty.TSlice:typecheck_tree_len_result() return Ty.TScalar(C.ScalarIndex) end
    function Ty.TView:typecheck_tree_len_result() return Ty.TScalar(C.ScalarIndex) end

    function Ty.Type:typecheck_tree_index_elem() return nil end
    function Ty.TPtr:typecheck_tree_index_elem() return self.elem end
    function Ty.TArray:typecheck_tree_index_elem() return self.elem end
    function Ty.TSlice:typecheck_tree_index_elem() return self.elem end
    function Ty.TView:typecheck_tree_index_elem() return self.elem end

    function Ty.TypeRef:typecheck_tree_resolve_env_type(env)
        return nil
    end

    function Ty.TypeRefPath:typecheck_tree_resolve_env_type(env)
        if self.path == nil or #self.path.parts < 1 then return nil end
        local name = self.path.parts[#self.path.parts].text
        for i = #env.types, 1, -1 do
            if env.types[i].name == name then return env.types[i].ty end
        end
        return nil
    end

    function Ty.Type:typecheck_tree_canonical(env)
        return self
    end

    function Ty.TNamed:typecheck_tree_canonical(env)
        return self.ref:typecheck_tree_resolve_env_type(env) or self
    end

    function Ty.THandle:typecheck_tree_canonical(env)
        local found = self.ref:typecheck_tree_resolve_env_type(env)
        if found ~= nil and found:typecheck_tree_is_handle_type() then return found end
        return self
    end

    function Ty.TPtr:typecheck_tree_canonical(env)
        return Ty.TPtr(self.elem:typecheck_tree_canonical(env))
    end

    function Ty.TArray:typecheck_tree_canonical(env)
        return Ty.TArray(self.count, self.elem:typecheck_tree_canonical(env))
    end

    function Ty.TSlice:typecheck_tree_canonical(env)
        return Ty.TSlice(self.elem:typecheck_tree_canonical(env))
    end

    function Ty.TView:typecheck_tree_canonical(env)
        return Ty.TView(self.elem:typecheck_tree_canonical(env))
    end

    function Ty.TLease:typecheck_tree_canonical(env)
        return Ty.TLease(self.base:typecheck_tree_canonical(env), self.origin)
    end

    function Ty.TOwned:typecheck_tree_canonical(env)
        return Ty.TOwned(self.base:typecheck_tree_canonical(env))
    end

    function Ty.TAccess:typecheck_tree_canonical(env)
        return Ty.TAccess(self.access, self.base:typecheck_tree_canonical(env))
    end

    function Ty.TFunc:typecheck_tree_canonical(env)
        local params = {}
        for i = 1, #(self.params or {}) do params[i] = self.params[i]:typecheck_tree_canonical(env) end
        return Ty.TFunc(params, self.result:typecheck_tree_canonical(env))
    end

    function Ty.TClosure:typecheck_tree_canonical(env)
        local params = {}
        for i = 1, #(self.params or {}) do params[i] = self.params[i]:typecheck_tree_canonical(env) end
        return Ty.TClosure(params, self.result:typecheck_tree_canonical(env))
    end

    function Ty.Type:typecheck_tree_is_owned_type() return false end
    function Ty.TOwned:typecheck_tree_is_owned_type() return true end

    function Ty.Type:typecheck_tree_contains_lease() return false end
    function Ty.TLease:typecheck_tree_contains_lease() return true end
    function Ty.TOwned:typecheck_tree_contains_lease() return self.base:typecheck_tree_contains_lease() end
    function Ty.TAccess:typecheck_tree_contains_lease() return self.base:typecheck_tree_contains_lease() end
    function Ty.TPtr:typecheck_tree_contains_lease() return self.elem:typecheck_tree_contains_lease() end
    function Ty.TArray:typecheck_tree_contains_lease() return self.elem:typecheck_tree_contains_lease() end
    function Ty.TSlice:typecheck_tree_contains_lease() return self.elem:typecheck_tree_contains_lease() end
    function Ty.TView:typecheck_tree_contains_lease() return self.elem:typecheck_tree_contains_lease() end
    function Ty.TFunc:typecheck_tree_contains_lease()
        if self.result:typecheck_tree_contains_lease() then return true end
        for i = 1, #self.params do if self.params[i]:typecheck_tree_contains_lease() then return true end end
        return false
    end
    function Ty.TClosure:typecheck_tree_contains_lease()
        if self.result:typecheck_tree_contains_lease() then return true end
        for i = 1, #self.params do if self.params[i]:typecheck_tree_contains_lease() then return true end end
        return false
    end

    function Ty.Type:typecheck_tree_contains_owned() return false end
    function Ty.TOwned:typecheck_tree_contains_owned() return true end
    function Ty.TLease:typecheck_tree_contains_owned() return self.base:typecheck_tree_contains_owned() end
    function Ty.TAccess:typecheck_tree_contains_owned() return self.base:typecheck_tree_contains_owned() end
    function Ty.TPtr:typecheck_tree_contains_owned() return self.elem:typecheck_tree_contains_owned() end
    function Ty.TArray:typecheck_tree_contains_owned() return self.elem:typecheck_tree_contains_owned() end
    function Ty.TSlice:typecheck_tree_contains_owned() return self.elem:typecheck_tree_contains_owned() end
    function Ty.TView:typecheck_tree_contains_owned() return self.elem:typecheck_tree_contains_owned() end
    function Ty.TFunc:typecheck_tree_contains_owned()
        if self.result:typecheck_tree_contains_owned() then return true end
        for i = 1, #self.params do if self.params[i]:typecheck_tree_contains_owned() then return true end end
        return false
    end
    function Ty.TClosure:typecheck_tree_contains_owned()
        if self.result:typecheck_tree_contains_owned() then return true end
        for i = 1, #self.params do if self.params[i]:typecheck_tree_contains_owned() then return true end end
        return false
    end

    function Ty.Type:typecheck_tree_lease_access_base() return self end
    function Ty.TLease:typecheck_tree_lease_access_base() return self.base end
    function Ty.TAccess:typecheck_tree_lease_access_base() return self.base:typecheck_tree_lease_access_base() end

    function Ty.Type:typecheck_tree_named_ref() return nil end
    function Ty.TNamed:typecheck_tree_named_ref() return self.ref end
    function Ty.Type:typecheck_tree_nominal_ref() return nil end
    function Ty.TNamed:typecheck_tree_nominal_ref() return self.ref end
    function Ty.THandle:typecheck_tree_nominal_ref() return self.ref end

    function Ty.TypeRef:typecheck_tree_ref_text() return nil end
    function Ty.TypeRefGlobal:typecheck_tree_ref_text() return self.type_name end
    function Ty.TypeRefLocal:typecheck_tree_ref_text()
        return self.sym and self.sym.name or tostring(self.sym)
    end
    function Ty.TypeRefPath:typecheck_tree_ref_text()
        if self.path == nil or #self.path.parts == 0 then return nil end
        local parts = {}
        for i = 1, #self.path.parts do parts[i] = self.path.parts[i].text end
        return table.concat(parts, ".")
    end

    function Ty.TypeRef:typecheck_tree_ref_leaf()
        local text = self:typecheck_tree_ref_text()
        if text == nil then return nil end
        return text:match("([^%.]+)$") or text
    end

    function Ty.Type:typecheck_tree_matches_type_ref(ref)
        local ty_ref = self:typecheck_tree_nominal_ref()
        if ty_ref == nil then return false end
        local a, b = ref:typecheck_tree_ref_leaf(), ty_ref:typecheck_tree_ref_leaf()
        return a ~= nil and b ~= nil and a == b
    end

    local function find_variant_def(facts, name)
        for i = 1, #((facts and facts.variants) or {}) do
            if facts.variants[i].type_name == name then return facts.variants[i] end
        end
        return nil
    end

    local function find_handle_def(facts, name)
        for i = 1, #((facts and facts.handles) or {}) do
            if facts.handles[i].name == name then return facts.handles[i] end
        end
        return nil
    end

    function Ty.Type:typecheck_tree_variant_def(facts)
        return nil
    end

    function Ty.TNamed:typecheck_tree_variant_def(facts)
        return self.ref:typecheck_tree_ref_variant_def(facts)
    end

    function Ty.TypeRef:typecheck_tree_ref_variant_def(facts) return nil end
    function Ty.TypeRefGlobal:typecheck_tree_ref_variant_def(facts) return find_variant_def(facts, self.type_name) end
    function Ty.TypeRefLocal:typecheck_tree_ref_variant_def(facts) return find_variant_def(facts, self.sym.name) end
    function Ty.TypeRefPath:typecheck_tree_ref_variant_def(facts)
        if #self.path.parts == 1 then return find_variant_def(facts, self.path.parts[1].text) end
        return nil
    end

    function Ty.Type:typecheck_tree_handle_def(facts)
        return nil
    end

    function Ty.TOwned:typecheck_tree_handle_def(facts)
        return self.base:typecheck_tree_handle_def(facts)
    end

    function Ty.THandle:typecheck_tree_handle_def(facts)
        return self.ref:typecheck_tree_ref_handle_def(facts)
    end

    function Ty.TypeRef:typecheck_tree_ref_handle_def(facts) return nil end
    function Ty.TypeRefGlobal:typecheck_tree_ref_handle_def(facts) return find_handle_def(facts, self.type_name) end
    function Ty.TypeRefLocal:typecheck_tree_ref_handle_def(facts) return find_handle_def(facts, self.sym.name) end
    function Ty.TypeRefPath:typecheck_tree_ref_handle_def(facts)
        if #self.path.parts == 1 then return find_handle_def(facts, self:typecheck_tree_ref_leaf()) end
        return nil
    end

    function Ty.Type:typecheck_tree_is_void_type() return false end
    function Ty.TScalar:typecheck_tree_is_void_type() return self.scalar:typecheck_tree_is_void_scalar() end
    function Ty.Type:typecheck_tree_is_handle_type() return false end
    function Ty.THandle:typecheck_tree_is_handle_type() return true end

    function Ty.HandleRepr:typecheck_tree_repr_type() return nil end
    function Ty.HandleReprScalar:typecheck_tree_repr_type() return Ty.TScalar(self.scalar) end
    function Ty.HandleRepr:typecheck_tree_check_handle_decl(type_name, issues)
        issues[#issues + 1] = Tr.TypeIssueExpected("handle repr", Ty.THandle(Ty.TypeRefPath(C.Path({ C.Name(type_name) })), Ty.HandleReprScalar(C.ScalarU32)), Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(type_name) }))))
    end
    function Ty.HandleReprScalar:typecheck_tree_check_handle_decl(type_name, issues) end
    function Ty.Type:typecheck_tree_handle_repr_type() return nil end
    function Ty.TOwned:typecheck_tree_handle_repr_type() return self.base:typecheck_tree_handle_repr_type() end
    function Ty.THandle:typecheck_tree_handle_repr_type() return self.repr:typecheck_tree_repr_type() end

    function Ty.ArrayLen:typecheck_tree_check_policy(array_ty, issues, site) end
    function Ty.ArrayLenExpr:typecheck_tree_check_policy(array_ty, issues, site)
        issues[#issues + 1] = Tr.TypeIssueExpected((site or "type") .. " array length", Ty.TArray(Ty.ArrayLenConst(0), array_ty.elem), array_ty)
    end

    function Ty.Type:typecheck_tree_valid_lease_base() return false end
    function Ty.TPtr:typecheck_tree_valid_lease_base() return true end
    function Ty.TView:typecheck_tree_valid_lease_base() return true end

    function Ty.Type:typecheck_tree_valid_owned_base() return true end
    function Ty.TOwned:typecheck_tree_valid_owned_base() return false end
    function Ty.TLease:typecheck_tree_valid_owned_base() return false end
    function Ty.TAccess:typecheck_tree_valid_owned_base() return false end
    function Ty.TPtr:typecheck_tree_valid_owned_base() return false end
    function Ty.TView:typecheck_tree_valid_owned_base() return false end

    function Ty.HandleRepr:typecheck_tree_check_policy(handle_ty, issues, site)
        issues[#issues + 1] = Tr.TypeIssueExpected((site or "type") .. " handle repr", Ty.THandle(handle_ty.ref, Ty.HandleReprScalar(C.ScalarU32)), handle_ty)
    end
    function Ty.HandleReprScalar:typecheck_tree_check_policy(handle_ty, issues, site) end

    function Ty.Type:typecheck_tree_check_policy(issues, site) end
    function Ty.TArray:typecheck_tree_check_policy(issues, site)
        self.count:typecheck_tree_check_policy(self, issues, site)
        self.elem:typecheck_tree_check_policy(issues, site)
    end
    function Ty.TPtr:typecheck_tree_check_policy(issues, site)
        self.elem:typecheck_tree_check_policy(issues, site)
    end
    function Ty.TSlice:typecheck_tree_check_policy(issues, site)
        self.elem:typecheck_tree_check_policy(issues, site)
    end
    function Ty.TView:typecheck_tree_check_policy(issues, site)
        self.elem:typecheck_tree_check_policy(issues, site)
    end
    function Ty.TLease:typecheck_tree_check_policy(issues, site)
        self.base:typecheck_tree_check_policy(issues, site)
        if not self.base:typecheck_tree_valid_lease_base() then
            issues[#issues + 1] = Tr.TypeIssueExpected((site or "type") .. " lease base", Ty.TPtr(Ty.TScalar(C.ScalarVoid)), self.base)
        end
        if self.base:typecheck_tree_contains_owned() then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryOwnedInvalidComposition, self) end
    end
    function Ty.TOwned:typecheck_tree_check_policy(issues, site)
        self.base:typecheck_tree_check_policy(issues, site)
        if not self.base:typecheck_tree_valid_owned_base() then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryOwnedInvalidComposition, self) end
        if self.base:typecheck_tree_contains_lease() then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryOwnedInvalidComposition, self) end
    end
    function Ty.TAccess:typecheck_tree_check_policy(issues, site)
        self.base:typecheck_tree_check_policy(issues, site)
        if self.base:typecheck_tree_contains_owned() then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryOwnedInvalidComposition, self) end
    end
    function Ty.THandle:typecheck_tree_check_policy(issues, site)
        self.repr:typecheck_tree_check_policy(self, issues, site)
    end
    function Ty.TFunc:typecheck_tree_check_policy(issues, site)
        for i = 1, #self.params do self.params[i]:typecheck_tree_check_policy(issues, site) end
        self.result:typecheck_tree_check_policy(issues, site)
    end
    function Ty.TClosure:typecheck_tree_check_policy(issues, site)
        for i = 1, #self.params do self.params[i]:typecheck_tree_check_policy(issues, site) end
        self.result:typecheck_tree_check_policy(issues, site)
    end

    function Ty.ArrayLen:typecheck_tree_const_count() return nil end
    function Ty.ArrayLenConst:typecheck_tree_const_count() return self.count end

    function Ty.Type:typecheck_tree_append_live_lease(out) end
    function Ty.TLease:typecheck_tree_append_live_lease(out) out[#out + 1] = self end

    function Ty.Type:typecheck_tree_lease_target_type() return nil end
    function Ty.TAccess:typecheck_tree_lease_target_type() return self.base:typecheck_tree_lease_target_type() end
    function Ty.TLease:typecheck_tree_lease_target_type() return self.base:typecheck_tree_lease_base_target_type() end
    function Ty.Type:typecheck_tree_lease_base_target_type() return nil end
    function Ty.TAccess:typecheck_tree_lease_base_target_type() return self.base:typecheck_tree_lease_base_target_type() end
    function Ty.TPtr:typecheck_tree_lease_base_target_type() return self.elem end
    function Ty.TView:typecheck_tree_lease_base_target_type() return self.elem end

    function Ty.Type:typecheck_tree_domain_match_elem() return nil end
    function Ty.TAccess:typecheck_tree_domain_match_elem() return self.base:typecheck_tree_domain_match_elem() end
    function Ty.TPtr:typecheck_tree_domain_match_elem() return self.elem end
    function Ty.TView:typecheck_tree_domain_match_elem() return self.elem end

    function Ty.Type:typecheck_tree_call_may_invalidate_live_lease_param() return false end
    function Ty.TPtr:typecheck_tree_call_may_invalidate_live_lease_param() return true end
    function Ty.TView:typecheck_tree_call_may_invalidate_live_lease_param() return true end

    function Ty.LeaseOrigin:typecheck_tree_origin_name() return nil end
    function Ty.LeaseOriginParam:typecheck_tree_origin_name() return self.name end
    function Ty.Type:typecheck_tree_lease_origin_name() return nil end
    function Ty.TLease:typecheck_tree_lease_origin_name() return self.origin:typecheck_tree_origin_name() end

    function Ty.Type:typecheck_tree_lease_payload_info() return nil end
    function Ty.TAccess:typecheck_tree_lease_payload_info() return self.base:typecheck_tree_lease_payload_info() end
    function Ty.TLease:typecheck_tree_lease_payload_info()
        local target = self:typecheck_tree_lease_target_type()
        if target == nil then return nil end
        return { lease = self, target = target, origin = self:typecheck_tree_lease_origin_name() }
    end

    function Ty.TypeAccess:typecheck_tree_allows_lease_grant() return nil end
    function Ty.TypeAccessReadonly:typecheck_tree_allows_lease_grant() return true end
    function Ty.TypeAccessPreserve:typecheck_tree_allows_lease_grant() return true end
    function Ty.TypeAccessInvalidate:typecheck_tree_allows_lease_grant() return false end
    function Ty.TypeAccessWriteonly:typecheck_tree_allows_lease_grant() return false end

    function Ty.Type:typecheck_tree_access_allows_lease_grant() return false end
    function Ty.TAccess:typecheck_tree_access_allows_lease_grant()
        local decision = self.access:typecheck_tree_allows_lease_grant()
        if decision ~= nil then return decision end
        return self.base:typecheck_tree_access_allows_lease_grant()
    end

    function Ty.Type:typecheck_tree_arg_as_actual_for_expected(env, expected) return false end
    function Ty.TAccess:typecheck_tree_arg_as_actual_for_expected(env, expected)
        return expected:typecheck_tree_arg_matches_actual(env, self.base)
    end
    function Ty.Type:typecheck_tree_arg_as_actual_for_lease_expected(env, expected_lease)
        return type_eq(expected_lease.base, self)
    end
    function Ty.TLease:typecheck_tree_arg_as_actual_for_lease_expected(env, expected_lease)
        return type_eq(expected_lease.base, self.base)
    end
    function Ty.Type:typecheck_tree_arg_matches_actual(env, actual)
        return actual:typecheck_tree_arg_as_actual_for_expected(env, self)
    end
    function Ty.TAccess:typecheck_tree_arg_matches_actual(env, actual)
        return self.base:typecheck_tree_arg_matches_actual(env, actual)
    end
    function Ty.TLease:typecheck_tree_arg_matches_actual(env, actual)
        return actual:typecheck_tree_arg_as_actual_for_lease_expected(env, self)
    end

    function C.LitInt:typecheck_tree_literal() return i32_ty() end
    function C.LitFloat:typecheck_tree_literal() return f64_ty() end
    function C.LitBool:typecheck_tree_literal() return Ty.TScalar(C.ScalarBool) end
    function C.LitString:typecheck_tree_literal() return Ty.TSlice(u8_ty()) end
    function C.LitNil:typecheck_tree_literal() return void_ty() end

    function C.LitInt:typecheck_tree_literal_expected(expected)
        if expected ~= nil and expected:typecheck_tree_is_integer_scalar() then return expected end
        return self:typecheck_tree_literal()
    end
    function C.LitFloat:typecheck_tree_literal_expected(expected)
        if expected ~= nil and expected:typecheck_tree_is_float_scalar() then return expected end
        return self:typecheck_tree_literal()
    end
    function C.LitString:typecheck_tree_literal_expected(expected)
        if expected ~= nil and expected:typecheck_tree_accept_string_literal() then return expected end
        return self:typecheck_tree_literal()
    end
    function C.LitNil:typecheck_tree_literal_expected(expected)
        if expected ~= nil and expected:typecheck_tree_accept_nil_literal() then return expected end
        return self:typecheck_tree_literal()
    end
    function C.Literal:typecheck_tree_literal_expected(expected)
        if expected ~= nil
            and self:typecheck_tree_literal():typecheck_tree_is_integer_scalar()
            and expected:typecheck_tree_is_integer_scalar()
        then
            return expected
        end
        return self:typecheck_tree_literal()
    end

    function T.LalinTree.ModuleHeader:typecheck_tree_is_typed_module() return false end
    function T.LalinTree.ModuleTyped:typecheck_tree_is_typed_module() return true end
    function T.LalinTree.ExprHeader:typecheck_tree_is_typed_expr() return false end
    function T.LalinTree.ExprTyped:typecheck_tree_is_typed_expr() return true end
    function T.LalinTree.TypeIssue:typecheck_tree_is_array_length_expected() return false end
    function T.LalinTree.TypeIssueExpected:typecheck_tree_is_array_length_expected()
        return self.site ~= nil and self.site:match("array length") ~= nil
    end

    function Ty.Type:typecheck_tree_accept_string_literal() return false end
    function Ty.TSlice:typecheck_tree_accept_string_literal() return type_eq(self.elem, u8_ty()) end
    function Ty.Type:typecheck_tree_accept_nil_literal() return false end
    function Ty.TPtr:typecheck_tree_accept_nil_literal() return true end
end
