local pvm = require("moonlift.pvm")
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T, opts)
    opts = opts or {}
    local Ty = T.MoonType
    local O = T.MoonOpen
    local B = T.MoonBind
    local Sem = T.MoonSem
    local Tr = T.MoonTree

    local lookup_slot_value
    local lookup_param_value
    local lookup_region_frag
    local lookup_expr_frag
    local expand_type_ref
    local expand_handle_fact
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
        local values = expand_value_ref_expr(ref, h, env)
        if #values == 0 then
            return nil
        end
        return values[1]
    end

    local function expand_types(xs, env)
        local out = {}
        for i = 1, #xs do
            local x = xs[i]
            if schema.classof(x) == Ty.TSlot then
                local values = lookup_slot_value(O.SlotType(x.slot), env)
                if #values == 1 and schema.classof(values[1]) == O.SlotValueTypes then
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
            if schema.classof(x) == Tr.ExprSlotValue then
                local values = lookup_slot_value(O.SlotExpr(x.slot), env)
                if #values == 1 and schema.classof(values[1]) == O.SlotValueExprs then
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
        for i = 1, #xs do out[#out + 1] = schema.with(xs[i], { value = one(expand_expr, xs[i].value, env) }) end
        return out
    end

    local function expand_params(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = schema.with(xs[i], { ty = one(expand_type, xs[i].ty, env) })
        end
        return out
    end

    local function expand_fields(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = schema.with(xs[i], { ty = one(expand_type, xs[i].ty, env) })
        end
        return out
    end

    local function expand_handle_facts(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = one(expand_handle_fact, xs[i], env)
        end
        return out
    end

    local function expand_variants(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = Ty.VariantDecl(xs[i].name, one(expand_type, xs[i].payload, env), expand_fields(xs[i].fields, env))
        end
        return out
    end

    local function expand_open_params(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = O.OpenParam(xs[i].key, xs[i].name, one(expand_type, xs[i].ty, env))
        end
        return out
    end

    local function expand_block_params(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = Tr.BlockParam(xs[i].name, one(expand_type, xs[i].ty, env))
        end
        return out
    end

    local function expand_entry_params(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = Tr.EntryBlockParam(xs[i].name, one(expand_type, xs[i].ty, env), one(expand_expr, xs[i].init, env))
        end
        return out
    end

    local function expand_cont_slots(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = O.ContSlot(xs[i].key, xs[i].pretty_name, expand_block_params(xs[i].params, env))
        end
        return out
    end

    local function expand_control_blocks(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = Tr.ControlBlock(xs[i].label, expand_block_params(xs[i].params, env), expand_stmts(xs[i].body, env))
        end
        return out
    end

    local function expand_switch_key(key, env)
        return key
    end

    local function expand_switch_stmt_arms(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = schema.with(xs[i], { raw_key = expand_switch_key(xs[i].raw_key, env), body = expand_stmts(xs[i].body, env) })
        end
        return out
    end

    local function expand_switch_expr_arms(xs, env)
        local out = {}
        for i = 1, #xs do
            out[#out + 1] = schema.with(xs[i], { raw_key = expand_switch_key(xs[i].raw_key, env), body = expand_stmts(xs[i].body, env), result = one(expand_expr, xs[i].result, env) })
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
            if schema.classof(binding.slot) == O.SlotCont then
                local key = binding.slot.slot.key
                local v = binding.value
                local vcls = schema.classof(v)
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

    function lookup_slot_value(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.SlotType) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotValue) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotExpr) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotPlace) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotDomain) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotRegion) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotCont) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotFunc) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotConst) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotStatic) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotTypeDecl) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotItems) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotModule) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotRegionFrag) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotExprFrag) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        elseif schema.isa(node, O.SlotName) then
            return (function(self, env)

            local v = slot_value(self, env)
            if v == nil then return erased.empty() end
            return erased.once(v)
            end)(node, ...)
        else
            error("erased phase moonlift_open_lookup_slot_value: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function lookup_param_value(param, env)
        for i = #env.params, 1, -1 do
            local binding = env.params[i]
            if binding.param == param then
                return binding.value
            end
        end
        return schema.NIL
    end

    lookup_region_frag = function(name, env)
        for i = #env.region_frags, 1, -1 do
            local fn = env.region_frags[i].name
            -- Resolve NameRef to plain string for comparison.
            if type(fn) ~= "string" then
                local cls = schema.classof(fn)
                if cls == O.NameRefText then fn = fn.text end
            end
            if fn == name then return env.region_frags[i] end
        end
        return schema.NIL
    end

    lookup_expr_frag = function(name, env)
        for i = #env.expr_frags, 1, -1 do
            local fn = env.expr_frags[i].name
            if type(fn) ~= "string" then
                local cls = schema.classof(fn)
                if cls == O.NameRefText then fn = fn.text end
            end
            if fn == name then return env.expr_frags[i] end
        end
        return schema.NIL
    end

    -- Resolve a RegionFragRef to a RegionFrag ASDL node, or schema.NIL.
    local function lookup_region_frag_ref(ref, env)
        local cls = schema.classof(ref)
        if cls == O.RegionFragRefName then
            return lookup_region_frag(ref.name, env)
        elseif cls == O.RegionFragRefSlot then
            local values = lookup_slot_value(O.SlotRegionFrag(ref.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueRegionFrag then
                return values[1].frag
            end
        end
        return schema.NIL
    end

    -- Resolve an ExprFragRef to an ExprFrag ASDL node, or schema.NIL.
    local function lookup_expr_frag_ref(ref, env)
        local cls = schema.classof(ref)
        if cls == O.ExprFragRefName then
            return lookup_expr_frag(ref.name, env)
        elseif cls == O.ExprFragRefSlot then
            local values = lookup_slot_value(O.SlotExprFrag(ref.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueExprFrag then
                return values[1].frag
            end
        end
        return schema.NIL
    end

    -- Resolve a NameRef to a concrete string.  If unresolved, returns nil.
    local function name_text(ref, env)
        local cls = schema.classof(ref)
        if cls == O.NameRefText then return ref.text end
        if cls == O.NameRefSlot then
            local values = lookup_slot_value(O.SlotName(ref.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueName then
                return values[1].text
            end
        end
        return nil
    end

    function expand_name_ref(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.NameRefText) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, O.NameRefSlot) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotName(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueName then
                return erased.once(O.NameRefText(values[1].text))
            end
            return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_name_ref: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_type_ref(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TypeRefPath) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefGlobal) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefLocal) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TypeRefSlot) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotType(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueType then
                local ty = one(expand_type, values[1].ty, env)
                local cls = schema.classof(ty)
                if cls == Ty.TNamed or cls == Ty.THandle then
                    return erased.once(ty.ref)
                end
            end
            return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_type_ref: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_handle_fact(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.HandleDomain) then
            return (function(self, env)
 return erased.once(Ty.HandleDomain(one(expand_type_ref, self.domain, env)))
            end)(node, ...)
        elseif schema.isa(node, Ty.HandleTarget) then
            return (function(self, env)
 return erased.once(Ty.HandleTarget(one(expand_type_ref, self.target, env)))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_handle_fact: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Ty.TScalar) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TPtr) then
            return (function(self, env)
 return erased.once(schema.with(self, { elem = one(expand_type, self.elem, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TArray) then
            return (function(self, env)
 return erased.once(schema.with(self, { elem = one(expand_type, self.elem, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TSlice) then
            return (function(self, env)
 return erased.once(schema.with(self, { elem = one(expand_type, self.elem, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TView) then
            return (function(self, env)
 return erased.once(schema.with(self, { elem = one(expand_type, self.elem, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TLease) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_type, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TOwned) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_type, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TAccess) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_type, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.THandle) then
            return (function(self, env)
 return erased.once(schema.with(self, { ref = one(expand_type_ref, self.ref, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TFunc) then
            return (function(self, env)
 return erased.once(schema.with(self, { params = expand_types(self.params, env), result = one(expand_type, self.result, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TClosure) then
            return (function(self, env)
 return erased.once(schema.with(self, { params = expand_types(self.params, env), result = one(expand_type, self.result, env) }))
            end)(node, ...)
        elseif schema.isa(node, Ty.TNamed) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TSlot) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotType(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueType then
                return expand_type(values[1].ty, env)
            end
            return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TCType) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Ty.TCFuncPtr) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_open_set(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, O.OpenSet) then
            return (function(open, env)

            local slots = {}
            for i = 1, #open.slots do
                if #lookup_slot_value(open.slots[i], env) == 0 then
                    slots[#slots + 1] = open.slots[i]
                end
            end
            return erased.once(O.OpenSet(open.value_imports, open.type_imports, open.layouts, slots))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_open_set: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_expr_header(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprSurface) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprTyped) then
            return (function(self, env)
 return erased.once(schema.with(self, { ty = one(expand_type, self.ty, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprOpen) then
            return (function(self, env)

            local ty = one(expand_type, self.ty, env)
            local open = one(expand_open_set, self.open, env)
            if open_empty(open) then return erased.once(Tr.ExprTyped(ty)) end
            return erased.once(Tr.ExprOpen(ty, open))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_expr_header: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_place_header(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceSurface) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceTyped) then
            return (function(self, env)
 return erased.once(schema.with(self, { ty = one(expand_type, self.ty, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceOpen) then
            return (function(self, env)

            local ty = one(expand_type, self.ty, env)
            local open = one(expand_open_set, self.open, env)
            if open_empty(open) then return erased.once(Tr.PlaceTyped(ty)) end
            return erased.once(Tr.PlaceOpen(ty, open))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_place_header: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_stmt_header(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtSurface) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtOpen) then
            return (function(self, env)

            local open = one(expand_open_set, self.open, env)
            if open_empty(open) then return erased.once(Tr.StmtSurface) end
            return erased.once(Tr.StmtOpen(open))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtFlow) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_stmt_header: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_module_header(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ModuleSurface) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleTyped) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleOpen) then
            return (function(self, env)

            local open = one(expand_open_set, self.open, env)
            if self.name ~= O.ModuleNameOpen and open_empty(open) then
                return erased.once(Tr.ModuleTyped(self.name.module_name))
            end
            return erased.once(Tr.ModuleOpen(self.name, open))
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleSem) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleCode) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_module_header: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_binding(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.Binding) then
            return (function(self, env)

            local class = self.class
            if schema.classof(class) == B.BindingClassOpenParam then
                class = B.BindingClassOpenParam(schema.with(class.param, { ty = one(expand_type, class.param.ty, env) }))
            end
            return erased.once(schema.with(self, { ty = one(expand_type, self.ty, env), class = class }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_binding: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_value_ref_expr(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(self, h, env)

            local cls = schema.classof(self.binding.class)
            if cls == B.BindingClassOpenParam then
                local v = lookup_param_value(self.binding.class.param, env)
                if v ~= schema.NIL then return expand_expr(v, env) end
            end
            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefHole) then
            return (function(self, h, env)

            local values = lookup_slot_value(self.slot, env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueExpr then
                return expand_expr(values[1].expr, env)
            end
            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_value_ref_expr: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_value_ref(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(self, env)
 return erased.once(schema.with(self, { binding = one(expand_binding, self.binding, env) }))
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
            error("erased phase moonlift_open_expand_value_ref: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_view(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ViewFromExpr) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_expr, self.base, env), elem = one(expand_type, self.elem, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewContiguous) then
            return (function(self, env)
 return erased.once(schema.with(self, { data = one(expand_expr, self.data, env), elem = one(expand_type, self.elem, env), len = one(expand_expr, self.len, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewStrided) then
            return (function(self, env)
 return erased.once(schema.with(self, { data = one(expand_expr, self.data, env), elem = one(expand_type, self.elem, env), len = one(expand_expr, self.len, env), stride = one(expand_expr, self.stride, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewRestrided) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_view, self.base, env), elem = one(expand_type, self.elem, env), stride = one(expand_expr, self.stride, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewWindow) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_view, self.base, env), start = one(expand_expr, self.start, env), len = one(expand_expr, self.len, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewRowBase) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_view, self.base, env), row_offset = one(expand_expr, self.row_offset, env), elem = one(expand_type, self.elem, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewInterleaved) then
            return (function(self, env)
 return erased.once(schema.with(self, { data = one(expand_expr, self.data, env), elem = one(expand_type, self.elem, env), len = one(expand_expr, self.len, env), stride = one(expand_expr, self.stride, env), lane = one(expand_expr, self.lane, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ViewInterleavedView) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_view, self.base, env), elem = one(expand_type, self.elem, env), stride = one(expand_expr, self.stride, env), lane = one(expand_expr, self.lane, env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_view: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_domain(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.DomainRange) then
            return (function(self, env)
 return erased.once(schema.with(self, { stop = one(expand_expr, self.stop, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainRange2) then
            return (function(self, env)
 return erased.once(schema.with(self, { start = one(expand_expr, self.start, env), stop = one(expand_expr, self.stop, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainZipEqValues) then
            return (function(self, env)
 return erased.once(schema.with(self, { values = expand_exprs(self.values, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainValue) then
            return (function(self, env)
 return erased.once(schema.with(self, { value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainView) then
            return (function(self, env)
 return erased.once(schema.with(self, { view = one(expand_view, self.view, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainZipEqViews) then
            return (function(self, env)

            local views = {}
            for i = 1, #self.views do views[#views + 1] = one(expand_view, self.views[i], env) end
            return erased.once(schema.with(self, { views = views }))
            end)(node, ...)
        elseif schema.isa(node, Tr.DomainSlotValue) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotDomain(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueDomain then
                return expand_domain(values[1].domain, env)
            end
            return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_domain: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_index_base(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.IndexBaseExpr) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_expr, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBasePlace) then
            return (function(self, env)
 return erased.once(schema.with(self, { base = one(expand_place, self.base, env), elem = one(expand_type, self.elem, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.IndexBaseView) then
            return (function(self, env)
 return erased.once(schema.with(self, { view = one(expand_view, self.view, env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_index_base: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_place(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.PlaceRef) then
            return (function(self, env)

            local h = one(expand_place_header, self.h, env)
            local replacement = maybe_expr_from_value_ref(self.ref, h, env)
            if replacement ~= nil and schema.classof(replacement) == Tr.ExprRef then
                return erased.once(Tr.PlaceRef(h, replacement.ref))
            end
            return erased.once(schema.with(self, { h = h, ref = one(expand_value_ref, self.ref, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDeref) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_place_header, self.h, env), base = one(expand_expr, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceDot) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_place_header, self.h, env), base = one(expand_place, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceField) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_place_header, self.h, env), base = one(expand_place, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceIndex) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_place_header, self.h, env), base = one(expand_index_base, self.base, env), index = one(expand_expr, self.index, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.PlaceSlotValue) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotPlace(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValuePlace then
                return expand_place(values[1].place, env)
            end
            return erased.once(schema.with(self, { h = one(expand_place_header, self.h, env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_place: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

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

            local cls = schema.classof(target)
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
    -- alpha-renaming, continuation routing, and block hoisting. Region call
    -- lowering is frontend-only and is collected here as generated ordinary
    -- Tree items which are then expanded through the same pipeline.

    local RegionCall = require("moonlift.region_call_lowering").Define(T, {
        expand_expr = function(expr, env) return one(expand_expr, expr, env) end,
        expand_stmt_header = function(h, env) return one(expand_stmt_header, h, env) end,
        lookup_region_frag_ref = lookup_region_frag_ref,
    })

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
        lower_region_call_use = (not opts.defer_region_calls) and function(stmt, env, label_map)
            return RegionCall.lower_call_use(stmt, env, label_map)
        end or nil,
    })

    function expand_control_stmt_region(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlStmtRegion) then
            return (function(self, env)

            return erased.once(rnf.control_stmt_region(self, env))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_control_stmt_region: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_control_expr_region(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ControlExprRegion) then
            return (function(self, env)

            return erased.once(rnf.control_expr_region(self, env))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_control_expr_region: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_expr(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprLit) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprRef) then
            return (function(self, env)

            local replacement = maybe_expr_from_value_ref(self.ref, self.h, env)
            if replacement ~= nil then return erased.once(replacement) end
            return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ref = one(expand_value_ref, self.ref, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), base = one(expand_expr, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), lhs = one(expand_expr, self.lhs, env), rhs = one(expand_expr, self.rhs, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), lhs = one(expand_expr, self.lhs, env), rhs = one(expand_expr, self.rhs, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), lhs = one(expand_expr, self.lhs, env), rhs = one(expand_expr, self.rhs, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), args = expand_exprs(self.args, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), place = one(expand_place, self.place, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function(self, env)

            return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), callee = one(expand_expr, self.callee, env), args = expand_exprs(self.args, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCtor) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), args = expand_exprs(self.args, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprNull) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), elem = one(expand_type, self.elem, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLen) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), base = one(expand_expr, self.base, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), base = one(expand_index_base, self.base, env), index = one(expand_expr, self.index, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(self, env)

            local fields = {}
            for i = 1, #self.fields do fields[#fields + 1] = schema.with(self.fields[i], { value = one(expand_expr, self.fields[i].value, env) }) end
            return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), fields = fields }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), elem_ty = one(expand_type, self.elem_ty, env), elems = expand_exprs(self.elems, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), cond = one(expand_expr, self.cond, env), then_expr = one(expand_expr, self.then_expr, env), else_expr = one(expand_expr, self.else_expr, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), cond = one(expand_expr, self.cond, env), then_expr = one(expand_expr, self.then_expr, env), else_expr = one(expand_expr, self.else_expr, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(self, env)

            local var_arms = {}
            for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = schema.with(self.variant_arms[i], { binds = self.variant_arms[i].binds, body = expand_stmts(self.variant_arms[i].body, env), result = one(expand_expr, self.variant_arms[i].result, env) }) end
            return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env), arms = expand_switch_expr_arms(self.arms, env), variant_arms = var_arms, default_body = expand_stmts(self.default_body or {}, env), default_expr = one(expand_expr, self.default_expr, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), region = one(expand_control_expr_region, self.region, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), stmts = expand_stmts(self.stmts, env), result = one(expand_expr, self.result, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), view = one(expand_view, self.view, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSizeOf) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAlignOf) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIsNull) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicLoad) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicRmw) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicCas) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env), expected = one(expand_expr, self.expected, env), replacement = one(expand_expr, self.replacement, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSlotValue) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotExpr(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueExpr then
                return expand_expr(values[1].expr, env)
            end
            return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUseExprFrag) then
            return (function(self, env)

            local frag = lookup_expr_frag_ref(self.frag, env)
            if frag == schema.NIL then
                return erased.once(schema.with(self, { h = one(expand_expr_header, self.h, env), args = expand_exprs(self.args, env) }))
            end
            local local_env = env_with_fills_and_params(env, self.fills, frag_param_bindings(frag.params, self.args, env))
            return expand_expr(frag.body, local_env)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_expr: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_stmt(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtLet) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), binding = one(expand_binding, self.binding, env), init = one(expand_expr, self.init, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), binding = one(expand_binding, self.binding, env), init = one(expand_expr, self.init, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), place = one(expand_place, self.place, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), ty = one(expand_type, self.ty, env), addr = one(expand_expr, self.addr, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), expr = one(expand_expr, self.expr, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), cond = one(expand_expr, self.cond, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), cond = one(expand_expr, self.cond, env), then_body = expand_stmts(self.then_body, env), else_body = expand_stmts(self.else_body, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function(self, env)

            local var_arms = {}
            for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = schema.with(self.variant_arms[i], { binds = self.variant_arms[i].binds, body = expand_stmts(self.variant_arms[i].body, env) }) end
            return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), value = one(expand_expr, self.value, env), arms = expand_switch_stmt_arms(self.arms, env), variant_arms = var_arms, default_body = expand_stmts(self.default_body, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJump) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), args = expand_jump_args(self.args, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJumpCont) then
            return (function(self, env)

            local args = expand_jump_args(self.args, env)
            local target = resolve_cont_target(self.slot, env)
            if target ~= nil then
                local cls = schema.classof(target)
                if cls == O.ContTargetLabel then
                    return erased.once(Tr.StmtJump(one(expand_stmt_header, self.h, env), target.label, args))
                elseif cls == O.ContTargetSlot then
                    return erased.once(Tr.StmtJumpCont(one(expand_stmt_header, self.h, env), target.slot, args))
                end
            end
            return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), args = args }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), region = one(expand_control_stmt_region, self.region, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotRegion(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueRegion then
                return erased.children(function(stmt) return expand_stmt(stmt, env) end, values[1].body)
            end
            return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function(self, env)

            local frag_ref = self.frag
            local frag = lookup_region_frag_ref(self.frag, env)
            -- Preserve emit as a region-fragment reference, but collapse a filled
            -- @{frag} slot to the concrete fragment name.  Leaving the slot in
            -- expanded statement lists lets unrelated later binders with the same
            -- splice key capture the emit target.
            local use_id = self.use_id
            if frag ~= schema.NIL then
                local name = frag.name
                if type(name) == "table" then name = name.text or name.name end
                name = tostring(name)
                frag_ref = O.RegionFragRefName(name)
                local rewritten = tostring(use_id):gsub("@splice%.%d+", name)
                if rewritten == tostring(use_id) and not rewritten:match(name) then
                    rewritten = rewritten .. "." .. name
                end
                use_id = rewritten
            end
            return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env), use_id = use_id, frag = frag_ref, args = expand_exprs(self.args, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtTrap) then
            return (function(self, env)
 return erased.once(schema.with(self, { h = one(expand_stmt_header, self.h, env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_stmt: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_func(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.FuncLocal) then
            return (function(self, env)

            return erased.once(schema.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExport) then
            return (function(self, env)

            return erased.once(schema.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncLocalContract) then
            return (function(self, env)

            return erased.once(schema.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExportContract) then
            return (function(self, env)

            return erased.once(schema.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncDecl) then
            return (function(self, env)

            return erased.once(schema.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncOpen) then
            return (function(self, env)

            local local_env = merge_fills(env, {})
            return erased.once(schema.with(self, { open = one(expand_open_set, self.open, env), result = one(expand_type, self.result, env), body = expand_stmts(self.body, local_env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_func: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_extern(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExternFunc) then
            return (function(self, env)

            return erased.once(schema.with(self, { params = expand_params(self.params, env), result = one(expand_type, self.result, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExternFuncOpen) then
            return (function(self, env)
 return erased.once(schema.with(self, { result = one(expand_type, self.result, env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_extern: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ConstItem) then
            return (function(self, env)
 return erased.once(schema.with(self, { ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ConstItemOpen) then
            return (function(self, env)
 return erased.once(schema.with(self, { open = one(expand_open_set, self.open, env), ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_const: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_static(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StaticItem) then
            return (function(self, env)
 return erased.once(schema.with(self, { ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.StaticItemOpen) then
            return (function(self, env)
 return erased.once(schema.with(self, { open = one(expand_open_set, self.open, env), ty = one(expand_type, self.ty, env), value = one(expand_expr, self.value, env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_static: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expand_type_decl(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.TypeDeclStruct) then
            return (function(self, env)

            return erased.once(schema.with(self, { fields = expand_fields(self.fields, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclUnion) then
            return (function(self, env)

            return erased.once(schema.with(self, { fields = expand_fields(self.fields, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclEnumSugar) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclTaggedUnionSugar) then
            return (function(self, env)
 return erased.once(schema.with(self, { variants = expand_variants(self.variants, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclHandle) then
            return (function(self, env)
 return erased.once(schema.with(self, { facts = expand_handle_facts(self.facts, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclOpenStruct) then
            return (function(self, env)

            return erased.once(schema.with(self, { fields = expand_fields(self.fields, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclOpenUnion) then
            return (function(self, env)

            return erased.once(schema.with(self, { fields = expand_fields(self.fields, env) }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_type_decl: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function append_unique(dst, value)
        for i = 1, #dst do
            if dst[i] == value then return end
        end
        dst[#dst + 1] = value
    end

    local function env_with_module_frags(env, items)
        local region_frags, expr_frags = {}, {}
        for i = 1, #(env.region_frags or {}) do append_unique(region_frags, env.region_frags[i]) end
        for i = 1, #(env.expr_frags or {}) do append_unique(expr_frags, env.expr_frags[i]) end
        for i = 1, #(items or {}) do
            local item = items[i]
            local cls = schema.classof(item)
            if cls == Tr.ItemRegionFrag then
                append_unique(region_frags, item.frag)
            elseif cls == Tr.ItemExprFrag then
                append_unique(expr_frags, item.frag)
            end
        end
        return O.ExpandEnv(region_frags, expr_frags, env.fills, env.conts, env.params, env.rebase_prefix)
    end

    local function expand_region_frag_node(frag, env)
        if schema.classof(frag) == O.RegionFragDecl then
            local params = expand_open_params(frag.params, env)
            local conts = expand_cont_slots(frag.conts, env)
            local resolved_name = name_text(frag.name, env) or "<unresolved>"
            return O.RegionFragDecl(O.NameRefText(resolved_name), params, conts)
        end
        local body_env = env_with_module_frags(env, { Tr.ItemRegionFrag(frag) })
        local params = expand_open_params(frag.params, env)
        local conts = expand_cont_slots(frag.conts, env)
        local entry = Tr.EntryControlBlock(frag.entry.label, expand_entry_params(frag.entry.params, body_env), expand_stmts(frag.entry.body, body_env))
        local blocks = expand_control_blocks(frag.blocks, body_env)
        local resolved_name = name_text(frag.name, env) or "<unresolved>"
        return O.RegionFrag(O.NameRefText(resolved_name), params, conts, frag.open, entry, blocks)
    end

    local function expand_expr_frag_node(frag, env)
        local params = expand_open_params(frag.params, env)
        local body = one(expand_expr, frag.body, env)
        local result = one(expand_type, frag.result, env)
        local resolved_name = name_text(frag.name, env) or "<unresolved>"
        return O.ExprFrag(O.NameRefText(resolved_name), params, frag.open, body, result)
    end

    function expand_item(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ItemFunc) then
            return (function(self, env)
 return erased.once(schema.with(self, { func = one(expand_func, self.func, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExtern) then
            return (function(self, env)
 return erased.once(schema.with(self, { func = one(expand_extern, self.func, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemConst) then
            return (function(self, env)
 return erased.once(schema.with(self, { c = one(expand_const, self.c, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemStatic) then
            return (function(self, env)
 return erased.once(schema.with(self, { s = one(expand_static, self.s, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemImport) then
            return (function(self)
 return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemType) then
            return (function(self, env)
 return erased.once(schema.with(self, { t = one(expand_type_decl, self.t, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemRegionFrag) then
            return (function(self, env)
 return erased.once(schema.with(self, { frag = expand_region_frag_node(self.frag, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExprFrag) then
            return (function(self, env)
 return erased.once(schema.with(self, { frag = expand_expr_frag_node(self.frag, env) }))
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseTypeDeclSlot) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotTypeDecl(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueTypeDecl then
                return erased.once(Tr.ItemType(one(expand_type_decl, values[1].t, env)))
            end
            return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseItemsSlot) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotItems(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueItems then
                return erased.children(function(item) return expand_item(item, env) end, values[1].items)
            end
            return erased.once(self)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModule) then
            return (function(self, env)

            local local_env = merge_fills(env, self.fills)
            local module = one(expand_module, self.module, local_env)
            return erased.children(function(item) return erased.once(item) end, module.items)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModuleSlot) then
            return (function(self, env)

            local values = lookup_slot_value(O.SlotModule(self.slot), env)
            if #values == 1 and schema.classof(values[1]) == O.SlotValueModule then
                local local_env = merge_fills(env, self.fills)
                local module = one(expand_module, values[1].module, local_env)
                return erased.children(function(item) return erased.once(item) end, module.items)
            end
            return erased.once(self)
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_item: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function expand_pending_region_call_wrappers(out, env)
        local emitted = {}
        while true do
            local pending = RegionCall.pending_wrappers()
            local progressed = false
            for i = 1, #pending do
                local rec = pending[i]
                if not emitted[rec.key] then
                    emitted[rec.key] = true
                    progressed = true
                    RegionCall.mark_emitted(rec.key)
                    for j = 1, #rec.items do
                        local g, p, c = expand_item(rec.items[j], env)
                        pvm.drain_into(g, p, c, out)
                    end
                end
            end
            if not progressed then break end
        end
        return out
    end

    function expand_module(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.Module) then
            return (function(module, env)

            local module_env = env_with_module_frags(env, module.items)
            local items = expand_items(module.items, module_env)
            expand_pending_region_call_wrappers(items, module_env)
            return erased.once(schema.with(module, { h = one(expand_module_header, module.h, module_env), items = items }))
            end)(node, ...)
        else
            error("erased phase moonlift_open_expand_module: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

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
            return expand_region_frag_node(frag, env)
        end,
        -- Expand a standalone ExprFrag (resolves type/expr slots).
        expand_expr_frag = function(frag, env)
            return expand_expr_frag_node(frag, env)
        end,
        expand_name_ref = expand_name_ref,
        expand_type_decl = function(decl, env) return one(expand_type_decl, decl, env or empty_env()) end,
        expand_module = function(module, env) return one(expand_module, module, env or empty_env()) end,
        expand_type = expand_type,
        expand_open_set = expand_open_set,
        expand_expr = expand_expr,
        expand_stmt = expand_stmt,
        expand_item = expand_item,
        generated_items = function()
            local out = {}
            if RegionCall and RegionCall.pending_wrappers then
                local recs = RegionCall.pending_wrappers()
                for i = 1, #recs do
                    for j = 1, #(recs[i].items or {}) do out[#out + 1] = recs[i].items[j] end
                end
            end
            return out
        end,
        type = function(ty, env) return one(expand_type, ty, env or empty_env()) end,
        expr = function(expr, env) return one(expand_expr, expr, env or empty_env()) end,
        stmts = function(stmts, env) return expand_stmts(stmts, env or empty_env()) end,
        item_stream = function(item, env) return expand_item(item, env or empty_env()) end,
        module = function(module, env) return one(expand_module, module, env or empty_env()) end,
    }
end

return M
