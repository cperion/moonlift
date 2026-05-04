-- Hosted .mlua execution bridge.
--
-- `.mlua` is LuaJIT Lua plus Moonlift hosted islands.  Island discovery is not
-- implemented here anymore: it flows through the MoonMlua document parser first
-- (`mlua_document`), so the executable host chunk is produced from parsed
-- MLUA segments instead of a second ad-hoc scanner/rewrite pass.
--
-- Moonlift meaning still flows through ASDL/PVM phases:
--   MLUA document -> MoonMlua segments -> MoonHost / MoonTree ASDL -> phases.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Quote = require("moonlift.quote")
local Lex = require("moonlift.mlua_lex")

local M = {}

local FuncQuote = {}; FuncQuote.__index = FuncQuote
local ModuleQuote = {}; ModuleQuote.__index = ModuleQuote
local RegionFragValue = {}; RegionFragValue.__index = RegionFragValue
local ExprFragValue = {}; ExprFragValue.__index = ExprFragValue
local QuoteSource = {}; QuoteSource.__index = QuoteSource
local StructDeclValue = {}; StructDeclValue.__index = StructDeclValue
local ExposeDeclValue = {}; ExposeDeclValue.__index = ExposeDeclValue
local TypedSplice = {}; TypedSplice.__index = TypedSplice
local TypeValue = {}; TypeValue.__index = TypeValue
local CompiledFunction = {}; CompiledFunction.__index = CompiledFunction
local CompiledModule = {}; CompiledModule.__index = CompiledModule
local HostRuntime = {}; HostRuntime.__index = HostRuntime

local skip_comment_or_string = Lex.skip_comment_or_string
local lua_string_literal = Lex.lua_string_literal

local function normalize_method_func_source(src)
    local prefix, owner, method_name, rest = src:match("^%s*(export%s+)func%s+([_%a][_%w]*)%s*:%s*([_%a][_%w]*)(.*)$")
    if not owner then prefix, owner, method_name, rest = "", src:match("^%s*func%s+([_%a][_%w]*)%s*:%s*([_%a][_%w]*)(.*)$") end
    if not owner then return src, nil, nil end
    return (prefix or "") .. "func " .. owner .. "_" .. method_name .. rest, owner, method_name
end

local function module_body_from_source(src)
    -- Extract the body from a module wrapper: "module [Name] ... end"
    local module_pos, module_name, module_start = src:match("^()%s*module%s+([_%a][_%w]*)()")
    local name_is_keyword = module_name and ({ export = true, extern = true, func = true, ["type"] = true, region = true, expr = true, struct = true, expose = true })[module_name]
    if not module_name or name_is_keyword then
        -- Anonymous module or name matched a keyword: "module\n ... end"
        module_pos, module_start = src:match("^()%s*module%s*()\n")
        if not module_pos then
            module_pos, module_start = src:match("^()%s*module%s*()$")
        end
    end
    if not module_start then return src end
    local end_pos = Lex.find_matching_end(src, module_pos, Lex.open_words_island)
    if not end_pos then return src end
    local body = src:sub(module_start, end_pos - 3)  -- exclude the closing 'end'
    body = body:gsub("^%s+", ""):gsub("%s+$", "")
    -- Strip the module name if it redundantly appears as first word of body
    local maybe_name, rest = body:match("^%s*([_%a][_%w]*)([%s%S]*)$")
    if maybe_name and not Lex.open_words_form[maybe_name]
        and not ({ export = true, extern = true, const = true, static = true, import = true })[maybe_name] then
        body = rest
    end
    return body
end

local function expected_splice_kind(src, at)
    local prefix = src:sub(1, at - 1):gsub("%s+$", "")
    if prefix:match("%f[%w_]emit%s*$") then return "emit" end
    local line = prefix:match("([^\n]*)$") or prefix
    if line:match(":%s*[%w_%.%s%(]*$") or line:match("%-%>%s*[%w_%.%s%(]*$") or line:match("%f[%w_]as%s*%(%s*$") then return "type" end
    return "expr"
end

