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
    if T._moonlift_api_cache.code_schedule_plan ~= nil then return T._moonlift_api_cache.code_schedule_plan end

    local Back = T.MoonBack
    local Code = T.MoonCode
    local Kernel = T.MoonKernel
    local Schedule = T.MoonSchedule
    local CodeGraph = require("moonlift.code_graph").Define(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts").Define(T)
    local CodeValueFacts = require("moonlift.code_value_facts").Define(T)
    local CodeMemFacts = require("moonlift.code_mem_facts").Define(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts").Define(T)
    local CodeKernelPlan = require("moonlift.code_kernel_plan").Define(T)
    local KernelEmitSupport = require("moonlift.kernel_emit_support").Define(T)

    local api = {}

    local function default_target()
        return Back.BackTargetModel(Back.BackTargetNative, {})
    end

    local function supports_masked_tail(target)
        for _, fact in ipairs(target and target.facts or {}) do if fact == Back.BackTargetSupportsMaskedTail then return true end end
        return false
    end

    local function target_prefers_unroll(target)
        for _, fact in ipairs(target and target.facts or {}) do
            if pvm.classof(fact) == Back.BackTargetPrefersUnroll then return fact.unroll end
        end
        return 1
    end

    local function proofs_for(plan, capability)
        local proofs = { Schedule.ScheduleProofTarget(capability.reason or "kernel emitter support classified executable") }
        local eq = plan.body and plan.body.equivalence or nil
        if pvm.classof(eq) == Kernel.KernelEquivalenceProof then
            for _, proof in ipairs(eq.proofs or {}) do
                local cls = pvm.classof(proof)
                if cls == Kernel.KernelProofMemory then proofs[#proofs + 1] = Schedule.ScheduleProofMemory(proof.proof)
                elseif cls == Kernel.KernelProofValue then proofs[#proofs + 1] = Schedule.ScheduleProofAlgebra(proof.proof) end
            end
        end
        proofs[#proofs + 1] = Schedule.ScheduleProofProfit("selected because semantic lowering has an emitter for " .. tostring(capability.kind))
        return proofs
    end

    local function scalar_for_code_ty(ty)
        if ty == Code.CodeTyBool8 then return Back.BackBool end
        if ty == Code.CodeTyIndex then return Back.BackIndex end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then
            if ty.bits == 8 then return ty.signedness == Code.CodeSigned and Back.BackI8 or Back.BackU8 end
            if ty.bits == 16 then return ty.signedness == Code.CodeSigned and Back.BackI16 or Back.BackU16 end
            if ty.bits == 32 then return ty.signedness == Code.CodeSigned and Back.BackI32 or Back.BackU32 end
            if ty.bits == 64 then return ty.signedness == Code.CodeSigned and Back.BackI64 or Back.BackU64 end
        end
        if cls == Code.CodeTyFloat then
            if ty.bits == 32 then return Back.BackF32 end
            if ty.bits == 64 then return Back.BackF64 end
        end
        return nil
    end

    local function vector_candidate_kind(plan, target)
        local body = plan.body
        if body == nil or #(body.streams or {}) == 0 then return nil end
        if pvm.classof(body.result) == Kernel.KernelResultClosedForm then return nil end
        local elem_ty = nil
        for _, stream in ipairs(body.streams or {}) do
            if stream.pattern ~= T.MoonMem.MemAccessContiguous then return nil end
            elem_ty = elem_ty or stream.elem_ty
            if scalar_for_code_ty(stream.elem_ty) ~= scalar_for_code_ty(elem_ty) then return nil end
        end
        local elem = scalar_for_code_ty(elem_ty)
        if elem == nil then return nil end
        for _, fact in ipairs(target and target.facts or {}) do
            if pvm.classof(fact) == Back.BackTargetSupportsShape and pvm.classof(fact.shape) == Back.BackShapeVec and fact.shape.vec.elem == elem then
                return Schedule.ScheduleVector(Schedule.LaneVector(elem_ty, fact.shape.vec.lanes), target_prefers_unroll(target), 1, Schedule.TailScalar)
            end
        end
        return nil
    end

    local function scalar_or_closed_kind_for(plan)
        local result = plan.body and plan.body.result or nil
        if pvm.classof(result) == Kernel.KernelResultClosedForm then return Schedule.ScheduleClosedForm end
        return Schedule.ScheduleScalarIndex
    end

    local function schedule_for_plan(plan, target)
        local kid = plan.id
        local rejected_alternatives = {}
        local vector_kind = vector_candidate_kind(plan, target)
        if vector_kind ~= nil then
            local vcap = KernelEmitSupport.classify(plan, vector_kind, target)
            if vcap.executable then
                return Schedule.SchedulePlanned(
                    Schedule.ScheduleId("schedule:" .. sanitize(kid.text) .. ":" .. sanitize(vcap.kind)),
                    kid,
                    vector_kind,
                    proofs_for(plan, vcap),
                    {}
                )
            end
            for _, r in ipairs(vcap.rejects or {}) do rejected_alternatives[#rejected_alternatives + 1] = r end
        end
        local kind = scalar_or_closed_kind_for(plan)
        local capability = KernelEmitSupport.classify(plan, kind, target)
        if not capability.executable then return Schedule.ScheduleNoPlan(kid, capability.rejects) end
        return Schedule.SchedulePlanned(
            Schedule.ScheduleId("schedule:" .. sanitize(kid.text) .. ":" .. sanitize(capability.kind)),
            kid,
            kind,
            proofs_for(plan, capability),
            rejected_alternatives
        )
    end

    local function plan(module, kernels, flow, value, mem, effect, target)
        if kernels == nil then
            local graph = CodeGraph.graph(module)
            flow = flow or CodeFlowFacts.facts(module, graph)
            value = value or CodeValueFacts.facts(module, graph, flow)
            mem = mem or CodeMemFacts.semantic_facts(module, graph, flow, value, nil)
            effect = effect or CodeEffectFacts.facts(module, graph, mem, nil)
            kernels = CodeKernelPlan.plan(module, graph, flow, value, mem, effect)
        end
        target = target or default_target()
        local schedules = {}
        for _, kernel_plan in ipairs(kernels.plans or {}) do
            if pvm.classof(kernel_plan) == Kernel.KernelPlanned then
                schedules[#schedules + 1] = schedule_for_plan(kernel_plan, target)
            end
        end
        return Schedule.ScheduleModulePlan(module.id, Schedule.ScheduleTarget(target), schedules)
    end

    api.plan = plan
    api.module = plan

    T._moonlift_api_cache.code_schedule_plan = api
    return api
end

return M
