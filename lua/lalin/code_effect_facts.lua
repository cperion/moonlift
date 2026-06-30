local asdl = require("lalin.asdl")

local function class_name(x)
    local cls = asdl.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_effect_facts ~= nil then return T._lalin_api_cache.code_effect_facts end

    local Code = T.LalinCode
    local Mem = T.LalinMem
    local Effect = T.LalinEffect
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)

    local api = {}

    local function access_id_text(func, block, inst)
        local function sanitize(s)
            s = tostring(s or "x"):gsub("[^%w_]", "_")
            if s:match("^%d") then s = "_" .. s end
            if s == "" then s = "x" end
            return s
        end
        return "access:" .. sanitize(func.name) .. ":" .. sanitize(block.id.text) .. ":" .. sanitize(inst.id.text)
    end

    local function contract_facts(contracts)
        if contracts == nil then return {} end
        if asdl.classof(contracts) == Code.CodeContractFactSet then return contracts.facts or {} end
        return contracts
    end

    local function contract_entry_effects(contracts)
        local out = {}
        for _, f in ipairs(contract_facts(contracts)) do
            local k = f.fact
            local cls = asdl.classof(k)
            local effects = out[f.func.text]
            if effects == nil then effects = {}; out[f.func.text] = effects end
            local proof = Mem.MemProofContract(f, "contract normalized into explicit effect fact")
            if cls == Code.CodeContractReadonly then
                effects[#effects + 1] = Effect.EffectRead(Effect.EffectObjectStore(k.base), proof)
                effects[#effects + 1] = Effect.EffectNoEscape(k.base, "readonly contract value does not escape through writes")
            elseif cls == Code.CodeContractWriteonly then
                effects[#effects + 1] = Effect.EffectWrite(Effect.EffectObjectStore(k.base), proof)
            elseif cls == Code.CodeContractNoAlias then
                effects[#effects + 1] = Effect.EffectNoEscape(k.base, "noalias/noescape contract boundary")
            elseif cls == Code.CodeContractInvalidate then
                effects[#effects + 1] = Effect.EffectInvalidate(Effect.EffectObjectStore(k.base), "invalidate contract boundary")
            elseif cls == Code.CodeContractPreserve then
                effects[#effects + 1] = Effect.EffectRetain(k.base, "preserve contract boundary")
            elseif cls == Code.CodeContractRejected then
                effects[#effects + 1] = Effect.EffectUnknown(k.reason)
            end
        end
        return out
    end

    local function pure_internal_functions(module)
        local pure = {}
        for _, func in ipairs(module.funcs or {}) do
            local ok = true
            for _, block in ipairs(func.blocks or {}) do
                for _, inst in ipairs(block.insts or {}) do
                    local cls = asdl.classof(inst.op)
                    if cls == Code.CodeInstLoad or cls == Code.CodeInstStore or cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicStore
                        or cls == Code.CodeInstAtomicRmw or cls == Code.CodeInstAtomicCas or cls == Code.CodeInstAtomicFence or cls == Code.CodeInstCall then
                        ok = false
                    end
                end
                local tcls = asdl.classof(block.term and block.term.op or nil)
                if tcls == Code.CodeTermTrap or tcls == Code.CodeTermUnreachable then ok = false end
            end
            if ok then pure[func.id.text] = true end
        end
        return pure
    end

    local function call_summary(module, target, contracts, pure_funcs)
        local cls = asdl.classof(target)
        if cls == Code.CodeCallDirect then
            if pure_funcs and pure_funcs[target.func.text] then
                return Effect.CallSummary(target.func, nil, { Effect.EffectNoTrap("direct internal callee has no memory/call/trap effects") })
            end
            return Effect.CallSummary(target.func, nil, { Effect.EffectUnknown("direct call effects require callee summary") })
        elseif cls == Code.CodeCallExtern then
            local name = target["extern"].text
            for _, ext in ipairs(module.externs or {}) do if ext.id == target["extern"] then name = ext.symbol or ext.name or name end end
            return Effect.CallSummary(nil, name, { Effect.EffectUnknown("extern call has unknown effects without a contract summary") })
        elseif cls == Code.CodeCallIndirect then
            return Effect.CallSummary(nil, nil, { Effect.EffectUnknown("indirect call target is unknown") })
        elseif cls == Code.CodeCallClosure then
            return Effect.CallSummary(nil, nil, { Effect.EffectUnknown("closure call target is unknown") })
        end
        return Effect.CallSummary(nil, nil, { Effect.EffectUnknown("unsupported call target " .. class_name(target)) })
    end

    local function inst_effects(module, mem, contracts)
        local mem_projection = CodeMemFacts.access_projection(mem)
        local pure_funcs = pure_internal_functions(module)
        local insts, calls = {}, {}
        for _, func in ipairs(module.funcs or {}) do
            for _, block in ipairs(func.blocks or {}) do
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.op
                    local cls = asdl.classof(k)
                    local effects = {}
                    if cls == Code.CodeInstLoad or cls == Code.CodeInstStore or cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicStore or cls == Code.CodeInstAtomicRmw or cls == Code.CodeInstAtomicCas then
                        local aid = access_id_text(func, block, inst)
                        local obj = mem_projection:object_for_access(aid)
                        local proof = mem_projection:proof_for_access(aid)
                        local eobj = obj and Effect.EffectObjectMem(obj) or Effect.EffectObjectUnknown("memory access object is unknown")
                        if cls == Code.CodeInstLoad or cls == Code.CodeInstAtomicLoad then effects[#effects + 1] = Effect.EffectRead(eobj, proof) end
                        if cls == Code.CodeInstStore or cls == Code.CodeInstAtomicStore then effects[#effects + 1] = Effect.EffectWrite(eobj, proof) end
                        if cls == Code.CodeInstAtomicRmw or cls == Code.CodeInstAtomicCas then
                            effects[#effects + 1] = Effect.EffectRead(eobj, proof)
                            effects[#effects + 1] = Effect.EffectWrite(eobj, proof)
                        end
                        local backend = mem_projection:backend_for_access(aid)
                        if backend ~= nil and asdl.classof(backend.trap) == Mem.MemNonTrapping then
                            effects[#effects + 1] = Effect.EffectNoTrap(backend.trap.reason or "memory backend info proves non-trapping")
                        elseif k.access.trap == Code.CodeMustNotTrap then
                            effects[#effects + 1] = Effect.EffectNoTrap("Code memory access is marked must-not-trap")
                        else
                            effects[#effects + 1] = Effect.EffectMayTrap("memory access may trap")
                        end
                        if k.access.volatile then effects[#effects + 1] = Effect.EffectVolatile("volatile memory access") end
                        if cls == Code.CodeInstAtomicLoad or cls == Code.CodeInstAtomicStore or cls == Code.CodeInstAtomicRmw or cls == Code.CodeInstAtomicCas then effects[#effects + 1] = Effect.EffectAtomic(tostring(k.ordering or k.access.ordering or "atomic")) end
                    elseif cls == Code.CodeInstCall then
                        local summary = call_summary(module, k.target, contracts, pure_funcs)
                        calls[#calls + 1] = summary
                        for _, eff in ipairs(summary.effects or {}) do effects[#effects + 1] = eff end
                    elseif cls == Code.CodeInstAtomicFence then
                        effects[#effects + 1] = Effect.EffectAtomic(tostring(k.ordering or "fence"))
                    end
                    if #effects > 0 then insts[#insts + 1] = Effect.InstEffect(inst.id, effects) end
                end
            end
        end
        return calls, insts
    end

    local function term_effects(module, contracts)
        local terms = {}
        local entry_effects = contract_entry_effects(contracts)
        for _, func in ipairs(module.funcs or {}) do
            local effects = entry_effects[func.id.text]
            if effects ~= nil and #effects > 0 then terms[#terms + 1] = Effect.TermEffect(func.entry, effects) end
            for _, block in ipairs(func.blocks or {}) do
                local term = block.term and block.term.op or nil
                local cls = asdl.classof(term)
                if cls == Code.CodeTermTrap then
                    terms[#terms + 1] = Effect.TermEffect(block.id, { Effect.EffectMayTrap(term.reason or "explicit trap terminator") })
                elseif cls == Code.CodeTermUnreachable then
                    terms[#terms + 1] = Effect.TermEffect(block.id, { Effect.EffectUnknown(term.reason or "unreachable terminator") })
                end
            end
        end
        return terms
    end

    local function facts(module, graph, mem, contracts)
        graph = graph or CodeGraph.graph(module)
        local flow = CodeFlowFacts.facts(module, graph)
        local value = CodeValueFacts.facts(module, graph, flow)
        mem = mem or CodeMemFacts.semantic_facts(module, graph, flow, value, contracts)
        local calls, insts = inst_effects(module, mem, contracts)
        return Effect.EffectFactSet(module.id, calls, insts, term_effects(module, contracts))
    end

    api.facts = facts
    api.module = facts

    T._lalin_api_cache.code_effect_facts = api
    return api
end

return bind_context
