local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_value_facts ~= nil then return T._lalin_api_cache.code_value_facts end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Graph = T.LalinGraph
    local Flow = T.LalinFlow
    local Value = T.LalinValue
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local ReductionAlgebra = require("lalin.reduction_algebra")(T)

    local api = {}

    local function identity(reason) return Value.AlgebraProofIdentity(reason) end

    local function int_const_expr(ty, raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(raw))))
    end

    local function exact_int_sem(reason)
        return Code.CodeIntSemantics(Code.CodeIntAssumeNoOverflow(reason), Code.CodeDivTrapOnZero, Code.CodeShiftTrapOutOfRange)
    end

    local function arithmetic_series_expr(init, start, stop, step, ty, sem)
        if init == nil or start == nil or stop == nil or step == nil then return nil end
        local exact_sem = sem or exact_int_sem("arithmetic-series closed form exactness proof")
        local zero = int_const_expr(ty, 0)
        local one = int_const_expr(ty, 1)
        local two = int_const_expr(ty, 2)
        local diff = Value.ValueExprSub(stop, start, ty, exact_sem)
        -- Executed trip count for an increasing exclusive loop is
        -- max(0, ceil((stop - start) / step)).  Use a select so closed-form
        -- replacement preserves the original zero-trip behavior for n <= start.
        local step_minus_one = Value.ValueExprSub(step, one, ty, exact_sem)
        local ceil_num = Value.ValueExprAdd(diff, step_minus_one, ty, exact_sem)
        local trip_pos = Value.ValueExprDiv(ceil_num, step, ty, exact_sem)
        local nonpositive = Value.ValueExprCmp(Core.CmpLe, ty, diff, zero)
        local trip = Value.ValueExprSelect(nonpositive, zero, trip_pos)
        local last_delta = Value.ValueExprMul(Value.ValueExprSub(trip, one, ty, exact_sem), step, ty, exact_sem)
        local first_twice = Value.ValueExprMul(two, start, ty, exact_sem)
        local pair_sum = Value.ValueExprAdd(first_twice, last_delta, ty, exact_sem)
        local series = Value.ValueExprDiv(Value.ValueExprMul(trip, pair_sum, ty, exact_sem), two, ty, exact_sem)
        return Value.ValueExprAdd(init, series, ty, exact_sem)
    end

    local function expr_for(exprs, id)
        return (id and exprs[id.text]) or (id and Value.ValueExprValue(id)) or nil
    end

    local function add_expr_fact(out, exprs, id, expr, proof)
        if id == nil or expr == nil then return end
        exprs[id.text] = expr
        out[#out + 1] = Value.ValueExprFact(id, expr, proof or identity("syntactic Code value expression"))
    end

    function Core.BinaryOp:code_value_int_expr(a, b, ty, sem)
        return nil
    end

    function Core.BinAdd:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprAdd(a, b, ty, sem)
    end

    function Core.BinSub:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprSub(a, b, ty, sem)
    end

    function Core.BinMul:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprMul(a, b, ty, sem)
    end

    function Core.BinDiv:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprDiv(a, b, ty, sem)
    end

    function Core.BinRem:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprRem(a, b, ty, sem)
    end

    function Core.BinBitAnd:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprBinary(self, a, b, ty, sem)
    end

    function Core.BinBitOr:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprBinary(self, a, b, ty, sem)
    end

    function Core.BinBitXor:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprBinary(self, a, b, ty, sem)
    end

    function Core.BinShl:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprBinary(self, a, b, ty, sem)
    end

    function Core.BinLShr:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprBinary(self, a, b, ty, sem)
    end

    function Core.BinAShr:code_value_int_expr(a, b, ty, sem)
        return Value.ValueExprBinary(self, a, b, ty, sem)
    end

    function Core.BinaryOp:code_value_float_expr(a, b, ty)
        return nil
    end

    function Core.BinAdd:code_value_float_expr(a, b, ty)
        return Value.ValueExprAdd(a, b, ty, nil)
    end

    function Core.BinSub:code_value_float_expr(a, b, ty)
        return Value.ValueExprSub(a, b, ty, nil)
    end

    function Core.BinMul:code_value_float_expr(a, b, ty)
        return Value.ValueExprMul(a, b, ty, nil)
    end

    function Core.BinDiv:code_value_float_expr(a, b, ty)
        return Value.ValueExprDiv(a, b, ty, nil)
    end

    function Code.CodeInstOp:code_value_expr_facts(out_values, exprs)
    end

    function Code.CodeInstConst:code_value_expr_facts(out_values, exprs)
        add_expr_fact(out_values, exprs, self.dst, Value.ValueExprConst(self.const), identity("Code constant"))
    end

    function Code.CodeInstAlias:code_value_expr_facts(out_values, exprs)
        add_expr_fact(out_values, exprs, self.dst, expr_for(exprs, self.src), identity("Code alias"))
    end

    function Code.CodeInstUnary:code_value_expr_facts(out_values, exprs)
        add_expr_fact(out_values, exprs, self.dst, Value.ValueExprUnary(self.op, expr_for(exprs, self.value), self.ty), identity("Code unary expression"))
    end

    function Code.CodeInstBinary:code_value_expr_facts(out_values, exprs)
        local expr = self.op:code_value_int_expr(expr_for(exprs, self.lhs), expr_for(exprs, self.rhs), self.ty, self.semantics)
        if expr ~= nil then add_expr_fact(out_values, exprs, self.dst, expr, identity("Code integer binary expression")) end
        if self.semantics ~= nil then
            out_values[#out_values + 1] = Value.ValueNoWrapFact(self.dst, self.semantics, Value.AlgebraProofNoWrap(self.dst, "integer operation carries CodeIntSemantics"))
        end
    end

    function Code.CodeInstFloatBinary:code_value_expr_facts(out_values, exprs)
        local expr = self.op:code_value_float_expr(expr_for(exprs, self.lhs), expr_for(exprs, self.rhs), self.ty)
        if expr ~= nil then add_expr_fact(out_values, exprs, self.dst, expr, identity("Code float expression")) end
        out_values[#out_values + 1] = Value.ValueFloatModeFact(self.dst, self.mode, identity("Code float mode"))
    end

    function Code.CodeInstCompare:code_value_expr_facts(out_values, exprs)
        add_expr_fact(out_values, exprs, self.dst, Value.ValueExprCmp(self.op, self.operand_ty, expr_for(exprs, self.lhs), expr_for(exprs, self.rhs)), identity("Code compare expression"))
    end

    function Code.CodeInstSelect:code_value_expr_facts(out_values, exprs)
        add_expr_fact(out_values, exprs, self.dst, Value.ValueExprSelect(expr_for(exprs, self.cond), expr_for(exprs, self.then_value), expr_for(exprs, self.else_value)), identity("Code select expression"))
    end

    function Code.CodeInstCast:code_value_expr_facts(out_values, exprs)
        add_expr_fact(out_values, exprs, self.dst, Value.ValueExprCast(self.op, self.from, self.to, expr_for(exprs, self.value)), identity("Code cast expression"))
    end

    function Code.CodeFunc:code_value_extract_exprs(out_values, exprs_by_func)
        local exprs = {}
        exprs_by_func[self.id.text] = exprs
        for _, param in ipairs(self.params or {}) do exprs[param.value.text] = Value.ValueExprValue(param.value) end
        for _, block in ipairs(self.blocks or {}) do
            for _, param in ipairs(block.params or {}) do exprs[param.value.text] = Value.ValueExprValue(param.value) end
            for _, inst in ipairs(block.insts or {}) do
                inst.op:code_value_expr_facts(out_values, exprs)
            end
        end
    end

    local function value_defs(func)
        local defs = {}
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do
                local dst = inst.op:code_graph_dst()
                if dst ~= nil then defs[dst.text] = { inst = inst, op = inst.op, block = block } end
            end
        end
        return defs
    end

    local function graph_loop_index(graph)
        local by_id = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do by_id[loop.id.text] = loop end
        end
        return by_id
    end

    local function edge_fact_index(flow)
        local by_key = {}
        for _, fact in ipairs(flow and flow.edges or {}) do
            by_key[fact.edge.from.block.text .. "\0" .. fact.edge.to.block.text] = fact
        end
        return by_key
    end

    local function block_index(func)
        local by_id = {}
        for _, block in ipairs(func.blocks or {}) do by_id[block.id.text] = block end
        return by_id
    end

    local function backedge_arg(edge_fact, param)
        for _, arg in ipairs(edge_fact and edge_fact.args or {}) do if arg.dst_param == param.value then return arg.src end end
        return nil
    end

    local function incoming_arg(edge_facts, header, param, skip_from)
        for _, fact in ipairs(edge_facts or {}) do
            if fact.edge.to.block == header and fact.edge.from.block ~= skip_from then
                for _, arg in ipairs(fact.args or {}) do if arg.dst_param == param.value then return arg.src end end
            end
        end
        return nil
    end

    local function reduction_op_for(op, is_float)
        return ReductionAlgebra.binary_reduction_op(op, is_float)
    end

    local function canonical_value(value, aliases)
        local seen = {}
        while value ~= nil and aliases ~= nil and aliases[value.text] ~= nil and not seen[value.text] do
            seen[value.text] = true
            value = aliases[value.text]
        end
        return value
    end

    local function same_value(a, b) return a ~= nil and b ~= nil and a == b end

    local function same_canonical_value(a, b, aliases)
        return same_value(canonical_value(a, aliases), canonical_value(b, aliases))
    end

    local function resolve_def(defs, id)
        local seen = {}
        local def = id and defs[id.text] or nil
        while def ~= nil do
            local src = def.op:code_value_alias_src()
            if src == nil or seen[src.text] then break end
            seen[src.text] = true
            def = defs[src.text]
        end
        return def
    end

    function Code.CodeInstOp:code_value_alias_src()
        return nil
    end

    function Code.CodeInstAlias:code_value_alias_src()
        return self.src
    end

    function Code.CodeInstOp:code_value_reduction_step(param, defs, aliases)
        return nil, nil, nil, nil, nil, nil
    end

    function Code.CodeInstBinary:code_value_reduction_step(param, defs, aliases)
        local contribution = nil
        if same_canonical_value(self.lhs, param.value, aliases) then contribution = self.rhs end
        if same_canonical_value(self.rhs, param.value, aliases) then contribution = self.lhs end
        return contribution and reduction_op_for(self.op, false) or nil, contribution, self.ty, self.semantics, nil, self
    end

    function Code.CodeInstFloatBinary:code_value_reduction_step(param, defs, aliases)
        local contribution = nil
        if same_canonical_value(self.lhs, param.value, aliases) then contribution = self.rhs end
        if same_canonical_value(self.rhs, param.value, aliases) then contribution = self.lhs end
        return contribution and reduction_op_for(self.op, true) or nil, contribution, self.ty, nil, self.mode, self
    end

    function Code.CodeInstSelect:code_value_reduction_step(param, defs, aliases)
        local cdef = self.cond and defs[self.cond.text] or nil
        local cmp = cdef and cdef.op:code_value_compare_op() or nil
        if cmp == nil then return nil end
        local lhs, rhs = cmp.lhs, cmp.rhs
        if not ((same_value(self.then_value, lhs) and same_value(self.else_value, rhs)) or (same_value(self.then_value, rhs) and same_value(self.else_value, lhs))) then return nil end
        if not (same_canonical_value(lhs, param.value, aliases) or same_canonical_value(rhs, param.value, aliases)) then return nil end
        local contribution = same_canonical_value(lhs, param.value, aliases) and rhs or lhs
        local true_value_is_lhs = same_value(self.then_value, lhs)
        return ReductionAlgebra.select_minmax_op(cmp.op, true_value_is_lhs), contribution, self.ty or cmp.operand_ty, nil, nil, self
    end

    function Code.CodeInstOp:code_value_compare_op()
        return nil
    end

    function Code.CodeInstCompare:code_value_compare_op()
        return self
    end

    function Code.CodeInstOp:code_value_is_int_binary()
        return false
    end

    function Code.CodeInstBinary:code_value_is_int_binary()
        return true
    end

    function Core.BinaryOp:code_value_closed_form_expr(init, start, stop, step, ty, sem)
        return nil
    end

    function Core.BinAdd:code_value_closed_form_expr(init, start, stop, step, ty, sem)
        return arithmetic_series_expr(init, start, stop, step, ty, sem)
    end

    local function closed_form_for_step(recurrence_op, init, loop_fact, exprs, ty, int_sem)
        if recurrence_op == nil or not recurrence_op:code_value_is_int_binary() then return nil end
        if loop_fact.counted == nil or not loop_fact.counted.stop_exclusive then return nil end
        return recurrence_op.op:code_value_closed_form_expr(
            expr_for(exprs, init),
            expr_for(exprs, loop_fact.counted.start),
            expr_for(exprs, loop_fact.counted.stop),
            expr_for(exprs, loop_fact.counted.step),
            ty,
            int_sem
        )
    end

    local function loop_body_aliases(graph_loop, flow, latch)
        local loop_blocks = {}
        for _, block in ipairs(graph_loop and graph_loop.body or {}) do loop_blocks[block.block.text] = true end
        local aliases = {}
        local changed = true
        while changed do
            changed = false
            for _, fact in ipairs(flow and flow.edges or {}) do
                local edge = fact.edge
                if edge ~= latch and loop_blocks[edge.from.block.text] and loop_blocks[edge.to.block.text] then
                    for _, arg in ipairs(fact.args or {}) do
                        local src = canonical_value(arg.src, aliases)
                        if src ~= nil and src ~= arg.dst_param and aliases[arg.dst_param.text] == nil then
                            aliases[arg.dst_param.text] = src
                            changed = true
                        end
                    end
                end
            end
        end
        return aliases
    end

    local function detect_reductions(module, graph, flow, exprs_by_func)
        local graph_loops = graph_loop_index(graph)
        local edge_facts = edge_fact_index(flow)
        local reductions, closed_forms = {}, {}
        local funcs = {}
        for _, func in ipairs(module.funcs or {}) do funcs[func.id.text] = func end

        for _, loop_fact in ipairs(flow and flow.loops or {}) do
            local graph_loop = graph_loops[loop_fact.loop.text]
            local func = nil
            if graph_loop ~= nil then func = funcs[graph_loop.func.text] end
            if func ~= nil and graph_loop ~= nil and graph_loop.latches[1] ~= nil then
                local blocks = block_index(func)
                local header = blocks[graph_loop.header.block.text]
                local latch = graph_loop.latches[1]
                local latch_fact = edge_facts[latch.from.block.text .. "\0" .. latch.to.block.text]
                local aliases = loop_body_aliases(graph_loop, flow, latch)
                local defs = value_defs(func)
                local exprs = exprs_by_func[func.id.text] or {}
                local primary = {}
                for _, induction in ipairs(loop_fact.inductions or {}) do
                    if induction:code_value_is_primary_induction() then primary[induction.value.text] = true end
                end

                for _, param in ipairs(header and header.params or {}) do
                    if not primary[param.value.text] then
                        local back = backedge_arg(latch_fact, param)
                        local init = incoming_arg(flow.edges, graph_loop.header.block, param, latch.from.block)
                        local def = resolve_def(defs, back)
                        local rop, contribution, rty, int_sem, float_mode, recurrence_op = nil, nil, nil, nil, nil, nil
                        if def ~= nil then
                            rop, contribution, rty, int_sem, float_mode, recurrence_op = def.op:code_value_reduction_step(param, defs, aliases)
                        end
                        if rop ~= nil and contribution ~= nil then
                            local canonical_contribution = canonical_value(contribution, aliases)
                            local domain = Flow.FlowDomainLoop(loop_fact.loop)
                            local proof = Value.AlgebraProofFlow(domain, "loop-carried accumulator recurrence")
                            local reduction = Value.ReductionFact(
                                Value.AlgebraFactId("reduction:" .. sanitize(func.name) .. ":" .. sanitize(loop_fact.loop.text) .. ":" .. sanitize(param.value.text)),
                                domain,
                                param.value,
                                rop,
                                expr_for(exprs, init),
                                expr_for(exprs, canonical_contribution),
                                rty,
                                int_sem,
                                float_mode,
                                proof
                            )
                            reductions[#reductions + 1] = reduction
                            if rop == Value.ReductionAdd and primary[canonical_contribution.text] then
                                local closed_expr = closed_form_for_step(recurrence_op, init, loop_fact, exprs, rty, int_sem)
                                if closed_expr ~= nil then
                                    closed_forms[#closed_forms + 1] = Value.ClosedFormFact(
                                        Value.AlgebraFactId("closed_form:arith_series:" .. sanitize(func.name) .. ":" .. sanitize(loop_fact.loop.text) .. ":" .. sanitize(param.value.text)),
                                        reduction,
                                        closed_expr,
                                        Value.AlgebraProofReduction(reduction, "exact arithmetic-series closed form from counted loop start/stop/step")
                                    )
                                end
                            end
                        end
                    end
                end
            end
        end
        return reductions, closed_forms
    end

    function Flow.FlowInductionRole:code_value_is_primary_induction()
        return false
    end

    function Flow.FlowPrimaryInduction:code_value_is_primary_induction()
        return true
    end

    function Flow.FlowInduction:code_value_is_primary_induction()
        return rawget(self, "role"):code_value_is_primary_induction()
    end

    function Flow.FlowLoopSemanticFact:code_value_append_facts(out_values)
    end

    function Flow.FlowLoopInductionRange:code_value_append_facts(out_values)
        local r = self.range
        out_values[#out_values + 1] = Value.ValueRangeFact(Value.ValueRangeInt(
            r.value,
            Value.ValueExprValue(r.min.value or r.value),
            Value.ValueExprValue(r.max.value or r.value),
            not r.max_exclusive,
            Value.AlgebraProofFlow(Flow.FlowDomainLoop(r.loop), r.reason)
        ))
    end

    function Flow.FlowInduction:code_value_append_facts(loop, out_values)
        out_values[#out_values + 1] = Value.ValueExprFact(
            self.value,
            Value.ValueExprAffine(Value.AffineExpr("0", { Value.AffineTerm(self.value, "1") }, self.ty, nil)),
            Value.AlgebraProofFlow(Flow.FlowDomainLoop(loop.loop), "induction variable affine identity")
        )
    end

    local function add_flow_ranges(flow, out_values)
        for _, fact in ipairs(flow and flow.facts or {}) do
            fact:code_value_append_facts(out_values)
        end
        for _, loop in ipairs(flow and flow.loops or {}) do
            for _, induction in ipairs(loop.inductions or {}) do
                induction:code_value_append_facts(loop, out_values)
            end
        end
    end

    function Value.ValueFact:code_value_index_into(index)
    end

    function Value.ValueExprFact:code_value_index_into(index)
        index.expr_by_value[self.value.text] = self.expr
        index.proof_by_value[self.value.text] = self.proof
    end

    function Value.ValueNoWrapFact:code_value_index_into(index)
        index.no_wrap_by_value[self.value.text] = self.sem
    end

    function Value.ValueFloatModeFact:code_value_index_into(index)
        index.float_mode_by_value[self.value.text] = self.mode
    end

    function Value.ValueFactProjection:expr_for_value(id)
        if id == nil then return nil end
        return self.expr_by_value[id.text] or Value.ValueExprValue(id)
    end

    function Value.ValueFactProjection:expr_for_value_or_nil(id)
        if id == nil then return nil end
        return self.expr_by_value[id.text]
    end

    function Value.ValueFactProjection:proof_for_value(id)
        if id == nil then return nil end
        return self.proof_by_value[id.text]
    end

    function Value.ValueFactProjection:int_semantics_for_value(id)
        if id == nil then return nil end
        return self.no_wrap_by_value[id.text]
    end

    function Value.ValueFactProjection:float_mode_for_value(id)
        if id == nil then return nil end
        return self.float_mode_by_value[id.text]
    end

    function Value.ValueFactProjection:code_value_semantics_projection()
        return Code.CodeValueSemanticsProjection(self.no_wrap_by_value, self.float_mode_by_value)
    end

    local function expr_index(value_fact_set)
        local index = Value.ValueFactProjection({}, {}, {}, {})
        for _, fact in ipairs(value_fact_set and value_fact_set.values or {}) do
            fact:code_value_index_into(index)
        end
        return index
    end

    local lowerable_expr
    lowerable_expr = function(expr, seen)
        if expr == nil then return false, "missing ValueExpr" end
        seen = seen or {}
        if seen[expr] then return true end
        seen[expr] = true
        return expr:code_value_lowerable(seen, lowerable_expr)
    end

    function Value.ValueExpr:code_value_lowerable(seen, lower)
        return false, "unsupported ValueExpr for executable lowering"
    end

    function Value.ValueExprConst:code_value_lowerable()
        return true
    end

    function Value.ValueExprValue:code_value_lowerable()
        return true
    end

    function Value.ValueExprAffine:code_value_lowerable()
        return true
    end

    function Value.ValueExprUnary:code_value_lowerable(seen, lower)
        return lower(self.value, seen)
    end

    function Value.ValueExprCast:code_value_lowerable(seen, lower)
        return lower(self.value, seen)
    end

    local function lower_binary_expr(expr, seen, lower)
        local ok, reason = lower(expr.a, seen)
        if not ok then return false, reason end
        return lower(expr.b, seen)
    end

    function Value.ValueExprAdd:code_value_lowerable(seen, lower)
        return lower_binary_expr(self, seen, lower)
    end

    function Value.ValueExprSub:code_value_lowerable(seen, lower)
        return lower_binary_expr(self, seen, lower)
    end

    function Value.ValueExprMul:code_value_lowerable(seen, lower)
        return lower_binary_expr(self, seen, lower)
    end

    function Value.ValueExprDiv:code_value_lowerable(seen, lower)
        if self.sem == nil then return false, "div/rem expression lacks exact CodeIntSemantics" end
        return lower_binary_expr(self, seen, lower)
    end

    function Value.ValueExprRem:code_value_lowerable(seen, lower)
        if self.sem == nil then return false, "div/rem expression lacks exact CodeIntSemantics" end
        return lower_binary_expr(self, seen, lower)
    end

    function Value.ValueExprBinary:code_value_lowerable(seen, lower)
        return lower_binary_expr(self, seen, lower)
    end

    function Value.ValueExprSelect:code_value_lowerable(seen, lower)
        local ok, reason = lower(self.cond, seen)
        if not ok then return false, reason end
        ok, reason = lower(self.t, seen)
        if not ok then return false, reason end
        return lower(self.f, seen)
    end

    function Value.ValueExprCmp:code_value_lowerable(seen, lower)
        return lower_binary_expr(self, seen, lower)
    end

    local function facts(module, graph, flow)
        graph = graph or CodeGraph.graph(module)
        flow = flow or CodeFlowFacts.facts(module, graph)
        local values, exprs_by_func = {}, {}
        for _, func in ipairs(module.funcs or {}) do func:code_value_extract_exprs(values, exprs_by_func) end
        add_flow_ranges(flow, values)
        local reductions, closed_forms = detect_reductions(module, graph, flow, exprs_by_func)
        return Value.ValueFactSet(module.id, values, reductions, closed_forms)
    end

    api.facts = facts
    api.module = facts
    api.expr_index = expr_index
    api.lowerable_expr = lowerable_expr

    T._lalin_api_cache.code_value_facts = api
    return api
end

return bind_context
