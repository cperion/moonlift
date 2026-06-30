package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.exec_plan")(T)

local Code = T.LalinCode
local Exec = T.LalinExec
local Flow = T.LalinFlow
local Stencil = T.LalinStencil
local Kernel = T.LalinKernel
local Value = T.LalinValue

local function provenance()
    return Stencil.StencilScheduleSelectionProvenance(Stencil.StencilScheduleSelectionHeuristic, "test", {}, "test")
end

local function compiler()
    return Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO2, Stencil.StencilMachineNative, {})
end

local access = Stencil.StencilAccessRef("dst")
local producer = Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward))
local descriptor = Stencil.StencilDescriptor(
    producer,
    {},
    Stencil.StencilBodyPoint(Stencil.StencilPointConst(Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, T.LalinCore.LitInt("0"))), Code.CodeTyIndex)),
    Stencil.StencilSinkStore(access, Stencil.StencilStoreElementwise)
)
local instance = Stencil.StencilInstance(
    Stencil.StencilInstanceId("stencil:inst"),
    descriptor,
    Stencil.StencilScheduleScalar(compiler()),
    Stencil.StencilAbi({}, nil),
    {}
)
local artifact = Stencil.StencilArtifact(
    instance,
    Stencil.StencilProviderC,
    Stencil.StencilSymbolId("symbol:test"),
    "void test(void)",
    Stencil.StencilArtifactFingerprint("fp:test"),
    nil,
    {},
    {}
)
local fake_selection = Stencil.StencilSelected(instance, provenance())
local func_id = Code.CodeFuncId("fn:test")
local kernel_id = Kernel.KernelId("kernel:test")
local kernel_plan = Kernel.KernelPlanned(
    kernel_id,
    Kernel.KernelSubjectFragment(func_id, Code.CodeBlockId("block:entry"), Code.CodeBlockId("block:exit")),
    Kernel.KernelBody(
        Kernel.KernelDomainFlow(Flow.FlowDomainFunction(func_id), Flow.FlowTripCountUnknown("test"), nil),
        {},
        {},
        {},
        Kernel.KernelResultVoid,
        Kernel.KernelEquivalenceProof({})
    )
)
local kernel_entry = { kernel = kernel_id }

local function materialize(selection)
    local entries, by_func = {}, {}
    selection:add_exec_stencil(entries, by_func, kernel_entry, 1, kernel_plan, {}, artifact, func_id)
    return entries[1], by_func
end

local function input(fields)
    return Exec.ExecStencilInput(
        fields.artifact,
        fields.func,
        fields.selected_reason or "selected",
        fields.unselected_reason or "not selected",
        fields.missing_artifact_reason or "missing artifact",
        fields.missing_func_reason or "missing function"
    )
end

do
    local selection = fake_selection:select_exec_stencil(input {
        artifact = artifact,
        func = func_id,
        selected_reason = "materialize",
    })
    assert(selection.reason == "materialize")
    local entry, by_func = materialize(selection)
    assert(entry.decision.reason == "materialize")
    assert(entry.decision.fragment.source_func == func_id)
    assert(#by_func[func_id.text] == 1)
end

do
    local selection = Stencil.StencilNoSelection(Stencil.StencilStore, {}, provenance()):select_exec_stencil(input {
        unselected_reason = "entry skipped",
    })
    assert(selection.reason == "entry skipped")
    local entry = materialize(selection)
    assert(entry.decision.reason == "entry skipped")
end

do
    local selection = fake_selection:select_exec_stencil(input {
        artifact = nil,
        func = func_id,
        missing_artifact_reason = "artifact absent",
    })
    assert(selection.reason == "artifact absent")
    local entry = materialize(selection)
    assert(entry.decision.reason == "artifact absent")
end

do
    local selection = fake_selection:select_exec_stencil(input {
        artifact = artifact,
        func = nil,
        missing_func_reason = "function absent",
    })
    assert(selection.reason == "function absent")
    local entry = materialize(selection)
    assert(entry.decision.reason == "function absent")
end

local ok = pcall(require, "lalin.exec_plan_rules")
assert(not ok, "exec_plan_rules must not exist")

io.write("lalin exec_plan methods ok\n")
