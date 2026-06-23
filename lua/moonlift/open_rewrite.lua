local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

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
        for i = 1, #xs do out[#out + 1] = schema.with(xs[i], { value = one(rewrite_expr, xs[i].value, set) }) end
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

    function type_rule_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.RewriteType) then
            return (function(self, value)
 if self.from == value then return erased.once(self.to) end return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteBinding) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewritePlace) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteDomain) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteExpr) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteStmt) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteItem) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_type_rule_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function binding_rule_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.RewriteBinding) then
            return (function(self, value)
 if self.from == value then return erased.once(self.to) end return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteType) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewritePlace) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteDomain) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteExpr) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteStmt) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteItem) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_binding_rule_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function place_rule_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.RewritePlace) then
            return (function(self, value)
 if self.from == value then return erased.once(self.to) end return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteType) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteBinding) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteDomain) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteExpr) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteStmt) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteItem) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_place_rule_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function domain_rule_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.RewriteDomain) then
            return (function(self, value)
 if self.from == value then return erased.once(self.to) end return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteType) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteBinding) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewritePlace) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteExpr) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteStmt) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteItem) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_domain_rule_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expr_rule_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.RewriteExpr) then
            return (function(self, value)
 if self.from == value then return erased.once(self.to) end return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteType) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteBinding) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewritePlace) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteDomain) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteStmt) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteItem) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_expr_rule_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function stmt_rule_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.RewriteStmt) then
            return (function(self, value)
 if self.from == value then return erased.children(function(stmt) return erased.once(stmt) end, self.to) end return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteType) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteBinding) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewritePlace) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteDomain) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteExpr) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteItem) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_stmt_rule_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function item_rule_target(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.RewriteItem) then
            return (function(self, value)
 if self.from == value then return erased.children(function(item) return erased.once(item) end, self.to) end return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteType) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteBinding) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewritePlace) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteDomain) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteExpr) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, O.RewriteStmt) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_item_rule_target: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TScalar) then
            return (function(self, set)
 return erased.once(first_target(type_rule_target, set, self) or self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TPtr) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { elem = one(rewrite_type, self.elem, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TArray) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { elem = one(rewrite_type, self.elem, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TSlice) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { elem = one(rewrite_type, self.elem, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TView) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { elem = one(rewrite_type, self.elem, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TLease) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_type, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TOwned) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_type, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TAccess) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_type, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.THandle) then
            return (function(self, set)
 return erased.once(first_target(type_rule_target, set, self) or self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TFunc) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { params = rewrite_types(self.params, set), result = one(rewrite_type, self.result, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TClosure) then
            return (function(self, set)
 local t = first_target(type_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { params = rewrite_types(self.params, set), result = one(rewrite_type, self.result, set) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TNamed) then
            return (function(self, set)
 return erased.once(first_target(type_rule_target, set, self) or self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TSlot) then
            return (function(self, set)
 return erased.once(first_target(type_rule_target, set, self) or self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TCType) then
            return (function(self, set)
 return erased.once(first_target(type_rule_target, set, self) or self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TCFuncPtr) then
            return (function(self, set)
 return erased.once(first_target(type_rule_target, set, self) or self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_binding(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.Binding) then
            return (function(self, set)

            local t = first_target(binding_rule_target, set, self)
            if t then return erased.once(t) end
            return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_binding: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_value_ref(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(self, set)
 return erased.once(schema.with(self, { binding = one(rewrite_binding, self.binding, set) }))
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefHole) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_value_ref: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_view(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ViewFromExpr) then
            return (function(self, set)
 return erased.once(schema.with(self, { base = one(rewrite_expr, self.base, set), elem = one(rewrite_type, self.elem, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewContiguous) then
            return (function(self, set)
 return erased.once(schema.with(self, { data = one(rewrite_expr, self.data, set), elem = one(rewrite_type, self.elem, set), len = one(rewrite_expr, self.len, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewStrided) then
            return (function(self, set)
 return erased.once(schema.with(self, { data = one(rewrite_expr, self.data, set), elem = one(rewrite_type, self.elem, set), len = one(rewrite_expr, self.len, set), stride = one(rewrite_expr, self.stride, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewRestrided) then
            return (function(self, set)
 return erased.once(schema.with(self, { base = one(rewrite_view, self.base, set), elem = one(rewrite_type, self.elem, set), stride = one(rewrite_expr, self.stride, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewWindow) then
            return (function(self, set)
 return erased.once(schema.with(self, { base = one(rewrite_view, self.base, set), start = one(rewrite_expr, self.start, set), len = one(rewrite_expr, self.len, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewRowBase) then
            return (function(self, set)
 return erased.once(schema.with(self, { base = one(rewrite_view, self.base, set), row_offset = one(rewrite_expr, self.row_offset, set), elem = one(rewrite_type, self.elem, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewInterleaved) then
            return (function(self, set)
 return erased.once(schema.with(self, { data = one(rewrite_expr, self.data, set), elem = one(rewrite_type, self.elem, set), len = one(rewrite_expr, self.len, set), stride = one(rewrite_expr, self.stride, set), lane = one(rewrite_expr, self.lane, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewInterleavedView) then
            return (function(self, set)
 return erased.once(schema.with(self, { base = one(rewrite_view, self.base, set), elem = one(rewrite_type, self.elem, set), stride = one(rewrite_expr, self.stride, set), lane = one(rewrite_expr, self.lane, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_view: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_domain(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.DomainRange) then
            return (function(self, set)
 local t = first_target(domain_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { stop = one(rewrite_expr, self.stop, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainRange2) then
            return (function(self, set)
 local t = first_target(domain_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { start = one(rewrite_expr, self.start, set), stop = one(rewrite_expr, self.stop, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainZipEqValues) then
            return (function(self, set)
 local t = first_target(domain_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { values = rewrite_exprs(self.values, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainValue) then
            return (function(self, set)
 local t = first_target(domain_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainView) then
            return (function(self, set)
 local t = first_target(domain_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { view = one(rewrite_view, self.view, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainZipEqViews) then
            return (function(self, set)
 local t = first_target(domain_rule_target, set, self); if t then return erased.once(t) end; local views = {}; for i = 1, #self.views do views[#views + 1] = one(rewrite_view, self.views[i], set) end; return erased.once(schema.with(self, { views = views }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainSlotValue) then
            return (function(self, set)
 return erased.once(first_target(domain_rule_target, set, self) or self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_domain: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_index_base(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.IndexBaseExpr) then
            return (function(self, set)
 return erased.once(schema.with(self, { base = one(rewrite_expr, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBasePlace) then
            return (function(self, set)
 return erased.once(schema.with(self, { base = one(rewrite_place, self.base, set), elem = one(rewrite_type, self.elem, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBaseView) then
            return (function(self, set)
 return erased.once(schema.with(self, { view = one(rewrite_view, self.view, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_index_base: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_place(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceRef) then
            return (function(self, set)
 local t = first_target(place_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { ref = one(rewrite_value_ref, self.ref, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDeref) then
            return (function(self, set)
 local t = first_target(place_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_expr, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self, set)
 local t = first_target(place_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_place, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceField) then
            return (function(self, set)
 local t = first_target(place_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_place, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceIndex) then
            return (function(self, set)
 local t = first_target(place_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_index_base, self.base, set), index = one(rewrite_expr, self.index, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceSlotValue) then
            return (function(self, set)
 return erased.once(first_target(place_rule_target, set, self) or self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_place: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function rewrite_entry_block(block, set)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = schema.with(block.params[i], { ty = one(rewrite_type, block.params[i].ty, set), init = one(rewrite_expr, block.params[i].init, set) }) end
        return schema.with(block, { params = params, body = rewrite_stmts(block.body, set) })
    end

    local function rewrite_control_block(block, set)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = schema.with(block.params[i], { ty = one(rewrite_type, block.params[i].ty, set) }) end
        return schema.with(block, { params = params, body = rewrite_stmts(block.body, set) })
    end

    function rewrite_control_stmt_region(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlStmtRegion) then
            return (function(self, set)

            local blocks = {}; for i = 1, #self.blocks do blocks[#blocks + 1] = rewrite_control_block(self.blocks[i], set) end
            return erased.once(schema.with(self, { entry = rewrite_entry_block(self.entry, set), blocks = blocks }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_control_stmt_region: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_control_expr_region(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlExprRegion) then
            return (function(self, set)

            local blocks = {}; for i = 1, #self.blocks do blocks[#blocks + 1] = rewrite_control_block(self.blocks[i], set) end
            return erased.once(schema.with(self, { result_ty = one(rewrite_type, self.result_ty, set), entry = rewrite_entry_block(self.entry, set), blocks = blocks }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_control_expr_region: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_expr(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprLit) then
            return (function(self, set)
 return erased.once(first_target(expr_rule_target, set, self) or self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprRef) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { ref = one(rewrite_value_ref, self.ref, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_expr, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { lhs = one(rewrite_expr, self.lhs, set), rhs = one(rewrite_expr, self.rhs, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { lhs = one(rewrite_expr, self.lhs, set), rhs = one(rewrite_expr, self.rhs, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { lhs = one(rewrite_expr, self.lhs, set), rhs = one(rewrite_expr, self.rhs, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { args = rewrite_exprs(self.args, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { place = one(rewrite_place, self.place, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { args = rewrite_exprs(self.args, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLen) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_expr, self.base, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { base = one(rewrite_index_base, self.base, set), index = one(rewrite_expr, self.index, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = schema.with(self.fields[i], { value = one(rewrite_expr, self.fields[i].value, set) }) end; return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), fields = fields }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCtor) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { args = rewrite_exprs(self.args, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { elem_ty = one(rewrite_type, self.elem_ty, set), elems = rewrite_exprs(self.elems, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { cond = one(rewrite_expr, self.cond, set), then_expr = one(rewrite_expr, self.then_expr, set), else_expr = one(rewrite_expr, self.else_expr, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { cond = one(rewrite_expr, self.cond, set), then_expr = one(rewrite_expr, self.then_expr, set), else_expr = one(rewrite_expr, self.else_expr, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = schema.with(self.arms[i], { body = rewrite_stmts(self.arms[i].body, set), result = one(rewrite_expr, self.arms[i].result, set) }) end; local var_arms = {}; for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = schema.with(self.variant_arms[i], { body = rewrite_stmts(self.variant_arms[i].body, set), result = one(rewrite_expr, self.variant_arms[i].result, set) }) end; return erased.once(schema.with(self, { value = one(rewrite_expr, self.value, set), arms = arms, variant_arms = var_arms, default_body = rewrite_stmts(self.default_body or {}, set), default_expr = one(rewrite_expr, self.default_expr, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { region = one(rewrite_control_expr_region, self.region, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { stmts = rewrite_stmts(self.stmts, set), result = one(rewrite_expr, self.result, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { body = rewrite_stmts(self.body, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { view = one(rewrite_view, self.view, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), addr = one(rewrite_expr, self.addr, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicLoad) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), addr = one(rewrite_expr, self.addr, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicRmw) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), addr = one(rewrite_expr, self.addr, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicCas) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), addr = one(rewrite_expr, self.addr, set), expected = one(rewrite_expr, self.expected, set), replacement = one(rewrite_expr, self.replacement, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSlotValue) then
            return (function(self, set)
 return erased.once(first_target(expr_rule_target, set, self) or self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUseExprFrag) then
            return (function(self, set)
 local t = first_target(expr_rule_target, set, self); if t then return erased.once(t) end; return erased.once(schema.with(self, { args = rewrite_exprs(self.args, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_expr: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_stmt(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtLet) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { binding = one(rewrite_binding, self.binding, set), init = one(rewrite_expr, self.init, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { binding = one(rewrite_binding, self.binding, set), init = one(rewrite_expr, self.init, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { place = one(rewrite_place, self.place, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), addr = one(rewrite_expr, self.addr, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { expr = one(rewrite_expr, self.expr, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { cond = one(rewrite_expr, self.cond, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { cond = one(rewrite_expr, self.cond, set), then_body = rewrite_stmts(self.then_body, set), else_body = rewrite_stmts(self.else_body, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; local arms = {}; for i = 1, #self.arms do arms[#arms + 1] = schema.with(self.arms[i], { body = rewrite_stmts(self.arms[i].body, set) }) end; local var_arms = {}; for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = schema.with(self.variant_arms[i], { body = rewrite_stmts(self.variant_arms[i].body, set) }) end; return erased.once(schema.with(self, { value = one(rewrite_expr, self.value, set), arms = arms, variant_arms = var_arms, default_body = rewrite_stmts(self.default_body, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJump) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { args = rewrite_jump_args(self.args, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJumpCont) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { args = rewrite_jump_args(self.args, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { region = one(rewrite_control_stmt_region, self.region, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function(self, set)
 local targets = rule_targets(stmt_rule_target, set, self); if #targets > 0 then return erased.children(function(stmt) return erased.once(stmt) end, targets) end; return erased.once(schema.with(self, { args = rewrite_exprs(self.args, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_stmt: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_func(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.FuncLocal) then
            return (function(self, set)
 return erased.once(schema.with(self, { body = rewrite_stmts(self.body, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExport) then
            return (function(self, set)
 return erased.once(schema.with(self, { body = rewrite_stmts(self.body, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncLocalContract) then
            return (function(self, set)
 return erased.once(schema.with(self, { body = rewrite_stmts(self.body, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExportContract) then
            return (function(self, set)
 return erased.once(schema.with(self, { body = rewrite_stmts(self.body, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncOpen) then
            return (function(self, set)
 return erased.once(schema.with(self, { result = one(rewrite_type, self.result, set), body = rewrite_stmts(self.body, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_func: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_extern(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExternFunc) then
            return (function(self, set)
 return erased.once(schema.with(self, { result = one(rewrite_type, self.result, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExternFuncOpen) then
            return (function(self, set)
 return erased.once(schema.with(self, { result = one(rewrite_type, self.result, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_extern: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ConstItem) then
            return (function(self, set)
 return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ConstItemOpen) then
            return (function(self, set)
 return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_const: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_static(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StaticItem) then
            return (function(self, set)
 return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StaticItemOpen) then
            return (function(self, set)
 return erased.once(schema.with(self, { ty = one(rewrite_type, self.ty, set), value = one(rewrite_expr, self.value, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_static: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_type_decl(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.TypeDeclStruct) then
            return (function(self, set)
 local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = schema.with(self.fields[i], { ty = one(rewrite_type, self.fields[i].ty, set) }) end; return erased.once(schema.with(self, { fields = fields }))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclUnion) then
            return (function(self, set)
 local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = schema.with(self.fields[i], { ty = one(rewrite_type, self.fields[i].ty, set) }) end; return erased.once(schema.with(self, { fields = fields }))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclEnumSugar) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclTaggedUnionSugar) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclHandle) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclOpenStruct) then
            return (function(self, set)
 local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = schema.with(self.fields[i], { ty = one(rewrite_type, self.fields[i].ty, set) }) end; return erased.once(schema.with(self, { fields = fields }))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclOpenUnion) then
            return (function(self, set)
 local fields = {}; for i = 1, #self.fields do fields[#fields + 1] = schema.with(self.fields[i], { ty = one(rewrite_type, self.fields[i].ty, set) }) end; return erased.once(schema.with(self, { fields = fields }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_type_decl: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_item(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ItemFunc) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(schema.with(self, { func = one(rewrite_func, self.func, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExtern) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(schema.with(self, { func = one(rewrite_extern, self.func, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemConst) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(schema.with(self, { c = one(rewrite_const, self.c, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemStatic) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(schema.with(self, { s = one(rewrite_static, self.s, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemImport) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemType) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(schema.with(self, { t = one(rewrite_type_decl, self.t, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemRegionFrag) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExprFrag) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseTypeDeclSlot) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseItemsSlot) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModule) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(schema.with(self, { module = one(rewrite_module, self.module, set) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModuleSlot) then
            return (function(self, set)
 local targets = rule_targets(item_rule_target, set, self); if #targets > 0 then return erased.children(function(item) return erased.once(item) end, targets) end; return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_item: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function rewrite_module(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.Module) then
            return (function(module, set)
 return erased.once(schema.with(module, { items = rewrite_items(module.items, set) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_rewrite_module: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

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
