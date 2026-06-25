-- Benchmark fused Apply -> Reduce metastencils against direct reduce_n and
-- handwritten GCC C. The generated baseline C is authored through llbl.c.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local Measure = require("lalin.luajit_measure")
local C = require("llbl.c")
C.use()

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_LJ_METASTENCIL_BENCH_N") or (full and "1000000" or "120000"))
local samples = tonumber(os.getenv("LALIN_LJ_METASTENCIL_BENCH_SAMPLES") or (full and "5" or "3"))
local rounds = tonumber(os.getenv("LALIN_LJ_METASTENCIL_BENCH_ROUNDS") or (full and "3" or "2"))
local cc = os.getenv("LALIN_LJ_METASTENCIL_BENCH_CC") or os.getenv("CC") or "gcc"
local gcc_cflags = os.getenv("LALIN_LJ_METASTENCIL_BENCH_GCC_CFLAGS") or "-std=gnu99 -O3 -march=native"
local mc_cflags = os.getenv("LALIN_LJ_METASTENCIL_BENCH_MC_CFLAGS")
    or "-std=gnu99 -O3 -march=native -fno-builtin -fno-builtin-memmove -fno-builtin-memcpy -fno-builtin-memset -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function exec_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function make_context()
    local T = pvm.context()
    Schema(T)
    return T
end

local T = make_context()
local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Graph = T.LalinGraph
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local Meta = require("lalin.stencil_metastencil")(T)
local MC = require("lalin.copy_patch_mc")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function reduction(kind, init)
    local domain = Flow.FlowDomainLoop(Graph.GraphLoopId("loop:bench_meta_reduce"))
    return Value.ReductionFact(
        Value.AlgebraFactId("reduction:bench_meta_reduce"),
        domain,
        Code.CodeValueId("v:acc"),
        kind,
        iconst(init),
        Value.ValueExprValue(Code.CodeValueId("v:item")),
        i32,
        sem,
        nil,
        Value.AlgebraProofFlow(domain, "metastencil fused reduce benchmark")
    )
end

local function bin(op, left, right)
    return Plan.apply_binary_expr(op, left, right, i32, { int_semantics = sem })
end

local inputs = {
    { name = "x1", ty = i32 },
    { name = "x2", ty = i32 },
    { name = "x3", ty = i32 },
    { name = "x4", ty = i32 },
}

local expr =
    bin(
        Stencil.StencilBinaryAdd,
        bin(Stencil.StencilBinaryMul, Plan.input_expr("x1"), Plan.input_expr("x2")),
        bin(Stencil.StencilBinarySub, Plan.input_expr("x3"), Plan.input_expr("x4"))
    )

local apply4 = Plan.apply_n_array_artifact({
    tag = "bench_meta4",
    result_ty = i32,
    inputs = inputs,
    expr = expr,
    step_num = 1,
})

local reduce1 = Plan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
})

local direct_reduce4 = Plan.reduce_n_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    tag = "bench_direct4",
    item_ty = i32,
    result_ty = i32,
    inputs = inputs,
    expr = expr,
    step_num = 1,
})

