local schema = require("lalin.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function bind_context(T)
    local Tr = T.LalinTree
    local B = T.LalinBind

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
            if base == nil or len == nil then return single(reject("bounds")) end
            return single(Tr.ContractFactBounds(base, len))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractWindowBounds) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return single(reject("window_bounds")) end
            return single(Tr.ContractFactWindowBounds(base, self.base_len, self.start, self.len))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractDisjoint) then
            return (function(self)

            local a, b = expr_binding(self.a), expr_binding(self.b)
            if a == nil or b == nil then return single(reject("disjoint")) end
            return single(Tr.ContractFactDisjoint(a, b))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractSameLen) then
            return (function(self)

            local a, b = expr_binding(self.a), expr_binding(self.b)
            if a == nil or b == nil then return single(reject("same_len")) end
            return single(Tr.ContractFactSameLen(a, b))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractSoAComponent) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return single(reject("soa_component")) end
            return single(Tr.ContractFactSoAComponent(base, self.record_ty, self.field_name, self.component_index))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractNoAlias) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return single(reject("noalias")) end
            return single(Tr.ContractFactNoAlias(base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractReadonly) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return single(reject("readonly")) end
            return single(Tr.ContractFactReadonly(base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractWriteonly) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return single(reject("writeonly")) end
            return single(Tr.ContractFactWriteonly(base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractInvalidate) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return single(reject("invalidate")) end
            return single(Tr.ContractFactInvalidate(base))
            end)(node, ...)
        elseif schema.isa(node, Tr.ContractPreserve) then
            return (function(self)

            local base = expr_binding(self.base)
            if base == nil then return single(reject("preserve")) end
            return single(Tr.ContractFactPreserve(base))
            end)(node, ...)
        else
            error("phase lalin_tree_contract_fact: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    local function facts_from_contracts(contracts)
        local facts = {}
        for i = 1, #contracts do facts[#facts + 1] = only(contract_fact(contracts[i])) end
        return Tr.ContractFactSet(facts)
    end

    function func_facts(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.FuncLocal) then
            return (function()
 return single(Tr.ContractFactSet({}))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExport) then
            return (function()
 return single(Tr.ContractFactSet({}))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncLocalContract) then
            return (function(self)
 return single(facts_from_contracts(self.contracts))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncExportContract) then
            return (function(self)
 return single(facts_from_contracts(self.contracts))
            end)(node, ...)
        elseif schema.isa(node, Tr.FuncOpen) then
            return (function()
 return single(Tr.ContractFactSet({}))
            end)(node, ...)
        else
            error("phase lalin_tree_func_contract_facts: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
        end
    end

    return {
        contract_fact = contract_fact,
        func_facts = func_facts,
        facts = function(func) return only(func_facts(func)) end,
    }
end

return bind_context
