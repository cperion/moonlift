local pvm = require("pvm")

local M = {}

local function copy_array(src)
    local out = {}
    if src == nil then return out end
    for i = 1, #src do out[i] = src[i] end
    return out
end

function M.Define(T)
    local Meta = T.MoonliftMeta
    local Elab = T.MoonliftElab
    if Meta == nil or Elab == nil then error("meta_source: Meta and Elab modules must be defined", 2) end

    local Parse = require("moonlift.parse").Define(T)
    local Desugar = require("moonlift.desugar_closures")
    local SurfaceToElab = require("moonlift.lower_surface_to_elab_loop").Define(T)
    local SurfaceToElabTop = require("moonlift.lower_surface_to_elab_top").Define(T)
    local ElabToMeta = require("moonlift.lower_elab_to_meta").Define(T)
    local Seal = require("moonlift.seal_meta_to_elab").Define(T)
    local Expand = require("moonlift.expand_meta").Define(T)

    local meta_slot_to_elab_type
    local meta_type_to_elab_source
    local meta_layout_to_elab_source
    local meta_slot_env_entry
    local meta_value_import_env_entry

    local function one(boundary, node, a, b)
        if b ~= nil then return pvm.one(boundary(node, a, b)) end
        if a ~= nil then return pvm.one(boundary(node, a)) end
        return pvm.one(boundary(node))
    end
    local function one_meta_type(node, env) return one(meta_type_to_elab_source, node, env) end
    local function one_layout(node, env) return one(meta_layout_to_elab_source, node, env) end
    local function one_slot_entry(node, module_name) return one(meta_slot_env_entry, node, module_name) end
    local function one_import_entry(node, module_name) return one(meta_value_import_env_entry, node, module_name) end

    local function elab_fields(fields, env)
        local out = {}
        for i = 1, #(fields or {}) do
            local f = fields[i]
            out[i] = Elab.ElabFieldType(f.field_name, one_meta_type(f.ty, env))
        end
        return out
    end

    meta_slot_to_elab_type = pvm.phase("meta_source_slot_to_elab_type", {
        [Meta.MetaTypeSlot] = function(self) return pvm.once(Elab.ElabTNamed("$meta.type_slot", self.key)) end,
    })

    meta_type_to_elab_source = pvm.phase("meta_source_type_to_elab", {
        [Meta.MetaTVoid] = function() return pvm.once(Elab.ElabTVoid) end,
        [Meta.MetaTBool] = function() return pvm.once(Elab.ElabTBool) end,
        [Meta.MetaTI8] = function() return pvm.once(Elab.ElabTI8) end,
        [Meta.MetaTI16] = function() return pvm.once(Elab.ElabTI16) end,
        [Meta.MetaTI32] = function() return pvm.once(Elab.ElabTI32) end,
        [Meta.MetaTI64] = function() return pvm.once(Elab.ElabTI64) end,
        [Meta.MetaTU8] = function() return pvm.once(Elab.ElabTU8) end,
        [Meta.MetaTU16] = function() return pvm.once(Elab.ElabTU16) end,
        [Meta.MetaTU32] = function() return pvm.once(Elab.ElabTU32) end,
        [Meta.MetaTU64] = function() return pvm.once(Elab.ElabTU64) end,
        [Meta.MetaTF32] = function() return pvm.once(Elab.ElabTF32) end,
        [Meta.MetaTF64] = function() return pvm.once(Elab.ElabTF64) end,
        [Meta.MetaTIndex] = function() return pvm.once(Elab.ElabTIndex) end,
        [Meta.MetaTPtr] = function(self, env) return pvm.once(Elab.ElabTPtr(one_meta_type(self.elem, env))) end,
        [Meta.MetaTArray] = function(self, env)
            local count = Seal.expr(Expand.expr(self.count), env and env.seal_env or Seal.env(env and env.module_name or ""))
            return pvm.once(Elab.ElabTArray(count, one_meta_type(self.elem, env)))
        end,
        [Meta.MetaTSlice] = function(self, env) return pvm.once(Elab.ElabTSlice(one_meta_type(self.elem, env))) end,
        [Meta.MetaTView] = function(self, env) return pvm.once(Elab.ElabTView(one_meta_type(self.elem, env))) end,
        [Meta.MetaTFunc] = function(self, env)
            local params = {}
            for i = 1, #self.params do params[i] = one_meta_type(self.params[i], env) end
            return pvm.once(Elab.ElabTFunc(params, one_meta_type(self.result, env)))
        end,
        [Meta.MetaTNamed] = function(self) return pvm.once(Elab.ElabTNamed(self.module_name, self.type_name)) end,
        [Meta.MetaTLocalNamed] = function(self, env) return pvm.once(Elab.ElabTNamed(env.module_name or "", self.sym.name)) end,
        [Meta.MetaTSlot] = function(self) return pvm.once(pvm.one(meta_slot_to_elab_type(self.slot))) end,
    })

    meta_layout_to_elab_source = pvm.phase("meta_source_layout_to_elab", {
        [Meta.MetaLayoutNamed] = function(self, env) return pvm.once(Elab.ElabLayoutNamed(self.module_name, self.type_name, elab_fields(self.fields, env))) end,
        [Meta.MetaLayoutLocal] = function(self, env) return pvm.once(Elab.ElabLayoutNamed(env.module_name or "", self.sym.name, elab_fields(self.fields, env))) end,
    })

    meta_slot_env_entry = pvm.phase("meta_source_slot_env_entry", {
        [Meta.MetaSlotType] = function(self)
            local ty = pvm.one(meta_slot_to_elab_type(self.slot))
            return pvm.once({ type_entry = Elab.ElabTypeEntry(self.slot.pretty_name, ty), type_map = Meta.MetaSourceTypeEntry(ty, Meta.MetaTSlot(self.slot)) })
        end,
        [Meta.MetaSlotExpr] = function(self, module_name)
            local ty = one_meta_type(self.slot.ty, { module_name = module_name })
            local binding = Elab.ElabLocalValue("$meta.expr_slot." .. self.slot.key, self.slot.pretty_name, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.slot.pretty_name, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceExprSlotBinding(self.slot)) })
        end,
        [Meta.MetaSlotFunc] = function(self, module_name)
            local ty = one_meta_type(self.slot.fn_ty, { module_name = module_name })
            local binding = Elab.ElabLocalValue("$meta.func_slot." .. self.slot.key, self.slot.pretty_name, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.slot.pretty_name, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceFuncSlotBinding(self.slot)) })
        end,
        [Meta.MetaSlotConst] = function(self, module_name)
            local ty = one_meta_type(self.slot.ty, { module_name = module_name })
            local binding = Elab.ElabLocalValue("$meta.const_slot." .. self.slot.key, self.slot.pretty_name, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.slot.pretty_name, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceConstSlotBinding(self.slot)) })
        end,
        [Meta.MetaSlotStatic] = function(self, module_name)
            local ty = one_meta_type(self.slot.ty, { module_name = module_name })
            local binding = Elab.ElabLocalValue("$meta.static_slot." .. self.slot.key, self.slot.pretty_name, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.slot.pretty_name, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceStaticSlotBinding(self.slot)) })
        end,
        [Meta.MetaSlotPlace] = function() return pvm.once({}) end,
        [Meta.MetaSlotDomain] = function() return pvm.once({}) end,
        [Meta.MetaSlotRegion] = function() return pvm.once({}) end,
        [Meta.MetaSlotTypeDecl] = function() return pvm.once({}) end,
        [Meta.MetaSlotItems] = function() return pvm.once({}) end,
        [Meta.MetaSlotModule] = function() return pvm.once({}) end,
    })

    meta_value_import_env_entry = pvm.phase("meta_source_value_import_env_entry", {
        [Meta.MetaImportValue] = function(self, module_name)
            local ty = one_meta_type(self.ty, { module_name = module_name })
            local binding = Elab.ElabLocalValue("$meta.import." .. self.key, self.name, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.name, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceValueImportBinding(self)) })
        end,
        [Meta.MetaImportGlobalFunc] = function(self, module_name)
            local ty = one_meta_type(self.ty, { module_name = module_name })
            local binding = Elab.ElabGlobalFunc(self.module_name, self.item_name, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.key, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceValueImportBinding(self)) })
        end,
        [Meta.MetaImportGlobalConst] = function(self, module_name)
            local ty = one_meta_type(self.ty, { module_name = module_name })
            local binding = Elab.ElabGlobalConst(self.module_name, self.item_name, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.key, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceValueImportBinding(self)) })
        end,
        [Meta.MetaImportGlobalStatic] = function(self, module_name)
            local ty = one_meta_type(self.ty, { module_name = module_name })
            local binding = Elab.ElabGlobalStatic(self.module_name, self.item_name, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.key, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceValueImportBinding(self)) })
        end,
        [Meta.MetaImportExtern] = function(self, module_name)
            local ty = one_meta_type(self.ty, { module_name = module_name })
            local binding = Elab.ElabExtern(self.symbol, ty)
            return pvm.once({ value_entry = Elab.ElabValueEntry(self.key, binding), binding_map = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceValueImportBinding(self)) })
        end,
    })

    local function build_env(params, open, module_name)
        module_name = module_name or ""
        open = open or Meta.MetaOpenSet({}, {}, {}, {})
        local values, types, layouts, binding_maps, type_maps = {}, {}, {}, {}, {}
        local src_env_shell = { module_name = module_name }
        for i = 1, #(params or {}) do
            local param = params[i]
            local binding = Elab.ElabArg(i - 1, param.name, one_meta_type(param.ty, src_env_shell))
            values[#values + 1] = Elab.ElabValueEntry(param.name, binding)
            binding_maps[#binding_maps + 1] = Meta.MetaSourceBindingEntry(binding, Meta.MetaSourceParamBinding(param))
        end
        for i = 1, #open.value_imports do
            local entry = one_import_entry(open.value_imports[i], module_name)
            if entry.value_entry ~= nil then values[#values + 1] = entry.value_entry end
            if entry.binding_map ~= nil then binding_maps[#binding_maps + 1] = entry.binding_map end
        end
        for i = 1, #open.type_imports do
            local imp = open.type_imports[i]
            types[#types + 1] = Elab.ElabTypeEntry(imp.local_name, one_meta_type(imp.ty, src_env_shell))
        end
        for i = 1, #open.layouts do layouts[#layouts + 1] = one_layout(open.layouts[i], src_env_shell) end
        for i = 1, #open.slots do
            local entry = one_slot_entry(open.slots[i], module_name)
            if entry.value_entry ~= nil then values[#values + 1] = entry.value_entry end
            if entry.type_entry ~= nil then types[#types + 1] = entry.type_entry end
            if entry.binding_map ~= nil then binding_maps[#binding_maps + 1] = entry.binding_map end
            if entry.type_map ~= nil then type_maps[#type_maps + 1] = entry.type_map end
        end
        return Elab.ElabEnv(module_name, values, types, layouts), Meta.MetaSourceEnv(module_name, binding_maps, type_maps)
    end

    local function slot_key(slot)
        if slot.slot ~= nil then slot = slot.slot end
        return slot.key
    end

    local function slot_pretty_name(slot)
        if slot.slot ~= nil then slot = slot.slot end
        return slot.pretty_name or slot.name or slot.local_name or slot.key
    end

    local function open_with_slots(open, slots)
        open = open or Meta.MetaOpenSet({}, {}, {}, {})
        if slots == nil or #slots == 0 then return open end
        local out = {}
        for i = 1, #open.slots do out[#out + 1] = open.slots[i] end
        for i = 1, #slots do out[#out + 1] = slots[i].as_slot and slots[i]:as_slot() or slots[i] end
        return Meta.MetaOpenSet(open.value_imports, open.type_imports, open.layouts, out)
    end

    local function preprocess_quote_source(source, holes)
        if holes == nil then return source end
        return (source:gsub("%$([%a_][%w_]*)", function(name)
            local hole = holes[name]
            if hole == nil then error("meta_source: unknown quote hole '$" .. name .. "'", 3) end
            return slot_pretty_name(hole)
        end))
    end

    local function quote_opts(opts)
        opts = opts or {}
        return opts.params or {}, open_with_slots(opts.open, opts.slots), opts.module_name or "", opts
    end

    local api = {}
    api.build_env = build_env
    api.preprocess_quote_source = preprocess_quote_source

    function api.expr_frag(source, params, open, result, module_name)
        local elab_env, source_env = build_env(params or {}, open, module_name or "")
        local surf = Parse.parse_expr(source)
        local expected = result and one_meta_type(result, { module_name = module_name or "" }) or nil
        local elab = pvm.one(SurfaceToElab.lower_expr(surf, elab_env, expected))
        return Meta.MetaExprFrag(copy_array(params), open or Meta.MetaOpenSet({}, {}, {}, {}), ElabToMeta.expr(elab, source_env), result or ElabToMeta.type(SurfaceToElab.expr_type(elab), source_env))
    end

    function api.region_frag_stmt(source, params, open, module_name, return_ty)
        local elab_env, source_env = build_env(params or {}, open, module_name or "")
        local surf = Parse.parse_stmt(source)
        local elab_return = return_ty and one_meta_type(return_ty, { module_name = module_name or "" }) or nil
        local elab = pvm.one(SurfaceToElab.lower_stmt(surf, elab_env, "meta.region", false, nil, elab_return))
        return Meta.MetaRegionFrag(copy_array(params), open or Meta.MetaOpenSet({}, {}, {}, {}), { ElabToMeta.stmt(elab, source_env) })
    end

    function api.region_frag_stmts(sources, params, open, module_name, return_ty)
        local body = {}
        for i = 1, #sources do
            local frag = api.region_frag_stmt(sources[i], params, open, module_name, return_ty)
            body[#body + 1] = frag.body[1]
        end
        return Meta.MetaRegionFrag(copy_array(params), open or Meta.MetaOpenSet({}, {}, {}, {}), body)
    end

    function api.expr_quote(source, opts)
        local params, open, module_name, raw = quote_opts(opts)
        return api.expr_frag(preprocess_quote_source(source, raw.holes), params, open, raw.result, module_name)
    end

    function api.region_quote(source, opts)
        local params, open, module_name, raw = quote_opts(opts)
        return api.region_frag_stmt(preprocess_quote_source(source, raw.holes), params, open, module_name, raw.return_ty)
    end

    function api.region_quotes(sources, opts)
        local params, open, module_name, raw = quote_opts(opts)
        local rewritten = {}
        for i = 1, #sources do rewritten[i] = preprocess_quote_source(sources[i], raw.holes) end
        return api.region_frag_stmts(rewritten, params, open, module_name, raw.return_ty)
    end

    function api.item(source, open, module_name)
        local elab_env, source_env = build_env({}, open, module_name or "")
        local surf = Parse.parse_item(source)
        local wrapped = Desugar.desugar(T.MoonliftSurface.SurfModule({ surf }), T.MoonliftSurface)
        if #wrapped.items ~= 1 then error("meta_source: source item expanded to " .. tostring(#wrapped.items) .. " items; use module_quote for multi-item source", 2) end
        local elab = pvm.one(SurfaceToElabTop.lower_item(wrapped.items[1], elab_env))
        return ElabToMeta.phases.item and pvm.one(ElabToMeta.phases.item(elab, source_env)) or nil
    end

    function api.func(source, open, module_name)
        local item = api.item(source, open, module_name)
        if item.func == nil then error("meta_source: source item is not a function", 2) end
        return pvm.with(item.func, { open = open or Meta.MetaOpenSet({}, {}, {}, {}) })
    end

    function api.const(source, open, module_name)
        local item = api.item(source, open, module_name)
        if item.c == nil then error("meta_source: source item is not a const", 2) end
        return pvm.with(item.c, { open = open or Meta.MetaOpenSet({}, {}, {}, {}) })
    end

    function api.static(source, open, module_name)
        local item = api.item(source, open, module_name)
        if item.s == nil then error("meta_source: source item is not a static", 2) end
        return pvm.with(item.s, { open = open or Meta.MetaOpenSet({}, {}, {}, {}) })
    end

    function api.module(source, open, module_name)
        local elab_env, source_env = build_env({}, open, module_name or "")
        local surf = Desugar.desugar(Parse.parse_module(source), T.MoonliftSurface)
        local elab = pvm.one(SurfaceToElabTop.lower_module(surf, elab_env))
        local module = ElabToMeta.module(elab, source_env)
        return pvm.with(module, { open = open or Meta.MetaOpenSet({}, {}, {}, {}) })
    end

    function api.func_quote(source, opts)
        local _, open, module_name, raw = quote_opts(opts)
        return api.func(preprocess_quote_source(source, raw.holes), open, module_name)
    end

    function api.const_quote(source, opts)
        local _, open, module_name, raw = quote_opts(opts)
        return api.const(preprocess_quote_source(source, raw.holes), open, module_name)
    end

    function api.static_quote(source, opts)
        local _, open, module_name, raw = quote_opts(opts)
        return api.static(preprocess_quote_source(source, raw.holes), open, module_name)
    end

    function api.module_quote(source, opts)
        local _, open, module_name, raw = quote_opts(opts)
        return api.module(preprocess_quote_source(source, raw.holes), open, module_name)
    end

    return api
end

return M
