local pvm = require("moonlift.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_value_facts ~= nil then return T._moonlift_api_cache.code_value_facts end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Graph = T.MoonGraph
    local Flow = T.MoonFlow
    local Value = T.MoonValue
    local CodeGraph = require("moonlift.code_graph")(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts")(T)
    local ReductionAlgebra = require("moonlift.reduction_algebra")(T)

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

    local function value_defs(func)
        local defs = {}
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                local cls = pvm.classof(k)
                if k.dst ~= nil then defs[k.dst.text] = { cls = cls, inst = inst, kind = k, block = block } end
            end
        end
        return defs
    end

    local function expr_for(exprs, id)
        return (id and exprs[id.text]) or (id and Value.ValueExprValue(id)) or nil
    end

    local function add_expr_fact(out, exprs, id, expr, proof)
        if id == nil or expr == nil then return end
        exprs[id.text] = expr
        out[#out + 1] = Value.ValueExprFact(id, expr, proof or identity("syntactic Code value expression"))
    end

    local function binary_expr(k, exprs)
        local a, b = expr_for(exprs, k.lhs), expr_for(exprs, k.rhs)
        if k.op == Core.BinAdd then return Value.ValueExprAdd(a, b, k.ty, k.semantics) end
        if k.op == Core.BinSub then return Value.ValueExprSub(a, b, k.ty, k.semantics) end
        if k.op == Core.BinMul then return Value.ValueExprMul(a, b, k.ty, k.semantics) end
        if k.op == Core.BinDiv or k.op == Core.BinRem then return Value.ValueExprDiv(a, b, k.ty, k.semantics) end
        return nil
    end

    local function extract_func_values(func, out_values, exprs_by_func)
        local exprs = {}
        exprs_by_func[func.id.text] = exprs
        for _, param in ipairs(func.params or {}) do exprs[param.value.text] = Value.ValueExprValue(param.value) end
        for _, block in ipairs(func.blocks or {}) do
            for _, param in ipairs(block.params or {}) do exprs[param.value.text] = Value.ValueExprValue(param.value) end
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                local cls = pvm.classof(k)
                if cls == Code.CodeInstConst then
                    add_expr_fact(out_values, exprs, k.dst, Value.ValueExprConst(k.const), identity("Code constant"))
                elseif cls == Code.CodeInstAlias then
                    add_expr_fact(out_values, exprs, k.dst, expr_for(exprs, k.src), identity("Code alias"))
                elseif cls == Code.CodeInstUnary then
                    add_expr_fact(out_values, exprs, k.dst, Value.ValueExprUnary(k.op, expr_for(exprs, k.value), k.ty), identity("Code unary expression"))
                elseif cls == Code.CodeInstBinary then
                    local expr = binary_expr(k, exprs)
                    if expr ~= nil then add_expr_fact(out_values, exprs, k.dst, expr, identity("Code integer binary expression")) end
                    if k.semantics ~= nil then out_values[#out_values + 1] = Value.ValueNoWrapFact(k.dst, k.semantics, Value.AlgebraProofNoWrap(k.dst, "integer operation carries CodeIntSemantics")) end
                elseif cls == Code.CodeInstFloatBinary then
                    if k.op == Core.BinAdd then add_expr_fact(out_values, exprs, k.dst, Value.ValueExprAdd(expr_for(exprs, k.lhs), expr_for(exprs, k.rhs), k.ty, nil), identity("Code float add expression")) end
                    if k.op == Core.BinSub then add_expr_fact(out_values, exprs, k.dst, Value.ValueExprSub(expr_for(exprs, k.lhs), expr_for(exprs, k.rhs), k.ty, nil), identity("Code float sub expression")) end
                    if k.op == Core.BinMul then add_expr_fact(out_values, exprs, k.dst, Value.ValueExprMul(expr_for(exprs, k.lhs), expr_for(exprs, k.rhs), k.ty, nil), identity("Code float mul expression")) end
                    if k.op == Core.BinDiv then add_expr_fact(out_values, exprs, k.dst, Value.ValueExprDiv(expr_for(exprs, k.lhs), expr_for(exprs, k.rhs), k.ty, nil), identity("Code float div expression")) end
                    out_values[#out_values + 1] = Value.ValueFloatModeFact(k.dst, k.mode, identity("Code float mode"))
                elseif cls == Code.CodeInstCompare then
                    add_expr_fact(out_values, exprs, k.dst, Value.ValueExprCmp(k.op, k.operand_ty, expr_for(exprs, k.lhs), expr_for(exprs, k.rhs)), identity("Code compare expression"))
                elseif cls == Code.CodeInstSelect then
                    add_expr_fact(out_values, exprs, k.dst, Value.ValueExprSelect(expr_for(exprs, k.cond), expr_for(exprs, k.then_value), expr_for(exprs, k.else_value)), identity("Code select expression"))
                elseif cls == Code.CodeInstCast then
                    add_expr_fact(out_values, exprs, k.dst, Value.ValueExprCast(k.op, k.from, k.to, expr_for(exprs, k.value)), identity("Code cast expression"))
                end
            end
        end
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

    local function reduction_kind_for(op, is_float)
        return ReductionAlgebra.binary_reduction_kind(op, is_float)
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
        while def ~= nil and def.cls == Code.CodeInstAlias and def.kind.src ~= nil and not seen[def.kind.src.text] do
            seen[def.kind.src.text] = true
            def = defs[def.kind.src.text]
        end
        return def
    end

    local function select_minmax_reduction(param, def, defs, aliases)
        if def == nil or def.cls ~= Code.CodeInstSelect then return nil end
        local k = def.kind
        local cdef = k.cond and defs[k.cond.text] or nil
        if cdef == nil or cdef.cls ~= Code.CodeInstCompare then return nil end
        local cmp = cdef.kind
        local lhs, rhs = cmp.lhs, cmp.rhs
        if not ((same_value(k.then_value, lhs) and same_value(k.else_value, rhs)) or (same_value(k.then_value, rhs) and same_value(k.else_value, lhs))) then return nil end
        if not (same_canonical_value(lhs, param.value, aliases) or same_canonical_value(rhs, param.value, aliases)) then return nil end
        local contribution = same_canonical_value(lhs, param.value, aliases) and rhs or lhs
        local true_value_is_lhs = same_value(k.then_value, lhs)
        local rkind = ReductionAlgebra.select_minmax_kind(cmp.op, true_value_is_lhs)
        if rkind == nil then return nil end
        return rkind, contribution, k.ty or cmp.operand_ty, nil, nil
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
                        if src ~= nil and aliases[arg.dst_param.text] ~= src then
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
                    if induction.kind == Flow.FlowPrimaryInduction then primary[induction.value.text] = true end
                end

                for _, param in ipairs(header and header.params or {}) do
                    if not primary[param.value.text] then
                        local back = backedge_arg(latch_fact, param)
                        local init = incoming_arg(flow.edges, graph_loop.header.block, param, latch.from.block)
                        local def = resolve_def(defs, back)
                        local rkind, contribution, rty, int_sem, float_mode, recurrence_cls = nil, nil, nil, nil, nil, nil
                        if def ~= nil and (def.cls == Code.CodeInstBinary or def.cls == Code.CodeInstFloatBinary) then
                            recurrence_cls = def.cls
                            local k = def.kind
                            if same_canonical_value(k.lhs, param.value, aliases) then contribution = k.rhs elseif same_canonical_value(k.rhs, param.value, aliases) then contribution = k.lhs end
                            local is_float = def.cls == Code.CodeInstFloatBinary
                            rkind = contribution and reduction_kind_for(k.op, is_float) or nil
                            rty = k.ty
                            int_sem = (def.cls == Code.CodeInstBinary) and k.semantics or nil
                            float_mode = (def.cls == Code.CodeInstFloatBinary) and k.mode or nil
                        elseif def ~= nil and def.cls == Code.CodeInstSelect then
                            recurrence_cls = def.cls
                            rkind, contribution, rty, int_sem, float_mode = select_minmax_reduction(param, def, defs, aliases)
                        end
                        if rkind ~= nil and contribution ~= nil then
                            local canonical_contribution = canonical_value(contribution, aliases)
                            local domain = Flow.FlowDomainLoop(loop_fact.loop)
                            local proof = Value.AlgebraProofFlow(domain, "loop-carried accumulator recurrence")
                            local reduction = Value.ReductionFact(
                                Value.AlgebraFactId("reduction:" .. sanitize(func.name) .. ":" .. sanitize(loop_fact.loop.text) .. ":" .. sanitize(param.value.text)),
                                domain,
                                param.value,
                                rkind,
                                expr_for(exprs, init),
                                expr_for(exprs, canonical_contribution),
                                rty,
                                int_sem,
                                float_mode,
                                proof
                            )
                            reductions[#reductions + 1] = reduction
                            if rkind == Value.ReductionAdd and recurrence_cls == Code.CodeInstBinary and primary[canonical_contribution.text] and loop_fact.counted ~= nil and loop_fact.counted.stop_exclusive then
                                local closed_expr = arithmetic_series_expr(
                                    expr_for(exprs, init),
                                    expr_for(exprs, loop_fact.counted.start),
                                    expr_for(exprs, loop_fact.counted.stop),
                                    expr_for(exprs, loop_fact.counted.step),
                                    rty,
                                    int_sem
                                )
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

    local function add_flow_ranges(flow, out_values)
        for _, fact in ipairs(flow and flow.facts or {}) do
            if pvm.classof(fact) == Flow.FlowLoopInductionRange then
                local r = fact.range
                out_values[#out_values + 1] = Value.ValueRangeFact(Value.ValueRangeInt(r.value, Value.ValueExprValue(r.min.value or r.value), Value.ValueExprValue(r.max.value or r.value), not r.max_exclusive, Value.AlgebraProofFlow(Flow.FlowDomainLoop(r.loop), r.reason)))
            end
        end
        for _, loop in ipairs(flow and flow.loops or {}) do
            for _, induction in ipairs(loop.inductions or {}) do
                out_values[#out_values + 1] = Value.ValueExprFact(
                    induction.value,
                    Value.ValueExprAffine(Value.AffineExpr("0", { Value.AffineTerm(induction.value, "1") }, induction.ty, nil)),
                    Value.AlgebraProofFlow(Flow.FlowDomainLoop(loop.loop), "induction variable affine identity")
                )
            end
        end
    end

    local function expr_index(value_fact_set)
        local index = { expr_by_value = {}, proof_by_value = {}, no_wrap_by_value = {}, float_mode_by_value = {} }
        for _, fact in ipairs(value_fact_set and value_fact_set.values or {}) do
            local cls = pvm.classof(fact)
            if cls == Value.ValueExprFact then
                index.expr_by_value[fact.value.text] = fact.expr
                index.proof_by_value[fact.value.text] = fact.proof
            elseif cls == Value.ValueNoWrapFact then
                index.no_wrap_by_value[fact.value.text] = fact.sem
            elseif cls == Value.ValueFloatModeFact then
                index.float_mode_by_value[fact.value.text] = fact.mode
            end
        end
        return index
    end

    local lowerable_expr
    lowerable_expr = function(expr, seen)
        if expr == nil then return false, "missing ValueExpr" end
        seen = seen or {}
        if seen[expr] then return true end
        seen[expr] = true
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprConst or cls == Value.ValueExprValue or cls == Value.ValueExprAffine then return true end
        if cls == Value.ValueExprUnary then return lowerable_expr(expr.value, seen) end
        if cls == Value.ValueExprCast then return lowerable_expr(expr.value, seen) end
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul then
            local ok, reason = lowerable_expr(expr.a, seen); if not ok then return false, reason end
            return lowerable_expr(expr.b, seen)
        end
        if cls == Value.ValueExprDiv then
            if expr.sem == nil then return false, "division expression lacks exact CodeIntSemantics" end
            local ok, reason = lowerable_expr(expr.a, seen); if not ok then return false, reason end
            return lowerable_expr(expr.b, seen)
        end
        if cls == Value.ValueExprSelect then
            local ok, reason = lowerable_expr(expr.cond, seen); if not ok then return false, reason end
            ok, reason = lowerable_expr(expr.t, seen); if not ok then return false, reason end
            return lowerable_expr(expr.f, seen)
        end
        if cls == Value.ValueExprCmp then
            local ok, reason = lowerable_expr(expr.a, seen); if not ok then return false, reason end
            return lowerable_expr(expr.b, seen)
        end
        return false, "unsupported ValueExpr for executable lowering"
    end

    local function facts(module, graph, flow)
        graph = graph or CodeGraph.graph(module)
        flow = flow or CodeFlowFacts.facts(module, graph)
        local values, exprs_by_func = {}, {}
        for _, func in ipairs(module.funcs or {}) do extract_func_values(func, values, exprs_by_func) end
        add_flow_ranges(flow, values)
        local reductions, closed_forms = detect_reductions(module, graph, flow, exprs_by_func)
        return Value.ValueFactSet(module.id, values, reductions, closed_forms)
    end

    api.facts = facts
    api.module = facts
    api.expr_index = expr_index
    api.lowerable_expr = lowerable_expr

    T._moonlift_api_cache.code_value_facts = api
    return api
end

return bind_context
