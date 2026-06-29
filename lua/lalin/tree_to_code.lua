local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function class_name(x)
    return tostring(x)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.tree_to_code ~= nil then return T._lalin_api_cache.tree_to_code end

    local Core = T.LalinCore
    local Ty = T.LalinType
    local Bind = T.LalinBind
    local Sem = T.LalinSem
    local Host = T.LalinHost
    local Tr = T.LalinTree
    local Code = T.LalinCode

    local CodeType = require("lalin.code_type")(T)
    local TypeSizeAlign = require("lalin.type_size_align")(T)
    local ModuleType = require("lalin.tree_module_type")(T)
    local ConstEval = require("lalin.sem_const_eval")(T)
    local TreeContractFacts = require("lalin.tree_contract_facts")(T)
    local api = {}
    local variant_name_text
    local source_access_base
    local expr_type
    local place_type

    function Tr.ModuleHeader:tree_code_module_name() return "module" end
    function Tr.ModuleTyped:tree_code_module_name() return self.module_name end
    function Tr.ModuleSem:tree_code_module_name() return self.module_name end
    function Tr.ModuleCode:tree_code_module_name() return self.module_name end

    function Core.Scalar:tree_code_is_void_scalar() return false end
    function Core.ScalarVoid:tree_code_is_void_scalar() return true end

    function Ty.Type:tree_code_is_void_type() return false end
    function Ty.TScalar:tree_code_is_void_type() return self.scalar:tree_code_is_void_scalar() end

    function Ty.Type:tree_code_source_access_base() return self end
    function Ty.TLease:tree_code_source_access_base() return self.base end
    function Ty.TOwned:tree_code_source_access_base() return self.base:tree_code_source_access_base() end
    function Ty.TAccess:tree_code_source_access_base() return self.base:tree_code_source_access_base() end

    function Ty.Type:tree_code_named_type_name() return nil end
    function Ty.TNamed:tree_code_named_type_name() return self.ref:tree_code_type_ref_name() end
    function Ty.TypeRef:tree_code_type_ref_name() return nil end
    function Ty.TypeRefGlobal:tree_code_type_ref_name() return self.type_name end
    function Ty.TypeRefLocal:tree_code_type_ref_name() return self.sym.name end
    function Ty.TypeRefPath:tree_code_type_ref_name()
        if #self.path.parts == 0 then return nil end
        return self.path.parts[#self.path.parts].text
    end

    function Tr.TypeDecl:tree_code_add_variant_defs(defs, mod_name) end
    function Tr.TypeDeclEnumSugar:tree_code_add_variant_defs(defs, mod_name)
        local variants = {}
        for i = 1, #self.variants do
            local name = variant_name_text(self.variants[i])
            variants[name] = Tr.TreeCodeVariant(name, i - 1, Ty.TScalar(Core.ScalarVoid), {})
        end
        defs[self.name] = Tr.TreeCodeVariantDef(Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)), variants)
    end
    function Tr.TypeDeclTaggedUnionSugar:tree_code_add_variant_defs(defs, mod_name)
        local variants = {}
        for i = 1, #self.variants do
            local v = self.variants[i]
            variants[v.name] = Tr.TreeCodeVariant(v.name, i - 1, v.payload, v.fields or {})
        end
        defs[self.name] = Tr.TreeCodeVariantDef(Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)), variants)
    end
    function Tr.Item:tree_code_add_variant_defs(defs, mod_name) end
    function Tr.ItemType:tree_code_add_variant_defs(defs, mod_name)
        self.t:tree_code_add_variant_defs(defs, mod_name)
    end

    function Tr.ExprHeader:tree_code_expr_type() return nil end
    function Tr.ExprTyped:tree_code_expr_type() return self.ty end
    function Tr.PlaceHeader:tree_code_place_type() return nil end
    function Tr.PlaceTyped:tree_code_place_type() return self.ty end

    function Ty.Type:tree_code_index_elem_type() return nil end
    function Ty.TPtr:tree_code_index_elem_type() return self.elem end
    function Ty.TArray:tree_code_index_elem_type() return self.elem end
    function Ty.TSlice:tree_code_index_elem_type() return self.elem end
    function Ty.TView:tree_code_index_elem_type() return self.elem end
    function Tr.IndexBase:tree_code_index_base_elem_type() return nil end
    function Tr.IndexBaseExpr:tree_code_index_base_elem_type()
        return source_access_base(expr_type(self.base)):tree_code_index_elem_type()
    end
    function Tr.IndexBasePlace:tree_code_index_base_elem_type() return self.elem end
    function Tr.IndexBaseView:tree_code_index_base_elem_type() return self.view.elem end

    function Code.CodeType:tree_code_is_float_type() return false end
    function Code.CodeTyFloat:tree_code_is_float_type() return true end
    function Code.CodeType:tree_code_is_aggregate_type() return false end
    function Code.CodeTyNamed:tree_code_is_aggregate_type() return true end
    function Code.CodeTyArray:tree_code_is_aggregate_type() return true end
    function Code.CodeTySlice:tree_code_is_aggregate_type() return true end
    function Code.CodeTyView:tree_code_is_aggregate_type() return true end
    function Code.CodeTyClosure:tree_code_is_aggregate_type() return true end
    function Code.CodeType:tree_code_is_view_type() return false end
    function Code.CodeTyView:tree_code_is_view_type() return true end

    function Ty.TypeMemLayoutResult:tree_code_known_layout() return nil end
    function Ty.TypeMemLayoutKnown:tree_code_known_layout() return self.layout end

    local function unsupported(ctx, node, what)
        local site = ctx and ctx.func_name or "module"
        error("tree_to_code unsupported lowering: " .. tostring(what or class_name(node)) .. " in " .. site, 3)
    end

    local function module_name(module)
        local h = module and module.h
        return h and h:tree_code_module_name() or "module"
    end

    local function binding_key(binding)
        if binding == nil then return "<nil>" end
        if binding.id and binding.id.text then return binding.id.text end
        return tostring(binding.name)
    end

    local function scoped_binding_key(ctx, binding)
        local key = binding_key(binding)
        local alpha = ctx and ctx.binding_alpha
        if alpha ~= nil and alpha[key] ~= nil then return alpha[key] end
        return key
    end

    local function binding_alpha_suffix(ctx)
        return ctx and ctx.binding_alpha_suffixes and ctx.binding_alpha_suffixes.current or nil
    end

    local function declare_binding_key(ctx, binding)
        local key = binding_key(binding)
        local suffix = binding_alpha_suffix(ctx)
        if ctx ~= nil and ctx.binding_alpha ~= nil and suffix ~= nil and ctx.binding_alpha[key] == nil then
            ctx.binding_alpha[key] = key .. "@" .. suffix
        end
        return scoped_binding_key(ctx, binding)
    end

    local function declare_fresh_binding_key(ctx, binding)
        local key = binding_key(binding)
        local suffix = binding_alpha_suffix(ctx)
        if ctx ~= nil and ctx.binding_alpha ~= nil and suffix ~= nil then
            ctx.binding_alpha[key] = key .. "@" .. suffix .. "_l" .. tostring(ctx:tree_code_next_counter("binding_alpha"))
        end
        return scoped_binding_key(ctx, binding)
    end

    local function binding_is_addressed(ctx, binding)
        local key = binding_key(binding)
        local scoped = scoped_binding_key(ctx, binding)
        return (ctx.addressed and (ctx.addressed[key] or ctx.addressed[scoped])) or false
    end

    local function binding_is_mutable(ctx, binding)
        local key = binding_key(binding)
        local scoped = scoped_binding_key(ctx, binding)
        return (ctx.mutable and (ctx.mutable[key] or ctx.mutable[scoped])) or false
    end

    local function is_void_type(ty)
        return ty:tree_code_is_void_type()
    end

    source_access_base = function(ty)
        return ty:tree_code_source_access_base()
    end

    variant_name_text = function(v)
        if type(v) == "string" then return v end
        return v and (v.text or v.name) or tostring(v)
    end

    local function named_type_name(ty)
        return ty:tree_code_named_type_name()
    end

    local function build_variant_defs(module, module_name)
        local defs = {}
        for i = 1, #(module.items or {}) do
            module.items[i]:tree_code_add_variant_defs(defs, module_name)
        end
        return defs
    end

    local function func_key(module_name, item_name)
        return tostring(module_name or "") .. "\0" .. tostring(item_name or "")
    end

    local function code_func_id(item_name)
        return Code.CodeFuncId("fn:" .. tostring(item_name))
    end

    local function code_extern_id(name)
        return Code.CodeExternId("extern:" .. tostring(name))
    end

    local function code_global_id(module_name, item_name)
        return Code.CodeGlobalId("global:" .. tostring(module_name or "") .. ":" .. tostring(item_name or ""))
    end

    local function code_data_id(id)
        return Code.CodeDataId("data:" .. tostring(id and id.text or id))
    end

    local function decoded_string_bytes(bytes)
        bytes = tostring(bytes or "")
        local first = bytes:sub(1, 1)
        if (first == '"' or first == "'") and bytes:sub(-1) == first then
            local loader = loadstring or load
            local fn = loader("return " .. bytes)
            if fn then
                local ok, value = pcall(fn)
                if ok and type(value) == "string" then return value end
            end
        end
        return bytes
    end

    local function new_tree_code_func_context(module_ctx, func_name, residence)
        residence = residence or {}
        return Tr.TreeCodeFuncContext(
            module_ctx,
            func_name,
            {},
            {},
            residence.addressed or {},
            residence.mutable or {},
            {},
            {},
            nil,
            {},
            {},
            0,
            0,
            0,
            0,
            0,
            {},
            nil,
            {},
            0,
            nil,
            {},
            {}
        )
    end

    local function tree_code_target(raw_target)
        local target = raw_target and raw_target.c_target or raw_target
        local ok, normalized = pcall(CodeType.normalize_target, target)
        if ok then return normalized end
        return CodeType.default_target({
            pointer_bits = target and target.pointer_bits or nil,
            index_bits = target and (target.index_bits or target.pointer_bits) or nil,
            endian = type(target and target.endian) == "string" and target.endian or nil,
        })
    end

    local function fresh_string_data(ctx, bytes)
        local module_ctx = ctx.module
        module_ctx.next_string_data = (module_ctx.next_string_data or 0) + 1
        local stem = "str_" .. sanitize(ctx.func_name) .. "_" .. tostring(module_ctx.next_string_data)
        local id = Code.CodeDataId("data:" .. tostring(module_ctx.facts.module_name or "module") .. ":" .. stem)
        local decoded = decoded_string_bytes(bytes)
        local nul_terminated = decoded .. "\0"
        module_ctx.generated_data[#module_ctx.generated_data + 1] = Code.CodeData(
            id,
            stem,
            Code.CodeLinkageLocal,
            #nul_terminated,
            1,
            { Code.CodeDataBytes(0, nul_terminated) },
            Code.CodeOriginGenerated("string literal " .. stem)
        )
        return id, #decoded
    end

    local function value_id_for_binding(ctx, binding)
        return Code.CodeValueId("v:" .. sanitize(ctx.func_name) .. ":" .. sanitize(scoped_binding_key(ctx, binding)))
    end

    local function local_id_for_binding(ctx, binding)
        return Code.CodeLocalId("local:" .. sanitize(ctx.func_name) .. ":" .. sanitize(scoped_binding_key(ctx, binding)))
    end

    local function origin_binding(binding)
        if binding ~= nil then return Code.CodeOriginBinding(binding) end
        return Code.CodeOriginUnknown
    end

    local function origin_generated(reason)
        return Code.CodeOriginGenerated(reason)
    end

    expr_type = function(expr)
        local h = expr and expr.h
        if h ~= nil then
            local ty = h:tree_code_expr_type()
            if ty ~= nil then return ty end
        end
        unsupported(nil, expr, "untyped expression " .. class_name(expr))
    end

    place_type = function(place)
        local h = place and place.h
        if h ~= nil then
            local ty = h:tree_code_place_type()
            if ty ~= nil then return ty end
        end
        unsupported(nil, place, "untyped place " .. class_name(place))
    end

    local function index_base_elem_ty(base)
        local elem = base:tree_code_index_base_elem_type()
        if elem ~= nil then return elem end
        unsupported(nil, base, "index base without element type " .. class_name(base))
    end

    local function code_ty(ctx, ty)
        return CodeType.type_to_code(ty, ctx.module)
    end

    local function u8_code_ty()
        return Code.CodeTyInt(8, Code.CodeUnsigned)
    end

    local function variant_def(ctx, type_name)
        return ctx.module.facts.variant_defs and ctx.module.facts.variant_defs[type_name] or nil
    end

    local function variant_payload_ty(ctx, variant)
        if #(variant.fields or {}) > 1 then unsupported(ctx, variant, "multi-field variant payload `" .. tostring(variant.name) .. "`") end
        local ty = (#(variant.fields or {}) == 1) and variant.fields[1].ty or variant.payload
        if ty == nil or is_void_type(ty) then return nil end
        return ty
    end

    local function variant_ref(ctx, owner_ty, variant)
        local payload_ty = variant_payload_ty(ctx, variant)
        return Code.CodeVariantRef(code_ty(ctx, owner_ty), variant.name, variant.tag, payload_ty and code_ty(ctx, payload_ty) or nil)
    end

    local function variant_binding(kind, variant, bind)
        return Bind.Binding(Core.Id("variant:" .. kind .. ":" .. variant.name .. ":" .. bind.name), bind.name, bind.ty, Bind.BindingClassLocalValue)
    end

    local function is_float_code_ty(ty)
        return ty:tree_code_is_float_type()
    end

    local function is_aggregate_code_ty(ty)
        return ty:tree_code_is_aggregate_type()
    end

    local function layout_of(ctx, ty)
        local result = TypeSizeAlign.result(ty, ctx.module.facts.layout_env, ctx.module.facts.target)
        return result:tree_code_known_layout()
    end

    local function align_of(ctx, ty)
        local layout = layout_of(ctx, ty)
        return layout and layout.align or 1
    end

    local function size_of(ctx, ty)
        local layout = layout_of(ctx, ty)
        return layout and layout.size or nil
    end

    local clone_map, replace_map
    local label_key

    function Tr.TreeCodeFuncContext:tree_code_next_counter(name)
        local next_value = (self.counter_values[name] or 0) + 1
        self.counter_values[name] = next_value
        return next_value
    end

    function Tr.TreeCodeFuncContext:tree_code_current_block()
        return self.current_blocks.current
    end

    function Tr.TreeCodeFuncContext:tree_code_has_current_block()
        return self:tree_code_current_block() ~= nil
    end

    function Tr.TreeCodeFuncContext:tree_code_set_current_block(block)
        self.current_blocks.current = block
    end

    function Tr.TreeCodeFuncContext:tree_code_clear_current_block()
        self.current_blocks.current = nil
    end

    function Tr.TreeCodeFuncContext:tree_code_append_block(block)
        self.blocks[#self.blocks + 1] = block
    end

    function Tr.TreeCodeFuncContext:tree_code_save_bindings()
        return Tr.TreeCodeBindingSnapshot(clone_map(self.bindings), clone_map(self.locals_by_key))
    end

    function Tr.TreeCodeFuncContext:tree_code_restore_bindings(saved)
        replace_map(self.bindings, saved.bindings)
        replace_map(self.locals_by_key, saved.locals_by_key)
    end

    function Tr.TreeCodeFuncContext:tree_code_note_binding(binding, value)
        self.bindings[scoped_binding_key(self, binding)] = value
    end

    function Tr.TreeCodeFuncContext:tree_code_note_mutable(binding)
        self.mutable[declare_fresh_binding_key(self, binding)] = true
    end

    function Tr.TreeCodeFuncContext:tree_code_alpha_snapshot()
        return clone_map(self.binding_alpha), self.binding_alpha_suffixes.current
    end

    function Tr.TreeCodeFuncContext:tree_code_use_alpha(alpha, suffix)
        replace_map(self.binding_alpha, alpha)
        self.binding_alpha_suffixes.current = suffix
    end

    function Tr.TreeCodeFuncContext:tree_code_fork_alpha(suffix)
        self:tree_code_use_alpha(setmetatable({}, { __index = self.binding_alpha }), suffix)
        return self.binding_alpha
    end

    function Tr.TreeCodeFuncContext:tree_code_enter_control_region(region)
        self.control_regions.current = region
        self.control_exit_seen.current = false
    end

    function Tr.TreeCodeFuncContext:tree_code_leave_control_region(region)
        local saw_exit = self.control_exit_seen.current or false
        self.control_regions.current = region
        self.control_exit_seen.current = false
        return saw_exit
    end

    function Tr.TreeCodeFuncContext:tree_code_current_control_region()
        return self.control_regions.current
    end

    function Tr.TreeCodeFuncContext:tree_code_note_control_exit()
        self.control_exit_seen.current = true
    end

    function Tr.TreeCodeFuncContext:tree_code_control_target(label)
        local region = self:tree_code_current_control_region()
        if region == nil then return nil end
        return region.targets[label_key(label)]
    end

    function Tr.TreeCodeFuncContext:tree_code_ensure_local(binding, source_ty, residence)
        local key = declare_binding_key(self, binding)
        local existing = self.locals_by_key[key]
        if existing ~= nil then return existing.id, existing.ty end
        local cty = code_ty(self, source_ty or binding.ty)
        local id = local_id_for_binding(self, binding)
        local local_ = Code.CodeLocal(id, binding.name, cty, residence or residence_for(self, binding, source_ty or binding.ty), origin_binding(binding))
        self.locals[#self.locals + 1] = local_
        self.locals_by_key[key] = Tr.TreeCodeLocalBinding(id, cty, source_ty or binding.ty)
        return id, cty
    end

    local function new_temp(ctx, prefix)
        return Code.CodeValueId("v:" .. sanitize(ctx.func_name) .. ":" .. sanitize(prefix or "tmp") .. tostring(ctx:tree_code_next_counter("value")))
    end

    local function new_inst_id(ctx, prefix)
        return Code.CodeInstId("inst:" .. sanitize(ctx.func_name) .. ":" .. sanitize(prefix or "i") .. tostring(ctx:tree_code_next_counter("inst")))
    end

    local function new_term_id(ctx, prefix)
        return Code.CodeTermId("term:" .. sanitize(ctx.func_name) .. ":" .. sanitize(prefix or "t") .. tostring(ctx:tree_code_next_counter("term")))
    end

    local function new_block_id(ctx, prefix)
        return Code.CodeBlockId("block:" .. sanitize(ctx.func_name) .. ":" .. sanitize(prefix or "b") .. tostring(ctx:tree_code_next_counter("block")))
    end

    local function append_inst(ctx, kind, origin)
        local block = ctx:tree_code_current_block()
        if block == nil then unsupported(ctx, kind, "instruction after terminator") end
        block.insts[#block.insts + 1] = Code.CodeInst(new_inst_id(ctx), kind, origin or origin_generated("tree_to_code"))
    end

    local function start_block(ctx, id, name, params, origin)
        if ctx:tree_code_has_current_block() then unsupported(ctx, id, "starting block before terminating current block") end
        ctx:tree_code_set_current_block(Tr.TreeCodeBlockBuilder(id, name, params or {}, {}, origin or origin_generated("block " .. tostring(name or "block"))))
    end

    local function terminate(ctx, kind, origin)
        if not ctx:tree_code_has_current_block() then unsupported(ctx, kind, "terminator without current block") end
        local term = Code.CodeTerm(new_term_id(ctx, "term"), kind, origin or origin_generated("terminator"))
        local block = ctx:tree_code_current_block()
        ctx:tree_code_append_block(Code.CodeBlock(block.id, block.name, block.params, block.insts, term, block.origin))
        ctx:tree_code_clear_current_block()
        return term
    end

    clone_map = function(t)
        local out = {}
        for k, v in pairs(t or {}) do out[k] = v end
        return out
    end

    replace_map = function(dst, src)
        for k in pairs(dst or {}) do dst[k] = nil end
        for k, v in pairs(src or {}) do dst[k] = v end
        return dst
    end

    local function save_bindings(ctx)
        return ctx:tree_code_save_bindings()
    end

    local function restore_bindings(ctx, saved)
        ctx:tree_code_restore_bindings(saved)
    end

    local function default_int_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftTrapOutOfRange)
    end

    local function default_float_mode()
        return Code.CodeFloatStrict
    end

    local function memory_access(ctx, mode, source_ty, code_type)
        return Code.CodeMemoryAccess(mode, code_type or code_ty(ctx, source_ty), align_of(ctx, source_ty), Code.CodeMayTrap, false, nil)
    end

    local function residence_for(ctx, binding, ty)
        if binding_is_addressed(ctx, binding) then return Code.CodeResidenceAddressed end
        if is_aggregate_code_ty(code_ty(ctx, ty or binding.ty)) then return Code.CodeResidenceAggregate end
        return Code.CodeResidenceValue
    end

    local function is_view_code_ty(ty)
        return ty:tree_code_is_view_type()
    end

    local function ensure_local(ctx, binding, ty, residence)
        return ctx:tree_code_ensure_local(binding, ty, residence)
    end

    local collect_address_taken_expr, collect_address_taken_place, collect_address_taken_stmts

    local function mark_addressed_place(place, out)
        place:tree_code_mark_addressed_place(out)
    end

    collect_address_taken_place = function(place, out)
        place:tree_code_collect_address_taken_place(out)
    end

    collect_address_taken_expr = function(expr, out)
        if expr == nil then return end
        expr:tree_code_collect_address_taken_expr(out)
    end

    collect_address_taken_stmts = function(stmts, out)
        for i = 1, #(stmts or {}) do
            stmts[i]:tree_code_collect_address_taken_stmt(out)
        end
        return out
    end

    function Bind.ValueRef:tree_code_mark_addressed_binding(out) end
    function Bind.ValueRefBinding:tree_code_mark_addressed_binding(out)
        out.addressed[binding_key(self.binding)] = true
    end

    function Tr.Place:tree_code_mark_addressed_place(out) end
    function Tr.PlaceRef:tree_code_mark_addressed_place(out) self.ref:tree_code_mark_addressed_binding(out) end
    function Tr.PlaceField:tree_code_mark_addressed_place(out) mark_addressed_place(self.base, out) end
    function Tr.PlaceDot:tree_code_mark_addressed_place(out) mark_addressed_place(self.base, out) end
    function Tr.PlaceIndex:tree_code_mark_addressed_place(out) self.base:tree_code_mark_addressed_index_base(out) end
    function Tr.IndexBase:tree_code_mark_addressed_index_base(out) end
    function Tr.IndexBasePlace:tree_code_mark_addressed_index_base(out) mark_addressed_place(self.base, out) end

    function Tr.Place:tree_code_collect_address_taken_place(out) end
    function Tr.PlaceDeref:tree_code_collect_address_taken_place(out) collect_address_taken_expr(self.base, out) end
    function Tr.PlaceField:tree_code_collect_address_taken_place(out) collect_address_taken_place(self.base, out) end
    function Tr.PlaceDot:tree_code_collect_address_taken_place(out) collect_address_taken_place(self.base, out) end
    function Tr.PlaceIndex:tree_code_collect_address_taken_place(out)
        self.base:tree_code_collect_address_taken_index_base(out)
        collect_address_taken_expr(self.index, out)
    end
    function Tr.IndexBase:tree_code_collect_address_taken_index_base(out) end
    function Tr.IndexBaseExpr:tree_code_collect_address_taken_index_base(out) collect_address_taken_expr(self.base, out) end
    function Tr.IndexBasePlace:tree_code_collect_address_taken_index_base(out) collect_address_taken_place(self.base, out) end
    function Tr.IndexBaseView:tree_code_collect_address_taken_index_base(out) collect_address_taken_expr(self.view.base, out) end

    function Tr.Expr:tree_code_collect_address_taken_expr(out) end
    function Tr.ExprAddrOf:tree_code_collect_address_taken_expr(out)
        mark_addressed_place(self.place, out)
        collect_address_taken_place(self.place, out)
    end
    function Tr.ExprUnary:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprDeref:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprLen:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprIsNull:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprBinary:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
    function Tr.ExprCompare:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
    function Tr.ExprLogic:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
    function Tr.ExprCast:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprMachineCast:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprLoad:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out) end
    function Tr.ExprAtomicLoad:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out) end
    function Tr.ExprAtomicRmw:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.value, out) end
    function Tr.ExprAtomicCas:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.expected, out); collect_address_taken_expr(self.replacement, out) end
    function Tr.ExprCall:tree_code_collect_address_taken_expr(out)
        collect_address_taken_expr(self.callee, out)
        for i = 1, #(self.args or {}) do collect_address_taken_expr(self.args[i], out) end
    end
    function Tr.ExprField:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.base, out) end
    function Tr.ExprDot:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.base, out) end
    function Tr.ExprIndex:tree_code_collect_address_taken_expr(out)
        self.base:tree_code_collect_address_taken_index_base(out)
        collect_address_taken_expr(self.index, out)
    end
    function Tr.ExprIntrinsic:tree_code_collect_address_taken_expr(out)
        for i = 1, #(self.args or {}) do collect_address_taken_expr(self.args[i], out) end
    end
    function Tr.ExprArray:tree_code_collect_address_taken_expr(out)
        for i = 1, #(self.elems or {}) do collect_address_taken_expr(self.elems[i], out) end
    end
    function Tr.ExprCtor:tree_code_collect_address_taken_expr(out)
        for i = 1, #(self.args or {}) do collect_address_taken_expr(self.args[i], out) end
    end
    function Tr.ExprAgg:tree_code_collect_address_taken_expr(out)
        for i = 1, #(self.fields or {}) do collect_address_taken_expr(self.fields[i].value, out) end
    end
    function Tr.ExprIf:tree_code_collect_address_taken_expr(out)
        collect_address_taken_expr(self.cond, out); collect_address_taken_expr(self.then_expr, out); collect_address_taken_expr(self.else_expr, out)
    end
    function Tr.ExprSelect:tree_code_collect_address_taken_expr(out)
        collect_address_taken_expr(self.cond, out); collect_address_taken_expr(self.then_expr, out); collect_address_taken_expr(self.else_expr, out)
    end
    function Tr.ExprSwitch:tree_code_collect_address_taken_expr(out)
        collect_address_taken_expr(self.value, out)
        for i = 1, #(self.arms or {}) do collect_address_taken_stmts(self.arms[i].body, out); collect_address_taken_expr(self.arms[i].result, out) end
        for i = 1, #(self.variant_arms or {}) do collect_address_taken_stmts(self.variant_arms[i].body, out); collect_address_taken_expr(self.variant_arms[i].result, out) end
        collect_address_taken_stmts(self.default_body or {}, out); collect_address_taken_expr(self.default_expr, out)
    end
    function Tr.ExprControl:tree_code_collect_address_taken_expr(out)
        collect_address_taken_stmts(self.region.entry.body, out)
        for i = 1, #(self.region.blocks or {}) do collect_address_taken_stmts(self.region.blocks[i].body, out) end
    end
    function Tr.ExprView:tree_code_collect_address_taken_expr(out) self.view:tree_code_collect_address_taken_view(out) end
    function Tr.ExprBlock:tree_code_collect_address_taken_expr(out)
        collect_address_taken_stmts(self.stmts or {}, out); collect_address_taken_expr(self.result, out)
    end

    function Tr.View:tree_code_collect_address_taken_view(out) end
    function Tr.ViewFromExpr:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.base, out) end
    function Tr.ViewContiguous:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out) end
    function Tr.ViewStrided:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out); collect_address_taken_expr(self.stride, out) end
    function Tr.ViewRestrided:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.stride, out) end
    function Tr.ViewWindow:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.start, out); collect_address_taken_expr(self.len, out) end
    function Tr.ViewRowBase:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.row_offset, out) end
    function Tr.ViewInterleaved:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out); collect_address_taken_expr(self.stride, out); collect_address_taken_expr(self.lane, out) end
    function Tr.ViewInterleavedView:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.stride, out); collect_address_taken_expr(self.lane, out) end

    function Tr.Stmt:tree_code_collect_address_taken_stmt(out) end
    function Tr.StmtLet:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.init, out) end
    function Tr.StmtVar:tree_code_collect_address_taken_stmt(out)
        out.mutable[binding_key(self.binding)] = true
        collect_address_taken_expr(self.init, out)
    end
    function Tr.StmtSet:tree_code_collect_address_taken_stmt(out) collect_address_taken_place(self.place, out); collect_address_taken_expr(self.value, out) end
    function Tr.StmtAtomicStore:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.value, out) end
    function Tr.StmtExpr:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.expr, out) end
    function Tr.StmtAssert:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.cond, out) end
    function Tr.StmtYieldValue:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.value, out) end
    function Tr.StmtReturnValue:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.value, out) end
    function Tr.StmtIf:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.cond, out); collect_address_taken_stmts(self.then_body, out); collect_address_taken_stmts(self.else_body, out) end
    function Tr.StmtSwitch:tree_code_collect_address_taken_stmt(out)
        collect_address_taken_expr(self.value, out)
        for j = 1, #(self.arms or {}) do collect_address_taken_stmts(self.arms[j].body, out) end
        for j = 1, #(self.variant_arms or {}) do collect_address_taken_stmts(self.variant_arms[j].body, out) end
        collect_address_taken_stmts(self.default_body or {}, out)
    end
    function Tr.StmtJump:tree_code_collect_address_taken_stmt(out)
        for j = 1, #(self.args or {}) do collect_address_taken_expr(self.args[j].value, out) end
    end
    function Tr.StmtJumpCont:tree_code_collect_address_taken_stmt(out)
        for j = 1, #(self.args or {}) do collect_address_taken_expr(self.args[j].value, out) end
    end
    function Tr.StmtControl:tree_code_collect_address_taken_stmt(out)
        collect_address_taken_stmts(self.region.entry.body, out)
        for j = 1, #(self.region.blocks or {}) do collect_address_taken_stmts(self.region.blocks[j].body, out) end
    end

    local lower_expr
    local lower_place
    local expr_as_place
    local lower_view_parts
    local lower_stmt
    local lower_stmt_body
    local lower_expr_if
    local lower_expr_switch
    local lower_expr_logic
    local lower_call
    local lower_control_region
    local lower_stmt_if
    local lower_stmt_switch

    local function lookup_binding(ctx, ref)
        return ref:tree_code_lookup_binding(ctx)
    end

    function Bind.ValueRef:tree_code_lookup_binding(ctx)
        unsupported(ctx, self, "non-binding value reference " .. class_name(self))
    end
    function Bind.ValueRefBinding:tree_code_lookup_binding(ctx)
        return self.binding, scoped_binding_key(ctx, self.binding)
    end

    local function load_place(ctx, place, source_ty, reason)
        local dst = new_temp(ctx, reason or "load")
        append_inst(ctx, Code.CodeInstLoad(dst, place, memory_access(ctx, Code.CodeMemoryRead, source_ty, code_ty(ctx, source_ty))), origin_generated(reason or "load"))
        return dst, code_ty(ctx, source_ty)
    end

    local function store_place(ctx, place, source_ty, value, origin)
        append_inst(ctx, Code.CodeInstStore(place, value, memory_access(ctx, Code.CodeMemoryWrite, source_ty, code_ty(ctx, source_ty))), origin or origin_generated("store"))
    end

    local function atomic_access(ctx, mode, source_ty, ordering)
        return Code.CodeMemoryAccess(mode, code_ty(ctx, source_ty), align_of(ctx, source_ty), Code.CodeMayTrap, true, ordering)
    end

    local function const_index(ctx, n, reason)
        local dst = new_temp(ctx, reason or "index_const")
        append_inst(ctx, Code.CodeInstConst(dst, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(n)))), origin_generated(reason or "index const"))
        return dst, Code.CodeTyIndex
    end

    local function as_index_value(ctx, value, value_ty, reason)
        if value_ty == Code.CodeTyIndex then return value end
        local op = value_ty:tree_code_index_cast_op()
        if op == nil then unsupported(ctx, value_ty, "non-integer index value " .. class_name(value_ty)) end
        local dst = new_temp(ctx, reason or "to_index")
        append_inst(ctx, Code.CodeInstCast(dst, op, value_ty, Code.CodeTyIndex, value), origin_generated(reason or "index cast"))
        return dst
    end

    function Code.CodeType:tree_code_index_cast_op() return nil end
    function Code.CodeTyInt:tree_code_index_cast_op()
        if self.bits < 64 then
            return self.signedness == Code.CodeSigned and Core.MachineCastSextend or Core.MachineCastUextend
        end
        return Core.MachineCastBitcast
    end
    function Code.CodeTyBool8:tree_code_index_cast_op() return Core.MachineCastUextend end

    local function lower_index_expr_for_view(ctx, expr, reason)
        local value, ty = lower_expr(ctx, expr)
        return as_index_value(ctx, value, ty, reason)
    end

    local function index_mul(ctx, lhs, rhs, reason)
        local dst = new_temp(ctx, reason)
        append_inst(ctx, Code.CodeInstBinary(dst, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), lhs, rhs), origin_generated(reason))
        return dst
    end

    local function data_offset(ctx, view, data, index, elem, reason)
        local ptr_ty = Code.CodeTyDataPtr(code_ty(ctx, elem))
        local dst = new_temp(ctx, reason)
        local elem_size = size_of(ctx, elem)
        if elem_size == nil then unsupported(ctx, view, "view element without known size") end
        append_inst(ctx, Code.CodeInstPtrOffset(dst, ptr_ty, data, index, elem_size, 0), origin_generated(reason))
        return dst
    end

    function Tr.View:lower_tree_view_parts_to_code(ctx)
        unsupported(ctx, self, "view form " .. class_name(self))
    end
    function Tr.ViewContiguous:lower_tree_view_parts_to_code(ctx)
        local data = lower_expr(ctx, self.data)
        local len = lower_index_expr_for_view(ctx, self.len, "view_len")
        local stride = const_index(ctx, 1, "view_stride")
        return data, len, stride
    end
    function Tr.ViewStrided:lower_tree_view_parts_to_code(ctx)
        local data = lower_expr(ctx, self.data)
        local len = lower_index_expr_for_view(ctx, self.len, "view_len")
        local stride = lower_index_expr_for_view(ctx, self.stride, "view_stride")
        return data, len, stride
    end
    function Tr.ViewFromExpr:lower_tree_view_parts_to_code(ctx)
        return source_access_base(expr_type(self.base)):tree_code_lower_view_from_expr(ctx, self)
    end
    function Ty.Type:tree_code_lower_view_from_expr(ctx, view)
        unsupported(ctx, view, "view-from expression type " .. class_name(self))
    end
    function Ty.TPtr:tree_code_lower_view_from_expr(ctx, view)
        local data = lower_expr(ctx, view.base)
        local len = const_index(ctx, 1, "view_len")
        local stride = const_index(ctx, 1, "view_stride")
        return data, len, stride
    end
    function Ty.TView:tree_code_lower_view_from_expr(ctx, view)
        local base = lower_expr(ctx, view.base)
        local data = new_temp(ctx, "view_data")
        local len = new_temp(ctx, "view_len")
        local stride = new_temp(ctx, "view_stride")
        append_inst(ctx, Code.CodeInstViewData(data, base), origin_generated("view data"))
        append_inst(ctx, Code.CodeInstViewLen(len, base), origin_generated("view len"))
        append_inst(ctx, Code.CodeInstViewStride(stride, base), origin_generated("view stride"))
        return data, len, stride
    end
    function Tr.ViewRestrided:lower_tree_view_parts_to_code(ctx)
        local data, len = lower_view_parts(ctx, self.base)
        local stride = lower_index_expr_for_view(ctx, self.stride, "view_stride")
        return data, len, stride
    end
    function Tr.ViewWindow:lower_tree_view_parts_to_code(ctx)
        local data, _, stride = lower_view_parts(ctx, self.base)
        local start = lower_index_expr_for_view(ctx, self.start, "view_window_start")
        local scaled = index_mul(ctx, start, stride, "view_window_start")
        local window_data = data_offset(ctx, self, data, scaled, self.elem, "view_window_data")
        local len = lower_index_expr_for_view(ctx, self.len, "view_window_len")
        return window_data, len, stride
    end
    function Tr.ViewRowBase:lower_tree_view_parts_to_code(ctx)
        local data, len, stride = lower_view_parts(ctx, self.base)
        local row = lower_index_expr_for_view(ctx, self.row_offset, "view_row_base")
        local scaled = index_mul(ctx, row, stride, "view_row_base_offset")
        return data_offset(ctx, self, data, scaled, self.elem, "view_row_base_data"), len, stride
    end
    function Tr.ViewInterleaved:lower_tree_view_parts_to_code(ctx)
        local data = lower_expr(ctx, self.data)
        local len = lower_index_expr_for_view(ctx, self.len, "view_len")
        local stride = lower_index_expr_for_view(ctx, self.stride, "view_stride")
        local lane = lower_index_expr_for_view(ctx, self.lane, "view_lane")
        return data_offset(ctx, self, data, lane, self.elem, "view_interleaved_data"), len, stride
    end
    function Tr.ViewInterleavedView:lower_tree_view_parts_to_code(ctx)
        local data, len, base_stride = lower_view_parts(ctx, self.base)
        local stride_factor = lower_index_expr_for_view(ctx, self.stride, "view_stride")
        local lane = lower_index_expr_for_view(ctx, self.lane, "view_lane")
        local lane_offset = index_mul(ctx, lane, base_stride, "view_interleaved_lane")
        local stride = index_mul(ctx, base_stride, stride_factor, "view_interleaved_stride")
        return data_offset(ctx, self, data, lane_offset, self.elem, "view_interleaved_data"), len, stride
    end

    lower_view_parts = function(ctx, view)
        return view:lower_tree_view_parts_to_code(ctx)
    end

    function Bind.BindingClass:tree_code_lookup_value(ctx, binding, ref)
        unsupported(ctx, ref, "unbound scalar reference `" .. tostring(binding.name) .. "`")
    end
    function Bind.BindingClassGlobalFunc:tree_code_lookup_value(ctx, binding, ref)
        local ptr_ty = code_ty(ctx, binding.ty)
        local dst = new_temp(ctx, "fnref")
        append_inst(ctx, Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefFunc(code_func_id(self.item_name)), ptr_ty), origin_binding(binding))
        return dst, ptr_ty
    end
    function Bind.BindingClassExtern:tree_code_lookup_value(ctx, binding, ref)
        local ptr_ty = code_ty(ctx, binding.ty)
        local dst = new_temp(ctx, "externref")
        append_inst(ctx, Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefExtern(code_extern_id(binding.name)), ptr_ty), origin_binding(binding))
        return dst, ptr_ty
    end
    function Bind.BindingClassGlobalConst:tree_code_lookup_value(ctx, binding, ref)
        local gid = code_global_id(self.module_name, self.item_name)
        return load_place(ctx, Code.CodePlaceGlobal(gid, code_ty(ctx, binding.ty)), binding.ty, "load_global_" .. binding.name)
    end
    function Bind.BindingClassGlobalStatic:tree_code_lookup_value(ctx, binding, ref)
        local gid = code_global_id(self.module_name, self.item_name)
        return load_place(ctx, Code.CodePlaceGlobal(gid, code_ty(ctx, binding.ty)), binding.ty, "load_global_" .. binding.name)
    end

    function Ty.Type:tree_code_call_sig_id(ctx)
        unsupported(ctx, self, "non-callable type " .. class_name(self))
    end
    function Ty.TFunc:tree_code_call_sig_id(ctx)
        return CodeType.ensure_type_sig(ctx.module, self.params, self.result)
    end
    function Ty.TClosure:tree_code_call_sig_id(ctx)
        return CodeType.ensure_type_sig(ctx.module, self.params, self.result)
    end

    function Tr.Expr:tree_code_direct_call_target() return nil end
    function Tr.ExprRef:tree_code_direct_call_target()
        return self.ref:tree_code_direct_call_target()
    end
    function Bind.ValueRef:tree_code_direct_call_target() return nil end
    function Bind.ValueRefBinding:tree_code_direct_call_target()
        return self.binding.class:tree_code_direct_call_target(self.binding)
    end
    function Bind.BindingClass:tree_code_direct_call_target(binding) return nil end
    function Bind.BindingClassGlobalFunc:tree_code_direct_call_target(binding)
        return Code.CodeCallDirect(code_func_id(self.item_name))
    end
    function Bind.BindingClassExtern:tree_code_direct_call_target(binding)
        return Code.CodeCallExtern(code_extern_id(binding.name))
    end
    function Ty.Type:tree_code_indirect_call_target(callee, sig)
        return Code.CodeCallIndirect(callee, sig)
    end
    function Ty.TClosure:tree_code_indirect_call_target(callee, sig)
        return Code.CodeCallClosure(callee, sig)
    end

    function Ty.Type:tree_code_lower_field_base_place(ctx, base)
        return expr_as_place(ctx, base), self
    end
    function Ty.TPtr:tree_code_lower_field_base_place(ctx, base)
        local addr = lower_expr(ctx, base)
        return Code.CodePlaceDeref(addr, code_ty(ctx, self.elem), align_of(ctx, self.elem)), self.elem
    end
    function Sem.FieldRef:tree_code_require_lowered_field(ctx)
        unsupported(ctx, self, "field access before sem_layout_resolve")
    end
    function Sem.FieldByOffset:tree_code_require_lowered_field(ctx) end

    function Tr.IndexBase:tree_code_lower_index_base_place(ctx, idx, elem_ty)
        unsupported(ctx, self, "index base " .. class_name(self))
    end
    function Tr.IndexBaseExpr:tree_code_lower_index_base_place(ctx, idx, elem_ty)
        return source_access_base(expr_type(self.base)):tree_code_lower_expr_index_base(ctx, self.base, idx, elem_ty)
    end
    function Tr.IndexBasePlace:tree_code_lower_index_base_place(ctx, idx, elem_ty)
        return source_access_base(place_type(self.base)):tree_code_lower_place_index_base(ctx, self.base, idx, elem_ty)
    end
    function Tr.IndexBaseView:tree_code_lower_index_base_place(ctx, idx, elem_ty)
        local data, _, stride = lower_view_parts(ctx, self.view)
        local scaled = new_temp(ctx, "view_index_scaled")
        append_inst(ctx, Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
        return Code.CodePlaceDeref(data, code_ty(ctx, elem_ty), align_of(ctx, elem_ty)), scaled
    end

    function Ty.Type:tree_code_lower_expr_index_base(ctx, base, idx, elem_ty)
        if is_aggregate_code_ty(code_ty(ctx, self)) then return expr_as_place(ctx, base), idx end
        unsupported(ctx, base, "index expression base type " .. class_name(self))
    end
    function Ty.TPtr:tree_code_lower_expr_index_base(ctx, base, idx, elem_ty)
        local addr = lower_expr(ctx, base)
        return Code.CodePlaceDeref(addr, code_ty(ctx, elem_ty), align_of(ctx, elem_ty)), idx
    end
    function Ty.TView:tree_code_lower_expr_index_base(ctx, base, idx, elem_ty)
        local view = lower_expr(ctx, base)
        local data = new_temp(ctx, "view_index_data")
        local stride = new_temp(ctx, "view_index_stride")
        local scaled = new_temp(ctx, "view_index_scaled")
        append_inst(ctx, Code.CodeInstViewData(data, view), origin_generated("view index data"))
        append_inst(ctx, Code.CodeInstViewStride(stride, view), origin_generated("view index stride"))
        append_inst(ctx, Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
        return Code.CodePlaceDeref(data, code_ty(ctx, elem_ty), align_of(ctx, elem_ty)), scaled
    end
    function Ty.TSlice:tree_code_lower_expr_index_base(ctx, base, idx, elem_ty)
        local slice = lower_expr(ctx, base)
        local data = new_temp(ctx, "slice_index_data")
        append_inst(ctx, Code.CodeInstSliceData(data, slice), origin_generated("slice index data"))
        return Code.CodePlaceDeref(data, code_ty(ctx, elem_ty), align_of(ctx, elem_ty)), idx
    end
    function Ty.TArray:tree_code_lower_expr_index_base(ctx, base, idx, elem_ty)
        return expr_as_place(ctx, base), idx
    end

    function Ty.Type:tree_code_lower_place_index_base(ctx, base, idx, elem_ty)
        return lower_place(ctx, base), idx
    end
    function Ty.TView:tree_code_lower_place_index_base(ctx, base, idx, elem_ty)
        local view = load_place(ctx, lower_place(ctx, base), self, "view_index")
        local data = new_temp(ctx, "view_index_data")
        local stride = new_temp(ctx, "view_index_stride")
        local scaled = new_temp(ctx, "view_index_scaled")
        append_inst(ctx, Code.CodeInstViewData(data, view), origin_generated("view index data"))
        append_inst(ctx, Code.CodeInstViewStride(stride, view), origin_generated("view index stride"))
        append_inst(ctx, Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
        return Code.CodePlaceDeref(data, code_ty(ctx, elem_ty), align_of(ctx, elem_ty)), scaled
    end

    function Bind.BindingClass:tree_code_global_place(ctx, binding) return nil end
    function Bind.BindingClassGlobalConst:tree_code_global_place(ctx, binding)
        return Code.CodePlaceGlobal(code_global_id(self.module_name, self.item_name), code_ty(ctx, binding.ty))
    end
    function Bind.BindingClassGlobalStatic:tree_code_global_place(ctx, binding)
        return Code.CodePlaceGlobal(code_global_id(self.module_name, self.item_name), code_ty(ctx, binding.ty))
    end

    function Ty.Type:tree_code_lower_place_field_base(ctx, base)
        return lower_place(ctx, base)
    end
    function Ty.TPtr:tree_code_lower_place_field_base(ctx, base)
        local ref = base:tree_code_ref_for_ptr_field()
        if ref == nil then return lower_place(ctx, base) end
        local addr = lower_expr(ctx, Tr.ExprRef(Tr.ExprTyped(self), ref))
        return Code.CodePlaceDeref(addr, code_ty(ctx, self.elem), align_of(ctx, self.elem))
    end
    function Tr.Place:tree_code_ref_for_ptr_field() return nil end
    function Tr.PlaceRef:tree_code_ref_for_ptr_field() return self.ref end

    function Tr.Expr:tree_code_as_place(ctx)
        unsupported(ctx, self, "expression is not addressable " .. class_name(self))
    end
    function Tr.ExprRef:tree_code_as_place(ctx)
        return lower_place(ctx, Tr.PlaceRef(Tr.PlaceTyped(expr_type(self)), self.ref))
    end
    function Tr.ExprDeref:tree_code_as_place(ctx)
        return Code.CodePlaceDeref(lower_expr(ctx, self.value), code_ty(ctx, expr_type(self)), align_of(ctx, expr_type(self)))
    end
    function Tr.ExprField:tree_code_as_place(ctx)
        return lower_field_place(ctx, self.base, self.field)
    end
    function Tr.ExprIndex:tree_code_as_place(ctx)
        return lower_index_place(ctx, self.base, self.index, expr_type(self))
    end

    function Core.Literal:lower_tree_literal_to_code(ctx, source_ty)
        local ty = code_ty(ctx, source_ty)
        local dst = new_temp(ctx, "lit")
        append_inst(ctx, Code.CodeInstConst(dst, Code.CodeConstLiteral(ty, self)), origin_generated("literal"))
        return Tr.TreeCodeExprResult(dst, ty)
    end
    function Core.LitString:lower_tree_literal_to_code(ctx, source_ty)
        local ty = code_ty(ctx, source_ty)
        local elem_ty = u8_code_ty()
        local data_id, len_bytes = fresh_string_data(ctx, self.bytes)
        local data = new_temp(ctx, "str_data")
        append_inst(ctx, Code.CodeInstGlobalRef(data, Code.CodeGlobalRefData(data_id), Code.CodeTyDataPtr(elem_ty)), origin_generated("string literal data ref"))
        local len = new_temp(ctx, "str_len")
        append_inst(ctx, Code.CodeInstConst(len, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(len_bytes)))), origin_generated("string literal length"))
        local dst = new_temp(ctx, "str")
        append_inst(ctx, Code.CodeInstSliceMake(dst, elem_ty, data, len), origin_generated("string literal slice"))
        return Tr.TreeCodeExprResult(dst, ty)
    end

    function Ty.Type:tree_code_is_ptr_type() return false end
    function Ty.TPtr:tree_code_is_ptr_type() return true end

    function Ty.Type:lower_tree_len_to_code(ctx, expr)
        unsupported(ctx, expr, "len of non-array/view")
    end
    function Ty.TArray:lower_tree_len_to_code(ctx, expr)
        return self.count:lower_tree_array_len_to_code(ctx, expr)
    end
    function Ty.ArrayLen:lower_tree_array_len_to_code(ctx, expr)
        unsupported(ctx, expr, "len of non-constant array")
    end
    function Ty.ArrayLenConst:lower_tree_array_len_to_code(ctx, expr)
        return Tr.TreeCodeExprResult(const_index(ctx, self.count, "array_len"), Code.CodeTyIndex)
    end
    function Ty.TView:lower_tree_len_to_code(ctx, expr)
        local view = lower_expr(ctx, expr.value)
        local dst = new_temp(ctx, "view_len")
        append_inst(ctx, Code.CodeInstViewLen(dst, view), origin_generated("view len"))
        return Tr.TreeCodeExprResult(dst, Code.CodeTyIndex)
    end

    local function lookup_value(ctx, ref)
        local binding, key = lookup_binding(ctx, ref)
        local local_info = ctx.locals_by_key[key]
        if local_info ~= nil then
            return load_place(ctx, Code.CodePlaceLocal(local_info.id, local_info.ty), binding.ty, "load_" .. binding.name)
        end
        local id = ctx.bindings[key]
        if id ~= nil then return id, code_ty(ctx, binding.ty) end
        return binding.class:tree_code_lookup_value(ctx, binding, ref)
    end

    local function call_sig_id(ctx, fn_ty)
        return fn_ty:tree_code_call_sig_id(ctx)
    end

    lower_call = function(ctx, expr)
        local fn_ty = expr_type(expr.callee)
        local sig = call_sig_id(ctx, fn_ty)
        local args = {}
        for i = 1, #(expr.args or {}) do args[i] = lower_expr(ctx, expr.args[i]) end
        local target
        target = expr.callee:tree_code_direct_call_target()
        if target == nil then
            local callee = lower_expr(ctx, expr.callee)
            target = fn_ty:tree_code_indirect_call_target(callee, sig)
        end
        local result_ty = code_ty(ctx, expr_type(expr))
        local dst = nil
        if result_ty ~= Code.CodeTyVoid then dst = new_temp(ctx, "call") end
        append_inst(ctx, Code.CodeInstCall(dst, target, sig, args), origin_generated("call"))
        return dst, result_ty
    end

    local function lower_field_base_place(ctx, base, base_ty)
        base_ty = source_access_base(base_ty)
        return base_ty:tree_code_lower_field_base_place(ctx, base)
    end

    local function lower_field_place(ctx, base, field)
        field:tree_code_require_lowered_field(ctx)
        local base_ty = expr_type(base)
        local base_place = lower_field_base_place(ctx, base, base_ty)
        local field_layout = layout_of(ctx, field.ty)
        return Code.CodePlaceField(base_place, field, code_ty(ctx, field.ty), field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil)
    end

    local function lower_index_place(ctx, base, index, elem_ty)
        local idx, idx_ty = lower_expr(ctx, index)
        idx = as_index_value(ctx, idx, idx_ty, "index")
        local elem_size = size_of(ctx, elem_ty)
        if elem_size == nil then unsupported(ctx, base, "index element without known size") end
        local base_place
        base_place, idx = base:tree_code_lower_index_base_place(ctx, idx, elem_ty)
        return Code.CodePlaceIndex(base_place, idx, code_ty(ctx, elem_ty), elem_size)
    end

    function Tr.PlaceRef:lower_tree_place_to_code(input)
        local ctx = input
        local binding, key = lookup_binding(ctx, self.ref)
        local global_place = binding.class:tree_code_global_place(ctx, binding)
        if global_place ~= nil then return Tr.TreeCodePlaceResult(global_place) end
        local local_info = ctx.locals_by_key[key]
        if local_info == nil then
            if ctx.addressed[key] or ctx.mutable[key] or is_aggregate_code_ty(code_ty(ctx, binding.ty)) then
                ensure_local(ctx, binding, binding.ty)
                local_info = ctx.locals_by_key[key]
            else
                unsupported(ctx, self, "address/store of value-resident binding `" .. tostring(binding.name) .. "`")
            end
        end
        return Tr.TreeCodePlaceResult(Code.CodePlaceLocal(local_info.id, local_info.ty))
    end

    function Tr.PlaceDeref:lower_tree_place_to_code(input)
        local ctx = input
        local addr = lower_expr(ctx, self.base)
        local ty = place_type(self)
        return Tr.TreeCodePlaceResult(Code.CodePlaceDeref(addr, code_ty(ctx, ty), align_of(ctx, ty)))
    end

    function Tr.PlaceField:lower_tree_place_to_code(input)
        local ctx = input
        self.field:tree_code_require_lowered_field(ctx)
        local base_ty = source_access_base(place_type(self.base))
        local base_place = base_ty:tree_code_lower_place_field_base(ctx, self.base)
        local field_layout = layout_of(ctx, self.field.ty)
        return Tr.TreeCodePlaceResult(Code.CodePlaceField(base_place, self.field, code_ty(ctx, self.field.ty), self.field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil))
    end

    function Tr.PlaceIndex:lower_tree_place_to_code(input)
        local ctx = input
        return Tr.TreeCodePlaceResult(lower_index_place(ctx, self.base, self.index, place_type(self)))
    end

    function Tr.PlaceDot:lower_tree_place_to_code(input)
        unsupported(input, self, "dot place before sem_layout_resolve")
    end

    lower_place = function(ctx, place)
        local result = place:lower_tree_place_to_code(ctx)
        return result.place
    end

    expr_as_place = function(ctx, expr)
        return expr:tree_code_as_place(ctx)
    end

    function Tr.ExprLit:lower_tree_expr_to_code(input)
        local ctx = input
        return self.value:lower_tree_literal_to_code(ctx, expr_type(self))
    end

    function Tr.ExprRef:lower_tree_expr_to_code(input)
        local value, ty = lookup_value(input, self.ref)
        return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprUnary:lower_tree_expr_to_code(input)
        local ctx = input
            local value = lower_expr(ctx, self.value)
            local ty = code_ty(ctx, expr_type(self))
            local dst = new_temp(ctx, "unary")
            append_inst(ctx, Code.CodeInstUnary(dst, self.op, ty, value), origin_generated("unary"))
            return Tr.TreeCodeExprResult(dst, ty)
    end

    function Tr.ExprBinary:lower_tree_expr_to_code(input)
        local ctx = input
            local lhs, lhs_ty = lower_expr(ctx, self.lhs)
            local rhs, rhs_ty = lower_expr(ctx, self.rhs)
            local ty = code_ty(ctx, expr_type(self))
            local dst = new_temp(ctx, "bin")
            local lhs_src_ty = source_access_base(expr_type(self.lhs))
            local rhs_src_ty = source_access_base(expr_type(self.rhs))
            local lhs_is_ptr = lhs_src_ty:tree_code_is_ptr_type()
            local rhs_is_ptr = rhs_src_ty:tree_code_is_ptr_type()
            if self.op == Core.BinAdd and (lhs_is_ptr or rhs_is_ptr) then
                local ptr_value, index_value, index_ty, elem_ty
                if lhs_is_ptr then
                    ptr_value, index_value, index_ty, elem_ty = lhs, rhs, rhs_ty, lhs_src_ty.elem
                else
                    ptr_value, index_value, index_ty, elem_ty = rhs, lhs, lhs_ty, rhs_src_ty.elem
                end
                local index = as_index_value(ctx, index_value, index_ty, "ptr_add_index")
                local elem_size = size_of(ctx, elem_ty)
                if elem_size == nil then unsupported(ctx, self, "pointer arithmetic element without known size") end
                append_inst(ctx, Code.CodeInstPtrOffset(dst, ty, ptr_value, index, elem_size, 0), origin_generated("pointer add"))
            elseif self.op == Core.BinSub and lhs_is_ptr and not rhs_is_ptr then
                local index = as_index_value(ctx, rhs, rhs_ty, "ptr_sub_index")
                local zero = const_index(ctx, 0, "ptr_sub_zero")
                local neg = new_temp(ctx, "ptr_sub_neg")
                append_inst(ctx, Code.CodeInstBinary(neg, Core.BinSub, Code.CodeTyIndex, default_int_semantics(), zero, index), origin_generated("pointer subtract index"))
                local elem_size = size_of(ctx, lhs_src_ty.elem)
                if elem_size == nil then unsupported(ctx, self, "pointer arithmetic element without known size") end
                append_inst(ctx, Code.CodeInstPtrOffset(dst, ty, lhs, neg, elem_size, 0), origin_generated("pointer subtract"))
            else
                if is_float_code_ty(ty) then
                    append_inst(ctx, Code.CodeInstFloatBinary(dst, self.op, ty, default_float_mode(), lhs, rhs), origin_generated("float binary"))
                else
                    append_inst(ctx, Code.CodeInstBinary(dst, self.op, ty, default_int_semantics(), lhs, rhs), origin_generated("binary"))
                end
            end
            return Tr.TreeCodeExprResult(dst, ty)
    end

    function Tr.ExprCompare:lower_tree_expr_to_code(input)
        local ctx = input
            local lhs = lower_expr(ctx, self.lhs)
            local rhs = lower_expr(ctx, self.rhs)
            local operand_ty = code_ty(ctx, expr_type(self.lhs))
            local dst = new_temp(ctx, "cmp")
            append_inst(ctx, Code.CodeInstCompare(dst, self.op, operand_ty, lhs, rhs), origin_generated("compare"))
            return Tr.TreeCodeExprResult(dst, Code.CodeTyBool8)
    end

    function Tr.ExprLogic:lower_tree_expr_to_code(input)
        local value, ty = lower_expr_logic(input, self)
        return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprIf:lower_tree_expr_to_code(input)
        local value, ty = lower_expr_if(input, self)
        return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprSwitch:lower_tree_expr_to_code(input)
        local value, ty = lower_expr_switch(input, self)
        return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprControl:lower_tree_expr_to_code(input)
        local value, ty = lower_control_region(input, self.region, true)
        return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprBlock:lower_tree_expr_to_code(input)
        local ctx = input
            local saved = save_bindings(ctx)
            lower_stmt_body(ctx, self.stmts or {})
            if not ctx:tree_code_has_current_block() then unsupported(ctx, self, "expression block body terminated before result") end
            local value, ty = lower_expr(ctx, self.result)
            restore_bindings(ctx, saved)
            return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprMachineCast:lower_tree_expr_to_code(input)
        local ctx = input
            local value, from = lower_expr(ctx, self.value)
            local to = code_ty(ctx, self.ty or expr_type(self))
            local dst = new_temp(ctx, "cast")
            append_inst(ctx, Code.CodeInstCast(dst, self.op, from, to, value), origin_generated("cast"))
            return Tr.TreeCodeExprResult(dst, to)
    end

    function Tr.ExprCast:lower_tree_expr_to_code(input)
        unsupported(input, self, "surface cast after typechecking")
    end

    function Tr.ExprSelect:lower_tree_expr_to_code(input)
        local ctx = input
            local cond = lower_expr(ctx, self.cond)
            local then_value = lower_expr(ctx, self.then_expr)
            local else_value = lower_expr(ctx, self.else_expr)
            local ty = code_ty(ctx, expr_type(self))
            local dst = new_temp(ctx, "select")
            append_inst(ctx, Code.CodeInstSelect(dst, ty, cond, then_value, else_value), origin_generated("select"))
            return Tr.TreeCodeExprResult(dst, ty)
    end

    function Tr.ExprAddrOf:lower_tree_expr_to_code(input)
        local ctx = input
            local place = lower_place(ctx, self.place)
            local ptr_ty = code_ty(ctx, expr_type(self))
            local dst = new_temp(ctx, "addr")
            append_inst(ctx, Code.CodeInstAddrOf(dst, ptr_ty, place), origin_generated("address of"))
            return Tr.TreeCodeExprResult(dst, ptr_ty)
    end

    function Tr.ExprIntrinsic:lower_tree_expr_to_code(input)
        local ctx = input
            local args = {}
            for i = 1, #(self.args or {}) do args[i] = lower_expr(ctx, self.args[i]) end
            local ty = code_ty(ctx, expr_type(self))
            local dst = ty ~= Code.CodeTyVoid and new_temp(ctx, "intrin") or nil
            append_inst(ctx, Code.CodeInstIntrinsic(dst, self.op, ty, args), origin_generated("intrinsic"))
            return Tr.TreeCodeExprResult(dst, ty)
    end

    function Tr.ExprAgg:lower_tree_expr_to_code(input)
        local ctx = input
            local ty = code_ty(ctx, self.ty or expr_type(self))
            local fields = {}
            for i = 1, #(self.fields or {}) do
                local fi = self.fields[i]
                local value = lower_expr(ctx, fi.value)
                fields[#fields + 1] = Code.CodeFieldValue(Sem.FieldByOffset(fi.name, fi.offset or 0, expr_type(fi.value), Host.HostRepOpaque("tree_to_code.aggregate")), value)
            end
            local dst = new_temp(ctx, "agg")
            append_inst(ctx, Code.CodeInstAggregate(dst, ty, fields), origin_generated("aggregate"))
            return Tr.TreeCodeExprResult(dst, ty)
    end

    function Tr.ExprArray:lower_tree_expr_to_code(input)
        local ctx = input
            local ty = code_ty(ctx, expr_type(self))
            local elems = {}
            for i = 1, #(self.elems or {}) do elems[#elems + 1] = Code.CodeArrayValue(i - 1, lower_expr(ctx, self.elems[i])) end
            local dst = new_temp(ctx, "array")
            append_inst(ctx, Code.CodeInstArray(dst, ty, elems), origin_generated("array"))
            return Tr.TreeCodeExprResult(dst, ty)
    end

    function Tr.ExprView:lower_tree_expr_to_code(input)
        local ctx = input
            local data, len, stride = lower_view_parts(ctx, self.view)
            local ty = code_ty(ctx, expr_type(self))
            local dst = new_temp(ctx, "view")
            append_inst(ctx, Code.CodeInstViewMake(dst, ty.elem, data, len, stride), origin_generated("view"))
            return Tr.TreeCodeExprResult(dst, ty)
    end

    function Tr.ExprLen:lower_tree_expr_to_code(input)
        local ctx = input
        return source_access_base(expr_type(self.value)):lower_tree_len_to_code(ctx, self)
    end

    function Tr.ExprSizeOf:lower_tree_expr_to_code(input)
        local ctx = input
            local n = size_of(ctx, self.ty)
            if n == nil then unsupported(ctx, self, "sizeof type without known layout") end
            return Tr.TreeCodeExprResult(const_index(ctx, n, "sizeof"), Code.CodeTyIndex)
    end

    function Tr.ExprAlignOf:lower_tree_expr_to_code(input)
        return Tr.TreeCodeExprResult(const_index(input, align_of(input, self.ty), "alignof"), Code.CodeTyIndex)
    end

    function Tr.ExprIsNull:lower_tree_expr_to_code(input)
        local ctx = input
            local value, ty = lower_expr(ctx, self.value)
            local null_value = new_temp(ctx, "null_cmp")
            append_inst(ctx, Code.CodeInstConst(null_value, Code.CodeConstNull(ty)), origin_generated("null compare literal"))
            local dst = new_temp(ctx, "is_null")
            append_inst(ctx, Code.CodeInstCompare(dst, Core.CmpEq, ty, value, null_value), origin_generated("is null"))
            return Tr.TreeCodeExprResult(dst, Code.CodeTyBool8)
    end

    function Tr.ExprCall:lower_tree_expr_to_code(input)
        local value, ty = lower_call(input, self)
        return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprDeref:lower_tree_expr_to_code(input)
        local ctx = input
            local place = Code.CodePlaceDeref(lower_expr(ctx, self.value), code_ty(ctx, expr_type(self)), align_of(ctx, expr_type(self)))
            local value, ty = load_place(ctx, place, expr_type(self), "deref")
            return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprField:lower_tree_expr_to_code(input)
        local ctx = input
        local value, ty = load_place(ctx, lower_field_place(ctx, self.base, self.field), expr_type(self), "field")
        return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprIndex:lower_tree_expr_to_code(input)
        local ctx = input
        local value, ty = load_place(ctx, lower_index_place(ctx, self.base, self.index, expr_type(self)), expr_type(self), "index")
        return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprLoad:lower_tree_expr_to_code(input)
        local ctx = input
            local place = Code.CodePlaceDeref(lower_expr(ctx, self.addr), code_ty(ctx, self.ty or expr_type(self)), align_of(ctx, self.ty or expr_type(self)))
            local value, ty = load_place(ctx, place, self.ty or expr_type(self), "load")
            return Tr.TreeCodeExprResult(value, ty)
    end

    function Tr.ExprAtomicLoad:lower_tree_expr_to_code(input)
        local ctx = input
            local ty = self.ty or expr_type(self)
            local place = Code.CodePlaceDeref(lower_expr(ctx, self.addr), code_ty(ctx, ty), align_of(ctx, ty))
            local dst = new_temp(ctx, "atomic_load")
            append_inst(ctx, Code.CodeInstAtomicLoad(dst, place, atomic_access(ctx, Code.CodeMemoryRead, ty, self.ordering), self.ordering), origin_generated("atomic load"))
            return Tr.TreeCodeExprResult(dst, code_ty(ctx, ty))
    end

    function Tr.ExprAtomicRmw:lower_tree_expr_to_code(input)
        local ctx = input
            local ty = self.ty or expr_type(self)
            local place = Code.CodePlaceDeref(lower_expr(ctx, self.addr), code_ty(ctx, ty), align_of(ctx, ty))
            local value = lower_expr(ctx, self.value)
            local dst = new_temp(ctx, "atomic_rmw")
            append_inst(ctx, Code.CodeInstAtomicRmw(dst, self.op, place, value, atomic_access(ctx, Code.CodeMemoryReadWrite, ty, self.ordering), self.ordering), origin_generated("atomic rmw"))
            return Tr.TreeCodeExprResult(dst, code_ty(ctx, ty))
    end

    function Tr.ExprAtomicCas:lower_tree_expr_to_code(input)
        local ctx = input
            local ty = self.ty or expr_type(self)
            local place = Code.CodePlaceDeref(lower_expr(ctx, self.addr), code_ty(ctx, ty), align_of(ctx, ty))
            local expected = lower_expr(ctx, self.expected)
            local replacement = lower_expr(ctx, self.replacement)
            local dst = new_temp(ctx, "atomic_cas")
            append_inst(ctx, Code.CodeInstAtomicCas(dst, place, expected, replacement, atomic_access(ctx, Code.CodeMemoryReadWrite, ty, self.ordering), self.ordering), origin_generated("atomic cas"))
            return Tr.TreeCodeExprResult(dst, code_ty(ctx, ty))
    end

    function Tr.ExprCtor:lower_tree_expr_to_code(input)
        local ctx = input
            if #(self.args or {}) > 1 then unsupported(ctx, self, "multi-argument variant constructor `" .. tostring(self.type_name) .. "." .. tostring(self.variant_name) .. "`") end
            local def = variant_def(ctx, self.type_name)
            local variant = def and def.variants[self.variant_name] or nil
            if variant == nil then unsupported(ctx, self, "unknown variant constructor `" .. tostring(self.type_name) .. "." .. tostring(self.variant_name) .. "`") end
            local owner_ty = expr_type(self)
            local payload = nil
            if #(self.args or {}) == 1 then payload = lower_expr(ctx, self.args[1]) end
            local dst = new_temp(ctx, "variant_ctor")
            append_inst(ctx, Code.CodeInstVariantCtor(dst, code_ty(ctx, owner_ty), variant_ref(ctx, owner_ty, variant), payload), origin_generated("variant constructor"))
            return Tr.TreeCodeExprResult(dst, code_ty(ctx, owner_ty))
    end

    function Tr.ExprNull:lower_tree_expr_to_code(input)
        local ctx = input
            local ty = code_ty(ctx, expr_type(self))
            local dst = new_temp(ctx, "null")
            append_inst(ctx, Code.CodeInstConst(dst, Code.CodeConstNull(ty)), origin_generated("null"))
            return Tr.TreeCodeExprResult(dst, ty)
    end

    lower_expr = function(ctx, expr)
        local result = expr:lower_tree_expr_to_code(ctx)
        return result.value, result.ty
    end

    local function bind_alias(ctx, binding, src, ty)
        declare_binding_key(ctx, binding)
        local dst = value_id_for_binding(ctx, binding)
        ctx:tree_code_note_binding(binding, dst)
        append_inst(ctx, Code.CodeInstAlias(dst, ty, src), origin_binding(binding))
        return dst
    end

    local function bind_local_init(ctx, binding, init_value, source_ty, is_mutable)
        local residence = is_mutable and Code.CodeResidenceAddressed or residence_for(ctx, binding, source_ty)
        local local_id, local_ty = ensure_local(ctx, binding, source_ty, residence)
        store_place(ctx, Code.CodePlaceLocal(local_id, local_ty), source_ty, init_value, origin_binding(binding))
        return local_id
    end

    local function lower_variant_binds(ctx, kind, owner_value, owner_ty, variant, arm)
        if #(arm.binds or {}) == 0 then return end
        if #(arm.binds or {}) > 1 then unsupported(ctx, arm, "multi-bind variant arm `" .. tostring(variant.name) .. "`") end
        local payload_ty = variant_payload_ty(ctx, variant)
        if payload_ty == nil then unsupported(ctx, arm, "payload bind for void variant `" .. tostring(variant.name) .. "`") end
        local ref = variant_ref(ctx, owner_ty, variant)
        local payload = new_temp(ctx, "variant_payload")
        append_inst(ctx, Code.CodeInstVariantPayload(payload, ref, owner_value), origin_generated("variant payload"))
        local binding = variant_binding(kind, variant, arm.binds[1])
        local ty = code_ty(ctx, binding.ty)
        if binding_is_addressed(ctx, binding) or is_aggregate_code_ty(ty) then
            bind_local_init(ctx, binding, payload, binding.ty, false)
        else
            bind_alias(ctx, binding, payload, ty)
        end
    end

    label_key = function(label)
        return label and label.name or tostring(label)
    end

    local function find_jump_arg(args, name)
        local found = nil
        for i = 1, #(args or {}) do
            if args[i].name == name then
                if found ~= nil then unsupported(nil, args[i], "duplicate jump arg `" .. tostring(name) .. "`") end
                found = args[i]
            end
        end
        if found == nil then unsupported(nil, name, "missing jump arg `" .. tostring(name) .. "`") end
        return found
    end

    local function control_binding(region_id, label, param, index, is_entry)
        local class = is_entry and Bind.BindingClassEntryBlockParam(region_id, label.name, index) or Bind.BindingClassBlockParam(region_id, label.name, index)
        return Bind.Binding(Core.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. param.name), param.name, param.ty, class)
    end

    function Tr.SwitchKeyInt:tree_code_switch_literal()
        return Core.LitInt(self.raw)
    end

    function Tr.SwitchKeyBool:tree_code_switch_literal()
        return Core.LitBool(self.value)
    end

    function Tr.SwitchKeyName:tree_code_switch_literal()
        unsupported(nil, self.name, "named switch case requires resolved key lowering")
    end

    function Tr.SwitchKeyExpr:tree_code_switch_literal()
        unsupported(nil, self.expr, "expression switch case requires compare-fallback lowering")
    end

    local function lower_stmt_fallthrough_to(ctx, body, block_id, name, join_id)
        start_block(ctx, block_id, name, {}, origin_generated(name))
        local saved = save_bindings(ctx)
        lower_stmt_body(ctx, body or {})
        local falls = ctx:tree_code_has_current_block()
        if falls then terminate(ctx, Code.CodeTermJump(join_id, {}), origin_generated(name .. " fallthrough")) end
        restore_bindings(ctx, saved)
        return falls
    end

    lower_stmt_if = function(ctx, stmt)
        local cond = lower_expr(ctx, stmt.cond)
        local then_id = new_block_id(ctx, "if_then")
        local else_id = new_block_id(ctx, "if_else")
        local join_id = new_block_id(ctx, "if_join")
        local saved = save_bindings(ctx)
        terminate(ctx, Code.CodeTermBranch(cond, then_id, {}, else_id, {}), origin_generated("if branch"))
        restore_bindings(ctx, saved)
        local then_falls = lower_stmt_fallthrough_to(ctx, stmt.then_body, then_id, "if.then", join_id)
        restore_bindings(ctx, saved)
        local else_falls = lower_stmt_fallthrough_to(ctx, stmt.else_body, else_id, "if.else", join_id)
        restore_bindings(ctx, saved)
        if then_falls or else_falls then
            start_block(ctx, join_id, "if.join", {}, origin_generated("if join"))
        end
    end

    lower_stmt_switch = function(ctx, stmt)
        if #(stmt.variant_arms or {}) > 0 then
            if #(stmt.arms or {}) > 0 then unsupported(ctx, stmt, "mixed scalar and variant switch arms") end
            local owner_ty = expr_type(stmt.value)
            local type_name = named_type_name(owner_ty)
            local def = type_name and variant_def(ctx, type_name) or nil
            if def == nil then unsupported(ctx, stmt, "variant switch without tagged-union facts") end
            local value = lower_expr(ctx, stmt.value)
            local tag = new_temp(ctx, "variant_tag")
            append_inst(ctx, Code.CodeInstVariantTag(tag, Code.CodeTyInt(32, Code.CodeUnsigned), value), origin_generated("variant tag"))
            local case_ids = {}
            local cases = {}
            for i = 1, #(stmt.variant_arms or {}) do
                local arm = stmt.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                if variant == nil then unsupported(ctx, stmt, "unknown variant arm `" .. tostring(arm.variant_name) .. "`") end
                local bid = new_block_id(ctx, "switch_variant_case")
                case_ids[i] = bid
                cases[i] = Code.CodeVariantCase(variant_ref(ctx, owner_ty, variant), bid, {})
            end
            local default_id = new_block_id(ctx, "switch_variant_default")
            local join_id = new_block_id(ctx, "switch_variant_join")
            local saved = save_bindings(ctx)
            terminate(ctx, Code.CodeTermVariantSwitch(tag, cases, default_id, {}), origin_generated("variant switch"))
            local any_falls = false
            for i = 1, #(stmt.variant_arms or {}) do
                restore_bindings(ctx, saved)
                local arm = stmt.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                start_block(ctx, case_ids[i], "switch.variant.case", {}, origin_generated("variant switch case"))
                lower_variant_binds(ctx, "stmt_switch", value, owner_ty, variant, arm)
                lower_stmt_body(ctx, arm.body or {})
                if ctx:tree_code_has_current_block() then terminate(ctx, Code.CodeTermJump(join_id, {}), origin_generated("variant switch case fallthrough")); any_falls = true end
            end
            restore_bindings(ctx, saved)
            if lower_stmt_fallthrough_to(ctx, stmt.default_body or {}, default_id, "switch.variant.default", join_id) then any_falls = true end
            restore_bindings(ctx, saved)
            if any_falls then start_block(ctx, join_id, "switch.variant.join", {}, origin_generated("variant switch join")) end
            return
        end
        local value = lower_expr(ctx, stmt.value)
        local case_ids = {}
        local cases = {}
        for i = 1, #(stmt.arms or {}) do
            local bid = new_block_id(ctx, "switch_case")
            case_ids[i] = bid
            cases[i] = Code.CodeSwitchCase(stmt.arms[i].key:tree_code_switch_literal(), bid, {})
        end
        local default_id = new_block_id(ctx, "switch_default")
        local join_id = new_block_id(ctx, "switch_join")
        local saved = save_bindings(ctx)
        terminate(ctx, Code.CodeTermSwitch(value, cases, default_id, {}), origin_generated("switch"))
        local any_falls = false
        for i = 1, #(stmt.arms or {}) do
            restore_bindings(ctx, saved)
            if lower_stmt_fallthrough_to(ctx, stmt.arms[i].body, case_ids[i], "switch.case", join_id) then any_falls = true end
        end
        restore_bindings(ctx, saved)
        if lower_stmt_fallthrough_to(ctx, stmt.default_body or {}, default_id, "switch.default", join_id) then any_falls = true end
        restore_bindings(ctx, saved)
        if any_falls then start_block(ctx, join_id, "switch.join", {}, origin_generated("switch join")) end
    end

    lower_expr_if = function(ctx, expr)
        local cond = lower_expr(ctx, expr.cond)
        local then_id = new_block_id(ctx, "expr_if_then")
        local else_id = new_block_id(ctx, "expr_if_else")
        local join_id = new_block_id(ctx, "expr_if_join")
        local result_ty = code_ty(ctx, expr_type(expr))
        local result_value = new_temp(ctx, "if_result")
        local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("if expression result"))
        local saved = save_bindings(ctx)
        terminate(ctx, Code.CodeTermBranch(cond, then_id, {}, else_id, {}), origin_generated("if expression branch"))
        restore_bindings(ctx, saved)
        start_block(ctx, then_id, "expr.if.then", {}, origin_generated("if expression then"))
        local then_value = lower_expr(ctx, expr.then_expr)
        terminate(ctx, Code.CodeTermJump(join_id, { then_value }), origin_generated("if expression then yield"))
        restore_bindings(ctx, saved)
        start_block(ctx, else_id, "expr.if.else", {}, origin_generated("if expression else"))
        local else_value = lower_expr(ctx, expr.else_expr)
        terminate(ctx, Code.CodeTermJump(join_id, { else_value }), origin_generated("if expression else yield"))
        restore_bindings(ctx, saved)
        start_block(ctx, join_id, "expr.if.join", { result_param }, origin_generated("if expression join"))
        return result_value, result_ty
    end

    lower_expr_logic = function(ctx, expr)
        local lhs = lower_expr(ctx, expr.lhs)
        local rhs_id = new_block_id(ctx, "logic_rhs")
        local short_id = new_block_id(ctx, "logic_short")
        local join_id = new_block_id(ctx, "logic_join")
        local result_value = new_temp(ctx, "logic_result")
        local result_param = Code.CodeParam(result_value, "result", Code.CodeTyBool8, origin_generated("logic result"))
        if expr.op == Core.LogicAnd then
            terminate(ctx, Code.CodeTermBranch(lhs, rhs_id, {}, short_id, {}), origin_generated("logic and branch"))
        elseif expr.op == Core.LogicOr then
            terminate(ctx, Code.CodeTermBranch(lhs, short_id, {}, rhs_id, {}), origin_generated("logic or branch"))
        else
            unsupported(ctx, expr, "logic op " .. class_name(expr.op))
        end
        local saved = save_bindings(ctx)
        start_block(ctx, rhs_id, "logic.rhs", {}, origin_generated("logic rhs"))
        local rhs = lower_expr(ctx, expr.rhs)
        terminate(ctx, Code.CodeTermJump(join_id, { rhs }), origin_generated("logic rhs yield"))
        restore_bindings(ctx, saved)
        start_block(ctx, short_id, "logic.short", {}, origin_generated("logic short"))
        local lit = expr.op == Core.LogicAnd and Core.LitBool(false) or Core.LitBool(true)
        local short_value = new_temp(ctx, "logic_short")
        append_inst(ctx, Code.CodeInstConst(short_value, Code.CodeConstLiteral(Code.CodeTyBool8, lit)), origin_generated("logic short-circuit literal"))
        terminate(ctx, Code.CodeTermJump(join_id, { short_value }), origin_generated("logic short yield"))
        restore_bindings(ctx, saved)
        start_block(ctx, join_id, "logic.join", { result_param }, origin_generated("logic join"))
        return result_value, Code.CodeTyBool8
    end

    lower_expr_switch = function(ctx, expr)
        if #(expr.variant_arms or {}) > 0 then
            if #(expr.arms or {}) > 0 then unsupported(ctx, expr, "mixed scalar and variant switch expression arms") end
            local owner_ty = expr_type(expr.value)
            local type_name = named_type_name(owner_ty)
            local def = type_name and variant_def(ctx, type_name) or nil
            if def == nil then unsupported(ctx, expr, "variant switch expression without tagged-union facts") end
            local value = lower_expr(ctx, expr.value)
            local tag = new_temp(ctx, "variant_tag")
            append_inst(ctx, Code.CodeInstVariantTag(tag, Code.CodeTyInt(32, Code.CodeUnsigned), value), origin_generated("variant tag"))
            local result_ty = code_ty(ctx, expr_type(expr))
            local result_value = new_temp(ctx, "switch_result")
            local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("variant switch expression result"))
            local case_ids = {}
            local cases = {}
            for i = 1, #(expr.variant_arms or {}) do
                local arm = expr.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                if variant == nil then unsupported(ctx, expr, "unknown variant arm `" .. tostring(arm.variant_name) .. "`") end
                local bid = new_block_id(ctx, "expr_switch_variant_case")
                case_ids[i] = bid
                cases[i] = Code.CodeVariantCase(variant_ref(ctx, owner_ty, variant), bid, {})
            end
            local default_id = new_block_id(ctx, "expr_switch_variant_default")
            local join_id = new_block_id(ctx, "expr_switch_variant_join")
            local saved = save_bindings(ctx)
            terminate(ctx, Code.CodeTermVariantSwitch(tag, cases, default_id, {}), origin_generated("variant switch expression"))
            local any_falls = false
            for i = 1, #(expr.variant_arms or {}) do
                restore_bindings(ctx, saved)
                local arm = expr.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                start_block(ctx, case_ids[i], "expr.switch.variant.case", {}, origin_generated("variant switch expression case"))
                lower_variant_binds(ctx, "expr_switch", value, owner_ty, variant, arm)
                lower_stmt_body(ctx, arm.body or {})
                if ctx:tree_code_has_current_block() then
                    local arm_value = lower_expr(ctx, arm.result)
                    terminate(ctx, Code.CodeTermJump(join_id, { arm_value }), origin_generated("variant switch expression case yield"))
                    any_falls = true
                end
            end
            restore_bindings(ctx, saved)
            start_block(ctx, default_id, "expr.switch.variant.default", {}, origin_generated("variant switch expression default"))
            lower_stmt_body(ctx, expr.default_body or {})
            if ctx:tree_code_has_current_block() then
                local default_value = lower_expr(ctx, expr.default_expr)
                terminate(ctx, Code.CodeTermJump(join_id, { default_value }), origin_generated("variant switch expression default yield"))
                any_falls = true
            end
            restore_bindings(ctx, saved)
            if not any_falls then unsupported(ctx, expr, "variant switch expression has no value-producing arm") end
            start_block(ctx, join_id, "expr.switch.variant.join", { result_param }, origin_generated("variant switch expression join"))
            return result_value, result_ty
        end
        local value = lower_expr(ctx, expr.value)
        local result_ty = code_ty(ctx, expr_type(expr))
        local result_value = new_temp(ctx, "switch_result")
        local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("switch expression result"))
        local case_ids = {}
        local cases = {}
        for i = 1, #(expr.arms or {}) do
            local bid = new_block_id(ctx, "expr_switch_case")
            case_ids[i] = bid
            cases[i] = Code.CodeSwitchCase(expr.arms[i].key:tree_code_switch_literal(), bid, {})
        end
        local default_id = new_block_id(ctx, "expr_switch_default")
        local join_id = new_block_id(ctx, "expr_switch_join")
        local saved = save_bindings(ctx)
        terminate(ctx, Code.CodeTermSwitch(value, cases, default_id, {}), origin_generated("switch expression"))
        local any_falls = false
        for i = 1, #(expr.arms or {}) do
            restore_bindings(ctx, saved)
            start_block(ctx, case_ids[i], "expr.switch.case", {}, origin_generated("switch expression case"))
            lower_stmt_body(ctx, expr.arms[i].body or {})
            if ctx:tree_code_has_current_block() then
                local arm_value = lower_expr(ctx, expr.arms[i].result)
                terminate(ctx, Code.CodeTermJump(join_id, { arm_value }), origin_generated("switch expression case yield"))
                any_falls = true
            end
        end
        restore_bindings(ctx, saved)
        start_block(ctx, default_id, "expr.switch.default", {}, origin_generated("switch expression default"))
        lower_stmt_body(ctx, expr.default_body or {})
        if ctx:tree_code_has_current_block() then
            local default_value = lower_expr(ctx, expr.default_expr)
            terminate(ctx, Code.CodeTermJump(join_id, { default_value }), origin_generated("switch expression default yield"))
            any_falls = true
        end
        restore_bindings(ctx, saved)
        if not any_falls then unsupported(ctx, expr, "switch expression has no value-producing arm") end
        start_block(ctx, join_id, "expr.switch.join", { result_param }, origin_generated("switch expression join"))
        return result_value, result_ty
    end

    lower_control_region = function(ctx, region, is_expr)
        local result_ty = is_expr and code_ty(ctx, region.result_ty) or nil
        local result_value = is_expr and new_temp(ctx, "control_result") or nil
        local exit_params = {}
        if is_expr then exit_params[1] = Code.CodeParam(result_value, "result", result_ty, origin_generated("control result")) end
        local saved_alpha, saved_alpha_suffix = ctx:tree_code_alpha_snapshot()
        local alpha_suffix = "ctl" .. tostring(ctx:tree_code_next_counter("control_scope"))
        local alpha = ctx:tree_code_fork_alpha(alpha_suffix)
        local records = {}
        local targets = {}
        local function add_record(block, is_entry)
            local bid = new_block_id(ctx, "ctl_" .. block.label.name)
            local params = {}
            local bindings = {}
            for i = 1, #(block.params or {}) do
                local b = control_binding(region.region_id, block.label, block.params[i], i, is_entry)
                declare_binding_key(ctx, b)
                local v = value_id_for_binding(ctx, b)
                local ty = code_ty(ctx, block.params[i].ty)
                params[#params + 1] = Code.CodeParam(v, block.params[i].name, ty, origin_binding(b))
                bindings[#bindings + 1] = { binding = b, value = v, ty = block.params[i].ty, code_ty = ty }
            end
            local rec = { id = bid, label = block.label, name = "ctl." .. block.label.name, params = params, bindings = bindings, body = block.body or {}, entry = is_entry, entry_params = block.params or {} }
            records[#records + 1] = rec
            targets[label_key(block.label)] = Tr.TreeCodeControlTarget(bid, params)
            return rec
        end
        local entry = add_record(region.entry, true)
        for i = 1, #(region.blocks or {}) do add_record(region.blocks[i], false) end
        local region_alpha = clone_map(ctx.binding_alpha)
        local exit_id = new_block_id(ctx, is_expr and "ctl_expr_exit" or "ctl_stmt_exit")
        local saved_outer = save_bindings(ctx)
        local entry_args = {}
        ctx:tree_code_use_alpha(saved_alpha, saved_alpha_suffix)
        for i = 1, #(region.entry.params or {}) do
            entry_args[#entry_args + 1] = lower_expr(ctx, region.entry.params[i].init)
        end
        ctx:tree_code_use_alpha(region_alpha, alpha_suffix)
        terminate(ctx, Code.CodeTermJump(entry.id, entry_args), origin_generated("enter control region"))
        local outer_control = ctx:tree_code_current_control_region()
        local control_region = Tr.TreeCodeControlRegion(is_expr, exit_id, targets)
        ctx:tree_code_enter_control_region(control_region)
        local saved_region_outer = saved_outer
        for i = 1, #records do
            local rec = records[i]
            restore_bindings(ctx, saved_region_outer)
            ctx:tree_code_use_alpha(setmetatable({}, { __index = region_alpha }), alpha_suffix .. "_b" .. tostring(i))
            start_block(ctx, rec.id, rec.name, rec.params, origin_generated("control block " .. rec.label.name))
            for j = 1, #rec.bindings do
                local b = rec.bindings[j]
                ctx:tree_code_note_binding(b.binding, b.value)
                if binding_is_addressed(ctx, b.binding) or is_aggregate_code_ty(b.code_ty) then
                    bind_local_init(ctx, b.binding, b.value, b.ty, false)
                end
            end
            lower_stmt_body(ctx, rec.body)
            if ctx:tree_code_has_current_block() then unsupported(ctx, rec.label, "control block `" .. tostring(rec.label.name) .. "` can fall through") end
        end
        local has_exit = ctx:tree_code_leave_control_region(outer_control)
        ctx:tree_code_use_alpha(saved_alpha, saved_alpha_suffix)
        restore_bindings(ctx, saved_outer)
        if has_exit or is_expr then
            start_block(ctx, exit_id, is_expr and "ctl.expr.exit" or "ctl.stmt.exit", exit_params, origin_generated("control exit"))
        end
        if is_expr then return result_value, result_ty end
    end

    function Tr.StmtLet:lower_tree_stmt_to_code(input)
        local ctx = input
        local src, ty = lower_expr(ctx, self.init)
        declare_fresh_binding_key(ctx, self.binding)
        if binding_is_addressed(ctx, self.binding) or (is_aggregate_code_ty(ty) and not is_view_code_ty(ty)) then bind_local_init(ctx, self.binding, src, self.binding.ty, false)
        else bind_alias(ctx, self.binding, src, ty) end
    end

    function Tr.StmtVar:lower_tree_stmt_to_code(input)
        local ctx = input
        local src = lower_expr(ctx, self.init)
        ctx:tree_code_note_mutable(self.binding)
        bind_local_init(ctx, self.binding, src, self.binding.ty, true)
    end

    function Tr.StmtSet:lower_tree_stmt_to_code(input)
        local ctx = input
        local value = lower_expr(ctx, self.value)
        store_place(ctx, lower_place(ctx, self.place), place_type(self.place), value, origin_generated("set"))
    end

    function Tr.StmtAtomicStore:lower_tree_stmt_to_code(input)
        local ctx = input
        local value = lower_expr(ctx, self.value)
        local place = Code.CodePlaceDeref(lower_expr(ctx, self.addr), code_ty(ctx, self.ty), align_of(ctx, self.ty))
        append_inst(ctx, Code.CodeInstAtomicStore(place, value, atomic_access(ctx, Code.CodeMemoryWrite, self.ty, self.ordering), self.ordering), origin_generated("atomic store"))
    end

    function Tr.StmtAtomicFence:lower_tree_stmt_to_code(input)
        append_inst(input, Code.CodeInstAtomicFence(self.ordering), origin_generated("atomic fence"))
    end

    function Tr.StmtExpr:lower_tree_stmt_to_code(input)
        lower_expr(input, self.expr)
    end

    function Tr.StmtIf:lower_tree_stmt_to_code(input)
        lower_stmt_if(input, self)
    end

    function Tr.StmtSwitch:lower_tree_stmt_to_code(input)
        lower_stmt_switch(input, self)
    end

    function Tr.StmtControl:lower_tree_stmt_to_code(input)
        lower_control_region(input, self.region, false)
    end

    function Tr.StmtJump:lower_tree_stmt_to_code(input)
        local ctx = input
        local region = ctx:tree_code_current_control_region()
        if region == nil then unsupported(ctx, self, "jump outside control region") end
        local target = ctx:tree_code_control_target(self.target)
        if target == nil then unsupported(ctx, self, "missing control target `" .. tostring(self.target.name) .. "`") end
        local args = {}
        for i = 1, #target.params do
            local arg = find_jump_arg(self.args, target.params[i].name)
            args[#args + 1] = lower_expr(ctx, arg.value)
        end
        terminate(ctx, Code.CodeTermJump(target.id, args), origin_generated("control jump"))
    end

    function Tr.StmtJumpCont:lower_tree_stmt_to_code(input)
        unsupported(input, self, "continuation slot jump after open expansion")
    end

    function Tr.StmtYieldValue:lower_tree_stmt_to_code(input)
        local ctx = input
        local region = ctx:tree_code_current_control_region()
        if region == nil or not region.is_expr then unsupported(ctx, self, "value yield outside expression control region") end
        local value = lower_expr(ctx, self.value)
        ctx:tree_code_note_control_exit()
        terminate(ctx, Code.CodeTermJump(region.exit_id, { value }), origin_generated("control yield value"))
    end

    function Tr.StmtYieldVoid:lower_tree_stmt_to_code(input)
        local ctx = input
        local region = ctx:tree_code_current_control_region()
        if region == nil or region.is_expr then unsupported(ctx, self, "void yield outside statement control region") end
        ctx:tree_code_note_control_exit()
        terminate(ctx, Code.CodeTermJump(region.exit_id, {}), origin_generated("control yield"))
    end

    function Tr.StmtReturnValue:lower_tree_stmt_to_code(input)
        local ctx = input
        local value = lower_expr(ctx, self.value)
        terminate(ctx, Code.CodeTermReturn({ value }), origin_generated("return"))
    end

    function Tr.StmtReturnVoid:lower_tree_stmt_to_code(input)
        terminate(input, Code.CodeTermReturn({}), origin_generated("return"))
    end

    function Tr.StmtTrap:lower_tree_stmt_to_code(input)
        terminate(input, Code.CodeTermTrap("source trap"), origin_generated("trap"))
    end

    function Tr.StmtAssert:lower_tree_stmt_to_code(input)
        local ctx = input
        local cond = lower_expr(ctx, self.cond)
        local ok_id = new_block_id(ctx, "assert_ok")
        local trap_id = new_block_id(ctx, "assert_trap")
        terminate(ctx, Code.CodeTermBranch(cond, ok_id, {}, trap_id, {}), origin_generated("assert branch"))
        start_block(ctx, trap_id, "assert.trap", {}, origin_generated("assert trap"))
        terminate(ctx, Code.CodeTermTrap("assertion failed"), origin_generated("assert trap"))
        start_block(ctx, ok_id, "assert.ok", {}, origin_generated("assert ok"))
    end

    lower_stmt = function(ctx, stmt)
        if not ctx:tree_code_has_current_block() then return end
        stmt:lower_tree_stmt_to_code(ctx)
    end

    lower_stmt_body = function(ctx, body)
        for i = 1, #(body or {}) do
            if not ctx:tree_code_has_current_block() then return end
            lower_stmt(ctx, body[i])
        end
    end

    function Tr.FuncLocal:lower_tree_func_parts_to_code()
        return Tr.TreeCodeFuncParts(self.name, Code.CodeLinkageLocal, self.params, self.result, self.body)
    end

    function Tr.FuncExport:lower_tree_func_parts_to_code()
        return Tr.TreeCodeFuncParts(self.name, Code.CodeLinkageExport, self.params, self.result, self.body)
    end

    function Tr.FuncLocalContract:lower_tree_func_parts_to_code()
        return Tr.TreeCodeFuncParts(self.name, Code.CodeLinkageLocal, self.params, self.result, self.body)
    end

    function Tr.FuncExportContract:lower_tree_func_parts_to_code()
        return Tr.TreeCodeFuncParts(self.name, Code.CodeLinkageExport, self.params, self.result, self.body)
    end

    local function func_parts(func)
        local parts = func:lower_tree_func_parts_to_code()
        return parts.name, parts.linkage, parts.params, parts.result, parts.body
    end

    local function param_binding(Core, Bind, func_name, param, index)
        return Bind.Binding(Core.Id("arg:" .. func_name .. ":" .. param.name), param.name, param.ty, Bind.BindingClassArg(index - 1))
    end

    local function param_types(params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = params[i].ty end
        return out
    end

    local function global_init_for_const(ctx, source_ty, value_expr, site)
        local value = ConstEval.value(value_expr, ctx.module.facts.const_env, ConstEval.empty_local_env())
        local ty = code_ty(ctx, source_ty)
        return value:tree_code_global_init(ctx, ty, value_expr, site)
    end

    function Sem.ConstValue:tree_code_global_init(ctx, ty, value_expr, site)
        unsupported(ctx, value_expr, "non-scalar constant initializer for global `" .. tostring(site) .. "`")
    end
    function Sem.ConstInt:tree_code_global_init(ctx, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitInt(self.raw)) }
    end
    function Sem.ConstFloat:tree_code_global_init(ctx, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitFloat(self.raw)) }
    end
    function Sem.ConstBool:tree_code_global_init(ctx, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitBool(self.value)) }
    end

    local function lower_global(module_ctx, name, source_ty, value_expr)
        local ctx = new_tree_code_func_context(module_ctx, module_ctx.facts.module_name)
        local inits = global_init_for_const(ctx, source_ty, value_expr, name)
        return Code.CodeGlobal(code_global_id(module_ctx.facts.module_name, name), name, code_ty(ctx, source_ty), Code.CodeLinkageLocal, size_of(ctx, source_ty), align_of(ctx, source_ty), inits, origin_generated("global " .. tostring(name)))
    end

    local function contract_value_for_binding(func_name, binding)
        return value_id_for_binding({ func_name = func_name }, binding)
    end

    local function contract_value_for_expr(func_name, expr)
        return expr:tree_code_contract_value(func_name)
    end

    function Tr.Expr:tree_code_contract_value(func_name)
        return nil, "contract expression is not a lowered binding reference: " .. class_name(self)
    end
    function Tr.ExprRef:tree_code_contract_value(func_name)
        return self.ref:tree_code_contract_value(func_name, self)
    end
    function Bind.ValueRef:tree_code_contract_value(func_name, expr)
        return nil, "contract expression is not a lowered binding reference: " .. class_name(expr)
    end
    function Bind.ValueRefBinding:tree_code_contract_value(func_name, expr)
        return contract_value_for_binding(func_name, self.binding)
    end

    local function code_contract_reject(func_id, reason)
        return Code.CodeFuncContractFact(
            func_id,
            Code.CodeContractRejected(tostring(reason or "unsupported contract fact")),
            origin_generated("contract rejection")
        )
    end

    local function join_reasons(...)
        local out = {}
        for i = 1, select("#", ...) do
            local reason = select(i, ...)
            if reason ~= nil then out[#out + 1] = tostring(reason) end
        end
        return table.concat(out, "; ")
    end

    function Tr.ContractFactBounds:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(
            contract_value_for_binding(func_name, self.base),
            contract_value_for_binding(func_name, self.len)
        ), origin_binding(self.base)))
    end

    function Tr.ContractFactWindowBounds:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        local base = contract_value_for_binding(func_name, self.base)
        local base_len, base_len_err = contract_value_for_expr(func_name, self.base_len)
        local start, start_err = contract_value_for_expr(func_name, self.start)
        local len, len_err = contract_value_for_expr(func_name, self.len)
        if base_len == nil or start == nil or len == nil then
            return Tr.TreeCodeContractResult(code_contract_reject(func_id, join_reasons(base_len_err, start_err, len_err)))
        end
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractWindowBounds(base, base_len, start, len), origin_binding(self.base)))
    end

    function Tr.ContractFactDisjoint:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(contract_value_for_binding(func_name, self.a), contract_value_for_binding(func_name, self.b)), origin_binding(self.a)))
    end

    function Tr.ContractFactSameLen:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractSameLen(contract_value_for_binding(func_name, self.a), contract_value_for_binding(func_name, self.b)), origin_binding(self.a)))
    end

    function Tr.ContractFactSoAComponent:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractSoAComponent(contract_value_for_binding(func_name, self.base), code_ty(ctx, self.record_ty), self.field_name, self.component_index), origin_binding(self.base)))
    end

    function Tr.ContractFactNoAlias:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractNoAlias(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactReadonly:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactWriteonly:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactInvalidate:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractInvalidate(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactPreserve:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractPreserve(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactRejected:lower_tree_contract_fact_to_code(ctx, func_name, func_id)
        return Tr.TreeCodeContractResult(code_contract_reject(func_id, "tree contract rejected: " .. class_name(self.issue)))
    end

    local function code_contract_fact(module_ctx, func_name, func_id, fact)
        local ctx = new_tree_code_func_context(module_ctx, func_name)
        return fact:lower_tree_contract_fact_to_code(ctx, func_name, func_id).fact
    end

    local function build_module_ctx(module, opts)
        opts = opts or {}
        local layout_env = opts.layout_env
        if layout_env == nil then layout_env = T.LalinSem.LayoutEnv(ModuleType.env(module, opts.target).layouts) end
        local mod_name = module_name(module)
        local const_entries = {}
        for i = 1, #(module.items or {}) do
            module.items[i]:tree_code_add_const_entries(const_entries, mod_name)
        end
        local module_facts = Tr.TreeCodeModuleFacts(
            mod_name,
            layout_env,
            tree_code_target(opts.target),
            Bind.ConstEnv(const_entries),
            build_variant_defs(module, mod_name)
        )
        local module_ctx = Tr.TreeCodeModuleContext(
            module_facts,
            {},
            {},
            {},
            {},
            {},
            0
        )
        local externs = {}
        for i = 1, #(module.items or {}) do
            module.items[i]:lower_tree_item_register_to_code(module_ctx, externs)
        end
        return module_ctx, externs
    end

    function Tr.Item:lower_tree_item_register_to_code(module_ctx, externs) end
    function Tr.Item:tree_code_add_const_entries(entries, mod_name) end
    function Tr.ItemConst:tree_code_add_const_entries(entries, mod_name)
        self.c:tree_code_add_const_entries(entries, mod_name)
    end
    function Tr.ConstItem:tree_code_add_const_entries(entries, mod_name)
        entries[#entries + 1] = Bind.ConstEntry(mod_name, self.name, self.ty, self.value)
    end

    function Tr.ItemFunc:lower_tree_item_register_to_code(module_ctx)
        local name, _, params, result_ty = func_parts(self.func)
        local sig = CodeType.ensure_type_sig(module_ctx, param_types(params), result_ty)
        module_ctx.funcs[func_key(module_ctx.facts.module_name, name)] = Tr.TreeCodeFuncRegistration(code_func_id(name), sig)
    end

    function Tr.ItemExtern:lower_tree_item_register_to_code(module_ctx, externs)
        local f = self.func
        f:tree_code_register_extern(module_ctx, externs)
    end

    function Tr.ExternFunc:tree_code_register_extern(module_ctx, externs)
        local param_tys = {}
        for j = 1, #(self.params or {}) do param_tys[j] = self.params[j].ty end
        local sig = CodeType.ensure_type_sig(module_ctx, param_tys, self.result)
        local ex = Code.CodeExtern(code_extern_id(self.name), self.name, self.symbol, sig, origin_generated("extern " .. self.name))
        module_ctx.externs[self.name] = ex
        externs[#externs + 1] = ex
    end

    local function lower_contracts(module, opts)
        opts = opts or {}
        local module_ctx = build_module_ctx(module, opts)
        local mod_id = Code.CodeModuleId("module:" .. sanitize(opts.module_id or module_name(module)))
        local facts = {}
        for i = 1, #(module.items or {}) do
            local item = module.items[i]
            item:lower_tree_item_contracts_to_code(module_ctx, facts)
        end
        return Code.CodeContractFactSet(mod_id, facts)
    end

    function Tr.Item:lower_tree_item_contracts_to_code(module_ctx, facts) end

    function Tr.ItemFunc:lower_tree_item_contracts_to_code(module_ctx, facts)
        local name = func_parts(self.func)
        local func_id = code_func_id(name)
        local tree_facts = TreeContractFacts.facts(self.func)
        for j = 1, #(tree_facts.facts or {}) do
            facts[#facts + 1] = code_contract_fact(module_ctx, name, func_id, tree_facts.facts[j])
        end
    end

    local function lower_func(module_ctx, func)
        local name, linkage, params, result_ty, body = func_parts(func)
        local residence = collect_address_taken_stmts(body or {}, { addressed = {}, mutable = {} })
        local ctx = new_tree_code_func_context(module_ctx, name, residence)

        local entry = Code.CodeBlockId("block:" .. sanitize(name) .. ":entry")
        start_block(ctx, entry, "entry", {}, origin_generated("entry block"))

        local code_params = {}
        local sig_params = {}
        for i = 1, #(params or {}) do
            local p = params[i]
            local binding = param_binding(Core, Bind, name, p, i)
            local ty = code_ty(ctx, p.ty)
            local value = value_id_for_binding(ctx, binding)
            ctx:tree_code_note_binding(binding, value)
            code_params[#code_params + 1] = Code.CodeParam(value, p.name, ty, origin_binding(binding))
            sig_params[#sig_params + 1] = ty
            if binding_is_addressed(ctx, binding) or is_aggregate_code_ty(ty) then
                bind_local_init(ctx, binding, value, p.ty, false)
            end
        end

        local result = code_ty(ctx, result_ty)
        local sig_results = {}
        if result ~= Code.CodeTyVoid then sig_results[#sig_results + 1] = result end
        local sig = CodeType.ensure_code_sig(module_ctx, sig_params, sig_results)

        lower_stmt_body(ctx, body or {})
        if ctx:tree_code_has_current_block() then
            if result == Code.CodeTyVoid then
                terminate(ctx, Code.CodeTermReturn({}), origin_generated("void fallthrough"))
            else
                unsupported(ctx, func, "non-void function without return")
            end
        end

        return Code.CodeFunc(Code.CodeFuncId("fn:" .. name), name, linkage, sig, code_params, ctx.locals, entry, ctx.blocks, origin_generated("function " .. name))
    end

    local function lower_module(module, opts)
        opts = opts or {}
        local mod_name = module_name(module)
        local module_ctx, externs = build_module_ctx(module, opts)
        local funcs = {}
        local data = {}
        local globals = {}
        for i = 1, #(module.items or {}) do
            module.items[i]:lower_tree_item_to_code(module_ctx, mod_name, funcs, data, globals)
        end
        for i = 1, #module_ctx.generated_data do data[#data + 1] = module_ctx.generated_data[i] end
        return Code.CodeModule(
            Code.CodeModuleId("module:" .. sanitize(opts.module_id or module_name(module))),
            module_ctx.code_sig_order,
            {}, data, globals, externs, funcs,
            origin_generated("tree_to_code module")
        )
    end

    function Tr.Item:lower_tree_item_to_code(module_ctx, mod_name, funcs, data, globals) end

    function Tr.ItemFunc:lower_tree_item_to_code(module_ctx, mod_name, funcs)
        funcs[#funcs + 1] = lower_func(module_ctx, self.func)
    end

    function Tr.ItemData:lower_tree_item_to_code(module_ctx, mod_name, funcs, data)
        data[#data + 1] = Code.CodeData(code_data_id(self.data.id), self.data.id.text, Code.CodeLinkageLocal, self.data.size, self.data.align, { Code.CodeDataBytes(0, self.data.bytes) }, origin_generated("data " .. tostring(self.data.id.text)))
    end

    function Tr.ItemConst:lower_tree_item_to_code(module_ctx, mod_name, funcs, data, globals)
        self.c:tree_code_lower_const_item(module_ctx, globals)
    end

    function Tr.ConstItem:tree_code_lower_const_item(module_ctx, globals)
        globals[#globals + 1] = lower_global(module_ctx, self.name, self.ty, self.value)
    end

    function Tr.ItemStatic:lower_tree_item_to_code(module_ctx, mod_name, funcs, data, globals)
        self.s:tree_code_lower_static_item(module_ctx, globals)
    end

    function Tr.StaticItem:tree_code_lower_static_item(module_ctx, globals)
        globals[#globals + 1] = lower_global(module_ctx, self.name, self.ty, self.value)
    end

    function Tr.ItemExtern:lower_tree_item_to_code(module_ctx, mod_name, funcs, data, globals) end
    function Tr.ItemType:lower_tree_item_to_code(module_ctx, mod_name, funcs, data, globals) end
    function Tr.ItemImport:lower_tree_item_to_code(module_ctx, mod_name, funcs, data, globals) end

    function Tr.ItemRegion:lower_tree_item_to_code(module_ctx, mod_name)
        unsupported({ func_name = mod_name }, self, "region item leaked past frontend expansion/typecheck")
    end

    local function lower_module_with_contracts(module, opts)
        return lower_module(module, opts), lower_contracts(module, opts)
    end

    api.module = lower_module
    api.contracts = lower_contracts
    api.module_with_contracts = lower_module_with_contracts

    T._lalin_api_cache.tree_to_code = api
    return api
end

return bind_context
