package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Flow = T.MoonFlow
local Graph = T.MoonGraph
local Value = T.MoonValue
local Kernel = T.MoonKernel
local Ty = T.MoonType
local Stencil = T.MoonStencil

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
            "xs",
            Stencil.StencilAliasUnknown,
            Stencil.StencilAlignmentKnown(4),
            true,
            true
        ),
        Stencil.StencilAccessVectorFact(
            "acc",
            Stencil.StencilAliasNoAlias,
            Stencil.StencilAlignmentUnknown,
            false,
            false
        ),
    },
    Stencil.StencilTripCountDynamic,
    Stencil.StencilArithmeticVectorFact(true, sem, nil)
)
local schedule = Stencil.StencilScheduleAutoVector(compiler, vector_facts)
local descriptor = Stencil.StencilDescriptor(
    Stencil.StencilReduce,
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
    nil,
    Stencil.StencilReducer(Value.ReductionAdd, i32, init, sem, nil),
    Stencil.StencilSkeletonReduce,
    Stencil.StencilMemorySemantics(nil, nil, nil),
    i32,
    {
        Stencil.StencilParamType("elem_ty", i32),
        Stencil.StencilParamReduction("reduction", Value.ReductionAdd),
        Stencil.StencilParamNumber("stride", 1),
    }
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
    "int32_t ml_stencil_reduce_array_i32_add_s1(const int32_t *, int32_t, int32_t, int32_t);"
)

assert(instance.descriptor.vocab == Stencil.StencilReduce)
assert(pvm.classof(instance.descriptor.domain) == Stencil.StencilDomainRange1D)
assert(instance.descriptor.accesses[1].role == Stencil.StencilAccessRead)
assert(instance.descriptor.accesses[2].role == Stencil.StencilAccessReduce)
assert(pvm.classof(instance.descriptor.reducer) == Stencil.StencilReducer)
assert(instance.descriptor.skeleton == Stencil.StencilSkeletonReduce)
assert(pvm.classof(instance.schedule) == Stencil.StencilScheduleAutoVector)
assert(instance.schedule.compiler.compiler == Stencil.StencilCompilerGcc)
assert(instance.schedule.compiler.opt_level == Stencil.StencilOptO3)
assert(instance.schedule.compiler.machine == Stencil.StencilMachineNative)
assert(instance.schedule.facts.access_facts[1].access_name == "xs")
assert(pvm.classof(instance.schedule.facts.access_facts[1].alignment) == Stencil.StencilAlignmentKnown)
assert(instance.schedule.facts.arithmetic.int_semantics == sem)
assert(artifact.provider == Stencil.StencilProviderC)
assert(artifact.instance == instance)

local pred = Stencil.StencilPredEqConst(init)
local op = Stencil.StencilOpUnary(Stencil.StencilUnaryNeg, i32)
local zip_op = Stencil.StencilOpBinary(Stencil.StencilBinaryAdd, i32)
local cast_op = Stencil.StencilOpCast(Core.MachineCastSToF, i32, Code.CodeTyFloat(64))
local pred_op = Stencil.StencilOpPredicate(pred, Code.CodeTyBool8)
local cmp_op = Stencil.StencilOpCompare(Core.CmpLt, Code.CodeTyBool8)
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
assert(pvm.classof(pred) == Stencil.StencilPredEqConst)

io.write("moonlift schema_stencil ok\n")
