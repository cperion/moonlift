package.path = "./?.lua;./?/init.lua;" .. package.path

-- desugar_closures.lua
--
-- Surface -> Surface pass for closure syntax.  The pass is deliberately
-- source-level: it rewrites closure-specific Surface values into ordinary
-- Surface structs, function fields, context pointers, aggregates, field
-- projections, and calls before the normal Surface -> Elab path.
--
-- Representation:
--
--   closure(T1, ..., Tn) -> R
--     => generated named struct _closure_sig_<signature> {
--          fn:  func(ptr(void), T1, ..., Tn) -> R,
--          ctx: ptr(void),
--        }
--
--   fn(x: T) -> R ... end
--     => generated ctx struct + generated helper function
--        helper(ctx: ptr(void), x: T) -> R
--        closure value = _closure_sig { fn = helper, ctx = bitcast(ptr(void), &ctx_val) }
--
--   f(a, b) where f is closure-typed
--     => f.fn(f.ctx, a, b)

local M = {}

local function path1(Surf, name)
    return Surf.SurfPath({ Surf.SurfName(name) })
end

local function named(Surf, name)
    return Surf.SurfTNamed(path1(Surf, name))
end

local function ptr_void(Surf)
    return Surf.SurfTPtr(Surf.SurfTVoid)
end

local function sanitize(s)
    s = tostring(s):gsub("[^%w_]", "_")
    s = s:gsub("_+", "_")
    if s == "" then return "anon" end
    return s
end

local function path_text(path)
    local out = {}
    for i = 1, #path.parts do out[i] = path.parts[i].text end
    return table.concat(out, ".")
end

