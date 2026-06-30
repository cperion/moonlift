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

    local function unsupported(tree_code_input, node, what)
        local site = tree_code_input and tree_code_input:tree_code_func_name() or "module"
        error("tree_to_code unsupported lowering: " .. tostring(what or class_name(node)) .. " in " .. site, 3)
    end

    local function tree_code_expr_result(input, value, ty)
        return Tr.TreeCodeExprResult(value, ty, input:tree_code_state())
    end

    local function tree_code_place_result(input, place)
        return Tr.TreeCodePlaceResult(place, input:tree_code_state())
    end

    function Tr.TreeCodeExprInput:tree_code_module_facts() return self.facts.module_facts end
    function Tr.TreeCodePlaceInput:tree_code_module_facts() return self.facts.module_facts end
    function Tr.TreeCodeStmtInput:tree_code_module_facts() return self.facts.module_facts end
    function Tr.TreeCodeControlInput:tree_code_module_facts() return self.facts.module_facts end
    function Tr.TreeCodeContractInput:tree_code_module_facts() return self.module_facts end

    function Tr.TreeCodeExprInput:tree_code_module_sigs() return self.facts.sigs end
    function Tr.TreeCodePlaceInput:tree_code_module_sigs() return self.facts.sigs end
    function Tr.TreeCodeStmtInput:tree_code_module_sigs() return self.facts.sigs end
    function Tr.TreeCodeControlInput:tree_code_module_sigs() return self.facts.sigs end
    function Tr.TreeCodeContractInput:tree_code_module_sigs() return self.sigs end

    function Tr.TreeCodeExprInput:tree_code_module_emission() return self.facts.module_emission end
    function Tr.TreeCodePlaceInput:tree_code_module_emission() return self.facts.module_emission end
    function Tr.TreeCodeStmtInput:tree_code_module_emission() return self.facts.module_emission end
    function Tr.TreeCodeControlInput:tree_code_module_emission() return self.facts.module_emission end

    function Tr.TreeCodeExprInput:tree_code_func_facts() return self.facts end
    function Tr.TreeCodePlaceInput:tree_code_func_facts() return self.facts end
    function Tr.TreeCodeStmtInput:tree_code_func_facts() return self.facts end
    function Tr.TreeCodeControlInput:tree_code_func_facts() return self.facts end

    function Tr.TreeCodeExprInput:tree_code_func_name() return self.facts.func_name end
    function Tr.TreeCodePlaceInput:tree_code_func_name() return self.facts.func_name end
    function Tr.TreeCodeStmtInput:tree_code_func_name() return self.facts.func_name end
    function Tr.TreeCodeControlInput:tree_code_func_name() return self.facts.func_name end
    function Tr.TreeCodeContractInput:tree_code_func_name() return self.func_name end

    function Tr.TreeCodeExprInput:tree_code_state() return self.state end
    function Tr.TreeCodePlaceInput:tree_code_state() return self.state end
    function Tr.TreeCodeStmtInput:tree_code_state() return self.state end
    function Tr.TreeCodeControlInput:tree_code_state() return self.state end

    local function install_tree_code_input_method(name, fn)
        Tr.TreeCodeExprInput[name] = fn
        Tr.TreeCodePlaceInput[name] = fn
        Tr.TreeCodeStmtInput[name] = fn
        Tr.TreeCodeControlInput[name] = fn
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

    function Tr.TreeCodeFuncState:tree_code_scoped_binding_key(binding)
        local key = binding_key(binding)
        local alpha = self.alpha.renamed_by_key
        if alpha ~= nil and alpha[key] ~= nil then return alpha[key] end
        return key
    end

    function Tr.TreeCodeFuncState:tree_code_binding_alpha_suffix()
        local entry = self.alpha.current_suffix_by_slot and self.alpha.current_suffix_by_slot.current
        return entry and entry.suffix or nil
    end

    function Tr.TreeCodeFuncState:tree_code_declare_binding_key(binding)
        local key = binding_key(binding)
        local suffix = self:tree_code_binding_alpha_suffix()
        if self.alpha.renamed_by_key ~= nil and suffix ~= nil and self.alpha.renamed_by_key[key] == nil then
            self.alpha.renamed_by_key[key] = key .. "@" .. suffix
        end
        return self:tree_code_scoped_binding_key(binding)
    end

    function Tr.TreeCodeFuncState:tree_code_declare_fresh_binding_key(binding)
        local key = binding_key(binding)
        local suffix = self:tree_code_binding_alpha_suffix()
        if self.alpha.renamed_by_key ~= nil and suffix ~= nil then
            self.alpha.renamed_by_key[key] = key .. "@" .. suffix .. "_l" .. tostring(self:tree_code_next_counter("binding_alpha"))
        end
        return self:tree_code_scoped_binding_key(binding)
    end

    local function input_binding_is_addressed(self, binding)
        local key = binding_key(binding)
        local scoped = self:tree_code_state():tree_code_scoped_binding_key(binding)
        local state = self:tree_code_state()
        return (state.residence.addressed_by_key and (state.residence.addressed_by_key[key] or state.residence.addressed_by_key[scoped])) or false
    end
    install_tree_code_input_method("tree_code_binding_is_addressed", input_binding_is_addressed)

    local function input_binding_is_mutable(self, binding)
        local key = binding_key(binding)
        local scoped = self:tree_code_state():tree_code_scoped_binding_key(binding)
        local state = self:tree_code_state()
        return (state.residence.mutable_by_key and (state.residence.mutable_by_key[key] or state.residence.mutable_by_key[scoped])) or false
    end
    install_tree_code_input_method("tree_code_binding_is_mutable", input_binding_is_mutable)

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

    local function new_tree_code_func_lowering(module_facts, sigs, registrations, emission, func_name, residence)
        residence = residence or {}
        return Tr.TreeCodeFuncFacts(module_facts, sigs, registrations, emission, func_name),
            Tr.TreeCodeFuncState(
            Tr.TreeCodeBindingState({}, {}),
            Tr.TreeCodeResidenceFacts(residence.addressed or {}, residence.mutable or {}),
            Tr.TreeCodeEmissionState({}, {}, {}),
            Tr.TreeCodeCounterState({}),
            Tr.TreeCodeAlphaState({}, {}, 0),
            Tr.TreeCodeControlState({}, {})
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

    local function input_fresh_string_data(self, bytes)
        local module_facts = self:tree_code_module_facts()
        local emission = self:tree_code_module_emission()
        local next_string_data = ((emission.counters and emission.counters.string_data and emission.counters.string_data.next_value) or 0) + 1
        emission.counters.string_data = Tr.TreeCodeCounterEntry("string_data", next_string_data)
        local stem = "str_" .. sanitize(self:tree_code_func_name()) .. "_" .. tostring(next_string_data)
        local id = Code.CodeDataId("data:" .. tostring(module_facts.module_name or "module") .. ":" .. stem)
        local decoded = decoded_string_bytes(bytes)
        local nul_terminated = decoded .. "\0"
        emission.generated_data[#emission.generated_data + 1] = Code.CodeData(
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
    install_tree_code_input_method("tree_code_fresh_string_data", input_fresh_string_data)

    local function input_value_id_for_binding(self, binding)
        return Code.CodeValueId("v:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(self:tree_code_state():tree_code_scoped_binding_key(binding)))
    end
    install_tree_code_input_method("tree_code_value_id_for_binding", input_value_id_for_binding)

    local function input_local_id_for_binding(self, binding)
        return Code.CodeLocalId("local:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(self:tree_code_state():tree_code_scoped_binding_key(binding)))
    end
    install_tree_code_input_method("tree_code_local_id_for_binding", input_local_id_for_binding)

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

    local function input_code_type(self, ty)
        return CodeType.type_to_code(ty, self:tree_code_module_sigs())
    end
    install_tree_code_input_method("tree_code_type", input_code_type)
    function Tr.TreeCodeContractInput:tree_code_type(ty)
        return CodeType.type_to_code(ty, self:tree_code_module_sigs())
    end

    local function u8_code_ty()
        return Code.CodeTyInt(8, Code.CodeUnsigned)
    end

    local function input_variant_def(self, type_name)
        local module_facts = self:tree_code_module_facts()
        return module_facts.variant_defs and module_facts.variant_defs[type_name] or nil
    end
    install_tree_code_input_method("tree_code_variant_def", input_variant_def)

    function Tr.TreeCodeVariant:tree_code_payload_type(input)
        if #(self.fields or {}) > 1 then unsupported(input, self, "multi-field variant payload `" .. tostring(self.name) .. "`") end
        local ty = (#(self.fields or {}) == 1) and self.fields[1].ty or self.payload
        if ty == nil or is_void_type(ty) then return nil end
        return ty
    end

    function Tr.TreeCodeVariant:tree_code_ref(input, owner_ty)
        local payload_ty = self:tree_code_payload_type(input)
        return Code.CodeVariantRef(input:tree_code_type(owner_ty), self.name, self.tag, payload_ty and input:tree_code_type(payload_ty) or nil)
    end

    local function input_variant_payload_type(self, variant)
        return variant:tree_code_payload_type(self)
    end
    install_tree_code_input_method("tree_code_variant_payload_type", input_variant_payload_type)

    local function input_variant_ref(self, owner_ty, variant)
        return variant:tree_code_ref(self, owner_ty)
    end
    install_tree_code_input_method("tree_code_variant_ref", input_variant_ref)

    local function input_layout_of(self, ty)
        local module_facts = self:tree_code_module_facts()
        local result = TypeSizeAlign.result(ty, module_facts.layout_env, module_facts.target)
        return result:tree_code_known_layout()
    end
    install_tree_code_input_method("tree_code_layout_of", input_layout_of)

    local function input_align_of(self, ty)
        local layout = self:tree_code_layout_of(ty)
        return layout and layout.align or 1
    end
    install_tree_code_input_method("tree_code_align_of", input_align_of)

    local function input_size_of(self, ty)
        local layout = self:tree_code_layout_of(ty)
        return layout and layout.size or nil
    end
    install_tree_code_input_method("tree_code_size_of", input_size_of)

    function Tr.TreeCodeContractInput:tree_code_layout_of(ty)
        local module_facts = self:tree_code_module_facts()
        local result = TypeSizeAlign.result(ty, module_facts.layout_env, module_facts.target)
        return result:tree_code_known_layout()
    end

    function Tr.TreeCodeContractInput:tree_code_align_of(ty)
        local layout = self:tree_code_layout_of(ty)
        return layout and layout.align or 1
    end

    function Tr.TreeCodeContractInput:tree_code_size_of(ty)
        local layout = self:tree_code_layout_of(ty)
        return layout and layout.size or nil
    end

    local function variant_binding(kind, variant, bind)
        return Bind.Binding(Core.Id("variant:" .. kind .. ":" .. variant.name .. ":" .. bind.name), bind.name, bind.ty, Bind.BindingRoleLocalValue)
    end

    local function is_float_code_ty(ty)
        return ty:tree_code_is_float_type()
    end

    local function is_aggregate_code_ty(ty)
        return ty:tree_code_is_aggregate_type()
    end

    local clone_map, replace_map
    local label_key

    function Tr.TreeCodeFuncState:tree_code_next_counter(name)
        local next_value = (self.counters.values_by_name[name] or 0) + 1
        self.counters.values_by_name[name] = next_value
        return next_value
    end

    function Tr.TreeCodeFuncState:tree_code_current_block()
        return self.emission.current_blocks and self.emission.current_blocks[1] or nil
    end

    function Tr.TreeCodeFuncState:tree_code_has_current_block()
        return self:tree_code_current_block() ~= nil
    end

    function Tr.TreeCodeFuncState:tree_code_set_current_block(block)
        self.emission.current_blocks[1] = block
    end

    function Tr.TreeCodeFuncState:tree_code_clear_current_block()
        self.emission.current_blocks[1] = nil
    end

    function Tr.TreeCodeFuncState:tree_code_append_block(block)
        self.emission.blocks[#self.emission.blocks + 1] = block
    end

    function Tr.TreeCodeFuncState:tree_code_save_bindings()
        return Tr.TreeCodeBindingSnapshot(clone_map(self.bindings.values_by_key), clone_map(self.bindings.locals_by_key))
    end

    function Tr.TreeCodeFuncState:tree_code_restore_bindings(saved)
        replace_map(self.bindings.values_by_key, saved.bindings)
        replace_map(self.bindings.locals_by_key, saved.locals_by_key)
    end

    function Tr.TreeCodeFuncState:tree_code_note_binding(binding, value)
        self.bindings.values_by_key[self:tree_code_scoped_binding_key(binding)] = value
    end

    function Tr.TreeCodeFuncState:tree_code_note_mutable(binding)
        self.residence.mutable_by_key[self:tree_code_declare_fresh_binding_key(binding)] = true
    end

    function Tr.TreeCodeFuncState:tree_code_alpha_snapshot()
        return clone_map(self.alpha.renamed_by_key), self:tree_code_binding_alpha_suffix()
    end

    function Tr.TreeCodeFuncState:tree_code_use_alpha(alpha, suffix)
        replace_map(self.alpha.renamed_by_key, alpha)
        if suffix == nil then
            self.alpha.current_suffix_by_slot.current = nil
        else
            self.alpha.current_suffix_by_slot.current = Tr.TreeCodeAlphaSuffixEntry("current", suffix)
        end
    end

    function Tr.TreeCodeFuncState:tree_code_fork_alpha(suffix)
        self:tree_code_use_alpha(setmetatable({}, { __index = self.alpha.renamed_by_key }), suffix)
        return self.alpha.renamed_by_key
    end

    function Tr.TreeCodeFuncState:tree_code_enter_control_region(region)
        local depth = #(self.control.current_regions or {}) + 1
        self.control.current_regions[depth] = Tr.TreeCodeControlRegionSlot("control:" .. tostring(depth), region)
        self.control.flags[depth] = Tr.TreeCodeControlFlag("exit_seen:" .. tostring(depth), false)
    end

    function Tr.TreeCodeFuncState:tree_code_leave_control_region(region)
        local depth = #(self.control.current_regions or {})
        local exit_flag = self.control.flags[depth]
        local saw_exit = exit_flag and exit_flag.enabled or false
        self.control.current_regions[depth] = nil
        self.control.flags[depth] = nil
        return saw_exit
    end

    function Tr.TreeCodeFuncState:tree_code_current_control_region()
        local slot = self.control.current_regions[#(self.control.current_regions or {})]
        return slot and slot.region or nil
    end

    function Tr.TreeCodeFuncState:tree_code_note_control_exit()
        local depth = #(self.control.current_regions or {})
        if depth > 0 then self.control.flags[depth] = Tr.TreeCodeControlFlag("exit_seen:" .. tostring(depth), true) end
    end

    function Tr.TreeCodeFuncState:tree_code_control_target(label)
        local region = self:tree_code_current_control_region()
        if region == nil then return nil end
        local key = label_key(label)
        for _, entry in ipairs(region.targets or {}) do
            if entry.label_name == key then return entry.target end
        end
        return nil
    end

    function Tr.TreeCodeFuncState:tree_code_ensure_local(facts, binding, source_ty, residence)
        local input = Tr.TreeCodeStmtInput(facts, self)
        local key = self:tree_code_declare_binding_key(binding)
        local existing = self.bindings.locals_by_key[key]
        if existing ~= nil then return existing.id, existing.ty end
        local cty = input:tree_code_type(source_ty or binding.ty)
        local id = input:tree_code_local_id_for_binding(binding)
        local local_ = Code.CodeLocal(id, binding.name, cty, residence or input:tree_code_residence_for(binding, source_ty or binding.ty), origin_binding(binding))
        self.emission.locals[#self.emission.locals + 1] = local_
        self.bindings.locals_by_key[key] = Tr.TreeCodeLocalBinding(id, cty, source_ty or binding.ty)
        return id, cty
    end

    local function input_value_id(self, prefix)
        return Code.CodeValueId("v:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(prefix or "tmp") .. tostring(self:tree_code_state():tree_code_next_counter("value")))
    end
    Tr.TreeCodeExprInput.tree_code_new_value = input_value_id
    Tr.TreeCodePlaceInput.tree_code_new_value = input_value_id
    Tr.TreeCodeStmtInput.tree_code_new_value = input_value_id
    Tr.TreeCodeControlInput.tree_code_new_value = input_value_id

    local function input_inst_id(self, prefix)
        return Code.CodeInstId("inst:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(prefix or "i") .. tostring(self:tree_code_state():tree_code_next_counter("inst")))
    end
    Tr.TreeCodeExprInput.tree_code_new_inst = input_inst_id
    Tr.TreeCodePlaceInput.tree_code_new_inst = input_inst_id
    Tr.TreeCodeStmtInput.tree_code_new_inst = input_inst_id
    Tr.TreeCodeControlInput.tree_code_new_inst = input_inst_id

    local function input_term_id(self, prefix)
        return Code.CodeTermId("term:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(prefix or "t") .. tostring(self:tree_code_state():tree_code_next_counter("term")))
    end
    Tr.TreeCodeExprInput.tree_code_new_term = input_term_id
    Tr.TreeCodePlaceInput.tree_code_new_term = input_term_id
    Tr.TreeCodeStmtInput.tree_code_new_term = input_term_id
    Tr.TreeCodeControlInput.tree_code_new_term = input_term_id

    local function input_block_id(self, prefix)
        return Code.CodeBlockId("block:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(prefix or "b") .. tostring(self:tree_code_state():tree_code_next_counter("block")))
    end
    Tr.TreeCodeExprInput.tree_code_new_block = input_block_id
    Tr.TreeCodePlaceInput.tree_code_new_block = input_block_id
    Tr.TreeCodeStmtInput.tree_code_new_block = input_block_id
    Tr.TreeCodeControlInput.tree_code_new_block = input_block_id

    local function input_append_inst(self, kind, origin)
        local block = self:tree_code_state():tree_code_current_block()
        if block == nil then unsupported(self, kind, "instruction after terminator") end
        block.insts[#block.insts + 1] = Code.CodeInst(self:tree_code_new_inst(), kind, origin or origin_generated("tree_to_code"))
    end
    Tr.TreeCodeExprInput.tree_code_append_inst = input_append_inst
    Tr.TreeCodePlaceInput.tree_code_append_inst = input_append_inst
    Tr.TreeCodeStmtInput.tree_code_append_inst = input_append_inst
    Tr.TreeCodeControlInput.tree_code_append_inst = input_append_inst

    local function input_start_block(self, id, name, params, origin)
        if self:tree_code_state():tree_code_has_current_block() then unsupported(self, id, "starting block before terminating current block") end
        self:tree_code_state():tree_code_set_current_block(Tr.TreeCodeBlockBuilder(id, name, params or {}, {}, origin or origin_generated("block " .. tostring(name or "block"))))
    end
    Tr.TreeCodeExprInput.tree_code_start_block = input_start_block
    Tr.TreeCodePlaceInput.tree_code_start_block = input_start_block
    Tr.TreeCodeStmtInput.tree_code_start_block = input_start_block
    Tr.TreeCodeControlInput.tree_code_start_block = input_start_block

    local function input_terminate(self, kind, origin)
        if not self:tree_code_state():tree_code_has_current_block() then unsupported(self, kind, "terminator without current block") end
        local term = Code.CodeTerm(self:tree_code_new_term("term"), kind, origin or origin_generated("terminator"))
        local block = self:tree_code_state():tree_code_current_block()
        self:tree_code_state():tree_code_append_block(Code.CodeBlock(block.id, block.name, block.params, block.insts, term, block.origin))
        self:tree_code_state():tree_code_clear_current_block()
        return term
    end
    Tr.TreeCodeExprInput.tree_code_terminate = input_terminate
    Tr.TreeCodePlaceInput.tree_code_terminate = input_terminate
    Tr.TreeCodeStmtInput.tree_code_terminate = input_terminate
    Tr.TreeCodeControlInput.tree_code_terminate = input_terminate

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

    local function input_save_bindings(self)
        return self:tree_code_state():tree_code_save_bindings()
    end
    install_tree_code_input_method("tree_code_save_bindings", input_save_bindings)

    local function input_restore_bindings(self, saved)
        self:tree_code_state():tree_code_restore_bindings(saved)
    end
    install_tree_code_input_method("tree_code_restore_bindings", input_restore_bindings)

    local function default_int_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftTrapOutOfRange)
    end

    local function default_float_mode()
        return Code.CodeFloatStrict
    end

    local function input_memory_access(self, mode, source_ty, code_type)
        return Code.CodeMemoryAccess(mode, code_type or self:tree_code_type(source_ty), self:tree_code_align_of(source_ty), Code.CodeMayTrap, false, nil)
    end
    install_tree_code_input_method("tree_code_memory_access", input_memory_access)

    local function input_residence_for(self, binding, ty)
        if self:tree_code_binding_is_addressed(binding) then return Code.CodeResidenceAddressed end
        if is_aggregate_code_ty(self:tree_code_type(ty or binding.ty)) then return Code.CodeResidenceAggregate end
        return Code.CodeResidenceValue
    end
    install_tree_code_input_method("tree_code_residence_for", input_residence_for)

    local function is_view_code_ty(ty)
        return ty:tree_code_is_view_type()
    end

    local function input_ensure_local(self, binding, ty, residence)
        return self:tree_code_state():tree_code_ensure_local(self:tree_code_func_facts(), binding, ty, residence)
    end
    install_tree_code_input_method("tree_code_ensure_local", input_ensure_local)

    local function input_lower_stmt_body(self, body)
        local input = Tr.TreeCodeStmtInput(self:tree_code_func_facts(), self:tree_code_state())
        for i = 1, #(body or {}) do
            if not input:tree_code_state():tree_code_has_current_block() then return input end
            local result = body[i]:lower_tree_stmt_to_code(input)
            input = Tr.TreeCodeStmtInput(input:tree_code_func_facts(), result.state)
        end
        return input
    end
    install_tree_code_input_method("tree_code_lower_stmt_body", input_lower_stmt_body)

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

    function Bind.ValueRef:tree_code_lookup_binding(tree_code_input)
        unsupported(tree_code_input, self, "non-binding value reference " .. class_name(self))
    end
    function Bind.ValueRefBinding:tree_code_lookup_binding(tree_code_input)
        return self.binding, tree_code_input:tree_code_state():tree_code_scoped_binding_key(self.binding)
    end

    local function input_load_place(self, place, source_ty, reason)
        local dst = self:tree_code_new_value(reason or "load")
        self:tree_code_append_inst(Code.CodeInstLoad(dst, place, self:tree_code_memory_access(Code.CodeMemoryRead, source_ty, self:tree_code_type(source_ty))), origin_generated(reason or "load"))
        return dst, self:tree_code_type(source_ty)
    end
    install_tree_code_input_method("tree_code_load_place", input_load_place)

    local function input_store_place(self, place, source_ty, value, origin)
        self:tree_code_append_inst(Code.CodeInstStore(place, value, self:tree_code_memory_access(Code.CodeMemoryWrite, source_ty, self:tree_code_type(source_ty))), origin or origin_generated("store"))
    end
    install_tree_code_input_method("tree_code_store_place", input_store_place)

    local function input_atomic_access(self, mode, source_ty, ordering)
        return Code.CodeMemoryAccess(mode, self:tree_code_type(source_ty), self:tree_code_align_of(source_ty), Code.CodeMayTrap, true, ordering)
    end
    install_tree_code_input_method("tree_code_atomic_access", input_atomic_access)

    local function input_const_index(self, n, reason)
        local dst = self:tree_code_new_value(reason or "index_const")
        self:tree_code_append_inst(Code.CodeInstConst(dst, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(n)))), origin_generated(reason or "index const"))
        return dst, Code.CodeTyIndex
    end
    install_tree_code_input_method("tree_code_const_index", input_const_index)

    local function input_as_index_value(self, value, value_ty, reason)
        if value_ty == Code.CodeTyIndex then return value end
        local op = value_ty:tree_code_index_cast_op()
        if op == nil then unsupported(self, value_ty, "non-integer index value " .. class_name(value_ty)) end
        local dst = self:tree_code_new_value(reason or "to_index")
        self:tree_code_append_inst(Code.CodeInstCast(dst, op, value_ty, Code.CodeTyIndex, value), origin_generated(reason or "index cast"))
        return dst
    end
    install_tree_code_input_method("tree_code_as_index_value", input_as_index_value)

    local function input_index_mul(self, lhs, rhs, reason)
        local dst = self:tree_code_new_value(reason)
        self:tree_code_append_inst(Code.CodeInstBinary(dst, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), lhs, rhs), origin_generated(reason))
        return dst
    end
    install_tree_code_input_method("tree_code_index_mul", input_index_mul)

    local function input_data_offset(self, view, data, index, elem, reason)
        local ptr_ty = Code.CodeTyDataPtr(self:tree_code_type(elem))
        local dst = self:tree_code_new_value(reason)
        local elem_size = self:tree_code_size_of(elem)
        if elem_size == nil then unsupported(self, view, "view element without known size") end
        self:tree_code_append_inst(Code.CodeInstPtrOffset(dst, ptr_ty, data, index, elem_size, 0), origin_generated(reason))
        return dst
    end
    install_tree_code_input_method("tree_code_data_offset", input_data_offset)

    function Code.CodeType:tree_code_index_cast_op() return nil end
    function Code.CodeTyInt:tree_code_index_cast_op()
        if self.bits < 64 then
            return self.signedness == Code.CodeSigned and Core.MachineCastSextend or Core.MachineCastUextend
        end
        return Core.MachineCastBitcast
    end
    function Code.CodeTyBool8:tree_code_index_cast_op() return Core.MachineCastUextend end

    function Tr.Expr:tree_code_lower_index_value(tree_code_input, reason)
        local result = self:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
        return tree_code_input:tree_code_as_index_value(result.value, result.ty, reason)
    end

    function Tr.View:lower_tree_view_parts_to_code(tree_code_input)
        unsupported(tree_code_input, self, "view form " .. class_name(self))
    end
    function Tr.ViewContiguous:lower_tree_view_parts_to_code(tree_code_input)
        local data = self.data:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local len = self.len:tree_code_lower_index_value(tree_code_input, "view_len")
        local stride = tree_code_input:tree_code_const_index(1, "view_stride")
        return data, len, stride
    end
    function Tr.ViewStrided:lower_tree_view_parts_to_code(tree_code_input)
        local data = self.data:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local len = self.len:tree_code_lower_index_value(tree_code_input, "view_len")
        local stride = self.stride:tree_code_lower_index_value(tree_code_input, "view_stride")
        return data, len, stride
    end
    function Tr.ViewFromExpr:lower_tree_view_parts_to_code(tree_code_input)
        return source_access_base(expr_type(self.base)):tree_code_lower_view_from_expr(tree_code_input, self)
    end
    function Ty.Type:tree_code_lower_view_from_expr(tree_code_input, view)
        unsupported(tree_code_input, view, "view-from expression type " .. class_name(self))
    end
    function Ty.TPtr:tree_code_lower_view_from_expr(tree_code_input, view)
        local data = view.base:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local len = tree_code_input:tree_code_const_index(1, "view_len")
        local stride = tree_code_input:tree_code_const_index(1, "view_stride")
        return data, len, stride
    end
    function Ty.TView:tree_code_lower_view_from_expr(tree_code_input, view)
        local base = view.base:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local data = tree_code_input:tree_code_new_value("view_data")
        local len = tree_code_input:tree_code_new_value("view_len")
        local stride = tree_code_input:tree_code_new_value("view_stride")
        tree_code_input:tree_code_append_inst(Code.CodeInstViewData(data, base), origin_generated("view data"))
        tree_code_input:tree_code_append_inst(Code.CodeInstViewLen(len, base), origin_generated("view len"))
        tree_code_input:tree_code_append_inst(Code.CodeInstViewStride(stride, base), origin_generated("view stride"))
        return data, len, stride
    end
    function Tr.ViewRestrided:lower_tree_view_parts_to_code(tree_code_input)
        local data, len = self.base:lower_tree_view_parts_to_code(tree_code_input)
        local stride = self.stride:tree_code_lower_index_value(tree_code_input, "view_stride")
        return data, len, stride
    end
    function Tr.ViewWindow:lower_tree_view_parts_to_code(tree_code_input)
        local data, _, stride = self.base:lower_tree_view_parts_to_code(tree_code_input)
        local start = self.start:tree_code_lower_index_value(tree_code_input, "view_window_start")
        local scaled = tree_code_input:tree_code_index_mul(start, stride, "view_window_start")
        local window_data = tree_code_input:tree_code_data_offset(self, data, scaled, self.elem, "view_window_data")
        local len = self.len:tree_code_lower_index_value(tree_code_input, "view_window_len")
        return window_data, len, stride
    end
    function Tr.ViewRowBase:lower_tree_view_parts_to_code(tree_code_input)
        local data, len, stride = self.base:lower_tree_view_parts_to_code(tree_code_input)
        local row = self.row_offset:tree_code_lower_index_value(tree_code_input, "view_row_base")
        local scaled = tree_code_input:tree_code_index_mul(row, stride, "view_row_base_offset")
        return tree_code_input:tree_code_data_offset(self, data, scaled, self.elem, "view_row_base_data"), len, stride
    end
    function Tr.ViewInterleaved:lower_tree_view_parts_to_code(tree_code_input)
        local data = self.data:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local len = self.len:tree_code_lower_index_value(tree_code_input, "view_len")
        local stride = self.stride:tree_code_lower_index_value(tree_code_input, "view_stride")
        local lane = self.lane:tree_code_lower_index_value(tree_code_input, "view_lane")
        return tree_code_input:tree_code_data_offset(self, data, lane, self.elem, "view_interleaved_data"), len, stride
    end
    function Tr.ViewInterleavedView:lower_tree_view_parts_to_code(tree_code_input)
        local data, len, base_stride = self.base:lower_tree_view_parts_to_code(tree_code_input)
        local stride_factor = self.stride:tree_code_lower_index_value(tree_code_input, "view_stride")
        local lane = self.lane:tree_code_lower_index_value(tree_code_input, "view_lane")
        local lane_offset = tree_code_input:tree_code_index_mul(lane, base_stride, "view_interleaved_lane")
        local stride = tree_code_input:tree_code_index_mul(base_stride, stride_factor, "view_interleaved_stride")
        return tree_code_input:tree_code_data_offset(self, data, lane_offset, self.elem, "view_interleaved_data"), len, stride
    end

    function Bind.BindingRole:tree_code_lookup_value(tree_code_input, binding, ref)
        unsupported(tree_code_input, ref, "unbound scalar reference `" .. tostring(binding.name) .. "`")
    end
    function Bind.BindingRoleGlobalFunc:tree_code_lookup_value(tree_code_input, binding, ref)
        local ptr_ty = tree_code_input:tree_code_type(binding.ty)
        local dst = tree_code_input:tree_code_new_value("fnref")
        tree_code_input:tree_code_append_inst(Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefFunc(code_func_id(self.item_name)), ptr_ty), origin_binding(binding))
        return dst, ptr_ty
    end
    function Bind.BindingRoleExtern:tree_code_lookup_value(tree_code_input, binding, ref)
        local ptr_ty = tree_code_input:tree_code_type(binding.ty)
        local dst = tree_code_input:tree_code_new_value("externref")
        tree_code_input:tree_code_append_inst(Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefExtern(code_extern_id(binding.name)), ptr_ty), origin_binding(binding))
        return dst, ptr_ty
    end
    function Bind.BindingRoleGlobalConst:tree_code_lookup_value(tree_code_input, binding, ref)
        local gid = code_global_id(self.module_name, self.item_name)
        return tree_code_input:tree_code_load_place(Code.CodePlaceGlobal(gid, tree_code_input:tree_code_type(binding.ty)), binding.ty, "load_global_" .. binding.name)
    end
    function Bind.BindingRoleGlobalStatic:tree_code_lookup_value(tree_code_input, binding, ref)
        local gid = code_global_id(self.module_name, self.item_name)
        return tree_code_input:tree_code_load_place(Code.CodePlaceGlobal(gid, tree_code_input:tree_code_type(binding.ty)), binding.ty, "load_global_" .. binding.name)
    end

    function Ty.Type:tree_code_call_sig_id(tree_code_input)
        unsupported(tree_code_input, self, "non-callable type " .. class_name(self))
    end
    function Ty.TFunc:tree_code_call_sig_id(tree_code_input)
        return CodeType.ensure_type_sig(tree_code_input:tree_code_module_sigs(), self.params, self.result)
    end
    function Ty.TClosure:tree_code_call_sig_id(tree_code_input)
        return CodeType.ensure_type_sig(tree_code_input:tree_code_module_sigs(), self.params, self.result)
    end

    function Tr.Expr:tree_code_direct_call_target() return nil end
    function Tr.ExprRef:tree_code_direct_call_target()
        return self.ref:tree_code_direct_call_target()
    end
    function Bind.ValueRef:tree_code_direct_call_target() return nil end
    function Bind.ValueRefBinding:tree_code_direct_call_target()
        return self.binding.role:tree_code_direct_call_target(self.binding)
    end
    function Bind.BindingRole:tree_code_direct_call_target(binding) return nil end
    function Bind.BindingRoleGlobalFunc:tree_code_direct_call_target(binding)
        return Code.CodeCallDirect(code_func_id(self.item_name))
    end
    function Bind.BindingRoleExtern:tree_code_direct_call_target(binding)
        return Code.CodeCallExtern(code_extern_id(binding.name))
    end
    function Ty.Type:tree_code_indirect_call_target(callee, sig)
        return Code.CodeCallIndirect(callee, sig)
    end
    function Ty.TClosure:tree_code_indirect_call_target(callee, sig)
        return Code.CodeCallClosure(callee, sig)
    end

    function Ty.Type:tree_code_lower_field_base_place(tree_code_input, base)
        return base:tree_code_as_place(tree_code_input), self
    end
    function Ty.TPtr:tree_code_lower_field_base_place(tree_code_input, base)
        local addr = base:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        return Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(self.elem), tree_code_input:tree_code_align_of(self.elem)), self.elem
    end
    function Sem.FieldRef:tree_code_require_lowered_field(tree_code_input)
        unsupported(tree_code_input, self, "field access before sem_layout_resolve")
    end
    function Sem.FieldByOffset:tree_code_require_lowered_field(tree_code_input) end

    function Tr.IndexBase:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        unsupported(tree_code_input, self, "index base " .. class_name(self))
    end
    function Tr.IndexBaseExpr:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        return source_access_base(expr_type(self.base)):tree_code_lower_expr_index_base(tree_code_input, self.base, idx, elem_ty)
    end
    function Tr.IndexBasePlace:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        return source_access_base(place_type(self.base)):tree_code_lower_place_index_base(tree_code_input, self.base, idx, elem_ty)
    end
    function Tr.IndexBaseView:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        local data, _, stride = self.view:lower_tree_view_parts_to_code(tree_code_input)
        local scaled = tree_code_input:tree_code_new_value("view_index_scaled")
        tree_code_input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
        return Code.CodePlaceDeref(data, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), scaled
    end

    function Ty.Type:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        if is_aggregate_code_ty(tree_code_input:tree_code_type(self)) then return base:tree_code_as_place(tree_code_input), idx end
        unsupported(tree_code_input, base, "index expression base type " .. class_name(self))
    end
    function Ty.TPtr:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        local addr = base:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        return Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), idx
    end
    function Ty.TView:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        local view = base:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local data = tree_code_input:tree_code_new_value("view_index_data")
        local stride = tree_code_input:tree_code_new_value("view_index_stride")
        local scaled = tree_code_input:tree_code_new_value("view_index_scaled")
        tree_code_input:tree_code_append_inst(Code.CodeInstViewData(data, view), origin_generated("view index data"))
        tree_code_input:tree_code_append_inst(Code.CodeInstViewStride(stride, view), origin_generated("view index stride"))
        tree_code_input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
        return Code.CodePlaceDeref(data, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), scaled
    end
    function Ty.TSlice:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        local slice = base:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local data = tree_code_input:tree_code_new_value("slice_index_data")
        tree_code_input:tree_code_append_inst(Code.CodeInstSliceData(data, slice), origin_generated("slice index data"))
        return Code.CodePlaceDeref(data, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), idx
    end
    function Ty.TArray:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        return base:tree_code_as_place(tree_code_input), idx
    end

    function Ty.Type:tree_code_lower_place_index_base(tree_code_input, base, idx, elem_ty)
        return base:lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place, idx
    end
    function Ty.TView:tree_code_lower_place_index_base(tree_code_input, base, idx, elem_ty)
        local base_place = base:lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place
        local view = tree_code_input:tree_code_load_place(base_place, self, "view_index")
        local data = tree_code_input:tree_code_new_value("view_index_data")
        local stride = tree_code_input:tree_code_new_value("view_index_stride")
        local scaled = tree_code_input:tree_code_new_value("view_index_scaled")
        tree_code_input:tree_code_append_inst(Code.CodeInstViewData(data, view), origin_generated("view index data"))
        tree_code_input:tree_code_append_inst(Code.CodeInstViewStride(stride, view), origin_generated("view index stride"))
        tree_code_input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale"))
        return Code.CodePlaceDeref(data, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), scaled
    end

    function Bind.BindingRole:tree_code_global_place(tree_code_input, binding) return nil end
    function Bind.BindingRoleGlobalConst:tree_code_global_place(tree_code_input, binding)
        return Code.CodePlaceGlobal(code_global_id(self.module_name, self.item_name), tree_code_input:tree_code_type(binding.ty))
    end
    function Bind.BindingRoleGlobalStatic:tree_code_global_place(tree_code_input, binding)
        return Code.CodePlaceGlobal(code_global_id(self.module_name, self.item_name), tree_code_input:tree_code_type(binding.ty))
    end

    function Ty.Type:tree_code_lower_place_field_base(tree_code_input, base)
        return base:lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place
    end
    function Ty.TPtr:tree_code_lower_place_field_base(tree_code_input, base)
        local ref = base:tree_code_ref_for_ptr_field()
        if ref == nil then return base:lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place end
        local addr = Tr.ExprRef(Tr.ExprTyped(self), ref):lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        return Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(self.elem), tree_code_input:tree_code_align_of(self.elem))
    end
    function Tr.Place:tree_code_ref_for_ptr_field() return nil end
    function Tr.PlaceRef:tree_code_ref_for_ptr_field() return self.ref end

    function Tr.Expr:tree_code_as_place(tree_code_input)
        unsupported(tree_code_input, self, "expression is not addressable " .. class_name(self))
    end
    function Tr.ExprRef:tree_code_as_place(tree_code_input)
        return Tr.PlaceRef(Tr.PlaceTyped(expr_type(self)), self.ref):lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place
    end
    function Tr.ExprDeref:tree_code_as_place(tree_code_input)
        local value = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        return Code.CodePlaceDeref(value, tree_code_input:tree_code_type(expr_type(self)), tree_code_input:tree_code_align_of(expr_type(self)))
    end
    function Tr.ExprField:tree_code_as_place(tree_code_input)
        self.field:tree_code_require_lowered_field(tree_code_input)
        local base_ty = source_access_base(expr_type(self.base))
        local base_place = base_ty:tree_code_lower_field_base_place(tree_code_input, self.base)
        local field_layout = tree_code_input:tree_code_layout_of(self.field.ty)
        return Code.CodePlaceField(base_place, self.field, tree_code_input:tree_code_type(self.field.ty), self.field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil)
    end
    function Tr.ExprIndex:tree_code_as_place(tree_code_input)
        return self.base:tree_code_lower_place(tree_code_input, self.index, expr_type(self))
    end

    function Core.Literal:lower_tree_literal_to_code(tree_code_input, source_ty)
        local ty = tree_code_input:tree_code_type(source_ty)
        local dst = tree_code_input:tree_code_new_value("lit")
        tree_code_input:tree_code_append_inst(Code.CodeInstConst(dst, Code.CodeConstLiteral(ty, self)), origin_generated("literal"))
        return tree_code_expr_result(tree_code_input, dst, ty)
    end
    function Core.LitString:lower_tree_literal_to_code(tree_code_input, source_ty)
        local ty = tree_code_input:tree_code_type(source_ty)
        local elem_ty = u8_code_ty()
        local data_id, len_bytes = tree_code_input:tree_code_fresh_string_data(self.bytes)
        local data = tree_code_input:tree_code_new_value("str_data")
        tree_code_input:tree_code_append_inst(Code.CodeInstGlobalRef(data, Code.CodeGlobalRefData(data_id), Code.CodeTyDataPtr(elem_ty)), origin_generated("string literal data ref"))
        local len = tree_code_input:tree_code_new_value("str_len")
        tree_code_input:tree_code_append_inst(Code.CodeInstConst(len, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(len_bytes)))), origin_generated("string literal length"))
        local dst = tree_code_input:tree_code_new_value("str")
        tree_code_input:tree_code_append_inst(Code.CodeInstSliceMake(dst, elem_ty, data, len), origin_generated("string literal slice"))
        return tree_code_expr_result(tree_code_input, dst, ty)
    end

    function Ty.Type:tree_code_is_ptr_type() return false end
    function Ty.TPtr:tree_code_is_ptr_type() return true end

    function Ty.Type:lower_tree_len_to_code(tree_code_input, expr)
        unsupported(tree_code_input, expr, "len of non-array/view")
    end
    function Ty.TArray:lower_tree_len_to_code(tree_code_input, expr)
        return self.count:lower_tree_array_len_to_code(tree_code_input, expr)
    end
    function Ty.ArrayLen:lower_tree_array_len_to_code(tree_code_input, expr)
        unsupported(tree_code_input, expr, "len of non-constant array")
    end
    function Ty.ArrayLenConst:lower_tree_array_len_to_code(tree_code_input, expr)
        return tree_code_expr_result(tree_code_input, tree_code_input:tree_code_const_index(self.count, "array_len"), Code.CodeTyIndex)
    end
    function Ty.TView:lower_tree_len_to_code(tree_code_input, expr)
        local view = expr.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local dst = tree_code_input:tree_code_new_value("view_len")
        tree_code_input:tree_code_append_inst(Code.CodeInstViewLen(dst, view), origin_generated("view len"))
        return tree_code_expr_result(tree_code_input, dst, Code.CodeTyIndex)
    end

    function Bind.ValueRef:tree_code_lookup_value(tree_code_input)
        unsupported(tree_code_input, self, "non-binding value reference " .. class_name(self))
    end

    function Bind.ValueRefBinding:tree_code_lookup_value(tree_code_input)
        local binding, key = self:tree_code_lookup_binding(tree_code_input)
        local local_info = tree_code_input:tree_code_state().bindings.locals_by_key[key]
        if local_info ~= nil then
            return tree_code_input:tree_code_load_place(Code.CodePlaceLocal(local_info.id, local_info.ty), binding.ty, "load_" .. binding.name)
        end
        local id = tree_code_input:tree_code_state().bindings.values_by_key[key]
        if id ~= nil then return id, tree_code_input:tree_code_type(binding.ty) end
        return binding.role:tree_code_lookup_value(tree_code_input, binding, self)
    end

    function Tr.IndexBase:tree_code_lower_place(tree_code_input, index, elem_ty)
        local index_result = index:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
        local idx, idx_ty = index_result.value, index_result.ty
        idx = tree_code_input:tree_code_as_index_value(idx, idx_ty, "index")
        local elem_size = tree_code_input:tree_code_size_of(elem_ty)
        if elem_size == nil then unsupported(tree_code_input, self, "index element without known size") end
        local base_place
        base_place, idx = self:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        return Code.CodePlaceIndex(base_place, idx, tree_code_input:tree_code_type(elem_ty), elem_size)
    end

    function Tr.PlaceRef:lower_tree_place_to_code(input)
        local tree_code_input = input
        local binding, key = self.ref:tree_code_lookup_binding(tree_code_input)
        local global_place = binding.role:tree_code_global_place(tree_code_input, binding)
        if global_place ~= nil then return tree_code_place_result(tree_code_input, global_place) end
        local local_info = tree_code_input:tree_code_state().bindings.locals_by_key[key]
        if local_info == nil then
            if tree_code_input:tree_code_state().residence.addressed_by_key[key] or tree_code_input:tree_code_state().residence.mutable_by_key[key] or is_aggregate_code_ty(tree_code_input:tree_code_type(binding.ty)) then
                tree_code_input:tree_code_ensure_local(binding, binding.ty)
                local_info = tree_code_input:tree_code_state().bindings.locals_by_key[key]
            else
                unsupported(tree_code_input, self, "address/store of value-resident binding `" .. tostring(binding.name) .. "`")
            end
        end
        return tree_code_place_result(tree_code_input, Code.CodePlaceLocal(local_info.id, local_info.ty))
    end

    function Tr.PlaceDeref:lower_tree_place_to_code(input)
        local tree_code_input = input
        local addr = self.base:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local ty = place_type(self)
        return tree_code_place_result(tree_code_input, Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(ty), tree_code_input:tree_code_align_of(ty)))
    end

    function Tr.PlaceField:lower_tree_place_to_code(input)
        local tree_code_input = input
        self.field:tree_code_require_lowered_field(tree_code_input)
        local base_ty = source_access_base(place_type(self.base))
        local base_place = base_ty:tree_code_lower_place_field_base(tree_code_input, self.base)
        local field_layout = tree_code_input:tree_code_layout_of(self.field.ty)
        return tree_code_place_result(tree_code_input, Code.CodePlaceField(base_place, self.field, tree_code_input:tree_code_type(self.field.ty), self.field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil))
    end

    function Tr.PlaceIndex:lower_tree_place_to_code(input)
        local tree_code_input = input
        return tree_code_place_result(tree_code_input, self.base:tree_code_lower_place(tree_code_input, self.index, place_type(self)))
    end

    function Tr.PlaceDot:lower_tree_place_to_code(input)
        unsupported(input, self, "dot place before sem_layout_resolve")
    end

    function Tr.ExprLit:lower_tree_expr_to_code(input)
        local tree_code_input = input
        return self.value:lower_tree_literal_to_code(tree_code_input, expr_type(self))
    end

    function Tr.ExprRef:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local value, ty = self.ref:tree_code_lookup_value(tree_code_input)
        return tree_code_expr_result(tree_code_input, value, ty)
    end

    function Tr.ExprUnary:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local value = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst = tree_code_input:tree_code_new_value("unary")
            tree_code_input:tree_code_append_inst(Code.CodeInstUnary(dst, self.op, ty, value), origin_generated("unary"))
            return tree_code_expr_result(tree_code_input, dst, ty)
    end

    function Tr.ExprBinary:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local lhs_result = self.lhs:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
            local rhs_result = self.rhs:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
            local lhs, lhs_ty = lhs_result.value, lhs_result.ty
            local rhs, rhs_ty = rhs_result.value, rhs_result.ty
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst = tree_code_input:tree_code_new_value("bin")
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
                local index = tree_code_input:tree_code_as_index_value(index_value, index_ty, "ptr_add_index")
                local elem_size = tree_code_input:tree_code_size_of(elem_ty)
                if elem_size == nil then unsupported(tree_code_input, self, "pointer arithmetic element without known size") end
                tree_code_input:tree_code_append_inst(Code.CodeInstPtrOffset(dst, ty, ptr_value, index, elem_size, 0), origin_generated("pointer add"))
            elseif self.op == Core.BinSub and lhs_is_ptr and not rhs_is_ptr then
                local index = tree_code_input:tree_code_as_index_value(rhs, rhs_ty, "ptr_sub_index")
                local zero = tree_code_input:tree_code_const_index(0, "ptr_sub_zero")
                local neg = tree_code_input:tree_code_new_value("ptr_sub_neg")
                tree_code_input:tree_code_append_inst(Code.CodeInstBinary(neg, Core.BinSub, Code.CodeTyIndex, default_int_semantics(), zero, index), origin_generated("pointer subtract index"))
                local elem_size = tree_code_input:tree_code_size_of(lhs_src_ty.elem)
                if elem_size == nil then unsupported(tree_code_input, self, "pointer arithmetic element without known size") end
                tree_code_input:tree_code_append_inst(Code.CodeInstPtrOffset(dst, ty, lhs, neg, elem_size, 0), origin_generated("pointer subtract"))
            else
                if is_float_code_ty(ty) then
                    tree_code_input:tree_code_append_inst(Code.CodeInstFloatBinary(dst, self.op, ty, default_float_mode(), lhs, rhs), origin_generated("float binary"))
                else
                    tree_code_input:tree_code_append_inst(Code.CodeInstBinary(dst, self.op, ty, default_int_semantics(), lhs, rhs), origin_generated("binary"))
                end
            end
            return tree_code_expr_result(tree_code_input, dst, ty)
    end

    function Tr.ExprCompare:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local lhs = self.lhs:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local rhs = self.rhs:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local operand_ty = tree_code_input:tree_code_type(expr_type(self.lhs))
            local dst = tree_code_input:tree_code_new_value("cmp")
            tree_code_input:tree_code_append_inst(Code.CodeInstCompare(dst, self.op, operand_ty, lhs, rhs), origin_generated("compare"))
            return tree_code_expr_result(tree_code_input, dst, Code.CodeTyBool8)
    end

    function Tr.ExprControl:lower_tree_expr_to_code(input)
        local tree_code_input = input
        return self.region:tree_code_lower_expr_control_to_code(tree_code_input)
    end

    function Tr.ExprBlock:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local saved = tree_code_input:tree_code_save_bindings()
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(self.stmts or {})
            if not tree_code_input:tree_code_state():tree_code_has_current_block() then unsupported(tree_code_input, self, "expression block body terminated before result") end
            local result = self.result:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
            tree_code_input:tree_code_restore_bindings(saved)
            return tree_code_expr_result(tree_code_input, result.value, result.ty)
    end

    function Tr.ExprMachineCast:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local result = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
            local value, from = result.value, result.ty
            local to = tree_code_input:tree_code_type(self.ty or expr_type(self))
            local dst = tree_code_input:tree_code_new_value("cast")
            tree_code_input:tree_code_append_inst(Code.CodeInstCast(dst, self.op, from, to, value), origin_generated("cast"))
            return tree_code_expr_result(tree_code_input, dst, to)
    end

    function Tr.ExprCast:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local result = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
        local value, from = result.value, result.ty
        local to = tree_code_input:tree_code_type(self.ty or expr_type(self))
        local dst = tree_code_input:tree_code_new_value("cast")
        tree_code_input:tree_code_append_inst(Code.CodeInstCast(dst, Core.MachineCastIdentity, from, to, value), origin_generated("surface identity cast"))
        return tree_code_expr_result(tree_code_input, dst, to)
    end

    function Tr.ExprSelect:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local cond = self.cond:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local then_value = self.then_expr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local else_value = self.else_expr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst = tree_code_input:tree_code_new_value("select")
            tree_code_input:tree_code_append_inst(Code.CodeInstSelect(dst, ty, cond, then_value, else_value), origin_generated("select"))
            return tree_code_expr_result(tree_code_input, dst, ty)
    end

    function Tr.ExprAddrOf:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local place = self.place:lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place
            local ptr_ty = tree_code_input:tree_code_type(expr_type(self))
            local dst = tree_code_input:tree_code_new_value("addr")
            tree_code_input:tree_code_append_inst(Code.CodeInstAddrOf(dst, ptr_ty, place), origin_generated("address of"))
            return tree_code_expr_result(tree_code_input, dst, ptr_ty)
    end

    function Tr.ExprIntrinsic:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local args = {}
            for i = 1, #(self.args or {}) do args[i] = self.args[i]:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value end
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst = ty ~= Code.CodeTyVoid and tree_code_input:tree_code_new_value("intrin") or nil
            tree_code_input:tree_code_append_inst(Code.CodeInstIntrinsic(dst, self.op, ty, args), origin_generated("intrinsic"))
            return tree_code_expr_result(tree_code_input, dst, ty)
    end

    function Tr.ExprAgg:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = tree_code_input:tree_code_type(self.ty or expr_type(self))
            local fields = {}
            for i = 1, #(self.fields or {}) do
                local fi = self.fields[i]
                local value = fi.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
                fields[#fields + 1] = Code.CodeFieldValue(Sem.FieldByOffset(fi.name, fi.offset or 0, expr_type(fi.value), Host.HostRepOpaque("tree_to_code.aggregate")), value)
            end
            local dst = tree_code_input:tree_code_new_value("agg")
            tree_code_input:tree_code_append_inst(Code.CodeInstAggregate(dst, ty, fields), origin_generated("aggregate"))
            return tree_code_expr_result(tree_code_input, dst, ty)
    end

    function Tr.ExprArray:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local elems = {}
            for i = 1, #(self.elems or {}) do elems[#elems + 1] = Code.CodeArrayValue(i - 1, self.elems[i]:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value) end
            local dst = tree_code_input:tree_code_new_value("array")
            tree_code_input:tree_code_append_inst(Code.CodeInstArray(dst, ty, elems), origin_generated("array"))
            return tree_code_expr_result(tree_code_input, dst, ty)
    end

    function Tr.ExprView:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local data, len, stride = self.view:lower_tree_view_parts_to_code(tree_code_input)
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst = tree_code_input:tree_code_new_value("view")
            tree_code_input:tree_code_append_inst(Code.CodeInstViewMake(dst, ty.elem, data, len, stride), origin_generated("view"))
            return tree_code_expr_result(tree_code_input, dst, ty)
    end

    function Tr.ExprLen:lower_tree_expr_to_code(input)
        local tree_code_input = input
        return source_access_base(expr_type(self.value)):lower_tree_len_to_code(tree_code_input, self)
    end

    function Tr.ExprSizeOf:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local n = tree_code_input:tree_code_size_of(self.ty)
            if n == nil then unsupported(tree_code_input, self, "sizeof type without known layout") end
            return tree_code_expr_result(tree_code_input, tree_code_input:tree_code_const_index(n, "sizeof"), Code.CodeTyIndex)
    end

    function Tr.ExprAlignOf:lower_tree_expr_to_code(input)
        local tree_code_input = input
        return tree_code_expr_result(tree_code_input, tree_code_input:tree_code_const_index(tree_code_input:tree_code_align_of(self.ty), "alignof"), Code.CodeTyIndex)
    end

    function Tr.ExprIsNull:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local result = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
            local value, ty = result.value, result.ty
            local null_value = tree_code_input:tree_code_new_value("null_cmp")
            tree_code_input:tree_code_append_inst(Code.CodeInstConst(null_value, Code.CodeConstNull(ty)), origin_generated("null compare literal"))
            local dst = tree_code_input:tree_code_new_value("is_null")
            tree_code_input:tree_code_append_inst(Code.CodeInstCompare(dst, Core.CmpEq, ty, value, null_value), origin_generated("is null"))
            return tree_code_expr_result(tree_code_input, dst, Code.CodeTyBool8)
    end

    function Tr.ExprCall:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local fn_ty = expr_type(self.callee)
        local sig = fn_ty:tree_code_call_sig_id(tree_code_input)
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = self.args[i]:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value end
        local target = self.callee:tree_code_direct_call_target()
        if target == nil then
            local callee = self.callee:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            target = fn_ty:tree_code_indirect_call_target(callee, sig)
        end
        local result_ty = tree_code_input:tree_code_type(expr_type(self))
        local dst = nil
        if result_ty ~= Code.CodeTyVoid then dst = tree_code_input:tree_code_new_value("call") end
        tree_code_input:tree_code_append_inst(Code.CodeInstCall(dst, target, sig, args), origin_generated("call"))
        return tree_code_expr_result(tree_code_input, dst, result_ty)
    end

    function Tr.ExprDeref:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local addr = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(expr_type(self)), tree_code_input:tree_code_align_of(expr_type(self)))
            local value, ty = tree_code_input:tree_code_load_place(place, expr_type(self), "deref")
            return tree_code_expr_result(tree_code_input, value, ty)
    end

    function Tr.ExprField:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local value, ty = tree_code_input:tree_code_load_place(self:tree_code_as_place(tree_code_input), expr_type(self), "field")
        return tree_code_expr_result(tree_code_input, value, ty)
    end

    function Tr.ExprIndex:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local value, ty = tree_code_input:tree_code_load_place(self.base:tree_code_lower_place(tree_code_input, self.index, expr_type(self)), expr_type(self), "index")
        return tree_code_expr_result(tree_code_input, value, ty)
    end

    function Tr.ExprLoad:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local addr = self.addr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(self.ty or expr_type(self)), tree_code_input:tree_code_align_of(self.ty or expr_type(self)))
            local value, ty = tree_code_input:tree_code_load_place(place, self.ty or expr_type(self), "load")
            return tree_code_expr_result(tree_code_input, value, ty)
    end

    function Tr.ExprAtomicLoad:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = self.ty or expr_type(self)
            local addr = self.addr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(ty), tree_code_input:tree_code_align_of(ty))
            local dst = tree_code_input:tree_code_new_value("atomic_load")
            tree_code_input:tree_code_append_inst(Code.CodeInstAtomicLoad(dst, place, tree_code_input:tree_code_atomic_access(Code.CodeMemoryRead, ty, self.ordering), self.ordering), origin_generated("atomic load"))
            return tree_code_expr_result(tree_code_input, dst, tree_code_input:tree_code_type(ty))
    end

    function Tr.ExprAtomicRmw:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = self.ty or expr_type(self)
            local addr = self.addr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(ty), tree_code_input:tree_code_align_of(ty))
            local value = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local dst = tree_code_input:tree_code_new_value("atomic_rmw")
            tree_code_input:tree_code_append_inst(Code.CodeInstAtomicRmw(dst, self.op, place, value, tree_code_input:tree_code_atomic_access(Code.CodeMemoryReadWrite, ty, self.ordering), self.ordering), origin_generated("atomic rmw"))
            return tree_code_expr_result(tree_code_input, dst, tree_code_input:tree_code_type(ty))
    end

    function Tr.ExprAtomicCas:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = self.ty or expr_type(self)
            local addr = self.addr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(ty), tree_code_input:tree_code_align_of(ty))
            local expected = self.expected:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local replacement = self.replacement:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local dst = tree_code_input:tree_code_new_value("atomic_cas")
            tree_code_input:tree_code_append_inst(Code.CodeInstAtomicCas(dst, place, expected, replacement, tree_code_input:tree_code_atomic_access(Code.CodeMemoryReadWrite, ty, self.ordering), self.ordering), origin_generated("atomic cas"))
            return tree_code_expr_result(tree_code_input, dst, tree_code_input:tree_code_type(ty))
    end

    function Tr.ExprCtor:lower_tree_expr_to_code(input)
        local tree_code_input = input
            if #(self.args or {}) > 1 then unsupported(tree_code_input, self, "multi-argument variant constructor `" .. tostring(self.type_name) .. "." .. tostring(self.variant_name) .. "`") end
            local def = tree_code_input:tree_code_variant_def(self.type_name)
            local variant = def and def.variants[self.variant_name] or nil
            if variant == nil then unsupported(tree_code_input, self, "unknown variant constructor `" .. tostring(self.type_name) .. "." .. tostring(self.variant_name) .. "`") end
            local owner_ty = expr_type(self)
            local payload = nil
            if #(self.args or {}) == 1 then payload = self.args[1]:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value end
            local dst = tree_code_input:tree_code_new_value("variant_ctor")
            tree_code_input:tree_code_append_inst(Code.CodeInstVariantCtor(dst, tree_code_input:tree_code_type(owner_ty), tree_code_input:tree_code_variant_ref(owner_ty, variant), payload), origin_generated("variant constructor"))
            return tree_code_expr_result(tree_code_input, dst, tree_code_input:tree_code_type(owner_ty))
    end

    function Tr.ExprNull:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst = tree_code_input:tree_code_new_value("null")
            tree_code_input:tree_code_append_inst(Code.CodeInstConst(dst, Code.CodeConstNull(ty)), origin_generated("null"))
            return tree_code_expr_result(tree_code_input, dst, ty)
    end

    local function input_bind_alias(self, binding, src, ty)
        self:tree_code_state():tree_code_declare_binding_key(binding)
        local dst = self:tree_code_value_id_for_binding(binding)
        self:tree_code_state():tree_code_note_binding(binding, dst)
        self:tree_code_append_inst(Code.CodeInstAlias(dst, ty, src), origin_binding(binding))
        return dst
    end
    install_tree_code_input_method("tree_code_bind_alias", input_bind_alias)

    local function input_bind_local_init(self, binding, init_value, source_ty, is_mutable)
        local residence = is_mutable and Code.CodeResidenceAddressed or self:tree_code_residence_for(binding, source_ty)
        local local_id, local_ty = self:tree_code_ensure_local(binding, source_ty, residence)
        self:tree_code_store_place(Code.CodePlaceLocal(local_id, local_ty), source_ty, init_value, origin_binding(binding))
        return local_id
    end
    install_tree_code_input_method("tree_code_bind_local_init", input_bind_local_init)

    function Tr.SwitchVariantStmtArm:tree_code_bind_variant_payload(tree_code_input, kind, owner_value, owner_ty, variant)
        if #(self.binds or {}) == 0 then return end
        if #(self.binds or {}) > 1 then unsupported(tree_code_input, self, "multi-bind variant arm `" .. tostring(variant.name) .. "`") end
        local payload_ty = tree_code_input:tree_code_variant_payload_type(variant)
        if payload_ty == nil then unsupported(tree_code_input, self, "payload bind for void variant `" .. tostring(variant.name) .. "`") end
        local ref = tree_code_input:tree_code_variant_ref(owner_ty, variant)
        local payload = tree_code_input:tree_code_new_value("variant_payload")
        tree_code_input:tree_code_append_inst(Code.CodeInstVariantPayload(payload, ref, owner_value), origin_generated("variant payload"))
        local binding = variant_binding(kind, variant, self.binds[1])
        local ty = tree_code_input:tree_code_type(binding.ty)
        if tree_code_input:tree_code_binding_is_addressed(binding) or is_aggregate_code_ty(ty) then
            tree_code_input:tree_code_bind_local_init(binding, payload, binding.ty, false)
        else
            tree_code_input:tree_code_bind_alias(binding, payload, ty)
        end
    end

    function Tr.SwitchVariantExprArm:tree_code_bind_variant_payload(tree_code_input, kind, owner_value, owner_ty, variant)
        if #(self.binds or {}) == 0 then return end
        if #(self.binds or {}) > 1 then unsupported(tree_code_input, self, "multi-bind variant arm `" .. tostring(variant.name) .. "`") end
        local payload_ty = tree_code_input:tree_code_variant_payload_type(variant)
        if payload_ty == nil then unsupported(tree_code_input, self, "payload bind for void variant `" .. tostring(variant.name) .. "`") end
        local ref = tree_code_input:tree_code_variant_ref(owner_ty, variant)
        local payload = tree_code_input:tree_code_new_value("variant_payload")
        tree_code_input:tree_code_append_inst(Code.CodeInstVariantPayload(payload, ref, owner_value), origin_generated("variant payload"))
        local binding = variant_binding(kind, variant, self.binds[1])
        local ty = tree_code_input:tree_code_type(binding.ty)
        if tree_code_input:tree_code_binding_is_addressed(binding) or is_aggregate_code_ty(ty) then
            tree_code_input:tree_code_bind_local_init(binding, payload, binding.ty, false)
        else
            tree_code_input:tree_code_bind_alias(binding, payload, ty)
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
        local role = is_entry and Bind.BindingRoleEntryBlockParam(region_id, label.name, index) or Bind.BindingRoleBlockParam(region_id, label.name, index)
        return Bind.Binding(Core.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. param.name), param.name, param.ty, role)
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

    local function input_lower_stmt_fallthrough_to(self, body, block_id, name, join_id)
        self:tree_code_start_block(block_id, name, {}, origin_generated(name))
        local saved = self:tree_code_save_bindings()
        local input = self:tree_code_lower_stmt_body(body or {})
        local falls = input:tree_code_state():tree_code_has_current_block()
        if falls then input:tree_code_terminate(Code.CodeTermJump(join_id, {}), origin_generated(name .. " fallthrough")) end
        input:tree_code_restore_bindings(saved)
        return falls
    end
    install_tree_code_input_method("tree_code_lower_stmt_fallthrough_to", input_lower_stmt_fallthrough_to)

    function Tr.StmtIf:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local stmt = self
        local cond = stmt.cond:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local then_id = tree_code_input:tree_code_new_block("if_then")
        local else_id = tree_code_input:tree_code_new_block("if_else")
        local join_id = tree_code_input:tree_code_new_block("if_join")
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input:tree_code_terminate(Code.CodeTermBranch(cond, then_id, {}, else_id, {}), origin_generated("if branch"))
        tree_code_input:tree_code_restore_bindings(saved)
        local then_falls = tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.then_body, then_id, "if.then", join_id)
        tree_code_input:tree_code_restore_bindings(saved)
        local else_falls = tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.else_body, else_id, "if.else", join_id)
        tree_code_input:tree_code_restore_bindings(saved)
        if then_falls or else_falls then
            tree_code_input:tree_code_start_block(join_id, "if.join", {}, origin_generated("if join"))
        end
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtSwitch:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local stmt = self
        if #(stmt.variant_arms or {}) > 0 then
            if #(stmt.arms or {}) > 0 then unsupported(tree_code_input, stmt, "mixed scalar and variant switch arms") end
            local owner_ty = expr_type(stmt.value)
            local type_name = named_type_name(owner_ty)
            local def = type_name and tree_code_input:tree_code_variant_def(type_name) or nil
            if def == nil then unsupported(tree_code_input, stmt, "variant switch without tagged-union facts") end
            local value = stmt.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local tag = tree_code_input:tree_code_new_value("variant_tag")
            tree_code_input:tree_code_append_inst(Code.CodeInstVariantTag(tag, Code.CodeTyInt(32, Code.CodeUnsigned), value), origin_generated("variant tag"))
            local case_ids = {}
            local cases = {}
            for i = 1, #(stmt.variant_arms or {}) do
                local arm = stmt.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                if variant == nil then unsupported(tree_code_input, stmt, "unknown variant arm `" .. tostring(arm.variant_name) .. "`") end
                local bid = tree_code_input:tree_code_new_block("switch_variant_case")
                case_ids[i] = bid
                cases[i] = Code.CodeVariantCase(tree_code_input:tree_code_variant_ref(owner_ty, variant), bid, {})
            end
            local default_id = tree_code_input:tree_code_new_block("switch_variant_default")
            local join_id = tree_code_input:tree_code_new_block("switch_variant_join")
            local saved = tree_code_input:tree_code_save_bindings()
            tree_code_input:tree_code_terminate(Code.CodeTermVariantSwitch(tag, cases, default_id, {}), origin_generated("variant switch"))
            local any_falls = false
            for i = 1, #(stmt.variant_arms or {}) do
                tree_code_input:tree_code_restore_bindings(saved)
                local arm = stmt.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                tree_code_input:tree_code_start_block(case_ids[i], "switch.variant.case", {}, origin_generated("variant switch case"))
                arm:tree_code_bind_variant_payload(tree_code_input, "stmt_switch", value, owner_ty, variant)
                tree_code_input = tree_code_input:tree_code_lower_stmt_body(arm.body or {})
                if tree_code_input:tree_code_state():tree_code_has_current_block() then tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, {}), origin_generated("variant switch case fallthrough")); any_falls = true end
            end
            tree_code_input:tree_code_restore_bindings(saved)
            if tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.default_body or {}, default_id, "switch.variant.default", join_id) then any_falls = true end
            tree_code_input:tree_code_restore_bindings(saved)
            if any_falls then tree_code_input:tree_code_start_block(join_id, "switch.variant.join", {}, origin_generated("variant switch join")) end
            return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
        end
        local value = stmt.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local case_ids = {}
        local cases = {}
        for i = 1, #(stmt.arms or {}) do
            local bid = tree_code_input:tree_code_new_block("switch_case")
            case_ids[i] = bid
            cases[i] = Code.CodeSwitchCase(stmt.arms[i].key:tree_code_switch_literal(), bid, {})
        end
        local default_id = tree_code_input:tree_code_new_block("switch_default")
        local join_id = tree_code_input:tree_code_new_block("switch_join")
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input:tree_code_terminate(Code.CodeTermSwitch(value, cases, default_id, {}), origin_generated("switch"))
        local any_falls = false
        for i = 1, #(stmt.arms or {}) do
            tree_code_input:tree_code_restore_bindings(saved)
            if tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.arms[i].body, case_ids[i], "switch.case", join_id) then any_falls = true end
        end
        tree_code_input:tree_code_restore_bindings(saved)
        if tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.default_body or {}, default_id, "switch.default", join_id) then any_falls = true end
        tree_code_input:tree_code_restore_bindings(saved)
        if any_falls then tree_code_input:tree_code_start_block(join_id, "switch.join", {}, origin_generated("switch join")) end
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.ExprIf:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local expr = self
        local cond = expr.cond:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local then_id = tree_code_input:tree_code_new_block("expr_if_then")
        local else_id = tree_code_input:tree_code_new_block("expr_if_else")
        local join_id = tree_code_input:tree_code_new_block("expr_if_join")
        local result_ty = tree_code_input:tree_code_type(expr_type(expr))
        local result_value = tree_code_input:tree_code_new_value("if_result")
        local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("if expression result"))
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input:tree_code_terminate(Code.CodeTermBranch(cond, then_id, {}, else_id, {}), origin_generated("if expression branch"))
        tree_code_input:tree_code_restore_bindings(saved)
        tree_code_input:tree_code_start_block(then_id, "expr.if.then", {}, origin_generated("if expression then"))
        local then_value = expr.then_expr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { then_value }), origin_generated("if expression then yield"))
        tree_code_input:tree_code_restore_bindings(saved)
        tree_code_input:tree_code_start_block(else_id, "expr.if.else", {}, origin_generated("if expression else"))
        local else_value = expr.else_expr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { else_value }), origin_generated("if expression else yield"))
        tree_code_input:tree_code_restore_bindings(saved)
        tree_code_input:tree_code_start_block(join_id, "expr.if.join", { result_param }, origin_generated("if expression join"))
        return tree_code_expr_result(tree_code_input, result_value, result_ty)
    end

    function Tr.ExprLogic:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local expr = self
        local lhs = expr.lhs:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local rhs_id = tree_code_input:tree_code_new_block("logic_rhs")
        local short_id = tree_code_input:tree_code_new_block("logic_short")
        local join_id = tree_code_input:tree_code_new_block("logic_join")
        local result_value = tree_code_input:tree_code_new_value("logic_result")
        local result_param = Code.CodeParam(result_value, "result", Code.CodeTyBool8, origin_generated("logic result"))
        if expr.op == Core.LogicAnd then
            tree_code_input:tree_code_terminate(Code.CodeTermBranch(lhs, rhs_id, {}, short_id, {}), origin_generated("logic and branch"))
        elseif expr.op == Core.LogicOr then
            tree_code_input:tree_code_terminate(Code.CodeTermBranch(lhs, short_id, {}, rhs_id, {}), origin_generated("logic or branch"))
        else
            unsupported(tree_code_input, expr, "logic op " .. class_name(expr.op))
        end
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input:tree_code_start_block(rhs_id, "logic.rhs", {}, origin_generated("logic rhs"))
        local rhs = expr.rhs:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { rhs }), origin_generated("logic rhs yield"))
        tree_code_input:tree_code_restore_bindings(saved)
        tree_code_input:tree_code_start_block(short_id, "logic.short", {}, origin_generated("logic short"))
        local lit = expr.op == Core.LogicAnd and Core.LitBool(false) or Core.LitBool(true)
        local short_value = tree_code_input:tree_code_new_value("logic_short")
        tree_code_input:tree_code_append_inst(Code.CodeInstConst(short_value, Code.CodeConstLiteral(Code.CodeTyBool8, lit)), origin_generated("logic short-circuit literal"))
        tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { short_value }), origin_generated("logic short yield"))
        tree_code_input:tree_code_restore_bindings(saved)
        tree_code_input:tree_code_start_block(join_id, "logic.join", { result_param }, origin_generated("logic join"))
        return tree_code_expr_result(tree_code_input, result_value, Code.CodeTyBool8)
    end

    function Tr.ExprSwitch:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local expr = self
        if #(expr.variant_arms or {}) > 0 then
            if #(expr.arms or {}) > 0 then unsupported(tree_code_input, expr, "mixed scalar and variant switch expression arms") end
            local owner_ty = expr_type(expr.value)
            local type_name = named_type_name(owner_ty)
            local def = type_name and tree_code_input:tree_code_variant_def(type_name) or nil
            if def == nil then unsupported(tree_code_input, expr, "variant switch expression without tagged-union facts") end
            local value = expr.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            local tag = tree_code_input:tree_code_new_value("variant_tag")
            tree_code_input:tree_code_append_inst(Code.CodeInstVariantTag(tag, Code.CodeTyInt(32, Code.CodeUnsigned), value), origin_generated("variant tag"))
            local result_ty = tree_code_input:tree_code_type(expr_type(expr))
            local result_value = tree_code_input:tree_code_new_value("switch_result")
            local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("variant switch expression result"))
            local case_ids = {}
            local cases = {}
            for i = 1, #(expr.variant_arms or {}) do
                local arm = expr.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                if variant == nil then unsupported(tree_code_input, expr, "unknown variant arm `" .. tostring(arm.variant_name) .. "`") end
                local bid = tree_code_input:tree_code_new_block("expr_switch_variant_case")
                case_ids[i] = bid
                cases[i] = Code.CodeVariantCase(tree_code_input:tree_code_variant_ref(owner_ty, variant), bid, {})
            end
            local default_id = tree_code_input:tree_code_new_block("expr_switch_variant_default")
            local join_id = tree_code_input:tree_code_new_block("expr_switch_variant_join")
            local saved = tree_code_input:tree_code_save_bindings()
            tree_code_input:tree_code_terminate(Code.CodeTermVariantSwitch(tag, cases, default_id, {}), origin_generated("variant switch expression"))
            local any_falls = false
            for i = 1, #(expr.variant_arms or {}) do
                tree_code_input:tree_code_restore_bindings(saved)
                local arm = expr.variant_arms[i]
                local variant = def.variants[arm.variant_name]
                tree_code_input:tree_code_start_block(case_ids[i], "expr.switch.variant.case", {}, origin_generated("variant switch expression case"))
                arm:tree_code_bind_variant_payload(tree_code_input, "expr_switch", value, owner_ty, variant)
                tree_code_input = tree_code_input:tree_code_lower_stmt_body(arm.body or {})
                if tree_code_input:tree_code_state():tree_code_has_current_block() then
                    local arm_value = arm.result:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
                    tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { arm_value }), origin_generated("variant switch expression case yield"))
                    any_falls = true
                end
            end
            tree_code_input:tree_code_restore_bindings(saved)
            tree_code_input:tree_code_start_block(default_id, "expr.switch.variant.default", {}, origin_generated("variant switch expression default"))
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(expr.default_body or {})
            if tree_code_input:tree_code_state():tree_code_has_current_block() then
                local default_value = expr.default_expr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
                tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { default_value }), origin_generated("variant switch expression default yield"))
                any_falls = true
            end
            tree_code_input:tree_code_restore_bindings(saved)
            if not any_falls then unsupported(tree_code_input, expr, "variant switch expression has no value-producing arm") end
            tree_code_input:tree_code_start_block(join_id, "expr.switch.variant.join", { result_param }, origin_generated("variant switch expression join"))
            return tree_code_expr_result(tree_code_input, result_value, result_ty)
        end
        local value = expr.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local result_ty = tree_code_input:tree_code_type(expr_type(expr))
        local result_value = tree_code_input:tree_code_new_value("switch_result")
        local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("switch expression result"))
        local case_ids = {}
        local cases = {}
        for i = 1, #(expr.arms or {}) do
            local bid = tree_code_input:tree_code_new_block("expr_switch_case")
            case_ids[i] = bid
            cases[i] = Code.CodeSwitchCase(expr.arms[i].key:tree_code_switch_literal(), bid, {})
        end
        local default_id = tree_code_input:tree_code_new_block("expr_switch_default")
        local join_id = tree_code_input:tree_code_new_block("expr_switch_join")
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input:tree_code_terminate(Code.CodeTermSwitch(value, cases, default_id, {}), origin_generated("switch expression"))
        local any_falls = false
        for i = 1, #(expr.arms or {}) do
            tree_code_input:tree_code_restore_bindings(saved)
            tree_code_input:tree_code_start_block(case_ids[i], "expr.switch.case", {}, origin_generated("switch expression case"))
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(expr.arms[i].body or {})
            if tree_code_input:tree_code_state():tree_code_has_current_block() then
                local arm_value = expr.arms[i].result:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
                tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { arm_value }), origin_generated("switch expression case yield"))
                any_falls = true
            end
        end
        tree_code_input:tree_code_restore_bindings(saved)
        tree_code_input:tree_code_start_block(default_id, "expr.switch.default", {}, origin_generated("switch expression default"))
        tree_code_input = tree_code_input:tree_code_lower_stmt_body(expr.default_body or {})
        if tree_code_input:tree_code_state():tree_code_has_current_block() then
            local default_value = expr.default_expr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
            tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { default_value }), origin_generated("switch expression default yield"))
            any_falls = true
        end
        tree_code_input:tree_code_restore_bindings(saved)
        if not any_falls then unsupported(tree_code_input, expr, "switch expression has no value-producing arm") end
        tree_code_input:tree_code_start_block(join_id, "expr.switch.join", { result_param }, origin_generated("switch expression join"))
        return tree_code_expr_result(tree_code_input, result_value, result_ty)
    end

    function Tr.ControlExprRegion:tree_code_lower_expr_control_to_code(tree_code_input)
        local region = self
        local result_ty = tree_code_input:tree_code_type(region.result_ty)
        local result_value = tree_code_input:tree_code_new_value("control_result")
        local exit_params = { Code.CodeParam(result_value, "result", result_ty, origin_generated("control result")) }
        local saved_alpha, saved_alpha_suffix = tree_code_input:tree_code_state():tree_code_alpha_snapshot()
        local alpha_suffix = "ctl" .. tostring(tree_code_input:tree_code_state():tree_code_next_counter("control_scope"))
        local alpha = tree_code_input:tree_code_state():tree_code_fork_alpha(alpha_suffix)
        local records = {}
        local targets = {}
        local function add_record(block, is_entry)
            local bid = tree_code_input:tree_code_new_block("ctl_" .. block.label.name)
            local params = {}
            local bindings = {}
            for i = 1, #(block.params or {}) do
                local b = control_binding(region.region_id, block.label, block.params[i], i, is_entry)
                tree_code_input:tree_code_state():tree_code_declare_binding_key(b)
                local v = tree_code_input:tree_code_value_id_for_binding(b)
                local ty = tree_code_input:tree_code_type(block.params[i].ty)
                params[#params + 1] = Code.CodeParam(v, block.params[i].name, ty, origin_binding(b))
                bindings[#bindings + 1] = { binding = b, value = v, ty = block.params[i].ty, code_ty = ty }
            end
            local rec = { id = bid, label = block.label, name = "ctl." .. block.label.name, params = params, bindings = bindings, body = block.body or {}, entry = is_entry, entry_params = block.params or {} }
            records[#records + 1] = rec
            targets[#targets + 1] = Tr.TreeCodeControlTargetEntry(label_key(block.label), Tr.TreeCodeControlTarget(bid, params))
            return rec
        end
        local entry = add_record(region.entry, true)
        for i = 1, #(region.blocks or {}) do add_record(region.blocks[i], false) end
        local region_alpha = clone_map(tree_code_input:tree_code_state().alpha.renamed_by_key)
        local exit_id = tree_code_input:tree_code_new_block("ctl_expr_exit")
        local saved_outer = tree_code_input:tree_code_save_bindings()
        local entry_args = {}
        tree_code_input:tree_code_state():tree_code_use_alpha(saved_alpha, saved_alpha_suffix)
        for i = 1, #(region.entry.params or {}) do
            entry_args[#entry_args + 1] = region.entry.params[i].init:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        end
        tree_code_input:tree_code_state():tree_code_use_alpha(region_alpha, alpha_suffix)
        tree_code_input:tree_code_terminate(Code.CodeTermJump(entry.id, entry_args), origin_generated("enter control region"))
        local outer_control = tree_code_input:tree_code_state():tree_code_current_control_region()
        local control_region = Tr.TreeCodeExprControlRegion(exit_id, targets)
        tree_code_input:tree_code_state():tree_code_enter_control_region(control_region)
        local saved_region_outer = saved_outer
        for i = 1, #records do
            local rec = records[i]
            tree_code_input:tree_code_restore_bindings(saved_region_outer)
            tree_code_input:tree_code_state():tree_code_use_alpha(setmetatable({}, { __index = region_alpha }), alpha_suffix .. "_b" .. tostring(i))
            tree_code_input:tree_code_start_block(rec.id, rec.name, rec.params, origin_generated("control block " .. rec.label.name))
            for j = 1, #rec.bindings do
                local b = rec.bindings[j]
                tree_code_input:tree_code_state():tree_code_note_binding(b.binding, b.value)
                if tree_code_input:tree_code_binding_is_addressed(b.binding) or is_aggregate_code_ty(b.code_ty) then
                    tree_code_input:tree_code_bind_local_init(b.binding, b.value, b.ty, false)
                end
            end
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(rec.body)
            if tree_code_input:tree_code_state():tree_code_has_current_block() then unsupported(tree_code_input, rec.label, "control block `" .. tostring(rec.label.name) .. "` can fall through") end
        end
        local has_exit = tree_code_input:tree_code_state():tree_code_leave_control_region(outer_control)
        tree_code_input:tree_code_state():tree_code_use_alpha(saved_alpha, saved_alpha_suffix)
        tree_code_input:tree_code_restore_bindings(saved_outer)
        tree_code_input:tree_code_start_block(exit_id, "ctl.expr.exit", exit_params, origin_generated("control exit"))
        return tree_code_expr_result(tree_code_input, result_value, result_ty)
    end

    function Tr.ControlStmtRegion:tree_code_lower_stmt_control_to_code(tree_code_input)
        local region = self
        local saved_alpha, saved_alpha_suffix = tree_code_input:tree_code_state():tree_code_alpha_snapshot()
        local alpha_suffix = "ctl" .. tostring(tree_code_input:tree_code_state():tree_code_next_counter("control_scope"))
        local alpha = tree_code_input:tree_code_state():tree_code_fork_alpha(alpha_suffix)
        local records = {}
        local targets = {}
        local function add_record(block, is_entry)
            local bid = tree_code_input:tree_code_new_block("ctl_" .. block.label.name)
            local params = {}
            local bindings = {}
            for i = 1, #(block.params or {}) do
                local b = control_binding(region.region_id, block.label, block.params[i], i, is_entry)
                tree_code_input:tree_code_state():tree_code_declare_binding_key(b)
                local v = tree_code_input:tree_code_value_id_for_binding(b)
                local ty = tree_code_input:tree_code_type(block.params[i].ty)
                params[#params + 1] = Code.CodeParam(v, block.params[i].name, ty, origin_binding(b))
                bindings[#bindings + 1] = { binding = b, value = v, ty = block.params[i].ty, code_ty = ty }
            end
            local rec = { id = bid, label = block.label, name = "ctl." .. block.label.name, params = params, bindings = bindings, body = block.body or {}, entry = is_entry, entry_params = block.params or {} }
            records[#records + 1] = rec
            targets[#targets + 1] = Tr.TreeCodeControlTargetEntry(label_key(block.label), Tr.TreeCodeControlTarget(bid, params))
            return rec
        end
        local entry = add_record(region.entry, true)
        for i = 1, #(region.blocks or {}) do add_record(region.blocks[i], false) end
        local region_alpha = clone_map(tree_code_input:tree_code_state().alpha.renamed_by_key)
        local exit_id = tree_code_input:tree_code_new_block("ctl_stmt_exit")
        local saved_outer = tree_code_input:tree_code_save_bindings()
        local entry_args = {}
        tree_code_input:tree_code_state():tree_code_use_alpha(saved_alpha, saved_alpha_suffix)
        for i = 1, #(region.entry.params or {}) do
            entry_args[#entry_args + 1] = region.entry.params[i].init:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        end
        tree_code_input:tree_code_state():tree_code_use_alpha(region_alpha, alpha_suffix)
        tree_code_input:tree_code_terminate(Code.CodeTermJump(entry.id, entry_args), origin_generated("enter control region"))
        local outer_control = tree_code_input:tree_code_state():tree_code_current_control_region()
        local control_region = Tr.TreeCodeStmtControlRegion(exit_id, targets)
        tree_code_input:tree_code_state():tree_code_enter_control_region(control_region)
        local saved_region_outer = saved_outer
        for i = 1, #records do
            local rec = records[i]
            tree_code_input:tree_code_restore_bindings(saved_region_outer)
            tree_code_input:tree_code_state():tree_code_use_alpha(setmetatable({}, { __index = region_alpha }), alpha_suffix .. "_b" .. tostring(i))
            tree_code_input:tree_code_start_block(rec.id, rec.name, rec.params, origin_generated("control block " .. rec.label.name))
            for j = 1, #rec.bindings do
                local b = rec.bindings[j]
                tree_code_input:tree_code_state():tree_code_note_binding(b.binding, b.value)
                if tree_code_input:tree_code_binding_is_addressed(b.binding) or is_aggregate_code_ty(b.code_ty) then
                    tree_code_input:tree_code_bind_local_init(b.binding, b.value, b.ty, false)
                end
            end
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(rec.body)
            if tree_code_input:tree_code_state():tree_code_has_current_block() then unsupported(tree_code_input, rec.label, "control block `" .. tostring(rec.label.name) .. "` can fall through") end
        end
        local has_exit = tree_code_input:tree_code_state():tree_code_leave_control_region(outer_control)
        tree_code_input:tree_code_state():tree_code_use_alpha(saved_alpha, saved_alpha_suffix)
        tree_code_input:tree_code_restore_bindings(saved_outer)
        if has_exit then
            tree_code_input:tree_code_start_block(exit_id, "ctl.stmt.exit", {}, origin_generated("control exit"))
        end
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtLet:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local init = self.init:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
        local src, ty = init.value, init.ty
        tree_code_input:tree_code_state():tree_code_declare_fresh_binding_key(self.binding)
        if tree_code_input:tree_code_binding_is_addressed(self.binding) or (is_aggregate_code_ty(ty) and not is_view_code_ty(ty)) then tree_code_input:tree_code_bind_local_init(self.binding, src, self.binding.ty, false)
        else tree_code_input:tree_code_bind_alias(self.binding, src, ty) end
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtVar:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local src = self.init:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        tree_code_input:tree_code_state():tree_code_note_mutable(self.binding)
        tree_code_input:tree_code_bind_local_init(self.binding, src, self.binding.ty, true)
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtSet:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local value = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local place = self.place:lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place
        tree_code_input:tree_code_store_place(place, place_type(self.place), value, origin_generated("set"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtAtomicStore:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local value = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local addr = self.addr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(self.ty), tree_code_input:tree_code_align_of(self.ty))
        tree_code_input:tree_code_append_inst(Code.CodeInstAtomicStore(place, value, tree_code_input:tree_code_atomic_access(Code.CodeMemoryWrite, self.ty, self.ordering), self.ordering), origin_generated("atomic store"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtAtomicFence:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        tree_code_input:tree_code_append_inst(Code.CodeInstAtomicFence(self.ordering), origin_generated("atomic fence"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtExpr:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        self.expr:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state()))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtControl:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        return self.region:tree_code_lower_stmt_control_to_code(tree_code_input)
    end

    function Tr.StmtJump:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local region = tree_code_input:tree_code_state():tree_code_current_control_region()
        if region == nil then unsupported(tree_code_input, self, "jump outside control region") end
        local target = tree_code_input:tree_code_state():tree_code_control_target(self.target)
        if target == nil then unsupported(tree_code_input, self, "missing control target `" .. tostring(self.target.name) .. "`") end
        local args = {}
        for i = 1, #target.params do
            local arg = find_jump_arg(self.args, target.params[i].name)
            args[#args + 1] = arg.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        end
        tree_code_input:tree_code_terminate(Code.CodeTermJump(target.id, args), origin_generated("control jump"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtJumpCont:lower_tree_stmt_to_code(input)
        unsupported(input, self, "continuation slot jump after open expansion")
    end

    function Tr.TreeCodeExprControlRegion:tree_code_yield_value_exit(tree_code_input, stmt)
        return self.exit_id
    end

    function Tr.TreeCodeStmtControlRegion:tree_code_yield_value_exit(tree_code_input, stmt)
        unsupported(tree_code_input, stmt, "value yield outside expression control region")
    end

    function Tr.TreeCodeExprControlRegion:tree_code_yield_void_exit(tree_code_input, stmt)
        unsupported(tree_code_input, stmt, "void yield outside statement control region")
    end

    function Tr.TreeCodeStmtControlRegion:tree_code_yield_void_exit(tree_code_input, stmt)
        return self.exit_id
    end

    function Tr.StmtYieldValue:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local region = tree_code_input:tree_code_state():tree_code_current_control_region()
        if region == nil then unsupported(tree_code_input, self, "value yield outside expression control region") end
        local value = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        tree_code_input:tree_code_state():tree_code_note_control_exit()
        tree_code_input:tree_code_terminate(Code.CodeTermJump(region:tree_code_yield_value_exit(tree_code_input, self), { value }), origin_generated("control yield value"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtYieldVoid:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local region = tree_code_input:tree_code_state():tree_code_current_control_region()
        if region == nil then unsupported(tree_code_input, self, "void yield outside statement control region") end
        tree_code_input:tree_code_state():tree_code_note_control_exit()
        tree_code_input:tree_code_terminate(Code.CodeTermJump(region:tree_code_yield_void_exit(tree_code_input, self), {}), origin_generated("control yield"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtReturnValue:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local value = self.value:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        tree_code_input:tree_code_terminate(Code.CodeTermReturn({ value }), origin_generated("return"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtReturnVoid:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        tree_code_input:tree_code_terminate(Code.CodeTermReturn({}), origin_generated("return"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtTrap:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        tree_code_input:tree_code_terminate(Code.CodeTermTrap("source trap"), origin_generated("trap"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtAssert:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local cond = self.cond:lower_tree_expr_to_code(Tr.TreeCodeExprInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).value
        local ok_id = tree_code_input:tree_code_new_block("assert_ok")
        local trap_id = tree_code_input:tree_code_new_block("assert_trap")
        tree_code_input:tree_code_terminate(Code.CodeTermBranch(cond, ok_id, {}, trap_id, {}), origin_generated("assert branch"))
        tree_code_input:tree_code_start_block(trap_id, "assert.trap", {}, origin_generated("assert trap"))
        tree_code_input:tree_code_terminate(Code.CodeTermTrap("assertion failed"), origin_generated("assert trap"))
        tree_code_input:tree_code_start_block(ok_id, "assert.ok", {}, origin_generated("assert ok"))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
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
        return Bind.Binding(Core.Id("arg:" .. func_name .. ":" .. param.name), param.name, param.ty, Bind.BindingRoleArg(index - 1))
    end

    local function param_types(params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = params[i].ty end
        return out
    end

    local function input_global_init_for_const(tree_code_input, source_ty, value_expr, site)
        local value = ConstEval.value(value_expr, tree_code_input:tree_code_module_facts().const_env, ConstEval.empty_local_env())
        local ty = tree_code_input:tree_code_type(source_ty)
        return value:tree_code_global_init(tree_code_input, ty, value_expr, site)
    end
    install_tree_code_input_method("tree_code_global_init_for_const", input_global_init_for_const)

    function Sem.ConstValue:tree_code_global_init(tree_code_input, ty, value_expr, site)
        unsupported(tree_code_input, value_expr, "non-scalar constant initializer for global `" .. tostring(site) .. "`")
    end
    function Sem.ConstInt:tree_code_global_init(tree_code_input, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitInt(self.raw)) }
    end
    function Sem.ConstFloat:tree_code_global_init(tree_code_input, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitFloat(self.raw)) }
    end
    function Sem.ConstBool:tree_code_global_init(tree_code_input, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitBool(self.value)) }
    end

    function Tr.ConstItem:tree_code_lower_global_to_code(input)
        local facts, state = new_tree_code_func_lowering(input.module_facts, input.sigs, input.registrations, input.emission, input.module_facts.module_name)
        local expr_input = Tr.TreeCodeExprInput(facts, state)
        local inits = expr_input:tree_code_global_init_for_const(self.ty, self.value, self.name)
        return Code.CodeGlobal(code_global_id(input.module_facts.module_name, self.name), self.name, expr_input:tree_code_type(self.ty), Code.CodeLinkageLocal, expr_input:tree_code_size_of(self.ty), expr_input:tree_code_align_of(self.ty), inits, origin_generated("global " .. tostring(self.name)))
    end

    function Tr.StaticItem:tree_code_lower_global_to_code(input)
        local facts, state = new_tree_code_func_lowering(input.module_facts, input.sigs, input.registrations, input.emission, input.module_facts.module_name)
        local input = Tr.TreeCodeExprInput(facts, state)
        local inits = input:tree_code_global_init_for_const(self.ty, self.value, self.name)
        return Code.CodeGlobal(code_global_id(input:tree_code_module_facts().module_name, self.name), self.name, input:tree_code_type(self.ty), Code.CodeLinkageLocal, input:tree_code_size_of(self.ty), input:tree_code_align_of(self.ty), inits, origin_generated("global " .. tostring(self.name)))
    end

    local function contract_value_for_binding(func_name, binding)
        return Code.CodeValueId("v:" .. sanitize(func_name) .. ":" .. sanitize(binding_key(binding)))
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

    function Tr.ContractFactBounds:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(
            contract_value_for_binding(func_name, self.base),
            contract_value_for_binding(func_name, self.len)
        ), origin_binding(self.base)))
    end

    function Tr.ContractFactWindowBounds:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        local base = contract_value_for_binding(func_name, self.base)
        local base_len, base_len_err = contract_value_for_expr(func_name, self.base_len)
        local start, start_err = contract_value_for_expr(func_name, self.start)
        local len, len_err = contract_value_for_expr(func_name, self.len)
        if base_len == nil or start == nil or len == nil then
            return Tr.TreeCodeContractResult(code_contract_reject(func_id, join_reasons(base_len_err, start_err, len_err)))
        end
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractWindowBounds(base, base_len, start, len), origin_binding(self.base)))
    end

    function Tr.ContractFactDisjoint:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(contract_value_for_binding(func_name, self.a), contract_value_for_binding(func_name, self.b)), origin_binding(self.a)))
    end

    function Tr.ContractFactSameLen:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractSameLen(contract_value_for_binding(func_name, self.a), contract_value_for_binding(func_name, self.b)), origin_binding(self.a)))
    end

    function Tr.ContractFactSoAComponent:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractSoAComponent(contract_value_for_binding(func_name, self.base), tree_code_input:tree_code_type(self.record_ty), self.field_name, self.component_index), origin_binding(self.base)))
    end

    function Tr.ContractFactNoAlias:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractNoAlias(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactReadonly:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactWriteonly:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactInvalidate:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractInvalidate(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactPreserve:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(func_id, Code.CodeContractPreserve(contract_value_for_binding(func_name, self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactRejected:lower_tree_contract_fact_to_code(tree_code_input, func_name, func_id)
        return Tr.TreeCodeContractResult(code_contract_reject(func_id, "tree contract rejected: " .. class_name(self.issue)))
    end

    local function code_contract_fact(module_facts, sigs, func_name, func_id, fact)
        return fact:lower_tree_contract_fact_to_code(Tr.TreeCodeContractInput(module_facts, sigs, func_name, func_id), func_name, func_id).fact
    end

    local function build_module_parts(module, opts)
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
        local sigs = Tr.TreeCodeModuleSigState(mod_name, {}, {})
        local registrations = Tr.TreeCodeModuleRegistrationState({}, {}, {})
        local emission = Tr.TreeCodeModuleEmissionState({}, {})
        local input = Tr.TreeCodeItemRegisterInput(module_facts, sigs, registrations)
        for i = 1, #(module.items or {}) do
            module.items[i]:lower_tree_item_register_to_code(input)
        end
        return module_facts, sigs, registrations, emission
    end

    function Tr.Item:lower_tree_item_register_to_code(input) end
    function Tr.Item:tree_code_add_const_entries(entries, mod_name) end
    function Tr.ItemConst:tree_code_add_const_entries(entries, mod_name)
        self.c:tree_code_add_const_entries(entries, mod_name)
    end
    function Tr.ConstItem:tree_code_add_const_entries(entries, mod_name)
        entries[#entries + 1] = Bind.ConstEntry(mod_name, self.name, self.ty, self.value)
    end

    function Tr.ItemFunc:lower_tree_item_register_to_code(input)
        local name, _, params, result_ty = func_parts(self.func)
        local sig = CodeType.ensure_type_sig(input.sigs, param_types(params), result_ty)
        input.registrations.funcs[func_key(input.module_facts.module_name, name)] = Tr.TreeCodeFuncRegistration(code_func_id(name), sig)
    end

    function Tr.ItemExtern:lower_tree_item_register_to_code(input)
        local f = self.func
        f:tree_code_register_extern(input)
    end

    function Tr.ExternFunc:tree_code_register_extern(input)
        local param_tys = {}
        for j = 1, #(self.params or {}) do param_tys[j] = self.params[j].ty end
        local sig = CodeType.ensure_type_sig(input.sigs, param_tys, self.result)
        local ex = Code.CodeExtern(code_extern_id(self.name), self.name, self.symbol, sig, origin_generated("extern " .. self.name))
        input.registrations.externs[self.name] = ex
        input.registrations.extern_order[#input.registrations.extern_order + 1] = ex
    end

    local function lower_contracts(module, opts)
        opts = opts or {}
        local module_facts, sigs, registrations, emission = build_module_parts(module, opts)
        local mod_id = Code.CodeModuleId("module:" .. sanitize(opts.module_id or module_name(module)))
        local facts = {}
        local input = Tr.TreeCodeItemContractsInput(module_facts, sigs, registrations, emission, facts)
        for i = 1, #(module.items or {}) do
            local item = module.items[i]
            item:lower_tree_item_contracts_to_code(input)
        end
        return Code.CodeContractFactSet(mod_id, input.contract_facts)
    end

    function Tr.Item:lower_tree_item_contracts_to_code(input) end

    function Tr.ItemFunc:lower_tree_item_contracts_to_code(input)
        local name = func_parts(self.func)
        local func_id = code_func_id(name)
        local tree_facts = TreeContractFacts.facts(self.func)
        for j = 1, #(tree_facts.facts or {}) do
            input.contract_facts[#input.contract_facts + 1] = code_contract_fact(input.module_facts, input.sigs, name, func_id, tree_facts.facts[j])
        end
    end

    function Tr.Func:lower_tree_func_to_code(input)
        local name, linkage, params, result_ty, body = func_parts(self)
        local residence = collect_address_taken_stmts(body or {}, { addressed = {}, mutable = {} })
        local facts, state = new_tree_code_func_lowering(input.module_facts, input.sigs, input.registrations, input.emission, name, residence)
        local tree_code_input = Tr.TreeCodeStmtInput(facts, state)

        local entry = Code.CodeBlockId("block:" .. sanitize(name) .. ":entry")
        tree_code_input:tree_code_start_block(entry, "entry", {}, origin_generated("entry block"))

        local code_params = {}
        local sig_params = {}
        for i = 1, #(params or {}) do
            local p = params[i]
            local binding = param_binding(Core, Bind, name, p, i)
            local ty = tree_code_input:tree_code_type(p.ty)
            local value = tree_code_input:tree_code_value_id_for_binding(binding)
            tree_code_input:tree_code_state():tree_code_note_binding(binding, value)
            code_params[#code_params + 1] = Code.CodeParam(value, p.name, ty, origin_binding(binding))
            sig_params[#sig_params + 1] = ty
            if tree_code_input:tree_code_binding_is_addressed(binding) or is_aggregate_code_ty(ty) then
                tree_code_input:tree_code_bind_local_init(binding, value, p.ty, false)
            end
        end

        local result = tree_code_input:tree_code_type(result_ty)
        local sig_results = {}
        if result ~= Code.CodeTyVoid then sig_results[#sig_results + 1] = result end
        local sig = CodeType.ensure_code_sig(input.sigs, sig_params, sig_results)

        tree_code_input = tree_code_input:tree_code_lower_stmt_body(body or {})
        if tree_code_input:tree_code_state():tree_code_has_current_block() then
            if result == Code.CodeTyVoid then
                tree_code_input:tree_code_terminate(Code.CodeTermReturn({}), origin_generated("void fallthrough"))
            else
                unsupported(tree_code_input, self, "non-void function without return")
            end
        end

        return Code.CodeFunc(Code.CodeFuncId("fn:" .. name), name, linkage, sig, code_params, tree_code_input:tree_code_state().emission.locals, entry, tree_code_input:tree_code_state().emission.blocks, origin_generated("function " .. name))
    end

    local function lower_module(module, opts)
        opts = opts or {}
        local mod_name = module_name(module)
        local module_facts, sigs, registrations, emission = build_module_parts(module, opts)
        local funcs = {}
        local data = {}
        local globals = {}
        local input = Tr.TreeCodeItemLowerInput(module_facts, sigs, registrations, emission, mod_name, funcs, data, globals)
        for i = 1, #(module.items or {}) do
            module.items[i]:lower_tree_item_to_code(input)
        end
        funcs, data, globals = input.funcs, input.data, input.globals
        for i = 1, #emission.generated_data do data[#data + 1] = emission.generated_data[i] end
        return Code.CodeModule(
            Code.CodeModuleId("module:" .. sanitize(opts.module_id or module_name(module))),
            sigs.code_sig_order,
            {}, data, globals, registrations.extern_order, funcs,
            origin_generated("tree_to_code module")
        )
    end

    function Tr.Item:lower_tree_item_to_code(input) end

    function Tr.ItemFunc:lower_tree_item_to_code(input)
        input.funcs[#input.funcs + 1] = self.func:lower_tree_func_to_code(input)
    end

    function Tr.ItemData:lower_tree_item_to_code(input)
        input.data[#input.data + 1] = Code.CodeData(code_data_id(self.data.id), self.data.id.text, Code.CodeLinkageLocal, self.data.size, self.data.align, { Code.CodeDataBytes(0, self.data.bytes) }, origin_generated("data " .. tostring(self.data.id.text)))
    end

    function Tr.ItemConst:lower_tree_item_to_code(input)
        self.c:tree_code_lower_const_item(input)
    end

    function Tr.ConstItem:tree_code_lower_const_item(input)
        input.globals[#input.globals + 1] = self:tree_code_lower_global_to_code(input)
    end

    function Tr.ItemStatic:lower_tree_item_to_code(input)
        self.s:tree_code_lower_static_item(input)
    end

    function Tr.StaticItem:tree_code_lower_static_item(input)
        input.globals[#input.globals + 1] = self:tree_code_lower_global_to_code(input)
    end

    function Tr.ItemExtern:lower_tree_item_to_code(input) end
    function Tr.ItemType:lower_tree_item_to_code(input) end
    function Tr.ItemImport:lower_tree_item_to_code(input) end

    function Tr.ItemRegion:lower_tree_item_to_code(input)
        unsupported(Tr.TreeCodeContractInput(input.module_facts, input.sigs, input.mod_name, Code.CodeFuncId("invalid:region")), self, "region item leaked past frontend expansion/typecheck")
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
