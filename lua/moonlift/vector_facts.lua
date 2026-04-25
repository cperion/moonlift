local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonliftSem
    local Vec = T.MoonliftVec

    local vector_expr
    local vector_stmt
    local vector_domain
    local vector_loop_facts
    local vector_loop_decision
    local vector_func
    local vector_module

    local function is_class(node, cls)
        return pvm.classof(node) == cls
    end

    local function append_all(out, src)
        for i = 1, #src do out[#out + 1] = src[i] end
        return out
    end

    local function copy_append(a, b)
        local out = {}
        append_all(out, a)
        append_all(out, b)
        return out
    end

    local function expr_id(text)
        return Vec.VecExprId(text)
    end

    local function loop_id(text)
        return Vec.VecLoopId(text)
    end

    local function sem_ty_to_elem(ty)
        if ty == Sem.SemTBool then return Vec.VecElemBool end
        if ty == Sem.SemTI8 then return Vec.VecElemI8 end
        if ty == Sem.SemTI16 then return Vec.VecElemI16 end
        if ty == Sem.SemTI32 then return Vec.VecElemI32 end
        if ty == Sem.SemTI64 then return Vec.VecElemI64 end
        if ty == Sem.SemTU8 then return Vec.VecElemU8 end
        if ty == Sem.SemTU16 then return Vec.VecElemU16 end
        if ty == Sem.SemTU32 then return Vec.VecElemU32 end
        if ty == Sem.SemTU64 then return Vec.VecElemU64 end
        if ty == Sem.SemTF32 then return Vec.VecElemF32 end
        if ty == Sem.SemTF64 then return Vec.VecElemF64 end
        if ty == Sem.SemTRawPtr then return Vec.VecElemPtr end
        if pvm.classof(ty) == Sem.SemTPtrTo then return Vec.VecElemPtr end
        if ty == Sem.SemTIndex then return Vec.VecElemIndex end
        return nil
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

    local function find_local(locals, binding)
        for i = #locals, 1, -1 do
            local local_fact = locals[i]
            if local_fact.binding == binding then
                return local_fact
            end
        end
        return nil
    end

    local function append_local(locals, local_fact)
        local out = {}
        for i = 1, #locals do out[i] = locals[i] end
        out[#out + 1] = local_fact
        return out
    end

    local function with_local(env, local_fact)
        return Vec.VecExprEnv(env.index, append_local(env.locals, local_fact))
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

    local function one_expr(expr, env, id_text)
        return pvm.one(vector_expr(expr, env, id_text))
    end

    local function one_stmt(stmt, env, id_text)
        return pvm.one(vector_stmt(stmt, env, id_text))
    end

    local function one_domain(domain, id_text)
        return pvm.one(vector_domain(domain, id_text))
    end

    local function one_loop_facts(loop)
        return pvm.one(vector_loop_facts(loop))
    end

    local function binding_expr_is(expr, binding)
        return is_class(expr, Sem.SemExprBinding) and expr.binding == binding
    end

    local function result_rejected(id, reject, ty)
        return Vec.VecExprResult(id, { Vec.VecExprRejected(id, reject) }, {}, {}, { reject }, ty or Sem.SemTIndex)
    end

    local function combine_unary(op, self, env, id_text)
        local id = expr_id(id_text)
        local value = one_expr(self.value, env, id_text .. ".value")
        if #value.rejects > 0 then
            return Vec.VecExprResult(id, value.facts, value.memory, value.ranges, value.rejects, self.ty)
        end
        local facts = copy_append(value.facts, { Vec.VecExprUnary(id, op, value.value, self.ty) })
        return Vec.VecExprResult(id, facts, value.memory, value.ranges, {}, self.ty)
    end

    local function const_int_value(result)
        for i = 1, #result.facts do
            local fact = result.facts[i]
            if fact.id == result.value
                and (is_class(fact, Vec.VecExprConst) or is_class(fact, Vec.VecExprInvariant))
                and is_class(fact.expr, Sem.SemExprConstInt) then
                return tonumber(fact.expr.raw), fact.expr.raw
            end
        end
        return nil, nil
    end

    local function combine_bin(op, self, env, id_text)
        local id = expr_id(id_text)
        local lhs = one_expr(self.lhs, env, id_text .. ".lhs")
        local rhs = one_expr(self.rhs, env, id_text .. ".rhs")
        local facts = copy_append(lhs.facts, rhs.facts)
        local memory = copy_append(lhs.memory, rhs.memory)
        local ranges = copy_append(lhs.ranges, rhs.ranges)
        local rejects = copy_append(lhs.rejects, rhs.rejects)
        if #rejects > 0 then
            return Vec.VecExprResult(id, facts, memory, ranges, rejects, self.ty)
        end
        facts[#facts + 1] = Vec.VecExprBin(id, op, lhs.value, rhs.value, self.ty)
        if op == Vec.VecBitAnd then
            local _, lhs_raw = const_int_value(lhs)
            local _, rhs_raw = const_int_value(rhs)
            local raw = lhs_raw or rhs_raw
            if raw ~= nil then
                ranges[#ranges + 1] = Vec.VecRangeBitAnd(id, raw, raw)
            end
        end
        return Vec.VecExprResult(id, facts, memory, ranges, {}, self.ty)
    end

    vector_expr = pvm.phase("moonlift_vec_expr", {
        [Sem.SemExprConstInt] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(Vec.VecExprResult(id, { Vec.VecExprConst(id, self, self.ty) }, {}, {}, {}, self.ty))
        end,
        [Sem.SemExprConstFloat] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(Vec.VecExprResult(id, { Vec.VecExprConst(id, self, self.ty) }, {}, {}, {}, self.ty))
        end,
        [Sem.SemExprConstBool] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(Vec.VecExprResult(id, { Vec.VecExprConst(id, self, Sem.SemTBool) }, {}, {}, {}, Sem.SemTBool))
        end,
        [Sem.SemExprNil] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(Vec.VecExprResult(id, { Vec.VecExprConst(id, self, self.ty) }, {}, {}, {}, self.ty))
        end,
        [Sem.SemExprBinding] = function(self, env, id_text)
            local id = expr_id(id_text)
            if self.binding == env.index then
                return pvm.once(Vec.VecExprResult(id, { Vec.VecExprLaneIndex(id, self.binding, self.binding.ty) }, {}, {}, {}, self.binding.ty))
            end
            local local_fact = find_local(env.locals, self.binding)
            if local_fact ~= nil then
                return pvm.once(Vec.VecExprResult(id, { Vec.VecExprLocal(id, self.binding, local_fact.value, self.binding.ty) }, {}, {}, {}, self.binding.ty))
            end
            return pvm.once(Vec.VecExprResult(id, { Vec.VecExprInvariant(id, self, self.binding.ty) }, {}, {}, {}, self.binding.ty))
        end,
        [Sem.SemExprNeg] = function(self, env, id_text) return pvm.once(combine_unary(Vec.VecNeg, self, env, id_text)) end,
        [Sem.SemExprNot] = function(self, env, id_text) return pvm.once(combine_unary(Vec.VecNot, self, env, id_text)) end,
        [Sem.SemExprBNot] = function(self, env, id_text) return pvm.once(combine_unary(Vec.VecBitNot, self, env, id_text)) end,
        [Sem.SemExprAdd] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecAdd, self, env, id_text)) end,
        [Sem.SemExprSub] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecSub, self, env, id_text)) end,
        [Sem.SemExprMul] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecMul, self, env, id_text)) end,
        [Sem.SemExprRem] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecRem, self, env, id_text)) end,
        [Sem.SemExprBitAnd] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecBitAnd, self, env, id_text)) end,
        [Sem.SemExprBitOr] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecBitOr, self, env, id_text)) end,
        [Sem.SemExprBitXor] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecBitXor, self, env, id_text)) end,
        [Sem.SemExprShl] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecShl, self, env, id_text)) end,
        [Sem.SemExprLShr] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecLShr, self, env, id_text)) end,
        [Sem.SemExprAShr] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecAShr, self, env, id_text)) end,
        [Sem.SemExprEq] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecEq, self, env, id_text)) end,
        [Sem.SemExprNe] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecNe, self, env, id_text)) end,
        [Sem.SemExprLt] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecLt, self, env, id_text)) end,
        [Sem.SemExprLe] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecLe, self, env, id_text)) end,
        [Sem.SemExprGt] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecGt, self, env, id_text)) end,
        [Sem.SemExprGe] = function(self, env, id_text) return pvm.once(combine_bin(Vec.VecGe, self, env, id_text)) end,
        [Sem.SemExprSelect] = function(self, env, id_text)
            local id = expr_id(id_text)
            local cond = one_expr(self.cond, env, id_text .. ".cond")
            local tv = one_expr(self.then_value, env, id_text .. ".then")
            local ev = one_expr(self.else_value, env, id_text .. ".else")
            local facts, memory, ranges, rejects = {}, {}, {}, {}
            append_all(facts, cond.facts); append_all(facts, tv.facts); append_all(facts, ev.facts)
            append_all(memory, cond.memory); append_all(memory, tv.memory); append_all(memory, ev.memory)
            append_all(ranges, cond.ranges); append_all(ranges, tv.ranges); append_all(ranges, ev.ranges)
            append_all(rejects, cond.rejects); append_all(rejects, tv.rejects); append_all(rejects, ev.rejects)
            if #rejects == 0 then facts[#facts + 1] = Vec.VecExprSelect(id, cond.value, tv.value, ev.value, self.ty) end
            return pvm.once(Vec.VecExprResult(id, facts, memory, ranges, rejects, self.ty))
        end,
        [Sem.SemExprIndex] = function(self, env, id_text)
            local id = expr_id(id_text)
            local index = one_expr(self.index, env, id_text .. ".index")
            local facts, memory, ranges, rejects = {}, {}, {}, {}
            append_all(facts, index.facts)
            append_all(memory, index.memory)
            append_all(ranges, index.ranges)
            append_all(rejects, index.rejects)
            local access_id = Vec.VecAccessId(id_text .. ".access")
            if not is_class(self.base, Sem.SemIndexBaseView) then
                local reject = Vec.VecRejectUnsupportedMemory(access_id, "only view-backed index loads are vectorizable initially")
                rejects[#rejects + 1] = reject
                facts[#facts + 1] = Vec.VecExprRejected(id, reject)
                return pvm.once(Vec.VecExprResult(id, facts, memory, ranges, rejects, self.ty))
            end
            local view = self.base.view
            local vcls = pvm.classof(view)
            local base_expr, pattern
            if vcls == Sem.SemViewContiguous then
                base_expr = view.data
                pattern = Vec.VecAccessContiguous
            elseif vcls == Sem.SemViewStrided then
                base_expr = view.data
                if is_class(view.stride, Sem.SemExprConstInt) then
                    pattern = Vec.VecAccessStrided(tonumber(view.stride.raw) or 1)
                else
                    local reject = Vec.VecRejectUnsupportedMemory(access_id, "dynamic strided vector loads are not implemented yet")
                    rejects[#rejects + 1] = reject
                    facts[#facts + 1] = Vec.VecExprRejected(id, reject)
                    return pvm.once(Vec.VecExprResult(id, facts, memory, ranges, rejects, self.ty))
                end
            else
                local reject = Vec.VecRejectUnsupportedMemory(access_id, "only contiguous/constant-strided views are vectorizable initially")
                rejects[#rejects + 1] = reject
                facts[#facts + 1] = Vec.VecExprRejected(id, reject)
                return pvm.once(Vec.VecExprResult(id, facts, memory, ranges, rejects, self.ty))
            end
            local bounds_reject = Vec.VecRejectUnsupportedMemory(access_id, "bounds proof is not connected yet")
            local access = Vec.VecMemoryAccess(access_id, Vec.VecAccessLoad, base_expr, index.value, self.ty, pattern, Vec.VecAlignmentUnknown, Vec.VecBoundsUnknown(bounds_reject))
            memory[#memory + 1] = access
            facts[#facts + 1] = Vec.VecExprLoad(id, access_id, self.ty)
            return pvm.once(Vec.VecExprResult(id, facts, memory, ranges, rejects, self.ty))
        end,
        [Sem.SemExprCastTo] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(result_rejected(id, Vec.VecRejectUnsupportedExpr(id, "cast vector facts are not implemented yet"), self.ty))
        end,
        [Sem.SemExprIntrinsicCall] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(result_rejected(id, Vec.VecRejectUnsupportedExpr(id, "intrinsic vector facts are not implemented yet"), self.ty))
        end,
        [Sem.SemExprCall] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(result_rejected(id, Vec.VecRejectUnsupportedExpr(id, "calls are not vectorizable facts yet"), self.ty))
        end,
        [Sem.SemExprIf] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(result_rejected(id, Vec.VecRejectUnsupportedExpr(id, "if-expr vector facts are not implemented yet"), self.ty))
        end,
        [Sem.SemExprSwitch] = function(self, env, id_text)
            local id = expr_id(id_text)
            return pvm.once(result_rejected(id, Vec.VecRejectUnsupportedExpr(id, "switch-expr vector facts are not implemented yet"), self.ty))
        end,
    })

    vector_stmt = pvm.phase("moonlift_vec_stmt", {
        [Sem.SemStmtLet] = function(self, env, id_text)
            local result = one_expr(self.init, env, id_text .. ".init")
            local local_fact = Vec.VecLocalFact(local_binding_from_let(self), result.value, self.ty)
            return pvm.once(Vec.VecStmtLocal(local_fact, result.facts, result.memory, result.ranges, result.rejects))
        end,
        [Sem.SemStmtExpr] = function(self, env, id_text)
            local result = one_expr(self.expr, env, id_text .. ".expr")
            return pvm.once(Vec.VecStmtIgnored(result.facts, result.memory, result.ranges, result.rejects))
        end,
        [Sem.SemStmtAssert] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "assert in loop body is not vectorizable yet") }))
        end,
        [Sem.SemStmtVar] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "mutable var in loop body is not vectorizable yet") }))
        end,
        [Sem.SemStmtSet] = function(self, env, id_text)
            local access_id = Vec.VecAccessId(id_text .. ".store")
            if not is_class(self.place, Sem.SemPlaceIndex) or not is_class(self.place.base, Sem.SemIndexBaseView) then
                return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "only view index stores are vectorizable initially") }))
            end
            local view = self.place.base.view
            local vcls = pvm.classof(view)
            local base_expr, pattern
            if vcls == Sem.SemViewContiguous then
                base_expr = view.data
                pattern = Vec.VecAccessContiguous
            else
                return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedMemory(access_id, "only contiguous view stores are vectorizable initially") }))
            end
            local index = one_expr(self.place.index, env, id_text .. ".index")
            local value = one_expr(self.value, env, id_text .. ".value")
            local facts, memory, ranges, rejects = {}, {}, {}, {}
            append_all(facts, index.facts); append_all(facts, value.facts)
            append_all(memory, index.memory); append_all(memory, value.memory)
            append_all(ranges, index.ranges); append_all(ranges, value.ranges)
            append_all(rejects, index.rejects); append_all(rejects, value.rejects)
            local bounds_reject = Vec.VecRejectUnsupportedMemory(access_id, "bounds proof is not connected yet")
            local access = Vec.VecMemoryAccess(access_id, Vec.VecAccessStore, base_expr, index.value, self.place.ty, pattern, Vec.VecAlignmentUnknown, Vec.VecBoundsUnknown(bounds_reject))
            memory[#memory + 1] = access
            local store = Vec.VecStoreFact(access, value.value)
            return pvm.once(Vec.VecStmtStore(store, facts, memory, ranges, rejects))
        end,
        [Sem.SemStmtIf] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "if statement in loop body is not vectorizable yet") }))
        end,
        [Sem.SemStmtSwitch] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "switch statement in loop body is not vectorizable yet") }))
        end,
        [Sem.SemStmtLoop] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "nested loop vector facts are not implemented yet") }))
        end,
        [Sem.SemStmtReturnValue] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "return in loop body is not vectorizable") }))
        end,
        [Sem.SemStmtReturnVoid] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "return in loop body is not vectorizable") }))
        end,
        [Sem.SemStmtBreak] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "break in loop body is not vectorizable yet") }))
        end,
        [Sem.SemStmtBreakValue] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "break value in loop body is not vectorizable yet") }))
        end,
        [Sem.SemStmtContinue] = function(self, env, id_text)
            return pvm.once(Vec.VecStmtIgnored({}, {}, {}, { Vec.VecRejectUnsupportedStmt(id_text, "continue in loop body is not vectorizable yet") }))
        end,
    })

    local function gather_body(loop, index_binding)
        local env = Vec.VecExprEnv(index_binding, {})
        local locals, stores, expr_facts, memory, ranges, rejects = {}, {}, {}, {}, {}, {}
        for i = 1, #loop.body do
            local stmt = one_stmt(loop.body[i], env, loop.loop_id .. ".body." .. i)
            append_all(expr_facts, stmt.facts)
            append_all(memory, stmt.memory)
            append_all(ranges, stmt.ranges)
            append_all(rejects, stmt.rejects)
            if is_class(stmt, Vec.VecStmtLocal) then
                locals[#locals + 1] = stmt["local"]
                env = with_local(env, stmt["local"])
            elseif is_class(stmt, Vec.VecStmtStore) then
                stores[#stores + 1] = stmt.store
            end
        end
        return env, locals, stores, expr_facts, memory, ranges, rejects
    end

    local function update_reduction(loop, update, env, id_text)
        local carry
        for i = 1, #loop.carries do
            if loop.carries[i].port_id == update.port_id then carry = loop.carries[i]; break end
        end
        if carry == nil then
            return nil, {}, {}, {}, { Vec.VecRejectUnsupportedLoop(loop_id(loop.loop_id), "next update does not match a loop carry") }
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
                return nil, {}, {}, {}, { Vec.VecRejectUnsupportedLoop(loop_id(loop.loop_id), "add update is not rooted in the carry") }
            end
            local result = one_expr(value_expr, env, id_text)
            if #result.rejects > 0 then
                return nil, result.facts, result.memory, result.ranges, result.rejects
            end
            return Vec.VecReductionAdd(carry, result.value, Vec.VecReassocWrapping), result.facts, result.memory, result.ranges, {}
        end
        return nil, {}, {}, {}, { Vec.VecRejectUnsupportedLoop(loop_id(loop.loop_id), "only add reductions are recognized in the initial vector fact pass") }
    end

    vector_domain = pvm.phase("moonlift_vec_domain", {
        [Sem.SemDomainRange] = function(self, id_text)
            return pvm.once(Vec.VecDomainCounted(Sem.SemExprConstInt(Sem.SemTIndex, "0"), self.stop, Sem.SemExprConstInt(Sem.SemTIndex, "1")))
        end,
        [Sem.SemDomainRange2] = function(self, id_text)
            return pvm.once(Vec.VecDomainCounted(self.start, self.stop, Sem.SemExprConstInt(Sem.SemTIndex, "1")))
        end,
        [Sem.SemDomainView] = function(self, id_text)
            local access = Vec.VecAccessId(id_text .. ".view")
            return pvm.once(Vec.VecDomainRejected(Vec.VecRejectUnsupportedMemory(access, "view domains need access/dependence facts before vectorization")))
        end,
        [Sem.SemDomainZipEq] = function(self, id_text)
            local access = Vec.VecAccessId(id_text .. ".zip")
            return pvm.once(Vec.VecDomainRejected(Vec.VecRejectUnsupportedMemory(access, "zip domains need access/dependence facts before vectorization")))
        end,
    })

    local function same_binding_base(a, b)
        return is_class(a, Sem.SemExprBinding)
            and is_class(b, Sem.SemExprBinding)
            and a.binding == b.binding
    end

    local function index_is_lane_index(exprs, id)
        local fact = exprs[id]
        if fact == nil then return false end
        if is_class(fact, Vec.VecExprLaneIndex) then return true end
        if is_class(fact, Vec.VecExprLocal) then return index_is_lane_index(exprs, fact.value) end
        return false
    end

    local function build_dependence_facts(memory, expr_facts)
        local deps = {}
        local exprs = {}
        for i = 1, #expr_facts do exprs[expr_facts[i].id] = expr_facts[i] end
        for i = 1, #memory do
            local a = memory[i]
            for j = i + 1, #memory do
                local b = memory[j]
                if a.access_kind == Vec.VecAccessStore or b.access_kind == Vec.VecAccessStore then
                    if a.pattern == Vec.VecAccessContiguous
                        and b.pattern == Vec.VecAccessContiguous
                        and same_binding_base(a.base, b.base)
                        and index_is_lane_index(exprs, a.index)
                        and index_is_lane_index(exprs, b.index) then
                        local proof = Vec.VecProofNoMemoryDependence({ a.id, b.id }, "same pointer base and lane index; no loop-carried dependence")
                        deps[#deps + 1] = Vec.VecNoDependence(a.id, b.id, proof)
                    else
                        local reject = Vec.VecRejectUnsupportedMemory(a.id, "memory dependence proof is unknown for this access pair")
                        deps[#deps + 1] = Vec.VecDependenceUnknown(a.id, b.id, reject)
                    end
                end
            end
        end
        return deps
    end

    vector_loop_facts = pvm.phase("moonlift_vec_loop_facts", {
        [Sem.SemOverStmt] = function(self)
            local lid = loop_id(self.loop_id)
            local domain = one_domain(self.domain, self.loop_id .. ".domain")
            local rejects = {}
            if is_class(domain, Vec.VecDomainRejected) then rejects[#rejects + 1] = domain.reject end
            local index_binding = loop_index_binding(self)
            local env, locals, stores, expr_facts, memory, ranges, body_rejects = gather_body(self, index_binding)
            append_all(rejects, body_rejects)
            local reductions = {}
            for i = 1, #self.next do
                local reduction, facts, mmemory, rranges, rrejects = update_reduction(self, self.next[i], env, self.loop_id .. ".next." .. i)
                append_all(expr_facts, facts)
                append_all(memory, mmemory)
                append_all(ranges, rranges)
                append_all(rejects, rrejects)
                if reduction ~= nil then reductions[#reductions + 1] = reduction end
            end
            local inductions = {}
            if is_class(domain, Vec.VecDomainCounted) then
                inductions[1] = Vec.VecPrimaryInduction(index_binding, domain.start, domain.step)
            end
            local dependences = build_dependence_facts(memory, expr_facts)
            return pvm.once(Vec.VecLoopFacts(lid, domain, inductions, Vec.VecExprGraph(expr_facts), memory, dependences, ranges, stores, reductions, rejects))
        end,
        [Sem.SemWhileStmt] = function(self)
            local lid = loop_id(self.loop_id)
            local reject = Vec.VecRejectUnsupportedLoop(lid, "while-loop counted-loop detection is not implemented yet")
            return pvm.once(Vec.VecLoopFacts(lid, Vec.VecDomainRejected(reject), {}, Vec.VecExprGraph({}), {}, {}, {}, {}, {}, { reject }))
        end,
        [Sem.SemWhileExpr] = function(self)
            local lid = loop_id(self.loop_id)
            local reject = Vec.VecRejectUnsupportedLoop(lid, "expression-loop vector facts are not implemented yet")
            return pvm.once(Vec.VecLoopFacts(lid, Vec.VecDomainRejected(reject), {}, Vec.VecExprGraph({}), {}, {}, {}, {}, {}, { reject }))
        end,
        [Sem.SemOverExpr] = function(self)
            local lid = loop_id(self.loop_id)
            local reject = Vec.VecRejectUnsupportedLoop(lid, "expression-loop vector facts are not implemented yet")
            return pvm.once(Vec.VecLoopFacts(lid, Vec.VecDomainRejected(reject), {}, Vec.VecExprGraph({}), {}, {}, {}, {}, {}, { reject }))
        end,
    })

    local function expr_map(graph)
        local out = {}
        for i = 1, #graph.exprs do
            out[graph.exprs[i].id] = graph.exprs[i]
        end
        return out
    end

    local function find_range_for(facts, id)
        for i = 1, #facts.ranges do
            local r = facts.ranges[i]
            if (is_class(r, Vec.VecRangeBitAnd) or is_class(r, Vec.VecRangeExact) or is_class(r, Vec.VecRangeUnsigned)) and r.expr == id then
                return r
            end
        end
        local fact = expr_map(facts.exprs)[id]
        if fact ~= nil and is_class(fact, Vec.VecExprLocal) then
            return find_range_for(facts, fact.value)
        end
        return nil
    end

    local function scalar_decision(facts, rejects, considered)
        return Vec.VecLoopDecision(facts, Vec.VecLoopScalar(facts.loop, rejects), considered or {})
    end

    local function collect_memory_access_ids(facts)
        local ids = {}
        for i = 1, #facts.memory do ids[#ids + 1] = facts.memory[i].id end
        return ids
    end

    local function dependence_rejects(facts)
        local rejects = {}
        for i = 1, #facts.dependences do
            local dep = facts.dependences[i]
            if is_class(dep, Vec.VecDependenceUnknown) or is_class(dep, Vec.VecLoopCarriedDependence) then
                rejects[#rejects + 1] = dep.reject
            end
        end
        return rejects
    end

    local function decide_loop(loop, lanes, unroll, chunk_elems)
        lanes = lanes or 2
        unroll = unroll or 1
        local facts = one_loop_facts(loop)
        local elem = Vec.VecElemIndex
        local vector_shape = Vec.VecVectorShape(elem, lanes)
        local scalar_shape = Vec.VecLoopScalar(facts.loop, facts.rejects)
        local considered = { Vec.VecShapeScore(scalar_shape, 1, 0, "scalar fallback in vector-capable IR") }
        if #facts.rejects > 0 then
            return scalar_decision(facts, facts.rejects, considered)
        end
        if not is_class(facts.domain, Vec.VecDomainCounted) then
            return scalar_decision(facts, { Vec.VecRejectUnsupportedLoop(facts.loop, "vector loop requires counted domain") }, considered)
        end
        if #facts.reductions == 0 and #facts.stores == 1 then
            local dep_rejects = dependence_rejects(facts)
            if #dep_rejects > 0 then
                return scalar_decision(facts, dep_rejects, considered)
            end
            local store = facts.stores[1]
            elem = sem_ty_to_elem(store.access.elem_ty) or Vec.VecElemIndex
            vector_shape = Vec.VecVectorShape(elem, lanes)
            local target_fact = Vec.VecTargetSupportsShape(vector_shape)
            local proofs = {
                Vec.VecProofDomain("counted unit-step domain"),
                Vec.VecProofNoMemoryDependence(collect_memory_access_ids(facts), "store loop memory accesses have no loop-carried dependence facts"),
                Vec.VecProofTarget(target_fact, "target has requested vector store shape"),
            }
            considered[#considered + 1] = Vec.VecShapeScore(Vec.VecLoopVector(facts.loop, vector_shape, unroll, Vec.VecTailScalar, proofs), lanes * unroll, 8 + unroll, "unit-step map/store loop")
            return Vec.VecLoopDecision(facts, Vec.VecLoopVector(facts.loop, vector_shape, unroll, Vec.VecTailScalar, proofs), considered)
        end
        if #facts.reductions ~= 1 then
            return scalar_decision(facts, { Vec.VecRejectCost("initial vector decision requires exactly one reduction or one store") }, considered)
        end
        local reduction = facts.reductions[1]
        if not is_class(reduction, Vec.VecReductionAdd) then
            return scalar_decision(facts, { Vec.VecRejectCost("initial vector decision only supports add reductions") }, considered)
        end
        elem = sem_ty_to_elem(reduction.carry.ty) or Vec.VecElemIndex
        vector_shape = Vec.VecVectorShape(elem, lanes)
        local target_fact = Vec.VecTargetSupportsBinOp(vector_shape, Vec.VecAdd)
        local proofs = {
            Vec.VecProofDomain("counted unit-step domain"),
            Vec.VecProofReduction(reduction, "single add reduction"),
            Vec.VecProofTarget(target_fact, "target has requested vector add shape"),
        }
        if chunk_elems ~= nil then
            local narrow_shape = Vec.VecVectorShape(Vec.VecElemI32, lanes)
            local range = find_range_for(facts, reduction.value)
            local max_value = range and tonumber(range.max_value) or nil
            if lanes ~= 4 then
                return scalar_decision(facts, { Vec.VecRejectTarget(narrow_shape, "chunked narrow vector decision currently requires i32x4 lanes") }, considered)
            end
            if max_value == nil or max_value < 0 or max_value > 2147483647 then
                return scalar_decision(facts, { Vec.VecRejectRange(reduction.value, "chunked narrow vector decision requires an explicit non-negative bitand bound fitting i32") }, considered)
            end
            local per_lane = math.floor(chunk_elems / (lanes * unroll)) + 1
            if per_lane * max_value >= 2147483647 then
                return scalar_decision(facts, { Vec.VecRejectRange(reduction.value, "chunked i32 accumulator may overflow; reduce chunk_elems or unroll more") }, considered)
            end
            local range_proof = Vec.VecProofRange(range, "bitand range bounds the narrowed term")
            local narrow_proof = Vec.VecProofNarrowSafe(reduction, Vec.VecElemI32, chunk_elems, "bounded term keeps chunk accumulator in i32")
            proofs[#proofs + 1] = range_proof
            considered[#considered + 1] = Vec.VecShapeScore(Vec.VecLoopChunkedNarrowVector(facts.loop, narrow_shape, unroll, chunk_elems, Vec.VecTailScalar, narrow_proof, proofs), lanes * unroll, 20, "bounded i32x4 chunked add reduction")
            return Vec.VecLoopDecision(facts, Vec.VecLoopChunkedNarrowVector(facts.loop, narrow_shape, unroll, chunk_elems, Vec.VecTailScalar, narrow_proof, proofs), considered)
        end
        considered[#considered + 1] = Vec.VecShapeScore(Vec.VecLoopVector(facts.loop, vector_shape, unroll, Vec.VecTailScalar, proofs), lanes * unroll, 10 + unroll, "unit-step add reduction")
        return Vec.VecLoopDecision(facts, Vec.VecLoopVector(facts.loop, vector_shape, unroll, Vec.VecTailScalar, proofs), considered)
    end

    vector_loop_decision = pvm.phase("moonlift_vec_loop_decision", {
        [Sem.SemOverStmt] = function(self, lanes, unroll, chunk_elems)
            return pvm.once(decide_loop(self, lanes, unroll, chunk_elems))
        end,
        [Sem.SemWhileStmt] = function(self, lanes, unroll, chunk_elems)
            return pvm.once(decide_loop(self, lanes, unroll, chunk_elems))
        end,
        [Sem.SemWhileExpr] = function(self, lanes, unroll, chunk_elems)
            return pvm.once(decide_loop(self, lanes, unroll, chunk_elems))
        end,
        [Sem.SemOverExpr] = function(self, lanes, unroll, chunk_elems)
            return pvm.once(decide_loop(self, lanes, unroll, chunk_elems))
        end,
    })

    local function value_id(text)
        return Vec.VecValueId(text)
    end

    local function block_id(text)
        return Vec.VecBlockId(text)
    end

    local function scalar_shape(elem)
        return Vec.VecScalarShape(elem)
    end

    local function vector_shape(elem, lanes)
        return Vec.VecVectorShape(elem, lanes)
    end

    local function value_param(id, shape)
        if is_class(shape, Vec.VecVectorShape) then
            return Vec.VecVectorParam(id, shape.elem, shape.lanes)
        end
        return Vec.VecScalarParam(id, shape.elem)
    end

    local function expr_fact_map(facts)
        local out = {}
        for i = 1, #facts.exprs.exprs do
            out[facts.exprs.exprs[i].id] = facts.exprs.exprs[i]
        end
        return out
    end

    local function memory_fact_map(facts)
        local out = {}
        for i = 1, #facts.memory do
            out[facts.memory[i].id] = facts.memory[i]
        end
        return out
    end

    local function elem_size(elem)
        if elem == Vec.VecElemI8 or elem == Vec.VecElemU8 or elem == Vec.VecElemBool then return 1 end
        if elem == Vec.VecElemI16 or elem == Vec.VecElemU16 then return 2 end
        if elem == Vec.VecElemI32 or elem == Vec.VecElemU32 or elem == Vec.VecElemF32 then return 4 end
        return 8
    end

    local function arg_value_id_from_binding_expr(expr)
        if is_class(expr, Sem.SemExprBinding) and is_class(expr.binding, Sem.SemBindArg) then
            return value_id("arg:" .. expr.binding.index .. ":" .. expr.binding.name)
        end
        return nil
    end

    local function func_entry_params(func)
        local params = {}
        for i = 1, #func.params do
            params[i] = value_param(value_id("arg:" .. (i - 1) .. ":" .. func.params[i].name), scalar_shape(sem_ty_to_elem(func.params[i].ty) or Vec.VecElemIndex))
        end
        return params
    end

    local function stop_value_id(facts)
        if is_class(facts.domain, Vec.VecDomainCounted)
            and is_class(facts.domain.stop, Sem.SemExprBinding)
            and is_class(facts.domain.stop.binding, Sem.SemBindArg) then
            return value_id("arg:" .. facts.domain.stop.binding.index .. ":" .. facts.domain.stop.binding.name)
        end
        return value_id("arg:0:" .. "n")
    end

    local function collect_const_facts(facts)
        local out = {}
        local seen = {}
        for i = 1, #facts.exprs.exprs do
            local fact = facts.exprs.exprs[i]
            if is_class(fact, Vec.VecExprConst) or is_class(fact, Vec.VecExprInvariant) then
                if is_class(fact.expr, Sem.SemExprConstInt) and seen[fact.id] == nil then
                    seen[fact.id] = true
                    out[#out + 1] = fact
                end
            end
        end
        return out
    end

    local function build_loop_vector_blocks(func, decision)
        local chosen = decision.chosen
        if not is_class(chosen, Vec.VecLoopVector) then
            return {}
        end
        local facts = decision.facts
        if #facts.reductions == 0 and #facts.stores == 1 then
            return nil
        end
        if #facts.reductions ~= 1 or #facts.inductions < 1 then
            return {}
        end
        local reduction = facts.reductions[1]
        local induction = facts.inductions[1]
        local elem = chosen.shape.elem
        local lanes = chosen.shape.lanes
        local unroll = chosen.unroll
        local sshape = scalar_shape(elem)
        local vshape = vector_shape(elem, lanes)
        local fname = func.name
        local entry = block_id(fname .. ":entry")
        local header = block_id(fname .. ":vec.header")
        local body = block_id(fname .. ":vec.body")
        local vec_exit = block_id(fname .. ":vec.exit")
        local tail_header = block_id(fname .. ":tail.header")
        local tail_body = block_id(fname .. ":tail.body")
        local exit = block_id(fname .. ":exit")
        local n_arg = stop_value_id(facts)
        local start_id = value_id("init.i")
        local acc0 = value_id("init.acc")
        local count = value_id("main.count")
        local stride_id = value_id("const.stride")
        local rem = value_id("main.rem")
        local main_count = value_id("main.count.aligned")
        local main_stop = value_id("main.stop")
        local h_i = value_id("vec.header.i")
        local b_i = value_id("vec.body.i")
        local result = value_id("result")
        local t_i = value_id("tail.header.i")
        local t_acc = value_id("tail.header.acc")
        local tb_i = value_id("tail.body.i")
        local tb_acc = value_id("tail.body.acc")
        local h_acc, b_acc, ve_acc, next_acc, init_acc = {}, {}, {}, {}, {}
        local h_offsets, b_offsets, init_offsets = {}, {}, {}
        for u = 1, unroll do
            h_acc[u] = value_id("vec.header.acc" .. u)
            b_acc[u] = value_id("vec.body.acc" .. u)
            ve_acc[u] = value_id("vec.exit.acc" .. u)
            next_acc[u] = value_id("vec.next.acc" .. u)
            init_acc[u] = value_id("init.vacc" .. u)
            h_offsets[u] = value_id("vec.header.offset" .. u)
            b_offsets[u] = value_id("vec.body.offset" .. u)
            init_offsets[u] = value_id("init.offset" .. u)
        end
        local const_facts = collect_const_facts(facts)
        local init_consts, h_consts, b_consts = {}, {}, {}
        for i = 1, #const_facts do
            init_consts[i] = value_id("init.const." .. const_facts[i].id.text)
            h_consts[i] = value_id("vec.header.const" .. i)
            b_consts[i] = value_id("vec.body.const" .. i)
        end
        local const_param_by_expr = {}
        for i = 1, #const_facts do
            const_param_by_expr[const_facts[i].id] = b_consts[i]
        end
        local exprs = expr_fact_map(facts)
        local accesses = memory_fact_map(facts)
        local serial = 0
        local function next_tmp(prefix)
            serial = serial + 1
            return value_id(prefix .. "." .. serial)
        end
        local function lower_load_addr(access, scalar_index, first_lane, cmds, path)
            local base = arg_value_id_from_binding_expr(access.base)
            if base == nil then
                error("vector_facts: vector load base must currently be a pointer argument")
            end
            local idx = scalar_index
            if first_lane ~= 0 then
                local c = next_tmp(path .. ".lane")
                local add = next_tmp(path .. ".idx")
                cmds[#cmds + 1] = Vec.VecCmdConstInt(c, Vec.VecElemIndex, tostring(first_lane))
                cmds[#cmds + 1] = Vec.VecCmdBin(add, scalar_shape(Vec.VecElemIndex), Vec.VecAdd, scalar_index, c)
                idx = add
            end
            local lelem = sem_ty_to_elem(access.elem_ty) or Vec.VecElemIndex
            local sz = next_tmp(path .. ".esize")
            local bytes = next_tmp(path .. ".bytes")
            local addr = next_tmp(path .. ".addr")
            cmds[#cmds + 1] = Vec.VecCmdConstInt(sz, Vec.VecElemIndex, tostring(elem_size(lelem)))
            cmds[#cmds + 1] = Vec.VecCmdBin(bytes, scalar_shape(Vec.VecElemIndex), Vec.VecMul, idx, sz)
            cmds[#cmds + 1] = Vec.VecCmdBin(addr, scalar_shape(Vec.VecElemPtr), Vec.VecAdd, base, bytes)
            return addr
        end
        local function lower_vec_expr(id, offset_id, first_lane, cmds)
            local fact = exprs[id]
            if fact == nil then error("vector_facts: missing expr fact " .. id.text) end
            if is_class(fact, Vec.VecExprLaneIndex) then
                local splat = next_tmp("vec.splat.i")
                local ramp = next_tmp("vec.ramp.i")
                cmds[#cmds + 1] = Vec.VecCmdSplat(splat, vshape, b_i)
                cmds[#cmds + 1] = Vec.VecCmdBin(ramp, vshape, Vec.VecAdd, splat, offset_id)
                return ramp
            elseif is_class(fact, Vec.VecExprConst) or is_class(fact, Vec.VecExprInvariant) then
                return const_param_by_expr[id]
            elseif is_class(fact, Vec.VecExprLocal) then
                return lower_vec_expr(fact.value, offset_id, first_lane, cmds)
            elseif is_class(fact, Vec.VecExprLoad) then
                local access = accesses[fact.access]
                if access == nil then error("vector_facts: missing memory access " .. fact.access.text) end
                local dst = next_tmp("vec.load")
                local addr = lower_load_addr(access, b_i, first_lane, cmds, "vec.load")
                cmds[#cmds + 1] = Vec.VecCmdLoad(dst, vshape, access, addr)
                return dst
            elseif is_class(fact, Vec.VecExprBin) then
                local lhs = lower_vec_expr(fact.lhs, offset_id, first_lane, cmds)
                local rhs = lower_vec_expr(fact.rhs, offset_id, first_lane, cmds)
                local dst = next_tmp("vec.bin")
                cmds[#cmds + 1] = Vec.VecCmdBin(dst, vshape, fact.op, lhs, rhs)
                return dst
            end
            error("vector_facts: unsupported vector expr fact " .. tostring(fact))
        end
        local function lower_scalar_expr(id, index_id, cmds)
            local fact = exprs[id]
            if fact == nil then error("vector_facts: missing scalar expr fact " .. id.text) end
            if is_class(fact, Vec.VecExprLaneIndex) then
                return index_id
            elseif is_class(fact, Vec.VecExprConst) or is_class(fact, Vec.VecExprInvariant) then
                local dst = next_tmp("tail.const")
                cmds[#cmds + 1] = Vec.VecCmdConstInt(dst, elem, fact.expr.raw)
                return dst
            elseif is_class(fact, Vec.VecExprLocal) then
                return lower_scalar_expr(fact.value, index_id, cmds)
            elseif is_class(fact, Vec.VecExprLoad) then
                local access = accesses[fact.access]
                if access == nil then error("vector_facts: missing memory access " .. fact.access.text) end
                local dst = next_tmp("tail.load")
                local addr = lower_load_addr(access, index_id, 0, cmds, "tail.load")
                cmds[#cmds + 1] = Vec.VecCmdLoad(dst, sshape, access, addr)
                return dst
            elseif is_class(fact, Vec.VecExprBin) then
                local lhs = lower_scalar_expr(fact.lhs, index_id, cmds)
                local rhs = lower_scalar_expr(fact.rhs, index_id, cmds)
                local dst = next_tmp("tail.bin")
                cmds[#cmds + 1] = Vec.VecCmdBin(dst, sshape, fact.op, lhs, rhs)
                return dst
            end
            error("vector_facts: unsupported scalar expr fact " .. tostring(fact))
        end

        local entry_cmds = {
            Vec.VecCmdConstInt(start_id, elem, induction.start.raw or "0"),
            Vec.VecCmdConstInt(acc0, elem, reduction.carry.init.raw or "0"),
            Vec.VecCmdConstInt(stride_id, elem, tostring(lanes * unroll)),
            Vec.VecCmdBin(count, sshape, Vec.VecSub, n_arg, start_id),
            Vec.VecCmdBin(rem, sshape, Vec.VecRem, count, stride_id),
            Vec.VecCmdBin(main_count, sshape, Vec.VecSub, count, rem),
            Vec.VecCmdBin(main_stop, sshape, Vec.VecAdd, start_id, main_count),
        }
        for u = 1, unroll do
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdSplat(init_acc[u], vshape, acc0)
            local offsets = {}
            for lane = 0, lanes - 1 do offsets[#offsets + 1] = tostring((u - 1) * lanes + lane) end
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdRamp(init_offsets[u], vshape, start_id, offsets)
        end
        for i = 1, #const_facts do
            local scalar_const = value_id("init.scalar." .. const_facts[i].id.text)
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdConstInt(scalar_const, elem, const_facts[i].expr.raw)
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdSplat(init_consts[i], vshape, scalar_const)
        end
        local header_args = { start_id }
        for u = 1, unroll do header_args[#header_args + 1] = init_acc[u] end
        for u = 1, unroll do header_args[#header_args + 1] = init_offsets[u] end
        for i = 1, #init_consts do header_args[#header_args + 1] = init_consts[i] end

        local header_params = { value_param(h_i, sshape) }
        local body_params = { value_param(b_i, sshape) }
        local exit_params = {}
        for u = 1, unroll do
            header_params[#header_params + 1] = value_param(h_acc[u], vshape)
            body_params[#body_params + 1] = value_param(b_acc[u], vshape)
            exit_params[#exit_params + 1] = value_param(ve_acc[u], vshape)
        end
        for u = 1, unroll do
            header_params[#header_params + 1] = value_param(h_offsets[u], vshape)
            body_params[#body_params + 1] = value_param(b_offsets[u], vshape)
        end
        for i = 1, #h_consts do
            header_params[#header_params + 1] = value_param(h_consts[i], vshape)
            body_params[#body_params + 1] = value_param(b_consts[i], vshape)
        end
        local body_args = { h_i }
        local exit_args = {}
        for u = 1, unroll do body_args[#body_args + 1] = h_acc[u]; exit_args[#exit_args + 1] = h_acc[u] end
        for u = 1, unroll do body_args[#body_args + 1] = h_offsets[u] end
        for i = 1, #h_consts do body_args[#body_args + 1] = h_consts[i] end
        local header_cond = value_id("vec.cond")
        local header_cmds = { Vec.VecCmdBin(header_cond, sshape, Vec.VecLt, h_i, main_stop) }

        local body_cmds = {}
        for u = 1, unroll do
            local vec_value = lower_vec_expr(reduction.value, b_offsets[u], (u - 1) * lanes, body_cmds)
            body_cmds[#body_cmds + 1] = Vec.VecCmdBin(next_acc[u], vshape, Vec.VecAdd, b_acc[u], vec_value)
        end
        local next_i = value_id("vec.next.i")
        body_cmds[#body_cmds + 1] = Vec.VecCmdBin(next_i, sshape, Vec.VecAdd, b_i, stride_id)
        local back_args = { next_i }
        for u = 1, unroll do back_args[#back_args + 1] = next_acc[u] end
        for u = 1, unroll do back_args[#back_args + 1] = b_offsets[u] end
        for i = 1, #b_consts do back_args[#back_args + 1] = b_consts[i] end

        local reduced = value_id("reduce.total")
        local exit_cmds = { Vec.VecCmdHorizontalReduce(reduced, Vec.VecAdd, ve_acc) }
        local tail_cond = value_id("tail.cond")
        local tail_header_cmds = { Vec.VecCmdBin(tail_cond, sshape, Vec.VecLt, t_i, n_arg) }
        local tail_body_cmds = {}
        local tail_value = lower_scalar_expr(reduction.value, tb_i, tail_body_cmds)
        local tail_next_acc = value_id("tail.next.acc")
        local one = value_id("tail.one")
        local tail_next_i = value_id("tail.next.i")
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdBin(tail_next_acc, sshape, Vec.VecAdd, tb_acc, tail_value)
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdConstInt(one, elem, "1")
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdBin(tail_next_i, sshape, Vec.VecAdd, tb_i, one)

        return {
            Vec.VecBlock(entry, func_entry_params(func), entry_cmds, Vec.VecJump(header, header_args)),
            Vec.VecBlock(header, header_params, header_cmds, Vec.VecBrIf(header_cond, body, body_args, vec_exit, exit_args)),
            Vec.VecBlock(body, body_params, body_cmds, Vec.VecJump(header, back_args)),
            Vec.VecBlock(vec_exit, exit_params, exit_cmds, Vec.VecJump(tail_header, { main_stop, reduced })),
            Vec.VecBlock(tail_header, { value_param(t_i, sshape), value_param(t_acc, sshape) }, tail_header_cmds, Vec.VecBrIf(tail_cond, tail_body, { t_i, t_acc }, exit, { t_acc })),
            Vec.VecBlock(tail_body, { value_param(tb_i, sshape), value_param(tb_acc, sshape) }, tail_body_cmds, Vec.VecJump(tail_header, { tail_next_i, tail_next_acc })),
            Vec.VecBlock(exit, { value_param(result, sshape) }, {}, Vec.VecReturnValue(result)),
        }
    end

    local function build_loop_store_blocks(func, decision)
        local chosen = decision.chosen
        if not is_class(chosen, Vec.VecLoopVector) then return {} end
        local facts = decision.facts
        if #facts.stores ~= 1 or #facts.inductions < 1 then return {} end
        local store = facts.stores[1]
        local induction = facts.inductions[1]
        local elem = sem_ty_to_elem(store.access.elem_ty) or Vec.VecElemIndex
        local lanes = chosen.shape.lanes
        local unroll = chosen.unroll
        local sshape = scalar_shape(elem)
        local ishape = scalar_shape(Vec.VecElemIndex)
        local pshape = scalar_shape(Vec.VecElemPtr)
        local vshape = vector_shape(elem, lanes)
        local fname = func.name
        local entry = block_id(fname .. ":entry")
        local header = block_id(fname .. ":store.header")
        local body = block_id(fname .. ":store.body")
        local tail_header = block_id(fname .. ":store.tail.header")
        local tail_body = block_id(fname .. ":store.tail.body")
        local exit = block_id(fname .. ":exit")
        local n_arg = stop_value_id(facts)
        local start_id = value_id("store.init.i")
        local stride_id = value_id("store.const.stride")
        local count = value_id("store.count")
        local rem = value_id("store.rem")
        local main_count = value_id("store.count.aligned")
        local main_stop = value_id("store.main.stop")
        local h_i = value_id("store.header.i")
        local b_i = value_id("store.body.i")
        local t_i = value_id("store.tail.i")
        local tb_i = value_id("store.tail.body.i")
        local h_offsets, b_offsets, init_offsets = {}, {}, {}
        for u = 1, unroll do
            h_offsets[u] = value_id("store.header.offset" .. u)
            b_offsets[u] = value_id("store.body.offset" .. u)
            init_offsets[u] = value_id("store.init.offset" .. u)
        end
        local const_facts = collect_const_facts(facts)
        local init_consts, h_consts, b_consts = {}, {}, {}
        for i = 1, #const_facts do
            init_consts[i] = value_id("store.init.const." .. const_facts[i].id.text)
            h_consts[i] = value_id("store.header.const" .. i)
            b_consts[i] = value_id("store.body.const" .. i)
        end
        local const_param_by_expr = {}
        for i = 1, #const_facts do const_param_by_expr[const_facts[i].id] = b_consts[i] end
        local exprs = expr_fact_map(facts)
        local accesses = memory_fact_map(facts)
        local serial = 0
        local function next_tmp(prefix)
            serial = serial + 1
            return value_id(prefix .. "." .. serial)
        end
        local function lower_addr(access, scalar_index, first_lane, cmds, path)
            local base = arg_value_id_from_binding_expr(access.base)
            if base == nil then error("vector_facts: vector store base must currently be a pointer argument") end
            local idx = scalar_index
            if first_lane ~= 0 then
                local c = next_tmp(path .. ".lane")
                local add = next_tmp(path .. ".idx")
                cmds[#cmds + 1] = Vec.VecCmdConstInt(c, Vec.VecElemIndex, tostring(first_lane))
                cmds[#cmds + 1] = Vec.VecCmdBin(add, ishape, Vec.VecAdd, scalar_index, c)
                idx = add
            end
            local sz = next_tmp(path .. ".esize")
            local bytes = next_tmp(path .. ".bytes")
            local addr = next_tmp(path .. ".addr")
            cmds[#cmds + 1] = Vec.VecCmdConstInt(sz, Vec.VecElemIndex, tostring(elem_size(elem)))
            cmds[#cmds + 1] = Vec.VecCmdBin(bytes, ishape, Vec.VecMul, idx, sz)
            cmds[#cmds + 1] = Vec.VecCmdBin(addr, pshape, Vec.VecAdd, base, bytes)
            return addr
        end
        local function lower_vec_expr(id, offset_id, first_lane, cmds)
            local fact = exprs[id]
            if fact == nil then error("vector_facts: missing store expr fact " .. id.text) end
            if is_class(fact, Vec.VecExprLaneIndex) then
                local splat = next_tmp("store.splat.i")
                local ramp = next_tmp("store.ramp.i")
                cmds[#cmds + 1] = Vec.VecCmdSplat(splat, vshape, b_i)
                cmds[#cmds + 1] = Vec.VecCmdBin(ramp, vshape, Vec.VecAdd, splat, offset_id)
                return ramp
            elseif is_class(fact, Vec.VecExprConst) or is_class(fact, Vec.VecExprInvariant) then
                return const_param_by_expr[id]
            elseif is_class(fact, Vec.VecExprLocal) then
                return lower_vec_expr(fact.value, offset_id, first_lane, cmds)
            elseif is_class(fact, Vec.VecExprLoad) then
                local access = accesses[fact.access]
                local dst = next_tmp("store.load")
                local addr = lower_addr(access, b_i, first_lane, cmds, "store.load")
                cmds[#cmds + 1] = Vec.VecCmdLoad(dst, vshape, access, addr)
                return dst
            elseif is_class(fact, Vec.VecExprBin) then
                local lhs = lower_vec_expr(fact.lhs, offset_id, first_lane, cmds)
                local rhs = lower_vec_expr(fact.rhs, offset_id, first_lane, cmds)
                local dst = next_tmp("store.bin")
                cmds[#cmds + 1] = Vec.VecCmdBin(dst, vshape, fact.op, lhs, rhs)
                return dst
            end
            error("vector_facts: unsupported store vector expr fact " .. tostring(fact))
        end
        local function lower_scalar_expr(id, scalar_index, cmds)
            local fact = exprs[id]
            if fact == nil then error("vector_facts: missing store scalar expr fact " .. id.text) end
            if is_class(fact, Vec.VecExprLaneIndex) then
                return scalar_index
            elseif is_class(fact, Vec.VecExprConst) or is_class(fact, Vec.VecExprInvariant) then
                local dst = next_tmp("store.tail.const")
                cmds[#cmds + 1] = Vec.VecCmdConstInt(dst, elem, fact.expr.raw)
                return dst
            elseif is_class(fact, Vec.VecExprLocal) then
                return lower_scalar_expr(fact.value, scalar_index, cmds)
            elseif is_class(fact, Vec.VecExprLoad) then
                local access = accesses[fact.access]
                local dst = next_tmp("store.tail.load")
                local addr = lower_addr(access, scalar_index, 0, cmds, "store.tail.load")
                cmds[#cmds + 1] = Vec.VecCmdLoad(dst, sshape, access, addr)
                return dst
            elseif is_class(fact, Vec.VecExprBin) then
                local lhs = lower_scalar_expr(fact.lhs, scalar_index, cmds)
                local rhs = lower_scalar_expr(fact.rhs, scalar_index, cmds)
                local dst = next_tmp("store.tail.bin")
                cmds[#cmds + 1] = Vec.VecCmdBin(dst, sshape, fact.op, lhs, rhs)
                return dst
            end
            error("vector_facts: unsupported store scalar expr fact " .. tostring(fact))
        end
        local entry_cmds = {
            Vec.VecCmdConstInt(start_id, Vec.VecElemIndex, induction.start.raw or "0"),
            Vec.VecCmdConstInt(stride_id, Vec.VecElemIndex, tostring(lanes * unroll)),
            Vec.VecCmdBin(count, ishape, Vec.VecSub, n_arg, start_id),
            Vec.VecCmdBin(rem, ishape, Vec.VecRem, count, stride_id),
            Vec.VecCmdBin(main_count, ishape, Vec.VecSub, count, rem),
            Vec.VecCmdBin(main_stop, ishape, Vec.VecAdd, start_id, main_count),
        }
        for u = 1, unroll do
            local offsets = {}
            for lane = 0, lanes - 1 do offsets[#offsets + 1] = tostring((u - 1) * lanes + lane) end
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdRamp(init_offsets[u], vshape, start_id, offsets)
        end
        for i = 1, #const_facts do
            local scalar_const = value_id("store.init.scalar." .. const_facts[i].id.text)
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdConstInt(scalar_const, elem, const_facts[i].expr.raw)
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdSplat(init_consts[i], vshape, scalar_const)
        end
        local header_args = { start_id }
        for u = 1, unroll do header_args[#header_args + 1] = init_offsets[u] end
        for i = 1, #init_consts do header_args[#header_args + 1] = init_consts[i] end
        local header_params = { value_param(h_i, ishape) }
        local body_params = { value_param(b_i, ishape) }
        local body_args = { h_i }
        for u = 1, unroll do
            header_params[#header_params + 1] = value_param(h_offsets[u], vshape)
            body_params[#body_params + 1] = value_param(b_offsets[u], vshape)
            body_args[#body_args + 1] = h_offsets[u]
        end
        for i = 1, #h_consts do
            header_params[#header_params + 1] = value_param(h_consts[i], vshape)
            body_params[#body_params + 1] = value_param(b_consts[i], vshape)
            body_args[#body_args + 1] = h_consts[i]
        end
        local header_cond = value_id("store.cond")
        local header_cmds = { Vec.VecCmdBin(header_cond, ishape, Vec.VecLt, h_i, main_stop) }
        local body_cmds = {}
        for u = 1, unroll do
            local store_value = lower_vec_expr(store.value, b_offsets[u], (u - 1) * lanes, body_cmds)
            local addr = lower_addr(store.access, b_i, (u - 1) * lanes, body_cmds, "store.vec")
            body_cmds[#body_cmds + 1] = Vec.VecCmdStore(store.access, vshape, addr, store_value)
        end
        local next_i = value_id("store.next.i")
        body_cmds[#body_cmds + 1] = Vec.VecCmdBin(next_i, ishape, Vec.VecAdd, b_i, stride_id)
        local back_args = { next_i }
        for u = 1, unroll do back_args[#back_args + 1] = b_offsets[u] end
        for i = 1, #b_consts do back_args[#back_args + 1] = b_consts[i] end
        local tail_cond = value_id("store.tail.cond")
        local tail_header_cmds = { Vec.VecCmdBin(tail_cond, ishape, Vec.VecLt, t_i, n_arg) }
        local tail_body_cmds = {}
        local tail_value = lower_scalar_expr(store.value, tb_i, tail_body_cmds)
        local tail_addr = lower_addr(store.access, tb_i, 0, tail_body_cmds, "store.tail")
        local one = value_id("store.tail.one")
        local tail_next_i = value_id("store.tail.next.i")
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdStore(store.access, sshape, tail_addr, tail_value)
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdConstInt(one, Vec.VecElemIndex, "1")
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdBin(tail_next_i, ishape, Vec.VecAdd, tb_i, one)
        return {
            Vec.VecBlock(entry, func_entry_params(func), entry_cmds, Vec.VecJump(header, header_args)),
            Vec.VecBlock(header, header_params, header_cmds, Vec.VecBrIf(header_cond, body, body_args, tail_header, { main_stop })),
            Vec.VecBlock(body, body_params, body_cmds, Vec.VecJump(header, back_args)),
            Vec.VecBlock(tail_header, { value_param(t_i, ishape) }, tail_header_cmds, Vec.VecBrIf(tail_cond, tail_body, { t_i }, exit, {})),
            Vec.VecBlock(tail_body, { value_param(tb_i, ishape) }, tail_body_cmds, Vec.VecJump(tail_header, { tail_next_i })),
            Vec.VecBlock(exit, {}, {}, Vec.VecReturnVoid),
        }
    end

    local function build_loop_chunked_blocks(func, decision)
        local chosen = decision.chosen
        if not is_class(chosen, Vec.VecLoopChunkedNarrowVector) then
            return {}
        end
        local facts = decision.facts
        if #facts.reductions ~= 1 or #facts.inductions < 1 then
            return {}
        end
        local reduction = facts.reductions[1]
        local induction = facts.inductions[1]
        local lanes = chosen.narrow_shape.lanes
        local unroll = chosen.unroll
        local chunk_elems = math.floor(chosen.chunk_elems / (lanes * unroll)) * (lanes * unroll)
        if chunk_elems < lanes * unroll then chunk_elems = lanes * unroll end
        local wide_elem = sem_ty_to_elem(reduction.carry.ty) or Vec.VecElemIndex
        local narrow_elem = Vec.VecElemI32
        local wide_shape = scalar_shape(wide_elem)
        local narrow_shape = scalar_shape(narrow_elem)
        local vshape = vector_shape(narrow_elem, lanes)
        local fname = func.name
        local entry = block_id(fname .. ":entry")
        local outer_header = block_id(fname .. ":outer.header")
        local outer_body = block_id(fname .. ":outer.body")
        local inner_header = block_id(fname .. ":inner.header")
        local inner_body = block_id(fname .. ":inner.body")
        local inner_exit = block_id(fname .. ":inner.exit")
        local tail_header = block_id(fname .. ":tail.header")
        local tail_body = block_id(fname .. ":tail.body")
        local exit = block_id(fname .. ":exit")
        local n_arg = stop_value_id(facts)
        local start_id = value_id("init.i")
        local total0 = value_id("init.total")
        local stride_id = value_id("const.stride")
        local chunk_id = value_id("const.chunk")
        local count = value_id("main.count")
        local rem = value_id("main.rem")
        local main_count = value_id("main.count.aligned")
        local main_stop = value_id("main.stop")
        local zero32 = value_id("zero.i32")
        local o_i = value_id("outer.i")
        local o_total = value_id("outer.total")
        local raw_chunk_end = value_id("chunk.raw.end")
        local chunk_lt = value_id("chunk.lt")
        local chunk_end = value_id("chunk.end")
        local ih_i = value_id("inner.header.i")
        local ib_i = value_id("inner.body.i")
        local t_i = value_id("tail.header.i")
        local t_acc = value_id("tail.header.acc")
        local tb_i = value_id("tail.body.i")
        local tb_acc = value_id("tail.body.acc")
        local result = value_id("result")
        local zero_v, ih_acc, ib_acc, ie_acc, next_acc = {}, {}, {}, {}, {}
        local ih_offsets, ib_offsets, init_offsets = {}, {}, {}
        for u = 1, unroll do
            zero_v[u] = value_id("zero.v" .. u)
            ih_acc[u] = value_id("inner.header.acc" .. u)
            ib_acc[u] = value_id("inner.body.acc" .. u)
            ie_acc[u] = value_id("inner.exit.acc" .. u)
            next_acc[u] = value_id("inner.next.acc" .. u)
            ih_offsets[u] = value_id("inner.header.offset" .. u)
            ib_offsets[u] = value_id("inner.body.offset" .. u)
            init_offsets[u] = value_id("init.i32.offset" .. u)
        end
        local const_facts = collect_const_facts(facts)
        local init_consts, ih_consts, ib_consts = {}, {}, {}
        for i = 1, #const_facts do
            init_consts[i] = value_id("init.i32.const." .. const_facts[i].id.text)
            ih_consts[i] = value_id("inner.header.const" .. i)
            ib_consts[i] = value_id("inner.body.const" .. i)
        end
        local const_param_by_expr = {}
        for i = 1, #const_facts do const_param_by_expr[const_facts[i].id] = ib_consts[i] end
        local exprs = expr_fact_map(facts)
        local serial = 0
        local function next_tmp(prefix)
            serial = serial + 1
            return value_id(prefix .. "." .. serial)
        end
        local function lower_vec_expr(id, index_id, offset_id, cmds)
            local fact = exprs[id]
            if fact == nil then error("vector_facts: missing chunk expr fact " .. id.text) end
            if is_class(fact, Vec.VecExprLaneIndex) then
                local splat = next_tmp("chunk.splat.i")
                local ramp = next_tmp("chunk.ramp.i")
                cmds[#cmds + 1] = Vec.VecCmdSplat(splat, vshape, index_id)
                cmds[#cmds + 1] = Vec.VecCmdBin(ramp, vshape, Vec.VecAdd, splat, offset_id)
                return ramp
            elseif is_class(fact, Vec.VecExprConst) or is_class(fact, Vec.VecExprInvariant) then
                return const_param_by_expr[id]
            elseif is_class(fact, Vec.VecExprLocal) then
                return lower_vec_expr(fact.value, index_id, offset_id, cmds)
            elseif is_class(fact, Vec.VecExprBin) then
                local lhs = lower_vec_expr(fact.lhs, index_id, offset_id, cmds)
                local rhs = lower_vec_expr(fact.rhs, index_id, offset_id, cmds)
                local dst = next_tmp("chunk.bin")
                cmds[#cmds + 1] = Vec.VecCmdBin(dst, vshape, fact.op, lhs, rhs)
                return dst
            end
            error("vector_facts: unsupported chunk vector expr fact " .. tostring(fact))
        end
        local function lower_scalar_expr(id, index_id, cmds)
            local fact = exprs[id]
            if fact == nil then error("vector_facts: missing chunk scalar expr fact " .. id.text) end
            if is_class(fact, Vec.VecExprLaneIndex) then
                return index_id
            elseif is_class(fact, Vec.VecExprConst) or is_class(fact, Vec.VecExprInvariant) then
                local dst = next_tmp("chunk.tail.const")
                cmds[#cmds + 1] = Vec.VecCmdConstInt(dst, wide_elem, fact.expr.raw)
                return dst
            elseif is_class(fact, Vec.VecExprLocal) then
                return lower_scalar_expr(fact.value, index_id, cmds)
            elseif is_class(fact, Vec.VecExprBin) then
                local lhs = lower_scalar_expr(fact.lhs, index_id, cmds)
                local rhs = lower_scalar_expr(fact.rhs, index_id, cmds)
                local dst = next_tmp("chunk.tail.bin")
                cmds[#cmds + 1] = Vec.VecCmdBin(dst, wide_shape, fact.op, lhs, rhs)
                return dst
            end
            error("vector_facts: unsupported chunk scalar expr fact " .. tostring(fact))
        end

        local entry_cmds = {
            Vec.VecCmdConstInt(start_id, wide_elem, induction.start.raw or "0"),
            Vec.VecCmdConstInt(total0, wide_elem, reduction.carry.init.raw or "0"),
            Vec.VecCmdConstInt(stride_id, wide_elem, tostring(lanes * unroll)),
            Vec.VecCmdConstInt(chunk_id, wide_elem, tostring(chunk_elems)),
            Vec.VecCmdBin(count, wide_shape, Vec.VecSub, n_arg, start_id),
            Vec.VecCmdBin(rem, wide_shape, Vec.VecRem, count, stride_id),
            Vec.VecCmdBin(main_count, wide_shape, Vec.VecSub, count, rem),
            Vec.VecCmdBin(main_stop, wide_shape, Vec.VecAdd, start_id, main_count),
            Vec.VecCmdConstInt(zero32, narrow_elem, "0"),
        }
        for u = 1, unroll do
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdSplat(zero_v[u], vshape, zero32)
            local offsets = {}
            for lane = 0, lanes - 1 do offsets[#offsets + 1] = tostring((u - 1) * lanes + lane) end
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdRamp(init_offsets[u], vshape, zero32, offsets)
        end
        for i = 1, #const_facts do
            local scalar_const = value_id("init.i32.scalar." .. const_facts[i].id.text)
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdConstInt(scalar_const, narrow_elem, const_facts[i].expr.raw)
            entry_cmds[#entry_cmds + 1] = Vec.VecCmdSplat(init_consts[i], vshape, scalar_const)
        end
        local outer_cond = value_id("outer.cond")
        local outer_header_cmds = { Vec.VecCmdBin(outer_cond, wide_shape, Vec.VecLt, o_i, main_stop) }
        local outer_body_cmds = {
            Vec.VecCmdBin(raw_chunk_end, wide_shape, Vec.VecAdd, o_i, chunk_id),
            Vec.VecCmdBin(chunk_lt, wide_shape, Vec.VecLt, raw_chunk_end, main_stop),
            Vec.VecCmdSelect(chunk_end, wide_shape, chunk_lt, raw_chunk_end, main_stop),
        }
        local inner_start_args = { o_i }
        for u = 1, unroll do inner_start_args[#inner_start_args + 1] = zero_v[u] end
        for u = 1, unroll do inner_start_args[#inner_start_args + 1] = init_offsets[u] end
        for i = 1, #init_consts do inner_start_args[#inner_start_args + 1] = init_consts[i] end

        local inner_cond = value_id("inner.cond")
        local inner_header_cmds = { Vec.VecCmdBin(inner_cond, wide_shape, Vec.VecLt, ih_i, chunk_end) }
        local inner_body_cmds = {}
        local index32 = {}
        for u = 1, unroll do
            index32[u] = value_id("inner.index32." .. u)
            inner_body_cmds[#inner_body_cmds + 1] = Vec.VecCmdIreduce(index32[u], narrow_elem, ib_i, chosen.narrow_proof)
            local vec_value = lower_vec_expr(reduction.value, index32[u], ib_offsets[u], inner_body_cmds)
            inner_body_cmds[#inner_body_cmds + 1] = Vec.VecCmdBin(next_acc[u], vshape, Vec.VecAdd, ib_acc[u], vec_value)
        end
        local inner_next_i = value_id("inner.next.i")
        inner_body_cmds[#inner_body_cmds + 1] = Vec.VecCmdBin(inner_next_i, wide_shape, Vec.VecAdd, ib_i, stride_id)

        local inner_exit_cmds = {}
        local reduced = o_total
        for u = 1, unroll do
            for lane = 0, lanes - 1 do
                local lane32 = value_id("chunk.reduce.u" .. u .. ".lane" .. lane)
                local lane_wide = value_id("chunk.reduce.u" .. u .. ".wide" .. lane)
                local sum = value_id("chunk.reduce.u" .. u .. ".sum" .. lane)
                inner_exit_cmds[#inner_exit_cmds + 1] = Vec.VecCmdExtractLane(lane32, ie_acc[u], lane)
                inner_exit_cmds[#inner_exit_cmds + 1] = Vec.VecCmdUextend(lane_wide, wide_elem, lane32)
                inner_exit_cmds[#inner_exit_cmds + 1] = Vec.VecCmdBin(sum, wide_shape, Vec.VecAdd, reduced, lane_wide)
                reduced = sum
            end
        end

        local tail_cond = value_id("tail.cond")
        local tail_header_cmds = { Vec.VecCmdBin(tail_cond, wide_shape, Vec.VecLt, t_i, n_arg) }
        local tail_body_cmds = {}
        local tail_value = lower_scalar_expr(reduction.value, tb_i, tail_body_cmds)
        local tail_next_acc = value_id("tail.next.acc")
        local one = value_id("tail.one")
        local tail_next_i = value_id("tail.next.i")
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdBin(tail_next_acc, wide_shape, Vec.VecAdd, tb_acc, tail_value)
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdConstInt(one, wide_elem, "1")
        tail_body_cmds[#tail_body_cmds + 1] = Vec.VecCmdBin(tail_next_i, wide_shape, Vec.VecAdd, tb_i, one)

        local inner_header_params = { value_param(ih_i, wide_shape) }
        local inner_body_params = { value_param(ib_i, wide_shape) }
        local inner_exit_params = {}
        local inner_body_args = { ih_i }
        local inner_exit_args = {}
        local inner_back_args = { inner_next_i }
        for u = 1, unroll do
            inner_header_params[#inner_header_params + 1] = value_param(ih_acc[u], vshape)
            inner_body_params[#inner_body_params + 1] = value_param(ib_acc[u], vshape)
            inner_exit_params[#inner_exit_params + 1] = value_param(ie_acc[u], vshape)
            inner_body_args[#inner_body_args + 1] = ih_acc[u]
            inner_exit_args[#inner_exit_args + 1] = ih_acc[u]
            inner_back_args[#inner_back_args + 1] = next_acc[u]
        end
        for u = 1, unroll do
            inner_header_params[#inner_header_params + 1] = value_param(ih_offsets[u], vshape)
            inner_body_params[#inner_body_params + 1] = value_param(ib_offsets[u], vshape)
            inner_body_args[#inner_body_args + 1] = ih_offsets[u]
            inner_back_args[#inner_back_args + 1] = ib_offsets[u]
        end
        for i = 1, #ih_consts do
            inner_header_params[#inner_header_params + 1] = value_param(ih_consts[i], vshape)
            inner_body_params[#inner_body_params + 1] = value_param(ib_consts[i], vshape)
            inner_body_args[#inner_body_args + 1] = ih_consts[i]
            inner_back_args[#inner_back_args + 1] = ib_consts[i]
        end

        return {
            Vec.VecBlock(entry, func_entry_params(func), entry_cmds, Vec.VecJump(outer_header, { start_id, total0 })),
            Vec.VecBlock(outer_header, { value_param(o_i, wide_shape), value_param(o_total, wide_shape) }, outer_header_cmds, Vec.VecBrIf(outer_cond, outer_body, {}, tail_header, { main_stop, o_total })),
            Vec.VecBlock(outer_body, {}, outer_body_cmds, Vec.VecJump(inner_header, inner_start_args)),
            Vec.VecBlock(inner_header, inner_header_params, inner_header_cmds, Vec.VecBrIf(inner_cond, inner_body, inner_body_args, inner_exit, inner_exit_args)),
            Vec.VecBlock(inner_body, inner_body_params, inner_body_cmds, Vec.VecJump(inner_header, inner_back_args)),
            Vec.VecBlock(inner_exit, inner_exit_params, inner_exit_cmds, Vec.VecJump(outer_header, { chunk_end, reduced })),
            Vec.VecBlock(tail_header, { value_param(t_i, wide_shape), value_param(t_acc, wide_shape) }, tail_header_cmds, Vec.VecBrIf(tail_cond, tail_body, { t_i, t_acc }, exit, { t_acc })),
            Vec.VecBlock(tail_body, { value_param(tb_i, wide_shape), value_param(tb_acc, wide_shape) }, tail_body_cmds, Vec.VecJump(tail_header, { tail_next_i, tail_next_acc })),
            Vec.VecBlock(exit, { value_param(result, wide_shape) }, {}, Vec.VecReturnValue(result)),
        }
    end

    local function collect_func_decisions(func, lanes, unroll, chunk_elems)
        local decisions = {}
        for i = 1, #func.body do
            local stmt = func.body[i]
            if is_class(stmt, Sem.SemStmtLoop) then
                decisions[#decisions + 1] = pvm.one(vector_loop_decision(stmt.loop, lanes, unroll, chunk_elems))
            end
        end
        return decisions
    end

    local function has_vector_decision(decisions)
        for i = 1, #decisions do
            local chosen = decisions[i].chosen
            if is_class(chosen, Vec.VecLoopVector) or is_class(chosen, Vec.VecLoopChunkedNarrowVector) then
                return true
            end
        end
        return false
    end

    local function build_func_blocks(func, decisions)
        for i = 1, #decisions do
            local chosen = decisions[i].chosen
            if is_class(chosen, Vec.VecLoopVector) then
                if #decisions[i].facts.stores > 0 then
                    return build_loop_store_blocks(func, decisions[i])
                end
                return build_loop_vector_blocks(func, decisions[i])
            elseif is_class(chosen, Vec.VecLoopChunkedNarrowVector) then
                return build_loop_chunked_blocks(func, decisions[i])
            end
        end
        return {}
    end

    vector_func = pvm.phase("moonlift_vec_func", {
        [Sem.SemFuncLocal] = function(self, lanes, unroll, chunk_elems)
            local decisions = collect_func_decisions(self, lanes, unroll, chunk_elems)
            if has_vector_decision(decisions) then
                return pvm.once(Vec.VecFuncVector(self, decisions, build_func_blocks(self, decisions)))
            end
            return pvm.once(Vec.VecFuncScalar(self, decisions))
        end,
        [Sem.SemFuncExport] = function(self, lanes, unroll, chunk_elems)
            local decisions = collect_func_decisions(self, lanes, unroll, chunk_elems)
            if has_vector_decision(decisions) then
                return pvm.once(Vec.VecFuncVector(self, decisions, build_func_blocks(self, decisions)))
            end
            return pvm.once(Vec.VecFuncScalar(self, decisions))
        end,
    })

    vector_module = pvm.phase("moonlift_vec_module", {
        [Sem.SemModule] = function(self, target, lanes, unroll, chunk_elems)
            target = target or Vec.VecTargetModel(Vec.VecTargetCraneliftJit, {})
            local funcs = {}
            for i = 1, #self.items do
                local item = self.items[i]
                if is_class(item, Sem.SemItemFunc) then
                    funcs[#funcs + 1] = pvm.one(vector_func(item.func, lanes, unroll, chunk_elems))
                end
            end
            return pvm.once(Vec.VecModule(self, target, funcs))
        end,
    })

    return {
        vector_expr = vector_expr,
        vector_stmt = vector_stmt,
        vector_domain = vector_domain,
        vector_loop_facts = vector_loop_facts,
        vector_loop_decision = vector_loop_decision,
        vector_func = vector_func,
        vector_module = vector_module,
    }
end

return M
