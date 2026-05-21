-- Unified moon.XXX metaprogramming API.
--
-- Every moon.XXX is either:
--   moon.XXX[[]]     — pure quote (no @{}), returns typed ASDL
--   moon.XXX{values} — values binder (string keys), returns function(src)
--   moon.XXX{array}  — table builder (integer keys), returns ASDL array
--
-- The function(b) builder pattern has been retired.

local Session = require("moonlift.host_session")

local default_session = Session.new({ prefix = "default" })
local api = default_session:api()
local M = api
M.default_session = default_session
M.region_compose = require("moonlift.region_compose")

function M.new_session(opts)
    return Session.new(opts)
end

function M.session(opts)
    return Session.new(opts)
end

function M.classify_type(ty, ...)
    return default_session:classify_type(ty, ...)
end

function M.size_align(ty, env)
    return default_session:size_align(ty, env)
end

function M.abi_of(ty, env)
    return default_session:abi_of(ty, env)
end

function M.layout_of(ty)
    return default_session:layout_of(ty)
end

-- ── Callable function — lazy compile on first call ────────────────────────

local CallableFunc = {}
CallableFunc.__index = CallableFunc

-- ── moon.chain: imported from chain.lua ──────────────────────────────────────
local chain_mod = require("moonlift.chain")
local chain_binding = chain_mod.bind(default_session, CallableFunc)
local make_chain = chain_binding.make
local make_quote = chain_binding.make_quote

function CallableFunc:compile(opts)
    if not self._compiled then
        local api = self._api
        local b = api.bundle(self.name .. "_auto")

        -- Register dependency values as bundle items so the typechecker
        -- can resolve cross-function @{} name references.
        if self._dep_values then
            for _, value in pairs(self._dep_values) do
                local kind = rawget(value, "kind")
                if kind == "func" or kind == "extern_func" then
                    b:pack(value)
                elseif kind == "region_frag" or rawget(value, "moonlift_quote_kind") == "region_frag" then
                    b:pack(value)
                elseif kind == "struct" or kind == "union" then
                    b:pack(value)
                end
            end
        end

        b:pack(self)
        local artifact = b:jit(opts or {})
        self._compiled = artifact
        self._fn = artifact:get(self.name)
    end
    return self._fn
end

function CallableFunc:__call(...)
    return self:compile()(...)
end

function CallableFunc:free()
    if self._compiled then
        self._compiled:free()
        self._compiled = nil
        self._fn = nil
    end
end

-- ── Scalar types ──────────────────────────────────────────────────────────────

M.void = api.void; M.bool = api.bool

-- ── The universal applicative primitive ────────────────────────────────────────
-- Every moon.XXX is an instance of moon.chain. Users can define their own:
--   my_api = moon.chain { name = "my_api", parse = ..., wrap = ... }
M.chain = make_chain

M.i8 = api.i8; M.i16 = api.i16; M.i32 = api.i32; M.i64 = api.i64
M.u8 = api.u8; M.u16 = api.u16; M.u32 = api.u32; M.u64 = api.u64
M.f32 = api.f32; M.f64 = api.f64; M.index = api.index; M.rawptr = api.rawptr

-- ── Compound type constructors ────────────────────────────────────────────────

M.ptr = api.ptr; M.view = api.view; M.named = api.named; M.path_named = api.path_named
M.func_type = api.func_type; M.closure_type = api.closure_type
M.array_type = api.array; M.slice = api.slice

-- ── Expression constructors ───────────────────────────────────────────────────

M.int = api.int; M.float = api.float; M.bool_lit = api.bool_lit; M.string_lit = api.string_lit
M.nil_lit = api.nil_lit; M.ref = api.ref; M.select = api.select
M.load = api.load; M.addr_of = api.addr_of; M.len = api.len
M.atomic_load = api.atomic_load; M.atomic_store = api.atomic_store
M.atomic_rmw = api.atomic_rmw; M.atomic_cas = api.atomic_cas; M.atomic_fence = api.atomic_fence

-- ── Table builders (data-shaped things) ───────────────────────────────────────
-- Installed after make_quote helpers below so builders also support [[]] and
-- {bindings}[[]] quote forms.

M.conts = api.conts
M.blocks = api.blocks
M.entry_params = api.entry_params

-- ── Quotes (code-shaped things) ───────────────────────────────────────────────

M.type = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_type(src) end,
    function(value) return api.type_from_asdl(value, "moon.type quote") end,
    function(e, value, env) return e.type(value, env) end
)

M.expr = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_expr(src) end,
    function(value) return api.expr_from_asdl(value, nil, "moon.expr quote") end,
    function(e, value, env) return e.expr(value, env) end
)

