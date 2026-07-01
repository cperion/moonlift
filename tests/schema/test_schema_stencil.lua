package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Graph = T.LalinGraph
local Value = T.LalinValue
local Kernel = T.LalinKernel
local Ty = T.LalinType
local Stencil = T.LalinStencil
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local loop = Graph.GraphLoopId("loop:sum")
local domain = Flow.FlowDomainLoop(loop)
local init = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
local reduction = Value.ReductionFact(
    Value.AlgebraFactId("reduction:sum"),
    domain,
    Code.CodeValueId("v:acc"),
    Value.ReductionAdd,
    init,
    Value.ValueExprValue(Code.CodeValueId("v:item")),
    i32,
    sem,
    nil,
    Value.AlgebraProofFlow(domain, "test reduction")
)
local proof = Kernel.KernelProofValue(reduction.proof, "test proof")
local compiler = Stencil.StencilCompilerPolicy(
    Stencil.StencilCompilerGcc,
    Stencil.StencilOptO3,
    Stencil.StencilMachineNative,
    { "-fno-builtin" }
)
local vector_facts = Stencil.StencilVectorizationFacts(
    {
        Stencil.StencilAccessVectorFact(
            Stencil.StencilAccessRef("xs"),
            Stencil.StencilAlignmentKnown(4),
            true,
            true
        ),
        Stencil.StencilAccessVectorFact(
            Stencil.StencilAccessRef("acc"),
            Stencil.StencilAlignmentUnknown,
            false,
            false
        ),
    },
    {
        Stencil.StencilAccessAliasFact(
            Stencil.StencilAccessRef("xs"),
            Stencil.StencilAccessRef("acc"),
            Stencil.StencilAliasNoAlias
        ),
    },
    Stencil.StencilTripCountDynamic,
    Stencil.StencilArithmeticVectorFact(true, sem, nil),
    {
        Stencil.StencilProofObligation(
            Stencil.StencilProofUnitStride(Stencil.StencilAccessRef("xs")),
            Stencil.StencilProofCheckerDerived,
            nil
        ),
        Stencil.StencilProofObligation(
            Stencil.StencilProofAlignment(Stencil.StencilAccessRef("xs"), Stencil.StencilAlignmentKnown(4)),
            Stencil.StencilProofBoundaryContract,
            nil
        ),
        Stencil.StencilProofObligation(
            Stencil.StencilProofNoAlias(Stencil.StencilAccessRef("xs"), Stencil.StencilAccessRef("acc")),
            Stencil.StencilProofAuthorAsserted,
            nil
        ),
        Stencil.StencilProofObligation(
            Stencil.StencilProofReductionReassociable,
            Stencil.StencilProofCheckerDerived,
            proof
        ),
    }
)
local schedule = Stencil.StencilScheduleAutoVector(compiler, vector_facts)
local producer = Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward))
local descriptor = Stencil.StencilDescriptor(
    producer,
    {
        Stencil.StencilAccess(
            "xs",
            Stencil.StencilAccessRead,
            i32,
            Stencil.StencilLayoutContiguous(1)
        ),
        Stencil.StencilAccess(
            "acc",
            Stencil.StencilAccessReduce,
            i32,
            Stencil.StencilLayoutScalar(init)
        ),
    },
    Stencil.StencilBodyPoint(Stencil.StencilPointInput(Stencil.StencilAccessRef("xs"))),
    Stencil.StencilSinkReduce(i32, Stencil.StencilReduceScopeDomain, Stencil.StencilReduceFold(Stencil.StencilReducer(Value.ReductionAdd, i32, init, sem, nil)))
)
local instance = Stencil.StencilInstance(
    Stencil.StencilInstanceId("stencil:reduce_array:i32:add"),
    descriptor,
    schedule,
    Stencil.StencilAbi({ Code.CodeTyDataPtr(i32), i32, i32, i32 }, i32),
    { proof }
)
local artifact = Stencil.StencilArtifact(
    instance,
    Stencil.StencilProviderC,
    Stencil.StencilSymbolId("ml_stencil_reduce_array_i32_add_s1"),
    "int32_t ml_stencil_reduce_array_i32_add_s1(const int32_t *, int32_t, int32_t, int32_t);",
    Stencil.StencilArtifactFingerprint("test:fingerprint"),
    nil,
    {},
    {}
)

