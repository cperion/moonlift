local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local M = {}

function M.Define(T)
    local Tr = T.MoonTree
    local B = T.MoonBind

    local contract_fact
    local func_facts

    local function append_all(out, xs) for i = 1, #xs do out[#out + 1] = xs[i] end end

    local function expr_binding(expr)
        if schema.classof(expr) == Tr.ExprRef and schema.classof(expr.ref) == B.ValueRefBinding then return expr.ref.binding end
        return nil
    end

    local function reject(name)
        return Tr.ContractFactRejected(Tr.TypeIssueUnresolvedValue(name or "<contract>"))
    end

    function contract_fact(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.ContractBounds) then
            return (function(self)

            local base, len = expr_binding(self.base), expr_binding(self.len)
            if base == nil or len == nil then return erased.once(reject("bounds")) end
            return erased.once(Tr.ContractFactBounds(base, len))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractWindowBounds) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return erased.once(reject("window_bounds")) end
            return erased.once(Tr.ContractFactWindowBounds(base, self.base_len, self.start, self.len))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractDisjoint) then
            return (function(self)

            local a, b = expr_binding(self.a), expr_binding(self.b)
            if a == nil or b == nil then return erased.once(reject("disjoint")) end
            return erased.once(Tr.ContractFactDisjoint(a, b))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractSameLen) then
            return (function(self)

            local a, b = expr_binding(self.a), expr_binding(self.b)
            if a == nil or b == nil then return erased.once(reject("same_len")) end
            return erased.once(Tr.ContractFactSameLen(a, b))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractNoAlias) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return erased.once(reject("noalias")) end
            return erased.once(Tr.ContractFactNoAlias(base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractReadonly) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return erased.once(reject("readonly")) end
            return erased.once(Tr.ContractFactReadonly(base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractWriteonly) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return erased.once(reject("writeonly")) end
            return erased.once(Tr.ContractFactWriteonly(base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractInvalidate) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return erased.once(reject("invalidate")) end
            return erased.once(Tr.ContractFactInvalidate(base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractPreserve) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return erased.once(reject("preserve")) end
            return erased.once(Tr.ContractFactPreserve(base))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_contract_fact: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function facts_from_contracts(contracts)
        local facts = {}
        for i = 1, #contracts do facts[#facts + 1] = erased.one(contract_fact(contracts[i])) end
        return Tr.ContractFactSet(facts)
    end

    function func_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.FuncLocal) then
            return (function()
 return erased.once(Tr.ContractFactSet({}))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExport) then
            return (function()
 return erased.once(Tr.ContractFactSet({}))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncLocalContract) then
            return (function(self)
 return erased.once(facts_from_contracts(self.contracts))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExportContract) then
            return (function(self)
 return erased.once(facts_from_contracts(self.contracts))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncOpen) then
            return (function()
 return erased.once(Tr.ContractFactSet({}))
            end)(node, ...)
        else
            error("erased phase moonlift_tree_func_contract_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        contract_fact = contract_fact,
        func_facts = func_facts,
        facts = function(func) return erased.one(func_facts(func)) end,
    }
end

return M
