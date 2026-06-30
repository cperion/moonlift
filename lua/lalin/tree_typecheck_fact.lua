return function(T)
    local C = T.LalinCore
    local B = T.LalinBind
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local function void_ty()
        return Ty.TScalar(C.ScalarVoid)
    end

    local function variant_name_text(v)
        return v and (v.text or v.name) or tostring(v)
    end

    local function append_all(out, values)
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    end

    local function clone_values(values)
        local out = {}
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
        return out
    end

    function Tr.TypeValueScope:typecheck_tree_add_value(entry)
        local values = clone_values(self.values)
        values[#values + 1] = entry
        return Tr.TypeValueScope(self.module_name, values, self.types, self.layouts, self.facts)
    end

    function Tr.TypeValueScope:typecheck_tree_add_params(scope_name, params)
        local scope = self
        for i = 1, #(params or {}) do
            local p = params[i]
            local binding = B.Binding(C.Id("arg:" .. scope_name .. ":" .. p.name), p.name, p.ty, B.BindingRoleArg(i - 1))
            scope = scope:typecheck_tree_add_value(B.ValueEntry(p.name, binding))
        end
        return scope
    end

    function Tr.TypeValueScope:typecheck_tree_with_layouts(layouts)
        return Tr.TypeValueScope(self.module_name, self.values, self.types, layouts, self.facts)
    end

    function Tr.TypeValueScope:typecheck_tree_lookup_value(name)
        for i = #self.values, 1, -1 do
            if self.values[i].name == name then return self.values[i].binding end
        end
        return nil
    end

    function Tr.TypeValueScope:typecheck_tree_stmt_input(return_ty, yield)
        return Tr.TypeStmtInput(self, return_ty, yield)
    end

    function Tr.TypeValueScope:typecheck_tree_expr_input()
        return Tr.TypeExprInput(self)
    end

    function Tr.TypeValueScope:typecheck_tree_place_input()
        return Tr.TypePlaceInput(self)
    end

    function Tr.TypeStmtInput:typecheck_tree_with_scope(scope)
        return Tr.TypeStmtInput(scope, self.return_ty, self.yield)
    end

    function Tr.TypeStmtInput:typecheck_tree_with_yield(yield)
        return Tr.TypeStmtInput(self.scope, self.return_ty, yield)
    end

    function Tr.TypeStmtInput:typecheck_tree_expr_input()
        return self.scope:typecheck_tree_expr_input()
    end

    function Tr.TypeStmtInput:typecheck_tree_place_input()
        return self.scope:typecheck_tree_place_input()
    end

    function Tr.TypeStmtInput:typecheck_tree_expected_expr_input(expected)
        return Tr.TypeExpectedExprInput(self.scope, expected)
    end

    function Ty.HandleFact:typecheck_tree_handle_domain()
        return nil
    end

    function Ty.HandleDomain:typecheck_tree_handle_domain()
        return self.domain
    end

    function Ty.HandleFact:typecheck_tree_handle_target()
        return nil
    end

    function Ty.HandleTarget:typecheck_tree_handle_target()
        return self.target
    end

    function Tr.TypeDecl:typecheck_tree_variant_defs(input)
        return {}
    end

    function Tr.TypeDeclEnumSugar:typecheck_tree_variant_defs(input)
        local variants = {}
        for i = 1, #self.variants do
            local name = variant_name_text(self.variants[i])
            variants[#variants + 1] = Tr.TypeVariantCase(name, i - 1, void_ty(), {})
        end
        return { Tr.TypeVariantDef(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.module_name, self.name)), variants) }
    end

    function Tr.TypeDeclTaggedUnionSugar:typecheck_tree_variant_defs(input)
        local variants = {}
        for i = 1, #self.variants do
            local v = self.variants[i]
            variants[#variants + 1] = Tr.TypeVariantCase(v.name, i - 1, v.payload, v.fields or {})
        end
        return { Tr.TypeVariantDef(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.module_name, self.name)), variants) }
    end

    function Tr.TypeDecl:typecheck_tree_handle_defs(input)
        return {}
    end

    function Tr.TypeDeclHandle:typecheck_tree_handle_defs(input)
        local domain, target = nil, nil
        for i = 1, #(self.facts or {}) do
            domain = self.facts[i]:typecheck_tree_handle_domain() or domain
            target = self.facts[i]:typecheck_tree_handle_target() or target
        end
        return { Tr.TypeHandleDef(self.name, Ty.THandle(Ty.TypeRefGlobal(input.module_name, self.name), self.repr), self.repr, self.invalid, domain, target) }
    end

    function Tr.Func:typecheck_tree_effect_defs(input)
        return {}
    end

    function Tr.FuncLocal:typecheck_tree_effect_defs(input)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
    end

    function Tr.FuncExport:typecheck_tree_effect_defs(input)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
    end

    local function contract_effect_names(contracts)
        local readonly, preserve, invalidate = {}, {}, {}
        for i = 1, #(contracts or {}) do
            contracts[i]:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
        end
        return readonly, preserve, invalidate
    end

    function Tr.FuncLocalContract:typecheck_tree_effect_defs(input)
        local readonly, preserve, invalidate = contract_effect_names(self.contracts)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, readonly, preserve, invalidate) }
    end

    function Tr.FuncExportContract:typecheck_tree_effect_defs(input)
        local readonly, preserve, invalidate = contract_effect_names(self.contracts)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, readonly, preserve, invalidate) }
    end

    function Tr.FuncDecl:typecheck_tree_effect_defs(input)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
    end

    function Tr.FuncContract:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
    end

    function Tr.Expr:typecheck_tree_contract_name()
        return nil
    end

    function Tr.ExprRef:typecheck_tree_contract_name()
        return self.ref:typecheck_tree_contract_name()
    end

    function B.ValueRef:typecheck_tree_contract_name()
        return nil
    end

    function B.ValueRefName:typecheck_tree_contract_name()
        return self.name
    end

    function B.ValueRefBinding:typecheck_tree_contract_name()
        return self.binding and self.binding.name or nil
    end

    function Tr.FuncContract:typecheck_tree_contract(input)
        return self, {}
    end

    function Tr.ContractBounds:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local len = self.len:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, base.issues)
        append_all(issues, len.issues)
        return Tr.ContractBounds(base.expr, len.expr), issues
    end

    function Tr.ContractWindowBounds:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local base_len = self.base_len:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local start = self.start:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local len = self.len:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, base.issues)
        append_all(issues, base_len.issues)
        append_all(issues, start.issues)
        append_all(issues, len.issues)
        return Tr.ContractWindowBounds(base.expr, base_len.expr, start.expr, len.expr), issues
    end

    function Tr.ContractDisjoint:typecheck_tree_contract(input)
        local a = self.a:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local b = self.b:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, a.issues)
        append_all(issues, b.issues)
        return Tr.ContractDisjoint(a.expr, b.expr), issues
    end

    function Tr.ContractSameLen:typecheck_tree_contract(input)
        local a = self.a:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local b = self.b:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, a.issues)
        append_all(issues, b.issues)
        return Tr.ContractSameLen(a.expr, b.expr), issues
    end

    function Tr.ContractSoAComponent:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractSoAComponent(base.expr, self.record_ty:typecheck_tree_canonical(input.scope), self.field_name, self.component_index), base.issues
    end

    function Tr.ContractNoAlias:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractNoAlias(base.expr), base.issues
    end

    function Tr.ContractReadonly:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractReadonly(base.expr), base.issues
    end

    function Tr.ContractWriteonly:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractWriteonly(base.expr), base.issues
    end

    function Tr.ContractInvalidate:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractInvalidate(base.expr), base.issues
    end

    function Tr.ContractPreserve:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractPreserve(base.expr), base.issues
    end

    function Tr.ContractReadonly:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
        local name = self.base:typecheck_tree_contract_name()
        if name ~= nil then readonly[#readonly + 1] = name; preserve[#preserve + 1] = name end
    end

    function Tr.ContractPreserve:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
        local name = self.base:typecheck_tree_contract_name()
        if name ~= nil then preserve[#preserve + 1] = name end
    end

    function Tr.ContractInvalidate:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
        local name = self.base:typecheck_tree_contract_name()
        if name ~= nil then invalidate[#invalidate + 1] = name end
    end

    function Tr.Item:typecheck_tree_variant_defs(input)
        return {}
    end

    function Tr.ItemType:typecheck_tree_variant_defs(input)
        return self.t:typecheck_tree_variant_defs(input)
    end

    function Tr.Item:typecheck_tree_handle_defs(input)
        return {}
    end

    function Tr.ItemType:typecheck_tree_handle_defs(input)
        return self.t:typecheck_tree_handle_defs(input)
    end

    function Tr.Item:typecheck_tree_effect_defs(input)
        return {}
    end

    function Tr.ItemFunc:typecheck_tree_effect_defs(input)
        return self.func:typecheck_tree_effect_defs(input)
    end

    function Tr.ItemExtern:typecheck_tree_effect_defs(input)
        return { Tr.TypeFuncEffect(self.func.name, self.func.params or {}, {}, {}, {}) }
    end

    function Tr.Module:typecheck_tree_module_facts(input)
        local variants, handles, effects = {}, {}, {}
        for i = 1, #self.items do
            local item = self.items[i]
            local item_variants = item:typecheck_tree_variant_defs(input)
            for j = 1, #item_variants do variants[#variants + 1] = item_variants[j] end
            local item_handles = item:typecheck_tree_handle_defs(input)
            for j = 1, #item_handles do handles[#handles + 1] = item_handles[j] end
            local item_effects = item:typecheck_tree_effect_defs(input)
            for j = 1, #item_effects do effects[#effects + 1] = item_effects[j] end
        end
        return Tr.TypeModuleFacts(variants, handles, effects)
    end
end
