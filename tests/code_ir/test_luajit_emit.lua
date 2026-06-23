package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Measure = require("moonlift.luajit_measure")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Back = T.MoonBack
local LJ = T.MoonLuaJIT
local Value = T.MoonValue
local CType = require("moonlift.luajit_ctype")(T)
local Emit = require("moonlift.luajit_emit")(T)

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

local vec_id = LJ.LJMachineId("vec")
local vec = LJ.LJMachine(
    vec_id,
    LJ.LJMachineVectorReduceArray(xs_id, LJ.LJExprLiteral(Core.LitInt("0"), i32_phys), LJ.LJExprValue(n_id), LJ.LJExprLiteral(Core.LitInt("1"), i32_phys), i32_phys, i32_phys, Value.ReductionAdd, sem, LJ.LJExprLiteral(Core.LitInt("0"), i32_phys), 8, 1, nil),
    i32_phys,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local vec_fn = LJ.LJFunc(
    LJ.LJFuncId("sum_i32_vec"),
    nil,
    "sum_i32_vec",
    LJ.LJFuncSigId("sig:sum_i32_vec"),
    {
        LJ.LJParam(xs_id, "xs", ptr_i32_phys),
        LJ.LJParam(n_id, "n", i32_phys),
    },
    {},
    { vec },
    LJ.LJBodyMachine(vec_id, LJ.LJTerminalFirst(nil)),
    LJ.LJTraceHot
)
local vec_compiled, vec_err, vec_src = Emit.compile_module(LJ.LJModule(nil, { vec_fn }, {}, {}, {}))
assert(vec_compiled ~= nil, tostring(vec_err) .. "\n" .. tostring(vec_src))
assert(vec_compiled.sum_i32_vec(xs, n) == expected)
assert(vec_src:match("__vreduce_vec"), "vector reduce fallback should emit explicit reduce locals")

local helper_id = LJ.LJHelperId("helper:sum_i32_vec")
local native_vec = LJ.LJMachine(
    vec_id,
    LJ.LJMachineVectorReduceArray(xs_id, LJ.LJExprLiteral(Core.LitInt("0"), i32_phys), LJ.LJExprValue(n_id), LJ.LJExprLiteral(Core.LitInt("1"), i32_phys), i32_phys, i32_phys, Value.ReductionAdd, sem, LJ.LJExprLiteral(Core.LitInt("0"), i32_phys), 8, 1, helper_id),
    i32_phys,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local native_fn = LJ.LJFunc(
    LJ.LJFuncId("sum_i32_native_vec"),
    nil,
    "sum_i32_native_vec",
    LJ.LJFuncSigId("sig:sum_i32_native_vec"),
    {
        LJ.LJParam(xs_id, "xs", ptr_i32_phys),
        LJ.LJParam(n_id, "n", i32_phys),
    },
    {},
    { native_vec },
    LJ.LJBodyMachine(vec_id, LJ.LJTerminalFirst(nil)),
    LJ.LJTraceHot
)
local native_calls = 0
local native_compiled, native_err, native_src = Emit.compile_module(LJ.LJModule(nil, { native_fn }, {}, {}, {}), {
    native_helpers = {
        [helper_id.text] = function(ptr, len)
            native_calls = native_calls + 1
            local acc = 0
            for i = 0, len - 1 do acc = bit.tobit(acc + ptr[i]) end
            return acc
        end,
    },
})
assert(native_compiled ~= nil, tostring(native_err) .. "\n" .. tostring(native_src))
assert(native_compiled.sum_i32_native_vec(xs, n) == expected)
assert(native_calls == 1, "native vector reduce helper should be called once")

local function vector_reduce_func(name, reduction, init_raw)
    local machine_id = LJ.LJMachineId("vec:" .. name)
    local machine = LJ.LJMachine(
        machine_id,
        LJ.LJMachineVectorReduceArray(
            xs_id,
            LJ.LJExprLiteral(Core.LitInt("0"), i32_phys),
            LJ.LJExprValue(n_id),
            LJ.LJExprLiteral(Core.LitInt("1"), i32_phys),
            i32_phys,
            i32_phys,
            reduction,
            sem,
            LJ.LJExprLiteral(Core.LitInt(init_raw), i32_phys),
            8,
            1,
            nil
        ),
        i32_phys,
        LJ.LJStateScalar,
        LJ.LJTraceHot
    )
    return LJ.LJFunc(
        LJ.LJFuncId(name),
        nil,
        name,
        LJ.LJFuncSigId("sig:" .. name),
        {
            LJ.LJParam(xs_id, "xs", ptr_i32_phys),
            LJ.LJParam(n_id, "n", i32_phys),
        },
        {},
        { machine },
        LJ.LJBodyMachine(machine_id, LJ.LJTerminalFirst(nil)),
        LJ.LJTraceHot
    )
end

local family_mod = LJ.LJModule(nil, {
    vector_reduce_func("mul_i32_vec", Value.ReductionMul, "1"),
    vector_reduce_func("and_i32_vec", Value.ReductionAnd, "-1"),
    vector_reduce_func("or_i32_vec", Value.ReductionOr, "0"),
    vector_reduce_func("xor_i32_vec", Value.ReductionXor, "0"),
}, {}, {}, {})
local family_compiled, family_err, family_src = Emit.compile_module(family_mod)
assert(family_compiled ~= nil, tostring(family_err) .. "\n" .. tostring(family_src))
local small_n = 7
local small = ffi.new("int32_t[?]", small_n)
local exp_mul, exp_and, exp_or, exp_xor = 1, -1, 0, 0
for i = 0, small_n - 1 do
    small[i] = bit.tobit(i + 3)
    exp_mul = bit.tobit(exp_mul * small[i])
    exp_and = bit.band(exp_and, small[i])
    exp_or = bit.bor(exp_or, small[i])
    exp_xor = bit.bxor(exp_xor, small[i])
end
assert(family_compiled.mul_i32_vec(small, small_n) == exp_mul)
assert(family_compiled.and_i32_vec(small, small_n) == exp_and)
assert(family_compiled.or_i32_vec(small, small_n) == exp_or)
assert(family_compiled.xor_i32_vec(small, small_n) == exp_xor)

local u32 = Code.CodeTyInt(32, Code.CodeUnsigned)
local u32_phys = CType.physical_type(u32, {})
local ptr_u32_phys = CType.physical_type(Code.CodeTyDataPtr(u32), {})
local u32_vec = LJ.LJMachine(
    LJ.LJMachineId("vec:u32"),
    LJ.LJMachineVectorReduceArray(xs_id, LJ.LJExprLiteral(Core.LitInt("0"), i32_phys), LJ.LJExprValue(n_id), LJ.LJExprLiteral(Core.LitInt("1"), i32_phys), u32_phys, u32_phys, Value.ReductionAdd, sem, LJ.LJExprLiteral(Core.LitInt("0"), u32_phys), 8, 1, nil),
    u32_phys,
    LJ.LJStateScalar,
    LJ.LJTraceHot
)
local u32_fn = LJ.LJFunc(LJ.LJFuncId("sum_u32_vec"), nil, "sum_u32_vec", LJ.LJFuncSigId("sig:sum_u32_vec"), {
    LJ.LJParam(xs_id, "xs", ptr_u32_phys),
    LJ.LJParam(n_id, "n", i32_phys),
}, {}, { u32_vec }, LJ.LJBodyMachine(u32_vec.id, LJ.LJTerminalFirst(nil)), LJ.LJTraceHot)
local u32_compiled, u32_err, u32_src = Emit.compile_module(LJ.LJModule(nil, { u32_fn }, {}, {}, {}))
assert(u32_compiled ~= nil, tostring(u32_err) .. "\n" .. tostring(u32_src))
local u32_small = ffi.new("uint32_t[?]", 3)
u32_small[0], u32_small[1], u32_small[2] = 4294967295, 1, 2
assert(u32_compiled.sum_u32_vec(u32_small, 3) == 2)

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

io.write("moonlift luajit_emit ok\n")
