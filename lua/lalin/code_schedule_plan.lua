local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_schedule_plan ~= nil then return T._lalin_api_cache.code_schedule_plan end

    local Back = T.LalinBack
    local Code = T.LalinCode
    local Kernel = T.LalinKernel
    local Schedule = T.LalinSchedule
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local KernelEmitSupport = require("lalin.kernel_emit_support")(T)

    local api = {}

    local function capability_executable(capability)
        return capability ~= nil and capability.executable == true
    end

    local function capability_rejects(capability)
        return capability and capability.rejects or {}
    end

    function Schedule.SchedulePlanInput:select_kernel_schedule()
        if self.vector_kind ~= nil and capability_executable(self.vector_capability) then
            return Schedule.ScheduleSelectionPlanned(self.vector_kind, self.vector_capability, {})
        end
        if self.vector_kind ~= nil and (not capability_executable(self.vector_capability)) and capability_executable(self.scalar_capability) then
            return Schedule.ScheduleSelectionPlanned(self.scalar_kind, self.scalar_capability, capability_rejects(self.vector_capability))
        end
        if self.vector_kind == nil and capability_executable(self.scalar_capability) then
            return Schedule.ScheduleSelectionPlanned(self.scalar_kind, self.scalar_capability, {})
        end
        return Schedule.ScheduleSelectionNoPlan(capability_rejects(self.scalar_capability))
    end

    function Schedule.SchedulePlanSelection:schedule_plan_is_planned() return false end
    function Schedule.ScheduleSelectionPlanned:schedule_plan_is_planned() return true end
    function Schedule.SchedulePlanSelection:schedule_plan_is_no_plan() return false end
    function Schedule.ScheduleSelectionNoPlan:schedule_plan_is_no_plan() return true end

    function Schedule.SchedulePlanSelection:to_kernel_schedule(kid, plan, proofs_for_selection)
        error("code_schedule_plan: unsupported schedule selection", 2)
    end

    function Schedule.ScheduleSelectionNoPlan:to_kernel_schedule(kid, plan, proofs_for_selection)
        return Schedule.ScheduleNoPlan(kid, self.rejects)
    end

    function Schedule.ScheduleSelectionPlanned:to_kernel_schedule(kid, plan, proofs_for_selection)
        local capability = assert(self.capability, "planned schedule selection has no emitter capability")
        return Schedule.SchedulePlanned(
            Schedule.ScheduleId("schedule:" .. sanitize(kid.text) .. ":" .. sanitize(capability.kind)),
            kid,
            self.schedule,
            proofs_for_selection(plan, capability),
            self.rejected_alternatives or {}
        )
    end

    local function default_target()
        return Back.BackTargetModel(Back.BackTargetNative, {})
    end

    local function supports_masked_tail(target)
        for _, fact in ipairs(target and target.facts or {}) do if fact == Back.BackTargetSupportsMaskedTail then return true end end
        return false
    end

    local function target_prefers_unroll(target)
        for _, fact in ipairs(target and target.facts or {}) do
            if asdl.classof(fact) == Back.BackTargetPrefersUnroll then return fact.unroll end
        end
        return 1
    end

    local function proofs_for(plan, capability)
        local proofs = { Schedule.ScheduleProofTarget(capability.reason or "kernel emitter support classified executable") }
        local eq = plan.body and plan.body.equivalence or nil
        if asdl.classof(eq) == Kernel.KernelEquivalenceProof then
            for _, proof in ipairs(eq.proofs or {}) do
                local cls = asdl.classof(proof)
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
        local cls = asdl.classof(ty)
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

    local function vector_schedule_kind(plan, target)
        local body = plan.body
        if body == nil or #(body.lanes or {}) == 0 then return nil end
        if asdl.classof(body.result) == Kernel.KernelResultClosedForm then return nil end
        local elem_ty = nil
        for _, lane in ipairs(body.lanes or {}) do
            if lane.pattern ~= T.LalinMem.MemAccessContiguous then return nil end
            elem_ty = elem_ty or lane.elem_ty
            if scalar_for_code_ty(lane.elem_ty) ~= scalar_for_code_ty(elem_ty) then return nil end
        end
        local elem = scalar_for_code_ty(elem_ty)
        if elem == nil then return nil end
        for _, fact in ipairs(target and target.facts or {}) do
            if asdl.classof(fact) == Back.BackTargetSupportsShape and asdl.classof(fact.shape) == Back.BackShapeVec and fact.shape.vec.elem == elem then
                return Schedule.ScheduleVector(Schedule.LaneVector(elem_ty, fact.shape.vec.lanes), target_prefers_unroll(target), 1, Schedule.TailScalar)
            end
        end
        return nil
    end

    local function scalar_or_closed_kind_for(plan)
        local result = plan.body and plan.body.result or nil
        if asdl.classof(result) == Kernel.KernelResultClosedForm then return Schedule.ScheduleClosedForm end
        return Schedule.ScheduleScalarIndex
    end

    local function schedule_for_plan(plan, target, flow)
        local kid = plan.id
        local vector_kind = vector_schedule_kind(plan, target)
        local vector_cap = nil
        if vector_kind ~= nil then
            vector_cap = KernelEmitSupport.classify(plan, vector_kind, target, flow)
        end
        local scalar_kind = scalar_or_closed_kind_for(plan)
        local scalar_cap = vector_cap and vector_cap.executable and nil or KernelEmitSupport.classify(plan, scalar_kind, target, flow)
        local selection = Schedule.SchedulePlanInput(vector_kind, vector_cap, scalar_kind, scalar_cap):select_kernel_schedule()
        return selection:to_kernel_schedule(kid, plan, proofs_for)
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
            if asdl.classof(kernel_plan) == Kernel.KernelPlanned then
                schedules[#schedules + 1] = schedule_for_plan(kernel_plan, target, flow)
            end
        end
        return Schedule.ScheduleModulePlan(module.id, Schedule.ScheduleTarget(target), schedules)
    end

    api.plan = plan
    api.module = plan

    T._lalin_api_cache.code_schedule_plan = api
    return api
end

return bind_context
