local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.MoonCore
    local Ty = T.MoonType
    local B = T.MoonBind
    local Tr = T.MoonTree
    local V = T.MoonVec

    local expr_ty_api = require("moonlift.tree_expr_type").Define(T)
    local control_api = require("moonlift.tree_control_facts").Define(T)

    local bin_op
    local view_access_pattern
    local index_base_memory_base
    local place_memory_base
    local memory_base_alias
    local expr_facts
    local store_place_facts
    local stmt_facts
    local control_stmt_facts
    local control_expr_facts

    local function append_all(out, xs) for i = 1, #xs do out[#out + 1] = xs[i] end end
    local function expr_id(path) return V.VecExprId(path) end
    local function access_id(path) return V.VecAccessId(path) end
    local function region_loop_id(region_id) return V.VecLoopId(region_id) end
    local function label_key(label) return label.name end

    local function binding_same_slot(a, b)
        if a == b then return true end
        if a.name ~= b.name then return false end
        local ca, cb = pvm.classof(a.class), pvm.classof(b.class)
        if ca == B.BindingClassArg and cb == B.BindingClassArg then return a.class.index == b.class.index end
        if ca == B.BindingClassEntryBlockParam and cb == B.BindingClassEntryBlockParam then
            return a.class.region_id == b.class.region_id and a.class.block_name == b.class.block_name and a.class.index == b.class.index
        end
        if ca == B.BindingClassBlockParam and cb == B.BindingClassBlockParam then
            return a.class.region_id == b.class.region_id and a.class.block_name == b.class.block_name and a.class.index == b.class.index
        end
        return false
    end

    local function lookup_local(env, binding)
        for i = #env.locals, 1, -1 do
            local local_fact = env.locals[i]
            if binding_same_slot(local_fact.binding, binding) then return local_fact end
        end
        return nil
    end

    local function ty_of(expr)
        return expr_ty_api.type(expr) or Ty.TScalar(C.ScalarVoid)
    end

    local function literal_int_raw(expr)
        if pvm.classof(expr) == Tr.ExprLit and pvm.classof(expr.value) == C.LitInt then return expr.value.raw end
        return nil
    end

    local function empty_stmt()
        return V.VecStmtIgnored({}, {}, {}, {})
    end

    local function result_append(a, b)
        local exprs = {}; append_all(exprs, a.facts); append_all(exprs, b.facts)
        local memory = {}; append_all(memory, a.memory); append_all(memory, b.memory)
        local ranges = {}; append_all(ranges, a.ranges); append_all(ranges, b.ranges)
        local rejects = {}; append_all(rejects, a.rejects); append_all(rejects, b.rejects)
        return exprs, memory, ranges, rejects
    end

    local function reject_expr(expr, path, reason)
        local id = expr_id(path)
        local reject = V.VecRejectUnsupportedExpr(id, reason)
        return V.VecExprResult(id, { V.VecExprRejected(id, reject) }, {}, { V.VecRangeUnknown(id) }, { reject }, ty_of(expr))
    end

    local function reject_stmt(path, reason)
        return V.VecStmtIgnored({}, {}, {}, { V.VecRejectUnsupportedStmt(path, reason) })
    end

    local function bounds_unknown(id)
        local reject = V.VecRejectUnsupportedMemory(id, "bounds proof deferred")
        return V.VecBoundsUnknown(reject)
    end

    bin_op = pvm.phase("moonlift_vec_bin_op", {
        [C.BinAdd] = function() return pvm.once(V.VecAdd) end,
        [C.BinSub] = function() return pvm.once(V.VecSub) end,
        [C.BinMul] = function() return pvm.once(V.VecMul) end,
        [C.BinRem] = function() return pvm.once(V.VecRem) end,
        [C.BinBitAnd] = function() return pvm.once(V.VecBitAnd) end,
        [C.BinBitOr] = function() return pvm.once(V.VecBitOr) end,
        [C.BinBitXor] = function() return pvm.once(V.VecBitXor) end,
        [C.BinShl] = function() return pvm.once(V.VecShl) end,
        [C.BinLShr] = function() return pvm.once(V.VecLShr) end,
        [C.BinAShr] = function() return pvm.once(V.VecAShr) end,
        [C.BinDiv] = function() return pvm.empty() end,
    })

    view_access_pattern = pvm.phase("moonlift_vec_view_access_pattern", {
        [Tr.ViewFromExpr] = function() return pvm.once(V.VecAccessUnknown) end,
        [Tr.ViewContiguous] = function() return pvm.once(V.VecAccessContiguous) end,
        [Tr.ViewStrided] = function(self)
            local raw = literal_int_raw(self.stride)
            if raw == "1" then return pvm.once(V.VecAccessContiguous) end
            local stride = raw and tonumber(raw) or nil
            if stride ~= nil then return pvm.once(V.VecAccessStrided(stride)) end
            return pvm.once(V.VecAccessUnknown)
        end,
        [Tr.ViewRestrided] = function() return pvm.once(V.VecAccessUnknown) end,
        [Tr.ViewWindow] = function() return pvm.once(V.VecAccessContiguous) end,
        [Tr.ViewRowBase] = function() return pvm.once(V.VecAccessUnknown) end,
        [Tr.ViewInterleaved] = function() return pvm.once(V.VecAccessUnknown) end,
        [Tr.ViewInterleavedView] = function() return pvm.once(V.VecAccessUnknown) end,
    })

    index_base_memory_base = pvm.phase("moonlift_vec_index_base_memory_base", {
        [Tr.IndexBaseExpr] = function(self) return pvm.once(V.VecMemoryBaseRawAddr(self.base)) end,
        [Tr.IndexBaseView] = function(self) return pvm.once(V.VecMemoryBaseView(self.view)) end,
        [Tr.IndexBasePlace] = function(self) return pvm.once(V.VecMemoryBasePlace(self.base)) end,
    })

    local function index_base_access_pattern(base)
        if pvm.classof(base) == Tr.IndexBaseView then return pvm.one(view_access_pattern(base.view)) end
        return V.VecAccessUnknown
    end

    place_memory_base = pvm.phase("moonlift_vec_place_memory_base", {
        [Tr.PlaceRef] = function(self) return pvm.once(V.VecMemoryBasePlace(self)) end,
        [Tr.PlaceDeref] = function(self) return pvm.once(V.VecMemoryBaseRawAddr(self.base)) end,
        [Tr.PlaceDot] = function(self) return pvm.once(V.VecMemoryBasePlace(self)) end,
        [Tr.PlaceField] = function(self) return pvm.once(V.VecMemoryBasePlace(self)) end,
        [Tr.PlaceIndex] = function(self) return index_base_memory_base(self.base) end,
        [Tr.PlaceSlotValue] = function(self) return pvm.once(V.VecMemoryBasePlace(self)) end,
    })

    memory_base_alias = pvm.phase("moonlift_vec_memory_base_alias", {
        [V.VecMemoryBaseRawAddr] = function(self, other, a, b)
            if other == self then return pvm.once(V.VecAccessSameBase(a, b, "same raw-address expression")) end
            return pvm.once(V.VecAliasUnknown(a, b, V.VecRejectUnsupportedMemory(a, "raw-address alias proof is unknown")))
        end,
        [V.VecMemoryBaseView] = function(self, other, a, b)
            if other == self then return pvm.once(V.VecAccessSameBase(a, b, "same view base")) end
            return pvm.once(V.VecAliasUnknown(a, b, V.VecRejectUnsupportedMemory(a, "view alias proof is unknown")))
        end,
        [V.VecMemoryBasePlace] = function(self, other, a, b)
            if other == self then return pvm.once(V.VecAccessSameBase(a, b, "same place base")) end
            return pvm.once(V.VecAliasUnknown(a, b, V.VecRejectUnsupportedMemory(a, "place alias proof is unknown")))
        end,
    }, { args_cache = "last" })

    expr_facts = pvm.phase("moonlift_vec_expr_facts", {
        [Tr.ExprLit] = function(expr, env, path)
            local id = expr_id(path)
            local ty = ty_of(expr)
            local facts = { V.VecExprConst(id, expr, ty) }
            local ranges = {}
            if pvm.classof(expr.value) == C.LitInt then ranges[#ranges + 1] = V.VecRangeExact(id, expr.value.raw) else ranges[#ranges + 1] = V.VecRangeUnknown(id) end
            return pvm.once(V.VecExprResult(id, facts, {}, ranges, {}, ty))
        end,
        [Tr.ExprRef] = function(expr, env, path)
            local id = expr_id(path)
            local ty = ty_of(expr)
            if pvm.classof(expr.ref) == B.ValueRefBinding then
                if binding_same_slot(expr.ref.binding, env.index) then
                    return pvm.once(V.VecExprResult(id, { V.VecExprLaneIndex(id, expr.ref.binding, ty) }, {}, { V.VecRangeUnknown(id) }, {}, ty))
                end
                local local_fact = lookup_local(env, expr.ref.binding)
                if local_fact ~= nil then
                    return pvm.once(V.VecExprResult(id, { V.VecExprLocal(id, expr.ref.binding, local_fact.value, ty) }, {}, { V.VecRangeUnknown(id) }, {}, ty))
                end
            end
            return pvm.once(V.VecExprResult(id, { V.VecExprInvariant(id, expr, ty) }, {}, { V.VecRangeUnknown(id) }, {}, ty))
        end,
        [Tr.ExprBinary] = function(expr, env, path)
            local lhs = pvm.one(expr_facts(expr.lhs, env, path .. ".lhs"))
            local rhs = pvm.one(expr_facts(expr.rhs, env, path .. ".rhs"))
            local id = expr_id(path)
            local op = pvm.drain(bin_op(expr.op))[1]
            local facts, memory, ranges, rejects = result_append(lhs, rhs)
            local ty = ty_of(expr)
            if op == nil then
                rejects[#rejects + 1] = V.VecRejectUnsupportedExpr(id, "unsupported binary op")
                facts[#facts + 1] = V.VecExprRejected(id, rejects[#rejects])
            else
                facts[#facts + 1] = V.VecExprBin(id, op, lhs.value, rhs.value, ty)
            end
            ranges[#ranges + 1] = V.VecRangeUnknown(id)
            return pvm.once(V.VecExprResult(id, facts, memory, ranges, rejects, ty))
        end,
        [Tr.ExprUnary] = function(expr, env, path)
            local value = pvm.one(expr_facts(expr.value, env, path .. ".value"))
            local id = expr_id(path)
            local facts = {}; append_all(facts, value.facts)
            local memory = {}; append_all(memory, value.memory)
            local ranges = {}; append_all(ranges, value.ranges); ranges[#ranges + 1] = V.VecRangeUnknown(id)
            local rejects = {}; append_all(rejects, value.rejects)
            if expr.op == C.UnaryNot then
                facts[#facts + 1] = V.VecExprUnary(id, V.VecNot, value.value, ty_of(expr))
            else
                rejects[#rejects + 1] = V.VecRejectUnsupportedExpr(id, "unsupported unary op")
                facts[#facts + 1] = V.VecExprRejected(id, rejects[#rejects])
            end
            return pvm.once(V.VecExprResult(id, facts, memory, ranges, rejects, ty_of(expr)))
        end,
        [Tr.ExprCompare] = function(expr, env, path)
            local lhs = pvm.one(expr_facts(expr.lhs, env, path .. ".lhs"))
            local rhs = pvm.one(expr_facts(expr.rhs, env, path .. ".rhs"))
            local id = expr_id(path)
            local facts = {}; append_all(facts, lhs.facts); append_all(facts, rhs.facts)
            local memory = {}; append_all(memory, lhs.memory); append_all(memory, rhs.memory)
            local ranges = {}; append_all(ranges, lhs.ranges); append_all(ranges, rhs.ranges); ranges[#ranges + 1] = V.VecRangeUnknown(id)
            local rejects = {}; append_all(rejects, lhs.rejects); append_all(rejects, rhs.rejects)
            local op = nil
            if expr.op == C.CmpEq then op = V.VecEq elseif expr.op == C.CmpNe then op = V.VecNe elseif expr.op == C.CmpLt then op = V.VecLt elseif expr.op == C.CmpLe then op = V.VecLe elseif expr.op == C.CmpGt then op = V.VecGt elseif expr.op == C.CmpGe then op = V.VecGe end
            if op ~= nil then facts[#facts + 1] = V.VecExprBin(id, op, lhs.value, rhs.value, ty_of(expr)) end
            return pvm.once(V.VecExprResult(id, facts, memory, ranges, rejects, ty_of(expr)))
        end,
        [Tr.ExprLogic] = function(expr, env, path)
            local lhs = pvm.one(expr_facts(expr.lhs, env, path .. ".lhs"))
            local rhs = pvm.one(expr_facts(expr.rhs, env, path .. ".rhs"))
            local id = expr_id(path)
            local facts, memory, ranges, rejects = result_append(lhs, rhs)
            local op = nil
            if expr.op == C.LogicAnd then op = V.VecBitAnd elseif expr.op == C.LogicOr then op = V.VecBitOr end
            if op ~= nil then facts[#facts + 1] = V.VecExprBin(id, op, lhs.value, rhs.value, ty_of(expr))
            else rejects[#rejects + 1] = V.VecRejectUnsupportedExpr(id, "unsupported logic op"); facts[#facts + 1] = V.VecExprRejected(id, rejects[#rejects]) end
            ranges[#ranges + 1] = V.VecRangeUnknown(id)
            return pvm.once(V.VecExprResult(id, facts, memory, ranges, rejects, ty_of(expr)))
        end,
        [Tr.ExprCast] = function(expr, env, path) return expr_facts(expr.value, env, path .. ".cast") end,
        [Tr.ExprMachineCast] = function(expr, env, path) return expr_facts(expr.value, env, path .. ".cast") end,
        [Tr.ExprLoad] = function(expr, env, path)
            local addr = pvm.one(expr_facts(expr.addr, env, path .. ".addr"))
            local id = expr_id(path)
            local facts = {}; append_all(facts, addr.facts)
            local memory = {}; append_all(memory, addr.memory)
            local ranges = {}; append_all(ranges, addr.ranges); ranges[#ranges + 1] = V.VecRangeUnknown(id)
            local rejects = {}; append_all(rejects, addr.rejects)
            local access = V.VecMemoryAccess(access_id(path), V.VecAccessLoad, V.VecMemoryBaseRawAddr(expr.addr), addr.value, expr.ty, V.VecAccessUnknown, V.VecAlignmentUnknown, bounds_unknown(access_id(path)))
            memory[#memory + 1] = access
            facts[#facts + 1] = V.VecExprLoad(id, access_id(path), expr.ty)
            return pvm.once(V.VecExprResult(id, facts, memory, ranges, rejects, expr.ty))
        end,
        [Tr.ExprCall] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "call facts deferred")) end,
        [Tr.ExprLen] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "len facts are only used as loop-domain stops initially")) end,
        [Tr.ExprDot] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "dot facts deferred")) end,
        [Tr.ExprAddrOf] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "address facts deferred")) end,
        [Tr.ExprDeref] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "deref facts deferred")) end,
        [Tr.ExprField] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "field facts deferred")) end,
        [Tr.ExprIndex] = function(expr, env, path)
            local index = pvm.one(expr_facts(expr.index, env, path .. ".index"))
            local id = expr_id(path)
            local facts = {}; append_all(facts, index.facts)
            local memory = {}; append_all(memory, index.memory)
            local ranges = {}; append_all(ranges, index.ranges); ranges[#ranges + 1] = V.VecRangeUnknown(id)
            local rejects = {}; append_all(rejects, index.rejects)
            local access = V.VecMemoryAccess(access_id(path), V.VecAccessLoad, pvm.one(index_base_memory_base(expr.base)), index.value, ty_of(expr), index_base_access_pattern(expr.base), V.VecAlignmentUnknown, bounds_unknown(access_id(path)))
            memory[#memory + 1] = access
            facts[#facts + 1] = V.VecExprLoad(id, access_id(path), ty_of(expr))
            return pvm.once(V.VecExprResult(id, facts, memory, ranges, rejects, ty_of(expr)))
        end,
        [Tr.ExprAgg] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "aggregate facts deferred")) end,
        [Tr.ExprArray] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "array facts deferred")) end,
        [Tr.ExprIf] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "if facts deferred")) end,
        [Tr.ExprSelect] = function(expr, env, path)
            local cond = pvm.one(expr_facts(expr.cond, env, path .. ".cond"))
            local then_value = pvm.one(expr_facts(expr.then_expr, env, path .. ".then"))
            local else_value = pvm.one(expr_facts(expr.else_expr, env, path .. ".else"))
            local id = expr_id(path)
            local facts = {}; append_all(facts, cond.facts); append_all(facts, then_value.facts); append_all(facts, else_value.facts)
            local memory = {}; append_all(memory, cond.memory); append_all(memory, then_value.memory); append_all(memory, else_value.memory)
            local ranges = {}; append_all(ranges, cond.ranges); append_all(ranges, then_value.ranges); append_all(ranges, else_value.ranges); ranges[#ranges + 1] = V.VecRangeUnknown(id)
            local rejects = {}; append_all(rejects, cond.rejects); append_all(rejects, then_value.rejects); append_all(rejects, else_value.rejects)
            facts[#facts + 1] = V.VecExprSelect(id, cond.value, then_value.value, else_value.value, ty_of(expr))
            return pvm.once(V.VecExprResult(id, facts, memory, ranges, rejects, ty_of(expr)))
        end,
        [Tr.ExprSwitch] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "switch facts deferred")) end,
        [Tr.ExprControl] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "control expression vector recognition deferred")) end,
        [Tr.ExprBlock] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "block expr facts deferred")) end,
        [Tr.ExprClosure] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "closure facts deferred")) end,
        [Tr.ExprView] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "view facts deferred")) end,
        [Tr.ExprSlotValue] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "slot facts deferred")) end,
        [Tr.ExprUseExprFrag] = function(expr, env, path) return pvm.once(reject_expr(expr, path, "fragment facts deferred")) end,
    }, { args_cache = "last" })

    store_place_facts = pvm.phase("moonlift_vec_store_place_facts", {
        [Tr.PlaceIndex] = function(place, value, env, path)
            local index = pvm.one(expr_facts(place.index, env, path .. ".index"))
            local facts = {}; append_all(facts, value.facts); append_all(facts, index.facts)
            local memory = {}; append_all(memory, value.memory); append_all(memory, index.memory)
            local ranges = {}; append_all(ranges, value.ranges); append_all(ranges, index.ranges)
            local rejects = {}; append_all(rejects, value.rejects); append_all(rejects, index.rejects)
            local access = V.VecMemoryAccess(access_id(path), V.VecAccessStore, pvm.one(index_base_memory_base(place.base)), index.value, value.ty, index_base_access_pattern(place.base), V.VecAlignmentUnknown, bounds_unknown(access_id(path)))
            local store = V.VecStoreFact(access, value.value)
            memory[#memory + 1] = access
            return pvm.once(V.VecStmtStore(store, facts, memory, ranges, rejects))
        end,
        [Tr.PlaceRef] = function(_, value, _, path) local rejects = {}; append_all(rejects, value.rejects); rejects[#rejects + 1] = V.VecRejectUnsupportedStmt(path, "non-index store facts deferred"); return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, rejects)) end,
        [Tr.PlaceDeref] = function(_, value, _, path) local rejects = {}; append_all(rejects, value.rejects); rejects[#rejects + 1] = V.VecRejectUnsupportedStmt(path, "deref store facts deferred"); return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, rejects)) end,
        [Tr.PlaceDot] = function(_, value, _, path) local rejects = {}; append_all(rejects, value.rejects); rejects[#rejects + 1] = V.VecRejectUnsupportedStmt(path, "dot store facts deferred"); return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, rejects)) end,
        [Tr.PlaceField] = function(_, value, _, path) local rejects = {}; append_all(rejects, value.rejects); rejects[#rejects + 1] = V.VecRejectUnsupportedStmt(path, "field store facts deferred"); return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, rejects)) end,
        [Tr.PlaceSlotValue] = function(_, value, _, path) local rejects = {}; append_all(rejects, value.rejects); rejects[#rejects + 1] = V.VecRejectUnsupportedStmt(path, "slot store facts deferred"); return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, rejects)) end,
    }, { args_cache = "last" })

    stmt_facts = pvm.phase("moonlift_vec_stmt_facts", {
        [Tr.StmtLet] = function(stmt, env, path)
            local value = pvm.one(expr_facts(stmt.init, env, path .. ".init"))
            local local_fact = V.VecLocalFact(stmt.binding, value.value, stmt.binding.ty)
            return pvm.once(V.VecStmtLocal(local_fact, value.facts, value.memory, value.ranges, value.rejects))
        end,
        [Tr.StmtExpr] = function(stmt, env, path)
            local value = pvm.one(expr_facts(stmt.expr, env, path .. ".expr"))
            return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, value.rejects))
        end,
        [Tr.StmtSet] = function(stmt, env, path)
            local value = pvm.one(expr_facts(stmt.value, env, path .. ".value"))
            return store_place_facts(stmt.place, value, env, path .. ".store")
        end,
        [Tr.StmtAssert] = function(stmt, env, path) local value = pvm.one(expr_facts(stmt.cond, env, path .. ".cond")); return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, value.rejects)) end,
        [Tr.StmtReturnVoid] = function() return pvm.once(empty_stmt()) end,
        [Tr.StmtReturnValue] = function(stmt, env, path) local value = pvm.one(expr_facts(stmt.value, env, path .. ".ret")); return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, value.rejects)) end,
        [Tr.StmtVar] = function(stmt, env, path) return stmt_facts(Tr.StmtLet(stmt.h, stmt.binding, stmt.init), env, path) end,
        [Tr.StmtIf] = function(_, _, path) return pvm.once(reject_stmt(path, "if stmt facts deferred")) end,
        [Tr.StmtSwitch] = function(_, _, path) return pvm.once(reject_stmt(path, "switch stmt facts deferred")) end,
        [Tr.StmtJump] = function(stmt, env, path)
            local facts, memory, ranges, rejects = {}, {}, {}, { V.VecRejectUnsupportedStmt(path, "jump/control vector recognition deferred") }
            for i = 1, #stmt.args do
                local value = pvm.one(expr_facts(stmt.args[i].value, env, path .. ".arg." .. stmt.args[i].name))
                append_all(facts, value.facts)
                append_all(memory, value.memory)
                append_all(ranges, value.ranges)
                append_all(rejects, value.rejects)
            end
            return pvm.once(V.VecStmtIgnored(facts, memory, ranges, rejects))
        end,
        [Tr.StmtJumpCont] = function(stmt, env, path)
            local facts, memory, ranges, rejects = {}, {}, {}, { V.VecRejectUnsupportedStmt(path, "continuation jump vector recognition deferred") }
            for i = 1, #stmt.args do
                local value = pvm.one(expr_facts(stmt.args[i].value, env, path .. ".arg." .. stmt.args[i].name))
                append_all(facts, value.facts)
                append_all(memory, value.memory)
                append_all(ranges, value.ranges)
                append_all(rejects, value.rejects)
            end
            return pvm.once(V.VecStmtIgnored(facts, memory, ranges, rejects))
        end,
        [Tr.StmtYieldVoid] = function() return pvm.once(empty_stmt()) end,
        [Tr.StmtYieldValue] = function(stmt, env, path) local value = pvm.one(expr_facts(stmt.value, env, path .. ".yield")); return pvm.once(V.VecStmtIgnored(value.facts, value.memory, value.ranges, value.rejects)) end,
        [Tr.StmtControl] = function(stmt) return control_stmt_facts(stmt.region) end,
        [Tr.StmtUseRegionSlot] = function() return pvm.once(empty_stmt()) end,
        [Tr.StmtUseRegionFrag] = function(_, _, path) return pvm.once(reject_stmt(path, "region fragment facts deferred")) end,
    }, { args_cache = "last" })

    local function unsupported_control_region(region_id, reason)
        local reject = V.VecRejectUnsupportedLoop(region_loop_id(region_id), reason)
        return V.VecLoopFacts(region_loop_id(region_id), V.VecLoopSourceRejected(reject), V.VecDomainRejected(reject), {}, V.VecExprGraph({}), {}, {}, {}, {}, {}, {}, {}, { reject })
    end

    local function param_binding(region_id, label, index, param, is_entry)
        local class
        if is_entry then class = B.BindingClassEntryBlockParam(region_id, label.name, index) else class = B.BindingClassBlockParam(region_id, label.name, index) end
        return B.Binding(C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. param.name), param.name, param.ty, class)
    end

    local function ref_binding(expr)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefBinding then return expr.ref.binding end
        return nil
    end

    local function same_param_ref(expr, binding)
        local b = ref_binding(expr)
        return b ~= nil and binding_same_slot(b, binding)
    end

    local function find_self_jump(region)
        local body = region.entry.body
        if #body == 0 then return nil end
        local last = body[#body]
        if pvm.classof(last) == Tr.StmtJump and label_key(last.target) == label_key(region.entry.label) then return last end
        return nil
    end

    local function body_exits_region(body)
        for i = 1, #body do
            local cls = pvm.classof(body[i])
            if cls == Tr.StmtYieldVoid or cls == Tr.StmtYieldValue or cls == Tr.StmtReturnVoid or cls == Tr.StmtReturnValue then return true end
            if cls == Tr.StmtJump then return false end
        end
        return false
    end

    local function exit_test_from_condition(cond, bindings)
        if pvm.classof(cond) ~= Tr.ExprCompare then return nil, nil end
        if cond.op == C.CmpGe then
            for i = 1, #bindings do
                if same_param_ref(cond.lhs, bindings[i]) then return i, cond.rhs end
            end
        elseif cond.op == C.CmpLe then
            for i = 1, #bindings do
                if same_param_ref(cond.rhs, bindings[i]) then return i, cond.lhs end
            end
        end
        return nil, nil
    end

    local function is_terminal_exit_if(stmt, bindings)
        if pvm.classof(stmt) ~= Tr.StmtIf or #stmt.then_body == 0 or #stmt.else_body ~= 0 or not body_exits_region(stmt.then_body) then return false end
        local index_i = exit_test_from_condition(stmt.cond, bindings)
        return index_i ~= nil
    end

    local function find_exit_test(region, bindings)
        for i = 1, #region.entry.body do
            local stmt = region.entry.body[i]
            if is_terminal_exit_if(stmt, bindings) then
                local index_i, stop = exit_test_from_condition(stmt.cond, bindings)
                return index_i, stop
            end
        end
        return nil, nil
    end

    local function append_stmt_result(out, result)
        append_all(out.exprs, result.facts)
        append_all(out.memory, result.memory)
        append_all(out.ranges, result.ranges)
        append_all(out.rejects, result.rejects)
        if pvm.classof(result) == V.VecStmtLocal then out.locals[#out.locals + 1] = result["local"] end
        if pvm.classof(result) == V.VecStmtStore then out.stores[#out.stores + 1] = result.store end
    end

    local function expr_fact_map(exprs)
        local out = {}
        for i = 1, #exprs do out[exprs[i].id] = exprs[i] end
        return out
    end

    local function index_is_lane_index(map, id)
        local fact = map[id]
        if fact == nil then return false end
        local cls = pvm.classof(fact)
        if cls == V.VecExprLaneIndex then return true end
        if cls == V.VecExprLocal then return index_is_lane_index(map, fact.value) end
        return false
    end

    local function alias_is_same_base(alias)
        return pvm.classof(alias) == V.VecAccessSameBase
    end

    local function build_alias_dependence_facts(memory, exprs)
        local aliases = {}
        local dependences = {}
        local map = expr_fact_map(exprs)
        for i = 1, #memory do
            local a = memory[i]
            for j = i + 1, #memory do
                local b = memory[j]
                local alias = pvm.one(memory_base_alias(a.base, b.base, a.id, b.id))
                aliases[#aliases + 1] = alias
                if a.access_kind == V.VecAccessStore or b.access_kind == V.VecAccessStore then
                    if alias_is_same_base(alias)
                        and a.pattern == V.VecAccessContiguous
                        and b.pattern == V.VecAccessContiguous
                        and index_is_lane_index(map, a.index)
                        and index_is_lane_index(map, b.index) then
                        local proof = V.VecProofNoMemoryDependence({ a.id, b.id }, "same contiguous base and lane-indexed accesses")
                        dependences[#dependences + 1] = V.VecNoDependence(a.id, b.id, proof)
                    else
                        local reject = V.VecRejectUnsupportedMemory(a.id, "memory dependence proof is unknown for this access pair")
                        dependences[#dependences + 1] = V.VecDependenceUnknown(a.id, b.id, reject)
                    end
                end
            end
        end
        return aliases, dependences
    end

    local function find_arg(args, name)
        local found = nil
        for i = 1, #args do if args[i].name == name then found = args[i] end end
        return found
    end

    local function update_add_step(expr, binding)
        if pvm.classof(expr) ~= Tr.ExprBinary or expr.op ~= C.BinAdd then return nil end
        if same_param_ref(expr.lhs, binding) then return expr.rhs end
        if same_param_ref(expr.rhs, binding) then return expr.lhs end
        return nil
    end

    local function reduction_from_update(binding, value, env, path)
        if pvm.classof(value) ~= Tr.ExprBinary then return nil, nil end
        local op = value.op
        local contribution_id = nil
        if same_param_ref(value.lhs, binding) then contribution_id = expr_id(path .. ".rhs") elseif same_param_ref(value.rhs, binding) then contribution_id = expr_id(path .. ".lhs") end
        if contribution_id == nil then return nil, nil end
        local facts = pvm.one(expr_facts(value, env, path))
        local reduction = nil
        if op == C.BinAdd then reduction = V.VecReductionAdd(binding, contribution_id, V.VecReassocWrapping)
        elseif op == C.BinMul then reduction = V.VecReductionMul(binding, contribution_id, V.VecReassocWrapping)
        elseif op == C.BinBitAnd then reduction = V.VecReductionBitAnd(binding, contribution_id)
        elseif op == C.BinBitOr then reduction = V.VecReductionBitOr(binding, contribution_id)
        elseif op == C.BinBitXor then reduction = V.VecReductionBitXor(binding, contribution_id)
        end
        return reduction, facts
    end

    local function recognized_control_region(region)
        local control_decision = control_api.decide(region)
        if pvm.classof(control_decision) == Tr.ControlDecisionIrreducible then return nil, "invalid control region" end
        if #region.blocks ~= 0 then return nil, "multi-block vector loop recognition deferred" end
        local jump = find_self_jump(region)
        if jump == nil then return nil, "missing self backedge jump" end

        local params = region.entry.params
        local bindings = {}
        for i = 1, #params do bindings[i] = param_binding(region.region_id, region.entry.label, i, params[i], true) end

        local index_i, stop = find_exit_test(region, bindings)
        if index_i == nil then return nil, "missing canonical terminal counted-loop exit test" end

        local index_binding = bindings[index_i]
        local index_arg = find_arg(jump.args, params[index_i].name)
        if index_arg == nil then return nil, "missing primary induction jump arg" end
        local step = update_add_step(index_arg.value, index_binding)
        if step == nil then return nil, "primary induction is not updated by i + step" end

        local locals = {}
        for i = 1, #params do locals[#locals + 1] = V.VecLocalFact(bindings[i], expr_id("param." .. params[i].name), params[i].ty) end
        local env = V.VecExprEnv(index_binding, locals)
        local exprs, memory, ranges, rejects = {}, {}, {}, {}
        local stores = {}
        local reductions = {}
        local body_out = { exprs = exprs, memory = memory, ranges = ranges, rejects = rejects, stores = stores, locals = locals }
        for i = 1, #region.entry.body - 1 do
            local stmt = region.entry.body[i]
            if not is_terminal_exit_if(stmt, bindings) then
                append_stmt_result(body_out, pvm.one(stmt_facts(stmt, env, "body." .. tostring(i))))
            end
        end
        for i = 1, #params do
            if i ~= index_i then
                local arg = find_arg(jump.args, params[i].name)
                if arg ~= nil then
                    local reduction, update_facts = reduction_from_update(bindings[i], arg.value, env, "jump." .. params[i].name)
                    if update_facts ~= nil then
                        append_all(exprs, update_facts.facts)
                        append_all(memory, update_facts.memory)
                        append_all(ranges, update_facts.ranges)
                        append_all(rejects, update_facts.rejects)
                    end
                    if reduction ~= nil then reductions[#reductions + 1] = reduction end
                end
            end
        end
        local step_facts = pvm.one(expr_facts(step, env, "domain.step"))
        append_all(exprs, step_facts.facts); append_all(memory, step_facts.memory); append_all(ranges, step_facts.ranges); append_all(rejects, step_facts.rejects)
        local aliases, dependences = build_alias_dependence_facts(memory, exprs)
        return V.VecLoopFacts(
            region_loop_id(region.region_id),
            V.VecLoopSourceControlRegion(region.region_id, region.entry.label, region.entry.label),
            V.VecDomainCounted(params[index_i].init, stop, step),
            { V.VecPrimaryInduction(index_binding, params[index_i].init, step) },
            V.VecExprGraph(exprs),
            memory,
            aliases,
            dependences,
            ranges,
            stores,
            reductions,
            {},
            rejects
        ), nil
    end

    local function control_region_facts(region)
        local facts, reason = recognized_control_region(region)
        if facts ~= nil then return facts end
        return unsupported_control_region(region.region_id, reason)
    end

    control_stmt_facts = pvm.phase("moonlift_vec_control_stmt_facts", {
        [Tr.ControlStmtRegion] = function(region) return pvm.once(control_region_facts(region)) end,
    })

    control_expr_facts = pvm.phase("moonlift_vec_control_expr_facts", {
        [Tr.ControlExprRegion] = function(region) return pvm.once(control_region_facts(region)) end,
    })

    return {
        bin_op = bin_op,
        expr_facts = expr_facts,
        stmt_facts = stmt_facts,
        control_stmt_facts = control_stmt_facts,
        control_expr_facts = control_expr_facts,
        facts = function(region)
            local cls = pvm.classof(region)
            if cls == Tr.ControlStmtRegion then return pvm.one(control_stmt_facts(region)) end
            if cls == Tr.ControlExprRegion then return pvm.one(control_expr_facts(region)) end
            error("vec_loop_facts expects a ControlStmtRegion or ControlExprRegion", 2)
        end,
    }
end

return M
