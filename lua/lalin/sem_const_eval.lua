local bit = require("bit")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.sem_const_eval ~= nil then return T._lalin_api_cache.sem_const_eval end

    local C = T.LalinCore
    local Ty = T.LalinType
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Tr = T.LalinTree

    local function void_ty()
        return Ty.TScalar(C.ScalarVoid)
    end

    local function known(value)
        return Sem.ConstKnown(value)
    end

    local function not_foldable(reason)
        return Sem.ConstNotFoldable(reason)
    end

    local function rejected(reason)
        return Sem.ConstRejected(reason)
    end

    local function empty_const_env()
        return B.ConstEnv({})
    end

    local function empty_local_env()
        return Sem.ConstLocalEnv({})
    end

    local function input_for(const_env, local_env)
        return Sem.ConstEvalInput(const_env or empty_const_env(), local_env or empty_local_env())
    end

    local function with_local_env(input, local_env)
        return Sem.ConstEvalInput(input.const_env, local_env)
    end

    function Sem.ConstExprResult:sem_const_eval_value()
        return nil
    end

    function Sem.ConstKnown:sem_const_eval_value()
        return rawget(self, "value")
    end

    function Sem.ConstStmtFlow:sem_const_eval_fallthrough_env()
        return nil
    end

    function Sem.ConstFallsThrough:sem_const_eval_fallthrough_env()
        return self.env
    end

    function Sem.ConstValue:sem_const_eval_int_raw()
        return nil
    end

    function Sem.ConstInt:sem_const_eval_int_raw()
        return self.raw
    end

    function Sem.ConstValue:sem_const_eval_bool_value()
        return nil
    end

    function Sem.ConstBool:sem_const_eval_bool_value()
        return rawget(self, "value")
    end

    function Sem.ConstValue:sem_const_eval_same(other)
        return self == other
    end

    function Sem.ConstInt:sem_const_eval_same(other)
        return other ~= nil and other:sem_const_eval_int_raw() == self.raw
    end

    function Sem.ConstBool:sem_const_eval_same(other)
        local value = other ~= nil and other:sem_const_eval_bool_value() or nil
        return value ~= nil and value == rawget(self, "value")
    end

    local function result_value(result)
        return result:sem_const_eval_value()
    end

    local function expr_value(expr, input)
        return result_value(expr:sem_const_eval_expr(input))
    end

    local function local_lookup_result(env, binding)
        for i = #env.entries, 1, -1 do
            local entry = env.entries[i]
            if entry.binding == binding then return known(rawget(entry, "value")) end
        end
        return not_foldable("binding has no constant local value")
    end

    local function local_put(env, binding, value)
        local entries = {}
        for i = 1, #env.entries do entries[#entries + 1] = env.entries[i] end
        entries[#entries + 1] = Sem.ConstLocalEntry(binding, value)
        return Sem.ConstLocalEnv(entries)
    end

    local function number_string(n)
        if n == math.floor(n) then return tostring(n) end
        return tostring(n)
    end

    function Tr.ExprHeader:sem_const_eval_type()
        return void_ty()
    end

    function Tr.ExprTyped:sem_const_eval_type()
        return self.ty
    end

    function C.Literal:sem_const_eval_literal(ty)
        return not_foldable("literal is not foldable")
    end

    function C.LitInt:sem_const_eval_literal(ty)
        return known(Sem.ConstInt(ty, self.raw))
    end

    function C.LitFloat:sem_const_eval_literal(ty)
        return known(Sem.ConstFloat(ty, self.raw))
    end

    function C.LitBool:sem_const_eval_literal()
        return known(Sem.ConstBool(rawget(self, "value")))
    end

    function C.LitNil:sem_const_eval_literal(ty)
        return known(Sem.ConstNil(ty))
    end

    function C.UnaryOp:sem_const_eval_unary(value, ty)
        return not_foldable("unary op is not foldable")
    end

    function C.UnaryNeg:sem_const_eval_unary(value, ty)
        local raw = value:sem_const_eval_int_raw()
        local n = raw ~= nil and tonumber(raw) or nil
        if n == nil then return not_foldable("unary neg requires integer constant") end
        return known(Sem.ConstInt(ty, number_string(-n)))
    end

    function C.UnaryNot:sem_const_eval_unary(value)
        local b = value:sem_const_eval_bool_value()
        if b == nil then return not_foldable("logical not requires boolean constant") end
        return known(Sem.ConstBool(not b))
    end

    function C.UnaryBitNot:sem_const_eval_unary(value, ty)
        local raw = value:sem_const_eval_int_raw()
        local n = raw ~= nil and tonumber(raw) or nil
        if n == nil then return not_foldable("bitwise not requires integer constant") end
        return known(Sem.ConstInt(ty, tostring(bit.bnot(n))))
    end

    local function int_pair(a, b)
        local x = tonumber(a:sem_const_eval_int_raw())
        local y = tonumber(b:sem_const_eval_int_raw())
        return x, y
    end

    function C.BinaryOp:sem_const_eval_binary(a, b, ty)
        return not_foldable("binary op is not foldable")
    end

    function C.BinAdd:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("add requires integer constants") end
        return known(Sem.ConstInt(ty, number_string(x + y)))
    end

    function C.BinSub:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("sub requires integer constants") end
        return known(Sem.ConstInt(ty, number_string(x - y)))
    end

    function C.BinMul:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("mul requires integer constants") end
        return known(Sem.ConstInt(ty, number_string(x * y)))
    end

    function C.BinDiv:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil or y == 0 then return not_foldable("div requires non-zero integer constants") end
        return known(Sem.ConstInt(ty, number_string(math.floor(x / y))))
    end

    function C.BinRem:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil or y == 0 then return not_foldable("rem requires non-zero integer constants") end
        return known(Sem.ConstInt(ty, number_string(x % y)))
    end

    function C.BinBitAnd:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("bitand requires integer constants") end
        return known(Sem.ConstInt(ty, tostring(bit.band(x, y))))
    end

    function C.BinBitOr:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("bitor requires integer constants") end
        return known(Sem.ConstInt(ty, tostring(bit.bor(x, y))))
    end

    function C.BinBitXor:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("bitxor requires integer constants") end
        return known(Sem.ConstInt(ty, tostring(bit.bxor(x, y))))
    end

    function C.BinShl:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("shl requires integer constants") end
        return known(Sem.ConstInt(ty, tostring(bit.lshift(x, y))))
    end

    function C.BinLShr:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("lshr requires integer constants") end
        return known(Sem.ConstInt(ty, tostring(bit.rshift(x, y))))
    end

    function C.BinAShr:sem_const_eval_binary(a, b, ty)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("ashr requires integer constants") end
        return known(Sem.ConstInt(ty, tostring(bit.arshift(x, y))))
    end

    function C.CmpOp:sem_const_eval_compare(a, b)
        return not_foldable("compare op is not foldable")
    end

    function C.CmpEq:sem_const_eval_compare(a, b)
        return known(Sem.ConstBool(a:sem_const_eval_same(b)))
    end

    function C.CmpNe:sem_const_eval_compare(a, b)
        return known(Sem.ConstBool(not a:sem_const_eval_same(b)))
    end

    function C.CmpLt:sem_const_eval_compare(a, b)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("lt requires integer constants") end
        return known(Sem.ConstBool(x < y))
    end

    function C.CmpLe:sem_const_eval_compare(a, b)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("le requires integer constants") end
        return known(Sem.ConstBool(x <= y))
    end

    function C.CmpGt:sem_const_eval_compare(a, b)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("gt requires integer constants") end
        return known(Sem.ConstBool(x > y))
    end

    function C.CmpGe:sem_const_eval_compare(a, b)
        local x, y = int_pair(a, b)
        if x == nil or y == nil then return not_foldable("ge requires integer constants") end
        return known(Sem.ConstBool(x >= y))
    end

    function C.LogicOp:sem_const_eval_logic(a, b)
        return not_foldable("logic op is not foldable")
    end

    function C.LogicAnd:sem_const_eval_logic(a, b)
        local x, y = a:sem_const_eval_bool_value(), b:sem_const_eval_bool_value()
        if x == nil or y == nil then return not_foldable("and requires boolean constants") end
        return known(Sem.ConstBool(x and y))
    end

    function C.LogicOr:sem_const_eval_logic(a, b)
        local x, y = a:sem_const_eval_bool_value(), b:sem_const_eval_bool_value()
        if x == nil or y == nil then return not_foldable("or requires boolean constants") end
        return known(Sem.ConstBool(x or y))
    end

    function B.BindingRole:sem_const_eval_global_const(input)
        return not_foldable("binding is not a global constant")
    end

    function B.BindingRoleGlobalConst:sem_const_eval_global_const(input)
        for i = 1, #input.const_env.entries do
            local entry = input.const_env.entries[i]
            if entry.module_name == self.module_name and entry.item_name == self.item_name then
                return rawget(entry, "value"):sem_const_eval_expr(with_local_env(input, empty_local_env()))
            end
        end
        return not_foldable("global constant has no entry")
    end

    function B.ValueRef:sem_const_eval_ref(input)
        return not_foldable("value reference is not foldable")
    end

    function B.ValueRefBinding:sem_const_eval_ref(input)
        local local_result = local_lookup_result(input.local_env, self.binding)
        local local_value = result_value(local_result)
        if local_value ~= nil then return local_result end
        return self.binding.role:sem_const_eval_global_const(input)
    end

    function Tr.SwitchKey:sem_const_eval_matches_value(value, input)
        return false
    end

    function Tr.SwitchKeyInt:sem_const_eval_matches_value(value)
        return value:sem_const_eval_int_raw() == self.raw
    end

    function Tr.SwitchKeyBool:sem_const_eval_matches_value(value)
        local b = value:sem_const_eval_bool_value()
        return b ~= nil and b == rawget(self, "value")
    end

    function Tr.SwitchKeyExpr:sem_const_eval_matches_value(value, input)
        local key = expr_value(self.expr, input)
        return key ~= nil and key:sem_const_eval_same(value)
    end

    function Tr.IndexBase:sem_const_eval_base_value(input)
        return not_foldable("index base is not a foldable expression")
    end

    function Tr.IndexBaseExpr:sem_const_eval_base_value(input)
        return self.base:sem_const_eval_expr(input)
    end

    function Tr.Expr:sem_const_eval_expr(input)
        return not_foldable("expression is not foldable")
    end

    function Tr.ExprLit:sem_const_eval_expr(input)
        return rawget(self, "value"):sem_const_eval_literal(self.h:sem_const_eval_type())
    end

    function Tr.ExprRef:sem_const_eval_expr(input)
        return self.ref:sem_const_eval_ref(input)
    end

    function Tr.ExprUnary:sem_const_eval_expr(input)
        local value = expr_value(rawget(self, "value"), input)
        if value == nil then return not_foldable("unary operand is not constant") end
        return self.op:sem_const_eval_unary(value, self.h:sem_const_eval_type())
    end

    function Tr.ExprBinary:sem_const_eval_expr(input)
        local lhs = expr_value(self.lhs, input)
        local rhs = expr_value(self.rhs, input)
        if lhs == nil or rhs == nil then return not_foldable("binary operands are not constant") end
        return self.op:sem_const_eval_binary(lhs, rhs, self.h:sem_const_eval_type())
    end

    function Tr.ExprCompare:sem_const_eval_expr(input)
        local lhs = expr_value(self.lhs, input)
        local rhs = expr_value(self.rhs, input)
        if lhs == nil or rhs == nil then return not_foldable("compare operands are not constant") end
        return self.op:sem_const_eval_compare(lhs, rhs)
    end

    function Tr.ExprLogic:sem_const_eval_expr(input)
        local lhs = expr_value(self.lhs, input)
        local rhs = expr_value(self.rhs, input)
        if lhs == nil or rhs == nil then return not_foldable("logic operands are not constant") end
        return self.op:sem_const_eval_logic(lhs, rhs)
    end

    function Tr.ExprCast:sem_const_eval_expr(input)
        local value = expr_value(rawget(self, "value"), input)
        if value == nil then return not_foldable("cast operand is not constant") end
        return value:sem_const_eval_cast_to(self.ty)
    end

    function Sem.ConstValue:sem_const_eval_cast_to(ty)
        return known(self)
    end

    function Sem.ConstInt:sem_const_eval_cast_to(ty)
        return known(Sem.ConstInt(ty, self.raw))
    end

    function Sem.ConstFloat:sem_const_eval_cast_to(ty)
        return known(Sem.ConstFloat(ty, self.raw))
    end

    function Sem.ConstNil:sem_const_eval_cast_to(ty)
        return known(Sem.ConstNil(ty))
    end

    function Tr.ExprMachineCast:sem_const_eval_expr(input)
        return Tr.ExprCast(self.h, C.SurfaceCast, self.ty, rawget(self, "value")):sem_const_eval_expr(input)
    end

    function Tr.ExprField:sem_const_eval_expr(input)
        local base = expr_value(self.base, input)
        if base == nil then return not_foldable("field base is not constant") end
        return base:sem_const_eval_field(self.field.field_name)
    end

    function Sem.ConstValue:sem_const_eval_field(name)
        return not_foldable("constant has no fields")
    end

    function Sem.ConstAgg:sem_const_eval_field(name)
        for i = 1, #self.fields do
            if self.fields[i].name == name then return known(rawget(self.fields[i], "value")) end
        end
        return not_foldable("constant aggregate has no requested field")
    end

    function Tr.ExprIndex:sem_const_eval_expr(input)
        local base = result_value(self.base:sem_const_eval_base_value(input))
        local index = expr_value(self.index, input)
        if base == nil or index == nil then return not_foldable("index operands are not constant") end
        return base:sem_const_eval_index(index)
    end

    function Sem.ConstValue:sem_const_eval_index(index)
        return not_foldable("constant is not indexable")
    end

    function Sem.ConstArray:sem_const_eval_index(index)
        local raw = index:sem_const_eval_int_raw()
        local n = raw ~= nil and tonumber(raw) or nil
        if n == nil then return not_foldable("constant array index is not integer") end
        local value = self.elems[n + 1]
        if value == nil then return not_foldable("constant array index is out of bounds") end
        return known(value)
    end

    function Tr.ExprAgg:sem_const_eval_expr(input)
        local fields = {}
        for i = 1, #self.fields do
            local value = expr_value(rawget(self.fields[i], "value"), input)
            if value == nil then return not_foldable("aggregate field is not constant") end
            fields[#fields + 1] = Sem.ConstFieldValue(self.fields[i].name, value)
        end
        return known(Sem.ConstAgg(self.ty, fields))
    end

    function Tr.ExprArray:sem_const_eval_expr(input)
        local elems = {}
        for i = 1, #self.elems do
            local value = expr_value(self.elems[i], input)
            if value == nil then return not_foldable("array element is not constant") end
            elems[#elems + 1] = value
        end
        return known(Sem.ConstArray(self.elem_ty, elems))
    end

    function Tr.ExprIf:sem_const_eval_expr(input)
        local cond = expr_value(self.cond, input)
        local b = nil
        if cond ~= nil then b = cond:sem_const_eval_bool_value() end
        if b == nil then return not_foldable("if condition is not constant") end
        return (b and self.then_expr or self.else_expr):sem_const_eval_expr(input)
    end

    function Tr.ExprSelect:sem_const_eval_expr(input)
        local cond = expr_value(self.cond, input)
        local b = nil
        if cond ~= nil then b = cond:sem_const_eval_bool_value() end
        if b == nil then return not_foldable("select condition is not constant") end
        return (b and self.then_expr or self.else_expr):sem_const_eval_expr(input)
    end

    local function eval_stmts(stmts, input)
        local current = input.local_env
        for i = 1, #(stmts or {}) do
            local flow = stmts[i]:sem_const_eval_stmt(with_local_env(input, current))
            local next_env = flow:sem_const_eval_fallthrough_env()
            if next_env == nil then return flow end
            current = next_env
        end
        return Sem.ConstFallsThrough(current)
    end

    function Tr.ExprSwitch:sem_const_eval_expr(input)
        local value = expr_value(rawget(self, "value"), input)
        if value == nil then return not_foldable("switch value is not constant") end
        for i = 1, #self.arms do
            local arm = self.arms[i]
            if arm.key:sem_const_eval_matches_value(value, input) then
                local flow = eval_stmts(arm.body, input)
                local env = flow:sem_const_eval_fallthrough_env()
                if env == nil then return not_foldable("matching switch arm does not fall through") end
                return arm.result:sem_const_eval_expr(with_local_env(input, env))
            end
        end
        return self.default_expr:sem_const_eval_expr(input)
    end

    function Tr.ExprBlock:sem_const_eval_expr(input)
        local flow = eval_stmts(self.stmts, input)
        local env = flow:sem_const_eval_fallthrough_env()
        if env == nil then return not_foldable("block statements do not fall through") end
        return self.result:sem_const_eval_expr(with_local_env(input, env))
    end

    function Tr.Stmt:sem_const_eval_stmt(input)
        return Sem.ConstFallsThrough(input.local_env)
    end

    function Tr.StmtLet:sem_const_eval_stmt(input)
        local value = expr_value(self.init, input)
        if value == nil then return Sem.ConstFallsThrough(input.local_env) end
        return Sem.ConstFallsThrough(local_put(input.local_env, self.binding, value))
    end

    function Tr.StmtVar:sem_const_eval_stmt(input)
        local value = expr_value(self.init, input)
        if value == nil then return Sem.ConstFallsThrough(input.local_env) end
        return Sem.ConstFallsThrough(local_put(input.local_env, self.binding, value))
    end

    function Tr.StmtExpr:sem_const_eval_stmt(input)
        self.expr:sem_const_eval_expr(input)
        return Sem.ConstFallsThrough(input.local_env)
    end

    function Tr.StmtIf:sem_const_eval_stmt(input)
        local cond = expr_value(self.cond, input)
        local b = nil
        if cond ~= nil then b = cond:sem_const_eval_bool_value() end
        if b == nil then return Sem.ConstFallsThrough(input.local_env) end
        return eval_stmts(b and self.then_body or self.else_body, input)
    end

    function Tr.StmtReturnVoid:sem_const_eval_stmt(input)
        return Sem.ConstReturnVoid(input.local_env)
    end

    function Tr.StmtReturnValue:sem_const_eval_stmt(input)
        local value = expr_value(rawget(self, "value"), input)
        if value == nil then return Sem.ConstReturnVoid(input.local_env) end
        return Sem.ConstReturnValue(input.local_env, value)
    end

    function Tr.StmtJump:sem_const_eval_stmt(input)
        return Sem.ConstJump(input.local_env, self.target.name)
    end

    function Tr.StmtYieldVoid:sem_const_eval_stmt(input)
        return Sem.ConstYieldVoid(input.local_env)
    end

    function Tr.StmtYieldValue:sem_const_eval_stmt(input)
        local value = expr_value(rawget(self, "value"), input)
        if value == nil then return Sem.ConstYieldVoid(input.local_env) end
        return Sem.ConstYieldValue(input.local_env, value)
    end

    local api = {}

    api.empty_const_env = empty_const_env
    api.empty_local_env = empty_local_env
    api.input = input_for

    api.expr = function(expr, const_env, local_env)
        return expr:sem_const_eval_expr(input_for(const_env, local_env))
    end

    api.value = function(expr, const_env, local_env)
        return result_value(api.expr(expr, const_env, local_env))
    end

    api.stmts = function(stmts, const_env, local_env)
        return eval_stmts(stmts, input_for(const_env, local_env))
    end

    api.expr_type = function(expr_header)
        return expr_header:sem_const_eval_type()
    end

    api.literal_const = function(literal, ty)
        return literal:sem_const_eval_literal(ty or void_ty())
    end

    api.expr_const_class = api.expr
    api.stmt_const_result = function(stmt, const_env, local_env)
        return stmt:sem_const_eval_stmt(input_for(const_env, local_env))
    end

    T._lalin_api_cache.sem_const_eval = api
    return api
end

return bind_context
