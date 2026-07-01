local asdl = require("lalin.asdl")
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

local function stable_hash128(s)
    return table.concat({
        stable_hash32("lalin:0:" .. s),
        stable_hash32("lalin:1:" .. s),
        stable_hash32("lalin:2:" .. s),
        stable_hash32("lalin:3:" .. s),
    })
end

local function stable_repr(v, seen)
    local tv = type(v)
    if tv == "nil" then return "nil" end
    if tv == "boolean" or tv == "number" then return tostring(v) end
    if tv == "string" then return string.format("%q", v) end
    if tv ~= "table" then return tv .. ":" .. tostring(v) end
    local cls = asdl.classof(v)
    if tostring(cls) == "Class(LalinCode.CodeValueId)" then return tostring(cls) .. "{_}" end
    if tostring(cls):match("^Class%(LalinFlow%.FlowDomain") then return tostring(cls) .. "{_}" end
    if tostring(cls) == "Class(LalinGraph.GraphLoopId)" then return tostring(cls) .. "{_}" end
    if tostring(cls) == "Class(LalinCode.CodeFuncId)" then return tostring(cls) .. "{_}" end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local out = {}
    if cls then
        out[#out + 1] = tostring(cls)
        out[#out + 1] = "{"
        for i, field in ipairs(asdl.fields(cls) or {}) do
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
        local cls = asdl.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if ty == Code.CodeTyIndex then return "index" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        return sanitize(CodeType.code_type_key(ty))
    end

    local function c_type(ty)
        local cls = asdl.classof(ty)
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
        local cls = asdl.classof(pred)
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

    local function scatter_reduce_conflict_name(conflicts)
        if conflicts == Stencil.StencilScatterReduceSequential then return "seq" end
        if conflicts == Stencil.StencilScatterReduceUniqueIndices then return "unique" end
        if asdl.classof(conflicts) == Stencil.StencilScatterReduceAtomic then return "atomic" end
        if conflicts == Stencil.StencilScatterReducePrivatized then return "privatized" end
        return "scatter_reduce"
    end

    local function proof_list(plan)
        local eq = plan and plan.body and plan.body.equivalence or nil
        if asdl.classof(eq) == Kernel.KernelEquivalenceProof then return eq.proofs or {} end
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

    local function access_abi_ty(access)
        if asdl.classof(access.layout) == Stencil.StencilLayoutScalar then return access.ty end
        return Code.CodeTyDataPtr(access.ty)
    end

    local function access_arg_decl(access, mutable)
        if asdl.classof(access.layout) == Stencil.StencilLayoutScalar then return c_type(access.ty) .. " " .. access.name end
        if mutable then return c_type(access.ty) .. " *" .. access.name end
        return const_elem_ptr_decl(access.ty, access.name)
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
        return asdl.classof(ty) == Code.CodeTyInt
    end

    local function is_integer_like(ty)
        return asdl.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyIndex
    end

    local function is_float(ty)
        return asdl.classof(ty) == Code.CodeTyFloat
    end

    local function same_source_type(a, b)
        if a == b then return true end
        if a == nil or b == nil then return false end
        return tostring(a) == tostring(b)
    end

    local function same_type(a, b)
        if a == b then return true end
        local ac, bc = asdl.classof(a), asdl.classof(b)
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
        local cls = asdl.classof(ty)
        return cls == Code.CodeTyInt or cls == Code.CodeTyFloat or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function default_int_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
    end

    local function element_int_semantics(ty, info)
        local cls = asdl.classof(ty)
        if cls ~= Code.CodeTyInt and ty ~= Code.CodeTyIndex and ty ~= Code.CodeTyBool8 then return nil end
        return info and (info.int_semantics or info.semantics) or default_int_semantics()
    end

    local function element_float_mode(ty, info)
        if asdl.classof(ty) ~= Code.CodeTyFloat then return nil end
        return info and info.float_mode or Code.CodeFloatStrict
    end

    local function input_expr(name)
        return Stencil.StencilPointInput(Stencil.StencilAccessRef(name))
    end

    local function axis_ref(index)
        index = tonumber(index or 1) or 1
        return Stencil.StencilAxisRef(index)
    end

    local function domain_reduce_scope()
        return Stencil.StencilReduceScopeDomain
    end

    local function reduce_scope_from_attrs(attrs)
        attrs = attrs or {}
        return attrs.reduce_scope or attrs.scope or domain_reduce_scope()
    end

    local function scan_axis_from_attrs(attrs)
        attrs = attrs or {}
        return attrs.scan_axis or attrs.axis or axis_ref(1)
    end

    local function const_expr(value, ty)
        return Stencil.StencilPointConst(value, ty)
    end

    local function point_unary_expr(op, arg, result_ty, info)
        return Stencil.StencilPointUnary(op, arg, result_ty, element_int_semantics(result_ty, info), element_float_mode(result_ty, info))
    end

    local function point_binary_expr(op, left, right, result_ty, info)
        return Stencil.StencilPointBinary(op, left, right, result_ty, element_int_semantics(result_ty, info), element_float_mode(result_ty, info))
    end

    local function point_predicate_expr(pred, arg, result_ty)
        return Stencil.StencilPointPredicate(pred, arg, result_ty)
    end

    local function point_compare_expr(cmp, left, right, result_ty)
        return Stencil.StencilPointCompare(cmp, left, right, result_ty)
    end

    local function point_cast_expr(op, arg, from, to)
        return Stencil.StencilPointCast(op, arg, from, to)
    end

    local function point_select_expr(pred, cond, then_expr, else_expr, result_ty)
        return Stencil.StencilPointSelect(pred, cond, then_expr, else_expr, result_ty)
    end

    local function predicate_checked(pred, operand_ty)
        local cls = asdl.classof(pred)
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
        return asdl.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyBool8
    end

    local function supports_div_ty(ty)
        return asdl.classof(ty) == Code.CodeTyInt or asdl.classof(ty) == Code.CodeTyFloat or ty == Code.CodeTyIndex
    end

    local function supports_integer_arithmetic_ty(ty)
        return asdl.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyIndex
    end

    function api.reduce_array_supported(reduction, info)
        local elem_ty = info and info.elem_ty or nil
        local result_ty = info and info.result_ty or nil
        if elem_ty == nil or result_ty == nil then return false, "reduce_array stencil requires elem_ty and result_ty" end
        if not same_type(elem_ty, result_ty) then return false, "reduce_array stencil currently requires matching element/result types" end
        local ok_type, err = pcall(function() c_type(elem_ty); c_type(result_ty) end)
        if not ok_type then return false, tostring(err) end
        local op = reduction.op
        if is_integer_like(result_ty) then
            if op == Value.ReductionAdd or op == Value.ReductionMul
                or op == Value.ReductionAnd or op == Value.ReductionOr or op == Value.ReductionXor
                or op == Value.ReductionMin or op == Value.ReductionMax then
                return true
            end
            return false, "unsupported integer reduction"
        end
        if result_ty == Code.CodeTyBool8 then
            if op == Value.ReductionAnd or op == Value.ReductionOr or op == Value.ReductionXor then
                return true
            end
            return false, "bool8 reduce_array stencil only supports and/or/xor"
        end
        if is_float(result_ty) then
            if op == Value.ReductionAdd or op == Value.ReductionMul
                or op == Value.ReductionMin or op == Value.ReductionMax then
                return true
            end
            return false, "float reduce_array stencil only supports add/mul/min/max"
        end
        return false, "reduce_array stencil only supports integer, index, bool8, and float scalar types"
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

    local function range1d_producer(stride, origin)
        return Stencil.StencilProducer(
            origin,
            Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, tonumber(stride) or 1, Stencil.StencilProducerForward)
        )
    end

    local function canonical_axis(axis)
        return Stencil.StencilProducerAxis(axis.index_ty, nil, nil, axis.step, axis.order, axis.index_name)
    end

    local function canonical_producer(producer)
        local shape = producer and producer.shape or nil
        local cls = asdl.classof(shape)
        if cls == Stencil.StencilProduceRange1D then
            return Stencil.StencilProducer(
                nil,
                Stencil.StencilProduceRange1D(shape.index_ty, nil, nil, shape.step, shape.order)
            )
        end
        if cls == Stencil.StencilProduceRangeND then
            local axes = {}
            for i, axis in ipairs(shape.axes or {}) do axes[i] = canonical_axis(axis) end
            return Stencil.StencilProducer(nil, Stencil.StencilProduceRangeND(axes))
        end
        if cls == Stencil.StencilProduceWindowND then
            local axes = {}
            for i, axis in ipairs(shape.axes or {}) do axes[i] = canonical_axis(axis) end
            return Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND(axes, shape.windows or {}))
        end
        if cls == Stencil.StencilProduceTiledND then
            local axes = {}
            for i, axis in ipairs(shape.axes or {}) do axes[i] = canonical_axis(axis) end
            return Stencil.StencilProducer(nil, Stencil.StencilProduceTiledND(axes, shape.tile_sizes or {}))
        end
        return producer
    end

    local function producer_from_attrs(stride, attrs)
        attrs = attrs or {}
        return canonical_producer(attrs.producer or range1d_producer(stride, attrs.origin))
    end

    local function memory(opts)
        return opts or {}
    end

    local function attrs(info, extra)
        local out = {}
        for k, v in pairs(info or {}) do out[k] = v end
        for k, v in pairs(extra or {}) do out[k] = v end
        return out
    end

    local function contig(name, role, ty, stride)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilLayoutContiguous(tonumber(stride) or 1))
    end

    local function shaped(name, role, ty, layout, stride)
        return Stencil.StencilAccess(name, role, ty, layout or Stencil.StencilLayoutContiguous(1))
    end

    local function indexed(name, role, ty, index_ref, index_ty, stride)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilLayoutIndexed(
            Stencil.StencilLayoutContiguous(1),
            Stencil.StencilAccessRef(index_ref),
            index_ty,
            tonumber(stride) or 1
        ))
    end

    local function scalar(name, role, ty, value)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilLayoutScalar(value))
    end

    local function reducer_identity(reduction, result_ty)
        local identity, reason = ReductionAlgebra.identity_expr(reduction.op, result_ty)
        if identity == nil then error("stencil_artifact_plan: reduction has no identity: " .. tostring(reason), 3) end
        return identity
    end

    local function reducer_desc(reduction, result_ty)
        return Stencil.StencilReducer(reduction.op, result_ty, reducer_identity(reduction, result_ty), reduction.int_semantics, reduction.float_mode)
    end

    local function predicate_expr_pred(expr)
        local cls = asdl.classof(expr)
        if cls == Stencil.StencilPointPredicate or cls == Stencil.StencilPointSelect then return expr.pred end
        error("stencil_artifact_plan: descriptor mode requires a predicate point expression", 3)
    end

    local function descriptor(vocab, stride, accesses, expr, reducer, attrs, mem, result_ty)
        attrs = attrs or {}
        local producer = producer_from_attrs(stride, attrs)
        local body = Stencil.StencilBodyPoint(expr or input_expr("xs"))
        if vocab == "scatter_reduce" then
            body = Stencil.StencilBodyPoint(assert(expr, "scatter_reduce descriptor requires expr"))
            return Stencil.StencilDescriptor(
                producer,
                accesses,
                body,
                Stencil.StencilSinkScatterReduce(
                    Stencil.StencilAccessRef(attrs.store_dst or "dst"),
                    assert(reducer, "scatter_reduce descriptor requires reducer"),
                    attrs.scatter_reduce_conflicts or Stencil.StencilScatterReduceSequential,
                    assert(result_ty, "scatter_reduce descriptor requires result type")
                )
            )
        end
        if vocab == "reduce" then
            return Stencil.StencilDescriptor(producer, accesses, body, Stencil.StencilSinkReduce(assert(result_ty, "reduce descriptor requires result type"), reduce_scope_from_attrs(attrs), Stencil.StencilReduceFold(assert(reducer, "reduce descriptor requires reducer"))))
        end
        if vocab == "store" then
            body = Stencil.StencilBodyPoint(assert(expr, "store descriptor requires expr"))
            return Stencil.StencilDescriptor(producer, accesses, body, Stencil.StencilSinkStore(Stencil.StencilAccessRef(attrs.store_dst or "dst"), attrs.store_mode or Stencil.StencilStoreElementwise))
        end
        if vocab == "scan" then
            return Stencil.StencilDescriptor(producer, accesses, body, Stencil.StencilSinkScan(Stencil.StencilAccessRef("dst"), scan_axis_from_attrs(attrs), assert(reducer, "scan descriptor requires reducer"), assert(attrs.mode, "scan descriptor requires mode"), assert(result_ty, "scan descriptor requires result type")))
        end
        if vocab == "find" then
            expr = assert(expr, "find descriptor requires predicate expr")
            body = Stencil.StencilBodyPoint(expr)
            return Stencil.StencilDescriptor(producer, accesses, body, Stencil.StencilSinkReduce(assert(result_ty, "find descriptor requires result type"), reduce_scope_from_attrs(attrs), Stencil.StencilReduceFind(predicate_expr_pred(expr), assert(attrs.not_found, "find descriptor requires not_found"))))
        end
        if vocab == "partition" then
            body = Stencil.StencilBodyPoint(assert(expr, "partition descriptor requires predicate expr"))
            return Stencil.StencilDescriptor(producer, accesses, body, Stencil.StencilSinkStore(Stencil.StencilAccessRef("dst"), Stencil.StencilStorePartition(assert(attrs.semantics, "partition descriptor requires semantics"))))
        end
        if vocab == "count" then
            expr = assert(expr, "count descriptor requires predicate expr")
            body = Stencil.StencilBodyPoint(expr)
            return Stencil.StencilDescriptor(producer, accesses, body, Stencil.StencilSinkReduce(assert(result_ty, "count descriptor requires result type"), reduce_scope_from_attrs(attrs), Stencil.StencilReduceCount(predicate_expr_pred(expr))))
        end
        error("stencil_artifact_plan: unsupported descriptor vocab", 3)
    end

    local function descriptor_vocab(desc)
        local sink_cls = desc and desc.sink and asdl.classof(desc.sink) or nil
        if sink_cls == Stencil.StencilSinkStore then return Stencil.StencilStore end
        if sink_cls == Stencil.StencilSinkReduce then return Stencil.StencilReduce end
        if sink_cls == Stencil.StencilSinkScan then return Stencil.StencilScan end
        if sink_cls == Stencil.StencilSinkScatterReduce then return Stencil.StencilScatterReduce end
        return nil
    end

    local function descriptor_reduction_semantics(desc)
        if desc == nil or asdl.classof(desc.sink) ~= Stencil.StencilSinkReduce then return nil end
        return desc.sink.semantics
    end

    local function descriptor_reducer(desc)
        if desc == nil then return nil end
        local sink_cls = asdl.classof(desc.sink)
        if sink_cls == Stencil.StencilSinkScan then return desc.sink.reducer end
        if sink_cls == Stencil.StencilSinkScatterReduce then return desc.sink.reducer end
        if sink_cls == Stencil.StencilSinkReduce and asdl.classof(desc.sink.semantics) == Stencil.StencilReduceFold then return desc.sink.semantics.reducer end
        return nil
    end

    local function descriptor_expr(desc)
        if desc == nil or asdl.classof(desc.body) ~= Stencil.StencilBodyPoint then
            error("stencil_artifact_plan: descriptor body is not an apply expression", 3)
        end
        return desc.body.expr
    end

    local function descriptor_accesses(desc)
        return desc and desc.accesses or {}
    end

    local function descriptor_producer(desc)
        return desc and desc.producer or nil
    end

    local function descriptor_access_identity_map(desc)
        local map = {}
        local input_i, output_i = 0, 0
        for _, access in ipairs(descriptor_accesses(desc)) do
            local role = access.role
            if role == Stencil.StencilAccessWrite
                or role == Stencil.StencilAccessReadWrite
                or role == Stencil.StencilAccessReduce
                or role == Stencil.StencilAccessControlResult then
                output_i = output_i + 1
                map[access.name] = output_i == 1 and "dst" or ("dst" .. tostring(output_i))
            else
                input_i = input_i + 1
                map[access.name] = "x" .. tostring(input_i)
            end
        end
        return map
    end

    local function descriptor_identity_repr(desc)
        local access_map = descriptor_access_identity_map(desc)
        local function repr(v, seen, owner_cls, field_name)
            local tv = type(v)
            if tv == "nil" then return "nil" end
            if tv == "boolean" or tv == "number" then return tostring(v) end
            if tv == "string" then
                if owner_cls == Stencil.StencilAccess and field_name == "name" then
                    return string.format("%q", access_map[v] or v)
                end
                return string.format("%q", v)
            end
            if tv ~= "table" then return tv .. ":" .. tostring(v) end
            local cls = asdl.classof(v)
            if cls == Stencil.StencilAccessRef then
                return tostring(cls) .. "{name=" .. string.format("%q", access_map[v.name] or v.name) .. "}"
            end
            if tostring(cls) == "Class(LalinCode.CodeValueId)" then return tostring(cls) .. "{_}" end
            if tostring(cls):match("^Class%(LalinFlow%.FlowDomain") then return tostring(cls) .. "{_}" end
            if tostring(cls) == "Class(LalinGraph.GraphLoopId)" then return tostring(cls) .. "{_}" end
            if tostring(cls) == "Class(LalinCode.CodeFuncId)" then return tostring(cls) .. "{_}" end
            seen = seen or {}
            if seen[v] then return "<cycle>" end
            seen[v] = true
            local out = {}
            if cls then
                out[#out + 1] = tostring(cls)
                out[#out + 1] = "{"
                for i, field in ipairs(asdl.fields(cls) or {}) do
                    if i > 1 then out[#out + 1] = "," end
                    out[#out + 1] = field.name
                    out[#out + 1] = "="
                    out[#out + 1] = repr(rawget(v, field.name), seen, cls, field.name)
                end
                out[#out + 1] = "}"
            else
                local keys = {}
                for key in pairs(v) do keys[#keys + 1] = key end
                table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
                out[#out + 1] = "{"
                for i, key in ipairs(keys) do
                    if i > 1 then out[#out + 1] = "," end
                    out[#out + 1] = repr(key, seen)
                    out[#out + 1] = "="
                    out[#out + 1] = repr(v[key], seen)
                end
                out[#out + 1] = "}"
            end
            seen[v] = nil
            return table.concat(out)
        end
        return repr(desc)
    end

    local function producer_shape(producer)
        if producer == nil then return nil end
        if asdl.classof(producer) == Stencil.StencilProducer then return producer.shape end
        return producer
    end

    local function producer_axis_count(producer)
        local shape = producer_shape(producer)
        local cls = asdl.classof(shape)
        if cls == Stencil.StencilProduceRange1D then return 1 end
        if cls == Stencil.StencilProduceRangeND or cls == Stencil.StencilProduceWindowND or cls == Stencil.StencilProduceTiledND then return #(shape.axes or {}) end
        return 0
    end

    local function axis_ref_invalid_reason(axis, producer, site)
        site = site or "stencil axis"
        local idx = tonumber(axis and axis.index)
        if idx == nil or idx < 1 or math.floor(idx) ~= idx then return site .. " must be a positive integer axis index" end
        local rank = producer_axis_count(producer)
        if idx > rank then return site .. " " .. tostring(idx) .. " is outside producer rank " .. tostring(rank) end
        return nil
    end

    local function axis_set_invalid_reason(axes, producer, site)
        if #(axes or {}) == 0 then return (site or "axis set") .. " requires at least one axis" end
        local seen = {}
        for i, axis in ipairs(axes or {}) do
            local reason = axis_ref_invalid_reason(axis, producer, (site or "axis set") .. " axis " .. tostring(i))
            if reason ~= nil then return reason end
            if seen[axis.index] then return (site or "axis set") .. " repeats axis " .. tostring(axis.index) end
            seen[axis.index] = true
        end
        return nil
    end

    local function producer_axis_invalid_reason(axis, index)
        if axis == nil then return "producer axis " .. tostring(index) .. " is missing" end
        if (tonumber(axis.step) or 0) <= 0 then return "producer axis " .. tostring(index) .. " step must be a positive compile-time constant" end
        return nil
    end

    local function producer_window_invalid_reason(window, index)
        if window == nil then return "producer window " .. tostring(index) .. " is missing" end
        if (tonumber(window.before) or -1) < 0 then return "producer window " .. tostring(index) .. " before extent must be nonnegative" end
        if (tonumber(window.after) or -1) < 0 then return "producer window " .. tostring(index) .. " after extent must be nonnegative" end
        return nil
    end

    local function producer_shape_reject_reason(producer)
        local shape = producer_shape(producer)
        local cls = asdl.classof(shape)
        if cls == Stencil.StencilProduceRange1D then
            if (tonumber(shape.step) or 0) <= 0 then return "1D stencil producer step must be a positive compile-time constant" end
            return nil
        end
        if cls == Stencil.StencilProduceRangeND or cls == Stencil.StencilProduceWindowND or cls == Stencil.StencilProduceTiledND then
            if #(shape.axes or {}) == 0 then return "ND stencil producer requires at least one axis" end
            for i, axis in ipairs(shape.axes or {}) do
                local reason = producer_axis_invalid_reason(axis, i)
                if reason ~= nil then return reason end
            end
            if cls == Stencil.StencilProduceWindowND and #(shape.windows or {}) ~= #(shape.axes or {}) then
                return "windowed stencil producer requires one window per axis"
            end
            if cls == Stencil.StencilProduceWindowND then
                for i, window in ipairs(shape.windows or {}) do
                    local reason = producer_window_invalid_reason(window, i)
                    if reason ~= nil then return reason end
                end
            end
            if cls == Stencil.StencilProduceTiledND then
                if #(shape.tile_sizes or {}) ~= #(shape.axes or {}) then return "tiled stencil producer requires one tile size per axis" end
                for i, tile in ipairs(shape.tile_sizes or {}) do
                    if (tonumber(tile) or 0) <= 0 then return "tiled stencil producer tile size " .. tostring(i) .. " must be positive" end
                end
            end
            return nil
        end
        return "unknown stencil producer kind"
    end

    local function producer_shape_supported(producer)
        return producer_shape_reject_reason(producer) == nil
    end

    local function producer_axes_forward(axes)
        for _, axis in ipairs(axes or {}) do
            if axis.order ~= Stencil.StencilProducerForward then return false end
        end
        return true
    end

    local function producer_materialized(producer)
        local shape = producer_shape(producer)
        if not producer_shape_supported(producer) then return false end
        local cls = asdl.classof(shape)
        if cls == Stencil.StencilProduceRange1D then return true end
        if cls == Stencil.StencilProduceRangeND or cls == Stencil.StencilProduceWindowND or cls == Stencil.StencilProduceTiledND then
            return producer_axes_forward(shape.axes)
        end
        return false
    end

    local function producer_materializer_reject_reason(producer)
        local shape = producer_shape(producer)
        local shape_reason = producer_shape_reject_reason(producer)
        if shape_reason ~= nil then return shape_reason end
        local cls = asdl.classof(shape)
        if cls == Stencil.StencilProduceRange1D then
            return nil
        end
        if cls == Stencil.StencilProduceRangeND then
            if not producer_axes_forward(shape.axes) then return "backward ND range axes are represented but not materialized yet" end
            return nil
        end
        if cls == Stencil.StencilProduceWindowND then
            if not producer_axes_forward(shape.axes) then return "backward windowed ND axes are represented but not materialized yet" end
            return nil
        end
        if cls == Stencil.StencilProduceTiledND then
            if not producer_axes_forward(shape.axes) then return "backward tiled ND axes are represented but not materialized yet" end
            return nil
        end
        return "unknown stencil producer kind"
    end

    local function unsupported_producer_reject(producer)
        local reason = producer_materializer_reject_reason(producer)
        if reason == nil then return nil end
        return Stencil.StencilRejectUnsupportedProducer(producer, reason)
    end

    local function expr_window_input_reason(expr, producer)
        local cls = asdl.classof(expr)
        if cls == Stencil.StencilPointWindowInput then
            local shape = producer_shape(producer)
            if asdl.classof(shape) ~= Stencil.StencilProduceWindowND then return "window-relative point input requires a WindowND producer" end
            local seen = {}
            for i, offset in ipairs(expr.offsets or {}) do
                local reason = axis_ref_invalid_reason(offset.axis, producer, "window input offset " .. tostring(i))
                if reason ~= nil then return reason end
                if seen[offset.axis.index] then return "window input repeats axis " .. tostring(offset.axis.index) end
                seen[offset.axis.index] = true
            end
            return nil
        end
        if cls == Stencil.StencilPointUnary or cls == Stencil.StencilPointCast or cls == Stencil.StencilPointPredicate then
            return expr_window_input_reason(expr.arg, producer)
        end
        if cls == Stencil.StencilPointBinary or cls == Stencil.StencilPointCompare then
            return expr_window_input_reason(expr.left, producer) or expr_window_input_reason(expr.right, producer)
        end
        if cls == Stencil.StencilPointSelect then
            return expr_window_input_reason(expr.cond, producer) or expr_window_input_reason(expr.then_expr, producer) or expr_window_input_reason(expr.else_expr, producer)
        end
        return nil
    end

    local function reduce_scope_materializer_reject_reason(scope, producer)
        local cls = asdl.classof(scope)
        if scope == Stencil.StencilReduceScopeDomain or cls == Stencil.StencilReduceScopeDomain then return nil end
        if cls == Stencil.StencilReduceScopeAxes then
            local reason = axis_set_invalid_reason(scope.axes, producer, "reduce axis scope")
            if reason ~= nil then return reason end
            return nil
        end
        if cls == Stencil.StencilReduceScopeWindow then
            local shape = producer_shape(producer)
            if asdl.classof(shape) ~= Stencil.StencilProduceWindowND then return "window-local reduction requires a WindowND producer" end
            local reason = axis_set_invalid_reason(scope.axes, producer, "window reduction scope")
            if reason ~= nil then return reason end
            return nil
        end
        return "unknown reduce sink scope"
    end

    local function sink_materializer_reject_reason(desc)
        if desc == nil or desc.sink == nil then return "missing stencil sink" end
        local producer = descriptor_producer(desc)
        local body_reason = expr_window_input_reason(descriptor_expr(desc), producer)
        if body_reason ~= nil then return body_reason end
        local sink = desc.sink
        local sink_cls = asdl.classof(sink)
        if sink_cls == Stencil.StencilSinkReduce then
            return reduce_scope_materializer_reject_reason(sink.scope, producer)
        end
        if sink_cls == Stencil.StencilSinkScan then
            local reason = axis_ref_invalid_reason(sink.axis, producer, "scan axis")
            if reason ~= nil then return reason end
            return nil
        end
        if sink_cls == Stencil.StencilSinkStore then return nil end
        if sink_cls == Stencil.StencilSinkScatterReduce then
            if sink.conflicts == Stencil.StencilScatterReduceSequential or sink.conflicts == Stencil.StencilScatterReduceUniqueIndices then return nil end
            if asdl.classof(sink.conflicts) == Stencil.StencilScatterReduceAtomic then return "atomic scatter-reduce is represented but not materialized yet" end
            if sink.conflicts == Stencil.StencilScatterReducePrivatized then return "privatized scatter-reduce is represented but not materialized yet" end
            return "unknown scatter-reduce conflict semantics"
        end
        return "unknown stencil sink"
    end

    local function unsupported_sink_reject(desc)
        local reason = sink_materializer_reject_reason(desc)
        if reason == nil then return nil end
        return Stencil.StencilRejectUnsupportedSink(desc.sink, reason)
    end

    local function schedule_lane_count(schedule)
        if asdl.classof(schedule) ~= Stencil.StencilScheduleVector then return nil end
        local policy = schedule.lane_policy
        if asdl.classof(policy) == Stencil.StencilLaneFixed then return tonumber(policy.lanes) end
        return nil
    end

    local function realized_matches_request(schedule, realized)
        local scls = asdl.classof(schedule)
        local rcls = asdl.classof(realized)
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
        if asdl.classof(schedule) ~= Stencil.StencilScheduleVector then return {} end
        local compiler = schedule.compiler
        local vector_compiler = schedule.vector_compiler
        local cc = compiler and compiler.compiler or nil
        local reason
        if vector_compiler == Stencil.StencilVectorCompilerGccAutovec and cc ~= Stencil.StencilCompilerGcc then
            reason = "gcc autovec vector compiler requires gcc"
        elseif vector_compiler == Stencil.StencilVectorCompilerHandwritten and cc == Stencil.StencilCompilerSystemC then
            reason = "handwritten C vector compiler requires a C compiler"
        elseif vector_compiler == Stencil.StencilVectorCompilerCompiledStencil and cc ~= Stencil.StencilCompilerGcc then
            reason = "copy+compile residual stencil vector compiler is currently built by gcc"
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
        if type(value) == "table" then
            local text = rawget(value, "text")
            if text ~= nil then return text end
        end
        local cls = asdl.classof(value)
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
        local cls = asdl.classof(schedule)
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
            descriptor_identity_repr(instance0.descriptor),
            stable_repr(instance0.schedule),
            stable_repr(instance0.abi),
            provider_key(provider),
            symbol.text,
            signature,
        }, "\n")
        return Stencil.StencilArtifactFingerprint("stencil-artifact-v1:" .. stable_hash128(source))
    end

    local function append_realized_diagnostics(out, realized)
        if realized == nil then return end
        for _, evidence in ipairs(realized.evidence or {}) do
            local cls = asdl.classof(evidence)
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
            if asdl.classof(reject) == Stencil.StencilScheduleRejectCompilerMatrix then has_compiler_matrix_reject = true end
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

    local function layout_unit_stride(layout)
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return layout_unit_stride(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent then return layout_unit_stride(layout.parent) end
        if cls == Stencil.StencilLayoutAffine1D then return math.abs(tonumber(layout.scale) or 0) == 1 and layout_unit_stride(layout.parent) end
        if cls == Stencil.StencilLayoutAffineND then return false end
        if cls == Stencil.StencilLayoutContiguous or cls == Stencil.StencilLayoutIndexed then return tonumber(layout.stride) == 1 end
        if cls == Stencil.StencilLayoutSliceDescriptor or cls == Stencil.StencilLayoutByteSpanDescriptor then return true end
        if cls == Stencil.StencilLayoutViewDescriptor then return layout.stride_const == 1 end
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
            layout_unit_stride(access.layout)
        )
    end

    local function is_memory_access(access)
        return asdl.classof(access.layout) ~= Stencil.StencilLayoutScalar
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
        local function descriptor_access_named(name)
            for _, access in ipairs(descriptor_accesses(desc)) do
                if access.name == name then return access end
            end
            return nil
        end

        for _, fact in ipairs(access_facts) do
            local name = access_ref_name(fact.access)
            local access = descriptor_access_named(name)
            if fact.unit_stride then
                add_proof_obligation(
                    out,
                    Stencil.StencilProofUnitStride(fact.access),
                    Stencil.StencilProofCheckerDerived,
                    nil
                )
            end
            if asdl.classof(fact.alignment) == Stencil.StencilAlignmentKnown then
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

        local trip_count_cls = asdl.classof(trip_count)
        if trip_count_cls == Stencil.StencilTripCountMultipleOf or trip_count_cls == Stencil.StencilTripCountExact then
            add_proof_obligation(
                out,
                Stencil.StencilProofTripCount(trip_count),
                global_proof_origin(info, "trip_count_proof_origin", Stencil.StencilProofAuthorAsserted),
                nil
            )
        end

        if arithmetic.reduction_reassociable and descriptor_reducer(desc) ~= nil then
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
        local cls = asdl.classof(fact)
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
        local reducer = descriptor_reducer(desc)
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

    local function auto_vector_descriptor(desc)
        local sink_cls = desc and desc.sink and asdl.classof(desc.sink) or nil
        if sink_cls == Stencil.StencilSinkScan then return true end
        if sink_cls == Stencil.StencilSinkScatterReduce then return false end
        if sink_cls == Stencil.StencilSinkStore then
            return asdl.classof(desc.sink.semantics) ~= Stencil.StencilStorePartition
        end
        if sink_cls == Stencil.StencilSinkReduce then
            return asdl.classof(desc.sink.semantics) ~= Stencil.StencilReduceFind
        end
        return false
    end

    local function unroll_factor(info)
        local n = tonumber(info and (info.unroll or info.unroll_factor) or 1) or 1
        n = math.floor(n)
        if n < 1 then return 1 end
        if n > 16 then return 16 end
        return n
    end

    local function schedule_vector_lanes(kind)
        if Schedule == nil or asdl.classof(kind) ~= Schedule.ScheduleVector then return nil end
        if asdl.classof(kind.lanes) ~= Schedule.LaneVector then return nil end
        return tonumber(kind.lanes.lanes)
    end

    local function schedule_for_descriptor_with_info(desc, info)
        local policy = default_compiler_policy()
        local sched = info and info.schedule or nil
        if Schedule ~= nil and asdl.classof(sched) == Schedule.ScheduleVector then
            local lanes = schedule_vector_lanes(sched)
            if lanes ~= nil and lanes > 1 then
                return Stencil.StencilScheduleVector(
                    Stencil.StencilVectorFeatureNative,
                    Stencil.StencilLaneFixed(lanes),
                    Stencil.StencilVectorUnaligned,
                    sched.tail == Schedule.TailMasked and Stencil.StencilVectorMaskTail or Stencil.StencilVectorScalarTail,
                    Stencil.StencilVectorReductionHorizontal,
                    Stencil.StencilVectorCompilerCompiledStencil,
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
        if unroll > 1 and auto_vector_descriptor(desc) then return Stencil.StencilScheduleUnrolled(unroll, policy, vectorization_facts(desc, info)) end
        if auto_vector_descriptor(desc) then return Stencil.StencilScheduleAutoVector(policy, vectorization_facts(desc, info)) end
        return Stencil.StencilScheduleScalar(policy)
    end

    local function schedule_suffix(schedule)
        local cls = asdl.classof(schedule)
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
        local cls = asdl.classof(schedule)
        if cls == Stencil.StencilScheduleScalar then return "scalar" end
        if cls == Stencil.StencilScheduleAutoVector then return "autovector" end
        if cls == Stencil.StencilScheduleUnrolled then return "unrolled:" .. tostring(schedule.factor) end
        if cls == Stencil.StencilScheduleVector then
            return "vector:" .. tostring(schedule_lane_count(schedule) or "target") .. ":u" .. tostring(schedule.vector_unroll or 1) .. ":i" .. tostring(schedule.interleave or 1)
        end
        return "schedule"
    end

    local function schedule_candidate_cost(schedule)
        local cls = asdl.classof(schedule)
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
        if asdl.classof(schedule) ~= Stencil.StencilScheduleScalar then
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
            if asdl.classof(reject) == Stencil.StencilRejectSchedule then schedule_rejects[#schedule_rejects + 1] = reject.reject end
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

    local function layout_has_dynamic_stride(layout)
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return layout_has_dynamic_stride(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent then return layout_has_dynamic_stride(layout.parent) end
        if cls == Stencil.StencilLayoutAffine1D then return layout_has_dynamic_stride(layout.parent) end
        if cls == Stencil.StencilLayoutAffineND then return layout_has_dynamic_stride(layout.parent) end
        if cls == Stencil.StencilLayoutIndexed then return layout_has_dynamic_stride(layout.parent) end
        return cls == Stencil.StencilLayoutViewDescriptor and layout.stride_const == nil
    end

    local function layout_has_affine_offset(layout)
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return layout_has_affine_offset(layout.parent) end
        if cls == Stencil.StencilLayoutSoAComponent then return layout_has_affine_offset(layout.parent) end
        if cls == Stencil.StencilLayoutIndexed then return layout_has_affine_offset(layout.parent) end
        if cls == Stencil.StencilLayoutAffine1D then return layout.offset ~= nil or layout_has_affine_offset(layout.parent) end
        if cls == Stencil.StencilLayoutAffineND then return layout.offset ~= nil or layout_has_affine_offset(layout.parent) end
        return false
    end

    local function dynamic_stride_accesses(desc)
        local out = {}
        for _, access in ipairs(descriptor_accesses(desc)) do
            if layout_has_dynamic_stride(access.layout) then
                out[#out + 1] = access
            end
        end
        return out
    end

    local function dynamic_affine_offset_accesses(desc)
        local out = {}
        for _, access in ipairs(descriptor_accesses(desc)) do
            if layout_has_affine_offset(access.layout) then
                out[#out + 1] = access
            end
        end
        return out
    end

    local function stride_param_name(access)
        return sanitize(access.name) .. "_stride"
    end

    local function affine_offset_param_name(access)
        return sanitize(access.name) .. "_affine_offset"
    end

    local abi_params_with_layouts

    local function abi_with_dynamic_strides(desc, params, result)
        local out = {}
        params = abi_params_with_layouts(desc, params)
        for i = 1, #(params or {}) do out[i] = params[i] end
        for _, _access in ipairs(dynamic_stride_accesses(desc)) do
            out[#out + 1] = i32_ty()
        end
        for _, _access in ipairs(dynamic_affine_offset_accesses(desc)) do
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
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            out[#out + 1] = "int32_t " .. affine_offset_param_name(access)
        end
        return out
    end

    local function field_layout(layout)
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return layout end
        if cls == Stencil.StencilLayoutAffine1D then return field_layout(layout.parent) end
        if cls == Stencil.StencilLayoutAffineND then return field_layout(layout.parent) end
        return nil
    end

    local function pointer_accesses(desc)
        local out = {}
        for _, access in ipairs(descriptor_accesses(desc)) do
            if asdl.classof(access.layout) ~= Stencil.StencilLayoutScalar then out[#out + 1] = access end
        end
        return out
    end

    local function param_decl_for_access(access, default)
        local field = field_layout(access.layout)
        if field == nil then return default end
        local name = default:match("%*%s*([_%a][_%w]*)") or access.name
        local is_const = default:match("%f[%w]const%f[%W]") ~= nil
        return c_type(field.record_ty) .. (is_const and " const *" or " *") .. name
    end

    local function abi_param_type_for_access(access, default_ty)
        local field = field_layout(access.layout)
        if field == nil then return default_ty end
        return Code.CodeTyDataPtr(field.record_ty)
    end

    abi_params_with_layouts = function(desc, params)
        local out = {}
        local accesses = pointer_accesses(desc)
        local access_i = 1
        for i = 1, #(params or {}) do
            local p = params[i]
            if asdl.classof(p) == Code.CodeTyDataPtr and accesses[access_i] ~= nil then
                out[i] = abi_param_type_for_access(accesses[access_i], p)
                access_i = access_i + 1
            else
                out[i] = p
            end
        end
        return out
    end

    local function layout_suffix_for(access, layout)
        local top = access.layout
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutViewDescriptor then
            return "_view_" .. (layout.stride_const ~= nil and ("s" .. tostring(layout.stride_const)) or "sdyn")
        end
        if cls == Stencil.StencilLayoutFieldProjection then
            return layout_suffix_for(access, layout.parent) .. "_field_" .. sanitize(layout.field_name) .. "_o" .. tostring(layout.field_offset or 0)
        end
        if cls == Stencil.StencilLayoutSoAComponent then
            return layout_suffix_for(access, layout.parent) .. "_soa_" .. sanitize(layout.field_name) .. "_c" .. tostring(layout.component_index or 0)
        end
        if cls == Stencil.StencilLayoutAffine1D then
            local scale = tonumber(layout.scale) or 1
            local scale_tag = scale < 0 and ("m" .. tostring(math.abs(scale))) or ("p" .. tostring(scale))
            local offset_tag = layout.offset ~= nil and "odyn" or "o0"
            return layout_suffix_for(access, layout.parent) .. "_aff1d_" .. scale_tag .. "_" .. offset_tag
        end
        if cls == Stencil.StencilLayoutAffineND then
            local parts = {}
            for _, term in ipairs(layout.terms or {}) do
                parts[#parts + 1] = "a" .. tostring(term.axis.index)
            end
            local offset_tag = layout.offset ~= nil and "odyn" or "o0"
            return layout_suffix_for(access, layout.parent) .. "_affnd_" .. table.concat(parts, "x") .. "_" .. offset_tag
        end
        if cls == Stencil.StencilLayoutSliceDescriptor then
            return "_slice"
        end
        if cls == Stencil.StencilLayoutByteSpanDescriptor then
            return "_bytespan"
        end
        return ""
    end

    local function layout_suffix(access, access_name)
        local suffix = layout_suffix_for(access, access.layout)
        if suffix == "" then return "" end
        return "_" .. sanitize(access_name or access.name) .. suffix
    end

    local function descriptor_symbol_suffix(desc)
        local out = {}
        local access_map = descriptor_access_identity_map(desc)
        for _, access in ipairs(descriptor_accesses(desc)) do
            local suffix = layout_suffix(access, access_map[access.name])
            if suffix ~= "" then out[#out + 1] = suffix end
        end
        if #out == 0 then return "" end
        return "_l" .. stable_hash128(table.concat(out, "|"))
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

    local producer_tag
    local append_producer_params
    local descriptor_abi_args

    function api.reduce_array_artifact(reduction, plan, info)
        local elem_ty = assert(info.elem_ty, "stencil_artifact_plan.reduce_array_artifact requires elem_ty")
        local result_ty = assert(info.result_ty, "stencil_artifact_plan.reduce_array_artifact requires result_ty")
        local stride = assert(info.step_num, "stencil_artifact_plan.reduce_array_artifact requires step_num")
        local supported, reason = api.reduce_array_supported(reduction, info)
        if not supported then error("stencil_artifact_plan: unsupported reduce_array artifact: " .. tostring(reason), 2) end
        local desc = descriptor(
            "reduce",
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty)),
            },
            nil,
            reducer_desc(reduction, result_ty),
            info,
            memory(),
            result_ty
        )
        local selected_schedule = schedule_for_descriptor_with_info(desc, info)
        local suffix, symbol_suffix = schedule_suffix(selected_schedule)
        local id = Stencil.StencilInstanceId(reduce_instance_id(elem_ty, result_ty, reduction.op, stride).text .. suffix)
        local symbol = Stencil.StencilSymbolId(reduce_symbol_id(elem_ty, result_ty, reduction.op, stride).text .. symbol_suffix)
        local abi, args = descriptor_abi_args(desc, { { ty = result_ty, decl = c_type(result_ty) .. " init" } })
        local inst = instance(
            id,
            desc,
            abi_with_dynamic_strides(desc, abi, result_ty),
            proof_list(plan),
            info
        )
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, args))
    end

    function api.scan_array_artifact(reduction, plan, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        local mode = info.mode or Stencil.StencilScanInclusive
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported scan_array producer: " .. tostring(producer_reason), 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = elem_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported scan_array artifact: " .. tostring(reason), 2) end
        local ptag = producer_tag(producer)
        local id = Stencil.StencilInstanceId("stencil:scan_array:" .. type_name(elem_ty) .. ":" .. reduction_name(reduction.op) .. ":to:" .. type_name(result_ty) .. ":" .. scan_mode_name(mode) .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_scan_array_" .. type_name(elem_ty) .. "_" .. reduction_name(reduction.op) .. "_to_" .. type_name(result_ty) .. "_" .. scan_mode_name(mode) .. "_" .. ptag)
        local desc = descriptor(
            "scan",
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_layout, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout or info.src_layout, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty)),
            },
            nil,
            reducer_desc(reduction, result_ty),
            { mode = mode, producer = producer, axis = info.axis or info.scan_axis },
            memory(),
            result_ty
        )
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported scan_array sink/body: " .. tostring(sink_reason), 2) end
        local abi = { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty) }
        local args = { c_type(result_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "xs") }
        append_producer_params(producer, abi, args)
        abi[#abi + 1] = result_ty
        args[#args + 1] = c_type(result_ty) .. " init"
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, result_ty), proof_list(plan), info)
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, args))
    end

    function api.find_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:find_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_find_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_s" .. tostring(stride))        local not_found = Value.ValueExprConst(Code.CodeConstLiteral(i32_ty(), Core.LitInt("-1")))
        local desc = descriptor(
            "find",
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout or info.src_layout, stride),
                scalar("index", Stencil.StencilAccessControlResult, i32_ty(), not_found),
            },
            point_predicate_expr(predicate_checked(pred, elem_ty), input_expr("xs"), i32_ty()),
            nil,
            attrs(info, { not_found = not_found }),
            memory(),
            i32_ty()
        )
        local abi, args = descriptor_abi_args(desc)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, args))
    end

    function api.partition_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local semantics = info.semantics or Stencil.StencilPartitionStable
        local id = Stencil.StencilInstanceId("stencil:partition_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":" .. partition_semantics_name(semantics) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_partition_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_" .. partition_semantics_name(semantics) .. "_s" .. tostring(stride))
        local desc = descriptor(
            "partition",
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_layout, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout or info.src_layout, stride),
                scalar("split", Stencil.StencilAccessControlResult, i32_ty(), nil),
            },
            point_predicate_expr(predicate_checked(pred, elem_ty), input_expr("xs"), i32_ty()),
            nil,
            attrs(info, { semantics = semantics }),
            memory({ partition = semantics }),
            i32_ty()
        )
        local abi, args = descriptor_abi_args(desc)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, args))
    end

    function api.scatter_reduce_n_artifact(reduction, plan, info)
        local result_ty = assert(info.result_ty or info.elem_ty, "stencil_artifact_plan.scatter_reduce_n_artifact requires result_ty")
        local item_ty = assert(info.item_ty or info.elem_ty or result_ty, "stencil_artifact_plan.scatter_reduce_n_artifact requires item_ty")
        local index_ty = assert(info.index_ty, "stencil_artifact_plan.scatter_reduce_n_artifact requires index_ty")
        local stride = assert(info.step_num or info.stride or 1)
        local inputs = assert(info.inputs, "stencil_artifact_plan.scatter_reduce_n_artifact requires inputs")
        local expr = info.expr or input_expr(inputs[1] and (inputs[1].name or "x1") or "xs")
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported scatter_reduce_n producer: " .. tostring(producer_reason), 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = item_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported scatter_reduce_n reduction: " .. tostring(reason), 2) end
        local dst_name = info.dst_name or "dst"
        local idx_name = info.index_name or "idx"
        local accesses = {
            shaped(dst_name, Stencil.StencilAccessReadWrite, result_ty, info.dst_layout or Stencil.StencilLayoutIndexed(Stencil.StencilLayoutContiguous(1), Stencil.StencilAccessRef(idx_name), index_ty, stride), stride),
        }
        for i, input in ipairs(inputs) do
            local name = input.name or ("x" .. tostring(i))
            accesses[#accesses + 1] = shaped(name, Stencil.StencilAccessRead, assert(input.ty, "scatter_reduce_n input requires ty"), input.layout, stride)
        end
        accesses[#accesses + 1] = shaped(idx_name, Stencil.StencilAccessIndex, index_ty, info.index_layout, stride)
        local tag = sanitize(info.tag or ("arity" .. tostring(#inputs)))
        local ptag = producer_tag(producer)
        local conflicts = info.conflicts or info.scatter_reduce_conflicts or Stencil.StencilScatterReduceSequential
        local conflict_tag = scatter_reduce_conflict_name(conflicts)
        local id = Stencil.StencilInstanceId("stencil:scatter_reduce_n:" .. type_name(item_ty) .. ":" .. reduction_name(reduction.op) .. ":to:" .. type_name(result_ty) .. ":" .. conflict_tag .. ":" .. tag .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_scatter_reduce_n_" .. type_name(item_ty) .. "_" .. reduction_name(reduction.op) .. "_to_" .. type_name(result_ty) .. "_" .. conflict_tag .. "_" .. tag .. "_" .. ptag)
        local reducer = reducer_desc(reduction, result_ty)
        local desc = descriptor("scatter_reduce", stride, accesses, expr, reducer, { producer = producer, store_dst = dst_name, scatter_reduce_conflicts = conflicts }, memory({ scatter_reduce = true, scatter_reduce_conflicts = conflicts }), result_ty)
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported scatter_reduce_n sink/body: " .. tostring(sink_reason), 2) end
        local abi, args = descriptor_abi_args(desc)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, nil), proof_list(plan), info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, args))
    end

    function api.count_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:count_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_count_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_s" .. tostring(stride))
        local desc = descriptor(
            "count",
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout or info.src_layout, stride),
                scalar("count", Stencil.StencilAccessReduce, i32_ty(), nil),
            },
            point_predicate_expr(predicate_checked(pred, elem_ty), input_expr("xs"), i32_ty()),
            nil,
            info,
            memory(),
            i32_ty()
        )
        local abi, args = descriptor_abi_args(desc)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, args))
    end

    local function producer_param_name(axis_index, suffix)
        return "axis" .. tostring(axis_index) .. "_" .. suffix
    end

    function producer_tag(producer)
        local shape = producer_shape(producer)
        local cls = asdl.classof(shape)
        if cls == Stencil.StencilProduceRange1D then
            return (shape.order == Stencil.StencilProducerBackward and "b" or "f") .. "s" .. tostring(shape.step)
        end
        local function nd_step_suffix(axes)
            local steps, non_unit = {}, false
            for i, axis in ipairs(axes or {}) do
                local step = tonumber(axis.step) or 1
                steps[i] = tostring(step)
                if step ~= 1 then non_unit = true end
            end
            return non_unit and ("_s" .. table.concat(steps, "x")) or ""
        end
        if cls == Stencil.StencilProduceRangeND then return "range_nd" .. tostring(#(shape.axes or {})) .. nd_step_suffix(shape.axes) end
        if cls == Stencil.StencilProduceWindowND then return "window_nd" .. tostring(#(shape.axes or {})) .. nd_step_suffix(shape.axes) end
        if cls == Stencil.StencilProduceTiledND then return "tiled_nd" .. tostring(#(shape.axes or {})) .. nd_step_suffix(shape.axes) end
        return "producer"
    end

    function append_producer_params(producer, abi, args)
        local shape = producer_shape(producer)
        local cls = asdl.classof(shape)
        if cls == Stencil.StencilProduceRange1D then
            abi[#abi + 1] = i32_ty()
            abi[#abi + 1] = i32_ty()
            args[#args + 1] = "int32_t start"
            args[#args + 1] = "int32_t stop"
            return
        end
        if cls == Stencil.StencilProduceRangeND or cls == Stencil.StencilProduceWindowND or cls == Stencil.StencilProduceTiledND then
            for axis_index = 1, #(shape.axes or {}) do
                abi[#abi + 1] = i32_ty()
                abi[#abi + 1] = i32_ty()
                args[#args + 1] = "int32_t " .. producer_param_name(axis_index, "start")
                args[#args + 1] = "int32_t " .. producer_param_name(axis_index, "stop")
            end
            return
        end
        local reason = producer_materializer_reject_reason(producer)
        error("stencil_artifact_plan: unsupported producer ABI: " .. tostring(reason), 3)
    end

    function descriptor_abi_args(desc, trailing)
        local abi, args = {}, {}
        for _, access in ipairs(descriptor_accesses(desc)) do
            if asdl.classof(access.layout) ~= Stencil.StencilLayoutScalar then
                local role = access.role
                if role == Stencil.StencilAccessRead or role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite or role == Stencil.StencilAccessIndex then
                    abi[#abi + 1] = access_abi_ty(access)
                    args[#args + 1] = access_arg_decl(access, role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite)
                end
            end
        end
        append_producer_params(desc.producer, abi, args)
        for _, item in ipairs(trailing or {}) do
            abi[#abi + 1] = item.ty
            args[#args + 1] = item.decl
        end
        return abi, args
    end

    local function store_n_inputs(info, stride, producer)
        local inputs = assert(info.inputs, "stencil_artifact_plan.store_n_artifact requires inputs")
        local accesses = { shaped("dst", Stencil.StencilAccessWrite, assert(info.result_ty), info.dst_layout, stride) }
        local abi = { Code.CodeTyDataPtr(info.result_ty) }
        local args = { c_type(info.result_ty) .. " *dst" }
        for i, input in ipairs(inputs) do
            local name = input.name or ("x" .. tostring(i))
            local ty = assert(input.ty, "stencil_artifact_plan.store_n input requires ty")
            local role = input.role or Stencil.StencilAccessRead
            accesses[#accesses + 1] = shaped(name, role, ty, input.layout, stride)
            local access = accesses[#accesses]
            abi[#abi + 1] = access_abi_ty(access)
            args[#args + 1] = access_arg_decl(access, role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite)
        end
        append_producer_params(producer, abi, args)
        return inputs, accesses, abi, args
    end

    function api.store_n_artifact(info)
        local result_ty, stride = assert(info.result_ty, "stencil_artifact_plan.store_n_artifact requires result_ty"), assert(info.step_num or info.stride or 1)
        local expr = assert(info.expr, "stencil_artifact_plan.store_n_artifact requires expr")
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported store_n producer: " .. tostring(producer_reason), 2) end
        local inputs, accesses, abi, args = store_n_inputs(info, stride, producer)
        local desc = descriptor("store", stride, accesses, expr, nil, attrs(info, { producer = producer }), memory(), nil)
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported store_n sink/body: " .. tostring(sink_reason), 2) end
        local tag = sanitize("d" .. stable_hash128(descriptor_identity_repr(desc)))
        local ptag = producer_tag(producer)
        local id = Stencil.StencilInstanceId("stencil:store_n:" .. type_name(result_ty) .. ":" .. tag .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_store_n_" .. type_name(result_ty) .. "_" .. tag .. "_" .. ptag)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, args))
    end

    function api.reduce_n_artifact(reduction, plan, info)
        local result_ty, item_ty, stride = assert(info.result_ty, "stencil_artifact_plan.reduce_n_artifact requires result_ty"), assert(info.item_ty or info.mapped_ty or info.result_ty, "stencil_artifact_plan.reduce_n_artifact requires item_ty"), assert(info.step_num or info.stride or 1)
        local expr = assert(info.expr, "stencil_artifact_plan.reduce_n_artifact requires expr")
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported reduce_n producer: " .. tostring(producer_reason), 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = item_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported reduce_n reduction: " .. tostring(reason), 2) end
        local inputs = assert(info.inputs, "stencil_artifact_plan.reduce_n_artifact requires inputs")
        local scope = info.scope or info.reduce_scope or domain_reduce_scope()
        local scope_cls = asdl.classof(scope)
        local scoped_output = not (scope == Stencil.StencilReduceScopeDomain or scope_cls == Stencil.StencilReduceScopeDomain)
        local accesses = {}
        local abi = {}
        local args = {}
        if scoped_output then
            local dst_name = assert(scope.dst and scope.dst.name, "stencil_artifact_plan.reduce_n scoped output requires scope dst")
            accesses[#accesses + 1] = shaped(dst_name, Stencil.StencilAccessWrite, result_ty, info.dst_layout, stride)
            local access = accesses[#accesses]
            abi[#abi + 1] = access_abi_ty(access)
            args[#args + 1] = access_arg_decl(access, true)
        end
        for i, input in ipairs(inputs) do
            local name = input.name or ("x" .. tostring(i))
            local ty = assert(input.ty, "stencil_artifact_plan.reduce_n input requires ty")
            local role = input.role or Stencil.StencilAccessRead
            accesses[#accesses + 1] = shaped(name, role, ty, input.layout, stride)
            local access = accesses[#accesses]
            abi[#abi + 1] = access_abi_ty(access)
            args[#args + 1] = access_arg_decl(access, role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite)
        end
        accesses[#accesses + 1] = scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty))
        append_producer_params(producer, abi, args)
        if not scoped_output then
            abi[#abi + 1] = result_ty
            args[#args + 1] = c_type(result_ty) .. " init"
        end
        local desc = descriptor("reduce", stride, accesses, expr, reducer_desc(reduction, result_ty), { producer = producer, reduce_scope = scope }, memory(), result_ty)
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported reduce_n sink/body: " .. tostring(sink_reason), 2) end
        local tag = sanitize((info.tag or ("arity" .. tostring(#inputs))) .. "_" .. stable_hash128(descriptor_identity_repr(desc)))
        local ptag = producer_tag(producer)
        local id = Stencil.StencilInstanceId("stencil:reduce_n:" .. type_name(item_ty) .. ":" .. reduction_name(reduction.op) .. ":to:" .. type_name(result_ty) .. ":" .. tag .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_reduce_n_" .. type_name(item_ty) .. "_" .. reduction_name(reduction.op) .. "_to_" .. type_name(result_ty) .. "_" .. tag .. "_" .. ptag)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, scoped_output and nil or result_ty), proof_list(plan), info)
        if scoped_output then return artifact(inst, symbol, void_desc_decl(symbol, desc, args)) end
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, args))
    end

    function api.scan_n_artifact(reduction, plan, info)
        local result_ty, item_ty, stride = assert(info.result_ty, "stencil_artifact_plan.scan_n_artifact requires result_ty"), assert(info.item_ty or info.mapped_ty or info.result_ty, "stencil_artifact_plan.scan_n_artifact requires item_ty"), assert(info.step_num or info.stride or 1)
        local expr = assert(info.expr, "stencil_artifact_plan.scan_n_artifact requires expr")
        local mode = info.mode or Stencil.StencilScanInclusive
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported scan_n producer: " .. tostring(producer_reason), 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = item_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported scan_n reduction: " .. tostring(reason), 2) end
        local inputs = assert(info.inputs, "stencil_artifact_plan.scan_n_artifact requires inputs")
        local accesses = { shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_layout, stride) }
        local abi = { Code.CodeTyDataPtr(result_ty) }
        local args = { c_type(result_ty) .. " *dst" }
        for i, input in ipairs(inputs) do
            local name = input.name or ("x" .. tostring(i))
            local ty = assert(input.ty, "stencil_artifact_plan.scan_n input requires ty")
            local role = input.role or Stencil.StencilAccessRead
            accesses[#accesses + 1] = shaped(name, role, ty, input.layout, stride)
            local access = accesses[#accesses]
            abi[#abi + 1] = access_abi_ty(access)
            args[#args + 1] = access_arg_decl(access, role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite)
        end
        accesses[#accesses + 1] = scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty))
        append_producer_params(producer, abi, args)
        abi[#abi + 1] = result_ty
        args[#args + 1] = c_type(result_ty) .. " init"
        local reducer = reducer_desc(reduction, result_ty)
        local desc = descriptor("scan", stride, accesses, expr, reducer, { mode = mode, producer = producer, axis = info.axis or info.scan_axis }, memory(), result_ty)
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported scan_n sink/body: " .. tostring(sink_reason), 2) end
        local tag = sanitize((info.tag or ("arity" .. tostring(#inputs))) .. "_" .. stable_hash128(descriptor_identity_repr(desc)))
        local ptag = producer_tag(producer)
        local id = Stencil.StencilInstanceId("stencil:scan_n:" .. type_name(item_ty) .. ":" .. reduction_name(reduction.op) .. ":to:" .. type_name(result_ty) .. ":" .. scan_mode_name(mode) .. ":" .. tag .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_scan_n_" .. type_name(item_ty) .. "_" .. reduction_name(reduction.op) .. "_to_" .. type_name(result_ty) .. "_" .. scan_mode_name(mode) .. "_" .. tag .. "_" .. ptag)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, nil), proof_list(plan), info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, args))
    end

    local function access_named(desc, name)
        for _, a in ipairs(descriptor_accesses(desc)) do
            if a.name == name then return a end
        end
        error("stencil_artifact_plan: descriptor missing access " .. tostring(name), 3)
    end

    local function layout_stride(access)
        local top = access.layout
        if top.stride ~= nil then return top.stride end
        return 1
    end

    local function producer_stride(desc)
        local producer = descriptor_producer(desc)
        local shape = producer_shape(producer)
        if asdl.classof(shape) == Stencil.StencilProduceRange1D and producer_materialized(producer) then return tonumber(shape.step) or 1 end
        local reason = producer_materializer_reject_reason(producer)
        error("stencil_artifact_plan: unsupported stencil producer for artifact shape: " .. tostring(reason), 3)
    end

    function Stencil.StencilProducerExecution:artifact_shape_stride()
        return nil
    end

    function Stencil.StencilProducerExecRange1D:artifact_shape_stride()
        return self.stride
    end

    function Stencil.StencilProducerShape:artifact_execution_plan()
        error("stencil_artifact_plan: unsupported producer execution plan", 3)
    end

    function Stencil.StencilProduceRange1D:artifact_execution_plan()
        return Stencil.StencilProducerExecRange1D(
            tonumber(self.step) or 1,
            self.order
        )
    end

    local function nd_execution_axes(axes)
        local out = {}
        for i, axis in ipairs(axes or {}) do
            out[#out + 1] = Stencil.StencilProducerExecutionAxis(
                axis.index_ty,
                tonumber(axis.step) or 1,
                producer_param_name(i, "start"),
                producer_param_name(i, "stop")
            )
        end
        return out
    end

    function Stencil.StencilProduceRangeND:artifact_execution_plan()
        local axes = nd_execution_axes(self.axes)
        return Stencil.StencilProducerExecRangeND(#axes, axes)
    end

    function Stencil.StencilProduceWindowND:artifact_execution_plan()
        local axes = nd_execution_axes(self.axes)
        return Stencil.StencilProducerExecWindowND(#axes, axes, self.windows)
    end

    function Stencil.StencilProduceTiledND:artifact_execution_plan()
        local axes = nd_execution_axes(self.axes)
        return Stencil.StencilProducerExecTiledND(#axes, axes, self.tile_sizes)
    end

    local function producer_execution_plan(desc)
        local producer = descriptor_producer(desc)
        local reason = producer_materializer_reject_reason(producer)
        if reason ~= nil then error("stencil_artifact_plan: unsupported stencil producer for artifact shape: " .. tostring(reason), 3) end
        local shape = producer_shape(producer)
        return shape:artifact_execution_plan()
    end

    local function indexed_ty(access)
        local top = access.layout
        if asdl.classof(top) ~= Stencil.StencilLayoutIndexed then
            error("stencil_artifact_plan: descriptor access is not indexed: " .. tostring(access.name), 3)
        end
        return top.index_ty
    end

    function Stencil.StencilReduceScope:artifact_reduce_execution_scope()
        error("stencil_artifact_plan: unsupported reduce execution scope", 3)
    end

    function Stencil.StencilReduceScopeDomain:artifact_reduce_execution_scope()
        return Stencil.StencilReduceExecDomain
    end

    function Stencil.StencilReduceExecDomain:artifact_reduce_init_mode()
        return Stencil.StencilReduceInitExternal
    end

    function Stencil.StencilReduceScopeAxes:artifact_reduce_execution_scope()
        return Stencil.StencilReduceExecAxes(self.dst.name, self.axes)
    end

    function Stencil.StencilReduceExecAxes:artifact_reduce_init_mode()
        return Stencil.StencilReduceInitIdentity
    end

    function Stencil.StencilReduceScopeWindow:artifact_reduce_execution_scope()
        return Stencil.StencilReduceExecWindow(self.dst.name, self.axes)
    end

    function Stencil.StencilReduceExecWindow:artifact_reduce_init_mode()
        return Stencil.StencilReduceInitIdentity
    end

    local function expr_input_name(expr)
        if asdl.classof(expr) == Stencil.StencilPointInput then return expr.access.name end
        return nil
    end

    local function expr_is_input(expr, name)
        return expr_input_name(expr) == name
    end

    local function collect_expr_inputs(expr, seen, out)
        seen = seen or {}
        out = out or {}
        local cls = asdl.classof(expr)
        if cls == Stencil.StencilPointInput or cls == Stencil.StencilPointWindowInput then
            local name = expr.access.name
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        elseif cls == Stencil.StencilPointUnary or cls == Stencil.StencilPointCast or cls == Stencil.StencilPointPredicate then
            collect_expr_inputs(expr.arg, seen, out)
        elseif cls == Stencil.StencilPointBinary or cls == Stencil.StencilPointCompare then
            collect_expr_inputs(expr.left, seen, out)
            collect_expr_inputs(expr.right, seen, out)
        elseif cls == Stencil.StencilPointSelect then
            collect_expr_inputs(expr.cond, seen, out)
            collect_expr_inputs(expr.then_expr, seen, out)
            collect_expr_inputs(expr.else_expr, seen, out)
        elseif cls == Stencil.StencilPointConst then
            return out
        else
            error("stencil_artifact_plan: unsupported apply expression", 3)
        end
        return out
    end

    local function collect_layout_inputs(layout, seen, out)
        local cls = asdl.classof(layout)
        if cls == Stencil.StencilLayoutIndexed then
            local name = layout.index.name
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
            collect_layout_inputs(layout.parent, seen, out)
        elseif cls == Stencil.StencilLayoutFieldProjection or cls == Stencil.StencilLayoutSoAComponent then
            collect_layout_inputs(layout.parent, seen, out)
        end
    end

    local function expr_inputs_for_shape(desc, expr)
        local seen, names = {}, {}
        collect_expr_inputs(expr, seen, names)
        for _, access in ipairs(descriptor_accesses(desc)) do
            collect_layout_inputs(access.layout, seen, names)
        end
        local out = {}
        for _, name in ipairs(names) do
            local access = access_named(desc, name)
            if access.role == Stencil.StencilAccessRead or access.role == Stencil.StencilAccessReadWrite or access.role == Stencil.StencilAccessIndex then
                out[#out + 1] = access
            end
        end
        return out
    end

    local function store_n_shape(desc, result_ty, dst_name, store_mode)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        return Stencil.StencilArtifactStoreN(inputs, result_ty, dst_name or "dst", store_mode, expr, producer, producer:artifact_shape_stride())
    end

    local function reduce_n_shape(desc, red, init_mode)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        local scope = desc.sink.scope
        local reduce_scope = scope:artifact_reduce_execution_scope()
        return Stencil.StencilArtifactReduceN(
            inputs,
            expr,
            desc.sink.result_ty,
            red.result_ty,
            red.reduction,
            red.int_semantics,
            red.float_mode,
            red.identity,
            scope,
            reduce_scope,
            init_mode or reduce_scope:artifact_reduce_init_mode(),
            producer,
            producer:artifact_shape_stride()
        )
    end

    local function count_reduce_shape(desc, mode)
        local red = Stencil.StencilReducer(
            Value.ReductionAdd,
            desc.sink.result_ty,
            reducer_identity({ op = Value.ReductionAdd }, desc.sink.result_ty),
            default_int_semantics(),
            nil
        )
        return reduce_n_shape(desc, red, Stencil.StencilReduceInitIdentity)
    end

    local function find_n_shape(desc, mode)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        return Stencil.StencilArtifactFindN(inputs, expr, desc.sink.result_ty, mode.pred, mode.not_found, producer, producer:artifact_shape_stride())
    end

    local function partition_n_shape(desc, sink)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        return Stencil.StencilArtifactPartitionN(inputs, expr, Code.CodeTyInt(32, Code.CodeSigned), sink.dst.name, sink.semantics, producer, producer:artifact_shape_stride())
    end

    local function scan_n_shape(desc, sink)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        local red = sink.reducer
        return Stencil.StencilArtifactScanN(
            inputs,
            expr,
            sink.result_ty,
            red.reduction,
            red.int_semantics,
            red.float_mode,
            red.identity,
            sink.mode,
            sink.axis,
            producer,
            producer:artifact_shape_stride()
        )
    end

    local function scatter_reduce_n_shape(desc, sink)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        local red = sink.reducer
        return Stencil.StencilArtifactScatterReduceN(
            inputs,
            expr,
            sink.result_ty,
            red.reduction,
            red.int_semantics,
            red.float_mode,
            red.identity,
            sink.dst.name,
            sink.conflicts,
            producer,
            producer:artifact_shape_stride()
        )
    end

    function Stencil.StencilArtifact:artifact_shape()
        return self.instance.descriptor:artifact_shape()
    end

    function Stencil.StencilDescriptor:artifact_shape()
        local sink_reason = sink_materializer_reject_reason(self)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported stencil sink: " .. tostring(sink_reason), 3) end
        return self.sink:artifact_shape_for_descriptor(self)
    end

    function Stencil.StencilSink:artifact_shape_for_descriptor(_desc)
        error("stencil_artifact_plan: unsupported stencil descriptor", 3)
    end

    function Stencil.StencilReductionSemantics:artifact_reduce_shape(_desc)
        error("stencil_artifact_plan: unsupported reduce sink semantics", 3)
    end

    function Stencil.StencilReduceFold:artifact_reduce_shape(desc)
        return reduce_n_shape(desc, self.reducer)
    end

    function Stencil.StencilReduceCount:artifact_reduce_shape(desc)
        return count_reduce_shape(desc, self)
    end

    function Stencil.StencilReduceFind:artifact_reduce_shape(desc)
        return find_n_shape(desc, self)
    end

    function Stencil.StencilSinkReduce:artifact_shape_for_descriptor(desc)
        return self.semantics:artifact_reduce_shape(desc)
    end

    function Stencil.StencilStoreSemantics:artifact_store_shape(desc, sink)
        return store_n_shape(desc, access_named(desc, sink.dst.name).ty, sink.dst.name, self)
    end

    function Stencil.StencilStorePartition:artifact_store_shape(desc, sink)
        return partition_n_shape(desc, sink)
    end

    function Stencil.StencilSinkStore:artifact_shape_for_descriptor(desc)
        return self.semantics:artifact_store_shape(desc, self)
    end

    function Stencil.StencilSinkScan:artifact_shape_for_descriptor(desc)
        return scan_n_shape(desc, self)
    end

    function Stencil.StencilSinkScatterReduce:artifact_shape_for_descriptor(desc)
        return scatter_reduce_n_shape(desc, self)
    end

    local function artifact_shape(artifact)
        return artifact:artifact_shape()
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
    api.input_expr = input_expr
    api.const_expr = const_expr
    api.point_unary_expr = point_unary_expr
    api.point_binary_expr = point_binary_expr
    api.point_predicate_expr = point_predicate_expr
    api.point_compare_expr = point_compare_expr
    api.point_cast_expr = point_cast_expr
    api.point_select_expr = point_select_expr
    api.descriptor_vocab = descriptor_vocab
    api.descriptor_accesses = descriptor_accesses
    api.descriptor_producer = descriptor_producer
    api.producer_shape = producer_shape
    api.producer_axis_count = producer_axis_count
    api.producer_shape_reject_reason = producer_shape_reject_reason
    api.producer_shape_supported = producer_shape_supported
    api.producer_materialized = producer_materialized
    api.producer_materializer_reject_reason = producer_materializer_reject_reason
    api.unsupported_producer_reject = unsupported_producer_reject
    api.sink_materializer_reject_reason = sink_materializer_reject_reason
    api.unsupported_sink_reject = unsupported_sink_reject
    api.axis_ref = axis_ref
    api.domain_reduce_scope = domain_reduce_scope
    api.schedule_lane_count = schedule_lane_count
    api.selection_provenance_for_artifact = selection_provenance_for_artifact
    api.no_selection_provenance = no_selection_provenance
    api.schedule_rejects_for_realized = schedule_rejects_for_realized
    api.artifact_with_realized = artifact_with_realized
    api.stride_param_name = stride_param_name
    api.dynamic_stride_accesses = dynamic_stride_accesses
    api.affine_offset_param_name = affine_offset_param_name
    api.dynamic_affine_offset_accesses = dynamic_affine_offset_accesses

    T._lalin_api_cache.stencil_artifact_plan = api
    return api
end

return bind_context
