local pvm = require("moonlift.pvm")

local M = {}

local function append_all(out, xs)
    for i = 1, #xs do out[#out + 1] = xs[i] end
end

function M.Define(T)
    local C = (T.MoonCore or T.Moon2Core)
    local Ty = (T.MoonType or T.Moon2Type)
    local V = (T.MoonVec or T.Moon2Vec)

    local scalar_elem
    local elem_bits
    local target_vector_bits
    local target_supports_shape
    local facts_elem
    local memory_rejects
    local dependence_rejects
    local decide_loop

    scalar_elem = pvm.phase("moon2_vec_scalar_elem", {
        [C.ScalarBool] = function() return pvm.once(V.VecElemBool) end,
        [C.ScalarI8] = function() return pvm.once(V.VecElemI8) end,
        [C.ScalarI16] = function() return pvm.once(V.VecElemI16) end,
        [C.ScalarI32] = function() return pvm.once(V.VecElemI32) end,
        [C.ScalarI64] = function() return pvm.once(V.VecElemI64) end,
        [C.ScalarU8] = function() return pvm.once(V.VecElemU8) end,
        [C.ScalarU16] = function() return pvm.once(V.VecElemU16) end,
        [C.ScalarU32] = function() return pvm.once(V.VecElemU32) end,
        [C.ScalarU64] = function() return pvm.once(V.VecElemU64) end,
        [C.ScalarF32] = function() return pvm.once(V.VecElemF32) end,
        [C.ScalarF64] = function() return pvm.once(V.VecElemF64) end,
        [C.ScalarRawPtr] = function() return pvm.once(V.VecElemPtr) end,
        [C.ScalarIndex] = function() return pvm.once(V.VecElemIndex) end,
        [C.ScalarVoid] = function() return pvm.empty() end,
    })

    elem_bits = pvm.phase("moon2_vec_elem_bits", {
        [V.VecElemBool] = function() return pvm.once(1) end,
        [V.VecElemI8] = function() return pvm.once(8) end,
        [V.VecElemU8] = function() return pvm.once(8) end,
        [V.VecElemI16] = function() return pvm.once(16) end,
        [V.VecElemU16] = function() return pvm.once(16) end,
        [V.VecElemI32] = function() return pvm.once(32) end,
        [V.VecElemU32] = function() return pvm.once(32) end,
        [V.VecElemF32] = function() return pvm.once(32) end,
        [V.VecElemI64] = function() return pvm.once(64) end,
        [V.VecElemU64] = function() return pvm.once(64) end,
        [V.VecElemF64] = function() return pvm.once(64) end,
        [V.VecElemPtr] = function() return pvm.once(64) end,
        [V.VecElemIndex] = function() return pvm.once(64) end,
    })

    target_vector_bits = pvm.phase("moon2_vec_target_vector_bits", {
        [V.VecTargetModel] = function(model)
            for i = 1, #model.facts do
                local fact = model.facts[i]
                if pvm.classof(fact) == V.VecTargetVectorBits then return pvm.once(fact.bits) end
            end
            return pvm.once(128)
        end,
    })

    target_supports_shape = pvm.phase("moon2_vec_target_supports_shape", {
        [V.VecTargetModel] = function(model, shape)
            for i = 1, #model.facts do
                local fact = model.facts[i]
                if pvm.classof(fact) == V.VecTargetSupportsShape and fact.shape == shape then return pvm.once(true) end
            end
            return pvm.once(false)
        end,
    }, { args_cache = "last" })

    memory_rejects = pvm.phase("moon2_vec_memory_rejects", {
        [V.VecMemoryAccess] = function(self)
            if self.pattern == V.VecAccessContiguous then return pvm.empty() end
            local pattern = pvm.classof(self.pattern)
            if pattern == V.VecAccessStrided then return pvm.once(V.VecRejectUnsupportedMemory(self.id, "strided memory access requires gather/scatter or a stride-specific vector lowering")) end
            if self.pattern == V.VecAccessGather then return pvm.once(V.VecRejectUnsupportedMemory(self.id, "gather memory access is not supported by the current vector backend")) end
            if self.pattern == V.VecAccessScatter then return pvm.once(V.VecRejectUnsupportedMemory(self.id, "scatter memory access is not supported by the current vector backend")) end
            return pvm.once(V.VecRejectUnsupportedMemory(self.id, "memory access pattern is unknown"))
        end,
    })

    dependence_rejects = pvm.phase("moon2_vec_dependence_rejects", {
        [V.VecNoDependence] = function() return pvm.empty() end,
        [V.VecDependenceUnknown] = function(self) return pvm.once(self.reject) end,
        [V.VecLoopCarriedDependence] = function(self) return pvm.once(self.reject) end,
    })

    facts_elem = pvm.phase("moon2_vec_facts_elem", {
        [V.VecLoopFacts] = function(facts)
            if #facts.reductions > 0 then
                local ty = facts.reductions[1].accumulator.ty
                if pvm.classof(ty) == Ty.TScalar then return scalar_elem(ty.scalar) end
            end
            if #facts.inductions > 0 then
                local ty = facts.inductions[1].binding.ty
                if pvm.classof(ty) == Ty.TScalar then return scalar_elem(ty.scalar) end
            end
            return pvm.empty()
        end,
    })

    decide_loop = pvm.phase("moon2_vec_loop_decide", {
        [V.VecLoopFacts] = function(facts, target)
            local rejects = {}
            for i = 1, #facts.rejects do rejects[#rejects + 1] = facts.rejects[i] end
            for i = 1, #facts.memory do append_all(rejects, pvm.drain(memory_rejects(facts.memory[i]))) end
            for i = 1, #facts.dependences do append_all(rejects, pvm.drain(dependence_rejects(facts.dependences[i]))) end
            if #rejects > 0 then
                local chosen = V.VecLoopScalar(facts.loop, rejects)
                return pvm.once(V.VecLoopDecision(facts, V.VecIllegal(rejects), V.VecScheduleScalar(rejects), chosen, { V.VecShapeScore(chosen, 1, 0, "existing rejects") }))
            end
            local elem = pvm.drain(facts_elem(facts))[1]
            if elem == nil then
                local reject = V.VecRejectUnsupportedLoop(facts.loop, "no scalar element type for loop")
                local rejects2 = { reject }
                local chosen = V.VecLoopScalar(facts.loop, rejects2)
                return pvm.once(V.VecLoopDecision(facts, V.VecIllegal(rejects2), V.VecScheduleScalar(rejects2), chosen, { V.VecShapeScore(chosen, 1, 0, "missing element") }))
            end
            local bits = pvm.one(target_vector_bits(target))
            local ebits = pvm.one(elem_bits(elem))
            local lanes = math.floor(bits / ebits)
            if lanes < 2 then lanes = 2 end
            local shape = V.VecVectorShape(elem, lanes)
            if not pvm.one(target_supports_shape(target, shape)) then
                local reject = V.VecRejectTarget(shape, "target does not advertise shape")
                local rejects2 = { reject }
                local chosen = V.VecLoopScalar(facts.loop, rejects2)
                return pvm.once(V.VecLoopDecision(facts, V.VecIllegal(rejects2), V.VecScheduleScalar(rejects2), chosen, { V.VecShapeScore(chosen, 1, 0, "target reject") }))
            end
            local proof = V.VecProofDomain("counted domain")
            local proofs = { proof }
            local tail = V.VecTailScalar
            local chosen = V.VecLoopVector(facts.loop, shape, 1, tail, proofs)
            local schedule = V.VecScheduleVector(shape, 1, 1, tail, 1, {}, proofs)
            return pvm.once(V.VecLoopDecision(facts, V.VecLegal(proofs), schedule, chosen, { V.VecShapeScore(chosen, lanes, 100, "supported counted vector loop") }))
        end,
    }, { args_cache = "last" })

    return {
        scalar_elem = scalar_elem,
        elem_bits = elem_bits,
        facts_elem = facts_elem,
        memory_rejects = memory_rejects,
        decide_loop = decide_loop,
        decide = function(facts, target) return pvm.one(decide_loop(facts, target)) end,
    }
end

return M
