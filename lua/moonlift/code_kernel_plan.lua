local pvm = require("moonlift.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_kernel_plan ~= nil then return T._moonlift_api_cache.code_kernel_plan end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Graph = T.MoonGraph
    local Flow = T.MoonFlow
    local Value = T.MoonValue
    local Mem = T.MoonMem
    local Effect = T.MoonEffect
    local Kernel = T.MoonKernel
    local Stencil = T.MoonStencil
    local CodeGraph = require("moonlift.code_graph")(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts")(T)
    local CodeValueFacts = require("moonlift.code_value_facts")(T)
    local CodeMemFacts = require("moonlift.code_mem_facts")(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts")(T)
    local CodeKernelPlanRules = require("moonlift.code_kernel_plan_rules")(T)

    local api = {}

    local function graph_loop_func(graph)
        local out = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do out[loop.id.text] = fg.func end
        end
        return out
    end

    local function graph_loop_index(graph)
        local out = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do out[loop.id.text] = loop end
        end
        return out
    end

    local function graph_func_index(graph)
        local out = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do out[fg.func.text] = fg end
        return out
    end

    local function flow_loop_index(flow)
        local out = {}
        for _, loop in ipairs(flow and flow.loops or {}) do out[loop.loop.text] = loop end
        return out
    end

    local function flow_edge_index(flow)
        local out = {}
        for _, fact in ipairs(flow and flow.edges or {}) do out[fact.edge.from.block.text .. "\0" .. fact.edge.to.block.text] = fact end
        return out
    end

    local function semantic_trip_counts(module, graph, flow)
        local sem = CodeFlowFacts.semantic_facts(module, graph, flow)
        local out = {}
        for _, fact in ipairs(sem.facts or {}) do
            if pvm.classof(fact) == Flow.FlowLoopNormalizedCounted then out[fact.loop.text] = fact.trip_count end
        end
        return out
    end

    local function access_indexes(mem)
        local access_by_id, object_by_access, backend_by_access = {}, {}, {}
        for _, access in ipairs(mem and mem.accesses or {}) do access_by_id[access.id.text] = access end
        for _, interval in ipairs(mem and mem.intervals or {}) do object_by_access[interval.access.text] = interval.object end
        for _, info in ipairs(mem and mem.backend_info or {}) do backend_by_access[info.access.text] = info end
        return access_by_id, object_by_access, backend_by_access
    end

    local function is_write_access(kind)
        return kind == Mem.MemStore or kind == Mem.MemAtomicStore or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas
    end

    local function block_set(blocks)
        local set = {}
        for _, b in ipairs(blocks or {}) do set[b.block.text] = true end
        return set
    end

    local function add_blocks_to_set(set, blocks)
        for _, b in ipairs(blocks or {}) do set[b.block.text] = true end
        return set
    end

    local function block_index(func)
        local out = {}
        for _, block in ipairs(func and func.blocks or {}) do out[block.id.text] = block end
        return out
    end

    local function streams_for_accesses(func_id, loop_id, loop_blocks, mem, rejects, proofs)
        local _, object_by_access, backend_by_access = access_indexes(mem)
        local stream_by_access = {}
        local grouped = {}
        local loop_accesses = {}
        for _, access in ipairs(mem and mem.accesses or {}) do
            if access.func == func_id and loop_blocks[access.block.block.text] then
                local object = object_by_access[access.id.text]
                local backend = backend_by_access[access.id.text]
                if backend == nil then
                    rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "missing MemBackendAccessInfo for loop-local access")
                elseif pvm.classof(backend.trap) ~= Mem.MemNonTrapping then
                    rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "loop-local access is not proven non-trapping")
                elseif pvm.classof(backend.bounds) == Mem.MemBoundsUnknown then
                    rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "loop-local access bounds are unknown")
                elseif object == nil then
                    rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "loop-local access has no proven object interval")
                else
                    local key = object.text .. "\0" .. tostring(access.base) .. "\0" .. tostring(access.pattern)
                    local group = grouped[key]
                    if group == nil then
                        group = { object = object, base = access.base, elem_ty = access.access.ty, pattern = access.pattern, accesses = {}, backend = {} }
                        grouped[key] = group
                    end
                    group.accesses[#group.accesses + 1] = access.id
                    group.backend[#group.backend + 1] = backend
                    for _, proof in ipairs(backend.proofs or {}) do proofs[#proofs + 1] = Kernel.KernelProofMemory(proof, "backend access info proves kernel memory safety") end
                end
                loop_accesses[#loop_accesses + 1] = access
            end
        end
        local dep_proved = {}
        local dep_unknown = {}
        for _, dep in ipairs(mem and mem.dependences or {}) do
            local dcls = pvm.classof(dep)
            if dcls == Mem.MemNoLoopCarriedDependence and dep.loop == loop_id then
                dep_proved[dep.before.text .. "\0" .. dep.after.text] = true
                dep_proved[dep.after.text .. "\0" .. dep.before.text] = true
            elseif dcls == Mem.MemNoDependence then
                dep_proved[dep.before.text .. "\0" .. dep.after.text] = true
                dep_proved[dep.after.text .. "\0" .. dep.before.text] = true
            elseif dcls == Mem.MemDependenceUnknown or dcls == Mem.MemLoopCarriedDependence then
                dep_unknown[dep.before.text .. "\0" .. dep.after.text] = true
                dep_unknown[dep.after.text .. "\0" .. dep.before.text] = true
            end
        end
        local dependence_rejects = {}
        for i = 1, #loop_accesses do
            for j = i + 1, #loop_accesses do
                local a, b = loop_accesses[i], loop_accesses[j]
                if is_write_access(a.kind) or is_write_access(b.kind) then
                    local key = a.id.text .. "\0" .. b.id.text
                    if dep_unknown[key] or not dep_proved[key] then
                        dependence_rejects[#dependence_rejects + 1] = {
                            before = a.id,
                            after = b.id,
                            reason = "loop write pair lacks pairwise no-dependence proof: " .. a.id.text .. " / " .. b.id.text,
                        }
                    end
                end
            end
        end
        local streams = {}
        local keys = {}
        for key in pairs(grouped) do keys[#keys + 1] = key end
        table.sort(keys)
        for i, key in ipairs(keys) do
            local g = grouped[key]
            local stream = Kernel.KernelStream(Kernel.KernelStreamId("stream:" .. sanitize(func_id.text) .. ":" .. sanitize(loop_id.text) .. ":" .. tostring(i)), g.object, g.accesses, g.base, g.elem_ty, g.pattern, g.backend)
            streams[#streams + 1] = stream
            for _, aid in ipairs(g.accesses or {}) do stream_by_access[aid.text] = stream end
        end
        return streams, stream_by_access, dependence_rejects
    end

    local function reductions_for_domain(value, domain)
        local reductions, closed_forms = {}, {}
        for _, r in ipairs(value and value.reductions or {}) do
            if pvm.classof(r.domain) == Flow.FlowDomainLoop and pvm.classof(domain) == Flow.FlowDomainLoop and r.domain.loop == domain.loop then reductions[#reductions + 1] = r end
        end
        for _, cf in ipairs(value and value.closed_forms or {}) do
            if pvm.classof(cf.reduction.domain) == Flow.FlowDomainLoop and pvm.classof(domain) == Flow.FlowDomainLoop and cf.reduction.domain.loop == domain.loop then closed_forms[#closed_forms + 1] = cf end
        end
        return reductions, closed_forms
    end

    local function inst_block_index(func)
        local out = {}
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do out[inst.id.text] = block.id end
        end
        return out
    end

    local function effect_is_reject(eff)
        local cls = pvm.classof(eff)
        return cls == Effect.EffectUnknown or cls == Effect.EffectVolatile or cls == Effect.EffectAtomic or cls == Effect.EffectMayTrap
    end

    local function loop_effects(func, loop_blocks, effect, rejects, proofs)
        local out = {}
        local inst_block = inst_block_index(func)
        for _, inst_eff in ipairs(effect and effect.insts or {}) do
            local block_id = inst_block[inst_eff.inst.text]
            if block_id ~= nil and loop_blocks[block_id.text] then
                for _, eff in ipairs(inst_eff.effects or {}) do
                    if effect_is_reject(eff) then
                        rejects[#rejects + 1] = Kernel.KernelRejectEffect(eff, "loop-local effect is unsupported by semantic kernel planning")
                    else
                        proofs[#proofs + 1] = Kernel.KernelProofEffect(eff, "loop-local effect is explicitly represented")
                    end
                end
            end
        end
        -- Calls are kept loop-local by InstEffect. Unknown call effects reject above;
        -- there is no module-wide call attachment in Kernel planning.
        for _, term_eff in ipairs(effect and effect.terms or {}) do
            if loop_blocks[term_eff.block.text] then
                for _, eff in ipairs(term_eff.effects or {}) do
                    if effect_is_reject(eff) then
                        rejects[#rejects + 1] = Kernel.KernelRejectEffect(eff, "loop-local terminator/contract effect is unsupported by semantic kernel planning")
                    else
                        proofs[#proofs + 1] = Kernel.KernelProofEffect(eff, "loop-local term effect is explicitly represented")
                    end
                end
            end
        end
        return out
    end

    local function access_id_text(func, block, inst)
        return "access:" .. sanitize(func.name) .. ":" .. sanitize(block.id.text) .. ":" .. sanitize(inst.id.text)
    end

    local function index_expr(mem_index)
        local cls = pvm.classof(mem_index)
        if mem_index == Mem.MemIndexNone then return Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt("0"))) end
        if cls == Mem.MemIndexValue then return Value.ValueExprValue(mem_index.value) end
        if cls == Mem.MemIndexInduction then return Value.ValueExprValue(mem_index.induction.value) end
        return nil
    end

    local function kernel_value_expr(value_index, bindings_by_value, id)
        if id == nil then return nil end
        if bindings_by_value[id.text] ~= nil then return Kernel.KernelExprKernelValue(bindings_by_value[id.text]) end
        local expr = value_index.expr_by_value[id.text] or Value.ValueExprValue(id)
        return Kernel.KernelExprAlgebra(expr)
    end

    local function inst_result_ty(k)
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then return k.const.ty end
        if cls == Code.CodeInstAlias then return k.ty end
        if cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect then return k.ty end
        if cls == Code.CodeInstCompare then return Code.CodeTyBool8 end
        if cls == Code.CodeInstCast then return k.to end
        return k.ty
    end

    local function build_kernel_body(func, loop_blocks, value, mem, stream_by_access, reduction_backedges, rejects)
        local value_index = CodeValueFacts.expr_index(value)
        local access_by_id = {}
        for _, access in ipairs(mem and mem.accesses or {}) do access_by_id[access.id.text] = access end
        local bindings, effects, bindings_by_value = {}, {}, {}
        local function add_binding(dst, ty, expr)
            if dst == nil or expr == nil then return end
            local kid = Kernel.KernelValueId("kval:" .. dst.text)
            bindings_by_value[dst.text] = kid
            bindings[#bindings + 1] = Kernel.KernelBinding(kid, ty, expr)
        end
        for _, block in ipairs(func.blocks or {}) do
            if loop_blocks[block.id.text] then
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    local cls = pvm.classof(k)
                    if cls == Code.CodeInstLoad then
                        local aid = Mem.MemAccessId(access_id_text(func, block, inst))
                        local stream = stream_by_access[aid.text]
                        local access = access_by_id[aid.text]
                        if stream == nil or access == nil then rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(aid, "load has no kernel stream")
                        else add_binding(k.dst, k.access.ty, Kernel.KernelExprLoad(stream, index_expr(access.index))) end
                    elseif cls == Code.CodeInstStore then
                        local aid = Mem.MemAccessId(access_id_text(func, block, inst))
                        local stream = stream_by_access[aid.text]
                        local access = access_by_id[aid.text]
                        local val = kernel_value_expr(value_index, bindings_by_value, k.value)
                        if stream == nil or access == nil then rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(aid, "store has no kernel stream")
                        elseif val == nil then rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedExpr(k.value, "store value cannot be represented as KernelExpr")
                        else effects[#effects + 1] = Kernel.KernelEffectStore(stream, index_expr(access.index), val) end
                    elseif cls == Code.CodeInstConst or cls == Code.CodeInstAlias or cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstCompare or cls == Code.CodeInstSelect or cls == Code.CodeInstCast then
                        local dst = k.dst
                        if dst ~= nil then
                            local expr = value_index.expr_by_value[dst.text]
                            if expr ~= nil then add_binding(dst, inst_result_ty(k), Kernel.KernelExprAlgebra(expr))
                            elseif reduction_backedges and reduction_backedges[dst.text] then
                                -- The loop-carried recurrence result is represented by
                                -- KernelEffectFold; it does not need a second executable
                                -- binding in the kernel body.
                            else rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedExpr(dst, "loop-local value instruction lacks ValueExprFact") end
                        end
                    elseif cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicStore or cls == Code.CodeInstAtomicRmw or cls == Code.CodeInstAtomicCas or cls == Code.CodeInstAtomicFence or cls == Code.CodeInstCall then
                        rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedExpr((k.dst or Code.CodeValueId(inst.id.text)), "unsupported side-effecting instruction in kernel body")
                    else
                        -- Address/projection/view instructions may feed memory facts; they are executable kernel ops only when they define a value used in a binding.
                    end
                end
            end
        end
        return bindings, effects
    end

    local function first_effect(effects, cls)
        local found = nil
        for _, effect in ipairs(effects or {}) do
            if pvm.classof(effect) == cls then
                if found ~= nil then return nil, "multiple effects of same skeleton class" end
                found = effect
            end
        end
        return found, nil
    end

    local function binding_index(bindings)
        local out = {}
        for _, binding in ipairs(bindings or {}) do out[binding.id.text] = binding end
        return out
    end

    local function resolve_kernel_expr(expr, bindings, seen)
        if expr == nil then return nil end
        if pvm.classof(expr) ~= Kernel.KernelExprKernelValue then return expr end
        seen = seen or {}
        if seen[expr.value.text] then return expr end
        seen[expr.value.text] = true
        local binding = bindings[expr.value.text]
        if binding == nil then return expr end
        return resolve_kernel_expr(binding.expr, bindings, seen)
    end

    local function value_expr_is_value(expr, id)
        return id ~= nil and pvm.classof(expr) == Value.ValueExprValue and expr.value == id
    end

    local function same_value_expr(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Value.ValueExprValue then return a.value == b.value end
        if ac == Value.ValueExprConst then return a.const == b.const end
        return false
    end

    local function const_int_expr(expr)
        if pvm.classof(expr) ~= Value.ValueExprConst then return nil end
        local c = expr.const
        if pvm.classof(c) ~= Code.CodeConstLiteral or pvm.classof(c.literal) ~= Core.LitInt then return nil end
        return tonumber(c.literal.raw)
    end

    local function is_minus_one_expr(expr)
        return const_int_expr(expr) == -1
    end

    local function reduction_update_matches(expr, reduction)
        if pvm.classof(expr) ~= Kernel.KernelExprAlgebra then return false end
        local v = expr.expr
        local cls = pvm.classof(v)
        local acc = reduction.accumulator
        local contrib = reduction.contribution
        if reduction.kind == Value.ReductionAdd and cls == Value.ValueExprAdd then
            return (value_expr_is_value(v.a, acc) and same_value_expr(v.b, contrib))
                or (value_expr_is_value(v.b, acc) and same_value_expr(v.a, contrib))
        end
        if reduction.kind == Value.ReductionMul and cls == Value.ValueExprMul then
            return (value_expr_is_value(v.a, acc) and same_value_expr(v.b, contrib))
                or (value_expr_is_value(v.b, acc) and same_value_expr(v.a, contrib))
        end
        return false
    end

    local function loop_primary_induction(loop)
        for _, induction in ipairs(loop and loop.inductions or {}) do
            if induction.kind == Flow.FlowPrimaryInduction then return induction.value end
        end
        return nil
    end

    local function index_is_primary(index, loop)
        return value_expr_is_value(index, loop_primary_induction(loop))
    end

    local function stream_has_access(stream, id)
        if stream == nil or id == nil then return false end
        for _, access in ipairs(stream.accesses or {}) do
            if access.text == id.text then return true end
        end
        return false
    end

    local function copy_dependence_semantics(dst, src, dependence_rejects)
        local needs_memmove = false
        for _, dep in ipairs(dependence_rejects or {}) do
            local before_dst, before_src = stream_has_access(dst, dep.before), stream_has_access(src, dep.before)
            local after_dst, after_src = stream_has_access(dst, dep.after), stream_has_access(src, dep.after)
            if (before_dst and after_src) or (before_src and after_dst) then
                needs_memmove = true
            else
                return nil, dep.reason
            end
        end
        if needs_memmove then return Stencil.StencilCopyMemMove end
        return Stencil.StencilCopyNoOverlap
    end

    local function term_args_to_dest(term, dest)
        local k = term and term.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeTermJump and k.dest == dest then return k.args or {} end
        if cls == Code.CodeTermBranch then
            if k.then_dest == dest then return k.then_args or {} end
            if k.else_dest == dest then return k.else_args or {} end
        elseif cls == Code.CodeTermSwitch then
            for _, case in ipairs(k.cases or {}) do if case.dest == dest then return case.args or {} end end
            if k.default_dest == dest then return k.default_args or {} end
        elseif cls == Code.CodeTermVariantSwitch then
            for _, case in ipairs(k.cases or {}) do if case.dest == dest then return case.args or {} end end
            if k.default_dest == dest then return k.default_args or {} end
        end
        return nil
    end

    local function edge_return_expr(blocks, edge, value_index)
        local from, to = blocks[edge.from.block.text], blocks[edge.to.block.text]
        local ret = to and to.term and to.term.kind or nil
        if from == nil or pvm.classof(ret) ~= Code.CodeTermReturn or #(ret.values or {}) ~= 1 then return nil end
        local value = ret.values[1]
        for i, param in ipairs(to.params or {}) do
            if value == param.value then
                local args = term_args_to_dest(from.term, to.id)
                value = args and args[i] or nil
                break
            end
        end
        if value == nil then return nil end
        return value_index.expr_by_value[value.text] or Value.ValueExprValue(value), value
    end

    local function edge_branch_polarity(blocks, edge)
        local from = blocks[edge.from.block.text]
        local term = from and from.term and from.term.kind or nil
        if pvm.classof(term) ~= Code.CodeTermBranch then return nil, nil end
        if term.then_dest == edge.to.block then return term.cond, true end
        if term.else_dest == edge.to.block then return term.cond, false end
        return nil, nil
    end

    local function flip_cmp(op)
        if op == Core.CmpLt then return Core.CmpGt end
        if op == Core.CmpLe then return Core.CmpGe end
        if op == Core.CmpGt then return Core.CmpLt end
        if op == Core.CmpGe then return Core.CmpLe end
        return op
    end

    local function invert_cmp(op)
        if op == Core.CmpEq then return Core.CmpNe end
        if op == Core.CmpNe then return Core.CmpEq end
        if op == Core.CmpLt then return Core.CmpGe end
        if op == Core.CmpLe then return Core.CmpGt end
        if op == Core.CmpGt then return Core.CmpLe end
        if op == Core.CmpGe then return Core.CmpLt end
        return nil
    end

    local function pred_from_cmp(op, cexpr)
        if op == Core.CmpEq then return Stencil.StencilPredEqConst(cexpr) end
        if op == Core.CmpNe then return Stencil.StencilPredNeConst(cexpr) end
        if op == Core.CmpLt then return Stencil.StencilPredLtConst(cexpr) end
        if op == Core.CmpLe then return Stencil.StencilPredLeConst(cexpr) end
        if op == Core.CmpGt then return Stencil.StencilPredGtConst(cexpr) end
        if op == Core.CmpGe then return Stencil.StencilPredGeConst(cexpr) end
        return nil
    end

    local function same_load_expr(a, b)
        if pvm.classof(a) ~= Kernel.KernelExprLoad or pvm.classof(b) ~= Kernel.KernelExprLoad then return false end
        return a.stream == b.stream and same_value_expr(a.index, b.index)
    end

    local function expr_as_kernel_value(expr, bindings)
        if pvm.classof(expr) ~= Value.ValueExprValue then return nil end
        return resolve_kernel_expr(Kernel.KernelExprKernelValue(Kernel.KernelValueId("kval:" .. expr.value.text)), bindings)
    end

    local function find_predicate_from_cond(cond, polarity, bindings, value_index)
        local expr = cond and value_index.expr_by_value[cond.text] or nil
        if pvm.classof(expr) ~= Value.ValueExprCmp then return nil end
        local op = polarity and expr.op or invert_cmp(expr.op)
        if op == nil then return nil end
        local a_kernel, b_kernel = expr_as_kernel_value(expr.a, bindings), expr_as_kernel_value(expr.b, bindings)
        local a_const = pvm.classof(expr.a) == Value.ValueExprConst and expr.a or nil
        local b_const = pvm.classof(expr.b) == Value.ValueExprConst and expr.b or nil
        if a_kernel ~= nil and b_const ~= nil and pvm.classof(a_kernel) == Kernel.KernelExprLoad then
            return a_kernel, pred_from_cmp(op, b_const)
        end
        if b_kernel ~= nil and a_const ~= nil and pvm.classof(b_kernel) == Kernel.KernelExprLoad then
            return b_kernel, pred_from_cmp(flip_cmp(op), a_const)
        end
        return nil
    end

    local function infer_scan_skeleton(loop, effects, reductions, bindings, proofs)
        if #reductions ~= 1 then return nil end
        local store = first_effect(effects, Kernel.KernelEffectStore)
        if store == nil or not index_is_primary(store.index, loop) then return nil end
        local reduction = reductions[1]
        if not reduction_update_matches(resolve_kernel_expr(store.value, bindings), reduction) then return nil end
        proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("store of loop-carried reduction update is a prefix scan")
        return {
            effects = {
                Kernel.KernelEffectScan(store.dst, store.index, reduction, Stencil.StencilScanInclusive),
                Kernel.KernelEffectFold(reduction),
            },
            result = Kernel.KernelResultReduction(reduction),
        }
    end

    local function infer_copy_skeleton(loop, effects, bindings, dependence_rejects, proofs)
        local store = first_effect(effects, Kernel.KernelEffectStore)
        if store == nil or not index_is_primary(store.index, loop) then return nil end
        local src = resolve_kernel_expr(store.value, bindings)
        if pvm.classof(src) ~= Kernel.KernelExprLoad then return nil end
        if not index_is_primary(src.index, loop) then return nil end
        if store.dst.elem_ty ~= src.stream.elem_ty then return nil end
        local semantics, dep_reason = copy_dependence_semantics(store.dst, src.stream, dependence_rejects)
        if semantics == nil then return nil, dep_reason end
        proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("primary-index load/store is an array copy skeleton")
        if semantics == Stencil.StencilCopyMemMove then
            proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("copy skeleton uses memmove semantics for unresolved source/destination overlap")
        end
        return {
            effects = {
                Kernel.KernelEffectCopy(store.dst, src, semantics),
            },
            result = Kernel.KernelResultVoid,
            handles_dependences = true,
        }
    end

    local function infer_find_skeleton(func, graph_loop, loop, body_bindings, value_index, proofs)
        if graph_loop == nil or #(graph_loop.exits or {}) ~= 2 then return nil end
        local primary = loop_primary_induction(loop)
        if primary == nil then return nil end
        local bindings = binding_index(body_bindings)
        local blocks = block_index(func)
        local hit_src, hit_pred, not_found = nil, nil, nil
        for _, edge in ipairs(graph_loop.exits or {}) do
            local ret_expr, ret_value = edge_return_expr(blocks, edge, value_index)
            if ret_expr ~= nil and (ret_value == primary or value_expr_is_value(ret_expr, primary)) then
                local cond, polarity = edge_branch_polarity(blocks, edge)
                local src, pred = find_predicate_from_cond(cond, polarity, bindings, value_index)
                if src == nil or pred == nil then return nil end
                hit_src, hit_pred = src, pred
            elseif ret_expr ~= nil and is_minus_one_expr(ret_expr) then
                not_found = ret_expr
            elseif ret_value ~= nil then
                return nil
            end
        end
        if hit_src == nil or hit_pred == nil or not_found == nil then return nil end
        if pvm.classof(hit_src) ~= Kernel.KernelExprLoad or not index_is_primary(hit_src.index, loop) then return nil end
        proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("early-exit primary-index search is an array find skeleton")
        return {
            effects = {},
            result = Kernel.KernelResultFind(hit_src, hit_pred, not_found),
        }
    end

    local function infer_loop_skeleton(func, graph_loop, loop, effects, reductions, body_bindings, dependence_rejects, value_index, proofs)
        local bindings = binding_index(body_bindings)
        local scan = infer_scan_skeleton(loop, effects, reductions, bindings, proofs)
        if scan ~= nil then return scan end
        if #reductions == 0 then
            local find = infer_find_skeleton(func, graph_loop, loop, body_bindings, value_index, proofs)
            if find ~= nil then return find end
            local copy = infer_copy_skeleton(loop, effects, bindings, dependence_rejects, proofs)
            if copy ~= nil then return copy end
        end
        return nil
    end

    local function same_counted_domain(a, b)
        return a ~= nil and b ~= nil and a.start == b.start and a.stop == b.stop and a.step == b.step and a.stop_exclusive == b.stop_exclusive
    end

    local function first_store_effect(effects)
        for _, effect in ipairs(effects or {}) do
            if pvm.classof(effect) == Kernel.KernelEffectStore then return effect end
        end
        return nil
    end

    local function infer_partition_skeleton(func, graph_func, flow_loops, value, mem, trip_counts)
        if graph_func == nil then return nil end
        local grouped, order = {}, {}
        for _, graph_loop in ipairs(graph_func.loops or {}) do
            local key = graph_loop.header.block.text
            if grouped[key] == nil then
                grouped[key] = {}
                order[#order + 1] = key
            end
            grouped[key][#grouped[key] + 1] = graph_loop
        end
        if #order ~= 2 then return nil end
        table.sort(order)
        local group_a, group_b = grouped[order[1]], grouped[order[2]]
        local loop_a = flow_loops[group_a[1].id.text]
        local loop_b = flow_loops[group_b[1].id.text]
        if loop_a == nil or loop_b == nil or not same_counted_domain(loop_a.counted, loop_b.counted) then return nil end
        if loop_primary_induction(loop_a) == nil or loop_primary_induction(loop_b) == nil then return nil end

        local subject = Kernel.KernelSubjectFunction(func.id)
        local domain = Flow.FlowDomainLoop(loop_a.loop)
        local proofs = { Kernel.KernelProofFlow(domain, "two counted loops recognized as stable partition domain") }
        local rejects = {}
        local loop_blocks = {}
        for _, graph_loop in ipairs(group_a) do
            local facts = flow_loops[graph_loop.id.text]
            if facts ~= nil then add_blocks_to_set(loop_blocks, facts.body_blocks or facts.body) end
        end
        for _, graph_loop in ipairs(group_b) do
            local facts = flow_loops[graph_loop.id.text]
            if facts ~= nil then add_blocks_to_set(loop_blocks, facts.body_blocks or facts.body) end
        end
        local streams, stream_by_access, dependence_rejects = streams_for_accesses(func.id, loop_a.loop, loop_blocks, mem, rejects, proofs)
        if #rejects > 0 then return nil end

        local body_bindings, body_effects = build_kernel_body(func, loop_blocks, value, mem, stream_by_access, {}, rejects)
        if #rejects > 0 then return nil end
        local store = first_store_effect(body_effects)
        if store == nil then return nil end
        local value_index = CodeValueFacts.expr_index(value)
        local bindings = binding_index(body_bindings)
        local src, pred = nil, nil
        for _, block in ipairs(func.blocks or {}) do
            if loop_blocks[block.id.text] then
                local term = block.term and block.term.kind or nil
                if pvm.classof(term) == Code.CodeTermBranch then
                    local candidate_src, candidate_pred = find_predicate_from_cond(term.cond, true, bindings, value_index)
                    if candidate_src ~= nil and candidate_pred ~= nil and pvm.classof(candidate_src) == Kernel.KernelExprLoad then
                        src, pred = candidate_src, candidate_pred
                        break
                    end
                end
            end
        end
        if src == nil or pred == nil or not index_is_primary(src.index, loop_a) then return nil end
        if store.dst.elem_ty ~= src.stream.elem_ty then return nil end
        for _, dep in ipairs(dependence_rejects or {}) do
            local before_dst, before_src = stream_has_access(store.dst, dep.before), stream_has_access(src.stream, dep.before)
            local after_dst, after_src = stream_has_access(store.dst, dep.after), stream_has_access(src.stream, dep.after)
            if not ((before_dst and after_src) or (before_src and after_dst) or (before_dst and after_dst)) then return nil end
        end
        proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("two-pass predicate-preserving copy is a stable partition skeleton")
        local body = Kernel.KernelBody(
            Kernel.KernelDomainFlow(domain, trip_counts[loop_a.loop.text] or Flow.FlowTripCountUnknown("no semantic trip-count fact"), loop_primary_induction(loop_a)),
            streams,
            body_bindings,
            { Kernel.KernelEffectPartition(store.dst, src, pred, Stencil.StencilPartitionStable) },
            Kernel.KernelResultValue(Kernel.KernelExprAlgebra(Value.ValueExprValue(loop_primary_induction(loop_a)))),
            Kernel.KernelEquivalenceProof(proofs)
        )
        return Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(func.id.text) .. ":partition"), subject, body)
    end

    local function function_plans(module, graph, flow, value, mem, effect)
        local plans = {}
        local funcs = {}
        for _, func in ipairs(module.funcs or {}) do funcs[func.id.text] = func end
        local loop_func = graph_loop_func(graph)
        local graph_loops = graph_loop_index(graph)
        local graph_funcs = graph_func_index(graph)
        local flow_loops = flow_loop_index(flow)
        local edge_facts = flow_edge_index(flow)
        local trip_counts = semantic_trip_counts(module, graph, flow)

        for _, loop in ipairs(flow and flow.loops or {}) do
            local subject = Kernel.KernelSubjectLoop(loop.loop)
            local func_id = loop_func[loop.loop.text]
            local function select(candidate)
                local selection, err = CodeKernelPlanRules.select(candidate)
                assert(selection ~= nil, tostring(err))
                return selection
            end
            if loop.counted == nil then
                local selection = select({
                    counted = false,
                    has_func_id = func_id ~= nil,
                    has_func = false,
                    has_rejects = false,
                    has_closed_form = false,
                    has_reduction = false,
                    has_skeleton_result = false,
                    closed_form_trip_unknown = false,
                    not_counted_rejects = { Kernel.KernelRejectNoFacts(subject, "loop is not a counted Flow domain") },
                    no_owner_rejects = { Kernel.KernelRejectNoFacts(subject, "graph loop has no function owner") },
                    rejects = {},
                })
                plans[#plans + 1] = Kernel.KernelNoPlan(subject, selection.rejects)
            elseif func_id == nil then
                local selection = select({
                    counted = true,
                    has_func_id = false,
                    has_func = false,
                    has_rejects = false,
                    has_closed_form = false,
                    has_reduction = false,
                    has_skeleton_result = false,
                    closed_form_trip_unknown = false,
                    not_counted_rejects = { Kernel.KernelRejectNoFacts(subject, "loop is not a counted Flow domain") },
                    no_owner_rejects = { Kernel.KernelRejectNoFacts(subject, "graph loop has no function owner") },
                    rejects = {},
                })
                plans[#plans + 1] = Kernel.KernelNoPlan(subject, selection.rejects)
            else
                local func = funcs[func_id.text]
                local domain = Flow.FlowDomainLoop(loop.loop)
                local rejects = {}
                local proofs = { Kernel.KernelProofFlow(domain, "Flow counted-domain recognition") }
                local loop_blocks = block_set(loop.body_blocks or loop.body)
                if func == nil then rejects[#rejects + 1] = Kernel.KernelRejectNoFacts(subject, "graph loop owner function is missing from CodeModule") end
                local streams, stream_by_access, dependence_rejects = streams_for_accesses(func_id, loop.loop, loop_blocks, mem, rejects, proofs)
                local effects = func and loop_effects(func, loop_blocks, effect, rejects, proofs) or {}
                local reductions, closed_forms = reductions_for_domain(value, domain)
                local reduction_backedges = {}
                local graph_loop = graph_loops[loop.loop.text]
                if graph_loop ~= nil then
                    for _, latch in ipairs(graph_loop.latches or {}) do
                        local fact = edge_facts[latch.from.block.text .. "\0" .. latch.to.block.text]
                        for _, arg in ipairs(fact and fact.args or {}) do
                            for _, reduction in ipairs(reductions or {}) do
                                if arg.dst_param == reduction.accumulator then reduction_backedges[arg.src.text] = true end
                            end
                        end
                    end
                end
                local body_bindings, body_effects = {}, {}
                local value_index = CodeValueFacts.expr_index(value)
                if func ~= nil then
                    body_bindings, body_effects = build_kernel_body(func, loop_blocks, value, mem, stream_by_access, reduction_backedges, rejects)
                end
                local skeleton = nil
                if #rejects == 0 then skeleton = infer_loop_skeleton(func, graph_loop, loop, body_effects, reductions, body_bindings, dependence_rejects, value_index, proofs) end
                if skeleton ~= nil then
                    for _, e in ipairs(skeleton.effects or {}) do effects[#effects + 1] = e end
                    if not skeleton.handles_dependences then
                        for _, dep in ipairs(dependence_rejects or {}) do
                            rejects[#rejects + 1] = Kernel.KernelRejectNoFacts(subject, dep.reason)
                        end
                    end
                else
                    for _, e in ipairs(body_effects or {}) do effects[#effects + 1] = e end
                    for _, reduction in ipairs(reductions) do effects[#effects + 1] = Kernel.KernelEffectFold(reduction) end
                    for _, dep in ipairs(dependence_rejects or {}) do
                        rejects[#rejects + 1] = Kernel.KernelRejectNoFacts(subject, dep.reason)
                    end
                end
                for _, reduction in ipairs(reductions) do
                    proofs[#proofs + 1] = Kernel.KernelProofValue(reduction.proof, "reduction fact justifies kernel fold")
                end
                local trip = trip_counts[loop.loop.text] or Flow.FlowTripCountUnknown("no semantic trip-count fact")
                local selection = select({
                    counted = true,
                    has_func_id = true,
                    has_func = func ~= nil,
                    has_rejects = #rejects > 0,
                    has_closed_form = #closed_forms > 0,
                    has_reduction = #reductions > 0,
                    has_skeleton_result = skeleton ~= nil and skeleton.result ~= nil,
                    closed_form = closed_forms[1],
                    reduction = reductions[1],
                    skeleton_result = skeleton and skeleton.result or nil,
                    closed_form_trip_unknown = #closed_forms > 0 and pvm.classof(trip) == Flow.FlowTripCountUnknown,
                    not_counted_rejects = { Kernel.KernelRejectNoFacts(subject, "loop is not a counted Flow domain") },
                    no_owner_rejects = { Kernel.KernelRejectNoFacts(subject, "graph loop has no function owner") },
                    rejects = rejects,
                })
                if selection.kind == "no_plan" then
                    plans[#plans + 1] = Kernel.KernelNoPlan(subject, selection.rejects)
                else
                    local result
                    if selection.result_kind == "closed_form" then
                        local closed_form = assert(selection.closed_form, "closed-form kernel selection has no closed-form fact")
                        result = Kernel.KernelResultClosedForm(closed_form)
                        proofs[#proofs + 1] = Kernel.KernelProofValue(closed_form.proof, "closed form fact justifies kernel result")
                        if selection.add_trip_unknown_proof then
                            -- The current closed-form expression encodes start/stop/step directly, so
                            -- keep the plan but make the proof dependence explicit rather than claiming
                            -- an exact FlowTripCountExact fact that Flow does not provide yet.
                            proofs[#proofs + 1] = Kernel.KernelProofFlow(domain, "closed-form expression uses counted start/stop/step directly; FlowTripCountExact is unavailable")
                        end
                    elseif selection.result_kind == "reduction" then
                        result = Kernel.KernelResultReduction(assert(selection.reduction, "reduction kernel selection has no reduction fact"))
                    elseif selection.result_kind == "skeleton" then
                        result = assert(selection.skeleton_result, "skeleton kernel selection has no result")
                    else
                        result = Kernel.KernelResultOriginalControl("semantic loop kernel preserves original control by default")
                    end
                    local counter = loop.inductions and loop.inductions[1] and loop.inductions[1].value or nil
                    local body = Kernel.KernelBody(
                        Kernel.KernelDomainFlow(domain, trip, counter),
                        streams,
                        body_bindings,
                        effects,
                        result,
                        Kernel.KernelEquivalenceProof(proofs)
                    )
                    plans[#plans + 1] = Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(loop.loop.text)), subject, body)
                end
            end
        end

        for _, func in ipairs(module.funcs or {}) do
            local partition = infer_partition_skeleton(func, graph_funcs[func.id.text], flow_loops, value, mem, trip_counts)
            if partition ~= nil then
                plans[#plans + 1] = partition
            else
                plans[#plans + 1] = Kernel.KernelNoPlan(Kernel.KernelSubjectFunction(func.id), { Kernel.KernelRejectUnsupportedSubject(Kernel.KernelSubjectFunction(func.id), "function-level replacement is not a semantic kernel plan") })
            end
        end
        return plans
    end

    local function plan(module, graph, flow, value, mem, effect)
        graph = graph or CodeGraph.graph(module)
        flow = flow or CodeFlowFacts.facts(module, graph)
        value = value or CodeValueFacts.facts(module, graph, flow)
        mem = mem or CodeMemFacts.semantic_facts(module, graph, flow, value, nil)
        effect = effect or CodeEffectFacts.facts(module, graph, mem, nil)
        return Kernel.KernelModulePlan(module.id, flow, value, mem, effect, function_plans(module, graph, flow, value, mem, effect))
    end

    api.plan = plan
    api.module = plan

    T._moonlift_api_cache.code_kernel_plan = api
    return api
end

return bind_context
