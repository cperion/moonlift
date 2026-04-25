package.path = "./?.lua;./?/init.lua;" .. package.path

-- desugar_closures.lua
-- Surface -> Surface pass: transforms every SurfClosureExpr in a module
-- into module-level generated struct + function items, and replaces the
-- closure expression with a struct aggregate that constructs the
-- {fn, ctx} closure value.

local M = {}

-- Walk the closure body and collect names that are NOT closure params
-- and NOT locally introduced bindings; these are the captured variables.
local function free_vars_in_body(stmts, closure_params, Surf)
    local captured = {}
    local seen = {}

    local function try_capture(name)
        if seen[name] then return end
        for _, p in ipairs(closure_params) do
            if p.name == name then return end
        end
        seen[name] = true
        captured[#captured + 1] = name
    end

    local function walk_expr(expr)
        if not expr then return end
        local k = expr.kind
        if k == "SurfNameRef" then
            try_capture(expr.name)
            return
        end
        -- Walk children: dispatch on expression form
        local children = {}
        if expr.value then children[#children+1] = expr.value end
        if expr.lhs then children[#children+1] = expr.lhs end
        if expr.rhs then children[#children+1] = expr.rhs end
        if expr.base then children[#children+1] = expr.base end
        if expr.callee then children[#children+1] = expr.callee end
        if expr.cond then children[#children+1] = expr.cond end
        if expr.then_expr then children[#children+1] = expr.then_expr end
        if expr.else_expr then children[#children+1] = expr.else_expr end
        if expr.default_expr then children[#children+1] = expr.default_expr end
        if expr.index then children[#children+1] = expr.index end
        if expr.result then children[#children+1] = expr.result end
        if expr.args then for _, a in ipairs(expr.args) do children[#children+1] = a end end
        if expr.elems then for _, e in ipairs(expr.elems) do children[#children+1] = e end end
        if expr.fields then
            for _, f in ipairs(expr.fields) do
                if f.value then children[#children+1] = f.value end
            end
        end
        if expr.arms then
            for _, arm in ipairs(expr.arms) do
                if arm.key then children[#children+1] = arm.key end
                if arm.body then for _, s in ipairs(arm.body) do walk_stmt(s) end end
                if arm.result then children[#children+1] = arm.result end
            end
        end
        if expr.stmts then for _, s in ipairs(expr.stmts) do walk_stmt(s) end end
        if expr.loop then
            local l = expr.loop
            if l.cond then children[#children+1] = l.cond end
            if l.body then for _, s in ipairs(l.body) do walk_stmt(s) end end
            if l.next then for _, n in ipairs(l.next) do children[#children+1] = n.value end end
            if l.result then children[#children+1] = l.result end
            if l.carries then for _, c in ipairs(l.carries) do children[#children+1] = c.init end end
            if l.domain then
                local d = l.domain
                if d.stop then children[#children+1] = d.stop end
                if d.start then children[#children+1] = d.start end
                if d.value then children[#children+1] = d.value end
                if d.values then for _, v in ipairs(d.values) do children[#children+1] = v end end
            end
        end
        if expr.value then -- for SurfExprRef place-based
            -- SurfPlace: NameRef, PathRef, Deref, Dot, Field, Index
            local p = expr.place
            if p then
                if p.base then children[#children+1] = p.base end
                if p.index then children[#children+1] = p.index end
            end
        end
        for _, c in ipairs(children) do
            walk_expr(c)
        end
    end

    local function walk_stmt(stmt)
        if not stmt then return end
        local sk = stmt.kind
        if sk == "SurfLet" or sk == "SurfVar" then
            walk_expr(stmt.init)
        elseif sk == "SurfSet" then
            walk_expr(stmt.value)
        elseif sk == "SurfExprStmt" then
            walk_expr(stmt.expr)
        elseif sk == "SurfAssert" then
            walk_expr(stmt.cond)
        elseif sk == "SurfReturnValue" then
            walk_expr(stmt.value)
        elseif sk == "SurfBreakValue" then
            walk_expr(stmt.value)
        elseif sk == "SurfIf" then
            walk_expr(stmt.cond)
            for _, s in ipairs(stmt.then_body or {}) do walk_stmt(s) end
            for _, s in ipairs(stmt.else_body or {}) do walk_stmt(s) end
        elseif sk == "SurfSwitch" then
            walk_expr(stmt.value)
            for _, arm in ipairs(stmt.arms or {}) do
                if arm.key then walk_expr(arm.key) end
                for _, s in ipairs(arm.body or {}) do walk_stmt(s) end
            end
            for _, s in ipairs(stmt.default_body or {}) do walk_stmt(s) end
        elseif sk == "SurfStmtLoop" then
            walk_loop(stmt.loop)
        end
    end

    local function walk_loop(loop)
        if not loop then return end
        if loop.cond then walk_expr(loop.cond) end
        if loop.body then for _, s in ipairs(loop.body) do walk_stmt(s) end end
        if loop.next then for _, n in ipairs(loop.next) do walk_expr(n.value) end end
        if loop.result then walk_expr(loop.result) end
        if loop.carries then for _, c in ipairs(loop.carries) do walk_expr(c.init) end end
        if loop.domain then
            local d = loop.domain
            if d.stop then walk_expr(d.stop) end
            if d.start then walk_expr(d.start) end
            if d.value then walk_expr(d.value) end
            if d.values then for _, v in ipairs(d.values) do walk_expr(v) end end
        end
    end

    for _, stmt in ipairs(stmts) do
        walk_stmt(stmt)
    end

    return captured
end

-- Build the binding stack at a given point in a function body.
-- Returns all names visible: function params + let/var bindings before the position.
local function build_scope(stmts, up_to_index, fn_params)
    local scope = {}
    -- Add function params
    for _, p in ipairs(fn_params or {}) do
        scope[p.name] = true
    end
    -- Add let/var bindings up to (but not including) up_to_index
    for i = 1, (up_to_index or #stmts) - 1 do
        local s = stmts[i]
        if s.kind == "SurfLet" or s.kind == "SurfVar" then
            scope[s.name] = true
        end
    end
    return scope
end

-- Module-level globals: exported funcs, consts, static names.
local function build_module_scope(items)
    local scope = {}
    for _, item in ipairs(items) do
        if item.func then
            scope[item.func.name] = true
        elseif item.c then
            scope[item.c.name] = true
        elseif item.s then
            scope[item.s.name] = true
        end
    end
    return scope
end

-- Check if a name is a module-level global.
local function is_module_global(name, module_scope)
    return module_scope[name] == true
end

-- Main desugaring: walks the module, finds closures, generates
-- ctx structs + helper funcs + closure struct types, rewrites everything.
function M.desugar(module, Surf)
    if not module or not module.items then return module end

    local closure_count = 0
    local new_items_before = {}  -- items to insert at module level
    local items_after = {}       -- rewritten items
    local module_scope = build_module_scope(module.items)

    -- Clone a struct value by generating constructor calls
    local function clone_type(ty)
        -- simplified: return as-is (Surface types are immutable)
        return ty
    end

    -- Determine the type of a captured variable.
    -- We need to track types through the function body. For now,
    -- use a simple approach: for function params, use the declared type.
    -- For let/var bindings, track the declared type.
    local function infer_type(name, fn_params, stmts, pos)
        -- Check function params
        for _, p in ipairs(fn_params or {}) do
            if p.name == name then return clone_type(p.ty) end
        end
        -- Check let/var bindings before position
        for i = 1, (pos or #stmts) - 1 do
            local s = stmts[i]
            if (s.kind == "SurfLet" or s.kind == "SurfVar") and s.name == name then
                return clone_type(s.ty)
            end
        end
        -- Check loop carries in enclosing loops (simplified)
        return nil -- unknown type → will be reported
    end

    -- Process a function body: find closures, generate items, rewrite.
    local function process_body(stmts, fn_params, result_ty)
        if not stmts then return stmts, {}, {} end
        local new_stmts = {}
        local gen_items = {}   -- generated module items
        local pre_stmts = {}   -- ctx init statements to insert before the closure

        for idx = 1, #stmts do
            local stmt = stmts[idx]

            -- Check if this statement contains a closure expression
            local function replace_closures(expr)
                if not expr then return expr end
                if expr.kind == "SurfClosureExpr" then
                    closure_count = closure_count + 1
                    local cid = closure_count

                    -- Find free variables in the closure body
                    -- Exclude: closure params, module globals, names in scope at closure site
                    local free = free_vars_in_body(expr.body, expr.params, Surf)
                    local scope = build_scope(stmts, idx, fn_params)

                    -- Filter: only capture names that are in scope but not module globals
                    local captures = {}
                    local capture_types = {}
                    for _, name in ipairs(free) do
                        if scope[name] and not is_module_global(name, module_scope) then
                            captures[#captures + 1] = name
                            local ty = infer_type(name, fn_params, stmts, idx)
                            capture_types[name] = ty or Surf.SurfTVoid -- fallback
                        end
                    end

                    -- Generate context struct type
                    local ctx_name = "_closure_ctx_" .. cid
                    local ctx_fields = {}
                    for _, name in ipairs(captures) do
                        ctx_fields[#ctx_fields + 1] = Surf.SurfFieldDecl(name, capture_types[name])
                    end
                    gen_items[#gen_items + 1] = Surf.SurfItemType(Surf.SurfStruct(ctx_name, ctx_fields))

                    -- Generate closure struct type
                    local closure_type_name = "_closure_" .. cid
                    local param_types = {}
                    for _, p in ipairs(expr.params) do
                        param_types[#param_types + 1] = clone_type(p.ty)
                    end
                    local fn_field_type = Surf.SurfTFunc(
                        { Surf.SurfTPtr(Surf.SurfTNamed(Surf.SurfPath({Surf.SurfName(ctx_name)}))), unpack(param_types) },
                        clone_type(expr.result)
                    )
                    gen_items[#gen_items + 1] = Surf.SurfItemType(Surf.SurfStruct(closure_type_name, {
                        Surf.SurfFieldDecl("fn", fn_field_type),
                        Surf.SurfFieldDecl("ctx", Surf.SurfTPtr(Surf.SurfTNamed(Surf.SurfPath({Surf.SurfName(ctx_name)})))),
                    }))

                    -- Generate helper function
                    local fn_name = "_closure_fn_" .. cid
                    local fn_params = {
                        Surf.SurfParam("ctx", Surf.SurfTPtr(Surf.SurfTNamed(Surf.SurfPath({Surf.SurfName(ctx_name)})))),
                    }
                    for _, p in ipairs(expr.params) do
                        fn_params[#fn_params + 1] = Surf.SurfParam(p.name, clone_type(p.ty))
                    end

                    -- Rewrite closure body: replace captured vars with (*ctx).field
                    local function rewrite_expr(e)
                        if not e then return e end
                        if e.kind == "SurfNameRef" then
                            for _, cap in ipairs(captures) do
                                if e.name == cap then
                                    -- Replace: name → (*ctx).name via SurfField(SurfExprDeref(SurfNameRef("ctx")), name)
                                    return Surf.SurfField(
                                        Surf.SurfExprDeref(Surf.SurfNameRef("ctx")),
                                        cap
                                    )
                                end
                            end
                            return e
                        end
                        -- For compound expressions, recurse into children
                        local rw = function(x) return rewrite_expr(x) end
                        -- Binary expressions
                        if e.lhs and e.rhs then
                            return Surf[e.kind](rw(e.lhs), rw(e.rhs))
                        end
                        -- Unary expressions
                        if e.value then
                            return Surf[e.kind](rw(e.value))
                        end
                        -- Call expressions
                        if e.callee then
                            local args = {}
                            if e.args then for _, a in ipairs(e.args) do args[#args+1] = rw(a) end end
                            return Surf.SurfCall(rw(e.callee), args)
                        end
                        -- If/select/switch expressions
                        if e.cond and e.then_expr then
                            return Surf[e.kind](rw(e.cond), rw(e.then_expr), rw(e.else_expr))
                        end
                        -- Field access: rewrite base
                        if e.base and e.name then
                            return Surf.SurfField(rw(e.base), e.name)
                        end
                        -- Index: rewrite base and index
                        if e.base and e.index then
                            return Surf.SurfIndex(rw(e.base), rw(e.index))
                        end
                        -- Intrinsic calls
                        if e.op and e.args then
                            local args = {}
                            for _, a in ipairs(e.args) do args[#args+1] = rw(a) end
                            return Surf.SurfExprIntrinsicCall(e.op, args)
                        end
                        return e
                    end

                    -- For now, use the original body with captured var rewriting
                    local rewritten_body = {}
                    for _, s in ipairs(expr.body) do
                        if s.kind == "SurfReturnValue" then
                            rewritten_body[#rewritten_body + 1] = Surf.SurfReturnValue(rewrite_expr(s.value))
                        elseif s.kind == "SurfExprStmt" then
                            rewritten_body[#rewritten_body + 1] = Surf.SurfExprStmt(rewrite_expr(s.expr))
                        elseif s.kind == "SurfAssert" then
                            rewritten_body[#rewritten_body + 1] = Surf.SurfAssert(rewrite_expr(s.cond))
                        elseif s.kind == "SurfLet" then
                            rewritten_body[#rewritten_body + 1] = Surf.SurfLet(s.name, clone_type(s.ty), rewrite_expr(s.init))
                        elseif s.kind == "SurfVar" then
                            rewritten_body[#rewritten_body + 1] = Surf.SurfVar(s.name, clone_type(s.ty), rewrite_expr(s.init))
                        elseif s.kind == "SurfSet" then
                            rewritten_body[#rewritten_body + 1] = Surf.SurfSet(s.place, rewrite_expr(s.value))
                        elseif s.kind == "SurfIf" then
                            rewritten_body[#rewritten_body + 1] = Surf.SurfIf(
                                rewrite_expr(s.cond),
                                process_body(s.then_body or {}, {}, nil),
                                process_body(s.else_body or {}, {}, nil)
                            )
                        else
                            rewritten_body[#rewritten_body + 1] = s
                        end
                    end

                    gen_items[#gen_items + 1] = Surf.SurfItemFunc(Surf.SurfFuncLocal(fn_name, fn_params, clone_type(expr.result), rewritten_body))

                    -- Create ctx init statement
                    local ctx_fields_init = {}
                    for _, name in ipairs(captures) do
                        ctx_fields_init[#ctx_fields_init + 1] = Surf.SurfFieldInit(name, Surf.SurfNameRef(name))
                    end
                    local ctx_var_name = "_closure_ctx_val_" .. cid
                    pre_stmts[#pre_stmts + 1] = Surf.SurfLet(ctx_var_name, Surf.SurfTNamed(Surf.SurfPath({Surf.SurfName(ctx_name)})),
                        Surf.SurfAgg(Surf.SurfTNamed(Surf.SurfPath({Surf.SurfName(ctx_name)})), ctx_fields_init))

                    -- Replace closure expression with struct aggregate
                    local closure_value = Surf.SurfAgg(
                        Surf.SurfTNamed(Surf.SurfPath({Surf.SurfName(closure_type_name)})),
                        {
                            Surf.SurfFieldInit("fn", Surf.SurfNameRef(fn_name)),
                            Surf.SurfFieldInit("ctx", Surf.SurfExprRef(Surf.SurfPlaceName(ctx_var_name))),
                        }
                    )
                    return closure_value
                end

                -- Recursively process sub-expressions
                -- For non-closure expressions, just return as-is;
                -- the recursion is only for finding nested closures.
                return expr
            end

            -- Process statement-level expressions
            local new_stmt = stmt
            local k = stmt.kind
            if k == "SurfLet" or k == "SurfVar" then
                local new_init = replace_closures(stmt.init)
                if new_init ~= stmt.init then
                    for _, ps in ipairs(pre_stmts) do
                        new_stmts[#new_stmts + 1] = ps
                    end
                    pre_stmts = {}
                    new_stmt = Surf[k](stmt.name, clone_type(stmt.ty), new_init)
                end
            elseif k == "SurfExprStmt" then
                local new_expr = replace_closures(stmt.expr)
                if new_expr ~= stmt.expr then
                    for _, ps in ipairs(pre_stmts) do
                        new_stmts[#new_stmts + 1] = ps
                    end
                    pre_stmts = {}
                    new_stmt = Surf.SurfExprStmt(new_expr)
                end
            elseif k == "SurfAssert" then
                local new_cond = replace_closures(stmt.cond)
                if new_cond ~= stmt.cond then
                    for _, ps in ipairs(pre_stmts) do
                        new_stmts[#new_stmts + 1] = ps
                    end
                    pre_stmts = {}
                    new_stmt = Surf.SurfAssert(new_cond)
                end
            elseif k == "SurfReturnValue" then
                local new_val = replace_closures(stmt.value)
                if new_val ~= stmt.value then
                    for _, ps in ipairs(pre_stmts) do
                        new_stmts[#new_stmts + 1] = ps
                    end
                    pre_stmts = {}
                    new_stmt = Surf.SurfReturnValue(new_val)
                end
            elseif k == "SurfSet" then
                local new_val = replace_closures(stmt.value)
                if new_val ~= stmt.value then
                    for _, ps in ipairs(pre_stmts) do
                        new_stmts[#new_stmts + 1] = ps
                    end
                    pre_stmts = {}
                    new_stmt = Surf.SurfSet(stmt.place, new_val)
                end
            elseif k == "SurfIf" then
                local new_cond = replace_closures(stmt.cond)
                if new_cond ~= stmt.cond then
                    for _, ps in ipairs(pre_stmts) do
                        new_stmts[#new_stmts + 1] = ps
                    end
                    pre_stmts = {}
                end
                local new_then, then_items, then_pre = process_body(stmt.then_body or {}, fn_params or {}, result_ty)
                local new_else, else_items, else_pre = process_body(stmt.else_body or {}, fn_params or {}, result_ty)
                for _, it in ipairs(then_items) do gen_items[#gen_items+1] = it end
                for _, it in ipairs(else_items) do gen_items[#gen_items+1] = it end
                new_stmt = Surf.SurfIf(new_cond, new_then, new_else)
            else
                -- pass through
            end

            new_stmts[#new_stmts + 1] = new_stmt
        end

        -- Flush remaining pre-stmts
        for _, ps in ipairs(pre_stmts) do
            new_stmts[#new_stmts + 1] = ps
        end

        return new_stmts, gen_items, {}
    end

    -- Process each item in the module
    for _, item in ipairs(module.items) do
        if item.func then
            local f = item.func
            local new_body, gen_items, _ = process_body(f.body, f.params, f.result)
            -- Insert generated items before this function
            for _, gi in ipairs(gen_items) do
                new_items_before[#new_items_before + 1] = gi
            end
            -- Rewrite the function with new body, preserving visibility as an explicit ASDL variant.
            local new_func
            if f.kind == "SurfFuncExport" then
                new_func = Surf.SurfFuncExport(f.name, f.params, f.result, new_body)
            else
                new_func = Surf.SurfFuncLocal(f.name, f.params, f.result, new_body)
            end
            items_after[#items_after + 1] = Surf.SurfItemFunc(new_func)
        else
            items_after[#items_after + 1] = item
        end
    end

    -- Combine: new items inserted before the original items
    local all_items = {}
    for _, it in ipairs(new_items_before) do all_items[#all_items+1] = it end
    for _, it in ipairs(items_after) do all_items[#all_items+1] = it end

    return Surf.SurfModule(all_items)
end

return M
