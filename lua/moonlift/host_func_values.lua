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
    local C, Ty, B, Tr = T.MoonCore, T.MoonType, T.MoonBind, T.MoonTree

    local function as_param(v, site)
        if type(v) == "table" and getmetatable(v) == ParamValue then return v end
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

    function FuncBuilder:param(name)
        local v = self.bindings[name]
        assert(v ~= nil, "unknown function parameter: " .. tostring(name))
        return v
    end

    function FuncBuilder:emit(stmt)
        self.body[#self.body + 1] = stmt
        return stmt
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

    function api._module_export_func(module_value, name, params, result, builder_fn)
        return make_func(module_value, "export", name, params, result, builder_fn)
    end

    api.ParamValue = ParamValue
    api.FuncValue = FuncValue
    api.FuncBuilder = FuncBuilder
end

return M
