local asdl = require("lalin.asdl")

local function class_name(x)
    local cls = asdl.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.kernel_emit_support ~= nil then return T._lalin_api_cache.kernel_emit_support end

    local Code = T.LalinCode
    local Back = T.LalinBack
    local Flow = T.LalinFlow
    local Value = T.LalinValue
    local Mem = T.LalinMem
    local Kernel = T.LalinKernel
    local Schedule = T.LalinSchedule
    local ReductionAlgebra = require("lalin.reduction_algebra")(T)

    local api = {}

    local function reject_target(reason) return Schedule.ScheduleRejectTarget(reason) end
    local function reject_memory(reason) return Schedule.ScheduleRejectMemory(reason) end
    local function reject_algebra(reason) return Schedule.ScheduleRejectAlgebra(reason) end
    local function reject_profit(reason) return Schedule.ScheduleRejectProfit(reason) end
    local function summarize_rejects(rejects)
        if #rejects == 0 then return "no reject reasons" end
        local out = {}
        for i = 1, math.min(4, #rejects) do
            local reject = rejects[i]
            local msg = reject and (reject.reason or reject) or nil
            out[#out + 1] = tostring(msg or reject)
        end
        if #rejects > #out then
            out[#out + 1] = tostring(#rejects - #out) .. " additional reject(s)"
        end
        return table.concat(out, "; ")
    end

    local function append(dst, src)
        for _, v in ipairs(src or {}) do dst[#dst + 1] = v end
    end

    local function is_scalar_code_ty(ty)
        local cls = asdl.classof(ty)
        return ty == Code.CodeTyVoid
            or ty == Code.CodeTyBool8
            or ty == Code.CodeTyIndex
            or cls == Code.CodeTyInt
            or cls == Code.CodeTyFloat
            or cls == Code.CodeTyDataPtr
            or cls == Code.CodeTyCodePtr
            or cls == Code.CodeTyImportedCFuncPtr
            or cls == Code.CodeTyHandle
            or cls == Code.CodeTyLease
    end

    local function value_expr_supported(expr, seen)
        if expr == nil then return false, "missing ValueExpr" end
        seen = seen or {}
        if seen[expr] then return true end
        seen[expr] = true
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprConst or cls == Value.ValueExprValue then return true end
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul then
            if not is_scalar_code_ty(expr.ty) then return false, "non-scalar arithmetic type in " .. class_name(expr) end
            local ok, reason = value_expr_supported(expr.a, seen); if not ok then return false, reason end
            return value_expr_supported(expr.b, seen)
        end
        if cls == Value.ValueExprDiv or cls == Value.ValueExprRem then
            if not is_scalar_code_ty(expr.ty) then return false, "non-scalar div/rem type" end
            if expr.sem == nil then return false, "div/rem expression lacks exactness/semantics proof" end
            local ok, reason = value_expr_supported(expr.a, seen); if not ok then return false, reason end
            return value_expr_supported(expr.b, seen)
        end
        if cls == Value.ValueExprBinary then
            if not is_scalar_code_ty(expr.ty) then return false, "non-scalar binary type in " .. class_name(expr) end
            local ok, reason = value_expr_supported(expr.a, seen); if not ok then return false, reason end
            return value_expr_supported(expr.b, seen)
        end
        if cls == Value.ValueExprSelect then
            local ok, reason = value_expr_supported(expr.cond, seen); if not ok then return false, reason end
            ok, reason = value_expr_supported(expr.t, seen); if not ok then return false, reason end
            return value_expr_supported(expr.f, seen)
        end
        if cls == Value.ValueExprCmp then
            local ok, reason = value_expr_supported(expr.a, seen); if not ok then return false, reason end
            return value_expr_supported(expr.b, seen)
        end
        if cls == Value.ValueExprAffine then
            return true
        end
        return false, "unsupported ValueExpr " .. class_name(expr)
    end

    local function kernel_expr_supported(expr)
        if expr == nil then return false, "missing KernelExpr" end
        local cls = asdl.classof(expr)
        if cls == Kernel.KernelExprValue or cls == Kernel.KernelExprKernelValue then return true end
        if cls == Kernel.KernelExprAlgebra then return value_expr_supported(expr.expr) end
        if cls == Kernel.KernelExprLaneLoad then
            if asdl.classof(expr.lane) ~= Kernel.KernelLane then return false, "KernelExprLaneLoad has no concrete KernelLane" end
            local ok, reason = value_expr_supported(expr.index); if not ok then return false, reason end
            if #(expr.lane.backend_info or {}) == 0 then return false, "KernelExprLaneLoad lane lacks backend access info" end
            return true
        end
        return false, "unsupported KernelExpr " .. class_name(expr)
    end

    local function lane_supported(lane)
        if asdl.classof(lane) ~= Kernel.KernelLane then return false, "not a KernelLane" end
        if not is_scalar_code_ty(lane.elem_ty) then return false, "lane element type is not scalar-lowerable" end
        local pat_cls = asdl.classof(lane.pattern)
        if not (lane.pattern == Mem.MemAccessScalar or lane.pattern == Mem.MemAccessContiguous or pat_cls == Mem.MemAccessStrided) then
            return false, "unsupported lane access pattern " .. class_name(lane.pattern)
        end
        if #(lane.backend_info or {}) == 0 then return false, "lane has no backend memory info" end
        for _, info in ipairs(lane.backend_info or {}) do
            if asdl.classof(info.trap) ~= Mem.MemNonTrapping then return false, "lane access may trap" end
            if asdl.classof(info.bounds) == Mem.MemBoundsUnknown then return false, "lane access has unknown bounds" end
            if info.deref_bytes == nil then return false, "lane access lacks dereference byte proof" end
        end
        return true
    end

    local function schedule_kind_name(kind)
        local cls = asdl.classof(kind)
        if kind == Schedule.ScheduleClosedForm then return "closed_form" end
        if kind == Schedule.ScheduleScalarIndex then return "scalar_index" end
        if kind == Schedule.ScheduleScalarPointer then return "scalar_pointer" end
        if cls == Schedule.ScheduleVector then return "vector_contiguous" end
        return nil
    end

    local function target_supports_vector(target, elem_ty, lanes)
        if target == nil then return false end
        local scalar = nil
        local cls = asdl.classof(elem_ty)
        if elem_ty == Code.CodeTyIndex then scalar = Back.BackIndex
        elseif cls == Code.CodeTyInt then
            if elem_ty.bits == 32 then scalar = elem_ty.signedness == Code.CodeSigned and Back.BackI32 or Back.BackU32
            elseif elem_ty.bits == 64 then scalar = elem_ty.signedness == Code.CodeSigned and Back.BackI64 or Back.BackU64
            elseif elem_ty.bits == 16 then scalar = elem_ty.signedness == Code.CodeSigned and Back.BackI16 or Back.BackU16
            elseif elem_ty.bits == 8 then scalar = elem_ty.signedness == Code.CodeSigned and Back.BackI8 or Back.BackU8 end
        elseif cls == Code.CodeTyFloat then
            scalar = elem_ty.bits == 32 and Back.BackF32 or (elem_ty.bits == 64 and Back.BackF64 or nil)
        end
        if scalar == nil then return false end
        for _, fact in ipairs(target and target.facts or {}) do
            if asdl.classof(fact) == Back.BackTargetSupportsShape and asdl.classof(fact.shape) == Back.BackShapeVec then
                local vec = fact.shape.vec
                if vec.elem == scalar and vec.lanes == lanes then return true end
            end
        end
        return false
    end

    local function base_rejects(plan)
        local rejects = {}
        if asdl.classof(plan) ~= Kernel.KernelPlanned then
            rejects[#rejects + 1] = reject_target("only KernelPlanned can be emitted")
            return rejects
        end
        if asdl.classof(plan.subject) ~= Kernel.KernelSubjectLoop then rejects[#rejects + 1] = reject_target("only loop kernels have emitters") end
        local body = plan.body
        if body == nil then rejects[#rejects + 1] = reject_target("kernel has no body"); return rejects end
        if asdl.classof(body.equivalence) ~= Kernel.KernelEquivalenceProof or #(body.equivalence.proofs or {}) == 0 then
            rejects[#rejects + 1] = reject_algebra("kernel lacks equivalence proof")
        end
        if asdl.classof(body.domain) ~= Kernel.KernelDomainFlow then rejects[#rejects + 1] = reject_target("kernel domain is not Flow-backed") end
        for _, lane in ipairs(body.lanes or {}) do
            local ok, reason = lane_supported(lane)
            if not ok then rejects[#rejects + 1] = reject_memory(reason) end
        end
        for _, binding in ipairs(body.bindings or {}) do
            if not is_scalar_code_ty(binding.ty) then rejects[#rejects + 1] = reject_algebra("binding type is not scalar-lowerable") end
            local ok, reason = kernel_expr_supported(binding.expr)
            if not ok then rejects[#rejects + 1] = reject_algebra(reason) end
        end
        for _, effect in ipairs(body.effects or {}) do
            local ecls = asdl.classof(effect)
            if ecls == Kernel.KernelEffectStore then
                local ok, reason = lane_supported(effect.dst)
                if not ok then rejects[#rejects + 1] = reject_memory(reason) end
                ok, reason = value_expr_supported(effect.index)
                if not ok then rejects[#rejects + 1] = reject_algebra(reason) end
                ok, reason = kernel_expr_supported(effect.value)
                if not ok then rejects[#rejects + 1] = reject_algebra(reason) end
            elseif ecls == Kernel.KernelEffectFold then
                -- folds are executable only via Reduction/ClosedForm-specific emitters.
            elseif ecls == Kernel.KernelEffectCall then
                rejects[#rejects + 1] = reject_target("kernel call effects do not have an emitter")
            else
                rejects[#rejects + 1] = reject_target("unsupported KernelEffect " .. class_name(effect))
            end
        end
        return rejects
    end

    local function binding_code_key(binding)
        local text = binding and binding.id and binding.id.text or ""
        return text:match("^kval:(.+)$")
    end

    local function loop_variant_values(body, flow)
        local out = {}
        if body == nil or asdl.classof(body.domain) ~= Kernel.KernelDomainFlow then return out end
        if body.domain.counter ~= nil then out[body.domain.counter.text] = true end
        local domain = body.domain.domain
        if asdl.classof(domain) ~= Flow.FlowDomainLoop then return out end
        local loop_id = domain.loop
        local body_blocks = {}
        for _, loop in ipairs(flow and flow.loops or {}) do
            if loop.loop == loop_id then
                for _, induction in ipairs(loop.inductions or {}) do out[induction.value.text] = true end
                for _, ref in ipairs(loop.body_blocks or {}) do body_blocks[ref.block.text] = true end
                break
            end
        end
        for _, edge_fact in ipairs(flow and flow.edges or {}) do
            local edge = edge_fact.edge
            if edge ~= nil and body_blocks[edge.from.block.text] and body_blocks[edge.to.block.text] then
                for _, arg in ipairs(edge_fact.args or {}) do
                    out[arg.dst_param.text] = true
                end
            end
        end
        return out
    end

    local function vector_value_expr_supported(expr, binding_by_code, variant_by_code, seen)
        if expr == nil then return false, "missing vector ValueExpr" end
        seen = seen or {}
        if seen[expr] then return true end
        seen[expr] = true
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprConst then return true end
        if cls == Value.ValueExprValue then
            if binding_by_code[expr.value.text] ~= nil then return true end
            if variant_by_code[expr.value.text] then
                return false, "vector expression references non-vector loop value " .. expr.value.text
            end
            return true
        end
        if cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul then
            local ok, reason = vector_value_expr_supported(expr.a, binding_by_code, variant_by_code, seen); if not ok then return false, reason end
            return vector_value_expr_supported(expr.b, binding_by_code, variant_by_code, seen)
        end
        if cls == Value.ValueExprBinary then
            return false, "Back vector emission does not support generic binary expression " .. tostring(expr.op)
        end
        if cls == Value.ValueExprCmp then
            local info = ReductionAlgebra.type_info(expr.ty)
            if info.class == "float" then return false, "Back has no vector float compare" end
            local ok, reason = vector_value_expr_supported(expr.a, binding_by_code, variant_by_code, seen); if not ok then return false, reason end
            return vector_value_expr_supported(expr.b, binding_by_code, variant_by_code, seen)
        end
        if cls == Value.ValueExprSelect then
            local ok, reason = vector_value_expr_supported(expr.cond, binding_by_code, variant_by_code, seen); if not ok then return false, reason end
            ok, reason = vector_value_expr_supported(expr.t, binding_by_code, variant_by_code, seen); if not ok then return false, reason end
            return vector_value_expr_supported(expr.f, binding_by_code, variant_by_code, seen)
        end
        return false, "vector emitter does not support " .. class_name(expr)
    end

    local function vector_kernel_expr_supported(expr, binding_by_id, binding_by_code, variant_by_code, seen)
        if expr == nil then return false, "missing vector KernelExpr" end
        seen = seen or {}
        local cls = asdl.classof(expr)
        if cls == Kernel.KernelExprLaneLoad then return true end
        if cls == Kernel.KernelExprAlgebra then return vector_value_expr_supported(expr.expr, binding_by_code, variant_by_code, seen) end
        if cls == Kernel.KernelExprKernelValue then
            local binding = binding_by_id[expr.value.text]
            if binding == nil then return false, "vector KernelExpr references missing binding" end
            if seen[binding] then return true end
            seen[binding] = true
            return vector_kernel_expr_supported(binding.expr, binding_by_id, binding_by_code, variant_by_code, seen)
        end
        return false, "vector emitter does not support " .. class_name(expr)
    end

    local function classify(plan, schedule_kind, target, flow)
        local rejects = base_rejects(plan)
        local body = plan and plan.body or nil
        local result = body and body.result or nil
        local kind_name = schedule_kind_name(schedule_kind)
        if kind_name == nil then
            if asdl.classof(result) == Kernel.KernelResultClosedForm then kind_name = "closed_form"
            elseif #(body and body.lanes or {}) > 0 then kind_name = "scalar_index"
            else kind_name = "scalar_index" end
        end
        if kind_name == "closed_form" then
            if asdl.classof(result) ~= Kernel.KernelResultClosedForm then
                rejects[#rejects + 1] = reject_algebra("closed-form schedule requires KernelResultClosedForm")
            else
                local ok, reason = value_expr_supported(result.closed_form.expr)
                if not ok then rejects[#rejects + 1] = reject_algebra(reason) end
            end
            if #(body and body.lanes or {}) > 0 then rejects[#rejects + 1] = reject_target("closed-form emitter only supports scalar control/result replacement, not lane stores") end
        elseif kind_name == "scalar_index" or kind_name == "scalar_pointer" then
            if asdl.classof(result) == Kernel.KernelResultClosedForm then rejects[#rejects + 1] = reject_algebra("closed-form result must use ScheduleClosedForm") end
            if body and body.domain and body.domain.counter == nil then rejects[#rejects + 1] = reject_algebra("scalar kernel requires loop counter") end
            if #(body and body.effects or {}) == 0 and asdl.classof(result) == Kernel.KernelResultOriginalControl then rejects[#rejects + 1] = reject_profit("scalar kernel has no executable effects/result") end
        elseif kind_name == "vector_contiguous" then
            local sk = asdl.classof(schedule_kind) == Schedule.ScheduleVector and schedule_kind or nil
            if sk == nil or asdl.classof(sk.lanes) ~= Schedule.LaneVector then
                rejects[#rejects + 1] = reject_target("vector schedule requires LaneVector")
            elseif not target_supports_vector(target, sk.lanes.elem_ty, sk.lanes.lanes) then
                rejects[#rejects + 1] = reject_target("target lacks requested vector shape")
            end
            for _, lane in ipairs(body and body.lanes or {}) do
                if lane.pattern ~= Mem.MemAccessContiguous then rejects[#rejects + 1] = reject_memory("vector emitter only supports contiguous lanes") end
            end
            if asdl.classof(result) == Kernel.KernelResultClosedForm then rejects[#rejects + 1] = reject_target("closed-form results must use ScheduleClosedForm") end
            if asdl.classof(result) == Kernel.KernelResultReduction then
                if sk ~= nil and sk.tail ~= Schedule.TailScalar then rejects[#rejects + 1] = reject_target("vector reductions require TailScalar") end
                local ok, reason = ReductionAlgebra.vector_support(result.reduction, sk and sk.lanes and sk.lanes.elem_ty or nil)
                if not ok then rejects[#rejects + 1] = reject_algebra(reason) end
            end
            local binding_by_id, binding_by_code = {}, {}
            for _, binding in ipairs(body and body.bindings or {}) do
                binding_by_id[binding.id.text] = binding
                local code_key = binding_code_key(binding)
                if code_key ~= nil then binding_by_code[code_key] = binding end
            end
            local variant_by_code = loop_variant_values(body, flow)
            for _, effect in ipairs(body and body.effects or {}) do
                if asdl.classof(effect) == Kernel.KernelEffectStore then
                    local ok, reason = vector_kernel_expr_supported(effect.value, binding_by_id, binding_by_code, variant_by_code)
                    if not ok then rejects[#rejects + 1] = reject_target(reason) end
                elseif asdl.classof(effect) == Kernel.KernelEffectFold then
                    if sk ~= nil and sk.tail ~= Schedule.TailScalar then rejects[#rejects + 1] = reject_target("vector reductions require TailScalar") end
                    local ok, reason = ReductionAlgebra.vector_support(effect.reduction, sk and sk.lanes and sk.lanes.elem_ty or nil)
                    if not ok then rejects[#rejects + 1] = reject_algebra(reason) end
                    ok, reason = vector_value_expr_supported(effect.reduction.contribution, binding_by_code, variant_by_code)
                    if not ok then rejects[#rejects + 1] = reject_algebra(reason) end
                else
                    rejects[#rejects + 1] = reject_target("vector emitter only supports store effects")
                end
            end
        else
            rejects[#rejects + 1] = reject_target("unknown schedule kind " .. tostring(kind_name))
        end
        return Schedule.ScheduleEmitterCapability(
            kind_name,
            #rejects == 0,
            #rejects == 0 and "supported by current semantic emitters"
                or ("unsupported by current semantic emitters: " .. summarize_rejects(rejects)),
            rejects
        )
    end

    api.classify = classify
    api.value_expr_supported = value_expr_supported
    api.kernel_expr_supported = kernel_expr_supported
    api.lane_supported = lane_supported

    T._lalin_api_cache.kernel_emit_support = api
    return api
end

return bind_context
