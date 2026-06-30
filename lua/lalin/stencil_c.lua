local asdl = require("lalin.asdl")

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
    require("lalin.stencil_methods")(T)
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
        local cls = asdl.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if ty == Code.CodeTyIndex then return "index" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        return "ty"
    end

    local function c_type(ty)
        local cls = asdl.classof(ty)
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
        local vector_facts = schedule and schedule:stencil_vectorization_facts() or nil
        local facts = vector_facts and vector_facts.access_facts or {}
        for _, fact in ipairs(facts or {}) do
            if access_ref_name(fact.access) == name then return fact end
        end
        return nil
    end

    local function alias_relation(artifact, left, right)
        if left == right then return Stencil.StencilAliasNoAlias end
        local schedule = artifact.instance and artifact.instance.schedule
        local vector_facts = schedule and schedule:stencil_vectorization_facts() or nil
        local facts = vector_facts and vector_facts.alias_facts or {}
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
            if not access.layout:stencil_c_is_scalar_layout() then out[#out + 1] = access.name end
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
        if asdl.classof(fact.alignment) == Stencil.StencilAlignmentKnown then return tonumber(fact.alignment.bytes) end
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

    local function producer_param_name(axis_index, suffix)
        return "axis" .. tostring(axis_index) .. "_" .. suffix
    end

    local function producer_axis_start_param(axis_index)
        return producer_param_name(axis_index, "start")
    end

    local function producer_axis_stop_param(axis_index)
        return producer_param_name(axis_index, "stop")
    end

    function Stencil.StencilProducerShape:stencil_c_param_structs()
        error("stencil_c: unsupported producer shape", 3)
    end
    function Stencil.StencilProduceRange1D:stencil_c_param_structs()
        return {
            structured_param("start", C.i32),
            structured_param("stop", C.i32),
        }
    end
    function Stencil.StencilProduceRangeND:stencil_c_param_structs()
        local params = {}
        for axis_index = 1, #(self.axes or {}) do
            params[#params + 1] = structured_param(producer_axis_start_param(axis_index), C.i32)
            params[#params + 1] = structured_param(producer_axis_stop_param(axis_index), C.i32)
        end
        return params
    end
    function Stencil.StencilProduceWindowND:stencil_c_param_structs()
        return Stencil.StencilProduceRangeND.stencil_c_param_structs(self)
    end
    function Stencil.StencilProduceTiledND:stencil_c_param_structs()
        return Stencil.StencilProduceRangeND.stencil_c_param_structs(self)
    end

    local function producer_param_structs(producer_shape)
        return producer_shape:stencil_c_param_structs()
    end

    local function append_producer_param_structs(params, producer_shape)
        local producer_params = producer_param_structs(producer_shape)
        for i = 1, #producer_params do params[#params + 1] = producer_params[i] end
    end

    local function range_nd_linear_index_from_coords(producer, coords)
        local linear = nil
        for axis_index, axis in ipairs(producer.axes or {}) do
            local iv = coords and coords[axis_index] or cn("__ml_axis" .. tostring(axis_index))
            local offset = iv - cn(producer_axis_start_param(axis_index))
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

    local function stencil_loop_scope(producer, index, axes)
        return { producer = producer, index = index, axis_values = axes or {} }
    end

    local function nd_axis_extents(producer)
        local stmts = {}
        for axis_index, axis in ipairs(producer.axes or {}) do
            local step = tonumber(axis.step) or 1
            local span = cn(producer_axis_stop_param(axis_index)) - cn(producer_axis_start_param(axis_index))
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
                    _(body_for_index(cn("__ml_i"), stencil_loop_scope(producer, cn("__ml_i"), current_axis_values(producer)))),
                }
            end
            local axis = axes[axis_index]
            local iv = LLBL.N["__ml_axis" .. tostring(axis_index)]
            return {
                C.for_ {
                    C.decl[iv][C.i32](cn(producer_axis_start_param(axis_index))),
                    C.lt (cn(iv))(cn(producer_axis_stop_param(axis_index))),
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
                            _(body_for_index(cn("__ml_i"), stencil_loop_scope(producer, cn("__ml_i"), current_axis_values(producer)))),
                        }
                    end
                    local axis = axes[point_axis]
                    local iv = LLBL.N["__ml_axis" .. tostring(point_axis)]
                    local tile_iv = cn("__ml_tile_axis" .. tostring(point_axis))
                    local tile_end = cn("__ml_tile_end" .. tostring(point_axis))
                        return {
                            C.decl[LLBL.N["__ml_tile_end" .. tostring(point_axis)]][C.i32](
                            C.select (C.lt (tile_iv + tonumber(producer.tile_sizes[point_axis] or 1))(cn(producer_axis_stop_param(point_axis))))(tile_iv + tonumber(producer.tile_sizes[point_axis] or 1))(cn(producer_axis_stop_param(point_axis)))
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
                    C.decl[iv][C.i32](cn(producer_axis_start_param(axis_index))),
                    C.lt (cn(iv))(cn(producer_axis_stop_param(axis_index))),
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

    function Stencil.StencilProducerShape:stencil_c_loop(body_for_index)
        error("stencil_c: unsupported producer loop", 3)
    end
    function Stencil.StencilProduceRange1D:stencil_c_loop(body_for_index)
        local stride = tonumber(self.step) or 1
        if self.order == Stencil.StencilProducerBackward then
            return { descending_loop_i(stride, function(i) return body_for_index(i, stencil_loop_scope(self, i, { i })) end) }
        end
        return { loop_i(stride, body_for_index(cn("i"), stencil_loop_scope(self, cn("i"), { cn("i") }))) }
    end
    function Stencil.StencilProduceRangeND:stencil_c_loop(body_for_index)
        return range_nd_loop(self, body_for_index)
    end
    function Stencil.StencilProduceWindowND:stencil_c_loop(body_for_index)
        return range_nd_loop(self, body_for_index)
    end
    function Stencil.StencilProduceTiledND:stencil_c_loop(body_for_index)
        return tiled_nd_loop(self, body_for_index)
    end

    local function producer_loop(producer_shape, body_for_index)
        return producer_shape:stencil_c_loop(body_for_index)
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
            C.decl[iv][C.i32](cn(producer_axis_start_param(axis_index))),
            C.lt (cn(iv))(cn(producer_axis_stop_param(axis_index))),
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
                local offset = iv - cn(producer_axis_start_param(axis_index))
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
        local cls = asdl.classof(ty)
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
        if asdl.classof(eq) == Kernel.KernelEquivalenceProof then return eq.proofs or {} end
        return {}
    end

    local function is_int(ty)
        return asdl.classof(ty) == Code.CodeTyInt
    end

    local function is_float(ty)
        return asdl.classof(ty) == Code.CodeTyFloat
    end

    local function same_type(a, b)
        if a == b then return true end
        local ac, bc = asdl.classof(a), asdl.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    local function is_scalar(ty)
        local cls = asdl.classof(ty)
        return cls == Code.CodeTyInt or cls == Code.CodeTyFloat or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function supports_bitwise_ty(ty)
        return asdl.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyBool8
    end

    local function is_int_like(ty)
        local cls = asdl.classof(ty)
        return cls == Code.CodeTyInt or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function is_signed_int(ty)
        return asdl.classof(ty) == Code.CodeTyInt and ty.signedness == Code.CodeSigned
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
        local cls = asdl.classof(ty)
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
        local cls = asdl.classof(ty)
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
        local cls = asdl.classof(expr)
        if cls == Value.ValueExprConst and asdl.classof(expr.const) == Code.CodeConstLiteral then
            local lit = expr.const.literal
            if asdl.classof(lit) == Core.LitInt then return tonumber(lit.raw) or 0 end
        end
        error("stencil_c: AffineND layout currently requires constant coefficients", 3)
    end

    local access_offset_c_expr
    function Stencil.StencilAccessLayout:stencil_c_is_scalar_layout()
        return false
    end
    function Stencil.StencilLayoutScalar:stencil_c_is_scalar_layout()
        return true
    end
    function Stencil.StencilAccessLayout:stencil_c_offset(access, index, access_by_name, loop_scope)
        return index
    end
    function Stencil.StencilLayoutFieldProjection:stencil_c_offset(access, index, access_by_name, loop_scope)
        return access_offset_c_expr({ layout = self.parent, name = access.name }, index, access_by_name, loop_scope)
    end
    function Stencil.StencilLayoutSoAComponent:stencil_c_offset(access, index, access_by_name, loop_scope)
        return access_offset_c_expr({ layout = self.parent, name = access.name }, index, access_by_name, loop_scope)
    end
    function Stencil.StencilLayoutIndexed:stencil_c_offset(access, index, access_by_name, loop_scope)
        local index_name = self.index.name
        local index_access = access_by_name and access_by_name[index_name] or { layout = Stencil.StencilLayoutContiguous(1), name = index_name }
        local idx = access_c_expr(index_access, index_name, index, access_by_name, loop_scope)
        local stride = tonumber(self.stride) or 1
        local logical = stride == 1 and idx or idx * stride
        return access_offset_c_expr({ layout = self.parent, name = access.name }, logical, access_by_name, loop_scope)
    end
    function Stencil.StencilLayoutAffine1D:stencil_c_offset(access, index, access_by_name, loop_scope)
        local scale = tonumber(self.scale) or 1
        local offset = self.offset ~= nil and cn(affine_offset_param_name(access)) or 0
        local logical = scale == 1 and (offset + index) or (offset + index * scale)
        return access_offset_c_expr({ layout = self.parent, name = access.name }, logical, access_by_name, loop_scope)
    end
    function Stencil.StencilLayoutAffineND:stencil_c_offset(access, index, access_by_name, loop_scope)
        if loop_scope == nil or loop_scope.axis_values == nil then error("stencil_c: AffineND layout requires producer loop context", 3) end
        local logical = self.offset ~= nil and cn(affine_offset_param_name(access)) or 0
        for _, term in ipairs(self.terms or {}) do
            local axis_value = assert(loop_scope.axis_values[term.axis.index], "stencil_c: missing AffineND axis value")
            logical = logical + axis_value * value_expr_c_expr(term.coeff)
        end
        return access_offset_c_expr({ layout = self.parent, name = access.name }, logical, access_by_name, loop_scope)
    end
    function Stencil.StencilLayoutViewDescriptor:stencil_c_offset(access, index, access_by_name, loop_scope)
        local stride = self.stride_const or cn(stride_param_name(access))
        if tonumber(stride) == 1 then return index end
        return index * stride
    end

    access_offset_c_expr = function(access, index, access_by_name, loop_scope)
        return access.layout:stencil_c_offset(access, index, access_by_name, loop_scope)
    end

    function Stencil.StencilAccessLayout:stencil_c_access_expr(access, base, index, access_by_name, loop_scope)
        return cn(base)[access_offset_c_expr(access, index, access_by_name, loop_scope)]
    end
    function Stencil.StencilLayoutFieldProjection:stencil_c_access_expr(access, base, index, access_by_name, loop_scope)
        return cn(base)[access_offset_c_expr({ layout = self.parent, name = access.name }, index, access_by_name, loop_scope)][sanitize(self.field_name)]
    end

    access_c_expr = function(access, base, index, access_by_name, loop_scope)
        return access.layout:stencil_c_access_expr(access, base, index, access_by_name, loop_scope)
    end

    function Stencil.StencilAccessLayout:stencil_c_field_layout_for_param()
        return nil
    end
    function Stencil.StencilLayoutFieldProjection:stencil_c_field_layout_for_param()
        return self
    end
    function Stencil.StencilLayoutIndexed:stencil_c_field_layout_for_param()
        return self.parent:stencil_c_field_layout_for_param()
    end
    function Stencil.StencilLayoutAffine1D:stencil_c_field_layout_for_param()
        return self.parent:stencil_c_field_layout_for_param()
    end
    function Stencil.StencilLayoutAffineND:stencil_c_field_layout_for_param()
        return self.parent:stencil_c_field_layout_for_param()
    end

    local function field_layout_for_param(layout)
        return layout:stencil_c_field_layout_for_param()
    end

    local function c_access_param_type_node(access, mutable, artifact)
        if access.layout:stencil_c_is_scalar_layout() then return c_type_node(access.ty) end
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
        local cls = asdl.classof(expr)
        if cls ~= Value.ValueExprConst or asdl.classof(expr.const) ~= Code.CodeConstLiteral then
            error("stencil_c: select predicate const must be a literal ValueExprConst", 3)
        end
        local lit = expr.const.literal
        local lcls = asdl.classof(lit)
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
        local cls = asdl.classof(pred)
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

    local function axis_last_coord(producer, axis_index)
        local axis = producer.axes[axis_index]
        local step = tonumber(axis.step) or 1
        return cn(producer_axis_start_param(axis_index)) + (((cn(producer_axis_stop_param(axis_index)) - cn(producer_axis_start_param(axis_index))) - 1) / step) * step
    end

    function window_axis_coord(producer, axis_index, base_coord, offset)
        local axis = producer.axes[axis_index]
        local window = producer.windows[axis_index]
        local step = tonumber(axis.step) or 1
        local raw = base_coord + offset * step
        local in_bounds = C.land (C.ge (raw)(cn(producer_axis_start_param(axis_index))))(C.lt (raw)(cn(producer_axis_stop_param(axis_index))))
        if window.boundary == Stencil.StencilWindowBoundaryClamp then
            return C.select (C.lt (raw)(cn(producer_axis_start_param(axis_index))))(cn(producer_axis_start_param(axis_index)))(C.select (C.ge (raw)(cn(producer_axis_stop_param(axis_index))))(axis_last_coord(producer, axis_index))(raw)), nil
        end
        if window.boundary == Stencil.StencilWindowBoundaryWrap then
            local extent = cn("__ml_extent" .. tostring(axis_index))
            local logical = ((base_coord - cn(producer_axis_start_param(axis_index))) / step) + offset
            local wrapped = ((logical % extent) + extent) % extent
            return cn(producer_axis_start_param(axis_index)) + wrapped * step, nil
        end
        return raw, in_bounds
    end

    function Stencil.StencilProducerShape:stencil_c_is_window_nd()
        return false
    end
    function Stencil.StencilProduceWindowND:stencil_c_is_window_nd()
        return true
    end
    function Stencil.StencilProducerShape:stencil_c_is_range1d()
        return false
    end
    function Stencil.StencilProduceRange1D:stencil_c_is_range1d()
        return true
    end

    local function c_window_input_expr(expr, desc, access_by_name, loop_scope)
        if loop_scope == nil or loop_scope.producer == nil or not loop_scope.producer:stencil_c_is_window_nd() then
            error("stencil_c: window-relative point input requires a WindowND producer context", 3)
        end
        local name = expr.access.name
        local access = access_by_name[name] or access_named(desc, name)
        local offsets = window_offset_by_axis(expr.offsets)
        local coords = {}
        local bounds = {}
        for axis_index = 1, #(loop_scope.producer.axes or {}) do
            local coord, in_bounds = window_axis_coord(loop_scope.producer, axis_index, loop_scope.axis_values[axis_index], offsets[axis_index] or 0)
            coords[axis_index] = coord
            if in_bounds ~= nil then bounds[#bounds + 1] = in_bounds end
        end
        local index = range_nd_linear_index_from_coords(loop_scope.producer, coords)
        local value = access_c_expr(access, name, index, access_by_name, loop_scope)
        if #bounds == 0 then return value end
        local in_bounds = all_c_node(bounds)
        local has_zero = false
        local has_reject = false
        for _, window in ipairs(loop_scope.producer.windows or {}) do
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
        local bits = asdl.classof(result_ty) == Code.CodeTyInt and tonumber(result_ty.bits) or 8
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

    local c_point_expr
    function Stencil.StencilPointExpr:stencil_c_expr(desc, access_by_name, index, loop_scope)
        error("stencil_c: unsupported generic point expression", 3)
    end
    function Stencil.StencilPointInput:stencil_c_expr(desc, access_by_name, index, loop_scope)
        local name = self.access.name
        local access = access_by_name[name] or access_named(desc, name)
        if access.layout:stencil_c_is_scalar_layout() then return cn(name) end
        return access_c_expr(access, name, index, access_by_name, loop_scope)
    end
    function Stencil.StencilPointWindowInput:stencil_c_expr(desc, access_by_name, index, loop_scope)
        return c_window_input_expr(self, desc, access_by_name, loop_scope)
    end
    function Stencil.StencilPointConst:stencil_c_expr(desc, access_by_name, index, loop_scope)
        return c_value_const_expr(self.value, self.ty)
    end
    function Stencil.StencilPointUnary:stencil_c_expr(desc, access_by_name, index, loop_scope)
        local result_ty = assert(self.result_ty, "stencil_c: generic unary apply requires result_ty")
        local arg = c_point_expr(self.arg, desc, access_by_name, index, loop_scope)
        if self.op == Stencil.StencilUnaryIdentity then return c_cast(result_ty, arg) end
        if self.op == Stencil.StencilUnaryNeg then return c_cast(result_ty, C.cast[c_unsigned_type_node(result_ty)](0) - c_unsigned_cast(result_ty, arg)) end
        if self.op == Stencil.StencilUnaryBitNot then return c_cast(result_ty, C.bnot(c_unsigned_cast(result_ty, arg))) end
        if self.op == Stencil.StencilUnaryBoolNot then return c_cast(result_ty, C.not_(arg)) end
        error("stencil_c: unsupported generic unary apply " .. unary_name(self.op), 3)
    end
    function Stencil.StencilPointBinary:stencil_c_expr(desc, access_by_name, index, loop_scope)
        return c_binary_expr(
            self.op,
            c_point_expr(self.left, desc, access_by_name, index, loop_scope),
            c_point_expr(self.right, desc, access_by_name, index, loop_scope),
            assert(self.result_ty, "stencil_c: generic binary apply requires result_ty"),
            self.int_semantics,
            self.float_mode
        )
    end
    function Stencil.StencilPointCast:stencil_c_expr(desc, access_by_name, index, loop_scope)
        if self.op == Core.MachineCastBitcast then error("stencil_c: generic point bitcast requires a dedicated lowering", 3) end
        return c_cast(self.to, c_point_expr(self.arg, desc, access_by_name, index, loop_scope))
    end
    function Stencil.StencilPointPredicate:stencil_c_expr(desc, access_by_name, index, loop_scope)
        return c_cast(self.result_ty, c_predicate_expr(self.pred, c_point_expr(self.arg, desc, access_by_name, index, loop_scope)))
    end
    function Stencil.StencilPointCompare:stencil_c_expr(desc, access_by_name, index, loop_scope)
        return c_cast(
            self.result_ty,
            c_compare_expr(
                self.cmp,
                c_point_expr(self.left, desc, access_by_name, index, loop_scope),
                c_point_expr(self.right, desc, access_by_name, index, loop_scope)
            )
        )
    end
    function Stencil.StencilPointSelect:stencil_c_expr(desc, access_by_name, index, loop_scope)
        return c_cast(
            self.result_ty,
            C.select (c_predicate_expr(self.pred, c_point_expr(self.cond, desc, access_by_name, index, loop_scope)))(c_point_expr(self.then_expr, desc, access_by_name, index, loop_scope))(c_point_expr(self.else_expr, desc, access_by_name, index, loop_scope))
        )
    end

    c_point_expr = function(expr, desc, access_by_name, index, loop_scope)
        return expr:stencil_c_expr(desc, access_by_name, index, loop_scope)
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

    local function store_n_decl(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local producer_shape = desc.producer.shape
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
                if access.layout:stencil_c_is_scalar_layout() then
                    scalar_params[#scalar_params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
                else
                    params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
                end
            end
        end
        append_producer_param_structs(params, producer_shape)
        for i = 1, #scalar_params do params[#params + 1] = scalar_params[i] end
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local function assign_stmts(i, loop_scope)
            return {
                C.assign(
                    access_c_expr(dst_access, dst_name, i, access_by_name, loop_scope),
                    c_point_expr(shape.expr, desc, access_by_name, i, loop_scope)
                ),
            }
        end
        local function copy_input_name()
            if asdl.classof(shape.store_mode) ~= Stencil.StencilStoreCopy then return nil end
            if asdl.classof(shape.expr) ~= Stencil.StencilPointInput then return nil end
            local name = shape.expr.access.name
            if name == dst_name then return nil end
            return name
        end
        local copy_src_name = copy_input_name()
        local copy_semantics = asdl.classof(shape.store_mode) == Stencil.StencilStoreCopy and shape.store_mode.semantics or nil
        local name = LLBL.N[artifact.symbol.text]
        if copy_src_name ~= nil and producer_shape:stencil_c_is_range1d() and (copy_semantics == Stencil.StencilCopyMemMove or copy_semantics == Stencil.StencilCopyMayOverlapBackward) then
            local forward_body = producer_loop(producer_shape, assign_stmts)
            local backward_body = { reverse_loop_i(shape.stride or 1, function(i) return assign_stmts(i, stencil_loop_scope(producer_shape, i, { i })) end) }
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
            _(producer_loop(producer_shape, function(i, loop_scope)
                return assign_stmts(i, loop_scope)
            end)),
        }
    end

    local function reduce_n_decl(artifact)
        local shape = artifact_shape(artifact)
        local desc = artifact.instance.descriptor
        local producer_shape = desc.producer.shape
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
        append_producer_param_structs(params, producer_shape)
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
            local kept_axes = axis_indices(producer_shape, function(axis_index) return not reduce_axes[axis_index] end)
            local folded_axes = axis_indices(producer_shape, function(axis_index) return reduce_axes[axis_index] end)
            local function folded_body()
                local idx = range_nd_linear_index(producer_shape)
                local loop_scope = stencil_loop_scope(producer_shape, idx, current_axis_values(producer_shape))
                return {
                    C.assign(
                        cn("acc"),
                        c_reduction_update_expr(
                            shape.reduction,
                            cn("acc"),
                            c_point_expr(shape.expr, desc, access_by_name, idx, loop_scope),
                            shape.result_ty
                        )
                    ),
                }
            end
            local function outer_body()
                local out_idx = subset_linear_index(producer_shape, kept_axes)
                local body = {
                    C.decl. acc[acc_type_node](C.cast[acc_type_node](c_value_const_expr(shape.identity, shape.result_ty))),
                    _(nest_axis_loops(producer_shape, folded_axes, folded_body)),
                    C.assign(access_c_expr(dst_access, shape.dst_name, out_idx, access_by_name), c_cast(shape.result_ty, cn("acc"))),
                }
                return body
            end
            return C.fn[name] { _(param_fragment(params)) } [C.void] {
                _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
                _(nd_axis_extents(producer_shape)),
                _(nest_axis_loops(producer_shape, kept_axes, outer_body)),
            }
        end
        if shape.scope_kind == "window" then
            local reduce_axes = axis_indices(producer_shape, function(axis_index)
                local reduce = axis_set_map(shape.axes)
                return reduce[axis_index]
            end)
            local has_zero, has_reject = window_boundary_flags(producer_shape)
            local function window_update_body(offsets)
                local coords, bounds = window_coords_with_offsets(producer_shape, offsets)
                local idx = range_nd_linear_index_from_coords(producer_shape, coords)
                local loop_scope = stencil_loop_scope(producer_shape, idx, coords)
                local item = c_point_expr(shape.expr, desc, access_by_name, idx, loop_scope)
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
                _(producer_loop(producer_shape, function(i, loop_scope)
                    return {
                        C.decl. acc[acc_type_node](C.cast[acc_type_node](c_value_const_expr(shape.identity, shape.result_ty))),
                        _(nest_window_offset_loops(producer_shape, reduce_axes, window_update_body)),
                        C.assign(access_c_expr(dst_access, shape.dst_name, i, access_by_name), c_cast(shape.result_ty, cn("acc"))),
                    }
                end)),
            }
        end
        local init_value = shape.external_init == false and c_value_const_expr(shape.identity, shape.result_ty) or cn("init")
        return C.fn[name] { _(param_fragment(params)) } [C.type[result_ty]] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            C.decl. acc[acc_type_node](C.cast[acc_type_node](init_value)),
            _(producer_loop(producer_shape, function(i, loop_scope)
                return {
                    C.assign(
                        cn("acc"),
                        c_reduction_update_expr(
                            shape.reduction,
                            cn("acc"),
                            c_point_expr(shape.expr, desc, access_by_name, i, loop_scope),
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
        local producer_shape = desc.producer.shape
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
        append_producer_param_structs(params, producer_shape)
        params[#params + 1] = structured_param("init", c_type_node(shape.result_ty))
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local name = LLBL.N[artifact.symbol.text]
        if not producer_shape:stencil_c_is_range1d() then
            local scan_axis = tonumber(shape.axis.index)
            local outer_axes = axis_indices(producer_shape, function(axis_index) return axis_index ~= scan_axis end)
            local function scan_line_body()
                local i = cn("__ml_i")
                local loop_scope = stencil_loop_scope(producer_shape, i, current_axis_values(producer_shape))
                local item = c_point_expr(shape.expr, desc, access_by_name, i, loop_scope)
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
                    axis_loop_stmt(producer_shape, scan_axis, {
                        C.decl. __ml_i[C.i32](range_nd_linear_index(producer_shape)),
                        _(scan_stmts),
                    }),
                }
            end
            return C.fn[name] { _(param_fragment(params)) } [C.type[result_ty]] {
                _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
                _(nd_axis_extents(producer_shape)),
                _(nest_axis_loops(producer_shape, outer_axes, scan_line_body)),
                C.return_(c_cast(shape.result_ty, 0)),
            }
        end
        return C.fn[name] { _(param_fragment(params)) } [C.type[result_ty]] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            C.decl. acc[acc_type_node](C.cast[acc_type_node](cn("init"))),
            _(producer_loop(producer_shape, function(i, loop_scope)
                local item = c_point_expr(shape.expr, desc, access_by_name, i, loop_scope)
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
        local producer_shape = desc.producer.shape
        local dst_name = shape.dst_name or "dst"
        local dst_access = access_named(desc, dst_name)
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end
        local params = {
            structured_param(dst_name, c_access_param_type_node(dst_access, true, artifact)),
        }
        for _, access in ipairs(descriptor_accesses(desc)) do
            if access.name ~= dst_name and not access.layout:stencil_c_is_scalar_layout() then
                params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
            end
        end
        append_producer_param_structs(params, producer_shape)
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local name = LLBL.N[artifact.symbol.text]
        return C.fn[name] { _(param_fragment(params)) } [C.void] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            _(producer_loop(producer_shape, function(i, loop_scope)
                local slot = access_c_expr(dst_access, dst_name, i, access_by_name)
                return {
                    C.assign(
                        slot,
                        c_reduction_update_expr(
                            shape.reduction,
                            slot,
                            c_point_expr(shape.expr, desc, access_by_name, i, loop_scope),
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
        local producer_shape = desc.producer.shape
        local access_by_name = {}
        for _, access in ipairs(descriptor_accesses(desc)) do access_by_name[access.name] = access end
        local params = {}
        for _, access in ipairs(shape.inputs or {}) do
            params[#params + 1] = structured_param(access.name, c_access_param_type_node(access, false, artifact))
        end
        append_producer_param_structs(params, producer_shape)
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local name = LLBL.N[artifact.symbol.text]
        return C.fn[name] { _(param_fragment(params)) } [c_type_node(shape.result_ty)] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            _(producer_loop(producer_shape, function(i, loop_scope)
                return {
                    C.if_(C.ne (c_point_expr(shape.expr, desc, access_by_name, i, loop_scope))(0)) {
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
        local producer_shape = desc.producer.shape
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
        append_producer_param_structs(params, producer_shape)
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            params[#params + 1] = structured_param(stride_param_name(access), C.i32)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            params[#params + 1] = structured_param(affine_offset_param_name(access), C.i32)
        end
        local out_init = producer_shape:stencil_c_is_range1d() and cn("start") or 0
        local name = LLBL.N[artifact.symbol.text]
        return C.fn[name] { _(param_fragment(params)) } [C.i32] {
            _(assume_aligned_stmts(artifact, pointer_access_names(artifact))),
            C.decl. out[C.i32](out_init),
            _(producer_loop(producer_shape, function(i, loop_scope)
                return {
                    C.if_(C.ne (c_point_expr(shape.expr, desc, access_by_name, i, loop_scope))(0)) {
                        C.assign(access_c_expr(dst_access, dst_name, cn("out"), access_by_name), access_c_expr(src_access, "xs", i, access_by_name)),
                        C.assign(cn("out"), cn("out") + 1),
                    },
                }
            end)),
            C.decl. split[C.i32](cn("out")),
            _(producer_loop(producer_shape, function(i, loop_scope)
                return {
                    C.if_(C.eq (c_point_expr(shape.expr, desc, access_by_name, i, loop_scope))(0)) {
                        C.assign(access_c_expr(dst_access, dst_name, cn("out"), access_by_name), access_c_expr(src_access, "xs", i, access_by_name)),
                        C.assign(cn("out"), cn("out") + 1),
                    },
                }
            end)),
            C.return_(cn("split")),
        }
    end

    function Stencil.StencilDescriptor:stencil_c_artifact_decl(artifact)
        return self.sink:stencil_c_sink_decl(artifact, self)
    end

    function Stencil.StencilSink:stencil_c_sink_decl(artifact, desc)
        error("stencil_c: unsupported stencil sink", 3)
    end
    function Stencil.StencilSinkStore:stencil_c_sink_decl(artifact, desc)
        return self.semantics:stencil_c_store_decl(artifact, self, desc)
    end
    function Stencil.StencilSinkReduce:stencil_c_sink_decl(artifact, desc)
        return self.semantics:stencil_c_reduce_decl(artifact, self, desc)
    end
    function Stencil.StencilSinkScan:stencil_c_sink_decl(artifact, desc)
        return scan_n_decl(artifact)
    end
    function Stencil.StencilSinkScatterReduce:stencil_c_sink_decl(artifact, desc)
        return scatter_reduce_n_decl(artifact)
    end

    function Stencil.StencilStoreSemantics:stencil_c_store_decl(artifact, sink, desc)
        return store_n_decl(artifact)
    end
    function Stencil.StencilStorePartition:stencil_c_store_decl(artifact, sink, desc)
        return partition_n_decl(artifact)
    end

    function Stencil.StencilReductionSemantics:stencil_c_reduce_decl(artifact, sink, desc)
        error("stencil_c: unsupported reduce sink semantics", 3)
    end
    function Stencil.StencilReduceFold:stencil_c_reduce_decl(artifact, sink, desc)
        return reduce_n_decl(artifact)
    end
    function Stencil.StencilReduceCount:stencil_c_reduce_decl(artifact, sink, desc)
        return reduce_n_decl(artifact)
    end
    function Stencil.StencilReduceFind:stencil_c_reduce_decl(artifact, sink, desc)
        return find_n_decl(artifact)
    end

    local function artifact_decl(artifact)
        return artifact.instance.descriptor:stencil_c_artifact_decl(artifact)
    end

    function api.source(artifacts, opts)
        opts = opts or {}
        local decls = {}
        if opts.omit_preamble ~= true then
            decls[#decls + 1] = C.include "stdint.h"
            decls[#decls + 1] = C.include "stddef.h"
            decls[#decls + 1] = C.include "string.h"
            decls[#decls + 1] = C.include "math.h"
            decls[#decls + 1] = C.typedef. ml_index [C.intptr_t]
        end
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
