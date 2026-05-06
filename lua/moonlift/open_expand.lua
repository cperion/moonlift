local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Ty = T.MoonType
    local O = T.MoonOpen
    local B = T.MoonBind
    local Tr = T.MoonTree

    local lookup_slot_value
    local lookup_param_value
    local lookup_region_frag
    local lookup_expr_frag
    local expand_type
    local expand_open_set
    local expand_expr_header
    local expand_place_header
    local expand_stmt_header
    local expand_module_header
    local expand_value_ref_expr
    local expand_value_ref
    local expand_binding
    local expand_place
    local expand_expr
    local expand_stmt
    local expand_view
    local expand_domain
    local expand_index_base
    local expand_control_stmt_region
    local expand_control_expr_region
    local expand_func
    local expand_extern
    local expand_const
    local expand_static
    local expand_type_decl
    local expand_item
    local expand_module

    local function slot_value(slot, env)
        local bindings = env.fills.bindings
        for i = #bindings, 1, -1 do
            local binding = bindings[i]
            if binding.slot == slot then
                return binding.value
            end
        end
        return nil
    end

    local function open_empty(open)
        return #open.value_imports == 0 and #open.type_imports == 0 and #open.layouts == 0 and #open.slots == 0
    end

    local function one(phase, node, env)
        return pvm.one(phase(node, env))
    end

    local function maybe_expr_from_value_ref(ref, h, env)
        local values = pvm.drain(expand_value_ref_expr(ref, h, env))
        if #values == 0 then
            return nil
        end
        return values[1]
    end

    local function expand_types(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = one(expand_type, xs[i], env)
        end
        return out
    end

    local function expand_exprs(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = one(expand_expr, xs[i], env)
        end
        return out
    end

    local function expand_stmts(xs, env)
        local out = {}
        for i = 1, #xs do
            local g, p, c = expand_stmt(xs[i], env)
            pvm.drain_into(g, p, c, out)
        end
        return out
    end

    local function expand_jump_args(xs, env)
        local out = {}
        for i = 1, #xs do out[#out + 1] = pvm.with(xs[i], { value = one(expand_expr, xs[i].value, env) }) end
        return out
    end

    local function expand_items(xs, env)
        local out = {}
        for i = 1, #xs do
            local g, p, c = expand_item(xs[i], env)
            pvm.drain_into(g, p, c, out)
        end
        return out
    end

    local function merge_fills(env, fills)
        local merged = {}
        for i = 1, #env.fills.bindings do merged[#merged + 1] = env.fills.bindings[i] end
        for i = 1, #fills do merged[#merged + 1] = fills[i] end
        return O.ExpandEnv(env.region_frags, env.expr_frags, O.FillSet(merged), env.conts, env.params, env.rebase_prefix)
    end

    local function env_with_params(env, params)
        local merged = {}
        for i = 1, #env.params do merged[#merged + 1] = env.params[i] end
        for i = 1, #params do merged[#merged + 1] = params[i] end
        return O.ExpandEnv(env.region_frags, env.expr_frags, env.fills, env.conts, merged, env.rebase_prefix)
    end

    local function env_with_conts(env, conts)
        local merged = {}
        for i = 1, #env.conts do merged[#merged + 1] = env.conts[i] end
        for i = 1, #conts do merged[#merged + 1] = conts[i] end
        return O.ExpandEnv(env.region_frags, env.expr_frags, env.fills, merged, env.params, env.rebase_prefix)
    end

    local function env_at_path(env, path)
        return O.ExpandEnv(env.region_frags, env.expr_frags, env.fills, env.conts, env.params, path)
    end

    local function env_with_fills_conts_and_params(env, fills, conts, params)
        return env_with_params(env_with_conts(merge_fills(env, fills), conts), params)
    end

    local function env_with_fills_and_params(env, fills, params)
        return env_with_fills_conts_and_params(env, fills, {}, params)
    end

    local function frag_param_bindings(params, args, env)
        local out = {}
        local n = #params
        if #args < n then n = #args end
        for i = 1, n do
            out[#out + 1] = O.ParamBinding(params[i], one(expand_expr, args[i], env))
        end
        return out
    end

    lookup_slot_value = pvm.phase("moonlift_open_lookup_slot_value", {
        [O.SlotType] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotValue] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotExpr] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotPlace] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotDomain] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotRegion] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotCont] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotFunc] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotConst] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotStatic] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotTypeDecl] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotItems] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotModule] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotRegionFrag] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotExprFrag] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
        [O.SlotName] = function(self, env)
            local v = slot_value(self, env)
            if v == nil then return pvm.empty() end
            return pvm.once(v)
        end,
    }, { args_cache = "last" })

    lookup_param_value = pvm.phase("moonlift_open_lookup_param_value", function(param, env)
        for i = #env.params, 1, -1 do
            local binding = env.params[i]
            if binding.param == param then
                return binding.value
            end
        end
        return pvm.NIL
    end, { args_cache = "last" })

    lookup_region_frag = function(name, env)
        for i = #env.region_frags, 1, -1 do
            local fn = env.region_frags[i].name
            -- Resolve NameRef to plain string for comparison.
            if type(fn) ~= "string" then
                local cls = pvm.classof(fn)
                if cls == O.NameRefText then fn = fn.text end
            end
            if fn == name then return env.region_frags[i] end
        end
        return pvm.NIL
    end

    lookup_expr_frag = function(name, env)
        for i = #env.expr_frags, 1, -1 do
            local fn = env.expr_frags[i].name
            if type(fn) ~= "string" then
                local cls = pvm.classof(fn)
                if cls == O.NameRefText then fn = fn.text end
            end
            if fn == name then return env.expr_frags[i] end
        end
        return pvm.NIL
    end

    -- Resolve a RegionFragRef to a RegionFrag ASDL node, or pvm.NIL.
    local function lookup_region_frag_ref(ref, env)
        local cls = pvm.classof(ref)
        if cls == O.RegionFragRefName then
            return lookup_region_frag(ref.name, env)
        elseif cls == O.RegionFragRefSlot then
            local values = pvm.drain(lookup_slot_value(O.SlotRegionFrag(ref.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueRegionFrag then
                return values[1].frag
            end
        end
        return pvm.NIL
    end

    -- Resolve an ExprFragRef to an ExprFrag ASDL node, or pvm.NIL.
    local function lookup_expr_frag_ref(ref, env)
        local cls = pvm.classof(ref)
        if cls == O.ExprFragRefName then
            return lookup_expr_frag(ref.name, env)
        elseif cls == O.ExprFragRefSlot then
            local values = pvm.drain(lookup_slot_value(O.SlotExprFrag(ref.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueExprFrag then
                return values[1].frag
            end
        end
        return pvm.NIL
    end

    -- Resolve a NameRef to a concrete string.  If unresolved, returns nil.
    local function name_text(ref, env)
        local cls = pvm.classof(ref)
        if cls == O.NameRefText then return ref.text end
        if cls == O.NameRefSlot then
            local values = pvm.drain(lookup_slot_value(O.SlotName(ref.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueName then
                return values[1].text
            end
        end
        return nil
    end

    expand_name_ref = pvm.phase("moonlift_open_expand_name_ref", {
        [O.NameRefText] = function(self) return pvm.once(self) end,
        [O.NameRefSlot] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotName(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueName then
                return pvm.once(O.NameRefText(values[1].text))
            end
            return pvm.once(self)
        end,
    }, { args_cache = "last" })

    expand_type = pvm.phase("moonlift_open_expand_type", {
        [Ty.TScalar] = function(self) return pvm.once(self) end,
        [Ty.TPtr] = function(self, env) return pvm.once(pvm.with(self, { elem = one(expand_type, self.elem, env) })) end,
        [Ty.TArray] = function(self, env) return pvm.once(pvm.with(self, { elem = one(expand_type, self.elem, env) })) end,
        [Ty.TSlice] = function(self, env) return pvm.once(pvm.with(self, { elem = one(expand_type, self.elem, env) })) end,
        [Ty.TView] = function(self, env) return pvm.once(pvm.with(self, { elem = one(expand_type, self.elem, env) })) end,
        [Ty.TFunc] = function(self, env) return pvm.once(pvm.with(self, { params = expand_types(self.params, env), result = one(expand_type, self.result, env) })) end,
        [Ty.TClosure] = function(self, env) return pvm.once(pvm.with(self, { params = expand_types(self.params, env), result = one(expand_type, self.result, env) })) end,
        [Ty.TNamed] = function(self) return pvm.once(self) end,
        [Ty.TSlot] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotType(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueType then
                return expand_type(values[1].ty, env)
            end
            return pvm.once(self)
        end,
    }, { args_cache = "last" })

    expand_open_set = pvm.phase("moonlift_open_expand_open_set", {
        [O.OpenSet] = function(open, env)
            local slots = {}
            for i = 1, #open.slots do
                if #pvm.drain(lookup_slot_value(open.slots[i], env)) == 0 then
                    slots[#slots + 1] = open.slots[i]
                end
            end
            return pvm.once(O.OpenSet(open.value_imports, open.type_imports, open.layouts, slots))
        end,
    }, { args_cache = "last" })

    expand_expr_header = pvm.phase("moonlift_open_expand_expr_header", {
        [Tr.ExprSurface] = function(self) return pvm.once(self) end,
        [Tr.ExprTyped] = function(self, env) return pvm.once(pvm.with(self, { ty = one(expand_type, self.ty, env) })) end,
        [Tr.ExprOpen] = function(self, env)
            local ty = one(expand_type, self.ty, env)
            local open = one(expand_open_set, self.open, env)
            if open_empty(open) then return pvm.once(Tr.ExprTyped(ty)) end
            return pvm.once(Tr.ExprOpen(ty, open))
        end,
        [Tr.ExprSem] = function(self, env) return pvm.once(pvm.with(self, { ty = one(expand_type, self.ty, env) })) end,
        [Tr.ExprCode] = function(self, env) return pvm.once(pvm.with(self, { ty = one(expand_type, self.ty, env) })) end,
    }, { args_cache = "last" })

    expand_place_header = pvm.phase("moonlift_open_expand_place_header", {
        [Tr.PlaceSurface] = function(self) return pvm.once(self) end,
        [Tr.PlaceTyped] = function(self, env) return pvm.once(pvm.with(self, { ty = one(expand_type, self.ty, env) })) end,
        [Tr.PlaceOpen] = function(self, env)
            local ty = one(expand_type, self.ty, env)
            local open = one(expand_open_set, self.open, env)
            if open_empty(open) then return pvm.once(Tr.PlaceTyped(ty)) end
            return pvm.once(Tr.PlaceOpen(ty, open))
        end,
        [Tr.PlaceSem] = function(self, env) return pvm.once(pvm.with(self, { ty = one(expand_type, self.ty, env) })) end,
    }, { args_cache = "last" })

    expand_stmt_header = pvm.phase("moonlift_open_expand_stmt_header", {
        [Tr.StmtSurface] = function(self) return pvm.once(self) end,
        [Tr.StmtTyped] = function(self) return pvm.once(self) end,
        [Tr.StmtOpen] = function(self, env)
            local open = one(expand_open_set, self.open, env)
            if open_empty(open) then return pvm.once(Tr.StmtTyped) end
            return pvm.once(Tr.StmtOpen(open))
        end,
        [Tr.StmtSem] = function(self) return pvm.once(self) end,
        [Tr.StmtCode] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    expand_module_header = pvm.phase("moonlift_open_expand_module_header", {
        [Tr.ModuleSurface] = function(self) return pvm.once(self) end,
        [Tr.ModuleTyped] = function(self) return pvm.once(self) end,
        [Tr.ModuleOpen] = function(self, env)
            local open = one(expand_open_set, self.open, env)
            if self.name ~= O.ModuleNameOpen and open_empty(open) then
                return pvm.once(Tr.ModuleTyped(self.name.module_name))
            end
            return pvm.once(Tr.ModuleOpen(self.name, open))
        end,
        [Tr.ModuleSem] = function(self) return pvm.once(self) end,
        [Tr.ModuleCode] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    expand_binding = pvm.phase("moonlift_open_expand_binding", {
        [B.Binding] = function(self, env)
            return pvm.once(pvm.with(self, { ty = one(expand_type, self.ty, env) }))
        end,
    }, { args_cache = "last" })

    expand_value_ref_expr = pvm.phase("moonlift_open_expand_value_ref_expr", {
        [B.ValueRefBinding] = function(self, h, env)
            local cls = pvm.classof(self.binding.class)
            if cls == B.BindingClassOpenParam then
                local v = pvm.one(lookup_param_value(self.binding.class.param, env))
                if v ~= pvm.NIL then return expand_expr(v, env) end
            end
            return pvm.empty()
        end,
        [B.ValueRefSlot] = function(self, h, env)
            local values = pvm.drain(lookup_slot_value(O.SlotValue(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueExpr then
                return expand_expr(values[1].expr, env)
            end
            return pvm.empty()
        end,
        [B.ValueRefName] = function() return pvm.empty() end,
        [B.ValueRefPath] = function() return pvm.empty() end,
        [B.ValueRefFuncSlot] = function() return pvm.empty() end,
        [B.ValueRefConstSlot] = function() return pvm.empty() end,
        [B.ValueRefStaticSlot] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    expand_value_ref = pvm.phase("moonlift_open_expand_value_ref", {
        [B.ValueRefBinding] = function(self, env) return pvm.once(pvm.with(self, { binding = one(expand_binding, self.binding, env) })) end,
        [B.ValueRefName] = function(self) return pvm.once(self) end,
        [B.ValueRefPath] = function(self) return pvm.once(self) end,
        [B.ValueRefSlot] = function(self) return pvm.once(self) end,
        [B.ValueRefFuncSlot] = function(self) return pvm.once(self) end,
        [B.ValueRefConstSlot] = function(self) return pvm.once(self) end,
        [B.ValueRefStaticSlot] = function(self) return pvm.once(self) end,
    }, { args_cache = "last" })

    expand_view = pvm.phase("moonlift_open_expand_view", {
        [Tr.ViewFromExpr] = function(self, env) return pvm.once(pvm.with(self, { base = one(expand_expr, self.base, env), elem = one(expand_type, self.elem, env) })) end,
        [Tr.ViewContiguous] = function(self, env) return pvm.once(pvm.with(self, { data = one(expand_expr, self.data, env), elem = one(expand_type, self.elem, env), len = one(expand_expr, self.len, env) })) end,
        [Tr.ViewStrided] = function(self, env) return pvm.once(pvm.with(self, { data = one(expand_expr, self.data, env), elem = one(expand_type, self.elem, env), len = one(expand_expr, self.len, env), stride = one(expand_expr, self.stride, env) })) end,
        [Tr.ViewRestrided] = function(self, env) return pvm.once(pvm.with(self, { base = one(expand_view, self.base, env), elem = one(expand_type, self.elem, env), stride = one(expand_expr, self.stride, env) })) end,
        [Tr.ViewWindow] = function(self, env) return pvm.once(pvm.with(self, { base = one(expand_view, self.base, env), start = one(expand_expr, self.start, env), len = one(expand_expr, self.len, env) })) end,
        [Tr.ViewRowBase] = function(self, env) return pvm.once(pvm.with(self, { base = one(expand_view, self.base, env), row_offset = one(expand_expr, self.row_offset, env), elem = one(expand_type, self.elem, env) })) end,
        [Tr.ViewInterleaved] = function(self, env) return pvm.once(pvm.with(self, { data = one(expand_expr, self.data, env), elem = one(expand_type, self.elem, env), len = one(expand_expr, self.len, env), stride = one(expand_expr, self.stride, env), lane = one(expand_expr, self.lane, env) })) end,
        [Tr.ViewInterleavedView] = function(self, env) return pvm.once(pvm.with(self, { base = one(expand_view, self.base, env), elem = one(expand_type, self.elem, env), stride = one(expand_expr, self.stride, env), lane = one(expand_expr, self.lane, env) })) end,
    }, { args_cache = "last" })

    expand_domain = pvm.phase("moonlift_open_expand_domain", {
        [Tr.DomainRange] = function(self, env) return pvm.once(pvm.with(self, { stop = one(expand_expr, self.stop, env) })) end,
        [Tr.DomainRange2] = function(self, env) return pvm.once(pvm.with(self, { start = one(expand_expr, self.start, env), stop = one(expand_expr, self.stop, env) })) end,
        [Tr.DomainZipEqValues] = function(self, env) return pvm.once(pvm.with(self, { values = expand_exprs(self.values, env) })) end,
        [Tr.DomainValue] = function(self, env) return pvm.once(pvm.with(self, { value = one(expand_expr, self.value, env) })) end,
        [Tr.DomainView] = function(self, env) return pvm.once(pvm.with(self, { view = one(expand_view, self.view, env) })) end,
        [Tr.DomainZipEqViews] = function(self, env)
            local views = {}
            for i = 1, #self.views do views[#views + 1] = one(expand_view, self.views[i], env) end
            return pvm.once(pvm.with(self, { views = views }))
        end,
        [Tr.DomainSlotValue] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotDomain(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueDomain then
                return expand_domain(values[1].domain, env)
            end
            return pvm.once(self)
        end,
    }, { args_cache = "last" })

    expand_index_base = pvm.phase("moonlift_open_expand_index_base", {
        [Tr.IndexBaseExpr] = function(self, env) return pvm.once(pvm.with(self, { base = one(expand_expr, self.base, env) })) end,
        [Tr.IndexBasePlace] = function(self, env) return pvm.once(pvm.with(self, { base = one(expand_place, self.base, env), elem = one(expand_type, self.elem, env) })) end,
        [Tr.IndexBaseView] = function(self, env) return pvm.once(pvm.with(self, { view = one(expand_view, self.view, env) })) end,
    }, { args_cache = "last" })

    expand_place = pvm.phase("moonlift_open_expand_place", {
        [Tr.PlaceRef] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_place_header, self.h, env), ref = one(expand_value_ref, self.ref, env) })) end,
        [Tr.PlaceDeref] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_place_header, self.h, env), base = one(expand_expr, self.base, env) })) end,
        [Tr.PlaceDot] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_place_header, self.h, env), base = one(expand_place, self.base, env) })) end,
        [Tr.PlaceField] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_place_header, self.h, env), base = one(expand_place, self.base, env) })) end,
        [Tr.PlaceIndex] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_place_header, self.h, env), base = one(expand_index_base, self.base, env), index = one(expand_expr, self.index, env) })) end,
        [Tr.PlaceSlotValue] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotPlace(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValuePlace then
                return expand_place(values[1].place, env)
            end
            return pvm.once(pvm.with(self, { h = one(expand_place_header, self.h, env) }))
        end,
    }, { args_cache = "last" })

    local function label_map_for_frag(frag, use_id)
        local map = {}
        local prefix = use_id .. "."
        map[frag.entry.label.name] = Tr.BlockLabel(prefix .. frag.entry.label.name)
        for i = 1, #frag.blocks do
            map[frag.blocks[i].label.name] = Tr.BlockLabel(prefix .. frag.blocks[i].label.name)
        end
        return map
    end

    local function rebase_label(label, map)
        return map[label.name] or label
    end

    local function runtime_param_name(name)
        return "__rt_" .. name
    end

    local function runtime_param_expr(name)
        return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(runtime_param_name(name)))
    end

    local function runtime_block_params(frag, env)
        local out = {}
        for i = 1, #frag.params do out[#out + 1] = Tr.BlockParam(runtime_param_name(frag.params[i].name), one(expand_type, frag.params[i].ty, env)) end
        return out
    end

    local function runtime_jump_args_from_names(frag, captures)
        local out = {}
        for i = 1, #frag.params do out[#out + 1] = Tr.JumpArg(runtime_param_name(frag.params[i].name), runtime_param_expr(frag.params[i].name)) end
        for i = 1, #(captures or {}) do out[#out + 1] = Tr.JumpArg(captures[i].name, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(captures[i].name))) end
        return out
    end

    local function prepend_runtime_args(args, frag, captures)
        local out = runtime_jump_args_from_names(frag, captures)
        for i = 1, #args do out[#out + 1] = args[i] end
        return out
    end

    local function rebase_stmts(stmts, map, frag, captures)
        local out = {}
        for i = 1, #stmts do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtJump then
                local target = rebase_label(stmt.target, map)
                local args = map[stmt.target.name] and prepend_runtime_args(stmt.args, frag, captures) or stmt.args
                out[#out + 1] = pvm.with(stmt, { target = target, args = args })
            elseif cls == Tr.StmtIf then
                out[#out + 1] = pvm.with(stmt, { then_body = rebase_stmts(stmt.then_body, map, frag, captures), else_body = rebase_stmts(stmt.else_body, map, frag, captures) })
            elseif cls == Tr.StmtSwitch then
                local arms = {}
                for j = 1, #stmt.arms do arms[#arms + 1] = pvm.with(stmt.arms[j], { body = rebase_stmts(stmt.arms[j].body, map, frag, captures) }) end
                out[#out + 1] = pvm.with(stmt, { arms = arms, default_body = rebase_stmts(stmt.default_body, map, frag, captures) })
            else
                out[#out + 1] = stmt
            end
        end
        return out
    end

    local expand_region_stmts

    local function rebase_control_block_body(block, map, frag, captures)
        return pvm.with(block, { body = rebase_stmts(block.body, map, frag, captures) })
    end

    local function expr_ref_name(expr)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefName then return expr.ref.name end
        return nil
    end

    local function capture_runtime_params(frag, env)
        local seen, params, args = {}, {}, {}
        for i = 1, #frag.params do seen[runtime_param_name(frag.params[i].name)] = true end
        for i = 1, #env.params do
            local binding = env.params[i]
            local name = expr_ref_name(binding.value)
            if name ~= nil and name:match("^__rt_") and not seen[name] then
                seen[name] = true
                params[#params + 1] = Tr.BlockParam(name, one(expand_type, binding.param.ty, env))
                args[#args + 1] = Tr.JumpArg(name, binding.value)
            end
        end
        return params, args
    end

    local function append_all(dst, src)
        for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
        return dst
    end

    local function cont_slot_by_name(frag, name)
        for i = 1, #frag.conts do
            if frag.conts[i].pretty_name == name then return frag.conts[i] end
        end
        return nil
    end

    local function instantiate_cont_fills(frag, cont_fills)
        local out = {}
        for i = 1, #(cont_fills or {}) do
            local fill = cont_fills[i]
            local slot = cont_slot_by_name(frag, fill.name)
            if slot ~= nil then out[#out + 1] = O.ContBinding(slot.key, fill.target) end
        end
        return out
    end

    local function resolve_cont_target(slot, env, seen)
        seen = seen or {}
        if seen[slot.key] then return nil end
        seen[slot.key] = true
        for i = #env.conts, 1, -1 do
            local binding = env.conts[i]
            if binding.name == slot.key then
                local target = binding.target
                local cls = pvm.classof(target)
                if cls == O.ContTargetLabel then return target
                elseif cls == O.ContTargetSlot then return resolve_cont_target(target.slot, env, seen) or target end
            end
        end
        return nil
    end

    local function expand_region_frag_use(stmt, env)
        local frag = lookup_region_frag_ref(stmt.frag, env)
        if frag == pvm.NIL then
            return pvm.with(stmt, { h = one(expand_stmt_header, stmt.h, env), args = expand_exprs(stmt.args, env) }), {}
        end
        local child_path = (env.rebase_prefix ~= "" and (env.rebase_prefix .. ".") or "") .. stmt.use_id
        local runtime_param_bindings = {}
        for i = 1, #frag.params do runtime_param_bindings[#runtime_param_bindings + 1] = O.ParamBinding(frag.params[i], runtime_param_expr(frag.params[i].name)) end
        local cont_bindings = instantiate_cont_fills(frag, stmt.cont_fills)
        local local_env = env_at_path(env_with_fills_conts_and_params(env, stmt.fills, cont_bindings, runtime_param_bindings), child_path)
        local init_env = env_at_path(env_with_fills_conts_and_params(env, stmt.fills, cont_bindings, frag_param_bindings(frag.params, stmt.args, env)), child_path)
        local map = label_map_for_frag(frag, child_path)
        local capture_params, capture_args = capture_runtime_params(frag, env)
        local entry_params, entry_args = append_all(runtime_block_params(frag, local_env), capture_params), {}
        for i = 1, #frag.params do
            entry_args[#entry_args + 1] = Tr.JumpArg(runtime_param_name(frag.params[i].name), one(expand_expr, stmt.args[i], env))
        end
        append_all(entry_args, capture_args)
        for i = 1, #frag.entry.params do
            local p = frag.entry.params[i]
            entry_params[#entry_params + 1] = Tr.BlockParam(p.name, one(expand_type, p.ty, local_env))
            entry_args[#entry_args + 1] = Tr.JumpArg(p.name, one(expand_expr, p.init, init_env))
        end
        local entry_body, entry_nested = expand_region_stmts(frag.entry.body, local_env)
        local entry_body2 = expand_stmts(rebase_stmts(entry_body, map, frag, capture_params), local_env)
        local blocks = {
            Tr.ControlBlock(map[frag.entry.label.name], entry_params, entry_body2)
        }
        for i = 1, #entry_nested do blocks[#blocks + 1] = rebase_control_block_body(entry_nested[i], map, frag, capture_params) end
        for i = 1, #frag.blocks do
            local block = frag.blocks[i]
            local params = append_all(runtime_block_params(frag, local_env), capture_params)
            for j = 1, #block.params do params[#params + 1] = pvm.with(block.params[j], { ty = one(expand_type, block.params[j].ty, local_env) }) end
            local block_body, block_nested = expand_region_stmts(block.body, local_env)
            local block_body2 = expand_stmts(rebase_stmts(block_body, map, frag, capture_params), local_env)
            blocks[#blocks + 1] = Tr.ControlBlock(map[block.label.name], params, block_body2)
            for j = 1, #block_nested do blocks[#blocks + 1] = rebase_control_block_body(block_nested[j], map, frag, capture_params) end
        end
        return Tr.StmtJump(one(expand_stmt_header, stmt.h, env), map[frag.entry.label.name], entry_args), blocks
    end

    expand_region_stmts = function(stmts, env)
        local body, blocks = {}, {}
        for i = 1, #stmts do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtUseRegionFrag then
                local jump, more_blocks = expand_region_frag_use(stmt, env)
                body[#body + 1] = jump
                for j = 1, #more_blocks do blocks[#blocks + 1] = more_blocks[j] end
            elseif cls == Tr.StmtIf then
                local then_body, then_blocks = expand_region_stmts(stmt.then_body, env)
                local else_body, else_blocks = expand_region_stmts(stmt.else_body, env)
                body[#body + 1] = pvm.with(stmt, { h = one(expand_stmt_header, stmt.h, env), cond = one(expand_expr, stmt.cond, env), then_body = then_body, else_body = else_body })
                for j = 1, #then_blocks do blocks[#blocks + 1] = then_blocks[j] end
                for j = 1, #else_blocks do blocks[#blocks + 1] = else_blocks[j] end
            elseif cls == Tr.StmtSwitch then
                local arms = {}
                for j = 1, #stmt.arms do
                    local arm_body, arm_blocks = expand_region_stmts(stmt.arms[j].body, env)
                    arms[#arms + 1] = pvm.with(stmt.arms[j], { body = arm_body })
                    for k = 1, #arm_blocks do blocks[#blocks + 1] = arm_blocks[k] end
                end
                local default_body, default_blocks = expand_region_stmts(stmt.default_body, env)
                body[#body + 1] = pvm.with(stmt, { h = one(expand_stmt_header, stmt.h, env), value = one(expand_expr, stmt.value, env), arms = arms, default_body = default_body })
                for j = 1, #default_blocks do blocks[#blocks + 1] = default_blocks[j] end
            else
                local g, p, c = expand_stmt(stmt, env)
                pvm.drain_into(g, p, c, body)
            end
        end
        return body, blocks
    end

    local function expand_entry_block(block, env)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = pvm.with(block.params[i], { ty = one(expand_type, block.params[i].ty, env), init = one(expand_expr, block.params[i].init, env) }) end
        local body, blocks = expand_region_stmts(block.body, env)
        return pvm.with(block, { params = params, body = body }), blocks
    end

    local function expand_control_block(block, env)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = pvm.with(block.params[i], { ty = one(expand_type, block.params[i].ty, env) }) end
        local body, blocks = expand_region_stmts(block.body, env)
        return pvm.with(block, { params = params, body = body }), blocks
    end

    expand_control_stmt_region = pvm.phase("moonlift_open_expand_control_stmt_region", {
        [Tr.ControlStmtRegion] = function(self, env)
            local entry, entry_blocks = expand_entry_block(self.entry, env)
            local blocks = {}; for i = 1, #entry_blocks do blocks[#blocks + 1] = entry_blocks[i] end
            for i = 1, #self.blocks do local block, more = expand_control_block(self.blocks[i], env); blocks[#blocks + 1] = block; for j = 1, #more do blocks[#blocks + 1] = more[j] end end
            return pvm.once(pvm.with(self, { entry = entry, blocks = blocks }))
        end,
    }, { args_cache = "last" })

    expand_control_expr_region = pvm.phase("moonlift_open_expand_control_expr_region", {
        [Tr.ControlExprRegion] = function(self, env)
            local entry, entry_blocks = expand_entry_block(self.entry, env)
            local blocks = {}; for i = 1, #entry_blocks do blocks[#blocks + 1] = entry_blocks[i] end
            for i = 1, #self.blocks do local block, more = expand_control_block(self.blocks[i], env); blocks[#blocks + 1] = block; for j = 1, #more do blocks[#blocks + 1] = more[j] end end
            return pvm.once(pvm.with(self, { result_ty = one(expand_type, self.result_ty, env), entry = entry, blocks = blocks }))
        end,
    }, { args_cache = "last" })

    expand_expr = pvm.phase("moonlift_open_expand_expr", {
        [Tr.ExprLit] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env) })) end,
        [Tr.ExprRef] = function(self, env)
            local replacement = maybe_expr_from_value_ref(self.ref, self.h, env)
            if replacement ~= nil then return pvm.once(replacement) end
            return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ref = one(expand_value_ref, self.ref, env) }))
        end,
        [Tr.ExprDot] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), base = one(expand_expr, self.base, env) })) end,
        [Tr.ExprUnary] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.ExprBinary] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), lhs = one(expand_expr, self.lhs, env), rhs = one(expand_expr, self.rhs, env) })) end,
        [Tr.ExprCompare] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), lhs = one(expand_expr, self.lhs, env), rhs = one(expand_expr, self.rhs, env) })) end,
        [Tr.ExprLogic] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), lhs = one(expand_expr, self.lhs, env), rhs = one(expand_expr, self.rhs, env) })) end,
        [Tr.ExprCast] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.ExprMachineCast] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.ExprIntrinsic] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), args = expand_exprs(self.args, env) })) end,
        [Tr.ExprAddrOf] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), place = one(expand_place, self.place, env) })) end,
        [Tr.ExprDeref] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.ExprCall] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), args = expand_exprs(self.args, env) })) end,
        [Tr.ExprLen] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.ExprField] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), base = one(expand_expr, self.base, env) })) end,
        [Tr.ExprIndex] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), base = one(expand_index_base, self.base, env), index = one(expand_expr, self.index, env) })) end,
        [Tr.ExprAgg] = function(self, env)
            local fields = {}
            for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { value = one(expand_expr, self.fields[i].value, env) }) end
            return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), fields = fields }))
        end,
        [Tr.ExprArray] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), elem_ty = one(expand_type, self.elem_ty, env), elems = expand_exprs(self.elems, env) })) end,
        [Tr.ExprIf] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), cond = one(expand_expr, self.cond, env), then_expr = one(expand_expr, self.then_expr, env), else_expr = one(expand_expr, self.else_expr, env) })) end,
        [Tr.ExprSelect] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), cond = one(expand_expr, self.cond, env), then_expr = one(expand_expr, self.then_expr, env), else_expr = one(expand_expr, self.else_expr, env) })) end,
        [Tr.ExprSwitch] = function(self, env)
            local arms = {}
            for i = 1, #self.arms do arms[#arms + 1] = pvm.with(self.arms[i], { body = expand_stmts(self.arms[i].body, env), result = one(expand_expr, self.arms[i].result, env) }) end
            return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env), arms = arms, default_expr = one(expand_expr, self.default_expr, env) }))
        end,
        [Tr.ExprControl] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), region = one(expand_control_expr_region, self.region, env) })) end,
        [Tr.ExprBlock] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), stmts = expand_stmts(self.stmts, env), result = one(expand_expr, self.result, env) })) end,
        [Tr.ExprClosure] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), body = expand_stmts(self.body, env) })) end,
        [Tr.ExprView] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), view = one(expand_view, self.view, env) })) end,
        [Tr.ExprLoad] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env) })) end,
        [Tr.ExprSlotValue] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotExpr(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueExpr then
                return expand_expr(values[1].expr, env)
            end
            return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env) }))
        end,
        [Tr.ExprUseExprFrag] = function(self, env)
            local frag = lookup_expr_frag_ref(self.frag, env)
            if frag == pvm.NIL then
                return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), args = expand_exprs(self.args, env) }))
            end
            local local_env = env_with_fills_and_params(env, self.fills, frag_param_bindings(frag.params, self.args, env))
            return expand_expr(frag.body, local_env)
        end,
    }, { args_cache = "last" })

    expand_stmt = pvm.phase("moonlift_open_expand_stmt", {
        [Tr.StmtLet] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), binding = one(expand_binding, self.binding, env), init = one(expand_expr, self.init, env) })) end,
        [Tr.StmtVar] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), binding = one(expand_binding, self.binding, env), init = one(expand_expr, self.init, env) })) end,
        [Tr.StmtSet] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), place = one(expand_place, self.place, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.StmtExpr] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), expr = one(expand_expr, self.expr, env) })) end,
        [Tr.StmtAssert] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), cond = one(expand_expr, self.cond, env) })) end,
        [Tr.StmtIf] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), cond = one(expand_expr, self.cond, env), then_body = expand_stmts(self.then_body, env), else_body = expand_stmts(self.else_body, env) })) end,
        [Tr.StmtSwitch] = function(self, env)
            local arms = {}
            for i = 1, #self.arms do arms[#arms + 1] = pvm.with(self.arms[i], { body = expand_stmts(self.arms[i].body, env) }) end
            local var_arms = {}
            for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = pvm.with(self.variant_arms[i], { binds = self.variant_arms[i].binds, body = expand_stmts(self.variant_arms[i].body, env) }) end
            return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), value = one(expand_expr, self.value, env), arms = arms, variant_arms = var_arms, default_body = expand_stmts(self.default_body, env) }))
        end,
        [Tr.StmtJump] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), args = expand_jump_args(self.args, env) })) end,
        [Tr.StmtJumpCont] = function(self, env)
            local args = expand_jump_args(self.args, env)
            local target = resolve_cont_target(self.slot, env)
            if target ~= nil then
                local cls = pvm.classof(target)
                if cls == O.ContTargetLabel then
                    return pvm.once(Tr.StmtJump(one(expand_stmt_header, self.h, env), target.label, args))
                elseif cls == O.ContTargetSlot then
                    return pvm.once(Tr.StmtJumpCont(one(expand_stmt_header, self.h, env), target.slot, args))
                end
            end
            return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), args = args }))
        end,
        [Tr.StmtYieldVoid] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env) })) end,
        [Tr.StmtYieldValue] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.StmtReturnVoid] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env) })) end,
        [Tr.StmtReturnValue] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.StmtControl] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), region = one(expand_control_stmt_region, self.region, env) })) end,
        [Tr.StmtUseRegionSlot] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotRegion(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueRegion then
                return pvm.children(function(stmt) return expand_stmt(stmt, env) end, values[1].body)
            end
            return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env) }))
        end,
        [Tr.StmtUseRegionFrag] = function(self, env)
            return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), args = expand_exprs(self.args, env) }))
        end,
    }, { args_cache = "last" })

    expand_func = pvm.phase("moonlift_open_expand_func", {
        [Tr.FuncLocal] = function(self, env)
            local params = {}
            for i = 1, #self.params do params[i] = pvm.with(self.params[i], { ty = one(expand_type, self.params[i].ty, env) }) end
            return pvm.once(pvm.with(self, { params = params, result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
        end,
        [Tr.FuncExport] = function(self, env)
            local params = {}
            for i = 1, #self.params do params[i] = pvm.with(self.params[i], { ty = one(expand_type, self.params[i].ty, env) }) end
            return pvm.once(pvm.with(self, { params = params, result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
        end,
        [Tr.FuncLocalContract] = function(self, env)
            local params = {}
            for i = 1, #self.params do params[i] = pvm.with(self.params[i], { ty = one(expand_type, self.params[i].ty, env) }) end
            return pvm.once(pvm.with(self, { params = params, result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
        end,
        [Tr.FuncExportContract] = function(self, env)
            local params = {}
            for i = 1, #self.params do params[i] = pvm.with(self.params[i], { ty = one(expand_type, self.params[i].ty, env) }) end
            return pvm.once(pvm.with(self, { params = params, result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
        end,
        [Tr.FuncOpen] = function(self, env)
            local local_env = merge_fills(env, {})
            return pvm.once(pvm.with(self, { open = one(expand_open_set, self.open, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, local_env) }))
        end,
    }, { args_cache = "last" })

    expand_extern = pvm.phase("moonlift_open_expand_extern", {
        [Tr.ExternFunc] = function(self, env)
            local params = {}
            for i = 1, #self.params do params[i] = pvm.with(self.params[i], { ty = one(expand_type, self.params[i].ty, env) }) end
            return pvm.once(pvm.with(self, { params = params, result = one(expand_type, self.result, env) }))
        end,
        [Tr.ExternFuncOpen] = function(self, env) return pvm.once(pvm.with(self, { result = one(expand_type, self.result, env) })) end,
    }, { args_cache = "last" })

    expand_const = pvm.phase("moonlift_open_expand_const", {
        [Tr.ConstItem] = function(self, env) return pvm.once(pvm.with(self, { ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.ConstItemOpen] = function(self, env) return pvm.once(pvm.with(self, { open = one(expand_open_set, self.open, env), ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) })) end,
    }, { args_cache = "last" })

    expand_static = pvm.phase("moonlift_open_expand_static", {
        [Tr.StaticItem] = function(self, env) return pvm.once(pvm.with(self, { ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.StaticItemOpen] = function(self, env) return pvm.once(pvm.with(self, { open = one(expand_open_set, self.open, env), ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) })) end,
    }, { args_cache = "last" })

    expand_type_decl = pvm.phase("moonlift_open_expand_type_decl", {
        [Tr.TypeDeclStruct] = function(self, env)
            local fields = {}
            for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { ty = one(expand_type, self.fields[i].ty, env) }) end
            return pvm.once(pvm.with(self, { fields = fields }))
        end,
        [Tr.TypeDeclUnion] = function(self, env)
            local fields = {}
            for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { ty = one(expand_type, self.fields[i].ty, env) }) end
            return pvm.once(pvm.with(self, { fields = fields }))
        end,
        [Tr.TypeDeclEnumSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclTaggedUnionSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclOpenStruct] = function(self, env)
            local fields = {}
            for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { ty = one(expand_type, self.fields[i].ty, env) }) end
            return pvm.once(pvm.with(self, { fields = fields }))
        end,
        [Tr.TypeDeclOpenUnion] = function(self, env)
            local fields = {}
            for i = 1, #self.fields do fields[#fields + 1] = pvm.with(self.fields[i], { ty = one(expand_type, self.fields[i].ty, env) }) end
            return pvm.once(pvm.with(self, { fields = fields }))
        end,
    }, { args_cache = "last" })

    expand_item = pvm.phase("moonlift_open_expand_item", {
        [Tr.ItemFunc] = function(self, env) return pvm.once(pvm.with(self, { func = one(expand_func, self.func, env) })) end,
        [Tr.ItemExtern] = function(self, env) return pvm.once(pvm.with(self, { func = one(expand_extern, self.func, env) })) end,
        [Tr.ItemConst] = function(self, env) return pvm.once(pvm.with(self, { c = one(expand_const, self.c, env) })) end,
        [Tr.ItemStatic] = function(self, env) return pvm.once(pvm.with(self, { s = one(expand_static, self.s, env) })) end,
        [Tr.ItemImport] = function(self) return pvm.once(self) end,
        [Tr.ItemType] = function(self, env) return pvm.once(pvm.with(self, { t = one(expand_type_decl, self.t, env) })) end,
        [Tr.ItemUseTypeDeclSlot] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotTypeDecl(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueTypeDecl then
                return pvm.once(Tr.ItemType(one(expand_type_decl, values[1].t, env)))
            end
            return pvm.once(self)
        end,
        [Tr.ItemUseItemsSlot] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotItems(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueItems then
                return pvm.children(function(item) return expand_item(item, env) end, values[1].items)
            end
            return pvm.once(self)
        end,
        [Tr.ItemUseModule] = function(self, env)
            local local_env = merge_fills(env, self.fills)
            local module = one(expand_module, self.module, local_env)
            return pvm.children(function(item) return pvm.once(item) end, module.items)
        end,
        [Tr.ItemUseModuleSlot] = function(self, env)
            local values = pvm.drain(lookup_slot_value(O.SlotModule(self.slot), env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueModule then
                local local_env = merge_fills(env, self.fills)
                local module = one(expand_module, values[1].module, local_env)
                return pvm.children(function(item) return pvm.once(item) end, module.items)
            end
            return pvm.once(self)
        end,
    }, { args_cache = "last" })

    expand_module = pvm.phase("moonlift_open_expand_module", {
        [Tr.Module] = function(module, env)
            return pvm.once(pvm.with(module, { h = one(expand_module_header, module.h, env), items = expand_items(module.items, env) }))
        end,
    }, { args_cache = "last" })

    local function list_from_map_or_list(xs)
        local out = {}
        if xs == nil then return out end
        if #xs > 0 then for i = 1, #xs do out[#out + 1] = xs[i] end; return out end
        for _, v in pairs(xs) do
            if type(v) == "table" and v.frag ~= nil then out[#out + 1] = v.frag else out[#out + 1] = v end
        end
        return out
    end

    local function empty_env(region_frags, expr_frags)
        return O.ExpandEnv(
            list_from_map_or_list(region_frags or T._moonlift_host_region_frags),
            list_from_map_or_list(expr_frags or T._moonlift_host_expr_frags),
            O.FillSet({}), {}, {}, "")
    end

    return {
        empty_env = empty_env,
        lookup_slot_value = lookup_slot_value,
        lookup_param_value = lookup_param_value,
        lookup_region_frag = lookup_region_frag,
        lookup_expr_frag = lookup_expr_frag,
        env_with_frags = empty_env,
        env_with_fills = function(env, bindings) return merge_fills(env, bindings) end,
        -- Expand a standalone RegionFrag (resolves type/expr slots in its
        -- params, body, and blocks using the given env, but does NOT inline
        -- nested emit uses — those are resolved later at use sites).
        expand_region_frag = function(frag, env)
            local params = {}
            for i = 1, #frag.params do
                local p = frag.params[i]
                params[i] = O.OpenParam(p.key, p.name, one(expand_type, p.ty, env))
            end
            local conts = {}
            for i = 1, #frag.conts do
                local c = frag.conts[i]
                local cparams = {}
                for j = 1, #c.params do
                    cparams[j] = Tr.BlockParam(c.params[j].name, one(expand_type, c.params[j].ty, env))
                end
                conts[i] = O.ContSlot(c.key, c.pretty_name, cparams)
            end
            local eparams = {}
            for i = 1, #frag.entry.params do
                local p = frag.entry.params[i]
                eparams[i] = Tr.EntryBlockParam(p.name, one(expand_type, p.ty, env), one(expand_expr, p.init, env))
            end
            local ebody = expand_stmts(frag.entry.body, env)
            local entry = Tr.EntryControlBlock(frag.entry.label, eparams, ebody)
            local blocks = {}
            for i = 1, #frag.blocks do
                local b = frag.blocks[i]
                local bparams = {}
                for j = 1, #b.params do
                    bparams[j] = Tr.BlockParam(b.params[j].name, one(expand_type, b.params[j].ty, env))
                end
                blocks[i] = Tr.ControlBlock(b.label, bparams, expand_stmts(b.body, env))
            end
            local resolved_name = name_text(frag.name, env) or "<unresolved>"
            return O.RegionFrag(O.NameRefText(resolved_name), params, conts, frag.open, entry, blocks)
        end,
        -- Expand a standalone ExprFrag (resolves type/expr slots).
        expand_expr_frag = function(frag, env)
            local params = {}
            for i = 1, #frag.params do
                local p = frag.params[i]
                params[i] = O.OpenParam(p.key, p.name, one(expand_type, p.ty, env))
            end
            local body   = one(expand_expr, frag.body, env)
            local result = one(expand_type, frag.result, env)
            local resolved_name = name_text(frag.name, env) or "<unresolved>"
            return O.ExprFrag(O.NameRefText(resolved_name), params, frag.open, body, result)
        end,
        expand_name_ref = expand_name_ref,
        expand_module = function(module, env) return one(expand_module, module, env or empty_env()) end,
        expand_type = expand_type,
        expand_open_set = expand_open_set,
        expand_expr = expand_expr,
        expand_stmt = expand_stmt,
        expand_item = expand_item,
        type = function(ty, env) return one(expand_type, ty, env or empty_env()) end,
        expr = function(expr, env) return one(expand_expr, expr, env or empty_env()) end,
        stmts = function(stmts, env) return expand_stmts(stmts, env or empty_env()) end,
        item_stream = function(item, env) return expand_item(item, env or empty_env()) end,
        module = function(module, env) return one(expand_module, module, env or empty_env()) end,
    }
end

return M
