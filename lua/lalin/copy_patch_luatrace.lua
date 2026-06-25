local pvm = require("lalin.pvm")
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
    if T._lalin_api_cache.copy_patch_luatrace ~= nil then return T._lalin_api_cache.copy_patch_luatrace end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Stencil = T.LalinStencil
    local LT = T.LalinLuaTrace
    local ArtifactPlan = require("lalin.stencil_artifact_plan")(T)
    local Meta = require("lalin.stencil_metastencil")(T)
    local BCBank = require("lalin.copy_patch_bc")(T)

    local api = {}

    local function is_int_ty(ty)
        return pvm.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function elem_bytes(ty)
        local cls = pvm.classof(ty)
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
        if pvm.classof(expr) == Value.ValueExprConst then
            local k = expr.const or expr.value
            if pvm.classof(k) == Code.CodeConstLiteral then
                local lit = k.literal or k.value
                if pvm.classof(lit) == Core.LitInt then return tonumber(lit.raw or lit.text) end
                if pvm.classof(lit) == Core.LitFloat then return tonumber(lit.raw or lit.text) end
                if pvm.classof(lit) == Core.LitBool then return lit.value and 1 or 0 end
            end
        end
        error("copy_patch_luatrace: unsupported constant expression", 3)
    end

    local function access_ref_name(ref)
        return ref and ref.name or nil
    end

    local function fact_map(facts)
        local out = {}
        for _, fact in ipairs(facts and facts.access_facts or {}) do
            out[access_ref_name(fact.access)] = fact
        end
        return out
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

    local function access_kind(topology)
        local cls = pvm.classof(topology)
        if cls == Stencil.StencilTopologyContiguous then return "contiguous" end
        if cls == Stencil.StencilTopologyIndexed then return "indexed" end
        if cls == Stencil.StencilTopologyInPlace then return "in_place" end
        if cls == Stencil.StencilTopologyFieldProjection then return "field_projection" end
        if cls == Stencil.StencilTopologySoAComponent then return "soa_component" end
        if cls == Stencil.StencilTopologySliceDescriptor then return "slice_descriptor" end
        if cls == Stencil.StencilTopologyByteSpanDescriptor then return "byte_span_descriptor" end
        if cls == Stencil.StencilTopologyViewDescriptor then
            return topology.stride_const ~= nil and "view_const_stride" or "view_dynamic_stride"
        end
        if cls == Stencil.StencilTopologyScalar then return "scalar" end
        return "unknown"
    end

    local function plain_bulk_access(topology)
        local cls = pvm.classof(topology)
        if cls == Stencil.StencilTopologyContiguous then return tonumber(topology.stride) == 1 end
        if cls == Stencil.StencilTopologyInPlace then return tonumber(topology.stride) == 1 end
        if cls == Stencil.StencilTopologySliceDescriptor then return true end
        if cls == Stencil.StencilTopologyByteSpanDescriptor then return true end
        if cls == Stencil.StencilTopologyViewDescriptor then return tonumber(topology.stride_const) == 1 end
        return false
    end

    local function build_access_plan(access, facts_by_name)
        local fact = facts_by_name and facts_by_name[access.name] or nil
        local top = access.topology
        local cls = pvm.classof(top)
        local plan = {
            kind = access_kind(top),
            name = access.name,
            safe_name = sanitize(access.name),
            role = access.role,
            ty = access.ty,
            topology = top,
            readonly = fact ~= nil and fact.readonly or access.role == Stencil.StencilAccessRead,
            readwrite = access.role == Stencil.StencilAccessReadWrite,
            alignment_fact = fact and fact.alignment or Stencil.StencilAlignmentUnknown,
            unit_stride = fact and fact.unit_stride or false,
            dynamic_stride_arg = nil,
            stride_const = nil,
            field_name = nil,
            field_offset = nil,
            component_index = nil,
            parent = nil,
            can_pointer_bump = false,
            can_bulk_copy = false,
            can_bulk_fill = false,
        }
        plan.element_bytes = elem_bytes(access.ty)
        if plain_bulk_access(top) and plan.element_bytes ~= nil then
            plan.can_bulk_copy = true
            plan.can_bulk_fill = plan.element_bytes == 1
        end
        if cls == Stencil.StencilTopologyFieldProjection then
            plan.field_name = top.field_name
            plan.field_offset = top.field_offset
            plan.parent = build_access_plan({ name = access.name, role = access.role, ty = access.ty, topology = top.parent }, facts_by_name)
        elseif cls == Stencil.StencilTopologySoAComponent then
            plan.field_name = top.field_name
            plan.component_index = top.component_index
            plan.parent = build_access_plan({ name = access.name, role = access.role, ty = access.ty, topology = top.parent }, facts_by_name)
        elseif cls == Stencil.StencilTopologyViewDescriptor then
            plan.stride_const = top.stride_const
            plan.dynamic_stride_arg = top.stride_const == nil and (sanitize(access.name) .. "_stride") or nil
        end
        return plan
    end

    local function build_access_plans(desc, facts)
        local by_name = {}
        local list = {}
        local facts_by_name = fact_map(facts)
        for _, access in ipairs(ArtifactPlan.descriptor_accesses(desc)) do
            local plan = build_access_plan(access, facts_by_name)
            list[#list + 1] = plan
            by_name[access.name] = plan
        end
        return list, by_name
    end

    local function lua_access_offset(plan, index)
        local top = plan.topology
        local cls = pvm.classof(top)
        if cls == Stencil.StencilTopologyFieldProjection then
            return lua_access_offset(plan.parent, index)
        end
        if cls == Stencil.StencilTopologySoAComponent then
            return lua_access_offset(plan.parent, index)
        end
        if cls == Stencil.StencilTopologyViewDescriptor then
            local stride = plan.stride_const or plan.dynamic_stride_arg
            if tonumber(stride) == 1 then return index end
            return "((" .. index .. ") * " .. tostring(stride) .. ")"
        end
        return index
    end

    local function lua_access_ref(plan, base, index)
        local top = plan.topology
        local cls = pvm.classof(top)
        if cls == Stencil.StencilTopologyFieldProjection then
            return base .. "[" .. lua_access_offset(plan.parent, index) .. "]." .. sanitize(top.field_name)
        end
        if cls == Stencil.StencilTopologySoAComponent then
            return base .. "[" .. lua_access_offset(plan.parent, index) .. "]"
        end
        return base .. "[" .. lua_access_offset(plan, index) .. "]"
    end

    local function lua_unary_expr(op, v, ty, int_semantics, float_mode)
        if op == Stencil.StencilUnaryIdentity then return v end
        if op == Stencil.StencilUnaryNeg then return lua_int_expr(ty, "(-" .. v .. ")") end
        if op == Stencil.StencilUnaryBitNot then return "__ml_bnot(" .. v .. ")" end
        if op == Stencil.StencilUnaryBoolNot then return "((" .. v .. ") == 0 and 1 or 0)" end
        error("copy_patch_luatrace: unsupported unary op", 3)
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
            if not is_int_ty(ty) then error("copy_patch_luatrace: modulo requires integer type", 3) end
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
        error("copy_patch_luatrace: unsupported binary op", 3)
    end

    local function lua_reduce_expr(kind, acc, item, ty)
        if kind == Value.ReductionAdd then return lua_int_expr(ty, "((" .. acc .. ") + (" .. item .. "))") end
        if kind == Value.ReductionMul then return lua_int_expr(ty, "((" .. acc .. ") * (" .. item .. "))") end
        if kind == Value.ReductionAnd then return "__ml_band(" .. acc .. ", " .. item .. ")" end
        if kind == Value.ReductionOr then return "__ml_bor(" .. acc .. ", " .. item .. ")" end
        if kind == Value.ReductionXor then return "__ml_bxor(" .. acc .. ", " .. item .. ")" end
        if kind == Value.ReductionMin then return "((" .. item .. ") < (" .. acc .. ") and (" .. item .. ") or (" .. acc .. "))" end
        if kind == Value.ReductionMax then return "((" .. item .. ") > (" .. acc .. ") and (" .. item .. ") or (" .. acc .. "))" end
        error("copy_patch_luatrace: unsupported reduction", 3)
    end

    local lua_cmp_expr

    local function lua_pred_expr(p, v)
        local cls = pvm.classof(p)
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
        error("copy_patch_luatrace: unsupported predicate", 3)
    end

    lua_cmp_expr = function(op, a, b)
        if op == Core.CmpEq then return "(" .. a .. " == " .. b .. ")" end
        if op == Core.CmpNe then return "(" .. a .. " ~= " .. b .. ")" end
        if op == Core.CmpLt then return "(" .. a .. " < " .. b .. ")" end
        if op == Core.CmpLe then return "(" .. a .. " <= " .. b .. ")" end
        if op == Core.CmpGt then return "(" .. a .. " > " .. b .. ")" end
        if op == Core.CmpGe then return "(" .. a .. " >= " .. b .. ")" end
        error("copy_patch_luatrace: unsupported compare op", 3)
    end

    local function is_i32_signed(ty)
        return pvm.classof(ty) == Code.CodeTyInt and tonumber(ty.bits) == 32 and ty.signedness == Code.CodeSigned
    end

    local function is_u8(ty)
        return pvm.classof(ty) == Code.CodeTyInt and tonumber(ty.bits) == 8 and ty.signedness == Code.CodeUnsigned
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
        local cls = pvm.classof(pred)
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
        local cls = pvm.classof(schedule)
        if cls == Stencil.StencilScheduleAutoVector or cls == Stencil.StencilScheduleUnrolled or cls == Stencil.StencilScheduleVector then return schedule.facts end
        return nil
    end

    local function trip_count_multiple_of(facts, group)
        if facts == nil or group <= 1 then return false end
        local trip = facts.trip_count
        local cls = pvm.classof(trip)
        if cls == Stencil.StencilTripCountMultipleOf then
            local factor = tonumber(trip.factor) or 1
            return factor >= group and factor % group == 0
        end
        if cls == Stencil.StencilTripCountExact then
            local count = tonumber(trip.count) or 0
            return count >= 0 and count % group == 0
        end
        return false
    end

    local function facts_unit_stride(desc, facts)
        if facts == nil then return false end
        local facts_by_name = fact_map(facts)
        local saw_memory_access = false
        for _, access in ipairs(ArtifactPlan.descriptor_accesses(desc)) do
            if pvm.classof(access.topology) ~= Stencil.StencilTopologyScalar then
                local fact = facts_by_name[access.name]
                if fact == nil or not fact.unit_stride then return false end
                saw_memory_access = true
            end
        end
        return saw_memory_access
    end

    local function kind_group_cap(shape)
        local kind = shape.kind
        if kind == "reduce_array" or kind == "scan_array" then return 16 end
        if kind == "map_array" or kind == "zip_map_array" or kind == "select_array" or kind == "apply_n_array" or kind == "copy_array" or kind == "fill_array" or kind == "cast_array" then return 8 end
        if kind == "in_place_map_array" or kind == "reduce_n_array" then return 8 end
        if kind == "compare_array" or kind == "zip_compare_array" or kind == "count_array" then return 4 end
        if kind == "scatter_array" and shape.conflicts == Stencil.StencilScatterUniqueIndices then return 4 end
        return 1
    end

    local function autovector_group(desc, shape, facts)
        if not facts_unit_stride(desc, facts) then return 1, "autovector_blocked_non_unit_stride" end
        return kind_group_cap(shape), "autovector_trace_group"
    end

    local function build_loop_plan(desc, schedule, shape)
        local stride = tonumber(shape.stride) or 1
        local group, reason = 1, "scalar"
        if stride ~= 1 then
            return { domain_stride = stride, group = 1, reason = "domain_stride", tail_strategy = "generic_tail_loop", loop_shape = "scalar_for" }
        end
        local cls = pvm.classof(schedule)
        if cls == Stencil.StencilScheduleVector then
            local lanes = math.max(1, math.floor(tonumber(ArtifactPlan.schedule_lane_count(schedule)) or 1))
            local unroll = math.max(1, math.floor(tonumber(schedule.vector_unroll) or 1))
            local interleave = math.max(1, math.floor(tonumber(schedule.interleave) or 1))
            group, reason = math.max(1, lanes * unroll * interleave), "vector_as_trace_group"
        elseif cls == Stencil.StencilScheduleUnrolled then
            group, reason = math.max(1, math.floor(tonumber(schedule.factor) or 1)), "unrolled_trace_group"
        elseif cls == Stencil.StencilScheduleAutoVector then
            group, reason = autovector_group(desc, shape, schedule_facts(schedule))
            local cap = kind_group_cap(shape)
            if #ArtifactPlan.dynamic_stride_accesses(desc) ~= 0 then cap = math.min(cap, 4) end
            if group > cap then
                group = cap
                reason = reason .. "_capped_" .. tostring(cap)
            end
        end
        local tail_strategy = "generic_tail_loop"
        if trip_count_multiple_of(schedule_facts(schedule), math.max(1, group)) then
            tail_strategy = "no_tail_trip_count_multiple"
        end
        return {
            domain_stride = stride,
            group = math.max(1, group),
            reason = reason,
            tail_strategy = tail_strategy,
            loop_shape = group > 1 and "grouped_while" or "scalar_for",
        }
    end

    local function build_predicate_plan(shape, access_by_name, loop_plan)
        if shape.kind == "count_array" then
            if loop_plan ~= nil and loop_plan.group > 1 then
                return {
                    kind = "multi_counter_branch",
                    counters = loop_plan.group,
                    rejected = "numeric_count_measured_slower",
                }
            end
            return {
                kind = "branch",
                rejected = "numeric_count_measured_slower",
            }
        end
        if shape.kind == "compare_array" then
            local xs = access_by_name.xs
            local numeric = xs ~= nil and lua_numeric_pred_expr(shape.pred, "__ml_x", xs.ty) ~= nil
            return {
                kind = numeric and "numeric_store" or "lua_select",
                rejected = numeric and "helper_branchless_measured_slower" or "numeric_predicate_unavailable",
            }
        end
        if shape.kind == "zip_compare_array" then
            local lhs, rhs = access_by_name.lhs, access_by_name.rhs
            local numeric = lhs ~= nil and rhs ~= nil and lua_numeric_cmp_expr(shape.cmp, "__ml_a", "__ml_b", lhs.ty, rhs.ty) ~= nil
            return {
                kind = numeric and "numeric_store" or "lua_select",
                rejected = numeric and "helper_branchless_measured_slower" or "numeric_compare_unavailable",
            }
        end
        if shape.kind == "select_array" then
            return {
                kind = "lua_select",
                rejected = "branchless_numeric_select_not_measured",
            }
        end
        return { kind = "none" }
    end

    local function build_scatter_plan(shape)
        if shape.kind ~= "scatter_array" then return nil end
        if shape.conflicts == Stencil.StencilScatterUniqueIndices then
            return { kind = "unique_indices", may_group = true }
        end
        if shape.conflicts == Stencil.StencilScatterLastWriteWins then
            return { kind = "ordered_last_write", may_group = false }
        end
        if shape.conflicts == Stencil.StencilScatterConflictUndefined then
            return { kind = "conflict_undefined", may_group = false }
        end
        return { kind = "unknown_conflicts", may_group = false }
    end

    local function build_reduction_plan(shape, facts)
        if shape.kind ~= "reduce_array" and shape.kind ~= "scan_array"
            and shape.kind ~= "reduce_n_array" then
            return nil
        end
        local arithmetic = facts and facts.arithmetic or nil
        local reassociable = arithmetic ~= nil and arithmetic.reduction_reassociable or false
        local float_mode = arithmetic and arithmetic.float_mode or shape.float_mode
        return {
            kind = "ordered_single_accumulator",
            reduction = shape.reduction,
            reassociation_required = false,
            reassociable = reassociable,
            int_semantics = arithmetic and arithmetic.int_semantics or shape.int_semantics,
            float_mode = float_mode,
            multi_accumulator = false,
            multi_accumulator_rejected = reassociable and "not_measured_faster_for_luatrace" or "reassociation_not_legal",
        }
    end

    local function build_kernel_plan(shape, access_by_name, facts, loop_plan)
        local primitive_plan = nil
        if shape.kind == "copy_array" then
            local dst, src = access_by_name.dst, access_by_name.src
            local no_overlap = shape.semantics == Stencil.StencilCopyNoOverlap
                or (dst ~= nil and src ~= nil and alias_relation(facts, "dst", "src") == Stencil.StencilAliasNoAlias)
            if no_overlap
                and dst ~= nil and src ~= nil
                and not dst.readonly and src.readonly
                and dst.can_bulk_copy and src.can_bulk_copy
                and dst.element_bytes == src.element_bytes then
                primitive_plan = {
                    kind = "ffi_copy",
                    bytes_per_element = dst.element_bytes,
                    no_overlap_source = shape.semantics == Stencil.StencilCopyNoOverlap and "copy_semantics" or "noalias_facts",
                }
            end
        elseif shape.kind == "fill_array" then
            local dst = access_by_name.dst
            if dst ~= nil and not dst.readonly and dst.can_bulk_fill then
                primitive_plan = {
                    kind = "ffi_fill",
                    bytes_per_element = dst.element_bytes,
                }
            end
        end
        return {
            kind = shape.kind,
            primitive_plan = primitive_plan,
            predicate_plan = build_predicate_plan(shape, access_by_name, loop_plan),
            scatter_plan = build_scatter_plan(shape),
            reduction_plan = build_reduction_plan(shape, facts),
        }
    end

    local function lua_apply_expr(expr, desc, access_by_name, index)
        local cls = pvm.classof(expr)
        if cls == Stencil.StencilApplyInput then
            local name = expr.access.name
            local access = assert(access_by_name[name], "copy_patch_luatrace: missing apply input access " .. tostring(name))
            if pvm.classof(access.topology) == Stencil.StencilTopologyScalar then return name end
            return lua_access_ref(access, name, index)
        end
        if cls == Stencil.StencilApplyConst then return tostring(iconst(expr.value)) end
        if cls == Stencil.StencilApplyUnary then
            return lua_unary_expr(expr.op, lua_apply_expr(expr.arg, desc, access_by_name, index), expr.result_ty, expr.int_semantics, expr.float_mode)
        end
        if cls == Stencil.StencilApplyBinary then
            return lua_binary_expr(
                expr.op,
                lua_apply_expr(expr.left, desc, access_by_name, index),
                lua_apply_expr(expr.right, desc, access_by_name, index),
                expr.result_ty,
                expr.int_semantics,
                expr.float_mode
            )
        end
        if cls == Stencil.StencilApplyCast then
            return lua_apply_expr(expr.arg, desc, access_by_name, index)
        end
        if cls == Stencil.StencilApplyPredicate then
            return "(" .. lua_pred_expr(expr.pred, lua_apply_expr(expr.arg, desc, access_by_name, index)) .. " and 1 or 0)"
        end
        if cls == Stencil.StencilApplyCompare then
            return "(" .. lua_cmp_expr(
                expr.cmp,
                lua_apply_expr(expr.left, desc, access_by_name, index),
                lua_apply_expr(expr.right, desc, access_by_name, index)
            ) .. " and 1 or 0)"
        end
        if cls == Stencil.StencilApplySelect then
            return "("
                .. lua_pred_expr(expr.pred, lua_apply_expr(expr.cond, desc, access_by_name, index))
                .. " and "
                .. lua_apply_expr(expr.then_expr, desc, access_by_name, index)
                .. " or "
                .. lua_apply_expr(expr.else_expr, desc, access_by_name, index)
                .. ")"
        end
        error("copy_patch_luatrace: unsupported apply expression", 3)
    end

    local function build_artifact_plan(artifact)
        local desc = artifact.instance.descriptor
        local shape = ArtifactPlan.artifact_shape(artifact)
        local schedule = artifact.instance.schedule
        local facts = schedule_facts(schedule)
        local access_plans, access_by_name = build_access_plans(desc, facts)
        local loop_plan = build_loop_plan(desc, schedule, shape)
        return {
            kind = "LuaTraceArtifactPlan",
            artifact = artifact,
            descriptor = desc,
            shape = shape,
            schedule = schedule,
            facts = facts,
            access_plans = access_plans,
            access_by_name = access_by_name,
            loop_plan = loop_plan,
            kernel_plan = build_kernel_plan(shape, access_by_name, facts, loop_plan),
            source_name = sanitize(artifact.symbol.text),
        }
    end

    local function realized_bc_schedule(artifact)
        local plan = build_artifact_plan(artifact)
        local evidence = {
            Stencil.StencilRealizedByConstruction("LuaTrace copy-patch materializer emitted " .. tostring(plan.loop_plan.reason)),
        }
        local group = tonumber(plan.loop_plan.group) or 1
        if group > 1 then
            return Stencil.StencilRealizedUnrolled(group, Stencil.StencilMaterializerCopyPatchBC, evidence)
        end
        return Stencil.StencilRealizedScalar(Stencil.StencilMaterializerCopyPatchBC, evidence)
    end

    local function with_realized(artifact, provider, realized)
        return ArtifactPlan.artifact_with_realized(artifact, provider or artifact.provider, realized)
    end

    local function emit_forward_loop(out, artifact_plan, body)
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

    local function emit_lua_function(artifact)
        local artifact_plan = build_artifact_plan(artifact)
        local shape = artifact_plan.shape
        local kind = shape.kind
        local stride = tonumber(shape.stride) or 1
        local trace_plan = artifact_plan.loop_plan
        local access = artifact_plan.access_by_name
        local kernel_plan = artifact_plan.kernel_plan
        local out = {}
        out[#out + 1] = "-- " .. artifact.instance.id.text
        out[#out + 1] = "-- luatrace plan: " .. trace_plan.reason .. " group=" .. tostring(trace_plan.group) .. " tail=" .. tostring(trace_plan.tail_strategy) .. " primitive=" .. tostring(kernel_plan.primitive_plan and kernel_plan.primitive_plan.kind or "none") .. " predicate=" .. tostring(kernel_plan.predicate_plan and kernel_plan.predicate_plan.kind or "none") .. " scatter=" .. tostring(kernel_plan.scatter_plan and kernel_plan.scatter_plan.kind or "none") .. " reduction=" .. tostring(kernel_plan.reduction_plan and kernel_plan.reduction_plan.kind or "none")

        if kind == "reduce_array" then
            local xs_access = assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "xs", "start", "stop", "init" })
            out[#out + 1] = "    local acc = init"
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. "acc = " .. lua_reduce_expr(shape.reduction, "acc", lua_access_ref(xs_access, "xs", i), shape.result_ty)
            end)
            out[#out + 1] = "    return acc"
        elseif kind == "map_array" then
            local dst_access, xs_access = assert(access.dst, "missing dst access plan"), assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "xs", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = " .. lua_unary_expr(shape.op, lua_access_ref(xs_access, "xs", i), shape.result_ty, shape.int_semantics, shape.float_mode)
            end)
        elseif kind == "zip_map_array" then
            local dst_access = assert(access.dst, "missing dst access plan")
            local lhs_access, rhs_access = assert(access.lhs, "missing lhs access plan"), assert(access.rhs, "missing rhs access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "lhs", "rhs", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = " .. lua_binary_expr(shape.op, lua_access_ref(lhs_access, "lhs", i), lua_access_ref(rhs_access, "rhs", i), shape.result_ty, shape.int_semantics, shape.float_mode)
            end)
        elseif kind == "scan_array" then
            local dst_access, xs_access = assert(access.dst, "missing dst access plan"), assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "xs", "start", "stop", "init" })
            out[#out + 1] = "    local acc = init"
            emit_forward_loop(out, artifact_plan, function(i, indent)
                if shape.mode == Stencil.StencilScanExclusive then
                    out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = acc"
                    out[#out + 1] = indent .. "acc = " .. lua_reduce_expr(shape.reduction, "acc", lua_access_ref(xs_access, "xs", i), shape.result_ty)
                else
                    out[#out + 1] = indent .. "acc = " .. lua_reduce_expr(shape.reduction, "acc", lua_access_ref(xs_access, "xs", i), shape.result_ty)
                    out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = acc"
                end
            end)
            out[#out + 1] = "    return acc"
        elseif kind == "copy_array" then
            local dst_access, src_access = assert(access.dst, "missing dst access plan"), assert(access.src, "missing src access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "src", "start", "stop" })
            if kernel_plan.primitive_plan and kernel_plan.primitive_plan.kind == "ffi_copy" then
                out[#out + 1] = "    local __ml_n = stop - start"
                out[#out + 1] = "    if __ml_n > 0 then ffi.copy(dst + start, src + start, __ml_n * " .. tostring(kernel_plan.primitive_plan.bytes_per_element) .. ") end"
            elseif shape.semantics == Stencil.StencilCopyMemMove or shape.semantics == Stencil.StencilCopyMayOverlapBackward then
                out[#out + 1] = "    for i = stop - 1, start, -" .. tostring(stride) .. " do"
                out[#out + 1] = "        " .. lua_access_ref(dst_access, "dst", "i") .. " = " .. lua_access_ref(src_access, "src", "i")
                out[#out + 1] = "    end"
            else
                emit_forward_loop(out, artifact_plan, function(i, indent)
                    out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = " .. lua_access_ref(src_access, "src", i)
                end)
            end
        elseif kind == "fill_array" then
            local dst_access = assert(access.dst, "missing dst access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "start", "stop", "value" })
            if kernel_plan.primitive_plan and kernel_plan.primitive_plan.kind == "ffi_fill" then
                out[#out + 1] = "    local __ml_n = stop - start"
                out[#out + 1] = "    if __ml_n > 0 then ffi.fill(dst + start, __ml_n, value) end"
            else
                emit_forward_loop(out, artifact_plan, function(i, indent)
                    out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = value"
                end)
            end
        elseif kind == "find_array" then
            local xs_access = assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "xs", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. "if " .. lua_pred_expr(shape.pred, lua_access_ref(xs_access, "xs", i)) .. " then return " .. i .. " end"
            end)
            out[#out + 1] = "    return -1"
        elseif kind == "partition_array" then
            local dst_access, xs_access = assert(access.dst, "missing dst access plan"), assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "xs", "start", "stop" })
            out[#out + 1] = "    local out_i = start"
            emit_forward_loop(out, artifact_plan, function(i, indent)
                local x = lua_access_ref(xs_access, "xs", i)
                out[#out + 1] = indent .. "if " .. lua_pred_expr(shape.pred, x) .. " then " .. lua_access_ref(dst_access, "dst", "out_i") .. " = " .. x .. "; out_i = out_i + 1 end"
            end)
            out[#out + 1] = "    local split = out_i"
            emit_forward_loop(out, artifact_plan, function(i, indent)
                local x = lua_access_ref(xs_access, "xs", i)
                out[#out + 1] = indent .. "if not " .. lua_pred_expr(shape.pred, x) .. " then " .. lua_access_ref(dst_access, "dst", "out_i") .. " = " .. x .. "; out_i = out_i + 1 end"
            end)
            out[#out + 1] = "    return split"
        elseif kind == "cast_array" then
            local dst_access, xs_access = assert(access.dst, "missing dst access plan"), assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "xs", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = " .. lua_access_ref(xs_access, "xs", i)
            end)
        elseif kind == "compare_array" then
            local dst_access, xs_access = assert(access.dst, "missing dst access plan"), assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "xs", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                local numeric = lua_numeric_pred_expr(shape.pred, "__ml_x", xs_access.ty)
                if numeric ~= nil then
                    out[#out + 1] = indent .. "local __ml_x = __ml_tobit(" .. lua_access_ref(xs_access, "xs", i) .. ")"
                    out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = " .. numeric
                else
                    out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = " .. lua_pred_expr(shape.pred, lua_access_ref(xs_access, "xs", i)) .. " and 1 or 0"
                end
            end)
        elseif kind == "zip_compare_array" then
            local dst_access = assert(access.dst, "missing dst access plan")
            local lhs_access, rhs_access = assert(access.lhs, "missing lhs access plan"), assert(access.rhs, "missing rhs access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "lhs", "rhs", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                local numeric = lua_numeric_cmp_expr(shape.cmp, "__ml_a", "__ml_b", lhs_access.ty, rhs_access.ty)
                if numeric ~= nil then
                    out[#out + 1] = indent .. "local __ml_a = __ml_tobit(" .. lua_access_ref(lhs_access, "lhs", i) .. ")"
                    out[#out + 1] = indent .. "local __ml_b = __ml_tobit(" .. lua_access_ref(rhs_access, "rhs", i) .. ")"
                    out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = " .. numeric
                else
                    out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = " .. lua_cmp_expr(shape.cmp, lua_access_ref(lhs_access, "lhs", i), lua_access_ref(rhs_access, "rhs", i)) .. " and 1 or 0"
                end
            end)
        elseif kind == "select_array" then
            local dst_access = assert(access.dst, "missing dst access plan")
            local cond_access = assert(access.cond, "missing cond access plan")
            local then_access = assert(access.then_xs, "missing then access plan")
            local else_access = assert(access.else_xs, "missing else access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "cond", "then_xs", "else_xs", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent
                    .. lua_access_ref(dst_access, "dst", i)
                    .. " = "
                    .. lua_pred_expr(shape.pred, lua_access_ref(cond_access, "cond", i))
                    .. " and "
                    .. lua_access_ref(then_access, "then_xs", i)
                    .. " or "
                    .. lua_access_ref(else_access, "else_xs", i)
            end)
        elseif kind == "apply_n_array" then
            local dst_access = assert(access.dst, "missing dst access plan")
            local params = { "dst" }
            for _, input in ipairs(shape.inputs or {}) do params[#params + 1] = input.name end
            params[#params + 1] = "start"
            params[#params + 1] = "stop"
            out[#out + 1] = fn_header(artifact, params)
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent
                    .. lua_access_ref(dst_access, "dst", i)
                    .. " = "
                    .. lua_apply_expr(shape.expr, artifact_plan.descriptor, access, i)
            end)
        elseif kind == "gather_array" then
            local dst_access, idx_access = assert(access.dst, "missing dst access plan"), assert(access.idx, "missing idx access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "src", "idx", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. lua_access_ref(dst_access, "dst", i) .. " = src[" .. lua_access_ref(idx_access, "idx", i) .. "]"
            end)
        elseif kind == "scatter_array" then
            local src_access, idx_access = assert(access.src, "missing src access plan"), assert(access.idx, "missing idx access plan")
            out[#out + 1] = fn_header(artifact, { "dst", "src", "idx", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. "dst[" .. lua_access_ref(idx_access, "idx", i) .. "] = " .. lua_access_ref(src_access, "src", i)
            end)
        elseif kind == "in_place_map_array" then
            local xs_access = assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "xs", "start", "stop" })
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. lua_access_ref(xs_access, "xs", i) .. " = " .. lua_unary_expr(shape.op, lua_access_ref(xs_access, "xs", i), shape.elem_ty, shape.int_semantics, shape.float_mode)
            end)
        elseif kind == "count_array" then
            local xs_access = assert(access.xs, "missing xs access plan")
            out[#out + 1] = fn_header(artifact, { "xs", "start", "stop" })
            if kernel_plan.predicate_plan.kind == "multi_counter_branch" then
                local group = trace_plan.group
                local sum_terms = {}
                for lane = 0, group - 1 do
                    out[#out + 1] = "    local n" .. tostring(lane) .. " = 0"
                    sum_terms[#sum_terms + 1] = "n" .. tostring(lane)
                end
                out[#out + 1] = "    local n_tail = 0"
                sum_terms[#sum_terms + 1] = "n_tail"
                out[#out + 1] = "    -- luatrace predicate: multi_counter_branch counters=" .. tostring(group)
                out[#out + 1] = "    local __ml_i = start"
                if trace_plan.tail_strategy == "no_tail_trip_count_multiple" then
                    out[#out + 1] = "    local __ml_stop_group = stop"
                else
                    out[#out + 1] = "    local __ml_stop_group = stop - ((stop - start) % " .. tostring(group) .. ")"
                end
                out[#out + 1] = "    while __ml_i < __ml_stop_group do"
                for lane = 0, group - 1 do
                    local idx = lane == 0 and "__ml_i" or ("__ml_i + " .. tostring(lane))
                    out[#out + 1] = "        if " .. lua_pred_expr(shape.pred, lua_access_ref(xs_access, "xs", idx)) .. " then n" .. tostring(lane) .. " = n" .. tostring(lane) .. " + 1 end"
                end
                out[#out + 1] = "        __ml_i = __ml_i + " .. tostring(group)
                out[#out + 1] = "    end"
                if trace_plan.tail_strategy ~= "no_tail_trip_count_multiple" then
                    out[#out + 1] = "    for i = __ml_i, stop - 1, 1 do"
                    out[#out + 1] = "        if " .. lua_pred_expr(shape.pred, lua_access_ref(xs_access, "xs", "i")) .. " then n_tail = n_tail + 1 end"
                    out[#out + 1] = "    end"
                end
                out[#out + 1] = "    return " .. table.concat(sum_terms, " + ")
            else
                out[#out + 1] = "    local n = 0"
                emit_forward_loop(out, artifact_plan, function(i, indent)
                    local numeric = lua_numeric_pred_expr(shape.pred, "__ml_x", xs_access.ty)
                    if numeric ~= nil then
                        out[#out + 1] = indent .. "local __ml_x = __ml_tobit(" .. lua_access_ref(xs_access, "xs", i) .. ")"
                        out[#out + 1] = indent .. "n = n + " .. numeric
                    else
                        out[#out + 1] = indent .. "if " .. lua_pred_expr(shape.pred, lua_access_ref(xs_access, "xs", i)) .. " then n = n + 1 end"
                    end
                end)
                out[#out + 1] = "    return n"
            end
        elseif kind == "reduce_n_array" then
            local params = {}
            for _, input in ipairs(shape.inputs or {}) do params[#params + 1] = input.name end
            params[#params + 1] = "start"
            params[#params + 1] = "stop"
            params[#params + 1] = "init"
            out[#out + 1] = fn_header(artifact, params)
            out[#out + 1] = "    local acc = init"
            emit_forward_loop(out, artifact_plan, function(i, indent)
                out[#out + 1] = indent .. "acc = " .. lua_reduce_expr(shape.reduction, "acc", lua_apply_expr(shape.expr, artifact_plan.descriptor, access, i), shape.result_ty)
            end)
            out[#out + 1] = "    return acc"
        else
            error("copy_patch_luatrace: unsupported stencil shape " .. tostring(kind), 3)
        end

        out[#out + 1] = "end"
        out[#out + 1] = "__lalin_luajit_stencil_symbols[" .. lua_string(artifact.symbol.text) .. "] = " .. sanitize(artifact.symbol.text)
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
                holes = opts.holes,
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

    local function bindings_for_symbol(opts, symbol)
        local bindings = opts and (opts.patch_bindings or opts.bc_patch_bindings) or nil
        if bindings == nil then return nil end
        return bindings[symbol] or bindings
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
                    return nil, "copy_patch_bc: bank entry missing artifact fingerprint for " .. tostring(symbol)
                end
                if requested_artifact.fingerprint == nil or requested_artifact.fingerprint.text == nil then
                    return nil, "copy_patch_bc: requested artifact missing fingerprint for " .. tostring(symbol)
                end
                if entry.artifact.fingerprint.text ~= requested_artifact.fingerprint.text then
                    return nil, "copy_patch_bc: artifact fingerprint mismatch for " .. tostring(symbol)
                end
            end
            local fn, err = BCBank.load_symbol(bank, symbol, bindings_for_symbol(opts, symbol), {
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
            "-- Generated Lalin LuaTrace BC copy-patch bank.",
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
        return assert(api.realize_bc_artifacts(artifacts), "LuaTrace bytecode realization failed")
    end

    T._lalin_api_cache.copy_patch_luatrace = api
    return api
end

return bind_context
