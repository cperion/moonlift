local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local C = T.MoonCore
    local Ty = T.MoonType
    local B = T.MoonBind
    local Sem = T.MoonSem
    local Tr = T.MoonTree

    local layout_api = require("moonlift.type_size_align").Define(T)

    local module_name
    local func_entry
    local extern_entry
    local const_entry
    local static_entry
    local type_entry
    local item_env_entries
    local module_env
    local item_layout

    local function pack(g, p, c) return { g, p, c } end

    function module_name(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ModuleTyped) then
            return (function(self)
 return erased.once(self.module_name)
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleSem) then
            return (function(self)
 return erased.once(self.module_name)
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleCode) then
            return (function(self)
 return erased.once(self.module_name)
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleOpen) then
            return (function(self)

            if self.name ~= T.MoonOpen.ModuleNameOpen then return erased.once(self.name.module_name) end
            return erased.once("")
            end)(node, ...)
        elseif schema.isa(node, Tr.ModuleSurface) then
            return (function()
 return erased.once("")
            end)(node, ...)
        else
            error("erased phase moonlift_tree_module_name: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function params_type(params, result)
        local tys = {}
        for i = 1, #params do tys[#tys + 1] = params[i].ty end
        return Ty.TFunc(tys, result)
    end

    function func_entry(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.FuncLocal) then
            return (function(self, mod_name)
 return erased.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExport) then
            return (function(self, mod_name)
 return erased.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncLocalContract) then
            return (function(self, mod_name)
 return erased.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExportContract) then
            return (function(self, mod_name)
 return erased.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncOpen) then
            return (function(self, mod_name)
 return erased.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("func:" .. self.sym.key), self.sym.name, Ty.TFunc({}, self.result), B.BindingClassOpenSym(C.OpenSym(C.SymKindFunc, self.sym.key, self.sym.name, "")))))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_func_value_entry: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function extern_entry(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExternFunc) then
            return (function(self)
 return erased.once(B.ValueEntry(self.name, B.Binding(C.Id("extern:" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassExtern(self.symbol))))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExternFuncOpen) then
            return (function(self)
 return erased.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("extern:" .. self.sym.key), self.sym.name, Ty.TFunc({}, self.result), B.BindingClassOpenSym(C.OpenSym(C.SymKindExtern, self.sym.key, self.sym.name, self.sym.symbol)))))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_extern_value_entry: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function const_entry(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ConstItem) then
            return (function(self, mod_name)
 return erased.once(B.ValueEntry(self.name, B.Binding(C.Id("const:" .. mod_name .. ":" .. self.name), self.name, self.ty, B.BindingClassGlobalConst(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.ConstItemOpen) then
            return (function(self)
 return erased.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("const:" .. self.sym.key), self.sym.name, self.ty, B.BindingClassOpenSym(C.OpenSym(C.SymKindConst, self.sym.key, self.sym.name, "")))))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_const_value_entry: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function static_entry(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StaticItem) then
            return (function(self, mod_name)
 return erased.once(B.ValueEntry(self.name, B.Binding(C.Id("static:" .. mod_name .. ":" .. self.name), self.name, self.ty, B.BindingClassGlobalStatic(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.StaticItemOpen) then
            return (function(self)
 return erased.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("static:" .. self.sym.key), self.sym.name, self.ty, B.BindingClassOpenSym(C.OpenSym(C.SymKindStatic, self.sym.key, self.sym.name, "")))))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_static_value_entry: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function type_entry(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.TypeDeclStruct) then
            return (function(self, mod_name)
 return erased.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclUnion) then
            return (function(self, mod_name)
 return erased.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclEnumSugar) then
            return (function(self, mod_name)
 return erased.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclTaggedUnionSugar) then
            return (function(self, mod_name)
 return erased.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name))))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclHandle) then
            return (function(self, mod_name)
 return erased.once(B.TypeEntry(self.name, Ty.THandle(Ty.TypeRefGlobal(mod_name, self.name), self.repr)))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclOpenStruct) then
            return (function(self)
 return erased.once(B.TypeEntry(self.sym.name, Ty.TNamed(Ty.TypeRefLocal(self.sym))))
            end)(node, ...)
        elseif schema.isa(node, Tr.TypeDeclOpenUnion) then
            return (function(self)
 return erased.once(B.TypeEntry(self.sym.name, Ty.TNamed(Ty.TypeRefLocal(self.sym))))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_type_entry: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function align_up(x, a)
        if a <= 1 then return x end
        return math.floor((x + a - 1) / a) * a
    end

    local function tag_ty() return Ty.TScalar(C.ScalarU32) end
    local function payload_byte_array(size) return Ty.TArray(Ty.ArrayLenConst(size), Ty.TScalar(C.ScalarU8)) end

    local function field_layout(fields, env, is_union, target)
        local out, offset, max_size, max_align = {}, 0, 0, 1
        for i = 1, #fields do
            local r = layout_api.result(fields[i].ty, env, target)
            local size, align = 0, 1
            if schema.classof(r) == Ty.TypeMemLayoutKnown then size, align = r.layout.size, r.layout.align end
            if is_union then
                out[#out + 1] = Sem.FieldLayout(fields[i].field_name, 0, fields[i].ty)
                if size > max_size then max_size = size end
                if align > max_align then max_align = align end
            else
                offset = align_up(offset, align)
                out[#out + 1] = Sem.FieldLayout(fields[i].field_name, offset, fields[i].ty)
                offset = offset + size
                if align > max_align then max_align = align end
            end
        end
        local size = is_union and max_size or offset
        return out, align_up(size, max_align), max_align
    end

    function item_layout(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ItemType) then
            return (function(self, mod_name, env, target)

            local t = self.t
            local cls = schema.classof(t)
            if cls == Tr.TypeDeclStruct or cls == Tr.TypeDeclUnion then
                local fields, size, align = field_layout(t.fields, env, cls == Tr.TypeDeclUnion, target)
                return erased.once(Sem.LayoutNamed(mod_name, t.name, fields, size, align))
            end
            if cls == Tr.TypeDeclOpenStruct or cls == Tr.TypeDeclOpenUnion then
                local fields, size, align = field_layout(t.fields, env, cls == Tr.TypeDeclOpenUnion, target)
                return erased.once(Sem.LayoutLocal(t.sym, fields, size, align))
            end
            if cls == Tr.TypeDeclEnumSugar then
                local tag_layout = layout_api.result(tag_ty(), env, target).layout
                return erased.once(Sem.LayoutNamed(mod_name, t.name, { Sem.FieldLayout("__tag", 0, tag_ty()) }, tag_layout.size, tag_layout.align))
            end
            if cls == Tr.TypeDeclHandle then
                local repr_ty = Ty.THandle(Ty.TypeRefGlobal(mod_name, t.name), t.repr)
                local layout = layout_api.result(repr_ty, env, target).layout
                return erased.once(Sem.LayoutNamed(mod_name, t.name, { Sem.FieldLayout("__handle", 0, repr_ty) }, layout.size, layout.align))
            end
            if cls == Tr.TypeDeclTaggedUnionSugar then
                local tag_layout = layout_api.result(tag_ty(), env, target).layout
                local payload_size, payload_align = 0, 1
                for i = 1, #t.variants do
                    local v = t.variants[i]
                    local sz, al
                    if #(v.fields or {}) > 0 then
                        local _, fsz, fal = field_layout(v.fields, env, false, target)
                        sz, al = fsz, fal
                    else
                        local r = layout_api.result(v.payload, env, target)
                        local l = schema.classof(r) == Ty.TypeMemLayoutKnown and r.layout or Sem.MemLayout(0, 1)
                        sz, al = l.size, l.align
                    end
                    if sz > payload_size then payload_size = sz end
                    if al > payload_align then payload_align = al end
                end
                local fields = { Sem.FieldLayout("__tag", 0, tag_ty()) }
                local size, align = tag_layout.size, tag_layout.align
                if payload_size > 0 then
                    local payload_offset = align_up(tag_layout.size, payload_align)
                    fields[#fields + 1] = Sem.FieldLayout("__payload", payload_offset, payload_byte_array(payload_size))
                    size = payload_offset + payload_size
                    if payload_align > align then align = payload_align end
                end
                return erased.once(Sem.LayoutNamed(mod_name, t.name, fields, align_up(size, align), align))
            end
            return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemFunc) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExtern) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemConst) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemStatic) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemImport) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemRegionFrag) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExprFrag) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseTypeDeclSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseItemsSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModule) then
            return (function(self, _, env, target)

            local use_mod_name = erased.one(module_name(self.module.h))
            return erased.children(function(item) return item_layout(item, use_mod_name, env, target) end, self.module.items)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModuleSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_tree_item_layout: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function item_env_entries(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ItemFunc) then
            return (function(self, mod_name)
 return func_entry(self.func, mod_name)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExtern) then
            return (function(self)
 return extern_entry(self.func)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemConst) then
            return (function(self, mod_name)
 return const_entry(self.c, mod_name)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemStatic) then
            return (function(self, mod_name)
 return static_entry(self.s, mod_name)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemType) then
            return (function(self, mod_name)
 return type_entry(self.t, mod_name)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemImport) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemRegionFrag) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemExprFrag) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseTypeDeclSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseItemsSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModule) then
            return (function(self)

            local use_mod_name = erased.one(module_name(self.module.h))
            return erased.children(function(item) return item_env_entries(item, use_mod_name) end, self.module.items)
            end)(node, ...)
        elseif schema.isa(node, Tr.ItemUseModuleSlot) then
            return (function()
 return erased.empty()
            end)(node, ...)
        else
            error("erased phase moonlift_tree_item_env_entries: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function module_env(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.Module) then
            return (function(module, target)

            local mod_name = erased.one(module_name(module.h))
            local values = {}
            local types = {}
            local layouts = {}
            for i = 1, #module.items do
                local entries = item_env_entries(module.items[i], mod_name)
                for j = 1, #entries do
                    if schema.classof(entries[j]) == B.ValueEntry then values[#values + 1] = entries[j] end
                    if schema.classof(entries[j]) == B.TypeEntry then types[#types + 1] = entries[j] end
                end
            end
            for _ = 1, math.max(1, #module.items) do
                local pass_layouts = {}
                local layout_env = Sem.LayoutEnv(layouts)
                for i = 1, #module.items do
                    local ls = item_layout(module.items[i], mod_name, layout_env, target)
                    for j = 1, #ls do pass_layouts[#pass_layouts + 1] = ls[j] end
                end
                layouts = pass_layouts
            end
            return erased.once(B.Env(mod_name, values, types, layouts))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_module_env: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        module_name = module_name,
        item_env_entries = item_env_entries,
        module_env = module_env,
        env = function(module, target) return erased.one(module_env(module, target)) end,
    }
end

return M