local function find_antiquote_end(src, i)
    local depth = 1
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        else
            local c = src:sub(i, i)
            if c == "{" then depth = depth + 1; i = i + 1
            elseif c == "}" then
                depth = depth - 1
                if depth == 0 then return i end
                i = i + 1
            else
                i = i + 1
            end
        end
    end
    error("unterminated Moonlift antiquote @{...}", 2)
end

local function typed_splice_expr(lua_expr, expected)
    return "{__moonlift_host.typed_splice((" .. lua_expr .. "), " .. lua_string_literal(expected) .. ")}"
end

local function source_expr_with_antiquotes(src)
    local parts = {}
    local i, literal_start = 1, 1
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        elseif src:sub(i, i + 1) == "@{" then
            if literal_start < i then parts[#parts + 1] = lua_string_literal(src:sub(literal_start, i - 1)) end
            local e = find_antiquote_end(src, i + 2)
            parts[#parts + 1] = typed_splice_expr(src:sub(i + 2, e - 1), expected_splice_kind(src, i))
            i = e + 1
            literal_start = i
        else
            i = i + 1
        end
    end
    if literal_start <= #src then parts[#parts + 1] = lua_string_literal(src:sub(literal_start)) end
    if #parts == 0 then parts[1] = lua_string_literal("") end
    return "__moonlift_host.source({" .. table.concat(parts, ", ") .. "})"
end

local function translate_island(kind, source)
    if kind == "struct" then
        local name = assert(source:match("^%s*struct%s+([_%a][_%w]*)"), "struct island without name")
        return "local " .. name .. " = __moonlift_host.struct_from_source(" .. source_expr_with_antiquotes(source) .. ")"
    end
    if kind == "expose" then
        local name = source:match("^%s*expose%s+([_%a][_%w]*)%s*:")
        assert(name, "expected expose Name: subject")
        return "local " .. name .. " = __moonlift_host.expose_from_source(" .. source_expr_with_antiquotes(source) .. ")"
    end
    if kind == "func" then
        local _, owner, method_name = normalize_method_func_source(source)
        local expr = "__moonlift_host.func_from_source(" .. source_expr_with_antiquotes(source) .. ")"
        if owner and method_name then return owner .. "." .. method_name .. " = " .. expr end
        return expr
    end
    if kind == "module" then
        return "__moonlift_host.module_from_source(" .. source_expr_with_antiquotes(module_body_from_source(source)) .. ")"
    end
    if kind == "region" then
        return "__moonlift_host.region_from_source(" .. source_expr_with_antiquotes(source) .. ")"
    end
    if kind == "expr" then
        return "__moonlift_host.expr_from_source(" .. source_expr_with_antiquotes(source) .. ")"
    end
    error("unknown hosted island kind: " .. tostring(kind), 2)
end

local function parsed_mlua_parts(src, name)
    local A = require("moonlift.asdl")
    local T = pvm.context()
    A.Define(T)
    local S = T.MoonSource
    local doc = S.DocumentSnapshot(S.DocUri(name or "<mlua>"), S.DocVersion(0), S.LangMlua, src)
    return require("moonlift.mlua_document").Define(T).document_parts(doc), T
end

local function island_kind_word(Mlua, island)
    if island.kind == Mlua.IslandStruct then return "struct" end
    if island.kind == Mlua.IslandExpose then return "expose" end
    if island.kind == Mlua.IslandFunc then return "func" end
    if island.kind == Mlua.IslandModule then return "module" end
    if island.kind == Mlua.IslandRegion then return "region" end
    if island.kind == Mlua.IslandExpr then return "expr" end
    error("unknown hosted island kind", 2)
end

function M.translate(src, name)
    local parts, T = parsed_mlua_parts(src, name)
    local Mlua = T.MoonMlua
    local out = {}
    for i = 1, #parts.segments do
        local seg = parts.segments[i]
        local cls = pvm.classof(seg)
        if cls == Mlua.LuaOpaque then
            out[#out + 1] = seg.occurrence.slice.text
        elseif cls == Mlua.HostedIsland then
            local kind = island_kind_word(Mlua, seg.island)
            local source = seg.island.source.text
            out[#out + 1] = translate_island(kind, source)
        elseif cls == Mlua.MalformedIsland then
            error(seg.reason, 2)
        else
            error("unknown MLUA document segment", 2)
        end
    end
    return table.concat(out)
end

local function new_quote_deps()
    return { region_frags = {}, expr_frags = {} }
end

local function merge_named(dst, src)
    for k, v in pairs(src or {}) do dst[k] = v end
end

local function merge_deps(dst, src)
    if src == nil then return dst end
    merge_named(dst.region_frags, src.region_frags)
    merge_named(dst.expr_frags, src.expr_frags)
    return dst
end

local function clone_deps(src)
    return merge_deps(new_quote_deps(), src)
end

local function quote_kind(v)
    if type(v) ~= "table" and type(v) ~= "userdata" then return nil end
    return rawget(v, "moonlift_quote_kind")
end

local function normalize_source(src)
    if getmetatable(src) == QuoteSource then return src.source, clone_deps(src.deps) end
    return src, new_quote_deps()
end

function M.typed_splice(value, expected)
    return setmetatable({ value = value, expected = expected }, TypedSplice)
end

local function splice_kind(v)
    local tv = type(v)
    if tv == "number" or tv == "boolean" or tv == "nil" or tv == "string" then return "expr" end
    if tv == "table" or tv == "userdata" then
        local mt = getmetatable(v)
        if mt == TypedSplice then return splice_kind(v.value) end
        local qk = quote_kind(v)
        if qk == "region_frag" then return "region" end
        if qk == "expr_frag" then return "expr" end
        if qk == "source" then return "source" end
        if qk == "type" then return "type" end
        if mt == TypeValue or mt == StructDeclValue then return "type" end
        if type(v.as_type_value) == "function" then return "type" end
        if type(v.moonlift_splice_source) == "function" then return "source" end
    end
    return tv
end

local function splice_kind_matches(actual, expected)
    if expected == nil or expected == "any" then return true end
    if expected == "emit" then return actual == "region" or actual == "expr" end
    if actual == "source" and (expected == "expr" or expected == "emit") then return true end
    return actual == expected
end

function M.splice_checked(v, expected)
    if getmetatable(v) == TypedSplice then expected = v.expected or expected; v = v.value end
    -- Plain Lua primitives are valid MoonLift source text in any position.
    -- Kind checking only applies to structured values (fragments, TypeValues, etc.).
    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" or tv == "nil" then
        return M.splice(v)
    end
    local actual = splice_kind(v)
    if not splice_kind_matches(actual, expected) then
        error("Moonlift splice kind mismatch: expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
    return M.splice(v)
end

function M.splice(v)
    local tv = type(v)
    if tv == "number" then return tostring(v) end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "nil" then return "nil" end
    if tv == "string" then return v end
    if tv == "table" or tv == "userdata" then
        local mt = getmetatable(v)
        if mt == TypedSplice then return M.splice_checked(v) end
        if mt and mt.__moonlift_splice_source then return mt.__moonlift_splice_source(v) end
        if type(v.moonlift_splice_source) == "function" then return v:moonlift_splice_source() end
    end
    error("cannot splice Lua value of type " .. tv .. " into Moonlift source", 2)
end

local function append_source_part(out, deps, part, expected)
    if type(part) == "table" and getmetatable(part) == nil and #part == 1 then part = part[1] end
    if getmetatable(part) == TypedSplice then return append_source_part(out, deps, part.value, part.expected or expected) end
    if type(part) == "string" and expected == nil then
        out[#out + 1] = part
        return
    end
    out[#out + 1] = M.splice_checked(part, expected)
    local qk = quote_kind(part)
    if qk == "source" then
        merge_deps(deps, part.deps)
    elseif qk == "region_frag" then
        merge_deps(deps, part.deps)
        deps.region_frags[part.name] = part
    elseif qk == "expr_frag" then
        merge_deps(deps, part.deps)
        deps.expr_frags[part.name] = part
    end
end

function M.source(parts)
    local out, deps = {}, new_quote_deps()
    for i = 1, #parts do append_source_part(out, deps, parts[i], nil) end
    return setmetatable({ moonlift_quote_kind = "source", source = table.concat(out), deps = deps }, QuoteSource)
end

function QuoteSource:moonlift_splice_source() return self.source end
function QuoteSource:__tostring() return self.source end

function TypeValue:moonlift_splice_source() return self.source end
function TypeValue:__tostring() return "MoonliftType(" .. self.source .. ")" end

function M.type(source)
    assert(type(source) == "string" and source ~= "", "Moonlift type source must be a non-empty string")
    return setmetatable({ moonlift_quote_kind = "type", source = source }, TypeValue)
end

M.i8 = M.type("i8"); M.i16 = M.type("i16"); M.i32 = M.type("i32"); M.i64 = M.type("i64")
M.u8 = M.type("u8"); M.u16 = M.type("u16"); M.u32 = M.type("u32"); M.u64 = M.type("u64")
M.f32 = M.type("f32"); M.f64 = M.type("f64")
M.bool = M.type("bool"); M.void = M.type("void"); M.index = M.type("index")

function M.ptr(elem)
    if getmetatable(elem) == TypeValue then elem = elem.source end
    assert(type(elem) == "string", "ptr expects a Moonlift type value or source string")
    return M.type("ptr(" .. elem .. ")")
end

local function new_host_context()
    local A = require("moonlift.asdl")
    local T = pvm.context()
    A.Define(T)
    return T
end

local function parse_mlua_source_in(T, src, name)
    local MluaParse = require("moonlift.mlua_parse")
    return MluaParse.Define(T).parse(src, name or "<mlua>"), T
end

local function parse_mlua_source(src, name)
    local T = new_host_context()
    return parse_mlua_source_in(T, src, name)
end

local function first_decl(result, cls)
    for i = 1, #result.decls.decls do
        local d = result.decls.decls[i]
        if pvm.classof(d) == cls then return d.decl, d end
    end
    return nil
end

local function runtime_add_decl(runtime, decl)
    if runtime and decl then runtime.decls[#runtime.decls + 1] = decl end
    return decl
end

function HostRuntime:host_decl_set()
    return self.T.MoonHost.HostDeclSet(self.decls)
end

function HostRuntime:parse(src, name)
    local source = normalize_source(src)
    return parse_mlua_source_in(self.T, source, name or self.name)
end

function HostRuntime:host_pipeline(src, module_name, target)
    local source = normalize_source(src)
    local parsed = parse_mlua_source_in(self.T, source, module_name or self.name)
    return require("moonlift.mlua_host_pipeline").Define(self.T).pipeline(parsed, module_name or self.name, target)
end

function HostRuntime:host_pipeline_result(module_name, target)
    local H, Tr = self.T.MoonHost, self.T.MoonTree
    local parsed = H.MluaParseResult(self:host_decl_set(), Tr.Module(Tr.ModuleSurface, {}), {}, {}, {})
    return require("moonlift.mlua_host_pipeline").Define(self.T).pipeline(parsed, module_name or self.name, target)
end

function M.parse(src, name)
    local source = normalize_source(src)
    return parse_mlua_source(source, name)
end

function M.parsefile(path)
    local f, err = io.open(path, "rb"); if not f then error(err, 2) end
    local src = f:read("*a"); f:close()
    return parse_mlua_source(src, "@" .. path)
end

function M.host_pipeline(src, module_name, target)
    local source = normalize_source(src)
    local parsed, T = parse_mlua_source(source, module_name or "<mlua>")
    return require("moonlift.mlua_host_pipeline").Define(T).pipeline(parsed, module_name, target)
end

function M.host_pipelinefile(path, module_name, target)
    local f, err = io.open(path, "rb"); if not f then error(err, 2) end
    local src = f:read("*a"); f:close()
    return M.host_pipeline(src, module_name or path, target)
end

function StructDeclValue:moonlift_splice_source() return self.name end
function StructDeclValue:as_host_decl() return self.host_decl end
function StructDeclValue:host_decl_set()
    local H = self.T.MoonHost
    local decls = { self.host_decl }
    for i = 1, #(self.lua_accessors or {}) do decls[#decls + 1] = self.lua_accessors[i] end
    return H.HostDeclSet(decls)
end
function StructDeclValue:__tostring() return "MoonliftStructDecl(" .. tostring(self.name) .. ")" end
function StructDeclValue:__newindex(k, v)
    rawset(self, k, v)
    if type(k) ~= "string" or not (self.T and self.name) then return end
    local H = self.T.MoonHost
    local host_decl
    if type(v) == "function" then
        host_decl = H.HostDeclAccessor(H.HostAccessorLua(self.name, k, self.name .. "_" .. k))
    elseif getmetatable(v) == FuncQuote and v.host_func then
        host_decl = H.HostDeclAccessor(H.HostAccessorMoonlift(self.name, k, v.host_func))
    end
    if host_decl then
        self.lua_accessors = self.lua_accessors or {}
        self.lua_accessors[#self.lua_accessors + 1] = host_decl
        runtime_add_decl(self.runtime, host_decl)
    end
end

function ExposeDeclValue:as_host_decl() return self.host_decl end
function ExposeDeclValue:__tostring()
    return "MoonliftExposeDecl(" .. tostring(self.decl and self.decl.public_name or "<expose>") .. ")"
end

local function struct_from_source_in(runtime, src)
    local source = normalize_source(src)
    local result = parse_mlua_source_in(runtime.T, source, "<struct>")
    local decl = first_decl(result, runtime.T.MoonHost.HostDeclStruct)
    local host_decl = decl and runtime.T.MoonHost.HostDeclStruct(decl)
    local name = decl and decl.name or source:match("^%s*struct%s+([_%a][_%w]*)")
    runtime_add_decl(runtime, host_decl)
    return setmetatable({ name = name, source = source, parse_result = result, T = runtime.T, runtime = runtime, decl = decl, host_decl = host_decl, lua_accessors = {} }, StructDeclValue)
end

local function expose_from_source_in(runtime, src)
    local source = normalize_source(src)
    local result = parse_mlua_source_in(runtime.T, source, "<expose>")
    local decl = first_decl(result, runtime.T.MoonHost.HostDeclExpose)
    local host_decl = decl and runtime.T.MoonHost.HostDeclExpose(decl)
    runtime_add_decl(runtime, host_decl)
    return setmetatable({ source = source, parse_result = result, T = runtime.T, runtime = runtime, decl = decl, host_decl = host_decl }, ExposeDeclValue)
end

function M.struct_from_source(src)
    return struct_from_source_in(M.new_runtime(), src)
end

function M.expose_from_source(src)
    return expose_from_source_in(M.new_runtime(), src)
end

function RegionFragValue:moonlift_splice_source() return self.name end
function RegionFragValue:__tostring() return "MoonliftRegionFrag(" .. self.name .. ")" end
function ExprFragValue:moonlift_splice_source() return self.name end
function ExprFragValue:__tostring() return "MoonliftExprFrag(" .. self.name .. ")" end

local function normalize_moonlift_body(src)
    return Lex.moonlift_body(src)
end

local function parse_signature(src)
    local source = normalize_source(src)
    local normalized = normalize_method_func_source(source)
    src = normalize_moonlift_body(normalized)
    local name, params_src, result = src:match("^%s*export%s+func%s+([_%a][_%w]*)%s*%((.-)%)%s*%-%>%s*([^%s]+)")
    if not name then name, params_src, result = src:match("^%s*func%s+([_%a][_%w]*)%s*%((.-)%)%s*%-%>%s*([^%s]+)") end
    if not name then name, params_src = src:match("^%s*export%s+func%s+([_%a][_%w]*)%s*%((.-)%)") end
    if not name then name, params_src = src:match("^%s*func%s+([_%a][_%w]*)%s*%((.-)%)") end
    result = result or "void"
    assert(name, "host func quote: expected `func name(params...) [-> result]`")
    local params = {}
    for param in (params_src or ""):gmatch("[^,]+") do
        local pname, pty = param:match("^%s*([_%a][_%w]*)%s*:%s*(.-)%s*$")
        if pname then params[#params + 1] = { name = pname, ty = pty } end
    end
    return { name = name, params = params, result = result }
end

local function module_item_source(src)
    -- Use the same nesting-aware extraction as module_body_from_source
    return module_body_from_source(src)
end

local function parse_module_signatures(src)
    local signatures = {}
    local normalized = normalize_moonlift_body(src)
    for chunk in normalized:gmatch("export%s+func%s+[_%a][_%w]*%s*%b()%s*%-%>%s*[^\n]+") do
        local sig = parse_signature(chunk); signatures[sig.name] = sig
    end
    for chunk in normalized:gmatch("export%s+func%s+[_%a][_%w]*%s*%b()") do
        local sig = parse_signature(chunk); signatures[sig.name] = signatures[sig.name] or sig
    end
    return signatures
end

local ctype_scalar = {
    i8 = "int8_t", i16 = "int16_t", i32 = "int32_t", i64 = "int64_t",
    u8 = "uint8_t", u16 = "uint16_t", u32 = "uint32_t", u64 = "uint64_t",
    f32 = "float", f64 = "double", bool = "bool", void = "void", index = "intptr_t",
}

local function ctype_of(ty)
    ty = ty:gsub("%s+", "")
    local ptr_inner = ty:match("^ptr%((.+)%)$")
    if ptr_inner then return (ctype_scalar[ptr_inner] or "void") .. " *" end
    if ty:match("^view%(.+%)$") then return "void *" end
    return assert(ctype_scalar[ty], "host func quote: unsupported FFI ctype for Moonlift type `" .. ty .. "`")
end

local function c_sig_of(sig)
    local args = {}
    for i = 1, #sig.params do args[i] = ctype_of(sig.params[i].ty) end
    return ctype_of(sig.result) .. " (*)(" .. table.concat(args, ", ") .. ")"
end

local function compile_module_source(src, deps)
    deps = deps or new_quote_deps()
    src = module_item_source(src)
    local A2 = require("moonlift.asdl")
    local Parse = require("moonlift.parse")
    local OpenFacts = require("moonlift.open_facts")
    local OpenValidate = require("moonlift.open_validate")
    local OpenExpand = require("moonlift.open_expand")
    local Typecheck = require("moonlift.tree_typecheck")
    local TreeToBack = require("moonlift.tree_to_back")
    local Validate = require("moonlift.back_validate")
    local J = require("moonlift.back_jit")

    local T = pvm.context(); A2.Define(T)
    local P = Parse.Define(T)
    local OF = OpenFacts.Define(T)
    local OV = OpenValidate.Define(T)
    local OE = OpenExpand.Define(T)
    local TC = Typecheck.Define(T)
    local Lower = TreeToBack.Define(T)
    local V = Validate.Define(T)
    local jit_api = J.Define(T)

    local parsed_expr_frags = {}
    for name, frag_value in pairs(deps.expr_frags or {}) do
        local parsed = P.parse_expr_frag(frag_value.source)
        if #parsed.issues ~= 0 then error("host expr parse failed: " .. tostring(parsed.issues[1]), 2) end
        parsed_expr_frags[name] = parsed.value
    end

    local parsed_region_frags = {}
    for name, frag_value in pairs(deps.region_frags or {}) do
        local parsed = P.parse_region_frag(frag_value.source, { expr_frags = parsed_expr_frags, region_frags = parsed_region_frags })
        if #parsed.issues ~= 0 then error("host region parse failed: " .. tostring(parsed.issues[1]), 2) end
        parsed_region_frags[name] = parsed.value
    end

    local parsed = P.parse_module(normalize_moonlift_body(src), { region_frags = parsed_region_frags, expr_frags = parsed_expr_frags })
    if #parsed.issues ~= 0 then error("host module parse failed: " .. tostring(parsed.issues[1]), 2) end
    local expanded = OE.module(parsed.module, OE.env_with_frags(parsed_region_frags, parsed_expr_frags))
    local open_report = OV.validate(OF.facts_of_module(expanded))
    if #open_report.issues ~= 0 then error("host module open validation failed: " .. tostring(open_report.issues[1]), 2) end
    local checked = TC.check_module(expanded)
    if #checked.issues ~= 0 then error("host module typecheck failed: " .. tostring(checked.issues[1]), 2) end
    local program = Lower.module(checked.module)
    local report = V.validate(program)
    if #report.issues ~= 0 then error("host module back validation failed: " .. tostring(report.issues[1]), 2) end
    return jit_api.jit():compile(program), T
end

local function export_func_source(src)
    if src:match("^%s*export%s+func") then return src end
    local out = src:gsub("^%s*func", "export func", 1)
    return out
end

function M.func_from_source(src)
    local source, deps = normalize_source(src)
    local normalized, owner_name, method_name = normalize_method_func_source(source)
    normalized = normalize_moonlift_body(normalized)
    local sig = parse_signature(normalized)
    return setmetatable({ moonlift_quote_kind = "func", source = normalized, deps = deps, name = sig.name, params = sig.params, result = sig.result, owner_name = owner_name, method_name = method_name }, FuncQuote)
end

local function extract_module_local_frags(source, deps)
    local parts, T = parsed_mlua_parts(source, "<module>")
    local Mlua = T.MoonMlua
    local out = {}
    for i = 1, #parts.segments do
        local seg = parts.segments[i]
        local cls = pvm.classof(seg)
        if cls == Mlua.LuaOpaque then
            out[#out + 1] = seg.occurrence.slice.text
        elseif cls == Mlua.HostedIsland then
            local kind = island_kind_word(Mlua, seg.island)
            local form = seg.island.source.text
            if kind == "region" then
                local name = assert(form:match("^%s*region%s+([_%a][_%w]*)"), "module-local region name")
                deps.region_frags[name] = setmetatable({ moonlift_quote_kind = "region_frag", name = name, source = form, deps = new_quote_deps() }, RegionFragValue)
                out[#out + 1] = "\n"
            elseif kind == "expr" then
                local name = assert(form:match("^%s*expr%s+([_%a][_%w]*)"), "module-local expr name")
                deps.expr_frags[name] = setmetatable({ moonlift_quote_kind = "expr_frag", name = name, source = form, deps = new_quote_deps() }, ExprFragValue)
                out[#out + 1] = "\n"
            else
                out[#out + 1] = form
            end
        elseif cls == Mlua.MalformedIsland then
            error(seg.reason, 2)
        end
    end
    return table.concat(out), deps
end

function M.module_from_source(src)
    local source, deps = normalize_source(src)
    source = module_item_source(source)
    source, deps = extract_module_local_frags(source, deps)
    return setmetatable({ moonlift_quote_kind = "module", source = source, deps = deps, signatures = parse_module_signatures(source) }, ModuleQuote)
end

local function parse_host_func_ast(T, quote)
    local Parse = require("moonlift.parse").Define(T)
    local parsed = Parse.parse_module(quote:module_source())
    if #parsed.issues ~= 0 then return nil end
    for i = 1, #parsed.module.items do
        local item = parsed.module.items[i]
        if pvm.classof(item) == T.MoonTree.ItemFunc then return item.func end
    end
    return nil
end

function M.new_runtime(opts)
    opts = opts or {}
    local runtime = setmetatable({
        T = opts.T or new_host_context(),
        name = opts.name or "mlua",
        decls = {},
    }, HostRuntime)
    runtime.source = M.source
    runtime.typed_splice = M.typed_splice
    runtime.splice = M.splice
    runtime.splice_checked = M.splice_checked
    runtime.type = M.type
    runtime.ptr = M.ptr
    runtime.i8, runtime.i16, runtime.i32, runtime.i64 = M.i8, M.i16, M.i32, M.i64
    runtime.u8, runtime.u16, runtime.u32, runtime.u64 = M.u8, M.u16, M.u32, M.u64
    runtime.f32, runtime.f64 = M.f32, M.f64
    runtime.bool, runtime.void, runtime.index = M.bool, M.void, M.index
    runtime.struct_from_source = function(src) return struct_from_source_in(runtime, src) end
    runtime.expose_from_source = function(src) return expose_from_source_in(runtime, src) end
    runtime.func_from_source = function(src)
        local quote = M.func_from_source(src)
        quote.host_func = parse_host_func_ast(runtime.T, quote)
        return quote
    end
    runtime.module_from_source = M.module_from_source
    runtime.region_from_source = M.region_from_source
    runtime.expr_from_source = M.expr_from_source
    return runtime
end

function M.region_from_source(src)
    local source, deps = normalize_source(src)
    local name = assert(source:match("^%s*region%s+([_%a][_%w]*)"), "host region quote: expected `region name(...)`")
    return setmetatable({ moonlift_quote_kind = "region_frag", name = name, source = source, deps = deps }, RegionFragValue)
end

function M.expr_from_source(src)
    local source, deps = normalize_source(src)
    local name = assert(source:match("^%s*expr%s+([_%a][_%w]*)"), "host expr quote: expected `expr name(...)`")
    return setmetatable({ moonlift_quote_kind = "expr_frag", name = name, source = source, deps = deps }, ExprFragValue)
end

function FuncQuote:module_source() return export_func_source(self.source) end
function FuncQuote:compile()
    local m = M.module_from_source(setmetatable({ moonlift_quote_kind = "source", source = self:module_source(), deps = clone_deps(self.deps) }, QuoteSource)):compile()
    local f = m:get(self.name); f.owns_module = true; return f
end
function FuncQuote:__tostring() return "MoonliftFuncQuote(" .. self.name .. ")" end

function ModuleQuote:compile()
    local artifact, T = compile_module_source(self.source, self.deps)
    return setmetatable({ quote = self, artifact = artifact, T = T, functions = {} }, CompiledModule)
end
function ModuleQuote:__tostring() return "MoonliftModuleQuote" end

function CompiledModule:get(name)
    local cached = self.functions[name]
    if cached then return cached end
    local sig = assert(self.quote.signatures[name], "compiled module has no exported function signature for `" .. tostring(name) .. "`")
    local B2 = self.T.MoonBack
    local ptr = self.artifact:getpointer(B2.BackFuncId(name))
    local c_sig = c_sig_of(sig)
    local fn = ffi.cast(c_sig, ptr)
    local wrapped = setmetatable({ module = self, quote = sig, fn = fn, c_sig = c_sig }, CompiledFunction)
    self.functions[name] = wrapped
    return wrapped
end
function CompiledModule:free() if self.artifact then self.artifact:free(); self.artifact = nil end end
function CompiledModule:__tostring() return "CompiledMoonliftModule" end

function CompiledFunction:__call(...)
    if not self.module or not self.module.artifact then error("compiled Moonlift function called after artifact was freed", 2) end
    return self.fn(...)
end
function CompiledFunction:free() if self.owns_module and self.module then self.module:free(); self.module = nil end end
function CompiledFunction:__tostring() return "CompiledMoonliftFunction(" .. self.quote.name .. ": " .. self.c_sig .. ")" end

function M.compile_chunk(src, chunk_name, runtime)
    runtime = runtime or M.new_runtime({ name = chunk_name })
    local lua_src = M.translate(src, chunk_name)
    local q = Quote()
    local host = q:val(runtime, "moonlift_host")
    q("return function(...)")
    q("local __moonlift_host = %s", host)
    q:block(lua_src)
    q("end")
    return q:compile(chunk_name or "=(moonlift.host_quote)"), runtime
end

function M.load(src, chunk_name)
    return M.compile_chunk(src, chunk_name)
end

function M.load_with_runtime(src, chunk_name)
    return M.compile_chunk(src, chunk_name)
end

function M.eval(src, chunk_name, ...)
    local chunk = M.compile_chunk(src, chunk_name)
    return chunk(...)
end

function M.eval_with_runtime(src, chunk_name, ...)
    local chunk, runtime = M.compile_chunk(src, chunk_name)
    return runtime, chunk(...)
end

function M.loadfile(path)
    local f, err = io.open(path, "rb"); if not f then error(err, 2) end
    local src = f:read("*a"); f:close()
    return M.compile_chunk(src, "@" .. path)
end

function M.loadfile_with_runtime(path)
    local f, err = io.open(path, "rb"); if not f then error(err, 2) end
    local src = f:read("*a"); f:close()
    return M.compile_chunk(src, "@" .. path)
end

function M.dofile(path, ...)
    return M.loadfile(path)(...)
end

return M
