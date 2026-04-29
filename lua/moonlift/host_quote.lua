-- Clean hosted .mlua bridge.
--
-- `.mlua` is an ordinary LuaJIT chunk with a small number of Moonlift source
-- islands.  This module does not parse Lua.  It only lexically finds the added
-- island forms and rewrites them to ordinary Lua calls; LuaJIT owns everything
-- else.
--
-- Moonlift meaning still flows through ASDL/PVM phases:
--   hosted island text -> MoonHost / MoonTree ASDL -> existing phases.

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Quote = require("moonlift.quote")

local M = {}

local FuncQuote = {}; FuncQuote.__index = FuncQuote
local ModuleQuote = {}; ModuleQuote.__index = ModuleQuote
local RegionFragValue = {}; RegionFragValue.__index = RegionFragValue
local ExprFragValue = {}; ExprFragValue.__index = ExprFragValue
local SourceChunk = {}; SourceChunk.__index = SourceChunk
local StructDeclValue = {}; StructDeclValue.__index = StructDeclValue
local ExposeDeclValue = {}; ExposeDeclValue.__index = ExposeDeclValue
local TypedSplice = {}; TypedSplice.__index = TypedSplice
local TypeValue = {}; TypeValue.__index = TypeValue
local CompiledFunction = {}; CompiledFunction.__index = CompiledFunction
local CompiledModule = {}; CompiledModule.__index = CompiledModule
local HostRuntime = {}; HostRuntime.__index = HostRuntime

local function starts_ident_char(c)
    return c and c:match("[%w_]") ~= nil
end

local function is_boundary(src, i, n)
    local before = i > 1 and src:sub(i - 1, i - 1) or ""
    local after = src:sub(i + n, i + n)
    return not starts_ident_char(before) and not starts_ident_char(after)
end

