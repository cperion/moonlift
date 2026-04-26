local ffi = require("ffi")

local M = {}

local ModuleValue = {}
ModuleValue.__index = ModuleValue

local CompiledModule = {}
CompiledModule.__index = CompiledModule

local CompiledFunction = {}
CompiledFunction.__index = CompiledFunction

local scalar_ctype = {
    BackBool = "bool",
    BackI8 = "int8_t", BackI16 = "int16_t", BackI32 = "int32_t", BackI64 = "int64_t",
    BackU8 = "uint8_t", BackU16 = "uint16_t", BackU32 = "uint32_t", BackU64 = "uint64_t",
    BackF32 = "float", BackF64 = "double",
    BackPtr = "void *",
    BackIndex = "intptr_t",
    BackVoid = "void",
}

local function assert_name(name, site)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), site .. " expects an identifier")
end

local function append_item(self, value)
    self.items[#self.items + 1] = value.item or value:as_item()
    if type(value) == "table" and (value.kind == "struct" or value.kind == "union" or value.kind == "struct_draft") then
        self.type_values[#self.type_values + 1] = value
    end
    return value
end

function ModuleValue:add_type(value)
    return append_item(self, value)
end

function ModuleValue:add_func(value)
    if value.visibility == "export" then self.exports[value.name] = value end
    return append_item(self, value)
end

local function reserve_type_name(self, name)
    assert_name(name, "type")
    if self.type_names[name] ~= nil then self.api.raise_host_issue(self.session.T.Moon2Host.HostIssueDuplicateType(self.name, name)) end
    self.type_names[name] = true
end

local function reserve_func_name(self, name)
    assert_name(name, "func")
    if self.func_names[name] ~= nil then self.api.raise_host_issue(self.session.T.Moon2Host.HostIssueDuplicateFunc(self.name, name)) end
    self.func_names[name] = true
end

function ModuleValue:struct(name, fields)
    reserve_type_name(self, name)
    return self:add_type(self.api._module_struct(self, name, fields))
end

function ModuleValue:union(name, fields)
    reserve_type_name(self, name)
    return self:add_type(self.api._module_union(self, name, fields))
end

function ModuleValue:enum(name, variants)
    reserve_type_name(self, name)
    return self:add_type(self.api._module_enum(self, name, variants))
end

function ModuleValue:tagged_union(name, variants)
    reserve_type_name(self, name)
    return self:add_type(self.api._module_tagged_union(self, name, variants))
end

function ModuleValue:newstruct(name)
    reserve_type_name(self, name)
    return self.api._module_newstruct(self, name)
end

function ModuleValue:instantiate(template, args)
    return self.api._module_instantiate(self, template, args)
end

function ModuleValue:func(name, params, result, builder_fn)
    reserve_func_name(self, name)
    return self:add_func(self.api._module_func(self, name, params, result, builder_fn))
end

function ModuleValue:export_func(name, params, result, builder_fn)
    reserve_func_name(self, name)
    return self:add_func(self.api._module_export_func(self, name, params, result, builder_fn))
end

function ModuleValue:to_asdl()
    for i = 1, #self.drafts do
        if not self.drafts[i].sealed then self.api.raise_host_issue(self.session.T.Moon2Host.HostIssueUnsealedType(self.name, self.drafts[i].name)) end
    end
    local Tr = self.session.T.Moon2Tree
    local items = {}
    for i = 1, #self.items do items[i] = self.items[i] end
    return Tr.Module(Tr.ModuleTyped(self.name), items)
end

function ModuleValue:layout_env()
    local Sem = self.session.T.Moon2Sem
    local layouts = {}
    for i = 1, #self.type_values do
        local layout = self.session:layout_of(self.type_values[i])
        if layout ~= nil then layouts[#layouts + 1] = layout end
    end
    return Sem.LayoutEnv(layouts)
end

local function back_scalar_name(scalar)
    return tostring(scalar):match("%.([%w_]+):") or tostring(scalar):match("(Back[%w_]+)") or tostring(scalar)
end

local function ctype_of_type(api, ty_value)
    local pvm = require("moonlift.pvm")
    local T = api.T
    local Ty = T.Moon2Type
    local Back = require("moonlift.type_to_back_scalar").Define(T)
    local tv = api.as_type_value(ty_value, "ctype expects type value")
    local cls = pvm.classof(tv.ty)
    if cls == Ty.TPtr then return "void *" end
    local r = Back.result(tv.ty)
    if pvm.classof(r) ~= Ty.TypeBackScalarKnown then return "void *" end
    local name = back_scalar_name(r.scalar)
    return assert(scalar_ctype[name], "unsupported exported C type: " .. tostring(r.scalar))
end

local function c_sig_of(api, func_value)
    local pvm = require("moonlift.pvm")
    local Ty = api.T.Moon2Type
    local args = {}
    local result_ty = api.as_type_value(func_value.result, "function result type").ty
    local result_is_view = pvm.classof(result_ty) == Ty.TView
    if result_is_view then args[#args + 1] = "void *" end
    for i = 1, #func_value.params do args[#args + 1] = ctype_of_type(api, func_value.params[i].type) end
    local ret = result_is_view and "void" or ctype_of_type(api, func_value.result)
    return ret .. " (*)(" .. table.concat(args, ", ") .. ")"
end

function ModuleValue:compile()
    local pvm = require("moonlift.pvm")
    local OpenFacts = require("moonlift.open_facts")
    local OpenValidate = require("moonlift.open_validate")
    local OpenExpand = require("moonlift.open_expand")
    local Typecheck = require("moonlift.tree_typecheck")
    local SemLayout = require("moonlift.sem_layout_resolve")
    local TreeToBack = require("moonlift.tree_to_back")
    local Validate = require("moonlift.back_validate")
    local Bridge = require("moonlift.back_to_moonlift")
    local Jit = require("moonlift_legacy.jit")

    local T = self.session.T
    local OF = OpenFacts.Define(T)
    local OV = OpenValidate.Define(T)
    local OE = OpenExpand.Define(T)
    local TC = Typecheck.Define(T)
    local Layout = SemLayout.Define(T)
    local Lower = TreeToBack.Define(T)
    local V = Validate.Define(T)
    local bridge = Bridge.Define(T)
    local jit_api = Jit.Define(T)

    local module = self:to_asdl()
    local expanded = OE.module(module)
    local open_report = OV.validate(OF.facts_of_module(expanded))
    if #open_report.issues ~= 0 then error("host module open validation failed: " .. tostring(open_report.issues[1]), 2) end
    local checked = TC.check_module(expanded)
    if #checked.issues ~= 0 then error("host module typecheck failed: " .. tostring(checked.issues[1]), 2) end
    local resolved_module = Layout.module(checked.module, self:layout_env())
    local program = Lower.module(resolved_module)
    local report = V.validate(program)
    if #report.issues ~= 0 then error("host module back validation failed: " .. tostring(report.issues[1]), 2) end
    local artifact = jit_api.jit():compile(bridge.lower_program(program))
    return setmetatable({ module = self, artifact = artifact, T = T, functions = {} }, CompiledModule)
end

function ModuleValue:__tostring()
    return "Moon2ModuleValue(" .. self.name .. ")"
end

function CompiledModule:get(name)
    local cached = self.functions[name]
    if cached then return cached end
    local func = assert(self.module.exports[name], "compiled module has no exported function: " .. tostring(name))
    local B1 = self.T.MoonliftBack
    local c_sig = c_sig_of(self.module.api, func)
    local ptr = self.artifact:getpointer(B1.BackFuncId(name))
    local fn = ffi.cast(c_sig, ptr)
    local wrapped = setmetatable({ module = self, func = func, fn = fn, c_sig = c_sig }, CompiledFunction)
    self.functions[name] = wrapped
    return wrapped
end

function CompiledModule:free()
    if self.artifact then self.artifact:free(); self.artifact = nil end
end

function CompiledFunction:__call(...)
    if not self.module or not self.module.artifact then error("compiled Moonlift function called after artifact was freed", 2) end
    return self.fn(...)
end

function CompiledFunction:__tostring()
    return "CompiledMoon2Function(" .. self.func.name .. ": " .. self.c_sig .. ")"
end

function M.Install(api, session)
    local function new_module(name)
        assert_name(name, "module")
        return setmetatable({
            kind = "module",
            session = session,
            api = api,
            name = name,
            items = {},
            exports = {},
            drafts = {},
            type_values = {},
            type_names = {},
            func_names = {},
        }, ModuleValue)
    end

    function api.module(name)
        return new_module(name)
    end

    function session:module(name)
        return new_module(name)
    end

    api.ModuleValue = ModuleValue
end

return M
