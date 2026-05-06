-- Canonical hosted value handles.
--
-- This module is the new ASDL-first boundary for hosted values.  It does not
-- parse source and it does not concatenate source.  It wraps existing ASDL
-- values with Lua reflection metadata and registers stable HostValueRefs in the
-- active HostSession.

local pvm = require("moonlift.pvm")

local M = {}

local RegionFragValue = {}
RegionFragValue.__index = RegionFragValue

local ExprFragValue = {}
ExprFragValue.__index = ExprFragValue

local SourceValue = {}
SourceValue.__index = SourceValue

local NilSpliceValue = {
    kind = "source",
    moonlift_quote_kind = "source",
    source = "nil",
}
function NilSpliceValue:moonlift_splice_source() return "nil" end

local function classof(v) return pvm.classof(v) end

local function assert_same_context(session, node, site)
    -- ASDL nodes do not currently expose their owning context.  Keep this as a
    -- single choke point so strict context tagging can be added later without
    -- rewriting host/composition code.
    if type(node) ~= "table" or not classof(node) then
        error((site or "host value") .. ": expected ASDL node", 3)
    end
end

local function list_to_name_map(list)
    local out = {}
    for i = 1, #(list or {}) do
        local v = list[i]
        out[v.name or v.pretty_name or tostring(i)] = v
    end
    return out
end

local function empty_deps_asdl(session)
    local H = session.T.MoonHost
    return H.FragmentDeps({}, {})
end

