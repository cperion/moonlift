local ffi = require("ffi")

local M = {}

local BundleValue = {}
BundleValue.__index = BundleValue
local ModuleValue = BundleValue  -- internal alias for compat

local CompiledModule = {}
CompiledModule.__index = CompiledModule

local CompiledFunction = {}
CompiledFunction.__index = CompiledFunction

local CCompiledModule = {}
CCompiledModule.__index = CCompiledModule

local CCompiledFunction = {}
CCompiledFunction.__index = CCompiledFunction

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
    if type(value) == "table" and (value.kind == "struct" or value.kind == "union" or value.kind == "handle" or value.kind == "struct_draft" or value.kind == "type") then
        self.type_values[#self.type_values + 1] = value
    end
    return value
end

function BundleValue:add_type(value)
    return append_item(self, value)
end

function BundleValue:add_func(value)
    if value.visibility == "export" then self.exports[value.name] = value end
    return append_item(self, value)
end

function BundleValue:add_region(value)
    if value.frag then
        self.region_frags[#self.region_frags + 1] = value.frag
    end
    return value
end

function BundleValue:pack(...)
    self._pack_seen = self._pack_seen or {}

    local function pack_one(v)
        if type(v) ~= "table" then
            error("bundle:pack() expected a Moonlift value (func, region, struct, union), got " .. type(v), 3)
        end
        if self._pack_seen[v] then return end
        self._pack_seen[v] = true

        -- Pack the explicit dependency closure first.  Quoted values record only
        -- the @{} values they actually used; no bundle compile may depend on
        -- ambient session history.
        local deps = rawget(v, "_dep_values")
        if type(deps) == "table" then
            for _, dep in pairs(deps) do
                if type(dep) == "table" then
                    local dep_kind = rawget(dep, "kind") or rawget(dep, "moonlift_quote_kind")
                    if dep_kind == "func" or dep_kind == "extern_func" or dep_kind == "region_frag"
                        or dep_kind == "struct" or dep_kind == "union" then
                        pack_one(dep)
                    end
                end
            end
        end

        local generated_items = rawget(v, "_generated_items")
        if type(generated_items) == "table" and #generated_items > 0 then
            self._generated_item_seen = self._generated_item_seen or {}
            local T = self.session.T
            local Tr = T.MoonTree
            local pvm = require("moonlift.pvm")
            for gi = 1, #generated_items do
                local item = generated_items[gi]
                local cls = pvm.classof(item)
                local key = tostring(item)
                if cls == Tr.ItemType and item.t and item.t.name then key = "type:" .. item.t.name
                elseif cls == Tr.ItemFunc and item.func and item.func.name then key = "func:" .. item.func.name end
                if not self._generated_item_seen[key] then
                    self._generated_item_seen[key] = true
                    self.items[#self.items + 1] = item
                end
            end
        end

        local kind = rawget(v, "kind") or rawget(v, "moonlift_quote_kind")
        if kind == "func" or kind == "extern_func" then
            self:add_func(v)
        elseif kind == "region_frag" or rawget(v, "moonlift_quote_kind") == "region_frag" then
            self:add_region(v)
        elseif kind == "struct" or kind == "union" then
            self:add_type(v)
        else
            error("bundle:pack() expected a Moonlift value (func, region, struct, union), got " .. type(v), 3)
        end
    end

    for i = 1, select("#", ...) do pack_one(select(i, ...)) end
    return self
end

local function reserve_type_name(self, name)
    assert_name(name, "type")
    if self.type_names[name] ~= nil then self.api.raise_host_issue(self.session.T.MoonHost.HostIssueDuplicateType(self.name, name)) end
    self.type_names[name] = true
end

local function reserve_func_name(self, name)
    assert_name(name, "func")
    if self.func_names[name] ~= nil then self.api.raise_host_issue(self.session.T.MoonHost.HostIssueDuplicateFunc(self.name, name)) end
    self.func_names[name] = true
end

function BundleValue:struct(name, fields)
    reserve_type_name(self, name)
    return self:add_type(self.api._module_struct(self, name, fields))
end

function BundleValue:union(name, fields)
    reserve_type_name(self, name)
    return self:add_type(self.api._module_union(self, name, fields))
end

function BundleValue:enum(name, variants)
    reserve_type_name(self, name)
    return self:add_type(self.api._module_enum(self, name, variants))
end

function BundleValue:tagged_union(name, variants)
    reserve_type_name(self, name)
    return self:add_type(self.api._module_tagged_union(self, name, variants))
end

function BundleValue:newstruct(name)
    reserve_type_name(self, name)
    return self.api._module_newstruct(self, name)
end

function BundleValue:instantiate(template, args)
    return self.api._module_instantiate(self, template, args)
end

function BundleValue:func(name, params, result, builder_fn)
    reserve_func_name(self, name)
    return self:add_func(self.api._module_func(self, name, params, result, builder_fn))
end

function BundleValue:extern_func(name, params, result, symbol)
    reserve_func_name(self, name)
    return self:add_func(self.api._module_extern_func(self, name, params, result, symbol))
end

function BundleValue:export_func(name, params, result, builder_fn)
    reserve_func_name(self, name)
    return self:add_func(self.api._module_export_func(self, name, params, result, builder_fn))
end

function BundleValue:symbol(name, ptr)
    assert(type(name) == "string" and name ~= "", "symbol expects an extern symbol name")
    self.extern_symbols[name] = ptr
    return self
end

function BundleValue:symbols(map)
    assert(type(map) == "table", "symbols expects a map of name -> pointer")
    for name, ptr in pairs(map) do self:symbol(name, ptr) end
    return self
end

function BundleValue:to_asdl()
    for i = 1, #self.drafts do
        if not self.drafts[i].sealed then self.api.raise_host_issue(self.session.T.MoonHost.HostIssueUnsealedType(self.name, self.drafts[i].name)) end
    end
    local Tr = self.session.T.MoonTree
    local pvm = require("moonlift.pvm")
    local items = {}
    local seen_types = {}
    if self.session.global_type_values then
        for _, tv in pairs(self.session.global_type_values) do
            if type(tv) == "table" and tv.item ~= nil and tv.decl ~= nil and tv.decl.name ~= nil and not seen_types[tv.decl.name] then
                items[#items + 1] = tv.item
                seen_types[tv.decl.name] = true
            end
        end
    end
    for i = 1, #self.items do
        local item = self.items[i]
        if pvm.classof(item) == Tr.ItemType and item.t and item.t.name then seen_types[item.t.name] = true end
        items[#items + 1] = item
    end
    return Tr.Module(Tr.ModuleTyped(self.name), items)
end

function BundleValue:layout_env()
    local Sem = self.session.T.MoonSem
    local pvm = require("moonlift.pvm")
    local layouts = {}
    local resolved = {}
    
    local type_values = {}
    if self.session.global_type_values then
        for _, tv in pairs(self.session.global_type_values) do type_values[#type_values + 1] = tv end
    end
    for i = 1, #self.type_values do type_values[#type_values + 1] = self.type_values[i] end

    -- Multi-pass: retry types whose dependencies aren't resolved yet.
    for pass = 1, 10 do
        local progress = false
        for i = 1, #type_values do
            if not resolved[i] then
                local tv = type_values[i]
                local env_layouts = {}
                for j = 1, #layouts do env_layouts[j] = layouts[j] end
                local layout = self.session:layout_of(tv, Sem.LayoutEnv(env_layouts))
                if layout ~= nil then
                    layouts[#layouts + 1] = layout
                    resolved[i] = true
                    progress = true
                end
            end
        end
        if not progress then break end
    end
    
    local out_layouts = {}
    for i = 1, #layouts do out_layouts[i] = layouts[i] end
    return Sem.LayoutEnv(out_layouts)
end

local function back_scalar_name(scalar)
    return tostring(scalar):match("%.([%w_]+):") or tostring(scalar):match("(Back[%w_]+)") or tostring(scalar)
end

local function ctype_of_type(api, ty_value)
    local pvm = require("moonlift.pvm")
    local T = api.T
    local Ty = T.MoonType
    local Back = require("moonlift.type_to_back_scalar").Define(T)
    local tv = api.as_type_value(ty_value, "ctype expects type value")
    local cls = pvm.classof(tv.ty)
    if cls == Ty.TPtr then return "void *" end
    local r = Back.result(tv.ty)
    if pvm.classof(r) ~= Ty.TypeBackScalarKnown then return "void *" end
    local name = back_scalar_name(r.scalar)
    return assert(scalar_ctype[name], "unsupported exported C type: " .. tostring(r.scalar))
end

local function c_signature_parts(api, func_value)
    local pvm = require("moonlift.pvm")
    local Ty = api.T.MoonType
    local args = {}
    local result_ty = api.as_type_value(func_value.result, "function result type").ty
    local result_is_view = pvm.classof(result_ty) == Ty.TView
    if result_is_view then args[#args + 1] = "void *" end
    for i = 1, #func_value.params do args[#args + 1] = ctype_of_type(api, func_value.params[i].type) end
    local ret = result_is_view and "void" or ctype_of_type(api, func_value.result)
    return ret, args
end

local function c_sig_of(api, func_value)
    local ret, args = c_signature_parts(api, func_value)
    return ret .. " (*)(" .. table.concat(args, ", ") .. ")"
end

local function c_decl_of(api, func_value, c_name)
    local ret, args = c_signature_parts(api, func_value)
    if #args == 0 then args[1] = "void" end
    return "extern " .. ret .. " " .. c_name .. "(" .. table.concat(args, ", ") .. ");"
end

local function shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function exec_ok(cmd)
    local r = os.execute(cmd)
    return r == true or r == 0
end

local function command_exists(cmd)
    local word = tostring(cmd):match("^%s*(%S+)") or tostring(cmd)
    return exec_ok("command -v " .. shell_quote(word) .. " >/dev/null 2>&1")
end

local function choose_c_compiler(opts)
    opts = opts or {}
    local explicit = opts.cc or opts.compiler or os.getenv("MOONLIFT_C_CC")
    if explicit and explicit ~= "" then
        assert(command_exists(explicit), "requested C compiler not found: " .. tostring(explicit))
        return explicit
    end
    local candidates = { "tcc", "cc", "gcc", "clang" }
    for i = 1, #candidates do if command_exists(candidates[i]) then return candidates[i] end end
    error("no C compiler found (tried MOONLIFT_C_CC, tcc, cc, gcc, clang)", 3)
end

local function is_tcc_compiler(cc)
    local word = tostring(cc):match("^%s*(%S+)") or tostring(cc)
    word = word:gsub("\\", "/")
    return word:match("(^|/)tcc$") ~= nil or word:match("(^|/)tinycc$") ~= nil
end

local function compile_shared_c_source(source, opts)
    opts = opts or {}
    local cc = choose_c_compiler(opts)
    local base = opts.base or os.tmpname()
    local c_path = opts.c_path or (base .. ".c")
    local so_path = opts.so_path or (base .. ".so")
    local f = assert(io.open(c_path, "wb")); f:write(source); f:close()
    local cflags = opts.cflags or (is_tcc_compiler(cc) and "-std=c99 -shared" or "-std=c99 -fPIC -shared")
    local ldflags = opts.ldflags or "-lm"
    local cmd = table.concat({ cc, cflags, shell_quote(c_path), ldflags, "-o", shell_quote(so_path) }, " ")
    assert(exec_ok(cmd), "C backend compiler failed: " .. cmd)
    return { compiler = cc, c_path = c_path, so_path = so_path, cleanup = opts.cleanup ~= false }
end

function BundleValue:_lower_program(opts)
    opts = opts or {}
    local Pipeline = require("moonlift.frontend_pipeline").Define(self.session.T)
    local lower_opts = {
        site = "host module",
        layout_env = self:layout_env(),
    }
    -- Inject only explicit bundle region dependencies.  A compile unit must be
    -- determined by the values packed into the bundle and their recorded @{}
    -- dependency closure, never by ambient session history.
    local T = self.session.T
    local region_frags = {}
    local seen = {}
    for i = 1, #(self.region_frags or {}) do
        local frag = self.region_frags[i]
        if not seen[frag] then region_frags[#region_frags + 1] = frag end
    end
    if #region_frags > 0 then
        local O = T.MoonOpen
        lower_opts.expand_env = O.ExpandEnv(region_frags, {}, O.FillSet({}), {}, {}, "")
    end
    return Pipeline.lower_module(self:to_asdl(), lower_opts).program
end

function BundleValue:_lower_c_unit(opts)
    opts = opts or {}
    local Pipeline = require("moonlift.frontend_pipeline").Define(self.session.T)
    local lower_opts = {
        site = "host module c",
        layout_env = self:layout_env(),
        c_opts = opts,
    }
    local T = self.session.T
    local region_frags = {}
    local seen = {}
    for i = 1, #(self.region_frags or {}) do
        local frag = self.region_frags[i]
        if not seen[frag] then region_frags[#region_frags + 1] = frag end
    end
    if #region_frags > 0 then
        local O = T.MoonOpen
        lower_opts.expand_env = O.ExpandEnv(region_frags, {}, O.FillSet({}), {}, {}, "")
    end
    local result = Pipeline.lower_module_to_c(self:to_asdl(), lower_opts)
    if result.code_module == nil then error("bundle:emit_c lowering failed: MoonCode module was not produced", 2) end
    if result.code_report ~= nil and #result.code_report.issues ~= 0 then
        local msgs = {}
        for i = 1, #result.code_report.issues do msgs[#msgs + 1] = tostring(result.code_report.issues[i]) end
        error("bundle:emit_c code validation failed: " .. table.concat(msgs, "\n"), 2)
    end
    if #result.c_report.issues ~= 0 then
        local msgs = {}
        for i = 1, #result.c_report.issues do msgs[#msgs + 1] = tostring(result.c_report.issues[i]) end
        error("bundle:emit_c validation failed: " .. table.concat(msgs, "\n"), 2)
    end
    return result.c_unit
end

function BundleValue:compile(opts)
    opts = opts or {}
    local backend = opts.backend or opts.codegen or "cranelift"
    if backend == "c" or backend == "tcc" or backend == "libtcc" then
        return self:compile_c(opts)
    end
    local program = self:_lower_program(opts)
    local Jit = require("moonlift.back_jit")
    local T = self.session.T
    local jit_api = Jit.Define(T)
    local jit = jit_api.jit()
    for name, ptr in pairs(self.extern_symbols or {}) do jit:symbol(name, ptr) end
    for name, ptr in pairs(opts.symbols or {}) do jit:symbol(name, ptr) end
    local artifact = jit:compile(program)
    return setmetatable({ module = self, artifact = artifact, T = T, functions = {} }, CompiledModule)
end

function BundleValue:compile_c(opts)
    opts = opts or {}
    local source = self:emit_c(opts)
    local runner = opts.runner or opts.c_runner or opts.backend
    local symbols = {}
    for name, ptr in pairs(self.extern_symbols or {}) do symbols[name] = ptr end
    for name, ptr in pairs(opts.symbols or {}) do symbols[name] = ptr end

    local prefer_libtcc = runner == nil or runner == "c" or runner == "libtcc" or runner == "tcc" or runner == "auto"
    if prefer_libtcc then
        local CTcc = require("moonlift.c_tcc")
        local available = CTcc.available(opts.libtcc_opts)
        if available then
            local libtcc_opts = opts.libtcc_opts or {}
            libtcc_opts.libraries = libtcc_opts.libraries or { "m" }
            libtcc_opts.host_symbols = libtcc_opts.host_symbols or symbols
            local session, err = CTcc.compile(source, libtcc_opts)
            if session then
                return setmetatable({ module = self, backend = "c", runner = "libtcc", source = source, session = session, T = self.session.T, functions = {} }, CCompiledModule)
            end
            if runner == "libtcc" or runner == "tcc" then error(err and err.message or "libtcc compile failed", 2) end
        elseif runner == "libtcc" or runner == "tcc" then
            local _, err = CTcc.available(opts.libtcc_opts)
            error(err and err.message or "libtcc unavailable for callable C backend", 2)
        end
    end

    local artifact = compile_shared_c_source(source, opts)
    local lib = ffi.load(artifact.so_path)
    return setmetatable({ module = self, backend = "c", runner = "shared", source = source, shared = artifact, lib = lib, T = self.session.T, functions = {} }, CCompiledModule)
end

function BundleValue:emit_object(opts)
    opts = opts or {}
    local program = self:_lower_program(opts)
    local T = self.session.T
    local Object = require("moonlift.back_object")
    local O = Object.Define(T)
    local name = opts.module_name or self.name
    local artifact = O.compile(program, { module_name = name })
    return artifact
end

function BundleValue:emit_c(opts)
    opts = opts or {}
    local unit = self:_lower_c_unit(opts)
    local CEmit = require("moonlift.c_emit").Define(self.session.T)
    return CEmit.emit(unit, opts)
end

function BundleValue:jit(opts)
    return self:compile(opts)
end

function BundleValue:object(path_or_opts)
    local opts = path_or_opts
    if type(path_or_opts) == "string" then opts = { object_path = path_or_opts } end
    local artifact = self:emit_object(opts)
    if opts.object_path then
        artifact:write(opts.object_path)
    end
    return artifact
end

function BundleValue:c_source(path_or_opts)
    local opts = path_or_opts or {}
    if type(path_or_opts) == "string" then opts = { c_path = path_or_opts } end
    local source = self:emit_c(opts)
    local path = opts.c_path or opts.source_path
    if path then
        local f = assert(io.open(path, "wb"))
        f:write(source)
        f:close()
    end
    return source
end

function BundleValue:library(path_or_opts)
    local opts = path_or_opts
    if type(path_or_opts) == "string" then opts = { shared_path = path_or_opts } end
    local object_artifact = self:emit_object(opts)
    local object_path = opts.object_path or (os.tmpname() .. ".o")
    object_artifact:write(object_path)

    local LinkTarget = require("moonlift.link_target_model")
    local LinkValidate = require("moonlift.link_plan_validate")
    local LinkCommand = require("moonlift.link_command_plan")
    local LinkExecute = require("moonlift.link_execute")
    local T = self.session.T
    local Link = T.MoonLink
    local LT = LinkTarget.Define(T)
    local LV = LinkValidate.Define(T)
    local LC = LinkCommand.Define(T)
    local LE = LinkExecute.Define(T)

    local link_plan = Link.LinkPlan(
        LT.default_object(),
        Link.LinkArtifactSharedLibrary,
        Link.LinkTool(Link.LinkerSystemCc, Link.LinkPath("cc")),
        Link.LinkPath(opts.shared_path or "lib" .. self.name .. ".so"),
        { Link.LinkInputObject(Link.LinkPath(object_path)) },
        Link.LinkExportAll,
        Link.LinkExternRequireResolved,
        {}
    )
    local link_report = LV.validate(link_plan)
    if #link_report.issues ~= 0 then
        local msgs = {}
        for j = 1, #link_report.issues do
            msgs[#msgs + 1] = tostring(link_report.issues[j].message or link_report.issues[j])
        end
        error("bundle:library link validation failed: " .. table.concat(msgs, "\n"), 2)
    end
    local commands = LC.plan(link_plan)
    local result = LE.execute(commands)
    local LinkFailed = T.MoonLink.LinkFailed
    if pvm.classof(result) == LinkFailed then
        error("bundle:library link failed", 2)
    end
    return opts.shared_path
end

function BundleValue:__tostring()
    return "MoonBundle(" .. self.name .. ")"
end

function CompiledModule:get(name)
    local cached = self.functions[name]
    if cached then return cached end
    local func = assert(self.module.exports[name], "compiled module has no exported function: " .. tostring(name))
    local B2 = self.T.MoonBack
    local c_sig = c_sig_of(self.module.api, func)
    local ptr = self.artifact:getpointer(B2.BackFuncId(name))
    local fn = ffi.cast(c_sig, ptr)
    local wrapped = setmetatable({ module = self, func = func, fn = fn, c_sig = c_sig }, CompiledFunction)
    self.functions[name] = wrapped
    return wrapped
end

function CompiledModule:free()
    if self.artifact then self.artifact:free(); self.artifact = nil end
end

function CCompiledModule:get(name)
    local cached = self.functions[name]
    if cached then return cached end
    local func = assert(self.module.exports[name], "compiled C module has no exported function: " .. tostring(name))
    local c_sig = c_sig_of(self.module.api, func)
    local c_name = tostring(name):gsub("[^%w_]", "_")
    local fn
    if self.runner == "libtcc" then
        local ptr, err = self.session:symbol(c_name, c_sig)
        if not ptr then error(err and err.message or ("C symbol not found: " .. c_name), 2) end
        fn = ptr
    else
        pcall(ffi.cdef, c_decl_of(self.module.api, func, c_name))
        fn = ffi.cast(c_sig, self.lib[c_name])
    end
    local wrapped = setmetatable({ module = self, func = func, fn = fn, c_sig = c_sig }, CCompiledFunction)
    self.functions[name] = wrapped
    return wrapped
end

function CCompiledModule:free()
    if self.session then self.session:free(); self.session = nil end
    if self.shared and self.shared.cleanup then
        os.remove(self.shared.c_path)
        os.remove(self.shared.so_path)
        self.shared.cleanup = false
    end
end

function CCompiledFunction:__call(...)
    if not self.module then error("compiled C Moonlift function called after module was freed", 2) end
    return self.fn(...)
end

function CCompiledFunction:free()
    if self.module then self.module:free(); self.module = nil end
end

function CCompiledFunction:__tostring()
    return "CompiledCMoonFunction(" .. self.func.name .. ": " .. self.c_sig .. ")"
end

function CompiledFunction:__call(...)
    if not self.module or not self.module.artifact then error("compiled Moonlift function called after artifact was freed", 2) end
    -- In a : method call, self is NOT in ... — ... is just the actual args
    return self.fn(...)
end

function CompiledFunction:__tostring()
    return "CompiledMoonFunction(" .. self.func.name .. ": " .. self.c_sig .. ")"
end

function CompiledFunction:free()
    if self.module then
        self.module:free()
        self.module = nil
    end
end

function M.Install(api, session)
    local function new_bundle(name)
        assert_name(name, "bundle")
        return setmetatable({
            kind = "bundle",
            session = session,
            api = api,
            name = name,
            items = {},
            exports = {},
            drafts = {},
            type_values = {},
            type_names = {},
            func_names = {},
            extern_symbols = {},
            region_frags = {},
        }, BundleValue)
    end

    function api.bundle(name)
        return new_bundle(name)
    end

    -- Internal alias for backward compat
    function api.module(name)
        return new_bundle(name)
    end

    function session:module(name)
        return new_bundle(name)
    end

    api.BundleValue = BundleValue
    api.ModuleValue = BundleValue  -- alias for compat
end

return M
