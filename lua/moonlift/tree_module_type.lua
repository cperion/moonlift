local pvm = require("moonlift.pvm")

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

    module_name = pvm.phase("moonlift_tree_module_name", {
        [Tr.ModuleTyped] = function(self) return pvm.once(self.module_name) end,
        [Tr.ModuleSem] = function(self) return pvm.once(self.module_name) end,
        [Tr.ModuleCode] = function(self) return pvm.once(self.module_name) end,
        [Tr.ModuleOpen] = function(self)
            if self.name ~= T.MoonOpen.ModuleNameOpen then return pvm.once(self.name.module_name) end
            return pvm.once("")
        end,
        [Tr.ModuleSurface] = function() return pvm.once("") end,
    })

    local function params_type(params, result)
        local tys = {}
        for i = 1, #params do tys[#tys + 1] = params[i].ty end
        return Ty.TFunc(tys, result)
    end

    func_entry = pvm.phase("moonlift_tree_func_value_entry", {
        [Tr.FuncLocal] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name)))) end,
        [Tr.FuncExport] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name)))) end,
        [Tr.FuncLocalContract] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name)))) end,
        [Tr.FuncExportContract] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name)))) end,
        [Tr.FuncOpen] = function(self, mod_name) return pvm.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("func:" .. self.sym.key), self.sym.name, Ty.TFunc({}, self.result), B.BindingClassFuncSym(self.sym)))) end,
    }, { args_cache = "last" })

    extern_entry = pvm.phase("moonlift_tree_extern_value_entry", {
        [Tr.ExternFunc] = function(self) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("extern:" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassExtern(self.symbol)))) end,
        [Tr.ExternFuncOpen] = function(self) return pvm.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("extern:" .. self.sym.key), self.sym.name, Ty.TFunc({}, self.result), B.BindingClassExternSym(self.sym)))) end,
    })

    const_entry = pvm.phase("moonlift_tree_const_value_entry", {
        [Tr.ConstItem] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("const:" .. mod_name .. ":" .. self.name), self.name, self.ty, B.BindingClassGlobalConst(mod_name, self.name)))) end,
        [Tr.ConstItemOpen] = function(self) return pvm.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("const:" .. self.sym.key), self.sym.name, self.ty, B.BindingClassConstSym(self.sym)))) end,
    }, { args_cache = "last" })

    static_entry = pvm.phase("moonlift_tree_static_value_entry", {
        [Tr.StaticItem] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("static:" .. mod_name .. ":" .. self.name), self.name, self.ty, B.BindingClassGlobalStatic(mod_name, self.name)))) end,
        [Tr.StaticItemOpen] = function(self) return pvm.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("static:" .. self.sym.key), self.sym.name, self.ty, B.BindingClassStaticSym(self.sym)))) end,
    }, { args_cache = "last" })

    type_entry = pvm.phase("moonlift_tree_type_entry", {
        [Tr.TypeDeclStruct] = function(self, mod_name) return pvm.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)))) end,
        [Tr.TypeDeclUnion] = function(self, mod_name) return pvm.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)))) end,
        [Tr.TypeDeclEnumSugar] = function(self, mod_name) return pvm.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)))) end,
        [Tr.TypeDeclTaggedUnionSugar] = function(self, mod_name) return pvm.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)))) end,
        [Tr.TypeDeclOpenStruct] = function(self) return pvm.once(B.TypeEntry(self.sym.name, Ty.TNamed(Ty.TypeRefLocal(self.sym)))) end,
        [Tr.TypeDeclOpenUnion] = function(self) return pvm.once(B.TypeEntry(self.sym.name, Ty.TNamed(Ty.TypeRefLocal(self.sym)))) end,
    }, { args_cache = "last" })

    local function align_up(x, a)
        if a <= 1 then return x end
        return math.floor((x + a - 1) / a) * a
    end

    local function field_layout(fields, env, is_union)
        local out, offset, max_size, max_align = {}, 0, 0, 1
        for i = 1, #fields do
            local r = layout_api.result(fields[i].ty, env)
            local size, align = 0, 1
            if pvm.classof(r) == Ty.TypeMemLayoutKnown then size, align = r.layout.size, r.layout.align end
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

    item_layout = pvm.phase("moonlift_tree_item_layout", {
        [Tr.ItemType] = function(self, mod_name, env)
            local t = self.t
            local cls = pvm.classof(t)
            if cls == Tr.TypeDeclStruct or cls == Tr.TypeDeclUnion then
                local fields, size, align = field_layout(t.fields, env, cls == Tr.TypeDeclUnion)
                return pvm.once(Sem.LayoutNamed(mod_name, t.name, fields, size, align))
            end
            if cls == Tr.TypeDeclOpenStruct or cls == Tr.TypeDeclOpenUnion then
                local fields, size, align = field_layout(t.fields, env, cls == Tr.TypeDeclOpenUnion)
                return pvm.once(Sem.LayoutLocal(t.sym, fields, size, align))
            end
            return pvm.empty()
        end,
        [Tr.ItemFunc] = function() return pvm.empty() end,
        [Tr.ItemExtern] = function() return pvm.empty() end,
        [Tr.ItemConst] = function() return pvm.empty() end,
        [Tr.ItemStatic] = function() return pvm.empty() end,
        [Tr.ItemImport] = function() return pvm.empty() end,
        [Tr.ItemUseTypeDeclSlot] = function() return pvm.empty() end,
        [Tr.ItemUseItemsSlot] = function() return pvm.empty() end,
        [Tr.ItemUseModule] = function(self, _, env)
            local use_mod_name = pvm.one(module_name(self.module.h))
            return pvm.children(function(item) return item_layout(item, use_mod_name, env) end, self.module.items)
        end,
        [Tr.ItemUseModuleSlot] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    item_env_entries = pvm.phase("moonlift_tree_item_env_entries", {
        [Tr.ItemFunc] = function(self, mod_name) return func_entry(self.func, mod_name) end,
        [Tr.ItemExtern] = function(self) return extern_entry(self.func) end,
        [Tr.ItemConst] = function(self, mod_name) return const_entry(self.c, mod_name) end,
        [Tr.ItemStatic] = function(self, mod_name) return static_entry(self.s, mod_name) end,
        [Tr.ItemType] = function(self, mod_name) return type_entry(self.t, mod_name) end,
        [Tr.ItemImport] = function() return pvm.empty() end,
        [Tr.ItemUseTypeDeclSlot] = function() return pvm.empty() end,
        [Tr.ItemUseItemsSlot] = function() return pvm.empty() end,
        [Tr.ItemUseModule] = function(self)
            local use_mod_name = pvm.one(module_name(self.module.h))
            return pvm.children(function(item) return item_env_entries(item, use_mod_name) end, self.module.items)
        end,
        [Tr.ItemUseModuleSlot] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    module_env = pvm.phase("moonlift_tree_module_env", {
        [Tr.Module] = function(module)
            local mod_name = pvm.one(module_name(module.h))
            local values = {}
            local types = {}
            local layouts = {}
            for i = 1, #module.items do
                local entries = pvm.drain(item_env_entries(module.items[i], mod_name))
                for j = 1, #entries do
                    if pvm.classof(entries[j]) == B.ValueEntry then values[#values + 1] = entries[j] end
                    if pvm.classof(entries[j]) == B.TypeEntry then types[#types + 1] = entries[j] end
                end
            end
            local layout_env = Sem.LayoutEnv(layouts)
            for i = 1, #module.items do
                local ls = pvm.drain(item_layout(module.items[i], mod_name, layout_env))
                for j = 1, #ls do layouts[#layouts + 1] = ls[j] end
                layout_env = Sem.LayoutEnv(layouts)
            end
            return pvm.once(B.Env(mod_name, values, types, layouts))
        end,
    })

    return {
        module_name = module_name,
        item_env_entries = item_env_entries,
        module_env = module_env,
        env = function(module) return pvm.one(module_env(module)) end,
    }
end

return M
