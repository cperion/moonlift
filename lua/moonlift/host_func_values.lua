local M = {}

local ParamValue = {}
ParamValue.__index = ParamValue

local FuncValue = {}
FuncValue.__index = FuncValue

local FuncBuilder = {}
FuncBuilder.__index = FuncBuilder

local function assert_name(name, site)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), site .. " expects an identifier")
end

function FuncValue:as_item()
    return self.item
end

function FuncValue:__tostring()
    return "MoonFuncValue(" .. self.name .. ")"
end

function M.Install(api, session)
    local T = session.T
    local C, Ty, B, O, Sem, Tr = T.MoonCore, T.MoonType, T.MoonBind, T.MoonOpen, T.MoonSem, T.MoonTree
    local pvm = require("moonlift.pvm")

    local function as_param(v, site)
        if type(v) == "table" and getmetatable(v) == ParamValue then return v end
        if type(v) == "table" and v.name and v.type then
            local tv = api.as_type_value(v.type, site)
            return setmetatable({
                kind = "param",
                session = session,
                name = v.name,
                type = tv,
                decl = Ty.Param(v.name, tv.ty),
            }, ParamValue)
        end
        error((site or "expected param value") .. ": got " .. type(v), 3)
    end

    local function param_decls(params)
        local out = {}
        for i = 1, #params do out[i] = params[i].decl end
        return out
    end

    local function binding_extra_for_type(tv)
        local extra = {}
        if tv.pointee then
            extra.pointee_type = tv.pointee
            extra.element_type = tv.pointee
        end
        if tv.element then extra.element_type = tv.element end
        return extra
    end

    local function new_builder(module_value, name, params, result)
        local b = setmetatable({
            session = session,
            module = module_value,
            name = name,
            params = params,
            result = result,
            body = {},
            bindings = {},
        }, FuncBuilder)
        for i = 1, #params do
            local p = params[i]
            local binding = B.Binding(C.Id("arg:" .. name .. ":" .. p.name), p.name, p.type.ty, B.BindingClassArg(i - 1))
            p.binding = binding
            b.bindings[p.name] = api.expr_ref(binding, p.type, p.name, binding_extra_for_type(p.type))
        end
        return b
    end

    local function child_builder(parent)
        local bindings = {}
        for k, v in pairs(parent.bindings) do bindings[k] = v end
        return setmetatable({
            session = session,
            module = parent.module,
            name = parent.name,
            params = parent.params,
            result = parent.result,
            body = {},
            bindings = bindings,
        }, FuncBuilder)
    end

    function api.param(name, ty)
        assert_name(name, "param")
        local tv = api.as_type_value(ty, "param expects a type value")
        return setmetatable({
            kind = "param",
            session = session,
            name = name,
            type = tv,
            decl = Ty.Param(name, tv.ty),
        }, ParamValue)
    end

    local function sorted_string_keys(t)
        local keys = {}
        for k in pairs(t) do
            if type(k) == "string" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        return keys
    end

    local function param_from_spec(spec, site)
        if type(spec) == "table" and getmetatable(spec) == ParamValue then return spec end
        if type(spec) == "table" and spec.name ~= nil then
            return api.param(spec.name, spec.type)
        end
        if type(spec) == "table" and type(spec[1]) == "string" then
            return api.param(spec[1], spec[2])
        end
        error((site or "params") .. " expects param specs as {name=..., type=...} or {\"name\", type}", 3)
    end

    function api.params(specs)
        assert(type(specs) == "table", "moon.params expects a table")
        local out = {}
        if #specs > 0 then
            for i = 1, #specs do out[i] = param_from_spec(specs[i], "params element") end
            return out
        end
        -- Convenience map form: moon.params { a = moon.i32, b = moon.i32 }.
        -- Map keys are sorted for deterministic output; use list/pair form to
        -- control ABI parameter order.
        local keys = sorted_string_keys(specs)
        for i = 1, #keys do out[i] = api.param(keys[i], specs[keys[i]]) end
        return out
    end

    function FuncBuilder:param(name)
        local v = self.bindings[name]
        assert(v ~= nil, "unknown function parameter: " .. tostring(name))
        return v
    end

    local function append_stmt(builder, stmt)
        builder.body[#builder.body + 1] = stmt
        return stmt
    end

    local function ordered_pairs_from_map(map)
        local keys = {}
        for k in pairs(map or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        local i = 0
        return function()
            i = i + 1
            local k = keys[i]
            if k ~= nil then return k, map[k] end
        end
    end

    function FuncBuilder:emit(stmt_or_fragment, runtime_args, fills)
        if type(stmt_or_fragment) == "table"
            and (rawget(stmt_or_fragment, "moonlift_quote_kind") == "region_frag"
                 or rawget(stmt_or_fragment, "kind") == "region_frag") then
            local fragment = stmt_or_fragment
            local args = {}
            for i = 1, #(runtime_args or {}) do
                args[i] = api.as_moonlift_expr(runtime_args[i], "emit runtime arg expects expression")
            end
            local cont_fills = {}
            for name, target in ordered_pairs_from_map(fills or {}) do
                if type(target) == "string" then
                    cont_fills[#cont_fills + 1] = O.ContBinding(name, O.ContTargetLabel(Tr.BlockLabel(target)))
                elseif type(target) == "table" and target.label ~= nil then
                    cont_fills[#cont_fills + 1] = O.ContBinding(name, O.ContTargetLabel(target.label))
                elseif type(target) == "table" and target.slot ~= nil then
                    cont_fills[#cont_fills + 1] = O.ContBinding(name, O.ContTargetSlot(target.slot))
                else
                    error("continuation fill must be a block label string, block value, or continuation value", 2)
                end
            end
            return append_stmt(self, Tr.StmtUseRegionFrag(Tr.StmtSurface,
                session:symbol_key("emit", fragment.name or "region"),
                O.RegionFragRefName(fragment.name), args, {}, cont_fills))
        end
        return append_stmt(self, stmt_or_fragment)
    end

    function FuncBuilder:use_region(fragment, runtime_args, fills)
        return self:emit(fragment, runtime_args, fills)
    end

    function FuncBuilder:return_(expr)
        if expr == nil then
            return self:emit(Tr.StmtReturnVoid(Tr.StmtSurface))
        end
        local e = api.as_expr_value(expr, "return expects expression value")
        return self:emit(Tr.StmtReturnValue(Tr.StmtSurface, e.expr))
    end

    function FuncBuilder:expr(expr)
        local e = api.as_expr_value(expr, "expr statement expects expression value")
        return self:emit(Tr.StmtExpr(Tr.StmtSurface, e.expr))
    end

    function FuncBuilder:yield_(expr)
        if expr == nil then return self:emit(Tr.StmtYieldVoid(Tr.StmtSurface)) end
        local e = api.as_expr_value(expr, "yield expects expression value")
        return self:emit(Tr.StmtYieldValue(Tr.StmtSurface, e.expr))
    end

    local function jump_args(args)
        local out = {}
        local keys = {}
        for k in pairs(args or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        for i = 1, #keys do
            local name = keys[i]
            out[#out + 1] = Tr.JumpArg(name, api.as_moonlift_expr(args[name], "jump arg expects expression value"))
        end
        return out
    end

    function FuncBuilder:jump(target, args)
        if type(target) == "string" then
            assert(target:match("^[_%a][_%w]*$"), "jump target must be an identifier")
            return self:emit(Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(target), jump_args(args)))
        elseif type(target) == "table" and target.label ~= nil then
            return self:emit(Tr.StmtJump(Tr.StmtSurface, target.label, jump_args(args)))
        end
        error("jump target must be a block label string or block-like value", 2)
    end

    function FuncBuilder:place(name)
        local v = self.bindings[name]
        assert(v ~= nil, "unknown function binding: " .. tostring(name))
        return v:place()
    end

    function FuncBuilder:set(place, value)
        local p = api.as_place_value(place, "set expects place value")
        local v = api.as_expr_value(value, "set expects expression value")
        return self:emit(Tr.StmtSet(Tr.StmtSurface, p.place, v.expr))
    end

    function FuncBuilder:atomic_store(addr, value, ty)
        return self:emit(api.atomic_store(addr, value, ty))
    end

    function FuncBuilder:atomic_fence()
        return self:emit(api.atomic_fence())
    end

    function FuncBuilder:if_(cond, then_fn, else_fn)
        local c = api.as_expr_value(cond, "if_ expects condition expression")
        assert(type(then_fn) == "function", "if_ expects then builder function")
        local then_builder = child_builder(self)
        then_fn(then_builder)
        local else_body = {}
        if else_fn ~= nil then
            assert(type(else_fn) == "function", "if_ expects else builder function")
            local else_builder = child_builder(self)
            else_fn(else_builder)
            else_body = else_builder.body
        end
        return self:emit(Tr.StmtIf(Tr.StmtSurface, c.expr, then_builder.body, else_body))
    end

    function FuncBuilder:let(name, ty, init)
        assert_name(name, "let")
        local tv = api.as_type_value(ty, "let expects a type value")
        local e = api.as_expr_value(init, "let expects expression init")
        local binding = B.Binding(session:id("local", self.name .. ":" .. name), name, tv.ty, B.BindingClassLocalValue)
        self:emit(Tr.StmtLet(Tr.StmtSurface, binding, e.expr))
        local ref = api.expr_ref(binding, tv, name, binding_extra_for_type(tv))
        self.bindings[name] = ref
        return ref
    end

    function FuncBuilder:var(name, ty, init)
        assert_name(name, "var")
        local tv = api.as_type_value(ty, "var expects a type value")
        local e = api.as_expr_value(init, "var expects expression init")
        local binding = B.Binding(session:id("local", self.name .. ":" .. name), name, tv.ty, B.BindingClassLocalCell)
        self:emit(Tr.StmtVar(Tr.StmtSurface, binding, e.expr))
        local ref = api.expr_ref(binding, tv, name, binding_extra_for_type(tv))
        self.bindings[name] = ref
        return ref
    end

    local function make_func(module_value, visibility, name, params, result, builder_fn)
        assert_name(name, "func")
        assert(type(params) == "table", "function params must be an ordered list")
        local ps = {}
        local seen = {}
        for i = 1, #params do
            local p = as_param(params[i], "function param")
            assert(not seen[p.name], "duplicate function parameter: " .. p.name)
            seen[p.name] = true
            ps[i] = p
        end
        local ret = api.as_type_value(result or api.void, "function result must be a type value")
        local builder = new_builder(module_value, name, ps, ret)
        local maybe = builder_fn and builder_fn(builder)
        if maybe ~= nil then builder:return_(maybe) end
        local decl_params = param_decls(ps)
        local func
        if visibility == "export" then
            func = Tr.FuncExport(name, decl_params, ret.ty, builder.body)
        else
            func = Tr.FuncLocal(name, decl_params, ret.ty, builder.body)
        end
        return setmetatable({
            kind = "func",
            session = session,
            name = name,
            visibility = visibility,
            params = ps,
            result = ret,
            func = func,
            item = Tr.ItemFunc(func),
            type = api.func_type((function()
                local ts = {}; for i = 1, #ps do ts[i] = ps[i].type end; return ts
            end)(), ret),
        }, FuncValue)
    end

    function api._module_func(module_value, name, params, result, builder_fn)
        return make_func(module_value, "local", name, params, result, builder_fn)
    end

    function api._module_extern_func(module_value, name, params, result, symbol)
        assert_name(name, "extern func")
        assert(type(params) == "table", "extern function params must be an ordered list")
        local ps = {}
        local seen = {}
        for i = 1, #params do
            local p = as_param(params[i], "extern function param")
            assert(not seen[p.name], "duplicate extern function parameter: " .. p.name)
            seen[p.name] = true
            ps[i] = p
        end
        local ret = api.as_type_value(result or api.void, "extern function result must be a type value")
        local func = Tr.ExternFunc(name, symbol or name, param_decls(ps), ret.ty)
        return setmetatable({
            kind = "extern_func",
            session = session,
            name = name,
            visibility = "extern",
            symbol = symbol or name,
            params = ps,
            result = ret,
            func = func,
            item = Tr.ItemExtern(func),
            type = api.func_type((function()
                local ts = {}; for i = 1, #ps do ts[i] = ps[i].type end; return ts
            end)(), ret),
        }, FuncValue)
    end

    function api._module_export_func(module_value, name, params, result, builder_fn)
        return make_func(module_value, "export", name, params, result, builder_fn)
    end

    function api._stmts_quote(src)
        local Parse = require("moonlift.parse").Define(T)
        local parsed = Parse.parse_stmts(src)
        if #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
        if #parsed.splice_slots ~= 0 then
            error("moon.stmts[[]] does not evaluate @{}; use moon.stmts{values}[[src]] instead", 3)
        end
        return setmetatable(parsed.value, stmts_concat_mt)
    end

    function api._stmts_values_binder(values)
        local Parse = require("moonlift.parse")
        local hs = require("moonlift.host_splice")
        local expand = require("moonlift.open_expand")
        return function(src)
            local T_local = T
            local parsed = Parse.Define(T_local).parse_stmts(src)
            if #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
            if #parsed.splice_slots == 0 then
                return setmetatable(parsed.value, stmts_concat_mt)
            end
            local bindings = {}
            for _, ss in ipairs(parsed.splice_slots) do
                local splice_key = ss.splice_text or ss.splice_id
                local v = values[splice_key]
                if v == nil then
                    error("no value bound for @" .. tostring(splice_key) .. " in values table", 3)
                end
                local binding = hs.fill(session, ss.slot, v, "splice " .. splice_key, ss.role, ss.spread)
                bindings[#bindings + 1] = binding
            end
            local e = expand.Define(T_local)
            local env = e.empty_env()
            env = e.env_with_fills(env, bindings)
            return setmetatable(e.stmts(parsed.value, env), stmts_concat_mt)
        end
    end



    -- ── Statement concatenation ────────────────────────────────────────
    -- Wraps Stmt[] arrays so you can compose them with `..`:
    --   local body = moon.stmts[[ let x = 1 ]] .. moon.stmts[[ return x ]]
    local stmts_concat_mt = {}
    function stmts_concat_mt.__concat(a, b)
        local result = {}
        local function append(v)
            if type(v) == "table" then
                local pvm = require("moonlift.pvm")
                -- ASDL node (has __class) → single element
                -- Plain array → iterate
                local mt = getmetatable(v)
                if mt and mt.__class then
                    result[#result + 1] = v
                elseif #v > 0 then
                    for i = 1, #v do result[#result + 1] = v[i] end
                end
                return
            end
            result[#result + 1] = v
        end
        append(a)
        append(b)
        return setmetatable(result, stmts_concat_mt)
    end

    -- ── api.stmts — chain-based quote through frontend pipeline ────────────
    -- Uses chain.lua so that @{} bindings and expand/env are handled correctly.
    local chain_mod = require("moonlift.chain")
    local chain_binding = chain_mod.bind(session)
    api.stmts = chain_binding.make_quote(
        -- parse_fn
        function(T, src)
            local Parse = require("moonlift.parse").Define(T)
            return Parse.parse_stmts(src)
        end,
        -- wrap_fn
        function(value, parsed, T, src, bindings)
            return setmetatable(value, stmts_concat_mt)
        end,
        -- expand_fn
        function(e, value, env)
            return e.stmts(value, env)
        end,
        -- table_fn (ASDL pass-through)
        function(arg)
            return setmetatable(arg, stmts_concat_mt)
        end
    )

    function api.switch_stmt_arm(raw_key, body)
        return { kind = "switch_stmt_arm", raw_key = tostring(raw_key), body = body }
    end

    function api.switch_arms(specs, default_body)
        assert(type(specs) == "table", "moon.switch_arms expects a table")
        local function make_arm(key, body)
            return { raw_key = tostring(key), body = body }
        end
        local out = {}
        if #specs > 0 then
            local first = specs[1]
            -- Single compact arm: {42, body}
            if type(first) == "number" or type(first) == "string" then
                out[#out + 1] = make_arm(first, specs[2])
            else
                -- Array of compact arms: {{42, body1}, {10, body2}}
                for i = 1, #specs do
                    local s = specs[i]
                    if type(s) == "table" then
                        out[#out + 1] = make_arm(s[1], s[2])
                    end
                end
            end
        end
        if default_body then
            out[#out + 1] = make_arm("default", default_body)
        end
        return out
    end

    api.ParamValue = ParamValue
    api.FuncValue = FuncValue
    api.FuncBuilder = FuncBuilder
end

return M
