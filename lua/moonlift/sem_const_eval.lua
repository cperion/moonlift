local pvm = require("moonlift.pvm")
local bit = require("bit")

local M = {}

function M.Define(T)
    local C = T.Moon2Core
    local Ty = T.Moon2Type
    local B = T.Moon2Bind
    local Sem = T.Moon2Sem
    local Tr = T.Moon2Tree

    local expr_type
    local literal_const
    local unary_const
    local binary_const
    local compare_const
    local logic_const
    local value_ref_const
    local expr_const_class
    local stmt_const_result

    local function const_value(class)
        if pvm.classof(class) == Sem.ConstClassYes then return class.value end
        return nil
    end

    local function no() return Sem.ConstClassNo end
    local function yes(v) return Sem.ConstClassYes(v) end

    local function int_raw(v)
        if pvm.classof(v) == Sem.ConstInt then return v.raw end
        return nil
    end

    local function bool_value(v)
        if pvm.classof(v) == Sem.ConstBool then return v.value end
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
        return pvm.one(expr_const_class(expr, const_env, local_env))
    end

    local function eval_value(expr, const_env, local_env)
        return const_value(eval_expr(expr, const_env, local_env))
    end

    local function eval_stmts(stmts, const_env, local_env)
        local current = local_env
        for i = 1, #stmts do
            local result = pvm.one(stmt_const_result(stmts[i], const_env, current))
            local cls = pvm.classof(result)
            if cls == Sem.ConstStmtFallsThrough then
                current = result.local_env
            else
                return result
            end
        end
        return Sem.ConstStmtFallsThrough(current)
    end

    local function field_value(fields, name)
        for i = 1, #fields do
            if fields[i].name == name then return fields[i].value end
        end
        return nil
    end

    local function switch_key_value(key)
        local cls = pvm.classof(key)
        if cls == Sem.SwitchKeyConst then return key.value end
        if cls == Sem.SwitchKeyRaw then return key.raw end
        return nil
    end

    local function same_const(a, b)
        return a == b
    end

    expr_type = pvm.phase("moon2_sem_const_expr_type", {
        [Tr.ExprSurface] = function() return pvm.empty() end,
        [Tr.ExprTyped] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprOpen] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprSem] = function(self) return pvm.once(self.ty) end,
        [Tr.ExprCode] = function(self) return pvm.once(self.ty) end,
    })

    literal_const = pvm.phase("moon2_sem_literal_const", {
        [C.LitInt] = function(self, ty) return pvm.once(yes(Sem.ConstInt(ty, self.raw))) end,
        [C.LitFloat] = function(self, ty) return pvm.once(yes(Sem.ConstFloat(ty, self.raw))) end,
        [C.LitBool] = function(self) return pvm.once(yes(Sem.ConstBool(self.value))) end,
        [C.LitNil] = function(_, ty) return pvm.once(yes(Sem.ConstNil(ty))) end,
    }, { args_cache = "last" })

    unary_const = pvm.phase("moon2_sem_unary_const", {
        [C.UnaryNeg] = function(_, value, ty)
            local raw = int_raw(value)
            if raw == nil then return pvm.once(no()) end
            return pvm.once(yes(Sem.ConstInt(ty, number_string(-tonumber(raw)))))
        end,
        [C.UnaryNot] = function(_, value)
            local b = bool_value(value)
            if b == nil then return pvm.once(no()) end
            return pvm.once(yes(Sem.ConstBool(not b)))
        end,
        [C.UnaryBitNot] = function(_, value, ty)
            local raw = int_raw(value)
            if raw == nil then return pvm.once(no()) end
            return pvm.once(yes(Sem.ConstInt(ty, tostring(bit.bnot(tonumber(raw))))) )
        end,
    }, { args_cache = "last" })

    binary_const = pvm.phase("moon2_sem_binary_const", {
        [C.BinAdd] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, number_string(x + y)))) end,
        [C.BinSub] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, number_string(x - y)))) end,
        [C.BinMul] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, number_string(x * y)))) end,
        [C.BinDiv] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y or y == 0 then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, number_string(math.floor(x / y))))) end,
        [C.BinRem] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y or y == 0 then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, number_string(x % y)))) end,
        [C.BinBitAnd] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, tostring(bit.band(x, y))))) end,
        [C.BinBitOr] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, tostring(bit.bor(x, y))))) end,
        [C.BinBitXor] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, tostring(bit.bxor(x, y))))) end,
        [C.BinShl] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, tostring(bit.lshift(x, y))))) end,
        [C.BinLShr] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, tostring(bit.rshift(x, y))))) end,
        [C.BinAShr] = function(_, a, b, ty) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstInt(ty, tostring(bit.arshift(x, y))))) end,
    }, { args_cache = "last" })

    compare_const = pvm.phase("moon2_sem_compare_const", {
        [C.CmpEq] = function(_, a, b) return pvm.once(yes(Sem.ConstBool(same_const(a, b)))) end,
        [C.CmpNe] = function(_, a, b) return pvm.once(yes(Sem.ConstBool(not same_const(a, b)))) end,
        [C.CmpLt] = function(_, a, b) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstBool(x < y))) end,
        [C.CmpLe] = function(_, a, b) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstBool(x <= y))) end,
        [C.CmpGt] = function(_, a, b) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstBool(x > y))) end,
        [C.CmpGe] = function(_, a, b) local x, y = tonumber(int_raw(a)), tonumber(int_raw(b)); if not x or not y then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstBool(x >= y))) end,
    }, { args_cache = "last" })

    logic_const = pvm.phase("moon2_sem_logic_const", {
        [C.LogicAnd] = function(_, a, b) local x, y = bool_value(a), bool_value(b); if x == nil or y == nil then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstBool(x and y))) end,
        [C.LogicOr] = function(_, a, b) local x, y = bool_value(a), bool_value(b); if x == nil or y == nil then return pvm.once(no()) end; return pvm.once(yes(Sem.ConstBool(x or y))) end,
    }, { args_cache = "last" })

    value_ref_const = pvm.phase("moon2_sem_value_ref_const", {
        [B.ValueRefBinding] = function(self, const_env, local_env)
            local local_value = local_lookup(local_env, self.binding)
            if local_value ~= nil then return pvm.once(yes(local_value)) end
            local class = self.binding.class
            if pvm.classof(class) == B.BindingClassGlobalConst then
                for i = 1, #const_env.entries do
                    local entry = const_env.entries[i]
                    if entry.module_name == class.module_name and entry.item_name == class.item_name then
                        return expr_const_class(entry.value, const_env, Sem.ConstLocalEnv({}))
                    end
                end
            end
            return pvm.once(no())
        end,
        [B.ValueRefName] = function() return pvm.once(no()) end,
        [B.ValueRefPath] = function() return pvm.once(no()) end,
        [B.ValueRefSlot] = function() return pvm.once(no()) end,
        [B.ValueRefFuncSlot] = function() return pvm.once(no()) end,
        [B.ValueRefConstSlot] = function() return pvm.once(no()) end,
        [B.ValueRefStaticSlot] = function() return pvm.once(no()) end,
    }, { args_cache = "last" })

    expr_const_class = pvm.phase("moon2_sem_expr_const_class", {
        [Tr.ExprLit] = function(self)
            local tys = pvm.drain(expr_type(self.h))
            return literal_const(self.value, tys[1] or Ty.TScalar(C.ScalarVoid))
        end,
        [Tr.ExprRef] = function(self, const_env, local_env) return value_ref_const(self.ref, const_env, local_env) end,
        [Tr.ExprUnary] = function(self, const_env, local_env)
            local v = eval_value(self.value, const_env, local_env)
            if v == nil then return pvm.once(no()) end
            local tys = pvm.drain(expr_type(self.h))
            return unary_const(self.op, v, tys[1] or Ty.TScalar(C.ScalarVoid))
        end,
        [Tr.ExprBinary] = function(self, const_env, local_env)
            local a, b = eval_value(self.lhs, const_env, local_env), eval_value(self.rhs, const_env, local_env)
            if a == nil or b == nil then return pvm.once(no()) end
            local tys = pvm.drain(expr_type(self.h))
            return binary_const(self.op, a, b, tys[1] or Ty.TScalar(C.ScalarVoid))
        end,
        [Tr.ExprCompare] = function(self, const_env, local_env)
            local a, b = eval_value(self.lhs, const_env, local_env), eval_value(self.rhs, const_env, local_env)
            if a == nil or b == nil then return pvm.once(no()) end
            return compare_const(self.op, a, b)
        end,
        [Tr.ExprLogic] = function(self, const_env, local_env)
            local a, b = eval_value(self.lhs, const_env, local_env), eval_value(self.rhs, const_env, local_env)
            if a == nil or b == nil then return pvm.once(no()) end
            return logic_const(self.op, a, b)
        end,
        [Tr.ExprCast] = function(self, const_env, local_env)
            local v = eval_value(self.value, const_env, local_env)
            if v == nil then return pvm.once(no()) end
            if pvm.classof(v) == Sem.ConstInt then return pvm.once(yes(Sem.ConstInt(self.ty, v.raw))) end
            if pvm.classof(v) == Sem.ConstFloat then return pvm.once(yes(Sem.ConstFloat(self.ty, v.raw))) end
            if pvm.classof(v) == Sem.ConstNil then return pvm.once(yes(Sem.ConstNil(self.ty))) end
            return pvm.once(yes(v))
        end,
        [Tr.ExprMachineCast] = function(self, const_env, local_env) return expr_const_class(Tr.ExprCast(self.h, C.SurfaceCast, self.ty, self.value), const_env, local_env) end,
        [Tr.ExprIntrinsic] = function() return pvm.once(no()) end,
        [Tr.ExprAddrOf] = function() return pvm.once(no()) end,
        [Tr.ExprDeref] = function() return pvm.once(no()) end,
        [Tr.ExprCall] = function() return pvm.once(no()) end,
        [Tr.ExprLen] = function() return pvm.once(no()) end,
        [Tr.ExprDot] = function() return pvm.once(no()) end,
        [Tr.ExprField] = function(self, const_env, local_env)
            local base = eval_value(self.base, const_env, local_env)
            if base == nil or pvm.classof(base) ~= Sem.ConstAgg then return pvm.once(no()) end
            local v = field_value(base.fields, self.field.field_name)
            if v == nil then return pvm.once(no()) end
            return pvm.once(yes(v))
        end,
        [Tr.ExprIndex] = function(self, const_env, local_env)
            local base = nil
            if pvm.classof(self.base) == Tr.IndexBaseView then return pvm.once(no()) end
            base = eval_value(self.base.base, const_env, local_env)
            local index = eval_value(self.index, const_env, local_env)
            local n = index and tonumber(int_raw(index))
            if base == nil or pvm.classof(base) ~= Sem.ConstArray or n == nil then return pvm.once(no()) end
            local v = base.elems[n + 1]
            if v == nil then return pvm.once(no()) end
            return pvm.once(yes(v))
        end,
        [Tr.ExprAgg] = function(self, const_env, local_env)
            local fields = {}
            for i = 1, #self.fields do
                local v = eval_value(self.fields[i].value, const_env, local_env)
                if v == nil then return pvm.once(no()) end
                fields[#fields + 1] = Sem.ConstFieldValue(self.fields[i].name, v)
            end
            return pvm.once(yes(Sem.ConstAgg(self.ty, fields)))
        end,
        [Tr.ExprArray] = function(self, const_env, local_env)
            local elems = {}
            for i = 1, #self.elems do
                local v = eval_value(self.elems[i], const_env, local_env)
                if v == nil then return pvm.once(no()) end
                elems[#elems + 1] = v
            end
            return pvm.once(yes(Sem.ConstArray(self.elem_ty, elems)))
        end,
        [Tr.ExprIf] = function(self, const_env, local_env)
            local cond = eval_value(self.cond, const_env, local_env)
            local b = cond and bool_value(cond)
            if b == nil then return pvm.once(no()) end
            if b then return expr_const_class(self.then_expr, const_env, local_env) end
            return expr_const_class(self.else_expr, const_env, local_env)
        end,
        [Tr.ExprSelect] = function(self, const_env, local_env)
            local cond = eval_value(self.cond, const_env, local_env)
            local b = cond and bool_value(cond)
            if b == nil then return pvm.once(no()) end
            if b then return expr_const_class(self.then_expr, const_env, local_env) end
            return expr_const_class(self.else_expr, const_env, local_env)
        end,
        [Tr.ExprSwitch] = function(self, const_env, local_env)
            local value = eval_value(self.value, const_env, local_env)
            if value == nil then return pvm.once(no()) end
            for i = 1, #self.arms do
                local key = switch_key_value(self.arms[i].key)
                if key == value or (type(key) == "string" and int_raw(value) == key) then
                    local stmt_result = eval_stmts(self.arms[i].body, const_env, local_env)
                    if pvm.classof(stmt_result) == Sem.ConstStmtFallsThrough then
                        return expr_const_class(self.arms[i].result, const_env, stmt_result.local_env)
                    end
                    return pvm.once(no())
                end
            end
            return expr_const_class(self.default_expr, const_env, local_env)
        end,
        [Tr.ExprControl] = function() return pvm.once(no()) end,
        [Tr.ExprBlock] = function(self, const_env, local_env)
            local result = eval_stmts(self.stmts, const_env, local_env)
            if pvm.classof(result) ~= Sem.ConstStmtFallsThrough then return pvm.once(no()) end
            return expr_const_class(self.result, const_env, result.local_env)
        end,
        [Tr.ExprClosure] = function() return pvm.once(no()) end,
        [Tr.ExprView] = function() return pvm.once(no()) end,
        [Tr.ExprLoad] = function() return pvm.once(no()) end,
        [Tr.ExprSlotValue] = function() return pvm.once(no()) end,
        [Tr.ExprUseExprFrag] = function() return pvm.once(no()) end,
    }, { args_cache = "last" })

    stmt_const_result = pvm.phase("moon2_sem_stmt_const_result", {
        [Tr.StmtLet] = function(self, const_env, local_env)
            local v = eval_value(self.init, const_env, local_env)
            if v == nil then return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end
            return pvm.once(Sem.ConstStmtFallsThrough(local_put(local_env, self.binding, v)))
        end,
        [Tr.StmtVar] = function(self, const_env, local_env)
            local v = eval_value(self.init, const_env, local_env)
            if v == nil then return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end
            return pvm.once(Sem.ConstStmtFallsThrough(local_put(local_env, self.binding, v)))
        end,
        [Tr.StmtSet] = function(_, _, local_env) return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end,
        [Tr.StmtExpr] = function(self, const_env, local_env) eval_expr(self.expr, const_env, local_env); return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end,
        [Tr.StmtAssert] = function(_, _, local_env) return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end,
        [Tr.StmtIf] = function(self, const_env, local_env)
            local cond = eval_value(self.cond, const_env, local_env)
            local b = cond and bool_value(cond)
            if b == nil then return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end
            if b then return pvm.once(eval_stmts(self.then_body, const_env, local_env)) end
            return pvm.once(eval_stmts(self.else_body, const_env, local_env))
        end,
        [Tr.StmtSwitch] = function(_, _, local_env) return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end,
        [Tr.StmtReturnVoid] = function(_, _, local_env) return pvm.once(Sem.ConstStmtReturnVoid(local_env)) end,
        [Tr.StmtReturnValue] = function(self, const_env, local_env)
            local v = eval_value(self.value, const_env, local_env)
            if v == nil then return pvm.once(Sem.ConstStmtReturnVoid(local_env)) end
            return pvm.once(Sem.ConstStmtReturnValue(local_env, v))
        end,
        [Tr.StmtJump] = function(self, _, local_env) return pvm.once(Sem.ConstStmtJump(local_env, self.target.name)) end,
        [Tr.StmtJumpCont] = function(_, _, local_env) return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end,
        [Tr.StmtYieldVoid] = function(_, _, local_env) return pvm.once(Sem.ConstStmtYieldVoid(local_env)) end,
        [Tr.StmtYieldValue] = function(self, const_env, local_env)
            local v = eval_value(self.value, const_env, local_env)
            if v == nil then return pvm.once(Sem.ConstStmtYieldVoid(local_env)) end
            return pvm.once(Sem.ConstStmtYieldValue(local_env, v))
        end,
        [Tr.StmtControl] = function(_, _, local_env) return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end,
        [Tr.StmtUseRegionSlot] = function(_, _, local_env) return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end,
        [Tr.StmtUseRegionFrag] = function(_, _, local_env) return pvm.once(Sem.ConstStmtFallsThrough(local_env)) end,
    }, { args_cache = "last" })

    local function empty_const_env() return B.ConstEnv({}) end
    local function empty_local_env() return Sem.ConstLocalEnv({}) end

    return {
        empty_const_env = empty_const_env,
        empty_local_env = empty_local_env,
        expr_type = expr_type,
        literal_const = literal_const,
        expr_const_class = expr_const_class,
        stmt_const_result = stmt_const_result,
        expr = function(expr, const_env, local_env) return pvm.one(expr_const_class(expr, const_env or empty_const_env(), local_env or empty_local_env())) end,
        value = function(expr, const_env, local_env) return const_value(pvm.one(expr_const_class(expr, const_env or empty_const_env(), local_env or empty_local_env()))) end,
        stmts = function(stmts, const_env, local_env) return eval_stmts(stmts, const_env or empty_const_env(), local_env or empty_local_env()) end,
    }
end

return M
