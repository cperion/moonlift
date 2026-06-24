local pvm = require("moonlift.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.stencil_c ~= nil then return T._moonlift_api_cache.stencil_c end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Value = T.MoonValue
    local Kernel = T.MoonKernel
    local Stencil = T.MoonStencil
    local Schedule = T.MoonSchedule
    local CodeType = require("moonlift.code_type")(T)
    local CEmit = require("moonlift.c_emit")(T)

    local api = {}

    local function type_name(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if ty == Code.CodeTyIndex then return "index" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        return "ty"
    end

    local function c_type(ty)
        return CEmit.emit_type(CodeType.code_type_to_c(ty, {}))
    end

    local function unsigned_c_type(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt and (ty.bits == 8 or ty.bits == 16 or ty.bits == 32 or ty.bits == 64) then return "uint" .. tostring(ty.bits) .. "_t" end
        return c_type(ty)
    end

    local function reduction_name(kind)
        if kind == Value.ReductionAdd then return "add" end
        if kind == Value.ReductionMul then return "mul" end
        if kind == Value.ReductionAnd then return "and" end
        if kind == Value.ReductionOr then return "or" end
        if kind == Value.ReductionXor then return "xor" end
        if kind == Value.ReductionMin then return "min" end
        if kind == Value.ReductionMax then return "max" end
        return "reduction"
    end

    local function unary_name(op)
        if op == Stencil.StencilUnaryIdentity then return "identity" end
        if op == Stencil.StencilUnaryNeg then return "neg" end
        if op == Stencil.StencilUnaryBitNot then return "bitnot" end
        if op == Stencil.StencilUnaryBoolNot then return "boolnot" end
        return "unary"
    end

    local function binary_name(op)
        if op == Stencil.StencilBinaryAdd then return "add" end
        if op == Stencil.StencilBinarySub then return "sub" end
        if op == Stencil.StencilBinaryMul then return "mul" end
        if op == Stencil.StencilBinaryAnd then return "and" end
        if op == Stencil.StencilBinaryOr then return "or" end
        if op == Stencil.StencilBinaryXor then return "xor" end
        if op == Stencil.StencilBinaryMin then return "min" end
        if op == Stencil.StencilBinaryMax then return "max" end
        return "binary"
    end

    local function pred_name(pred)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return "nonzero" end
        if cls == Stencil.StencilPredEqConst then return "eq" end
        if cls == Stencil.StencilPredNeConst then return "ne" end
        if cls == Stencil.StencilPredLtConst then return "lt" end
        if cls == Stencil.StencilPredLeConst then return "le" end
        if cls == Stencil.StencilPredGtConst then return "gt" end
        if cls == Stencil.StencilPredGeConst then return "ge" end
        return "pred"
    end

    local function cmp_name(op)
        if op == Core.CmpEq then return "eq" end
        if op == Core.CmpNe then return "ne" end
        if op == Core.CmpLt then return "lt" end
        if op == Core.CmpLe then return "le" end
        if op == Core.CmpGt then return "gt" end
        if op == Core.CmpGe then return "ge" end
        return "cmp"
    end

    local function cast_name(op)
        if op == Core.MachineCastIdentity then return "identity" end
        if op == Core.MachineCastBitcast then return "bitcast" end
        if op == Core.MachineCastIreduce then return "ireduce" end
        if op == Core.MachineCastSextend then return "sext" end
        if op == Core.MachineCastUextend then return "uext" end
        if op == Core.MachineCastFpromote then return "fpromote" end
        if op == Core.MachineCastFdemote then return "fdemote" end
        if op == Core.MachineCastSToF then return "stof" end
        if op == Core.MachineCastUToF then return "utof" end
        if op == Core.MachineCastFToS then return "ftos" end
        if op == Core.MachineCastFToU then return "ftou" end
        return "cast"
    end

    local function scan_mode_name(mode)
        if mode == Stencil.StencilScanInclusive then return "inclusive" end
        if mode == Stencil.StencilScanExclusive then return "exclusive" end
        return "scan"
    end

    local function copy_semantics_name(semantics)
        if semantics == Stencil.StencilCopyNoOverlap then return "nooverlap" end
        if semantics == Stencil.StencilCopyMayOverlapForward then return "forward" end
        if semantics == Stencil.StencilCopyMayOverlapBackward then return "backward" end
        if semantics == Stencil.StencilCopyMemMove then return "memmove" end
        return "copy"
    end

    local function partition_semantics_name(semantics)
        if semantics == Stencil.StencilPartitionStable then return "stable" end
        if semantics == Stencil.StencilPartitionUnstable then return "unstable" end
        return "partition"
    end

    local function scatter_conflict_name(conflicts)
        if conflicts == Stencil.StencilScatterUniqueIndices then return "unique" end
        if conflicts == Stencil.StencilScatterLastWriteWins then return "last" end
        if conflicts == Stencil.StencilScatterConflictUndefined then return "undefined" end
        return "scatter"
    end

    local function proof_list(plan)
        local eq = plan and plan.body and plan.body.equivalence or nil
        if pvm.classof(eq) == Kernel.KernelEquivalenceProof then return eq.proofs or {} end
        return {}
    end

    local function reduce_instance_id(elem_ty, result_ty, reduction, stride)
        return Stencil.StencilInstanceId("stencil:reduce_array:" .. type_name(elem_ty) .. ":" .. reduction_name(reduction) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
    end

    local function reduce_symbol_id(elem_ty, result_ty, reduction, stride)
        return Stencil.StencilSymbolId("ml_stencil_reduce_array_" .. type_name(elem_ty) .. "_" .. reduction_name(reduction) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
    end

    local function reduce_c_decl(symbol, elem_ty, result_ty)
        local elem = c_type(elem_ty)
        local result = c_type(result_ty)
        return result .. " " .. symbol.text .. "(const " .. elem .. " *xs, int32_t start, int32_t stop, " .. result .. " init);"
    end

    local function scalar_param_ty(ty)
        return c_type(ty)
    end

    local function void_decl(symbol, args)
        return "void " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    local function result_decl(symbol, result_ty, args)
        return c_type(result_ty) .. " " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    local function int32_decl(symbol, args)
        return "int32_t " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    local function is_int(ty)
        return pvm.classof(ty) == Code.CodeTyInt
    end

    local function is_float(ty)
        return pvm.classof(ty) == Code.CodeTyFloat
    end

    local function same_type(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    local function is_scalar(ty)
        local cls = pvm.classof(ty)
        return cls == Code.CodeTyInt or cls == Code.CodeTyFloat or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function supports_bitwise_ty(ty)
        return pvm.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyBool8
    end

    local function const_literal_source(expr, ty)
        local cls = pvm.classof(expr)
        if cls ~= Value.ValueExprConst or pvm.classof(expr.const) ~= Code.CodeConstLiteral then
            error("stencil_c: predicate/fill const must be a literal ValueExprConst", 3)
        end
        local lit = expr.const.literal
        local lcls = pvm.classof(lit)
        if lcls == Core.LitInt then
            local raw = tostring(lit.raw)
            local tcls = pvm.classof(ty or expr.const.ty)
            if tcls == Code.CodeTyInt and ty.bits == 64 then
                return raw .. ((ty.signedness == Code.CodeUnsigned) and "ULL" or "LL")
            end
            return raw
        elseif lcls == Core.LitFloat then
            return tostring(lit.raw)
        elseif lcls == Core.LitBool then
            return lit.value and "1" or "0"
        end
        error("stencil_c: unsupported literal for C stencil", 3)
    end

    local function predicate_expr(pred, item, ty)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return "(" .. item .. " != 0)" end
        local c = "(" .. c_type(ty) .. ")(" .. const_literal_source(pred.value, ty) .. ")"
        if cls == Stencil.StencilPredEqConst then return "(" .. item .. " == " .. c .. ")" end
        if cls == Stencil.StencilPredNeConst then return "(" .. item .. " != " .. c .. ")" end
        if cls == Stencil.StencilPredLtConst then return "(" .. item .. " < " .. c .. ")" end
        if cls == Stencil.StencilPredLeConst then return "(" .. item .. " <= " .. c .. ")" end
        if cls == Stencil.StencilPredGtConst then return "(" .. item .. " > " .. c .. ")" end
        if cls == Stencil.StencilPredGeConst then return "(" .. item .. " >= " .. c .. ")" end
        error("stencil_c: unsupported predicate " .. pred_name(pred), 3)
    end

    local function compare_expr(cmp, lhs, rhs)
        if cmp == Core.CmpEq then return "(" .. lhs .. " == " .. rhs .. ")" end
        if cmp == Core.CmpNe then return "(" .. lhs .. " != " .. rhs .. ")" end
        if cmp == Core.CmpLt then return "(" .. lhs .. " < " .. rhs .. ")" end
        if cmp == Core.CmpLe then return "(" .. lhs .. " <= " .. rhs .. ")" end
        if cmp == Core.CmpGt then return "(" .. lhs .. " > " .. rhs .. ")" end
        if cmp == Core.CmpGe then return "(" .. lhs .. " >= " .. rhs .. ")" end
        error("stencil_c: unsupported compare op " .. cmp_name(cmp), 3)
    end

    local function bool_result_expr(cond, result_ty)
        return "(" .. c_type(result_ty) .. ")((" .. cond .. ") ? 1 : 0)"
    end

    local function reduction_update_expr(kind, acc, item, ty)
        local ct = c_type(ty)
        local acc_ty = (kind == Value.ReductionMin or kind == Value.ReductionMax) and ct or unsigned_c_type(ty)
        if kind == Value.ReductionAdd then return "(" .. acc_ty .. ")((" .. acc .. ") + (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionMul then return "(" .. acc_ty .. ")((" .. acc .. ") * (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionAnd then return "(" .. acc_ty .. ")((" .. acc .. ") & (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionOr then return "(" .. acc_ty .. ")((" .. acc .. ") | (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionXor then return "(" .. acc_ty .. ")((" .. acc .. ") ^ (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionMin then return "((" .. item .. ") < (" .. acc .. ") ? (" .. item .. ") : (" .. acc .. "))" end
        if kind == Value.ReductionMax then return "((" .. item .. ") > (" .. acc .. ") ? (" .. item .. ") : (" .. acc .. "))" end
        error("stencil_c: unsupported reduction " .. reduction_name(kind), 3)
    end

    local function unary_expr(op, value, result_ty)
        local ct = c_type(result_ty)
        if op == Stencil.StencilUnaryIdentity then return "(" .. ct .. ")(" .. value .. ")" end
        if op == Stencil.StencilUnaryNeg then return "(" .. ct .. ")(-(" .. value .. "))" end
        if op == Stencil.StencilUnaryBitNot then return "(" .. ct .. ")(~(" .. unsigned_c_type(result_ty) .. ")(" .. value .. "))" end
        if op == Stencil.StencilUnaryBoolNot then return "(" .. ct .. ")(!(" .. value .. "))" end
        error("stencil_c: unsupported unary op " .. unary_name(op), 3)
    end

    local function binary_expr(op, lhs, rhs, result_ty)
        local ct = c_type(result_ty)
        local ut = unsigned_c_type(result_ty)
        if op == Stencil.StencilBinaryAdd then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") + (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinarySub then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") - (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryMul then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") * (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryAnd then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") & (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryOr then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") | (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryXor then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") ^ (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryMin then return "((" .. lhs .. ") < (" .. rhs .. ") ? (" .. lhs .. ") : (" .. rhs .. "))" end
        if op == Stencil.StencilBinaryMax then return "((" .. lhs .. ") > (" .. rhs .. ") ? (" .. lhs .. ") : (" .. rhs .. "))" end
        error("stencil_c: unsupported binary op " .. binary_name(op), 3)
    end

    local ArtifactPlan = require("moonlift.stencil_artifact_plan")(T)
    local artifact_shape = ArtifactPlan.artifact_shape
    local source_params = ArtifactPlan.source_params
    local access_named = ArtifactPlan.access_named
    local stride_param_name = ArtifactPlan.stride_param_name
    local dynamic_stride_accesses = ArtifactPlan.dynamic_stride_accesses

    local function access_offset(access, index)
        local top = access.topology
        local cls = pvm.classof(top)
        if cls == Stencil.StencilTopologyFieldProjection then
            return access_offset({ topology = top.parent }, index)
        end
        if cls == Stencil.StencilTopologySoAComponent then
            return access_offset({ topology = top.parent, name = access.name }, index)
        end
        if cls == Stencil.StencilTopologyViewDescriptor then
            local stride = top.stride_const or stride_param_name(access)
            if tonumber(stride) == 1 then return index end
            return "((" .. index .. ") * " .. tostring(stride) .. ")"
        end
        if cls == Stencil.StencilTopologySliceDescriptor then return index end
        if cls == Stencil.StencilTopologyByteSpanDescriptor then return index end
        return index
    end

    local function access_ref(access, base, index)
        local top = access.topology
        if pvm.classof(top) == Stencil.StencilTopologyFieldProjection then
            return base .. "[" .. access_offset({ topology = top.parent }, index) .. "]." .. sanitize(top.field_name)
        end
        if pvm.classof(top) == Stencil.StencilTopologySoAComponent then
            return base .. "[" .. access_offset({ topology = top.parent, name = access.name }, index) .. "]"
        end
        return base .. "[" .. access_offset(access, index) .. "]"
    end

    local function is_i32(ty)
        return pvm.classof(ty) == Code.CodeTyInt and ty.bits == 32 and ty.signedness == Code.CodeSigned
    end

    local function is_plain_linear_access(access)
        local cls = pvm.classof(access.topology)
        return cls == Stencil.StencilTopologyContiguous
            or cls == Stencil.StencilTopologySliceDescriptor
            or cls == Stencil.StencilTopologyByteSpanDescriptor
    end

    local function vector_reduction_source(artifact, shape, xs_access, schedule, ct, et)
        local stride = tonumber(shape.stride) or 1
        if stride ~= 1 then return nil end
        if shape.reduction ~= Value.ReductionAdd then return nil end
        if not is_i32(shape.elem_ty) or not is_i32(shape.result_ty) then return nil end
        local top = pvm.classof(xs_access.topology)
        if top ~= Stencil.StencilTopologyContiguous and top ~= Stencil.StencilTopologySliceDescriptor then return nil end
        local lanes = math.max(2, math.floor(tonumber(schedule.lanes) or 4))
        local unroll = math.max(1, math.floor(tonumber(schedule.unroll) or 1))
        local vec_ty = "ml_vec_u32x" .. tostring(lanes)
        local vec_bytes = lanes * 4
        local lines = {}
        lines[#lines + 1] = ct .. " " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { "const " .. et .. " *xs", "int32_t start", "int32_t stop", ct .. " init" }), ", ") .. ") {"
        lines[#lines + 1] = "    typedef uint32_t " .. vec_ty .. " __attribute__((vector_size(" .. tostring(vec_bytes) .. ")));"
        lines[#lines + 1] = "    int32_t i = start;"
        lines[#lines + 1] = "    int32_t span = stop - start;"
        lines[#lines + 1] = "    if (span <= 0) return init;"
        lines[#lines + 1] = "    int32_t step = " .. tostring(lanes * unroll) .. ";"
        lines[#lines + 1] = "    int32_t stop_vec = stop - (span & (step - 1));"
        for lane = 0, unroll - 1 do lines[#lines + 1] = "    " .. vec_ty .. " vacc" .. tostring(lane) .. " = (" .. vec_ty .. "){0};" end
        lines[#lines + 1] = "    for (; i < stop_vec; i += step) {"
        for lane = 0, unroll - 1 do
            local off = lane * lanes
            lines[#lines + 1] = "        " .. vec_ty .. " chunk" .. tostring(lane) .. ";"
            lines[#lines + 1] = "        __builtin_memcpy(&chunk" .. tostring(lane) .. ", xs + i" .. (off == 0 and "" or (" + " .. tostring(off))) .. ", sizeof(chunk" .. tostring(lane) .. "));"
            lines[#lines + 1] = "        vacc" .. tostring(lane) .. " += chunk" .. tostring(lane) .. ";"
        end
        lines[#lines + 1] = "    }"
        for lane = 1, unroll - 1 do lines[#lines + 1] = "    vacc0 += vacc" .. tostring(lane) .. ";" end
        lines[#lines + 1] = "    uint32_t partial[" .. tostring(lanes) .. "];"
        lines[#lines + 1] = "    __builtin_memcpy(partial, &vacc0, sizeof(partial));"
        lines[#lines + 1] = "    uint32_t acc = (uint32_t)init;"
        lines[#lines + 1] = "    for (int32_t lane = 0; lane < " .. tostring(lanes) .. "; lane++) acc += partial[lane];"
        lines[#lines + 1] = "    switch (stop - i) {"
        for tail = (lanes * unroll) - 1, 1, -1 do
            lines[#lines + 1] = "    case " .. tostring(tail) .. ": acc = (uint32_t)(acc + (uint32_t)" .. access_ref(xs_access, "xs", "i + " .. tostring(tail - 1)) .. ");"
        end
        lines[#lines + 1] = "    default: break;"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. ct .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function reduce_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local elem_ty, result_ty = shape.elem_ty, shape.result_ty
        local ct = c_type(result_ty)
        local et = c_type(elem_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and ct or unsigned_c_type(result_ty)
        local stride = tonumber(shape.stride) or 1
        local schedule = artifact.instance.schedule
        if pvm.classof(schedule) == Stencil.StencilScheduleVector then
            local vector_source = vector_reduction_source(artifact, shape, xs_access, schedule, ct, et)
            if vector_source ~= nil then return vector_source end
        end
        local unroll = pvm.classof(schedule) == Stencil.StencilScheduleUnrolled and tonumber(schedule.factor) or 1
        unroll = math.max(1, math.floor(unroll or 1))
        local lines = {}
        lines[#lines + 1] = ct .. " " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { "const " .. et .. " *xs", "int32_t start", "int32_t stop", ct .. " init" }), ", ") .. ") {"
        if unroll > 1 and stride == 1 then
            lines[#lines + 1] = "    " .. acc_ty .. " acc0 = (" .. acc_ty .. ")init;"
            for lane = 1, unroll - 1 do lines[#lines + 1] = "    " .. acc_ty .. " acc" .. tostring(lane) .. " = (" .. acc_ty .. ")0;" end
            lines[#lines + 1] = "    int32_t i = start;"
            lines[#lines + 1] = "    int32_t stop_unrolled = start + ((stop - start) / " .. tostring(unroll) .. ") * " .. tostring(unroll) .. ";"
            lines[#lines + 1] = "    for (; i < stop_unrolled; i += " .. tostring(unroll) .. ") {"
            for lane = 0, unroll - 1 do
                lines[#lines + 1] = "        acc" .. tostring(lane) .. " = " .. reduction_update_expr(shape.reduction, "acc" .. tostring(lane), access_ref(xs_access, "xs", "i + " .. tostring(lane)), shape.result_ty) .. ";"
            end
            lines[#lines + 1] = "    }"
            for lane = 1, unroll - 1 do
                lines[#lines + 1] = "    acc0 = " .. reduction_update_expr(shape.reduction, "acc0", "acc" .. tostring(lane), shape.result_ty) .. ";"
            end
            lines[#lines + 1] = "    for (; i < stop; i++) {"
            lines[#lines + 1] = "        acc0 = " .. reduction_update_expr(shape.reduction, "acc0", access_ref(xs_access, "xs", "i"), shape.result_ty) .. ";"
            lines[#lines + 1] = "    }"
            lines[#lines + 1] = "    return (" .. ct .. ")acc0;"
        else
            lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
            lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
            lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", access_ref(xs_access, "xs", "i"), shape.result_ty) .. ";"
            lines[#lines + 1] = "    }"
            lines[#lines + 1] = "    return (" .. ct .. ")acc;"
        end
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function map_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, xs_access = access_named(desc, "dst"), access_named(desc, "xs")
        local et, rt = c_type(shape.elem_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", "const " .. et .. " *xs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        " .. access_ref(dst_access, "dst", "i") .. " = " .. unary_expr(shape.op, access_ref(xs_access, "xs", "i"), shape.result_ty) .. ";"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function zip_map_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, lhs_access, rhs_access = access_named(desc, "dst"), access_named(desc, "lhs"), access_named(desc, "rhs")
        local lt, rt = c_type(shape.lhs_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", "const " .. lt .. " *lhs", "const " .. lt .. " *rhs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        " .. access_ref(dst_access, "dst", "i") .. " = " .. binary_expr(shape.op, access_ref(lhs_access, "lhs", "i"), access_ref(rhs_access, "rhs", "i"), shape.result_ty) .. ";"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function scan_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, xs_access = access_named(desc, "dst"), access_named(desc, "xs")
        local et, rt = c_type(shape.elem_ty), c_type(shape.result_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and rt or unsigned_c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = rt .. " " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", "const " .. et .. " *xs", "int32_t start", "int32_t stop", rt .. " init" }), ", ") .. ") {"
        lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        local x = access_ref(xs_access, "xs", "i")
        local dst = access_ref(dst_access, "dst", "i")
        if shape.mode == Stencil.StencilScanExclusive then
            lines[#lines + 1] = "        " .. dst .. " = (" .. rt .. ")acc;"
            lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", x, shape.result_ty) .. ";"
        else
            lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", x, shape.result_ty) .. ";"
            lines[#lines + 1] = "        " .. dst .. " = (" .. rt .. ")acc;"
        end
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. rt .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function copy_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, src_access = access_named(desc, "dst"), access_named(desc, "src")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        local dst_param = et .. " *dst"
        local src_param = "const " .. et .. " *src"
        if shape.semantics ~= Stencil.StencilCopyMemMove and shape.semantics ~= Stencil.StencilCopyMayOverlapBackward then
            dst_param = et .. " *__restrict dst"
            src_param = "const " .. et .. " *__restrict src"
        end
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { dst_param, src_param, "int32_t start", "int32_t stop" }), ", ") .. ") {"
        if shape.semantics == Stencil.StencilCopyMayOverlapBackward then
            lines[#lines + 1] = "    for (int32_t i = stop - 1; i >= start; i -= " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = " .. access_ref(src_access, "src", "i") .. ";"
        elseif shape.semantics == Stencil.StencilCopyMemMove then
            lines[#lines + 1] = "    if ((uintptr_t)dst <= (uintptr_t)src) {"
            lines[#lines + 1] = "        for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = " .. access_ref(src_access, "src", "i") .. ";"
            lines[#lines + 1] = "    } else {"
            lines[#lines + 1] = "        for (int32_t i = stop - 1; i >= start; i -= " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = " .. access_ref(src_access, "src", "i") .. ";"
            lines[#lines + 1] = "    }"
        else
            lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = " .. access_ref(src_access, "src", "i") .. ";"
        end
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function fill_array_source(artifact)
        local shape = artifact_shape(artifact)
        local dst_access = access_named(artifact.instance.descriptor, "dst")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { et .. " *dst", "int32_t start", "int32_t stop", et .. " value" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = value;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function find_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "int32_t " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { "const " .. et .. " *xs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        if " .. predicate_expr(shape.pred, access_ref(xs_access, "xs", "i"), shape.elem_ty) .. " return i;"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return -1;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function partition_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, xs_access = access_named(desc, "dst"), access_named(desc, "xs")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "int32_t " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { et .. " *dst", "const " .. et .. " *xs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    int32_t out = start;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") { if " .. predicate_expr(shape.pred, access_ref(xs_access, "xs", "i"), shape.elem_ty) .. " " .. access_ref(dst_access, "dst", "out++") .. " = " .. access_ref(xs_access, "xs", "i") .. "; }"
        lines[#lines + 1] = "    int32_t split = out;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") { if (!" .. predicate_expr(shape.pred, access_ref(xs_access, "xs", "i"), shape.elem_ty) .. ") " .. access_ref(dst_access, "dst", "out++") .. " = " .. access_ref(xs_access, "xs", "i") .. "; }"
        lines[#lines + 1] = "    return split;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function cast_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, xs_access = access_named(desc, "dst"), access_named(desc, "xs")
        local st, dt = c_type(shape.src_ty), c_type(shape.dst_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { dt .. " *dst", "const " .. st .. " *xs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        local dst = access_ref(dst_access, "dst", "i")
        local x = access_ref(xs_access, "xs", "i")
        if shape.op == Core.MachineCastBitcast then
            lines[#lines + 1] = "        memset(&" .. dst .. ", 0, sizeof(" .. dst .. "));"
            lines[#lines + 1] = "        memcpy(&" .. dst .. ", &" .. x .. ", sizeof(" .. dst .. ") < sizeof(" .. x .. ") ? sizeof(" .. dst .. ") : sizeof(" .. x .. "));"
        else
            lines[#lines + 1] = "        " .. dst .. " = (" .. dt .. ")(" .. x .. ");"
        end
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function compare_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, xs_access = access_named(desc, "dst"), access_named(desc, "xs")
        local et, rt = c_type(shape.elem_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", "const " .. et .. " *xs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = " .. bool_result_expr(predicate_expr(shape.pred, access_ref(xs_access, "xs", "i"), shape.elem_ty), shape.result_ty) .. ";"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function zip_compare_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, lhs_access, rhs_access = access_named(desc, "dst"), access_named(desc, "lhs"), access_named(desc, "rhs")
        local lt, rt = c_type(shape.lhs_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", "const " .. lt .. " *lhs", "const " .. lt .. " *rhs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = " .. bool_result_expr(compare_expr(shape.cmp, access_ref(lhs_access, "lhs", "i"), access_ref(rhs_access, "rhs", "i")), shape.result_ty) .. ";"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function gather_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, idx_access = access_named(desc, "dst"), access_named(desc, "idx")
        local et, it = c_type(shape.elem_ty), c_type(shape.index_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { et .. " *dst", "const " .. et .. " *src", "const " .. it .. " *idx", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = src[" .. access_ref(idx_access, "idx", "i") .. "];"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function scatter_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local src_access, idx_access = access_named(desc, "src"), access_named(desc, "idx")
        local et, it = c_type(shape.elem_ty), c_type(shape.index_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { et .. " *dst", "const " .. et .. " *src", "const " .. it .. " *idx", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") dst[" .. access_ref(idx_access, "idx", "i") .. "] = " .. access_ref(src_access, "src", "i") .. ";"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function in_place_map_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { et .. " *xs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        local x = access_ref(xs_access, "xs", "i")
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") " .. x .. " = " .. unary_expr(shape.op, x, shape.elem_ty) .. ";"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function count_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "int32_t " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { "const " .. et .. " *xs", "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    int32_t count = 0;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") if " .. predicate_expr(shape.pred, access_ref(xs_access, "xs", "i"), shape.elem_ty) .. " count++;"
        lines[#lines + 1] = "    return count;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function map_reduce_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local et, mt, rt = c_type(shape.elem_ty), c_type(shape.mapped_ty), c_type(shape.result_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and rt or unsigned_c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = rt .. " " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { "const " .. et .. " *xs", "int32_t start", "int32_t stop", rt .. " init" }), ", ") .. ") {"
        lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", unary_expr(shape.op, access_ref(xs_access, "xs", "i"), shape.mapped_ty), shape.result_ty) .. ";"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. rt .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function zip_reduce_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local lhs_access, rhs_access = access_named(desc, "lhs"), access_named(desc, "rhs")
        local lt, rt = c_type(shape.lhs_ty), c_type(shape.result_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and rt or unsigned_c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = rt .. " " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { "const " .. lt .. " *lhs", "const " .. lt .. " *rhs", "int32_t start", "int32_t stop", rt .. " init" }), ", ") .. ") {"
        lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", binary_expr(shape.op, access_ref(lhs_access, "lhs", "i"), access_ref(rhs_access, "rhs", "i"), shape.mapped_ty), shape.result_ty) .. ";"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. rt .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function artifact_source(artifact)
        local kind = artifact_shape(artifact).kind
        if kind == "reduce_array" then return reduce_array_source(artifact) end
        if kind == "map_array" then return map_array_source(artifact) end
        if kind == "zip_map_array" then return zip_map_array_source(artifact) end
        if kind == "scan_array" then return scan_array_source(artifact) end
        if kind == "copy_array" then return copy_array_source(artifact) end
        if kind == "fill_array" then return fill_array_source(artifact) end
        if kind == "find_array" then return find_array_source(artifact) end
        if kind == "partition_array" then return partition_array_source(artifact) end
        if kind == "cast_array" then return cast_array_source(artifact) end
        if kind == "compare_array" then return compare_array_source(artifact) end
        if kind == "zip_compare_array" then return zip_compare_array_source(artifact) end
        if kind == "gather_array" then return gather_array_source(artifact) end
        if kind == "scatter_array" then return scatter_array_source(artifact) end
        if kind == "in_place_map_array" then return in_place_map_array_source(artifact) end
        if kind == "count_array" then return count_array_source(artifact) end
        if kind == "map_reduce_array" then return map_reduce_array_source(artifact) end
        if kind == "zip_reduce_array" then return zip_reduce_array_source(artifact) end
        error("stencil_c: unsupported stencil shape", 3)
    end

    function api.source(artifacts, opts)
        opts = opts or {}
        local out = { "#include <stdint.h>", "#include <stddef.h>", "#include <string.h>", "typedef intptr_t ml_index;" }
        if opts.preamble ~= nil and opts.preamble ~= "" then out[#out + 1] = opts.preamble end
        local seen = {}
        for _, artifact in ipairs(artifacts or {}) do
            local key = artifact.symbol.text
            if not seen[key] then
                out[#out + 1] = artifact_source(artifact)
                seen[key] = true
            end
        end
        return table.concat(out, "\n\n") .. "\n"
    end

    T._moonlift_api_cache.stencil_c = api
    return api
end

return bind_context
