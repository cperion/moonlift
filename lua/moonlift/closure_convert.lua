local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.MoonCore
    local Ty = T.MoonType
    local B = T.MoonBind
    local Sem = T.MoonSem
    local Tr = T.MoonTree

    local rewrite_expr
    local rewrite_place
    local rewrite_control_stmt_region
    local rewrite_control_expr_region
    local collect_captures_place
    local collect_captures_index_base
    local collect_captures_view
    local collect_captures_stmts
    local rewrite_stmt
    local rewrite_func
    local rewrite_item
    local rewrite_module

    local state = nil

    local function append_all(out, xs)
        for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end
    end

    local function clone(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = xs[i] end
        return out
    end

    local function fresh_helper_name()
        state.counter = state.counter + 1
        return "__moon_closure_" .. tostring(state.module_name or "mod") .. "_" .. tostring(state.owner or "anon") .. "_" .. tostring(state.counter)
    end

    local function rewrite_exprs(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = rewrite_expr(xs[i]) end
        return out
    end

    local function rewrite_stmts(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = rewrite_stmt(xs[i]) end
        return out
    end

    local function rewrite_jump_args(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = pvm.with(xs[i], { value = rewrite_expr(xs[i].value) }) end
        return out
    end

    local function rewrite_view(view)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr then return pvm.with(view, { base = rewrite_expr(view.base) }) end
        if cls == Tr.ViewContiguous then return pvm.with(view, { data = rewrite_expr(view.data), len = rewrite_expr(view.len) }) end
        if cls == Tr.ViewStrided then return pvm.with(view, { data = rewrite_expr(view.data), len = rewrite_expr(view.len), stride = rewrite_expr(view.stride) }) end
        if cls == Tr.ViewRestrided then return pvm.with(view, { base = rewrite_view(view.base), stride = rewrite_expr(view.stride) }) end
        if cls == Tr.ViewWindow then return pvm.with(view, { base = rewrite_view(view.base), start = rewrite_expr(view.start), len = rewrite_expr(view.len) }) end
        if cls == Tr.ViewRowBase then return pvm.with(view, { base = rewrite_view(view.base), row_offset = rewrite_expr(view.row_offset) }) end
        if cls == Tr.ViewInterleaved then return pvm.with(view, { data = rewrite_expr(view.data), len = rewrite_expr(view.len), stride = rewrite_expr(view.stride), lane = rewrite_expr(view.lane) }) end
        if cls == Tr.ViewInterleavedView then return pvm.with(view, { base = rewrite_view(view.base), stride = rewrite_expr(view.stride), lane = rewrite_expr(view.lane) }) end
        return view
    end

    local function rewrite_index_base(base)
        local cls = pvm.classof(base)
        if cls == Tr.IndexBaseExpr then return pvm.with(base, { base = rewrite_expr(base.base) }) end
        if cls == Tr.IndexBasePlace then return pvm.with(base, { base = rewrite_place(base.base) }) end
        if cls == Tr.IndexBaseView then return pvm.with(base, { view = rewrite_view(base.view) }) end
        return base
    end

    function rewrite_place(place)
        local cls = pvm.classof(place)
        if cls == Tr.PlaceDeref then return pvm.with(place, { base = rewrite_expr(place.base) }) end
        if cls == Tr.PlaceDot or cls == Tr.PlaceField then return pvm.with(place, { base = rewrite_place(place.base) }) end
        if cls == Tr.PlaceIndex then return pvm.with(place, { base = rewrite_index_base(place.base), index = rewrite_expr(place.index) }) end
        return place
    end

    local function scope_get(name)
        for i = #state.scopes, 1, -1 do
            local ty = state.scopes[i][name]
            if ty ~= nil then return ty end
        end
        return nil
    end

    local function push_scope(entries)
        state.scopes[#state.scopes + 1] = entries or {}
    end

    local function pop_scope()
        state.scopes[#state.scopes] = nil
    end

    local function params_scope(params)
        local out = {}
        for i = 1, #(params or {}) do out[params[i].name] = params[i].ty end
        return out
    end

    local function type_size_align(ty)
        local cls = pvm.classof(ty)
        if cls == Ty.TScalar then
            if ty.scalar == C.ScalarBool or ty.scalar == C.ScalarI8 or ty.scalar == C.ScalarU8 then return 1, 1 end
            if ty.scalar == C.ScalarI16 or ty.scalar == C.ScalarU16 then return 2, 2 end
            if ty.scalar == C.ScalarI32 or ty.scalar == C.ScalarU32 or ty.scalar == C.ScalarF32 then return 4, 4 end
            if ty.scalar == C.ScalarI64 or ty.scalar == C.ScalarU64 or ty.scalar == C.ScalarF64 or ty.scalar == C.ScalarIndex or ty.scalar == C.ScalarRawPtr then return 8, 8 end
            if ty.scalar == C.ScalarVoid then return 0, 1 end
        end
        if cls == Ty.TPtr or cls == Ty.TFunc or cls == Ty.TClosure then return 8, 8 end
        error("closure conversion cannot capture value with unsupported environment layout: " .. tostring(ty), 2)
    end

    local function capture_layout(captures)
        local offset, align = 0, 1
        for i = 1, #captures do
            local size, a = type_size_align(captures[i].ty)
            if a > align then align = a end
            local rem = offset % a
            if rem ~= 0 then offset = offset + (a - rem) end
            captures[i].offset = offset
            captures[i].size = size
            offset = offset + size
        end
        local rem = offset % align
        if rem ~= 0 then offset = offset + (align - rem) end
        return offset, align
    end

    local function int_lit(raw)
        return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(raw)))
    end

    local function name_ref(name)
        return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
    end

    local function captured_load(cap)
        local ctx = name_ref("__moon_ctx")
        local addr = ctx
        if cap.offset ~= 0 then addr = Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, ctx, int_lit(cap.offset)) end
        return Tr.ExprLoad(Tr.ExprSurface, cap.ty, Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, Ty.TPtr(cap.ty), addr))
    end

    local function collect_captures_expr(expr, locals, out, seen)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefName then
            local name = expr.ref.name
            if not locals[name] and not seen[name] then
                local ty = scope_get(name)
                if ty ~= nil then seen[name] = true; out[#out + 1] = { name = name, ty = ty } end
            end
        elseif cls == Tr.ExprUnary or cls == Tr.ExprDeref or cls == Tr.ExprLen then collect_captures_expr(expr.value, locals, out, seen)
        elseif cls == Tr.ExprBinary or cls == Tr.ExprCompare or cls == Tr.ExprLogic then collect_captures_expr(expr.lhs, locals, out, seen); collect_captures_expr(expr.rhs, locals, out, seen)
        elseif cls == Tr.ExprCast or cls == Tr.ExprMachineCast then collect_captures_expr(expr.value, locals, out, seen)
        elseif cls == Tr.ExprIntrinsic then for i = 1, #expr.args do collect_captures_expr(expr.args[i], locals, out, seen) end
        elseif cls == Tr.ExprAddrOf then collect_captures_place(expr.place, locals, out, seen)
        elseif cls == Tr.ExprCall then
            collect_captures_expr(expr.callee, locals, out, seen)
            for i = 1, #expr.args do collect_captures_expr(expr.args[i], locals, out, seen) end
        elseif cls == Tr.ExprField or cls == Tr.ExprDot then collect_captures_expr(expr.base, locals, out, seen)
        elseif cls == Tr.ExprIndex then collect_captures_index_base(expr.base, locals, out, seen); collect_captures_expr(expr.index, locals, out, seen)
        elseif cls == Tr.ExprAgg then for i = 1, #expr.fields do collect_captures_expr(expr.fields[i].value, locals, out, seen) end
        elseif cls == Tr.ExprArray then for i = 1, #expr.elems do collect_captures_expr(expr.elems[i], locals, out, seen) end
        elseif cls == Tr.ExprIf or cls == Tr.ExprSelect then collect_captures_expr(expr.cond, locals, out, seen); collect_captures_expr(expr.then_expr, locals, out, seen); collect_captures_expr(expr.else_expr, locals, out, seen)
        elseif cls == Tr.ExprBlock then local inner = {}; for k, v in pairs(locals) do inner[k] = v end; collect_captures_stmts(expr.stmts, inner, out, seen); collect_captures_expr(expr.result, inner, out, seen)
        elseif cls == Tr.ExprView then collect_captures_view(expr.view, locals, out, seen)
        elseif cls == Tr.ExprLoad or cls == Tr.ExprAtomicLoad then collect_captures_expr(expr.addr, locals, out, seen)
        elseif cls == Tr.ExprAtomicRmw then collect_captures_expr(expr.addr, locals, out, seen); collect_captures_expr(expr.value, locals, out, seen)
        elseif cls == Tr.ExprAtomicCas then collect_captures_expr(expr.addr, locals, out, seen); collect_captures_expr(expr.expected, locals, out, seen); collect_captures_expr(expr.replacement, locals, out, seen)
        end
    end

    collect_captures_place = function(place, locals, out, seen)
        local cls = pvm.classof(place)
        if cls == Tr.PlaceRef and pvm.classof(place.ref) == B.ValueRefName then collect_captures_expr(Tr.ExprRef(Tr.ExprSurface, place.ref), locals, out, seen)
        elseif cls == Tr.PlaceDeref then collect_captures_expr(place.base, locals, out, seen)
        elseif cls == Tr.PlaceDot or cls == Tr.PlaceField then collect_captures_place(place.base, locals, out, seen)
        elseif cls == Tr.PlaceIndex then collect_captures_index_base(place.base, locals, out, seen); collect_captures_expr(place.index, locals, out, seen) end
    end

    collect_captures_index_base = function(base, locals, out, seen)
        local cls = pvm.classof(base)
        if cls == Tr.IndexBaseExpr then collect_captures_expr(base.base, locals, out, seen)
        elseif cls == Tr.IndexBasePlace then collect_captures_place(base.base, locals, out, seen)
        elseif cls == Tr.IndexBaseView then collect_captures_view(base.view, locals, out, seen) end
    end

    collect_captures_view = function(view, locals, out, seen)
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr then collect_captures_expr(view.base, locals, out, seen)
        elseif cls == Tr.ViewContiguous then collect_captures_expr(view.data, locals, out, seen); collect_captures_expr(view.len, locals, out, seen)
        elseif cls == Tr.ViewStrided then collect_captures_expr(view.data, locals, out, seen); collect_captures_expr(view.len, locals, out, seen); collect_captures_expr(view.stride, locals, out, seen)
        elseif cls == Tr.ViewRestrided then collect_captures_view(view.base, locals, out, seen); collect_captures_expr(view.stride, locals, out, seen)
        elseif cls == Tr.ViewWindow then collect_captures_view(view.base, locals, out, seen); collect_captures_expr(view.start, locals, out, seen); collect_captures_expr(view.len, locals, out, seen)
        elseif cls == Tr.ViewRowBase then collect_captures_view(view.base, locals, out, seen); collect_captures_expr(view.row_offset, locals, out, seen)
        elseif cls == Tr.ViewInterleaved then collect_captures_expr(view.data, locals, out, seen); collect_captures_expr(view.len, locals, out, seen); collect_captures_expr(view.stride, locals, out, seen); collect_captures_expr(view.lane, locals, out, seen)
        elseif cls == Tr.ViewInterleavedView then collect_captures_view(view.base, locals, out, seen); collect_captures_expr(view.stride, locals, out, seen); collect_captures_expr(view.lane, locals, out, seen)
        end
    end

    collect_captures_stmts = function(stmts, locals, out, seen)
        for i = 1, #(stmts or {}) do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtLet or cls == Tr.StmtVar then collect_captures_expr(stmt.init, locals, out, seen); locals[stmt.binding.name] = stmt.binding.ty
            elseif cls == Tr.StmtSet then collect_captures_place(stmt.place, locals, out, seen); collect_captures_expr(stmt.value, locals, out, seen)
            elseif cls == Tr.StmtExpr then collect_captures_expr(stmt.expr, locals, out, seen)
            elseif cls == Tr.StmtReturnValue or cls == Tr.StmtYieldValue then collect_captures_expr(stmt.value, locals, out, seen)
            elseif cls == Tr.StmtIf then collect_captures_expr(stmt.cond, locals, out, seen); local a = {}; for k, v in pairs(locals) do a[k] = v end; collect_captures_stmts(stmt.then_body, a, out, seen); local b = {}; for k, v in pairs(locals) do b[k] = v end; collect_captures_stmts(stmt.else_body, b, out, seen)
            end
        end
    end

    local function closure_captures(expr)
        local locals = params_scope(expr.params)
        local out, seen = {}, {}
        collect_captures_stmts(expr.body, locals, out, seen)
        return out
    end

    local function helper_for_closure(expr, captures)
        local name = fresh_helper_name()
        captures = captures or closure_captures(expr)
        local helper_params = clone(expr.params)
        for i = 1, #captures do helper_params[#helper_params + 1] = Ty.Param(captures[i].name, captures[i].ty) end
        local old_owner = state.owner
        state.owner = name
        push_scope(params_scope(helper_params))
        local body = rewrite_stmts(expr.body)
        pop_scope()
        state.owner = old_owner
        local helper = Tr.FuncLocal(name, helper_params, expr.result, body)
        state.helpers[#state.helpers + 1] = Tr.ItemFunc(helper)
        return name, captures
    end

    local function helper_for_escaping_closure(expr, captures)
        local name = fresh_helper_name()
        captures = captures or closure_captures(expr)
        capture_layout(captures)
        local helper_params = { Ty.Param("__moon_ctx", Ty.TPtr(Ty.TScalar(C.ScalarU8))) }
        append_all(helper_params, expr.params)
        local capture_env = {}
        for i = 1, #captures do capture_env[captures[i].name] = captures[i] end
        local old_owner, old_capture_env, old_scopes = state.owner, state.capture_env, state.scopes
        state.owner = name
        state.capture_env = capture_env
        state.scopes = {}
        push_scope(params_scope(helper_params))
        local body = rewrite_stmts(expr.body)
        pop_scope()
        state.scopes = old_scopes
        state.capture_env = old_capture_env
        state.owner = old_owner
        local helper = Tr.FuncLocal(name, helper_params, expr.result, body)
        state.helpers[#state.helpers + 1] = Tr.ItemFunc(helper)
        return name, captures
    end

    local function descriptor_for_closure(expr)
        local captures = closure_captures(expr)
        local helper_name = helper_for_escaping_closure(expr, captures)
        local fields = { Tr.FieldInit("__moon_fn", name_ref(helper_name), 0) }
        for i = 1, #captures do
            fields[#fields + 1] = Tr.FieldInit("__moon_cap_" .. captures[i].name, name_ref(captures[i].name), captures[i].offset)
        end
        local params = {}
        for i = 1, #expr.params do params[i] = expr.params[i].ty end
        return Tr.ExprAgg(Tr.ExprSurface, Ty.TClosure(params, expr.result), fields)
    end

    function rewrite_expr(expr)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefName and state.capture_env ~= nil then
            local cap = state.capture_env[expr.ref.name]
            if cap ~= nil and scope_get(expr.ref.name) == nil then return captured_load(cap) end
        end
        if cls == Tr.ExprCall then
            local callee = rewrite_expr(expr.callee)
            local args = rewrite_exprs(expr.args)
            return pvm.with(expr, { callee = callee, args = args })
        end
        if cls == Tr.ExprUnary or cls == Tr.ExprDeref or cls == Tr.ExprLen then return pvm.with(expr, { value = rewrite_expr(expr.value) }) end
        if cls == Tr.ExprBinary or cls == Tr.ExprCompare or cls == Tr.ExprLogic then return pvm.with(expr, { lhs = rewrite_expr(expr.lhs), rhs = rewrite_expr(expr.rhs) }) end
        if cls == Tr.ExprCast or cls == Tr.ExprMachineCast then return pvm.with(expr, { value = rewrite_expr(expr.value) }) end
        if cls == Tr.ExprIntrinsic then return pvm.with(expr, { args = rewrite_exprs(expr.args) }) end
        if cls == Tr.ExprAddrOf then return pvm.with(expr, { place = rewrite_place(expr.place) }) end
        if cls == Tr.ExprField or cls == Tr.ExprDot then return pvm.with(expr, { base = rewrite_expr(expr.base) }) end
        if cls == Tr.ExprIndex then return pvm.with(expr, { base = rewrite_index_base(expr.base), index = rewrite_expr(expr.index) }) end
        if cls == Tr.ExprAgg then local fields = {}; for i = 1, #expr.fields do fields[i] = pvm.with(expr.fields[i], { value = rewrite_expr(expr.fields[i].value) }) end; return pvm.with(expr, { fields = fields }) end
        if cls == Tr.ExprArray then return pvm.with(expr, { elems = rewrite_exprs(expr.elems) }) end
        if cls == Tr.ExprIf or cls == Tr.ExprSelect then return pvm.with(expr, { cond = rewrite_expr(expr.cond), then_expr = rewrite_expr(expr.then_expr), else_expr = rewrite_expr(expr.else_expr) }) end
        if cls == Tr.ExprSwitch then local arms = {}; for i = 1, #expr.arms do arms[i] = pvm.with(expr.arms[i], { body = rewrite_stmts(expr.arms[i].body), result = rewrite_expr(expr.arms[i].result) }) end; return pvm.with(expr, { value = rewrite_expr(expr.value), arms = arms, default_body = rewrite_stmts(expr.default_body or {}), default_expr = rewrite_expr(expr.default_expr) }) end
        if cls == Tr.ExprControl then return pvm.with(expr, { region = rewrite_control_expr_region(expr.region) }) end
        if cls == Tr.ExprBlock then return pvm.with(expr, { stmts = rewrite_stmts(expr.stmts), result = rewrite_expr(expr.result) }) end
        if cls == Tr.ExprClosure then return descriptor_for_closure(expr) end
        if cls == Tr.ExprView then return pvm.with(expr, { view = rewrite_view(expr.view) }) end
        if cls == Tr.ExprLoad or cls == Tr.ExprAtomicLoad then return pvm.with(expr, { addr = rewrite_expr(expr.addr) }) end
        if cls == Tr.ExprAtomicRmw then return pvm.with(expr, { addr = rewrite_expr(expr.addr), value = rewrite_expr(expr.value) }) end
        if cls == Tr.ExprAtomicCas then return pvm.with(expr, { addr = rewrite_expr(expr.addr), expected = rewrite_expr(expr.expected), replacement = rewrite_expr(expr.replacement) }) end
        if cls == Tr.ExprUseExprFrag then return pvm.with(expr, { args = rewrite_exprs(expr.args) }) end
        return expr
    end

    function rewrite_control_stmt_region(region)
        local blocks = {}
        for i = 1, #region.blocks do blocks[i] = pvm.with(region.blocks[i], { body = rewrite_stmts(region.blocks[i].body) }) end
        local entry_params = {}
        for i = 1, #region.entry.params do entry_params[i] = pvm.with(region.entry.params[i], { init = rewrite_expr(region.entry.params[i].init) }) end
        local entry = pvm.with(region.entry, { params = entry_params, body = rewrite_stmts(region.entry.body) })
        return pvm.with(region, { entry = entry, blocks = blocks })
    end

    function rewrite_control_expr_region(region)
        local blocks = {}
        for i = 1, #region.blocks do blocks[i] = pvm.with(region.blocks[i], { body = rewrite_stmts(region.blocks[i].body) }) end
        local entry_params = {}
        for i = 1, #region.entry.params do entry_params[i] = pvm.with(region.entry.params[i], { init = rewrite_expr(region.entry.params[i].init) }) end
        local entry = pvm.with(region.entry, { params = entry_params, body = rewrite_stmts(region.entry.body) })
        return pvm.with(region, { entry = entry, blocks = blocks })
    end

    function rewrite_stmt(stmt)
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtLet or cls == Tr.StmtVar then
            local out = pvm.with(stmt, { init = rewrite_expr(stmt.init) })
            if #state.scopes > 0 then state.scopes[#state.scopes][stmt.binding.name] = stmt.binding.ty end
            return out
        end
        if cls == Tr.StmtSet then return pvm.with(stmt, { place = rewrite_place(stmt.place), value = rewrite_expr(stmt.value) }) end
        if cls == Tr.StmtAtomicStore then return pvm.with(stmt, { addr = rewrite_expr(stmt.addr), value = rewrite_expr(stmt.value) }) end
        if cls == Tr.StmtExpr then return pvm.with(stmt, { expr = rewrite_expr(stmt.expr) }) end
        if cls == Tr.StmtAssert then return pvm.with(stmt, { cond = rewrite_expr(stmt.cond) }) end
        if cls == Tr.StmtIf then return pvm.with(stmt, { cond = rewrite_expr(stmt.cond), then_body = rewrite_stmts(stmt.then_body), else_body = rewrite_stmts(stmt.else_body) }) end
        if cls == Tr.StmtSwitch then local arms = {}; for i = 1, #stmt.arms do arms[i] = pvm.with(stmt.arms[i], { body = rewrite_stmts(stmt.arms[i].body) }) end; local var_arms = {}; for i = 1, #(stmt.variant_arms or {}) do var_arms[i] = pvm.with(stmt.variant_arms[i], { body = rewrite_stmts(stmt.variant_arms[i].body) }) end; return pvm.with(stmt, { value = rewrite_expr(stmt.value), arms = arms, variant_arms = var_arms, default_body = rewrite_stmts(stmt.default_body or {}) }) end
        if cls == Tr.StmtJump or cls == Tr.StmtJumpCont then return pvm.with(stmt, { args = rewrite_jump_args(stmt.args) }) end
        if cls == Tr.StmtYieldValue then return pvm.with(stmt, { value = rewrite_expr(stmt.value) }) end
        if cls == Tr.StmtReturnValue then return pvm.with(stmt, { value = rewrite_expr(stmt.value) }) end
        if cls == Tr.StmtControl then return pvm.with(stmt, { region = rewrite_control_stmt_region(stmt.region) }) end
        if cls == Tr.StmtUseRegionFrag then return pvm.with(stmt, { args = rewrite_exprs(stmt.args) }) end
        return stmt
    end

    function rewrite_func(func)
        local old_owner = state.owner
        local cls = pvm.classof(func)
        if cls == Tr.FuncLocal or cls == Tr.FuncExport or cls == Tr.FuncLocalContract or cls == Tr.FuncExportContract then state.owner = func.name end
        if cls == Tr.FuncOpen then state.owner = func.sym.name end
        push_scope(params_scope(func.params or {}))
        local out = pvm.with(func, { body = rewrite_stmts(func.body) })
        pop_scope()
        state.owner = old_owner
        return out
    end

    function rewrite_item(item)
        local cls = pvm.classof(item)
        if cls == Tr.ItemFunc then return pvm.with(item, { func = rewrite_func(item.func) }) end
        if cls == Tr.ItemConst then return pvm.with(item, { c = pvm.with(item.c, { value = rewrite_expr(item.c.value) }) }) end
        if cls == Tr.ItemStatic then return pvm.with(item, { s = pvm.with(item.s, { value = rewrite_expr(item.s.value) }) }) end
        if cls == Tr.ItemUseModule then return pvm.with(item, { module = rewrite_module(item.module) }) end
        return item
    end

    local function module_name(module)
        local h = module.h
        local cls = pvm.classof(h)
        if cls == Tr.ModuleTyped or cls == Tr.ModuleSem or cls == Tr.ModuleCode then return h.module_name end
        if cls == Tr.ModuleOpen and h.name ~= T.MoonOpen.ModuleNameOpen then return h.name.module_name end
        return ""
    end

    function rewrite_module(module)
        local previous = state
        state = { module_name = module_name(module), owner = "module", counter = 0, helpers = {}, scopes = {} }
        local items = {}
        for i = 1, #module.items do
            local before = #state.helpers
            local rewritten = rewrite_item(module.items[i])
            for j = before + 1, #state.helpers do items[#items + 1] = state.helpers[j] end
            items[#items + 1] = rewritten
        end
        local out = pvm.with(module, { items = items })
        state = previous
        return out
    end

    return {
        module = rewrite_module,
        func = function(func) state = { module_name = "", owner = "func", counter = 0, helpers = {}, scopes = {} }; local out = rewrite_func(func); local helpers = state.helpers; state = nil; return out, helpers end,
    }
end

return M
