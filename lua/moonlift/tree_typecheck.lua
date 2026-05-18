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

    local function env_with_values(env, values)
        return B.Env(env.module_name, values, env.types, env.layouts)
    end

    local function env_add_value(env, entry)
        local values = clone_values(env.values)
        values[#values + 1] = entry
        return env_with_values(env, values)
    end

    local function ctx_with_env(ctx, env)
        return Tr.TypeCheckEnv(env, ctx.return_ty, ctx.yield)
    end

    local function ctx_with_yield(ctx, yield)
        return Tr.TypeCheckEnv(ctx.env, ctx.return_ty, yield)
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

    local function int_literal_can_adopt(expr, expected)
        return pvm.classof(expr) == Tr.ExprLit
            and pvm.classof(expr.value) == C.LitInt
            and is_integer_scalar(expected)
    end

    local function array_len_const(len)
        if pvm.classof(len) == Ty.ArrayLenConst then return len.count end
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
        return result
    end

    local function ref_type(ref, env)
        local cls = pvm.classof(ref)
        if cls == B.ValueRefBinding then return ref.binding.ty, ref, {} end
        if cls == B.ValueRefSlot then return ref.slot.ty, ref, {} end
        if cls == B.ValueRefFuncSlot then return ref.slot.fn_ty, ref, {} end
        if cls == B.ValueRefConstSlot then return ref.slot.ty, ref, {} end
        if cls == B.ValueRefStaticSlot then return ref.slot.ty, ref, {} end
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
            if pvm.classof(base.ty) == Ty.TView then elem = base.ty.elem elseif pvm.classof(base.ty) == Ty.TPtr then elem = base.ty.elem end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { base = base.expr, elem = elem }), issues))
        end,
        [Tr.ViewContiguous] = function(self, ctx)
            local data = pvm.one(type_expr(self.data, ctx)); local len = type_expr_expect(self.len, ctx, index_ty())
            local issues = {}; append_all(issues, data.issues); append_all(issues, len.issues)
            local elem = self.elem
            if pvm.classof(data.ty) == Ty.TPtr then elem = data.ty.elem
            elseif pvm.classof(data.ty) == Ty.TView then elem = data.ty.elem
            else issues[#issues + 1] = Tr.TypeIssueExpected("view data", Ty.TScalar(C.ScalarRawPtr), data.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view len", index_ty(), len.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { data = data.expr, elem = elem, len = len.expr }), issues))
        end,
        [Tr.ViewStrided] = function(self, ctx)
            local data = pvm.one(type_expr(self.data, ctx)); local len = type_expr_expect(self.len, ctx, index_ty()); local stride = type_expr_expect(self.stride, ctx, index_ty())
            local issues = {}; append_all(issues, data.issues); append_all(issues, len.issues); append_all(issues, stride.issues)
            local elem = self.elem
            if pvm.classof(data.ty) == Ty.TPtr then elem = data.ty.elem
            elseif pvm.classof(data.ty) == Ty.TView then elem = data.ty.elem
            else issues[#issues + 1] = Tr.TypeIssueExpected("view data", Ty.TScalar(C.ScalarRawPtr), data.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view len", index_ty(), len.ty) end
            if not is_integer_scalar(stride.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("view stride", index_ty(), stride.ty) end
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { data = data.expr, elem = elem, len = len.expr, stride = stride.expr }), issues))
        end,
        [Tr.ViewRestrided] = function(self, ctx)
            local base = pvm.one(type_view(self.base, ctx)); local stride = pvm.one(type_expr(self.stride, ctx))
            local issues = {}; append_all(issues, base.issues); append_all(issues, stride.issues)
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
            local base = pvm.one(type_view(self.base, ctx)); local row_offset = pvm.one(type_expr(self.row_offset, ctx))
            local issues = {}; append_all(issues, base.issues); append_all(issues, row_offset.issues)
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { base = base.view, row_offset = row_offset.expr }), issues))
        end,
        [Tr.ViewInterleaved] = function(self, ctx)
            local data = pvm.one(type_expr(self.data, ctx)); local len = pvm.one(type_expr(self.len, ctx)); local stride = pvm.one(type_expr(self.stride, ctx)); local lane = pvm.one(type_expr(self.lane, ctx))
            local issues = {}; append_all(issues, data.issues); append_all(issues, len.issues); append_all(issues, stride.issues); append_all(issues, lane.issues)
            return pvm.once(Tr.TypeViewResult(pvm.with(self, { data = data.expr, len = len.expr, stride = stride.expr, lane = lane.expr }), issues))
        end,
        [Tr.ViewInterleavedView] = function(self, ctx)
            local base = pvm.one(type_view(self.base, ctx)); local stride = pvm.one(type_expr(self.stride, ctx)); local lane = pvm.one(type_expr(self.lane, ctx))
            local issues = {}; append_all(issues, base.issues); append_all(issues, stride.issues); append_all(issues, lane.issues)
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
            if pvm.classof(base.ty) == Ty.TView or pvm.classof(base.ty) == Ty.TPtr then
                return pvm.once(Tr.TypeIndexBaseResult(Tr.IndexBaseView(Tr.ViewFromExpr(base.expr, base.ty.elem)), base.ty.elem, issues))
            end
            if pvm.classof(base.ty) == Ty.TArray then
                if pvm.classof(base.expr) == Tr.ExprRef then
                    return pvm.once(Tr.TypeIndexBaseResult(Tr.IndexBasePlace(Tr.PlaceRef(Tr.PlaceTyped(base.ty), base.expr.ref), base.ty.elem), base.ty.elem, issues))
                end
                issues[#issues + 1] = Tr.TypeIssueNotIndexable(base.ty)
                return pvm.once(Tr.TypeIndexBaseResult(Tr.IndexBaseView(Tr.ViewFromExpr(base.expr, base.ty.elem)), base.ty.elem, issues))
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
            if pvm.classof(base.ty) == Ty.TPtr then ty = base.ty.elem else issues[#issues + 1] = Tr.TypeIssueNotPointer(base.ty) end
            return pvm.once(result_place(Tr.PlaceDeref(Tr.PlaceTyped(ty), base.expr), ty, issues))
        end,
        [Tr.PlaceDot] = function(self, ctx)
            local base = pvm.one(type_place(self.base, ctx)); local issues = {}; append_all(issues, base.issues)
            local lookup_ty = base.ty
            if pvm.classof(lookup_ty) == Ty.TPtr then lookup_ty = lookup_ty.elem end
            local layout = field_layout_for(ctx.env, lookup_ty, self.name)
            if layout ~= nil then
                return pvm.once(result_place(Tr.PlaceField(Tr.PlaceTyped(layout.ty), base.place, Sem.FieldByName(layout.field_name, layout.ty)), layout.ty, issues))
            end
            return pvm.once(result_place(Tr.PlaceDot(Tr.PlaceTyped(base.ty), base.place, self.name), base.ty, issues))
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
        [Tr.ExprCast] = function(self, ctx) local value = pvm.one(type_expr(self.value, ctx)); return pvm.once(result_expr(Tr.ExprCast(Tr.ExprTyped(self.ty), self.op, self.ty, value.expr), self.ty, value.issues)) end,
        [Tr.ExprMachineCast] = function(self, ctx) local value = pvm.one(type_expr(self.value, ctx)); return pvm.once(result_expr(Tr.ExprMachineCast(Tr.ExprTyped(self.ty), self.op, self.ty, value.expr), self.ty, value.issues)) end,
        [Tr.ExprLen] = function(self, ctx)
            local value = pvm.one(type_expr(self.value, ctx)); local issues = {}; append_all(issues, value.issues)
            if pvm.classof(value.ty) ~= Ty.TView and pvm.classof(value.ty) ~= Ty.TArray then issues[#issues + 1] = Tr.TypeIssueExpected("len", Ty.TView(void_ty()), value.ty) end
            return pvm.once(result_expr(Tr.ExprLen(Tr.ExprTyped(index_ty()), value.expr), index_ty(), issues))
        end,
        [Tr.ExprCall] = function(self, ctx)
            local issues = {}; local args = {}
            local fn_ty, target = nil, self.target
            if pvm.classof(self.target) == Sem.CallUnresolved then
                local callee = pvm.one(type_expr(self.target.callee, ctx)); append_all(issues, callee.issues); fn_ty = callee.ty
                if pvm.classof(fn_ty) == Ty.TClosure then
                    target = Sem.CallClosure(callee.expr, fn_ty)
                elseif pvm.classof(self.target.callee) == Tr.ExprRef and pvm.classof(callee.expr.ref) == B.ValueRefBinding then
                    local cls = pvm.classof(callee.expr.ref.binding.class)
                    if cls == B.BindingClassGlobalFunc then target = Sem.CallDirect(callee.expr.ref.binding.class.module_name, callee.expr.ref.binding.class.item_name, fn_ty)
                    elseif cls == B.BindingClassExtern then target = Sem.CallExtern(callee.expr.ref.binding.class.symbol, fn_ty)
                    else target = Sem.CallIndirect(callee.expr, fn_ty) end
                else
                    target = Sem.CallIndirect(callee.expr, fn_ty)
                end
            else
                if pvm.classof(self.target) == Sem.CallDirect or pvm.classof(self.target) == Sem.CallExtern or pvm.classof(self.target) == Sem.CallIndirect or pvm.classof(self.target) == Sem.CallClosure then fn_ty = self.target.fn_ty end
            end
            local result_ty, param_tys = callable_result(fn_ty or void_ty())
            if result_ty == nil then issues[#issues + 1] = Tr.TypeIssueNotCallable(fn_ty or void_ty()); result_ty = void_ty(); param_tys = {} end
            if #param_tys ~= #self.args then issues[#issues + 1] = Tr.TypeIssueArgCount("call", #param_tys, #self.args) end
            for i = 1, #self.args do
                local arg = type_expr_expect(self.args[i], ctx, param_tys[i]); append_all(issues, arg.issues); args[#args + 1] = arg.expr
                if param_tys[i] ~= nil then check_expected("call arg", param_tys[i], arg.ty, issues) end
            end
            return pvm.once(result_expr(Tr.ExprCall(Tr.ExprTyped(result_ty), target, args), result_ty, issues))
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
            for i = 1, #self.elems do local e = type_expr_expect(self.elems[i], ctx, self.elem_ty); elems[#elems + 1] = e.expr; append_all(issues, e.issues); check_expected("array elem", self.elem_ty, e.ty, issues) end
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
            local base = pvm.one(type_expr(self.base, ctx)); local issues = {}; append_all(issues, base.issues)
            local base_ty = base.ty
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
            return pvm.once(result_expr(Tr.ExprDot(Tr.ExprTyped(base.ty), base.expr, self.name), base.ty, issues))
        end,
        [Tr.ExprIntrinsic] = function(self, ctx)
            local issues = {}; local args = {}
            for i = 1, #self.args do local a = pvm.one(type_expr(self.args[i], ctx)); args[#args + 1] = a.expr; append_all(issues, a.issues) end
            local h_cls = pvm.classof(self.h)
            local ty = nil
            if h_cls == Tr.ExprTyped or h_cls == Tr.ExprOpen or h_cls == Tr.ExprSem or h_cls == Tr.ExprCode then ty = self.h.ty end
            if ty == nil or (pvm.classof(ty) == Ty.TScalar and ty.scalar == C.ScalarVoid and self.op ~= C.IntrinsicTrap and self.op ~= C.IntrinsicAssume) then
                ty = (#self.args > 0) and pvm.one(type_expr(self.args[1], ctx)).ty or void_ty()
            end
            if self.op == C.IntrinsicTrap or self.op == C.IntrinsicAssume then ty = void_ty() end
            return pvm.once(result_expr(Tr.ExprIntrinsic(Tr.ExprTyped(ty), self.op, args), ty, issues))
        end,
        [Tr.ExprAddrOf] = function(self, ctx) local place = pvm.one(type_place(self.place, ctx)); local ty = Ty.TPtr(place.ty); return pvm.once(result_expr(Tr.ExprAddrOf(Tr.ExprTyped(ty), place.place), ty, place.issues)) end,
        [Tr.ExprDeref] = function(self, ctx) local value = pvm.one(type_expr(self.value, ctx)); local issues = {}; append_all(issues, value.issues); local ty = void_ty(); if pvm.classof(value.ty) == Ty.TPtr then ty = value.ty.elem else issues[#issues + 1] = Tr.TypeIssueNotPointer(value.ty) end; return pvm.once(result_expr(Tr.ExprDeref(Tr.ExprTyped(ty), value.expr), ty, issues)) end,
        [Tr.ExprSwitch] = function(self, ctx)
            local value = pvm.one(type_expr(self.value, ctx))
            local default_body = type_stmt_body(self.default_body or {}, ctx)
            local default = pvm.one(type_expr(self.default_expr, default_body.env))
            local issues = {}; append_all(issues, value.issues); append_all(issues, default_body.issues); append_all(issues, default.issues)
            local arms = {}
            for i = 1, #self.arms do
                local key = type_switch_key(self.arms[i].key, ctx, value.ty, issues)
                local body = type_stmt_body(self.arms[i].body, ctx)
                local result = pvm.one(type_expr(self.arms[i].result, body.env))
                append_all(issues, body.issues); append_all(issues, result.issues)
                check_expected("switch arm", default.ty, result.ty, issues)
                arms[#arms + 1] = Tr.SwitchExprArm(key, body.stmts, result.expr)
            end
            return pvm.once(result_expr(Tr.ExprSwitch(Tr.ExprTyped(default.ty), value.expr, arms, default_body.stmts, default.expr), default.ty, issues))
        end,
        [Tr.ExprClosure] = function(self, ctx) local ty = Ty.TClosure(self.params, self.result); return pvm.once(result_expr(pvm.with(self, { h = Tr.ExprTyped(ty) }), ty, {})) end,
        [Tr.ExprSlotValue] = function(self, ctx) return pvm.once(result_expr(Tr.ExprSlotValue(Tr.ExprTyped(self.slot.ty), self.slot), self.slot.ty, {})) end,
        [Tr.ExprUseExprFrag] = function(self, ctx) local ty = void_ty(); return pvm.once(result_expr(pvm.with(self, { h = Tr.ExprTyped(ty) }), ty, {})) end,
    }, { args_cache = "last" })

    type_switch_key = function(key, ctx, value_ty, issues)
        local cls = pvm.classof(key)
        if cls == Sem.SwitchKeyExpr then
            local expr = pvm.one(type_expr(key.expr, ctx))
            append_all(issues, expr.issues)
            check_expected("switch key", value_ty, expr.ty, issues)
            return Sem.SwitchKeyExpr(expr.expr)
        end
        -- SwitchKeyRaw: if the raw string is a bare name (not a literal number),
        -- re-typecheck it as an expression so named constants resolve to their values.
        if cls == Sem.SwitchKeyRaw then
            local raw = key.raw
            -- Check if it looks like a non-numeric identifier
            if raw:match("^[%a_][%w_]*$") then
                local ref_expr = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(raw))
                local expr = pvm.one(type_expr(ref_expr, ctx))
                if #expr.issues == 0 then
                    check_expected("switch key", value_ty, expr.ty, issues)
                    return Sem.SwitchKeyExpr(expr.expr)
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
            local is_inferred = pvm.classof(self.binding.ty) == Ty.TScalar and self.binding.ty.scalar == C.ScalarVoid
            local init = is_inferred and pvm.one(type_expr(self.init, ctx)) or type_expr_expect(self.init, ctx, self.binding.ty)
            local issues = {}; append_all(issues, init.issues)
            local actual_ty = is_inferred and init.ty or self.binding.ty
            if not is_inferred then check_expected("let " .. self.binding.name, actual_ty, init.ty, issues) end
            local binding = pvm.with(self.binding, { ty = actual_ty, class = B.BindingClassLocalValue })
            local env = env_add_value(ctx.env, B.ValueEntry(binding.name, binding))
            return pvm.once(Tr.TypeStmtResult(ctx_with_env(ctx, env), { Tr.StmtLet(Tr.StmtTyped, binding, init.expr) }, issues))
        end,
        [Tr.StmtVar] = function(self, ctx)
            local is_inferred = pvm.classof(self.binding.ty) == Ty.TScalar and self.binding.ty.scalar == C.ScalarVoid
            local init = is_inferred and pvm.one(type_expr(self.init, ctx)) or type_expr_expect(self.init, ctx, self.binding.ty)
            local issues = {}; append_all(issues, init.issues)
            local actual_ty = is_inferred and init.ty or self.binding.ty
            if not is_inferred then check_expected("var " .. self.binding.name, actual_ty, init.ty, issues) end
            local binding = pvm.with(self.binding, { ty = actual_ty, class = B.BindingClassLocalCell })
            local env = env_add_value(ctx.env, B.ValueEntry(binding.name, binding))
            return pvm.once(Tr.TypeStmtResult(ctx_with_env(ctx, env), { Tr.StmtVar(Tr.StmtTyped, binding, init.expr) }, issues))
        end,
        [Tr.StmtSet] = function(self, ctx) local place = pvm.one(type_place(self.place, ctx)); local value = type_expr_expect(self.value, ctx, place.ty); local issues = {}; append_all(issues, place.issues); append_all(issues, value.issues); check_expected("set", place.ty, value.ty, issues); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtSet(Tr.StmtTyped, place.place, value.expr) }, issues)) end,
        [Tr.StmtAtomicStore] = function(self, ctx)
            local addr = type_expr_expect(self.addr, ctx, Ty.TPtr(self.ty)); local value = type_expr_expect(self.value, ctx, self.ty); local issues = {}; append_all(issues, addr.issues); append_all(issues, value.issues)
            check_expected("atomic_store addr", Ty.TPtr(self.ty), addr.ty, issues); check_expected("atomic_store value", self.ty, value.ty, issues); check_atomic_value_type("atomic_store", self.ty, issues)
            return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtAtomicStore(Tr.StmtTyped, self.ty, addr.expr, value.expr, self.ordering) }, issues))
        end,
        [Tr.StmtAtomicFence] = function(self, ctx) return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtAtomicFence(Tr.StmtTyped, self.ordering) }, {})) end,
        [Tr.StmtExpr] = function(self, ctx) local expr = pvm.one(type_expr(self.expr, ctx)); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtExpr(Tr.StmtTyped, expr.expr) }, expr.issues)) end,
        [Tr.StmtAssert] = function(self, ctx) local cond = type_expr_expect(self.cond, ctx, bool_ty()); local issues = {}; append_all(issues, cond.issues); check_expected("assert", bool_ty(), cond.ty, issues); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtAssert(Tr.StmtTyped, cond.expr) }, issues)) end,
        [Tr.StmtReturnVoid] = function(self, ctx) local issues = {}; check_expected("return", void_ty(), ctx.return_ty, issues); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtReturnVoid(Tr.StmtTyped) }, issues)) end,
        [Tr.StmtReturnValue] = function(self, ctx) local value = type_expr_expect(self.value, ctx, ctx.return_ty); local issues = {}; append_all(issues, value.issues); check_expected("return", ctx.return_ty, value.ty, issues); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtReturnValue(Tr.StmtTyped, value.expr) }, issues)) end,
        [Tr.StmtYieldVoid] = function(self, ctx) local issues = {}; if ctx.yield ~= Tr.TypeYieldVoid then issues[#issues + 1] = Tr.TypeIssueUnexpectedYield("yield") end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtYieldVoid(Tr.StmtTyped) }, issues)) end,
        [Tr.StmtYieldValue] = function(self, ctx) local expected = pvm.classof(ctx.yield) == Tr.TypeYieldValue and ctx.yield.ty or nil; local value = type_expr_expect(self.value, ctx, expected); local issues = {}; append_all(issues, value.issues); if pvm.classof(ctx.yield) == Tr.TypeYieldValue then check_expected("yield", ctx.yield.ty, value.ty, issues) else issues[#issues + 1] = Tr.TypeIssueUnexpectedYield("yield value") end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtYieldValue(Tr.StmtTyped, value.expr) }, issues)) end,
        [Tr.StmtIf] = function(self, ctx)
            local cond = type_expr_expect(self.cond, ctx, bool_ty()); local then_r = type_stmt_body(self.then_body, ctx); local else_r = type_stmt_body(self.else_body, ctx); local issues = {}
            append_all(issues, cond.issues); append_all(issues, then_r.issues); append_all(issues, else_r.issues); check_expected("if cond", bool_ty(), cond.ty, issues)
            return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtIf(Tr.StmtTyped, cond.expr, then_r.stmts, else_r.stmts) }, issues))
        end,
        [Tr.StmtJump] = function(self, ctx) local args = {}; local issues = {}; for i = 1, #self.args do local value = pvm.one(type_expr(self.args[i].value, ctx)); args[#args + 1] = Tr.JumpArg(self.args[i].name, value.expr); append_all(issues, value.issues) end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtJump(Tr.StmtTyped, self.target, args) }, issues)) end,
        [Tr.StmtJumpCont] = function(self, ctx) local args = {}; local issues = {}; for i = 1, #self.args do local value = pvm.one(type_expr(self.args[i].value, ctx)); args[#args + 1] = Tr.JumpArg(self.args[i].name, value.expr); append_all(issues, value.issues) end; return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtJumpCont(Tr.StmtTyped, self.slot, args) }, issues)) end,
        [Tr.StmtSwitch] = function(self, ctx)
            local value = pvm.one(type_expr(self.value, ctx))
            local issues = {}; append_all(issues, value.issues)
            local arms = {}
            for i = 1, #self.arms do
                local key = type_switch_key(self.arms[i].key, ctx, value.ty, issues)
                local body = type_stmt_body(self.arms[i].body, ctx)
                append_all(issues, body.issues)
                arms[#arms + 1] = Tr.SwitchStmtArm(key, body.stmts)
            end
            local default = type_stmt_body(self.default_body, ctx)
            append_all(issues, default.issues)
            return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtSwitch(Tr.StmtTyped, value.expr, arms, {}, default.stmts) }, issues))
        end,
        [Tr.StmtControl] = function(self, ctx) local region = pvm.one(type_control_stmt_region(self.region, ctx)); return pvm.once(Tr.TypeStmtResult(ctx, { Tr.StmtControl(Tr.StmtTyped, region.region) }, region.issues)) end,
        [Tr.StmtUseRegionSlot] = function(self, ctx) return pvm.once(Tr.TypeStmtResult(ctx, { pvm.with(self, { h = Tr.StmtTyped }) }, {})) end,
        [Tr.StmtUseRegionFrag] = function(self, ctx) return pvm.once(Tr.TypeStmtResult(ctx, { pvm.with(self, { h = Tr.StmtTyped }) }, {})) end,
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

    local function type_entry_block(region_id, block, ctx, yield_mode)
        local entry_params = {}
        local issues = {}
        for i = 1, #block.params do local init = type_expr_expect(block.params[i].init, ctx, block.params[i].ty); entry_params[#entry_params + 1] = pvm.with(block.params[i], { init = init.expr }); append_all(issues, init.issues); check_expected("block param " .. block.params[i].name, block.params[i].ty, init.ty, issues) end
        local block_env = env_with_block_params(ctx.env, region_id, block.label, block.params, true)
        local body = type_stmt_body(block.body, ctx_with_yield(ctx_with_env(ctx, block_env), yield_mode))
        append_all(issues, body.issues)
        return Tr.EntryControlBlock(block.label, entry_params, body.stmts), issues
    end

    local function type_control_block(region_id, block, ctx, yield_mode)
        local block_env = env_with_block_params(ctx.env, region_id, block.label, block.params, false)
        local body = type_stmt_body(block.body, ctx_with_yield(ctx_with_env(ctx, block_env), yield_mode))
        return Tr.ControlBlock(block.label, block.params, body.stmts), body.issues
    end

    local function validate_control(region)
        local issues = {}
        local decision = control_api.decide(region)
        if pvm.classof(decision) == Tr.ControlDecisionIrreducible then issues[#issues + 1] = Tr.TypeIssueInvalidControl(region.region_id, decision.reject) end
        return issues
    end

    type_control_stmt_region = pvm.phase("moonlift_tree_typecheck_control_stmt_region", {
        [Tr.ControlStmtRegion] = function(self, ctx)
            local entry, issues = type_entry_block(self.region_id, self.entry, ctx, Tr.TypeYieldVoid)
            local blocks = {}
            for i = 1, #self.blocks do local b, bi = type_control_block(self.region_id, self.blocks[i], ctx, Tr.TypeYieldVoid); blocks[#blocks + 1] = b; append_all(issues, bi) end
            local region = Tr.ControlStmtRegion(self.region_id, entry, blocks); append_all(issues, validate_control(region))
            return pvm.once(Tr.TypeControlStmtRegionResult(region, issues))
        end,
    }, { args_cache = "last" })

    type_control_expr_region = pvm.phase("moonlift_tree_typecheck_control_expr_region", {
        [Tr.ControlExprRegion] = function(self, ctx)
            local entry, issues = type_entry_block(self.region_id, self.entry, ctx, Tr.TypeYieldValue(self.result_ty))
            local blocks = {}
            for i = 1, #self.blocks do local b, bi = type_control_block(self.region_id, self.blocks[i], ctx, Tr.TypeYieldValue(self.result_ty)); blocks[#blocks + 1] = b; append_all(issues, bi) end
            local region = Tr.ControlExprRegion(self.region_id, self.result_ty, entry, blocks); append_all(issues, validate_control(region))
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
            if pvm.classof(base.ty) ~= Ty.TPtr and pvm.classof(base.ty) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("bounds base", Ty.TScalar(C.ScalarRawPtr), base.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("bounds len", Ty.TScalar(C.ScalarIndex), len.ty) end
            return Tr.ContractBounds(base.expr, len.expr), issues
        elseif cls == Tr.ContractWindowBounds then
            local base = pvm.one(type_expr(contract.base, ctx)); local base_len = type_expr_expect(contract.base_len, ctx, Ty.TScalar(C.ScalarIndex)); local start = type_expr_expect(contract.start, ctx, Ty.TScalar(C.ScalarIndex)); local len = type_expr_expect(contract.len, ctx, Ty.TScalar(C.ScalarIndex))
            append_all(issues, base.issues); append_all(issues, base_len.issues); append_all(issues, start.issues); append_all(issues, len.issues)
            if pvm.classof(base.ty) ~= Ty.TPtr and pvm.classof(base.ty) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("window_bounds base", Ty.TScalar(C.ScalarRawPtr), base.ty) end
            if not is_integer_scalar(base_len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("window_bounds base_len", Ty.TScalar(C.ScalarIndex), base_len.ty) end
            if not is_integer_scalar(start.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("window_bounds start", Ty.TScalar(C.ScalarIndex), start.ty) end
            if not is_integer_scalar(len.ty) then issues[#issues + 1] = Tr.TypeIssueExpected("window_bounds len", Ty.TScalar(C.ScalarIndex), len.ty) end
            return Tr.ContractWindowBounds(base.expr, base_len.expr, start.expr, len.expr), issues
        elseif cls == Tr.ContractDisjoint then
            local a = pvm.one(type_expr(contract.a, ctx)); local b = pvm.one(type_expr(contract.b, ctx))
            append_all(issues, a.issues); append_all(issues, b.issues)
            if pvm.classof(a.ty) ~= Ty.TPtr and pvm.classof(a.ty) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("disjoint lhs", Ty.TScalar(C.ScalarRawPtr), a.ty) end
            if pvm.classof(b.ty) ~= Ty.TPtr and pvm.classof(b.ty) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("disjoint rhs", Ty.TScalar(C.ScalarRawPtr), b.ty) end
            return Tr.ContractDisjoint(a.expr, b.expr), issues
        elseif cls == Tr.ContractSameLen then
            local a = pvm.one(type_expr(contract.a, ctx)); local b = pvm.one(type_expr(contract.b, ctx))
            append_all(issues, a.issues); append_all(issues, b.issues)
            if pvm.classof(a.ty) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("same_len lhs", Ty.TView(void_ty()), a.ty) end
            if pvm.classof(b.ty) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("same_len rhs", Ty.TView(void_ty()), b.ty) end
            return Tr.ContractSameLen(a.expr, b.expr), issues
        elseif cls == Tr.ContractNoAlias or cls == Tr.ContractReadonly or cls == Tr.ContractWriteonly then
            local base = pvm.one(type_expr(contract.base, ctx)); append_all(issues, base.issues)
            if pvm.classof(base.ty) ~= Ty.TPtr and pvm.classof(base.ty) ~= Ty.TView then issues[#issues + 1] = Tr.TypeIssueExpected("memory contract base", Ty.TScalar(C.ScalarRawPtr), base.ty) end
            if cls == Tr.ContractNoAlias then return Tr.ContractNoAlias(base.expr), issues end
            if cls == Tr.ContractReadonly then return Tr.ContractReadonly(base.expr), issues end
            return Tr.ContractWriteonly(base.expr), issues
        end
        return contract, issues
    end

    local function type_contracts(contracts, ctx)
        local out, issues = {}, {}
        for i = 1, #contracts do local c, ci = type_contract(contracts[i], ctx); out[#out + 1] = c; append_all(issues, ci) end
        return out, issues
    end

    local function type_plain_func(self, module_env)
        local ctx = Tr.TypeCheckEnv(env_with_params(module_env, self.name, self.params), self.result, Tr.TypeYieldNone)
        local body = type_stmt_body(self.body, ctx)
        return Tr.TypeFuncResult(pvm.with(self, { body = body.stmts }), body.issues)
    end

    local function type_contract_func(self, module_env)
        local ctx = Tr.TypeCheckEnv(env_with_params(module_env, self.name, self.params), self.result, Tr.TypeYieldNone)
        local contracts, issues = type_contracts(self.contracts, ctx)
        local body = type_stmt_body(self.body, ctx)
        append_all(issues, body.issues)
        return Tr.TypeFuncResult(pvm.with(self, { contracts = contracts, body = body.stmts }), issues)
    end

    type_func = pvm.phase("moonlift_tree_typecheck_func", {
        [Tr.FuncLocal] = function(self, module_env) return pvm.once(type_plain_func(self, module_env)) end,
        [Tr.FuncExport] = function(self, module_env) return pvm.once(type_plain_func(self, module_env)) end,
        [Tr.FuncLocalContract] = function(self, module_env) return pvm.once(type_contract_func(self, module_env)) end,
        [Tr.FuncExportContract] = function(self, module_env) return pvm.once(type_contract_func(self, module_env)) end,
        [Tr.FuncOpen] = function(self, module_env) local ctx = Tr.TypeCheckEnv(module_env, self.result, Tr.TypeYieldNone); local body = type_stmt_body(self.body, ctx); return pvm.once(Tr.TypeFuncResult(pvm.with(self, { body = body.stmts }), body.issues)) end,
    }, { args_cache = "last" })

    type_item = pvm.phase("moonlift_tree_typecheck_item", {
        [Tr.ItemFunc] = function(self, module_env) local r = pvm.one(type_func(self.func, module_env)); return pvm.once(Tr.TypeItemResult({ Tr.ItemFunc(r.func) }, r.issues)) end,
        [Tr.ItemConst] = function(self, module_env) local ctx = Tr.TypeCheckEnv(module_env, self.c.ty, Tr.TypeYieldNone); local value = pvm.one(type_expr(self.c.value, ctx)); local issues = {}; append_all(issues, value.issues); check_expected("const", self.c.ty, value.ty, issues); return pvm.once(Tr.TypeItemResult({ Tr.ItemConst(pvm.with(self.c, { value = value.expr })) }, issues)) end,
        [Tr.ItemStatic] = function(self, module_env) local ctx = Tr.TypeCheckEnv(module_env, self.s.ty, Tr.TypeYieldNone); local value = pvm.one(type_expr(self.s.value, ctx)); local issues = {}; append_all(issues, value.issues); check_expected("static", self.s.ty, value.ty, issues); return pvm.once(Tr.TypeItemResult({ Tr.ItemStatic(pvm.with(self.s, { value = value.expr })) }, issues)) end,
        [Tr.ItemExtern] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
        [Tr.ItemImport] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
        [Tr.ItemType] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
        [Tr.ItemUseTypeDeclSlot] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
        [Tr.ItemUseItemsSlot] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
        [Tr.ItemUseModule] = function(self)
            local r = pvm.one(type_module(self.module))
            return pvm.once(Tr.TypeItemResult({ pvm.with(self, { module = r.module }) }, r.issues))
        end,
        [Tr.ItemUseModuleSlot] = function(self) return pvm.once(Tr.TypeItemResult({ self }, {})) end,
    }, { args_cache = "last" })

    type_module = pvm.phase("moonlift_tree_typecheck_module", {
        [Tr.Module] = function(module)
            local module_env = module_type_api.env(module)
            local items = {}
            local issues = {}
            for i = 1, #module.items do local r = pvm.one(type_item(module.items[i], module_env)); append_all(items, r.items); append_all(issues, r.issues) end
            return pvm.once(Tr.TypeModuleResult(Tr.Module(Tr.ModuleTyped(module_env.module_name), items), issues))
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
        check_module = function(module) return pvm.one(type_module(module)) end,
    }
end

return M
