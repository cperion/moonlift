-- ASDL-hosted .mlua runner.
--
-- This replaces host_quote as the execution bridge.  The document is first
-- segmented into MoonMlua/MoonHost ASDL values.  Generated Lua is now only the
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
local ModuleValue = {}; ModuleValue.__index = ModuleValue
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

local function splice_to_source(value)
    local tv = type(value)
    if tv == "number" or tv == "boolean" then return tostring(value) end
    if tv == "nil" then return "nil" end
    if tv == "string" then return value end
    if (tv == "table" or tv == "userdata") and type(value.moonlift_splice_source) == "function" then
        return value:moonlift_splice_source()
    end
    error("cannot splice host value " .. tv, 3)
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

local function adopt_splice_value(runtime, value)
    if type(value) ~= "table" then return end
    local kind = rawget(value, "moonlift_quote_kind") or rawget(value, "kind")
    if kind == "region_frag" and value.frag ~= nil then
        runtime.region_frags[value.name or value.frag.name] = value
        local deps = value.deps
        if deps and deps.region_frags then
            for i = 1, #deps.region_frags do
                local frag = deps.region_frags[i]
                runtime.region_frags[frag.name] = runtime.region_frags[frag.name] or frag
            end
        end
        if deps and deps.expr_frags then
            for i = 1, #deps.expr_frags do
                local frag = deps.expr_frags[i]
                runtime.expr_frags[frag.name] = runtime.expr_frags[frag.name] or frag
            end
        end
    elseif kind == "expr_frag" and value.frag ~= nil then
        runtime.expr_frags[value.name or value.frag.name] = value
    end
end

