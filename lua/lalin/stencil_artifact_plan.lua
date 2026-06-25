local pvm = require("lalin.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.stencil_artifact_plan ~= nil then return T._lalin_api_cache.stencil_artifact_plan end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Kernel = T.LalinKernel
    local Stencil = T.LalinStencil
    local Schedule = T.LalinSchedule
    local CodeType = require("lalin.code_type")(T)
    local CEmit = require("lalin.c_emit")(T)

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

    function api.reduce_array_supported(reduction, info)
        local elem_ty = info and info.elem_ty or nil
        local result_ty = info and info.result_ty or nil
        if elem_ty == nil or result_ty == nil then return false, "reduce_array stencil requires elem_ty and result_ty" end
        if not same_type(elem_ty, result_ty) then return false, "reduce_array stencil currently requires matching element/result types" end
        local ok_type, err = pcall(function() c_type(elem_ty); c_type(result_ty) end)
        if not ok_type then return false, tostring(err) end
        local kind = reduction.kind
        if is_int(result_ty) then
            if kind == Value.ReductionAdd or kind == Value.ReductionMul
                or kind == Value.ReductionAnd or kind == Value.ReductionOr or kind == Value.ReductionXor
                or kind == Value.ReductionMin or kind == Value.ReductionMax then
                return true
            end
            return false, "unsupported integer reduction"
        end
        if is_float(result_ty) then
            if kind == Value.ReductionAdd or kind == Value.ReductionMul
                or kind == Value.ReductionMin or kind == Value.ReductionMax then
                return true
            end
            return false, "float reduce_array stencil only supports add/mul/min/max"
        end
        return false, "reduce_array stencil only supports integer and float scalar types"
    end

    local function binary_supported(op, ty)
        if op == Stencil.StencilBinaryAnd or op == Stencil.StencilBinaryOr or op == Stencil.StencilBinaryXor then return supports_bitwise_ty(ty) end
        return is_scalar(ty)
    end

    local function unary_supported(op, ty)
        if op == Stencil.StencilUnaryBitNot then return supports_bitwise_ty(ty) end
        return is_scalar(ty)
    end

    local artifact

    local function i32_ty()
        return Code.CodeTyInt(32, Code.CodeSigned)
    end

    local function domain(stride)
        return Stencil.StencilDomainRange1D(Code.CodeTyIndex, nil, nil, tonumber(stride) or 1, Stencil.StencilDomainForward)
    end

    local function memory(opts)
        opts = opts or {}
        return Stencil.StencilMemorySemantics(opts.copy, opts.partition, opts.scatter)
    end

    local function contig(name, role, ty, stride)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilTopologyContiguous(tonumber(stride) or 1))
    end

    local function shaped(name, role, ty, topology, stride)
        return Stencil.StencilAccess(name, role, ty, topology or Stencil.StencilTopologyContiguous(1))
    end

    local function indexed(name, role, ty, index_ty, stride)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilTopologyIndexed(index_ty, tonumber(stride) or 1))
    end

    local function scalar(name, role, ty, value)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilTopologyScalar(value))
    end

    local function reducer_desc(reduction, result_ty)
        return Stencil.StencilReducer(reduction.kind, result_ty, reduction.init, reduction.int_semantics, reduction.float_mode)
    end

    local function descriptor(vocab, stride, accesses, operator, reducer, skeleton, mem, result_ty, params)
        return Stencil.StencilDescriptor(vocab, domain(stride), accesses, operator, reducer, skeleton, mem or memory(), result_ty, params or {})
    end

    local function default_compiler_policy()
        return Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, Stencil.StencilMachineNative, {})
    end

    local function topology_unit_stride(topology)
        local cls = pvm.classof(topology)
        if cls == Stencil.StencilTopologyFieldProjection then return topology_unit_stride(topology.parent) end
        if cls == Stencil.StencilTopologySoAComponent then return topology_unit_stride(topology.parent) end
        if cls == Stencil.StencilTopologyContiguous or cls == Stencil.StencilTopologyIndexed or cls == Stencil.StencilTopologyInPlace then return tonumber(topology.stride) == 1 end
        if cls == Stencil.StencilTopologySliceDescriptor or cls == Stencil.StencilTopologyByteSpanDescriptor then return true end
        if cls == Stencil.StencilTopologyViewDescriptor then return topology.stride_const == 1 end
        return false
    end

    local function access_vector_fact(access)
        return Stencil.StencilAccessVectorFact(
            access.name,
            Stencil.StencilAliasUnknown,
            Stencil.StencilAlignmentUnknown,
            access.role == Stencil.StencilAccessRead,
            topology_unit_stride(access.topology)
        )
    end

    local function reduction_reassociable(reducer)
        if reducer == nil then return true end
        if reducer.float_mode == Code.CodeFloatStrict then return false end
        if reducer.float_mode ~= nil then return true end
        return true
    end

    local function vectorization_facts(desc)
        local access_facts = {}
        for i, access in ipairs(desc.accesses or {}) do access_facts[i] = access_vector_fact(access) end
        local reducer = desc.reducer
        return Stencil.StencilVectorizationFacts(
            access_facts,
            Stencil.StencilTripCountDynamic,
            Stencil.StencilArithmeticVectorFact(
                reduction_reassociable(reducer),
                reducer and reducer.int_semantics or nil,
                reducer and reducer.float_mode or nil
            )
        )
    end

    local function auto_vector_vocab(vocab)
        return vocab == Stencil.StencilReduce
            or vocab == Stencil.StencilMap
            or vocab == Stencil.StencilZipMap
            or vocab == Stencil.StencilScan
            or vocab == Stencil.StencilCopy
            or vocab == Stencil.StencilFill
            or vocab == Stencil.StencilCast
            or vocab == Stencil.StencilCompare
            or vocab == Stencil.StencilZipCompare
            or vocab == Stencil.StencilGather
            or vocab == Stencil.StencilScatter
            or vocab == Stencil.StencilInPlaceMap
            or vocab == Stencil.StencilCount
            or vocab == Stencil.StencilMapReduce
            or vocab == Stencil.StencilZipReduce
    end

    local function unroll_factor(info)
        local n = tonumber(info and (info.unroll or info.unroll_factor) or 1) or 1
        n = math.floor(n)
        if n < 1 then return 1 end
        if n > 16 then return 16 end
        return n
    end

    local function schedule_vector_lanes(kind)
        if Schedule == nil or pvm.classof(kind) ~= Schedule.ScheduleVector then return nil end
        if pvm.classof(kind.lanes) ~= Schedule.LaneVector then return nil end
        return tonumber(kind.lanes.lanes)
    end

    local function schedule_for_descriptor_with_info(desc, info)
        local policy = default_compiler_policy()
        local sched = info and info.schedule or nil
        if Schedule ~= nil and pvm.classof(sched) == Schedule.ScheduleVector then
            local lanes = schedule_vector_lanes(sched)
            if lanes ~= nil and lanes > 1 then
                return Stencil.StencilScheduleVector(
                    Stencil.StencilVectorFeatureNative,
                    Stencil.StencilLaneFixed(lanes),
                    Stencil.StencilVectorUnaligned,
                    sched.tail == Schedule.TailMasked and Stencil.StencilVectorMaskTail or Stencil.StencilVectorScalarTail,
                    Stencil.StencilVectorReductionHorizontal,
                    Stencil.StencilVectorCompilerCopyPatchStencil,
                    lanes,
                    tonumber(sched.unroll) or 1,
                    tonumber(sched.interleave) or 1,
                    policy,
                    vectorization_facts(desc)
                )
            end
        elseif Schedule ~= nil and (sched == Schedule.ScheduleScalarIndex or sched == Schedule.ScheduleScalarPointer or sched == Schedule.ScheduleClosedForm) then
            return Stencil.StencilScheduleScalar(policy)
        end
        local unroll = unroll_factor(info)
        if unroll > 1 and auto_vector_vocab(desc.vocab) then return Stencil.StencilScheduleUnrolled(unroll, policy, vectorization_facts(desc)) end
        if auto_vector_vocab(desc.vocab) then return Stencil.StencilScheduleAutoVector(policy, vectorization_facts(desc)) end
        return Stencil.StencilScheduleScalar(policy)
    end

    local function schedule_suffix(schedule)
        local cls = pvm.classof(schedule)
        if cls == Stencil.StencilScheduleVector then
            local unroll = tonumber(schedule.unroll) or 1
            local interleave = tonumber(schedule.interleave) or 1
            return ":v" .. tostring(schedule.lanes) .. (unroll > 1 and (":u" .. tostring(unroll)) or "") .. (interleave > 1 and (":i" .. tostring(interleave)) or ""),
                "_v" .. tostring(schedule.lanes) .. (unroll > 1 and ("_u" .. tostring(unroll)) or "") .. (interleave > 1 and ("_i" .. tostring(interleave)) or "")
        end
        if cls == Stencil.StencilScheduleUnrolled then
            return ":u" .. tostring(schedule.factor), "_u" .. tostring(schedule.factor)
        end
        return "", ""
    end

    local function instance(id, desc, abi, proofs, info)
        return Stencil.StencilInstance(id, desc, schedule_for_descriptor_with_info(desc, info), abi, proofs or {})
    end

    local function topology_has_dynamic_stride(topology)
        local cls = pvm.classof(topology)
        if cls == Stencil.StencilTopologyFieldProjection then return topology_has_dynamic_stride(topology.parent) end
        if cls == Stencil.StencilTopologySoAComponent then return topology_has_dynamic_stride(topology.parent) end
        return cls == Stencil.StencilTopologyViewDescriptor and topology.stride_const == nil
    end

    local function dynamic_stride_accesses(desc)
        local out = {}
        for _, access in ipairs(desc.accesses or {}) do
            if topology_has_dynamic_stride(access.topology) then
                out[#out + 1] = access
            end
        end
        return out
    end

    local function stride_param_name(access)
        return sanitize(access.name) .. "_stride"
    end

    local abi_params_with_topologies

    local function abi_with_dynamic_strides(desc, params, result)
        local out = {}
        params = abi_params_with_topologies(desc, params)
        for i = 1, #(params or {}) do out[i] = params[i] end
        for _, _access in ipairs(dynamic_stride_accesses(desc)) do
            out[#out + 1] = i32_ty()
        end
        return Stencil.StencilAbi(out, result)
    end

    local function params_with_dynamic_strides(desc, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = params[i] end
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            out[#out + 1] = "int32_t " .. stride_param_name(access)
        end
        return out
    end

    local function field_topology(topology)
        local cls = pvm.classof(topology)
        if cls == Stencil.StencilTopologyFieldProjection then return topology end
        return nil
    end

    local function pointer_accesses(desc)
        local out = {}
        for _, access in ipairs(desc and desc.accesses or {}) do
            if pvm.classof(access.topology) ~= Stencil.StencilTopologyScalar then out[#out + 1] = access end
        end
        return out
    end

    local function param_decl_for_access(access, default)
        local field = field_topology(access.topology)
        if field == nil then return default end
        local name = default:match("%*%s*([_%a][_%w]*)") or access.name
        local is_const = default:match("^%s*const%s+") ~= nil
        return (is_const and "const " or "") .. c_type(field.record_ty) .. " *" .. name
    end

    local function abi_param_type_for_access(access, default_ty)
        local field = field_topology(access.topology)
        if field == nil then return default_ty end
        return Code.CodeTyDataPtr(field.record_ty)
    end

    abi_params_with_topologies = function(desc, params)
        local out = {}
        local accesses = pointer_accesses(desc)
        local access_i = 1
        for i = 1, #(params or {}) do
            local p = params[i]
            if pvm.classof(p) == Code.CodeTyDataPtr and accesses[access_i] ~= nil then
                out[i] = abi_param_type_for_access(accesses[access_i], p)
                access_i = access_i + 1
            else
                out[i] = p
            end
        end
        return out
    end

    local function topology_suffix_for(access, topology)
        local top = access.topology
        local cls = pvm.classof(topology)
        if cls == Stencil.StencilTopologyViewDescriptor then
            return "_view_" .. (topology.stride_const ~= nil and ("s" .. tostring(topology.stride_const)) or "sdyn")
        end
        if cls == Stencil.StencilTopologyFieldProjection then
            return topology_suffix_for(access, topology.parent) .. "_field_" .. sanitize(topology.field_name) .. "_o" .. tostring(topology.field_offset or 0)
        end
        if cls == Stencil.StencilTopologySoAComponent then
            return topology_suffix_for(access, topology.parent) .. "_soa_" .. sanitize(topology.field_name) .. "_c" .. tostring(topology.component_index or 0)
        end
        if cls == Stencil.StencilTopologySliceDescriptor then
            return "_slice"
        end
        if cls == Stencil.StencilTopologyByteSpanDescriptor then
            return "_bytespan"
        end
        return ""
    end

    local function topology_suffix(access)
        local suffix = topology_suffix_for(access, access.topology)
        if suffix == "" then return "" end
        return "_" .. sanitize(access.name) .. suffix
    end

    local function descriptor_symbol_suffix(desc)
        local out = {}
        for _, access in ipairs(desc.accesses or {}) do
            local suffix = topology_suffix(access)
            if suffix ~= "" then out[#out + 1] = suffix end
        end
        return table.concat(out)
    end

    local function scheduled_instance(id, symbol, desc, abi, proofs, info)
        local selected_schedule = schedule_for_descriptor_with_info(desc, info or {})
        local suffix, symbol_suffix = schedule_suffix(selected_schedule)
        if suffix ~= "" then id = Stencil.StencilInstanceId(id.text .. suffix) end
        if symbol_suffix ~= "" then symbol = Stencil.StencilSymbolId(symbol.text .. symbol_suffix) end
        return instance(id, desc, abi, proofs, info), symbol
    end

    local source_params

    function artifact(instance, symbol, signature)
        local suffix = descriptor_symbol_suffix(instance.descriptor)
        if suffix ~= "" then
            local old_symbol = symbol.text
            symbol = Stencil.StencilSymbolId(old_symbol .. suffix)
            signature = signature:gsub(old_symbol, symbol.text, 1)
            instance = Stencil.StencilInstance(
                Stencil.StencilInstanceId(instance.id.text .. suffix),
                instance.descriptor,
                instance.schedule,
                instance.abi,
                instance.proofs
            )
        end
        return Stencil.StencilArtifact(instance, Stencil.StencilProviderC, symbol, signature)
    end

    local function void_desc_decl(symbol, desc, args)
        return void_decl(symbol, source_params({ instance = { descriptor = desc } }, args))
    end

    local function result_desc_decl(symbol, result_ty, desc, args)
        return result_decl(symbol, result_ty, source_params({ instance = { descriptor = desc } }, args))
    end

    local function int32_desc_decl(symbol, desc, args)
        return int32_decl(symbol, source_params({ instance = { descriptor = desc } }, args))
    end

    function api.reduce_array_artifact(reduction, plan, info)
        local elem_ty = assert(info.elem_ty, "stencil_artifact_plan.reduce_array_artifact requires elem_ty")
        local result_ty = assert(info.result_ty, "stencil_artifact_plan.reduce_array_artifact requires result_ty")
        local stride = assert(info.step_num, "stencil_artifact_plan.reduce_array_artifact requires step_num")
        local supported, reason = api.reduce_array_supported(reduction, info)
        if not supported then error("stencil_artifact_plan: unsupported reduce_array artifact: " .. tostring(reason), 2) end
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamReduction("reduction", reduction.kind),
            Stencil.StencilParamNumber("stride", stride),
            Stencil.StencilParamValueExpr("init", reduction.init),
        }
        local desc = descriptor(
            Stencil.StencilReduce,
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reduction.init),
            },
            nil,
            reducer_desc(reduction, result_ty),
            Stencil.StencilSkeletonReduce,
            memory(),
            result_ty,
            params
        )
        local selected_schedule = schedule_for_descriptor_with_info(desc, info)
        local suffix, symbol_suffix = schedule_suffix(selected_schedule)
        local id = Stencil.StencilInstanceId(reduce_instance_id(elem_ty, result_ty, reduction.kind, stride).text .. suffix)
        local symbol = Stencil.StencilSymbolId(reduce_symbol_id(elem_ty, result_ty, reduction.kind, stride).text .. symbol_suffix)
        local inst = instance(
            id,
            desc,
            abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty(), result_ty }, result_ty),
            proof_list(plan),
            { schedule = info and info.schedule, unroll = info and info.unroll, unroll_factor = info and info.unroll_factor }
        )
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, { "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    function api.map_array_artifact(op, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_artifact_plan: unsupported map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:map_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_map_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("op", unary_name(op)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilMap,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.src_topology or info.array_topology, stride),
            },
            Stencil.StencilOpUnary(op, result_ty),
            nil,
            Stencil.StencilSkeletonApply,
            memory(),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.zip_map_array_artifact(op, info)
        local lhs_ty, rhs_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) or not same_type(lhs_ty, result_ty) then error("stencil_artifact_plan: zip_map_array currently requires matching lhs/rhs/result types", 2) end
        if not binary_supported(op, result_ty) then error("stencil_artifact_plan: unsupported zip_map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_map_array:" .. type_name(lhs_ty) .. ":" .. binary_name(op) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_map_array_" .. type_name(lhs_ty) .. "_" .. binary_name(op) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("lhs_ty", lhs_ty),
            Stencil.StencilParamType("rhs_ty", rhs_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("op", binary_name(op)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilZipMap,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("lhs", Stencil.StencilAccessRead, lhs_ty, info.lhs_topology, stride),
                shaped("rhs", Stencil.StencilAccessRead, rhs_ty, info.rhs_topology, stride),
            },
            Stencil.StencilOpBinary(op, result_ty),
            nil,
            Stencil.StencilSkeletonApply,
            memory(),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", "const " .. c_type(lhs_ty) .. " *lhs", "const " .. c_type(rhs_ty) .. " *rhs", "int32_t start", "int32_t stop" }))
    end

    function api.scan_array_artifact(reduction, plan, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        local mode = info.mode or Stencil.StencilScanInclusive
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = elem_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported scan_array artifact: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:scan_array:" .. type_name(elem_ty) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":" .. scan_mode_name(mode) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_scan_array_" .. type_name(elem_ty) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_" .. scan_mode_name(mode) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamReduction("reduction", reduction.kind),
            Stencil.StencilParamText("mode", scan_mode_name(mode)),
            Stencil.StencilParamNumber("stride", stride),
            Stencil.StencilParamValueExpr("init", reduction.init),
        }
        local desc = descriptor(
            Stencil.StencilScan,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reduction.init),
            },
            nil,
            reducer_desc(reduction, result_ty),
            Stencil.StencilSkeletonScan(mode),
            memory(),
            result_ty,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty(), result_ty }, result_ty), proof_list(plan), info)
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, { c_type(result_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    function api.copy_array_artifact(info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local semantics = info.semantics or Stencil.StencilCopyNoOverlap
        local id = Stencil.StencilInstanceId("stencil:copy_array:" .. type_name(elem_ty) .. ":" .. copy_semantics_name(semantics) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_copy_array_" .. type_name(elem_ty) .. "_" .. copy_semantics_name(semantics) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("semantics", copy_semantics_name(semantics)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilCopy,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_topology, stride),
                shaped("src", Stencil.StencilAccessRead, elem_ty, info.src_topology, stride),
            },
            Stencil.StencilOpIdentity,
            nil,
            Stencil.StencilSkeletonCopy(semantics),
            memory({ copy = semantics }),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *src", "int32_t start", "int32_t stop" }))
    end

    function api.fill_array_artifact(info)
        local elem_ty, stride, value = assert(info.elem_ty), assert(info.step_num or info.stride or 1), assert(info.value)
        local id = Stencil.StencilInstanceId("stencil:fill_array:" .. type_name(elem_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_fill_array_" .. type_name(elem_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamValueExpr("value", value),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilFill,
            stride,
            { shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_topology, stride) },
            Stencil.StencilOpFill(value),
            nil,
            Stencil.StencilSkeletonApply,
            memory(),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty(), elem_ty }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", "int32_t start", "int32_t stop", scalar_param_ty(elem_ty) .. " value" }))
    end

    function api.find_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:find_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_find_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("pred", pred_name(pred)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local not_found = Value.ValueExprConst(Code.CodeConstLiteral(i32_ty(), Core.LitInt("-1")))
        local desc = descriptor(
            Stencil.StencilFind,
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("index", Stencil.StencilAccessControlResult, i32_ty(), not_found),
            },
            Stencil.StencilOpPredicate(pred, i32_ty()),
            nil,
            Stencil.StencilSkeletonFind(not_found),
            memory(),
            i32_ty(),
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, { "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.partition_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local semantics = info.semantics or Stencil.StencilPartitionStable
        local id = Stencil.StencilInstanceId("stencil:partition_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":" .. partition_semantics_name(semantics) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_partition_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_" .. partition_semantics_name(semantics) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("pred", pred_name(pred)),
            Stencil.StencilParamText("semantics", partition_semantics_name(semantics)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilPartition,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("split", Stencil.StencilAccessControlResult, i32_ty(), nil),
            },
            Stencil.StencilOpPredicate(pred, i32_ty()),
            nil,
            Stencil.StencilSkeletonPartition(semantics),
            memory({ partition = semantics }),
            i32_ty(),
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.cast_array_artifact(op, info)
        local src_ty, dst_ty, stride = assert(info.src_ty), assert(info.dst_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:cast_array:" .. type_name(src_ty) .. ":" .. cast_name(op) .. ":to:" .. type_name(dst_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_cast_array_" .. type_name(src_ty) .. "_" .. cast_name(op) .. "_to_" .. type_name(dst_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("src_ty", src_ty),
            Stencil.StencilParamType("dst_ty", dst_ty),
            Stencil.StencilParamText("op", cast_name(op)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilCast,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, dst_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, src_ty, info.src_topology or info.array_topology, stride),
            },
            Stencil.StencilOpCast(op, src_ty, dst_ty),
            nil,
            Stencil.StencilSkeletonApply,
            memory(),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(dst_ty), Code.CodeTyDataPtr(src_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(dst_ty) .. " *dst", "const " .. c_type(src_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.compare_array_artifact(pred, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:compare_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_compare_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("pred", pred_name(pred)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilCompare,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.src_topology or info.array_topology, stride),
            },
            Stencil.StencilOpPredicate(pred, result_ty),
            nil,
            Stencil.StencilSkeletonApply,
            memory(),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.zip_compare_array_artifact(cmp, info)
        local lhs_ty, rhs_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) then error("stencil_artifact_plan: zip_compare_array currently requires matching lhs/rhs types", 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_compare_array:" .. type_name(lhs_ty) .. ":" .. cmp_name(cmp) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_compare_array_" .. type_name(lhs_ty) .. "_" .. cmp_name(cmp) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("lhs_ty", lhs_ty),
            Stencil.StencilParamType("rhs_ty", rhs_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("cmp", cmp_name(cmp)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilZipCompare,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("lhs", Stencil.StencilAccessRead, lhs_ty, info.lhs_topology, stride),
                shaped("rhs", Stencil.StencilAccessRead, rhs_ty, info.rhs_topology, stride),
            },
            Stencil.StencilOpCompare(cmp, result_ty),
            nil,
            Stencil.StencilSkeletonApply,
            memory(),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", "const " .. c_type(lhs_ty) .. " *lhs", "const " .. c_type(rhs_ty) .. " *rhs", "int32_t start", "int32_t stop" }))
    end

    function api.gather_array_artifact(info)
        local elem_ty, index_ty, stride = assert(info.elem_ty), assert(info.index_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:gather_array:" .. type_name(elem_ty) .. ":index:" .. type_name(index_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_gather_array_" .. type_name(elem_ty) .. "_idx_" .. type_name(index_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("index_ty", index_ty),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilGather,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_topology, stride),
                indexed("src", Stencil.StencilAccessRead, elem_ty, index_ty, stride),
                shaped("idx", Stencil.StencilAccessRead, index_ty, info.index_topology, stride),
            },
            Stencil.StencilOpIdentity,
            nil,
            Stencil.StencilSkeletonApply,
            memory(),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(index_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *src", "const " .. c_type(index_ty) .. " *idx", "int32_t start", "int32_t stop" }))
    end

    function api.scatter_array_artifact(info)
        local elem_ty, index_ty, stride = assert(info.elem_ty), assert(info.index_ty), assert(info.step_num or info.stride or 1)
        local conflicts = info.conflicts or Stencil.StencilScatterUniqueIndices
        local id = Stencil.StencilInstanceId("stencil:scatter_array:" .. type_name(elem_ty) .. ":index:" .. type_name(index_ty) .. ":" .. scatter_conflict_name(conflicts) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_scatter_array_" .. type_name(elem_ty) .. "_idx_" .. type_name(index_ty) .. "_" .. scatter_conflict_name(conflicts) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("index_ty", index_ty),
            Stencil.StencilParamText("conflicts", scatter_conflict_name(conflicts)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilScatter,
            stride,
            {
                indexed("dst", Stencil.StencilAccessWrite, elem_ty, index_ty, stride),
                shaped("src", Stencil.StencilAccessRead, elem_ty, info.src_topology, stride),
                shaped("idx", Stencil.StencilAccessRead, index_ty, info.index_topology, stride),
            },
            Stencil.StencilOpIdentity,
            nil,
            Stencil.StencilSkeletonApply,
            memory({ scatter = conflicts }),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(index_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *src", "const " .. c_type(index_ty) .. " *idx", "int32_t start", "int32_t stop" }))
    end

    function api.in_place_map_array_artifact(op, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_artifact_plan: unsupported in_place_map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:in_place_map_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_in_place_map_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("op", unary_name(op)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilInPlaceMap,
            stride,
            { Stencil.StencilAccess("xs", Stencil.StencilAccessReadWrite, elem_ty, info.src_topology or info.dst_topology or Stencil.StencilTopologyInPlace(stride)) },
            Stencil.StencilOpUnary(op, elem_ty),
            nil,
            Stencil.StencilSkeletonApply,
            memory(),
            nil,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.count_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:count_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_count_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("pred", pred_name(pred)),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilCount,
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("count", Stencil.StencilAccessReduce, i32_ty(), nil),
            },
            Stencil.StencilOpPredicate(pred, i32_ty()),
            nil,
            Stencil.StencilSkeletonReduce,
            memory(),
            i32_ty(),
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, { "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.map_reduce_array_artifact(op, reduction, plan, info)
        local elem_ty, mapped_ty, result_ty, stride = assert(info.elem_ty), assert(info.mapped_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_artifact_plan: unsupported map_reduce_array op/type", 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = mapped_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported map_reduce_array reduction: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:map_reduce_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_map_reduce_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("mapped_ty", mapped_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("op", unary_name(op)),
            Stencil.StencilParamReduction("reduction", reduction.kind),
            Stencil.StencilParamValueExpr("init", reduction.init),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilMapReduce,
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reduction.init),
            },
            Stencil.StencilOpUnary(op, mapped_ty),
            reducer_desc(reduction, result_ty),
            Stencil.StencilSkeletonReduce,
            memory(),
            result_ty,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty(), result_ty }, result_ty), proof_list(plan), info)
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, { "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    function api.zip_reduce_array_artifact(op, reduction, plan, info)
        local lhs_ty, rhs_ty, mapped_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.mapped_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) or not same_type(lhs_ty, mapped_ty) then error("stencil_artifact_plan: zip_reduce_array currently requires matching lhs/rhs/mapped types", 2) end
        if not binary_supported(op, mapped_ty) then error("stencil_artifact_plan: unsupported zip_reduce_array op/type", 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = mapped_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported zip_reduce_array reduction: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_reduce_array:" .. type_name(lhs_ty) .. ":" .. binary_name(op) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_reduce_array_" .. type_name(lhs_ty) .. "_" .. binary_name(op) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local params = {
            Stencil.StencilParamType("lhs_ty", lhs_ty),
            Stencil.StencilParamType("rhs_ty", rhs_ty),
            Stencil.StencilParamType("mapped_ty", mapped_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("op", binary_name(op)),
            Stencil.StencilParamReduction("reduction", reduction.kind),
            Stencil.StencilParamValueExpr("init", reduction.init),
            Stencil.StencilParamNumber("stride", stride),
        }
        local desc = descriptor(
            Stencil.StencilZipReduce,
            stride,
            {
                shaped("lhs", Stencil.StencilAccessRead, lhs_ty, info.lhs_topology, stride),
                shaped("rhs", Stencil.StencilAccessRead, rhs_ty, info.rhs_topology, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reduction.init),
            },
            Stencil.StencilOpBinary(op, mapped_ty),
            reducer_desc(reduction, result_ty),
            Stencil.StencilSkeletonReduce,
            memory(),
            result_ty,
            params
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), i32_ty(), i32_ty(), result_ty }, result_ty), proof_list(plan), info)
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, { "const " .. c_type(lhs_ty) .. " *lhs", "const " .. c_type(rhs_ty) .. " *rhs", "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    local function access_named(desc, name)
        for _, a in ipairs(desc.accesses or {}) do
            if a.name == name then return a end
        end
        error("stencil_artifact_plan: descriptor missing access " .. tostring(name), 3)
    end

    local function topology_stride(access)
        local top = access.topology
        if top.stride ~= nil then return top.stride end
        return 1
    end

    local function domain_stride(desc)
        local dom = desc and desc.domain
        if pvm.classof(dom) == Stencil.StencilDomainRange1D then return tonumber(dom.step) or 1 end
        return 1
    end

    local function indexed_ty(access)
        local top = access.topology
        if pvm.classof(top) ~= Stencil.StencilTopologyIndexed then
            error("stencil_artifact_plan: descriptor access is not indexed: " .. tostring(access.name), 3)
        end
        return top.index_ty
    end

    local function expect_operator(desc, cls)
        local op = desc.operator
        if pvm.classof(op) ~= cls then error("stencil_artifact_plan: descriptor operator mismatch", 3) end
        return op
    end

    local function expect_skeleton(desc, cls)
        local sk = desc.skeleton
        if pvm.classof(sk) ~= cls then error("stencil_artifact_plan: descriptor skeleton mismatch", 3) end
        return sk
    end

    local function local_shape(kind, fields)
        fields.kind = kind
        return fields
    end

    local function artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local vocab = desc.vocab
        if vocab == Stencil.StencilReduce then
            local xs = access_named(desc, "xs")
            local red = assert(desc.reducer, "stencil_artifact_plan: reduce descriptor missing reducer")
            return local_shape("reduce_array", { elem_ty = xs.ty, result_ty = red.result_ty, reduction = red.reduction, int_semantics = red.int_semantics, float_mode = red.float_mode, init = red.init, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilMap then
            local dst, xs = access_named(desc, "dst"), access_named(desc, "xs")
            local op = expect_operator(desc, Stencil.StencilOpUnary)
            return local_shape("map_array", { elem_ty = xs.ty, result_ty = dst.ty, op = op.op, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilZipMap then
            local dst, lhs, rhs = access_named(desc, "dst"), access_named(desc, "lhs"), access_named(desc, "rhs")
            local op = expect_operator(desc, Stencil.StencilOpBinary)
            return local_shape("zip_map_array", { lhs_ty = lhs.ty, rhs_ty = rhs.ty, result_ty = dst.ty, op = op.op, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilScan then
            local dst, xs = access_named(desc, "dst"), access_named(desc, "xs")
            local red = assert(desc.reducer, "stencil_artifact_plan: scan descriptor missing reducer")
            local sk = expect_skeleton(desc, Stencil.StencilSkeletonScan)
            return local_shape("scan_array", { elem_ty = xs.ty, result_ty = dst.ty, reduction = red.reduction, int_semantics = red.int_semantics, float_mode = red.float_mode, init = red.init, mode = sk.mode, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilCopy then
            local src = access_named(desc, "src")
            local sk = expect_skeleton(desc, Stencil.StencilSkeletonCopy)
            return local_shape("copy_array", { elem_ty = src.ty, semantics = sk.semantics, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilFill then
            local dst = access_named(desc, "dst")
            local op = expect_operator(desc, Stencil.StencilOpFill)
            return local_shape("fill_array", { elem_ty = dst.ty, value = op.value, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilFind then
            local xs = access_named(desc, "xs")
            local op = expect_operator(desc, Stencil.StencilOpPredicate)
            return local_shape("find_array", { elem_ty = xs.ty, pred = op.pred, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilPartition then
            local xs = access_named(desc, "xs")
            local op = expect_operator(desc, Stencil.StencilOpPredicate)
            local sk = expect_skeleton(desc, Stencil.StencilSkeletonPartition)
            return local_shape("partition_array", { elem_ty = xs.ty, pred = op.pred, semantics = sk.semantics, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilCast then
            local xs = access_named(desc, "xs")
            local op = expect_operator(desc, Stencil.StencilOpCast)
            return local_shape("cast_array", { src_ty = op.from, dst_ty = op.to, op = op.op, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilCompare then
            local xs = access_named(desc, "xs")
            local op = expect_operator(desc, Stencil.StencilOpPredicate)
            return local_shape("compare_array", { elem_ty = xs.ty, result_ty = op.result_ty, pred = op.pred, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilZipCompare then
            local lhs, rhs = access_named(desc, "lhs"), access_named(desc, "rhs")
            local op = expect_operator(desc, Stencil.StencilOpCompare)
            return local_shape("zip_compare_array", { lhs_ty = lhs.ty, rhs_ty = rhs.ty, result_ty = op.result_ty, cmp = op.cmp, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilGather then
            local src = access_named(desc, "src")
            return local_shape("gather_array", { elem_ty = src.ty, index_ty = indexed_ty(src), stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilScatter then
            local dst = access_named(desc, "dst")
            return local_shape("scatter_array", { elem_ty = dst.ty, index_ty = indexed_ty(dst), conflicts = desc.memory.scatter, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilInPlaceMap then
            local xs = access_named(desc, "xs")
            local op = expect_operator(desc, Stencil.StencilOpUnary)
            return local_shape("in_place_map_array", { elem_ty = xs.ty, op = op.op, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilCount then
            local xs = access_named(desc, "xs")
            local op = expect_operator(desc, Stencil.StencilOpPredicate)
            return local_shape("count_array", { elem_ty = xs.ty, pred = op.pred, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilMapReduce then
            local xs = access_named(desc, "xs")
            local op = expect_operator(desc, Stencil.StencilOpUnary)
            local red = assert(desc.reducer, "stencil_artifact_plan: map_reduce descriptor missing reducer")
            return local_shape("map_reduce_array", { elem_ty = xs.ty, mapped_ty = op.result_ty, result_ty = red.result_ty, op = op.op, reduction = red.reduction, int_semantics = red.int_semantics, float_mode = red.float_mode, init = red.init, stride = domain_stride(desc) })
        end
        if vocab == Stencil.StencilZipReduce then
            local lhs, rhs = access_named(desc, "lhs"), access_named(desc, "rhs")
            local op = expect_operator(desc, Stencil.StencilOpBinary)
            local red = assert(desc.reducer, "stencil_artifact_plan: zip_reduce descriptor missing reducer")
            return local_shape("zip_reduce_array", { lhs_ty = lhs.ty, rhs_ty = rhs.ty, mapped_ty = op.result_ty, result_ty = red.result_ty, op = op.op, reduction = red.reduction, int_semantics = red.int_semantics, float_mode = red.float_mode, init = red.init, stride = domain_stride(desc) })
        end
        error("stencil_artifact_plan: unsupported stencil descriptor", 3)
    end

    source_params = function(artifact, params)
        local desc = artifact.instance.descriptor
        local accesses = pointer_accesses(desc)
        local access_i = 1
        local out = {}
        for i = 1, #(params or {}) do
            local p = params[i]
            if p:match("%*") and accesses[access_i] ~= nil then
                out[i] = param_decl_for_access(accesses[access_i], p)
                access_i = access_i + 1
            else
                out[i] = p
            end
        end
        return params_with_dynamic_strides(desc, out)
    end


    api.artifact_shape = artifact_shape
    api.source_params = source_params
    api.access_named = access_named
    api.stride_param_name = stride_param_name
    api.dynamic_stride_accesses = dynamic_stride_accesses

    T._lalin_api_cache.stencil_artifact_plan = api
    return api
end

return bind_context