function M.desugar(module, Surf)
    if module == nil or module.items == nil then return module end

    local closure_count = 0
    local sig_items = {}
    local sig_seen = {}
    local generated_items = {}

    local transform_type
    local type_key
    local rewrite_expr
    local rewrite_stmt
    local process_body

    type_key = function(ty)
        local k = ty.kind
        if k == "SurfTVoid" then return "void" end
        if k == "SurfTBool" then return "bool" end
        if k == "SurfTI8" then return "i8" end
        if k == "SurfTI16" then return "i16" end
        if k == "SurfTI32" then return "i32" end
        if k == "SurfTI64" then return "i64" end
        if k == "SurfTU8" then return "u8" end
        if k == "SurfTU16" then return "u16" end
        if k == "SurfTU32" then return "u32" end
        if k == "SurfTU64" then return "u64" end
        if k == "SurfTF32" then return "f32" end
        if k == "SurfTF64" then return "f64" end
        if k == "SurfTIndex" then return "index" end
        if k == "SurfTPtr" then return "ptr_" .. type_key(ty.elem) end
        if k == "SurfTSlice" then return "slice_" .. type_key(ty.elem) end
        if k == "SurfTView" then return "view_" .. type_key(ty.elem) end
        if k == "SurfTArray" then
            local count = ty.count and (ty.count.raw or ty.count.kind or "expr") or "expr"
            return "array_" .. sanitize(count) .. "_" .. type_key(ty.elem)
        end
        if k == "SurfTFunc" then
            local parts = { "func" }
            for i = 1, #ty.params do parts[#parts + 1] = type_key(ty.params[i]) end
            parts[#parts + 1] = "to"
            parts[#parts + 1] = type_key(ty.result)
            return table.concat(parts, "_")
        end
        if k == "SurfTClosure" then
            local parts = { "closure" }
            for i = 1, #ty.params do parts[#parts + 1] = type_key(ty.params[i]) end
            parts[#parts + 1] = "to"
            parts[#parts + 1] = type_key(ty.result)
            return table.concat(parts, "_")
        end
        if k == "SurfTNamed" then return "named_" .. sanitize(path_text(ty.path)) end
        error("desugar_closures: unknown surface type " .. tostring(k))
    end

    local function transform_type_list(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = transform_type(xs[i]) end
        return out
    end

    local function ensure_closure_signature(param_tys, result_ty)
        local transformed_params = transform_type_list(param_tys)
        local transformed_result = transform_type(result_ty)
        local parts = { "closure_sig" }
        for i = 1, #transformed_params do parts[#parts + 1] = type_key(transformed_params[i]) end
        parts[#parts + 1] = "to"
        parts[#parts + 1] = type_key(transformed_result)
        local key = table.concat(parts, "_")
        local name = "_" .. sanitize(key)
        if not sig_seen[name] then
            sig_seen[name] = true
            local fn_params = { ptr_void(Surf) }
            for i = 1, #transformed_params do fn_params[#fn_params + 1] = transformed_params[i] end
            sig_items[#sig_items + 1] = Surf.SurfItemType(Surf.SurfStruct(name, {
                Surf.SurfFieldDecl("fn", Surf.SurfTFunc(fn_params, transformed_result)),
                Surf.SurfFieldDecl("ctx", ptr_void(Surf)),
            }))
        end
        return name, transformed_params, transformed_result
    end

    transform_type = function(ty)
        local k = ty.kind
        if k == "SurfTPtr" then return Surf.SurfTPtr(transform_type(ty.elem)) end
        if k == "SurfTSlice" then return Surf.SurfTSlice(transform_type(ty.elem)) end
        if k == "SurfTView" then return Surf.SurfTView(transform_type(ty.elem)) end
        if k == "SurfTArray" then return Surf.SurfTArray(ty.count, transform_type(ty.elem)) end
        if k == "SurfTFunc" then return Surf.SurfTFunc(transform_type_list(ty.params), transform_type(ty.result)) end
        if k == "SurfTClosure" then
            local name = ensure_closure_signature(ty.params, ty.result)
            return named(Surf, name)
        end
        return ty
    end

    local function transform_param(p)
        if p.ty ~= nil and p.ty.kind == "SurfTClosure" then
            local name = ensure_closure_signature(p.ty.params, p.ty.result)
            return Surf.SurfParam(p.name, Surf.SurfTPtr(named(Surf, name)))
        end
        return Surf.SurfParam(p.name, transform_type(p.ty))
    end

    local function is_closure_type(ty)
        return ty ~= nil and ty.kind == "SurfTClosure"
    end

    local function copy_scope(scope)
        local out = {}
        for k, v in pairs(scope or {}) do out[k] = v end
        return out
    end

    local function module_scope(items)
        local out = {}
        for _, item in ipairs(items) do
            if item.func then out[item.func.name] = true end
            if item.c then out[item.c.name] = true end
            if item.s then out[item.s.name] = true end
        end
        return out
    end

    local globals = module_scope(module.items)

    local function collect_free_vars(stmts, local_names, out, seen)
        out = out or {}
        seen = seen or {}
        local locals = copy_scope(local_names)
        local walk_expr, walk_place, walk_stmt
        local function mark(name)
            if locals[name] or globals[name] or seen[name] then return end
            seen[name] = true
            out[#out + 1] = name
        end
        walk_place = function(p)
            if p == nil then return end
            if p.kind == "SurfPlaceName" then mark(p.name); return end
            if p.base then walk_place(p.base); walk_expr(p.base) end
            if p.index then walk_expr(p.index) end
        end
        walk_expr = function(e)
            if e == nil then return end
            local k = e.kind
            if k == "SurfNameRef" then mark(e.name); return end
            if k == "SurfPathRef" then return end
            if k == "SurfClosureExpr" then
                local nested = copy_scope(locals)
                for _, p in ipairs(e.params) do nested[p.name] = true end
                collect_free_vars(e.body, nested, out, seen)
                return
            end
            if e.place then walk_place(e.place) end
            if e.value then walk_expr(e.value) end
            if e.lhs then walk_expr(e.lhs) end
            if e.rhs then walk_expr(e.rhs) end
            if e.base then walk_expr(e.base) end
            if e.index then walk_expr(e.index) end
            if e.callee then walk_expr(e.callee) end
            if e.cond then walk_expr(e.cond) end
            if e.then_expr then walk_expr(e.then_expr) end
            if e.else_expr then walk_expr(e.else_expr) end
            if e.default_expr then walk_expr(e.default_expr) end
            if e.result then walk_expr(e.result) end
            if e.args then for _, a in ipairs(e.args) do walk_expr(a) end end
            if e.elems then for _, x in ipairs(e.elems) do walk_expr(x) end end
            if e.fields then for _, f in ipairs(e.fields) do walk_expr(f.value) end end
            if e.arms then
                for _, arm in ipairs(e.arms) do
                    walk_expr(arm.key)
                    for _, s in ipairs(arm.body or {}) do walk_stmt(s) end
                    walk_expr(arm.result)
                end
            end
            if e.stmts then for _, s in ipairs(e.stmts) do walk_stmt(s) end end
            if e.loop then
                local l = e.loop
                walk_expr(l.cond); walk_expr(l.result)
                if l.domain then
                    walk_expr(l.domain.start); walk_expr(l.domain.stop); walk_expr(l.domain.value)
                    for _, v in ipairs(l.domain.values or {}) do walk_expr(v) end
                end
                for _, c in ipairs(l.carries or {}) do walk_expr(c.init); locals[c.name] = true end
                for _, s in ipairs(l.body or {}) do walk_stmt(s) end
                for _, n in ipairs(l.next or {}) do walk_expr(n.value) end
            end
        end
        walk_stmt = function(s)
            if s == nil then return end
            local k = s.kind
            if k == "SurfLet" or k == "SurfVar" then
                walk_expr(s.init)
                locals[s.name] = true
            elseif k == "SurfSet" then
                walk_place(s.place); walk_expr(s.value)
            elseif k == "SurfExprStmt" then walk_expr(s.expr)
            elseif k == "SurfAssert" then walk_expr(s.cond)
            elseif k == "SurfReturnValue" then walk_expr(s.value)
            elseif k == "SurfBreakValue" then walk_expr(s.value)
            elseif k == "SurfIf" then
                walk_expr(s.cond)
                for _, x in ipairs(s.then_body or {}) do walk_stmt(x) end
                for _, x in ipairs(s.else_body or {}) do walk_stmt(x) end
            elseif k == "SurfSwitch" then
                walk_expr(s.value)
                for _, arm in ipairs(s.arms or {}) do walk_expr(arm.key); for _, x in ipairs(arm.body or {}) do walk_stmt(x) end end
                for _, x in ipairs(s.default_body or {}) do walk_stmt(x) end
            elseif k == "SurfStmtLoop" then
                local l = s.loop
                walk_expr(l.cond)
                if l.domain then
                    walk_expr(l.domain.start); walk_expr(l.domain.stop); walk_expr(l.domain.value)
                    for _, v in ipairs(l.domain.values or {}) do walk_expr(v) end
                end
                for _, c in ipairs(l.carries or {}) do walk_expr(c.init); locals[c.name] = true end
                for _, x in ipairs(l.body or {}) do walk_stmt(x) end
                for _, n in ipairs(l.next or {}) do walk_expr(n.value) end
            end
        end
        for _, s in ipairs(stmts or {}) do walk_stmt(s) end
        return out
    end

    local function rewrite_place(place, scope, pre)
        if place == nil then return nil end
        local k = place.kind
        if k == "SurfPlaceName" or k == "SurfPlacePath" then return place end
        if k == "SurfPlaceDeref" then return Surf.SurfPlaceDeref(rewrite_expr(place.base, scope, pre)) end
        if k == "SurfPlaceDot" then return Surf.SurfPlaceDot(rewrite_place(place.base, scope, pre), place.name) end
        if k == "SurfPlaceField" then return Surf.SurfPlaceField(rewrite_place(place.base, scope, pre), place.name) end
        if k == "SurfPlaceIndex" then return Surf.SurfPlaceIndex(rewrite_expr(place.base, scope, pre), rewrite_expr(place.index, scope, pre)) end
        return place
    end

    local function rewrite_domain(domain, scope, pre)
        if domain == nil then return nil end
        local k = domain.kind
        if k == "SurfDomainRange" then return Surf.SurfDomainRange(rewrite_expr(domain.stop, scope, pre)) end
        if k == "SurfDomainRange2" then return Surf.SurfDomainRange2(rewrite_expr(domain.start, scope, pre), rewrite_expr(domain.stop, scope, pre)) end
        if k == "SurfDomainValue" then return Surf.SurfDomainValue(rewrite_expr(domain.value, scope, pre)) end
        if k == "SurfDomainZipEq" then
            local values = {}
            for i = 1, #domain.values do values[i] = rewrite_expr(domain.values[i], scope, pre) end
            return Surf.SurfDomainZipEq(values)
        end
        return domain
    end

    local function closure_call_parts(callee, rewritten_callee, scope)
        if callee.kind == "SurfNameRef" and scope[callee.name] and scope[callee.name].is_closure then
            local base = rewritten_callee
            if scope[callee.name].by_ref then
                base = Surf.SurfExprDeref(rewritten_callee)
            end
            return Surf.SurfField(base, "fn"), Surf.SurfField(base, "ctx")
        end
        return nil, nil
    end

    rewrite_expr = function(expr, scope, pre)
        if expr == nil then return nil end
        local k = expr.kind
        if k == "SurfClosureExpr" then
            closure_count = closure_count + 1
            local cid = closure_count
            local params = {}
            for i = 1, #expr.params do params[i] = transform_param(expr.params[i]) end
            local result_ty = transform_type(expr.result)
            local param_tys = {}
            for i = 1, #expr.params do param_tys[i] = expr.params[i].ty end
            local sig_name = ensure_closure_signature(param_tys, expr.result)
            local sig_ty = named(Surf, sig_name)

            local local_names = {}
            for i = 1, #expr.params do local_names[expr.params[i].name] = true end
            local free = collect_free_vars(expr.body, local_names)
            local captures = {}
            for _, name in ipairs(free) do
                if scope[name] ~= nil then captures[#captures + 1] = name end
            end

            local ctx_name = "_closure_ctx_" .. cid
            local ctx_ty = named(Surf, ctx_name)
            local ctx_fields = {}
            for _, name in ipairs(captures) do
                ctx_fields[#ctx_fields + 1] = Surf.SurfFieldDecl(name, transform_type(scope[name].ty))
            end
            generated_items[#generated_items + 1] = Surf.SurfItemType(Surf.SurfStruct(ctx_name, ctx_fields))

            local helper_name = "_closure_fn_" .. cid
            local helper_params = { Surf.SurfParam("ctx", ptr_void(Surf)) }
            for i = 1, #params do helper_params[#helper_params + 1] = params[i] end

            local helper_scope = {}
            helper_scope.ctx = { ty = ptr_void(Surf), is_closure = false }
            for i = 1, #params do helper_scope[params[i].name] = { ty = params[i].ty, is_closure = false } end
            local capture_set = {}
            for _, name in ipairs(captures) do capture_set[name] = true end

            local function ctx_expr()
                return Surf.SurfExprDeref(Surf.SurfExprBitcastTo(Surf.SurfTPtr(ctx_ty), Surf.SurfNameRef("ctx")))
            end
            local saved_rewrite_expr = rewrite_expr
            local function rewrite_captured_expr(e, body_scope, body_pre)
                if e ~= nil and e.kind == "SurfNameRef" and capture_set[e.name] then
                    return Surf.SurfField(ctx_expr(), e.name)
                end
                return saved_rewrite_expr(e, body_scope, body_pre)
            end
            rewrite_expr = rewrite_captured_expr
            local helper_body = process_body(expr.body, helper_scope)
            rewrite_expr = saved_rewrite_expr

            generated_items[#generated_items + 1] = Surf.SurfItemFunc(Surf.SurfFuncLocal(helper_name, helper_params, result_ty, helper_body))

            local ctx_inits = {}
            for _, name in ipairs(captures) do ctx_inits[#ctx_inits + 1] = Surf.SurfFieldInit(name, Surf.SurfNameRef(name)) end
            local ctx_var = "_closure_ctx_val_" .. cid
            pre[#pre + 1] = Surf.SurfLet(ctx_var, ctx_ty, Surf.SurfAgg(ctx_ty, ctx_inits))
            return Surf.SurfAgg(sig_ty, {
                Surf.SurfFieldInit("fn", Surf.SurfNameRef(helper_name)),
                Surf.SurfFieldInit("ctx", Surf.SurfExprBitcastTo(ptr_void(Surf), Surf.SurfExprRef(Surf.SurfPlaceName(ctx_var)))),
            })
        end
        if k == "SurfInt" or k == "SurfFloat" or k == "SurfBool" or k == "SurfNil" or k == "SurfNameRef" or k == "SurfPathRef" then return expr end
        if k == "SurfExprDot" then return Surf.SurfExprDot(rewrite_expr(expr.base, scope, pre), expr.name) end
        if k == "SurfExprNeg" then return Surf.SurfExprNeg(rewrite_expr(expr.value, scope, pre)) end
        if k == "SurfExprNot" then return Surf.SurfExprNot(rewrite_expr(expr.value, scope, pre)) end
        if k == "SurfExprBNot" then return Surf.SurfExprBNot(rewrite_expr(expr.value, scope, pre)) end
        if k == "SurfExprRef" then return Surf.SurfExprRef(rewrite_place(expr.place, scope, pre)) end
        if k == "SurfExprDeref" then return Surf.SurfExprDeref(rewrite_expr(expr.value, scope, pre)) end
        local bin = {
            SurfExprAdd = Surf.SurfExprAdd, SurfExprSub = Surf.SurfExprSub, SurfExprMul = Surf.SurfExprMul,
            SurfExprDiv = Surf.SurfExprDiv, SurfExprRem = Surf.SurfExprRem, SurfExprEq = Surf.SurfExprEq,
            SurfExprNe = Surf.SurfExprNe, SurfExprLt = Surf.SurfExprLt, SurfExprLe = Surf.SurfExprLe,
            SurfExprGt = Surf.SurfExprGt, SurfExprGe = Surf.SurfExprGe, SurfExprAnd = Surf.SurfExprAnd,
            SurfExprOr = Surf.SurfExprOr, SurfExprBitAnd = Surf.SurfExprBitAnd, SurfExprBitOr = Surf.SurfExprBitOr,
            SurfExprBitXor = Surf.SurfExprBitXor, SurfExprShl = Surf.SurfExprShl, SurfExprLShr = Surf.SurfExprLShr,
            SurfExprAShr = Surf.SurfExprAShr,
        }
        if bin[k] then return bin[k](rewrite_expr(expr.lhs, scope, pre), rewrite_expr(expr.rhs, scope, pre)) end
        local cast = {
            SurfExprCastTo = Surf.SurfExprCastTo, SurfExprTruncTo = Surf.SurfExprTruncTo,
            SurfExprZExtTo = Surf.SurfExprZExtTo, SurfExprSExtTo = Surf.SurfExprSExtTo,
            SurfExprBitcastTo = Surf.SurfExprBitcastTo, SurfExprSatCastTo = Surf.SurfExprSatCastTo,
        }
        if cast[k] then return cast[k](transform_type(expr.ty), rewrite_expr(expr.value, scope, pre)) end
        if k == "SurfExprIntrinsicCall" then
            local args = {}; for i = 1, #expr.args do args[i] = rewrite_expr(expr.args[i], scope, pre) end
            return Surf.SurfExprIntrinsicCall(expr.op, args)
        end
        if k == "SurfCall" then
            local callee = rewrite_expr(expr.callee, scope, pre)
            local args = {}; for i = 1, #expr.args do args[i] = rewrite_expr(expr.args[i], scope, pre) end
            local fn, ctx = closure_call_parts(expr.callee, callee, scope)
            if fn ~= nil then
                local call_args = { ctx }
                for i = 1, #args do call_args[#call_args + 1] = args[i] end
                return Surf.SurfCall(fn, call_args)
            end
            return Surf.SurfCall(callee, args)
        end
        if k == "SurfField" then return Surf.SurfField(rewrite_expr(expr.base, scope, pre), expr.name) end
        if k == "SurfIndex" then return Surf.SurfIndex(rewrite_expr(expr.base, scope, pre), rewrite_expr(expr.index, scope, pre)) end
        if k == "SurfAgg" then
            local fields = {}; for i = 1, #expr.fields do fields[i] = Surf.SurfFieldInit(expr.fields[i].name, rewrite_expr(expr.fields[i].value, scope, pre)) end
            return Surf.SurfAgg(transform_type(expr.ty), fields)
        end
        if k == "SurfArrayLit" then
            local elems = {}; for i = 1, #expr.elems do elems[i] = rewrite_expr(expr.elems[i], scope, pre) end
            return Surf.SurfArrayLit(transform_type(expr.elem_ty), elems)
        end
        if k == "SurfIfExpr" then return Surf.SurfIfExpr(rewrite_expr(expr.cond, scope, pre), rewrite_expr(expr.then_expr, scope, pre), rewrite_expr(expr.else_expr, scope, pre)) end
        if k == "SurfSelectExpr" then return Surf.SurfSelectExpr(rewrite_expr(expr.cond, scope, pre), rewrite_expr(expr.then_expr, scope, pre), rewrite_expr(expr.else_expr, scope, pre)) end
        if k == "SurfSwitchExpr" then
            local arms = {}; for i = 1, #expr.arms do arms[i] = Surf.SurfSwitchExprArm(rewrite_expr(expr.arms[i].key, scope, pre), process_body(expr.arms[i].body, copy_scope(scope)), rewrite_expr(expr.arms[i].result, scope, pre)) end
            return Surf.SurfSwitchExpr(rewrite_expr(expr.value, scope, pre), arms, rewrite_expr(expr.default_expr, scope, pre))
        end
        if k == "SurfBlockExpr" then return Surf.SurfBlockExpr(process_body(expr.stmts, copy_scope(scope)), rewrite_expr(expr.result, scope, pre)) end
        if k == "SurfExprView" then return Surf.SurfExprView(rewrite_expr(expr.base, scope, pre)) end
        if k == "SurfExprViewWindow" then return Surf.SurfExprViewWindow(rewrite_expr(expr.base, scope, pre), rewrite_expr(expr.start, scope, pre), rewrite_expr(expr.len, scope, pre)) end
        if k == "SurfExprViewFromPtr" then return Surf.SurfExprViewFromPtr(rewrite_expr(expr.ptr, scope, pre), rewrite_expr(expr.len, scope, pre)) end
        if k == "SurfExprViewFromPtrStrided" then return Surf.SurfExprViewFromPtrStrided(rewrite_expr(expr.ptr, scope, pre), rewrite_expr(expr.len, scope, pre), rewrite_expr(expr.stride, scope, pre)) end
        if k == "SurfExprViewStrided" then return Surf.SurfExprViewStrided(rewrite_expr(expr.base, scope, pre), rewrite_expr(expr.stride, scope, pre)) end
        if k == "SurfExprViewInterleaved" then return Surf.SurfExprViewInterleaved(rewrite_expr(expr.base, scope, pre), rewrite_expr(expr.stride, scope, pre), rewrite_expr(expr.lane, scope, pre)) end
        return expr
    end

    rewrite_stmt = function(stmt, scope)
        local pre = {}
        local out
        local k = stmt.kind
        if k == "SurfLet" or k == "SurfVar" then
            local init = rewrite_expr(stmt.init, scope, pre)
            local ty = transform_type(stmt.ty)
            out = Surf[k](stmt.name, ty, init)
            scope[stmt.name] = { ty = ty, is_closure = is_closure_type(stmt.ty), by_ref = false }
        elseif k == "SurfSet" then
            out = Surf.SurfSet(rewrite_place(stmt.place, scope, pre), rewrite_expr(stmt.value, scope, pre))
        elseif k == "SurfExprStmt" then out = Surf.SurfExprStmt(rewrite_expr(stmt.expr, scope, pre))
        elseif k == "SurfAssert" then out = Surf.SurfAssert(rewrite_expr(stmt.cond, scope, pre))
        elseif k == "SurfIf" then
            local cond = rewrite_expr(stmt.cond, scope, pre)
            out = Surf.SurfIf(cond, process_body(stmt.then_body or {}, copy_scope(scope)), process_body(stmt.else_body or {}, copy_scope(scope)))
        elseif k == "SurfSwitch" then
            local arms = {}
            for i = 1, #stmt.arms do arms[i] = Surf.SurfSwitchStmtArm(rewrite_expr(stmt.arms[i].key, scope, pre), process_body(stmt.arms[i].body, copy_scope(scope))) end
            out = Surf.SurfSwitch(rewrite_expr(stmt.value, scope, pre), arms, process_body(stmt.default_body or {}, copy_scope(scope)))
        elseif k == "SurfReturnVoid" then out = Surf.SurfReturnVoid
        elseif k == "SurfReturnValue" then out = Surf.SurfReturnValue(rewrite_expr(stmt.value, scope, pre))
        elseif k == "SurfBreak" then out = Surf.SurfBreak
        elseif k == "SurfBreakValue" then out = Surf.SurfBreakValue(rewrite_expr(stmt.value, scope, pre))
        elseif k == "SurfContinue" then out = Surf.SurfContinue
        elseif k == "SurfStmtLoop" then out = stmt -- Closure expressions inside loop bodies are deferred until loop-body rewrite is made fully scope-aware.
        else out = stmt end
        local result = {}
        for i = 1, #pre do result[#result + 1] = pre[i] end
        result[#result + 1] = out
        return result
    end

    process_body = function(stmts, scope)
        local out = {}
        local local_scope = scope or {}
        for i = 1, #(stmts or {}) do
            local expanded = rewrite_stmt(stmts[i], local_scope)
            for j = 1, #expanded do out[#out + 1] = expanded[j] end
        end
        return out
    end

    local function transform_field_decl(f)
        return Surf.SurfFieldDecl(f.field_name, transform_type(f.ty))
    end

    local function transform_type_decl(t)
        if t.kind == "SurfStruct" then
            local fields = {}; for i = 1, #t.fields do fields[i] = transform_field_decl(t.fields[i]) end
            return Surf.SurfStruct(t.name, fields)
        end
        if t.kind == "SurfUnion" then
            local fields = {}; for i = 1, #t.fields do fields[i] = transform_field_decl(t.fields[i]) end
            return Surf.SurfUnion(t.name, fields)
        end
        return t
    end

    local rewritten_items = {}
    for _, item in ipairs(module.items) do
        if item.func then
            local f = item.func
            local params = {}
            local scope = {}
            for i = 1, #f.params do
                params[i] = transform_param(f.params[i])
                scope[params[i].name] = { ty = params[i].ty, is_closure = is_closure_type(f.params[i].ty), by_ref = is_closure_type(f.params[i].ty) }
            end
            local body = process_body(f.body, scope)
            local result = transform_type(f.result)
            if f.kind == "SurfFuncExport" then
                rewritten_items[#rewritten_items + 1] = Surf.SurfItemFunc(Surf.SurfFuncExport(f.name, params, result, body))
            else
                rewritten_items[#rewritten_items + 1] = Surf.SurfItemFunc(Surf.SurfFuncLocal(f.name, params, result, body))
            end
        elseif item.func == nil and item.t ~= nil then
            rewritten_items[#rewritten_items + 1] = Surf.SurfItemType(transform_type_decl(item.t))
        elseif item.c ~= nil then
            local pre = {}
            rewritten_items[#rewritten_items + 1] = Surf.SurfItemConst(Surf.SurfConst(item.c.name, transform_type(item.c.ty), rewrite_expr(item.c.value, {}, pre)))
            for i = #pre, 1, -1 do
                error("desugar_closures: closure expressions are not valid in const item initializers")
            end
        elseif item.s ~= nil then
            local pre = {}
            rewritten_items[#rewritten_items + 1] = Surf.SurfItemStatic(Surf.SurfStatic(item.s.name, transform_type(item.s.ty), rewrite_expr(item.s.value, {}, pre)))
            if #pre ~= 0 then error("desugar_closures: closure expressions are not valid in static item initializers") end
        else
            rewritten_items[#rewritten_items + 1] = item
        end
    end

    local all = {}
    for i = 1, #sig_items do all[#all + 1] = sig_items[i] end
    for i = 1, #generated_items do all[#all + 1] = generated_items[i] end
    for i = 1, #rewritten_items do all[#all + 1] = rewritten_items[i] end
    return Surf.SurfModule(all)
end

return M