local function typed_list_parse_error(prefix, parsed)
    if parsed and parsed.issues and #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
    error(prefix .. " parse failed", 3)
end

local function parse_params_quote(T, src)
    local P = require("moonlift.parse").Define(T)
    local parsed = P.parse_func("func __moon_params(" .. src .. ") end")
    if not parsed.value then typed_list_parse_error("params", parsed) end
    return parsed
end

local function wrap_params_quote(value)
    local out = {}
    for i = 1, #(value.params or {}) do
        local p = value.params[i]
        out[i] = api.param(p.name, api.type_from_asdl(p.ty, p.name))
    end
    return out
end

local function expand_params_quote(e, value, env)
    local pvm = require("moonlift.pvm")
    local Tr = default_session.T.MoonTree
    local result = pvm.one(e.item_stream(Tr.ItemFunc(value), env))
    local item = result.items and result.items[1]
    return item and item.func or value
end

local function parse_fields_quote(T, src)
    local P = require("moonlift.parse").Define(T)
    local parsed = P.parse_struct("struct __moon_fields\n" .. src .. "\nend")
    if not parsed.value then typed_list_parse_error("fields", parsed) end
    return parsed
end

local function wrap_fields_quote(value)
    local decl = value.decl or value
    local out = {}
    for i = 1, #(decl.fields or {}) do
        local f = decl.fields[i]
        out[i] = api.field(f.field_name, api.type_from_asdl(f.ty, f.field_name))
    end
    return out
end

local function expand_fields_quote(e, value, env)
    return { name = value.name, decl = e.expand_type_decl(value.decl or value, env) }
end

local function parse_variants_quote(T, src)
    local P = require("moonlift.parse").Define(T)
    local parsed = P.parse_union("union __moon_variants\n" .. src .. "\nend")
    if not parsed.value then typed_list_parse_error("variants", parsed) end
    return parsed
end

local function wrap_variants_quote(value)
    local decl = value.decl or value
    local out = {}
    for i = 1, #(decl.variants or {}) do
        local v = decl.variants[i]
        local fields = v.fields or {}
        if #fields > 0 then
            out[i] = { kind = "variant", name = v.name, payload = nil, fields = fields, decl = v }
        else
            out[i] = api.variant(v.name, api.type_from_asdl(v.payload, v.name))
        end
    end
    return out
end

local function expand_variants_quote(e, value, env)
    return { name = value.name, decl = e.expand_type_decl(value.decl or value, env) }
end

-- exits: same union parser, but wraps into ExitProtocol instead of variant array
local function parse_exits_quote(T, src)
    return parse_variants_quote(T, src)  -- same grammar: ok(i32) | err(i64)
end

local function wrap_exits_quote(value)
    local decl = value.decl or value
    local exits = wrap_variants_quote(value)  -- [{kind="variant", name, type}, ...]
    -- Re-key variant values into exit values
    for i = 1, #exits do
        local v = exits[i]
        exits[i] = { kind = "exit", name = v.name, ty = v.type or v.payload, fields = v.fields, decl = v.decl }
    end
    return setmetatable({ kind = "exit_protocol", exits = exits, _owner = "exits" }, { __index = api.ExitProtocol })
end

local function expand_exits_quote(e, value, env)
    return e.expand_type_decl(value.decl or value, env)
end

M.params = make_quote(parse_params_quote, wrap_params_quote, expand_params_quote, api.params)
M.fields = make_quote(parse_fields_quote, wrap_fields_quote, expand_fields_quote, api.fields)
M.variants = make_quote(parse_variants_quote, wrap_variants_quote, expand_variants_quote, api.variants)
M.exits = make_quote(parse_exits_quote, wrap_exits_quote, expand_exits_quote, api.exits)

local function parse_switch_arms_quote(T, src)
    -- Switch-arm keys are backend raw keys; keep the builder source-shaped but
    -- require concrete keys here.  Generated dynamic keys are better expressed
    -- with table form: moon.switch_arms { {key, body}, ... }.
    if src:find("@{", 1, true) then
        error("moon.switch_arms[[]] does not support @{} in case keys; use table form for generated keys", 3)
    end
    local P = require("moonlift.parse").Define(T)
    local parsed = P.parse_stmts("switch __moon_key do\n" .. src .. "\ndefault then\nend")
    if parsed.issues and #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
    return parsed
end

local function wrap_switch_arms_quote(value)
    local pvm = require("moonlift.pvm")
    local Tr = default_session.T.MoonTree
    local sw = value and value[1]
    if pvm.classof(sw) ~= Tr.StmtSwitch then return {} end
    local out = {}
    for i = 1, #sw.arms do out[i] = sw.arms[i] end
    return out
