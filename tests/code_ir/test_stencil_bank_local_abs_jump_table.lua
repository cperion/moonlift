package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Schedule = T.LalinSchedule
local Stencil = T.LalinStencil
local Value = T.LalinValue
local LJ = T.LalinLuaJIT

local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local StencilBank = require("lalin.stencil_bank")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local init = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
local reduction = Value.ReductionFact(
    Value.AlgebraFactId("reduction:test:local_abs_jump_table"),
    Flow.FlowDomainFunction(Code.CodeFuncId("fn:local_abs_jump_table")),
    Code.CodeValueId("v:acc"),
    Value.ReductionAdd,
    init,
    Value.ValueExprValue(Code.CodeValueId("v:item")),
    i32,
    sem,
    nil,
    Value.AlgebraProofIdentity("local absolute relocation jump table regression")
)

local artifact = StencilArtifactPlan.reduce_array_artifact(reduction, nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
    schedule = Schedule.ScheduleVector(Schedule.LaneVector(i32, 16), 1, 1, Schedule.TailScalar),
})

local bank, err = StencilBank.build_binary_bank({ artifact }, {
    stem = "test_stencil_bank_local_abs_jump_table",
    cflags = "-std=c99 -O3 -march=native -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c",
})
assert(bank ~= nil, tostring(err))

local saw_local_abs32 = false
local saw_local_abs64 = false
for _, entry in ipairs(bank.entries or {}) do
    for _, patch in ipairs(entry.patches or {}) do
        saw_local_abs32 = saw_local_abs32 or patch.kind == LJ.LJPatchLocalAbs32
        saw_local_abs64 = saw_local_abs64 or patch.kind == LJ.LJPatchLocalAbs64
    end
end

-- Some compilers may lower this tail without a jump table, but GCC -O3 on x64
-- emits R_X86_64_32S to .rodata plus R_X86_64_64 table entries.
if saw_local_abs32 then
    assert(bank.install.address == LJ.LJInstallLow32Address, "local absolute32 relocations require low32 installation")
end
if saw_local_abs64 then
    assert(#bank.entries[1].binary > 256, "local absolute64 jump-table section should be materialized into the blob")
end

local realization, realize_err = StencilBank.realize_binary_artifacts({ artifact }, { bank = bank })
assert(realization ~= nil, tostring(realize_err))

local fn = assert(realization.symbols[artifact.symbol.text])
local n = 257
local xs = ffi.new("int32_t[?]", n)
local expected = 0
for i = 0, n - 1 do
    xs[i] = (i * 17 + 11) % 127
    expected = expected + xs[i]
end
assert(fn(xs, 0, n, 0) == expected, "local absolute jump-table stencil produced wrong sum")

io.write("lalin stencil_bank local abs jump table ok\n")