assert(StencilArtifactPlan.descriptor_vocab(instance.descriptor) == Stencil.StencilReduce)
assert(asdl.classof(StencilArtifactPlan.descriptor_producer(instance.descriptor).shape) == Stencil.StencilProduceRange1D)
assert(StencilArtifactPlan.descriptor_accesses(instance.descriptor)[1].role == Stencil.StencilAccessRead)
assert(StencilArtifactPlan.descriptor_accesses(instance.descriptor)[2].role == Stencil.StencilAccessReduce)
assert(asdl.classof(instance.descriptor.body) == Stencil.StencilBodyPoint)
assert(asdl.classof(instance.descriptor.sink.semantics) == Stencil.StencilReduceFold)
assert(instance.descriptor.sink.scope == Stencil.StencilReduceScopeDomain)
assert(asdl.classof(instance.descriptor.sink.semantics.reducer) == Stencil.StencilReducer)
assert(instance.descriptor.sink.semantics.reducer.identity == init)
assert(asdl.classof(instance.schedule) == Stencil.StencilScheduleAutoVector)
assert(instance.schedule.compiler.compiler == Stencil.StencilCompilerGcc)
assert(instance.schedule.compiler.opt_level == Stencil.StencilOptO3)
assert(instance.schedule.compiler.machine == Stencil.StencilMachineNative)
assert(instance.schedule.facts.access_facts[1].access.name == "xs")
assert(instance.schedule.facts.alias_facts[1].left.name == "xs")
assert(instance.schedule.facts.alias_facts[1].right.name == "acc")
assert(instance.schedule.facts.alias_facts[1].relation == Stencil.StencilAliasNoAlias)
assert(asdl.classof(instance.schedule.facts.access_facts[1].alignment) == Stencil.StencilAlignmentKnown)
assert(instance.schedule.facts.arithmetic.int_semantics == sem)
assert(#instance.schedule.facts.proof_obligations == 4)
assert(asdl.classof(instance.schedule.facts.proof_obligations[1].requirement) == Stencil.StencilProofUnitStride)
assert(asdl.classof(instance.schedule.facts.proof_obligations[2].requirement) == Stencil.StencilProofAlignment)
assert(instance.schedule.facts.proof_obligations[2].origin == Stencil.StencilProofBoundaryContract)
assert(asdl.classof(instance.schedule.facts.proof_obligations[3].requirement) == Stencil.StencilProofNoAlias)
assert(instance.schedule.facts.proof_obligations[3].origin == Stencil.StencilProofAuthorAsserted)
assert(instance.schedule.facts.proof_obligations[4].requirement == Stencil.StencilProofReductionReassociable)
assert(instance.schedule.facts.proof_obligations[4].proof == proof)
assert(artifact.provider == Stencil.StencilProviderC)
assert(artifact.instance == instance)
assert(artifact.realized == nil)
assert(#artifact.schedule_rejects == 0)

local meta_node_id = Stencil.StencilMetastencilNodeId("meta:n0")
local meta_external = Stencil.StencilMetastencilPort(
    Stencil.StencilMetastencilPortRef(nil, "xs"),
    Stencil.StencilMetastencilPortInput,
    i32,
    nil
)
local meta_input = Stencil.StencilMetastencilPort(
    Stencil.StencilMetastencilPortRef(meta_node_id, "xs"),
    Stencil.StencilMetastencilPortInput,
    i32,
    Stencil.StencilAccessRef("xs")
)
local meta_output = Stencil.StencilMetastencilPort(
    Stencil.StencilMetastencilPortRef(meta_node_id, "acc"),
    Stencil.StencilMetastencilPortOutput,
    i32,
    Stencil.StencilAccessRef("acc")
)
local meta_node = Stencil.StencilMetastencilNode(meta_node_id, artifact, { meta_input }, { meta_output })
local meta_wire = Stencil.StencilMetastencilWire(
    Stencil.StencilMetastencilWireId("meta:w0"),
    meta_external.ref,
    meta_input.ref,
    i32
)
local meta_legality = Stencil.StencilFusionLegality(
    {
        Stencil.StencilFusionCompatibleAbi(meta_wire.id, i32),
        Stencil.StencilFusionNoIntermediateMaterialization(meta_wire.id),
    },
    {},
    {}
)
local meta_descriptor = Stencil.StencilMetastencilDescriptor(
    Stencil.StencilMetastencilId("meta:reduce"),
    { meta_external },
    { meta_node },
    { meta_wire },
    instance.abi,
    meta_legality
)
local meta_fingerprint = Stencil.StencilMetastencilFingerprint("test:meta:fingerprint")
local meta_candidate = Stencil.StencilMetastencilCandidate(
    meta_descriptor,
    meta_fingerprint,
    1,
    0,
    Stencil.StencilMetastencilCandidateSelected,
    {},
    "schema smoke"
)
local meta_provenance = Stencil.StencilMetastencilCoverProvenance(
    Stencil.StencilScheduleSelectionHeuristic,
    meta_descriptor.id.text,
    { meta_candidate },
    "schema smoke"
)
local meta_selection = Stencil.StencilMetastencilCoverSelected(meta_candidate, meta_provenance)
assert(meta_descriptor.id.text == "meta:reduce")
assert(meta_descriptor.external_ports[1].ref.name == "xs")
assert(meta_descriptor.nodes[1].artifact == artifact)
assert(meta_descriptor.wires[1].ty == i32)
assert(asdl.classof(meta_descriptor.legality.facts[1]) == Stencil.StencilFusionCompatibleAbi)
assert(asdl.classof(meta_selection.candidate) == Stencil.StencilMetastencilCandidate)
assert(meta_selection.provenance.winner == "meta:reduce")

local axis_x = Stencil.StencilProducerAxis(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward)
local axis_y = Stencil.StencilProducerAxis(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward)
local nd_producer = Stencil.StencilProducer(nil, Stencil.StencilProduceRangeND({ axis_x, axis_y }))
local producer_fact = Stencil.StencilProducerFact(
    domain,
    nd_producer,
    { Kernel.KernelProofFlow(domain, "schema producer fact smoke") },
    Stencil.StencilProducerCheckerDerived
)
local producer_facts = Stencil.StencilProducerFactSet(Code.CodeModuleId("module:producer_fact"), { producer_fact })
assert(producer_facts.facts[1].domain == domain)
assert(producer_facts.facts[1].producer == nd_producer)
assert(producer_facts.facts[1].origin == Stencil.StencilProducerCheckerDerived)
local window_producer = Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND({ axis_x, axis_y }, {
    Stencil.StencilWindowAxis(1, 1, Stencil.StencilWindowBoundaryClamp),
    Stencil.StencilWindowAxis(1, 1, Stencil.StencilWindowBoundaryReject),
}))
local tiled_producer = Stencil.StencilProducer(nil, Stencil.StencilProduceTiledND({ axis_x, axis_y }, { 16, 16 }))
local backward_producer = Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerBackward))
local zero_step_producer = Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 0, Stencil.StencilProducerForward))
assert(StencilArtifactPlan.producer_axis_count(nd_producer) == 2)
assert(StencilArtifactPlan.producer_axis_count(window_producer) == 2)
assert(StencilArtifactPlan.producer_axis_count(tiled_producer) == 2)
assert(StencilArtifactPlan.producer_shape_supported(nd_producer))
assert(StencilArtifactPlan.producer_shape_supported(window_producer))
assert(StencilArtifactPlan.producer_shape_supported(tiled_producer))
assert(StencilArtifactPlan.producer_shape_supported(backward_producer))
assert(not StencilArtifactPlan.producer_shape_supported(zero_step_producer))
assert(StencilArtifactPlan.producer_materialized(nd_producer))
assert(StencilArtifactPlan.producer_materialized(window_producer))
assert(StencilArtifactPlan.producer_materialized(tiled_producer))
assert(StencilArtifactPlan.producer_materialized(backward_producer))
assert(not StencilArtifactPlan.producer_materialized(zero_step_producer))
assert(StencilArtifactPlan.unsupported_producer_reject(nd_producer) == nil)
assert(StencilArtifactPlan.unsupported_producer_reject(window_producer) == nil)
assert(StencilArtifactPlan.unsupported_producer_reject(tiled_producer) == nil)
assert(StencilArtifactPlan.unsupported_producer_reject(backward_producer) == nil)
assert(StencilArtifactPlan.unsupported_producer_reject(zero_step_producer).reason:find("positive compile-time", 1, true) ~= nil)
local bad_window_producer = Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND({ axis_x, axis_y }, {
    Stencil.StencilWindowAxis(1, 1, Stencil.StencilWindowBoundaryClamp),
}))
local bad_window_extent_producer = Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND({ axis_x, axis_y }, {
    Stencil.StencilWindowAxis(-1, 1, Stencil.StencilWindowBoundaryClamp),
    Stencil.StencilWindowAxis(1, 1, Stencil.StencilWindowBoundaryReject),
}))
local bad_tiled_producer = Stencil.StencilProducer(nil, Stencil.StencilProduceTiledND({ axis_x, axis_y }, { 16, 0 }))
assert(not StencilArtifactPlan.producer_shape_supported(bad_window_producer))
assert(not StencilArtifactPlan.producer_shape_supported(bad_window_extent_producer))
assert(not StencilArtifactPlan.producer_shape_supported(bad_tiled_producer))
assert(StencilArtifactPlan.producer_shape_reject_reason(nd_producer) == nil)
assert(StencilArtifactPlan.producer_materializer_reject_reason(nd_producer) == nil)
assert(StencilArtifactPlan.unsupported_producer_reject(bad_window_producer).reason:find("one window per axis", 1, true) ~= nil)
assert(StencilArtifactPlan.unsupported_producer_reject(bad_window_extent_producer).reason:find("before extent", 1, true) ~= nil)
assert(StencilArtifactPlan.unsupported_producer_reject(bad_tiled_producer).reason:find("tile size 2", 1, true) ~= nil)
local nd_descriptor = Stencil.StencilDescriptor(
    nd_producer,
    {
        Stencil.StencilAccess("dst", Stencil.StencilAccessWrite, i32, Stencil.StencilLayoutContiguous(1)),
        Stencil.StencilAccess("xs", Stencil.StencilAccessRead, i32, Stencil.StencilLayoutContiguous(1)),
    },
    Stencil.StencilBodyPoint(Stencil.StencilPointInput(Stencil.StencilAccessRef("xs"))),
    Stencil.StencilSinkStore(Stencil.StencilAccessRef("dst"), Stencil.StencilStoreElementwise)
)
local nd_instance = Stencil.StencilInstance(instance.id, nd_descriptor, instance.schedule, instance.abi, instance.proofs)
local nd_artifact = Stencil.StencilArtifact(nd_instance, artifact.provider, artifact.symbol, artifact.c_signature, artifact.fingerprint, nil, {}, {})
local nd_shape = StencilArtifactPlan.artifact_shape(nd_artifact)
assert(asdl.classof(nd_shape) == Stencil.StencilArtifactStoreN)
assert(asdl.classof(nd_shape.producer) == Stencil.StencilProducerExecRangeND)
assert(nd_shape.producer.rank == 2)

