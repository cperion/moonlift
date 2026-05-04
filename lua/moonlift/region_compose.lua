-- ASDL-native region composition.
--
-- This module no longer generates `region ... end` source.  Composition is
-- lowered through the hosted region/ASDL builder and returns real region
-- fragment values.  Parser-shaped helpers (`seq`, `choice`, `star`, ...) are
-- retained here only as protocol-parameterized conveniences; the long-term
-- parser-facing API lives in parser_compose.lua.

local HostSession = require("moonlift.host_session")

local M = {}
local Compose = {}
Compose.__index = Compose

local function ordered_keys(map)
    local keys = {}
    for k in pairs(map or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function assert_region_value(frag, site)
    assert(type(frag) == "table" and (frag.kind == "region_frag" or frag.moonlift_quote_kind == "region_frag") and frag.name, (site or "compose") .. " expects RegionFragValue")
end

local function cont_params(cont)
    return cont.params or cont.block_params or {}
end

local function cont_signature(cont)
    local ps = cont_params(cont)
    local out = {}
    for i = 1, #ps do
        local p = ps[i]
        out[i] = tostring(p.name) .. ":" .. tostring((p.type and p.type.ty) or p.ty)
    end
    return table.concat(out, ",")
end

local function same_cont_sig(a, b)
    return cont_signature(a) == cont_signature(b)
end

function Compose.new(moon_or_session, opts)
    opts = opts or {}
    local api, session, prefix
    if type(moon_or_session) == "table" and moon_or_session.region_frag then
        api = moon_or_session
        session = api.session
        prefix = opts.prefix or opts[1]
    elseif type(moon_or_session) == "table" and moon_or_session.api then
        session = moon_or_session
        api = session:api()
        prefix = opts.prefix or opts[1]
    elseif type(moon_or_session) == "string" or moon_or_session == nil then
        -- Full-clean API is session/API based.  For bare old-style construction,
        -- create a fresh ASDL host session so new builder fragments can still be
        -- composed without source strings.
        session = HostSession.new({ prefix = moon_or_session or "compose" })
        api = session:api()
        prefix = moon_or_session or "compose"
        opts._auto_session = true
    else
        error("region_compose.new expects moon host api, HostSession, or prefix", 2)
    end
    return setmetatable({ api = api, session = session, prefix = prefix or "compose", next_id = 0, _auto_session = opts._auto_session or false }, Compose)
end

function Compose:adopt_fragment_session(frag)
    if self._auto_session and frag and frag.session and frag.session ~= self.session then
        self.session = frag.session
        self.api = frag.session:api()
        self._auto_session = false
    end
end

function Compose:fresh(base)
    self.next_id = self.next_id + 1
    return string.format("%s_%s_%d", self.prefix, base or "g", self.next_id)
end

Compose.fresh_id = Compose.fresh

local function as_type_value(api, ty)
    if type(ty) == "table" and ty.ty then return ty end
    return api.type_from_asdl(ty, tostring(ty))
end

function Compose:param_specs_from_fragment(frag)
    local api = self.api
    local out = {}
    for i = 1, #(frag.params or {}) do
        local p = frag.params[i]
        if type(p) == "table" and getmetatable(p) == api.ParamValue then
            out[i] = p
        else
            out[i] = api.param(p.name, as_type_value(api, p.ty))
        end
    end
    return out
end

function Compose:cont_specs_from_fragment(frag)
    local api = self.api
    local out = {}
    for _, name in ipairs(ordered_keys(frag.conts or {})) do
        local cont = frag.conts[name]
        local ps = cont_params(cont)
        local cparams = {}
        for i = 1, #ps do
            local p = ps[i]
            if type(p) == "table" and getmetatable(p) == api.ParamValue then
                cparams[i] = p
            else
                cparams[i] = api.param(p.name, as_type_value(api, p.ty or (p.type and p.type.ty)))
            end
        end
        out[name] = api.cont(cparams)
    end
    return out
end

function Compose:runtime_args_from_region(r, params)
    local args = {}
    for i = 1, #(params or {}) do
        args[i] = r[params[i].name]
    end
    return args
end

function Compose:runtime_args_after(block, r, params, opts)
    opts = opts or {}
    local position_param = opts.position_param or "pos"
    local next_param = opts.next_param or "next"
    local args = {}
    for i = 1, #(params or {}) do
        local name = params[i].name
        if name == position_param then args[i] = block[next_param] else args[i] = r[name] end
    end
    return args
end

function Compose:validate_complete_routes(frag, routes)
    local H = self.session.T.MoonHost
    for name in pairs(frag.conts or {}) do
        if routes[name] == nil then
            self.api.raise_host_issue(H.HostIssueRegionComposeIncompleteRoute(frag.name, name))
        end
    end
end

function Compose:to_outer(name, arg_map)
    return { kind = "outer", name = name, arg_map = arg_map }
end

function Compose:route(name, frag, opts)
    assert_region_value(frag, "route")
    self:adopt_fragment_session(frag)
    opts = opts or {}
    name = name or self:fresh("route")
    local params = opts.params or self:param_specs_from_fragment(frag)
    local conts = opts.conts or self:cont_specs_from_fragment(frag)
    local routes = opts.exits or opts.routes or {}
    for cname in pairs(frag.conts or {}) do
        routes[cname] = routes[cname] or self:to_outer(cname)
    end
    self:validate_complete_routes(frag, routes)

    local api = self.api
    return api.region_frag(name, params, conts, function(r)
        r:entry("start", {}, function(b)
            local fills = {}
            for cname, target in pairs(routes) do
                if target.kind == "outer" then
                    assert(r.conts[target.name], "unknown outer continuation: " .. tostring(target.name))
                    fills[cname] = r.conts[target.name]
                else
                    error("route target kind not yet lowerable in entry: " .. tostring(target.kind), 2)
                end
            end
            local args = opts.args and opts.args(r) or self:runtime_args_from_region(r, params)
            b:emit(frag, args, fills)
        end)
    end)
end

function Compose:forward(frag, exit_map)
    assert_region_value(frag, "forward")
    local routes = {}
    for cname in pairs(frag.conts or {}) do
        routes[cname] = self:to_outer((exit_map and exit_map[cname]) or cname)
    end
    return self:route(self:fresh("forward"), frag, { exits = routes })
end

function Compose:seq(fragments, opts)
    opts = opts or {}
    assert(type(fragments) == "table" and #fragments > 0, "seq expects a non-empty array of fragments")
    for i = 1, #fragments do assert_region_value(fragments[i], "seq") end
    self:adopt_fragment_session(fragments[1])
    local name = opts.name or self:fresh("seq")
    local through = opts.through or "ok"
    local failure = opts.failure or "fail"
    local params = opts.params or self:param_specs_from_fragment(fragments[1])
    local conts = opts.conts or self:cont_specs_from_fragment(fragments[1])
    local api = self.api

    return api.region_frag(name, params, conts, function(r)
        local after = {}
        for i = #fragments, 2, -1 do
            local prev_exit = fragments[i - 1].conts[through]
            if not prev_exit then
                api.raise_host_issue(self.session.T.MoonHost.HostIssueRegionComposeMissingExit(fragments[i - 1].name, through))
            end
            local bparams = {}
            local cps = cont_params(prev_exit)
            for j = 1, #cps do
                local p = cps[j]
                bparams[j] = api.param(p.name, as_type_value(api, p.ty or (p.type and p.type.ty)))
            end
            after[i - 1] = r:block_decl(self:fresh("seq_after"), bparams)
            after[i - 1]:body_fn(function(b)
                local fills = {}
                for cname in pairs(fragments[i].conts or {}) do
                    if cname == through and i < #fragments then fills[cname] = after[i]
                    elseif r.conts[cname] then fills[cname] = r.conts[cname]
                    elseif cname == failure and r.conts[failure] then fills[cname] = r.conts[failure]
                    else api.raise_host_issue(self.session.T.MoonHost.HostIssueRegionComposeIncompleteRoute(fragments[i].name, cname)) end
                end
                local args = opts.next_args and opts.next_args(r, b, fragments[i], i) or self:runtime_args_after(b, r, params, opts)
                b:emit(fragments[i], args, fills)
            end)
        end
        r:entry("start", {}, function(b)
            local fills = {}
            for cname in pairs(fragments[1].conts or {}) do
                if cname == through and #fragments > 1 then fills[cname] = after[1]
                elseif r.conts[cname] then fills[cname] = r.conts[cname]
                elseif cname == failure and r.conts[failure] then fills[cname] = r.conts[failure]
                else api.raise_host_issue(self.session.T.MoonHost.HostIssueRegionComposeIncompleteRoute(fragments[1].name, cname)) end
            end
            b:emit(fragments[1], self:runtime_args_from_region(r, params), fills)
        end)
    end)
end

function Compose:choice(alternatives, opts)
    opts = opts or {}
    assert(type(alternatives) == "table" and #alternatives > 0, "choice expects a non-empty array of fragments")
    for i = 1, #alternatives do assert_region_value(alternatives[i], "choice") end
    self:adopt_fragment_session(alternatives[1])
    local name = opts.name or self:fresh("choice")
    local success = opts.success or "ok"
    local failure = opts.failure or "fail"
    local params = opts.params or self:param_specs_from_fragment(alternatives[1])
    local conts = opts.conts or self:cont_specs_from_fragment(alternatives[1])
    local api = self.api

    return api.region_frag(name, params, conts, function(r)
        local tries = {}
        for i = #alternatives, 2, -1 do
            local fail_exit = alternatives[i - 1].conts[failure]
            if not fail_exit then api.raise_host_issue(self.session.T.MoonHost.HostIssueRegionComposeMissingExit(alternatives[i - 1].name, failure)) end
            local bparams = {}
            local cps = cont_params(fail_exit)
            for j = 1, #cps do local p = cps[j]; bparams[j] = api.param(p.name, as_type_value(api, p.ty or (p.type and p.type.ty))) end
            tries[i - 1] = r:block_decl(self:fresh("choice_try"), bparams)
            tries[i - 1]:body_fn(function(b)
                local fills = {}
                for cname in pairs(alternatives[i].conts or {}) do
                    if cname == success and r.conts[success] then fills[cname] = r.conts[success]
                    elseif cname == failure and i < #alternatives then fills[cname] = tries[i]
                    elseif r.conts[cname] then fills[cname] = r.conts[cname]
                    else api.raise_host_issue(self.session.T.MoonHost.HostIssueRegionComposeIncompleteRoute(alternatives[i].name, cname)) end
                end
                b:emit(alternatives[i], self:runtime_args_from_region(r, params), fills)
            end)
        end
        r:entry("start", {}, function(b)
            local fills = {}
            for cname in pairs(alternatives[1].conts or {}) do
                if cname == success and r.conts[success] then fills[cname] = r.conts[success]
                elseif cname == failure and #alternatives > 1 then fills[cname] = tries[1]
                elseif r.conts[cname] then fills[cname] = r.conts[cname]
                else api.raise_host_issue(self.session.T.MoonHost.HostIssueRegionComposeIncompleteRoute(alternatives[1].name, cname)) end
            end
            b:emit(alternatives[1], self:runtime_args_from_region(r, params), fills)
        end)
    end)
end

function Compose:star(fragment, opts)
    opts = opts or {}
    assert_region_value(fragment, "star")
    self:adopt_fragment_session(fragment)
    local api = self.api
    local name = opts.name or self:fresh("star")
    local success = opts.success or "ok"
    local failure = opts.failure or "fail"
    local position_param = opts.position_param or "pos"
    local next_param = opts.next_param or "next"
    local params = opts.params or self:param_specs_from_fragment(fragment)
    local conts = opts.conts or { [success] = self:cont_specs_from_fragment(fragment)[success] }

    return api.region_frag(name, params, conts, function(r)
        local loop = r:block_decl(self:fresh("star_loop"), { api.param(next_param, api.i32) })
        local yield = r:block_decl(self:fresh("star_yield"), { api.param(opts.failure_param or "at", api.i32) })
        local zero = r:block_decl(self:fresh("star_zero"), {})
        loop:body_fn(function(b)
            local fills = {}; fills[success] = loop; fills[failure] = yield
            b:emit(fragment, self:runtime_args_after(b, r, params, { position_param = position_param, next_param = next_param }), fills)
        end)
        yield:body_fn(function(b) b:jump(r.conts[success], { [next_param] = b[opts.failure_param or "at"] }) end)
        zero:body_fn(function(b) b:jump(r.conts[success], { [next_param] = r[position_param] }) end)
        r:entry("start", {}, function(b)
            local fills = {}; fills[success] = loop; fills[failure] = zero
            b:emit(fragment, self:runtime_args_from_region(r, params), fills)
        end)
    end)
end

function Compose:plus(fragment, opts)
    return self:seq({ fragment, self:star(fragment, opts) }, opts)
end

function Compose:opt(fragment, opts)
    opts = opts or {}
    self:adopt_fragment_session(fragment)
    local api = self.api
    local name = opts.name or self:fresh("opt")
    local success = opts.success or "ok"
    local failure = opts.failure or "fail"
    local position_param = opts.position_param or "pos"
    local next_param = opts.next_param or "next"
    local params = opts.params or self:param_specs_from_fragment(fragment)
    local conts = opts.conts or { [success] = self:cont_specs_from_fragment(fragment)[success] }
    return api.region_frag(name, params, conts, function(r)
        local none = r:block_decl(self:fresh("opt_none"), { api.param(opts.failure_param or "at", api.i32) })
        none:body_fn(function(b) b:jump(r.conts[success], { [next_param] = r[position_param] }) end)
        r:entry("start", {}, function(b)
            local fills = {}; fills[success] = r.conts[success]; fills[failure] = none
            b:emit(fragment, self:runtime_args_from_region(r, params), fills)
        end)
    end)
end

-- Lookahead remains parser sugar; kept protocol-parameterized for now.
function Compose:pred(fragment, opts)
    opts = opts or {}
    self:adopt_fragment_session(fragment)
    local api = self.api
    local name = opts.name or self:fresh("pred")
    local success = opts.success or "ok"
    local failure = opts.failure or "fail"
    local position_param = opts.position_param or "pos"
    local next_param = opts.next_param or "next"
    local params = opts.params or self:param_specs_from_fragment(fragment)
    local conts = opts.conts or self:cont_specs_from_fragment(fragment)
    return api.region_frag(name, params, conts, function(r)
        local okb = r:block_decl(self:fresh("pred_ok"), { api.param(next_param, api.i32) })
        okb:body_fn(function(b) b:jump(r.conts[success], { [next_param] = r[position_param] }) end)
        r:entry("start", {}, function(b)
            local fills = {}; fills[success] = okb; fills[failure] = r.conts[failure]
            b:emit(fragment, self:runtime_args_from_region(r, params), fills)
        end)
    end)
end

function Compose:not_pred(fragment, opts)
    opts = opts or {}
    self:adopt_fragment_session(fragment)
    local api = self.api
    local name = opts.name or self:fresh("not")
    local success = opts.success or "ok"
    local failure = opts.failure or "fail"
    local position_param = opts.position_param or "pos"
    local next_param = opts.next_param or "next"
    local params = opts.params or self:param_specs_from_fragment(fragment)
    local conts = opts.conts or self:cont_specs_from_fragment(fragment)
    return api.region_frag(name, params, conts, function(r)
        local okb = r:block_decl(self:fresh("not_ok"), { api.param(opts.failure_param or "at", api.i32) })
        local failb = r:block_decl(self:fresh("not_fail"), { api.param(next_param, api.i32) })
        okb:body_fn(function(b) b:jump(r.conts[success], { [next_param] = r[position_param] }) end)
        failb:body_fn(function(b) b:jump(r.conts[failure], { [opts.failure_param or "at"] = r[position_param] }) end)
        r:entry("start", {}, function(b)
            local fills = {}; fills[success] = failb; fills[failure] = okb
            b:emit(fragment, self:runtime_args_from_region(r, params), fills)
        end)
    end)
end

M.new = Compose.new
M.Compose = Compose
return M
