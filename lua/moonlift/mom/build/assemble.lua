-- MOM Assembly infrastructure.
-- Loads compiler source modules and assembles them into one unified Moonlift
-- module object.  Compiler modules install declarations by assigning into M:
--
--   M.TypeName = struct TypeName ... end
--   M.helper = func(...) ... end
--   M.export.entry = func(...) ... end
--   M.extern.c_symbol = extern c_symbol(...) -> ... end

local Host = require("moonlift.mlua_run")
local Manifest = require("moonlift.mom.build.manifest")

local A = {}
local MomAssembly = {}

local function is_source_type_value(v)
    return type(v) == "table" and v.kind == "type" and v.decl ~= nil
end

local function is_host_type_value(v)
    return type(v) == "table" and (
        v.kind == "struct" or v.kind == "union" or v.kind == "struct_draft" or
        v.kind == "enum" or v.kind == "tagged_union" or v.kind == "type_decl"
    )
end

local function is_func_value(v)
    return type(v) == "table" and v.visibility ~= nil and v.name ~= nil
end

local function adapt_source_type(self, name, value)
    local Tr = self.rt.T.MoonTree
    return {
        kind = "type_decl",
        name = name,
        item = Tr.ItemType(value.decl),
        type = value,
        decl = value.decl,
    }
end

local function install_type(self, name, value)
    if self.verbose then io.stderr:write("mom assemble: type " .. tostring(name) .. "\n") end
    self.names[name] = "type"
    self.types[#self.types + 1] = value
    self.values[name] = value

    if value.item ~= nil or type(value.as_item) == "function" then
        self.module:add_type(value)
    elseif is_source_type_value(value) then
        self.module:add_type(adapt_source_type(self, name, value))
    else
        error("MOM type " .. tostring(name) .. " has no item or decl", 3)
    end
    return value
end

local function install_func(self, name, value, kind)
    if self.verbose then io.stderr:write("mom assemble: " .. kind .. " " .. tostring(name) .. "\n") end
    self.names[name] = kind
    self.funcs[#self.funcs + 1] = value
    self.values[name] = value
    if kind == "export_func" then self.exports[name] = true end
    if kind == "extern_func" then self.externs[#self.externs + 1] = value end
    self.module:add_func(value)
    return value
end

local function install_decl(self, name, value, kind)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), "invalid MOM declaration name: " .. tostring(name))

    local effective_kind = kind
    if kind == "type" or is_source_type_value(value) or is_host_type_value(value) then
        effective_kind = "type"
    end

    local prior = self.names[name]
    if prior ~= nil then
        error("duplicate MOM item " .. name .. " as " .. effective_kind .. ", previous " .. tostring(prior), 3)
    end

    if effective_kind == "type" then
        return install_type(self, name, value)
    end
    if kind == "extern_func" then
        assert(is_func_value(value), "M.extern." .. name .. " expects an extern function value")
        return install_func(self, name, value, "extern_func")
    end
    if kind == "export_func" then
        assert(is_func_value(value), "M.export." .. name .. " expects a function value")
        return install_func(self, name, value, "export_func")
    end
    if is_func_value(value) then
        return install_func(self, name, value, "local_func")
    end

    self.names[name] = "value"
    self.values[name] = value
    return value
end

local function namespace(parent, kind)
    return setmetatable({}, {
        __newindex = function(_, name, value)
            install_decl(parent, name, value, kind)
        end,
        __index = function(_, name)
            return parent.values[name]
        end,
    })
end

MomAssembly.__index = function(self, key)
    local method = MomAssembly[key]
    if method ~= nil then return method end
    return self.values[key]
end

MomAssembly.__newindex = function(self, name, value)
    install_decl(self, name, value, "local_func")
end

-- Compatibility helpers are kept as aliases during the mechanical conversion,
-- but compiler modules should prefer assignment syntax.
function MomAssembly:type(name, value)
    return install_decl(self, name, value, "type")
end

function MomAssembly:local_func(name, value)
    return install_decl(self, name, value, "local_func")
end

function MomAssembly:export_func(name, value)
    return install_decl(self, name, value, "export_func")
end

function MomAssembly:extern_func(name, value)
    return install_decl(self, name, value, "extern_func")
end

function MomAssembly:struct(name, fields)
    return install_decl(self, name, self.module:struct(name, fields), "type")
end

function MomAssembly:union(name, fields)
    return install_decl(self, name, self.module:union(name, fields), "type")
end

-- Create a new assembly context.
function A.new(opts)
    opts = opts or {}
    local carrier, rt = Host.loadfile(Manifest.compiler_sources[1])
    local api = rt.session:api()
    local module = api.module(opts.name or "mom")
    local self = setmetatable({
        rt = rt,
        api = api,
        module = module,
        names = {},
        values = {},
        types = {},
        funcs = {},
        exports = {},
        externs = {},
        verbose = opts.verbose or os.getenv("MOM_ASSEMBLE_TRACE") == "1",
    }, MomAssembly)
    rawset(self, "export", namespace(self, "export_func"))
    rawset(self, "extern", namespace(self, "extern_func"))
    return self, carrier
end

-- Load all compiler sources and install into assembly.
function A.load(opts)
    opts = opts or {}
    local verbose = opts.verbose or os.getenv("MOM_ASSEMBLE_TRACE") == "1"
    local assembly, first_carrier = A.new(opts)

    for i, path in ipairs(Manifest.compiler_sources) do
        if verbose then io.stderr:write(string.format("mom assemble [%02d/%02d] %s\n", i, #Manifest.compiler_sources, path)) end
        local carrier
        if i == 1 then
            carrier = first_carrier
        else
            carrier = assert(Host.loadfile(path, { runtime = assembly.rt }))
        end
        local installer = carrier()
        assert(type(installer) == "function", path .. " must return function(M) ... return M end")
        local returned = installer(assembly)
        assert(returned == assembly, path .. " did not return the assembly object")
    end

    return assembly
end

-- Emit precompiled object.
function A.emit_object(opts)
    opts = opts or {}
    local verbose = opts.verbose or os.getenv("MOM_ASSEMBLE_TRACE") == "1"
    local assembly = A.load({ name = opts.name or "mom", verbose = verbose })
    if verbose then io.stderr:write("mom assemble: lowering/emitting object\n") end
    local artifact = assembly.module:emit_object({ module_name = opts.module_name or "libmom_precompiled" })
    if verbose then io.stderr:write("mom assemble: object artifact ready\n") end
    return artifact
end

return A
