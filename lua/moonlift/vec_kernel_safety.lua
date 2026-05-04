local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local V = T.MoonVec
    local B = T.MoonBind
    local Tr = T.MoonTree
    local Ty = T.MoonType
    local C = T.MoonCore

    local expr_uses
    local mask_uses
    local core_uses
    local window_range_decide
    local decide_input
    local contract_same_len

    local function append_all(out, xs)
        for i = 1, #xs do out[#out + 1] = xs[i] end
    end

    local function same_binding_slot(a, b)
        if a == b then return true end
        if a == nil or b == nil or a.name ~= b.name then return false end
        local ca, cb = pvm.classof(a.class), pvm.classof(b.class)
        if ca == B.BindingClassArg and cb == B.BindingClassArg then return a.class.index == b.class.index end
        if ca == B.BindingClassEntryBlockParam and cb == B.BindingClassEntryBlockParam then return a.class.region_id == b.class.region_id and a.class.block_name == b.class.block_name and a.class.index == b.class.index end
        if ca == B.BindingClassBlockParam and cb == B.BindingClassBlockParam then return a.class.region_id == b.class.region_id and a.class.block_name == b.class.block_name and a.class.index == b.class.index end
        return false
    end

    local function expr_binding(expr)
        local Tr = T.MoonTree
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefBinding then return expr.ref.binding end
        return nil
    end

    local function view_base_binding(view)
        local Tr = T.MoonTree
        local cls = pvm.classof(view)
        if cls == Tr.ViewFromExpr then return expr_binding(view.base) end
        if cls == Tr.ViewContiguous then return expr_binding(view.data) end
        return nil
    end

    local function memory_base_binding(base)
        local Tr = T.MoonTree
        local cls = pvm.classof(base)
        if cls == V.VecMemoryBaseRawAddr then return expr_binding(base.addr) end
        if cls == V.VecMemoryBaseView then return view_base_binding(base.view) end
        if cls == V.VecMemoryBasePlace and pvm.classof(base.place) == Tr.PlaceRef and pvm.classof(base.place.ref) == B.ValueRefBinding then return base.place.ref.binding end
        return nil
    end

    local function literal_int_raw(expr)
        if pvm.classof(expr) == Tr.ExprLit and pvm.classof(expr.value) == C.LitInt then return expr.value.raw end
        return nil
    end

    local function offset_is_zero(offset)
        if offset == nil or offset == V.VecKernelOffsetZero then return true end
        if pvm.classof(offset) == V.VecKernelOffsetExpr and literal_int_raw(offset.expr) == "0" then return true end
        return false
    end

    local function scalar_alias_for_binding(scalars, binding)
        for i = 1, #(scalars or {}) do if same_binding_slot(scalars[i].binding, binding) then return scalars[i] end end
        return nil
    end

    local function resolve_scalar_expr(expr, scalars, depth)
        depth = depth or 0
        if depth > 16 then return expr end
        local binding = expr_binding(expr)
        if binding ~= nil then
            local alias = scalar_alias_for_binding(scalars, binding)
            if alias ~= nil then return resolve_scalar_expr(alias.value, scalars, depth + 1) end
        end
        if pvm.classof(expr) == Tr.ExprBinary then
            local lhs = resolve_scalar_expr(expr.lhs, scalars, depth + 1)
            local rhs = resolve_scalar_expr(expr.rhs, scalars, depth + 1)
            if lhs ~= expr.lhs or rhs ~= expr.rhs then return Tr.ExprBinary(expr.h, expr.op, lhs, rhs) end
        end
        return expr
    end

    local function offset_expr(offset)
        if pvm.classof(offset) == V.VecKernelOffsetExpr then return offset.expr end
        return nil
    end

    local function offset_expr_resolved(offset, scalars)
        local expr = offset_expr(offset)
        if expr == nil then return nil end
        return resolve_scalar_expr(expr, scalars)
    end

    local function const_int_expr(expr, scalars)
        expr = resolve_scalar_expr(expr, scalars)
        local raw = literal_int_raw(expr)
        if raw ~= nil then return tonumber(raw) end
        return nil
    end

    local function offset_literal(offset, scalars)
        if offset == nil or offset == V.VecKernelOffsetZero then return 0 end
        local cls = pvm.classof(offset)
        if cls == V.VecKernelOffsetExpr then return const_int_expr(offset.expr, scalars) end
        if cls == V.VecKernelOffsetAdd then
            local a = offset_literal(offset.lhs, scalars)
            local b = offset_literal(offset.rhs, scalars)
            if a ~= nil and b ~= nil then return a + b end
        end
        return nil
    end

    local function expr_same(a, b, scalars, contracts)
        a = resolve_scalar_expr(a, scalars)
        b = resolve_scalar_expr(b, scalars)
        if a == b then return true end
        local ab, bb = expr_binding(a), expr_binding(b)
        if ab ~= nil and bb ~= nil then return same_binding_slot(ab, bb) end
        if pvm.classof(a) == Tr.ExprLit and pvm.classof(b) == Tr.ExprLit then return a.value == b.value end
        if pvm.classof(a) == Tr.ExprLen and pvm.classof(b) == Tr.ExprLen then
            local av, bv = expr_binding(a.value), expr_binding(b.value)
            if av ~= nil and bv ~= nil and contract_same_len ~= nil and contract_same_len(contracts or {}, av, bv) then return true end
        end
        return false
    end

    local function binding_expr(binding)
        return Tr.ExprRef(Tr.ExprTyped(binding.ty), B.ValueRefBinding(binding))
    end

    local function len_source_expr(source)
        local cls = pvm.classof(source)
        if cls == V.VecKernelLenBinding then return binding_expr(source.binding) end
        if cls == V.VecKernelLenView then return Tr.ExprLen(Tr.ExprTyped(Ty.TScalar(C.ScalarIndex)), binding_expr(source.view)) end
        if cls == V.VecKernelLenExpr then return source.expr end
        return Tr.ExprLit(Tr.ExprTyped(Ty.TScalar(C.ScalarIndex)), C.LitInt("0"))
    end

    local function len_source_key(source)
        local cls = pvm.classof(source)
        if cls == V.VecKernelLenBinding then return "binding:" .. source.binding.id.text end
        if cls == V.VecKernelLenView then return "view:" .. source.view.id.text end
        if cls == V.VecKernelLenExpr then return "expr:" .. tostring(source.expr) end
        return "unknown"
    end

    local function len_source_is_binding(source, binding)
        return pvm.classof(source) == V.VecKernelLenBinding and same_binding_slot(source.binding, binding)
    end

    mask_uses = pvm.phase("moonlift_vec_kernel_mask_memory_uses", {
        [V.VecKernelMaskCompare] = function(self, elem)
            local out = {}
            append_all(out, pvm.one(expr_uses(self.lhs, elem)))
            append_all(out, pvm.one(expr_uses(self.rhs, elem)))
            return pvm.once(out)
        end,
        [V.VecKernelMaskNot] = function(self, elem)
            return mask_uses(self.value, elem)
        end,
        [V.VecKernelMaskBin] = function(self, elem)
            local out = {}
            append_all(out, pvm.one(mask_uses(self.lhs, elem)))
            append_all(out, pvm.one(mask_uses(self.rhs, elem)))
            return pvm.once(out)
        end,
    }, { args_cache = "last" })

    expr_uses = pvm.phase("moonlift_vec_kernel_expr_memory_uses", {
        [V.VecKernelExprLoad] = function(self, elem)
            return pvm.once({ V.VecKernelRead(self.base, elem, self.offset, self.base_len, self.len_value) })
        end,
        [V.VecKernelExprInvariant] = function()
            return pvm.once({})
        end,
        [V.VecKernelExprBin] = function(self, elem)
            local out = {}
            append_all(out, pvm.one(expr_uses(self.lhs, elem)))
            append_all(out, pvm.one(expr_uses(self.rhs, elem)))
            return pvm.once(out)
        end,
        [V.VecKernelExprSelect] = function(self, elem)
            local out = {}
            append_all(out, pvm.one(mask_uses(self.cond, elem)))
            append_all(out, pvm.one(expr_uses(self.then_value, elem)))
            append_all(out, pvm.one(expr_uses(self.else_value, elem)))
            return pvm.once(out)
        end,
    }, { args_cache = "last" })

    core_uses = pvm.phase("moonlift_vec_kernel_core_memory_uses", {
        [V.VecKernelCoreReduce] = function(self)
            local uses = {}
            append_all(uses, pvm.one(expr_uses(self.reduction.value, self.elem)))
            return pvm.once(uses)
        end,
        [V.VecKernelCoreMap] = function(self)
            local uses = {}
            for i = 1, #self.stores do
                uses[#uses + 1] = V.VecKernelWrite(self.stores[i].dst, self.elem, self.stores[i].offset, self.stores[i].base_len, self.stores[i].len_value)
                append_all(uses, pvm.one(expr_uses(self.stores[i].value, self.elem)))
            end
            return pvm.once(uses)
        end,
    })

    local function unique_bases(uses)
        local out, seen = {}, {}
        for i = 1, #uses do
            local base = uses[i].base
            local key = base.id.text
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = base
            end
        end
        return out
    end

    local function proven_bounds_for_base(facts, base)
        for i = 1, #facts.memory do
            local access = facts.memory[i]
            if pvm.classof(access) == V.VecMemoryAccess then
                local binding = memory_base_binding(access.base)
                if binding ~= nil and same_binding_slot(binding, base) and pvm.classof(access.bounds) == V.VecBoundsProven then return access.bounds.proof end
            end
        end
        return nil
    end

    contract_same_len = function(contracts, a, b)
        for i = 1, #(contracts or {}) do
            local fact = contracts[i]
            if pvm.classof(fact) == Tr.ContractFactSameLen then
                if (same_binding_slot(fact.a, a) and same_binding_slot(fact.b, b)) or (same_binding_slot(fact.a, b) and same_binding_slot(fact.b, a)) then return true end
            end
        end
        return false
    end

    local function view_len_bounds_proof(base, stop, contracts)
        if pvm.classof(base.ty) == Ty.TView and pvm.classof(stop.ty) == Ty.TView then
            if same_binding_slot(base, stop) then return V.VecProofKernelSafety("view length domain proves vector access range") end
            if contract_same_len(contracts, base, stop) then return V.VecProofKernelSafety("same_len contract proves view access range") end
        end
        return nil
    end

    local function contract_bounds_proof(contracts, base, stop)
        for i = 1, #(contracts or {}) do
            local fact = contracts[i]
            if pvm.classof(fact) == Tr.ContractFactBounds and same_binding_slot(fact.base, base) and same_binding_slot(fact.len, stop) then
                return V.VecProofKernelSafety("source bounds contract proves vector access range")
            end
        end
        return nil
    end

    local function contract_window_bounds_proof(contracts, obligation, scalars)
        local start = offset_expr_resolved(obligation.start, scalars)
        if start == nil then return nil end
        for i = 1, #(contracts or {}) do
            local fact = contracts[i]
            if pvm.classof(fact) == Tr.ContractFactWindowBounds
                and same_binding_slot(fact.base, obligation.base)
                and expr_same(fact.base_len, len_source_expr(obligation.base_len), scalars, contracts)
                and expr_same(fact.start, start, scalars, contracts)
                and (expr_same(fact.len, binding_expr(obligation.len), scalars, contracts) or expr_same(fact.len, obligation.len_value, scalars, contracts)) then
                return V.VecProofKernelSafety("source window_bounds contract proves vector window access range")
            end
        end
        return nil
    end

    window_range_decide = pvm.phase("moonlift_vec_window_range_decide", {
        [V.VecWindowRangeObligation] = function(self, contracts, scalars)
            scalars = scalars or {}
            if offset_is_zero(self.start) and (len_source_is_binding(self.base_len, self.len) or expr_same(self.len_value, len_source_expr(self.base_len), scalars, contracts)) then
                return pvm.once(V.VecWindowRangeProven(self, V.VecProofKernelSafety("window range equals the full base range")))
            end
            local start_value = offset_literal(self.start, scalars)
            local len_value = resolve_scalar_expr(self.len_value, scalars)
            local function shrink_const(expr)
                expr = resolve_scalar_expr(expr, scalars)
                if expr_same(expr, len_source_expr(self.base_len), scalars, contracts) then return 0 end
                if pvm.classof(expr) == Tr.ExprBinary and expr.op == C.BinSub then
                    local lhs = shrink_const(expr.lhs)
                    local rhs = const_int_expr(expr.rhs, scalars)
                    if lhs ~= nil and rhs ~= nil then return lhs + rhs end
                end
                return nil
            end
            local shrink = shrink_const(len_value)
            if start_value ~= nil and start_value >= 0 and shrink ~= nil and shrink >= start_value then
                return pvm.once(V.VecWindowRangeProven(self, V.VecProofKernelSafety("literal affine shrink window range is inside the base range")))
            end
            local proof = contract_window_bounds_proof(contracts or {}, self, scalars)
            if proof ~= nil then return pvm.once(V.VecWindowRangeProven(self, proof)) end
            return pvm.once(V.VecWindowRangeRejected(self, V.VecRejectUnsupportedMemory(V.VecAccessId("window.range:" .. self.base.id.text), "window range needs compiler proof or matching window_bounds(base, base_len, start, len) contract")))
        end,
    }, { args_cache = "last" })

    local function base_bounds_proof(facts, base, source, contracts)
        local cls = pvm.classof(source)
        if cls == V.VecKernelLenBinding then return view_len_bounds_proof(base, source.binding, contracts) or contract_bounds_proof(contracts, base, source.binding) or proven_bounds_for_base(facts, base) end
        if cls == V.VecKernelLenView and same_binding_slot(base, source.view) and pvm.classof(base.ty) == Ty.TView then return V.VecProofKernelSafety("view descriptor length proves base range") end
        return proven_bounds_for_base(facts, base)
    end

    local function bounds_for_uses(facts, uses, stop, contracts, scalars)
        local bounds = {}
        local assumptions = {}
        local proofs = {}
        local rejects = {}
        local seen = {}
        for i = 1, #uses do
            local use = uses[i]
            local effective_base_len = use.base_len
            if len_source_is_binding(use.base_len, use.base) then effective_base_len = V.VecKernelLenBinding(stop) end
            local key = use.base.id.text .. ":" .. tostring(use.offset) .. ":" .. len_source_key(effective_base_len) .. ":" .. stop.id.text
            if not seen[key] then
                seen[key] = true
                local obligation = V.VecWindowRangeObligation(use.base, effective_base_len, use.offset, stop, use.len_value)
                local range = pvm.one(window_range_decide(obligation, contracts or {}, scalars or {}))
                if pvm.classof(range) == V.VecWindowRangeRejected then
                    rejects[#rejects + 1] = range.reject
                    bounds[#bounds + 1] = V.VecKernelBoundsRejected(range.reject)
                else
                    proofs[#proofs + 1] = range.proof
                    local base_proof = base_bounds_proof(facts, use.base, effective_base_len, contracts)
                    if base_proof ~= nil then
                        proofs[#proofs + 1] = base_proof
                        bounds[#bounds + 1] = V.VecKernelBoundsProven(V.VecProofKernelSafety("base bounds plus window range prove vector access range"))
                    elseif pvm.classof(effective_base_len) == V.VecKernelLenBinding then
                        local assumption = V.VecAssumeRawPtrBounds(use.base, effective_base_len.binding, "raw pointer kernel assumes base window range is in bounds")
                        assumptions[#assumptions + 1] = assumption
                        bounds[#bounds + 1] = V.VecKernelBoundsAssumed(assumption)
                    else
                        local reject = V.VecRejectUnsupportedMemory(V.VecAccessId("base.bounds:" .. use.base.id.text), "base bounds need a view length, bounds contract, or binding-backed assumption")
                        rejects[#rejects + 1] = reject
                        bounds[#bounds + 1] = V.VecKernelBoundsRejected(reject)
                    end
                end
            end
        end
        return bounds, assumptions, proofs, rejects
    end

    local function dependence_proofs(facts)
        local proofs = {}
        for i = 1, #facts.dependences do
            if pvm.classof(facts.dependences[i]) == V.VecNoDependence then proofs[#proofs + 1] = facts.dependences[i].proof end
        end
        return proofs
    end

    local function contract_disjoint_pair(contracts, a, b)
        for i = 1, #(contracts or {}) do
            local fact = contracts[i]
            local cls = pvm.classof(fact)
            if cls == Tr.ContractFactDisjoint then
                if (same_binding_slot(fact.a, a) and same_binding_slot(fact.b, b)) or (same_binding_slot(fact.a, b) and same_binding_slot(fact.b, a)) then return true end
            elseif cls == Tr.ContractFactNoAlias then
                if same_binding_slot(fact.base, a) or same_binding_slot(fact.base, b) then return true end
            end
        end
        return false
    end

    local function same_offset(a, b)
        if a == b then return true end
        if offset_is_zero(a) and offset_is_zero(b) then return true end
        if pvm.classof(a) == V.VecKernelOffsetExpr and pvm.classof(b) == V.VecKernelOffsetExpr then return expr_same(a.expr, b.expr) end
        return false
    end

    local function alignments_for_uses(uses)
        local alignments = {}
        local seen = {}
        for i = 1, #(uses or {}) do
            local use = uses[i]
            local bytes = nil
            if use.elem == V.VecElemI32 or use.elem == V.VecElemU32 or use.elem == V.VecElemF32 then bytes = 4
            elseif use.elem == V.VecElemI64 or use.elem == V.VecElemU64 or use.elem == V.VecElemF64 or use.elem == V.VecElemIndex or use.elem == V.VecElemPtr then bytes = 8
            elseif use.elem == V.VecElemI16 or use.elem == V.VecElemU16 then bytes = 2
            elseif use.elem == V.VecElemI8 or use.elem == V.VecElemU8 or use.elem == V.VecElemBool then bytes = 1 end
            local key = use.base.id.text .. ":" .. tostring(use.elem)
            if not seen[key] then
                seen[key] = true
                if bytes ~= nil then
                    alignments[#alignments + 1] = V.VecKernelAlignProven(use.base, use.elem, bytes, V.VecProofKernelSafety("typed pointer/view element access proves natural alignment"))
                else
                    alignments[#alignments + 1] = V.VecKernelAlignUnknown(use.base, use.elem, "element alignment is not known")
                end
            end
        end
        return alignments
    end

    local function aliases_for_uses(uses, contracts)
        local aliases = {}
        local assumptions = {}
        local bases = unique_bases(uses)
        local writes = {}
        local reads = {}
        for i = 1, #uses do
            if pvm.classof(uses[i]) == V.VecKernelWrite then writes[#writes + 1] = uses[i] end
            if pvm.classof(uses[i]) == V.VecKernelRead then reads[#reads + 1] = uses[i] end
        end
        for wi = 1, #writes do
            local saw_read = false
            local all_same = true
            for ri = 1, #reads do
                saw_read = true
                if not same_binding_slot(writes[wi].base, reads[ri].base) or not same_offset(writes[wi].offset, reads[ri].offset) then all_same = false end
            end
            if saw_read and all_same then
                aliases[#aliases + 1] = V.VecKernelAliasSameIndexSafe(V.VecProofKernelSafety("store reads only the same base at the same lane index before writing"))
            elseif not saw_read then
                aliases[#aliases + 1] = V.VecKernelAliasProven(V.VecProofKernelSafety("store value is loop-invariant and has no read/write dependence"))
            end
        end
        if #bases > 1 then
            local function has_write(base)
                for wi = 1, #writes do if same_binding_slot(writes[wi].base, base) then return true end end
                return false
            end
            local all_proven = true
            for i = 1, #bases do
                for j = i + 1, #bases do
                    if (has_write(bases[i]) or has_write(bases[j])) and not contract_disjoint_pair(contracts, bases[i], bases[j]) then all_proven = false end
                end
            end
            if all_proven then
                aliases[#aliases + 1] = V.VecKernelAliasProven(V.VecProofKernelSafety("source noalias/disjoint contracts prove pointer bases independent"))
            else
                local assumption = V.VecAssumeRawPtrDisjointOrSameIndexSafe(bases, "distinct raw pointer bases are assumed disjoint or same-index safe")
                assumptions[#assumptions + 1] = assumption
                aliases[#aliases + 1] = V.VecKernelAliasAssumed(assumption)
            end
        end
        return aliases, assumptions
    end

    decide_input = pvm.phase("moonlift_vec_kernel_safety_decide", {
        [V.VecKernelSafetyInput] = function(self)
            local stop = self.core.stop
            local proofs = { V.VecProofDomain("canonical counted vector kernel") }
            local bounds, bound_assumptions, bound_proofs, bound_rejects = bounds_for_uses(self.facts, self.uses, stop, self.contracts or {}, self.core.scalars or {})
            append_all(proofs, bound_proofs)
            append_all(proofs, dependence_proofs(self.facts))
            local alignments = alignments_for_uses(self.uses)
            local aliases, alias_assumptions = aliases_for_uses(self.uses, self.contracts or {})
            local assumptions = {}
            append_all(assumptions, bound_assumptions)
            for i = 1, #alignments do if pvm.classof(alignments[i]) == V.VecKernelAlignAssumed then assumptions[#assumptions + 1] = alignments[i].assumption end end
            append_all(assumptions, alias_assumptions)
            for i = 1, #aliases do
                local cls = pvm.classof(aliases[i])
                if cls == V.VecKernelAliasSameIndexSafe or cls == V.VecKernelAliasProven then proofs[#proofs + 1] = aliases[i].proof end
            end
            local safety
            if #bound_rejects > 0 then safety = V.VecKernelSafetyRejected(bound_rejects)
            elseif #assumptions == 0 then safety = V.VecKernelSafetyProven(proofs) else safety = V.VecKernelSafetyAssumed(proofs, assumptions) end
            return pvm.once(V.VecKernelSafetyDecision(safety, bounds, alignments, aliases, bound_rejects))
        end,
    })

    return {
        expr_uses = expr_uses,
        core_uses = core_uses,
        window_range_decide = window_range_decide,
        decide_input = decide_input,
        decide = function(facts, core, contracts)
            local uses = pvm.one(core_uses(core))
            return pvm.one(decide_input(V.VecKernelSafetyInput(facts, core, uses, contracts or {})))
        end,
    }
end

return M
