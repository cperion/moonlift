local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.c_residence ~= nil then return T._moonlift_api_cache.c_residence end

    local Ty = T.MoonType
    local Tr = T.MoonTree
    local Bn = T.MoonBind
    local C = T.MoonC

    local classify_api = require("moonlift.type_classify").Define(T)
    local TypeToC = require("moonlift.type_to_c").Define(T)

    local api = {}

    local function binding_key(binding)
        return binding.id and binding.id.text or binding.name
    end

    local function expr_ty(expr)
        local h = expr and expr.h
        local cls = pvm.classof(h)
        if cls == Tr.ExprTyped or cls == Tr.ExprOpen then return h.ty end
        return nil
    end

    local function is_descriptor_type(ty)
        local cls = pvm.classof(ty)
        return cls == Ty.TView or cls == Ty.TSlice or cls == Ty.TClosure
    end

    local function is_aggregate_type(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TArray or cls == Ty.TNamed then return true end
        if ty == nil then return false end
        return pvm.classof(classify_api.classify(ty)) == Ty.TypeClassAggregate
    end

    local function rank(res)
        if res == C.CBackendResidenceAddressed then return 4 end
        if res == C.CBackendResidenceAggregate then return 3 end
        if res == C.CBackendResidenceDescriptor then return 2 end
        return 1
    end

    local function default_residence_for_type(ty)
        if is_descriptor_type(ty) then return C.CBackendResidenceDescriptor end
        if is_aggregate_type(ty) then return C.CBackendResidenceAggregate end
        return C.CBackendResidenceValue
    end

    local function new_state()
        return { residences = {}, reasons = {}, bindings = {}, address_taken = {}, mutable = {} }
    end

    local function remember(st, binding, residence, reason)
        if binding == nil then return end
        local key = binding_key(binding)
        st.bindings[key] = binding
        local old = st.residences[key]
        if old == nil or rank(residence) > rank(old) then st.residences[key] = residence end
        st.reasons[key] = st.reasons[key] or {}
        st.reasons[key][#st.reasons[key] + 1] = reason or "inferred"
    end

    local function ref_binding(ref)
        if pvm.classof(ref) == Bn.ValueRefBinding then return ref.binding end
        return nil
    end

    local walk_expr, walk_stmt, walk_place, walk_view, walk_region

    local function mark_ref_expr_if_by_address(st, expr, reason)
        if pvm.classof(expr) == Tr.ExprRef then
            local binding = ref_binding(expr.ref)
            if binding and (is_aggregate_type(binding.ty) or is_descriptor_type(binding.ty)) then
                remember(st, binding, C.CBackendResidenceAddressed, reason)
            end
        end
    end

    walk_place = function(st, place, mode)
        local cls = pvm.classof(place)
        if cls == Tr.PlaceRef then
            local binding = ref_binding(place.ref)
            if binding then
                if mode == "address" then
                    st.address_taken[binding_key(binding)] = true
                    remember(st, binding, C.CBackendResidenceAddressed, "address taken")
                elseif mode == "set" then
                    st.mutable[binding_key(binding)] = true
                    remember(st, binding, C.CBackendResidenceAddressed, "assigned through place")
                else
                    remember(st, binding, default_residence_for_type(binding.ty), "place reference")
                end
            end
        elseif cls == Tr.PlaceDeref then
            walk_expr(st, place.base)
        elseif cls == Tr.PlaceDot or cls == Tr.PlaceField then
            walk_place(st, place.base, mode)
        elseif cls == Tr.PlaceIndex then
            local bcls = pvm.classof(place.base)
            if bcls == Tr.IndexBaseExpr then walk_expr(st, place.base.base)
            elseif bcls == Tr.IndexBasePlace then walk_place(st, place.base.base, mode)
            elseif bcls == Tr.IndexBaseView then walk_view(st, place.base.view) end
            walk_expr(st, place.index)
        end
    end

    walk_view = function(st, view)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr then walk_expr(st, view.base)
        elseif cls == Tr.ViewContiguous then walk_expr(st, view.data); walk_expr(st, view.len)
        elseif cls == Tr.ViewStrided then walk_expr(st, view.data); walk_expr(st, view.len); walk_expr(st, view.stride)
        elseif cls == Tr.ViewRestrided then walk_view(st, view.base); walk_expr(st, view.stride)
        elseif cls == Tr.ViewWindow then walk_view(st, view.base); walk_expr(st, view.start); walk_expr(st, view.len)
        elseif cls == Tr.ViewRowBase then walk_view(st, view.base); walk_expr(st, view.row_offset)
        elseif cls == Tr.ViewInterleaved then walk_expr(st, view.data); walk_expr(st, view.len); walk_expr(st, view.stride); walk_expr(st, view.lane)
        elseif cls == Tr.ViewInterleavedView then walk_view(st, view.base); walk_expr(st, view.stride); walk_expr(st, view.lane) end
    end

    local function walk_expr_list(st, xs)
        for i = 1, #(xs or {}) do walk_expr(st, xs[i]) end
    end

    local function walk_stmt_list(st, xs)
        for i = 1, #(xs or {}) do walk_stmt(st, xs[i]) end
    end

    walk_expr = function(st, expr)
        if expr == nil then return end
        local cls = pvm.classof(expr)
        if cls == Tr.ExprLit or cls == Tr.ExprRef or cls == Tr.ExprNull or cls == Tr.ExprSizeOf or cls == Tr.ExprAlignOf then return end
        if cls == Tr.ExprDot then walk_expr(st, expr.base)
        elseif cls == Tr.ExprUnary then walk_expr(st, expr.value)
        elseif cls == Tr.ExprBinary or cls == Tr.ExprCompare or cls == Tr.ExprLogic then walk_expr(st, expr.lhs); walk_expr(st, expr.rhs)
        elseif cls == Tr.ExprCast or cls == Tr.ExprMachineCast or cls == Tr.ExprDeref or cls == Tr.ExprLen or cls == Tr.ExprIsNull then walk_expr(st, expr.value)
        elseif cls == Tr.ExprIntrinsic then walk_expr_list(st, expr.args)
        elseif cls == Tr.ExprAddrOf then walk_place(st, expr.place, "address")
        elseif cls == Tr.ExprCall then
            walk_expr(st, expr.callee)
            for i = 1, #(expr.args or {}) do
                mark_ref_expr_if_by_address(st, expr.args[i], "call argument requires materialization when ABI lowers by address")
                walk_expr(st, expr.args[i])
            end
        elseif cls == Tr.ExprField then walk_expr(st, expr.base)
        elseif cls == Tr.ExprIndex then
            local bcls = pvm.classof(expr.base)
            if bcls == Tr.IndexBaseExpr then walk_expr(st, expr.base.base)
            elseif bcls == Tr.IndexBasePlace then walk_place(st, expr.base.base)
            elseif bcls == Tr.IndexBaseView then walk_view(st, expr.base.view) end
            walk_expr(st, expr.index)
        elseif cls == Tr.ExprAgg then
            for i = 1, #(expr.fields or {}) do walk_expr(st, expr.fields[i].value) end
        elseif cls == Tr.ExprArray then walk_expr_list(st, expr.elems)
        elseif cls == Tr.ExprIf then walk_expr(st, expr.cond); walk_expr(st, expr.then_expr); walk_expr(st, expr.else_expr)
        elseif cls == Tr.ExprSelect then walk_expr(st, expr.cond); walk_expr(st, expr.then_expr); walk_expr(st, expr.else_expr)
        elseif cls == Tr.ExprSwitch then
            walk_expr(st, expr.value)
            for i = 1, #(expr.arms or {}) do walk_stmt_list(st, expr.arms[i].body); walk_expr(st, expr.arms[i].result) end
            for i = 1, #(expr.variant_arms or {}) do walk_stmt_list(st, expr.variant_arms[i].body); walk_expr(st, expr.variant_arms[i].result) end
            walk_stmt_list(st, expr.default_body or {}); walk_expr(st, expr.default_expr)
        elseif cls == Tr.ExprControl then walk_region(st, expr.region)
        elseif cls == Tr.ExprBlock then walk_stmt_list(st, expr.stmts); walk_expr(st, expr.result)
        elseif cls == Tr.ExprClosure then walk_stmt_list(st, expr.body)
        elseif cls == Tr.ExprView then walk_view(st, expr.view)
        elseif cls == Tr.ExprLoad or cls == Tr.ExprAtomicLoad then walk_expr(st, expr.addr)
        elseif cls == Tr.ExprAtomicRmw then walk_expr(st, expr.addr); walk_expr(st, expr.value)
        elseif cls == Tr.ExprAtomicCas then walk_expr(st, expr.addr); walk_expr(st, expr.expected); walk_expr(st, expr.replacement)
        elseif cls == Tr.ExprUseExprFrag then walk_expr_list(st, expr.args)
        elseif cls == Tr.ExprCtor then walk_expr_list(st, expr.args) end
    end

    walk_stmt = function(st, stmt)
        if stmt == nil then return end
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtLet then
            remember(st, stmt.binding, default_residence_for_type(stmt.binding.ty), "let binding")
            walk_expr(st, stmt.init)
            if pvm.classof(stmt.init) == Tr.ExprAgg or pvm.classof(stmt.init) == Tr.ExprArray then remember(st, stmt.binding, C.CBackendResidenceAggregate, "aggregate initializer") end
        elseif cls == Tr.StmtVar then
            remember(st, stmt.binding, C.CBackendResidenceAddressed, "mutable var binding")
            walk_expr(st, stmt.init)
        elseif cls == Tr.StmtSet then walk_place(st, stmt.place, "set"); walk_expr(st, stmt.value)
        elseif cls == Tr.StmtAtomicStore then walk_expr(st, stmt.addr); walk_expr(st, stmt.value)
        elseif cls == Tr.StmtExpr then walk_expr(st, stmt.expr)
        elseif cls == Tr.StmtAssert then walk_expr(st, stmt.cond)
        elseif cls == Tr.StmtIf then walk_expr(st, stmt.cond); walk_stmt_list(st, stmt.then_body); walk_stmt_list(st, stmt.else_body)
        elseif cls == Tr.StmtSwitch then
            walk_expr(st, stmt.value)
            for i = 1, #(stmt.arms or {}) do walk_stmt_list(st, stmt.arms[i].body) end
            for i = 1, #(stmt.variant_arms or {}) do walk_stmt_list(st, stmt.variant_arms[i].body) end
            walk_stmt_list(st, stmt.default_body)
        elseif cls == Tr.StmtJump or cls == Tr.StmtJumpCont then for i = 1, #(stmt.args or {}) do walk_expr(st, stmt.args[i].value) end
        elseif cls == Tr.StmtYieldValue or cls == Tr.StmtReturnValue then walk_expr(st, stmt.value)
        elseif cls == Tr.StmtControl then walk_region(st, stmt.region)
        elseif cls == Tr.StmtUseRegionFrag then walk_expr_list(st, stmt.args) end
    end

    walk_region = function(st, region)
        if region == nil then return end
        if region.entry then
            for i = 1, #(region.entry.params or {}) do walk_expr(st, region.entry.params[i].init) end
            walk_stmt_list(st, region.entry.body)
        end
        for i = 1, #(region.blocks or {}) do
            local block = region.blocks[i]
            for j = 1, #(block.params or {}) do
                local fake = Bn.Binding(T.MoonCore.Id("block:" .. region.region_id .. ":" .. block.label.name .. ":" .. block.params[j].name), block.params[j].name, block.params[j].ty, Bn.BindingClassBlockParam(region.region_id, block.label.name, j - 1))
                remember(st, fake, default_residence_for_type(block.params[j].ty), "control block parameter")
            end
            walk_stmt_list(st, block.body)
        end
    end

    local function seed_params(st, func)
        for i = 1, #(func.params or {}) do
            local p = func.params[i]
            local binding = Bn.Binding(T.MoonCore.Id("arg:" .. func.name .. ":" .. p.name), p.name, p.ty, Bn.BindingClassArg(i))
            local res = default_residence_for_type(p.ty)
            if is_aggregate_type(p.ty) then res = C.CBackendResidenceAddressed end
            remember(st, binding, res, "function parameter")
        end
    end

    local function analyze_func(func)
        local st = new_state()
        local cls = pvm.classof(func)
        if cls == Tr.FuncLocal or cls == Tr.FuncExport or cls == Tr.FuncLocalContract or cls == Tr.FuncExportContract then
            seed_params(st, func)
            walk_stmt_list(st, func.body)
        end
        return st
    end

    local function storage_for_binding(binding, id, name, st, ctx)
        st = st or new_state()
        local key = binding_key(binding)
        local res = st.residences[key] or default_residence_for_type(binding.ty)
        return C.CBackendLocalStorage(
            id,
            C.CBackendName(name or binding.name),
            TypeToC.type_to_c(binding.ty, ctx),
            res,
            C.CBackendLocalUninitialized,
            st.address_taken[key] == true
        )
    end

    api.analyze_func = analyze_func
    api.walk_expr = walk_expr
    api.walk_stmt = walk_stmt
    api.walk_place = walk_place
    api.default_residence_for_type = default_residence_for_type
    api.is_descriptor_type = is_descriptor_type
    api.is_aggregate_type = is_aggregate_type
    api.storage_for_binding = storage_for_binding
    api.binding_key = binding_key

    T._moonlift_api_cache.c_residence = api
    return api
end

return M
