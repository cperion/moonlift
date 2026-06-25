package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local Measure = require("lalin.luajit_measure")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Back = T.LalinBack
local Flow = T.LalinFlow
local LJ = T.LalinLuaJIT
local Value = T.LalinValue
local CType = require("lalin.luajit_ctype")(T)
local Emit = require("lalin.luajit_emit")(T)
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local StencilBinary = require("tests.code_ir.stencil_binary_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local i32_phys = CType.physical_type(i32, {})
local ptr_i32_phys = CType.physical_type(Code.CodeTyDataPtr(i32), {})

local xs_id = LJ.LJValueId("xs")
local n_id = LJ.LJValueId("n")
local item_id = LJ.LJValueId("item")
local acc_id = LJ.LJValueId("acc")
local source_id = LJ.LJMachineId("source")
local fold_id = LJ.LJMachineId("fold")

local source = LJ.LJMachine(
    source_id,
    LJ.LJMachineSourceArray(xs_id, i32_phys, LJ.LJExprValue(n_id)),
    i32_phys,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local step = LJ.LJExprIntBinary(Core.BinAdd, i32_phys, sem, LJ.LJExprValue(acc_id), LJ.LJExprValue(item_id))
local fold = LJ.LJMachine(
    fold_id,
    LJ.LJMachineFold(source_id, acc_id, item_id, LJ.LJExprLiteral(Core.LitInt("0"), i32_phys), step),
    i32_phys,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local fn = LJ.LJFunc(
    LJ.LJFuncId("sum_i32"),
    nil,
    "sum_i32",
    LJ.LJFuncSigId("sig:sum_i32"),
    {
        LJ.LJParam(xs_id, "xs", ptr_i32_phys),
        LJ.LJParam(n_id, "n", i32_phys),
    },
    {},
    { source, fold },
    LJ.LJBodyMachine(fold_id, LJ.LJTerminalFirst(nil)),
    LJ.LJTraceHot
)
local module = LJ.LJModule(nil, { fn }, {}, {}, {})
local compiled, err, src = Emit.compile_module(module)
assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))

local n = 128
local xs = ffi.new("int32_t[?]", n)
local expected = 0
for i = 0, n - 1 do
    xs[i] = bit.tobit(i * 17 + 11)
    expected = bit.tobit(expected + xs[i])
end
assert(compiled.sum_i32(xs, n) == expected)
assert(src:match("bit%.tobit"), "emitted i32 lowering should keep trace-int arithmetic")

local stencil_reduction = Value.ReductionFact(
    Value.AlgebraFactId("reduction:test:sum_i32"),
    Flow.FlowDomainFunction(Code.CodeFuncId("fn:sum_i32_stencil")),
    Code.CodeValueId("v:acc"),
    Value.ReductionAdd,
    Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0"))),
    Value.ValueExprValue(Code.CodeValueId("v:item")),
    i32,
    sem,
    nil,
    Value.AlgebraProofIdentity("test stencil reduction")
)
local stencil_artifact = StencilArtifactPlan.reduce_array_artifact(stencil_reduction, nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
})
local stencil_build, stencil_build_err = StencilBinary.compile(T, { stencil_artifact }, { stem = "test_luajit_emit_stencil" })
assert(stencil_build ~= nil, tostring(stencil_build_err))
local stencil_machine_id = LJ.LJMachineId("stencil_reduce")
local stencil_vec = LJ.LJMachine(
    stencil_machine_id,
    LJ.LJMachineStencilCall(
        stencil_artifact,
        {
            LJ.LJExprValue(xs_id),
            LJ.LJExprLiteral(Core.LitInt("0"), i32_phys),
            LJ.LJExprValue(n_id),
            LJ.LJExprLiteral(Core.LitInt("0"), i32_phys),
        },
        i32_phys
    ),
    i32_phys,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local stencil_fn = LJ.LJFunc(
    LJ.LJFuncId("sum_i32_stencil_vec"),
    nil,
    "sum_i32_stencil_vec",
    LJ.LJFuncSigId("sig:sum_i32_stencil_vec"),
    {
        LJ.LJParam(xs_id, "xs", ptr_i32_phys),
        LJ.LJParam(n_id, "n", i32_phys),
    },
    {},
    { stencil_vec },
    LJ.LJBodyMachine(stencil_machine_id, LJ.LJTerminalFirst(nil)),
    LJ.LJTraceHot
)
local stencil_compiled, stencil_err, stencil_src = Emit.compile_module(LJ.LJModule(nil, { stencil_fn }, {}, {}, {}), {
    stencil_symbols = stencil_build.symbols,
})
assert(stencil_compiled ~= nil, tostring(stencil_err) .. "\n" .. tostring(stencil_src))
assert(stencil_compiled.sum_i32_stencil_vec(xs, n) == expected)

local bench_n = 350000
local bench_xs = ffi.new("int32_t[?]", bench_n)
for i = 0, bench_n - 1 do bench_xs[i] = bit.tobit(i * 17 + 11) end
local function emitted_sum()
    return compiled.sum_i32(bench_xs, bench_n)
end
local result = Measure.measure_case {
    name = "emitted sum_i32",
    samples = 3,
    rounds = 1,
    warmup = 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
    fn = emitted_sum,
}
assert(result.trace.stop >= 1, "emitted sum_i32 should form a compiled trace")
assert(result.seconds.median < 0.010, "emitted sum_i32 unexpectedly slow: " .. Measure.format_result(result))

local a_id = LJ.LJValueId("a")
local b_id = LJ.LJValueId("b")
local entry_id = LJ.LJBlockId("entry")
local then_id = LJ.LJBlockId("then")
local else_id = LJ.LJBlockId("else")
local max_fn = LJ.LJFunc(
    LJ.LJFuncId("max_i32"),
    nil,
    "max_i32",
    LJ.LJFuncSigId("sig:max_i32"),
    {
        LJ.LJParam(a_id, "a", i32_phys),
        LJ.LJParam(b_id, "b", i32_phys),
    },
    {},
    {},
    LJ.LJBodyBlocks(entry_id, {
        LJ.LJBlock(
            entry_id,
            {},
            {},
            LJ.LJTermBranch(
                LJ.LJExprCompare(Core.CmpGt, i32_phys, LJ.LJExprValue(a_id), LJ.LJExprValue(b_id)),
                then_id,
                {},
                else_id,
                {}
            )
        ),
        LJ.LJBlock(then_id, {}, {}, LJ.LJTermReturn({ LJ.LJExprValue(a_id) })),
        LJ.LJBlock(else_id, {}, {}, LJ.LJTermReturn({ LJ.LJExprValue(b_id) })),
    }),
    LJ.LJTraceHot
)
local max_mod = LJ.LJModule(nil, { max_fn }, {}, {}, {})
local max_compiled, max_err, max_src = Emit.compile_module(max_mod)
assert(max_compiled ~= nil, tostring(max_err) .. "\n" .. tostring(max_src))
assert(max_compiled.max_i32(3, 9) == 9)
assert(max_compiled.max_i32(12, 4) == 12)

io.write("lalin luajit_emit ok\n")
