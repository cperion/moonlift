local M = {}

function M.Define(T)
    local V = T.Moon2Vec
    assert(V, "moonlift.vec_inspect.Define expects moonlift.asdl in the context")

    local function decision(decision)
        return V.VecScheduleInspection(decision.facts.loop, decision.legality, decision.schedule, decision.considered)
    end

    local function decisions(decisions)
        local out = {}
        for i = 1, #(decisions or {}) do out[#out + 1] = decision(decisions[i]) end
        return V.VecInspectionReport(out)
    end

    return {
        decision = decision,
        decisions = decisions,
    }
end

return M
