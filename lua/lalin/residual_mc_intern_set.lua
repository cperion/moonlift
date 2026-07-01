local function bind_context(T)
    local Code = T.LalinCode
    local Core = T.LalinCore
    local Stencil = T.LalinStencil
    local Residual = T.LalinResidual
    local Ty = T.LalinType
    local Value = T.LalinValue
    local ReductionAlgebra = require("lalin.reduction_algebra")(T)
    require("lalin.residual_native")(T)

    local M = {}

    local i32 = Code.CodeTyInt(32, Code.CodeSigned)
    local u32 = Code.CodeTyInt(32, Code.CodeUnsigned)
    local i64 = Code.CodeTyInt(64, Code.CodeSigned)
    local f32 = Code.CodeTyFloat(32)
    local f64 = Code.CodeTyFloat(64)
    local bool8 = Code.CodeTyBool8
    local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
    local pair_soa_ty = Code.CodeTyNamed("Demo", "PairSoA", Ty.TNamed(Ty.TypeRefGlobal("Demo", "PairSoA")))
    local int_semantics = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftTrapOutOfRange)

    local scalar_seeds = {
        Residual.StencilTemplateScalarSeed("i32", i32, true, true, true, false),
        Residual.StencilTemplateScalarSeed("u32", u32, true, true, false, false),
        Residual.StencilTemplateScalarSeed("i64", i64, true, true, true, false),
        Residual.StencilTemplateScalarSeed("f32", f32, true, false, true, true),
        Residual.StencilTemplateScalarSeed("f64", f64, true, false, true, true),
        Residual.StencilTemplateScalarSeed("bool8", bool8, false, true, false, false),
    }

    local function ty_label(ty)
        return ty:patch_template_key()
    end

    local function lit_for_ty(ty, raw)
        for _, seed in ipairs(scalar_seeds) do
            if seed.ty == ty then return seed:literal(raw) end
        end
        return Core.LitInt(tostring(raw))
    end

    local function const_expr(ty, raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(ty, lit_for_ty(ty, raw)))
    end

    local function default_compiler_policy()
        return Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, Stencil.StencilMachineNative, {})
    end

    local function default_vectorization_facts()
        return Stencil.StencilVectorizationFacts(
            {},
            {},
            Stencil.StencilTripCountDynamic,
            Stencil.StencilArithmeticVectorFact(false, nil, nil),
            {}
        )
    end

    local function axis()
        return Stencil.StencilProducerAxis(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward)
    end

    local function axes(rank)
        local out = {}
        for _ = 1, rank do out[#out + 1] = axis() end
        return out
    end

    local function windows(rank, radius, boundary)
        local out = {}
        for _ = 1, rank do out[#out + 1] = Stencil.StencilWindowAxis(radius, radius, boundary) end
        return out
    end

    local function tile_sizes(rank, tile_size)
        local out = {}
        for _ = 1, rank do out[#out + 1] = tile_size end
        return out
    end

    local function reducer(op, ty)
        local identity, reason = ReductionAlgebra.identity_expr(op, ty)
        assert(identity ~= nil, "residual_mc_intern_set: reduction identity missing: " .. tostring(reason))
        return Stencil.StencilReducer(op, ty, identity, int_semantics, nil)
    end

    local function access(name, role, ty, layout)
        return Stencil.StencilAccess(name, role, ty, layout)
    end

    local function input_accesses(seed)
        local out = {}
        for i = 1, seed.input_count do
            local name = "x" .. tostring(i)
            out[#out + 1] = access(name, Stencil.StencilAccessRead, seed:template_result_ty(), seed.layout:input_layout(name))
        end
        return out
    end

    local function append_inputs(out, seed)
        local inputs = input_accesses(seed)
        for i = 1, #inputs do out[#out + 1] = inputs[i] end
        seed.layout:append_extra_accesses(out, seed)
        return out
    end

    local function coroutine_triplet_gen(thread, state)
        local ok, value = coroutine.resume(thread)
        if not ok then error(value, 2) end
        if value == nil then return nil end
        return state + 1, value
    end

    function Stencil.StencilUnaryIdentity:template_label() return "identity" end
    function Stencil.StencilUnaryNeg:template_label() return "neg" end
    function Stencil.StencilUnaryBitNot:template_label() return "bitnot" end
    function Stencil.StencilUnaryBoolNot:template_label() return "boolnot" end

    function Stencil.StencilBinaryAdd:template_label() return "add" end
    function Stencil.StencilBinarySub:template_label() return "sub" end
    function Stencil.StencilBinaryMul:template_label() return "mul" end
    function Stencil.StencilBinaryDiv:template_label() return "div" end
    function Stencil.StencilBinaryMod:template_label() return "mod" end
    function Stencil.StencilBinaryAnd:template_label() return "and" end
    function Stencil.StencilBinaryOr:template_label() return "or" end
    function Stencil.StencilBinaryXor:template_label() return "xor" end
    function Stencil.StencilBinaryShl:template_label() return "shl" end
    function Stencil.StencilBinaryLShr:template_label() return "lshr" end
    function Stencil.StencilBinaryAShr:template_label() return "ashr" end
    function Stencil.StencilBinaryMin:template_label() return "min" end
    function Stencil.StencilBinaryMax:template_label() return "max" end

    function Core.CmpEq:template_label() return "eq" end
    function Core.CmpNe:template_label() return "ne" end
    function Core.CmpLt:template_label() return "lt" end
    function Core.CmpLe:template_label() return "le" end
    function Core.CmpGt:template_label() return "gt" end
    function Core.CmpGe:template_label() return "ge" end

    function Value.ReductionAdd:template_label() return "add" end
    function Value.ReductionMul:template_label() return "mul" end
    function Value.ReductionMin:template_label() return "min" end
    function Value.ReductionMax:template_label() return "max" end
    function Value.ReductionAnd:template_label() return "and" end
    function Value.ReductionOr:template_label() return "or" end
    function Value.ReductionXor:template_label() return "xor" end

    function Value.ReductionAdd:template_supports_scalar(scalar) return scalar.numeric == true end
    function Value.ReductionMul:template_supports_scalar(scalar) return scalar.numeric == true end
    function Value.ReductionMin:template_supports_scalar(scalar) return scalar.numeric == true end
    function Value.ReductionMax:template_supports_scalar(scalar) return scalar.numeric == true end
    function Value.ReductionAnd:template_supports_scalar(scalar) return scalar.bitwise == true end
    function Value.ReductionOr:template_supports_scalar(scalar) return scalar.bitwise == true end
    function Value.ReductionXor:template_supports_scalar(scalar) return scalar.bitwise == true end

    function Residual.StencilTemplateScalarSeed:literal(raw)
        if self.label == "bool8" then
            return Core.LitBool(raw == true or raw == 1)
        end
        if self.floating then return Core.LitFloat(tostring(raw)) end
        return Core.LitInt(tostring(raw))
    end

    function Residual.StencilTemplateProducerSeed:template_label()
        return self:patch_template_key()
    end

    function Residual.StencilTemplateProducerRange1D:template_producer()
        return Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward))
    end

    function Residual.StencilTemplateProducerRange1D:template_label()
        return "range1d"
    end

    function Residual.StencilTemplateProducerRangeND:template_producer()
        return Stencil.StencilProducer(nil, Stencil.StencilProduceRangeND(axes(self.rank)))
    end

    function Residual.StencilTemplateProducerRangeND:template_label()
        return "range_nd" .. tostring(self.rank)
    end

    function Residual.StencilTemplateProducerTiledND:template_producer()
        return Stencil.StencilProducer(nil, Stencil.StencilProduceTiledND(axes(self.rank), tile_sizes(self.rank, self.tile_size)))
    end

    function Residual.StencilTemplateProducerTiledND:template_label()
        return "tiled_nd" .. tostring(self.rank) .. "_t" .. tostring(self.tile_size)
    end

    function Residual.StencilTemplateProducerWindowND:template_producer()
        return Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND(axes(self.rank), windows(self.rank, self.radius, self.boundary)))
    end

    function Residual.StencilTemplateProducerWindowND:template_label()
        return "window_nd" .. tostring(self.rank) .. "_r" .. tostring(self.radius)
    end

    function Residual.StencilTemplateLayoutSeed:dst_layout()
        return self:input_layout("dst")
    end

    function Residual.StencilTemplateLayoutSeed:append_extra_accesses(_out, _seed)
    end

    function Residual.StencilTemplateLayoutContiguous:input_layout(_name)
        return Stencil.StencilLayoutContiguous(1)
    end

    function Residual.StencilTemplateLayoutContiguous:template_label()
        return "contiguous"
    end

    function Residual.StencilTemplateLayoutAffine1D:input_layout(_name)
        return Stencil.StencilLayoutAffine1D(Stencil.StencilLayoutContiguous(1), self.scale, nil)
    end

    function Residual.StencilTemplateLayoutAffine1D:template_label()
        return "affine1d_s" .. tostring(self.scale)
    end

    function Residual.StencilTemplateLayoutView:input_layout(name)
        return Stencil.StencilLayoutViewDescriptor(
            Code.CodeValueId("v:view:" .. tostring(name)),
            Code.CodeValueId("v:data:" .. tostring(name)),
            Code.CodeValueId("v:len:" .. tostring(name)),
            Code.CodeValueId("v:stride:" .. tostring(name)),
            nil
        )
    end

    function Residual.StencilTemplateLayoutView:template_label()
        return "view"
    end

    function Residual.StencilTemplateLayoutSlice:input_layout(name)
        return Stencil.StencilLayoutSliceDescriptor(
            Code.CodeValueId("v:slice:" .. tostring(name)),
            Code.CodeValueId("v:data:" .. tostring(name)),
            Code.CodeValueId("v:len:" .. tostring(name))
        )
    end

    function Residual.StencilTemplateLayoutSlice:template_label()
        return "slice"
    end

    function Residual.StencilTemplateLayoutByteSpan:input_layout(name)
        return Stencil.StencilLayoutByteSpanDescriptor(
            Code.CodeValueId("v:bytespan:" .. tostring(name)),
            Code.CodeValueId("v:data:" .. tostring(name)),
            Code.CodeValueId("v:len:" .. tostring(name))
        )
    end

    function Residual.StencilTemplateLayoutByteSpan:template_label()
        return "bytespan"
    end

    function Residual.StencilTemplateLayoutFieldProjection:input_layout(_name)
        return Stencil.StencilLayoutFieldProjection(
            Stencil.StencilLayoutContiguous(1),
            self.record_ty,
            self.field_name,
            self.field_offset
        )
    end

    function Residual.StencilTemplateLayoutFieldProjection:template_label()
        return "field_" .. tostring(self.field_name)
    end

    function Residual.StencilTemplateLayoutSoAComponent:input_layout(_name)
        return Stencil.StencilLayoutSoAComponent(
            Stencil.StencilLayoutContiguous(1),
            self.record_ty,
            self.field_name,
            self.component_index
        )
    end

    function Residual.StencilTemplateLayoutSoAComponent:template_label()
        return "soa_" .. tostring(self.field_name) .. "_" .. tostring(self.component_index)
    end

    function Residual.StencilTemplateLayoutIndexed:input_layout(name)
        return Stencil.StencilLayoutIndexed(
            Stencil.StencilLayoutContiguous(1),
            Stencil.StencilAccessRef("idx_" .. tostring(name)),
            self.index_ty,
            self.stride
        )
    end

    function Residual.StencilTemplateLayoutIndexed:append_extra_accesses(out, seed)
        for i = 1, seed.input_count do
            out[#out + 1] = access("idx_x" .. tostring(i), Stencil.StencilAccessIndex, self.index_ty, Stencil.StencilLayoutContiguous(1))
        end
    end

    function Residual.StencilTemplateLayoutIndexed:template_label()
        return "indexed_s" .. tostring(self.stride)
    end

    function Residual.StencilTemplateLayoutScalar:input_layout(_name)
        return Stencil.StencilLayoutScalar(nil)
    end

    function Residual.StencilTemplateLayoutScalar:dst_layout()
        return Stencil.StencilLayoutContiguous(1)
    end

    function Residual.StencilTemplateLayoutScalar:template_label()
        return "scalar"
    end

    function Residual.StencilTemplatePointInput:template_point_expr()
        return Stencil.StencilPointInput(Stencil.StencilAccessRef("x" .. tostring(self.input_index)))
    end

    function Residual.StencilTemplatePointInput:template_label()
        return "x" .. tostring(self.input_index)
    end

    function Residual.StencilTemplatePointConst:template_point_expr()
        return Stencil.StencilPointConst(const_expr(self.ty, 0), self.ty)
    end

    function Residual.StencilTemplatePointConst:template_label()
        return "c0"
    end

    function Residual.StencilTemplatePointUnary:template_point_expr()
        return Stencil.StencilPointUnary(self.op, self.arg:template_point_expr(), self.result_ty, int_semantics, nil)
    end

    function Residual.StencilTemplatePointUnary:template_label()
        return "unary_" .. self.op:template_label() .. "_" .. self.arg:template_label()
    end

    function Residual.StencilTemplatePointBinary:template_point_expr()
        return Stencil.StencilPointBinary(self.op, self.left:template_point_expr(), self.right:template_point_expr(), self.result_ty, int_semantics, nil)
    end

    function Residual.StencilTemplatePointBinary:template_label()
        return "binary_" .. self.op:template_label() .. "_" .. self.left:template_label() .. "_" .. self.right:template_label()
    end

    function Residual.StencilTemplatePointCompare:template_point_expr()
        return Stencil.StencilPointCompare(self.cmp, self.left:template_point_expr(), self.right:template_point_expr(), self.result_ty)
    end

    function Residual.StencilTemplatePointCompare:template_label()
        return "cmp_" .. self.cmp:template_label() .. "_" .. self.left:template_label() .. "_" .. self.right:template_label()
    end

    function Residual.StencilTemplatePointSelect:template_point_expr()
        return Stencil.StencilPointSelect(
            Stencil.StencilPredNonZero,
            self.cond:template_point_expr(),
            self.then_expr:template_point_expr(),
            self.else_expr:template_point_expr(),
            self.result_ty
        )
    end

    function Residual.StencilTemplatePointSelect:template_label()
        return "select_" .. self.cond:template_label() .. "_" .. self.then_expr:template_label() .. "_" .. self.else_expr:template_label()
    end

    function Residual.StencilTemplateSinkStoreN:template_sink_descriptor(seed)
        local result_ty = seed:template_result_ty()
        local accesses = {
            access("dst", Stencil.StencilAccessWrite, result_ty, seed.layout:dst_layout()),
        }
        append_inputs(accesses, seed)
        return Stencil.StencilDescriptor(
            seed.producer:template_producer(),
            accesses,
            Stencil.StencilBodyPoint(seed.point:template_point_expr()),
            Stencil.StencilSinkStore(Stencil.StencilAccessRef("dst"), Stencil.StencilStoreElementwise)
        )
    end

    function Residual.StencilTemplateSinkStoreN:template_label()
        return "store_n"
    end

    function Residual.StencilTemplateSinkReduceN:template_sink_descriptor(seed)
        local result_ty = seed:template_result_ty()
        local accesses = {}
        append_inputs(accesses, seed)
        accesses[#accesses + 1] = access("acc", Stencil.StencilAccessReduce, result_ty, Stencil.StencilLayoutScalar(const_expr(result_ty, 0)))
        return Stencil.StencilDescriptor(
            seed.producer:template_producer(),
            accesses,
            Stencil.StencilBodyPoint(seed.point:template_point_expr()),
            Stencil.StencilSinkReduce(result_ty, Stencil.StencilReduceScopeDomain, Stencil.StencilReduceFold(reducer(self.op, result_ty)))
        )
    end

    function Residual.StencilTemplateSinkReduceN:template_label()
        return "reduce_n_" .. self.op:template_label()
    end

    function Residual.StencilTemplateSinkScanN:template_sink_descriptor(seed)
        local result_ty = seed:template_result_ty()
        local accesses = {
            access("dst", Stencil.StencilAccessWrite, result_ty, seed.layout:dst_layout()),
        }
        append_inputs(accesses, seed)
        accesses[#accesses + 1] = access("acc", Stencil.StencilAccessReduce, result_ty, Stencil.StencilLayoutScalar(const_expr(result_ty, 0)))
        return Stencil.StencilDescriptor(
            seed.producer:template_producer(),
            accesses,
            Stencil.StencilBodyPoint(seed.point:template_point_expr()),
            Stencil.StencilSinkScan(Stencil.StencilAccessRef("dst"), Stencil.StencilAxisRef(1), reducer(self.op, result_ty), Stencil.StencilScanInclusive, result_ty)
        )
    end

    function Residual.StencilTemplateSinkScanN:template_label()
        return "scan_n_" .. self.op:template_label()
    end

    function Residual.StencilTemplateSinkScatterReduceN:template_sink_descriptor(seed)
        local result_ty = seed:template_result_ty()
        local accesses = {
            access(
                "dst",
                Stencil.StencilAccessReadWrite,
                result_ty,
                Stencil.StencilLayoutIndexed(Stencil.StencilLayoutContiguous(1), Stencil.StencilAccessRef("idx_dst"), i32, 1)
            ),
            access("idx_dst", Stencil.StencilAccessIndex, i32, Stencil.StencilLayoutContiguous(1)),
        }
        append_inputs(accesses, seed)
        return Stencil.StencilDescriptor(
            seed.producer:template_producer(),
            accesses,
            Stencil.StencilBodyPoint(seed.point:template_point_expr()),
            Stencil.StencilSinkScatterReduce(Stencil.StencilAccessRef("dst"), reducer(self.op, result_ty), Stencil.StencilScatterReduceSequential, result_ty)
        )
    end

    function Residual.StencilTemplateSinkScatterReduceN:template_label()
        return "scatter_reduce_n_" .. self.op:template_label()
    end

    function Residual.StencilTemplateScheduleScalar:template_schedule()
        return Stencil.StencilScheduleScalar(default_compiler_policy())
    end

    function Residual.StencilTemplateScheduleScalar:template_label()
        return "scalar"
    end

    function Residual.StencilTemplateScheduleVector:template_schedule()
        return Stencil.StencilScheduleVector(
            Stencil.StencilVectorFeatureNative,
            Stencil.StencilLaneFixed(self.lanes),
            Stencil.StencilVectorUnaligned,
            Stencil.StencilVectorScalarTail,
            Stencil.StencilVectorReductionScalarFinish,
            Stencil.StencilVectorCompilerGccAutovec,
            1,
            1,
            default_compiler_policy(),
            default_vectorization_facts()
        )
    end

    function Residual.StencilTemplateScheduleVector:template_label()
        return "v" .. tostring(self.lanes)
    end

    function Residual.StencilTemplateSeed:template_label()
        return table.concat({
            self.producer:template_label(),
            self.layout:template_label(),
            self.sink:template_label(),
            "in" .. tostring(self.input_count),
            "ty" .. ty_label(self:template_result_ty()),
            self.point:template_label(),
            self.schedule:template_label(),
        }, ".")
    end

    function Residual.StencilTemplateSeed:template_result_ty()
        return self.scalar.ty
    end

    function Residual.StencilTemplateSeed:template_instance()
        local descriptor = self.sink:template_sink_descriptor(self)
        return Stencil.StencilInstance(
            Stencil.StencilInstanceId("patch-template:" .. self:template_label()),
            descriptor,
            self.schedule:template_schedule(),
            Stencil.StencilAbi(descriptor:template_abi_params(self), self:template_result_ty()),
            {}
        )
    end

    function Stencil.StencilDescriptor:template_abi_params(_seed)
        local params = {}
        for _, item in ipairs(self.accesses or {}) do
            params[#params + 1] = item.ty
        end
        params[#params + 1] = Code.CodeTyIndex
        params[#params + 1] = Code.CodeTyIndex
        params[#params + 1] = Code.CodeTyIndex
        return params
    end

    function Residual.StencilTemplateSeed:template_entry()
        local instance = self:template_instance()
        local selection = instance:select_patch_template()
        return Residual.StencilPatchTemplateEntry(
            selection,
            selection.family,
            instance,
            self:estimated_template_bytes(),
            #(selection.coordinates or {})
        )
    end

    function Residual.StencilTemplateSeed:estimated_template_bytes()
        return 256 + (self.input_count * 32) + (#(self:template_instance().descriptor.accesses or {}) * 24)
    end

    local function producer_seeds()
        return {
            Residual.StencilTemplateProducerRange1D,
            Residual.StencilTemplateProducerRangeND(2),
            Residual.StencilTemplateProducerRangeND(3),
            Residual.StencilTemplateProducerTiledND(2, 2),
            Residual.StencilTemplateProducerTiledND(3, 2),
            Residual.StencilTemplateProducerWindowND(1, 1, Stencil.StencilWindowBoundaryClamp),
            Residual.StencilTemplateProducerWindowND(2, 1, Stencil.StencilWindowBoundaryClamp),
        }
    end

    local function layout_seeds()
        return {
            Residual.StencilTemplateLayoutContiguous,
            Residual.StencilTemplateLayoutAffine1D(-1),
            Residual.StencilTemplateLayoutView,
            Residual.StencilTemplateLayoutSlice,
            Residual.StencilTemplateLayoutByteSpan,
            Residual.StencilTemplateLayoutFieldProjection(pair_ty, "right", 4),
            Residual.StencilTemplateLayoutSoAComponent(pair_soa_ty, "right", 1),
            Residual.StencilTemplateLayoutIndexed(i32, 1),
            Residual.StencilTemplateLayoutScalar,
        }
    end

    local function reduction_seeds()
        return {
            Value.ReductionAdd,
            Value.ReductionMul,
            Value.ReductionMin,
            Value.ReductionMax,
            Value.ReductionAnd,
            Value.ReductionOr,
            Value.ReductionXor,
        }
    end

    local function sink_seeds(scalar)
        local out = { Residual.StencilTemplateSinkStoreN }
        for _, op in ipairs(reduction_seeds()) do
            if op:template_supports_scalar(scalar) then
                out[#out + 1] = Residual.StencilTemplateSinkReduceN(op)
                out[#out + 1] = Residual.StencilTemplateSinkScanN(op)
                out[#out + 1] = Residual.StencilTemplateSinkScatterReduceN(op)
            end
        end
        return out
    end

    local function schedule_seeds()
        return {
            Residual.StencilTemplateScheduleScalar,
            Residual.StencilTemplateScheduleVector(4),
        }
    end

    local function point_seeds(input_count, scalar)
        local ty = scalar.ty
        local out = {}
        for i = 1, input_count do out[#out + 1] = Residual.StencilTemplatePointInput(i, ty) end
        out[#out + 1] = Residual.StencilTemplatePointConst(ty)
        for i = 1, input_count do
            local x = Residual.StencilTemplatePointInput(i, ty)
            if scalar.numeric == true then out[#out + 1] = Residual.StencilTemplatePointUnary(Stencil.StencilUnaryNeg, x, ty) end
            out[#out + 1] = Residual.StencilTemplatePointUnary(Stencil.StencilUnaryIdentity, x, ty)
        end
        if input_count >= 2 then
            local x1 = Residual.StencilTemplatePointInput(1, ty)
            local x2 = Residual.StencilTemplatePointInput(2, ty)
            if scalar.numeric == true then
                out[#out + 1] = Residual.StencilTemplatePointBinary(Stencil.StencilBinaryAdd, x1, x2, ty)
                out[#out + 1] = Residual.StencilTemplatePointBinary(Stencil.StencilBinarySub, x1, x2, ty)
                out[#out + 1] = Residual.StencilTemplatePointBinary(Stencil.StencilBinaryMul, x1, x2, ty)
            end
            if scalar.bitwise == true then
                out[#out + 1] = Residual.StencilTemplatePointBinary(Stencil.StencilBinaryAnd, x1, x2, ty)
                out[#out + 1] = Residual.StencilTemplatePointBinary(Stencil.StencilBinaryOr, x1, x2, ty)
                out[#out + 1] = Residual.StencilTemplatePointBinary(Stencil.StencilBinaryXor, x1, x2, ty)
            end
            out[#out + 1] = Residual.StencilTemplatePointCompare(Core.CmpLt, x1, x2, bool8)
            out[#out + 1] = Residual.StencilTemplatePointSelect(x1, x1, x2, ty)
        end
        return out
    end

    function Residual.StencilTemplateUnbounded:template_limit_reached(_emitted)
        return false
    end

    function Residual.StencilTemplateLimited:template_limit_reached(emitted)
        return emitted >= self.count
    end

    function Residual.StencilTemplateUnsharded:template_shard_accepts(_ordinal)
        return true
    end

    function Residual.StencilTemplateShardSlice:template_shard_accepts(ordinal)
        return ((ordinal - 1) % self.count) + 1 == self.index
    end

    function Residual.StencilTemplateBankRequest:template_seed_triplet()
        local thread = coroutine.create(function()
            local ordinal = 0
            local emitted = 0
            for _, producer in ipairs(producer_seeds()) do
                for _, layout in ipairs(layout_seeds()) do
                    for _, scalar in ipairs(scalar_seeds) do
                        for input_count = 1, self.input_count_max do
                            for _, point in ipairs(point_seeds(input_count, scalar)) do
                                for _, sink in ipairs(sink_seeds(scalar)) do
                                    for _, schedule in ipairs(schedule_seeds()) do
                                        ordinal = ordinal + 1
                                        if self.shard:template_shard_accepts(ordinal) then
                                            coroutine.yield(Residual.StencilTemplateSeed(producer, layout, point, sink, schedule, input_count, scalar))
                                            emitted = emitted + 1
                                            if self.limit:template_limit_reached(emitted) then return end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        return coroutine_triplet_gen, thread, 0
    end

    function Residual.StencilTemplateBankRequest:template_entry_triplet()
        local thread = coroutine.create(function()
            local g, p, s = self:template_seed_triplet()
            while true do
                local seed
                s, seed = g(p, s)
                if s == nil then break end
                coroutine.yield(seed:template_entry())
            end
        end)
        return coroutine_triplet_gen, thread, 0
    end

    function Residual.StencilTemplateBankRequest:template_batch_triplet()
        local thread = coroutine.create(function()
            local batch = {}
            local batch_index = 0
            local function flush()
                if #batch == 0 then return end
                batch_index = batch_index + 1
                coroutine.yield(Residual.StencilPatchTemplateBatch(batch_index, batch))
                batch = {}
            end
            local g, p, s = self:template_entry_triplet()
            while true do
                local entry
                s, entry = g(p, s)
                if s == nil then break end
                batch[#batch + 1] = entry
                if #batch >= self.batch_size then flush() end
            end
            flush()
        end)
        return coroutine_triplet_gen, thread, 0
    end

    function Residual.StencilTemplateBankRequest:template_bank()
        local entries = {}
        local estimated = 0
        local coordinates = 0
        local g, p, s = self:template_entry_triplet()
        while true do
            local entry
            s, entry = g(p, s)
            if s == nil then break end
            entries[#entries + 1] = entry
            estimated = estimated + entry.estimated_template_bytes
            coordinates = coordinates + entry.coordinate_count
        end
        return Residual.StencilPatchTemplateBank(entries, #entries, estimated, coordinates)
    end

    function Residual.StencilTemplateBankRequest:each_template_entry(emit)
        emit = assert(emit, "residual_mc_intern_set.each_template_entry requires an emit callback")
        local g, p, s = self:template_entry_triplet()
        while true do
            local entry
            s, entry = g(p, s)
            if s == nil then break end
            if emit(entry) == false then return false end
        end
        return true
    end

    function M.request(opts)
        opts = opts or {}
        local max_templates = tonumber(opts.max_templates or os.getenv("LALIN_MC_BANK_MAX_TEMPLATES") or "")
        local limit = max_templates ~= nil and max_templates > 0
            and Residual.StencilTemplateLimited(max_templates)
            or Residual.StencilTemplateUnbounded
        local input_count_max = tonumber(opts.input_count_max or os.getenv("LALIN_MC_BANK_INPUT_MAX") or "") or 3
        local batch_size = tonumber(opts.batch_size or os.getenv("LALIN_MC_BANK_BATCH_SIZE") or "") or 1024
        local shard_count = tonumber(opts.shard_count or os.getenv("LALIN_MC_BANK_SHARD_COUNT") or "")
        local shard_index = tonumber(opts.shard_index or os.getenv("LALIN_MC_BANK_SHARD_INDEX") or "")
        local shard = Residual.StencilTemplateUnsharded
        if shard_count ~= nil or shard_index ~= nil then
            assert(shard_count ~= nil and shard_count >= 1, "residual_mc_intern_set: shard_count must be >= 1")
            assert(shard_index ~= nil and shard_index >= 1 and shard_index <= shard_count, "residual_mc_intern_set: shard_index must be in 1..shard_count")
            shard = Residual.StencilTemplateShardSlice(shard_index, shard_count)
        end
        if input_count_max < 1 then input_count_max = 1 end
        if batch_size < 1 then batch_size = 1 end
        return Residual.StencilTemplateBankRequest(limit, math.floor(input_count_max), math.floor(batch_size), shard)
    end

    function M.template_seed_triplet(request)
        return assert(request, "residual_mc_intern_set.template_seed_triplet requires a StencilTemplateBankRequest"):template_seed_triplet()
    end

    function M.template_entry_triplet(request)
        return assert(request, "residual_mc_intern_set.template_entry_triplet requires a StencilTemplateBankRequest"):template_entry_triplet()
    end

    function M.template_batch_triplet(request)
        return assert(request, "residual_mc_intern_set.template_batch_triplet requires a StencilTemplateBankRequest"):template_batch_triplet()
    end

    function M.template_bank(request)
        return assert(request, "residual_mc_intern_set.template_bank requires a StencilTemplateBankRequest"):template_bank()
    end

    function M.c_decls()
        local C = require("llbl.c")
        local LLBL = require("llbl")
        return {
            C.typedef_struct [LLBL.N.Demo_Pair] {
                LLBL.N.left [C.i32],
                LLBL.N.right [C.i32],
            },
        }
    end

    function M.ffi_preamble()
        return "typedef struct { int32_t left; int32_t right; } Demo_Pair;"
    end

    return M
end

return bind_context