local bad_vector_schedule = Stencil.StencilScheduleVector(
    Stencil.StencilVectorFeatureNative,
    Stencil.StencilLaneFixed(4),
    Stencil.StencilVectorUnaligned,
    Stencil.StencilVectorScalarTail,
    Stencil.StencilVectorReductionHorizontal,
    Stencil.StencilVectorCompilerGccAutovec,
    1,
    1,
    Stencil.StencilCompilerPolicy(Stencil.StencilCompilerClang, Stencil.StencilOptO3, Stencil.StencilMachineNative, {}),
    vector_facts
)
local bad_vector_instance = Stencil.StencilInstance(instance.id, descriptor, bad_vector_schedule, instance.abi, instance.proofs)
local bad_vector_artifact = Stencil.StencilArtifact(bad_vector_instance, artifact.provider, artifact.symbol, artifact.c_signature, artifact.fingerprint, nil, {}, {})
local rejected_vector_artifact = StencilArtifactPlan.artifact_with_realized(bad_vector_artifact, nil, nil)
assert(#rejected_vector_artifact.schedule_rejects == 1)
assert(asdl.classof(rejected_vector_artifact.schedule_rejects[1]) == Stencil.StencilScheduleRejectCompilerMatrix)

local realized = Stencil.StencilRealizedVector(
    Stencil.StencilVectorFeatureNative,
    4,
    2,
    1,
    Stencil.StencilVectorScalarTail,
    Stencil.StencilMaterializerResidualMC,
    { Stencil.StencilRealizedByConstruction("schema smoke") }
)
local schedule_reject = Stencil.StencilRejectSchedule(Stencil.StencilScheduleRejectRequestedRealizedMismatch(schedule, realized, "schema smoke mismatch"))
local missing_proof = Stencil.StencilRejectMissingProof(Stencil.StencilProofTripCount(Stencil.StencilTripCountMultipleOf(4)))
assert(realized.lanes == 4)
assert(asdl.classof(schedule_reject.reject) == Stencil.StencilScheduleRejectRequestedRealizedMismatch)
assert(asdl.classof(missing_proof.requirement) == Stencil.StencilProofTripCount)

local pred = Stencil.StencilPredCompareConst(Core.CmpEq, i32, init)
local input_xs = Stencil.StencilPointInput(Stencil.StencilAccessRef("xs"))
local input_lhs = Stencil.StencilPointInput(Stencil.StencilAccessRef("lhs"))
local input_rhs = Stencil.StencilPointInput(Stencil.StencilAccessRef("rhs"))
local window_input = Stencil.StencilPointWindowInput(
    Stencil.StencilAccessRef("xs"),
    { Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), -1) }
)
assert(asdl.classof(window_input) == Stencil.StencilPointWindowInput)
assert(window_input.offsets[1].axis.index == 1)
assert(window_input.offsets[1].offset == -1)
local op = Stencil.StencilPointUnary(Stencil.StencilUnaryNeg, input_xs, i32, sem, nil)
local zip_op = Stencil.StencilPointBinary(Stencil.StencilBinaryAdd, input_lhs, input_rhs, i32, sem, nil)
local cast_op = Stencil.StencilPointCast(Core.MachineCastSToF, input_xs, i32, Code.CodeTyFloat(64))
local pred_op = Stencil.StencilPointPredicate(pred, input_xs, Code.CodeTyBool8)
local cmp_op = Stencil.StencilPointCompare(Core.CmpLt, input_lhs, input_rhs, Code.CodeTyBool8)
local indexed = Stencil.StencilLayoutIndexed(Stencil.StencilLayoutContiguous(1), Stencil.StencilAccessRef("idx"), i32, 1)
local affine_layout = Stencil.StencilLayoutAffine1D(Stencil.StencilLayoutContiguous(1), -1, init)
local affine_nd_layout = Stencil.StencilLayoutAffineND(
    Stencil.StencilLayoutContiguous(1),
    {
        Stencil.StencilAffineAxisTerm(Stencil.StencilAxisRef(1), init),
        Stencil.StencilAffineAxisTerm(Stencil.StencilAxisRef(2), Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt("2")))),
    },
    nil
)
local slice_layout = Stencil.StencilLayoutSliceDescriptor(
    Code.CodeValueId("v:slice"),
    Code.CodeValueId("v:slice_data"),
    Code.CodeValueId("v:slice_len")
)
local view_layout = Stencil.StencilLayoutViewDescriptor(
    Code.CodeValueId("v:view"),
    Code.CodeValueId("v:view_data"),
    Code.CodeValueId("v:view_len"),
    Code.CodeValueId("v:view_stride"),
    2
)
local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local field_layout = Stencil.StencilLayoutFieldProjection(
    Stencil.StencilLayoutContiguous(1),
    pair_ty,
    "right",
    4
)
local soa_layout = Stencil.StencilLayoutSoAComponent(
    Stencil.StencilLayoutContiguous(1),
    pair_ty,
    "right",
    1
)

