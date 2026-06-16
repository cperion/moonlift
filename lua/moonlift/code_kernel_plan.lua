local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T)
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
    local CodeGraph = require("moonlift.code_graph").Define(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts").Define(T)
    local CodeValueFacts = require("moonlift.code_value_facts").Define(T)
    local CodeMemFacts = require("moonlift.code_mem_facts").Define(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts").Define(T)

    local api = {}

    local function graph_loop_func(graph)
        local out = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do out[loop.id.text] = fg.func end
        end
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
        for i = 1, #loop_accesses do
            for j = i + 1, #loop_accesses do
                local a, b = loop_accesses[i], loop_accesses[j]
                if is_write_access(a.kind) or is_write_access(b.kind) then
                    local key = a.id.text .. "\0" .. b.id.text
                    if dep_unknown[key] or not dep_proved[key] then
                        rejects[#rejects + 1] = Kernel.KernelRejectNoFacts(Kernel.KernelSubjectLoop(loop_id), "loop write pair lacks pairwise no-dependence proof: " .. a.id.text .. " / " .. b.id.text)
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
        return streams, stream_by_access
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
                        rejects[#rejects + 1] = Kernel.KernelRejectEffect(eff, "loop-local effect is unsupported by semantic kernel v1")
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
                        rejects[#rejects + 1] = Kernel.KernelRejectEffect(eff, "loop-local terminator/contract effect is unsupported by semantic kernel v1")
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
        if cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect then return k.ty end
        if cls == Code.CodeInstCompare then return Code.CodeTyBool8 end
        if cls == Code.CodeInstCast then return k.to end
        return k.ty
    end

    local function build_kernel_body(func, loop_blocks, value, mem, stream_by_access, rejects)
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
                    elseif cls == Code.CodeInstConst or cls == Code.CodeInstAlias or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstCompare or cls == Code.CodeInstSelect or cls == Code.CodeInstCast then
                        local dst = k.dst
                        if dst ~= nil then
                            local expr = value_index.expr_by_value[dst.text]
                            if expr ~= nil then add_binding(dst, inst_result_ty(k), Kernel.KernelExprAlgebra(expr))
                            else rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedExpr(dst, "loop-local value instruction lacks ValueExprFact") end
                        end
                    elseif cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicStore or cls == Code.CodeInstAtomicRmw or cls == Code.CodeInstAtomicCas or cls == Code.CodeInstAtomicFence or cls == Code.CodeInstCall then
                        rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedExpr((k.dst or Code.CodeValueId(inst.id.text)), "unsupported side-effecting instruction in kernel body")
                    else
                        -- Address/projection/view instructions may feed memory facts; they are not executable kernel ops in v1 unless they define a value used in a binding.
                    end
                end
            end
        end
        return bindings, effects
    end

    local function function_plans(module, graph, flow, value, mem, effect)
        local plans = {}
        local funcs = {}
        for _, func in ipairs(module.funcs or {}) do funcs[func.id.text] = func end
        local loop_func = graph_loop_func(graph)
        local trip_counts = semantic_trip_counts(module, graph, flow)

        for _, loop in ipairs(flow and flow.loops or {}) do
            local subject = Kernel.KernelSubjectLoop(loop.loop)
            local func_id = loop_func[loop.loop.text]
            if loop.counted == nil then
                plans[#plans + 1] = Kernel.KernelNoPlan(subject, { Kernel.KernelRejectNoFacts(subject, "loop is not a counted Flow domain") })
            elseif func_id == nil then
                plans[#plans + 1] = Kernel.KernelNoPlan(subject, { Kernel.KernelRejectNoFacts(subject, "graph loop has no function owner") })
            else
                local func = funcs[func_id.text]
                local domain = Flow.FlowDomainLoop(loop.loop)
                local rejects = {}
                local proofs = { Kernel.KernelProofFlow(domain, "Flow counted-domain recognition") }
                local loop_blocks = block_set(loop.body_blocks or loop.body)
                if func == nil then rejects[#rejects + 1] = Kernel.KernelRejectNoFacts(subject, "graph loop owner function is missing from CodeModule") end
                local streams, stream_by_access = streams_for_accesses(func_id, loop.loop, loop_blocks, mem, rejects, proofs)
                local effects = func and loop_effects(func, loop_blocks, effect, rejects, proofs) or {}
                local body_bindings, body_effects = {}, {}
                if func ~= nil then
                    body_bindings, body_effects = build_kernel_body(func, loop_blocks, value, mem, stream_by_access, rejects)
                end
                for _, e in ipairs(body_effects or {}) do effects[#effects + 1] = e end
                local reductions, closed_forms = reductions_for_domain(value, domain)
                for _, reduction in ipairs(reductions) do
                    effects[#effects + 1] = Kernel.KernelEffectFold(reduction)
                    proofs[#proofs + 1] = Kernel.KernelProofValue(reduction.proof, "reduction fact justifies kernel fold")
                end
                local result = Kernel.KernelResultOriginalControl("semantic loop kernel preserves original control by default")
                if #closed_forms > 0 then
                    result = Kernel.KernelResultClosedForm(closed_forms[1])
                    proofs[#proofs + 1] = Kernel.KernelProofValue(closed_forms[1].proof, "closed form fact justifies kernel result")
                elseif #reductions > 0 then
                    result = Kernel.KernelResultReduction(reductions[1])
                end
                local trip = trip_counts[loop.loop.text] or Flow.FlowTripCountUnknown("no semantic trip-count fact")
                if pvm.classof(result) == Kernel.KernelResultClosedForm and pvm.classof(trip) == Flow.FlowTripCountUnknown then
                    -- The current closed-form expression encodes start/stop/step directly, so
                    -- keep the plan but make the proof dependence explicit rather than claiming
                    -- an exact FlowTripCountExact fact that Flow does not provide yet.
                    proofs[#proofs + 1] = Kernel.KernelProofFlow(domain, "closed-form expression uses counted start/stop/step directly; FlowTripCountExact is unavailable")
                end
                if #rejects > 0 then
                    plans[#plans + 1] = Kernel.KernelNoPlan(subject, rejects)
                else
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
            plans[#plans + 1] = Kernel.KernelNoPlan(Kernel.KernelSubjectFunction(func.id), { Kernel.KernelRejectUnsupportedSubject(Kernel.KernelSubjectFunction(func.id), "function-level replacement is not a semantic kernel v1 plan") })
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

return M