local function deps_asdl_from_table(session, deps)
    if deps ~= nil and classof(deps) == session.T.MoonHost.FragmentDeps then return deps end
    local r, e = {}, {}
    if deps then
        if deps.region_frags then
            for _, v in pairs(deps.region_frags) do
                r[#r + 1] = v.frag or v
            end
        end
        if deps.expr_frags then
            for _, v in pairs(deps.expr_frags) do
                e[#e + 1] = v.frag or v
            end
        end
    end
    return session.T.MoonHost.FragmentDeps(r, e)
end

local function host_kind_for_value(session, value)
    local H = session.T.MoonHost
    if type(value) == "table" then
        local mt = getmetatable(value)
        if mt == RegionFragValue or rawget(value, "kind") == "region_frag" or rawget(value, "moonlift_quote_kind") == "region_frag" then return H.HostValueRegionFrag end
        if mt == ExprFragValue or rawget(value, "kind") == "expr_frag" or rawget(value, "moonlift_quote_kind") == "expr_frag" then return H.HostValueExprFrag end
        if rawget(value, "moonlift_quote_kind") == "type" or rawget(value, "kind") == "type" or type(value.as_type_value) == "function" or (mt and mt.__moonlift_host_type_value == true) then return H.HostValueType end
        if rawget(value, "moonlift_quote_kind") == "module" then return H.HostValueModule end
        if rawget(value, "moonlift_quote_kind") == "source" then return H.HostValueSource end
    end
    return H.HostValueLua
end

local function value_ref(session, value, pretty)
    if value == nil then value = NilSpliceValue end
    local H = session.T.MoonHost
    local id = session:host_value_id(pretty or (type(value) == "table" and (value.name or value.kind)) or type(value))
    local kind = host_kind_for_value(session, value)
    session:register_host_value(id, value)
    return H.HostValueRef(id, kind)
end

function RegionFragValue:moonlift_splice_source() return self.name end
function RegionFragValue:__tostring() return "MoonRegionFragValue(" .. tostring(self.name) .. ")" end

function ExprFragValue:moonlift_splice_source() return self.name end
function ExprFragValue:__tostring() return "MoonExprFragValue(" .. tostring(self.name) .. ")" end

function SourceValue:moonlift_splice_source() return self.source end
function SourceValue:__tostring() return self.source end

function M.region_frag_value(session, frag, opts)
    opts = opts or {}
    assert_same_context(session, frag, "region_frag_value")
    local O = session.T.MoonOpen
    assert(classof(frag) == O.RegionFrag, "region_frag_value expects MoonOpen.RegionFrag")
    local deps = deps_asdl_from_table(session, opts.deps)
    local meta = session.T.MoonHost.RegionFragMeta(frag.name, frag, opts.protocol, deps)
    local value = setmetatable({
        kind = "region_frag",
        moonlift_quote_kind = "region_frag",
        id = session:host_value_id("region:" .. frag.name),
        name = frag.name,
        frag = frag,
        meta = meta,
        params = frag.params,
        params_by_name = list_to_name_map(frag.params),
        conts = list_to_name_map(frag.conts),
        protocol = opts.protocol,
        deps = deps,
        T = session.T,
        session = session,
    }, RegionFragValue)
    session:register_host_value(value.id, value)
    return value
end

function M.expr_frag_value(session, frag, opts)
    opts = opts or {}
    assert_same_context(session, frag, "expr_frag_value")
    local O = session.T.MoonOpen
    assert(classof(frag) == O.ExprFrag, "expr_frag_value expects MoonOpen.ExprFrag")
    local value = setmetatable({
        kind = "expr_frag",
        moonlift_quote_kind = "expr_frag",
        id = session:host_value_id("expr:" .. frag.name),
        name = frag.name,
        frag = frag,
        params = frag.params,
        params_by_name = list_to_name_map(frag.params),
        T = session.T,
        session = session,
    }, ExprFragValue)
    session:register_host_value(value.id, value)
    return value
end

function M.source_value(session, source, deps)
    local value = setmetatable({
        kind = "source",
        moonlift_quote_kind = "source",
        id = session:host_value_id("source"),
        source = tostring(source or ""),
        deps = deps,
        T = session.T,
        session = session,
    }, SourceValue)
    session:register_host_value(value.id, value)
    return value
end

function M.value_ref(session, value, pretty)
    return value_ref(session, value, pretty)
end

function M.empty_deps(session)
    return empty_deps_asdl(session)
end

function M.deps_asdl_from_table(session, deps)
    return deps_asdl_from_table(session, deps)
end

function M.Install(api, session)
    api.CanonicalRegionFragValue = RegionFragValue
    api.CanonicalExprFragValue = ExprFragValue
    api.HostSourceValue = SourceValue
    api.host_value_ref = function(value, pretty) return value_ref(session, value, pretty) end
    api.region_frag_value_from_asdl = function(frag, opts) return M.region_frag_value(session, frag, opts) end
    api.expr_frag_value_from_asdl = function(frag, opts) return M.expr_frag_value(session, frag, opts) end
    api.empty_fragment_deps = function() return empty_deps_asdl(session) end
    api.fragment_deps_from_table = function(deps) return deps_asdl_from_table(session, deps) end

    -- moon.memoize(fn): returns a memoized version of a factory function.
    -- Caches results by argument identity. Like Terra's terralib.memoize().
    -- Works for any MoonLift value (regions, exprs, modules, funcs, structs).
    -- Usage: local make_range = moon.memoize(function(lo, hi) return region ... end end)
    api.memoize = function(fn)
        local cache = {}
        return function(...)
            local n = select("#", ...)
            if n == 0 then
                cache[0] = cache[0] or fn()
                return cache[0]
            end
            local key = {n}
            for i = 1, n do
                local v = select(i, ...)
                local tv = type(v)
                if tv == "table" then
                    -- MoonLift values: use splice source (region name, expr name, etc.)
                    -- Falls back to .name, then .kind, then tostring
                    key[i + 1] = (type(v.moonlift_splice_source) == "function" and v:moonlift_splice_source())
                        or v.name or v.kind or tostring(v)
                else
                    key[i + 1] = tostring(v)
                end
            end
            local k = table.concat(key, "\0")
            cache[k] = cache[k] or fn(...)
            return cache[k]
        end
    end
end

return M
