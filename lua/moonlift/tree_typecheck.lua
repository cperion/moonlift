local pvm = require("moonlift.pvm")

local M = {}

local function append_all(out, xs)
    for i = 1, #xs do out[#out + 1] = xs[i] end
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

function M.Define(T)
    local C = T.MoonCore
    local Ty = T.MoonType
    local B = T.MoonBind
    local O = T.MoonOpen
    local Sem = T.MoonSem
    local Tr = T.MoonTree

    local module_type_api = require("moonlift.tree_module_type").Define(T)
    local control_api = require("moonlift.tree_control_facts").Define(T)

    local type_view
    local type_index_base
    local type_place
    local type_expr
    local type_expr_expect
    local type_stmt
    local type_stmt_body
    local type_control_stmt_region
    local type_control_expr_region
    local type_switch_key
    local type_func
    local type_item
    local type_module

    local function void_ty() return Ty.TScalar(C.ScalarVoid) end
    local function bool_ty() return Ty.TScalar(C.ScalarBool) end
    local function i32_ty() return Ty.TScalar(C.ScalarI32) end
    local function index_ty() return Ty.TScalar(C.ScalarIndex) end
    local function f64_ty() return Ty.TScalar(C.ScalarF64) end
    local function cstr_ty() return Ty.TPtr(Ty.TScalar(C.ScalarU8)) end

    local function view_elem(view)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr or cls == Tr.ViewContiguous or cls == Tr.ViewStrided or cls == Tr.ViewRestrided or cls == Tr.ViewRowBase or cls == Tr.ViewInterleaved or cls == Tr.ViewInterleavedView then return view.elem end
        if cls == Tr.ViewWindow then return view_elem(view.base) end
        return void_ty()
    end

    local function attach_semantic_defs(env, variant_defs, handle_defs, func_effect_defs)
        if variant_defs ~= nil then rawset(env, "__variant_defs", variant_defs) end
        if handle_defs ~= nil then rawset(env, "__handle_defs", handle_defs) end
        if func_effect_defs ~= nil then rawset(env, "__func_effect_defs", func_effect_defs) end
        return env
    end

    local function env_with_values(env, values)
        return attach_semantic_defs(B.Env(env.module_name, values, env.types, env.layouts), rawget(env, "__variant_defs"), rawget(env, "__handle_defs"), rawget(env, "__func_effect_defs"))
    end

    local function env_add_value(env, entry)
        local values = clone_values(env.values)
        values[#values + 1] = entry
        return env_with_values(env, values)
    end

    local function ctx_with_env(ctx, env)
        return Tr.TypeCheckEnv(env, ctx.return_ty, ctx.yield, ctx.region_frags)
    end

    local function ctx_with_yield(ctx, yield)
        return Tr.TypeCheckEnv(ctx.env, ctx.return_ty, yield, ctx.region_frags)
    end

    local function env_lookup_value(env, name)
        for i = #env.values, 1, -1 do
            if env.values[i].name == name then return env.values[i].binding end
        end
        return nil
    end

    local function type_eq(a, b)
        return a == b
    end

    local function env_lookup_type(env, name)
        for i = #env.types, 1, -1 do
            if env.types[i].name == name then return env.types[i].ty end
        end
        return nil
    end

    local canonical_type
    canonical_type = function(env, ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TNamed and pvm.classof(ty.ref) == Ty.TypeRefPath and #ty.ref.path.parts == 1 then
            return env_lookup_type(env, ty.ref.path.parts[1].text) or ty
        elseif cls == Ty.THandle and pvm.classof(ty.ref) == Ty.TypeRefPath and #ty.ref.path.parts == 1 then
            local found = env_lookup_type(env, ty.ref.path.parts[1].text)
            if found ~= nil and pvm.classof(found) == Ty.THandle then return found end
            return ty
        elseif cls == Ty.TPtr then
            return Ty.TPtr(canonical_type(env, ty.elem))
        elseif cls == Ty.TArray then
            return Ty.TArray(ty.count, canonical_type(env, ty.elem))
        elseif cls == Ty.TSlice then
            return Ty.TSlice(canonical_type(env, ty.elem))
        elseif cls == Ty.TView then
            return Ty.TView(canonical_type(env, ty.elem))
        elseif cls == Ty.TLease then
            return Ty.TLease(canonical_type(env, ty.base), ty.origin)
        elseif cls == Ty.TOwned then
            return Ty.TOwned(canonical_type(env, ty.base))
        elseif cls == Ty.TAccess then
            return Ty.TAccess(ty.access, canonical_type(env, ty.base))
        elseif cls == Ty.TFunc or cls == Ty.TClosure then
            local params = {}
            for i = 1, #ty.params do params[i] = canonical_type(env, ty.params[i]) end
            local result = canonical_type(env, ty.result)
            return cls == Ty.TFunc and Ty.TFunc(params, result) or Ty.TClosure(params, result)
        end
        return ty
    end

    local function canonical_params(env, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = Ty.Param(params[i].name, canonical_type(env, params[i].ty)) end
        return out
    end

    local function type_contains_lease(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TLease then return true end
        if cls == Ty.TOwned then return type_contains_lease(ty.base) end
        if cls == Ty.TAccess then return type_contains_lease(ty.base) end
        if cls == Ty.TPtr or cls == Ty.TArray or cls == Ty.TSlice or cls == Ty.TView then return type_contains_lease(ty.elem) end
        if cls == Ty.TFunc or cls == Ty.TClosure then
            if type_contains_lease(ty.result) then return true end
            for i = 1, #ty.params do if type_contains_lease(ty.params[i]) then return true end end
        end
        return false
    end

    local function type_contains_owned(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TOwned then return true end
        if cls == Ty.TLease then return type_contains_owned(ty.base) end
        if cls == Ty.TAccess then return type_contains_owned(ty.base) end
        if cls == Ty.TPtr or cls == Ty.TArray or cls == Ty.TSlice or cls == Ty.TView then return type_contains_owned(ty.elem) end
        if cls == Ty.TFunc or cls == Ty.TClosure then
            if type_contains_owned(ty.result) then return true end
            for i = 1, #ty.params do if type_contains_owned(ty.params[i]) then return true end end
        end
        return false
    end

    local function is_owned_type(ty)
        return pvm.classof(ty) == Ty.TOwned
    end

    local function lease_access_base(ty)
        if pvm.classof(ty) == Ty.TLease then return ty.base end
        if pvm.classof(ty) == Ty.TAccess then return lease_access_base(ty.base) end
        return ty
    end

    local function arg_matches_param(expected, actual)
        if type_eq(expected, actual) then return true end
        if is_owned_type(expected) or is_owned_type(actual) then return false end
        if pvm.classof(expected) == Ty.TAccess then return arg_matches_param(expected.base, actual) end
        if pvm.classof(actual) == Ty.TAccess then return arg_matches_param(expected, actual.base) end
        if pvm.classof(expected) == Ty.TLease and pvm.classof(actual) == Ty.TLease and type_eq(expected.base, actual.base) then return true end
        if pvm.classof(expected) == Ty.TLease and type_eq(expected.base, actual) then return true end
        return false
    end

    local function named_ref(ty)
        if pvm.classof(ty) == Ty.TNamed then return ty.ref end
        return nil
    end

    local function field_layout_for(env, ty, field_name)
        local ref = named_ref(ty)
        if ref == nil then return nil end
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            local cls = pvm.classof(layout)
            local matches = false
            if cls == Sem.LayoutNamed and pvm.classof(ref) == Ty.TypeRefGlobal then
                matches = layout.module_name == ref.module_name and layout.type_name == ref.type_name
            elseif cls == Sem.LayoutNamed and pvm.classof(ref) == Ty.TypeRefPath then
                matches = #ref.path.parts == 1 and layout.type_name == ref.path.parts[1].text
            elseif cls == Sem.LayoutLocal and pvm.classof(ref) == Ty.TypeRefLocal then
                matches = layout.sym == ref.sym
            end
            if matches then
                for j = 1, #layout.fields do
                    if layout.fields[j].field_name == field_name then return layout.fields[j] end
                end
            end
        end
        return nil
    end

    local function scalar_kind(ty)
        if pvm.classof(ty) == Ty.TScalar then return ty.scalar end
        return nil
    end

    local function is_bool(ty)
        return scalar_kind(ty) == C.ScalarBool
    end

    local function is_numeric_scalar(ty)
        local s = scalar_kind(ty)
        return s == C.ScalarI8 or s == C.ScalarI16 or s == C.ScalarI32 or s == C.ScalarI64
            or s == C.ScalarU8 or s == C.ScalarU16 or s == C.ScalarU32 or s == C.ScalarU64
            or s == C.ScalarF32 or s == C.ScalarF64 or s == C.ScalarIndex
    end

    local function is_integer_scalar(ty)
        local s = scalar_kind(ty)
        return s == C.ScalarI8 or s == C.ScalarI16 or s == C.ScalarI32 or s == C.ScalarI64
            or s == C.ScalarU8 or s == C.ScalarU16 or s == C.ScalarU32 or s == C.ScalarU64
            or s == C.ScalarIndex
    end

    local int_scalar_info = {
        [C.ScalarBool] = { bits = 1, signed = false },
        [C.ScalarI8] = { bits = 8, signed = true },
        [C.ScalarI16] = { bits = 16, signed = true },
        [C.ScalarI32] = { bits = 32, signed = true },
        [C.ScalarI64] = { bits = 64, signed = true },
        [C.ScalarU8] = { bits = 8, signed = false },
        [C.ScalarU16] = { bits = 16, signed = false },
        [C.ScalarU32] = { bits = 32, signed = false },
        [C.ScalarU64] = { bits = 64, signed = false },
        [C.ScalarIndex] = { bits = 64, signed = true },
    }

    local float_scalar_bits = {
        [C.ScalarF32] = 32,
        [C.ScalarF64] = 64,
    }

    local function semantic_cast_op(src_ty, dst_ty)
        local src, dst = scalar_kind(src_ty), scalar_kind(dst_ty)
        if src == nil or dst == nil then return C.MachineCastBitcast end
        if src == dst then return C.MachineCastIdentity end
        local si, di = int_scalar_info[src], int_scalar_info[dst]
        if si ~= nil and di ~= nil then
            if di.bits < si.bits then return C.MachineCastIreduce end
            if di.bits > si.bits then return si.signed and C.MachineCastSextend or C.MachineCastUextend end
            return C.MachineCastIdentity
        end
        local sf, df = float_scalar_bits[src], float_scalar_bits[dst]
        if sf ~= nil and df ~= nil then
            if df > sf then return C.MachineCastFpromote end
            if df < sf then return C.MachineCastFdemote end
            return C.MachineCastIdentity
        end
        if si ~= nil and df ~= nil then return si.signed and C.MachineCastSToF or C.MachineCastUToF end
        if sf ~= nil and di ~= nil then return di.signed and C.MachineCastFToS or C.MachineCastFToU end
        return C.MachineCastBitcast
    end

    local function surface_cast_to_machine_op(surface_op, src_ty, dst_ty)
        if surface_op == C.SurfaceCast then return semantic_cast_op(src_ty, dst_ty) end
        if surface_op == C.SurfaceTrunc then return C.MachineCastIreduce end
        if surface_op == C.SurfaceZExt then return C.MachineCastUextend end
        if surface_op == C.SurfaceSExt then return C.MachineCastSextend end
        if surface_op == C.SurfaceBitcast then return C.MachineCastBitcast end
        if surface_op == C.SurfaceSatCast then return C.MachineCastBitcast end
        return C.MachineCastBitcast
    end

    local function is_atomic_value_type(ty)
        return is_integer_scalar(ty) or is_bool(ty) or pvm.classof(ty) == Ty.TPtr
    end

    local function check_atomic_value_type(site, ty, issues)
        if not is_atomic_value_type(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(site, ty) end
    end

    local function check_atomic_rmw_value_type(op, ty, issues)
        check_atomic_value_type("atomic_rmw", ty, issues)
        if op == C.AtomicRmwXchg then return end
        if pvm.classof(ty) == Ty.TPtr then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("atomic_rmw pointer op", ty); return end
        if is_bool(ty) and (op == C.AtomicRmwAdd or op == C.AtomicRmwSub) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("atomic_rmw bool add/sub", ty) end
    end

    local function result_expr(expr, ty, issues)
        return Tr.TypeExprResult(expr, ty, issues or {})
    end

    local function result_place(place, ty, issues)
        return Tr.TypePlaceResult(place, ty, issues or {})
    end

    local function typed_expr_header_ty(h)
        local cls = pvm.classof(h)
        if cls == Tr.ExprTyped or cls == Tr.ExprOpen then return h.ty end
        return nil
    end

    local function typed_place_header_ty(h)
        local cls = pvm.classof(h)
        if cls == Tr.PlaceTyped or cls == Tr.PlaceOpen then return h.ty end
        return nil
    end

    local function merge_env_layouts(env, extra_layout_env)
        local extra = extra_layout_env and extra_layout_env.layouts
        if extra == nil or #extra == 0 then return env end
        local layouts = clone_values(env.layouts)
        for i = 1, #extra do layouts[#layouts + 1] = extra[i] end
        return attach_semantic_defs(B.Env(env.module_name, env.values, env.types, layouts), rawget(env, "__variant_defs"), rawget(env, "__handle_defs"), rawget(env, "__func_effect_defs"))
    end

    local function int_literal_can_adopt(expr, expected)
        return pvm.classof(expr) == Tr.ExprLit
            and pvm.classof(expr.value) == C.LitInt
            and is_integer_scalar(expected)
    end

    local function is_nil_literal(expr)
        if pvm.classof(expr) ~= Tr.ExprLit then return false end
        if expr.value == C.LitNil then return true end
        local cls = pvm.classof(expr.value)
        return cls ~= false and cls.kind == "LitNil"
    end

    local function array_len_const(len)
        if pvm.classof(len) == Ty.ArrayLenConst then return len.count end
        return nil
    end

    local function check_type_policy(ty, issues, site)
        local cls = pvm.classof(ty)
        if cls == Ty.TArray then
            if pvm.classof(ty.count) == Ty.ArrayLenExpr then
                issues[#issues + 1] = Tr.TypeIssueExpected((site or "type") .. " array length", Ty.TArray(Ty.ArrayLenConst(0), ty.elem), ty)
            end
            check_type_policy(ty.elem, issues, site)
        elseif cls == Ty.TPtr or cls == Ty.TSlice or cls == Ty.TView then
            check_type_policy(ty.elem, issues, site)
        elseif cls == Ty.TLease then
            check_type_policy(ty.base, issues, site)
            if pvm.classof(ty.base) ~= Ty.TPtr and pvm.classof(ty.base) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected((site or "type") .. " lease base", Ty.TPtr(Ty.TScalar(C.ScalarVoid)), ty.base) end
            if type_contains_owned(ty.base) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned lease composition", ty) end
        elseif cls == Ty.TOwned then
            check_type_policy(ty.base, issues, site)
            local bcls = pvm.classof(ty.base)
            if bcls == Ty.TOwned or bcls == Ty.TLease or bcls == Ty.TAccess or bcls == Ty.TPtr or bcls == Ty.TView then
                issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned invalid base", ty)
            end
            if type_contains_lease(ty.base) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned lease composition", ty) end
        elseif cls == Ty.TAccess then
            check_type_policy(ty.base, issues, site)
            if type_contains_owned(ty.base) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned access composition", ty) end
        elseif cls == Ty.THandle then
            if pvm.classof(ty.repr) ~= Ty.HandleReprScalar then issues[#issues + 1] = Tr.TypeIssueExpected((site or "type") .. " handle repr", Ty.THandle(ty.ref, Ty.HandleReprScalar(C.ScalarU32)), ty) end
        elseif cls == Ty.TFunc or cls == Ty.TClosure then
            for i = 1, #ty.params do check_type_policy(ty.params[i], issues, site) end
            check_type_policy(ty.result, issues, site)
        end
    end

    local function type_ref_text(ref)
        local cls = pvm.classof(ref)
        if cls == Ty.TypeRefGlobal then return ref.type_name end
        if cls == Ty.TypeRefLocal then return ref.sym and ref.sym.name or tostring(ref.sym) end
        if cls == Ty.TypeRefPath and ref.path and #ref.path.parts > 0 then
            local parts = {}
            for i = 1, #ref.path.parts do parts[i] = ref.path.parts[i].text end
            return table.concat(parts, ".")
        end
        return nil
    end

    local function region_frag_name_text(frag)
        if frag == nil then return nil end
        local cls = pvm.classof(frag.name)
        if cls == O.NameRefText then return frag.name.text end
        return nil
    end

    local function lookup_region_frag_in_list(region_frags, ref)
        if ref == nil then return nil end
        local cls = pvm.classof(ref)
        if cls ~= O.RegionFragRefName then return nil end
        for i = 1, #(region_frags or {}) do
            local frag = region_frags[i]
            if region_frag_name_text(frag) == ref.name then return frag end
        end
        return nil
    end

    local function lookup_region_frag(ctx, ref)
        return lookup_region_frag_in_list(ctx.region_frags, ref)
    end

    local function type_ref_leaf(ref)
        local text = type_ref_text(ref)
        if text == nil then return nil end
        return text:match("([^%.]+)$") or text
    end

    local function type_ref_matches_ty(ref, ty)
        local cls = pvm.classof(ty)
        local ty_ref = nil
        if cls == Ty.TNamed then ty_ref = ty.ref
        elseif cls == Ty.THandle then ty_ref = ty.ref end
        if ty_ref == nil then return false end
        local a, b = type_ref_leaf(ref), type_ref_leaf(ty_ref)
        return a ~= nil and b ~= nil and a == b
    end

    local function is_void_type(ty)
        return pvm.classof(ty) == Ty.TScalar and ty.scalar == C.ScalarVoid
    end

    local function is_handle_type(ty)
        return pvm.classof(ty) == Ty.THandle
    end

    local function handle_repr_type(handle_ty)
        if pvm.classof(handle_ty) ~= Ty.THandle then return nil end
        if pvm.classof(handle_ty.repr) == Ty.HandleReprScalar then return Ty.TScalar(handle_ty.repr.scalar) end
        return nil
    end

    local function type_name_for_ctor(type_name)
        return Ty.TNamed(Ty.TypeRefGlobal("", type_name))
    end

    local function variant_name_text(v)
        if type(v) == "string" then return v end
        return v and (v.text or v.name) or tostring(v)
    end

    local function build_variant_defs(module, module_name)
        local defs = {}
        local function add_type_decl(t, mod_name)
            local cls = pvm.classof(t)
            if cls == Tr.TypeDeclEnumSugar then
                local variants = {}
                for i = 1, #t.variants do
                    local name = variant_name_text(t.variants[i])
                    variants[name] = { name = name, tag = i - 1, payload = void_ty(), fields = {} }
                end
                defs[t.name] = { type_name = t.name, ty = Ty.TNamed(Ty.TypeRefGlobal(mod_name, t.name)), variants = variants }
            elseif cls == Tr.TypeDeclTaggedUnionSugar then
                local variants = {}
                for i = 1, #t.variants do
                    local v = t.variants[i]
                    variants[v.name] = { name = v.name, tag = i - 1, payload = v.payload, fields = v.fields or {} }
                end
                defs[t.name] = { type_name = t.name, ty = Ty.TNamed(Ty.TypeRefGlobal(mod_name, t.name)), variants = variants }
            end
        end
        for i = 1, #module.items do
            local item = module.items[i]
            local cls = pvm.classof(item)
            if cls == Tr.ItemType then add_type_decl(item.t, module_name)
            elseif cls == Tr.ItemUseModule then
                local nested = build_variant_defs(item.module, module_name)
                for k, v in pairs(nested) do defs[k] = v end
            end
        end
        return defs
    end

    local function build_handle_defs(module, module_name)
        local defs = {}
        local function add_type_decl(t, mod_name)
            if pvm.classof(t) == Tr.TypeDeclHandle then
                local domain, target = nil, nil
                for i = 1, #(t.facts or {}) do
                    local fact = t.facts[i]
                    local fcls = pvm.classof(fact)
                    if fcls == Ty.HandleDomain then domain = fact.domain
                    elseif fcls == Ty.HandleTarget then target = fact.target end
                end
                defs[t.name] = { name = t.name, ty = Ty.THandle(Ty.TypeRefGlobal(mod_name, t.name), t.repr), repr = t.repr, invalid = t.invalid, domain = domain, target = target }
            end
        end
        for i = 1, #module.items do
            local item = module.items[i]
            local cls = pvm.classof(item)
            if cls == Tr.ItemType then add_type_decl(item.t, module_name)
            elseif cls == Tr.ItemUseModule then
                local nested = build_handle_defs(item.module, module_name)
                for k, v in pairs(nested) do defs[k] = v end
            end
        end
        return defs
    end

    local function func_parts_for_effect(func)
        local cls = pvm.classof(func)
        if cls == Tr.FuncLocal or cls == Tr.FuncExport then return func.name, func.params, {} end
        if cls == Tr.FuncLocalContract or cls == Tr.FuncExportContract then return func.name, func.params, func.contracts or {} end
        if cls == Tr.FuncDecl then return func.name, func.params, {} end
        return nil, nil, nil
    end

    local function effect_param_names(contracts)
        local out = { readonly = {}, preserve = {}, invalidate = {} }
        for i = 1, #(contracts or {}) do
            local c = contracts[i]
            local cls = pvm.classof(c)
            if pvm.classof(c.base) == Tr.ExprRef and pvm.classof(c.base.ref) == B.ValueRefName then
                local name = c.base.ref.name
                if cls == Tr.ContractReadonly then out.readonly[name] = true; out.preserve[name] = true
                elseif cls == Tr.ContractPreserve then out.preserve[name] = true
                elseif cls == Tr.ContractInvalidate then out.invalidate[name] = true end
            end
        end
        return out
    end

    local function build_func_effect_defs(module)
        local defs = {}
        for i = 1, #module.items do
            local item = module.items[i]
            local cls = pvm.classof(item)
            if cls == Tr.ItemFunc then
                local name, params, contracts = func_parts_for_effect(item.func)
                if name ~= nil then
                    local effects = effect_param_names(contracts)
                    defs[name] = { params = params or {}, readonly = effects.readonly, preserve = effects.preserve, invalidate = effects.invalidate }
                end
            elseif cls == Tr.ItemExtern then
                if pvm.classof(item.func) == Tr.ExternFunc then
                    defs[item.func.name] = { params = item.func.params or {}, readonly = {}, preserve = {}, invalidate = {} }
                end
            elseif cls == Tr.ItemUseModule then
                local nested = build_func_effect_defs(item.module)
                for k, v in pairs(nested) do defs[k] = v end
            end
        end
        return defs
    end

    local function find_handle_def(ctx, name)
        local defs = rawget(ctx.env, "__handle_defs") or {}
        return defs[name]
    end

    local function find_handle_def_for_type(ctx, ty)
        if pvm.classof(ty) ~= Ty.THandle then return nil end
        local defs = rawget(ctx.env, "__handle_defs") or {}
        local ref = ty.ref
        local rcls = pvm.classof(ref)
        if rcls == Ty.TypeRefGlobal then return defs[ref.type_name] end
        if rcls == Ty.TypeRefLocal then return defs[ref.sym.name] end
        if rcls == Ty.TypeRefPath and #ref.path.parts == 1 then return defs[type_ref_leaf(ref)] end
        return nil
    end

    local function lease_target_type(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TAccess then return lease_target_type(ty.base) end
        if cls ~= Ty.TLease then return nil end
        local base = lease_access_base(ty.base)
        local bcls = pvm.classof(base)
        if bcls == Ty.TPtr or bcls == Ty.TView then return base.elem end
        return nil
    end

    local function param_domain_matches(param_ty, domain_ref)
        local base = lease_access_base(param_ty)
        local cls = pvm.classof(base)
        if cls ~= Ty.TPtr and cls ~= Ty.TView then return false end
        return type_ref_matches_ty(domain_ref, base.elem)
    end

    local function check_handle_resolution_signature(ctx, params, payload_params, issues, site)
        local handle_defs = {}
        local has_domain_param = {}
        local all_defs = rawget(ctx.env, "__handle_defs") or {}
        for i = 1, #(params or {}) do
            local pty = canonical_type(ctx.env, params[i].ty)
            local def = find_handle_def_for_type(ctx, pty)
            if def and def.target then handle_defs[#handle_defs + 1] = def end
            for _, hdef in pairs(all_defs) do
                if hdef.domain and param_domain_matches(pty, hdef.domain) then
                    has_domain_param[type_ref_leaf(hdef.domain) or ""] = true
                end
            end
        end
        if #handle_defs == 0 then return end
        for i = 1, #(payload_params or {}) do
            local target_ty = lease_target_type(canonical_type(ctx.env, payload_params[i].ty))
            if target_ty ~= nil then
                local matched = nil
                for j = 1, #handle_defs do
                    if type_ref_matches_ty(handle_defs[j].target, target_ty) then
                        matched = handle_defs[j]
                        break
                    end
                end
                if matched == nil then
                    issues[#issues + 1] = Tr.TypeIssueExpected((site or "handle resolution") .. " handle target", Ty.THandle(handle_defs[1].ty.ref, handle_defs[1].repr), target_ty)
                elseif matched.domain and not has_domain_param[type_ref_leaf(matched.domain) or ""] then
                    issues[#issues + 1] = Tr.TypeIssueExpected((site or "handle resolution") .. " handle domain", Ty.TNamed(matched.domain), Ty.TScalar(C.ScalarRawPtr))
                end
            end
        end
    end

    local function find_variant(ctx, type_name, variant_name)
        local defs = rawget(ctx.env, "__variant_defs") or {}
        local def = defs[type_name]
        if def == nil then return nil, nil end
        return def, def.variants[variant_name]
    end

    local function variant_def_for_value_ty(ctx, ty)
        if pvm.classof(ty) ~= Ty.TNamed then return nil end
        local defs = rawget(ctx.env, "__variant_defs") or {}
        local ref = ty.ref
        local rcls = pvm.classof(ref)
        if rcls == Ty.TypeRefGlobal or rcls == Ty.TypeRefLocal then return defs[ref.type_name or ref.sym.name] end
        if rcls == Ty.TypeRefPath and #ref.path.parts == 1 then return defs[ref.path.parts[1].text] end
        return nil
    end

    local function bind_env_for_variant(ctx, region_id, variant, requested_binds)
        local env = ctx.env
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
            local b = B.Binding(C.Id("variant:" .. tostring(region_id or "switch") .. ":" .. variant.name .. ":" .. binds[i].name), binds[i].name, binds[i].ty, B.BindingClassLocalValue)
            env = env_add_value(env, B.ValueEntry(b.name, b))
        end
        return env, binds
    end

    local function live_lease_tys(ctx)
        local out = {}
        for i = #ctx.env.values, 1, -1 do
            local ty = canonical_type(ctx.env, ctx.env.values[i].binding.ty)
            if pvm.classof(ty) == Ty.TLease then out[#out + 1] = ty end
        end
        return out
    end

    local function lease_origin_name(lease_ty)
        if pvm.classof(lease_ty) ~= Ty.TLease then return nil end
        if pvm.classof(lease_ty.origin) == Ty.LeaseOriginParam then return lease_ty.origin.name end
        return nil
    end

    local function expr_binding_name(expr)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefBinding then return expr.ref.binding.name end
        return nil
    end

    local function callee_effect_def(ctx, callee_expr)
        if pvm.classof(callee_expr) == Tr.ExprRef and pvm.classof(callee_expr.ref) == B.ValueRefBinding then
            local defs = rawget(ctx.env, "__func_effect_defs") or {}
            return defs[callee_expr.ref.binding.name]
        end
        return nil
    end

    local function call_may_invalidate_while_lease_live(ctx, callee_expr, param_tys, typed_args)
        local leases = live_lease_tys(ctx)
        if #leases == 0 then return nil end
        local effect = callee_effect_def(ctx, callee_expr)
        local preserve = effect and effect.preserve or {}
        local explicit_invalidate = effect and effect.invalidate or {}
        for i = 1, #(param_tys or {}) do
            local pty = canonical_type(ctx.env, param_tys[i])
            local pcls = pvm.classof(pty)
            if pcls ~= Ty.TLease and (pcls == Ty.TPtr or pcls == Ty.TView) then
                local pname = effect and effect.params and effect.params[i] and effect.params[i].name
                local preserves_param = pname and preserve[pname]
                local invalidates_param = (pname and explicit_invalidate[pname]) or not preserves_param
                if invalidates_param then
                    local arg_name = typed_args and typed_args[i] and expr_binding_name(typed_args[i]) or nil
                    for j = 1, #leases do
                        local origin = lease_origin_name(leases[j])
                        if origin == nil or arg_name == nil or origin == arg_name then return leases[j] end
                    end
                end
            end
        end
        return nil
    end

    type_expr_expect = function(expr, ctx, expected)
        if expected ~= nil and pvm.classof(expr) == Tr.ExprAgg and pvm.classof(expected) == Ty.TNamed then
            return pvm.one(type_expr(pvm.with(expr, { ty = expected }), ctx))
        end
        if expected ~= nil and pvm.classof(expr) == Tr.ExprArray and pvm.classof(expected) == Ty.TArray then
            local expected_count = array_len_const(expected.count)
            local issues = {}
            if expected_count ~= nil and expected_count ~= #expr.elems then
                issues[#issues + 1] = Tr.TypeIssueExpected("array length", expected, Ty.TArray(Ty.ArrayLenConst(#expr.elems), expected.elem))
            end
            local elems = {}
            for i = 1, #expr.elems do
                local e = type_expr_expect(expr.elems[i], ctx, expected.elem)
                append_all(issues, e.issues)
                if not type_eq(expected.elem, e.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("array elem", expected.elem, e.ty) end
                elems[#elems + 1] = e.expr
            end
            local ty = Ty.TArray(Ty.ArrayLenConst(#elems), expected.elem)
            return result_expr(Tr.ExprArray(Tr.ExprTyped(ty), expected.elem, elems), ty, issues)
        end
        local result = pvm.one(type_expr(expr, ctx))
        if expected ~= nil and int_literal_can_adopt(expr, expected) then
            return result_expr(Tr.ExprLit(Tr.ExprTyped(expected), expr.value), expected, result.issues)
        end
        if expected ~= nil and is_nil_literal(expr) and pvm.classof(expected) == Ty.TPtr then
            return result_expr(Tr.ExprLit(Tr.ExprTyped(expected), expr.value), expected, result.issues)
        end
        return result
    end

    local function ref_type(ref, env)
        local cls = pvm.classof(ref)
        if cls == B.ValueRefBinding then return ref.binding.ty, ref, {} end
        if cls == B.ValueRefHole then
            local slot_cls = pvm.classof(ref.slot)
            if slot_cls == O.SlotFunc then return ref.slot.slot.fn_ty, ref, {} end
            if slot_cls == O.SlotValue or slot_cls == O.SlotConst or slot_cls == O.SlotStatic then return ref.slot.slot.ty, ref, {} end
            if slot_cls == O.SlotExpr or slot_cls == O.SlotPlace then return ref.slot.slot.ty or void_ty(), ref, {} end
            return void_ty(), ref, {}
        end
        if cls == B.ValueRefName then
            local binding = env_lookup_value(env, ref.name)
            if binding ~= nil then return binding.ty, B.ValueRefBinding(binding), {} end
            return void_ty(), ref, { Tr.TypeIssueUnresolvedValue(ref.name) }
        end
        if cls == B.ValueRefPath then return void_ty(), ref, { Tr.TypeIssueUnresolvedPath(ref.path) } end
        return void_ty(), ref, { Tr.TypeIssueUnresolvedValue("<unknown>") }
    end

    local function callable_result(fn_ty)
        local cls = pvm.classof(fn_ty)
        if cls == Ty.TFunc or cls == Ty.TClosure then return fn_ty.result, fn_ty.params end
        return nil, nil
    end

    local function check_expected(site, expected, actual, issues)
        if not type_eq(expected, actual) then issues[#issues + 1] = Tr.TypeIssueExpected(site, expected, actual) end
    end

    local function type_binary_op(op, lhs_ty, rhs_ty, issues)
        -- Pointer arithmetic: ptr + int, int + ptr, ptr - int
        if op == C.BinAdd then
            local lhs_is_ptr = pvm.classof(lhs_ty) == Ty.TPtr
            local rhs_is_ptr = pvm.classof(rhs_ty) == Ty.TPtr
            if lhs_is_ptr and is_integer_scalar(rhs_ty) then return lhs_ty end
            if rhs_is_ptr and is_integer_scalar(lhs_ty) then return rhs_ty end
        end
        if op == C.BinSub then
            if pvm.classof(lhs_ty) == Ty.TPtr and is_integer_scalar(rhs_ty) then return lhs_ty end
        end
        if not type_eq(lhs_ty, rhs_ty) then
            issues[#issues + 1] = Tr.TypeIssueInvalidBinary(tostring(op), lhs_ty, rhs_ty)
            return lhs_ty
        end
        if op == C.BinAdd or op == C.BinSub or op == C.BinMul or op == C.BinDiv or op == C.BinRem then
            if is_numeric_scalar(lhs_ty) then return lhs_ty end
        else
            if is_integer_scalar(lhs_ty) then return lhs_ty end
        end
        issues[#issues + 1] = Tr.TypeIssueInvalidBinary(tostring(op), lhs_ty, rhs_ty)
        return lhs_ty
    end

    local function type_compare_op(op, lhs_ty, rhs_ty, issues)
        if not type_eq(lhs_ty, rhs_ty) then issues[#issues + 1] = Tr.TypeIssueInvalidCompare(tostring(op), lhs_ty, rhs_ty) end
        return bool_ty()
    end

    type_view = pvm.phase("moonlift_tree_typecheck_view", {
        [Tr.ViewFromExpr] = function(self, ctx)
            local base = pvm.one(type_expr(self.base, ctx))
            local issues = {}; append_all(issues, base.issues)
            local elem = self.elem
            local base_access = lease_access_base(base.ty)
            if pvm.classof(base_access) == Ty.TView then elem = base_access.elem elseif pvm.classof(base_access) == Ty.TPtr then elem = base_access.elem end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { base = base.expr, elem = elem }), issues))
        end,
        [Tr.ViewContiguous] = function(self, ctx)
            local data = pvm.one(type_expr(self.data, ctx)); local len = type_expr_expect(self.len, ctx, index_ty())
            local issues = {}; append_all(issues, data.issues); append_all(issues, len.issues)
            local elem = self.elem
            local data_access = lease_access_base(data.ty)
            if pvm.classof(data_access) == Ty.TPtr then elem = data_access.elem
            elseif pvm.classof(data_access) == Ty.TView then elem = data_access.elem
            else issues[#issues + 1] = Tr.TypeIssueExpected("view data", Ty.TScalar(C.ScalarRawPtr), data.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view len", index_ty(), len.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { data = data.expr, elem = elem, len = len.expr }), issues))
        end,
        [Tr.ViewStrided] = function(self, ctx)
            local data = pvm.one(type_expr(self.data, ctx)); local len = type_expr_expect(self.len, ctx, index_ty()); local stride = type_expr_expect(self.stride, ctx, index_ty())
            local issues = {}; append_all(issues, data.issues); append_all(issues, len.issues); append_all(issues, stride.issues)
            local elem = self.elem
            local data_access = lease_access_base(data.ty)
            if pvm.classof(data_access) == Ty.TPtr then elem = data_access.elem
            elseif pvm.classof(data_access) == Ty.TView then elem = data_access.elem
            else issues[#issues + 1] = Tr.TypeIssueExpected("view data", Ty.TScalar(C.ScalarRawPtr), data.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view len", index_ty(), len.ty) end
            if not is_integer_scalar(stride.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view stride", index_ty(), stride.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { data = data.expr, elem = elem, len = len.expr, stride = stride.expr }), issues))
        end,
        [Tr.ViewRestrided] = function(self, ctx)
            local base = pvm.one(type_view(self.base, ctx)); local stride = type_expr_expect(self.stride, ctx, index_ty())
            local issues = {}; append_all(issues, base.issues); append_all(issues, stride.issues)
            if not is_integer_scalar(stride.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view stride", index_ty(), stride.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { base = base.view, stride = stride.expr }), issues))
        end,
        [Tr.ViewWindow] = function(self, ctx)
            local base = pvm.one(type_view(self.base, ctx)); local start = type_expr_expect(self.start, ctx, index_ty()); local len = type_expr_expect(self.len, ctx, index_ty())
            local issues = {}; append_all(issues, base.issues); append_all(issues, start.issues); append_all(issues, len.issues)
            if not is_integer_scalar(start.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view window start", index_ty(), start.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view window len", index_ty(), len.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { base = base.view, start = start.expr, len = len.expr }), issues))
        end,
        [Tr.ViewRowBase] = function(self, ctx)
            local base = pvm.one(type_view(self.base, ctx)); local row_offset = type_expr_expect(self.row_offset, ctx, index_ty())
            local issues = {}; append_all(issues, base.issues); append_all(issues, row_offset.issues)
            if not is_integer_scalar(row_offset.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view row offset", index_ty(), row_offset.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { base = base.view, row_offset = row_offset.expr }), issues))
        end,
        [Tr.ViewInterleaved] = function(self, ctx)
            local data = pvm.one(type_expr(self.data, ctx)); local len = type_expr_expect(self.len, ctx, index_ty()); local stride = type_expr_expect(self.stride, ctx, index_ty()); local lane = type_expr_expect(self.lane, ctx, index_ty())
            local issues = {}; append_all(issues, data.issues); append_all(issues, len.issues); append_all(issues, stride.issues); append_all(issues, lane.issues)
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view len", index_ty(), len.ty) end
            if not is_integer_scalar(stride.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view stride", index_ty(), stride.ty) end
            if not is_integer_scalar(lane.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view lane", index_ty(), lane.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { data = data.expr, len = len.expr, stride = stride.expr, lane = lane.expr }), issues))
        end,
        [Tr.ViewInterleavedView] = function(self, ctx)
            local base = pvm.one(type_view(self.base, ctx)); local stride = type_expr_expect(self.stride, ctx, index_ty()); local lane = type_expr_expect(self.lane, ctx, index_ty())
            local issues = {}; append_all(issues, base.issues); append_all(issues, stride.issues); append_all(issues, lane.issues)
            if not is_integer_scalar(stride.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view stride", index_ty(), stride.ty) end
            if not is_integer_scalar(lane.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view lane", index_ty(), lane.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { base = base.view, stride = stride.expr, lane = lane.expr }), issues))
        end,
    }, { args_cache = "last" })

    local function index_base_elem(base)
        if pvm.classof(base) == Tr.IndexBaseView then return base.view.elem end
        if pvm.classof(base) == Tr.IndexBasePlace then return base.elem end
        if pvm.classof(base) == Tr.IndexBaseExpr then return void_ty() end
        return void_ty()
    end

    type_index_base = pvm.phase("moonlift_tree_typecheck_index_base", {
        [Tr.IndexBaseExpr] = function(self, ctx)
            local base = pvm.one(type_expr(self.base, ctx))
            local issues = {}; append_all(issues, base.issues)
            local base_access = lease_access_base(base.ty)
            if pvm.classof(base_access) == Ty.TView or pvm.classof(base_access) == Ty.TPtr then
                return pvm.once(Tr.TypeIndexBaseResult(Tr.IndexBaseView(Tr.ViewFromExpr(base.expr, base_access.elem)), base_access.elem, issues))
            end
            if pvm.classof(base_access) == Ty.TArray then
                if pvm.classof(base.expr) == Tr.ExprRef then
                    return pvm.once(Tr.TypeIndexBaseResult(Tr.IndexBasePlace(Tr.PlaceRef(Tr.PlaceTyped(base_access), base.expr.ref), base_access.elem), base_access.elem, issues))
                end
                issues[#issues + 1] = Tr.TypeIssueNotIndexable(base.ty)
                return pvm.once(Tr.TypeIndexBaseResult(Tr.IndexBaseView(Tr.ViewFromExpr(base.expr, base_access.elem)), base_access.elem, issues))
            end
            issues[#issues + 1] = Tr.TypeIssueNotIndexable(base.ty)
            return pvm.once(Tr.TypeIndexBaseResult(Tr.IndexBaseView(Tr.ViewFromExpr(base.expr, void_ty())), void_ty(), issues))
        end,
        [Tr.IndexBaseView] = function(self, ctx)
            local view = pvm.one(type_view(self.view, ctx))
            return pvm.once(Tr.TypeIndexBaseResult(pvm.with(self, { view = view.view }), view_elem(view.view), view.issues))
        end,
        [Tr.IndexBasePlace] = function(self, ctx)
            local base = pvm.one(type_place(self.base, ctx))
            local issues = {}; append_all(issues, base.issues)
            return pvm.once(Tr.TypeIndexBaseResult(pvm.with(self, { base = base.place }), self.elem, issues))
        end,
    }, { args_cache = "last" })

    type_place = pvm.phase("moonlift_tree_typecheck_place", {
        [Tr.PlaceRef] = function(self, ctx)
            local ty, ref, issues = ref_type(self.ref, ctx.env)
            return pvm.once(result_place(Tr.PlaceRef(Tr.PlaceTyped(ty), ref), ty, issues))
        end,
        [Tr.PlaceDeref] = function(self, ctx)
            local base = pvm.one(type_expr(self.base, ctx))
            local issues = {}; append_all(issues, base.issues)
            local ty = void_ty()
            local base_access = lease_access_base(base.ty)
            if pvm.classof(base_access) == Ty.TPtr then ty = base_access.elem else issues[#issues + 1] = Tr.TypeIssueNotPointer(base.ty) end
            return pvm.once(result_place(Tr.PlaceDeref(Tr.PlaceTyped(ty), base.expr), ty, issues))
        end,
        [Tr.PlaceDot] = function(self, ctx)
            local base = pvm.one(type_place(self.base, ctx)); local issues = {}; append_all(issues, base.issues)
            local lookup_ty = lease_access_base(base.ty)
            if pvm.classof(lookup_ty) == Ty.TPtr then lookup_ty = lookup_ty.elem end
            local layout = field_layout_for(ctx.env, lookup_ty, self.name)
            if layout ~= nil then
                return pvm.once(result_place(Tr.PlaceField(Tr.PlaceTyped(layout.ty), base.place, Sem.FieldByName(layout.field_name, layout.ty)), layout.ty, issues))
            end
            local preserved_ty = typed_place_header_ty(self.h) or base.ty
            return pvm.once(result_place(Tr.PlaceDot(Tr.PlaceTyped(preserved_ty), base.place, self.name), preserved_ty, issues))
        end,
        [Tr.PlaceField] = function(self, ctx)
            local base = pvm.one(type_place(self.base, ctx)); local issues = {}; append_all(issues, base.issues)
            return pvm.once(result_place(Tr.PlaceField(Tr.PlaceTyped(self.field.ty), base.place, self.field), self.field.ty, issues))
        end,
        [Tr.PlaceIndex] = function(self, ctx)
            local base = pvm.one(type_index_base(self.base, ctx)); local index = type_expr_expect(self.index, ctx, Ty.TScalar(C.ScalarIndex))
            local issues = {}; append_all(issues, base.issues); append_all(issues, index.issues)
            if not is_integer_scalar(index.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("index", Ty.TScalar(C.ScalarIndex), index.ty) end
            return pvm.once(result_place(Tr.PlaceIndex(Tr.PlaceTyped(base.elem), base.base, index.expr), base.elem, issues))
        end,
        [Tr.PlaceSlotValue] = function(self, ctx) return pvm.once(result_place(Tr.PlaceSlotValue(Tr.PlaceTyped(self.slot.ty), self.slot), self.slot.ty, {})) end,
    }, { args_cache = "last" })

    type_expr = pvm.phase("moonlift_tree_typecheck_expr", {
        [Tr.ExprLit] = function(self, ctx)
            local cls = pvm.classof(self.value)
            local ty = void_ty()
            if cls == C.LitInt then ty = i32_ty() elseif cls == C.LitFloat then ty = f64_ty() elseif cls == C.LitBool then ty = bool_ty() elseif cls == C.LitString then ty = cstr_ty() end
            return pvm.once(result_expr(Tr.ExprLit(Tr.ExprTyped(ty), self.value), ty, {}))
        end,
        [Tr.ExprRef] = function(self, ctx)
            local ty, ref, issues = ref_type(self.ref, ctx.env)
            return pvm.once(result_expr(Tr.ExprRef(Tr.ExprTyped(ty), ref), ty, issues))
        end,
        [Tr.ExprUnary] = function(self, ctx)
            local value = pvm.one(type_expr(self.value, ctx)); local issues = {}; append_all(issues, value.issues)
            if self.op == C.UnaryNot then if not is_bool(value.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("not", value.ty) end; return pvm.once(result_expr(Tr.ExprUnary(Tr.ExprTyped(bool_ty()), self.op, value.expr), bool_ty(), issues)) end
            if not is_numeric_scalar(value.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(tostring(self.op), value.ty) end
            return pvm.once(result_expr(Tr.ExprUnary(Tr.ExprTyped(value.ty), self.op, value.expr), value.ty, issues))
        end,
        [Tr.ExprBinary] = function(self, ctx)
            local lhs = pvm.one(type_expr(self.lhs, ctx)); local issues = {}
            append_all(issues, lhs.issues)
            -- Pointer arithmetic: ptr(T) +/- integer — don't constrain rhs to ptr type
            local lhs_is_ptr = pvm.classof(lhs.ty) == Ty.TPtr
            local rhs
            if lhs_is_ptr and (self.op == C.BinAdd or self.op == C.BinSub) then
                rhs = pvm.one(type_expr(self.rhs, ctx))
            else
                rhs = type_expr_expect(self.rhs, ctx, lhs.ty)
            end
            append_all(issues, rhs.issues)
            local ty = type_binary_op(self.op, lhs.ty, rhs.ty, issues)
            return pvm.once(result_expr(Tr.ExprBinary(Tr.ExprTyped(ty), self.op, lhs.expr, rhs.expr), ty, issues))
        end,
        [Tr.ExprCompare] = function(self, ctx)
            local lhs = pvm.one(type_expr(self.lhs, ctx)); local rhs = type_expr_expect(self.rhs, ctx, lhs.ty); local issues = {}
            append_all(issues, lhs.issues); append_all(issues, rhs.issues); type_compare_op(self.op, lhs.ty, rhs.ty, issues)
            return pvm.once(result_expr(Tr.ExprCompare(Tr.ExprTyped(bool_ty()), self.op, lhs.expr, rhs.expr), bool_ty(), issues))
        end,
        [Tr.ExprLogic] = function(self, ctx)
            local lhs = pvm.one(type_expr(self.lhs, ctx)); local rhs = pvm.one(type_expr(self.rhs, ctx)); local issues = {}
            append_all(issues, lhs.issues); append_all(issues, rhs.issues)
            if not is_bool(lhs.ty) or not is_bool(rhs.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidLogic(tostring(self.op), lhs.ty, rhs.ty) end
            return pvm.once(result_expr(Tr.ExprLogic(Tr.ExprTyped(bool_ty()), self.op, lhs.expr, rhs.expr), bool_ty(), issues))
        end,
        [Tr.ExprCast] = function(self, ctx)
            local dst_ty = canonical_type(ctx.env, self.ty)
            local value = pvm.one(type_expr(self.value, ctx))
            local issues = {}; append_all(issues, value.issues); check_type_policy(dst_ty, issues, "cast")
            if (is_handle_type(value.ty) or is_handle_type(dst_ty)) and not type_eq(value.ty, dst_ty) then
                issues[#issues + 1] = Tr.TypeIssueInvalidUnary("handle cast", is_handle_type(value.ty) and value.ty or dst_ty)
            end
            local op = surface_cast_to_machine_op(self.op, value.ty, dst_ty)
            return pvm.once(result_expr(Tr.ExprMachineCast(Tr.ExprTyped(dst_ty), op, dst_ty, value.expr), dst_ty, issues))
        end,
        [Tr.ExprMachineCast] = function(self, ctx) local value = pvm.one(type_expr(self.value, ctx)); local issues = {}; append_all(issues, value.issues); check_type_policy(self.ty, issues, "machine cast"); return pvm.once(result_expr(Tr.ExprMachineCast(Tr.ExprTyped(self.ty), self.op, self.ty, value.expr), self.ty, issues)) end,
        [Tr.ExprLen] = function(self, ctx)
            local value = pvm.one(type_expr(self.value, ctx)); local issues = {}; append_all(issues, value.issues)
            local value_access = lease_access_base(value.ty)
            if pvm.classof(value_access) ~= Ty.TView and pvm.classof(value_access) ~= Ty.TArray then issues[#issues + 1] = Tr.TypeIssueExpected("len", Ty.TView(void_ty()), value.ty) end
            return pvm.once(result_expr(Tr.ExprLen(Tr.ExprTyped(index_ty()), value.expr), index_ty(), issues))
        end,
        [Tr.ExprCall] = function(self, ctx)
            local issues = {}; local typed_args = {}
            -- Trusted/internal handle representation operations.
            -- `repr(handle_value)` exposes the declared scalar representation.
            if pvm.classof(self.callee) == Tr.ExprRef and pvm.classof(self.callee.ref) == B.ValueRefName and self.callee.ref.name == "repr" and #self.args == 1 then
                local arg = pvm.one(type_expr(self.args[1], ctx)); append_all(issues, arg.issues)
                local hty = canonical_type(ctx.env, arg.ty)
                local rty = handle_repr_type(hty)
                if rty == nil then
                    issues[#issues + 1] = Tr.TypeIssueInvalidUnary("handle repr", arg.ty)
                    rty = void_ty()
                end
                return pvm.once(result_expr(Tr.ExprMachineCast(Tr.ExprTyped(rty), C.MachineCastBitcast, rty, arg.expr), rty, issues))
            end
            -- `HandleType.from_repr(raw)` creates a handle at an explicit trust boundary.
            if pvm.classof(self.callee) == Tr.ExprDot and self.callee.name == "from_repr"
               and pvm.classof(self.callee.base) == Tr.ExprRef and pvm.classof(self.callee.base.ref) == B.ValueRefName
               and #self.args == 1 then
                local def = find_handle_def(ctx, self.callee.base.ref.name)
                if def ~= nil then
                    local rty = handle_repr_type(def.ty) or void_ty()
                    local arg = type_expr_expect(self.args[1], ctx, rty); append_all(issues, arg.issues); check_expected("handle from_repr", rty, arg.ty, issues)
                    return pvm.once(result_expr(Tr.ExprMachineCast(Tr.ExprTyped(def.ty), C.MachineCastBitcast, def.ty, arg.expr), def.ty, issues))
                end
            end
            -- self.callee is the callee expression, self.args is the argument list
            local callee_r = pvm.one(type_expr(self.callee, ctx)); append_all(issues, callee_r.issues)
            local fn_ty = callee_r.ty
            if pvm.classof(fn_ty) ~= Ty.TFunc and pvm.classof(fn_ty) ~= Ty.TClosure then
                issues[#issues + 1] = Tr.TypeIssueNotCallable(fn_ty or void_ty())
                return pvm.once(result_expr(Tr.ExprCall(Tr.ExprTyped(void_ty()), callee_r.expr, {}), void_ty(), issues))
            end
            local result_ty, param_tys = callable_result(fn_ty)
            result_ty = canonical_type(ctx.env, result_ty)
            local canonical_param_tys = {}
            for i = 1, #(param_tys or {}) do canonical_param_tys[i] = canonical_type(ctx.env, param_tys[i]) end
            param_tys = canonical_param_tys
            if #param_tys ~= #self.args then issues[#issues + 1] = Tr.TypeIssueArgCount("call", #param_tys, #self.args) end
            for i = 1, #self.args do
                local arg = type_expr_expect(self.args[i], ctx, param_tys[i]); append_all(issues, arg.issues); typed_args[#typed_args + 1] = arg.expr
                if param_tys[i] ~= nil then
                    if not arg_matches_param(param_tys[i], arg.ty) then check_expected("call arg", param_tys[i], arg.ty, issues) end
                    if type_contains_lease(arg.ty) and not type_contains_lease(param_tys[i]) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape call", arg.ty) end
                    if type_contains_owned(arg.ty) and not type_contains_owned(param_tys[i]) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned passed to non-owned parameter", arg.ty) end
                end
            end
            local invalidated_lease = call_may_invalidate_while_lease_live(ctx, callee_r.expr, param_tys, typed_args)
            if invalidated_lease ~= nil then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease invalidating call", invalidated_lease) end
            return pvm.once(result_expr(Tr.ExprCall(Tr.ExprTyped(result_ty), callee_r.expr, typed_args), result_ty, issues))
        end,
        [Tr.ExprField] = function(self, ctx) local base = pvm.one(type_expr(self.base, ctx)); local issues = {}; append_all(issues, base.issues); return pvm.once(result_expr(Tr.ExprField(Tr.ExprTyped(self.field.ty), base.expr, self.field), self.field.ty, issues)) end,
        [Tr.ExprIndex] = function(self, ctx)
            local base = pvm.one(type_index_base(self.base, ctx)); local index = type_expr_expect(self.index, ctx, Ty.TScalar(C.ScalarIndex)); local issues = {}
            append_all(issues, base.issues); append_all(issues, index.issues); if not is_integer_scalar(index.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("index", Ty.TScalar(C.ScalarIndex), index.ty) end
            return pvm.once(result_expr(Tr.ExprIndex(Tr.ExprTyped(base.elem), base.base, index.expr), base.elem, issues))
        end,
        [Tr.ExprIf] = function(self, ctx)
            local cond = pvm.one(type_expr(self.cond, ctx)); local a = pvm.one(type_expr(self.then_expr, ctx)); local b = pvm.one(type_expr(self.else_expr, ctx)); local issues = {}
            append_all(issues, cond.issues); append_all(issues, a.issues); append_all(issues, b.issues); check_expected("if cond", bool_ty(), cond.ty, issues); check_expected("if branches", a.ty, b.ty, issues)
            return pvm.once(result_expr(Tr.ExprIf(Tr.ExprTyped(a.ty), cond.expr, a.expr, b.expr), a.ty, issues))
        end,
        [Tr.ExprSelect] = function(self, ctx)
            local cond = pvm.one(type_expr(self.cond, ctx)); local a = pvm.one(type_expr(self.then_expr, ctx)); local b = pvm.one(type_expr(self.else_expr, ctx)); local issues = {}
            append_all(issues, cond.issues); append_all(issues, a.issues); append_all(issues, b.issues); check_expected("select cond", bool_ty(), cond.ty, issues); check_expected("select branches", a.ty, b.ty, issues)
            return pvm.once(result_expr(Tr.ExprSelect(Tr.ExprTyped(a.ty), cond.expr, a.expr, b.expr), a.ty, issues))
        end,
        [Tr.ExprControl] = function(self, ctx)
            local region = pvm.one(type_control_expr_region(self.region, ctx)); return pvm.once(result_expr(Tr.ExprControl(Tr.ExprTyped(region.region.result_ty), region.region), region.region.result_ty, region.issues))
        end,
        [Tr.ExprBlock] = function(self, ctx)
            local body = type_stmt_body(self.stmts, ctx); local result = pvm.one(type_expr(self.result, body.env)); local issues = {}; append_all(issues, body.issues); append_all(issues, result.issues)
            return pvm.once(result_expr(Tr.ExprBlock(Tr.ExprTyped(result.ty), body.stmts, result.expr), result.ty, issues))
        end,
        [Tr.ExprArray] = function(self, ctx)
            local elems = {}; local issues = {}
            for i = 1, #self.elems do local e = type_expr_expect(self.elems[i], ctx, self.elem_ty); elems[#elems + 1] = e.expr; append_all(issues, e.issues); check_expected("array elem", self.elem_ty, e.ty, issues); if type_contains_owned(e.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned captured in aggregate", e.ty) end end
            local ty = Ty.TArray(Ty.ArrayLenConst(#elems), self.elem_ty)
            return pvm.once(result_expr(Tr.ExprArray(Tr.ExprTyped(ty), self.elem_ty, elems), ty, issues))
        end,
        [Tr.ExprAgg] = function(self, ctx)
            local issues = {}
            if pvm.classof(self.ty) == Ty.TClosure then
                local field_exprs = {}
                for j = 1, #self.fields do
                    local fi = self.fields[j]
                    local ev = pvm.one(type_expr(fi.value, ctx))
                    append_all(issues, ev.issues)
                    if type_contains_lease(ev.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape aggregate", ev.ty) end
                    if type_contains_owned(ev.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned captured in aggregate", ev.ty) end
                    field_exprs[j] = Tr.FieldInit(fi.name, ev.expr, fi.offset)
                end
                return pvm.once(result_expr(Tr.ExprAgg(Tr.ExprTyped(self.ty), self.ty, field_exprs), self.ty, issues))
            end
            local ref = named_ref(self.ty)
            local layout
            if ref then
                for i = 1, #ctx.env.layouts do
                    local l = ctx.env.layouts[i]
                    local cls = pvm.classof(l)
                    local matches = false
                    if cls == Sem.LayoutNamed and pvm.classof(ref) == Ty.TypeRefPath then
                        matches = #ref.path.parts == 1 and l.type_name == ref.path.parts[1].text
                    elseif cls == Sem.LayoutNamed and pvm.classof(ref) == Ty.TypeRefGlobal then
                        matches = l.module_name == ref.module_name and l.type_name == ref.type_name
                    end
                    if matches then layout = l; break end
                end
                if not layout then
                    if pvm.classof(ref) == Ty.TypeRefPath then issues[#issues + 1] = Tr.TypeIssueUnresolvedPath(ref.path)
                    else issues[#issues + 1] = Tr.TypeIssueExpected("struct literal", self.ty, void_ty()) end
                end
            end
            if layout then
                local field_map = {}
                for j = 1, #layout.fields do field_map[layout.fields[j].field_name] = layout.fields[j] end
                local field_exprs = {}
                for j = 1, #self.fields do
                    local fi = self.fields[j]
                    local decl = field_map[fi.name]
                    if not decl then
                        issues[#issues + 1] = Tr.TypeIssueUnresolvedValue(fi.name)
                    else
                        local ev = type_expr_expect(fi.value, ctx, decl.ty)
                        append_all(issues, ev.issues)
                        check_expected("struct field '" .. fi.name .. "'", decl.ty, ev.ty, issues)
                        if type_contains_lease(ev.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape aggregate", ev.ty) end
                        if type_contains_owned(ev.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned captured in aggregate", ev.ty) end
                        field_exprs[j] = Tr.FieldInit(fi.name, ev.expr, decl.offset)
                    end
                end
                return pvm.once(result_expr(Tr.ExprAgg(Tr.ExprTyped(self.ty), self.ty, field_exprs), self.ty, issues))
            end
            return pvm.once(result_expr(pvm.with(self, { h = Tr.ExprTyped(self.ty) }), self.ty, {}))
        end,
        [Tr.ExprArray] = function(self, ctx)
            if #self.elems == 0 then
                local ty = Ty.TArray(Ty.ArrayLenConst(0), self.elem_ty)
                return pvm.once(result_expr(Tr.ExprArray(Tr.ExprTyped(ty), self.elem_ty, {}), ty, { Tr.TypeIssueExpected("empty array literal", ty, void_ty()) }))
            end
            local issues = {}
            local first_ty = pvm.one(type_expr(self.elems[1], ctx)).ty
            local elem_ty = first_ty
            local checked = {}
            for i = 1, #self.elems do
                local ev = type_expr_expect(self.elems[i], ctx, elem_ty)
                append_all(issues, ev.issues)
                check_expected("array elem", elem_ty, ev.ty, issues)
                if type_contains_owned(ev.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned captured in aggregate", ev.ty) end
                checked[i] = ev.expr
            end
            local ty = Ty.TArray(Ty.ArrayLenConst(#self.elems), elem_ty)
            return pvm.once(result_expr(Tr.ExprArray(Tr.ExprTyped(ty), elem_ty, checked), ty, issues))
        end,
        [Tr.ExprView] = function(self, ctx) local view = pvm.one(type_view(self.view, ctx)); local ty = Ty.TView(view_elem(view.view)); return pvm.once(result_expr(Tr.ExprView(Tr.ExprTyped(ty), view.view), ty, view.issues)) end,
        [Tr.ExprLoad] = function(self, ctx) local addr = pvm.one(type_expr(self.addr, ctx)); return pvm.once(result_expr(Tr.ExprLoad(Tr.ExprTyped(self.ty), self.ty, addr.expr), self.ty, addr.issues)) end,
        [Tr.ExprAtomicLoad] = function(self, ctx)
            local addr = type_expr_expect(self.addr, ctx, Ty.TPtr(self.ty)); local issues = {}; append_all(issues, addr.issues)
            check_expected("atomic_load addr", Ty.TPtr(self.ty), addr.ty, issues); check_atomic_value_type("atomic_load", self.ty, issues)
            return pvm.once(result_expr(Tr.ExprAtomicLoad(Tr.ExprTyped(self.ty), self.ty, addr.expr, self.ordering), self.ty, issues))
        end,
        [Tr.ExprAtomicRmw] = function(self, ctx)
            local addr = type_expr_expect(self.addr, ctx, Ty.TPtr(self.ty)); local value = type_expr_expect(self.value, ctx, self.ty); local issues = {}; append_all(issues, addr.issues); append_all(issues, value.issues)
            check_expected("atomic_rmw addr", Ty.TPtr(self.ty), addr.ty, issues); check_expected("atomic_rmw value", self.ty, value.ty, issues); check_atomic_rmw_value_type(self.op, self.ty, issues)
            return pvm.once(result_expr(Tr.ExprAtomicRmw(Tr.ExprTyped(self.ty), self.op, self.ty, addr.expr, value.expr, self.ordering), self.ty, issues))
        end,
        [Tr.ExprAtomicCas] = function(self, ctx)
            local addr = type_expr_expect(self.addr, ctx, Ty.TPtr(self.ty)); local expected = type_expr_expect(self.expected, ctx, self.ty); local replacement = type_expr_expect(self.replacement, ctx, self.ty); local issues = {}
            append_all(issues, addr.issues); append_all(issues, expected.issues); append_all(issues, replacement.issues)
            check_expected("atomic_cas addr", Ty.TPtr(self.ty), addr.ty, issues); check_expected("atomic_cas expected", self.ty, expected.ty, issues); check_expected("atomic_cas replacement", self.ty, replacement.ty, issues); check_atomic_value_type("atomic_cas", self.ty, issues)
            return pvm.once(result_expr(Tr.ExprAtomicCas(Tr.ExprTyped(self.ty), self.ty, addr.expr, expected.expr, replacement.expr, self.ordering), self.ty, issues))
        end,
        [Tr.ExprDot] = function(self, ctx)
            if self.name == "invalid" and pvm.classof(self.base) == Tr.ExprRef and pvm.classof(self.base.ref) == B.ValueRefName then
                local def = find_handle_def(ctx, self.base.ref.name)
                if def ~= nil and pvm.classof(def.invalid) == Ty.HandleInvalidInt then
                    return pvm.once(result_expr(Tr.ExprLit(Tr.ExprTyped(def.ty), C.LitInt(def.invalid.raw)), def.ty, {}))
                end
            end
            local base = pvm.one(type_expr(self.base, ctx)); local issues = {}; append_all(issues, base.issues)
            local base_ty = lease_access_base(base.ty)
            if pvm.classof(base_ty) == Ty.TPtr then
                local layout = field_layout_for(ctx.env, base_ty.elem, self.name)
                if layout ~= nil then
                    return pvm.once(result_expr(Tr.ExprField(Tr.ExprTyped(layout.ty), base.expr, Sem.FieldByName(layout.field_name, layout.ty)), layout.ty, issues))
                end
            end
            local layout = field_layout_for(ctx.env, base_ty, self.name)
            if layout ~= nil then
                return pvm.once(result_expr(Tr.ExprField(Tr.ExprTyped(layout.ty), base.expr, Sem.FieldByName(layout.field_name, layout.ty)), layout.ty, issues))
            end
            local preserved_ty = typed_expr_header_ty(self.h) or base.ty
            return pvm.once(result_expr(Tr.ExprDot(Tr.ExprTyped(preserved_ty), base.expr, self.name), preserved_ty, issues))
        end,
        [Tr.ExprIntrinsic] = function(self, ctx)
            local issues = {}; local args = {}
            for i = 1, #self.args do local a = pvm.one(type_expr(self.args[i], ctx)); args[#args + 1] = a.expr; append_all(issues, a.issues) end
            local h_cls = pvm.classof(self.h)
            local ty = nil
            if h_cls == Tr.ExprTyped or h_cls == Tr.ExprOpen then ty = self.h.ty end
            if ty == nil or (pvm.classof(ty) == Ty.TScalar and ty.scalar == C.ScalarVoid and self.op ~= C.IntrinsicTrap and self.op ~= C.IntrinsicAssume) then
                ty = (#self.args > 0) and pvm.one(type_expr(self.args[1], ctx)).ty or void_ty()
            end
            if self.op == C.IntrinsicTrap or self.op == C.IntrinsicAssume then ty = void_ty() end
            return pvm.once(result_expr(Tr.ExprIntrinsic(Tr.ExprTyped(ty), self.op, args), ty, issues))
        end,
        [Tr.ExprAddrOf] = function(self, ctx) local place = pvm.one(type_place(self.place, ctx)); local ty = Ty.TPtr(place.ty); return pvm.once(result_expr(Tr.ExprAddrOf(Tr.ExprTyped(ty), place.place), ty, place.issues)) end,
        [Tr.ExprDeref] = function(self, ctx) local value = pvm.one(type_expr(self.value, ctx)); local issues = {}; append_all(issues, value.issues); local ty = void_ty(); local access = lease_access_base(value.ty); if pvm.classof(access) == Ty.TPtr then ty = access.elem else issues[#issues + 1] = Tr.TypeIssueNotPointer(value.ty) end; return pvm.once(result_expr(Tr.ExprDeref(Tr.ExprTyped(ty), value.expr), ty, issues)) end,
        [Tr.ExprSwitch] = function(self, ctx)
            local value = pvm.one(type_expr(self.value, ctx))
            local default_body = type_stmt_body(self.default_body or {}, ctx)
            local default = pvm.one(type_expr(self.default_expr, default_body.env))
            local issues = {}; append_all(issues, value.issues); append_all(issues, default_body.issues); append_all(issues, default.issues)
            local arms = {}
            for i = 1, #self.arms do
                local body = type_stmt_body(self.arms[i].body, ctx)
                local result = pvm.one(type_expr(self.arms[i].result, body.env))
                append_all(issues, body.issues); append_all(issues, result.issues)
                check_expected("switch arm", default.ty, result.ty, issues)
                arms[#arms + 1] = Tr.SwitchExprArm(self.arms[i].raw_key, body.stmts, result.expr)
            end
            local var_arms = {}
            local def = variant_def_for_value_ty(ctx, value.ty)
            for i = 1, #(self.variant_arms or {}) do
                local arm = self.variant_arms[i]
                local variant = def and def.variants[arm.variant_name] or nil
                if variant == nil then issues[#issues + 1] = Tr.TypeIssueUnknownVariant(def and def.type_name or "?", arm.variant_name) end
                local arm_ctx, typed_binds = ctx, arm.binds
                if variant ~= nil then local env, binds = bind_env_for_variant(ctx, "expr_switch", variant, arm.binds); arm_ctx = ctx_with_env(ctx, env); typed_binds = {}; for j = 1, #binds do typed_binds[#typed_binds + 1] = Tr.VariantBind(binds[j].name, binds[j].ty) end end
                local body = type_stmt_body(arm.body, arm_ctx)
                local result = pvm.one(type_expr(arm.result, body.env))
                append_all(issues, body.issues); append_all(issues, result.issues)
                check_expected("variant switch arm", default.ty, result.ty, issues)
                var_arms[#var_arms + 1] = Tr.SwitchVariantExprArm(arm.variant_name, typed_binds, body.stmts, result.expr)
            end
            return pvm.once(result_expr(Tr.ExprSwitch(Tr.ExprTyped(default.ty), value.expr, arms, var_arms, default_body.stmts, default.expr), default.ty, issues))
        end,
        [Tr.ExprClosure] = function(self, ctx) local ty = Ty.TClosure(self.params, self.result); return pvm.once(result_expr(pvm.with(self, { h = Tr.ExprTyped(ty) }), ty, {})) end,
        [Tr.ExprCtor] = function(self, ctx)
            local def, variant = find_variant(ctx, self.type_name, self.variant_name)
            local ty = (def and def.ty) or type_name_for_ctor(self.type_name)
            local args, issues = {}, {}
            if variant == nil then
                issues[#issues + 1] = Tr.TypeIssueUnknownVariant(self.type_name, self.variant_name)
                for i = 1, #(self.args or {}) do local a = pvm.one(type_expr(self.args[i], ctx)); args[#args + 1] = a.expr; append_all(issues, a.issues) end
                return pvm.once(result_expr(Tr.ExprCtor(Tr.ExprTyped(ty), self.type_name, self.variant_name, args), ty, issues))
            end
            local expected = {}
            if #(variant.fields or {}) > 0 then
                for i = 1, #variant.fields do expected[#expected + 1] = variant.fields[i].ty end
            elseif not is_void_type(variant.payload) then
                expected[#expected + 1] = variant.payload
            end
            if #expected ~= #(self.args or {}) then
                issues[#issues + 1] = Tr.TypeIssueVariantPayloadMismatch(self.type_name, self.variant_name, expected[1] or void_ty(), self.args[1] and pvm.one(type_expr(self.args[1], ctx)).ty or void_ty())
            end
            for i = 1, #(self.args or {}) do
                local a = expected[i] and type_expr_expect(self.args[i], ctx, expected[i]) or pvm.one(type_expr(self.args[i], ctx))
                args[#args + 1] = a.expr
                append_all(issues, a.issues)
                if expected[i] then check_expected("variant payload", expected[i], a.ty, issues) end
            end
            return pvm.once(result_expr(Tr.ExprCtor(Tr.ExprTyped(ty), self.type_name, self.variant_name, args), ty, issues))
        end,
        [Tr.ExprNull] = function(self, ctx)
            local issues = {}
            if pvm.classof(self.elem) ~= Ty.TPtr then
                issues[#issues + 1] = Tr.TypeIssueExpected("null", Ty.TPtr(Ty.TVoid), self.elem)
            end
            return pvm.once(result_expr(Tr.ExprNull(Tr.ExprTyped(self.elem), self.elem), self.elem, issues))
        end,
        [Tr.ExprSizeOf] = function(self, ctx)
            local issues = {}; check_type_policy(self.ty, issues, "sizeof")
            return pvm.once(result_expr(Tr.ExprSizeOf(Tr.ExprTyped(index_ty()), self.ty), index_ty(), issues))
        end,
        [Tr.ExprAlignOf] = function(self, ctx)
            local issues = {}; check_type_policy(self.ty, issues, "alignof")
            return pvm.once(result_expr(Tr.ExprAlignOf(Tr.ExprTyped(index_ty()), self.ty), index_ty(), issues))
        end,
        [Tr.ExprIsNull] = function(self, ctx)
            local value = pvm.one(type_expr(self.value, ctx))
            local issues = {}; append_all(issues, value.issues)
            if pvm.classof(lease_access_base(value.ty)) ~= Ty.TPtr then
                issues[#issues + 1] = Tr.TypeIssueNotPointer(value.ty)
            end
            return pvm.once(result_expr(Tr.ExprIsNull(Tr.ExprTyped(bool_ty()), value.expr), bool_ty(), issues))
        end,
        [Tr.ExprSlotValue] = function(self, ctx) return pvm.once(result_expr(Tr.ExprSlotValue(Tr.ExprTyped(self.slot.ty), self.slot), self.slot.ty, {})) end,
        [Tr.ExprUseExprFrag] = function(self, ctx) local ty = void_ty(); return pvm.once(result_expr(pvm.with(self, { h = Tr.ExprTyped(ty) }), ty, {})) end,
    }, { args_cache = "last" })

    type_switch_key = function(key, ctx, value_ty, issues)
        if key.kind == "expr" then
            local expr = pvm.one(type_expr(key.expr, ctx))
            append_all(issues, expr.issues)
            check_expected("switch key", value_ty, expr.ty, issues)
            return { kind = "expr", expr = expr.expr }
        end
        -- SwitchKeyRaw: if the raw string is a bare name (not a literal number),
        -- re-typecheck it as an expression so named constants resolve to their values.
        if key.kind == "raw" then
            local raw = key.raw
            -- Check if it looks like a non-numeric identifier
            if raw:match("^[%a_][%w_]*$") then
                local ref_expr = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(raw))
                local expr = pvm.one(type_expr(ref_expr, ctx))
                if #expr.issues == 0 then
                    check_expected("switch key", value_ty, expr.ty, issues)
                    return { kind = "expr", expr = expr.expr }
                end
                -- Name not found — fall through to keep raw (will fail at backend with clear error)
            end
        end
        return key
    end

    local function jump_args_by_name(args)
        local out = {}; local dup = {}
        for i = 1, #args do if out[args[i].name] ~= nil then dup[args[i].name] = true end; out[args[i].name] = args[i] end
        return out, dup
    end

    local function block_param_bindings(region_id, label, params, is_entry)
        local entries = {}
        for i = 1, #params do
            local class = is_entry and B.BindingClassEntryBlockParam(region_id, label.name, i) or B.BindingClassBlockParam(region_id, label.name, i)
            local binding = B.Binding(C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. params[i].name), params[i].name, params[i].ty, class)
            entries[#entries + 1] = B.ValueEntry(params[i].name, binding)
        end
        return entries
    end

    local function env_with_block_params(env, region_id, label, params, is_entry)
        local out = env
        local entries = block_param_bindings(region_id, label, params, is_entry)
        for i = 1, #entries do out = env_add_value(out, entries[i]) end
        return out
    end

    type_stmt = pvm.phase("moonlift_tree_typecheck_stmt", {
        [Tr.StmtLet] = function(self, ctx)
            local binding_ty = canonical_type(ctx.env, self.binding.ty)
            local is_inferred = pvm.classof(binding_ty) == Ty.TScalar and binding_ty.scalar == C.ScalarVoid
            local init = is_inferred and pvm.one(type_expr(self.init, ctx)) or type_expr_expect(self.init, ctx, binding_ty)
            local issues = {}; append_all(issues, init.issues)
            local actual_ty = is_inferred and init.ty or binding_ty
            if not is_inferred then check_expected("let " .. self.binding.name, actual_ty, init.ty, issues) end
            local binding = pvm.with(self.binding, { ty = actual_ty, class = B.BindingClassLocalValue })
            local env = env_add_value(ctx.env, B.ValueEntry(binding.name, binding))
            return pvm.once(Tr.TypeStmtResult(ctx_with_env(ctx, env), { Tr.StmtLet(Tr.StmtSurface, binding, init.expr) }, issues))
        end,
        [Tr.StmtVar] = function(self, ctx)
            local binding_ty = canonical_type(ctx.env, self.binding.ty)
            local is_inferred = pvm.classof(binding_ty) == Ty.TScalar and binding_ty.scalar == C.ScalarVoid
            local init = is_inferred and pvm.one(type_expr(self.init, ctx)) or type_expr_expect(self.init, ctx, binding_ty)
            local issues = {}; append_all(issues, init.issues)
            local actual_ty = is_inferred and init.ty or binding_ty
            if not is_inferred then check_expected("var " .. self.binding.name, actual_ty, init.ty, issues) end
            local binding = pvm.with(self.binding, { ty = actual_ty, class = B.BindingClassLocalCell })
            local env = env_add_value(ctx.env, B.ValueEntry(binding.name, binding))
            return pvm.once(Tr.TypeStmtResult(ctx_with_env(ctx, env), { Tr.StmtVar(Tr.StmtSurface, binding, init.expr) }, issues))
        end,
        [Tr.StmtSet] = function(self, ctx) local place = pvm.one(type_place(self.place, ctx)); local value = type_expr_expect(self.value, ctx, place.ty); local issues = {}; append_all(issues, place.issues); append_all(issues, value.issues); check_expected("set", place.ty, value.ty, issues); if type_contains_lease(value.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape store", value.ty) end; if type_contains_owned(value.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned stored in durable field", value.ty) end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtSet(Tr.StmtSurface, place.place, value.expr) }, issues)) end,
        [Tr.StmtAtomicStore] = function(self, ctx)
            local addr = type_expr_expect(self.addr, ctx, Ty.TPtr(self.ty)); local value = type_expr_expect(self.value, ctx, self.ty); local issues = {}; append_all(issues, addr.issues); append_all(issues, value.issues)
            check_expected("atomic_store addr", Ty.TPtr(self.ty), addr.ty, issues); check_expected("atomic_store value", self.ty, value.ty, issues); check_atomic_value_type("atomic_store", self.ty, issues)
            return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtAtomicStore(Tr.StmtSurface, self.ty, addr.expr, value.expr, self.ordering) }, issues))
        end,
        [Tr.StmtAtomicFence] = function(self, ctx) return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtAtomicFence(Tr.StmtSurface, self.ordering) }, {})) end,
        [Tr.StmtExpr] = function(self, ctx) local expr = pvm.one(type_expr(self.expr, ctx)); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtExpr(Tr.StmtSurface, expr.expr) }, expr.issues)) end,
        [Tr.StmtAssert] = function(self, ctx) local cond = type_expr_expect(self.cond, ctx, bool_ty()); local issues = {}; append_all(issues, cond.issues); check_expected("assert", bool_ty(), cond.ty, issues); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtAssert(Tr.StmtSurface, cond.expr) }, issues)) end,
        [Tr.StmtReturnVoid] = function(self, ctx) local issues = {}; check_expected("return", void_ty(), ctx.return_ty, issues); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtReturnVoid(Tr.StmtSurface) }, issues)) end,
        [Tr.StmtReturnValue] = function(self, ctx) local value = type_expr_expect(self.value, ctx, ctx.return_ty); local issues = {}; append_all(issues, value.issues); check_expected("return", ctx.return_ty, value.ty, issues); if type_contains_lease(value.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape return", value.ty) end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtReturnValue(Tr.StmtSurface, value.expr) }, issues)) end,
        [Tr.StmtYieldVoid] = function(self, ctx) local issues = {}; if ctx.yield ~= Tr.TypeYieldVoid then issues[#issues + 1] = Tr.TypeIssueUnexpectedYield("yield") end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtYieldVoid(Tr.StmtSurface) }, issues)) end,
        [Tr.StmtYieldValue] = function(self, ctx) local expected = pvm.classof(ctx.yield) == Tr.TypeYieldValue and ctx.yield.ty or nil; local value = type_expr_expect(self.value, ctx, expected); local issues = {}; append_all(issues, value.issues); if pvm.classof(ctx.yield) == Tr.TypeYieldValue then check_expected("yield", ctx.yield.ty, value.ty, issues) else issues[#issues + 1] = Tr.TypeIssueUnexpectedYield("yield value") end; if type_contains_lease(value.ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape yield", value.ty) end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtYieldValue(Tr.StmtSurface, value.expr) }, issues)) end,
        [Tr.StmtIf] = function(self, ctx)
            local cond = type_expr_expect(self.cond, ctx, bool_ty()); local then_r = type_stmt_body(self.then_body, ctx); local else_r = type_stmt_body(self.else_body, ctx); local issues = {}
            append_all(issues, cond.issues); append_all(issues, then_r.issues); append_all(issues, else_r.issues); check_expected("if cond", bool_ty(), cond.ty, issues)
            return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtIf(Tr.StmtSurface, cond.expr, then_r.stmts, else_r.stmts) }, issues))
        end,
        [Tr.StmtJump] = function(self, ctx) local args = {}; local issues = {}; for i = 1, #self.args do local value = pvm.one(type_expr(self.args[i].value, ctx)); args[#args + 1] = Tr.JumpArg(self.args[i].name, value.expr); append_all(issues, value.issues) end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtJump(Tr.StmtSurface, self.target, args) }, issues)) end,
        [Tr.StmtJumpCont] = function(self, ctx) local args = {}; local issues = {}; for i = 1, #self.args do local value = pvm.one(type_expr(self.args[i].value, ctx)); args[#args + 1] = Tr.JumpArg(self.args[i].name, value.expr); append_all(issues, value.issues) end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtJumpCont(Tr.StmtSurface, self.slot, args) }, issues)) end,
        [Tr.StmtSwitch] = function(self, ctx)
            local value = pvm.one(type_expr(self.value, ctx))
            local issues = {}; append_all(issues, value.issues)
            local arms = {}
            for i = 1, #self.arms do
                local body = type_stmt_body(self.arms[i].body, ctx)
                append_all(issues, body.issues)
                arms[#arms + 1] = Tr.SwitchStmtArm(self.arms[i].raw_key, body.stmts)
            end
            local variant_arms = {}
            local def = variant_def_for_value_ty(ctx, value.ty)
            for i = 1, #(self.variant_arms or {}) do
                local arm = self.variant_arms[i]
                local variant = def and def.variants[arm.variant_name] or nil
                if variant == nil then issues[#issues + 1] = Tr.TypeIssueUnknownVariant(def and def.type_name or "?", arm.variant_name) end
                local arm_ctx, typed_binds = ctx, arm.binds
                if variant ~= nil then local env, binds = bind_env_for_variant(ctx, "stmt_switch", variant, arm.binds); arm_ctx = ctx_with_env(ctx, env); typed_binds = {}; for j = 1, #binds do typed_binds[#typed_binds + 1] = Tr.VariantBind(binds[j].name, binds[j].ty) end end
                local body = type_stmt_body(arm.body, arm_ctx)
                append_all(issues, body.issues)
                variant_arms[#variant_arms + 1] = Tr.SwitchVariantStmtArm(arm.variant_name, typed_binds, body.stmts)
            end
            local default = type_stmt_body(self.default_body, ctx)
            append_all(issues, default.issues)
            return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtSwitch(Tr.StmtSurface, value.expr, arms, variant_arms, default.stmts) }, issues))
        end,
        [Tr.StmtControl] = function(self, ctx) local region = pvm.one(type_control_stmt_region(self.region, ctx)); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtControl(Tr.StmtSurface, region.region) }, region.issues)) end,
        [Tr.StmtTrap] = function(self, ctx)
            return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtTrap(Tr.StmtSurface) }, {}))
        end,
        [Tr.StmtUseRegionSlot] = function(self, ctx) return pvm.once(Tr.TypeStmtResult(ctx, { pvm.with(self, { h = Tr.StmtSurface }) }, {})) end,
        [Tr.StmtUseRegionFrag] = function(self, ctx)
            local frag = lookup_region_frag(ctx, self.frag)
            local issues, args = {}, {}
            for i = 1, #(self.args or {}) do
                local p = frag and frag.params and frag.params[i] or nil
                local expected = p and p.ty or nil
                local value = expected and type_expr_expect(self.args[i], ctx, expected) or pvm.one(type_expr(self.args[i], ctx))
                args[#args + 1] = value.expr
                append_all(issues, value.issues)
                if expected ~= nil and not arg_matches_param(expected, value.ty) then check_expected("emit arg", expected, value.ty, issues) end
                if expected ~= nil and type_contains_lease(value.ty) and not type_contains_lease(expected) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape call", value.ty) end
                if expected ~= nil and type_contains_owned(value.ty) and not type_contains_owned(expected) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned passed to non-owned parameter", value.ty) end
            end
            if frag ~= nil and self.mode == Tr.RegionUseCall then
                for i = 1, #(frag.conts or {}) do
                    local cont = frag.conts[i]
                    for j = 1, #(cont.params or {}) do
                        local ty = cont.params[j].ty
                        if type_contains_lease(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("region call lease payload", ty) end
                        if type_contains_owned(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned region call payload", ty) end
                    end
                end
            end
            return pvm.once(Tr.TypeStmtResult(ctx, { pvm.with(self, { h = Tr.StmtSurface, args = args }) }, issues))
        end,
    }, { args_cache = "last" })

    type_stmt_body = function(stmts, ctx)
        local current = ctx
        local out = {}
        local issues = {}
        for i = 1, #stmts do
            local r = pvm.one(type_stmt(stmts[i], current))
            append_all(out, r.stmts)
            append_all(issues, r.issues)
            current = r.env
        end
        return Tr.TypeStmtResult(current, out, issues)
    end

    local function owned_issue(issues, op, ty)
        issues[#issues + 1] = Tr.TypeIssueInvalidUnary(op, ty or void_ty())
    end

    local function binding_key(binding)
        return binding and binding.id and (binding.id.text or binding.id.name or tostring(binding.id)) or nil
    end

    local function expr_ty(expr)
        return expr and typed_expr_header_ty(expr.h) or void_ty()
    end

    local function place_ty(place)
        return place and typed_place_header_ty(place.h) or void_ty()
    end

    local function state_new(bindings, region_frags)
        local state = { live = {}, reachable = true, region_frags = region_frags or {} }
        for i = 1, #(bindings or {}) do
            local b = bindings[i].binding or bindings[i]
            if is_owned_type(b.ty) then
                local key = binding_key(b)
                if key then state.live[key] = b end
            end
        end
        return state
    end

    local function state_clone(state)
        local live = {}
        for k, v in pairs(state.live or {}) do live[k] = v end
        return { live = live, reachable = state.reachable, region_frags = state.region_frags }
    end

    local function state_report_live(state, issues, op)
        for _, b in pairs(state.live or {}) do owned_issue(issues, op, b.ty) end
    end

    local function state_same_live(a, b)
        for k, _ in pairs(a.live or {}) do if not (b.live or {})[k] then return false end end
        for k, _ in pairs(b.live or {}) do if not (a.live or {})[k] then return false end end
        return true
    end

    local check_owned_expr
    local check_owned_stmt_body

    local function expr_binding(expr)
        if not expr or pvm.classof(expr) ~= Tr.ExprRef then return nil end
        if pvm.classof(expr.ref) == B.ValueRefBinding then return expr.ref.binding end
        return nil
    end

    local function consume_binding(state, binding, issues)
        local key = binding_key(binding)
        if not key then return end
        if state.live[key] == nil then owned_issue(issues, "owned use after move", binding.ty)
        else state.live[key] = nil end
    end

    local function check_owned_exprs(exprs, state, issues, mode)
        for i = 1, #(exprs or {}) do check_owned_expr(exprs[i], state, issues, mode or "observe") end
    end

    local function callable_param_tys(callee)
        local ty = expr_ty(callee)
        local cls = pvm.classof(ty)
        if cls == Ty.TFunc or cls == Ty.TClosure then return ty.params or {} end
        return {}
    end

    check_owned_expr = function(expr, state, issues, mode)
        if not state.reachable or expr == nil then return end
        mode = mode or "observe"
        local cls = pvm.classof(expr)
        local ty = expr_ty(expr)
        if cls == Tr.ExprRef then
            local binding = expr_binding(expr)
            if binding and is_owned_type(binding.ty) then
                if mode == "consume" then consume_binding(state, binding, issues)
                else owned_issue(issues, "owned observed without transfer", binding.ty) end
            end
            return
        elseif cls == Tr.ExprCall then
            check_owned_expr(expr.callee, state, issues, "observe")
            local params = callable_param_tys(expr.callee)
            for i = 1, #(expr.args or {}) do
                local pty = params[i]
                if pty ~= nil and is_owned_type(pty) then
                    check_owned_expr(expr.args[i], state, issues, "consume")
                else
                    if type_contains_owned(expr_ty(expr.args[i])) then owned_issue(issues, "owned passed to non-owned parameter", expr_ty(expr.args[i])) end
                    check_owned_expr(expr.args[i], state, issues, "observe")
                end
            end
            if is_owned_type(ty) and mode ~= "consume" then owned_issue(issues, "owned dropped", ty) end
            return
        elseif cls == Tr.ExprIf or cls == Tr.ExprSelect then
            check_owned_expr(expr.cond, state, issues, "observe")
            local a, b = state_clone(state), state_clone(state)
            check_owned_expr(expr.then_expr, a, issues, mode)
            check_owned_expr(expr.else_expr, b, issues, mode)
            if a.reachable and b.reachable and not state_same_live(a, b) then owned_issue(issues, "owned branch mismatch", ty) end
            if a.reachable and not b.reachable then state.live = a.live
            elseif b.reachable and not a.reachable then state.live = b.live
            elseif a.reachable and b.reachable then state.live = a.live
            else state.reachable = false; state.live = {} end
            return
        elseif cls == Tr.ExprBlock then
            local s = check_owned_stmt_body(expr.stmts or {}, state, issues, nil, nil)
            check_owned_expr(expr.result, s, issues, mode)
            return
        elseif cls == Tr.ExprAgg or cls == Tr.ExprArray or cls == Tr.ExprCtor then
            if type_contains_owned(ty) then owned_issue(issues, "owned captured in aggregate", ty) end
            if cls == Tr.ExprAgg then
                for i = 1, #(expr.fields or {}) do
                    if type_contains_owned(expr_ty(expr.fields[i].value)) then owned_issue(issues, "owned captured in aggregate", expr_ty(expr.fields[i].value)) end
                    check_owned_expr(expr.fields[i].value, state, issues, "observe")
                end
            else
                check_owned_exprs(expr.elems or expr.args, state, issues, "observe")
            end
            return
        elseif cls == Tr.ExprControl then
            for i = 1, #(expr.region.entry.params or {}) do
                local p = expr.region.entry.params[i]
                if is_owned_type(p.ty) then check_owned_expr(p.init, state, issues, "consume")
                else check_owned_expr(p.init, state, issues, "observe") end
            end
            if is_owned_type(ty) and mode ~= "consume" then owned_issue(issues, "owned dropped", ty) end
            return
        elseif cls == Tr.ExprDot or cls == Tr.ExprField then check_owned_expr(expr.base, state, issues, "observe")
        elseif cls == Tr.ExprUnary or cls == Tr.ExprCast or cls == Tr.ExprMachineCast or cls == Tr.ExprDeref or cls == Tr.ExprLen or cls == Tr.ExprIsNull then check_owned_expr(expr.value, state, issues, "observe")
        elseif cls == Tr.ExprBinary or cls == Tr.ExprCompare or cls == Tr.ExprLogic then check_owned_expr(expr.lhs, state, issues, "observe"); check_owned_expr(expr.rhs, state, issues, "observe")
        elseif cls == Tr.ExprIntrinsic then check_owned_exprs(expr.args, state, issues, "observe")
        elseif cls == Tr.ExprIndex then check_owned_expr(expr.index, state, issues, "observe")
        elseif cls == Tr.ExprView then
            local v = expr.view
            if v then check_owned_expr(v.data, state, issues, "observe"); check_owned_expr(v.len, state, issues, "observe"); check_owned_expr(v.stride, state, issues, "observe") end
        elseif cls == Tr.ExprLoad or cls == Tr.ExprAtomicLoad then check_owned_expr(expr.addr, state, issues, "observe")
        elseif cls == Tr.ExprAtomicRmw then check_owned_expr(expr.addr, state, issues, "observe"); check_owned_expr(expr.value, state, issues, "observe")
        elseif cls == Tr.ExprAtomicCas then check_owned_expr(expr.addr, state, issues, "observe"); check_owned_expr(expr.expected, state, issues, "observe"); check_owned_expr(expr.replacement, state, issues, "observe")
        elseif cls == Tr.ExprUseExprFrag then check_owned_exprs(expr.args, state, issues, "observe")
        end
        if is_owned_type(ty) and mode ~= "consume" then owned_issue(issues, "owned dropped", ty) end
    end

    local function target_params(params)
        local by_name = {}
        for i = 1, #(params or {}) do by_name[params[i].name] = params[i].ty end
        return by_name
    end

    local function check_jump_args(args, target, state, issues)
        for i = 1, #(args or {}) do
            local arg = args[i]
            local pty = target and target[arg.name]
            if pty ~= nil and is_owned_type(pty) then
                check_owned_expr(arg.value, state, issues, "consume")
            else
                if type_contains_owned(expr_ty(arg.value)) then owned_issue(issues, "owned passed to non-owned parameter", expr_ty(arg.value)) end
                check_owned_expr(arg.value, state, issues, "observe")
            end
        end
        state_report_live(state, issues, "owned dropped")
        state.live = {}
        state.reachable = false
    end

    local function merge_branch_states(base, branches, issues, ty)
        local merged, any = nil, false
        for i = 1, #branches do
            local s = branches[i]
            if s.reachable then
                if merged == nil then merged = s
                elseif not state_same_live(merged, s) then owned_issue(issues, "owned branch mismatch", ty or void_ty()) end
                any = true
            end
        end
        if any and merged then base.live = merged.live; base.reachable = true else base.live = {}; base.reachable = false end
    end

    local function variant_bindings(binds)
        local out = {}
        for i = 1, #(binds or {}) do out[#out + 1] = B.Binding(C.Id("variant:" .. tostring(binds[i].name)), binds[i].name, binds[i].ty, B.BindingClassLocalValue) end
        return out
    end

    local function cont_fill_target(stmt, name)
        for i = 1, #(stmt.cont_fills or {}) do
            if stmt.cont_fills[i].name == name then return stmt.cont_fills[i].target end
        end
        return nil
    end

    local function target_param_map(target, block_targets)
        if target == nil then return nil end
        local cls = pvm.classof(target)
        if cls == O.ContTargetLabel then return block_targets and block_targets[target.label.name] end
        if cls == O.ContTargetSlot then return target_params(target.slot.params) end
        return nil
    end

    local function check_emit_owned_continuations(stmt, frag, block_targets, issues)
        for i = 1, #(frag.conts or {}) do
            local cont = frag.conts[i]
            local target = cont_fill_target(stmt, cont.pretty_name)
            local target_params_by_name = target_param_map(target, block_targets)
            for j = 1, #(cont.params or {}) do
                local param = cont.params[j]
                if is_owned_type(param.ty) then
                    local target_ty = target_params_by_name and target_params_by_name[param.name] or nil
                    if target_ty == nil or not type_eq(target_ty, param.ty) then
                        owned_issue(issues, "owned emit target mismatch", param.ty)
                    end
                end
            end
        end
    end

    local function check_owned_stmt(stmt, state, issues, block_targets, cont_targets)
        if not state.reachable then return state end
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtLet then
            if is_owned_type(stmt.binding.ty) then
                check_owned_expr(stmt.init, state, issues, "consume")
                state.live[binding_key(stmt.binding)] = stmt.binding
            else
                if type_contains_owned(expr_ty(stmt.init)) then owned_issue(issues, "owned captured in aggregate", expr_ty(stmt.init)) end
                check_owned_expr(stmt.init, state, issues, "observe")
            end
        elseif cls == Tr.StmtVar then
            if type_contains_owned(stmt.binding.ty) then owned_issue(issues, "owned var cell unsupported", stmt.binding.ty) end
            check_owned_expr(stmt.init, state, issues, "observe")
        elseif cls == Tr.StmtSet then
            if type_contains_owned(place_ty(stmt.place)) or type_contains_owned(expr_ty(stmt.value)) then owned_issue(issues, "owned stored in durable field", expr_ty(stmt.value)) end
            check_owned_expr(stmt.value, state, issues, "observe")
        elseif cls == Tr.StmtAtomicStore then
            check_owned_expr(stmt.addr, state, issues, "observe"); check_owned_expr(stmt.value, state, issues, "observe")
        elseif cls == Tr.StmtExpr then
            check_owned_expr(stmt.expr, state, issues, "observe")
        elseif cls == Tr.StmtAssert then
            check_owned_expr(stmt.cond, state, issues, "observe")
        elseif cls == Tr.StmtIf then
            check_owned_expr(stmt.cond, state, issues, "observe")
            local a = check_owned_stmt_body(stmt.then_body or {}, state_clone(state), issues, block_targets, cont_targets)
            local b = check_owned_stmt_body(stmt.else_body or {}, state_clone(state), issues, block_targets, cont_targets)
            merge_branch_states(state, { a, b }, issues, void_ty())
        elseif cls == Tr.StmtSwitch then
            check_owned_expr(stmt.value, state, issues, "observe")
            local branches = {}
            for i = 1, #(stmt.arms or {}) do branches[#branches + 1] = check_owned_stmt_body(stmt.arms[i].body or {}, state_clone(state), issues, block_targets, cont_targets) end
            for i = 1, #(stmt.variant_arms or {}) do
                local s = state_clone(state)
                for _, b in ipairs(variant_bindings(stmt.variant_arms[i].binds)) do if is_owned_type(b.ty) then s.live[binding_key(b)] = b end end
                branches[#branches + 1] = check_owned_stmt_body(stmt.variant_arms[i].body or {}, s, issues, block_targets, cont_targets)
            end
            branches[#branches + 1] = check_owned_stmt_body(stmt.default_body or {}, state_clone(state), issues, block_targets, cont_targets)
            merge_branch_states(state, branches, issues, void_ty())
        elseif cls == Tr.StmtJump then
            check_jump_args(stmt.args, block_targets and block_targets[stmt.target.name], state, issues)
        elseif cls == Tr.StmtJumpCont then
            check_jump_args(stmt.args, target_params(stmt.slot.params), state, issues)
        elseif cls == Tr.StmtYieldVoid or cls == Tr.StmtReturnVoid or cls == Tr.StmtTrap then
            state_report_live(state, issues, "owned dropped")
            state.live = {}
            state.reachable = false
        elseif cls == Tr.StmtYieldValue or cls == Tr.StmtReturnValue then
            if is_owned_type(expr_ty(stmt.value)) then check_owned_expr(stmt.value, state, issues, "consume") else check_owned_expr(stmt.value, state, issues, "observe") end
            state_report_live(state, issues, "owned dropped")
            state.live = {}
            state.reachable = false
        elseif cls == Tr.StmtControl then
            for i = 1, #(stmt.region.entry.params or {}) do
                local p = stmt.region.entry.params[i]
                if is_owned_type(p.ty) then check_owned_expr(p.init, state, issues, "consume")
                else check_owned_expr(p.init, state, issues, "observe") end
            end
            -- Nested control ownership is checked on the typed region.
        elseif cls == Tr.StmtUseRegionFrag then
            local frag = lookup_region_frag_in_list(state.region_frags, stmt.frag)
            for i = 1, #(stmt.args or {}) do
                local p = frag and frag.params and frag.params[i] or nil
                if p ~= nil and is_owned_type(p.ty) then
                    check_owned_expr(stmt.args[i], state, issues, "consume")
                else
                    if type_contains_owned(expr_ty(stmt.args[i])) then owned_issue(issues, "owned region call payload", expr_ty(stmt.args[i])) end
                    check_owned_expr(stmt.args[i], state, issues, "observe")
                end
            end
            if frag ~= nil then
                if stmt.mode == Tr.RegionUseCall then
                    for i = 1, #(frag.conts or {}) do
                        for j = 1, #(frag.conts[i].params or {}) do
                            if type_contains_owned(frag.conts[i].params[j].ty) then owned_issue(issues, "owned region call payload", frag.conts[i].params[j].ty) end
                        end
                    end
                else
                    check_emit_owned_continuations(stmt, frag, block_targets, issues)
                end
            end
            state_report_live(state, issues, "owned dropped")
            state.live = {}
            state.reachable = false
        end
        return state
    end

    check_owned_stmt_body = function(stmts, state, issues, block_targets, cont_targets)
        for i = 1, #(stmts or {}) do check_owned_stmt(stmts[i], state, issues, block_targets, cont_targets) end
        return state
    end

    local function check_owned_function(func_name, params, body, issues, region_frags)
        local bindings = {}
        for i = 1, #(params or {}) do bindings[#bindings + 1] = B.Binding(C.Id("arg:" .. tostring(func_name) .. ":" .. tostring(params[i].name)), params[i].name, params[i].ty, B.BindingClassArg(i - 1)) end
        local state = check_owned_stmt_body(body or {}, state_new(bindings, region_frags), issues, nil, nil)
        if state.reachable then state_report_live(state, issues, "owned dropped") end
    end

    local function block_param_target(params)
        local map = {}
        for i = 1, #(params or {}) do map[params[i].name] = params[i].ty end
        return map
    end

    local function check_owned_control_region(region, issues, region_frags, entry_extra_bindings)
        local block_targets = {}
        block_targets[region.entry.label.name] = block_param_target(region.entry.params)
        for i = 1, #(region.blocks or {}) do block_targets[region.blocks[i].label.name] = block_param_target(region.blocks[i].params) end
        local function check_block(block, is_entry)
            local bindings = block_param_bindings(region.region_id, block.label, block.params, is_entry)
            if is_entry then append_all(bindings, entry_extra_bindings or {}) end
            local state = check_owned_stmt_body(block.body or {}, state_new(bindings, region_frags), issues, block_targets, nil)
            if state.reachable then state_report_live(state, issues, "owned dropped") end
        end
        check_block(region.entry, true)
        for i = 1, #(region.blocks or {}) do check_block(region.blocks[i], false) end
    end

    local function type_entry_block(region_id, block, ctx, yield_mode)
        local entry_params = {}
        local issues = {}
        local params = {}
        for i = 1, #block.params do
            local p = pvm.with(block.params[i], { ty = canonical_type(ctx.env, block.params[i].ty) })
            local init = type_expr_expect(block.params[i].init, ctx, p.ty)
            params[i] = pvm.with(p, { init = init.expr })
            append_all(issues, init.issues)
            if not arg_matches_param(p.ty, init.ty) then check_expected("block param " .. block.params[i].name, p.ty, init.ty, issues) end
        end
        entry_params = params
        local block_env = env_with_block_params(ctx.env, region_id, block.label, entry_params, true)
        local body = type_stmt_body(block.body, ctx_with_yield(ctx_with_env(ctx, block_env), yield_mode))
        append_all(issues, body.issues)
        return Tr.EntryControlBlock(block.label, entry_params, body.stmts), issues
    end

    local function type_control_block(region_id, block, ctx, yield_mode)
        local params = {}
        for i = 1, #block.params do params[i] = pvm.with(block.params[i], { ty = canonical_type(ctx.env, block.params[i].ty) }) end
        local block_env = env_with_block_params(ctx.env, region_id, block.label, params, false)
        local body = type_stmt_body(block.body, ctx_with_yield(ctx_with_env(ctx, block_env), yield_mode))
        return Tr.ControlBlock(block.label, params, body.stmts), body.issues
    end

    local function validate_control(region)
        local issues = {}
        local decision = control_api.decide(region)
        if pvm.classof(decision) == Tr.ControlDecisionIrreducible then issues[#issues + 1] = Tr.TypeIssueInvalidControl(region.region_id, decision.reject) end
        return issues
    end

    local function body_has_region_use(stmts)
        for i = 1, #(stmts or {}) do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtUseRegionFrag then return true end
            if cls == Tr.StmtIf and (body_has_region_use(stmt.then_body) or body_has_region_use(stmt.else_body)) then return true end
            if cls == Tr.StmtSwitch then
                for j = 1, #(stmt.arms or {}) do if body_has_region_use(stmt.arms[j].body) then return true end end
                for j = 1, #(stmt.variant_arms or {}) do if body_has_region_use(stmt.variant_arms[j].body) then return true end end
                if body_has_region_use(stmt.default_body) then return true end
            end
            if cls == Tr.StmtControl then
                if body_has_region_use(stmt.region.entry.body) then return true end
                for j = 1, #(stmt.region.blocks or {}) do if body_has_region_use(stmt.region.blocks[j].body) then return true end end
            end
        end
        return false
    end

    local function region_has_region_use(region)
        if body_has_region_use(region.entry.body) then return true end
        for i = 1, #(region.blocks or {}) do if body_has_region_use(region.blocks[i].body) then return true end end
        return false
    end

    type_control_stmt_region = pvm.phase("moonlift_tree_typecheck_control_stmt_region", {
        [Tr.ControlStmtRegion] = function(self, ctx)
            local entry, issues = type_entry_block(self.region_id, self.entry, ctx, Tr.TypeYieldVoid)
            local blocks = {}
            for i = 1, #self.blocks do local b, bi = type_control_block(self.region_id, self.blocks[i], ctx, Tr.TypeYieldVoid); blocks[#blocks + 1] = b; append_all(issues, bi) end
            local region = Tr.ControlStmtRegion(self.region_id, entry, blocks); if not region_has_region_use(region) then append_all(issues, validate_control(region)) end
            check_owned_control_region(region, issues, ctx.region_frags)
            return pvm.once(Tr.TypeControlStmtRegionResult(region, issues))
        end,
    }, { args_cache = "last" })

    type_control_expr_region = pvm.phase("moonlift_tree_typecheck_control_expr_region", {
        [Tr.ControlExprRegion] = function(self, ctx)
            local result_ty = canonical_type(ctx.env, self.result_ty)
            local entry, issues = type_entry_block(self.region_id, self.entry, ctx, Tr.TypeYieldValue(result_ty))
            local blocks = {}
            for i = 1, #self.blocks do local b, bi = type_control_block(self.region_id, self.blocks[i], ctx, Tr.TypeYieldValue(result_ty)); blocks[#blocks + 1] = b; append_all(issues, bi) end
            local region = Tr.ControlExprRegion(self.region_id, result_ty, entry, blocks); if not region_has_region_use(region) then append_all(issues, validate_control(region)) end
            check_owned_control_region(region, issues, ctx.region_frags)
            return pvm.once(Tr.TypeControlExprRegionResult(region, issues))
        end,
    }, { args_cache = "last" })

    local function env_with_params(module_env, name, params)
        local env = module_env
        for i = 1, #params do
            local binding = B.Binding(C.Id("arg:" .. name .. ":" .. params[i].name), params[i].name, params[i].ty, B.BindingClassArg(i - 1))
            env = env_add_value(env, B.ValueEntry(params[i].name, binding))
        end
        return env
    end

    local function type_contract(contract, ctx)
        local cls = pvm.classof(contract)
        local issues = {}
        if cls == Tr.ContractBounds then
            local base = pvm.one(type_expr(contract.base, ctx)); local len = type_expr_expect(contract.len, ctx, Ty.TScalar(C.ScalarIndex))
            append_all(issues, base.issues); append_all(issues, len.issues)
            local base_access = lease_access_base(base.ty)
            if pvm.classof(base_access) ~= Ty.TPtr and pvm.classof(base_access) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("bounds base", Ty.TScalar(C.ScalarRawPtr), base.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("bounds len", Ty.TScalar(C.ScalarIndex), len.ty) end
            return Tr.ContractBounds(base.expr, len.expr), issues
        elseif cls == Tr.ContractWindowBounds then
            local base = pvm.one(type_expr(contract.base, ctx)); local base_len = type_expr_expect(contract.base_len, ctx, Ty.TScalar(C.ScalarIndex)); local start = type_expr_expect(contract.start, ctx, Ty.TScalar(C.ScalarIndex)); local len = type_expr_expect(contract.len, ctx, Ty.TScalar(C.ScalarIndex))
            append_all(issues, base.issues); append_all(issues, base_len.issues); append_all(issues, start.issues); append_all(issues, len.issues)
            local base_access = lease_access_base(base.ty)
            if pvm.classof(base_access) ~= Ty.TPtr and pvm.classof(base_access) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("window_bounds base", Ty.TScalar(C.ScalarRawPtr), base.ty) end
            if not is_integer_scalar(base_len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("window_bounds base_len", Ty.TScalar(C.ScalarIndex), base_len.ty) end
            if not is_integer_scalar(start.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("window_bounds start", Ty.TScalar(C.ScalarIndex), start.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("window_bounds len", Ty.TScalar(C.ScalarIndex), len.ty) end
            return Tr.ContractWindowBounds(base.expr, base_len.expr, start.expr, len.expr), issues
        elseif cls == Tr.ContractDisjoint then
            local a = pvm.one(type_expr(contract.a, ctx)); local b = pvm.one(type_expr(contract.b, ctx))
            append_all(issues, a.issues); append_all(issues, b.issues)
            local a_access, b_access = lease_access_base(a.ty), lease_access_base(b.ty)
            if pvm.classof(a_access) ~= Ty.TPtr and pvm.classof(a_access) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("disjoint lhs", Ty.TScalar(C.ScalarRawPtr), a.ty) end
            if pvm.classof(b_access) ~= Ty.TPtr and pvm.classof(b_access) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("disjoint rhs", Ty.TScalar(C.ScalarRawPtr), b.ty) end
            return Tr.ContractDisjoint(a.expr, b.expr), issues
        elseif cls == Tr.ContractSameLen then
            local a = pvm.one(type_expr(contract.a, ctx)); local b = pvm.one(type_expr(contract.b, ctx))
            append_all(issues, a.issues); append_all(issues, b.issues)
            local a_access, b_access = lease_access_base(a.ty), lease_access_base(b.ty)
            if pvm.classof(a_access) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("same_len lhs", Ty.TView(void_ty()), a.ty) end
            if pvm.classof(b_access) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("same_len rhs", Ty.TView(void_ty()), b.ty) end
            return Tr.ContractSameLen(a.expr, b.expr), issues
        elseif cls == Tr.ContractNoAlias or cls == Tr.ContractReadonly or cls == Tr.ContractWriteonly or cls == Tr.ContractInvalidate or cls == Tr.ContractPreserve then
            local base = pvm.one(type_expr(contract.base, ctx)); append_all(issues, base.issues)
            local base_access = lease_access_base(base.ty)
            if pvm.classof(base_access) ~= Ty.TPtr and pvm.classof(base_access) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("memory contract base", Ty.TScalar(C.ScalarRawPtr), base.ty) end
            if cls == Tr.ContractNoAlias then return Tr.ContractNoAlias(base.expr), issues end
            if cls == Tr.ContractReadonly then return Tr.ContractReadonly(base.expr), issues end
            if cls == Tr.ContractWriteonly then return Tr.ContractWriteonly(base.expr), issues end
            if cls == Tr.ContractInvalidate then return Tr.ContractInvalidate(base.expr), issues end
            return Tr.ContractPreserve(base.expr), issues
        end
        return contract, issues
    end

    local function type_contracts(contracts, ctx)
        local out, issues = {}, {}
        for i = 1, #contracts do local c, ci = type_contract(contracts[i], ctx); out[#out + 1] = c; append_all(issues, ci) end
        return out, issues
    end

    local function check_func_types(func, issues)
        for i = 1, #(func.params or {}) do check_type_policy(func.params[i].ty, issues, "param " .. tostring(func.params[i].name)) end
        check_type_policy(func.result, issues, "result")
        if type_contains_lease(func.result) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape result", func.result) end
    end

    local function check_region_frag_signature(frag, module_env, issues)
        local ctx = Tr.TypeCheckEnv(module_env, Ty.TScalar(C.ScalarVoid), Tr.TypeYieldNone, {})
        for i = 1, #(frag.params or {}) do
            check_type_policy(frag.params[i].ty, issues, "region param " .. tostring(frag.params[i].name))
        end
        for i = 1, #(frag.conts or {}) do
            local cont = frag.conts[i]
            for j = 1, #(cont.params or {}) do
                local param = cont.params[j]
                check_type_policy(param.ty, issues, "continuation " .. tostring(cont.pretty_name) .. " param " .. tostring(param.name))
            end
            check_handle_resolution_signature(ctx, frag.params, cont.params, issues, "region " .. tostring(cont.pretty_name))
        end
    end

    local function canonical_func(self, module_env)
        return pvm.with(self, { params = canonical_params(module_env, self.params), result = canonical_type(module_env, self.result) })
    end

    local function canonical_block_params(module_env, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = pvm.with(params[i], { ty = canonical_type(module_env, params[i].ty) }) end
        return out
    end

    local function canonical_entry_params(module_env, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = pvm.with(params[i], { ty = canonical_type(module_env, params[i].ty) }) end
        return out
    end

    local function canonical_region_frag(module_env, frag)
        local params = {}
        for i = 1, #(frag.params or {}) do params[i] = pvm.with(frag.params[i], { ty = canonical_type(module_env, frag.params[i].ty) }) end
        local conts = {}
        for i = 1, #(frag.conts or {}) do conts[i] = pvm.with(frag.conts[i], { params = canonical_block_params(module_env, frag.conts[i].params) }) end
        local entry = pvm.with(frag.entry, { params = canonical_entry_params(module_env, frag.entry.params) })
        local blocks = {}
        for i = 1, #(frag.blocks or {}) do blocks[i] = pvm.with(frag.blocks[i], { params = canonical_block_params(module_env, frag.blocks[i].params) }) end
        return pvm.with(frag, { params = params, conts = conts, entry = entry, blocks = blocks })
    end

    local function type_plain_func(self, module_env, region_frags)
        local func = canonical_func(self, module_env)
        local ctx = Tr.TypeCheckEnv(env_with_params(module_env, func.name, func.params), func.result, Tr.TypeYieldNone, region_frags or {})
        local body = type_stmt_body(func.body, ctx)
        local issues = {}; check_func_types(func, issues); append_all(issues, body.issues)
        check_owned_function(func.name, func.params, body.stmts, issues, ctx.region_frags)
        return Tr.TypeFuncResult(pvm.with(func, { body = body.stmts }), issues)
    end

    local function type_contract_func(self, module_env, region_frags)
        local func = canonical_func(self, module_env)
        local ctx = Tr.TypeCheckEnv(env_with_params(module_env, func.name, func.params), func.result, Tr.TypeYieldNone, region_frags or {})
        local contracts, issues = type_contracts(func.contracts, ctx)
        check_func_types(func, issues)
        local body = type_stmt_body(func.body, ctx)
        append_all(issues, body.issues)
        check_owned_function(func.name, func.params, body.stmts, issues, ctx.region_frags)
        return Tr.TypeFuncResult(pvm.with(func, { contracts = contracts, body = body.stmts }), issues)
    end

    type_func = pvm.phase("moonlift_tree_typecheck_func", {
        [Tr.FuncLocal] = function(self, module_env, region_frags) return pvm.once(type_plain_func(self, module_env, region_frags)) end,
        [Tr.FuncExport] = function(self, module_env, region_frags) return pvm.once(type_plain_func(self, module_env, region_frags)) end,
        [Tr.FuncLocalContract] = function(self, module_env, region_frags) return pvm.once(type_contract_func(self, module_env, region_frags)) end,
        [Tr.FuncExportContract] = function(self, module_env, region_frags) return pvm.once(type_contract_func(self, module_env, region_frags)) end,
        [Tr.FuncOpen] = function(self, module_env, region_frags) local ctx = Tr.TypeCheckEnv(module_env, self.result, Tr.TypeYieldNone, region_frags or {}); local body = type_stmt_body(self.body, ctx); local issues = {}; append_all(issues, body.issues); check_owned_function("<open>", {}, body.stmts, issues, ctx.region_frags); return pvm.once(Tr.TypeFuncResult(pvm.with(self, { body = body.stmts }), issues)) end,
    }, { args_cache = "last" })

    type_item = pvm.phase("moonlift_tree_typecheck_item", {
        [Tr.ItemFunc] = function(self, module_env, region_frags) local r = pvm.one(type_func(self.func, module_env, region_frags or {})); return pvm.once(Tr.TypeItemResult({ Tr.ItemFunc(r.func) }, r.issues)) end,
        [Tr.ItemConst] = function(self, module_env, region_frags)
            local ty = canonical_type(module_env, self.c.ty)
            local ctx = Tr.TypeCheckEnv(module_env, ty, Tr.TypeYieldNone, region_frags or {})
            local value = pvm.one(type_expr(self.c.value, ctx))
            local issues = {}; check_type_policy(ty, issues, "const"); append_all(issues, value.issues); check_expected("const", ty, value.ty, issues)
            if type_contains_lease(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape const", ty) end
            if type_contains_owned(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned stored in durable field", ty) end
            return pvm.once(Tr.TypeItemResult({ Tr.ItemConst(pvm.with(self.c, { ty = ty, value = value.expr })) }, issues))
        end,
        [Tr.ItemStatic] = function(self, module_env, region_frags)
            local ty = canonical_type(module_env, self.s.ty)
            local ctx = Tr.TypeCheckEnv(module_env, ty, Tr.TypeYieldNone, region_frags or {})
            local value = pvm.one(type_expr(self.s.value, ctx))
            local issues = {}; check_type_policy(ty, issues, "static"); append_all(issues, value.issues); check_expected("static", ty, value.ty, issues)
            if type_contains_lease(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape static", ty) end
            if type_contains_owned(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned stored in durable field", ty) end
            return pvm.once(Tr.TypeItemResult({ Tr.ItemStatic(pvm.with(self.s, { ty = ty, value = value.expr })) }, issues))
        end,
        [Tr.ItemExtern] = function(self) local issues = {}; check_func_types(self.func, issues); return pvm.once(Tr.TypeItemResult({ self }, issues)) end,
        [Tr.ItemImport] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
        [Tr.ItemType] = function(self)
            local issues = {}
            local cls = pvm.classof(self.t)
            if cls == Tr.TypeDeclStruct or cls == Tr.TypeDeclUnion then
                for i = 1, #self.t.fields do check_type_policy(self.t.fields[i].ty, issues, "field " .. self.t.fields[i].field_name); if type_contains_lease(self.t.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape field", self.t.fields[i].ty) end; if type_contains_owned(self.t.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned stored in durable field", self.t.fields[i].ty) end end
            elseif cls == Tr.TypeDeclEnumSugar then
                local seen = {}
                for i = 1, #self.t.variants do
                    local name = variant_name_text(self.t.variants[i])
                    if seen[name] then issues[#issues + 1] = Tr.TypeIssueDuplicateVariant(self.t.name, name) end
                    seen[name] = true
                end
            elseif cls == Tr.TypeDeclTaggedUnionSugar then
                local seen = {}
                local is_region_call_result = type(self.t.name) == "string" and self.t.name:match("^__moon_region_call_") ~= nil
                for i = 1, #self.t.variants do
                    local v = self.t.variants[i]
                    local name = v.name
                    check_type_policy(v.payload, issues, "variant " .. name)
                    if type_contains_lease(v.payload) then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and "region call lease payload" or "lease escape variant field", v.payload)
                    end
                    if type_contains_owned(v.payload) then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and "owned region call payload" or "owned stored in durable field", v.payload)
                    end
                    for j = 1, #(v.fields or {}) do
                        check_type_policy(v.fields[j].ty, issues, "variant field " .. v.fields[j].field_name)
                        if type_contains_lease(v.fields[j].ty) then
                            issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and "region call lease payload" or "lease escape variant field", v.fields[j].ty)
                        end
                        if type_contains_owned(v.fields[j].ty) then
                            issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and "owned region call payload" or "owned stored in durable field", v.fields[j].ty)
                        end
                    end
                    if seen[name] then issues[#issues + 1] = Tr.TypeIssueDuplicateVariant(self.t.name, name) end
                    seen[name] = true
                end
            elseif cls == Tr.TypeDeclHandle then
                if pvm.classof(self.t.repr) ~= Ty.HandleReprScalar then issues[#issues + 1] = Tr.TypeIssueExpected("handle repr", Ty.THandle(Ty.TypeRefPath(C.Path({ C.Name(self.t.name) })), Ty.HandleReprScalar(C.ScalarU32)), Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(self.t.name) })))) end
            end
            return pvm.once(Tr.TypeItemResult({ self }, issues))
        end,
        [Tr.ItemUseTypeDeclSlot] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
        [Tr.ItemUseItemsSlot] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
        [Tr.ItemRegionFrag] = function(self, module_env, region_frags)
            local issues = {}
            check_region_frag_signature(self.frag, module_env, issues)
            local params = {}
            for i = 1, #(self.frag.params or {}) do params[i] = Ty.Param(self.frag.params[i].name, canonical_type(module_env, self.frag.params[i].ty)) end
            local ctx = Tr.TypeCheckEnv(env_with_params(module_env, "region:" .. tostring(region_frag_name_text(self.frag) or "?"), params), Ty.TScalar(C.ScalarVoid), Tr.TypeYieldNone, region_frags or {})
            local entry = pvm.with(self.frag.entry, {
                params = (function()
                    local out = {}
                    for i = 1, #(self.frag.entry.params or {}) do out[i] = pvm.with(self.frag.entry.params[i], { ty = canonical_type(module_env, self.frag.entry.params[i].ty) }) end
                    return out
                end)()
            })
            local runtime_bindings = {}
            for i = 1, #params do
                local frag_name = tostring(region_frag_name_text(self.frag) or "?")
                local open_param = self.frag.params and self.frag.params[i] or nil
                local class = open_param and B.BindingClassOpenParam(open_param) or B.BindingClassArg(i - 1)
                local b = B.Binding(C.Id("open-param:" .. frag_name .. ":" .. params[i].name), params[i].name, params[i].ty, class)
                runtime_bindings[#runtime_bindings + 1] = B.ValueEntry(params[i].name, b)
            end
            local region_id = "region-frag:" .. tostring(region_frag_name_text(self.frag) or "?")
            local typed_entry, entry_issues = type_entry_block(region_id, entry, ctx, Tr.TypeYieldVoid)
            append_all(issues, entry_issues)
            local typed_blocks = {}
            for i = 1, #(self.frag.blocks or {}) do
                local b, bi = type_control_block(region_id, self.frag.blocks[i], ctx, Tr.TypeYieldVoid)
                typed_blocks[#typed_blocks + 1] = b
                append_all(issues, bi)
            end
            local typed_region = Tr.ControlStmtRegion(region_id, typed_entry, typed_blocks)
            check_owned_control_region(typed_region, issues, region_frags or {}, runtime_bindings)
            return pvm.once(Tr.TypeItemResult({}, issues))
        end,
        [Tr.ItemExprFrag] = function() return pvm.once(Tr.TypeItemResult({}, {})) end,
        [Tr.ItemUseModule] = function(self)
            local r = pvm.one(type_module(self.module))
            return pvm.once(Tr.TypeItemResult({ pvm.with(self, { module = r.module }) }, r.issues))
        end,
        [Tr.ItemUseModuleSlot] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
    }, { args_cache = "last" })

    local function type_module_with_layout_env(module, extra_layout_env, target)
        local base_env = module_type_api.env(module, target)
        attach_semantic_defs(base_env, build_variant_defs(module, base_env.module_name), build_handle_defs(module, base_env.module_name), build_func_effect_defs(module))
        local module_env = merge_env_layouts(base_env, extra_layout_env)
        local region_frags = {}
        for i = 1, #(module.items or {}) do
            if pvm.classof(module.items[i]) == Tr.ItemRegionFrag then region_frags[#region_frags + 1] = canonical_region_frag(module_env, module.items[i].frag) end
        end
        local items = {}
        local issues = {}
        for i = 1, #module.items do local r = pvm.one(type_item(module.items[i], module_env, region_frags)); append_all(items, r.items); append_all(issues, r.issues) end
        return Tr.TypeModuleResult(Tr.Module(Tr.ModuleTyped(module_env.module_name), items), issues)
    end

    type_module = pvm.phase("moonlift_tree_typecheck_module", {
        [Tr.Module] = function(module)
            return pvm.once(type_module_with_layout_env(module, nil, nil))
        end,
    })

    return {
        expr = type_expr,
        place = type_place,
        stmt = type_stmt,
        stmt_body = type_stmt_body,
        control_stmt_region = type_control_stmt_region,
        control_expr_region = type_control_expr_region,
        func = type_func,
        item = type_item,
        module = type_module,
        check_module = function(module, opts)
            opts = opts or {}
            local result = opts.layout_env and type_module_with_layout_env(module, opts.layout_env, opts.target or opts.c_target) or type_module_with_layout_env(module, nil, opts.target or opts.c_target)
            local collector = opts.collector
            if collector then
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

local Format = require("moonlift.error.format")

local function site_description(site)
    -- Produces a human-readable context string from a site string
    if not site or site == "" then return "expression" end
    -- Check specific site types
    if site:find("let ") then return "variable initializer" end
    if site:find("var ") then return "variable initializer" end
    if site:find("return") then return "return value" end
    if site:find("yield") then return "yielded value" end
    if site:find("set") then return "assignment" end
    if site:find("if cond") then return "if condition" end
    if site:find("select cond") then return "select condition" end
    if site:find("if branches") then return "if branches" end
    if site:find("select branches") then return "select branches" end
    if site:find("call") then return "call argument" end
    if site:find("index") then return "index expression" end
    if site:find("view data") then return "view data" end
    if site:find("view len") or site:find("view stride") or site:find("view window") then return "view" end
    if site:find("bounds") then return "bounds" end
    if site:find("window_bounds") then return "window_bounds" end
    if site:find("disjoint") then return "disjoint" end
    if site:find("same_len") then return "same_len" end
    if site:find("memory contract") then return "memory contract" end
    if site:find("atomic") then return "atomic" end
    if site:find("block param") then return "block parameter" end
    if site:find("assert") then return "assert" end
    if site:find("switch key") then return "switch key" end
    if site:find("switch arm") then return "switch arm" end
    if site:find("array elem") then return "array element" end
    if site:find("len") then return "len" end
    if site:find("const") or site:find("static") then return "constant initializer" end
    return site
end

local function explain_type_issue(issue, analysis)
    analysis = analysis or { anchors = {} }
    local resolvers = require("moonlift.error.span_resolvers")
    local pvm = require("moonlift.pvm")
    local span = resolvers.typecheck_resolver(issue, analysis)
    local cls = pvm.classof(issue)
    if not cls then return { code = "E9999", severity = "error", primary = { span = span, message = tostring(issue) } } end
    local kind = cls.kind

    if kind == "TypeIssueExpected" then
        -- Port of E0301 builder logic
        local site = issue.site or "expression"
        local expected = Format.type_name(issue.expected)
        local actual = Format.type_name(issue.actual)
        local expected_raw = issue.expected
        local actual_raw = issue.actual
        local notes = {}
        local suggestions = {}

        -- Context-specific notes
        if site:find("call") then
            notes[#notes + 1] = { message = "this argument has type `" .. actual .. "`, but the function expects `" .. expected .. "`" }
        elseif site:find("let ") or site:find("var ") then
            local var_name = site:match("let (%w+)") or site:match("var (%w+)") or ""
            notes[#notes + 1] = { message = "the initializer has type `" .. actual .. "`, but the variable is declared as `" .. expected .. "`" }
        elseif site:find("return") then
            notes[#notes + 1] = { message = "the return value has type `" .. actual .. "`, but the function returns `" .. expected .. "`" }
        elseif site:find("yield") then
            notes[#notes + 1] = { message = "the yielded value has type `" .. actual .. "`, but the region yields `" .. expected .. "`" }
        elseif site:find("set") then
            notes[#notes + 1] = { message = "the assigned value has type `" .. actual .. "`, but the target has type `" .. expected .. "`" }
        elseif site:find("if cond") or site:find("select cond") then
            notes[#notes + 1] = { message = "the condition has type `" .. actual .. "`, but the condition must be `bool`" }
        elseif site:find("if branches") or site:find("select branches") then
            notes[#notes + 1] = { message = "both branches must have the same type; the then-branch is `" .. actual .. "`, the else-branch is `" .. expected .. "`" }
        elseif site:find("index") then
            notes[#notes + 1] = { message = "indexing requires an integer type, got `" .. actual .. "`" }
        elseif site:find("view data") then
            notes[#notes + 1] = { message = "view data must be a `ptr` or `view`, got `" .. actual .. "`" }
        elseif site:find("view len") or site:find("view stride") or site:find("view window") or site:find("bounds") or site:find("window_bounds") then
            notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
        elseif site:find("disjoint") then
            notes[#notes + 1] = { message = "disjoint contract requires `ptr` or `view`, got `" .. actual .. "`" }
        elseif site:find("same_len") then
            notes[#notes + 1] = { message = "same_len contract requires `view`, got `" .. actual .. "`" }
        elseif site:find("memory contract") then
            notes[#notes + 1] = { message = "memory contract requires `ptr` or `view`, got `" .. actual .. "`" }
        elseif site:find("atomic") then
            notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
        elseif site:find("block param") then
            notes[#notes + 1] = { message = "block parameter initializer has type `" .. actual .. "`, but the parameter is declared as `" .. expected .. "`" }
        elseif site:find("assert") then
            notes[#notes + 1] = { message = "assert condition must be `bool`, got `" .. actual .. "`" }
        elseif site:find("switch key") then
            notes[#notes + 1] = { message = "switch key has type `" .. actual .. "`, but the switch expression is `" .. expected .. "`" }
        elseif site:find("switch arm") then
            notes[#notes + 1] = { message = "switch arm has type `" .. actual .. "`, but the default arm is `" .. expected .. "`" }
        elseif site:find("array elem") then
            notes[#notes + 1] = { message = "array element has type `" .. actual .. "`, but the array expects `" .. expected .. "`" }
        elseif site:find("len") then
            notes[#notes + 1] = { message = "`len` requires a `view`, got `" .. actual .. "`" }
        elseif site:find("const") or site:find("static") then
            notes[#notes + 1] = { message = "the initializer has type `" .. actual .. "`, but the declaration is `" .. expected .. "`" }
        else
            notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
        end

        -- Numeric conversion hint
        local function is_integer(ty)
            if not ty then return false end
            local tcls = pvm.classof(ty)
            if tcls and tcls.kind == "TScalar" and ty.scalar then
                local scls = pvm.classof(ty.scalar)
                return scls and (scls.kind == "ScalarI32" or scls.kind == "ScalarI64"
                    or scls.kind == "ScalarU32" or scls.kind == "ScalarU8"
                    or scls.kind == "ScalarI8" or scls.kind == "ScalarI16"
                    or scls.kind == "ScalarU16" or scls.kind == "ScalarU64"
                    or scls.kind == "ScalarIndex")
            end
            return false
        end

        if actual == "bool" and expected ~= "bool" then
            suggestions[#suggestions + 1] = { message = "to convert a boolean to an integer, use a conditional: `select(flag, 1, 0)`" }
        elseif actual == "f64" and is_integer(expected_raw) then
            suggestions[#suggestions + 1] = { message = "to convert a float to an integer, use `as(i32, value)`" }
        elseif is_integer(actual_raw) and expected == "f64" then
            suggestions[#suggestions + 1] = { message = "to convert an integer to a float, use `as(f64, value)`" }
        end

        return {
            code = "E0301",
            severity = "error",
            phase_context = "while type-checking",
            primary = { span = span, message = "type mismatch" },
            notes = notes,
            suggestions = suggestions,
        }
    end

    if kind == "TypeIssueNotCallable" then
        local ty = Format.type_name(issue.ty)
        return { code = "E0302", severity = "error", phase_context = "while type-checking a call",
            primary = { span = span, message = "type `" .. ty .. "` is not callable" },
            notes = { { message = "only `func` and `closure` types can be called" } },
            suggestions = { { message = "did you mean to index? write `expr[idx]` for element access" } } }
    end

    if kind == "TypeIssueNotIndexable" or kind == "TypeIssueNotPointer" then
        local ty = Format.type_name(issue.ty)
        return { code = "E0303", severity = "error", phase_context = "while type-checking an index",
            primary = { span = span, message = "type `" .. ty .. "` is not indexable" },
            notes = { { message = "only `view`, `ptr`, and `array` types support indexing" } },
            suggestions = { { message = "if you meant to access a field, use `.` syntax: `expr.field`" } } }
    end

    if kind == "TypeIssueArgCount" then
        return { code = "E0305", severity = "error", phase_context = "while type-checking",
            primary = { span = span, message = (issue.site or "call") .. " expected " .. tostring(issue.expected) .. " arguments, got " .. tostring(issue.actual) },
            suggestions = { { message = "check the function signature and add or remove arguments" } } }
    end

    if kind == "TypeIssueInvalidUnary" then
        local op = Format.op_symbol(issue.op)
        local ty = Format.type_name(issue.ty)
        local raw_op = tostring(issue.op or "")
        local function report(primary, notes, suggestions)
            return { code = "E0304", severity = "error", phase_context = "while type-checking an expression",
                primary = { span = span, message = primary }, notes = notes or {}, suggestions = suggestions or {} }
        end
        if raw_op == "lease escape return" then
            return report("lease escapes through return", {
                { message = "lease value `" .. ty .. "` is temporary access produced by a store or boundary" },
                { message = "leases may access memory inside their dynamic extent but may not be returned as durable identity" },
            }, { { message = "return a handle or copied scalar data instead, or keep the pointer parameter marked `noescape`" } })
        elseif raw_op == "lease escape yield" then
            return report("lease escapes through yield", {
                { message = "yielding `" .. ty .. "` would move temporary access outside the granting region" },
            }, { { message = "yield a handle/status protocol, not the lease pointer/view" } })
        elseif raw_op == "lease escape store" then
            return report("lease escapes through store", {
                { message = "storing `" .. ty .. "` would make temporary access durable" },
            }, { { message = "store the handle, or copy the data through the lease instead" } })
        elseif raw_op == "lease escape call" then
            return report("lease passed to retaining parameter", {
                { message = "a lease can only be passed to another `lease` or `noescape` parameter" },
                { message = "plain `ptr`/`view` parameters are treated as possibly retained" },
            }, { { message = "mark the callee parameter `noescape`, or change it to `lease ptr(T)` / `lease view(T)`" } })
        elseif raw_op == "lease invalidating call" then
            return report("call may invalidate store while lease is live", {
                { message = "live lease `" .. ty .. "` may refer to storage that this call can move, free, compact, clear, or reuse" },
                { message = "`readonly` and `preserve` parameters keep leases valid; unannotated pointer/view parameters are conservative invalidators" },
            }, { { message = "end the lease scope before the call, call a `preserve`/`readonly` API, or use `lease(store)` to associate the lease with the correct store" } })
        elseif raw_op == "lease escape aggregate" then
            return report("lease captured in aggregate", {
                { message = "aggregates can outlive the current access extent, so they cannot contain `" .. ty .. "`" },
            }, { { message = "store a handle or copied data instead of the lease" } })
        elseif raw_op == "region call lease payload" then
            return report("cannot call region because continuation payload contains a lease", {
                { message = "continuation payload `" .. ty .. "` is temporary access and cannot be packed into the generated region-call result" },
            }, { { message = "use `emit` so temporary access stays in control flow" } })
        elseif raw_op == "lease escape field" or raw_op == "lease escape variant field" or raw_op == "lease escape result" or raw_op == "lease escape const" or raw_op == "lease escape static" then
            return report("lease appears in durable type position", {
                { message = "`" .. ty .. "` is temporary access, not storable data" },
                { message = "leases may appear in function/block/continuation parameters, not durable fields/results/statics" },
            }, { { message = "use a handle type for durable identity, or a plain pointer only at an unchecked ABI boundary" } })
        elseif raw_op == "owned dropped" then
            return report("owned obligation is not discharged", {
                { message = "`" .. ty .. "` must be transferred to an owned parameter/result or consumed by a closing protocol" },
                { message = "owned values do not have destructors and cannot silently fall out of scope" },
            }, { { message = "jump/return/yield/pass the owner to an `owned` slot, or call the explicit close/retire region" } })
        elseif raw_op == "owned use after move" then
            return report("owned value used after transfer", {
                { message = "`" .. ty .. "` was already consumed by an ownership transfer" },
            }, { { message = "thread the returned/re-yielded owner forward if the protocol preserves the obligation" } })
        elseif raw_op == "owned observed without transfer" or raw_op == "owned passed to non-owned parameter" then
            return report("owned value used without an ownership contract", {
                { message = "`" .. ty .. "` is linear authority and cannot be copied or borrowed as a plain value" },
            }, { { message = "make the callee parameter `owned`, or use a protocol that returns the owner on every preserving edge" } })
        elseif raw_op == "owned captured in aggregate" or raw_op == "owned stored in durable field" then
            return report("owned value captured in durable storage", {
                { message = "`" .. ty .. "` is a CFG obligation, not storable data" },
            }, { { message = "store the plain handle separately and keep the owned obligation in control flow" } })
        elseif raw_op == "owned branch mismatch" then
            return report("branches leave different owned obligations live", {
                { message = "all continuing paths must preserve the same live owned set" },
            }, { { message = "move the transfer before the branch, or return/jump/yield on the consuming path" } })
        elseif raw_op == "owned var cell unsupported" then
            return report("owned values cannot live in mutable cells", {
                { message = "`var owned T` needs explicit take/put semantics and is rejected" },
            }, { { message = "use `let` ownership threading through CFG parameters" } })
        elseif raw_op == "owned region call payload" then
            return report("owned payload cannot use expression-style region call", {
                { message = "`" .. ty .. "` cannot be packed into the generated region-call result aggregate" },
            }, { { message = "use `emit`/explicit continuations so ownership stays in CFG" } })
        elseif raw_op == "owned emit target mismatch" then
            return report("owned continuation payload has no matching target parameter", {
                { message = "`" .. ty .. "` must land in a target block/continuation parameter with the same owned type and name" },
            }, { { message = "add the owned parameter to the filled target, or consume the owner inside the emitted fragment" } })
        elseif raw_op == "owned lease composition" or raw_op == "owned access composition" or raw_op == "owned invalid base" then
            return report("invalid owned type composition", {
                { message = "`" .. ty .. "` mixes ownership authority with access modifiers or temporary leases" },
            }, { { message = "own the durable handle/resource token; borrow access through a protocol that returns the owner" } })
        elseif raw_op == "handle cast" then
            return report("handle representation is opaque", {
                { message = "handle `" .. ty .. "` is not its integer representation in safe casts" },
                { message = "ordinary `as(...)` cannot convert handles to or from raw scalars" },
            }, { { message = "resolve the handle through a store region, or use trusted `repr(handle)` / `Handle.from_repr(raw)` inside store implementation code" } })
        elseif raw_op == "handle repr" then
            return report("`repr` expects a handle", {
                { message = "`repr(value)` is the explicit trusted handle-to-scalar boundary" },
                { message = "the value has type `" .. ty .. "`, not a handle" },
            })
        end
        local unotes = {}
        local usuggestions = {}
        if op == "not" then
            unotes[#unotes + 1] = { message = "`not` requires a `bool` operand, got `" .. ty .. "`" }
        else
            unotes[#unotes + 1] = { message = "operator `" .. op .. "` is not defined for type `" .. ty .. "`" }
            unotes[#unotes + 1] = { message = "arithmetic operators require numeric types (i8, i16, i32, ...)" }
        end
        if ty == "bool" and op ~= "not" then
            usuggestions[#usuggestions + 1] = { message = "for boolean logic, use `not`: `not value`" }
        end
        return { code = "E0304", severity = "error", phase_context = "while type-checking an expression",
            primary = { span = span, message = "invalid unary operator `" .. op .. "` for type `" .. ty .. "`" },
            notes = unotes, suggestions = usuggestions }
    end

    if kind == "TypeIssueInvalidBinary" then
        local op = Format.op_symbol(issue.op)
        local lhs = Format.type_name(issue.lhs)
        local rhs = Format.type_name(issue.rhs)
        local bnotes = { { message = "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" } }
        local bsuggestions = {}
        if lhs == "bool" and rhs == "bool" then
            if op == "+" or op == "-" or op == "*" or op == "/" then
                bnotes[#bnotes + 1] = { message = "arithmetic operators require numeric types (i8, i16, i32, ...)" }
                bsuggestions[#bsuggestions + 1] = { message = "for boolean logic, use `and` / `or`: `a and b` or `a or b`" }
            end
        end
        if lhs ~= rhs then
            bnotes[#bnotes + 1] = { message = "both operands must have the same type" }
        end
        return { code = "E0304", severity = "error", phase_context = "while type-checking an expression",
            primary = { span = span, message = "invalid operator `" .. op .. "`" },
            notes = bnotes, suggestions = bsuggestions }
    end

    if kind == "TypeIssueInvalidCompare" or kind == "TypeIssueInvalidLogic" then
        local op = Format.op_symbol(issue.op)
        local lhs = Format.type_name(issue.lhs)
        local rhs = Format.type_name(issue.rhs)
        local cnotes = { { message = "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" } }
        if lhs ~= rhs then
            cnotes[#cnotes + 1] = { message = "both operands must have the same type" }
        end
        return { code = "E0304", severity = "error", phase_context = "while type-checking an expression",
            primary = { span = span, message = "invalid operator `" .. op .. "`" },
            notes = cnotes }
    end

    if kind == "TypeIssueUnresolvedValue" then
        return { code = "E0201", severity = "error", phase_context = "while resolving names",
            primary = { span = span, message = "unresolved name `" .. tostring(issue.name or "?") .. "`" },
            notes = { { message = "`" .. tostring(issue.name or "?") .. "` is not defined in this scope" } } }
    end

    if kind == "TypeIssueUnresolvedPath" then
        local path_text = tostring(issue.path_text or "?")
        local first_segment = issue.first_name or path_text:match("^([%w_]+)") or "?"
        -- Try did_you_mean on the first path segment
        local dym = nil
        local analysis_scope = analysis and analysis.in_scope_names or {}
        if #analysis_scope > 0 then
            local suggest = require("moonlift.error.suggest")
            dym = suggest.did_you_mean(first_segment, analysis_scope)
        end
        local suggestions = {}
        if dym then suggestions[#suggestions + 1] = { message = dym } end
        return { code = "E0202", severity = "error", phase_context = "while resolving names",
            primary = { span = span, message = "unresolved path `" .. path_text .. "`" },
            notes = { { message = "the first segment `" .. first_segment .. "` could not be resolved" } },
            suggestions = suggestions }
    end

    if kind == "TypeIssueInvalidControl" then
        local reject = issue.reject
        local reject_kind = reject and pvm.classof(reject).kind or "ControlRejectIrreducible"
        local label = reject and reject.label and reject.label.name or "?"
        local name = reject and reject.name or "?"
        local region = issue.region_id or (reject and reject.region_id) or "?"
        local code = "E0405"
        local primary = "invalid control flow"
        local notes = { { message = "region: " .. tostring(region) } }
        local suggestions = {}

        if reject_kind == "ControlRejectMissingJumpArg" then
            code = "E0404"
            primary = "jump to `" .. label .. "` is missing argument `" .. tostring(name) .. "`"
            notes[#notes + 1] = { message = "target block `" .. label .. "` declares parameter `" .. tostring(name) .. "`, but this jump does not provide it" }
            suggestions[#suggestions + 1] = { message = "pass `" .. tostring(name) .. " = ...` at the jump, or rename the target block parameter to match the existing argument" }
        elseif reject_kind == "ControlRejectExtraJumpArg" then
            code = "E0404"
            primary = "jump to `" .. label .. "` has extra argument `" .. tostring(name) .. "`"
            notes[#notes + 1] = { message = "target block `" .. label .. "` has no parameter named `" .. tostring(name) .. "`" }
            suggestions[#suggestions + 1] = { message = "remove the extra argument or add a matching block parameter" }
        elseif reject_kind == "ControlRejectDuplicateJumpArg" then
            code = "E0203"
            primary = "duplicate jump argument `" .. tostring(name) .. "` for `" .. label .. "`"
            suggestions[#suggestions + 1] = { message = "provide each jump argument name only once" }
        elseif reject_kind == "ControlRejectJumpType" then
            code = "E0301"
            primary = "jump argument `" .. tostring(name) .. "` for `" .. label .. "` has wrong type"
            notes[#notes + 1] = { message = "expected `" .. Format.type_name(reject.expected) .. "`, got `" .. Format.type_name(reject.actual) .. "`" }
        elseif reject_kind == "ControlRejectMissingLabel" then
            code = "E0402"
            primary = "missing jump target `" .. label .. "`"
            notes[#notes + 1] = { message = "block `" .. label .. "` is not defined in this region" }
        elseif reject_kind == "ControlRejectDuplicateLabel" then
            code = "E0203"
            primary = "duplicate block label `" .. label .. "`"
            suggestions[#suggestions + 1] = { message = "rename one of the blocks" }
        elseif reject_kind == "ControlRejectUnterminatedBlock" then
            code = "E0406"
            primary = "block `" .. label .. "` does not terminate"
            notes[#notes + 1] = { message = "every block path must end in jump, yield, return, or trap" }
        elseif reject_kind == "ControlRejectYieldOutsideRegion" then
            code = "E0407"
            primary = "invalid yield in control region"
            notes[#notes + 1] = { message = reject.reason or "yield kind does not match this region" }
        elseif reject_kind == "ControlRejectYieldType" then
            code = "E0301"
            primary = "yield has wrong type"
            notes[#notes + 1] = { message = "expected `" .. Format.type_name(reject.expected) .. "`, got `" .. Format.type_name(reject.actual) .. "`" }
        elseif reject_kind == "ControlRejectUnknownVariant" then
            code = "E0201"
            primary = "unknown switch variant `" .. tostring(reject.variant_name or "?") .. "`"
        else
            primary = "irreducible control flow"
            notes[#notes + 1] = { message = (reject and reject.reason) or "irreducible cycle detected" }
            notes[#notes + 1] = { message = "control flow is irreducible when no block dominates the others — restructure so one block is the single entry point" }
            suggestions[#suggestions + 1] = { message = "add a dispatch block that dominates all other blocks in this region" }
        end

        return { code = code, severity = "error", phase_context = "while checking control flow",
            primary = { span = span, message = primary }, notes = notes, suggestions = suggestions }
    end

    if kind == "TypeIssueMissingJumpTarget" then
        local label = (issue.label and issue.label.name) or (issue.label_name) or "?"
        local candidates = issue.block_names or {}
        local dym = Format.Suggest.did_you_mean(label, candidates)
        local mnotes = { { message = "block `" .. label .. "` is not defined in this region" } }
        local msuggestions = {}
        if dym then msuggestions[#msuggestions + 1] = { message = dym } end
        return { code = "E0402", severity = "error", phase_context = "while checking control flow",
            primary = { span = span, message = "missing jump target `" .. label .. "`" },
            notes = mnotes, suggestions = msuggestions }
    end

    if kind == "TypeIssueMissingJumpArg" or kind == "TypeIssueExtraJumpArg" then
        return { code = "E0404", severity = "error", phase_context = "while checking control flow",
            primary = { span = span, message = "jump argument count mismatch for `" .. tostring(issue.name or "?") .. "`" },
            notes = { { message = "check that the number of arguments passed to the jump matches the block parameters" } } }
    end

    if kind == "TypeIssueDuplicateJumpArg" then
        return { code = "E0203", severity = "error", phase_context = "while checking control flow",
            primary = { span = span, message = "duplicate jump argument `" .. tostring(issue.name or "?") .. "`" },
            suggestions = { { message = "remove the duplicate argument or rename one of them" } } }
    end

    if kind == "TypeIssueUnexpectedYield" then
        return { code = "E0407", severity = "error", phase_context = "while type-checking",
            primary = { span = span, message = "`yield` used outside a region" },
            notes = { { message = "`yield` can only be used inside a `region` or a `return region: T` expression" } },
            suggestions = { { message = "did you mean `return`? Functions use `return`, not `yield`" } } }
    end

    if kind == "TypeIssueUnknownVariant" then
        return { code = "E0201", severity = "error", phase_context = "while resolving names",
            primary = { span = span, message = "unknown variant `" .. tostring(issue.variant_name or "?") .. "` in type `" .. Format.type_name(issue.type_name) .. "`" } }
    end

    if kind == "TypeIssueVariantPayloadMismatch" then
        return { code = "E0301", severity = "error", phase_context = "while type-checking",
            primary = { span = span, message = "variant payload mismatch for `" .. tostring(issue.variant_name or "?") .. "`" } }
    end

    if kind == "TypeIssueDuplicateVariant" then
        return { code = "E0203", severity = "error", phase_context = "while checking declarations",
            primary = { span = span, message = "duplicate variant `" .. tostring(issue.variant_name or "?") .. "`" } }
    end

    -- Fallback
    return { code = "E9999", severity = "error", primary = { span = span, message = kind or tostring(issue) } }
end

M.explain_type_issue = explain_type_issue

return M
