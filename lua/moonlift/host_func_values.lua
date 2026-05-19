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

    function api.params(specs)
        if type(specs) == "table" and #specs > 0 and type(specs[1]) == "table" and specs[1].name ~= nil then
            local out = {}
            for i = 1, #specs do
                local spec = specs[i]
                local tv = api.as_type_value(spec.type, "params element expects type value")
                out[i] = setmetatable({
                    kind = "param",
                    session = session,
                    name = spec.name,
                    type = tv,
                    decl = Ty.Param(spec.name, tv.ty),
                }, ParamValue)
            end
            return out
        end
        error("moon.params{table} expects array of {name, type} records", 2)
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
        return parsed.value
    end

    function api._stmts_values_binder(values)
        local Parse = require("moonlift.parse")
        local hs = require("moonlift.host_splice")
        local expand = require("moonlift.open_expand")
        return function(src)
            local T_local = T
            local parsed = Parse.Define(T_local).parse_stmts(src)
            if #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
            if #parsed.splice_slots == 0 then return parsed.value end
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
            return e.stmts(parsed.value, env)
        end
    end



    -- ── api.stmts — unified quoting + values binder ────────────────────────
    -- Supports three forms:
    --   api.stmts(src)               — pure quote (no @{} allowed)
    --   api.stmts{values}(src)       — values binder (quote with @{})
    --   api.stmts{array}             — ASDL pass-through (raw Stmt[])
    --
    -- The dispatch object is a table with __call for pure quotes and
    -- __index for the table-argument forms.
    local stmts_mt = {}
    function stmts_mt.__call(_, arg)
        if type(arg) == "string" then
            -- Pure quote: moon.stmts[[src]]
            local Parse = require("moonlift.parse").Define(T)
            local parsed = Parse.parse_stmts(arg)
            if #parsed.issues ~= 0 then error(parsed.issues[1].message, 3) end
            if #parsed.splice_slots ~= 0 then
                error("moon.stmts[[]] does not evaluate @{}; use moon.stmts{values}[[src]] instead", 3)
            end
            return parsed.value
        end
        if type(arg) == "table" then
            -- Table argument: values binder or ASDL pass-through
            if #arg > 0 then
                local pvm = require("moonlift.pvm")
                if pvm.classof(arg[1]) ~= false then return arg end
            end
            for k in pairs(arg) do
                if type(k) == "string" then
                    return api._stmts_values_binder(arg)
                end
            end
            error("moon.stmts{...}: table has no string keys nor ASDL elements", 3)
        end
        error("moon.stmts expects a string [[]] or table {}", 3)
    end
    api.stmts = setmetatable({}, stmts_mt)

    api.ParamValue = ParamValue
    api.FuncValue = FuncValue
    api.FuncBuilder = FuncBuilder
end

return M
