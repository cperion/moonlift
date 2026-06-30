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

local function clone_values(values)
    local out = {}
    for i = 1, #values do out[#out + 1] = values[i] end
    return out
end

local function clone_types(types)
    local out = {}
    for i = 1, #types do out[#out + 1] = types[i] end
    return out
end

local function bind_context(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Tr = T.LalinTree

    local module_type_api = require("lalin.tree_module_type")(T)
    local control_api = require("lalin.tree_control_facts")(T)
    require("lalin.tree_typecheck_type")(T)
    require("lalin.tree_typecheck_layout")(T)
    require("lalin.tree_typecheck_fact")(T)
    local type_view
    local type_index_base
    local type_place
    local type_expr
    local type_expr_expect
    local type_func
    local type_item

    local function void_ty() return Ty.TScalar(C.ScalarVoid) end
    local function bool_ty() return Ty.TScalar(C.ScalarBool) end
    local function i32_ty() return Ty.TScalar(C.ScalarI32) end
    local function index_ty() return Ty.TScalar(C.ScalarIndex) end
    local function f64_ty() return Ty.TScalar(C.ScalarF64) end
    local function u8_ty() return Ty.TScalar(C.ScalarU8) end
    local function string_ty() return Ty.TSlice(u8_ty()) end

    function Tr.View:typecheck_tree_elem()
        return void_ty()
    end

    function Tr.ViewFromExpr:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewContiguous:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewStrided:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewRestrided:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewRowBase:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewInterleaved:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewInterleavedView:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewWindow:typecheck_tree_elem()
        return self.base:typecheck_tree_elem()
    end

    local function view_elem(view)
        return view:typecheck_tree_elem()
    end

    local function type_eq(a, b)
        return a == b
    end

    local canonical_type
    canonical_type = function(env, ty)
        return ty:typecheck_tree_canonical(env)
    end

    local function canonical_params(env, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = Ty.Param(params[i].name, canonical_type(env, params[i].ty)) end
        return out
    end

    local function type_contains_lease(ty)
        return ty:typecheck_tree_contains_lease()
    end

    local function type_contains_owned(ty)
        return ty:typecheck_tree_contains_owned()
    end

    local function is_owned_type(ty)
        return ty:typecheck_tree_is_owned_type()
    end

    local function lease_access_base(ty)
        return ty:typecheck_tree_lease_access_base()
    end

    local function arg_matches_param(env, expected, actual)
        expected = canonical_type(env, expected)
        actual = canonical_type(env, actual)
        if type_eq(expected, actual) then return true end
        if is_owned_type(expected) or is_owned_type(actual) then return false end
        return expected:typecheck_tree_arg_matches_actual(env, actual)
    end

    require("lalin.tree_typecheck_expr")(T)
    require("lalin.tree_typecheck_stmt")(T)

    function Tr.ExprHeader:typecheck_tree_typed_ty()
        return nil
    end

    function Tr.ExprTyped:typecheck_tree_typed_ty()
        return self.ty
    end

    local function typed_expr_header_ty(h)
        return h:typecheck_tree_typed_ty()
    end

    function Tr.PlaceHeader:typecheck_tree_typed_ty()
        return nil
    end

    function Tr.PlaceTyped:typecheck_tree_typed_ty()
        return self.ty
    end

    local function typed_place_header_ty(h)
        return h:typecheck_tree_typed_ty()
    end

    local function merged_layouts(scope, extra_layout_env)
        local extra = extra_layout_env and extra_layout_env.layouts
        if extra == nil or #extra == 0 then return scope.layouts end
        local layouts = clone_values(scope.layouts)
        for i = 1, #extra do layouts[#layouts + 1] = extra[i] end
        return layouts
    end

    local function array_len_const(len)
        return len:typecheck_tree_const_count()
    end

    local function check_type_policy(ty, issues, site)
        ty:typecheck_tree_check_policy(issues, site)
    end

    local function type_ref_text(ref)
        return ref:typecheck_tree_ref_text()
    end

    local function type_ref_leaf(ref)
        return ref:typecheck_tree_ref_leaf()
    end

    local function type_ref_matches_ty(ref, ty)
        return ty:typecheck_tree_matches_type_ref(ref)
    end

    local function empty_type_module_facts()
        return Tr.TypeModuleFacts({}, {}, {})
    end

    local function variant_name_text(v)
        if type(v) == "string" then return v end
        return v and (v.text or v.name) or tostring(v)
    end

    local function is_void_type(ty)
        return ty:typecheck_tree_is_void_type()
    end

    local function is_handle_type(ty)
        return ty:typecheck_tree_is_handle_type()
    end

    local function handle_repr_type(handle_ty)
        return handle_ty:typecheck_tree_handle_repr_type()
    end

    local function find_handle_def(scope, name)
        for i = 1, #(scope.facts.handles or {}) do
            if scope.facts.handles[i].name == name then return scope.facts.handles[i] end
        end
        return nil
    end

    local function find_handle_def_for_type(scope, ty)
        return ty:typecheck_tree_handle_def(scope.facts)
    end

    local function lease_target_type(ty)
        return ty:typecheck_tree_lease_target_type()
    end

    local function lease_origin_name(lease_ty)
        return lease_ty:typecheck_tree_lease_origin_name()
    end

    local function lease_payload_info(ty)
        return ty:typecheck_tree_lease_payload_info()
    end

    local function access_allows_lease_grant(ty)
        return ty:typecheck_tree_access_allows_lease_grant()
    end

    local function param_domain_matches(param_ty, domain_ref)
        local elem = param_ty:typecheck_tree_domain_match_elem()
        if elem == nil then return false end
        return type_ref_matches_ty(domain_ref, elem)
    end

    local function append_domain_param(params_by_domain, domain_ref, param_name)
        local key = type_ref_leaf(domain_ref) or ""
        local bucket = params_by_domain[key]
        if not bucket then bucket = {}; params_by_domain[key] = bucket end
        bucket[#bucket + 1] = param_name
    end

    local function contains_name(names, name)
        for i = 1, #(names or {}) do if names[i] == name then return true end end
        return false
    end

    local function check_handle_resolution_signature(scope, params, payload_params, issues, site)
        local handle_defs = {}
        local domain_params = {}
        local preserving_domain_params = {}
        local all_defs = scope.facts.handles or {}
        for i = 1, #(params or {}) do
            local pty = canonical_type(scope, params[i].ty)
            local def = find_handle_def_for_type(scope, pty)
            if def and def.target then handle_defs[#handle_defs + 1] = def end
            for j = 1, #all_defs do
                local hdef = all_defs[j]
                if hdef.domain and param_domain_matches(pty, hdef.domain) then
                    append_domain_param(domain_params, hdef.domain, params[i].name)
                    if access_allows_lease_grant(pty) then append_domain_param(preserving_domain_params, hdef.domain, params[i].name) end
                end
            end
        end
        if #handle_defs == 0 then return end
        for i = 1, #(payload_params or {}) do
            local info = lease_payload_info(canonical_type(scope, payload_params[i].ty))
            if info ~= nil then
                local matched = nil
                for j = 1, #handle_defs do
                    if type_ref_matches_ty(handle_defs[j].target, info.target) then
                        matched = handle_defs[j]
                        break
                    end
                end
                if matched == nil then
                    issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryHandleTargetMismatch, info.lease)
                elseif matched.domain then
                    local key = type_ref_leaf(matched.domain) or ""
                    if #(domain_params[key] or {}) == 0 then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryHandleDomainMissing, info.lease)
                    elseif #(preserving_domain_params[key] or {}) == 0 then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryHandleDomainAccess, info.lease)
                    elseif info.origin == nil then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryHandleLeaseOriginMissing, info.lease)
                    elseif not contains_name(preserving_domain_params[key], info.origin) then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryHandleLeaseOriginMismatch, info.lease)
                    end
                end
            end
        end
    end

    local function find_variant(scope, type_name, variant_name)
        for i = 1, #(scope.facts.variants or {}) do
            local def = scope.facts.variants[i]
            if def.type_name == type_name then
                for j = 1, #(def.variants or {}) do
                    if def.variants[j].name == variant_name then return def, def.variants[j] end
                end
                return def, nil
            end
        end
        return nil, nil
    end

    local function variant_def_for_value_ty(scope, ty)
        return ty:typecheck_tree_variant_def(scope.facts)
    end

    local function bind_scope_for_variant(scope, region_id, variant, requested_binds)
        local out_scope = scope
        local binds = {}
        if requested_binds ~= nil and #requested_binds > 0 then
            for i = 1, #requested_binds do
                local rb = requested_binds[i]
                local ty = rb.ty
                for j = 1, #(variant.fields or {}) do
                    if variant.fields[j].field_name == rb.name then ty = variant.fields[j].ty end
                end
                if is_void_type(ty) and not is_void_type(variant.payload) then ty = variant.payload end
                binds[#binds + 1] = { name = rb.name, ty = ty }
            end
        elseif #(variant.fields or {}) > 0 then
            for i = 1, #variant.fields do binds[#binds + 1] = { name = variant.fields[i].field_name, ty = variant.fields[i].ty } end
        elseif not is_void_type(variant.payload) then
            binds[#binds + 1] = { name = "payload", ty = variant.payload }
        end
        for i = 1, #binds do
            local b = B.Binding(C.Id("variant:" .. tostring(region_id or "switch") .. ":" .. variant.name .. ":" .. binds[i].name), binds[i].name, binds[i].ty, B.BindingRoleLocalValue)
            out_scope = out_scope:typecheck_tree_add_value(B.ValueEntry(b.name, b))
        end
        return out_scope, binds
    end

    local function live_lease_tys(scope)
        local out = {}
        for i = #scope.values, 1, -1 do
            local ty = canonical_type(scope, scope.values[i].binding.ty)
            ty:typecheck_tree_append_live_lease(out)
        end
        return out
    end

    local function callee_effect_def(scope, callee_expr)
        local binding_name = callee_expr:typecheck_tree_binding_name()
        if binding_name == nil then return nil end
        for i = 1, #(scope.facts.effects or {}) do
            if scope.facts.effects[i].name == binding_name then return scope.facts.effects[i] end
        end
        return nil
    end

    local function call_may_invalidate_while_lease_live(scope, callee_expr, param_tys, typed_args)
        local leases = live_lease_tys(scope)
        if #leases == 0 then return nil end
        local effect = callee_effect_def(scope, callee_expr)
        local preserve = effect and effect.preserve or {}
        local explicit_invalidate = effect and effect.invalidate or {}
        for i = 1, #(param_tys or {}) do
            local pty = canonical_type(scope, param_tys[i])
            if pty:typecheck_tree_call_may_invalidate_live_lease_param() then
                local pname = effect and effect.params and effect.params[i] and effect.params[i].name
                local preserves_param = pname and contains_name(preserve, pname)
                local invalidates_param = (pname and contains_name(explicit_invalidate, pname)) or not preserves_param
                if invalidates_param then
                    local arg_name = typed_args and typed_args[i] and typed_args[i]:typecheck_tree_binding_name() or nil
                    for j = 1, #leases do
                        local origin = lease_origin_name(leases[j])
                        if origin == nil or arg_name == nil or origin == arg_name then return leases[j] end
                    end
                end
            end
        end
        return nil
    end

    type_expr_expect = function(expr, stmt_input, expected)
        return expr:typecheck_tree_expr_expected(stmt_input:typecheck_tree_expected_expr_input(expected))
    end

    local function check_expected(site, expected, actual, issues)
        if not type_eq(expected, actual) then issues[#issues + 1] = Tr.TypeIssueExpected(site, expected, actual) end
    end

    function type_view(node, ...)
        return node:typecheck_tree_view(...)
    end

    function type_index_base(node, ...)
        return node:typecheck_tree_index_base(...)
    end

    function type_place(node, input)
        return node:typecheck_tree_place(input)
    end

    function type_expr(node, input)
        return node:typecheck_tree_expr(input)
    end

    local function jump_args_by_name(args)
        local out = {}; local dup = {}
        for i = 1, #args do if out[args[i].name] ~= nil then dup[args[i].name] = true end; out[args[i].name] = args[i] end
        return out, dup
    end

    local function block_param_bindings(region_id, label, params, is_entry)
        local entries = {}
        for i = 1, #params do
            local role = is_entry and B.BindingRoleEntryBlockParam(region_id, label.name, i) or B.BindingRoleBlockParam(region_id, label.name, i)
            local binding = B.Binding(C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. params[i].name), params[i].name, params[i].ty, role)
            entries[#entries + 1] = B.ValueEntry(params[i].name, binding)
        end
        return entries
    end

    local function scope_with_block_params(scope, region_id, label, params, is_entry)
        local out = scope
        local entries = block_param_bindings(region_id, label, params, is_entry)
        for i = 1, #entries do out = out:typecheck_tree_add_value(entries[i]) end
        return out
    end

    local function type_contracts(contracts, input)
        local out, issues = {}, {}
        for i = 1, #contracts do
            local c, ci = contracts[i]:typecheck_tree_contract(input)
            out[#out + 1] = c
            append_all(issues, ci)
        end
        return out, issues
    end

    local function check_func_types(func, issues)
        for i = 1, #(func.params or {}) do check_type_policy(func.params[i].ty, issues, "param " .. tostring(func.params[i].name)) end
        check_type_policy(func.result, issues, "result")
        if type_contains_lease(func.result) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryLeaseEscapeDurable, func.result) end
    end

    function Tr.Region:typecheck_tree_signature_issues(input)
        local issues = {}
        for i = 1, #(self.params or {}) do
            check_type_policy(self.params[i].ty, issues, "region param " .. tostring(self.params[i].name))
        end
        for i = 1, #(self.conts or {}) do
            local cont = self.conts[i]
            for j = 1, #(cont.params or {}) do
                local param = cont.params[j]
                check_type_policy(param.ty, issues, "continuation " .. tostring(cont.name) .. " param " .. tostring(param.name))
            end
            check_handle_resolution_signature(input.scope, self.params, cont.params, issues, "region " .. tostring(cont.name))
        end
        return issues
    end

    local function canonical_func(self, scope)
        return schema.with(self, { params = canonical_params(scope, self.params), result = canonical_type(scope, self.result) })
    end

    local function canonical_block_params(scope, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = schema.with(params[i], { ty = canonical_type(scope, params[i].ty) }) end
        return out
    end

    local function canonical_entry_params(scope, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = schema.with(params[i], { ty = canonical_type(scope, params[i].ty) }) end
        return out
    end

    local function canonical_region(scope, region)
        local params = canonical_params(scope, region.params or {})
        local conts = {}
        for i = 1, #(region.conts or {}) do conts[i] = schema.with(region.conts[i], { params = canonical_block_params(scope, region.conts[i].params) }) end
        local entry = schema.with(region.entry, { params = canonical_entry_params(scope, region.entry.params) })
        local blocks = {}
        for i = 1, #(region.blocks or {}) do blocks[i] = schema.with(region.blocks[i], { params = canonical_block_params(scope, region.blocks[i].params) }) end
        return schema.with(region, { params = params, conts = conts, entry = entry, blocks = blocks })
    end

    local function type_plain_func(self, input)
        local func = canonical_func(self, input.scope)
        local func_scope = input.scope:typecheck_tree_add_params(func.name, func.params)
        local stmt_input = func_scope:typecheck_tree_stmt_input(func.result, Tr.TypeYieldNone)
        local body = stmt_input:typecheck_tree_stmt_body(func.body)
        local issues = {}; check_func_types(func, issues); append_all(issues, body.issues)
        check_owned_function(func.name, func.params, body.stmts, issues)
        return Tr.TypeFuncResult(schema.with(func, { body = body.stmts }), issues)
    end

    local function type_contract_func(self, input)
        local func = canonical_func(self, input.scope)
        local func_scope = input.scope:typecheck_tree_add_params(func.name, func.params)
        local stmt_input = func_scope:typecheck_tree_stmt_input(func.result, Tr.TypeYieldNone)
        local contracts, issues = type_contracts(func.contracts, stmt_input)
        check_func_types(func, issues)
        local body = stmt_input:typecheck_tree_stmt_body(func.body)
        append_all(issues, body.issues)
        check_owned_function(func.name, func.params, body.stmts, issues)
        return Tr.TypeFuncResult(schema.with(func, { contracts = contracts, body = body.stmts }), issues)
    end

    function Tr.FuncLocal:typecheck_tree_func(input)
        return type_plain_func(self, input)
    end

    function Tr.FuncExport:typecheck_tree_func(input)
        return type_plain_func(self, input)
    end

    function Tr.FuncLocalContract:typecheck_tree_func(input)
        return type_contract_func(self, input)
    end

    function Tr.FuncExportContract:typecheck_tree_func(input)
        return type_contract_func(self, input)
    end

    function type_func(node, ...)
        return node:typecheck_tree_func(...)
    end

    function Tr.ItemFunc:typecheck_tree_item(input)
        local r = type_func(self.func, Tr.TypeFuncInput(input.scope))
        return Tr.TypeItemResult({ Tr.ItemFunc(r.func) }, r.issues)
    end

    function Tr.ItemConst:typecheck_tree_item(input)
        local ty = canonical_type(input.scope, self.c.ty)
        local expr_input = input.scope:typecheck_tree_expr_input()
        local value = type_expr(self.c.value, expr_input)
        local issues = {}
        check_type_policy(ty, issues, "const")
        append_all(issues, value.issues)
        check_expected("const", ty, value.ty, issues)
        if type_contains_lease(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryLeaseEscapeDurable, ty) end
        if type_contains_owned(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryOwnedCapturedDurable, ty) end
        return Tr.TypeItemResult({ Tr.ItemConst(schema.with(self.c, { ty = ty, value = value.expr })) }, issues)
    end

    function Tr.ItemStatic:typecheck_tree_item(input)
        local ty = canonical_type(input.scope, self.s.ty)
        local expr_input = input.scope:typecheck_tree_expr_input()
        local value = type_expr(self.s.value, expr_input)
        local issues = {}
        check_type_policy(ty, issues, "static")
        append_all(issues, value.issues)
        check_expected("static", ty, value.ty, issues)
        if type_contains_lease(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryLeaseEscapeDurable, ty) end
        if type_contains_owned(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryOwnedCapturedDurable, ty) end
        return Tr.TypeItemResult({ Tr.ItemStatic(schema.with(self.s, { ty = ty, value = value.expr })) }, issues)
    end

    function Tr.ItemExtern:typecheck_tree_item()
        local issues = {}
        check_func_types(self.func, issues)
        return Tr.TypeItemResult({ self }, issues)
    end

    function Tr.ItemImport:typecheck_tree_item()
        return Tr.TypeItemResult({ self }, {})
    end

    function Tr.TypeDecl:typecheck_tree_item_issues()
        return {}
    end

    function Tr.TypeDeclStruct:typecheck_tree_item_issues()
        local issues = {}
        for i = 1, #self.fields do
            check_type_policy(self.fields[i].ty, issues, "field " .. self.fields[i].field_name)
            if type_contains_lease(self.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryLeaseEscapeDurable, self.fields[i].ty) end
            if type_contains_owned(self.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryOwnedCapturedDurable, self.fields[i].ty) end
        end
        return issues
    end

    function Tr.TypeDeclUnion:typecheck_tree_item_issues()
        local issues = {}
        for i = 1, #self.fields do
            check_type_policy(self.fields[i].ty, issues, "field " .. self.fields[i].field_name)
            if type_contains_lease(self.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryLeaseEscapeDurable, self.fields[i].ty) end
            if type_contains_owned(self.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(Tr.TypeUnaryOwnedCapturedDurable, self.fields[i].ty) end
        end
        return issues
    end

    function Tr.TypeDeclEnumSugar:typecheck_tree_item_issues()
        local issues = {}
        local seen = {}
        for i = 1, #self.variants do
            local name = variant_name_text(self.variants[i])
            if seen[name] then issues[#issues + 1] = Tr.TypeIssueDuplicateVariant(self.name, name) end
            seen[name] = true
        end
        return issues
    end

    function Tr.TypeDeclTaggedUnionSugar:typecheck_tree_item_issues()
        local issues = {}
        local seen = {}
        local is_region_call_result = type(self.name) == "string" and self.name:match("^__lalin_region_call_") ~= nil
        for i = 1, #self.variants do
            local v = self.variants[i]
            local name = v.name
            check_type_policy(v.payload, issues, "variant " .. name)
            if type_contains_lease(v.payload) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and Tr.TypeUnaryRegionCallLeasePayload or Tr.TypeUnaryLeaseEscapeDurable, v.payload) end
            if type_contains_owned(v.payload) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and Tr.TypeUnaryOwnedRegionCallPayload or Tr.TypeUnaryOwnedCapturedDurable, v.payload) end
            for j = 1, #(v.fields or {}) do
                check_type_policy(v.fields[j].ty, issues, "variant field " .. v.fields[j].field_name)
                if type_contains_lease(v.fields[j].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and Tr.TypeUnaryRegionCallLeasePayload or Tr.TypeUnaryLeaseEscapeDurable, v.fields[j].ty) end
                if type_contains_owned(v.fields[j].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and Tr.TypeUnaryOwnedRegionCallPayload or Tr.TypeUnaryOwnedCapturedDurable, v.fields[j].ty) end
            end
            if seen[name] then issues[#issues + 1] = Tr.TypeIssueDuplicateVariant(self.name, name) end
            seen[name] = true
        end
        return issues
    end

    function Tr.TypeDeclHandle:typecheck_tree_item_issues()
        local issues = {}
        self.repr:typecheck_tree_check_handle_decl(self.name, issues)
        return issues
    end

    function Tr.ItemType:typecheck_tree_item()
        local issues = self.t:typecheck_tree_item_issues()
        return Tr.TypeItemResult({ self }, issues)
    end

    function Tr.ItemRegion:typecheck_tree_item(input)
        local region = canonical_region(input.scope, self.region)
        local issues = region:typecheck_tree_signature_issues(input)
        local region_scope = input.scope:typecheck_tree_add_params("region:" .. tostring(region.name), region.params)
        local stmt_input = region_scope:typecheck_tree_stmt_input(Ty.TScalar(C.ScalarVoid), Tr.TypeYieldNone)
        local region_id = "region:" .. tostring(region.name)
        local control_input = Tr.TypeControlInput(stmt_input:typecheck_tree_with_yield(Tr.TypeYieldVoid), region_id)
        local typed_entry, entry_issues = region.entry:typecheck_tree_control_entry(control_input)
        append_all(issues, entry_issues)
        local typed_blocks = {}
        for i = 1, #(region.blocks or {}) do
            local b, bi = region.blocks[i]:typecheck_tree_control_block(control_input)
            typed_blocks[#typed_blocks + 1] = b
            append_all(issues, bi)
        end
        local runtime_bindings = {}
        for i = 1, #region.params do
            local p = region.params[i]
            local b = B.Binding(C.Id("region-param:" .. region.name .. ":" .. p.name), p.name, p.ty, B.BindingRoleArg(i - 1))
            runtime_bindings[#runtime_bindings + 1] = B.ValueEntry(p.name, b)
        end
        local cont_targets = {}
        for i = 1, #(region.conts or {}) do cont_targets[region.conts[i].name] = true end
        check_owned_control_region(Tr.ControlStmtRegion(region_id, typed_entry, typed_blocks), issues, runtime_bindings, cont_targets)
        return Tr.TypeItemResult({}, issues)
    end

    function type_item(node, ...)
        return node:typecheck_tree_item(...)
    end

    function Tr.Item:typecheck_tree_diagnostic_name()
        return nil
    end

    function Tr.ItemFunc:typecheck_tree_diagnostic_name()
        return self.func and self.func.name or nil
    end

    function Tr.ItemRegion:typecheck_tree_diagnostic_name()
        return self.region and self.region.name or nil
    end

    function Tr.ItemType:typecheck_tree_diagnostic_name()
        return self.t and self.t.name or nil
    end

    function Tr.ItemExtern:typecheck_tree_diagnostic_name()
        return self.func and self.func.name or nil
    end

    function Tr.ItemConst:typecheck_tree_diagnostic_name()
        return self.c and self.c.name or nil
    end

    function Tr.ItemStatic:typecheck_tree_diagnostic_name()
        return self.s and self.s.name or nil
    end

    local function item_diagnostic_name(item)
        return item:typecheck_tree_diagnostic_name()
    end

    function Tr.ControlReject:typecheck_tree_report(region)
        return Tr.ControlRejectExplanation("E0405", "irreducible control flow", {
            "region: " .. tostring(region),
            self.reason or "irreducible cycle detected",
            "control flow is irreducible when no block dominates the others - restructure so one block is the single entry point",
        }, {
            "add a dispatch block that dominates all other blocks in this region",
        })
    end

    function Tr.ControlRejectMissingJumpArg:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        local name = tostring(self.name)
        return Tr.ControlRejectExplanation("E0404", "jump to `" .. label .. "` is missing argument `" .. name .. "`", {
            "region: " .. tostring(region),
            "target block `" .. label .. "` declares parameter `" .. name .. "`, but this jump does not provide it",
        }, {
            "pass `" .. name .. " = ...` at the jump, or rename the target block parameter to match the existing argument",
        })
    end

    function Tr.ControlRejectExtraJumpArg:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        local name = tostring(self.name)
        return Tr.ControlRejectExplanation("E0404", "jump to `" .. label .. "` has extra argument `" .. name .. "`", {
            "region: " .. tostring(region),
            "target block `" .. label .. "` has no parameter named `" .. name .. "`",
        }, {
            "remove the extra argument or add a matching block parameter",
        })
    end

    function Tr.ControlRejectDuplicateJumpArg:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0203", "duplicate jump argument `" .. tostring(self.name) .. "` for `" .. label .. "`", {
            "region: " .. tostring(region),
        }, {
            "provide each jump argument name only once",
        })
    end

    function Tr.ControlRejectJumpType:typecheck_tree_report(region)
        local Format = require("lalin.error.format")
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0301", "jump argument `" .. tostring(self.name) .. "` for `" .. label .. "` has wrong type", {
            "region: " .. tostring(region),
            "expected `" .. Format.type_name(self.expected) .. "`, got `" .. Format.type_name(self.actual) .. "`",
        }, {})
    end

    function Tr.ControlRejectMissingLabel:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0402", "missing jump target `" .. label .. "`", {
            "region: " .. tostring(region),
            "block `" .. label .. "` is not defined in this region",
        }, {})
    end

    function Tr.ControlRejectDuplicateLabel:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0203", "duplicate block label `" .. label .. "`", {
            "region: " .. tostring(region),
        }, {
            "rename one of the blocks",
        })
    end

    function Tr.ControlRejectUnterminatedBlock:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0406", "block `" .. label .. "` does not terminate", {
            "region: " .. tostring(region),
            "every block path must end in jump, yield, return, or trap",
        }, {})
    end

    function Tr.ControlRejectYieldOutsideRegion:typecheck_tree_report(region)
        return Tr.ControlRejectExplanation("E0407", "invalid yield in control region", {
            "region: " .. tostring(region),
            self.reason or "yield kind does not match this region",
        }, {})
    end

    function Tr.ControlRejectYieldType:typecheck_tree_report(region)
        local Format = require("lalin.error.format")
        return Tr.ControlRejectExplanation("E0301", "yield has wrong type", {
            "region: " .. tostring(region),
            "expected `" .. Format.type_name(self.expected) .. "`, got `" .. Format.type_name(self.actual) .. "`",
        }, {})
    end

    function Tr.ControlRejectUnknownVariant:typecheck_tree_report(region)
        return Tr.ControlRejectExplanation("E0201", "unknown switch variant `" .. tostring(self.variant_name or "?") .. "`", {
            "region: " .. tostring(region),
        }, {})
    end

    function Tr.TypeIssueInvalidControl:typecheck_tree_fallback_control_report(region)
        return Tr.ControlRejectExplanation("E0405", "irreducible control flow", {
            "region: " .. tostring(region),
            "irreducible cycle detected",
            "control flow is irreducible when no block dominates the others - restructure so one block is the single entry point",
        }, {
            "add a dispatch block that dominates all other blocks in this region",
        })
    end

    function Tr.TypeIssue:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E9999", "", tostring(self), {}, {})
    end

    function Tr.TypeIssueInvalidControl:typecheck_tree_explanation()
        local reject = self.reject
        local region = self.region_id or (reject and reject.region_id) or "?"
        local report = reject and reject:typecheck_tree_report(region) or self:typecheck_tree_fallback_control_report(region)
        return Tr.TypeIssueExplanation(report.code, "while checking control flow", report.primary, report.notes, report.suggestions)
    end

    function Tr.TypeIssueMissingJumpTarget:typecheck_tree_explanation()
        local label = (self.label and self.label.name) or "?"
        return Tr.TypeIssueExplanation("E0402", "while checking control flow", "missing jump target `" .. label .. "`", {
            "block `" .. label .. "` is not defined in this region",
        }, {})
    end

    function Tr.TypeIssueMissingJumpArg:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E0404", "while checking control flow", "jump argument count mismatch for `" .. tostring(self.name or "?") .. "`", {
            "check that the number of arguments passed to the jump matches the block parameters",
        }, {})
    end

    function Tr.TypeIssueExtraJumpArg:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E0404", "while checking control flow", "jump argument count mismatch for `" .. tostring(self.name or "?") .. "`", {
            "check that the number of arguments passed to the jump matches the block parameters",
        }, {})
    end

    function Tr.TypeIssueDuplicateJumpArg:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E0203", "while checking control flow", "duplicate jump argument `" .. tostring(self.name or "?") .. "`", {}, {
            "remove the duplicate argument or rename one of them",
        })
    end

    function Tr.TypeIssueUnexpectedYield:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E0407", "while type-checking", "`yield` used outside a region", {
            "`yield` can only be used inside a `region` or a `return region: T` expression",
        }, {
            "did you mean `return`? Functions use `return`, not `yield`",
        })
    end

    function Tr.TypeIssueUnknownVariant:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        return Tr.TypeIssueExplanation("E0201", "while resolving names", "unknown variant `" .. tostring(self.variant_name or "?") .. "` in type `" .. Format.type_name(self.type_name) .. "`", {}, {})
    end

    function Tr.TypeIssueVariantPayloadMismatch:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E0301", "while type-checking", "variant payload mismatch for `" .. tostring(self.variant_name or "?") .. "`", {}, {})
    end

    function Tr.TypeIssueDuplicateVariant:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E0203", "while checking declarations", "duplicate variant `" .. tostring(self.variant_name or "?") .. "`", {}, {})
    end

    function Tr.TypeIssueNotCallable:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local ty = Format.type_name(self.ty)
        return Tr.TypeIssueExplanation("E0302", "while type-checking a call", "type `" .. ty .. "` is not callable", {
            "only `func` and `closure` types can be called",
        }, {
            "did you mean to index? write `expr[idx]` for element access",
        })
    end

    function Tr.TypeIssueNotIndexable:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local ty = Format.type_name(self.ty)
        return Tr.TypeIssueExplanation("E0303", "while type-checking an index", "type `" .. ty .. "` is not indexable", {
            "only `view`, `ptr`, and `array` types support indexing",
        }, {
            "if you meant to access a field, use `.` syntax: `expr.field`",
        })
    end

    function Tr.TypeIssueNotPointer:typecheck_tree_explanation()
        return self:typecheck_tree_explanation_not_indexable()
    end

    function Tr.TypeIssueNotPointer:typecheck_tree_explanation_not_indexable()
        local Format = require("lalin.error.format")
        local ty = Format.type_name(self.ty)
        return Tr.TypeIssueExplanation("E0303", "while type-checking an index", "type `" .. ty .. "` is not indexable", {
            "only `view`, `ptr`, and `array` types support indexing",
        }, {
            "if you meant to access a field, use `.` syntax: `expr.field`",
        })
    end

    function Tr.TypeIssueArgCount:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E0305", "while type-checking", (self.site or "call") .. " expected " .. tostring(self.expected) .. " arguments, got " .. tostring(self.actual), {}, {
            "check the function signature and add or remove arguments",
        })
    end

    function Tr.TypeIssueInvalidBinary:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local op = Format.op_symbol(self.op)
        local lhs = Format.type_name(self.lhs)
        local rhs = Format.type_name(self.rhs)
        local notes = { "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" }
        local suggestions = {}
        if lhs == "bool" and rhs == "bool" and (op == "+" or op == "-" or op == "*" or op == "/") then
            notes[#notes + 1] = "arithmetic operators require numeric types (i8, i16, i32, ...)"
            suggestions[#suggestions + 1] = "for boolean logic, use `and` / `or`: `a and b` or `a or b`"
        end
        if lhs ~= rhs then notes[#notes + 1] = "both operands must have the same type" end
        return Tr.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid operator `" .. op .. "`", notes, suggestions)
    end

    function Tr.TypeIssueInvalidCompare:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local op = Format.op_symbol(self.op)
        local lhs = Format.type_name(self.lhs)
        local rhs = Format.type_name(self.rhs)
        local notes = { "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" }
        if lhs ~= rhs then notes[#notes + 1] = "both operands must have the same type" end
        return Tr.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid operator `" .. op .. "`", notes, {})
    end

    function Tr.TypeIssueInvalidLogic:typecheck_tree_explanation()
        return self:typecheck_tree_explanation_compare_like()
    end

    function Tr.TypeIssueInvalidLogic:typecheck_tree_explanation_compare_like()
        local Format = require("lalin.error.format")
        local op = Format.op_symbol(self.op)
        local lhs = Format.type_name(self.lhs)
        local rhs = Format.type_name(self.rhs)
        local notes = { "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" }
        if lhs ~= rhs then notes[#notes + 1] = "both operands must have the same type" end
        return Tr.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid operator `" .. op .. "`", notes, {})
    end

    function Tr.TypeIssueUnresolvedValue:typecheck_tree_explanation()
        return Tr.TypeIssueExplanation("E0201", "while resolving names", "unresolved name `" .. tostring(self.name or "?") .. "`", {
            "`" .. tostring(self.name or "?") .. "` is not defined in this scope",
        }, {})
    end

    function Tr.TypeIssueUnresolvedPath:typecheck_tree_explanation()
        local parts = {}
        for i = 1, #((self.path and self.path.parts) or {}) do parts[i] = self.path.parts[i].text end
        local path_text = #parts > 0 and table.concat(parts, ".") or "?"
        local first_segment = parts[1] or "?"
        return Tr.TypeIssueExplanation("E0202", "while resolving names", "unresolved path `" .. path_text .. "`", {
            "the first segment `" .. first_segment .. "` could not be resolved",
        }, {})
    end

    function Tr.TypeIssueExpected:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local site = self.site or "expression"
        local expected = Format.type_name(self.expected)
        local actual = Format.type_name(self.actual)
        local notes = {}
        local suggestions = {}

        if site:find("call") then
            notes[#notes + 1] = "this argument has type `" .. actual .. "`, but the function expects `" .. expected .. "`"
        elseif site:find("let ") or site:find("var ") then
            notes[#notes + 1] = "the initializer has type `" .. actual .. "`, but the variable is declared as `" .. expected .. "`"
        elseif site:find("return") then
            notes[#notes + 1] = "the return value has type `" .. actual .. "`, but the function returns `" .. expected .. "`"
        elseif site:find("yield") then
            notes[#notes + 1] = "the yielded value has type `" .. actual .. "`, but the region yields `" .. expected .. "`"
        elseif site:find("set") then
            notes[#notes + 1] = "the assigned value has type `" .. actual .. "`, but the target has type `" .. expected .. "`"
        elseif site:find("if cond") or site:find("select cond") then
            notes[#notes + 1] = "the condition has type `" .. actual .. "`, but the condition must be `bool`"
        elseif site:find("if branches") or site:find("select branches") then
            notes[#notes + 1] = "both branches must have the same type; the then-branch is `" .. actual .. "`, the else-branch is `" .. expected .. "`"
        elseif site:find("index") then
            notes[#notes + 1] = "indexing requires an integer type, got `" .. actual .. "`"
        elseif site:find("view data") then
            notes[#notes + 1] = "view data must be a `ptr` or `view`, got `" .. actual .. "`"
        elseif site:find("view len") or site:find("view stride") or site:find("view window") or site:find("bounds") or site:find("window_bounds") then
            notes[#notes + 1] = "expected `" .. expected .. "`, got `" .. actual .. "`"
        elseif site:find("disjoint") then
            notes[#notes + 1] = "disjoint contract requires `ptr` or `view`, got `" .. actual .. "`"
        elseif site:find("same_len") then
            notes[#notes + 1] = "same_len contract requires `view`, got `" .. actual .. "`"
        elseif site:find("memory contract") then
            notes[#notes + 1] = "memory contract requires `ptr` or `view`, got `" .. actual .. "`"
        elseif site:find("atomic") then
            notes[#notes + 1] = "expected `" .. expected .. "`, got `" .. actual .. "`"
        elseif site:find("block param") then
            notes[#notes + 1] = "block parameter initializer has type `" .. actual .. "`, but the parameter is declared as `" .. expected .. "`"
        elseif site:find("assert") then
            notes[#notes + 1] = "assert condition must be `bool`, got `" .. actual .. "`"
        elseif site:find("switch key") then
            notes[#notes + 1] = "switch key has type `" .. actual .. "`, but the switch expression is `" .. expected .. "`"
        elseif site:find("switch arm") then
            notes[#notes + 1] = "switch arm has type `" .. actual .. "`, but the default arm is `" .. expected .. "`"
        elseif site:find("array elem") then
            notes[#notes + 1] = "array element has type `" .. actual .. "`, but the array expects `" .. expected .. "`"
        elseif site:find("len") then
            notes[#notes + 1] = "`len` requires a `view`, got `" .. actual .. "`"
        elseif site:find("const") or site:find("static") then
            notes[#notes + 1] = "the initializer has type `" .. actual .. "`, but the declaration is `" .. expected .. "`"
        else
            notes[#notes + 1] = "expected `" .. expected .. "`, got `" .. actual .. "`"
        end

        if actual == "bool" and expected ~= "bool" then
            suggestions[#suggestions + 1] = "to convert a boolean to an integer, use a conditional: `select(flag, 1, 0)`"
        elseif actual == "f64" and self.expected:typecheck_tree_is_integer_scalar() then
            suggestions[#suggestions + 1] = "to convert a float to an integer, use `as(i32, value)`"
        elseif self.actual:typecheck_tree_is_integer_scalar() and expected == "f64" then
            suggestions[#suggestions + 1] = "to convert an integer to a float, use `as(f64, value)`"
        end

        return Tr.TypeIssueExplanation("E0301", "while type-checking", "type mismatch", notes, suggestions)
    end

    function Tr.TypeIssueInvalidUnary:typecheck_tree_explanation()
        return self.reason:typecheck_tree_explanation(self.ty)
    end

    function Tr.TypeUnaryIssueReason:typecheck_tree_explanation(ty)
        local Format = require("lalin.error.format")
        local ty_text = Format.type_name(ty)
        return Tr.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid unary operator for type `" .. ty_text .. "`", {}, {})
    end

    function Tr.TypeUnaryInvalidOperator:typecheck_tree_explanation(ty)
        local Format = require("lalin.error.format")
        local op = Format.op_symbol(self.op)
        local ty_text = Format.type_name(ty)
        local notes = {}
        local suggestions = {}
        if op == "not" then
            notes[#notes + 1] = "`not` requires a `bool` operand, got `" .. ty_text .. "`"
        else
            notes[#notes + 1] = "operator `" .. op .. "` is not defined for type `" .. ty_text .. "`"
            notes[#notes + 1] = "arithmetic operators require numeric types (i8, i16, i32, ...)"
        end
        if ty_text == "bool" and op ~= "not" then suggestions[#suggestions + 1] = "for boolean logic, use `not`: `not value`" end
        return Tr.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid unary operator `" .. op .. "` for type `" .. ty_text .. "`", notes, suggestions)
    end

    local function unary_reason_report(primary, notes, suggestions)
        return Tr.TypeIssueExplanation("E0304", "while type-checking an expression", primary, notes or {}, suggestions or {})
    end

    function Tr.TypeUnaryLeaseEscapeReturn:typecheck_tree_explanation(ty)
        local ty_text = require("lalin.error.format").type_name(ty)
        return unary_reason_report("lease escapes through return", {
            "lease value `" .. ty_text .. "` is temporary access produced by a store or boundary",
            "leases may access memory inside their dynamic extent but may not be returned as durable identity",
        }, { "return a handle or copied scalar data instead, or keep the pointer parameter marked `noescape`" })
    end

    function Tr.TypeUnaryLeaseEscapeYield:typecheck_tree_explanation(ty)
        local ty_text = require("lalin.error.format").type_name(ty)
        return unary_reason_report("lease escapes through yield", {
            "yielding `" .. ty_text .. "` would move temporary access outside the granting region",
        }, { "yield a handle/status protocol, not the lease pointer/view" })
    end

    function Tr.TypeUnaryLeaseEscapeStore:typecheck_tree_explanation(ty)
        return unary_reason_report("lease escapes through store", {
            "storing `" .. require("lalin.error.format").type_name(ty) .. "` would make temporary access durable",
        }, { "store the handle, or copy the data through the lease instead" })
    end

    function Tr.TypeUnaryLeaseEscapeCall:typecheck_tree_explanation(ty)
        return unary_reason_report("lease passed to retaining parameter", {
            "a lease can only be passed to another `lease` or `noescape` parameter",
            "plain `ptr`/`view` parameters are treated as possibly retained",
        }, { "mark the callee parameter `noescape`, or change it to `lease ptr(T)` / `lease view(T)`" })
    end

    function Tr.TypeUnaryLeaseInvalidatingCall:typecheck_tree_explanation(ty)
        return unary_reason_report("call may invalidate store while lease is live", {
            "live lease `" .. require("lalin.error.format").type_name(ty) .. "` may refer to storage that this call can move, free, compact, clear, or reuse",
            "`readonly` and `preserve` parameters keep leases valid; unannotated pointer/view parameters are conservative invalidators",
        }, { "end the lease scope before the call, call a `preserve`/`readonly` API, or use `lease(store)` to associate the lease with the correct store" })
    end

    function Tr.TypeUnaryLeaseEscapeAggregate:typecheck_tree_explanation(ty)
        return unary_reason_report("lease captured in aggregate", {
            "aggregates can outlive the current access extent, so they cannot contain `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, { "store a handle or copied data instead of the lease" })
    end

    function Tr.TypeUnaryRegionCallLeasePayload:typecheck_tree_explanation(ty)
        return unary_reason_report("cannot call region because continuation payload contains a lease", {
            "continuation payload `" .. require("lalin.error.format").type_name(ty) .. "` is temporary access and cannot be packed into the generated region-call result",
        }, { "use `emit` so temporary access stays in control flow" })
    end

    function Tr.TypeUnaryLeaseEscapeDurable:typecheck_tree_explanation(ty)
        return unary_reason_report("lease appears in durable type position", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` is temporary access, not storable data",
            "leases may appear in function/block/continuation parameters, not durable fields/results/statics",
        }, { "use a handle type for durable identity, or a plain pointer only at an unchecked ABI boundary" })
    end

    function Tr.TypeUnaryOwnedDropped:typecheck_tree_explanation(ty)
        return unary_reason_report("owned obligation is not discharged", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` must be transferred to an owned parameter/result or consumed by a closing protocol",
            "owned values do not have destructors and cannot silently fall out of scope",
        }, { "jump/return/yield/pass the owner to an `owned` slot, or call the explicit close/retire region" })
    end

    function Tr.TypeUnaryOwnedUseAfterMove:typecheck_tree_explanation(ty)
        return unary_reason_report("owned value used after transfer", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` was already consumed by an ownership transfer",
        }, { "thread the returned/re-yielded owner forward if the protocol preserves the obligation" })
    end

    function Tr.TypeUnaryOwnedObservedWithoutTransfer:typecheck_tree_explanation(ty)
        return unary_reason_report("owned value used without an ownership contract", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` is linear authority and cannot be copied or borrowed as a plain value",
        }, { "make the callee parameter `owned`, or use a protocol that returns the owner on every preserving edge" })
    end

    function Tr.TypeUnaryOwnedCapturedDurable:typecheck_tree_explanation(ty)
        return unary_reason_report("owned value captured in durable storage", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` is a CFG obligation, not storable data",
        }, { "store the plain handle separately and keep the owned obligation in control flow" })
    end

    function Tr.TypeUnaryOwnedBranchMismatch:typecheck_tree_explanation(ty)
        return unary_reason_report("branches leave different owned obligations live", {
            "all continuing paths must preserve the same live owned set",
        }, { "move the transfer before the branch, or return/jump/yield on the consuming path" })
    end

    function Tr.TypeUnaryOwnedVarCellUnsupported:typecheck_tree_explanation(ty)
        return unary_reason_report("owned values cannot live in mutable cells", {
            "`var owned T` needs explicit take/put semantics and is rejected",
        }, { "use `let` ownership threading through CFG parameters" })
    end

    function Tr.TypeUnaryOwnedRegionCallPayload:typecheck_tree_explanation(ty)
        return unary_reason_report("owned payload cannot use expression-style region call", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` cannot be packed into the generated region-call result aggregate",
        }, { "use `emit`/explicit continuations so ownership stays in CFG" })
    end

    function Tr.TypeUnaryOwnedEmitTargetMismatch:typecheck_tree_explanation(ty)
        return unary_reason_report("owned continuation payload has no matching target parameter", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` must land in a target block/continuation parameter with the same owned type and name",
        }, { "add the owned parameter to the filled target, or consume the owner inside the emitted fragment" })
    end

    function Tr.TypeUnaryOwnedInvalidComposition:typecheck_tree_explanation(ty)
        return unary_reason_report("invalid owned type composition", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` mixes ownership authority with access modifiers or temporary leases",
        }, { "own the durable handle/resource token; borrow access through a protocol that returns the owner" })
    end

    function Tr.TypeUnaryHandleCast:typecheck_tree_explanation(ty)
        return unary_reason_report("handle representation is opaque", {
            "handle `" .. require("lalin.error.format").type_name(ty) .. "` is not its integer representation in safe casts",
            "ordinary `as(...)` cannot convert handles to or from raw scalars",
        }, { "resolve the handle through a store region, or use trusted `repr(handle)` / `Handle.from_repr(raw)` inside store implementation code" })
    end

    function Tr.TypeUnaryHandleRepr:typecheck_tree_explanation(ty)
        return unary_reason_report("`repr` expects a handle", {
            "`repr(value)` is the explicit trusted handle-to-scalar boundary",
            "the value has type `" .. require("lalin.error.format").type_name(ty) .. "`, not a handle",
        })
    end

    function Tr.TypeUnaryHandleTargetMismatch:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver returns a lease to the wrong target", {
            "a handle with a `target` fact may only grant leases to that target type",
            "the continuation payload has type `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, { "change the lease payload target, or declare a different handle target fact" })
    end

    function Tr.TypeUnaryHandleDomainMissing:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver does not take the owning domain", {
            "a handle with a `domain` fact must be resolved through that store/domain parameter",
            "the continuation payload has type `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, { "add a `readonly` or `preserve` `ptr(Store)` parameter matching the handle domain" })
    end

    function Tr.TypeUnaryHandleDomainAccess:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver domain parameter does not preserve leases", {
            "resolver regions that grant leases must take the owning domain as `readonly` or `preserve`",
            "bare pointer/view parameters are conservative invalidators",
        }, { "mark the domain parameter `readonly` or `preserve`" })
    end

    function Tr.TypeUnaryHandleLeaseOriginMissing:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver lease is not tied to its store parameter", {
            "a handle resolver must return `lease(store) ptr(Target)` or `lease(store) view(Target)`",
            "anonymous leases cannot participate in store invalidation checks",
        }, { "write the lease as `lease(store_param) ptr(T)`" })
    end

    function Tr.TypeUnaryHandleLeaseOriginMismatch:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver lease is tied to the wrong store parameter", {
            "the lease origin must name the `readonly` or `preserve` domain parameter for the handle",
            "the continuation payload has type `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, { "change the `lease(...)` origin to the matching store parameter" })
    end

    function Tr.TypeUnaryAtomicRmwPointerOp:typecheck_tree_explanation(ty)
        return unary_reason_report("invalid atomic read-modify-write operation", {
            "atomic read-modify-write arithmetic is not defined for pointer type `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, {})
    end

    function Tr.TypeUnaryAtomicRmwBoolAddSub:typecheck_tree_explanation(ty)
        return unary_reason_report("invalid atomic read-modify-write operation", {
            "atomic add/sub is not defined for `bool`",
        }, {})
    end

    function Tr.TypeUnaryAtomicInvalidValue:typecheck_tree_explanation(ty)
        return unary_reason_report("invalid atomic value type", {
            (self.site or "atomic") .. " requires an atomic scalar or pointer type, got `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, {})
    end

    local function emit_item_issues(collector, base_analysis, item, issues)
        if not collector or #issues == 0 then return end
        local item_name = item_diagnostic_name(item)
        local item_analysis = item_name and base_analysis and base_analysis.item_analyses and base_analysis.item_analyses[item_name]
        local saved = collector.analysis_ctx
        if item_analysis then
            collector.analysis_ctx = {
                uri = item_analysis.uri,
                source_text = item_analysis.source_text,
                source_cache = base_analysis.source_cache or item_analysis.source_cache,
                anchors = item_analysis.anchors or {},
                document = item_analysis.document,
                item_analyses = base_analysis.item_analyses,
            }
        end
        for i = 1, #issues do collector:emit(issues[i], "typecheck") end
        collector.analysis_ctx = saved
    end

    local function type_module_with_layout_env(module, extra_layout_env, target, collector, analysis_ctx)
        local base_env = module_type_api.env(module, target)
        local facts = module:typecheck_tree_module_facts(Tr.TypeModuleFactsInput(base_env.module_name))
        local module_scope = Tr.TypeValueScope(base_env.module_name, base_env.values, base_env.types, base_env.layouts, facts)
        module_scope = module_scope:typecheck_tree_with_layouts(merged_layouts(module_scope, extra_layout_env))
        local items = {}
        local issues = {}
        local input = Tr.TypeItemInput(module_scope)
        for i = 1, #module.items do
            local item = module.items[i]
            local r = type_item(item, input)
            append_all(items, r.items)
            append_all(issues, r.issues)
            emit_item_issues(collector, analysis_ctx or {}, item, r.issues)
        end
        return Tr.TypeModuleResult(Tr.Module(Tr.ModuleTyped(module_scope.module_name), items), issues)
    end

    function Tr.Module:typecheck_tree_module(extra_layout_env, target, collector, analysis_ctx)
        return type_module_with_layout_env(self, extra_layout_env, target, collector, analysis_ctx)
    end

    return {
        check_module = function(module, opts)
            opts = opts or {}
            local collector = opts.collector
            local analysis_ctx = opts.analysis_ctx or (collector and collector.analysis_ctx) or {}
            local result = opts.layout_env
                and type_module_with_layout_env(module, opts.layout_env, opts.target or opts.c_target, collector, analysis_ctx)
                or type_module_with_layout_env(module, nil, opts.target or opts.c_target, collector, analysis_ctx)
            if collector and not analysis_ctx.item_analyses then
                for i = 1, #result.issues do
                    collector:emit(result.issues[i], "typecheck")
                end
            end
            return result
        end,
    }
end

-----------------------------------------------------------------------------
-- explain_type_issue: explains a single TypeIssue
-----------------------------------------------------------------------------

local function explain_type_issue(issue, analysis)
	analysis = analysis or { anchors = {} }
	local resolvers = require("lalin.error.span_resolvers")
	local span = resolvers.typecheck_resolver(issue, analysis)
    local function message_list(lines)
        local out = {}
        for i = 1, #(lines or {}) do out[i] = { message = lines[i] } end
        return out
    end
    local report = issue:typecheck_tree_explanation()
    return { code = report.code, severity = "error", phase_context = report.phase_context,
        primary = { span = span, message = report.primary }, notes = message_list(report.notes), suggestions = message_list(report.suggestions) }
end

return setmetatable({
    explain_type_issue = explain_type_issue,
}, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