assert(op.op == Stencil.StencilUnaryNeg and op.result_ty == i32)
assert(zip_op.op == Stencil.StencilBinaryAdd and zip_op.result_ty == i32)
assert(cast_op.op == Core.MachineCastSToF)
assert(pred_op.result_ty == Code.CodeTyBool8)
assert(cmp_op.cmp == Core.CmpLt)
assert(indexed.index_ty == i32)
assert(affine_layout.scale == -1)
assert(affine_layout.offset == init)
assert(asdl.classof(affine_nd_layout) == Stencil.StencilLayoutAffineND)
assert(affine_nd_layout.terms[2].axis.index == 2)
assert(slice_layout.len == Code.CodeValueId("v:slice_len"))
assert(view_layout.stride == Code.CodeValueId("v:view_stride"))
assert(view_layout.stride_const == 2)
assert(field_layout.parent == Stencil.StencilLayoutContiguous(1))
assert(field_layout.record_ty == pair_ty)
assert(field_layout.field_name == "right")
assert(field_layout.field_offset == 4)
assert(asdl.classof(soa_layout.parent) == Stencil.StencilLayoutContiguous)
assert(soa_layout.record_ty == pair_ty)
assert(soa_layout.field_name == "right")
assert(soa_layout.component_index == 1)
assert(asdl.classof(pred) == Stencil.StencilPredCompareConst)
assert(pred.cmp == Core.CmpEq)
assert(pred.operand_ty == i32)

io.write("lalin schema_stencil ok\n")