local function has_word(src, i, word)
    return src:sub(i, i + #word - 1) == word and is_boundary(src, i, #word)
end

local function skip_space(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then break end
        i = i + 1
    end
    return i
end

local function skip_hspace(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" then break end
        i = i + 1
    end
    return i
end

local function read_ident(src, i)
    if not src:sub(i, i):match("[A-Za-z_]") then return nil, i end
    local s = i
    i = i + 1
    while i <= #src and src:sub(i, i):match("[%w_]") do i = i + 1 end
    return src:sub(s, i - 1), i
end

local function lua_string_literal(s)
    return string.format("%q", s)
end

local function skip_string(src, i, quote)
    i = i + 1
    while i <= #src do
        local c = src:sub(i, i)
        if c == "\\" then i = i + 2
        elseif c == quote then return i + 1
        else i = i + 1 end
    end
    return i
end

local function skip_long_bracket(src, i)
    local eq = src:match("^%[(=*)%[", i)
    if not eq then return nil end
    local close = "]" .. eq .. "]"
    local j = src:find(close, i + 2 + #eq, true)
    return j and (j + #close) or (#src + 1)
end

local function skip_comment_or_string(src, i)
    local c = src:sub(i, i)
    local n = src:sub(i, i + 1)
    if n == "--" then
        local lb = skip_long_bracket(src, i + 2)
        if lb then return lb end
        local j = src:find("\n", i + 2, true)
        return j or (#src + 1)
    end
    if c == '"' or c == "'" then return skip_string(src, i, c) end
    if c == "[" then return skip_long_bracket(src, i) end
    return nil
end

local open_words = {
    struct = true, expose = true, func = true, module = true, region = true, expr = true,
    ["if"] = true, switch = true, block = true, entry = true, control = true,
}

local function line_prefix_has_word(src, i, word)
    local line_start = src:sub(1, i - 1):match(".*\n()") or 1
    local prefix = src:sub(line_start, i - 1)
    return prefix:match("%f[%w_]" .. word .. "%f[^%w_]") ~= nil
end

local function find_matching_end(src, start_i)
    local depth, i = 0, start_i
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        elseif src:sub(i, i):match("[A-Za-z_]") then
            local word, j = read_ident(src, i)
            if is_boundary(src, i, #word) then
                if word == "end" then
                    depth = depth - 1
                    if depth == 0 then return j - 1 end
                elseif open_words[word] then
                    depth = depth + 1
                elseif word == "do" then
                    if not line_prefix_has_word(src, i, "switch") then depth = depth + 1 end
                elseif word == "loop" then
                    local next_word = read_ident(src, skip_space(src, j))
                    if next_word == "counted" then depth = depth + 1 end
                end
            end
            i = j
        else
            i = i + 1
        end
    end
    error("unterminated hosted Moonlift island", 2)
end

local function is_island_start(src, i, kind)
    if not has_word(src, i, kind) then return false end
    local j = skip_space(src, i + #kind)
    if kind == "struct" or kind == "func" or kind == "region" or kind == "expr" then
        return read_ident(src, j) ~= nil
    end
    if kind == "expose" then
        return read_ident(src, j) ~= nil
    end
    if kind == "module" then
        local item_words = { export = true, extern = true, func = true, const = true, static = true, import = true, type = true, region = true, expr = true, ["end"] = true }
        local p = i - 1
        while p >= 1 do
            local c = src:sub(p, p)
            if c ~= " " and c ~= "\t" and c ~= "\r" then break end
            p = p - 1
        end
        local prev = p >= 1 and src:sub(p, p) or "\n"
        local word_end = p
        while p >= 1 and src:sub(p, p):match("[%w_]") do p = p - 1 end
        local prev_word = word_end >= p + 1 and src:sub(p + 1, word_end) or ""
        local from_return = prev_word == "return"
        local prefix_ok = prev == "\n" or prev == "="
        if not prefix_ok and not from_return then return false end
        local k = skip_hspace(src, i + #kind)
        local ch = src:sub(k, k)
        if ch == "" then return prefix_ok end
        if ch == "\n" then
            if not from_return then return true end
            local next_word = read_ident(src, skip_space(src, k + 1))
            return item_words[next_word] == true
        end
        local word, after_word = read_ident(src, k)
        if not word then return false end
        if item_words[word] then return true end
        local next_i = skip_hspace(src, after_word)
        local next_ch = src:sub(next_i, next_i)
        if from_return then return next_ch == "\n" end
        return next_ch == "" or next_ch == "\n"
    end
    return false
end

local island_order = { "struct", "expose", "func", "module", "region", "expr" }

local function find_next_island(src, i)
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        else
            for k = 1, #island_order do
                local kind = island_order[k]
                if is_island_start(src, i, kind) then return i, kind end
            end
            i = i + 1
        end
    end
    return nil, nil
end

local function island_end(src, start_i, kind)
    if kind == "expose" then
        local nl = src:find("\n", start_i, true)
        if not nl then return #src end
        local next_word = read_ident(src, skip_space(src, nl + 1))
        if next_word == "end" or next_word == "lua" or next_word == "terra" or next_word == "c" or next_word == "moonlift" then
            return find_matching_end(src, start_i)
        end
        return nl - 1
    end
    return find_matching_end(src, start_i)
end

local function assigned_name_before_quote(prefix)
    return prefix:match("([_%a][_%w]*)%s*=%s*$")
end

local function normalize_method_func_source(src)
    local prefix, owner, method_name, rest = src:match("^%s*(export%s+)func%s+([_%a][_%w]*)%s*:%s*([_%a][_%w]*)(.*)$")
    if not owner then prefix, owner, method_name, rest = "", src:match("^%s*func%s+([_%a][_%w]*)%s*:%s*([_%a][_%w]*)(.*)$") end
    if not owner then return src, nil, nil end
    return (prefix or "") .. "func " .. owner .. "_" .. method_name .. rest, owner, method_name
end

local function module_body_from_source(src)
    local body = src:match("^%s*module%s+([%s%S]-)%s*end%s*$")
    if not body then return src end
    local maybe_name, rest = body:match("^%s*([_%a][_%w]*)([%s%S]*)$")
    if maybe_name and not ({ export = true, extern = true, func = true, const = true, static = true, import = true, type = true, region = true, expr = true, ["end"] = true })[maybe_name] then
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

local function source_expr_with_antiquotes(src, known_frag_vars)
    known_frag_vars = known_frag_vars or {}
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
        elseif has_word(src, i, "emit") then
            local j = skip_space(src, i + 4)
            local name, after_name = read_ident(src, j)
            if name and known_frag_vars[name] then
                if literal_start < j then parts[#parts + 1] = lua_string_literal(src:sub(literal_start, j - 1)) end
                parts[#parts + 1] = typed_splice_expr(name, known_frag_vars[name])
                i = after_name
                literal_start = i
            else
                i = i + 4
            end
        else
            i = i + 1
        end
    end
    if literal_start <= #src then parts[#parts + 1] = lua_string_literal(src:sub(literal_start)) end
    if #parts == 0 then parts[1] = lua_string_literal("") end
    return "__moonlift_host.source({" .. table.concat(parts, ", ") .. "})"
end

local function translate_island(kind, source, assigned, known_frag_vars)
    if kind == "struct" then
        local name = assert(source:match("^%s*struct%s+([_%a][_%w]*)"), "struct island without name")
        return "local " .. name .. " = __moonlift_host.struct_from_source(" .. source_expr_with_antiquotes(source, known_frag_vars) .. ")"
    end
    if kind == "expose" then
        local name = source:match("^%s*expose%s+([_%a][_%w]*)%s*:")
        assert(name, "expected expose Name: subject")
        return "local " .. name .. " = __moonlift_host.expose_from_source(" .. source_expr_with_antiquotes(source, known_frag_vars) .. ")"
    end
    if kind == "func" then
        local _, owner, method_name = normalize_method_func_source(source)
        local expr = "__moonlift_host.func_from_source(" .. source_expr_with_antiquotes(source, known_frag_vars) .. ")"
        if owner and not assigned then return owner .. "." .. method_name .. " = " .. expr end
        return expr
    end
    if kind == "module" then
        return "__moonlift_host.module_from_source(" .. source_expr_with_antiquotes(module_body_from_source(source), known_frag_vars) .. ")"
    end
    if kind == "region" then
        if assigned then known_frag_vars[assigned] = "region" end
        return "__moonlift_host.region_from_source(" .. source_expr_with_antiquotes(source, known_frag_vars) .. ")"
    end
    if kind == "expr" then
        if assigned then known_frag_vars[assigned] = "expr" end
        return "__moonlift_host.expr_from_source(" .. source_expr_with_antiquotes(source, known_frag_vars) .. ")"
    end
    error("unknown hosted island kind: " .. tostring(kind), 2)
end

function M.translate(src)
    local out = {}
    local known_frag_vars = {}
    local i = 1
    while i <= #src do
        local f, kind = find_next_island(src, i)
        if not f then out[#out + 1] = src:sub(i); break end
        local prefix = src:sub(i, f - 1)
        out[#out + 1] = prefix
        local e = island_end(src, f, kind)
        local source = src:sub(f, e)
        out[#out + 1] = translate_island(kind, source, assigned_name_before_quote(prefix), known_frag_vars)
        i = e + 1
    end
    return table.concat(out)
end

local function merge_splices(dst, src)
    for k, v in pairs(src or {}) do dst[k] = v end
end

local function normalize_source(src)
    if getmetatable(src) == SourceChunk then return src.source, src.region_frags, src.expr_frags end
    return src, {}, {}
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
        if mt == RegionFragValue then return "region" end
        if mt == ExprFragValue then return "expr" end
        if mt == SourceChunk then return "source" end
        if mt == TypeValue or mt == StructDeclValue then return "type" end
        if mt and mt.__moon2_host_type_value == true then return "type" end
        if type(v.as_moon2_type) == "function" or type(v.as_type_value) == "function" then return "type" end
        if (mt and mt.__moonlift_splice_source) or type(v.moonlift_splice_source) == "function" then return "source" end
    end
    return tv
end

local function splice_kind_matches(actual, expected)
    if expected == nil or expected == "any" then return true end
    if expected == "emit" then return actual == "region" or actual == "expr" end
    return actual == expected
end

function M.splice_checked(v, expected)
    if getmetatable(v) == TypedSplice then expected = v.expected or expected; v = v.value end
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
    if tv == "string" then return lua_string_literal(v) end
    if tv == "table" or tv == "userdata" then
        local mt = getmetatable(v)
        if mt == TypedSplice then return M.splice_checked(v) end
        if mt and mt.__moonlift_splice_source then return mt.__moonlift_splice_source(v) end
        if type(v.moonlift_splice_source) == "function" then return v:moonlift_splice_source() end
    end
    error("cannot splice Lua value of type " .. tv .. " into Moonlift source", 2)
end

local function append_source_part(out, region_frags, expr_frags, part, expected)
    if type(part) == "table" and getmetatable(part) == nil and #part == 1 then part = part[1] end
    if getmetatable(part) == TypedSplice then return append_source_part(out, region_frags, expr_frags, part.value, part.expected or expected) end
    if type(part) == "string" and expected == nil then
        out[#out + 1] = part
        return
    end
    local mt = getmetatable(part)
    out[#out + 1] = M.splice_checked(part, expected)
    if mt == SourceChunk then
        merge_splices(region_frags, part.region_frags); merge_splices(expr_frags, part.expr_frags)
    elseif mt == RegionFragValue then
        merge_splices(region_frags, part.region_frags); region_frags[part.name] = part; merge_splices(expr_frags, part.expr_frags)
    elseif mt == ExprFragValue then
        expr_frags[part.name] = part
    end
end

function M.source(parts)
    local out, region_frags, expr_frags = {}, {}, {}
    for i = 1, #parts do append_source_part(out, region_frags, expr_frags, parts[i], nil) end
    return setmetatable({ source = table.concat(out), region_frags = region_frags, expr_frags = expr_frags }, SourceChunk)
end

function SourceChunk:moonlift_splice_source() return self.source end
function SourceChunk:__tostring() return self.source end

function TypeValue:moonlift_splice_source() return self.source end
function TypeValue:__tostring() return "MoonliftType(" .. self.source .. ")" end

function M.type(source)
    assert(type(source) == "string" and source ~= "", "Moonlift type source must be a non-empty string")
    return setmetatable({ source = source }, TypeValue)
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
    return require("moonlift.mlua_source_normalize").moonlift_body(src)
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
    local body = src:match("^%s*module%s+([%s%S]-)%s*end%s*$")
    if not body then return src end
    local maybe_name, rest = body:match("^%s*([_%a][_%w]*)([%s%S]*)$")
    if maybe_name and not ({ export = true, extern = true, func = true, const = true, static = true, import = true, type = true, region = true, expr = true, ["end"] = true })[maybe_name] then
        body = rest
    end
    return body
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

local function compile_module_source(src, region_frags, expr_frags)
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
    for name, frag_value in pairs(expr_frags or {}) do
        local parsed = P.parse_expr_frag(frag_value.source)
        if #parsed.issues ~= 0 then error("host expr parse failed: " .. tostring(parsed.issues[1]), 2) end
        parsed_expr_frags[name] = parsed.value
    end

    local parsed_region_frags, pending = {}, {}
    for name, frag_value in pairs(region_frags or {}) do pending[name] = frag_value end
    while next(pending) do
        local progressed, last_issue = false, nil
        for name, frag_value in pairs(pending) do
            local parsed = P.parse_region_frag(frag_value.source, { expr_frags = parsed_expr_frags, region_frags = parsed_region_frags })
            if #parsed.issues == 0 then
                parsed_region_frags[name] = parsed.value; pending[name] = nil; progressed = true
            else
                last_issue = parsed.issues[1]
            end
        end
        if not progressed then error("host region parse failed: " .. tostring(last_issue), 2) end
    end

    local parsed = P.parse_module(normalize_moonlift_body(src), { region_frags = parsed_region_frags, expr_frags = parsed_expr_frags })
    if #parsed.issues ~= 0 then error("host module parse failed: " .. tostring(parsed.issues[1]), 2) end
    local expanded = OE.module(parsed.module)
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
    local source, region_frags, expr_frags = normalize_source(src)
    local normalized, owner_name, method_name = normalize_method_func_source(source)
    normalized = normalize_moonlift_body(normalized)
    local sig = parse_signature(normalized)
    return setmetatable({ source = normalized, region_frags = region_frags, expr_frags = expr_frags, name = sig.name, params = sig.params, result = sig.result, owner_name = owner_name, method_name = method_name }, FuncQuote)
end

local function extract_module_local_frags(source, region_frags, expr_frags)
    local out, i = {}, 1
    while i <= #source do
        local skipped = skip_comment_or_string(source, i)
        if skipped then
            out[#out + 1] = source:sub(i, skipped - 1); i = skipped
        elseif is_island_start(source, i, "region") or is_island_start(source, i, "expr") then
            local kind = is_island_start(source, i, "region") and "region" or "expr"
            local e = island_end(source, i, kind)
            local form = source:sub(i, e)
            if kind == "region" then
                local name = assert(form:match("^%s*region%s+([_%a][_%w]*)"), "module-local region name")
                region_frags[name] = setmetatable({ name = name, source = form, region_frags = {}, expr_frags = {} }, RegionFragValue)
            else
                local name = assert(form:match("^%s*expr%s+([_%a][_%w]*)"), "module-local expr name")
                expr_frags[name] = setmetatable({ name = name, source = form }, ExprFragValue)
            end
            out[#out + 1] = "\n"; i = e + 1
        else
            out[#out + 1] = source:sub(i, i); i = i + 1
        end
    end
    return table.concat(out), region_frags, expr_frags
end

function M.module_from_source(src)
    local source, region_frags, expr_frags = normalize_source(src)
    source = module_item_source(source)
    source, region_frags, expr_frags = extract_module_local_frags(source, region_frags, expr_frags)
    return setmetatable({ source = source, region_frags = region_frags, expr_frags = expr_frags, signatures = parse_module_signatures(source) }, ModuleQuote)
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
    local source, region_frags, expr_frags = normalize_source(src)
    local name = assert(source:match("^%s*region%s+([_%a][_%w]*)"), "host region quote: expected `region name(...)`")
    return setmetatable({ name = name, source = source, region_frags = region_frags, expr_frags = expr_frags }, RegionFragValue)
end

function M.expr_from_source(src)
    local source = normalize_source(src)
    local name = assert(source:match("^%s*expr%s+([_%a][_%w]*)"), "host expr quote: expected `expr name(...)`")
    return setmetatable({ name = name, source = source }, ExprFragValue)
end

function FuncQuote:module_source() return export_func_source(self.source) end
function FuncQuote:compile()
    local m = M.module_from_source(setmetatable({ source = self:module_source(), region_frags = self.region_frags or {}, expr_frags = self.expr_frags or {} }, SourceChunk)):compile()
    local f = m:get(self.name); f.owns_module = true; return f
end
function FuncQuote:__tostring() return "MoonliftFuncQuote(" .. self.name .. ")" end

function ModuleQuote:compile()
    local artifact, T = compile_module_source(self.source, self.region_frags, self.expr_frags)
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
    local lua_src = M.translate(src)
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
