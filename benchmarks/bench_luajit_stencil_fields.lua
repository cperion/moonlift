-- Benchmark AoS field-projection stencils against raw artifacts and direct GCC loops.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local Measure = require("lalin.luajit_measure")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Host = T.LalinHost
local LJ = T.LalinLuaJIT
local Sem = T.LalinSem
local Stencil = T.LalinStencil
local Ty = T.LalinType
local Value = T.LalinValue

local Lower = require("lalin.luajit_lower")(T)
local Emit = require("lalin.luajit_emit")(T)
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local CopyPatchMC = require("lalin.copy_patch_mc")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_LJ_FIELD_STENCIL_BENCH_N") or (full and "1000000" or "120000"))
local samples = tonumber(os.getenv("LALIN_LJ_FIELD_STENCIL_BENCH_SAMPLES") or (full and "5" or "3"))
local rounds = tonumber(os.getenv("LALIN_LJ_FIELD_STENCIL_BENCH_ROUNDS") or (full and "3" or "2"))
local cc = os.getenv("LALIN_LJ_FIELD_STENCIL_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("LALIN_LJ_FIELD_STENCIL_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"

local function stencil_object_cflags()
    return cflags .. " -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
end

local function compile_artifacts(artifacts, opts)
    opts = opts or {}
    opts.cc = opts.cc or cc
    opts.cflags = opts.cflags or stencil_object_cflags()
    local bank, bank_err, source = CopyPatchMC.build_mc_bank(artifacts, opts)
    if bank == nil then return nil, bank_err, source end
    local realization, realize_err = CopyPatchMC.realize_mc_artifacts(artifacts, {
        mc_bank = bank,
        preamble = opts.preamble,
        ffi_preamble = opts.ffi_preamble,
    })
    if realization == nil then return nil, realize_err, source end
    return { kind = "MCStencilBenchmarkBuild", bank = bank, realization = realization, symbols = realization.symbols, source = source }, nil, source
end

local origin = Code.CodeOriginGenerated("bench_luajit_stencil_fields")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ty_i32 = Ty.TScalar(Core.ScalarI32)
local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local ptr_pair = Code.CodeTyDataPtr(pair_ty)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_i32 = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)
local right_field = Sem.FieldByOffset("right", 4, ty_i32, Host.HostRepScalar(Core.ScalarI32))
local preamble = "typedef struct { int32_t left; int32_t right; } Demo_Pair;"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end

local function pair_right_place(base, index)
    local item = Code.CodePlaceIndex(Code.CodePlaceDeref(base, pair_ty, 4), index, pair_ty, 8)
    return Code.CodePlaceField(item, right_field, i32, 4, 4, 4)
end

local function i32_place(base, index)
    return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4)
end

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local function reduction(kind, init)
    return {
        kind = kind,
        init = iconst(init),
        int_semantics = sem,
        float_mode = nil,
    }
end

local function field_topology()
    return Stencil.StencilTopologyFieldProjection(
        Stencil.StencilTopologyContiguous(1),
        pair_ty,
        "right",
        4
    )
end

