local M = {}

local ExprValue = {}
ExprValue.__index = ExprValue
ExprValue.__moon2_host_expr_value = true

local function get_expr_value(v)
    if type(v) ~= "table" then return nil end
    local mt = getmetatable(v)
    if mt == ExprValue then return v end
    if mt and mt.__moon2_host_expr_value and type(v.as_expr_value) == "function" then return v:as_expr_value() end
    return nil
end

function ExprValue:as_expr_value()
    return self
end

function ExprValue:as_moon2_expr()
    return self.expr
end

function ExprValue:__tostring()
    return "Moon2ExprValue(" .. tostring(self.source_hint or self.expr) .. ")"
end

function M.Install(api, session)
    local T = session.T
    local C, Ty, B, Sem, Tr = T.Moon2Core, T.Moon2Type, T.Moon2Bind, T.Moon2Sem, T.Moon2Tree

    local function expr_value(expr, ty, source_hint, extra)
        local v = extra or {}
        v.kind = "expr"
        v.session = session
        v.expr = expr
        v.type = ty and api.as_type_value(ty, "expr type must be a type value") or nil
        v.source_hint = source_hint
        return setmetatable(v, ExprValue)
    end

    local function coerce(v, site)
        local e = get_expr_value(v)
        if e then return e end
        if type(v) == "number" then return api.int(v) end
        if type(v) == "boolean" then return api.bool_lit(v) end
        error((site or "expected expression value") .. ": got " .. type(v), 3)
    end

    local function moon_expr(v, site)
        return coerce(v, site).expr
    end

    local function type_or_nil(v)
        local e = get_expr_value(v)
        return e and e.type or nil
    end

    local function source_of(v)
        local e = coerce(v)
        return e.source_hint or tostring(e.expr)
    end

    function api.expr_from_asdl(expr, ty, source_hint, extra)
        return expr_value(expr, ty, source_hint, extra)
    end

    function api.as_expr_value(v, site)
        return coerce(v, site)
    end

    function api.as_moon2_expr(v, site)
        return moon_expr(v, site)
    end

    function api.int(raw, ty)
        return expr_value(Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(raw))), ty or api.i32, tostring(raw))
    end

    function api.float(raw, ty)
        return expr_value(Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(raw))), ty or api.f64, tostring(raw))
    end

    function api.bool_lit(value)
        return expr_value(Tr.ExprLit(Tr.ExprSurface, C.LitBool(value and true or false)), api.bool, value and "true" or "false")
    end

    function api.nil_lit(ty)
        return expr_value(Tr.ExprLit(Tr.ExprSurface, C.LitNil), ty, "nil")
    end

    function api.expr_ref(binding, ty, source_hint, extra)
        extra = extra or {}
        extra.binding = binding
        return expr_value(Tr.ExprRef(Tr.ExprSurface, B.ValueRefBinding(binding)), ty, source_hint or binding.name, extra)
    end

    local function binary(lhs, op, rhs, source_op)
        lhs, rhs = coerce(lhs, "binary lhs"), coerce(rhs, "binary rhs")
        return expr_value(Tr.ExprBinary(Tr.ExprSurface, op, lhs.expr, rhs.expr), lhs.type, "(" .. source_of(lhs) .. " " .. source_op .. " " .. source_of(rhs) .. ")")
    end

    local function compare(lhs, op, rhs, source_op)
        lhs, rhs = coerce(lhs, "compare lhs"), coerce(rhs, "compare rhs")
        return expr_value(Tr.ExprCompare(Tr.ExprSurface, op, lhs.expr, rhs.expr), api.bool, "(" .. source_of(lhs) .. " " .. source_op .. " " .. source_of(rhs) .. ")")
    end

    function ExprValue.__add(a, b) return binary(a, C.BinAdd, b, "+") end
    function ExprValue.__sub(a, b) return binary(a, C.BinSub, b, "-") end
    function ExprValue.__mul(a, b) return binary(a, C.BinMul, b, "*") end
    function ExprValue.__div(a, b) return binary(a, C.BinDiv, b, "/") end
    function ExprValue.__mod(a, b) return binary(a, C.BinRem, b, "%") end
    function ExprValue.__unm(a)
        a = coerce(a, "unary operand")
        return expr_value(Tr.ExprUnary(Tr.ExprSurface, C.UnaryNeg, a.expr), a.type, "(-" .. source_of(a) .. ")")
    end

    function ExprValue:eq(rhs) return compare(self, C.CmpEq, rhs, "==") end
    function ExprValue:ne(rhs) return compare(self, C.CmpNe, rhs, "~=") end
    function ExprValue:lt(rhs) return compare(self, C.CmpLt, rhs, "<") end
    function ExprValue:le(rhs) return compare(self, C.CmpLe, rhs, "<=") end
    function ExprValue:gt(rhs) return compare(self, C.CmpGt, rhs, ">") end
    function ExprValue:ge(rhs) return compare(self, C.CmpGe, rhs, ">=") end

    function ExprValue:band(rhs) return binary(self, C.BinBitAnd, rhs, "&") end
    function ExprValue:bor(rhs) return binary(self, C.BinBitOr, rhs, "|") end
    function ExprValue:bxor(rhs) return binary(self, C.BinBitXor, rhs, "~") end
    function ExprValue:shl(rhs) return binary(self, C.BinShl, rhs, "<<") end
    function ExprValue:lshr(rhs) return binary(self, C.BinLShr, rhs, ">>") end
    function ExprValue:ashr(rhs) return binary(self, C.BinAShr, rhs, ">>>") end

    function ExprValue:field(name, ty)
        assert(type(name) == "string" and name ~= "", "field expects a field name")
        local field_ty = ty
        if field_ty == nil and self.type and self.type.fields_by_name then
            field_ty = self.type.fields_by_name[name]
        end
        if field_ty == nil and self.pointee_type and self.pointee_type.fields_by_name then
            field_ty = self.pointee_type.fields_by_name[name]
        end
        assert(field_ty ~= nil, "field type is required unless the base expression carries struct field metadata")
        local ft = api.as_type_value(field_ty, "field type must be a type value")
        return expr_value(Tr.ExprField(Tr.ExprSurface, self.expr, Sem.FieldByName(name, ft.ty)), ft, (self.source_hint or "<expr>") .. "." .. name)
    end

    function ExprValue:index(index)
        local idx = coerce(index, "index expects expression value")
        local elem_ty = self.element_type
        return expr_value(Tr.ExprIndex(Tr.ExprSurface, Tr.IndexBaseExpr(self.expr), idx.expr), elem_ty, (self.source_hint or "<expr>") .. "[" .. (idx.source_hint or "<idx>") .. "]")
    end

    function ExprValue:select(then_value, else_value)
        local tv, ev = coerce(then_value, "select then"), coerce(else_value, "select else")
        return expr_value(Tr.ExprSelect(Tr.ExprSurface, self.expr, tv.expr, ev.expr), tv.type, "select(...)")
    end

    function ExprValue:cast(ty)
        local tv = api.as_type_value(ty, "cast expects type value")
        return expr_value(Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, tv.ty, self.expr), tv, "cast<" .. tv.source_hint .. ">(...)")
    end

    function ExprValue:zext(ty)
        local tv = api.as_type_value(ty, "zext expects type value")
        return expr_value(Tr.ExprCast(Tr.ExprSurface, C.SurfaceZExt, tv.ty, self.expr), tv, "zext<" .. tv.source_hint .. ">(...)")
    end

    function api.select(cond, then_value, else_value)
        return coerce(cond, "select cond"):select(then_value, else_value)
    end

    function api.load(addr, ty)
        local a = coerce(addr, "load expects address expression")
        local tv = api.as_type_value(ty, "load expects result type")
        return expr_value(Tr.ExprLoad(Tr.ExprSurface, tv.ty, a.expr), tv, "load(...)")
    end

    function api.addr_of(place)
        local p = api.as_place_value(place, "addr_of expects place value")
        local ty = p.type and api.ptr(p.type) or nil
        return expr_value(Tr.ExprAddrOf(Tr.ExprSurface, p.place), ty, "&" .. tostring(p.source_hint or "<place>"))
    end

    function ExprValue:load(ty)
        return api.load(self, ty)
    end

    function api.intrinsic(op, args, ty)
        local op_value = assert(C["Intrinsic" .. op], "unknown intrinsic: " .. tostring(op))
        local exprs = {}
        for i = 1, #(args or {}) do exprs[i] = moon_expr(args[i], "intrinsic arg") end
        return expr_value(Tr.ExprIntrinsic(Tr.ExprSurface, op_value, exprs), ty, op .. "(...)")
    end

    api.ExprValue = ExprValue
end

return M
