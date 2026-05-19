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
-- MUST be declared before make_quote (LuaJIT upvalue capture quirk)

local CallableFunc

-- ── Helper: create a quoting entry point ──────────────────────────────────────

local function make_quote(parse_fn, wrap_fn, expand_fn)
    return setmetatable({}, {
        __call = function(_, arg)
            if type(arg) == "string" then
                -- Pure quote: moon.XXX[[src]]
                local T = default_session.T
                local parsed = parse_fn(T, arg)
                if #parsed.issues ~= 0 then error(parsed.issues[1].message, 2) end
                if #parsed.splice_slots ~= 0 then
                    error("moon.XXX[[]] does not evaluate @{}; use moon.XXX{values}[[src]] instead", 2)
                end
                return wrap_fn(parsed.value, parsed, T)
            end
            if type(arg) == "table" then
                -- Values binder: moon.XXX{values} returns a quote function
                local has_str_keys = false
                for k in pairs(arg) do
                    if type(k) == "string" then has_str_keys = true; break end
                end
                if not has_str_keys then return arg end  -- pass-through for table builders
                local bound_values = {}
                for k, v in pairs(arg) do bound_values[k] = v end
                return function(src)
                    local T = default_session.T
                    local parsed = parse_fn(T, src)
                    if #parsed.issues ~= 0 then error(parsed.issues[1].message, 2) end
                    if #parsed.splice_slots == 0 then return wrap_fn(parsed.value, parsed, T) end
                    local hs = require("moonlift.host_splice")
                    local open_expand = require("moonlift.open_expand")
                    local bindings = {}
                    for _, ss in ipairs(parsed.splice_slots) do
                        local key = ss.splice_text or ss.splice_id
                        local v = bound_values[key]
                        if v == nil then
                            error("no value bound for @" .. tostring(key) .. " in values table", 2)
                        end
                        local binding = hs.fill(default_session, ss.slot, v,
                            "splice " .. ss.splice_id, ss.role, ss.spread)
                        bindings[#bindings + 1] = binding
                    end
                    local e = open_expand.Define(T)
                    local env = e.empty_env()
                    env = e.env_with_fills(env, bindings)
                    local expanded = expand_fn(e, parsed.value, env)
                    local result = wrap_fn(expanded, parsed, T)
                    -- Attach deps for lazy compilation in CallableFunc:__call
                    if type(result) == "table" then
                        local mt = getmetatable(result)
                        if mt == CallableFunc then
                            result._dep_values = bound_values
                        end
                    end
                    return result
                end
            end
            error("moon.XXX expects a string [[]] or table {}", 2)
        end,
    })
end

CallableFunc = {}
CallableFunc.__index = CallableFunc

function CallableFunc:__call(...)
    if not self._compiled then
        local api = self._api
        local m = api.module(self.name .. "_auto")

        -- Register dependency values as module items so the typechecker
        -- can resolve cross-function @{} name references.
        if self._dep_values then
            for _, value in pairs(self._dep_values) do
                local kind = rawget(value, "kind")
                if kind == "func" or kind == "extern_func" then
                    m:add_func(value)
                elseif kind == "region_frag" or rawget(value, "moonlift_quote_kind") == "region_frag" then
                    m:add_region(value)
                elseif kind == "struct" or kind == "union" then
                    m:add_type(value)
                end
            end
        end

        m:add_func(self)
        local compiled = m:compile()
        self._compiled = compiled
        self._fn = compiled:get(self.name)
    end
    return self._fn(...)
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

M.params = api.params
M.fields = api.fields
M.variants = api.variants
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

M.func = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_func(src) end,
    function(value, parsed, T)
        local pvm = require("moonlift.pvm")
        local Tr = T.MoonTree
        -- Accept both raw FuncLocal and expanded ItemFunc
        local func_val = value
        if pvm.classof(value) == Tr.ItemFunc then
            func_val = value.func
        end
        if pvm.classof(func_val) == Tr.FuncLocal then
            local params = {}
            for i = 1, #(func_val.params or {}) do
                local p = func_val.params[i]
                params[i] = setmetatable({ kind = "param", name = p.name,
                    type = api.type_from_asdl(p.ty, p.name), decl = p }, {})
            end
            return setmetatable({ kind = "func", session = default_session, name = func_val.name,
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
        local rfv = api.CanonicalRegionFragValue or {}
        return setmetatable({ kind = "region_frag", moonlift_quote_kind = "region_frag",
            session = default_session, name = value.name, frag = value, conts = {},
            params = {}, blocks = {} }, rfv)
    end,
    function(e, value, env)
        local pvm = require("moonlift.pvm")
        local g, p, c = e.expand_open_set(value, env)
        return pvm.one(g, p, c)
    end
)

M.expr_frag = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_expr_frag(src) end,
    function(value, parsed)
        return setmetatable({ kind = "expr_frag", moonlift_quote_kind = "expr_frag",
            name = value.name, frag = value, params = {} },
            require("moonlift.host_values").ExprFragValue or {})
    end,
    function(e, value, env)
        local pvm = require("moonlift.pvm")
        local g, p, c = e.expand_open_set(value, env)
        return pvm.one(g, p, c)
    end
)

M.struct = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_struct(src) end,
    function(value, parsed)
        local name = value.name or "_anon"
        local ty = api.path_named(name)
        return setmetatable({ kind = "struct", session = default_session, name = name,
            fields = {}, fields_by_name = {}, decl = value.decl, type = ty }, api.StructValue or {})
    end,
    function(e, value, env)
        local pvm = require("moonlift.pvm")
        local g, p, c = e.expand_type_decl(value, env)
        return pvm.one(g, p, c)
    end
)

M.union = make_quote(
    function(T, src) return require("moonlift.parse").Define(T).parse_union(src) end,
    function(value, parsed)
        local name = value.name or "_anon"
        local ty = api.path_named(name)
        return setmetatable({ kind = "union", session = default_session, name = name,
            decl = value.decl, type = ty }, api.StructValue or {})
    end,
    function(e, value, env)
        local pvm = require("moonlift.pvm")
        local g, p, c = e.expand_type_decl(value, env)
        return pvm.one(g, p, c)
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

-- ── Module builder ────────────────────────────────────────────────────────────
-- M.module = api.module  (already available via M = api)

return M