end

local function expand_switch_arms_quote(e, value, env)
    return e.stmts(value, env)
end

M.switch_arms = make_quote(parse_switch_arms_quote, wrap_switch_arms_quote, expand_switch_arms_quote, api.switch_arms)

M.func = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_func(src) end,
    function(value, parsed, T, src, bindings)
        local pvm = require("moonlift.pvm")
        local Tr = T.MoonTree
        local function type_name_for(ty)
            return require("moonlift.error.format").type_name(ty)
        end
        local func_val = value
        if pvm.classof(value) == Tr.ItemFunc then
            func_val = value.func
        end
        -- Bodyless func declaration — return a header closure
        if pvm.classof(func_val) == Tr.FuncDecl then
            local params = {}
            for i = 1, #(func_val.params or {}) do
                local p = func_val.params[i]
                params[i] = setmetatable({ kind = "param", name = p.name,
                    type = api.type_from_asdl(p.ty, p.name), decl = p }, {})
            end
            local result_val = api.type_from_asdl(func_val.result, func_val.name)
            local function make_header(sig, bindings, src)
                return setmetatable({
                    kind = "func_header", name = sig.name,
                    params = params, result = result_val,
                    _sig = sig, _bindings = bindings or {}, _src = src,
                }, {
                    __call = function(self, arg)
                        if type(arg) == "string" then
                            -- Body provided: reconstruct full func from sig + body
                            local T2 = default_session.T
                            local pvm2 = require("moonlift.pvm")
                            local Tr2 = T2.MoonTree
                            local merged = self._bindings or {}
                            -- Reconstruct the func signature from the raw header source,
                            -- replacing @{key} with types from merged bindings
                            local sig_src = self._src or (self._sig.name .. "(...)")
                            -- Replace @{key} with type names from merged bindings
                            local function resolve_bindings(s)
                                return (s:gsub("@{(%w+)}", function(k)
                                    local v = merged[k]
                                    if v then
                                        local ty = type(v) == "table" and (v.ty or v) or v
                                        return require("moonlift.error.format").type_name(ty)
                                    end
                                    return "@{" .. k .. "}"
                                end))
                            end
                            -- Add "func" prefix if not present in the source
                            local header_src = resolve_bindings(sig_src)
                            if not header_src:match("^func") then
                                header_src = "func " .. header_src
                            end
                            local full = header_src .. "\n" .. arg .. "\nend"
                            local res = require("moonlift.parse").Define(T2).parse_func(full)
                            local fv = res.value or res
                            if pvm2.classof(fv) == Tr2.ItemFunc then fv = fv.func end
                            -- Build params from the COMPILED FuncLocal (fv) — these have the overridden types
                            local new_params = {}
                            local new_result = fv.result
                            for pi = 1, #(fv.params or {}) do
                                local pp = fv.params[pi]
                                new_params[pi] = setmetatable({ kind = "param", name = pp.name,
                                    type = api.type_from_asdl(pp.ty, pp.name), decl = pp }, {})
                            end
                            return setmetatable({ kind = "func", session = default_session, T = T2,
                                name = fv.name, params = new_params, result = api.type_from_asdl(new_result, fv.name),
                                func = fv, item = Tr2.ItemFunc(fv), visibility = "export",
                                _api = api, _session = default_session }, CallableFunc)
                        elseif type(arg) == "table" then
                            -- Bindings override: merge and return new header
                            local merged = {}
                            for k, v in pairs(self._bindings) do merged[k] = v end
                            for k, v in pairs(arg) do merged[k] = v end
                            return make_header(self._sig, merged, self._src)
                        end
                        error("moon.func header expects body string [[]] or binding table {}", 2)
                    end,
                })
            end
            return make_header(func_val, bindings or {}, src)
        end
        local func_cls = pvm.classof(func_val)
        if func_cls == Tr.FuncLocal or func_cls == Tr.FuncExport
           or func_cls == Tr.FuncLocalContract or func_cls == Tr.FuncExportContract then
            local params = {}
            for i = 1, #(func_val.params or {}) do
                local p = func_val.params[i]
                params[i] = setmetatable({ kind = "param", name = p.name,
                    type = api.type_from_asdl(p.ty, p.name), decl = p }, {})
            end
            return setmetatable({ kind = "func", session = default_session, T = T, name = func_val.name,
                params = params, result = api.type_from_asdl(func_val.result, func_val.name),
                func = func_val, item = Tr.ItemFunc(func_val), visibility = "export",
                _api = api, _session = default_session }, CallableFunc)
        end
        error("moon.func[[]] expected a function", 2)
    end,
    function(e, value, env)
        local pvm = require("moonlift.pvm")
        local Tr = default_session.T.MoonTree
        local g, p, c = e.item_stream(Tr.ItemFunc(value), env)
        return pvm.one(g, p, c)
    end
)

