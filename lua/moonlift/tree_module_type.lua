local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.MoonCore
    local Ty = T.MoonType
    local B = T.MoonBind
    local Tr = T.MoonTree

    local module_name
    local func_entry
    local extern_entry
    local const_entry
    local static_entry
    local type_entry
    local item_env_entries
    local module_env

    local function pack(g, p, c) return { g, p, c } end

    module_name = pvm.phase("moon2_tree_module_name", {
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

    func_entry = pvm.phase("moon2_tree_func_value_entry", {
        [Tr.FuncLocal] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name)))) end,
        [Tr.FuncExport] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name)))) end,
        [Tr.FuncLocalContract] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name)))) end,
        [Tr.FuncExportContract] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("func:" .. mod_name .. ":" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassGlobalFunc(mod_name, self.name)))) end,
        [Tr.FuncOpen] = function(self, mod_name) return pvm.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("func:" .. self.sym.key), self.sym.name, Ty.TFunc({}, self.result), B.BindingClassFuncSym(self.sym)))) end,
    }, { args_cache = "last" })

    extern_entry = pvm.phase("moon2_tree_extern_value_entry", {
        [Tr.ExternFunc] = function(self) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("extern:" .. self.name), self.name, params_type(self.params, self.result), B.BindingClassExtern(self.symbol)))) end,
        [Tr.ExternFuncOpen] = function(self) return pvm.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("extern:" .. self.sym.key), self.sym.name, Ty.TFunc({}, self.result), B.BindingClassExternSym(self.sym)))) end,
    })

    const_entry = pvm.phase("moon2_tree_const_value_entry", {
        [Tr.ConstItem] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("const:" .. mod_name .. ":" .. self.name), self.name, self.ty, B.BindingClassGlobalConst(mod_name, self.name)))) end,
        [Tr.ConstItemOpen] = function(self) return pvm.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("const:" .. self.sym.key), self.sym.name, self.ty, B.BindingClassConstSym(self.sym)))) end,
    }, { args_cache = "last" })

    static_entry = pvm.phase("moon2_tree_static_value_entry", {
        [Tr.StaticItem] = function(self, mod_name) return pvm.once(B.ValueEntry(self.name, B.Binding(C.Id("static:" .. mod_name .. ":" .. self.name), self.name, self.ty, B.BindingClassGlobalStatic(mod_name, self.name)))) end,
        [Tr.StaticItemOpen] = function(self) return pvm.once(B.ValueEntry(self.sym.name, B.Binding(C.Id("static:" .. self.sym.key), self.sym.name, self.ty, B.BindingClassStaticSym(self.sym)))) end,
    }, { args_cache = "last" })

    type_entry = pvm.phase("moon2_tree_type_entry", {
        [Tr.TypeDeclStruct] = function(self, mod_name) return pvm.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)))) end,
        [Tr.TypeDeclUnion] = function(self, mod_name) return pvm.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)))) end,
        [Tr.TypeDeclEnumSugar] = function(self, mod_name) return pvm.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)))) end,
        [Tr.TypeDeclTaggedUnionSugar] = function(self, mod_name) return pvm.once(B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)))) end,
        [Tr.TypeDeclOpenStruct] = function(self) return pvm.once(B.TypeEntry(self.sym.name, Ty.TNamed(Ty.TypeRefLocal(self.sym)))) end,
        [Tr.TypeDeclOpenUnion] = function(self) return pvm.once(B.TypeEntry(self.sym.name, Ty.TNamed(Ty.TypeRefLocal(self.sym)))) end,
    }, { args_cache = "last" })

    item_env_entries = pvm.phase("moon2_tree_item_env_entries", {
        [Tr.ItemFunc] = function(self, mod_name) return func_entry(self.func, mod_name) end,
        [Tr.ItemExtern] = function(self) return extern_entry(self.func) end,
        [Tr.ItemConst] = function(self, mod_name) return const_entry(self.c, mod_name) end,
        [Tr.ItemStatic] = function(self, mod_name) return static_entry(self.s, mod_name) end,
        [Tr.ItemType] = function(self, mod_name) return type_entry(self.t, mod_name) end,
        [Tr.ItemImport] = function() return pvm.empty() end,
        [Tr.ItemUseTypeDeclSlot] = function() return pvm.empty() end,
        [Tr.ItemUseItemsSlot] = function() return pvm.empty() end,
        [Tr.ItemUseModule] = function(self, mod_name) return pvm.children(function(item) return item_env_entries(item, mod_name) end, self.module.items) end,
        [Tr.ItemUseModuleSlot] = function() return pvm.empty() end,
    }, { args_cache = "last" })

    module_env = pvm.phase("moon2_tree_module_env", {
        [Tr.Module] = function(module)
            local mod_name = pvm.one(module_name(module.h))
            local values = {}
            local types = {}
            for i = 1, #module.items do
                local entries = pvm.drain(item_env_entries(module.items[i], mod_name))
                for j = 1, #entries do
                    if pvm.classof(entries[j]) == B.ValueEntry then values[#values + 1] = entries[j] end
                    if pvm.classof(entries[j]) == B.TypeEntry then types[#types + 1] = entries[j] end
                end
            end
            return pvm.once(B.Env(mod_name, values, types, {}))
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