local function build_lowered_module()
    local xs = param("xs", ptr_pair)
    local dst = param("dst", ptr_i32)
    local nparam = param("n", i32)

    local zero = Code.CodeValueId("v:zero")
    local one = Code.CodeValueId("v:one")
    local i = Code.CodeValueId("v:i")
    local acc = Code.CodeValueId("v:acc")
    local cond = Code.CodeValueId("v:cond")
    local item = Code.CodeValueId("v:item")
    local next_i = Code.CodeValueId("v:next_i")
    local next_acc = Code.CodeValueId("v:next_acc")
    local out = Code.CodeValueId("v:out")

    local sum_entry_id = Code.CodeBlockId("block:sum_pair_right:entry")
    local sum_header_id = Code.CodeBlockId("block:sum_pair_right:header")
    local sum_body_id = Code.CodeBlockId("block:sum_pair_right:body")
    local sum_exit_id = Code.CodeBlockId("block:sum_pair_right:exit")
    local sum_sig_id = Code.CodeSigId("sig:sum_pair_right")
    local sum_func_id = Code.CodeFuncId("fn:sum_pair_right")

    local sum_entry = Code.CodeBlock(sum_entry_id, "entry", {}, {
        inst("sum:zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst("sum:one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term("sum:entry", Code.CodeTermJump(sum_header_id, { zero, zero })), origin)
    local sum_header = Code.CodeBlock(sum_header_id, "header", {
        Code.CodeParam(i, "i", i32, origin),
        Code.CodeParam(acc, "acc", i32, origin),
    }, {
        inst("sum:cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, nparam.value)),
    }, term("sum:header", Code.CodeTermBranch(cond, sum_body_id, {}, sum_exit_id, { acc })), origin)
    local sum_body = Code.CodeBlock(sum_body_id, "body", {}, {
        inst("sum:load", Code.CodeInstLoad(item, pair_right_place(xs.value, i), read_i32)),
        inst("sum:add", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
        inst("sum:inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
    }, term("sum:body", Code.CodeTermJump(sum_header_id, { next_i, next_acc })), origin)
    local sum_exit = Code.CodeBlock(sum_exit_id, "exit", {
        Code.CodeParam(out, "out", i32, origin),
    }, {}, term("sum:exit", Code.CodeTermReturn({ out })), origin)
    local sum_func = Code.CodeFunc(sum_func_id, "sum_pair_right", Code.CodeLinkageExport, sum_sig_id, { xs, nparam }, {}, sum_entry_id, {
        sum_entry,
        sum_header,
        sum_body,
        sum_exit,
    }, origin)

    local mi = Code.CodeValueId("v:map_i")
    local mcond = Code.CodeValueId("v:map_cond")
    local mitem = Code.CodeValueId("v:map_item")
    local mneg = Code.CodeValueId("v:map_neg")
    local mnext_i = Code.CodeValueId("v:map_next_i")
    local map_entry_id = Code.CodeBlockId("block:neg_pair_right:entry")
    local map_header_id = Code.CodeBlockId("block:neg_pair_right:header")
    local map_body_id = Code.CodeBlockId("block:neg_pair_right:body")
    local map_exit_id = Code.CodeBlockId("block:neg_pair_right:exit")
    local map_sig_id = Code.CodeSigId("sig:neg_pair_right")
    local map_func_id = Code.CodeFuncId("fn:neg_pair_right")

    local map_entry = Code.CodeBlock(map_entry_id, "entry", {}, {
        inst("map:zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst("map:one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term("map:entry", Code.CodeTermJump(map_header_id, { zero })), origin)
    local map_header = Code.CodeBlock(map_header_id, "header", {
        Code.CodeParam(mi, "i", i32, origin),
    }, {
        inst("map:cond", Code.CodeInstCompare(mcond, Core.CmpLt, i32, mi, nparam.value)),
    }, term("map:header", Code.CodeTermBranch(mcond, map_body_id, {}, map_exit_id, {})), origin)
    local map_body = Code.CodeBlock(map_body_id, "body", {}, {
        inst("map:load", Code.CodeInstLoad(mitem, pair_right_place(xs.value, mi), read_i32)),
        inst("map:neg", Code.CodeInstUnary(mneg, Core.UnaryNeg, i32, mitem)),
        inst("map:store", Code.CodeInstStore(i32_place(dst.value, mi), mneg, write_i32)),
        inst("map:inc", Code.CodeInstBinary(mnext_i, Core.BinAdd, i32, sem, mi, one)),
    }, term("map:body", Code.CodeTermJump(map_header_id, { mnext_i })), origin)
    local map_exit = Code.CodeBlock(map_exit_id, "exit", {}, {}, term("map:exit", Code.CodeTermReturn({})), origin)
    local map_func = Code.CodeFunc(map_func_id, "neg_pair_right", Code.CodeLinkageExport, map_sig_id, { dst, xs, nparam }, {}, map_entry_id, {
        map_entry,
        map_header,
        map_body,
        map_exit,
    }, origin)

    local module = Code.CodeModule(Code.CodeModuleId("module:bench_stencil_fields"), {
        Code.CodeSig(sum_sig_id, { ptr_pair, i32 }, { i32 }),
        Code.CodeSig(map_sig_id, { ptr_i32, ptr_pair, i32 }, {}),
    }, {}, {}, {}, {}, { sum_func, map_func }, origin)
    local contracts = Code.CodeContractFactSet(module.id, {
        Code.CodeFuncContractFact(sum_func_id, Code.CodeContractBounds(xs.value, nparam.value), origin),
        Code.CodeFuncContractFact(sum_func_id, Code.CodeContractReadonly(xs.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractBounds(dst.value, nparam.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractWriteonly(dst.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractBounds(xs.value, nparam.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractReadonly(xs.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractDisjoint(dst.value, xs.value), origin),
    })
    return module, contracts
end

local raw_reduce = StencilArtifactPlan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
    array_topology = field_topology(),
})
local raw_map = StencilArtifactPlan.map_array_artifact(Stencil.StencilUnaryNeg, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
    src_topology = field_topology(),
})

local module, contracts = build_lowered_module()
local lowered_artifacts = {}
local lj_module = Lower.lower_module(module, {
    contracts = contracts,
    stencil_reduce_artifact_for = function(_func, vocab, _op, reduction_, plan, info)
        assert(vocab == Stencil.StencilReduce)
        local artifact = StencilArtifactPlan.reduce_array_artifact(reduction_, plan, info)
        lowered_artifacts[#lowered_artifacts + 1] = artifact
        return artifact
    end,
    stencil_store_artifact_for = function(_func, vocab, op, _plan, info)
        assert(vocab == Stencil.StencilMap)
        local artifact = StencilArtifactPlan.map_array_artifact(op, info)
        lowered_artifacts[#lowered_artifacts + 1] = artifact
        return artifact
    end,
})
assert(pvm.classof(lj_module.funcs[1].body) == LJ.LJBodyMachine)
assert(pvm.classof(lj_module.funcs[2].body) == LJ.LJBodyMachine)

local artifact_build, artifact_err, artifact_src = compile_artifacts({
    raw_reduce,
    raw_map,
    lowered_artifacts[1],
    lowered_artifacts[2],
}, {
    stem = "bench_luajit_stencil_fields",
    preamble = preamble,
    cc = cc,
    cflags = stencil_object_cflags(),
})
assert(artifact_build ~= nil, tostring(artifact_err) .. "\n" .. tostring(artifact_src))

local compiled, emit_err, emit_src = Emit.compile_module(lj_module, {
    chunk_name = "bench_luajit_stencil_fields",
    stencil_symbols = artifact_build.symbols,
})
assert(compiled ~= nil, tostring(emit_err) .. "\n" .. tostring(emit_src))

os.execute("mkdir -p target/luajit_bench")
local c_path = "target/luajit_bench/stencil_fields_baseline.c"
local so_path = "target/luajit_bench/stencil_fields_baseline.so"
write_file(c_path, [=[
#include <stdint.h>

typedef struct { int32_t left; int32_t right; } Demo_Pair;

int32_t gcc_sum_pair_right(const Demo_Pair *xs, int32_t n) {
    uint32_t acc = 0;
    for (int32_t i = 0; i < n; i++) acc = (uint32_t)(acc + (uint32_t)xs[i].right);
    return (int32_t)acc;
}

void gcc_neg_pair_right(int32_t *dst, const Demo_Pair *xs, int32_t n) {
    for (int32_t i = 0; i < n; i++) dst[i] = -xs[i].right;
}
]=])
local cmd = table.concat({ shell_quote(cc), cflags, "-fPIC -shared", shell_quote(c_path), "-o", shell_quote(so_path) }, " ")
local ok = os.execute(cmd)
assert(ok == true or ok == 0, "gcc baseline failed: " .. cmd)
ffi.cdef([[
int32_t gcc_sum_pair_right(const Demo_Pair *xs, int32_t n);
void gcc_neg_pair_right(int32_t *dst, const Demo_Pair *xs, int32_t n);
]])
local gcc = ffi.load(so_path)

local xs = ffi.new("Demo_Pair[?]", n)
local out = ffi.new("int32_t[?]", n)
local mid = math.floor(n / 2)
for i = 0, n - 1 do
    xs[i].left = i
    xs[i].right = (i % 97) - 48
    out[i] = 0
end

local function sym(artifact)
    return assert(artifact_build.symbols[artifact.symbol.text], artifact.symbol.text)
end

local raw_reduce_fn = sym(raw_reduce)
local raw_map_fn = sym(raw_map)

local cases = {
    { name = "lowered field reduce", fn = function() return compiled.sum_pair_right(xs, n) end },
    { name = "raw field reduce", fn = function() return raw_reduce_fn(xs, 0, n, 0) end },
    { name = "gcc field reduce", fn = function() return gcc.gcc_sum_pair_right(xs, n) end },
    { name = "lowered field map", fn = function() compiled.neg_pair_right(out, xs, n); return out[mid] end },
    { name = "raw field map", fn = function() raw_map_fn(out, xs, 0, n); return out[mid] end },
    { name = "gcc field map", fn = function() gcc.gcc_neg_pair_right(out, xs, n); return out[mid] end },
}

print(string.format("LuaJIT AoS field stencil benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
for _, result in ipairs(Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do
    print(Measure.format_result(result))
end