M.region = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_region(src) end,
    function(value, parsed)
        local pvm = require("moonlift.pvm")
        local O = default_session.T.MoonOpen
        -- Bodyless region decl — return a header closure
        if pvm.classof(value) == O.RegionFragDecl then
            local header = setmetatable({
                kind = "region_header",
                name = value.name,
                _src_cont = parsed and parsed.src,
                _O = O,
            }, {
                __call = function(self, body_src)
                    if type(body_src) ~= "string" then
                        error("moon.region header expects a body string [[]] or nil", 2)
                    end
                    local T2 = default_session.T
                    local full = body_src
                    local parsed = require("moonlift.parse").Define(T2).parse_region(full)
                    local v = parsed.value or parsed
                    local rfv = api.CanonicalRegionFragValue or {}
                    return setmetatable({ kind = "region_frag", moonlift_quote_kind = "region_frag",
                        session = default_session, name = v.name, frag = v, conts = {},
                        params = {}, blocks = {} }, rfv)
                end,
            })
            return header
        end
        local rfv = api.CanonicalRegionFragValue or {}
        local name = (type(value.name) == "table" and (value.name.text or value.name.name)) or value.name
        return setmetatable({ kind = "region_frag", moonlift_quote_kind = "region_frag",
            session = default_session, name = name, frag = value, conts = {},
            params = {}, blocks = {} }, rfv)
    end,
    function(e, value, env)
        return e.expand_region_frag(value, env)
    end
)

M.expr_frag = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_expr_frag(src) end,
    function(value, parsed)
        local name = (type(value.name) == "table" and (value.name.text or value.name.name)) or value.name
        return setmetatable({ kind = "expr_frag", moonlift_quote_kind = "expr_frag",
            name = name, frag = value, params = {} },
            require("moonlift.host_values").ExprFragValue or {})
    end,
    function(e, value, env)
        return e.expand_expr_frag(value, env)
    end
)

M.struct = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_struct(src) end,
    function(value, parsed, T)
        local name = value.name or "_anon"
        local ty = api.path_named(name)
        return setmetatable({ kind = "struct", session = default_session, name = name,
            fields = {}, fields_by_name = {}, decl = value.decl, item = T.MoonTree.ItemType(value.decl), type = ty }, api.StructValue or {})
    end,
    function(e, value, env)
        return { name = value.name, decl = e.expand_type_decl(value.decl or value, env) }
    end
)

M.union = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_union(src) end,
    function(value, parsed, T)
        local name = value.name or "_anon"
        local ty = api.path_named(name)
        return setmetatable({ kind = "union", session = default_session, name = name,
            decl = value.decl, item = T.MoonTree.ItemType(value.decl), type = ty }, api.StructValue or {})
    end,
    function(e, value, env)
        return { name = value.name, decl = e.expand_type_decl(value.decl or value, env) }
    end
)

M.extern = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_extern(src) end,
    function(value, parsed, T)
        local pvm = require("moonlift.pvm")
        local Tr = T.MoonTree
        local ext_val = value
        if pvm.classof(value) == Tr.ItemExtern then
            ext_val = value.func
        end
        local params = {}
        for i = 1, #(ext_val.params or {}) do
            local p = ext_val.params[i]
            params[i] = setmetatable({ kind = "param", name = p.name,
                type = api.type_from_asdl(p.ty, p.name), decl = p }, {})
        end
        return setmetatable({ kind = "extern_func", session = default_session, visibility = "export",
            name = ext_val.name, func = ext_val, params = params, item = Tr.ItemExtern(ext_val),
            _api = api, _session = default_session }, CallableFunc)
    end,
    function(e, value, env)
        local pvm = require("moonlift.pvm")
        local Tr = default_session.T.MoonTree
        local g, p, c = e.item_stream(Tr.ItemExtern(value), env)
        return pvm.one(g, p, c)
    end
)

-- ── stmts — aliased from api (installed by host_func_values) ─────────────────
-- api.stmts is a table with metatable supporting both [[]] and {} dispatch.
M.stmts = api.stmts

-- ── Bundle builder ────────────────────────────────────────────────────────────
M.bundle = api.bundle

-- ── Control structures (user-defined chains) ───────────────────────────────────
M.control = require("moonlift.control").build(default_session, chain_binding)

return M
