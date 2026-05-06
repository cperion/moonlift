local M = {}

local ExprFragValue = {}
ExprFragValue.__index = ExprFragValue

local ExprFragBuilder = {}
ExprFragBuilder.__index = ExprFragBuilder

local function assert_name(name, site)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), site .. " expects an identifier")
end

function ExprFragValue:moonlift_splice_source()
    return self.name
end

function ExprFragValue:moonlift_splice(role, session, site)
    if role == "expr_frag" then return self.frag end
    error((site or "splice") .. ": expression fragment value cannot splice as " .. role, 2)
end

function ExprFragValue:__tostring()
    return "MoonExprFragValue(" .. self.name .. ")"
end

function M.Install(api, session)
    local T = session.T
    local C, B, O, Tr = T.MoonCore, T.MoonBind, T.MoonOpen, T.MoonTree

    local function as_param(v, site)
        if type(v) == "table" and getmetatable(v) == api.ParamValue then return v end
        error((site or "expected param value") .. ": got " .. type(v), 3)
    end

    function ExprFragBuilder:param(name)
        local v = self.bindings[name]
        assert(v ~= nil, "unknown expr fragment parameter: " .. tostring(name))
        return v
    end

    function api.expr_frag(name, params, result_ty, body_fn)
        assert_name(name, "expr_frag")
        assert(type(params) == "table", "expr_frag params must be an ordered list")
        assert(type(body_fn) == "function", "expr_frag expects a body builder function")
        local result = api.as_type_value(result_ty, "expr_frag result must be a type value")
        local open_params = {}
        local bindings = {}
        local seen = {}
        for i = 1, #params do
            local p = as_param(params[i], "expr_frag param")
            assert(not seen[p.name], "duplicate expr_frag parameter: " .. p.name)
            seen[p.name] = true
            local op = O.OpenParam(session:symbol_key("expr_open_param", name .. ":" .. p.name), p.name, p.type.ty)
            open_params[i] = op
            local binding = B.Binding(C.Id("expr-open-param:" .. name .. ":" .. p.name), p.name, p.type.ty, B.BindingClassOpenParam(op))
            bindings[p.name] = api.expr_ref(binding, p.type, p.name)
        end
        local builder = setmetatable({ name = name, bindings = bindings }, ExprFragBuilder)
        local body = api.as_expr_value(body_fn(builder), "expr_frag body must return an expression value")
        local frag = O.ExprFrag(O.NameRefText(name), open_params, O.OpenSet({}, {}, {}, {}), body.expr, result.ty)
        session.T._moonlift_host_expr_frags = session.T._moonlift_host_expr_frags or {}
        session.T._moonlift_host_expr_frags[name] = frag
        return setmetatable({ kind = "expr_frag", name = name, frag = frag, result = result, params = params }, ExprFragValue)
    end

    function api.emit_expr(fragment, args)
        assert(type(fragment) == "table" and getmetatable(fragment) == ExprFragValue, "emit_expr expects an expression fragment value")
        args = args or {}
        if #args ~= #fragment.params then api.raise_host_issue(session.T.MoonHost.HostIssueArgCount("emit_expr " .. fragment.name, #fragment.params, #args)) end
        local exprs = {}
        for i = 1, #args do exprs[i] = api.as_moonlift_expr(args[i], "emit_expr arg expects expression") end
        local use_id = session:symbol_key("emit_expr", fragment.name)
        return api.expr_from_asdl(Tr.ExprUseExprFrag(Tr.ExprSurface, use_id, O.ExprFragRefName(fragment.name), exprs, {}), fragment.result, "emit " .. fragment.name .. "(...)")
    end

    function api.expr_frag_template(name, type_params, builder_fn)
        assert_name(name, "expr_frag_template")
        assert(type(type_params) == "table", "expr_frag_template type params must be an ordered list")
        assert(type(builder_fn) == "function", "expr_frag_template expects a builder function")
        return {
            kind = "expr_frag_template",
            name = name,
            type_params = type_params,
            instantiate = function(_, args)
                args = args or {}
                assert(#args == #type_params, "expr_frag_template " .. name .. " expected " .. #type_params .. " type args, got " .. #args)
                local concrete = {}
                local suffix = {}
                for i = 1, #args do
                    concrete[i] = api.as_type_value(args[i], "expr_frag_template arg must be a type value")
                    suffix[i] = concrete[i].source_hint:gsub("[^_%w]+", "_")
                end
                local spec = builder_fn(unpack(concrete))
                assert(type(spec) == "table", "expr_frag_template builder must return a spec table")
                return api.expr_frag(name .. "_" .. table.concat(suffix, "_"), spec.params or {}, spec.result, spec.body)
            end,
        }
    end

    api.ExprFragValue = ExprFragValue
    api.ExprFragBuilder = ExprFragBuilder
end

return M
