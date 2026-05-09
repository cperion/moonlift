-- ASDL-hosted .mlua runner.
--
-- The document is first segmented into MoonMlua/MoonHost ASDL values.
-- Generated Lua is only the
-- host language execution carrier; hosted islands are explicit HostTemplate
-- values evaluated through Runtime:eval_island.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Quote = require("moonlift.quote")
local Session = require("moonlift.host_session")
local HostValues = require("moonlift.host_values")

local M = {}
local Runtime = {}; Runtime.__index = Runtime
local ModuleValue = {}
local module_value_mt
local CompiledModule = {}; CompiledModule.__index = CompiledModule
local CompiledFunction = {}; CompiledFunction.__index = CompiledFunction
local FuncValue = {}; FuncValue.__index = FuncValue

local runtime_stack = {}

local function push_runtime(runtime)
    runtime_stack[#runtime_stack + 1] = runtime
    return function()
        assert(runtime_stack[#runtime_stack] == runtime, "moonlift runtime stack imbalance")
        runtime_stack[#runtime_stack] = nil
    end
end

function M.current_runtime()
    return runtime_stack[#runtime_stack]
end

function M._push_runtime(runtime)
    return push_runtime(runtime)
end

local function new_context()
    local T = pvm.context(); A.Define(T); return T
end

local scalar_ctype = {
    BackBool = "bool",
    BackI8 = "int8_t", BackI16 = "int16_t", BackI32 = "int32_t", BackI64 = "int64_t",
    BackU8 = "uint8_t", BackU16 = "uint16_t", BackU32 = "uint32_t", BackU64 = "uint64_t",
    BackF32 = "float", BackF64 = "double",
    BackPtr = "void *",
    BackIndex = "intptr_t",
    BackVoid = "void",
}

local function class_name(v)
    local cls = pvm.classof(v)
    return cls and tostring(cls) or type(v)
end

local function back_scalar_name(scalar)
    return tostring(scalar):match("%.([%w_]+):") or tostring(scalar):match("(Back[%w_]+)") or tostring(scalar)
end

local function ctype_of_type(T, ty)
    local Ty = T.MoonType
    if pvm.classof(ty) == Ty.TPtr then return "void *" end
    local Back = require("moonlift.type_to_back_scalar").Define(T)
    local r = Back.result(ty)
    if pvm.classof(r) ~= Ty.TypeBackScalarKnown then return "void *" end
    return assert(scalar_ctype[back_scalar_name(r.scalar)], "unsupported exported C type: " .. tostring(r.scalar))
end

local function c_sig_of(T, func)
    local Ty = T.MoonType
    local args = {}
    local result_is_view = pvm.classof(func.result) == Ty.TView
    if result_is_view then args[#args + 1] = "void *" end
    for i = 1, #func.params do args[#args + 1] = ctype_of_type(T, func.params[i].ty) end
    local ret = result_is_view and "void" or ctype_of_type(T, func.result)
    return ret .. " (*)(" .. table.concat(args, ", ") .. ")"
end

local function module_funcs(T, module)
    local Tr = T.MoonTree
    local out = {}
    for i = 1, #module.items do
        local item = module.items[i]
        if pvm.classof(item) == Tr.ItemFunc then
            local cls = pvm.classof(item.func)
            if cls == Tr.FuncExport or cls == Tr.FuncLocal then out[item.func.name] = item.func end
        end
    end
    return out
end

local function module_name_of(T, module)
    local Tr = T.MoonTree
    local h = module and module.h
    local cls = h and pvm.classof(h)
    if cls == Tr.ModuleTyped or cls == Tr.ModuleSem or cls == Tr.ModuleCode then return h.module_name end
    if cls == Tr.ModuleOpen and h.name ~= T.MoonOpen.ModuleNameOpen then return h.name.module_name end
    return ""
end

local function func_type(T, params, result)
    local tys = {}
    for i = 1, #(params or {}) do tys[i] = params[i].ty end
    return T.MoonType.TFunc(tys, result)
end

local function exported_module_fields(runtime, module, extra)
    local T = runtime.T
    local C, B, Tr = T.MoonCore, T.MoonBind, T.MoonTree
    local api = runtime.session:api()
    local mod_name = module_name_of(T, module)
    local fields = {}
    for i = 1, #module.items do
        local item = module.items[i]
        local cls = pvm.classof(item)
        if cls == Tr.ItemType then
            local t = item.t
            local name = t.name or (t.sym and t.sym.name)
            if name then
                local extra = {}
                if pvm.classof(t) == Tr.TypeDeclTaggedUnionSugar then extra.protocol_variants = t.variants end
                fields[name] = api.type_from_asdl(T.MoonType.TNamed(T.MoonType.TypeRefGlobal(mod_name, name)), (mod_name ~= "" and (mod_name .. ".") or "") .. name, extra)
            end
        elseif cls == Tr.ItemConst then
            local c = item.c
            local name = c.name or (c.sym and c.sym.name)
            if name then
                fields[name] = api.expr_from_asdl(c.value, api.type_from_asdl(c.ty, name), (mod_name ~= "" and (mod_name .. ".") or "") .. name)
            end
        elseif cls == Tr.ItemFunc then
            local f = item.func
            local fcls = pvm.classof(f)
            if fcls == Tr.FuncExport or fcls == Tr.FuncExportContract then
                local ty = api.type_from_asdl(func_type(T, f.params, f.result), f.name)
                local binding = B.Binding(C.Id("func:" .. mod_name .. ":" .. f.name), f.name, ty.ty, B.BindingClassGlobalFunc(mod_name, f.name))
                fields[f.name] = api.expr_ref(binding, ty, (mod_name ~= "" and (mod_name .. ".") or "") .. f.name)
            end
        elseif cls == Tr.ItemExtern then
            local f = item.func
            local ty = api.type_from_asdl(func_type(T, f.params, f.result), f.name)
            local binding = B.Binding(C.Id("extern:" .. f.name), f.name, ty.ty, B.BindingClassExtern(f.symbol))
            fields[f.name] = api.expr_ref(binding, ty, f.name)
        end
    end
    for k, v in pairs(extra or {}) do fields[k] = v end
    return fields
end

local function current_dep_table(runtime)
    local stack = runtime.require_stack
    if stack and #stack > 0 then return stack[#stack].deps end
    runtime.root_deps = runtime.root_deps or {}
    return runtime.root_deps
end

local function new_module_value(runtime, module, extra_fields)
    return setmetatable({
        kind = "module",
        moonlift_quote_kind = "module",
        name = module_name_of(runtime.T, module),
        module = module,
        exports = exported_module_fields(runtime, module, extra_fields),
        deps = current_dep_table(runtime),
        T = runtime.T,
        runtime = runtime,
    }, module_value_mt)
end

-- splice_to_source is kept only for debug/display use.
local function splice_to_source(value)
    local tv = type(value)
    if tv == "number" or tv == "boolean" then return tostring(value) end
    if tv == "nil" then return "nil" end
    if tv == "string" then return value end
    if (tv == "table" or tv == "userdata") and type(value.moonlift_splice_source) == "function" then
        return value:moonlift_splice_source()
    end
    return tostring(value)
end

local function island_kind_word(T, island)
    local Mlua = T.MoonMlua
    if island.kind == Mlua.IslandStruct then return "struct" end
    if island.kind == Mlua.IslandExpose then return "expose" end
    if island.kind == Mlua.IslandFunc then return "func" end
    if island.kind == Mlua.IslandModule then return "module" end
    if island.kind == Mlua.IslandRegion then return "region" end
    if island.kind == Mlua.IslandExpr then return "expr" end
    return "unknown"
end

local function named_island(T, island)
    local Mlua = T.MoonMlua
    if pvm.classof(island.name) == Mlua.IslandNamed then return island.name.name end
    return nil
end

local function adopt_frag_map(out, frags)
    if frags == nil then return end
    for key, frag in pairs(frags) do
        local name = frag.name or (frag.frag and frag.frag.name) or key
        out[name] = out[name] or frag
    end
end

local function adopt_splice_value(runtime, value)
    if type(value) ~= "table" then return end
    local kind = rawget(value, "moonlift_quote_kind") or rawget(value, "kind")
    if kind == "region_frag" and value.frag ~= nil then
        runtime.region_frags[value.name or value.frag.name] = value
        local deps = value.deps
        if deps then
            adopt_frag_map(runtime.region_frags, deps.region_frags)
            adopt_frag_map(runtime.expr_frags, deps.expr_frags)
        end
    elseif kind == "expr_frag" and value.frag ~= nil then
        runtime.expr_frags[value.name or value.frag.name] = value
    end
end

-- Adopt a Lua host value: register region/expr fragment values so they are
-- available for future emit resolution inside expand.
local function adopt_splice_value(runtime, value)
    if type(value) ~= "table" then return end
    local kind = rawget(value, "moonlift_quote_kind") or rawget(value, "kind")
    if kind == "region_frag" and value.frag ~= nil then
        runtime.region_frags[value.name or value.frag.name] = value
        local deps = value.deps
        if deps then
            for _, v in pairs(deps.region_frags or {}) do
                local n = v.name or (v.frag and v.frag.name)
                if n then runtime.region_frags[n] = runtime.region_frags[n] or v end
            end
            for _, v in pairs(deps.expr_frags or {}) do
                local n = v.name or (v.frag and v.frag.name)
                if n then runtime.expr_frags[n] = runtime.expr_frags[n] or v end
            end
        end
    elseif kind == "expr_frag" and value.frag ~= nil then
        runtime.expr_frags[value.name or value.frag.name] = value
    end
end

-- New slot-based eval_island: parse template with holes, fill slots, expand.
function Runtime:eval_island(step_index, closures)
    local step = assert(self.program.steps[step_index], "unknown island step " .. tostring(step_index))
    local H = self.T.MoonHost
    local Parse  = require("moonlift.parse").Define(self.T)
    local Splice = require("moonlift.host_splice")
    local Expand = require("moonlift.open_expand").Define(self.T)

    -- 1. Evaluate splice Lua closures and auto-qualified module-table probes.
    local luamap = {}
    local qualified_values = {}
    for id, fn in pairs(closures or {}) do
        local ok, val = pcall(fn)
        if not ok then
            error("Moonlift splice eval failed at " .. id .. ": " .. tostring(val), 2)
        end
        if id:match("^qualified%.") then
            if val ~= nil then
                luamap[id] = { present = true, value = val }
                local path = id:gsub("^qualified%.", "", 1)
                qualified_values[path] = true
                if type(val) == "table" and val.protocol_variants then self.protocol_types[path] = val.protocol_variants end
                adopt_splice_value(self, val)
            end
        else
            luamap[id] = { present = true, value = val }
            adopt_splice_value(self, val)
        end
    end

    -- 2. Parse template with holes → ASDL + splice_slots list.
    local kind = step.template.kind_word
    local parse_opts = { region_frags = self.region_frags, expr_frags = self.expr_frags, protocol_types = self.protocol_types, qualified_values = qualified_values }
    local parsed
    if kind == "region" then
        parsed = Parse.parse_region_frag_template(step.template, parse_opts)
    elseif kind == "expr" then
        parsed = Parse.parse_expr_frag_template(step.template, parse_opts)
    elseif kind == "module" then
        parsed = Parse.parse_module_template(step.template, parse_opts)
    elseif kind == "func" then
        parsed = Parse.parse_func_template(step.template, parse_opts)
    else
        error("unsupported hosted island kind: " .. tostring(kind), 2)
    end
    if #parsed.issues ~= 0 then
        error("Moonlift template parse failed: " .. tostring(parsed.issues[1]), 2)
    end

    -- 3. Coerce each splice value into a SlotBinding.
    local bindings = {}
    for _, ss in ipairs(parsed.splice_slots) do
        local rec = luamap[ss.splice_id]
        if not rec or not rec.present then
            error("missing splice value for " .. ss.splice_id, 2)
        end
        bindings[#bindings + 1] = Splice.fill(
            self.session, ss.slot, rec.value, "splice " .. ss.splice_id)
    end

    -- 4. Build expand env: all previously registered frags + new splice fills.
    local base_env = Expand.env_with_frags(self.region_frags, self.expr_frags)
    local env      = Expand.env_with_fills(base_env, bindings)

    -- 5. Expand and wrap as host value.
    if kind == "region" then
        local raw_frag    = parsed.value.frag
        local expanded    = Expand.expand_region_frag(raw_frag, env)
        local value       = HostValues.region_frag_value(self.session, expanded, {})
        self.region_frags[value.name] = value
        return value
    elseif kind == "expr" then
        local raw_frag    = parsed.value.frag
        local expanded    = Expand.expand_expr_frag(raw_frag, env)
        local value       = HostValues.expr_frag_value(self.session, expanded)
        self.expr_frags[value.name] = value
        return value
    elseif kind == "module" then
        -- Persist protocol types registered by this island so later
        -- islands (parsed in separate steps) can resolve them.
        if parsed.protocol_types then
            for name, variants in pairs(parsed.protocol_types) do
                self.protocol_types[name] = variants
            end
        end
        -- Pre-expand region/expr frags defined inline in the module body, then
        -- store them so emit calls in the module body can resolve them.
        if parsed.region_frags then
            for name, frag_result in pairs(parsed.region_frags) do
                if type(frag_result) == "table" and frag_result.frag then
                    local expanded = Expand.expand_region_frag(frag_result.frag, env)
                    local hv = HostValues.region_frag_value(self.session, expanded, {})
                    self.region_frags[hv.name] = hv
                end
            end
        end
        if parsed.expr_frags then
            for name, frag_result in pairs(parsed.expr_frags) do
                if type(frag_result) == "table" and frag_result.frag then
                    local expanded = Expand.expand_expr_frag(frag_result.frag, env)
                    local hv = HostValues.expr_frag_value(self.session, expanded)
                    self.expr_frags[hv.name] = hv
                end
            end
        end
        -- Rebuild env so the module expansion sees the newly expanded frags.
        env = Expand.env_with_fills(
            Expand.env_with_frags(self.region_frags, self.expr_frags),
            bindings)
        local expanded = Expand.expand_module(parsed.module, env)
        local frag_fields = {}
        for name, fr in pairs(parsed.region_frags or {}) do
            if self.region_frags[name] then frag_fields[name] = self.region_frags[name] end
        end
        for name, fr in pairs(parsed.expr_frags or {}) do
            if self.expr_frags[name] then frag_fields[name] = self.expr_frags[name] end
        end
        return new_module_value(self, expanded, frag_fields)
    elseif kind == "func" then
        -- Adopt frags parsed inline in the func island body.
        if parsed.region_frags then
            for name, fr in pairs(parsed.region_frags) do
                if type(fr) == "table" and fr.frag then
                    self.region_frags[name] = self.region_frags[name] or HostValues.region_frag_value(self.session, fr.frag, {})
                end
            end
        end
        if parsed.expr_frags then
            for name, fr in pairs(parsed.expr_frags) do
                if type(fr) == "table" and fr.frag then
                    self.expr_frags[name] = self.expr_frags[name] or HostValues.expr_frag_value(self.session, fr.frag)
                end
            end
        end
        env = Expand.env_with_fills(
            Expand.env_with_frags(self.region_frags, self.expr_frags),
            bindings)
        local expanded_mod = Expand.expand_module(parsed.module, env)
        local Tr = self.T.MoonTree
        for i = 1, #expanded_mod.items do
            local item = expanded_mod.items[i]
            if pvm.classof(item) == Tr.ItemFunc then
                local mv = new_module_value(self, expanded_mod)
                return setmetatable({ kind = "func", name = item.func.name, func = item.func, module = mv, T = self.T, runtime = self }, FuncValue)
            end
        end
        error("func island did not produce a function", 2)
    end
end

local function module_value_index(self, key)
    local method = ModuleValue[key]
    if method ~= nil then return method end
    local exports = rawget(self, "exports")
    if exports and exports[key] ~= nil then return exports[key] end
    return nil
end

local function module_value_newindex(self, key)
    error("Moonlift module tables are sealed; cannot assign field " .. tostring(key), 2)
end

module_value_mt = { __index = module_value_index, __newindex = module_value_newindex }

function ModuleValue:moonlift_splice(role)
    if role == "module_items" then return self.module.items end
    if role == "module" then return self.module end
    return nil
end

function ModuleValue:__tostring()
    return "MoonModuleValue(" .. tostring(self.name or "<anonymous>") .. ")"
end

local function module_with_required_deps(self)
    local deps = self.deps or {}
    if #deps == 0 then return self.module end
    local Tr = self.T.MoonTree
    local items, seen = {}, {}
    for _, dep in ipairs(deps) do
        if type(dep) == "table" and dep ~= self and dep.module and not seen[dep.module] then
            seen[dep.module] = true
            items[#items + 1] = Tr.ItemUseModule("require:" .. tostring(dep.name or #items + 1), dep.module, {})
        end
    end
    for i = 1, #self.module.items do items[#items + 1] = self.module.items[i] end
    return Tr.Module(self.module.h, items)
end

function ModuleValue:compile()
    local OpenExpand = require("moonlift.open_expand").Define(self.T)
    local Typecheck = require("moonlift.tree_typecheck").Define(self.T)
    local Layout = require("moonlift.sem_layout_resolve").Define(self.T)
    local TreeToBack = require("moonlift.tree_to_back").Define(self.T)
    local Validate = require("moonlift.back_validate").Define(self.T)
    local J = require("moonlift.back_jit").Define(self.T)
    -- Module has already been open-expanded by eval_island; typecheck/lower directly.
    local expanded = module_with_required_deps(self)
    local checked = Typecheck.check_module(expanded)
    if #checked.issues ~= 0 then error("module typecheck failed: " .. tostring(checked.issues[1]), 2) end
    local resolved = Layout.module(checked.module)
    local program = TreeToBack.module(resolved)
    local report = Validate.validate(program)
    if #report.issues ~= 0 then error("module back validation failed: " .. tostring(report.issues[1]), 2) end
    local artifact = J.jit():compile(program)
    return setmetatable({ module = self, artifact = artifact, T = self.T, exports = module_funcs(self.T, checked.module), functions = {} }, CompiledModule)
end

function CompiledModule:get(name)
    local cached = self.functions[name]
    if cached then return cached end
    local func = assert(self.exports[name], "compiled module has no exported function: " .. tostring(name))
    local c_sig = c_sig_of(self.T, func)
    local ptr = self.artifact:getpointer(self.T.MoonBack.BackFuncId(name))
    local wrapped = setmetatable({ module = self, func = func, fn = ffi.cast(c_sig, ptr), c_sig = c_sig }, CompiledFunction)
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

function CompiledFunction:free()
    if self.module then self.module:free(); self.module = nil end
end

function CompiledFunction:__tostring()
    return "CompiledMoonFunction(" .. tostring(self.func.name) .. ": " .. tostring(self.c_sig) .. ")"
end

function FuncValue:compile()
    return self.module:compile():get(self.name)
end

local function module_path_candidates(runtime, name)
    local rel = tostring(name):gsub("%.", "/")
    local patterns = runtime.module_path_patterns or { "mlua/?.mlua", "mlua/?/init.mlua", "?.mlua", "?/init.mlua" }
    local out = {}
    for i = 1, #patterns do out[#out + 1] = (patterns[i]:gsub("%?", rel)) end
    return out
end

function Runtime:note_require_dep(value)
    if not (type(value) == "table" and value.module) then return end
    local deps = current_dep_table(self)
    for i = 1, #deps do if deps[i] == value then return end end
    deps[#deps + 1] = value
end

function Runtime:require(name)
    self.require_cache = self.require_cache or {}
    if self.require_cache[name] == false then error("circular moon.require for " .. tostring(name), 2) end
    if self.require_cache[name] ~= nil then
        local cached = self.require_cache[name]
        self:note_require_dep(cached)
        return cached
    end
    local tried = {}
    for _, path in ipairs(module_path_candidates(self, name)) do
        tried[#tried + 1] = path
        local f = io.open(path, "rb")
        if f then
            f:close()
            self.require_cache[name] = false -- cycle guard
            local frame = { name = name, deps = {} }
            self.require_stack[#self.require_stack + 1] = frame
            local ok, loaded_or_err = pcall(function()
                local fn = assert(M.loadfile(path, { runtime = self }))
                return fn()
            end)
            self.require_stack[#self.require_stack] = nil
            if not ok then
                self.require_cache[name] = nil
                error(loaded_or_err, 2)
            end
            local value = loaded_or_err
            if type(value) == "table" and value.module then value.deps = frame.deps end
            self.require_cache[name] = value
            self:note_require_dep(value)
            return value
        end
    end
    error("moon.require could not find " .. tostring(name) .. " (tried " .. table.concat(tried, ", ") .. ")", 2)
end

local function expression_for_island(T, step_index, island, template)
    local H = T.MoonHost
    local entries = {}
    local seen = {}
    local function add(id, src)
        if seen[id] then return end
        seen[id] = true
        entries[#entries + 1] = string.format("[%q] = function() %s end", id, src)
    end
    for i = 1, #template.parts do
        local part = template.parts[i]
        if pvm.classof(part) == H.TemplateSplicePart then
            add(part.splice.id, "return (" .. part.splice.lua_source.text .. ")")
        elseif pvm.classof(part) == H.TemplateText then
            local text = part.text.source.text
            for base, field in text:gmatch("([_%a][_%w]*)%.([_%a][_%w]*)") do
                local path = base .. "." .. field
                add("qualified." .. path,
                    "local __v = " .. base .. "; if type(__v) == 'table' or type(__v) == 'userdata' then return __v[" .. string.format("%q", field) .. "] end; return nil")
            end
        end
    end
    return string.format("__moonlift_runtime:eval_island(%d, {%s})", step_index, table.concat(entries, ","))
end

local function translation_for_island(T, step_index, island, template)
    return "(" .. expression_for_island(T, step_index, island, template) .. ")"
end

local function translate_runtime(runtime)
    local T = runtime.T
    local H = T.MoonHost
    local out = {}
    for i = 1, #runtime.program.steps do
        local step = runtime.program.steps[i]
        local cls = pvm.classof(step)
        if cls == H.HostStepLua then
            out[#out + 1] = step.source.text
        elseif cls == H.HostStepIsland then
            out[#out + 1] = translation_for_island(T, i, step.island, step.template)
        end
    end
    return table.concat(out, "\n")
end

function M.loadstring(src, chunk_name, opts)
    opts = opts or {}
    local parent = opts.runtime
    local T = opts.T or (parent and parent.T) or new_context()
    local session = opts.session or (parent and parent.session) or Session.new({ prefix = opts.prefix or "mlua", T = T })
    local S = T.MoonSource
    local doc = S.DocumentSnapshot(S.DocUri(chunk_name or "<mlua>"), S.DocVersion(0), S.LangMlua, src)
    local parts = require("moonlift.mlua_document").Define(T).document_parts(doc)
    local program = pvm.one(require("moonlift.mlua_host_model").Define(T).host_program(parts))
    local runtime = setmetatable({
        T = T,
        session = session,
        program = program,
        region_frags = opts.region_frags or (parent and parent.region_frags) or {},
        expr_frags = opts.expr_frags or (parent and parent.expr_frags) or {},
        protocol_types = opts.protocol_types or (parent and parent.protocol_types) or {},
        require_cache = opts.require_cache or (parent and parent.require_cache) or {},
        require_stack = opts.require_stack or (parent and parent.require_stack) or {},
        root_deps = opts.root_deps or (parent and parent.root_deps) or {},
        module_path_patterns = opts.module_path_patterns or opts.module_paths or (parent and parent.module_path_patterns),
    }, Runtime)
    local lua_src = translate_runtime(runtime)
    local q = Quote()
    local rt = q:val(runtime, "runtime")
    q("return function(...)")
    q("local __moonlift_runtime = %s", rt)
    q("local moon = setmetatable({ require = function(name) return __moonlift_runtime:require(name) end }, { __index = __moonlift_runtime.session:api() })")
    q(lua_src)
    q("end")
    local inner = q:compile(chunk_name or "=(moonlift.mlua_run)")
    local function fn(...)
        local pop = push_runtime(runtime)
        local function pack(ok, ...) return { ok = ok, n = select("#", ...), ... } end
        local results = pack(pcall(inner, ...))
        pop()
        if not results.ok then error(results[1], 0) end
        return unpack(results, 1, results.n)
    end
    return fn, runtime, lua_src
end

function M.loadfile(path, opts)
    local f = assert(io.open(path, "rb")); local src = f:read("*a"); f:close()
    return M.loadstring(src, path, opts)
end

local function is_load_opts(v)
    return type(v) == "table" and (v.runtime ~= nil or v.T ~= nil or v.session ~= nil or v.prefix ~= nil or v.region_frags ~= nil or v.expr_frags ~= nil)
end

function M.dofile(path, opts, ...)
    if is_load_opts(opts) then
        local fn = assert(M.loadfile(path, opts))
        return fn(...)
    end
    -- Auto-detect parent runtime for .mlua files loaded from within .mlua
    if not opts and path:match("%.mlua$") then
        local parent = M.current_runtime()
        if parent then
            local fn = assert(M.loadfile(path, { runtime = parent }))
            return fn(...)
        end
    end
    local fn = assert(M.loadfile(path))
    if opts == nil then return fn(...) end
    return fn(opts, ...)
end

function M.eval(src, chunk_name, ...)
    local fn = assert(M.loadstring(src, chunk_name or "=(moonlift.mlua_run.eval)"))
    return fn(...)
end

return M
