local pvm = require("lalin.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.stencil_c ~= nil then return T._lalin_api_cache.stencil_c end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Kernel = T.LalinKernel
    local Stencil = T.LalinStencil
    local Schedule = T.LalinSchedule
    local CodeType = require("lalin.code_type")(T)
    local CEmit = require("lalin.c_emit")(T)
    local C = require("llbl.c")
    local LLBL = require("llbl")
    local _ = LLBL.spread
    local cn
    local source_params
    local descriptor_accesses

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
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyArray then return "ml_array_" .. tostring(ty.count) .. "_" .. sanitize(CodeType.code_type_key(ty.elem)) end
        if cls == Code.CodeTyClosure then return "ml_closure_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyVector then return "ml_vector_" .. tostring(ty.lanes) .. "_" .. sanitize(CodeType.code_type_key(ty.elem)) end
        if cls == Code.CodeTyImportedCFuncPtr then return "ml_cfuncptr_" .. sanitize(ty.sig.text) end
        return CEmit.emit_type(CodeType.code_type_to_c(ty, {}))
    end

    local function const_elem_ptr_decl(ty, name)
        return c_type(ty) .. " const *" .. name
    end

    local function access_ref_name(ref)
        return ref and ref.name or nil
    end

    local function access_vector_fact(artifact, name)
        local schedule = artifact.instance and artifact.instance.schedule
        local facts = schedule and schedule.facts and schedule.facts.access_facts or {}
        for _, fact in ipairs(facts or {}) do
            if access_ref_name(fact.access) == name then return fact end
        end
        return nil
    end

    local function alias_relation(artifact, left, right)
        if left == right then return Stencil.StencilAliasNoAlias end
        local schedule = artifact.instance and artifact.instance.schedule
        local facts = schedule and schedule.facts and schedule.facts.alias_facts or {}
        for _, fact in ipairs(facts or {}) do
            local a = access_ref_name(fact.left)
            local b = access_ref_name(fact.right)
            if (a == left and b == right) or (a == right and b == left) then return fact.relation end
        end
        return Stencil.StencilAliasUnknown
    end

    local function pointer_access_names(artifact)
        local out = {}
        local desc = artifact.instance and artifact.instance.descriptor
        for _, access in ipairs(descriptor_accesses(desc)) do
            if pvm.classof(access.topology) ~= Stencil.StencilTopologyScalar then out[#out + 1] = access.name end
        end
        return out
    end

    local function access_noalias(artifact, name)
        local saw = false
        for _, other in ipairs(pointer_access_names(artifact)) do
            if other == name then
                saw = true
            elseif alias_relation(artifact, name, other) ~= Stencil.StencilAliasNoAlias then
                return false
            end
        end
        return saw
    end

    local function access_alignment_bytes(artifact, name)
        local fact = access_vector_fact(artifact, name)
        if fact == nil then return nil end
        if pvm.classof(fact.alignment) == Stencil.StencilAlignmentKnown then return tonumber(fact.alignment.bytes) end
        return nil
    end

    local function assume_aligned_lines(artifact, names)
        local lines = {}
        for _, name in ipairs(names) do
            local bytes = access_alignment_bytes(artifact, name)
            if bytes ~= nil and bytes > 0 then
                lines[#lines + 1] = "    " .. name .. " = __builtin_assume_aligned(" .. name .. ", " .. tostring(bytes) .. ");"
            end
        end
        return lines
    end

    local function ptr_decl(ty, name, opts)
        opts = opts or {}
        local q = opts.const and " const" or ""
        local r = opts.restrict and " *__restrict " or " *"
        return c_type(ty) .. q .. r .. name
    end

    local function source_param_fragments(artifact, params)
        local raw = source_params(artifact, params)
        local out = {}
        for i = 1, #raw do out[i] = C.raw_param(raw[i]) end
        return out
    end

    local function emit_c_fn(artifact, result_ty, params, body)
        local name = LLBL.N[artifact.symbol.text]
        return C.emit_decl(C.fn[name] { _(source_param_fragments(artifact, params)) } [C.type[result_ty]] {
            _(body),
        })
    end

    local function emit_void_fn(artifact, params, body)
        local name = LLBL.N[artifact.symbol.text]
        return C.emit_decl(C.fn[name] { _(source_param_fragments(artifact, params)) } [C.void] {
            _(body),
        })
    end

    local function loop_i(stride, body)
        return C.for_ { C.decl. i[C.i32](cn("start")), C.lt(cn("i"), cn("stop")), C.assign(cn("i"), cn("i") + (tonumber(stride) or 1)) } {
            _(body),
        }
    end

    local function assume_aligned_stmts(artifact, names)
        local stmts = {}
        for _, name in ipairs(names) do
            local bytes = access_alignment_bytes(artifact, name)
            if bytes ~= nil and bytes > 0 then
                stmts[#stmts + 1] = C.assign(C.raw_expr(name), C.builtin.assume_aligned { C.raw_expr(name), C.raw_expr(tostring(bytes)) })
            end
        end
        return stmts
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

    local compare_expr

    local function all_c_expr(terms)
        if #terms == 0 then return "(1)" end
        local out = terms[1]
        for i = 2, #terms do out = "(" .. out .. " && " .. terms[i] .. ")" end
        return out
    end

    local function any_c_expr(terms)
        if #terms == 0 then return "(0)" end
        local out = terms[1]
        for i = 2, #terms do out = "(" .. out .. " || " .. terms[i] .. ")" end
        return out
    end

    local function predicate_expr(pred, item, ty)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return "(" .. item .. " != 0)" end
        if cls == Stencil.StencilPredCompareConst then
            local ct = c_type(pred.operand_ty)
            local lhs = "(" .. ct .. ")(" .. item .. ")"
            local rhs = "(" .. ct .. ")(" .. const_literal_source(pred.value, pred.operand_ty) .. ")"
            return compare_expr(pred.cmp, lhs, rhs)
        end
        if cls == Stencil.StencilPredRange then
            local ct = c_type(pred.operand_ty)
            local lhs = "(" .. ct .. ")(" .. item .. ")"
            return "("
                .. compare_expr(pred.lower_cmp, lhs, "(" .. ct .. ")(" .. const_literal_source(pred.lower, pred.operand_ty) .. ")")
                .. " && "
                .. compare_expr(pred.upper_cmp, lhs, "(" .. ct .. ")(" .. const_literal_source(pred.upper, pred.operand_ty) .. ")")
                .. ")"
        end
        if cls == Stencil.StencilPredAnd then
            local terms = {}
            for _, term in ipairs(pred.terms or {}) do terms[#terms + 1] = predicate_expr(term, item, ty) end
            return all_c_expr(terms)
        end
        if cls == Stencil.StencilPredOr then
            local terms = {}
            for _, term in ipairs(pred.terms or {}) do terms[#terms + 1] = predicate_expr(term, item, ty) end
            return any_c_expr(terms)
        end
        if cls == Stencil.StencilPredNot then return "(!" .. predicate_expr(pred.term, item, ty) .. ")" end
        if cls == Stencil.StencilPredIsNaN then return "isnan(" .. item .. ")" end
        if cls == Stencil.StencilPredIsInf then return "isinf(" .. item .. ")" end
        if cls == Stencil.StencilPredIsFinite then return "isfinite(" .. item .. ")" end
        error("stencil_c: unsupported predicate " .. pred_name(pred), 3)
    end

    compare_expr = function(cmp, lhs, rhs)
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

    local function int_wrap_semantics(sem)
        return sem ~= nil and sem.overflow == Code.CodeIntWrap
    end

    local function is_int_like(ty)
        local cls = pvm.classof(ty)
        return cls == Code.CodeTyInt or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function is_signed_int(ty)
        return pvm.classof(ty) == Code.CodeTyInt and ty.signedness == Code.CodeSigned
    end

    local function unary_expr(op, value, result_ty, int_semantics, float_mode)
        local ct = c_type(result_ty)
        if op == Stencil.StencilUnaryIdentity then return "(" .. ct .. ")(" .. value .. ")" end
        if op == Stencil.StencilUnaryNeg then
            if int_wrap_semantics(int_semantics) then
                local ut = unsigned_c_type(result_ty)
                return "(" .. ct .. ")((((" .. ut .. ")0) - (" .. ut .. ")(" .. value .. ")))"
            end
            return "(" .. ct .. ")(-(" .. value .. "))"
        end
        if op == Stencil.StencilUnaryBitNot then return "(" .. ct .. ")(~(" .. unsigned_c_type(result_ty) .. ")(" .. value .. "))" end
        if op == Stencil.StencilUnaryBoolNot then return "(" .. ct .. ")(!(" .. value .. "))" end
        error("stencil_c: unsupported unary op " .. unary_name(op), 3)
    end

    local function binary_expr(op, lhs, rhs, result_ty, int_semantics, float_mode)
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

    local ArtifactPlan = require("lalin.stencil_artifact_plan")(T)
    local artifact_shape = ArtifactPlan.artifact_shape
    source_params = ArtifactPlan.source_params
    descriptor_accesses = ArtifactPlan.descriptor_accesses
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

    function cn(name)
        return LLBL.N[tostring(name)]
    end

    local function c_type_node(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then
            if ty.bits == 8 then return ty.signedness == Code.CodeSigned and C.i8 or C.u8 end
            if ty.bits == 16 then return ty.signedness == Code.CodeSigned and C.i16 or C.u16 end
            if ty.bits == 32 then return ty.signedness == Code.CodeSigned and C.i32 or C.u32 end
            if ty.bits == 64 then return ty.signedness == Code.CodeSigned and C.i64 or C.u64 end
        end
        if cls == Code.CodeTyFloat then
            if ty.bits == 32 then return C.f32 end
            if ty.bits == 64 then return C.f64 end
        end
        if ty == Code.CodeTyIndex then return C.intptr_t end
        if ty == Code.CodeTyBool8 then return C.u8 end
        return C.type[c_type(ty)]
    end

    local function c_unsigned_type_node(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then
            if ty.bits == 8 then return C.u8 end
            if ty.bits == 16 then return C.u16 end
            if ty.bits == 32 then return C.u32 end
            if ty.bits == 64 then return C.u64 end
        end
        if ty == Code.CodeTyIndex then return C.uintptr_t end
        if ty == Code.CodeTyBool8 then return C.u8 end
        return c_type_node(ty)
    end

    local function access_offset_c_expr(access, index)
        local top = access.topology
        local cls = pvm.classof(top)
        if cls == Stencil.StencilTopologyFieldProjection then
            return access_offset_c_expr({ topology = top.parent }, index)
        end
        if cls == Stencil.StencilTopologySoAComponent then
            return access_offset_c_expr({ topology = top.parent, name = access.name }, index)
        end
        if cls == Stencil.StencilTopologyViewDescriptor then
            local stride = top.stride_const or cn(stride_param_name(access))
            if tonumber(stride) == 1 then return index end
            return index * stride
        end
        return index
    end

    local function access_c_expr(access, base, index)
        local base_expr = cn(base)
        local top = access.topology
        if pvm.classof(top) == Stencil.StencilTopologyFieldProjection then
            return base_expr[access_offset_c_expr({ topology = top.parent }, index)][sanitize(top.field_name)]
        end
        return base_expr[access_offset_c_expr(access, index)]
    end

    local function c_cast(ty, value)
        return C.cast[c_type_node(ty)](value)
    end

    local function c_unsigned_cast(ty, value)
        return C.cast[c_unsigned_type_node(ty)](value)
    end

    local function const_literal_value(expr)
        local cls = pvm.classof(expr)
        if cls ~= Value.ValueExprConst or pvm.classof(expr.const) ~= Code.CodeConstLiteral then
            error("stencil_c: select predicate const must be a literal ValueExprConst", 3)
        end
        local lit = expr.const.literal
        local lcls = pvm.classof(lit)
        if lcls == Core.LitInt or lcls == Core.LitFloat then return tonumber(lit.raw) end
        if lcls == Core.LitBool then return lit.value and 1 or 0 end
        error("stencil_c: unsupported select predicate literal", 3)
    end

    local function c_compare_expr(cmp, lhs, rhs)
        if cmp == Core.CmpEq then return C.eq(lhs, rhs) end
        if cmp == Core.CmpNe then return C.ne(lhs, rhs) end
        if cmp == Core.CmpLt then return C.lt(lhs, rhs) end
        if cmp == Core.CmpLe then return C.le(lhs, rhs) end
        if cmp == Core.CmpGt then return C.gt(lhs, rhs) end
        if cmp == Core.CmpGe then return C.ge(lhs, rhs) end
        error("stencil_c: unsupported compare op " .. cmp_name(cmp), 3)
    end

    local function all_c_node(terms)
        if #terms == 0 then return C.raw_expr("1") end
        local out = terms[1]
        for i = 2, #terms do out = C.land(out, terms[i]) end
        return out
    end

    local function any_c_node(terms)
        if #terms == 0 then return C.raw_expr("0") end
        local out = terms[1]
        for i = 2, #terms do out = C.lor(out, terms[i]) end
        return out
    end

    local function c_predicate_expr(pred, value)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return C.ne(value, 0) end
        if cls == Stencil.StencilPredCompareConst then
            return c_compare_expr(
                pred.cmp,
                c_cast(pred.operand_ty, value),
                c_cast(pred.operand_ty, const_literal_value(pred.value))
            )
        end
        if cls == Stencil.StencilPredRange then
            local lhs = c_cast(pred.operand_ty, value)
            return C.land(
                c_compare_expr(pred.lower_cmp, lhs, c_cast(pred.operand_ty, const_literal_value(pred.lower))),
                c_compare_expr(pred.upper_cmp, lhs, c_cast(pred.operand_ty, const_literal_value(pred.upper)))
            )
        end
        if cls == Stencil.StencilPredAnd then
            local terms = {}
            for _, term in ipairs(pred.terms or {}) do terms[#terms + 1] = c_predicate_expr(term, value) end
            return all_c_node(terms)
        end
        if cls == Stencil.StencilPredOr then
            local terms = {}
            for _, term in ipairs(pred.terms or {}) do terms[#terms + 1] = c_predicate_expr(term, value) end
            return any_c_node(terms)
        end
        if cls == Stencil.StencilPredNot then return C.not_(c_predicate_expr(pred.term, value)) end
        if cls == Stencil.StencilPredIsNaN then return C.builtin.isnan { value } end
        if cls == Stencil.StencilPredIsInf then return C.builtin.isinf { value } end
        if cls == Stencil.StencilPredIsFinite then return C.builtin.isfinite { value } end
        error("stencil_c: unsupported predicate " .. pred_name(pred), 3)
    end

    local function c_divrem_expr(op, lhs, rhs, result_ty)
        if not is_int_like(result_ty) then
            if op == Stencil.StencilBinaryDiv then return c_cast(result_ty, lhs / rhs) end
            error("stencil_c: modulo requires an integer result type", 3)
        end
        local a, b = cn("__ml_a"), cn("__ml_b")
        local body = {
            C.decl. __ml_a[c_type_node(result_ty)](c_cast(result_ty, lhs)),
            C.decl. __ml_b[c_type_node(result_ty)](c_cast(result_ty, rhs)),
            C.if_(C.eq(b, 0)) {
                C.expr(C.builtin.trap {}),
            },
        }
        if is_signed_int(result_ty) then
            local min_value = c_cast(result_ty, C.shl(C.cast[c_unsigned_type_node(result_ty)](1), (tonumber(result_ty.bits) or 32) - 1))
            body[#body + 1] = C.if_(C.land(C.eq(b, c_cast(result_ty, -1)), C.eq(a, min_value))) {
                C.expr(C.builtin.trap {}),
            }
        end
        body[#body + 1] = C.expr(c_cast(result_ty, op == Stencil.StencilBinaryDiv and (a / b) or (a % b)))
        return C.stmt_expr(body)
    end

    local function c_shift_expr(op, lhs, rhs, result_ty)
        if not is_int_like(result_ty) then error("stencil_c: shift requires an integer result type", 3) end
        local bits = pvm.classof(result_ty) == Code.CodeTyInt and tonumber(result_ty.bits) or 8
        local a, s, x, mask = cn("__ml_a"), cn("__ml_s"), cn("__ml_x"), cn("__ml_mask")
        local body = {
            C.decl. __ml_a[c_type_node(result_ty)](c_cast(result_ty, lhs)),
            C.decl. __ml_s[C.uint](C.band(C.cast[C.uint](rhs), bits - 1)),
        }
        if op == Stencil.StencilBinaryShl then
            body[#body + 1] = C.expr(c_cast(result_ty, C.shl(c_unsigned_cast(result_ty, a), s)))
            return C.stmt_expr(body)
        end
        if op == Stencil.StencilBinaryLShr or not is_signed_int(result_ty) then
            body[#body + 1] = C.expr(c_cast(result_ty, C.shr(c_unsigned_cast(result_ty, a), s)))
            return C.stmt_expr(body)
        end
        body[#body + 1] = C.decl. __ml_mask[c_unsigned_type_node(result_ty)](C.bnot(C.cast[c_unsigned_type_node(result_ty)](0)))
        body[#body + 1] = C.decl. __ml_x[c_unsigned_type_node(result_ty)](C.band(c_unsigned_cast(result_ty, a), mask))
        body[#body + 1] = C.if_(C.land(C.ne(s, 0), C.lt(a, 0))) {
            C.assign(x, C.bor(C.shr(x, s), C.shl(mask, bits - s))),
        } {
            C.assign(x, C.shr(x, s)),
        }
        body[#body + 1] = C.expr(c_cast(result_ty, C.band(x, mask)))
        return C.stmt_expr(body)
    end

    local function c_binary_expr(op, lhs, rhs, result_ty, int_semantics, float_mode)
        if op == Stencil.StencilBinaryAdd then return c_cast(result_ty, c_unsigned_cast(result_ty, lhs) + c_unsigned_cast(result_ty, rhs)) end
        if op == Stencil.StencilBinarySub then return c_cast(result_ty, c_unsigned_cast(result_ty, lhs) - c_unsigned_cast(result_ty, rhs)) end
        if op == Stencil.StencilBinaryMul then return c_cast(result_ty, c_unsigned_cast(result_ty, lhs) * c_unsigned_cast(result_ty, rhs)) end
        if op == Stencil.StencilBinaryDiv or op == Stencil.StencilBinaryMod then return c_divrem_expr(op, lhs, rhs, result_ty) end
        if op == Stencil.StencilBinaryAnd then return c_cast(result_ty, C.band(c_unsigned_cast(result_ty, lhs), c_unsigned_cast(result_ty, rhs))) end
        if op == Stencil.StencilBinaryOr then return c_cast(result_ty, C.bor(c_unsigned_cast(result_ty, lhs), c_unsigned_cast(result_ty, rhs))) end
        if op == Stencil.StencilBinaryXor then return c_cast(result_ty, C.bxor(c_unsigned_cast(result_ty, lhs), c_unsigned_cast(result_ty, rhs))) end
        if op == Stencil.StencilBinaryShl or op == Stencil.StencilBinaryLShr or op == Stencil.StencilBinaryAShr then return c_shift_expr(op, lhs, rhs, result_ty) end
        if op == Stencil.StencilBinaryMin then return C.select(C.lt(lhs, rhs), lhs, rhs) end
        if op == Stencil.StencilBinaryMax then return C.select(C.gt(lhs, rhs), lhs, rhs) end
        error("stencil_c: unsupported binary op " .. binary_name(op), 3)
    end

    local function c_reduction_update_expr(kind, acc, item, ty)
        if kind == Value.ReductionAdd then return c_cast(ty, c_unsigned_cast(ty, acc) + c_unsigned_cast(ty, item)) end
        if kind == Value.ReductionMul then return c_cast(ty, c_unsigned_cast(ty, acc) * c_unsigned_cast(ty, item)) end
        if kind == Value.ReductionAnd then return c_cast(ty, C.band(c_unsigned_cast(ty, acc), c_unsigned_cast(ty, item))) end
        if kind == Value.ReductionOr then return c_cast(ty, C.bor(c_unsigned_cast(ty, acc), c_unsigned_cast(ty, item))) end
        if kind == Value.ReductionXor then return c_cast(ty, C.bxor(c_unsigned_cast(ty, acc), c_unsigned_cast(ty, item))) end
        if kind == Value.ReductionMin then return C.select(C.lt(item, acc), item, acc) end
        if kind == Value.ReductionMax then return C.select(C.gt(item, acc), item, acc) end
        error("stencil_c: unsupported reduction " .. reduction_name(kind), 3)
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
        local lanes = math.max(2, math.floor(tonumber(ArtifactPlan.schedule_lane_count(schedule)) or 4))
        local unroll = math.max(1, math.floor(tonumber(schedule.vector_unroll) or 1))
        local vec_ty = "ml_vec_u32x" .. tostring(lanes)
        local vec_bytes = lanes * 4
        local lines = {}
        lines[#lines + 1] = ct .. " " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { const_elem_ptr_decl(shape.elem_ty, "xs"), "int32_t start", "int32_t stop", ct .. " init" }), ", ") .. ") {"
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
        lines[#lines + 1] = "    for (; i < stop; i++) acc = " .. reduction_update_expr(shape.reduction, "acc", access_ref(xs_access, "xs", "i"), shape.result_ty) .. ";"
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
        lines[#lines + 1] = ct .. " " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { const_elem_ptr_decl(elem_ty, "xs"), "int32_t start", "int32_t stop", ct .. " init" }), ", ") .. ") {"
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
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", const_elem_ptr_decl(shape.elem_ty, "xs"), "int32_t start", "int32_t stop" }), ", ") .. ") {"
        if shape.op == Stencil.StencilUnaryIdentity
            and stride == 1
            and et == rt
            and is_plain_linear_access(dst_access)
            and is_plain_linear_access(xs_access) then
            lines[#lines + 1] = "    if (stop > start) memmove(dst + start, xs + start, (size_t)(stop - start) * sizeof(dst[0]));"
        else
            lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
            lines[#lines + 1] = "        " .. access_ref(dst_access, "dst", "i") .. " = " .. unary_expr(shape.op, access_ref(xs_access, "xs", "i"), shape.result_ty, shape.int_semantics, shape.float_mode) .. ";"
            lines[#lines + 1] = "    }"
        end
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function zip_map_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, lhs_access, rhs_access = access_named(desc, "dst"), access_named(desc, "lhs"), access_named(desc, "rhs")
        local lt, rt = c_type(shape.lhs_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local i = cn("i")
        return emit_void_fn(artifact, { rt .. " *dst", const_elem_ptr_decl(shape.lhs_ty, "lhs"), const_elem_ptr_decl(shape.rhs_ty, "rhs"), "int32_t start", "int32_t stop" }, {
            loop_i(stride, {
                C.assign(
                    access_c_expr(dst_access, "dst", i),
                    c_binary_expr(
                        shape.op,
                        access_c_expr(lhs_access, "lhs", i),
                        access_c_expr(rhs_access, "rhs", i),
                        shape.result_ty,
                        shape.int_semantics,
                        shape.float_mode
                    )
                ),
            }),
        })
    end

    local function scan_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, xs_access = access_named(desc, "dst"), access_named(desc, "xs")
        local et, rt = c_type(shape.elem_ty), c_type(shape.result_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and rt or unsigned_c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = rt .. " " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", const_elem_ptr_decl(shape.elem_ty, "xs"), "int32_t start", "int32_t stop", rt .. " init" }), ", ") .. ") {"
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
        local dst_param = et .. " *dst"
        local src_param = const_elem_ptr_decl(shape.elem_ty, "src")
        if shape.semantics ~= Stencil.StencilCopyMemMove and shape.semantics ~= Stencil.StencilCopyMayOverlapBackward then
            dst_param = et .. " *__restrict dst"
            src_param = c_type(shape.elem_ty) .. " const *__restrict src"
        end
        local plain_bulk = stride == 1 and is_plain_linear_access(dst_access) and is_plain_linear_access(src_access)
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { dst_param, src_param, "int32_t start", "int32_t stop" }), ", ") .. ") {"
        if plain_bulk and shape.semantics == Stencil.StencilCopyNoOverlap then
            lines[#lines + 1] = "    if (stop > start) memcpy(dst + start, src + start, (size_t)(stop - start) * sizeof(dst[0]));"
        elseif plain_bulk and shape.semantics == Stencil.StencilCopyMemMove then
            lines[#lines + 1] = "    if (stop > start) memmove(dst + start, src + start, (size_t)(stop - start) * sizeof(dst[0]));"
        elseif shape.semantics == Stencil.StencilCopyMayOverlapBackward then
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
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        " .. access_ref(dst_access, "dst", "i") .. " = value;"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function find_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "int32_t " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { const_elem_ptr_decl(shape.elem_ty, "xs"), "int32_t start", "int32_t stop" }), ", ") .. ") {"
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
        local pred = predicate_expr(shape.pred, access_ref(xs_access, "xs", "i"), shape.elem_ty)
        local lines = {}
        lines[#lines + 1] = "int32_t " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { et .. " *dst", const_elem_ptr_decl(shape.elem_ty, "xs"), "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    int32_t out = start;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") { if " .. pred .. " " .. access_ref(dst_access, "dst", "out++") .. " = " .. access_ref(xs_access, "xs", "i") .. "; }"
        lines[#lines + 1] = "    int32_t split = out;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") { if (!" .. pred .. ") " .. access_ref(dst_access, "dst", "out++") .. " = " .. access_ref(xs_access, "xs", "i") .. "; }"
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
        local dst = access_ref(dst_access, "dst", "i")
        local x = access_ref(xs_access, "xs", "i")
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { dt .. " *dst", const_elem_ptr_decl(shape.src_ty, "xs"), "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
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
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", const_elem_ptr_decl(shape.elem_ty, "xs"), "int32_t start", "int32_t stop" }), ", ") .. ") {"
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
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. table.concat(source_params(artifact, { rt .. " *dst", const_elem_ptr_decl(shape.lhs_ty, "lhs"), const_elem_ptr_decl(shape.rhs_ty, "rhs"), "int32_t start", "int32_t stop" }), ", ") .. ") {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") " .. access_ref(dst_access, "dst", "i") .. " = " .. bool_result_expr(compare_expr(shape.cmp, access_ref(lhs_access, "lhs", "i"), access_ref(rhs_access, "rhs", "i")), shape.result_ty) .. ";"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function select_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access = access_named(desc, "dst")
        local cond_access = access_named(desc, "cond")
        local then_access = access_named(desc, "then_xs")
        local else_access = access_named(desc, "else_xs")
        local rt = c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local i = cn("i")
        return emit_void_fn(artifact, { rt .. " *dst", const_elem_ptr_decl(shape.cond_ty, "cond"), const_elem_ptr_decl(shape.then_ty, "then_xs"), const_elem_ptr_decl(shape.else_ty, "else_xs"), "int32_t start", "int32_t stop" }, {
            loop_i(stride, {
                C.assign(
                    access_c_expr(dst_access, "dst", i),
                    C.select(
                        c_predicate_expr(shape.pred, access_c_expr(cond_access, "cond", i)),
                        access_c_expr(then_access, "then_xs", i),
                        access_c_expr(else_access, "else_xs", i)
                    )
                ),
            }),
        })
    end

    local function gather_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access, idx_access = access_named(desc, "dst"), access_named(desc, "idx")
        local stride = tonumber(shape.stride) or 1
        local schedule = artifact.instance.schedule
        local unroll = pvm.classof(schedule) == Stencil.StencilScheduleUnrolled and tonumber(schedule.factor) or 1
        unroll = math.max(1, math.floor(unroll or 1))
        local body = assume_aligned_stmts(artifact, { "dst", "src", "idx" })
        if unroll > 1 and stride == 1 then
            body[#body + 1] = C.decl. i[C.i32](C.raw_expr("start"))
            body[#body + 1] = C.decl. stop_unrolled[C.i32](C.raw_expr("start + ((stop - start) / " .. tostring(unroll) .. ") * " .. tostring(unroll)))
            local unrolled_body = {}
            for lane = 0, unroll - 1 do
                local ix = lane == 0 and "i" or ("i + " .. tostring(lane))
                unrolled_body[#unrolled_body + 1] = C.assign(C.raw_expr(access_ref(dst_access, "dst", ix)), C.raw_expr("src[" .. access_ref(idx_access, "idx", ix) .. "]"))
            end
            body[#body + 1] = C.for_ { "", C.raw_expr("i < stop_unrolled"), "i += " .. tostring(unroll) } {
                _(unrolled_body),
            }
            body[#body + 1] = C.for_ { "", C.raw_expr("i < stop"), "i++" } {
                C.assign(C.raw_expr(access_ref(dst_access, "dst", "i")), C.raw_expr("src[" .. access_ref(idx_access, "idx", "i") .. "]")),
            }
        else
            body[#body + 1] = loop_i(stride, {
                C.assign(C.raw_expr(access_ref(dst_access, "dst", "i")), C.raw_expr("src[" .. access_ref(idx_access, "idx", "i") .. "]")),
            })
        end
        return emit_void_fn(artifact, {
            ptr_decl(shape.elem_ty, "dst", { restrict = access_noalias(artifact, "dst") }),
            ptr_decl(shape.elem_ty, "src", { const = true, restrict = access_noalias(artifact, "src") }),
            ptr_decl(shape.index_ty, "idx", { const = true, restrict = access_noalias(artifact, "idx") }),
            "int32_t start",
            "int32_t stop",
        }, body)
    end

    local function scatter_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local src_access, idx_access = access_named(desc, "src"), access_named(desc, "idx")
        local stride = tonumber(shape.stride) or 1
        local schedule = artifact.instance.schedule
        local unroll = pvm.classof(schedule) == Stencil.StencilScheduleUnrolled and tonumber(schedule.factor) or 1
        unroll = math.max(1, math.floor(unroll or 1))
        local body = assume_aligned_stmts(artifact, { "dst", "src", "idx" })
        if unroll > 1 and stride == 1 then
            body[#body + 1] = C.decl. i[C.i32](C.raw_expr("start"))
            body[#body + 1] = C.decl. stop_unrolled[C.i32](C.raw_expr("start + ((stop - start) / " .. tostring(unroll) .. ") * " .. tostring(unroll)))
            local unrolled_body = {}
            for lane = 0, unroll - 1 do
                local ix = lane == 0 and "i" or ("i + " .. tostring(lane))
                unrolled_body[#unrolled_body + 1] = C.assign(C.raw_expr("dst[" .. access_ref(idx_access, "idx", ix) .. "]"), C.raw_expr(access_ref(src_access, "src", ix)))
            end
            body[#body + 1] = C.for_ { "", C.raw_expr("i < stop_unrolled"), "i += " .. tostring(unroll) } {
                _(unrolled_body),
            }
            body[#body + 1] = C.for_ { "", C.raw_expr("i < stop"), "i++" } {
                C.assign(C.raw_expr("dst[" .. access_ref(idx_access, "idx", "i") .. "]"), C.raw_expr(access_ref(src_access, "src", "i"))),
            }
        else
            body[#body + 1] = loop_i(stride, {
                C.assign(C.raw_expr("dst[" .. access_ref(idx_access, "idx", "i") .. "]"), C.raw_expr(access_ref(src_access, "src", "i"))),
            })
        end
        return emit_void_fn(artifact, {
            ptr_decl(shape.elem_ty, "dst", { restrict = access_noalias(artifact, "dst") }),
            ptr_decl(shape.elem_ty, "src", { const = true, restrict = access_noalias(artifact, "src") }),
            ptr_decl(shape.index_ty, "idx", { const = true, restrict = access_noalias(artifact, "idx") }),
            "int32_t start",
            "int32_t stop",
        }, body)
    end

    local function in_place_map_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local x = access_ref(xs_access, "xs", "i")
        return emit_void_fn(artifact, { et .. " *xs", "int32_t start", "int32_t stop" }, {
            loop_i(stride, {
                C.assign(C.raw_expr(x), C.raw_expr(unary_expr(shape.op, x, shape.elem_ty, shape.int_semantics, shape.float_mode))),
            }),
        })
    end

    local function count_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        return emit_c_fn(artifact, "int32_t", { const_elem_ptr_decl(shape.elem_ty, "xs"), "int32_t start", "int32_t stop" }, {
            C.decl. count[C.i32](0),
            loop_i(stride, {
                C.if_(C.raw_expr(predicate_expr(shape.pred, access_ref(xs_access, "xs", "i"), shape.elem_ty))) {
                    C.assign(C.raw_expr("count"), C.raw_expr("count + 1")),
                },
            }),
            C.return_(C.raw_expr("count")),
        })
    end

    local function map_reduce_array_source(artifact)
        local shape = artifact_shape(artifact)
        local xs_access = access_named(artifact.instance.descriptor, "xs")
        local et, mt, rt = c_type(shape.elem_ty), c_type(shape.mapped_ty), c_type(shape.result_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and rt or unsigned_c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        return emit_c_fn(artifact, rt, { const_elem_ptr_decl(shape.elem_ty, "xs"), "int32_t start", "int32_t stop", rt .. " init" }, {
            C.decl. acc[C.type[acc_ty]](C.raw_expr("(" .. acc_ty .. ")init")),
            loop_i(stride, {
                C.assign(C.raw_expr("acc"), C.raw_expr(reduction_update_expr(shape.reduction, "acc", unary_expr(shape.op, access_ref(xs_access, "xs", "i"), shape.mapped_ty, shape.op_int_semantics, shape.op_float_mode), shape.result_ty))),
            }),
            C.return_(C.raw_expr("(" .. rt .. ")acc")),
        })
    end

    local function zip_reduce_array_source(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local lhs_access, rhs_access = access_named(desc, "lhs"), access_named(desc, "rhs")
        local lt, rt = c_type(shape.lhs_ty), c_type(shape.result_ty)
        local acc_type_node = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and c_type_node(shape.result_ty) or c_unsigned_type_node(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local i = cn("i")
        return emit_c_fn(artifact, rt, { const_elem_ptr_decl(shape.lhs_ty, "lhs"), const_elem_ptr_decl(shape.rhs_ty, "rhs"), "int32_t start", "int32_t stop", rt .. " init" }, {
            C.decl. acc[acc_type_node](C.cast[acc_type_node](cn("init"))),
            loop_i(stride, {
                C.assign(
                    cn("acc"),
                    c_reduction_update_expr(
                        shape.reduction,
                        cn("acc"),
                        c_binary_expr(
                            shape.op,
                            access_c_expr(lhs_access, "lhs", i),
                            access_c_expr(rhs_access, "rhs", i),
                            shape.mapped_ty,
                            shape.op_int_semantics,
                            shape.op_float_mode
                        ),
                        shape.result_ty
                    )
                ),
            }),
            C.return_(c_cast(shape.result_ty, cn("acc"))),
        })
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
        if kind == "select_array" then return select_array_source(artifact) end
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
        local out = { "#include <stdint.h>", "#include <stddef.h>", "#include <string.h>", "#include <math.h>", "typedef intptr_t ml_index;" }
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

    T._lalin_api_cache.stencil_c = api
    return api
end

return bind_context
