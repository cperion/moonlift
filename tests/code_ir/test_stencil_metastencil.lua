package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local ffi = require("ffi")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Graph = T.LalinGraph
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local Meta = require("lalin.stencil_metastencil")(T)
local CopyPatchLuaTrace = require("lalin.copy_patch_luatrace")(T)
local MC = require("tests.code_ir.copy_patch_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local bool8 = Code.CodeTyBool8
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function reduction(kind, init)
    local domain = Flow.FlowDomainLoop(Graph.GraphLoopId("loop:meta"))
    return Value.ReductionFact(
        Value.AlgebraFactId("reduction:meta"),
        domain,
        Code.CodeValueId("v:acc"),
        kind,
        iconst(init),
        Value.ValueExprValue(Code.CodeValueId("v:item")),
        i32,
        sem,
        nil,
        Value.AlgebraProofFlow(domain, "metastencil test reduction")
    )
end

local add2 = Plan.apply_n_array_artifact({
    tag = "meta_add2",
    result_ty = i32,
    inputs = {
        { name = "x1", ty = i32 },
        { name = "x2", ty = i32 },
    },
    expr = Plan.apply_binary_expr(
        Stencil.StencilBinaryAdd,
        Plan.input_expr("x1"),
        Plan.input_expr("x2"),
        i32,
        { int_semantics = sem }
    ),
    step_num = 1,
})

local sum1 = Plan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
})

local select1 = Plan.select_array_artifact(Stencil.StencilPredNonZero, {
    cond_ty = bool8,
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
})

local add_node = Meta.node_from_artifact("add", add2)
local sum_node = Meta.node_from_artifact("sum", sum1)
local select_node = Meta.node_from_artifact("select", select1)

assert(#add_node.inputs == 2, "apply_n node should expose two typed input ports")
assert(#add_node.outputs == 1, "apply_n node should expose one typed output port")
assert(add_node.outputs[1].ref.name == "dst")
assert(sum_node.inputs[1].ref.name == "xs")

local ext_x1 = Meta.external_port("x1", Stencil.StencilMetastencilPortInput, i32)
local ext_x2 = Meta.external_port("x2", Stencil.StencilMetastencilPortInput, i32)
local ext_out = Meta.external_port("out", Stencil.StencilMetastencilPortOutput, i32)
local ext_cond = Meta.external_port("cond", Stencil.StencilMetastencilPortInput, bool8)

local one_node = Meta.descriptor(
    "meta:add",
    { ext_x1, ext_x2, ext_out },
    { add_node },
    {
        Meta.wire("w:x1:add", nil, "x1", "add", "x1", i32),
        Meta.wire("w:x2:add", nil, "x2", "add", "x2", i32),
        Meta.wire("w:add:out", "add", "dst", nil, "out", i32),
    },
    add2.instance.abi
)

local two_node = Meta.descriptor(
    "meta:add_then_sum",
    { ext_x1, ext_x2 },
    { add_node, sum_node },
    {
        Meta.wire("w:x1:add", nil, "x1", "add", "x1", i32),
        Meta.wire("w:x2:add", nil, "x2", "add", "x2", i32),
        Meta.wire("w:add:sum", "add", "dst", "sum", "xs", i32),
    },
    sum1.instance.abi
)

local bad_type = Meta.descriptor(
    "meta:bad_type",
    { ext_x1, ext_cond },
    { select_node },
    {
        Meta.wire("w:bad:cond", nil, "x1", "select", "cond", i32),
        Meta.wire("w:cond:then", nil, "cond", "select", "then_xs", bool8),
    },
    select1.instance.abi
)

assert(#one_node.legality.rejects == 0, "one-node cover should be legal")
assert(#two_node.legality.rejects == 0, "two-node cover should be legal")
assert(#bad_type.legality.rejects >= 1, "bad cover should record typed rejects")
assert(pvm.classof(bad_type.legality.rejects[1]) == Stencil.StencilFusionRejectTypeMismatch)

local fp1 = Meta.fingerprint(two_node)
local fp2 = Meta.fingerprint(two_node)
local fp3 = Meta.fingerprint(one_node)
assert(fp1.text == fp2.text, "metastencil fingerprint must be stable")
assert(fp1.text ~= fp3.text, "metastencil fingerprint must include graph shape")

local selection = Meta.select_longest_legal_cover({ one_node, bad_type, two_node })
assert(pvm.classof(selection) == Stencil.StencilMetastencilCoverSelected)
assert(selection.candidate.descriptor.id.text == "meta:add_then_sum")
assert(selection.candidate.covered_nodes == 2)
assert(selection.candidate.status == Stencil.StencilMetastencilCandidateSelected)
assert(#selection.provenance.candidates == 3)

local no_cover = Meta.select_longest_legal_cover({ bad_type })
assert(pvm.classof(no_cover) == Stencil.StencilMetastencilNoCover)
assert(#no_cover.rejects >= 1)
assert(no_cover.provenance.winner == "none")

local mc = assert(MC.compile(T, { selection }, { stem = "test_stencil_metastencil_cover_mc" }))
assert(#mc.mc_bank.metastencil_covers == 1, "MC bank should own selected cover metadata")
assert(mc.mc_bank.metastencil_covers[1].descriptor.id.text == "meta:add_then_sum")
assert(#mc.realization.metastencil_covers == 1, "MC realization should preserve selected cover metadata")
assert(mc.realization.metastencil_covers[1].descriptor.id.text == "meta:add_then_sum")
assert(#mc.mc_bank.entries == 1, "MC selected cover should materialize as one fused artifact")
local mc_fused_symbol = mc.mc_bank.entries[1].artifact.symbol.text
assert(Plan.artifact_shape(mc.mc_bank.entries[1].artifact).kind == "reduce_n_array", "MC fused cover should lower to reduce_n_array")
assert(mc.symbols[mc_fused_symbol], "MC selected cover should install fused artifact")

local bc = assert(CopyPatchLuaTrace.realize_artifacts({ selection }, { stem = "test_stencil_metastencil_cover_bc" }))
assert(#bc.bc_bank.metastencil_covers == 1, "BC bank should own selected cover metadata")
assert(bc.bc_bank.metastencil_covers[1].descriptor.id.text == "meta:add_then_sum")
assert(#bc.metastencil_covers == 1, "BC realization should preserve selected cover metadata")
assert(bc.metastencil_covers[1].descriptor.id.text == "meta:add_then_sum")
assert(#bc.bc_bank.entries == 1, "BC selected cover should materialize as one fused artifact")
local bc_fused_symbol = bc.bc_bank.entries[1].artifact.symbol.text
assert(Plan.artifact_shape(bc.bc_bank.entries[1].artifact).kind == "reduce_n_array", "BC fused cover should lower to reduce_n_array")
assert(bc.symbols[bc_fused_symbol], "BC selected cover should install fused artifact")

local x1v = ffi.new("int32_t[5]", { 1, 2, 3, 4, 5 })
local x2v = ffi.new("int32_t[5]", { 10, 20, 30, 40, 50 })
assert(mc.symbols[mc_fused_symbol](x1v, x2v, 0, 5, 0) == 165, "MC fused cover should execute")
assert(bc.symbols[bc_fused_symbol](x1v, x2v, 0, 5, 0) == 165, "BC fused cover should execute")

io.write("stencil metastencil ok\n")
