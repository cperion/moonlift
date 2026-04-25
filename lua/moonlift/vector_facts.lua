local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonliftSem
    local Vec = T.MoonliftVec

    local vector_expr
    local vector_stmt
    local vector_domain
    local vector_loop_facts
    local vector_loop_plan

    local function one_expr(expr, env)
        return pvm.one(vector_expr(expr, env))
    end

    local function one_stmt(stmt, env)
        return pvm.one(vector_stmt(stmt, env))
    end

    local function one_domain(domain)
        return pvm.one(vector_domain(domain))
    end

    local function one_loop_facts(loop)
        return pvm.one(vector_loop_facts(loop))
    end

    local function is_class(node, cls)
        return pvm.classof(node) == cls
    end

    local function expr_ty(expr)
        local cls = pvm.classof(expr)
        if cls == Sem.SemExprConstInt or cls == Sem.SemExprConstFloat or cls == Sem.SemExprNil then
            return expr.ty
        elseif cls == Sem.SemExprConstBool then
            return Sem.SemTBool
        elseif cls == Sem.SemExprBinding then
            return expr.binding.ty
        elseif expr.ty ~= nil then
            return expr.ty
        end
        return nil
    end

    local function binding_expr_is(expr, binding)
        return is_class(expr, Sem.SemExprBinding) and expr.binding == binding
    end

    local function expr_fact_reject(fact)
        if is_class(fact, Vec.VecExprRejected) then
            return fact.reject
        end
        return nil
    end

    local function stmt_reject(fact)
        if is_class(fact, Vec.VecStmtRejected) then
            return fact.reject
        end
        return nil
    end

    local function find_local(locals, binding)
        for i = #locals, 1, -1 do
            local local_fact = locals[i]
            if local_fact.binding == binding then
                return local_fact.expr
            end
        end
        return nil
    end

    local function append_local(locals, local_fact)
        local out = {}
        for i = 1, #locals do
            out[i] = locals[i]
        end
        out[#out + 1] = local_fact
        return out
    end

    local function with_local(env, local_fact)
        return Vec.VecEnv(env.index, append_local(env.locals, local_fact))
    end

    local function local_binding_from_let(stmt)
        return Sem.SemBindLocalValue(stmt.id, stmt.name, stmt.ty)
    end

    local function loop_index_binding(loop)
        return Sem.SemBindLoopIndex(loop.loop_id, loop.index_port.name, loop.index_port.ty)
    end

    local function loop_carry_binding(loop, carry)
        return Sem.SemBindLoopCarry(loop.loop_id, carry.port_id, carry.name, carry.ty)
    end

    local function combine_bin(op, self, env)
        local lhs = one_expr(self.lhs, env)
        local lhs_reject = expr_fact_reject(lhs)
        if lhs_reject ~= nil then
            return pvm.once(Vec.VecExprRejected(lhs_reject))
        end
        local rhs = one_expr(self.rhs, env)
        local rhs_reject = expr_fact_reject(rhs)
        if rhs_reject ~= nil then
            return pvm.once(Vec.VecExprRejected(rhs_reject))
        end
        return pvm.once(Vec.VecExprBin(op, lhs, rhs, self.ty))
    end

    vector_expr = pvm.phase("moonlift_vec_expr_fact", {
        [Sem.SemExprConstInt] = function(self)
            return pvm.once(Vec.VecExprInvariant(self, self.ty))
        end,
        [Sem.SemExprConstFloat] = function(self)
            return pvm.once(Vec.VecExprInvariant(self, self.ty))
        end,
        [Sem.SemExprConstBool] = function(self)
            return pvm.once(Vec.VecExprInvariant(self, Sem.SemTBool))
        end,
        [Sem.SemExprNil] = function(self)
            return pvm.once(Vec.VecExprInvariant(self, self.ty))
        end,
        [Sem.SemExprBinding] = function(self, env)
            if self.binding == env.index then
                return pvm.once(Vec.VecExprLaneIndex(self.binding, self.binding.ty))
            end
            local local_fact = find_local(env.locals, self.binding)
            if local_fact ~= nil then
                return pvm.once(local_fact)
            end
            return pvm.once(Vec.VecExprInvariant(self, self.binding.ty))
        end,
        [Sem.SemExprAdd] = function(self, env)
            return combine_bin(Vec.VecAdd, self, env)
        end,
        [Sem.SemExprSub] = function(self, env)
            return combine_bin(Vec.VecSub, self, env)
        end,
        [Sem.SemExprMul] = function(self, env)
            return combine_bin(Vec.VecMul, self, env)
        end,
        [Sem.SemExprBitAnd] = function(self, env)
            return combine_bin(Vec.VecBitAnd, self, env)
        end,
        [Sem.SemExprBitOr] = function(self, env)
            return combine_bin(Vec.VecBitOr, self, env)
        end,
        [Sem.SemExprBitXor] = function(self, env)
            return combine_bin(Vec.VecBitXor, self, env)
        end,
        [Sem.SemExprShl] = function(self, env)
            return combine_bin(Vec.VecShl, self, env)
        end,
        [Sem.SemExprLShr] = function(self, env)
            return combine_bin(Vec.VecLShr, self, env)
        end,
        [Sem.SemExprAShr] = function(self, env)
            return combine_bin(Vec.VecAShr, self, env)
        end,
        [Sem.SemExprCastTo] = function(self)
            return pvm.once(Vec.VecExprRejected(Vec.VecRejectExpr("cast vector facts are not implemented yet")))
        end,
        [Sem.SemExprIntrinsicCall] = function(self)
            return pvm.once(Vec.VecExprRejected(Vec.VecRejectExpr("intrinsic vector facts are not implemented yet")))
        end,
        [Sem.SemExprCall] = function(self)
            return pvm.once(Vec.VecExprRejected(Vec.VecRejectExpr("calls are not vectorizable facts yet")))
        end,
        [Sem.SemExprIf] = function(self)
            return pvm.once(Vec.VecExprRejected(Vec.VecRejectExpr("if-expr vector facts are not implemented yet")))
        end,
        [Sem.SemExprSwitch] = function(self)
            return pvm.once(Vec.VecExprRejected(Vec.VecRejectExpr("switch-expr vector facts are not implemented yet")))
        end,
    })

    local function update_reduction(loop, update, env)
        local carry
        for i = 1, #loop.carries do
            if loop.carries[i].port_id == update.port_id then
                carry = loop.carries[i]
                break
            end
        end
        if carry == nil then
            return nil, Vec.VecRejectUpdate("next update does not match a loop carry")
        end
        local carry_binding = loop_carry_binding(loop, carry)
        local expr = update.value
        if is_class(expr, Sem.SemExprAdd) then
            local value_expr
            if binding_expr_is(expr.lhs, carry_binding) then
                value_expr = expr.rhs
            elseif binding_expr_is(expr.rhs, carry_binding) then
                value_expr = expr.lhs
            else
                return nil, Vec.VecRejectUpdate("add update is not rooted in the carry")
            end
            local value_fact = one_expr(value_expr, env)
            local reject = expr_fact_reject(value_fact)
            if reject ~= nil then
                return nil, reject
            end
            return Vec.VecReductionAdd(carry, value_fact), nil
        end
        return nil, Vec.VecRejectUpdate("only add reductions are recognized in the initial vector fact pass")
    end

    vector_stmt = pvm.phase("moonlift_vec_stmt_fact", {
        [Sem.SemStmtLet] = function(self, env)
            local fact = one_expr(self.init, env)
            local reject = expr_fact_reject(fact)
            if reject ~= nil then
                return pvm.once(Vec.VecStmtRejected(reject))
            end
            return pvm.once(Vec.VecStmtLocal(Vec.VecLocalFact(local_binding_from_let(self), fact)))
        end,
        [Sem.SemStmtExpr] = function(self, env)
            local fact = one_expr(self.expr, env)
            local reject = expr_fact_reject(fact)
            if reject ~= nil then
                return pvm.once(Vec.VecStmtRejected(reject))
            end
            return pvm.once(Vec.VecStmtIgnored)
        end,
        [Sem.SemStmtAssert] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("assert in loop body is not vectorizable yet")))
        end,
        [Sem.SemStmtVar] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("mutable var in loop body is not vectorizable yet")))
        end,
        [Sem.SemStmtSet] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("stores are not vectorizable facts yet")))
        end,
        [Sem.SemStmtIf] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("if statement in loop body is not vectorizable yet")))
        end,
        [Sem.SemStmtSwitch] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("switch statement in loop body is not vectorizable yet")))
        end,
        [Sem.SemStmtLoop] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("nested loop vector facts are not implemented yet")))
        end,
        [Sem.SemStmtReturnValue] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("return in loop body is not vectorizable")))
        end,
        [Sem.SemStmtReturnVoid] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("return in loop body is not vectorizable")))
        end,
        [Sem.SemStmtBreak] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("break in loop body is not vectorizable yet")))
        end,
        [Sem.SemStmtBreakValue] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("break value in loop body is not vectorizable yet")))
        end,
        [Sem.SemStmtContinue] = function()
            return pvm.once(Vec.VecStmtRejected(Vec.VecRejectStmt("continue in loop body is not vectorizable yet")))
        end,
    })

    local function gather_body(loop, index_binding)
        local env = Vec.VecEnv(index_binding, {})
        local locals = {}
        local rejects = {}
        for i = 1, #loop.body do
            local fact = one_stmt(loop.body[i], env)
            local reject = stmt_reject(fact)
            if reject ~= nil then
                rejects[#rejects + 1] = reject
            elseif is_class(fact, Vec.VecStmtLocal) then
                locals[#locals + 1] = fact["local"]
                env = with_local(env, fact["local"])
            end
        end
        local reductions = {}
        for i = 1, #loop.next do
            local reduction, reject = update_reduction(loop, loop.next[i], env)
            if reject ~= nil then
                rejects[#rejects + 1] = reject
            elseif reduction ~= nil then
                reductions[#reductions + 1] = reduction
            end
        end
        return Vec.VecBodyFacts(locals, reductions, rejects)
    end

    vector_domain = pvm.phase("moonlift_vec_domain_fact", {
        [Sem.SemDomainRange] = function(self)
            return pvm.once(Vec.VecCountedDomain(Sem.SemExprConstInt(Sem.SemTIndex, "0"), self.stop))
        end,
        [Sem.SemDomainRange2] = function(self)
            return pvm.once(Vec.VecCountedDomain(self.start, self.stop))
        end,
        [Sem.SemDomainView] = function()
            return pvm.once(Vec.VecDomainRejected(Vec.VecRejectDomain("view domains need access/dependence facts before vectorization")))
        end,
        [Sem.SemDomainZipEq] = function()
            return pvm.once(Vec.VecDomainRejected(Vec.VecRejectDomain("zip domains need access/dependence facts before vectorization")))
        end,
    })

    vector_loop_facts = pvm.phase("moonlift_vec_loop_fact", {
        [Sem.SemOverStmt] = function(self)
            local domain = one_domain(self.domain)
            if is_class(domain, Vec.VecDomainRejected) then
                return pvm.once(Vec.VecLoopRejected(domain.reject))
            end
            local index_binding = loop_index_binding(self)
            local body = gather_body(self, index_binding)
            if #body.rejects > 0 then
                return pvm.once(Vec.VecLoopRejected(body.rejects[1]))
            end
            return pvm.once(Vec.VecCountedLoop(self.loop_id, index_binding, domain.start, domain.stop, body))
        end,
        [Sem.SemWhileStmt] = function()
            return pvm.once(Vec.VecLoopRejected(Vec.VecRejectLoopShape("while-loop counted-loop detection is not implemented yet")))
        end,
        [Sem.SemWhileExpr] = function()
            return pvm.once(Vec.VecLoopRejected(Vec.VecRejectLoopShape("expression-loop vector facts are not implemented yet")))
        end,
        [Sem.SemOverExpr] = function()
            return pvm.once(Vec.VecLoopRejected(Vec.VecRejectLoopShape("expression-loop vector facts are not implemented yet")))
        end,
    })

    vector_loop_plan = pvm.phase("moonlift_vec_loop_plan", {
        [Sem.SemOverStmt] = function(self, lanes)
            local facts = one_loop_facts(self)
            if is_class(facts, Vec.VecLoopRejected) then
                return pvm.once(Vec.VecNoPlan(facts.reject))
            end
            if #facts.body.reductions ~= 1 then
                return pvm.once(Vec.VecNoPlan(Vec.VecRejectPlan("initial vector planner requires exactly one add reduction")))
            end
            local reduction = facts.body.reductions[1]
            if not is_class(reduction, Vec.VecReductionAdd) then
                return pvm.once(Vec.VecNoPlan(Vec.VecRejectPlan("initial vector planner only supports add reductions")))
            end
            return pvm.once(Vec.VecAddReductionPlan(facts.loop_id, lanes, facts.index, facts.start, facts.stop, reduction.carry, reduction.value))
        end,
        [Sem.SemWhileStmt] = function(self, lanes)
            local facts = one_loop_facts(self)
            return pvm.once(Vec.VecNoPlan(facts.reject))
        end,
        [Sem.SemWhileExpr] = function(self, lanes)
            local facts = one_loop_facts(self)
            return pvm.once(Vec.VecNoPlan(facts.reject))
        end,
        [Sem.SemOverExpr] = function(self, lanes)
            local facts = one_loop_facts(self)
            return pvm.once(Vec.VecNoPlan(facts.reject))
        end,
    })

    return {
        vector_expr = vector_expr,
        vector_stmt = vector_stmt,
        vector_domain = vector_domain,
        vector_loop_facts = vector_loop_facts,
        vector_loop_plan = vector_loop_plan,
    }
end

return M
