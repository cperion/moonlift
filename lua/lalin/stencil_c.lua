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
    local descriptor_accesses
    local window_axis_coord

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
            if pvm.classof(access.layout) ~= Stencil.StencilLayoutScalar then out[#out + 1] = access.name end
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

    local function param_fragment(items)
        return LLBL.fragment("params", items)
    end

    local function structured_param(name, ty)
        return { name = name, type = ty }
    end

    local function loop_i(stride, body)
        return C.for_ { C.decl. i[C.i32](cn("start")), C.lt (cn("i"))(cn("stop")), C.assign(cn("i"), cn("i") + (tonumber(stride) or 1)) } {
            _(body),
        }
    end

    local function reverse_loop_i(stride, body_for_index)
        stride = tonumber(stride) or 1
        return C.if_(C.gt (cn("stop"))(cn("start"))) {
            C.decl. __ml_last[C.i32](cn("start") + (((cn("stop") - cn("start")) - 1) / stride) * stride),
            C.for_ { C.decl. i[C.i32](cn("__ml_last")), C.ge (cn("i"))(cn("start")), C.assign(cn("i"), cn("i") - stride) } {
                _(body_for_index(cn("i"))),
            },
        }
    end

    local function descending_loop_i(stride, body_for_index)
        stride = tonumber(stride) or 1
        return C.for_ { C.decl. i[C.i32](cn("start")), C.gt (cn("i"))(cn("stop")), C.assign(cn("i"), cn("i") - stride) } {
            _(body_for_index(cn("i"))),
        }
    end

    local function producer_param_structs(producer)
        if producer == nil or producer.kind == "range1d" then
            return {
                structured_param("start", C.i32),
                structured_param("stop", C.i32),
            }
        end
        if producer.kind == "range_nd" or producer.kind == "window_nd" or producer.kind == "tiled_nd" then
            local params = {}
            for _, axis in ipairs(producer.axes or {}) do
                params[#params + 1] = structured_param(axis.start_param, C.i32)
                params[#params + 1] = structured_param(axis.stop_param, C.i32)
            end
            return params
        end
        error("stencil_c: unsupported producer plan " .. tostring(producer.kind), 3)
    end

    local function append_producer_param_structs(params, producer)
        local producer_params = producer_param_structs(producer)
        for i = 1, #producer_params do params[#params + 1] = producer_params[i] end
    end

    local function range_nd_linear_index_from_coords(producer, coords)
        local linear = nil
        for axis_index, axis in ipairs(producer.axes or {}) do
            local iv = coords and coords[axis_index] or cn("__ml_axis" .. tostring(axis_index))
            local offset = iv - cn(axis.start_param)
            local step = tonumber(axis.step) or 1
            if step ~= 1 then offset = offset / step end
            if linear == nil then
                linear = offset
            else
                linear = linear * cn("__ml_extent" .. tostring(axis_index)) + offset
            end
        end
        return linear or 0
    end

    local function range_nd_linear_index(producer)
        return range_nd_linear_index_from_coords(producer, nil)
    end

    local function current_axis_values(producer)
        local out = {}
        for axis_index = 1, #(producer.axes or {}) do out[axis_index] = cn("__ml_axis" .. tostring(axis_index)) end
        return out
    end

    local function loop_ctx(producer, index, axes)
        return { producer = producer, index = index, axis_values = axes or {} }
    end

    local function nd_axis_extents(producer)
        local stmts = {}
        for axis_index, axis in ipairs(producer.axes or {}) do
            local step = tonumber(axis.step) or 1
            local span = cn(axis.stop_param) - cn(axis.start_param)
            local extent = step == 1 and span or ((span + (step - 1)) / step)
            stmts[#stmts + 1] = C.decl[LLBL.N["__ml_extent" .. tostring(axis_index)]][C.i32](extent)
        end
        return stmts
    end

    local function range_nd_loop(producer, body_for_index)
        local axes = producer.axes or {}
        local stmts = nd_axis_extents(producer)
        local function nest(axis_index)
            if axis_index > #axes then
                return {
                    C.decl. __ml_i[C.i32](range_nd_linear_index(producer)),
                    _(body_for_index(cn("__ml_i"), loop_ctx(producer, cn("__ml_i"), current_axis_values(producer)))),
                }
            end
            local axis = axes[axis_index]
            local iv = LLBL.N["__ml_axis" .. tostring(axis_index)]
            return {
                C.for_ {
                    C.decl[iv][C.i32](cn(axis.start_param)),
                    C.lt (cn(iv))(cn(axis.stop_param)),
                    C.assign(cn(iv), cn(iv) + (tonumber(axis.step) or 1))
                } {
                    _(nest(axis_index + 1)),
                },
            }
        end
        local loop_body = nest(1)
        for i = 1, #loop_body do stmts[#stmts + 1] = loop_body[i] end
        return stmts
    end

    local function tiled_nd_loop(producer, body_for_index)
        local axes = producer.axes or {}
        local stmts = nd_axis_extents(producer)
        local function tile_nest(axis_index)
            if axis_index > #axes then
                local function point_nest(point_axis)
                    if point_axis > #axes then
                        return {
                            C.decl. __ml_i[C.i32](range_nd_linear_index(producer)),
                            _(body_for_index(cn("__ml_i"), loop_ctx(producer, cn("__ml_i"), current_axis_values(producer)))),
                        }
                    end
                    local axis = axes[point_axis]
                    local iv = LLBL.N["__ml_axis" .. tostring(point_axis)]
                    local tile_iv = cn("__ml_tile_axis" .. tostring(point_axis))
                    local tile_end = cn("__ml_tile_end" .. tostring(point_axis))
                    return {
                        C.decl[LLBL.N["__ml_tile_end" .. tostring(point_axis)]][C.i32](
                            C.select (C.lt (tile_iv + tonumber(producer.tile_sizes[point_axis] or 1))(cn(axis.stop_param)))(tile_iv + tonumber(producer.tile_sizes[point_axis] or 1))(cn(axis.stop_param))
                        ),
                        C.for_ {
                            C.decl[iv][C.i32](tile_iv),
                            C.lt (cn(iv))(tile_end),
                            C.assign(cn(iv), cn(iv) + (tonumber(axis.step) or 1))
                        } {
                            _(point_nest(point_axis + 1)),
                        },
                    }
                end
                return point_nest(1)
            end
            local axis = axes[axis_index]
            local tile = tonumber(producer.tile_sizes[axis_index] or 1)
            local iv = LLBL.N["__ml_tile_axis" .. tostring(axis_index)]
            local tile_step = tile * (tonumber(axis.step) or 1)
            return {
                C.for_ {
                    C.decl[iv][C.i32](cn(axis.start_param)),
                    C.lt (cn(iv))(cn(axis.stop_param)),
                    C.assign(cn(iv), cn(iv) + tile_step)
                } {
                    _(tile_nest(axis_index + 1)),
                },
            }
        end
        local loop_body = tile_nest(1)
        for i = 1, #loop_body do stmts[#stmts + 1] = loop_body[i] end
        return stmts
    end

    local function producer_loop(producer, body_for_index)
        if producer == nil or producer.kind == "range1d" then
            local p = producer or { kind = "range1d", order = "forward" }
            if p.order == "backward" then
                return { descending_loop_i(p.stride or 1, function(i) return body_for_index(i, loop_ctx(p, i, { i })) end) }
            end
            return { loop_i(p.stride or 1, body_for_index(cn("i"), loop_ctx(p, cn("i"), { cn("i") }))) }
        end
        if producer.kind == "range_nd" or producer.kind == "window_nd" then return range_nd_loop(producer, body_for_index) end
        if producer.kind == "tiled_nd" then return tiled_nd_loop(producer, body_for_index) end
        error("stencil_c: unsupported producer loop " .. tostring(producer.kind), 3)
    end

    local function axis_set_map(axes)
        local out = {}
        for _, axis in ipairs(axes or {}) do out[tonumber(type(axis) == "table" and axis.index or axis)] = true end
        return out
    end

    local function axis_loop_stmt(producer, axis_index, body)
        local axis = producer.axes[axis_index]
        local iv = LLBL.N["__ml_axis" .. tostring(axis_index)]
        return C.for_ {
            C.decl[iv][C.i32](cn(axis.start_param)),
            C.lt (cn(iv))(cn(axis.stop_param)),
            C.assign(cn(iv), cn(iv) + (tonumber(axis.step) or 1))
        } {
            _(body),
        }
    end

    local function nest_axis_loops(producer, axis_indices, body_fn, pos)
        pos = pos or 1
        if pos > #axis_indices then return body_fn() end
        return { axis_loop_stmt(producer, axis_indices[pos], nest_axis_loops(producer, axis_indices, body_fn, pos + 1)) }
    end

    local function axis_indices(producer, pred)
        local out = {}
        for axis_index = 1, #(producer.axes or {}) do
            if pred(axis_index) then out[#out + 1] = axis_index end
        end
        return out
    end

    local function subset_linear_index(producer, keep_axes)
        local keep = axis_set_map(keep_axes)
        local linear = nil
        for axis_index, axis in ipairs(producer.axes or {}) do
            if keep[axis_index] then
                local iv = cn("__ml_axis" .. tostring(axis_index))
                local offset = iv - cn(axis.start_param)
                local step = tonumber(axis.step) or 1
                if step ~= 1 then offset = offset / step end
                if linear == nil then
                    linear = offset
                else
                    linear = linear * cn("__ml_extent" .. tostring(axis_index)) + offset
                end
            end
        end
        return linear or 0
    end

    local function window_boundary_flags(producer)
        local has_zero, has_reject = false, false
        for _, window in ipairs(producer.windows or {}) do
            has_zero = has_zero or window.boundary == Stencil.StencilWindowBoundaryZero
            has_reject = has_reject or window.boundary == Stencil.StencilWindowBoundaryReject
        end
        return has_zero, has_reject
    end

    local function window_coords_with_offsets(producer, offsets)
        local coords = {}
        local bounds = {}
        for axis_index = 1, #(producer.axes or {}) do
            local coord, in_bounds = window_axis_coord(producer, axis_index, cn("__ml_axis" .. tostring(axis_index)), offsets[axis_index] or 0)
            coords[axis_index] = coord
            if in_bounds ~= nil then bounds[#bounds + 1] = in_bounds end
        end
        return coords, bounds
    end

    local function nest_window_offset_loops(producer, axes, body_fn, offsets, pos)
        offsets = offsets or {}
        pos = pos or 1
        if pos > #axes then return body_fn(offsets) end
        local axis_index = axes[pos]
        local window = producer.windows[axis_index]
        local iv = LLBL.N["__ml_win_axis" .. tostring(axis_index)]
        local iv_expr = cn("__ml_win_axis" .. tostring(axis_index))
        return {
            C.for_ {
                C.decl[iv][C.i32](-(tonumber(window.before) or 0)),
                C.le (iv_expr)(tonumber(window.after) or 0),
                C.assign(iv_expr, iv_expr + 1)
            } {
                _(nest_window_offset_loops(producer, axes, body_fn, setmetatable({ [axis_index] = iv_expr }, { __index = offsets }), pos + 1)),
            },
        }
    end

    local function assume_aligned_stmts(artifact, names)
        local stmts = {}
        for _, name in ipairs(names) do
            local bytes = access_alignment_bytes(artifact, name)
            if bytes ~= nil and bytes > 0 then
                stmts[#stmts + 1] = C.assign(cn(name), C.builtin.assume_aligned { cn(name), bytes })
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

    local function scatter_reduce_conflicts_materialized(conflicts)
        return conflicts == nil
            or conflicts == Stencil.StencilScatterReduceSequential
            or conflicts == Stencil.StencilScatterReduceUniqueIndices
    end

    local function proof_list(plan)
        local eq = plan and plan.body and plan.body.equivalence or nil
        if pvm.classof(eq) == Kernel.KernelEquivalenceProof then return eq.proofs or {} end
        return {}
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

    local function is_int_like(ty)
        local cls = pvm.classof(ty)
        return cls == Code.CodeTyInt or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function is_signed_int(ty)
        return pvm.classof(ty) == Code.CodeTyInt and ty.signedness == Code.CodeSigned
    end

    local ArtifactPlan = require("lalin.stencil_artifact_plan")(T)
    local artifact_shape = ArtifactPlan.artifact_shape
    descriptor_accesses = ArtifactPlan.descriptor_accesses
    local access_named = ArtifactPlan.access_named
    local stride_param_name = ArtifactPlan.stride_param_name
    local dynamic_stride_accesses = ArtifactPlan.dynamic_stride_accesses
    local affine_offset_param_name = ArtifactPlan.affine_offset_param_name
    local dynamic_affine_offset_accesses = ArtifactPlan.dynamic_affine_offset_accesses

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
        if cls == Code.CodeTyDataPtr then
            return ty.pointee and C.ptr[c_type_node(ty.pointee)] or C.void_ptr
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

    local access_c_expr

    local function value_expr_c_expr(expr)
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprConst and pvm.classof(expr.const) == Code.CodeConstLiteral then
            local lit = expr.const.literal
            if pvm.classof(lit) == Core.LitInt then return tonumber(lit.raw) or 0 end
        end
        error("stencil_c: AffineND layout currently requires constant coefficients", 3)
    end

    local function access_offset_c_expr(access, index, access_by_name, ctx)
        local top = access.layout
        local cls = pvm.classof(top)
        if cls == Stencil.StencilLayoutFieldProjection then
            return access_offset_c_expr({ layout = top.parent, name = access.name }, index, access_by_name, ctx)
        end
        if cls == Stencil.StencilLayoutSoAComponent then
            return access_offset_c_expr({ layout = top.parent, name = access.name }, index, access_by_name, ctx)
        end
        if cls == Stencil.StencilLayoutIndexed then
            local index_name = top.index.name
            local index_access = access_by_name and access_by_name[index_name] or { layout = Stencil.StencilLayoutContiguous(1), name = index_name }
            local idx = access_c_expr(index_access, index_name, index, access_by_name, ctx)
            local stride = tonumber(top.stride) or 1
            local logical = stride == 1 and idx or idx * stride
            return access_offset_c_expr({ layout = top.parent, name = access.name }, logical, access_by_name, ctx)
        end
        if cls == Stencil.StencilLayoutAffine1D then
            local scale = tonumber(top.scale) or 1
            local offset = top.offset ~= nil and cn(affine_offset_param_name(access)) or 0
            local logical = scale == 1 and (offset + index) or (offset + index * scale)
            return access_offset_c_expr({ layout = top.parent, name = access.name }, logical, access_by_name, ctx)
        end
        if cls == Stencil.StencilLayoutAffineND then
            if ctx == nil or ctx.axis_values == nil then error("stencil_c: AffineND layout requires producer loop context", 3) end
            local logical = top.offset ~= nil and cn(affine_offset_param_name(access)) or 0
            for _, term in ipairs(top.terms or {}) do
                local axis_value = assert(ctx.axis_values[term.axis.index], "stencil_c: missing AffineND axis value")
                logical = logical + axis_value * value_expr_c_expr(term.coeff)
            end
            return access_offset_c_expr({ layout = top.parent, name = access.name }, logical, access_by_name, ctx)
        end
        if cls == Stencil.StencilLayoutViewDescriptor then
            local stride = top.stride_const or cn(stride_param_name(access))
            if tonumber(stride) == 1 then return index end
            return index * stride
        end
        return index
    end

    access_c_expr = function(access, base, index, access_by_name, ctx)
        local base_expr = cn(base)
        local top = access.layout
        if pvm.classof(top) == Stencil.StencilLayoutFieldProjection then
            return base_expr[access_offset_c_expr({ layout = top.parent, name = access.name }, index, access_by_name, ctx)][sanitize(top.field_name)]
        end
        return base_expr[access_offset_c_expr(access, index, access_by_name, ctx)]
    end

    local function field_layout_for_param(layout)
        local cls = pvm.classof(layout)
        if cls == Stencil.StencilLayoutFieldProjection then return layout end
        if cls == Stencil.StencilLayoutIndexed then return field_layout_for_param(layout.parent) end
        if cls == Stencil.StencilLayoutAffine1D then return field_layout_for_param(layout.parent) end
        if cls == Stencil.StencilLayoutAffineND then return field_layout_for_param(layout.parent) end
        return nil
    end

    local function c_access_param_type_node(access, mutable, artifact)
        if pvm.classof(access.layout) == Stencil.StencilLayoutScalar then return c_type_node(access.ty) end
        local field = field_layout_for_param(access.layout)
        local base_ty = field and field.record_ty or access.ty
        local ptr_ty = mutable and C.ptr[c_type_node(base_ty)] or C.ptr[C.const[c_type_node(base_ty)]]
        if artifact ~= nil and access_noalias(artifact, access.name) then ptr_ty = C.restrict[ptr_ty] end
        return ptr_ty
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
        if cmp == Core.CmpEq then return C.eq (lhs)(rhs) end
        if cmp == Core.CmpNe then return C.ne (lhs)(rhs) end
        if cmp == Core.CmpLt then return C.lt (lhs)(rhs) end
        if cmp == Core.CmpLe then return C.le (lhs)(rhs) end
        if cmp == Core.CmpGt then return C.gt (lhs)(rhs) end
        if cmp == Core.CmpGe then return C.ge (lhs)(rhs) end
        error("stencil_c: unsupported compare op " .. cmp_name(cmp), 3)
    end

    local function all_c_node(terms)
        if #terms == 0 then return 1 end
        local out = terms[1]
        for i = 2, #terms do out = C.land (out)(terms[i]) end
        return out
    end

    local function any_c_node(terms)
        if #terms == 0 then return 0 end
        local out = terms[1]
        for i = 2, #terms do out = C.lor (out)(terms[i]) end
        return out
    end

    local function c_predicate_expr(pred, value)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return C.ne (value)(0) end
        if cls == Stencil.StencilPredCompareConst then
            return c_compare_expr(
                pred.cmp,
                c_cast(pred.operand_ty, value),
                c_cast(pred.operand_ty, const_literal_value(pred.value))
            )
        end
        if cls == Stencil.StencilPredRange then
            local lhs = c_cast(pred.operand_ty, value)
            return C.land (c_compare_expr(pred.lower_cmp, lhs, c_cast(pred.operand_ty, const_literal_value(pred.lower))))(c_compare_expr(pred.upper_cmp, lhs, c_cast(pred.operand_ty, const_literal_value(pred.upper))))
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

    local function window_offset_by_axis(offsets)
        local out = {}
        for _, offset in ipairs(offsets or {}) do out[tonumber(offset.axis.index)] = tonumber(offset.offset) or 0 end
        return out
    end

    local function axis_last_coord(axis)
        local step = tonumber(axis.step) or 1
        return cn(axis.start_param) + (((cn(axis.stop_param) - cn(axis.start_param)) - 1) / step) * step
    end

    function window_axis_coord(producer, axis_index, base_coord, offset)
        local axis = producer.axes[axis_index]
        local window = producer.windows[axis_index]
        local step = tonumber(axis.step) or 1
        local raw = base_coord + offset * step
        local in_bounds = C.land (C.ge (raw)(cn(axis.start_param)))(C.lt (raw)(cn(axis.stop_param)))
        if window.boundary == Stencil.StencilWindowBoundaryClamp then
            return C.select (C.lt (raw)(cn(axis.start_param)))(cn(axis.start_param))(C.select (C.ge (raw)(cn(axis.stop_param)))(axis_last_coord(axis))(raw)), nil
        end
        if window.boundary == Stencil.StencilWindowBoundaryWrap then
            local extent = cn("__ml_extent" .. tostring(axis_index))
            local logical = ((base_coord - cn(axis.start_param)) / step) + offset
            local wrapped = ((logical % extent) + extent) % extent
            return cn(axis.start_param) + wrapped * step, nil
        end
        return raw, in_bounds
    end

    local function c_window_input_expr(expr, desc, access_by_name, ctx)
        if ctx == nil or ctx.producer == nil or ctx.producer.kind ~= "window_nd" then
            error("stencil_c: window-relative apply input requires a WindowND producer context", 3)
        end
        local name = expr.access.name
        local access = access_by_name[name] or access_named(desc, name)
        local offsets = window_offset_by_axis(expr.offsets)
        local coords = {}
        local bounds = {}
        for axis_index = 1, #(ctx.producer.axes or {}) do
            local coord, in_bounds = window_axis_coord(ctx.producer, axis_index, ctx.axis_values[axis_index], offsets[axis_index] or 0)
            coords[axis_index] = coord
            if in_bounds ~= nil then bounds[#bounds + 1] = in_bounds end
        end
        local index = range_nd_linear_index_from_coords(ctx.producer, coords)
        local value = access_c_expr(access, name, index, access_by_name, ctx)
        if #bounds == 0 then return value end
        local in_bounds = all_c_node(bounds)
        local has_zero = false
        local has_reject = false
        for _, window in ipairs(ctx.producer.windows or {}) do
            has_zero = has_zero or window.boundary == Stencil.StencilWindowBoundaryZero
            has_reject = has_reject or window.boundary == Stencil.StencilWindowBoundaryReject
        end
        if has_zero then return C.select (in_bounds)(value)(c_cast(access.ty, 0)) end
        if has_reject then
            return C.stmt_expr {
                C.if_(C.not_(in_bounds)) {
                    C.expr(C.builtin.trap {}),
                },
                C.expr(value),
            }
        end
        return value
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
            C.if_(C.eq (b)(0)) {
                C.expr(C.builtin.trap {}),
            },
        }
        if is_signed_int(result_ty) then
            local min_value = c_cast(result_ty, C.shl (C.cast[c_unsigned_type_node(result_ty)](1))((tonumber(result_ty.bits) or 32) - 1))
            body[#body + 1] = C.if_(C.land (C.eq (b)(c_cast(result_ty, -1)))(C.eq (a)(min_value))) {
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
            C.decl. __ml_s[C.uint](C.band (C.cast[C.uint](rhs))(bits - 1)),
        }
        if op == Stencil.StencilBinaryShl then
            body[#body + 1] = C.expr(c_cast(result_ty, C.shl (c_unsigned_cast(result_ty, a))(s)))
            return C.stmt_expr(body)
        end
        if op == Stencil.StencilBinaryLShr or not is_signed_int(result_ty) then
            body[#body + 1] = C.expr(c_cast(result_ty, C.shr (c_unsigned_cast(result_ty, a))(s)))
            return C.stmt_expr(body)
        end
        body[#body + 1] = C.decl. __ml_mask[c_unsigned_type_node(result_ty)](C.bnot(C.cast[c_unsigned_type_node(result_ty)](0)))
        body[#body + 1] = C.decl. __ml_x[c_unsigned_type_node(result_ty)](C.band (c_unsigned_cast(result_ty, a))(mask))
        body[#body + 1] = C.if_(C.land (C.ne (s)(0))(C.lt (a)(0))) {
            C.assign(x, C.bor (C.shr (x)(s))(C.shl (mask)(bits - s))),
        } {
            C.assign(x, C.shr (x)(s)),
        }
        body[#body + 1] = C.expr(c_cast(result_ty, C.band (x)(mask)))
        return C.stmt_expr(body)
    end

    local function c_binary_expr(op, lhs, rhs, result_ty, int_semantics, float_mode)
        if op == Stencil.StencilBinaryAdd then return c_cast(result_ty, c_unsigned_cast(result_ty, lhs) + c_unsigned_cast(result_ty, rhs)) end
        if op == Stencil.StencilBinarySub then return c_cast(result_ty, c_unsigned_cast(result_ty, lhs) - c_unsigned_cast(result_ty, rhs)) end
        if op == Stencil.StencilBinaryMul then return c_cast(result_ty, c_unsigned_cast(result_ty, lhs) * c_unsigned_cast(result_ty, rhs)) end
        if op == Stencil.StencilBinaryDiv or op == Stencil.StencilBinaryMod then return c_divrem_expr(op, lhs, rhs, result_ty) end
        if op == Stencil.StencilBinaryAnd then return c_cast(result_ty, C.band (c_unsigned_cast(result_ty, lhs))(c_unsigned_cast(result_ty, rhs))) end
        if op == Stencil.StencilBinaryOr then return c_cast(result_ty, C.bor (c_unsigned_cast(result_ty, lhs))(c_unsigned_cast(result_ty, rhs))) end
        if op == Stencil.StencilBinaryXor then return c_cast(result_ty, C.bxor (c_unsigned_cast(result_ty, lhs))(c_unsigned_cast(result_ty, rhs))) end
        if op == Stencil.StencilBinaryShl or op == Stencil.StencilBinaryLShr or op == Stencil.StencilBinaryAShr then return c_shift_expr(op, lhs, rhs, result_ty) end
        if op == Stencil.StencilBinaryMin then return C.select (C.lt (lhs)(rhs))(lhs)(rhs) end
        if op == Stencil.StencilBinaryMax then return C.select (C.gt (lhs)(rhs))(lhs)(rhs) end
        error("stencil_c: unsupported binary op " .. binary_name(op), 3)
    end

    local function c_value_const_expr(value, ty)
        return c_cast(ty, const_literal_value(value))
    end

    local function c_apply_expr(expr, desc, access_by_name, index, ctx)
        local cls = pvm.classof(expr)
        if cls == Stencil.StencilApplyInput then
            local name = expr.access.name
            local access = access_by_name[name] or access_named(desc, name)
            if pvm.classof(access.layout) == Stencil.StencilLayoutScalar then return cn(name) end
            return access_c_expr(access, name, index, access_by_name, ctx)
        end
        if cls == Stencil.StencilApplyWindowInput then
            return c_window_input_expr(expr, desc, access_by_name, ctx)
        end
        if cls == Stencil.StencilApplyConst then return c_value_const_expr(expr.value, expr.ty) end
        if cls == Stencil.StencilApplyUnary then
            local result_ty = assert(expr.result_ty, "stencil_c: generic unary apply requires result_ty")
            local arg = c_apply_expr(expr.arg, desc, access_by_name, index, ctx)
            if expr.op == Stencil.StencilUnaryIdentity then return c_cast(result_ty, arg) end
            if expr.op == Stencil.StencilUnaryNeg then return c_cast(result_ty, C.cast[c_unsigned_type_node(result_ty)](0) - c_unsigned_cast(result_ty, arg)) end
            if expr.op == Stencil.StencilUnaryBitNot then return c_cast(result_ty, C.bnot(c_unsigned_cast(result_ty, arg))) end
            if expr.op == Stencil.StencilUnaryBoolNot then return c_cast(result_ty, C.not_(arg)) end
            error("stencil_c: unsupported generic unary apply " .. unary_name(expr.op), 3)
        end
        if cls == Stencil.StencilApplyBinary then
            return c_binary_expr(
                expr.op,
                c_apply_expr(expr.left, desc, access_by_name, index, ctx),
                c_apply_expr(expr.right, desc, access_by_name, index, ctx),
                assert(expr.result_ty, "stencil_c: generic binary apply requires result_ty"),
                expr.int_semantics,
                expr.float_mode
            )
        end
        if cls == Stencil.StencilApplyCast then
            if expr.op == Core.MachineCastBitcast then error("stencil_c: generic apply bitcast requires a dedicated lowering", 3) end
            return c_cast(expr.to, c_apply_expr(expr.arg, desc, access_by_name, index, ctx))
        end
        if cls == Stencil.StencilApplyPredicate then
            return c_cast(expr.result_ty, c_predicate_expr(expr.pred, c_apply_expr(expr.arg, desc, access_by_name, index, ctx)))
        end
        if cls == Stencil.StencilApplyCompare then
            return c_cast(
                expr.result_ty,
                c_compare_expr(
                    expr.cmp,
                    c_apply_expr(expr.left, desc, access_by_name, index, ctx),
                    c_apply_expr(expr.right, desc, access_by_name, index, ctx)
                )
            )
        end
        if cls == Stencil.StencilApplySelect then
            return c_cast(
                expr.result_ty,
                C.select (c_predicate_expr(expr.pred, c_apply_expr(expr.cond, desc, access_by_name, index, ctx)))(c_apply_expr(expr.then_expr, desc, access_by_name, index, ctx))(c_apply_expr(expr.else_expr, desc, access_by_name, index, ctx))
            )
        end
        error("stencil_c: unsupported generic apply expression", 3)
    end

    local function c_reduction_update_expr(kind, acc, item, ty)
        if kind == Value.ReductionAdd then return c_cast(ty, c_unsigned_cast(ty, acc) + c_unsigned_cast(ty, item)) end
        if kind == Value.ReductionMul then return c_cast(ty, c_unsigned_cast(ty, acc) * c_unsigned_cast(ty, item)) end
        if kind == Value.ReductionAnd then return c_cast(ty, C.band (c_unsigned_cast(ty, acc))(c_unsigned_cast(ty, item))) end
        if kind == Value.ReductionOr then return c_cast(ty, C.bor (c_unsigned_cast(ty, acc))(c_unsigned_cast(ty, item))) end
        if kind == Value.ReductionXor then return c_cast(ty, C.bxor (c_unsigned_cast(ty, acc))(c_unsigned_cast(ty, item))) end
        if kind == Value.ReductionMin then return C.select (C.lt (item)(acc))(item)(acc) end
        if kind == Value.ReductionMax then return C.select (C.gt (item)(acc))(item)(acc) end
        error("stencil_c: unsupported reduction " .. reduction_name(kind), 3)
    end

    local function apply_n_decl(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_name = shape.dst_name or "dst"
        local dst_access = access_named(desc, dst_name)
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end
        local params = {
            structured_param(dst_name, c_access_param_type_node(dst_access, true, artifact)),
        }
        local scalar_params = {}
        for _, access in ipairs(shape.inputs or {}) do
            if access.name ~= dst_name then
                if pvm.classof(access.layout) == Stencil.StencilLayoutScalar then
                    scalar_params[#scalar_params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
                else
                    params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
                end
            end
        end
        append_producer_param_structs(params, shape.producer)
        for i = 1, #scalar_params do params[#params + 1] = scalar_params[i] end
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local function assign_stmts(i, ctx)
            return {
                C.assign(
                    access_c_expr(dst_access, dst_name, i, access_by_name, ctx),
                    c_apply_expr(shape.expr, desc, access_by_name, i, ctx)
                ),
            }
        end
        local function copy_input_name()
            if pvm.classof(shape.store_mode) ~= Stencil.StencilStoreCopy then return nil end
            if pvm.classof(shape.expr) ~= Stencil.StencilApplyInput then return nil end
            local name = shape.expr.access.name
            if name == dst_name then return nil end
            return name
        end
        local copy_src_name = copy_input_name()
        local copy_semantics = pvm.classof(shape.store_mode) == Stencil.StencilStoreCopy and shape.store_mode.semantics or nil
        local name = LLBL.N[artifact.symbol.text]
        if copy_src_name ~= nil and shape.producer.kind == "range1d" and (copy_semantics == Stencil.StencilCopyMemMove or copy_semantics == Stencil.StencilCopyMayOverlapBackward) then
            local forward_body = producer_loop(shape.producer, assign_stmts)
            local backward_body = { reverse_loop_i(shape.stride or 1, function(i) return assign_stmts(i, loop_ctx(shape.producer, i, { i })) end) }
            return C.fn[name] { _(param_fragment(params)) } [C.void] {
                _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
                _(copy_semantics == Stencil.StencilCopyMayOverlapBackward and backward_body or {
                    C.if_(C.lt (cn(dst_name))(cn(copy_src_name))) {
                        _(forward_body),
                    } {
                        _(backward_body),
                    },
                }),
            }
        end
        return C.fn[name] { _(param_fragment(params)) } [C.void] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            _(producer_loop(shape.producer, function(i, ctx)
                return assign_stmts(i, ctx)
            end)),
        }
    end

    local function reduce_n_decl(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end
        local result_ty = c_type(shape.result_ty)
        local acc_type_node = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and c_type_node(shape.result_ty) or c_unsigned_type_node(shape.result_ty)
        local params = {}
        local dst_access
        if shape.scope_kind ~= nil and shape.scope_kind ~= "domain" then
            dst_access = access_named(desc, shape.dst_name)
            params[#params + 1] = structured_param(shape.dst_name, c_access_param_type_node(dst_access, true, artifact))
        end
        for _, access in ipairs(shape.inputs or {}) do
            params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
        end
        append_producer_param_structs(params, shape.producer)
        if shape.scope_kind == nil or shape.scope_kind == "domain" and shape.external_init ~= false then
            params[#params + 1] = structured_param("init", c_type_node(shape.result_ty))
        end
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local name = LLBL.N[artifact.symbol.text]
        if shape.scope_kind == "axes" then
            local reduce_axes = axis_set_map(shape.axes)
            local kept_axes = axis_indices(shape.producer, function(axis_index) return not reduce_axes[axis_index] end)
            local folded_axes = axis_indices(shape.producer, function(axis_index) return reduce_axes[axis_index] end)
            local function folded_body()
                local idx = range_nd_linear_index(shape.producer)
                local ctx = loop_ctx(shape.producer, idx, current_axis_values(shape.producer))
                return {
                    C.assign(
                        cn("acc"),
                        c_reduction_update_expr(
                            shape.reduction,
                            cn("acc"),
                            c_apply_expr(shape.expr, desc, access_by_name, idx, ctx),
                            shape.result_ty
                        )
                    ),
                }
            end
            local function outer_body()
                local out_idx = subset_linear_index(shape.producer, kept_axes)
                local body = {
                    C.decl. acc[acc_type_node](C.cast[acc_type_node](c_value_const_expr(shape.identity, shape.result_ty))),
                    _(nest_axis_loops(shape.producer, folded_axes, folded_body)),
                    C.assign(access_c_expr(dst_access, shape.dst_name, out_idx, access_by_name), c_cast(shape.result_ty, cn("acc"))),
                }
                return body
            end
            return C.fn[name] { _(param_fragment(params)) } [C.void] {
                _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
                _(nd_axis_extents(shape.producer)),
                _(nest_axis_loops(shape.producer, kept_axes, outer_body)),
            }
        end
        if shape.scope_kind == "window" then
            local reduce_axes = axis_indices(shape.producer, function(axis_index)
                local reduce = axis_set_map(shape.axes)
                return reduce[axis_index]
            end)
            local has_zero, has_reject = window_boundary_flags(shape.producer)
            local function window_update_body(offsets)
                local coords, bounds = window_coords_with_offsets(shape.producer, offsets)
                local idx = range_nd_linear_index_from_coords(shape.producer, coords)
                local ctx = loop_ctx(shape.producer, idx, coords)
                local item = c_apply_expr(shape.expr, desc, access_by_name, idx, ctx)
                local prefix = {}
                if #bounds > 0 then
                    local in_bounds = all_c_node(bounds)
                    if has_zero then item = C.select (in_bounds)(item)(c_cast(shape.result_ty, 0)) end
                    if has_reject then
                        prefix[#prefix + 1] = C.if_(C.not_(in_bounds)) {
                            C.expr(C.builtin.trap {}),
                        }
                    end
                end
                prefix[#prefix + 1] = C.assign(
                    cn("acc"),
                    c_reduction_update_expr(shape.reduction, cn("acc"), item, shape.result_ty)
                )
                return prefix
            end
            return C.fn[name] { _(param_fragment(params)) } [C.void] {
                _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
                _(producer_loop(shape.producer, function(i, ctx)
                    return {
                        C.decl. acc[acc_type_node](C.cast[acc_type_node](c_value_const_expr(shape.identity, shape.result_ty))),
                        _(nest_window_offset_loops(shape.producer, reduce_axes, window_update_body)),
                        C.assign(access_c_expr(dst_access, shape.dst_name, i, access_by_name), c_cast(shape.result_ty, cn("acc"))),
                    }
                end)),
            }
        end
        local init_value = shape.external_init == false and c_value_const_expr(shape.identity, shape.result_ty) or cn("init")
        return C.fn[name] { _(param_fragment(params)) } [C.type[result_ty]] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            C.decl. acc[acc_type_node](C.cast[acc_type_node](init_value)),
            _(producer_loop(shape.producer, function(i, ctx)
                return {
                    C.assign(
                        cn("acc"),
                        c_reduction_update_expr(
                            shape.reduction,
                            cn("acc"),
                            c_apply_expr(shape.expr, desc, access_by_name, i, ctx),
                            shape.result_ty
                        )
                    ),
                }
            end)),
            C.return_(c_cast(shape.result_ty, cn("acc"))),
        }
    end

    local function scan_n_decl(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_access = access_named(desc, "dst")
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end
        local result_ty = c_type(shape.result_ty)
        local acc_type_node = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and c_type_node(shape.result_ty) or c_unsigned_type_node(shape.result_ty)
        local params = {
            structured_param("dst", c_access_param_type_node(dst_access, true, artifact)),
        }
        for _, access in ipairs(shape.inputs or {}) do
            params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
        end
        append_producer_param_structs(params, shape.producer)
        params[#params + 1] = structured_param("init", c_type_node(shape.result_ty))
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local name = LLBL.N[artifact.symbol.text]
        if shape.producer.kind ~= "range1d" then
            local scan_axis = tonumber(shape.axis.index)
            local outer_axes = axis_indices(shape.producer, function(axis_index) return axis_index ~= scan_axis end)
            local function scan_line_body()
                local i = cn("__ml_i")
                local ctx = loop_ctx(shape.producer, i, current_axis_values(shape.producer))
                local item = c_apply_expr(shape.expr, desc, access_by_name, i, ctx)
                local scan_stmts
                if shape.mode == Stencil.StencilScanExclusive then
                    scan_stmts = {
                        C.assign(access_c_expr(dst_access, "dst", i, access_by_name), c_cast(shape.result_ty, cn("acc"))),
                        C.assign(cn("acc"), c_reduction_update_expr(shape.reduction, cn("acc"), item, shape.result_ty)),
                    }
                else
                    scan_stmts = {
                        C.assign(cn("acc"), c_reduction_update_expr(shape.reduction, cn("acc"), item, shape.result_ty)),
                        C.assign(access_c_expr(dst_access, "dst", i, access_by_name), c_cast(shape.result_ty, cn("acc"))),
                    }
                end
                return {
                    C.decl. acc[acc_type_node](C.cast[acc_type_node](cn("init"))),
                    axis_loop_stmt(shape.producer, scan_axis, {
                        C.decl. __ml_i[C.i32](range_nd_linear_index(shape.producer)),
                        _(scan_stmts),
                    }),
                }
            end
            return C.fn[name] { _(param_fragment(params)) } [C.type[result_ty]] {
                _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
                _(nd_axis_extents(shape.producer)),
                _(nest_axis_loops(shape.producer, outer_axes, scan_line_body)),
                C.return_(c_cast(shape.result_ty, 0)),
            }
        end
        return C.fn[name] { _(param_fragment(params)) } [C.type[result_ty]] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            C.decl. acc[acc_type_node](C.cast[acc_type_node](cn("init"))),
            _(producer_loop(shape.producer, function(i, ctx)
                local item = c_apply_expr(shape.expr, desc, access_by_name, i, ctx)
                if shape.mode == Stencil.StencilScanExclusive then
                    return {
                        C.assign(access_c_expr(dst_access, "dst", i, access_by_name), c_cast(shape.result_ty, cn("acc"))),
                        C.assign(cn("acc"), c_reduction_update_expr(shape.reduction, cn("acc"), item, shape.result_ty)),
                    }
                end
                return {
                    C.assign(cn("acc"), c_reduction_update_expr(shape.reduction, cn("acc"), item, shape.result_ty)),
                    C.assign(access_c_expr(dst_access, "dst", i, access_by_name), c_cast(shape.result_ty, cn("acc"))),
                }
            end)),
            C.return_(c_cast(shape.result_ty, cn("acc"))),
        }
    end

    local function scatter_reduce_n_decl(artifact)
        local shape = artifact_shape(artifact)
        if not scatter_reduce_conflicts_materialized(shape.conflicts) then
            error("stencil_c: unsupported scatter-reduce conflict semantics", 3)
        end
        local desc = artifact.instance.descriptor
        local dst_name = shape.dst_name or "dst"
        local dst_access = access_named(desc, dst_name)
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end
        local params = {
            structured_param(dst_name, c_access_param_type_node(dst_access, true, artifact)),
        }
        for _, access in ipairs(descriptor_accesses(desc)) do
            if access.name ~= dst_name and pvm.classof(access.layout) ~= Stencil.StencilLayoutScalar then
                params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
            end
        end
        append_producer_param_structs(params, shape.producer)
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local name = LLBL.N[artifact.symbol.text]
        return C.fn[name] { _(param_fragment(params)) } [C.void] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            _(producer_loop(shape.producer, function(i, ctx)
                local slot = access_c_expr(dst_access, dst_name, i, access_by_name)
                return {
                    C.assign(
                        slot,
                        c_reduction_update_expr(
                            shape.reduction,
                            slot,
                            c_apply_expr(shape.expr, desc, access_by_name, i, ctx),
                            shape.result_ty
                        )
                    ),
                }
            end)),
        }
    end

    local function find_n_decl(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end
        local params = {}
        for _, access in ipairs(shape.inputs or {}) do
            params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
        end
        append_producer_param_structs(params, shape.producer)
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local name = LLBL.N[artifact.symbol.text]
        return C.fn[name] { _(param_fragment(params)) } [c_type_node(shape.result_ty)] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            _(producer_loop(shape.producer, function(i, ctx)
                return {
                    C.if_(C.ne (c_apply_expr(shape.expr, desc, access_by_name, i, ctx))(0)) {
                        C.return_(c_cast(shape.result_ty, i)),
                    },
                }
            end)),
            C.return_(c_value_const_expr(shape.not_found, shape.result_ty)),
        }
    end

    local function partition_n_decl(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local dst_name = shape.dst_name or "dst"
        local dst_access = access_named(desc, dst_name)
        local src_access = access_named(desc, "xs")
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end
        local params = {
            structured_param(dst_name, c_access_param_type_node(dst_access, true, artifact)),
        }
        for _, access in ipairs(shape.inputs or {}) do
            if access.name ~= dst_name then
                params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
            end
        end
        append_producer_param_structs(params, shape.producer)
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local out_init = shape.producer.kind == "range1d" and cn("start") or 0
        local name = LLBL.N[artifact.symbol.text]
        return C.fn[name] { _(param_fragment(params)) } [C.i32] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            C.decl. out[C.i32](out_init),
            _(producer_loop(shape.producer, function(i, ctx)
                return {
                    C.if_(C.ne (c_apply_expr(shape.expr, desc, access_by_name, i, ctx))(0)) {
                        C.assign(access_c_expr(dst_access, dst_name, cn("out"), access_by_name), access_c_expr(src_access, "xs", i, access_by_name)),
                        C.assign(cn("out"), cn("out") + 1),
                    },
                }
            end)),
            C.decl. split[C.i32](cn("out")),
            _(producer_loop(shape.producer, function(i, ctx)
                return {
                    C.if_(C.eq (c_apply_expr(shape.expr, desc, access_by_name, i, ctx))(0)) {
                        C.assign(access_c_expr(dst_access, dst_name, cn("out"), access_by_name), access_c_expr(src_access, "xs", i, access_by_name)),
                        C.assign(cn("out"), cn("out") + 1),
                    },
                }
            end)),
            C.return_(cn("split")),
        }
    end

    local function artifact_decl(artifact)
        local kind = artifact_shape(artifact).kind
        if kind == "apply_n" then return apply_n_decl(artifact) end
        if kind == "reduce_n" then return reduce_n_decl(artifact) end
        if kind == "scan_n" then return scan_n_decl(artifact) end
        if kind == "scatter_reduce_n" then return scatter_reduce_n_decl(artifact) end
        if kind == "find_n" then return find_n_decl(artifact) end
        if kind == "partition_n" then return partition_n_decl(artifact) end
        error("stencil_c: unsupported stencil shape", 3)
    end

    function api.source(artifacts, opts)
        opts = opts or {}
        local decls = {
            C.include "stdint.h",
            C.include "stddef.h",
            C.include "string.h",
            C.include "math.h",
            C.typedef. ml_index [C.intptr_t],
        }
        for _, decl in ipairs(opts.c_decls or opts.decls or {}) do
            if C.role(decl) ~= "decl" then
                error("stencil_c: c_decls entries must be llbl.c declaration nodes", 2)
            end
            decls[#decls + 1] = decl
        end
        local seen = {}
        for _, artifact in ipairs(artifacts or {}) do
            local key = artifact.symbol.text
            if not seen[key] then
                decls[#decls + 1] = artifact_decl(artifact)
                seen[key] = true
            end
        end
        return C.emit_unit(C.unit. lalin_stencil_unit {
            _(LLBL.fragment("decls", decls)),
        }, opts)
    end

    T._lalin_api_cache.stencil_c = api
    return api
end

return bind_context
