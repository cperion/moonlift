package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
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
local descriptor = Stencil.StencilDescriptorReduce(
    Stencil.StencilDomainRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilDomainForward),
    {
        Stencil.StencilAccess(
            "xs",
            Stencil.StencilAccessRead,
            i32,
            Stencil.StencilTopologyContiguous(1)
        ),
        Stencil.StencilAccess(
            "acc",
            Stencil.StencilAccessReduce,
            i32,
            Stencil.StencilTopologyScalar(init)
        ),
    },
    Stencil.StencilApplyInput(Stencil.StencilAccessRef("xs")),
    i32,
    Stencil.StencilReduceFold(Stencil.StencilReducer(Value.ReductionAdd, i32, init, sem, nil))
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
assert(pvm.classof(StencilArtifactPlan.descriptor_domain(instance.descriptor)) == Stencil.StencilDomainRange1D)
assert(StencilArtifactPlan.descriptor_accesses(instance.descriptor)[1].role == Stencil.StencilAccessRead)
assert(StencilArtifactPlan.descriptor_accesses(instance.descriptor)[2].role == Stencil.StencilAccessReduce)
assert(pvm.classof(instance.descriptor.mode) == Stencil.StencilReduceFold)
assert(pvm.classof(instance.descriptor.mode.reducer) == Stencil.StencilReducer)
assert(instance.descriptor.mode.reducer.identity == init)
assert(pvm.classof(instance.schedule) == Stencil.StencilScheduleAutoVector)
assert(instance.schedule.compiler.compiler == Stencil.StencilCompilerGcc)
assert(instance.schedule.compiler.opt_level == Stencil.StencilOptO3)
assert(instance.schedule.compiler.machine == Stencil.StencilMachineNative)
assert(instance.schedule.facts.access_facts[1].access.name == "xs")
assert(instance.schedule.facts.alias_facts[1].left.name == "xs")
assert(instance.schedule.facts.alias_facts[1].right.name == "acc")
assert(instance.schedule.facts.alias_facts[1].relation == Stencil.StencilAliasNoAlias)
assert(pvm.classof(instance.schedule.facts.access_facts[1].alignment) == Stencil.StencilAlignmentKnown)
assert(instance.schedule.facts.arithmetic.int_semantics == sem)
assert(#instance.schedule.facts.proof_obligations == 4)
assert(pvm.classof(instance.schedule.facts.proof_obligations[1].kind) == Stencil.StencilProofUnitStride)
assert(pvm.classof(instance.schedule.facts.proof_obligations[2].kind) == Stencil.StencilProofAlignment)
assert(instance.schedule.facts.proof_obligations[2].origin == Stencil.StencilProofBoundaryContract)
assert(pvm.classof(instance.schedule.facts.proof_obligations[3].kind) == Stencil.StencilProofNoAlias)
assert(instance.schedule.facts.proof_obligations[3].origin == Stencil.StencilProofAuthorAsserted)
assert(instance.schedule.facts.proof_obligations[4].kind == Stencil.StencilProofReductionReassociable)
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
assert(pvm.classof(meta_descriptor.legality.facts[1]) == Stencil.StencilFusionCompatibleAbi)
assert(pvm.classof(meta_selection.candidate) == Stencil.StencilMetastencilCandidate)
assert(meta_selection.provenance.winner == "meta:reduce")

local axis_x = Stencil.StencilDomainAxis(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilDomainForward)
local axis_y = Stencil.StencilDomainAxis(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilDomainForward)
local nd_domain = Stencil.StencilDomainRangeND({ axis_x, axis_y })
local window_domain = Stencil.StencilDomainWindowND({ axis_x, axis_y }, {
    Stencil.StencilWindowAxis(1, 1, Stencil.StencilWindowBoundaryClamp),
    Stencil.StencilWindowAxis(1, 1, Stencil.StencilWindowBoundaryReject),
})
local tiled_domain = Stencil.StencilDomainTiledND({ axis_x, axis_y }, { 16, 16 })
local backward_domain = Stencil.StencilDomainRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilDomainBackward)
local zero_step_domain = Stencil.StencilDomainRange1D(Code.CodeTyIndex, nil, nil, 0, Stencil.StencilDomainForward)
assert(not StencilArtifactPlan.domain_supported(nd_domain))
assert(not StencilArtifactPlan.domain_supported(window_domain))
assert(not StencilArtifactPlan.domain_supported(tiled_domain))
assert(not StencilArtifactPlan.domain_supported(backward_domain))
assert(not StencilArtifactPlan.domain_supported(zero_step_domain))
local nd_reject = StencilArtifactPlan.unsupported_domain_reject(nd_domain)
assert(pvm.classof(nd_reject) == Stencil.StencilRejectUnsupportedDomain)
assert(nd_reject.domain == nd_domain)
assert(StencilArtifactPlan.unsupported_domain_reject(backward_domain).reason:find("backward", 1, true) ~= nil)
assert(StencilArtifactPlan.unsupported_domain_reject(zero_step_domain).reason:find("positive compile-time", 1, true) ~= nil)
local nd_descriptor = Stencil.StencilDescriptorApply(
    nd_domain,
    {
        Stencil.StencilAccess("dst", Stencil.StencilAccessWrite, i32, Stencil.StencilTopologyContiguous(1)),
        Stencil.StencilAccess("xs", Stencil.StencilAccessRead, i32, Stencil.StencilTopologyContiguous(1)),
    },
    Stencil.StencilApplyInput(Stencil.StencilAccessRef("xs")),
    Stencil.StencilApplyElementwise
)
local nd_instance = Stencil.StencilInstance(instance.id, nd_descriptor, instance.schedule, instance.abi, instance.proofs)
local nd_artifact = Stencil.StencilArtifact(nd_instance, artifact.provider, artifact.symbol, artifact.c_signature, artifact.fingerprint, nil, {}, {})
local ok, err = pcall(function() return StencilArtifactPlan.artifact_shape(nd_artifact) end)
assert(not ok and tostring(err):find("unsupported stencil domain", 1, true) ~= nil)

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
assert(pvm.classof(rejected_vector_artifact.schedule_rejects[1]) == Stencil.StencilScheduleRejectCompilerMatrix)