local function render_template(runtime, template, closures)
    local H = runtime.T.MoonHost
    local out = {}
    for i = 1, #template.parts do
        local part = template.parts[i]
        local cls = pvm.classof(part)
        if cls == H.TemplateText then
            out[#out + 1] = part.text.source.text
        elseif cls == H.TemplateSplicePart then
            local fn = closures and closures[part.splice.id]
            if not fn then error("missing splice closure " .. part.splice.id, 2) end
            local value = fn()
            adopt_splice_value(runtime, value)
            out[#out + 1] = splice_to_source(value)
        end
    end
    return table.concat(out)
end

local function normalize_moonlift_body(src)
    return require("moonlift.mlua_lex").moonlift_body(src)
end

local function parse_region(runtime, source)
    local parsed = require("moonlift.parse").Define(runtime.T).parse_region_frag(normalize_moonlift_body(source), {
        region_frags = runtime.region_frags,
        expr_frags = runtime.expr_frags,
    })
    if #parsed.issues ~= 0 then error("region parse failed: " .. tostring(parsed.issues[1]), 2) end
    local value = HostValues.region_frag_value(runtime.session, parsed.value.frag, { deps = parsed.value.deps })
    runtime.region_frags[value.name] = value
    return value
end

local function parse_expr(runtime, source)
    local parsed = require("moonlift.parse").Define(runtime.T).parse_expr_frag(normalize_moonlift_body(source), {
        expr_frags = runtime.expr_frags,
    })
    if #parsed.issues ~= 0 then error("expr parse failed: " .. tostring(parsed.issues[1]), 2) end
    local value = HostValues.expr_frag_value(runtime.session, parsed.value.frag)
    runtime.expr_frags[value.name] = value
    return value
end

local function module_body_from_source(src)
    local Lex = require("moonlift.mlua_lex")
    local module_pos, module_name, module_start = src:match("^()%s*module%s+([_%a][_%w]*)()")
    local name_is_keyword = module_name and ({ export = true, extern = true, func = true, ["type"] = true, region = true, expr = true, struct = true, expose = true })[module_name]
    if not module_name or name_is_keyword then
        module_pos, module_start = src:match("^()%s*module%s*()\n")
        if not module_pos then module_pos, module_start = src:match("^()%s*module%s*()$") end
    end
    if not module_start then return src end
    local end_pos = Lex.find_matching_end(src, module_pos, Lex.open_words_island)
    if not end_pos then return src end
    local body = src:sub(module_start, end_pos - 3):gsub("^%s+", ""):gsub("%s+$", "")
    local maybe_name, rest = body:match("^%s*([_%a][_%w]*)([%s%S]*)$")
    if maybe_name and not Lex.open_words_form[maybe_name] and not ({ export = true, extern = true, const = true, static = true, import = true, ["type"] = true })[maybe_name] then body = rest end
    return body
end

local function parse_module(runtime, source)
    source = module_body_from_source(source)
    local Parse = require("moonlift.parse").Define(runtime.T)
    local parsed = Parse.parse_module(normalize_moonlift_body(source), {
        region_frags = runtime.region_frags,
        expr_frags = runtime.expr_frags,
    })
    if #parsed.issues ~= 0 then error("module parse failed: " .. tostring(parsed.issues[1]), 2) end
    return setmetatable({ kind = "module", module = parsed.module, T = runtime.T, runtime = runtime }, ModuleValue)
end

local function parse_func(runtime, source)
    local m = parse_module(runtime, source)
    local Tr = runtime.T.MoonTree
    for i = 1, #m.module.items do
        local item = m.module.items[i]
        if pvm.classof(item) == Tr.ItemFunc then
            return setmetatable({ kind = "func", name = item.func.name, func = item.func, module = m, T = runtime.T, runtime = runtime }, FuncValue)
        end
    end
    error("func island did not produce function", 2)
end

function Runtime:eval_island(step_index, closures)
    local step = assert(self.program.steps[step_index], "unknown island step " .. tostring(step_index))
    local text = render_template(self, step.template, closures or {})
    local kind = step.template.kind_word
    if kind == "region" then return parse_region(self, text) end
    if kind == "expr" then return parse_expr(self, text) end
    if kind == "module" then return parse_module(self, text) end
    if kind == "func" then return parse_func(self, text) end
    error("unsupported hosted island kind in ASDL runner: " .. tostring(kind), 2)
end

function ModuleValue:compile()
    local OpenExpand = require("moonlift.open_expand").Define(self.T)
    local Typecheck = require("moonlift.tree_typecheck").Define(self.T)
    local Layout = require("moonlift.sem_layout_resolve").Define(self.T)
    local TreeToBack = require("moonlift.tree_to_back").Define(self.T)
    local Validate = require("moonlift.back_validate").Define(self.T)
    local J = require("moonlift.back_jit").Define(self.T)
    local expanded = OpenExpand.module(self.module, OpenExpand.env_with_frags(self.runtime.region_frags, self.runtime.expr_frags))
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

local function expression_for_island(T, step_index, island, template)
    local H = T.MoonHost
    local entries = {}
    for i = 1, #template.parts do
        local part = template.parts[i]
        if pvm.classof(part) == H.TemplateSplicePart then
            entries[#entries + 1] = string.format("[%q] = function() return (%s) end", part.splice.id, part.splice.lua_source.text)
        end
    end
    return string.format("__moonlift_runtime:eval_island(%d, {%s})", step_index, table.concat(entries, ","))
end

local function translation_for_island(T, step_index, island, template)
    -- Islands lower to expressions.  Binding is now explicit Lua responsibility:
    -- `local x = region R ... end` or `return module ... end`.
    return expression_for_island(T, step_index, island, template)
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
    }, Runtime)
    local lua_src = translate_runtime(runtime)
    local q = Quote()
    local rt = q:val(runtime, "runtime")
    q("return function(...)")
    q("local __moonlift_runtime = %s", rt)
    q("local moon = __moonlift_runtime.session:api()")
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
    local fn = assert(M.loadfile(path))
    if opts == nil then return fn(...) end
    return fn(opts, ...)
end

function M.eval(src, chunk_name, ...)
    local fn = assert(M.loadstring(src, chunk_name or "=(moonlift.mlua_run.eval)"))
    return fn(...)
end

return M
