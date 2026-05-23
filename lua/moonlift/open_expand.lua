local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Ty = T.MoonType
    local O = T.MoonOpen
    local B = T.MoonBind
    local Sem = T.MoonSem
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

    local function spread_region_slot(role, name)
        local prefix = "__moonlift_spread_" .. role .. ":"
        if type(name) ~= "string" or name:sub(1, #prefix) ~= prefix then return nil end
        local key = name:sub(#prefix + 1)
        local pretty = key:match("([^:]+)$") or key
        return O.RegionSlot(key, pretty)
    end

    local function expand_types(xs, env)
        local out = {}
        for i = 1, #xs do
            local x = xs[i]
            if pvm.classof(x) == Ty.TSlot then
                local values = pvm.drain(lookup_slot_value(O.SlotType(x.slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueTypes then
                    for j = 1, #values[1].types do out[#out + 1] = one(expand_type, values[1].types[j], env) end
                else
                    out[#out + 1] = one(expand_type, x, env)
                end
            else
                out[#out + 1] = one(expand_type, x, env)
            end
        end
        return out
    end

    local function expand_exprs(xs, env)
        local out = {}
        for i = 1, #xs do
            local x = xs[i]
            if pvm.classof(x) == Tr.ExprSlotValue then
                local values = pvm.drain(lookup_slot_value(O.SlotExpr(x.slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueExprs then
                    for j = 1, #values[1].exprs do out[#out + 1] = one(expand_expr, values[1].exprs[j], env) end
                else
                    out[#out + 1] = one(expand_expr, x, env)
                end
            else
                out[#out + 1] = one(expand_expr, x, env)
            end
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

    local function expand_params(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_region_slot("param_list", xs[i].name)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueParams then
                    for j = 1, #values[1].params do
                        local p = values[1].params[j]
                        out[#out + 1] = pvm.with(p, { ty = one(expand_type, p.ty, env) })
                    end
                else
                    out[#out + 1] = pvm.with(xs[i], { ty = one(expand_type, xs[i].ty, env) })
                end
            else
                out[#out + 1] = pvm.with(xs[i], { ty = one(expand_type, xs[i].ty, env) })
            end
        end
        return out
    end

    local function expand_fields(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_region_slot("field_list", xs[i].field_name)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueFields then
                    for j = 1, #values[1].fields do
                        local f = values[1].fields[j]
                        out[#out + 1] = pvm.with(f, { ty = one(expand_type, f.ty, env) })
                    end
                else
                    out[#out + 1] = pvm.with(xs[i], { ty = one(expand_type, xs[i].ty, env) })
                end
            else
                out[#out + 1] = pvm.with(xs[i], { ty = one(expand_type, xs[i].ty, env) })
            end
        end
        return out
    end

    local function expand_variants(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_region_slot("variant_list", xs[i].name)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueVariants then
                    for j = 1, #values[1].variants do
                        local v = values[1].variants[j]
                        out[#out + 1] = Ty.VariantDecl(v.name, one(expand_type, v.payload, env), expand_fields(v.fields, env))
                    end
                else
                    out[#out + 1] = Ty.VariantDecl(xs[i].name, one(expand_type, xs[i].payload, env), expand_fields(xs[i].fields, env))
                end
            else
                out[#out + 1] = Ty.VariantDecl(xs[i].name, one(expand_type, xs[i].payload, env), expand_fields(xs[i].fields, env))
            end
        end
        return out
    end

    local function spread_slot_from_switch_key(role, key)
        if key ~= nil and key ~= "" then return spread_region_slot(role, key) end
        return nil
    end

    local function expand_open_params(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_region_slot("open_param_list", xs[i].name)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueOpenParams then
                    for j = 1, #values[1].params do
                        local p = values[1].params[j]
                        out[#out + 1] = O.OpenParam(p.key, p.name, one(expand_type, p.ty, env))
                    end
                else
                    out[#out + 1] = O.OpenParam(xs[i].key, xs[i].name, one(expand_type, xs[i].ty, env))
                end
            else
                out[#out + 1] = O.OpenParam(xs[i].key, xs[i].name, one(expand_type, xs[i].ty, env))
            end
        end
        return out
    end

    local function expand_block_params(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_region_slot("block_param_list", xs[i].name)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueBlockParams then
                    for j = 1, #values[1].params do
                        local p = values[1].params[j]
                        out[#out + 1] = Tr.BlockParam(p.name, one(expand_type, p.ty, env))
                    end
                else
                    out[#out + 1] = Tr.BlockParam(xs[i].name, one(expand_type, xs[i].ty, env))
                end
            else
                out[#out + 1] = Tr.BlockParam(xs[i].name, one(expand_type, xs[i].ty, env))
            end
        end
        return out
    end

    local function expand_entry_params(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_region_slot("entry_param_list", xs[i].name)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueEntryParams then
                    for j = 1, #values[1].params do
                        local p = values[1].params[j]
                        out[#out + 1] = Tr.EntryBlockParam(p.name, one(expand_type, p.ty, env), one(expand_expr, p.init, env))
                    end
                else
                    out[#out + 1] = Tr.EntryBlockParam(xs[i].name, one(expand_type, xs[i].ty, env), one(expand_expr, xs[i].init, env))
                end
            else
                out[#out + 1] = Tr.EntryBlockParam(xs[i].name, one(expand_type, xs[i].ty, env), one(expand_expr, xs[i].init, env))
            end
        end
        return out
    end

    local function expand_cont_slots(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_region_slot("cont_slot_list", xs[i].pretty_name)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueContSlots then
                    for j = 1, #values[1].conts do
                        local c = values[1].conts[j]
                        out[#out + 1] = O.ContSlot(c.key, c.pretty_name, expand_block_params(c.params, env))
                    end
                else
                    out[#out + 1] = O.ContSlot(xs[i].key, xs[i].pretty_name, expand_block_params(xs[i].params, env))
                end
            else
                out[#out + 1] = O.ContSlot(xs[i].key, xs[i].pretty_name, expand_block_params(xs[i].params, env))
            end
        end
        return out
    end

    local function expand_control_blocks(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_region_slot("control_block_list", xs[i].label.name)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueControlBlocks then
                    for j = 1, #values[1].blocks do
                        local b = values[1].blocks[j]
                        out[#out + 1] = Tr.ControlBlock(b.label, expand_block_params(b.params, env), expand_stmts(b.body, env))
                    end
                end
            else
                out[#out + 1] = Tr.ControlBlock(xs[i].label, expand_block_params(xs[i].params, env), expand_stmts(xs[i].body, env))
            end
        end
        return out
    end

    local function expand_switch_key(key, env)
        return key
    end

    local function expand_switch_stmt_arms(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_slot_from_switch_key("switch_stmt_arm_list", xs[i].raw_key)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueSwitchStmtArms then
                    for j = 1, #values[1].arms do
                        local a = values[1].arms[j]
                        out[#out + 1] = pvm.with(a, { raw_key = expand_switch_key(a.raw_key, env), body = expand_stmts(a.body, env) })
                    end
                end
            else
                out[#out + 1] = pvm.with(xs[i], { raw_key = expand_switch_key(xs[i].raw_key, env), body = expand_stmts(xs[i].body, env) })
            end
        end
        return out
    end

    local function expand_switch_expr_arms(xs, env)
        local out = {}
        for i = 1, #xs do
            local slot = spread_slot_from_switch_key("switch_expr_arm_list", xs[i].raw_key)
            if slot then
                local values = pvm.drain(lookup_slot_value(O.SlotRegion(slot), env))
                if #values == 1 and pvm.classof(values[1]) == O.SlotValueSwitchExprArms then
                    for j = 1, #values[1].arms do
                        local a = values[1].arms[j]
                        out[#out + 1] = pvm.with(a, { raw_key = expand_switch_key(a.raw_key, env), body = expand_stmts(a.body, env), result = one(expand_expr, a.result, env) })
                    end
                end
            else
                out[#out + 1] = pvm.with(xs[i], { raw_key = expand_switch_key(xs[i].raw_key, env), body = expand_stmts(xs[i].body, env), result = one(expand_expr, xs[i].result, env) })
            end
        end
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

        -- Legacy SlotCont fills are accepted only when the fill slot is
        -- actually a continuation slot.  Do not promote arbitrary fill slots
        -- into continuation bindings: region emit cont_fills are already
        -- represented directly in `conts`, and broad promotion can create
        -- inner-cont -> outer-cont -> inner-cont cycles for direct routing
        -- such as `next = next`.
        for i = 1, #env.fills.bindings do
            local binding = env.fills.bindings[i]
            if pvm.classof(binding.slot) == O.SlotCont then
                local key = binding.slot.slot.key
                local v = binding.value
                local vcls = pvm.classof(v)
                if vcls == O.SlotValueCont then
                    merged[#merged + 1] = O.ContBinding(key, O.ContTargetLabel(v.label))
                elseif vcls == O.SlotValueContSlot and v.slot.key ~= key then
                    merged[#merged + 1] = O.ContBinding(key, O.ContTargetSlot(v.slot))
                end
            end
        end
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
    }, { args_cache = "last" })

    expand_stmt_header = pvm.phase("moonlift_open_expand_stmt_header", {
        [Tr.StmtSurface] = function(self) return pvm.once(self) end,
        [Tr.StmtOpen] = function(self, env)
            local open = one(expand_open_set, self.open, env)
            if open_empty(open) then return pvm.once(Tr.StmtSurface) end
            return pvm.once(Tr.StmtOpen(open))
        end,
        [Tr.StmtFlow] = function(self) return pvm.once(self) end,
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
        [B.ValueRefHole] = function(self, h, env)
            local values = pvm.drain(lookup_slot_value(self.slot, env))
            if #values == 1 and pvm.classof(values[1]) == O.SlotValueExpr then
                return expand_expr(values[1].expr, env)
            end
            return pvm.empty()
        end,
        [B.ValueRefName] = function() return pvm.empty() end,
        [B.ValueRefPath] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    expand_value_ref = pvm.phase("moonlift_open_expand_value_ref", {
        [B.ValueRefBinding] = function(self, env) return pvm.once(pvm.with(self, { binding = one(expand_binding, self.binding, env) })) end,
        [B.ValueRefName] = function(self) return pvm.once(self) end,
        [B.ValueRefPath] = function(self) return pvm.once(self) end,
        [B.ValueRefHole] = function(self) return pvm.once(self) end,
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
        [Tr.PlaceRef] = function(self, env)
            local h = one(expand_place_header, self.h, env)
            local replacement = maybe_expr_from_value_ref(self.ref, h, env)
            if replacement ~= nil and pvm.classof(replacement) == Tr.ExprRef then
                return pvm.once(Tr.PlaceRef(h, replacement.ref))
            end
            return pvm.once(pvm.with(self, { h = h, ref = one(expand_value_ref, self.ref, env) }))
        end,
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

    local function resolve_cont_target(slot, env)
        local original_key = slot.key
        local current = slot
        local seen = {}
        while true do
            if seen[current.key] then return nil end
            seen[current.key] = true

            local target = nil
            for i = #env.conts, 1, -1 do
                local binding = env.conts[i]
                if binding.name == current.key then
                    target = binding.target
                    break
                end
            end
            if target == nil then
                if current.key == original_key then return nil end
                return O.ContTargetSlot(current)
            end

            local cls = pvm.classof(target)
            if cls == O.ContTargetLabel then return target end
            if cls == O.ContTargetSlot then
                if seen[target.slot.key] then
                    -- A cycle means a direct continuation route was rebound
                    -- back through the current environment.  Collapse to the
                    -- last non-cycling slot when possible; leave true
                    -- self-cycles unresolved so expansion remains finite.
                    if current.key ~= original_key then return O.ContTargetSlot(current) end
                    return nil
                end
                current = target.slot
            else
                return nil
            end
        end
    end

    -- Region emit composition is handled by region_normal_form.lua.
    -- open_expand still owns value/type/name expansion; RNF owns CFG import,
    -- alpha-renaming, continuation routing, and block hoisting.

    local rnf = require("moonlift.region_normal_form").Define(T, {
        expand_type = function(ty, env) return one(expand_type, ty, env) end,
        expand_expr = function(expr, env) return one(expand_expr, expr, env) end,
        expand_stmt_header = function(h, env) return one(expand_stmt_header, h, env) end,
        expand_stmt = function(stmt, env) return expand_stmt(stmt, env) end,
        expand_stmts = expand_stmts,
        expand_switch_stmt_arms = expand_switch_stmt_arms,
        lookup_region_frag_ref = lookup_region_frag_ref,
        env_at_path = env_at_path,
        env_with_fills_conts_and_params = env_with_fills_conts_and_params,
        frag_param_bindings = frag_param_bindings,
    })

    expand_control_stmt_region = pvm.phase("moonlift_open_expand_control_stmt_region", {
        [Tr.ControlStmtRegion] = function(self, env)
            return pvm.once(rnf.control_stmt_region(self, env))
        end,
    }, { args_cache = "last" })

    expand_control_expr_region = pvm.phase("moonlift_open_expand_control_expr_region", {
        [Tr.ControlExprRegion] = function(self, env)
            return pvm.once(rnf.control_expr_region(self, env))
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
        [Tr.ExprCall] = function(self, env)
            return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), callee = one(expand_expr, self.callee, env), args = expand_exprs(self.args, env) }))
        end,
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
            return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env), arms = expand_switch_expr_arms(self.arms, env), default_body = expand_stmts(self.default_body or {}, env), default_expr = one(expand_expr, self.default_expr, env) }))
        end,
        [Tr.ExprControl] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), region = one(expand_control_expr_region, self.region, env) })) end,
        [Tr.ExprBlock] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), stmts = expand_stmts(self.stmts, env), result = one(expand_expr, self.result, env) })) end,
        [Tr.ExprClosure] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) })) end,
        [Tr.ExprView] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), view = one(expand_view, self.view, env) })) end,
        [Tr.ExprLoad] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env) })) end,
        [Tr.ExprAtomicLoad] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env) })) end,
        [Tr.ExprAtomicRmw] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.ExprAtomicCas] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env), expected = one(expand_expr, self.expected, env), replacement = one(expand_expr, self.replacement, env) })) end,
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
        [Tr.StmtAtomicStore] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env), value = one(expand_expr, self.value, env) })) end,
        [Tr.StmtAtomicFence] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env) })) end,
        [Tr.StmtExpr] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), expr = one(expand_expr, self.expr, env) })) end,
        [Tr.StmtAssert] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), cond = one(expand_expr, self.cond, env) })) end,
        [Tr.StmtIf] = function(self, env) return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), cond = one(expand_expr, self.cond, env), then_body = expand_stmts(self.then_body, env), else_body = expand_stmts(self.else_body, env) })) end,
        [Tr.StmtSwitch] = function(self, env)
            local var_arms = {}
            for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = pvm.with(self.variant_arms[i], { binds = self.variant_arms[i].binds, body = expand_stmts(self.variant_arms[i].body, env) }) end
            return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), value = one(expand_expr, self.value, env), arms = expand_switch_stmt_arms(self.arms, env), variant_arms = var_arms, default_body = expand_stmts(self.default_body, env) }))
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
            local frag_ref = self.frag
            local frag = lookup_region_frag_ref(self.frag, env)
            -- Preserve emit as a region-fragment reference, but collapse a filled
            -- @{frag} slot to the concrete fragment name.  Leaving the slot in
            -- expanded statement lists lets unrelated later binders with the same
            -- splice key capture the emit target.
            local use_id = self.use_id
            if frag ~= pvm.NIL then
                local name = frag.name
                if type(name) == "table" then name = name.text or name.name end
                name = tostring(name)
                frag_ref = O.RegionFragRefName(name)
                use_id = tostring(use_id):gsub("@splice%.%d+", name)
            end
            return pvm.once(pvm.with(self, { h = one(expand_stmt_header, self.h, env), use_id = use_id, frag = frag_ref, args = expand_exprs(self.args, env) }))
        end,
    }, { args_cache = "last" })

    expand_func = pvm.phase("moonlift_open_expand_func", {
        [Tr.FuncLocal] = function(self, env)
            return pvm.once(pvm.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
        end,
        [Tr.FuncExport] = function(self, env)
            return pvm.once(pvm.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
        end,
        [Tr.FuncLocalContract] = function(self, env)
            return pvm.once(pvm.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
        end,
        [Tr.FuncExportContract] = function(self, env)
            return pvm.once(pvm.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
        end,
        [Tr.FuncDecl] = function(self, env)
            return pvm.once(pvm.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env) }))
        end,
        [Tr.FuncOpen] = function(self, env)
            local local_env = merge_fills(env, {})
            return pvm.once(pvm.with(self, { open = one(expand_open_set, self.open, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, local_env) }))
        end,
    }, { args_cache = "last" })

    expand_extern = pvm.phase("moonlift_open_expand_extern", {
        [Tr.ExternFunc] = function(self, env)
            return pvm.once(pvm.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env) }))
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
            return pvm.once(pvm.with(self, { fields = expand_fields(self.fields, env) }))
        end,
        [Tr.TypeDeclUnion] = function(self, env)
            return pvm.once(pvm.with(self, { fields = expand_fields(self.fields, env) }))
        end,
        [Tr.TypeDeclEnumSugar] = function(self) return pvm.once(self) end,
        [Tr.TypeDeclTaggedUnionSugar] = function(self, env) return pvm.once(pvm.with(self, { variants = expand_variants(self.variants, env) })) end,
        [Tr.TypeDeclOpenStruct] = function(self, env)
            return pvm.once(pvm.with(self, { fields = expand_fields(self.fields, env) }))
        end,
        [Tr.TypeDeclOpenUnion] = function(self, env)
            return pvm.once(pvm.with(self, { fields = expand_fields(self.fields, env) }))
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
            local pvm = require("moonlift.pvm")
            if pvm.classof(frag) == O.RegionFragDecl then
                local params = expand_open_params(frag.params, env)
                local conts = expand_cont_slots(frag.conts, env)
                local resolved_name = name_text(frag.name, env) or "<unresolved>"
                return O.RegionFragDecl(O.NameRefText(resolved_name), params, conts)
            end
            local params = expand_open_params(frag.params, env)
            local conts = expand_cont_slots(frag.conts, env)
            local entry = Tr.EntryControlBlock(frag.entry.label, expand_entry_params(frag.entry.params, env), expand_stmts(frag.entry.body, env))
            local blocks = expand_control_blocks(frag.blocks, env)
            local resolved_name = name_text(frag.name, env) or "<unresolved>"
            return O.RegionFrag(O.NameRefText(resolved_name), params, conts, frag.open, entry, blocks)
        end,
        -- Expand a standalone ExprFrag (resolves type/expr slots).
        expand_expr_frag = function(frag, env)
            local params = expand_open_params(frag.params, env)
            local body   = one(expand_expr, frag.body, env)
            local result = one(expand_type, frag.result, env)
            local resolved_name = name_text(frag.name, env) or "<unresolved>"
            return O.ExprFrag(O.NameRefText(resolved_name), params, frag.open, body, result)
        end,
        expand_name_ref = expand_name_ref,
        expand_type_decl = function(decl, env) return one(expand_type_decl, decl, env or empty_env()) end,
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