local apply_node = Meta.node_from_artifact("apply", apply4)
local reduce_node = Meta.node_from_artifact("reduce", reduce1)
local external_ports = {}
local wires = {}
for _, input in ipairs(inputs) do
    external_ports[#external_ports + 1] = Meta.external_port(input.name, Stencil.StencilMetastencilPortInput, input.ty)
    wires[#wires + 1] = Meta.wire("w:" .. input.name .. ":apply", nil, input.name, "apply", input.name, input.ty)
end
wires[#wires + 1] = Meta.wire("w:apply:reduce", "apply", "dst", "reduce", "xs", i32)

local cover = Meta.descriptor(
    "meta:bench_apply4_reduce",
    external_ports,
    { apply_node, reduce_node },
    wires,
    reduce1.instance.abi
)
local selection = Meta.select_longest_legal_cover({ cover })

local function realize_mc(artifacts, stem)
    local bank, bank_err, source = MC.build_mc_bank(artifacts, {
        stem = stem,
        cc = cc,
        cflags = mc_cflags,
    })
    assert(bank, tostring(bank_err) .. "\n" .. tostring(source))
    local realization, realize_err = MC.realize_mc_artifacts(artifacts, { mc_bank = bank })
    assert(realization, tostring(realize_err))
    return bank, realization
end

local fused_bank, fused_mc = realize_mc({ selection }, "bench_luajit_metastencil_fused_reduce")
local direct_bank, direct_mc = realize_mc({ direct_reduce4 }, "bench_luajit_metastencil_direct_reduce")

assert(#fused_bank.entries == 1, "selected Apply -> Reduce cover should become one fused MC entry")
assert(Plan.artifact_shape(fused_bank.entries[1].artifact).kind == "reduce_n_array", "fused cover should lower to reduce_n_array")
assert(#fused_bank.metastencil_covers == 1, "fused MC bank should preserve typed selected-cover metadata")

local fused_symbol = fused_bank.entries[1].artifact.symbol.text
local direct_symbol = direct_bank.entries[1].artifact.symbol.text
local fused_fn = assert(fused_mc.symbols[fused_symbol])
local direct_fn = assert(direct_mc.symbols[direct_symbol])

os.execute("mkdir -p target/luajit_bench")
local c_path = "target/luajit_bench/metastencil_fused_reduce_baseline.c"
local so_path = "target/luajit_bench/metastencil_fused_reduce_baseline.so"

local baseline = C.unit. metastencil_fused_reduce_baseline {
    C.include "stdint.h",

    C.fn. gcc_meta_apply_reduce4 {
        x1 [C.restrict [C.ptr [C.const [C.i32]]]],
        x2 [C.restrict [C.ptr [C.const [C.i32]]]],
        x3 [C.restrict [C.ptr [C.const [C.i32]]]],
        x4 [C.restrict [C.ptr [C.const [C.i32]]]],
        start [C.i32],
        stop [C.i32],
        init [C.i32],
    } [C.i32] {
        C.decl. acc [C.u32] (C.cast [C.u32] (init)),
        C.for_ { C.decl. i [C.i32] (start), C.lt(i, stop), C.assign(i, i + 1) } {
            C.decl. item [C.u32] (
                C.cast [C.u32] (
                    (C.cast [C.u32] (x1[i]) * C.cast [C.u32] (x2[i]))
                    + (C.cast [C.u32] (x3[i]) - C.cast [C.u32] (x4[i]))
                )
            ),
            C.assign(acc, acc + item),
        },
        C.return_ (C.cast [C.i32] (acc)),
    },
}

write_file(c_path, C.emit_unit(baseline, { dialect = "gnu99" }))
local cmd = table.concat({ shell_quote(cc), gcc_cflags, "-fPIC -shared", shell_quote(c_path), "-o", shell_quote(so_path) }, " ")
assert(exec_ok(cmd), "GCC baseline failed: " .. cmd)

ffi.cdef([[
int32_t gcc_meta_apply_reduce4(
    const int32_t *x1,
    const int32_t *x2,
    const int32_t *x3,
    const int32_t *x4,
    int32_t start,
    int32_t stop,
    int32_t init);
]])
local gcc = ffi.load(so_path)

local x1_buf = ffi.new("int32_t[?]", n)
local x2_buf = ffi.new("int32_t[?]", n)
local x3_buf = ffi.new("int32_t[?]", n)
local x4_buf = ffi.new("int32_t[?]", n)
for i = 0, n - 1 do
    x1_buf[i] = (i % 97) - 48
    x2_buf[i] = (i % 31) - 15
    x3_buf[i] = (i % 53) + 7
    x4_buf[i] = (i % 19) - 9
end

local fused_result = fused_fn(x1_buf, x2_buf, x3_buf, x4_buf, 0, n, 0)
local direct_result = direct_fn(x1_buf, x2_buf, x3_buf, x4_buf, 0, n, 0)
local gcc_result = gcc.gcc_meta_apply_reduce4(x1_buf, x2_buf, x3_buf, x4_buf, 0, n, 0)
assert(fused_result == direct_result, "fused MC result disagrees with direct reduce_n")
assert(fused_result == gcc_result, "fused MC result disagrees with handwritten GCC baseline")

local cases = {
    { name = "mc fused Apply->Reduce", fn = function() return fused_fn(x1_buf, x2_buf, x3_buf, x4_buf, 0, n, 0) end },
    { name = "mc direct reduce_n", fn = function() return direct_fn(x1_buf, x2_buf, x3_buf, x4_buf, 0, n, 0) end },
    { name = "gcc -O3 handwritten", fn = function() return gcc.gcc_meta_apply_reduce4(x1_buf, x2_buf, x3_buf, x4_buf, 0, n, 0) end },
}

print(string.format(
    "LuaJIT metastencil fused-reduce benchmark mode=%s n=%d samples=%d rounds=%d",
    mode,
    n,
    samples,
    rounds
))
print(string.format(
    "fused_entries=%d direct_entries=%d result=%s",
    #fused_bank.entries,
    #direct_bank.entries,
    tostring(fused_result)
))
for _, result in ipairs(Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do
    print(Measure.format_result(result))
end