local realized = Stencil.StencilRealizedVector(
    Stencil.StencilVectorFeatureNative,
    4,
    2,
    1,
    Stencil.StencilVectorScalarTail,
    Stencil.StencilMaterializerCopyPatchMC,
    { Stencil.StencilRealizedByConstruction("schema smoke") }
)
local schedule_reject = Stencil.StencilRejectSchedule(Stencil.StencilScheduleRejectRequestedRealizedMismatch(schedule, realized, "schema smoke mismatch"))
local missing_proof = Stencil.StencilRejectMissingProof(Stencil.StencilProofTripCount(Stencil.StencilTripCountMultipleOf(4)))
assert(realized.lanes == 4)
assert(pvm.classof(schedule_reject.reject) == Stencil.StencilScheduleRejectRequestedRealizedMismatch)
assert(pvm.classof(missing_proof.obligation) == Stencil.StencilProofTripCount)

local pred = Stencil.StencilPredCompareConst(Core.CmpEq, i32, init)
local input_xs = Stencil.StencilApplyInput(Stencil.StencilAccessRef("xs"))
local input_lhs = Stencil.StencilApplyInput(Stencil.StencilAccessRef("lhs"))
local input_rhs = Stencil.StencilApplyInput(Stencil.StencilAccessRef("rhs"))
local op = Stencil.StencilApplyUnary(Stencil.StencilUnaryNeg, input_xs, i32, sem, nil)
local zip_op = Stencil.StencilApplyBinary(Stencil.StencilBinaryAdd, input_lhs, input_rhs, i32, sem, nil)
local cast_op = Stencil.StencilApplyCast(Core.MachineCastSToF, input_xs, i32, Code.CodeTyFloat(64))
local pred_op = Stencil.StencilApplyPredicate(pred, input_xs, Code.CodeTyBool8)
local cmp_op = Stencil.StencilApplyCompare(Core.CmpLt, input_lhs, input_rhs, Code.CodeTyBool8)
local indexed = Stencil.StencilTopologyIndexed(i32, 1)
local slice_topology = Stencil.StencilTopologySliceDescriptor(
    Code.CodeValueId("v:slice"),
    Code.CodeValueId("v:slice_data"),
    Code.CodeValueId("v:slice_len")
)
local view_topology = Stencil.StencilTopologyViewDescriptor(
    Code.CodeValueId("v:view"),
    Code.CodeValueId("v:view_data"),
    Code.CodeValueId("v:view_len"),
    Code.CodeValueId("v:view_stride"),
    2
)
local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local field_topology = Stencil.StencilTopologyFieldProjection(
    Stencil.StencilTopologyContiguous(1),
    pair_ty,
    "right",
    4
)
local soa_topology = Stencil.StencilTopologySoAComponent(
    Stencil.StencilTopologyContiguous(1),
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
assert(slice_topology.len == Code.CodeValueId("v:slice_len"))
assert(view_topology.stride == Code.CodeValueId("v:view_stride"))
assert(view_topology.stride_const == 2)
assert(field_topology.parent == Stencil.StencilTopologyContiguous(1))
assert(field_topology.record_ty == pair_ty)
assert(field_topology.field_name == "right")
assert(field_topology.field_offset == 4)
assert(pvm.classof(soa_topology.parent) == Stencil.StencilTopologyContiguous)
assert(soa_topology.record_ty == pair_ty)
assert(soa_topology.field_name == "right")
assert(soa_topology.component_index == 1)
assert(pvm.classof(pred) == Stencil.StencilPredCompareConst)
assert(pred.cmp == Core.CmpEq)
assert(pred.operand_ty == i32)

io.write("lalin schema_stencil ok\n")
