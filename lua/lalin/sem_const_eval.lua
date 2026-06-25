local schema = require("lalin.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end
local bit = require("bit")

local function bind_context(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Tr = T.LalinTree

    local expr_type
    local literal_const
    local unary_const
    local binary_const
    local compare_const
    local logic_const
    local value_ref_const
    local expr_const_class
    local stmt_const_result

    local function const_value(v)
        return v
    end

    local function no() return nil end
    local function yes(v) return v end

    local function int_raw(v)
        if schema.classof(v) == Sem.ConstInt then return v.raw end
        return nil
    end

    local function bool_value(v)
        if schema.classof(v) == Sem.ConstBool then return v.value end
        return nil
    end

    local function number_string(n)
        if n == nil then return nil end
        if n == math.floor(n) then return tostring(n) end
        return tostring(n)
    end

    local function local_lookup(env, binding)
        for i = #env.entries, 1, -1 do
            local entry = env.entries[i]
            if entry.binding == binding then return entry.value end
        end
        return nil
    end

    local function local_put(env, binding, value)
        local entries = {}
        for i = 1, #env.entries do entries[#entries + 1] = env.entries[i] end
        entries[#entries + 1] = Sem.ConstLocalEntry(binding, value)
        return Sem.ConstLocalEnv(entries)
    end

    local function eval_expr(expr, const_env, local_env)
        return only(expr_const_class(expr, const_env, local_env))
    end

    local function eval_value(expr, const_env, local_env)
        return const_value(eval_expr(expr, const_env, local_env))
    end

    local function eval_stmts(stmts, const_env, local_env)
        local current = local_env
        for i = 1, #stmts do
            local result = only(stmt_const_result(stmts[i], const_env, current))
            local cls = schema.classof(result)
            if result.kind == "falls_through" then
                current = result.env
            else
                return result
            end
        end
        return { kind = "falls_through", env = current }
    end

    local function field_value(fields, name)
        for i = 1, #fields do
            if fields[i].name == name then return fields[i].value end
        end
        return nil
    end

    local function switch_key_value(key)
        return key
    end

    local function same_const(a, b)
        return a == b
    end

    function expr_type(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprSurface) then
            return (function()
 return {}
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprTyped) then
            return (function(self)
 return single(self.ty)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprOpen) then
            return (function(self)
 return single(self.ty)
            end)(node, ...)
        else
            error("phase lalin_sem_const_expr_type: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function literal_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.LitInt) then
            return (function(self, ty)
 return single(yes(Sem.ConstInt(ty, self.raw)))
            end)(node, ...)
        elseif schema.isa(node, C.LitFloat) then
            return (function(self, ty)
 return single(yes(Sem.ConstFloat(ty, self.raw)))
            end)(node, ...)
        elseif schema.isa(node, C.LitBool) then
            return (function(self)
 return single(yes(Sem.ConstBool(self.value)))
            end)(node, ...)
        elseif schema.isa(node, C.LitString) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, C.LitNil) then
            return (function(_, ty)
 return single(yes(Sem.ConstNil(ty)))
            end)(node, ...)
        else
            error("phase lalin_sem_literal_const: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function unary_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.UnaryNeg) then
            return (function(_, value, ty)

            local raw = int_raw(value)
            if raw == nil then return single(no()) end
            return single(yes(Sem.ConstInt(ty, number_string(-tonumber(raw)))))
            end)(node, ...)
        elseif schema.isa(node, C.UnaryNot) then
            return (function(_, value)

            local b = bool_value(value)
            if b == nil then return single(no()) end
            return single(yes(Sem.ConstBool(not b)))
            end)(node, ...)
        elseif schema.isa(node, C.UnaryBitNot) then
            return (function(_, value, ty)

            local raw = int_raw(value)
            if raw == nil then return single(no()) end
            return single(yes(Sem.ConstInt(ty, tostring(bit.bnot(tonumber(raw))))) )
            end)(node, ...)
        else
            error("phase lalin_sem_unary_const: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function binary_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.BinAdd) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, number_string(x + y))))
            end)(node, ...)
        elseif schema.isa(node, C.BinSub) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, number_string(x - y))))
            end)(node, ...)
        elseif schema.isa(node, C.BinMul) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, number_string(x * y))))
            end)(node, ...)
        elseif schema.isa(node, C.BinDiv) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y or y == 0 then return single(no()) end; return single(yes(Sem.ConstInt(ty, number_string(math.floor(x / y)))))
            end)(node, ...)
        elseif schema.isa(node, C.BinRem) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y or y == 0 then return single(no()) end; return single(yes(Sem.ConstInt(ty, number_string(x % y))))
            end)(node, ...)
        elseif schema.isa(node, C.BinBitAnd) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, tostring(bit.band(x, y)))))
            end)(node, ...)
        elseif schema.isa(node, C.BinBitOr) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, tostring(bit.bor(x, y)))))
            end)(node, ...)
        elseif schema.isa(node, C.BinBitXor) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, tostring(bit.bxor(x, y)))))
            end)(node, ...)
        elseif schema.isa(node, C.BinShl) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, tostring(bit.lshift(x, y)))))
            end)(node, ...)
        elseif schema.isa(node, C.BinLShr) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, tostring(bit.rshift(x, y)))))
            end)(node, ...)
        elseif schema.isa(node, C.BinAShr) then
            return (function(_, a, b, ty)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstInt(ty, tostring(bit.arshift(x, y)))))
            end)(node, ...)
        else
            error("phase lalin_sem_binary_const: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function compare_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.CmpEq) then
            return (function(_, a, b)
 return single(yes(Sem.ConstBool(same_const(a, b))))
            end)(node, ...)
        elseif schema.isa(node, C.CmpNe) then
            return (function(_, a, b)
 return single(yes(Sem.ConstBool(not same_const(a, b))))
            end)(node, ...)
        elseif schema.isa(node, C.CmpLt) then
            return (function(_, a, b)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstBool(x < y)))
            end)(node, ...)
        elseif schema.isa(node, C.CmpLe) then
            return (function(_, a, b)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstBool(x <= y)))
            end)(node, ...)
        elseif schema.isa(node, C.CmpGt) then
            return (function(_, a, b)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstBool(x > y)))
            end)(node, ...)
        elseif schema.isa(node, C.CmpGe) then
            return (function(_, a, b)
 local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return single(no()) end; return single(yes(Sem.ConstBool(x >= y)))
            end)(node, ...)
        else
            error("phase lalin_sem_compare_const: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function logic_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, C.LogicAnd) then
            return (function(_, a, b)
 local x, y = bool_value(a), bool_value(b); if x == nil or y == nil then return single(no()) end; return single(yes(Sem.ConstBool(x and y)))
            end)(node, ...)
        elseif schema.isa(node, C.LogicOr) then
            return (function(_, a, b)
 local x, y = bool_value(a), bool_value(b); if x == nil or y == nil then return single(no()) end; return single(yes(Sem.ConstBool(x or y)))
            end)(node, ...)
        else
            error("phase lalin_sem_logic_const: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function value_ref_const(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, B.ValueRefBinding) then
            return (function(self, const_env, local_env)

            local local_value = local_lookup(local_env, self.binding)
            if local_value ~= nil then return single(yes(local_value)) end
            local class = self.binding.class
            if schema.classof(class) == B.BindingClassGlobalConst then
                for i = 1, #const_env.entries do
                    local entry = const_env.entries[i]
                    if entry.module_name == class.module_name and entry.item_name == class.item_name then
                        return expr_const_class(entry.value, const_env, Sem.ConstLocalEnv({}))
                    end
                end
            end
            return single(no())
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefName) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefPath) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, B.ValueRefHole) then
            return (function()
 return single(nil)
            end)(node, ...)
        else
            error("phase lalin_sem_value_ref_const: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function expr_const_class(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ExprLit) then
            return (function(self)

            local tys = expr_type(self.h)
            return literal_const(self.value, tys[1] or Ty.TScalar(C.ScalarVoid))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprRef) then
            return (function(self, const_env, local_env)
 return value_ref_const(self.ref, const_env, local_env)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUnary) then
            return (function(self, const_env, local_env)

            local v = eval_value(self.value, const_env, local_env)
            if v == nil then return single(no()) end
            local tys = expr_type(self.h)
            return unary_const(self.op, v, tys[1] or Ty.TScalar(C.ScalarVoid))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBinary) then
            return (function(self, const_env, local_env)

            local a, b = eval_value(self.lhs, const_env, local_env), eval_value(self.rhs, const_env, local_env)
            if a == nil or b == nil then return single(no()) end
            local tys = expr_type(self.h)
            return binary_const(self.op, a, b, tys[1] or Ty.TScalar(C.ScalarVoid))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCompare) then
            return (function(self, const_env, local_env)

            local a, b = eval_value(self.lhs, const_env, local_env), eval_value(self.rhs, const_env, local_env)
            if a == nil or b == nil then return single(no()) end
            return compare_const(self.op, a, b)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLogic) then
            return (function(self, const_env, local_env)

            local a, b = eval_value(self.lhs, const_env, local_env), eval_value(self.rhs, const_env, local_env)
            if a == nil or b == nil then return single(no()) end
            return logic_const(self.op, a, b)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCast) then
            return (function(self, const_env, local_env)

            local v = eval_value(self.value, const_env, local_env)
            if v == nil then return single(no()) end
            if schema.classof(v) == Sem.ConstInt then return single(yes(Sem.ConstInt(self.ty, v.raw))) end
            if schema.classof(v) == Sem.ConstFloat then return single(yes(Sem.ConstFloat(self.ty, v.raw))) end
            if schema.classof(v) == Sem.ConstNil then return single(yes(Sem.ConstNil(self.ty))) end
            return single(yes(v))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprMachineCast) then
            return (function(self, const_env, local_env)
 return expr_const_class(Tr.ExprCast(self.h, C.SurfaceCast, self.ty, self.value), const_env, local_env)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIntrinsic) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAddrOf) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDeref) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprCall) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLen) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprDot) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprField) then
            return (function(self, const_env, local_env)

            local base = eval_value(self.base, const_env, local_env)
            if base == nil or schema.classof(base) ~= Sem.ConstAgg then return single(no()) end
            local v = field_value(base.fields, self.field.field_name)
            if v == nil then return single(no()) end
            return single(yes(v))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIndex) then
            return (function(self, const_env, local_env)

            local base = nil
            if schema.classof(self.base) == Tr.IndexBaseView then return single(no()) end
            base = eval_value(self.base.base, const_env, local_env)
            local index = eval_value(self.index, const_env, local_env)
            local n = index and tonumber(int_raw(index))
            if base == nil or schema.classof(base) ~= Sem.ConstArray or n == nil then return single(no()) end
            local v = base.elems[n + 1]
            if v == nil then return single(no()) end
            return single(yes(v))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAgg) then
            return (function(self, const_env, local_env)

            local fields = {}
            for i = 1, #self.fields do
                local v = eval_value(self.fields[i].value, const_env, local_env)
                if v == nil then return single(no()) end
                fields[#fields + 1] = Sem.ConstFieldValue(self.fields[i].name, v)
            end
            return single(yes(Sem.ConstAgg(self.ty, fields)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprArray) then
            return (function(self, const_env, local_env)

            local elems = {}
            for i = 1, #self.elems do
                local v = eval_value(self.elems[i], const_env, local_env)
                if v == nil then return single(no()) end
                elems[#elems + 1] = v
            end
            return single(yes(Sem.ConstArray(self.elem_ty, elems)))
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprIf) then
            return (function(self, const_env, local_env)

            local cond = eval_value(self.cond, const_env, local_env)
            local b = cond and bool_value(cond)
            if b == nil then return single(no()) end
            if b then return expr_const_class(self.then_expr, const_env, local_env) end
            return expr_const_class(self.else_expr, const_env, local_env)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSelect) then
            return (function(self, const_env, local_env)

            local cond = eval_value(self.cond, const_env, local_env)
            local b = cond and bool_value(cond)
            if b == nil then return single(no()) end
            if b then return expr_const_class(self.then_expr, const_env, local_env) end
            return expr_const_class(self.else_expr, const_env, local_env)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSwitch) then
            return (function(self, const_env, local_env)

            local value = eval_value(self.value, const_env, local_env)
            if value == nil then return single(no()) end
            for i = 1, #self.arms do
                local key = switch_key_value(self.arms[i].raw_key)
                if key == value or (type(key) == "string" and int_raw(value) == key) then
                    local stmt_result = eval_stmts(self.arms[i].body, const_env, local_env)
                    if stmt_result.kind == "falls_through" then
                        return expr_const_class(self.arms[i].result, const_env, stmt_result.env)
                    end
                    return single(no())
                end
            end
            return expr_const_class(self.default_expr, const_env, local_env)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprControl) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprBlock) then
            return (function(self, const_env, local_env)

            local result = eval_stmts(self.stmts, const_env, local_env)
            if result.kind ~= "falls_through" then return single(no()) end
            return expr_const_class(self.result, const_env, result.env)
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprClosure) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprView) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprLoad) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicLoad) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicRmw) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprAtomicCas) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprSlotValue) then
            return (function()
 return single(no())
            end)(node, ...)
        elseif schema.isa(node, Tr.ExprUseExprFrag) then
            return (function()
 return single(no())
            end)(node, ...)
        else
            error("phase lalin_sem_expr_const_class: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    function stmt_const_result(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.StmtLet) then
            return (function(self, const_env, local_env)

            local v = eval_value(self.init, const_env, local_env)
            if v == nil then return single({ kind = "falls_through", env = local_env }) end
            return single({ kind = "falls_through", env = local_put(local_env, self.binding, v) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtVar) then
            return (function(self, const_env, local_env)

            local v = eval_value(self.init, const_env, local_env)
            if v == nil then return single({ kind = "falls_through", env = local_env }) end
            return single({ kind = "falls_through", env = local_put(local_env, self.binding, v) })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSet) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicStore) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAtomicFence) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtExpr) then
            return (function(self, const_env, local_env)
 eval_expr(self.expr, const_env, local_env); return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtAssert) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtIf) then
            return (function(self, const_env, local_env)

            local cond = eval_value(self.cond, const_env, local_env)
            local b = cond and bool_value(cond)
            if b == nil then return single({ kind = "falls_through", env = local_env }) end
            if b then return single(eval_stmts(self.then_body, const_env, local_env)) end
            return single(eval_stmts(self.else_body, const_env, local_env))
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtSwitch) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnVoid) then
            return (function(_, _, local_env)
 return single({ kind = "return_void", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtReturnValue) then
            return (function(self, const_env, local_env)

            local v = eval_value(self.value, const_env, local_env)
            if v == nil then return single({ kind = "return_void", env = local_env }) end
            return single({ kind = "return_value", env = local_env, value = v })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJump) then
            return (function(self, _, local_env)
 return single({ kind = "jump", env = local_env, target = self.target.name })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtJumpCont) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldVoid) then
            return (function(_, _, local_env)
 return single({ kind = "yield_void", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtYieldValue) then
            return (function(self, const_env, local_env)

            local v = eval_value(self.value, const_env, local_env)
            if v == nil then return single({ kind = "yield_void", env = local_env }) end
            return single({ kind = "yield_value", env = local_env, value = v })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtControl) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionSlot) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        elseif schema.isa(node, Tr.StmtUseRegionFrag) then
            return (function(_, _, local_env)
 return single({ kind = "falls_through", env = local_env })
            end)(node, ...)
        else
            error("phase lalin_sem_stmt_const_result: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function empty_const_env() return B.ConstEnv({}) end
    local function empty_local_env() return Sem.ConstLocalEnv({}) end

    return {
        empty_const_env = empty_const_env,
        empty_local_env = empty_local_env,
        expr_type = expr_type,
        literal_const = literal_const,
        expr_const_class = expr_const_class,
        stmt_const_result = stmt_const_result,
        expr = function(expr, const_env, local_env) return only(expr_const_class(expr, const_env or empty_const_env(), local_env or empty_local_env())) end,
        value = function(expr, const_env, local_env) return const_value(only(expr_const_class(expr, const_env or empty_const_env(), local_env or empty_local_env()))) end,
        stmts = function(stmts, const_env, local_env) return eval_stmts(stmts, const_env or empty_const_env(), local_env or empty_local_env()) end,
    }
end

return bind_context