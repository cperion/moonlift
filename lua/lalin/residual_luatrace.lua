local asdl = require("lalin.asdl")
local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then ffi = nil end

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function lua_string(s)
    return string.format("%q", tostring(s))
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.residual_luatrace ~= nil then return T._lalin_api_cache.residual_luatrace end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Stencil = T.LalinStencil
    require("lalin.stencil_methods")(T)
    local LT = T.LalinLuaTrace
    local ArtifactPlan = require("lalin.stencil_artifact_plan")(T)
    local Meta = require("lalin.stencil_metastencil")(T)
    local BCBank = require("lalin.residual_bc")(T)

    local api = {}

    local function is_int_ty(ty)
        return asdl.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function elem_bytes(ty)
        local cls = asdl.classof(ty)
        if ty == Code.CodeTyBool8 then return 1 end
        if ty == Code.CodeTyIndex then return nil end
        if cls == Code.CodeTyInt or cls == Code.CodeTyFloat then
            return math.floor((tonumber(ty.bits) or 0) / 8)
        end
        if cls == Code.CodeTyDataPtr or cls == Code.CodeTyCodePtr or cls == Code.CodeTyImportedCFuncPtr then
            return ffi and ffi.abi("64bit") and 8 or 4
        end
        return nil
    end

    local function lua_int_expr(ty, e)
        if is_int_ty(ty) then return "__ml_tobit(" .. e .. ")" end
        return e
    end

    local function iconst(expr)
        if expr == nil then return nil end
        if asdl.classof(expr) == Value.ValueExprConst then
            local k = expr.const or expr.value
            if asdl.classof(k) == Code.CodeConstLiteral then
                local lit = k.literal or k.value
                if asdl.classof(lit) == Core.LitInt then return tonumber(lit.raw or lit.text) end
                if asdl.classof(lit) == Core.LitFloat then return tonumber(lit.raw or lit.text) end
                if asdl.classof(lit) == Core.LitBool then return lit.value and 1 or 0 end
            end
        end
        error("residual_luatrace: unsupported constant expression", 3)
    end

    local function access_ref_name(ref)
        return ref and ref.name or nil
    end

    function Stencil.StencilVectorizationFacts:luatrace_access_fact_for(access)
        local name = type(access) == "string" and access or access.name
        for _, fact in ipairs(self.access_facts or {}) do
            if access_ref_name(fact.access) == name then return fact end
        end
        return nil
    end

    local function access_fact_for(facts, access)
        if facts == nil then return nil end
        return facts:luatrace_access_fact_for(access)
    end

    local function alias_relation(facts, left, right)
        if left == right then return Stencil.StencilAliasNoAlias end
        for _, fact in ipairs(facts and facts.alias_facts or {}) do
            local a = access_ref_name(fact.left)
            local b = access_ref_name(fact.right)
            if (a == left and b == right) or (a == right and b == left) then return fact.relation end
        end
        return Stencil.StencilAliasUnknown
    end

    function LT.LTAccessPlanSet:access_named(name)
        for _, plan in ipairs(self.entries or {}) do
            if plan.name == name then return plan end
        end
        return nil
    end

    function Stencil.StencilAccessLayout:luatrace_plain_bulk_access()
        return false
    end

    function Stencil.StencilAccessLayout:luatrace_is_scalar_layout()
        return false
    end

    function Stencil.StencilLayoutScalar:luatrace_is_scalar_layout()
        return true
    end

    function LT.LTAccessPlanEntry:luatrace_is_scalar_layout()
        return self.layout:luatrace_is_scalar_layout()
    end

    function Stencil.StencilLayoutContiguous:luatrace_plain_bulk_access()
        return tonumber(self.stride) == 1
    end

    function Stencil.StencilLayoutSliceDescriptor:luatrace_plain_bulk_access()
        return true
    end

    function Stencil.StencilLayoutByteSpanDescriptor:luatrace_plain_bulk_access()
        return true
    end

    function Stencil.StencilLayoutViewDescriptor:luatrace_plain_bulk_access()
        return tonumber(self.stride_const) == 1
    end

    local function access_plan_entry(access, fact, layout, parent, dynamic_stride_arg, stride_const, field_name, field_offset, component_index, index_name, index_stride)
        local element_bytes = elem_bytes(access.ty)
        local can_bulk_copy = layout:luatrace_plain_bulk_access() and element_bytes ~= nil
        return LT.LTAccessPlanEntry(
            access.name,
            access.role,
            access.ty,
            layout,
            fact ~= nil and fact.readonly or access.role == Stencil.StencilAccessRead,
            access.role == Stencil.StencilAccessReadWrite,
            fact and fact.alignment or Stencil.StencilAlignmentUnknown,
            fact and fact.unit_stride or false,
            dynamic_stride_arg,
            stride_const,
            field_name,
            field_offset,
            component_index,
            index_name,
            index_stride,
            element_bytes,
            parent,
            false,
            can_bulk_copy,
            can_bulk_copy and element_bytes == 1
        )
    end

    function Stencil.StencilAccessLayout:luatrace_access_plan(access, fact)
        return access_plan_entry(access, fact, self, nil, nil, nil, nil, nil, nil, nil, nil)
    end

    function Stencil.StencilLayoutFieldProjection:luatrace_access_plan(access, fact)
        local parent_access = Stencil.StencilAccess(access.name, access.role, access.ty, self.parent)
        return access_plan_entry(access, fact, self, self.parent:luatrace_access_plan(parent_access, fact), nil, nil, self.field_name, self.field_offset, nil, nil, nil)
    end

    function Stencil.StencilLayoutSoAComponent:luatrace_access_plan(access, fact)
        local parent_access = Stencil.StencilAccess(access.name, access.role, access.ty, self.parent)
        return access_plan_entry(access, fact, self, self.parent:luatrace_access_plan(parent_access, fact), nil, nil, self.field_name, nil, self.component_index, nil, nil)
    end

    function Stencil.StencilLayoutIndexed:luatrace_access_plan(access, fact)
        local parent_access = Stencil.StencilAccess(access.name, access.role, access.ty, self.parent)
        return access_plan_entry(access, fact, self, self.parent:luatrace_access_plan(parent_access, fact), nil, nil, nil, nil, nil, tostring(self.index.name), self.stride)
    end

    function Stencil.StencilLayoutViewDescriptor:luatrace_access_plan(access, fact)
        return access_plan_entry(access, fact, self, nil, self.stride_const == nil and (sanitize(access.name) .. "_stride") or nil, self.stride_const, nil, nil, nil, nil, nil)
    end

    local function build_access_plans(desc, facts)
        local list = {}
        for _, access in ipairs(ArtifactPlan.descriptor_accesses(desc)) do
            local plan = access.layout:luatrace_access_plan(access, access_fact_for(facts, access))
            list[#list + 1] = plan
        end
        return LT.LTAccessPlanSet(list)
    end

    local function lua_access_offset(plan, index)
        return plan:luatrace_offset(index)
    end

    local function lua_access_ref(plan, base, index)
        return plan:luatrace_ref(base, index)
    end

    function LT.LTAccessPlanEntry:luatrace_offset(index)
        return self.layout:luatrace_offset(self, tostring(index))
    end

    function Stencil.StencilAccessLayout:luatrace_offset(_plan, index)
        return index
    end

    function Stencil.StencilLayoutFieldProjection:luatrace_offset(plan, index)
        return plan.parent:luatrace_offset(index)
    end

    function Stencil.StencilLayoutSoAComponent:luatrace_offset(plan, index)
        return plan.parent:luatrace_offset(index)
    end

    function Stencil.StencilLayoutIndexed:luatrace_offset(plan, index)
        local indexed = table.concat({ tostring(plan.index_name), "[", plan.parent:luatrace_offset(index), "]" })
        if tonumber(plan.index_stride) ~= nil and tonumber(plan.index_stride) ~= 1 then
            indexed = "((" .. indexed .. ") * " .. tostring(plan.index_stride) .. ")"
        end
        return plan.parent:luatrace_offset(indexed)
    end

    function Stencil.StencilLayoutViewDescriptor:luatrace_offset(plan, index)
        local stride = plan.stride_const or plan.dynamic_stride_arg
        if tonumber(stride) == 1 then return index end
        return "((" .. index .. ") * " .. tostring(stride) .. ")"
    end

    function LT.LTAccessPlanEntry:luatrace_ref(base, index)
        return self.layout:luatrace_ref(self, tostring(base), tostring(index))
    end

    function Stencil.StencilAccessLayout:luatrace_ref(plan, base, index)
        return base .. "[" .. plan:luatrace_offset(index) .. "]"
    end

    function Stencil.StencilLayoutFieldProjection:luatrace_ref(plan, base, index)
        return base .. "[" .. plan.parent:luatrace_offset(index) .. "]." .. sanitize(self.field_name)
    end

    function Stencil.StencilLayoutSoAComponent:luatrace_ref(plan, base, index)
        return base .. "[" .. plan.parent:luatrace_offset(index) .. "]"
    end

    local function lua_unary_expr(op, v, ty, int_semantics, float_mode)
        if op == Stencil.StencilUnaryIdentity then return v end
        if op == Stencil.StencilUnaryNeg then return lua_int_expr(ty, "(-" .. v .. ")") end
        if op == Stencil.StencilUnaryBitNot then return "__ml_bnot(" .. v .. ")" end
        if op == Stencil.StencilUnaryBoolNot then return "((" .. v .. ") == 0 and 1 or 0)" end
        error("residual_luatrace: unsupported unary op", 3)
    end

    local function lua_binary_expr(op, a, b, ty, int_semantics, float_mode)
        if op == Stencil.StencilBinaryAdd then return lua_int_expr(ty, "((" .. a .. ") + (" .. b .. "))") end
        if op == Stencil.StencilBinarySub then return lua_int_expr(ty, "((" .. a .. ") - (" .. b .. "))") end
        if op == Stencil.StencilBinaryMul then return lua_int_expr(ty, "((" .. a .. ") * (" .. b .. "))") end
        if op == Stencil.StencilBinaryDiv then
            if is_int_ty(ty) then return "__ml_idiv(" .. a .. ", " .. b .. ")" end
            return "((" .. a .. ") / (" .. b .. "))"
        end
        if op == Stencil.StencilBinaryMod then
            if not is_int_ty(ty) then error("residual_luatrace: modulo requires integer type", 3) end
            return "__ml_imod(" .. a .. ", " .. b .. ")"
        end
        if op == Stencil.StencilBinaryAnd then return "__ml_band(" .. a .. ", " .. b .. ")" end
        if op == Stencil.StencilBinaryOr then return "__ml_bor(" .. a .. ", " .. b .. ")" end
        if op == Stencil.StencilBinaryXor then return "__ml_bxor(" .. a .. ", " .. b .. ")" end
        if op == Stencil.StencilBinaryShl then return lua_int_expr(ty, "__ml_lshift(" .. a .. ", " .. b .. ")") end
        if op == Stencil.StencilBinaryLShr then return lua_int_expr(ty, "__ml_rshift(" .. a .. ", " .. b .. ")") end
        if op == Stencil.StencilBinaryAShr then return lua_int_expr(ty, "__ml_arshift(" .. a .. ", " .. b .. ")") end
        if op == Stencil.StencilBinaryMin then return "((" .. a .. ") < (" .. b .. ") and (" .. a .. ") or (" .. b .. "))" end
        if op == Stencil.StencilBinaryMax then return "((" .. a .. ") > (" .. b .. ") and (" .. a .. ") or (" .. b .. "))" end
        error("residual_luatrace: unsupported binary op", 3)
    end

    function Value.ReductionOp:luatrace_update_expr(_acc, _item, _ty)
        error("residual_luatrace: unsupported reduction", 3)
    end

    function Value.ReductionAdd:luatrace_update_expr(acc, item, ty)
        return lua_int_expr(ty, "((" .. acc .. ") + (" .. item .. "))")
    end

    function Value.ReductionMul:luatrace_update_expr(acc, item, ty)
        return lua_int_expr(ty, "((" .. acc .. ") * (" .. item .. "))")
    end

    function Value.ReductionAnd:luatrace_update_expr(acc, item, _ty)
        return "__ml_band(" .. acc .. ", " .. item .. ")"
    end

    function Value.ReductionOr:luatrace_update_expr(acc, item, _ty)
        return "__ml_bor(" .. acc .. ", " .. item .. ")"
    end

    function Value.ReductionXor:luatrace_update_expr(acc, item, _ty)
        return "__ml_bxor(" .. acc .. ", " .. item .. ")"
    end

    function Value.ReductionMin:luatrace_update_expr(acc, item, _ty)
        return "((" .. item .. ") < (" .. acc .. ") and (" .. item .. ") or (" .. acc .. "))"
    end

    function Value.ReductionMax:luatrace_update_expr(acc, item, _ty)
        return "((" .. item .. ") > (" .. acc .. ") and (" .. item .. ") or (" .. acc .. "))"
    end

    local function lua_reduce_expr(kind, acc, item, ty)
        return kind:luatrace_update_expr(acc, item, ty)
    end

    local lua_cmp_expr

    local function lua_pred_expr(p, v)
        local cls = asdl.classof(p)
        if p == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return "(" .. v .. " ~= 0)" end
        if cls == Stencil.StencilPredCompareConst then return lua_cmp_expr(p.cmp, v, tostring(iconst(p.value))) end
        if cls == Stencil.StencilPredRange then
            return "(" .. lua_cmp_expr(p.lower_cmp, v, tostring(iconst(p.lower))) .. " and " .. lua_cmp_expr(p.upper_cmp, v, tostring(iconst(p.upper))) .. ")"
        end
        if cls == Stencil.StencilPredAnd then
            local terms = {}
            for _, term in ipairs(p.terms or {}) do terms[#terms + 1] = lua_pred_expr(term, v) end
            if #terms == 0 then return "(true)" end
            return "(" .. table.concat(terms, " and ") .. ")"
        end
        if cls == Stencil.StencilPredOr then
            local terms = {}
            for _, term in ipairs(p.terms or {}) do terms[#terms + 1] = lua_pred_expr(term, v) end
            if #terms == 0 then return "(false)" end
            return "(" .. table.concat(terms, " or ") .. ")"
        end
        if cls == Stencil.StencilPredNot then return "(not " .. lua_pred_expr(p.term, v) .. ")" end
        if cls == Stencil.StencilPredIsNaN then return "((" .. v .. ") ~= (" .. v .. "))" end
        if cls == Stencil.StencilPredIsInf then return "(((" .. v .. ") == math.huge) or ((" .. v .. ") == -math.huge))" end
        if cls == Stencil.StencilPredIsFinite then return "(((" .. v .. ") == (" .. v .. ")) and ((" .. v .. ") ~= math.huge) and ((" .. v .. ") ~= -math.huge))" end
        error("residual_luatrace: unsupported predicate", 3)
    end

    lua_cmp_expr = function(op, a, b)
        if op == Core.CmpEq then return "(" .. a .. " == " .. b .. ")" end
        if op == Core.CmpNe then return "(" .. a .. " ~= " .. b .. ")" end
        if op == Core.CmpLt then return "(" .. a .. " < " .. b .. ")" end
        if op == Core.CmpLe then return "(" .. a .. " <= " .. b .. ")" end
        if op == Core.CmpGt then return "(" .. a .. " > " .. b .. ")" end
        if op == Core.CmpGe then return "(" .. a .. " >= " .. b .. ")" end
        error("residual_luatrace: unsupported compare op", 3)
    end

    local function is_i32_signed(ty)
        return asdl.classof(ty) == Code.CodeTyInt and tonumber(ty.bits) == 32 and ty.signedness == Code.CodeSigned
    end

    local function is_u8(ty)
        return asdl.classof(ty) == Code.CodeTyInt and tonumber(ty.bits) == 8 and ty.signedness == Code.CodeUnsigned
    end

    local function lua_i32_gt_zero_value(v)
        return "__ml_band(__ml_bnot(__ml_rshift(" .. v .. ", 31)), __ml_rshift(__ml_bor(" .. v .. ", __ml_tobit(-" .. v .. ")), 31), 1)"
    end

    local function lua_i32_lt_value(a, b)
        local sx = "__ml_rshift(" .. a .. ", 31)"
        local sy = "__ml_rshift(" .. b .. ", 31)"
        local diff = "__ml_bxor(" .. sx .. ", " .. sy .. ")"
        local sd = "__ml_rshift(__ml_tobit(" .. a .. " - " .. b .. "), 31)"
        return "__ml_band(__ml_bor(__ml_band(" .. sx .. ", " .. diff .. "), __ml_band(__ml_bnot(" .. diff .. "), " .. sd .. ")), 1)"
    end

    local function lua_numeric_pred_expr(pred, v, ty)
        local cls = asdl.classof(pred)
        if cls == Stencil.StencilPredCompareConst and pred.cmp == Core.CmpGt then
            local c = iconst(pred.value)
            if c == 0 and is_i32_signed(ty) then return lua_i32_gt_zero_value(v) end
            if c == 127 and is_u8(ty) then return "__ml_rshift(" .. v .. ", 7)" end
        end
        return nil
    end

    local function lua_numeric_cmp_expr(op, a, b, lhs_ty, rhs_ty)
        if op == Core.CmpLt and is_i32_signed(lhs_ty) and is_i32_signed(rhs_ty) then
            return lua_i32_lt_value(a, b)
        end
        return nil
    end

    local function with_dynamic_strides(desc, params)
        local out = {}
        for i = 1, #params do out[i] = params[i] end
        for _, access in ipairs(ArtifactPlan.dynamic_stride_accesses(desc)) do
            out[#out + 1] = sanitize(access.name) .. "_stride"
        end
        return out
    end

    local function fn_header(artifact, args)
        return "local function " .. sanitize(artifact.symbol.text) .. "(" .. table.concat(with_dynamic_strides(artifact.instance.descriptor, args), ", ") .. ")"
    end

    local function schedule_facts(schedule)
        return schedule and schedule:stencil_vectorization_facts() or nil
    end

    function Stencil.StencilTripCountFact:luatrace_multiple_of(_group)
        return false
    end

    function Stencil.StencilTripCountMultipleOf:luatrace_multiple_of(group)
        local factor = tonumber(self.factor) or 1
        return factor >= group and factor % group == 0
    end

    function Stencil.StencilTripCountExact:luatrace_multiple_of(group)
        local count = tonumber(self.count) or 0
        return count >= 0 and count % group == 0
    end

    local function trip_count_multiple_of(facts, group)
        if facts == nil or group <= 1 then return false end
        return facts.trip_count:luatrace_multiple_of(group)
    end

    local function facts_unit_stride(desc, facts)
        if facts == nil then return false end
        local saw_memory_access = false
        for _, access in ipairs(ArtifactPlan.descriptor_accesses(desc)) do
            if not access.layout:luatrace_is_scalar_layout() then
                local fact = access_fact_for(facts, access)
                if fact == nil or not fact.unit_stride then return false end
                saw_memory_access = true
            end
        end
        return saw_memory_access
    end

    function Stencil.StencilArtifactShape:luatrace_group_cap()
        return 1
    end

    function Stencil.StencilStoreSemantics:luatrace_group_cap()
        return 8
    end

    function Stencil.StencilStoreScatter:luatrace_group_cap()
        return self.conflicts == Stencil.StencilScatterUniqueIndices and 4 or 1
    end

    function Stencil.StencilArtifactStoreN:luatrace_group_cap()
        return self.store_mode:luatrace_group_cap()
    end

    function Stencil.StencilReduceInitMode:luatrace_group_cap()
        return 8
    end

    function Stencil.StencilReduceInitIdentity:luatrace_group_cap()
        return 4
    end

    function Stencil.StencilArtifactReduceN:luatrace_group_cap()
        return self.init_mode:luatrace_group_cap()
    end

    function Stencil.StencilArtifactScanN:luatrace_group_cap()
        return 16
    end

    function Stencil.StencilProducerExecution:luatrace_is_linear_range()
        return false
    end

    function Stencil.StencilProducerExecRange1D:luatrace_is_linear_range()
        return true
    end

    function Stencil.StencilProducerExecution:luatrace_loop_shape_name()
        error("residual_luatrace: unsupported producer execution", 3)
    end

    function Stencil.StencilProducerExecRange1D:luatrace_loop_shape_name()
        return "range1d"
    end

    function Stencil.StencilProducerExecRangeND:luatrace_loop_shape_name()
        return "range_nd"
    end

    function Stencil.StencilProducerExecWindowND:luatrace_loop_shape_name()
        return "window_nd"
    end

    function Stencil.StencilProducerExecTiledND:luatrace_loop_shape_name()
        return "tiled_nd"
    end

    function Stencil.StencilProducerExecution:luatrace_loop_reason()
        return self:luatrace_loop_shape_name() .. "_producer_scalar"
    end

    local function autovector_group(desc, shape, facts)
        if not facts_unit_stride(desc, facts) then return 1, "autovector_blocked_non_unit_stride" end
        return shape:luatrace_group_cap(), "autovector_trace_group"
    end

    function Stencil.StencilSchedule:luatrace_linear_loop_plan(desc, shape, stride)
        local group, reason = 1, "scalar"
        local tail_strategy = "generic_tail_loop"
        if trip_count_multiple_of(schedule_facts(self), group) then
            tail_strategy = "no_tail_trip_count_multiple"
        end
        return LT.LTLoopPlan(stride, group, reason, tail_strategy, "scalar_for")
    end

    function Stencil.StencilScheduleVector:luatrace_linear_loop_plan(_desc, _shape, stride)
        local lanes = math.max(1, math.floor(tonumber(ArtifactPlan.schedule_lane_count(self)) or 1))
        local unroll = math.max(1, math.floor(tonumber(self.vector_unroll) or 1))
        local interleave = math.max(1, math.floor(tonumber(self.interleave) or 1))
        local group = math.max(1, lanes * unroll * interleave)
        local tail_strategy = trip_count_multiple_of(schedule_facts(self), group) and "no_tail_trip_count_multiple" or "generic_tail_loop"
        return LT.LTLoopPlan(stride, group, "vector_as_trace_group", tail_strategy, group > 1 and "grouped_while" or "scalar_for")
    end

    function Stencil.StencilScheduleUnrolled:luatrace_linear_loop_plan(_desc, _shape, stride)
        local group = math.max(1, math.floor(tonumber(self.factor) or 1))
        local tail_strategy = trip_count_multiple_of(schedule_facts(self), group) and "no_tail_trip_count_multiple" or "generic_tail_loop"
        return LT.LTLoopPlan(stride, group, "unrolled_trace_group", tail_strategy, group > 1 and "grouped_while" or "scalar_for")
    end

    function Stencil.StencilScheduleAutoVector:luatrace_linear_loop_plan(desc, shape, stride)
        local group, reason = autovector_group(desc, shape, schedule_facts(self))
        local cap = shape:luatrace_group_cap()
        if #ArtifactPlan.dynamic_stride_accesses(desc) ~= 0 then cap = math.min(cap, 4) end
        if group > cap then
            group = cap
            reason = reason .. "_capped_" .. tostring(cap)
        end
        local tail_strategy = trip_count_multiple_of(schedule_facts(self), math.max(1, group)) and "no_tail_trip_count_multiple" or "generic_tail_loop"
        return LT.LTLoopPlan(stride, math.max(1, group), reason, tail_strategy, group > 1 and "grouped_while" or "scalar_for")
    end

    local function build_loop_plan(desc, schedule, shape)
        if not shape.producer:luatrace_is_linear_range() then
            return LT.LTLoopPlan(1, 1, shape.producer:luatrace_loop_reason(), "producer_loop", shape.producer:luatrace_loop_shape_name())
        end
        local stride = tonumber(shape.stride) or 1
        if stride ~= 1 then
            return LT.LTLoopPlan(stride, 1, "domain_stride", "generic_tail_loop", "scalar_for")
        end
        return schedule:luatrace_linear_loop_plan(desc, shape, stride)
    end

    local function no_predicate_plan()
        return LT.LTPredicateNone
    end

    local function count_predicate_plan(loop_plan)
        if loop_plan ~= nil and loop_plan.group > 1 then
            return LT.LTPredicateMultiCounterBranch(loop_plan.group, "numeric_count_measured_slower")
        end
        return LT.LTPredicateBranch("numeric_count_measured_slower")
    end

    function Stencil.StencilPointExpr:luatrace_input_name()
        return nil
    end

    function Stencil.StencilPointInput:luatrace_input_name()
        return self.access.name
    end

    function Stencil.StencilPointExpr:luatrace_store_predicate_plan(_access_plans)
        return no_predicate_plan()
    end

    function Stencil.StencilPointPredicate:luatrace_store_predicate_plan(access_plans)
        local input_name = self.arg:luatrace_input_name()
        local input = input_name ~= nil and access_plans:access_named(input_name) or nil
        local numeric = input ~= nil and lua_numeric_pred_expr(self.pred, "__ml_x", input.ty) ~= nil
        if numeric then return LT.LTPredicateNumericStore("helper_branchless_measured_slower") end
        return LT.LTPredicateLuaSelect("numeric_predicate_unavailable")
    end

    function Stencil.StencilPointCompare:luatrace_store_predicate_plan(access_plans)
        local left_name = self.left:luatrace_input_name()
        local right_name = self.right:luatrace_input_name()
        local lhs = left_name ~= nil and access_plans:access_named(left_name) or nil
        local rhs = right_name ~= nil and access_plans:access_named(right_name) or nil
        local numeric = lhs ~= nil and rhs ~= nil and lua_numeric_cmp_expr(self.cmp, "__ml_a", "__ml_b", lhs.ty, rhs.ty) ~= nil
        if numeric then return LT.LTPredicateNumericStore("helper_branchless_measured_slower") end
        return LT.LTPredicateLuaSelect("numeric_compare_unavailable")
    end

    function Stencil.StencilPointSelect:luatrace_store_predicate_plan(_access_plans)
        return LT.LTPredicateLuaSelect("branchless_numeric_select_not_measured")
    end

    function Stencil.StencilArtifactShape:luatrace_predicate_plan(_access_plans, _loop_plan)
        return no_predicate_plan()
    end

    function Stencil.StencilArtifactStoreN:luatrace_predicate_plan(access_plans, _loop_plan)
        return self.expr:luatrace_store_predicate_plan(access_plans)
    end

    function Stencil.StencilReduceInitMode:luatrace_reduce_predicate_plan(_shape, _loop_plan)
        return no_predicate_plan()
    end

    function Stencil.StencilReduceInitIdentity:luatrace_reduce_predicate_plan(_shape, loop_plan)
        return count_predicate_plan(loop_plan)
    end

    function Stencil.StencilArtifactReduceN:luatrace_predicate_plan(_access_plans, loop_plan)
        return self.init_mode:luatrace_reduce_predicate_plan(self, loop_plan)
    end

    function Stencil.StencilStoreSemantics:luatrace_scatter_plan()
        return LT.LTScatterNone
    end

    function Stencil.StencilStoreScatter:luatrace_scatter_plan()
        local conflicts = self.conflicts
        if conflicts == Stencil.StencilScatterUniqueIndices then return LT.LTScatterUniqueIndices end
        if conflicts == Stencil.StencilScatterLastWriteWins then return LT.LTScatterOrderedLastWrite end
        if conflicts == Stencil.StencilScatterConflictUndefined then return LT.LTScatterConflictUndefined end
        return LT.LTScatterUnknown("unknown_conflicts")
    end

    function Stencil.StencilArtifactShape:luatrace_scatter_plan()
        return LT.LTScatterNone
    end

    function Stencil.StencilArtifactStoreN:luatrace_scatter_plan()
        return self.store_mode:luatrace_scatter_plan()
    end

    local function reduction_plan_for_shape(shape, facts)
        local arithmetic = facts and facts.arithmetic or nil
        local reassociable = arithmetic ~= nil and arithmetic.reduction_reassociable or false
        local float_mode = arithmetic and arithmetic.float_mode or shape.float_mode
        return LT.LTReductionOrderedSingleAccumulator(false, reassociable, false, reassociable and "not_measured_faster_for_luatrace" or "reassociation_not_legal")
    end

    function Stencil.StencilArtifactShape:luatrace_reduction_plan(_facts)
        return LT.LTReductionNone
    end

    function Stencil.StencilArtifactReduceN:luatrace_reduction_plan(facts)
        return reduction_plan_for_shape(self, facts)
    end

    function Stencil.StencilArtifactScanN:luatrace_reduction_plan(facts)
        return reduction_plan_for_shape(self, facts)
    end

    function Stencil.StencilStoreSemantics:luatrace_copy_src_name(_expr)
        return nil
    end

    function Stencil.StencilStoreCopy:luatrace_copy_src_name(expr)
        return expr:luatrace_input_name()
    end

    function Stencil.StencilStoreSemantics:luatrace_fill_value_name(_expr)
        return nil
    end

    function Stencil.StencilStoreElementwise:luatrace_fill_value_name(expr)
        return expr:luatrace_input_name()
    end

    function Stencil.StencilStoreSemantics:luatrace_copy_semantics()
        return nil
    end

    function Stencil.StencilStoreCopy:luatrace_copy_semantics()
        return self.semantics
    end

    function Stencil.StencilArtifactShape:luatrace_primitive_plan(_access_plans, _facts)
        return LT.LTPrimitiveNone
    end

    function Stencil.StencilArtifactStoreN:luatrace_primitive_plan(access_plans, facts)
        local can_use_linear_range_primitive = self.producer:luatrace_is_linear_range()
        local copy_src_name = self.store_mode:luatrace_copy_src_name(self.expr)
        if copy_src_name ~= nil then
            local dst_name = self.dst_name or "dst"
            local src_name = copy_src_name or "src"
            local dst, src = access_plans:access_named(dst_name), access_plans:access_named(src_name)
            local semantics = self.store_mode:luatrace_copy_semantics()
            local no_overlap = semantics == Stencil.StencilCopyNoOverlap
                or (dst ~= nil and src ~= nil and alias_relation(facts, dst_name, src_name) == Stencil.StencilAliasNoAlias)
            if can_use_linear_range_primitive
                and no_overlap
                and dst ~= nil and src ~= nil
                and not dst.readonly and src.readonly
                and dst.can_bulk_copy and src.can_bulk_copy
                and dst.element_bytes == src.element_bytes then
                return LT.LTPrimitiveFfiCopy(
                    dst.element_bytes,
                    dst_name,
                    src_name,
                    semantics == Stencil.StencilCopyNoOverlap and "copy_semantics" or "noalias_facts"
                )
            end
            return LT.LTPrimitiveNone
        end
        local value_name = self.store_mode:luatrace_fill_value_name(self.expr)
        if value_name ~= nil then
            local dst_name = self.dst_name or "dst"
            local dst, value_access = access_plans:access_named(dst_name), access_plans:access_named(value_name)
            if can_use_linear_range_primitive
                and dst ~= nil and value_access ~= nil
                and value_access:luatrace_is_scalar_layout()
                and not dst.readonly and dst.can_bulk_fill then
                return LT.LTPrimitiveFfiFill(dst.element_bytes, dst_name, value_name)
            end
        end
        return LT.LTPrimitiveNone
    end

    local function build_kernel_plan(shape, access_plans, facts, loop_plan)
        return LT.LTKernelPlan(
            shape:luatrace_primitive_plan(access_plans, facts),
            shape:luatrace_predicate_plan(access_plans, loop_plan),
            shape:luatrace_scatter_plan(),
            shape:luatrace_reduction_plan(facts)
        )
    end

    local function lua_point_expr(expr, desc, access_plans, index)
        return expr:luatrace_point_expr(desc, access_plans, index)
    end

    function Stencil.StencilPointExpr:luatrace_point_expr(_desc, _access_plans, _index)
        error("residual_luatrace: unsupported apply expression", 3)
    end

    function Stencil.StencilPointInput:luatrace_point_expr(_desc, access_plans, index)
        local name = tostring(self.access.name)
        local access = assert(access_plans:access_named(name), "residual_luatrace: missing point input access " .. tostring(name))
        if access:luatrace_is_scalar_layout() then return name end
        return lua_access_ref(access, name, index)
    end

    function Stencil.StencilPointWindowInput:luatrace_point_expr(_desc, _access_plans, _index)
        error("residual_luatrace: window-relative point inputs are not materialized by LuaTrace", 3)
    end

    function Stencil.StencilPointConst:luatrace_point_expr(_desc, _access_plans, _index)
        return tostring(iconst(self.value))
    end

    function Stencil.StencilPointUnary:luatrace_point_expr(desc, access_plans, index)
        return lua_unary_expr(self.op, lua_point_expr(self.arg, desc, access_plans, index), self.result_ty, self.int_semantics, self.float_mode)
    end

    function Stencil.StencilPointBinary:luatrace_point_expr(desc, access_plans, index)
        return lua_binary_expr(
            self.op,
            lua_point_expr(self.left, desc, access_plans, index),
            lua_point_expr(self.right, desc, access_plans, index),
            self.result_ty,
            self.int_semantics,
            self.float_mode
        )
    end

    function Stencil.StencilPointCast:luatrace_point_expr(desc, access_plans, index)
        return lua_point_expr(self.arg, desc, access_plans, index)
    end

    function Stencil.StencilPointPredicate:luatrace_point_expr(desc, access_plans, index)
        return "(" .. lua_pred_expr(self.pred, lua_point_expr(self.arg, desc, access_plans, index)) .. " and 1 or 0)"
    end

    function Stencil.StencilPointCompare:luatrace_point_expr(desc, access_plans, index)
        return "(" .. lua_cmp_expr(
            self.cmp,
            lua_point_expr(self.left, desc, access_plans, index),
            lua_point_expr(self.right, desc, access_plans, index)
        ) .. " and 1 or 0)"
    end

    function Stencil.StencilPointSelect:luatrace_point_expr(desc, access_plans, index)
        return "("
            .. lua_pred_expr(self.pred, lua_point_expr(self.cond, desc, access_plans, index))
            .. " and "
            .. lua_point_expr(self.then_expr, desc, access_plans, index)
            .. " or "
            .. lua_point_expr(self.else_expr, desc, access_plans, index)
            .. ")"
    end

    function Stencil.StencilStoreSemantics:luatrace_range_nd_reject_reason()
        return nil
    end

    function Stencil.StencilStoreCopy:luatrace_range_nd_reject_reason()
        if self.semantics == Stencil.StencilCopyMemMove or self.semantics == Stencil.StencilCopyMayOverlapBackward then
            return "RangeND copy with overlapping memmove semantics is not materialized by LuaTrace yet"
        end
        return nil
    end

    function Stencil.StencilReduceExecutionScope:luatrace_range_nd_reject_reason()
        return nil
    end

    function Stencil.StencilReduceExecWindow:luatrace_range_nd_reject_reason()
        return "RangeND window-local reduction needs WindowND producer semantics"
    end

    function Stencil.StencilArtifactShape:luatrace_range_nd_reject_reason()
        return nil
    end

    function Stencil.StencilArtifactStoreN:luatrace_range_nd_reject_reason()
        return self.store_mode:luatrace_range_nd_reject_reason()
    end

    function Stencil.StencilArtifactReduceN:luatrace_range_nd_reject_reason()
        return self.reduce_scope:luatrace_range_nd_reject_reason()
    end

    function Stencil.StencilArtifactPartitionN:luatrace_range_nd_reject_reason()
        return "RangeND producer is not materialized for PartitionN in LuaTrace"
    end

    function Stencil.StencilProducerExecution:luatrace_reject_shape(_shape)
        return "producer " .. self:luatrace_loop_shape_name() .. " is not materialized by the LuaTrace bytecode path yet"
    end

    function Stencil.StencilProducerExecRange1D:luatrace_reject_shape(_shape)
        return nil
    end

    function Stencil.StencilProducerExecRangeND:luatrace_reject_shape(shape)
        return shape:luatrace_range_nd_reject_reason()
    end

    local function luatrace_producer_reject_reason(shape)
        return shape.producer:luatrace_reject_shape(shape)
    end

    local function build_artifact_plan(artifact)
        local desc = artifact.instance.descriptor
        local shape = ArtifactPlan.artifact_shape(artifact)
        local producer_reject = luatrace_producer_reject_reason(shape)
        if producer_reject ~= nil then
            error("residual_luatrace: " .. tostring(producer_reject), 3)
        end
        local schedule = artifact.instance.schedule
        local facts = schedule_facts(schedule)
        local access_plans = build_access_plans(desc, facts)
        local loop_plan = build_loop_plan(desc, schedule, shape)
        return LT.LTArtifactPlan(
            artifact,
            desc,
            shape,
            schedule,
            facts,
            access_plans,
            loop_plan,
            build_kernel_plan(shape, access_plans, facts, loop_plan),
            sanitize(artifact.symbol.text)
        )
    end

    local function realized_bc_schedule(artifact)
        local plan = build_artifact_plan(artifact)
        local evidence = {
            Stencil.StencilRealizedByConstruction("LuaTrace copy+compile residual materializer emitted " .. tostring(plan.loop_plan.reason)),
        }
        local group = tonumber(plan.loop_plan.group) or 1
        if group > 1 then
            return Stencil.StencilRealizedUnrolled(group, Stencil.StencilMaterializerResidualBC, evidence)
        end
        return Stencil.StencilRealizedScalar(Stencil.StencilMaterializerResidualBC, evidence)
    end

    local function with_realized(artifact, provider, realized)
        return ArtifactPlan.artifact_with_realized(artifact, provider or artifact.provider, realized)
    end

    local function scatter_reduce_conflicts_materialized(conflicts)
        return conflicts == nil
            or conflicts == Stencil.StencilScatterReduceSequential
            or conflicts == Stencil.StencilScatterReduceUniqueIndices
    end

    function Stencil.StencilProducerExecution:luatrace_params()
        error("residual_luatrace: unsupported producer params for " .. self:luatrace_loop_shape_name(), 3)
    end

    function Stencil.StencilProducerExecRange1D:luatrace_params()
        return { "start", "stop" }
    end

    function Stencil.StencilProducerExecRangeND:luatrace_params()
        local params = {}
        for _, axis in ipairs(self.axes or {}) do
            params[#params + 1] = axis.start_param
            params[#params + 1] = axis.stop_param
        end
        return params
    end

    local function append_producer_params(params, producer)
        local p = producer:luatrace_params()
        for i = 1, #p do params[#params + 1] = p[i] end
    end

    local function range_nd_extent_expr(axis)
        local step = tonumber(axis.step) or 1
        local span = tostring(axis.stop_param) .. " - " .. tostring(axis.start_param)
        if step == 1 then return "(" .. span .. ")" end
        return "math.floor((" .. span .. " + " .. tostring(step - 1) .. ") / " .. tostring(step) .. ")"
    end

    local function range_nd_axis_offset_expr(axis_index, axis)
        local step = tonumber(axis.step) or 1
        local offset = "(__ml_axis" .. tostring(axis_index) .. " - " .. tostring(axis.start_param) .. ")"
        if step == 1 then return offset end
        return "math.floor(" .. offset .. " / " .. tostring(step) .. ")"
    end

    local function range_nd_linear_index_expr(producer)
        local linear = nil
        for axis_index, axis in ipairs(producer.axes or {}) do
            local offset = range_nd_axis_offset_expr(axis_index, axis)
            if linear == nil then
                linear = offset
            else
                linear = "((" .. linear .. ") * __ml_extent" .. tostring(axis_index) .. " + " .. offset .. ")"
            end
        end
        return linear or "0"
    end

    local function range_nd_projected_index_expr(producer, keep_axes)
        local linear = nil
        for axis_index, axis in ipairs(producer.axes or {}) do
            if keep_axes[axis_index] then
                local offset = range_nd_axis_offset_expr(axis_index, axis)
                if linear == nil then
                    linear = offset
                else
                    linear = "((" .. linear .. ") * __ml_extent" .. tostring(axis_index) .. " + " .. offset .. ")"
                end
            end
        end
        return linear or "0"
    end

    local function emit_range_nd_extents(out, producer, indent)
        for axis_index, axis in ipairs(producer.axes or {}) do
            out[#out + 1] = indent .. "local __ml_extent" .. tostring(axis_index) .. " = " .. range_nd_extent_expr(axis)
        end
    end

    local function emit_range_nd_axis_loops(out, producer, axis_indices, indent, body)
        local function nest(pos, current_indent)
            if pos > #axis_indices then
                body(current_indent)
                return
            end
            local axis_index = axis_indices[pos]
            local axis = producer.axes[axis_index]
            out[#out + 1] = current_indent
                .. "for __ml_axis" .. tostring(axis_index)
                .. " = " .. tostring(axis.start_param)
                .. ", " .. tostring(axis.stop_param) .. " - 1"
                .. ", " .. tostring(tonumber(axis.step) or 1) .. " do"
            nest(pos + 1, current_indent .. "    ")
            out[#out + 1] = current_indent .. "end"
        end
        nest(1, indent)
    end

    local function range_nd_all_axes(producer)
        local axes = {}
        for axis_index = 1, #(producer.axes or {}) do axes[#axes + 1] = axis_index end
        return axes
    end

    local function axis_ref_set(axes)
        local set = {}
        for _, axis in ipairs(axes or {}) do set[tonumber(axis.index)] = true end
        return set
    end

    local function complement_axis_list(producer, selected)
        local out = {}
        for axis_index = 1, #(producer.axes or {}) do
            if not selected[axis_index] then out[#out + 1] = axis_index end
        end
        return out
    end

    local function selected_axis_list(producer, selected)
        local out = {}
        for axis_index = 1, #(producer.axes or {}) do
            if selected[axis_index] then out[#out + 1] = axis_index end
        end
        return out
    end

    local function emit_range_nd_loop(out, producer, body)
        emit_range_nd_extents(out, producer, "    ")
        emit_range_nd_axis_loops(out, producer, range_nd_all_axes(producer), "    ", function(indent)
            out[#out + 1] = indent .. "local __ml_i = " .. range_nd_linear_index_expr(producer)
            body("__ml_i", indent)
        end)
    end

    local function emit_forward_loop(out, artifact_plan, body)
        local producer = artifact_plan.shape.producer
        if producer:luatrace_emit_loop(out, body) then return end
        local plan = artifact_plan.loop_plan
        local stride, group, reason = plan.domain_stride, plan.group, plan.reason
        if group <= 1 then
            out[#out + 1] = "    for i = start, stop - 1, " .. tostring(stride) .. " do"
            body("i", "        ")
            out[#out + 1] = "    end"
            return
        end
        out[#out + 1] = "    -- luatrace schedule: " .. reason .. " factor=" .. tostring(group)
        out[#out + 1] = "    local __ml_i = start"
        if plan.tail_strategy == "no_tail_trip_count_multiple" then
            out[#out + 1] = "    local __ml_stop_group = stop"
        else
            out[#out + 1] = "    local __ml_stop_group = stop - ((stop - start) % " .. tostring(group) .. ")"
        end
        out[#out + 1] = "    while __ml_i < __ml_stop_group do"
        for lane = 0, group - 1 do
            body(lane == 0 and "__ml_i" or ("__ml_i + " .. tostring(lane)), "        ")
        end
        out[#out + 1] = "        __ml_i = __ml_i + " .. tostring(group)
        out[#out + 1] = "    end"
        if plan.tail_strategy ~= "no_tail_trip_count_multiple" then
            out[#out + 1] = "    for i = __ml_i, stop - 1, 1 do"
            body("i", "        ")
            out[#out + 1] = "    end"
        end
    end

    function Stencil.StencilProducerExecution:luatrace_emit_loop(_out, _body)
        return false
    end

    function Stencil.StencilProducerExecRangeND:luatrace_emit_loop(out, body)
        emit_range_nd_loop(out, self, body)
        return true
    end

    local function emit_range_nd_axis_reduce(out, artifact_plan, body_expr)
        local shape = artifact_plan.shape
        local producer = shape.producer
        local dst_name = assert(shape.reduce_scope.dst_name, "residual_luatrace: axis reduce needs destination")
        local dst_access = assert(artifact_plan.access_plans:access_named(dst_name), "missing axis reduce destination access plan")
        local reduce_axes = axis_ref_set(shape.reduce_scope.axes)
        local keep_axes = {}
        for axis_index = 1, #(producer.axes or {}) do keep_axes[axis_index] = not reduce_axes[axis_index] end
        local outer_axes = complement_axis_list(producer, reduce_axes)
        local inner_axes = selected_axis_list(producer, reduce_axes)
        emit_range_nd_extents(out, producer, "    ")
        emit_range_nd_axis_loops(out, producer, outer_axes, "    ", function(outer_indent)
            out[#out + 1] = outer_indent .. "local acc = " .. tostring(iconst(shape.identity))
            emit_range_nd_axis_loops(out, producer, inner_axes, outer_indent, function(inner_indent)
                local i = range_nd_linear_index_expr(producer)
                out[#out + 1] = inner_indent .. "local __ml_i = " .. i
                out[#out + 1] = inner_indent .. "acc = " .. lua_reduce_expr(shape.reduction, "acc", body_expr("__ml_i"), shape.result_ty)
            end)
            local out_i = range_nd_projected_index_expr(producer, keep_axes)
            out[#out + 1] = outer_indent .. lua_access_ref(dst_access, dst_name, out_i) .. " = acc"
        end)
    end

    function Stencil.StencilReduceExecutionScope:luatrace_append_result_param(_params)
    end

    function Stencil.StencilReduceExecAxes:luatrace_append_result_param(params)
        params[#params + 1] = self.dst_name
    end

    function Stencil.StencilReduceExecWindow:luatrace_append_result_param(params)
        params[#params + 1] = self.dst_name
    end

    function Stencil.StencilReduceExecutionScope:luatrace_emit_axis_reduce(_out, _artifact_plan, _body_expr)
        return false
    end

    function Stencil.StencilReduceExecAxes:luatrace_emit_axis_reduce(out, artifact_plan, body_expr)
        emit_range_nd_axis_reduce(out, artifact_plan, body_expr)
        return true
    end

    function Stencil.StencilProducerExecution:luatrace_emit_axis_reduce(_out, _artifact_plan, _body_expr)
        return false
    end

    function Stencil.StencilProducerExecRangeND:luatrace_emit_axis_reduce(out, artifact_plan, body_expr)
        return artifact_plan.shape.reduce_scope:luatrace_emit_axis_reduce(out, artifact_plan, body_expr)
    end

    local function emit_range_nd_axis_scan(out, artifact_plan, body_expr)
        local shape = artifact_plan.shape
        local producer = shape.producer
        local axis_index = tonumber(shape.axis and shape.axis.index) or 1
        local scan_axes = { [axis_index] = true }
        local outer_axes = complement_axis_list(producer, scan_axes)
        local dst_access = assert(artifact_plan.access_plans:access_named("dst"), "missing scan destination access plan")
        emit_range_nd_extents(out, producer, "    ")
        emit_range_nd_axis_loops(out, producer, outer_axes, "    ", function(outer_indent)
            out[#out + 1] = outer_indent .. "local acc = init"
            emit_range_nd_axis_loops(out, producer, { axis_index }, outer_indent, function(inner_indent)
                out[#out + 1] = inner_indent .. "local __ml_i = " .. range_nd_linear_index_expr(producer)
                if shape.mode == Stencil.StencilScanExclusive then
                    out[#out + 1] = inner_indent .. lua_access_ref(dst_access, "dst", "__ml_i") .. " = acc"
                    out[#out + 1] = inner_indent .. "acc = " .. lua_reduce_expr(shape.reduction, "acc", body_expr("__ml_i"), shape.result_ty)
                else
                    out[#out + 1] = inner_indent .. "acc = " .. lua_reduce_expr(shape.reduction, "acc", body_expr("__ml_i"), shape.result_ty)
                    out[#out + 1] = inner_indent .. lua_access_ref(dst_access, "dst", "__ml_i") .. " = acc"
                end
            end)
        end)
    end

    function Stencil.StencilProducerExecution:luatrace_emit_axis_scan(_out, _artifact_plan, _body_expr)
        return false
    end

    function Stencil.StencilProducerExecRangeND:luatrace_emit_axis_scan(out, artifact_plan, body_expr)
        emit_range_nd_axis_scan(out, artifact_plan, body_expr)
        return true
    end

    function Stencil.StencilReduceInitMode:luatrace_append_init_param(_params)
    end

    function Stencil.StencilReduceInitExternal:luatrace_append_init_param(params)
        params[#params + 1] = "init"
    end

    function Stencil.StencilReduceInitMode:luatrace_initial_expr(shape)
        return tostring(iconst(shape.identity))
    end

    function Stencil.StencilReduceInitExternal:luatrace_initial_expr(_shape)
        return "init"
    end

    function Stencil.StencilStoreSemantics:luatrace_emit_overlap_copy(_shape, _out, _artifact_plan, _dst_access, _dst_name, _stride)
        return false
    end

    function Stencil.StencilStoreCopy:luatrace_emit_overlap_copy(shape, out, artifact_plan, dst_access, dst_name, stride)
        local src_name = shape.expr:luatrace_input_name()
        if src_name == nil then return false end
        if not shape.producer:luatrace_is_linear_range() then return false end
        if self.semantics ~= Stencil.StencilCopyMemMove and self.semantics ~= Stencil.StencilCopyMayOverlapBackward then return false end
        local access = artifact_plan.access_plans
        local function emit_copy_loop(reverse)
            if reverse then
                out[#out + 1] = "        for i = stop - 1, start, -" .. tostring(stride) .. " do"
            else
                out[#out + 1] = "        for i = start, stop - 1, " .. tostring(stride) .. " do"
            end
            out[#out + 1] = "            " .. lua_access_ref(dst_access, dst_name, "i") .. " = " .. lua_point_expr(shape.expr, artifact_plan.descriptor, access, "i")
            out[#out + 1] = "        end"
        end
        if self.semantics == Stencil.StencilCopyMayOverlapBackward then
            out[#out + 1] = "    do"
            emit_copy_loop(true)
            out[#out + 1] = "    end"
            return true
        end
        out[#out + 1] = "    if " .. dst_name .. " < " .. src_name .. " then"
        emit_copy_loop(false)
        out[#out + 1] = "    else"
        emit_copy_loop(true)
        out[#out + 1] = "    end"
        return true
    end

    function LT.LTPrimitivePolicy:luatrace_comment_name()
        return "none"
    end

    function LT.LTPrimitiveFfiCopy:luatrace_comment_name()
        return "ffi_copy"
    end

    function LT.LTPrimitiveFfiFill:luatrace_comment_name()
        return "ffi_fill"
    end

    function LT.LTPredicatePolicy:luatrace_comment_name()
        return "none"
    end

    function LT.LTPredicateLuaSelect:luatrace_comment_name()
        return "lua_select"
    end

    function LT.LTPredicateNumericStore:luatrace_comment_name()
        return "numeric_store"
    end

    function LT.LTPredicateBranch:luatrace_comment_name()
        return "branch"
    end

    function LT.LTPredicateMultiCounterBranch:luatrace_comment_name()
        return "multi_counter_branch"
    end

    function LT.LTScatterPolicy:luatrace_comment_name()
        return "none"
    end

    function LT.LTScatterUniqueIndices:luatrace_comment_name()
        return "unique_indices"
    end

    function LT.LTScatterOrderedLastWrite:luatrace_comment_name()
        return "ordered_last_write"
    end

    function LT.LTScatterConflictUndefined:luatrace_comment_name()
        return "conflict_undefined"
    end

    function LT.LTScatterUnknown:luatrace_comment_name()
        return "unknown"
    end

    function LT.LTReductionPolicy:luatrace_comment_name()
        return "none"
    end

    function LT.LTReductionOrderedSingleAccumulator:luatrace_comment_name()
        return "ordered_single_accumulator"
    end

    function LT.LTPrimitivePolicy:luatrace_emit_store(_out, _dst_name)
        return false
    end

    function LT.LTPrimitiveFfiCopy:luatrace_emit_store(out, _dst_name)
        out[#out + 1] = "    local __ml_n = stop - start"
        out[#out + 1] = "    if __ml_n > 0 then ffi.copy(" .. self.dst_name .. " + start, " .. self.src_name .. " + start, __ml_n * " .. tostring(self.bytes_per_element) .. ") end"
        return true
    end

    function LT.LTPrimitiveFfiFill:luatrace_emit_store(out, _dst_name)
        out[#out + 1] = "    local __ml_n = stop - start"
        out[#out + 1] = "    if __ml_n > 0 then ffi.fill(" .. self.dst_name .. " + start, __ml_n, " .. self.value_name .. ") end"
        return true
    end

    function Stencil.StencilArtifactShape:luatrace_emit_body(_out, _artifact_plan)
        error("residual_luatrace: unsupported stencil shape", 3)
    end

    function Stencil.StencilArtifactStoreN:luatrace_emit_body(out, artifact_plan)
        local access = artifact_plan.access_plans
        local kernel_plan = artifact_plan.kernel_plan
        local stride = tonumber(self.stride) or 1
        local dst_name = self.dst_name or "dst"
        local dst_access = assert(access:access_named(dst_name), "missing destination access plan")
        local scalar_params = {}
        local input_params = {}
        for _, input in ipairs(self.inputs or {}) do
            if input.name ~= dst_name then
                if input.layout:luatrace_is_scalar_layout() then
                    scalar_params[#scalar_params + 1] = input.name
                else
                    input_params[#input_params + 1] = input.name
                end
            end
        end
        local params = { dst_name }
        for i = 1, #input_params do params[#params + 1] = input_params[i] end
        append_producer_params(params, self.producer)
        for i = 1, #scalar_params do params[#params + 1] = scalar_params[i] end
        out[#out + 1] = fn_header(artifact_plan.artifact, params)
        if kernel_plan.primitive:luatrace_emit_store(out, dst_name) then
            return
        elseif self.store_mode:luatrace_emit_overlap_copy(self, out, artifact_plan, dst_access, dst_name, stride) then
            return
        else
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent
                    .. lua_access_ref(dst_access, dst_name, i)
                    .. " = "
                    .. lua_point_expr(self.expr, artifact_plan.descriptor, access, i)
            end)
        end
    end

    function Stencil.StencilArtifactReduceN:luatrace_emit_body(out, artifact_plan)
        local access = artifact_plan.access_plans
        local params = {}
        self.reduce_scope:luatrace_append_result_param(params)
        for _, input in ipairs(self.inputs or {}) do params[#params + 1] = input.name end
        append_producer_params(params, self.producer)
        self.init_mode:luatrace_append_init_param(params)
        out[#out + 1] = fn_header(artifact_plan.artifact, params)
        if self.producer:luatrace_emit_axis_reduce(out, artifact_plan, function(i)
            return lua_point_expr(self.expr, artifact_plan.descriptor, access, i)
        end) then
            return
        end
        out[#out + 1] = "    local acc = " .. self.init_mode:luatrace_initial_expr(self)
        emit_forward_loop(out, artifact_plan, function(i, indent)
            out[#out + 1] = indent .. "acc = " .. lua_reduce_expr(self.reduction, "acc", lua_point_expr(self.expr, artifact_plan.descriptor, access, i), self.result_ty)
        end)
        out[#out + 1] = "    return acc"
    end

    function Stencil.StencilArtifactFindN:luatrace_emit_body(out, artifact_plan)
        local access = artifact_plan.access_plans
        local params = {}
        for _, input in ipairs(self.inputs or {}) do params[#params + 1] = input.name end
        append_producer_params(params, self.producer)
        out[#out + 1] = fn_header(artifact_plan.artifact, params)
        emit_forward_loop(out, artifact_plan, function(i, indent)
            out[#out + 1] = indent .. "if " .. lua_point_expr(self.expr, artifact_plan.descriptor, access, i) .. " ~= 0 then return " .. i .. " end"
        end)
        out[#out + 1] = "    return " .. tostring(iconst(self.not_found))
    end

    function Stencil.StencilArtifactPartitionN:luatrace_emit_body(out, artifact_plan)
        local access = artifact_plan.access_plans
        local dst_name = self.dst_name or "dst"
        local dst_access = assert(access:access_named(dst_name), "missing destination access plan")
        local xs_access = assert(access:access_named("xs"), "missing xs access plan")
        local params = { dst_name }
        for _, input in ipairs(self.inputs or {}) do
            if input.name ~= dst_name then params[#params + 1] = input.name end
        end
        append_producer_params(params, self.producer)
        out[#out + 1] = fn_header(artifact_plan.artifact, params)
        out[#out + 1] = "    local out_i = start"
        emit_forward_loop(out, artifact_plan, function(i, indent)
            local x = lua_access_ref(xs_access, "xs", i)
            out[#out + 1] = indent .. "if " .. lua_point_expr(self.expr, artifact_plan.descriptor, access, i) .. " ~= 0 then " .. lua_access_ref(dst_access, dst_name, "out_i") .. " = " .. x .. "; out_i = out_i + 1 end"
        end)
        out[#out + 1] = "    local split = out_i"
        emit_forward_loop(out, artifact_plan, function(i, indent)
            local x = lua_access_ref(xs_access, "xs", i)
            out[#out + 1] = indent .. "if " .. lua_point_expr(self.expr, artifact_plan.descriptor, access, i) .. " == 0 then " .. lua_access_ref(dst_access, dst_name, "out_i") .. " = " .. x .. "; out_i = out_i + 1 end"
        end)
        out[#out + 1] = "    return split"
    end

    function Stencil.StencilArtifactScanN:luatrace_emit_body(out, artifact_plan)
        local access = artifact_plan.access_plans
        local dst_access = assert(access:access_named("dst"), "missing dst access plan")
        local params = { "dst" }
        for _, input in ipairs(self.inputs or {}) do params[#params + 1] = input.name end
        append_producer_params(params, self.producer)
        params[#params + 1] = "init"
        out[#out + 1] = fn_header(artifact_plan.artifact, params)
        if self.producer:luatrace_emit_axis_scan(out, artifact_plan, function(i)
            return lua_point_expr(self.expr, artifact_plan.descriptor, access, i)
        end) then
            return
        end
        out[#out + 1] = "    local acc = init"
        emit_forward_loop(out, artifact_plan, function(i, indent)
            if self.mode == Stencil.StencilScanExclusive then
                out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = acc"
                out[#out + 1] = indent .. "acc = " .. lua_reduce_expr(self.reduction, "acc", lua_point_expr(self.expr, artifact_plan.descriptor, access, i), self.result_ty)
            else
                out[#out + 1] = indent .. "acc = " .. lua_reduce_expr(self.reduction, "acc", lua_point_expr(self.expr, artifact_plan.descriptor, access, i), self.result_ty)
                out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = acc"
            end
        end)
        out[#out + 1] = "    return acc"
    end

    function Stencil.StencilArtifactScatterReduceN:luatrace_emit_body(out, artifact_plan)
        if not scatter_reduce_conflicts_materialized(self.conflicts) then
            error("residual_luatrace: unsupported scatter-reduce conflict semantics", 3)
        end
        local access = artifact_plan.access_plans
        local dst_name = self.dst_name or "dst"
        local dst_access = assert(access:access_named(dst_name), "missing scatter-reduce destination access plan")
        local params = { dst_name }
        for _, a in ipairs(ArtifactPlan.descriptor_accesses(artifact_plan.descriptor)) do
            if a.name ~= dst_name and not a.layout:luatrace_is_scalar_layout() then
                params[#params + 1] = a.name
            end
        end
        append_producer_params(params, self.producer)
        out[#out + 1] = fn_header(artifact_plan.artifact, params)
        emit_forward_loop(out, artifact_plan, function(i, indent)
            local slot = lua_access_ref(dst_access, dst_name, i)
            out[#out + 1] = indent .. slot .. " = " .. lua_reduce_expr(self.reduction, slot, lua_point_expr(self.expr, artifact_plan.descriptor, access, i), self.result_ty)
        end)
    end

    local function emit_lua_function(artifact)
        local artifact_plan = build_artifact_plan(artifact)
        local shape = artifact_plan.shape
        local trace_plan = artifact_plan.loop_plan
        local kernel_plan = artifact_plan.kernel_plan
        local out = {}
        out[#out + 1] = "-- " .. artifact.instance.id.text
        out[#out + 1] = "-- luatrace plan: " .. trace_plan.reason .. " group=" .. tostring(trace_plan.group) .. " tail=" .. tostring(trace_plan.tail_strategy) .. " primitive=" .. kernel_plan.primitive:luatrace_comment_name() .. " predicate=" .. kernel_plan.predicate:luatrace_comment_name() .. " scatter=" .. kernel_plan.scatter:luatrace_comment_name() .. " reduction=" .. kernel_plan.reduction:luatrace_comment_name()
        shape:luatrace_emit_body(out, artifact_plan)

        out[#out + 1] = "end"
        out[#out + 1] = "__lalin_luajit_stencil_symbols[" .. lua_string(artifact.symbol.text) .. "] = " .. sanitize(artifact.symbol.text)
        for i = 1, #out do
            if type(out[i]) ~= "string" then
                local detail = {}
                for k, v in pairs(out[i]) do detail[#detail + 1] = tostring(k) .. "=" .. tostring(v) end
                error("residual_luatrace: emitted non-string fragment " .. tostring(i) .. " for " .. tostring(artifact.symbol.text) .. ": " .. tostring(out[i]) .. " {" .. table.concat(detail, ",") .. "}", 3)
            end
        end
        return table.concat(out, "\n")
    end

    function api.bc_artifact(artifact)
        return with_realized(artifact, Stencil.StencilProviderLuaTrace, realized_bc_schedule(artifact))
    end

    function api.plan_artifact(artifact)
        return build_artifact_plan(artifact)
    end

    local function bc_stencil_source(artifact)
        return table.concat({
            "local __lalin_luajit_stencil_symbols = {}",
            "do",
            emit_lua_function(artifact),
            "end",
            "return __lalin_luajit_stencil_symbols[" .. lua_string(artifact.symbol.text) .. "]",
        }, "\n") .. "\n"
    end

    function api.emit_mc_stencil_source(artifact)
        return bc_stencil_source(artifact)
    end

    local function bc_env()
        local bit = require("bit")
        local ffi = require("ffi")
        return {
            bit = bit,
            ffi = ffi,
            require = require,
            assert = assert,
            tonumber = tonumber,
            tostring = tostring,
            type = type,
            math = math,
            __ml_tobit = bit.tobit,
            __ml_band = bit.band,
            __ml_bor = bit.bor,
            __ml_bxor = bit.bxor,
            __ml_bnot = bit.bnot,
            __ml_lshift = bit.lshift,
            __ml_rshift = bit.rshift,
            __ml_arshift = bit.arshift,
            __ml_idiv = function(a, b)
                local q = a / b
                if q < 0 then return bit.tobit(math.ceil(q)) end
                return bit.tobit(math.floor(q))
            end,
            __ml_imod = function(a, b)
                local q = a / b
                if q < 0 then q = bit.tobit(math.ceil(q)) else q = bit.tobit(math.floor(q)) end
                return bit.tobit(a - q * b)
            end,
        }
    end

    function api.build_bc_bank(artifacts, opts)
        opts = opts or {}
        local metastencil_covers
        artifacts, metastencil_covers = Meta.normalize_artifact_inputs(artifacts or {})
        local entries = {}
        for _, artifact in ipairs(artifacts or {}) do
            artifact = api.bc_artifact(artifact)
            local symbol = artifact.symbol.text
            local entry, err = BCBank.compile_entry {
                id = tostring(opts.stem or "ljbc") .. ":" .. tostring(symbol),
                symbol = symbol,
                chunk_name = "@lalin_luajit_bc_stencil/" .. tostring(symbol),
                source = bc_stencil_source(artifact),
                artifact = artifact,
            }
            if entry == nil then return nil, err end
            entries[#entries + 1] = entry
        end
        local bank, err = BCBank.build_bank(entries, {
            id = opts.id or ((opts.stem or "ljbc") .. ":bank"),
            target = opts.target,
            metastencil_covers = metastencil_covers,
        })
        if bank == nil then return nil, err end
        return bank
    end

    function api.realize_bc_artifacts(artifacts, opts)
        opts = opts or {}
        local requested_inputs = artifacts or {}
        local metastencil_covers
        artifacts, metastencil_covers = Meta.normalize_artifact_inputs(requested_inputs)
        artifacts = artifacts or {}
        local bank = opts.bank
        if bank == nil then
            local err
            bank, err = api.build_bc_bank(requested_inputs, opts)
            if bank == nil then return nil, err end
        end
        local symbols = {}
        local installed = {}
        local env = opts.env or bc_env()
        for _, artifact in ipairs(artifacts) do
            local symbol = artifact.symbol.text
            local requested_artifact = api.bc_artifact(artifact)
            local entry = bank and BCBank.entry_by_symbol and BCBank.entry_by_symbol(bank, symbol) or nil
            if entry ~= nil then
                if entry.artifact == nil or entry.artifact.fingerprint == nil or entry.artifact.fingerprint.text == nil then
                    return nil, "residual_bc: bank entry missing artifact fingerprint for " .. tostring(symbol)
                end
                if requested_artifact.fingerprint == nil or requested_artifact.fingerprint.text == nil then
                    return nil, "residual_bc: requested artifact missing fingerprint for " .. tostring(symbol)
                end
                if entry.artifact.fingerprint.text ~= requested_artifact.fingerprint.text then
                    return nil, "residual_bc: artifact fingerprint mismatch for " .. tostring(symbol)
                end
            end
            local fn, err = BCBank.load_symbol(bank, symbol, {
                chunk_name = "@lalin_luajit_bc_stencil/load/" .. tostring(symbol),
                env = env,
            })
            if fn == nil then return nil, err end
            local installed_artifact = entry and entry.artifact or requested_artifact
            symbols[symbol] = fn
            installed[#installed + 1] = {
                symbol = symbol,
                artifact = installed_artifact,
                provider = Stencil.StencilProviderLuaTrace,
                materializer = "bc",
            }
        end
        return {
            kind = "BCStencilBankRealization",
            symbols = symbols,
            installed = installed,
            provider = Stencil.StencilProviderLuaTrace,
            materializer = "bc",
            bc_bank = bank,
            metastencil_covers = metastencil_covers or bank.metastencil_covers or {},
        }
    end

    local function target_check_source(target)
        local checks = {}
        checks[#checks + 1] = "assert(jit and jit.version == " .. lua_string(target.luajit_version) .. ", 'LuaTrace BC bank LuaJIT version mismatch')"
        checks[#checks + 1] = "assert(jit and jit.arch == " .. lua_string(target.arch) .. ", 'LuaTrace BC bank arch mismatch')"
        checks[#checks + 1] = "assert(jit and jit.os == " .. lua_string(target.os) .. ", 'LuaTrace BC bank os mismatch')"
        checks[#checks + 1] = "assert((ffi.abi('64bit') and 64 or 32) == " .. tostring(target.pointer_bits) .. ", 'LuaTrace BC bank pointer width mismatch')"
        if target.endian == "little" then
            checks[#checks + 1] = "assert(ffi.abi('le'), 'LuaTrace BC bank endian mismatch')"
        elseif target.endian == "big" then
            checks[#checks + 1] = "assert(ffi.abi('be'), 'LuaTrace BC bank endian mismatch')"
        end
        checks[#checks + 1] = "assert(ffi.abi('gc64') == " .. tostring(target.gc64) .. ", 'LuaTrace BC bank GC64 mismatch')"
        checks[#checks + 1] = "assert(ffi.abi('dualnum') == " .. tostring(target.dualnum) .. ", 'LuaTrace BC bank dualnum mismatch')"
        return table.concat(checks, "\n")
    end

    function api.emit_bc_bank_source(bank, opts)
        opts = opts or {}
        local out = {
            "-- Generated Lalin LuaTrace BC copy+compile residual bank.",
            "local bit = require('bit')",
            "local ffi = require('ffi')",
            target_check_source(bank.target),
            "local __lalin_luajit_stencil_symbols = __lalin_luajit_stencil_symbols or {}",
            "local __ml_bc_env = {",
            "  bit = bit,",
            "  ffi = ffi,",
            "  require = require,",
            "  assert = assert,",
            "  tonumber = tonumber,",
            "  tostring = tostring,",
            "  type = type,",
            "  math = math,",
            "  __ml_tobit = bit.tobit,",
            "  __ml_band = bit.band,",
            "  __ml_bor = bit.bor,",
            "  __ml_bxor = bit.bxor,",
            "  __ml_bnot = bit.bnot,",
            "  __ml_lshift = bit.lshift,",
            "  __ml_rshift = bit.rshift,",
            "  __ml_arshift = bit.arshift,",
            "  __ml_idiv = function(a, b)",
            "    local q = a / b",
            "    if q < 0 then return bit.tobit(math.ceil(q)) end",
            "    return bit.tobit(math.floor(q))",
            "  end,",
            "  __ml_imod = function(a, b)",
            "    local q = a / b",
            "    if q < 0 then q = bit.tobit(math.ceil(q)) else q = bit.tobit(math.floor(q)) end",
            "    return bit.tobit(a - q * b)",
            "  end,",
            "}",
            "local function __ml_load_bc(symbol, bytes, chunk_name)",
            "  local fn, err = loadstring(bytes, chunk_name)",
            "  if fn == nil then error(err, 2) end",
            "  setfenv(fn, __ml_bc_env)",
            "  __lalin_luajit_stencil_symbols[symbol] = fn",
            "end",
        }
        for _, entry in ipairs(bank.entries or {}) do
            out[#out + 1] = "__ml_load_bc(" .. lua_string(entry.symbol) .. ", " .. lua_string(entry.bytecode) .. ", " .. lua_string(entry.chunk_name) .. ")"
        end
        return table.concat(out, "\n") .. "\n"
    end

    function api.compile_artifact(artifact)
        local realization, err = api.realize_bc_artifacts({ artifact }, {
            stem = "compile_artifact",
        })
        if realization == nil then error(tostring(err), 2) end
        return assert(realization.symbols[artifact.symbol.text], artifact.symbol.text)
    end

    function api.realize_artifacts(artifacts)
        local realization, err = api.realize_bc_artifacts(artifacts)
        return assert(realization, err or "LuaTrace bytecode realization failed")
    end

    T._lalin_api_cache.residual_luatrace = api
    return api
end

return bind_context
