local pvm = require("lalin.pvm")
local bit = require("bit")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function stable_hash32(s)
    local h = 2166136261
    for i = 1, #s do h = (bit.bxor(h, s:byte(i)) * 16777619) % 4294967296 end
    return string.format("%08x", h)
end

local function stable_repr(v, seen)
    local tv = type(v)
    if tv == "nil" then return "nil" end
    if tv == "boolean" or tv == "number" then return tostring(v) end
    if tv == "string" then return string.format("%q", v) end
    if tv ~= "table" then return tv .. ":" .. tostring(v) end
    local cls = pvm.classof(v)
    if tostring(cls) == "Class(LalinCode.CodeValueId)" then return tostring(cls) .. "{_}" end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local out = {}
    if cls and cls.__fields then
        out[#out + 1] = tostring(cls)
        out[#out + 1] = "{"
        for i, field in ipairs(cls.__fields or {}) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = field.name
            out[#out + 1] = "="
            out[#out + 1] = stable_repr(rawget(v, field.name), seen)
        end
        out[#out + 1] = "}"
    else
        local keys = {}
        for key in pairs(v) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        out[#out + 1] = "{"
        for i, key in ipairs(keys) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = stable_repr(key, seen)
            out[#out + 1] = "="
            out[#out + 1] = stable_repr(v[key], seen)
        end
        out[#out + 1] = "}"
    end
    seen[v] = nil
    return table.concat(out)
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
    local ReductionAlgebra = require("lalin.reduction_algebra")(T)

    local api = {}

    local function type_name(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if ty == Code.CodeTyIndex then return "index" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        return sanitize(CodeType.code_type_key(ty))
    end

    local function c_type(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyArray then return "ml_array_" .. tostring(ty.count) .. "_" .. type_name(ty.elem) end
        if cls == Code.CodeTyClosure then return "ml_closure_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyVector then return "ml_vector_" .. tostring(ty.lanes) .. "_" .. type_name(ty.elem) end
        if cls == Code.CodeTyImportedCFuncPtr then return "ml_cfuncptr_" .. sanitize(ty.sig.text) end
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
        if op == Stencil.StencilBinaryDiv then return "div" end
        if op == Stencil.StencilBinaryMod then return "mod" end
        if op == Stencil.StencilBinaryAnd then return "and" end
        if op == Stencil.StencilBinaryOr then return "or" end
        if op == Stencil.StencilBinaryXor then return "xor" end
        if op == Stencil.StencilBinaryShl then return "shl" end
        if op == Stencil.StencilBinaryLShr then return "lshr" end
        if op == Stencil.StencilBinaryAShr then return "ashr" end
        if op == Stencil.StencilBinaryMin then return "min" end
        if op == Stencil.StencilBinaryMax then return "max" end
        return "binary"
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

    local function pred_name(pred)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return "nonzero" end
        if cls == Stencil.StencilPredCompareConst then return cmp_name(pred.cmp) end
        if cls == Stencil.StencilPredRange then return "range_" .. cmp_name(pred.lower_cmp) .. "_" .. cmp_name(pred.upper_cmp) end
        if cls == Stencil.StencilPredAnd then return "and" .. tostring(#(pred.terms or {})) end
        if cls == Stencil.StencilPredOr then return "or" .. tostring(#(pred.terms or {})) end
        if cls == Stencil.StencilPredNot then return "not_" .. pred_name(pred.term) end
        if cls == Stencil.StencilPredIsNaN then return "isnan" end
        if cls == Stencil.StencilPredIsInf then return "isinf" end
        if cls == Stencil.StencilPredIsFinite then return "isfinite" end
        return "pred"
    end

    local function select_name(pred)
        return pred_name(pred)
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

    local function const_elem_ptr_decl(ty, name)
        return c_type(ty) .. " const *" .. name
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

    local function same_source_type(a, b)
        if a == b then return true end
        if a == nil or b == nil then return false end
        return tostring(a) == tostring(b)
    end

    local function same_type(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        if ac == Code.CodeTyDataPtr then
            if a.pointee == nil or b.pointee == nil then return a.pointee == b.pointee end
            return same_type(a.pointee, b.pointee)
        end
        if ac == Code.CodeTyCodePtr then return a.sig == b.sig end
        if ac == Code.CodeTyNamed then return a.module_name == b.module_name and a.type_name == b.type_name end
        if ac == Code.CodeTyArray then return a.count == b.count and same_type(a.elem, b.elem) end
        if ac == Code.CodeTySlice or ac == Code.CodeTyView then return same_type(a.elem, b.elem) end
        if ac == Code.CodeTyHandle then return same_type(a.repr, b.repr) and same_source_type(a.source_ty, b.source_ty) end
        if ac == Code.CodeTyLease then return same_type(a.base, b.base) and same_source_type(a.source_ty, b.source_ty) end
        if ac == Code.CodeTyClosure then return a.sig == b.sig end
        if ac == Code.CodeTyImportedC then return a.id == b.id or (a.id.module_name == b.id.module_name and a.id.spelling == b.id.spelling) end
        if ac == Code.CodeTyImportedCFuncPtr then return a.sig == b.sig end
        if ac == Code.CodeTyVector then return a.lanes == b.lanes and same_type(a.elem, b.elem) end
        return false
    end

    local function is_scalar(ty)
        local cls = pvm.classof(ty)
        return cls == Code.CodeTyInt or cls == Code.CodeTyFloat or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function default_int_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
    end

    local function element_int_semantics(ty, info)
        local cls = pvm.classof(ty)
        if cls ~= Code.CodeTyInt and ty ~= Code.CodeTyIndex and ty ~= Code.CodeTyBool8 then return nil end
        return info and (info.int_semantics or info.semantics) or default_int_semantics()
    end

    local function element_float_mode(ty, info)
        if pvm.classof(ty) ~= Code.CodeTyFloat then return nil end
        return info and info.float_mode or Code.CodeFloatStrict
    end

    local function element_unary_operator(op, result_ty, info)
        return Stencil.StencilOpUnary(op, result_ty, element_int_semantics(result_ty, info), element_float_mode(result_ty, info))
    end

    local function element_binary_operator(op, result_ty, info)
        return Stencil.StencilOpBinary(op, result_ty, element_int_semantics(result_ty, info), element_float_mode(result_ty, info))
    end

    local function predicate_checked(pred, operand_ty)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return pred end
        if cls == Stencil.StencilPredCompareConst or cls == Stencil.StencilPredRange or cls == Stencil.StencilPredIsNaN or cls == Stencil.StencilPredIsInf or cls == Stencil.StencilPredIsFinite then
            if not same_type(pred.operand_ty, operand_ty) then error("stencil_artifact_plan: predicate operand type does not match stencil element type", 3) end
            if (cls == Stencil.StencilPredIsNaN or cls == Stencil.StencilPredIsInf or cls == Stencil.StencilPredIsFinite) and not is_float(operand_ty) then
                error("stencil_artifact_plan: float-class predicate requires a float operand type", 3)
            end
            return pred
        end
        if cls == Stencil.StencilPredAnd or cls == Stencil.StencilPredOr then
            for _, term in ipairs(pred.terms or {}) do predicate_checked(term, operand_ty) end
            return pred
        end
        if cls == Stencil.StencilPredNot then
            predicate_checked(pred.term, operand_ty)
            return pred
        end
        error("stencil_artifact_plan: unsupported predicate", 3)
        return pred
    end

    local function supports_bitwise_ty(ty)
        return pvm.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyBool8
    end

    local function supports_div_ty(ty)
        return pvm.classof(ty) == Code.CodeTyInt or pvm.classof(ty) == Code.CodeTyFloat or ty == Code.CodeTyIndex
    end

    local function supports_integer_arithmetic_ty(ty)
        return pvm.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyIndex
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
        if op == Stencil.StencilBinaryDiv then return supports_div_ty(ty) end
        if op == Stencil.StencilBinaryMod then return supports_integer_arithmetic_ty(ty) end
        if op == Stencil.StencilBinaryShl or op == Stencil.StencilBinaryLShr or op == Stencil.StencilBinaryAShr then return supports_bitwise_ty(ty) end
        return is_scalar(ty)
    end

    local function unary_supported(op, ty)
        if op == Stencil.StencilUnaryIdentity then return ty ~= Code.CodeTyVoid end
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
        return opts or {}
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

    local function reducer_identity(reduction, result_ty)
        local identity, reason = ReductionAlgebra.identity_expr(reduction.kind, result_ty)
        if identity == nil then error("stencil_artifact_plan: reduction has no identity: " .. tostring(reason), 3) end
        return identity
    end

    local function reducer_desc(reduction, result_ty)
        return Stencil.StencilReducer(reduction.kind, result_ty, reducer_identity(reduction, result_ty), reduction.int_semantics, reduction.float_mode)
    end

    local function descriptor(vocab, stride, accesses, operator, reducer, attrs, mem, result_ty)
        attrs = attrs or {}
        local dom = domain(stride)
        if vocab == Stencil.StencilReduce then
            return Stencil.StencilDescriptorReduce(dom, accesses, assert(reducer, "reduce descriptor requires reducer"), assert(result_ty, "reduce descriptor requires result type"))
        end
        if vocab == Stencil.StencilMap then return Stencil.StencilDescriptorMap(dom, accesses, assert(operator, "map descriptor requires operator")) end
        if vocab == Stencil.StencilZipMap then return Stencil.StencilDescriptorZipMap(dom, accesses, assert(operator, "zip-map descriptor requires operator")) end
        if vocab == Stencil.StencilScan then
            return Stencil.StencilDescriptorScan(dom, accesses, assert(reducer, "scan descriptor requires reducer"), assert(attrs.mode, "scan descriptor requires mode"), assert(result_ty, "scan descriptor requires result type"))
        end
        if vocab == Stencil.StencilCopy then
            return Stencil.StencilDescriptorCopy(dom, accesses, assert(attrs.semantics, "copy descriptor requires semantics"))
        end
        if vocab == Stencil.StencilFill then return Stencil.StencilDescriptorFill(dom, accesses, assert(operator, "fill descriptor requires operator")) end
        if vocab == Stencil.StencilFind then
            local op = assert(operator, "find descriptor requires predicate operator")
            return Stencil.StencilDescriptorFind(dom, accesses, op.pred, assert(attrs.not_found, "find descriptor requires not_found"), assert(result_ty, "find descriptor requires result type"))
        end
        if vocab == Stencil.StencilPartition then
            local op = assert(operator, "partition descriptor requires predicate operator")
            return Stencil.StencilDescriptorPartition(dom, accesses, op.pred, assert(attrs.semantics, "partition descriptor requires semantics"), assert(result_ty, "partition descriptor requires result type"))
        end
        if vocab == Stencil.StencilCast then return Stencil.StencilDescriptorCast(dom, accesses, assert(operator, "cast descriptor requires operator")) end
        if vocab == Stencil.StencilCompare then
            local op = assert(operator, "compare descriptor requires predicate operator")
            return Stencil.StencilDescriptorCompare(dom, accesses, op.pred, op.result_ty)
        end
        if vocab == Stencil.StencilZipCompare then
            local op = assert(operator, "zip-compare descriptor requires compare operator")
            return Stencil.StencilDescriptorZipCompare(dom, accesses, op.cmp, op.result_ty)
        end
        if vocab == Stencil.StencilSelect then
            local op = assert(operator, "select descriptor requires select operator")
            return Stencil.StencilDescriptorSelect(dom, accesses, op.pred, op.result_ty)
        end
        if vocab == Stencil.StencilGather then return Stencil.StencilDescriptorGather(dom, accesses) end
        if vocab == Stencil.StencilScatter then return Stencil.StencilDescriptorScatter(dom, accesses, assert((mem or {}).scatter, "scatter descriptor requires conflict semantics")) end
        if vocab == Stencil.StencilInPlaceMap then return Stencil.StencilDescriptorInPlaceMap(dom, accesses, assert(operator, "in-place map descriptor requires operator")) end
        if vocab == Stencil.StencilCount then
            local op = assert(operator, "count descriptor requires predicate operator")
            return Stencil.StencilDescriptorCount(dom, accesses, op.pred, assert(result_ty, "count descriptor requires result type"))
        end
        if vocab == Stencil.StencilMapReduce then
            return Stencil.StencilDescriptorMapReduce(dom, accesses, assert(operator, "map-reduce descriptor requires operator"), assert(reducer, "map-reduce descriptor requires reducer"), assert(result_ty, "map-reduce descriptor requires result type"))
        end
        if vocab == Stencil.StencilZipReduce then
            return Stencil.StencilDescriptorZipReduce(dom, accesses, assert(operator, "zip-reduce descriptor requires operator"), assert(reducer, "zip-reduce descriptor requires reducer"), assert(result_ty, "zip-reduce descriptor requires result type"))
        end
        error("stencil_artifact_plan: unsupported descriptor vocab", 3)
    end

    local function descriptor_vocab(desc)
        local cls = pvm.classof(desc)
        if cls == Stencil.StencilDescriptorReduce then return Stencil.StencilReduce end
        if cls == Stencil.StencilDescriptorMap then return Stencil.StencilMap end
        if cls == Stencil.StencilDescriptorZipMap then return Stencil.StencilZipMap end
        if cls == Stencil.StencilDescriptorScan then return Stencil.StencilScan end
        if cls == Stencil.StencilDescriptorCopy then return Stencil.StencilCopy end
        if cls == Stencil.StencilDescriptorFill then return Stencil.StencilFill end
        if cls == Stencil.StencilDescriptorFind then return Stencil.StencilFind end
        if cls == Stencil.StencilDescriptorPartition then return Stencil.StencilPartition end
        if cls == Stencil.StencilDescriptorCast then return Stencil.StencilCast end
        if cls == Stencil.StencilDescriptorCompare then return Stencil.StencilCompare end
        if cls == Stencil.StencilDescriptorZipCompare then return Stencil.StencilZipCompare end
        if cls == Stencil.StencilDescriptorSelect then return Stencil.StencilSelect end
        if cls == Stencil.StencilDescriptorGather then return Stencil.StencilGather end
        if cls == Stencil.StencilDescriptorScatter then return Stencil.StencilScatter end
        if cls == Stencil.StencilDescriptorInPlaceMap then return Stencil.StencilInPlaceMap end
        if cls == Stencil.StencilDescriptorCount then return Stencil.StencilCount end
        if cls == Stencil.StencilDescriptorMapReduce then return Stencil.StencilMapReduce end
        if cls == Stencil.StencilDescriptorZipReduce then return Stencil.StencilZipReduce end
        return nil
    end

    local function descriptor_accesses(desc)
        return desc and desc.accesses or {}
    end

    local function descriptor_domain(desc)
        return desc and desc.domain or nil
    end

    local function domain_supported(domain0)
        return pvm.classof(domain0) == Stencil.StencilDomainRange1D
            and (tonumber(domain0.step) or 0) > 0
            and domain0.order == Stencil.StencilDomainForward
    end

    local function domain_reject_reason(domain0)
        local cls = pvm.classof(domain0)
        if cls == Stencil.StencilDomainRange1D then
            if domain0.order ~= Stencil.StencilDomainForward then return "backward 1D domains are represented but not materialized by current stencil backends" end
            if (tonumber(domain0.step) or 0) <= 0 then return "1D stencil domain step must be a positive compile-time constant" end
            return nil
        end
        if cls == Stencil.StencilDomainRangeND then return "ND range domains are represented but not materialized by the current 1D stencil backends" end
        if cls == Stencil.StencilDomainWindowND then return "windowed stencil domains are represented but not materialized by the current 1D stencil backends" end
        if cls == Stencil.StencilDomainTiledND then return "tiled ND domains are represented but not materialized by the current 1D stencil backends" end
        return "unknown stencil domain kind"
    end

    local function unsupported_domain_reject(domain0)
        local reason = domain_reject_reason(domain0)
        if reason == nil then return nil end
        return Stencil.StencilRejectUnsupportedDomain(domain0, reason)
    end

    local function schedule_lane_count(schedule)
        if pvm.classof(schedule) ~= Stencil.StencilScheduleVector then return nil end
        local policy = schedule.lane_policy
        if pvm.classof(policy) == Stencil.StencilLaneFixed then return tonumber(policy.lanes) end
        return nil
    end

    local function realized_matches_request(schedule, realized)
        local scls = pvm.classof(schedule)
        local rcls = pvm.classof(realized)
        if scls == Stencil.StencilScheduleScalar then return rcls == Stencil.StencilRealizedScalar end
        if scls == Stencil.StencilScheduleAutoVector then return rcls == Stencil.StencilRealizedVector end
        if scls == Stencil.StencilScheduleUnrolled then
            return rcls == Stencil.StencilRealizedUnrolled and tonumber(realized.factor) == tonumber(schedule.factor)
        end
        if scls == Stencil.StencilScheduleVector then
            local lanes = schedule_lane_count(schedule)
            return rcls == Stencil.StencilRealizedVector
                and (lanes == nil or tonumber(realized.lanes) == lanes)
                and tonumber(realized.unroll) == tonumber(schedule.vector_unroll)
                and tonumber(realized.interleave) == tonumber(schedule.interleave)
        end
        return false
    end

    local function schedule_rejects_for_realized(schedule, realized)
        if realized == nil or realized_matches_request(schedule, realized) then return {} end
        return {
            Stencil.StencilScheduleRejectRequestedRealizedMismatch(
                schedule,
                realized,
                "requested stencil schedule did not match materialized schedule"
            ),
        }
    end

    local function compiler_matrix_rejects(schedule)
        if pvm.classof(schedule) ~= Stencil.StencilScheduleVector then return {} end
        local compiler = schedule.compiler
        local vector_compiler = schedule.vector_compiler
        local cc = compiler and compiler.compiler or nil
        local reason
        if vector_compiler == Stencil.StencilVectorCompilerGccAutovec and cc ~= Stencil.StencilCompilerGcc then
            reason = "gcc autovec vector compiler requires gcc"
        elseif vector_compiler == Stencil.StencilVectorCompilerHandwritten and cc == Stencil.StencilCompilerSystemC then
            reason = "handwritten C vector compiler requires a C compiler"
        elseif vector_compiler == Stencil.StencilVectorCompilerCopyPatchStencil and cc ~= Stencil.StencilCompilerGcc then
            reason = "copy-patch stencil vector compiler is currently built by gcc"
        end
        if reason == nil then return {} end
        return {
            Stencil.StencilScheduleRejectCompilerMatrix(
                compiler,
                vector_compiler,
                reason
            ),
        }
    end

    local function variant_name(value)
        if value == nil then return "nil" end
        if value.text ~= nil then return value.text end
        local cls = pvm.classof(value)
        local s = tostring(cls or value)
        return s:match("([%w_]+)%)$") or s:match("%.([%w_]+)$") or s
    end

    local function provider_key(provider)
        return variant_name(provider)
    end

    local function compiler_policy_key(policy)
        if policy == nil then return "compiler:nil" end
        local flags = {}
        for i, flag in ipairs(policy.flags or {}) do flags[i] = tostring(flag) end
        return table.concat({
            variant_name(policy.compiler),
            variant_name(policy.opt_level),
            variant_name(policy.machine),
            table.concat(flags, ","),
        }, "/")
    end

    local function schedule_key(schedule)
        local cls = pvm.classof(schedule)
        if cls == Stencil.StencilScheduleScalar then return "scalar:" .. compiler_policy_key(schedule.compiler) end
        if cls == Stencil.StencilScheduleAutoVector then return "autovector:" .. compiler_policy_key(schedule.compiler) end
        if cls == Stencil.StencilScheduleUnrolled then return "unrolled:" .. tostring(schedule.factor) .. ":" .. compiler_policy_key(schedule.compiler) end
        if cls == Stencil.StencilScheduleVector then
            return table.concat({
                "vector",
                variant_name(schedule.feature),
                variant_name(schedule.lane_policy),
                tostring(schedule_lane_count(schedule) or "target"),
                variant_name(schedule.required_alignment),
                variant_name(schedule.tail),
                variant_name(schedule.reduction),
                variant_name(schedule.vector_compiler),
                tostring(schedule.vector_unroll),
                tostring(schedule.interleave),
                compiler_policy_key(schedule.compiler),
            }, ":")
        end
        return "schedule:" .. variant_name(schedule)
    end

    local function artifact_fingerprint(instance0, provider, symbol, signature)
        local source = table.concat({
            "stencil-artifact-v1",
            stable_repr(instance0.descriptor),
            stable_repr(instance0.schedule),
            stable_repr(instance0.abi),
            provider_key(provider),
            symbol.text,
            signature,
        }, "\n")
        return Stencil.StencilArtifactFingerprint("stencil-artifact-v1:" .. stable_hash32(source))
    end

    local function append_realized_diagnostics(out, realized)
        if realized == nil then return end
        for _, evidence in ipairs(realized.evidence or {}) do
            local cls = pvm.classof(evidence)
            if cls == Stencil.StencilRealizedByConstruction then
                out[#out + 1] = Stencil.StencilArtifactDiagnostic(
                    Stencil.StencilArtifactDiagnosticNote,
                    "realized-schedule",
                    evidence.reason
                )
            elseif cls == Stencil.StencilRealizedCompilerRemark then
                out[#out + 1] = Stencil.StencilArtifactDiagnostic(
                    Stencil.StencilArtifactDiagnosticRemark,
                    "compiler",
                    evidence.remark
                )
            elseif cls == Stencil.StencilRealizedDisassembly then
                out[#out + 1] = Stencil.StencilArtifactDiagnostic(
                    Stencil.StencilArtifactDiagnosticRemark,
                    "disassembly",
                    evidence.classification
                )
            end
        end
    end

    local function artifact_with_realized(artifact, provider, realized, extra_rejects, extra_diagnostics)
        provider = provider or artifact.provider
        local rejects = {}
        local has_compiler_matrix_reject = false
        for _, reject in ipairs(artifact.schedule_rejects or {}) do
            rejects[#rejects + 1] = reject
            if pvm.classof(reject) == Stencil.StencilScheduleRejectCompilerMatrix then has_compiler_matrix_reject = true end
        end
        if not has_compiler_matrix_reject then
            for _, reject in ipairs(compiler_matrix_rejects(artifact.instance.schedule)) do rejects[#rejects + 1] = reject end
        end
        for _, reject in ipairs(schedule_rejects_for_realized(artifact.instance.schedule, realized)) do rejects[#rejects + 1] = reject end
        for _, reject in ipairs(extra_rejects or {}) do rejects[#rejects + 1] = reject end
        local diagnostics = {}
        for _, diagnostic in ipairs(artifact.diagnostics or {}) do diagnostics[#diagnostics + 1] = diagnostic end
        append_realized_diagnostics(diagnostics, realized)
        for _, diagnostic in ipairs(extra_diagnostics or {}) do diagnostics[#diagnostics + 1] = diagnostic end
        return Stencil.StencilArtifact(
            artifact.instance,
            provider,
            artifact.symbol,
            artifact.c_signature,
            artifact_fingerprint(artifact.instance, provider, artifact.symbol, artifact.c_signature),
            realized,
            diagnostics,
            rejects
        )
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

    local function access_info_fact(info, access)
        if info == nil then return nil end
        local facts = info.access_facts or info.vector_facts
        if type(facts) ~= "table" then return nil end
        return facts[access.name]
    end

    local function access_alignment_fact(info, access)
        local fact = access_info_fact(info, access)
        local alignment = fact and (fact.alignment or fact.align)
        if alignment == nil and info ~= nil then alignment = info.alignment or info.align end
        if type(alignment) == "number" and alignment > 0 then return Stencil.StencilAlignmentKnown(alignment) end
        if alignment ~= nil then return alignment end
        return Stencil.StencilAlignmentUnknown
    end

    local function access_ref(name)
        return Stencil.StencilAccessRef(name)
    end

    local function access_ref_name(ref)
        return ref and ref.name or nil
    end

    local function access_vector_fact(access, info)
        return Stencil.StencilAccessVectorFact(
            access_ref(access.name),
            access_alignment_fact(info, access),
            access.role == Stencil.StencilAccessRead or access.role == Stencil.StencilAccessIndex,
            topology_unit_stride(access.topology)
        )
    end

    local function is_memory_access(access)
        return pvm.classof(access.topology) ~= Stencil.StencilTopologyScalar
    end

    local function proof_origin(origin, fallback)
        if origin == Stencil.StencilProofCheckerDerived
            or origin == Stencil.StencilProofBoundaryContract
            or origin == Stencil.StencilProofAuthorAsserted then
            return origin
        end
        return fallback or Stencil.StencilProofAuthorAsserted
    end

    local function global_proof_origin(info, field, fallback)
        if info == nil then return fallback or Stencil.StencilProofAuthorAsserted end
        return proof_origin(info[field] or info.proof_origin, fallback)
    end

    local function alias_pair_fact(left, right, relation)
        return Stencil.StencilAccessAliasFact(access_ref(left), access_ref(right), relation)
    end

    local function append_alias_fact(out, pair, default_relation)
        if pair == nil then return end
        local left = pair.left or pair[1]
        local right = pair.right or pair[2]
        local relation = pair.relation or pair[3] or default_relation
        if left == nil or right == nil then error("stencil_artifact_plan: alias pair requires left and right accesses", 3) end
        out[#out + 1] = alias_pair_fact(left, right, relation or Stencil.StencilAliasUnknown)
    end

    local function alias_facts(desc, info)
        local out = {}
        if info ~= nil and info.noalias == true then
            local accesses = {}
            for _, access in ipairs(descriptor_accesses(desc)) do
                if is_memory_access(access) then accesses[#accesses + 1] = access end
            end
            for i = 1, #accesses do
                for j = i + 1, #accesses do
                    out[#out + 1] = alias_pair_fact(accesses[i].name, accesses[j].name, Stencil.StencilAliasNoAlias)
                end
            end
        end
        if info ~= nil then
            for _, pair in ipairs(info.noalias_pairs or {}) do append_alias_fact(out, pair, Stencil.StencilAliasNoAlias) end
            for _, pair in ipairs(info.mayalias_pairs or {}) do append_alias_fact(out, pair, Stencil.StencilAliasMayAlias) end
            for _, pair in ipairs(info.alias_pairs or {}) do append_alias_fact(out, pair, nil) end
        end
        return out
    end

    local function access_alignment_origin(info, access)
        local fact = access_info_fact(info, access)
        if fact ~= nil then
            local origin = fact.alignment_proof_origin or fact.proof_origin or fact.origin
            if origin ~= nil then return proof_origin(origin, Stencil.StencilProofAuthorAsserted) end
        end
        return global_proof_origin(info, "alignment_proof_origin", Stencil.StencilProofAuthorAsserted)
    end

    local function add_proof_obligation(out, kind, origin, proof)
        out[#out + 1] = Stencil.StencilProofObligation(kind, origin, proof)
    end

    local function vector_proof_obligations(desc, info, access_facts, aliases, trip_count, arithmetic)
        local out = {}
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end

        for _, fact in ipairs(access_facts) do
            local name = access_ref_name(fact.access)
            local access = access_by_name[name]
            if fact.unit_stride then
                add_proof_obligation(
                    out,
                    Stencil.StencilProofUnitStride(fact.access),
                    Stencil.StencilProofCheckerDerived,
                    nil
                )
            end
            if pvm.classof(fact.alignment) == Stencil.StencilAlignmentKnown then
                add_proof_obligation(
                    out,
                    Stencil.StencilProofAlignment(fact.access, fact.alignment),
                    access_alignment_origin(info, access or { name = name }),
                    nil
                )
            end
        end

        local alias_origin = global_proof_origin(info, "alias_proof_origin", Stencil.StencilProofAuthorAsserted)
        for _, fact in ipairs(aliases) do
            if fact.relation == Stencil.StencilAliasNoAlias then
                add_proof_obligation(
                    out,
                    Stencil.StencilProofNoAlias(fact.left, fact.right),
                    alias_origin,
                    nil
                )
            end
        end

        local trip_count_cls = pvm.classof(trip_count)
        if trip_count_cls == Stencil.StencilTripCountMultipleOf or trip_count_cls == Stencil.StencilTripCountExact then
            add_proof_obligation(
                out,
                Stencil.StencilProofTripCount(trip_count),
                global_proof_origin(info, "trip_count_proof_origin", Stencil.StencilProofAuthorAsserted),
                nil
            )
        end

        if arithmetic.reduction_reassociable and desc.reducer ~= nil then
            add_proof_obligation(
                out,
                Stencil.StencilProofReductionReassociable,
                Stencil.StencilProofCheckerDerived,
                nil
            )
        end

        return out
    end

    local function reduction_reassociable(reducer)
        if reducer == nil then return true end
        if reducer.float_mode == Code.CodeFloatStrict then return false end
        if reducer.float_mode ~= nil then return true end
        return true
    end

    local function trip_count_fact(info)
        if info == nil then return Stencil.StencilTripCountDynamic end
        local fact = info.trip_count or info.trip_count_fact
        local cls = pvm.classof(fact)
        if cls == Stencil.StencilTripCountUnknown
            or cls == Stencil.StencilTripCountDynamic
            or cls == Stencil.StencilTripCountExact
            or cls == Stencil.StencilTripCountMultipleOf then
            return fact
        end
        local exact = info.exact_trip_count or info.trip_count_exact
        if exact ~= nil then return Stencil.StencilTripCountExact(tonumber(exact)) end
        local multiple = info.trip_count_multiple_of or info.multiple_of
        if multiple ~= nil then return Stencil.StencilTripCountMultipleOf(tonumber(multiple)) end
        return Stencil.StencilTripCountDynamic
    end

    local function vectorization_facts(desc, info)
        local access_facts = {}
        for i, access in ipairs(descriptor_accesses(desc)) do access_facts[i] = access_vector_fact(access, info) end
        local reducer = desc.reducer
        local aliases = alias_facts(desc, info)
        local trip_count = trip_count_fact(info)
        local arithmetic = Stencil.StencilArithmeticVectorFact(
            reduction_reassociable(reducer),
            reducer and reducer.int_semantics or nil,
            reducer and reducer.float_mode or nil
        )
        return Stencil.StencilVectorizationFacts(
            access_facts,
            aliases,
            trip_count,
            arithmetic,
            vector_proof_obligations(desc, info, access_facts, aliases, trip_count, arithmetic)
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
            or vocab == Stencil.StencilSelect
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
                    tonumber(sched.unroll) or 1,
                    tonumber(sched.interleave) or 1,
                    policy,
                    vectorization_facts(desc, info)
                )
            end
        elseif Schedule ~= nil and (sched == Schedule.ScheduleScalarIndex or sched == Schedule.ScheduleScalarPointer or sched == Schedule.ScheduleClosedForm) then
            return Stencil.StencilScheduleScalar(policy)
        end
        local unroll = unroll_factor(info)
        local vocab = descriptor_vocab(desc)
        if unroll > 1 and auto_vector_vocab(vocab) then return Stencil.StencilScheduleUnrolled(unroll, policy, vectorization_facts(desc, info)) end
        if auto_vector_vocab(vocab) then return Stencil.StencilScheduleAutoVector(policy, vectorization_facts(desc, info)) end
        return Stencil.StencilScheduleScalar(policy)
    end

    local function schedule_suffix(schedule)
        local cls = pvm.classof(schedule)
        if cls == Stencil.StencilScheduleVector then
            local lanes = schedule_lane_count(schedule)
            local lane_suffix = lanes and tostring(lanes) or "target"
            local unroll = tonumber(schedule.vector_unroll) or 1
            local interleave = tonumber(schedule.interleave) or 1
            return ":v" .. lane_suffix .. (unroll > 1 and (":vu" .. tostring(unroll)) or "") .. (interleave > 1 and (":i" .. tostring(interleave)) or ""),
                "_v" .. lane_suffix .. (unroll > 1 and ("_vu" .. tostring(unroll)) or "") .. (interleave > 1 and ("_i" .. tostring(interleave)) or "")
        end
        if cls == Stencil.StencilScheduleUnrolled then
            return ":u" .. tostring(schedule.factor), "_u" .. tostring(schedule.factor)
        end
        return "", ""
    end

    local function schedule_candidate_name(schedule)
        local cls = pvm.classof(schedule)
        if cls == Stencil.StencilScheduleScalar then return "scalar" end
        if cls == Stencil.StencilScheduleAutoVector then return "autovector" end
        if cls == Stencil.StencilScheduleUnrolled then return "unrolled:" .. tostring(schedule.factor) end
        if cls == Stencil.StencilScheduleVector then
            return "vector:" .. tostring(schedule_lane_count(schedule) or "target") .. ":u" .. tostring(schedule.vector_unroll or 1) .. ":i" .. tostring(schedule.interleave or 1)
        end
        return "schedule"
    end

    local function schedule_candidate_cost(schedule)
        local cls = pvm.classof(schedule)
        if cls == Stencil.StencilScheduleVector then
            local lanes = schedule_lane_count(schedule) or 4
            local unroll = tonumber(schedule.vector_unroll) or 1
            local interleave = tonumber(schedule.interleave) or 1
            return math.floor(100000 / math.max(1, lanes * unroll * interleave))
        end
        if cls == Stencil.StencilScheduleAutoVector then return 25000 end
        if cls == Stencil.StencilScheduleUnrolled then return math.floor(60000 / math.max(1, tonumber(schedule.factor) or 1)) end
        if cls == Stencil.StencilScheduleScalar then return 100000 end
        return 1000000
    end

    local function schedule_candidate(schedule, status, reason, rejects)
        return Stencil.StencilScheduleCandidate(
            schedule_candidate_name(schedule),
            schedule,
            schedule_candidate_cost(schedule),
            status,
            rejects or {},
            reason
        )
    end

    local function selection_provenance_for_artifact(artifact, reason)
        local schedule = artifact.instance.schedule
        local compiler = schedule.compiler or default_compiler_policy()
        local selected = schedule_candidate(
            schedule,
            Stencil.StencilScheduleCandidateSelected,
            reason or "selected stencil schedule has lowest estimated materialization cost among viable candidates",
            artifact.schedule_rejects or {}
        )
        local candidates = { selected }
        if pvm.classof(schedule) ~= Stencil.StencilScheduleScalar then
            candidates[#candidates + 1] = schedule_candidate(
                Stencil.StencilScheduleScalar(compiler),
                Stencil.StencilScheduleCandidateViable,
                "scalar fallback is viable but has higher estimated cost",
                {}
            )
        end
        return Stencil.StencilScheduleSelectionProvenance(
            Stencil.StencilScheduleSelectionHeuristic,
            selected.name,
            candidates,
            selected.reason
        )
    end

    local function no_selection_provenance(vocab, rejects, reason)
        local schedule_rejects = {}
        for _, reject in ipairs(rejects or {}) do
            if pvm.classof(reject) == Stencil.StencilRejectSchedule then schedule_rejects[#schedule_rejects + 1] = reject.reject end
        end
        local candidate = Stencil.StencilScheduleCandidate(
            "none:" .. tostring(vocab),
            nil,
            1000000,
            Stencil.StencilScheduleCandidateRejected,
            schedule_rejects,
            reason or "no stencil schedule candidate was selected"
        )
        return Stencil.StencilScheduleSelectionProvenance(
            Stencil.StencilScheduleSelectionFallback,
            "none",
            { candidate },
            candidate.reason
        )
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
        for _, access in ipairs(descriptor_accesses(desc)) do
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
        for _, access in ipairs(descriptor_accesses(desc)) do
            if pvm.classof(access.topology) ~= Stencil.StencilTopologyScalar then out[#out + 1] = access end
        end
        return out
    end

    local function param_decl_for_access(access, default)
        local field = field_topology(access.topology)
        if field == nil then return default end
        local name = default:match("%*%s*([_%a][_%w]*)") or access.name
        local is_const = default:match("%f[%w]const%f[%W]") ~= nil
        return c_type(field.record_ty) .. (is_const and " const *" or " *") .. name
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
        for _, access in ipairs(descriptor_accesses(desc)) do
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
        return Stencil.StencilArtifact(
            instance,
            Stencil.StencilProviderC,
            symbol,
            signature,
            artifact_fingerprint(instance, Stencil.StencilProviderC, symbol, signature),
            nil,
            {},
            compiler_matrix_rejects(instance.schedule)
        )
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
        local desc = descriptor(
            Stencil.StencilReduce,
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty)),
            },
            nil,
            reducer_desc(reduction, result_ty),
            nil,
            memory(),
            result_ty
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
            info
        )
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, { const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    function api.map_array_artifact(op, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_artifact_plan: unsupported map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:map_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_map_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilMap,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.src_topology or info.array_topology, stride),
            },
            element_unary_operator(op, result_ty, info),
            nil,
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop" }))
    end

    function api.zip_map_array_artifact(op, info)
        local lhs_ty, rhs_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) or not same_type(lhs_ty, result_ty) then error("stencil_artifact_plan: zip_map_array currently requires matching lhs/rhs/result types", 2) end
        if not binary_supported(op, result_ty) then error("stencil_artifact_plan: unsupported zip_map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_map_array:" .. type_name(lhs_ty) .. ":" .. binary_name(op) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_map_array_" .. type_name(lhs_ty) .. "_" .. binary_name(op) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilZipMap,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("lhs", Stencil.StencilAccessRead, lhs_ty, info.lhs_topology, stride),
                shaped("rhs", Stencil.StencilAccessRead, rhs_ty, info.rhs_topology, stride),
            },
            element_binary_operator(op, result_ty, info),
            nil,
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", const_elem_ptr_decl(lhs_ty, "lhs"), const_elem_ptr_decl(rhs_ty, "rhs"), "int32_t start", "int32_t stop" }))
    end

    function api.scan_array_artifact(reduction, plan, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        local mode = info.mode or Stencil.StencilScanInclusive
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = elem_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported scan_array artifact: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:scan_array:" .. type_name(elem_ty) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":" .. scan_mode_name(mode) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_scan_array_" .. type_name(elem_ty) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_" .. scan_mode_name(mode) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilScan,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty)),
            },
            nil,
            reducer_desc(reduction, result_ty),
            { mode = mode },
            memory(),
            result_ty
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty(), result_ty }, result_ty), proof_list(plan), info)
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, { c_type(result_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    function api.copy_array_artifact(info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local semantics = info.semantics or Stencil.StencilCopyNoOverlap
        local id = Stencil.StencilInstanceId("stencil:copy_array:" .. type_name(elem_ty) .. ":" .. copy_semantics_name(semantics) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_copy_array_" .. type_name(elem_ty) .. "_" .. copy_semantics_name(semantics) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilCopy,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_topology, stride),
                shaped("src", Stencil.StencilAccessRead, elem_ty, info.src_topology, stride),
            },
            Stencil.StencilOpIdentity,
            nil,
            { semantics = semantics },
            memory({ copy = semantics }),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "src"), "int32_t start", "int32_t stop" }))
    end

    function api.fill_array_artifact(info)
        local elem_ty, stride, value = assert(info.elem_ty), assert(info.step_num or info.stride or 1), assert(info.value)
        local id = Stencil.StencilInstanceId("stencil:fill_array:" .. type_name(elem_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_fill_array_" .. type_name(elem_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilFill,
            stride,
            { shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_topology, stride) },
            Stencil.StencilOpFill(value),
            nil,
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty(), elem_ty }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", "int32_t start", "int32_t stop", scalar_param_ty(elem_ty) .. " value" }))
    end

    function api.find_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:find_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_find_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_s" .. tostring(stride))        local not_found = Value.ValueExprConst(Code.CodeConstLiteral(i32_ty(), Core.LitInt("-1")))
        local desc = descriptor(
            Stencil.StencilFind,
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("index", Stencil.StencilAccessControlResult, i32_ty(), not_found),
            },
            Stencil.StencilOpPredicate(predicate_checked(pred, elem_ty), i32_ty()),
            nil,
            { not_found = not_found },
            memory(),
            i32_ty()
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, { const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop" }))
    end

    function api.partition_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local semantics = info.semantics or Stencil.StencilPartitionStable
        local id = Stencil.StencilInstanceId("stencil:partition_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":" .. partition_semantics_name(semantics) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_partition_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_" .. partition_semantics_name(semantics) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilPartition,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("split", Stencil.StencilAccessControlResult, i32_ty(), nil),
            },
            Stencil.StencilOpPredicate(predicate_checked(pred, elem_ty), i32_ty()),
            nil,
            { semantics = semantics },
            memory({ partition = semantics }),
            i32_ty()
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop" }))
    end

    function api.cast_array_artifact(op, info)
        local src_ty, dst_ty, stride = assert(info.src_ty), assert(info.dst_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:cast_array:" .. type_name(src_ty) .. ":" .. cast_name(op) .. ":to:" .. type_name(dst_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_cast_array_" .. type_name(src_ty) .. "_" .. cast_name(op) .. "_to_" .. type_name(dst_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilCast,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, dst_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, src_ty, info.src_topology or info.array_topology, stride),
            },
            Stencil.StencilOpCast(op, src_ty, dst_ty),
            nil,
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(dst_ty), Code.CodeTyDataPtr(src_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(dst_ty) .. " *dst", const_elem_ptr_decl(src_ty, "xs"), "int32_t start", "int32_t stop" }))
    end

    function api.compare_array_artifact(pred, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:compare_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_compare_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilCompare,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.src_topology or info.array_topology, stride),
            },
            Stencil.StencilOpPredicate(predicate_checked(pred, elem_ty), result_ty),
            nil,
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop" }))
    end

    function api.zip_compare_array_artifact(cmp, info)
        local lhs_ty, rhs_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) then error("stencil_artifact_plan: zip_compare_array currently requires matching lhs/rhs types", 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_compare_array:" .. type_name(lhs_ty) .. ":" .. cmp_name(cmp) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_compare_array_" .. type_name(lhs_ty) .. "_" .. cmp_name(cmp) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
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
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", const_elem_ptr_decl(lhs_ty, "lhs"), const_elem_ptr_decl(rhs_ty, "rhs"), "int32_t start", "int32_t stop" }))
    end

    function api.select_array_artifact(pred, info)
        local cond_ty = assert(info.cond_ty or info.mask_ty or info.pred_ty)
        local then_ty = assert(info.then_ty or info.elem_ty)
        local else_ty = assert(info.else_ty or info.elem_ty)
        local result_ty = assert(info.result_ty or info.elem_ty)
        local stride = assert(info.step_num or info.stride or 1)
        if not same_type(then_ty, else_ty) or not same_type(then_ty, result_ty) then error("stencil_artifact_plan: select_array requires matching then/else/result types", 2) end
        pred = predicate_checked(pred, cond_ty)
        local id = Stencil.StencilInstanceId("stencil:select_array:" .. type_name(cond_ty) .. ":" .. select_name(pred) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_select_array_" .. type_name(cond_ty) .. "_" .. select_name(pred) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilSelect,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_topology, stride),
                shaped("cond", Stencil.StencilAccessRead, cond_ty, info.cond_topology or info.mask_topology or info.pred_topology, stride),
                shaped("then_xs", Stencil.StencilAccessRead, then_ty, info.then_topology or info.true_topology, stride),
                shaped("else_xs", Stencil.StencilAccessRead, else_ty, info.else_topology or info.false_topology, stride),
            },
            Stencil.StencilOpSelect(pred, result_ty),
            nil,
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(cond_ty), Code.CodeTyDataPtr(then_ty), Code.CodeTyDataPtr(else_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(result_ty) .. " *dst", const_elem_ptr_decl(cond_ty, "cond"), const_elem_ptr_decl(then_ty, "then_xs"), const_elem_ptr_decl(else_ty, "else_xs"), "int32_t start", "int32_t stop" }))
    end

    function api.gather_array_artifact(info)
        local elem_ty, index_ty, stride = assert(info.elem_ty), assert(info.index_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:gather_array:" .. type_name(elem_ty) .. ":index:" .. type_name(index_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_gather_array_" .. type_name(elem_ty) .. "_idx_" .. type_name(index_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilGather,
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_topology, stride),
                indexed("src", Stencil.StencilAccessRead, elem_ty, index_ty, stride),
                shaped("idx", Stencil.StencilAccessIndex, index_ty, info.index_topology, stride),
            },
            Stencil.StencilOpIdentity,
            nil,
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(index_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "src"), const_elem_ptr_decl(index_ty, "idx"), "int32_t start", "int32_t stop" }))
    end

    function api.scatter_array_artifact(info)
        local elem_ty, index_ty, stride = assert(info.elem_ty), assert(info.index_ty), assert(info.step_num or info.stride or 1)
        local conflicts = info.conflicts or Stencil.StencilScatterUniqueIndices
        local id = Stencil.StencilInstanceId("stencil:scatter_array:" .. type_name(elem_ty) .. ":index:" .. type_name(index_ty) .. ":" .. scatter_conflict_name(conflicts) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_scatter_array_" .. type_name(elem_ty) .. "_idx_" .. type_name(index_ty) .. "_" .. scatter_conflict_name(conflicts) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilScatter,
            stride,
            {
                indexed("dst", Stencil.StencilAccessWrite, elem_ty, index_ty, stride),
                shaped("src", Stencil.StencilAccessRead, elem_ty, info.src_topology, stride),
                shaped("idx", Stencil.StencilAccessIndex, index_ty, info.index_topology, stride),
            },
            Stencil.StencilOpIdentity,
            nil,
            nil,
            memory({ scatter = conflicts }),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(index_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "src"), const_elem_ptr_decl(index_ty, "idx"), "int32_t start", "int32_t stop" }))
    end

    function api.in_place_map_array_artifact(op, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_artifact_plan: unsupported in_place_map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:in_place_map_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_in_place_map_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilInPlaceMap,
            stride,
            { Stencil.StencilAccess("xs", Stencil.StencilAccessReadWrite, elem_ty, info.src_topology or info.dst_topology or Stencil.StencilTopologyInPlace(stride)) },
            element_unary_operator(op, elem_ty, info),
            nil,
            nil,
            memory(),
            nil
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, { c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.count_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:count_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_count_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilCount,
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("count", Stencil.StencilAccessReduce, i32_ty(), nil),
            },
            Stencil.StencilOpPredicate(predicate_checked(pred, elem_ty), i32_ty()),
            nil,
            nil,
            memory(),
            i32_ty()
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty() }, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, { const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop" }))
    end

    function api.map_reduce_array_artifact(op, reduction, plan, info)
        local elem_ty, mapped_ty, result_ty, stride = assert(info.elem_ty), assert(info.mapped_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_artifact_plan: unsupported map_reduce_array op/type", 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = mapped_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported map_reduce_array reduction: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:map_reduce_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_map_reduce_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilMapReduce,
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_topology or info.src_topology, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty)),
            },
            element_unary_operator(op, mapped_ty, info),
            reducer_desc(reduction, result_ty),
            nil,
            memory(),
            result_ty
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(elem_ty), i32_ty(), i32_ty(), result_ty }, result_ty), proof_list(plan), info)
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, { const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    function api.zip_reduce_array_artifact(op, reduction, plan, info)
        local lhs_ty, rhs_ty, mapped_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.mapped_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) or not same_type(lhs_ty, mapped_ty) then error("stencil_artifact_plan: zip_reduce_array currently requires matching lhs/rhs/mapped types", 2) end
        if not binary_supported(op, mapped_ty) then error("stencil_artifact_plan: unsupported zip_reduce_array op/type", 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = mapped_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported zip_reduce_array reduction: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_reduce_array:" .. type_name(lhs_ty) .. ":" .. binary_name(op) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_reduce_array_" .. type_name(lhs_ty) .. "_" .. binary_name(op) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local desc = descriptor(
            Stencil.StencilZipReduce,
            stride,
            {
                shaped("lhs", Stencil.StencilAccessRead, lhs_ty, info.lhs_topology, stride),
                shaped("rhs", Stencil.StencilAccessRead, rhs_ty, info.rhs_topology, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty)),
            },
            element_binary_operator(op, mapped_ty, info),
            reducer_desc(reduction, result_ty),
            nil,
            memory(),
            result_ty
        )
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, { Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), i32_ty(), i32_ty(), result_ty }, result_ty), proof_list(plan), info)
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, { const_elem_ptr_decl(lhs_ty, "lhs"), const_elem_ptr_decl(rhs_ty, "rhs"), "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    local function access_named(desc, name)
        for _, a in ipairs(descriptor_accesses(desc)) do
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
        local dom = descriptor_domain(desc)
        if domain_supported(dom) then return tonumber(dom.step) or 1 end
        local reason = domain_reject_reason(dom)
        error("stencil_artifact_plan: unsupported stencil domain for artifact shape: " .. tostring(reason), 3)
    end

    local function indexed_ty(access)
        local top = access.topology
        if pvm.classof(top) ~= Stencil.StencilTopologyIndexed then
            error("stencil_artifact_plan: descriptor access is not indexed: " .. tostring(access.name), 3)
        end
        return top.index_ty
    end

    local function local_shape(kind, fields)
        fields.kind = kind
        return fields
    end

    local function artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local cls = pvm.classof(desc)
        if cls == Stencil.StencilDescriptorReduce then
            local xs = access_named(desc, "xs")
            local red = desc.reducer
            return local_shape("reduce_array", { elem_ty = xs.ty, result_ty = red.result_ty, reduction = red.reduction, int_semantics = red.int_semantics, float_mode = red.float_mode, identity = red.identity, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorMap then
            local dst, xs = access_named(desc, "dst"), access_named(desc, "xs")
            local op = desc.operator
            return local_shape("map_array", { elem_ty = xs.ty, result_ty = dst.ty, op = op.op, int_semantics = op.int_semantics, float_mode = op.float_mode, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorZipMap then
            local dst, lhs, rhs = access_named(desc, "dst"), access_named(desc, "lhs"), access_named(desc, "rhs")
            local op = desc.operator
            return local_shape("zip_map_array", { lhs_ty = lhs.ty, rhs_ty = rhs.ty, result_ty = dst.ty, op = op.op, int_semantics = op.int_semantics, float_mode = op.float_mode, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorScan then
            local dst, xs = access_named(desc, "dst"), access_named(desc, "xs")
            local red = desc.reducer
            return local_shape("scan_array", { elem_ty = xs.ty, result_ty = dst.ty, reduction = red.reduction, int_semantics = red.int_semantics, float_mode = red.float_mode, identity = red.identity, mode = desc.mode, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorCopy then
            local src = access_named(desc, "src")
            return local_shape("copy_array", { elem_ty = src.ty, semantics = desc.semantics, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorFill then
            local dst = access_named(desc, "dst")
            local op = desc.operator
            return local_shape("fill_array", { elem_ty = dst.ty, value = op.value, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorFind then
            local xs = access_named(desc, "xs")
            return local_shape("find_array", { elem_ty = xs.ty, pred = desc.pred, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorPartition then
            local xs = access_named(desc, "xs")
            return local_shape("partition_array", { elem_ty = xs.ty, pred = desc.pred, semantics = desc.semantics, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorCast then
            local xs = access_named(desc, "xs")
            local op = desc.operator
            return local_shape("cast_array", { src_ty = op.from, dst_ty = op.to, op = op.op, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorCompare then
            local xs = access_named(desc, "xs")
            return local_shape("compare_array", { elem_ty = xs.ty, result_ty = desc.result_ty, pred = desc.pred, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorZipCompare then
            local lhs, rhs = access_named(desc, "lhs"), access_named(desc, "rhs")
            return local_shape("zip_compare_array", { lhs_ty = lhs.ty, rhs_ty = rhs.ty, result_ty = desc.result_ty, cmp = desc.cmp, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorSelect then
            local cond = access_named(desc, "cond")
            local then_xs = access_named(desc, "then_xs")
            local else_xs = access_named(desc, "else_xs")
            return local_shape("select_array", { cond_ty = cond.ty, then_ty = then_xs.ty, else_ty = else_xs.ty, result_ty = desc.result_ty, pred = desc.pred, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorGather then
            local src = access_named(desc, "src")
            return local_shape("gather_array", { elem_ty = src.ty, index_ty = indexed_ty(src), stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorScatter then
            local dst = access_named(desc, "dst")
            return local_shape("scatter_array", { elem_ty = dst.ty, index_ty = indexed_ty(dst), conflicts = desc.conflicts, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorInPlaceMap then
            local xs = access_named(desc, "xs")
            local op = desc.operator
            return local_shape("in_place_map_array", { elem_ty = xs.ty, op = op.op, int_semantics = op.int_semantics, float_mode = op.float_mode, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorCount then
            local xs = access_named(desc, "xs")
            return local_shape("count_array", { elem_ty = xs.ty, pred = desc.pred, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorMapReduce then
            local xs = access_named(desc, "xs")
            local op = desc.operator
            local red = desc.reducer
            return local_shape("map_reduce_array", { elem_ty = xs.ty, mapped_ty = op.result_ty, result_ty = red.result_ty, op = op.op, op_int_semantics = op.int_semantics, op_float_mode = op.float_mode, reduction = red.reduction, int_semantics = red.int_semantics, float_mode = red.float_mode, identity = red.identity, stride = domain_stride(desc) })
        end
        if cls == Stencil.StencilDescriptorZipReduce then
            local lhs, rhs = access_named(desc, "lhs"), access_named(desc, "rhs")
            local op = desc.operator
            local red = desc.reducer
            return local_shape("zip_reduce_array", { lhs_ty = lhs.ty, rhs_ty = rhs.ty, mapped_ty = op.result_ty, result_ty = red.result_ty, op = op.op, op_int_semantics = op.int_semantics, op_float_mode = op.float_mode, reduction = red.reduction, int_semantics = red.int_semantics, float_mode = red.float_mode, identity = red.identity, stride = domain_stride(desc) })
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
    api.descriptor_vocab = descriptor_vocab
    api.descriptor_accesses = descriptor_accesses
    api.descriptor_domain = descriptor_domain
    api.domain_supported = domain_supported
    api.unsupported_domain_reject = unsupported_domain_reject
    api.schedule_lane_count = schedule_lane_count
    api.selection_provenance_for_artifact = selection_provenance_for_artifact
    api.no_selection_provenance = no_selection_provenance
    api.schedule_rejects_for_realized = schedule_rejects_for_realized
    api.artifact_with_realized = artifact_with_realized
    api.stride_param_name = stride_param_name
    api.dynamic_stride_accesses = dynamic_stride_accesses

    T._lalin_api_cache.stencil_artifact_plan = api
    return api
end

return bind_context
