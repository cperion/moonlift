local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_kernel_plan ~= nil then return T._lalin_api_cache.code_kernel_plan end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Graph = T.LalinGraph
    local Flow = T.LalinFlow
    local Value = T.LalinValue
    local Mem = T.LalinMem
    local Effect = T.LalinEffect
    local Kernel = T.LalinKernel
    local Stencil = T.LalinStencil
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local ReductionAlgebra = require("lalin.reduction_algebra")(T)

    local api = {}

    function Flow.FlowTripCount:kernel_plan_closed_form_trip_unknown_proof() return false end
    function Flow.FlowTripCountUnknown:kernel_plan_closed_form_trip_unknown_proof() return true end

    function Kernel.KernelLoopPlanInput:select_kernel_loop_plan()
        if not self.counted then
            return Kernel.KernelLoopNoPlan(self.not_counted_rejects)
        end
        if not self.has_func_id then
            return Kernel.KernelLoopNoPlan(self.no_owner_rejects)
        end
        if #(self.rejects or {}) > 0 then
            return Kernel.KernelLoopNoPlan(self.rejects)
        end
        if self.has_func and self.closed_form ~= nil then
            return Kernel.KernelLoopPlanClosedForm(self.closed_form, self.trip_count:kernel_plan_closed_form_trip_unknown_proof())
        end
        if self.has_func and self.reduction ~= nil then
            return Kernel.KernelLoopPlanReduction(self.reduction)
        end
        if self.has_func and self.skeleton_result ~= nil then
            return Kernel.KernelLoopPlanSkeleton(self.skeleton_result)
        end
        return Kernel.KernelLoopPlanOriginalControl
    end

    function Kernel.KernelLoopPlanSelection:kernel_plan_is_no_plan() return false end
    function Kernel.KernelLoopNoPlan:kernel_plan_is_no_plan() return true end
    function Kernel.KernelLoopPlanSelection:kernel_plan_is_closed_form() return false end
    function Kernel.KernelLoopPlanClosedForm:kernel_plan_is_closed_form() return true end
    function Kernel.KernelLoopPlanSelection:kernel_plan_is_reduction() return false end
    function Kernel.KernelLoopPlanReduction:kernel_plan_is_reduction() return true end
    function Kernel.KernelLoopPlanSelection:kernel_plan_is_skeleton() return false end
    function Kernel.KernelLoopPlanSkeleton:kernel_plan_is_skeleton() return true end
    function Kernel.KernelLoopPlanSelection:kernel_plan_is_original_control() return false end
    function Kernel.KernelLoopPlanOriginalControl:kernel_plan_is_original_control() return true end

    function Kernel.KernelLoopPlanSelection:add_selected_loop_plan(plans, subject, state)
        local body = Kernel.KernelBody(
            Kernel.KernelDomainFlow(state.domain, state.trip_count, state.counter),
            state.lanes,
            state.bindings,
            state.effects,
            Kernel.KernelResultOriginalControl("semantic loop kernel preserves original control by default"),
            Kernel.KernelEquivalenceProof(state.proofs)
        )
        plans[#plans + 1] = Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(subject.loop.text)), subject, body)
    end

    function Kernel.KernelLoopNoPlan:add_selected_loop_plan(plans, subject, state)
        plans[#plans + 1] = Kernel.KernelNoPlan(subject, self.rejects)
    end

    function Kernel.KernelLoopPlanClosedForm:add_selected_loop_plan(plans, subject, state)
        state.proofs[#state.proofs + 1] = Kernel.KernelProofValue(self.closed_form.proof, "closed form fact justifies kernel result")
        if self.add_trip_unknown_proof then
            -- The current closed-form expression encodes start/stop/step directly, so
            -- keep the plan but make the proof dependence explicit rather than claiming
            -- an exact FlowTripCountExact fact that Flow does not provide yet.
            state.proofs[#state.proofs + 1] = Kernel.KernelProofFlow(state.domain, "closed-form expression uses counted start/stop/step directly; FlowTripCountExact is unavailable")
        end
        local body = Kernel.KernelBody(
            Kernel.KernelDomainFlow(state.domain, state.trip_count, state.counter),
            state.lanes,
            state.bindings,
            state.effects,
            Kernel.KernelResultClosedForm(self.closed_form),
            Kernel.KernelEquivalenceProof(state.proofs)
        )
        plans[#plans + 1] = Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(subject.loop.text)), subject, body)
    end

    function Kernel.KernelLoopPlanReduction:add_selected_loop_plan(plans, subject, state)
        local body = Kernel.KernelBody(
            Kernel.KernelDomainFlow(state.domain, state.trip_count, state.counter),
            state.lanes,
            state.bindings,
            state.effects,
            Kernel.KernelResultReduction(self.reduction),
            Kernel.KernelEquivalenceProof(state.proofs)
        )
        plans[#plans + 1] = Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(subject.loop.text)), subject, body)
    end

    function Kernel.KernelLoopPlanSkeleton:add_selected_loop_plan(plans, subject, state)
        local body = Kernel.KernelBody(
            Kernel.KernelDomainFlow(state.domain, state.trip_count, state.counter),
            state.lanes,
            state.bindings,
            state.effects,
            self.result,
            Kernel.KernelEquivalenceProof(state.proofs)
        )
        plans[#plans + 1] = Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(subject.loop.text)), subject, body)
    end

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
            if asdl.classof(fact) == Flow.FlowLoopNormalizedCounted then out[fact.loop.text] = fact.trip_count end
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

    function Mem.MemAccessKind:kernel_plan_is_write_access() return false end
    function Mem.MemStore:kernel_plan_is_write_access() return true end
    function Mem.MemAtomicStore:kernel_plan_is_write_access() return true end
    function Mem.MemAtomicRmw:kernel_plan_is_write_access() return true end
    function Mem.MemAtomicCas:kernel_plan_is_write_access() return true end

    local function is_write_access(kind)
        return kind:kernel_plan_is_write_access()
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

    local function lanes_for_accesses(func_id, loop_id, loop_blocks, mem, rejects, proofs)
        local _, object_by_access, backend_by_access = access_indexes(mem)
        local lane_by_access = {}
        local grouped = {}
        local loop_accesses = {}
        for _, access in ipairs(mem and mem.accesses or {}) do
            if access.func == func_id and loop_blocks[access.block.block.text] then
                local object = object_by_access[access.id.text]
                local backend = backend_by_access[access.id.text]
                if backend == nil then
                    rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "missing MemBackendAccessInfo for loop-local access")
                elseif asdl.classof(backend.trap) ~= Mem.MemNonTrapping then
                    rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "loop-local access is not proven non-trapping")
                elseif asdl.classof(backend.bounds) == Mem.MemBoundsUnknown then
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
            local dcls = asdl.classof(dep)
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
        local lanes = {}
        local keys = {}
        for key in pairs(grouped) do keys[#keys + 1] = key end
        table.sort(keys)
        for i, key in ipairs(keys) do
            local g = grouped[key]
            local lane = Kernel.KernelLane(Kernel.KernelLaneId("lane:" .. sanitize(func_id.text) .. ":" .. sanitize(loop_id.text) .. ":" .. tostring(i)), g.object, g.accesses, g.base, g.elem_ty, g.pattern, g.backend)
            lanes[#lanes + 1] = lane
            for _, aid in ipairs(g.accesses or {}) do lane_by_access[aid.text] = lane end
        end
        return lanes, lane_by_access, dependence_rejects
    end

    local function reductions_for_domain(value, domain)
        local reductions, closed_forms = {}, {}
        for _, r in ipairs(value and value.reductions or {}) do
            if asdl.classof(r.domain) == Flow.FlowDomainLoop and asdl.classof(domain) == Flow.FlowDomainLoop and r.domain.loop == domain.loop then reductions[#reductions + 1] = r end
        end
        for _, cf in ipairs(value and value.closed_forms or {}) do
            if asdl.classof(cf.reduction.domain) == Flow.FlowDomainLoop and asdl.classof(domain) == Flow.FlowDomainLoop and cf.reduction.domain.loop == domain.loop then closed_forms[#closed_forms + 1] = cf end
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
        local cls = asdl.classof(eff)
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
        local cls = asdl.classof(mem_index)
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
        local cls = asdl.classof(k)
        if cls == Code.CodeInstConst then return k.const.ty end
        if cls == Code.CodeInstAlias then return k.ty end
        if cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect then return k.ty end
        if cls == Code.CodeInstCompare then return Code.CodeTyBool8 end
        if cls == Code.CodeInstCast then return k.to end
        return k.ty
    end

    local function build_kernel_body(func, loop_blocks, value, mem, lane_by_access, reduction_backedges, rejects)
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
                    local cls = asdl.classof(k)
                    if cls == Code.CodeInstLoad then
                        local aid = Mem.MemAccessId(access_id_text(func, block, inst))
                        local lane = lane_by_access[aid.text]
                        local access = access_by_id[aid.text]
                        if lane == nil or access == nil then rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(aid, "load has no kernel lane")
                        else add_binding(k.dst, k.access.ty, Kernel.KernelExprLaneLoad(lane, index_expr(access.index))) end
                    elseif cls == Code.CodeInstStore then
                        local aid = Mem.MemAccessId(access_id_text(func, block, inst))
                        local lane = lane_by_access[aid.text]
                        local access = access_by_id[aid.text]
                        local val = kernel_value_expr(value_index, bindings_by_value, k.value)
                        if lane == nil or access == nil then rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(aid, "store has no kernel lane")
                        elseif val == nil then rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedExpr(k.value, "store value cannot be represented as KernelExpr")
                        else effects[#effects + 1] = Kernel.KernelEffectStore(lane, index_expr(access.index), val) end
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
            if asdl.classof(effect) == cls then
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
        if asdl.classof(expr) ~= Kernel.KernelExprKernelValue then return expr end
        seen = seen or {}
        if seen[expr.value.text] then return expr end
        seen[expr.value.text] = true
        local binding = bindings[expr.value.text]
        if binding == nil then return expr end
        return resolve_kernel_expr(binding.expr, bindings, seen)
    end

    local function canonical_value(value, aliases)
        local seen = {}
        while value ~= nil and aliases ~= nil and aliases[value.text] ~= nil and not seen[value.text] do
            seen[value.text] = true
            value = aliases[value.text]
        end
        return value
    end

    local function loop_body_aliases(graph_loop, flow)
        local latch = graph_loop and graph_loop.latches and graph_loop.latches[1] or nil
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

    local function value_expr_is_value(expr, id, aliases)
        if id == nil or asdl.classof(expr) ~= Value.ValueExprValue then return false end
        return canonical_value(expr.value, aliases) == canonical_value(id, aliases)
    end

    local function same_value_expr(a, b, aliases)
        if a == b then return true end
        local ac, bc = asdl.classof(a), asdl.classof(b)
        if ac ~= bc then return false end
        if ac == Value.ValueExprValue then return canonical_value(a.value, aliases) == canonical_value(b.value, aliases) end
        if ac == Value.ValueExprConst then return a.const == b.const end
        return false
    end

    local function const_int_expr(expr)
        if asdl.classof(expr) ~= Value.ValueExprConst then return nil end
        local c = expr.const
        if asdl.classof(c) ~= Code.CodeConstLiteral or asdl.classof(c.literal) ~= Core.LitInt then return nil end
        return tonumber(c.literal.raw)
    end

    local function is_minus_one_expr(expr)
        return const_int_expr(expr) == -1
    end

    function Value.ReductionKind:kernel_plan_update_matches_expr(expr, reduction, aliases)
        return false
    end
    function Value.ReductionAdd:kernel_plan_update_matches_expr(expr, reduction, aliases)
        return expr:kernel_plan_matches_add_update(reduction, aliases)
    end
    function Value.ReductionMul:kernel_plan_update_matches_expr(expr, reduction, aliases)
        return expr:kernel_plan_matches_mul_update(reduction, aliases)
    end
    function Kernel.KernelExpr:kernel_plan_matches_add_update(reduction, aliases) return false end
    function Kernel.KernelExpr:kernel_plan_matches_mul_update(reduction, aliases) return false end
    function Kernel.KernelExprAlgebra:kernel_plan_matches_add_update(reduction, aliases)
        return self.expr:kernel_plan_matches_add_update(reduction, aliases)
    end
    function Kernel.KernelExprAlgebra:kernel_plan_matches_mul_update(reduction, aliases)
        return self.expr:kernel_plan_matches_mul_update(reduction, aliases)
    end
    function Value.ValueExpr:kernel_plan_matches_add_update(reduction, aliases) return false end
    function Value.ValueExpr:kernel_plan_matches_mul_update(reduction, aliases) return false end
    function Value.ValueExprAdd:kernel_plan_matches_add_update(reduction, aliases)
        local acc = reduction.accumulator
        local contrib = reduction.contribution
        return (value_expr_is_value(self.a, acc, aliases) and same_value_expr(self.b, contrib, aliases))
            or (value_expr_is_value(self.b, acc, aliases) and same_value_expr(self.a, contrib, aliases))
    end
    function Value.ValueExprMul:kernel_plan_matches_mul_update(reduction, aliases)
        local acc = reduction.accumulator
        local contrib = reduction.contribution
        return (value_expr_is_value(self.a, acc, aliases) and same_value_expr(self.b, contrib, aliases))
            or (value_expr_is_value(self.b, acc, aliases) and same_value_expr(self.a, contrib, aliases))
    end

    local function reduction_update_matches(expr, reduction, aliases)
        return reduction.kind:kernel_plan_update_matches_expr(expr, reduction, aliases)
    end

    local function loop_primary_induction(loop)
        for _, induction in ipairs(loop and loop.inductions or {}) do
            local value = induction.kind:kernel_plan_primary_induction_value(induction)
            if value ~= nil then return value end
        end
        return nil
    end

    function Flow.FlowInductionKind:kernel_plan_primary_induction_value(induction) return nil end
    function Flow.FlowPrimaryInduction:kernel_plan_primary_induction_value(induction) return induction.value end

    local function value_expr_binding(value, bindings)
        if value == nil or bindings == nil then return nil end
        local binding = bindings["kval:" .. value.text]
        if binding == nil then return nil end
        local expr = resolve_kernel_expr(binding.expr, bindings)
        if asdl.classof(expr) == Kernel.KernelExprAlgebra then return expr.expr end
        return nil
    end

    local function expr_is_primary(expr, loop, aliases, bindings, seen)
        if expr == nil then return false end
        if value_expr_is_value(expr, loop_primary_induction(loop), aliases) then return true end
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprValue then
            seen = seen or {}
            if seen[expr.value.text] then return false end
            seen[expr.value.text] = true
            return expr_is_primary(value_expr_binding(expr.value, bindings), loop, aliases, bindings, seen)
        end
        if cls == Value.ValueExprCast then return expr_is_primary(expr.value, loop, aliases, bindings, seen) end
        if cls == Value.ValueExprMul then
            if const_int_expr(expr.a) == 1 then return expr_is_primary(expr.b, loop, aliases, bindings, seen) end
            if const_int_expr(expr.b) == 1 then return expr_is_primary(expr.a, loop, aliases, bindings, seen) end
        end
        if cls == Value.ValueExprAdd then
            if const_int_expr(expr.a) == 0 then return expr_is_primary(expr.b, loop, aliases, bindings, seen) end
            if const_int_expr(expr.b) == 0 then return expr_is_primary(expr.a, loop, aliases, bindings, seen) end
        end
        return false
    end

    local function index_is_primary(index, loop, aliases, bindings)
        return expr_is_primary(index, loop, aliases, bindings)
    end

    local function lane_has_access(lane, id)
        if lane == nil or id == nil then return false end
        for _, access in ipairs(lane.accesses or {}) do
            if access.text == id.text then return true end
        end
        return false
    end

    local function copy_dependence_semantics(dst, src, dependence_rejects)
        local needs_memmove = false
        for _, dep in ipairs(dependence_rejects or {}) do
            local before_dst, before_src = lane_has_access(dst, dep.before), lane_has_access(src, dep.before)
            local after_dst, after_src = lane_has_access(dst, dep.after), lane_has_access(src, dep.after)
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
        local cls = asdl.classof(k)
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

    local function substitute_value(value, env)
        local seen = {}
        while value ~= nil and env ~= nil and env[value.text] ~= nil and not seen[value.text] do
            seen[value.text] = true
            value = env[value.text]
        end
        return value
    end

    local function edge_return_expr(blocks, edge, value_index)
        local from, block = blocks[edge.from.block.text], blocks[edge.to.block.text]
        if from == nil or block == nil then return nil end
        local env = {}
        local args = term_args_to_dest(from.term, block.id)
        for i, param in ipairs(block.params or {}) do
            if args and args[i] then env[param.value.text] = substitute_value(args[i], env) end
        end
        local seen = {}
        while block ~= nil and not seen[block.id.text] do
            seen[block.id.text] = true
            local term = block.term and block.term.kind or nil
            local cls = asdl.classof(term)
            if cls == Code.CodeTermReturn then
                if #(term.values or {}) ~= 1 then return nil end
                local value = substitute_value(term.values[1], env)
                if value == nil then return nil end
                return value_index.expr_by_value[value.text] or Value.ValueExprValue(value), value
            end
            if cls ~= Code.CodeTermJump then return nil end
            local dest = blocks[term.dest.text]
            if dest == nil then return nil end
            local next_env = {}
            for i, param in ipairs(dest.params or {}) do
                if term.args and term.args[i] then next_env[param.value.text] = substitute_value(term.args[i], env) end
            end
            block, env = dest, next_env
        end
        return nil
    end

    local function edge_branch_polarity(blocks, edge)
        local from = blocks[edge.from.block.text]
        local term = from and from.term and from.term.kind or nil
        if asdl.classof(term) ~= Code.CodeTermBranch then return nil, nil end
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

    local function pred_from_cmp(op, operand_ty, cexpr)
        if op == Core.CmpEq or op == Core.CmpNe or op == Core.CmpLt or op == Core.CmpLe or op == Core.CmpGt or op == Core.CmpGe then
            return Stencil.StencilPredCompareConst(op, operand_ty, cexpr)
        end
        return nil
    end

    local function same_load_expr(a, b)
        if asdl.classof(a) ~= Kernel.KernelExprLaneLoad or asdl.classof(b) ~= Kernel.KernelExprLaneLoad then return false end
        return a.lane == b.lane and same_value_expr(a.index, b.index)
    end

    local function expr_as_kernel_value(expr, bindings)
        if asdl.classof(expr) ~= Value.ValueExprValue then return nil end
        return resolve_kernel_expr(Kernel.KernelExprKernelValue(Kernel.KernelValueId("kval:" .. expr.value.text)), bindings)
    end

    local function find_predicate_from_cond(cond, polarity, bindings, value_index)
        local expr = cond and value_index.expr_by_value[cond.text] or nil
        if asdl.classof(expr) ~= Value.ValueExprCmp then return nil end
        local op = polarity and expr.op or invert_cmp(expr.op)
        if op == nil then return nil end
        local a_kernel, b_kernel = expr_as_kernel_value(expr.a, bindings), expr_as_kernel_value(expr.b, bindings)
        local a_const = asdl.classof(expr.a) == Value.ValueExprConst and expr.a or nil
        local b_const = asdl.classof(expr.b) == Value.ValueExprConst and expr.b or nil
        if a_kernel ~= nil and b_const ~= nil and asdl.classof(a_kernel) == Kernel.KernelExprLaneLoad then
            return a_kernel, pred_from_cmp(op, a_kernel.lane.elem_ty, b_const)
        end
        if b_kernel ~= nil and a_const ~= nil and asdl.classof(b_kernel) == Kernel.KernelExprLaneLoad then
            return b_kernel, pred_from_cmp(flip_cmp(op), b_kernel.lane.elem_ty, a_const)
        end
        return nil
    end

    local function scan_axis_from_header(func, graph_loop)
        local header_id = graph_loop and graph_loop.header and graph_loop.header.block
        if header_id == nil then return nil end
        for _, block in ipairs(func and func.blocks or {}) do
            if block.id ~= nil and block.id.text == header_id.text then
                local axis = tostring(block.name or ""):match("^ctl%.lln_loop_nd_.*_scan_axis_(%d+)$")
                axis = tonumber(axis)
                if axis ~= nil then return Stencil.StencilAxisRef(axis) end
                return nil
            end
        end
        return nil
    end

    local function infer_scan_skeleton(func, graph_loop, loop, effects, reductions, bindings, aliases, proofs)
        if #reductions ~= 1 then return nil end
        local store = first_effect(effects, Kernel.KernelEffectStore)
        if store == nil then return nil end
        local reduction = reductions[1]
        if not reduction_update_matches(resolve_kernel_expr(store.value, bindings), reduction, aliases) then return nil end
        proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("store of loop-carried reduction update is a prefix scan")
        return {
            effects = {
                Kernel.KernelEffectScan(store.dst, store.index, reduction, Stencil.StencilScanInclusive, scan_axis_from_header(func, graph_loop)),
                Kernel.KernelEffectFold(reduction),
            },
            result = Kernel.KernelResultReduction(reduction),
        }
    end

    local function infer_copy_skeleton(loop, effects, bindings, dependence_rejects, aliases, proofs)
        local store = first_effect(effects, Kernel.KernelEffectStore)
        if store == nil or not index_is_primary(store.index, loop, aliases, bindings) then return nil end
        local src = resolve_kernel_expr(store.value, bindings)
        if asdl.classof(src) ~= Kernel.KernelExprLaneLoad then return nil end
        if not index_is_primary(src.index, loop, aliases, bindings) then return nil end
        if store.dst.elem_ty ~= src.lane.elem_ty then return nil end
        local semantics, dep_reason = copy_dependence_semantics(store.dst, src.lane, dependence_rejects)
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

    local function scatter_reduce_kind(expr)
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprAdd then return Value.ReductionAdd, expr.a, expr.b, expr.ty, expr.sem end
        if cls == Value.ValueExprMul then return Value.ReductionMul, expr.a, expr.b, expr.ty, expr.sem end
        if cls == Value.ValueExprBinary then
            local kind = ReductionAlgebra.binary_reduction_kind(expr.op, false)
            if kind ~= nil then return kind, expr.a, expr.b, expr.ty, expr.sem end
        end
        return nil
    end

    local function resolved_value_expr(expr, bindings, seen)
        if expr == nil then return nil end
        if asdl.classof(expr) ~= Value.ValueExprValue then return expr end
        seen = seen or {}
        if seen[expr.value.text] then return expr end
        seen[expr.value.text] = true
        return resolved_value_expr(value_expr_binding(expr.value, bindings) or expr, bindings, seen)
    end

    local function value_expr_key(expr, bindings, aliases)
        expr = resolved_value_expr(expr, bindings)
        if expr == nil then return "nil" end
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprConst and asdl.classof(expr.const) == Code.CodeConstLiteral then
            local lit = expr.const.literal
            return "const:" .. tostring(asdl.classof(lit)) .. ":" .. tostring(lit and (lit.raw or lit.value))
        end
        if cls == Value.ValueExprValue then
            local binding = bindings and bindings["kval:" .. expr.value.text] or nil
            if binding ~= nil and asdl.classof(binding.expr) == Kernel.KernelExprLaneLoad then
                return "load:" .. tostring(binding.expr.lane.id.text) .. ":" .. value_expr_key(binding.expr.index, bindings, aliases)
            end
            local v = canonical_value(expr.value, aliases)
            return "value:" .. tostring(v and v.text)
        end
        if cls == Value.ValueExprCast then return value_expr_key(expr.value, bindings, aliases) end
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
            return tostring(cls) .. "(" .. value_expr_key(expr.a, bindings, aliases) .. "," .. value_expr_key(expr.b, bindings, aliases) .. ")"
        end
        if cls == Value.ValueExprBinary then
            return "binary:" .. tostring(expr.op) .. "(" .. value_expr_key(expr.a, bindings, aliases) .. "," .. value_expr_key(expr.b, bindings, aliases) .. ")"
        end
        return tostring(expr)
    end

    local function same_index_expr(a, b, bindings, aliases)
        return value_expr_key(a, bindings, aliases) == value_expr_key(b, bindings, aliases)
    end

    local function scatter_reduce_contribution(store, a, b, bindings, aliases)
        local ka = expr_as_kernel_value(a, bindings)
        local kb = expr_as_kernel_value(b, bindings)
        if asdl.classof(ka) == Kernel.KernelExprLaneLoad
            and ka.lane == store.dst
            and same_index_expr(ka.index, store.index, bindings, aliases) then
            return kb or Kernel.KernelExprAlgebra(b)
        end
        if asdl.classof(kb) == Kernel.KernelExprLaneLoad
            and kb.lane == store.dst
            and same_index_expr(kb.index, store.index, bindings, aliases) then
            return ka or Kernel.KernelExprAlgebra(a)
        end
        return nil
    end

    local function scatter_reduce_select_kind(expr, bindings, aliases)
        if asdl.classof(expr) ~= Value.ValueExprSelect then return nil end
        local cond = resolved_value_expr(expr.cond, bindings)
        if asdl.classof(cond) ~= Value.ValueExprCmp then return nil end
        local lhs_key = value_expr_key(cond.a, bindings, aliases)
        local rhs_key = value_expr_key(cond.b, bindings, aliases)
        local t_key = value_expr_key(expr.t, bindings, aliases)
        local f_key = value_expr_key(expr.f, bindings, aliases)
        if lhs_key == t_key and rhs_key == f_key then
            return ReductionAlgebra.select_minmax_kind(cond.op, true), expr.t, expr.f
        end
        if lhs_key == f_key and rhs_key == t_key then
            return ReductionAlgebra.select_minmax_kind(cond.op, false), expr.t, expr.f
        end
        return nil
    end

    local function infer_scatter_reduce_skeleton(loop, effects, bindings, aliases, proofs)
        local store = first_effect(effects, Kernel.KernelEffectStore)
        if store == nil then return nil end
        local value = resolve_kernel_expr(store.value, bindings)
        if asdl.classof(value) ~= Kernel.KernelExprAlgebra then return nil end
        local kind, a, b, ty, sem = scatter_reduce_kind(value.expr)
        if kind == nil then
            kind, a, b = scatter_reduce_select_kind(value.expr, bindings, aliases)
            ty = store.dst.elem_ty
        end
        if kind == nil then return nil end
        local contribution = scatter_reduce_contribution(store, a, b, bindings, aliases)
        if contribution == nil then return nil end
        local identity, reason = ReductionAlgebra.identity_expr(kind, store.dst.elem_ty)
        if identity == nil then return nil, reason end
        local reducer = Stencil.StencilReducer(kind, store.dst.elem_ty, identity, sem, nil)
        proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("indexed read-modify-write store is a scatter-reduce skeleton")
        return {
            effects = {
                Kernel.KernelEffectScatterReduce(store.dst, store.index, contribution, reducer),
            },
            result = Kernel.KernelResultVoid,
            handles_dependences = true,
        }
    end

    local function infer_find_skeleton(func, graph_loop, loop, body_bindings, value_index, aliases, proofs)
        if graph_loop == nil or #(graph_loop.exits or {}) ~= 2 then return nil end
        local primary = loop_primary_induction(loop)
        if primary == nil then return nil end
        local bindings = binding_index(body_bindings)
        local blocks = block_index(func)
        local hit_src, hit_pred, not_found = nil, nil, nil
        for _, edge in ipairs(graph_loop.exits or {}) do
            local ret_expr, ret_value = edge_return_expr(blocks, edge, value_index)
            if ret_expr ~= nil and (canonical_value(ret_value, aliases) == canonical_value(primary, aliases) or value_expr_is_value(ret_expr, primary, aliases)) then
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
        if asdl.classof(hit_src) ~= Kernel.KernelExprLaneLoad or not index_is_primary(hit_src.index, loop, aliases, bindings) then return nil end
        proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("early-exit primary-index search is an array find skeleton")
        return {
            effects = {},
            result = Kernel.KernelResultFind(hit_src, hit_pred, not_found),
        }
    end

    local function infer_loop_skeleton(func, graph_loop, loop, effects, reductions, body_bindings, dependence_rejects, value_index, aliases, proofs)
        local bindings = binding_index(body_bindings)
        local scan = infer_scan_skeleton(func, graph_loop, loop, effects, reductions, bindings, aliases, proofs)
        if scan ~= nil then return scan end
        if #reductions == 0 then
            local scatter_reduce = infer_scatter_reduce_skeleton(loop, effects, bindings, aliases, proofs)
            if scatter_reduce ~= nil then return scatter_reduce end
            local find = infer_find_skeleton(func, graph_loop, loop, body_bindings, value_index, aliases, proofs)
            if find ~= nil then return find end
            local copy = infer_copy_skeleton(loop, effects, bindings, dependence_rejects, aliases, proofs)
            if copy ~= nil then return copy end
        end
        return nil
    end

    local function same_code_const(a, b)
        if a == b then return true end
        if asdl.classof(a) ~= Code.CodeConstLiteral or asdl.classof(b) ~= Code.CodeConstLiteral then return false end
        if a.ty ~= b.ty then return false end
        local al, bl = a.literal, b.literal
        local alc, blc = asdl.classof(al), asdl.classof(bl)
        if alc ~= blc then return false end
        return al ~= nil and bl ~= nil and al.raw == bl.raw
    end

    local function same_value_id_semantic(a, b, value_index)
        if a == b then return true end
        local ae = a and value_index and value_index.expr_by_value[a.text] or nil
        local be = b and value_index and value_index.expr_by_value[b.text] or nil
        if asdl.classof(ae) == Value.ValueExprConst and asdl.classof(be) == Value.ValueExprConst then return same_code_const(ae.const, be.const) end
        return false
    end

    local function same_counted_domain(a, b, value_index)
        return a ~= nil and b ~= nil
            and same_value_id_semantic(a.start, b.start, value_index)
            and same_value_id_semantic(a.stop, b.stop, value_index)
            and same_value_id_semantic(a.step, b.step, value_index)
            and a.stop_exclusive == b.stop_exclusive
    end

    local function first_store_effect(effects)
        for _, effect in ipairs(effects or {}) do
            if asdl.classof(effect) == Kernel.KernelEffectStore then return effect end
        end
        return nil
    end

    local function infer_partition_skeleton(func, graph_func, flow, flow_loops, value, mem, trip_counts)
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
        local group_a, group_b = grouped[order[1]], grouped[order[2]]
        local loop_a = flow_loops[group_a[1].id.text]
        local loop_b = flow_loops[group_b[1].id.text]
        local value_index = CodeValueFacts.expr_index(value)
        if loop_a == nil or loop_b == nil or not same_counted_domain(loop_a.counted, loop_b.counted, value_index) then return nil end
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
        local lanes, lane_by_access, dependence_rejects = lanes_for_accesses(func.id, loop_a.loop, loop_blocks, mem, rejects, proofs)
        if #rejects > 0 then return nil end

        local body_bindings, body_effects = build_kernel_body(func, loop_blocks, value, mem, lane_by_access, {}, rejects)
        if #rejects > 0 then return nil end
        local store = first_store_effect(body_effects)
        if store == nil then return nil end
        local bindings = binding_index(body_bindings)
        local aliases = loop_body_aliases(group_a[1], flow)
        local src, pred = nil, nil
        for _, block in ipairs(func.blocks or {}) do
            if loop_blocks[block.id.text] then
                local term = block.term and block.term.kind or nil
                if asdl.classof(term) == Code.CodeTermBranch then
                    local candidate_src, candidate_pred = find_predicate_from_cond(term.cond, true, bindings, value_index)
                    if candidate_src ~= nil and candidate_pred ~= nil and asdl.classof(candidate_src) == Kernel.KernelExprLaneLoad then
                        src, pred = candidate_src, candidate_pred
                        break
                    end
                end
            end
        end
        if src == nil or pred == nil or not index_is_primary(src.index, loop_a, aliases, bindings) then return nil end
        if store.dst.elem_ty ~= src.lane.elem_ty then return nil end
        for _, dep in ipairs(dependence_rejects or {}) do
            local before_dst, before_src = lane_has_access(store.dst, dep.before), lane_has_access(src.lane, dep.before)
            local after_dst, after_src = lane_has_access(store.dst, dep.after), lane_has_access(src.lane, dep.after)
            if not ((before_dst and after_src) or (before_src and after_dst) or (before_dst and after_dst)) then return nil end
        end
        proofs[#proofs + 1] = Kernel.KernelProofFunctionEquivalence("two-pass predicate-preserving copy is a stable partition skeleton")
        local body = Kernel.KernelBody(
            Kernel.KernelDomainFlow(domain, trip_counts[loop_a.loop.text] or Flow.FlowTripCountUnknown("no semantic trip-count fact"), loop_primary_induction(loop_a)),
            lanes,
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
            if loop.counted == nil then
                local selection = Kernel.KernelLoopPlanInput(
                    false,
                    func_id ~= nil,
                    false,
                    {},
                    { Kernel.KernelRejectNoFacts(subject, "loop is not a counted Flow domain") },
                    { Kernel.KernelRejectNoFacts(subject, "graph loop has no function owner") },
                    nil,
                    nil,
                    nil,
                    Flow.FlowTripCountUnknown("uncounted loop")
                ):select_kernel_loop_plan()
                selection:add_selected_loop_plan(plans, subject)
            elseif func_id == nil then
                local selection = Kernel.KernelLoopPlanInput(
                    true,
                    false,
                    false,
                    {},
                    { Kernel.KernelRejectNoFacts(subject, "loop is not a counted Flow domain") },
                    { Kernel.KernelRejectNoFacts(subject, "graph loop has no function owner") },
                    nil,
                    nil,
                    nil,
                    Flow.FlowTripCountUnknown("ownerless loop")
                ):select_kernel_loop_plan()
                selection:add_selected_loop_plan(plans, subject)
            else
                local func = funcs[func_id.text]
                local domain = Flow.FlowDomainLoop(loop.loop)
                local rejects = {}
                local proofs = { Kernel.KernelProofFlow(domain, "Flow counted-domain recognition") }
                local loop_blocks = block_set(loop.body_blocks or loop.body)
                if func == nil then rejects[#rejects + 1] = Kernel.KernelRejectNoFacts(subject, "graph loop owner function is missing from CodeModule") end
                local lanes, lane_by_access, dependence_rejects = lanes_for_accesses(func_id, loop.loop, loop_blocks, mem, rejects, proofs)
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
                    body_bindings, body_effects = build_kernel_body(func, loop_blocks, value, mem, lane_by_access, reduction_backedges, rejects)
                end
                local skeleton = nil
                if #rejects == 0 then
                    local aliases = loop_body_aliases(graph_loop, flow)
                    skeleton = infer_loop_skeleton(func, graph_loop, loop, body_effects, reductions, body_bindings, dependence_rejects, value_index, aliases, proofs)
                end
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
                local selection = Kernel.KernelLoopPlanInput(
                    true,
                    true,
                    func ~= nil,
                    rejects,
                    { Kernel.KernelRejectNoFacts(subject, "loop is not a counted Flow domain") },
                    { Kernel.KernelRejectNoFacts(subject, "graph loop has no function owner") },
                    closed_forms[1],
                    reductions[1],
                    skeleton and skeleton.result or nil,
                    trip
                ):select_kernel_loop_plan()
                local counter = loop.inductions and loop.inductions[1] and loop.inductions[1].value or nil
                selection:add_selected_loop_plan(plans, subject, Kernel.KernelLoopPlanBuild(domain, trip, counter, lanes, body_bindings, effects, proofs))
            end
        end

        for _, func in ipairs(module.funcs or {}) do
            local partition = infer_partition_skeleton(func, graph_funcs[func.id.text], flow, flow_loops, value, mem, trip_counts)
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

    T._lalin_api_cache.code_kernel_plan = api
    return api
end

return bind_context
