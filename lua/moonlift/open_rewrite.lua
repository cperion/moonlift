local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Ty = T.MoonType
    local O = T.MoonOpen
    local B = T.MoonBind
    local Tr = T.MoonTree

    local type_rule_target
    local binding_rule_target
    local place_rule_target
    local domain_rule_target
    local expr_rule_target
    local stmt_rule_target
    local item_rule_target
    local rewrite_type
    local rewrite_binding
    local rewrite_value_ref
    local rewrite_place
    local rewrite_expr
    local rewrite_stmt
    local rewrite_view
    local rewrite_domain
    local rewrite_index_base
    local rewrite_control_stmt_region
    local rewrite_control_expr_region
    local rewrite_func
    local rewrite_extern
    local rewrite_const
    local rewrite_static
    local rewrite_type_decl
    local rewrite_item
    local rewrite_module

    local function rule_targets(phase, set, value)
        local out = {}
        for i = 1, #set.rules do
            local g, p, c = phase(set.rules[i], value)
            pvm.drain_into(g, p, c, out)
        end
        return out
    end

    local function first_target(phase, set, value)
        local targets = rule_targets(phase, set, value)
        return targets[1]
    end

    local function one(phase, node, set)
        return pvm.one(phase(node, set))
    end

    local function rewrite_types(xs, set)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(rewrite_type, xs[i], set) end
        return out
    end

    local function rewrite_exprs(xs, set)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(rewrite_expr, xs[i], set) end
        return out
    end

    local function rewrite_stmts(xs, set)
        local out = {}
        for i = 1, #xs do
            local g, p, c = rewrite_stmt(xs[i], set)
            pvm.drain_into(g, p, c, out)
        end
        return out
    end

    local function rewrite_jump_args(xs, set)
        local out = {}
        for i = 1, #xs do out[#out + 1] = pvm.with(xs[i], { value = one(rewrite_expr, xs[i].value, set) }) end
        return out
    end

    local function rewrite_items(xs, set)
        local out = {}
        for i = 1, #xs do
            local g, p, c = rewrite_item(xs[i], set)
            pvm.drain_into(g, p, c, out)
        end
        return out
    end

    type_rule_target = pvm.phase("moonlift_open_rewrite_type_rule_target", {
        [O.RewriteType] = function(self, value) if self.from == value then return pvm.once(self.to) end return pvm.empty() end,
        [O.RewriteBinding] = function() return pvm.empty() end,
        [O.RewritePlace] = function() return pvm.empty() end,
        [O.RewriteDomain] = function() return pvm.empty() end,
        [O.RewriteExpr] = function() return pvm.empty() end,
        [O.RewriteStmt] = function() return pvm.empty() end,
        [O.RewriteItem] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    binding_rule_target = pvm.phase("moonlift_open_rewrite_binding_rule_target", {
        [O.RewriteBinding] = function(self, value) if self.from == value then return pvm.once(self.to) end return pvm.empty() end,
        [O.RewriteType] = function() return pvm.empty() end,
        [O.RewritePlace] = function() return pvm.empty() end,
        [O.RewriteDomain] = function() return pvm.empty() end,
        [O.RewriteExpr] = function() return pvm.empty() end,
        [O.RewriteStmt] = function() return pvm.empty() end,
        [O.RewriteItem] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    place_rule_target = pvm.phase("moonlift_open_rewrite_place_rule_target", {
        [O.RewritePlace] = function(self, value) if self.from == value then return pvm.once(self.to) end return pvm.empty() end,
        [O.RewriteType] = function() return pvm.empty() end,
        [O.RewriteBinding] = function() return pvm.empty() end,
        [O.RewriteDomain] = function() return pvm.empty() end,
        [O.RewriteExpr] = function() return pvm.empty() end,
        [O.RewriteStmt] = function() return pvm.empty() end,
        [O.RewriteItem] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    domain_rule_target = pvm.phase("moonlift_open_rewrite_domain_rule_target", {
        [O.RewriteDomain] = function(self, value) if self.from == value then return pvm.once(self.to) end return pvm.empty() end,
        [O.RewriteType] = function() return pvm.empty() end,
        [O.RewriteBinding] = function() return pvm.empty() end,
        [O.RewritePlace] = function() return pvm.empty() end,
        [O.RewriteExpr] = function() return pvm.empty() end,
        [O.RewriteStmt] = function() return pvm.empty() end,
        [O.RewriteItem] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    expr_rule_target = pvm.phase("moonlift_open_rewrite_expr_rule_target", {
        [O.RewriteExpr] = function(self, value) if self.from == value then return pvm.once(self.to) end return pvm.empty() end,
        [O.RewriteType] = function() return pvm.empty() end,
        [O.RewriteBinding] = function() return pvm.empty() end,
        [O.RewritePlace] = function() return pvm.empty() end,
        [O.RewriteDomain] = function() return pvm.empty() end,
        [O.RewriteStmt] = function() return pvm.empty() end,
        [O.RewriteItem] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    stmt_rule_target = pvm.phase("moonlift_open_rewrite_stmt_rule_target", {
        [O.RewriteStmt] = function(self, value) if self.from == value then return pvm.children(function(stmt) return pvm.once(stmt) end, self.to) end return pvm.empty() end,
        [O.RewriteType] = function() return pvm.empty() end,
        [O.RewriteBinding] = function() return pvm.empty() end,
        [O.RewritePlace] = function() return pvm.empty() end,
        [O.RewriteDomain] = function() return pvm.empty() end,
        [O.RewriteExpr] = function() return pvm.empty() end,
        [O.RewriteItem] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    item_rule_target = pvm.phase("moonlift_open_rewrite_item_rule_target", {
        [O.RewriteItem] = function(self, value) if self.from == value then return pvm.children(function(item) return pvm.once(item) end, self.to) end return pvm.empty() end,
        [O.RewriteType] = function() return pvm.empty() end,
        [O.RewriteBinding] = function() return pvm.empty() end,
        [O.RewritePlace] = function() return pvm.empty() end,
        [O.RewriteDomain] = function() return pvm.empty() end,
        [O.RewriteExpr] = function() return pvm.empty() end,
        [O.RewriteStmt] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    rewrite_type = pvm.phase("moonlift_open_rewrite_type", {
        [Ty.TScalar] = function(self, set) return pvm.once(first_target(type_rule_target, set, self) or self) end,
        [Ty.TPtr] = function(self, set) local t = first_target(type_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { elem = one(rewrite_type, self.elem, set) })) end,
        [Ty.TArray] = function(self, set) local t = first_target(type_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { elem = one(rewrite_type, self.elem, set) })) end,
        [Ty.TSlice] = function(self, set) local t = first_target(type_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { elem = one(rewrite_type, self.elem, set) })) end,
        [Ty.TView] = function(self, set) local t = first_target(type_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { elem = one(rewrite_type, self.elem, set) })) end,
        [Ty.TFunc] = function(self, set) local t = first_target(type_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { params = rewrite_types(self.params, set), result = one(rewrite_type, self.result, set) })) end,
        [Ty.TClosure] = function(self, set) local t = first_target(type_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { params = rewrite_types(self.params, set), result = one(rewrite_type, self.result, set) })) end,
        [Ty.TNamed] = function(self, set) return pvm.once(first_target(type_rule_target, set, self) or self) end,
        [Ty.TSlot] = function(self, set) return pvm.once(first_target(type_rule_target, set, self) or self) end,
    }, { args_cache = "last" })

    rewrite_binding = pvm.phase("moonlift_open_rewrite_binding", {
        [B.Binding] = function(self, set)
            local t = first_target(binding_rule_target, set, self)
            if t then return pvm.once(t) end
            return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set) }))
        end,
    }, { args_cache = "last" })

    rewrite_value_ref = pvm.phase("moonlift_open_rewrite_value_ref", {
        [B.ValueRefBinding] = function(self, set) return pvm.once(pvm.with(self, { binding = one(rewrite_binding, self.binding, set) })) end,
        [B.ValueRefName] = function(self) return pvm.once(self) end,
        [B.ValueRefPath] = function(self) return pvm.once(self) end,
        [B.ValueRefSlot] = function(self) return pvm.once(self) end,
        [B.ValueRefFuncSlot] = function(self) return pvm.once(self) end,
        [B.ValueRefConstSlot] = function(self) return pvm.once(self) end,
        [B.ValueRefStaticSlot] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    rewrite_view = pvm.phase("moonlift_open_rewrite_view", {
        [Tr.ViewFromExpr] = function(self, set) return pvm.once(pvm.with(self, { base = one(rewrite_expr, self.base, set), elem = one(rewrite_type, self.elem, set) })) end,
        [Tr.ViewContiguous] = function(self, set) return pvm.once(pvm.with(self, { data = one(rewrite_expr, self.data, set), elem = one(rewrite_type, self.elem, set), len = one(rewrite_expr, self.len, set) })) end,
        [Tr.ViewStrided] = function(self, set) return pvm.once(pvm.with(self, { data = one(rewrite_expr, self.data, set), elem = one(rewrite_type, self.elem, set), len = one(rewrite_expr, self.len, set), stride = one(rewrite_expr, self.stride, set) })) end,
        [Tr.ViewRestrided] = function(self, set) return pvm.once(pvm.with(self, { base = one(rewrite_view, self.base, set), elem = one(rewrite_type, self.elem, set), stride = one(rewrite_expr, self.stride, set) })) end,
        [Tr.ViewWindow] = function(self, set) return pvm.once(pvm.with(self, { base = one(rewrite_view, self.base, set), start = one(rewrite_expr, self.start, set), len = one(rewrite_expr, self.len, set) })) end,
        [Tr.ViewRowBase] = function(self, set) return pvm.once(pvm.with(self, { base = one(rewrite_view, self.base, set), row_offset = one(rewrite_expr, self.row_offset, set), elem = one(rewrite_type, self.elem, set) })) end,
        [Tr.ViewInterleaved] = function(self, set) return pvm.once(pvm.with(self, { data = one(rewrite_expr, self.data, set), elem = one(rewrite_type, self.elem, set), len = one(rewrite_expr, self.len, set), stride = one(rewrite_expr, self.stride, set), lane = one(rewrite_expr, self.lane, set) })) end,
        [Tr.ViewInterleavedView] = function(self, set) return pvm.once(pvm.with(self, { base = one(rewrite_view, self.base, set), elem = one(rewrite_type, self.elem, set), stride = one(rewrite_expr, self.stride, set), lane = one(rewrite_expr, self.lane, set) })) end,
    }, { args_cache = "last" })

    rewrite_domain = pvm.phase("moonlift_open_rewrite_domain", {
        [Tr.DomainRange] = function(self, set) local t = first_target(domain_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { stop = one(rewrite_expr, self.stop, set) })) end,
        [Tr.DomainRange2] = function(self, set) local t = first_target(domain_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { start = one(rewrite_expr, self.start, set), stop = one(rewrite_expr, self.stop, set) })) end,
        [Tr.DomainZipEqValues] = function(self, set) local t = first_target(domain_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { values = rewrite_exprs(self.values, set) })) end,
        [Tr.DomainValue] = function(self, set) local t = first_target(domain_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { value = one(rewrite_expr, self.value, set) })) end,
        [Tr.DomainView] = function(self, set) local t = first_target(domain_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { view = one(rewrite_view, self.view, set) })) end,
        [Tr.DomainZipEqViews] = function(self, set) local t = first_target(domain_rule_target, set, self); if t then return pvm.once(t) end; local views = {}; for i = 1, #self.views do views[#views + 1] = one(rewrite_view, self.views[i], set) end; return pvm.once(pvm.with(self, { views = views })) end,
        [Tr.DomainSlotValue] = function(self, set) return pvm.once(first_target(domain_rule_target, set, self) or self) end,
    }, { args_cache = "last" })

    rewrite_index_base = pvm.phase("moonlift_open_rewrite_index_base", {
        [Tr.IndexBaseExpr] = function(self, set) return pvm.once(pvm.with(self, { base = one(rewrite_expr, self.base, set) })) end,
        [Tr.IndexBasePlace] = function(self, set) return pvm.once(pvm.with(self, { base = one(rewrite_place, self.base, set), elem = one(rewrite_type, self.elem, set) })) end,
        [Tr.IndexBaseView] = function(self, set) return pvm.once(pvm.with(self, { view = one(rewrite_view, self.view, set) })) end,
    }, { args_cache = "last" })

    rewrite_place = pvm.phase("moonlift_open_rewrite_place", {
        [Tr.PlaceRef] = function(self, set) local t = first_target(place_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { ref = one(rewrite_value_ref, self.ref, set) })) end,
        [Tr.PlaceDeref] = function(self, set) local t = first_target(place_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { base = one(rewrite_expr, self.base, set) })) end,
        [Tr.PlaceDot] = function(self, set) local t = first_target(place_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { base = one(rewrite_place, self.base, set) })) end,
        [Tr.PlaceField] = function(self, set) local t = first_target(place_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { base = one(rewrite_place, self.base, set) })) end,
        [Tr.PlaceIndex] = function(self, set) local t = first_target(place_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { base = one(rewrite_index_base, self.base, set), index = one(rewrite_expr, self.index, set) })) end,
        [Tr.PlaceSlotValue] = function(self, set) return pvm.once(first_target(place_rule_target, set, self) or self) end,
    }, { args_cache = "last" })

    local function rewrite_entry_block(block, set)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = pvm.with(block.params[i], { ty = one(rewrite_type, block.params[i].ty, set), init = one(rewrite_expr, block.params[i].init, set) }) end
        return pvm.with(block, { params = params, body = rewrite_stmts(block.body, set) })
    end

    local function rewrite_control_block(block, set)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = pvm.with(block.params[i], { ty = one(rewrite_type, block.params[i].ty, set) }) end
        return pvm.with(block, { params = params, body = rewrite_stmts(block.body, set) })
    end

    rewrite_control_stmt_region = pvm.phase("moonlift_open_rewrite_control_stmt_region", {
        [Tr.ControlStmtRegion] = function(self, set)
            local blocks = {}; for i = 1, #self.blocks do blocks[#blocks + 1] = rewrite_control_block(self.blocks[i], set) end
            return pvm.once(pvm.with(self, { entry = rewrite_entry_block(self.entry, set), blocks = blocks }))
        end,
    }, { args_cache = "last" })

    rewrite_control_expr_region = pvm.phase("moonlift_open_rewrite_control_expr_region", {
        [Tr.ControlExprRegion] = function(self, set)
            local blocks = {}; for i = 1, #self.blocks do blocks[#blocks + 1] = rewrite_control_block(self.blocks[i], set) end
            return pvm.once(pvm.with(self, { result_ty = one(rewrite_type, self.result_ty, set), entry = rewrite_entry_block(self.entry, set), blocks = blocks }))
        end,
    }, { args_cache = "last" })

    rewrite_expr = pvm.phase("moonlift_open_rewrite_expr", {
        [Tr.ExprLit] = function(self, set) return pvm.once(first_target(expr_rule_target, set, self) or self) end,
        [Tr.ExprRef] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { ref = one(rewrite_value_ref, self.ref, set) })) end,
        [Tr.ExprDot] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { base = one(rewrite_expr, self.base, set) })) end,
        [Tr.ExprUnary] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { value = one(rewrite_expr, self.value, set) })) end,
        [Tr.ExprBinary] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { lhs = one(rewrite_expr, self.lhs, set), rhs = one(rewrite_expr, self.rhs, set) })) end,
        [Tr.ExprCompare] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { lhs = one(rewrite_expr, self.lhs, set), rhs = one(rewrite_expr, self.rhs, set) })) end,
        [Tr.ExprLogic] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { lhs = one(rewrite_expr, self.lhs, set), rhs = one(rewrite_expr, self.rhs, set) })) end,
        [Tr.ExprCast] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) })) end,
        [Tr.ExprMachineCast] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) })) end,
        [Tr.ExprIntrinsic] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { args = rewrite_exprs(self.args, set) })) end,
        [Tr.ExprAddrOf] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { place = one(rewrite_place, self.place, set) })) end,
        [Tr.ExprDeref] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { value = one(rewrite_expr, self.value, set) })) end,
        [Tr.ExprCall] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { args = rewrite_exprs(self.args, set) })) end,
        [Tr.ExprLen] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { value = one(rewrite_expr, self.value, set) })) end,
        [Tr.ExprField] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { base = one(rewrite_expr, self.base, set) })) end,
        [Tr.ExprIndex] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { base = one(rewrite_index_base, self.base, set), index = one(rewrite_expr, self.index, set) })) end,
        [Tr.ExprAgg] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { value = one(rewrite_expr, self.fields[i].value, set) }) end; return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set), fields = fields })) end,
        [Tr.ExprArray] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { elem_ty = one(rewrite_type, self.elem_ty, set), elems = rewrite_exprs(self.elems, set) })) end,
        [Tr.ExprIf] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { cond = one(rewrite_expr, self.cond, set), then_expr = one(rewrite_expr, self.then_expr, set), else_expr = one(rewrite_expr, self.else_expr, set) })) end,
        [Tr.ExprSelect] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { cond = one(rewrite_expr, self.cond, set), then_expr = one(rewrite_expr, self.then_expr, set), else_expr = one(rewrite_expr, self.else_expr, set) })) end,
        [Tr.ExprSwitch] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = pvm.with(self.arms[i], { body = rewrite_stmts(self.arms[i].body, set), result = one(rewrite_expr, self.arms[i].result, set) }) end; return pvm.once(pvm.with(self, { value = one(rewrite_expr, self.value, set), arms = arms, default_expr = one(rewrite_expr, self.default_expr, set) })) end,
        [Tr.ExprControl] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { region = one(rewrite_control_expr_region, self.region, set) })) end,
        [Tr.ExprBlock] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { stmts = rewrite_stmts(self.stmts, set), result = one(rewrite_expr, self.result, set) })) end,
        [Tr.ExprClosure] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { body = rewrite_stmts(self.body, set) })) end,
        [Tr.ExprView] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { view = one(rewrite_view, self.view, set) })) end,
        [Tr.ExprLoad] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set), addr = one(rewrite_expr, self.addr, set) })) end,
        [Tr.ExprSlotValue] = function(self, set) return pvm.once(first_target(expr_rule_target, set, self) or self) end,
        [Tr.ExprUseExprFrag] = function(self, set) local t = first_target(expr_rule_target, set, self); if t then return pvm.once(t) end; return pvm.once(pvm.with(self, { args = rewrite_exprs(self.args, set) })) end,
    }, { args_cache = "last" })

    rewrite_stmt = pvm.phase("moonlift_open_rewrite_stmt", {
        [Tr.StmtLet] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { binding = one(rewrite_binding, self.binding, set), init = one(rewrite_expr, self.init, set) })) end,
        [Tr.StmtVar] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { binding = one(rewrite_binding, self.binding, set), init = one(rewrite_expr, self.init, set) })) end,
        [Tr.StmtSet] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { place = one(rewrite_place, self.place, set), value = one(rewrite_expr, self.value, set) })) end,
        [Tr.StmtExpr] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { expr = one(rewrite_expr, self.expr, set) })) end,
        [Tr.StmtAssert] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { cond = one(rewrite_expr, self.cond, set) })) end,
        [Tr.StmtIf] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { cond = one(rewrite_expr, self.cond, set), then_body = rewrite_stmts(self.then_body, set), else_body = rewrite_stmts(self.else_body, set) })) end,
        [Tr.StmtSwitch] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = pvm.with(self.arms[i], { body = rewrite_stmts(self.arms[i].body, set) }) end; return pvm.once(pvm.with(self, { value = one(rewrite_expr, self.value, set), arms = arms, default_body = rewrite_stmts(self.default_body, set) })) end,
        [Tr.StmtJump] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { args = rewrite_jump_args(self.args, set) })) end,
        [Tr.StmtJumpCont] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { args = rewrite_jump_args(self.args, set) })) end,
        [Tr.StmtYieldVoid] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(self) end,
        [Tr.StmtYieldValue] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { value = one(rewrite_expr, self.value, set) })) end,
        [Tr.StmtReturnVoid] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(self) end,
        [Tr.StmtReturnValue] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { value = one(rewrite_expr, self.value, set) })) end,
        [Tr.StmtControl] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { region = one(rewrite_control_stmt_region, self.region, set) })) end,
        [Tr.StmtUseRegionSlot] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(self) end,
        [Tr.StmtUseRegionFrag] = function(self, set) local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return pvm.children(function(stmt) return pvm.once(stmt) end, targets) end; return pvm.once(pvm.with(self, { args = rewrite_exprs(self.args, set) })) end,
    }, { args_cache = "last" })

    rewrite_func = pvm.phase("moonlift_open_rewrite_func", {
        [Tr.FuncLocal] = function(self, set) return pvm.once(pvm.with(self, { body = rewrite_stmts(self.body, set) })) end,
        [Tr.FuncExport] = function(self, set) return pvm.once(pvm.with(self, { body = rewrite_stmts(self.body, set) })) end,
        [Tr.FuncLocalContract] = function(self, set) return pvm.once(pvm.with(self, { body = rewrite_stmts(self.body, set) })) end,
        [Tr.FuncExportContract] = function(self, set) return pvm.once(pvm.with(self, { body = rewrite_stmts(self.body, set) })) end,
        [Tr.FuncOpen] = function(self, set) return pvm.once(pvm.with(self, { result = one(rewrite_type, self.result, set), body = rewrite_stmts(self.body, set) })) end,
    }, { args_cache = "last" })

    rewrite_extern = pvm.phase("moonlift_open_rewrite_extern", {
        [Tr.ExternFunc] = function(self, set) return pvm.once(pvm.with(self, { result = one(rewrite_type, self.result, set) })) end,
        [Tr.ExternFuncOpen] = function(self, set) return pvm.once(pvm.with(self, { result = one(rewrite_type, self.result, set) })) end,
    }, { args_cache = "last" })

    rewrite_const = pvm.phase("moonlift_open_rewrite_const", {
        [Tr.ConstItem] = function(self, set) return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) })) end,
        [Tr.ConstItemOpen] = function(self, set) return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) })) end,
    }, { args_cache = "last" })

    rewrite_static = pvm.phase("moonlift_open_rewrite_static", {
        [Tr.StaticItem] = function(self, set) return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) })) end,
        [Tr.StaticItemOpen] = function(self, set) return pvm.once(pvm.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) })) end,
    }, { args_cache = "last" })

    rewrite_type_decl = pvm.phase("moonlift_open_rewrite_type_decl", {
        [Tr.TypeDeclStruct] = function(self, set) local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { ty = one(rewrite_type, self.fields[i].ty, set) }) end; return pvm.once(pvm.with(self, { fields = fields })) end,
        [Tr.TypeDeclUnion] = function(self, set) local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { ty = one(rewrite_type, self.fields[i].ty, set) }) end; return pvm.once(pvm.with(self, { fields = fields })) end,
        [Tr.TypeDeclEnumSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclTaggedUnionSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclOpenStruct] = function(self, set) local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { ty = one(rewrite_type, self.fields[i].ty, set) }) end; return pvm.once(pvm.with(self, { fields = fields })) end,
        [Tr.TypeDeclOpenUnion] = function(self, set) local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { ty = one(rewrite_type, self.fields[i].ty, set) }) end; return pvm.once(pvm.with(self, { fields = fields })) end,
    }, { args_cache = "last" })

    rewrite_item = pvm.phase("moonlift_open_rewrite_item", {
        [Tr.ItemFunc] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(pvm.with(self, { func = one(rewrite_func, self.func, set) })) end,
        [Tr.ItemExtern] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(pvm.with(self, { func = one(rewrite_extern, self.func, set) })) end,
        [Tr.ItemConst] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(pvm.with(self, { c = one(rewrite_const, self.c, set) })) end,
        [Tr.ItemStatic] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(pvm.with(self, { s = one(rewrite_static, self.s, set) })) end,
        [Tr.ItemImport] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(self) end,
        [Tr.ItemType] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(pvm.with(self, { t = one(rewrite_type_decl, self.t, set) })) end,
        [Tr.ItemUseTypeDeclSlot] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(self) end,
        [Tr.ItemUseItemsSlot] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(self) end,
        [Tr.ItemUseModule] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(pvm.with(self, { module = one(rewrite_module, self.module, set) })) end,
        [Tr.ItemUseModuleSlot] = function(self, set) local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return pvm.children(function(item) return pvm.once(item) end, targets) end; return pvm.once(self) end,
    }, { args_cache = "last" })

    rewrite_module = pvm.phase("moonlift_open_rewrite_module", {
        [Tr.Module] = function(module, set) return pvm.once(pvm.with(module, { items = rewrite_items(module.items, set) })) end,
    }, { args_cache = "last" })

    local function empty_set()
        return O.RewriteSet({})
    end

    return {
        empty_set = empty_set,
        rewrite_type = rewrite_type,
        rewrite_binding = rewrite_binding,
        rewrite_place = rewrite_place,
        rewrite_domain = rewrite_domain,
        rewrite_expr = rewrite_expr,
        rewrite_stmt = rewrite_stmt,
        rewrite_item = rewrite_item,
        rewrite_module = rewrite_module,
        type = function(ty, set) return one(rewrite_type, ty, set or empty_set()) end,
        expr = function(expr, set) return one(rewrite_expr, expr, set or empty_set()) end,
        stmts = function(stmts, set) return rewrite_stmts(stmts, set or empty_set()) end,
        item_stream = function(item, set) return rewrite_item(item, set or empty_set()) end,
        module = function(module, set) return one(rewrite_module, module, set or empty_set()) end,
    }
end

return M
