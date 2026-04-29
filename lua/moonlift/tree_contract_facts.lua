local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local Tr = T.MoonTree
    local B = T.MoonBind

    local contract_fact
    local func_facts

    local function append_all(out, xs) for i = 1, #xs do out[#out + 1] = xs[i] end end

    local function expr_binding(expr)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefBinding then return expr.ref.binding end
        return nil
    end

    local function reject(name)
        return Tr.ContractFactRejected(Tr.TypeIssueUnresolvedValue(name or "<contract>"))
    end

    contract_fact = pvm.phase("moon2_tree_contract_fact", {
        [Tr.ContractBounds] = function(self)
            local base, len = expr_binding(self.base), expr_binding(self.len)
            if base == nil or len == nil then return pvm.once(reject("bounds")) end
            return pvm.once(Tr.ContractFactBounds(base, len))
        end,
        [Tr.ContractWindowBounds] = function(self)
            local base = expr_binding(self.base)
            if base == nil then return pvm.once(reject("window_bounds")) end
            return pvm.once(Tr.ContractFactWindowBounds(base, self.base_len, self.start, self.len))
        end,
        [Tr.ContractDisjoint] = function(self)
            local a, b = expr_binding(self.a), expr_binding(self.b)
            if a == nil or b == nil then return pvm.once(reject("disjoint")) end
            return pvm.once(Tr.ContractFactDisjoint(a, b))
        end,
        [Tr.ContractSameLen] = function(self)
            local a, b = expr_binding(self.a), expr_binding(self.b)
            if a == nil or b == nil then return pvm.once(reject("same_len")) end
            return pvm.once(Tr.ContractFactSameLen(a, b))
        end,
        [Tr.ContractNoAlias] = function(self)
            local base = expr_binding(self.base)
            if base == nil then return pvm.once(reject("noalias")) end
            return pvm.once(Tr.ContractFactNoAlias(base))
        end,
        [Tr.ContractReadonly] = function(self)
            local base = expr_binding(self.base)
            if base == nil then return pvm.once(reject("readonly")) end
            return pvm.once(Tr.ContractFactReadonly(base))
        end,
        [Tr.ContractWriteonly] = function(self)
            local base = expr_binding(self.base)
            if base == nil then return pvm.once(reject("writeonly")) end
            return pvm.once(Tr.ContractFactWriteonly(base))
        end,
    })

    local function facts_from_contracts(contracts)
        local facts = {}
        for i = 1, #contracts do facts[#facts + 1] = pvm.one(contract_fact(contracts[i])) end
        return Tr.ContractFactSet(facts)
    end

    func_facts = pvm.phase("moon2_tree_func_contract_facts", {
        [Tr.FuncLocal] = function() return pvm.once(Tr.ContractFactSet({})) end,
        [Tr.FuncExport] = function() return pvm.once(Tr.ContractFactSet({})) end,
        [Tr.FuncLocalContract] = function(self) return pvm.once(facts_from_contracts(self.contracts)) end,
        [Tr.FuncExportContract] = function(self) return pvm.once(facts_from_contracts(self.contracts)) end,
        [Tr.FuncOpen] = function() return pvm.once(Tr.ContractFactSet({})) end,
    })

    return {
        contract_fact = contract_fact,
        func_facts = func_facts,
        facts = function(func) return pvm.one(func_facts(func)) end,
    }
end

return M
